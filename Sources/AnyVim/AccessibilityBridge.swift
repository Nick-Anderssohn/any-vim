import AppKit
import Carbon.HIToolbox
import CoreGraphics

/// Result of a text capture operation.
struct CaptureResult {
    /// URL of the temp file containing captured text.
    let tempFileURL: URL
    /// The app that was frontmost when the hotkey fired. Used for focus restore.
    let originalApp: NSRunningApplication
    /// Clipboard state before capture. Used for restore after edit cycle.
    let clipboardSnapshot: ClipboardSnapshot
}

/// Bridges the accessibility layer: captures text from any focused field via
/// simulated Cmd+A/Cmd+C, and pastes back via Cmd+A/Cmd+V. Owns clipboard
/// snapshot lifecycle. Single class per D-04.
@MainActor
final class AccessibilityBridge {

    // MARK: - Timing constants (D-01, D-02, D-03, COMPAT-03)

    /// Delay between Cmd+A and Cmd+C during capture (D-01: ~100-150ms)
    static let captureDelayNs: UInt64 = 150_000_000  // 150ms

    /// Delay after focus restore before posting Cmd+A/Cmd+V (D-03: ~200ms)
    static let focusRestoreDelayNs: UInt64 = 200_000_000  // 200ms

    /// Delay after Cmd+A before Cmd+V during paste-back
    static let pasteDelayNs: UInt64 = 150_000_000  // 150ms

    /// Delay after Cmd+V before restoring clipboard (D-06: ~100-200ms)
    static let clipboardRestoreDelayNs: UInt64 = 150_000_000  // 150ms

    // MARK: - Dependencies (protocol-injected for testability)

    private let keystrokeSender: KeystrokeSending
    private let appActivator: AppActivating
    private let clipboardGuard: ClipboardGuard
    private let tempFileManager: TempFileManager
    private let permissionChecker: PermissionChecking
    private let pasteboard: PasteboardAccessing

    // MARK: - Init

    init(
        keystrokeSender: KeystrokeSending = SystemKeystrokeSender(),
        appActivator: AppActivating = SystemAppActivator(),
        clipboardGuard: ClipboardGuard = ClipboardGuard(),
        tempFileManager: TempFileManager = TempFileManager(),
        permissionChecker: PermissionChecking,
        pasteboard: PasteboardAccessing = SystemPasteboard()
    ) {
        self.keystrokeSender = keystrokeSender
        self.appActivator = appActivator
        self.clipboardGuard = clipboardGuard
        self.tempFileManager = tempFileManager
        self.permissionChecker = permissionChecker
        self.pasteboard = pasteboard
    }

    // MARK: - Capture (CAPT-02, CAPT-03, CAPT-04)

    /// Capture text from the currently focused text field.
    /// Returns CaptureResult on success, nil if permissions missing or no frontmost app.
    func captureText() async -> CaptureResult? {
        // Guard: need Accessibility permission
        guard permissionChecker.isAccessibilityGranted else { return nil }

        // D-07: capture frontmost app FIRST, before any other work
        guard let originalApp = appActivator.frontmostApplication() else { return nil }

        // D-05, CAPT-01: snapshot clipboard before we overwrite it
        let snapshot = clipboardGuard.snapshot()

        // D-10: record changeCount before Cmd+C
        let changeCountBefore = pasteboard.changeCount

        // CAPT-02: Cmd+A (select all)
        keystrokeSender.postKeystroke(keyCode: CGKeyCode(kVK_ANSI_A), flags: .maskCommand)
        try? await Task.sleep(nanoseconds: Self.captureDelayNs)

        // CAPT-02: Cmd+C (copy)
        keystrokeSender.postKeystroke(keyCode: CGKeyCode(kVK_ANSI_C), flags: .maskCommand)
        try? await Task.sleep(nanoseconds: Self.captureDelayNs)

        // D-10: check changeCount to distinguish empty field vs capture failure
        let changeCountAfter = pasteboard.changeCount
        let capturedText: String
        if changeCountAfter == changeCountBefore {
            // changeCount unchanged — capture did not fire (D-10: use empty string)
            capturedText = ""
        } else {
            capturedText = pasteboard.stringForType(.string) ?? ""
        }

        // CAPT-03, CAPT-04: write to temp file (empty content is valid)
        guard let tempURL = try? tempFileManager.createTempFile(content: capturedText) else {
            // Failed to create temp file — restore clipboard and bail
            clipboardGuard.restore(snapshot)
            return nil
        }

        return CaptureResult(
            tempFileURL: tempURL,
            originalApp: originalApp,
            clipboardSnapshot: snapshot
        )
    }

    // MARK: - Restore

    /// Paste edited text back to the original app and restore the clipboard.
    /// Called after vim :wq with the edited file content.
    func restoreText(_ editedContent: String, captureResult: CaptureResult) async {
        let app = captureResult.originalApp

        // D-08: if original app quit during session, skip everything
        guard !app.isTerminated else { return }

        // Put edited content on clipboard for pasting
        pasteboard.clearContents()
        pasteboard.setString(editedContent, forType: .string)

        // Restore focus to original app (D-07)
        appActivator.activate(app)
        try? await Task.sleep(nanoseconds: Self.focusRestoreDelayNs)  // D-03

        // Cmd+A (select all) then Cmd+V (paste)
        keystrokeSender.postKeystroke(keyCode: CGKeyCode(kVK_ANSI_A), flags: .maskCommand)
        try? await Task.sleep(nanoseconds: Self.pasteDelayNs)
        keystrokeSender.postKeystroke(keyCode: CGKeyCode(kVK_ANSI_V), flags: .maskCommand)

        // D-06: wait for target app to finish reading pasteboard before restoring
        try? await Task.sleep(nanoseconds: Self.clipboardRestoreDelayNs)

        // Restore original clipboard (D-05, CAPT-01)
        clipboardGuard.restore(captureResult.clipboardSnapshot)
    }

    // MARK: - Abort

    /// Clean up after an aborted edit cycle (:q! or error).
    /// Restores clipboard without pasting anything.
    func abortAndRestore(captureResult: CaptureResult) {
        clipboardGuard.restore(captureResult.clipboardSnapshot)
        tempFileManager.deleteTempFile(at: captureResult.tempFileURL)
    }
}
