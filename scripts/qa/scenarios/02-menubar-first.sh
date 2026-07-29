# scripts/qa/scenarios/02-menubar-first.sh
# 3ip.8 coexistence QA — first-surface: menu-bar popup.
#
# Expected results:
#   - App launches from clean state and the menu-bar popup is opened as the first surface.
#   - popup_is_open reports true (manual FAIL line if not).
#   - Activation policy remains regular.
#   - The first refresh advances history.json mtime within ~30 s.
#   - Opening the main window from the popup dismisses the popup automatically;
#     this is logged as expected behavior, not a failure.
#   - No crash.
# Leaves the app quit.
source "${SCRIPT_DIR}/lib/ax.sh"

APP_BUNDLE="${SCRIPT_DIR}/../../dist/MacLimitsTracker.app"
CRASH_WATERMARK="${CRASH_WATERMARK:-/tmp/qa-3ip8/crash-watermark}"
BASELINE="${EVIDENCE_DIR}/history-mtime-baseline.txt"

# Poll up to 30 s for history.json mtime to advance past the baseline.
_qa_s02_poll_refresh() {
    local baseline_file="$1"
    local baseline=""
    local current=""
    local i
    local HISTORY_PATH="${HOME}/Library/Application Support/dev.ascurse.MacLimitsTracker/history.json"

    if [[ ! -f "$baseline_file" ]]; then
        log_action "S02: refresh baseline missing: $baseline_file"
        return 1
    fi

    baseline=$(cat "$baseline_file" 2>/dev/null || true)
    [[ -n "$baseline" ]] || baseline="0"

    for ((i=1; i<=30; i++)); do
        if [[ -f "$HISTORY_PATH" ]]; then
            current=$(stat -f %m "$HISTORY_PATH" 2>/dev/null || true)
            if [[ -n "$current" && "$current" -gt "$baseline" ]]; then
                log_action "S02: refresh advanced history mtime after ${i}s"
                return 0
            fi
        fi
        wait_seconds 1
    done

    log_action "S02: refresh did not advance history mtime within 30 s"
    return 1
}

log_action "S02: begin menu-bar-first scenario"

# Clean state.
if [[ -n "$(app_pid 2>/dev/null || true)" ]]; then
    log_action "S02: app already running, quitting"
    quit_app || true
fi
_poll_until "process absent before launch" 20 0.5 _process_absent || true

# Launch.
open -a "$APP_BUNDLE" || true
if ! _poll_until "process to appear" 10 1 _process_exists; then
    log_action "S02: error: process did not appear within 10 s"
fi
wait_seconds 1

# Windowlist before opening the popup.
_qa_app_windows > "$(evidence_file windows-before-popup.txt)" 2>&1 || true

# First surface: open the menu-bar popup.
if popup_open; then
    _qa_pass "popup_open" "menu-bar popup opened as first surface"
else
    _qa_fail "popup_open" "menu-bar popup failed to open"
fi

# Manual assert on direct popup state.
if popup_is_open; then
    _qa_pass "popup_is_open" "AXSystemDialog is present"
else
    _qa_fail "popup_is_open" "AXSystemDialog is not present"
fi

# Windowlist after opening the popup.
_qa_app_windows > "$(evidence_file windows-after-popup.txt)" 2>&1 || true

# Screenshot while popup is open (no focus theft).
screenshot "popup-open" || true

# Policy.
assert_activation_policy regular

# Poll for refresh, then assert.
if ! _qa_s02_poll_refresh "$BASELINE"; then
    log_action "S02: first refresh did not advance within 30 s"
fi
assert_refresh_happened "$BASELINE"

# Open main window from popup and expect popup auto-dismissal.
if open_main_window; then
    if popup_is_open; then
        _qa_fail "popup_auto_dismissed" "popup remained open after opening main window"
    else
        log_action "S02: popup auto-dismissed after opening main window (expected behavior)"
    fi
else
    log_action "S02: open_main_window failed, cannot check popup auto-dismissal"
fi

# Crash check.
assert_no_crash "$CRASH_WATERMARK"

# Documented end state.
quit_app || true
