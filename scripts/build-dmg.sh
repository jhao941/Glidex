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

if diskutil image create from --help >/dev/null 2>&1; then
    diskutil image create from \
        --volumeName "Glidex" \
        --format UDZO \
        "$STAGING" \
        "$DMG"
else
    hdiutil create \
        -volname "Glidex" \
        -srcfolder "$STAGING" \
        -ov \
        -format UDZO \
        "$DMG"
fi

rm -rf "$STAGING"
echo "Built $DMG"
