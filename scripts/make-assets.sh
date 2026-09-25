#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

ICTOOL="/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

"$ICTOOL" Peekie/AppIcon.icon --export-image --output-file assets/icon.png \
  --platform macOS --rendition Default --width 512 --height 512 --scale 2

swiftc -o "$WORK/make-banner" assets/make-banner.swift
"$WORK/make-banner" assets/icon.png assets/banner.png
