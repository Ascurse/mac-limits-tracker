# Security Policy

## Supported Versions

Only the [latest release](https://github.com/Ascurse/mac-limits-tracker/releases/latest)
receives security fixes. The app is free and has no LTS branches — if you are
on an old tag, please update first and check whether the issue still exists.

| Version          | Supported |
| ---------------- | --------- |
| Latest release   | ✅        |
| Older releases   | ❌        |

## Sensitive data this app handles

mac-limits-tracker reads local credentials to display usage state:

- the Claude Code OAuth token from the macOS Keychain
  (`Claude Code-credentials`), sent only to `claude.ai` as a `Bearer` header
- JWT claims from `~/.codex/auth.json` (only the `id_token` body is decoded)
- Kimi credentials under `~/.kimi/`

The app never logs, persists, or transmits these tokens anywhere else, and it
makes no third-party network calls beyond the provider APIs. When reporting
issues, **never include tokens, `auth.json` contents, or unredacted screenshots
of credential files**.

## Reporting a Vulnerability

**Do not open a public issue for security vulnerabilities.**

Please report them privately via
[GitHub Security Advisories](https://github.com/Ascurse/mac-limits-tracker/security/advisories/new)
("Report a vulnerability"). Include:

- a description of the issue and its impact,
- steps to reproduce or a proof of concept,
- the affected version/commit.

You can expect an acknowledgment within a few days. If the report is accepted,
a fix will be prepared and released before the advisory is published; you will
be credited unless you prefer to stay anonymous. If it is declined, you will
receive an explanation.

## Scope notes

Issues that require an attacker to already have read access to the local
user's Keychain or home directory are generally out of scope — at that point
macOS itself provides no isolation between the user's processes. In scope are
things like: leaking tokens to logs/network, writing credential files with
insecure permissions, or trusting attacker-controlled data from config files
without validation.
