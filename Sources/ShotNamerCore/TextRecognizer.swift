import Foundation
import Vision

/// One recognised line of text. `y` is the vertical centre (0 = bottom, 1 = top), `height` the relative text height.
public struct TextLine: Equatable {
    public let text: String
    public let y: Double
    public let height: Double
    public init(text: String, y: Double, height: Double) { self.text = text; self.y = y; self.height = height }
}

/// On-device OCR (Apple Vision). Nothing leaves the Mac.
public enum TextRecognizer {
    public static func lines(of url: URL) -> [TextLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false // URLs and names are not dictionary words
        request.automaticallyDetectsLanguage = true
        do { try VNImageRequestHandler(url: url).perform([request]) } catch { return [] }
        return (request.results ?? []).compactMap { o in
            guard let c = o.topCandidates(1).first, c.confidence > 0.4 else { return nil }
            return TextLine(text: c.string, y: o.boundingBox.midY, height: o.boundingBox.height)
        }
    }

    /// The most prominent line: the largest text. Can be an ad on busy pages, so it is only a fallback.
    public static func headline(from lines: [TextLine]) -> String? {
        lines.filter { $0.text.count >= 4 }.max { $0.height < $1.height }?.text
    }
}
