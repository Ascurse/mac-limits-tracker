# Release signing pipeline

This document describes how to sign, notarize, and package `MacLimitsTracker.app` for release. The pipeline is intentionally fail-closed: if any prerequisite is missing, the script exits with `FAIL-CLOSED:` on stderr and produces no release artifact.

## What the pipeline does

`scripts/release/sign-and-notarize.sh` runs the following steps in order:

1. **Preflight**: checks tools, the `.app` bundle, the signing identity, and notary credentials.
2. **Sign**: codesigns the bundle with the Developer ID Application identity, hardened runtime, and a secure timestamp.
3. **Verify**: runs `codesign --verify --deep --strict` and confirms the runtime hardened flag and TeamIdentifier.
4. **Notarize**: submits a zip of the signed bundle to Apple via `notarytool` and waits for acceptance.
5. **Staple**: attaches the notarization ticket to the bundle with `stapler` and validates it.
6. **Gatekeeper assess**: runs `spctl --assess --type execute -vv` on the stapled bundle.
7. **Release zip**: creates `MacLimitsTracker.zip` from the stapled bundle.

On success the script prints:

```text
ARTIFACT_APP=<path to the signed/stapled .app>
RELEASE_ZIP=<path to MacLimitsTracker.zip>
```

The fail-closed principle means an unsigned or unverified bundle is never zipped or published. If a check fails, the script exits with code `1` and a `FAIL-CLOSED:` reason.

## Prerequisites

Before you run the pipeline, you need:

* An Apple Developer Program membership.
* A `Developer ID Application` certificate installed in your keychain. The identity name must start with `Developer ID Application:`.
* Xcode Command Line Tools, including `codesign`, `xcrun notarytool`, and `xcrun stapler`.
* A built and assembled `.app` bundle, produced by:

```bash
./make-app.sh
```

The default app path is `dist/MacLimitsTracker.app`.

## Local dry-run and preflight checks

Use `--dry-run` to run all preflight checks and print the commands the pipeline would execute, without changing any files or making network calls:

```bash
./scripts/release/sign-and-notarize.sh --dry-run
```

A successful dry-run prints lines like these and exits `0`:

```text
DRY-RUN: codesign --force --options runtime --timestamp --sign <identity> "<app>"
DRY-RUN: verify --deep --strict "<app>"
DRY-RUN: notary-zip -> "<scratch>/MacLimitsTracker-notary.zip"
DRY-RUN: submit notarytool --keychain-profile *** --wait --timeout 20m
DRY-RUN: staple "<app>"
DRY-RUN: validate "<app>"
DRY-RUN: assess --type execute -vv "<app>"
DRY-RUN: release-zip -> "<out>/MacLimitsTracker.zip"
```

Use `--preflight-only` to run only the checks and exit:

```bash
./scripts/release/sign-and-notarize.sh --preflight-only
```

Both flags mutate nothing. If anything is missing, the script prints `FAIL-CLOSED: <reason>` on stderr and exits `1`.

## Local signing mechanics test (no Developer ID needed)

If you do not have a `Developer ID Application` certificate locally, you can still test the sign and verify mechanics with an override identity. The local machine currently has an `Apple Distribution:` identity for team `56764BSR9B`, so the following command will sign and verify the bundle without notarization:

```bash
./scripts/release/sign-and-notarize.sh \
  --identity-override "Apple Distribution: Zigmund AM, LLC (56764BSR9B)" \
  --skip-notarize
```

> **Warning:** `--identity-override` is for local mechanics testing only.
> The output is written to a scratch directory, never to `dist/`, and the resulting bundle is **not** a release artifact. The script refuses this flag in CI. The identity override also forces `--skip-notarize` automatically.

On success the script prints `ARTIFACT_APP=<path>` and exits `0`. It does not produce a `RELEASE_ZIP` because notarization is skipped.

## Real local notarization

To run a full local release you must provide exactly one notary authentication method. You can verify which method the script resolves with:

```bash
./scripts/release/sign-and-notarize.sh --print-auth-method
```

### Method 1: Keychain profile (recommended for local use)

Store credentials in your keychain once, then reference them by profile name:

```bash
xcrun notarytool store-credentials "MacLimitsTracker-notary" \
  --apple-id your-apple-id@example.com \
  --team-id 56764BSR9B \
  --password your-app-specific-password
```

Then set the profile name and run the pipeline:

```bash
export DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)"
export NOTARY_PROFILE="MacLimitsTracker-notary"
./scripts/release/sign-and-notarize.sh
```

### Method 2: API key (P8 file)

Generate a JWT key in App Store Connect, base64-encode it, and export it with the key ID and issuer ID:

