import Foundation
import Testing
@testable import ShotNamerCore

let utc = TimeZone(identifier: "UTC")!

@Suite struct FileNamerTests {
    @Test func detectsLocalizedScreenshots() {
        #expect(FileNamer.isScreenshot(filename: "Screenshot 2026-11-24 at 2.32.10 PM.png"))
        #expect(FileNamer.isScreenshot(filename: "Bildschirmfoto 2026-11-24 um 14.32.10.png"))
        #expect(!FileNamer.isScreenshot(filename: ".Screenshot 2026-11-24 at 2.32.10 PM.png"))
        #expect(!FileNamer.isScreenshot(filename: "Screenshot 2026-11-24.mov")) // a video is not a screenshot
        #expect(FileNamer.isCapture(filename: "Screen Recording 2026-11-24 at 14.32.10.mov"))
        #expect(FileNamer.isCapture(filename: "Bildschirmaufnahme 2026-11-24 um 14.32.10.mov"))
        #expect(!FileNamer.isCapture(filename: "2026-11-24 14.32.10 - Safari.mov")) // renamed recordings are not re-processed
        #expect(!FileNamer.isCapture(filename: "Screen Recording notes.txt"))
        #expect(!FileNamer.isScreenshot(filename: "holiday.png"))
    }

    @Test func parsesCaptureTimeInAnyLocale() {
        let en = FileNamer.captureDate(fromFilename: "Screenshot 2026-11-24 at 2.32.10 PM.png", timeZone: utc)
        let de = FileNamer.captureDate(fromFilename: "Bildschirmfoto 2026-11-24 um 14.32.10.png", timeZone: utc)
        let am = FileNamer.captureDate(fromFilename: "Screenshot 2026-11-24 at 12.05.00 AM.png", timeZone: utc)
        #expect(en == de)
        #expect(en != nil)
        let c = Calendar(identifier: .gregorian)
        #expect(c.dateComponents(in: utc, from: am!).hour == 0)
        #expect(FileNamer.captureDate(fromFilename: "holiday.png") == nil)
    }

    @Test func renamedFilesAreNeverScreenshotsAgain() {
        let date = FileNamer.captureDate(fromFilename: "Screenshot 2026-11-24 at 2.32.10 PM.png", timeZone: utc)!
        let name = FileNamer.makeName(date: date, app: "Safari", text: "Screenshot of a page", ext: "png", timeZone: utc)
        #expect(name == "2026-11-24 14.32.10 - Safari - Screenshot of a page.png")
        #expect(!FileNamer.isScreenshot(filename: name)) // no rename loop
    }

    @Test func sanitizesIllegalCharacters() {
        #expect(FileNamer.sanitize("a/b: c\\d\n e") == "a b c d e")
        #expect(FileNamer.sanitize("..hidden") == "hidden")
        #expect(FileNamer.sanitize(String(repeating: "x", count: 80)).count == 50)
    }

    @Test func omitsMissingParts() {
        let name = FileNamer.makeName(date: Date(timeIntervalSince1970: 0), app: nil, text: nil, ext: "png", timeZone: utc)
        #expect(name == "1970-01-01 00.00.00.png")
    }
}

@Suite struct AppHistoryTests {
    @Test func returnsAppActiveAtThatTime() {
        var h = AppHistory()
        h.record(name: "Safari", at: Date(timeIntervalSince1970: 100))
        h.record(name: "Xcode", at: Date(timeIntervalSince1970: 200))
        #expect(h.app(at: Date(timeIntervalSince1970: 150)) == "Safari")
        #expect(h.app(at: Date(timeIntervalSince1970: 250)) == "Xcode")
        #expect(h.app(at: Date(timeIntervalSince1970: 50)) == nil)
    }
}

@Suite struct RenamerTests {
    func scratch() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func renamesUndoesAndAvoidsCollisions() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = UndoLog(url: dir.appendingPathComponent("log.json"))
        let date = Date(timeIntervalSince1970: 0)

        func shot(_ n: String) throws -> URL {
            let u = dir.appendingPathComponent(n); try Data([1]).write(to: u); return u
        }
        let a = try shot("Screenshot A.png"), b = try shot("Screenshot B.png")

