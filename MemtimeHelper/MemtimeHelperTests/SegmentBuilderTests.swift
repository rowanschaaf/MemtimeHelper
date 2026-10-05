import XCTest
@testable import MemtimeHelper

final class SegmentBuilderTests: XCTestCase {
    let appA = "com.example.a"
    let appB = "com.example.b"
    let edge = "com.microsoft.edgemac"

    func sample(_ t: Int64, _ app: String? = "com.example.a", title: String? = "Doc A",
                idle: Int64 = 0, enricher: String? = nil, extracted: String? = nil,
                url: String? = nil, tab: String? = nil, locked: Bool = false) -> ActivitySample {
        ActivitySample(time: t, bundleID: app, windowTitle: title, url: url, tabTitle: tab,
                       idleSeconds: idle, enricherName: enricher, extractedTitle: extracted,
                       isLocked: locked)
    }

    /// Feeds samples in order and collects every segment that closed.
    func feed(_ builder: inout SegmentBuilder, _ samples: [ActivitySample]) -> [CapturedSegment] {
        samples.flatMap { builder.ingest($0) }
    }

    func appSegment(_ start: Int64, _ end: Int64, program: String = "com.example.a",
                    title: String? = "Doc A") -> CapturedSegment {
        CapturedSegment(start: start, end: end, type: .app, program: program,
                        title: title, path: nil, rawTitle: title, enricher: nil)
    }

    func test_sameActivity_extendsOneOpenSegment() {
        var b = SegmentBuilder()
        let closed = feed(&b, (100...105).map { sample($0) })
        XCTAssertEqual(closed, [])
        XCTAssertEqual(b.open, appSegment(100, 105))
    }

    func test_rule1_titleChange_closesAndOpens() {
        var b = SegmentBuilder()
        var closed = feed(&b, (100...101).map { sample($0) })
        closed += b.ingest(sample(102, title: "Doc B"))
        XCTAssertEqual(closed, [appSegment(100, 102)])
        XCTAssertEqual(b.open, appSegment(102, 102, title: "Doc B"))
    }

    func test_rule1_programChange_closesAndOpens() {
        var b = SegmentBuilder()
        var closed = feed(&b, (100...101).map { sample($0) })
        closed += b.ingest(sample(102, appB, title: "Doc A"))
        XCTAssertEqual(closed, [appSegment(100, 102)])
        XCTAssertEqual(b.open?.program, appB)
    }

    func test_rawTitleIsNotPartOfTheSegmentKey() {
        // An extracted title stays constant while the window title wobbles.
        var b = SegmentBuilder()
        let closed = feed(&b, [
            sample(100, title: "Claude", enricher: "claude", extracted: "PAT: plan"),
            sample(101, title: "Claude — PAT", enricher: "claude", extracted: "PAT: plan"),
        ])
        XCTAssertEqual(closed, [])
        XCTAssertEqual(b.open?.end, 101)
    }

    func test_noFrontmostApp_closesOpenSegment() {
        var b = SegmentBuilder()
        var closed = feed(&b, (100...101).map { sample($0) })
        closed += b.ingest(sample(102, nil, title: nil))
        XCTAssertEqual(closed, [appSegment(100, 102)])
        XCTAssertNil(b.open)
    }

    func test_browserBundle_isTypedBrowser_withTabTitleAndURL() {
        var b = SegmentBuilder()
        _ = b.ingest(sample(100, edge, title: "Edge — Board", url: "https://dev.azure.com/x", tab: "Board"))
        XCTAssertEqual(b.open, CapturedSegment(start: 100, end: 100, type: .browser, program: edge,
                                               title: "Board", path: "https://dev.azure.com/x",
                                               rawTitle: "Edge — Board", enricher: nil))
    }

    func test_browserWithoutAutomation_staysBrowser_withNilPath() {
        var b = SegmentBuilder()
        _ = b.ingest(sample(100, edge, title: "Edge — Board"))
        XCTAssertEqual(b.open?.type, .browser)
        XCTAssertNil(b.open?.path)
        XCTAssertEqual(b.open?.title, "Edge — Board")
    }
}
