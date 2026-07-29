#!/usr/bin/env bash
set -uo pipefail
# Harness без set -e: ошибки assert не прерывают выполнение.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPT_DIR="$ROOT/scripts/release"
TEST_DIR="$ROOT/scripts/release/tests"
SIGN_SCRIPT="$SCRIPT_DIR/sign-and-notarize.sh"
MAKE_FAKE_APP="$TEST_DIR/make-fake-app.sh"

PASS=0
FAIL=0
TEST_NO=1

SCRATCH="$(mktemp -d)"
cleanup() {
    rm -rf "$SCRATCH"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Helpers: запуск команд и захват stdout/stderr
# ---------------------------------------------------------------------------

run_cmd() {
    printf '%s\n' "$*" > "$SCRATCH/last-cmd.txt"
    if "$@" > "$SCRATCH/stdout" 2> "$SCRATCH/stderr"; then
        EXIT_STATUS=0
    else
        EXIT_STATUS=$?
    fi
    cat "$SCRATCH/stdout" "$SCRATCH/stderr" > "$SCRATCH/combined" 2>/dev/null || true
}

ok() {
    local name="$1"
    printf 'ok %d - %s\n' "$TEST_NO" "$name"
    PASS=$((PASS + 1))
    TEST_NO=$((TEST_NO + 1))
}

not_ok() {
    local name="$1"
    local detail="${2:-}"
    printf 'not ok %d - %s' "$TEST_NO" "$name"
    if [[ -n "$detail" ]]; then
        printf ' (%s)' "$detail"
    fi
    printf '\n'
    FAIL=$((FAIL + 1))
    TEST_NO=$((TEST_NO + 1))
}

assert_exit_zero() {
    local name="$1"
    if [[ "$EXIT_STATUS" -eq 0 ]]; then
        ok "$name"
    else
        not_ok "$name" "expected exit 0, got $EXIT_STATUS"
    fi
}

assert_exit_nonzero() {
    local name="$1"
    if [[ "$EXIT_STATUS" -ne 0 ]]; then
        ok "$name"
    else
        not_ok "$name" "expected nonzero exit"
    fi
}

assert_stdout_contains() {
    local name="$1"
    local needle="$2"
    if grep -qF "$needle" "$SCRATCH/stdout"; then
        ok "$name"
    else
        not_ok "$name" "stdout missing '$needle'"
    fi
}

assert_stderr_contains() {
    local name="$1"
    local needle="$2"
    if grep -qF "$needle" "$SCRATCH/stderr"; then
        ok "$name"
    else
        not_ok "$name" "stderr missing '$needle'"
    fi
}

assert_equal() {
    local name="$1"
    local expected="$2"
    local actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        ok "$name"
    else
        not_ok "$name" "expected '$expected', got '$actual'"
    fi
}

assert_file_absent() {
    local name="$1"
    local path="$2"
    if [[ ! -e "$path" ]]; then
        ok "$name"
    else
        not_ok "$name" "unexpected file exists: $path"
    fi
}

assert_file_contains() {
    local name="$1"
    local path="$2"
    local needle="$3"
    if grep -qF "$needle" "$path" 2>/dev/null; then
        ok "$name"
    else
        not_ok "$name" "file $path missing '$needle'"
    fi
}

assert_no_secret_leak() {
    local name="$1"
    local sentinel="$2"
    if grep -qF "$sentinel" "$SCRATCH/combined"; then
        not_ok "$name" "sentinel '$sentinel' leaked"
    else
        ok "$name"
    fi
}

build_fake_app() {
    FAKE_APP="$SCRATCH/fake-app"
    rm -rf "$FAKE_APP"
    mkdir -p "$FAKE_APP"
    "$MAKE_FAKE_APP" "$FAKE_APP"
    FAKE_APP="$FAKE_APP/Fake.app"
}

# ---------------------------------------------------------------------------
# Fake security для тестирования dry-run notarization без настоящего DevID.
# ---------------------------------------------------------------------------

make_fake_security() {
    local fake_bin="$SCRATCH/fake-bin"
    mkdir -p "$fake_bin"
    cat > "$fake_bin/security" <<'EOF'
#!/usr/bin/env bash
# Подменяет только find-identity -p codesigning, остальное делегирует /usr/bin/security.
for arg in "$@"; do
    if [[ "$arg" == "codesigning" ]]; then
        echo '  1) DEADBEEF "Developer ID Application: Local Test (TEST1234567)"'
        echo '     1 valid identities found'
        exit 0
    fi
done
exec /usr/bin/security "$@"
EOF
    chmod +x "$fake_bin/security"
    echo "$fake_bin"
}

run_with_fake_security() {
    local fake_bin="$(make_fake_security)"
    PATH="$fake_bin:$PATH" "$@"
}

# ---------------------------------------------------------------------------
# T1: harness self-test + fixture
# ---------------------------------------------------------------------------

run_cmd true
assert_exit_zero "harness self-test: true exits 0"

build_fake_app
run_cmd plutil -lint "$FAKE_APP/Contents/Info.plist"
assert_exit_zero "fixture: Info.plist passes plutil -lint"

run_cmd file "$FAKE_APP/Contents/MacOS/Fake"
assert_stdout_contains "fixture: executable is Mach-O" ": Mach-O"

# ---------------------------------------------------------------------------
# T2: preflight + dry-run (red-first TDD)
# ---------------------------------------------------------------------------

run_cmd bash -n "$SIGN_SCRIPT"
assert_exit_zero "T2: sign-and-notarize.sh parses cleanly"

build_fake_app

NOTARY_PROFILE="test-profile" \
    run_cmd "$SIGN_SCRIPT" --preflight-only --app "$FAKE_APP"
assert_exit_nonzero "T2: preflight fails when DEVELOPER_ID_APPLICATION is unset"
assert_stderr_contains "T2: preflight failure message is fail-closed" "FAIL-CLOSED:"

DEVELOPER_ID_APPLICATION="Apple Development: Maximilian Shupyro (558Y6Y86YJ)" \
    NOTARY_PROFILE="test-profile" \
    run_cmd "$SIGN_SCRIPT" --preflight-only --app "$FAKE_APP"
assert_exit_nonzero "T2: preflight rejects Apple Development identity by prefix"
assert_stderr_contains "T2: wrong-prefix failure message is fail-closed" "FAIL-CLOSED:"

DEVELOPER_ID_APPLICATION="Developer ID Application: Nobody (XXXXXXXXXX)" \
    NOTARY_PROFILE="test-profile" \
    run_cmd "$SIGN_SCRIPT" --preflight-only --app "$FAKE_APP"
assert_exit_nonzero "T2: preflight rejects absent Developer ID identity"
assert_stderr_contains "T2: absent-identity failure message is fail-closed" "FAIL-CLOSED:"

FAKE_SECURITY_BIN="$(make_fake_security)"
DEVELOPER_ID_APPLICATION="Developer ID Application: Local Test (TEST1234567)" \
    APPLE_ID="test@example.com" \
    PATH="$FAKE_SECURITY_BIN:$PATH" \
    run_cmd "$SIGN_SCRIPT" --preflight-only --app "$FAKE_APP"
assert_exit_nonzero "T2: preflight fails on partial notary credentials"
assert_stderr_contains "T2: partial-creds failure message is fail-closed" "FAIL-CLOSED:"

NOTARY_PROFILE="test-profile" \
    run_cmd "$SIGN_SCRIPT" --preflight-only --app "$SCRATCH/Missing.app"
assert_exit_nonzero "T2: preflight fails when app bundle is missing"
assert_stderr_contains "T2: missing-app failure message is fail-closed" "FAIL-CLOSED:"

CI=true \
    run_cmd "$SIGN_SCRIPT" --identity-override "Apple Distribution: Zigmund AM, LLC (56764BSR9B)" --app "$FAKE_APP"
assert_exit_nonzero "T2: identity override is forbidden in CI"
assert_stderr_contains "T2: CI override failure message is fail-closed" "FAIL-CLOSED:"

build_fake_app
FAKE_SECURITY_BIN="$(make_fake_security)"
app_checksum() {
    find "$FAKE_APP" -type f -exec shasum -a 256 {} \; | sort | shasum -a 256
}
BEFORE_SUM="$(app_checksum)"
DEVELOPER_ID_APPLICATION="Developer ID Application: Local Test (TEST1234567)" \
    NOTARY_PROFILE="test-profile" \
    PATH="$FAKE_SECURITY_BIN:$PATH" \
    run_cmd "$SIGN_SCRIPT" --dry-run --app "$FAKE_APP" --out "$SCRATCH/release"
assert_exit_zero "T2: dry-run exits successfully with a valid identity"
assert_stdout_contains "T2: dry-run prints notary-zip stage" "DRY-RUN: notary-zip"
assert_stdout_contains "T2: dry-run prints submit stage" "DRY-RUN: submit"
assert_stdout_contains "T2: dry-run prints staple stage" "DRY-RUN: staple"
assert_stdout_contains "T2: dry-run prints validate stage" "DRY-RUN: validate"
assert_stdout_contains "T2: dry-run prints assess stage" "DRY-RUN: assess"
assert_stdout_contains "T2: dry-run prints release-zip stage" "DRY-RUN: release-zip"
AFTER_SUM="$(app_checksum)"
assert_equal "T2: dry-run leaves app bundle checksum unchanged" "$BEFORE_SUM" "$AFTER_SUM"
assert_file_absent "T2: dry-run does not create release zip" "$SCRATCH/release/MacLimitsTracker.zip"
assert_file_absent "T2: dry-run does not create notary zip" "$SCRATCH/MacLimitsTracker-notary.zip"

SENTINEL="HUNTER2-SENTINEL"
leak_case() {
    local case_name="$1"
    shift
    DEVELOPER_ID_APPLICATION="Developer ID Application: Local Test (TEST1234567)" \
    NOTARY_PROFILE="$SENTINEL" \
    APPLE_ID="$SENTINEL" \
    APPLE_APP_PASSWORD="$SENTINEL" \
    APPLE_TEAM_ID="$SENTINEL" \
    NOTARY_KEY="$SENTINEL" \
    NOTARY_KEY_ID="$SENTINEL" \
    NOTARY_ISSUER="$SENTINEL" \
        run_cmd "$@"
    assert_no_secret_leak "$case_name" "$SENTINEL"
}

build_fake_app
leak_case "T2: no secret leak on identity-unset failure" \
    "$SIGN_SCRIPT" --preflight-only --app "$FAKE_APP"

leak_case "T2: no secret leak on wrong-prefix identity failure" \
    "$SIGN_SCRIPT" --preflight-only --app "$FAKE_APP"

leak_case "T2: no secret leak on absent-identity failure" \
    "$SIGN_SCRIPT" --preflight-only --app "$FAKE_APP"

leak_case "T2: no secret leak on partial-creds failure" \
    "$SIGN_SCRIPT" --preflight-only --app "$FAKE_APP"

leak_case "T2: no secret leak on missing-app failure" \
    "$SIGN_SCRIPT" --preflight-only --app "$SCRATCH/Missing.app"

leak_case "T2: no secret leak on CI-override failure" \
    "$SIGN_SCRIPT" --identity-override "Apple Distribution: Zigmund AM, LLC (56764BSR9B)" --app "$FAKE_APP"

FAKE_SECURITY_BIN="$(make_fake_security)"
SENTINEL_PROFILE="profile-sentinel-$$"
DEVELOPER_ID_APPLICATION="Developer ID Application: Local Test (TEST1234567)" \
NOTARY_PROFILE="$SENTINEL_PROFILE" \
PATH="$FAKE_SECURITY_BIN:$PATH" \
    run_cmd "$SIGN_SCRIPT" --dry-run --app "$FAKE_APP" --out "$SCRATCH/release"
assert_exit_zero "T2: dry-run with fake security succeeds"
assert_no_secret_leak "T2: no secret leak in dry-run output" "$SENTINEL_PROFILE"

assert_combined_contains() {
    local name="$1"
    local needle="$2"
    if grep -qF "$needle" "$SCRATCH/combined"; then
        ok "$name"
    else
        not_ok "$name" "combined output missing '$needle'"
    fi
}

# ---------------------------------------------------------------------------
# T3: sign + verify
# ---------------------------------------------------------------------------

build_fake_app
T3_OUT="$SCRATCH/t3-out"
run_cmd "$SIGN_SCRIPT" \
    --identity-override "Apple Distribution: Zigmund AM, LLC (56764BSR9B)" \
    --skip-notarize \
    --app "$FAKE_APP" \
    --out "$T3_OUT"
assert_exit_zero "T3: sign+verify with override identity succeeds"
assert_stdout_contains "T3: script reports signed artifact path" "ARTIFACT_APP="
SIGNED_APP="$(grep '^ARTIFACT_APP=' "$SCRATCH/stdout" | cut -d= -f2-)"

run_cmd codesign --verify --strict "$SIGNED_APP"
assert_exit_zero "T3: codesign --verify --strict passes on signed app"

run_cmd codesign -dv --verbose=4 "$SIGNED_APP"
assert_stderr_contains "T3: signed app has hardened runtime flag" "flags=0x10000(runtime)"
assert_stderr_contains "T3: signed app has expected team identifier" "TeamIdentifier=56764BSR9B"

build_fake_app
UNSIGNED_APP="$SCRATCH/unsigned/Fake.app"
mkdir -p "$SCRATCH/unsigned"
cp -a "$FAKE_APP" "$UNSIGNED_APP"
run_cmd codesign --verify --strict "$UNSIGNED_APP"
assert_exit_nonzero "T3: verify stage rejects unsigned fixture"

assert_file_absent "T3: override does not create dist/ directory" "dist"

# ---------------------------------------------------------------------------
# T4: notarize + staple + assess
# ---------------------------------------------------------------------------

build_fake_app
NOTARY_PROFILE="test-profile" \
    run_cmd "$SIGN_SCRIPT" --print-auth-method --app "$SCRATCH/Nonexistent.app"
assert_exit_zero "T4: print-auth-method bypasses preflight with missing app"
assert_equal "T4: profile auth method resolves" "profile" "$(cat "$SCRATCH/stdout")"

NOTARY_KEY="-----BEGIN PRIVATE KEY-----" \
NOTARY_KEY_ID="KID1234567" \
NOTARY_ISSUER="00000000-0000-0000-0000-000000000000" \
    run_cmd "$SIGN_SCRIPT" --print-auth-method
assert_exit_zero "T4: API key auth method resolves"
assert_equal "T4: api-key auth method resolves" "api-key" "$(cat "$SCRATCH/stdout")"

APPLE_ID="test@example.com" \
APPLE_APP_PASSWORD="abcd-efgh-ijkl-mnop" \
APPLE_TEAM_ID="TEST1234567" \
    run_cmd "$SIGN_SCRIPT" --print-auth-method
assert_exit_zero "T4: Apple ID auth method resolves"
assert_equal "T4: apple-id auth method resolves" "apple-id" "$(cat "$SCRATCH/stdout")"

run_cmd "$SIGN_SCRIPT" --print-auth-method
assert_exit_zero "T4: no auth method resolves to none-conflict"
assert_equal "T4: none-conflict auth method resolves" "none-conflict" "$(cat "$SCRATCH/stdout")"

NOTARY_KEY="k" \
NOTARY_KEY_ID="kid" \
    run_cmd "$SIGN_SCRIPT" --print-auth-method
assert_exit_nonzero "T4: partial API key auth method fails"
assert_stderr_contains "T4: partial API key reports fail-closed" "FAIL-CLOSED:"

APPLE_ID="a" \
    run_cmd "$SIGN_SCRIPT" --print-auth-method
assert_exit_nonzero "T4: partial Apple ID auth method fails"
assert_stderr_contains "T4: partial Apple ID reports fail-closed" "FAIL-CLOSED:"

NOTARY_PROFILE="p" \
NOTARY_KEY="k" \
NOTARY_KEY_ID="kid" \
NOTARY_ISSUER="iss" \
    run_cmd "$SIGN_SCRIPT" --print-auth-method
assert_exit_nonzero "T4: conflicting profile + API key auth methods fail"
assert_stderr_contains "T4: conflicting auth methods report fail-closed" "FAIL-CLOSED:"

NOTARY_PROFILE="p" \
APPLE_ID="a" \
APPLE_APP_PASSWORD="pw" \
APPLE_TEAM_ID="t" \
    run_cmd "$SIGN_SCRIPT" --print-auth-method
assert_exit_nonzero "T4: conflicting profile + Apple ID auth methods fail"
assert_stderr_contains "T4: conflicting profile+apple-id report fail-closed" "FAIL-CLOSED:"

build_fake_app
FAKE_SECURITY_BIN="$(make_fake_security)"
T4_SKIP_OUT="$SCRATCH/t4-skip-out"
run_cmd "$SIGN_SCRIPT" \
    --identity-override "Apple Distribution: Zigmund AM, LLC (56764BSR9B)" \
    --skip-notarize \
    --app "$FAKE_APP" \
    --out "$T4_SKIP_OUT"
assert_exit_zero "T4: --skip-notarize exits after sign+verify"
assert_stdout_contains "T4: skip-notarize reports artifact path" "ARTIFACT_APP="
assert_file_absent "T4: skip-notarize does not create release zip" "$T4_SKIP_OUT/MacLimitsTracker.zip"
assert_file_absent "T4: skip-notarize does not create notary zip" "$SCRATCH/MacLimitsTracker-notary.zip"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

printf '\n# pass: %d, fail: %d\n' "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
    exit 1
fi
exit 0
