import SwiftUI
import SwiftTerm
import TermCore

struct TerminalScreen: View {
    @ObservedObject var session: TerminalSession
    let onDisconnect: () -> Void
    var tabCount = 1
    var showSessions: (() -> Void)?
    var body: some View {
        TerminalContainer(session: session, showSessions: showSessions)
            .ignoresSafeArea(.keyboard)
            .allowsHitTesting(session.isLive)
            .accessibilityHidden(!session.isLive)
            .overlay {
                if !session.isLive { ConnectionOverlay(session: session) }
            }
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .leading) {
            if !session.isLive || !session.floatingKeysVisible {
                Button("Hosts and sessions", systemImage: "sidebar.left") { showSessions?() }
                    .accessibilityIdentifier("terminal.sessions")
                    .labelStyle(.iconOnly)
                    .buttonStyle(SideControlButtonStyle())
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .padding(.leading, 4)
            }
        }
        .overlay(alignment: .topTrailing) {
            if session.isResizingPanes {
                HStack {
                    if session.isPreparingPaneResize { ProgressView().accessibilityLabel("Reading pane borders") }
                    Button("Done resizing") { session.finishPaneResize() }
                        .accessibilityIdentifier("terminal.pane.resize.done")
                }.padding(12).background(.regularMaterial, in: Capsule()).padding(8)
            }
        }
        .sheet(isPresented: $session.selectingTmux) { TmuxSessionPicker(session: session).interactiveDismissDisabled() }
        .task { if !session.hasStarted { session.connect() } }
        .onChange(of: session.optionAsMeta) { _, value in session.terminal.optionAsMetaKey = value }
        .onDisappear { session.stopScrolling(); session.floatingKeyInput.reset(); session.terminal.controlModifier = false; session.terminal.metaModifier = false }
    }
}

private struct SideControlButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.frame(width: 44, height: 44)
            .background(configuration.isPressed ? Color.accentColor.opacity(0.2) : .clear)
            .contentShape(Rectangle())
    }
}

struct TerminalSidebarTools: View {
    @ObservedObject var session: TerminalSession
    let onDisconnect: () -> Void
    var body: some View {
        Section("Connection") {
            Button("Disconnect", systemImage: "xmark.circle") { onDisconnect() }
            Button("Previous tab", systemImage: "chevron.left") { session.store?.stepTab(for: session.host.id, by: -1) }.keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            Button("Next tab", systemImage: "chevron.right") { session.store?.stepTab(for: session.host.id, by: 1) }.keyboardShortcut(.rightArrow, modifiers: [.command, .option])
        }
        Section("Terminal") {
            Toggle("Floating keys", isOn: Binding(get: { session.floatingKeysVisible }, set: session.setFloatingKeysVisible))
                .accessibilityIdentifier("terminal.floatingKeys.toggle")
            if let message = session.scrollStatus { Text(message) }
            Button(session.keyboardVisible ? "Hide keyboard" : "Show keyboard", systemImage: "keyboard") { session.toggleKeyboard() }
            Button("Larger text", systemImage: "textformat.size.larger") { session.changeFontSize(by: 1) }
            Button("Smaller text", systemImage: "textformat.size.smaller") { session.changeFontSize(by: -1) }
            Toggle("Option as Meta", isOn: Binding(get: { session.optionAsMeta }, set: { session.setOptionAsMeta($0) }))
        }
        if !session.host.tmuxSession.isEmpty {
            DisclosureGroup("tmux controls") {
                Group {
                    ForEach(session.bindings?.shortcuts ?? []) { shortcut in
                        Button(shortcut.title + " · " + shortcut.keys) { session.send(shortcut.bytes) }
                            .disabled(!session.isLive)
                    }
                }
                Group {
                    Text("Double-tap to resize panes, then drag a border with one finger. Requires tmux mouse mode.")
                    Text(session.bindingsStatus)
                    if let prefix = session.prefixBytes {
                        Button("Send prefix") { session.send(prefix) }.disabled(!session.isLive)
                    }
                    Button("Refresh shortcuts", systemImage: "arrow.clockwise") {
                        Task { await session.refreshBindings() }
                    }.disabled(!session.isLive)
                }
            }
        }
    }
}

