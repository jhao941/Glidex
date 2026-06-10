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
