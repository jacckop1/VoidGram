#!/usr/bin/env bash
set -euo pipefail

: "${APP_PATH:?set APP_PATH to the built VoidGram.app}"
dist="${DIST_DIR:-$PWD/dist}"
test "$(uname -s)" = Darwin || { echo "Packaging needs macOS." >&2; exit 1; }
test -d "$APP_PATH"
mkdir -p "$dist"
dist="$(cd "$dist" && pwd)"
stage="$(mktemp -d "${TMPDIR:-/tmp}/voidgram-dmg.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
app="$stage/VoidGram.app"
ditto "$APP_PATH" "$app"
plist="$app/Contents/Info.plist"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist")" = VoidGram
case "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")" in
  com.voidgram.desktop|com.voidgram.desktop.debug) ;;
  *) echo "Unexpected application bundle identifier." >&2; exit 1 ;;
esac
test -s "$app/Contents/Resources/AppIcon-Default.icns"
lipo "$app/Contents/MacOS/VoidGram" -verify_arch x86_64 arm64

while IFS= read -r -d '' library; do
  codesign --force --sign - "$library"
done < <(find "$app/Contents/Frameworks" -type f -name '*.dylib' -print0)
codesign --force --sign - "$app"
codesign --verify --deep --strict --verbose=2 "$app"

ditto -c -k --sequesterRsrc --keepParent "$app" "$dist/voidgram-desktop-macos-universal.zip"
ln -s /Applications "$stage/Applications"
hdiutil create -ov -format UDZO -volname VoidGram -srcfolder "$stage" \
  "$dist/voidgram-desktop-macos-universal.dmg"
(
  cd "$dist"
  shasum -a 256 voidgram-desktop-macos-universal.zip voidgram-desktop-macos-universal.dmg > SHA256SUMS-macos.txt
)
echo "Packages: $dist"
