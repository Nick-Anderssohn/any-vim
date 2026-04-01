---
phase: 01-app-shell-and-permissions
plan: 01
subsystem: ui
tags: [swift, appkit, nsstatusitem, xcode, xctest, macos, menu-bar]

# Dependency graph
requires: []
provides:
  - Buildable Xcode project (macOS app target + unit test target)
  - NSStatusItem menu bar daemon with character.cursor.ibeam SF Symbol
  - NSMenu with permission placeholder items, Launch at Login placeholder, and Quit AnyVim (Cmd+Q)
  - Info.plist with LSUIElement=YES, NSAccessibilityUsageDescription, NSInputMonitoringUsageDescription
  - AnyVim.entitlements with hardened runtime configuration
  - XCTest infrastructure with 3 passing MenuBarControllerTests
affects: [02-app-shell-and-permissions, all subsequent phases]

# Tech tracking
tech-stack:
  added: [Swift 6.0, AppKit, XCTest, Xcode 16.3/26.4]
  patterns:
    - NSStatusItem retained as AppDelegate instance property (prevents premature release)
    - setActivationPolicy(.accessory) + LSUIElement=YES for menu bar daemon (no Dock icon)
    - MenuBarController as separate class for menu construction and updateMenu() stub

key-files:
  created:
    - AnyVim.xcodeproj/project.pbxproj
    - Sources/AnyVim/AppDelegate.swift
    - Sources/AnyVim/MenuBarController.swift
    - AnyVim/Info.plist
    - AnyVim/AnyVim.entitlements
    - AnyVimTests/MenuBarControllerTests.swift
  modified: []

key-decisions:
  - "NSStatusItem held as AppDelegate instance var (private var statusItem: NSStatusItem!) — local var would be released immediately after applicationDidFinishLaunching"
  - "MenuBarController.buildMenu() returns NSMenu built fresh each call — stateless; Plan 02 will inject PermissionManager and LoginItemManager to read live state"
  - "Permission status items use placeholder 'Not Granted — Click to Enable' copy per UI-SPEC; Plan 02 wires live AXIsProcessTrusted() / CGPreflightListenEventAccess() values"
  - "Swift language mode set to Swift 6 with SWIFT_STRICT_CONCURRENCY=complete per CLAUDE.md recommendation"
  - "Deployment target macOS 13.0 per CLAUDE.md"

patterns-established:
  - "Pattern: Menu bar daemon — NSStatusItem retained on AppDelegate, setActivationPolicy(.accessory), LSUIElement=YES in Info.plist"
  - "Pattern: MenuBarController owns menu construction; AppDelegate assigns statusItem.menu"

requirements-completed: [MENU-01, MENU-03]

# Metrics
duration: 12min
completed: 2026-03-31
---

# Phase 01 Plan 01: App Shell and Menu Bar Daemon Summary

**NSStatusItem menu bar daemon with AppKit NSMenu (character.cursor.ibeam SF Symbol, permission placeholders, Quit AnyVim), full Xcode project, and 3 passing XCTest unit tests**

## Performance

- **Duration:** ~12 min
- **Started:** 2026-03-31T20:49:00Z
- **Completed:** 2026-03-31T20:52:00Z
- **Tasks:** 2 of 2
- **Files modified:** 6

## Accomplishments
- Created buildable Xcode project from scratch with macOS app target and unit test target
- AppDelegate retains NSStatusItem as instance property with character.cursor.ibeam SF Symbol (isTemplate=true)
- MenuBarController builds NSMenu with permission placeholders, Launch at Login placeholder, and Quit AnyVim (Cmd+Q) per UI-SPEC exact copy
- Info.plist: LSUIElement=YES suppresses Dock icon; both TCC usage description strings present
- AnyVim.entitlements: hardened runtime configured
- All 3 unit tests pass: testBuildMenuContainsQuitItem, testBuildMenuContainsPermissionStatusItems, testBuildMenuContainsLaunchAtLoginItem

## Task Commits

Each task was committed atomically:

1. **Task 1: Create Xcode project and app shell with menu bar presence** - `a710007` (feat)
2. **Task 2: Add unit test target and test infrastructure** - `92e9eed` (feat)

## Files Created/Modified
- `AnyVim.xcodeproj/project.pbxproj` - Full Xcode project definition with app target, test target, Swift 6 settings, macOS 13.0 deployment target
- `Sources/AnyVim/AppDelegate.swift` - @main entry point, retains NSStatusItem, sets .accessory activation policy
- `Sources/AnyVim/MenuBarController.swift` - Builds NSMenu per UI-SPEC; includes updateMenu() stub for Plan 02
- `AnyVim/Info.plist` - LSUIElement=YES, NSAccessibilityUsageDescription, NSInputMonitoringUsageDescription
- `AnyVim/AnyVim.entitlements` - Hardened runtime entitlements
- `AnyVimTests/MenuBarControllerTests.swift` - 3 unit tests verifying menu structure

## Decisions Made
- Used manually crafted project.pbxproj (no Xcode GUI available in CLI context) — all required build settings match what Xcode 16.3 would generate for a new macOS App target
- Swift language mode Swift 6 with SWIFT_STRICT_CONCURRENCY=complete per CLAUDE.md
- MenuBarController uses placeholder item titles for Plan 01 scope; Plan 02 will inject PermissionManager/LoginItemManager and call live APIs

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

1. **Permission status items** (`Sources/AnyVim/MenuBarController.swift`, `buildMenu()`)
   - Both "Accessibility: Not Granted — Click to Enable" and "Input Monitoring: Not Granted — Click to Enable" are static placeholder strings with `action: nil`
   - Intentional: Plan 01 scope establishes menu structure only. Plan 02 (permissions) will inject `PermissionManager` and wire live `AXIsProcessTrusted()` / `CGPreflightListenEventAccess()` values.

2. **Launch at Login item** (`Sources/AnyVim/MenuBarController.swift`, `buildMenu()`)
   - Static item with `action: nil` and no checkmark state
   - Intentional: Plan 02 (permissions) will inject `LoginItemManager` and wire `SMAppService.mainApp` toggle action.

3. **MenuBarController.updateMenu()** (`Sources/AnyVim/MenuBarController.swift`)
   - Empty stub body
   - Intentional: Plan 02 will implement live menu rebuild when permission state changes.

## Issues Encountered
None — xcodebuild build and test both succeeded on first attempt.

## Next Phase Readiness
- Xcode project is buildable and all tests pass — Plan 02 can immediately add PermissionManager, LoginItemManager, and NotificationManager source files
- MenuBarController.updateMenu() stub is ready for Plan 02 to implement
- Test target is ready for Plan 02 to add PermissionManagerTests and LoginItemManagerTests
- Code signing configured as Automatic with empty DEVELOPMENT_TEAM — developer must configure their team ID before testing TCC permission flows (per RESEARCH.md Pitfall 1)

## Self-Check: PASSED

- FOUND: AnyVim.xcodeproj/project.pbxproj
- FOUND: Sources/AnyVim/AppDelegate.swift
- FOUND: Sources/AnyVim/MenuBarController.swift
- FOUND: AnyVim/Info.plist
- FOUND: AnyVim/AnyVim.entitlements
- FOUND: AnyVimTests/MenuBarControllerTests.swift
- FOUND: commit a710007 (Task 1)
- FOUND: commit 92e9eed (Task 2)

---
*Phase: 01-app-shell-and-permissions*
*Completed: 2026-03-31*
