#!/usr/bin/env bash
# scripts/qa/scenarios/10-quit-relaunch.sh
#
# EXPECTED RESULTS:
# - Quitting the app removes the process within 5 seconds and leaves no leaked
#   windows owned by the dead PID (including negative-layer widget panels).
# - A clean relaunch preserves app-owned UserDefaults; macOS-managed window
#   frames may change when the system chooses another display.
# - Widget visibility matches the persisted showDesktopWidget setting.
# - Activation policy stays regular and the app does not crash.

source "${SCRIPT_DIR}/lib/ax.sh"
source "${SCRIPT_DIR}/scenarios/_common.sh"

_qa_ensure_watermark
_qa_launch_clean

# Read-only seed: record current defaults before quitting.
defaults export dev.ascurse.MacLimitsTracker - > "$(evidence_file defaults-pre-quit.txt)" 2>/dev/null || true

# Read the persisted widget setting so we can verify it after relaunch.
widget_enabled="$(defaults read dev.ascurse.MacLimitsTracker showDesktopWidget 2>/dev/null || echo 0)"
log_action "quit-relaunch: persisted showDesktopWidget = $widget_enabled"

# Capture the PID before quit so we can detect leaked windows afterwards.
pre_quit_pid="$(app_pid)"
log_action "quit-relaunch: pre-quit pid = ${pre_quit_pid:-<none>}"

quit_app
if _qa_wait_for_process_exit 10 0.5; then
    _qa_pass "process_exited_after_quit" "process exited within 5 seconds of quit"
else
    _qa_fail "process_exited_after_quit" "process still alive after quit timeout"
fi

windowlist_after_quit="$(evidence_file windowlist-after-quit.txt)"
"${BIN_DIR}/windowlist" > "$windowlist_after_quit" 2>/dev/null || true

leaked_count="$(awk -F'|' -v pid="$pre_quit_pid" '$2 == pid {count++} END {print count+0}' "$windowlist_after_quit")"
_qa_manual_assert "no_leaked_windows_after_quit" "$(( leaked_count == 0 ? 0 : 1 ))" "found $leaked_count windows owned by dead PID $pre_quit_pid"

leaked_widget_count="$(awk -F'|' -v pid="$pre_quit_pid" '$2 == pid && $4 < 0 {count++} END {print count+0}' "$windowlist_after_quit")"
_qa_manual_assert "no_leaked_widget_after_quit" "$(( leaked_widget_count == 0 ? 0 : 1 ))" "found $leaked_widget_count negative-layer windows owned by dead PID $pre_quit_pid"

# Clean relaunch.
open -a "$(_qa_app_path)" >/dev/null 2>&1 || open "$(_qa_app_path)" >/dev/null 2>&1 || true
_qa_wait_for_process 15 0.5
wait_seconds 3

defaults export dev.ascurse.MacLimitsTracker - > "$(evidence_file defaults-post-relaunch.txt)" 2>/dev/null || true

defaults_pre_normalized="$(evidence_file defaults-pre-quit-normalized.plist)"
defaults_post_normalized="$(evidence_file defaults-post-relaunch-normalized.plist)"
cp -f "$(evidence_file defaults-pre-quit.txt)" "$defaults_pre_normalized"
cp -f "$(evidence_file defaults-post-relaunch.txt)" "$defaults_post_normalized"
for defaults_file in "$defaults_pre_normalized" "$defaults_post_normalized"; do
    plutil -remove 'NSWindow Frame DesktopWidget' "$defaults_file" 2>/dev/null || true
    plutil -remove 'NSWindow Frame com_apple_SwiftUI_Settings_window' "$defaults_file" 2>/dev/null || true
    plutil -remove 'NSWindow Frame main' "$defaults_file" 2>/dev/null || true
done

diff_file="$(evidence_file defaults-diff.txt)"
diff -u "$defaults_pre_normalized" "$defaults_post_normalized" > "$diff_file" 2>&1 || true
if [[ ! -s "$diff_file" ]]; then
    _qa_pass "defaults_preserved_across_relaunch" "defaults export diff is empty"
else
    _qa_fail "defaults_preserved_across_relaunch" "defaults changed across relaunch; see defaults-diff.txt"
fi

if [[ "$widget_enabled" == "1" ]]; then
    wait_seconds 2
    assert_widget_visible true
else
    assert_widget_visible false
fi

assert_single_process
assert_activation_policy regular
assert_no_crash "$(_qa_watermark_path)"

screenshot "relaunch-state"
log_action "quit-relaunch: complete"