        let a2 = try Renamer.rename(a, date: date, app: "Safari", useOCR: true, log: log, recognize: { _ in [TextLine(text: "Title", y: 0.5, height: 0.1)] })
        let b2 = try Renamer.rename(b, date: date, app: "Safari", useOCR: true, log: log, recognize: { _ in [TextLine(text: "Title", y: 0.5, height: 0.1)] })
        #expect(a2.lastPathComponent.hasSuffix("Safari - Title.png"))
        #expect(b2.lastPathComponent.hasSuffix("Safari - Title 2.png"))

        let restored = try Renamer.undoLast(log: log)
        #expect(restored?.lastPathComponent == "Screenshot B.png")
        #expect(FileManager.default.fileExists(atPath: b.path))
        #expect(!FileManager.default.fileExists(atPath: b2.path))

        try Renamer.undoLast(log: log)
        #expect(try Renamer.undoLast(log: log) == nil)
    }

    @Test func titleBeatsOCR() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = UndoLog(url: dir.appendingPathComponent("log.json"))
        let u = dir.appendingPathComponent("Screenshot.png"); try Data([1]).write(to: u)
        let new = try Renamer.rename(u, date: Date(timeIntervalSince1970: 0), app: "Brave Browser",
                                     title: "Meine Anzeigen | willhaben", useOCR: true, log: log,
                                     recognize: { _ in Issue.record("OCR must not run when a title exists"); return [] })
        #expect(new.lastPathComponent.hasSuffix("Brave Browser - Meine Anzeigen | willhaben.png"))
    }

    @Test func ocrOffSkipsText() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = UndoLog(url: dir.appendingPathComponent("log.json"))
        let u = dir.appendingPathComponent("Screenshot.png"); try Data([1]).write(to: u)
        let new = try Renamer.rename(u, date: Date(timeIntervalSince1970: 0), app: "Notes", useOCR: false, log: log,
                                     recognize: { _ in Issue.record("OCR must not run"); return [] })
        #expect(new.lastPathComponent.hasSuffix("Notes.png"))
    }
}

@Suite struct SiteDetectorTests {
    func lines(_ items: (String, Double)...) -> [TextLine] { items.map { TextLine(text: $0.0, y: $0.1, height: 0.02) } }

    @Test func findsDomainInAddressBar() {
        #expect(SiteDetector.domain(in: lines(("Bookmarks", 0.95), ("willhaben.at/iad/myprofile/myadverts", 0.99))) == "willhaben.at")
        #expect(SiteDetector.domain(in: lines(("github.com", 0.91))) == "github.com")
        #expect(SiteDetector.domain(in: lines(("https://www.docs.github.com/en", 0.95))) == "github.com")
        #expect(SiteDetector.registrable("www.bbc.co.uk") == "bbc.co.uk")
    }

    @Test func ignoresNonDomains() {
        #expect(SiteDetector.domain(in: lines(("MARKTPLATZ 13.797.610", 0.8), ("Aktiv bis 08.01.", 0.4), ("Node.js and file.png", 0.5))) == nil)
        #expect(SiteDetector.domain(in: lines(("mail me at dan@gmail.com", 0.5))) == nil)
    }

    @Test func addressBarBeatsPageContent() {
        #expect(SiteDetector.domain(in: lines(("see example.org", 0.5), ("see example.org", 0.4), ("github.com", 0.95))) == "github.com")
        #expect(SiteDetector.domain(in: lines(("see example.org", 0.5), ("a.com", 0.3), ("example.org", 0.2))) == "example.org")
    }

    @Test func onlyBrowsersAreScanned() {
        #expect(SiteDetector.isBrowser("Brave Browser"))
        #expect(SiteDetector.isBrowser("Safari"))
        #expect(!SiteDetector.isBrowser("Mail"))
        #expect(!SiteDetector.isBrowser(nil))
    }

    @Test func redundantTitleIsDropped() {
        #expect(SiteDetector.isRedundant(title: "GitHub", site: "github.com"))
        #expect(!SiteDetector.isRedundant(title: "Meine Anzeigen | willhaben", site: "willhaben.at"))
    }

