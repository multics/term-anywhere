import XCTest
import SwiftTerm
@testable import TermAnywhere

@MainActor final class TouchScrollTests: XCTestCase {
    /// Opt-in computer-use check. No host, credentials, or saved configuration is involved.
    func testInteractiveTapKeepsKeyboardHidden() async throws {
        let marker = URL.documentsDirectory.appendingPathComponent("touch-gesture-check")
        guard FileManager.default.fileExists(atPath: marker.path) else { throw XCTSkip("No interactive gesture check requested.") }
        try FileManager.default.removeItem(at: marker)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene), controller = UIViewController()
        controller.view.backgroundColor = .systemBackground
        let instruction = UILabel(); instruction.text = "1. Tap the terminal"; instruction.textAlignment = .center
        let view = SafeTerminalView(frame: .zero), recorder = ScrollRecorder()
        view.terminalDelegate = recorder
        for child in [instruction, view] { child.translatesAutoresizingMaskIntoConstraints = false; controller.view.addSubview(child) }
        NSLayoutConstraint.activate([
            instruction.topAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.topAnchor),
            instruction.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
            instruction.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor), instruction.heightAnchor.constraint(equalToConstant: 44),
            view.topAnchor.constraint(equalTo: instruction.bottomAnchor), view.bottomAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor), view.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor)
        ])
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .milliseconds(300))
        view.feed(text: "\u{1b}[?1000h\u{1b}[?1006hTap anywhere below this line.\r\nThe keyboard must stay hidden.\r\n")
        try await waitForGesture { recorder.text.contains("M") && recorder.text.contains("m") }
        XCTAssertTrue(recorder.text.hasPrefix("\u{1b}[<0;")); XCTAssertFalse(view.isFirstResponder)
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = "Actual tap with keyboard hidden"; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func waitForGesture(_ ready: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(45)
        while !ready(), Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertTrue(ready(), "The expected interactive gesture did not arrive")
    }
    func testTwoFingerDragSendsPressMotionReleaseWithoutWheelOrKeyboard() {
        let view = SafeTerminalView(frame: CGRect(x: 0, y: 0, width: 390, height: 300))
        let recorder = ScrollRecorder(); view.terminalDelegate = recorder
        view.feed(text: "\u{1b}[?1002h\u{1b}[?1006h")
        let gesture = view.gestureRecognizers?.first { $0.name == "terminal.mouse.drag" } as? UIPanGestureRecognizer
        XCTAssertEqual(gesture?.minimumNumberOfTouches, 2)
        XCTAssertEqual(gesture?.maximumNumberOfTouches, 2)
        let size = view.getOptimalFrameSize(), terminal = view.getTerminal()
        let cell = CGSize(width: size.width / CGFloat(terminal.cols), height: size.height / CGFloat(terminal.rows))
        view.beginMouseDrag(at: CGPoint(x: cell.width * 5, y: cell.height * 3))
        view.scrollTouch(lines: 3, at: .zero)
        view.moveMouseDrag(to: CGPoint(x: cell.width * 9, y: cell.height * 3))
        view.moveMouseDrag(to: CGPoint(x: cell.width * 9, y: cell.height * 7))
        view.endMouseDrag(); view.endMouseDrag()
        XCTAssertEqual(recorder.text, "\u{1b}[<0;6;4M\u{1b}[<32;10;4M\u{1b}[<32;10;8M\u{1b}[<0;10;8m")
        XCTAssertFalse(view.isFirstResponder)
        recorder.bytes = []
        view.scrollTouch(lines: 1, at: .zero)
        XCTAssertEqual(recorder.text, "\u{1b}[<64;1;1M")
    }
    @MainActor func testRemovingTerminalReleasesActiveMouseDrag() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIViewController(); window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        let view = SafeTerminalView(frame: CGRect(x: 0, y: 0, width: 390, height: 300))
        window.rootViewController?.view.addSubview(view)
        let recorder = ScrollRecorder(); view.terminalDelegate = recorder
        view.feed(text: "\u{1b}[?1002h\u{1b}[?1006h")
        view.beginMouseDrag(at: .zero)
        view.removeFromSuperview()
        view.endMouseDrag()
        XCTAssertEqual(recorder.text, "\u{1b}[<0;1;1M\u{1b}[<0;1;1m")
    }
    func testDragRequiresMotionModeAndSuppressesSelectionInput() {
        let view = SafeTerminalView(frame: CGRect(x: 0, y: 0, width: 390, height: 300))
        let recorder = ScrollRecorder(); view.terminalDelegate = recorder
        for sequence in ["", "\u{1b}[?9h", "\u{1b}[?9l\u{1b}[?1000h"] {
            view.feed(text: sequence)
            XCTAssertFalse(view.canDragMouse)
            view.beginMouseDrag(at: .zero); view.moveMouseDrag(to: CGPoint(x: 50, y: 50)); view.endMouseDrag()
        }
        XCTAssertTrue(recorder.bytes.isEmpty)
        view.feed(text: "\u{1b}[?1000l\u{1b}[?1003h\u{1b}[?1006hSELECT ME")
        view.beginMouseDrag(at: .zero)
        view.selectAll(nil)
        XCTAssertEqual(recorder.text, "\u{1b}[<0;1;1M\u{1b}[<0;1;1m")
        recorder.bytes = []
        view.beginMouseDrag(at: .zero); view.moveMouseDrag(to: .zero); view.endMouseDrag()
        XCTAssertTrue(recorder.bytes.isEmpty)
    }
    func testCancelledDragClampsCoordinatesAndDoesNotReplayAfterModeChange() {
        let view = SafeTerminalView(frame: CGRect(x: 0, y: 0, width: 390, height: 300))
        let recorder = ScrollRecorder(); view.terminalDelegate = recorder
        view.feed(text: "\u{1b}[?1002h\u{1b}[?1006h")
        view.beginMouseDrag(at: CGPoint(x: -10, y: -10))
        view.moveMouseDrag(to: CGPoint(x: 9999, y: 9999)); view.endMouseDrag()
        let terminal = view.getTerminal()
        XCTAssertEqual(recorder.text, "\u{1b}[<0;1;1M\u{1b}[<32;\(terminal.cols);\(terminal.rows)M\u{1b}[<0;\(terminal.cols);\(terminal.rows)m")
        view.beginMouseDrag(at: .zero)
        view.feed(text: "\u{1b}[?1002l")
        recorder.bytes = []
        view.feed(text: "\u{1b}[?1002h")
        view.moveMouseDrag(to: .zero); view.endMouseDrag()
        XCTAssertTrue(recorder.bytes.isEmpty)
        view.beginMouseDrag(at: .zero); view.endMouseDrag(sendRelease: false)
        recorder.bytes = []
        view.moveMouseDrag(to: .zero); view.endMouseDrag()
        XCTAssertTrue(recorder.bytes.isEmpty)
    }
    func testTapHonorsMouseModeAndWorksWithoutKeyboardFocus() {
        let view = SafeTerminalView(frame: CGRect(x: 0, y: 0, width: 390, height: 300))
        let recorder = ScrollRecorder(); view.terminalDelegate = recorder
        view.tapTouch(at: .zero)
        XCTAssertTrue(recorder.bytes.isEmpty)
        view.feed(text: "\u{1b}[?1000h\u{1b}[?1006h")
        XCTAssertTrue(view.allowMouseReporting)
        view.tapTouch(at: .zero)
        XCTAssertEqual(recorder.text, "\u{1b}[<0;1;1M\u{1b}[<0;1;1m")
        XCTAssertFalse(view.isFirstResponder)
        recorder.bytes = []
        view.feed(text: "\u{1b}[?1000l")
        view.tapTouch(at: .zero)
        XCTAssertTrue(recorder.bytes.isEmpty)
    }
    func testLocalSelectionSuppressesClicksAndSurvivesOutput() {
        let view = SafeTerminalView(frame: CGRect(x: 0, y: 0, width: 390, height: 300))
        let recorder = ScrollRecorder(); view.terminalDelegate = recorder
        view.feed(text: "\u{1b}[?1000h\u{1b}[?1006hSelect this text")
        view.selectAll(nil)
        XCTAssertTrue(view.selection.active); XCTAssertFalse(view.allowMouseReporting)
        view.tapTouch(at: .zero); view.scrollTouch(lines: 3, at: .zero)
        view.feed(text: "\r\nMore output")
        XCTAssertTrue(view.selection.active); XCTAssertTrue(recorder.bytes.isEmpty)
        view.selection.selectNone()
        XCTAssertTrue(view.allowMouseReporting)
        view.tapTouch(at: .zero)
        XCTAssertFalse(recorder.bytes.isEmpty)
    }
    func testTapCoordinatesAndX10PressOnlyEncoding() {
        let view = SafeTerminalView(frame: CGRect(x: 0, y: 0, width: 390, height: 300))
        let recorder = ScrollRecorder(); view.terminalDelegate = recorder
        view.feed(text: "\u{1b}[?9h")
        view.tapTouch(at: .zero)
        XCTAssertEqual(recorder.bytes, [27, 91, 77, 32, 33, 33])
        recorder.bytes = []
        view.feed(text: "\u{1b}[?9l\u{1b}[?1000h\u{1b}[?1006h")
        let size = view.getOptimalFrameSize(), terminal = view.getTerminal()
        view.tapTouch(at: CGPoint(x: size.width - 1, y: size.height - 1))
        XCTAssertEqual(recorder.text, "\u{1b}[<0;\(terminal.cols);\(terminal.rows)M\u{1b}[<0;\(terminal.cols);\(terminal.rows)m")
    }
    func testNormalShellScrollDoesNotSendCommandHistoryKeys() {
        let view = SafeTerminalView(frame: CGRect(x: 0, y: 0, width: 390, height: 300))
        let recorder = ScrollRecorder(); view.terminalDelegate = recorder
        view.feed(text: (0..<100).map { "LINE \($0)\r\n" }.joined())
        XCTAssertEqual(view.scrollRoute, .local)
        view.scrollTouch(lines: 5, at: CGPoint(x: 20, y: 20))
        XCTAssertTrue(recorder.bytes.isEmpty)
        XCTAssertGreaterThan(view.contentSize.height, view.bounds.height)
        view.setContentOffset(.zero, animated: false)
        XCTAssertEqual(view.contentOffset.y, 0)
    }
    func testMouseWheelUsesNegotiatedSGRCoordinatesWithoutClickEvents() {
        let view = SafeTerminalView(frame: CGRect(x: 0, y: 0, width: 390, height: 300))
        let recorder = ScrollRecorder(); view.terminalDelegate = recorder
        view.feed(text: "\u{1b}[?1000h\u{1b}[?1006h")
        XCTAssertEqual(view.scrollRoute, .mouse)
        view.scrollTouch(lines: 2, at: .zero)
        XCTAssertEqual(recorder.text, "\u{1b}[<64;1;1M\u{1b}[<64;1;1M")
        recorder.bytes = []
        view.scrollTouch(lines: -1, at: .zero)
        XCTAssertEqual(recorder.text, "\u{1b}[<65;1;1M")
        view.feed(text: "\u{1b}[?1000l")
        XCTAssertEqual(view.scrollRoute, .local)
    }
    func testAlternateScreenRespectsCursorAndAlternateScrollModes() {
        let view = SafeTerminalView(frame: CGRect(x: 0, y: 0, width: 390, height: 300))
        let recorder = ScrollRecorder(); view.terminalDelegate = recorder
        view.feed(text: "\u{1b}[?1049h\u{1b}[?1h")
        XCTAssertEqual(view.scrollRoute, .alternate)
        view.scrollTouch(lines: 2, at: .zero)
        XCTAssertEqual(recorder.text, "\u{1b}OA\u{1b}OA")
        recorder.bytes = []
        view.feed(text: "\u{1b}[?1l")
        view.scrollTouch(lines: -1, at: .zero)
        XCTAssertEqual(recorder.text, "\u{1b}[B")
        view.feed(text: "\u{1b}[?1007l")
        XCTAssertEqual(view.scrollRoute, .local)
    }
    func testTmuxHistoryAndSelectionTakePrecedenceOverCursorFallback() {
        let view = SafeTerminalView(frame: CGRect(x: 0, y: 0, width: 390, height: 300))
        let recorder = ScrollRecorder(); view.terminalDelegate = recorder
        var scrolls: [Int] = []
        view.tmuxScrollHandler = { scrolls.append($0) }
        XCTAssertEqual(view.scrollRoute, .tmux, "tmux can disable its outer alternate buffer")
        view.feed(text: "\u{1b}[?1049hTEXT FOR SELECTION")
        XCTAssertEqual(view.scrollRoute, .tmux)
        view.scrollTouch(lines: 4, at: .zero)
        XCTAssertEqual(scrolls, [4]); XCTAssertTrue(recorder.bytes.isEmpty)
        view.selectAll(nil)
        XCTAssertEqual(view.scrollRoute, .selection)
        view.scrollTouch(lines: 3, at: .zero)
        XCTAssertEqual(scrolls, [4]); XCTAssertTrue(recorder.bytes.isEmpty)
    }
}

private final class ScrollRecorder: NSObject, TerminalViewDelegate {
    var bytes: [UInt8] = []
    var text: String { String(decoding: bytes, as: UTF8.self) }
    func send(source: TerminalView, data: ArraySlice<UInt8>) { bytes.append(contentsOf: data) }
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func scrolled(source: TerminalView, position: Double) {}
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
    func bell(source: TerminalView) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}
