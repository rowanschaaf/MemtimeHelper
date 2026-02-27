import Cocoa
import ApplicationServices

final class AccessibilityMonitor {
    /// Returns the active conversation title from Claude.app, or nil if unavailable.
    func currentConversationTitle(for pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)

        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement],
              let window = windows.first else { return nil }

        return findConversationTitle(in: window, depth: 0)
    }

    // MARK: - Private

    private func findConversationTitle(in element: AXUIElement, depth: Int) -> String? {
        guard depth <= 30 else { return nil }

        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? ""

        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
        let title = titleRef as? String ?? ""

        // Skip menu bar — we only care about window content
        if role == "AXMenuBar" { return nil }

        // If this is the "Preview" button, its previous sibling is the conversation title button
        if role == "AXButton" && title == "Preview" {
            if let conversationTitle = previousSiblingTitle(of: element) {
                return conversationTitle
            }
        }

        // Recurse into children
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return nil }

        for child in children {
            if let found = findConversationTitle(in: child, depth: depth + 1) {
                return found
            }
        }
        return nil
    }

    /// Returns the title of the AXButton immediately before the given element among its parent's children.
    private func previousSiblingTitle(of element: AXUIElement) -> String? {
        var parentRef: CFTypeRef?
        // Guard on .success ensures parentRef is non-nil and is a valid AXUIElement;
        // AXUIElement is a CF type so conditional cast always succeeds — use force-cast
        // behind the success guard, which is the safe and idiomatic pattern here.
        guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parentRef) == .success,
              parentRef != nil else { return nil }
        let parent = parentRef! as! AXUIElement // swiftlint:disable:this force_cast

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return nil }

        for (index, child) in children.enumerated() {
            guard index > 0, CFEqual(child, element) else { continue }

            let previous = children[index - 1]
            var prevRoleRef: CFTypeRef?
            var prevTitleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(previous, kAXRoleAttribute as CFString, &prevRoleRef)
            AXUIElementCopyAttributeValue(previous, kAXTitleAttribute as CFString, &prevTitleRef)

            guard prevRoleRef as? String == "AXButton",
                  let prevTitle = prevTitleRef as? String,
                  !prevTitle.isEmpty else { return nil }

            return prevTitle
        }
        return nil
    }
}
