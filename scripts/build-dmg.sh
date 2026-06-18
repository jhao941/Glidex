#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${GLIDEX_VERSION:-0.1.0}"
DIST="${GLIDEX_DIST_DIR:-$ROOT/dist}"
STAGING="$DIST/dmg-root"
DMG="$DIST/Glidex-$VERSION.dmg"

"$ROOT/scripts/build-app.sh"

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$DIST/Glidex.app" "$STAGING/Glidex.app"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
    -volname "Glidex" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    "$DMG"

rm -rf "$STAGING"
echo "Built $DMG"
