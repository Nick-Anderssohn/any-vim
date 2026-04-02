# Phase 3: Accessibility Bridge and Clipboard - Research

**Researched:** 2026-04-01
**Domain:** CGEvent keystroke simulation, NSPasteboard snapshot/restore, NSRunningApplication focus management, Swift 6 async/await timing
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Use fixed delays between simulated keystrokes. Start with conservative values (~100-150ms between Cmd+A and Cmd+C for capture). Tune empirically during Phase 3 testing.
- **D-02:** Delays are hardcoded named constants in source code. No user-facing configuration, no UserDefaults — tune by changing the constant and recompiling.
- **D-03:** Paste-back uses a longer delay than capture (~200ms) to account for focus restoration to the original app. STATE.md flagged this as a known concern.
- **D-04:** Single `AccessibilityBridge` class handles both text capture and text restore. It owns the clipboard snapshot lifecycle and keystroke simulation. Follows the established one-manager-per-concern pattern (like HotkeyManager, PermissionManager).
- **D-05:** Snapshot ALL pasteboard items with all their types (plain text, RTF, images, app-specific custom types). Restore exactly after the edit cycle completes. Zero surprise for users.
- **D-06:** Clipboard is restored after a short delay (~100-200ms) following the Cmd+V paste, ensuring the target app has finished reading the pasteboard before it's overwritten with the restored content.
- **D-07:** Use `NSWorkspace.shared.frontmostApplication` to capture the active app when the hotkey fires. On restore, call `activate()` on the saved `NSRunningApplication`. Simple, reliable, well-documented API.
- **D-08:** If the original app is no longer running when AnyVim tries to restore focus (user quit it during vim session), silently skip focus restoration and clipboard restore. The field no longer exists — this is expected.
- **D-09:** Best-effort approach for non-text contexts. Run Cmd+A/Cmd+C regardless of what's focused — no AXUIElement role-checking. If no text is captured, open vim with an empty file.
- **D-10:** Use `NSPasteboard.general.changeCount` before and after Cmd+C to distinguish "empty field" (changeCount changed, content is empty string) from "capture failed" (changeCount unchanged). Both cases still open vim with an empty file — the distinction is for internal logging/debugging.
- **D-11:** Temp files go in `NSTemporaryDirectory()` with UUID-based naming (e.g., `anyvim-{uuid}.txt`). Auto-cleaned by macOS. Deleted after every edit cycle completes.

### Claude's Discretion

- Protocol abstraction design for testability (wrapping CGEvent.post, NSPasteboard, NSWorkspace)
- Exact delay values within the stated ranges — tune during implementation
- Internal logging/debug output for capture success/failure
- How AccessibilityBridge communicates results back to the caller (closure, async/await, or return value)

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CAPT-01 | On trigger, app saves the current clipboard contents (all pasteboard types) for later restoration | NSPasteboard.pasteboardItems deep-copy pattern — iterate items, copy each type's Data eagerly before pasteboard is overwritten |
| CAPT-02 | App sends Cmd+A, Cmd+C to the focused application via CGEvent to grab text field contents | CGEvent(keyboardEventSource:virtualKey:keyDown:) + flags = .maskCommand, post(tap: .cghidEventTap), keycodes kVK_ANSI_A=0x00, kVK_ANSI_C=0x08 |
| CAPT-03 | App reads the grabbed text from the clipboard and writes it to a temporary file | NSPasteboard.general.string(forType: .string) after delay, FileManager write to NSTemporaryDirectory()/anyvim-{UUID}.txt |
| CAPT-04 | App handles the case where the focused field is empty (empty temp file) | changeCount check before/after Cmd+C; empty string or unchanged count both produce empty temp file |
| COMPAT-01 | App works with native Cocoa text fields (TextEdit, Notes, Mail) | CGEvent Cmd+A/C/V works in all AppKit text fields when Accessibility permission is granted |
| COMPAT-02 | App works with browser text areas (Safari, Chrome, Firefox) | Same CGEvent approach works in browsers — browsers process HID-level keyboard events normally |
| COMPAT-03 | App handles timing delays between simulated keystrokes (100-150ms between Cmd+A and Cmd+C) | Task.sleep(nanoseconds:) in async context provides non-blocking timing; constants for each step |
</phase_requirements>

---

## Summary

