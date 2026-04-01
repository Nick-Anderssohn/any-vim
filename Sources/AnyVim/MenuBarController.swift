import AppKit

@MainActor
final class MenuBarController {

    // MARK: - Dependencies (protocol types for testability)

    private let permissionManager: PermissionChecking
    private let loginItemManager: LoginItemManaging
    private let hotkeyManager: HotkeyManaging?

    // MARK: - Init

    init(
        permissionManager: PermissionChecking,
        loginItemManager: LoginItemManaging,
        hotkeyManager: HotkeyManaging? = nil
    ) {
        self.permissionManager = permissionManager
        self.loginItemManager = loginItemManager
        self.hotkeyManager = hotkeyManager
    }

    // MARK: - Menu construction

    /// Build the full menu with live permission and login-item state.
    ///
    /// Called fresh on each menu open (or on permission change callback) so all
    /// values reflect the current OS state — no caching.
    func buildMenu() -> NSMenu {
        let menu = NSMenu()

        // --- Permission status items (D-03) ---

        if permissionManager.isAccessibilityGranted {
            let item = NSMenuItem(title: "Accessibility: Granted", action: nil, keyEquivalent: "")
            menu.addItem(item)
        } else {
            let item = NSMenuItem(
                title: "Accessibility: Not Granted \u{2014} Click to Enable",
                action: #selector(openAccessibilitySettings),
                keyEquivalent: ""
            )
            item.target = self
            menu.addItem(item)
        }

        if permissionManager.isInputMonitoringGranted {
            let item = NSMenuItem(title: "Input Monitoring: Granted", action: nil, keyEquivalent: "")
            menu.addItem(item)
        } else {
            let item = NSMenuItem(
                title: "Input Monitoring: Not Granted \u{2014} Click to Enable",
                action: #selector(openInputMonitoringSettings),
                keyEquivalent: ""
            )
            item.target = self
            menu.addItem(item)
        }

        // --- Tap health status (D-09: persistent menu bar indication) ---

        if let hk = hotkeyManager {
            if hk.isTapHealthy {
                let item = NSMenuItem(title: "Hotkey: Active", action: nil, keyEquivalent: "")
                menu.addItem(item)
            } else {
                let item = NSMenuItem(
                    title: "Hotkey: Inactive \u{2014} Tap Unhealthy",
                    action: nil,
                    keyEquivalent: ""
                )
                menu.addItem(item)
            }
        }

        menu.addItem(NSMenuItem.separator())

        // --- Launch at Login toggle (D-09) ---

        let loginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        loginItem.target = self
        loginItem.state = loginItemManager.isEnabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(NSMenuItem.separator())

        // --- Quit (MENU-03) ---

        let quitItem = NSMenuItem(
            title: "Quit AnyVim",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        return menu
    }

    // MARK: - Actions

    @objc private func openAccessibilitySettings() {
        permissionManager.openAccessibilitySettings()
    }

    @objc private func openInputMonitoringSettings() {
        permissionManager.openInputMonitoringSettings()
    }

    @objc private func toggleLaunchAtLogin() {
        if loginItemManager.isEnabled {
            loginItemManager.disable()
        } else {
            loginItemManager.enable()
        }
        // Menu checkmark updates on next open — buildMenu() reads live state
    }
}
