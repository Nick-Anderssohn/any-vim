import AppKit
import CoreGraphics

@main
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
    private var menuBarController: MenuBarController!

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

        // Build menu with live state
        menuBarController = MenuBarController(
            permissionManager: permissionManager,
            loginItemManager: loginItemManager
        )
        statusItem.menu = menuBarController.buildMenu()

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
        // Rebuild menu with updated live state
        statusItem.menu = menuBarController.buildMenu()

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
