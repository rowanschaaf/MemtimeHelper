# Design: MemtimeHelper — Claude Window Title Daemon

**Date:** 2026-02-27
**Status:** Approved
**Language:** Swift
**Platform:** macOS

---

## Problem

Memtime captures time spent in Claude.app as `"Claude"` with no project context. Claude.app sets a static window title regardless of which conversation is active, so Memtime cannot differentiate between projects.

Memtime has no inbound API, so the fix must happen at the OS window title level.

---

## Solution

A Swift macOS background app (`MemtimeHelper.app`) that:

1. Monitors when Claude.app is the frontmost application
2. Reads the active conversation title from Claude.app's accessibility tree
3. Updates Claude.app's window title to `"Claude • {conversationTitle}"`
4. Memtime captures the enriched title; rules map it to the correct project

---

## Architecture

```
MemtimeHelper.app
├── AppDelegate            — app lifecycle, login item registration
├── AccessibilityMonitor   — reads active conversation title from Claude.app's AX tree
├── WindowTitleUpdater     — writes updated title back to Claude.app's window
└── ConversationTracker    — debounces changes, avoids redundant updates
```

### Core Loop

1. `NSWorkspace.didActivateApplicationNotification` fires when Claude.app becomes frontmost
2. Start a ~1s polling timer while Claude is active
3. Each tick: read conversation title → if changed, update window title
4. Stop polling when Claude is deactivated

---

## Accessibility Tree Reading

Claude.app is an Electron (Chromium) app. The conversation title is readable from the sidebar via:

```
AXApplication (Claude)
  └── AXWindow
        └── ... (Chromium web content)
              └── AXStaticText / AXHeading — active conversation title
```

The exact element path is determined empirically using Xcode's Accessibility Inspector during development. The monitor searches for the currently selected conversation item in the sidebar.

---

## Window Title Update

**Primary:** `AXSetAttributeValue(windowElement, kAXTitleAttribute, newTitle)`

**Fallback:** AppleScript via `NSAppleScript`:
```applescript
tell application "System Events"
  tell process "Claude"
    set name of window 1 to "Claude • ProjectName: description"
  end tell
end tell
```

The fallback is used if the primary approach is blocked by Claude.app.

---

## Window Title Format

```
Claude • {conversationTitle}
```

Example: `Claude • Memtime: accessibility daemon design`

If no conversation is active or the title is unavailable, the title is left unchanged (falls back to `"Claude"`).

---

## Naming Convention

Users name conversations with a project prefix:

```
ProjectName: description of work
```

Examples:
- `Memtime: accessibility daemon design`
- `PatternApp: fix login bug`
- `ClientX: weekly report prep`

Conversations without a project prefix (e.g. `"New conversation"`) fall through to Memtime's unassigned bucket — no regression from current behaviour.

---

## Memtime Rules

One rule per project, configured once in Memtime:

| Condition | Action |
|-----------|--------|
| Title contains `"Memtime"` | Assign to Memtime project |
| Title contains `"PatternApp"` | Assign to PatternApp project |
| Title contains `"ClientX"` | Assign to ClientX project |

---

## Permissions

- **Accessibility** — required, granted once in System Settings → Privacy & Security → Accessibility

---

## Installation

1. Build `MemtimeHelper.app` and copy to `/Applications`
2. Launch the app — it prompts for Accessibility permission on first run
3. App registers itself as a Login Item automatically on first launch
4. Runs silently in the background; a menu bar icon shows status:
   - Active (Claude running, title being updated)
   - Waiting (Claude not running)
   - Error (Accessibility permission not granted)

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Accessibility tree structure changes with Claude.app updates | Element search is by role/value, not hard-coded index path; robust to minor UI changes |
| `AXSetAttributeValue` blocked on Electron window | AppleScript fallback |
| Brief gap between conversation switch and title update | 1s polling interval keeps gap small; acceptable for time tracking granularity |
| Accessibility permission revoked | Menu bar icon shows error state; app prompts user to re-grant |
