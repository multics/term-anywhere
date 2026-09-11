import SwiftUI
import UniformTypeIdentifiers
import TermCore

struct CredentialsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var importingKey = false
    @State private var syncNewKeys = true
    @State private var syncNewProfiles = true
    @State private var keyName = ""
    @State private var profile = ""
    @State private var accessKey = ""
    @State private var secretKey = ""
    @State private var token = ""
    @State private var message: String?
    @State private var pendingChange: CredentialChange?
    #if os(macOS)
    @State private var importingAWS = false
    #endif
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(store.keyNames, id: \.self) { name in credentialRow(name, prefix: "key:", icon: "key.fill") }
                    Toggle("Sync new keys with iCloud Keychain", isOn: $syncNewKeys)
                    TextField("Name for imported key", text: $keyName)
                    #if os(macOS)
                    Button("Import private key", systemImage: "square.and.arrow.down") {
                        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
                        panel.showsHiddenFiles = true
                        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
                        if panel.runModal() == .OK, let url = panel.url { importKey(url) }
                    }
                    #else
                    Button("Import private key", systemImage: "square.and.arrow.down") { importingKey = true }.disabled(keyName.trimmingCharacters(in: .whitespaces).isEmpty)
                    #endif
                } header: { Text("SSH keys") } footer: { Text("Keys use iCloud Keychain by default. Turn off the switch to keep a new key on this device. Replacing a synced key updates its shared copy. Enter encrypted-key passphrases when connecting.") }
                Section {
                    #if os(macOS)
                    Button("Import AWS profiles from this Mac…") { importingAWS = true }
                    #endif
                    ForEach(store.awsNames, id: \.self) { name in credentialRow(name, prefix: "aws:", icon: "cloud") }
                    Toggle("Sync new profiles with iCloud Keychain", isOn: $syncNewProfiles)
                    TextField("Profile name", text: $profile)
                    SecureField("Access key ID", text: $accessKey)
                    SecureField("Secret access key", text: $secretKey)
                    SecureField("Session token (if required)", text: $token)
                    Button("Save AWS credentials") {
                        do {
                            let value = AWSCredentials(accessKeyID: accessKey.trimmingCharacters(in: .whitespacesAndNewlines), secretAccessKey: secretKey.trimmingCharacters(in: .whitespacesAndNewlines), sessionToken: token.isEmpty ? nil : token)
                            try store.vault.save(JSONEncoder().encode(value), account: "aws:" + profile, syncNewItem: syncNewProfiles)
                            try store.refreshCredentials(); accessKey = ""; secretKey = ""; token = ""; message = "AWS credentials saved."
                        } catch { message = error.localizedDescription }
                    }.disabled(profile.isEmpty || accessKey.isEmpty || secretKey.isEmpty)
                } header: { Text("AWS credentials") } footer: { Text("Profiles use iCloud Keychain by default. The switch applies to new profiles. Replacing a credential that uses iCloud Keychain updates its shared copy. Temporary credentials still expire.") }
                Section("iCloud Keychain") {
                    Text("Enable Passwords & Keychain in iCloud settings on each device, using the same Apple Account. Apple controls delivery; the storage label does not confirm arrival on another device.")
                    Button("Refresh credentials", systemImage: "arrow.clockwise") { refresh() }
                    ForEach(store.credentialSyncIssues, id: \.self) { Text($0).font(.callout).foregroundStyle(.red) }
                }
                if let message { Text(message).font(.callout).textSelection(.enabled) }
            }
            #if os(iOS)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .navigationBarTitleDisplayMode(.inline)
            #else
            .formStyle(.grouped)
            .sheet(isPresented: $importingAWS) { MacAWSImportView().environmentObject(store) }
            #endif
            .navigationTitle("Keys and AWS")
            .onAppear { refresh() }
            .alert(item: $pendingChange) { change in
                let confirm: Alert.Button = change.operation == .enable
                    ? .default(Text(change.action)) { changeStorage(change) }
                    : .destructive(Text(change.action)) { changeStorage(change) }
                return Alert(title: Text(change.title), message: Text(change.explanation), primaryButton: confirm, secondaryButton: .cancel())
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .fileImporter(isPresented: $importingKey, allowedContentTypes: [.data, .plainText]) { result in
                do { importKey(try result.get()) } catch { message = error.localizedDescription }
            }
        }
    }
    private func changeStorage(_ change: CredentialChange) {
        do {
            switch change.operation {
            case .enable: try store.vault.setSynchronized(true, account: change.account)
            case .disable: try store.vault.setSynchronized(false, account: change.account)
            case .useCloud: try store.vault.useICloudCopy(account: change.account)
            }
            try store.refreshCredentials()
            message = "Storage updated. iCloud delivery can take time."
        } catch { refresh(); message = error.localizedDescription }
    }
    private func refresh() {
        do { try store.refreshCredentials() } catch { message = error.localizedDescription }
    }
    private func credentialRow(_ name: String, prefix: String, icon: String) -> some View {
        let account = prefix + name
        let storage = store.credentialStorage[account] ?? .device
        return HStack {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                    Text(storage.rawValue).font(.caption).foregroundStyle(.secondary)
                }
            } icon: { Image(systemName: icon) }
            Spacer()
            Menu {
                if storage != .iCloud {
                    Button("Enable iCloud Keychain") { pendingChange = CredentialChange(account: account, name: name, operation: .enable) }
                }
                Button("Keep on this device only…") { pendingChange = CredentialChange(account: account, name: name, operation: .disable) }
                if storage == .deviceAndICloud {
                    Button("Use iCloud copy on this device…") { pendingChange = CredentialChange(account: account, name: name, operation: .useCloud) }
                }
            } label: { Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44) }
            .accessibilityLabel("Storage for \(name)")
        }
    }
    private func importKey(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            guard data.count <= 128 * 1024, let text = String(data: data, encoding: .utf8), text.contains("PRIVATE KEY-----") else { throw ConnectionError.message("Choose an OpenSSH or PEM private-key file.") }
            let name = keyName.trimmingCharacters(in: .whitespaces)
            try store.vault.save(data, account: "key:" + (name.isEmpty ? url.lastPathComponent : name), syncNewItem: syncNewKeys)
            try store.refreshCredentials(); message = "SSH key imported."; keyName = ""
        } catch { message = error.localizedDescription }
    }
}

private struct CredentialChange: Identifiable {
    enum Operation { case enable, disable, useCloud }
    let account: String
    let name: String
    let operation: Operation
    var id: String { account }
    var title: String {
        switch operation {
        case .enable: return "Sync \(name)?"
        case .disable: return "Keep \(name) on this device only?"
        case .useCloud: return "Use the iCloud copy of \(name)?"
        }
    }
    var explanation: String {
        switch operation {
        case .enable: return "This credential will use iCloud Keychain on your devices. An existing, different cloud copy will not be replaced. Server fingerprint trust stays on each device."
        case .disable: return "Keep the copy used on this device, then delete the shared copy. Other devices can lose access when this deletion arrives. Separate local copies remain. This does not revoke the key or AWS credentials on the server."
        case .useCloud: return "Delete this device’s separate copy and use the credential from iCloud Keychain. Future shared changes will apply here."
        }
    }
    var action: String {
        switch operation {
        case .enable: return "Enable sync"
        case .disable: return "Keep local and remove shared"
        case .useCloud: return "Use iCloud copy"
        }
    }
}
