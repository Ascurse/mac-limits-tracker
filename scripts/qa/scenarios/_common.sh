#!/usr/bin/env bash
# scripts/qa/scenarios/_common.sh — shared helpers for S06–S10 scenario scripts.
#
# Sourced by each scenario script after lib/ax.sh. Uses helpers already defined
# by the harness (lib/common.sh, lib/assert.sh, lib/ax.sh).
#
# Bash 3.2 compatible.

# Path to the built .app bundle.
_qa_app_path() {
    if [[ -n "${ROOT:-}" ]]; then
        echo "${ROOT}/dist/MacLimitsTracker.app"
    else
        echo "$(cd "${SCRIPT_DIR}/../.." && pwd)/dist/MacLimitsTracker.app"
    fi
}

# Wait for the MacLimitsTracker process to appear.
_qa_wait_for_process() {
    local max_attempts=$1
    local sleep_secs=$2
    local attempt=1
    while [ "$attempt" -le "$max_attempts" ]; do
        if _process_exists; then
            return 0
        fi
        sleep "$sleep_secs"
        attempt=$((attempt + 1))
    done
    return 1
}

# Wait for the MacLimitsTracker process to disappear.
_qa_wait_for_process_exit() {
    local max_attempts=$1
    local sleep_secs=$2
    local attempt=1
    while [ "$attempt" -le "$max_attempts" ]; do
        if _process_absent; then
            return 0
        fi
        sleep "$sleep_secs"
        attempt=$((attempt + 1))
    done
    return 1
}

# Ensure a clean start: quit any running instance, then launch the bundled app.
_qa_launch_clean() {
    log_action "launch_clean: begin"
    local app_path
    app_path="$(_qa_app_path)"

    if _process_exists; then
        log_action "launch_clean: app already running, quitting"
        quit_app || true
        if ! _qa_wait_for_process_exit 10 0.5; then
            log_action "launch_clean: quit timed out, killing leftover"
            killall -TERM MacLimitsTracker 2>/dev/null || true
            sleep 1
            killall -9 MacLimitsTracker 2>/dev/null || true
            _qa_wait_for_process_exit 5 0.5 || true
        fi
    fi

    log_action "launch_clean: opening $app_path"
    # Primary launch method requested by the spec. open -a with a path may
    # fail on some macOS versions; fall back to plain open of the bundle.
    if open -a "$app_path" >/dev/null 2>&1; then
        log_action "launch_clean: open -a succeeded"
    else
        log_action "launch_clean: open -a failed, falling back to open"
        open "$app_path" >/dev/null 2>&1 || true
    fi

    _qa_wait_for_process 15 0.5
    log_action "launch_clean: process up"
}

# Manual assert that uses the same PASS/FAIL logging and fail counter as the
# harness assert primitives. condition: 0 = PASS, non-zero = FAIL.
_qa_manual_assert() {
    local name="$1"
    local condition="$2"
    local detail="$3"
    if [[ "$condition" == "0" ]]; then
        _qa_pass "$name" "$detail"
    else
        _qa_fail "$name" "$detail"
    fi
}

# Count app-owned windows whose title matches the given regex.
_qa_count_window_matches() {
    local regex="$1"
    local count
    count="$(_qa_app_windows | awk -F'|' -v re="$regex" '$5 ~ re {count++} END {print count+0}')"
    printf '%s\n' "$count"
}

# Save the current app-owned windowlist to an evidence file.
_qa_record_windows() {
    local name="$1"
    local path
    path="$(evidence_file "$name")"
    _qa_app_windows > "$path"
    log_action "recorded app windows to $name"
}

# Poll until history.json mtime advances past the baseline file.
_qa_wait_for_refresh() {
    local baseline_file="$1"
    local max_attempts="${2:-60}"
    local sleep_secs="${3:-2}"
    local history
    history="${HOME}/Library/Application Support/dev.ascurse.MacLimitsTracker/history.json"
    local attempt=1
    local baseline
    baseline="$(cat "$baseline_file" 2>/dev/null || echo 0)"
    while [ "$attempt" -le "$max_attempts" ]; do
        local current
        current="$(stat -f %m "$history" 2>/dev/null || echo 0)"
        if [[ -n "$current" && -n "$baseline" && "$current" -gt "$baseline" ]]; then
            log_action "refresh detected: $baseline -> $current"
            return 0
        fi
        sleep "$sleep_secs"
        attempt=$((attempt + 1))
    done
    return 1
}

# Crash-report watermark used by assert_no_crash.
_qa_watermark_path() {
    echo "/tmp/qa-3ip8/crash-watermark"
}

_qa_ensure_watermark() {
    local path
    path="$(_qa_watermark_path)"
    mkdir -p "$(dirname "$path")"
    if [[ ! -f "$path" ]]; then
        touch "$path"
    fi
}

