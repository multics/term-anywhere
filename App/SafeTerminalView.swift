import UIKit
import SwiftTerm

/// Native keyboard and text selection with mouse input that follows the remote terminal mode.
final class SafeTerminalView: TerminalView, UIGestureRecognizerDelegate {
    var approvePaste: ((String, @escaping () -> Void) -> Void)?
    var tmuxScrollHandler: ((Int) -> Void)?
    var compositionChanged: (() -> Void)?
    private let compositionDelegate = CompositionInputDelegate()
    var compositionText: String? { markedTextRange.flatMap { text(in: $0) } }

    func observeComposition() {
        // UIKit owns the input delegate. Forward all of its callbacks unchanged.
        if inputDelegate !== compositionDelegate {
            compositionDelegate.forward = inputDelegate
            inputDelegate = compositionDelegate
        }
        compositionDelegate.didChange = { [weak self] in self?.compositionChanged?() }
        compositionChanged?()
    }
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { observeComposition() }
        return result
    }
    override func deleteBackward() {
        guard let marked = markedTextRange, let text = text(in: marked), let selected = selectedTextRange else {
            super.deleteBackward(); return
        }
        // SwiftTerm's default path sends backspaces even for text that was never sent.
        let value = text as NSString
        let start = max(0, min(value.length, offset(from: marked.start, to: selected.start)))
        let end = max(start, min(value.length, offset(from: marked.start, to: selected.end)))
        guard end > start || start > 0 else { return }
        let range = end > start
            ? value.rangeOfComposedCharacterSequences(for: NSRange(location: start, length: end - start))
            : value.rangeOfComposedCharacterSequence(at: start - 1)
        let remaining = value.replacingCharacters(in: range, with: "")
        setMarkedText(remaining.isEmpty ? nil : remaining, selectedRange: NSRange(location: range.location, length: 0))
    }
    override func resignFirstResponder() -> Bool {
        // Leaving the terminal must not send an unfinished composition to the server.
        if markedTextRange != nil { setMarkedText(nil, selectedRange: NSRange(location: 0, length: 0)) }
        let result = super.resignFirstResponder()
        if result { compositionChanged?() }
        return result
    }
    private var touchPan: UIPanGestureRecognizer!
    private var touchTap: UITapGestureRecognizer!
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
        observeComposition()
        touchPan = UIPanGestureRecognizer(target: self, action: #selector(scrollPan(_:)))
        touchPan.maximumNumberOfTouches = 1
        touchPan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        touchPan.delegate = self
        addGestureRecognizer(touchPan)
        panGestureRecognizer.require(toFail: touchPan)
        touchTap = UITapGestureRecognizer(target: self, action: #selector(mouseTap(_:)))
        touchTap.name = "terminal.mouse.tap"
        touchTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        touchTap.delegate = self
        for gesture in gestureRecognizers ?? [] {
            if gesture is UITapGestureRecognizer { gesture.require(toFail: touchTap) }
            if gesture is UILongPressGestureRecognizer { touchTap.require(toFail: gesture) }
        }
        touchTap.require(toFail: touchPan)
        addGestureRecognizer(touchTap)
    }
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === touchTap {
            let terminal = getTerminal()
            let localSelection = gestureRecognizer.modifierFlags.contains(.shift) && !terminal.mouseShiftCapture
            return !selection.active && !localSelection && terminal.mouseMode != .off
        }
        guard gestureRecognizer === touchPan else { return super.gestureRecognizerShouldBegin(gestureRecognizer) }
        let velocity = touchPan.velocity(in: self)
        return abs(velocity.y) > abs(velocity.x) && scrollRoute != .local && scrollRoute != .selection
    }
    override func selectionChanged(source: Terminal) {
        // Long-press Select stays local, including while the remote application produces output.
        allowMouseReporting = !selection.active
        super.selectionChanged(source: source)
    }
    @objc private func mouseTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        var point = gesture.location(in: self); point.y -= contentOffset.y
        tapTouch(at: point)
    }
    func tapTouch(at point: CGPoint) {
        let terminal = getTerminal()
        guard !selection.active, terminal.mouseMode != .off else { return }
        if UIMenuController.shared.isMenuVisible { UIMenuController.shared.hideMenu(); return }
        sendMouseEvent(0, at: point)
        if terminal.mouseMode != .x10 { sendMouseEvent(3, at: point) }
        // A pane-selection tap must also work with the keyboard hidden, without opening it.
    }
    private func sendMouseEvent(_ flags: Int, at point: CGPoint) {
        let terminal = getTerminal(), frame = getOptimalFrameSize()
        let col = max(0, min(terminal.cols - 1, Int(point.x / max(1, frame.width / CGFloat(max(1, terminal.cols))))))
        let row = max(0, min(terminal.rows - 1, Int(point.y / max(1, frame.height / CGFloat(max(1, terminal.rows))))))
        terminal.sendEvent(buttonFlags: flags, x: col, y: row,
                           pixelX: Int(max(0, min(frame.width - 1, point.x))),
                           pixelY: Int(max(0, min(frame.height - 1, point.y))))
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
            for _ in 0..<count { sendMouseEvent(lines > 0 ? 64 : 65, at: point) }
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

@MainActor private final class CompositionInputDelegate: NSObject, UITextInputDelegate {
    weak var forward: UITextInputDelegate?
    var didChange: (() -> Void)?
    func conversationContext(_ context: UIConversationContext?, didChange textInput: UITextInput?) {
        forward?.conversationContext(context, didChange: textInput)
    }
    func selectionWillChange(_ textInput: UITextInput?) { forward?.selectionWillChange(textInput) }
    func selectionDidChange(_ textInput: UITextInput?) {
        forward?.selectionDidChange(textInput); didChange?()
    }
    func textWillChange(_ textInput: UITextInput?) { forward?.textWillChange(textInput) }
    func textDidChange(_ textInput: UITextInput?) {
        forward?.textDidChange(textInput); didChange?()
    }
}
