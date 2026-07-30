#!/usr/bin/env bash
# scripts/qa/red-phase.sh — prove every assert in lib/assert.sh CAN fail.
#
# Sets up an isolated scratch env under /tmp/qa-3ip8/red-phase-<ts>/,
# sources the QA harness libs, forces deliberately wrong state for each
# assert primitive, and records whether the assert correctly FAILED.
#
# Exits 0 only if every assert either failed as expected or is documented
# as deferred (requires running app to falsify).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# 1. Precondition: MacLimitsTracker must NOT be running
# ---------------------------------------------------------------------------
APP_PID="$(pgrep -x MacLimitsTracker 2>/dev/null | head -n 1 || true)"
if [[ -n "$APP_PID" ]]; then
    echo "ERROR: MacLimitsTracker is running (PID $APP_PID)." >&2
    echo "  Red-phase requires the app to be stopped because several asserts" >&2
    echo "  depend on the app NOT running to force a FAIL state." >&2
    echo "  Please quit MacLimitsTracker first, then re-run." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# 2. Scratch environment
# ---------------------------------------------------------------------------
TIMESTAMP="$(date +%s)"
EVIDENCE_ROOT="/tmp/qa-3ip8/red-phase-${TIMESTAMP}"
EVIDENCE_DIR="${EVIDENCE_ROOT}/red"
BIN_DIR="${EVIDENCE_ROOT}/bin"
mkdir -p "$EVIDENCE_DIR" "$BIN_DIR"

# Use pre-compiled windowlist from the latest preflight run if available.
LATEST_LINK="/tmp/qa-3ip8/latest"
if [[ -L "$LATEST_LINK" ]]; then
    LATEST_DIR="$(readlink "$LATEST_LINK")"
    if [[ -x "${LATEST_DIR}/bin/windowlist" ]]; then
        cp "${LATEST_DIR}/bin/windowlist" "${BIN_DIR}/windowlist"
    fi
fi
if [[ ! -x "${BIN_DIR}/windowlist" ]]; then
    swiftc -O -o "${BIN_DIR}/windowlist" "${SCRIPT_DIR}/lib/windowlist.swift"
fi

export EVIDENCE_ROOT EVIDENCE_DIR BIN_DIR

source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/ax.sh"
source "${SCRIPT_DIR}/lib/assert.sh"

printf '0\n' > "${EVIDENCE_DIR}/.failcount"

RED_LOG="${EVIDENCE_DIR}/red-phase.log"
: > "$RED_LOG"

log_info "=== Red-phase: proving every assert CAN fail ==="
echo "  EVIDENCE_DIR: $EVIDENCE_DIR"
echo "  BIN_DIR:      $BIN_DIR"

# ---------------------------------------------------------------------------
# 3. Assert runner helper
# ---------------------------------------------------------------------------
# Calls an assert function, checks whether it bumped .failcount, and writes
# EXPECTED-FAIL or UNEXPECTED-PASS to the log.
_red_check() {
    local name="$1"
    shift
    local before after
    before="$(cat "${EVIDENCE_DIR}/.failcount")"
    # Run the assert. Asserts never abort (they don't set -e internally), but
    # the || true is a safety net.
    "$@" || true
    after="$(cat "${EVIDENCE_DIR}/.failcount")"
    if [[ "$after" -gt "$before" ]]; then
        printf 'EXPECTED-FAIL ✓ %s\n' "$name" >> "$RED_LOG"
        printf '  ✓ %s FAILED as expected\n' "$name"
    else
        printf 'UNEXPECTED-PASS ✗ %s\n' "$name" >> "$RED_LOG"
        printf '  ✗ %s PASSED unexpectedly\n' "$name"
    fi
}

# ---------------------------------------------------------------------------
# 4. Run each assert with deliberately wrong state
# ---------------------------------------------------------------------------

# 4a. assert_single_process — app NOT running → pgrep returns 0, assert
#     expects exactly 1 process.
log_info "--- assert_single_process ---"
COUNT="$(pgrep -x MacLimitsTracker 2>/dev/null | wc -l | tr -d ' ')"
echo "  MacLimitsTracker processes: $COUNT"
_red_check "assert_single_process" assert_single_process

# 4b. assert_activation_policy regular — app NOT running → lsappinfo info
#     returns nothing → assert FAILs with "MacLimitsTracker not found".
log_info "--- assert_activation_policy ---"
_red_check "assert_activation_policy" assert_activation_policy regular

# 4c. assert_window_present "Limits Tracker" — app NOT running → _qa_app_windows
#     returns nothing → no window matches → FAIL.
log_info "--- assert_window_present ---"
_red_check "assert_window_present" assert_window_present "Limits Tracker"

# 4d. assert_widget_visible true — app NOT running, expected true → FAIL
#     "app not running, cannot check widget".
log_info "--- assert_widget_visible ---"
_red_check "assert_widget_visible" assert_widget_visible true

# 4e. assert_default showDesktopWidget true — set value to false, expect true
log_info "--- assert_default ---"
WIDGET_SNAPSHOT="$(defaults read dev.ascurse.MacLimitsTracker showDesktopWidget 2>/dev/null || echo "")"
WIDGET_ABSENT=false
if [[ -z "$WIDGET_SNAPSHOT" ]]; then
    WIDGET_ABSENT=true
fi
echo "  Current showDesktopWidget: '${WIDGET_SNAPSHOT:-<absent>}'"

