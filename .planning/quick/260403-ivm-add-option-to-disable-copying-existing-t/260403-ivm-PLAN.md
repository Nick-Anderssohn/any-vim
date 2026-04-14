---
phase: quick
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - Sources/AnyVim/EditCycleCoordinating.swift
  - Sources/AnyVim/AccessibilityBridge.swift
  - Sources/AnyVim/AppDelegate.swift
  - Sources/AnyVim/MenuBarController.swift
  - AnyVimTests/EditCycleCoordinatorTests.swift
  - AnyVimTests/MenuBarControllerTests.swift
autonomous: true
requirements: []
must_haves:
  truths:
    - "Menu bar contains a 'Copy Existing Text' toggle that defaults to ON"
    - "When toggle is ON, double-tap Control captures existing text into vim (current behavior)"
    - "When toggle is OFF, double-tap Control opens vim with an empty buffer"
    - "When toggle is OFF, edited text is still pasted back on :wq"
    - "Toggle state persists across app restarts via UserDefaults"
  artifacts:
    - path: "Sources/AnyVim/EditCycleCoordinating.swift"
      provides: "openEmpty() method on TextCapturing protocol"
    - path: "Sources/AnyVim/AccessibilityBridge.swift"
      provides: "openEmpty() implementation — creates CaptureResult with empty temp file, no Cmd+A/Cmd+C"
    - path: "Sources/AnyVim/AppDelegate.swift"
      provides: "Conditional dispatch in handleHotkeyTrigger based on UserDefaults copyExistingText"
    - path: "Sources/AnyVim/MenuBarController.swift"
      provides: "Copy Existing Text toggle menu item"
  key_links:
    - from: "Sources/AnyVim/AppDelegate.swift"
      to: "UserDefaults copyExistingText"
      via: "bool(forKey:) check before captureText vs openEmpty"
      pattern: "UserDefaults.*copyExistingText"
    - from: "Sources/AnyVim/MenuBarController.swift"
      to: "UserDefaults copyExistingText"
      via: "Toggle sets/reads the same key"
      pattern: "copyExistingText"
---

<objective>
Add a "Copy Existing Text" toggle to the menu bar that controls whether double-tap Control copies the focused text field's contents into vim or opens vim empty.

Purpose: Some users want to use AnyVim to compose new text from scratch without capturing whatever is currently in the text field.
Output: Menu toggle + conditional capture logic, with tests.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@Sources/AnyVim/EditCycleCoordinating.swift
@Sources/AnyVim/AccessibilityBridge.swift
@Sources/AnyVim/AppDelegate.swift
@Sources/AnyVim/MenuBarController.swift
@Sources/AnyVim/SystemProtocols.swift
@Sources/AnyVim/ClipboardGuard.swift
@Sources/AnyVim/TempFileManager.swift
@AnyVimTests/EditCycleCoordinatorTests.swift
@AnyVimTests/MenuBarControllerTests.swift

<interfaces>
<!-- Key types and contracts the executor needs -->

From Sources/AnyVim/EditCycleCoordinating.swift:
```swift
@MainActor
protocol TextCapturing {
    func captureText() async -> CaptureResult?
    func restoreText(_ editedContent: String, captureResult: CaptureResult) async
    func abortAndRestore(captureResult: CaptureResult)
}
```

From Sources/AnyVim/AccessibilityBridge.swift:
```swift
struct CaptureResult {
    let tempFileURL: URL
    let originalApp: NSRunningApplication
    let clipboardSnapshot: ClipboardSnapshot
}
```

The restore flow needs `CaptureResult` regardless of whether text was captured — it uses `originalApp` for focus restore and `clipboardSnapshot` for clipboard restore. Even when opening empty, we still need these fields populated.

