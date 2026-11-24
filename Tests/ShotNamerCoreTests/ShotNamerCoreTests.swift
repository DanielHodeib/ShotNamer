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
        _ = UndoLog(url: url).all() // a second corrupt read must not fail to back up
        let baks = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".bak") }
        #expect(!baks.isEmpty)
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

@Suite struct SensitiveDetectorTests {
    func kinds(_ s: String) -> [String] { SensitiveDetector.matches(in: s).map(\.kind) }

    @Test func findsEachKind() {
        #expect(kinds("write to max.muster@example.com now") == ["e-mail"])
        #expect(kinds("IBAN AT61 1904 3002 3457 3201") == ["IBAN"])
        #expect(kinds("DE89370400440532013000") == ["IBAN"])
        #expect(kinds("Card 4111 1111 1111 1111") == ["card number"])
        #expect(kinds("4111111111111111") == ["card number"])           // plain digits pass Luhn
        #expect(kinds("token ghp_" + String(repeating: "a1B2", count: 10)) == ["key / token"])
        #expect(kinds("AKIAIOSFODNN7EXAMPLE") == ["key / token"])
        #expect(kinds("Authorization: Bearer abcdef0123456789abcdef") == ["key / token"])
        #expect(kinds("password: hunter2") == ["password / secret"])
        #expect(kinds("Passwort = geheim123") == ["password / secret"])
    }

    @Test func leavesNormalTextAlone() {
        for s in ["MARKTPLATZ 13.797.610", "Aktiv bis 08.01.", "willhaben.at/iad/myprofile", "Meine Anzeigen | willhaben",
                  "1234567890123456", // 16 digits failing Luhn
                  "Node.js and file.png", "26-27-pos5-5a-061-angular-routing-erweiterung-danielhodeib", "Tue 24. Nov 08:39:07",
                  "Passwort vergessen?"] {
            #expect(!SensitiveDetector.contains(s), "false positive: \(s)")
        }
    }

    @Test func scrubRemovesTheSecretButKeepsTheRest() {
        let out = SensitiveDetector.scrub("Login max@example.com password: hunter2 done")
        #expect(!out.contains("max@") && !out.contains("hunter2"))
        #expect(out.contains("Login") && out.contains("done"))
    }
}

import ImageIO
import UniformTypeIdentifiers

@Suite struct RedactionTests {
    func makePNG(at url: URL, dpi: Double = 144) throws {
        let ctx = CGContext(data: nil, width: 400, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 200))
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary)
        #expect(CGImageDestinationFinalize(dest))
    }

    func pixelIsBlack(_ url: URL, x: Int, y: Int) -> Bool { // x,y from the top-left
        let img = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(url as CFURL, nil)!, 0, nil)!
        let ctx = CGContext(data: nil, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        let p = ctx.data!.assumingMemoryBound(to: UInt8.self)
        let row = ctx.bytesPerRow * y
        return p[row + x * 4] < 20 && p[row + x * 4 + 1] < 20 && p[row + x * 4 + 2] < 20
    }

    func dpi(_ url: URL) -> Double? {
        let props = CGImageSourceCopyPropertiesAtIndex(CGImageSourceCreateWithURL(url as CFURL, nil)!, 0, nil) as? [CFString: Any]
        return props?[kCGImagePropertyDPIWidth] as? Double
    }

    @Test func blacksOutKeepsBackupKeepsDPIAndUndoRestores() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = UndoLog(url: dir.appendingPathComponent("log.json"))
        let shot = dir.appendingPathComponent("Screenshot.png"); try makePNG(at: shot)
        let backups = dir.appendingPathComponent("Originals")

        // OCR says: line "Contact max@example.com", the e-mail occupies x 0.5…0.8, y 0.4…0.6 (bottom-left origin)
        let line = TextLine(text: "Contact max@example.com", y: 0.5, height: 0.2, rect: CGRect(x: 0.1, y: 0.4, width: 0.7, height: 0.2),
                            boxFor: { _ in CGRect(x: 0.5, y: 0.4, width: 0.3, height: 0.2) })
        var reported: [String] = []
        let new = try Renamer.rename(shot, date: Date(timeIntervalSince1970: 0), app: "Mail", useOCR: false, searchable: true,
                                     redact: true, backupDir: backups, onRedacted: { reported = $0 }, log: log, recognize: { _ in [line] })

        #expect(reported == ["e-mail"])
        #expect(pixelIsBlack(new, x: 260, y: 100))           // inside the box (x 0.65*400, y centre)
        #expect(!pixelIsBlack(new, x: 20, y: 100))           // outside stays white
        #expect(dpi(new) == 144)                             // Retina metadata survived
        #expect(!new.lastPathComponent.contains("max@"))
        #expect(!(SearchIndex.read(from: new) ?? "").contains("max@"))  // the comment never holds the secret
        #expect((SearchIndex.read(from: new) ?? "").contains("Contact"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: backups.path).count == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).allSatisfy { !$0.hasPrefix(".shotnamer-") }) // temp file gone

        let restored = try #require(try Renamer.undoLast(log: log))
        #expect(!pixelIsBlack(restored, x: 260, y: 100))     // the original is back, unredacted
    }

    @Test func titleWithASecretIsDroppedFromTheName() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = UndoLog(url: dir.appendingPathComponent("log.json"))
        let u = dir.appendingPathComponent("Screenshot.png"); try Data([1]).write(to: u)
        let new = try Renamer.rename(u, date: Date(timeIntervalSince1970: 0), app: "Safari", title: "Inbox - max@example.com",
                                     useOCR: false, redact: true, log: log, recognize: { _ in [] })
        #expect(!new.lastPathComponent.contains("max@"))
    }

    @Test func neverRedactsWithoutABackupLocation() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = UndoLog(url: dir.appendingPathComponent("log.json"))
        let shot = dir.appendingPathComponent("Screenshot.png"); try makePNG(at: shot)
        let line = TextLine(text: "max@example.com", y: 0.5, height: 0.2, rect: CGRect(x: 0.1, y: 0.4, width: 0.5, height: 0.2))
        #expect(throws: (any Error).self) {
            try Renamer.rename(shot, date: Date(), app: "Mail", useOCR: false, redact: true, backupDir: nil, log: log, recognize: { _ in [line] })
        }
        #expect(!pixelIsBlack(shot, x: 100, y: 100)) // untouched
    }
}

