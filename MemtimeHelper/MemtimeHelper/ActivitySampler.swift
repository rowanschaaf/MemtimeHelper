import AppKit
import ApplicationServices
import CoreGraphics

/// Supplies one ActivitySample per tick. The live sampler reads the system;
/// tests use a fake.
protocol ActivitySampler {
    func sample() -> ActivitySample
}

/// Reads the frontmost app, its focused-window title, idle time and lock state.
/// For Edge it also reads the active tab's URL and title (never for a private
/// window, and never for Safari).
final class LiveActivitySampler: ActivitySampler {
    private let monitors: [String: AppMonitor]
    private let tabReader: BrowserTabReading

    @MainActor
    init(monitors: [AppMonitor], tabReader: BrowserTabReading? = nil) {
        self.monitors = Dictionary(uniqueKeysWithValues: monitors.map { ($0.bundleID, $0) })
        self.tabReader = tabReader ?? BrowserTabReader.live()
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
        // CaptureEngine is @MainActor and calls sample() on the main thread.
        let tab = bundleID.map { id in MainActor.assumeIsolated { tabReader.activeTab(bundleID: id) } }
        Self.applyBrowserPrivacy(&sample, tab: tab ?? .unavailable)
        return sample
    }

    /// Window-title markers of a private window. English only: a localised
    /// browser may label its private windows differently.
    static let privateWindowMarkers = ["(InPrivate)", "(Incognito)"]

    /// Browser privacy rules. Edge records URL and tab title for a normal window only;
    /// a private window records nothing. In any app, a window title carrying a private
    /// marker is never kept and marks the sample private. The one exception is a normal
    /// Edge tab: its AX title lags one tick at window switches, so only the title is cleared.
    /// Safari records no titles at all.
    static func applyBrowserPrivacy(_ sample: inout ActivitySample, tab: BrowserTabResult) {
        if sample.bundleID == EdgeTab.bundleID {
            switch tab {
            case .tab(let found):
                sample.url = found.url
                sample.tabTitle = found.title
            case .privateWindow:
                sample.isPrivateWindow = true
            case .unavailable:
                break
            }
        } else if sample.bundleID == SegmentBuilder.safariBundleID {
            sample.windowTitle = nil
            sample.url = nil
            sample.tabTitle = nil
        }
        if let title = sample.windowTitle, privateWindowMarkers.contains(where: title.contains) {
            sample.windowTitle = nil
            if sample.bundleID == EdgeTab.bundleID, case .tab = tab {} else { sample.isPrivateWindow = true }
        }
        if sample.isPrivateWindow {
            sample.windowTitle = nil
            sample.url = nil
            sample.tabTitle = nil
        }
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
