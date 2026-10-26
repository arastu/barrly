#!/usr/bin/env bash
# release.sh <version>   e.g. scripts/release.sh 0.2.0
# Tests → bump bundle version → commit + tag → push → GitHub release → tap formula → brew upgrade.
set -euo pipefail
VERSION="${1:?usage: scripts/release.sh <version>}"
VERSION="${VERSION#v}"; TAG="v$VERSION"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
TAP_REPO="${TAP_REPO:-arastu/homebrew-tap}"
FORMULA="Formula/barrly.rb"

[ -z "$(git status --porcelain)" ] || { echo "working tree not clean"; exit 1; }
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && { echo "tag $TAG exists"; exit 1; }

echo "==> tests"; swift test 2>&1 | grep -E "Test run with|✘" | tail -3
swift test >/dev/null 2>&1 || { echo "tests failed"; exit 1; }

echo "==> bump version to $VERSION"
BUILD=$(( $(sed -n 's:.*<key>CFBundleVersion</key><string>\([0-9]*\)</string>.*:\1:p' Resources/Barrly.plist | head -1) + 1 ))
sed -i '' -e "s:<key>CFBundleShortVersionString</key><string>[^<]*</string>:<key>CFBundleShortVersionString</key><string>$VERSION</string>:" \
          -e "s:<key>CFBundleVersion</key><string>[^<]*</string>:<key>CFBundleVersion</key><string>$BUILD</string>:" Resources/Barrly.plist
git add Resources/Barrly.plist
git commit -qm "Release $TAG"
git tag -a "$TAG" -m "Barrly $VERSION"
git push -q origin HEAD "$TAG"
REV=$(git rev-parse "$TAG^{commit}")

echo "==> GitHub release"
gh release create "$TAG" --title "Barrly $VERSION" --generate-notes >/dev/null

echo "==> tap formula ($TAP_REPO)"
TMP="$(mktemp -d)"; gh repo clone "$TAP_REPO" "$TMP" -- -q
perl -0777 -i -pe 's/(tag:\s+")[^"]+(",\n\s+revision:\s+")[0-9a-f]{40}(")/${1}'"$TAG"'${2}'"$REV"'${3}/s' "$TMP/$FORMULA"
cp "$TMP/$FORMULA" "$FORMULA"
( cd "$TMP" && git add "$FORMULA" && git commit -qm "barrly $VERSION" && git push -q origin HEAD )
rm -rf "$TMP"
git add "$FORMULA" && git commit -qm "Formula: $VERSION" && git push -q origin HEAD

echo "==> brew upgrade"
brew update >/dev/null 2>&1 || true
brew upgrade arastu/tap/barrly 2>&1 | grep -E "🍺|Error" || true
/opt/homebrew/bin/barrly sign || true
if pgrep -x Barrly >/dev/null; then pkill -x Barrly; sleep 1; open -a /opt/homebrew/opt/barrly/Barrly.app; fi
echo "released $TAG"
