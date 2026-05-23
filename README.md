# SimTouch

`simtouch` is a minimal macOS CLI proof of concept for driving a booted iPhone Simulator through dynamically loaded private frameworks. The longer-term direction is a macOS overlay app that lets a Mac trackpad operate an Xcode iOS Simulator in a style similar to iPhone Mirroring.

Current scope:

- discover booted simulators
- dynamically load `CoreSimulator.framework` and `SimulatorKit.framework`
- probe `SimServiceContext`, `SimDeviceSet`, `SimDeviceLegacyHIDClient`, and Indigo HID symbols
- scaffold `tap`, `drag`, and `pinch` commands with detailed logging

Current non-goals:

- no menu bar app
- no GUI
- no `MultitouchSupport.framework`
- no product architecture beyond the minimum needed to validate injection

## Layout

```text
.
├── Package.swift
├── README.md
└── Sources
    ├── CSimTouchShim
    │   ├── CSimTouchShim.m
    │   ├── IndigoMessageBuilder.h
    │   ├── IndigoMessageBuilder.m
    │   └── include
    └── simtouch
        ├── CLI.swift
        ├── SimulatorInjector.swift
        ├── IndigoHIDBackend.swift
        ├── TouchMessageBuilder.swift
        └── ...
```

Key files:

- `Sources/simtouch/BootedSimulatorResolver.swift`: booted simulator discovery, `simctl` fallback, and CoreSimulator probing
- `Sources/simtouch/SimulatorKitLoader.swift`: dynamic loading and Indigo symbol resolution
- `Sources/simtouch/IndigoHIDBackend.swift`: current injection backend
- `Sources/simtouch/SimulatorInjector.swift`: command orchestration
- `Sources/simtouch/GestureSynthesizer.swift`: higher-level gesture sequencing
- `Sources/simtouch/TouchMessageBuilder.swift`: Indigo digitizer message construction
- `Sources/CSimTouchShim/*`: tiny C shim for Objective-C runtime method enumeration and message construction helpers

## Build

```bash
cd /Users/hao/Code/SimTouch
swift build
```

## Run

```bash
swift run simtouch list
swift run simtouch probe
swift run simtouch tap --x 120 --y 300
swift run simtouch drag --from 120,300 --to 120,700 --duration 0.5
swift run simtouch pinch --center 200,400 --scale 1.2 --duration 0.5
swift run simtouch pinch --center 200,400 --scale 0.8 --duration 0.5
```

## Current status

What is implemented:

- `simtouch list`
  - uses `xcrun simctl list devices booted --json`
  - also probes `SimServiceContext` and `SimDeviceSet` if `CoreSimulator.framework` loads
- `simtouch probe`
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
  - `pinch` remains the next major multi-touch validation target

What is not yet verified:

- robust behavior across multiple booted simulators
- coordinate mapping across device types, orientations, and simulator scale factors
- multi-contact pinch delivery into apps such as Maps, Photos, and Safari
- foreground, background, and hidden Simulator.app behavior across macOS/Xcode versions

## Backend hypotheses

Most likely backend candidates, in order:

1. `SimServiceContext -> SimDeviceSet -> SimDevice -> SimDeviceLegacyHIDClient(device:)`
2. handcrafted digitizer / touch `IndigoHIDMessageStruct` frames sent through the HID client
3. for future UI mirroring, a macOS overlay should collect trackpad gestures and call a reusable injection core directly

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
  - documents the historical `CoreSimulator + Indigo` model and why mach/HID reverse engineering is required

This PoC intentionally does not depend on those projects directly. They are used as architecture references and ABI sanity checks.

## Validation matrix

Record these before testing:

- macOS version
- Xcode version
- CPU architecture: Apple Silicon or Intel
- booted simulator model
- app under test inside the simulator

Run these checks:

1. `simtouch list`
   - confirm the selected booted iPhone simulator is correct
2. `simtouch probe`
   - confirm the private frameworks load and the expected symbols resolve
3. foreground tap
   - bring `Simulator.app` to the front
   - run `simtouch tap --x 120 --y 300`
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
   - test `simtouch drag --from 120,500 --to 120,200 --duration 0.5`
   - note whether scrolling is continuous or only lands as a tap
8. pinch open / close
   - test in Maps, Photos, and Safari where zoom is obvious
   - note whether open and close are both recognized

## Failure reporting

If a command fails, collect:

- full `simtouch` logs
- whether `Simulator.app` was foreground, background, or hidden
- current simulator model and orientation

Recommended manual commands:

```bash
nm -gU /Applications/Xcode.app/Contents/Developer/Library/PrivateFrameworks/SimulatorKit.framework/SimulatorKit | rg 'Indigo|LegacyHID|SimDeviceScreen'
strings /Applications/Xcode.app/Contents/Developer/Library/PrivateFrameworks/SimulatorKit.framework/SimulatorKit | rg 'SimDeviceLegacyHIDClient|send|device|screen'
nm -gU /Library/Developer/PrivateFrameworks/CoreSimulator.framework/CoreSimulator | rg 'SimServiceContext|SimDeviceSet|SimDeviceIO'
swift-demangle '$s12SimulatorKit24SimDeviceLegacyHIDClientC6deviceACSo0cD0C_tKcfC'
swift-demangle '$s12SimulatorKit24SimDeviceLegacyHIDClientC4send7messageySpySo22IndigoHIDMessageStructVG_tF'
otool -L /Applications/Xcode.app/Contents/Developer/Library/PrivateFrameworks/SimulatorKit.framework/SimulatorKit
```

Suggested LLDB targets:

```bash
lldb -- swift run simtouch probe
lldb -- swift run simtouch tap --x 120 --y 300
```

Useful LLDB ideas:

- set breakpoints on `IndigoHIDMessageForMouseNSEvent`
- inspect `NSClassFromString(@"SimulatorKit.SimDeviceLegacyHIDClient")`
- inspect selector names on candidate classes
- capture the actual screen hookup:
  - `log show --last 2m --predicate 'process == "simtouch" && eventMessage CONTAINS[c] "screen ID"'`

## Next step after this checkpoint

The next useful implementation step is not `MultitouchSupport`. It is to split the current CLI into a reusable core and a thin command-line wrapper:

1. create a `SimTouchCore` SwiftPM target
2. keep `simtouch` as a CLI executable target
3. preserve current `list`, `probe`, `tap`, `drag`, and `pinch` behavior
4. build a macOS overlay app on top of the same core in a later round
