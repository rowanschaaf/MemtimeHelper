import Foundation

/// The active tab of the frontmost browser window.
struct BrowserTab: Equatable {
    let url: String
    let title: String?
}

/// What one read of the active Edge window found. A private window is kept
/// apart from "unknown" so the caller can drop every title for it.
enum BrowserTabResult: Equatable {
    case tab(BrowserTab)
    case privateWindow
    case unavailable
}

/// Reads the active Edge tab. A private (InPrivate) window gives no tab:
/// no browser records a private window's URL or tab title.
enum EdgeTab {
    static let bundleID = "com.microsoft.edgemac"

    /// The mode check and the URL read rely on `front window` resolving once to a
    /// window reference (Chromium returns `window id N`), so both see the same window.
    static let source = """
    with timeout of 1 second
    tell application id "\(bundleID)"
      if (count of windows) is 0 then return {"", "", ""}
      set w to front window
      if mode of w is not "normal" then return {mode of w, "", ""}
      return {mode of w, URL of active tab of w, title of active tab of w}
    end tell
    end timeout
    """

    /// Expects `{mode, URL, title}`. A normal window with a URL is a tab; any other
    /// non-empty mode is a private window; everything else is unavailable.
    static func parse(_ result: NSAppleEventDescriptor) -> BrowserTabResult {
        guard result.numberOfItems == 3, let mode = result.atIndex(1)?.stringValue,
              !mode.isEmpty else { return .unavailable }
        guard mode == "normal" else { return .privateWindow }
        guard let url = result.atIndex(2)?.stringValue, !url.isEmpty else { return .unavailable }
        let title = result.atIndex(3)?.stringValue
        return .tab(BrowserTab(url: url, title: (title?.isEmpty ?? true) ? nil : title))
    }
}
