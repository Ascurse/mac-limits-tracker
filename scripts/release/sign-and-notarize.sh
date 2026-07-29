#!/usr/bin/env bash
set -euo pipefail
set +x

# Fail-closed pipeline для подписи Developer ID, notarization, staple и
# Gatekeeper-оценки. Всегда падает при отсутствии prerequisites.
# Hardened runtime — это флаг --options runtime, поэтому entitlements-файл
# не создаётся; sandbox запрещён по дизайну приложения.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly ROOT

# Значения по умолчанию.
APP="${ROOT}/dist/MacLimitsTracker.app"
DRY_RUN=false
PREFLIGHT_ONLY=false
SKIP_NOTARIZE=false
IDENTITY_OVERRIDE=""
OUT_DIR="${ROOT}/dist"
OUT_DIR_PROVIDED=false
PRINT_AUTH_METHOD=false

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

die() {
    printf 'FAIL-CLOSED: %s\n' "$1" >&2
    exit 1
}

usage() {
    cat >&2 <<EOF
Usage: ${0##*/} [options]
  --app PATH              path to .app bundle (default: dist/MacLimitsTracker.app)
  --out DIR               release zip output directory (default: dist/)
  --dry-run               run all checks and print planned commands, no mutations
  --preflight-only        run preflight checks and exit
  --skip-notarize         sign and verify only, no network/Apple calls
  --identity-override NAME  use a non-Developer-ID identity for local signing
  --print-auth-method     print resolved notary auth method and exit
EOF
}

# ---------------------------------------------------------------------------
# Arg parsing
# ---------------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
    case "$1" in
        --app)
            APP="$2"
            shift 2
            ;;
        --out)
            OUT_DIR="$2"
            OUT_DIR_PROVIDED=true
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --preflight-only)
            PREFLIGHT_ONLY=true
            shift
            ;;
        --skip-notarize)
            SKIP_NOTARIZE=true
            shift
            ;;
        --identity-override)
            IDENTITY_OVERRIDE="$2"
            shift 2
            ;;
        --print-auth-method)
            PRINT_AUTH_METHOD=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "unknown argument: $1"
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Scratch directory (для override-копии, временных P8 и логов notarytool).
# ---------------------------------------------------------------------------

INTERNAL_SCRATCH="$(mktemp -d)"
trap 'rm -rf "$INTERNAL_SCRATCH"' EXIT

# ---------------------------------------------------------------------------
# Auth resolver
# ---------------------------------------------------------------------------

resolve_auth_method() {
    local profile=false api_key=false apple_id=false
    local api_key_partial=false apple_id_partial=false
    local missing=()

    if [[ -n "${NOTARY_PROFILE:-}" ]]; then
        profile=true
    fi

    if [[ -n "${NOTARY_KEY:-}" || -n "${NOTARY_KEY_ID:-}" || -n "${NOTARY_ISSUER:-}" ]]; then
        if [[ -n "${NOTARY_KEY:-}" && -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER:-}" ]]; then
            api_key=true
        else
            api_key_partial=true
            [[ -n "${NOTARY_KEY:-}" ]] || missing+=(NOTARY_KEY)
            [[ -n "${NOTARY_KEY_ID:-}" ]] || missing+=(NOTARY_KEY_ID)
            [[ -n "${NOTARY_ISSUER:-}" ]] || missing+=(NOTARY_ISSUER)
        fi
    fi

    if [[ -n "${APPLE_ID:-}" || -n "${APPLE_APP_PASSWORD:-}" || -n "${APPLE_TEAM_ID:-}" ]]; then
        if [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]]; then
            apple_id=true
        else
            apple_id_partial=true
            [[ -n "${APPLE_ID:-}" ]] || missing+=(APPLE_ID)
            [[ -n "${APPLE_APP_PASSWORD:-}" ]] || missing+=(APPLE_APP_PASSWORD)
            [[ -n "${APPLE_TEAM_ID:-}" ]] || missing+=(APPLE_TEAM_ID)
        fi
    fi

    if $api_key_partial; then
        die "notary auth incomplete (API key): ${missing[*]}"
    fi
    if $apple_id_partial; then
        die "notary auth incomplete (Apple ID): ${missing[*]}"
    fi

    local count=0
    $profile && count=$((count + 1))
    $api_key && count=$((count + 1))
    $apple_id && count=$((count + 1))

    if [[ $count -gt 1 ]]; then
        die "conflicting notary auth methods"
    fi

    if $profile; then
        echo "profile"
    elif $api_key; then
        echo "api-key"
    elif $apple_id; then
        echo "apple-id"
    else
        echo "none-conflict"
    fi
}

print_auth_method() {
    local method
    method="$(resolve_auth_method)"
    printf '%s\n' "$method"
}

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------

preflight_tools() {
    local tool
    for tool in codesign xcrun ditto security plutil; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            die "required tool missing from PATH: $tool"
        fi
    done

    if [[ ! -x "/usr/libexec/PlistBuddy" ]]; then
        die "required tool missing: /usr/libexec/PlistBuddy"
    fi

    if ! xcrun notarytool --version >/dev/null 2>&1; then
        die "xcrun notarytool not functional"
    fi
}

