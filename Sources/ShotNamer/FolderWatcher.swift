import Foundation
import ShotNamerCore

/// Calls `onNew` for each screenshot file that appears in `folder` after start.
final class FolderWatcher {
    private let folder: URL
    private let onNew: (URL) -> Void
    private var source: DispatchSourceFileSystemObject?
    private var seen: Set<String> = []

    init(folder: URL, onNew: @escaping (URL) -> Void) {
        self.folder = folder
        self.onNew = onNew
    }

    /// Returns false if the folder can't be opened (missing, or no permission).
    func start() -> Bool {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return false }
        seen = Set(names) // existing files are never touched
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return false }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        src.setEventHandler { [weak self] in self?.scan() }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
        return true
    }

    private func scan() {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
        let current = Set(names)
        for name in current.subtracting(seen) where FileNamer.isCapture(filename: name) {
            onNew(folder.appendingPathComponent(name))
        }
        seen = current
    }
}
