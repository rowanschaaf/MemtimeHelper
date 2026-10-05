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
}
