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
- **Structured logging** — all API calls logged via `os.log`, viewable in Console.app.
- **Privacy-first** — no accounts, no cloud, no telemetry. All data stays on your machine.

## Install

Download the latest DMG from [GitHub Releases](https://github.com/Matyss/quota-stats/releases/latest), or visit the [landing page](https://matyss.github.io/quota-stats/).

1. Open the DMG, drag `QuotaStats.app` to `/Applications`
2. Remove the quarantine flag (required because the app is not notarized):
   ```bash
   xattr -cr /Applications/QuotaStats.app
   ```
3. Open the app. When prompted for Keychain access, enter your login password and click **Always Allow**
4. Done — quota appears in your menu bar

> **Why is this needed?** macOS quarantines all downloaded apps. Notarized apps pass automatically, but since QuotaStats isn't notarized yet, you need to clear the quarantine manually. Without this step, macOS Sequoia shows a misleading "app is damaged" error.

### Prerequisites

- macOS 14.0+
- **Cursor IDE** installed and signed in
- **Claude Code** installed and authenticated at least once (`claude` in terminal → sign in)

## Development

### Build from source

```bash
cd QuotaStats
xcodebuild -project QuotaStats.xcodeproj -scheme QuotaStats -configuration Release -derivedDataPath build
```

The built app is at `build/Build/Products/Release/QuotaStats.app`.

### Run during development

```bash
# Build and launch
xcodebuild -project QuotaStats.xcodeproj -scheme QuotaStats -configuration Debug -derivedDataPath build
open build/Build/Products/Debug/QuotaStats.app

# Or build + deploy + launch in one shot
xcodebuild -project QuotaStats.xcodeproj -scheme QuotaStats -configuration Release -derivedDataPath build \
  && rm -rf /Applications/QuotaStats.app \
  && cp -R build/Build/Products/Release/QuotaStats.app /Applications/ \
  && open /Applications/QuotaStats.app
```

To kill a running instance before relaunching:

```bash
osascript -e 'quit app "QuotaStats"'
```

### Debugging

View live logs in Terminal:

```bash
/usr/bin/log stream --predicate 'subsystem == "com.matt.quotastats"' --info --debug
```

View recent logs:

```bash
/usr/bin/log show --predicate 'subsystem == "com.matt.quotastats"' --last 5m --info --debug
```

Log categories: `CursorAPI`, `ClaudeAPI`, `Store`. Filter with:

```bash
/usr/bin/log stream --predicate 'subsystem == "com.matt.quotastats" AND category == "ClaudeAPI"' --info --debug
```

### Testing changes

There is no automated test suite yet. Manual testing workflow:

1. Make changes to Swift files
2. Build: `xcodebuild -project QuotaStats.xcodeproj -scheme QuotaStats -configuration Debug -derivedDataPath build`
3. Quit running instance: `osascript -e 'quit app "QuotaStats"'`
4. Launch: `open build/Build/Products/Debug/QuotaStats.app`
5. Check menu bar icon appears with correct data
6. Open popover, verify both Cursor and Claude sections display
7. Toggle settings checkboxes, verify menu bar updates after closing popover
8. Tail logs to verify no errors: `/usr/bin/log stream --predicate 'subsystem == "com.matt.quotastats"' --info --debug`

### Test the API clients independently

```bash
# Cursor — verify credentials are readable and API responds
curl -s -H "Cookie: WorkosCursorSessionToken=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null | echo 'skip')" \
  "https://cursor.com/api/usage?user=YOUR_USER_ID"

# Claude — verify token and usage endpoint
TOKEN=$(security find-generic-password -s "Claude Code-credentials" -w | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['claudeAiOauth']['accessToken'])")
curl -s -H "Authorization: Bearer $TOKEN" -H "anthropic-beta: oauth-2025-04-20" \
  "https://api.anthropic.com/api/oauth/usage"
```

## Releases

Releases are automated via GitHub Actions. To ship a new version:

```bash
# 1. Make and commit your changes
git add -A && git commit -m "description of changes"

# 2. Tag with semver
git tag v1.1.0

# 3. Push (triggers CI)
git push origin main --tags
```

The CI workflow (`.github/workflows/release.yml`) will:
1. Build the app on macOS 14
2. Set the version from the git tag into `Info.plist`
3. Package a DMG with drag-to-Applications
4. Create a GitHub Release with the DMG attached
5. Update the Sparkle `appcast.xml` on `gh-pages` branch

The release appears at `https://github.com/Matyss/quota-stats/releases/tag/v1.1.0`.

### Version convention

- Bump **patch** (`v1.0.1`) for bug fixes
- Bump **minor** (`v1.1.0`) for new features
- Bump **major** (`v2.0.0`) for breaking changes

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

### Credential sources

| Service | Source | Details |
|---------|--------|---------|
| Cursor | `~/Library/Application Support/Cursor/sentry/scope_v3.json` | User ID |
| Cursor | `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb` | Access token (SQLite) |
| Claude Code | macOS Keychain (`Claude Code-credentials`) | OAuth access/refresh tokens, auto-refreshed on expiry |

No credentials leave your machine. All API calls go directly from your Mac to Cursor/Anthropic servers.

## Security

- **No credentials are stored in this repository.** All secrets (tokens, passwords) are read at runtime from the user's local machine (Keychain, application data files).
- The `.gitignore` excludes common credential file patterns (`.env`, `*.pem`, `*.key`, etc.).
- The Claude OAuth `clientId` in the source code is a public identifier (embedded in the Claude Code CLI binary) — it is not a secret.
- The app runs without a backend. There is no server, no analytics, no telemetry, no data collection.

## License

MIT
