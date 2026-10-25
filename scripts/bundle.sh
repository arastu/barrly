#!/usr/bin/env bash
# bundle.sh <executable> <AppName> <bundle-id> <out-dir> [extra-resources-dir]
# Assembles <out-dir>/<AppName>.app around a SwiftPM-built executable and ad-hoc signs it.
set -euo pipefail
EXE="$1"; NAME="$2"; BID="$3"; OUT="$4"; RES="${5:-}"
APP="$OUT/$NAME.app"; NEW="$APP.new"
rm -rf "$NEW"; mkdir -p "$NEW/Contents/MacOS" "$NEW/Contents/Resources"
cp "$EXE" "$NEW/Contents/MacOS/$NAME"
if [ -n "$RES" ] && [ -d "$RES" ]; then cp -R "$RES"/. "$NEW/Contents/Resources/"; fi
# SwiftPM resource bundles (Name_Target.bundle) live next to the executable; bring them along.
for b in "$(dirname "$EXE")"/*.bundle; do [ -d "$b" ] && cp -R "$b" "$NEW/Contents/Resources/"; done
PLIST="$(dirname "$0")/../Resources/${NAME}.plist"
if [ -f "$PLIST" ]; then
  sed -e "s/__NAME__/$NAME/g" -e "s/__BID__/$BID/g" "$PLIST" > "$NEW/Contents/Info.plist"
else
  cat > "$NEW/Contents/Info.plist" <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$NAME</string>
<key>CFBundleIdentifier</key><string>$BID</string>
<key>CFBundleName</key><string>$NAME</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
P
fi
codesign --force --deep --sign - "$NEW" >/dev/null
rm -rf "$APP"; mv "$NEW" "$APP"
echo "$APP"
