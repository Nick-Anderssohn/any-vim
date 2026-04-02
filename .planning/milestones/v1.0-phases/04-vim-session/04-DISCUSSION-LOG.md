# Phase 4: Vim Session - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-01
**Phase:** 04-vim-session
**Areas discussed:** Terminal window behavior, Vim exit detection, Vim binary resolution, Terminal appearance

---

## Terminal Window Behavior

### Window Position

| Option | Description | Selected |
|--------|-------------|----------|
| Centered on screen | Always opens centered on the active display. Predictable, works well for a quick edit popup. | ✓ |
| Near the text field | Try to position near focused text field using accessibility APIs. More contextual but complex and less reliable. | |
| Remember last position | Opens where the user last moved/resized it. Persistent across sessions via UserDefaults. | |

**User's choice:** Centered on screen
**Notes:** None

### Window Size

| Option | Description | Selected |
|--------|-------------|----------|
| Fixed comfortable size | A sensible default like 80x24 or 100x30 characters. Resizable but resets each time. | |
| Proportional to screen | Opens at ~60% of screen width/height. Adapts to different display sizes. | |
| Remember last size | Persists the user's resize across sessions via UserDefaults. | ✓ |

**User's choice:** Remember last size
**Notes:** None

### Focus Loss Behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Stay floating, keep focus | NSPanel with .floating level stays above other windows. Must :wq or :q! to dismiss. | ✓ |
| Stay floating, lose focus | Window stays visible but loses keyboard focus when clicking away. | |
| Hide until clicked | Window drops behind other windows when focus is lost. | |

**User's choice:** Stay floating, keep focus
**Notes:** None

### Title Bar

| Option | Description | Selected |
|--------|-------------|----------|
| Minimal title bar | Standard NSPanel title bar with "AnyVim" or filename. Drag handle and close button. | ✓ |
| No title bar | Borderless window. Terminal fills entire frame. No drag handle. | |
| Compact title bar | fullSizeContentView with toolbar hidden. Title bar overlaps content slightly. | |

**User's choice:** Minimal title bar
**Notes:** None

---

## Vim Exit Detection

### Detection Method

| Option | Description | Selected |
|--------|-------------|----------|
| Check file modification time | Record mtime before vim, compare after exit. Changed = :wq, unchanged = :q!. | ✓ |
| Check vim exit code | Vim returns 0 for both :wq and :q!, so can't distinguish without wrapper script. | |
| Watch file with DispatchSource | Monitor temp file for writes in real-time. More complex, swap file false positives. | |

**User's choice:** Check file modification time
**Notes:** None

### Crash/Kill Handling

| Option | Description | Selected |
|--------|-------------|----------|
| Treat as abort | Same as :q! — don't paste, restore clipboard, clean up. Safest default. | ✓ |
| Check file and decide | If file was modified before crash, treat as :wq. More aggressive, could paste partial edits. | |
| Show error dialog | Alert the user and let them choose whether to paste or discard. | |

**User's choice:** Treat as abort
**Notes:** None

### Close Button Behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Close button = abort | Clicking red X kills vim process, treats as :q!. Consistent with crash-as-abort. | ✓ |
| Close button disabled | Remove/disable close button. Must exit through vim commands. | |
| Close button prompts | Confirmation dialog before killing vim. | |

**User's choice:** Close button = abort
**Notes:** None

---

## Vim Binary Resolution

### Default Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Search PATH | Use /usr/bin/env vim or resolve $PATH. Picks up Homebrew vim, falls back to system vim. | ✓ |
| Hardcode /usr/bin/vim | Always use macOS system vim. Ignores Homebrew installs. | |
| Try Homebrew first, fallback | Check /opt/homebrew/bin/vim and /usr/local/bin/vim first, then /usr/bin/vim. | |

**User's choice:** Search PATH
**Notes:** None

### Vim Not Found

| Option | Description | Selected |
|--------|-------------|----------|
| Show error alert | macOS alert explaining vim not found, suggest Homebrew. Treat as abort. | ✓ |
| Show menu bar warning | Persistent warning in menu bar dropdown. Still abort. | |
| You decide | Claude picks approach. | |

**User's choice:** Show error alert
**Notes:** None

---

## Terminal Appearance

### Font

| Option | Description | Selected |
|--------|-------------|----------|
| System monospace | NSFont.monospacedSystemFont (SF Mono). Clean, native, no bundled fonts. | ✓ |
| Menlo | Classic macOS terminal font. | |
| You decide | Claude picks a good monospace font. | |

**User's choice:** System monospace
**Notes:** None

### Color Scheme

| Option | Description | Selected |
|--------|-------------|----------|
| Match system appearance | Light in light mode, dark in dark mode. Vim colorscheme renders on top. | ✓ |
| Always dark | Dark background regardless. Classic terminal look. | |
| You decide | Claude picks sensible colors. | |

**User's choice:** Match system appearance
**Notes:** None

### Visual Style

| Option | Description | Selected |
|--------|-------------|----------|
| Clean and minimal | Standard NSPanel, no special effects. Padding for breathing room. | ✓ |
| Rounded corners + shadow | Custom window with polished popup feel. | |
| Slight transparency | Semi-transparent background to see text underneath. | |

**User's choice:** Clean and minimal
**Notes:** None

---

## Claude's Discretion

- SwiftTerm LocalProcessTerminalView configuration and PTY setup
- Process termination detection mechanism (delegate vs waitUntilExit vs DispatchSource)
- Default window dimensions (exact columns/rows)
- Environment variables for vim subprocess
- Protocol abstraction design for VimSessionManager
- Exit status communication pattern (closure vs async/await)
- Font size within 13-14pt range
- Padding values around terminal view

## Deferred Ideas

None — discussion stayed within phase scope
