import Foundation
import Vision

/// On-device OCR (Apple Vision). Nothing leaves the Mac.
public enum TextRecognizer {
    /// The most prominent line of text: the largest, confidently-read line is usually the title/heading.
    public static func headline(of url: URL) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        do { try VNImageRequestHandler(url: url).perform([request]) } catch { return nil }
        let best = (request.results ?? [])
            .compactMap { o -> (String, CGFloat)? in
                guard let c = o.topCandidates(1).first, c.confidence > 0.5, c.string.count >= 4 else { return nil }
                return (c.string, o.boundingBox.height)
            }
            .max { $0.1 < $1.1 }
        return best?.0
    }
}
