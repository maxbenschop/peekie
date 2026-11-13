#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(xcodebuild -project Peekie.xcodeproj -scheme Peekie -showBuildSettings 2>/dev/null \
  | awk '/ MARKETING_VERSION = /{print $3}')
DMG="dist/Peekie-${VERSION}.dmg"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

# Notary credentials: either a notarytool keychain profile (NOTARY_PROFILE, handy locally)
# or an Apple ID, team id and app-specific password (used by the release workflow).
IDENTITY="${SIGN_IDENTITY:--}"
NOTARY_ARGS=()
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
elif [[ -n "${NOTARY_APPLE_ID:-}" && -n "${NOTARY_TEAM_ID:-}" && -n "${NOTARY_PASSWORD:-}" ]]; then
  NOTARY_ARGS=(--apple-id "$NOTARY_APPLE_ID" --team-id "$NOTARY_TEAM_ID" --password "$NOTARY_PASSWORD")
fi
NOTARIZE=false
if [[ "$IDENTITY" != "-" && ${#NOTARY_ARGS[@]} -gt 0 ]]; then
  NOTARIZE=true
fi
if [[ "$IDENTITY" != "-" && "$NOTARIZE" == false && -n "${CI:-}" ]]; then
  echo "SIGN_IDENTITY is set but notary credentials are missing: refusing to publish an un-notarized build." >&2
  exit 1
fi

xcodebuild -project Peekie.xcodeproj -scheme Peekie -configuration Release \
  -derivedDataPath build ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="$IDENTITY" OTHER_CODE_SIGN_FLAGS="--timestamp" build | tail -1

cp -R build/Build/Products/Release/Peekie.app "$STAGE/"
APP="$STAGE/Peekie.app"

if [[ "$IDENTITY" != "-" ]]; then
  codesign --verify --deep --strict --verbose=2 "$APP"
  if codesign -d --entitlements - --xml "$APP" 2>/dev/null | grep -q "get-task-allow"; then
    echo "The app carries the get-task-allow entitlement; Apple will reject it." >&2
    exit 1
  fi
fi

# Submits $1, waits, prints Apple's log if it is not accepted, then staples the ticket to $2.
notarize() {
  local out id attempt
  # Apple's service occasionally answers 403 or times out for a moment; try the upload three times.
  for attempt in 1 2 3; do
    out=$(xcrun notarytool submit "$1" "${NOTARY_ARGS[@]}" --wait --output-format json) && break
    if (( attempt == 3 )); then
      echo "Could not submit $(basename "$1") for notarization." >&2
      exit 1
    fi
    echo "Notary submission failed, retrying in 30 s…" >&2
    sleep 30
  done
  id=$(print -r -- "$out" | plutil -extract id raw -o - -)
  if [[ "$(print -r -- "$out" | plutil -extract status raw -o - -)" != "Accepted" ]]; then
    echo "Notarization of $(basename "$1") failed:" >&2
    xcrun notarytool log "$id" "${NOTARY_ARGS[@]}" >&2 || true
    exit 1
  fi
  echo "Notarized $(basename "$1") ($id)"
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
  # Check exactly what a downloaded copy gets: Gatekeeper must accept both without a prompt.
  spctl --assess --type execute --verbose=2 "$APP"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
  xcrun stapler validate "$DMG"
fi

hdiutil verify "$DMG" | tail -1
echo "Architectures: $(lipo -archs "$APP/Contents/MacOS/Peekie")"
echo "Signed with: $IDENTITY, notarized: $NOTARIZE"
echo "Created $DMG ($(du -h "$DMG" | cut -f1))"