```bash
export DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)"
export NOTARY_KEY="$(cat AuthKey_1234567890.p8)"
export NOTARY_KEY_ID="1234567890"
export NOTARY_ISSUER="00000000-0000-0000-0000-000000000000"
./scripts/release/sign-and-notarize.sh
```

The script writes the key to a temporary scratch file with `600` permissions and removes it on exit.

### Method 3: Apple ID app-specific password

Use an app-specific password directly. The password is passed only to `notarytool` and is never printed:

```bash
export DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)"
export APPLE_ID="your-apple-id@example.com"
export APPLE_APP_PASSWORD="abcd-efgh-ijkl-mnop"
export APPLE_TEAM_ID="56764BSR9B"
./scripts/release/sign-and-notarize.sh
```

Do not mix these methods. If more than one method is configured, the script fails with `FAIL-CLOSED: conflicting notary auth methods`.

## CI setup

The release workflow (`.github/workflows/release.yml`) triggers on a `v*` tag, for example `v0.2.0`. It expects these repository secrets:

| Secret | Purpose | How to set |
|---|---|---|
| `MACOS_CERT_P12_BASE64` | Base64-encoded `Developer ID Application` P12 certificate | `base64 -i cert.p12 \| pbcopy` then paste into the secret |
| `MACOS_CERT_PASSWORD` | Password for the P12 certificate | enter when exporting the certificate |
| `DEVELOPER_ID_APPLICATION` | Full identity name, e.g. `Developer ID Application: Your Name (TEAMID)` | match the certificate name exactly |
| Notary method secrets, exactly one of: |  |  |
| `NOTARY_KEY` + `NOTARY_KEY_ID` + `NOTARY_ISSUER` | App Store Connect API key P8 content, key ID, and issuer ID | paste the P8 text and the two IDs |
| `APPLE_ID` + `APPLE_APP_PASSWORD` + `APPLE_TEAM_ID` | Apple ID, app-specific password, and team ID | use a dedicated CI Apple ID |

`NOTARY_PROFILE` is not a CI secret; it is for local runs only (see Method 1 above). In CI, use the API key or the Apple ID method.

On a tag push the workflow runs: secrets preflight (fails before any build or release mutation if anything is missing) → `swift test` → universal build → `make-app.sh` → temporary keychain creation + P12 import → `scripts/release/sign-and-notarize.sh` → only on success, publish `dist/MacLimitsTracker.zip` to the GitHub release. The temporary keychain is deleted in an `if: always()` cleanup step. If any step fails, the CI job stops and no release is published or mutated.

## Fail-closed behavior summary

| Failure | Where it surfaces |
|---|---|
| Missing `codesign`, `xcrun`, `notarytool`, `stapler`, `ditto`, `security`, or `plutil` | `FAIL-CLOSED: required tool missing from PATH` on stderr |
| `.app` bundle missing or `Info.plist` invalid | `FAIL-CLOSED: app bundle not found` or `FAIL-CLOSED: Info.plist is invalid` on stderr |
| `DEVELOPER_ID_APPLICATION` unset, wrong prefix, or not in keychain | `FAIL-CLOSED:` reason on stderr |
| `--identity-override` used in CI | `FAIL-CLOSED: identity-override is not allowed in CI` on stderr |
| No notary auth method, partial credentials, or multiple methods | `FAIL-CLOSED:` reason on stderr |
| Notarization rejected by Apple | `FAIL-CLOSED: notarization failed: status=<status>` on stderr, with a log saved to the scratch directory |
| Signature verification or Gatekeeper assessment fails | `FAIL-CLOSED:` reason on stderr |
| Any CI step fails | GitHub Actions job fails before the release is created or updated |

In every case, the script exits `1` and leaves no `RELEASE_ZIP` output.

## Manual clean-machine QA checklist

After a real signed release is published, verify it on a Mac that has not seen the build before:

1. Download `MacLimitsTracker.zip` from the release page.
2. Unzip it and inspect the app:

```bash
spctl --assess --type execute -vv MacLimitsTracker.app
xcrun stapler validate MacLimitsTracker.app
```

3. Double-click the app. It should open without a Gatekeeper warning.
4. On first launch, macOS may show one keychain access prompt. Click **Always Allow**. Subsequent launches of the same build should not show the prompt again.

If any of these checks fail, the release is not ready for users.

## Release script tests

Automated tests for the signing pipeline live in `scripts/release/tests/run-tests.sh`. They exercise the argument parser, preflight checks, dry-run behavior, identity override mechanics, and notary auth resolution without contacting Apple:

```bash
./scripts/release/tests/run-tests.sh
```

A clean run reports `pass: 61, fail: 0` and exits `0`.
