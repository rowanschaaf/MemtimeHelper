import XCTest
@testable import MemtimeHelper

@MainActor
final class CaptureHealthMonitorTests: XCTestCase {
    private let claude = "com.anthropic.claudefordesktop"
    private var granted = true
    private var statuses: [CaptureHealth.Status] = []
    private var alerts: [String] = []

    private func makeMonitor(threshold: TimeInterval = 10) -> CaptureHealthMonitor {
        let m = CaptureHealthMonitor(extractors: [claude: "Claude"], threshold: threshold,
                                     isAccessibilityGranted: { [unowned self] in granted })
        m.onChange = { [unowned self] in statuses.append($0) }
        m.onTitleAlert = { [unowned self] in alerts.append($0) }
        return m
    }

    private func claudeSample(_ t: Int64, title: String?, locked: Bool = false) -> ActivitySample {
        ActivitySample(time: t, bundleID: claude, windowTitle: "Claude",
                       enricherName: "claude", extractedTitle: title, isLocked: locked)
    }

    private func at(_ t: Int64) -> Date { Date(timeIntervalSince1970: TimeInterval(t)) }

    func test_missingAccessibility_isDegraded_andRecovers() {
        let m = makeMonitor()
        granted = false
        m.record(claudeSample(100, title: "PAT: plan"), at: at(100))
        XCTAssertEqual(m.status, .degraded([.accessibilityMissing]))
        granted = true
        m.record(claudeSample(101, title: "PAT: plan"), at: at(101))
        XCTAssertEqual(m.status, .capturing)
        XCTAssertEqual(statuses, [.degraded([.accessibilityMissing]), .capturing])
    }

    func test_titlesNotRead_afterThreshold_alertsOnce() {
        let m = makeMonitor(threshold: 10)
        for t in Int64(100)...115 { m.record(claudeSample(t, title: nil), at: at(t)) }
        XCTAssertEqual(m.status, .degraded([.titlesNotRead(app: "Claude")]))
        XCTAssertEqual(alerts, ["Claude"])
    }

    func test_titleRead_clearsTheReason() {
        let m = makeMonitor(threshold: 10)
        for t in Int64(100)...115 { m.record(claudeSample(t, title: nil), at: at(t)) }
        m.record(claudeSample(116, title: "PAT: plan"), at: at(116))
        XCTAssertEqual(m.status, .capturing)
    }

    func test_lockedSamples_doNotCountAsMissingTime() {
        let m = makeMonitor(threshold: 10)
        for t in Int64(100)...130 { m.record(claudeSample(t, title: nil, locked: true), at: at(t)) }
        XCTAssertEqual(m.status, .capturing)
        XCTAssertEqual(alerts, [])
    }

    func test_otherFrontmostApp_doesNotCountAgainstClaude() {
        let m = makeMonitor(threshold: 10)
        for t in Int64(100)...130 {
            m.record(ActivitySample(time: t, bundleID: "com.example.app", windowTitle: "Doc"), at: at(t))
        }
        XCTAssertEqual(m.status, .capturing)
    }

    func test_writesFailing_andAutomationDenied_areReasons() {
        let m = makeMonitor()
        m.setWritesFailing(true)
        m.setAutomationDenied(browser: "Microsoft Edge")
        XCTAssertEqual(m.status, .degraded([.automationDenied(browser: "Microsoft Edge"), .storeWritesFailing]))
        m.setWritesFailing(false)
        XCTAssertEqual(m.status, .degraded([.automationDenied(browser: "Microsoft Edge")]))
    }

    func test_stop_reportsStopped_andNoRepeatOnSameStatus() {
        let m = makeMonitor()
        m.stop(because: "another MemtimeHelper instance owns the capture store")
        m.setWritesFailing(false)
        XCTAssertEqual(statuses, [.stopped("another MemtimeHelper instance owns the capture store")])
    }
}
