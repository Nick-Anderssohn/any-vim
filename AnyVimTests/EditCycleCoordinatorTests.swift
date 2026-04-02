import XCTest
@testable import AnyVim

// MARK: - MockTextCapture

@MainActor
final class MockTextCapture: TextCapturing {
    var captureTextResult: CaptureResult? = nil
    var captureTextCallCount = 0

    var restoreTextCalls: [(content: String, captureResult: CaptureResult)] = []
    var abortAndRestoreCalls: [CaptureResult] = []

    func captureText() async -> CaptureResult? {
        captureTextCallCount += 1
        return captureTextResult
    }

    func restoreText(_ editedContent: String, captureResult: CaptureResult) async {
        restoreTextCalls.append((editedContent, captureResult))
    }

    func abortAndRestore(captureResult: CaptureResult) {
        abortAndRestoreCalls.append(captureResult)
    }
}

// MARK: - MockVimSession

@MainActor
final class MockVimSession: VimSessionOpening {
    var exitResult: VimExitResult = .aborted

    func openVimSession(tempFileURL: URL) async -> VimExitResult {
        return exitResult
    }
}

// MARK: - EditCycleCoordinatorTests

@MainActor
final class EditCycleCoordinatorTests: XCTestCase {

    private var delegate: AppDelegate!
    private var mockCapture: MockTextCapture!
    private var mockVim: MockVimSession!
    private var createdTempFiles: [URL] = []

    override func setUp() {
        super.setUp()
        // Create AppDelegate without triggering applicationDidFinishLaunching
        delegate = AppDelegate()
        mockCapture = MockTextCapture()
        mockVim = MockVimSession()
        // Inject mocks via internal properties
        delegate.accessibilityBridge = mockCapture
        delegate.vimSessionManager = mockVim
    }

    override func tearDown() {
        for url in createdTempFiles {
            try? FileManager.default.removeItem(at: url)
        }
        createdTempFiles = []
        delegate = nil
        mockCapture = nil
        mockVim = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Create a real temp file with given content. Registers for teardown cleanup.
    private func makeTempFile(content: String = "original") throws -> URL {
        let url = try TempFileManager().createTempFile(content: content)
        createdTempFiles.append(url)
        return url
    }

    /// Build a CaptureResult using a real temp URL.
    private func makeCaptureResult(tempFileURL: URL) -> CaptureResult {
        return CaptureResult(
            tempFileURL: tempFileURL,
            originalApp: NSRunningApplication.current,
            clipboardSnapshot: []
        )
    }

    // MARK: - REST-01/REST-02: saved path calls restoreText with file content

    func testSavedExitCallsRestoreTextWithEditedContent() async throws {
        // Create temp file and write "edited" content (simulates vim save)
        let tempURL = try makeTempFile(content: "original")
        try "edited".write(to: tempURL, atomically: true, encoding: .utf8)

        mockCapture.captureTextResult = makeCaptureResult(tempFileURL: tempURL)
        mockVim.exitResult = .saved

        delegate.handleHotkeyTrigger()
        try await Task.sleep(nanoseconds: 100_000_000)  // 100ms for Task to complete

        XCTAssertEqual(mockCapture.restoreTextCalls.count, 1,
            "restoreText should be called exactly once on .saved exit (REST-01)")
        XCTAssertEqual(mockCapture.restoreTextCalls[0].content, "edited",
            "restoreText should receive the edited file content (REST-01)")
        XCTAssertEqual(mockCapture.abortAndRestoreCalls.count, 0,
            "abortAndRestore should NOT be called on successful .saved exit")
    }

    // MARK: - REST-03: aborted path skips restoreText

    func testAbortedExitCallsAbortAndRestore() async throws {
        let tempURL = try makeTempFile()
        mockCapture.captureTextResult = makeCaptureResult(tempFileURL: tempURL)
        mockVim.exitResult = .aborted

        delegate.handleHotkeyTrigger()
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(mockCapture.abortAndRestoreCalls.count, 1,
            "abortAndRestore should be called on .aborted exit (REST-03)")
        XCTAssertEqual(mockCapture.restoreTextCalls.count, 0,
            "restoreText should NOT be called on .aborted exit (REST-03)")
    }

    // MARK: - REST-05: temp file deleted after save

    func testTempFileDeletedAfterSave() async throws {
        let tempURL = try makeTempFile(content: "original")
        try "edited".write(to: tempURL, atomically: true, encoding: .utf8)

        mockCapture.captureTextResult = makeCaptureResult(tempFileURL: tempURL)
        mockVim.exitResult = .saved

        delegate.handleHotkeyTrigger()
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertFalse(FileManager.default.fileExists(atPath: tempURL.path),
            "Temp file should be deleted after .saved exit (REST-05)")
    }

    // MARK: - D-03: saved but file read fails → treat as abort

    func testSavedButFileDeletedTreatsAsAbort() async throws {
        // Create a URL that does NOT exist on disk
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("anyvim-nonexistent-\(UUID().uuidString).txt")

        mockCapture.captureTextResult = makeCaptureResult(tempFileURL: tempURL)
        mockVim.exitResult = .saved

        delegate.handleHotkeyTrigger()
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(mockCapture.restoreTextCalls.count, 0,
            "restoreText should NOT be called when file read fails (D-03)")
        XCTAssertEqual(mockCapture.abortAndRestoreCalls.count, 1,
            "abortAndRestore should be called when file read fails (D-03)")
    }

    // MARK: - Re-entrancy guard blocks second trigger

    func testReentrancyGuardBlocksSecondTrigger() async throws {
        delegate.isEditSessionActive = true

        delegate.handleHotkeyTrigger()
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(mockCapture.captureTextCallCount, 0,
            "captureText should NOT be called when isEditSessionActive is true (D-01)")
    }

    // MARK: - Guard resets after completion

    func testGuardResetsAfterCompletion() async throws {
        let tempURL = try makeTempFile()
        mockCapture.captureTextResult = makeCaptureResult(tempFileURL: tempURL)
        mockVim.exitResult = .aborted

        delegate.handleHotkeyTrigger()
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertFalse(delegate.isEditSessionActive,
            "isEditSessionActive should be false after edit cycle completes (D-02)")
    }
}
