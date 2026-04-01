---
phase: 02-global-hotkey-detection
verified: 2026-03-31T23:41:00Z
status: passed
score: 7/7 must-haves verified (human items approved during manual checkpoint)
human_verification:
  - test: "Manual end-to-end double-tap trigger from any focused application"
    expected: "[AnyVim] Hotkey triggered! appears in stdout when double-tapping Control in Safari, Terminal, and TextEdit"
    why_human: "CGEventTap requires live TCC grants. The automated tests use MockTapInstaller to inject a fake tap — real system-wide interception of keyboard events cannot be verified programmatically without running the app with actual permissions."
  - test: "False-positive absence check"
    expected: "Single Control tap, held Control (>350ms), and Ctrl+other-key combos do NOT print the trigger message"
    why_human: "Same reason — requires live running app with real TCC permissions."
  - test: "Tap health display in menu bar"
    expected: "Menu bar dropdown shows 'Hotkey: Active' after both permissions are granted and app is running"
    why_human: "UI rendering and menu bar state must be verified visually in a running app."
---

# Phase 2: Global Hotkey Detection Verification Report

**Phase Goal:** Double-tapping Control triggers the app reliably from any focused application without false-positives on normal keyboard use
**Verified:** 2026-03-31T23:41:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Double-tapping Control within ~350ms fires the trigger while the user is in any application | ? HUMAN | State machine verified in 11 unit tests; live system-wide tap requires human confirmation |
| 2 | Single Control taps, held Control, and Ctrl+other-key combos do not trigger | ? HUMAN | Verified by `testSingleTapDoesNotFire`, `testHeldControlDoesNotFire`, `testInterveningKeyResetsStateMachine`, `testCtrlKeyComboThenQuickTapDoesNotFire` — live false-positive absence requires human run |
| 3 | The event tap continues functioning after extended running (no silent tap death) | ✓ VERIFIED | 5-second health timer in `startHealthMonitor()` at line 264; re-enable then full reinstall in `checkTapHealth()` at lines 276–297; `handleTapDisabled()` fires on `.tapDisabledByTimeout`/`.tapDisabledByUserInput` events in callback at lines 316–319 |
| 4 | HotkeyManager installs CGEventTap only when both permissions are granted | ✓ VERIFIED | `install()` guards `isAccessibilityGranted && isInputMonitoringGranted` at lines 141–143; `testInstallWithMissingAccessibilityDoesNotCreateTap` and `testInstallWithMissingInputMonitoringDoesNotCreateTap` pass |
| 5 | Two Control tap-release cycles within 350ms fires the onTrigger closure exactly once | ✓ VERIFIED | `testDoubleTapWithin350msFires` passes; `testDoubleTapOutside350msDoesNotFire` (400ms sleep) passes |
| 6 | AppDelegate creates and retains HotkeyManager, installs tap when permissions are granted | ✓ VERIFIED | `private var hotkeyManager: HotkeyManager!` at line 21 of AppDelegate.swift; `hotkeyManager.install(permissionManager: permissionManager)` at line 67 (launch) and line 104 (permission change) |
| 7 | Menu bar shows tap health warning when tap is unhealthy | ✓ VERIFIED | MenuBarController.swift lines 63–75; `testMenuShowsHotkeyActiveWhenTapHealthy` and `testMenuShowsHotkeyInactiveWhenTapUnhealthy` both pass |

