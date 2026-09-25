#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(xcodebuild -project Peekie.xcodeproj -scheme Peekie -showBuildSettings 2>/dev/null \
  | awk '/ MARKETING_VERSION = /{print $3}')
DMG="dist/Peekie-${VERSION}.dmg"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

xcodebuild -project Peekie.xcodeproj -scheme Peekie -configuration Release \
  -derivedDataPath build ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO CODE_SIGN_IDENTITY=- build | tail -1

cp -R build/Build/Products/Release/Peekie.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"

mkdir -p dist
rm -f "$DMG"
hdiutil create -volname "Peekie" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 "$DMG" >/dev/null

hdiutil verify "$DMG" | tail -1
echo "Architectures: $(lipo -archs "$STAGE/Peekie.app/Contents/MacOS/Peekie")"
echo "Created $DMG ($(du -h "$DMG" | cut -f1))"
