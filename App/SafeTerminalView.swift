import UIKit
import SwiftTerm

/// Keep the system input method; only add a preview for pastes that can submit commands.
final class SafeTerminalView: TerminalView, UIGestureRecognizerDelegate {
    var approvePaste: ((String, @escaping () -> Void) -> Void)?
    var tmuxScrollHandler: ((Int) -> Void)?
    private var touchPan: UIPanGestureRecognizer!
    private var lastScrollTranslation: CGFloat = 0
    enum ScrollRoute { case selection, local, mouse, tmux, alternate }
    var scrollRoute: ScrollRoute {
        let terminal = getTerminal()
        if selection.active { return .selection }
        if terminal.mouseMode != .off { return .mouse }
        if tmuxScrollHandler != nil { return .tmux }
        if terminal.isCurrentBufferAlternate {
            if terminal.alternateScrollMode { return .alternate }
        }
        return .local
    }
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureTouchPan()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureTouchPan()
    }
    private func configureTouchPan() {
        touchPan = UIPanGestureRecognizer(target: self, action: #selector(scrollPan(_:)))
        touchPan.maximumNumberOfTouches = 1
        touchPan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        touchPan.delegate = self
        addGestureRecognizer(touchPan)
        panGestureRecognizer.require(toFail: touchPan)
    }
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === touchPan else { return super.gestureRecognizerShouldBegin(gestureRecognizer) }
        let velocity = touchPan.velocity(in: self)
        return abs(velocity.y) > abs(velocity.x) && scrollRoute != .local && scrollRoute != .selection
    }
    override func mouseModeChanged(source: Terminal) {
        // Keep SwiftTerm's pointer gesture, but direct touch uses wheel input instead of a button drag.
        let previous = Set((gestureRecognizers ?? []).map(ObjectIdentifier.init))
        super.mouseModeChanged(source: source)
        for gesture in gestureRecognizers ?? [] where !previous.contains(ObjectIdentifier(gesture)) {
            gesture.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]
        }
    }
    @objc private func scrollPan(_ gesture: UIPanGestureRecognizer) {
        if gesture.state == .began { lastScrollTranslation = 0 }
        guard gesture.state == .began || gesture.state == .changed else { return }
        let translation = gesture.translation(in: self).y
        let rowHeight = max(1, getOptimalFrameSize().height / CGFloat(max(1, getTerminal().rows)))
        let lines = Int((translation - lastScrollTranslation) / rowHeight)
        guard lines != 0 else { return }
        lastScrollTranslation += CGFloat(lines) * rowHeight
        var point = gesture.location(in: self); point.y -= contentOffset.y
        scrollTouch(lines: lines, at: point)
    }
    /// Positive lines reveal older content. Normal-buffer scrolling stays with UIScrollView.
    func scrollTouch(lines: Int, at point: CGPoint) {
        guard lines != 0 else { return }
        let terminal = getTerminal(), count = min(30, abs(lines))
        switch scrollRoute {
        case .local, .selection: return
        case .tmux: tmuxScrollHandler?(lines > 0 ? count : -count)
        case .alternate:
            let key = "\u{1b}" + (terminal.applicationCursor ? "O" : "[") + (lines > 0 ? "A" : "B")
            send(txt: String(repeating: key, count: count))
        case .mouse:
            let frame = getOptimalFrameSize()
            let col = max(0, min(terminal.cols - 1, Int(point.x / max(1, frame.width / CGFloat(max(1, terminal.cols))))))
            let row = max(0, min(terminal.rows - 1, Int(point.y / max(1, frame.height / CGFloat(max(1, terminal.rows))))))
            for _ in 0..<count {
                terminal.sendEvent(buttonFlags: lines > 0 ? 64 : 65, x: col, y: row,
                                   pixelX: Int(max(0, min(frame.width - 1, point.x))),
                                   pixelY: Int(max(0, min(frame.height - 1, point.y))))
            }
        }
    }
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
