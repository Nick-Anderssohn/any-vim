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
    var accessibilityBridge: (any TextCapturing)!
    var vimSessionManager: (any VimSessionOpening)!

    /// Re-entrancy guard — prevents a second trigger while vim is open (D-01, D-02).
    var isEditSessionActive = false

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register UserDefaults defaults before any reads (ensures bool(forKey:) returns correct value when key absent)
        UserDefaults.standard.register(defaults: ["copyExistingText": true])

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

        // Create VimSessionManager (Phase 4: hosts vim in floating SwiftTerm window)
        // CONF-01: inject UserDefaultsVimPathResolver to support custom vim binary
        vimSessionManager = VimSessionManager(vimPathResolver: UserDefaultsVimPathResolver())

        // Create and wire HotkeyManager (D-06: install immediately if permissions already granted)
        hotkeyManager = HotkeyManager()
        hotkeyManager.onTrigger = { [weak self] in self?.handleHotkeyTrigger() }
        hotkeyManager.onHealthChange = { [weak self] _ in self?.rebuildMenu() }

        // Build menu with live state (must happen before install() — the health change
        // callback fires synchronously during install and calls rebuildMenu())
        // CONF-01: pass vimPathResolver and rebuild callback for vim path section
        menuBarController = MenuBarController(
            permissionManager: permissionManager,
            loginItemManager: loginItemManager,
            hotkeyManager: hotkeyManager,
            vimPathResolver: UserDefaultsVimPathResolver(),
            onVimPathChange: { [weak self] in self?.rebuildMenu() }
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

    func handleHotkeyTrigger() {
        Task { @MainActor in
            // D-01: silent swallow if session already active
            guard !isEditSessionActive else { return }
            isEditSessionActive = true
            // MENU-02 D-03: set active icon before captureText
            // statusItem is nil in unit test context — optional chain prevents crash
            statusItem?.button?.image = NSImage(systemSymbolName: "pencil.circle.fill",
                                                 accessibilityDescription: "AnyVim \u{2014} editing")
            statusItem?.button?.image?.isTemplate = true
            // D-02: defer ensures reset on ALL exit paths (including captureText failure)
            defer {
                isEditSessionActive = false
                // MENU-02 D-03: restore idle icon on ALL exit paths
                statusItem?.button?.image = NSImage(systemSymbolName: "character.cursor.ibeam",
                                                     accessibilityDescription: "AnyVim")
                statusItem?.button?.image?.isTemplate = true
            }

            let copyExistingText = UserDefaults.standard.bool(forKey: "copyExistingText")
            let result: CaptureResult?
            if copyExistingText {
                result = await accessibilityBridge.captureText()
            } else {
                result = await accessibilityBridge.openEmpty()
            }
            guard let result else {
                showCaptureFailureAlert()
                return
            }

            let exitResult = await vimSessionManager.openVimSession(tempFileURL: result.tempFileURL)

            switch exitResult {
            case .saved:
                // REST-01: read edited file content
                if let editedContent = try? String(contentsOf: result.tempFileURL, encoding: .utf8) {
                    // Vim always appends a trailing newline on :wq — strip it so the
                    // pasted text matches what the user actually typed.
                    let trimmed = editedContent.replacingOccurrences(of: "\\n+$", with: "", options: .regularExpression)
                    // REST-01, REST-02: paste edited text back to original app
                    await accessibilityBridge.restoreText(trimmed, captureResult: result, selectAllBeforePaste: copyExistingText)
                    // REST-05: delete temp file (restoreText does not delete)
                    TempFileManager().deleteTempFile(at: result.tempFileURL)
                } else {
                    // D-03, D-04: read failure — treat as abort, no user alert
                    accessibilityBridge.abortAndRestore(captureResult: result)
                }

            case .aborted:
                // REST-03: skip paste-back
                // REST-04, REST-05: abortAndRestore restores clipboard and deletes temp file
                accessibilityBridge.abortAndRestore(captureResult: result)
            }
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
