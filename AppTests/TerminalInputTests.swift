import XCTest
import SwiftTerm
import TermCore
@testable import TermAnywhere

@MainActor final class TerminalInputTests: XCTestCase {
    func testChineseCompositionSendsOnlyCommittedText() {
        let terminal = SafeTerminalView(frame: CGRect(x: 0, y: 0, width: 393, height: 500))
        let output = InputRecorder(); terminal.terminalDelegate = output
        terminal.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0))
        XCTAssertTrue(output.data.isEmpty, "Pinyin composition must not reach the server")
        terminal.insertText("你")
        XCTAssertEqual(String(decoding: output.data, as: UTF8.self), "你")
    }
    func testControlModifierIsOneShot() {
        let terminal = SafeTerminalView(frame: CGRect(x: 0, y: 0, width: 393, height: 500))
        let output = InputRecorder(); terminal.terminalDelegate = output
        // The app replaces SwiftTerm's default accessory with its fixed native row.
        terminal.inputAccessoryView = UIInputView(frame: .zero, inputViewStyle: .keyboard)
        terminal.controlModifier = true; terminal.insertText("c"); terminal.insertText("x")
        XCTAssertEqual(output.data, Data([3, 120]))
        XCTAssertFalse(terminal.controlModifier)
    }
    func testKeychainWorksInsideSignedSimulatorApp() throws {
        let vault = KeychainStore(service: "me.tianyong.term-anywhere.ios-tests." + UUID().uuidString)
        defer { try? vault.delete(account: "key:fixture") }
        try vault.save(Data("synthetic-test-only".utf8), account: "key:fixture")
        XCTAssertEqual(try vault.read(account: "key:fixture"), Data("synthetic-test-only".utf8))
    }
    func testApplicationCursorAndTerminalSize() {
        let terminal = SafeTerminalView(frame: CGRect(x: 0, y: 0, width: 393, height: 500))
        terminal.feed(text: "\u{1b}[?1h")
        XCTAssertTrue(terminal.getTerminal().applicationCursor)
        terminal.feed(text: "\u{1b}[?1l")
        XCTAssertFalse(terminal.getTerminal().applicationCursor)
        XCTAssertGreaterThan(terminal.getTerminal().cols, 20)
    }
}
@MainActor private final class InputRecorder: @preconcurrency TerminalViewDelegate {
    var data = Data()
    func send(source: TerminalView, data: ArraySlice<UInt8>) { self.data.append(contentsOf: data) }
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func scrolled(source: TerminalView, position: Double) {}
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
    func bell(source: TerminalView) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}
