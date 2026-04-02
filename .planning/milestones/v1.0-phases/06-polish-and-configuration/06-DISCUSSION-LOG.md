# Phase 6: Polish and Configuration - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-02
**Phase:** 06-polish-and-configuration
**Areas discussed:** Session indicator, Vim path config UI, Vim path persistence

---

## Session Indicator

| Option | Description | Selected |
|--------|-------------|----------|
| Swap SF Symbol | Switch to a different SF Symbol while editing and revert on session end. Simple, no animation APIs needed, clear visual distinction. | ✓ |
| Tinted icon | Keep the same SF Symbol but apply a color tint during active session. Requires non-template image mode. | |
| Dot badge | Keep the same icon but add a small colored dot indicator. More subtle — may be too easy to miss. | |

**User's choice:** Swap SF Symbol
**Notes:** Template mode preserved for both idle and active states.

### Follow-up: Menu dropdown state

| Option | Description | Selected |
|--------|-------------|----------|
| Icon swap only | The icon change is the sole indicator. Menu stays as-is. Keeps things minimal. | ✓ |
| Add status item | Add a "Session: Active" / "Session: Idle" line in the dropdown menu. | |

**User's choice:** Icon swap only
**Notes:** Consistent with Phase 1 D-06 minimal menu philosophy.

---

## Vim Path Config UI

| Option | Description | Selected |
|--------|-------------|----------|
| Menu item with file picker | Add "Set Vim Path..." in the menu dropdown. Opens NSOpenPanel. "Reset to Default" restores PATH resolution. | ✓ |
| Preferences window | Small NSWindow with text field and Browse button. More conventional but heavier for a single setting. | |
| defaults command only | No UI — power users set via `defaults write`. Not discoverable. | |

**User's choice:** Menu item with file picker
**Notes:** Menu preview showed vim path display item, Set Vim Path..., and Reset Vim Path items in the dropdown.

---

## Vim Path Persistence

| Option | Description | Selected |
|--------|-------------|----------|
| Validate on set, fallback on use | Verify path exists and is executable on set. If invalid at trigger time, fall back to PATH resolution silently. Menu shows warning. | ✓ |
| Validate on set, error on use | Verify on set. If invalid at trigger time, show alert and abort. No silent fallback. | |
| No validation | Store whatever the user picks. Existing vim-not-found alert handles failures. | |

**User's choice:** Validate on set, fallback on use
**Notes:** Menu shows "(custom path invalid)" when the stored path becomes invalid so the user is aware.

---

## Claude's Discretion

- Exact SF Symbol for active-session icon (within pencil/edit family)
- Menu item ordering and separator placement for vim path items
- Whether to create a new `VimPathConfigManager` or extend existing resolver
- NSOpenPanel configuration details

## Deferred Ideas

None — discussion stayed within phase scope
