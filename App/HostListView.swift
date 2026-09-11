import SwiftUI
import UniformTypeIdentifiers
import TermCore

struct HostListView: View {
    @EnvironmentObject private var store: AppStore
    @State private var compactColumn: NavigationSplitViewColumn = .sidebar
    @State private var search = ""
    @State private var editing: Host?
    @State private var credentials = false
    @State private var importing = false
    @State private var settings = false
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        NavigationSplitView(preferredCompactColumn: $compactColumn) {
            List(selection: Binding(get: { store.selectedHostID }, set: { store.selectHost($0) })) {
                if store.hosts.isEmpty {
                    ContentUnavailableView("No hosts yet", systemImage: "terminal", description: Text("Add a host or import selected connections from your Mac."))
                        .listRowBackground(Color.clear)
                    Button("Add a host", systemImage: "plus") { editing = Host() }
                    Button("Import connections", systemImage: "square.and.arrow.down") { importing = true }
                }
                ForEach(store.hosts.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { host in
                    NavigationLink(value: host.id) {
                        HStack(spacing: 12) {
                            Image(systemName: host.isSSM ? "cloud" : "terminal").foregroundStyle(.tint).frame(width: 24)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(host.name).font(.headline)
                                Text("\(host.username) · \(host.isSSM ? "AWS SSM" : "SSH")").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if store.sessions[host.id]?.isLive == true { Image(systemName: "circle.fill").font(.system(size: 7)).foregroundStyle(.green).accessibilityLabel("Connected") }
                        }.padding(.vertical, 5)
                    }
                    .modifier(HostRowActions(host: host, edit: { editing = host }, remove: {
                        do { try store.removeHost(host.id) } catch { store.error = error.localizedDescription }
                    }, disconnect: store.sessions[host.id]?.canDisconnect == true ? { store.closeSession(host.id) } : nil))
                }
            }
            .navigationTitle("Hosts")
            .searchable(text: $search, prompt: "Find a server")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Keys and AWS", systemImage: "key") { credentials = true } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Add host", systemImage: "plus") { editing = Host() }
                        Button("Import connections", systemImage: "square.and.arrow.down") { importing = true }
                        Divider()
                        Button("Settings and iCloud", systemImage: "gear") { settings = true }
                    } label: { Label("Add", systemImage: "plus") }
                }
            }
        } detail: {
            if let selected = store.selectedHostID, let session = store.sessions[selected] {
                TerminalScreen(session: session, onDisconnect: { store.closeSession(selected) }).id(ObjectIdentifier(session))
            } else {
                ContentUnavailableView("Term Anywhere", systemImage: "terminal", description: Text("Choose a server to open a terminal."))
            }
        }
        .onChange(of: store.selectedHostID) { _, id in
            compactColumn = id == nil ? .sidebar : .detail
        }
        .sheet(item: $editing) { host in HostEditor(host: host) }
        .sheet(isPresented: $credentials) { CredentialsView() }
        .sheet(isPresented: $settings) { SettingsView(sync: store.configuration) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do { try store.importHosts(result.get()) } catch { store.error = error.localizedDescription }
        }
        .alert("Cannot complete the action", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store.configuration.start()
                do { try store.refreshCredentials() } catch { store.error = error.localizedDescription }
                for session in store.sessions.values { session.resume() }
            }
        }
        .overlay { if scenePhase == .background { Color(.systemBackground).ignoresSafeArea().overlay { Image(systemName: "terminal").font(.largeTitle) } } }
    }
}
