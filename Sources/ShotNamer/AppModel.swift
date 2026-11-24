import AppKit
import ServiceManagement
import ShotNamerCore

@MainActor
final class AppModel: ObservableObject {
    @Published var recent: [URL] = []
    @Published var status: String?

    let folder: URL
    private let log: UndoLog
    private var history = AppHistory()
    private var titles = AppHistory(capacity: 600) // window title over time; "" = none
    private var lastTitle: String?
    private var written: Set<String> = [] // files this app produced; never process them again
    private var watcher: FolderWatcher?
    private let ignoredBundles: Set<String> = ["com.apple.screencaptureui", Bundle.main.bundleIdentifier ?? ""]

    init() {
        UserDefaults.standard.register(defaults: ["useOCR": false, "useTitle": true, "useSite": true])
        // SHOTNAMER_FOLDER lets tests and debugging point the app at a scratch folder.
        if let p = ProcessInfo.processInfo.environment["SHOTNAMER_FOLDER"] {
            folder = URL(fileURLWithPath: p, isDirectory: true)
        } else {
            folder = Renamer.screenshotFolder()
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShotNamer", isDirectory: true)
        log = UndoLog(url: support.appendingPathComponent("renames.json"))

        // Seed with the current app, then follow activations.
        if let front = NSWorkspace.shared.frontmostApplication { note(front) }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { self?.note(app) }
        }

        if UserDefaults.standard.bool(forKey: "useTitle"), !WindowTitle.isTrusted { WindowTitle.requestPermission() }
        // Sample the focused window title once a second so the right one is known at capture time.
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sampleTitle() }
        }

        watcher = FolderWatcher(folder: folder) { [weak self] url in
            Task { @MainActor in await self?.handle(url) }
        }
        if watcher?.start() != true {
            status = "Can't read \(folder.lastPathComponent). Allow folder access in System Settings › Privacy & Security."
        }
    }

    private func note(_ app: NSRunningApplication) {
        guard let name = app.localizedName, !ignoredBundles.contains(app.bundleIdentifier ?? "") else { return }
        history.record(name: name, at: Date())
    }

    private func sampleTitle() {
        guard UserDefaults.standard.bool(forKey: "useTitle"),
              let app = NSWorkspace.shared.frontmostApplication, let name = app.localizedName,
              !ignoredBundles.contains(app.bundleIdentifier ?? "") else { return }
        let title = WindowTitle.focused(pid: app.processIdentifier, appName: name) ?? ""
        guard title != lastTitle else { return }
        lastTitle = title
        titles.record(name: title, at: Date())
    }

    private func handle(_ url: URL) async {
        guard !UserDefaults.standard.bool(forKey: "paused"), await waitUntilStable(url) else { return }
        // Checked after the wait: our own rename finishes (and is recorded) well within it.
        guard !written.contains(url.path) else { return }
        let date = Renamer.captureDate(of: url)
        let app = history.app(at: date)
        let title = UserDefaults.standard.bool(forKey: "useTitle") ? titles.app(at: date) : nil
        let useOCR = UserDefaults.standard.bool(forKey: "useOCR")
        let useSite = UserDefaults.standard.bool(forKey: "useSite")
        let template = UserDefaults.standard.string(forKey: "nameTemplate") ?? Template.defaultName
        let log = self.log
        do {
            // OCR is slow; keep it off the main thread.
            let new = try await Task.detached {
                try Renamer.rename(url, date: date, app: app, title: title, useSite: useSite, useOCR: useOCR, template: template, log: log)
            }.value
            written.insert(new.path)
            recent = Array(([new] + recent).prefix(5))
            status = nil
        } catch {
            status = "Rename failed: \(error.localizedDescription)"
        }
    }

    /// macOS may still be writing the file when it appears; wait until its size stops changing.
    private func waitUntilStable(_ url: URL) async -> Bool {
        var last = -1
        for _ in 0..<20 {
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attrs?[.size] as? NSNumber)?.intValue ?? -1 // .size is UInt64, `as? Int` would fail
            if size > 0 && size == last { return true }
            last = size
            try? await Task.sleep(for: .milliseconds(500))
        }
        return false
    }

    func undoLast() {
        do {
            if let restored = try Renamer.undoLast(log: log) {
                recent.removeAll { !FileManager.default.fileExists(atPath: $0.path) }
                status = "Restored \(restored.lastPathComponent)"
            } else {
                status = "Nothing to undo"
            }
        } catch {
            status = "Undo failed: \(error.localizedDescription)"
        }
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                status = "Launch at login failed (move the app to /Applications first): \(error.localizedDescription)"
            }
            objectWillChange.send()
        }
    }
}