Phase 3 builds `AccessibilityBridge`, the class responsible for (1) snapshotting the clipboard, (2) simulating Cmd+A/Cmd+C to capture text from the focused app, (3) writing that text to a temp file, and (4) providing the reverse path: write edited text to clipboard and simulate Cmd+A/Cmd+V to paste it back. The class also restores the clipboard to its exact pre-trigger state. Phase 3 explicitly does NOT launch vim — it only produces and consumes temp files.

The core macOS APIs are all available from macOS 13+: `CGEvent` with `.post(tap: .cghidEventTap)` for keystroke simulation, `NSPasteboard.pasteboardItems` for multi-type clipboard snapshots, `NSWorkspace.shared.frontmostApplication` for focus capture, and `NSRunningApplication.activate(options:)` for focus restoration. No third-party libraries are needed. The only meaningful complexity is the `NSPasteboardItem` deep-copy requirement — items must be read eagerly (all `Data` materialized before the pasteboard is mutated) because lazy data providers break after the source app no longer owns the pasteboard.

Timing is the empirical risk. The values 150ms (Cmd+A to Cmd+C) and 200ms (focus restore to Cmd+A/Cmd+V) are community-reported as conservative but correct starting points. `Task.sleep(nanoseconds:)` in an `async` method is the idiomatic Swift 6 approach for non-blocking waits on `@MainActor` — it suspends the task without blocking the run loop.

**Primary recommendation:** Implement `AccessibilityBridge` as a `@MainActor final class` with an `async` capture method and an `async` restore method. Use `Task.sleep(nanoseconds:)` for all inter-keystroke delays. Abstract `CGEvent.post`, `NSPasteboard`, and `NSRunningApplication.activate` behind protocols for unit-testability, following the `TapInstalling` protocol pattern from HotkeyManager.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| CoreGraphics (CGEvent) | macOS 13+ SDK | Synthesize Cmd+A/Cmd+C/Cmd+V keystrokes | Only supported mechanism for posting keyboard events to the system HID layer |
| AppKit (NSPasteboard) | macOS 13+ SDK | Clipboard snapshot/restore | System clipboard API; pasteboardItems gives full multi-type access |
| AppKit (NSWorkspace, NSRunningApplication) | macOS 13+ SDK | Focus capture and restore | frontmostApplication is the documented API for getting the active app |
| Foundation (FileManager, UUID) | macOS 13+ SDK | Temp file creation and cleanup | NSTemporaryDirectory() + UUID naming is the standard macOS temp file pattern |
| Carbon (HIToolbox keycodes) | macOS 13+ SDK | kVK_ANSI_A, kVK_ANSI_C, kVK_ANSI_V constants | Same Carbon constants already used in HotkeyManager for kVK_Control |

### Supporting

No third-party dependencies. All APIs are in the macOS SDK.

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| CGEvent.post | AXUIElement setValue for text | AXUIElement setValue works only when the element exposes AXValue as settable — many web elements don't; CGEvent Cmd+V is universal |
| Task.sleep(nanoseconds:) | DispatchQueue.asyncAfter | asyncAfter is callback-based and breaks async/await linearity; Task.sleep is idiomatic Swift 6 on @MainActor |
| NSRunningApplication.activate | NSWorkspace.open | open() is for launching apps not yet running; activate() is for apps already running |

**Installation:** No new packages — all APIs are in the macOS SDK. Carbon HIToolbox is already imported in HotkeyManager.

---

## Architecture Patterns

### Recommended Project Structure

```
Sources/AnyVim/
├── AccessibilityBridge.swift    # New: capture, restore, clipboard snapshot
├── AppDelegate.swift            # Wire AccessibilityBridge to handleHotkeyTrigger()
├── HotkeyManager.swift          # Existing — onTrigger calls AccessibilityBridge
├── PermissionManager.swift      # Existing — bridge queries before acting
└── (other existing files unchanged)
```

### Pattern 1: Protocol-Wrapped System APIs (following TapInstalling)

**What:** Each system API boundary (CGEvent.post, NSPasteboard, NSRunningApplication) is wrapped in a protocol so tests can inject mocks without real permissions or real clipboard state.

**When to use:** Always — consistent with HotkeyManager's TapInstalling pattern.

```swift
// Source: HotkeyManager.swift TapInstalling pattern (established project convention)

protocol KeystrokePoster {
    func postKeystroke(keyCode: CGKeyCode, flags: CGEventFlags)
}

protocol PasteboardAccessing {
    var changeCount: Int { get }
    func snapshot() -> [NSPasteboardItem]?
    func setString(_ string: String)
    func restore(_ items: [NSPasteboardItem])
}

protocol AppActivating {
    func frontmostApplication() -> NSRunningApplication?
    func activate(_ app: NSRunningApplication)
}
```

