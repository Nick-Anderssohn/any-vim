---
phase: 04-vim-session
plan: 02
subsystem: vim-session
tags: [appdegate, vim-wiring, swiftterm, async-await]
dependency_graph:
  requires: [04-01-SUMMARY]
  provides: [AppDelegate-VimSessionManager-wiring]
  affects: [AppDelegate]
tech_stack:
  added: []
  patterns: [Task-MainActor-async, VimSessionManager.openVimSession]
key_files:
  created: []
  modified:
    - Sources/AnyVim/AppDelegate.swift
decisions:
  - abortAndRestore called for both .saved and .aborted exits in Phase 4 — Phase 5 will differentiate and call restoreText() on .saved
metrics:
  duration: 5 minutes
  completed: 2026-04-02
  tasks: 1 of 2 (Task 2 awaiting human verification)
  files: 1
---

# Phase 04 Plan 02: Wire VimSessionManager into AppDelegate Summary

**One-liner:** AppDelegate now owns VimSessionManager and calls openVimSession after capture; double-tapping Control opens the floating SwiftTerm vim window.

## What Was Built

### AppDelegate.swift — three changes

**1. Instance property added:**
```swift
private var vimSessionManager: VimSessionManager!
```
Retained as instance property per Phase 1 ARC pattern — local variables are released immediately.

**2. Initialization in applicationDidFinishLaunching:**
```swift
// Create VimSessionManager (Phase 4: hosts vim in floating SwiftTerm window)
vimSessionManager = VimSessionManager()
```
Initialized after `accessibilityBridge`, before `hotkeyManager`.

**3. handleHotkeyTrigger updated:**
```swift
// Phase 4: Open vim with captured text
let exitResult = await vimSessionManager.openVimSession(tempFileURL: result.tempFileURL)

switch exitResult {
case .saved:
    print("[AnyVim] Vim session completed: saved")
case .aborted:
    print("[AnyVim] Vim session completed: aborted")
}

// NOTE: Phase 4 still uses abortAndRestore for ALL exits.
accessibilityBridge.abortAndRestore(captureResult: result)
```

The Phase 3 placeholder ("Phase 3: capture only") is fully replaced. The full flow is now:
1. captureText() — Cmd+A, Cmd+C, write to temp file
2. openVimSession(tempFileURL:) — open floating SwiftTerm window, await vim exit
3. Log exit result (.saved or .aborted)
4. abortAndRestore() — restore clipboard, delete temp file (Phase 5 will read file on .saved)

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

- `abortAndRestore` is called for both `.saved` and `.aborted` exits. This is intentional per plan design: Phase 5 will call `restoreText()` on `.saved` to paste the edited content back. The Phase 4 behavior discards edits regardless of exit type — this is tracked in Plan 03.

## Task 2: Awaiting Human Verification

Task 2 is a `checkpoint:human-verify` gate. Manual verification of the complete vim session flow is required before this plan can be marked complete. See the checkpoint details in the plan for the 7 test cases.

## Success Criteria

- [x] VimSessionManager is owned by AppDelegate as an instance property
- [x] handleHotkeyTrigger opens vim after capture and awaits the result
- [ ] All 7 manual verification tests pass (pending checkpoint)
- [x] Full automated test suite passes with no regressions

## Self-Check: PASSED

- `/Users/nick/Projects/any-vim/Sources/AnyVim/AppDelegate.swift` — exists, contains all required changes
- Commit `989f20f` — verified in git log
- Build succeeded: `** BUILD SUCCEEDED **`
- Tests: `** TEST SUCCEEDED **`
