import XCTest
@testable import MemtimeHelper

final class TitleHealthTests: XCTestCase {

    private var calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    /// 2026-10-05 09:00 UTC.
    private var clock = Date(timeIntervalSince1970: 1_791_190_800)

    private func makeHealth() -> TitleHealth {
        TitleHealth(threshold: 600, calendar: calendar)
    }

    /// Feeds one poll per second for `seconds` seconds, as WorkspaceObserver
    /// does, and returns every event emitted.
    private func poll(_ health: inout TitleHealth, seconds: Int,
                      title: String? = nil, frontmost: Bool = true) -> [TitleHealth.Event] {
        var events: [TitleHealth.Event] = []
        for _ in 0..<seconds {
            if let event = health.record(title: title, frontmost: frontmost, at: clock) {
                events.append(event)
            }
            clock += 1
        }
        return events
    }

    func test_noAlert_beforeThreshold() {
        var health = makeHealth()
        XCTAssertEqual(poll(&health, seconds: 300), [])
        XCTAssertFalse(health.isDegraded)
    }

    func test_alertsOnce_whenFrontmostWithoutTitlePastThreshold() {
        var health = makeHealth()
        XCTAssertEqual(poll(&health, seconds: 700), [.alert])
        XCTAssertTrue(health.isDegraded)
    }

    /// A backgrounded Claude often returns a stub AX tree. Those nil reads are
    /// normal and must never count.
    func test_backgroundNilReads_neverAlert() {
        var health = makeHealth()
        XCTAssertEqual(poll(&health, seconds: 3600, frontmost: false), [])
        XCTAssertFalse(health.isDegraded)
    }

    func test_successfulRead_resetsMissingTime() {
        var health = makeHealth()
        var events = poll(&health, seconds: 540)
        events += poll(&health, seconds: 1, title: "A conversation")
        events += poll(&health, seconds: 540)
        XCTAssertEqual(events, [])
    }

    func test_successfulRead_afterAlert_recovers() {
        var health = makeHealth()
        _ = poll(&health, seconds: 700)
        XCTAssertEqual(poll(&health, seconds: 1, title: "A conversation"), [.recovered])
        XCTAssertFalse(health.isDegraded)
    }

    /// Polling stops while the Mac sleeps. The gap on wake must not count as
    /// missing time, or every wake would raise a false alert.
    func test_pollGap_countsAsAtMostFiveSeconds() {
        var health = makeHealth()
        _ = poll(&health, seconds: 1)
        clock += 3600
        XCTAssertEqual(poll(&health, seconds: 1), [])
        XCTAssertFalse(health.isDegraded)
    }

    func test_stillDegraded_doesNotRepeatAlertSameDay() {
        var health = makeHealth()
        XCTAssertEqual(poll(&health, seconds: 700), [.alert])
        XCTAssertEqual(poll(&health, seconds: 3 * 3600), [])
    }

    func test_stillDegraded_repeatsAlertOnceOnNewDay() {
        var health = makeHealth()
        XCTAssertEqual(poll(&health, seconds: 700), [.alert])
        clock = calendar.date(byAdding: .day, value: 1, to: clock)!
        XCTAssertEqual(poll(&health, seconds: 120), [.alert])
    }

    func test_configuredThreshold_defaultsTo600() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        XCTAssertEqual(TitleHealth.configuredThreshold(defaults: defaults), 600)
    }

    func test_configuredThreshold_readsOverride() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defaults.set(20, forKey: TitleHealth.thresholdDefaultsKey)
        XCTAssertEqual(TitleHealth.configuredThreshold(defaults: defaults), 20)
    }
}
