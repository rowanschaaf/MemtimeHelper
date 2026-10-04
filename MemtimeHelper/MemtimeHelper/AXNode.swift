import ApplicationServices

/// Minimal abstraction over the Accessibility attributes the Claude title walk
/// needs. Live code uses `AXElementNode` (backed by a real `AXUIElement`);
/// tests use an in-memory fake so the walk can be exercised without a running
/// app. Keep this surface as small as the walk requires.
protocol AXNode {
    var role: String? { get }
    var title: String? { get }
    var desc: String? { get }
    var children: [AXNode] { get }
    var parent: AXNode? { get }
}

/// `AXNode` backed by a real `AXUIElement`.
struct AXElementNode: AXNode {
    let element: AXUIElement

    var role: String? { attr(kAXRoleAttribute as String) }
    var title: String? { attr(kAXTitleAttribute as String) }
    var desc: String? { attr(kAXDescriptionAttribute as String) }

    var children: [AXNode] {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &ref) == .success,
              let kids = ref as? [AXUIElement] else { return [] }
        return kids.map { AXElementNode(element: $0) }
    }

    var parent: AXNode? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &ref) == .success,
              ref != nil else { return nil }
        return AXElementNode(element: (ref as! AXUIElement))  // swiftlint:disable:this force_cast
    }

    private func attr(_ a: String) -> String? {
        var r: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, a as CFString, &r) == .success else { return nil }
        return r as? String
    }
}

/// Finds the anchor of each Claude conversation pane and extracts the
/// conversation title from it.
///
/// The anchor and the title location have changed across Claude versions:
///
///   - ≤ Apr 2026: anchor is `AXPopUpButton desc="Session actions"`. The title
///     is a titled `AXButton`, a direct sibling of the anchor.
///   - Jun 2026 (1.14271.0): same anchor. The title button moved into a
///     *sibling* group one level up: [title, toggles…, project popup] and
///     [Terminal, Diff, Preview, Session actions].
///   - Oct 2026 (2.19675.0): "Session actions" is gone. The title button has
///     no `title`; its `desc` is "{title}, rename session". That button is
///     the anchor, and the title comes from its own `desc`.
///
/// For the "Session actions" anchor, walk up from the anchor and, at each
/// ancestor, search its subtree for the first `AXButton` with a non-empty
/// title. Both climb and descent are depth-bounded so we never wander out of
/// the header into chat content or the sidebar.
///
/// Sidebar rows carry neither anchor. They have status-prefixed titles and
/// "More options for {title}" popups.
enum ClaudeTitle {
    private static let renameSuffix = ", rename session"

    static func isAnchor(_ node: AXNode) -> Bool {
        isRenameButton(node) || (node.role == "AXPopUpButton" && node.desc == "Session actions")
    }

    static func extract(fromAnchor anchor: AXNode, maxClimb: Int = 4, maxDescend: Int = 6) -> String? {
        if isRenameButton(anchor), let desc = anchor.desc {
            let title = String(desc.dropLast(renameSuffix.count))
            return title.isEmpty ? nil : title
        }

        var node: AXNode? = anchor.parent
        var climb = 0
        while let current = node, climb < maxClimb {
            if let title = firstButtonTitle(in: current, maxDepth: maxDescend) {
                return title
            }
            node = current.parent
            climb += 1
        }
        return nil
    }

    private static func isRenameButton(_ node: AXNode) -> Bool {
        node.role == "AXButton" && (node.desc?.hasSuffix(renameSuffix) ?? false)
    }

    private static func firstButtonTitle(in node: AXNode, maxDepth: Int) -> String? {
        if maxDepth < 0 { return nil }
        if node.role == "AXButton", let title = node.title, !title.isEmpty {
            return title
        }
        for child in node.children {
            if let title = firstButtonTitle(in: child, maxDepth: maxDepth - 1) {
                return title
            }
        }
        return nil
    }
}
