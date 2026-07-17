#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
BUILD_NUMBER="$(tr -d '[:space:]' < "$ROOT/BUILD_NUMBER")"
DIST="${GLIDEX_DIST_DIR:-$ROOT/dist}"
TAG="${GLIDEX_RELEASE_TAG:-}"

if [[ -n "$TAG" && "$TAG" != "v$VERSION" ]]; then
    echo "Release tag $TAG does not match VERSION v$VERSION" >&2
    exit 1
fi

export GLIDEX_VERSION="$VERSION"
export GLIDEX_BUILD_NUMBER="$BUILD_NUMBER"
export GLIDEX_REQUIRE_SIGNING=1

"$ROOT/scripts/build-app.sh"

APP_ZIP="$DIST/Glidex-$VERSION-app.zip"
rm -f "$APP_ZIP"
ditto -c -k --keepParent "$DIST/Glidex.app" "$APP_ZIP"
"$ROOT/scripts/notarize-artifact.sh" "$APP_ZIP" "$DIST/Glidex.app"

GLIDEX_SKIP_APP_BUILD=1 "$ROOT/scripts/build-dmg.sh"
DMG="$DIST/Glidex-$VERSION.dmg"
codesign --force --timestamp --sign "$GLIDEX_SIGN_IDENTITY" "$DMG"
codesign --verify --verbose=2 "$DMG"
"$ROOT/scripts/notarize-artifact.sh" "$DMG"

codesign --verify --deep --strict --verbose=2 "$DIST/Glidex.app"
spctl --assess --type execute --verbose=2 "$DIST/Glidex.app"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
DMG_NAME="$(basename "$DMG")"
(cd "$DIST" && shasum -a 256 "$DMG_NAME") > "$DMG.sha256"

echo "Release artifacts:"
echo "  $DMG"
echo "  $DMG.sha256"
