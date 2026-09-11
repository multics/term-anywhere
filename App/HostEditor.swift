import SwiftUI
import TermCore

struct HostEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var host: Host
    @State private var useSSM = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    TextField("Name", text: $host.name)
                    Toggle("Connect through AWS SSM", isOn: $useSSM)
                    TextField(useSSM ? "EC2 instance ID" : "Hostname or address", text: $host.address)
                    TextField("User", text: $host.username)
                    LabeledContent("SSH port") { TextField("22", value: $host.port, format: .number).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                    TextField("SSH key name", text: $host.keyID)
                    if !store.keyNames.isEmpty {
                        Menu("Choose an imported key") { ForEach(store.keyNames, id: \.self) { name in Button(name) { host.keyID = name } } }
                    }
                }
                if useSSM {
                    Section("AWS") {
                        TextField("Credential profile", text: $host.awsProfile)
                        TextField("Region", text: $host.region)
                        if !store.awsNames.isEmpty { Menu("Choose AWS credentials") { ForEach(store.awsNames, id: \.self) { name in Button(name) { host.awsProfile = name } } } }
                    }
                }
                Section {
                    TextField("tmux session (empty for plain shell)", text: $host.tmuxSession)
                    DisclosureGroup("Advanced tmux settings") {
                        TextField("Socket path (optional)", text: $host.tmuxSocket)
                        TextField("Fallback prefix, for example C-a", text: $host.manualPrefix)
                    }
                } header: { Text("Session recovery") } footer: {
                    Text("The app reads this server’s active tmux shortcuts each time it connects. The named session remains on the server when you disconnect.")
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .navigationTitle(store.hosts.contains(where: { $0.id == host.id }) ? "Edit host" : "Add host")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    do {
                        if !useSSM { host.awsProfile = "" }
                        else if host.awsProfile.isEmpty { throw ConnectionError.message("Select an AWS credential profile.") }
                        try store.save(host); store.closeSession(host.id); dismiss()
                    } catch { self.error = error.localizedDescription }
                } }
            }
        }.onAppear { useSSM = host.isSSM }
    }
}
