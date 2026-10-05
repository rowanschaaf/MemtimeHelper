import AppKit
import ApplicationServices
import CoreGraphics

/// Supplies one ActivitySample per tick. The live sampler reads the system;
/// tests use a fake.
protocol ActivitySampler {
    func sample() -> ActivitySample
}

/// Reads the frontmost app, its focused-window title, idle time and lock state.
/// Browser URLs arrive in M3; until then `url` and `tabTitle` stay nil.
final class LiveActivitySampler: ActivitySampler {
    private let monitors: [String: AppMonitor]

    init(monitors: [AppMonitor]) {
        self.monitors = Dictionary(uniqueKeysWithValues: monitors.map { ($0.bundleID, $0) })
    }

    /// Bundle ID -> extractor name, as written to the store's `enrichers` table
    /// and to `segments.enricher`.
    static func enricherNames(for monitors: [AppMonitor]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: monitors.map { ($0.bundleID, $0.appDisplayName.lowercased()) })
    }

    func sample() -> ActivitySample {
        let app = NSWorkspace.shared.frontmostApplication
        let bundleID = app?.bundleIdentifier
        let pid = app?.processIdentifier
        var sample = ActivitySample(time: Int64(Date().timeIntervalSince1970),
                                    bundleID: bundleID,
                                    windowTitle: pid.flatMap(Self.focusedWindowTitle(pid:)))
        sample.idleSeconds = Self.idleSeconds()
        sample.isLocked = Self.isSessionLocked()
        // Extractors run for the frontmost app only.
        if let bundleID, let pid, let monitor = monitors[bundleID] {
            sample.enricherName = monitor.appDisplayName.lowercased()
            sample.extractedTitle = monitor.currentTitle(for: pid)
        }
        return sample
    }

    /// Bounds this function's two AX reads so a hung app cannot stall a tick past the
    /// 10 s gap rule. The global timeout set at launch covers the extractors.
    private static let axTimeout: Float = 0.5

    /// Nil without the Accessibility grant: AX calls then fail and the app and
    /// idle capture continue without titles.
    static func focusedWindowTitle(pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, axTimeout)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window else { return nil }
        let windowElement = window as! AXUIElement
        AXUIElementSetMessagingTimeout(windowElement, axTimeout)
        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(windowElement, kAXTitleAttribute as CFString, &title) == .success,
              let text = title as? String, !text.isEmpty else { return nil }
        return text
    }

    static func idleSeconds() -> Int64 {
        let anyInput = CGEventType(rawValue: ~0)!
        return Int64(CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput))
    }

    /// True when the screen is locked or another user has the console.
    static func isSessionLocked() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        let locked = session["CGSSessionScreenIsLocked"] as? Bool ?? false
        let onConsole = session["kCGSSessionOnConsoleKey"] as? Bool ?? true
        return locked || !onConsole
    }
}
