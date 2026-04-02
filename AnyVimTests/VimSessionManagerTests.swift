import XCTest
@testable import AnyVim

// MARK: - MockVimPathResolver

/// Mock implementation of VimPathResolving — returns a configurable path or nil.
final class MockVimPathResolver: VimPathResolving {
    var pathToReturn: String?

    func resolveVimPath() -> String? {
        return pathToReturn
    }
}

// MARK: - MockFileModificationDateReader

/// Mock implementation of FileModificationDateReading — returns configurable dates.
final class MockFileModificationDateReader: FileModificationDateReading {
    /// Sequence of dates to return on successive calls. If empty, returns nil.
    var datesToReturn: [Date?] = []
    private var callIndex = 0

    func modificationDate(of url: URL) -> Date? {
        guard callIndex < datesToReturn.count else { return nil }
        let date = datesToReturn[callIndex]
        callIndex += 1
        return date
    }
}

// MARK: - VimSessionManagerTests

@MainActor
final class VimSessionManagerTests: XCTestCase {

    // MARK: - FileModificationDateReading production tests

    func testModificationDateReturnsDateForExistingFile() throws {
        // Create a real temp file
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("testModDate_\(UUID().uuidString).txt")
        try "test content".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let reader = SystemFileModificationDateReader()
        let date = reader.modificationDate(of: url)

        XCTAssertNotNil(date, "modificationDate should return a non-nil Date for an existing file")
    }

    func testModificationDateReturnsNilForMissingFile() {
        let url = URL(fileURLWithPath: "/tmp/nonexistent_\(UUID().uuidString).txt")
        let reader = SystemFileModificationDateReader()
        let date = reader.modificationDate(of: url)

        XCTAssertNil(date, "modificationDate should return nil for a non-existent file")
    }

    // MARK: - Mtime-based exit detection logic

    func testExitResultSavedWhenMtimeChanges() {
        // Different dates = file was written = .saved
        let before = Date(timeIntervalSince1970: 1000)
        let after = Date(timeIntervalSince1970: 2000)

        let result = VimExitResult.from(mtimeBefore: before, mtimeAfter: after)

        XCTAssertEqual(result, .saved, "VimExitResult should be .saved when mtime changes")
    }

    func testExitResultAbortedWhenMtimeUnchanged() {
        // Same date = file was NOT written = .aborted
        let date = Date(timeIntervalSince1970: 1000)

        let result = VimExitResult.from(mtimeBefore: date, mtimeAfter: date)

        XCTAssertEqual(result, .aborted, "VimExitResult should be .aborted when mtime is unchanged")
    }

    func testExitResultAbortedWhenMtimeAfterIsNil() {
        // Nil after = file disappeared or unreadable = treat as aborted
        let before = Date(timeIntervalSince1970: 1000)

        let result = VimExitResult.from(mtimeBefore: before, mtimeAfter: nil)

        XCTAssertEqual(result, .aborted, "VimExitResult should be .aborted when mtimeAfter is nil")
    }

    func testExitResultAbortedWhenMtimeBeforeIsNil() {
        // Nil before (file didn't exist) = treat as aborted
        let after = Date(timeIntervalSince1970: 2000)

        let result = VimExitResult.from(mtimeBefore: nil, mtimeAfter: after)

        XCTAssertEqual(result, .aborted, "VimExitResult should be .aborted when mtimeBefore is nil")
    }

    // MARK: - Vim path resolution (integration test)

    func testResolveVimPathFindsVim() {
        let resolver = ShellVimPathResolver()
        let path = resolver.resolveVimPath()

        XCTAssertNotNil(path, "resolveVimPath() should return a non-nil path (system vim exists)")
        if let path = path {
            XCTAssertTrue(path.contains("vim"), "Resolved path should contain 'vim', got: \(path)")
        }
    }

    // MARK: - VimSessionManager initialization

