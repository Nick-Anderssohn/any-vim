# Phase 4: Vim Session - Context

**Gathered:** 2026-04-01
**Status:** Ready for planning

<domain>
## Phase Boundary

A floating SwiftTerm-hosted terminal window opens with vim and the user's temp file loaded, and the app reliably detects whether vim exited via :wq (save) or :q! (abort). This phase builds the `VimSessionManager` class. It does NOT wire the full edit cycle (Phase 5), handle text paste-back (Phase 5), or provide vim path configuration UI (Phase 6).

</domain>

<decisions>
## Implementation Decisions

### Terminal Window Behavior
- **D-01:** Window opens centered on the active display. Predictable positioning for a quick edit popup.
- **D-02:** Window size is remembered across sessions via UserDefaults. Sensible default (e.g., 80x24 or 100x30) on first launch, user can resize, and that size persists.
- **D-03:** NSPanel with `.floating` window level stays above other windows. Clicking another app does not hide or defocus the vim window. User must exit through vim commands or the close button.
- **D-04:** Standard minimal NSPanel title bar with "AnyVim" or the filename. Provides drag handle and close button. Familiar macOS window chrome.

### Vim Exit Detection
- **D-05:** Check the temp file's modification time (mtime) before launching vim. After vim's process terminates, compare mtime. Changed = :wq (save), unchanged = :q! (abort). Simple, reliable, no vim scripting needed.
- **D-06:** If the vim process crashes or is killed (e.g., kill -9), treat as abort — don't paste anything back, restore clipboard, clean up temp file. Safest default.
- **D-07:** Clicking the window's red close button (X) kills the vim process and treats it as abort (:q!). Consistent with the crash-as-abort decision.

### Vim Binary Resolution
- **D-08:** Search PATH to find vim (e.g., via `/usr/bin/env vim` or resolving $PATH). Picks up Homebrew vim if installed, falls back to macOS system vim. Matches how the user runs vim in their own terminal.
- **D-09:** If vim is not found in PATH, show a macOS alert explaining the issue and suggesting Homebrew installation. Treat as abort — don't paste anything back.

### Terminal Appearance
- **D-10:** Use `NSFont.monospacedSystemFont` (SF Mono on modern macOS). Clean, native feel, no bundled fonts. Reasonable default size (13-14pt).
- **D-11:** Terminal colors match system appearance — light background in light mode, dark background in dark mode. Vim's own colorscheme renders on top.
- **D-12:** Clean and minimal window style. Standard NSPanel with no special effects. Padding around the SwiftTerm view for breathing room.

### Claude's Discretion
- SwiftTerm `LocalProcessTerminalView` configuration details and PTY setup
- How to detect process termination (SwiftTerm delegate vs Process.waitUntilExit vs DispatchSource)
- Default window dimensions (exact character columns/rows)
- Environment variables passed to the vim subprocess (TERM, SHELL, etc.)
- Protocol abstraction design for VimSessionManager (following established patterns)
- How VimSessionManager communicates exit status back to the caller (closure, async/await)
- Font size within the 13-14pt range
- Exact padding values around the terminal view

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Technology Stack
- `CLAUDE.md` §Recommended Stack > Terminal / Vim Hosting — SwiftTerm LocalProcessTerminalView usage, NSPanel floating window, PTY requirements, why Terminal.app and NSTask+pipe are rejected
- `CLAUDE.md` §Recommended Stack > Build System — SwiftTerm as SPM dependency (v1.13.0)

### Requirements
- `.planning/REQUIREMENTS.md` §Vim Session (VIM-01, VIM-02, VIM-03, VIM-04) — Dedicated terminal window, SwiftTerm/PTY, ~/.vimrc, exit detection

### Prior Phase Context
- `.planning/phases/01-app-shell-and-permissions/01-CONTEXT.md` — Manager ownership pattern, protocol-based testability, AppDelegate instance property retention
- `.planning/phases/02-global-hotkey-detection/02-CONTEXT.md` — HotkeyManager.onTrigger closure, @MainActor isolation, closure-based callbacks
- `.planning/phases/03-accessibility-bridge-and-clipboard/03-CONTEXT.md` — CaptureResult struct (tempFileURL, originalApp, clipboardSnapshot), AccessibilityBridge API surface

### Existing Code
- `Sources/AnyVim/AppDelegate.swift` — Manager ownership, `handleHotkeyTrigger()` where VimSessionManager will be called, CaptureResult consumption
- `Sources/AnyVim/AccessibilityBridge.swift` — CaptureResult struct definition (tempFileURL is the file vim opens), restoreText() and abortAndRestore() APIs that Phase 5 calls after vim exits
- `Sources/AnyVim/TempFileManager.swift` — Temp file creation/deletion, UUID-based naming in NSTemporaryDirectory()
- `Sources/AnyVim/SystemProtocols.swift` — Established protocol patterns for system API abstraction

### Blockers/Notes
- `.planning/STATE.md` §Blockers/Concerns — "SwiftTerm NSWindow lifecycle for modal vim session needs hands-on spike before Phase 4 plan is finalized — TerminalViewDelegate.processTerminated API needs verification"

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `CaptureResult` struct — Already holds `tempFileURL` that vim needs to open. VimSessionManager receives this from the caller.
- `TempFileManager` — Handles temp file lifecycle. VimSessionManager uses the URL but doesn't manage the file itself.
- Protocol-based testability pattern — `TapInstalling`, `PermissionChecking`, `KeystrokeSending`, `AppActivating`, `PasteboardAccessing` all establish the pattern VimSessionManager should follow.
- Manager ownership pattern — AppDelegate retains all managers as instance properties.

### Established Patterns
- Manager classes owned by AppDelegate as instance properties (prevents ARC release)
- Closure-based callbacks for async state changes (`onTrigger`, `onChange`)
- Protocol-based testability for all system API interactions
- `@MainActor` isolation for all manager classes
- Swift 6 strict concurrency mode

### Integration Points
- `AppDelegate.handleHotkeyTrigger()` — Currently captures text and immediately aborts. Phase 4 adds VimSessionManager call between capture and restore.
- Phase 5 will wire: capture → vim session → check exit → restoreText() or abortAndRestore()
- VimSessionManager needs to expose: (1) a way to open vim with a file URL, (2) a callback/result indicating save vs abort when vim exits

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches for SwiftTerm-based vim hosting.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 04-vim-session*
*Context gathered: 2026-04-01*
