import XCTest
import TermCore

/// Optional live checks. The developer copies the private fixture into the Simulator
/// container just before testing. It is never a bundle resource and is deleted here.
@MainActor final class ConnectionIntegrationTests: XCTestCase {
    struct Fixture: Decodable {
        let host: TermCore.Host
        let privateKey: Data
        let trustedFingerprint: String
        let aws: AWSCredentials?
    }
    func testActualConnectionsFromIOS() async throws {
        let file = URL.documentsDirectory.appendingPathComponent("connection-test-fixture.json")
        guard FileManager.default.fileExists(atPath: file.path) else { throw XCTSkip("No private connection fixture supplied.") }
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: file))
        try FileManager.default.removeItem(at: file)
        for fixture in fixtures {
            let connection = try await SSHConnection.open(host: fixture.host, privateKey: fixture.privateKey, trustedFingerprint: fixture.trustedFingerprint, aws: fixture.aws)
            let output = try await connection.execute("printf IOS_CONNECTION_OK")
            XCTAssertEqual(output, "IOS_CONNECTION_OK", fixture.host.name)
            connection.close()
        }
    }
}
