import Foundation

/// The native capture engine's health, as the menu bar shows it.
struct CaptureHealth: Equatable {
    enum Reason: Hashable {
        case accessibilityMissing
        case automationDenied(browser: String)
        case titlesNotRead(app: String)
        case storeWritesFailing

        var message: String {
            switch self {
            case .accessibilityMissing:
                return "Accessibility permission missing: window titles are not recorded"
            case .automationDenied(let browser):
                return "Automation for \(browser) denied: \(browser) URLs are not recorded"
            case .titlesNotRead(let app):
                return "\(app) titles are not being read: use Dump Claude AX Tree…"
            case .storeWritesFailing:
                return "Segments are not being saved: they are queued in memory"
            }
        }
    }

    enum Status: Equatable {
        case capturing
        case degraded([Reason])
        case stopped(String)
    }

    private(set) var reasons: Set<Reason> = []
    private(set) var stoppedReason: String?

    mutating func set(_ reason: Reason, active: Bool) {
        if active { reasons.insert(reason) } else { reasons.remove(reason) }
    }

    mutating func stop(because reason: String) {
        stoppedReason = reason
    }

    var status: Status {
        if let stoppedReason { return .stopped(stoppedReason) }
        if reasons.isEmpty { return .capturing }
        return .degraded(reasons.sorted { $0.message < $1.message })
    }
}
