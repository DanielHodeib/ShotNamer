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
    public static func rename(_ url: URL, date: Date, app: String?, title: String? = nil,
                              useSite: Bool = false, useOCR: Bool, template: String = Template.defaultName,
                              sort: SortMode = .off, sortRoot: URL? = nil, searchable: Bool = false, redact: Bool = false, backupDir: URL? = nil,
                              onRedacted: (([String]) -> Void)? = nil, log: UndoLog,
                              recognize: (URL) -> [TextLine] = TextRecognizer.lines) throws -> URL {
        var title = title.flatMap { $0.isEmpty ? nil : $0 }
        let wantSite = useSite && SiteDetector.isBrowser(app)
        // One OCR pass serves the site, the headline fallback, the Spotlight text and redaction.
        let rawLines = (wantSite || searchable || redact || (useOCR && title == nil)) ? recognize(url) : []
        var lines = rawLines
        var backupPath: String?

        if redact {
            // Nothing sensitive may reach the file name or the Spotlight comment, even where it could not be blacked out.
            lines = rawLines.map { TextLine(text: SensitiveDetector.scrub($0.text), y: $0.y, height: $0.height, rect: $0.rect) }
            if let t = title, SensitiveDetector.contains(t) { title = nil }
            let regions = FileNamer.isVideo(url) ? [] : Redactor.regions(in: rawLines) // videos are not redacted
            if !regions.isEmpty {
                guard let backupDir else { throw CocoaError(.fileWriteUnknown) } // never redact without a backup
                try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
                let backup = backupDir.appendingPathComponent("\(UUID().uuidString)-\(url.lastPathComponent)")
                try FileManager.default.copyItem(at: url, to: backup)
                do { try Redactor.blackOut(url, regions: regions) } catch {
                    try? FileManager.default.removeItem(at: backup) // original untouched, so no backup needed
                    throw error
                }
                backupPath = backup.path
                onRedacted?(Array(Set(regions.map(\.kind))).sorted())
            }
        }

        let site = wantSite ? SiteDetector.domain(in: lines) : nil
        var text = title
        if let t = title, let s = site, SiteDetector.isRedundant(title: t, site: s) { text = nil }
        if title == nil && useOCR { text = TextRecognizer.headline(from: lines) }
        let name = FileNamer.makeName(date: date, app: app, site: site, text: text,
                                     ext: url.pathExtension.lowercased(), template: template)
        let fm = FileManager.default
        var folder = sortRoot ?? url.deletingLastPathComponent()
        let sub = sort.subpath(date: date, app: app, site: site)
        if !sub.isEmpty { folder.appendPathComponent(sub, isDirectory: true) }
        var created: [String] = [] // folders that do not exist yet, outermost first
        var probe = folder
        while !fm.fileExists(atPath: probe.path) { created.insert(probe.path, at: 0); probe.deleteLastPathComponent() }
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let dest = FileNamer.uniqueURL(in: folder, name: name)
        try fm.moveItem(at: url, to: dest)
        if searchable && !FileNamer.isVideo(dest) { try? SearchIndex.write(SearchIndex.comment(from: lines), to: dest) } // best effort: never fail the rename
        try log.append(.init(from: url.path, to: dest.path, date: Date(), createdDirs: created.isEmpty ? nil : created, backup: backupPath))
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
        if let b = r.backup, fm.fileExists(atPath: b) { // put the unredacted original back
            _ = try fm.replaceItemAt(URL(fileURLWithPath: r.from), withItemAt: URL(fileURLWithPath: b))
        }
        for dir in (r.createdDirs ?? []).reversed() { // innermost first; only if now empty (rmdir refuses otherwise)
            rmdir(dir)
        }
        return URL(fileURLWithPath: r.from)
    }
}
