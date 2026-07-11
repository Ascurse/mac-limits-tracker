# mac-limits-tracker

A macOS menu-bar app that shows the current Claude Code and Codex CLI plan / usage state at a glance.

![platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)
![swift](https://img.shields.io/badge/swift-5.10%2B-orange)
![license](https://img.shields.io/badge/license-MIT-green)

## What it shows

Clicking the gauge icon in your menu bar opens a popup with two sections:

**Claude Code**
- Subscription type (`max`, `pro`, …) and account email — parsed live from `claude auth status --json`.
- Today's message count and token usage from `~/.claude/stats-cache.json`. If today's entry is missing (the stats cache is only refreshed intermittently), it falls back to the latest recorded day with a clear date label.
- Cumulative totals (sessions, messages) and the `lastComputedDate` of the cache.

**Codex (OpenAI Codex CLI)**
- ChatGPT plan type, account email, organization title — decoded from the `id_token` JWT stored in `~/.codex/auth.json`.
- `subscription_active_until` and remaining days until the renewal date in the JWT.

The status-bar tooltip shows `Claude: <plan> · Codex: <plan>` so you get the headline state without opening the popup.

## Data sources

| Source            | What it reads                                                   | How                                       |
|-------------------|-----------------------------------------------------------------|-------------------------------------------|
| Claude Code auth  | subscription type, email, orgName, logged-in state              | `claude auth status` (JSON via stdout)    |
| Claude Code stats | `dailyActivity`, `dailyModelTokens`, `lastComputedDate`, totals | `~/.claude/stats-cache.json`              |
| Codex auth        | `auth_mode`, `id_token` (JWT claims: plan, email, subs-until)   | `~/.codex/auth.json` — JWT body only      |

The app never prints or transmits raw tokens. Only the base64-decoded JWT **claims** are inspected to surface plan type, email, and renewal date; `access_token` is not read unless `id_token` is missing.

## Build & run

### Requirements
- macOS 14 (Sonoma) or newer
- Xcode 15+ / Swift 5.10+ toolchain
- `claude` CLI installed and logged in (Claude Code subscription)
- `codex` CLI installed and logged in (ChatGPT auth)

### Dev (no `.app` bundle)
```bash
swift run MacLimitsTracker
```
This drops you into a SwiftUI `MenuBarExtra` immediately. The Dock icon is hidden automatically (`LSUIElement=true` / accessory activation policy).

### Production `.app`
```bash
./make-app.sh
open -a dist/MacLimitsTracker.app
```
`make-app.sh` runs `swift build -c release` and assembles `dist/MacLimitsTracker.app` with an `Info.plist` (`LSUIElement=true`, bundle id `dev.ascurse.MacLimitsTracker`).

### Run on boot
Add `dist/MacLimitsTracker.app` to **System Settings → General → Login Items → Open at login**.

## Project layout

```
Sources/
  MacLimitsTrackerCore/         # Library: models, JWT decode, providers, ViewModel
    Models/ClaudeModels.swift
    Models/CodexModels.swift
    Providers/LimitsProviders.swift
    LimitsViewModel.swift
  MacLimitsTracker/             # Executable: SwiftUI app shell
    App/MacLimitsTrackerApp.swift
    App/AppDelegate.swift
    UI/StatusBarView.swift
  VerifyCli/                    # CLI for ad-hoc provider debugging
Tests/MacLimitsTrackerTests/    # Pure-logic unit tests (JWT, stats-cache, claims)
make-app.sh                     # One-shot release build + bundle assembler
Package.swift
```

## Auto-refresh

The ViewModel refreshes both providers every 5 minutes by default; the popup also has a manual refresh button and an auto-refresh toggle.

## Limitations

- **Claude Code "limits" are usage estimates, not live rate-limit windows.** The Claude subscription rate-limit windows (`/usage` window / 5h reset) are server-side and not exposed via the CLI or local files. The popup shows your subscription type + your cache's per-day activity as an approximation. To display true live quota, an upstream change to expose those headers/claims or authenticated Claude.ai dashboard calls would be needed.
- **Codex renewal date comes from the JWT `chatgpt_subscription_active_until` claim.** This claim is set when the token is minted; after renewal the old claim is stale (the timer floors at 0 days). The actual active subscription status is enforced server-side by ChatGPT.
- The app reads `~/.claude/` and `~/.codex/` directly, so do **not** share logs/screenshots of `auth.json` contents with anyone.

## Tests

Pure-logic tests for the parsers (no network, no filesystem):
```bash
swift test
```

## License

MIT — see [LICENSE](LICENSE).