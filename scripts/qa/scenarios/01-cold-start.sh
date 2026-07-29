# scripts/qa/scenarios/01-cold-start.sh
# 3ip.8 coexistence QA — first-surface: cold start (no surface opened).
#
# Expected results:
#   - App launches from clean state and exactly one MacLimitsTracker process runs.
#   - Activation policy is regular (bundled .app = persistent regular).
#   - Neither a "Limits Tracker" main window nor a "Settings" window is present.
#   - Desktop widget visibility matches the persisted showDesktopWidget default.
#   - First refresh advances history.json mtime within ~30 s.
#   - A keychain SecurityAgent "Always Allow" dialog, if shown, is handled once and
#     classified as a keychain-acl prompt.
#   - No crash report newer than the watermark is produced.
# Leaves the app quit.
source "${SCRIPT_DIR}/lib/ax.sh"

APP_BUNDLE="${SCRIPT_DIR}/../../dist/MacLimitsTracker.app"
CRASH_WATERMARK="${CRASH_WATERMARK:-/tmp/qa-3ip8/crash-watermark}"
BASELINE="${EVIDENCE_DIR}/history-mtime-baseline.txt"
HISTORY_PATH="${HOME}/Library/Application Support/dev.ascurse.MacLimitsTracker/history.json"

# Poll up to 30 s for history.json mtime to advance past the baseline.
_qa_s01_poll_refresh() {
    local baseline_file="$1"
    local baseline=""
    local current=""
    local i

    if [[ ! -f "$baseline_file" ]]; then
        log_action "S01: refresh baseline missing: $baseline_file"
        return 1
    fi

    baseline=$(cat "$baseline_file" 2>/dev/null || true)
    [[ -n "$baseline" ]] || baseline="0"

    for ((i=1; i<=30; i++)); do
        if [[ -f "$HISTORY_PATH" ]]; then
            current=$(stat -f %m "$HISTORY_PATH" 2>/dev/null || true)
            if [[ -n "$current" && "$current" -gt "$baseline" ]]; then
                log_action "S01: refresh advanced history mtime after ${i}s ($baseline -> $current)"
                return 0
            fi
        fi
        wait_seconds 1
    done

    log_action "S01: refresh did not advance history mtime within 30 s"
    return 1
}

# Poll up to 8 s for a SecurityAgent window with an "Always Allow" button.
_qa_s01_security_agent_present_poll() {
    local output=""
    local i

    for ((i=1; i<=16; i++)); do
        output=$(osascript -e 'tell application "System Events"
  set found to false
  repeat with p in (get processes)
    if name of p is "SecurityAgent" then
      repeat with w in (get windows of p)
        try
          repeat with btn in (get buttons of w)
            if name of btn is "Always Allow" then
              set found to true
              exit repeat
            end if
          end repeat
        end try
        if found then exit repeat
      end repeat
    end if
    if found then exit repeat
  end repeat
  return found
end tell' 2>/dev/null || true)
        if [[ "$output" == "true" ]]; then
            log_action "S01: SecurityAgent 'Always Allow' dialog found after ${i} checks"
            return 0
        fi
        wait_seconds 0.5
    done
    return 1
}

# Click "Always Allow" once in a SecurityAgent dialog.
_qa_s01_click_always_allow() {
    local output=""

    output=$(osascript -e 'tell application "System Events"
  tell process "SecurityAgent"
    set clickedIt to false
    repeat with w in (get windows)
      try
        repeat with btn in (get buttons of w)
          if name of btn is "Always Allow" then
            click btn
            set clickedIt to true
            exit repeat
          end if
        end repeat
      end try
      if clickedIt then exit repeat
    end repeat
    return clickedIt
  end tell
end tell' 2>/dev/null || true)

    if [[ "$output" == "true" ]]; then
        log_action "S01: clicked SecurityAgent 'Always Allow' once"
    else
        log_action "S01: SecurityAgent dialog found but click did not succeed"
    fi
}

log_action "S01: begin cold-start scenario"

# Clean state.
if [[ -n "$(app_pid 2>/dev/null || true)" ]]; then
    log_action "S01: app already running, quitting"
    quit_app || true
fi
if ! _poll_until "process absent before launch" 20 0.5 _process_absent; then
    log_action "S01: warning: process still present after quit attempt"
fi

# Capture lsappinfo absence before launch.
lsappinfo info "dev.ascurse.MacLimitsTracker" > "$(evidence_file lsappinfo-before.txt)" 2>&1 || true

# Read persisted widget default before launch.
local_widget_default=""
local_widget_default=$(defaults read dev.ascurse.MacLimitsTracker showDesktopWidget 2>/dev/null || true)
if [[ "$local_widget_default" == "1" ]]; then
    expected_widget="true"
else
    expected_widget="false"
fi
log_action "S01: showDesktopWidget default = '${local_widget_default:-<missing>}', expecting widget visible=$expected_widget"

# Launch.
log_action "S01: launching $APP_BUNDLE"
open -a "$APP_BUNDLE" || true

# Poll up to 10 s for the process.
if ! _poll_until "process to appear" 10 1 _process_exists; then
    log_action "S01: error: process did not appear within 10 s"
fi
wait_seconds 1

# Core asserts.
assert_single_process
assert_activation_policy regular
assert_window_absent "^Limits Tracker$"
assert_window_absent "Settings"
assert_widget_visible "$expected_widget"

# Evidence: windowlist + lsappinfo.
_qa_app_windows > "$(evidence_file windows.txt)" 2>&1 || true
lsappinfo info "dev.ascurse.MacLimitsTracker" > "$(evidence_file lsappinfo.txt)" 2>&1 || true

# Poll for first refresh, then assert it.
if ! _qa_s01_poll_refresh "$BASELINE"; then
    log_action "S01: first refresh did not advance within 30 s"
fi
assert_refresh_happened "$BASELINE"

# Keychain ACL dialog: handle once if shown.
if _qa_s01_security_agent_present_poll; then
    _qa_s01_click_always_allow
    classify_prompt keychain-acl "first refresh on fresh ad-hoc build"
else
    classify_prompt keychain-acl "not shown (previously allowed or no credential read)"
fi

# Crash check.
assert_no_crash "$CRASH_WATERMARK"

# Screenshot.
screenshot "cold-start" || true

# Documented end state.
quit_app || true
