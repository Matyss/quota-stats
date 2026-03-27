# QuotaStats

A native macOS menu bar app that displays real-time quota usage for **Cursor IDE** and **Claude Code**.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange)

## Features

- **Cursor IDE** — shows request count (e.g. `270/500`) with a colored progress ring and billing period reset date.
- **Claude Code** — shows 5-hour and 7-day utilization windows with individual progress rings and reset countdowns.
- **Menu bar customization** — choose which metrics appear in the top bar (Cursor, Claude 5h, Claude 7d). The popover always shows everything.
- **Auto-refresh** — polls APIs every 5 minutes (configurable).
- **Launch at Login** via `SMAppService`.
- **Local timezone** — all dates/times displayed in the user's timezone.

## Architecture

```
QuotaStats/
├── QuotaStatsApp.swift          # App entry point, wires AppDelegate
├── AppDelegate.swift            # NSStatusItem, NSPopover, menu bar rendering
├── Models/
│   └── UsageData.swift          # Codable API models, shared utilities
├── Services/
│   ├── CursorAPIClient.swift    # Reads Cursor credentials (SQLite + JSON), calls usage API
│   ├── ClaudeAPIClient.swift    # Reads OAuth from Keychain, handles token refresh, calls usage API
│   └── UsageStore.swift         # ObservableObject state, polling timer, concurrent fetching
└── Views/
    ├── PopoverView.swift        # SwiftUI popover with sections, settings, footer
    └── ProgressRing.swift       # Reusable circular progress indicator
```

## Credential Sources

| Service | Source | Details |
|---------|--------|---------|
| Cursor | `~/Library/Application Support/Cursor/sentry/scope_v3.json` | User ID |
| Cursor | `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb` | Access token (SQLite) |
| Claude Code | macOS Keychain (`Claude Code-credentials`) | OAuth access/refresh tokens, auto-refreshed on expiry |

## Requirements

- macOS 14.0+
- Xcode 15+ (to build)
- Active Cursor IDE and/or Claude Code subscriptions

## Build & Install

```bash
cd QuotaStats
xcodebuild -project QuotaStats.xcodeproj -scheme QuotaStats -configuration Release -derivedDataPath build
cp -R build/Build/Products/Release/QuotaStats.app /Applications/
open /Applications/QuotaStats.app
```

## License

MIT
