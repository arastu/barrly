#!/usr/bin/env bash
# release.sh <version>   e.g. scripts/release.sh 0.2.0
# Tests → bump bundle version → commit + tag → push → GitHub release → bottle + app zip as release
# assets → tap formula (tag, revision, bottle block) → brew reinstall from the bottle.
#
# Optional notarized app zip (needs an Apple Developer ID):
#   BARRLY_DEVELOPER_ID="Developer ID Application: Name (TEAMID)" BARRLY_NOTARY_PROFILE=barrly-notary scripts/release.sh 0.2.0
# where the profile was stored once with:  xcrun notarytool store-credentials barrly-notary
set -euo pipefail
VERSION="${1:?usage: scripts/release.sh <version>}"
VERSION="${VERSION#v}"; TAG="v$VERSION"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
REPO="${REPO:-arastu/barrly}"
TAP="${TAP:-arastu/tap}"
FORMULA="Formula/barrly.rb"
ROOT_URL="https://github.com/$REPO/releases/download/$TAG"

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
gh release create "$TAG" -R "$REPO" --title "Barrly $VERSION" --generate-notes >/dev/null

echo "==> tap formula: $TAG ($TAP)"
TAPDIR="$(brew --repository "$TAP")"
[ -d "$TAPDIR/.git" ] || brew tap "$TAP"
( cd "$TAPDIR" && git pull -q --ff-only )
TAPF="$TAPDIR/$FORMULA"
cp "$FORMULA" "$TAPF"   # the repo's formula is the source of truth; the tap gets tag, revision and bottle on top
perl -0777 -i -pe 's/(tag:\s+")[^"]+(",\n\s+revision:\s+")[0-9a-f]{40}(")/${1}'"$TAG"'${2}'"$REV"'${3}/s' "$TAPF"
perl -0777 -i -pe 's/\n  # Prebuilt[^\n]*\n  bottle do.*?\n  end\n//s' "$TAPF"   # previous version's bottle

echo "==> bottle (built from source once, ad-hoc signed)"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
brew uninstall --ignore-dependencies "$TAP/barrly" >/dev/null 2>&1 || true
brew install --build-bottle "$TAP/barrly" 2>&1 | grep -E "🍺|Error" || true
( cd "$WORK" && brew bottle --no-rebuild --json --root-url="$ROOT_URL" "$TAP/barrly" 2>&1 | grep -E "sha256|Error" )
BOTTLE=$(ls "$WORK"/barrly--*.bottle.tar.gz)
NATIVE_TAG=$(basename "$BOTTLE" | sed -E "s/^barrly--$VERSION\.(.*)\.bottle\.tar\.gz$/\1/")
SHA=$(shasum -a 256 "$BOTTLE" | cut -d' ' -f1)
# The binary targets macOS 26 (Package.swift), so the same tarball serves every macOS it runs on;
# Homebrew only pours a bottle whose tag matches the host, hence one upload per tag.
ASSETS=(); BLOCK=""
for T in $(printf '%s\n' "$NATIVE_TAG" arm64_tahoe | sort -u); do
  cp "$BOTTLE" "$WORK/barrly-$VERSION.$T.bottle.tar.gz"; ASSETS+=("$WORK/barrly-$VERSION.$T.bottle.tar.gz")
  BLOCK+="    sha256 cellar: :any, $T: \"$SHA\""$'\n'
done

echo "==> app zip (self-contained: adapter inside the bundle, unlike the Homebrew layout)"
[ -d Vendor/build/MediaRemoteAdapter.framework ] || scripts/build-adapter.sh
swift build -c release 2>&1 | grep -E "error:" || true
STAGE="$WORK/stage"; mkdir -p "$STAGE/MediaRemoteAdapter"
cp -R Vendor/build/MediaRemoteAdapter.framework Vendor/build/mediaremote-adapter.pl Vendor/build/MediaRemoteAdapterTestClient "$STAGE/MediaRemoteAdapter/"
BARRLY_SIGN_IDENTITY=- scripts/bundle.sh .build/release/Barrly Barrly dev.barrly.app "$WORK" "$STAGE" >/dev/null
ZIP="$WORK/Barrly-$VERSION.zip"
if [ -n "${BARRLY_DEVELOPER_ID:-}" ]; then
  # Notarized copy for people who do not use Homebrew (no Gatekeeper warning).
  codesign --force --deep --options runtime --timestamp --sign "$BARRLY_DEVELOPER_ID" "$WORK/Barrly.app"
  ditto -c -k --keepParent "$WORK/Barrly.app" "$ZIP"
  xcrun notarytool submit "$ZIP" --keychain-profile "${BARRLY_NOTARY_PROFILE:-barrly-notary}" --wait
  xcrun stapler staple "$WORK/Barrly.app"; rm "$ZIP"
fi
ditto -c -k --keepParent "$WORK/Barrly.app" "$ZIP"
codesign --verify --deep --strict "$WORK/Barrly.app"
gh release upload "$TAG" -R "$REPO" --clobber "${ASSETS[@]}" "$ZIP" >/dev/null

echo "==> tap formula: bottle block"
export ROOT_URL BLOCK
perl -0777 -i -pe 's/(  head "[^"]+", branch: "main"\n)/$1 . "\n  # Prebuilt on Apple Silicon with the macOS 26 deployment target; one tarball serves every tag.\n  bottle do\n    root_url \"$ENV{ROOT_URL}\"\n$ENV{BLOCK}  end\n"/se' "$TAPF"
( cd "$TAPDIR" && git add "$FORMULA" && git commit -qm "barrly $VERSION" && git push -q origin HEAD )
cp "$TAPF" "$FORMULA"
git add "$FORMULA" && git commit -qm "Formula: $VERSION" && git push -q origin HEAD

echo "==> brew reinstall (pours the bottle)"
brew uninstall --ignore-dependencies "$TAP/barrly" >/dev/null 2>&1 || true
brew install "$TAP/barrly" 2>&1 | grep -E "Pouring|🍺|Error" || true
if pgrep -x Barrly >/dev/null; then pkill -x Barrly; sleep 1; fi
"$(brew --prefix)/bin/barrly"
echo "released $TAG"
