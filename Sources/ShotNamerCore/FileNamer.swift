import Foundation

/// Pure helpers: decide what is a screenshot, when it was taken, and what to call it.
public enum FileNamer {
    /// Default macOS screenshot prefixes (localized). Renamed files start with a date, so they never match.
    static let prefixes = [
        "Screenshot", "Screen Shot", "Bildschirmfoto", "Capture d’écran", "Capture d'écran",
        "Captura de pantalla", "Schermafbeelding", "Istantanea schermo",
    ]
    // Screen recordings (.mov) are deliberately not handled.
    static let extensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff"]

    /// Screenshot or screen recording.
    public static func isCapture(filename: String) -> Bool { isScreenshot(filename: filename) }

    public static func isScreenshot(filename: String) -> Bool {
        guard !filename.hasPrefix(".") else { return false }
        let ext = (filename as NSString).pathExtension.lowercased()
        return extensions.contains(ext) && prefixes.contains { filename.hasPrefix($0) }
    }

    /// Capture time from the filename ("Screenshot 2026-11-24 at 2.32.10 PM.png",
    /// "Bildschirmfoto 2026-11-24 um 14.32.10.png"). Works for any locale; nil if no match.
    /// The file's own creation date can lag the shutter by seconds (floating thumbnail).
    public static func captureDate(fromFilename name: String, timeZone: TimeZone = .current) -> Date? {
        let pattern = #/(\d{4})-(\d{2})-(\d{2})\D+?(\d{1,2})[.:](\d{2})[.:](\d{2})\s*(AM|PM|am|pm)?/#
        guard let m = name.firstMatch(of: pattern) else { return nil }
        var comps = DateComponents()
        comps.timeZone = timeZone
        comps.year = Int(m.1); comps.month = Int(m.2); comps.day = Int(m.3)
        var hour = Int(m.4) ?? 0
        if let ampm = m.7?.lowercased() {
            hour = hour % 12 + (ampm == "pm" ? 12 : 0)
        }
        comps.hour = hour; comps.minute = Int(m.5); comps.second = Int(m.6)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal.date(from: comps)
    }

    /// Strip characters that are illegal or ugly in filenames, collapse spaces, cap the length.
    public static func sanitize(_ s: String, maxLength: Int = 50) -> String {
        let bad = CharacterSet(charactersIn: "/:\\").union(.controlCharacters).union(.newlines)
        var out = ""
        for u in s.unicodeScalars { out.unicodeScalars.append(bad.contains(u) ? " " : u) }
        out = out.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if out.count > maxLength { out = String(out.prefix(maxLength)) }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    }

    /// "2026-11-24 14.32.10 - Safari - github.com - Page title.png" with the default template.
    public static func makeName(date: Date, app: String?, site: String? = nil, text: String?, ext: String,
                                template: String = Template.defaultName, timeZone: TimeZone = .current) -> String {
        let d = DateFormatter(); d.locale = Locale(identifier: "en_US_POSIX"); d.timeZone = timeZone
        d.dateFormat = "yyyy-MM-dd"
        let t = DateFormatter(); t.locale = d.locale; t.timeZone = timeZone; t.dateFormat = "HH.mm.ss"
        let values = [
            "date": d.string(from: date), "time": t.string(from: date),
            "app": sanitize(app ?? "", maxLength: 30), "site": sanitize(site ?? "", maxLength: 40),
            "title": sanitize(text ?? ""),
        ]
        var name = Template.render(Template.isValidName(template) ? template : Template.defaultName, values: values)
        name = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: ".")
        return name + "." + ext
    }

    /// `name`, or `name 2`, `name 3` … if the file already exists in `dir`.
    public static func uniqueURL(in dir: URL, name: String, fileManager fm: FileManager = .default) -> URL {
        var url = dir.appendingPathComponent(name)
        guard fm.fileExists(atPath: url.path) else { return url }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var n = 2
        repeat {
            url = dir.appendingPathComponent("\(base) \(n).\(ext)")
            n += 1
        } while fm.fileExists(atPath: url.path)
        return url
    }
}
