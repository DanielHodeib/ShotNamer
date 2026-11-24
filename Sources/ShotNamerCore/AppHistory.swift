import Foundation

/// Which app was frontmost at a given moment. Fed by app-activation events.
public struct AppHistory {
    struct Entry { let date: Date; let name: String }
    private var entries: [Entry] = []
    private let capacity: Int

    public init(capacity: Int = 200) { self.capacity = capacity }

    public mutating func record(name: String, at date: Date) {
        entries.append(Entry(date: date, name: name))
        if entries.count > capacity { entries.removeFirst(entries.count - capacity) }
    }

    /// App that was frontmost at `date`, or nil if `date` predates all records.
    public func app(at date: Date) -> String? {
        entries.last(where: { $0.date <= date })?.name
    }
}
