import SwiftUI
import Combine
import TermCore

@main struct TermAnywhereApp: App {
    @StateObject private var store = AppStore()
    var body: some Scene {
        #if os(macOS)
        Window("Term Anywhere", id: "main") {
            MacHostListView().environmentObject(store).frame(minWidth: 850, minHeight: 560)
        }.defaultSize(width: 1080, height: 720)
        Settings { SettingsView(sync: store.configuration).environmentObject(store).frame(width: 560, height: 550) }
        #else
        WindowGroup { HostListView().environmentObject(store) }
        #endif
    }
}

@MainActor final class AppStore: ObservableObject {
    @Published var hosts: [TermCore.Host] = []
    #if os(macOS)
    let externalTerminal = MacTerminalLauncher()
    #endif
    #if os(iOS)
    @Published var sessions: [UUID: TerminalSession] = [:]
    @Published private(set) var selectedHostID: UUID?
    private var sessionObservers: [UUID: AnyCancellable] = [:]
    #endif
    @Published var keyNames: [String] = []
    @Published var awsNames: [String] = []
    @Published var error: String?
    @Published private(set) var preferences = TerminalPreferences()
    @Published var credentialSyncIssues: [String] = []
    @Published var credentialStorage: [String: CredentialStorage] = [:]
    let vault = KeychainStore(
        localAccessGroup: Bundle.main.object(forInfoDictionaryKey: "KeychainLocalAccessGroup") as? String,
        syncAccessGroup: Bundle.main.object(forInfoDictionaryKey: "KeychainSyncAccessGroup") as? String
    )
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
        #if os(iOS)
        for id in Array(sessions.keys) where state.hosts[SyncedConfiguration.hostPrefix + id.uuidString]?.deleted == true { closeSession(id) }
        for session in sessions.values { session.applyPreferences(preferences) }
        #endif
    }
    func savePreferences(_ value: TerminalPreferences) {
        do { try configuration.save(preferences: value) } catch { self.error = error.localizedDescription }
    }
    func refreshCredentials() throws {
        credentialSyncIssues = try vault.migrateLocalCredentialsToICloud()
        let keys = try vault.accounts(prefix: "key:")
        let profiles = try vault.accounts(prefix: "aws:")
        var locations: [String: CredentialStorage] = [:]
        for account in keys.map({ "key:" + $0 }) + profiles.map({ "aws:" + $0 }) {
            locations[account] = try vault.storage(account: account)
        }
        keyNames = keys; awsNames = profiles; credentialStorage = locations
    }
    func save(_ host: TermCore.Host) throws {
        try configuration.save(hosts: [host])
    }
    func removeHost(_ id: UUID) throws { try configuration.removeHost(id) }
    func importHosts(_ url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        guard data.count <= 2 * 1024 * 1024 else { throw ConnectionError.message("The settings file is too large.") }
        let imported = try JSONDecoder().decode([TermCore.Host].self, from: data)
        try configuration.save(hosts: imported)
    }
    #if os(iOS)
    func selectHost(_ id: UUID?) {
        guard let id, let host = hosts.first(where: { $0.id == id }) else {
            selectedHostID = nil
            return
        }
        _ = session(for: host)
        selectedHostID = id
    }
    func session(for host: TermCore.Host) -> TerminalSession {
        if let existing = sessions[host.id] {
            // A cloud edit must not interrupt a running terminal.
            if existing.host == host || existing.isLive || existing.isConnecting { return existing }
            existing.disconnect()
        }
        let session = TerminalSession(host: host, store: self); sessions[host.id] = session
        sessionObservers[host.id] = session.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        return session
    }
    func closeSession(_ id: UUID) {
        if selectedHostID == id { selectedHostID = nil }
        sessions[id]?.disconnect()
        sessions.removeValue(forKey: id)
        sessionObservers.removeValue(forKey: id)
    }
    #endif
}
