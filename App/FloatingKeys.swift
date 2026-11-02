import UIKit
import Combine
import SwiftTerm

/// Only the six requested keys; use the terminal's negotiated cursor/keyboard modes.
enum FloatingTerminalKey: Int, CaseIterable {
    case escape, up, shift, left, down, right
    var label: String { ["Escape", "Up arrow", "Shift", "Left arrow", "Down arrow", "Right arrow"][rawValue] }
    var symbol: String? { [nil, "arrow.up", "shift", "arrow.left", "arrow.down", "arrow.right"][rawValue] }
    func sequence(shifted: Bool, applicationCursor: Bool, flags: KittyKeyboardFlags = [], event: Int = 1) -> String {
        guard self != .shift else { return "" }
        let reportsEvents = flags.contains(.reportEvents)
        if event == 3 && !reportsEvents { return "" }
        let modifier = shifted ? 2 : 1
        let suffix = reportsEvents && event != 1 ? ":\(event)" : ""
        if self == .escape {
            if flags.contains(.disambiguate) || flags.contains(.reportAllKeys) {
                return "\u{1b}[27;\(modifier)\(suffix)u"
            }
            return event == 3 ? "" : "\u{1b}"
        }
        let letter = self == .up ? "A" : self == .down ? "B" : self == .right ? "C" : "D"
        if shifted || !suffix.isEmpty { return "\u{1b}[1;\(modifier)\(suffix)\(letter)" }
        return "\u{1b}" + (applicationCursor && flags.isEmpty ? "O" : "[") + letter
    }
}

@MainActor final class FloatingKeyInput: ObservableObject {
    @Published private(set) var shifted = false
    var enabled = false { didSet { if !enabled { reset() } } }
    var emit: ((FloatingTerminalKey, Bool, Int) -> Void)?
    private var heldShift = false
    private var shiftUsed = false
    private var wasArmed = false
    private var pressed: (FloatingTerminalKey, Bool)?
    private var repeating: Task<Void, Never>?

    func shiftDown() {
        guard enabled else { return }
        wasArmed = shifted; heldShift = true; shiftUsed = false; shifted = true
    }
    func shiftUp(cancelled: Bool = false) {
        guard heldShift else { return }
        heldShift = false
        shifted = !cancelled && !shiftUsed && !wasArmed
    }
    func press(_ key: FloatingTerminalKey) {
        guard enabled, key != .shift else { return }
        release()
        let modifier = shifted
        if heldShift { shiftUsed = true } else { shifted = false }
        pressed = (key, modifier)
        emit?(key, modifier, 1)
        guard key != .escape else { return }
        repeating = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(400))
                while !Task.isCancelled {
                    guard let self, self.enabled, let (key, modifier) = self.pressed else { return }
                    self.emit?(key, modifier, 2)
                    try await Task.sleep(for: .milliseconds(75))
                }
            } catch { }
        }
    }
    func release() {
        repeating?.cancel(); repeating = nil
        if let (key, modifier) = pressed { emit?(key, modifier, 3) }
        pressed = nil
    }
    func reset() {
        release(); heldShift = false; shiftUsed = false; wasArmed = false; shifted = false
    }
}

