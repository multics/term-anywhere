import Foundation
import Combine
import TermCore

@MainActor final class ConfigurationSync: NSObject, ObservableObject {
    @Published private(set) var state = SyncedConfiguration()
    @Published private(set) var status = "Saved on this device."
    @Published private(set) var accountChanged = false
    var onChange: ((SyncedConfiguration) -> Void)?
    private let cloud = NSUbiquitousKeyValueStore.default
    private let defaults = UserDefaults.standard
    private static var directory: URL {
        #if os(macOS)
        URL.applicationSupportDirectory.appendingPathComponent("TermAnywhere", isDirectory: true)
        #else
        URL.applicationSupportDirectory
        #endif
    }
    private let file = ConfigurationSync.directory.appendingPathComponent("configuration-v1.json")
    private var loaded = false

    override init() {
        super.init()
        do {
            if FileManager.default.fileExists(atPath: file.path) {
                state = try JSONDecoder().decode(SyncedConfiguration.self, from: Data(contentsOf: file))
            } else {
                let old = Self.directory.appendingPathComponent("hosts.json")
                if FileManager.default.fileExists(atPath: old.path) {
                    let hosts = try JSONDecoder().decode([TermCore.Host].self, from: Data(contentsOf: old))
                    // Old local settings have no revision. An existing cloud revision takes priority.
                    for host in hosts { try state.save(host, modified: Date(timeIntervalSince1970: 0)) }
                }
                try persist(state)
            }
            loaded = true
        } catch { status = "Cannot read saved settings. iCloud sync is paused." }
        accountChanged = defaults.bool(forKey: "sync.accountChanged")
        NotificationCenter.default.addObserver(self, selector: #selector(cloudChanged(_:)), name: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud)
    }
    func start() {
        guard loaded else { return }
        guard !accountChanged else { status = "iCloud account changed. Sync is paused."; return }
        // KVS remains usable without a document-container identity token. Apple queues
        // changes while signed out and transfers them when an account is available.
        // This requests synchronization; it does not confirm delivery to another device.
        guard cloud.synchronize() else { status = "iCloud unavailable. Saved on this device."; return }
        reconcile()
    }
    func save(hosts: [TermCore.Host]) throws {
        guard loaded else { throw ConnectionError.message(status) }
        var next = state
        for host in hosts { try next.save(host) }
        try persist(next); state = next; onChange?(next)
        start()
    }
    func removeHost(_ id: UUID) throws {
        guard loaded else { throw ConnectionError.message(status) }
        var next = state; next.removeHost(id: id)
        try persist(next); state = next; onChange?(next)
        start()
    }
    func save(preferences: TerminalPreferences) throws {
        guard loaded else { throw ConnectionError.message(status) }
        var next = state; try next.save(preferences)
        try persist(next); state = next; onChange?(next)
        start()
    }
    private func persist(_ value: SyncedConfiguration) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(macOS)
        try JSONEncoder().encode(value).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        #else
        try JSONEncoder().encode(value).write(to: file, options: [.atomic, .completeFileProtection])
        #endif
    }
    private func reconcile() {
        guard loaded, !accountChanged else { return }
        do {
            let remote = cloud.dictionaryRepresentation
            var next = state
            for (key, value) in remote where key.hasPrefix(SyncedConfiguration.hostPrefix) || key == SyncedConfiguration.preferencesKey {
                guard let data = value as? Data else { throw ConnectionError.message("iCloud settings have an unsupported format.") }
                try next.merge(key: key, data: data)
            }
            // Persist the merge before publishing or changing the UI.
            try persist(next)
            if next != state { state = next; onChange?(next) }
            let records = try next.encodedRecords()
            var projected = remote
            for (key, data) in records { projected[key] = data }
            let bytes = try PropertyListSerialization.data(fromPropertyList: projected, format: .binary, options: 0).count
            guard projected.count <= 1000, bytes <= 900_000 else {
                status = "iCloud settings limit reached. Changes are saved on this device."; return
            }
            for (key, data) in records where (remote[key] as? Data) != data { cloud.set(data, forKey: key) }
            status = "Saved locally. iCloud syncs when available."
        } catch { status = "iCloud sync paused: " + error.localizedDescription }
    }
    @objc private func cloudChanged(_ notification: Notification) {
        let reason = notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
        if reason == NSUbiquitousKeyValueStoreAccountChange { pauseForAccountChange(); return }
        if reason == NSUbiquitousKeyValueStoreQuotaViolationChange {
            status = "iCloud settings limit reached. Changes are saved on this device."; return
        }
        if reason == NSUbiquitousKeyValueStoreInitialSyncChange || reason == NSUbiquitousKeyValueStoreServerChange {
            reconcile()
        }
    }
    private func pauseForAccountChange() {
        accountChanged = true; defaults.set(true, forKey: "sync.accountChanged")
        status = "iCloud account changed. Sync is paused."
    }
    func resumeForCurrentAccount() {
        accountChanged = false; defaults.set(false, forKey: "sync.accountChanged"); start()
    }
    deinit { NotificationCenter.default.removeObserver(self) }
}
