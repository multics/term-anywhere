import Foundation
import Security

public enum CredentialStorage: String, Sendable {
    case device = "This device"
    case iCloud = "iCloud Keychain"
    case deviceAndICloud = "This device + iCloud"
}

public struct KeychainStore: Sendable {
    private let service: String
    private let localAccessGroup: String?
    private let syncAccessGroup: String?
    public init(service: String = "me.tianyong.term-anywhere", localAccessGroup: String? = nil, syncAccessGroup: String? = nil) {
        self.service = service; self.localAccessGroup = localAccessGroup; self.syncAccessGroup = syncAccessGroup
    }

    /// New credentials use iCloud by default. Existing items retain their effective scope.
    public func save(_ data: Data, account: String, syncNewItem: Bool = true) throws {
        let location = try storage(account: account)
        let synchronized: Bool
        if let location { synchronized = location == .iCloud }
        else {
            if canSynchronize(account) && !syncNewItem { try markDeviceOnly(account) }
            synchronized = try canSynchronize(account) && syncNewItem && !isDeviceOnly(account)
        }
        let query = try query(account: account, synchronized: synchronized)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound { try add(data, account: account, synchronized: synchronized) }
        else { try check(status) }
    }

    /// The default also applies to legacy imports. Explicit local choices persist on this device.
    public func migrateLocalCredentialsToICloud() throws -> [String] {
        guard syncAccessGroup != nil else { return [] }
        var issues: [String] = []
        for account in try accountNames(synchronized: false).sorted() where canSynchronize(account) {
            do {
                if try !isDeviceOnly(account) { try setSynchronized(true, account: account) }
            } catch { issues.append("\(String(account.dropFirst(4))): \(error.localizedDescription)") }
        }
        return issues
    }

    /// An existing local copy takes precedence; incoming cloud items never replace it silently.
    public func read(account: String) throws -> Data? {
        if let local = try read(account: account, synchronized: false) { return local }
        guard canSynchronize(account) else { return nil }
        return try read(account: account, synchronized: true)
    }

    public func storage(account: String) throws -> CredentialStorage? {
        let local = try accountNames(synchronized: false).contains(account)
        let cloud = try canSynchronize(account) && accountNames(synchronized: true).contains(account)
        if local && cloud { return .deviceAndICloud }
        return local ? .device : (cloud ? .iCloud : nil)
    }

    public func setSynchronized(_ enabled: Bool, account: String) throws {
        guard canSynchronize(account) else { throw ConnectionError.message("Only SSH keys and AWS profiles can use the shared iCloud Keychain in this build.") }
        let local = try read(account: account, synchronized: false)
        let cloud = try read(account: account, synchronized: true)
        guard let value = local ?? cloud else { throw ConnectionError.message("This credential is no longer available. Refresh the list.") }
        if enabled {
            // Never update a same-name cloud item during migration. A collision leaves both copies intact.
            try copyIfAbsent(value, account: account, synchronized: true)
            try delete(account: "device-only:" + account, synchronized: false)
            try delete(account: account, synchronized: false)
        } else {
            // Keep the effective (local-first) value before deleting the shared copy on all devices.
            try copyIfAbsent(value, account: account, synchronized: false)
            try markDeviceOnly(account)
            try delete(account: account, synchronized: true)
        }
    }

    public func useICloudCopy(account: String) throws {
        guard canSynchronize(account), try read(account: account, synchronized: true) != nil else {
            throw ConnectionError.message("The iCloud copy is not available on this device yet.")
        }
        try delete(account: "device-only:" + account, synchronized: false)
        try delete(account: account, synchronized: false)
    }

    /// Deletion is explicitly scoped. The default never deletes a shared item.
    public func delete(account: String, synchronized: Bool = false) throws {
        let status = SecItemDelete(try query(account: account, synchronized: synchronized) as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }

    public func accounts(prefix: String) throws -> [String] {
        let local = try accountNames(synchronized: false)
        let cloud = try syncAccessGroup == nil ? [] : accountNames(synchronized: true).filter { canSynchronize($0) }
        return Set(local + cloud).filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }.sorted()
    }

    private func isDeviceOnly(_ account: String) throws -> Bool {
        try read(account: "device-only:" + account, synchronized: false) != nil
    }
    private func markDeviceOnly(_ account: String) throws {
        if try !isDeviceOnly(account) { try add(Data([1]), account: "device-only:" + account, synchronized: false) }
    }

    private func canSynchronize(_ account: String) -> Bool {
        syncAccessGroup != nil && (account.hasPrefix("key:") || account.hasPrefix("aws:"))
    }

    private func query(account: String? = nil, synchronized: Bool) throws -> [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrSynchronizable as String: synchronized]
        if let account { query[kSecAttrAccount as String] = account }
        if synchronized {
            guard let syncAccessGroup, account == nil || canSynchronize(account!) else {
                throw ConnectionError.message("This item cannot use iCloud Keychain.")
            }
            query[kSecAttrAccessGroup as String] = syncAccessGroup
            #if os(macOS)
            query[kSecUseDataProtectionKeychain as String] = true
            #endif
        } else {
            #if os(macOS)
            // Preserve access to credentials saved by the original Mac app in the login Keychain.
            query[kSecUseDataProtectionKeychain as String] = false
            #else
            if let localAccessGroup { query[kSecAttrAccessGroup as String] = localAccessGroup }
            #endif
        }
        return query
    }

    private func read(account: String, synchronized: Bool) throws -> Data? {
        var query = try query(account: account, synchronized: synchronized)
        query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }; try check(status)
        guard let data = result as? Data else { throw ConnectionError.message("Keychain returned an unreadable credential.") }
        return data
    }

    private func add(_ data: Data, account: String, synchronized: Bool) throws {
        var item = try query(account: account, synchronized: synchronized)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = synchronized ? kSecAttrAccessibleWhenUnlocked : kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        try check(SecItemAdd(item as CFDictionary, nil))
    }

    private func copyIfAbsent(_ data: Data, account: String, synchronized: Bool) throws {
        if try read(account: account, synchronized: synchronized) == nil {
            do { try add(data, account: account, synchronized: synchronized) }
            catch {
                // A concurrent arrival may have created the destination. Accept only an identical copy.
                guard try read(account: account, synchronized: synchronized) == data else { throw error }
            }
        }
        guard try read(account: account, synchronized: synchronized) == data else {
            throw ConnectionError.message("A different credential already uses this name in iCloud Keychain. Both copies were kept. Use the iCloud copy, or import the device copy under a different name before enabling sync.")
        }
    }

    private func accountNames(synchronized: Bool) throws -> [String] {
        var query = try query(synchronized: synchronized)
        query[kSecReturnAttributes as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }; try check(status)
        return ((result as? [[String: Any]]) ?? []).compactMap { $0[kSecAttrAccount as String] as? String }
    }

    private func check(_ status: OSStatus) throws {
        if status == errSecMissingEntitlement { throw ConnectionError.message("This build is missing its Keychain signing entitlement. Rebuild and sign the app.") }
        guard status == errSecSuccess else { throw ConnectionError.message("Keychain operation failed (\(status)). Unlock the device and try again.") }
    }
}