# Dump the entire AX contents of the popup window (the AXSystemDialog that
# contains the popup's action buttons) to stdout. Buttons are nested inside a
# group, so we check both direct buttons and group buttons.
_qa_popup_contents() {
    _se 'tell application "System Events" to tell process "MacLimitsTracker"
  repeat with w in (get windows)
    try
      if (value of attribute "AXSubrole" of w) is "AXSystemDialog" then
        repeat with btn in (get buttons of w)
          try
            set h to value of attribute "AXHelp" of btn
            if h contains "Open Settings" or h contains "Open Limits Tracker" then
              return entire contents of w
            end if
          end try
        end repeat
        repeat with g in (get groups of w)
          repeat with btn in (get buttons of g)
            try
              set h to value of attribute "AXHelp" of btn
              if h contains "Open Settings" or h contains "Open Limits Tracker" then
                return entire contents of w
              end if
            end try
          end repeat
        end repeat
      end if
    end try
  end repeat
  return ""
end tell' 4
}

# Save the popup AX contents to an evidence file.
_qa_dump_popup_contents_to_evidence() {
    local name="$1"
    local path
    path="$(evidence_file "${name}.txt")"
    local output
    output="$(_qa_popup_contents)"
    printf '%s' "$output" > "$path"
    if [[ -n "$output" ]]; then
        log_action "dumped popup contents to ${name}.txt"
    else
        log_action "popup contents dump was empty/timed out"
    fi
}

# Return the menu-bar title string (if accessible).
_qa_menu_bar_title() {
    _se 'tell application "System Events" to tell process "MacLimitsTracker"
  try
    set t to title of menu bar item 1 of menu bar 2
    return t
  on error
    return ""
  end try
end tell' 5
}

# Return true if the app owns a menu-bar extra item.
_qa_menu_bar_item_present() {
    local output
    output="$(_se 'tell application "System Events" to tell process "MacLimitsTracker"
  try
    return (count of menu bar items of menu bar 2) > 0
  on error
    return false
  end try
end tell' 5)"
    [[ "$output" == "true" ]]
}

# Toggle the first matching provider row in the Settings window.
# Searches for a static text containing the provider name, then clicks the first
# checkbox in the same row. Returns 0 on success.
_qa_toggle_provider_in_settings() {
    local provider="$1"
    local provider_id
    local provider_index
    local output
    case "$provider" in
        "Kimi Code") provider_id="kimi" ;;
        Claude) provider_id="claude" ;;
        Codex) provider_id="codex" ;;
        *) provider_id="$provider" ;;
    esac
    provider_index="$(defaults read dev.ascurse.MacLimitsTracker 'providerSettings.order' 2>/dev/null | awk -v id="$provider_id" '$1 == id "," || $1 == id { print NR - 1; exit }')"
    [[ -n "$provider_index" ]] || provider_index=1
    output="$(_se "tell application \"System Events\" to tell process \"MacLimitsTracker\"
  repeat with attempt from 1 to 10
    try
      set settingsWin to first window whose (value of attribute \"AXTitle\") contains \"Settings\"
      set targetToggle to checkbox $provider_index of group 3 of scroll area 1 of group 1 of settingsWin
      click targetToggle
      return \"toggled\"
    end try
    delay 0.3
  end repeat
  try
    set settingsWin to first window whose (value of attribute \"AXTitle\") contains \"Settings\"
    try
      set targetToggle to first UI element of entire contents of settingsWin whose (value of attribute \"AXIdentifier\") is \"provider-toggle-$provider_id\"
      click targetToggle
      return \"toggled\"
    end try
    set targetText to first static text of settingsWin whose value contains \"$provider\"
    set rowGroup to parent of targetText
    try
      set toggle to first checkbox of rowGroup
      click toggle
      return \"toggled\"
    end try
    try
      set toggle to first button of rowGroup whose (value of attribute \"AXSubrole\") is \"AXToggle\"
      click toggle
      return \"toggled\"
    end try
    try
      set toggle to first button of rowGroup
      click toggle
      return \"toggled\"
    end try
    return \"noswitch\"
  on error errMsg
    return \"error: \" & errMsg
  end try
end tell" 10)"
    printf '%s\n' "$output"
    [[ "$output" == "toggled" ]]
}

# Count how many times a provider id appears in providerSettings.disabledIds.
_qa_count_defaults_disabled() {
    local provider_id="$1"
    local output
    output="$(defaults read dev.ascurse.MacLimitsTracker providerSettings.disabledIds 2>/dev/null || true)"
    if [[ -z "$output" ]]; then
        echo 0
        return
    fi
    printf '%s\n' "$output" | grep -c "$provider_id" || true
}

# Map provider id to the display name used in the popup/main window.
_qa_provider_display_name() {
    case "$1" in
        kimi) echo "Kimi Code" ;;
        claude) echo "Claude Code" ;;
        codex) echo "Codex" ;;
        *) echo "$1" ;;
    esac
}
