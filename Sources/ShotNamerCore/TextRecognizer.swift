import Foundation
import AVFoundation
import Vision

/// One recognised line of text. `y` is the vertical centre (0 = bottom, 1 = top), `height` the relative text height,
/// `rect` the line's normalised box. `boxFor` gives the box of a substring of `text` (for redaction).
public struct TextLine {
    public let text: String
    public let y: Double
    public let height: Double
    public let rect: CGRect
    /// OCR confidence 0…1. Naming uses > 0.4; redaction also covers fainter text.
    public let confidence: Float
    let boxFor: ((Range<String.Index>) -> CGRect?)?
    public init(text: String, y: Double, height: Double, rect: CGRect = .zero, confidence: Float = 1,
                boxFor: ((Range<String.Index>) -> CGRect?)? = nil) {
        self.text = text; self.y = y; self.height = height; self.rect = rect; self.confidence = confidence; self.boxFor = boxFor
    }
}

/// On-device OCR (Apple Vision). Nothing leaves the Mac.
public enum TextRecognizer {
    /// Images are read directly; for a video, a frame near the start is read.
    public static func lines(of url: URL) -> [TextLine] {
        if FileNamer.isVideo(url) {
            guard let frame = frame(of: url) else { return [] }
            return recognize(VNImageRequestHandler(cgImage: frame))
        }
        return recognize(VNImageRequestHandler(url: url))
    }

    private static func recognize(_ handler: VNImageRequestHandler) -> [TextLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false // URLs and names are not dictionary words
        request.automaticallyDetectsLanguage = true
        do { try handler.perform([request]) } catch { return [] }
        return (request.results ?? []).compactMap { o in
            guard let c = o.topCandidates(1).first, c.confidence > 0.1 else { return nil }
            // Ranges must be taken on c.string itself, so `text` is exactly that string.
            return TextLine(text: c.string, y: o.boundingBox.midY, height: o.boundingBox.height, rect: o.boundingBox,
                            confidence: c.confidence, boxFor: { range in (try? c.boundingBox(for: range))?.boundingBox })
        }
    }

    /// A frame one second in (or the middle of a shorter clip). Blocks; call it off the main thread.
    static func frame(of url: URL) -> CGImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        return blocking {
            let seconds = (try? await asset.load(.duration).seconds) ?? 0
            let t = CMTime(seconds: seconds.isFinite && seconds > 0 ? min(1, seconds / 2) : 0, preferredTimescale: 600)
            return try? await generator.image(at: t).image
        }
    }

    /// Runs an async job to completion from synchronous code.
    private static func blocking<T>(_ job: @escaping () async -> T?) -> T? {
        let box = ResultBox(), done = DispatchSemaphore(value: 0)
        Task.detached { box.value = await job(); done.signal() }
        done.wait()
        return box.value as? T
    }

    /// The most prominent line: the largest text. Can be an ad on busy pages, so it is only a fallback.
    public static func headline(from lines: [TextLine]) -> String? {
        lines.filter { $0.text.count >= 4 }.max { $0.height < $1.height }?.text
    }
}

private final class ResultBox: @unchecked Sendable { var value: Any? }
