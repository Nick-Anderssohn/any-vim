---
phase: 5
slug: edit-cycle-integration
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-01
---

# Phase 5 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (built into Xcode 16.3) |
| **Config file** | `AnyVimTests/` directory |
| **Quick run command** | `xcodebuild test -project AnyVim.xcodeproj -scheme AnyVim -destination 'platform=macOS' -only-testing:AnyVimTests/EditCycleCoordinatorTests` |
| **Full suite command** | `xcodebuild test -project AnyVim.xcodeproj -scheme AnyVim -destination 'platform=macOS'` |
| **Estimated runtime** | ~10 seconds |

---

## Sampling Rate

- **After every task commit:** Run quick run command (EditCycleCoordinatorTests only)
- **After every plan wave:** Run full suite command
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 05-01-01 | 01 | 0 | REST-01, REST-03, REST-05 | unit | `xcodebuild test -project AnyVim.xcodeproj -scheme AnyVim -destination 'platform=macOS' -only-testing:AnyVimTests/EditCycleCoordinatorTests` | ❌ W0 | ⬜ pending |
| 05-01-02 | 01 | 1 | REST-01 | unit | `xcodebuild test -project AnyVim.xcodeproj -scheme AnyVim -destination 'platform=macOS' -only-testing:AnyVimTests/EditCycleCoordinatorTests/testSavedExitCallsRestoreTextWithEditedContent` | ❌ W0 | ⬜ pending |
| 05-01-03 | 01 | 1 | REST-03 | unit | `xcodebuild test -project AnyVim.xcodeproj -scheme AnyVim -destination 'platform=macOS' -only-testing:AnyVimTests/EditCycleCoordinatorTests/testAbortedExitCallsAbortAndRestore` | ❌ W0 | ⬜ pending |
| 05-01-04 | 01 | 1 | REST-05 | unit | `xcodebuild test -project AnyVim.xcodeproj -scheme AnyVim -destination 'platform=macOS' -only-testing:AnyVimTests/EditCycleCoordinatorTests/testTempFileDeletedAfterSave` | ❌ W0 | ⬜ pending |
| 05-01-05 | 01 | 1 | REST-04 | unit | `xcodebuild test -project AnyVim.xcodeproj -scheme AnyVim -destination 'platform=macOS' -only-testing:AnyVimTests/EditCycleCoordinatorTests/testReentrancyGuardBlocksSecondTrigger` | ❌ W0 | ⬜ pending |
| 05-02-01 | 02 | 2 | REST-01, REST-02, REST-03, REST-04, REST-05 | manual | N/A — manual smoke test | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `AnyVimTests/EditCycleCoordinatorTests.swift` — test stubs for edit cycle orchestration (REST-01, REST-03, REST-04, REST-05)
- [ ] Mock protocols for AccessibilityBridge, VimSessionManager, TempFileManager if not already testable via protocols

*Existing test infrastructure (XCTest, project structure) already in place from Phase 1.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| :wq pastes edited text into original field | REST-01 | Requires real app focus, clipboard, accessibility | Trigger in TextEdit, edit, :wq, verify text replaced |
| :q! leaves field unchanged | REST-02 | Requires real app focus, clipboard, accessibility | Trigger in TextEdit, edit, :q!, verify text unchanged |
| Clipboard restored after cycle | REST-03 | Requires real pasteboard interaction | Copy something, trigger, :wq/:q!, paste — original content |
| Double-trigger ignored | REST-04 | Requires real hotkey timing | Double-tap Control twice rapidly, verify single window |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
