#if os(macOS)
import Foundation

/// A private, short-lived launch folder for a system OpenSSH session.
public struct ExternalSSHSession {
    public let directory: URL
    public let script: URL

    public init(host: Host, privateKey: Data, aws: AWSCredentials?, awsExecutable: URL? = nil,
                temporaryDirectory: URL = FileManager.default.temporaryDirectory) throws {
        try host.validate()
        guard !privateKey.isEmpty else { throw ConnectionError.message("The SSH key is empty.") }
        if host.isSSM {
            guard let aws, !aws.accessKeyID.isEmpty, !aws.secretAccessKey.isEmpty else {
                throw ConnectionError.message("Import the AWS profile named \(host.awsProfile).")
            }
            guard [aws.accessKeyID, aws.secretAccessKey, aws.sessionToken ?? ""].allSatisfy({ !$0.contains(where: { $0.isNewline }) }) else {
                throw ConnectionError.message("AWS credential values must not contain line breaks.")
            }
            guard awsExecutable != nil else { throw ConnectionError.message("Install AWS CLI and Session Manager Plugin on this Mac to connect through SSM.") }
        }
        let folder = temporaryDirectory.appendingPathComponent("term-anywhere-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        directory = folder
        script = folder.appendingPathComponent("Connect.command")
        do {
            func write(_ data: Data, _ name: String, mode: Int = 0o600) throws -> URL {
                let url = folder.appendingPathComponent(name)
                // The parent is already private before any credential bytes are written.
                try data.write(to: url, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
                return url
            }
            let key = try write(privateKey, "identity")
            var args = ["/usr/bin/ssh", "-F", "/dev/null", "-o", "IdentitiesOnly=yes", "-o", "StrictHostKeyChecking=ask", "-i", key.path, "-p", String(host.port), "-l", host.username]
            if host.isSSM, let aws, let awsExecutable {
                var values = "[term-anywhere]\naws_access_key_id = \(aws.accessKeyID)\naws_secret_access_key = \(aws.secretAccessKey)\n"
                if let token = aws.sessionToken, !token.isEmpty { values += "aws_session_token = \(token)\n" }
                let credentials = try write(Data(values.utf8), "aws-credentials")
                let command = ["/usr/bin/env", "-u", "AWS_ACCESS_KEY_ID", "-u", "AWS_SECRET_ACCESS_KEY", "-u", "AWS_SESSION_TOKEN", "-u", "AWS_SECURITY_TOKEN", "AWS_SHARED_CREDENTIALS_FILE=" + credentials.path, "AWS_CONFIG_FILE=/dev/null", awsExecutable.path, "ssm", "start-session", "--profile", "term-anywhere", "--region", host.region, "--target", host.address, "--document-name", "AWS-StartSSHSession", "--parameters", "portNumber=" + String(host.port)]
                let proxy = try write(Data(("#!/bin/zsh\n" + Self.pathSetup + "exec " + command.map(shellQuote).joined(separator: " ") + "\n").utf8), "ssm-proxy", mode: 0o700)
                // OpenSSH expands percent tokens in ProxyCommand, including quoted paths.
                args += ["-o", "ProxyCommand=exec /bin/zsh " + shellQuote(proxy.path).replacingOccurrences(of: "%", with: "%%")]
            }
            args += ["-t", "--", host.address]
            if !host.tmuxSession.isEmpty {
                args += [host.tmuxCommand + " new-session -A -s " + shellQuote(host.tmuxSession)]
            }
            let cleanup = "/bin/rm -rf -- " + shellQuote(folder.path)
            let text = """
            #!/bin/zsh
            \(Self.pathSetup)
            cleanup() { \(cleanup); }
            trap cleanup EXIT
            trap 'exit 130' INT
            trap 'exit 143' TERM
            trap 'exit 129' HUP
            \(args.map(shellQuote).joined(separator: " "))
            connection_status=$?
            cleanup
            if [ "$connection_status" -ne 0 ]; then
                print -r -- "SSH exited with status $connection_status."
                read -r '?Press Return to close…'
            fi
            exit "$connection_status"

            """
            _ = try write(Data(text.utf8), "Connect.command", mode: 0o700)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }
    public func remove() { try? FileManager.default.removeItem(at: directory) }
    private static let pathSetup = "export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin\n"
}
#endif
