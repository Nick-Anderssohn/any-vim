---
phase: 01-app-shell-and-permissions
plan: 02
subsystem: permissions
tags: [swift, appkit, accessibility, input-monitoring, smappservice, unnotification, xctest]

# Dependency graph
requires: [01-01]
provides:
  - PermissionManager with AXIsProcessTrusted + CGPreflightListenEventAccess polling
  - LoginItemManager with SMAppService first-run auto-enable
  - NotificationManager with UNUserNotificationCenter permission-granted banners
  - Sequential permission alert flow (Accessibility first, then Input Monitoring)
  - Live menu rebuild on permission change via 3s timer + DistributedNotificationCenter
  - 13 passing XCTests (6 PermissionManagerTests, 4 LoginItemManagerTests, 3 MenuBarControllerTests)
affects: [all subsequent phases]

# Tech tracking
tech-stack:
  added: [ApplicationServices/AXIsProcessTrusted, CoreGraphics/CGPreflightListenEventAccess, ServiceManagement/SMAppService, UserNotifications/UNUserNotificationCenter, Foundation/DistributedNotificationCenter]
  patterns:
    - PermissionChecking protocol abstracts AXIsProcessTrusted + CGPreflightListenEventAccess for testability
    - LoginItemManaging protocol abstracts SMAppService for testability
    - DistributedNotificationCenter + 3s Timer polling for live permission detection without restart
    - Plain AXIsProcessTrusted() in timer (never kAXTrustedCheckOptionPrompt in polling)
    - UserDefaults "launchAtLoginConfigured" flag for first-run auto-enable (reads SMAppService live for status)
    - Sequential alert flow: Accessibility alert shown at launch if missing; Input Monitoring alert shown after Accessibility is granted

key-files:
  created:
    - Sources/AnyVim/PermissionManager.swift
    - Sources/AnyVim/LoginItemManager.swift
    - Sources/AnyVim/NotificationManager.swift
    - AnyVimTests/PermissionManagerTests.swift
    - AnyVimTests/LoginItemManagerTests.swift
  modified:
    - Sources/AnyVim/AppDelegate.swift
    - Sources/AnyVim/MenuBarController.swift
    - AnyVimTests/MenuBarControllerTests.swift
    - AnyVim.xcodeproj/project.pbxproj

key-decisions:
  - "PermissionChecking protocol extended with openAccessibilitySettings/openInputMonitoringSettings — keeps MenuBarController fully protocol-typed (no concrete PermissionManager cast needed)"
  - "MockLoginItemService implements first-run logic in-memory (not via UserDefaults) — tests are hermetic and do not modify real UserDefaults state"
  - "MenuBarControllerTests updated with StubPermissionChecker + StubLoginItemManager — preserves the 3 original tests while adapting to new constructor signature"

patterns-established:
  - "Pattern: Protocol-abstracted manager types — PermissionChecking and LoginItemManaging enable XCTest mock injection without TCC or SMAppService calls"
  - "Pattern: Permission polling — DistributedNotificationCenter ('com.apple.accessibility.api') + 3s Timer fallback; plain AXIsProcessTrusted() in timer (never kAXTrustedCheckOptionPrompt)"

requirements-completed: [PERM-01, PERM-02, PERM-03, MENU-04]

# Metrics
duration: 8min
completed: 2026-03-31
---

# Phase 01 Plan 02: Permission Flow, Login Item, and Notifications Summary

**Permission checking (AXIsProcessTrusted + CGPreflightListenEventAccess), sequential alert onboarding (Accessibility first with launch-at-login note, then Input Monitoring), DistributedNotificationCenter + 3s-timer live polling, SMAppService first-run auto-enable, UNUserNotificationCenter permission-granted banners, live menu rebuild — all backed by 13 passing XCTests**

## Performance

- **Duration:** ~8 min
- **Started:** 2026-03-31T20:55:00Z
- **Completed:** 2026-03-31T20:58:54Z
- **Tasks:** 2 of 2
- **Files modified:** 9 (5 created, 4 updated)

## Accomplishments

