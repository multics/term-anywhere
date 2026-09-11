import Foundation
import CryptoKit
import CSSH
import Darwin

/// All libssh2 calls belong to worker. Socket shutdown may interrupt a blocked call.
public final class SSHConnection: @unchecked Sendable {
    private let worker = DispatchQueue(label: "me.tianyong.term-anywhere.ssh", qos: .userInitiated)
    private var session: OpaquePointer?
    private var channel: OpaquePointer?
    private let descriptor: Int32
    private let tunnel: SSMTunnel?
    private var stopped = false
    private var writeBuffers: [Data] = []
    private var writeOffset = 0
    private var lastKeepalive = Date()
    public let fingerprint: String
    public var onData: (@Sendable (Data) -> Void)?
    public var onClose: (@Sendable (String?) -> Void)?

    private init(session: OpaquePointer, descriptor: Int32, tunnel: SSMTunnel?, fingerprint: String) {
        self.session = session; self.descriptor = descriptor; self.tunnel = tunnel; self.fingerprint = fingerprint
    }
    public static func open(host: Host, privateKey: Data, passphrase: String = "", trustedFingerprint: String?, aws: AWSCredentials? = nil) async throws -> SSHConnection {
        try host.validate()
        var tunnel: SSMTunnel?, fd: Int32
        if host.isSSM {
            guard let aws else { throw ConnectionError.message("Add AWS credentials for \(host.awsProfile).") }
            let t = SSMTunnel(host: host, credentials: aws); tunnel = t; fd = try await t.open()
        } else {
            fd = await Task.detached { ta_connect(host.address, Int32(host.port)) }.value
        }
        guard fd >= 0 else { throw ConnectionError.message("Cannot reach the server. Check the address, port, and VPN.") }
        let socket = fd, transport = tunnel
        do {
            return try await Task.detached {
                guard let s = ta_session() else { throw ConnectionError.message("Cannot initialize SSH.") }
                var success = false
                defer { if !success { libssh2_session_free(s) } }
                libssh2_session_set_timeout(s, 20_000)
                libssh2_session_set_blocking(s, 1)
                guard libssh2_session_handshake(s, socket) == 0 else { throw ConnectionError.message("SSH handshake failed.") }
                var length = 0; var type: Int32 = 0
                guard let key = libssh2_session_hostkey(s, &length, &type), length > 0 else { throw ConnectionError.message("The server did not supply a host key.") }
                let fingerprint = "SHA256:" + Data(SHA256.hash(data: Data(bytes: key, count: length))).base64EncodedString().replacingOccurrences(of: "=", with: "")
                guard fingerprint == trustedFingerprint else { throw ConnectionError.hostKey(fingerprint, changed: trustedFingerprint != nil) }
                let auth = privateKey.withUnsafeBytes { bytes in
                    libssh2_userauth_publickey_frommemory(s, host.username, host.username.utf8.count, nil, 0, bytes.baseAddress!.assumingMemoryBound(to: CChar.self), bytes.count, passphrase)
                }
                guard auth == 0 else { throw ConnectionError.message("SSH key authentication failed. Check the user, selected key, and passphrase.") }
                libssh2_keepalive_config(s, 1, 30)
                success = true
                return SSHConnection(session: s, descriptor: socket, tunnel: transport, fingerprint: fingerprint)
            }.value
        } catch {
            shutdown(socket, SHUT_RDWR); Darwin.close(socket)
            if let transport { await transport.stop() }
            throw error
        }
    }
    public func execute(_ command: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            worker.async {
                do { continuation.resume(returning: try self.executeSync(command)) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
    private func executeSync(_ command: String) throws -> String {
        guard !stopped, let session else { throw ConnectionError.message("SSH is disconnected.") }
        libssh2_session_set_blocking(session, 1); libssh2_session_set_timeout(session, 8_000)
        defer { libssh2_session_set_blocking(session, 0) }
        guard let c = ta_channel(session) else { throw ConnectionError.message("Cannot open an SSH command channel.") }
        defer { libssh2_session_set_blocking(session, 1); libssh2_session_set_timeout(session, 2_000); libssh2_channel_free(c) }
        guard ta_exec(c, command) == 0 else { throw ConnectionError.message("Cannot execute the remote query.") }
        _ = libssh2_channel_send_eof(c)
        libssh2_session_set_blocking(session, 0)
        var output = Data(), buffer = [UInt8](repeating: 0, count: 8192)
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            let n = libssh2_channel_read_ex(c, 0, &buffer, buffer.count)
            if n > 0 { output.append(contentsOf: buffer.prefix(n)) }
            // EOF is not complete until stderr is drained too.
            let stderrCount = libssh2_channel_read_ex(c, 1, &buffer, buffer.count)
            if stderrCount < 0 && stderrCount != LIBSSH2_ERROR_EAGAIN { throw ConnectionError.message("The remote query failed.") }
            if n <= 0 && stderrCount <= 0 { usleep(10_000) }
            if output.count > 512 * 1024 { throw ConnectionError.message("The remote query produced too much output.") }
            if libssh2_channel_eof(c) != 0 { break }
            if n < 0 && n != LIBSSH2_ERROR_EAGAIN { throw ConnectionError.message("The remote query failed or timed out.") }
        }
        guard libssh2_channel_eof(c) != 0 else { throw ConnectionError.message("The remote query timed out.") }
        libssh2_channel_close(c)
        guard libssh2_channel_get_exit_status(c) == 0 else { throw ConnectionError.message("The remote query failed. Check that tmux and the selected session are available.") }
        return String(decoding: output, as: UTF8.self)
    }
    public func tmuxSessions(for host: Host) async throws -> TmuxSessionList {
        let command = "if command -v tmux >/dev/null 2>&1; then printf 'TERM_ANYWHERE_TMUX_AVAILABLE\\n'; \(host.tmuxCommand) list-sessions -F '#{session_name}' 2>/dev/null || :; else printf 'TERM_ANYWHERE_TMUX_UNAVAILABLE\\n'; fi"
        return try TmuxSessionList(output: await execute(command))
    }
    private func resolveTmuxSession(_ host: Host) throws -> String {
        let listing = try executeSync("\(host.tmuxCommand) list-sessions -F '#{session_name}\t#{session_id}'")
        for line in listing.split(separator: "\n") {
            let fields = line.split(separator: "\t", maxSplits: 1)
            if fields.count == 2, fields[0] == host.tmuxSession,
               fields[1].range(of: "^\\$[0-9]+$", options: .regularExpression) != nil { return String(fields[1]) }
        }
        throw ConnectionError.message("The saved tmux session no longer exists. Recreate it on the server or choose another session.")
    }
    public func tmuxSessionID(for host: Host) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            worker.async { do { continuation.resume(returning: try self.resolveTmuxSession(host)) } catch { continuation.resume(throwing: error) } }
        }
    }
    public func scrollTmux(for host: Host, lines: Int) async throws {
        let id = try await tmuxSessionID(for: host)
        try Task.checkCancellation()
        let state = try await execute("\(host.tmuxCommand) display-message -p -t \(shellQuote(id + ":")) '#{pane_id}|#{pane_mode}|#{alternate_on}'")
        try Task.checkCancellation()
        if let command = try TmuxScroll(state: state).command(tmux: host.tmuxCommand, lines: lines) {
            _ = try await execute(command)
        }
    }
    public func startTerminal(host: Host, reconnecting: Bool, columns: Int = 80, rows: Int = 24) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            worker.async {
                do {
                    guard !self.stopped, let s = self.session else { throw ConnectionError.message("SSH is disconnected.") }
                    let tmuxID = reconnecting && !host.tmuxSession.isEmpty ? try self.resolveTmuxSession(host) : nil
                    libssh2_session_set_blocking(s, 1); libssh2_session_set_timeout(s, 10_000)
                    guard let c = ta_channel(s) else { throw ConnectionError.message("Cannot open a terminal channel.") }
                    self.channel = c
                    guard libssh2_channel_request_pty_ex(c, "xterm-256color", 14, nil, 0, Int32(columns), Int32(rows), 0, 0) == 0 else { throw ConnectionError.message("The server rejected a terminal request.") }
                    let status: Int32
                    if host.tmuxSession.isEmpty { status = ta_shell(c) }
                    else {
                        let operation = reconnecting ? "attach-session -t \(shellQuote(tmuxID!))" : "new-session -A -s \(shellQuote(host.tmuxSession))"
                        status = ta_exec(c, "exec \(host.tmuxCommand) \(operation)")
                    }
                    guard status == 0 else { throw ConnectionError.message("Cannot start the remote terminal.") }
                    libssh2_session_set_blocking(s, 0)
                    continuation.resume()
                    self.poll()
                } catch { continuation.resume(throwing: error); self.closeSync(error.localizedDescription) }
            }
        }
    }
    public func tmuxBindings(for host: Host) async throws -> TmuxBindings {
        guard !host.tmuxSession.isEmpty else { throw ConnectionError.message("This connection uses a plain shell.") }
        // Explicit target is required: global prefix alone would miss per-session overrides.
        let id = try await tmuxSessionID(for: host)
        let prefix = try await execute("\(host.tmuxCommand) show-options -Av -t \(shellQuote(id)) prefix")
        let keys = try await execute("\(host.tmuxCommand) list-keys -T prefix && \(host.tmuxCommand) list-keys -T root")
        return TmuxBindings(prefix: prefix, listing: keys)
    }
    public func send(_ data: Data) {
        worker.async {
            guard !self.stopped, self.channel != nil, !data.isEmpty else { return }
            guard self.writeBuffers.reduce(0, { $0 + $1.count }) + data.count <= 1024 * 1024 else { self.closeSync("Input exceeded the buffer limit. Unsent input was discarded."); return }
            self.writeBuffers.append(data)
        }
    }
    public func resize(columns: Int, rows: Int) {
        worker.async { if !self.stopped, let c = self.channel { _ = libssh2_channel_request_pty_size_ex(c, Int32(max(1, columns)), Int32(max(1, rows)), 0, 0) } }
    }
    private func poll() {
        guard !stopped, let c = channel, let s = session else { return }
        var buffer = [UInt8](repeating: 0, count: 16384), output = Data()
        for stream in [Int32(0), Int32(1)] {
            for _ in 0..<8 {
                let n = libssh2_channel_read_ex(c, stream, &buffer, buffer.count)
                if n > 0 { output.append(contentsOf: buffer.prefix(n)) }
                else if n == Int(LIBSSH2_ERROR_EAGAIN) || n == 0 { break }
                else { closeSync("SSH connection lost."); return }
            }
        }
        if !output.isEmpty { onData?(output) }
        if libssh2_channel_eof(c) != 0 { closeSync(nil); return }
        if !writeBuffers.isEmpty {
            let n = writeBuffers[0].withUnsafeBytes { bytes in
                libssh2_channel_write_ex(c, 0, bytes.baseAddress!.advanced(by: writeOffset).assumingMemoryBound(to: CChar.self), bytes.count - writeOffset)
            }
            if n > 0 { writeOffset += n; if writeOffset == writeBuffers[0].count { writeBuffers.removeFirst(); writeOffset = 0 } }
            else if n != Int(LIBSSH2_ERROR_EAGAIN) { closeSync("SSH connection lost. Unsent input was discarded."); return }
        }
        if Date().timeIntervalSince(lastKeepalive) >= 30 {
            var seconds: Int32 = 0
            let result = libssh2_keepalive_send(s, &seconds)
            if result < 0 && result != LIBSSH2_ERROR_EAGAIN { closeSync("SSH keepalive failed."); return }
            lastKeepalive = Date()
        }
        worker.asyncAfter(deadline: .now() + .milliseconds(10)) { [weak self] in self?.poll() }
    }
    public func close() { worker.async { self.closeSync(nil) } }
    private func closeSync(_ reason: String?) {
        guard !stopped else { return }; stopped = true
        writeBuffers.removeAll(); writeOffset = 0
        shutdown(descriptor, SHUT_RDWR)
        if let channel { libssh2_channel_free(channel); self.channel = nil }
        if let session { libssh2_session_free(session); self.session = nil }
        Darwin.close(descriptor)
        if let tunnel { Task { await tunnel.stop() } }
        onClose?(reason); onClose = nil; onData = nil
    }
}
