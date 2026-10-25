#!/usr/bin/env bash
# Builds Vendor/mediaremote-adapter into Vendor/build/MediaRemoteAdapter.framework
# (+ MediaRemoteAdapterTestClient) with plain clang, since the upstream build uses cmake.
# The framework is bundled with Barrly.app and loaded by /usr/bin/perl, never linked.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/Vendor/mediaremote-adapter"
OUT="$ROOT/Vendor/build"
FW="$OUT/MediaRemoteAdapter.framework"
rm -rf "$OUT"; mkdir -p "$FW/Versions/A/Resources"

ADAPTER_SOURCES=(
  src/adapter/env.m src/adapter/get.m src/adapter/globals.m src/adapter/keys.m
  src/adapter/now_playing.m src/adapter/repeat.m src/adapter/seek.m src/adapter/send.m
  src/adapter/shuffle.m src/adapter/speed.m src/adapter/stream.m src/adapter/test.m
  src/private/MediaRemote.m src/utility/Debounce.m src/utility/helpers.m
)
COMMON=(-fobjc-arc -O2 -arch arm64 -arch x86_64 -mmacosx-version-min=12.0
        -I"$SRC/include" -I"$SRC/src" -I"$SRC/src/utility" -I"$SRC/src/private" -I"$SRC/src/adapter"
        -framework Foundation -framework AppKit -framework UniformTypeIdentifiers)

( cd "$SRC" && clang "${COMMON[@]}" -dynamiclib \
    -install_name "@rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter" \
    "${ADAPTER_SOURCES[@]}" -o "$FW/Versions/A/MediaRemoteAdapter" )

cat > "$FW/Versions/A/Resources/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.vandenbe.MediaRemoteAdapter</string>
  <key>CFBundleName</key><string>MediaRemoteAdapter</string>
  <key>CFBundleExecutable</key><string>MediaRemoteAdapter</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>0.1.0</string>
</dict></plist>
PLIST
ln -s A "$FW/Versions/Current"
ln -s Versions/Current/MediaRemoteAdapter "$FW/MediaRemoteAdapter"
ln -s Versions/Current/Resources "$FW/Resources"

( cd "$SRC" && clang "${COMMON[@]}" -framework MediaPlayer src/test/main.m src/test/NowPlayingTest.m \
    -o "$OUT/MediaRemoteAdapterTestClient" )
cp "$SRC/bin/mediaremote-adapter.pl" "$OUT/"
codesign --force --sign - "$FW" >/dev/null 2>&1 || true
codesign --force --sign - "$OUT/MediaRemoteAdapterTestClient" >/dev/null 2>&1 || true
echo "built $FW"
