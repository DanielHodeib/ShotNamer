// Release signing for the self-updater (Ed25519, CryptoKit).
//   swift scripts/update-key.swift keygen <keyfile>        → creates the private key, prints the public key
//   swift scripts/update-key.swift sign <keyfile> <file>   → prints the base64 signature of <file>
import CryptoKit
import Foundation

func fail(_ s: String) -> Never { FileHandle.standardError.write(Data((s + "\n").utf8)); exit(1) }
let a = CommandLine.arguments
guard a.count >= 3 else { fail("usage: keygen <keyfile> | sign <keyfile> <file>") }
let keyURL = URL(fileURLWithPath: a[2])
switch a[1] {
case "keygen":
    guard !FileManager.default.fileExists(atPath: keyURL.path) else { fail("\(keyURL.path) exists; refusing to overwrite") }
    let key = Curve25519.Signing.PrivateKey()
    try FileManager.default.createDirectory(at: keyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: keyURL.path, contents: Data(key.rawRepresentation.base64EncodedString().utf8),
                                   attributes: [.posixPermissions: 0o600])
    print(key.publicKey.rawRepresentation.base64EncodedString())
case "sign":
    guard a.count == 4 else { fail("usage: sign <keyfile> <file>") }
    guard let b64 = try? String(contentsOf: keyURL, encoding: .utf8),
          let raw = Data(base64Encoded: b64.trimmingCharacters(in: .whitespacesAndNewlines)),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else { fail("can't read key \(keyURL.path)") }
    let data = try Data(contentsOf: URL(fileURLWithPath: a[3]))
    print(try key.signature(for: data).base64EncodedString())
default: fail("unknown command \(a[1])")
}
