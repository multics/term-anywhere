import SwiftUI

struct TmuxSessionPicker: View {
    @ObservedObject var session: TerminalSession
    @State private var newName = ""
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(session.availableTmuxSessions, id: \.self) { name in
                        Button { session.selectTmuxSession(name) } label: {
                            HStack {
                                Label(name, systemImage: "rectangle.split.2x1")
                                Spacer()
                                if name == session.host.tmuxSession { Image(systemName: "checkmark").accessibilityLabel("Last selection") }
                            }
                        }
                    }
                } header: { Text("On \(session.host.name)") } footer: { Text(session.tmuxDiscoveryMessage) }
                Section {
                    Button("Open plain shell", systemImage: "terminal") { session.selectTmuxSession("") }
                } footer: { Text("The choice is saved for this host entry and used on the next connection. A plain shell does not provide tmux session recovery.") }
                if session.tmuxAvailable {
                    Section("New tmux session") {
                        TextField("Session name", text: $newName)
                        Button("Create and connect", systemImage: "plus") { session.selectTmuxSession(newName.trimmingCharacters(in: .whitespaces), create: true) }
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                if !session.host.tmuxSession.isEmpty {
                    Text("Last selection: \(session.host.tmuxSession)").font(.caption).foregroundStyle(.secondary)
                }
                if let error = session.tmuxSelectionError { Text(error).foregroundStyle(.red) }
            }
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .navigationTitle("Choose a session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { session.cancelTmuxSelection() } } }
        }.presentationDetents([.medium, .large])
    }
}
