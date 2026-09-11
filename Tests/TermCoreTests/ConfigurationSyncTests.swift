import XCTest
@testable import TermCore

final class ConfigurationSyncTests: XCTestCase {
    private func host(_ name: String) -> TermCore.Host { TermCore.Host(name: name, address: "example.invalid", username: "user", keyID: "local-key") }
    private func merged(_ local: SyncedConfiguration, _ remote: SyncedConfiguration) throws -> SyncedConfiguration {
        var result = local
        for (key, data) in try remote.encodedRecords() { try result.merge(key: key, data: data) }
        return result
    }
    func testIndependentOfflineEditsSurviveInBothDirections() throws {
        var phone = SyncedConfiguration(), pad = SyncedConfiguration()
        try phone.save(host("phone")); try pad.save(host("pad"))
        XCTAssertEqual(try merged(phone, pad), try merged(pad, phone))
        XCTAssertEqual(try merged(phone, pad).hosts.count, 2)
    }
    func testNewerHostEditWinsRegardlessOfDeliveryOrder() throws {
        var phone = SyncedConfiguration(); var host = host("original")
        try phone.save(host, modified: Date(timeIntervalSince1970: 10))
        var pad = phone
        host.name = "new name"; try pad.save(host, modified: Date(timeIntervalSince1970: 20))
        XCTAssertEqual(try merged(phone, pad).sortedHosts.first?.name, "new name")
        XCTAssertEqual(try merged(pad, phone), pad)
    }
    func testEqualTimestampsConvergeAndUnchangedSavesDoNotCreateRevisions() throws {
        let h = host("same"), key = SyncedConfiguration.hostPrefix + h.id.uuidString
        var a = SyncedConfiguration(), b = SyncedConfiguration()
        a.hosts[key] = ConfigurationRecord(h, modified: Date(timeIntervalSince1970: 10), revision: "a")
        var changed = h; changed.name = "winner"
        b.hosts[key] = ConfigurationRecord(changed, modified: Date(timeIntervalSince1970: 10), revision: "b")
        XCTAssertEqual(try merged(a, b), try merged(b, a))
        let before = b; try b.save(changed)
        XCTAssertEqual(before, b)
    }
    func testOlderDeviceClockCanEditAReceivedRecord() throws {
        var state = SyncedConfiguration(); var h = host("before")
        try state.save(h, modified: Date(timeIntervalSince1970: 20))
        h.name = "after"; try state.save(h, modified: Date(timeIntervalSince1970: 10))
        XCTAssertGreaterThan(try XCTUnwrap(state.hosts.values.first).modified, Date(timeIntervalSince1970: 20))
    }
    func testPersistenceAndPreferencesRoundTripWithoutCredentials() throws {
        var state = SyncedConfiguration(); try state.save(host("host"))
        var prefs = TerminalPreferences(); prefs.fontSize = 18; prefs.optionAsMeta = false
        try state.save(prefs)
        let data = try JSONEncoder().encode(state)
        XCTAssertEqual(try JSONDecoder().decode(SyncedConfiguration.self, from: data), state)
        XCTAssertEqual(try merged(SyncedConfiguration(), state).preferences?.value, prefs)
        let payload = String(decoding: data, as: UTF8.self)
        for secretField in ["privateKey", "secretAccessKey", "sessionToken", "passphrase", "trustedFingerprint"] { XCTAssertFalse(payload.contains(secretField)) }
    }
    func testRemovalSurvivesOfflineEditsAndEitherMergeOrder() throws {
        let h = host("remove")
        var removed = SyncedConfiguration(); try removed.save(h, modified: Date(timeIntervalSince1970: 10))
        var offline = removed
        removed.removeHost(id: h.id, modified: Date(timeIntervalSince1970: 20))
        var staleEdit = h; staleEdit.name = "offline edit"
        try offline.save(staleEdit, modified: Date(timeIntervalSince1970: 100))
        let a = try merged(removed, offline), b = try merged(offline, removed)
        XCTAssertEqual(a, b); XCTAssertTrue(a.sortedHosts.isEmpty)
        XCTAssertThrowsError(try removed.save(h))
    }
    func testRemovalPersistsWithoutRemovingOtherHostsOrPreferences() throws {
        let deleted = host("remove"), kept = host("keep")
        var state = SyncedConfiguration(); try state.save(deleted); try state.save(kept)
        try state.save(TerminalPreferences())
        state.removeHost(id: deleted.id)
        let restored = try JSONDecoder().decode(SyncedConfiguration.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(restored.sortedHosts, [kept]); XCTAssertNotNil(restored.preferences)
        XCTAssertEqual(try merged(SyncedConfiguration(), restored).sortedHosts, [kept])
        let before = state; state.removeHost(id: deleted.id); state.removeHost(id: UUID())
        XCTAssertEqual(state, before)
    }
    func testPreRemovalSchemaRemainsReadable() throws {
        let h = host("existing")
        let record = ConfigurationRecord(h)
        let data = try JSONEncoder().encode(record)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("deleted"))
        var state = SyncedConfiguration()
        try state.merge(key: SyncedConfiguration.hostPrefix + h.id.uuidString, data: data)
        XCTAssertEqual(state.sortedHosts, [h])
    }
    func testHostOrderSyncsAndNewHostsAppendWithoutRestoringRemovedHosts() throws {
        let a = host("a"), b = host("b"), c = host("c")
        var state = SyncedConfiguration(); try state.save(a); try state.save(b)
        try state.saveHostOrder([b.id, a.id])
        XCTAssertEqual(try merged(SyncedConfiguration(), state).sortedHosts.map(\.id), [b.id, a.id])
        try state.save(c); state.removeHost(id: b.id)
        XCTAssertEqual(state.sortedHosts.map(\.id), [a.id, c.id])
        XCTAssertEqual(try JSONDecoder().decode(SyncedConfiguration.self, from: JSONEncoder().encode(state)).sortedHosts, state.sortedHosts)
    }
    func testConcurrentHostOrdersConvergeAndDuplicateIDsAreRejected() throws {
        let a = UUID(), b = UUID()
        var phone = SyncedConfiguration(), pad = SyncedConfiguration()
        try phone.saveHostOrder([a, b], modified: Date(timeIntervalSince1970: 10))
        try pad.saveHostOrder([b, a], modified: Date(timeIntervalSince1970: 20))
        XCTAssertEqual(try merged(phone, pad).hostOrder?.value, [b, a])
        XCTAssertEqual(try merged(phone, pad), try merged(pad, phone))
        XCTAssertThrowsError(try phone.saveHostOrder([a, a]))
    }
    func testInvalidCloudDataDoesNotReplaceLocalSettings() throws {
        var state = SyncedConfiguration(); let h = host("keep")
        try state.save(h); let before = state
        let record = ConfigurationRecord(host("wrong id"))
        XCTAssertThrowsError(try state.merge(key: SyncedConfiguration.hostPrefix + h.id.uuidString, data: JSONEncoder().encode(record)))
        XCTAssertThrowsError(try state.merge(key: SyncedConfiguration.preferencesKey, data: Data("bad json".utf8)))
        var invalid = TerminalPreferences(); invalid.fontSize = 999
        XCTAssertThrowsError(try state.merge(key: SyncedConfiguration.preferencesKey, data: JSONEncoder().encode(ConfigurationRecord(invalid))))
        XCTAssertEqual(before, state)
    }
}
