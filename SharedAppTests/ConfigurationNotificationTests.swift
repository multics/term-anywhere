import XCTest
import Combine
#if os(macOS)
@testable import Term_Anywhere
#else
@testable import TermAnywhere
#endif

@MainActor final class ConfigurationNotificationTests: XCTestCase {
    func testBackgroundCloudNotificationPublishesOnMainThread() async {
        let sync = ConfigurationSync()
        let received = expectation(description: "Cloud status updated on main thread")
        let subscription = sync.$status.dropFirst().sink { status in
            guard status.contains("limit reached") else { return }
            XCTAssertTrue(Thread.isMainThread)
            received.fulfill()
        }
        await Task.detached {
            NotificationCenter.default.post(name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: NSUbiquitousKeyValueStore.default,
                userInfo: [NSUbiquitousKeyValueStoreChangeReasonKey: NSUbiquitousKeyValueStoreQuotaViolationChange])
        }.value
        await fulfillment(of: [received], timeout: 3)
        subscription.cancel()
        sync.start()
    }
}
