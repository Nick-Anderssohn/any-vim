# Project Retrospective

*A living document updated after each milestone. Lessons feed forward into future planning.*

## Milestone: v1.0 — MVP

**Shipped:** 2026-04-02
**Phases:** 6 | **Plans:** 14

### What Was Built
- Complete trigger-grab-edit-paste loop: double-tap Control → capture text → vim in floating window → :wq pastes back
- Menu bar daemon with permission onboarding that auto-detects grants without restart
- CGEventTap-based double-tap detection with health monitoring and automatic tap reinstall
- Accessibility bridge using Cmd+A/Cmd+C/Cmd+V with full clipboard preservation
- SwiftTerm-hosted vim session with mtime-based :wq/:q! detection
- Configurable vim path and visual session indicator (icon swap)

### What Worked
- Protocol-driven architecture from Phase 1 made every subsequent phase testable without real macOS permissions
- Manual verification plans (odd-numbered plans like 01-03, 03-03) caught real bugs (hidesOnDeactivate, trailing newline)
- Mtime-based exit detection was simple and reliable — avoided complex IPC or exit code parsing
- Each phase had clear boundaries — no scope creep between phases
- 67 unit tests provided confidence that cross-phase wiring didn't break earlier work

### What Was Inefficient
- Nyquist validation files created for all phases but only Phase 5 was fully validated — draft VALIDATION.md files accumulated as tech debt
- REQUIREMENTS.md checkbox for HOTKEY-02 was never updated after implementation — manual traceability tracking drifted
- Some SUMMARY.md files lack requirements_completed frontmatter — inconsistent metadata

### Patterns Established
- Protocol + mock pattern for macOS system APIs (PasteboardAccessing, KeystrokeSending, TapInstalling, etc.)
- Manual verification as a dedicated plan (not ad-hoc) for human-only testable behaviors
- Icon swap via defer block to guarantee restore on all exit paths
- Static menu labels for items that would block main thread (ShellVimPathResolver)

### Key Lessons
1. NSPanel defaults `hidesOnDeactivate = true` — always set to `false` for floating utility windows
2. Vim always appends a trailing newline on save — must strip before paste-back
3. Developer signing is required from the very first commit for TCC to work — ad-hoc signing won't register in System Settings
4. CGEventTap can be silently disabled by code-signing changes — periodic health checks are essential
5. Cmd+A/Cmd+C/Cmd+V needs timing delays (150-200ms) between keystrokes to avoid races

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Phases | Plans | Key Change |
|-----------|--------|-------|------------|
| v1.0 | 6 | 14 | Initial project — established protocol-driven testing pattern |

### Cumulative Quality

| Milestone | Tests | LOC | Requirements |
|-----------|-------|-----|-------------|
| v1.0 | 67 | 9,540 | 27/27 |

### Top Lessons (Verified Across Milestones)

1. Protocol abstractions for system APIs pay for themselves in testability — every phase benefited
2. Manual verification plans catch bugs that unit tests structurally cannot (UI behavior, TCC interactions)
