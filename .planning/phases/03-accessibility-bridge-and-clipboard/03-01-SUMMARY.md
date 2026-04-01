---
phase: 03-accessibility-bridge-and-clipboard
plan: 01
subsystem: accessibility-bridge
tags: [clipboard, protocols, testability, swift6]
dependency_graph:
  requires: []
  provides: [PasteboardAccessing, KeystrokeSending, AppActivating, ClipboardGuard, TempFileManager]
  affects: [03-02-AccessibilityBridge]
tech_stack:
  added: []
  patterns: [protocol-injection, deep-copy-pasteboard, uuid-temp-files]
key_files:
  created:
    - Sources/AnyVim/SystemProtocols.swift
    - Sources/AnyVim/ClipboardGuard.swift
    - Sources/AnyVim/TempFileManager.swift
    - AnyVimTests/ClipboardGuardTests.swift
    - AnyVimTests/TempFileManagerTests.swift
  modified:
    - AnyVim.xcodeproj/project.pbxproj
decisions:
  - "ClipboardSnapshot typealias [[NSPasteboard.PasteboardType: Data]] enables clean deep copy without NSPasteboardItem subclassing"
  - "MockPasteboard tracks clearContentsCalled and writtenItems separately for fine-grained assertion"
  - "TempFileManager.deleteTempFile is best-effort (try?) — callers should not need error handling on cleanup"
metrics:
  duration_seconds: 526
  completed_date: "2026-04-01"
  tasks_completed: 3
  files_changed: 6
---

# Phase 03 Plan 01: System Protocols, ClipboardGuard, TempFileManager Summary

**One-liner:** PasteboardAccessing/KeystrokeSending/AppActivating protocols with ClipboardGuard deep-copy snapshot/restore and UUID-named TempFileManager — foundation types for AccessibilityBridge.

## What Was Built

### SystemProtocols.swift
Three protocols and three production implementations following the TapInstalling/SystemTapInstaller pattern from HotkeyManager:

- **PasteboardAccessing** — abstracts NSPasteboard.general (changeCount, pasteboardItems, clearContents, writeObjects, setString, stringForType)
- **KeystrokeSending** — abstracts CGEvent.post; production `SystemKeystrokeSender` uses `.hidSystemState` event source per RESEARCH.md Pitfall 4, posts keyDown+keyUp pair to `.cghidEventTap`
- **AppActivating** — abstracts NSWorkspace/NSRunningApplication; `SystemAppActivator.activate` uses `app.activate(options: [])` per D-07 (no .activateIgnoringOtherApps)

### ClipboardGuard.swift
Clipboard snapshot/restore with deep copy of all pasteboard items:

- `ClipboardSnapshot` typealias: `[[NSPasteboard.PasteboardType: Data]]`
- `snapshot()` — iterates all pasteboard items, calls `item.data(forType:)` for every type eagerly (per RESEARCH.md Pitfall 1: lazy providers become invalid after `clearContents()`)
- `restore(_:)` — calls `clearContents()` then writes back all snapshotted items with their exact data

### TempFileManager.swift
Temp file lifecycle:

- `createTempFile(content:)` — creates `anyvim-{uuid}.txt` in `NSTemporaryDirectory()` using `String.write(to:atomically:encoding:)`
- `deleteTempFile(at:)` — best-effort deletion with `try? FileManager.default.removeItem`
- Empty string content produces a valid empty file (CAPT-04 compliance)

## Test Results

| Suite | Tests | Passed | Failed |
|-------|-------|--------|--------|
| ClipboardGuardTests | 6 | 6 | 0 |
| TempFileManagerTests | 7 | 7 | 0 |
| Existing tests | 13 | 13 | 0 |
| **Total** | **26** | **26** | **0** |

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| 1 — SystemProtocols | 415fa88 | feat(03-01): add system API protocols for testability |
| 2 — ClipboardGuard | 6b23301 | feat(03-01): add ClipboardGuard with deep-copy snapshot/restore and unit tests |
| 3 — TempFileManager | 7cf1dcf | feat(03-01): add TempFileManager with UUID naming and unit tests |

## Deviations from Plan

None — plan executed exactly as written.

The Xcode project.pbxproj was updated to include all 5 new files (3 source, 2 test). This is a required mechanical step not explicitly listed in the plan but necessary for the build system to pick them up.

## Self-Check: PASSED

- [x] Sources/AnyVim/SystemProtocols.swift exists
- [x] Sources/AnyVim/ClipboardGuard.swift exists
- [x] Sources/AnyVim/TempFileManager.swift exists
- [x] AnyVimTests/ClipboardGuardTests.swift exists
- [x] AnyVimTests/TempFileManagerTests.swift exists
- [x] Commit 415fa88 exists
- [x] Commit 6b23301 exists
- [x] Commit 7cf1dcf exists
- [x] All 26 tests pass
