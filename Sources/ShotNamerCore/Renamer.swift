import Foundation

public enum Renamer {
    /// Where macOS saves screenshots: the `com.apple.screencapture location` pref, else ~/Desktop.
    public static func screenshotFolder() -> URL {
        if let p = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") {
            return URL(fileURLWithPath: (p as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
    }

    /// Shutter time: parsed from the filename, else the file's creation date, else now.
    public static func captureDate(of url: URL) -> Date {
        if let d = FileNamer.captureDate(fromFilename: url.lastPathComponent) { return d }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.creationDate] as? Date) ?? Date()
    }

    /// Renames `url` in place and logs it for undo. Returns the new URL.
    @discardableResult
    public static func rename(_ url: URL, date: Date, app: String?, title: String? = nil, useOCR: Bool, log: UndoLog,
                              ocr: (URL) -> String? = TextRecognizer.headline) throws -> URL {
        // Window title is far more meaningful than OCR; OCR only fills in when there is no title.
        let text = title.flatMap { $0.isEmpty ? nil : $0 } ?? (useOCR ? ocr(url) : nil)
        let name = FileNamer.makeName(date: date, app: app, text: text, ext: url.pathExtension.lowercased())
        let dest = FileNamer.uniqueURL(in: url.deletingLastPathComponent(), name: name)
        try FileManager.default.moveItem(at: url, to: dest)
        try log.append(.init(from: url.path, to: dest.path, date: Date()))
        return dest
    }

    /// Reverts the most recent rename. Returns the restored URL, or nil if the log is empty.
    /// If the renamed file is gone or the old name is taken, the entry is dropped and an error thrown.
    @discardableResult
    public static func undoLast(log: UndoLog) throws -> URL? {
        guard let r = try log.popLast() else { return nil }
        let fm = FileManager.default
        guard fm.fileExists(atPath: r.to) else { throw CocoaError(.fileNoSuchFile) }
        guard !fm.fileExists(atPath: r.from) else { throw CocoaError(.fileWriteFileExists) }
        try fm.moveItem(atPath: r.to, toPath: r.from)
        return URL(fileURLWithPath: r.from)
    }
}
