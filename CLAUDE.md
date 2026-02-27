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
  MemtimeHelperTests/       ← XCTest unit tests
docs/plans/                 ← Design doc and implementation plan
```

## Gotchas

**xcodegen workflow:** Never edit `MemtimeHelper.xcodeproj` directly. Edit `project.yml`, then run `xcodegen generate`. The `.xcodeproj` is regenerated from the spec.

**No sandboxing:** The app must NOT be sandboxed. Sandboxing blocks cross-process Accessibility API access (`AXUIElement`), which is the core mechanism. Do not add `com.apple.security.app-sandbox` to the entitlements.

**Accessibility permission:** Requires Privacy & Security → Accessibility permission. Without it, `AXIsProcessTrusted()` returns false and all AX calls silently fail — no errors, just `nil` results.

**CF ownership:** Use `takeUnretainedValue()` (not `takeRetainedValue()`) for `kAXTrustedCheckOptionPrompt` — it is a `+0` global constant.

**Bundle ID:** Claude.app bundle identifier is `com.anthropic.claudefordesktop` (NOT `com.anthropic.claude`). Stored as file-level `let claudeBundleID` in `WorkspaceObserver.swift`.

**Reactive menu bar icon:** `AppDelegate` conforms to `ObservableObject` and forwards `appState.objectWillChange` via Combine so `MenuBarExtra`'s `systemImage` updates reactively.

**AX tree discovery:** Claude's conversation title is exposed as an `AXButton` with the conversation name as its title, positioned immediately before the `AXButton` with title `"Preview"` in Claude's toolbar.

## Current State

Tasks 1–10 complete. Pending Task 11 (end-to-end smoke test — requires manual verification).

- ✅ Task 1: Xcode project scaffolded via xcodegen
- ✅ Task 2: Info.plist + entitlements configured
- ✅ Task 3: AccessibilityPermission checker + tests
- ✅ Task 4: AX tree explorer (deleted after use — bundle ID + tree structure confirmed)
- ✅ Task 5: AccessibilityMonitor — reads conversation title from Claude's AX tree
- ✅ Task 6: WindowTitleUpdater — sets Claude window title via AX then AppleScript fallback
- ✅ Task 7: ConversationTracker — change detection with debounce
- ✅ Task 8: WorkspaceObserver — NSWorkspace notifications + 1s polling loop
- ✅ Task 9: AppState + MenuBarView — reactive menu bar status UI
- ✅ Task 10: AppDelegate — full wiring, login item, permission guard
- ⏸ Task 11: End-to-end smoke test — run app, grant Accessibility, open named Claude conversation, verify Memtime captures "Claude • {title}"

Full plan: `docs/plans/2026-02-27-memtime-helper.md`
