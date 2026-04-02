---
phase: 02
slug: global-hotkey-detection
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-31
---

# Phase 02 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (Xcode built-in) |
| **Config file** | AnyVim.xcodeproj test target |
| **Quick run command** | `xcodebuild test -project AnyVim.xcodeproj -scheme AnyVim -destination 'platform=macOS'` |
| **Full suite command** | `xcodebuild test -project AnyVim.xcodeproj -scheme AnyVim -destination 'platform=macOS'` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `xcodebuild test -project AnyVim.xcodeproj -scheme AnyVim -destination 'platform=macOS'`
- **After every plan wave:** Run full suite
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 02-01-01 | 01 | 1 | HOTKEY-01 | unit (protocol mock) | `xcodebuild test ... -only-testing:HotkeyManagerTests/testTapInstallsWhenPermissionsGranted` | ❌ W0 | ⬜ pending |
| 02-01-02 | 01 | 1 | HOTKEY-01 | unit (protocol mock) | `xcodebuild test ... -only-testing:HotkeyManagerTests/testTapSkipsInstallWhenAccessibilityMissing` | ❌ W0 | ⬜ pending |
| 02-01-03 | 01 | 1 | HOTKEY-02 | unit (state machine) | `xcodebuild test ... -only-testing:HotkeyManagerTests/testDoubleTapWithin350msFires` | ❌ W0 | ⬜ pending |
| 02-01-04 | 01 | 1 | HOTKEY-02 | unit (state machine) | `xcodebuild test ... -only-testing:HotkeyManagerTests/testDoubleTapOutside350msDoesNotFire` | ❌ W0 | ⬜ pending |
| 02-01-05 | 01 | 1 | HOTKEY-02 | unit (state machine) | `xcodebuild test ... -only-testing:HotkeyManagerTests/testSingleTapDoesNotFire` | ❌ W0 | ⬜ pending |
| 02-01-06 | 01 | 1 | HOTKEY-02 | unit (state machine) | `xcodebuild test ... -only-testing:HotkeyManagerTests/testHeldControlDoesNotFire` | ❌ W0 | ⬜ pending |
| 02-01-07 | 01 | 1 | HOTKEY-02 | unit (state machine) | `xcodebuild test ... -only-testing:HotkeyManagerTests/testInterveningKeyResetsStateMachine` | ❌ W0 | ⬜ pending |
| 02-01-08 | 01 | 1 | HOTKEY-03 | manual | N/A — requires live CGEventTap | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `AnyVimTests/HotkeyManagerTests.swift` — test stubs for all HOTKEY-01 and HOTKEY-02 unit tests
- [ ] `MockHotkeyTapInstaller` (in test file or shared fixture) — protocol mock for CGEvent tap creation, so tests never require live TCC permissions

*Existing test infrastructure: `PermissionManagerTests.swift`, `LoginItemManagerTests.swift`, `MenuBarControllerTests.swift` — all passing. `MockPermissionChecker` already implements `PermissionChecking` and is reusable.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Double-tap Control fires from any app | HOTKEY-03 | Requires live CGEventTap with TCC permissions; cannot unit test system-wide event interception | 1. Launch AnyVim with permissions granted 2. Open Safari, Terminal, and TextEdit 3. Double-tap Control in each — verify trigger fires 4. Single-tap, hold, and Ctrl+key combos should NOT trigger |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
