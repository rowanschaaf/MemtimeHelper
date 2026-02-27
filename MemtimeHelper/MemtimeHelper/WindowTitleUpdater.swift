import Cocoa
import ApplicationServices
import os

private let logger = Logger(subsystem: "com.memtimehelper.MemtimeHelper", category: "WindowTitleUpdater")

final class WindowTitleUpdater {
    // MARK: - Title Formatting

    static func formatTitle(_ conversationTitle: String?) -> String {
        guard let title = conversationTitle, !title.isEmpty else { return "Claude" }
        return "Claude • \(title)"
    }

    // MARK: - Applying the Title

    /// Attempts to update Claude.app's window title.
    /// Tries Accessibility API first, falls back to AppleScript.
    @discardableResult
    func update(pid: pid_t, conversationTitle: String?) -> Bool {
        let newTitle = Self.formatTitle(conversationTitle)
        if setViaAccessibility(pid: pid, title: newTitle) { return true }
        if setViaAppleScript(title: newTitle) { return true }
        logger.warning("Failed to update Claude window title via both AX and AppleScript")
        return false
    }

    // MARK: - Private

    private func setViaAccessibility(pid: pid_t, title: String) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement],
              let window = windows.first else { return false }

        let result = AXUIElementSetAttributeValue(window, kAXTitleAttribute as CFString, title as CFTypeRef)
        return result == .success
    }

    private func setViaAppleScript(title: String) -> Bool {
        // Escape double quotes to prevent breaking out of the AppleScript string literal.
        // Conversation titles come from Claude's own AX tree (trusted source), but we
        // sanitise defensively since the title is interpolated into a script string.
        let safeTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "System Events"
            tell process "Claude"
                set name of window 1 to "\(safeTitle)"
            end tell
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error { logger.debug("AppleScript error: \(error)") }
        return error == nil
    }
}
