import SwiftUI
import SwiftTerm
import TermCore

struct TerminalScreen: View {
    @ObservedObject var session: TerminalSession
    let onDisconnect: () -> Void
    var tabCount = 1
    var showSessions: (() -> Void)?
    var body: some View {
        TerminalContainer(session: session)
            .ignoresSafeArea(.keyboard)
            .allowsHitTesting(session.isLive)
            .accessibilityHidden(!session.isLive)
            .overlay {
                if !session.isLive { ConnectionOverlay(session: session) }
            }
        .navigationTitle(session.host.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button { showSessions?() } label: {
                    VStack(spacing: 1) {
                        Text(session.host.name).font(.headline).lineLimit(1)
                        HStack(spacing: 4) {
                            Text(session.host.sessionLabel).lineLimit(1)
                            if showSessions != nil {
                                Image(systemName: "chevron.down")
                                Text("\(tabCount)").monospacedDigit()
                            }
                        }.font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Sessions, \(session.host.sessionLabel), \(tabCount) open")
                .accessibilityIdentifier("terminal.sessions")
                .disabled(showSessions == nil)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(session.keyboardVisible ? "Hide keyboard" : "Show keyboard",
                       systemImage: session.keyboardVisible ? "keyboard.chevron.compact.down" : "keyboard") {
                    session.toggleKeyboard()
                }
                .accessibilityIdentifier("terminal.keyboard.toggle")
            }
            ToolbarItem(placement: .topBarTrailing) {
                if !session.host.tmuxSession.isEmpty {
                    Menu {
                        Section {
                            ForEach(session.bindings?.shortcuts ?? []) { shortcut in
                                Button(shortcut.title + " · " + shortcut.keys) { session.send(shortcut.bytes) }
                                    .disabled(!session.isLive)
                            }
                        }
                        Section {
                            Text(session.bindingsStatus)
                            if let prefix = session.prefixBytes {
                                Button("Send prefix") { session.send(prefix) }.disabled(!session.isLive)
                            }
                            Button("Refresh shortcuts", systemImage: "arrow.clockwise") {
                                Task { await session.refreshBindings() }
                            }.disabled(!session.isLive)
                        }
                    } label: { Label("tmux controls", systemImage: "rectangle.split.2x1") }
                    .accessibilityIdentifier("terminal.tmux")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section("Connection") {
                        Text(session.status)
                        Button("Sessions…", systemImage: "rectangle.on.rectangle") { showSessions?() }.disabled(showSessions == nil)
                        Button("Previous tab", systemImage: "chevron.left") { session.store?.stepTab(for: session.host.id, by: -1) }.keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                        Button("Next tab", systemImage: "chevron.right") { session.store?.stepTab(for: session.host.id, by: 1) }.keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                        Button("Close tab", systemImage: "xmark.circle") { onDisconnect() }
                    }
                    Section("Terminal") {
                        if let message = session.scrollStatus { Text(message) }
                        Button(session.keyboardVisible ? "Hide keyboard" : "Show keyboard", systemImage: "keyboard") { session.toggleKeyboard() }
                        Button("Larger text", systemImage: "textformat.size.larger") { session.changeFontSize(by: 1) }
                        Button("Smaller text", systemImage: "textformat.size.smaller") { session.changeFontSize(by: -1) }
                        Toggle("Option as Meta", isOn: Binding(get: { session.optionAsMeta }, set: { session.setOptionAsMeta($0) }))
                    }
                } label: { Label("Session and terminal tools", systemImage: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $session.selectingTmux) { TmuxSessionPicker(session: session).interactiveDismissDisabled() }
        .task { if !session.hasStarted { session.connect() } }
        .onChange(of: session.optionAsMeta) { _, value in session.terminal.optionAsMetaKey = value }
        .onDisappear { session.terminal.controlModifier = false; session.terminal.metaModifier = false }
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
    func makeUIViewController(context: Context) -> TerminalCoordinator {
        let controller = TerminalCoordinator(session: session); session.coordinator = controller; return controller
    }
    func updateUIViewController(_ controller: TerminalCoordinator, context: Context) {
        controller.refreshMenu()
        session.updateTerminalColors()
        controller.requestInitialLandscape()
    }
}

@MainActor final class TerminalCoordinator: UIViewController, @preconcurrency TerminalViewDelegate {
    weak var session: TerminalSession?
    let terminal: TerminalView
    private var controlButton: UIButton?
    private var moreButton: UIButton?
    private var repeatTimer: Timer?
    private var keyboardFrame: CGRect?
    init(session: TerminalSession) { self.session = session; self.terminal = session.terminal; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func loadView() {
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
        makeAccessory()
        session?.updateTerminalColors()
        NotificationCenter.default.addObserver(self, selector: #selector(resetControl), name: .terminalViewControlModifierReset, object: terminal)
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
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        session?.updateTerminalColors()
        requestInitialLandscape()
        session?.restoreKeyboardIfNeeded()
    }
    func requestInitialLandscape() {
        guard let window = viewIfLoaded?.window else { return }
        session?.requestInitialLandscape(in: window)
    }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); stopRepeat(); terminal.controlModifier = false; resetControl() }
    private func makeAccessory() {
        let bar = UIInputView(frame: CGRect(x: 0, y: 0, width: 393, height: 48), inputViewStyle: .keyboard)
        let stack = UIStackView(); stack.axis = .horizontal; stack.distribution = .fillEqually; stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false; bar.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 4), stack.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -4), stack.topAnchor.constraint(equalTo: bar.topAnchor, constant: 2), stack.bottomAnchor.constraint(equalTo: bar.bottomAnchor, constant: -2)])
        for title in ["Esc", "Ctrl", "Tab", "←", "↓", "↑", "→", "More"] {
            let button = UIButton(type: .system); button.setTitle(title, for: .normal); button.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
            button.accessibilityLabel = ["←": "Left arrow", "↓": "Down arrow", "↑": "Up arrow", "→": "Right arrow" ][title] ?? title
            if title == "More" { moreButton = button; button.accessibilityIdentifier = "terminal.keyboard.more"; button.showsMenuAsPrimaryAction = true }
            else if title == "Ctrl" {
                controlButton = button
                button.addAction(UIAction { [weak self] _ in guard let self, self.session?.isLive == true else { return }; self.terminal.controlModifier.toggle(); self.resetControl() }, for: .touchUpInside)
            } else if ["←", "↓", "↑", "→"].contains(title) {
                button.addAction(UIAction { [weak self] _ in
                    guard let self else { return }; self.stopRepeat(); self.arrow(title)
                    self.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
                        MainActor.assumeIsolated {
                            self?.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.arrow(title) } }
                        }
                    }
                }, for: .touchDown)
                button.addAction(UIAction { [weak self] _ in self?.stopRepeat() }, for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
            } else { button.addAction(UIAction { [weak self] _ in self?.terminal.send(title == "Esc" ? [27] : [9]) }, for: .touchUpInside) }
            stack.addArrangedSubview(button)
        }
        terminal.inputAccessoryView = bar; refreshMenu()
    }
    private func arrow(_ key: String) {
        guard session?.isLive == true else { return }
        let suffix = ["↑": "A", "↓": "B", "→": "C", "←": "D"][key]!
        terminal.send(txt: "\u{1b}" + (terminal.getTerminal().applicationCursor ? "O" : "[") + suffix)
    }
    func closeUI() {
        stopRepeat()
        terminal.resignFirstResponder()
        viewIfLoaded?.endEditing(true)
        dismiss(animated: false)
        (terminal as? SafeTerminalView)?.approvePaste = nil
    }
    @objc private func keyboardFrameChanged(_ notification: Notification) {
        keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        updateKeyboardViewport()
    }
    @objc private func keyboardWillShow() {
        if terminal.isFirstResponder { session?.keyboardVisible = true }
    }
    @objc private func keyboardWillHide() { session?.keyboardVisible = false; keyboardFrame = nil; updateKeyboardViewport() }
    func stopRepeat() { repeatTimer?.invalidate(); repeatTimer = nil }
    @objc private func resetControl() { controlButton?.tintColor = terminal.controlModifier ? .systemOrange : .label; controlButton?.accessibilityValue = terminal.controlModifier ? "On" : "Off" }
    func refreshMenu() {
        guard let session else { return }
        var items: [UIMenuElement] = []
        for shortcut in session.bindings?.shortcuts ?? [] {
            items.append(UIAction(title: shortcut.title, subtitle: shortcut.keys, attributes: session.isLive ? [] : .disabled) { [weak session] _ in session?.send(shortcut.bytes) })
        }
        if let bytes = session.prefixBytes {
            items.append(UIAction(title: "Prefix · " + (session.bindings?.prefix ?? session.host.manualPrefix), attributes: session.isLive ? [] : .disabled) { [weak session] _ in session?.send(bytes) })
        }
        items.append(UIAction(title: "Refresh tmux shortcuts", attributes: session.isLive ? [] : .disabled) { [weak session] _ in Task { await session?.refreshBindings() } })
        let tmux = UIMenu(title: "tmux", options: .displayInline, children: items)
        let symbols = ["/", "~", "|", "-", "_", "$"].map { symbol in UIAction(title: symbol) { [weak self] _ in self?.terminal.insertText(symbol) } }
        moreButton?.menu = UIMenu(children: [tmux, UIMenu(title: "Symbols", children: symbols), UIAction(title: "Alt / Meta", state: terminal.metaModifier ? .on : .off) { [weak self] _ in self?.terminal.metaModifier.toggle() }, UIAction(title: "Hide keyboard") { [weak session] _ in session?.hideKeyboard() }])
    }
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