preflight_app() {
    if [[ ! -d "$APP" ]]; then
        die "app bundle not found: $APP"
    fi

    local plist
    plist="$APP/Contents/Info.plist"
    if [[ ! -f "$plist" ]]; then
        die "Info.plist missing: $plist"
    fi

    if ! plutil -lint "$plist" >/dev/null 2>&1; then
        die "Info.plist is invalid: $plist"
    fi

    local bundle_id bundle_version
    bundle_id="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$plist" 2>/dev/null || true)"
    bundle_version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$plist" 2>/dev/null || true)"

    if [[ -z "$bundle_id" ]]; then
        die "CFBundleIdentifier unreadable in $plist"
    fi
    if [[ -z "$bundle_version" ]]; then
        die "CFBundleShortVersionString unreadable in $plist"
    fi

    readonly BUNDLE_ID="$bundle_id"
    readonly BUNDLE_VERSION="$bundle_version"
}

preflight_identity() {
    if [[ -n "$IDENTITY_OVERRIDE" ]]; then
        if [[ -n "${CI:-}" ]]; then
            die "identity-override is not allowed in CI"
        fi
        IDENTITY="$IDENTITY_OVERRIDE"
        SKIP_NOTARIZE=true
        return
    fi

    if [[ -z "${DEVELOPER_ID_APPLICATION:-}" ]]; then
        die "DEVELOPER_ID_APPLICATION is not set"
    fi

    if [[ "${DEVELOPER_ID_APPLICATION}" != "Developer ID Application:"* ]]; then
        die "DEVELOPER_ID_APPLICATION must start with 'Developer ID Application:'"
    fi

    if ! security find-identity -v -p codesigning 2>/dev/null | grep -qF "$DEVELOPER_ID_APPLICATION"; then
        die "DEVELOPER_ID_APPLICATION not found in keychain"
    fi

    IDENTITY="$DEVELOPER_ID_APPLICATION"
}

preflight_auth() {
    if $SKIP_NOTARIZE; then
        return
    fi

    local method
    method="$(resolve_auth_method)"
    if [[ "$method" == "none-conflict" ]]; then
        die "notary auth method missing"
    fi
}

preflight() {
    preflight_tools
    preflight_app
    preflight_identity
    preflight_auth
}

# ---------------------------------------------------------------------------
# Dry-run plan
# ---------------------------------------------------------------------------

dry_run_plan() {
    local auth_method="none"
    if ! $SKIP_NOTARIZE; then
        auth_method="$(resolve_auth_method)"
    fi

    printf 'DRY-RUN: codesign --force --options runtime --timestamp --sign <identity> "%s"\n' "$WORK_APP"
    printf 'DRY-RUN: verify --deep --strict "%s"\n' "$WORK_APP"

    if $SKIP_NOTARIZE; then
        return
    fi

    printf 'DRY-RUN: notary-zip -> "%s/MacLimitsTracker-notary.zip"\n' "$INTERNAL_SCRATCH"

    case "$auth_method" in
        profile)
            printf 'DRY-RUN: submit notarytool --keychain-profile *** --wait --timeout 20m\n'
            ;;
        api-key)
            printf 'DRY-RUN: submit notarytool --key *** --key-id *** --issuer *** --wait --timeout 20m\n'
            ;;
        apple-id)
            printf 'DRY-RUN: submit notarytool --apple-id *** --password *** --team-id *** --wait --timeout 20m\n'
            ;;
        *)
            die "dry-run auth method unknown: $auth_method"
            ;;
    esac

    printf 'DRY-RUN: staple "%s"\n' "$WORK_APP"
    printf 'DRY-RUN: validate "%s"\n' "$WORK_APP"
    printf 'DRY-RUN: assess --type execute -vv "%s"\n' "$WORK_APP"
    printf 'DRY-RUN: release-zip -> "%s/MacLimitsTracker.zip"\n' "$OUT_DIR"
}

# ---------------------------------------------------------------------------
# Sign and verify
# ---------------------------------------------------------------------------

sign_app() {
    # Подписываем корень бандла. Нет --deep, потому что в бандле нет
    # вложенного кода/хелперов/фреймворков. Нет entitlements-файла:
    # hardened runtime задаётся флагом --options runtime, а sandbox
    # противоречит дизайну приложения (читает ~/.claude, ~/.codex, ~/.kimi-code
    # и запускает subprocesses). Стабильная Developer ID-подпись избавляет от
    # keychain ACL-промптов на каждую сборку для Claude Code-credentials.
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$WORK_APP"
}

