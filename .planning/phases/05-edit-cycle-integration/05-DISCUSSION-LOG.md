# Phase 5: Edit Cycle Integration - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-01
**Phase:** 05-edit-cycle-integration
**Areas discussed:** Re-entrancy guard, Error handling on paste-back, Temp file cleanup timing, Edit cycle feedback

---

## Re-entrancy Guard

| Option | Description | Selected |
|--------|-------------|----------|
| Silent ignore | Do nothing — hotkey swallowed. Simplest, matches SC-4. | ✓ |
| Bring vim window to front | Re-focus existing vim panel. Helpful if user lost window. | |
| System beep | NSSound.beep() so user knows trigger was blocked. | |

**User's choice:** Silent ignore (Recommended)
**Notes:** None

### Follow-up: Guard Location

| Option | Description | Selected |
|--------|-------------|----------|
| AppDelegate flag | Simple `isEditSessionActive` bool on AppDelegate. Matches existing pattern. | ✓ |
| VimSessionManager state | VimSessionManager exposes `isActive` property. | |
| You decide | Claude picks during planning. | |

**User's choice:** AppDelegate flag (Recommended)
**Notes:** None

---

## Error Handling on Paste-back

| Option | Description | Selected |
|--------|-------------|----------|
| Treat as abort | Can't read file → don't paste. Restore clipboard, delete temp. Safest default. | ✓ |
| Show alert then abort | NSAlert explaining read failed, then abort. User knows something went wrong. | |
| You decide | Claude picks during planning. | |

**User's choice:** Treat as abort (Recommended)
**Notes:** Consistent with Phase 4's crash-as-abort philosophy (D-06).

---

## Temp File Cleanup Timing

| Option | Description | Selected |
|--------|-------------|----------|
| Immediately after cycle | Delete right after paste-back/abort. No lingering files. | ✓ |
| Brief delay for debugging | Delete after ~5s for dev inspection. Debug-only flag. | |
| You decide | Claude picks during planning. | |

**User's choice:** Immediately after cycle (Recommended)
**Notes:** None

### Follow-up: Cleanup Owner

| Option | Description | Selected |
|--------|-------------|----------|
| handleHotkeyTrigger | AppDelegate orchestrates full cycle, calls deleteTempFile as final step. | ✓ |
| AccessibilityBridge methods | Co-locate with clipboard logic inside restore/abort methods. | |
| You decide | Claude picks based on code fit. | |

**User's choice:** handleHotkeyTrigger (Recommended)
**Notes:** abortAndRestore already calls deleteTempFile internally — planner can centralize or keep idempotent.

---

## Edit Cycle Feedback

| Option | Description | Selected |
|--------|-------------|----------|
| No feedback | Text appearing in field IS the feedback. Keep invisible. Phase 6 adds icon. | ✓ |
| Console log only | Print to stdout for debugging (already exists from Phase 4). | |
| Brief notification | macOS notification on success/abort. Potentially annoying. | |

**User's choice:** No feedback (Recommended)
**Notes:** Phase 6 handles menu bar icon visual indicator for active sessions.

---

## Claude's Discretion

- Whether to centralize deleteTempFile in AppDelegate or keep idempotent in abortAndRestore
- Orchestration flow details in handleHotkeyTrigger
- Whether to keep or remove Phase 4 print() debug logging
- String encoding choice for reading edited temp file

## Deferred Ideas

None — discussion stayed within phase scope
