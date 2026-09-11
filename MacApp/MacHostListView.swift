import SwiftUI
import UniformTypeIdentifiers
import TermCore

private enum MacSelection: Hashable { case host(UUID), keys, aws }

struct MacHostListView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var phase
    @State private var selected: MacSelection?
    @State private var editing: TermCore.Host?
    @State private var search = ""
    @State private var importingSSH = false
    @State private var importingJSON = false
    @State private var importingAWS = false
    var body: some View {
        NavigationSplitView {
            List(selection: $selected) {
                Section("Credentials") {
                    Label("SSH Keys", systemImage: "key").badge(store.keyNames.count).tag(MacSelection.keys)
                    Label("AWS Profiles", systemImage: "cloud").badge(store.awsNames.count).tag(MacSelection.aws)
                }
                Section("Hosts") {
                    ForEach(store.hosts.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { host in
                        Label { VStack(alignment: .leading) {
                            Text(host.name)
                            Text(host.isSSM ? "AWS SSM" : "\(host.username)@\(host.address)").font(.caption).foregroundStyle(.secondary)
                        } } icon: { Image(systemName: host.isSSM ? "cloud" : "server.rack") }.tag(MacSelection.host(host.id))
                    }
                }
            }.searchable(text: $search, prompt: "Find a host")
            .navigationSplitViewColumnWidth(min: 200, ideal: 250)
            .safeAreaInset(edge: .bottom) { MacSyncStatus(sync: store.configuration) }
        } detail: {
            switch selected {
            case .keys: CredentialsView(page: .keys, showsDone: false).id("keys")
            case .aws: CredentialsView(page: .aws, showsDone: false).id("aws")
            case .host(let id):
                if let host = store.hosts.first(where: { $0.id == id }) {
                    MacHostEditor(host: host, onSaved: { selected = .host($0.id) }).id(host)
                } else { welcome }
            case nil: welcome
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    Button("Read SSH config…") { importingSSH = true }
                    Button("Import host JSON…") { importingJSON = true }
                    Divider()
                    Button("Import AWS profiles…") { importingAWS = true }
                } label: { Label("Import", systemImage: "square.and.arrow.down") }
                Button("Add host", systemImage: "plus") { editing = TermCore.Host() }.keyboardShortcut("n")
                SettingsLink { Label("Settings", systemImage: "gear") }
            }
        }
        .sheet(item: $editing) { host in
            MacHostEditor(host: host, onSaved: { selected = .host($0.id); editing = nil }, showsCancel: true).frame(width: 620, height: 650)
        }
        .sheet(isPresented: $importingSSH) { MacSSHImportView() }
        .sheet(isPresented: $importingAWS) { MacAWSImportView() }
        .fileImporter(isPresented: $importingJSON, allowedContentTypes: [.json]) { result in
            do { try store.importHosts(result.get()) } catch { store.error = error.localizedDescription }
        }
        .alert("Cannot complete the action", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
        .onChange(of: store.hosts.map(\.id)) { _, ids in
            if case .host(let id) = selected, !ids.contains(id) { selected = nil }
        }
        .onChange(of: phase) { _, value in
            if value == .active {
                store.configuration.start()
                do { try store.refreshCredentials() } catch { store.error = error.localizedDescription }
            }
        }
    }
    private var welcome: some View {
        ContentUnavailableView {
            Label("Configure your servers", systemImage: "server.rack")
        } description: { Text("Manage hosts, SSH keys, and AWS profiles here. Your iPhone and iPad use them to connect.") }
        actions: {
            Button("Import SSH hosts…") { importingSSH = true }.buttonStyle(.borderedProminent)
            Button("Add host") { editing = TermCore.Host() }
        }
    }
}

private struct MacSyncStatus: View {
    @ObservedObject var sync: ConfigurationSync
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("iCloud", systemImage: "icloud").font(.callout)
            Text(sync.status).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
    }
}

struct MacHostEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var host: TermCore.Host
    let onSaved: (TermCore.Host) -> Void
    var showsCancel = false
    @State private var error: String?
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(host.name.isEmpty ? "New host" : host.name).font(.title2.bold())
                Spacer()
                Button("Save") { save() }.keyboardShortcut("s")
                if showsCancel { Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction) }
            }.padding()
            Form {
                Section("Connection settings") {
                    TextField("Name", text: $host.name)
                    TextField("Hostname or EC2 instance ID", text: $host.address)
                    TextField("SSH user", text: $host.username)
                    TextField("SSH port", value: $host.port, format: .number)
                    TextField("SSH key name", text: $host.keyID)
                    if !store.keyNames.isEmpty { Picker("Imported key", selection: $host.keyID) {
                        Text(host.keyID.isEmpty ? "Choose a key" : host.keyID).tag(host.keyID)
                        ForEach(store.keyNames.filter { $0 != host.keyID }, id: \.self) { Text($0).tag($0) }
                    } }
                }
                Section("AWS SSM") {
                    TextField("Profile name (empty for direct SSH)", text: $host.awsProfile)
                    if !store.awsNames.isEmpty { Picker("Imported profile", selection: $host.awsProfile) {
                        Text(host.awsProfile.isEmpty ? "Direct SSH" : host.awsProfile).tag(host.awsProfile)
                        ForEach(store.awsNames.filter { $0 != host.awsProfile }, id: \.self) { Text($0).tag($0) }
                    } }
                    TextField("Region", text: $host.region)
                    Text("Use the same credential name on each device. Manage keys and profiles in the sidebar.").font(.caption).foregroundStyle(.secondary)
                }
                Section("tmux on iPhone and iPad") {
                    TextField("Session (empty for plain shell)", text: $host.tmuxSession)
                    TextField("Socket path (optional)", text: $host.tmuxSocket)
                    TextField("Fallback prefix (for example C-a)", text: $host.manualPrefix)
                }
                if let error { Text(error).foregroundStyle(.red) }
            }.formStyle(.grouped)
        }
    }
    private func save() {
        do { try store.save(host); onSaved(host) }
        catch { self.error = error.localizedDescription }
    }
}
