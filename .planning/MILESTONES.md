# Milestones: AnyVim

## v1.0 MVP — Shipped 2026-04-02

**Phases:** 6 | **Plans:** 14 | **Requirements:** 27/27

Seamless vim editing in any text input on macOS. Double-tap Control to trigger, edit in a floating SwiftTerm vim window, :wq to paste back with full clipboard preservation.

### Key Accomplishments

1. Menu bar daemon with permission onboarding and auto-detection (no restart required)
2. System-wide double-tap Control detection via CGEventTap with health monitoring
3. Text capture and paste-back via Accessibility APIs with full clipboard preservation
4. Floating SwiftTerm window hosting vim with :wq/:q! exit detection via mtime comparison
5. Complete trigger-grab-edit-paste loop with re-entrancy protection and temp file cleanup
6. Visual session indicator (icon swap) and configurable vim binary path

### Stats

- **Lines of code:** 9,540 Swift
- **Timeline:** 3 days (2026-03-31 → 2026-04-02)
- **Commits:** 101
- **Files:** 98 modified
- **Audit:** tech_debt — all requirements met, minor documentation items

### Archive

- [v1.0-ROADMAP.md](milestones/v1.0-ROADMAP.md) — Full phase details
- [v1.0-REQUIREMENTS.md](milestones/v1.0-REQUIREMENTS.md) — All 27 requirements with final status
- [v1.0-MILESTONE-AUDIT.md](milestones/v1.0-MILESTONE-AUDIT.md) — Audit report
