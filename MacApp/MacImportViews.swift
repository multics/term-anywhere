import SwiftUI
import AppKit
import TermCore

private func chooseFile(_ current: URL) -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = false; panel.allowsMultipleSelection = false; panel.showsHiddenFiles = true
    panel.directoryURL = current.deletingLastPathComponent()
    return panel.runModal() == .OK ? panel.url : nil
}

struct MacSSHImportView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var config = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/config")
    @State private var names = ""
    @State private var hosts: [TermCore.Host] = []
    @State private var selected: Set<UUID> = []
    @State private var messages: [String] = []
    @State private var loading = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Import SSH hosts").font(.title2.bold())
            HStack { Text(config.path).font(.caption).textSelection(.enabled); Spacer(); Button("Choose config…") { if let url = chooseFile(config) { config = url; readNames() } }.disabled(loading) }
            TextField("SSH aliases, separated by spaces", text: $names).disabled(loading)
            Text("Names below come from this file. You can also enter aliases from Include files. OpenSSH resolves each selected alias; no connection is opened.").font(.caption).foregroundStyle(.secondary)
            Button("Preview hosts") { preview() }.disabled(loading || names.isEmpty)
            if loading { ProgressView() }
            List(hosts) { host in
                Toggle(isOn: Binding(get: { selected.contains(host.id) }, set: { if $0 { selected.insert(host.id) } else { selected.remove(host.id) } })) {
                    VStack(alignment: .leading) {
                        Text(host.name).font(.headline)
                        Text("\(host.username)@\(host.address):\(host.port) · key: \(host.keyID)" + (host.isSSM ? " · AWS: " + host.awsProfile : "")).font(.caption).textSelection(.enabled)
                    }
                }.toggleStyle(.checkbox)
            }.frame(minHeight: 180)
            if !messages.isEmpty { ScrollView { Text(messages.joined(separator: "\n")).font(.caption).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 100) }
            Text("Import saves host settings and syncs them through iCloud. Private keys and AWS credentials are imported separately.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Import \(selected.count) hosts") {
                    do { try store.configuration.save(hosts: hosts.filter { selected.contains($0.id) }); dismiss() }
                    catch { messages = [error.localizedDescription] }
                }.buttonStyle(.borderedProminent).disabled(selected.isEmpty || loading)
            }
        }.padding(24).frame(width: 720, height: 560).onAppear { readNames() }
    }
    private func readNames() {
        hosts = []; selected = []; messages = []
        do { names = MacConfigurationImport.aliases(in: try String(contentsOf: config, encoding: .utf8)).joined(separator: " ") }
        catch { messages = ["Choose your SSH config or enter aliases to resolve."] }
    }
    private func preview() {
        loading = true; hosts = []; selected = []; messages = []
        let aliases = Set(names.split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init)).sorted()
        Task {
            for name in aliases {
                do { let host = try await MacConfigurationImport.resolve(alias: name, config: config); hosts.append(host); selected.insert(host.id) }
                catch { messages.append(error.localizedDescription) }
            }
            loading = false
        }
    }
}

struct MacAWSImportView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".aws/credentials")
    @State private var profiles: [String: AWSCredentials] = [:]
    @State private var syncNewProfiles = true
    @State private var selected: Set<String> = []
    @State private var message: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import AWS profiles").font(.title2.bold())
            HStack { Text(file.path).font(.caption).textSelection(.enabled); Spacer(); Button("Choose file…") { if let url = chooseFile(file) { file = url; read() } } }
            Text("Select static profiles to store in this Mac’s Keychain. New profiles use iCloud Keychain by default. Turn off the switch to keep new profiles on this Mac. Replacing a synced profile updates its shared copy. SSO, role assumption, and credential_process are not imported.").font(.callout)
            Toggle("Sync new profiles with iCloud Keychain", isOn: $syncNewProfiles)
            List(profiles.keys.sorted(), id: \.self) { name in
                Toggle(name, isOn: Binding(get: { selected.contains(name) }, set: { if $0 { selected.insert(name) } else { selected.remove(name) } })).toggleStyle(.checkbox)
            }
            if let message { Text(message).font(.caption) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Import selected profiles") {
                    do {
                        for name in selected.sorted() { try store.vault.save(JSONEncoder().encode(profiles[name]!), account: "aws:" + name, syncNewItem: syncNewProfiles) }
                        try store.refreshCredentials(); dismiss()
                    } catch { message = error.localizedDescription }
                }.buttonStyle(.borderedProminent).disabled(selected.isEmpty)
            }
        }.padding(24).frame(width: 590, height: 440).onAppear { read() }
    }
    private func read() {
        profiles = [:]; selected = []; message = nil
        do {
            let data = try Data(contentsOf: file)
            guard data.count <= 512 * 1024, let text = String(data: data, encoding: .utf8) else { throw ConnectionError.message("Choose a small UTF-8 AWS credentials file.") }
            profiles = MacConfigurationImport.awsProfiles(in: text)
            if profiles.isEmpty { message = "No static credentials found in this file." }
        } catch { message = "Cannot read the AWS file. Choose your credentials file." }
    }
}
