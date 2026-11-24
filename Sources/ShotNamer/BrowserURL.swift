import Foundation

/// Asks a scriptable browser for the address of its front tab (AppleScript). Needs the one-time Automation permission.
/// Only call this for the frontmost browser: `tell application` would otherwise launch a browser that is not running.
enum BrowserURL {
    /// bundle id → is Safari-style (`front document`) rather than Chromium-style (`active tab of front window`).
    static let supported: [String: Bool] = [
        "com.apple.Safari": true,
        "com.google.Chrome": false, "com.brave.Browser": false, "com.microsoft.edgemac": false,
        "company.thebrowser.Browser": false, "com.vivaldi.Vivaldi": false, "com.operasoftware.Opera": false,
        "org.chromium.Chromium": false,
    ]

    enum Result { case url(String), none, denied }

    static func current(bundleID: String) -> Result {
        guard let safari = supported[bundleID] else { return .none }
        let body = safari ? "URL of front document" : "URL of active tab of front window"
        var error: NSDictionary?
        let out = NSAppleScript(source: "with timeout of 1 seconds\ntell application id \"\(bundleID)\" to return \(body)\nend timeout")?.executeAndReturnError(&error)
        // -1743: not allowed. -1712 (timeout, e.g. a hung browser) just gives no URL this second.
        if let code = error?[NSAppleScript.errorNumber] as? Int { return code == -1743 ? .denied : .none }
        return out?.stringValue.map { .url($0) } ?? .none
    }
}
