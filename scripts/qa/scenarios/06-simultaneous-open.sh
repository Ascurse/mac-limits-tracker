#!/usr/bin/env bash
# scripts/qa/scenarios/06-simultaneous-open.sh
#
# EXPECTED RESULTS:
# - A single MacLimitsTracker process remains alive throughout.
# - Rapid triple-open (popup + main + Settings) produces exactly one main window
#   titled "Limits Tracker" and one Settings window.
# - The popup auto-dismisses once the main window becomes key.
# - Repeating the triple 3 times (closing surfaces between rounds) never creates
#   duplicated windows; counts stay 1/1 each round.

source "${SCRIPT_DIR}/lib/ax.sh"
source "${SCRIPT_DIR}/scenarios/_common.sh"

_qa_launch_clean

for round in 1 2 3; do
    log_action "simultaneous-open: round $round"

    # Fire the three open paths in rapid succession (no explicit waits).
    popup_open
    open_main_window
    open_settings_window

    assert_single_process

    # The popup must auto-dismiss when the main window becomes key.
    if ! popup_is_open; then
        _qa_pass "popup_dismissed_round_${round}" "popup auto-dismissed by design"
    else
        _qa_fail "popup_dismissed_round_${round}" "popup still open after main window became key"
    fi

    assert_window_present "^Limits Tracker$"
    assert_window_present ".*Settings.*"

    main_count="$(_qa_count_window_matches "^Limits Tracker$")"
    settings_count="$(_qa_count_window_matches ".*Settings.*")"
    total_count="$(_qa_count_window_matches ".*")"

    _qa_manual_assert "main_window_count_round_${round}" "$(( main_count == 1 ? 0 : 1 ))" "expected 1 main window, found $main_count"
    _qa_manual_assert "settings_window_count_round_${round}" "$(( settings_count == 1 ? 0 : 1 ))" "expected 1 settings window, found $settings_count"
    _qa_manual_assert "total_app_window_count_round_${round}" "$(( total_count == 2 ? 0 : 1 ))" "expected 2 app windows total, found $total_count"

    _qa_record_windows "windows-r${round}.txt"

    if [[ "$round" == "1" ]]; then
        screenshot "simultaneous"
    fi

    # Close surfaces between rounds; the final round leaves them open for the
    # driver to snapshot defaults-after.
    if [[ "$round" != "3" ]]; then
        close_window "^Limits Tracker$"
        close_window ".*Settings.*"
        popup_close
        wait_seconds 1
    fi
done

assert_activation_policy regular
log_action "simultaneous-open: complete"
