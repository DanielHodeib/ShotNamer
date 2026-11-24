import Foundation

/// Where a renamed screenshot is filed, relative to the destination root.
public enum SortMode: String, CaseIterable, Identifiable {
    case off, month, source, monthSource
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .off: "Don't sort (keep in the screenshot folder)"
        case .month: "By month  (2026-11)"
        case .source: "By website or app  (github.com)"
        case .monthSource: "By month, then website or app  (2026-11/github.com)"
        }
    }

    var folderTemplate: String? {
        switch self {
        case .off: nil
        case .month: "{year}-{month}"
        case .source: "{where}"
        case .monthSource: "{year}-{month}/{where}"
        }
    }

    /// Relative folder path ("2026-11/github.com"), or "" when not sorting. Parts can never contain "/" or ":".
    public func subpath(date: Date, app: String?, site: String?, timeZone: TimeZone = .current) -> String {
        guard let template = folderTemplate else { return "" }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month], from: date)
        let origin = FileNamer.sanitize(site ?? app ?? "", maxLength: 40)
        let values = ["year": String(c.year ?? 0), "month": String(format: "%02d", c.month ?? 0),
                      "where": origin.isEmpty ? "Other" : origin]
        return template.split(separator: "/").map { Template.render(String($0), values: values) }
            .filter { !$0.isEmpty }.joined(separator: "/")
    }
}