private struct ConnectionOverlay: View {
    @ObservedObject var session: TerminalSession
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 16) {
                    if session.isConnecting { ProgressView().accessibilityLabel("Connecting") }
                    Text(session.status).font(.headline)
                    if let error = session.error {
                        Text(error).font(.callout).textSelection(.enabled)
                    }
                    if session.pendingFingerprint != nil {
                        Button(session.changedFingerprint ? "I verified the new fingerprint — update trust" : "Trust this fingerprint and connect") {
                            session.trustAndConnect()
                        }.buttonStyle(.borderedProminent)
                    } else if !session.isConnecting {
                        if session.showingPassphrase {
                            SecureField("Key passphrase", text: $session.passphrase)
                                .textFieldStyle(.roundedBorder)
                        }
                        Button("Connect", systemImage: "bolt") { session.connect() }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("terminal.connect")
                    }
                }
                .multilineTextAlignment(.center)
                .padding(24)
                .frame(maxWidth: 420)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                .padding(24)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
            }
            .background {
                Color(uiColor: .systemBackground)
                    .opacity(reduceTransparency ? 1 : 0.25)
                    .ignoresSafeArea()
            }
        }
        .accessibilityIdentifier("terminal.connection.overlay")
    }
}

struct TerminalContainer: UIViewControllerRepresentable {
    @ObservedObject var session: TerminalSession
    var showSessions: (() -> Void)?
    func makeUIViewController(context: Context) -> TerminalCoordinator {
        let controller = TerminalCoordinator(session: session); session.coordinator = controller
        controller.showSessions = showSessions
        return controller
    }
    func updateUIViewController(_ controller: TerminalCoordinator, context: Context) {
        controller.showSessions = showSessions
        session.updateTerminalColors()
        controller.updateKeyboardViewport()
    }
}

