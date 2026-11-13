#!/bin/bash
# Construit build/core-eraser.app : interface SwiftUI + le script rangé dans l'app.
# Demande Xcode (les macros de SwiftUI ne sont pas livrées avec les seuls outils en ligne de commande).
set -eu

ROOT="$(cd "$(dirname "$0")" && pwd -P)"
APP="$ROOT/build/core-eraser.app"
VERSION="$("$ROOT/core-eraser.sh" --version | awk '{ print $2 }')"
ID="io.github.benjaminbusselet.core-eraser"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -parse-as-library -target "$(uname -m)-apple-macos13.0" \
    "$ROOT"/app/Sources/*.swift -o "$APP/Contents/MacOS/core-eraser"

cp "$ROOT/core-eraser.sh" "$APP/Contents/Resources/core-eraser.sh"
chmod +x "$APP/Contents/Resources/core-eraser.sh"

PLIST="$APP/Contents/Info.plist"
plutil -create xml1 "$PLIST"
plutil -insert CFBundleIdentifier -string "$ID" "$PLIST"
plutil -insert CFBundleExecutable -string "core-eraser" "$PLIST"
plutil -insert CFBundleName -string "core-eraser" "$PLIST"
plutil -insert CFBundlePackageType -string "APPL" "$PLIST"
plutil -insert CFBundleShortVersionString -string "$VERSION" "$PLIST"
plutil -insert CFBundleVersion -string "$VERSION" "$PLIST"
plutil -insert LSMinimumSystemVersion -string "13.0" "$PLIST"
plutil -insert NSHighResolutionCapable -bool true "$PLIST"

# Signature locale (sans compte développeur Apple)
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
echo "Built $APP ($VERSION)"
