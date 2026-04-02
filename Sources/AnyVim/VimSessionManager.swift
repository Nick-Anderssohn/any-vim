// VimSessionManager — core class that opens a floating SwiftTerm terminal window
// with vim, detects save vs abort via mtime, and returns a VimExitResult.
//
// Architecture:
//   - @MainActor isolated (Phase 4 pattern; all UI work is on main thread)
//   - async/await via CheckedContinuation (caller suspends until vim exits)
//   - Dependency injection for testability (VimPathResolving, FileModificationDateReading)
//   - Instance properties retained to prevent ARC release (Phase 1 NSStatusItem pattern)
//
// Exit detection (D-05, D-06):
//   Record file mtime BEFORE launching vim. After processTerminated fires,
//   compare mtime. Changed = :wq (saved). Unchanged = :q! or crash (aborted).
//   Exit code is NOT used — vim exits 0 for both :wq and :q!.
import AppKit
import SwiftTerm

// MARK: - VimExitResult

/// Result of a vim session — indicates whether the user saved (:wq) or aborted (:q!).
enum VimExitResult: Equatable {
    case saved
    case aborted

    /// Determine exit result by comparing file modification dates before and after vim ran.
    /// If either date is nil or both dates are equal, treat as aborted (D-05, D-06).
    static func from(mtimeBefore: Date?, mtimeAfter: Date?) -> VimExitResult {
        guard let before = mtimeBefore, let after = mtimeAfter else {
            return .aborted
        }
        return before == after ? .aborted : .saved
    }
}

// MARK: - VimSessionManager

/// Manages the lifecycle of a single vim editing session.
///
/// Usage:
/// ```swift
/// let result = await vimSessionManager.openVimSession(tempFileURL: url)
/// switch result {
/// case .saved: // user wrote the file
/// case .aborted: // user quit without saving
/// }
/// ```
@MainActor
final class VimSessionManager: NSObject {

    // MARK: - Dependencies

    private let vimPathResolver: VimPathResolving
    private let fileModDateReader: FileModificationDateReading

    // MARK: - Retained instance state
    // All stored as instance properties to prevent ARC release (Pitfall 6 pattern)

    private var panel: VimPanel?
    private var terminalView: LocalProcessTerminalView?
    private var continuation: CheckedContinuation<VimExitResult, Never>?
    private var currentTempFileURL: URL?
    private var mtimeBefore: Date?

    /// Observation token for NSWindow.willCloseNotification (D-07: close button = abort).
    private var closeObserver: NSObjectProtocol?

    // MARK: - Constants

    private let windowFrameKey = "VimWindowFrame"
    private let defaultColumns = 100
    private let defaultRows = 35

    // MARK: - Init

    /// - Parameters:
    ///   - vimPathResolver: Resolves the vim binary path (injectable for tests).
    ///   - fileModDateReader: Reads file modification dates (injectable for tests).
    ///   - showAlerts: Set to false in unit tests to suppress modal dialogs.
    init(
        vimPathResolver: VimPathResolving = ShellVimPathResolver(),
        fileModDateReader: FileModificationDateReading = SystemFileModificationDateReader(),
        showAlerts: Bool = true
    ) {
        self.vimPathResolver = vimPathResolver
        self.fileModDateReader = fileModDateReader
        self.showAlerts = showAlerts
    }

    /// Controls whether modal alerts are shown. Set to false in unit tests.
    private let showAlerts: Bool

    // MARK: - Public API

