import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var sync: ConfigurationSync
    @State private var confirmingAccount = false
    var body: some View {
        NavigationStack {
            Form {
                Section("iCloud") {
                    Label(sync.status, systemImage: "icloud")
                    Text("Hosts, SSH key names, AWS profile names, tmux settings, and terminal preferences sync between your devices.")
                    Text("Private keys, AWS credentials, fingerprint trust, and terminal output stay on this device.")
                    if sync.accountChanged {
                        Button("Resume with this iCloud account") { confirmingAccount = true }
                    } else {
                        Button("Check iCloud") { sync.start() }
                    }
                }
                Section("Terminal") {
                    Toggle("Option as Meta", isOn: Binding(get: { store.preferences.optionAsMeta }, set: { enabled in
                        var value = store.preferences; value.optionAsMeta = enabled; store.savePreferences(value)
                    }))
                    Stepper("Text size: \(Int(store.preferences.fontSize)) pt", value: Binding(get: { store.preferences.fontSize }, set: { size in
                        var value = store.preferences; value.fontSize = size; store.savePreferences(value)
                    }), in: 10...28, step: 1)
                }
            }
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .alert("Merge with this iCloud account?", isPresented: $confirmingAccount) {
                Button("Cancel", role: .cancel) {}
                Button("Merge settings") { sync.resumeForCurrentAccount() }
            } message: { Text("Local hosts and settings will merge with the current account. For edits to the same host, the newer edit wins. Credentials stay on this device.") }
        }
    }
}
