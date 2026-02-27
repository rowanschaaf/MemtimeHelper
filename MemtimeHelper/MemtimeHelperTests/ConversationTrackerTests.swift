import XCTest
@testable import MemtimeHelper

@MainActor
final class ConversationTrackerTests: XCTestCase {
    func test_hasChanged_returnsTrueWhenTitleDiffers() {
        let tracker = ConversationTracker()
        tracker.record("old title")
        XCTAssertTrue(tracker.hasChanged(from: "new title"))
    }

    func test_hasChanged_returnsFalseWhenTitleSame() {
        let tracker = ConversationTracker()
        tracker.record("same title")
        XCTAssertFalse(tracker.hasChanged(from: "same title"))
    }

    func test_hasChanged_returnsTrueFromNilToNonNil() {
        let tracker = ConversationTracker()
        // lastTitle is nil by default
        XCTAssertTrue(tracker.hasChanged(from: "new title"))
    }

    func test_hasChanged_returnsFalseWhenBothNil() {
        let tracker = ConversationTracker()
        // lastTitle is nil by default
        XCTAssertFalse(tracker.hasChanged(from: nil))
    }

    func test_record_updatesTrackedTitle() {
        let tracker = ConversationTracker()
        tracker.record("my project: task")
        XCTAssertFalse(tracker.hasChanged(from: "my project: task"))
    }

    func test_hasChanged_returnsTrueFromNonNilToNil() {
        let tracker = ConversationTracker()
        tracker.record("some title")
        XCTAssertTrue(tracker.hasChanged(from: nil))
    }
}
