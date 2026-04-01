# Phase 1: App Shell and Permissions - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-31
**Phase:** 01-app-shell-and-permissions
**Areas discussed:** Permission onboarding, Menu bar presence, Launch at login UX

---

## Permission Onboarding

### Q1: How should the app present missing permissions on first launch?

| Option | Description | Selected |
|--------|-------------|----------|
| Alert dialog (Recommended) | A modal alert on first launch explaining what's needed, with a button to open System Settings directly. Non-intrusive after first run. | ✓ |
| Menu bar indicator only | No dialog. Menu bar icon changes and dropdown shows permission status with link to System Settings. | |
| Both | Alert on first launch AND persistent menu bar status indicator. | |

**User's choice:** Alert dialog
**Notes:** None

### Q2: After the initial alert, how should the app indicate permission status?

| Option | Description | Selected |
|--------|-------------|----------|
| Menu item shows status | A menu item like "Accessibility: Not Granted" in the dropdown. Clicking opens System Settings. | ✓ |
| Icon badge | Menu bar icon itself changes appearance until permissions are granted. | |
| You decide | Claude picks based on macOS conventions. | |

**User's choice:** Menu item shows status
**Notes:** None

### Q3: Should the app notify when a permission is granted?

| Option | Description | Selected |
|--------|-------------|----------|
| Silent update | Just update the menu item status quietly. | |
| Brief notification | Show a macOS notification so the user knows it worked. | ✓ |
| You decide | Claude picks what feels least intrusive. | |

**User's choice:** Brief notification
**Notes:** None

### Q4: Combined or separate alerts for the two permissions?

| Option | Description | Selected |
|--------|-------------|----------|
| Combined alert | One dialog listing both permissions, single "Open System Settings" button. | |
| Sequential alerts | Two separate alerts, one per permission. User grants one, app detects it, then shows the next. | ✓ |
| You decide | Claude picks simplest approach. | |

**User's choice:** Sequential alerts
**Notes:** None

---

## Menu Bar Presence

### Q1: What should the menu bar icon look like?

| Option | Description | Selected |
|--------|-------------|----------|
| SF Symbol (Recommended) | System SF Symbol like pencil.and.outline. Consistent with macOS, scales well. | ✓ |
| Custom icon | A custom-designed icon. More distinctive but requires design work. | |
| Text character | A simple text glyph like "V". Zero design effort but less polished. | |

**User's choice:** SF Symbol
**Notes:** None

### Q2: What should be in the dropdown menu for Phase 1?

| Option | Description | Selected |
|--------|-------------|----------|
| Minimal (Recommended) | Just permission status items + Quit. | ✓ |
| Include About | Permission status + About AnyVim + Quit. | |
| Include Launch at Login | Permission status + Launch at Login toggle + Quit. | |

**User's choice:** Minimal
**Notes:** User initially chose minimal, but follow-up revealed MENU-04 requires launch-at-login in Phase 1, so a toggle was added.

### Q3: Where should the launch-at-login toggle live?

| Option | Description | Selected |
|--------|-------------|----------|
| Add it to the menu | A "Launch at Login" toggle in the dropdown. One extra item, still minimal. | ✓ |
| First-run prompt only | Ask during onboarding, no persistent toggle. User disables via System Settings. | |
| You decide | Claude picks simplest approach for MENU-04. | |

**User's choice:** Add it to the menu
**Notes:** None

---

## Launch at Login UX

### Q1: Should launch-at-login default to on or off?

| Option | Description | Selected |
|--------|-------------|----------|
| Off by default (Recommended) | User explicitly enables via menu toggle. Respects least surprise. | |
| On by default | Enabled automatically on first launch. User can disable via toggle. | ✓ |

**User's choice:** On by default
**Notes:** User chose on-by-default despite the recommendation for off-by-default.

### Q2: Should the app tell the user it's been added to login items?

| Option | Description | Selected |
|--------|-------------|----------|
| Mention in first-run alert | Add a line to the permission alert about launch-at-login being enabled. Transparent. | ✓ |
| Silent | Just enable it. Toggle visible in menu if they want to change. | |
| You decide | Claude picks based on flow. | |

**User's choice:** Mention in first-run alert
**Notes:** None

---

## Claude's Discretion

- Specific SF Symbol choice for the menu bar icon
- Re-poll interval for permission detection
- Alert dialog copy and layout details
- Login item mechanism (SMAppService vs LaunchAgent)

## Deferred Ideas

None — discussion stayed within phase scope
