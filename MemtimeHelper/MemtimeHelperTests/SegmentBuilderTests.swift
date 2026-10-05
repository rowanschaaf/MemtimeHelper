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

    func test_rule2_idleExactly300_opensOffline() {
        var b = SegmentBuilder()
        let closed = feed(&b, idleRun(from: 100, to: 500))   // the last sample has idle of exactly 300
        XCTAssertEqual(closed, [appSegment(100, 200)])
        XCTAssertEqual(b.open, CapturedSegment(start: 200, end: 500, type: .offline, program: nil,
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

    let claude = "com.anthropic.claudefordesktop"

    func claudeSample(_ t: Int64, _ extracted: String?) -> ActivitySample {
        sample(t, claude, title: "Claude", enricher: "claude", extracted: extracted)
    }

    func test_extractedTitle_isUsed_withEnricherName() {
        var b = SegmentBuilder()
        _ = b.ingest(claudeSample(100, "PAT: plan"))
        XCTAssertEqual(b.open, CapturedSegment(start: 100, end: 100, type: .app, program: claude,
                                               title: "PAT: plan", path: nil, rawTitle: "Claude",
                                               enricher: "claude"))
    }

    func test_rule4_nilReadsWithin60s_keepTitle_andDoNotSplit() {
        var b = SegmentBuilder()
        var samples = [claudeSample(100, "PAT: plan")]
        samples += (101...160).map { claudeSample($0, nil) }
        let closed = feed(&b, samples)
        XCTAssertEqual(closed, [])
        XCTAssertEqual(b.open?.title, "PAT: plan")
        XCTAssertEqual(b.open?.enricher, "claude")
        XCTAssertEqual(b.open?.end, 160)
    }

    func test_rule5_nilReadsPast60s_fallBackToWindowTitle() {
        var b = SegmentBuilder()
        var samples = [claudeSample(100, "PAT: plan")]
        samples += (101...161).map { claudeSample($0, nil) }
        let closed = feed(&b, samples)
        XCTAssertEqual(closed.map(\.title), ["PAT: plan"])
        XCTAssertEqual(closed.first?.end, 161)
        XCTAssertEqual(b.open?.title, "Claude")
        XCTAssertNil(b.open?.enricher)
    }

    func test_rule5_noSuccessAtAll_recordsWindowTitle_withNilEnricher() {
        var b = SegmentBuilder()
        _ = feed(&b, (100...110).map { claudeSample($0, nil) })
        XCTAssertEqual(b.open?.title, "Claude")
        XCTAssertNil(b.open?.enricher)
    }

    func test_rule4_carryForwardIsPerApp() {
        var b = SegmentBuilder()
        _ = b.ingest(claudeSample(100, "PAT: plan"))
        _ = b.ingest(sample(101, "com.microsoft.Outlook", title: "Inbox", enricher: "outlook", extracted: "Re: invoice"))
        _ = b.ingest(claudeSample(102, nil))
        XCTAssertEqual(b.open?.title, "PAT: plan")
    }

    func test_appWithoutExtractor_usesWindowTitle() {
        var b = SegmentBuilder()
        _ = b.ingest(sample(100, appA, title: "Spreadsheet"))
        XCTAssertEqual(b.open?.title, "Spreadsheet")
        XCTAssertNil(b.open?.enricher)
    }

    func test_rule4_laterSuccess_resetsTheWindow() {
        var b = SegmentBuilder()
        var samples = [claudeSample(100, "PAT: plan")]
        samples += (101...149).map { claudeSample($0, nil) }
        samples.append(claudeSample(150, "PAT: plan"))          // same title; window restarts at 150
        samples += (151...211).map { claudeSample($0, nil) }    // 211 is 61 s after 150, 111 s after 100
        let closed = feed(&b, samples)
        XCTAssertEqual(closed.map(\.end), [211])
        XCTAssertEqual(b.open?.title, "Claude")
    }

    func test_rule4_carriesTheLatestExtractedTitle() {
        var b = SegmentBuilder()
        _ = feed(&b, [claudeSample(100, "PAT: plan"), claudeSample(150, "PAT: review"), claudeSample(151, nil)])
        XCTAssertEqual(b.open?.title, "PAT: review")
        XCTAssertEqual(b.open?.enricher, "claude")
    }

    func test_rule6_gapOver10s_closesAtLastSample() {
        var b = SegmentBuilder()
        var closed = feed(&b, (100...105).map { sample($0) })
        closed += b.ingest(sample(116))
        XCTAssertEqual(closed, [appSegment(100, 105)])
        XCTAssertEqual(b.open, appSegment(116, 116))
    }

    func test_rule6_gapOf10s_doesNotSplit() {
        var b = SegmentBuilder()
        var closed = feed(&b, (100...105).map { sample($0) })
        closed += b.ingest(sample(115))
        XCTAssertEqual(closed, [])
        XCTAssertEqual(b.open, appSegment(100, 115))
    }

    func test_rule7_clockBackwards_closesAtLastSample() throws {
        var b = SegmentBuilder()
        var closed = feed(&b, (100...105).map { sample($0) })
        closed += b.ingest(sample(90))
        XCTAssertEqual(closed, [appSegment(100, 105)])
        // The new segment starts at the floor, not at the earlier clock reading,
        // so it cannot overlap the segment that just closed.
        let open = try XCTUnwrap(b.open)
        XCTAssertEqual(open.start, 105)
        XCTAssertGreaterThanOrEqual(open.end, open.start)
    }

    func test_rule8_interrupt_closesAtEventTime() {
        var b = SegmentBuilder()
        _ = feed(&b, (100...105).map { sample($0) })
        XCTAssertEqual(b.interrupt(at: 105), [appSegment(100, 105)])
        XCTAssertNil(b.open)
    }

    func test_rule9_locked_opensNoSegment() {
        var b = SegmentBuilder()
        var closed = feed(&b, (100...105).map { sample($0) })
        closed += feed(&b, (106...120).map { sample($0, locked: true) })
        XCTAssertEqual(closed, [appSegment(100, 106)])
        XCTAssertNil(b.open)
        _ = b.ingest(sample(121))
        XCTAssertEqual(b.open, appSegment(121, 121))
    }

    func test_wakeWithStaleIdle_offlineStartsAtWake_notBeforeSleep() {
        // The Mac slept from t = 105. On wake the idle counter still measures from
        // the last input before sleep, so offline must not reach back across the sleep.
        var b = SegmentBuilder()
        var closed = feed(&b, (100...105).map { sample($0) })
        closed += b.ingest(sample(4000, idle: 3895))
        XCTAssertEqual(closed, [appSegment(100, 105)])
        XCTAssertEqual(b.open?.type, .offline)
        XCTAssertEqual(b.open?.start, 4000)
    }
}
