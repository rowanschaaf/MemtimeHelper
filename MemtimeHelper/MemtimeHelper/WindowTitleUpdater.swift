import Cocoa
import ApplicationServices.HIServices

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
        return setViaAccessibility(pid: pid, title: newTitle)
            || setViaAppleScript(title: newTitle)
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
        // Escape double quotes to prevent AppleScript injection
        let safeTitle = title.replacingOccurrences(of: "\"", with: "'")
        let script = """
        tell application "System Events"
            tell process "Claude"
                set name of window 1 to "\(safeTitle)"
            end tell
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        return error == nil
    }
}
