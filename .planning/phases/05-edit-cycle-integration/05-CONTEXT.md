# Phase 5: Edit Cycle Integration - Context

**Gathered:** 2026-04-01
**Status:** Ready for planning

<domain>
## Phase Boundary

Wire the complete trigger-grab-edit-paste workflow end-to-end. On hotkey trigger: capture text (Phase 3), open vim (Phase 4), detect exit, paste back on :wq or abort on :q!, clean up temp file, and restore clipboard. Includes re-entrancy protection so a second trigger during an active session is ignored. This phase does NOT add visual feedback (Phase 6), vim path configuration (Phase 6), or any new capabilities — it connects existing components.

</domain>

<decisions>
## Implementation Decisions

### Re-entrancy Guard
- **D-01:** Silent ignore when user triggers hotkey while a vim session is active. No beep, no alert, no window refocus — the trigger is simply swallowed. Matches SC-4.
- **D-02:** Guard implemented as a simple `isEditSessionActive` bool on AppDelegate. Set true at the start of `handleHotkeyTrigger`, false after all cleanup completes. Follows the existing manager-in-AppDelegate ownership pattern.

### Error Handling
- **D-03:** If reading the edited temp file fails after :wq (disk error, file deleted externally, encoding issue), treat as abort — restore clipboard, delete temp file, do not paste. Consistent with Phase 4's crash-as-abort philosophy (D-06).
- **D-04:** No user-visible error feedback for read failures. The abort path handles it silently.

### Temp File Cleanup
- **D-05:** Temp file deleted immediately after the edit cycle completes — no delay, no debug grace period. Matches REST-05 and Phase 3 D-11.
- **D-06:** `handleHotkeyTrigger` in AppDelegate owns cleanup as the final step after restoreText or abortAndRestore. Single place for all end-of-cycle cleanup. Note: `abortAndRestore` already calls `deleteTempFile` internally — planner may centralize or keep idempotent.

### Edit Cycle Feedback
- **D-07:** No user-visible feedback on cycle completion or abort. The edited text appearing in the field (or not) is the signal. Phase 6 adds menu bar icon changes for active session state.

### Claude's Discretion
- Whether to remove `deleteTempFile` from `abortAndRestore` (centralize in AppDelegate) or keep it idempotent in both places
- Exact orchestration flow in `handleHotkeyTrigger` (the wiring between captureText → openVimSession → restoreText/abortAndRestore → cleanup)
- Whether to keep or remove the Phase 4 `print()` debug logging
- How to read the edited temp file content (String(contentsOf:) encoding choice)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements
- `.planning/REQUIREMENTS.md` §Text Restore (REST-01, REST-02, REST-03, REST-04, REST-05) — Paste-back on :wq, skip on :q!, clipboard restore, temp file deletion

### Prior Phase Context
- `.planning/phases/03-accessibility-bridge-and-clipboard/03-CONTEXT.md` — AccessibilityBridge API surface, clipboard preservation decisions, timing constants, best-effort capture approach
- `.planning/phases/04-vim-session/04-CONTEXT.md` — VimSessionManager API, mtime-based exit detection, crash-as-abort philosophy, window behavior decisions

### Existing Code (Critical)
- `Sources/AnyVim/AppDelegate.swift` — `handleHotkeyTrigger()` at line 127: current Phase 4 wiring that must be modified. Shows capture → vim → abort pattern that Phase 5 replaces with full cycle.
- `Sources/AnyVim/AccessibilityBridge.swift` — `restoreText(_:captureResult:)` at line 115: paste-back API (unused until Phase 5). `abortAndRestore(captureResult:)` at line 145: abort API (already called).
- `Sources/AnyVim/VimSessionManager.swift` — `openVimSession(tempFileURL:)` returns `VimExitResult` (.saved/.aborted). Async/await API.
- `Sources/AnyVim/TempFileManager.swift` — `deleteTempFile(at:)` for cleanup.

### Technology Stack
- `CLAUDE.md` §Recommended Stack > Accessibility API — Cmd+A/Cmd+V simulation, clipboard snapshot/restore pattern

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `AccessibilityBridge.restoreText(_:captureResult:)` — Fully implemented paste-back: sets clipboard, restores focus, Cmd+A/Cmd+V, restores clipboard. Ready to call.
- `AccessibilityBridge.abortAndRestore(captureResult:)` — Fully implemented abort: restores clipboard, deletes temp file. Already wired in Phase 4.
- `VimSessionManager.openVimSession(tempFileURL:)` — Returns `VimExitResult` via async/await. Already wired in Phase 4.
- `TempFileManager.deleteTempFile(at:)` — File deletion. Already called inside `abortAndRestore`.
- `CaptureResult` struct — Holds tempFileURL, originalApp, clipboardSnapshot. Passed through the full cycle.

### Established Patterns
- Manager classes owned by AppDelegate as instance properties
- `@MainActor` isolation for all managers and AppDelegate
- Async/await with `Task { @MainActor in }` for hotkey trigger handling
- Protocol-based testability for system API interactions
- Swift 6 strict concurrency mode

### Integration Points
- `AppDelegate.handleHotkeyTrigger()` — The single point where all wiring happens. Currently: capture → vim → log → abortAndRestore. Phase 5 changes to: guard re-entrancy → capture → vim → switch(result) { .saved: read file, restoreText / .aborted: abortAndRestore } → delete temp file → clear guard.

</code_context>

<specifics>
## Specific Ideas

No specific requirements — the integration is well-defined by the existing APIs. Connect the dots.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 05-edit-cycle-integration*
*Context gathered: 2026-04-01*