    @Test func siteEndsUpInTheName() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = UndoLog(url: dir.appendingPathComponent("log.json"))
        let u = dir.appendingPathComponent("Screenshot.png"); try Data([1]).write(to: u)
        let fake: (URL) -> [TextLine] = { _ in [TextLine(text: "github.com", y: 0.91, height: 0.02)] }
        let new = try Renamer.rename(u, date: Date(timeIntervalSince1970: 0), app: "Brave Browser", title: "GitHub",
                                     useSite: true, useOCR: false, log: log, recognize: fake)
        #expect(new.lastPathComponent.hasSuffix("Brave Browser - github.com.png"))
        // non-browser: no scanning
        let v = dir.appendingPathComponent("Screenshot2.png"); try Data([1]).write(to: v)
        let other = try Renamer.rename(v, date: Date(timeIntervalSince1970: 0), app: "Mail", useSite: true, useOCR: false,
                                       log: log, recognize: { _ in Issue.record("must not OCR in Mail"); return [] })
        #expect(other.lastPathComponent.hasSuffix("Mail.png"))
    }
}

@Suite struct TemplateTests {
    let all = ["date": "2026-11-24", "time": "14.32.10", "app": "Safari", "site": "github.com", "title": "Pull requests"]

    @Test func defaultTemplateReproducesTheOriginalNames() {
        #expect(Template.render(Template.defaultName, values: all) == "2026-11-24 14.32.10 - Safari - github.com - Pull requests")
        var v = all; v["site"] = ""
        #expect(Template.render(Template.defaultName, values: v) == "2026-11-24 14.32.10 - Safari - Pull requests")
        v["app"] = ""; v["title"] = ""
        #expect(Template.render(Template.defaultName, values: v) == "2026-11-24 14.32.10")
    }

    @Test func customTemplatesAndMissingLeadingTokens() {
        #expect(Template.render("{site} · {date}", values: all) == "github.com · 2026-11-24")
        var v = all; v["site"] = ""
        #expect(Template.render("{site} · {date}", values: v) == "2026-11-24")
        #expect(Template.render("{date}_{app}", values: all) == "2026-11-24_Safari")
        #expect(Template.render("{date} {nope}", values: all) == "2026-11-24 {nope}") // unknown token kept
    }

    @Test func rejectsTemplatesThatWouldCauseRenameLoopsOrCollisions() {
        #expect(Template.isValidName(Template.defaultName))
        #expect(!Template.isValidName("Screenshot {date} {time}")) // output looks like a new screenshot
        #expect(!Template.isValidName("{app} - {site}"))           // no date/time → names collide
        #expect(!Template.isValidName(""))
        #expect(FileNamer.makeName(date: Date(timeIntervalSince1970: 0), app: "A", text: nil, ext: "png",
                                   template: "Screenshot {date}", timeZone: utc) == "1970-01-01 00.00.00 - A.png") // falls back to default
    }

    @Test func tokenValuesCannotCreateFolders() {
        let name = FileNamer.makeName(date: Date(timeIntervalSince1970: 0), app: "a/b", site: nil, text: "x/../y: z",
                                      ext: "png", template: "{date}/{title}", timeZone: utc)
        #expect(!name.contains("/") && !name.contains(":"))
    }
}

@Suite struct UndoLogCompatTests {
    @Test func readsTheLogFormatWrittenByEarlierVersions() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("renames.json")
        // exact shape of the 0.1 file on disk: date, from, to
        try #"[{"date":"2026-11-24T07:34:52Z","from":"/a/Screenshot.png","to":"/a/2026-11-24 - X.png"}]"#.write(to: url, atomically: true, encoding: .utf8)
        let log = UndoLog(url: url)
        #expect(log.all().count == 1)
        try log.append(.init(from: "/b", to: "/c", date: Date()))
        #expect(log.all().count == 2) // old record survived the rewrite
    }

    @Test func corruptLogIsBackedUpNotDestroyed() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("renames.json")
        try "not json".write(to: url, atomically: true, encoding: .utf8)
        _ = UndoLog(url: url).all()
        #expect(FileManager.default.fileExists(atPath: url.appendingPathExtension("bak").path))
    }
}

