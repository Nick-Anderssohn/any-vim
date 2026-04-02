---
phase: 04-vim-session
plan: 01
subsystem: vim-session
tags: [swiftterm, nspanel, vim-hosting, async-await, mtime-detection]
dependency_graph:
  requires: [03-02-SUMMARY]
  provides: [VimSessionManager, VimPanel, VimExitResult, VimPathResolving, FileModificationDateReading]
  affects: [AppDelegate]
tech_stack:
  added: [SwiftTerm 1.13.0 (via Xcode SPM)]
  patterns: [CheckedContinuation, LocalProcessTerminalViewDelegate, NSPanel.level=.floating]
key_files:
  created:
    - Sources/AnyVim/VimPanel.swift
    - Sources/AnyVim/VimSessionManager.swift
    - AnyVimTests/VimSessionManagerTests.swift
  modified:
    - Sources/AnyVim/SystemProtocols.swift
    - AnyVim.xcodeproj/project.pbxproj
decisions:
  - showAlerts: Bool injection added to VimSessionManager to suppress modal NSAlert in unit tests
  - VimExitResult.from(mtimeBefore:mtimeAfter:) static factory for pure unit-testable mtime comparison
  - LocalProcessTerminalViewDelegate requires 4 methods (sizeChanged, setTerminalTitle, hostCurrentDirectoryUpdate, processTerminated)
  - nonisolated delegate methods + Task { @MainActor in } for Swift 6 concurrency safety
metrics:
  duration: 23 minutes
  completed: 2026-04-02
  tasks: 1
  files: 5
---

# Phase 04 Plan 01: VimPanel, VimSessionManager, and Protocols Summary

**One-liner:** SwiftTerm-based floating NSPanel vim session with async/await continuation, mtime exit detection, and login-shell PATH resolution for Homebrew vim.

## What Was Built

### VimPanel.swift
NSPanel subclass that overrides `canBecomeKey` and `canBecomeMain` to return `true`. Without these overrides, vim receives no keyboard input at `.floating` window level. No `.nonactivatingPanel` style mask — that would prevent input regardless of the override.

### VimSessionManager.swift
`@MainActor final class VimSessionManager` implementing the complete vim session lifecycle:

1. **Vim binary resolution** — `ShellVimPathResolver` runs `/bin/zsh -l -c "which vim"` to get the user's full shell PATH (including Homebrew).
2. **File mtime baseline** — Reads `modificationDate` before `startProcess` for change detection.
3. **NSPanel creation** — `VimPanel` with `.floating` level, `isReleasedWhenClosed = false`, SF Mono 13pt, `configureNativeColors()`.
4. **SwiftTerm setup** — `LocalProcessTerminalView` added to panel content view BEFORE `startProcess` (Pitfall 7).
5. **Process launch** — `startProcess(executable:args:environment:execName:currentDirectory:)` with `nil` environment (SwiftTerm provides TERM=xterm-256color, HOME, etc.).
6. **Async suspension** — `withCheckedContinuation` stores continuation as instance property.
7. **Exit detection** — `processTerminated(source:exitCode:)` delegate fires; mtime comparison determines `.saved` vs `.aborted`.
8. **Window frame persistence** — Saves/restores `VimWindowFrame` in UserDefaults (D-02).
9. **Close button handling** — `NSWindow.willCloseNotification` observer treats window close as `.aborted` (D-07).

### SystemProtocols.swift additions
- `protocol VimPathResolving` — `func resolveVimPath() -> String?`
- `protocol FileModificationDateReading` — `func modificationDate(of url: URL) -> Date?`
- `struct ShellVimPathResolver` — production `/bin/zsh -l` resolver
- `struct SystemFileModificationDateReader` — production `FileManager.attributesOfItem` reader

### VimSessionManagerTests.swift
9 unit tests covering all spec behaviors:
- `testModificationDateReturnsDateForExistingFile` — production reader returns Date for real file
- `testModificationDateReturnsNilForMissingFile` — production reader returns nil for missing file
- `testExitResultSavedWhenMtimeChanges` — different dates = .saved
- `testExitResultAbortedWhenMtimeUnchanged` — same dates = .aborted
- `testExitResultAbortedWhenMtimeAfterIsNil` — nil after = .aborted
- `testExitResultAbortedWhenMtimeBeforeIsNil` — nil before = .aborted
- `testResolveVimPathFindsVim` — integration: system vim is found
- `testVimSessionManagerInitializesWithMockDependencies` — mock injection compiles and initializes
- `testOpenVimSessionReturnsAbortedWhenVimNotFound` — nil resolver returns .aborted without blocking

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing] `showAlerts: Bool` parameter added to VimSessionManager init**
- **Found during:** Task 1 test execution
- **Issue:** `testOpenVimSessionReturnsAbortedWhenVimNotFound` was blocking for ~103 seconds on `NSAlert.runModal()` (modal dialog waiting for user interaction in test)
- **Fix:** Added `showAlerts: Bool = true` parameter to `init`. Alert suppressed when `showAlerts: false`. Tests pass `showAlerts: false`. Production code defaults to `true`.
- **Files modified:** `Sources/AnyVim/VimSessionManager.swift`, `AnyVimTests/VimSessionManagerTests.swift`
- **Commit:** 2d3b6e9

**2. [Rule 1 - Bug] `LocalProcessTerminalViewDelegate` requires 4 methods, not 1**
- **Found during:** Task 1 build
- **Issue:** Research noted only `processTerminated` but the actual SwiftTerm protocol requires `sizeChanged`, `setTerminalTitle`, `hostCurrentDirectoryUpdate`, and `processTerminated`.
- **Fix:** Added all 4 required delegate methods. `sizeChanged` and `hostCurrentDirectoryUpdate` are no-ops. `setTerminalTitle` updates panel title on main actor.
- **Files modified:** `Sources/AnyVim/VimSessionManager.swift`
- **Commit:** 2d3b6e9

**3. [Rule 2 - Missing] `VimExitResult.from(mtimeBefore:mtimeAfter:)` static factory**
- **Found during:** Task 1 test design
- **Issue:** Plan called for testing mtime comparison "unit test the mtime comparison logic directly" but the original design embedded the logic inside `handleProcessTerminated()` with no testable surface.
- **Fix:** Extracted mtime comparison into `static func from(mtimeBefore: Date?, mtimeAfter: Date?) -> VimExitResult` on `VimExitResult`. Added 4 pure unit tests against this method.
- **Files modified:** `Sources/AnyVim/VimSessionManager.swift`, `AnyVimTests/VimSessionManagerTests.swift`
- **Commit:** 2d3b6e9

## Known Stubs

None — `VimSessionManager.openVimSession` is fully implemented. AppDelegate wiring is deferred to Plan 02 per plan design (not a stub).

## Success Criteria Met

- [x] SwiftTerm is a project dependency and builds
- [x] VimPanel.swift: NSPanel subclass with canBecomeKey/canBecomeMain = true
- [x] VimSessionManager.swift: @MainActor class with async openVimSession API, mtime detection, vim path resolution, window centering, size persistence
- [x] SystemProtocols.swift: VimPathResolving and FileModificationDateReading protocols with production implementations
- [x] VimSessionManagerTests.swift: All 9 tests pass (mtime logic, vim path resolution, abort-on-no-vim)
- [x] Full test suite passes (no regressions)

## Self-Check: PASSED

All created/modified files exist on disk. Commit 2d3b6e9 verified in git log.
