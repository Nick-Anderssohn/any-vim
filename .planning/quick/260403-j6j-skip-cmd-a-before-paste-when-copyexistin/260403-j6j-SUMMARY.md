---
phase: quick
plan: 260403-j6j
subsystem: accessibility-bridge
tags: [paste, clipboard, accessibility, edit-cycle]
dependency_graph:
  requires: []
  provides: [conditional-select-all-before-paste]
  affects: [EditCycleCoordinating, AccessibilityBridge, AppDelegate]
tech_stack:
  added: []
  patterns: [conditional-keystroke-based-on-user-setting]
key_files:
  created: []
  modified:
    - Sources/AnyVim/EditCycleCoordinating.swift
    - Sources/AnyVim/AccessibilityBridge.swift
    - Sources/AnyVim/AppDelegate.swift
decisions:
  - Capture copyExistingText once into a local let in AppDelegate to avoid double-reading UserDefaults and to pass the same value to both the capture path selector and restoreText
metrics:
  duration: ~10 minutes
  completed: 2026-04-03
---

# Quick Task 260403-j6j: Skip Cmd+A before paste when copyExistingText is off — Summary

**One-liner:** Added `selectAllBeforePaste` parameter to `restoreText` so Cmd+A (select all) is skipped when the user opened vim with an empty buffer, preventing edited text from incorrectly replacing entire field contents.

## What Was Done

### Task 1: Add selectAllBeforePaste parameter to restoreText across protocol and implementation

Updated three files to thread the `selectAllBeforePaste: Bool` parameter from the call site down through the protocol to the implementation:

1. `EditCycleCoordinating.swift` — Added `selectAllBeforePaste: Bool` to the `TextCapturing.restoreText` protocol signature.

2. `AccessibilityBridge.swift` — Updated `restoreText` to accept the parameter. Wrapped the Cmd+A keystroke and its 150ms sleep inside `if selectAllBeforePaste { ... }`. Cmd+V remains unconditional.

3. `AppDelegate.swift` — Captured `UserDefaults.standard.bool(forKey: "copyExistingText")` into a local `let copyExistingText` before the capture branch. Passed it as `selectAllBeforePaste: copyExistingText` at the `restoreText` call site.

**Verification:** `xcodebuild` with `CODE_SIGNING_REQUIRED=NO` — BUILD SUCCEEDED. All warnings are pre-existing (in `PermissionManager.swift` and `VimSessionManager.swift`).

## Deviations from Plan

None — plan executed exactly as written.

The verification command in the plan (`swift build`) does not apply because AnyVim is an Xcode project, not a Swift Package. Used `xcodebuild ... CODE_SIGNING_REQUIRED=NO` instead to verify compilation.

## Commits

| Hash | Description |
|------|-------------|
| cbb9f9b | fix: skip Cmd+A before paste when copyExistingText is off |

## Known Stubs

None.

## Self-Check: PASSED

- Sources/AnyVim/EditCycleCoordinating.swift — modified (selectAllBeforePaste in protocol)
- Sources/AnyVim/AccessibilityBridge.swift — modified (conditional Cmd+A)
- Sources/AnyVim/AppDelegate.swift — modified (pass selectAllBeforePaste)
- Commit cbb9f9b — verified present