@Suite struct SiteFallbackTests {
    func L(_ t: String, _ y: Double) -> TextLine { TextLine(text: t, y: y, height: 0.03) }

    @Test func titleSegmentNeedsEvidenceInTheImage() {
        let header = [L("WILLHABEN", 0.92), L("Meine Anzeigen", 0.6)]
        #expect(SiteDetector.fromTitle("Meine Anzeigen | willhaben", lines: header) == "willhaben")
        #expect(SiteDetector.fromTitle("Meine Anzeigen | willhaben", lines: [L("Meine Anzeigen", 0.6)]) == nil)   // no evidence
        #expect(SiteDetector.fromTitle("Meine Anzeigen | willhaben", lines: [L("willhaben", 0.3)]) == nil)         // not a header
        #expect(SiteDetector.fromTitle("Home - Docs", lines: [L("Welcome", 0.5)]) == nil)                           // never invent a site
        #expect(SiteDetector.fromTitle("Dashboard", lines: [L("Dashboard", 0.95)]) == nil)                          // single segment
        #expect(SiteDetector.fromTitle("E-Mail Einstellungen", lines: [L("E-Mail Einstellungen", 0.9)]) == nil)     // hyphen is not a separator
    }

    @Test func wellKnownBrandsInTitles() {
        #expect(SiteDetector.fromTitle("GitHub", lines: []) == "github.com")
        #expect(SiteDetector.fromTitle("Pull requests · DanielHodeib/ShotNamer · GitHub", lines: []) == "github.com")
        #expect(SiteDetector.fromTitle("How do I … - Stack Overflow", lines: []) == "stackoverflow.com")
    }

    @Test func brandHeaderOnlyForExactTopLines() {
        #expect(SiteDetector.brandHeader(in: [L("YouTube", 0.95)]) == "youtube.com")
        #expect(SiteDetector.brandHeader(in: [L("YouTube", 0.5)]) == nil)                         // body text, not a header
        #expect(SiteDetector.brandHeader(in: [L("I love GitHub actions", 0.95)]) == nil)           // sentence, not the logo
    }

    @Test func urlsBecomeDomains() {
        #expect(SiteDetector.domain(ofURL: "https://docs.github.com/en/x?y=1") == "github.com")
        #expect(SiteDetector.domain(ofURL: "https://www.willhaben.at/iad/myprofile") == "willhaben.at")
        #expect(SiteDetector.domain(ofURL: "chrome://newtab") == nil)
        #expect(SiteDetector.domain(ofURL: "file:///Users/x/a.html") == nil)
        #expect(SiteDetector.domain(ofURL: "http://localhost:3000/") == nil)
    }

