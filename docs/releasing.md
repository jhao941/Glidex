# Releasing Glidex

## Local validation

```bash
swift build
swift test
GLIDEX_VERSION=0.1.0 GLIDEX_BUILD_NUMBER=1 ./scripts/build-app.sh
codesign --verify --deep --strict --verbose=2 dist/Glidex.app
```

Run the packaged app and manually verify Navigate, Direct Touch, pinch,
long-press drag, recording, Replay Last, and Replay Recording before tagging.

## Signing and notarization

`scripts/build-app.sh` applies only an ad-hoc signature. Public binary releases
should instead use a Developer ID Application certificate, hardened runtime,
and Apple notarization.

The repository intentionally does not contain certificate names, keychain
profiles, Apple IDs, or notarization credentials. Configure those in a private
release environment, sign the final app recursively, create a ZIP or DMG,
submit it with `notarytool`, and staple the accepted ticket before publishing.

Do not describe an artifact as notarized until these pass on the exact file:

```bash
codesign --verify --deep --strict --verbose=2 Glidex.app
spctl --assess --type execute --verbose=4 Glidex.app
xcrun stapler validate Glidex.app
```

## Source release

1. Replace `Unreleased` in `CHANGELOG.md` with the release date.
2. Confirm the README compatibility notes match tested macOS and Xcode builds.
3. Commit the release metadata.
4. Tag the commit with `vMAJOR.MINOR.PATCH`.
5. Publish source archives and only attach binaries that passed the signing and
   notarization checks above.
