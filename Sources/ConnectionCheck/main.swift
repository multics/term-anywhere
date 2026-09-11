import Foundation
import TermCore

@main struct ConnectionCheck {
    static func main() async {
        do {
            guard CommandLine.arguments.count >= 3 else { print("Usage: connection-check HOST_JSON PRIVATE_KEY_PATH [AWS_PROFILE] [FINGERPRINT]"); return }
            let args = CommandLine.arguments
            let host = try JSONDecoder().decode(Host.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
            let key = try Data(contentsOf: URL(fileURLWithPath: args[2]))
            var aws: AWSCredentials?
            if args.count > 3, args[3] != "-" {
                let content = try String(contentsOf: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".aws/credentials"), encoding: .utf8)
                var section = "", values: [String: String] = [:]
                for raw in content.components(separatedBy: .newlines) {
                    let line = raw.trimmingCharacters(in: .whitespaces)
                    if line.hasPrefix("[") && line.hasSuffix("]") { section = String(line.dropFirst().dropLast()); continue }
                    if section == args[3], let split = line.firstIndex(of: "=") { values[String(line[..<split]).trimmingCharacters(in: .whitespaces)] = String(line[line.index(after: split)...]).trimmingCharacters(in: .whitespaces) }
                }
                guard let id = values["aws_access_key_id"], let secret = values["aws_secret_access_key"] else { throw ConnectionError.message("AWS profile is missing.") }
                aws = AWSCredentials(accessKeyID: id, secretAccessKey: secret, sessionToken: values["aws_session_token"])
            }
            let trusted = args.count > 4 ? args[4] : nil
            let connection = try await SSHConnection.open(host: host, privateKey: key, trustedFingerprint: trusted, aws: aws)
            let output = try await connection.execute("printf 'SSH_OK\\n'; command -v tmux >/dev/null && tmux -V || true")
            print(output.trimmingCharacters(in: .whitespacesAndNewlines))
            if args.contains("--list-sessions") {
                let sessions = try await connection.tmuxSessions(for: host)
                print("TMUX_LIST_OK available=\(sessions.isAvailable) count=\(sessions.names.count)")
            }
            if args.contains("--tmux-check") {
                try await checkTmux(connection: connection, host: host, key: key, trusted: trusted, aws: aws)
            } else { connection.close() }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        } catch { print(error.localizedDescription); exit(1) }
    }
    static func checkTmux(connection: SSHConnection, host: TermCore.Host, key: Data, trusted: String?, aws: AWSCredentials?) async throws {
        var target = host
        target.tmuxSession = "check"
        target.tmuxSocket = "/tmp/term-anywhere-check-" + UUID().uuidString.lowercased()
        let tmux = target.tmuxCommand
        print("TMUX_CHECK_CREATE " + target.tmuxSocket)
        var active = connection
        do {
        _ = try await connection.execute("\(tmux) -f /dev/null new-session -d -s check && \(tmux) set-option -t check prefix C-a && \(tmux) unbind-key -T prefix % && \(tmux) bind-key -T prefix v split-window -h")
            let listing = try await active.tmuxSessions(for: target)
            guard listing.isAvailable, listing.names == ["check"] else { throw ConnectionError.message("The tmux session list did not match the isolated server.") }
            print("TMUX_SESSION_DISCOVERY_OK")
            print("TMUX_CHECK_READ_BINDINGS")
            let map = try await active.tmuxBindings(for: target)
            guard map.prefix == "C-a", map.shortcuts.contains(where: { $0.title == "Split side by side" && $0.bytes == Data([1, 118]) }) else { throw ConnectionError.message("Runtime tmux mapping did not match server settings.") }
            let captured = OutputCapture()
            active.onData = { captured.append($0) }
            print("TMUX_CHECK_ATTACH")
            try await active.startTerminal(host: target, reconnecting: false)
            active.send(Data("export TERM_ANYWHERE_CHECK=retained; printf 'ATTACHED_%s\\n' OK\n".utf8))
            try await waitFor("ATTACHED_OK", capture: captured)
            // A query on the other SSH channel must not be typed into the shell.
            print("TMUX_CHECK_QUERY_ISOLATION")
            let query = try await active.execute("printf QUERY_CHANNEL_OK")
            guard query == "QUERY_CHANNEL_OK", !captured.text.contains("QUERY_CHANNEL_OK") else { throw ConnectionError.message("Command output leaked into the interactive channel.") }
            var otherHost = target; otherHost.tmuxSession = "other"
            let other = try await SSHConnection.open(host: otherHost, privateKey: key, trustedFingerprint: trusted, aws: aws)
            defer { other.close() }
            let otherOutput = OutputCapture(); other.onData = { otherOutput.append($0) }
            try await other.startTerminal(host: otherHost, reconnecting: false)
            other.send(Data("printf 'SECOND_TAB_%s\\n' OK\n".utf8))
            try await waitFor("SECOND_TAB_OK", capture: otherOutput)
            guard !captured.text.contains("SECOND_TAB_OK") else { throw ConnectionError.message("Output crossed between tabs.") }
            other.close()
            let afterClose = try await active.tmuxSessions(for: target)
            guard Set(afterClose.names) == Set(["check", "other"]) else { throw ConnectionError.message("Closing a tab removed a remote session.") }
            active.send(Data("printf 'FIRST_TAB_%s\\n' ACTIVE\n".utf8))
            try await waitFor("FIRST_TAB_ACTIVE", capture: captured)
            print("TMUX_MULTIPLE_TABS_OK OUTPUT_ISOLATED CLOSE_RETAINS_REMOTE_SESSION")
            active.close()
            try await Task.sleep(nanoseconds: 500_000_000)
            print("TMUX_CHECK_RECONNECT")
            active = try await SSHConnection.open(host: target, privateKey: key, trustedFingerprint: trusted, aws: aws)
            let second = OutputCapture(); active.onData = { second.append($0) }
            try await active.startTerminal(host: target, reconnecting: true)
            active.send(Data("printf 'RESTORED_%s\\n' \"$TERM_ANYWHERE_CHECK\"\n".utf8))
            try await waitFor("RESTORED_retained", capture: second)
            _ = try await active.execute("\(tmux) kill-server")
            active.close()
            print("TMUX_BINDINGS_OK QUERY_CHANNEL_ISOLATED RECONNECT_STATE_RETAINED")
        } catch {
            _ = try? await active.execute("\(tmux) kill-server")
            active.close(); throw error
        }
    }
    static func waitFor(_ text: String, capture: OutputCapture) async throws {
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if capture.text.contains(text) { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw ConnectionError.message("Terminal check timed out: " + text)
    }
}
final class OutputCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func append(_ value: Data) { lock.lock(); defer { lock.unlock() }; data.append(value); if data.count > 1024 * 1024 { data.removeFirst(data.count - 1024 * 1024) } }
    var text: String { lock.lock(); defer { lock.unlock() }; return String(decoding: data, as: UTF8.self) }
}
