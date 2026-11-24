#!/bin/bash
# Builds build/ShotNamer.app (universal, ad-hoc signed). Usage: scripts/build-app.sh [--native]
set -euo pipefail
cd "$(dirname "$0")/.."

ARCHS=(--arch arm64 --arch x86_64)
[ "${1:-}" = "--native" ] && ARCHS=()

swift build -c release ${ARCHS[@]+"${ARCHS[@]}"}
BIN="$(swift build -c release ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)"

APP=build/ShotNamer.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/ShotNamer" "$APP/Contents/MacOS/ShotNamer"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# SHOTNAMER_SIGN_IDENTITY: a code-signing certificate name (e.g. a self-signed one from Keychain Access).
# With one fixed identity, macOS keeps Accessibility/Automation grants across updates. Default "-" = ad-hoc:
# the identity changes per build, so those grants reset after every install or update.
codesign --force --sign "${SHOTNAMER_SIGN_IDENTITY:--}" "$APP"
echo "Built $APP"
