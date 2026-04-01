# Phase 2: Global Hotkey Detection - Research

**Researched:** 2026-03-31
**Domain:** CGEventTap, modifier key double-tap detection, Swift 6 concurrency, tap health monitoring
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Track `CGEventType.flagsChanged` events only — this is the natural event type for modifier-only keys. A "tap" is defined as flagsChanged with Control flag set, then flagsChanged with Control flag cleared, with no other keys pressed in between.
- **D-02:** Both left and right Control keys count toward double-tap detection. Users don't think about which Control key they're pressing.
- **D-03:** Double-tap timing threshold is ~350ms (per HOTKEY-02). Two Control tap-release cycles within this window trigger the app.
- **D-04:** Any intervening key press (modifier or otherwise) between the two Control taps resets the double-tap state machine. This prevents Ctrl+C followed by a quick Control tap from false-triggering.
- **D-05:** CGEventTap code lives in a dedicated `HotkeyManager` class. AppDelegate creates and retains it as an instance property, following the same pattern as PermissionManager and LoginItemManager.
- **D-06:** The event tap is installed on launch if both Accessibility and Input Monitoring permissions are already granted. If not, HotkeyManager installs the tap when notified that permissions have been granted (via PermissionManager's onChange callback).
- **D-07:** Use `.defaultTap` (active tap) per CLAUDE.md guidance. This requires Accessibility permission and allows optionally consuming events in the future.
- **D-08:** HotkeyManager runs its own periodic timer to call `CGEvent.tapIsEnabled()`. If the tap is found disabled, attempt `CGEvent.tapEnable()` first. If that fails, reinstall the tap from scratch.
- **D-09:** If the tap cannot be reinstalled, show a warning state in the menu bar dropdown (similar to permission status items). Keep retrying on the health check interval. No modal alert — just persistent menu bar indication.
- **D-10:** HotkeyManager takes an `onTrigger` closure, consistent with PermissionManager's `onChange` closure pattern. AppDelegate provides the closure when creating HotkeyManager. Simple, type-safe, and testable.

### Claude's Discretion

- Health check timer interval (should be reasonable — every few seconds, similar to permission poll)
- Internal state machine implementation details for double-tap detection
- Whether to log tap health events for debugging
- How HotkeyManager learns about permission grants (direct PermissionManager integration vs AppDelegate mediation)
- Test strategy for the event tap (protocol-based mocking of CGEvent APIs)

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| HOTKEY-01 | App detects double-tap of Control key system-wide via CGEventTap | CGEventTap with `.flagsChanged` event mask, `.defaultTap`, added to `CFRunLoopGetMain()` |
| HOTKEY-02 | Double-tap detection uses a timing threshold (~350ms) to distinguish from single taps and held modifier | `Date.timeIntervalSinceNow` / `ProcessInfo.processInfo.systemUptime` for sub-millisecond timing; 350ms window confirmed by CONTEXT.md D-03 |
| HOTKEY-03 | Hotkey works regardless of which application is focused | `.cgSessionEventTap` + `.headInsertEventTap` intercepts events before any app sees them; confirmed by community reference projects |
</phase_requirements>

---

## Summary

CGEventTap with the `.flagsChanged` event type is the correct and only supported macOS mechanism for observing modifier-only key presses globally. Detecting a "double-tap" requires a state machine that tracks tap-release cycles: when `flagsChanged` fires with the Control modifier present and no other modifiers active, record a timestamp; when it fires again without Control (the key-up), the tap-release is complete. A second such cycle within 350ms constitutes a double-tap. Any intervening `flagsChanged` or `keyDown` event resets the state machine.

The critical production concern is silent tap death: macOS TCC ties event tap permissions to code-signing identity. After a re-sign (common during development) and re-launch via Finder/Dock, the tap handle is non-nil but callbacks never fire — no error, no log. The fix is a periodic health check via `CGEvent.tapIsEnabled()` with a recovery path that tries `CGEvent.tapEnable()` and, if that fails, tears down and reinstalls the tap.

For Swift 6 with `@MainActor` on AppDelegate and manager classes: the CGEventTap C callback is a bare C function pointer and cannot capture actor context directly. The canonical pattern is to schedule the actual state-machine work onto `DispatchQueue.main` (or call `MainActor.assumeIsolated`) from inside the nonisolated C callback. This keeps all mutable HotkeyManager state on the main actor while satisfying Swift 6 strict concurrency.

**Primary recommendation:** Implement `HotkeyManager` as a `@MainActor final class` with a C callback shim that bounces to `DispatchQueue.main.async`. Add a `Timer` health check every 5 seconds (matching the PermissionManager poll interval pattern already established). Use a 4-state machine: `.idle`, `.firstTapDown`, `.firstTapUp`, `.secondTapDown`.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| CoreGraphics (CGEventTap) | macOS 13+ SDK | System-wide event interception | Only supported API for pre-application event observation on macOS |
| Carbon (HIToolbox keycodes) | macOS 13+ SDK | `kVK_Control` (0x3B) / `kVK_RightControl` (0x3E) constants | Standard virtual keycode definitions used by all macOS event-tap projects |
| Foundation (Timer, Date) | macOS 13+ SDK | Health check timer, tap timing | Built-in; no additional dependencies |

### Supporting

No third-party dependencies for this phase. All needed APIs are in the macOS SDK.

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `.flagsChanged` event mask | `keyDown` + modifier check | `flagsChanged` is the correct type for modifier-only keys; `keyDown` does not fire for modifier-only presses |
| `.defaultTap` | `.listenOnly` | `.listenOnly` cannot consume events (no future-proofing); `.defaultTap` requires Accessibility permission (already required) |
| `.cgSessionEventTap` | `.cghidEventTap` | Session tap is sufficient and lower privilege; HID tap is unnecessary for this use case |
| C callback shim + `DispatchQueue.main` | `NSEvent.addGlobalMonitorForEvents` | `NSEvent` monitor is passive-only and has lower fidelity for modifier-only keys |

**Installation:** No additional packages. All APIs are SDK-native.

---

## Architecture Patterns

### Recommended Project Structure

```
Sources/AnyVim/
├── AppDelegate.swift          # owns HotkeyManager as instance property (existing)
├── PermissionManager.swift    # already checks permissions; HotkeyManager queries it (existing)
├── HotkeyManager.swift        # NEW — CGEventTap lifecycle, double-tap state machine, health timer
├── MenuBarController.swift    # extend buildMenu() to show tap health warning (existing)
└── ...
```

### Pattern 1: CGEventTap Setup with CFRunLoop (Main Thread)

**What:** Create the tap, source it into the main run loop, enable it.
**When to use:** On app launch (if permissions already granted) or when permissions are newly granted.

```swift
// Source: https://gaitatzis.medium.com/capture-key-bindings-in-swift-3050b0ccbf42
// and Apple CoreGraphics docs

// 1. Event mask — flagsChanged only (D-01)
let eventMask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)

// 2. Create tap — .defaultTap requires Accessibility permission (D-07)
guard let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .defaultTap,
    eventsOfInterest: eventMask,
    callback: hotkeyManagerCCallback,  // bare C function — see Pattern 2
    userInfo: selfPointer               // Unmanaged<HotkeyManager>.passUnretained(self).toOpaque()
) else {
    // Tap creation failed — permissions not yet granted
    return
}

// 3. Source into main run loop
let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)

// Retain tap and source as instance properties
self.eventTap = tap
self.runLoopSource = source
```

### Pattern 2: C Callback Shim for Swift 6 / @MainActor

**What:** CGEventTap requires a C function pointer callback. In Swift 6, the main HotkeyManager state is `@MainActor`-isolated. The callback must be a global (or nonisolated) C-compatible function that bounces to the main actor.
**When to use:** Always — this is the only Swift-6-compliant pattern for CGEventTap.

```swift
// Global C-compatible callback — cannot capture actor context directly
private func hotkeyManagerCCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let ptr = userInfo else { return Unmanaged.passRetained(event) }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(ptr).takeUnretainedValue()

    // Re-enable tap on system-initiated disable (timeout or user-input disable)
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = manager.eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return nil
    }

    // Snapshot event data before dispatching (CGEvent is not thread-safe)
    let flags = event.flags
    let keycode = event.getIntegerValueField(.keyboardEventKeycode)

    // Bounce to main actor — all state mutation happens there
    DispatchQueue.main.async {
        manager.handleFlagsChanged(flags: flags, keycode: Int(keycode))
    }

    return Unmanaged.passRetained(event)
}
```

### Pattern 3: Double-Tap State Machine

**What:** 4-state machine tracking tap-release cycles for Control key.
**When to use:** Inside `handleFlagsChanged` — called on main actor from the C callback shim.

```swift
// Virtual key codes from Carbon/HIToolbox/Events.h
// kVK_Control = 0x3B (59), kVK_RightControl = 0x3E (62)
private let controlKeycodes: Set<Int> = [0x3B, 0x3E]

// State machine
private enum DoubleTapState {
    case idle
    case firstTapDown(at: TimeInterval)
    case firstTapUp(at: TimeInterval)
    case secondTapDown
}

private var doubleTapState: DoubleTapState = .idle

// Called on @MainActor from C callback bounce
func handleFlagsChanged(flags: CGEventFlags, keycode: Int) {
    let controlActive = flags.contains(.maskControl)
    let isControlKey = controlKeycodes.contains(keycode)
    let now = ProcessInfo.processInfo.systemUptime  // monotonic, sub-ms precision

    // Any non-Control modifier key activity resets state machine (D-04)
    if !isControlKey {
        doubleTapState = .idle
        return
    }

    switch doubleTapState {
    case .idle:
        if controlActive { doubleTapState = .firstTapDown(at: now) }

    case .firstTapDown(let start):
        if !controlActive {
            // Control released — first tap complete
            doubleTapState = .firstTapUp(at: now)
        } else if now - start > 0.350 {
            // Held too long — held modifier, not a tap; reset
            doubleTapState = .idle
        }

    case .firstTapUp(let upTime):
        if now - upTime > 0.350 {
            // Too slow — reset to idle
            doubleTapState = .idle
        } else if controlActive {
            doubleTapState = .secondTapDown
        }

    case .secondTapDown:
        if !controlActive {
            // Second tap complete — fire trigger
            doubleTapState = .idle
            onTrigger?()
        }
    }
}
```

### Pattern 4: Tap Health Monitor Timer

**What:** Periodic check via `CGEvent.tapIsEnabled()`. Matches the PermissionManager poll timer pattern already established in Phase 1.
**When to use:** Start alongside tap installation; keep running for app lifetime.

```swift
// 5-second interval — matches PermissionManager's 3-second poll cadence in spirit
// Use 5s here since tap health changes are less frequent than permission changes
private var healthTimer: Timer?

func startHealthMonitor() {
    healthTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
        self?.checkTapHealth()
    }
}

private func checkTapHealth() {
    guard let tap = eventTap else { return }

    if CGEvent.tapIsEnabled(tap: tap) { return }  // healthy — nothing to do

    // Attempt re-enable first (cheaper than full reinstall)
    CGEvent.tapEnable(tap: tap, enable: true)

    // Verify re-enable succeeded
    if !CGEvent.tapIsEnabled(tap: tap) {
        // Re-enable failed — full reinstall
        tearDownTap()
        installTap()
    }

    // Update health status for menu bar (D-09)
    isTapHealthy = CGEvent.tapIsEnabled(tap: tap)
    // Caller (AppDelegate or MenuBarController) observes isTapHealthy via KVO/closure
}
```

### Pattern 5: HotkeyManager Protocol for Testability

**What:** Protocol-based abstraction matching the `PermissionChecking` pattern from Phase 1.
**When to use:** MenuBarController and AppDelegate reference the protocol type, not the concrete class.

```swift
protocol HotkeyManaging: AnyObject {
    var isTapHealthy: Bool { get }
    var onTrigger: (() -> Void)? { get set }
    func install()
    func tearDown()
}

@MainActor
final class HotkeyManager: HotkeyManaging { ... }
```

### Anti-Patterns to Avoid

- **Non-nil tap assumed healthy:** `tapCreate` returning non-nil does NOT mean callbacks will fire. Always verify with `tapIsEnabled`. This is the most common silent failure in shipping apps.
- **C callback capturing `self` via closure:** CGEventTapCallBack is a C function pointer — it cannot close over Swift values. Pass `self` via `userInfo` as an `UnsafeMutableRawPointer`.
- **Mutating state directly in C callback:** Swift 6 will reject mutation of `@MainActor`-isolated properties from a nonisolated context. Always bounce via `DispatchQueue.main.async`.
- **Using `keyDown` for Control detection:** `keyDown` events do not fire for modifier-only key presses. Only `flagsChanged` catches Control press/release.
- **Ignoring `.tapDisabledByTimeout` and `.tapDisabledByUserInput` event types in callback:** These arrive as CGEventType values in the callback — if not handled, the tap silently stops receiving events until reinstalled.
- **Tearing down the RunLoop source before the tap:** Remove tap from RunLoop before releasing the CFMachPort to avoid dangling source references.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Virtual keycode constants | Magic numbers like `59`, `62` | Import Carbon and use `kVK_Control`, `kVK_RightControl` | Carbon HIToolbox constants are canonical; magic numbers are brittle and unclear |
| Monotonic timing | `Date()` comparisons | `ProcessInfo.processInfo.systemUptime` | `systemUptime` is monotonic and immune to clock adjustments; `Date()` can jump on NTP sync |
| Tap re-enable on system-initiated disable | Separate health logic | Handle `.tapDisabledByTimeout` / `.tapDisabledByUserInput` in the C callback itself | The callback fires synchronously before the tap goes cold; re-enabling there is faster than waiting for the next timer tick |

**Key insight:** The CGEventTap C API looks simple but has several non-obvious sharp edges (silent disable, callback type constraints, RunLoop ownership). The implementation surface is small — resist the urge to over-engineer; the standard patterns from the macOS community are well-established.

---

## Common Pitfalls

### Pitfall 1: Silent Tap Death After Re-Sign

**What goes wrong:** After a development re-sign and re-launch via Finder/Dock, `tapCreate` returns non-nil, `tapIsEnabled` returns true at creation time, but callbacks never fire.
**Why it happens:** TCC ties event tap permissions to code-signing identity. Re-signing creates a new identity that Launch Services evaluates, potentially voiding the prior grant. Direct binary launch bypasses this.
**How to avoid:** The periodic health check (`CGEvent.tapIsEnabled()` every 5 seconds) catches this and reinstalls the tap. During development, expect this after re-signing.
**Warning signs:** Double-tap has no effect after re-launching from Dock/Finder; launching binary directly from terminal works fine.
Source: https://danielraffel.me/til/2026/02/19/cgevent-taps-and-code-signing-the-silent-disable-race/

### Pitfall 2: `flagsChanged` Fires for ALL Modifier Changes

**What goes wrong:** `flagsChanged` fires when Shift, Command, Option, or any other modifier changes — not just Control. If the state machine doesn't filter by keycode, it will incorrectly reset or advance state on unrelated modifier key activity.
**Why it happens:** The `CGEventMask` filters event *type*, not which key changed. Within the callback, you must check the keycode to know which modifier changed.
**How to avoid:** Check `event.getIntegerValueField(.keyboardEventKeycode)` against `{0x3B, 0x3E}` (left/right Control). If the keycode is anything else, reset state (D-04).
**Warning signs:** State machine advances spuriously when pressing Shift or Command.

### Pitfall 3: Held Control Counted as Two Taps

**What goes wrong:** Holding Control down fires one `flagsChanged` event (flags set) but no "release" event while held. The state machine must time out of `firstTapDown` if Control is held too long — otherwise a single hold followed by a second tap will trigger.
**Why it happens:** `flagsChanged` fires once on press and once on release. There is no "key repeat" for modifier keys. A held modifier stays in the "flags set" state until released.
**How to avoid:** In the `firstTapDown` case, check elapsed time. If more than ~350ms has passed since the down event and Control is still held, reset to idle. (The state machine pattern above handles this.)
**Warning signs:** Ctrl+C followed by a quick Control tap fires the trigger.

### Pitfall 4: CGEventTap Requires Both Permissions

**What goes wrong:** Creating a `.defaultTap` requires Accessibility permission. `CGRequestListenEventAccess()` is needed for the app to appear in Input Monitoring. If either is missing, `tapCreate` returns nil silently (no exception, no log).
**Why it happens:** TCC enforces these at the OS level; the API simply returns nil on unauthorized access.
**How to avoid:** D-06 — only attempt tap installation after both permissions are confirmed via `PermissionManager.isAccessibilityGranted && isInputMonitoringGranted`.
**Warning signs:** `tapCreate` returns nil; permissions are shown as granted in System Settings but tap never works.

### Pitfall 5: Swift 6 Concurrency Errors with C Callback

**What goes wrong:** The CGEventTap C callback is not isolated to any actor. Accessing `@MainActor`-isolated properties from within it is a Swift 6 compile error.
**Why it happens:** Swift 6 strict concurrency (`SWIFT_STRICT_CONCURRENCY=complete`) enforces actor isolation at compile time. C callbacks are nonisolated.
**How to avoid:** Use `DispatchQueue.main.async { manager.handleFlagsChanged(...) }` from the C callback to bounce work to the main actor. Never access HotkeyManager state directly in the callback body.
**Warning signs:** `Main actor-isolated property 'X' can not be mutated from a nonisolated context` compiler error.

---

## Code Examples

### Full HotkeyManager Skeleton

```swift
// Source: Synthesized from Apple CoreGraphics docs, alt-tab-macos reference,
// and danielraffel.me CGEventTap code-signing article.
import Carbon.HIToolbox
import CoreGraphics
import Foundation

protocol HotkeyManaging: AnyObject {
    var isTapHealthy: Bool { get }
    var onTrigger: (() -> Void)? { get set }
    func install(permissionManager: PermissionChecking)
    func tearDown()
}

@MainActor
final class HotkeyManager: HotkeyManaging {

    // MARK: - Public state

    private(set) var isTapHealthy: Bool = false
    var onTrigger: (() -> Void)?

    // MARK: - Internal tap state

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var healthTimer: Timer?

    // MARK: - Double-tap state machine

    private enum DoubleTapState {
        case idle
        case firstTapDown(at: TimeInterval)
        case firstTapUp(at: TimeInterval)
        case secondTapDown
    }
    private var doubleTapState: DoubleTapState = .idle
    private let controlKeycodes: Set<Int> = [Int(kVK_Control), Int(kVK_RightControl)]

    // MARK: - Lifecycle

    func install(permissionManager: PermissionChecking) {
        guard permissionManager.isAccessibilityGranted,
              permissionManager.isInputMonitoringGranted else { return }
        installTap()
        startHealthMonitor()
    }

    func tearDown() {
        healthTimer?.invalidate()
        healthTimer = nil
        tearDownTap()
    }

    // MARK: - Tap install / remove

    private func installTap() {
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: hotkeyEventTapCallback,
            userInfo: selfPtr
        ) else {
            isTapHealthy = false
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
        isTapHealthy = true
    }

    private func tearDownTap() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isTapHealthy = false
    }

    // MARK: - Health monitor

    private func startHealthMonitor() {
        healthTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkTapHealth()
        }
    }

    private func checkTapHealth() {
        guard let tap = eventTap else {
            isTapHealthy = false
            return
        }
        if CGEvent.tapIsEnabled(tap: tap) {
            isTapHealthy = true
            return
        }
        // Try cheap re-enable first
        CGEvent.tapEnable(tap: tap, enable: true)
        if CGEvent.tapIsEnabled(tap: tap) {
            isTapHealthy = true
            return
        }
        // Full reinstall
        tearDownTap()
        installTap()
    }

    // MARK: - State machine (called on main actor from C callback bounce)

    func handleFlagsChanged(flags: CGEventFlags, keycode: Int) {
        let isControl = controlKeycodes.contains(keycode)
        let controlActive = flags.contains(.maskControl)
        let now = ProcessInfo.processInfo.systemUptime

        if !isControl {
            // Some other modifier changed — reset (D-04)
            doubleTapState = .idle
            return
        }

        switch doubleTapState {
        case .idle:
            if controlActive { doubleTapState = .firstTapDown(at: now) }

        case .firstTapDown(let start):
            if !controlActive {
                doubleTapState = .firstTapUp(at: now)
            } else if now - start > 0.350 {
                doubleTapState = .idle  // held — not a tap
            }

        case .firstTapUp(let upTime):
            if now - upTime > 0.350 {
                doubleTapState = .idle  // too slow
            } else if controlActive {
                doubleTapState = .secondTapDown
            }

        case .secondTapDown:
            if !controlActive {
                doubleTapState = .idle
                onTrigger?()
            }
        }
    }

    // MARK: - Re-enable on system-initiated tap disable (called from C callback)

    func handleTapDisabled() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }
}

// MARK: - C callback (nonisolated, cannot capture actor state)

private func hotkeyEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let ptr = userInfo else { return Unmanaged.passRetained(event) }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(ptr).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        DispatchQueue.main.async { manager.handleTapDisabled() }
        return nil
    }

    guard type == .flagsChanged else { return Unmanaged.passRetained(event) }

    let flags = event.flags
    let keycode = Int(event.getIntegerValueField(.keyboardEventKeycode))
    DispatchQueue.main.async { manager.handleFlagsChanged(flags: flags, keycode: keycode) }

    return Unmanaged.passRetained(event)
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `NSEvent.addGlobalMonitorForEvents` for modifier keys | `CGEventTap` with `.flagsChanged` | macOS 10.x era | NSEvent monitor is passive (cannot consume) and misses some modifier events; CGEventTap is the authoritative approach |
| `kVK_Control` from Carbon framework imported directly | `import Carbon.HIToolbox` submodule import | Swift 3+ | Submodule import avoids pulling in all of Carbon |

**No deprecated items relevant to this phase.**

---

## Open Questions

1. **How should `isTapHealthy` propagate to MenuBarController?**
   - What we know: Phase 1 established that `MenuBarController.buildMenu()` is called with current state from AppDelegate. AppDelegate calls `buildMenu()` on permission change.
   - What's unclear: Whether MenuBarController should directly observe `isTapHealthy` or whether AppDelegate mediates (same pattern as permission status).
   - Recommendation: Follow existing pattern — AppDelegate calls `statusItem.menu = menuBarController.buildMenu()` when `isTapHealthy` changes. Keep MenuBarController accepting health state as a parameter, not reaching into HotkeyManager directly. (Claude's discretion per D-09.)

2. **Should the held-Control timeout in `firstTapDown` be exactly 350ms or slightly less?**
   - What we know: 350ms is the total double-tap window (D-03). A hold-to-reset at 350ms means a very fast double-tap followed immediately by a hold could still register.
   - What's unclear: Real-world feel; requires manual testing.
   - Recommendation: Use 300ms for the single-tap hold timeout (slightly shorter than the inter-tap window). Adjust during Phase 2 testing.

---

## Environment Availability

Step 2.6: SKIPPED — this phase is purely code changes against the macOS SDK. No external CLI tools, databases, or services are required beyond the development environment (Xcode 16.3, macOS 13+ SDK) already confirmed available in Phase 1.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | XCTest (Xcode built-in) |
| Config file | AnyVim.xcodeproj test target |
| Quick run command | `xcodebuild test -project AnyVim.xcodeproj -scheme AnyVim -destination 'platform=macOS'` |
| Full suite command | `xcodebuild test -project AnyVim.xcodeproj -scheme AnyVim -destination 'platform=macOS'` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| HOTKEY-01 | CGEventTap installs when both permissions granted | unit (protocol mock) | `xcodebuild test ... -only-testing:HotkeyManagerTests/testTapInstallsWhenPermissionsGranted` | ❌ Wave 0 |
| HOTKEY-01 | Tap not installed when Accessibility missing | unit (protocol mock) | `xcodebuild test ... -only-testing:HotkeyManagerTests/testTapSkipsInstallWhenAccessibilityMissing` | ❌ Wave 0 |
| HOTKEY-02 | Two taps within 350ms fires onTrigger | unit (state machine) | `xcodebuild test ... -only-testing:HotkeyManagerTests/testDoubleTapWithin350msFires` | ❌ Wave 0 |
| HOTKEY-02 | Two taps outside 350ms does not fire | unit (state machine) | `xcodebuild test ... -only-testing:HotkeyManagerTests/testDoubleTapOutside350msDoesNotFire` | ❌ Wave 0 |
| HOTKEY-02 | Single tap does not fire | unit (state machine) | `xcodebuild test ... -only-testing:HotkeyManagerTests/testSingleTapDoesNotFire` | ❌ Wave 0 |
| HOTKEY-02 | Held Control does not fire | unit (state machine) | `xcodebuild test ... -only-testing:HotkeyManagerTests/testHeldControlDoesNotFire` | ❌ Wave 0 |
| HOTKEY-02 | Intervening key resets state machine | unit (state machine) | `xcodebuild test ... -only-testing:HotkeyManagerTests/testInterveningKeyResetsStateMachine` | ❌ Wave 0 |
| HOTKEY-03 | Works system-wide (CGEventTap session tap) | manual / integration | N/A — requires live tap, cannot be unit tested | N/A — manual |

**Note on HOTKEY-03 testing:** System-wide tap behavior cannot be unit tested without a live CGEventTap. Manual verification during implementation is the correct approach: run the app, verify double-tap fires in Safari, Terminal, and a native app (TextEdit). This is flagged manual-only.

### Sampling Rate

- **Per task commit:** `xcodebuild test -project /Users/nick/Projects/any-vim/AnyVim.xcodeproj -scheme AnyVim -destination 'platform=macOS'`
- **Per wave merge:** Same full suite
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `AnyVimTests/HotkeyManagerTests.swift` — covers all HOTKEY-01 and HOTKEY-02 unit tests above
- [ ] `MockHotkeyTapInstaller` (in test file or shared fixture) — protocol mock for CGEvent tap creation, so tests never require live TCC permissions

*(Existing test infrastructure: `PermissionManagerTests.swift`, `LoginItemManagerTests.swift`, `MenuBarControllerTests.swift` — all passing. `MockPermissionChecker` already implements `PermissionChecking` and is reusable for HotkeyManager tests.)*

---

## Project Constraints (from CLAUDE.md)

The following directives are enforced by CLAUDE.md and the planner must verify compliance:

| Directive | Constraint |
|-----------|------------|
| Language | Swift only — no Go, Objective-C |
| Swift version | Swift 6 language mode, `SWIFT_STRICT_CONCURRENCY=complete` |
| CGEventTap mode | `.defaultTap` (not `.listenOnly`) — required per CLAUDE.md |
| Tap health check | MANDATORY — `CGEvent.tapIsEnabled()` periodic check + reinstall on failure |
| Double-tap trigger | `CGEvent.tapCreate(tap:.cgSessionEventTap, place:.headInsertEventTap, ...)` — exact signature specified in CLAUDE.md |
| Event type | `flagsChanged` for modifier-only detection (confirmed by CONTEXT.md D-01) |
| Accessibility wrapper | Raw `AXUIElement` — no AXSwift (unmaintained) |
| No external dependencies | This phase adds no third-party packages |

---

## Sources

### Primary (HIGH confidence)

- CLAUDE.md §Recommended Stack > Global Keyboard Monitoring — full CGEventTap specification with exact API call, `.defaultTap` requirement, double-tap timing, and code-signing health check requirement
- Apple CoreGraphics docs — `CGEvent.tapCreate`, `CGEvent.tapIsEnabled`, `CGEvent.tapEnable`, `CGEventType.flagsChanged`
- Carbon HIToolbox — `kVK_Control` (0x3B / 59), `kVK_RightControl` (0x3E / 62) keycode constants

### Secondary (MEDIUM confidence)

- [Daniel Raffel — CGEvent Taps and Code Signing: The Silent Disable Race](https://danielraffel.me/til/2026/02/19/cgevent-taps-and-code-signing-the-silent-disable-race/) — verified account of non-nil tap / silent failure behavior; re-enable and reinstall recovery pattern
- [alt-tab-macos KeyboardEvents.swift](https://github.com/lwouis/alt-tab-macos/blob/master/src/logic/events/KeyboardEvents.swift) — production CGEventTap flagsChanged implementation; listen-only mode (different from our .defaultTap, but pattern applies)
- [Capture Key Bindings in Swift — Medium](https://gaitatzis.medium.com/capture-key-bindings-in-swift-3050b0ccbf42) — CFMachPortCreateRunLoopSource + CFRunLoopAddSource setup pattern

### Tertiary (LOW confidence)

- Community reports of 350ms as double-tap threshold — consistent with CONTEXT.md D-03 but not verified against an Apple spec. Empirical validation during implementation recommended.

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all APIs are in the macOS SDK, no third-party choices needed
- Architecture patterns: HIGH — CGEventTap + CFRunLoop + DispatchQueue.main bounce is the established pattern, verified across multiple production projects
- Double-tap state machine: HIGH — logic is straightforward; timing constants are LOW (community-reported 350ms, not from Apple spec)
- Tap health monitoring: HIGH — recovery pattern verified by official docs and the code-signing pitfall article
- Swift 6 concurrency approach: HIGH — DispatchQueue.main.async from C callback is the canonical Swift 6 solution

**Research date:** 2026-03-31
**Valid until:** 2026-06-30 (stable SDK APIs; no fast-moving dependencies in this phase)
