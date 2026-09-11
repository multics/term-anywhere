import XCTest
@testable import TermCore

final class HostDuplicationTests: XCTestCase {
    func testDuplicateKeepsCredentialsButHasIndependentIdentityAndSession() throws {
        let original = TermCore.Host(name: "Server", address: "i-0123456789abcdef0", port: 2222, username: "user", keyID: "key", tmuxSession: "work", tmuxSocket: "/tmp/socket", awsProfile: "profile", region: "us-west-2", manualPrefix: "C-a")
        var copy = original.duplicate()
        XCTAssertNotEqual(copy.id, original.id)
        XCTAssertEqual(copy.name, "Server Copy")
        XCTAssertEqual(copy.keyID, original.keyID); XCTAssertEqual(copy.awsProfile, original.awsProfile)
        XCTAssertEqual(copy.trustID, original.trustID)
        XCTAssertEqual(copy.tmuxSocket, original.tmuxSocket); XCTAssertEqual(copy.manualPrefix, original.manualPrefix)
        XCTAssertTrue(copy.tmuxSession.isEmpty)
        copy.tmuxSession = "other"
        var state = SyncedConfiguration(); try state.save(original); try state.save(copy)
        XCTAssertEqual(state.sortedHosts.count, 2)
        XCTAssertEqual(original.tmuxSession, "work")
        XCTAssertEqual(copy.sessionLabel, "tmux · other")
    }
}