UserDefaults keys already in use: "customVimPath". New key: "copyExistingText".
</interfaces>
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: Add openEmpty() to TextCapturing and AccessibilityBridge</name>
  <files>
    Sources/AnyVim/EditCycleCoordinating.swift
    Sources/AnyVim/AccessibilityBridge.swift
    AnyVimTests/EditCycleCoordinatorTests.swift
  </files>
  <behavior>
    - openEmpty() returns a CaptureResult with an empty temp file, the current frontmost app, and a clipboard snapshot
    - openEmpty() does NOT post any keystrokes (no Cmd+A, no Cmd+C)
    - openEmpty() returns nil if accessibility permission is missing or no frontmost app (same guards as captureText)
    - handleHotkeyTrigger calls openEmpty() when UserDefaults "copyExistingText" is false
    - handleHotkeyTrigger calls captureText() when UserDefaults "copyExistingText" is true (or key absent — defaults to true)
    - After openEmpty(), the full restore flow still works (:wq pastes back, :q! aborts cleanly)
  </behavior>
  <action>
    1. Add `func openEmpty() async -> CaptureResult?` to the `TextCapturing` protocol in EditCycleCoordinating.swift.

    2. Implement `openEmpty()` in AccessibilityBridge.swift. It should:
       - Guard on `permissionChecker.isAccessibilityGranted` (return nil if false)
       - Capture `originalApp` via `appActivator.frontmostApplication()` (return nil if nil)
       - Snapshot clipboard via `clipboardGuard.snapshot()` (needed for restore on abort)
       - Create an empty temp file via `tempFileManager.createTempFile(content: "")` (return nil if fails, restore clipboard on failure just like captureText does)
       - Return `CaptureResult(tempFileURL:, originalApp:, clipboardSnapshot:)` — NO keystrokes posted

    3. Update `AppDelegate.handleHotkeyTrigger()` to check `UserDefaults.standard.bool(forKey: "copyExistingText")`. IMPORTANT: `bool(forKey:)` returns `false` when key is absent, but we want the default to be ON. So use `UserDefaults.standard.object(forKey: "copyExistingText") == nil || UserDefaults.standard.bool(forKey: "copyExistingText")` — or register a default. Prefer registering defaults: in `applicationDidFinishLaunching`, add `UserDefaults.standard.register(defaults: ["copyExistingText": true])` before any reads. Then the check in handleHotkeyTrigger is simply:
       ```swift
       let result: CaptureResult?
       if UserDefaults.standard.bool(forKey: "copyExistingText") {
           result = await accessibilityBridge.captureText()
       } else {
           result = await accessibilityBridge.openEmpty()
       }
       guard let result else {
           showCaptureFailureAlert()
           return
       }
       ```
       The rest of the method (vim session, save/abort) stays exactly the same.

    4. Add `openEmpty()` to `MockTextCapture` in EditCycleCoordinatorTests.swift:
       - Track `openEmptyCallCount` and return `openEmptyResult` (same pattern as captureText mock)

    5. Add tests:
       - `testOpenEmptyCalledWhenCopyExistingTextDisabled`: Set UserDefaults "copyExistingText" to false, trigger, assert `openEmptyCallCount == 1` and `captureTextCallCount == 0`
       - `testCaptureTextCalledWhenCopyExistingTextEnabled`: Set UserDefaults "copyExistingText" to true, trigger, assert `captureTextCallCount == 1` and `openEmptyCallCount == 0`
       - `testCaptureTextCalledWhenCopyExistingTextKeyAbsent`: Remove the key, trigger, assert `captureTextCallCount == 1` (default is ON)
       - Clean up UserDefaults in tearDown: `UserDefaults.standard.removeObject(forKey: "copyExistingText")`
  </action>
  <verify>
    <automated>xcodebuild test -project AnyVim.xcodeproj -scheme AnyVim -destination 'platform=macOS' -only-testing:AnyVimTests/EditCycleCoordinatorTests 2>&1 | tail -20</automated>
  </verify>
  <done>
    - TextCapturing protocol has openEmpty() method
    - AccessibilityBridge.openEmpty() creates empty CaptureResult without keystrokes
    - handleHotkeyTrigger dispatches based on UserDefaults "copyExistingText" (default true)
    - All existing EditCycleCoordinatorTests still pass
    - New tests for the toggle behavior pass
  </done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: Add Copy Existing Text toggle to menu bar</name>
  <files>
    Sources/AnyVim/MenuBarController.swift
    AnyVimTests/MenuBarControllerTests.swift
  </files>
  <behavior>
    - Menu contains "Copy Existing Text" item with a checkmark when enabled
    - Clicking the item toggles the UserDefaults "copyExistingText" value
    - When UserDefaults key is absent (first run), item shows as checked (default ON)
    - Toggle appears in the settings section, between the vim path section and "Launch at Login"
  </behavior>
  <action>
    1. In `MenuBarController.buildMenu()`, add a "Copy Existing Text" toggle menu item. Place it AFTER the vim path section separator and BEFORE the "Launch at Login" item. The item should:
       - Title: "Copy Existing Text"
       - Action: `#selector(toggleCopyExistingText)`
       - Target: `self`
       - State: `.on` when `UserDefaults.standard.bool(forKey: "copyExistingText")` is true, `.off` otherwise
       - Since `register(defaults:)` is called in AppDelegate before menu construction, `bool(forKey:)` will correctly return true when key is absent

    2. Add the action method:
       ```swift
       @objc private func toggleCopyExistingText() {
           let current = UserDefaults.standard.bool(forKey: "copyExistingText")
           UserDefaults.standard.set(!current, forKey: "copyExistingText")
       }
       ```
       No menu rebuild needed — buildMenu() reads live state on each open.

    3. Add tests in MenuBarControllerTests.swift:
       - `testBuildMenuContainsCopyExistingTextItem`: Assert menu contains "Copy Existing Text" item
       - `testCopyExistingTextItemCheckedWhenEnabled`: Set UserDefaults to true, assert item state is `.on`
       - `testCopyExistingTextItemUncheckedWhenDisabled`: Set UserDefaults to false, assert item state is `.off`
       - Register defaults in setUp: `UserDefaults.standard.register(defaults: ["copyExistingText": true])`
       - Clean up in tearDown: `UserDefaults.standard.removeObject(forKey: "copyExistingText")`
  </action>
  <verify>
    <automated>xcodebuild test -project AnyVim.xcodeproj -scheme AnyVim -destination 'platform=macOS' -only-testing:AnyVimTests/MenuBarControllerTests 2>&1 | tail -20</automated>
  </verify>
  <done>
    - Menu bar shows "Copy Existing Text" toggle with correct checkmark state
    - Clicking toggles the UserDefaults value
    - All existing MenuBarControllerTests still pass
    - New toggle tests pass
  </done>
</task>

</tasks>

<verification>
Run full test suite to confirm no regressions:
```bash
xcodebuild test -project AnyVim.xcodeproj -scheme AnyVim -destination 'platform=macOS' 2>&1 | tail -30
```
</verification>

<success_criteria>
- "Copy Existing Text" toggle visible in menu bar, defaults to ON
- When OFF: double-tap Control opens vim with empty buffer (no Cmd+A/Cmd+C fired)
- When ON: existing behavior preserved (captures text from focused field)
- Restore flow works in both modes (:wq pastes back, :q! aborts cleanly)
- All tests pass (existing + new)
</success_criteria>

<output>
After completion, create `.planning/quick/260403-ivm-add-option-to-disable-copying-existing-t/260403-ivm-SUMMARY.md`
</output>
