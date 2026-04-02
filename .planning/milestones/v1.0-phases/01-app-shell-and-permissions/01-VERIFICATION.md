---
phase: 01-app-shell-and-permissions
verified: 2026-03-31T21:30:00Z
status: human_needed
score: 5/5 must-haves verified
re_verification: false
human_verification:
  - test: "Menu bar icon and no Dock icon at runtime"
    expected: "character.cursor.ibeam SF Symbol appears in menu bar; no icon in Dock; app absent from Force Quit dialog"
    why_human: "setActivationPolicy(.accessory) + LSUIElement=YES are verified in code, but actual suppression requires launching the .app bundle on a real macOS session — cannot confirm via static analysis"
  - test: "Permission alert flow on first launch"
    expected: "Alert titled 'Accessibility Permission Required' appears with correct body copy including launch-at-login mention; 'Open System Settings' button opens the Accessibility pane"
    why_human: "NSAlert.runModal() requires a live NSRunLoop. The alert code path exists and is wired, but actual modal presentation cannot be confirmed programmatically"
  - test: "Permission re-detection without restart (PERM-03)"
    expected: "After granting Accessibility in System Settings, the app detects it within ~3 seconds; a 'Accessibility permission granted.' notification banner appears; the Input Monitoring alert then shows"
    why_human: "DistributedNotificationCenter + 3s Timer polling is verified in code, but the TCC change signal and live notification delivery require a running app with real permissions"
  - test: "Launch at Login toggle"
    expected: "Menu shows 'Launch at Login' with checkmark on first run; clicking removes checkmark; clicking again restores it; reflects SMAppService live state"
    why_human: "SMAppService.mainApp.register()/unregister() behavior depends on signing identity and system state; cannot be confirmed statically"
---

# Phase 1: App Shell and Permissions Verification Report

**Phase Goal:** A runnable background agent exists with menu bar presence and permission onboarding that does not require app restart after permissions are granted
**Verified:** 2026-03-31T21:30:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | App runs in the menu bar with no Dock icon and persists after the launch terminal closes | ? HUMAN | Code verified: `setActivationPolicy(.accessory)`, `LSUIElement=YES`, `statusItem` retained as instance var; runtime behavior requires human confirmation |
| 2 | App shows actionable guidance when Accessibility or Input Monitoring permission is missing | ? HUMAN | Code verified: `showAccessibilityAlert()` and `showInputMonitoringAlert()` wired in `applicationDidFinishLaunching` and `handlePermissionChange`; modal presentation requires human confirmation |
| 3 | After the user grants a missing permission in System Settings, the app detects it within a few seconds without requiring a restart | ? HUMAN | Code verified: `DistributedNotificationCenter` observer for `"com.apple.accessibility.api"` + `Timer.scheduledTimer(withTimeInterval: 3.0)` both call `checkForChanges(onChange:)` which fires `onChange` on state transition; live TCC signal requires human confirmation |
| 4 | Menu contains a functioning Quit item that terminates the process cleanly | ✓ VERIFIED | `MenuBarController.buildMenu()` adds item with `action: #selector(NSApplication.terminate(_:))`, `keyEquivalent: "q"`; wired; `testBuildMenuContainsQuitItem` passes |
| 5 | App can be configured to launch at login | ? HUMAN | Code verified: `LoginItemManager` wraps `SMAppService.mainApp`; `enableIfFirstRun()` called in `applicationDidFinishLaunching`; `toggleLaunchAtLogin()` wired in menu; SMAppService behavior requires human confirmation |

