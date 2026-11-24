import Foundation

/// Persistent list of renames so any of them can be undone. Stored as one small JSON file.
public final class UndoLog {
    public struct Record: Codable, Equatable {
        public let from: String
        public let to: String
        public let date: Date
        public init(from: String, to: String, date: Date) { self.from = from; self.to = to; self.date = date }
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

    private func load() -> [Record] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        if let records = try? d.decode([Record].self, from: data) { return records }
        // Unreadable (corrupt or newer format): keep a copy so the next save does not destroy it.
        try? FileManager.default.copyItem(at: url, to: url.appendingPathExtension("bak"))
        return []
    }

    private func save(_ records: [Record]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        try e.encode(records).write(to: url, options: .atomic)
    }
}
