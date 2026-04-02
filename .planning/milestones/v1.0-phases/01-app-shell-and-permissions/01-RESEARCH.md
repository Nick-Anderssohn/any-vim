# Phase 01: App Shell and Permissions - Research

**Researched:** 2026-03-31
**Domain:** macOS AppKit menu bar daemon, TCC permissions (Accessibility + Input Monitoring), launch-at-login (SMAppService)
**Confidence:** HIGH (core APIs well-documented; one nuance on live permission detection flagged below)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Show a modal alert dialog on first launch explaining what permissions are needed and why. Include a button to open System Settings directly.
- **D-02:** Handle permissions sequentially — one alert per permission. After the user grants the first (e.g., Accessibility), detect it, then show the alert for the second (Input Monitoring).
- **D-03:** After the initial alert, show permission status as menu items in the dropdown (e.g., "Accessibility: Not Granted"). Clicking a status item opens the relevant System Settings pane.
- **D-04:** When a permission is granted (detected via re-polling), show a brief macOS notification confirming it (e.g., "Accessibility permission granted").
- **D-05:** Use an SF Symbol for the menu bar icon.
- **D-06:** Dropdown menu contents for Phase 1: permission status items + "Launch at Login" toggle + Quit. Minimal — no About, no config until later phases.
- **D-07:** Launch at login is enabled by default on first run.
- **D-08:** The first-run permission alert mentions that AnyVim will launch at login and that this can be changed in the menu bar.
- **D-09:** A "Launch at Login" toggle in the dropdown menu lets the user enable/disable it at any time.

### Claude's Discretion

- Specific SF Symbol choice for the menu bar icon
- Re-poll interval for permission detection (a few seconds, per success criteria)
- Alert dialog copy and layout details
- Whether to use SMAppService (modern) or legacy LaunchAgent for login items

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| MENU-01 | App runs as a menu bar app with a status icon (no dock icon) | NSStatusItem + LSUIElement=YES + setActivationPolicy(.accessory) |
| MENU-03 | Menu includes a Quit option | NSMenuItem targeting NSApp.terminate(_:) |
| MENU-04 | App launches at login (optional, configurable) | SMAppService.mainApp.register()/unregister() — macOS 13+ |
| PERM-01 | App checks for Accessibility permission on launch and displays guidance if not granted | AXIsProcessTrusted() + NSAlert + URL open to System Settings |
| PERM-02 | App checks for Input Monitoring permission on launch and displays guidance if not granted | CGPreflightListenEventAccess() + NSAlert + URL open to System Settings |
| PERM-03 | App re-checks permission state periodically and updates status accordingly | Timer + DistributedNotificationCenter ("com.apple.accessibility.api") + polling pattern |
</phase_requirements>

---

## Summary

Phase 1 creates the entire foundation: a signed macOS app bundle that lives in the menu bar, requests and tracks Accessibility and Input Monitoring permissions, and registers with the OS for login launch. All APIs involved are stable AppKit/ApplicationServices/CoreGraphics/ServiceManagement — no third-party dependencies are needed for this phase.

The single non-trivial subtlety is permission live-detection. `AXIsProcessTrusted()` and `CGPreflightListenEventAccess()` are documented NOT to return live values after a grant in the same process instance — the system normally offers a restart. To meet the "within a few seconds, no restart required" success criterion, the recommended approach is to combine a `DistributedNotificationCenter` observer on the `"com.apple.accessibility.api"` notification with a periodic `Timer` fallback poll. When either fires, re-query both functions and update the menu state. This avoids a forced restart while remaining reliable.

The project is greenfield (no existing source) on Xcode 26.4 / Swift 6.3. The Xcode project must be properly code-signed from day one — TCC permission grants are bound to code identity, so re-signing after permissions are granted silently clears them. Use a development certificate or Developer ID from the first build.

