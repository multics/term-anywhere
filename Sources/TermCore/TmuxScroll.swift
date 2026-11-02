import Foundation

/// Read the PTY identity before exec replaces the shell with the tmux client.
/// The random OSC marker is removed even when SSH splits it across reads.
struct TmuxClientHandshake {
    let token: String
    private var buffered = Data()
    private(set) var tty: String?
    private(set) var complete = false
    init(token: String = UUID().uuidString) { self.token = token }
    var prefix: Data { Data("\u{1b}]777;term-anywhere-\(token);".utf8) }
    var command: String { "printf '\\033]777;term-anywhere-\(token);%s\\007' \"$(tty)\"; " }
    mutating func consume(_ data: Data) -> Data {
        guard !complete else { return data }
        buffered.append(data)
        if let start = buffered.range(of: prefix) {
            let before = Data(buffered[..<start.lowerBound])
            if let end = buffered[start.upperBound...].firstIndex(of: 7) {
                let value = String(decoding: buffered[start.upperBound..<end], as: UTF8.self)
                if value.range(of: "^/dev/[A-Za-z0-9_./-]+$", options: .regularExpression) != nil { tty = value }
                complete = true
                let result = before + buffered[buffered.index(after: end)...]
                buffered.removeAll(); return result
            }
            if buffered.count > 4096 { complete = true; let result = buffered; buffered.removeAll(); return result }
            buffered = Data(buffered[start.lowerBound...]); return before
        }
        // Retain only a possible partial marker, never ordinary terminal output.
        var keep = min(buffered.count, prefix.count - 1)
        while keep > 0 && buffered.suffix(keep) != prefix.prefix(keep) { keep -= 1 }
        let result = Data(buffered.prefix(buffered.count - keep))
        buffered = Data(buffered.suffix(keep)); return result
    }
}

enum TmuxViewport {
    static func command(tmux: String, tty: String, columns: Int) -> String {
        let move = columns == 0 ? "-c" : "\(columns > 0 ? "-R" : "-L") \(min(240, max(-240, columns).magnitude))"
        return "\(tmux) refresh-client -t \(shellQuote(tty)) \(move)"
    }
}

/// Resolve history ownership from tmux state, without inspecting application names or key bindings.
public struct TmuxScroll: Equatable, Sendable {
    public let paneID: String
    public let mode: String
    public let alternateScreen: Bool
    public init(state: String) throws {
        let fields = state.trimmingCharacters(in: .newlines).components(separatedBy: "|")
        guard fields.count == 3, fields[0].range(of: "^%[0-9]+$", options: .regularExpression) != nil,
              ["0", "1"].contains(fields[2]) else { throw ConnectionError.message("Cannot read the active tmux pane.") }
        paneID = fields[0]; mode = fields[1]; alternateScreen = fields[2] == "1"
    }
    public func command(tmux: String, lines: Int) throws -> String? {
        guard lines != 0 else { return nil }
        let count = abs(max(-30, min(30, lines))), pane = shellQuote(paneID)
        if mode.isEmpty && alternateScreen {
            return "\(tmux) send-keys -t \(pane) -N \(count) \(lines > 0 ? "Up" : "Down")"
        }
        guard mode.isEmpty || mode == "copy-mode" else { throw ConnectionError.message("Finish the tmux chooser before scrolling history.") }
        if mode.isEmpty && lines < 0 { return nil }
        let enter = mode.isEmpty ? "\(tmux) copy-mode -e -t \(pane) && " : ""
        var command = enter + "\(tmux) send-keys -X -t \(pane) -N \(count) \(lines > 0 ? "scroll-up" : "scroll-down")"
        if lines < 0 {
            command += "; if [ \"$(\(tmux) display-message -p -t \(pane) '#{scroll_position}')\" = 0 ]; then \(tmux) send-keys -X -t \(pane) cancel; fi"
        }
        return command
    }
}