**Score:** 5/5 truths have passing code-level verification; 4/5 additionally require human runtime confirmation

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `AnyVim.xcodeproj/project.pbxproj` | Xcode project with macOS app target and test target | ✓ VERIFIED | Exists; BUILD SUCCEEDED; 13 tests pass |
| `Sources/AnyVim/AppDelegate.swift` | App entry point with NSStatusItem retained as instance property | ✓ VERIFIED | Contains `@main`, `static func main()`, `private var statusItem: NSStatusItem!`, `setActivationPolicy(.accessory)`, `character.cursor.ibeam`, `isTemplate = true`; all managers wired |
| `Sources/AnyVim/MenuBarController.swift` | Menu construction with Quit item, live permission state, login toggle | ✓ VERIFIED | Contains `Quit AnyVim`, `keyEquivalent: "q"`, `NSApplication.terminate`, `PermissionChecking`, `LoginItemManaging`, live state reads in `buildMenu()` |
| `AnyVim/Info.plist` | LSUIElement=YES and usage description strings | ✓ VERIFIED | Contains `LSUIElement` + `<true/>`, `NSAccessibilityUsageDescription`, `NSInputMonitoringUsageDescription` |
| `AnyVim/AnyVim.entitlements` | Hardened runtime entitlements | ✓ VERIFIED | File exists with `com.apple.security.cs.allow-jit = false` |
| `Sources/AnyVim/PermissionManager.swift` | Permission checking, polling, and System Settings URL opening | ✓ VERIFIED | Contains `protocol PermissionChecking`, `AXIsProcessTrusted()`, `CGPreflightListenEventAccess()`, `com.apple.accessibility.api`, `Timer.scheduledTimer(withTimeInterval: 3.0`, Privacy_Accessibility URL, Privacy_ListenEvent URL; does NOT contain `kAXTrustedCheckOptionPrompt` |
| `Sources/AnyVim/LoginItemManager.swift` | SMAppService register/unregister/status | ✓ VERIFIED | Contains `protocol LoginItemManaging`, `SMAppService.mainApp.status == .enabled`, `SMAppService.mainApp.register()`, `launchAtLoginConfigured` |
| `Sources/AnyVim/NotificationManager.swift` | UNUserNotificationCenter authorization and posting | ✓ VERIFIED | Contains `UNUserNotificationCenter`, `requestAuthorization`, `notifyPermissionGranted`, `permission granted.` |
| `AnyVimTests/PermissionManagerTests.swift` | Unit tests for permission checking via protocol abstraction | ✓ VERIFIED | Contains `MockPermissionChecker`; 6 tests; all pass |
| `AnyVimTests/LoginItemManagerTests.swift` | Unit tests for login item management via protocol abstraction | ✓ VERIFIED | Contains `MockLoginItemService`; 4 tests; all pass |
| `AnyVimTests/MenuBarControllerTests.swift` | Menu structure unit tests | ✓ VERIFIED | 3 tests using `StubPermissionChecker` + `StubLoginItemManager`; all pass |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `AppDelegate.swift` | `MenuBarController.swift` | `statusItem.menu = menuBarController.buildMenu()` | ✓ WIRED | Line 55 and line 75 (rebuild on permission change) |
| `AppDelegate.swift` | `PermissionManager.swift` | `permissionManager.startMonitoring` | ✓ WIRED | Line 63 in `applicationDidFinishLaunching` |
| `PermissionManager.swift` | `MenuBarController.swift` | `menuBarController.buildMenu()` callback in `handlePermissionChange` | ✓ WIRED | `handlePermissionChange` at line 73 calls `menuBarController.buildMenu()` via the `onChange` closure |
| `PermissionManager.swift` | `NotificationManager.swift` | `notificationManager.notifyPermissionGranted` | ✓ WIRED | Lines 79, 89 in `handlePermissionChange` |
| `MenuBarController.swift` | `LoginItemManager.swift` | `loginItemManager.enable()` / `loginItemManager.disable()` | ✓ WIRED | `toggleLaunchAtLogin()` at lines 92–96 |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|--------------|--------|-------------------|--------|
| `MenuBarController.swift` | `permissionManager.isAccessibilityGranted` | `AXIsProcessTrusted()` in `PermissionManager` | Yes — live syscall | ✓ FLOWING |
| `MenuBarController.swift` | `permissionManager.isInputMonitoringGranted` | `CGPreflightListenEventAccess()` in `PermissionManager` | Yes — live syscall | ✓ FLOWING |
| `MenuBarController.swift` | `loginItemManager.isEnabled` | `SMAppService.mainApp.status == .enabled` in `LoginItemManager` | Yes — live OS query | ✓ FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Project builds | `xcodebuild build -scheme AnyVim -destination 'platform=macOS'` | BUILD SUCCEEDED | ✓ PASS |
| All 13 tests pass | `xcodebuild test -scheme AnyVim -destination 'platform=macOS'` | 13 passed, 0 failed | ✓ PASS |
| PermissionManager does not use kAXTrustedCheckOptionPrompt | `grep kAXTrustedCheckOptionPrompt Sources/AnyVim/PermissionManager.swift` | No match | ✓ PASS |
| Commits documented in SUMMARYs exist in git log | `git log --oneline` | `a710007`, `92e9eed`, `89acbe4`, `782be3e`, `f9eb49b`, `a3942a0` all present | ✓ PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| MENU-01 | 01-01-PLAN.md | App runs as a menu bar app with a status icon (no dock icon) | ? HUMAN | `setActivationPolicy(.accessory)` + `LSUIElement=YES` verified in code; runtime dock suppression requires human |
| MENU-03 | 01-01-PLAN.md | Menu includes a Quit option | ✓ SATISFIED | `Quit AnyVim` with `NSApplication.terminate` and `keyEquivalent: "q"` in `MenuBarController.buildMenu()`; test passes |
| MENU-04 | 01-02-PLAN.md | App launches at login (optional, configurable) | ? HUMAN | `LoginItemManager` wraps `SMAppService`; `enableIfFirstRun()` + `toggleLaunchAtLogin()` wired; SMAppService behavior requires human |
| PERM-01 | 01-02-PLAN.md | App checks for Accessibility permission on launch and displays guidance if not granted | ? HUMAN | `showAccessibilityAlert()` called when `!permissionManager.isAccessibilityGranted` in `applicationDidFinishLaunching`; modal requires human |
| PERM-02 | 01-02-PLAN.md | App checks for Input Monitoring permission on launch and displays guidance if not granted | ? HUMAN | `showInputMonitoringAlert()` called from `handlePermissionChange` after Accessibility is granted; modal requires human |
| PERM-03 | 01-02-PLAN.md | App re-checks permission state periodically and updates status accordingly | ? HUMAN | `DistributedNotificationCenter` + `Timer(3.0s)` wired; live TCC re-detection requires human |