    @Test func orderIsAddressBarThenBrowserThenTitleThenHeader() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = UndoLog(url: dir.appendingPathComponent("log.json"))
        func name(lines: [TextLine], title: String?, known: String?, text: Bool) throws -> String {
            let u = dir.appendingPathComponent("Screenshot \(UUID().uuidString).png"); try Data([1]).write(to: u)
            return try Renamer.rename(u, date: Date(timeIntervalSince1970: 0), app: "Brave Browser", title: title, useSite: true, useOCR: false,
                                      knownSite: known, textSites: text, log: log, recognize: { _ in lines }).lastPathComponent
        }
        let first = try name(lines: [L("github.com", 0.95)], title: nil, known: "other.com", text: true)
        #expect(first.hasSuffix("github.com.png") && !first.contains("other.com")) // what the screenshot shows wins
        #expect(try name(lines: [], title: nil, known: "other.com", text: true).hasSuffix("other.com.png"))
        #expect(try name(lines: [L("WILLHABEN", 0.9)], title: "Meine Anzeigen | willhaben", known: nil, text: true).hasSuffix("willhaben - Meine Anzeigen | willhaben.png"))
        #expect(try name(lines: [L("YouTube", 0.95)], title: nil, known: nil, text: true).hasSuffix("youtube.com.png"))
        #expect(try name(lines: [L("YouTube", 0.95)], title: nil, known: nil, text: false).hasSuffix("Brave Browser.png"))  // experimental: opt-in
    }
}

import CryptoKit
import AVFoundation
import CoreVideo

@Suite struct UpdateTests {
    @Test func comparesVersions() {
        #expect(Update.isNewer("v0.2.0", than: "0.1.0"))
        #expect(Update.isNewer("0.1.10", than: "0.1.9"))   // numeric, not string, comparison
        #expect(Update.isNewer("1.0", than: "0.9.9"))
        #expect(!Update.isNewer("0.1.0", than: "0.1.0"))
        #expect(!Update.isNewer("0.1", than: "0.1.0"))      // equal after padding
        #expect(!Update.isNewer("0.0.9", than: "0.1.0"))    // never downgrade
        #expect(!Update.isNewer("latest", than: "0.1.0"))   // garbage tag
        #expect(!Update.isNewer("v1.0.0-beta", than: "0.1.0"))
    }

    @Test func parsesAGitHubRelease() throws {
        let json = #"{"tag_name":"v0.2.0","draft":false,"prerelease":false,"name":"x","assets":[{"name":"ShotNamer.zip","browser_download_url":"https://github.com/a/b/releases/download/v0.2.0/ShotNamer.zip","size":1},{"name":"ShotNamer.zip.sig","browser_download_url":"https://github.com/a/b/releases/download/v0.2.0/ShotNamer.zip.sig"}]}"#
        let r = try JSONDecoder().decode(Update.Release.self, from: Data(json.utf8))
        #expect(r.version == "0.2.0")
        #expect(r.asset(Update.zipName)?.lastPathComponent == "ShotNamer.zip")
        #expect(r.asset(Update.signatureName) != nil)
        #expect(r.asset("other") == nil)
    }

    @Test func onlyAcceptsCorrectlySignedData() throws {
        let key = Curve25519.Signing.PrivateKey()
        let pub = key.publicKey.rawRepresentation.base64EncodedString()
        let data = Data("the real update".utf8)
        let sig = try key.signature(for: data).base64EncodedString()
        #expect(Update.verify(data, signatureBase64: sig, publicKeyBase64: pub))
        #expect(!Update.verify(Data("tampered update".utf8), signatureBase64: sig, publicKeyBase64: pub))
        let other = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()
        #expect(!Update.verify(data, signatureBase64: sig, publicKeyBase64: other))   // signed by someone else
        #expect(!Update.verify(data, signatureBase64: "not base64!", publicKeyBase64: pub))
    }

