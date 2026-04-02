---
phase: 4
slug: vim-session
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-01
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (built into Xcode) |
| **Config file** | AnyVim.xcodeproj (test target: AnyVimTests) |
| **Quick run command** | `xcodebuild test -project AnyVim.xcodeproj -scheme AnyVim -destination 'platform=macOS'` |
| **Full suite command** | `xcodebuild test -project AnyVim.xcodeproj -scheme AnyVim -destination 'platform=macOS'` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `xcodebuild test -project AnyVim.xcodeproj -scheme AnyVim -destination 'platform=macOS'`
- **After every plan wave:** Run `xcodebuild test -project AnyVim.xcodeproj -scheme AnyVim -destination 'platform=macOS'`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 04-01-01 | 01 | 0 | VIM-01 | unit | `xcodebuild test ... -only-testing:AnyVimTests/VimSessionManagerTests` | ❌ W0 | ⬜ pending |
| 04-01-02 | 01 | 0 | VIM-02 | unit | `xcodebuild test ... -only-testing:AnyVimTests/VimSessionManagerTests` | ❌ W0 | ⬜ pending |
| 04-01-03 | 01 | 0 | VIM-03 | unit | `xcodebuild test ... -only-testing:AnyVimTests/VimSessionManagerTests` | ❌ W0 | ⬜ pending |
| 04-01-04 | 01 | 0 | VIM-04 | unit | `xcodebuild test ... -only-testing:AnyVimTests/VimSessionManagerTests` | ❌ W0 | ⬜ pending |
| 04-02-01 | 02 | 1 | D-05 | unit | `xcodebuild test ... -only-testing:AnyVimTests/VimSessionManagerTests` | ❌ W0 | ⬜ pending |
| 04-02-02 | 02 | 1 | D-08 | unit | `xcodebuild test ... -only-testing:AnyVimTests/VimSessionManagerTests` | ❌ W0 | ⬜ pending |
| 04-02-03 | 02 | 1 | D-09 | unit (mock) | `xcodebuild test ... -only-testing:AnyVimTests/VimSessionManagerTests` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `AnyVimTests/VimSessionManagerTests.swift` — test stubs for VIM-01 through VIM-04, D-05, D-08, D-09
- [ ] Add SwiftTerm 1.13.0 SPM package to AnyVim.xcodeproj — required before VimSessionManager compiles

*Wave 0 must be first plan — everything else depends on SwiftTerm being available.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Floating window appears above other apps | VIM-01, D-03 | Requires visual confirmation of window level | Open vim session, switch to another app, verify vim window stays on top |
| Keyboard input works in vim | VIM-02 | Requires interactive keyboard testing | Open vim session, type text, verify characters appear in vim |
| ~/.vimrc applied | VIM-02 | Requires visual inspection of vim settings | Open vim session, verify custom vimrc settings are visible |
| Window drag and close button | D-04, D-07 | Requires mouse interaction | Drag title bar, click close button, verify abort behavior |
| Light/dark mode colors | D-11 | Requires visual inspection | Toggle system appearance, verify terminal colors adapt |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
