# Glidex v1 Input Validation

## Automated Glidex Path

The raw-frame fixtures under `Tests/GlidexCoreTests/Fixtures` replay through the
production `GestureCoordinator` and a recording `TouchSink`. They cover left and
right Navigate swipes, rapid reversal, pinch, explicit Edge mode, and accidental
single-finger input.

Replay requires exactly one begin and one end for each recognized gesture and no
mouse/tap transaction from raw input. Navigate is replayed with different pointer
positions to prove that cursor movement does not change its anchor.

## Simulator Result Baseline

On June 10, 2026, XcodeBuildMCP booted iOS 18.6 on iPhone 16 Pro
`53CC2D84-516F-4DF5-9FF9-CDD32B610B77`. A direct XcodeBuildMCP left swipe moved
the Home Screen from the first page to the second page. This proves that the
target UI responds to the expected gesture, but it is not evidence for the
Glidex injection path.

The Glidex path is verified by fixture replay or real capture input only.

## Manual Feel Check

1. In Navigate, perform short and long left/right swipes after moving the mouse
   to unrelated positions. The swipe start should not move.
2. Reverse direction quickly and lift either finger first. No app icon or row
   should receive an extra tap.
3. In Point, move the orange virtual finger and confirm raw gestures begin there.
4. In Edge, test all four anchors. Notification Center and Control Center should
   occur only in this explicit mode.
5. Switch to Disabled during a gesture and confirm the contact ends.

The automated macOS GUI launch was unavailable because the external execution
approval quota was exhausted. Build, tests, fixture replay, Simulator UI
snapshot, and the direct result baseline were still run.
