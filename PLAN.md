# QuotaStats — Product Roadmap

## Distribution Model

Direct download (DMG). Mac App Store is not feasible — sandbox blocks credential reading.

For internal/teammate sharing: just zip the `.app` and send. Right-click > Open bypasses Gatekeeper.
Apple Developer Program ($99/yr) only needed when distributing publicly (notarization).

## V1 User Journey

1. Download DMG / receive zip from teammate
2. Drag to Applications, launch
3. First launch: welcome screen shows detection status for Cursor + Claude Code
4. If both installed and signed in → works immediately, menu bar shows quota
5. If something missing → clear error with recovery instructions
6. Settings: toggle menu bar metrics, refresh interval, launch at login
7. Notifications at 80%/100% quota thresholds
8. Auto-updates via Sparkle (public release only)

## MoSCoW

### Must Have

| # | Task | Effort | Notes |
|---|------|--------|-------|
| M1 | Error recovery UX (replace print logs with UI states) | 1 day | Each error: what, why, action to fix |
| M2 | Prerequisites detection (Cursor installed? Claude signed in?) | 1 day | Green/red status per service |
| M3 | Onboarding / welcome view on first launch | 1.5 days | Explain what app does, show prereq status |
| M4 | Keychain access denial handling | 0.5 day | Graceful re-prompt if user denies |
| M5 | Fix popover jumping bug | 1-2 days | Replace NSPopover with NSPanel |
| M6 | Privacy policy text | 0.5 day | "All data stays on your machine" |
| M7 | DMG packaging (drag-to-Applications) | 0.5 day | `create-dmg` or `hdiutil` |

**Total: ~6-7 days**

### Should Have

| # | Task | Effort | Notes |
|---|------|--------|-------|
| S1 | Quota threshold notifications (80%, 100%) | 1 day | UNUserNotificationCenter, once per cycle |
| S2 | Configurable refresh interval UI | 0.5 day | Picker: 1/5/15/30 min |
| S3 | About section (version, check for updates) | 0.5 day | |
| S4 | Keyboard shortcut to toggle popover | 0.5 day | Global hotkey |
| S5 | Robust logging for API debugging | 0.5 day | OSLog, viewable in Console.app |

**Total: ~3 days**

### Could Have (public release)

| # | Task | Effort | Notes |
|---|------|--------|-------|
| C1 | Apple Developer enrollment + code signing | 1.5 days | $99/yr, needed for notarization |
| C2 | Notarization pipeline | 1 day | codesign → notarytool → stapler |
| C3 | Sparkle auto-updater | 2 days | EdDSA keypair, appcast.xml |
| C4 | GitHub Actions release pipeline | 1 day | Tag → build → sign → notarize → release |
| C5 | Landing page | 1-2 days | Static site, screenshots, download |
| C6 | Homebrew Cask formula | 0.5 day | |
| C7 | Usage history chart | 3-4 days | Track over time, sparkline in popover |
| C8 | More integrations (Copilot, ChatGPT, etc.) | 2-4 days each | |

### Won't Have (v1)

- Mac App Store (sandbox incompatible)
- iOS/iPadOS (no local credentials)
- Windows/Linux (different credential stores)
- Cloud backend / accounts / telemetry
- Multi-account support

## Risk Register

| Risk | Impact | Mitigation |
|------|--------|------------|
| Cursor changes internal DB schema | App breaks for Cursor | Version detection + fallback paths, ship patches fast |
| Anthropic revokes Claude Code's OAuth clientId | Claude integration dies | Apply for own OAuth client registration |
| Keychain access blocked by macOS update | Claude integration dies | Code signing + proper entitlements |
| API rate limiting (429) | Degraded UX | Exponential backoff, cache last-known-good values |

## Timeline

| Week | Focus |
|------|-------|
| 1 | M1 (errors) + M5 (popover fix) + S5 (logging) |
| 2 | M2-M4 (onboarding + prereqs) + S1-S2 (notifications + refresh) |
| 3 | M6-M7 (privacy + DMG) + S3-S4 (about + hotkey) + polish |
| 4 | Testing, teammate distribution, feedback → **v1.0 internal release** |
