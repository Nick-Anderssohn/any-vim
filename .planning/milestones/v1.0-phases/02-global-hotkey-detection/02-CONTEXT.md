# Phase 2: Global Hotkey Detection - Context

**Gathered:** 2026-03-31
**Status:** Ready for planning

<domain>
## Phase Boundary

Reliable system-wide double-tap Control key detection via CGEventTap, with health monitoring to survive silent tap disabling from code-signing identity changes. This phase adds HotkeyManager to the existing app shell — it does NOT implement any text capture, vim launching, or edit cycle logic.

</domain>

<decisions>
## Implementation Decisions

### Double-Tap Detection Logic
- **D-01:** Track `CGEventType.flagsChanged` events only — this is the natural event type for modifier-only keys. A "tap" is defined as flagsChanged with Control flag set, then flagsChanged with Control flag cleared, with no other keys pressed in between.
- **D-02:** Both left and right Control keys count toward double-tap detection. Users don't think about which Control key they're pressing.
- **D-03:** Double-tap timing threshold is ~350ms (per HOTKEY-02). Two Control tap-release cycles within this window trigger the app.
- **D-04:** Any intervening key press (modifier or otherwise) between the two Control taps resets the double-tap state machine. This prevents Ctrl+C followed by a quick Control tap from false-triggering.

### Event Tap Lifecycle
- **D-05:** CGEventTap code lives in a dedicated `HotkeyManager` class. AppDelegate creates and retains it as an instance property, following the same pattern as PermissionManager and LoginItemManager.
- **D-06:** The event tap is installed on launch if both Accessibility and Input Monitoring permissions are already granted. If not, HotkeyManager installs the tap when notified that permissions have been granted (via PermissionManager's onChange callback).
- **D-07:** Use `.defaultTap` (active tap) per CLAUDE.md guidance. This requires Accessibility permission and allows optionally consuming events in the future.

### Tap Health Monitoring
- **D-08:** HotkeyManager runs its own periodic timer to call `CGEvent.tapIsEnabled()`. If the tap is found disabled, attempt `CGEvent.tapEnable()` first. If that fails, reinstall the tap from scratch.
- **D-09:** If the tap cannot be reinstalled, show a warning state in the menu bar dropdown (similar to permission status items). Keep retrying on the health check interval. No modal alert — just persistent menu bar indication.

### Trigger Callback
- **D-10:** HotkeyManager takes an `onTrigger` closure, consistent with PermissionManager's `onChange` closure pattern. AppDelegate provides the closure when creating HotkeyManager. Simple, type-safe, and testable.

### Claude's Discretion
- Health check timer interval (should be reasonable — every few seconds, similar to permission poll)
- Internal state machine implementation details for double-tap detection
- Whether to log tap health events for debugging
- How HotkeyManager learns about permission grants (direct PermissionManager integration vs AppDelegate mediation)
- Test strategy for the event tap (protocol-based mocking of CGEvent APIs)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Technology Stack
- `CLAUDE.md` §Recommended Stack > Global Keyboard Monitoring — CGEventTap usage, `.defaultTap` mode, `kVK_Control` detection, double-tap timing guidance
- `CLAUDE.md` §Recommended Stack > Global Keyboard Monitoring > Critical — CGEvent tap code-signing pitfall: non-nil tap is not a healthy tap, periodic `CGEvent.tapIsEnabled()` health check required

### Requirements
- `.planning/REQUIREMENTS.md` §Hotkey (HOTKEY-01, HOTKEY-02, HOTKEY-03) — System-wide detection, timing threshold, works regardless of focused app

### Prior Phase Context
- `.planning/phases/01-app-shell-and-permissions/01-CONTEXT.md` — App shell patterns (AppDelegate ownership, PermissionManager poll timer, manager retention)

### Existing Code
- `Sources/AnyVim/AppDelegate.swift` — Entry point, manager ownership pattern, permission monitoring integration
- `Sources/AnyVim/PermissionManager.swift` — Permission checking API (`isAccessibilityGranted`, `isInputMonitoringGranted`), poll timer pattern, `onChange` closure pattern

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `PermissionManager` — Already checks both permissions needed for CGEventTap. HotkeyManager can query it or receive permission state from AppDelegate.
- `MenuBarController.buildMenu()` — Can be extended to show tap health status (D-09). Currently shows permission status items.
- Poll timer pattern from `PermissionManager.startMonitoring()` — Established pattern for periodic health checks.

### Established Patterns
- Manager classes owned by AppDelegate as instance properties (prevents ARC release)
- Closure-based callbacks for state changes (`onChange` in PermissionManager)
- Protocol-based testability (`PermissionChecking` protocol)
- Sequential initialization in `applicationDidFinishLaunching`

### Integration Points
- AppDelegate creates HotkeyManager after PermissionManager, wires them together
- MenuBarController.buildMenu() needs to show tap health status when tap fails
- PermissionManager's onChange triggers HotkeyManager tap installation when permissions are newly granted

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches for CGEventTap-based hotkey detection.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 02-global-hotkey-detection*
*Context gathered: 2026-03-31*
