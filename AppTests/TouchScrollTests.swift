import XCTest
import SwiftTerm
@testable import TermAnywhere

@MainActor final class TouchScrollTests: XCTestCase {
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
