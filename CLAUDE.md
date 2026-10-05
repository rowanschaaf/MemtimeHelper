# MemtimeHelper

Swift macOS menu-bar app (no Dock icon) that reads conversation/email titles from monitored apps via the macOS Accessibility API and writes them directly into Memtime's local SQLite database — so Memtime tracks time per *conversation* (Claude) or *thread* (Outlook), not per app.

User-facing overview lives in [README.md](README.md). This file is for working in the codebase.

## Commands

```bash
# Build
cd MemtimeHelper && xcodebuild -scheme MemtimeHelper -destination 'platform=macOS' build

# Test
cd MemtimeHelper && xcodebuild test -scheme MemtimeHelper -destination 'platform=macOS'

# One-time: sign with your own certificate (keeps the Accessibility grant across rebuilds)
cp MemtimeHelper/Signing.local.xcconfig.example MemtimeHelper/Signing.local.xcconfig

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
  Signing.xcconfig                ← Default (ad-hoc) signing; optional-includes
                                    Signing.local.xcconfig (gitignored)
  MemtimeHelper/                  ← App source
    MemtimeHelperApp.swift        ← @main, MenuBarExtra scene
    AppDelegate.swift             ← Lifecycle, login item, starts WorkspaceObserver and CaptureEngine
    AccessibilityPermission.swift ← AXIsProcessTrusted wrapper

    AppMonitor.swift              ← Protocol all monitored apps conform to
    ClaudeMonitor.swift           ← Reads Claude conversation title from AX tree
    OutlookMonitor.swift          ← Reads Outlook email subject from AX tree
    OutlookContext.swift          ← Outlook-specific helpers

    WorkspaceObserver.swift       ← NSWorkspace notifications + 1s poll loop;
                                    decides UPDATE vs splitSegment per app
    ConversationTracker.swift     ← Per-app change detection (menu bar UX)
    TitleHealth.swift             ← Silent-breakage detector (frontmost time
                                    without a title → alert)
    WindowTitleUpdater.swift      ← SQLite writer; UPDATE / atomic split / recency filter

    CaptureModels.swift           ← ActivitySample, CapturedSegment, SegmentType
    CaptureSchema.swift           ← Store schema text + migrations (must equal docs/capture-store-v1.sql)
    CaptureStore.swift            ← Owns ~/Library/Application Support/ActivityCapture/capture.db
    SingleWriterLock.swift        ← flock on capture.lock; one capture writer per store
    SegmentBuilder.swift          ← Pure segment rules 1–9 (see TimesheetHelper spec 2026-10-05)
    ActivitySampler.swift         ← Sampler protocol + live sampler (frontmost app, AX title, idle, lock)
    CaptureEngine.swift           ← 1 s timer, 30 s checkpoint, write queue, sleep/lock events

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

**Signing lives in xcconfig, not project.yml:** `Signing.xcconfig` (committed) defaults to ad-hoc signing and optional-includes `Signing.local.xcconfig` (gitignored) for a personal certificate. Do not add `CODE_SIGN_*` or `DEVELOPMENT_TEAM` to `project.yml` target settings. Target settings override the xcconfig, so they block the local file. The repo is public, so personal team IDs stay out of it.

**Pin the certificate by name, never by hash:** The Accessibility (TCC) grant follows the app's designated requirement, which matches on the certificate CN. A renewed certificate keeps the CN, so a name pin survives renewal. A SHA-1 hash pin does not: it broke the build once, when the pinned certificate expired. A build signed ad-hoc or by a different certificate loses the grant. Compare `codesign -d -r- <built.app>` with the installed app before you replace it.

**Accessibility permission:** Requires Privacy & Security → Accessibility permission. Without it, `AXIsProcessTrusted()` returns false and all AX calls silently fail — no errors, just `nil` results.

**CF ownership:** Use `takeUnretainedValue()` (not `takeRetainedValue()`) for `kAXTrustedCheckOptionPrompt` — it is a `+0` global constant.

**Bundle ID:** Claude.app bundle identifier is `com.anthropic.claudefordesktop` (NOT `com.anthropic.claude`).

**Enhanced AX every poll:** `ClaudeMonitor` re-sends `AXEnhancedUserInterface` and `AXManualAccessibility` on the application AX element on every call. Setting these once per pid (the previous approach) routinely produced stub trees and persistent nil reads when Claude backgrounded or window state churned. Don't reintroduce a one-shot guard.

**Don't write on nil:** `WorkspaceObserver` skips DB writes when a monitor returns nil. A nil read is almost always a transient AX hiccup (backgrounded window, mid-transition). Writing the bare app name as fallback overwrites the last good title and segments cleanly into garbage.

**Recency filter on every SQL:** Memtime's DB accumulates `end IS NULL` orphans from past crashes going back years. Every statement in `WindowTitleUpdater` filters open rows to `start > now - 3600`. Without this, polls silently mutate ancient rows. Do not remove.

**Atomic split + no phantom inserts:** `splitSegment` wraps close+insert in `BEGIN IMMEDIATE`. If the close affected zero rows (Memtime hasn't opened a recent row for this app), the insert is skipped — we never materialise tracking rows Memtime didn't authorise.

**AX anchor for Claude:** Each real conversation pane has exactly one anchor element. `ClaudeTitle.isAnchor` (in `AXNode.swift`) accepts both known shapes: `AXPopUpButton desc="Session actions"` (≤ 1.14271.0) and `AXButton desc="{title}, rename session"` (2.19675.0+). The launcher home pane has no anchor, so panes without a conversation are ignored. With multiple panes, the one containing `kAXFocusedUIElementAttribute` wins (`pickPane`). The sidebar session list has many `AXButton title="{status} {title}"` rows and `AXPopUpButton desc="More options for {title}"` popups. Neither shape is an anchor. The panes also have a "More options for" popup, so do not anchor on that string.

**Claude title — the layout changes between Claude versions.** It has broken tracking twice:
- ≤ Apr 2026: the title is a titled `AXButton`, a direct sibling of the anchor: `[AXPopUpButton title="{project}", AXButton title="{conversation}", AXPopUpButton desc="Session actions"]` under one AXGroup.
- 1.14271.0 (Jun 2026): the header split into two sibling groups: `[AXButton title="{conversation}", …toggles, AXPopUpButton title="{project}"]` and `[Terminal, Diff, Preview, AXPopUpButton desc="Session actions"]`. The old preceding-sibling logic returned nil, and Memtime logged bare "Claude" for ~11 days.
- 2.19675.0 (dumped 2026-10-04): "Session actions" is gone. The header is `[Remote Control, AXButton desc="{conversation}, rename session", AXPopUpButton desc="More options for {conversation}", AXPopUpButton title="{project}"]` and `[Terminal, Changes, Browser, View options, Close split view]`. The title button has no `title` attribute. Memtime logged bare "Claude" from 2026-09-07 to 2026-10-05 (46 h). The Claude version that first made this change is not known; no dump exists between June and October.

`ClaudeTitle.extract` handles both anchors. For the rename button, the title is its `desc` without the ", rename session" suffix. For "Session actions", it walks *up* from the anchor and, at each ancestor, searches the subtree for the first titled `AXButton` (climb and descent are depth-bounded to stay inside the header). It is pure and unit-tested via the `AXNode` protocol: see `ClaudeTitleTests`. Add a case there when the tree shifts again. If it breaks again, run `AXTreeDumper` (menu bar → "Dump Claude AX Tree…", writes to ~/Desktop), diff against the dumps, and add the new shape to `isAnchor`/`extract`. Do not commit dumps: they contain real session titles. Do not use the `AXWebArea` title as a source. It was "Claude" in every dump before 2.19675.0.

**Title health signal:** Title extraction broke silently twice, and both times nothing reported it for weeks. `TitleHealth` counts cumulative *frontmost* time with nil reads, and any successful read resets it. At 600 s, `WorkspaceObserver` logs an `.error` line and `AppDelegate` sets the menu bar triangle and posts a notification. The notification repeats at most once per calendar day while the app stays degraded. Background time never counts, because a backgrounded Claude returns stub trees. A poll gap adds 5 s at most, so wake from sleep does not count. Only monitors with `expectsTitleWhenFrontmost == true` take part (Claude yes, Outlook no: Calendar and compose views have no reading pane). To test it live, shorten the threshold with `defaults write com.memtimehelper.MemtimeHelper TitleHealthThresholdSeconds -int 20`, then relaunch. Delete the key afterwards.

**Capture store is a cross-language contract:** TimesheetHelper reads `capture.db` in native mode. `docs/capture-store-v1.sql` is the canonical schema and `CaptureSchemaTests` fails if `CaptureSchema.v1` drifts from it. Migrations only add tables or columns — never rename or drop — so an older TimesheetHelper keeps working. After a schema change, copy the file to TimesheetHelper's `tests/fixtures/`.

**Two writers run until cutover:** `WorkspaceObserver` + `WindowTitleUpdater` still write extracted titles into Memtime's `core.db` (so Memtime stays a fair baseline for the side-by-side run). `CaptureEngine` writes only to `capture.db`. Never point new code at `core.db`.

**Closed segments only:** `segments.end` is never NULL. The open segment lives in `open_segment` (checkpointed every 30 s) and is recovered at launch. Do not reintroduce Memtime-style open rows.

**Bounded carry-forward:** a nil extractor read keeps the last good title for at most 60 s (rule 4), then falls back to the window title with `enricher` NULL (rule 5). Lengthening the limit hides extractor outages — the September 2026 Claude outage ran 28 days unnoticed.

**Segments from one engine never overlap:** `SegmentBuilder` keeps a monotone start floor, so a backwards clock or an interrupt stamped before the last sample can never start a segment before the previous one ended. Do not reset the floor to an earlier time; that reintroduces double-counted time.

**Single writer to capture.db:** `capture.lock` beside `capture.db` is flock'd (`O_CLOEXEC`) for the process lifetime, and capture is skipped under XCTest (`XCTestConfigurationFilePath`). A second writer would recover the live checkpoint at start and duplicate billable time. The Memtime writer (`WorkspaceObserver`) is skipped under XCTest too, so the test host never writes `core.db`.

**Checkpoint discipline:** `CaptureStore.insert` deletes the checkpoint row. The engine therefore re-checkpoints the open segment after every successful insert, and never writes `checkpoint(nil)` while segments are queued in `pending`. Dropping either breaks the "a crash loses 30 s at most" bound.

**AX timeouts:** `AppDelegate` sets a global 1.0 s messaging timeout on the system-wide element at launch, so the Claude/Outlook extractors (which create their own elements) cannot hang on an unresponsive app. `LiveActivitySampler.focusedWindowTitle` sets 0.5 s on its own two reads. A hung app must not stall a 1 s tick past the 10 s gap rule, which would split the segment.

**App Nap opt-out:** `CaptureEngine.start()` holds a `ProcessInfo.beginActivity(.userInitiatedAllowingIdleSystemSleep)` token until `stop()`, and the timer has zero tolerance. A windowless menu-bar app is a prime App Nap candidate. Napped timers coalesce, gaps pass 10 s, and segments split. The option still lets the Mac sleep when idle.

**Reactive menu bar icon:** `AppDelegate` conforms to `ObservableObject` and forwards `appState.objectWillChange` via Combine so `MenuBarExtra`'s `systemImage` updates reactively.

## Status

Working end-to-end. Tracks Claude conversations and Outlook threads with per-segment time blocks in Memtime.

Plans: [docs/plans/2026-02-27-memtime-helper.md](docs/plans/2026-02-27-memtime-helper.md)
