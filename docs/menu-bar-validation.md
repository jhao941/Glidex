# Menu Bar Validation

Validated on June 10, 2026 with macOS, Xcode 26.5, and an iOS 26.5 iPhone 17 Pro Simulator (`F3E2E3CA-D0B2-46C0-AC6D-1F69E73F9F40`).

## Automated

- `swift build --disable-sandbox`
- `swift test --disable-sandbox`
- Goal 2 left/right swipe, reversal, pinch, Edge, and noise replay fixtures
- Option begin-time latch, out-of-region fallback, mid-gesture release, and Point/Edge isolation
- transaction cancellation on target loss
- portrait/landscape, scale, calibration offset, and multi-display coordinate conversion
- preference restoration and Waiting/Error input gating

## Real Simulator

- Startup automatically matched the visible iPhone 17 Pro and reached `Active`.
- The Glidex overlay matched the Simulator content region at `334 x 725`; WindowServer reported overlay alpha `1`.
- Disabling Glidex stopped the raw stream, stopped window following, entered `Paused`, and a global mouse click passed through the overlay and launched News inside Simulator.
- Re-enabling rebuilt the target, raw stream, HID session boundary, window tracker, and returned to `Active` with Navigate preserved.
- Rotating left rebuilt the overlay from portrait `334 x 725` to landscape `725 x 334`, then returned to `Active`.
- Shutting down the device stopped raw input and entered `Waiting`; booting and showing it again automatically returned to `Active`.
- With Glidex not key, pressing Option while the pointer was over Simulator changed structured state to `optionAnchor=available(201,436)` and releasing it restored `inactive`.
- A real raw-trackpad Navigate transaction traversed `begin`, repeated `update`, and one `end` through `IndigoTouchSink` on the booted Simulator.
- Selecting Edge and Navigate from the menu updated the persistent mode without creating a temporary mode during Option handling.
- Quitting from the status menu stopped the raw stream and window tracker cleanly.

## Physical Trackpad Confirmation

These checks require a person using the physical trackpad and are not replaced by direct Simulator HID injection:

1. Ordinary left and right Navigate swipes retain the established `eb4da18` feel.
2. Hold Option with the pointer over two visibly different Simulator locations; each new gesture begins at its latched location.
3. Release Option during a continuing gesture; the contact must remain continuous and anchored.
4. Point remains fixed across repeated gestures; Edge uses the nearest edge to that fixed point.
5. Pause during an active gesture and confirm exactly one release with immediate mouse passthrough.

## Device Hub And Anchor Lock - June 11, 2026

Validated with Xcode 27 beta Device Hub (`com.apple.dt.Devices`), legacy Simulator from Xcode 26.5, and booted iPhone 16 Pro `53CC2D84-516F-4DF5-9FF9-CDD32B610B77`.

- Device Hub discovery found `AXGroup` / `iOSContentGroup`, read the CoreDevice UDID, and exactly matched the booted simulator.
- The selected developer directory was `/Applications/Xcode-beta.app/Contents/Developer`; SimulatorKit loaded from Xcode beta `Contents/SharedFrameworks`.
- Hiding/showing Device Hub's sidebar moved the content frame between x=614 and x=734; the Glidex overlay followed the same frame.
- Hiding the Inspector moved the content frame to x=874; the overlay again matched it after AX notification/health polling.
- Device Hub Zoom In and Zoom Out commands completed without losing attachment. This window was already at a constrained display size, so those commands did not change the measured content frame.
- With Device Hub and legacy Simulator visible together, discovery reported both hosts and selected Device Hub because it had the exact UDID.
- After a real Device Hub click loaded Xcode beta SimulatorKit, quitting Device Hub cancelled old input and discovered only legacy Simulator. Glidex entered Error instead of loading Xcode 26.5 SimulatorKit into the same process; reopening Device Hub recovered to Active.
- Point Unlocked accepted a mouse-position edit and a click produced no touch transaction. Lock Anchor then restored a mouse begin/end transaction at the clicked simulator coordinate.
- Edge Locked produced a real raw-trackpad transaction with `intent=edge`, a fixed trailing-edge anchor `401,436.4`, repeated updates, and one end.
- Active Touch state changed from zero to one on real raw and mouse begins and returned to zero on end. Pinch two-contact rendering remains covered by the observing-sink lifecycle test.
- Anchor and Active Touch menu switches are independent and old `showsTouchIndicator` data migrates to both.
- Status symbols use template rendering and no fixed `contentTintColor`; visual light/dark menu-bar confirmation remains manual because screen capture permission was unavailable in this session.

Known compatibility boundary: once one Xcode's SimulatorKit has been loaded into Glidex, switching to a host owned by another Xcode requires restarting Glidex. The app now reports this explicitly instead of loading duplicate Objective-C classes into one process.
