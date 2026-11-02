import XCTest
@testable import TermCore

final class TmuxScrollTests: XCTestCase {
    func testFittingTargetsOnlySelectedWindowsAndPreservesInheritedHooks() throws {
        let inherited = "session-window-changed[3] display-message hello\nafter-new-window[0] display-message other"
        let command = try TmuxSizing.command(tmux: "tmux -S '/tmp/socket'", sessionID: "$2", windows: "@3\n@4", localHooks: "", inheritedHooks: inherited)
        XCTAssertTrue(command.contains("set-hook -t '$2' 'session-window-changed[3]' 'display-message hello'"))
        XCTAssertFalse(command.contains("display-message other"))
        XCTAssertTrue(command.contains("set-hook -a -t '$2' session-window-changed"))
        XCTAssertTrue(command.contains("set-option -w -t '@3' window-size latest"))
        XCTAssertTrue(command.contains("set-option -w -t '@4' window-size latest"))
        XCTAssertFalse(command.contains(" -g"))
    }
    func testFittingPreservesLocalHooksAndIsIdempotent() throws {
        let existing = "session-window-changed[0] display-message local"
        let first = try TmuxSizing.command(tmux: "tmux", sessionID: "$2", windows: "@3", localHooks: existing, inheritedHooks: "session-window-changed[2] display-message global")
        XCTAssertFalse(first.contains("display-message global"))
        XCTAssertFalse(first.contains("display-message local"), "Append without replacing existing local actions")
        let installed = existing + "\nsession-window-changed[1] " + TmuxSizing.fitHook
        let next = try TmuxSizing.command(tmux: "tmux", sessionID: "$2", windows: "@3", localHooks: installed, inheritedHooks: "")
        XCTAssertEqual(next, "tmux set-option -w -t '@3' window-size latest")
    }
    func testFittingRejectsMalformedTargets() {
        XCTAssertThrowsError(try TmuxSizing.command(tmux: "tmux", sessionID: "bad", windows: "@3", localHooks: "", inheritedHooks: ""))
        XCTAssertThrowsError(try TmuxSizing.command(tmux: "tmux", sessionID: "$2", windows: "@3; other", localHooks: "", inheritedHooks: ""))
    }
    func testOldSmallestHooksAreMigratedInPlaceWithoutTouchingOtherEntries() throws {
        let hooks = "session-window-changed[0] display-message keep\n" +
            "session-window-changed[3] \(TmuxSizing.previousFitHook)\n" +
            "session-window-changed[7] \(TmuxSizing.previousFitHook)"
        let command = try TmuxSizing.command(tmux: "tmux", sessionID: "$2", windows: "@3", localHooks: hooks, inheritedHooks: "")
        XCTAssertTrue(command.contains("set-hook -t '$2' 'session-window-changed[3]' 'set-option -w window-size latest'"))
        XCTAssertTrue(command.contains("set-hook -t '$2' 'session-window-changed[7]' 'set-option -w window-size latest'"))
        XCTAssertFalse(command.contains("session-window-changed[0]"))
        XCTAssertFalse(command.contains("set-hook -a"))
        XCTAssertFalse(command.contains("smallest"))
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
