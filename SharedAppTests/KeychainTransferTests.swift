import XCTest
import TermCore

/// Opt-in, real-device delivery check. The fixture holds only a UUID and an operation.
/// See DESIGN.md. This test never reads the app's real credential service.
final class KeychainTransferTests: XCTestCase {
    private struct Fixture: Decodable { let id: UUID; let operation: String }
    func testSyntheticCrossDeviceDelivery() throws {
        #if os(macOS)
        let url = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("keychain-transfer.json")
        #else
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("keychain-transfer.json")
        #endif
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("No opt-in cross-device Keychain fixture.") }
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        try FileManager.default.removeItem(at: url)
        let group = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "KeychainSyncAccessGroup") as? String)
        let vault = KeychainStore(service: "me.tianyong.term-anywhere.transfer-test." + fixture.id.uuidString,
            localAccessGroup: Bundle.main.object(forInfoDictionaryKey: "KeychainLocalAccessGroup") as? String,
            syncAccessGroup: group)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let samples = ["key:probe": Data("synthetic-key-\(fixture.id)".utf8),
                       "aws:probe": try encoder.encode(AWSCredentials(accessKeyID: "SYNTHETIC", secretAccessKey: fixture.id.uuidString, sessionToken: "synthetic-session-token"))]
        switch fixture.operation {
        case "publish":
            for (account, value) in samples { try vault.save(value, account: account); try vault.setSynchronized(true, account: account) }
        case "verify":
            let deadline = Date().addingTimeInterval(30)
            while try samples.keys.contains(where: { try vault.read(account: $0) == nil }) && Date() < deadline { Thread.sleep(forTimeInterval: 1) }
            for (account, value) in samples {
                XCTAssertEqual(try vault.storage(account: account), .iCloud)
                let received = try XCTUnwrap(vault.read(account: account))
                if account.hasPrefix("aws:") {
                    let actual = try JSONDecoder().decode(AWSCredentials.self, from: received)
                    let expected = try JSONDecoder().decode(AWSCredentials.self, from: value)
                    XCTAssertEqual(actual.accessKeyID, expected.accessKeyID)
                    XCTAssertEqual(actual.secretAccessKey, expected.secretAccessKey)
                    XCTAssertEqual(actual.sessionToken, expected.sessionToken)
                } else { XCTAssertEqual(received, value) }
            }
        case "cleanup":
            for account in samples.keys { try vault.delete(account: account); try vault.delete(account: account, synchronized: true) }
        default: XCTFail("Unknown synthetic probe operation")
        }
    }
}