### Pattern 2: Async Capture/Restore Methods

**What:** `captureText()` and `restoreText(_:)` are `async` methods using `Task.sleep(nanoseconds:)` for inter-keystroke delays. Callers `await` them on `@MainActor`.

**When to use:** Any time a delay is needed between simulated keystrokes — avoids blocking the main thread.

```swift
// Source: Swift concurrency docs, Task.sleep pattern

@MainActor
final class AccessibilityBridge {
    // Named constants — tune empirically (D-01, D-02)
    private static let captureDelayNs: UInt64 = 150_000_000  // 150ms
    private static let pasteDelayNs:   UInt64 = 200_000_000  // 200ms
    private static let restoreDelayNs: UInt64 = 150_000_000  // 150ms

    func captureText() async -> URL? {
        // 1. Snapshot clipboard
        // 2. Capture frontmost app
        // 3. Post Cmd+A
        // 4. await Task.sleep(nanoseconds: Self.captureDelayNs)
        // 5. Post Cmd+C
        // 6. await Task.sleep(nanoseconds: Self.captureDelayNs)
        // 7. Read pasteboard, write temp file
        // 8. Return temp file URL (or nil if capture failed)
    }
}
```

### Pattern 3: NSPasteboardItem Deep Copy

**What:** Read ALL data for ALL types on ALL items eagerly before the pasteboard is mutated. NSPasteboardItems can have lazy data providers that become invalid once the pasteboard is cleared.

**Critical:** Call `item.data(forType:)` for every `type` in `item.types` immediately when snapshotting. Do not store `NSPasteboardItem` references — store the raw `Data`.

```swift
// Source: NSPasteboard documentation + Maccy clipboard manager pattern

func snapshot() -> [[NSPasteboard.PasteboardType: Data]] {
    guard let items = NSPasteboard.general.pasteboardItems else { return [] }
    return items.map { item in
        var typeData: [NSPasteboard.PasteboardType: Data] = [:]
        for type in item.types {
            if let data = item.data(forType: type) {
                typeData[type] = data
            }
        }
        return typeData
    }
}

func restore(_ snapshot: [[NSPasteboard.PasteboardType: Data]]) {
    let pb = NSPasteboard.general
    pb.clearContents()
    let items = snapshot.map { typeData -> NSPasteboardItem in
        let item = NSPasteboardItem()
        for (type, data) in typeData {
            item.setData(data, forType: type)
        }
        return item
    }
    pb.writeObjects(items)
}
```

### Pattern 4: Keystroke Simulation for Cmd+A/Cmd+C/Cmd+V

**What:** Create keyDown + keyUp CGEvent pairs with `.maskCommand` flags, post to `.cghidEventTap`.

**Key codes (Carbon HIToolbox):**
- `kVK_ANSI_A` = `0x00` — select all
- `kVK_ANSI_C` = `0x08` — copy
- `kVK_ANSI_V` = `0x09` — paste

```swift
// Source: CGEvent Apple docs + Carbon HIToolbox

func postKeystroke(keyCode: CGKeyCode, flags: CGEventFlags) {
    let src = CGEventSource(stateID: .hidSystemState)
    let keyDown = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
    let keyUp   = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
    keyDown?.flags = flags
    keyUp?.flags   = flags
    keyDown?.post(tap: .cghidEventTap)
    keyUp?.post(tap:   .cghidEventTap)
}
```

**Post target:** `.cghidEventTap` — posts at the HID level, delivering events to the currently focused application. This is the correct target for synthesizing keystrokes that should go to a specific app.

### Pattern 5: Focus Capture and Restore

**What:** Snapshot `NSWorkspace.shared.frontmostApplication` when the hotkey fires. Restore by calling `activate(options:)` on the saved reference.

**macOS 14+ deprecation note:** `activate(options: .activateIgnoringOtherApps)` is deprecated in macOS 14 — the `ignoringOtherApps` flag has no effect on macOS 14+. The replacement is `activate(from:options:)` (macOS 14+) which requires specifying the activating app. However, since AnyVim targets macOS 13+, use `activate(options: [])` with a deprecation suppression annotation, or use a compile-time version check. The simple `activate(options: [])` call (without `ignoringOtherApps`) should work for in-session app switching in practice.

