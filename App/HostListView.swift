import SwiftUI
import UniformTypeIdentifiers
import TermCore

struct HostListView: View {
    @EnvironmentObject private var store: AppStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly
    @State private var compactColumn: NavigationSplitViewColumn = .sidebar
    @State private var sidebarPath = NavigationPath()
    @State private var expandedHosts: Set<UUID> = []
    @State private var search = ""
    @State private var searching = false
    @State private var editing: Host?
    @State private var credentials = false
    @State private var importing = false
    @State private var settings = false
    @State private var editMode: EditMode = .inactive
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $compactColumn) {
            NavigationStack(path: $sidebarPath) {
            List {
                if searching {
                    TextField("Find a connection", text: $search)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("workspace.search")
                }
                if let selected = store.selectedHostID, let session = store.sessions[selected] {
                    WorkspaceCurrentTerminal(session: session).id(session.id)
                }
                Section {
                    if store.hosts.isEmpty {
                        ContentUnavailableView("No connections yet", systemImage: "terminal", description: Text("Add a connection or import connections from your Mac."))
                            .listRowBackground(Color.clear)
                        Button("Add connection", systemImage: "plus") { editing = Host() }
                        Button("Import connections", systemImage: "square.and.arrow.down") { importing = true }
                    }
                    ForEach(store.hosts.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { host in
                        connectionRow(host)
                    }
                    .onMove { offsets, destination in store.moveHosts(from: offsets, to: destination) }
                    .moveDisabled(!search.isEmpty)
                } header: {
                    HStack {
                        Text("Connections")
                        Spacer()
                        Button(editMode.isEditing ? "Done" : "Reorder") {
                            search = ""; editMode = editMode.isEditing ? .inactive : .active
                        }.disabled(store.hosts.count < 2 && !editMode.isEditing)
                    }
                }
            }
            .listStyle(.plain)
            .listSectionSpacing(8)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack {
                    Button("Credentials", systemImage: "key") { credentials = true }
                    Spacer()
                    Button("Settings", systemImage: "gear") { settings = true }
                }
                .font(.subheadline).buttonStyle(.borderless)
                .frame(minHeight: 44).padding(.horizontal, 16)
                .background(.bar)
            }
            .navigationDestination(for: WorkspaceSessionRoute.self) { route in
                if let source = store.sessions[route.hostID] {
                    ServerSessionBrowser(store: store, source: source, createOnly: route.create) {
                        store.selectHost(route.hostID); closeSidebar()
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .navigationTitle("Workspace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(searching ? "Close search" : "Find a connection", systemImage: searching ? "xmark" : "magnifyingglass") {
                        searching.toggle()
                        if !searching { search = "" }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Add connection", systemImage: "plus") { editing = Host() }
                        Button("Import connections", systemImage: "square.and.arrow.down") { importing = true }
                    } label: { Label("Add connection", systemImage: "plus") }
                }
            }
            }
        } detail: {
            if let selected = store.selectedHostID, store.sessions[selected] != nil {
                TerminalWorkspaceScreen(store: store, hostID: selected, showSidebar: {
                    columnVisibility = .all; compactColumn = .sidebar
                }).id(selected)
            } else {
                ContentUnavailableView("Term Anywhere", systemImage: "terminal", description: Text("Choose a server to open a terminal."))
            }
        }
        .navigationSplitViewStyle(.prominentDetail)
        .ignoresSafeArea(.keyboard)
        .task {
            // Apply initial visibility after the native split view has mounted.
            await Task.yield()
            if let selected = store.selectedHostID { expandedHosts.insert(selected) }
            else { columnVisibility = .all }
        }
        .onChange(of: store.selectedHostID) { _, id in
            if let id { expandedHosts.insert(id) }
            compactColumn = id == nil ? .sidebar : .detail
            columnVisibility = id == nil ? .all : .detailOnly
        }
        .sheet(item: $editing) { host in HostEditor(host: host) }
        .sheet(isPresented: $credentials) { CredentialsView() }
        .sheet(isPresented: $settings) { SettingsView(sync: store.configuration) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do { try store.importHosts(result.get()) } catch { store.error = error.localizedDescription }
        }
        .alert("Cannot complete the action", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
        .onChange(of: scenePhase, initial: true) { _, phase in
            UIApplication.shared.isIdleTimerDisabled = phase == .active
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store.configuration.start()
                do { try store.refreshCredentials() } catch { store.error = error.localizedDescription }
                for session in store.allSessions { session.resume() }
            } else { for session in store.allSessions { session.prepareForBackground() } }
        }
        .overlay { if scenePhase == .background { Color(.systemBackground).ignoresSafeArea().overlay { Image(systemName: "terminal").font(.largeTitle) } } }
    }
    private func connectionRow(_ host: Host) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Button {
                    if expandedHosts.contains(host.id) { expandedHosts.remove(host.id) }
                    else { expandedHosts.insert(host.id) }
                } label: {
                    Image(systemName: expandedHosts.contains(host.id) ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold)).frame(width: 44, height: 44)
                }
                .accessibilityLabel("\(expandedHosts.contains(host.id) ? "Collapse" : "Expand") \(host.name)")
                .accessibilityIdentifier("workspace.expand.\(host.id)")
                Button {
                    store.selectHost(host.id); expandedHosts.insert(host.id); closeSidebar()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(host.name).font(.headline).foregroundStyle(.primary)
                            Text("\(host.username) · \(host.isSSM ? "AWS SSM" : "SSH")").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        if let tabs = store.tabs[host.id], !tabs.isEmpty {
                            Text("\(tabs.count) open").font(.caption).foregroundStyle(.secondary)
                        }
                        if store.tabs[host.id]?.contains(where: { $0.isLive }) == true {
                            Image(systemName: "circle.fill").font(.system(size: 7)).foregroundStyle(.green).accessibilityLabel("Connected")
                        }
                    }.frame(minHeight: 44).contentShape(Rectangle())
                }.accessibilityIdentifier("workspace.host.\(host.id)")
            }
            .buttonStyle(.borderless)
            .modifier(HostRowActions(host: host, edit: { editing = host }, remove: {
                do { try store.removeHost(host.id) } catch { store.error = error.localizedDescription }
            }, duplicate: { editing = host.duplicate() }, disconnect: store.tabs[host.id]?.contains(where: { $0.canDisconnect }) == true ? { store.closeSession(host.id) } : nil))
            if expandedHosts.contains(host.id), !editMode.isEditing {
                ForEach(store.tabs[host.id] ?? [], id: \.id) { tab in
                    HStack {
                        Button {
                            store.activateTab(tab); closeSidebar()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tab.host.sessionLabel).foregroundStyle(.primary)
                                    Text(tab.status).font(.caption).foregroundStyle(tab.error == nil ? Color.secondary : .red)
                                }
                                Spacer()
                                if store.selectedHostID == host.id && store.sessions[host.id] === tab {
                                    Image(systemName: "checkmark").accessibilityLabel("Current session")
                                }
                            }.frame(minHeight: 44).contentShape(Rectangle())
                        }.accessibilityIdentifier("workspace.session.\(tab.id)")
                        Button { store.closeTab(tab) } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                            .accessibilityLabel("Close \(tab.host.sessionLabel) tab")
                    }.buttonStyle(.borderless).padding(.leading, 44)
                }
                if let source = store.sessions[host.id] {
                    HStack {
                        Button("Open session…") { sidebarPath.append(WorkspaceSessionRoute(hostID: host.id, create: false)) }
                        Spacer()
                        Button("New…") { sidebarPath.append(WorkspaceSessionRoute(hostID: host.id, create: true)) }
                    }.font(.subheadline).buttonStyle(.borderless).frame(minHeight: 44).padding(.leading, 44).disabled(!source.isLive)
                } else {
                    Text("Select this connection to open a terminal.").font(.caption).foregroundStyle(.secondary).padding(.leading, 44)
                }
            }
        }
    }
    private func closeSidebar() {
        sidebarPath = NavigationPath()
        guard store.selectedHostID != nil else { columnVisibility = .all; compactColumn = .sidebar; return }
        compactColumn = .detail; columnVisibility = .detailOnly
        let session = store.selectedHostID.flatMap { store.sessions[$0] }
        DispatchQueue.main.async { session?.restoreKeyboardIfNeeded() }
    }

}

private struct WorkspaceSessionRoute: Hashable {
    let hostID: UUID
    let create: Bool
}
