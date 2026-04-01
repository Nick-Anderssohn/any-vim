# Phase 2: Global Hotkey Detection - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-31
**Phase:** 02-global-hotkey-detection
**Areas discussed:** Double-tap detection logic, Event tap lifecycle, Tap health monitoring, Trigger callback

---

## Double-Tap Detection Logic

### Which key event should count as a Control tap?

| Option | Description | Selected |
|--------|-------------|----------|
| flagsChanged only | Track CGEventType.flagsChanged — fires when modifier keys are pressed/released. A "tap" = flagsChanged with Control flag set, then cleared, with no other keys in between | :white_check_mark: |
| keyDown for kVK_Control | Track raw keyDown events for the Control virtual key code. Simpler but may miss edge cases | |
| Both flagsChanged and keyDown | Belt-and-suspenders approach — watch both event types. More complex, potentially redundant | |

**User's choice:** flagsChanged only (Recommended)
**Notes:** None

### Should left Control and right Control both trigger?

| Option | Description | Selected |
|--------|-------------|----------|
| Either Control key | Both left and right Control count toward double-tap. Most natural | :white_check_mark: |
| Left Control only | Only the left Control key triggers. Prevents accidental right-hand triggers | |

**User's choice:** Either Control key (Recommended)
**Notes:** None

### What should the double-tap timing threshold be?

| Option | Description | Selected |
|--------|-------------|----------|
| ~350ms | Per HOTKEY-02 requirement. Standard double-click speed range | :white_check_mark: |
| ~300ms (tighter) | Slightly faster — reduces false positives but may frustrate slower tappers | |
| ~400ms (more forgiving) | More generous window — easier to trigger but higher false positive chance | |

**User's choice:** ~350ms (Recommended)
**Notes:** None

### How should Ctrl+other-key combos be handled?

| Option | Description | Selected |
|--------|-------------|----------|
| Any intervening key cancels | ANY other key pressed between two Control taps resets the double-tap state | :white_check_mark: |
| Only non-modifier keys cancel | Shift, Option, Command between taps don't cancel — only letter/number/symbol keys do | |

**User's choice:** Any intervening key cancels (Recommended)
**Notes:** None

---

## Event Tap Lifecycle

### Where should the CGEventTap code live?

| Option | Description | Selected |
|--------|-------------|----------|
| Dedicated HotkeyManager class | Own class encapsulating event tap, state machine, and health monitoring. AppDelegate creates and retains it | :white_check_mark: |
| Inside PermissionManager | Extend PermissionManager to also own the event tap. Fewer classes but mixed responsibilities | |
| Directly in AppDelegate | Simplest approach but gets crowded as complexity grows | |

**User's choice:** Dedicated HotkeyManager class (Recommended)
**Notes:** None

### When should the event tap be installed?

| Option | Description | Selected |
|--------|-------------|----------|
| On launch if permissions granted | Install in applicationDidFinishLaunching if both permissions granted. Otherwise install when PermissionManager detects grant | :white_check_mark: |
| Always on launch, fail silently | Attempt immediately, CGEvent.tapCreate returns nil if no permissions. Retry via health check | |

**User's choice:** On launch if permissions granted (Recommended)
**Notes:** None

### Should the tap be passive or active?

| Option | Description | Selected |
|--------|-------------|----------|
| Active tap / .defaultTap | Per CLAUDE.md guidance. Can observe AND optionally consume events. Requires Accessibility permission | :white_check_mark: |
| Passive tap / .listenOnly | Listen-only. Lower permission requirements but can't consume events later | |

**User's choice:** Active tap / .defaultTap (Recommended)
**Notes:** None

---

## Tap Health Monitoring

### How should health checks work?

| Option | Description | Selected |
|--------|-------------|----------|
| Periodic CGEvent.tapIsEnabled() check | HotkeyManager runs its own timer. If tap disabled, try tapEnable(), then reinstall from scratch | :white_check_mark: |
| Reuse PermissionManager's timer | Piggyback on existing 3-second poll. Fewer timers but couples the systems | |

**User's choice:** Periodic CGEvent.tapIsEnabled() check (Recommended)
**Notes:** None

### What should happen if the tap can't be reinstalled?

| Option | Description | Selected |
|--------|-------------|----------|
| Update menu bar status | Show warning in menu bar dropdown. Keep retrying on health check interval | :white_check_mark: |
| Show an alert dialog | Pop up modal alert. More intrusive but more visible | |
| Silent retry only | Keep retrying with no user indication. Simplest but user won't know hotkey stopped | |

**User's choice:** Update menu bar status (Recommended)
**Notes:** None

---

## Trigger Callback

### How should HotkeyManager notify the app?

| Option | Description | Selected |
|--------|-------------|----------|
| Closure callback | HotkeyManager takes an onTrigger closure, like PermissionManager's onChange. Type-safe and testable | :white_check_mark: |
| Delegate protocol | HotkeyManagerDelegate with didDetectDoubleTap(). More formal but heavier for single callback | |
| NotificationCenter post | Post a Notification. Most decoupled but hardest to test and type-unsafe | |

**User's choice:** Closure callback (Recommended)
**Notes:** None

---

## Claude's Discretion

- Health check timer interval
- Internal state machine implementation details
- Debug logging for tap health events
- How HotkeyManager learns about permission grants
- Test strategy for CGEvent APIs

## Deferred Ideas

None — discussion stayed within phase scope
