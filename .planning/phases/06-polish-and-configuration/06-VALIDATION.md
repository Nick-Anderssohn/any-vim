---
phase: 6
slug: polish-and-configuration
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-02
---

# Phase 6 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (Xcode 16.3) |
| **Config file** | AnyVim.xcodeproj |
| **Quick run command** | `xcodebuild -scheme AnyVim -destination 'platform=macOS' test` |
| **Full suite command** | `xcodebuild -scheme AnyVim -destination 'platform=macOS' test` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `xcodebuild -scheme AnyVim -destination 'platform=macOS' test`
- **After every plan wave:** Run `xcodebuild -scheme AnyVim -destination 'platform=macOS' test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 06-01-01 | 01 | 1 | MENU-02 | unit | `xcodebuild -scheme AnyVim -destination 'platform=macOS' test -only-testing:AnyVimTests/MenuBarControllerTests` | ❌ W0 | ⬜ pending |
| 06-01-02 | 01 | 1 | MENU-02 | unit | `xcodebuild -scheme AnyVim -destination 'platform=macOS' test -only-testing:AnyVimTests/EditCycleCoordinatorTests` | ❌ W0 | ⬜ pending |
| 06-01-03 | 01 | 1 | CONF-01 | unit | `xcodebuild -scheme AnyVim -destination 'platform=macOS' test -only-testing:AnyVimTests/VimSessionManagerTests` | ❌ W0 | ⬜ pending |
| 06-01-04 | 01 | 1 | CONF-01 | unit | `xcodebuild -scheme AnyVim -destination 'platform=macOS' test -only-testing:AnyVimTests/MenuBarControllerTests` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `AnyVimTests/MenuBarControllerTests.swift` — add vim path section tests (CONF-01: path display, invalid path display, reset action) and icon state tests (MENU-02)
- [ ] `AnyVimTests/VimSessionManagerTests.swift` — add `UserDefaultsVimPathResolver` unit tests (CONF-01: valid custom, invalid custom, nil custom)
- [ ] `AnyVimTests/EditCycleCoordinatorTests.swift` — add icon-state assertions in existing trigger tests (MENU-02: icon restores on all exit paths)

*Existing test infrastructure covers framework and config — only new test methods are needed.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Menu bar icon visually changes during active session | MENU-02 | NSStatusItem rendering requires running app with menu bar | 1. Build and run AnyVim 2. Double-tap Control to trigger 3. Observe menu bar icon changes to pencil symbol 4. :wq in vim 5. Observe icon restores to cursor beam |
| NSOpenPanel file picker opens and allows binary selection | CONF-01 | NSOpenPanel requires user interaction and filesystem access | 1. Click menu bar icon 2. Click "Set Vim Path..." 3. Navigate to /opt/homebrew/bin/vim 4. Select and confirm 5. Verify menu shows new path |
| Dark/light mode icon adaptation | MENU-02 | Requires visual inspection in both appearances | 1. Set system to dark mode 2. Trigger edit session 3. Verify icon adapts correctly 4. Repeat in light mode |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
