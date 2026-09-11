import SwiftUI
import SwiftTerm
import TermCore

@MainActor final class TerminalSession: ObservableObject {
    @Published private(set) var host: TermCore.Host
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
    @Published var keyboardVisible = false
    @Published var selectingTmux = false
    @Published private(set) var availableTmuxSessions: [String] = []
    @Published private(set) var tmuxAvailable = false
    @Published private(set) var tmuxDiscoveryMessage = ""
    @Published private(set) var tmuxSelectionError: String?
    private var tmuxSelectionContinuation: CheckedContinuation<TmuxSelection, Error>?
    struct TmuxSelection { let name: String; let create: Bool }
    var connection: SSHConnection?
    var coordinator: TerminalCoordinator?
    private var connectTask: Task<Void, Never>?
    var hasStarted = false
    @Published private var wantsConnection = false
    var canDisconnect: Bool { isLive || isConnecting || wantsConnection }
    private var retryCount = 0
    private var generation = UUID()
    private var terminalStyle: UIUserInterfaceStyle?
    private var requestedLandscape = false
    private var previousOrientation: UIInterfaceOrientation?
    private weak var orientationScene: UIWindowScene?

    init(host: TermCore.Host, store: AppStore) {
        self.host = host; self.store = store
        terminal = SafeTerminalView(frame: .zero)
        terminal.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        terminal.accessibilityLabel = "Terminal for \(host.name)"
        terminal.allowMouseReporting = false
        terminal.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { [weak self] (_: TerminalView, _: UITraitCollection) in
            self?.updateTerminalColors()
        }
        applyPreferences(store.preferences)
    }
    func applyPreferences(_ value: TerminalPreferences) {
        optionAsMeta = value.optionAsMeta; terminal.optionAsMetaKey = value.optionAsMeta
        switch value.appearance {
        case .system: terminal.overrideUserInterfaceStyle = .unspecified
        case .light: terminal.overrideUserInterfaceStyle = .light
        case .dark: terminal.overrideUserInterfaceStyle = .dark
        }
        updateTerminalColors()
        if terminal.font.pointSize != value.fontSize { terminal.font = .monospacedSystemFont(ofSize: value.fontSize, weight: .regular) }
    }
    func updateTerminalColors() {
        let style: UIUserInterfaceStyle = terminal.traitCollection.userInterfaceStyle == .dark ? .dark : .light
        guard terminalStyle != style else { return }
        terminalStyle = style
        let traits = UITraitCollection(userInterfaceStyle: style)
        terminal.nativeBackgroundColor = UIColor.systemBackground.resolvedColor(with: traits)
        terminal.nativeForegroundColor = UIColor.label.resolvedColor(with: traits)
        terminal.caretColor = UIColor.systemTeal.resolvedColor(with: traits)
        terminal.caretTextColor = terminal.nativeBackgroundColor
        coordinator?.viewIfLoaded?.backgroundColor = terminal.nativeBackgroundColor
        terminal.keyboardAppearance = style == .dark ? .dark : .light
        if terminal.isFirstResponder { terminal.reloadInputViews() }
        terminal.setNeedsDisplay()
    }
    func requestInitialLandscape(in window: UIWindow) {
        guard !requestedLandscape, isLive, let scene = window.windowScene,
              scene.traitCollection.userInterfaceIdiom == .phone else { return }
        requestedLandscape = true
        previousOrientation = scene.effectiveGeometry.interfaceOrientation
        orientationScene = scene
        window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        // SwiftUI can rebuild the terminal controller when a large iPhone rotates.
        // Keep this request with the session and wait until the view update ends.
        let request: @MainActor () -> Void = { [weak self, weak scene] in
            DispatchQueue.main.async {
                guard let self, let scene, self.isLive else { return }
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape)) { error in
                    NSLog("Terminal orientation request: %@", error.localizedDescription)
                }
            }
        }
        if let transition = coordinator?.transitionCoordinator,
           transition.animate(alongsideTransition: nil, completion: { _ in request() }) { return }
        request()
    }
    private func restoreOrientation() {
        guard let scene = orientationScene, let previousOrientation else { return }
        orientationScene = nil; self.previousOrientation = nil
        guard previousOrientation != .unknown else { return }
        let mask = UIInterfaceOrientationMask(rawValue: 1 << previousOrientation.rawValue)
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
            NSLog("Terminal orientation restore: %@", error.localizedDescription)
        }
    }
    func showKeyboard() {
        // iPad can hide its floating keyboard while keeping input focus.
        if terminal.isFirstResponder { terminal.resignFirstResponder() }
        terminal.becomeFirstResponder()
    }
    func hideKeyboard() {
        terminal.resignFirstResponder()
        keyboardVisible = false
        resetModifiers()
        coordinator?.stopRepeat()
        coordinator?.refreshMenu()
    }
    func toggleKeyboard() { if keyboardVisible { hideKeyboard() } else { showKeyboard() } }
    func setOptionAsMeta(_ enabled: Bool) {
        guard var value = store?.preferences else { return }
        value.optionAsMeta = enabled; store?.savePreferences(value)
    }
    func changeFontSize(by delta: Double) {
        guard var value = store?.preferences else { return }
        value.fontSize = min(28, max(10, value.fontSize + delta)); store?.savePreferences(value)
    }
    func connect(forceSessionSelection: Bool = false) {
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
                let attachOnly = try await prepareTmuxSession(using: c, forceSelection: forceSessionSelection)
                guard generation == attempt, !Task.isCancelled else { c.close(); return }
                let t = terminal.getTerminal()
                try await c.startTerminal(host: host, reconnecting: attachOnly, columns: t.cols, rows: t.rows)
                guard generation == attempt, !Task.isCancelled else { c.close(); return }
                retryCount = 0; isConnecting = false; isLive = true; status = "Connected"
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
    private func prepareTmuxSession(using connection: SSHConnection, forceSelection: Bool) async throws -> Bool {
        if !forceSelection {
            if host.tmuxSession.isEmpty && host.tmuxSelectionMade == true { return false }
        }
        status = "Reading tmux sessions…"
        availableTmuxSessions = []; tmuxAvailable = false; tmuxSelectionError = nil
        do {
            let listing = try await connection.tmuxSessions(for: host)
            try Task.checkCancellation()
            availableTmuxSessions = listing.names; tmuxAvailable = listing.isAvailable
            tmuxDiscoveryMessage = listing.isAvailable ? (listing.names.isEmpty ? "No tmux sessions were listed. Create one or open a plain shell." : "Choose a session for this host entry.") : "tmux is not available in this server’s PATH. You can open a plain shell."
        } catch {
            try Task.checkCancellation()
            tmuxDiscoveryMessage = "Cannot list tmux sessions. You can cancel and retry, or open a plain shell."
        }
        guard self.connection === connection, wantsConnection else { throw ConnectionError.message("The connection ended while reading tmux sessions.") }
        if !forceSelection, !host.tmuxSession.isEmpty, availableTmuxSessions.contains(host.tmuxSession) { return true }
        if tmuxAvailable, !host.tmuxSession.isEmpty, !availableTmuxSessions.contains(host.tmuxSession) {
            tmuxDiscoveryMessage = "The saved session was not listed. Choose another session, create one, or open a plain shell."
        }
        let choice = try await requestTmuxSelection()
        try Task.checkCancellation()
        guard let store, var saved = store.hosts.first(where: { $0.id == host.id }) else {
            throw ConnectionError.message("This host was removed while choosing a session.")
        }
        saved.tmuxSession = choice.name; saved.tmuxSelectionMade = true
        try store.save(saved)
        // Keep the connected endpoint even if another device edited the host during selection.
        host.tmuxSession = choice.name; host.tmuxSelectionMade = true
        return !choice.create && !choice.name.isEmpty
    }
    func requestTmuxSelection() async throws -> TmuxSelection {
        try Task.checkCancellation()
        status = "Choose a session"
        return try await withCheckedThrowingContinuation { continuation in
            tmuxSelectionContinuation = continuation; selectingTmux = true
        }
    }
    func selectTmuxSession(_ name: String, create: Bool = false) {
        guard let pending = tmuxSelectionContinuation else { return }
        do {
            var candidate = host; candidate.tmuxSession = name; try candidate.validate()
            if create && !tmuxAvailable { throw ConnectionError.message("tmux is not available for session creation.") }
            tmuxSelectionContinuation = nil; selectingTmux = false
            pending.resume(returning: TmuxSelection(name: name, create: create))
        } catch { tmuxSelectionError = error.localizedDescription }
    }
    func cancelTmuxSelection() {
        guard tmuxSelectionContinuation != nil else { return }
        if let store { store.closeSession(id) } else { disconnect() }
    }
    func chooseAnotherTmuxSession() {
        disconnect(closeUI: false)
        connect(forceSessionSelection: true)
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
    func disconnect(closeUI: Bool = true) {
        hasStarted = true; wantsConnection = false; generation = UUID(); connectTask?.cancel(); connectTask = nil
        let pending = tmuxSelectionContinuation; tmuxSelectionContinuation = nil; selectingTmux = false
        pending?.resume(throwing: CancellationError())
        connection?.close(); connection = nil
        isLive = false; isConnecting = false; status = "Disconnected"; passphrase = ""
        resetModifiers(); bindings = nil
        error = nil; pendingFingerprint = nil; changedFingerprint = false; showingPassphrase = false
        bindingsStatus = "Connect to read this server’s shortcuts."
        if closeUI {
            keyboardVisible = false
            restoreOrientation()
            terminal.resignFirstResponder()
            coordinator?.closeUI(); coordinator = nil
        } else { coordinator?.refreshMenu() }
    }
    private func didClose(_ reason: String?) {
        connection = nil; isLive = false; isConnecting = false; bindings = nil
        let pending = tmuxSelectionContinuation; tmuxSelectionContinuation = nil; selectingTmux = false
        pending?.resume(throwing: ConnectionError.message(reason ?? "The connection ended while choosing a session."))
        if pending != nil { wantsConnection = false }
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
