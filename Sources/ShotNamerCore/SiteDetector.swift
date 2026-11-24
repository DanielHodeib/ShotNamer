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

    // MARK: - Fallbacks for screenshots without a visible address bar

    /// Big sites whose name is distinctive. Used only for an exact title ("GitHub") or an exact header line.
    static let brands: [String: String] = [
        "github": "github.com", "gitlab": "gitlab.com", "youtube": "youtube.com", "google": "google.com",
        "wikipedia": "wikipedia.org", "reddit": "reddit.com", "stackoverflow": "stackoverflow.com",
        "linkedin": "linkedin.com", "twitter": "twitter.com", "facebook": "facebook.com", "instagram": "instagram.com",
        "netflix": "netflix.com", "spotify": "spotify.com", "amazon": "amazon.com", "ebay": "ebay.com",
        "notion": "notion.so", "figma": "figma.com", "slack": "slack.com", "discord": "discord.com",
        "chatgpt": "chatgpt.com", "claude": "claude.ai", "perplexity": "perplexity.ai", "medium": "medium.com",
        "twitch": "twitch.tv", "pinterest": "pinterest.com", "dropbox": "dropbox.com", "trello": "trello.com",
        "hackernews": "ycombinator.com",
    ]

    private static func key(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }

    /// Site name from a window title ("Meine Anzeigen | willhaben" → "willhaben"), but only with evidence:
    /// the last segment must also appear as a header/logo line in the top quarter of the image, or the whole
    /// title must be a well-known site ("GitHub"). Otherwise a title like "Home - Docs" would invent a site.
    public static func fromTitle(_ title: String, lines: [TextLine]) -> String? {
        if let d = brands[key(title)] { return d }
        // Separators need spaces around them, so "E-Mail" is not split.
        let parts = title.replacingOccurrences(of: #"\s[|–—·-]\s"#, with: "\u{1}", options: .regularExpression)
            .components(separatedBy: "\u{1}").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard parts.count >= 2, let name = parts.last, (3...25).contains(name.count),
              name.split(separator: " ").count <= 2 else { return nil }
        if let d = brands[key(name)] { return d }
        let k = key(name)
        let confirmed = lines.contains { $0.y > 0.75 && key($0.text) == k }
        return confirmed ? name.lowercased() : nil
    }

    /// A header line that is exactly a well-known site's name ("GitHub", "YouTube") near the top of the image.
    /// Experimental: a page that merely has such a line can be misread, so it is opt-in.
    public static func brandHeader(in lines: [TextLine]) -> String? {
        for line in lines.sorted(by: { $0.y > $1.y }) where line.y > 0.85 {
            if let d = brands[key(line.text)] { return d }
        }
        return nil
    }

    /// Domain of a URL ("https://docs.github.com/x" → "github.com"); nil for non-web URLs.
    public static func domain(ofURL string: String) -> String? {
        guard let url = URL(string: string), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, host.contains(".") else { return nil }
        return registrable(host)
    }
}
