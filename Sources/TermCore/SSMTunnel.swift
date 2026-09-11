import Foundation
import Darwin

public actor SSMTunnel {
    private let host: Host
    private let credentials: AWSCredentials
    private var websocket: URLSessionWebSocketTask?
    private let urlSession: URLSession
    private var sessionID: String?
    private var bridgeFD: Int32 = -1
    private var ready = false, closed = false, paused = false
    private var failure: Error?
    private var inputSequence: UInt64 = 0, outputSequence: UInt64 = 0
    private var pending: [UInt64: (SSMMessage, Date)] = [:]
    private var incoming: [UInt64: SSMMessage] = [:]
    private var receiver: Task<Void, Never>?, pump: Task<Void, Never>?, timer: Task<Void, Never>?
    private static let protocolVersion = "1.3.0.0"
    public init(host: Host, credentials: AWSCredentials) {
        self.host = host; self.credentials = credentials
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        urlSession = URLSession(configuration: config)
    }
    private func api(_ operation: String, body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://ssm.\(host.region).amazonaws.com/")!)
        request.httpMethod = "POST"; request.httpBody = try JSONSerialization.data(withJSONObject: body, options: .sortedKeys)
        request.setValue("application/x-amz-json-1.1", forHTTPHeaderField: "Content-Type")
        request.setValue("AmazonSSM." + operation, forHTTPHeaderField: "X-Amz-Target")
        request = AWSSigning.sign(request, credentials: credentials, region: host.region, service: "ssm")
        let (data, response) = try await urlSession.data(for: request)
        let result = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard let status = response as? HTTPURLResponse, (200..<300).contains(status.statusCode) else {
            let code = (result["__type"] as? String)?.components(separatedBy: "#").last ?? "RequestFailed"
            throw ConnectionError.message("AWS \(operation): \(code). Check the profile, region, permissions, and target status.")
        }
        return result
    }
    public func open() async throws -> Int32 {
        do {
            let response = try await api("StartSession", body: ["Target": host.address, "DocumentName": "AWS-StartSSHSession", "Parameters": ["portNumber": [String(host.port)]]])
            guard let id = response["SessionId"] as? String, let token = response["TokenValue"] as? String,
                  let address = response["StreamUrl"] as? String, let url = URL(string: address), url.scheme == "wss",
                  url.host == "ssmmessages.\(host.region).amazonaws.com" else { throw ConnectionError.message("AWS returned an invalid session endpoint.") }
            sessionID = id
            var request = URLRequest(url: url)
            if !(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).contains(where: { $0.name == "X-Amz-Signature" }) {
                request = AWSSigning.sign(request, credentials: credentials, region: host.region, service: "ssmmessages")
            }
            let ws = urlSession.webSocketTask(with: request); ws.maximumMessageSize = 4 * 1024 * 1024; websocket = ws; ws.resume()
            let hello: [String: String] = ["MessageSchemaVersion": "1.0", "RequestId": UUID().uuidString, "TokenValue": token, "ClientId": UUID().uuidString, "ClientVersion": Self.protocolVersion]
            try await ws.send(.string(String(decoding: JSONSerialization.data(withJSONObject: hello), as: UTF8.self)))
            var fds: [Int32] = [-1, -1]
            guard socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0 else { throw ConnectionError.message("Cannot open the local SSM stream.") }
            bridgeFD = fds[1]
            for fd in fds { var one: Int32 = 1; setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size)) }
            _ = fcntl(bridgeFD, F_SETFL, O_NONBLOCK)
            receiver = Task { await self.receiveLoop() }
            timer = Task { await self.maintenanceLoop() }
            let deadline = Date().addingTimeInterval(30)
            do {
                while !ready && !closed && Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
                if let failure { throw failure }
                guard ready, !closed else { throw ConnectionError.message("The SSM data-channel handshake timed out.") }
                pump = Task { await self.socketLoop() }
                return fds[0]
            } catch { Darwin.close(fds[0]); throw error }
        } catch { await stop(error); throw error }
    }
    private func sendFrame(_ message: SSMMessage) async throws {
        guard !closed, let websocket else { throw ConnectionError.message("SSM is disconnected.") }
        try await websocket.send(.data(message.encode()))
    }
    private func sendInput(_ data: Data, type: UInt32) async throws {
        while (pending.count >= 64 || paused) && !closed { try await Task.sleep(nanoseconds: 10_000_000) }
        guard !closed else { throw ConnectionError.message("SSM is disconnected.") }
        let message = SSMMessage(type: "input_stream_data", sequence: inputSequence, payloadType: type, payload: data)
        inputSequence += 1; pending[message.sequence] = (message, Date())
        try await sendFrame(message)
    }
    private func receiveLoop() async {
        do {
            while !closed, let ws = websocket {
                switch try await ws.receive() {
                case .data(let data): try await receive(SSMMessage(decode: data))
                case .string: throw ConnectionError.message("Unexpected SSM text response.")
                @unknown default: throw ConnectionError.message("Unknown SSM response.")
                }
            }
        } catch { if !closed { await stop(error) } }
    }
    private func receive(_ message: SSMMessage) async throws {
        switch message.type {
        case "acknowledge":
            if let ack = try JSONSerialization.jsonObject(with: message.payload) as? [String: Any], let n = ack["AcknowledgedMessageSequenceNumber"] as? NSNumber,
               let id = ack["AcknowledgedMessageId"] as? String, pending[n.uint64Value]?.0.id.uuidString.lowercased() == id.lowercased() { pending.removeValue(forKey: n.uint64Value) }
        case "output_stream_data":
            guard message.sequence <= outputSequence + 128, incoming.count < 128 else { throw ConnectionError.message("SSM output exceeded its buffer limit.") }
            if message.sequence >= outputSequence { incoming[message.sequence] = message }
            let ack: [String: Any] = ["AcknowledgedMessageType": message.type, "AcknowledgedMessageId": message.id.uuidString.lowercased(), "AcknowledgedMessageSequenceNumber": message.sequence, "IsSequentialMessage": true]
            try await sendFrame(SSMMessage(type: "acknowledge", payload: JSONSerialization.data(withJSONObject: ack)))
            while let next = incoming.removeValue(forKey: outputSequence) { outputSequence += 1; try await output(next) }
        case "start_publication": paused = false
        case "pause_publication": paused = true
        case "channel_closed": throw ConnectionError.message("AWS closed the SSM session.")
        default: throw ConnectionError.message("Unsupported SSM message type.")
        }
    }
    private func output(_ message: SSMMessage) async throws {
        switch message.payloadType {
        case 5:
            let request = try JSONSerialization.jsonObject(with: message.payload) as? [String: Any]
            let actions = request?["RequestedClientActions"] as? [[String: Any]] ?? []
            var responses: [[String: Any]] = []
            for action in actions {
                guard action["ActionType"] as? String == "SessionType", let p = action["ActionParameters"] as? [String: Any], p["SessionType"] as? String == "Port" else {
                    throw ConnectionError.message("This SSM session requires an unsupported handshake action (for example KMS).")
                }
                responses.append(["ActionType": "SessionType", "ActionStatus": 1, "ActionResult": NSNull(), "Error": ""])
            }
            let result: [String: Any] = ["ClientVersion": Self.protocolVersion, "ProcessedClientActions": responses, "Errors": [String]()]
            try await sendInput(JSONSerialization.data(withJSONObject: result), type: 6)
        case 7: ready = true
        case 1:
            guard ready else { throw ConnectionError.message("SSM sent data before its handshake completed.") }
            var offset = 0
            while offset < message.payload.count && !closed {
                let n = message.payload.withUnsafeBytes { Darwin.send(bridgeFD, $0.baseAddress!.advanced(by: offset), $0.count - offset, 0) }
                if n > 0 { offset += n }
                else if errno == EAGAIN || errno == EWOULDBLOCK { try await Task.sleep(nanoseconds: 5_000_000) }
                else { throw ConnectionError.message("The local SSM stream closed.") }
            }
        default: throw ConnectionError.message("Unsupported SSM payload type \(message.payloadType).")
        }
    }
    private func socketLoop() async {
        do {
            var buffer = [UInt8](repeating: 0, count: 8192)
            while !closed {
                let n = Darwin.recv(bridgeFD, &buffer, buffer.count, 0)
                if n > 0 { try await sendInput(Data(buffer.prefix(n)), type: 1) }
                else if n == 0 { await stop(nil); return }
                else if errno == EAGAIN || errno == EWOULDBLOCK { try await Task.sleep(nanoseconds: 10_000_000) }
                else { throw ConnectionError.message("The local SSM stream failed.") }
            }
        } catch { if !closed { await stop(error) } }
    }
    private func maintenanceLoop() async {
        var ticks = 0
        do {
            while !closed {
                try await Task.sleep(nanoseconds: 1_000_000_000); ticks += 1
                for (_, item) in pending {
                    if Date().timeIntervalSince(item.1) > 30 { throw ConnectionError.message("SSM acknowledgement timed out.") }
                    if Date().timeIntervalSince(item.1) > 2 { try await sendFrame(item.0) }
                }
                if ticks % 15 == 0 { websocket?.sendPing { _ in } }
            }
        } catch { if !closed { await stop(error) } }
    }
    public func stop(_ error: Error? = nil) async {
        guard !closed else { return }; closed = true; failure = error
        receiver?.cancel(); pump?.cancel(); timer?.cancel()
        websocket?.cancel(with: .goingAway, reason: nil)
        if bridgeFD >= 0 { shutdown(bridgeFD, SHUT_RDWR); Darwin.close(bridgeFD); bridgeFD = -1 }
        pending.removeAll(); incoming.removeAll()
        if let sessionID { _ = try? await api("TerminateSession", body: ["SessionId": sessionID]) }
        urlSession.invalidateAndCancel()
    }
}
