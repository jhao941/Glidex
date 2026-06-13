# Security and Compatibility

Glidex dynamically loads undocumented Apple frameworks and uses Accessibility
APIs to identify Simulator display regions. These interfaces can change without
notice between macOS and Xcode releases.

Glidex does not require network access and does not transmit gesture recordings.
Recordings are JSON files stored locally under:

```text
~/Library/Application Support/Glidex/Recordings/
```

Treat imported recording files as untrusted input. Glidex validates the format,
coordinates, timing, contact topology, and lifecycle before replay.

Please report security issues privately to `hao_941@icloud.com`. Include the
Glidex commit, macOS version, Xcode version, and a minimal reproduction. Do not
include private application data or unrelated system logs.
