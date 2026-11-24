<p align="center"><img src="docs/icon.png" width="128" alt="ShotNamer icon"></p>

# ShotNamer

A macOS menu bar app that renames your screenshots the moment you take them, so you can see **when**, **where from** and **what** at a glance.

```
Screenshot 2026-11-24 at 2.32.10 PM.png
        ↓
2026-11-24 14.32.10 - Safari - github.com - Pull requests.png
        date & time      app      website     window / tab title
```

- **App name** – the app that was frontmost when you pressed the shortcut.
- **Website** – for browser screenshots, the site shown in the address bar (`github.com`, `willhaben.at`), read from the image with on-device OCR. No permission needed.
- **Title** – the title of the focused window (for browsers, the tab title), read via the Accessibility API.
- **Biggest-text fallback** – optional; used only when no window title is available.
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
| Launch at login | Start automatically |
| Settings… | File name template and what goes into the name (see below) |
| Recent | Last five renamed files; click to reveal in Finder |
| Undo last rename | Restore the previous original filename |

### Settings

- **File name template.** Default `{date} {time} - {app} - {site} - {title}`. Tokens: `{date}` `{time}` `{app}` `{site}` `{title}`. A part that is missing (no site, say) disappears together with the separator before it. Example: `{app} · {date} {time}` → `Safari · 2026-11-24 14.32.10.png`. The template must contain `{date}` or `{time}` and must not produce names that look like a fresh macOS screenshot (`Screenshot …`); otherwise the default is used.
- **Make the text searchable** – on by default. The text in the screenshot (on-device OCR) is stored in the file's Finder comment, which Spotlight indexes: type a word from a screenshot into Spotlight and it appears. Only works for screenshots in folders Spotlight indexes (not `/tmp`, not hidden folders).
- **Sort screenshots** – off by default. Files into `2026-11/`, `github.com/` (website, else app) or `2026-11/github.com/`, inside the screenshot folder or a folder you choose. Undo moves the file back and removes folders it created if they are empty again. A destination outside Desktop/Documents may trigger a new macOS folder-access prompt.
- **Website** – read the address bar in browser screenshots.
- **Window / tab title** – needs Accessibility permission.
- **Biggest-text fallback** – off by default.

### Permissions

- **Folder access.** The first time, macOS asks whether ShotNamer may access your Desktop (or wherever screenshots are saved). Allow it, otherwise nothing can be renamed. The menu shows an error if access is denied.
- **Accessibility.** Optional; needed only to read window titles (the website name does not need it). macOS prompts when the app starts or when you switch "Add window / tab title" on; enable ShotNamer under *System Settings › Privacy & Security › Accessibility*. Without it the name is `date - app - website`. No Screen Recording permission is needed.
- After rebuilding from source the ad-hoc signature changes, so macOS may ask for folder access again.

### Privacy note

Websites, window titles and OCR text become part of the **filename**; titles can contain page names, document names or message subjects. The searchable text is stored in the file's Finder comment (extended attribute), so it travels with the file, can sync with it and shows in *Get Info*. Turn "searchable" off if screenshots may contain sensitive text. If your screenshot folder syncs (for example iCloud "Desktop & Documents"), that text syncs too, and it can show up in Finder, Spotlight and backups. Turn the title and OCR options off if your screenshots may contain sensitive material.

## Behaviour and limits

- Only screenshots **taken while the app runs** are renamed. Existing files are never touched.
- Recognised: PNG, JPG, HEIC and TIFF named like `Screenshot …`, `Screen Shot …` or the localized equivalents (German, French, Spanish, Dutch, Italian). Screen recordings (`.mov`) are ignored. A custom screenshot name prefix (`defaults write com.apple.screencapture name`) is not recognised yet.
- macOS does not store which app a screenshot came from. ShotNamer records which app was active over time and looks up the app active at the capture time (parsed from the filename). It is right in nearly all cases, but can be wrong if you switch apps within the same second.
- The window title is sampled once a second, so it matches the moment of capture even if you switch tab right after. Some apps expose no title; then the name is `date - app`.
- The website is only detected when the address bar (or the domain) is visible in the screenshot and the app is a browser (Safari, Chrome, Brave, Firefox, Arc, Edge, Opera, Vivaldi, Orion, DuckDuckGo, Zen). A cropped screenshot without the address bar gets no site. Other apps are not scanned.
- The biggest-text fallback picks the *largest* confident text line, which can be an ad or banner on busy pages, so it is off by default.
- Names are capped (app 30 chars, text 50) and cleaned of `/ : \`. Duplicates get ` 2`, ` 3`.

## Develop

```sh
swift build          # debug build
swift test           # unit tests (Swift Testing)
SHOTNAMER_FOLDER=/tmp/shots .build/debug/ShotNamer   # watch a scratch folder instead of the real one
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how it is put together and [CHANGELOG.md](CHANGELOG.md) for releases.

## Roadmap

- Recognise sites from logos / page text when the address bar is not visible
- Custom name template
- Screen recordings
- App icon, Developer ID signing and notarization, downloadable releases

## License

[MIT](LICENSE)