@Suite struct SortTests {
    @Test func buildsFolderPaths() {
        let d = FileNamer.captureDate(fromFilename: "Screenshot 2026-11-24 at 2.32.10 PM.png", timeZone: utc)!
        #expect(SortMode.off.subpath(date: d, app: "Safari", site: "github.com", timeZone: utc) == "")
        #expect(SortMode.month.subpath(date: d, app: nil, site: nil, timeZone: utc) == "2026-11")
        #expect(SortMode.source.subpath(date: d, app: "Safari", site: "github.com", timeZone: utc) == "github.com")
        #expect(SortMode.source.subpath(date: d, app: "Safari", site: nil, timeZone: utc) == "Safari")
        #expect(SortMode.source.subpath(date: d, app: nil, site: nil, timeZone: utc) == "Other")
        #expect(SortMode.monthSource.subpath(date: d, app: "A/B", site: nil, timeZone: utc) == "2026-11/A B")
    }

    func scratch() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func sortsThenUndoRemovesOnlyEmptyCreatedFolders() throws {
        let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
        let log = UndoLog(url: dir.appendingPathComponent("log.json"))
        let fm = FileManager.default
        func shot(_ n: String) throws -> URL { let u = dir.appendingPathComponent(n); try Data([1]).write(to: u); return u }
        let date = Date(timeIntervalSince1970: 0)
        let a = try Renamer.rename(try shot("Screenshot A.png"), date: date, app: "Safari", useOCR: false,
                                   sort: .monthSource, sortRoot: dir.appendingPathComponent("Sorted"), log: log)
        #expect(a.deletingLastPathComponent().path.hasSuffix("Sorted/1970-01/Safari"))
        let b = try Renamer.rename(try shot("Screenshot B.png"), date: date, app: "Safari", useOCR: false,
                                   sort: .monthSource, sortRoot: dir.appendingPathComponent("Sorted"), log: log)
        #expect(fm.fileExists(atPath: b.path))

        try Renamer.undoLast(log: log)            // B: folders already existed → must stay (A is inside)
        #expect(fm.fileExists(atPath: dir.appendingPathComponent("Sorted/1970-01/Safari").path))
        try Renamer.undoLast(log: log)            // A: created Sorted/, 1970-01/, Safari/ → all gone
        #expect(!fm.fileExists(atPath: dir.appendingPathComponent("Sorted").path))
        #expect(fm.fileExists(atPath: dir.appendingPathComponent("Screenshot A.png").path))
    }

    @Test func undoKeepsFoldersThatHoldOtherFiles() throws {
        let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
        let log = UndoLog(url: dir.appendingPathComponent("log.json"))
        let u = dir.appendingPathComponent("Screenshot.png"); try Data([1]).write(to: u)
        let root = dir.appendingPathComponent("Sorted")
        _ = try Renamer.rename(u, date: Date(timeIntervalSince1970: 0), app: "Safari", useOCR: false, sort: .source, sortRoot: root, log: log)
        try Data([2]).write(to: root.appendingPathComponent("Safari/user-file.txt"))
        try Renamer.undoLast(log: log)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("Safari/user-file.txt").path))
    }
}

@Suite struct SearchIndexTests {
    @Test func commentRoundTripsAndDedupes() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = UndoLog(url: dir.appendingPathComponent("log.json"))
        let u = dir.appendingPathComponent("Screenshot.png"); try Data([1]).write(to: u)
        let lines = [TextLine(text: "Marktplatz", y: 0.5, height: 0.1), TextLine(text: "Marktplatz", y: 0.4, height: 0.1),
                     TextLine(text: "Meine Anzeigen", y: 0.3, height: 0.1)]
        let new = try Renamer.rename(u, date: Date(timeIntervalSince1970: 0), app: "Notes", useOCR: false,
                                     searchable: true, log: log, recognize: { _ in lines })
        #expect(SearchIndex.read(from: new) == "Marktplatz Meine Anzeigen")
    }

    @Test func offMeansNoOCRAndNoComment() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = UndoLog(url: dir.appendingPathComponent("log.json"))
        let u = dir.appendingPathComponent("Screenshot.png"); try Data([1]).write(to: u)
        let new = try Renamer.rename(u, date: Date(timeIntervalSince1970: 0), app: "Notes", useOCR: false, log: log,
                                     recognize: { _ in Issue.record("no OCR needed"); return [] })
        #expect(SearchIndex.read(from: new) == nil)
    }
}
