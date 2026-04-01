import AppKit

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var menuBarController: MenuBarController!

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

        // Build menu
        menuBarController = MenuBarController()
        statusItem.menu = menuBarController.buildMenu()
    }
}
