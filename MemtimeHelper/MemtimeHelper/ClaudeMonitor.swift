import Cocoa
import ApplicationServices
import os

private let logger = Logger(subsystem: "com.memtimehelper.MemtimeHelper", category: "ClaudeMonitor")

final class ClaudeMonitor: AppMonitor {
    let bundleID = "com.anthropic.claudefordesktop"
    let appDisplayName = "Claude"

    func currentTitle(for pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)

        // Re-send the Chromium/Electron enhanced-AX handshake every call.
        // It's idempotent and cheap, and avoids the failure mode where Claude
        // collapses its AX tree (e.g. when backgrounded or after window churn)
        // and never re-enriches because we only set the flag once per pid.
        AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)

        guard let window = primaryWindow(of: app) else { return nil }

        // Claude tiles conversations as panes within ONE OS-level window.
        // Each conversation pane has this exact shape (see
        // ax-tree-com-anthropic-claudefordesktop-20260426T224551.txt for a
        // full dump captured 2026-04-26):
        //
        //   AXGroup
        //     AXPopUpButton title="{project}"      ← project / folder
        //     AXButton      title="{conversation}" ← THE TITLE
        //     AXPopUpButton desc="Session actions"
        //
        // The "Session actions" popup is the most reliable anchor — it only
        // appears once per real conversation pane. The launcher home (which
        // also lives under an AXLandmarkRegion) doesn't have it, so panes
        // without a conversation are correctly ignored.
        var sessionActionsPopups: [AXUIElement] = []
        collectSessionActionPopups(in: window, depth: 0, into: &sessionActionsPopups)
        if sessionActionsPopups.isEmpty { return nil }

        // With multiple conversation panes, prefer the one containing the
        // focused UI element — that's the pane the user is actively in.
        let chosen = pickPane(among: sessionActionsPopups, focusedElement: focusedElement(of: app))
        return conversationTitle(for: chosen)
    }

    // MARK: - Window selection

    private func primaryWindow(of app: AXUIElement) -> AXUIElement? {
        var ref: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &ref) == .success,
           ref != nil {
            return (ref as! AXUIElement)  // swiftlint:disable:this force_cast
        }
        var windowsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let windows = windowsRef as? [AXUIElement], let first = windows.first {
            return first
        }
        return nil
    }

    private func focusedElement(of app: AXUIElement) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &ref) == .success,
              ref != nil else { return nil }
        return (ref as! AXUIElement)  // swiftlint:disable:this force_cast
    }

    // MARK: - Walking

    /// Collects every `AXPopUpButton` whose description is "Session actions".
    /// Each one anchors one conversation pane.
    private func collectSessionActionPopups(in element: AXUIElement, depth: Int, into result: inout [AXUIElement]) {
        if depth > 30 { return }
        if attrString(element, kAXRoleAttribute as String) == "AXPopUpButton",
           attrString(element, kAXDescriptionAttribute as String) == "Session actions" {
            result.append(element)
            return  // No need to descend further into a popup.
        }
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return }
        for child in children {
            collectSessionActionPopups(in: child, depth: depth + 1, into: &result)
        }
    }

    /// Picks the session-actions popup belonging to the pane the user is in.
    /// Falls back to the first one if no focused element or it's outside any pane.
    private func pickPane(among popups: [AXUIElement], focusedElement: AXUIElement?) -> AXUIElement {
        guard popups.count > 1, let focused = focusedElement else { return popups[0] }

        // Walk up from the focused element. The first session-actions popup
        // that shares an ancestor (specifically, the immediate parent group of
        // the title triple) wins.
        var node: AXUIElement? = focused
        var depth = 0
        while let current = node, depth < 30 {
            for popup in popups {
                if let popupParent = parent(of: popup), CFEqual(popupParent, current) {
                    return popup
                }
                if isAncestor(current, of: popup, maxDepth: 20) {
                    return popup
                }
            }
            node = parent(of: current)
            depth += 1
        }
        return popups[0]
    }

    private func isAncestor(_ candidate: AXUIElement, of element: AXUIElement, maxDepth: Int) -> Bool {
        var node: AXUIElement? = parent(of: element)
        var depth = 0
        while let current = node, depth < maxDepth {
            if CFEqual(current, candidate) { return true }
            node = parent(of: current)
            depth += 1
        }
        return false
    }

    // MARK: - Title extraction

    /// Reads the conversation title — the nearest preceding `AXButton` sibling
    /// of the "Session actions" popup, with a non-empty title.
    private func conversationTitle(for sessionActionsPopup: AXUIElement) -> String? {
        guard let parent = parent(of: sessionActionsPopup) else { return nil }
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement],
              let idx = children.firstIndex(where: { CFEqual($0, sessionActionsPopup) }),
              idx > 0 else { return nil }

        for i in stride(from: idx - 1, through: 0, by: -1) {
            if attrString(children[i], kAXRoleAttribute as String) == "AXButton",
               let t = attrString(children[i], kAXTitleAttribute as String), !t.isEmpty {
                return t
            }
        }
        return nil
    }

    // MARK: - AX helpers

    private func parent(of element: AXUIElement) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &ref) == .success,
              ref != nil else { return nil }
        return (ref as! AXUIElement)  // swiftlint:disable:this force_cast
    }

    private func attrString(_ element: AXUIElement, _ attr: String) -> String? {
        var r: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr as CFString, &r) == .success else { return nil }
        return r as? String
    }
}
