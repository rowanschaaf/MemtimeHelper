import XCTest
@testable import MemtimeHelper

final class CaptureHealthTests: XCTestCase {
    func test_noReasons_isCapturing() {
        XCTAssertEqual(CaptureHealth().status, .capturing)
    }

    func test_activeReasons_areDegraded_sortedByMessage() {
        var h = CaptureHealth()
        h.set(.storeWritesFailing, active: true)
        h.set(.accessibilityMissing, active: true)
        XCTAssertEqual(h.status, .degraded([.accessibilityMissing, .storeWritesFailing]))
    }

    func test_clearingTheLastReason_returnsToCapturing() {
        var h = CaptureHealth()
        h.set(.titlesNotRead(app: "Claude"), active: true)
        h.set(.titlesNotRead(app: "Claude"), active: false)
        XCTAssertEqual(h.status, .capturing)
    }

    func test_stopped_winsOverDegraded() {
        var h = CaptureHealth()
        h.set(.storeWritesFailing, active: true)
        h.stop(because: "the capture store could not open")
        XCTAssertEqual(h.status, .stopped("the capture store could not open"))
    }

    func test_messages_nameTheApp() {
        XCTAssertTrue(CaptureHealth.Reason.automationDenied(browser: "Microsoft Edge").message.contains("Microsoft Edge"))
        XCTAssertTrue(CaptureHealth.Reason.titlesNotRead(app: "Claude").message.contains("Claude"))
    }
}
