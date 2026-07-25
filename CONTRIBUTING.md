# Contributing

Thanks for your interest in contributing to mac-limits-tracker! This document
covers how to report issues, propose features, and submit pull requests.

## Reporting bugs

Open a [bug report](https://github.com/Ascurse/mac-limits-tracker/issues/new?template=bug_report.md)
and include:

- macOS version and hardware (Apple Silicon / Intel)
- App version (release tag or commit)
- Which provider is affected (Claude Code / Codex / Kimi) and its CLI version
- Steps to reproduce, expected vs. actual behavior

**Never attach credentials or full auth dumps.** The app reads sensitive local
state — the Claude OAuth token in the macOS Keychain (`Claude Code-credentials`),
`~/.codex/auth.json`, `~/.kimi/` credentials. Redact tokens, emails, and
organization names from logs and screenshots before posting them.

## Proposing features

Open a [feature request](https://github.com/Ascurse/mac-limits-tracker/issues/new?template=feature_request.md).
If the feature is a new limits provider, read
[docs/adding-a-provider.md](docs/adding-a-provider.md) first — it describes the
`LimitsProvider` protocol and everything a new provider needs.

## Development setup

Requirements: macOS 14+, Xcode 15+ / Swift 5.10+ toolchain.

```bash
git clone https://github.com/Ascurse/mac-limits-tracker.git
cd mac-limits-tracker
swift build            # build
swift test             # run the pure-logic unit tests
swift run MacLimitsTracker   # run the app without bundling
```

For a distributable `.app`: `./make-app.sh` → `dist/MacLimitsTracker.app`.

For ad-hoc provider debugging (real Keychain + network) run `VerifyCli` in
**release** — a short-lived debug executable trips a spurious `nano-malloc`
abort on exit:

```bash
swift run -c release VerifyCli
```

## Pull requests

1. Fork the repo and branch from `main` (`feat/...`, `fix/...`).
2. Keep the change focused — one concern per PR, no drive-by reformatting.
3. Add or update unit tests in `Tests/MacLimitsTrackerTests` for parser /
   model / ViewModel logic. Tests must stay pure-logic: no network, no
   Keychain, no real `~/.claude` / `~/.codex` access — use dependency
   injection like the existing providers do.
4. Make sure `swift build` and `swift test` pass locally.
5. If you changed behavior visible to users (UI, popup, themes, widget),
   describe it in the PR and attach a screenshot where relevant.
6. Follow the existing code style: Swift API Design Guidelines, meaningful
   names, no magic strings — look at neighboring files first.

## Repository conventions worth knowing

- **Issue tracking** uses [bd (beads)](https://github.com/gastownhall/beads) —
  run `bd prime` in the repo for the workflow. GitHub Issues are used for
  external reports; internal work items live in beads.
- **Project memory** lives in `docs/journal/` (`decisions.md`, `gotchas.md`,
  `glossary.md`). Before changing a file, grep the journal for its name —
  known traps are indexed there. Non-trivial findings from your change are
  welcome as short journal entries.
- User-facing documentation (README, this file) is in English; journal entries
  are in Russian.

## Code of Conduct

Participation in this project is governed by the
[Code of Conduct](CODE_OF_CONDUCT.md).

## License

By contributing, you agree that your contributions will be licensed under the
[MIT License](LICENSE).
