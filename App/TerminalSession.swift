import SwiftUI
import SwiftTerm
import TermCore

@MainActor final class TerminalSession: ObservableObject {
    let host: TermCore.Host
    var id: UUID { host.id }
    let terminal: TerminalView
    weak var store: AppStore?
    @Published var status = "Disconnected"
    @Published var isLive = false
    @Published var isConnecting = false
    @Published var error: String?
    @Published var bindings: TmuxBindings?
    @Published var bindingsStatus = "Connect to read this server’s shortcuts."
    @Published var pendingFingerprint: String?
    @Published var changedFingerprint = false
    @Published var passphrase = ""
    @Published var showingPassphrase = false
    @Published var optionAsMeta = true
    var connection: SSHConnection?
    var coordinator: TerminalCoordinator?
    private var connectTask: Task<Void, Never>?
    var hasStarted = false
    private var hasAttached = false
    private var wantsConnection = false
    private var retryCount = 0
    private var generation = UUID()

    init(host: TermCore.Host, store: AppStore) {
        self.host = host; self.store = store
        #if os(macOS)
        terminal = SafeTerminalView(frame: .zero, font: nil)
        terminal.nativeBackgroundColor = NSColor(red: 0.025, green: 0.04, blue: 0.065, alpha: 1)
        terminal.nativeForegroundColor = NSColor(white: 0.92, alpha: 1)
        terminal.setAccessibilityLabel("Terminal for \(host.name)")
        #else
        terminal = SafeTerminalView(frame: .zero)
        terminal.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        terminal.nativeBackgroundColor = UIColor(red: 0.025, green: 0.04, blue: 0.065, alpha: 1)
        terminal.nativeForegroundColor = UIColor(white: 0.92, alpha: 1)
        terminal.accessibilityLabel = "Terminal for \(host.name)"
        #endif
        terminal.caretColor = .systemMint
        terminal.allowMouseReporting = false
        applyPreferences(store.preferences)
    }
    func applyPreferences(_ value: TerminalPreferences) {
        optionAsMeta = value.optionAsMeta; terminal.optionAsMetaKey = value.optionAsMeta
        if terminal.font.pointSize != value.fontSize { terminal.font = .monospacedSystemFont(ofSize: value.fontSize, weight: .regular) }
    }
    func setOptionAsMeta(_ enabled: Bool) {
        guard var value = store?.preferences else { return }
        value.optionAsMeta = enabled; store?.savePreferences(value)
    }
    func changeFontSize(by delta: Double) {
        guard var value = store?.preferences else { return }
        value.fontSize = min(28, max(10, value.fontSize + delta)); store?.savePreferences(value)
    }
    func connect() {
        guard !isConnecting, !isLive else { return }
        hasStarted = true; wantsConnection = true; error = nil; pendingFingerprint = nil
        bindings = nil; bindingsStatus = "Reading after attachment…"
        isConnecting = true; status = host.isSSM ? "Opening AWS session…" : "Connecting…"
        generation = UUID(); let attempt = generation
        connectTask = Task {
            do {
                guard let store, let key = try store.vault.read(account: "key:" + host.keyID), !key.isEmpty else { throw ConnectionError.message("Import the SSH key named \(host.keyID).") }
                let trusted = try store.vault.read(account: "trust:" + host.trustID).flatMap { String(data: $0, encoding: .utf8) }
                let aws = try store.vault.read(account: "aws:" + host.awsProfile).map { try JSONDecoder().decode(AWSCredentials.self, from: $0) }
                let c = try await SSHConnection.open(host: host, privateKey: key, passphrase: passphrase, trustedFingerprint: trusted, aws: aws)
                guard !Task.isCancelled, generation == attempt else { c.close(); return }
                connection = c
                c.onData = { [weak self] data in Task { @MainActor in
                    guard let self, self.generation == attempt else { return }
                    self.terminal.feed(byteArray: Array(data)[...])
                } }
                c.onClose = { [weak self] reason in Task { @MainActor in
                    guard let self, self.generation == attempt else { return }
                    self.didClose(reason)
                } }
                let t = terminal.getTerminal()
                try await c.startTerminal(host: host, reconnecting: hasAttached, columns: t.cols, rows: t.rows)
                guard generation == attempt, !Task.isCancelled else { c.close(); return }
                hasAttached = true; retryCount = 0; isConnecting = false; isLive = true; status = "Connected"
                await refreshBindings()
            } catch {
                guard generation == attempt, !Task.isCancelled else { return }
                isConnecting = false; isLive = false; status = "Needs attention"; self.error = error.localizedDescription
                wantsConnection = false
                if case ConnectionError.hostKey(let fingerprint, let changed) = error { pendingFingerprint = fingerprint; changedFingerprint = changed }
                if error.localizedDescription.contains("passphrase") { showingPassphrase = true }
                let c = connection; connection = nil; generation = UUID(); c?.close()
            }
        }
    }
    func trustAndConnect() {
        guard let fingerprint = pendingFingerprint, let store else { return }
        do { try store.vault.save(Data(fingerprint.utf8), account: "trust:" + host.trustID); connect() }
        catch { self.error = error.localizedDescription }
    }
    func refreshBindings() async {
        guard isLive, let connection else { return }
        let attempt = generation
        guard !host.tmuxSession.isEmpty else { bindingsStatus = "Plain shell — no tmux shortcuts."; return }
        bindings = nil; bindingsStatus = "Reading this server’s tmux settings…"
        do {
            // A newly created tmux session may need a moment before its query channel can find it.
            try await Task.sleep(nanoseconds: 200_000_000)
            let result = try await connection.tmuxBindings(for: host)
            guard generation == attempt, isLive else { return }
            bindings = result
            bindingsStatus = "Prefix: \(result.prefix) · \(result.shortcuts.count) shortcuts"
        } catch {
            guard generation == attempt else { return }
            bindings = nil; bindingsStatus = "Detection unavailable. Use terminal keys or a manual prefix."
        }
        coordinator?.refreshMenu()
    }
    var prefixBytes: Data? { TmuxBindings.keyBytes(bindings?.prefix ?? host.manualPrefix) }
    func send(_ data: Data) { guard isLive else { return }; connection?.send(data) }
    func disconnect() {
        hasStarted = true; wantsConnection = false; generation = UUID(); connectTask?.cancel(); connectTask = nil
        connection?.close(); connection = nil
        isLive = false; isConnecting = false; status = "Disconnected"; passphrase = ""
        resetModifiers(); bindings = nil
        error = nil; pendingFingerprint = nil; changedFingerprint = false; showingPassphrase = false
        bindingsStatus = "Connect to read this server’s shortcuts."
        terminal.resignFirstResponder()
        coordinator?.closeUI(); coordinator = nil
    }
    private func didClose(_ reason: String?) {
        connection = nil; isLive = false; isConnecting = false; bindings = nil
        resetModifiers()
        status = reason == nil ? "Session ended" : "Connection lost"; error = reason
        coordinator?.refreshMenu()
        guard wantsConnection, reason != nil, retryCount < 3, !host.tmuxSession.isEmpty else { return }
        retryCount += 1; let attempt = generation, delay = UInt64(1 << retryCount)
        status = "Reconnecting in \(delay)s…"
        connectTask = Task { try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            guard !Task.isCancelled, generation == attempt, wantsConnection else { return }; connect()
        }
    }
    func resume() {
        guard wantsConnection else { return }
        if !isLive && !isConnecting { connect() }
        else if let connection {
            let attempt = generation
            Task {
                do { _ = try await connection.execute("true") }
                catch {
                    guard generation == attempt, wantsConnection else { return }
                    disconnectForNetworkLoss()
                }
            }
        }
    }
    private func disconnectForNetworkLoss() {
        generation = UUID(); connection?.close(); connection = nil
        didClose("Connection lost while the app was inactive.")
    }
    private func resetModifiers() {
        #if os(iOS)
        terminal.controlModifier = false; terminal.metaModifier = false
        #endif
    }
}
