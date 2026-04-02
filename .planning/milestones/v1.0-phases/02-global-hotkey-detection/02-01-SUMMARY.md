---
phase: 02-global-hotkey-detection
plan: 01
subsystem: hotkey-detection
tags: [cgeventtap, state-machine, double-tap, health-monitor, swift6, tdd]
dependency_graph:
  requires:
    - Phase 01 Plan 02 (PermissionManager — PermissionChecking protocol)
  provides:
    - HotkeyManaging protocol (consumed by AppDelegate and MenuBarController in Plan 02)
    - HotkeyManager class with CGEventTap lifecycle
    - TapInstalling protocol (enables unit tests without TCC grants)
  affects:
    - AppDelegate — will wire HotkeyManager.install() and onTrigger callback
tech_stack:
  added:
    - Carbon.HIToolbox (kVK_Control, kVK_RightControl keycodes)
  patterns:
    - TapInstalling protocol for CGEvent dependency injection
    - @MainActor protocol for Swift 6 strict concurrency compliance
    - Free C callback dispatching to @MainActor via DispatchQueue.main.async
    - Monotonic timing via ProcessInfo.processInfo.systemUptime
key_files:
  created:
    - Sources/AnyVim/HotkeyManager.swift
    - AnyVimTests/HotkeyManagerTests.swift
  modified:
    - AnyVim.xcodeproj/project.pbxproj (registered both new files)
decisions:
  - "@MainActor on HotkeyManaging protocol required for Swift 6 strict concurrency — HotkeyManager is @MainActor and all protocol members are main-actor-isolated"
  - "TapInstalling protocol added to enable hermetic tests without TCC permissions — CGEvent.tapCreate requires real system grants that CI cannot provide"
  - "holdThreshold and doubleTapThreshold both 350ms — hold detection prevents accidental trigger from slow key release"
metrics:
  duration_seconds: 266
  completed_date: "2026-04-01T06:11:00Z"
  tasks_completed: 1
  files_changed: 3
---

# Phase 02 Plan 01: HotkeyManager Implementation Summary

CGEventTap-based double-tap Control detection with injectable TapInstalling protocol, four-state machine, 350ms threshold, and periodic health monitor — all unit-tested via MockTapInstaller without requiring TCC grants.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 (RED) | HotkeyManagerTests — failing tests | 5447e7a | AnyVimTests/HotkeyManagerTests.swift, AnyVim.xcodeproj/project.pbxproj |
| 1 (GREEN) | HotkeyManager implementation | 458a6ce | Sources/AnyVim/HotkeyManager.swift |

## What Was Built

**HotkeyManager.swift** (325 lines):

- `TapInstalling` protocol with `createTap`, `enableTap`, `isTapEnabled`, `disableTap`
- `SystemTapInstaller` struct — wraps real CGEvent APIs for production use
- `HotkeyManaging` `@MainActor` protocol with `isTapHealthy`, `onTrigger`, `onHealthChange`, `install(permissionManager:)`, `tearDown()`
- `DoubleTapState` enum: `.idle`, `.firstTapDown(at:)`, `.firstTapUp(at:)`, `.secondTapDown`
- `@MainActor final class HotkeyManager` implementing the full lifecycle:
  - Permission-gated `install()` (both Accessibility and Input Monitoring required)
  - `.cgSessionEventTap` / `.headInsertEventTap` / `.defaultTap` tap configuration
  - `handleFlagsChanged(flags:keycode:)` state machine with 350ms gap and hold thresholds
  - Both `kVK_Control` (0x3B) and `kVK_RightControl` (0x3E) recognized
  - Non-Control modifier keys reset state to `.idle`
  - `hotkeyEventTapCallback` free C function dispatching to main queue
  - 5-second health timer with re-enable and full reinstall fallback
  - `tearDownTap()` removes RunLoop source before nilling tap pointer

**HotkeyManagerTests.swift** (201 lines):

- `MockTapInstaller` with configurable `tapEnabledResult` and call tracking
- 10 tests covering all acceptance criteria: double-tap within/outside 350ms, single tap, held control, intervening key, left+right control combination, permission gating, tearDown

## Acceptance Criteria Verification

- `protocol HotkeyManaging` — present
- `@MainActor final class HotkeyManager: HotkeyManaging` — present
- `protocol TapInstalling` — present
- `import Carbon.HIToolbox` — present
- `.idle`, `.firstTapDown`, `.firstTapUp`, `.secondTapDown` — present
- `controlKeycodes` with `kVK_Control` and `kVK_RightControl` — present
- `0.350` threshold — present
- `.cgSessionEventTap`, `.headInsertEventTap`, `.defaultTap` — present
- `CGEvent.tapIsEnabled` — present (via `TapInstalling.isTapEnabled`)
- `hotkeyEventTapCallback` — present
- `DispatchQueue.main.async` — present
- `ProcessInfo.processInfo.systemUptime` — present
- `onHealthChange` — present
- All named test methods present: `testDoubleTapWithin350msFires`, `testDoubleTapOutside350msDoesNotFire`, `testSingleTapDoesNotFire`, `testHeldControlDoesNotFire`, `testInterveningKeyResetsStateMachine`, `MockTapInstaller`
- xcodebuild test: 10 HotkeyManagerTests + 13 Phase 1 tests = 23 total — all pass

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Swift 6 strict concurrency: @MainActor protocol conformance**
- **Found during:** Task 1 GREEN (first build attempt)
- **Issue:** `HotkeyManaging` was declared without `@MainActor`, causing "Conformance of 'HotkeyManager' to protocol 'HotkeyManaging' crosses into main actor-isolated code and can cause data races"
- **Fix:** Added `@MainActor` to `protocol HotkeyManaging` declaration
- **Files modified:** Sources/AnyVim/HotkeyManager.swift
- **Commit:** 458a6ce (included in the GREEN commit)

## Known Stubs

None — HotkeyManager is fully wired. The `onTrigger` closure is production-ready; it will be connected to the text-capture workflow in Phase 3.

## Self-Check: PASSED
