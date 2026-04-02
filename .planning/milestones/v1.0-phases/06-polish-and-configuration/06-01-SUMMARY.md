---
phase: 06-polish-and-configuration
plan: 01
subsystem: ui
tags: [swiftui, appkit, nsmenu, userdefaults, icon-swap, vim-path]

# Dependency graph
requires:
  - phase: 05-edit-cycle-integration
    provides: AppDelegate.handleHotkeyTrigger, VimSessionManager with injectable vimPathResolver
provides:
  - UserDefaultsVimPathResolver struct for composable custom vim binary selection
  - Icon swap to pencil.circle.fill on session start, restores on all exit paths
  - Vim path section in MenuBarController menu (info item, Set Vim Path..., Reset Vim Path)
  - MENU-02 and CONF-01 requirements fulfilled
affects: [06-02-manual-verification]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Composing resolver pattern: UserDefaultsVimPathResolver wraps ShellVimPathResolver via VimPathResolving protocol"
    - "statusItem? optional chain (not statusItem!) prevents nil crash in unit test context"
    - "UserDefaults(suiteName:) isolation in tests prevents polluting .standard"
    - "Pitfall 3 mitigation: avoid calling ShellVimPathResolver on main thread during menu build; show static 'Vim: (default)' instead"

key-files:
  created: []
  modified:
    - Sources/AnyVim/SystemProtocols.swift
    - Sources/AnyVim/MenuBarController.swift
    - Sources/AnyVim/AppDelegate.swift
    - AnyVimTests/VimSessionManagerTests.swift
    - AnyVimTests/MenuBarControllerTests.swift

key-decisions:
  - "Use statusItem? optional chain (not statusItem!) to prevent nil crash in unit tests where applicationDidFinishLaunching is never called"
  - "Show 'Vim: (default)' for no-custom-path case instead of calling ShellVimPathResolver to avoid 100-300ms main thread block during menu build (Pitfall 3)"
  - "Icon swap testing deferred to Plan 02 manual verification — statusItem is nil in unit test context; optional chain makes it a safe no-op"

patterns-established:
  - "Pattern: Composing VimPathResolving resolvers with injectable fallback, defaults, and key for full testability"
  - "Pattern: Always use statusItem? optional chaining in methods that may be called from test context"

requirements-completed: [MENU-02, CONF-01]

# Metrics
duration: 7min
completed: 2026-04-02
---

# Phase 06 Plan 01: Polish and Configuration Summary

**Session-indicator icon swap (pencil.circle.fill) and composable vim binary path selection via UserDefaults with NSOpenPanel**

## Performance

- **Duration:** 7 min
- **Started:** 2026-04-02T19:15:46Z
- **Completed:** 2026-04-02T19:23:08Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- `UserDefaultsVimPathResolver` composing resolver checks `UserDefaults.standard` for a custom vim binary before falling back to `ShellVimPathResolver`; invalid/absent paths fall back silently per D-06
- `AppDelegate.handleHotkeyTrigger` swaps to `pencil.circle.fill` on session start and restores `character.cursor.ibeam` in the defer block on all exit paths (MENU-02)
- `MenuBarController` gets `vimPathResolver` and `onVimPathChange` init parameters; `buildMenu()` adds vim path info item, "Set Vim Path...", and conditional "Reset Vim Path" (CONF-01)
- 10 new unit tests: 4 for `UserDefaultsVimPathResolver` resolver logic, 6 for `MenuBarController` vim path section menu items
- Full test suite passes (all existing tests unaffected)

## Task Commits

Each task was committed atomically:

1. **Task 1: Add UserDefaultsVimPathResolver and unit tests** - `7ef5bcc` (feat)
2. **Task 2: Icon swap, vim path menu items, wiring, and tests** - `b9b0623` (feat)

**Plan metadata:** (docs commit — pending)

_Note: TDD tasks committed test + implementation together per GREEN phase completion._

## Files Created/Modified
- `/Users/nick/Projects/any-vim/Sources/AnyVim/SystemProtocols.swift` - Added `UserDefaultsVimPathResolver` struct after `ShellVimPathResolver`
- `/Users/nick/Projects/any-vim/Sources/AnyVim/AppDelegate.swift` - Icon swap in `handleHotkeyTrigger`, `UserDefaultsVimPathResolver` wiring in `applicationDidFinishLaunching`, `onVimPathChange` callback to `MenuBarController`
- `/Users/nick/Projects/any-vim/Sources/AnyVim/MenuBarController.swift` - New `vimPathResolver`/`onVimPathChange` init params, vim path section in `buildMenu()`, `setVimPath`/`resetVimPath` `@objc` actions
- `/Users/nick/Projects/any-vim/AnyVimTests/VimSessionManagerTests.swift` - 4 new `testUserDefaultsVimPathResolver*` test methods
- `/Users/nick/Projects/any-vim/AnyVimTests/MenuBarControllerTests.swift` - 6 new vim path section tests, `StubVimPathResolver`, `tearDown` cleanup

## Decisions Made
- Used `statusItem?` optional chain instead of `statusItem!` (IUO) so icon swap code safe-no-ops in unit test context where `applicationDidFinishLaunching` never runs and `statusItem` is nil
- Menu build shows static `"Vim: (default)"` when no custom path set rather than calling `ShellVimPathResolver.resolveVimPath()` which spawns a shell process and blocks the main thread for 100-300ms (per RESEARCH.md Pitfall 3)
- Custom `UserDefaults(suiteName: "test-UUID")` instances used in tests to avoid polluting `UserDefaults.standard` global state

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed nil crash in EditCycleCoordinatorTests from statusItem IUO**
- **Found during:** Task 2 (icon swap implementation)
- **Issue:** `statusItem` is declared `NSStatusItem!` (implicitly unwrapped optional). After adding `statusItem.button?.image = ...`, EditCycleCoordinatorTests crashed with "signal trap" because `statusItem` is nil in test context (AppDelegate created without `applicationDidFinishLaunching`)
- **Fix:** Changed `statusItem.button?.image` to `statusItem?.button?.image` throughout `handleHotkeyTrigger` and the defer block — IUO unsafe force-unwrap replaced with safe optional chain
- **Files modified:** `Sources/AnyVim/AppDelegate.swift`
- **Verification:** All EditCycleCoordinatorTests pass (5/5 previously failing now pass)
- **Committed in:** `b9b0623` (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 - Bug)
**Impact on plan:** Essential correctness fix. The IUO `!` force-unwrap of a nil value is a runtime crash. Safe optional chaining matches the plan's intent ("optional chain safely no-ops in tests") without behavioral change in production (statusItem is always non-nil after `applicationDidFinishLaunching`).

## Issues Encountered
None beyond the auto-fixed nil crash documented above.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- MENU-02 (icon swap) and CONF-01 (configurable vim path) are fully implemented
- Plan 02 (manual verification) can proceed — icon swap and vim path configuration need hands-on testing in the running app
- No blockers

---
*Phase: 06-polish-and-configuration*
*Completed: 2026-04-02*
