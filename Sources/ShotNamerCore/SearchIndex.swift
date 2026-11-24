import Foundation

/// Makes a screenshot findable in Spotlight by its text: the OCR text goes into the Finder comment
/// (`kMDItemFinderComment`), which Spotlight indexes. The file name stays short.
public enum SearchIndex {
    static let attribute = "com.apple.metadata:kMDItemFinderComment"
    static let maxLength = 4000

    public static func comment(from lines: [TextLine]) -> String {
        var seen = Set<String>()
        let text = lines.map(\.text).filter { seen.insert($0).inserted }.joined(separator: " ")
        return String(text.prefix(maxLength))
    }

    public static func write(_ text: String, to url: URL) throws {
        guard !text.isEmpty else { return }
        let data = try PropertyListSerialization.data(fromPropertyList: text, format: .binary, options: 0)
        let rc = data.withUnsafeBytes { setxattr(url.path, attribute, $0.baseAddress, data.count, 0, 0) }
        if rc != 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    /// Reads the comment back (used by tests).
    public static func read(from url: URL) -> String? {
        let size = getxattr(url.path, attribute, nil, 0, 0, 0)
        guard size > 0 else { return nil }
        var data = Data(count: size)
        let n = data.withUnsafeMutableBytes { getxattr(url.path, attribute, $0.baseAddress, size, 0, 0) }
        guard n > 0 else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? String
    }
}