verify_app() {
    codesign --verify --deep --strict --verbose=2 "$WORK_APP"

    local info
    info="$(codesign -dvvv "$WORK_APP" 2>&1 || true)"

    if ! grep -q 'flags=0x10000(runtime)' <<<"$info"; then
        die "runtime hardened flag missing"
    fi
    if ! grep -q 'TeamIdentifier=' <<<"$info"; then
        die "TeamIdentifier missing"
    fi

    # Для production-identity проверяем, что авторитет — Developer ID.
    # Под identity-override (локальная разработка) эта проверка пропускается.
    if [[ -z "$IDENTITY_OVERRIDE" ]]; then
        if ! grep -q 'Authority=Developer ID Application:' <<<"$info"; then
            die "signature authority is not Developer ID Application"
        fi
    fi
}

# ---------------------------------------------------------------------------
# Notarize, staple, assess, release zip
# ---------------------------------------------------------------------------

notary_auth_args() {
    local args=()
    if [[ -n "${NOTARY_PROFILE:-}" ]]; then
        args+=(--keychain-profile "$NOTARY_PROFILE")
    elif [[ -n "${NOTARY_KEY:-}" ]]; then
        local p8_path
        p8_path="$INTERNAL_SCRATCH/notary-key.p8"
        printf '%s' "$NOTARY_KEY" > "$p8_path"
        chmod 600 "$p8_path"
        # Файл удалится вместе со scratch-директорией по EXIT-trap.
        args+=(--key "$p8_path" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER")
    elif [[ -n "${APPLE_ID:-}" ]]; then
        # set +x уже глобально; Apple ID-пароль не печатается нигде.
        args+=(--apple-id "$APPLE_ID" --password "$APPLE_APP_PASSWORD" --team-id "$APPLE_TEAM_ID")
    fi
    printf '%s\n' "${args[@]}"
}

notarize_app() {
    local zip submission_id status
    zip="$INTERNAL_SCRATCH/MacLimitsTracker-notary.zip"

    ditto -c -k --sequesterRsrc --keepParent "$WORK_APP" "$zip"

    local auth_args
    mapfile -t auth_args < <(notary_auth_args)

    local output
    # || true: иначе под set -e сетевой/авторизационный сбой notarytool убьёт
    # скрипт молча — вывод уже захвачен и FAIL-CLOSED причина потеряется.
    output="$(xcrun notarytool submit "$zip" --wait --timeout 20m --output-format json "${auth_args[@]}" 2>&1 || true)"

    if ! submission_id="$(printf '%s' "$output" | python3 -c 'import sys, json; print(json.load(sys.stdin).get("id",""))' 2>/dev/null)" || [[ -z "$submission_id" ]]; then
        die "could not parse notarytool submission response"
    fi
    if ! status="$(printf '%s' "$output" | python3 -c 'import sys, json; print(json.load(sys.stdin).get("status",""))' 2>/dev/null)" || [[ -z "$status" ]]; then
        die "could not parse notarytool status"
    fi

    if [[ "$status" != "Accepted" ]]; then
        local log_path
        log_path="$INTERNAL_SCRATCH/notary-log.json"
        xcrun notarytool log "$submission_id" --output-format json "${auth_args[@]}" > "$log_path" 2>&1 || true
        die "notarization failed: status=$status; log saved to $log_path"
    fi
}

staple_app() {
    xcrun stapler staple "$WORK_APP"
    xcrun stapler validate "$WORK_APP"
}

assess_app() {
    spctl --assess --type execute -vv "$WORK_APP"
}

release_zip() {
    # Release-артефакт должен быть создан уже после staple; notary-zip
    # никогда не публикуется как release artifact.
    ditto -c -k --sequesterRsrc --keepParent "$WORK_APP" "$OUT_DIR/MacLimitsTracker.zip"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    if $PRINT_AUTH_METHOD; then
        print_auth_method
        exit 0
    fi

    preflight

    # Для identity-override работаем на копии в scratch, чтобы никогда не
    # модифицировать dist/ и не оставлять неподписанный/непроверенный артефакт.
    if [[ -n "$IDENTITY_OVERRIDE" ]]; then
        if ! $OUT_DIR_PROVIDED || [[ "$OUT_DIR" == "${ROOT}/dist" ]]; then
            OUT_DIR="$(mktemp -d)"
            printf 'OVERRIDE_OUT_DIR=%s\n' "$OUT_DIR"
        fi
        WORK_APP="$OUT_DIR/app"
    else
        WORK_APP="$APP"
    fi
    mkdir -p "$OUT_DIR"
    if [[ -n "$IDENTITY_OVERRIDE" ]]; then
        cp -a "$APP" "$WORK_APP"
    fi

    if $DRY_RUN; then
        dry_run_plan
        exit 0
    fi

    if $PREFLIGHT_ONLY; then
        exit 0
    fi

    sign_app
    verify_app

    if $SKIP_NOTARIZE; then
        printf 'ARTIFACT_APP=%s\n' "$WORK_APP"
        exit 0
    fi

    notarize_app
    staple_app
    assess_app
    release_zip

    printf 'ARTIFACT_APP=%s\n' "$WORK_APP"
    printf 'RELEASE_ZIP=%s\n' "$OUT_DIR/MacLimitsTracker.zip"
}

main
