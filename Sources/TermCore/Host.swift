import Foundation

public struct Host: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var address: String
    public var port: Int
    public var username: String
    public var keyID: String
    public var tmuxSession: String
    public var tmuxSocket: String
    public var awsProfile: String
    public var region: String
    public var manualPrefix: String
    public var isSSM: Bool { !awsProfile.isEmpty }
    public var trustID: String { "\(isSSM ? awsProfile + ":" + region : "ssh"):\(address):\(port)" }
    public init(id: UUID = UUID(), name: String = "", address: String = "", port: Int = 22, username: String = "", keyID: String = "", tmuxSession: String = "mobile", tmuxSocket: String = "", awsProfile: String = "", region: String = "us-west-2", manualPrefix: String = "") {
        self.id = id; self.name = name; self.address = address; self.port = port
        self.username = username; self.keyID = keyID; self.tmuxSession = tmuxSession
        self.tmuxSocket = tmuxSocket; self.awsProfile = awsProfile; self.region = region; self.manualPrefix = manualPrefix
    }
    public func validate() throws {
        guard !name.isEmpty, !address.isEmpty, !username.isEmpty, (1...65535).contains(port), !keyID.isEmpty else {
            throw ConnectionError.message("Enter a name, address, user, valid port, and SSH key.")
        }
        guard tmuxSession.isEmpty || tmuxSession.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil else {
            throw ConnectionError.message("Use letters, numbers, underscores, or dashes for the tmux session name.")
        }
        if isSSM {
            guard address.range(of: "^i-[a-f0-9]{8,17}$", options: .regularExpression) != nil,
                  region.range(of: "^[a-z]{2}(-[a-z]+)+-[0-9]+$", options: .regularExpression) != nil else {
                throw ConnectionError.message("Enter a valid EC2 instance ID and AWS region.")
            }
        }
    }
    public var tmuxCommand: String { tmuxSocket.isEmpty ? "tmux" : "tmux -S " + shellQuote(tmuxSocket) }
}
public struct AWSCredentials: Codable, Sendable {
    public var accessKeyID: String
    public var secretAccessKey: String
    public var sessionToken: String?
    public init(accessKeyID: String, secretAccessKey: String, sessionToken: String? = nil) {
        self.accessKeyID = accessKeyID; self.secretAccessKey = secretAccessKey; self.sessionToken = sessionToken
    }
}
public enum ConnectionError: Error, LocalizedError {
    case message(String)
    case hostKey(String, changed: Bool)
    public var errorDescription: String? {
        switch self {
        case .message(let text): return text
        case .hostKey(let key, let changed): return (changed ? "The server's host key has changed. Verify it before updating trust.\n" : "Verify this server fingerprint before connecting.\n") + key
        }
    }
}
public func shellQuote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
