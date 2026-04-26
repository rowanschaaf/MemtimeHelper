# MemtimeHelper

A small macOS menu-bar app that makes [Memtime](https://memtime.com) usefully track time per **Claude.app conversation** and per **Microsoft Outlook email** — instead of lumping everything under one big "Claude" or "Outlook" block.

## Why this exists

Memtime tracks time per *application*. If you spend three hours in Claude Desktop across four different conversations, you get one three-hour `Claude` block. Same with Outlook — every reply in every thread looks identical in your timeline.

MemtimeHelper bridges the gap by reading the active conversation/email title via the macOS Accessibility API and writing it directly into Memtime's local SQLite database. When you switch conversations or threads, it closes the current Memtime tracking row and inserts a fresh one — so your timeline shows distinct, named segments per conversation.

**Before:**
```
09:00 ─┬─────────────────────────────────────┐
       │ Claude (2h 45min)                   │
11:45 ─┴─────────────────────────────────────┘
```

**After:**
```
09:00 ─┬─ Replace D365 with Attio (32min)
09:32 ─┼─ Continue CRM migration (48min)
10:20 ─┼─ Review content strategy (15min)
10:35 ─┼─ Fix Claude Code tracking (1h 10min)
11:45 ─┘
```

## How it works

1. A 1Hz polling loop reads the active conversation/email title from each monitored app's Accessibility (AX) tree.
2. When a new title is observed, it's written into Memtime's `TTracking` table by matching the most recent open row (`end IS NULL`) for the app's bundle ID.
3. When the title *changes* mid-session, the current row is closed and a new one inserted — atomically, in a `BEGIN IMMEDIATE` transaction so Memtime can't slip a row in between.
4. Nil reads (e.g., backgrounded apps with stub AX trees) deliberately *don't* overwrite — your last good title sticks.
5. A 1-hour recency filter ensures we never mutate Memtime's stale orphan rows from past crashes.

The Claude AX-tree anchor is the `AXPopUpButton desc="Session actions"` popup that appears once per real conversation pane. The conversation title is its preceding sibling `AXButton`.

## Requirements

- macOS 13+ (Ventura)
- [Memtime](https://memtime.com) installed (the app reads/writes its local SQLite DB at `~/Library/Application Support/memtime/user/core.db`)
- Xcode 15+ and [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Accessibility permission granted to MemtimeHelper (System Settings → Privacy & Security → Accessibility)

## Build & run

```bash
# Generate the .xcodeproj from project.yml
cd MemtimeHelper && xcodegen generate

# Build
xcodebuild -scheme MemtimeHelper -destination 'platform=macOS' build

# Or open in Xcode
open MemtimeHelper.xcodeproj
```

The first run will prompt for Accessibility permission. Without it, all AX reads return `nil` silently — nothing gets tracked.

## Project structure

```
MemtimeHelper/
  project.yml                ← xcodegen spec — edit this, NOT the .xcodeproj
  MemtimeHelper/
    MemtimeHelperApp.swift   ← @main entry point, MenuBarExtra scene
    AppDelegate.swift        ← Lifecycle, login item, starts WorkspaceObserver
    AccessibilityPermission.swift  ← AXIsProcessTrusted wrapper

    AppMonitor.swift         ← Protocol all monitored apps conform to
    ClaudeMonitor.swift      ← Reads conversation title from Claude.app
    OutlookMonitor.swift     ← Reads email subject from Outlook
    OutlookContext.swift     ← Outlook-specific helpers

    WorkspaceObserver.swift  ← NSWorkspace + 1s poll loop
    ConversationTracker.swift ← Per-app change detection
    WindowTitleUpdater.swift ← SQLite writer (UPDATE / split / atomic txn)
    AXTreeDumper.swift       ← Diagnostic — writes full AX tree to ~/Desktop

    AppState.swift           ← Observable status for menu bar
    MenuBarView.swift        ← Menu bar UI
docs/plans/                  ← Design + implementation notes
```

## Adding a new app to track

The architecture is per-app — each tracked app implements the [`AppMonitor`](MemtimeHelper/MemtimeHelper/AppMonitor.swift) protocol:

```swift
protocol AppMonitor {
    var bundleID: String { get }
    var appDisplayName: String { get }
    func currentTitle(for pid: pid_t) -> String?
}
```

Steps:

1. Use the included **Dump Claude AX Tree…** menu item as a model — adapt `AXTreeDumper` to your target bundle ID and run it to see the AX structure of the app you want to monitor.
2. Find a stable anchor (a unique `AXRole`/`AXSubrole`/`AXDescription` combo near the title you want).
3. Add a new `MyAppMonitor: AppMonitor` implementation.
4. Register it in [`AppDelegate`](MemtimeHelper/MemtimeHelper/AppDelegate.swift) where the monitor list is built.

## Gotchas

**No sandboxing.** The app is *not* sandboxed and must not be — sandboxing blocks cross-process Accessibility API access (`AXUIElement`), which is the entire mechanism. Don't add `com.apple.security.app-sandbox` to entitlements.

**xcodegen workflow.** Never edit `MemtimeHelper.xcodeproj` directly. Edit `project.yml`, then run `xcodegen generate`. The `.xcodeproj` is regenerated from the spec.

**CF ownership.** `kAXTrustedCheckOptionPrompt` is a `+0` global constant — use `takeUnretainedValue()`, not `takeRetainedValue()`.

**Bundle ID.** Claude.app's bundle identifier is `com.anthropic.claudefordesktop` (NOT `com.anthropic.claude`).

**Enhanced AX handshake.** Chromium/Electron apps (Claude Desktop is one) only expose a stub AX tree to background clients by default. We re-send `AXEnhancedUserInterface` and `AXManualAccessibility` on every poll because Claude collapses its tree under various conditions and one-shot prompts don't survive.

**Memtime's orphan rows.** Memtime's DB accumulates `end IS NULL` rows from past app crashes going back years. The updater filters every SQL statement with `start > now - 3600` so we never mutate ancient rows. Don't remove that filter.

**Race with Memtime.** Both this app and Memtime write to the same DB. Splits use `BEGIN IMMEDIATE` to acquire a write lock for the close+insert pair. Memtime can still open rows *between* our splits — that produces occasional zero-duration duplicate rows which the next split closes. They're benign.

## Limitations

- **Claude Desktop only** for now (Claude Code in the Web/CLI isn't covered).
- Only segments time when the conversation title *changes*. If you stay in one conversation for hours, that's still one block (correctly).
- Nothing is sent off-device. The app reads `~/Library/Application Support/memtime/user/core.db` and Claude/Outlook AX trees, period. No analytics, no network calls.

## License

MIT — see [LICENSE](LICENSE).

## Status

Built for personal use. Sharing in case it's useful to others. Issues and PRs welcome but support is best-effort.