@MainActor final class TerminalCoordinator: UIViewController, @preconcurrency TerminalViewDelegate {
    var showSessions: (() -> Void)?
    weak var session: TerminalSession?
    let terminal: TerminalView
    private var keyboardFrame: CGRect?
    let compositionPreview = CompositionPreview()
    private(set) var keyPalette: FloatingKeyPalette!
    init(session: TerminalSession) { self.session = session; self.terminal = session.terminal; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func loadView() {
        overrideUserInterfaceStyle = .dark
        view = UIView(); view.backgroundColor = terminal.nativeBackgroundColor
        view.clipsToBounds = true
        terminal.removeFromSuperview(); terminal.terminalDelegate = self
        terminal.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(terminal)
        NSLayoutConstraint.activate([
            terminal.topAnchor.constraint(equalTo: view.topAnchor), terminal.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            terminal.trailingAnchor.constraint(equalTo: view.trailingAnchor), terminal.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        (terminal as? SafeTerminalView)?.approvePaste = { [weak self] text, insert in
            guard let self, let session = self.session, session.isLive else { return }
            let preview = String(text.prefix(300)).replacingOccurrences(of: "\n", with: "↵\n").replacingOccurrences(of: "\r", with: "⏎").replacingOccurrences(of: "\u{1b}", with: "␛")
            let alert = UIAlertController(title: "Paste into " + session.host.name + "?", message: "This text includes line breaks or control characters.\n\n" + preview, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: "Paste", style: .default) { [weak session] _ in if session?.isLive == true { insert() } })
            self.present(alert, animated: true)
        }
        terminal.inputAccessoryView = nil
        compositionPreview.isHidden = true
        compositionPreview.isUserInteractionEnabled = false
        compositionPreview.accessibilityIdentifier = "terminal.composition"
        compositionPreview.accessibilityLabel = "Uncommitted text"
        compositionPreview.isAccessibilityElement = true
        compositionPreview.textColor = .label
        compositionPreview.backgroundColor = .secondarySystemBackground
        compositionPreview.layer.cornerRadius = 4
        compositionPreview.clipsToBounds = true
        view.addSubview(compositionPreview)
        if let session {
            keyPalette = FloatingKeyPalette(input: session.floatingKeyInput)
            keyPalette.showSidebar = { [weak self] in self?.showSessions?() }
            keyPalette.toggleKeyboard = { [weak session] in session?.toggleKeyboard() }
            view.addSubview(keyPalette)
        }
        (terminal as? SafeTerminalView)?.compositionChanged = { [weak self] in self?.updateKeyboardViewport() }
        session?.updateTerminalColors()
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardFrameChanged), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateKeyboardViewport()
    }
    func updateKeyboardViewport() {
        guard isViewLoaded else { return }
        updateKeyPalette()
        // Server redraws move the cursor while resizing; keep touch coordinates stable.
        guard (terminal as? SafeTerminalView)?.isDraggingPane != true else { return }
        // Move the viewport to keep the cursor visible without changing the PTY grid.
        var visibleHeight = view.bounds.height
        if let keyboardFrame, let window = view.window {
            let frame = view.convert(keyboardFrame, from: window.screen.coordinateSpace)
            // An undocked iPad keyboard must not move the full terminal viewport.
            if frame.maxY >= view.bounds.maxY && frame.width >= view.bounds.width {
                visibleHeight = max(0, min(view.bounds.height, frame.minY))
            }
        }
        let cellHeight = terminal.getOptimalFrameSize().height / CGFloat(max(1, terminal.getTerminal().rows))
        let cursorBottom = CGFloat(terminal.getTerminal().getCursorLocation().y + 1) * cellHeight
        let shift = min(max(0, view.bounds.height - visibleHeight), max(0, cursorBottom - visibleHeight))
        terminal.transform = CGAffineTransform(translationX: 0, y: -shift)
        let marked = (terminal as? SafeTerminalView)?.compositionText ?? ""
        compositionPreview.isHidden = marked.isEmpty || !terminal.isFirstResponder || session?.isLive != true
        guard !compositionPreview.isHidden else { compositionPreview.text = nil; return }
        compositionPreview.font = .monospacedSystemFont(ofSize: max(16, terminal.font.pointSize), weight: .regular)
        if compositionPreview.text != marked {
            compositionPreview.attributedText = NSAttributedString(string: marked, attributes: [.underlineStyle: NSUnderlineStyle.single.rawValue])
        }
        compositionPreview.accessibilityValue = marked
        let size = compositionPreview.sizeThatFits(CGSize(width: max(0, view.bounds.width - 12), height: .greatestFiniteMagnitude))
        let width = min(view.bounds.width, size.width + 12), height = size.height + 8
        let cellWidth = terminal.getOptimalFrameSize().width / CGFloat(max(1, terminal.getTerminal().cols))
        let x = min(CGFloat(terminal.getTerminal().getCursorLocation().x) * cellWidth, max(0, view.bounds.width - width))
        let y = max(0, min(cursorBottom - cellHeight - shift, visibleHeight - height))
        compositionPreview.frame = CGRect(x: x, y: y, width: width, height: height)
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        session?.updateTerminalColors()
        session?.restoreKeyboardIfNeeded()
        session?.activateTmuxClient()
    }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); session?.floatingKeyInput.reset(); (terminal as? SafeTerminalView)?.setPaneResizeMode(false); terminal.controlModifier = false }
    func closeUI() {
        terminal.resignFirstResponder()
        viewIfLoaded?.endEditing(true)
        dismiss(animated: false)
        (terminal as? SafeTerminalView)?.approvePaste = nil
        (terminal as? SafeTerminalView)?.compositionChanged = nil
    }
    private func updateKeyPalette() {
        guard let keyPalette, let session else { return }
        keyPalette.setKeyboardVisible(session.keyboardVisible)
        keyPalette.isHidden = !session.floatingKeysVisible || !session.isLive
        var keyboard: CGRect?
        if let keyboardFrame, let window = view.window {
            let converted = view.convert(keyboardFrame, from: window.screen.coordinateSpace)
            if converted.intersects(view.bounds) { keyboard = converted }
        }
        keyPalette.place(in: view.bounds.inset(by: view.safeAreaInsets), avoiding: keyboard)
    }
    @objc private func keyboardFrameChanged(_ notification: Notification) {
        keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        updateKeyboardViewport()
    }
    @objc private func keyboardWillShow() {
        (terminal as? SafeTerminalView)?.observeComposition()
        if terminal.isFirstResponder { session?.keyboardVisible = true }
    }
    @objc private func keyboardWillHide() { session?.keyboardVisible = false; keyboardFrame = nil; updateKeyboardViewport() }
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) { session?.connection?.resize(columns: newCols, rows: newRows) }
    func send(source: TerminalView, data: ArraySlice<UInt8>) { session?.send(Data(data)) }
    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func scrolled(source: TerminalView, position: Double) {}
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        guard let url = URL(string: link), ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return }
        let alert = UIAlertController(title: "Open link?", message: link, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel)); alert.addAction(UIAlertAction(title: "Open", style: .default) { _ in UIApplication.shared.open(url) }); present(alert, animated: true)
    }
    func bell(source: TerminalView) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    deinit { NotificationCenter.default.removeObserver(self) }
}

final class CompositionPreview: UILabel {
    override func drawText(in rect: CGRect) { super.drawText(in: rect.insetBy(dx: 6, dy: 4)) }
}
