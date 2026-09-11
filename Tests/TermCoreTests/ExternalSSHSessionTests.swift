#if os(macOS)
import XCTest
@testable import TermCore

final class ExternalSSHSessionTests: XCTestCase {
    func testDirectSessionUsesSavedValuesAndPrivateFiles() throws {
        let host = Host(name: "Fixture", address: "example.invalid", port: 2222, username: "user", keyID: "key", tmuxSession: "work")
        let session = try ExternalSSHSession(host: host, privateKey: Data("synthetic-key".utf8), aws: nil)
        defer { session.remove() }
        let script = try String(contentsOf: session.script, encoding: .utf8)
        XCTAssertTrue(script.contains("'-F' '/dev/null'"))
        XCTAssertTrue(script.contains("'-p' '2222' '-l' 'user'"))
        XCTAssertTrue(script.contains("'--' 'example.invalid'"))
        XCTAssertFalse(script.contains("synthetic-key"))
        for (url, mode) in [(session.directory, 0o700), (session.script, 0o700), (session.directory.appendingPathComponent("identity"), 0o600)] {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, mode)
        }
        let syntax = Process(); syntax.executableURL = URL(fileURLWithPath: "/bin/zsh"); syntax.arguments = ["-n", session.script.path]
        try syntax.run(); syntax.waitUntilExit(); XCTAssertEqual(syntax.terminationStatus, 0)
    }
    func testAWSSecretsStayOutOfCommandsAndUseIsolatedProfile() throws {
        let host = Host(name: "SSM", address: "i-0123456789abcdef0", username: "ubuntu", keyID: "key", awsProfile: "saved-profile")
        let aws = AWSCredentials(accessKeyID: "synthetic-id", secretAccessKey: "synthetic-secret", sessionToken: "synthetic-token")
        let session = try ExternalSSHSession(host: host, privateKey: Data([1]), aws: aws, awsExecutable: URL(fileURLWithPath: "/opt/homebrew/bin/aws"))
        defer { session.remove() }
        let proxy = try String(contentsOf: session.directory.appendingPathComponent("ssm-proxy"), encoding: .utf8)
        let script = try String(contentsOf: session.script, encoding: .utf8)
        XCTAssertTrue(proxy.contains("'--profile' 'term-anywhere'"))
        XCTAssertTrue(proxy.contains("'-u' 'AWS_ACCESS_KEY_ID'"))
        XCTAssertTrue(proxy.contains("'--target' 'i-0123456789abcdef0'"))
        for secret in [aws.accessKeyID, aws.secretAccessKey, aws.sessionToken!] {
            XCTAssertFalse(proxy.contains(secret)); XCTAssertFalse(script.contains(secret))
        }
        let credentials = try String(contentsOf: session.directory.appendingPathComponent("aws-credentials"), encoding: .utf8)
        XCTAssertTrue(credentials.contains("aws_session_token = synthetic-token"))
    }
    func testRejectsAWSLineBreaksAndMissingTool() throws {
        let host = Host(name: "SSM", address: "i-0123456789abcdef0", username: "ubuntu", keyID: "key", awsProfile: "profile")
        let injected = AWSCredentials(accessKeyID: "id", secretAccessKey: "secret\n[another-profile]")
        XCTAssertThrowsError(try ExternalSSHSession(host: host, privateKey: Data([1]), aws: injected, awsExecutable: URL(fileURLWithPath: "/usr/bin/true")))
        XCTAssertThrowsError(try ExternalSSHSession(host: host, privateKey: Data([1]), aws: AWSCredentials(accessKeyID: "id", secretAccessKey: "secret")))
    }
    func testShellQuotingAndCleanupAfterCommandExit() throws {
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        let host = Host(name: "Quote fixture", address: "host'; touch " + marker + "; '", username: "user", keyID: "key", tmuxSession: "", tmuxSocket: "socket with spaces")
        let session = try ExternalSSHSession(host: host, privateKey: Data([1]), aws: nil)
        defer { session.remove() }
        let script = try String(contentsOf: session.script, encoding: .utf8).replacingOccurrences(of: "'/usr/bin/ssh'", with: "'/usr/bin/true'")
        try script.write(to: session.script, atomically: true, encoding: .utf8)
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/zsh"); process.arguments = [session.script.path]
        try process.run(); process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker))
        XCTAssertFalse(FileManager.default.fileExists(atPath: session.directory.path))
    }
}
#endif
