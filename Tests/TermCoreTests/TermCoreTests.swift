import XCTest
@testable import TermCore

final class TermCoreTests: XCTestCase {
    func testCustomPrefixAndSplitBinding() {
        let listing = """
        bind-key -T prefix v split-window -h -c "#{pane_current_path}"
        bind-key -T prefix z resize-pane -Z
        bind-key -T prefix c new-window
        bind-key -T prefix x confirm-before "kill-pane"
        """
        let bindings = TmuxBindings(prefix: "C-a\n", listing: listing)
        XCTAssertEqual(bindings.shortcuts.first(where: { $0.title == "Split side by side" })?.bytes, Data([1, 118]))
        XCTAssertEqual(bindings.shortcuts.count, 3)
    }
    func testAmbiguousAndScriptBindingsAreNotMapped() {
        let bindings = TmuxBindings(prefix: "C-b", listing: """
        bind-key -T prefix v split-window -h
        bind-key -T prefix | split-window -h
        bind-key -T prefix c new-window \\; run-shell bad
        bind-key -T prefix z if-shell test 'resize-pane -Z' ''
        bind-key -T custom n next-window
        """)
        XCTAssertTrue(bindings.shortcuts.isEmpty)
    }
    func testRootBindingDoesNotSendPrefix() {
        let b = TmuxBindings(prefix: "None", listing: "bind-key -T root M-n next-window")
        XCTAssertEqual(b.shortcuts.first?.bytes, Data([27, 110]))
        XCTAssertNil(TmuxBindings.keyBytes("None")); XCTAssertNil(TmuxBindings.keyBytes("Up"))
        XCTAssertEqual(TmuxBindings.keyBytes("C-["), Data([27]))
    }
    func testConnectionMappingsAreIndependent() {
        let a = TmuxBindings(prefix: "C-a", listing: "bind-key -T prefix v split-window -h")
        let b = TmuxBindings(prefix: "C-b", listing: "bind-key -T prefix | split-window -h")
        XCTAssertEqual(a.shortcuts[0].bytes, Data([1, 118]))
        XCTAssertEqual(b.shortcuts[0].bytes, Data([2, 124]))
        XCTAssertTrue(TmuxBindings(prefix: "C-b", listing: "").shortcuts.isEmpty)
    }
    func testSSMUUIDWireOrderAndHeader() throws {
        let id = UUID(uuidString: "00112233-4455-6677-8899-aabbccddeeff")!
        let message = SSMMessage(type: "input_stream_data", sequence: 42, payloadType: 1, payload: Data("SSH-2.0-test\r\n".utf8), id: id)
        let bytes = message.encode()
        XCTAssertEqual(Array(bytes.prefix(4)), [0, 0, 0, 116])
        XCTAssertEqual(Array(bytes[64..<80]), [0x88,0x99,0xaa,0xbb,0xcc,0xdd,0xee,0xff,0,0x11,0x22,0x33,0x44,0x55,0x66,0x77])
        XCTAssertEqual(Array(bytes[112..<116]), [0, 0, 0, 1])
        let decoded = try SSMMessage(decode: bytes)
        XCTAssertEqual(decoded.id, id); XCTAssertEqual(decoded.sequence, 42); XCTAssertEqual(decoded.payload, message.payload)
    }
    func testSSMRejectsTruncationCorruptionAndOversizedLength() throws {
        let message = SSMMessage(type: "output_stream_data", payloadType: 1, payload: Data([1,2,3]))
        let bytes = message.encode()
        for length in 0..<bytes.count { XCTAssertThrowsError(try SSMMessage(decode: Data(bytes.prefix(length)))) }
        var corrupt = bytes; corrupt[120] ^= 1; XCTAssertThrowsError(try SSMMessage(decode: corrupt))
        corrupt = bytes; corrupt[116] = 255; XCTAssertThrowsError(try SSMMessage(decode: corrupt))
        corrupt = bytes; corrupt[39] = 2; XCTAssertThrowsError(try SSMMessage(decode: corrupt))
    }
    func testAWSOfficialVanillaSigningVector() {
        // boto/botocore tests/unit/auth/aws4_testsuite/get-vanilla (Apache-2.0).
        let date = ISO8601DateFormatter().date(from: "2015-08-30T12:36:00Z")!
        let credentials = AWSCredentials(accessKeyID: "AKIDEXAMPLE", secretAccessKey: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY")
        let signed = AWSSigning.sign(URLRequest(url: URL(string: "https://example.amazonaws.com/")!), credentials: credentials, region: "us-east-1", service: "service", date: date)
        XCTAssertEqual(signed.value(forHTTPHeaderField: "Authorization"), "AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20150830/us-east-1/service/aws4_request, SignedHeaders=host;x-amz-date, Signature=5fa00fa31553b73ebf1942676e86291e8372ff2a2260956d9b8aae1d763fbf31")
    }
    func testTmuxNamesCannotBecomeShellCommands() throws {
        var host = Host(name: "test", address: "example.com", username: "user", keyID: "key")
        host.tmuxSession = "mobile; touch bad"; XCTAssertThrowsError(try host.validate())
        host.tmuxSession = "mobile-one"; XCTAssertNoThrow(try host.validate())
        XCTAssertEqual(shellQuote("a'b"), "'a'\\''b'")
    }
    func testNewAndDuplicatedHostsChooseSessionsIndependently() throws {
        var original = Host(name: "server", address: "example.invalid", username: "user", keyID: "shared-key")
        XCTAssertEqual(original.tmuxSession, ""); XCTAssertNil(original.tmuxSelectionMade)
        original.tmuxSession = "work"; original.tmuxSelectionMade = true; original.awsProfile = "shared-profile"
        let copy = original.duplicate()
        XCTAssertNotEqual(copy.id, original.id); XCTAssertEqual(copy.address, original.address)
        XCTAssertEqual(copy.keyID, original.keyID); XCTAssertEqual(copy.awsProfile, original.awsProfile)
        XCTAssertTrue(copy.tmuxSession.isEmpty); XCTAssertNil(copy.tmuxSelectionMade)
        XCTAssertEqual(original.sessionLabel, "tmux · work")
        original.tmuxSession = ""
        XCTAssertEqual(original.sessionLabel, "Plain shell")
        XCTAssertEqual(try JSONDecoder().decode(Host.self, from: JSONEncoder().encode(original)).tmuxSelectionMade, true)
    }
    func testTmuxSessionDiscoveryDistinguishesUnavailableAndEmptyServers() throws {
        let sessions = try TmuxSessionList(output: "TERM_ANYWHERE_TMUX_AVAILABLE\nwork\nother\nwork\n")
        XCTAssertTrue(sessions.isAvailable); XCTAssertEqual(sessions.names, ["other", "work"])
        XCTAssertTrue(try TmuxSessionList(output: "TERM_ANYWHERE_TMUX_AVAILABLE\n").isAvailable)
        XCTAssertFalse(try TmuxSessionList(output: "TERM_ANYWHERE_TMUX_UNAVAILABLE\n").isAvailable)
        XCTAssertThrowsError(try TmuxSessionList(output: "unexpected banner"))
    }
    func testKeychainRoundTripAndDelete() throws {
        let vault = KeychainStore(service: "me.tianyong.term-anywhere.tests." + UUID().uuidString)
        defer { try? vault.delete(account: "key:test") }
        try vault.save(Data([1,2,3]), account: "key:test")
        XCTAssertEqual(try vault.read(account: "key:test"), Data([1,2,3]))
        try vault.save(Data([4,5]), account: "key:test")
        XCTAssertEqual(try vault.accounts(prefix: "key:"), ["test"])
        XCTAssertEqual(try vault.read(account: "key:test"), Data([4,5]))
        try vault.delete(account: "key:test")
        XCTAssertNil(try vault.read(account: "key:test"))
    }
}
