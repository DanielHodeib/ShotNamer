# Changelog

## 0.1.0 – unreleased

- Automatic updates from Ed25519-signed GitHub releases; `scripts/release.sh` publishes one.
- Window-title and browser-address sampling run on a background queue (a hung app can no longer stall the menu bar); video frames use the async AVFoundation API (no deprecation warnings).
- Review fixes: undo no longer gets re-renamed; a failed move after redaction restores the original; undo keeps its record until it succeeded; backups purged hourly and excluded from Time Machine; browser address cleared when another app is in front; page text no longer beats the browser's address; follows save-location changes; sort folder ignored when sorting is off; Spanish `p. m.` times; faint text is still redacted; 12-digit phone numbers are not cards; `.app`/`.ai` file names in pages are not sites; template keeps its own leading/trailing text; names capped at 255 bytes; AppleScript and Accessibility calls time out.

- Settings window with a custom file name template (`{date} {time} {app} {site} {title}`).
- Site detection without a visible address bar: browser address via AppleScript (opt-in), title evidence confirmed by the image, experimental header guess.
- Optional redaction: black out e-mails, IBANs, card numbers, keys/tokens and passwords; original backed up 7 days; undo restores it.
- Screen recordings (.mov/.mp4) are renamed like screenshots.
- Searchable text: OCR text stored in the Finder comment so Spotlight finds screenshots by their content.
- Optional sorting into month / website-or-app folders, with undo that cleans up empty folders.
- Undo log: a log that cannot be read is backed up to `renames.json.bak` instead of being overwritten.
- Menu bar app that renames new screenshots to `date - app - headline text`.
- Website name from the address bar in browser screenshots (on-device OCR, no permission).
- App icon.
- Window / tab title (Accessibility API) as the descriptive part; on-device OCR as optional fallback.
- `scripts/install.sh` installs to /Applications.
- Undo of the last rename, recent list, pause, launch at login.
- English, German, French, Spanish, Dutch and Italian screenshot names.
