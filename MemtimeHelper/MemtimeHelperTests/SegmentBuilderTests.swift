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

    func test_clockBackwards_neverOverlaps() {
        var b = SegmentBuilder()
        var closed = feed(&b, (100...110).map { sample($0) })
        closed += b.ingest(sample(105))
        XCTAssertEqual(closed, [appSegment(100, 110)])
        XCTAssertGreaterThanOrEqual(b.open!.start, 110)
        XCTAssertGreaterThanOrEqual(b.open!.end, b.open!.start)
    }

    func test_interruptThenEarlierSample_neverOverlaps() {
        var b = SegmentBuilder()
        _ = feed(&b, (100...110).map { sample($0) })
        _ = b.interrupt(at: 110)
        _ = b.ingest(sample(108))
        XCTAssertGreaterThanOrEqual(b.open!.start, 110)
        XCTAssertGreaterThanOrEqual(b.open!.end, b.open!.start)
    }

    func test_interruptThenWakeWithStaleIdle_offlineStartsAtWake() {
        // No segment while the Mac sleeps: the idle counter spans the sleep,
        // but the offline segment may only start at the wake sample.
        var b = SegmentBuilder()
        _ = feed(&b, (100...105).map { sample($0) })
        _ = b.interrupt(at: 105)
        _ = b.ingest(sample(4000, idle: 3895))
        XCTAssertEqual(b.open?.type, .offline)
        XCTAssertEqual(b.open?.start, 4000)
    }

    /// Input stops at t = 200 and the user stays away. Samples arrive every second.
    func idleRun(from start: Int64, to end: Int64, lastInput: Int64 = 200) -> [ActivitySample] {
        (start...end).map { t in sample(t, idle: max(0, t - lastInput)) }
    }

    func test_rule2_idleBelowThreshold_staysActive() {
        var b = SegmentBuilder()
        let closed = feed(&b, idleRun(from: 100, to: 499))   // idle reaches 299
        XCTAssertEqual(closed, [])
        XCTAssertEqual(b.open?.type, .app)
    }

    func test_rule2_idleAtThreshold_endsActiveAtLastInput_andOpensOffline() {
        var b = SegmentBuilder()
        let closed = feed(&b, idleRun(from: 100, to: 510))   // idle reaches 300 at t = 500
        XCTAssertEqual(closed, [appSegment(100, 200)])
        XCTAssertEqual(b.open, CapturedSegment(start: 200, end: 510, type: .offline, program: nil,
                                               title: nil, path: nil, rawTitle: nil, enricher: nil))
    }

    func test_rule3_inputResumes_closesOfflineAtFirstInput_andResumesActivity() {
        var b = SegmentBuilder()
        var closed = feed(&b, idleRun(from: 100, to: 510))
        closed += b.ingest(sample(511, idle: 2))             // first input at t = 509
        XCTAssertEqual(closed.last, CapturedSegment(start: 200, end: 509, type: .offline, program: nil,
                                                    title: nil, path: nil, rawTitle: nil, enricher: nil))
        XCTAssertEqual(b.open, appSegment(509, 511))
    }
}