No orphaned requirements: MENU-02 is mapped to Phase 6 in REQUIREMENTS.md, not Phase 1.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| None found | — | — | — | — |

No TODO/FIXME/placeholder comments, empty return values, console.log-only handlers, or hardcoded empty state rendering found in any source file. The `updateMenu()` stub from Plan 01 was fully replaced in Plan 02 by `buildMenu()` returning a rebuilt menu.

### Human Verification Required

#### 1. Menu Bar Presence and No Dock Icon (MENU-01)

**Test:** Build and launch `AnyVim.app`. Check the menu bar for the cursor-ibeam icon. Check the Dock for any AnyVim icon. Open Force Quit (Cmd+Opt+Esc) and confirm AnyVim is absent.
**Expected:** Menu bar icon visible, no Dock icon, absent from Force Quit.
**Why human:** `setActivationPolicy(.accessory)` and `LSUIElement=YES` are code-verified, but only a live macOS session confirms actual UI suppression.

#### 2. Permission Alert on First Launch (PERM-01, PERM-02)

**Test:** Reset UserDefaults (`defaults delete com.yourcompany.AnyVim` or use a fresh signing), revoke Accessibility in System Settings, launch the app. Observe whether the alert appears. Click "Open System Settings" and confirm it navigates to Privacy > Accessibility.
**Expected:** Alert titled "Accessibility Permission Required" with body containing "AnyVim needs Accessibility access..." and "AnyVim will also launch at login automatically...". "Open System Settings" opens the correct pane.
**Why human:** `NSAlert.runModal()` requires a live NSRunLoop; conditional branch triggered by `!permissionManager.isAccessibilityGranted` depends on real TCC state.

#### 3. Live Permission Re-Detection Without Restart (PERM-03)

**Test:** With Accessibility not granted, launch the app (dismiss the alert with "Later"). Go to System Settings > Privacy & Security > Accessibility, grant access. Wait up to 5 seconds.
**Expected:** A macOS notification banner appears: title "AnyVim", body "Accessibility permission granted." The Input Monitoring alert then appears automatically without restarting the app. The menu bar dropdown now shows "Accessibility: Granted".
**Why human:** `DistributedNotificationCenter` fires on real TCC changes; `Timer` polling at 3s interval verified in code but real-world TCC signal timing requires a running process.

#### 4. Launch at Login Toggle (MENU-04)

**Test:** On first launch, open the menu and confirm "Launch at Login" has a checkmark. Click it — checkmark should disappear. Open System Settings > General > Login Items and confirm AnyVim was removed. Click "Launch at Login" again — checkmark should return.
**Expected:** SMAppService state toggles correctly; checkmark reflects live state on each menu open.
**Why human:** `SMAppService.mainApp.register()/unregister()` requires a properly signed app; behavior cannot be confirmed without a real process and developer signing identity.

### Gaps Summary

No code-level gaps. All artifacts exist, are substantive (non-stub), are wired to each other, and carry real data (live syscalls — `AXIsProcessTrusted()`, `CGPreflightListenEventAccess()`, `SMAppService.mainApp.status`). The build compiles cleanly and all 13 unit tests pass.

Four items require human verification because they depend on macOS TCC, live NSRunLoop, or SMAppService behavior that cannot be confirmed by static code analysis. These are not code deficiencies — they are the expected boundary of automated verification for a macOS daemon with permission-gated UI flows.

The smoke test in Plan 03 was already executed by a human (per 01-03-SUMMARY.md) and two bugs were found and fixed inline (`f9eb49b`, `a3942a0`). The summary reports all 6 smoke test sections passed. This pre-existing human verification is strong evidence that the phase goal is achieved; the human verification items above are formal checkpoints for this verification report.

---

_Verified: 2026-03-31T21:30:00Z_
_Verifier: Claude (gsd-verifier)_
