# MemtimeHelper

Swift macOS background menu bar app (no Dock icon) that reads Claude.app's active conversation title via the macOS Accessibility API and updates Claude.app's window title to `"Claude • {conversationTitle}"` so Memtime captures project context automatically.

## Commands

```bash
# Build
cd MemtimeHelper && xcodebuild -scheme MemtimeHelper -destination 'platform=macOS' build

# Test
cd MemtimeHelper && xcodebuild test -scheme MemtimeHelper -destination 'platform=macOS'

# Regenerate .xcodeproj after adding/removing source files
cd MemtimeHelper && xcodegen generate

# Open in Xcode
open MemtimeHelper/MemtimeHelper.xcodeproj

# Verify Claude.app bundle ID
osascript -e 'id of app "Claude"'
```

## Architecture

```
MemtimeHelper/              ← Xcode project root
  project.yml               ← xcodegen spec — edit this, not the .xcodeproj directly
  MemtimeHelper/            ← App source
    MemtimeHelperApp.swift  ← @main, MenuBarExtra scene (no WindowGroup)
    AppDelegate.swift       ← Lifecycle, login item registration, starts WorkspaceObserver
    AccessibilityPermission.swift  ← AXIsProcessTrusted wrapper
    AccessibilityMonitor.swift     ← Reads conversation title from Claude's AX tree (Task 5)
    WindowTitleUpdater.swift       ← Sets Claude's window title via AX/AppleScript (Task 6)
    ConversationTracker.swift      ← Change detection / debounce (Task 7)
    WorkspaceObserver.swift        ← NSWorkspace notifications + 1s polling loop (Task 8)
    AppState.swift                 ← Observable status for menu bar (Task 9)
    MenuBarView.swift              ← Menu bar UI (Task 9)
    Dev/AXTreeExplorer.swift       ← DEV ONLY — delete before shipping (Task 8)
  MemtimeHelperTests/       ← XCTest unit tests
docs/plans/                 ← Design doc and implementation plan
```

## Gotchas

**xcodegen workflow:** Never edit `MemtimeHelper.xcodeproj` directly. Edit `project.yml`, then run `xcodegen generate`. The `.xcodeproj` is regenerated from the spec.

**No sandboxing:** The app must NOT be sandboxed. Sandboxing blocks cross-process Accessibility API access (`AXUIElement`), which is the core mechanism. Do not add `com.apple.security.app-sandbox` to the entitlements.

**Accessibility permission:** Requires Privacy & Security → Accessibility permission. Without it, `AXIsProcessTrusted()` returns false and all AX calls silently fail — no errors, just `nil` results.

**Dev utility:** `Dev/AXTreeExplorer.swift` and the `AppDelegate` call to `AXTreeExplorer.printClaudeTree()` are temporary. Both must be deleted in Task 8.

**CF ownership:** Use `takeUnretainedValue()` (not `takeRetainedValue()`) for `kAXTrustedCheckOptionPrompt` — it is a `+0` global constant.

## Current State

Implementation in progress (subagent-driven, Tasks 1–11).

- ✅ Task 1: Xcode project scaffolded via xcodegen
- ✅ Task 2: Info.plist + entitlements configured
- ✅ Task 3: AccessibilityPermission checker + tests
- ⏸ Task 4: AX tree explorer built — **waiting for user to run app, examine Claude.app's AX tree console output, and report which element contains the conversation title**
- ⬜ Tasks 5–11: pending Task 4 output

Full plan: `docs/plans/2026-02-27-memtime-helper.md`