**Primary recommendation:** Build a conventional Xcode macOS App target (not SPM executable), configure `LSUIElement=YES` in Info.plist, hold `NSStatusItem` as a retained `AppDelegate` property, use `SMAppService.mainApp` for launch-at-login, and combine `DistributedNotificationCenter` + `Timer` polling for permission re-detection.

---

## Standard Stack

### Core

| Library / API | Version | Purpose | Why Standard |
|---------------|---------|---------|--------------|
| AppKit — NSStatusBar / NSStatusItem | macOS 13+ SDK | Menu bar icon and dropdown menu | The only non-SwiftUI, native, stable way to create a status item. Raw NSStatusItem is ~10 lines, no timing quirks unlike SwiftUI MenuBarExtra. |
| ApplicationServices — AXIsProcessTrusted | macOS 13+ SDK | Check Accessibility permission | Official Apple API; no third-party wrapper needed. |
| CoreGraphics — CGPreflightListenEventAccess | macOS 13+ SDK | Check Input Monitoring permission | Official Apple API; also used before installing CGEventTap in Phase 2. |
| Foundation — DistributedNotificationCenter | macOS 13+ SDK | Receive system notification when TCC changes | Provides `"com.apple.accessibility.api"` notification for Accessibility changes. |
| Foundation — Timer | macOS 13+ SDK | Periodic permission re-poll fallback | Guarantees detection if DistributedNotification fires before process is running or is missed. |
| ServiceManagement — SMAppService | macOS 13+ SDK | Launch at login | Replaces deprecated `SMLoginItemSetEnabled`. `SMAppService.mainApp` requires no helper bundle. |
| UserNotifications — UNUserNotificationCenter | macOS 10.14+ SDK | Permission-granted confirmation notification (D-04) | Modern local notification API; must request authorization at startup. |

### Supporting

| Library / API | Version | Purpose | When to Use |
|---------------|---------|---------|-------------|
| NSWorkspace.shared.open(url:) | macOS 13+ SDK | Open System Settings to specific pane | Used in alert buttons and tapping status menu items (D-01, D-03). |
| NSAlert | macOS 13+ SDK | Modal onboarding dialog | D-01 first-run alert, D-02 sequential permission flow. |
| UserDefaults | macOS 13+ SDK | Track first-run state | Persist whether the first-run alert has already been shown. |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| SMAppService.mainApp | LaunchAgent plist + SMJobBless | LaunchAgent requires installing a helper plist in ~/Library/LaunchAgents — more work, deprecated workflow. SMAppService is the Apple-blessed macOS 13+ API. |
| Raw NSStatusItem | SwiftUI MenuBarExtra | MenuBarExtra has documented dismiss timing bugs and less layout control. CLAUDE.md explicitly forbids it for this project. |
| AXIsProcessTrusted() | Attempt to use AX API and catch failure | Trying a benign AX call (e.g., AXUIElementCreateSystemWide()) to test trust is brittle. Stick with the declared API. |
| UNUserNotificationCenter | NSUserNotification | NSUserNotification is deprecated since macOS 11. UNUserNotificationCenter is the current standard. |

**Installation:** No additional packages for Phase 1. All APIs are in macOS SDKs. Add `ServiceManagement` and `UserNotifications` frameworks to the Xcode target's "Frameworks, Libraries, and Embedded Content" if not already linked.

---

## Architecture Patterns

### Recommended Project Structure

```
AnyVim.xcodeproj
Sources/AnyVim/
├── AppDelegate.swift         # NSApplicationDelegate, owns NSStatusItem, sets up all subsystems
├── PermissionManager.swift   # AXIsProcessTrusted, CGPreflightListenEventAccess, polling logic
├── MenuBarController.swift   # Builds and updates NSMenu — permission status items, toggle, Quit
├── LoginItemManager.swift    # SMAppService.mainApp register/unregister/status
├── NotificationManager.swift # UNUserNotificationCenter authorization + local notification posting
└── Assets.xcassets/         # App icon (required for code signing), menu bar icon template
AnyVim/
├── Info.plist               # LSUIElement=YES, NSAccessibilityUsageDescription, NSInputMonitoringUsageDescription
└── AnyVim.entitlements      # Hardened runtime entitlements (see Entitlements section)
```

