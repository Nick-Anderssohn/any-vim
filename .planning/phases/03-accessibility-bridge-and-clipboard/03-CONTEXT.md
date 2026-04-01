# Phase 3: Accessibility Bridge and Clipboard - Context

**Gathered:** 2026-04-01
**Status:** Ready for planning

<domain>
## Phase Boundary

The app can grab text from any focused text field via simulated Cmd+A/Cmd+C keystrokes, write it to a temp file, and paste edited text back via Cmd+A/Cmd+V — leaving the user's clipboard exactly as it was before the trigger. This phase builds the `AccessibilityBridge` class and temp file management. It does NOT launch vim, open any terminal window, or wire the full edit cycle.

</domain>

<decisions>
## Implementation Decisions

### Keystroke Timing Strategy
- **D-01:** Use fixed delays between simulated keystrokes. Start with conservative values (~100-150ms between Cmd+A and Cmd+C for capture). Tune empirically during Phase 3 testing.
- **D-02:** Delays are hardcoded named constants in source code. No user-facing configuration, no UserDefaults — tune by changing the constant and recompiling.
- **D-03:** Paste-back uses a longer delay than capture (~200ms) to account for focus restoration to the original app. STATE.md flagged this as a known concern.

### Architecture
- **D-04:** Single `AccessibilityBridge` class handles both text capture and text restore. It owns the clipboard snapshot lifecycle and keystroke simulation. Follows the established one-manager-per-concern pattern (like HotkeyManager, PermissionManager).

### Clipboard Preservation
- **D-05:** Snapshot ALL pasteboard items with all their types (plain text, RTF, images, app-specific custom types). Restore exactly after the edit cycle completes. Zero surprise for users.
- **D-06:** Clipboard is restored after a short delay (~100-200ms) following the Cmd+V paste, ensuring the target app has finished reading the pasteboard before it's overwritten with the restored content.

### Focus Tracking
- **D-07:** Use `NSWorkspace.shared.frontmostApplication` to capture the active app when the hotkey fires. On restore, call `activate()` on the saved `NSRunningApplication`. Simple, reliable, well-documented API.
- **D-08:** If the original app is no longer running when AnyVim tries to restore focus (user quit it during vim session), silently skip focus restoration and clipboard restore. The field no longer exists — this is expected.

### Error Handling and Edge Cases
- **D-09:** Best-effort approach for non-text contexts. Run Cmd+A/Cmd+C regardless of what's focused — no AXUIElement role-checking. If no text is captured, open vim with an empty file.
- **D-10:** Use `NSPasteboard.general.changeCount` before and after Cmd+C to distinguish "empty field" (changeCount changed, content is empty string) from "capture failed" (changeCount unchanged). Both cases still open vim with an empty file — the distinction is for internal logging/debugging.
- **D-11:** Temp files go in `NSTemporaryDirectory()` with UUID-based naming (e.g., `anyvim-{uuid}.txt`). Auto-cleaned by macOS. Deleted after every edit cycle completes.

### Claude's Discretion
- Protocol abstraction design for testability (wrapping CGEvent.post, NSPasteboard, NSWorkspace)
- Exact delay values within the stated ranges — tune during implementation
- Internal logging/debug output for capture success/failure
- How AccessibilityBridge communicates results back to the caller (closure, async/await, or return value)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Technology Stack
- `CLAUDE.md` §Recommended Stack > Accessibility API — AXUIElement and CGEvent.post usage, Cmd+A/Cmd+C/Cmd+V simulation approach, clipboard snapshot/restore pattern, timing guidance
- `CLAUDE.md` §Recommended Stack > Global Keyboard Monitoring — CGEvent.post for synthesizing keystrokes (same API used here for Cmd+A/C/V)

### Requirements
- `.planning/REQUIREMENTS.md` §Text Capture (CAPT-01, CAPT-02, CAPT-03, CAPT-04) — Clipboard save, Cmd+A/Cmd+C, temp file write, empty field handling
- `.planning/REQUIREMENTS.md` §Compatibility (COMPAT-01, COMPAT-02, COMPAT-03) — Native Cocoa apps, browser text areas, keystroke timing

### Prior Phase Context
- `.planning/phases/01-app-shell-and-permissions/01-CONTEXT.md` — Manager ownership pattern, protocol-based testability, AppDelegate instance property retention
- `.planning/phases/02-global-hotkey-detection/02-CONTEXT.md` — HotkeyManager.onTrigger closure (where Phase 3 hooks in), @MainActor isolation pattern

### Existing Code
- `Sources/AnyVim/AppDelegate.swift` — Manager ownership, handleHotkeyTrigger() placeholder where AccessibilityBridge will be called
- `Sources/AnyVim/HotkeyManager.swift` — TapInstalling protocol pattern (model for AccessibilityBridge's system API abstraction)
- `Sources/AnyVim/PermissionManager.swift` — PermissionChecking protocol (AccessibilityBridge should verify permissions before acting)

### Blockers/Notes
- `.planning/STATE.md` §Blockers/Concerns — "Cmd+A -> Cmd+C delay values (150ms) and focus-restore -> Cmd+V (200ms) are community-reported; validate empirically during Phase 3 implementation"

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `TapInstalling` protocol in HotkeyManager.swift — Established pattern for abstracting system APIs behind a protocol for testability. AccessibilityBridge should follow this pattern for CGEvent.post and NSPasteboard.
- `PermissionManager` — Already checks Accessibility/Input Monitoring permissions. AccessibilityBridge can query it before attempting keystroke simulation.
- `HotkeyManager.onTrigger` closure — The integration point. AppDelegate will call AccessibilityBridge from this closure.

### Established Patterns
- Manager classes owned by AppDelegate as instance properties (prevents ARC release)
- Closure-based callbacks for async state changes
- Protocol-based testability for all system API interactions
- `@MainActor` isolation for all manager classes
- Swift 6 strict concurrency mode

### Integration Points
- `AppDelegate.handleHotkeyTrigger()` — Currently prints a placeholder message. Phase 3 wires AccessibilityBridge here.
- Phase 4 will consume the temp file path from AccessibilityBridge to open vim.
- Phase 5 will wire the full cycle: capture -> vim -> restore.

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches for macOS accessibility bridge implementation.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 03-accessibility-bridge-and-clipboard*
*Context gathered: 2026-04-01*
