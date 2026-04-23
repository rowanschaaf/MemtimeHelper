import Cocoa
import ApplicationServices
import os

private let logger = Logger(subsystem: "com.memtimehelper.MemtimeHelper", category: "OutlookMonitor")

final class OutlookMonitor: AppMonitor {
    let bundleID = "com.microsoft.Outlook"
    let appDisplayName = "Outlook"

    func currentTitle(for pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)

        // Outlook's kAXWindowsAttribute returns empty; use kAXFocusedWindowAttribute instead.
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &windowRef) == .success else {
            return nil
        }
        let window = windowRef as! AXUIElement

        // Look for the message header container (reading pane)
        if let context = readingPaneContext(in: window) {
            return context.formattedTitle
        }

        return nil
    }

    // MARK: - Reading Pane Extraction

    /// Finds the "Message header" group (id="HeaderMainContainer") and extracts subject + sender.
    private func readingPaneContext(in window: AXUIElement) -> OutlookContext? {
        guard let header = findElement(in: window, withID: "HeaderMainContainer", maxDepth: 12) else {
            return nil
        }

        let subject = extractSubject(from: header)
        let sender = extractSender(from: header)

        guard let subj = subject, !subj.isEmpty else { return nil }
        guard let send = sender, !send.isEmpty else {
            // Subject but no sender — still useful
            return .readingEmail(sender: "Unknown", subject: subj)
        }

        return .readingEmail(sender: send, subject: subj)
    }

    /// The subject is the first AXStaticText child of HeaderMainContainer.
    private func extractSubject(from header: AXUIElement) -> String? {
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(header, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return nil }

        for child in children {
            if attrString(child, kAXRoleAttribute as String) == "AXStaticText" {
                return attrString(child, kAXValueAttribute as String)
            }
        }
        return nil
    }

    /// The sender name is on the AXButton with id="messageHeaderPresenceView" (desc attribute).
    private func extractSender(from header: AXUIElement) -> String? {
        guard let presenceView = findElement(in: header, withID: "messageHeaderPresenceView", maxDepth: 4) else {
            return nil
        }
        return attrString(presenceView, kAXDescriptionAttribute as String)
    }

    // MARK: - AX Tree Search

    /// Recursively searches for an element with the given AXIdentifier.
    private func findElement(in element: AXUIElement, withID targetID: String, maxDepth: Int, depth: Int = 0) -> AXUIElement? {
        guard depth <= maxDepth else { return nil }

        if attrString(element, kAXIdentifierAttribute as String) == targetID {
            return element
        }

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return nil }

        for child in children {
            if let found = findElement(in: child, withID: targetID, maxDepth: maxDepth, depth: depth + 1) {
                return found
            }
        }
        return nil
    }

    // MARK: - Helpers

    private func attrString(_ element: AXUIElement, _ attr: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr as CFString, &ref) == .success else { return nil }
        return ref as? String
    }
}
