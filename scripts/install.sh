#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY=$(security find-identity -v -p codesigning | awk '/Apple Development/ {print $2; exit}')
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="-"
  echo "No Apple Development certificate found: signing ad-hoc (Accessibility must be re-granted after each install)."
fi

xcodebuild -project Peekie.xcodeproj -scheme Peekie -configuration Release \
  -derivedDataPath build CODE_SIGN_IDENTITY="$IDENTITY" build | tail -1

pkill -x Peekie 2>/dev/null && sleep 1 || true
rm -rf /Applications/Peekie.app
cp -R build/Build/Products/Release/Peekie.app /Applications/Peekie.app
open /Applications/Peekie.app
