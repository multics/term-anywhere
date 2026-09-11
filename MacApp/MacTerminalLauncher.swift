import AppKit
import Combine
import TermCore

@MainActor final class MacTerminalLauncher: ObservableObject {
    struct Application: Identifiable {
        let id: String
        let name: String
        let url: URL
    }
    @Published private(set) var applications: [Application] = []
    @Published var defaultID: String {
        didSet { UserDefaults.standard.set(defaultID, forKey: "mac.defaultTerminal") }
    }
    init() {
        defaultID = UserDefaults.standard.string(forKey: "mac.defaultTerminal") ?? "com.apple.Terminal"
        refresh()
    }
    func refresh() {
        applications = [("com.apple.Terminal", "Terminal"), ("com.mitchellh.ghostty", "Ghostty")].compactMap { id, name in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).map { Application(id: id, name: name, url: $0) }
        }
        if !applications.contains(where: { $0.id == defaultID }), let first = applications.first { defaultID = first.id }
    }
    func connect(_ host: TermCore.Host, vault: KeychainStore) async throws {
        refresh()
        guard let app = applications.first(where: { $0.id == defaultID }) else {
            throw ConnectionError.message("No supported terminal app was found. Install Terminal or Ghostty, then refresh Settings.")
        }
        guard let key = try vault.read(account: "key:" + host.keyID) else {
            throw ConnectionError.message("Import the SSH key named \(host.keyID).")
        }
        let aws = host.isSSM ? try vault.read(account: "aws:" + host.awsProfile).map { try JSONDecoder().decode(AWSCredentials.self, from: $0) } : nil
        let executable = ["/opt/homebrew/bin/aws", "/usr/local/bin/aws"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map { URL(fileURLWithPath: $0) }
        if host.isSSM, !["/opt/homebrew/bin/session-manager-plugin", "/usr/local/bin/session-manager-plugin"].contains(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            throw ConnectionError.message("Install Session Manager Plugin on this Mac to connect through SSM.")
        }
        let session = try ExternalSSHSession(host: host, privateKey: key, aws: aws, awsExecutable: executable)
        do { try await open(script: session.script, in: app) }
        catch { session.remove(); throw error }
    }
    func open(script: URL, in app: Application) async throws {
        if app.id == "com.mitchellh.ghostty" {
            // Ghostty documents macOS command launch through open -na --args.
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
            process.arguments = ["-n", "-a", app.url.path, "--args", "-e", "/bin/zsh", script.path]
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                process.terminationHandler = { result in
                    if result.terminationStatus == 0 { continuation.resume() }
                    else { continuation.resume(throwing: ConnectionError.message("Ghostty could not open the connection window.")) }
                }
                do { try process.run() } catch { continuation.resume(throwing: error) }
            }
        } else {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            _ = try await NSWorkspace.shared.open([script], withApplicationAt: app.url, configuration: configuration)
        }
    }
}
