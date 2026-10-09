#!/bin/zsh
# Packs 绝境 into a disk image for sharing: dist/Brink-<version>.dmg with the app, a link to
# /Applications and a short read-me, plus a .sha256 next to it.
#   ./scripts/make_dmg.sh             build the release app first, then pack it
#   ./scripts/make_dmg.sh --no-build  pack the dist/Brink.app that's already there
set -e
cd "$(dirname "$0")/.."
[[ "$1" == "--no-build" ]] || ./scripts/build_app.sh
APP=dist/Brink.app
[[ -d "$APP" ]] || { echo "no $APP — run scripts/build_app.sh first"; exit 1; }
VER=$(defaults read "$PWD/$APP/Contents/Info" CFBundleShortVersionString)
OUT="dist/Brink-$VER.dmg"

WORK=$(mktemp -d)
STAGE="$WORK/Brink"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Brink.app"
ln -s /Applications "$STAGE/Applications"
cp scripts/dmg_readme.txt "$STAGE/Read me · 安装说明.txt"

# the volume gets the app's icon
ICONSET="$WORK/Brink.iconset"
mkdir -p "$ICONSET"
for f in App/Assets.xcassets/AppIcon.appiconset/icon_*.png; do
  b=$(basename "$f" .png); b=${b%@1x}
  cp "$f" "$ICONSET/$b.png"
done
if iconutil -c icns "$ICONSET" -o "$STAGE/.VolumeIcon.icns" 2>/dev/null && command -v SetFile >/dev/null; then
  SetFile -a C "$STAGE"
fi

rm -f "$OUT" "$OUT.sha256"
hdiutil create -volname "绝境 Brink $VER" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$OUT" >/dev/null
hdiutil verify "$OUT" >/dev/null
( cd dist && shasum -a 256 "$(basename "$OUT")" > "$(basename "$OUT").sha256" )
rm -rf "$WORK"
echo "$OUT ($(du -h "$OUT" | cut -f1))"
