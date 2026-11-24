import Foundation

/// "{date} {time} - {app} - {site} - {title}" style templates, used for file names and sort folders.
public enum Template {
    public static let defaultName = "{date} {time} - {app} - {site} - {title}"
    public static let nameTokens = ["date", "time", "app", "site", "title"]

    private static let token = try! NSRegularExpression(pattern: #"\{(\w+)\}"#)

    /// Fills the template. A token with an empty value disappears together with the separator before it,
    /// so a missing site gives "date - app - title", not "date - app -  - title".
    public static func render(_ template: String, values: [String: String]) -> String {
        var out = "", pending = ""
        var first = true, emitted = false
        var cursor = template.startIndex
        let ns = template as NSString
        for m in token.matches(in: template, range: NSRange(location: 0, length: ns.length)) {
            let r = Range(m.range, in: template)!
            pending += template[cursor..<r.lowerBound]
            cursor = r.upperBound
            guard let value = values[ns.substring(with: m.range(at: 1))] else {
                pending += template[r] // unknown {token} stays as typed
                continue
            }
            if first { out += pending; pending = ""; first = false } // the template's own prefix ("Shot ") always stays
            if value.isEmpty { pending = ""; continue } // drop the separator before an empty value
            if emitted { out += pending } // no separator before the first value
            out += value
            pending = ""
            emitted = true
        }
        if emitted { out += pending + template[cursor...] } // trailing text, e.g. " (shot)"
        return out
    }

    /// A name template is usable if it makes names that are unique in time and never look like a fresh screenshot
    /// (otherwise the app would rename its own output forever).
    public static func isValidName(_ template: String) -> Bool {
        guard template.contains("{date}") || template.contains("{time}") else { return false }
        let sample = render(template, values: ["date": "2026-11-24", "time": "14.32.10", "app": "Safari", "site": "github.com", "title": "x"])
        let bare = render(template, values: ["date": "2026-11-24", "time": "14.32.10", "app": "", "site": "", "title": ""])
        return ![sample, bare].contains { FileNamer.isScreenshot(filename: $0 + ".png") || FileNamer.isCapture(filename: $0 + ".mov") }
    }
}
