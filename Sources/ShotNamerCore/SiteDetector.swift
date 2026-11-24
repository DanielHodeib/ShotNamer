import Foundation

/// Finds the website a browser screenshot shows, from the address bar text the OCR read.
public enum SiteDetector {
    static let browsers = ["Safari", "Brave", "Chrome", "Chromium", "Firefox", "Arc", "Edge", "Opera",
                           "Vivaldi", "Orion", "DuckDuckGo", "Zen", "Tor Browser"]

    /// Only browsers are scanned: in other apps a visible domain (an e-mail address, a log line) says nothing about the source.
    public static func isBrowser(_ app: String?) -> Bool {
        guard let app else { return false }
        return browsers.contains { app.localizedCaseInsensitiveContains($0) }
    }

    // Restricted TLD list keeps "Node.js", "file.png" or "13.797.610" from matching.
    private static let tlds = "com|org|net|io|dev|app|ai|tv|xyz|info|edu|gov|cloud|tech|at|de|ch|eu|uk|fr|es|nl|ca|pl|se|dk|fi|cz|hu|jp|cn|br"
    private static let pattern = try! NSRegularExpression(
        pattern: #"(?<![@\w.-])((?:[a-z0-9-]+\.)+(?:\#(tlds)))(?![\w-])"#, options: .caseInsensitive)

    /// "willhaben.at/iad/myprofile" → "willhaben.at". A match in the top strip (address bar) wins;
    /// otherwise the most frequent domain in the image.
    public static func domain(in lines: [TextLine]) -> String? {
        var top: [(domain: String, y: Double)] = []
        var counts: [String: Int] = [:]
        var order: [String] = []
        for line in lines {
            let ns = line.text as NSString
            for m in pattern.matches(in: line.text, range: NSRange(location: 0, length: ns.length)) {
                let d = registrable(ns.substring(with: m.range(at: 1)))
                if line.y > 0.8 { top.append((d, line.y)) }
                if counts[d] == nil { order.append(d) }
                counts[d, default: 0] += 1
            }
        }
        if let best = top.max(by: { $0.y < $1.y }) { return best.domain }
        return order.max { counts[$0]! < counts[$1]! } // ties: max keeps the later one; fine, rare
    }

    /// "docs.github.com" → "github.com"; "www.bbc.co.uk" → "bbc.co.uk".
    static func registrable(_ host: String) -> String {
        var labels = host.lowercased().split(separator: ".").map(String.init)
        if labels.first == "www" { labels.removeFirst() }
        let keep = (labels.count >= 3 && labels.last!.count == 2 && ["co", "com", "org", "ac", "gov"].contains(labels[labels.count - 2])) ? 3 : 2
        return labels.suffix(keep).joined(separator: ".")
    }

    /// A window title that only repeats the site ("GitHub" on github.com) adds nothing.
    public static func isRedundant(title: String, site: String) -> Bool {
        let t = title.lowercased().trimmingCharacters(in: .whitespaces)
        return t == site || t == site.split(separator: ".").first.map(String.init)
    }
}
