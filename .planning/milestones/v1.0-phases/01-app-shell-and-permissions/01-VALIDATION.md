---
phase: 1
slug: app-shell-and-permissions
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-31
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (built into Xcode) |
| **Config file** | Configured within Xcode project (Unit Test target) |
| **Quick run command** | `xcodebuild test -scheme AnyVim -destination 'platform=macOS'` |
| **Full suite command** | `xcodebuild test -scheme AnyVim -destination 'platform=macOS'` |
| **Estimated runtime** | ~10 seconds |

---

## Sampling Rate

- **After every task commit:** Run `xcodebuild build -scheme AnyVim`
- **After every plan wave:** Run `xcodebuild test -scheme AnyVim -destination 'platform=macOS'`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 01-01-01 | 01 | 1 | MENU-01 | Manual smoke | Launch app, verify no Dock icon | N/A | ⬜ pending |
| 01-01-02 | 01 | 1 | MENU-03 | Manual smoke | Click Quit in menu bar | N/A | ⬜ pending |
| 01-01-03 | 01 | 1 | MENU-04 | Unit | `xcodebuild test -only-testing:AnyVimTests/LoginItemManagerTests` | ❌ W0 | ⬜ pending |
| 01-01-04 | 01 | 1 | PERM-01 | Unit | `xcodebuild test -only-testing:AnyVimTests/PermissionManagerTests` | ❌ W0 | ⬜ pending |
| 01-01-05 | 01 | 1 | PERM-02 | Unit | `xcodebuild test -only-testing:AnyVimTests/PermissionManagerTests` | ❌ W0 | ⬜ pending |
| 01-01-06 | 01 | 1 | PERM-03 | Manual | Grant/revoke in System Settings while app runs | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] Xcode Unit Test target added to project (`AnyVimTests`) — required before any test file can run
- [ ] Signing identity configured in project settings — required before any TCC permission testing
- [ ] `AnyVimTests/PermissionManagerTests.swift` — stubs for PERM-01, PERM-02 with mock permission checker protocol
- [ ] `AnyVimTests/LoginItemManagerTests.swift` — stubs for MENU-04 with mock SMAppService wrapper

*If none: "Existing infrastructure covers all phase requirements."*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| App runs without Dock icon | MENU-01 | Dock state not introspectable via XCTest | Launch app, verify no icon appears in Dock, only menu bar |
| Quit menu item terminates process | MENU-03 | NSStatusItem not accessible from unit tests | Click Quit in menu bar dropdown, verify process exits |
| Permission status updates within 3s | PERM-03 | TCC state cannot be automated in tests | Grant permission in System Settings while app runs, verify detection within 3s |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
