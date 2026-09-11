import UIKit
import SwiftTerm

/// Keep the system input method; only add a preview for pastes that can submit commands.
final class SafeTerminalView: TerminalView {
    var approvePaste: ((String, @escaping () -> Void) -> Void)?
    override func paste(_ sender: Any?) {
        guard let text = UIPasteboard.general.string else { return }
        let insert = { [weak self] in
            guard let self else { return }
            if self.getTerminal().bracketedPasteMode { self.send(txt: "\u{1b}[200~") }
            self.send(txt: text)
            if self.getTerminal().bracketedPasteMode { self.send(txt: "\u{1b}[201~") }
        }
        if text.contains("\n") || text.contains("\r") || text.contains("\u{1b}") {
            approvePaste?(text, insert)
        } else { insert() }
    }
}
