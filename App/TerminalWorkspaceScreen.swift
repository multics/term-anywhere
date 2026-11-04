import SwiftUI
import TermCore

struct TerminalWorkspaceScreen: View {
    @ObservedObject var store: AppStore
    let hostID: UUID
    var showSidebar: () -> Void = {}
    var body: some View {
        if let session = store.sessions[hostID] {
            TerminalScreen(session: session, onDisconnect: { store.closeTab(session) },
                           tabCount: store.tabs[hostID]?.count ?? 1, showSessions: showSidebar)
                .id(session.id)
        }
    }
}

struct SessionPanel: View {
    @ObservedObject var store: AppStore
    let hostID: UUID
    let dismiss: () -> Void
    var body: some View {
        NavigationStack {
            List { SidebarSessionRows(store: store, hostID: hostID, dismiss: dismiss) }
                .navigationDestination(for: Bool.self) { create in
                    if let source = store.sessions[hostID] {
                        ServerSessionBrowser(store: store, source: source, createOnly: create, dismiss: dismiss)
                    }
                }
                .navigationTitle("Sessions")
        }
    }
}

struct SidebarSessionRows: View {
    @ObservedObject var store: AppStore
    let hostID: UUID
    let dismiss: () -> Void
    var body: some View {
        Section(store.hosts.first(where: { $0.id == hostID })?.name ?? "Open sessions") {
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
                NavigationLink(value: false) { Label("Open session…", systemImage: "rectangle.on.rectangle") }
                NavigationLink(value: true) { Label("New session…", systemImage: "plus") }
            } footer: { Text("Closing a tab leaves its remote tmux session running.") }
            .disabled(!source.isLive)
        }
    }
}

struct ServerSessionBrowser: View {
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

/// Session actions stay scoped to the terminal named at the top of the sidebar.
struct WorkspaceCurrentTerminal: View {
    @ObservedObject var session: TerminalSession
    @State private var tool: Tool?
    @State private var keyboardTogglePending = false
    private enum Tool: String, Identifiable { case terminal, tmux; var id: String { rawValue } }
    var body: some View {
        Section("Current terminal") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(session.host.name).font(.caption).foregroundStyle(.secondary)
                        Text(session.host.sessionLabel).font(.headline).lineLimit(1)
                    }
                    Spacer()
                    Menu {
                        Button("Disconnect", systemImage: "xmark.circle") { session.store?.closeTab(session) }
                    } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                    .accessibilityLabel("Current terminal actions")
                }
                HStack(spacing: 4) {
                    Button { session.store?.stepTab(for: session.host.id, by: -1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                        .accessibilityLabel("Previous tab").keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                        .disabled((session.store?.tabs[session.host.id]?.count ?? 0) < 2)
                    Button { session.store?.stepTab(for: session.host.id, by: 1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                        .accessibilityLabel("Next tab").keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                        .disabled((session.store?.tabs[session.host.id]?.count ?? 0) < 2)
                    Spacer(minLength: 0)
                    Button { tool = .terminal } label: {
                        Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44)
                    }.accessibilityLabel("Terminal controls")
                    if !session.host.tmuxSession.isEmpty { Button("tmux") { tool = .tmux }.frame(minWidth: 44, minHeight: 44) }
                    Toggle(isOn: Binding(get: { session.floatingKeysVisible }, set: session.setFloatingKeysVisible)) {
                        Label("Floating keys", systemImage: "keyboard").labelStyle(.iconOnly).frame(width: 36, height: 36)
                    }.toggleStyle(.button).accessibilityIdentifier("terminal.floatingKeys.toggle")
                        .accessibilityValue(session.floatingKeysVisible ? "Shown" : "Hidden")
                }.font(.subheadline).buttonStyle(.borderless)
            }
        }
        .sheet(item: $tool, onDismiss: {
            if keyboardTogglePending { keyboardTogglePending = false; session.toggleKeyboard() }
        }) { selected in
            NavigationStack {
                List {
                    TerminalSidebarTools(session: session, showTerminal: selected == .terminal) {
                        keyboardTogglePending = true; tool = nil
                    }
                }
                .navigationTitle(selected == .terminal ? "Terminal" : "tmux controls")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { tool = nil } } }
            }.presentationDetents([.medium, .large]).preferredColorScheme(.dark)
        }
    }
}
