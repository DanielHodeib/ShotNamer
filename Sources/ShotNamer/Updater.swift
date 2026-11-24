import AppKit
import ShotNamerCore

/// Installs new GitHub releases: download, check the Ed25519 signature and the app inside, swap the bundle, relaunch.
@MainActor
final class Updater {
    static let repo = "DanielHodeib/ShotNamer"
    private let api: URL
    private let testing: Bool // SHOTNAMER_UPDATE_API points at a local test server; plain http is allowed only then
    private let isBusy: () -> Bool
    private var checking = false

    init(isBusy: @escaping () -> Bool) {
        self.isBusy = isBusy
        if let o = ProcessInfo.processInfo.environment["SHOTNAMER_UPDATE_API"], let u = URL(string: o) {
            api = u; testing = true
        } else {
            api = URL(string: "https://api.github.com/repos/\(Updater.repo)/releases/latest")!; testing = false
        }
    }

    static var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }

    /// Checks 30 s after launch, then every 6 hours, while "Install updates automatically" is on.
    func startSchedule(report: @escaping (String?) -> Void) {
        let tick = { [weak self] in
            guard let self, UserDefaults.standard.bool(forKey: "autoUpdate") else { return }
            Task { if let msg = await self.check(manual: false) { report(msg) } }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { tick() }
        Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { _ in MainActor.assumeIsolated { tick() } }
    }

    /// Returns a status line, or nil when there is nothing worth saying (automatic check, no update).
    /// On success the app quits and the new version starts.
    func check(manual: Bool) async -> String? {
        guard !checking else { return manual ? "Already checking for updates…" : nil }
        checking = true
        defer { checking = false }
        do {
            return try await run(manual: manual)
        } catch {
            return "Update failed: \(error.localizedDescription)"
        }
    }

    private struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ s: String) { errorDescription = s }
    }

    private func run(manual: Bool) async throws -> String? {
        let bundle = Bundle.main.bundleURL
        guard bundle.pathExtension == "app", !bundle.path.contains("/AppTranslocation/"),
              FileManager.default.isWritableFile(atPath: bundle.deletingLastPathComponent().path) else {
            return manual ? "Updates need the app in /Applications (or another folder you can write to)." : nil
        }

        var req = URLRequest(url: api, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (body, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        // 404: no release yet, or the repository is private. Not an error worth showing every 6 hours.
        if code == 404 { return manual ? "No published release found." : nil }
        guard code == 200 else { throw Failure("GitHub answered \(code)") }
        let release = try JSONDecoder().decode(Update.Release.self, from: body)

        let current = Self.currentVersion
        guard !release.draft, !release.prerelease, Update.isNewer(release.version, than: current) else {
            return manual ? "ShotNamer \(current) is up to date." : nil
        }
        guard let zipURL = release.asset(Update.zipName), let sigURL = release.asset(Update.signatureName),
              testing || (zipURL.scheme == "https" && sigURL.scheme == "https") else {
            throw Failure("release \(release.version) has no signed download")
        }

        guard (release.size(Update.zipName) ?? 0) <= Update.maxZipBytes else { throw Failure("release \(release.version) is too large") }
        let (zip, _) = try await URLSession.shared.data(from: zipURL)
        guard zip.count <= Update.maxZipBytes else { throw Failure("release \(release.version) is too large") }
        let (sig, _) = try await URLSession.shared.data(from: sigURL)
        guard Update.verify(zip, signatureBase64: String(decoding: sig, as: UTF8.self), publicKeyBase64: Update.publicKey) else {
            throw Failure("the download of \(release.version) is not signed by the ShotNamer key; not installed")
        }

        // Same volume as the app, so the final swap is an atomic rename.
        let staging = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                  appropriateFor: bundle, create: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        let zipFile = staging.appendingPathComponent(Update.zipName)
        try zip.write(to: zipFile)
        let out = staging.appendingPathComponent("unpacked", isDirectory: true)
        let newApp = out.appendingPathComponent("ShotNamer.app", isDirectory: true)
        try await Self.exec("/usr/bin/ditto", ["-x", "-k", zipFile.path, out.path]) // ditto keeps symlinks and the signature
        guard Update.isAcceptable(app: newApp, releaseVersion: release.version,
                                  bundleID: Bundle.main.bundleIdentifier ?? "", current: current) else {
            throw Failure("the app inside \(release.version) has the wrong name or version; not installed")
        }
        try await Self.exec("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp.path])

        // Never quit in the middle of a rename (redaction swaps files). Recordings can take minutes to finish.
        var waited = 0
        while isBusy(), waited < 900 { try await Task.sleep(for: .seconds(1)); waited += 1 }
        guard !isBusy() else { return manual ? "Update postponed: a rename is still running." : nil }

        _ = try FileManager.default.replaceItemAt(bundle, withItemAt: newApp)
        try? FileManager.default.removeItem(at: staging) // terminate() below exits before the defer would run
        relaunch(bundle)
        return nil
    }

    /// Starts the new copy once this process has exited; `open` while we still run would just re-activate us.
    private func relaunch(_ app: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$2\"",
                       "sh", String(ProcessInfo.processInfo.processIdentifier), app.path]
        try? p.run()
        NSApp.terminate(nil)
    }

    private static func exec(_ tool: String, _ args: [String]) async throws {
        try await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: tool)
            p.arguments = args
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try p.run()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else {
                throw Failure("\((tool as NSString).lastPathComponent) failed (\(p.terminationStatus))")
            }
        }.value
    }
}