    @Test func refusesAWrongAppInsideTheZip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let app = dir.appendingPathComponent("ShotNamer.app/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        func make(_ id: String, _ v: String) throws {
            try (["CFBundleIdentifier": id, "CFBundleShortVersionString": v] as NSDictionary)
                .write(to: app.appendingPathComponent("Info.plist"))
        }
        let bundle = dir.appendingPathComponent("ShotNamer.app"), id = "io.github.danielhodeib.ShotNamer"
        try make(id, "0.2.0")
        #expect(Update.isAcceptable(app: bundle, releaseVersion: "0.2.0", bundleID: id, current: "0.1.0"))
        #expect(!Update.isAcceptable(app: bundle, releaseVersion: "0.3.0", bundleID: id, current: "0.1.0")) // old zip, new tag
        #expect(!Update.isAcceptable(app: bundle, releaseVersion: "0.2.0", bundleID: id, current: "0.2.0")) // not newer
        try make("com.evil.app", "0.2.0")
        #expect(!Update.isAcceptable(app: bundle, releaseVersion: "0.2.0", bundleID: id, current: "0.1.0"))
        #expect(!Update.isAcceptable(app: dir, releaseVersion: "0.2.0", bundleID: id, current: "0.1.0"))    // no Info.plist
    }
}

/// Regressions found in the full review (Nov 2026).
@Suite struct ReviewFixTests {
    func scratch() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    func L(_ t: String, _ y: Double) -> TextLine { TextLine(text: t, y: y, height: 0.03) }

    @Test func failedMoveAfterRedactionPutsTheOriginalBack() throws {
        let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
        let log = UndoLog(url: dir.appendingPathComponent("log.json"))
        let shot = dir.appendingPathComponent("Screenshot.png"); try RedactionTests().makePNG(at: shot)
        let notAFolder = dir.appendingPathComponent("file"); try Data([1]).write(to: notAFolder) // sort target can't be created
        let line = TextLine(text: "max@example.com", y: 0.5, height: 0.2, rect: CGRect(x: 0.1, y: 0.4, width: 0.5, height: 0.2))
        #expect(throws: (any Error).self) {
            try Renamer.rename(shot, date: Date(), app: "Mail", useOCR: false, sort: .month, sortRoot: notAFolder, redact: true,
                               backupDir: dir.appendingPathComponent("Originals"), log: log, recognize: { _ in [line] })
        }
        #expect(!RedactionTests().pixelIsBlack(shot, x: 100, y: 100)) // unredacted original, under its own name
        #expect(log.all().isEmpty)
    }

    @Test func faintTextIsRedactedButNotUsedForNames() throws {
        let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
        let shot = dir.appendingPathComponent("Screenshot.png"); try RedactionTests().makePNG(at: shot)
        let faint = TextLine(text: "Big faint max@example.com", y: 0.5, height: 0.9, rect: CGRect(x: 0.1, y: 0.4, width: 0.7, height: 0.2), confidence: 0.2)
        var reported: [String] = []
        let new = try Renamer.rename(shot, date: Date(timeIntervalSince1970: 0), app: "Mail", useOCR: true, redact: true,
                                     backupDir: dir.appendingPathComponent("Originals"), onRedacted: { reported = $0 },
                                     log: UndoLog(url: dir.appendingPathComponent("log.json")), recognize: { _ in [faint] })
        #expect(reported == ["e-mail"])
        #expect(!new.lastPathComponent.contains("faint"))
    }

    @Test func pageTextDoesNotBeatTheBrowserURL() throws {
        let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
        let u = dir.appendingPathComponent("Screenshot.png"); try Data([1]).write(to: u)
        let new = try Renamer.rename(u, date: Date(timeIntervalSince1970: 0), app: "Safari", useSite: true, useOCR: false,
                                     knownSite: "reddit.com", log: UndoLog(url: dir.appendingPathComponent("log.json")),
                                     recognize: { _ in [self.L("via imgur.com", 0.5), self.L("imgur.com", 0.3)] })
        #expect(new.lastPathComponent.contains("reddit.com"))
    }

    @Test func fileNamesInPagesAreNotSites() {
        #expect(SiteDetector.domain(in: [L("Open /Applications/Xcode.app now", 0.5)]) == nil)
        #expect(SiteDetector.domain(in: [L("claude.ai", 0.95)]) == "claude.ai") // in the address bar it is a site
    }

    @Test func phoneNumbersAreNotCards() {
        #expect(SensitiveDetector.matches(in: "Call 0664 1234 5678").isEmpty)
        #expect(SensitiveDetector.matches(in: "4111 1111 1111 1111").map(\.kind) == ["card number"])
    }

    @Test func templateKeepsItsOwnTextWhenTheFirstTokenIsEmpty() {
        #expect(Template.render("Shot {app} {date}", values: ["app": "", "date": "d"]) == "Shot d")
        #expect(Template.render("{date} {app} (mine)", values: ["app": "", "date": "d"]) == "d (mine)")
        #expect(Template.render("{date} - {app} - {title}", values: ["date": "d", "app": "", "title": "t"]) == "d - t")
    }

    @Test func spanishTwelveHourTimes() {
        let d = FileNamer.captureDate(fromFilename: "Captura de pantalla 2026-11-24 a las 2.32.10 p. m..png", timeZone: utc)
        #expect(d.map { Calendar(identifier: .gregorian).dateComponents(in: utc, from: $0).hour } == 14)
    }

    @Test func longUnicodeNamesFitTheFileSystem() {
        let name = FileNamer.makeName(date: Date(), app: String(repeating: "漢", count: 40), site: "example.com",
                                      text: String(repeating: "😀", count: 60), ext: "png")
        #expect(name.utf8.count <= 255)
    }

    @Test func undoOfAMissingFileDropsOnlyThatRecord() throws {
        let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
        let log = UndoLog(url: dir.appendingPathComponent("log.json"))
        let keep = UndoLog.Record(from: "/a", to: "/b", date: Date(timeIntervalSince1970: 1))
        try log.append(keep)
        try log.append(.init(from: "/x", to: dir.appendingPathComponent("gone.png").path, date: Date(timeIntervalSince1970: 2)))
        #expect(throws: (any Error).self) { try Renamer.undoLast(log: log) }
        #expect(log.all() == [keep])
    }

    @Test func undoThatFailsRestoringTheBackupKeepsTheRecordAndTheFile() throws {
        let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
        let log = UndoLog(url: dir.appendingPathComponent("log.json"))
        let shot = dir.appendingPathComponent("Screenshot.png"); try RedactionTests().makePNG(at: shot)
        let backups = dir.appendingPathComponent("Originals")
        let line = TextLine(text: "max@example.com", y: 0.5, height: 0.2, rect: CGRect(x: 0.1, y: 0.4, width: 0.5, height: 0.2))
        let new = try Renamer.rename(shot, date: Date(), app: "Mail", useOCR: false, redact: true, backupDir: backups,
                                     log: log, recognize: { _ in [line] })
        // Break the backup: an immutable file can't be moved into place, so the restore throws.
        var backup = try #require(FileManager.default.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil).first)
        var lock = URLResourceValues(); lock.isUserImmutable = true
        try backup.setResourceValues(lock)
        defer { var unlock = URLResourceValues(); unlock.isUserImmutable = false; try? backup.setResourceValues(unlock) }

        #expect(throws: (any Error).self) { try Renamer.undoLast(log: log) }
        #expect(FileManager.default.fileExists(atPath: new.path))            // still under the new name, not stranded
        #expect(!FileManager.default.fileExists(atPath: shot.path))
        #expect(log.all().count == 1)                                          // record kept: undo can be retried
    }
}

