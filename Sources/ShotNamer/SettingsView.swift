import SwiftUI
import ShotNamerCore

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("nameTemplate") private var template = Template.defaultName
    @AppStorage("useSite") private var useSite = true
    @AppStorage("useTitle") private var useTitle = true
    @AppStorage("useOCR") private var useOCR = false
    @AppStorage("searchable") private var searchable = true
    @AppStorage("useBrowserURL") private var useBrowserURL = false
    @AppStorage("textSites") private var textSites = false
    @AppStorage("redact") private var redact = false
    @AppStorage("sortMode") private var sortMode = SortMode.off.rawValue
    @AppStorage("sortRoot") private var sortRoot = ""

    private var preview: String {
        FileNamer.makeName(date: Date(), app: "Safari", site: "github.com", text: "Pull requests", ext: "png", template: template)
    }

    var body: some View {
        Form {
            Section("File name") {
                TextField("Template", text: $template)
                    .textFieldStyle(.roundedBorder)
                Text(preview).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                if !Template.isValidName(template) {
                    Text("Needs {date} or {time}, and must not start like a normal screenshot name. The default is used instead.")
                        .font(.caption).foregroundStyle(.red)
                }
                Text("Tokens: {date} {time} {app} {site} {title}. Missing parts disappear with their separator.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Reset to default") { template = Template.defaultName }
            }
            Section("What goes into the name") {
                Toggle("Website (read from the address bar in browser screenshots)", isOn: $useSite)
                Toggle("Ask the browser for the page address (Safari, Chrome, Brave, Edge, Arc, Vivaldi, Opera)", isOn: $useBrowserURL)
                Text("For screenshots that don't show the address bar. Asks macOS for Automation permission the first time. Firefox can't be asked.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Guess the site from a header line like “GitHub” (experimental)", isOn: $textSites)
                Toggle("Window / tab title (needs Accessibility permission)", isOn: Binding(get: { useTitle }, set: {
                    useTitle = $0
                    if $0 && !WindowTitle.isTrusted { WindowTitle.requestPermission() }
                }))
                if useTitle && !WindowTitle.isTrusted {
                    Button("Grant Accessibility…") { WindowTitle.requestPermission() }
                }
                Toggle("Fallback: biggest text in the image when there is no title", isOn: $useOCR)
            }
            Section("Privacy") {
                Toggle("Black out e-mails, IBANs, card numbers, keys and passwords", isOn: $redact)
                Text("Best effort: found with on-device OCR, so it can miss things. The image file is changed; the original is kept for 7 days and \"Undo last rename\" restores it. Videos are not redacted.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Search") {
                Toggle("Make the text in screenshots searchable in Spotlight", isOn: $searchable)
                Text("Stored on-device in the file's Finder comment. Find a screenshot by typing a word from it into Spotlight.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Folders") {
                Picker("Sort screenshots", selection: $sortMode) {
                    ForEach(SortMode.allCases) { Text($0.label).tag($0.rawValue) }
                }
                if sortMode != SortMode.off.rawValue || !sortRoot.isEmpty {
                    HStack {
                        Text("Into: \(sortRoot.isEmpty ? model.folder.path : sortRoot)")
                            .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                        Spacer()
                        Button("Choose…") { chooseFolder() }
                        if !sortRoot.isEmpty { Button("Reset") { sortRoot = "" } }
                    }
                }
                Text("Undo moves a file back and removes folders it created.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .padding(.vertical, 8)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url { sortRoot = url.path }
    }
}
