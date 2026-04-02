# AnyVim

## What This Is

A macOS menu bar utility that lets you use vim to edit text in any text field across any application. Double-tap the Control key to open vim with the current text field's contents, edit freely, and :wq to send the edited text back to the original text field.

## Core Value

Seamless vim editing in any text input on macOS — the trigger-edit-return loop must feel instant and reliable.

## Requirements

### Validated

- ✓ Menu bar app with status icon that runs in the background — v1.0
- ✓ System-wide double-tap Control key detection to trigger vim — v1.0
- ✓ Grab existing text from the focused text field (Cmd+A, Cmd+C via Accessibility APIs) — v1.0
- ✓ Write grabbed text to a temporary file — v1.0
- ✓ Launch vim in a terminal window with the temp file — v1.0
- ✓ On :wq, read the edited temp file contents — v1.0
- ✓ Paste edited text back into the original text field (Cmd+A, Cmd+V via Accessibility APIs) — v1.0
- ✓ Clean up temporary file after paste — v1.0
- ✓ Preserve clipboard — restore the user's original clipboard contents after the edit cycle — v1.0
- ✓ Visual session indicator — menu bar icon changes during active vim session — v1.0
- ✓ Configurable vim path — user can point to a non-default vim binary — v1.0

### Active

- [ ] Small, fast-launching binary
- [ ] Edit history in ~/.local/share/any-vim/ for recovery
- [ ] File type hint via temp file extension based on context
- [ ] Graceful Electron app support with fallback strategies
- [ ] Custom hotkey configuration (beyond double-tap Control)
- [ ] Neovim support as an alternative editor

### Out of Scope

- Vim keybindings overlay (kindaVim-style) — different product category, AnyVim launches real vim
- Browser extension (Firenvim-style) — extension maintenance burden; temp-file approach works across all apps
- Plugin system / extensibility — no validated demand; premature generalization
- Bundled vim binary — increases binary size; users already have vim on macOS
- App Store distribution — Accessibility + Input Monitoring permissions incompatible with sandbox
- Linux/Windows support — macOS-only APIs throughout
- Vim config management — scope creep; vim uses ~/.vimrc automatically
- Browser address bar support — too constrained for full text editing

## Context

Shipped v1.0 with 9,540 LOC Swift in 3 days.
Tech stack: Swift 6, AppKit, CGEventTap, AXUIElement, SwiftTerm, SPM.
All 27 v1 requirements validated. 67 unit tests passing.
Tested in TextEdit, Notes, Safari, Chrome — native apps and browser text areas confirmed working.
Menu bar daemon with no Dock icon, permission auto-detection, and launch-at-login support.

## Constraints

- **Language**: Swift — macOS Accessibility APIs, global event monitoring, and menu bar integration are all native AppKit/Cocoa APIs
- **Platform**: macOS only (uses platform-specific APIs throughout)
- **Permissions**: Requires Accessibility and Input Monitoring permissions — app handles the case where these aren't granted
- **Binary size**: Should be small — no heavy frameworks beyond what macOS provides
- **Startup time**: Must launch quickly and stay lightweight in the background

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Swift over Go | Accessibility APIs, global event taps, AppKit menu bar — all native Swift. Go would require extensive, fragile FFI bridging | ✓ Good |
| No-storyboard menu bar app | Pure code setup via static func main() — NSPrincipalClass alone doesn't wire delegate without nib | ✓ Good |
| Developer signing required from Phase 1 | TCC won't register ad-hoc signed apps in privacy settings | ✓ Good |
| Temp file for vim I/O | Vim naturally writes to files on :wq. Simpler and more reliable than trying to capture vim's stdout or use IPC | ✓ Good |
| Cmd+A/Cmd+C/Cmd+V for text field interaction | Standard macOS way to interact with text fields in other apps via Accessibility. Works across virtually all apps | ✓ Good |
| SwiftTerm for vim hosting | Embedded terminal emulator via LocalProcessTerminalView — proper PTY for vim with colors, cursor movement, raw mode. No Terminal.app dependency | ✓ Good |
| Mtime-based exit detection | Compare file modification date before/after vim runs. :wq changes mtime (saved), :q! does not (aborted). Exit code is unreliable (0 for both) | ✓ Good |
| NSPanel with hidesOnDeactivate=false | Floating panel stays visible when user clicks other apps. NSPanel defaults hidesOnDeactivate to true which hides the window | ✓ Good |
| Strip trailing newline after :wq | Vim always appends a trailing newline on save. Trimming before paste-back prevents an extra blank line in the target text field | ✓ Good |
| Composing resolver for vim path | UserDefaultsVimPathResolver wraps ShellVimPathResolver — checks UserDefaults first, falls back silently on invalid/missing custom path | ✓ Good |
| Static "Vim: (default)" in menu | Avoid calling ShellVimPathResolver on main thread during menu build (100-300ms block). Show static label, resolve at trigger time | ✓ Good |

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
*Last updated: 2026-04-02 after v1.0 milestone completion*
