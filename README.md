# ShotNamer

A macOS menu bar app that renames your screenshots the moment you take them, so you can see **when**, **where from** and **what** at a glance.

```
Screenshot 2026-11-24 at 2.32.10 PM.png
        ↓
2026-11-24 14.32.10 - Safari - Quarterly Budget Report.png
        date & time      app         biggest text in the image
```

- **App name** – the app that was frontmost when you pressed the shortcut.
- **Text** – on-device OCR (Apple Vision) picks the most prominent line of text, usually a title.
- **Undo** – every rename is logged; "Undo last rename" restores the original name.
- **Private** – no network access, no analytics, nothing leaves your Mac.

Requires macOS 14 (Sonoma) or newer.

## Install

There is no notarized download yet, so build it yourself (needs Xcode or the Swift toolchain):

```sh
git clone https://github.com/DanielHodeib/ShotNamer.git
cd ShotNamer
scripts/build-app.sh          # add --native to skip the Intel slice
open build/ShotNamer.app
```

Move `build/ShotNamer.app` to `/Applications` if you want "Launch at login" to work.

> **Unsigned builds:** the app is ad-hoc signed, not notarized. If you download a prebuilt copy instead of building, macOS Gatekeeper will block it on first launch. Allow it in *System Settings › Privacy & Security* (the "Open Anyway" button shown after the blocked attempt). Building from source avoids this.

## Use

Take screenshots as usual (⌘⇧3, ⌘⇧4, ⌘⇧5). A camera icon in the menu bar shows:

| Item | What it does |
|---|---|
| Pause | Stop renaming without quitting |
| Read text in screenshot (OCR) | Add the headline text to the name. Turn off for `date - app` only |
| Launch at login | Start automatically |
| Recent | Last five renamed files; click to reveal in Finder |
| Undo last rename | Restore the previous original filename |

### Permissions

- **Folder access.** The first time, macOS asks whether ShotNamer may access your Desktop (or wherever screenshots are saved). Allow it, otherwise nothing can be renamed. The menu shows an error if access is denied.
- No Screen Recording or Accessibility permission is needed.
- After rebuilding from source the ad-hoc signature changes, so macOS may ask for folder access again.

### Privacy note

OCR text becomes part of the **filename**. If your screenshot folder syncs (for example iCloud "Desktop & Documents"), that text syncs too, and it can show up in Finder, Spotlight and backups. Turn OCR off if your screenshots may contain secrets.

## Behaviour and limits

- Only screenshots **taken while the app runs** are renamed. Existing files are never touched.
- Recognised: PNG, JPG, HEIC and TIFF named like `Screenshot …`, `Screen Shot …` or the localized equivalents (German, French, Spanish, Dutch, Italian). Screen recordings (`.mov`) are ignored. A custom screenshot name prefix (`defaults write com.apple.screencapture name`) is not recognised yet.
- macOS does not store which app a screenshot came from. ShotNamer records which app was active over time and looks up the app active at the capture time (parsed from the filename). It is right in nearly all cases, but can be wrong if you switch apps within the same second.
- OCR picks the *largest* confident text line. It can choose the wrong line on busy screens.
- Names are capped (app 30 chars, text 50) and cleaned of `/ : \`. Duplicates get ` 2`, ` 3`.

## Develop

```sh
swift build          # debug build
swift test           # unit tests (Swift Testing)
SHOTNAMER_FOLDER=/tmp/shots .build/debug/ShotNamer   # watch a scratch folder instead of the real one
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how it is put together and [CHANGELOG.md](CHANGELOG.md) for releases.

## Roadmap

- Browser tab title / URL as the source (needs Automation permission)
- Custom name template
- Screen recordings
- App icon, Developer ID signing and notarization, downloadable releases

## License

[MIT](LICENSE)
