import XCTest
import CoreGraphics
@testable import AnyVim

// MARK: - MockKeystrokeSender

/// Mock keystroke sender — records all posted keystrokes for assertion.
final class MockKeystrokeSender: KeystrokeSending {
    var postedKeystrokes: [(keyCode: CGKeyCode, flags: CGEventFlags)] = []

    func postKeystroke(keyCode: CGKeyCode, flags: CGEventFlags) {
        postedKeystrokes.append((keyCode: keyCode, flags: flags))
    }
}

// MARK: - MockAppActivator

/// Mock app activator — returns a configurable frontmost app and records activate calls.
final class MockAppActivator: AppActivating {
    var frontmostApp: NSRunningApplication? = NSRunningApplication.current
    var activateCalled = false
    var activatedApp: NSRunningApplication?

    func frontmostApplication() -> NSRunningApplication? {
        return frontmostApp
    }

    func activate(_ app: NSRunningApplication) {
        activateCalled = true
        activatedApp = app
    }
}

// MARK: - MockPasteboardForBridge

/// Extended mock pasteboard for AccessibilityBridge tests — supports changeCount tracking
/// and string return.
final class MockPasteboardForBridge: PasteboardAccessing {
    /// The current changeCount. Set this before test. The bridge reads it before Cmd+A and
    /// after Cmd+C. If you want to simulate a successful copy, set `changeCountAfterCopy`
    /// to a different value — it will be returned on the second changeCount read.
    private var changeCountReadCount = 0
    private var _changeCount: Int = 0

    var changeCount: Int {
        get {
            changeCountReadCount += 1
            if let afterCopy = changeCountAfterCopy, changeCountReadCount > 1 {
                return afterCopy
            }
            return _changeCount
        }
        set {
            _changeCount = newValue
            changeCountReadCount = 0
        }
    }

    /// If set, the second (and subsequent) reads of changeCount return this value.
    /// Use this to simulate the clipboard changing after Cmd+C.
    var changeCountAfterCopy: Int? = nil

    var items: [NSPasteboardItem]?
    var stringToReturn: String? = nil
    var clearContentsCalled = false
    var setStringCalled = false
    var lastSetString: String? = nil
    var writtenItems: [NSPasteboardItem] = []

    func pasteboardItems() -> [NSPasteboardItem]? {
        return items
    }

    func stringForType(_ type: NSPasteboard.PasteboardType) -> String? {
        return stringToReturn
    }

    func clearContents() {
        clearContentsCalled = true
        items = []
    }

    func writeObjects(_ items: [NSPasteboardItem]) {
        writtenItems = items
        self.items = items
    }

    func setString(_ string: String, forType type: NSPasteboard.PasteboardType) {
        setStringCalled = true
        lastSetString = string
    }
}

// MARK: - MockPermissionCheckerForBridge

/// Local mock permission checker for AccessibilityBridge tests.
final class MockPermissionCheckerForBridge: PermissionChecking {
    var isAccessibilityGranted: Bool
    var isInputMonitoringGranted: Bool
    var openAccessibilitySettingsCalled = false
    var openInputMonitoringSettingsCalled = false

    init(accessibility: Bool = true, inputMonitoring: Bool = true) {
        self.isAccessibilityGranted = accessibility
        self.isInputMonitoringGranted = inputMonitoring
    }

    func openAccessibilitySettings() {
        openAccessibilitySettingsCalled = true
    }

    func openInputMonitoringSettings() {
        openInputMonitoringSettingsCalled = true
    }
}

// MARK: - AccessibilityBridgeTests

@MainActor
final class AccessibilityBridgeTests: XCTestCase {

    private var mockKeystrokeSender: MockKeystrokeSender!
    private var mockAppActivator: MockAppActivator!
    private var mockPasteboard: MockPasteboardForBridge!
    private var mockPermissionChecker: MockPermissionCheckerForBridge!
    private var bridge: AccessibilityBridge!
    private var createdTempFiles: [URL] = []

    override func setUp() {
        super.setUp()
        mockKeystrokeSender = MockKeystrokeSender()
        mockAppActivator = MockAppActivator()
        mockPasteboard = MockPasteboardForBridge()
        mockPermissionChecker = MockPermissionCheckerForBridge()

        // Set up pasteboard with initial changeCount
        mockPasteboard.changeCount = 0

        bridge = AccessibilityBridge(
            keystrokeSender: mockKeystrokeSender,
            appActivator: mockAppActivator,
            clipboardGuard: ClipboardGuard(pasteboard: mockPasteboard),
            tempFileManager: TempFileManager(),
            permissionChecker: mockPermissionChecker,
            pasteboard: mockPasteboard
        )
    }

