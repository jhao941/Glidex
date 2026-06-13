# Glidex

Glidex is a quiet macOS menu bar app and reusable Swift core for operating a booted iPhone Simulator from Mac input. It dynamically loads the same broad private-framework stack historically proven by Facebook's FBSimulatorControl and idb work: CoreSimulator device discovery, SimulatorKit's legacy HID client, and Indigo digitizer messages. Glidex does not depend on idb directly; that project is the architectural reference and prior art for this technical path.

Current scope:

- discover booted simulators
- dynamically load `CoreSimulator.framework` and `SimulatorKit.framework`
- probe `SimServiceContext`, `SimDeviceSet`, `SimDeviceLegacyHIDClient`, and Indigo HID symbols
- inject `tap`, `drag`, and `pinch` through Indigo HID
- capture raw trackpad frames through MultitouchSupport
- map mouse and two-finger trackpad input through a testable transaction pipeline
- attach to either Xcode 27 Device Hub or the legacy Simulator app through Accessibility APIs
- run as an accessory app with a transparent, border-only input overlay
- persist enablement, input mode, anchor lock preference, border visibility, and independent indicator preferences

Current non-goals:

- no public/private-API compatibility guarantee across macOS and Xcode releases
- no complete onboarding, signing, or distribution workflow
- no compatibility guarantee for future private-framework ABI changes

## Layout

```text
.
├── Package.swift
├── README.md
└── Sources
    ├── CGlidexShim
    │   ├── CGlidexShim.m
    │   ├── IndigoMessageBuilder.h
    │   ├── IndigoMessageBuilder.m
    │   └── include
    ├── GlidexCore
    │   ├── SimulatorInjector.swift
    │   ├── IndigoHIDBackend.swift
    │   ├── TouchMessageBuilder.swift
    │   └── ...
    ├── GlidexCapture
    │   ├── AppMain.swift
    │   ├── AppController.swift
    │   ├── CaptureSession.swift
    │   ├── CaptureView.swift
    │   ├── OverlayWindowController.swift
    │   ├── StatusItemController.swift
    │   └── SimulatorWindowTracker.swift
    └── glidexCLI
        ├── CLI.swift
        └── main.swift
```

Key files:

- `Sources/GlidexCore/BootedSimulatorResolver.swift`: booted simulator discovery, `simctl` fallback, and CoreSimulator probing
- `Sources/GlidexCore/SimulatorKitLoader.swift`: dynamic loading and Indigo symbol resolution
- `Sources/GlidexCore/DeveloperDirectoryResolver.swift`: host-Xcode, `xcode-select`, and standard Xcode resolution
- `Sources/GlidexCore/SimulatorDisplayHost.swift`: shared host descriptors and unambiguous booted-device matching
- `Sources/GlidexCore/IndigoHIDBackend.swift`: current injection backend
- `Sources/GlidexCore/SimulatorInjector.swift`: command orchestration
- `Sources/GlidexCore/GestureSynthesizer.swift`: higher-level gesture sequencing
- `Sources/GlidexCore/TouchMessageBuilder.swift`: Indigo digitizer message construction
- `Sources/GlidexCore/GestureInterpreter.swift`: pure raw-frame gesture state machine
- `Sources/GlidexCore/TouchTransaction.swift`: begin/update/end/cancel lifecycle and injectable `TouchSink`
- `Sources/GlidexCore/RawTouchStream.swift`: formal raw trackpad stream above isolated MultitouchSupport ABI bindings
- `Sources/GlidexCore/GestureCoordinator.swift`: input arbitration, anchor selection, coordinate mapping, and transaction ownership
- `Sources/GlidexCapture/CaptureSession.swift`: automatic attachment, raw stream lifetime, error recovery, and coordinator wiring
- `Sources/GlidexCapture/OverlayWindowController.swift`: transparent window geometry, passthrough, and calibration
- `Sources/GlidexCapture/CaptureView.swift`: border/touch-indicator drawing and AppKit responder entry points
- `Sources/GlidexCapture/SimulatorWindowTracker.swift`: Device Hub and legacy Simulator host adapters and screen-region tracking
- `Sources/CGlidexShim/*`: tiny C shim for Objective-C runtime method enumeration and message construction helpers

