import SwiftUI
import UniformTypeIdentifiers
import TermCore

struct MacHostListView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var phase
    @State private var selected: UUID?
    @State private var editing: TermCore.Host?
    @State private var terminalID: UUID?
    @State private var search = ""
    @State private var credentials = false
    @State private var importingSSH = false
    @State private var importingJSON = false
    var body: some View {
        NavigationSplitView {
            List(selection: $selected) {
                ForEach(store.hosts.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { host in
                    Label { VStack(alignment: .leading) {
                        Text(host.name)
                        Text(host.isSSM ? "AWS SSM" : "\(host.username)@\(host.address)").font(.caption).foregroundStyle(.secondary)
                    } } icon: { Image(systemName: host.isSSM ? "cloud" : "terminal") }.tag(host.id)
                }
            }.searchable(text: $search, prompt: "Find a host")
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
            .safeAreaInset(edge: .bottom) {
                Button("Keys and AWS profiles", systemImage: "key") { credentials = true }.buttonStyle(.plain).padding()
            }
        } detail: {
            if let selected, let host = store.hosts.first(where: { $0.id == selected }) {
                if terminalID == selected {
                    let session = store.session(for: host)
                    MacTerminalScreen(session: session, showSettings: { terminalID = nil }).id(ObjectIdentifier(session))
                } else {
                    MacHostEditor(host: host, onSaved: { self.selected = $0.id }, onConnect: { terminalID = host.id }).id(host)
                }
            } else {
                ContentUnavailableView {
                    Label("Your servers, on every device", systemImage: "terminal")
                } description: { Text("Add a host or import connections from this Mac’s SSH config.") }
                actions: {
                    Button("Import SSH hosts…") { importingSSH = true }.buttonStyle(.borderedProminent)
                    Button("Add host") { editing = TermCore.Host() }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Menu { Button("Read SSH config…") { importingSSH = true }; Button("Import host JSON…") { importingJSON = true } } label: { Label("Import", systemImage: "square.and.arrow.down") }
                Button("Add host", systemImage: "plus") { editing = TermCore.Host() }.keyboardShortcut("n")
                SettingsLink { Label("Settings", systemImage: "gear") }
            }
        }
        .sheet(item: $editing) { host in
            MacHostEditor(host: host, onSaved: { selected = $0.id; editing = nil }, onConnect: nil).frame(width: 620, height: 650)
        }
        .sheet(isPresented: $credentials) { CredentialsView().frame(width: 570, height: 640) }
        .sheet(isPresented: $importingSSH) { MacSSHImportView() }
        .fileImporter(isPresented: $importingJSON, allowedContentTypes: [.json]) { result in
            do { try store.importHosts(result.get()) } catch { store.error = error.localizedDescription }
        }
        .alert("Cannot complete the action", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
        .onChange(of: phase) { _, value in
            if value == .active {
                store.configuration.start()
                do { try store.refreshCredentials() } catch { store.error = error.localizedDescription }
                for session in store.sessions.values { session.resume() }
            }
        }
    }
}

struct MacHostEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var host: TermCore.Host
    let onSaved: (TermCore.Host) -> Void
    let onConnect: (() -> Void)?
    @State private var error: String?
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(host.name.isEmpty ? "New host" : host.name).font(.title2.bold())
                Spacer()
                if let onConnect { Button("Open terminal", systemImage: "terminal") { save(connect: onConnect) }.buttonStyle(.borderedProminent) }
                Button("Save") { save(connect: nil) }.keyboardShortcut("s")
                if onConnect == nil { Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction) }
            }.padding()
            Form {
                Section("Connection") {
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
                    Text("Use the same credential name on each device. Credentials use iCloud Keychain by default; manage storage in Keys and AWS profiles.").font(.caption).foregroundStyle(.secondary)
                }
                Section("tmux") {
                    TextField("Session (empty for plain shell)", text: $host.tmuxSession)
                    TextField("Socket path (optional)", text: $host.tmuxSocket)
                    TextField("Fallback prefix (for example C-a)", text: $host.manualPrefix)
                }
                if let error { Text(error).foregroundStyle(.red) }
            }.formStyle(.grouped)
        }
    }
    private func save(connect: (() -> Void)?) {
        do {
            let changed = store.hosts.first(where: { $0.id == host.id }) != host
            try store.save(host)
            if changed { store.closeSession(host.id) }
            onSaved(host); connect?()
        } catch { self.error = error.localizedDescription }
    }
}
