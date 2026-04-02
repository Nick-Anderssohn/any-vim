# Phase 5: Edit Cycle Integration - Research

**Researched:** 2026-04-01
**Domain:** Swift / AppKit — async/await orchestration, re-entrancy guard, file reading
**Confidence:** HIGH

## Summary

Phase 5 is a pure wiring phase. All the component APIs are fully implemented and tested: `AccessibilityBridge.captureText()`, `VimSessionManager.openVimSession(tempFileURL:)`, `AccessibilityBridge.restoreText(_:captureResult:)`, `AccessibilityBridge.abortAndRestore(captureResult:)`, and `TempFileManager.deleteTempFile(at:)`. The only new code is in `AppDelegate.handleHotkeyTrigger()` — replace the Phase 4 placeholder (which called `abortAndRestore` for all exits and logged) with the real dispatch: guard re-entrancy, read the temp file on `.saved`, call `restoreText` or `abortAndRestore`, then delete the temp file and reset the guard.

The two new additions beyond pure wiring are: (1) an `isEditSessionActive: Bool` property on `AppDelegate` for re-entrancy protection, and (2) a `String(contentsOf:encoding:.utf8)` call to read the edited file before calling `restoreText`. A read failure is treated as abort per D-03/D-04.

**Primary recommendation:** Replace the 8-line Phase 4 placeholder in `handleHotkeyTrigger` with the ~20-line Phase 5 orchestration block. Add `isEditSessionActive` guard at the top. Add a new `AppDelegateCycleTests.swift` covering all four success criteria.

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Silent ignore when user triggers hotkey while a vim session is active. No beep, no alert, no window refocus — the trigger is simply swallowed.
- **D-02:** Guard implemented as a simple `isEditSessionActive` bool on AppDelegate. Set true at the start of `handleHotkeyTrigger`, false after all cleanup completes. Follows the existing manager-in-AppDelegate ownership pattern.
- **D-03:** If reading the edited temp file fails after :wq (disk error, file deleted externally, encoding issue), treat as abort — restore clipboard, delete temp file, do not paste.
- **D-04:** No user-visible error feedback for read failures. The abort path handles it silently.
- **D-05:** Temp file deleted immediately after the edit cycle completes — no delay, no debug grace period.
- **D-06:** `handleHotkeyTrigger` in AppDelegate owns cleanup as the final step after restoreText or abortAndRestore. Note: `abortAndRestore` already calls `deleteTempFile` internally — planner may centralize or keep idempotent.
- **D-07:** No user-visible feedback on cycle completion or abort.

### Claude's Discretion

- Whether to remove `deleteTempFile` from `abortAndRestore` (centralize in AppDelegate) or keep it idempotent in both places
- Exact orchestration flow in `handleHotkeyTrigger` (the wiring between captureText → openVimSession → restoreText/abortAndRestore → cleanup)
- Whether to keep or remove the Phase 4 `print()` debug logging
- How to read the edited temp file content (String(contentsOf:) encoding choice)

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| REST-01 | On :wq, app reads the edited temp file and places contents on the clipboard | `String(contentsOf:encoding:.utf8)` + `AccessibilityBridge.restoreText(_:captureResult:)` already sets clipboard and pastes |
| REST-02 | App sends Cmd+A, Cmd+V to the original application to replace text field contents | `restoreText` already implemented and tested — Phase 5 just needs to call it |
| REST-03 | On :q!, app detects the file was not modified and skips paste-back | `VimExitResult.aborted` from `openVimSession` — branch to `abortAndRestore` |
| REST-04 | After paste-back (or abort), app restores the user's original clipboard contents | Both `restoreText` and `abortAndRestore` call `clipboardGuard.restore(captureResult.clipboardSnapshot)` |
| REST-05 | Temp file is deleted after the edit cycle completes | `TempFileManager.deleteTempFile(at:)` — called in `abortAndRestore` already; Phase 5 ensures it also runs after `.saved` path |
</phase_requirements>

---

## Standard Stack

### Core (no new dependencies)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Swift 6 (AppKit) | Built-in | Async/await, MainActor, Task | All orchestration in `handleHotkeyTrigger` uses existing async/await pattern |
| Foundation | Built-in | `String(contentsOf:encoding:)` | Only new API call — reads edited temp file content |