## Build

```bash
cd /Users/hao/Code/Glidex
swift build
swift test
```

## Run

```bash
swift run glidex list
swift run glidex probe
swift run glidex tap --x 120 --y 300
swift run glidex drag --from 120,300 --to 120,700 --duration 0.5
swift run glidex pinch --center 200,400 --scale 1.2 --duration 0.5
swift run glidex pinch --center 200,400 --scale 0.8 --duration 0.5
```

## Capture App

```bash
swift run glidex-capture
```

Glidex starts as an accessory app with no Dock icon and no debug window. When Accessibility permission is available, it discovers displays from Xcode 27 Device Hub (`com.apple.dt.Devices`) and the legacy Simulator app (`com.apple.iphonesimulator`). Device Hub uses its `iOSContentGroup` as the display region and prefers an exact CoreDevice UDID match. Legacy Simulator retains its AX region and aspect-ratio fallback. If both hosts are visible, an exact UDID match wins; otherwise ambiguous candidates are rejected instead of choosing the first one.

Private framework loading follows the selected host's containing Xcode first, then `xcode-select`, then standard Xcode locations. This supports Device Hub's Xcode-level `SharedFrameworks/SimulatorKit.framework` layout without permanently assuming `/Applications/Xcode.app`.

The menu bar controls provide:

- enable/pause with safe input passthrough
- Navigate, Direct Touch, Point, and Edge modes (Navigate is the default)
- Hidden, Subtle, Normal, and Strong border visibility
- Lock Anchor / Edit Anchor Position in Point and Edge modes
- independent Show Anchor Indicator and Show Active Touches switches
- Simulator input constraint and reconnect controls
- a copyable Diagnostics window with runtime, permission, host, and input-pipeline details
- Calibration Mode from Diagnostics, plus About and Quit actions

In Navigate mode, hold Option when a raw trackpad gesture begins to anchor only that gesture at the current mouse position inside the Simulator. The modifier, desktop mouse position, converted Simulator point, and final anchor policy are latched once at gesture begin. Releasing Option mid-gesture does not move or cancel the transaction. A pointer outside the Simulator safely falls back to ordinary Navigate behavior.

Point and Edge have an explicit lock state rather than another input mode. Unlocked edits the fixed anchor and does not inject mouse input; its orange dashed border makes that ownership visible. Locked keeps the anchor fixed while ordinary mouse tap/drag works normally. Switching the lock cancels any active transaction. Device attachment safely starts unlocked.

Edge chooses the nearest edge from the fixed anchor. Leading/trailing preserve the anchor's exact vertical position, while top/bottom preserve its horizontal position; the raw gesture centroid no longer changes the along-edge coordinate.

The overlay supports:

- click and drag -> live single-touch transaction
- two-finger movement -> live navigation transaction
- finger separation -> live two-contact pinch transaction
- an Anchor Indicator for Point/Edge anchors and Navigate+Option temporary anchors
- Active Touch indicators sourced from actual `TouchTransaction` begin/update/end/cancel events
- calibration mode: drag the overlay to move it or drag its lower-right corner to resize it

The window itself always remains fully opaque at the compositor level (`alphaValue = 1`). Only the inset border is drawn, so lowering border visibility never makes Simulator content dim or washed out. Paused and error states cancel active transactions before enabling click-through.

Simulator lifecycle recovery uses Accessibility moved, resized, destroyed, and layout-changed notifications plus a low-frequency health poll. Device Hub caches its `iOSContentGroup` and rebuilds the AX lookup only when that element becomes invalid. Geometry changes synchronously cancel active input and update the selected target, overlay frame, oriented screen metrics, and `CoordinateMapper`. Quartz/AppKit conversion uses the main display's global coordinate basis and supports displays positioned to either side or above the main display.

