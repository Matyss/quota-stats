# QuotaStats

A native macOS menu bar app that displays real-time quota usage for **Cursor IDE** and **Claude Code**.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange)

## Features

- **Cursor IDE** — shows request count (e.g. `270/500`) with a colored progress ring and billing period reset date.
- **Claude Code** — shows 5-hour and 7-day utilization windows with individual progress rings and reset countdowns.
- **Menu bar customization** — choose which metrics appear in the top bar (Cursor, Claude 5h, Claude 7d). The popover always shows everything.
- **Auto-refresh** — polls APIs every 5 minutes. Manual refresh via the popover button.
- **Rate limit handling** — respects Anthropic's `retry-after` headers, caches last-known data during cooldowns.
- **Launch at Login** via `SMAppService`.
- **Local timezone** — all dates/times displayed in the user's timezone.
- **Structured logging** — all API calls logged via `os.log` (subsystem `com.matt.quotastats`), viewable in Console.app.

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

No credentials leave your machine. All API calls go directly from your Mac to Cursor/Anthropic servers.

## Prerequisites

- macOS 14.0+
- **Cursor IDE** installed and signed in
- **Claude Code** installed and authenticated at least once (creates the Keychain entry)

## Build & Install

```bash
cd QuotaStats
xcodebuild -project QuotaStats.xcodeproj -scheme QuotaStats -configuration Release -derivedDataPath build
cp -R build/Build/Products/Release/QuotaStats.app /Applications/
open /Applications/QuotaStats.app
```

## Sharing with Colleagues

The app is not code-signed, so macOS Gatekeeper will block it by default.

To install a received copy:

1. Copy `QuotaStats.app` to `/Applications`
2. **Right-click** the app → **Open** (bypasses Gatekeeper on first launch)
3. When prompted for Keychain access to "Claude Code-credentials", enter your login password and click **Always Allow**
4. The app reads your local Cursor and Claude Code credentials — both must be installed and signed in on your machine

## Debugging

View live logs in Terminal:

```bash
/usr/bin/log stream --predicate 'subsystem == "com.matt.quotastats"' --info --debug
```

Or view recent logs:

```bash
/usr/bin/log show --predicate 'subsystem == "com.matt.quotastats"' --last 5m --info --debug
```

## License

MIT
