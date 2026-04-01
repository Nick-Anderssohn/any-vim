---
phase: 3
slug: accessibility-bridge-and-clipboard
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-01
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (built-in) |
| **Config file** | `AnyVimTests/` directory |
| **Quick run command** | `xcodebuild test -scheme AnyVim -only-testing AnyVimTests -quiet` |
| **Full suite command** | `xcodebuild test -scheme AnyVim -quiet` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `xcodebuild test -scheme AnyVim -only-testing AnyVimTests -quiet`
- **After every plan wave:** Run `xcodebuild test -scheme AnyVim -quiet`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 03-01-01 | 01 | 1 | CAPT-01 | unit | `xcodebuild test -scheme AnyVim -only-testing AnyVimTests/ClipboardGuardTests -quiet` | ❌ W0 | ⬜ pending |
| 03-01-02 | 01 | 1 | CAPT-03 | unit | `xcodebuild test -scheme AnyVim -only-testing AnyVimTests/ClipboardGuardTests -quiet` | ❌ W0 | ⬜ pending |
| 03-01-03 | 01 | 1 | CAPT-02 | unit | `xcodebuild test -scheme AnyVim -only-testing AnyVimTests/TextCaptureTests -quiet` | ❌ W0 | ⬜ pending |
| 03-02-01 | 02 | 2 | COMPAT-01 | manual | N/A — requires Accessibility permission | N/A | ⬜ pending |
| 03-02-02 | 02 | 2 | COMPAT-02 | manual | N/A — requires Accessibility permission | N/A | ⬜ pending |
| 03-02-03 | 02 | 2 | COMPAT-03 | manual | N/A — requires Accessibility permission | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `AnyVimTests/ClipboardGuardTests.swift` — stubs for CAPT-01, CAPT-03 (clipboard save/restore)
- [ ] `AnyVimTests/TextCaptureTests.swift` — stubs for CAPT-02 (empty field handling)
- [ ] Protocol-based mocks for AXUIElement and NSPasteboard to enable unit testing without Accessibility permission

*Existing XCTest infrastructure from Phase 1/2 covers framework needs.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Text capture from native Cocoa apps | COMPAT-01 | Requires real Accessibility permission and running apps | 1. Open TextEdit with text 2. Trigger capture 3. Verify text matches |
| Text capture from browser text areas | COMPAT-02 | Requires real browser with Accessibility | 1. Open Safari/Chrome textarea 2. Trigger capture 3. Verify text matches |
| Paste-back to original field | COMPAT-03 | Requires real app focus and Accessibility | 1. Capture text 2. Modify 3. Paste back 4. Verify field updated |
| Clipboard preservation across all exit paths | CAPT-03 | Requires real pasteboard interaction | 1. Copy known text 2. Trigger full cycle 3. Verify clipboard restored |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
