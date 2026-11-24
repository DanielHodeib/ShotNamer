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

Installed copies **update themselves** from signed GitHub releases (see *Updates* below); with a self-built copy you can also run `scripts/install.sh` again after pulling. (`scripts/build-app.sh` only builds `build/ShotNamer.app`.) "Launch at login" needs the app in `/Applications`.

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
- **Black out sensitive text** – off by default. Finds e-mail addresses, IBANs, card numbers, API keys / tokens (GitHub, OpenAI, Stripe, AWS, Slack, JWT …) and values after `password:` / `token:` / `secret:` with on-device OCR, and paints black boxes over them in the image. The unredacted **original is kept in `~/Library/Application Support/ShotNamer/Originals` for about 7 days** (it still contains the secrets; checked hourly and at launch, and excluded from Time Machine) and *Undo last rename* puts it back. Found secrets are also kept out of the file name and the Spotlight text. **Best effort, not a guarantee:** OCR can misread or miss text, a value split over two lines is not caught, and harmless text can be covered by mistake. Check screenshots before sharing them. Applies to images only; videos are not redacted.
- **Make the text searchable** – on by default. The text in the screenshot (on-device OCR) is stored in the file's Finder comment, which Spotlight indexes: type a word from a screenshot into Spotlight and it appears. Only works for screenshots in folders Spotlight indexes (not `/tmp`, not hidden folders).
- **Sort screenshots** – off by default. Files into `2026-11/`, `github.com/` (website, else app) or `2026-11/github.com/`, inside the screenshot folder or a folder you choose. Undo moves the file back and removes folders it created if they are empty again. A destination outside Desktop/Documents may trigger a new macOS folder-access prompt.
- **Website** – a site name for browser screenshots, from the most to the least reliable source:
  1. the address bar visible in the screenshot (`github.com`), read with OCR;
  2. the browser's real page address at the moment of capture, for screenshots without an address bar. Opt-in, uses AppleScript, so macOS asks once per browser for *Automation* permission. Safari, Chrome, Brave, Edge, Arc, Vivaldi, Opera and Chromium; Firefox cannot be asked;
  3. the end of the window title (`Meine Anzeigen | willhaben` → `willhaben`), accepted only if that name also appears as a header or logo line in the image (or is a well-known site such as GitHub). Needs the Accessibility permission for titles;
  4. *experimental, off by default:* a header line that is exactly a well-known site name (`GitHub`, `YouTube`, …).

  If none of these gives solid evidence, no site is added: a missing site is better than a wrong one.
- **Window / tab title** – needs Accessibility permission.
- **Biggest-text fallback** – off by default.

### Permissions

- **Folder access.** The first time, macOS asks whether ShotNamer may access your Desktop (or wherever screenshots are saved). Allow it, otherwise nothing can be renamed. The menu shows an error if access is denied.
- **Accessibility.** Optional; needed only to read window titles (the website name does not need it). macOS prompts when the app starts or when you switch "Window / tab title" on; enable ShotNamer under *System Settings › Privacy & Security › Accessibility*. Without it the name is `date - app - website`. No Screen Recording permission is needed. With ad-hoc signed builds (the default) macOS forgets the Accessibility and Automation grants after every rebuild or update; sign with a fixed identity (`SHOTNAMER_SIGN_IDENTITY`, see *Develop*) to keep them.
- After rebuilding from source the ad-hoc signature changes, so macOS may ask for folder access again.

### Privacy note

Websites, window titles and OCR text become part of the **filename**; titles can contain page names, document names or message subjects. The searchable text is stored in the file's Finder comment (extended attribute), so it travels with the file, can sync with it and shows in *Get Info*. Turn "searchable" off if screenshots may contain sensitive text. If your screenshot folder syncs (for example iCloud "Desktop & Documents"), that text syncs too, and it can show up in Finder, Spotlight and backups. Turn the title and OCR options off if your screenshots may contain sensitive material.

## Behaviour and limits

- Only screenshots **that appear while the app runs** are renamed; files already in the folder at launch are left alone. A screenshot-named file you copy or move into the folder counts as new. Screenshots taken during the ~2 s restart after an update are not renamed.
- If you change the save location (⌘⇧5 › Options), ShotNamer follows within 10 seconds.
- Recognised: PNG, JPG, HEIC and TIFF named like `Screenshot …`, `Screen Shot …` or the localized equivalents (German, French, Spanish, Dutch, Italian). **Screen recordings** (`Screen Recording …mov` / `Bildschirmaufnahme …mov`, also `.mp4`) are renamed too: ShotNamer waits until the movie is finished and playable, then names it from the app and window title at the start of the recording, and reads the website from a frame one second in. Recordings get no searchable text and are **not redacted**. A custom screenshot name prefix (`defaults write com.apple.screencapture name`) is not recognised yet.
- macOS does not store which app a screenshot came from. ShotNamer records which app was active over time and looks up the app active at the capture time (parsed from the filename). It is right in nearly all cases, but can be wrong if you switch apps within the same second.
- The window title is sampled once a second, so it matches the moment of capture even if you switch tab right after. Some apps expose no title; then the name is `date - app`.
- The website is only detected when the address bar (or the domain) is visible in the screenshot and the app is a browser (Safari, Chrome, Brave, Firefox, Arc, Edge, Opera, Vivaldi, Orion, DuckDuckGo, Zen). Without a visible address bar, the fallbacks above apply. Other apps are not scanned.
- The biggest-text fallback picks the *largest* confident text line, which can be an ad or banner on busy pages, so it is off by default.
- Names are capped (app 30 chars, text 50) and cleaned of `/ : \`. Duplicates get ` 2`, ` 3`.

## Updates

ShotNamer checks the latest GitHub release 30 s after launch and every 6 hours (*Settings › Updates*, on by default; *Check for updates* in the menu checks now). It installs a release only if:

- the zip's Ed25519 signature matches the public key built into the app (`Update.publicKey`),
- the app inside has the same bundle ID and exactly the release's version, and that version is newer (no downgrades, no re-uploaded old builds),
- its code signature verifies.

It waits until no rename is running, swaps the app bundle in place and restarts. Nothing is sent besides the request to `api.github.com`. Updates need the app in a folder you can write to (`/Applications` is fine) and a **public** repository.

### Publishing a release (maintainer)

```sh
swift scripts/update-key.swift keygen ~/.config/shotnamer/update_ed25519   # once; prints the public key for Update.publicKey
scripts/release.sh 0.2.0     # bumps Info.plist, tests, builds universal, zips with ditto, signs, tags, gh release create
```

**Back up the private key** (`~/.config/shotnamer/update_ed25519`, e.g. in a password manager). If it is lost, installed copies can never accept another update; if it leaks, anyone with it and write access to the releases could ship code to every user.

## Develop

```sh
swift build          # debug build
swift test           # unit tests (Swift Testing)
SHOTNAMER_FOLDER=/tmp/shots .build/debug/ShotNamer   # watch a scratch folder instead of the real one
SHOTNAMER_SIGN_IDENTITY="My Cert" scripts/install.sh  # sign with a fixed certificate so permissions survive rebuilds
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how it is put together and [CHANGELOG.md](CHANGELOG.md) for releases.

## Roadmap

- Developer ID signing and notarization
- Recognise custom screenshot name prefixes

## License

[MIT](LICENSE)
