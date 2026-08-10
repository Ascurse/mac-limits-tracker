# scripts/qa/scenarios/11-trend-visual-consistency.sh
# gld.5 — cross-theme trend, toggle and accessibility gate.
source "${SCRIPT_DIR}/lib/ax.sh"
source "${SCRIPT_DIR}/scenarios/_common.sh"

APP_BUNDLE="${SCRIPT_DIR}/../../dist/MacLimitsTracker.app"
CRASH_WATERMARK="${CRASH_WATERMARK:-/tmp/qa-3ip8/crash-watermark}"

_qa_normalize_bool() {
    case "$1" in
        1|true|yes) echo "true" ;;
        0|false|no) echo "false" ;;
        *) echo "$1" ;;
    esac
}

_qa_main_window_id() {
    _qa_app_windows | awk -F'|' '$5 ~ /^Limits Tracker$/ {print $1; exit}'
}

_qa_resize_main_window() {
    local width="$1"
    local height="$2"
    osascript -e "tell application \"System Events\" to tell process \"MacLimitsTracker\"
  set size of first window whose (value of attribute \"AXTitle\") is \"Limits Tracker\" to {$width, $height}
end tell" >/dev/null 2>&1
}

_qa_toggle_usage_trends() {
    local output
    output="$(_se 'tell application "System Events" to tell process "MacLimitsTracker"
  try
    set settingsWin to first window whose (value of attribute "AXTitle") contains "Settings"
    set toggle to checkbox 1 of group 1 of scroll area 1 of group 1 of settingsWin
    click toggle
    return "toggled"
  on error errMsg
    return "error: " & errMsg
  end try
end tell' 10)"
    [[ "$output" == "toggled" ]]
}

_qa_dump_trend_ax_attributes() {
    _se 'tell application "System Events" to tell process "MacLimitsTracker"
  try
    set targetWindow to first window whose (value of attribute "AXTitle") is "Limits Tracker"
    repeat with itemRef in entire contents of targetWindow
      try
        set labelText to value of attribute "AXDescription" of itemRef
        set valueText to value of attribute "AXValue" of itemRef
        if labelText contains "usage trend" then
          return labelText & " | " & valueText
        end if
      end try
    end repeat
  end try
  return ""
end tell' 10
}

_qa_run_theme() {
    local theme="$1"
    local main_id

    defaults write dev.ascurse.MacLimitsTracker appTheme -string "$theme"
    defaults write dev.ascurse.MacLimitsTracker showUsageTrends -bool true
    _qa_launch_clean || _qa_fail "${theme}_launch" "app did not launch"
    if ! open_main_window; then
        _qa_fail "${theme}_main_window" "main window did not open"
        quit_app || true
        return
    fi
    _qa_pass "${theme}_main_window" "main window opened"

    main_id="$(_qa_main_window_id)"
    if [[ -n "$main_id" ]]; then
        screenshot_window "$main_id" "${theme}-standard" || _qa_fail "${theme}_standard_screenshot" "screenshot failed"
        _qa_resize_main_window 1100 760 || _qa_fail "${theme}_wide_resize" "wide resize failed"
        wait_seconds 1
        screenshot_window "$main_id" "${theme}-wide" || _qa_fail "${theme}_wide_screenshot" "screenshot failed"
    else
        _qa_fail "${theme}_main_window_id" "main window id unavailable"
    fi

    wait_seconds 2
    if dump_ax_tree '^Limits Tracker$' "${theme}-enabled-ax"; then
        trend_attributes="$(_qa_dump_trend_ax_attributes)"
        printf '%s\n' "$trend_attributes" > "$(evidence_file "${theme}-trend-ax-attributes.txt")"
        if [[ "$trend_attributes" == *"usage trend"* && "$trend_attributes" == *"remaining"* && "$trend_attributes" == *"7d"* ]]; then
            _qa_pass "${theme}_trend_ax_attributes" "trend AX label/value exposes metric, value and range"
        else
            _qa_fail "${theme}_trend_ax_attributes" "trend AX label/value unavailable: ${trend_attributes:-<empty>}"
        fi
    else
        _qa_fail "${theme}_trend_ax_dump" "could not dump main window AX tree"
    fi

    if open_settings_window && _qa_toggle_usage_trends; then
        assert_default showUsageTrends false
        close_window '.*Settings.*' || true
        wait_seconds 1
        main_id="$(_qa_main_window_id)"
        if [[ -n "$main_id" ]]; then
            screenshot_window "$main_id" "${theme}-hidden" || _qa_fail "${theme}_hidden_screenshot" "screenshot failed"
        fi
        defaults write dev.ascurse.MacLimitsTracker showUsageTrends -bool true
        _qa_pass "${theme}_toggle_round_trip" "trend toggle disabled and restored"
    else
        _qa_fail "${theme}_toggle_round_trip" "could not open Settings or toggle trends"
    fi

    assert_no_crash "$CRASH_WATERMARK"
    quit_app || true
}

log_action "S11: begin trend visual consistency scenario"

previous_theme="$(defaults read dev.ascurse.MacLimitsTracker appTheme 2>/dev/null || true)"
previous_trends="$(defaults read dev.ascurse.MacLimitsTracker showUsageTrends 2>/dev/null || true)"

for theme in system terminal phosphor tui; do
    _qa_run_theme "$theme"
done

# Prove the persisted hidden state survives a fresh process, then restore it.
defaults write dev.ascurse.MacLimitsTracker showUsageTrends -bool false
_qa_launch_clean || _qa_fail "hidden_relaunch_launch" "app did not relaunch"
if open_main_window; then
    dump_ax_tree '^Limits Tracker$' hidden-relaunch-ax || true
    if grep -Eiq 'usage trend' "$(evidence_file hidden-relaunch-ax.txt)"; then
        _qa_fail "hidden_relaunch" "trend remains exposed after persisted disable"
    else
        _qa_pass "hidden_relaunch" "trend remains hidden after relaunch"
    fi
else
    _qa_fail "hidden_relaunch_main_window" "main window did not open"
fi
quit_app || true

if [[ -n "$previous_theme" ]]; then
    defaults write dev.ascurse.MacLimitsTracker appTheme -string "$previous_theme"
else
    defaults delete dev.ascurse.MacLimitsTracker appTheme || true
fi
if [[ -n "$previous_trends" ]]; then
    defaults write dev.ascurse.MacLimitsTracker showUsageTrends -bool "$(_qa_normalize_bool "$previous_trends")"
else
    defaults delete dev.ascurse.MacLimitsTracker showUsageTrends || true
fi

assert_no_crash "$CRASH_WATERMARK"
