# Releasing Glidex

[English](releasing.md) | [简体中文](releasing.zh-CN.md)

The canonical marketing version and build number live in `VERSION` and
`BUILD_NUMBER`. A release tag must exactly match `v<VERSION>`.

## Local validation

```bash
swift test
./scripts/build-app.sh
./scripts/build-dmg.sh
codesign --verify --deep --strict --verbose=2 dist/Glidex.app
```

Run the packaged app and manually verify focus switching, Navigate, Direct
Touch, calibration restore, recording library operations, replay, diagnostics,
and Simplified Chinese localization before tagging.

## Local notarized build

Export a Developer ID Application identity and either a notarytool keychain
profile or Apple ID notarization credentials:

```bash
export GLIDEX_SIGN_IDENTITY="Developer ID Application: Example (TEAMID)"
export GLIDEX_NOTARY_PROFILE="glidex-notary"
./scripts/release.sh
```

To create the profile once:

```bash
xcrun notarytool store-credentials glidex-notary \
  --apple-id "developer@example.com" \
  --team-id "TEAMID" \
  --password "app-specific-password"
```

The release script signs with the hardened runtime, submits a ZIP containing
the app, staples the app, builds the DMG, submits and staples the DMG, runs
`codesign`, `spctl`, and `stapler` validation, and writes a SHA-256 file.

## GitHub Actions secrets

Configure these repository secrets before pushing a release tag:

- `DEVELOPER_ID_APPLICATION_CERT_BASE64`: base64-encoded `.p12` certificate.
- `DEVELOPER_ID_APPLICATION_CERT_PASSWORD`: password for that `.p12`.
- `DEVELOPER_ID_APPLICATION_IDENTITY`: full certificate identity displayed by
  `security find-identity -v -p codesigning`.
- `RELEASE_KEYCHAIN_PASSWORD`: a strong temporary keychain password.
- `APPLE_ID`: Apple Developer account email.
- `APPLE_TEAM_ID`: ten-character developer team ID.
- `APPLE_APP_SPECIFIC_PASSWORD`: app-specific password for notarization.

Then update `VERSION` and `BUILD_NUMBER`, commit the release, and create the
matching tag:

```bash
git tag v0.2.0
git push origin v0.2.0
```

The Release workflow verifies the tag, tests the project, creates notarized
artifacts, and publishes the DMG and checksum using the repository-scoped
`GITHUB_TOKEN`.

## Source release

1. Replace `Unreleased` in `CHANGELOG.md` with the release date.
2. Confirm the README compatibility notes match tested macOS and Xcode builds.
3. Update `VERSION` and increment `BUILD_NUMBER`.
4. Commit the release metadata and create the matching `vMAJOR.MINOR.PATCH` tag.
5. Publish only binaries produced by the notarized Release workflow.
