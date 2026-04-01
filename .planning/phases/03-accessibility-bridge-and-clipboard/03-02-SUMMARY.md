---
phase: 03-accessibility-bridge-and-clipboard
plan: "02"
subsystem: accessibility-bridge
tags: [accessibility, clipboard, keystrokes, async, tdd]
dependency_graph:
  requires: ["03-01"]
  provides: ["AccessibilityBridge", "CaptureResult"]
  affects: ["AppDelegate", "Phase 5 vim session wiring"]
tech_stack:
  added: []
  patterns: ["@MainActor async/await", "protocol injection for testability", "changeCount sentinel for copy detection"]
key_files:
  created:
    - Sources/AnyVim/AccessibilityBridge.swift
    - AnyVimTests/AccessibilityBridgeTests.swift
  modified:
    - Sources/AnyVim/AppDelegate.swift
    - AnyVim.xcodeproj/project.pbxproj
decisions:
  - "changeCount sentinel approach: read pasteboard.changeCount before Cmd+A and after Cmd+C sleep; if equal, assume capture failed (D-10) and write empty temp file rather than silently failing"
  - "MockPasteboardForBridge uses read-count tracking for changeCount to simulate clipboard updating after Cmd+C without requiring actual keystrokes"
  - "restoreText skips paste if app.isTerminated (D-08) — no workaround needed for unit testing since NSRunningApplication.current is always non-terminated"
  - "abortAndRestore in Phase 3 called immediately after captureText to clean up — vim wiring deferred to Phase 5"
metrics:
  duration: "20 minutes"
  completed: "2026-04-01"
  tasks: 2
  files: 4
---

# Phase 3 Plan 02: AccessibilityBridge Summary

**One-liner:** Async AccessibilityBridge class orchestrates Cmd+A/Cmd+C capture and Cmd+A/Cmd+V paste-back with named timing constants, clipboard preservation, and 12 unit tests.

## What Was Built

### AccessibilityBridge.swift

`@MainActor final class AccessibilityBridge` is the core text-capture/restore class for Phase 3. It:

- `captureText() async -> CaptureResult?` — guards on Accessibility permission, snapshots clipboard, posts Cmd+A then Cmd+C with 150ms delays, checks changeCount sentinel (D-10), writes captured text (or empty string) to a temp file, returns a `CaptureResult`
- `restoreText(_ editedContent: String, captureResult: CaptureResult) async` — re-activates original app, waits 200ms for focus restore, posts Cmd+A/Cmd+V with 150ms delay, then restores the original clipboard after 150ms
- `abortAndRestore(captureResult: CaptureResult)` — synchronous cleanup path for canceled edit cycles

Named timing constants (COMPAT-03): `captureDelayNs = 150ms`, `focusRestoreDelayNs = 200ms`, `pasteDelayNs = 150ms`, `clipboardRestoreDelayNs = 150ms` — all non-zero.

`CaptureResult` struct carries `tempFileURL`, `originalApp: NSRunningApplication`, and `clipboardSnapshot: ClipboardSnapshot`.

All 6 protocol dependencies are injected via init (KeystrokeSending, AppActivating, ClipboardGuard, TempFileManager, PermissionChecking, PasteboardAccessing).

### AccessibilityBridgeTests.swift

12 unit tests covering:
- `testCaptureTextPostsCmdACmdC` — verifies keyCode 0x00 then 0x08 with .maskCommand
- `testCaptureTextSnapshotsClipboardBeforeKeystrokes` — clipboardSnapshot is non-nil
- `testCaptureTextCreatesTempFile` — file exists on disk with expected content
- `testCaptureTextReturnsOriginalApp` — processIdentifier matches mockAppActivator.frontmostApp
- `testCaptureTextEmptyClipboard` — nil stringForType produces empty temp file
- `testCaptureTextUnchangedChangeCount` — D-10: same changeCount before/after → empty temp file
- `testCaptureTextNoAccessibility` — returns nil
- `testCaptureTextNoFrontmostApp` — returns nil
- `testRestoreTextPostsCmdACmdV` — keyCode 0x00 then 0x09 with .maskCommand
- `testRestoreTextActivatesOriginalApp` — activateCalled is true
- `testRestoreTextSetsClipboardBeforePaste` — setString called with edited content
- `testTimingConstantsAreNonZero` — all 4 constants > 0 (COMPAT-03)

### AppDelegate.swift (updated)

- Added `private var accessibilityBridge: AccessibilityBridge!` instance property
- Initialized in `applicationDidFinishLaunching` before `HotkeyManager` creation
- Replaced `handleHotkeyTrigger` placeholder with async Task calling `captureText()`
- Added `showCaptureFailureAlert()` with "Text Capture Failed" message and "Dismiss" button (UI-SPEC)
- Phase 3 placeholder: `abortAndRestore` called immediately (vim session deferred to Phase 5)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] MockPasteboardForBridge changeCount not simulating clipboard update**

- **Found during:** Task 1 (TDD GREEN phase — testCaptureTextCreatesTempFile failed)
- **Issue:** The bridge reads `pasteboard.changeCount` before Cmd+A and after Cmd+C. Since the mock doesn't auto-increment on keystrokes, both reads returned the same value, causing the bridge to take the "unchanged changeCount" path and write an empty temp file instead of the captured text.
- **Fix:** Added `changeCountAfterCopy: Int?` to `MockPasteboardForBridge` and a read-count tracking mechanism. When `changeCountAfterCopy` is set, the second (and subsequent) reads return that value, simulating the clipboard updating after Cmd+C. Tests that need a successful copy set `changeCountAfterCopy = 1`; tests for the "unchanged" path leave it nil.
- **Files modified:** AnyVimTests/AccessibilityBridgeTests.swift
- **Commit:** cc29b53

## Commits

| Hash | Message |
|------|---------|
| cc29b53 | feat(03-02): AccessibilityBridge with captureText/restoreText and 12 passing tests |
| a750fdb | feat(03-02): wire AccessibilityBridge into AppDelegate.handleHotkeyTrigger |

## Known Stubs

- `handleHotkeyTrigger()` in AppDelegate calls `abortAndRestore(captureResult:)` immediately after capture — this is an intentional Phase 3 placeholder. Phase 5 will replace this with the full vim session cycle (open SwiftTerm window with `result.tempFileURL`, wait for `:wq`, call `restoreText`).

## Self-Check: PASSED

- Sources/AnyVim/AccessibilityBridge.swift: FOUND
- AnyVimTests/AccessibilityBridgeTests.swift: FOUND
- Sources/AnyVim/AppDelegate.swift (modified): FOUND
- Commit cc29b53: FOUND
- Commit a750fdb: FOUND
- All 38 tests pass (xcodebuild test SUCCEEDED)