# Set to false (will expect true so the assert fails).
defaults write dev.ascurse.MacLimitsTracker showDesktopWidget -bool false
_red_check "assert_default" assert_default "showDesktopWidget" "true"

# RESTORE the snapshotted value.
# Note: defaults read returns "0" or "1" for booleans; -bool expects
# true/false keywords so we map appropriately.
if [[ "$WIDGET_ABSENT" == "true" ]]; then
    defaults delete dev.ascurse.MacLimitsTracker showDesktopWidget 2>/dev/null || true
    echo "  Deleted showDesktopWidget (was absent before)"
else
    if [[ "$WIDGET_SNAPSHOT" == "1" ]]; then
        defaults write dev.ascurse.MacLimitsTracker showDesktopWidget -bool true
    else
        defaults write dev.ascurse.MacLimitsTracker showDesktopWidget -bool false
    fi
    echo "  Restored showDesktopWidget: $(defaults read dev.ascurse.MacLimitsTracker showDesktopWidget)"
fi

# 4f. assert_no_leaked_windows 999 — app not running → 0 windows, expected
#     999 → 0 != 999 → FAIL.
log_info "--- assert_no_leaked_windows ---"
_red_check "assert_no_leaked_windows" assert_no_leaked_windows 999

# 4g. assert_refresh_happened — baseline contains mtime far in the future
#     (year 2286) so history.json mtime can never advance past it.
log_info "--- assert_refresh_happened ---"
BASELINE_FILE="${EVIDENCE_DIR}/future-baseline"
printf '9999999999\n' > "$BASELINE_FILE"
HISTORY_FILE="${HOME}/Library/Application Support/dev.ascurse.MacLimitsTracker/history.json"
if [[ -f "$HISTORY_FILE" ]]; then
    echo "  history.json mtime: $(stat -f %m "$HISTORY_FILE")  (baseline: 9999999999)"
else
    echo "  history.json does NOT exist (assert will also FAIL)"
fi
_red_check "assert_refresh_happened" assert_refresh_happened "$BASELINE_FILE"

# 4h. assert_no_crash — plant a fake .ips newer than a very old watermark,
#     run assert, then delete everything we planted. If DiagnosticReports/
#     doesn't exist, the assert short-circuits with PASS, so we must create
#     the directory to exercise the real new-reports check.
log_info "--- assert_no_crash ---"
WATERMARK_FILE="${EVIDENCE_DIR}/crash-watermark"
REPORTS_DIR="${HOME}/Library/DiagnosticReports"
CREATED_REPORTS_DIR=false
if [[ ! -d "$REPORTS_DIR" ]]; then
    mkdir -p "$REPORTS_DIR"
    CREATED_REPORTS_DIR=true
    echo "  Created $REPORTS_DIR (did not exist)"
fi
touch -t 200001010000 "$WATERMARK_FILE"
FAKE_CRASH="${REPORTS_DIR}/MacLimitsTracker-FAKE-RED-PHASE.ips"
echo "Fake crash report for red-phase QA — safe to delete." > "$FAKE_CRASH"
echo "  Planted: $FAKE_CRASH"
_red_check "assert_no_crash" assert_no_crash "$WATERMARK_FILE"
rm -f "$FAKE_CRASH"
echo "  Deleted fake crash report"
if [[ "$CREATED_REPORTS_DIR" == "true" ]]; then
    rmdir "$REPORTS_DIR" 2>/dev/null || true
    echo "  Removed $REPORTS_DIR (was created by red-phase)"
fi

# 4i. assert_window_absent — DEFERRED. The assert filters by app PID (or
#     owner name "MacLimitsTracker" as fallback). Without the app running,
#     _qa_app_windows always returns empty, so assert_window_absent always
#     PASSES (no windows → no unexpected windows). It is only falsifiable
#     when the app IS running and HAS windows.
log_info "--- assert_window_absent (deferred) ---"
echo "  App not running: _qa_app_windows returns empty set"
echo "  assert_window_absent always PASSES when no app windows exist"
echo "  Primitive requires running app with windows to falsify"
printf 'EXPECTED-FAIL ✓ assert_window_absent (deferred: requires running app)\n' >> "$RED_LOG"
echo "  ↪ recorded as deferred"

# ---------------------------------------------------------------------------
# 5. Report and exit
# ---------------------------------------------------------------------------
echo ""
echo "=== Red-phase results ==="
cat "$RED_LOG"
echo ""

UNEXPECTED="$(grep -c '^UNEXPECTED-PASS' "$RED_LOG" || true)"
EXPECTED_COUNT="$(grep -c '^EXPECTED-FAIL' "$RED_LOG" || true)"
DEFERRED_COUNT="$(grep -c '^EXPECTED-FAIL.*deferred' "$RED_LOG" || true)"
VERIFIABLE_COUNT=$((EXPECTED_COUNT - DEFERRED_COUNT))

# EXPECTED_COUNT includes deferred. 9 = 8 verifiable + 1 deferred.
if [[ "$EXPECTED_COUNT" -ne 9 ]]; then
    echo "WARNING: Expected 9 EXPECTED-FAIL entries, found $EXPECTED_COUNT" >&2
fi

if [[ "$UNEXPECTED" -gt 0 ]]; then
    log_info "VERDICT: FAIL — $UNEXPECTED assert(s) PASSED when they should have FAILED"
    exit 1
else
    log_info "VERDICT: PASS — $VERIFIABLE_COUNT verifiable asserts all failed as expected, $DEFERRED_COUNT deferred"
    exit 0
fi
