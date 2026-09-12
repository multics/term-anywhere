import Foundation

public struct TmuxShortcut: Identifiable, Equatable, Sendable {
    public var id: String { title }
    public let title: String
    public let keys: String
    public let bytes: Data
}
public struct TmuxBindings: Sendable {
    public let prefix: String
    public let shortcuts: [TmuxShortcut]
    public init(prefix: String, listing: String) {
        self.prefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        var found: [String: [TmuxShortcut]] = [:]
        for line in listing.split(separator: "\n") {
            guard let tokens = Self.tokens(String(line)), tokens.first == "bind-key",
                  let tableFlag = tokens.firstIndex(of: "-T"), tableFlag + 3 < tokens.count else { continue }
            let table = tokens[tableFlag + 1]
            guard table == "prefix" || table == "root" else { continue }
            let key = tokens[tableFlag + 2], command = Array(tokens[(tableFlag + 3)...])
            // Only map commands whose entire structure is understood. No scripts or command chains.
            guard !command.contains(where: { $0.contains(";") || $0.contains("\n") }),
                  let title = Self.title(command), let keyBytes = Self.keyBytes(key) else { continue }
            var bytes = Data()
            if table == "prefix" {
                guard let p = Self.keyBytes(self.prefix), !p.isEmpty else { continue }
                bytes.append(p)
            }
            bytes.append(keyBytes)
            found[title, default: []].append(TmuxShortcut(title: title, keys: table == "prefix" ? "\(self.prefix) → \(key)" : key, bytes: bytes))
        }
        // Keep frequent navigation actions first in both terminal menus.
        let order = ["Zoom pane", "Next window", "Previous window", "New window", "Split side by side", "Split top and bottom", "Copy mode"]
        shortcuts = order.compactMap { title in
            guard let candidates = found[title], candidates.count == 1 else { return nil }
            return candidates[0]
        }
    }
    private static func title(_ command: [String]) -> String? {
        guard let name = command.first else { return nil }
        let exact: [String: String] = ["new-window": "New window", "previous-window": "Previous window", "next-window": "Next window", "copy-mode": "Copy mode"]
        if command.count == 1 { return exact[name] ?? (name == "split-window" ? "Split top and bottom" : nil) }
        if command == ["resize-pane", "-Z"] { return "Zoom pane" }
        if name == "split-window" || name == "new-window" {
            var args = Array(command.dropFirst()); var horizontal = false
            if args.first == "-h" || args.first == "-v" { horizontal = args.removeFirst() == "-h" }
            if args == ["-c", "#{pane_current_path}"] { args = [] }
            guard args.isEmpty else { return nil }
            return name == "new-window" ? "New window" : horizontal ? "Split side by side" : "Split top and bottom"
        }
        return nil
    }
    public static func keyBytes(_ key: String) -> Data? {
        if key == "None" || key.isEmpty { return nil }
        if key.hasPrefix("M-"), let rest = keyBytes(String(key.dropFirst(2))) { return Data([27]) + rest }
        if key.hasPrefix("C-"), key.count == 3, let c = key.uppercased().utf8.last {
            if c == 63 { return Data([127]) }
            if (64...95).contains(c) { return Data([c & 31]) }
            if c == 32 { return Data([0]) }
        }
        let named: [String: [UInt8]] = ["Space": [32], "Enter": [13], "Escape": [27], "Tab": [9], "BSpace": [127]]
        if let b = named[key] { return Data(b) }
        // Cursor/function encodings depend on the current terminal mode. Do not guess here.
        if key.utf8.count == 1, let c = key.utf8.first, (32...126).contains(c) { return Data([c]) }
        return nil
    }
    static func tokens(_ text: String) -> [String]? {
        var result: [String] = [], word = "", quote: Character?, escape = false, active = false
        for c in text {
            if escape { word.append(c); escape = false; active = true; continue }
            if c == "\\", quote != "'" { escape = true; continue }
            if let q = quote { if c == q { quote = nil } else { word.append(c) }; active = true; continue }
            if c == "\"" || c == "'" { quote = c; active = true; continue }
            if c.isWhitespace { if active { result.append(word); word = ""; active = false } }
            else { word.append(c); active = true }
        }
        guard quote == nil, !escape else { return nil }
        if active { result.append(word) }
        return result
    }
}
