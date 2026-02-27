#!/usr/bin/env swift
// Run with: swift explore-ax.swift
// Requires Accessibility permission granted to Terminal (or your shell).
// System Settings → Privacy & Security → Accessibility → enable Terminal/iTerm2.

import Cocoa
import ApplicationServices

let bundleID = "com.anthropic.claudefordesktop"

guard let claude = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
    print("❌ Claude.app is not running (bundle: \(bundleID)). Launch it and open a named conversation first.")
    exit(1)
}

guard AXIsProcessTrusted() else {
    print("❌ Accessibility permission not granted.")
    print("   Go to System Settings → Privacy & Security → Accessibility")
    print("   and enable Terminal (or whichever app you're running this from).")
    exit(1)
}

print("✅ Found Claude.app (PID: \(claude.processIdentifier))")
print("✅ Accessibility permission granted")
print("\n=== Claude.app AX Tree (maxDepth=7) ===\n")

func printElement(_ element: AXUIElement, depth: Int, maxDepth: Int) {
    guard depth <= maxDepth else { return }
    let indent = String(repeating: "  ", count: depth)

    var roleRef: CFTypeRef?
    var titleRef: CFTypeRef?
    var valueRef: CFTypeRef?
    var selectedRef: CFTypeRef?
    var focusedRef: CFTypeRef?

    AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
    AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
    AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
    AXUIElementCopyAttributeValue(element, kAXSelectedAttribute as CFString, &selectedRef)
    AXUIElementCopyAttributeValue(element, kAXFocusedAttribute as CFString, &focusedRef)

    let role = roleRef as? String ?? "?"
    let title = titleRef as? String ?? ""
    let value = (valueRef as? String).map { String($0.prefix(100)) } ?? ""
    let selected = selectedRef as? Bool == true ? " [SELECTED]" : ""
    let focused = focusedRef as? Bool == true ? " [FOCUSED]" : ""

    print("\(indent)[\(role)]\(selected)\(focused) title='\(title)' value='\(value)'")

    var childrenRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
          let children = childrenRef as? [AXUIElement] else { return }

    for child in children {
        printElement(child, depth: depth + 1, maxDepth: maxDepth)
    }
}

let app = AXUIElementCreateApplication(claude.processIdentifier)
printElement(app, depth: 0, maxDepth: 7)
print("\n=== End of AX Tree ===")
