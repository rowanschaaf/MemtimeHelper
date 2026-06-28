# MemtimeHelper

Swift macOS menu-bar app (no Dock icon) that reads conversation/email titles from monitored apps via the macOS Accessibility API and writes them directly into Memtime's local SQLite database — so Memtime tracks time per *conversation* (Claude) or *thread* (Outlook), not per app.

User-facing overview lives in [README.md](README.md). This file is for working in the codebase.

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

# Inspect Memtime's DB (rows are unix-seconds timestamps)
sqlite3 "$HOME/Library/Application Support/memtime/user/core.db" \
  "SELECT id, title, datetime(start,'unixepoch','localtime'), datetime(end,'unixepoch','localtime') \
   FROM TTracking WHERE program='com.anthropic.claudefordesktop' ORDER BY start DESC LIMIT 10;"
```

## Architecture

```
MemtimeHelper/                    ← Xcode project root
  project.yml                     ← xcodegen spec — edit this, NOT the .xcodeproj
  MemtimeHelper/                  ← App source
    MemtimeHelperApp.swift        ← @main, MenuBarExtra scene
    AppDelegate.swift             ← Lifecycle, login item, starts WorkspaceObserver
    AccessibilityPermission.swift ← AXIsProcessTrusted wrapper

    AppMonitor.swift              ← Protocol all monitored apps conform to
    ClaudeMonitor.swift           ← Reads Claude conversation title from AX tree
    OutlookMonitor.swift          ← Reads Outlook email subject from AX tree
    OutlookContext.swift          ← Outlook-specific helpers

    WorkspaceObserver.swift       ← NSWorkspace notifications + 1s poll loop;
                                    decides UPDATE vs splitSegment per app
    ConversationTracker.swift     ← Per-app change detection (menu bar UX)
    WindowTitleUpdater.swift      ← SQLite writer; UPDATE / atomic split / recency filter

    AXTreeDumper.swift            ← Diagnostic; menu item dumps full AX tree to ~/Desktop

    AppState.swift                ← Observable status for menu bar
    MenuBarView.swift             ← Menu bar UI
  MemtimeHelperTests/             ← XCTest unit tests
docs/plans/                       ← Design + implementation notes
```

Data flow: every 1s, `WorkspaceObserver` polls each `AppMonitor.currentTitle(for:)`. If non-nil, it either `update`s the open `TTracking` row's title or — when the title differs from the last write — calls `splitSegment` to atomically close the open row and insert a fresh one with the new title.

## Gotchas

**xcodegen workflow:** Never edit `MemtimeHelper.xcodeproj` directly. Edit `project.yml`, then run `xcodegen generate`. The `.xcodeproj` is regenerated from the spec.

**No sandboxing:** The app must NOT be sandboxed. Sandboxing blocks cross-process Accessibility API access (`AXUIElement`), which is the core mechanism. Do not add `com.apple.security.app-sandbox` to the entitlements.

**Accessibility permission:** Requires Privacy & Security → Accessibility permission. Without it, `AXIsProcessTrusted()` returns false and all AX calls silently fail — no errors, just `nil` results.

**CF ownership:** Use `takeUnretainedValue()` (not `takeRetainedValue()`) for `kAXTrustedCheckOptionPrompt` — it is a `+0` global constant.

**Bundle ID:** Claude.app bundle identifier is `com.anthropic.claudefordesktop` (NOT `com.anthropic.claude`).

**Enhanced AX every poll:** `ClaudeMonitor` re-sends `AXEnhancedUserInterface` and `AXManualAccessibility` on the application AX element on every call. Setting these once per pid (the previous approach) routinely produced stub trees and persistent nil reads when Claude backgrounded or window state churned. Don't reintroduce a one-shot guard.

**Don't write on nil:** `WorkspaceObserver` skips DB writes when a monitor returns nil. A nil read is almost always a transient AX hiccup (backgrounded window, mid-transition). Writing the bare app name as fallback overwrites the last good title and segments cleanly into garbage.

**Recency filter on every SQL:** Memtime's DB accumulates `end IS NULL` orphans from past crashes going back years. Every statement in `WindowTitleUpdater` filters open rows to `start > now - 3600`. Without this, polls silently mutate ancient rows. Do not remove.

**Atomic split + no phantom inserts:** `splitSegment` wraps close+insert in `BEGIN IMMEDIATE`. If the close affected zero rows (Memtime hasn't opened a recent row for this app), the insert is skipped — we never materialise tracking rows Memtime didn't authorise.

**AX anchor for Claude:** The `AXPopUpButton desc="Session actions"` popup is the unique per-pane anchor — one per real conversation pane. The launcher home pane lacks it, so panes without a conversation are correctly ignored. With multiple panes, the one containing `kAXFocusedUIElementAttribute` wins (`pickPane`). The launcher/sidebar session list also has many `AXButton title=…` entries, but those live under `AXLandmarkComplementary desc="Sidebar"`, not beside a "Session actions" popup, so the anchor naturally excludes them.

**Claude title walk — climb, don't assume siblings:** The conversation title is an `AXButton` (non-empty title) in the pane header, but its position *relative to the anchor changes between Claude versions* and has broken tracking once already:
- ≤ Apr 2026: a direct sibling of the popup — `[AXPopUpButton title="{project}", AXButton title="{conversation}", AXPopUpButton desc="Session actions"]` under one AXGroup.
- 1.14271.0 (Jun 2026): the header split into two sibling groups — `[AXButton title="{conversation}", …toggles, AXPopUpButton title="{project}"]` and `[Terminal, Diff, Preview, AXPopUpButton desc="Session actions"]`. The title is no longer a sibling of the popup, which made the old preceding-sibling logic return nil → Memtime logged bare "Claude" for ~11 days.

So `ClaudeTitle.extract` (in `AXNode.swift`) walks *up* from the anchor and, at each ancestor, searches the subtree for the first titled `AXButton` (both climb and descent depth-bounded to stay inside the header). This survives both layouts. It's pure and unit-tested via the `AXNode` protocol — see `ClaudeTitleTests`; add a case there when the tree shifts again. If it breaks once more, run `AXTreeDumper` (menu bar → "Dump Claude AX Tree…", writes to ~/Desktop), diff against the dumps, and widen the walk rather than re-pinning to a fixed sibling position.

**Reactive menu bar icon:** `AppDelegate` conforms to `ObservableObject` and forwards `appState.objectWillChange` via Combine so `MenuBarExtra`'s `systemImage` updates reactively.

## Status

Working end-to-end. Tracks Claude conversations and Outlook threads with per-segment time blocks in Memtime.

Plans: [docs/plans/2026-02-27-memtime-helper.md](docs/plans/2026-02-27-memtime-helper.md)
