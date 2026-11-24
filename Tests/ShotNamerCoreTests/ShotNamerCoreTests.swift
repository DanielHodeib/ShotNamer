import Foundation
import Testing
@testable import ShotNamerCore

let utc = TimeZone(identifier: "UTC")!

@Suite struct FileNamerTests {
    @Test func detectsLocalizedScreenshots() {
        #expect(FileNamer.isScreenshot(filename: "Screenshot 2026-11-24 at 2.32.10 PM.png"))
        #expect(FileNamer.isScreenshot(filename: "Bildschirmfoto 2026-11-24 um 14.32.10.png"))
        #expect(!FileNamer.isScreenshot(filename: ".Screenshot 2026-11-24 at 2.32.10 PM.png"))
        #expect(!FileNamer.isScreenshot(filename: "Screenshot 2026-11-24.mov"))
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

        let a2 = try Renamer.rename(a, date: date, app: "Safari", useOCR: true, log: log, ocr: { _ in "Title" })
        let b2 = try Renamer.rename(b, date: date, app: "Safari", useOCR: true, log: log, ocr: { _ in "Title" })
        #expect(a2.lastPathComponent.hasSuffix("Safari - Title.png"))
        #expect(b2.lastPathComponent.hasSuffix("Safari - Title 2.png"))

        let restored = try Renamer.undoLast(log: log)
        #expect(restored?.lastPathComponent == "Screenshot B.png")
        #expect(FileManager.default.fileExists(atPath: b.path))
        #expect(!FileManager.default.fileExists(atPath: b2.path))

        try Renamer.undoLast(log: log)
        #expect(try Renamer.undoLast(log: log) == nil)
    }

    @Test func ocrOffSkipsText() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = UndoLog(url: dir.appendingPathComponent("log.json"))
        let u = dir.appendingPathComponent("Screenshot.png"); try Data([1]).write(to: u)
        let new = try Renamer.rename(u, date: Date(timeIntervalSince1970: 0), app: "Notes", useOCR: false, log: log,
                                     ocr: { _ in Issue.record("OCR must not run"); return nil })
        #expect(new.lastPathComponent.hasSuffix("Notes.png"))
    }
}
