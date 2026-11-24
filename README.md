# ShotNamer

A macOS menu bar app that renames your screenshots the moment you take them, so you can see **when**, **where from** and **what** at a glance.

```
Screenshot 2026-11-24 at 2.32.10 PM.png
        ↓
2026-11-24 14.32.10 - Safari - Quarterly Budget Report.png
        date & time      app         window / tab title
```

- **App name** – the app that was frontmost when you pressed the shortcut.
- **Title** – the title of the focused window (for browsers, the tab title), read via the Accessibility API.
- **OCR fallback** – optional, on-device (Apple Vision); used only when no window title is available.
- **Undo** – every rename is logged; "Undo last rename" restores the original name.
- **Private** – no network access, no analytics, nothing leaves your Mac.

Requires macOS 14 (Sonoma) or newer.

## Install

There is no notarized download yet, so build it yourself (needs Xcode or the Swift toolchain):

```sh
git clone https://github.com/DanielHodeib/ShotNamer.git
cd ShotNamer
scripts/install.sh            # builds and installs to /Applications, then starts it
```

Run `scripts/install.sh` again after pulling updates. (`scripts/build-app.sh` only builds `build/ShotNamer.app`.) "Launch at login" needs the app in `/Applications`.

> **Unsigned builds:** the app is ad-hoc signed, not notarized. If you download a prebuilt copy instead of building, macOS Gatekeeper will block it on first launch. Allow it in *System Settings › Privacy & Security* (the "Open Anyway" button shown after the blocked attempt). Building from source avoids this.

## Use

Take screenshots as usual (⌘⇧3, ⌘⇧4, ⌘⇧5). A camera icon in the menu bar shows:

| Item | What it does |
|---|---|
| Pause | Stop renaming without quitting |
| Add window / tab title | Put the focused window's title in the name (needs Accessibility permission) |
| Fallback: read text in image (OCR) | Off by default. Used only if there is no window title |
| Launch at login | Start automatically |
| Recent | Last five renamed files; click to reveal in Finder |
| Undo last rename | Restore the previous original filename |

### Permissions

- **Folder access.** The first time, macOS asks whether ShotNamer may access your Desktop (or wherever screenshots are saved). Allow it, otherwise nothing can be renamed. The menu shows an error if access is denied.
- **Accessibility.** Needed only to read window titles. macOS prompts when the app starts or when you switch "Add window / tab title" on; enable ShotNamer under *System Settings › Privacy & Security › Accessibility*. Without it the name is `date - app`. No Screen Recording permission is needed.
- After rebuilding from source the ad-hoc signature changes, so macOS may ask for folder access again.

### Privacy note

Window titles (and OCR text) become part of the **filename**; titles can contain page names, document names or message subjects. If your screenshot folder syncs (for example iCloud "Desktop & Documents"), that text syncs too, and it can show up in Finder, Spotlight and backups. Turn the title and OCR options off if your screenshots may contain sensitive material.

## Behaviour and limits

- Only screenshots **taken while the app runs** are renamed. Existing files are never touched.
- Recognised: PNG, JPG, HEIC and TIFF named like `Screenshot …`, `Screen Shot …` or the localized equivalents (German, French, Spanish, Dutch, Italian). Screen recordings (`.mov`) are ignored. A custom screenshot name prefix (`defaults write com.apple.screencapture name`) is not recognised yet.
- macOS does not store which app a screenshot came from. ShotNamer records which app was active over time and looks up the app active at the capture time (parsed from the filename). It is right in nearly all cases, but can be wrong if you switch apps within the same second.
- The window title is sampled once a second, so it matches the moment of capture even if you switch tab right after. Some apps expose no title; then the name is `date - app`.
- OCR (fallback) picks the *largest* confident text line, which can be an ad or banner on busy pages, so it is off by default.
- Names are capped (app 30 chars, text 50) and cleaned of `/ : \`. Duplicates get ` 2`, ` 3`.

## Develop

```sh
swift build          # debug build
swift test           # unit tests (Swift Testing)
SHOTNAMER_FOLDER=/tmp/shots .build/debug/ShotNamer   # watch a scratch folder instead of the real one
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how it is put together and [CHANGELOG.md](CHANGELOG.md) for releases.

## Roadmap

- Browser URL / domain as the source
- Custom name template
- Screen recordings
- App icon, Developer ID signing and notarization, downloadable releases

## License

[MIT](LICENSE)
