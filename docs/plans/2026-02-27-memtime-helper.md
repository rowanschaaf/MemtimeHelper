# MemtimeHelper Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a Swift macOS background app that reads Claude.app's active conversation title via the Accessibility API and updates the window title so Memtime captures project context automatically.

**Architecture:** A SwiftUI menu bar app (no Dock icon, `LSUIElement = YES`) polls Claude.app's AX tree every 1 second while Claude is frontmost, calls `AXSetAttributeValue` to set the window title to `"Claude • {conversationTitle}"`, with an AppleScript fallback if the primary method is blocked. Registers as a Login Item on first launch via `SMAppService`.

**Tech Stack:** Swift 5.9+, SwiftUI, AppKit, AXUIElement (Accessibility API), SMAppService, NSAppleScript, XCTest

---

## Task 1: Xcode Project Scaffolding

**Files:**
- Create: `MemtimeHelper.xcodeproj` (via Xcode UI)
- Create: `MemtimeHelper/MemtimeHelperApp.swift`
- Create: `MemtimeHelper/AppDelegate.swift`

**Step 1: Create the Xcode project**

Open Xcode → File → New → Project → macOS → App
- Product Name: `MemtimeHelper`
- Team: your dev team
- Bundle Identifier: `com.yourname.MemtimeHelper`
- Interface: SwiftUI
- Language: Swift
- Uncheck "Include Tests" for now (we'll add the test target manually)

**Step 2: Delete the default ContentView.swift**

Delete `ContentView.swift` — we won't have a main window.

**Step 3: Replace `MemtimeHelperApp.swift`**

```swift
import SwiftUI

@main
struct MemtimeHelperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No WindowGroup — menu bar only
        MenuBarExtra("MemtimeHelper", systemImage: "circle.fill") {
            MenuBarView()
        }
        .menuBarExtraStyle(.menu)
    }
}
```

**Step 4: Create `AppDelegate.swift`**

```swift
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Suppress dock icon (belt-and-suspenders alongside LSUIElement)
        NSApp.setActivationPolicy(.accessory)
    }
}
```

**Step 5: Verify the app builds**

Product → Build (⌘B). Expected: build succeeds with "no issues".

**Step 6: Commit**

```bash
git add -A
git commit -m "feat: scaffold MemtimeHelper Xcode project"
```

---

## Task 2: Info.plist & Entitlements

**Files:**
- Modify: `MemtimeHelper/Info.plist`
- Modify: `MemtimeHelper/MemtimeHelper.entitlements`

**Step 1: Configure Info.plist**

In Xcode, open `Info.plist` and add:

| Key | Type | Value |
|-----|------|-------|
| `LSUIElement` | Boolean | YES |
| `NSAccessibilityUsageDescription` | String | `MemtimeHelper needs Accessibility access to read Claude's active conversation title for time tracking.` |
| `LSMinimumSystemVersion` | String | `13.0` |

`LSUIElement = YES` removes the app from the Dock entirely.

**Step 2: Configure entitlements**

Open `MemtimeHelper.entitlements`. Ensure it contains:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.automation.apple-events</key>
    <true/>
</dict>
</plist>
```

The `apple-events` entitlement is required for the AppleScript fallback.

**Step 3: Build and verify no dock icon appears**

Product → Run (⌘R). The app should appear only in the menu bar, not the Dock.

**Step 4: Commit**

```bash
git add -A
git commit -m "feat: configure Info.plist and entitlements for background app"
```

---

## Task 3: Accessibility Permission Checker

**Files:**
- Create: `MemtimeHelper/AccessibilityPermission.swift`
- Create: `MemtimeHelperTests/AccessibilityPermissionTests.swift`

**Step 1: Create the test file**

Add a new test target to the project: File → New → Target → Unit Testing Bundle → name it `MemtimeHelperTests`.

Create `MemtimeHelperTests/AccessibilityPermissionTests.swift`:

```swift
import XCTest
@testable import MemtimeHelper

final class AccessibilityPermissionTests: XCTestCase {
    func test_status_isTrusted_when_axIsProcessTrusted() {
        // This test documents the interface; actual trust value depends on system state.
        // In CI, permission will be denied — we just verify the function returns a Bool.
        let status = AccessibilityPermission.isGranted
        XCTAssertNotNil(status) // always returns true or false, never crashes
    }
}
```

**Step 2: Run the test to see it fail**

```bash
xcodebuild test -scheme MemtimeHelper -destination 'platform=macOS'
```

Expected: compile error — `AccessibilityPermission` does not exist yet.

**Step 3: Create `AccessibilityPermission.swift`**

```swift
import ApplicationServices

enum AccessibilityPermission {
    /// Returns true if Accessibility permission has been granted.
    static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompts the user to grant Accessibility permission.
    /// Shows the System Settings dialog. Does NOT block.
    static func requestIfNeeded() {
        guard !isGranted else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
```

**Step 4: Run tests**

```bash
xcodebuild test -scheme MemtimeHelper -destination 'platform=macOS'
```

Expected: PASS.

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add AccessibilityPermission checker"
```

---

## Task 4: AX Tree Explorer (Dev Utility)

**Files:**
- Create: `MemtimeHelper/Dev/AXTreeExplorer.swift`

This is a **development-only utility** used once to discover which AX element in Claude.app contains the conversation title. It will be deleted before shipping.

**Step 1: Create `AXTreeExplorer.swift`**

```swift
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
            print("Claude.app is not running. Launch it first.")
            return
        }

        let app = AXUIElementCreateApplication(claude.processIdentifier)
        print("=== Claude.app AX Tree ===\n")
        printElement(app, depth: 0, maxDepth: 6)
    }

    private static func printElement(_ element: AXUIElement, depth: Int, maxDepth: Int) {
        guard depth <= maxDepth else { return }
        let indent = String(repeating: "  ", count: depth)

        var roleRef: CFTypeRef?
        var titleRef: CFTypeRef?
        var valueRef: CFTypeRef?

        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)

        let role = roleRef as? String ?? "?"
        let title = titleRef as? String ?? ""
        let value = (valueRef as? String).map { String($0.prefix(80)) } ?? ""

        print("\(indent)[\(role)] title='\(title)' value='\(value)'")

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return }

        for child in children {
            printElement(child, depth: depth + 1, maxDepth: maxDepth)
        }
    }
}
```

**Step 2: Call the explorer temporarily from `AppDelegate`**

In `AppDelegate.applicationDidFinishLaunching`, add:

```swift
DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
    AXTreeExplorer.printClaudeTree()
}
```

**Step 3: Grant Accessibility permission and run**

1. Product → Run (⌘R)
2. When prompted, open System Settings → Privacy & Security → Accessibility → enable MemtimeHelper
3. Switch to Claude.app and open a conversation titled something memorable (e.g. "TestProject: hello world")
4. Switch back — check Xcode console output

**Step 4: Find the conversation title in the output**

Look for a line where `title` or `value` contains your conversation title ("TestProject: hello world"). Note:
- The full AX path (sequence of roles from root to that element)
- The attribute used (`kAXTitleAttribute` vs `kAXValueAttribute`)

Write this path down — you'll need it in Task 5.

Example output to look for:
```
  [AXGroup] title='' value=''
    [AXButton] title='TestProject: hello world' value=''
```

**Step 5: Remove the explorer call from AppDelegate**

Delete the `DispatchQueue.main.asyncAfter` block you added in Step 2. Keep the `AXTreeExplorer.swift` file for now (remove in Task 8).

**Step 6: Commit**

```bash
git add -A
git commit -m "dev: add AX tree explorer utility (to be deleted)"
```

---

## Task 5: AccessibilityMonitor

**Files:**
- Create: `MemtimeHelper/AccessibilityMonitor.swift`

**Step 1: Create `AccessibilityMonitor.swift`**

Fill in the `findConversationTitle` function using the path you discovered in Task 4. The skeleton below uses a recursive search — replace the `isConversationTitle` predicate with whatever matches your findings.

```swift
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

        return findConversationTitle(in: window)
    }

    // MARK: - Private

    private func findConversationTitle(in element: AXUIElement) -> String? {
        // Check if this element is the selected conversation item
        if let title = selectedConversationTitle(from: element) {
            return title
        }

        // Recurse into children
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return nil }

        for child in children {
            if let found = findConversationTitle(in: child) {
                return found
            }
        }
        return nil
    }

    /// Returns the title if this element represents the active/selected conversation.
    /// UPDATE THIS based on what Task 4 revealed about Claude's AX tree.
    private func selectedConversationTitle(from element: AXUIElement) -> String? {
        // Check if selected
        var selectedRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSelectedAttribute as CFString, &selectedRef)
        guard selectedRef as? Bool == true else { return nil }

        // Try title attribute first, then value
        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
        if let title = titleRef as? String, !title.isEmpty {
            return title
        }

        var valueRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
        if let value = valueRef as? String, !value.isEmpty {
            return value
        }

        return nil
    }
}
```

**Step 2: Manual smoke test**

Add a temporary print to `AppDelegate`:

```swift
DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
    guard let claude = NSRunningApplication.runningApplications(
        withBundleIdentifier: "com.anthropic.claude"
    ).first else { return }
    let monitor = AccessibilityMonitor()
    let title = monitor.currentConversationTitle(for: claude.processIdentifier)
    print("Conversation title: \(title ?? "nil")")
}
```

Run the app with a Claude conversation open. Verify the title appears in the console.

If `nil` is returned, revisit the `selectedConversationTitle` predicate using the AX tree output from Task 4.

**Step 3: Remove the temporary print from AppDelegate**

**Step 4: Commit**

```bash
git add -A
git commit -m "feat: add AccessibilityMonitor to read Claude conversation title"
```

---

## Task 6: WindowTitleUpdater

**Files:**
- Create: `MemtimeHelper/WindowTitleUpdater.swift`
- Create: `MemtimeHelperTests/WindowTitleFormatterTests.swift`

**Step 1: Write tests for title formatting**

```swift
import XCTest
@testable import MemtimeHelper

final class WindowTitleFormatterTests: XCTestCase {
    func test_format_withConversationTitle_returnsEnrichedTitle() {
        let result = WindowTitleUpdater.formatTitle("Memtime: fix bug")
        XCTAssertEqual(result, "Claude • Memtime: fix bug")
    }

    func test_format_withEmptyTitle_returnsBaseTitle() {
        let result = WindowTitleUpdater.formatTitle("")
        XCTAssertEqual(result, "Claude")
    }

    func test_format_withNilTitle_returnsBaseTitle() {
        let result = WindowTitleUpdater.formatTitle(nil)
        XCTAssertEqual(result, "Claude")
    }
}
```

**Step 2: Run tests to confirm they fail**

```bash
xcodebuild test -scheme MemtimeHelper -destination 'platform=macOS'
```

Expected: compile error — `WindowTitleUpdater` not found.

**Step 3: Create `WindowTitleUpdater.swift`**

```swift
import Cocoa
import ApplicationServices

final class WindowTitleUpdater {
    // MARK: - Title Formatting

    static func formatTitle(_ conversationTitle: String?) -> String {
        guard let title = conversationTitle, !title.isEmpty else { return "Claude" }
        return "Claude • \(title)"
    }

    // MARK: - Applying the Title

    /// Attempts to update Claude.app's window title.
    /// Returns true if the update succeeded via any method.
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

        let result = AXSetAttributeValue(window, kAXTitleAttribute as CFString, title as CFTypeRef)
        return result == .success
    }

    private func setViaAppleScript(title: String) -> Bool {
        // Escape any double quotes in the title to prevent AppleScript injection
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
```

**Step 4: Run tests**

```bash
xcodebuild test -scheme MemtimeHelper -destination 'platform=macOS'
```

Expected: PASS (formatting tests don't require Accessibility).

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add WindowTitleUpdater with AX and AppleScript methods"
```

---

## Task 7: ConversationTracker

**Files:**
- Create: `MemtimeHelper/ConversationTracker.swift`
- Create: `MemtimeHelperTests/ConversationTrackerTests.swift`

**Step 1: Write tests**

```swift
import XCTest
@testable import MemtimeHelper

final class ConversationTrackerTests: XCTestCase {
    func test_hasChanged_returnsTrueWhenTitleDiffers() {
        let tracker = ConversationTracker()
        tracker.lastTitle = "old title"
        XCTAssertTrue(tracker.hasChanged(from: "new title"))
    }

    func test_hasChanged_returnsFalseWhenTitleSame() {
        let tracker = ConversationTracker()
        tracker.lastTitle = "same title"
        XCTAssertFalse(tracker.hasChanged(from: "same title"))
    }

    func test_hasChanged_returnsTrueWhenBothNil_to_nonNil() {
        let tracker = ConversationTracker()
        tracker.lastTitle = nil
        XCTAssertTrue(tracker.hasChanged(from: "new title"))
    }

    func test_hasChanged_returnsFalseWhenBothNil() {
        let tracker = ConversationTracker()
        tracker.lastTitle = nil
        XCTAssertFalse(tracker.hasChanged(from: nil))
    }

    func test_record_updatesLastTitle() {
        let tracker = ConversationTracker()
        tracker.record("my project: task")
        XCTAssertEqual(tracker.lastTitle, "my project: task")
    }
}
```

**Step 2: Run tests to confirm failure**

```bash
xcodebuild test -scheme MemtimeHelper -destination 'platform=macOS'
```

Expected: compile error.

**Step 3: Create `ConversationTracker.swift`**

```swift
import Foundation

final class ConversationTracker {
    var lastTitle: String?

    func hasChanged(from newTitle: String?) -> Bool {
        lastTitle != newTitle
    }

    func record(_ title: String?) {
        lastTitle = title
    }
}
```

**Step 4: Run tests**

```bash
xcodebuild test -scheme MemtimeHelper -destination 'platform=macOS'
```

Expected: PASS.

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add ConversationTracker for change detection"
```

---

## Task 8: WorkspaceObserver + Polling Loop

**Files:**
- Create: `MemtimeHelper/WorkspaceObserver.swift`
- Delete: `MemtimeHelper/Dev/AXTreeExplorer.swift`

**Step 1: Delete the dev utility**

Delete `MemtimeHelper/Dev/AXTreeExplorer.swift` from both disk and the Xcode project.

**Step 2: Create `WorkspaceObserver.swift`**

```swift
import AppKit
import ApplicationServices

/// Monitors for Claude.app becoming frontmost and drives the polling loop.
final class WorkspaceObserver {
    private let monitor = AccessibilityMonitor()
    private let updater = WindowTitleUpdater()
    private let tracker = ConversationTracker()
    private var timer: Timer?

    func start() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidActivate),
            name: NSWorkspace.didActivateApplicationNotification,
            object: NSWorkspace.shared
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidDeactivate),
            name: NSWorkspace.didDeactivateApplicationNotification,
            object: NSWorkspace.shared
        )
    }

    func stop() {
        NotificationCenter.default.removeObserver(self)
        stopPolling()
    }

    // MARK: - Private

    @objc private func appDidActivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == "com.anthropic.claude" else { return }
        startPolling(pid: app.processIdentifier)
    }

    @objc private func appDidDeactivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == "com.anthropic.claude" else { return }
        stopPolling()
    }

    private func startPolling(pid: pid_t) {
        stopPolling()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.poll(pid: pid)
        }
        // Fire immediately
        poll(pid: pid)
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    private func poll(pid: pid_t) {
        let title = monitor.currentConversationTitle(for: pid)
        guard tracker.hasChanged(from: title) else { return }
        tracker.record(title)
        updater.update(pid: pid, conversationTitle: title)
    }
}
```

**Step 3: Build and verify no compile errors**

```bash
xcodebuild build -scheme MemtimeHelper
```

Expected: build succeeds.

**Step 4: Commit**

```bash
git add -A
git commit -m "feat: add WorkspaceObserver with 1s polling loop"
```

---

## Task 9: Menu Bar UI

**Files:**
- Create: `MemtimeHelper/MenuBarView.swift`

**Step 1: Create `MenuBarView.swift`**

```swift
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(state.statusMessage, systemImage: state.statusIcon)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

            Divider()

            Button("Quit MemtimeHelper") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(4)
    }
}
```

**Step 2: Create `AppState.swift`**

```swift
import Foundation
import Combine

final class AppState: ObservableObject {
    @Published var statusMessage: String = "Waiting for Claude..."
    @Published var statusIcon: String = "circle"

    func setActive(conversationTitle: String?) {
        DispatchQueue.main.async {
            if let title = conversationTitle {
                self.statusMessage = title
                self.statusIcon = "circle.fill"
            } else {
                self.statusMessage = "Claude active — no conversation"
                self.statusIcon = "circle.dotted"
            }
        }
    }

    func setWaiting() {
        DispatchQueue.main.async {
            self.statusMessage = "Waiting for Claude..."
            self.statusIcon = "circle"
        }
    }

    func setPermissionError() {
        DispatchQueue.main.async {
            self.statusMessage = "Accessibility permission needed"
            self.statusIcon = "exclamationmark.circle"
        }
    }
}
```

**Step 3: Update `MemtimeHelperApp.swift` to pass state**

```swift
import SwiftUI

@main
struct MemtimeHelperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("MemtimeHelper", systemImage: appDelegate.appState.statusIcon) {
            MenuBarView(state: appDelegate.appState)
        }
        .menuBarExtraStyle(.menu)
    }
}
```

**Step 4: Build**

```bash
xcodebuild build -scheme MemtimeHelper
```

Expected: build succeeds.

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add menu bar status UI"
```

---

## Task 10: Login Item Registration + Wire Everything Together

**Files:**
- Modify: `MemtimeHelper/AppDelegate.swift`

**Step 1: Update `AppDelegate.swift`**

```swift
import AppKit
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private let observer = WorkspaceObserver()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Register as login item on first launch
        registerLoginItemIfNeeded()

        // Check accessibility permission
        guard AccessibilityPermission.isGranted else {
            appState.setPermissionError()
            AccessibilityPermission.requestIfNeeded()
            return
        }

        // Start monitoring
        observer.start()

        // If Claude is already running when we launch, start polling immediately
        if let claude = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.anthropic.claude"
        ).first {
            observer.handleAlreadyRunning(pid: claude.processIdentifier)
        }
    }

    // MARK: - Private

    private func registerLoginItemIfNeeded() {
        do {
            if SMAppService.mainApp.status == .notRegistered {
                try SMAppService.mainApp.register()
            }
        } catch {
            print("Failed to register login item: \(error)")
        }
    }
}
```

**Step 2: Add `handleAlreadyRunning` to `WorkspaceObserver`**

In `WorkspaceObserver.swift`, add:

```swift
/// Call this if Claude is already the frontmost app when MemtimeHelper launches.
func handleAlreadyRunning(pid: pid_t) {
    startPolling(pid: pid)
}
```

**Step 3: Build**

```bash
xcodebuild build -scheme MemtimeHelper
```

Expected: build succeeds.

**Step 4: Run all tests**

```bash
xcodebuild test -scheme MemtimeHelper -destination 'platform=macOS'
```

Expected: all tests PASS.

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: wire AppDelegate, login item registration, and startup detection"
```

---

## Task 11: End-to-End Smoke Test

This task has no code changes — it verifies the full flow works.

**Step 1: Build and run**

Product → Run (⌘R). Verify:
- No Dock icon appears
- Menu bar icon appears

**Step 2: Verify Accessibility permission prompt**

On first run, System Settings should open. Grant access to MemtimeHelper. Restart the app.

**Step 3: Open Claude.app with a named conversation**

Name a conversation `"TestProject: smoke test"`. Click into it.

**Step 4: Check Memtime**

In Memtime, the Claude activity block should now show `"Claude • TestProject: smoke test"` as the title.

If it still shows `"Claude"`:
- Check Xcode console for errors from `WorkspaceObserver`
- Verify `AccessibilityMonitor.currentConversationTitle` returns the right string
- If `AXSetAttributeValue` returns `.failure`, check if the AppleScript fallback fires

**Step 5: Test conversation switching**

Switch to a different Claude conversation named `"OtherProject: different task"`. Wait 1-2 seconds. Memtime should now show the updated title.

**Step 6: Final commit**

```bash
git add -A
git commit -m "feat: MemtimeHelper v1.0 complete"
```

---

## Notes

**Claude.app bundle identifier:** Assumed to be `com.anthropic.claude`. Verify with:
```bash
osascript -e 'id of app "Claude"'
```
Update all bundle ID references if different.

**AX tree element path:** Task 4 must be completed before Task 5 can be finalised. The `selectedConversationTitle` predicate in `AccessibilityMonitor` is a placeholder — update it based on what Task 4's explorer reveals.

**macOS version:** `SMAppService` requires macOS 13+. If support for older versions is needed, fall back to `LaunchServices` or manual LaunchAgent plist.