```swift
// Source: NSRunningApplication documentation

// On hotkey fire (before posting any keystrokes):
let originalApp = NSWorkspace.shared.frontmostApplication

// On restore (after vim session, before Cmd+A/Cmd+V):
if let app = originalApp, app.isTerminated == false {
    app.activate(options: [])
    await Task.sleep(nanoseconds: Self.pasteDelayNs)
    // now post Cmd+A / Cmd+V
} else {
    // D-08: app quit during session — silently skip
    return
}
```

### Pattern 6: Temp File Management

**What:** Use `NSTemporaryDirectory()` + UUID for naming. Write at start of edit cycle, delete at end.

```swift
// Source: Foundation FileManager docs

let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
let tempFile = tempDir.appendingPathComponent("anyvim-\(UUID().uuidString).txt")

// Write (empty string if capture produced nothing):
try content.write(to: tempFile, atomically: true, encoding: .utf8)

// Delete after cycle:
try? FileManager.default.removeItem(at: tempFile)
```

### Anti-Patterns to Avoid

- **Storing NSPasteboardItem references across pasteboard mutations:** Items become invalid once `clearContents()` is called. Always copy all `Data` objects eagerly at snapshot time.
- **Blocking the main thread with `sleep()`:** Use `Task.sleep(nanoseconds:)` in an `async` context — this suspends the Swift task without blocking the run loop or the main thread.
- **Posting keystrokes before the original app is focused:** `CGEvent.post` sends to the currently focused app. If AnyVim has taken focus (e.g., to show a permission alert), post BEFORE any UI is shown, or restore focus before paste-back.
- **Using `.cgsAnnotatedSessionEventTap` for posting:** This tap is for monitors, not posting. Use `.cghidEventTap` for synthesis.
- **AXUIElement role-checking before Cmd+A/Cmd+C:** Per D-09, best-effort approach — skip the check. Role checking adds latency and fails for browser elements anyway.
- **Not setting `CGEventSource(stateID: .hidSystemState)` on synthesized events:** Without an event source, the system may reject the event on newer macOS versions.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Inter-keystroke timing | Custom Timer or sleep() | Task.sleep(nanoseconds:) | Non-blocking, @MainActor-compatible, idiomatic Swift 6 |
| Clipboard deep copy | Custom serialization | NSPasteboardItem.data(forType:) per type | Apple's own API; handles all UTTypes including app-specific |
| Temp file naming | Random numeric suffix | UUID().uuidString | Collision-free, no state needed |
| Focus tracking | AXUIElement kAXFocusedApplicationAttribute | NSWorkspace.shared.frontmostApplication | Simpler, works for whole-app focus (sufficient here) |

**Key insight:** The entire phase uses only platform-provided APIs. No custom algorithms or third-party libraries are needed. The complexity is in ordering (focus → keystrokes → delay → read) not in any individual operation.

---

## Runtime State Inventory

Phase 3 is not a rename/refactor/migration phase. No runtime state inventory required.

---

## Common Pitfalls

### Pitfall 1: NSPasteboardItem Lazy Data Provider Invalidation

**What goes wrong:** The clipboard snapshot is taken, then `clearContents()` is called, and restoring the items produces empty data or crashes.

**Why it happens:** `NSPasteboardItem` objects obtained from `pasteboardItems` may be backed by lazy data providers in the source app. Once the pasteboard is cleared or changes ownership, calling `data(forType:)` on a stale item returns `nil` or partial data.

**How to avoid:** At snapshot time, call `item.data(forType: type)` for every type in `item.types` immediately. Store `[NSPasteboard.PasteboardType: Data]` dictionaries. Never store `NSPasteboardItem` references across pasteboard mutations.

**Warning signs:** Restoring the clipboard results in empty content or the wrong content; `item.data(forType:)` returns `nil` on types that were present at snapshot time.

### Pitfall 2: Posting Keystrokes to Wrong Application

**What goes wrong:** Cmd+A/Cmd+C goes to AnyVim instead of the original text field, capturing nothing.

**Why it happens:** By the time the hotkey fires and `AccessibilityBridge` runs, if AnyVim has activated its own window (e.g., future permission alert), it becomes frontmost and receives the simulated keystrokes.

