import XCTest
@testable import MemtimeHelper

@MainActor
final class AppStateTests: XCTestCase {
    private let claude = "com.anthropic.claudefordesktop"

    func test_setDegraded_showsWarningIconAndMessage() {
        let state = AppState()
        state.setActive(bundleID: claude, title: "A conversation")

        state.setDegraded(bundleID: claude, appName: "Claude")

        XCTAssertEqual(state.statusIcon, "exclamationmark.triangle.fill")
        XCTAssertTrue(state.statusMessage.hasPrefix("Claude: no title read"), state.statusMessage)
        XCTAssertTrue(state.statusMessage.contains("Dump Claude AX Tree"), state.statusMessage)
    }

    func test_clearDegraded_restoresNormalStatus() {
        let state = AppState()
        state.setActive(bundleID: claude, title: "A conversation")
        state.setDegraded(bundleID: claude, appName: "Claude")

        state.clearDegraded(bundleID: claude)

        XCTAssertEqual(state.statusIcon, "circle.fill")
        XCTAssertEqual(state.statusMessage, "A conversation")
    }

    func test_captureStopped_showsStoppedIconAndReason() {
        let state = AppState()
        state.setCaptureStatus(.stopped("the capture store could not open"))
        XCTAssertEqual(state.statusIcon, "xmark.octagon.fill")
        XCTAssertTrue(state.statusMessage.contains("the capture store could not open"))
    }

    func test_captureDegraded_listsEachReason() {
        let state = AppState()
        state.setCaptureStatus(.degraded([.accessibilityMissing, .storeWritesFailing]))
        XCTAssertEqual(state.statusIcon, "exclamationmark.triangle.fill")
        XCTAssertTrue(state.statusMessage.contains(CaptureHealth.Reason.accessibilityMissing.message))
        XCTAssertTrue(state.statusMessage.contains(CaptureHealth.Reason.storeWritesFailing.message))
    }

    func test_captureRecovered_returnsToTheAppStatus() {
        let state = AppState()
        state.setActive(bundleID: "com.anthropic.claudefordesktop", title: "PAT: plan")
        state.setCaptureStatus(.degraded([.storeWritesFailing]))
        state.setCaptureStatus(.capturing)
        XCTAssertEqual(state.statusMessage, "PAT: plan")
        XCTAssertEqual(state.statusIcon, "circle.fill")
    }

    func test_stoppedCapture_isNotHiddenByLaterPermissionError() {
        let state = AppState()
        state.setCaptureStatus(.stopped("the capture store could not open"))
        state.setPermissionError()
        XCTAssertEqual(state.statusIcon, "xmark.octagon.fill")
        XCTAssertTrue(state.statusMessage.contains("the capture store could not open"))
    }

    func test_permissionError_aloneShowsPermissionNeeded() {
        let state = AppState()
        state.setPermissionError()
        XCTAssertEqual(state.statusMessage, "Accessibility permission needed")
        XCTAssertEqual(state.statusIcon, "exclamationmark.circle")
    }

    func test_degradedCapture_outranksPermissionError() {
        let state = AppState()
        state.setPermissionError()
        state.setCaptureStatus(.degraded([.accessibilityMissing]))
        XCTAssertEqual(state.statusIcon, "exclamationmark.triangle.fill")
        XCTAssertTrue(state.statusMessage.contains(CaptureHealth.Reason.accessibilityMissing.message))
    }

    func test_clearPermissionError_returnsToTheAppStatus() {
        let state = AppState()
        state.setPermissionError()
        state.clearPermissionError()
        XCTAssertEqual(state.statusMessage, "Monitoring — no active context")
    }
}