    func testVimSessionManagerInitializesWithMockDependencies() {
        let mockResolver = MockVimPathResolver()
        mockResolver.pathToReturn = "/usr/bin/vim"
        let mockReader = MockFileModificationDateReader()

        // Should compile and initialize without crash
        let manager = VimSessionManager(
            vimPathResolver: mockResolver,
            fileModDateReader: mockReader
        )

        XCTAssertNotNil(manager, "VimSessionManager should initialize with mock dependencies")
    }

    // MARK: - UserDefaultsVimPathResolver tests

    func testUserDefaultsVimPathResolverReturnsCustomPathWhenExecutable() throws {
        let suiteName = "test-\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: suiteName)!
        defer { testDefaults.removePersistentDomain(forName: suiteName) }

        // Create a real executable temp file
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("testvim-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: tempURL.path, contents: Data("#!/bin/sh".utf8))
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Set executable permission (0o755)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempURL.path)

        let fallback = MockVimPathResolver()
        fallback.pathToReturn = "/usr/bin/vim"
        testDefaults.set(tempURL.path, forKey: "customVimPath")

        let resolver = UserDefaultsVimPathResolver(
            fallback: fallback,
            defaults: testDefaults,
            key: "customVimPath"
        )

        XCTAssertEqual(resolver.resolveVimPath(), tempURL.path,
            "Should return custom executable path from UserDefaults")
    }

    func testUserDefaultsVimPathResolverFallsBackWhenCustomPathNotExecutable() {
        let suiteName = "test-\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: suiteName)!
        defer { testDefaults.removePersistentDomain(forName: suiteName) }

        let fallback = MockVimPathResolver()
        fallback.pathToReturn = "/usr/bin/vim"
        testDefaults.set("/nonexistent/path/vim", forKey: "customVimPath")

        let resolver = UserDefaultsVimPathResolver(
            fallback: fallback,
            defaults: testDefaults,
            key: "customVimPath"
        )

        XCTAssertEqual(resolver.resolveVimPath(), "/usr/bin/vim",
            "Should fall back to ShellVimPathResolver when custom path is not executable")
    }

    func testUserDefaultsVimPathResolverFallsBackWhenNoCustomPath() {
        let suiteName = "test-\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: suiteName)!
        defer { testDefaults.removePersistentDomain(forName: suiteName) }

        let fallback = MockVimPathResolver()
        fallback.pathToReturn = "/usr/bin/vim"

        let resolver = UserDefaultsVimPathResolver(
            fallback: fallback,
            defaults: testDefaults,
            key: "customVimPath"
        )

        XCTAssertEqual(resolver.resolveVimPath(), "/usr/bin/vim",
            "Should fall back when no custom path is set in UserDefaults")
    }

    func testUserDefaultsVimPathResolverFallsBackWhenCustomPathIsEmpty() {
        let suiteName = "test-\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: suiteName)!
        defer { testDefaults.removePersistentDomain(forName: suiteName) }

        let fallback = MockVimPathResolver()
        fallback.pathToReturn = "/usr/bin/vim"
        testDefaults.set("", forKey: "customVimPath")

        let resolver = UserDefaultsVimPathResolver(
            fallback: fallback,
            defaults: testDefaults,
            key: "customVimPath"
        )

        XCTAssertEqual(resolver.resolveVimPath(), "/usr/bin/vim",
            "Should fall back when custom path is empty string")
    }

    // MARK: - openVimSession returns .aborted when vim not found (D-09 path)

    func testOpenVimSessionReturnsAbortedWhenVimNotFound() async {
        let mockResolver = MockVimPathResolver()
        mockResolver.pathToReturn = nil  // Simulate vim not found

        let mockReader = MockFileModificationDateReader()
        // No dates needed — should bail early without checking mtime

        let manager = VimSessionManager(
            vimPathResolver: mockResolver,
            fileModDateReader: mockReader,
            showAlerts: false  // suppress modal NSAlert in unit tests
        )

        // Create a temp file (even though we won't use it — manager returns early)
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("testVimNotFound_\(UUID().uuidString).txt")
        try? "content".write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let result = await manager.openVimSession(tempFileURL: tempURL)

        XCTAssertEqual(result, .aborted, "openVimSession should return .aborted when vim is not found in PATH")
    }
}
