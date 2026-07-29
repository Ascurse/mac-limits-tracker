#!/usr/bin/env bash
# scripts/qa/lib/assert.sh — binary pass/fail assert primitives for 3ip.8 QA.
#
# Each assert appends a PASS/FAIL line to $EVIDENCE_DIR/assert.log, echoes it,
# and updates the atomic fail counter at $EVIDENCE_DIR/.failcount.
#
# This file is SOURCED; it does NOT set -e. A failing assert must NOT abort.
# Bash 3.2 compatible.

# ---------------------------------------------------------------------------
# Counter helpers
# ---------------------------------------------------------------------------

_qa_failcount_path() {
    echo "${EVIDENCE_DIR}/.failcount"
}

_qa_init_failcount() {
    local path
    path="$(_qa_failcount_path)"
    if [[ ! -f "$path" ]]; then
        printf '0\n' > "$path"
    fi
}

_qa_bump_failcount() {
    local path
    path="$(_qa_failcount_path)"
    _qa_init_failcount
    # Atomic-ish increment using flock when available; scenario scripts are
    # single-process, so a simple RMW is sufficient and bash-3.2 safe.
    if command -v flock >/dev/null 2>&1; then
        flock "$path" -c '
            path="'"$path"'"
            count=$(cat "$path" 2>/dev/null || echo 0)
            count=$((count + 1))
            printf "%s\n" "$count" > "$path"
        '
    else
        local count
        count="$(cat "$path" 2>/dev/null || echo 0)"
        count=$((count + 1))
        printf '%s\n' "$count" > "$path"
    fi
}

_qa_assert_log() {
    local status="$1"
    local name="$2"
    local detail="$3"
    _qa_init_failcount
    printf '%s: %s: %s\n' "$status" "$name" "$detail" | tee -a "${EVIDENCE_DIR}/assert.log"
}

_qa_pass() {
    _qa_assert_log "PASS" "$1" "$2"
}

_qa_fail() {
    _qa_assert_log "FAIL" "$1" "$2"
    _qa_bump_failcount
}

# ---------------------------------------------------------------------------
# Windowlist helpers
# ---------------------------------------------------------------------------

# Path to compiled windowlist binary. run-scenario.sh sets BIN_DIR.
_qa_windowlist() {
    if [[ -n "${BIN_DIR:-}" && -x "${BIN_DIR}/windowlist" ]]; then
        "${BIN_DIR}/windowlist" 2>/dev/null
    else
        # Allow ad-hoc usage if the binary is on PATH.
        windowlist 2>/dev/null
    fi
}

# Filter windowlist to rows owned by MacLimitsTracker (by pid or owner name).
_qa_app_windows() {
    local pid
    pid="$(app_pid 2>/dev/null || true)"
    if [[ -n "$pid" ]]; then
        _qa_windowlist | awk -F'|' -v pid="$pid" '$2 == pid {print}'
    else
        _qa_windowlist | awk -F'|' '$3 == "Limits Tracker" {print}'
    fi
}

# ---------------------------------------------------------------------------
# Assert primitives
# ---------------------------------------------------------------------------

# assert_single_process -> pgrep -x MacLimitsTracker | wc -l == 1
assert_single_process() {
    local count
    count="$(pgrep -x MacLimitsTracker 2>/dev/null | wc -l | tr -d ' ' || true)"
    if [[ "$count" == "1" ]]; then
        _qa_pass "assert_single_process" "exactly one MacLimitsTracker process ($count)"
    else
        _qa_fail "assert_single_process" "expected 1 process, found $count"
    fi
}

# assert_activation_policy <regular|accessory>
# Parses lsappinfo info MacLimitsTracker output.
#
# Empirical format (macOS 14+, verified on this machine):
#   Plain `lsappinfo info Finder` prints:
#       pid = 44678 type="Foreground" flavor=3 Version="1828.5.2" ...
#   `lsappinfo -all info Finder` contains:
#       "ApplicationType"="Foreground"
#   Accessory / LSUIElement apps (e.g. Control Centre, WindowManager) show:
#       type="UIElement"
#       "ApplicationType"="UIElement"
#   Background-only agents show:
#       type="BackgroundOnly"
# We parse both the short `type="..."` and full `ApplicationType="..."` keys
# and map Foreground -> regular, UIElement/BackgroundOnly -> accessory.
assert_activation_policy() {
    local expected="$1"
    local raw
    raw="$(lsappinfo info "dev.ascurse.MacLimitsTracker" 2>/dev/null || true)"
    if [[ -z "$raw" ]]; then
        _qa_fail "assert_activation_policy" "MacLimitsTracker not found by lsappinfo"
        return
    fi

    local policy
    policy="$(echo "$raw" | sed -nE 's/.*(ApplicationType|type)="([^"]+)".*/\2/p' | head -n 1)"

    local mapped
    case "$policy" in
        Foreground) mapped="regular" ;;
        UIElement|BackgroundOnly) mapped="accessory" ;;
        *) mapped="unknown($policy)" ;;
    esac

    if [[ "$mapped" == "$expected" ]]; then
        _qa_pass "assert_activation_policy" "expected $expected, got $mapped (raw: $policy)"
    else
        _qa_fail "assert_activation_policy" "expected $expected, got $mapped (raw: $policy)"
    fi
}

# assert_window_present <title-regex>
assert_window_present() {
    local regex="$1"
    local matches
    matches="$(_qa_app_windows | awk -F'|' -v re="$regex" '$5 ~ re {print}' || true)"
    if [[ -n "$matches" ]]; then
        local first
        first="$(echo "$matches" | head -n 1)"
        _qa_pass "assert_window_present" "found window matching /$regex/: $first"
    else
        _qa_fail "assert_window_present" "no window matching /$regex/ in windowlist"
    fi
}

