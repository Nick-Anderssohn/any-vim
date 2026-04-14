---
phase: quick
plan: 260403-ivm
subsystem: edit-cycle
tags: [feature, menu-bar, userdefaults, tdd]
dependency_graph:
  requires: []
  provides: [copyExistingText-toggle, openEmpty-capture-path]
  affects: [EditCycleCoordinating, AccessibilityBridge, AppDelegate, MenuBarController]
tech_stack:
  added: []
  patterns: [UserDefaults-register-defaults, protocol-extension-method]
key_files:
  created: []
  modified:
    - Sources/AnyVim/EditCycleCoordinating.swift
    - Sources/AnyVim/AccessibilityBridge.swift
    - Sources/AnyVim/AppDelegate.swift
    - Sources/AnyVim/MenuBarController.swift
    - AnyVimTests/EditCycleCoordinatorTests.swift
    - AnyVimTests/MenuBarControllerTests.swift
decisions:
  - Register copyExistingText default (true) via UserDefaults.register(defaults:) in applicationDidFinishLaunching so bool(forKey:) is correct when key is absent
  - Toggle placed between vim path section and Launch at Login in menu
  - Menu rebuilds on each open — no live observation needed for checkmark state
metrics:
  duration: ~10 minutes
  completed: 2026-04-03
  tasks_completed: 2
  files_modified: 6
---

# Quick Task 260403-ivm: Add Copy Existing Text Toggle Summary

**One-liner:** Menu bar toggle (UserDefaults "copyExistingText", default ON) gates whether double-tap Control runs Cmd+A/Cmd+C capture or opens an empty vim buffer.

## Tasks Completed

| # | Name | Commit | Files |
|---|------|--------|-------|
| 1 | Add openEmpty() to TextCapturing and AccessibilityBridge | 1b46308 | EditCycleCoordinating.swift, AccessibilityBridge.swift, AppDelegate.swift, EditCycleCoordinatorTests.swift |
| 2 | Add Copy Existing Text toggle to menu bar | a6234b1 | MenuBarController.swift, MenuBarControllerTests.swift |

## What Was Built

### Task 1: openEmpty() protocol method and dispatch logic

- Added `func openEmpty() async -> CaptureResult?` to the `TextCapturing` protocol.
- Implemented `openEmpty()` in `AccessibilityBridge`: guards on accessibility permission and frontmost app (same as `captureText()`), snapshots clipboard, creates an empty temp file — no keystrokes posted.
- Registered `copyExistingText: true` default in `applicationDidFinishLaunching` before any reads, ensuring `bool(forKey:)` returns `true` when the key is absent (first-run default ON).
- Updated `handleHotkeyTrigger` to dispatch: `captureText()` when the toggle is ON, `openEmpty()` when OFF. The rest of the edit cycle (vim session, save/abort paths) is unchanged.
- Updated `MockTextCapture` with `openEmptyCallCount` and `openEmptyResult`.
- Added 3 new tests: disabled (openEmpty called), enabled (captureText called), key absent (captureText called — default ON).

### Task 2: Copy Existing Text menu item

- Added "Copy Existing Text" menu item in `buildMenu()`, positioned after the vim path separator and before "Launch at Login".
- Checkmark state reads `UserDefaults.standard.bool(forKey: "copyExistingText")` live on each menu open.
- Added `toggleCopyExistingText()` action that flips the value in UserDefaults.
- Added 3 new tests: item presence, checked when true, unchecked when false.
- tearDown in both test classes cleans up `copyExistingText` key.

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None.

## Test Results

All tests pass (full suite: EditCycleCoordinatorTests 9/9, MenuBarControllerTests 15/15, all other suites unaffected).

## Self-Check: PASSED

Files verified present:
- Sources/AnyVim/EditCycleCoordinating.swift — contains `openEmpty()` in protocol
- Sources/AnyVim/AccessibilityBridge.swift — contains `openEmpty()` implementation
- Sources/AnyVim/AppDelegate.swift — contains `register(defaults:)` and dispatch logic
- Sources/AnyVim/MenuBarController.swift — contains "Copy Existing Text" item and action
- AnyVimTests/EditCycleCoordinatorTests.swift — contains 3 new toggle tests
- AnyVimTests/MenuBarControllerTests.swift — contains 3 new toggle tests

Commits verified:
- 1b46308 — feat(quick-01): add openEmpty() to TextCapturing and dispatch
- a6234b1 — feat(quick-01): add Copy Existing Text toggle to menu bar