/// A small native overlay. Only its handle owns the drag gesture.
@MainActor final class FloatingKeyPalette: UIView {
    static let paletteSize = CGSize(width: 156, height: 148)
    private let input: FloatingKeyInput
    private let preferences: UserDefaults
    private var buttons: [FloatingTerminalKey: UIButton] = [:]
    private var shiftObservation: AnyCancellable?
    private var dragOrigin = CGPoint.zero
    private var moving = false
    private var allowedBounds = CGRect.zero
    private var keyboardAvoidance: CGRect?
    private var normalizedPosition: CGPoint
    private let material = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))

    init(input: FloatingKeyInput, preferences: UserDefaults = .standard) {
        self.input = input; self.preferences = preferences
        normalizedPosition = CGPoint(x: preferences.object(forKey: "floatingKeys.x") as? Double ?? 1,
                                     y: preferences.object(forKey: "floatingKeys.y") as? Double ?? 1)
        super.init(frame: CGRect(origin: .zero, size: Self.paletteSize))
        accessibilityIdentifier = "terminal.floatingKeys"
        layer.cornerRadius = 16; clipsToBounds = true
        material.frame = bounds; material.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(material)
        let handle = UIView(frame: CGRect(x: 8, y: 0, width: 140, height: 44))
        handle.accessibilityLabel = "Move floating keys"; handle.isAccessibilityElement = true
        handle.accessibilityHint = "Drag to move the controls."
        handle.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Move to left edge", actionHandler: { [weak self] _ in self?.moveToEdge(x: 0); return true }),
            UIAccessibilityCustomAction(name: "Move to right edge", actionHandler: { [weak self] _ in self?.moveToEdge(x: 1); return true })
        ]
        handle.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(drag(_:))))
        let grip = UIView(frame: CGRect(x: 52, y: 20, width: 36, height: 4))
        grip.backgroundColor = .tertiaryLabel; grip.layer.cornerRadius = 2; grip.isUserInteractionEnabled = false
        handle.addSubview(grip); material.contentView.addSubview(handle)
        for key in FloatingTerminalKey.allCases {
            let button = UIButton(type: .system)
            var config = UIButton.Configuration.plain()
            if let symbol = key.symbol { config.image = UIImage(systemName: symbol) } else { config.title = "esc" }
            config.contentInsets = NSDirectionalEdgeInsets(top: 2, leading: 2, bottom: 2, trailing: 2)
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var result = attributes; result.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .medium); return result
            }
            config.baseForegroundColor = .label
            config.background.backgroundColor = .secondarySystemFill
            config.background.cornerRadius = 9
            button.configuration = config
            button.tag = key.rawValue; button.accessibilityLabel = key.label
            button.accessibilityIdentifier = "terminal.key.\(key)"
            button.frame = CGRect(x: 8 + (key.rawValue % 3) * 48, y: 48 + (key.rawValue / 3) * 48, width: 44, height: 44)
            button.isExclusiveTouch = false
            button.addTarget(self, action: #selector(keyDown(_:)), for: .touchDown)
            button.addTarget(self, action: #selector(keyUp(_:)), for: [.touchUpInside, .touchUpOutside])
            button.addTarget(self, action: #selector(keyCancel(_:)), for: [.touchCancel, .touchDragExit])
            button.addTarget(self, action: #selector(accessiblePress(_:)), for: .primaryActionTriggered)
            material.contentView.addSubview(button); buttons[key] = button
        }
        shiftObservation = input.$shifted.sink { [weak self] shifted in
            let button = self?.buttons[.shift]
            button?.configuration?.baseForegroundColor = shifted ? .white : .label
            button?.configuration?.background.backgroundColor = shifted ? .systemBlue : .secondarySystemFill
            button?.accessibilityValue = shifted ? "On" : "Off"
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    @objc private func keyDown(_ button: UIButton) {
        guard let key = FloatingTerminalKey(rawValue: button.tag) else { return }
        if key == .shift { input.shiftDown() } else { input.press(key) }
    }
    @objc private func keyUp(_ button: UIButton) {
        if button.tag == FloatingTerminalKey.shift.rawValue { input.shiftUp() } else { input.release() }
    }
    @objc private func keyCancel(_ button: UIButton) {
        if button.tag == FloatingTerminalKey.shift.rawValue { input.shiftUp(cancelled: true) } else { input.release() }
    }
    @objc private func accessiblePress(_ button: UIButton) {
        // UIKit emits primaryActionTriggered for physical taps too. Only synthesize
        // a complete press here when VoiceOver owns activation.
        guard UIAccessibility.isVoiceOverRunning else { return }
        keyDown(button); keyUp(button)
    }
    static func constrainedOrigin(_ proposed: CGPoint, in bounds: CGRect, avoiding keyboard: CGRect? = nil) -> CGPoint {
        let maxX = max(bounds.minX, bounds.maxX - paletteSize.width)
        let maxY = max(bounds.minY, bounds.maxY - paletteSize.height)
        var point = CGPoint(x: min(maxX, max(bounds.minX, proposed.x)), y: min(maxY, max(bounds.minY, proposed.y)))
        if let keyboard, CGRect(origin: point, size: paletteSize).intersects(keyboard) {
            point.y = max(bounds.minY, keyboard.minY - paletteSize.height - 8)
        }
        return point
    }
    func place(in bounds: CGRect, avoiding keyboard: CGRect?) {
        allowedBounds = bounds.insetBy(dx: 8, dy: 8); keyboardAvoidance = keyboard
        if moving {
            frame.origin = Self.constrainedOrigin(frame.origin, in: allowedBounds, avoiding: keyboard)
            return
        }
        let span = CGSize(width: max(0, allowedBounds.width - Self.paletteSize.width),
                          height: max(0, allowedBounds.height - Self.paletteSize.height))
        frame.origin = Self.constrainedOrigin(CGPoint(x: allowedBounds.minX + span.width * normalizedPosition.x,
                                                     y: allowedBounds.minY + span.height * normalizedPosition.y),
                                              in: allowedBounds, avoiding: keyboard)
    }
    private func moveToEdge(x: CGFloat) {
        normalizedPosition.x = x
        preferences.set(x, forKey: "floatingKeys.x")
        if let parent = superview { place(in: parent.bounds.inset(by: parent.safeAreaInsets), avoiding: keyboardAvoidance) }
    }
    @objc private func drag(_ gesture: UIPanGestureRecognizer) {
        guard let parent = superview else { return }
        if gesture.state == .began { input.reset(); moving = true; dragOrigin = frame.origin }
        if gesture.state == .began || gesture.state == .changed || gesture.state == .ended {
            let delta = gesture.translation(in: parent)
            frame.origin = Self.constrainedOrigin(CGPoint(x: dragOrigin.x + delta.x, y: dragOrigin.y + delta.y),
                                                  in: allowedBounds, avoiding: keyboardAvoidance)
        }
        if gesture.state == .ended || gesture.state == .cancelled {
            moving = false
            normalizedPosition = CGPoint(x: (frame.minX - allowedBounds.minX) / max(1, allowedBounds.width - frame.width),
                                         y: (frame.minY - allowedBounds.minY) / max(1, allowedBounds.height - frame.height))
            preferences.set(normalizedPosition.x, forKey: "floatingKeys.x")
            preferences.set(normalizedPosition.y, forKey: "floatingKeys.y")
        }
    }
    override func willMove(toWindow newWindow: UIWindow?) {
        if newWindow == nil { input.reset() }
        super.willMove(toWindow: newWindow)
    }
}
