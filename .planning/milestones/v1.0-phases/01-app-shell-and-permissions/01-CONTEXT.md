# Phase 1: App Shell and Permissions - Context

**Gathered:** 2026-03-31
**Status:** Ready for planning

<domain>
## Phase Boundary

A runnable macOS menu bar daemon with no Dock icon, permission onboarding for Accessibility and Input Monitoring, re-poll-after-grant detection, and launch-at-login support. This phase produces the skeleton app that all subsequent phases build on.

</domain>

<decisions>
## Implementation Decisions

### Permission Onboarding Flow
- **D-01:** Show a modal alert dialog on first launch explaining what permissions are needed and why. Include a button to open System Settings directly.
- **D-02:** Handle permissions sequentially — one alert per permission. After the user grants the first (e.g., Accessibility), detect it, then show the alert for the second (Input Monitoring).
- **D-03:** After the initial alert, show permission status as menu items in the dropdown (e.g., "Accessibility: Not Granted"). Clicking a status item opens the relevant System Settings pane.
- **D-04:** When a permission is granted (detected via re-polling), show a brief macOS notification confirming it (e.g., "Accessibility permission granted").

### Menu Bar Presence
- **D-05:** Use an SF Symbol for the menu bar icon. Choose something appropriate like `pencil.and.outline` or `character.cursor.ibeam` — scales well, supports dark/light mode automatically.
- **D-06:** Dropdown menu contents for Phase 1: permission status items + "Launch at Login" toggle + Quit. Minimal — no About, no config until later phases.

### Launch at Login
- **D-07:** Launch at login is enabled by default on first run.
- **D-08:** The first-run permission alert mentions that AnyVim will launch at login and that this can be changed in the menu bar.
- **D-09:** A "Launch at Login" toggle in the dropdown menu lets the user enable/disable it at any time.

### Claude's Discretion
- Specific SF Symbol choice for the menu bar icon
- Re-poll interval for permission detection (a few seconds, per success criteria)
- Alert dialog copy and layout details
- Whether to use SMAppService (modern) or legacy LaunchAgent for login items

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Technology Stack
- `CLAUDE.md` §Technology Stack — Full stack decisions including AppKit NSStatusItem, CGEventTap, SwiftTerm, and deployment target (macOS 13+)

### Requirements
- `.planning/REQUIREMENTS.md` §Permissions (PERM-01, PERM-02, PERM-03) — Permission check and re-poll requirements
- `.planning/REQUIREMENTS.md` §Menu Bar (MENU-01, MENU-03, MENU-04) — Menu bar presence, Quit, and launch-at-login requirements

### Architecture Guidance
- `CLAUDE.md` §Recommended Stack > Menu Bar Integration — AppKit NSStatusItem over SwiftUI MenuBarExtra, with rationale
- `CLAUDE.md` §Required Entitlements and Info.plist Keys — Entitlements needed for permission requests
- `CLAUDE.md` §CGEvent tap code signing pitfall — Code signing identity affects TCC grants; relevant from Phase 1

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- None — greenfield project, no existing code

### Established Patterns
- None yet — Phase 1 establishes the patterns all subsequent phases follow

### Integration Points
- This phase creates the app entry point, NSStatusItem, and permission checking infrastructure that Phases 2-6 build on
- The permission re-poll mechanism will be reused in Phase 2 (CGEventTap health monitoring)

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches for macOS menu bar daemons.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 01-app-shell-and-permissions*
*Context gathered: 2026-03-31*
