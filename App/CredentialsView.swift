import SwiftUI
import UniformTypeIdentifiers
import TermCore

struct CredentialsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var importingKey = false
    @State private var keyName = ""
    @State private var profile = ""
    @State private var accessKey = ""
    @State private var secretKey = ""
    @State private var token = ""
    @State private var message: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(store.keyNames, id: \.self) { name in Label(name, systemImage: "key.fill") }
                    TextField("Name for imported key", text: $keyName)
                    Button("Import private key", systemImage: "square.and.arrow.down") { importingKey = true }.disabled(keyName.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: { Text("SSH keys") } footer: { Text("Keys are stored on this device. If a key is encrypted, enter its passphrase when connecting.") }
                Section {
                    ForEach(store.awsNames, id: \.self) { name in Label(name, systemImage: "cloud") }
                    TextField("Profile name", text: $profile)
                    SecureField("Access key ID", text: $accessKey)
                    SecureField("Secret access key", text: $secretKey)
                    SecureField("Session token (if required)", text: $token)
                    Button("Save AWS credentials") {
                        do {
                            let value = AWSCredentials(accessKeyID: accessKey.trimmingCharacters(in: .whitespacesAndNewlines), secretAccessKey: secretKey.trimmingCharacters(in: .whitespacesAndNewlines), sessionToken: token.isEmpty ? nil : token)
                            try store.vault.save(JSONEncoder().encode(value), account: "aws:" + profile)
                            try store.refreshCredentials(); accessKey = ""; secretKey = ""; token = ""; message = "AWS credentials saved."
                        } catch { message = error.localizedDescription }
                    }.disabled(profile.isEmpty || accessKey.isEmpty || secretKey.isEmpty)
                } header: { Text("AWS credentials") } footer: { Text("Use the profile name from your imported connection. Temporary credentials must be replaced when they expire.") }
                if let message { Text(message).font(.callout) }
            }
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .navigationTitle("Keys and AWS").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .fileImporter(isPresented: $importingKey, allowedContentTypes: [.data, .plainText]) { result in
                do {
                    let url = try result.get(), scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let data = try Data(contentsOf: url)
                    guard data.count <= 128 * 1024, let text = String(data: data, encoding: .utf8), text.contains("PRIVATE KEY-----") else { throw ConnectionError.message("Choose an OpenSSH or PEM private-key file.") }
                    try store.vault.save(data, account: "key:" + keyName.trimmingCharacters(in: .whitespaces))
                    try store.refreshCredentials(); message = "SSH key imported."; keyName = ""
                } catch { message = error.localizedDescription }
            }
        }
    }
}
