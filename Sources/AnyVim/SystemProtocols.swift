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

// MARK: - VimPathResolving

/// Abstraction over vim binary resolution for testability.
protocol VimPathResolving {
    /// Resolve the path to the vim binary in the user's shell PATH.
    /// Returns nil if vim is not found.
    func resolveVimPath() -> String?
}

// MARK: - FileModificationDateReading

/// Abstraction over file modification date reading for testability.
protocol FileModificationDateReading {
    /// Read the modification date of a file at the given URL.
    /// Returns nil if the file does not exist or is unreadable.
    func modificationDate(of url: URL) -> Date?
}

// MARK: - ShellVimPathResolver

/// Production implementation: resolves vim via a login shell subprocess.
///
/// Uses `/bin/zsh -l -c "which vim"` to honor the user's full shell PATH,
/// including Homebrew paths (D-08). macOS GUI apps inherit a minimal launchd PATH
/// that omits `/opt/homebrew/bin` — the login shell flag `-l` fixes this.
struct ShellVimPathResolver: VimPathResolving {
    func resolveVimPath() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", "which vim"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()  // discard stderr
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (path?.isEmpty == false) ? path : nil
    }
}

// MARK: - UserDefaultsVimPathResolver

/// Composing resolver: checks UserDefaults for a custom vim binary path first,
/// falls back to the given resolver (typically ShellVimPathResolver) when the
/// custom path is absent, empty, or not executable.
///
/// D-06: invalid custom path falls back silently — no alert at resolution time.
struct UserDefaultsVimPathResolver: VimPathResolving {
    private let fallback: VimPathResolving
    private let defaults: UserDefaults
    private let key: String

    init(
        fallback: VimPathResolving = ShellVimPathResolver(),
        defaults: UserDefaults = .standard,
        key: String = "customVimPath"
    ) {
        self.fallback = fallback
        self.defaults = defaults
        self.key = key
    }

    func resolveVimPath() -> String? {
        if let custom = defaults.string(forKey: key),
           !custom.isEmpty,
           FileManager.default.isExecutableFile(atPath: custom) {
            return custom
        }
        // D-06: invalid custom path falls back silently
        return fallback.resolveVimPath()
    }
}

// MARK: - SystemFileModificationDateReader

/// Production implementation: reads file modification date via FileManager.
struct SystemFileModificationDateReader: FileModificationDateReading {
    func modificationDate(of url: URL) -> Date? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attrs?[FileAttributeKey.modificationDate] as? Date
    }
}
