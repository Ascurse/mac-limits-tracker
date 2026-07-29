# scripts/qa/scenarios/03-desktop-first.sh
# 3ip.8 coexistence QA — first-surface: main desktop window.
#
# Expected results:
#   - App launches from clean state and the main "Limits Tracker" window is opened
#     as the first surface via activate + Cmd-0.
#   - Exactly one window matching /^Limits Tracker$/ is present.
#   - The popup is not open.
#   - Activation policy is regular.
#   - Sending Cmd-0 a second time keeps the main-window count at 1 (singleton).
#   - No crash.
# Leaves the app quit.
source "${SCRIPT_DIR}/lib/ax.sh"

APP_BUNDLE="${SCRIPT_DIR}/../../dist/MacLimitsTracker.app"
CRASH_WATERMARK="${CRASH_WATERMARK:-/tmp/qa-3ip8/crash-watermark}"

# Open the main window via explicit activate + Cmd-0 (allowed for this first surface).
_qa_s03_open_main_window_by_keystroke() {
    log_action "S03: opening main window via activate + Cmd-0"
    osascript -e 'tell application "MacLimitsTracker" to activate' >/dev/null 2>&1 || true
    _press_cmd_key "0" || true
}

# Count app windows whose title matches /^Limits Tracker$/.
_qa_s03_main_window_count() {
    local count=""
    count=$(_qa_app_windows | awk -F'|' '$5 ~ /^Limits Tracker$/ {print}' | wc -l | tr -d ' ') || true
    echo "${count:-0}"
}

# Return the window ID of the first main window, or empty if none.
_qa_s03_main_window_id() {
    _qa_app_windows | awk -F'|' '$5 ~ /^Limits Tracker$/ {print $1}' | head -n 1 || true
}

log_action "S03: begin desktop-first scenario"

# Clean state.
if [[ -n "$(app_pid 2>/dev/null || true)" ]]; then
    log_action "S03: app already running, quitting"
    quit_app || true
fi
_poll_until "process absent before launch" 20 0.5 _process_absent || true

# Launch.
open -a "$APP_BUNDLE" || true
if ! _poll_until "process to appear" 10 1 _process_exists; then
    log_action "S03: error: process did not appear within 10 s"
fi
wait_seconds 1

# First surface: activate + Cmd-0.
_qa_s03_open_main_window_by_keystroke
if ! _poll_until "main window to appear" 25 0.2 _window_with_title_exists "Limits Tracker"; then
    log_action "S03: main window did not appear within 5 s"
fi

# Core asserts.
assert_activation_policy regular
assert_window_present "^Limits Tracker$"

# Exactly one main window.
main_count=$(_qa_s03_main_window_count) || true
if [[ "$main_count" == "1" ]]; then
    _qa_pass "main_window_count" "exactly one Limits Tracker window ($main_count)"
else
    _qa_fail "main_window_count" "expected 1, found $main_count"
fi

# Popup must not be open.
if popup_is_open; then
    _qa_fail "popup_not_open" "popup unexpectedly open with main window"
else
    _qa_pass "popup_not_open" "popup not open"
fi

# Evidence: windowlist.
_qa_app_windows > "$(evidence_file windows.txt)" 2>&1 || true

# Screenshot the main window.
main_window_id=$(_qa_s03_main_window_id) || true
if [[ -n "$main_window_id" ]]; then
    screenshot_window "$main_window_id" "main-window" || true
else
    log_action "S03: could not identify main window id for screenshot"
fi

# Singleton focus: a second Cmd-0 must not add another window.
_qa_s03_open_main_window_by_keystroke
wait_seconds 0.5
main_count2=$(_qa_s03_main_window_count) || true
if [[ "$main_count2" == "1" ]]; then
    _qa_pass "main_window_singleton" "second Cmd-0 kept count at 1"
else
    _qa_fail "main_window_singleton" "second Cmd-0 changed count to $main_count2"
fi

# Crash check.
assert_no_crash "$CRASH_WATERMARK"

# Documented end state.
quit_app || true