    override func tearDown() {
        // Clean up any temp files created during tests
        for url in createdTempFiles {
            try? FileManager.default.removeItem(at: url)
        }
        createdTempFiles = []
        bridge = nil
        mockPermissionChecker = nil
        mockPasteboard = nil
        mockAppActivator = nil
        mockKeystrokeSender = nil
        super.tearDown()
    }

    // MARK: - Capture tests

    func testCaptureTextPostsCmdACmdC() async {
        // Simulate pasteboard changeCount change after Cmd+C so capture succeeds
        mockPasteboard.changeCount = 0
        mockPasteboard.changeCountAfterCopy = 1  // Simulate clipboard updated after Cmd+C
        mockPasteboard.stringToReturn = "captured text"

        let result = await bridge.captureText()

        XCTAssertNotNil(result, "captureText should succeed")
        XCTAssertGreaterThanOrEqual(mockKeystrokeSender.postedKeystrokes.count, 2,
            "captureText should post at least 2 keystrokes")

        let cmdA = mockKeystrokeSender.postedKeystrokes[0]
        let cmdC = mockKeystrokeSender.postedKeystrokes[1]
        XCTAssertEqual(cmdA.keyCode, CGKeyCode(0x00), "First keystroke should be Cmd+A (keyCode 0x00)")
        XCTAssertTrue(cmdA.flags.contains(.maskCommand), "Cmd+A should have .maskCommand")
        XCTAssertEqual(cmdC.keyCode, CGKeyCode(0x08), "Second keystroke should be Cmd+C (keyCode 0x08)")
        XCTAssertTrue(cmdC.flags.contains(.maskCommand), "Cmd+C should have .maskCommand")

        if let url = result?.tempFileURL {
            createdTempFiles.append(url)
        }
    }

    func testCaptureTextSnapshotsClipboardBeforeKeystrokes() async {
        mockPasteboard.changeCount = 0
        mockPasteboard.changeCountAfterCopy = 1
        mockPasteboard.stringToReturn = "some text"
        // Put an item in pasteboard so snapshot returns something
        let item = NSPasteboardItem()
        item.setString("original clipboard", forType: .string)
        mockPasteboard.items = [item]

        let result = await bridge.captureText()

        XCTAssertNotNil(result, "captureText should succeed")
        // Verify snapshot was taken (clipboardSnapshot in result should reflect original content)
        XCTAssertNotNil(result?.clipboardSnapshot, "CaptureResult should contain a clipboard snapshot")

        if let url = result?.tempFileURL {
            createdTempFiles.append(url)
        }
    }

