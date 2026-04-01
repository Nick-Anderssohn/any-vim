import XCTest
@testable import AnyVim

// MARK: - TempFileManagerTests

final class TempFileManagerTests: XCTestCase {

    private var manager: TempFileManager!
    private var createdURLs: [URL] = []

    override func setUp() {
        super.setUp()
        manager = TempFileManager()
        createdURLs = []
    }

    override func tearDown() {
        // Clean up any files created during tests
        for url in createdURLs {
            try? FileManager.default.removeItem(at: url)
        }
        createdURLs = []
        manager = nil
        super.tearDown()
    }

    // Helper to track created files for cleanup
    private func createAndTrack(content: String) throws -> URL {
        let url = try manager.createTempFile(content: content)
        createdURLs.append(url)
        return url
    }

    // MARK: - Tests

    func testCreateTempFileWithContent() throws {
        let content = "hello world"
        let url = try createAndTrack(content: content)

        let readBack = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(readBack, content, "File content should match input string")
    }

    func testCreateTempFileEmpty() throws {
        let url = try createAndTrack(content: "")

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Empty file should exist on disk")
        let readBack = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(readBack, "", "Empty content should produce a file with empty content (CAPT-04)")
    }

    func testTempFileNamePattern() throws {
        let url = try createAndTrack(content: "pattern test")

        let fileName = url.lastPathComponent
        XCTAssertTrue(fileName.hasPrefix("anyvim-"), "Filename should start with 'anyvim-'")
        XCTAssertTrue(fileName.hasSuffix(".txt"), "Filename should end with '.txt'")
    }

    func testTempFileExistsOnDisk() throws {
        let url = try createAndTrack(content: "existence check")

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Created file should exist on disk")
    }

    func testDeleteTempFile() throws {
        let url = try createAndTrack(content: "to be deleted")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        manager.deleteTempFile(at: url)

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "File should no longer exist after deletion")
    }

    func testDeleteNonExistentFile() {
        let bogusURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("anyvim-nonexistent-\(UUID().uuidString).txt")

        // Should not crash or throw
        manager.deleteTempFile(at: bogusURL)
    }

    func testMultipleFilesUniqueNames() throws {
        let url1 = try createAndTrack(content: "first")
        let url2 = try createAndTrack(content: "second")

        XCTAssertNotEqual(url1, url2, "Each temp file should have a unique path")
        XCTAssertNotEqual(url1.lastPathComponent, url2.lastPathComponent, "Each temp file should have a unique filename")
    }
}