### Pattern 1: Menu Bar Daemon Without Dock Icon

**What:** Configure the app to show only in the menu bar, never in the Dock or Force Quit window.
**When to use:** All daemon-style macOS apps (any phase).

```swift
// Source: https://www.polpiella.dev/a-menu-bar-only-macos-app-using-appkit/
// AppDelegate.swift
import AppKit

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!   // Must be retained — local scope = released

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // No Dock icon, no Force Quit entry
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "character.cursor.ibeam",
                                   accessibilityDescription: "AnyVim")
            button.image?.isTemplate = true  // Adapts to dark/light menu bar automatically
        }
        // Build menu, start permission checks, etc.
    }
}
```

**Info.plist key (required):**
```xml
<key>LSUIElement</key>
<true/>
```

`setActivationPolicy(.accessory)` alone does not fully suppress the Dock icon during launch; `LSUIElement=YES` is needed.

### Pattern 2: Permission Check and Re-Poll

**What:** Check Accessibility and Input Monitoring at launch, then re-detect changes without requiring restart.
**When to use:** Any phase that installs or uses either permission.

```swift
// Source: Apple docs — AXIsProcessTrusted, CGPreflightListenEventAccess;
//         DistributedNotificationCenter approach from community cross-verification.
// PermissionManager.swift
import ApplicationServices
import CoreGraphics
import Foundation

final class PermissionManager {
    private var pollTimer: Timer?

    var isAccessibilityGranted: Bool { AXIsProcessTrusted() }
    var isInputMonitoringGranted: Bool { CGPreflightListenEventAccess() }

    func startMonitoring(onChange: @escaping () -> Void) {
        // 1. DistributedNotificationCenter fires when TCC accessibility table changes
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { _ in onChange() }

        // 2. Timer fallback (Input Monitoring has no equivalent DistributedNotification)
        //    3-second interval satisfies "within a few seconds" success criterion
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            onChange()
        }
    }

    func stopMonitoring() {
        DistributedNotificationCenter.default().removeObserver(self)
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func requestAccessibility() {
        // Opens System Settings prompt — do NOT use kAXTrustedCheckOptionPrompt during
        // onboarding because macOS 13+ shows the pane in the background; NSAlert + URL
        // is more reliable for first-run guidance (D-01).
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    func requestInputMonitoring() {
        CGRequestListenEventAccess()    // Triggers system prompt; fallback:
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }
}
```

**Critical note on live detection:** `AXIsProcessTrusted()` and `CGPreflightListenEventAccess()` are cached by the OS per process instance. On macOS 13+, the system normally prompts the user to restart after granting Accessibility. To meet PERM-03 without a restart:
- The `"com.apple.accessibility.api"` DistributedNotification fires when TCC changes (Accessibility only).
- The 3-second Timer poll catches Input Monitoring changes (no equivalent notification).
- In practice, the functions DO return `true` on a fresh call after the grant in the same process when triggered by these notifications — the "restart required" experience only happens when the system presents its own restart dialog, which you can suppress by not calling `AXIsProcessTrustedWithOptions` with the prompt option during polling.

### Pattern 3: Launch at Login with SMAppService

**What:** Register the app as a login item using the macOS 13+ API. No helper bundle needed.
**When to use:** MENU-04 + D-07 (enabled by default on first run) + D-09 (toggle in menu).

```swift
// Source: https://nilcoalescing.com/blog/LaunchAtLoginSetting/
//         Apple Developer Documentation — SMAppService
import ServiceManagement

final class LoginItemManager {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func enable() {
        do {
            try SMAppService.mainApp.register()
        } catch {
            // Log error — may fail if already registered
        }
    }

    func disable() {
        do {
            try SMAppService.mainApp.unregister()
        } catch { }
    }

    /// D-07: Enable by default on first run only.
    func enableIfFirstRun() {
        let key = "launchAtLoginConfigured"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        enable()
    }
}
```

