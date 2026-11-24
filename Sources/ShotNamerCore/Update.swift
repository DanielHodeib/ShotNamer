import CryptoKit
import Foundation

/// Pure parts of the self-updater: GitHub release parsing, version comparison and signature verification.
public enum Update {
    public static let zipName = "ShotNamer.zip"
    public static let signatureName = "ShotNamer.zip.sig"
    /// The zip is checked in memory; a bigger asset is refused before download (the app is a few MB).
    public static let maxZipBytes = 100_000_000
    /// Releases must be signed with the matching private key (kept off the repo, see scripts/release.sh).
    /// A constant, not an Info.plist entry, so an edited plist can't switch verification off.
    public static let publicKey = "plgczhtz0mQgLsjxe2yWfR6+h9MRDK2h90t+vXHI6Bs="

    public struct Release: Decodable {
        public struct Asset: Decodable {
            public let name: String
            public let browser_download_url: URL
            public let size: Int?
        }
        public let tag_name: String
        public let draft: Bool
        public let prerelease: Bool
        public let assets: [Asset]

        public var version: String { tag_name.hasPrefix("v") ? String(tag_name.dropFirst()) : tag_name }
        public func asset(_ name: String) -> URL? { assets.first { $0.name == name }?.browser_download_url }
        public func size(_ name: String) -> Int? { assets.first { $0.name == name }?.size }
    }

    /// "v1.2.10" → [1, 2, 10]; nil if it is not a plain dotted version.
    static func components(_ s: String) -> [Int]? {
        let parts = (s.hasPrefix("v") ? String(s.dropFirst()) : s).split(separator: ".").map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        return parts.map { $0! }
    }

    /// True only for a strictly newer, well-formed version (no downgrades, no garbage tags).
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard var a = components(candidate), var b = components(current) else { return false }
        let n = max(a.count, b.count)
        a += Array(repeating: 0, count: n - a.count); b += Array(repeating: 0, count: n - b.count)
        return a.lexicographicallyPrecedes(b) == false && a != b
    }

    /// Ed25519 check of the downloaded zip against the public key built into the app.
    public static func verify(_ data: Data, signatureBase64: String, publicKeyBase64: String) -> Bool {
        guard let sig = Data(base64Encoded: signatureBase64.trimmingCharacters(in: .whitespacesAndNewlines)),
              let raw = Data(base64Encoded: publicKeyBase64),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw) else { return false }
        return key.isValidSignature(sig, for: data)
    }

    /// The unpacked app must be ShotNamer, exactly the release's version, and newer than the running one.
    /// Binds the signed zip to its tag: an old signed zip re-uploaded under a new tag is refused.
    public static func isAcceptable(app: URL, releaseVersion: String, bundleID: String, current: String) -> Bool {
        guard let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
              info["CFBundleIdentifier"] as? String == bundleID,
              let v = info["CFBundleShortVersionString"] as? String else { return false }
        return v == releaseVersion && isNewer(v, than: current)
    }
}
