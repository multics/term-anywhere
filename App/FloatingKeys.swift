import UIKit
import Combine
import SwiftTerm

struct FloatingModifiers: OptionSet {
    let rawValue: Int
    static let shift = Self(rawValue: 1)
    static let alt = Self(rawValue: 2)
    static let control = Self(rawValue: 4)
}

/// Encode keys for the terminal's negotiated cursor and enhanced keyboard modes.
enum FloatingTerminalKey: Int, CaseIterable {
    case escape, tab, control, shift, left, down, up, right
    case home, end, pageUp, pageDown, alt, newline, interrupt
    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12
    static let functionKeys: [Self] = [.f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12]
    static let primary: [Self] = [.escape, .tab, .control, .shift, .left, .down, .up, .right]
    var label: String {
        ["Escape", "Tab", "Control", "Shift", "Left arrow", "Down arrow", "Up arrow", "Right arrow",
         "Home", "End", "Page Up", "Page Down", "Alt / Meta", "New line (Ctrl+J)", "Ctrl+C",
         "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12"][rawValue]
    }
    var title: String { self == .escape ? "esc" : self == .control ? "ctrl" : label }
    var symbol: String? {
        switch self {
        case .tab: return "arrow.right.to.line"
        case .shift: return "shift"
        case .left: return "arrow.left"
        case .down: return "arrow.down"
        case .up: return "arrow.up"
        case .right: return "arrow.right"
        default: return nil
        }
    }
    var modifier: FloatingModifiers? {
        switch self { case .shift: return .shift; case .control: return .control; case .alt: return .alt; default: return nil }
    }
    var repeats: Bool { [.left, .down, .up, .right, .pageUp, .pageDown].contains(self) }
    func sequence(shifted: Bool, applicationCursor: Bool, flags: KittyKeyboardFlags = [], event: Int = 1) -> String {
        sequence(modifiers: shifted ? .shift : [], applicationCursor: applicationCursor, flags: flags, event: event)
    }
    func sequence(modifiers: FloatingModifiers, applicationCursor: Bool, flags: KittyKeyboardFlags = [], event: Int = 1) -> String {
        guard modifier == nil else { return "" }
        let reportsEvents = flags.contains(.reportEvents)
        if event == 3 && !reportsEvents { return "" }
        let suffix = reportsEvents && event != 1 ? ":\(event)" : ""
        let enhanced = flags.contains(.disambiguate) || flags.contains(.reportAllKeys)
        let mod = 1 + modifiers.rawValue
        let altPrefix = modifiers.contains(.alt) ? "\u{1b}" : ""
        if let index = Self.functionKeys.firstIndex(of: self) {
            // Kitty uses CSI 13~ for F3; legacy terminals use SS3 R.
            if index < 4 && !(self == .f3 && !flags.isEmpty) {
                let letter = ["P", "Q", "R", "S"][index]
                if modifiers.isEmpty && suffix.isEmpty && !enhanced { return "\u{1b}O" + letter }
                return "\u{1b}[1;\(mod)\(suffix)\(letter)"
            }
            let code = self == .f3 ? 13 : [15, 17, 18, 19, 20, 21, 23, 24][index - 4]
            return "\u{1b}[\(code)" + (modifiers.isEmpty && suffix.isEmpty ? "" : ";\(mod)\(suffix)") + "~"
        }
        switch self {
        case .escape:
            if enhanced { return "\u{1b}[27;\(mod)\(suffix)u" }
            return event == 3 ? "" : altPrefix + "\u{1b}"
        case .tab:
            if enhanced || modifiers.contains(.control) { return "\u{1b}[9;\(mod)\(suffix)u" }
            return event == 3 ? "" : altPrefix + (modifiers.contains(.shift) ? "\u{1b}[Z" : "\t")
        case .newline, .interrupt:
            let code = self == .newline ? 106 : 99
            if enhanced { return "\u{1b}[\(code);5\(suffix)u" }
            return event == 3 ? "" : (self == .newline ? "\n" : "\u{3}")
        case .pageUp, .pageDown:
            let code = self == .pageUp ? 5 : 6
            return "\u{1b}[\(code)" + (modifiers.isEmpty && suffix.isEmpty ? "" : ";\(mod)\(suffix)") + "~"
        default:
            let letter: String
            switch self {
            case .up: letter = "A"
            case .down: letter = "B"
            case .right: letter = "C"
            case .left: letter = "D"
            case .home: letter = "H"
            case .end: letter = "F"
            default: return ""
            }
            if !modifiers.isEmpty || !suffix.isEmpty { return "\u{1b}[1;\(mod)\(suffix)\(letter)" }
            return "\u{1b}" + (applicationCursor && flags.isEmpty ? "O" : "[") + letter
        }
    }
}

