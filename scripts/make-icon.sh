#!/usr/bin/env bash
# Regenerates the app icon from its SwiftUI drawing (app/Sources/SuiteOfAgents/AppIcon.swift):
# every macOS size → app/Resources/AppIcon.icns, plus docs/images/icon.png for the README.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> Building the app"
cd "$ROOT/app"
swift build -c release
"$(swift build -c release --show-bin-path)/SuiteOfAgents" --render-icon "$WORK"

echo "==> Packing AppIcon.icns"
mkdir -p "$ROOT/app/Resources"
iconutil -c icns "$WORK/AppIcon.iconset" -o "$ROOT/app/Resources/AppIcon.icns"
cp "$WORK/AppIcon.iconset/icon_128x128@2x.png" "$ROOT/docs/images/icon.png"
echo "Wrote app/Resources/AppIcon.icns and docs/images/icon.png"