The default raw-touch path follows the stable behavior established by commit `eb4da18` (`Make raw touch the default capture path`). Navigate uses the raw gesture centroid and is independent of mouse position. Point uses the explicitly moved virtual finger. Edge gestures are produced only in Edge mode and use the nearest edge to that marker.

Input flows through explicit boundaries:

```text
TouchSource -> GestureInterpreter -> AnchorPolicy -> TouchTransaction -> TouchSink
```

The gesture interpreter, coordinate mapper, host/target selection, anchor policy, indicator lifecycle, overlay policy, and transaction lifecycle are pure logic covered by Swift Testing. `CaptureView` owns only AppKit responder events and drawing. Mouse events use one responder path; there is no parallel local event monitor or timestamp-based deduplication.

Raw-frame fixtures replay through the production `GestureCoordinator`; see [`docs/v1-input-validation.md`](docs/v1-input-validation.md) for the automated/manual validation boundary.
The menu bar and lifecycle validation record is in [`docs/menu-bar-validation.md`](docs/menu-bar-validation.md).

## Current status

What is implemented:

- `glidex list`
  - uses `xcrun simctl list devices booted --json`
  - also probes `SimServiceContext` and `SimDeviceSet` if `CoreSimulator.framework` loads
- `glidex probe`
  - loads `CoreSimulator.framework`
  - loads `SimulatorKit.framework`
  - enumerates selected Objective-C selectors on `SimServiceContext`, `SimDeviceSet`, and `SimulatorKit.SimDeviceLegacyHIDClient`
  - resolves:
    - `IndigoHIDMessageForMouseNSEvent`
    - `IndigoHIDMessageForScrollEvent`
    - `IndigoHIDTargetForScreen`
- `tap`, `drag`, `pinch`
  - emit detailed logs
  - `tap` and `drag` now reach a real private call chain:
    - `SimServiceContext`
    - `SimDeviceSet`
    - `SimDevice`
    - `SimulatorKit.SimDeviceLegacyHIDClient`
    - handcrafted digitizer `IndigoHIDMessageStruct` frames
    - `sendWithMessage:freeWhenDone:completionQueue:completion:`
- the capture app
  - runs from the menu bar as an accessory application
  - automatically attaches to one unambiguous Device Hub or legacy Simulator screen
  - consumes MultitouchSupport raw frames through `RawTouchStream`
  - injects through an `IndigoTouchSink`
  - emits structured touch lifecycle logs containing gesture ID, source, intent, anchor, phase, and contacts
  - releases active transactions before pause, error passthrough, target change, raw-stream stop, and shutdown

What still needs broader compatibility coverage:

- robust behavior across multiple booted simulators
- additional Xcode 27 beta builds if Device Hub AX metadata or private symbols change
- multi-contact pinch behavior across apps such as Maps, Photos, and Safari
- foreground, background, and hidden host behavior across more macOS/Xcode combinations

## Backend hypotheses

Most likely backend candidates, in order:

1. `SimServiceContext -> SimDeviceSet -> SimDevice -> SimDeviceLegacyHIDClient(device:)`
2. handcrafted digitizer / touch `IndigoHIDMessageStruct` frames sent through the HID client
3. the macOS overlay collects trackpad gestures and calls the reusable injection core directly

Observed on this machine during LLDB-assisted probing:

- main handset display: `screenID=1`
- external TV out display: `screenID=2`
- one observed main-screen description: `size=1206x2622@3x`

## Reference projects

