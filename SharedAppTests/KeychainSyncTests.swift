import XCTest
import Security
import TermCore

/// Run in the signed app host. Every test uses synthetic values in an isolated service.
final class KeychainSyncTests: XCTestCase {
    private var service = ""
    private var vault: KeychainStore!
    private var legacy: KeychainStore!
    private var group: String!
    override func setUpWithError() throws {
        service = "me.tianyong.term-anywhere.sync-tests." + UUID().uuidString
        group = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "KeychainSyncAccessGroup") as? String)
        vault = KeychainStore(service: service,
            localAccessGroup: Bundle.main.object(forInfoDictionaryKey: "KeychainLocalAccessGroup") as? String,
            syncAccessGroup: group)
        legacy = KeychainStore(service: service)
    }
    override func tearDownWithError() throws {
        for account in ["key:fixture", "aws:fixture", "trust:fixture"] {
            try vault.delete(account: account)
            try vault.delete(account: "device-only:" + account)
            if !account.hasPrefix("trust:") { try vault.delete(account: account, synchronized: true) }
        }
    }
    func testNewCredentialsSyncByDefaultAndLocalChoicePersists() throws {
        let account = "key:fixture"
        try vault.save(Data([1]), account: account)
        XCTAssertEqual(try vault.storage(account: account), .iCloud)
        try vault.setSynchronized(false, account: account)
        try vault.save(Data([2]), account: account)
        XCTAssertEqual(try vault.storage(account: account), .device)
        XCTAssertTrue(try vault.migrateLocalCredentialsToICloud().isEmpty)
        XCTAssertEqual(try vault.storage(account: account), .device)
        try vault.setSynchronized(true, account: account)
        XCTAssertEqual(try vault.storage(account: account), .iCloud)
    }
    func testExplicitLocalImportNeverCreatesSharedItem() throws {
        let account = "aws:fixture"
        try vault.save(Data("synthetic-local-only".utf8), account: account, syncNewItem: false)
        XCTAssertEqual(try vault.storage(account: account), .device)
        XCTAssertTrue(try vault.migrateLocalCredentialsToICloud().isEmpty)
        XCTAssertEqual(try vault.storage(account: account), .device)
    }
    func testDefaultMigrationIncludesLegacyImportsButNotTrust() throws {
        for account in ["key:fixture", "aws:fixture", "trust:fixture"] { try legacy.save(Data([3]), account: account) }
        XCTAssertTrue(try vault.migrateLocalCredentialsToICloud().isEmpty)
        XCTAssertEqual(try vault.storage(account: "key:fixture"), .iCloud)
        XCTAssertEqual(try vault.storage(account: "aws:fixture"), .iCloud)
        XCTAssertEqual(try vault.storage(account: "trust:fixture"), .device)
    }
    func testDefaultMigrationReportsConflictAndPreservesBothCopies() throws {
        try vault.save(Data([1]), account: "key:fixture")
        try legacy.save(Data([2]), account: "key:fixture")
        XCTAssertEqual(try vault.migrateLocalCredentialsToICloud().count, 1)
        XCTAssertEqual(try vault.storage(account: "key:fixture"), .deviceAndICloud)
        XCTAssertEqual(try vault.read(account: "key:fixture"), Data([2]))
    }
    func testLegacyCredentialMigrationAndStoragePreservingUpdate() throws {
        let account = "key:fixture"
        try legacy.save(Data("synthetic-private-key".utf8), account: account)
        XCTAssertEqual(try vault.storage(account: account), .device)
        XCTAssertEqual(try vault.read(account: account), try legacy.read(account: account))
        try vault.setSynchronized(true, account: account)
        XCTAssertNil(try legacy.read(account: account))
        XCTAssertEqual(try vault.storage(account: account), .iCloud)
        XCTAssertEqual(try vault.accounts(prefix: "key:"), ["fixture"])
        // A second vault with the same shared group sees the same credential.
        let peer = KeychainStore(service: service, syncAccessGroup: group)
        XCTAssertEqual(try peer.read(account: account), Data("synthetic-private-key".utf8))
        try vault.save(Data("rotated-synthetic-key".utf8), account: account)
        XCTAssertEqual(try vault.storage(account: account), .iCloud)
        XCTAssertEqual(try peer.read(account: account), Data("rotated-synthetic-key".utf8))
        var result: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account,
            kSecAttrAccessGroup: group!, kSecAttrSynchronizable: true,
            kSecReturnAttributes: true, kSecMatchLimit: kSecMatchLimitOne
        ] as CFDictionary, &result)
        XCTAssertEqual(status, errSecSuccess)
        XCTAssertEqual((result as? [String: Any])?[kSecAttrAccessible as String] as? String, kSecAttrAccessibleWhenUnlocked as String)
        try vault.setSynchronized(false, account: account)
        XCTAssertEqual(try vault.storage(account: account), .device)
        XCTAssertEqual(try legacy.read(account: account), Data("rotated-synthetic-key".utf8))
    }
    func testCloudCollisionKeepsLocalValueUntilExplicitChoice() throws {
        let account = "aws:fixture"
        let cloud = Data("synthetic-cloud-profile".utf8), local = Data("synthetic-local-profile".utf8)
        try vault.save(cloud, account: account); try vault.setSynchronized(true, account: account)
        try legacy.save(local, account: account)
        XCTAssertEqual(try vault.storage(account: account), .deviceAndICloud)
        XCTAssertEqual(try vault.accounts(prefix: "aws:"), ["fixture"])
        XCTAssertEqual(try vault.read(account: account), local)
        XCTAssertThrowsError(try vault.setSynchronized(true, account: account))
        XCTAssertEqual(try vault.storage(account: account), .deviceAndICloud)
        XCTAssertEqual(try legacy.read(account: account), local)
        try vault.useICloudCopy(account: account)
        XCTAssertEqual(try vault.read(account: account), cloud)
        XCTAssertEqual(try vault.storage(account: account), .iCloud)
    }
    func testDisableSyncPreservesEffectiveLocalCopyAndRemovesSharedCopy() throws {
        let account = "aws:fixture"
        try vault.save(Data([1]), account: account); try vault.setSynchronized(true, account: account)
        try legacy.save(Data([2]), account: account)
        try vault.setSynchronized(false, account: account)
        XCTAssertEqual(try vault.storage(account: account), .device)
        XCTAssertEqual(try vault.read(account: account), Data([2]))
    }
    func testIdenticalCopiesCanMergeWithoutReplacingSecret() throws {
        let account = "key:fixture", value = Data("same-synthetic-key".utf8)
        try vault.save(value, account: account); try vault.setSynchronized(true, account: account)
        try legacy.save(value, account: account)
        try vault.setSynchronized(true, account: account)
        XCTAssertEqual(try vault.storage(account: account), .iCloud)
        XCTAssertEqual(try vault.read(account: account), value)
    }
    func testFailedMigrationLeavesLegacyCredentialAvailable() throws {
        let account = "key:fixture", value = Data("synthetic-migration-failure".utf8)
        try legacy.save(value, account: account)
        let invalid = KeychainStore(service: service, syncAccessGroup: "INVALID.not-authorized")
        XCTAssertThrowsError(try invalid.setSynchronized(true, account: account))
        XCTAssertEqual(try legacy.read(account: account), value)
    }
    func testFingerprintTrustCannotSynchronize() throws {
        let account = "trust:fixture"
        try vault.save(Data("synthetic-fingerprint".utf8), account: account)
        XCTAssertThrowsError(try vault.setSynchronized(true, account: account))
        XCTAssertThrowsError(try vault.useICloudCopy(account: account))
        XCTAssertEqual(try vault.storage(account: account), .device)
        XCTAssertEqual(try vault.read(account: account), Data("synthetic-fingerprint".utf8))
    }
}