    /// Open a floating terminal window with vim editing the given temp file.
    ///
    /// Suspends the caller until vim exits (`:wq` or `:q!` or window close).
    /// Returns `.saved` if the file was modified, `.aborted` otherwise.
    ///
    /// - Parameter tempFileURL: Path to the temp file vim should open.
    /// - Returns: `.saved` if user saved, `.aborted` if user quit without saving.
    func openVimSession(tempFileURL: URL) async -> VimExitResult {
        // D-08, D-09: resolve vim binary via login shell to get user's full PATH
        guard let vimPath = vimPathResolver.resolveVimPath() else {
            showVimNotFoundAlert()
            return .aborted
        }

        // D-05: record mtime before launching — baseline for exit detection
        mtimeBefore = fileModDateReader.modificationDate(of: tempFileURL)
        currentTempFileURL = tempFileURL

        // Build panel and terminal view
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let contentRect = restoredOrCenteredRect(font: font)

        // Create and configure panel (Pitfall 2: no .nonactivatingPanel — prevents keyboard input)
        let panel = VimPanel(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.hidesOnDeactivate = false     // Stay visible when user clicks another app
        panel.isReleasedWhenClosed = false  // Pitfall 6: VimSessionManager owns lifecycle
        panel.title = "AnyVim"

        let termFrame = panel.contentView?.bounds ?? CGRect(x: 0, y: 0, width: contentRect.width, height: contentRect.height)
        let tv = LocalProcessTerminalView(frame: termFrame)

        // D-10: SF Mono 13pt
        tv.font = font
        // D-11: respect system dark/light mode
        tv.configureNativeColors()

        // Pitfall 7: add terminal view to hierarchy BEFORE startProcess
        tv.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(tv)

        // Wire delegate for process termination notification (Pitfall 5: use processDelegate, not terminalDelegate)
        tv.processDelegate = self

        // Retain as instance properties before startProcess (ARC safety, Phase 1 pattern)
        self.panel = panel
        self.terminalView = tv

        // D-07: close button treated as abort — observe willCloseNotification
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            self?.handleWindowClosed()
        }

        // Suspend caller until vim exits
        return await withCheckedContinuation { cont in
            self.continuation = cont

            // Start vim in the terminal
            tv.startProcess(
                executable: vimPath,
                args: [tempFileURL.path],
                environment: nil,  // SwiftTerm provides TERM=xterm-256color, HOME, USER, LANG, etc.
                execName: nil,
                currentDirectory: nil
            )

            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Private helpers

    /// Calculate the window frame: restore from UserDefaults if available, else center on screen.
    private func restoredOrCenteredRect(font: NSFont) -> NSRect {
        // D-02: restore saved frame if available
        if let saved = UserDefaults.standard.string(forKey: windowFrameKey) {
            let rect = NSRectFromString(saved)
            if rect.width > 100 && rect.height > 100 {
                return rect
            }
        }
        return centeredRect(font: font)
    }

    /// Compute a centered window rect for the given font and default column/row counts.
    /// D-01: open centered on the active display.
    private func centeredRect(font: NSFont) -> NSRect {
        let charSize = font.boundingRectForFont
        let padding: CGFloat = 10
        let titleBarHeight: CGFloat = 28

        let width = CGFloat(defaultColumns) * charSize.width + 2 * padding
        let height = CGFloat(defaultRows) * charSize.height + 2 * padding + titleBarHeight

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let screenRect = screen.visibleFrame
        let x = screenRect.midX - width / 2
        let y = screenRect.midY - height / 2
        return NSRect(x: x, y: y, width: width, height: height)
    }

    /// Called when the vim process terminates (via processDelegate).
    private func handleProcessTerminated() {
        guard let url = currentTempFileURL else {
            resumeContinuation(with: .aborted)
            return
        }

        // D-05: compare mtime after vim exits to determine save vs abort
        let mtimeAfter = fileModDateReader.modificationDate(of: url)
        let result = VimExitResult.from(mtimeBefore: mtimeBefore, mtimeAfter: mtimeAfter)

        // D-02: save window frame for next session
        if let panel = panel {
            UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: windowFrameKey)
        }

        cleanupSession()
        resumeContinuation(with: result)
    }

    /// Called when the window's close button is clicked (D-07).
    private func handleWindowClosed() {
        // Only act if continuation is still pending (not already resolved by processTerminated)
        guard continuation != nil else { return }

        // D-07: close button = abort. SwiftTerm will kill the process when view is removed.
        cleanupSession()
        resumeContinuation(with: .aborted)
    }

    /// Resume the continuation if one is pending.
    private func resumeContinuation(with result: VimExitResult) {
        guard let cont = continuation else { return }
        continuation = nil
        cont.resume(returning: result)
    }

    /// Clean up session state — nil out retained properties.
    private func cleanupSession() {
        if let observer = closeObserver {
            NotificationCenter.default.removeObserver(observer)
            closeObserver = nil
        }
        panel?.close()
        panel = nil
        terminalView = nil
        currentTempFileURL = nil
        mtimeBefore = nil
    }

    /// Show an NSAlert telling the user vim was not found (D-09).
    private func showVimNotFoundAlert() {
        guard showAlerts else { return }
        let alert = NSAlert()
        alert.messageText = "vim Not Found"
        alert.informativeText = """
            AnyVim could not find the vim binary in your PATH. \
            Install vim via Homebrew and try again:

            brew install vim
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

extension VimSessionManager: VimSessionOpening {}

// MARK: - LocalProcessTerminalViewDelegate

extension VimSessionManager: LocalProcessTerminalViewDelegate {
    /// Called by SwiftTerm when the terminal/process requests a size change.
    /// We let the NSPanel handle resizing — no action needed here.
    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        // Window resizing handled by NSPanel's resizable style mask
    }

    /// Called by SwiftTerm when the process updates the terminal title.
    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        // Update panel title on the main actor
        Task { @MainActor in
            self.panel?.title = title.isEmpty ? "AnyVim" : title
        }
    }

    /// Called by SwiftTerm when the process updates its current working directory.
    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        // Not needed for vim session management
    }

    /// Called by SwiftTerm when the vim process exits.
    ///
    /// NOTE: Swift 6 concurrency — this callback may arrive on a non-main thread
    /// (SwiftTerm uses DispatchSource internally). Dispatch to main actor to safely
    /// access @MainActor-isolated state.
    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor in
            self.handleProcessTerminated()
        }
    }
}
