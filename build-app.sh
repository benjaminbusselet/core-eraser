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

# App universelle (puce Apple et Intel) : une compilation par architecture, réunies par lipo
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
for ARCH in arm64 x86_64; do
    swiftc -O -parse-as-library -target "$ARCH-apple-macos13.0" \
        "$ROOT"/app/Sources/*.swift -o "$TMP/core-eraser-$ARCH"
done
lipo -create "$TMP/core-eraser-arm64" "$TMP/core-eraser-x86_64" -output "$APP/Contents/MacOS/core-eraser"

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

# Signature avec le certificat local stable (créé par sign-setup.sh), sinon signature ad hoc
IDENTITY="core-eraser local signing"
if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
    codesign --force --sign "$IDENTITY" --identifier "$ID" "$APP"
else
    echo "Warning: no '$IDENTITY' certificate, ad hoc signature." >&2
    echo "Full Disk Access will be lost at each build. Run ./sign-setup.sh once." >&2
    codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP"
echo "Built $APP ($VERSION)"
