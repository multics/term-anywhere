import XCTest
import SwiftUI
import SwiftTerm
import TermCore
@testable import TermAnywhere

@MainActor final class TerminalInputTests: XCTestCase {
    func testKeyboardCanHideAndReturnWithoutClosingTheSession() async throws {
        let store = AppStore(); store.configuration.onChange = nil
        let host = Host(name: "Keyboard fixture", address: "example.invalid", username: "fixture", keyID: "missing-fixture")
        store.hosts = [host]; store.selectHost(host.id)
        let session = try XCTUnwrap(store.sessions[host.id]); session.hasStarted = true
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let controller = UIHostingController(rootView: NavigationStack {
            TerminalScreen(session: session, onDisconnect: { store.closeSession(host.id) })
        })
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { store.closeSession(host.id); window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .milliseconds(300))
        session.terminal.feed(text: "Read this output with the keyboard hidden\r\n$ ")
        session.showKeyboard()
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertTrue(session.terminal.isFirstResponder)
        session.hideKeyboard()
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertFalse(session.terminal.isFirstResponder); XCTAssertFalse(session.keyboardVisible)
        XCTAssertEqual(store.selectedHostID, host.id); XCTAssertTrue(store.sessions[host.id] === session)
        XCTAssertTrue(String(decoding: session.terminal.getTerminal().getBufferAsData(), as: UTF8.self).contains("Read this output"))
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = "Terminal with keyboard hidden"; attachment.lifetime = .keepAlways; add(attachment)
        session.showKeyboard()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(session.terminal.isFirstResponder)
    }
    func testTerminalAppearanceChangesWithoutLosingOutput() async throws {
        let store = AppStore()
        // This fixture applies preferences directly; live iCloud delivery must not replace them.
        store.configuration.onChange = nil
        let host = Host(name: "Appearance fixture", address: "example.invalid", username: "fixture", keyID: "missing-fixture")
        let session = store.session(for: host)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let controller = TerminalCoordinator(session: session); session.coordinator = controller
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { store.closeSession(host.id); window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .milliseconds(200))
        window.layoutIfNeeded()
        session.terminal.feed(text: "Appearance keeps terminal output\r\n$ ")
        func output() -> String {
            String(decoding: session.terminal.getTerminal().getBufferAsData(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let before = output()
        var value = TerminalPreferences()
        for appearance in [AppAppearance.dark, .light] {
            value.appearance = appearance; session.applyPreferences(value)
            let traits = UITraitCollection(userInterfaceStyle: appearance == .dark ? .dark : .light)
            for _ in 0..<20 {
                if session.terminal.nativeBackgroundColor == UIColor.systemBackground.resolvedColor(with: traits) { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            XCTAssertEqual(session.terminal.nativeBackgroundColor, UIColor.systemBackground.resolvedColor(with: traits))
            XCTAssertEqual(session.terminal.nativeForegroundColor, UIColor.label.resolvedColor(with: traits))
            XCTAssertEqual(output(), before)
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: image); attachment.name = appearance.title + " terminal"; attachment.lifetime = .keepAlways; add(attachment)
        }
        value.appearance = .system; session.applyPreferences(value)
        for style in [UIUserInterfaceStyle.dark, .light] {
            window.overrideUserInterfaceStyle = style
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(session.terminal.nativeBackgroundColor, UIColor.systemBackground.resolvedColor(with: UITraitCollection(userInterfaceStyle: style)))
        }
        XCTAssertEqual(output(), before)
    }
    func testDisconnectRemovesTerminalFromVisibleHierarchy() async throws {
        let store = AppStore()
        let host = Host(name: "UI fixture", address: "example.invalid", username: "fixture", keyID: "missing-" + UUID().uuidString)
        store.hosts = [host]
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let controller = UIHostingController(rootView: HostListView().environmentObject(store).environment(\.scenePhase, .active))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        let initialOrientation = scene.effectiveGeometry.interfaceOrientation
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .milliseconds(200))
        store.selectHost(host.id)
        let session = try XCTUnwrap(store.sessions[host.id])
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertNotNil(session.terminal.window)
        session.isLive = true; session.status = "Connected"
        session.terminal.feed(text: "Welcome to the terminal\r\n$ ")
        for _ in 0..<50 {
            if scene.traitCollection.userInterfaceIdiom != .phone || scene.effectiveGeometry.interfaceOrientation.isLandscape { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        if scene.traitCollection.userInterfaceIdiom == .phone {
            XCTAssertTrue(scene.effectiveGeometry.interfaceOrientation.isLandscape, "A connected iPhone terminal must request landscape")
        } else {
            XCTAssertEqual(scene.effectiveGeometry.interfaceOrientation, initialOrientation, "iPad orientation must remain under user control")
        }
        try await Task.sleep(for: .milliseconds(600))
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Connected terminal layout"; attachment.lifetime = .keepAlways
        add(attachment)
        store.closeSession(host.id)
        for _ in 0..<50 {
            if session.terminal.window == nil && scene.effectiveGeometry.interfaceOrientation == initialOrientation { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(scene.effectiveGeometry.interfaceOrientation, initialOrientation)
        XCTAssertNil(store.selectedHostID)
        XCTAssertNil(session.terminal.window, "Disconnect must remove the terminal from the displayed hierarchy")
        XCTAssertNil(session.coordinator)
        XCTAssertTrue(store.sessions.isEmpty, "Rendering the empty detail must not recreate a session")
    }
    func testExplicitDisconnectClearsSelectionAndNeedsNewUserSelection() {
        let store = AppStore()
        let host = Host(name: "Disconnect fixture", address: "example.invalid", username: "fixture", keyID: "missing-fixture")
        store.hosts = [host]
        store.selectHost(host.id)
        let session = store.sessions[host.id]!
        session.isLive = true
        session.error = "Old error"
        session.pendingFingerprint = "Old fingerprint"
        session.changedFingerprint = true
        session.showingPassphrase = true
        session.passphrase = "synthetic"
        session.terminal.controlModifier = true
        session.terminal.metaModifier = true
        session.terminal.feed(text: "Old output")
        store.closeSession(host.id)
        XCTAssertNil(store.selectedHostID)
        XCTAssertNil(store.sessions[host.id])
        XCTAssertFalse(session.isLive)
        XCTAssertFalse(session.isConnecting)
        XCTAssertNil(session.error)
        XCTAssertNil(session.pendingFingerprint)
        XCTAssertFalse(session.showingPassphrase)
        XCTAssertTrue(session.passphrase.isEmpty)
        XCTAssertFalse(session.terminal.controlModifier)
        XCTAssertFalse(session.terminal.metaModifier)
        XCTAssertTrue(session.hasStarted, "A pending view task must not start this closed session")
        session.resume()
        XCTAssertFalse(session.isConnecting)
        store.selectHost(host.id)
        XCTAssertFalse(store.sessions[host.id] === session)
        XCTAssertFalse(store.sessions[host.id]!.hasStarted)
        store.closeSession(host.id)
    }
    func testClosingAnotherSessionPreservesCurrentSelection() {
        let store = AppStore()
        let first = Host(name: "First", address: "example.invalid", username: "fixture", keyID: "missing-fixture")
        let second = Host(name: "Second", address: "example.invalid", username: "fixture", keyID: "missing-fixture")
        store.hosts = [first, second]
        store.selectHost(first.id)
        store.selectHost(second.id)
        store.closeSession(first.id)
        XCTAssertEqual(store.selectedHostID, second.id)
        XCTAssertNotNil(store.sessions[second.id])
        store.closeSession(second.id)
    }
    func testCancellingSessionPickerClosesTheLocalSession() async throws {
        let store = AppStore()
        let host = Host(name: "Picker fixture", address: "example.invalid", username: "fixture", keyID: "missing-fixture")
        store.hosts = [host]; store.selectHost(host.id)
        let session = try XCTUnwrap(store.sessions[host.id])
        let waiting = Task { try await session.requestTmuxSelection() }
        await Task.yield()
        XCTAssertTrue(session.selectingTmux)
        session.cancelTmuxSelection()
        do { _ = try await waiting.value; XCTFail("The waiting connection must be cancelled") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(session.selectingTmux); XCTAssertNil(store.selectedHostID)
        XCTAssertNil(store.sessions[host.id])
    }
    func testSessionPickerValidatesBeforeResuming() async throws {
        let store = AppStore()
        let host = Host(name: "Picker fixture", address: "example.invalid", username: "fixture", keyID: "missing-fixture")
        let session = store.session(for: host)
        let waiting = Task { try await session.requestTmuxSelection() }
        await Task.yield()
        session.selectTmuxSession("invalid;name")
        XCTAssertTrue(session.selectingTmux); XCTAssertNotNil(session.tmuxSelectionError)
        session.selectTmuxSession("work")
        let selected = try await waiting.value
        XCTAssertEqual(selected.name, "work"); XCTAssertFalse(selected.create)
        XCTAssertFalse(session.selectingTmux)
        store.closeSession(host.id)
    }
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
