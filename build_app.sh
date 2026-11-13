#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
DIST="$ROOT/dist"
APP="$DIST/Lyrebird.app"
BINARY="$ROOT/.build/release/Lyrebird"

cd "$ROOT"
swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/Lyrebird"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT"/Resources/MenuBarBird*.png "$APP/Contents/Resources/"
xcrun actool "$ROOT/Resources/Assets.xcassets" --compile "$APP/Contents/Resources" --platform macosx --minimum-deployment-target 13.0 --output-format human-readable-text >/dev/null
printf 'APPL????' > "$APP/Contents/PkgInfo"
xattr -cr "$APP"

KEYCHAIN="$ROOT/Signing/Signing.keychain"
if [[ -f "$KEYCHAIN" || -f "$KEYCHAIN-db" ]]; then
    PASSWORD="$(< "$ROOT/Signing/keychain_password")"
    eval "ORIGINAL_KEYCHAINS=($(security list-keychains))"
    restore_keychains() {
        security list-keychains -s "${ORIGINAL_KEYCHAINS[@]}"
    }
    trap restore_keychains EXIT
    security unlock-keychain -p "$PASSWORD" "$KEYCHAIN"
    security list-keychains -s "$KEYCHAIN" "${ORIGINAL_KEYCHAINS[@]}"
    codesign --force \
        --sign "MusicTrackRecorder Local Signing" \
        --keychain "$KEYCHAIN" \
        --identifier com.kimi.MusicTrackRecorder \
        --timestamp=none \
        "$APP"
    restore_keychains
    trap - EXIT
else
    codesign --force --sign - --identifier com.kimi.MusicTrackRecorder "$APP"
fi
codesign --verify --deep --strict --verbose=2 "$APP"
rm -f "$DIST/Lyrebird.zip"
(cd "$DIST" && zip -q -r -X Lyrebird.zip Lyrebird.app)

echo "$APP"
