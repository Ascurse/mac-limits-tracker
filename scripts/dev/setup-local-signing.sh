#!/usr/bin/env bash
set -euo pipefail

IDENTITY_NAME="${MAC_LIMITS_TRACKER_SIGNING_IDENTITY:-}"

for required_command in security; do
    if ! command -v "$required_command" >/dev/null 2>&1; then
        echo "Required command not found: $required_command" >&2
        exit 1
    fi
done

if [[ "$IDENTITY_NAME" == *$'\n'* || "$IDENTITY_NAME" == *$'\r'* ]]; then
    echo "Signing identity must not contain newlines" >&2
    exit 1
fi

IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
if [[ -z "$IDENTITY_NAME" ]]; then
    AVAILABLE_IDENTITIES="$(printf '%s\n' "$IDENTITIES" \
        | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' \
        | sed -n '1,20p')"
    echo "Set MAC_LIMITS_TRACKER_SIGNING_IDENTITY to your personal Apple Development identity" >&2
    if [[ -n "$AVAILABLE_IDENTITIES" ]]; then
        printf '%s\n' "$AVAILABLE_IDENTITIES" >&2
    else
        echo "No Apple Development signing identity found" >&2
        echo "Sign in to Xcode with your personal Apple Account and create an Apple Development certificate" >&2
    fi
    exit 1
fi

if [[ "$IDENTITY_NAME" != Apple\ Development:* ]]; then
    echo "Only Apple Development identities are allowed for local signing" >&2
    exit 1
fi

if ! printf '%s\n' "$IDENTITIES" | grep -qF "\"$IDENTITY_NAME\""; then
    echo "Signing identity not found: $IDENTITY_NAME" >&2
    exit 1
fi

echo "Using local signing identity: $IDENTITY_NAME"
echo "Use: MAC_LIMITS_TRACKER_SIGNING_IDENTITY='$IDENTITY_NAME' ./make-app.sh"
