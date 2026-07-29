# scripts/qa/scenarios/05-widget-first.sh
# 3ip.8 coexistence QA — first-surface: desktop widget.
#
# Expected results:
#   - App launches from clean state with showDesktopWidget seeded true.
#   - The desktop widget appears (assert_widget_visible true) without opening a surface.
#   - The frontmost application remains unchanged, proving the widget is a non-activating panel.
#   - The showDesktopWidget default remains true after launch.
#   - Opening Settings and toggling the Desktop widget switch OFF makes the widget
#     disappear and updates the default to false.
#   - The original showDesktopWidget default is restored at scenario end.
#   - No crash.
# Leaves the app quit.
source "${SCRIPT_DIR}/lib/ax.sh"

APP_BUNDLE="${SCRIPT_DIR}/../../dist/MacLimitsTracker.app"
CRASH_WATERMARK="${CRASH_WATERMARK:-/tmp/qa-3ip8/crash-watermark}"

# Find the Desktop widget switch/checkbox in the Settings window and toggle it OFF.
# We locate the static text "Desktop widget" and click the first checkbox in the
# same group, matching the provider-row pattern used in _qa_toggle_provider_in_settings.
_qa_s05_toggle_desktop_widget_off() {
    local output=""

    log_action "S05: toggling Desktop widget switch OFF in Settings window"
    output=$(osascript -e 'tell application "System Events"
  tell process "MacLimitsTracker"
    try
      set settingsWin to first window whose (value of attribute "AXTitle") contains "Settings"
      set targetText to first static text of settingsWin whose value contains "Desktop widget"
      set rowGroup to parent of targetText
      try
        set toggle to first checkbox of rowGroup
        click toggle
        return "toggled"
      end try
      try
        set toggle to first button of rowGroup whose (value of attribute "AXSubrole") is "AXToggle"
        click toggle
        return "toggled"
      end try
      try
        set toggle to first button of rowGroup
        click toggle
        return "toggled"
      end try
      return "noswitch"
    on error errMsg
      return "error: " & errMsg
    end try
  end tell
end tell' 2>/dev/null || true)

    if [[ "$output" == "toggled" ]]; then
        log_action "S05: toggled Desktop widget switch OFF"
        return 0
    fi

    log_action "S05: could not toggle Desktop widget switch OFF (output=$output)"
    return 1
}

log_action "S05: begin widget-first scenario"

# Clean state.
if [[ -n "$(app_pid 2>/dev/null || true)" ]]; then
    log_action "S05: app already running, quitting"
    quit_app || true
fi
_poll_until "process absent before launch" 20 0.5 _process_absent || true

# Capture frontmost app before launch.
frontmost_before=""
frontmost_before=$(osascript -e 'tell application "System Events" to name of first application process whose frontmost is true' 2>/dev/null || true)
log_action "S05: frontmost app before launch: '${frontmost_before:-<unknown>}'"

# Snapshot previous widget default.
previous_widget_default=""
previous_widget_default=$(defaults read dev.ascurse.MacLimitsTracker showDesktopWidget 2>/dev/null || true)
log_action "S05: previous showDesktopWidget default: '${previous_widget_default:-<missing>}'"

# Seed Desktop widget on.
defaults write dev.ascurse.MacLimitsTracker showDesktopWidget -bool true || true

# Launch.
open -a "$APP_BUNDLE" || true
if ! _poll_until "process to appear" 10 1 _process_exists; then
    log_action "S05: error: process did not appear within 10 s"
fi
wait_seconds 3

# Widget should appear without any surface opened.
assert_widget_visible true

# Frontmost app must not have changed.
frontmost_after=""
frontmost_after=$(osascript -e 'tell application "System Events" to name of first application process whose frontmost is true' 2>/dev/null || true)
log_action "S05: frontmost app after widget appears: '${frontmost_after:-<unknown>}'"

if [[ -n "$frontmost_before" && "$frontmost_before" == "$frontmost_after" ]]; then
    _qa_pass "frontmost_unchanged" "frontmost app remained '$frontmost_before'"
else
    _qa_fail "frontmost_unchanged" "frontmost changed from '$frontmost_before' to '$frontmost_after'"
fi

assert_default showDesktopWidget true

# Evidence.
_qa_app_windows > "$(evidence_file windowlist.txt)" 2>&1 || true
screenshot "widget-visible" || true

# Open Settings and toggle the Desktop widget switch off.
if open_settings_window; then
    if _qa_s05_toggle_desktop_widget_off; then
        wait_seconds 1
        assert_widget_visible false
        assert_default showDesktopWidget false
    else
        log_action "S05: could not toggle Desktop widget off"
        _qa_fail "toggle_desktop_widget_off" "toggle helper did not succeed"
    fi
else
    log_action "S05: open_settings_window failed"
    _qa_fail "open_settings_window" "could not open settings"
fi

# Restore the original default. defaults write -bool only accepts true/false/yes/no,
# not 1/0, so we normalise the previously-read value before writing.
_qa_s05_normalize_bool() {
    case "$1" in
        1|true|yes) echo "true" ;;
        0|false|no) echo "false" ;;
        *) echo "$1" ;;
    esac
}

if [[ -n "$previous_widget_default" ]]; then
    restored_value="$(_qa_s05_normalize_bool "$previous_widget_default")"
    defaults write dev.ascurse.MacLimitsTracker showDesktopWidget -bool "$restored_value" || true
    log_action "S05: restored showDesktopWidget to $previous_widget_default (as $restored_value)"
else
    defaults delete dev.ascurse.MacLimitsTracker showDesktopWidget || true
    log_action "S05: deleted showDesktopWidget key (was missing before scenario)"
fi

# Crash check.
assert_no_crash "$CRASH_WATERMARK"

# Documented end state.
quit_app || true