**How to avoid:** Capture `NSWorkspace.shared.frontmostApplication` as the FIRST action in `handleHotkeyTrigger()`, before any other work. Phase 3 doesn't show any UI, so this is not a problem yet — but it must be documented for Phase 5 when the vim window activates.

**Warning signs:** Clipboard content after Cmd+C is the same as before (changeCount unchanged), even in apps with populated text fields.

### Pitfall 3: changeCount Race on Fast Machines

**What goes wrong:** The app reads the clipboard immediately after posting Cmd+C and gets the old content because the target app hasn't finished processing the copy yet.

**Why it happens:** `CGEvent.post` is asynchronous — the event is queued, not delivered synchronously. On a fast machine the post returns before the target app has processed the keyDown and updated the clipboard.

**How to avoid:** Always `await Task.sleep(nanoseconds: captureDelayNs)` after Cmd+C and before reading the clipboard. 150ms is conservative. The `changeCount` check (D-10) distinguishes between "copied empty content" and "copy didn't run yet" — only after waiting.

**Warning signs:** Intermittent failures, more frequent on slower or heavily loaded machines. Clipboard content after delay shows old content.

### Pitfall 4: CGEventSource Omission on macOS 15

**What goes wrong:** Simulated keystrokes work in development but fail in production on macOS 15.

**Why it happens:** Without `CGEventSource(stateID: .hidSystemState)`, synthesized events may have no source context. macOS 15 is stricter about event provenance.

**How to avoid:** Always pass `CGEventSource(stateID: .hidSystemState)` as the source when creating `CGEvent` for synthesis. This is different from the `nil` source used when intercepting events with a tap.

**Warning signs:** Keystrokes have no effect; no errors logged. Console may show "event provenance" or "unauthorized event" messages.

### Pitfall 5: NSRunningApplication.activate Deprecation Warning on macOS 14+

**What goes wrong:** Build warnings on macOS 14+ SDK for `activate(options: .activateIgnoringOtherApps)`.

**Why it happens:** `NSApplicationActivationOptions.activateIgnoringOtherApps` is deprecated in macOS 14.

**How to avoid:** Use `activate(options: [])` — the empty options call is not deprecated and functionally equivalent for our use case (restoring a recently-active app in the same user session). Add `#available` guard if using `activate(from:options:)` for macOS 14+ path.

**Warning signs:** Build warnings referencing `activateIgnoringOtherApps`.

### Pitfall 6: Temp File Not Deleted on Abort Path

**What goes wrong:** User triggers the hotkey, something fails, vim is never opened, but the temp file is left behind.

**Why it happens:** Early return paths in `captureText()` skip cleanup.

**How to avoid:** Use `defer { try? FileManager.default.removeItem(at: tempFile) }` at the call site in Phase 5 (where the full cycle is wired). Phase 3 only creates the file — Phase 5 owns cleanup. Document this dependency clearly in Phase 3 output.

**Warning signs:** Accumulating `anyvim-*.txt` files in `/private/var/folders/`.

---

## Code Examples

### Full Keystroke + Delay Sequence (capture)

```swift
// Source: CGEvent Apple docs + Task.sleep Swift concurrency docs

@MainActor
func captureText() async -> String? {
    let before = NSPasteboard.general.changeCount
    postKeystroke(keyCode: CGKeyCode(kVK_ANSI_A), flags: .maskCommand)  // Cmd+A
    await Task.sleep(nanoseconds: Self.captureDelayNs)
    postKeystroke(keyCode: CGKeyCode(kVK_ANSI_C), flags: .maskCommand)  // Cmd+C
    await Task.sleep(nanoseconds: Self.captureDelayNs)

    let after = NSPasteboard.general.changeCount
    if after == before {
        // changeCount unchanged — copy did not fire (no focused text element)
        // D-10: log for debugging, return empty string not nil
        return ""
    }
    return NSPasteboard.general.string(forType: .string) ?? ""
}
```

### Restore Flow

