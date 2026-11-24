#!/bin/bash
# Regenerates Resources/AppIcon.icns from scripts/make-icon.swift (the .icns is committed; only run this to change the design).
set -euo pipefail
cd "$(dirname "$0")/.."
T=$(mktemp -d)
swiftc -O scripts/make-icon.swift -o "$T/make-icon"
"$T/make-icon" "$T/icon-1024.png"
S="$T/AppIcon.iconset"; mkdir "$S"
for n in 16 32 128 256 512; do
  sips -z $n $n "$T/icon-1024.png" --out "$S/icon_${n}x${n}.png" >/dev/null
  sips -z $((n*2)) $((n*2)) "$T/icon-1024.png" --out "$S/icon_${n}x${n}@2x.png" >/dev/null
done
iconutil -c icns "$S" -o Resources/AppIcon.icns
cp "$T/icon-1024.png" docs/icon.png
echo "Wrote Resources/AppIcon.icns and docs/icon.png"
