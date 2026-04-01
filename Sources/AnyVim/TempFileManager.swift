import Foundation

/// Manages temp files for the edit cycle (D-11).
/// Files go in NSTemporaryDirectory() with UUID-based naming.
struct TempFileManager {

    /// Create a temp file with the given content. Returns the file URL.
    /// Empty content is valid (CAPT-04: empty field produces empty file).
    func createTempFile(content: String) throws -> URL {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        let fileName = "anyvim-\(UUID().uuidString).txt"
        let fileURL = tempDir.appendingPathComponent(fileName)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    /// Delete a temp file. Best-effort — does not throw if file is missing.
    func deleteTempFile(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