No new SPM dependencies for this phase. All required components exist.

**Installation:** None required.

## Architecture Patterns

### Recommended Project Structure

No new files needed beyond a test file:
```
Sources/AnyVim/
└── AppDelegate.swift           # handleHotkeyTrigger() is the only file modified

AnyVimTests/
└── AppDelegateCycleTests.swift  # New: covers REST-01 through REST-05 + re-entrancy
```

### Pattern 1: Re-entrancy Guard via Bool Flag

**What:** `isEditSessionActive` is an `@MainActor`-isolated `Bool` on `AppDelegate`. Set `true` at function entry, reset to `false` in a `defer` block (or explicit cleanup). Because `handleHotkeyTrigger` is already on `@MainActor` via the `Task { @MainActor in }` wrapper, the flag is safe without any locks.

**When to use:** Any time a long-running async operation must be non-reentrant.

**Example:**
```swift
// Source: existing AppDelegate.swift patterns + Swift 6 @MainActor guarantee
private var isEditSessionActive = false

private func handleHotkeyTrigger() {
    guard !isEditSessionActive else { return }   // D-01: silent swallow
    isEditSessionActive = true

    Task { @MainActor in
        defer { isEditSessionActive = false }    // D-02: always resets

        guard let result = await accessibilityBridge.captureText() else {
            showCaptureFailureAlert()
            return
        }

        let exitResult = await vimSessionManager.openVimSession(tempFileURL: result.tempFileURL)

        switch exitResult {
        case .saved:
            if let editedContent = try? String(contentsOf: result.tempFileURL, encoding: .utf8) {
                await accessibilityBridge.restoreText(editedContent, captureResult: result)
                TempFileManager().deleteTempFile(at: result.tempFileURL)  // REST-05
            } else {
                // D-03: read failure → abort path
                accessibilityBridge.abortAndRestore(captureResult: result)
            }
        case .aborted:
            accessibilityBridge.abortAndRestore(captureResult: result)
        }
    }
}
```

**Important nuance on `defer` placement:** The `defer` must be inside the `Task` closure, not in the outer `handleHotkeyTrigger` function body, because the async work (and thus the correct "session end" moment) occurs inside the Task. If placed in the outer function, `isEditSessionActive` resets immediately when the Task is dispatched (before vim opens).

### Pattern 2: Reading Edited Temp File

**What:** After `.saved` exit, read the temp file with `String(contentsOf:encoding:.utf8)`. Per D-03, a `try?` wrapper treats failure as abort.

**When to use:** `.saved` branch only.

**Example:**
```swift
// Source: Foundation stdlib — String.init(contentsOf:encoding:) Swift 6
if let editedContent = try? String(contentsOf: result.tempFileURL, encoding: .utf8) {
    await accessibilityBridge.restoreText(editedContent, captureResult: result)
    TempFileManager().deleteTempFile(at: result.tempFileURL)
} else {
    // D-03/D-04: disk read failure — treat as abort, no alert
    accessibilityBridge.abortAndRestore(captureResult: result)
}
```

UTF-8 encoding matches `TempFileManager.createTempFile(content:)` which writes with `.utf8`.

### Pattern 3: Temp File Cleanup Ownership (D-06 discretion)

Two viable approaches. Research recommendation: **keep `abortAndRestore` calling `deleteTempFile` and also call it explicitly after `restoreText` in the `.saved` path.** This makes AppDelegate the single orchestrator of cleanup without requiring changes to `abortAndRestore`'s existing behavior (which is already tested). The calls are idempotent (`TempFileManager.deleteTempFile` uses `try?`).

Alternative (centralize in AppDelegate only): Remove `deleteTempFile` from `abortAndRestore` and call it in all paths from `handleHotkeyTrigger`. This is cleaner but requires modifying `AccessibilityBridgeTests` expectations. Adds complexity with no benefit for this phase.

**Recommendation:** Keep idempotent pattern. Less change, all existing tests remain green.

### Anti-Patterns to Avoid

