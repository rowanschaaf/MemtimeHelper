import XCTest
@testable import MemtimeHelper

final class WindowTitleFormatterTests: XCTestCase {
    func test_format_withConversationTitle_returnsEnrichedTitle() {
        let result = WindowTitleUpdater.formatTitle("Memtime: fix bug")
        XCTAssertEqual(result, "Claude • Memtime: fix bug")
    }

    func test_format_withEmptyTitle_returnsBaseTitle() {
        let result = WindowTitleUpdater.formatTitle("")
        XCTAssertEqual(result, "Claude")
    }

    func test_format_withNilTitle_returnsBaseTitle() {
        let result = WindowTitleUpdater.formatTitle(nil)
        XCTAssertEqual(result, "Claude")
    }
}
