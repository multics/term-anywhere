import Foundation
import Security

public struct KeychainStore: Sendable {
    private let service: String
    public init(service: String = "me.tianyong.term-anywhere") { self.service = service }
    public func save(_ data: Data, account: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            item[kSecAttrSynchronizable as String] = false
            try check(SecItemAdd(item as CFDictionary, nil))
        } else { try check(status) }
    }
    public func read(account: String) throws -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }; try check(status)
        return result as? Data
    }
    public func delete(account: String) throws {
        let status = SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account] as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }
    public func accounts(prefix: String) throws -> [String] {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecReturnAttributes as String: true, kSecMatchLimit as String: kSecMatchLimitAll] as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }; try check(status)
        return ((result as? [[String: Any]]) ?? []).compactMap { $0[kSecAttrAccount as String] as? String }.filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }.sorted()
    }
    private func check(_ status: OSStatus) throws {
        if status == errSecMissingEntitlement { throw ConnectionError.message("This build is missing its Keychain signing entitlement. Rebuild and sign the app.") }
        guard status == errSecSuccess else { throw ConnectionError.message("Keychain operation failed (\(status)). Unlock the device and try again.") }
    }
}
