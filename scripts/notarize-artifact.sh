#!/bin/bash
set -euo pipefail

ARTIFACT="${1:?usage: notarize-artifact.sh SUBMISSION [STAPLE_TARGET]}"
STAPLE_TARGET="${2:-$ARTIFACT}"

if [[ -n "${GLIDEX_NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$ARTIFACT" \
        --keychain-profile "$GLIDEX_NOTARY_PROFILE" \
        --wait
else
    : "${APPLE_ID:?APPLE_ID is required}"
    : "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required}"
    : "${APPLE_APP_SPECIFIC_PASSWORD:?APPLE_APP_SPECIFIC_PASSWORD is required}"
    xcrun notarytool submit "$ARTIFACT" \
        --apple-id "$APPLE_ID" \
        --team-id "$APPLE_TEAM_ID" \
        --password "$APPLE_APP_SPECIFIC_PASSWORD" \
        --wait
fi

xcrun stapler staple "$STAPLE_TARGET"
xcrun stapler validate "$STAPLE_TARGET"
