import XCTest
@testable import AnyVim

// MARK: - MockPasteboard

/// Mock pasteboard for unit testing ClipboardGuard without touching the real system clipboard.
final class MockPasteboard: PasteboardAccessing {

    var changeCount: Int = 0

    /// Items returned by pasteboardItems(). nil simulates an empty/uninitialized pasteboard.
    var items: [NSPasteboardItem]?

    var clearContentsCalled = false
    var writtenItems: [NSPasteboardItem] = []
    var setStringCalled = false

    func pasteboardItems() -> [NSPasteboardItem]? {
        return items
    }

    func stringForType(_ type: NSPasteboard.PasteboardType) -> String? {
        return nil
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
        let item = NSPasteboardItem()
        item.setString(string, forType: type)
        self.items = [item]
    }
}

// MARK: - ClipboardGuardTests

@MainActor
final class ClipboardGuardTests: XCTestCase {

    private var mockPasteboard: MockPasteboard!
    private var guard_: ClipboardGuard!

    override func setUp() {
        super.setUp()
        mockPasteboard = MockPasteboard()
        guard_ = ClipboardGuard(pasteboard: mockPasteboard)
    }

    override func tearDown() {
        guard_ = nil
        mockPasteboard = nil
        super.tearDown()
    }

    // MARK: - Snapshot tests

    func testSnapshotEmptyPasteboard() {
        // nil items = empty/uninitialized pasteboard
        mockPasteboard.items = nil

        let snapshot = guard_.snapshot()

        XCTAssertEqual(snapshot.count, 0, "Snapshot of nil items should return empty array")
    }

    func testSnapshotSinglePlainTextItem() {
        let item = NSPasteboardItem()
        let testString = "hello"
        item.setString(testString, forType: .string)
        mockPasteboard.items = [item]

        let snapshot = guard_.snapshot()

        XCTAssertEqual(snapshot.count, 1, "Should snapshot one item")
        let typeData = snapshot[0]
        XCTAssertNotNil(typeData[.string], "Snapshot should capture .string type")
        let capturedString = String(data: typeData[.string]!, encoding: .utf8)
        XCTAssertEqual(capturedString, testString, "Captured data should match original string")
    }

    func testSnapshotMultiTypeItem() {
        let item = NSPasteboardItem()
        item.setString("plain text", forType: .string)
        // Use a custom type to simulate a secondary type without needing real RTF data
        let customType = NSPasteboard.PasteboardType("com.test.custom")
        item.setData("rtf-like".data(using: .utf8)!, forType: customType)
        mockPasteboard.items = [item]

        let snapshot = guard_.snapshot()

        XCTAssertEqual(snapshot.count, 1)
        let typeData = snapshot[0]
        XCTAssertNotNil(typeData[.string], "Should capture .string type")
        XCTAssertNotNil(typeData[customType], "Should capture custom type")
    }

    func testSnapshotMultipleItems() {
        let item1 = NSPasteboardItem()
        item1.setString("first", forType: .string)
        let item2 = NSPasteboardItem()
        item2.setString("second", forType: .string)
        mockPasteboard.items = [item1, item2]

        let snapshot = guard_.snapshot()

        XCTAssertEqual(snapshot.count, 2, "Should snapshot all items")
    }

    // MARK: - Restore tests

    func testRestoreWritesItems() {
        // Build a snapshot manually
        let item = NSPasteboardItem()
        item.setString("test content", forType: .string)
        mockPasteboard.items = [item]
        let snapshot = guard_.snapshot()

        // Reset mock state
        mockPasteboard.clearContentsCalled = false
        mockPasteboard.writtenItems = []

        guard_.restore(snapshot)

        XCTAssertTrue(mockPasteboard.clearContentsCalled, "restore() should call clearContents()")
        XCTAssertFalse(mockPasteboard.writtenItems.isEmpty, "restore() should write items back")
    }

    func testRestoreEmptySnapshot() {
        guard_.restore([])

        XCTAssertTrue(mockPasteboard.clearContentsCalled, "restore([]) should still call clearContents()")
        XCTAssertTrue(mockPasteboard.writtenItems.isEmpty, "restore([]) should not write any items")
    }
}
