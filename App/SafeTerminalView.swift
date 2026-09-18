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
    var paneResizeAvailable = false {
        didSet { if !paneResizeAvailable { setPaneResizeMode(false) } }
    }
    var resolveResizeStart: ((CGPoint) async -> CGPoint?)?
    private var resizeStartTask: Task<Void, Never>?
    private var pendingDragPoint: CGPoint?
    private var dragOffset = CGPoint.zero
    var resizeDragEnded: (() -> Void)?
    var isDraggingPane: Bool { isResizingPanes && (dragPoint != nil || pendingDragPoint != nil) }
    private var lastMotionCell: CGPoint?
    var resizeModeChanged: ((Bool) -> Void)?
    private(set) var isResizingPanes = false
    private var suspendedResizeGestures: [UIGestureRecognizer] = []
    private var resizeTap: UITapGestureRecognizer!
    func setPaneResizeMode(_ enabled: Bool, sendRelease: Bool = true) {
        endMouseDrag(sendRelease: sendRelease)
        let enabled = enabled && paneResizeAvailable && canDragMouse
        guard enabled != isResizingPanes else { return }
        isResizingPanes = enabled
        mouseDrag.minimumNumberOfTouches = enabled ? 1 : 2
        mouseDrag.maximumNumberOfTouches = enabled ? 1 : 2
        if enabled {
            // SwiftTerm's long press and selection pans must not steal a border drag.
            suspendedResizeGestures = (gestureRecognizers ?? []).filter {
                $0 !== mouseDrag && $0 !== resizeTap && $0 !== touchTap && $0.isEnabled &&
                ($0 is UIPanGestureRecognizer || $0 is UITapGestureRecognizer || $0 is UILongPressGestureRecognizer)
            }
            suspendedResizeGestures.forEach { $0.isEnabled = false }
        } else {
            suspendedResizeGestures.forEach { $0.isEnabled = true }
            suspendedResizeGestures.removeAll()
        }
        resizeModeChanged?(enabled)
    }
    @objc private func togglePaneResize(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        setPaneResizeMode(!isResizingPanes)
    }
    private var mouseDrag: UIPanGestureRecognizer!
    private var dragPoint: CGPoint?
    var canDragMouse: Bool {
        !selection.active && [.buttonEventTracking, .anyEvent].contains(getTerminal().mouseMode)
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
        mouseDrag = UIPanGestureRecognizer(target: self, action: #selector(dragMouse(_:)))
        mouseDrag.name = "terminal.mouse.drag"
        mouseDrag.minimumNumberOfTouches = 2; mouseDrag.maximumNumberOfTouches = 2
        mouseDrag.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        mouseDrag.delegate = self
        addGestureRecognizer(mouseDrag)
        panGestureRecognizer.require(toFail: mouseDrag)
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
        resizeTap = UITapGestureRecognizer(target: self, action: #selector(togglePaneResize(_:)))
        resizeTap.name = "terminal.pane.resize.toggle"
        resizeTap.numberOfTapsRequired = 2
        resizeTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        resizeTap.delegate = self
        for gesture in gestureRecognizers ?? [] where gesture is UITapGestureRecognizer {
            gesture.require(toFail: resizeTap)
        }
        addGestureRecognizer(resizeTap)
        touchPan.require(toFail: mouseDrag)
    }
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === resizeTap { return isResizingPanes || (paneResizeAvailable && canDragMouse) }
        if gestureRecognizer === mouseDrag { return canDragMouse }
        if gestureRecognizer === touchTap {
            let terminal = getTerminal()
            let localSelection = gestureRecognizer.modifierFlags.contains(.shift) && !terminal.mouseShiftCapture
            return !selection.active && !localSelection && terminal.mouseMode != .off
        }
        guard gestureRecognizer === touchPan else { return super.gestureRecognizerShouldBegin(gestureRecognizer) }
        let velocity = touchPan.velocity(in: self)
        return !isResizingPanes && abs(velocity.y) > abs(velocity.x) && scrollRoute != .local && scrollRoute != .selection
    }
    override func selectionChanged(source: Terminal) {
        // Long-press Select stays local, including while the remote application produces output.
        if selection.active { setPaneResizeMode(false) }
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
        guard !isResizingPanes, !selection.active, terminal.mouseMode != .off else { return }
        if UIMenuController.shared.isMenuVisible { UIMenuController.shared.hideMenu(); return }
        sendMouseEvent(0, at: point)
        if terminal.mouseMode != .x10 { sendMouseEvent(3, at: point) }
        // A pane-selection tap must also work with the keyboard hidden, without opening it.
    }
    @objc private func dragMouse(_ gesture: UIPanGestureRecognizer) {
        var point = gesture.location(in: self); point.y -= contentOffset.y
        switch gesture.state {
        case .began:
            // UIKit recognizes a pan after movement: press at the original border.
            let translation = gesture.translation(in: self)
            beginMouseDrag(at: CGPoint(x: point.x - translation.x, y: point.y - translation.y))
            moveMouseDrag(to: point)
        case .changed: moveMouseDrag(to: point)
        case .ended: moveMouseDrag(to: point); endMouseDrag()
        case .cancelled, .failed: endMouseDrag()
        default: break
        }
    }
    func beginMouseDrag(at point: CGPoint) {
        endMouseDrag()
        guard canDragMouse else { return }
        guard isResizingPanes else { startMouseDrag(at: point); return }
        // Never send a press on text in resize mode. Resolve a real server border first.
        guard let resolveResizeStart else { return }
        pendingDragPoint = point
        resizeStartTask = Task { [weak self] in
            guard let border = await resolveResizeStart(point), !Task.isCancelled,
                  let self, self.isResizingPanes, self.canDragMouse,
                  let latest = self.pendingDragPoint else { return }
            self.pendingDragPoint = nil
            self.dragOffset = CGPoint(x: border.x - point.x, y: border.y - point.y)
            self.startMouseDrag(at: border)
            self.moveMouseDrag(to: latest)
        }
    }
    private func startMouseDrag(at point: CGPoint) {
        dragPoint = point
        sendMouseEvent(0, at: point)
    }
    func moveMouseDrag(to point: CGPoint) {
        if pendingDragPoint != nil { pendingDragPoint = point; return }
        guard dragPoint != nil else { return }
        guard canDragMouse else {
            // tmux can suspend mouse reporting during redraw; keep the held drag.
            if !isResizingPanes { endMouseDrag() }
            return
        }
        let adjusted = CGPoint(x: point.x + dragOffset.x, y: point.y + dragOffset.y)
        dragPoint = adjusted
        sendMouseEvent(32, at: adjusted)
    }
    func endMouseDrag(sendRelease: Bool = true) {
        let wasResizing = isDraggingPane
        defer { if wasResizing { resizeDragEnded?() } }
        lastMotionCell = nil
        resizeStartTask?.cancel(); resizeStartTask = nil
        pendingDragPoint = nil; dragOffset = .zero
        guard let point = dragPoint else { return }
        dragPoint = nil
        if sendRelease && [.vt200, .buttonEventTracking, .anyEvent].contains(getTerminal().mouseMode) {
            sendMouseEvent(3, at: point)
        }
    }
    override func willMove(toWindow newWindow: UIWindow?) {
        if newWindow == nil { setPaneResizeMode(false) }
        super.willMove(toWindow: newWindow)
    }
    /// tmux pane rectangles exclude the status rows. Choose the nearest internal border.
    static func nearestPaneBorder(_ output: String, to point: CGPoint, cell: CGSize,
                                  columns: Int, rows: Int) -> CGPoint? {
        var candidates: [CGPoint] = []
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 8, let x = Int(fields[0]), let y = Int(fields[1]),
                  let width = Int(fields[2]), let height = Int(fields[3]),
                  let windowWidth = Int(fields[4]), let windowHeight = Int(fields[5]),
                  fields[7] == "0", windowWidth == columns, windowHeight <= rows,
                  x >= 0, y >= 0, width > 0, height > 0 else { continue }
            let top = fields[6] == "top" ? rows - windowHeight : 0
            let minX = (CGFloat(x) + 0.5) * cell.width
            let minY = (CGFloat(y + top) + 0.5) * cell.height
            if x + width < windowWidth {
                candidates.append(CGPoint(x: (CGFloat(x + width) + 0.5) * cell.width,
                    y: max(minY, min(point.y, (CGFloat(y + top + height) - 0.5) * cell.height))))
            }
            if y + height < windowHeight {
                candidates.append(CGPoint(x: max(minX, min(point.x, (CGFloat(x + width) - 0.5) * cell.width)),
                    y: (CGFloat(y + top + height) + 0.5) * cell.height))
            }
        }
        return candidates.min {
            hypot($0.x - point.x, $0.y - point.y) < hypot($1.x - point.x, $1.y - point.y)
        }
    }
    private func sendMouseEvent(_ flags: Int, at point: CGPoint) {
        let terminal = getTerminal(), frame = getOptimalFrameSize()
        let col = max(0, min(terminal.cols - 1, Int(point.x / max(1, frame.width / CGFloat(max(1, terminal.cols))))))
        let row = max(0, min(terminal.rows - 1, Int(point.y / max(1, frame.height / CGFloat(max(1, terminal.rows))))))
        // tmux resizes by cells. Repeating sub-cell motion only adds network backlog.
        if flags == 32 && isResizingPanes {
            let cell = CGPoint(x: col, y: row)
            guard cell != lastMotionCell else { return }
            lastMotionCell = cell
        }
        terminal.sendEvent(buttonFlags: flags, x: col, y: row,
                           pixelX: Int(max(0, min(frame.width - 1, point.x))),
                           pixelY: Int(max(0, min(frame.height - 1, point.y))))
    }
    override func mouseModeChanged(source: Terminal) {
        // SwiftTerm also calls this during initialization, before its terminal exists.
        // Reporting negotiation is not an exit from the user's explicit resize mode.
        // tmux redraws can turn reporting off and back on, even in separate reads.
        if dragPoint != nil && !isResizingPanes && !canDragMouse { endMouseDrag() }
        // Keep SwiftTerm's pointer gesture separate from direct-touch gestures.
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
        guard !isResizingPanes, lines != 0, dragPoint == nil else { return }
        lastScrollTranslation += CGFloat(lines) * rowHeight
        var point = gesture.location(in: self); point.y -= contentOffset.y
        scrollTouch(lines: lines, at: point)
    }
    /// Positive lines reveal older content. Normal-buffer scrolling stays with UIScrollView.
    func scrollTouch(lines: Int, at point: CGPoint) {
        guard !isResizingPanes, lines != 0, dragPoint == nil else { return }
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
