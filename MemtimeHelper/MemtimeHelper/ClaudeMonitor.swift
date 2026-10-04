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
        // Each conversation pane has exactly one anchor element; the launcher
        // home pane and the sidebar have none. `ClaudeTitle.isAnchor` holds the
        // anchor shapes per Claude version (see AXNode.swift and
        // ClaudeTitleTests). Run AXTreeDumper when the layout changes again.
        var anchors: [AXUIElement] = []
        collectAnchors(in: window, depth: 0, into: &anchors)
        if anchors.isEmpty { return nil }

        // With multiple conversation panes, prefer the one containing the
        // focused UI element — that's the pane the user is actively in.
        let chosen = pickPane(among: anchors, focusedElement: focusedElement(of: app))
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

    /// Collects every pane anchor (see `ClaudeTitle.isAnchor`).
    /// Each one marks one conversation pane.
    private func collectAnchors(in element: AXUIElement, depth: Int, into result: inout [AXUIElement]) {
        if depth > 30 { return }
        if ClaudeTitle.isAnchor(AXElementNode(element: element)) {
            result.append(element)
            return  // No need to descend further into an anchor.
        }
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return }
        for child in children {
            collectAnchors(in: child, depth: depth + 1, into: &result)
        }
    }

    /// Picks the anchor belonging to the pane the user is in.
    /// Falls back to the first one if no focused element or it's outside any pane.
    private func pickPane(among anchors: [AXUIElement], focusedElement: AXUIElement?) -> AXUIElement {
        guard anchors.count > 1, let focused = focusedElement else { return anchors[0] }

        // Walk up from the focused element. The first anchor below the current
        // ancestor wins. Panes are siblings, so the focused pane's region
        // matches before any shared container does.
        var node: AXUIElement? = focused
        var depth = 0
        while let current = node, depth < 30 {
            for anchor in anchors {
                if let anchorParent = parent(of: anchor), CFEqual(anchorParent, current) {
                    return anchor
                }
                if isAncestor(current, of: anchor, maxDepth: 20) {
                    return anchor
                }
            }
            node = parent(of: current)
            depth += 1
        }
        return anchors[0]
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

    /// Reads the conversation title for the pane marked by the given anchor.
    /// The anchor shape and title location change across Claude versions, so
    /// the logic lives in `ClaudeTitle` (covered by `ClaudeTitleTests`).
    private func conversationTitle(for anchor: AXUIElement) -> String? {
        ClaudeTitle.extract(fromAnchor: AXElementNode(element: anchor))
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
