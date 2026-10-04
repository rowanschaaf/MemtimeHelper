import Foundation

/// Protocol for app-specific accessibility monitors.
/// Each monitored application implements this to extract context from its AX tree.
protocol AppMonitor {
    /// The bundle identifier of the application this monitor handles.
    var bundleID: String { get }

    /// Human-readable application name for display purposes.
    var appDisplayName: String { get }

    /// True when the app, while frontmost, should always yield a title.
    /// Enables `TitleHealth` for this monitor. Set false where nil is a
    /// normal frontmost state, or the health signal raises false alerts.
    /// The alert text (AppState, AppDelegate) points at the Claude-only
    /// "Dump Claude AX Tree…" item. Generalise it before another app opts in.
    var expectsTitleWhenFrontmost: Bool { get }

    /// Reads the current context title from the app's AX tree.
    /// Returns a formatted title string, or nil if no useful context is available.
    func currentTitle(for pid: pid_t) -> String?
}