@Suite struct VideoTests {
    /// Writes a 2 s solid-colour .mov so the frame grabber and the rename can run on a real movie.
    static func makeMovie(at url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 320, AVVideoHeightKey: 200])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 320,
            kCVPixelBufferHeightKey as String: 200])
        writer.add(input); writer.startWriting(); writer.startSession(atSourceTime: .zero)
        for i in 0..<4 {
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, 320, 200, kCVPixelFormatType_32BGRA, nil, &buffer)
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(10)) }
            adaptor.append(buffer!, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: 2))
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }

    @Test func readsAFrameAndRenamesARecording() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let mov = dir.appendingPathComponent("Screen Recording 2026-11-24 at 9.55.00 AM.mov")
        try await Self.makeMovie(at: mov)

        let frame = try #require(TextRecognizer.frame(of: mov))
        #expect(frame.width == 320 && frame.height == 200)

        let log = UndoLog(url: dir.appendingPathComponent("log.json"))
        let new = try Renamer.rename(mov, date: Date(timeIntervalSince1970: 0), app: "Safari", useSite: true, useOCR: false,
                                     searchable: true, log: log)       // real OCR path on a video frame
        #expect(new.pathExtension == "mov" && !FileNamer.isCapture(filename: new.lastPathComponent))
        #expect(!FileManager.default.fileExists(atPath: mov.path))
    }
}
