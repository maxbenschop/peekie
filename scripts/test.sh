#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

SUITE="${1:-logic}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

SOURCES=()
for file in Peekie/*.swift; do
  [[ "$file" == "Peekie/main.swift" ]] && continue
  SOURCES+=("$file")
done

swiftc -swift-version 5 -o "$WORK/peekie-tests" Tests/*.swift "${SOURCES[@]}"

"$WORK/peekie-tests" "$SUITE" &
PID=$!
( sleep 300; kill "$PID" 2>/dev/null ) &
WATCHDOG=$!
wait "$PID"
STATUS=$?
kill "$WATCHDOG" 2>/dev/null || true
exit $STATUS
