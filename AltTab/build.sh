#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUNDLE="$SCRIPT_DIR/AltTab.app"
MACOS="$BUNDLE/Contents/MacOS"

echo "Building..."
cd "$SCRIPT_DIR"
swift build -c release

echo "Assembling app bundle..."
rm -rf "$BUNDLE"
mkdir -p "$MACOS" "$BUNDLE/Contents/Resources"
cp .build/release/AltTab "$MACOS/AltTab"
cp Info.plist "$BUNDLE/Contents/Info.plist"
cp AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"

echo "Installing to /Applications..."
rm -rf /Applications/AltTab.app
cp -r "$BUNDLE" /Applications/AltTab.app

echo "Done — /Applications/AltTab.app"
