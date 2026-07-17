# Glidex

[English](README.md) | [简体中文](README.zh-CN.md)

<p align="center">
  <img src="docs/images/glidex-default.png" alt="Glidex icon" width="280">
  <img src="docs/images/glidex-dark.png" alt="Glidex icon" width="280">
</p>

Glidex turns a Mac trackpad into multitouch input for a booted iPhone
Simulator. It is a lightweight macOS menu bar app with Navigate, anchored
Point/Edge input, one-to-five-finger Direct Touch, and gesture recording and
replay.

Glidex supports both the legacy Simulator app and Xcode Device Hub. It uses
undocumented Apple frameworks and trackpad APIs, so compatibility can change
between macOS and Xcode releases.

## Features

- Trackpad navigation, pinch, rotation, click, long press, and drag
- Direct Touch mapping for one to five physical contacts
- Point and Edge modes with editable fixed anchors
- Device Hub and legacy Simulator window tracking
- Optional Simulator visibility and pointer constraints
- Anchor and active-touch indicators
- Versioned JSON gesture recording and deterministic replay
- Recording library with rename, import/export, playback speed, and looping
- Per-host, per-device calibration profiles
- Compatibility self-check and one-click diagnostics bundle export
- English and Simplified Chinese app localization
- Menu bar controls, diagnostics, and a small automation CLI

## Requirements

- macOS 14 or later
- Apple Silicon Mac
- Xcode with an iOS Simulator runtime
- One visible, booted iPhone Simulator for automatic attachment
- Accessibility permission for Glidex

The current implementation is tested primarily with recent Xcode and Device
Hub builds. Intel Macs and physical iOS devices are not supported.

## Build and Run

```bash
git clone https://github.com/jhao941/Glidex.git
cd Glidex
swift build
swift test
swift run glidex-capture
```

On first launch, allow Glidex in **System Settings > Privacy & Security >
Accessibility**, then choose **Reconnect to Simulator** from the menu bar.

To build a local app bundle and CLI:

```bash
./scripts/build-app.sh
open dist/Glidex.app
```

Without environment overrides the script produces an ad-hoc-signed development
app. Set `GLIDEX_SIGN_IDENTITY` to a Developer ID Application identity for a
hardened-runtime build.

To build a drag-to-install disk image:

```bash
./scripts/build-dmg.sh
```

The resulting versioned DMG contains Glidex and an Applications
shortcut. It has the same signing status as the app bundle inside it.

`VERSION` and `BUILD_NUMBER` are the repository's canonical release values.
They can be overridden locally with `GLIDEX_VERSION` and
`GLIDEX_BUILD_NUMBER`. Tagged releases use `.github/workflows/release.yml` to
import a Developer ID certificate, notarize and staple both the app and DMG,
create a SHA-256 checksum, and publish a GitHub Release. See
[`docs/releasing.md`](docs/releasing.md) for the required secrets and release
procedure.

## Input Modes

### Navigate

The default mode. A trackpad gesture moves one virtual touch; two fingers can
navigate, pinch, and rotate. Mouse click, long press, and drag map to ordinary
single-touch input.

Hold Option when a raw gesture begins to anchor that gesture at the current
pointer position inside the Simulator.

### Direct Touch

Maps the trackpad surface to the Simulator screen. One physical finger becomes
one Simulator contact, two fingers become two contacts, and so on up to five.
Use `Control-Option-D` to switch between Direct Touch and the previous mode.

### Point and Edge

Point uses a fixed virtual finger location. Edge selects the nearest screen
edge while preserving the anchor position along that edge. Unlock the anchor to
edit it, then lock it to inject input.

## Recording and Replay

Open **Automation** in the menu bar:

1. Choose **Start Recording**.
2. Perform one or more gestures.
3. Choose **Stop and Save Recording**.
4. Use **Replay Last Recording** or **Replay Recording…**.

Choose **Manage Recordings…** to rename, delete, import, export, change replay
speed, or loop a recording.

Recordings are stored in:

```text
~/Library/Application Support/Glidex/Recordings/
```

Coordinates are normalized, so compatible recordings can replay on different
Simulator sizes. Replay blocks live input and reliably releases active contacts
when stopped, interrupted, or detached.

## CLI

The CLI is intentionally small. It exposes useful injection and replay actions
without trying to replace idb or become a general device automation platform.

```bash
swift run glidex list
swift run glidex tap --x 120 --y 300
swift run glidex live-drag --from 120,700 --to 120,300 --duration 0.5
swift run glidex pinch --center 200,400 --scale 1.2 --duration 0.5
swift run glidex recordings list
swift run glidex recordings replay --file gesture.json --rate 1.0
```

When multiple simulators are booted, add `--udid DEVICE_UDID` to replay.

## Architecture

Input flows through explicit, testable boundaries:

```text
RawTouchStream -> GestureInterpreter -> AnchorPolicy
               -> TouchTransaction -> TouchSink -> Simulator HID
```

Replay enters at `TouchSink`, after gesture recognition, and therefore preserves
the exact recorded contact lifecycle for every input mode. Private ABI loading
is isolated in `GlidexCore`; AppKit menu and window code lives in
`GlidexCapture`.

See [input validation](docs/v1-input-validation.md) and [menu validation](docs/menu-bar-validation.md)
for deeper implementation notes.

## Known Limitations

- Apple private APIs can break after an Xcode or macOS update.
- Automatic attachment rejects ambiguous Simulator windows instead of guessing.
- Some Simulator or system UI builds have their own gesture bugs. Validate on
  more than one iOS runtime before attributing behavior to Glidex.
- A successful HID send log does not prove the target UI responded.
- Local builds are ad-hoc signed unless a Developer ID identity is supplied.

## Privacy and Security

Glidex does not require network access and does not upload recordings. Imported
JSON is validated before replay. See [SECURITY.md](SECURITY.md) for reporting and
compatibility details.

## Contributing

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) before changing
input lifecycle or private-framework code.

## License

Glidex is available under the [MIT License](LICENSE).

The project is independent of Meta, Apple, idb, and FBSimulatorControl. Glidex
does not depend on or bundle those libraries. A reduced Indigo wire-layout
header is adapted from FBSimulatorControl under the MIT License; see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
