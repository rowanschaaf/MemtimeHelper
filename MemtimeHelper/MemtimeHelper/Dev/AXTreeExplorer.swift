import Cocoa
import ApplicationServices

/// Dev utility — prints Claude.app's accessibility tree to the console.
/// Run once to find the element path for the active conversation title.
/// DELETE THIS FILE before shipping.
enum AXTreeExplorer {
    static func printClaudeTree() {
        guard let claude = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.anthropic.claude"
        ).first else {
            print("❌ Claude.app is not running. Launch it first, then re-run.")
            return
        }

        print("✅ Found Claude.app (PID: \(claude.processIdentifier))")
        let app = AXUIElementCreateApplication(claude.processIdentifier)
        print("\n=== Claude.app AX Tree (maxDepth=6) ===\n")
        printElement(app, depth: 0, maxDepth: 6)
        print("\n=== End of AX Tree ===")
    }

    private static func printElement(_ element: AXUIElement, depth: Int, maxDepth: Int) {
        guard depth <= maxDepth else { return }
        let indent = String(repeating: "  ", count: depth)

        var roleRef: CFTypeRef?
        var titleRef: CFTypeRef?
        var valueRef: CFTypeRef?
        var selectedRef: CFTypeRef?

        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
        AXUIElementCopyAttributeValue(element, kAXSelectedAttribute as CFString, &selectedRef)

        let role = roleRef as? String ?? "?"
        let title = titleRef as? String ?? ""
        let value = (valueRef as? String).map { String($0.prefix(80)) } ?? ""
        let selected = selectedRef as? Bool == true ? " [SELECTED]" : ""

        print("\(indent)[\(role)]\(selected) title='\(title)' value='\(value)'")

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return }

        for child in children {
            printElement(child, depth: depth + 1, maxDepth: maxDepth)
        }
    }
}
