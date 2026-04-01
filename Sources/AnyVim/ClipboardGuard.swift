import AppKit

/// Snapshot type — deep-copied pasteboard content (per D-05: ALL items, ALL types).
/// Each element is one NSPasteboardItem's data, keyed by pasteboard type.
typealias ClipboardSnapshot = [[NSPasteboard.PasteboardType: Data]]

/// Guards the clipboard across an edit cycle.
/// Snapshots all pasteboard items eagerly (deep copy) and restores them exactly.
struct ClipboardGuard {
    private let pasteboard: PasteboardAccessing

    init(pasteboard: PasteboardAccessing = SystemPasteboard()) {
        self.pasteboard = pasteboard
    }

    /// Deep-copy all pasteboard items and their data. Per RESEARCH.md Pitfall 1:
    /// NSPasteboardItem lazy data providers become invalid after clearContents().
    /// Must call item.data(forType:) for every type immediately.
    func snapshot() -> ClipboardSnapshot {
        guard let items = pasteboard.pasteboardItems() else { return [] }
        return items.map { item in
            var typeData: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    typeData[type] = data
                }
            }
            return typeData
        }
    }

    /// Restore a previously snapshotted clipboard state.
    func restore(_ snapshot: ClipboardSnapshot) {
        pasteboard.clearContents()
        guard !snapshot.isEmpty else { return }
        let items = snapshot.map { typeData -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in typeData {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(items)
    }
}
