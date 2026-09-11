import XCTest
import SwiftUI
import TermCore
@testable import TermAnywhere

@MainActor final class SessionTabTests: XCTestCase {
    private func fixture() -> (AppStore, TerminalSession) {
        let store = AppStore(); store.configuration.onChange = nil
        var host = Host(name: "Tab fixture", address: "example.invalid", username: "fixture", keyID: "missing-fixture", tmuxSession: "dev")
        host.tmuxSelectionMade = true
        store.hosts = [host]; store.selectHost(host.id)
        let session = store.sessions[host.id]!
        session.hasStarted = true
        return (store, session)
    }
    func testTabsRetainIndependentBuffersAndReuseOpenSessions() throws {
        let (store, dev) = fixture(); defer { store.closeSession(dev.host.id) }
        dev.terminal.feed(text: "DEV OUTPUT\r\n")
        let logs = try store.openTab(from: dev, name: "logs")
        logs.hasStarted = true; logs.terminal.feed(text: "LOG OUTPUT\r\n")
        XCTAssertNotEqual(dev.id, logs.id)
        XCTAssertEqual(dev.host.id, logs.host.id)
        XCTAssertTrue(store.sessions[dev.host.id] === logs)
        XCTAssertTrue(try store.openTab(from: logs, name: "dev") === dev)
        XCTAssertEqual(store.tabs[dev.host.id]?.count, 2)
        XCTAssertTrue(buffer(dev).contains("DEV OUTPUT")); XCTAssertFalse(buffer(dev).contains("LOG OUTPUT"))
        XCTAssertTrue(buffer(logs).contains("LOG OUTPUT"))
        store.stepTab(for: dev.host.id, by: -1)
        XCTAssertTrue(store.sessions[dev.host.id] === logs)
        store.stepTab(for: dev.host.id, by: 1)
        XCTAssertTrue(store.sessions[dev.host.id] === dev)
    }
    func testCloseOneTabKeepsOthersAndLastCloseReturnsToHosts() throws {
        let (store, dev) = fixture()
        let logs = try store.openTab(from: dev, name: "logs"); logs.hasStarted = true
        let ops = try store.openTab(from: logs, name: "ops"); ops.hasStarted = true
        store.closeTab(logs)
        XCTAssertTrue(store.sessions[dev.host.id] === ops)
        store.closeTab(ops)
        XCTAssertTrue(store.sessions[dev.host.id] === dev)
        XCTAssertEqual(store.selectedHostID, dev.host.id)
        store.closeTab(dev)
        XCTAssertNil(store.selectedHostID); XCTAssertTrue(store.allSessions.isEmpty)
        XCTAssertTrue(store.sessions.isEmpty)
    }
    func testCancelOnlyClosesTheTabWaitingForSelection() async throws {
        let (store, dev) = fixture(); defer { store.closeSession(dev.host.id) }
        let logs = try store.openTab(from: dev, name: "logs"); logs.hasStarted = true
        let waiting = Task { try await logs.requestTmuxSelection() }
        await Task.yield()
        logs.cancelTmuxSelection()
        do { _ = try await waiting.value; XCTFail("Selection must be cancelled") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(store.sessions[dev.host.id] === dev)
        XCTAssertEqual(store.tabs[dev.host.id]?.count, 1)
    }
    func testInvalidNameDoesNotAddTabAndNewTabKeepsEndpointSnapshot() throws {
        let (store, dev) = fixture(); defer { store.closeSession(dev.host.id) }
        XCTAssertThrowsError(try store.openTab(from: dev, name: "bad;name", create: true))
        XCTAssertEqual(store.tabs[dev.host.id]?.count, 1)
        store.hosts[0].address = "edited.invalid"
        let created = try store.openTab(from: dev, name: "new", create: true)
        XCTAssertEqual(created.host.address, "example.invalid")
        XCTAssertTrue(created.createTmuxOnConnect)
        store.closeSession(dev.host.id)
        XCTAssertThrowsError(try store.openTab(from: dev, name: "after-close"))
    }
    func testSwitchingMountedTabsPreservesKeyboardPreferenceAndOutput() async throws {
        let (store, dev) = fixture()
        let logs = try store.openTab(from: dev, name: "logs"); logs.hasStarted = true
        store.selectTab(dev)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: NavigationStack {
            TerminalWorkspaceScreen(store: store, hostID: dev.host.id)
        })
        window.makeKeyAndVisible()
        defer { store.closeSession(dev.host.id); window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .milliseconds(400))
        dev.terminal.feed(text: "PRESERVED TAB OUTPUT\r\n")
        dev.showKeyboard()
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertTrue(dev.terminal.isFirstResponder)
        store.selectTab(logs)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertTrue(logs.terminal.isFirstResponder)
        XCTAssertFalse(dev.terminal.isFirstResponder)
        logs.hideKeyboard()
        store.selectTab(dev)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertFalse(dev.terminal.isFirstResponder)
        XCTAssertTrue(buffer(dev).contains("PRESERVED TAB OUTPUT"))
        XCTAssertNotNil(dev.terminal.window)
        XCTAssertNil(logs.terminal.window)
        attach(window, name: "Multiple session terminal")
        window.rootViewController = UIHostingController(rootView: SessionPanel(store: store, hostID: dev.host.id, dismiss: {}))
        try await Task.sleep(for: .milliseconds(300))
        attach(window, name: "Session panel")
    }
    private func buffer(_ session: TerminalSession) -> String {
        String(decoding: session.terminal.getTerminal().getBufferAsData(), as: UTF8.self)
    }
    private func attach(_ window: UIWindow, name: String) {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