@MainActor final class FloatingKeyInput: ObservableObject {
    @Published private(set) var modifiers: FloatingModifiers = []
    var shifted: Bool { modifiers.contains(.shift) }
    var paste: (() -> Void)?
    var enabled = false { didSet { if !enabled { reset() } } }
    var emit: ((FloatingTerminalKey, FloatingModifiers, Int) -> Void)?
    private var held: FloatingModifiers = []
    private var used: FloatingModifiers = []
    private var armedBefore: FloatingModifiers = []
    private var pressed: (FloatingTerminalKey, FloatingModifiers)?
    private var repeating: Task<Void, Never>?

    func modifierDown(_ modifier: FloatingModifiers) {
        guard enabled else { return }
        if modifiers.contains(modifier) { armedBefore.insert(modifier) } else { armedBefore.remove(modifier) }
        held.insert(modifier); used.remove(modifier); modifiers.insert(modifier)
    }
    func modifierUp(_ modifier: FloatingModifiers, cancelled: Bool = false) {
        guard held.contains(modifier) else { return }
        held.remove(modifier)
        if cancelled || used.contains(modifier) || armedBefore.contains(modifier) { modifiers.remove(modifier) }
    }
    func shiftDown() { modifierDown(.shift) }
    func shiftUp(cancelled: Bool = false) { modifierUp(.shift, cancelled: cancelled) }
    func consumeModifiers() -> FloatingModifiers {
        let value = modifiers
        used.formUnion(held)
        modifiers.formIntersection(held)
        return value
    }
    func press(_ key: FloatingTerminalKey) {
        guard enabled, key.modifier == nil else { return }
        release()
        let modifiers = consumeModifiers()
        pressed = (key, modifiers)
        emit?(key, modifiers, 1)
        guard key.repeats else { return }
        repeating = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(400))
                while !Task.isCancelled {
                    guard let self, self.enabled, let (key, modifiers) = self.pressed else { return }
                    self.emit?(key, modifiers, 2)
                    try await Task.sleep(for: .milliseconds(75))
                }
            } catch { }
        }
    }
    func release() {
        repeating?.cancel(); repeating = nil
        if let (key, modifiers) = pressed { emit?(key, modifiers, 3) }
        pressed = nil
    }
    func reset() { release(); held = []; used = []; armedBefore = []; modifiers = [] }
    func pasteFromClipboard() { guard enabled else { return }; reset(); paste?() }
}

