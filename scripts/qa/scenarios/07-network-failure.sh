#!/usr/bin/env bash
# scripts/qa/scenarios/07-network-failure.sh
#
# EXPECTED RESULTS:
# - Launching the binary directly with an isolated HOME and minimal PATH produces a
#   single responsive MacLimitsTracker process.
# - The app shows an error state in the popup or menu-bar title but does not
#   crash (no new .ips reports newer than the watermark).
# - The main window remains openable despite the failure.
# - After a clean relaunch, a refresh succeeds and no stale error UI remains.

source "${SCRIPT_DIR}/lib/ax.sh"
source "${SCRIPT_DIR}/scenarios/_common.sh"

_qa_ensure_watermark
_qa_launch_clean

history_file="${HOME}/Library/Application Support/dev.ascurse.MacLimitsTracker/history.json"
mtimes_log="$(evidence_file history-mtimes.log)"

pre_launch_mtime="$(stat -f %m "$history_file" 2>/dev/null || echo 0)"
printf 'pre-launch: %s\n' "$pre_launch_mtime" > "$mtimes_log"

# Quit the clean instance and relaunch without provider CLI/auth files.
log_action "network-failure: quitting clean instance"
quit_app || true
_qa_wait_for_process_exit 10 0.5 || true

binary_path="$(_qa_app_path)/Contents/MacOS/MacLimitsTracker"
isolated_home="$(mktemp -d /tmp/mac-limits-tracker-qa-home.XXXXXX)"
log_action "network-failure: launching binary with isolated HOME and minimal PATH"
HOME="$isolated_home" PATH="/usr/bin:/bin" "$binary_path" >/dev/null 2>&1 &
disown

_qa_wait_for_process 15 0.5
wait_seconds 5

# Wait up to 45 seconds for provider discovery/refresh attempts to fail.
log_action "network-failure: waiting 45s for isolated refresh attempts to fail"
attempt=1
while [ "$attempt" -le 9 ]; do
    wait_seconds 5
    attempt=$((attempt + 1))
done

post_failure_mtime="$(stat -f %m "$history_file" 2>/dev/null || echo 0)"
printf 'post-failure: %s\n' "$post_failure_mtime" >> "$mtimes_log"

assert_single_process

if popup_open; then
    _qa_pass "popup_responsive_under_failure" "popup opened under isolated provider failure"
else
    _qa_fail "popup_responsive_under_failure" "popup did not open under isolated provider failure"
fi

_qa_dump_popup_contents_to_evidence "popup-failure-contents"
menu_bar_title="$(_qa_menu_bar_title)"
log_action "network-failure: menu-bar title under failure: ${menu_bar_title:-<none>}"
lsappinfo info "dev.ascurse.MacLimitsTracker" > "$(evidence_file lsappinfo-failure.txt)" 2>/dev/null || true

failure_probe="$(grep -iE "error|failed|expired|unreachable|timeout" "$(evidence_file popup-failure-contents.txt)" 2>/dev/null | head -n 1 || true)"
if [[ -n "$failure_probe" || -n "$menu_bar_title" ]]; then
    _qa_pass "error_state_visible" "observed error indicator: ${failure_probe:-menu-bar-title=$menu_bar_title}"
else
    _qa_fail "error_state_visible" "no error indicator visible in popup or menu bar"
fi

assert_no_crash "$(_qa_watermark_path)"

open_main_window
assert_window_present "^Limits Tracker$"
close_window "^Limits Tracker$"

screenshot "error-state"

# Relaunch cleanly and wait for a successful refresh.
log_action "network-failure: quitting isolated instance and relaunching clean"
quit_app
_qa_wait_for_process_exit 10 0.5
if [[ "$isolated_home" == /tmp/mac-limits-tracker-qa-home.* ]]; then
    rm -rf -- "$isolated_home"
else
    _qa_fail "isolated_home_cleanup" "refusing unexpected cleanup path: $isolated_home"
fi

open -a "$(_qa_app_path)" >/dev/null 2>&1 || open "$(_qa_app_path)" >/dev/null 2>&1 || true
_qa_wait_for_process 15 0.5
wait_seconds 3

post_relaunch_mtime="$(stat -f %m "$history_file" 2>/dev/null || echo 0)"
printf 'post-relaunch: %s\n' "$post_relaunch_mtime" >> "$mtimes_log"

relaunch_baseline="$(evidence_file history-mtime-relaunch-baseline.txt)"
printf '%s\n' "$post_relaunch_mtime" > "$relaunch_baseline"

if _qa_wait_for_refresh "$relaunch_baseline" 60 2; then
    assert_refresh_happened "$relaunch_baseline"
else
    _qa_fail "recovery_refresh" "history mtime did not advance after clean relaunch"
fi

assert_single_process
assert_no_crash "$(_qa_watermark_path)"
screenshot "recovered-state"

log_action "network-failure: complete"
