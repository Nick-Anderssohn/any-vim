import Foundation

/// Subset of AccessibilityBridge used by the edit cycle. Enables mock injection for tests.
@MainActor
protocol TextCapturing {
    func captureText() async -> CaptureResult?
    func openEmpty() async -> CaptureResult?
    func restoreText(_ editedContent: String, captureResult: CaptureResult) async
    func abortAndRestore(captureResult: CaptureResult)
}

/// Subset of VimSessionManager used by the edit cycle. Enables mock injection for tests.
@MainActor
protocol VimSessionOpening {
    func openVimSession(tempFileURL: URL) async -> VimExitResult
}