# assert_window_absent <title-regex>
assert_window_absent() {
    local regex="$1"
    local matches
    matches="$(_qa_app_windows | awk -F'|' -v re="$regex" '$5 ~ re {print}' || true)"
    if [[ -z "$matches" ]]; then
        _qa_pass "assert_window_absent" "no window matching /$regex/ in windowlist"
    else
        local first
        first="$(echo "$matches" | head -n 1)"
        _qa_fail "assert_window_absent" "found unexpected window matching /$regex/: $first"
    fi
}

# assert_widget_visible <true|false>
# The desktop widget is an NSPanel at desktop level + 1. It is not reliably
# captured by the windowlist helper, so we detect it via Accessibility: an
# AXSystemDialog window of the app that does NOT contain the popup's action
# buttons (Open Settings / Open Limits Tracker).
assert_widget_visible() {
    local expected="$1"
    local widgets
    widgets="$(_qa_widget_window_exists >/dev/null && echo yes || echo no)"

    if [[ "$expected" == "true" ]]; then
        if [[ "$widgets" == "yes" ]]; then
            _qa_pass "assert_widget_visible" "desktop widget window found"
        else
            _qa_fail "assert_widget_visible" "no desktop widget window found"
        fi
    else
        if [[ "$widgets" == "no" ]]; then
            _qa_pass "assert_widget_visible" "no desktop widget window found"
        else
            _qa_fail "assert_widget_visible" "unexpected desktop widget window found"
        fi
    fi
}

# assert_no_leaked_windows <expected-count-or-list>
# Currently supports an expected count (numeric). Counts windows owned by the app.
assert_no_leaked_windows() {
    local expected="$1"
    local count
    count="$(_qa_app_windows | wc -l | tr -d ' ' || true)"
    local expected_count="$expected"
    if [[ "$expected" == "none" ]]; then
        expected_count="0"
    fi
    if [[ "$expected_count" =~ ^[0-9]+$ ]]; then
        if [[ "$count" == "$expected_count" ]]; then
            _qa_pass "assert_no_leaked_windows" "found $count app windows (expected $expected_count)"
        else
            _qa_fail "assert_no_leaked_windows" "found $count app windows, expected $expected_count"
        fi
    else
        _qa_fail "assert_no_leaked_windows" "expected numeric count or 'none', got '$expected'"
    fi
}

# Normalize boolean-like values for macOS defaults comparison.
# defaults read returns 1/0 for booleans; tests often write true/false.
_qa_normalize_bool() {
    case "$1" in
        1|true|yes) echo "true" ;;
        0|false|no) echo "false" ;;
        *) echo "$1" ;;
    esac
}

# assert_default <key> <expected>
assert_default() {
    local key="$1"
    local expected="$2"
    local actual
    actual="$(defaults read dev.ascurse.MacLimitsTracker "$key" 2>/dev/null || true)"
    local expected_norm actual_norm
    expected_norm="$(_qa_normalize_bool "$expected")"
    actual_norm="$(_qa_normalize_bool "$actual")"
    if [[ "$actual_norm" == "$expected_norm" ]]; then
        _qa_pass "assert_default" "$key == $expected (raw: $actual)"
    else
        _qa_fail "assert_default" "$key expected '$expected' (norm: $expected_norm), got '$actual' (norm: $actual_norm)"
    fi
}

# assert_refresh_happened <baseline-mtime-file>
# The argument is a file containing the baseline mtime epoch-seconds of history.json.
assert_refresh_happened() {
    local baseline_file="$1"
    local history="${HOME}/Library/Application Support/dev.ascurse.MacLimitsTracker/history.json"
    if [[ ! -f "$baseline_file" ]]; then
        _qa_fail "assert_refresh_happened" "baseline file missing: $baseline_file"
        return
    fi
    if [[ ! -f "$history" ]]; then
        _qa_fail "assert_refresh_happened" "history.json does not exist: $history"
        return
    fi

    local baseline current
    baseline="$(cat "$baseline_file" 2>/dev/null || true)"
    current="$(stat -f %m "$history" 2>/dev/null || true)"

    if [[ -z "$baseline" || -z "$current" ]]; then
        _qa_fail "assert_refresh_happened" "could not read mtime values (baseline=$baseline current=$current)"
        return
    fi

    if [[ "$current" -gt "$baseline" ]]; then
        _qa_pass "assert_refresh_happened" "history mtime advanced: $baseline -> $current"
    else
        _qa_fail "assert_refresh_happened" "history mtime did not advance: $baseline vs $current"
    fi
}

# assert_no_crash <watermark-file>
assert_no_crash() {
    local watermark="$1"
    local reports_dir="${HOME}/Library/DiagnosticReports"
    if [[ ! -f "$watermark" ]]; then
        _qa_fail "assert_no_crash" "watermark file missing: $watermark"
        return
    fi
    if [[ ! -d "$reports_dir" ]]; then
        _qa_pass "assert_no_crash" "DiagnosticReports directory absent, no crash reports possible"
        return
    fi

    local new_reports
    new_reports="$(find "$reports_dir" -maxdepth 1 -name 'MacLimitsTracker-*.ips' -newer "$watermark" 2>/dev/null || true)"
    if [[ -z "$new_reports" ]]; then
        _qa_pass "assert_no_crash" "no MacLimitsTracker crash reports newer than watermark"
    else
        local first
        first="$(echo "$new_reports" | head -n 1)"
        local count
        count="$(echo "$new_reports" | wc -l | tr -d ' ' || true)"
        _qa_fail "assert_no_crash" "found $count new crash report(s), e.g. $first"
    fi
}
