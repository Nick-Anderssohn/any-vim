import AppKit

final class MenuBarController {

    func buildMenu() -> NSMenu {
        let menu = NSMenu()

        // Permission status items (D-03) — placeholder titles for Plan 01
        // Plan 02 will wire live AXIsProcessTrusted() / CGPreflightListenEventAccess() values
        let axItem = NSMenuItem(
            title: "Accessibility: Not Granted — Click to Enable",
            action: nil,
            keyEquivalent: ""
        )
        menu.addItem(axItem)

        let imItem = NSMenuItem(
            title: "Input Monitoring: Not Granted — Click to Enable",
            action: nil,
            keyEquivalent: ""
        )
        menu.addItem(imItem)

        menu.addItem(NSMenuItem.separator())

        // Launch at Login toggle placeholder — Plan 02 will wire SMAppService
        let loginItem = NSMenuItem(
            title: "Launch at Login",
            action: nil,
            keyEquivalent: ""
        )
        menu.addItem(loginItem)

        menu.addItem(NSMenuItem.separator())

        // Quit AnyVim (MENU-03)
        let quitItem = NSMenuItem(
            title: "Quit AnyVim",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        return menu
    }

    /// Called when permission state changes (Plan 02 will implement live updates)
    func updateMenu() {
        // Stub: Plan 02 will rebuild menu with live permission state
    }
}