**Note on D-07 and Apple guidelines:** Apple App Review Guidelines say apps should not auto-launch without user consent. AnyVim is not App Store distributed (Accessibility + Input Monitoring are incompatible with the sandbox), so auto-enabling is acceptable. However, the first-run alert (D-08) must tell the user, making it informed consent.

**Reading status from system, not UserDefaults:** Users can remove login items via System Settings > General > Login Items. Always read `SMAppService.mainApp.status` to populate the menu toggle state — do not rely on a local UserDefaults flag.

### Pattern 4: Sequential Permission Alert Flow (D-01, D-02)

**What:** Show a modal NSAlert for each missing permission in order, with a button to open System Settings.
**When to use:** First-run onboarding and when permissions are found missing.

```swift
// Source: Apple Developer Documentation — NSAlert
import AppKit

func showPermissionAlert(title: String, message: String, openSettingsURL: URL) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Open System Settings")
    alert.addButton(withTitle: "Later")
    let response = alert.runModal()
    if response == .alertFirstButtonReturn {
        NSWorkspace.shared.open(openSettingsURL)
    }
}
```

Sequential flow in `PermissionManager`: check Accessibility first. If missing, show alert. Start polling. When Accessibility is detected as granted, check Input Monitoring. If missing, show its alert.

### Anti-Patterns to Avoid

- **Storing NSStatusItem in a local variable:** It will be released and vanish from the menu bar. Always hold it as a strong property on AppDelegate or a long-lived controller.
- **Using `kAXTrustedCheckOptionPrompt: true` for polling:** This triggers the TCC system dialog on every poll interval. Only use the option once during first-run prompting; use plain `AXIsProcessTrusted()` for polling.
- **Using SwiftUI MenuBarExtra:** CLAUDE.md explicitly excludes this due to dismiss timing bugs. Use raw NSStatusItem.
- **Building the Xcode project with "Sign to Run Locally":** TCC will not present permission dialogs for locally-signed apps. Always use a development team certificate from day one.
- **Enabling .mainApp SMAppService via `try? SMAppService.mainApp.register()` in `applicationWillFinishLaunching`:** Register in `applicationDidFinishLaunching` only, after UI is set up, to avoid ordering issues with the system login item service.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Launch at login | Custom LaunchAgent plist write | `SMAppService.mainApp` | SMAppService handles plist, user consent notification, and status tracking. Custom plist requires writing to ~/Library/LaunchAgents, handling permission errors, and is the deprecated path. |
| Permission status in menu | Custom bitfield / UserDefaults cache | Query `AXIsProcessTrusted()` and `CGPreflightListenEventAccess()` live on each menu open | The system is the source of truth. Caching permission state locally leads to stale display after the user revokes in System Settings. |
| Restart-on-grant UX | Force `NSApp.terminate` + `Process.launchedProcess` relaunch | DistributedNotificationCenter + Timer poll | Forced relaunch is disruptive and unnecessary. The poll approach satisfies PERM-03 without ejecting the user. |
| Notification display | Custom overlay window | `UNUserNotificationCenter` | macOS system notifications handle focus, DND, notification history, and accessibility automatically. |

---

## Common Pitfalls

### Pitfall 1: Code Signing Identity and TCC Grants

**What goes wrong:** Developer re-signs the binary during development (e.g., after modifying build settings, changing provisioning profile, or switching Xcode versions). The TCC database treats the new signature as a new app identity and revokes previously granted permissions silently. The app launches, `AXIsProcessTrusted()` returns `false` despite having been granted, and no alert appears because the "first run" flag was already set.

**Why it happens:** TCC permission grants are keyed to the code signing identity (team ID + bundle ID + signing certificate hash). Any change to those produces a new identity.

