# Changelog

## 0.1.0 – unreleased

- Settings window with a custom file name template (`{date} {time} {app} {site} {title}`).
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
