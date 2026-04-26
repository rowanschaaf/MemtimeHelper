import AppKit
import ApplicationServices
import os

private let logger = Logger(subsystem: "com.memtimehelper.MemtimeHelper", category: "AXTreeDumper")

/// One-off diagnostic tool: walks the full AX tree of a target app and writes
/// a human-readable dump to ~/Desktop. Used to pick stable anchors for the
/// conversation-title walker in `ClaudeMonitor`.
///
/// Triggered manually from the menu bar — not part of the polling loop.
enum AXTreeDumper {

    /// Dumps the AX tree for the given bundle ID. Returns the output file path,
    /// or nil if the app isn't running / dump failed.
    @discardableResult
    static func dump(bundleID: String) -> String? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            logger.error("\(bundleID, privacy: .public) is not running")
            return nil
        }

        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        // Re-send the enhanced-AX handshake every dump. Cheap and idempotent.
        AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)

        var output = "AX dump for \(bundleID) (pid \(pid)) at \(Date())\n"
        output += String(repeating: "=", count: 80) + "\n\n"

        // Enumerate windows explicitly so we can label them in the dump.
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            output += "(no windows attribute)\n"
            return write(output, bundleID: bundleID)
        }

        var focusedRef: CFTypeRef?
        let focusedWindow: AXUIElement? = (
            AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedRef) == .success
        ) ? (focusedRef as! AXUIElement?) : nil  // swiftlint:disable:this force_cast

        output += "Found \(windows.count) window(s)\n\n"

        for (idx, window) in windows.enumerated() {
            let isFocused = focusedWindow.map { CFEqual($0, window) } ?? false
            let title = string(window, kAXTitleAttribute as String) ?? "(no title)"
            output += String(repeating: "-", count: 80) + "\n"
            output += "Window \(idx)\(isFocused ? " [FOCUSED]" : ""): kAXTitle=\(title)\n"
            output += String(repeating: "-", count: 80) + "\n"
            walk(window, depth: 0, into: &output)
            output += "\n"
        }

        return write(output, bundleID: bundleID)
    }

    // MARK: - Walking

    private static func walk(_ element: AXUIElement, depth: Int, into output: inout String) {
        if depth > 30 {
            output += indent(depth) + "(depth limit)\n"
            return
        }

        let role = string(element, kAXRoleAttribute as String) ?? "?"
        let subrole = string(element, kAXSubroleAttribute as String)
        let title = string(element, kAXTitleAttribute as String)
        let desc = string(element, kAXDescriptionAttribute as String)
        let value = string(element, kAXValueAttribute as String)
        let identifier = string(element, kAXIdentifierAttribute as String)

        var line = indent(depth) + role
        if let subrole { line += "[\(subrole)]" }
        if let title, !title.isEmpty { line += " title=\(quote(title))" }
        if let desc, !desc.isEmpty { line += " desc=\(quote(desc))" }
        if let value, !value.isEmpty { line += " value=\(quote(value))" }
        if let identifier, !identifier.isEmpty { line += " id=\(quote(identifier))" }
        output += line + "\n"

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return }
        for child in children {
            walk(child, depth: depth + 1, into: &output)
        }
    }

    // MARK: - Helpers

    private static func string(_ element: AXUIElement, _ attr: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr as CFString, &ref) == .success else { return nil }
        return ref as? String
    }

    private static func indent(_ depth: Int) -> String {
        String(repeating: "  ", count: depth)
    }

    private static func quote(_ s: String) -> String {
        let truncated = s.count > 200 ? String(s.prefix(200)) + "…" : s
        let escaped = truncated.replacingOccurrences(of: "\"", with: "\\\"")
                               .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }

    private static func write(_ contents: String, bundleID: String) -> String? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime]
        let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "")
        let safeBundle = bundleID.replacingOccurrences(of: ".", with: "-")
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/ax-tree-\(safeBundle)-\(stamp).txt")

        do {
            try contents.write(to: path, atomically: true, encoding: .utf8)
            logger.notice("AX tree written to \(path.path, privacy: .public)")
            return path.path
        } catch {
            logger.error("Failed to write AX dump: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