    func testCaptureTextCreatesTempFile() async {
        // Simulate clipboard updating after Cmd+C
        mockPasteboard.changeCount = 0
        mockPasteboard.changeCountAfterCopy = 1
        mockPasteboard.stringToReturn = "hello world"

        let result = await bridge.captureText()

        XCTAssertNotNil(result, "captureText should return a result")
        XCTAssertNotNil(result?.tempFileURL, "CaptureResult should have a tempFileURL")

        if let url = result?.tempFileURL {
            createdTempFiles.append(url)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                "Temp file should exist on disk")
            let content = try? String(contentsOf: url, encoding: .utf8)
            XCTAssertEqual(content, "hello world", "Temp file should contain captured text")
        }
    }

    func testCaptureTextReturnsOriginalApp() async {
        mockPasteboard.changeCount = 0
        mockPasteboard.changeCountAfterCopy = 1
        mockPasteboard.stringToReturn = "text"
        let expectedApp = NSRunningApplication.current
        mockAppActivator.frontmostApp = expectedApp

        let result = await bridge.captureText()

        XCTAssertNotNil(result, "captureText should succeed")
        XCTAssertEqual(result?.originalApp.processIdentifier,
            expectedApp.processIdentifier,
            "CaptureResult should contain the frontmost app at trigger time")

        if let url = result?.tempFileURL {
            createdTempFiles.append(url)
        }
    }

    func testCaptureTextEmptyClipboard() async {
        // changeCount changes (Cmd+C fired) but pasteboard string is nil
        mockPasteboard.changeCount = 0
        mockPasteboard.changeCountAfterCopy = 1
        mockPasteboard.stringToReturn = nil

        let result = await bridge.captureText()

        XCTAssertNotNil(result, "captureText should still succeed with nil clipboard string")

        if let url = result?.tempFileURL {
            createdTempFiles.append(url)
            let content = try? String(contentsOf: url, encoding: .utf8)
            XCTAssertEqual(content, "", "Empty clipboard should produce empty temp file (CAPT-04)")
        }
    }

    func testCaptureTextUnchangedChangeCount() async {
        // changeCount does NOT change — simulates capture failure (field didn't copy)
        // changeCountAfterCopy is nil, so both reads return the same value
        mockPasteboard.changeCount = 42
        mockPasteboard.changeCountAfterCopy = nil  // Same value on both reads
        mockPasteboard.stringToReturn = "ignored text"  // Should NOT be used

        let result = await bridge.captureText()

        XCTAssertNotNil(result, "captureText should succeed even with unchanged changeCount (D-10)")

        if let url = result?.tempFileURL {
            createdTempFiles.append(url)
            let content = try? String(contentsOf: url, encoding: .utf8)
            XCTAssertEqual(content, "",
                "Unchanged changeCount should produce empty temp file (CAPT-04, D-10)")
        }
    }

    func testCaptureTextNoAccessibility() async {
        mockPermissionChecker.isAccessibilityGranted = false

        let result = await bridge.captureText()

        XCTAssertNil(result, "captureText should return nil when Accessibility permission not granted")
    }

    func testCaptureTextNoFrontmostApp() async {
        mockAppActivator.frontmostApp = nil

        let result = await bridge.captureText()

        XCTAssertNil(result, "captureText should return nil when no frontmost app is available")
    }

    // MARK: - Restore tests

    func testRestoreTextPostsCmdACmdV() async {
        // First do a real capture to get a valid CaptureResult
        mockPasteboard.changeCount = 0
        mockPasteboard.changeCountAfterCopy = 1
        mockPasteboard.stringToReturn = "original"
        let captureResult = await bridge.captureText()
        XCTAssertNotNil(captureResult)

        // Reset keystroke record for restore call
        mockKeystrokeSender.postedKeystrokes = []

        // Call restore
        await bridge.restoreText("edited content", captureResult: captureResult!, selectAllBeforePaste: true)

        XCTAssertGreaterThanOrEqual(mockKeystrokeSender.postedKeystrokes.count, 2,
            "restoreText should post at least 2 keystrokes")

        let cmdA = mockKeystrokeSender.postedKeystrokes[0]
        let cmdV = mockKeystrokeSender.postedKeystrokes[1]
        XCTAssertEqual(cmdA.keyCode, CGKeyCode(0x00), "First keystroke should be Cmd+A (keyCode 0x00)")
        XCTAssertTrue(cmdA.flags.contains(.maskCommand), "Cmd+A should have .maskCommand")
        XCTAssertEqual(cmdV.keyCode, CGKeyCode(0x09), "Second keystroke should be Cmd+V (keyCode 0x09)")
        XCTAssertTrue(cmdV.flags.contains(.maskCommand), "Cmd+V should have .maskCommand")

        if let url = captureResult?.tempFileURL {
            createdTempFiles.append(url)
        }
    }

    func testRestoreTextActivatesOriginalApp() async {
        mockPasteboard.changeCount = 0
        mockPasteboard.changeCountAfterCopy = 1
        mockPasteboard.stringToReturn = "text"
        let captureResult = await bridge.captureText()
        XCTAssertNotNil(captureResult)

        mockAppActivator.activateCalled = false

        await bridge.restoreText("edited", captureResult: captureResult!, selectAllBeforePaste: true)

        XCTAssertTrue(mockAppActivator.activateCalled,
            "restoreText should activate the original app (D-07)")

        if let url = captureResult?.tempFileURL {
            createdTempFiles.append(url)
        }
    }

    func testRestoreTextSetsClipboardBeforePaste() async {
        mockPasteboard.changeCount = 0
        mockPasteboard.changeCountAfterCopy = 1
        mockPasteboard.stringToReturn = "text"
        let captureResult = await bridge.captureText()
        XCTAssertNotNil(captureResult)

        mockPasteboard.setStringCalled = false
        mockPasteboard.lastSetString = nil

        await bridge.restoreText("edited content", captureResult: captureResult!, selectAllBeforePaste: true)

        XCTAssertTrue(mockPasteboard.setStringCalled,
            "restoreText should set clipboard string before pasting")
        XCTAssertEqual(mockPasteboard.lastSetString, "edited content",
            "Clipboard should contain the edited content before paste")

        if let url = captureResult?.tempFileURL {
            createdTempFiles.append(url)
        }
    }

    // MARK: - Timing constants test

    func testTimingConstantsAreNonZero() {
        XCTAssertGreaterThan(AccessibilityBridge.captureDelayNs, 0,
            "captureDelayNs must be non-zero (COMPAT-03)")
        XCTAssertGreaterThan(AccessibilityBridge.focusRestoreDelayNs, 0,
            "focusRestoreDelayNs must be non-zero (COMPAT-03)")
        XCTAssertGreaterThan(AccessibilityBridge.pasteDelayNs, 0,
            "pasteDelayNs must be non-zero (COMPAT-03)")
        XCTAssertGreaterThan(AccessibilityBridge.clipboardRestoreDelayNs, 0,
            "clipboardRestoreDelayNs must be non-zero (COMPAT-03)")
    }
}
