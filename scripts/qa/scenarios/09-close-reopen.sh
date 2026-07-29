#!/usr/bin/env bash
# scripts/qa/scenarios/09-close-reopen.sh
#
# EXPECTED RESULTS:
# - Three close/reopen cycles of the main and Settings windows keep exactly one
#   main window and one Settings window after each reopen.
# - Activation policy stays regular throughout the cycles.
# - After the final close of both windows, the app remains alive, its menu-bar
#   item is present, and the policy is still regular (no demotion/quit).

source "${SCRIPT_DIR}/lib/ax.sh"
source "${SCRIPT_DIR}/scenarios/_common.sh"

_qa_launch_clean
open_main_window
open_settings_window

assert_activation_policy regular

for cycle in 1 2 3; do
    log_action "close-reopen: cycle $cycle"

    close_window "^Limits Tracker$"
    close_window ".*Settings.*"

    popup_open
    popup_click_button "Open Limits Tracker"
    popup_click_button "Open Settings"

    wait_seconds 1

    assert_window_present "^Limits Tracker$"
    assert_window_present ".*Settings.*"

    main_count="$(_qa_count_window_matches "^Limits Tracker$")"
    settings_count="$(_qa_count_window_matches ".*Settings.*")"
    _qa_manual_assert "main_window_count_cycle_${cycle}" "$(( main_count == 1 ? 0 : 1 ))" "expected 1 main window, found $main_count"
    _qa_manual_assert "settings_window_count_cycle_${cycle}" "$(( settings_count == 1 ? 0 : 1 ))" "expected 1 settings window, found $settings_count"

    assert_activation_policy regular
    _qa_record_windows "windows-cycle${cycle}.txt"
done

# Final close: the app must stay alive and regular.
close_window "^Limits Tracker$"
close_window ".*Settings.*"
wait_seconds 1

assert_single_process
if _qa_menu_bar_item_present; then
    _qa_pass "menu_bar_item_present_after_final_close" "menu-bar item still present after closing all windows"
else
    _qa_fail "menu_bar_item_present_after_final_close" "menu-bar item missing after closing all windows"
fi
assert_activation_policy regular

screenshot "reopened"
log_action "close-reopen: complete"
