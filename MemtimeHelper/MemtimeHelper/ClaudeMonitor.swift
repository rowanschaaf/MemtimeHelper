import Cocoa
import ApplicationServices
import os

private let logger = Logger(subsystem: "com.memtimehelper.MemtimeHelper", category: "ClaudeMonitor")

final class ClaudeMonitor: AppMonitor {
    let bundleID = "com.anthropic.claudefordesktop"
    let appDisplayName = "Claude"

    private var hasRequestedEnhancedAX = false

    func currentTitle(for pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)

        // Ask Chromium/Electron to expose its full accessibility tree. Without
        // this handshake, Claude only exposes a stub tree to background AX
        // clients. `AXEnhancedUserInterface` is the historical VoiceOver signal;
        // `AXManualAccessibility` is Chromium's opt-in. Both set defensively.
        if !hasRequestedEnhancedAX {
            AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            hasRequestedEnhancedAX = true
            logger.notice("Requested enhanced AX tree from Claude (pid=\(pid))")
        }

        // Prefer the focused window (richer tree) and fall back to iterating
        // all windows. Claude's AX tree is most populated when its window is
        // focused, but we don't want to gate strictly on that.
        var candidates: [AXUIElement] = []
        var focusedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &focusedRef) == .success,
           focusedRef != nil {
            candidates.append(focusedRef! as! AXUIElement)  // swiftlint:disable:this force_cast
        }
        var windowsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let windows = windowsRef as? [AXUIElement] {
            for w in windows where !candidates.contains(where: { CFEqual($0, w) }) {
                candidates.append(w)
            }
        }

        // The primary pane holds the conversation the user is looking at. Its
        // header has this shape (see docs/notes/claude-ax-tree.md for a sample
        // AX dump captured 2026-04-23):
        //
        //   AXGroup/AXLandmarkRegion desc="Primary pane"
        //     ...
        //       AXPopUpButton title="{project}"     ← project switcher
        //       AXStaticText  value="{title}"       ← current conversation title
        //       AXPopUpButton desc="Session actions"
        //
        // NOTE: `AXStaticText` appears visually nested under the popup, but at
        // the AX-API level it is a SIBLING — `AXPopUpButton` hides its children
        // from assistive tech until opened. We therefore walk to the popup's
        // parent and search there for the title.
        for window in candidates {
            guard let pane = findPrimaryPane(in: window, depth: 0) else { continue }
            guard let popup = firstProjectPopupButton(in: pane, depth: 0) else { continue }
            guard let title = firstStaticTextValueInParentSubtree(of: popup) else { continue }
            let project = attrString(popup, kAXTitleAttribute as String)
            return formatted(project: project, title: title)
        }
        return nil
    }

    // MARK: - Finders

    /// Walks the subtree to locate the "Primary pane" AXLandmarkRegion.
    private func findPrimaryPane(in element: AXUIElement, depth: Int) -> AXUIElement? {
        if depth > 25 { return nil }
        if attrString(element, kAXSubroleAttribute as String) == "AXLandmarkRegion",
           attrString(element, kAXDescriptionAttribute as String) == "Primary pane" {
            return element
        }
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return nil }
        for child in children {
            if let found = findPrimaryPane(in: child, depth: depth + 1) {
                return found
            }
        }
        return nil
    }

    /// The first AXPopUpButton with a non-empty title inside the primary pane
    /// is the project switcher for the current conversation. The adjacent
    /// "Session actions" popup only has `desc`, not `title`, so it's skipped.
    private func firstProjectPopupButton(in element: AXUIElement, depth: Int) -> AXUIElement? {
        if depth > 20 { return nil }
        if attrString(element, kAXRoleAttribute as String) == "AXPopUpButton",
           let title = attrString(element, kAXTitleAttribute as String),
           !title.isEmpty {
            return element
        }
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return nil }
        for child in children {
            if let found = firstProjectPopupButton(in: child, depth: depth + 1) {
                return found
            }
        }
        return nil
    }

    /// Walks up to the element's parent and returns the first AXStaticText value
    /// found in that parent's subtree. This sidesteps the fact that popup
    /// buttons hide their own children from AX.
    private func firstStaticTextValueInParentSubtree(of element: AXUIElement) -> String? {
        var parentRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parentRef) == .success,
              parentRef != nil else { return nil }
        let parent = parentRef! as! AXUIElement  // swiftlint:disable:this force_cast
        return firstStaticTextValue(in: parent, depth: 0)
    }

    /// Returns the value of the first AXStaticText descendant with a non-empty value.
    private func firstStaticTextValue(in element: AXUIElement, depth: Int) -> String? {
        if depth > 10 { return nil }
        if attrString(element, kAXRoleAttribute as String) == "AXStaticText",
           let value = attrString(element, kAXValueAttribute as String),
           !value.isEmpty {
            return value
        }
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return nil }
        for child in children {
            if let found = firstStaticTextValue(in: child, depth: depth + 1) {
                return found
            }
        }
        return nil
    }

    // MARK: - Formatting

    private func formatted(project: String?, title: String) -> String {
        guard let rawProject = project, !rawProject.isEmpty else { return title }
        // Strip path annotations like " · ~/Documents/..." or " · PatternNZ".
        let cleanProject: String
        if let dotIdx = rawProject.range(of: " · ") {
            cleanProject = String(rawProject[..<dotIdx.lowerBound])
        } else {
            cleanProject = rawProject
        }
        if cleanProject.isEmpty || cleanProject == title { return title }
        return "\(cleanProject): \(title)"
    }

    // MARK: - AX helpers

    private func attrString(_ element: AXUIElement, _ attr: String) -> String? {
        var r: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr as CFString, &r) == .success else { return nil }
        return r as? String
    }
}
