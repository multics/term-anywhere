import SwiftUI
import Combine
import TermCore

@main struct TermAnywhereApp: App {
    @StateObject private var store = AppStore()
    var body: some Scene {
        #if os(macOS)
        Window("Term Anywhere", id: "main") {
            MacHostListView().environmentObject(store).preferredColorScheme(store.colorScheme).frame(minWidth: 850, minHeight: 560)
        }.defaultSize(width: 1080, height: 720)
        Settings { SettingsView(sync: store.configuration).environmentObject(store).preferredColorScheme(store.colorScheme).frame(width: 560, height: 550) }
        #else
        WindowGroup { HostListView().environmentObject(store).preferredColorScheme(store.colorScheme) }
        #endif
    }
}

@MainActor final class AppStore: ObservableObject {
    @Published var hosts: [TermCore.Host] = []
    #if os(macOS)
    let externalTerminal = MacTerminalLauncher()
    #endif
    #if os(iOS)
    @Published private(set) var tabs: [UUID: [TerminalSession]] = [:]
    @Published private var activeTabIDs: [UUID: UUID] = [:]
    var sessions: [UUID: TerminalSession] {
        tabs.compactMapValues { group in group.first { activeTabIDs[$0.host.id] == $0.id } ?? group.first }
    }
    var allSessions: [TerminalSession] { tabs.values.flatMap { $0 } }
    @Published private(set) var selectedHostID: UUID?
    private var sessionObservers: [UUID: AnyCancellable] = [:]
    #endif
    @Published var keyNames: [String] = []
    @Published var awsNames: [String] = []
    @Published var error: String?
    @Published private(set) var preferences = TerminalPreferences()
    var colorScheme: ColorScheme? {
        switch preferences.appearance { case .system: nil; case .light: .light; case .dark: .dark }
    }
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
        for session in allSessions { session.applyPreferences(preferences) }
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
    func moveHosts(from offsets: IndexSet, to destination: Int) {
        guard offsets.allSatisfy({ hosts.indices.contains($0) }), (0...hosts.count).contains(destination) else { return }
        var reordered = hosts; reordered.move(fromOffsets: offsets, toOffset: destination)
        do { try configuration.saveHostOrder(reordered.map(\.id)) } catch { self.error = error.localizedDescription }
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
        if let existing = sessions[host.id] { return existing }
        return addTab(host: host)
    }
    private func addTab(host: TermCore.Host, create: Bool = false) -> TerminalSession {
        let session = TerminalSession(host: host, store: self)
        session.createTmuxOnConnect = create
        tabs[host.id, default: []].append(session)
        sessionObservers[session.id] = session.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        selectTab(session)
        return session
    }
    @discardableResult func openTab(from source: TerminalSession, name: String, create: Bool = false) throws -> TerminalSession {
        guard tabs[source.host.id]?.contains(where: { $0 === source }) == true,
              hosts.contains(where: { $0.id == source.host.id }) else { throw ConnectionError.message("This host is no longer open.") }
        // Keep the endpoint that supplied the session list, even during a cloud edit.
        var host = source.host; host.tmuxSession = name; host.tmuxSelectionMade = true
        try host.validate()
        if let existing = tabs[host.id]?.first(where: { $0.host.tmuxSession == name && $0.host.tmuxSelectionMade == true }) {
            selectTab(existing); return existing
        }
        return addTab(host: host, create: create)
    }
    func selectTab(_ session: TerminalSession) {
        guard tabs[session.host.id]?.contains(where: { $0 === session }) == true else { return }
        if let previous = sessions[session.host.id], previous !== session {
            session.inheritPresentation(from: previous)
            previous.stopScrolling()
            previous.hideKeyboard()
        }
        activeTabIDs[session.host.id] = session.id
        if session.isLive { rememberSession(session) }
    }
    func stepTab(for hostID: UUID, by offset: Int) {
        guard let group = tabs[hostID], group.count > 1,
              let index = group.firstIndex(where: { $0.id == activeTabIDs[hostID] }) else { return }
        selectTab(group[(index + offset + group.count) % group.count])
    }
    func rememberSession(_ session: TerminalSession) {
        guard sessions[session.host.id] === session,
              var saved = hosts.first(where: { $0.id == session.host.id }) else { return }
        guard saved.tmuxSession != session.host.tmuxSession || saved.tmuxSelectionMade != true else { return }
        saved.tmuxSession = session.host.tmuxSession; saved.tmuxSelectionMade = true
        do { try save(saved) } catch { self.error = error.localizedDescription }
    }
    func closeTab(_ session: TerminalSession) {
        let hostID = session.host.id
        guard let group = tabs[hostID], let index = group.firstIndex(where: { $0 === session }) else { return }
        if group.count == 1 { closeSession(hostID); return }
        if sessions[hostID] === session {
            selectTab(group[index == group.count - 1 ? index - 1 : index + 1])
        }
        session.disconnect()
        tabs[hostID]?.removeAll { $0 === session }
        sessionObservers.removeValue(forKey: session.id)
    }
    func closeSession(_ id: UUID) {
        if selectedHostID == id { selectedHostID = nil }
        for session in tabs[id] ?? [] {
            session.disconnect()
            sessionObservers.removeValue(forKey: session.id)
        }
        tabs.removeValue(forKey: id); activeTabIDs.removeValue(forKey: id)
    }
    #endif
}
