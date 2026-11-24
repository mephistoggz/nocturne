#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
dest="${1:-$PWD/dist}"
mkdir -p "$dest"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
app="$tmp/NOCTURNE.app"
mkdir -p "$app/Contents/"{MacOS,Resources}
sources=(Sources/Nocturne/*.swift)
for arch in x86_64 arm64; do
    xcrun swiftc -O -whole-module-optimization -swift-version 5 -parse-as-library -target "$arch-apple-macos14.0" -module-name Nocturne "${sources[@]}" -o "$tmp/$arch"
done
lipo -create "$tmp/x86_64" "$tmp/arm64" -output "$app/Contents/MacOS/Nocturne"
cp Resources/Info.plist "$app/Contents/"
cp Resources/Nocturne.icns "$app/Contents/Resources/"
cp -R Sources/Nocturne/ThemeArt "$app/Contents/Resources/"
cp -R Resources/*.lproj "$app/Contents/Resources/"
if [[ -f Resources/GoogleOAuth.json ]]; then cp Resources/GoogleOAuth.json "$app/Contents/Resources/"; fi
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
ditto "$app" "$dest/NOCTURNE.app"
mkdir "$tmp/image"
ditto "$app" "$tmp/image/NOCTURNE.app"
ln -s /Applications "$tmp/image/Applications"
hdiutil create -ov -fs HFS+ -format UDZO -volname NOCTURNE -srcfolder "$tmp/image" "$dest/NOCTURNE.dmg"
hdiutil verify "$dest/NOCTURNE.dmg"
