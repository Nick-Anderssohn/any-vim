import AppKit

@MainActor
final class MenuBarController {

    // MARK: - Dependencies (protocol types for testability)

    private let permissionManager: PermissionChecking
    private let loginItemManager: LoginItemManaging
    private let hotkeyManager: HotkeyManaging?
    private let vimPathResolver: VimPathResolving?
    private let onMenuRefreshNeeded: (() -> Void)?

    // MARK: - Init

    init(
        permissionManager: PermissionChecking,
        loginItemManager: LoginItemManaging,
        hotkeyManager: HotkeyManaging? = nil,
        vimPathResolver: VimPathResolving? = nil,
        onMenuRefreshNeeded: (() -> Void)? = nil
    ) {
        self.permissionManager = permissionManager
        self.loginItemManager = loginItemManager
        self.hotkeyManager = hotkeyManager
        self.vimPathResolver = vimPathResolver
        self.onMenuRefreshNeeded = onMenuRefreshNeeded
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

        // --- Vim path section (CONF-01 D-05, D-06) ---

        if let _ = vimPathResolver {
            let customPath = UserDefaults.standard.string(forKey: "customVimPath")
            let isCustomSet = customPath != nil && !customPath!.isEmpty

            let pathDisplay: String
            if isCustomSet {
                // Validate custom path executability — avoid calling resolver (Pitfall 3: blocks main thread)
                let isValid = FileManager.default.isExecutableFile(atPath: customPath!)
                pathDisplay = isValid ? "Vim: \(customPath!)" : "Vim: (custom path invalid)"
            } else {
                // No custom path — show static default label (Pitfall 3: avoid ShellVimPathResolver on main thread)
                pathDisplay = "Vim: (default)"
            }

            let pathItem = NSMenuItem(title: pathDisplay, action: nil, keyEquivalent: "")
            pathItem.isEnabled = false
            menu.addItem(pathItem)

            let setItem = NSMenuItem(title: "Set Vim Path...", action: #selector(setVimPath), keyEquivalent: "")
            setItem.target = self
            menu.addItem(setItem)

            if isCustomSet {
                let resetItem = NSMenuItem(title: "Reset Vim Path", action: #selector(resetVimPath), keyEquivalent: "")
                resetItem.target = self
                menu.addItem(resetItem)
            }

            menu.addItem(NSMenuItem.separator())
        }

        // --- Copy Existing Text toggle ---

        let copyExistingItem = NSMenuItem(
            title: "Copy Existing Text",
            action: #selector(toggleCopyExistingText),
            keyEquivalent: ""
        )
        copyExistingItem.target = self
        copyExistingItem.state = UserDefaults.standard.bool(forKey: "copyExistingText") ? .on : .off
        menu.addItem(copyExistingItem)

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

    @objc private func toggleCopyExistingText() {
        let current = UserDefaults.standard.bool(forKey: "copyExistingText")
        UserDefaults.standard.set(!current, forKey: "copyExistingText")
        onMenuRefreshNeeded?()
    }

    @objc private func toggleLaunchAtLogin() {
        if loginItemManager.isEnabled {
            loginItemManager.disable()
        } else {
            loginItemManager.enable()
        }
        onMenuRefreshNeeded?()
    }

    @objc private func setVimPath() {
        let panel = NSOpenPanel()
        panel.title = "Choose Vim Binary"
        panel.message = "Select the vim executable to use with AnyVim"
        panel.prompt = "Select"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = []
        panel.directoryURL = URL(fileURLWithPath: "/usr/local/bin")

        if panel.runModal() == .OK, let url = panel.url {
            let path = url.path
            if FileManager.default.isExecutableFile(atPath: path) {
                UserDefaults.standard.set(path, forKey: "customVimPath")
                onMenuRefreshNeeded?()
            }
        }
    }

    @objc private func resetVimPath() {
        UserDefaults.standard.removeObject(forKey: "customVimPath")
        onMenuRefreshNeeded?()
    }
}