- **Guard in outer function, async work in Task:** Setting `isEditSessionActive = true` before `Task { }` and `defer` in the outer function resets the flag immediately when the Task is created, not when it completes. The guard must live entirely inside the `Task { @MainActor in }` block (or use a different dispatch pattern).
- **Reading file before vim exits:** The edited content is only meaningful after `openVimSession` returns `.saved`. Do not read the file at any other point.
- **Calling `restoreText` on `.aborted`:** `restoreText` pastes whatever is on the clipboard. On abort, only `abortAndRestore` should be called — it restores the clipboard without pasting.
- **Forgetting `deleteTempFile` after `.saved` + `restoreText`:** `abortAndRestore` deletes the file. `restoreText` does not. The `.saved` branch must explicitly delete.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Temp file read | Custom buffered reader | `String(contentsOf:encoding:.utf8)` | One line, UTF-8 matches write encoding, throws on error which maps cleanly to the abort path |
| Re-entrancy lock | DispatchSemaphore, actor, NSLock | `isEditSessionActive: Bool` on `@MainActor` class | `@MainActor` serializes all access; no concurrency primitive needed |
| Exit branch dispatch | Polling, notification, delegate | `switch exitResult { case .saved: ... case .aborted: ... }` | `VimExitResult` is already the right abstraction; switch is exhaustive |

**Key insight:** All complexity was solved in Phases 3 and 4. Phase 5 is dispatch logic only — the right instinct is "what's the minimum code to connect these APIs."

## Common Pitfalls

### Pitfall 1: `defer` in Wrong Scope Resets Guard Too Early

**What goes wrong:** `isEditSessionActive` resets to `false` immediately when `Task { }` is created — before vim even opens. A second trigger during the vim session is no longer blocked.

**Why it happens:** `defer` executes when the surrounding scope exits. The outer `handleHotkeyTrigger` function scope exits as soon as `Task { }` is dispatched (the Task runs independently).

**How to avoid:** Place both `isEditSessionActive = true` and the `defer { isEditSessionActive = false }` inside the `Task { @MainActor in }` closure.

**Warning signs:** Re-entrancy test passes locally but a real double-tap opens two windows.

### Pitfall 2: File Read Race with mtime-Based Exit Detection

**What goes wrong:** The temp file content is read before vim has fully flushed the file to disk, returning stale content.

**Why it happens:** VimSessionManager uses `processTerminated` (process exit) as the trigger. At process exit, the file write is already complete — vim calls `fsync` on `:wq`. This is NOT a real pitfall here.

**How to avoid:** No action needed. By the time `openVimSession` returns `.saved`, the process has exited and the OS has flushed all pending writes. Reading immediately after is safe.

### Pitfall 3: abortAndRestore Called Twice on `.saved` Read Failure

**What goes wrong:** If you structure the `.saved` fallback incorrectly, `abortAndRestore` is called and then cleanup runs again, attempting double-deletion of the temp file.

**Why it happens:** Poorly structured if/else where the outer `defer` in AppDelegate calls `deleteTempFile` regardless.

**How to avoid:** In the read-failure case, `abortAndRestore` handles its own deletion. Do NOT add an additional `deleteTempFile` call after `abortAndRestore`. The `.saved` + successful read path is the only one that needs an explicit `deleteTempFile` call from AppDelegate (because `restoreText` does not call it).

**Warning signs:** `deleteTempFile` called with a URL that no longer exists — harmless (it uses `try?`) but indicates logic confusion.

### Pitfall 4: `isEditSessionActive` Not Reset on `captureText` Failure

**What goes wrong:** If `captureText()` returns `nil`, the early `return` exits the `Task` but `isEditSessionActive` is never reset, permanently blocking future triggers.

**Why it happens:** Early return before `defer` fires... but `defer` fires even on early return. This is NOT a real pitfall if `defer` is used correctly. Using `defer` immediately after setting the flag handles all exit paths including the early return.

**How to avoid:** Use `defer { isEditSessionActive = false }` immediately after `isEditSessionActive = true`. Do not rely on explicit resets at each return site.

## Code Examples

### Complete `handleHotkeyTrigger` Implementation

