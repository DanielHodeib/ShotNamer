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
mkdir -p "$APP/Contents/MacOS"
cp "$BIN/ShotNamer" "$APP/Contents/MacOS/ShotNamer"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signature: runs locally. Ad-hoc identity changes per build, so macOS may re-ask for folder access.
codesign --force --sign - "$APP"
echo "Built $APP"
