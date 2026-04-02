# AnyVim

## What This Is

A macOS menu bar utility that lets you use vim to edit text in any text field across any application. Double-tap the Control key to open vim with the current text field's contents, edit freely, and :wq to send the edited text back to the original text field.

## Core Value

Seamless vim editing in any text input on macOS — the trigger-edit-return loop must feel instant and reliable.

## Requirements

### Validated

- [x] Menu bar app with status icon that runs in the background — Validated in Phase 1: App Shell and Permissions

### Active

- [x] System-wide double-tap Control key detection to trigger vim — Validated in Phase 2: Global Hotkey Detection
- [x] Grab existing text from the focused text field (Cmd+A, Cmd+C via Accessibility APIs) — Validated in Phase 3: Accessibility Bridge and Clipboard
- [x] Write grabbed text to a temporary file — Validated in Phase 3: Accessibility Bridge and Clipboard
- [x] Launch vim in a terminal window with the temp file — Validated in Phase 4: Vim Session
- [x] On :wq, read the edited temp file contents — Validated in Phase 4: Vim Session
- [x] Paste edited text back into the original text field (Cmd+A, Cmd+V via Accessibility APIs) — Validated in Phase 3: Accessibility Bridge and Clipboard
- [x] Clean up temporary file after paste — Validated in Phase 5: Edit Cycle Integration
- [ ] Small, fast-launching binary
- [x] Preserve clipboard — restore the user's original clipboard contents after the edit cycle — Validated in Phase 3: Accessibility Bridge and Clipboard

### Out of Scope

- Neovim/other editor support — vim only for v1
- Custom key binding configuration — double-tap Control is hardcoded for v1
- Linux/Windows support — macOS only
- Plugin system or extensibility
- Vim configuration management — uses the user's existing ~/.vimrc

## Context

- macOS Accessibility APIs (CGEvent, AXUIElement) are required for global key monitoring and simulating keystrokes in other apps
- These APIs are native Cocoa/AppKit, which strongly favors Swift over Go to avoid heavy FFI bridging
- The app will need Accessibility permissions (System Preferences > Privacy > Accessibility)
- The app will need Input Monitoring permissions for global keyboard events
- Vim is assumed to be installed on the user's system (ships with macOS or via Homebrew)
- The terminal window for vim should be a lightweight, purpose-built window — not a full Terminal.app launch

## Constraints

- **Language**: Swift preferred — macOS Accessibility APIs, global event monitoring, and menu bar integration are all native AppKit/Cocoa APIs with no practical Go equivalent
- **Platform**: macOS only (uses platform-specific APIs throughout)
- **Permissions**: Requires Accessibility and Input Monitoring permissions — app must handle the case where these aren't granted
- **Binary size**: Should be small — no heavy frameworks beyond what macOS provides
- **Startup time**: Must launch quickly and stay lightweight in the background

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Swift over Go | Accessibility APIs, global event taps, AppKit menu bar — all native Swift. Go would require extensive, fragile FFI bridging | Confirmed in Phase 1 |
| No-storyboard menu bar app | Pure code setup via static func main() — NSPrincipalClass alone doesn't wire delegate without nib | Established in Phase 1 |
| Developer signing required from Phase 1 | TCC won't register ad-hoc signed apps in privacy settings | Confirmed in Phase 1 |
| Temp file for vim I/O | Vim naturally writes to files on :wq. Simpler and more reliable than trying to capture vim's stdout or use IPC | Confirmed in Phase 3 |
| Cmd+A/Cmd+C/Cmd+V for text field interaction | Standard macOS way to interact with text fields in other apps via Accessibility. Works across virtually all apps | Confirmed in Phase 3 |
| SwiftTerm for vim hosting | Embedded terminal emulator via LocalProcessTerminalView — proper PTY for vim with colors, cursor movement, raw mode. No Terminal.app dependency | Confirmed in Phase 4 |
| Mtime-based exit detection | Compare file modification date before/after vim runs. :wq changes mtime (saved), :q! does not (aborted). Exit code is unreliable (0 for both) | Confirmed in Phase 4 |
| NSPanel with hidesOnDeactivate=false | Floating panel stays visible when user clicks other apps. NSPanel defaults hidesOnDeactivate to true which hides the window | Confirmed in Phase 4 |
| Strip trailing newline after :wq | Vim always appends a trailing newline on save. Trimming before paste-back prevents an extra blank line in the target text field | Confirmed in Phase 5 |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd:transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-04-02 after Phase 5 completion*