**How to avoid:** Establish the signing identity before any TCC permission testing. Use a consistent development certificate from day one. Document the certificate to use in CLAUDE.md Conventions. Source: https://danielraffel.me/til/2026/02/19/cgevent-taps-and-code-signing-the-silent-disable-race/

**Warning signs:** `AXIsProcessTrusted()` returns `false` even though the app appears in System Settings Privacy & Security with a checkmark; removing and re-adding it in System Settings fixes it.

### Pitfall 2: NSStatusItem Released Prematurely

**What goes wrong:** `statusItem` is assigned in a method body (e.g., `applicationDidFinishLaunching`) as a local variable. It is released at the end of the method, and the menu bar icon disappears seconds after launch.

**Why it happens:** `NSStatusBar.system.statusItem(withLength:)` returns an unowned-like reference; the caller is responsible for retaining it.

**How to avoid:** Declare `private var statusItem: NSStatusItem!` as an instance property of AppDelegate (or a long-lived MenuBarController). Never assign it to a local `let`.

### Pitfall 3: AXIsProcessTrustedWithOptions Looping

**What goes wrong:** Code calls `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])` in a polling timer. This causes repeated TCC system prompts or "wants to control this computer" dialogs every 3 seconds.

**Why it happens:** The `kAXTrustedCheckOptionPrompt` option is a one-shot request trigger, not a status query. It is not idempotent.

**How to avoid:** Call `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])` at most once (during first-run prompt, if at all — the NSAlert + URL approach from D-01 is preferred). Use plain `AXIsProcessTrusted()` (no options) in the polling timer.

### Pitfall 4: SMAppService Status Stale After System Settings Change

**What goes wrong:** User removes AnyVim from System Settings > Login Items manually. The "Launch at Login" menu item still shows a checkmark because the code reads from UserDefaults.

**Why it happens:** `SMAppService.mainApp.status` reflects the live OS state, but developers sometimes cache it locally.

**How to avoid:** Always read `SMAppService.mainApp.status == .enabled` when populating the menu. This is synchronous and fast.

### Pitfall 5: Missing Info.plist Usage Description Strings

**What goes wrong:** The app is rejected at the TCC prompt stage, or permission dialogs show a blank message because `NSAccessibilityUsageDescription` and `NSAppleEventsUsageDescription` are missing from Info.plist.

**Why it happens:** macOS TCC requires human-readable usage descriptions for permissions that involve privacy-sensitive APIs.

**How to avoid:** Add both keys to Info.plist before first run:
- `NSAccessibilityUsageDescription` — Accessibility
- `NSInputMonitoringUsageDescription` — Input Monitoring (key name may vary; verify in current Apple docs)

### Pitfall 6: UNUserNotificationCenter Authorization Not Requested

**What goes wrong:** Calling `UNUserNotificationCenter.current().add(request)` silently does nothing because the app never requested notification authorization.

**Why it happens:** Unlike iOS, macOS apps don't automatically prompt for notification permission; `requestAuthorization(options:completionHandler:)` must be called explicitly.

**How to avoid:** Call `requestAuthorization` in `applicationDidFinishLaunching`. If the user denies, fall back to an NSAlert-based confirmation instead of a system notification for D-04.

---

## Code Examples

### Full Menu Build with Permission Status Items and Quit

