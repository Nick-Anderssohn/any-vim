// System API abstractions for testability — follows TapInstalling pattern from HotkeyManager.swift
import AppKit
import CoreGraphics

// MARK: - PasteboardAccessing

/// Abstraction over NSPasteboard.general for testability.
protocol PasteboardAccessing {
    var changeCount: Int { get }
    func pasteboardItems() -> [NSPasteboardItem]?
    func stringForType(_ type: NSPasteboard.PasteboardType) -> String?
    func clearContents()
    func writeObjects(_ items: [NSPasteboardItem])
    func setString(_ string: String, forType type: NSPasteboard.PasteboardType)
}

// MARK: - KeystrokeSending

/// Abstraction over CGEvent.post for testability.
protocol KeystrokeSending {
    func postKeystroke(keyCode: CGKeyCode, flags: CGEventFlags)
}

// MARK: - AppActivating

/// Abstraction over NSWorkspace/NSRunningApplication for testability.
protocol AppActivating {
    func frontmostApplication() -> NSRunningApplication?
    func activate(_ app: NSRunningApplication)
}

// MARK: - SystemPasteboard

/// Production implementation wrapping NSPasteboard.general.
struct SystemPasteboard: PasteboardAccessing {
    var changeCount: Int {
        NSPasteboard.general.changeCount
    }

    func pasteboardItems() -> [NSPasteboardItem]? {
        NSPasteboard.general.pasteboardItems
    }

    func stringForType(_ type: NSPasteboard.PasteboardType) -> String? {
        NSPasteboard.general.string(forType: type)
    }

    func clearContents() {
        NSPasteboard.general.clearContents()
    }

    func writeObjects(_ items: [NSPasteboardItem]) {
        NSPasteboard.general.writeObjects(items)
    }

    func setString(_ string: String, forType type: NSPasteboard.PasteboardType) {
        NSPasteboard.general.setString(string, forType: type)
    }
}

// MARK: - SystemKeystrokeSender

/// Production implementation posting CGEvents to .cghidEventTap.
/// Per RESEARCH.md Pitfall 4: ALWAYS use .hidSystemState event source.
struct SystemKeystrokeSender: KeystrokeSending {
    func postKeystroke(keyCode: CGKeyCode, flags: CGEventFlags) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return }
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

// MARK: - SystemAppActivator

/// Production implementation wrapping NSWorkspace.shared and NSRunningApplication.activate.
struct SystemAppActivator: AppActivating {
    func frontmostApplication() -> NSRunningApplication? {
        NSWorkspace.shared.frontmostApplication
    }

    /// Per D-07: no .activateIgnoringOtherApps.
    func activate(_ app: NSRunningApplication) {
        app.activate(options: [])
    }
}
