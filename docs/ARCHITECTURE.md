# Architecture

SwiftPM package, two targets plus tests. No Xcode project; `scripts/build-app.sh` wraps the binary in an `.app` bundle.

```
Sources/
  ShotNamerCore/        pure logic, no UI, unit-tested
    FileNamer.swift     is-it-a-screenshot, parse capture time, sanitize, build name, pick unique path
    AppHistory.swift    "which app was frontmost at time T"
    TextRecognizer.swift  Vision OCR → most prominent line
    UndoLog.swift       JSON list of renames in ~/Library/Application Support/ShotNamer/
    Renamer.swift       screenshot folder lookup, rename + log, undo
  ShotNamer/            the menu bar app (SwiftUI MenuBarExtra)
    ShotNamerApp.swift  menu UI
    AppModel.swift      wires watcher, app-activation tracking, rename, undo
    FolderWatcher.swift DispatchSource on the folder; reports new screenshot files
Tests/ShotNamerCoreTests/
Resources/Info.plist    LSUIElement (no Dock icon), folder-access usage strings
scripts/build-app.sh    swift build → .app → ad-hoc codesign
```

## Flow

1. **Start.** `AppModel` resolves the screenshot folder (`com.apple.screencapture location`, else `~/Desktop`; `SHOTNAMER_FOLDER` overrides for tests), snapshots the existing file names so they are never touched, and starts listening to `NSWorkspace.didActivateApplicationNotification`. The current frontmost app seeds `AppHistory`.
2. **Detect.** `FolderWatcher` gets a directory `.write` event, lists the folder and diffs against the names it has seen. New names that pass `FileNamer.isScreenshot` are reported.
3. **Settle.** macOS may still be writing the file, so `AppModel.waitUntilStable` waits until its size stops changing (500 ms polls, 10 s cap).
4. **Identify.** Capture time comes from the digits in the filename (works in any locale, 12 h or 24 h). The file's own creation date is only a fallback, because the floating screenshot thumbnail can delay writing the file by seconds. `AppHistory.app(at:)` returns the app active at that time. `com.apple.screencaptureui` and ShotNamer itself are never recorded.
5. **Rename.** OCR (off the main thread, optional) → `FileNamer.makeName` → `uniqueURL` → move → append to `UndoLog`.
6. **Undo.** `Renamer.undoLast` pops the newest log entry and moves the file back, refusing to overwrite an existing file.

## Decisions

- **No rename loops.** Renamed files start with a date, never a screenshot prefix; a test enforces this.
- **Frontmost-app history instead of window titles.** Window titles need Screen Recording permission; app names need none.
- **On-device OCR only.** Apple Vision; no network code anywhere.
- **Swift 5 language mode** inside a `swift-tools-version:6.0` package, to avoid strict-concurrency churn for a small app. Revisit when moving to Swift 6 mode.
- **Ad-hoc signing.** No Developer ID yet, so no notarization; see README for the Gatekeeper consequence.

## Testing

`swift test` covers naming, locale parsing, the no-loop invariant, app lookup, rename/undo/collisions. The folder watcher and UI are checked by running the app on a scratch folder:

```sh
mkdir /tmp/shots
SHOTNAMER_FOLDER=/tmp/shots build/ShotNamer.app/Contents/MacOS/ShotNamer &
cp some.png "/tmp/shots/Screenshot 2026-11-24 at 2.32.10 PM.png"
ls /tmp/shots
```
