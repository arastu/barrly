#!/usr/bin/env bash
# Build Barrly (debug by default, `-c release` to pass through), bundle it, relaunch it.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONF="${1:-debug}"
cd "$ROOT"
[ -d Vendor/build/MediaRemoteAdapter.framework ] || scripts/build-adapter.sh
swift build -c "$CONF" 2>&1 | grep -E "error|warning: var|Compiling|Build complete|Linking" | grep -vE "^\s*$" || true
EXE="$ROOT/.build/$CONF/Barrly"
[ -x "$EXE" ] || { echo "build failed"; exit 1; }
STAGE="$(mktemp -d)"; mkdir -p "$STAGE/MediaRemoteAdapter"
cp -R Vendor/build/MediaRemoteAdapter.framework Vendor/build/mediaremote-adapter.pl Vendor/build/MediaRemoteAdapterTestClient "$STAGE/MediaRemoteAdapter/"
OUT="${BARRLY_APP_DIR:-$HOME/.local/share/barrly}"; mkdir -p "$OUT"
APP="$(scripts/bundle.sh "$EXE" Barrly dev.barrly.app "$OUT" "$STAGE")"
rm -rf "$STAGE"
pkill -x Barrly 2>/dev/null || true
sleep 0.3
open "$APP"
echo "launched $APP"