```swift
// Source: synthesized from existing AppDelegate.swift + CONTEXT.md decisions
private var isEditSessionActive = false

private func handleHotkeyTrigger() {
    Task { @MainActor in
        guard !isEditSessionActive else { return }   // D-01: silent swallow
        isEditSessionActive = true
        defer { isEditSessionActive = false }        // D-02: reset on all exit paths

        guard let result = await accessibilityBridge.captureText() else {
            showCaptureFailureAlert()
            return
        }

        let exitResult = await vimSessionManager.openVimSession(tempFileURL: result.tempFileURL)

        switch exitResult {
        case .saved:
            if let editedContent = try? String(contentsOf: result.tempFileURL, encoding: .utf8) {
                // REST-01, REST-02: paste edited text back
                await accessibilityBridge.restoreText(editedContent, captureResult: result)
                // REST-05: delete temp file (restoreText does not delete)
                TempFileManager().deleteTempFile(at: result.tempFileURL)
            } else {
                // D-03/D-04: read failure → silent abort
                accessibilityBridge.abortAndRestore(captureResult: result)
            }

        case .aborted:
            // REST-03: skip paste-back; REST-04/REST-05 handled by abortAndRestore
            accessibilityBridge.abortAndRestore(captureResult: result)
        }
    }
}
```

### Test Scaffolding for AppDelegate Cycle Tests

The challenge: `AppDelegate` is `@main` with real system dependencies. For unit tests, test `handleHotkeyTrigger` logic by extracting it into a testable helper OR by testing the components in isolation and adding a targeted integration test.

**Recommended approach:** Extract the orchestration logic into a separate `EditCycleOrchestrator` struct/class with protocol-typed dependencies, then wire it in AppDelegate. Tests cover the orchestrator directly. This follows the established pattern (HotkeyManager, AccessibilityBridge, etc.) and avoids `@main` class instantiation issues in test targets.

**Alternative (simpler):** Keep logic in AppDelegate and test it via the existing mock infrastructure (MockAccessibilityBridge + MockVimSessionManager). Mark `isEditSessionActive` and `handleHotkeyTrigger` as `internal` (remove `private`) for test access. This is acceptable for a small integration phase.

Both approaches are viable. Research leans toward the simpler alternative for a pure-wiring phase.

## State of the Art

| Old Approach (Phase 4 placeholder) | Current Approach (Phase 5) | Impact |
|------------------------------------|---------------------------|--------|
| `abortAndRestore` for ALL exits + `print()` log | Switch on `VimExitResult`, `restoreText` on `.saved`, `abortAndRestore` on `.aborted` | REST-01, REST-02, REST-03 satisfied |
| No re-entrancy protection | `isEditSessionActive` guard | SC-4 satisfied |
| Temp file deleted only in `abortAndRestore` | Deleted after `.saved` path too | REST-05 fully satisfied |

## Open Questions

1. **TempFileManager ownership in `.saved` path**
   - What we know: `AccessibilityBridge` internally holds a `TempFileManager` instance (private). `AppDelegate` also uses `TempFileManager()` directly (Phase 3 wiring created one per-call).
   - What's unclear: Should `AppDelegate.handleHotkeyTrigger` call `TempFileManager().deleteTempFile(at:)` as a new instance (fine — struct, stateless) or access it through `accessibilityBridge`?
   - Recommendation: `TempFileManager` is a struct with no state. `TempFileManager().deleteTempFile(at:)` as a one-off call is fine. Alternatively, expose a `deleteTempFile` method on `AccessibilityBridge` that AppDelegate can call — keeps file ownership encapsulated. Either approach is correct.