```swift
// Source: AppKit NSMenu / NSStatusItem documentation
// MenuBarController.swift
import AppKit
import ApplicationServices
import CoreGraphics

final class MenuBarController {
    private let permissionManager: PermissionManager
    private let loginItemManager: LoginItemManager

    init(permissionManager: PermissionManager, loginItemManager: LoginItemManager) {
        self.permissionManager = permissionManager
        self.loginItemManager = loginItemManager
    }

    func buildMenu() -> NSMenu {
        let menu = NSMenu()

        // Permission status items (D-03)
        let axStatus = permissionManager.isAccessibilityGranted ? "Granted" : "Not Granted — Click to Enable"
        let axItem = NSMenuItem(title: "Accessibility: \(axStatus)", action: nil, keyEquivalent: "")
        if !permissionManager.isAccessibilityGranted {
            axItem.action = #selector(openAccessibilitySettings)
            axItem.target = self
        }
        menu.addItem(axItem)

        let imStatus = permissionManager.isInputMonitoringGranted ? "Granted" : "Not Granted — Click to Enable"
        let imItem = NSMenuItem(title: "Input Monitoring: \(imStatus)", action: nil, keyEquivalent: "")
        if !permissionManager.isInputMonitoringGranted {
            imItem.action = #selector(openInputMonitoringSettings)
            imItem.target = self
        }
        menu.addItem(imItem)

        menu.addItem(NSMenuItem.separator())

        // Launch at login toggle (D-09)
        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = loginItemManager.isEnabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(NSMenuItem.separator())

        // Quit (MENU-03)
        let quitItem = NSMenuItem(title: "Quit AnyVim", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        return menu
    }

    @objc private func openAccessibilitySettings() {
        permissionManager.requestAccessibility()
    }

    @objc private func openInputMonitoringSettings() {
        permissionManager.requestInputMonitoring()
    }

    @objc private func toggleLaunchAtLogin() {
        if loginItemManager.isEnabled {
            loginItemManager.disable()
        } else {
            loginItemManager.enable()
        }
        // Rebuild menu to update checkmark
    }
}
```

### System Settings URL Schemes (Verified)

```swift
// Source: https://gannonlawlor.com/posts/macos_privacy_permissions/ (verified working macOS 13-15)
let accessibilityURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
let inputMonitoringURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
NSWorkspace.shared.open(accessibilityURL)
```

**Note:** These URL schemes are not officially documented and may change across major macOS versions. They are stable through macOS 15 (Sequoia) based on community verification. Test on each major OS version.

### UNUserNotificationCenter Permission Granted Banner (D-04)

```swift
// Source: Apple Developer Documentation — UNUserNotificationCenter
import UserNotifications

final class NotificationManager {
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            // Store granted state if needed for fallback
        }
    }

    func notifyPermissionGranted(_ permissionName: String) {
        let content = UNMutableNotificationContent()
        content.title = "AnyVim"
        content.body = "\(permissionName) permission granted."
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil  // deliver immediately
        )
        UNUserNotificationCenter.current().add(request)
    }
}
```

---

## Entitlements and Info.plist Keys

**Required Info.plist entries:**

```xml
<!-- Suppress Dock icon and Force Quit entry -->
<key>LSUIElement</key>
<true/>

<!-- TCC usage descriptions — required or permission dialog shows blank -->
<key>NSAccessibilityUsageDescription</key>
<string>AnyVim needs Accessibility access to detect the focused text field and simulate keyboard shortcuts to capture and restore text.</string>

<key>NSInputMonitoringUsageDescription</key>
<string>AnyVim needs Input Monitoring access to detect the double-tap Control key trigger globally.</string>
```

**Required entitlements (.entitlements file):**

For a non-sandboxed app with hardened runtime (required for Developer ID distribution and proper TCC behavior):

```xml
<key>com.apple.security.cs.allow-jit</key>
<false/>
<!-- Hardened runtime must be ON for TCC to work correctly with Developer ID signing -->
```

AnyVim does NOT use the App Sandbox (incompatible with Accessibility + Input Monitoring as noted in REQUIREMENTS.md Out of Scope). No sandbox entitlement needed.

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| SMLoginItemSetEnabled (deprecated) | SMAppService.mainApp.register() | macOS 13 (2022) | No helper bundle needed; status queryable live |
| NSUserNotification (deprecated) | UNUserNotificationCenter | macOS 11 (2020) | Standard notification lifecycle, DND support |
| SwiftUI MenuBarExtra for menu bar daemons | AppKit NSStatusItem (still best for daemons) | MenuBarExtra introduced macOS 13; known quirks documented | NSStatusItem remains preferred for apps without a primary window |
| LaunchAgent plist in ~/Library/LaunchAgents | SMAppService.mainApp | macOS 13 | Simpler, no plist file needed |

