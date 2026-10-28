#!/usr/bin/env bash
# Creates a local self-signed "Barrly Code Signing" identity in its own keychain and trusts it for
# code signing. Run once. Afterwards scripts/bundle.sh and the Homebrew formula sign Barrly with it,
# so macOS privacy grants (Accessibility for the input lock, Calendars, …) survive upgrades.
set -euo pipefail
NAME="Barrly Code Signing"
KC="$HOME/Library/Keychains/barrly-signing.keychain-db"
PASS="barrly"   # protects only this throwaway keychain; the identity has no value outside this Mac
if [ "${1:-}" = "--recreate" ] && [ -f "$KC" ]; then
  # Keychain lost or password unknown: set the old one aside (a new certificate means granting Accessibility again).
  LIST=$(security list-keychains -d user | tr -d '"' | sed 's/^ *//' | grep -v barrly-signing || true)
  security list-keychains -d user -s $LIST
  mv "$KC" "$KC.bak-$(date +%Y%m%d%H%M%S)"
fi
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$NAME"; then echo "identity '$NAME' already exists (--recreate replaces it)"; exit 0; fi
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
  -subj "/CN=$NAME/O=Barrly" -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" -addext "basicConstraints=critical,CA:false" 2>/dev/null
openssl pkcs12 -export -legacy -out "$TMP/id.p12" -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -passout "pass:$PASS" -name "$NAME"
[ -f "$KC" ] || security create-keychain -p "$PASS" "$KC"
security set-keychain-settings "$KC"            # never auto-lock, so codesign works unattended
security unlock-keychain -p "$PASS" "$KC"
security import "$TMP/id.p12" -k "$KC" -P "$PASS" -T /usr/bin/codesign -T /usr/bin/security -A
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASS" "$KC" >/dev/null
# Keep the existing search list and add our keychain.
LIST=$(security list-keychains -d user | tr -d '"' | sed 's/^ *//' | grep -v barrly-signing || true)
security list-keychains -d user -s $LIST "$KC"
security add-trusted-cert -r trustRoot -p codeSign -k "$KC" "$TMP/cert.pem"
security find-identity -v -p codesigning | grep "$NAME"
echo "done. Re-install or re-sign Barrly, then grant Accessibility once:  tccutil reset Accessibility dev.barrly.app"
