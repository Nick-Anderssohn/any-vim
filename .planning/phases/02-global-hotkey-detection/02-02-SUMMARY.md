---
phase: 02-global-hotkey-detection
plan: 02
subsystem: hotkey-detection
tags: [appdelegat, menubar, hotkeymanager, integration, swift6, macos]
dependency_graph:
  requires:
    - Phase 02 Plan 01 (HotkeyManager — HotkeyManaging protocol)
    - Phase 01 Plan 02 (MenuBarController, AppDelegate, PermissionManager)
  provides:
    - HotkeyManager wired into AppDelegate lifecycle
    - Tap health status display in menu bar dropdown
    - onTrigger placeholder for Phase 5 edit-cycle wiring
  affects:
    - AppDelegate — now owns HotkeyManager, installs tap, rebuilds menu on health changes
    - MenuBarController — now shows "Hotkey: Active" / "Hotkey: Inactive" status
tech_stack:
  added: []
  patterns:
    - "@MainActor on AppDelegate and MenuBarController for Swift 6 concurrency compliance"
    - "MenuBarController created before hotkeyManager.install() to avoid nil crash on synchronous health change callback"
key_files:
  created: []
  modified:
    - Sources/AnyVim/AppDelegate.swift
    - Sources/AnyVim/MenuBarController.swift
    - AnyVimTests/MenuBarControllerTests.swift
decisions:
  - "AppDelegate and MenuBarController marked @MainActor — both reference @MainActor-isolated HotkeyManaging protocol members; Swift 6 strict concurrency requires explicit isolation"
  - "MenuBarController created before hotkeyManager.install() — install() fires isTapHealthy.didSet synchronously which calls onHealthChange which calls rebuildMenu(); menuBarController must be non-nil before that call"
metrics:
  duration_seconds: 1225
  completed_date: "2026-04-01T06:20:25Z"
  tasks_completed: 1
  files_changed: 3
---

# Phase 02 Plan 02: HotkeyManager Integration Summary

HotkeyManager wired into AppDelegate with permission-triggered installation, menu bar tap health display ("Hotkey: Active" / "Hotkey: Inactive"), and onTrigger placeholder — all backed by three new MenuBarController tests via MockHotkeyManager.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Wire HotkeyManager into AppDelegate and add tap health status to MenuBarController | a9be61b | Sources/AnyVim/AppDelegate.swift, Sources/AnyVim/MenuBarController.swift, AnyVimTests/MenuBarControllerTests.swift |

## Task 2: Awaiting Manual Verification

Task 2 is a `checkpoint:human-verify` — manual verification of system-wide double-tap Control detection. See checkpoint details returned to orchestrator.

## What Was Built

**Sources/AnyVim/AppDelegate.swift:**

- Added `private var hotkeyManager: HotkeyManager!` instance property (retained)
- In `applicationDidFinishLaunching`: create `HotkeyManager()`, wire `onTrigger` and `onHealthChange` closures, create `MenuBarController` (with hotkeyManager), build initial menu, then call `install()` — order is critical (see Deviations)
- In `handlePermissionChange`: attempt re-install if tap not healthy, then call `rebuildMenu()`
- Added `private func rebuildMenu()` helper
- Added `private func handleHotkeyTrigger()` placeholder that prints `[AnyVim] Hotkey triggered!`
- Marked whole class `@MainActor` for Swift 6 compliance

**Sources/AnyVim/MenuBarController.swift:**

- Added `private let hotkeyManager: HotkeyManaging?` property
- Updated `init` to accept `hotkeyManager: HotkeyManaging? = nil` (backward compatible)
- Added tap health status block in `buildMenu()` after Input Monitoring item:
  - `hotkeyManager == nil`: no status item shown
  - `isTapHealthy == true`: "Hotkey: Active"
  - `isTapHealthy == false`: "Hotkey: Inactive — Tap Unhealthy"
- Marked `@MainActor` for Swift 6 compliance

**AnyVimTests/MenuBarControllerTests.swift:**

- Added `@MainActor final class MockHotkeyManager: HotkeyManaging` with configurable `isTapHealthy`, call tracking for `installCalled` and `tearDownCalled`
- `testMenuShowsHotkeyActiveWhenTapHealthy` — verifies "Hotkey: Active" item present
- `testMenuShowsHotkeyInactiveWhenTapUnhealthy` — verifies "Inactive" item present
- `testMenuOmitsHotkeyStatusWhenNoHotkeyManager` — verifies no "Hotkey" item when nil
- Marked `@MainActor` on the test class

## Acceptance Criteria Verification

- `private var hotkeyManager: HotkeyManager!` in AppDelegate — present
- `hotkeyManager.install(permissionManager: permissionManager)` in AppDelegate — present (twice: launch + permission change)
- `hotkeyManager.onTrigger` in AppDelegate — present
- `hotkeyManager.onHealthChange` in AppDelegate — present
- `handleHotkeyTrigger` in AppDelegate — present
- `rebuildMenu` in AppDelegate — present
- `hotkeyManager: HotkeyManaging?` in MenuBarController — present
- `Hotkey: Active` in MenuBarController — present
- `Hotkey: Inactive` in MenuBarController — present
- `MockHotkeyManager` in MenuBarControllerTests — present
- `testMenuShowsHotkeyActiveWhenTapHealthy` — present
- `testMenuShowsHotkeyInactiveWhenTapUnhealthy` — present
- `xcodebuild test` passes with zero failures — 26 tests total, all passed

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Crash when onHealthChange fires synchronously during install()**
- **Found during:** Task 1 (first test run)
- **Issue:** The plan specified creating HotkeyManager, wiring closures, calling `install()`, then creating MenuBarController. However, `install()` calls `installTap()` which sets `isTapHealthy`, which fires `isTapHealthy.didSet` synchronously, which calls `onHealthChange`, which calls `rebuildMenu()`, which crashes with `assertionFailure` because `menuBarController` was still nil at that point.
- **Fix:** Moved `MenuBarController` creation and initial `buildMenu()` call to BEFORE `hotkeyManager.install()`. Added comment documenting the ordering constraint.
- **Files modified:** Sources/AnyVim/AppDelegate.swift
- **Commit:** a9be61b (included in the Task 1 commit)

**2. [Rule 1 - Bug] Swift 6 strict concurrency: @MainActor required on AppDelegate and MenuBarController**
- **Found during:** Task 1 (first build attempt after adding hotkeyManager references)
- **Issue:** `HotkeyManaging` is `@MainActor`, so accessing `isTapHealthy` and calling `install()` / `buildMenu()` from non-isolated contexts causes Swift 6 errors. `AppDelegate` and `MenuBarController` are both main-thread-only in practice but lacked explicit `@MainActor` annotation.
- **Fix:** Added `@MainActor` to both `AppDelegate` and `MenuBarController` class declarations.
- **Files modified:** Sources/AnyVim/AppDelegate.swift, Sources/AnyVim/MenuBarController.swift
- **Commit:** a9be61b (included in the Task 1 commit)

## Known Stubs

**handleHotkeyTrigger() in AppDelegate.swift** — prints `[AnyVim] Hotkey triggered!` to stdout. This is intentional per the plan (D-10): actual edit-cycle wiring (capture text, launch vim, paste back) comes in Phase 3/5. The stub is load-bearing for manual verification in Task 2.

## Self-Check: PASSED
