import SwiftUI

struct MacTerminalSettings: View {
    @ObservedObject var launcher: MacTerminalLauncher
    var body: some View {
        Section("Mac connections") {
            Picker("Default terminal", selection: $launcher.defaultID) {
                ForEach(launcher.applications) { app in Text(app.name).tag(app.id) }
            }
            Button("Refresh installed terminals") { launcher.refresh() }
            Text("Connect opens the selected app. This choice stays on this Mac. SSH trust and passphrase prompts appear in that terminal.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
