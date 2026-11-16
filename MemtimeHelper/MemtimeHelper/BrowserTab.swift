import Foundation

/// The active tab of the frontmost browser window.
struct BrowserTab: Equatable {
    let url: String
    let title: String?
}

/// Reads the active Edge tab. A private (InPrivate) window gives no tab:
/// no browser records a private window's URL or tab title.
enum EdgeTab {
    static let bundleID = "com.microsoft.edgemac"

    static let source = """
    with timeout of 1 second
    tell application id "\(bundleID)"
      if (count of windows) is 0 then return {"", "", ""}
      set w to front window
      return {mode of w, URL of active tab of w, title of active tab of w}
    end tell
    end timeout
    """

    /// Expects `{mode, URL, title}`. Anything other than a normal window with a URL is nil.
    static func parse(_ result: NSAppleEventDescriptor) -> BrowserTab? {
        guard result.numberOfItems == 3,
              result.atIndex(1)?.stringValue == "normal",
              let url = result.atIndex(2)?.stringValue, !url.isEmpty else { return nil }
        let title = result.atIndex(3)?.stringValue
        return BrowserTab(url: url, title: (title?.isEmpty ?? true) ? nil : title)
    }
}