- [Baguette](https://github.com/tddworks/baguette)
  - confirms modern `SimulatorKit` private SPI and headless / streamed simulator control are viable
- [AXe](https://github.com/cameroncooke/AXe)
  - confirms a modern standalone CLI approach and HID-based simulator automation are viable
- [FBSimulatorControl / idb docs](https://fbidb.io/docs/fbsimulatorcontrol/)
  - establishes the historical `CoreSimulator + SimulatorKit/Indigo HID` approach that Glidex follows independently

Glidex intentionally does not depend on those projects directly. They remain architecture references and ABI sanity checks, especially because this private framework surface is undocumented and version-sensitive.

## Validation matrix

Record these before testing:

- macOS version
- Xcode version
- CPU architecture: Apple Silicon or Intel
- booted simulator model
- app under test inside the simulator

Run these checks:

1. `glidex list`
   - confirm the selected booted iPhone simulator is correct
2. `glidex probe`
   - confirm the private frameworks load and the expected symbols resolve
3. foreground tap
   - bring `Simulator.app` to the front
   - run `glidex tap --x 120 --y 300`
   - note whether the target app visibly receives a touch
   - current known behavior: the private call chain completes without throwing, but a visible UI transition still needs confirmation
4. background tap
   - keep the simulator booted but move another app to the foreground
   - rerun the same tap
   - note whether background injection still lands
5. no visible GUI
   - if possible, keep the simulator device booted without relying on a visible Simulator window
   - rerun tap
6. coordinate sanity
   - test at least one small phone and one large phone
   - portrait and landscape
   - different simulator scale factors in `Simulator.app`
7. drag continuity
   - test `glidex drag --from 120,500 --to 120,200 --duration 0.5`
   - note whether scrolling is continuous or only lands as a tap
8. pinch open / close
   - test in Maps, Photos, and Safari where zoom is obvious
   - note whether open and close are both recognized

## Failure reporting

If a command fails, collect:

- full `glidex` logs
- whether `Simulator.app` was foreground, background, or hidden
- current simulator model and orientation

Set `GLIDEX_DUMP_HID_MESSAGES=1` only when debugging raw Indigo message layout. It is intentionally off during capture use because it formats private binary message buffers on every injected touch.

Recommended manual commands:

```bash
SIMULATOR_KIT=/Applications/Xcode-beta.app/Contents/SharedFrameworks/SimulatorKit.framework/SimulatorKit
nm -gU "$SIMULATOR_KIT" | rg 'Indigo|LegacyHID|SimDeviceScreen'
strings "$SIMULATOR_KIT" | rg 'SimDeviceLegacyHIDClient|send|device|screen'
nm -gU /Library/Developer/PrivateFrameworks/CoreSimulator.framework/CoreSimulator | rg 'SimServiceContext|SimDeviceSet|SimDeviceIO'
swift-demangle '$s12SimulatorKit24SimDeviceLegacyHIDClientC6deviceACSo0cD0C_tKcfC'
swift-demangle '$s12SimulatorKit24SimDeviceLegacyHIDClientC4send7messageySpySo22IndigoHIDMessageStructVG_tF'
otool -L "$SIMULATOR_KIT"
```

Suggested LLDB targets:

```bash
lldb -- swift run glidex probe
lldb -- swift run glidex tap --x 120 --y 300
```

Useful LLDB ideas:

- set breakpoints on `IndigoHIDMessageForMouseNSEvent`
- inspect `NSClassFromString(@"SimulatorKit.SimDeviceLegacyHIDClient")`
- inspect selector names on candidate classes
- capture the actual screen hookup:
  - `log show --last 2m --predicate 'process == "glidex" && eventMessage CONTAINS[c] "screen ID"'`

## Next architecture checkpoint

The next product-facing work can build on `GlidexAppState`, `CaptureSession`, `SimulatorDisplayHost`, `TouchSource`, `AnchorPolicy`, and `TouchSink` without moving private ABI code into the UI layer. Likely integration points are a first-run permission flow, an explicit target picker for genuine ambiguity, broader Device Hub version probes, and signed app packaging.
