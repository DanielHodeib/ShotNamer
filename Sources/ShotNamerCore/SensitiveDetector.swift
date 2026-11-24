import Foundation

public struct SensitiveMatch {
    public let range: Range<String.Index>
    public let kind: String
}

/// Finds text that should not end up in a screenshot you share: e-mail addresses, IBANs, card numbers,
/// API keys / tokens and "password: …" values. Best effort on OCR text: it can miss things (OCR errors,
/// a value split over two lines) and it can flag harmless text. It is a safety net, not a guarantee.
public enum SensitiveDetector {
    private static func re(_ p: String, _ o: NSRegularExpression.Options = []) -> NSRegularExpression {
        try! NSRegularExpression(pattern: p, options: o)
    }

    private static let email = re(#"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, .caseInsensitive)
    // Structure + known country only: an OCR misread digit must not let a real IBAN through, so no checksum test.
    private static let iban = re(#"\b(?:AT|DE|CH|LI|FR|ES|IT|NL|BE|LU|GB|IE|PL|CZ|HU|SK|SI|HR|PT|DK|SE|NO|FI|GR|RO|BG|EE|LV|LT|MT|CY|IS)\d{2}(?: ?[A-Z0-9]{3,4}){3,8}\b"#)
    private static let cardGrouped = re(#"\b\d{4}[ -]\d{4,6}[ -]\d{4,5}(?:[ -]\d{1,4})?\b"#)
    private static let cardPlain = re(#"\b\d{13,19}\b"#)
    private static let tokenPrefixes = re(#"\b(?:sk-[A-Za-z0-9_-]{20,}|sk_live_\w{16,}|pk_live_\w{16,}|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_\w{30,}|xox[baprs]-[\w-]{10,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{30,}|eyJ[\w-]{10,}\.[\w-]{10,}\.[\w-]{10,})"#)
    private static let bearer = re(#"\bbearer\s+([A-Za-z0-9._~+/=-]{16,})"#, .caseInsensitive)
    private static let labelled = re(#"\b(?:password|passwort|passwd|pwd|kennwort|secret|token|api[_ -]?key|apikey|private[_ -]?key)\b\s*[:=]\s*(\S+)"#, .caseInsensitive)

    static func luhn(_ digits: String) -> Bool {
        var sum = 0
        for (i, ch) in digits.reversed().enumerated() {
            guard var d = ch.wholeNumberValue else { return false }
            if i % 2 == 1 { d *= 2; if d > 9 { d -= 9 } }
            sum += d
        }
        return sum % 10 == 0
    }

    public static func matches(in text: String) -> [SensitiveMatch] {
        let full = NSRange(text.startIndex..., in: text)
        var out: [SensitiveMatch] = []
        // Earlier kinds win: an IBAN's digit groups must not also be reported as a card number.
        func add(_ r: NSRange, _ kind: String) {
            guard let rr = Range(r, in: text), !out.contains(where: { $0.range.overlaps(rr) }) else { return }
            out.append(.init(range: rr, kind: kind))
        }
        for m in email.matches(in: text, range: full) { add(m.range, "e-mail") }
        for m in iban.matches(in: text, range: full) { add(m.range, "IBAN") }
        for m in cardGrouped.matches(in: text, range: full) { add(m.range, "card number") }
        for m in cardPlain.matches(in: text, range: full) {
            if let r = Range(m.range, in: text), luhn(String(text[r])) { add(m.range, "card number") }
        }
        for m in tokenPrefixes.matches(in: text, range: full) { add(m.range, "key / token") }
        for m in bearer.matches(in: text, range: full) { add(m.range(at: 1), "key / token") }
        for m in labelled.matches(in: text, range: full) { add(m.range(at: 1), "password / secret") }
        return out
    }

    public static func contains(_ text: String) -> Bool { !matches(in: text).isEmpty }

    /// The text with every match removed (used for file names and the Spotlight comment).
    public static func scrub(_ text: String) -> String {
        let ranges = matches(in: text).map(\.range).sorted { $0.lowerBound < $1.lowerBound }
        var out = "", cursor = text.startIndex
        for r in ranges where r.lowerBound >= cursor {
            out += text[cursor..<r.lowerBound]
            cursor = r.upperBound
        }
        out += text[cursor...]
        return out.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