- **PermissionManager**: checks `AXIsProcessTrusted()` and `CGPreflightListenEventAccess()` live; starts DistributedNotificationCenter observer for `"com.apple.accessibility.api"` + 3s `Timer` fallback; calls `onChange(accessibilityChanged:inputMonitoringChanged:)` only on actual state transitions; exposes `openAccessibilitySettings()` and `openInputMonitoringSettings()` via `PermissionChecking` protocol
- **LoginItemManager**: reads `SMAppService.mainApp.status == .enabled` live (never cached); `enableIfFirstRun()` uses `UserDefaults` "launchAtLoginConfigured" key; `enable()`/`disable()` wrap `SMAppService.mainApp.register()`/`unregister()`
- **NotificationManager**: calls `UNUserNotificationCenter.current().requestAuthorization` at launch; posts `UNNotificationRequest` with `trigger: nil` (immediate delivery) for each permission grant
- **AppDelegate**: wires all managers, runs sequential alert flow (Accessibility alert shown at launch if missing — D-08 launch-at-login copy appended; Input Monitoring alert shown after Accessibility is granted), starts `permissionManager.startMonitoring`, rebuilds menu on change
- **MenuBarController**: refactored to accept `PermissionChecking` + `LoginItemManaging` protocols; `buildMenu()` builds live menu per UI-SPEC — "Granted" (no action) vs "Not Granted — Click to Enable" (opens settings), "Launch at Login" checkmark from live SMAppService state, "Quit AnyVim" with ⌘Q
- All 13 unit tests pass (6 PermissionManagerTests, 4 LoginItemManagerTests, 3 MenuBarControllerTests)

## Task Commits

Each task was committed atomically:

1. **Task 1: Implement PermissionManager, LoginItemManager, and NotificationManager** — `89acbe4` (feat)
2. **Task 2: Wire managers into AppDelegate and MenuBarController with sequential alert flow** — `782be3e` (feat)

## Files Created/Modified

- `Sources/AnyVim/PermissionManager.swift` — `PermissionChecking` protocol + `PermissionManager` class; `AXIsProcessTrusted`, `CGPreflightListenEventAccess`, DistributedNotificationCenter, 3s Timer, System Settings URLs
- `Sources/AnyVim/LoginItemManager.swift` — `LoginItemManaging` protocol + `LoginItemManager` class; SMAppService wrapper, first-run auto-enable
- `Sources/AnyVim/NotificationManager.swift` — `NotificationManager` class; UNUserNotificationCenter authorization + immediate notification posting
- `Sources/AnyVim/AppDelegate.swift` — all managers wired; sequential alert flow with exact UI-SPEC copy; permission monitoring with menu rebuild callback
- `Sources/AnyVim/MenuBarController.swift` — refactored with protocol constructor; live menu build per UI-SPEC Menu Structure and Copywriting Contract
- `AnyVimTests/PermissionManagerTests.swift` — 6 tests via `MockPermissionChecker` (no TCC required)
- `AnyVimTests/LoginItemManagerTests.swift` — 4 tests via `MockLoginItemService` (no SMAppService required)
- `AnyVimTests/MenuBarControllerTests.swift` — updated with stubs to adapt to new constructor; 3 original tests preserved
- `AnyVim.xcodeproj/project.pbxproj` — added PBXBuildFile, PBXFileReference, PBXGroup, and PBXSourcesBuildPhase entries for all 5 new files

## Decisions Made

- Extended `PermissionChecking` protocol to include `openAccessibilitySettings()` and `openInputMonitoringSettings()` — prevents concrete-type casting in `MenuBarController` and keeps the class fully protocol-typed for testability
- `MockLoginItemService` implements first-run logic in-memory (not via real `UserDefaults`) — hermetic tests with no real system state mutation
- `MenuBarControllerTests` updated with `StubPermissionChecker` + `StubLoginItemManager` stubs — 3 original tests preserved, adapted for new constructor signature

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical Functionality] Extended PermissionChecking protocol with open-settings methods**

- **Found during:** Task 2, implementing MenuBarController
- **Issue:** Plan specified `PermissionChecking` with only `isAccessibilityGranted` and `isInputMonitoringGranted`. MenuBarController needs to call `openAccessibilitySettings()` and `openInputMonitoringSettings()` from its `@objc` action handlers — requiring either a concrete cast (fragile) or protocol extension (correct).
- **Fix:** Added `func openAccessibilitySettings()` and `func openInputMonitoringSettings()` to `PermissionChecking`. Updated `MockPermissionChecker` to implement them (with call-tracking booleans). Zero impact on testability — mocks implement all protocol requirements.
- **Files modified:** `Sources/AnyVim/PermissionManager.swift`, `AnyVimTests/PermissionManagerTests.swift`
- **Commit:** `782be3e`

## Known Stubs

None — all permission status, login item state, and notification delivery are wired to live system APIs.

## Self-Check: PASSED

- FOUND: Sources/AnyVim/PermissionManager.swift
- FOUND: Sources/AnyVim/LoginItemManager.swift
- FOUND: Sources/AnyVim/NotificationManager.swift
- FOUND: Sources/AnyVim/AppDelegate.swift
- FOUND: Sources/AnyVim/MenuBarController.swift
- FOUND: AnyVimTests/PermissionManagerTests.swift
- FOUND: AnyVimTests/LoginItemManagerTests.swift
- FOUND: AnyVimTests/MenuBarControllerTests.swift
- FOUND: commit 89acbe4 (Task 1)
- FOUND: commit 782be3e (Task 2)

---
*Phase: 01-app-shell-and-permissions*
*Completed: 2026-03-31*
