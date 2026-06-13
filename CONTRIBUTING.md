# Contributing

Glidex uses undocumented Apple frameworks and trackpad APIs. Small, focused
changes with reproducible evidence are much easier to review than broad
compatibility guesses.

## Development

Requirements:

- macOS 14 or later
- Apple Silicon
- Xcode with an iOS Simulator runtime
- Accessibility permission for the built capture app

Run the standard checks:

```bash
swift build
swift test
```

For input changes, also test an actual booted Simulator. Logs proving that a
message was sent are not enough; confirm that the Simulator visibly responds.
At minimum verify tap, drag, two-finger navigation, pinch, and Direct Touch.

## Pull requests

- Keep private-API code inside `GlidexCore`.
- Preserve begin/update/end/cancel transaction semantics.
- Never work around input races with delays, repeated sends, or device-specific
  hardcoding.
- Add pure tests for mapping, lifecycle, storage, or state-machine changes.
- Describe the macOS, Xcode, Simulator runtime, device, and app used for manual
  validation.

Do not commit generated `.build`, `.app`, or `dist` artifacts.
