import SwiftUI

@main
struct ShotNamerApp: App {
    @StateObject private var model = AppModel()
    @AppStorage("paused") private var paused = false
    @AppStorage("useOCR") private var useOCR = false
    @AppStorage("useTitle") private var useTitle = true
    @AppStorage("useSite") private var useSite = true

    var body: some Scene {
        MenuBarExtra("ShotNamer", systemImage: paused ? "camera.metering.unknown" : "camera.viewfinder") {
            Text("Watching \(model.folder.lastPathComponent)")
            if let status = model.status { Text(status) }
            Divider()
            Toggle("Pause", isOn: $paused)
            Toggle("Detect website (reads the address bar)", isOn: $useSite)
            Toggle("Add window / tab title", isOn: Binding(get: { useTitle }, set: {
                useTitle = $0
                if $0 && !WindowTitle.isTrusted { WindowTitle.requestPermission() }
            }))
            if useTitle && !WindowTitle.isTrusted {
                Button("Grant Accessibility for titles…") { WindowTitle.requestPermission() }
            }
            Toggle("Fallback: add biggest text in image", isOn: $useOCR)
            Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 }))
            Divider()
            if !model.recent.isEmpty {
                Text("Recent (click to reveal)")
                ForEach(model.recent, id: \.self) { url in
                    Button(url.lastPathComponent) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
                Button("Undo last rename") { model.undoLast() }
                Divider()
            }
            Button("Open screenshot folder") { NSWorkspace.shared.open(model.folder) }
            Button("Quit ShotNamer") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
