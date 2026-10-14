#!/usr/bin/env bash
# Builds a universal (Apple silicon + Intel) "Avengers Assemble.app" and zips it as build/AvengersAssemble.zip,
# the file the website's Download button points at (releases/latest/download/AvengersAssemble.zip).
#   ./scripts/package-release.sh
#   gh release create v1.0.0 build/AvengersAssemble.zip --title "Avengers Assemble 1.0" --notes-file ...
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UNIVERSAL=1 "$ROOT/scripts/build-app.sh"
APP="$ROOT/build/Avengers Assemble.app"
lipo -info "$APP/Contents/MacOS/SuiteOfAgents"
rm -f "$ROOT/build/AvengersAssemble.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ROOT/build/AvengersAssemble.zip"
echo "Packaged $ROOT/build/AvengersAssemble.zip ($(du -h "$ROOT/build/AvengersAssemble.zip" | cut -f1))"
