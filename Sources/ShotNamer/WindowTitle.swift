import ApplicationServices

/// Title of an app's focused window via the Accessibility API (needs the Accessibility permission).
enum WindowTitle {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that sends the user to Privacy & Security › Accessibility.
    static func requestPermission() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// Browsers append their name ("Page - Brave"); drop it, the app name is in the filename already.
    static func focused(pid: pid_t, appName: String) -> String? {
        guard isTrusted else { return nil }
        let app = AXUIElementCreateApplication(pid)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &value) == .success,
              var title = value as? String else { return nil }
        for suffix in [" - \(appName)", " – \(appName)", " - \(appName.replacingOccurrences(of: " Browser", with: ""))"]
        where title.hasSuffix(suffix) {
            title.removeLast(suffix.count)
        }
        return title.isEmpty ? nil : title
    }
}
