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
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let created = attrs?[.creationDate] as? Date
        guard let d = FileNamer.captureDate(fromFilename: url.lastPathComponent) else { return created ?? Date() }
        // More than 30 min apart: a 12-hour suffix we can't read ("p. m.") or a changed time zone. The file knows better.
        if let created, abs(created.timeIntervalSince(d)) > 1800 { return created }
        return d
    }

    /// Renames `url` in place and logs it for undo. Returns the new URL.
    @discardableResult
    public static func rename(_ url: URL, date: Date, app: String?, title: String? = nil,
                              useSite: Bool = false, useOCR: Bool, template: String = Template.defaultName,
                              sort: SortMode = .off, sortRoot: URL? = nil, searchable: Bool = false, redact: Bool = false, backupDir: URL? = nil,
                              onRedacted: (([String]) -> Void)? = nil,
                              knownSite: String? = nil, textSites: Bool = false, log: UndoLog,
                              recognize: (URL) -> [TextLine] = TextRecognizer.lines) throws -> URL {
        var title = title.flatMap { $0.isEmpty ? nil : $0 }
        let wantSite = useSite && SiteDetector.isBrowser(app)
        // One OCR pass serves the site, the headline fallback, the Spotlight text and redaction.
        let allLines = (wantSite || searchable || redact || (useOCR && title == nil)) ? recognize(url) : []
        let rawLines = allLines.filter { $0.confidence > 0.4 } // naming and search use confident text only
        var lines = rawLines
        var backupPath: String?

        if redact {
            // Nothing sensitive may reach the file name or the Spotlight comment, even where it could not be blacked out.
            lines = rawLines.map { TextLine(text: SensitiveDetector.scrub($0.text), y: $0.y, height: $0.height, rect: $0.rect, confidence: $0.confidence) }
            if let t = title, SensitiveDetector.contains(t) { title = nil }
            let regions = FileNamer.isVideo(url) ? [] : Redactor.regions(in: allLines) // videos are not redacted; faint text counts too
            if !regions.isEmpty {
                guard let backupDir else { throw CocoaError(.fileWriteUnknown) } // never redact without a backup
                try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
                var noTimeMachine = URLResourceValues(); noTimeMachine.isExcludedFromBackup = true // originals hold secrets
                var dir = backupDir; try? dir.setResourceValues(noTimeMachine)
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

        // Most to least reliable: what the screenshot shows → what the browser said → title evidence → header guess.
        var site: String?
        if wantSite {
            site = SiteDetector.addressBarDomain(in: lines) ?? knownSite ?? SiteDetector.domain(in: lines)
            if site == nil, let t = title { site = SiteDetector.fromTitle(t, lines: lines) }
            if site == nil, textSites { site = SiteDetector.brandHeader(in: lines) }
        }
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
        var dest = url
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            // Two captures in the same second can pick the same free name concurrently: retry on a clash.
            for attempt in 1...5 {
                dest = FileNamer.uniqueURL(in: folder, name: name)
                do { try fm.moveItem(at: url, to: dest); break } catch CocoaError.fileWriteFileExists where attempt < 5 {}
            }
        } catch {
            // Not renamed: the redacted file would otherwise stay with no logged backup (purged in 7 days).
            if let b = backupPath { _ = try? fm.replaceItemAt(url, withItemAt: URL(fileURLWithPath: b)) }
            throw error
        }
        if searchable && !FileNamer.isVideo(dest) { try? SearchIndex.write(SearchIndex.comment(from: lines), to: dest) } // best effort: never fail the rename
        try log.append(.init(from: url.path, to: dest.path, date: Date(), createdDirs: created.isEmpty ? nil : created, backup: backupPath))
        return dest
    }

    /// Reverts the most recent rename. Returns the restored URL, or nil if the log is empty.
    /// If the renamed file is gone or the old name is taken, the entry is dropped and an error thrown.
    @discardableResult
    public static func undoLast(log: UndoLog) throws -> URL? {
        guard let r = log.all().last else { return nil }
        let fm = FileManager.default
        guard fm.fileExists(atPath: r.to) else { try log.remove(r); throw CocoaError(.fileNoSuchFile) }
        guard !fm.fileExists(atPath: r.from) else { try log.remove(r); throw CocoaError(.fileWriteFileExists) }
        try fm.moveItem(atPath: r.to, toPath: r.from)
        if let b = r.backup, fm.fileExists(atPath: b) { // put the unredacted original back
            // On failure the record stays, so the backup is not orphaned; undo again once the cause is fixed.
            do { _ = try fm.replaceItemAt(URL(fileURLWithPath: r.from), withItemAt: URL(fileURLWithPath: b)) } catch {
                try? fm.moveItem(atPath: r.from, toPath: r.to); throw error
            }
        }
        try log.remove(r)
        for dir in (r.createdDirs ?? []).reversed() { // innermost first; only if now empty (rmdir refuses otherwise)
            rmdir(dir)
        }
        return URL(fileURLWithPath: r.from)
    }
}
