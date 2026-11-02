import XCTest
@testable import TermCore

final class TmuxScrollTests: XCTestCase {
    func testClientIdentitySurvivesEverySSHReadBoundaryWithoutLeakingIntoTerminal() {
        let marker = "\u{1b}]777;term-anywhere-test;/dev/pts/42\u{7}"
        let data = Data(("banner\r\n" + marker + "\u{1b}[31moutput").utf8)
        for split in 0...data.count {
            var handshake = TmuxClientHandshake(token: "test")
            let rendered = handshake.consume(data.prefix(split)) + handshake.consume(data.dropFirst(split))
            XCTAssertEqual(String(decoding: rendered, as: UTF8.self), "banner\r\n\u{1b}[31moutput")
            XCTAssertEqual(handshake.tty, "/dev/pts/42")
            XCTAssertTrue(handshake.complete)
            XCTAssertEqual(handshake.consume(Data("next".utf8)), Data("next".utf8))
        }
        var bytewise = TmuxClientHandshake(token: "test")
        let rendered = data.reduce(into: Data()) { $0.append(bytewise.consume(Data([$1]))) }
        XCTAssertEqual(bytewise.tty, "/dev/pts/42")
        XCTAssertEqual(String(decoding: rendered, as: UTF8.self), "banner\r\n\u{1b}[31moutput")
    }
    func testViewportTargetsOnlyItsPTYAndRejectsInvalidIdentity() {
        var handshake = TmuxClientHandshake(token: "test")
        _ = handshake.consume(Data("\u{1b}]777;term-anywhere-test;not a tty\u{7}".utf8))
        XCTAssertNil(handshake.tty)
        XCTAssertEqual(TmuxViewport.command(tmux: "tmux -S '/tmp/socket'", tty: "/dev/ttys005", columns: 20),
                       "tmux -S '/tmp/socket' refresh-client -t '/dev/ttys005' -R 20")
        XCTAssertEqual(TmuxViewport.command(tmux: "tmux", tty: "/dev/pts/2", columns: Int.min),
                       "tmux refresh-client -t '/dev/pts/2' -L 240")
        XCTAssertEqual(TmuxViewport.command(tmux: "tmux", tty: "/dev/pts/2", columns: 0),
                       "tmux refresh-client -t '/dev/pts/2' -c")
    }
    func testShellHistoryUsesCopyModeInsteadOfArrowKeys() throws {
        let state = try TmuxScroll(state: "%3||0\n")
        let command = try XCTUnwrap(state.command(tmux: "tmux", lines: 4))
        XCTAssertTrue(command.contains("copy-mode -e -t '%3'"))
        XCTAssertTrue(command.contains("send-keys -X -t '%3' -N 4 scroll-up"))
        XCTAssertFalse(command.contains(" Up"))
        XCTAssertNil(try state.command(tmux: "tmux", lines: -4))
    }
    func testAlternateScreenAndExistingCopyModeHaveDifferentRoutes() throws {
        let app = try TmuxScroll(state: "%7||1")
        XCTAssertEqual(try app.command(tmux: "tmux", lines: -3), "tmux send-keys -t '%7' -N 3 Down")
        let history = try TmuxScroll(state: "%7|copy-mode|1")
        let command = try XCTUnwrap(history.command(tmux: "tmux", lines: -3))
        XCTAssertTrue(command.contains("scroll-down")); XCTAssertTrue(command.contains("scroll_position"))
        XCTAssertFalse(command.contains(" Down"))
    }
    func testInvalidTargetAndOtherTmuxModesDoNotReceiveInput() throws {
        XCTAssertThrowsError(try TmuxScroll(state: "%1;kill-server||0"))
        XCTAssertThrowsError(try TmuxScroll(state: "%1||unknown"))
        XCTAssertThrowsError(try TmuxScroll(state: "%1|tree-mode|0").command(tmux: "tmux", lines: 1))
        let bounded = try TmuxScroll(state: "%1||0").command(tmux: "tmux", lines: 999)
        XCTAssertTrue(bounded?.contains("-N 30") == true)
    }
}
