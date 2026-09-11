import Foundation

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
