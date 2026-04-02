---
phase: 01-app-shell-and-permissions
plan: 03
subsystem: ui
tags: [appkit, menu-bar, tcc, accessibility, input-monitoring]

requires:
  - phase: 01-02
    provides: Permission managers, alert flow, menu bar controller with live state
provides:
  - Human-verified Phase 1 app shell and permission onboarding flow
affects: [phase-02, phase-03]

tech-stack:
  added: []
  patterns: []

key-files:
  created: []
  modified:
    - Sources/AnyVim/AppDelegate.swift
    - Sources/AnyVim/PermissionManager.swift
    - AnyVim.xcodeproj/project.pbxproj

key-decisions:
  - "AppDelegate requires explicit static func main() to wire delegate — @main with NSPrincipalClass=NSApplication does not auto-assign delegate without a storyboard/nib"
  - "CGRequestListenEventAccess() must be called at launch to register app in Input Monitoring system settings list"
  - "Developer signing identity required for TCC — ad-hoc signing prevents app from appearing in privacy settings"

patterns-established:
  - "No-storyboard menu bar app pattern: static func main() with manual NSApplication.shared + delegate + run()"

requirements-completed: [MENU-01, MENU-03, MENU-04, PERM-01, PERM-02, PERM-03]

duration: 15min
completed: 2026-03-31
---

# Plan 03: Manual Smoke Test Summary

**Human-verified menu bar app shell with full permission onboarding — all 6 smoke test sections passed**

## Performance

- **Duration:** 15 min (including 2 bug fixes discovered during testing)
- **Tasks:** 1 (human verification checkpoint)
- **Files modified:** 3

## Accomplishments
- All 6 smoke test sections verified by human: menu bar presence, permission alerts, re-detection, menu dropdown, login toggle, quit
- Fixed critical launch bug: AppDelegate was never wired as delegate (no UI appeared)
- Fixed Input Monitoring registration: app now appears in System Settings privacy list

## Task Commits

1. **Task 1: Manual smoke test** — Human verification checkpoint (no code commit)

**Bug fixes discovered during smoke test:**
- `f9eb49b` — fix: wire AppDelegate via static main() and call CGRequestListenEventAccess()
- `a3942a0` — fix: set development team on test target for code signing

## Issues Encountered

### 1. App launched with no visible UI
- **Root cause:** `@main` on AppDelegate generates `NSApplicationMain()` which reads `NSPrincipalClass=NSApplication` from Info.plist. Without a storyboard/nib, no delegate is assigned, so `applicationDidFinishLaunching` never fires.
- **Fix:** Added explicit `static func main()` that creates NSApplication.shared, assigns AppDelegate as delegate, and calls `app.run()`.

### 2. App not listed in Input Monitoring system settings
- **Root cause:** `CGPreflightListenEventAccess()` is a passive check that doesn't register the app. `CGRequestListenEventAccess()` is required to add the app to the TCC list.
- **Fix:** Call `CGRequestListenEventAccess()` at launch in `applicationDidFinishLaunching`.

### 3. Ad-hoc signing prevented TCC registration
- **Root cause:** Without a developer signing identity, macOS TCC cannot track permission grants for the app.
- **Fix:** User signed into Xcode with Apple ID, set development team (758YPU2N3M) on both app and test targets.

## Deviations from Plan
None from the smoke test plan itself — the test checklist was executed as written. Two bugs were discovered and fixed inline.

## Next Phase Readiness
- Phase 1 app shell is complete and verified
- All 13 unit tests pass with proper code signing
- Ready for Phase 2 (Global Hotkey Detection) to add CGEventTap on top of this foundation

---
*Phase: 01-app-shell-and-permissions*
*Completed: 2026-03-31*
