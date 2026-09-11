import Foundation

public struct TmuxSessionList: Equatable, Sendable {
    public let isAvailable: Bool
    public let names: [String]
    public init(output: String) throws {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let marker = lines.first, marker == "TERM_ANYWHERE_TMUX_AVAILABLE" || marker == "TERM_ANYWHERE_TMUX_UNAVAILABLE" else {
            throw ConnectionError.message("The server returned an unreadable tmux session list.")
        }
        isAvailable = marker == "TERM_ANYWHERE_TMUX_AVAILABLE"
        names = isAvailable ? Set(lines.dropFirst().filter { !$0.isEmpty }).sorted() : []
    }
}
