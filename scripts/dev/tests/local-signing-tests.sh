#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
MAKE_APP="$ROOT/make-app.sh"
SETUP_SCRIPT="$ROOT/scripts/dev/setup-local-signing.sh"
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

PASS=0
FAIL=0
TEST_NO=1

ok() {
    printf 'ok %d - %s\n' "$TEST_NO" "$1"
    PASS=$((PASS + 1))
    TEST_NO=$((TEST_NO + 1))
}

not_ok() {
    printf 'not ok %d - %s\n' "$TEST_NO" "$1"
    FAIL=$((FAIL + 1))
    TEST_NO=$((TEST_NO + 1))
}

assert_exit_zero() {
    local name="$1"
    shift
    if "$@" >"$SCRATCH/stdout" 2>"$SCRATCH/stderr"; then
        ok "$name"
    else
        not_ok "$name"
    fi
}

assert_exit_nonzero() {
    local name="$1"
    shift
    if "$@" >"$SCRATCH/stdout" 2>"$SCRATCH/stderr"; then
        not_ok "$name"
    else
        ok "$name"
    fi
}

assert_file_contains_line() {
    local name="$1"
    local file="$2"
    local expected="$3"
    if grep -qxF "$expected" "$file"; then
        ok "$name"
    else
        not_ok "$name"
    fi
}

FAKE_BIN="$SCRATCH/bin"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/codesign" <<'EOF'
#!/usr/bin/env bash
for arg in "$@"; do
    printf '<%s>\n' "$arg"
done > "${SIGNING_ARGS_FILE:?}"
EOF
chmod +x "$FAKE_BIN/codesign"

FAKE_BINARY="$SCRATCH/MacLimitsTracker"
printf '#!/usr/bin/env bash\n' > "$FAKE_BINARY"
chmod +x "$FAKE_BINARY"

run_make_app() {
    local output_dir="$1"
    shift
    SIGNING_ARGS_FILE="$SCRATCH/signing-args" \
        PATH="$FAKE_BIN:$PATH" \
        BIN_SRC="$FAKE_BINARY" \
        "$@" "$MAKE_APP" "$output_dir"
}

assert_exit_zero "make-app.sh keeps ad-hoc signing by default" \
    run_make_app "$SCRATCH/default" env -u MAC_LIMITS_TRACKER_SIGNING_IDENTITY bash
assert_file_contains_line "default signing identity is ad-hoc" \
    "$SCRATCH/signing-args" "<->"

assert_exit_zero "make-app.sh accepts a local signing identity" \
    run_make_app "$SCRATCH/local" env MAC_LIMITS_TRACKER_SIGNING_IDENTITY="MacLimitsTracker Local" bash
assert_file_contains_line "local signing identity is passed to codesign" \
    "$SCRATCH/signing-args" "<MacLimitsTracker Local>"

assert_exit_zero "local signing setup script has valid shell syntax" bash -n "$SETUP_SCRIPT"

FAKE_SECURITY_BIN="$SCRATCH/security-bin"
mkdir -p "$FAKE_SECURITY_BIN"
cat > "$FAKE_SECURITY_BIN/security" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "find-identity" ]]; then
    printf '%s\n' \
        '  1) PERSONAL "Apple Development: Personal Account (PERSONAL123)"' \
        '  2) WORK "Apple Distribution: Work Account (WORK123)"'
    exit 0
fi
exit 1
EOF
chmod +x "$FAKE_SECURITY_BIN/security"

run_setup_with_fake_security() {
    PATH="$FAKE_SECURITY_BIN:$PATH" "$@"
}

assert_exit_nonzero "setup refuses to choose an identity automatically" \
    run_setup_with_fake_security env -u MAC_LIMITS_TRACKER_SIGNING_IDENTITY bash "$SETUP_SCRIPT"
if grep -qF 'Apple Development: Personal Account (PERSONAL123)' "$SCRATCH/stderr"; then
    ok "setup lists available identities without selecting one"
else
    not_ok "setup lists available identities without selecting one"
fi

assert_exit_zero "setup accepts an explicitly selected personal identity" \
    run_setup_with_fake_security env MAC_LIMITS_TRACKER_SIGNING_IDENTITY="Apple Development: Personal Account (PERSONAL123)" bash "$SETUP_SCRIPT"

assert_exit_nonzero "setup rejects a non-Apple-Development identity" \
    run_setup_with_fake_security env MAC_LIMITS_TRACKER_SIGNING_IDENTITY="Apple Distribution: Work Account (WORK123)" bash "$SETUP_SCRIPT"

printf '\n# pass: %d, fail: %d\n' "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
    exit 1
fi
