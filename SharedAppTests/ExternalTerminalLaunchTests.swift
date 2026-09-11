#if os(macOS)
import XCTest
import TermCore
@testable import Term_Anywhere

@MainActor final class ExternalTerminalLaunchTests: XCTestCase {
    func testExternalSSHConnectionWithOptInHosts() async throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".local/external-ssh-smoke.json")
        guard FileManager.default.fileExists(atPath: fixture.path) else { throw XCTSkip("Opt-in read-only SSH check") }
        let names = try JSONDecoder().decode([String].self, from: Data(contentsOf: fixture))
        let store = AppStore()
        for name in names {
            var host = try XCTUnwrap(store.hosts.first(where: { $0.name == name }))
            host.tmuxSession = ""
            let key = try XCTUnwrap(store.vault.read(account: "key:" + host.keyID))
            let aws = host.isSSM ? try store.vault.read(account: "aws:" + host.awsProfile).map { try JSONDecoder().decode(AWSCredentials.self, from: $0) } : nil
            let session = try ExternalSSHSession(host: host, privateKey: key, aws: aws, awsExecutable: URL(fileURLWithPath: "/opt/homebrew/bin/aws"))
            defer { session.remove() }
            let script = try String(contentsOf: session.script, encoding: .utf8)
            var command = try XCTUnwrap(script.components(separatedBy: .newlines).first(where: { $0.hasPrefix("'/usr/bin/ssh'") }))
            command = command.replacingOccurrences(of: "'/usr/bin/ssh'", with: "'/usr/bin/ssh' '-o' 'BatchMode=yes' '-o' 'ConnectTimeout=15'")
                .replacingOccurrences(of: "'-t' ", with: "") + " 'printf TERM_ANYWHERE_EXTERNAL_SSH_OK'"
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/zsh"); process.arguments = ["-c", command]
            let output = Pipe(); process.standardOutput = output; process.standardError = FileHandle.nullDevice
            try process.run()
            for _ in 0..<450 {
                if !process.isRunning { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            if process.isRunning { process.terminate(); XCTFail("Read-only SSH check timed out"); continue }
            XCTAssertEqual(process.terminationStatus, 0, "External SSH must succeed")
            let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            XCTAssertTrue(text.contains("TERM_ANYWHERE_EXTERNAL_SSH_OK"))
        }
    }
    func testInstalledTerminalDiscovery() {
        let launcher = MacTerminalLauncher()
        XCTAssertTrue(launcher.applications.contains(where: { $0.id == "com.apple.Terminal" }))
        XCTAssertTrue(launcher.applications.contains(where: { $0.id == launcher.defaultID }))
        XCTAssertEqual(Set(launcher.applications.map(\.id)).count, launcher.applications.count)
    }
    func testLaunchSelectedAppsWithSyntheticCommand() async throws {
        let optIn = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".local/external-terminal-smoke")
        guard FileManager.default.fileExists(atPath: optIn.path) else { throw XCTSkip("Opt-in terminal launch smoke test") }
        let launcher = MacTerminalLauncher()
        for app in launcher.applications {
            print("Terminal launch check: " + app.url.path)
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("terminal-launch-check-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(at: directory) }
            let script = directory.appendingPathComponent("Term Anywhere launch check.command")
            let marker = directory.appendingPathComponent("passed")
            let text = "#!/bin/zsh\n/usr/bin/touch '" + marker.path + "'\nprint -r -- 'Term Anywhere: " + app.name + " launch check passed.'\n"
            try text.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
            try await launcher.open(script: script, in: app)
            for _ in 0..<100 {
                if FileManager.default.fileExists(atPath: marker.path) { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path), app.name + " must execute the requested command")
        }
    }
}
#endif
