import AppKit
import CoreGraphics

@main
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    // MARK: - Retained properties (all must be instance vars — local scope = released)

    private var statusItem: NSStatusItem!
    private var permissionManager: PermissionManager!
    private var loginItemManager: LoginItemManager!
    private var notificationManager: NotificationManager!
    private var hotkeyManager: HotkeyManager!
    private var menuBarController: MenuBarController!
    private var accessibilityBridge: AccessibilityBridge!

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Suppress Dock icon and Force Quit entry — menu bar daemon pattern
        NSApp.setActivationPolicy(.accessory)

        // Create and retain status item (NEVER local — will be released and vanish)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "character.cursor.ibeam",
                                   accessibilityDescription: "AnyVim")
            button.image?.isTemplate = true // Adapts to dark/light menu bar automatically
        }

        // Register with Input Monitoring early so the app appears in System Settings
        CGRequestListenEventAccess()

        // Create managers
        permissionManager = PermissionManager()
        loginItemManager = LoginItemManager()
        notificationManager = NotificationManager()

        // Request notification authorization early — must happen before posting (Pitfall 6)
        notificationManager.requestAuthorization()

        // Enable launch at login on first run (D-07)
        loginItemManager.enableIfFirstRun()

        // Create AccessibilityBridge (Phase 3: captures text on hotkey trigger)
        accessibilityBridge = AccessibilityBridge(permissionChecker: permissionManager)

        // Create and wire HotkeyManager (D-06: install immediately if permissions already granted)
        hotkeyManager = HotkeyManager()
        hotkeyManager.onTrigger = { [weak self] in self?.handleHotkeyTrigger() }
        hotkeyManager.onHealthChange = { [weak self] _ in self?.rebuildMenu() }

        // Build menu with live state (must happen before install() — the health change
        // callback fires synchronously during install and calls rebuildMenu())
        menuBarController = MenuBarController(
            permissionManager: permissionManager,
            loginItemManager: loginItemManager,
            hotkeyManager: hotkeyManager
        )
        statusItem.menu = menuBarController.buildMenu()

        // Install tap after menu is ready (health change may fire synchronously)
        hotkeyManager.install(permissionManager: permissionManager)

        // Sequential alert flow (D-01, D-02): show Accessibility alert first if missing
        if !permissionManager.isAccessibilityGranted {
            showAccessibilityAlert()
        }

        // Start permission monitoring — detects grants without requiring restart (PERM-03)
        permissionManager.startMonitoring { [weak self] accessibilityChanged, inputMonitoringChanged in
            self?.handlePermissionChange(
                accessibilityChanged: accessibilityChanged,
                inputMonitoringChanged: inputMonitoringChanged
            )
        }
    }

    // MARK: - Permission change handler

    private func handlePermissionChange(accessibilityChanged: Bool, inputMonitoringChanged: Bool) {
        if accessibilityChanged && permissionManager.isAccessibilityGranted {
            // Accessibility was just granted — notify the user (D-04)
            notificationManager.notifyPermissionGranted("Accessibility")

            // Sequential flow (D-02): now check Input Monitoring
            if !permissionManager.isInputMonitoringGranted {
                showInputMonitoringAlert()
            }
        }

        if inputMonitoringChanged && permissionManager.isInputMonitoringGranted {
            // Input Monitoring was just granted — notify the user (D-04)
            notificationManager.notifyPermissionGranted("Input Monitoring")
        }

        // Attempt tap installation if both permissions are now granted and tap is not yet healthy
        // (D-06: install when notified permissions granted)
        if !hotkeyManager.isTapHealthy {
            hotkeyManager.install(permissionManager: permissionManager)
        }

        // Rebuild menu with updated live state (including tap health)
        rebuildMenu()
    }

    // MARK: - Menu helper

    private func rebuildMenu() {
        statusItem.menu = menuBarController.buildMenu()
    }

    // MARK: - Hotkey trigger

    private func handleHotkeyTrigger() {
        Task { @MainActor in
            guard let result = await accessibilityBridge.captureText() else {
                // Capture failed — show alert per UI-SPEC
                showCaptureFailureAlert()
                return
            }
            // Phase 3: capture only — log the temp file path.
            // Phase 4 will open vim with result.tempFileURL.
            // Phase 5 will wire the full cycle.
            print("[AnyVim] Text captured to: \(result.tempFileURL.path)")
            print("[AnyVim] Original app: \(result.originalApp.localizedName ?? "unknown")")
            // NOTE: In Phase 3, we don't have vim yet, so clean up immediately.
            // This cleanup will move to Phase 5 when the full cycle is wired.
            accessibilityBridge.abortAndRestore(captureResult: result)
        }
    }

    /// Show alert when text capture fails (accessibility permission missing or no frontmost app).
    private func showCaptureFailureAlert() {
        let alert = NSAlert()
        alert.messageText = "Text Capture Failed"
        alert.informativeText = "AnyVim could not read the text in the focused field. Make sure Accessibility permission is granted, then try again."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Dismiss")
        alert.runModal()
    }

    // MARK: - Permission alerts

    /// Show the Accessibility permission alert (D-01, D-08).
    ///
    /// This is the FIRST alert shown. Per D-08, it includes the launch-at-login mention.
    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = """
            AnyVim needs Accessibility access to detect the focused text field and simulate \
            keyboard shortcuts to capture and restore text. Grant access in System Settings, \
            then return to AnyVim.

            AnyVim will also launch at login automatically. You can change this in the menu bar.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            permissionManager.openAccessibilitySettings()
        }
    }

    /// Show the Input Monitoring permission alert (D-02).
    private func showInputMonitoringAlert() {
        let alert = NSAlert()
        alert.messageText = "Input Monitoring Permission Required"
        alert.informativeText = """
            AnyVim needs Input Monitoring access to detect the double-tap Control key trigger \
            globally. Grant access in System Settings, then return to AnyVim.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            permissionManager.openInputMonitoringSettings()
        }
    }
}
