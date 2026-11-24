#!/bin/bash
# Builds ShotNamer and installs it to /Applications (replacing and restarting a running copy).
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build-app.sh --native
pkill -x ShotNamer 2>/dev/null || true
sleep 1
rm -rf /Applications/ShotNamer.app
cp -R build/ShotNamer.app /Applications/ShotNamer.app
open /Applications/ShotNamer.app
echo "Installed /Applications/ShotNamer.app"
