#if os(macOS)
import Foundation
import CryptoKit

/// Read local OpenSSH output and static AWS profiles. Never execute ProxyCommand text.
public enum MacConfigurationImport {
    public static func words(_ text: String) throws -> [String] {
        var result: [String] = [], token = "", quote: Character?, escaped = false, started = false
        for c in text {
            if escaped { token.append(c); escaped = false; started = true; continue }
            if c == "\\", quote != "'" { escaped = true; continue }
            if let q = quote { if c == q { quote = nil } else { token.append(c) }; continue }
            if c == "'" || c == "\"" { quote = c; started = true }
            else if c.isWhitespace { if started { result.append(token); token = ""; started = false } }
            else if c == "#", !started { break }
            else { token.append(c); started = true }
        }
        guard quote == nil, !escaped else { throw ConnectionError.message("A configuration value has incomplete quotes.") }
        if started { result.append(token) }; return result
    }
    public static func aliases(in config: String) -> [String] {
        var result = Set<String>()
        for line in config.components(separatedBy: .newlines) {
            guard let fields = try? words(line), fields.first?.lowercased() == "host" else { continue }
            for name in fields.dropFirst() where !name.contains(where: { "*?!".contains($0) }) { result.insert(name) }
        }
        return result.sorted()
    }
    public static func host(alias: String, resolved: String, home: URL) throws -> Host {
        var fields: [String: [String]] = [:]
        for line in resolved.components(separatedBy: .newlines) {
            let pair = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            if pair.count == 2 { fields[String(pair[0]).lowercased(), default: []].append(String(pair[1])) }
        }
        func first(_ name: String, _ fallback: String = "") -> String { fields[name]?.first ?? fallback }
        guard first("proxyjump", "none") == "none" else { throw ConnectionError.message("\(alias): ProxyJump is not supported.") }
        let identity = fields["identityfile"]?.first(where: { path in
            FileManager.default.fileExists(atPath: expand(path, home: home))
        })
        guard let identity else { throw ConnectionError.message("\(alias): no referenced SSH key file exists. Add a key before importing.") }
        var profile = "", region = "us-west-2"
        let proxy = first("proxycommand")
        if !proxy.isEmpty && proxy != "none" {
            var command = try words(proxy)
            if command.count == 3 && Array(command.prefix(2)) == ["sh", "-c"] { command = try words(command[2]) }
            guard Array(command.prefix(3)) == ["aws", "ssm", "start-session"] else { throw ConnectionError.message("\(alias): this ProxyCommand is not supported.") }
            let flags = Set(["--document-name", "--profile", "--region", "--target", "--parameters"])
            guard (command.count - 3) % 2 == 0 else { throw ConnectionError.message("\(alias): the SSM command contains unsupported arguments.") }
            var seen = Set<String>()
            for index in stride(from: 3, to: command.count, by: 2) {
                guard flags.contains(command[index]), seen.insert(command[index]).inserted else { throw ConnectionError.message("\(alias): the SSM command contains unsupported arguments.") }
            }
            func option(_ flag: String) throws -> String {
                guard let index = command.firstIndex(of: flag), index + 1 < command.count else { throw ConnectionError.message("\(alias): the SSM command is missing \(flag).") }
                return command[index + 1]
            }
            guard try option("--document-name") == "AWS-StartSSHSession" else { throw ConnectionError.message("\(alias): the SSM document is not supported.") }
            profile = try option("--profile"); region = try option("--region")
            let target = try option("--target")
            guard target == "%h" || target == first("hostname") else { throw ConnectionError.message("\(alias): the SSM target differs from the host address.") }
            let parameters = try option("--parameters")
            guard parameters == "portNumber=%p" || parameters == "portNumber=" + first("port", "22") else { throw ConnectionError.message("\(alias): the SSM port parameters are not supported.") }
        }
        if first("hostname").hasPrefix("i-"), profile.isEmpty { throw ConnectionError.message("\(alias): select the canonical SSM alias for this instance.") }
        guard let port = Int(first("port", "22")) else { throw ConnectionError.message("\(alias): invalid SSH port.") }
        let result = Host(id: identifier(for: alias), name: alias, address: first("hostname"), port: port, username: first("user"), keyID: URL(fileURLWithPath: identity).lastPathComponent, awsProfile: profile, region: region)
        try result.validate(); return result
    }
    /// Matches Python's uuid5(NAMESPACE_DNS, "term-anywhere:" + alias).
    public static func identifier(for alias: String) -> UUID {
        let namespace: [UInt8] = [0x6b,0xa7,0xb8,0x10,0x9d,0xad,0x11,0xd1,0x80,0xb4,0x00,0xc0,0x4f,0xd4,0x30,0xc8]
        var bytes = Array(Insecure.SHA1.hash(data: Data(namespace) + Data(("term-anywhere:" + alias).utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50; bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],bytes[6],bytes[7],bytes[8],bytes[9],bytes[10],bytes[11],bytes[12],bytes[13],bytes[14],bytes[15]))
    }
    public static func expand(_ path: String, home: URL) -> String {
        path.hasPrefix("~/") ? home.appendingPathComponent(String(path.dropFirst(2))).path : path
    }
    public static func resolve(alias: String, config: URL) async throws -> Host {
        guard !alias.isEmpty, !alias.hasPrefix("-"), !alias.contains(where: \.isWhitespace) else { throw ConnectionError.message("Enter one SSH alias per name.") }
        return try await Task.detached {
            let process = Process(), pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            process.arguments = ["-G", "-F", config.path, alias]
            process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
            try process.run()
            let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: timeout)
            defer { timeout.cancel() }
            let output = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
            guard process.terminationStatus == 0, output.count < 2 * 1024 * 1024 else { throw ConnectionError.message("\(alias): OpenSSH could not resolve this host. Check the config or try again.") }
            return try host(alias: alias, resolved: String(decoding: output, as: UTF8.self), home: FileManager.default.homeDirectoryForCurrentUser)
        }.value
    }
    public static func awsProfiles(in text: String) -> [String: AWSCredentials] {
        var sections: [String: [String: String]] = [:], section: String?
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") { continue }
            if line.hasPrefix("["), line.hasSuffix("]") {
                section = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                if section?.hasPrefix("profile ") == true { section = String(section!.dropFirst(8)) }
            } else if let section, let index = line.firstIndex(of: "=") {
                let key = line[..<index].trimmingCharacters(in: .whitespaces).lowercased()
                sections[section, default: [:]][key] = line[line.index(after: index)...].trimmingCharacters(in: .whitespaces)
            }
        }
        return sections.compactMapValues { values in
            guard values["role_arn"] == nil, values["credential_process"] == nil, values["sso_session"] == nil,
                  let id = values["aws_access_key_id"], !id.isEmpty,
                  let secret = values["aws_secret_access_key"], !secret.isEmpty else { return nil }
            let token = values["aws_session_token"].flatMap { $0.isEmpty ? nil : $0 }
            return AWSCredentials(accessKeyID: id, secretAccessKey: secret, sessionToken: token)
        }
    }
}
#endif
