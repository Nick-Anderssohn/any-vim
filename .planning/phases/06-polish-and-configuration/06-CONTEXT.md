# Phase 6: Polish and Configuration - Context

**Gathered:** 2026-04-02
**Status:** Ready for planning

<domain>
## Phase Boundary

Visual session indicator in the menu bar (icon swap during active vim session) and configurable vim binary path with menu-based UI. This phase does NOT add new editing capabilities, new hotkey options, or any features beyond MENU-02 and CONF-01.

</domain>

<decisions>
## Implementation Decisions

### Session Indicator (MENU-02)
- **D-01:** Swap the SF Symbol during an active vim session. Idle state uses `character.cursor.ibeam` (existing). Active state uses a different SF Symbol (e.g., `pencil.circle.fill` or `pencil.and.outline`). Both in template mode so they adapt to dark/light menu bar automatically.
- **D-02:** Icon swap is the sole visual indicator. No additional "Session: Active" menu item in the dropdown. Consistent with Phase 1 D-06 (minimal menu).
- **D-03:** Icon updates happen at the start and end of `handleHotkeyTrigger` — set active icon before `captureText`, restore idle icon after all cleanup completes (including abort paths).

### Vim Path Configuration (CONF-01)
- **D-04:** Add a "Set Vim Path..." menu item that opens an NSOpenPanel file picker. User selects a binary, path is stored in UserDefaults. A "Reset Vim Path" menu item restores PATH-based resolution.
- **D-05:** Menu shows the currently resolved vim path as a disabled info item (e.g., "Vim: /opt/homebrew/bin/vim"). Updates when custom path is set or reset.
- **D-06:** Validate on set — verify the selected file exists and is executable before saving. On each trigger, if the stored custom path is invalid, fall back to PATH resolution silently. Menu shows "(custom path invalid)" so the user knows.
- **D-07:** Custom path stored in UserDefaults under a key like `customVimPath`. When nil/empty, the existing `ShellVimPathResolver` PATH-based resolution is used. When set, the stored path takes precedence.

### Claude's Discretion
- Exact SF Symbol choice for the active-session icon (within the pencil/edit family)
- How to integrate the vim path display and picker into `MenuBarController.buildMenu()` (menu item ordering, separator placement)
- Whether to create a `VimPathConfigManager` class or add methods to existing `VimSessionManager`
- How `VimPathResolving` protocol adapts to check UserDefaults before PATH resolution
- NSOpenPanel configuration details (allowed file types, initial directory)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Technology Stack
- `CLAUDE.md` §Recommended Stack > Menu Bar Integration — AppKit NSStatusItem, SF Symbols, template mode
- `CLAUDE.md` §Recommended Stack > Terminal / Vim Hosting — Vim binary resolution context

### Requirements
- `.planning/REQUIREMENTS.md` §Menu Bar (MENU-02) — Menu bar icon animates or changes while vim session is active
- `.planning/REQUIREMENTS.md` §Configuration (CONF-01) — User can configure the path to the vim binary

### Prior Phase Context
- `.planning/phases/01-app-shell-and-permissions/01-CONTEXT.md` — D-05 (SF Symbol choice), D-06 (minimal menu structure)
- `.planning/phases/04-vim-session/04-CONTEXT.md` — D-08 (PATH-based vim resolution), VimPathResolving protocol
- `.planning/phases/05-edit-cycle-integration/05-CONTEXT.md` — D-07 (no visual feedback deferred to Phase 6), D-02 (isEditSessionActive guard)

### Existing Code (Critical)
- `Sources/AnyVim/AppDelegate.swift` — `statusItem` (NSStatusItem), `handleHotkeyTrigger()`, `isEditSessionActive` bool, `rebuildMenu()`
- `Sources/AnyVim/MenuBarController.swift` — `buildMenu()` constructs menu fresh each open, permission/hotkey status items pattern
- `Sources/AnyVim/VimSessionManager.swift` — `ShellVimPathResolver`, `VimPathResolving` protocol, `openVimSession(tempFileURL:)`
- `Sources/AnyVim/SystemProtocols.swift` — Protocol patterns for testability

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `statusItem.button.image` — Already set up with SF Symbol in template mode. Swapping image is a one-liner.
- `ShellVimPathResolver` implementing `VimPathResolving` — Protocol already exists for injection. Can extend or create a new resolver that checks UserDefaults first.
- `MenuBarController.buildMenu()` — Already follows a pattern of status items (permission, hotkey). Vim path display fits naturally as another status item.
- `isEditSessionActive` on AppDelegate — Already tracks session state. Icon swap hooks into the same entry/exit points.

### Established Patterns
- Manager classes owned by AppDelegate as instance properties
- `@MainActor` isolation for all managers and AppDelegate
- Protocol-based testability for system API interactions
- `buildMenu()` returns fresh NSMenu with live state each time
- UserDefaults for persistence (already used for `VimWindowFrame`)

### Integration Points
- `AppDelegate.handleHotkeyTrigger()` — Icon swap at start (before captureText) and end (after cleanup/abort)
- `MenuBarController.buildMenu()` — Add vim path display, "Set Vim Path...", and "Reset Vim Path" items
- `VimSessionManager.init()` — May need to accept a custom resolver or the resolver checks UserDefaults internally

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

*Phase: 06-polish-and-configuration*
*Context gathered: 2026-04-02*