**Deprecated/outdated:**
- `SMLoginItemSetEnabled`: Deprecated in macOS 13, removed behavior in macOS 15. Use `SMAppService`.
- `NSUserNotification`: Removed in macOS 12. Never use.
- `kAXTrustedCheckOptionPrompt` in polling loops: Causes repeated system dialogs. Use plain `AXIsProcessTrusted()` for polls.

---

## Open Questions

1. **Does AXIsProcessTrusted() return true live (without restart) on macOS 26.x (Xcode 26.4)?**
   - What we know: On macOS 13-15, it does NOT update live from the same process — the system normally prompts to restart. However, in practice the DistributedNotificationCenter approach appears to work (app gets the notification, re-queries, and gets the updated value) because the notification fires after the TCC database write is flushed.
   - What's unclear: Whether macOS 26 (the developer machine's OS) has changed this behavior.
   - Recommendation: Implement the combined DistributedNotification + 3s Timer approach. Add a `print` or log line in the timer callback during development to confirm the live value updates. If it does not, the fallback is to show a "Restart AnyVim to activate" menu item after grant — but try the polling approach first.

2. **Info.plist key for Input Monitoring usage description**
   - What we know: `NSInputMonitoringUsageDescription` is the commonly cited key.
   - What's unclear: Apple's official documentation on this exact key name for non-sandboxed apps is sparse.
   - Recommendation: Use `NSInputMonitoringUsageDescription` and validate it shows in the TCC prompt during first test run. If blank, check `Privacy - Input Monitoring Usage Description` as an alternative.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| Xcode | Build system, code signing | Yes | 26.4 (Build 17E192) | — |
| Swift | Primary language | Yes | 6.3.0 | — |
| Swift Package Manager | Dependencies | Yes | 6.3.0 | — |
| vim | Runtime (used in later phases) | Yes | 9.1 | — |
| macOS | Platform | Yes | 26.3.1 (Tahoe beta) | — |
| Developer certificate / Apple ID | TCC permission grants require proper signing | Unknown — not verified | — | Without it, permissions cannot be tested. Planner must include a Wave 0 step to verify signing identity. |

**Missing dependencies with no fallback:**
- Developer certificate: CGEventTap permissions (Phase 2) and TCC (Phase 1 testing) require a valid signing identity. The plan must include a task to configure Xcode signing before any permission testing.

**Missing dependencies with fallback:**
- None beyond signing.

**Note on macOS 26:** The development machine runs macOS Tahoe 26.3.1, which is newer than the minimum deployment target (macOS 13). All APIs used are available on macOS 13+ per CLAUDE.md. No API availability issues for this phase.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | XCTest (built into Xcode) |
| Config file | Configured within Xcode project (Unit Test target) |
| Quick run command | `xcodebuild test -scheme AnyVim -destination 'platform=macOS'` |
| Full suite command | Same (single target for this phase) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| MENU-01 | App runs without Dock icon | Manual smoke | Launch app, verify Dock | Manual only — Dock state not introspectable via XCTest |
| MENU-03 | Quit menu item terminates process | Manual smoke | Click Quit in menu bar | Manual only — NSStatusItem not accessible from unit tests |
| MENU-04 | Launch at login toggle registers/unregisters | Unit | `xcodebuild test ... -only-testing:AnyVimTests/LoginItemManagerTests` | No — Wave 0 |
| PERM-01 | Accessibility check returns correct value | Unit | `xcodebuild test ... -only-testing:AnyVimTests/PermissionManagerTests` | No — Wave 0 |
| PERM-02 | Input Monitoring check returns correct value | Unit | `xcodebuild test ... -only-testing:AnyVimTests/PermissionManagerTests` | No — Wave 0 |
| PERM-03 | Permission status updates within 3s poll | Integration | Manual — grant/revoke in System Settings while app runs | Manual only — TCC cannot be automated |

