import SwiftUI
import AppKit
import SwiftTerm

struct MacTerminalScreen: View {
    @ObservedObject var session: TerminalSession
    let showSettings: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(session.host.name).font(.headline)
                Text(session.status).foregroundStyle(.secondary)
                Spacer()
                Menu("tmux") {
                    Text(session.bindingsStatus)
                    if let prefix = session.prefixBytes { Button("Send prefix") { session.send(prefix) }.disabled(!session.isLive) }
                    ForEach(session.bindings?.shortcuts ?? []) { shortcut in Button(shortcut.title + " · " + shortcut.keys) { session.send(shortcut.bytes) }.disabled(!session.isLive) }
                    Button("Refresh shortcuts") { Task { await session.refreshBindings() } }.disabled(!session.isLive)
                }.fixedSize()
                Button("Host settings", action: showSettings)
                Button("Disconnect") { session.disconnect() }.disabled(!session.isLive && !session.isConnecting)
            }.padding(12)
            if !session.isLive {
                VStack(alignment: .leading, spacing: 10) {
                    if let error = session.error { Text(error).textSelection(.enabled) }
                    if session.pendingFingerprint != nil {
                        Button(session.changedFingerprint ? "I verified the new fingerprint — update trust" : "Trust this fingerprint and connect") { session.trustAndConnect() }
                    } else if !session.isConnecting {
                        if session.showingPassphrase { SecureField("Key passphrase", text: $session.passphrase).frame(maxWidth: 300) }
                        Button("Connect") { session.connect() }
                    } else { ProgressView() }
                }.padding().frame(maxWidth: .infinity, alignment: .leading)
            }
            MacTerminalContainer(session: session)
        }.task { if !session.hasStarted { session.connect() } }
    }
}

private struct MacTerminalContainer: NSViewControllerRepresentable {
    let session: TerminalSession
    func makeNSViewController(context: Context) -> TerminalCoordinator {
        let controller = TerminalCoordinator(session: session); session.coordinator = controller; return controller
    }
    func updateNSViewController(_ controller: TerminalCoordinator, context: Context) {}
}

@MainActor final class TerminalCoordinator: NSViewController, @preconcurrency TerminalViewDelegate {
    weak var session: TerminalSession?
    let terminal: TerminalView
    init(session: TerminalSession) { self.session = session; terminal = session.terminal; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func loadView() {
        view = NSView(); terminal.removeFromSuperview(); terminal.terminalDelegate = self
        terminal.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(terminal)
        NSLayoutConstraint.activate([terminal.topAnchor.constraint(equalTo: view.topAnchor), terminal.bottomAnchor.constraint(equalTo: view.bottomAnchor), terminal.leadingAnchor.constraint(equalTo: view.leadingAnchor), terminal.trailingAnchor.constraint(equalTo: view.trailingAnchor)])
        (terminal as? SafeTerminalView)?.approvePaste = { [weak self] text, insert in
            guard let self, let session = self.session, session.isLive, let window = self.view.window else { return }
            let alert = NSAlert(); alert.messageText = "Paste into " + session.host.name + "?"
            alert.informativeText = "This text includes line breaks or control characters.\n\n" + String(text.prefix(300)).replacingOccurrences(of: "\u{1b}", with: "␛")
            alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Paste")
            alert.beginSheetModal(for: window) { [weak session] response in if response == .alertSecondButtonReturn, session?.isLive == true { insert() } }
        }
    }
    override func viewDidAppear() { super.viewDidAppear(); view.window?.makeFirstResponder(terminal) }
    func refreshMenu() {}
    func send(source: TerminalView, data: ArraySlice<UInt8>) { session?.send(Data(data)) }
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) { session?.connection?.resize(columns: newCols, rows: newRows) }
    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func scrolled(source: TerminalView, position: Double) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        guard let url = URL(string: link), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), let window = view.window else { return }
        let alert = NSAlert(); alert.messageText = "Open link?"; alert.informativeText = link
        alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Open")
        alert.beginSheetModal(for: window) { if $0 == .alertSecondButtonReturn { NSWorkspace.shared.open(url) } }
    }
    func bell(source: TerminalView) { NSSound.beep() }
}

final class SafeTerminalView: TerminalView {
    var approvePaste: ((String, @escaping () -> Void) -> Void)?
    override func paste(_ sender: Any) {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        let insert = { [weak self] in
            guard let self else { return }
            if self.getTerminal().bracketedPasteMode { self.send(txt: "\u{1b}[200~") }
            self.send(txt: text)
            if self.getTerminal().bracketedPasteMode { self.send(txt: "\u{1b}[201~") }
        }
        if text.contains("\n") || text.contains("\r") || text.contains("\u{1b}") { approvePaste?(text, insert) }
        else { insert() }
    }
}
