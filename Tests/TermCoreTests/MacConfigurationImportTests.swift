#if os(macOS)
import XCTest
@testable import TermCore

final class MacConfigurationImportTests: XCTestCase {
    func testAliasDiscoverySkipsWildcardsAndKeepsQuotedNames() {
        XCTAssertEqual(MacConfigurationImport.aliases(in: """
        Host alpha beta # comment
        Host *.internal !excluded
        Host "gamma"
        Host alpha
        """), ["alpha", "beta", "gamma"])
        XCTAssertThrowsError(try MacConfigurationImport.words("sh 'unfinished"))
    }
    func testImportIDsMatchExistingPythonExports() {
        XCTAssertEqual(MacConfigurationImport.identifier(for: "alpha").uuidString.lowercased(), "66d248f5-0bed-5ad2-ad76-ca39d5f4d553")
    }
    func testDirectHostAndSSMKeepResolvedUserPortAndCredentialNames() throws {
        let key = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("synthetic".utf8).write(to: key); defer { try? FileManager.default.removeItem(at: key) }
        let base = "user operator\nport 2202\nidentityfile \(key.path)\n"
        let direct = try MacConfigurationImport.host(alias: "direct", resolved: base + "hostname example.invalid\n", home: .temporaryDirectory)
        XCTAssertEqual(direct.username, "operator"); XCTAssertEqual(direct.port, 2202)
        XCTAssertEqual(direct.keyID, key.lastPathComponent); XCTAssertFalse(direct.isSSM)
        let proxy = "proxycommand sh -c \"aws ssm start-session --profile example --region us-west-2 --target %h --document-name AWS-StartSSHSession --parameters 'portNumber=%p'\"\n"
        let ssm = try MacConfigurationImport.host(alias: "ssm", resolved: base + "hostname i-123456789abcdef00\n" + proxy, home: .temporaryDirectory)
        XCTAssertTrue(ssm.isSSM); XCTAssertEqual(ssm.awsProfile, "example"); XCTAssertEqual(ssm.region, "us-west-2")
        XCTAssertThrowsError(try MacConfigurationImport.host(alias: "bad", resolved: base + "hostname i-123456789abcdef00\n", home: .temporaryDirectory))
        XCTAssertThrowsError(try MacConfigurationImport.host(alias: "bad", resolved: base + "hostname test\nproxyjump gateway\n", home: .temporaryDirectory))
        XCTAssertThrowsError(try MacConfigurationImport.host(alias: "bad", resolved: base + "hostname test\nproxycommand arbitrary command\n", home: .temporaryDirectory))
        XCTAssertThrowsError(try MacConfigurationImport.host(alias: "bad", resolved: base + "hostname i-123456789abcdef00\n" + proxy.replacingOccurrences(of: "--region us-west-2", with: "--endpoint-url https://example.invalid"), home: .temporaryDirectory))
    }
    func testAWSProfilesRequireStaticCredentialsAndPreserveTemporaryToken() {
        let profiles = MacConfigurationImport.awsProfiles(in: """
        # synthetic fixtures only
        [example]
        aws_access_key_id = test-id
        aws_secret_access_key = test-secret
        aws_session_token = test-token==
        [profile another]
        aws_access_key_id = second-id
        aws_secret_access_key = second-secret
        [incomplete]
        aws_access_key_id = only-id
        [role]
        role_arn = test-role
        aws_access_key_id = id
        aws_secret_access_key = secret
        [process]
        credential_process = something
        """)
        XCTAssertEqual(profiles.keys.sorted(), ["another", "example"])
        XCTAssertEqual(profiles["example"]?.sessionToken, "test-token==")
    }
}
#endif
