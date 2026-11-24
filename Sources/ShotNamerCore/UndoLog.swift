import Foundation

/// Persistent list of renames so any of them can be undone. Stored as one small JSON file.
public final class UndoLog {
    public struct Record: Codable, Equatable {
        public let from: String
        public let to: String
        public let date: Date
        /// Folders the rename created (outermost first); removed on undo if they are empty again. Optional: absent in 0.1 logs.
        public let createdDirs: [String]?
        /// Unredacted original, restored on undo. Optional: absent in older logs and when nothing was redacted.
        public let backup: String?
        public init(from: String, to: String, date: Date, createdDirs: [String]? = nil, backup: String? = nil) {
            self.from = from; self.to = to; self.date = date; self.createdDirs = createdDirs; self.backup = backup
        }
    }

    private let url: URL
    private let limit = 500
    private let lock = NSLock()

    public init(url: URL) { self.url = url }

    public func all() -> [Record] {
        lock.lock(); defer { lock.unlock() }
        return load()
    }

    public func append(_ r: Record) throws {
        lock.lock(); defer { lock.unlock() }
        try save(Array((load() + [r]).suffix(limit)))
    }

    public func popLast() throws -> Record? {
        lock.lock(); defer { lock.unlock() }
        var records = load()
        guard let last = records.popLast() else { return nil }
        try save(records)
        return last
    }

    /// Removes `r` (the newest matching record); a rename logged meanwhile is kept.
    public func remove(_ r: Record) throws {
        lock.lock(); defer { lock.unlock() }
        var records = load()
        guard let i = records.lastIndex(of: r) else { return }
        records.remove(at: i)
        try save(records)
    }

    private func load() -> [Record] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        if let records = try? d.decode([Record].self, from: data) { return records }
        // Unreadable (corrupt or newer format): keep a copy so the next save does not destroy it.
        // Timestamped: a fixed ".bak" name would make the copy fail (and the log be lost) the second time.
        try? FileManager.default.copyItem(at: url, to: url.appendingPathExtension("\(Int(Date().timeIntervalSince1970)).bak"))
        return []
    }

    private func save(_ records: [Record]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        try e.encode(records).write(to: url, options: .atomic)
    }
}