```swift
// Source: NSRunningApplication docs + CGEvent docs

@MainActor
func restoreText(_ editedContent: String, to app: NSRunningApplication) async {
    guard !app.isTerminated else { return }  // D-08

    // Write edited content to clipboard for paste
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(editedContent, forType: .string)

    // Restore focus to original app
    app.activate(options: [])
    await Task.sleep(nanoseconds: Self.pasteDelayNs)  // D-03: longer for focus restore

    // Paste back
    postKeystroke(keyCode: CGKeyCode(kVK_ANSI_A), flags: .maskCommand)  // Cmd+A
    await Task.sleep(nanoseconds: Self.captureDelayNs)
    postKeystroke(keyCode: CGKeyCode(kVK_ANSI_V), flags: .maskCommand)  // Cmd+V
    await Task.sleep(nanoseconds: Self.restoreDelayNs)

    // D-06: now safe to restore original clipboard
    restoreClipboard(savedClipboard)
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `activate(options: .activateIgnoringOtherApps)` | `activate(options: [])` or `activate(from:options:)` | macOS 14 | IgnoringOtherApps flag deprecated; empty options works for in-session focus |
| `DispatchQueue.asyncAfter` for timing | `Task.sleep(nanoseconds:)` | Swift 5.5 / Swift 6 | Non-blocking, maintains @MainActor isolation, linear code flow |
| `sleep()` / `usleep()` (blocking) | `Task.sleep(nanoseconds:)` | Swift 5.5 | Must not block main thread; Task.sleep suspends without blocking |

**Deprecated/outdated:**
- `NSApplicationActivationOptions.activateIgnoringOtherApps`: Deprecated macOS 14 — has no effect. Use `activate(options: [])`.
- Blocking `sleep()` / `usleep()` on main thread: Never acceptable in a menu bar daemon. Freezes the run loop.

---

## Open Questions

1. **Exact delay values**
   - What we know: 150ms (Cmd+A→Cmd+C) and 200ms (focus restore→paste) are community-reported conservative values.
   - What's unclear: Whether these hold on modern M-series hardware with fast apps. Browser text areas may need different timing.
   - Recommendation: Implement as named constants (D-02), test empirically in Phase 3 with TextEdit, Safari, and Terminal. Adjust down if fast, up if flaky.

2. **`activate(from:options:)` macOS 14+ API**
   - What we know: New API requires specifying which app is activating. Available macOS 14+. Old `activate(options:)` still compiles, `ignoringOtherApps` just no longer works.
   - What's unclear: Whether `activate(options: [])` without `ignoringOtherApps` reliably brings the app forward in all scenarios (e.g., if another app stole focus after the vim session).
   - Recommendation: Use `activate(options: [])` for macOS 13 compatibility. Add a `#available(macOS 14, *)` branch using `activate(from: NSRunningApplication.current, options: [])` if the simple call proves unreliable.

3. **NSPasteboardItem and private/dynamic UTI types**
   - What we know: Some apps put private UTI types on the pasteboard (e.g., `com.apple.NSPasteboardTypeRTFD`, app-specific formats). Reading them with `data(forType:)` should work.
   - What's unclear: Whether writing back all opaque private types will work correctly for all apps, or if some types require the originating app to be present.
   - Recommendation: Implement the snapshot/restore as designed (D-05). In practice this works for clipboard managers like Maccy. If a specific app's restore fails, it's an edge case to document.

---

## Environment Availability

Step 2.6: SKIPPED — Phase 3 is purely code changes using macOS SDK APIs. No external CLI tools, databases, or services required beyond the existing Xcode build environment verified in Phase 1.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | XCTest (via Xcode 16.3) |
| Config file | AnyVim.xcodeproj — AnyVimTests target |
| Quick run command | `xcodebuild test -project AnyVim.xcodeproj -scheme AnyVim -destination 'platform=macOS'` |
| Full suite command | Same — single test target |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CAPT-01 | Clipboard snapshot captures all pasteboard items and types | unit | `xcodebuild test ... -only-testing:AnyVimTests/AccessibilityBridgeTests` | ❌ Wave 0 |
| CAPT-02 | Cmd+A and Cmd+C keystrokes are posted with correct key codes and flags | unit | `xcodebuild test ... -only-testing:AnyVimTests/AccessibilityBridgeTests` | ❌ Wave 0 |
| CAPT-03 | Captured text is written to a temp file at expected path pattern | unit | `xcodebuild test ... -only-testing:AnyVimTests/AccessibilityBridgeTests` | ❌ Wave 0 |
| CAPT-04 | Empty field (changeCount unchanged or empty string) produces empty temp file without crash | unit | `xcodebuild test ... -only-testing:AnyVimTests/AccessibilityBridgeTests` | ❌ Wave 0 |
| COMPAT-01 | Simulation of Cmd+A/C/V in native apps — accessibility permission required | manual-only | N/A — requires real Accessibility permission and real app | N/A |
| COMPAT-02 | Simulation in browser text areas — requires running browser | manual-only | N/A — requires real browser and Accessibility permission | N/A |
| COMPAT-03 | Keystroke timing constants are used at each step (not zero delay) | unit | `xcodebuild test ... -only-testing:AnyVimTests/AccessibilityBridgeTests` | ❌ Wave 0 |

