import XCTest
@testable import TermCore

final class TmuxScrollTests: XCTestCase {
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
