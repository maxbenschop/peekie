#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(xcodebuild -project Peekie.xcodeproj -scheme Peekie -showBuildSettings 2>/dev/null \
  | awk '/ MARKETING_VERSION = /{print $3}')
DMG="dist/Peekie-${VERSION}.dmg"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

IDENTITY="${SIGN_IDENTITY:--}"
NOTARIZE=false
if [[ "$IDENTITY" != "-" && -n "${NOTARY_APPLE_ID:-}" && -n "${NOTARY_TEAM_ID:-}" && -n "${NOTARY_PASSWORD:-}" ]]; then
  NOTARIZE=true
fi

xcodebuild -project Peekie.xcodeproj -scheme Peekie -configuration Release \
  -derivedDataPath build ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="$IDENTITY" OTHER_CODE_SIGN_FLAGS="--timestamp" build | tail -1

cp -R build/Build/Products/Release/Peekie.app "$STAGE/"
APP="$STAGE/Peekie.app"

notarize() {
  xcrun notarytool submit "$1" --apple-id "$NOTARY_APPLE_ID" --team-id "$NOTARY_TEAM_ID" \
    --password "$NOTARY_PASSWORD" --wait
  xcrun stapler staple "$2"
}

if $NOTARIZE; then
  ditto -c -k --keepParent "$APP" "$STAGE/Peekie.zip"
  notarize "$STAGE/Peekie.zip" "$APP"
  rm "$STAGE/Peekie.zip"
fi

ln -s /Applications "$STAGE/Applications"

mkdir -p dist
rm -f "$DMG"
hdiutil create -volname "Peekie" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 "$DMG" >/dev/null

if [[ "$IDENTITY" != "-" ]]; then
  codesign --sign "$IDENTITY" --timestamp "$DMG"
fi
if $NOTARIZE; then
  notarize "$DMG" "$DMG"
fi

hdiutil verify "$DMG" | tail -1
echo "Architectures: $(lipo -archs "$APP/Contents/MacOS/Peekie")"
echo "Signed with: $IDENTITY, notarized: $NOTARIZE"
echo "Created $DMG ($(du -h "$DMG" | cut -f1))"
