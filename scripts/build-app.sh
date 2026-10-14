#!/usr/bin/env bash
# Builds "build/Avengers Assemble.app": release Swift build + bundled Python engine, ad-hoc signed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Avengers Assemble"
APP="$ROOT/build/$APP_NAME.app"
VERSION="${SUITE_VERSION:-1.0.0}"
BUILD_NUMBER="${SUITE_BUILD:-1}"

echo "==> Building the Swift package (release)"
cd "$ROOT/app"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/SuiteOfAgents" "$APP/Contents/MacOS/SuiteOfAgents"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>com.amalmehta.avengersassemble</string>
    <key>CFBundleExecutable</key><string>SuiteOfAgents</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSSupportsAutomaticTermination</key><false/>
</dict>
</plist>
PLIST

if [ -f "$ROOT/engine/pyproject.toml" ]; then
    echo "==> Bundling the engine"
    rsync -a --delete \
        --exclude '.venv' --exclude '__pycache__' --exclude '.pytest_cache' \
        "$ROOT/engine/" "$APP/Contents/Resources/engine/"
else
    echo "warning: $ROOT/engine/pyproject.toml not found; the app will need an engine folder set in Settings" >&2
fi

echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - "$APP"
codesign --verify --deep "$APP"

echo "Built: $APP"