2. **Debug print() logging — keep or remove**
   - What we know: Phase 4 added `print("[AnyVim] Vim session completed: saved/aborted")`. CONTEXT.md flags this as discretionary.
   - What's unclear: No formal logging strategy established.
   - Recommendation: Remove for Phase 5. The print calls are superseded by the actual behavior (text appears or doesn't). Add them back if debugging is needed.

## Environment Availability

Step 2.6: SKIPPED — Phase 5 is purely code/config changes. No external tools, CLIs, services, or runtimes beyond the existing Xcode/Swift toolchain (verified operational by Phase 4 completion).

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | XCTest (built into Xcode 16.3) |
| Config file | AnyVim.xcodeproj (AnyVimTests target) |
| Quick run command | `xcodebuild test -project AnyVim.xcodeproj -scheme AnyVim -destination 'platform=macOS' 2>&1 \| grep -E "(Test Suite|passed|failed|error:)"` |
| Full suite command | `xcodebuild test -project AnyVim.xcodeproj -scheme AnyVim -destination 'platform=macOS'` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| REST-01 | On :wq, edited file content is read and passed to restoreText | unit | xcodebuild test (AppDelegateCycleTests::testSavedExitCallsRestoreTextWithEditedContent) | ❌ Wave 0 |
| REST-02 | restoreText sends Cmd+A/Cmd+V to original app | unit | xcodebuild test (AccessibilityBridgeTests::testRestoreTextPostsCmdACmdV) | ✅ exists |
| REST-03 | On :q!, abortAndRestore called (no paste) | unit | xcodebuild test (AppDelegateCycleTests::testAbortedExitCallsAbortAndRestore) | ❌ Wave 0 |
| REST-04 | Clipboard restored after both save and abort | unit | xcodebuild test (AccessibilityBridgeTests — existing restore tests cover this) | ✅ exists |
| REST-05 | Temp file deleted on save path AND abort path | unit | xcodebuild test (AppDelegateCycleTests::testTempFileDeletedAfterSave + testTempFileDeletedAfterAbort) | ❌ Wave 0 |
| SC-4 (re-entrancy) | Double trigger during active session is ignored | unit | xcodebuild test (AppDelegateCycleTests::testReentrancyGuardBlocksSecondTrigger) | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** `xcodebuild test -project AnyVim.xcodeproj -scheme AnyVim -destination 'platform=macOS' 2>&1 | grep -E "(passed|failed|error:)"`
- **Per wave merge:** Full suite (same command without grep)
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `AnyVimTests/AppDelegateCycleTests.swift` — covers REST-01, REST-03, REST-05, SC-4 re-entrancy
  - Requires mock `AccessibilityBridge` and mock `VimSessionManager` with injectable behavior
  - Either extract orchestration into `EditCycleOrchestrator` or mark `handleHotkeyTrigger`/`isEditSessionActive` as `internal`

*(Existing tests in AccessibilityBridgeTests.swift cover REST-02 and REST-04 already)*

## Sources

### Primary (HIGH confidence)

- `Sources/AnyVim/AppDelegate.swift` — `handleHotkeyTrigger()` at line 127: Phase 4 state to be replaced
- `Sources/AnyVim/AccessibilityBridge.swift` — `restoreText(_:captureResult:)` at line 115, `abortAndRestore(captureResult:)` at line 145: full API signatures verified by reading
- `Sources/AnyVim/VimSessionManager.swift` — `openVimSession(tempFileURL:)` async signature, `VimExitResult` enum: verified
- `Sources/AnyVim/TempFileManager.swift` — `deleteTempFile(at:)` idempotent via `try?`: verified
- `AnyVimTests/AccessibilityBridgeTests.swift` — Existing test coverage of REST-02/REST-04: verified
- `.planning/phases/05-edit-cycle-integration/05-CONTEXT.md` — All locked decisions D-01 through D-07
- `CLAUDE.md` — Swift 6 strict concurrency, `@MainActor` pattern, manager ownership

### Secondary (MEDIUM confidence)

- Apple Swift documentation: `String(contentsOf:encoding:)` throws on failure — used for D-03 abort-on-read-failure pattern. Standard Foundation API, HIGH confidence.
- Swift concurrency documentation: `defer` in async Task closure fires on all exit paths including early `return` — this is standard Swift semantics, HIGH confidence.

### Tertiary (LOW confidence)

None. All findings are from direct source code inspection or established Swift language semantics.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all components already implemented and verified in prior phases
- Architecture: HIGH — patterns are established (AppDelegate ownership, @MainActor, async/await Task)
- Pitfalls: HIGH — identified from reading the actual code; defer-scope pitfall is a documented Swift pattern issue

**Research date:** 2026-04-01
**Valid until:** 2026-05-01 (stable APIs, no external dependencies)
