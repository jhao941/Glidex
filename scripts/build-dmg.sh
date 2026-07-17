#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${GLIDEX_VERSION:-$(tr -d '[:space:]' < "$ROOT/VERSION")}"
DIST="${GLIDEX_DIST_DIR:-$ROOT/dist}"
STAGING="$DIST/dmg-root"
DMG="$DIST/Glidex-$VERSION.dmg"

if [[ "${GLIDEX_SKIP_APP_BUILD:-0}" != "1" ]]; then
    "$ROOT/scripts/build-app.sh"
fi

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$DIST/Glidex.app" "$STAGING/Glidex.app"
ln -s /Applications "$STAGING/Applications"

if diskutil image create from -h >/dev/null 2>&1; then
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