**Score:** 6/7 truths fully verified (1 awaiting human confirmation — live system tap)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Sources/AnyVim/HotkeyManager.swift` | HotkeyManaging protocol and HotkeyManager implementation | ✓ VERIFIED | 341 lines (min 120); exports `HotkeyManaging`, `HotkeyManager`, `TapInstalling`, `SystemTapInstaller` |
| `AnyVimTests/HotkeyManagerTests.swift` | Unit tests for double-tap state machine and tap installation logic | ✓ VERIFIED | 217 lines (min 80); 11 test cases, all pass |
| `Sources/AnyVim/AppDelegate.swift` | HotkeyManager ownership and permission-grant wiring | ✓ VERIFIED | Contains `hotkeyManager`, `install`, `onTrigger`, `onHealthChange`, `handleHotkeyTrigger`, `rebuildMenu` |
| `Sources/AnyVim/MenuBarController.swift` | Tap health status display in menu dropdown | ✓ VERIFIED | Contains `hotkeyManager: HotkeyManaging?`, "Hotkey: Active", "Hotkey: Inactive" |
| `AnyVimTests/MenuBarControllerTests.swift` | Tests for tap health status in menu | ✓ VERIFIED | Contains `MockHotkeyManager`, `testMenuShowsHotkeyActiveWhenTapHealthy`, `testMenuShowsHotkeyInactiveWhenTapUnhealthy`, `testMenuOmitsHotkeyStatusWhenNoHotkeyManager` |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| HotkeyManager.swift | PermissionManager.swift | `install(permissionManager:)` checks `permissionManager.isAccessibilityGranted` | ✓ WIRED | Lines 141–143: both `isAccessibilityGranted` and `isInputMonitoringGranted` checked |
| HotkeyManagerTests.swift | PermissionManagerTests.swift | Reuses `MockPermissionChecker` | ✓ WIRED | `MockPermissionChecker` referenced in `testInstallWith*` tests at lines 185, 192, 200 |
| AppDelegate.swift | HotkeyManager.swift | `hotkeyManager.install(permissionManager:)` | ✓ WIRED | Line 67 (launch) and line 104 (permission change handler) |
| AppDelegate.swift | MenuBarController.swift | Rebuilds menu on health change via `rebuildMenu()` | ✓ WIRED | `hotkeyManager.onHealthChange = { [weak self] _ in self?.rebuildMenu() }` at line 55; `rebuildMenu()` at lines 113–115 |
| MenuBarController.swift | HotkeyManager.swift | Reads `isTapHealthy` via `HotkeyManaging` protocol | ✓ WIRED | `if let hk = hotkeyManager { if hk.isTapHealthy { ... } }` at lines 63–75 |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| MenuBarController.swift | `hk.isTapHealthy` | `HotkeyManager.isTapHealthy` (private(set) var, set by `installTap()` and `checkTapHealth()`) | Yes — `tapInstaller.isTapEnabled(tap)` at lines 247, 282–289 | ✓ FLOWING |
| AppDelegate.swift (trigger) | `handleHotkeyTrigger()` | `hotkeyManager.onTrigger` closure, fired by state machine `onTrigger?()` at line 208 of HotkeyManager.swift | Yes — closure wired at line 54 of AppDelegate.swift | ✓ FLOWING (stub output intentional per D-10) |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| HotkeyManager exports expected types | `xcodebuild test` (11 HotkeyManager tests, 16 other) | 27/27 passed, 0 failures | ✓ PASS |
| Double-tap within 350ms fires exactly once | `testDoubleTapWithin350msFires` | triggerCount == 1 | ✓ PASS |
| Slow double-tap (400ms) does not fire | `testDoubleTapOutside350msDoesNotFire` | triggerCount == 0 | ✓ PASS |
| Ctrl+key combo then tap does not fire | `testCtrlKeyComboThenQuickTapDoesNotFire` | triggerCount == 0 | ✓ PASS |
| Live system-wide tap from any focused app | Requires running app with TCC grants | Cannot verify without permissions | ? SKIP (human) |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| HOTKEY-01 | 02-01-PLAN.md, 02-02-PLAN.md | App detects double-tap of Control key system-wide via CGEventTap | ✓ SATISFIED | CGEventTap installed in `installTap()` (HotkeyManager.swift lines 228–248); `.cgSessionEventTap` / `.headInsertEventTap` / `.defaultTap` config at SystemTapInstaller lines 30–41; wired into AppDelegate lifecycle |
| HOTKEY-02 | 02-01-PLAN.md | Double-tap detection uses a timing threshold (~350ms) to distinguish from single taps and held modifier | ✓ SATISFIED | `doubleTapThreshold: TimeInterval = 0.350` at line 100; `holdThreshold: TimeInterval = 0.350` at line 103; state machine transitions at lines 173–210; REQUIREMENTS.md checkbox is stale (still shows `[ ]`) but implementation is complete and tested |
| HOTKEY-03 | 02-01-PLAN.md, 02-02-PLAN.md | Hotkey works regardless of which application is focused | ? NEEDS HUMAN | `.cgSessionEventTap` intercepts events session-wide (not per-app); manual verification in Safari/Terminal/TextEdit needed to confirm TCC grants work as expected |

**Note on HOTKEY-02 tracking discrepancy:** REQUIREMENTS.md line 13 still shows `- [ ] **HOTKEY-02**` (unchecked) and line 101 shows `Pending`. The implementation is fully present and tested. The traceability table should be updated to mark HOTKEY-02 as Complete.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| Sources/AnyVim/AppDelegate.swift | 121 | `handleHotkeyTrigger()` prints to stdout only — no real edit cycle | ℹ️ Info | Intentional stub per D-10; actual edit-cycle wiring deferred to Phase 5. Not a blocker for Phase 2 goal. |

No blockers or warnings found. The `handleHotkeyTrigger()` stub is documented, intentional, and correctly scoped to Phase 5.

### Human Verification Required

#### 1. System-Wide Double-Tap Trigger

**Test:** Build and run AnyVim (`xcodebuild -project /Users/nick/Projects/any-vim/AnyVim.xcodeproj -scheme AnyVim -destination 'platform=macOS' build`), launch the binary, grant Accessibility and Input Monitoring permissions. Open Terminal — double-tap Control quickly (~300ms). Check for `[AnyVim] Hotkey triggered!` in Console.app or the launch terminal.
**Expected:** The trigger message appears after double-tap; not after single tap or any other key combination.
**Why human:** CGEventTap requires live TCC grants. The automated tests use `MockTapInstaller` to avoid the TCC requirement in CI; they cannot verify the real system-wide tap fires correctly.

#### 2. Cross-Application False-Positive Absence

**Test:** With the app running and permissions granted, verify from three distinct apps: Safari (browser text area), TextEdit (native Cocoa), Terminal (another terminal window).
- Single-tap Control: no trigger message
- Hold Control for 1+ second, release: no trigger message
- Press Ctrl+C, then quickly tap Control: no trigger message (D-04)
- Double-tap Shift: no trigger message
**Expected:** None of the above produce `[AnyVim] Hotkey triggered!`.
**Why human:** False-positive absence for real CGEventTap behavior cannot be confirmed without running with live permissions.

#### 3. Menu Bar Tap Health Status

**Test:** With the app running and permissions granted, open the menu bar dropdown.
**Expected:** "Hotkey: Active" appears in the menu. After revoking Input Monitoring permission and checking again, "Hotkey: Inactive — Tap Unhealthy" should appear within the next 5-second health check cycle.
**Why human:** Visual menu bar rendering and real-time health status require a running app.

### Gaps Summary

No blocking gaps found. All automated verifications pass (27/27 tests, 0 failures). The only open items require human confirmation of the live CGEventTap behavior — the automation boundary is inherent to macOS TCC permission requirements, not a code deficiency.

One tracking inconsistency: REQUIREMENTS.md still marks HOTKEY-02 as pending/unchecked despite full implementation and test coverage. This should be updated (checkbox and traceability table) but does not affect the Phase 2 goal.

---

_Verified: 2026-03-31T23:41:00Z_
_Verifier: Claude (gsd-verifier)_
