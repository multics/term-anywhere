import SwiftUI
import TermCore

struct TerminalWorkspaceScreen: View {
    @ObservedObject var store: AppStore
    let hostID: UUID
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var showingSessions = false
    @State private var keyboardWasVisible = false
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    private var usesSidePanel: Bool { !isPad && verticalSizeClass == .compact }
    private var sheetPresented: Binding<Bool> {
        Binding(get: { showingSessions && !usesSidePanel && !isPad }, set: { showingSessions = $0 })
    }
    private var popoverPresented: Binding<Bool> {
        Binding(get: { showingSessions && isPad }, set: { showingSessions = $0 })
    }
    var body: some View {
        GeometryReader { geometry in
            if let session = store.sessions[hostID] {
                TerminalScreen(session: session, onDisconnect: { store.closeTab(session) },
                               tabCount: store.tabs[hostID]?.count ?? 1, showSessions: {
                    keyboardWasVisible = session.keyboardVisible
                    showingSessions = true
                })
                .id(session.id)
                .popover(isPresented: popoverPresented, attachmentAnchor: .point(.topTrailing), arrowEdge: .top) {
                    panel.frame(width: 340, height: 420).presentationCompactAdaptation(.popover)
                }
                .sheet(isPresented: sheetPresented, onDismiss: restoreKeyboard) {
                    panel.presentationDetents([.medium, .large])
                }
                .overlay(alignment: .trailing) {
                    if showingSessions && usesSidePanel {
                        ZStack(alignment: .trailing) {
                            Color.black.opacity(0.18).contentShape(Rectangle())
                                .onTapGesture { showingSessions = false }
                                .accessibilityLabel("Dismiss sessions")
                                .accessibilityAddTraits(.isButton)
                            panel.frame(width: min(320, geometry.size.width * 0.6))
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .shadow(radius: 12)
                        }
                    }
                }
            }
        }
        .onChange(of: showingSessions) { _, visible in if !visible { restoreKeyboard() } }
    }
    private var panel: some View {
        SessionPanel(store: store, hostID: hostID) { showingSessions = false }
    }
    private func restoreKeyboard() {
        guard let session = store.sessions[hostID] else { return }
        session.restoreKeyboardOnAppear = keyboardWasVisible
        // A tab change mounts its terminal after this SwiftUI update.
        DispatchQueue.main.async { session.restoreKeyboardIfNeeded() }
    }
}

struct SessionPanel: View {
    @ObservedObject var store: AppStore
    let hostID: UUID
    let dismiss: () -> Void
    var body: some View {
        NavigationStack {
            List {
                Section("Open tabs") {
                    ForEach(store.tabs[hostID] ?? [], id: \.id) { tab in
                        HStack {
                            Button {
                                store.selectTab(tab); dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(tab.host.sessionLabel).foregroundStyle(.primary)
                                        Text(tab.status).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if store.sessions[hostID] === tab {
                                        Image(systemName: "checkmark").accessibilityLabel("Current tab")
                                    }
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Button {
                                store.closeTab(tab)
                                if store.tabs[hostID] == nil { dismiss() }
                            } label: {
                                Image(systemName: "xmark").frame(width: 44, height: 44)
                            }.buttonStyle(.borderless).accessibilityLabel("Close \(tab.host.sessionLabel) tab")
                        }
                    }
                }
                if let source = store.sessions[hostID] {
                    Section {
                        NavigationLink {
                            ServerSessionBrowser(store: store, source: source, createOnly: false, dismiss: dismiss)
                        } label: { Label("Open session…", systemImage: "rectangle.on.rectangle") }
                        NavigationLink {
                            ServerSessionBrowser(store: store, source: source, createOnly: true, dismiss: dismiss)
                        } label: { Label("New session…", systemImage: "plus") }
                    } footer: { Text("Closing a tab leaves its remote tmux session running.") }
                    .disabled(!source.isLive)
                }
            }
            .navigationTitle("Sessions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", action: dismiss) } }
        }
    }
}

private struct ServerSessionBrowser: View {
    @ObservedObject var store: AppStore
    @ObservedObject var source: TerminalSession
    let createOnly: Bool
    let dismiss: () -> Void
    @State private var names: [String] = []
    @State private var available = false
    @State private var loading = true
    @State private var error: String?
    @State private var newName = ""
    var body: some View {
        List {
            if loading { ProgressView("Reading server sessions…") }
            if let error {
                Text(error).foregroundStyle(.red)
                Button("Retry") { Task { await discover() } }
            }
            if !loading && error == nil {
                if createOnly && available {
                    TextField("Session name", text: $newName)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Create and open") { open(newName.trimmingCharacters(in: .whitespaces), create: true) }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                } else if !createOnly {
                    ForEach(names, id: \.self) { name in
                        Button { open(name) } label: {
                            HStack {
                                Text(name); Spacer()
                                if store.tabs[source.host.id]?.contains(where: { $0.host.tmuxSession == name }) == true {
                                    Text("Open").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if names.isEmpty { Text(available ? "No tmux sessions were listed." : "tmux is not available on this server.") }
                    Button("Open plain shell", systemImage: "terminal") { open("") }
                } else { Text("tmux is not available on this server.") }
            }
        }
        .navigationTitle(createOnly ? "New session" : "Server sessions")
        .task { await discover() }
    }
    private func discover() async {
        loading = true; error = nil
        defer { loading = false }
        do {
            guard source.isLive, let connection = source.connection else { throw ConnectionError.message("Reconnect this tab to read server sessions.") }
            let listing = try await connection.tmuxSessions(for: source.host)
            try Task.checkCancellation()
            names = listing.names; available = listing.isAvailable
        } catch { self.error = error.localizedDescription }
    }
    private func open(_ name: String, create: Bool = false) {
        do { try store.openTab(from: source, name: name, create: create); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
