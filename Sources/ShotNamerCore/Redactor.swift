import CoreGraphics
import Foundation
import ImageIO

/// Blacks out sensitive text in an image file. Opt-in; the caller must keep a backup of the original.
public enum Redactor {
    public struct Region {
        public let rect: CGRect // normalised, origin bottom-left (as Vision reports it)
        public let kind: String
    }

    /// Boxes for everything `SensitiveDetector` flags. If a substring box is unavailable the whole line is covered.
    public static func regions(in lines: [TextLine]) -> [Region] {
        lines.flatMap { line in
            SensitiveDetector.matches(in: line.text).compactMap { m -> Region? in
                let box = line.boxFor?(m.range) ?? line.rect
                return box.isEmpty ? nil : Region(rect: box, kind: m.kind)
            }
        }
    }

    /// Redraws the image with black boxes and replaces the file atomically. Keeps format, colour profile and DPI
    /// (the source's properties are copied), so a Retina screenshot does not suddenly open at double size.
    public static func blackOut(_ url: URL, regions: [Region]) throws {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil),
              let type = CGImageSourceGetType(src) else { throw CocoaError(.fileReadCorruptFile) }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil)
        let w = CGFloat(image.width), h = CGFloat(image.height) // pixels, not points
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                ?? CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                             space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw CocoaError(.fileWriteUnknown) }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        for r in regions {
            let box = CGRect(x: r.rect.minX * w, y: r.rect.minY * h, width: r.rect.width * w, height: r.rect.height * h)
            let pad = max(4, box.height * 0.25) // OCR boxes are tight; cover descenders and edges
            ctx.fill(box.insetBy(dx: -pad, dy: -pad))
        }
        guard let out = ctx.makeImage() else { throw CocoaError(.fileWriteUnknown) }

        // Dot-prefixed temp next to the original: invisible to the folder watcher, same volume for an atomic swap.
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".shotnamer-\(UUID().uuidString).\(url.pathExtension)")
        guard let dest = CGImageDestinationCreateWithURL(tmp as CFURL, type, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(dest, out, props)
        guard CGImageDestinationFinalize(dest) else { try? FileManager.default.removeItem(at: tmp); throw CocoaError(.fileWriteUnknown) }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
    }

    /// Originals older than `days` are deleted: they still contain the secrets.
    public static func purgeBackups(in dir: URL, olderThanDays days: Int = 7) {
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        for url in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let date, date < cutoff { try? fm.removeItem(at: url) }
        }
    }
}
