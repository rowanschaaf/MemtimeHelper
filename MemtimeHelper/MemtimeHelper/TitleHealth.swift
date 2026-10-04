import Foundation

/// Detects a monitor that has silently stopped reading titles.
///
/// Title extraction depends on the monitored app's AX layout, which changes
/// without notice. When it breaks, the monitor returns nil, WorkspaceObserver
/// skips the write, and Memtime logs the bare app name — for weeks, unnoticed.
///
/// Only frontmost time counts: a backgrounded app often returns a stub AX
/// tree, so nil reads there are normal. The missing time accumulates across
/// frontmost spells and resets on any successful read.
struct TitleHealth {
    enum Event: Equatable {
        /// Missing time reached the threshold, or a new day started while degraded.
        case alert
        /// A title was read again after an alert.
        case recovered
    }

    static let defaultThreshold: TimeInterval = 600
    static let thresholdDefaultsKey = "TitleHealthThresholdSeconds"

    /// The threshold, overridable for live testing with
    /// `defaults write com.memtimehelper.MemtimeHelper TitleHealthThresholdSeconds -int 20`.
    static func configuredThreshold(defaults: UserDefaults = .standard) -> TimeInterval {
        let override = defaults.double(forKey: thresholdDefaultsKey)
        return override > 0 ? override : defaultThreshold
    }

    /// The most one poll interval can add. Polling stops while the Mac
    /// sleeps; without this cap the gap on wake would count as missing time.
    private static let maxPollGap: TimeInterval = 5

    let threshold: TimeInterval
    let calendar: Calendar
    private(set) var isDegraded = false
    private var missingTime: TimeInterval = 0
    private var lastPoll: Date?
    private var lastAlert: Date?

    init(threshold: TimeInterval, calendar: Calendar = .current) {
        self.threshold = threshold
        self.calendar = calendar
    }

    mutating func record(title: String?, frontmost: Bool, at now: Date) -> Event? {
        defer { lastPoll = now }

        if title != nil {
            missingTime = 0
            guard isDegraded else { return nil }
            isDegraded = false
            lastAlert = nil
            return .recovered
        }

        guard frontmost else { return nil }
        if let lastPoll {
            missingTime += min(now.timeIntervalSince(lastPoll), Self.maxPollGap)
        }
        guard missingTime >= threshold else { return nil }

        if !isDegraded {
            isDegraded = true
            lastAlert = now
            return .alert
        }
        if let lastAlert, !calendar.isDate(lastAlert, inSameDayAs: now) {
            self.lastAlert = now
            return .alert
        }
        return nil
    }
}
