import SwiftUI

@main
struct ShotNamerApp: App {
    @StateObject private var model = AppModel()
    @AppStorage("paused") private var paused = false

    var body: some Scene {
        MenuBarExtra("ShotNamer", systemImage: paused ? "camera.metering.unknown" : "camera.viewfinder") {
            MenuContent().environmentObject(model)
        }
        Window("ShotNamer Settings", id: "settings") {
            SettingsView().environmentObject(model)
        }
        .windowResizability(.contentSize)
    }
}

struct MenuContent: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @AppStorage("paused") private var paused = false

    var body: some View {
        Text("Watching \(model.folder.lastPathComponent)")
        if let status = model.status { Text(status) }
        Divider()
        Toggle("Pause", isOn: $paused)
        Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 }))
        Button("Settings…") {
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true) // a menu-bar-only app otherwise opens windows behind others
        }
        .keyboardShortcut(",")
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
