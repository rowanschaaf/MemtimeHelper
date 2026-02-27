import XCTest
@testable import MemtimeHelper

@MainActor
final class ConversationTrackerTests: XCTestCase {
    func test_hasChanged_returnsTrueWhenTitleDiffers() {
        let tracker = ConversationTracker()
        tracker.lastTitle = "old title"
        XCTAssertTrue(tracker.hasChanged(from: "new title"))
    }

    func test_hasChanged_returnsFalseWhenTitleSame() {
        let tracker = ConversationTracker()
        tracker.lastTitle = "same title"
        XCTAssertFalse(tracker.hasChanged(from: "same title"))
    }

    func test_hasChanged_returnsTrueFromNilToNonNil() {
        let tracker = ConversationTracker()
        tracker.lastTitle = nil
        XCTAssertTrue(tracker.hasChanged(from: "new title"))
    }

    func test_hasChanged_returnsFalseWhenBothNil() {
        let tracker = ConversationTracker()
        tracker.lastTitle = nil
        XCTAssertFalse(tracker.hasChanged(from: nil))
    }

    func test_record_updatesLastTitle() {
        let tracker = ConversationTracker()
        tracker.record("my project: task")
        XCTAssertEqual(tracker.lastTitle, "my project: task")
    }

    func test_hasChanged_returnsTrueFromNonNilToNil() {
        let tracker = ConversationTracker()
        tracker.lastTitle = "some title"
        XCTAssertTrue(tracker.hasChanged(from: nil))
    }
}
