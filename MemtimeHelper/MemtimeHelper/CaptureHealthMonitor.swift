import Foundation

/// Turns capture events into a menu-bar status. Main thread only: the engine
/// calls it from its tick, and the reader's denial arrives on the main queue.
@MainActor
final class CaptureHealthMonitor {
    var onChange: ((CaptureHealth.Status) -> Void)?
    var onTitleAlert: ((String) -> Void)?
    private(set) var status: CaptureHealth.Status = .capturing

    private var health = CaptureHealth()
    private let extractors: [String: String]
    private var titleHealth: [String: TitleHealth]
    private let isAccessibilityGranted: () -> Bool

    init(extractors: [String: String], threshold: TimeInterval,
         isAccessibilityGranted: @escaping () -> Bool = { AccessibilityPermission.isGranted }) {
        self.extractors = extractors
        self.titleHealth = extractors.mapValues { _ in TitleHealth(threshold: threshold) }
        self.isAccessibilityGranted = isAccessibilityGranted
    }

    /// The extractor apps to health check: only those that always yield a title
    /// while frontmost. Outlook has views with no title, so it would alert falsely.
    static func healthCheckedExtractors(_ monitors: [AppMonitor]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: monitors.filter(\.expectsTitleWhenFrontmost)
            .map { ($0.bundleID, $0.appDisplayName) })
    }

    func record(_ sample: ActivitySample, at now: Date) {
        let granted = isAccessibilityGranted()
        health.set(.accessibilityMissing, active: !granted)
        // Without Accessibility no title can be read; the permission reason covers it.
        for (program, app) in extractors where granted {
            let frontmost = sample.bundleID == program && !sample.isLocked
            let title = frontmost ? sample.extractedTitle : nil
            switch titleHealth[program]?.record(title: title, frontmost: frontmost, at: now) {
            case .alert:
                health.set(.titlesNotRead(app: app), active: true)
                onTitleAlert?(app)
            case .recovered:
                health.set(.titlesNotRead(app: app), active: false)
            case nil:
                break
            }
        }
        publish()
    }

    func setWritesFailing(_ failing: Bool) {
        health.set(.storeWritesFailing, active: failing)
        publish()
    }

    func setAutomationDenied(browser: String) {
        health.set(.automationDenied(browser: browser), active: true)
        publish()
    }

    func stop(because reason: String) {
        health.stop(because: reason)
        publish()
    }

    private func publish() {
        let next = health.status
        guard next != status else { return }
        status = next
        onChange?(next)
    }
}