**Note:** PERM-01, PERM-02, and MENU-04 can have unit tests with protocol-abstracted permission checkers and mock SMAppService wrappers. PERM-03 and MENU-01/03 require manual smoke testing because they depend on OS-level UI and TCC state.

### Sampling Rate

- **Per task commit:** Build succeeds (`xcodebuild build -scheme AnyVim`)
- **Per wave merge:** Unit test suite green (`xcodebuild test -scheme AnyVim`)
- **Phase gate:** Full manual smoke checklist (Dock hidden, menu visible, permissions flow, Quit works, login toggle persists across relaunch)

### Wave 0 Gaps

- [ ] `AnyVimTests/PermissionManagerTests.swift` — covers PERM-01, PERM-02 with mock permission checker protocol
- [ ] `AnyVimTests/LoginItemManagerTests.swift` — covers MENU-04 with mock SMAppService wrapper
- [ ] Xcode Unit Test target added to project (`AnyVimTests`) — required before any test file can run
- [ ] Signing identity configured in project settings — required before any TCC permission testing

---

## Sources

### Primary (HIGH confidence)

- Apple Developer Documentation — NSStatusItem: https://developer.apple.com/documentation/appkit/nsstatusitem
- Apple Developer Documentation — NSStatusBar: https://developer.apple.com/documentation/appkit/nsstatusbar
- Apple Developer Documentation — AXIsProcessTrusted: https://developer.apple.com/documentation/applicationservices/1460720-axisprocesstrusted
- Apple Developer Documentation — CGPreflightListenEventAccess: https://developer.apple.com/documentation/coregraphics/cgpreflightlisteneventaccess()
- Apple Developer Documentation — CGRequestListenEventAccess: https://developer.apple.com/documentation/coregraphics/cgrequestlisteneventaccess()
- Apple Developer Documentation — SMAppService: https://developer.apple.com/documentation/servicemanagement/smappservice
- Apple Developer Documentation — UNUserNotificationCenter: https://developer.apple.com/documentation/usernotifications/unusernotificationcenter
- CGEvent tap code signing pitfall (per CLAUDE.md): https://danielraffel.me/til/2026/02/19/cgevent-taps-and-code-signing-the-silent-disable-race/

### Secondary (MEDIUM confidence)

- Polpiella.dev — Menu bar only macOS app with AppKit (NSStatusItem patterns, setActivationPolicy): https://www.polpiella.dev/a-menu-bar-only-macos-app-using-appkit/
- nilcoalescing.com — SMAppService launch at login with toggle (code examples): https://nilcoalescing.com/blog/LaunchAtLoginSetting/
- Gannon Lawlor — macOS privacy permissions (AXIsProcessTrusted, IOHIDCheckAccess, URL schemes): https://gannonlawlor.com/posts/macos_privacy_permissions/
- jano.dev — Accessibility permission on macOS (2025): https://jano.dev/apple/macos/swift/2025/01/08/Accessibility-Permission.html

### Tertiary (LOW confidence)

- Community pattern: DistributedNotificationCenter "com.apple.accessibility.api" for live permission detection — cited by multiple sources but not in official Apple documentation. Flagged for validation during implementation.
- System Settings URL schemes (x-apple.systempreferences:...) — not officially documented; stable through macOS 15 per community reports.

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all APIs are official Apple frameworks, no third-party dependencies
- Architecture: HIGH — established NSStatusItem + AppDelegate patterns verified across multiple sources
- Permission live-detection: MEDIUM — DistributedNotificationCenter approach is community-verified but not in official docs; Timer fallback makes it resilient
- SMAppService: HIGH — official Apple API with clear documentation
- System Settings URL schemes: LOW — not officially documented

**Research date:** 2026-03-31
**Valid until:** 2026-06-30 (stable APIs; URL schemes may change on a new macOS major version)
