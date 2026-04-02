# Phase 3: Accessibility Bridge and Clipboard - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-01
**Phase:** 03-accessibility-bridge-and-clipboard
**Areas discussed:** Keystroke timing strategy, Clipboard preservation scope, Focus tracking approach, Error handling and edge cases

---

## Keystroke Timing Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Fixed delays | Start with conservative fixed delays (e.g., 100-150ms between Cmd+A and Cmd+C). Simple, predictable, easy to tune later. | ✓ |
| Pasteboard polling | After posting Cmd+C, poll NSPasteboard.changeCount in a tight loop with a timeout. More robust but adds complexity. | |
| You decide | Claude picks the approach. | |

**User's choice:** Fixed delays
**Notes:** None

| Option | Description | Selected |
|--------|-------------|----------|
| Hardcoded constants | Define as named constants in the source. Tune during Phase 3 testing. No user-facing config. | ✓ |
| Internal config | Store in UserDefaults or a plist so they can be tweaked without recompiling. | |
| You decide | Claude picks. | |

**User's choice:** Hardcoded constants
**Notes:** None

| Option | Description | Selected |
|--------|-------------|----------|
| Same delay | Use the same constant for both capture and paste-back sequences. | |
| Longer for paste-back | Use a longer delay for paste-back (e.g., 200ms) since the app needs to regain focus first. | ✓ |
| You decide | Claude picks. | |

**User's choice:** Longer for paste-back
**Notes:** STATE.md already flagged 200ms as community-reported value

| Option | Description | Selected |
|--------|-------------|----------|
| Single AccessibilityBridge | One class handles both capture and restore. Owns clipboard snapshot lifecycle. | ✓ |
| Split capture/restore | Separate TextCaptureManager and TextRestoreManager classes. | |
| You decide | Claude picks. | |

**User's choice:** Single AccessibilityBridge
**Notes:** Follows established manager-per-concern pattern

---

## Clipboard Preservation Scope

| Option | Description | Selected |
|--------|-------------|----------|
| All pasteboard items | Snapshot every NSPasteboardItem with all its types. Restore exactly after edit cycle. | ✓ |
| Plain text only | Only save/restore the string representation. Simpler but lossy. | |
| You decide | Claude picks. | |

**User's choice:** All pasteboard items
**Notes:** Zero surprise for users — images, RTF, custom types all preserved

| Option | Description | Selected |
|--------|-------------|----------|
| Short delay after paste | Wait ~100-200ms after Cmd+V before restoring clipboard. Ensures target app finished reading. | ✓ |
| Immediately after Cmd+V | Restore right after posting Cmd+V event. Faster but risks race condition. | |
| You decide | Claude picks. | |

**User's choice:** Short delay after paste
**Notes:** None

---

## Focus Tracking Approach

| Option | Description | Selected |
|--------|-------------|----------|
| NSWorkspace frontmost app | Use NSWorkspace.shared.frontmostApplication. Simple, reliable, well-documented. | ✓ |
| AXUIElement focused element | Query focused AXUIElement for exact element tracking. More precise but significantly more complex. | |
| You decide | Claude picks. | |

**User's choice:** NSWorkspace frontmost app
**Notes:** None

| Option | Description | Selected |
|--------|-------------|----------|
| Silently skip | If the app is gone, skip focus restoration and clipboard restore. | ✓ |
| Show a notification | Post a macOS notification warning the user. | |
| You decide | Claude picks. | |

**User's choice:** Silently skip
**Notes:** Expected behavior — the field no longer exists

---

## Error Handling and Edge Cases

| Option | Description | Selected |
|--------|-------------|----------|
| Best-effort, no detection | Run Cmd+A/Cmd+C regardless. If no text captured, open vim with empty file. | ✓ |
| Check AXRole first | Query focused AXUIElement's role before proceeding. Skip if not text field. | |
| You decide | Claude picks. | |

**User's choice:** Best-effort, no detection
**Notes:** Avoids fragile AXRole checking across apps (especially Electron/web)

| Option | Description | Selected |
|--------|-------------|----------|
| Check changeCount | Compare NSPasteboard.general.changeCount before/after Cmd+C to detect failure vs empty. | ✓ |
| Don't distinguish | Treat both cases the same — open vim with empty file. | |
| You decide | Claude picks. | |

**User's choice:** Check changeCount
**Notes:** Both cases still open vim — distinction is for internal debugging

| Option | Description | Selected |
|--------|-------------|----------|
| Still open vim | Open vim with empty file anyway. User intentionally triggered AnyVim. | ✓ |
| Abort silently | Don't open vim. Restore clipboard and do nothing. | |
| Abort with notification | Don't open vim. Show notification explaining capture failed. | |

**User's choice:** Still open vim
**Notes:** Low friction — user may want to compose new text

| Option | Description | Selected |
|--------|-------------|----------|
| NSTemporaryDirectory | UUID-based filename like 'anyvim-{uuid}.txt'. Auto-cleaned by macOS. | ✓ |
| ~/.local/share/any-vim/ | Dedicated app directory. Overkill for v1 where we delete after every cycle. | |
| You decide | Claude picks. | |

**User's choice:** NSTemporaryDirectory
**Notes:** None

---

## Claude's Discretion

- Protocol abstraction design for testability (wrapping CGEvent.post, NSPasteboard, NSWorkspace)
- Exact delay values within stated ranges
- Internal logging/debug output for capture success/failure
- How AccessibilityBridge communicates results back to caller

## Deferred Ideas

None — discussion stayed within phase scope
