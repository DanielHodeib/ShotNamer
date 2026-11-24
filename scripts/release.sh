#!/bin/bash
# Publishes a signed GitHub release that installed copies pick up automatically.
# Usage: scripts/release.sh 0.2.0
# Needs: the private key at $SHOTNAMER_UPDATE_KEY (default ~/.config/shotnamer/update_ed25519), `gh` logged in,
# a clean main branch. The key must match Update.publicKey; without it no installed copy accepts an update.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/release.sh <version, e.g. 0.2.0>}"
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]] || { echo "version must look like 0.2.0" >&2; exit 1; }
KEY="${SHOTNAMER_UPDATE_KEY:-$HOME/.config/shotnamer/update_ed25519}"
[ -f "$KEY" ] || { echo "missing signing key $KEY" >&2; exit 1; }
[ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "commit your changes first" >&2; exit 1; }
git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null && { echo "tag v$VERSION exists" >&2; exit 1; }

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Resources/Info.plist
BUILD=$(( $(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Resources/Info.plist) + 1 ))
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" Resources/Info.plist

swift test
scripts/build-app.sh
OUT=build/release
rm -rf "$OUT" && mkdir -p "$OUT"
ditto -c -k --keepParent build/ShotNamer.app "$OUT/ShotNamer.zip"   # ditto keeps symlinks and the signature
swift scripts/update-key.swift sign "$KEY" "$OUT/ShotNamer.zip" > "$OUT/ShotNamer.zip.sig"

git commit -qm "Release $VERSION" Resources/Info.plist
git tag "v$VERSION"
git push -q origin HEAD "v$VERSION"
gh release create "v$VERSION" "$OUT/ShotNamer.zip" "$OUT/ShotNamer.zip.sig" --title "ShotNamer $VERSION" --generate-notes
echo "Released $VERSION"