/// A small native overlay. Only its handle owns the drag gesture.
@MainActor final class FloatingKeyPalette: UIView {
    static let paletteSize = CGSize(width: 204, height: 148)
    private let input: FloatingKeyInput
    private let preferences: UserDefaults
    private var buttons: [FloatingTerminalKey: UIButton] = [:]
    private var observations: Set<AnyCancellable> = []
    var showSidebar: (() -> Void)?
    var toggleKeyboard: (() -> Void)?
    private let keyboardButton = UIButton(type: .system)
    private let moreButton = UIButton(type: .system)
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
        let handle = UIView(frame: CGRect(x: 8, y: 0, width: 44, height: 44))
        handle.accessibilityLabel = "Move floating keys"; handle.isAccessibilityElement = true
        handle.accessibilityHint = "Drag to move the controls."
        handle.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Move to left edge", actionHandler: { [weak self] _ in self?.moveToEdge(x: 0); return true }),
            UIAccessibilityCustomAction(name: "Move to right edge", actionHandler: { [weak self] _ in self?.moveToEdge(x: 1); return true })
        ]
        handle.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(drag(_:))))
        let grip = UIView(frame: CGRect(x: 12, y: 20, width: 20, height: 4))
        grip.backgroundColor = .tertiaryLabel; grip.layer.cornerRadius = 2; grip.isUserInteractionEnabled = false
        handle.addSubview(grip); material.contentView.addSubview(handle)
        for (index, key) in FloatingTerminalKey.primary.enumerated() {
            let button = UIButton(type: .system)
            var config = UIButton.Configuration.plain()
            if let symbol = key.symbol { config.image = UIImage(systemName: symbol) } else { config.title = key.title }
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
            button.frame = CGRect(x: 8 + (index % 4) * 48, y: 48 + (index / 4) * 48, width: 44, height: 44)
            button.isExclusiveTouch = false
            button.addTarget(self, action: #selector(keyDown(_:)), for: .touchDown)
            button.addTarget(self, action: #selector(keyUp(_:)), for: [.touchUpInside, .touchUpOutside])
            button.addTarget(self, action: #selector(keyCancel(_:)), for: [.touchCancel, .touchDragExit])
            button.addTarget(self, action: #selector(accessiblePress(_:)), for: .primaryActionTriggered)
            material.contentView.addSubview(button); buttons[key] = button
        }
        let sidebarButton = UIButton(type: .system)
        sidebarButton.frame = CGRect(x: 56, y: 0, width: 44, height: 44)
        sidebarButton.setImage(UIImage(systemName: "sidebar.left"), for: .normal)
        sidebarButton.accessibilityLabel = "Hosts and sessions"
        sidebarButton.accessibilityIdentifier = "terminal.sessions"
        sidebarButton.addAction(UIAction { [weak self] _ in
            self?.input.reset(); self?.showSidebar?()
        }, for: .primaryActionTriggered)
        material.contentView.addSubview(sidebarButton)
        keyboardButton.frame = CGRect(x: 104, y: 0, width: 44, height: 44)
        keyboardButton.accessibilityIdentifier = "terminal.keyboard.toggle"
        keyboardButton.addAction(UIAction { [weak self] _ in
            self?.input.reset(); self?.toggleKeyboard?()
        }, for: .primaryActionTriggered)
        setKeyboardVisible(false)
        material.contentView.addSubview(keyboardButton)
        moreButton.frame = CGRect(x: 152, y: 0, width: 44, height: 44)
        moreButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        moreButton.accessibilityLabel = "More terminal keys"
        moreButton.accessibilityIdentifier = "terminal.key.more"
        moreButton.showsMenuAsPrimaryAction = true
        material.contentView.addSubview(moreButton)
        input.$modifiers.sink { [weak self] modifiers in
            for key: FloatingTerminalKey in [.shift, .control] {
                let active = modifiers.contains(key.modifier!)
                let button = self?.buttons[key]
                button?.configuration?.baseForegroundColor = active ? .white : .label
                button?.configuration?.background.backgroundColor = active ? .systemBlue : .secondarySystemFill
                button?.accessibilityValue = active ? "On" : "Off"
            }
            self?.updateMenu(modifiers: modifiers)
        }.store(in: &observations)
    }
    func setKeyboardVisible(_ visible: Bool) {
        keyboardButton.setImage(UIImage(systemName: visible ? "keyboard.chevron.compact.down" : "keyboard"), for: .normal)
        keyboardButton.accessibilityLabel = visible ? "Hide keyboard" : "Show keyboard"
    }
    private func updateMenu(modifiers: FloatingModifiers) {
        let keys: [FloatingTerminalKey] = [.home, .end, .pageUp, .pageDown, .alt, .newline, .interrupt]
        var actions: [UIMenuElement] = keys.map { key in
            UIAction(title: key.label, state: key == .alt && modifiers.contains(.alt) ? .on : .off) { [weak input] _ in
                guard let input else { return }
                if let modifier = key.modifier { input.modifierDown(modifier); input.modifierUp(modifier) }
                else { input.press(key); input.release() }
            }
        }
        actions.append(UIAction(title: "Paste", image: UIImage(systemName: "doc.on.clipboard")) { [weak input] _ in input?.pasteFromClipboard() })
        let functionKeys = FloatingTerminalKey.functionKeys.map { key in
            UIAction(title: key.label) { [weak input] _ in input?.press(key); input?.release() }
        }
        moreButton.menu = UIMenu(children: actions + [UIMenu(title: "F1–F12", children: functionKeys)])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    @objc private func keyDown(_ button: UIButton) {
        guard let key = FloatingTerminalKey(rawValue: button.tag) else { return }
        if let modifier = key.modifier { input.modifierDown(modifier) } else { input.press(key) }
    }
    @objc private func keyUp(_ button: UIButton) {
        if let modifier = FloatingTerminalKey(rawValue: button.tag)?.modifier { input.modifierUp(modifier) } else { input.release() }
    }
    @objc private func keyCancel(_ button: UIButton) {
        if let modifier = FloatingTerminalKey(rawValue: button.tag)?.modifier { input.modifierUp(modifier, cancelled: true) } else { input.release() }
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
