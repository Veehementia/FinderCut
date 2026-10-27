#!/bin/bash
# Builds build/FinderCut.app for Apple Silicon.
# Set SIGN_IDENTITY to a codesigning identity to sign with it (default: ad-hoc).
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/FinderCut.app"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

swift build -c release --arch arm64
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"

if [ ! -f Resources/AppIcon.icns ]; then
    ICONSET="$(mktemp -d)/AppIcon.iconset"
    swift scripts/make-icon.swift "$ICONSET"
    iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/FinderCut" "$APP/Contents/MacOS/FinderCut"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign "$SIGN_IDENTITY" --identifier com.matteonardone.FinderCut "$APP"

echo "Built $APP"
