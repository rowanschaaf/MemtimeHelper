import XCTest
@testable import MemtimeHelper

final class OutlookContextTests: XCTestCase {
    func test_readingEmail_formatsAsSenderDashSubject() {
        let ctx = OutlookContext.readingEmail(sender: "John Smith", subject: "Q1 Budget Review")
        XCTAssertEqual(ctx.formattedTitle, "John Smith — Q1 Budget Review")
    }

    func test_composing_withRecipientAndSubject() {
        let ctx = OutlookContext.composing(to: "jane@example.com", subject: "Meeting Follow-up")
        XCTAssertEqual(ctx.formattedTitle, "Composing to jane@example.com — Meeting Follow-up")
    }

    func test_composing_withNoSubject() {
        let ctx = OutlookContext.composing(to: "jane@example.com", subject: nil)
        XCTAssertEqual(ctx.formattedTitle, "Composing to jane@example.com — No Subject")
    }

    func test_composing_withNoRecipient() {
        let ctx = OutlookContext.composing(to: nil, subject: "Draft")
        XCTAssertEqual(ctx.formattedTitle, "Composing to New Email — Draft")
    }

    func test_calendar_withTitle() {
        let ctx = OutlookContext.calendar(eventTitle: "Team Standup")
        XCTAssertEqual(ctx.formattedTitle, "Calendar: Team Standup")
    }

    func test_calendar_withNilTitle() {
        let ctx = OutlookContext.calendar(eventTitle: nil)
        XCTAssertEqual(ctx.formattedTitle, "Calendar: Calendar")
    }
}
