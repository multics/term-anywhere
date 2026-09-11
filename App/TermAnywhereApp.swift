import SwiftUI
import TermCore

@main struct TermAnywhereApp: App {
    @StateObject private var store = AppStore()
    var body: some Scene {
        #if os(macOS)
        Window("Term Anywhere", id: "main") {
            MacHostListView().environmentObject(store).frame(minWidth: 850, minHeight: 560)
        }.defaultSize(width: 1080, height: 720)
        Settings { SettingsView(sync: store.configuration).environmentObject(store).frame(width: 520, height: 390) }
        #else
        WindowGroup { HostListView().environmentObject(store) }
        #endif
    }
}

@MainActor final class AppStore: ObservableObject {
    @Published var hosts: [TermCore.Host] = []
    @Published var sessions: [UUID: TerminalSession] = [:]
    @Published var keyNames: [String] = []
    @Published var awsNames: [String] = []
    @Published var error: String?
    @Published private(set) var preferences = TerminalPreferences()
    let vault = KeychainStore()
    let configuration = ConfigurationSync()
    init() {
        apply(configuration.state)
        configuration.onChange = { [weak self] in self?.apply($0) }
        configuration.start()
        do {
            try refreshCredentials()
        } catch { self.error = error.localizedDescription }
    }
    private func apply(_ state: SyncedConfiguration) {
        hosts = state.sortedHosts
        preferences = state.preferences?.value ?? TerminalPreferences()
        for session in sessions.values { session.applyPreferences(preferences) }
    }
    func savePreferences(_ value: TerminalPreferences) {
        do { try configuration.save(preferences: value) } catch { self.error = error.localizedDescription }
    }
    func refreshCredentials() throws {
        keyNames = try vault.accounts(prefix: "key:")
        awsNames = try vault.accounts(prefix: "aws:")
    }
    func save(_ host: TermCore.Host) throws {
        try configuration.save(hosts: [host])
    }
    func importHosts(_ url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        guard data.count <= 2 * 1024 * 1024 else { throw ConnectionError.message("The settings file is too large.") }
        let imported = try JSONDecoder().decode([TermCore.Host].self, from: data)
        try configuration.save(hosts: imported)
    }
    func session(for host: TermCore.Host) -> TerminalSession {
        if let existing = sessions[host.id] {
            // A cloud edit must not interrupt a running terminal.
            if existing.host == host || existing.isLive || existing.isConnecting { return existing }
            existing.disconnect()
        }
        let session = TerminalSession(host: host, store: self); sessions[host.id] = session
        return session
    }
    func closeSession(_ id: UUID) { sessions[id]?.disconnect(); sessions.removeValue(forKey: id) }
}
