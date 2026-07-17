#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${GLIDEX_VERSION:-$(tr -d '[:space:]' < "$ROOT/VERSION")}"
BUILD_NUMBER="${GLIDEX_BUILD_NUMBER:-$(tr -d '[:space:]' < "$ROOT/BUILD_NUMBER")}"
DIST="${GLIDEX_DIST_DIR:-$ROOT/dist}"
APP="$DIST/Glidex.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
ICON_SOURCE="$ROOT/Resources/Glidex.icon"
ICON_FALLBACK="$ROOT/Resources/Glidex.icns"

cd "$ROOT"
swift build -c release

rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"
cp ".build/release/glidex-capture" "$MACOS/Glidex"
cp ".build/release/glidex" "$DIST/glidex"
cp -R "$ROOT/Resources/Localization/"*.lproj "$RESOURCES/"

# Xcode 26 compiles Icon Composer projects into both Liquid Glass assets and
# a compatibility ICNS. Older actool versions fall back to the committed ICNS.
if ! xcrun actool "$ICON_SOURCE" \
    --compile "$RESOURCES" \
    --platform macosx \
    --minimum-deployment-target 14.0 \
    --app-icon Glidex \
    --output-partial-info-plist "$DIST/Glidex-icon-info.plist" >/dev/null 2>&1; then
    cp "$ICON_FALLBACK" "$RESOURCES/Glidex.icns"
fi

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>zh-Hans</string>
    </array>
    <key>CFBundleExecutable</key>
    <string>Glidex</string>
    <key>CFBundleIdentifier</key>
    <string>io.github.jhao941.Glidex</string>
    <key>CFBundleIconFile</key>
    <string>Glidex</string>
    <key>CFBundleIconName</key>
    <string>Glidex</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Glidex</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

plutil -lint "$CONTENTS/Info.plist"

SIGN_IDENTITY="${GLIDEX_SIGN_IDENTITY:--}"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
    if [[ "${GLIDEX_REQUIRE_SIGNING:-0}" == "1" ]]; then
        echo "GLIDEX_SIGN_IDENTITY must name a Developer ID Application certificate" >&2
        exit 1
    fi
    codesign --force --deep --sign - "$APP"
else
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$MACOS/Glidex"
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi

codesign --verify --deep --strict --verbose=2 "$APP"

echo "Built $APP"
echo "Built $DIST/glidex"
