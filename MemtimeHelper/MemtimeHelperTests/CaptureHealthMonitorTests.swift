import XCTest
@testable import MemtimeHelper

private struct StubMonitor: AppMonitor {
    let bundleID: String
    let appDisplayName: String
    let expectsTitleWhenFrontmost: Bool
    func currentTitle(for pid: pid_t) -> String? { nil }
}

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

    func test_newDay_whileDegraded_alertsAgain_andStaysDegraded() {
        let m = makeMonitor(threshold: 10)
        let noon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date(timeIntervalSince1970: 1_800_000_000))!
        for i in 0...15 { m.record(claudeSample(0, title: nil), at: noon.addingTimeInterval(TimeInterval(i))) }
        XCTAssertEqual(alerts, ["Claude"])
        let nextNoon = Calendar.current.date(byAdding: .day, value: 1, to: noon)!
        for i in 0...15 { m.record(claudeSample(0, title: nil), at: nextNoon.addingTimeInterval(TimeInterval(i))) }
        XCTAssertEqual(alerts, ["Claude", "Claude"])
        XCTAssertEqual(m.status, .degraded([.titlesNotRead(app: "Claude")]))
    }

    func test_missingTimeAccumulatesAcrossSpells_andRecoveryIsPerApp() {
        let outlook = "com.microsoft.Outlook"
        let m = CaptureHealthMonitor(extractors: [claude: "Claude", outlook: "Outlook"], threshold: 10,
                                     isAccessibilityGranted: { true })
        m.onTitleAlert = { [unowned self] in alerts.append($0) }
        var t: Int64 = 100
        for _ in 0..<6 { m.record(claudeSample(t, title: nil), at: at(t)); t += 1 }
        for _ in 0..<20 {
            m.record(ActivitySample(time: t, bundleID: "com.example.app", windowTitle: "Doc"), at: at(t)); t += 1
        }
        XCTAssertEqual(alerts, [])
        for _ in 0..<6 { m.record(claudeSample(t, title: nil), at: at(t)); t += 1 }
        XCTAssertEqual(alerts, ["Claude"])
        XCTAssertEqual(m.status, .degraded([.titlesNotRead(app: "Claude")]))

        m.record(ActivitySample(time: t, bundleID: outlook, windowTitle: "Outlook",
                                enricherName: "outlook", extractedTitle: "Re: x"), at: at(t)); t += 1
        XCTAssertEqual(m.status, .degraded([.titlesNotRead(app: "Claude")]))

        m.record(claudeSample(t, title: "PAT: plan"), at: at(t))
        XCTAssertEqual(m.status, .capturing)
    }

    func test_afterStop_writesFailing_keepsStoppedAndDoesNotNotify() {
        let m = makeMonitor()
        m.stop(because: "gone")
        m.setWritesFailing(true)
        XCTAssertEqual(m.status, .stopped("gone"))
        XCTAssertEqual(statuses, [.stopped("gone")])
    }

    /// Outlook returns no title in its calendar and empty-inbox views, so a
    /// title alert for it is noise. Only apps that opt in are health checked.
    func test_healthCheckedExtractors_skipAppsThatDoNotExpectATitle() {
        let monitors: [AppMonitor] = [
            StubMonitor(bundleID: "com.example.chat", appDisplayName: "Chat", expectsTitleWhenFrontmost: true),
            StubMonitor(bundleID: "com.example.mail", appDisplayName: "Mail", expectsTitleWhenFrontmost: false),
        ]
        XCTAssertEqual(CaptureHealthMonitor.healthCheckedExtractors(monitors), ["com.example.chat": "Chat"])
    }
}