**Manual-only justification:** COMPAT-01 and COMPAT-02 require real Accessibility permissions granted in System Settings, plus active text fields in real apps (TextEdit, Safari). These cannot be replicated in a unit test environment without granting permissions to the test runner, which is not reliable in CI. Manual smoke testing against the running app is the correct verification approach.

### Sampling Rate

- **Per task commit:** `xcodebuild test -project /Users/nick/Projects/any-vim/AnyVim.xcodeproj -scheme AnyVim -destination 'platform=macOS'`
- **Per wave merge:** Full suite (same command)
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `AnyVimTests/AccessibilityBridgeTests.swift` — covers CAPT-01, CAPT-02, CAPT-03, CAPT-04, COMPAT-03 with mock protocol injection
- [ ] Mock implementations: `MockKeystrokePoster`, `MockPasteboardAccessing`, `MockAppActivating` — needed for all AccessibilityBridge unit tests

---

## Project Constraints (from CLAUDE.md)

All directives from `CLAUDE.md` that apply to Phase 3:

| Directive | Implication for Phase 3 |
|-----------|------------------------|
| Swift 6 language mode, SWIFT_STRICT_CONCURRENCY=complete | `AccessibilityBridge` must be `@MainActor`. All async delays via `Task.sleep`, not DispatchQueue blocking. C callbacks nonisolated. |
| AppKit, no SwiftUI | No SwiftUI types. NSPasteboard, NSRunningApplication, NSWorkspace are all AppKit. |
| Raw AXUIElement, no AXSwift | Phase 3 doesn't need AXUIElement (per D-09 best-effort approach). If role-checking is ever added, use raw C API. |
| Manager classes as AppDelegate instance properties | `accessibilityBridge` must be stored as an instance property on AppDelegate. |
| Protocol-based testability | All system API interactions (CGEvent.post, NSPasteboard, NSRunningApplication) behind protocols. |
| Accessibility permission required | AccessibilityBridge must check `permissionManager.isAccessibilityGranted` before attempting keystroke simulation. |
| No user-facing configuration | Delay constants are hardcoded, not in UserDefaults or preferences UI. |

---

## Sources

### Primary (HIGH confidence)

- Apple Developer Documentation — NSPasteboard, pasteboardItems, NSPasteboardItem, clearContents, writeObjects
- Apple Developer Documentation — CGEvent, CGEventSource, CGEvent.post, CGEventFlags
- Apple Developer Documentation — NSRunningApplication, activate(options:), frontmostApplication
- Carbon HIToolbox — kVK_ANSI_A (0x00), kVK_ANSI_C (0x08), kVK_ANSI_V (0x09) keycodes
- Swift concurrency documentation — Task.sleep(nanoseconds:)
- NSPasteboard.org — TransientType/ConcealedType conventions

### Secondary (MEDIUM confidence)

- [Maccy clipboard manager (p0deje/Maccy)](https://github.com/p0deje/Maccy/blob/master/Maccy/Clipboard.swift) — NSPasteboard snapshot pattern with changeCount tracking (verified against Apple docs)
- [NSApplicationActivationOptions deprecation thread](https://developer.apple.com/documentation/appkit/nsrunningapplication/activate(options:)) — ignoringOtherApps deprecated macOS 14 (verified via multiple sources)
- [nspasteboard.org best practices](http://nspasteboard.org/) — TransientType marker guidance

### Tertiary (LOW confidence)

- Community-reported timing values (150ms Cmd+A→Cmd+C, 200ms focus restore→paste) — require empirical validation during Phase 3 implementation per STATE.md blocker

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all APIs are macOS SDK built-ins, no third-party libraries
- Architecture: HIGH — follows established TapInstalling/protocol pattern from Phase 2
- Pitfalls: HIGH for NSPasteboardItem lazy data (well-documented), MEDIUM for timing values (empirical)
- Activation API: MEDIUM — deprecation behavior on macOS 14+ confirmed by multiple sources; exact behavior of empty-options activate needs runtime validation

**Research date:** 2026-04-01
**Valid until:** 2026-07-01 (stable platform APIs; timing values need re-validation on each new macOS major version)
