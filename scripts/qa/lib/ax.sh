#!/bin/bash
# scripts/qa/lib/ax.sh
# Accessibility (AX) automation helpers for the MacLimitsTracker GUI.
#
# This file is intended to be SOURCED by scenario scripts. It does NOT use
# `set -e`; each function returns an explicit status and callers decide how to
# proceed.
#
# Prerequisites (provided by the scenario script via lib/common.sh):
#   - EVIDENCE_ROOT and EVIDENCE_DIR are set.
#   - log_action, log_info, evidence_file helpers are available.
#   - The target process name is "MacLimitsTracker".
#
# Design notes:
#   - The menu bar item click is a TOGGLE, not a pure open/close, so every
#     open/close path first checks the actual window state.
#   - AX windows are ordered front-to-back, so `window 1` is the frontmost
#     window (often the main window, not the popup). All searches iterate over
#     ALL windows and filter by subrole/title.
#   - SwiftUI buttons inside the popup have an empty AX name; the visible text
#     lives in child AXStaticText elements, so we locate buttons by AXHelp.
#   - No `activate` is used on screenshot/popup/poll paths; focus theft dismisses
#     the popup by design. `activate` is only used inside the explicit
#     fallbacks of open_main_window and open_settings_window.
#   - All osascript invocations are wrapped with a timeout to avoid hangs
#     (especially `entire contents`).
#   - Bash 3.2 compatible: no associative arrays, mapfile, globstar, or
#     `${var^^}`.

# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

# _run_with_timeout <timeout_secs> <command...>
#   Run <command...> with a wall-clock timeout. If the command does not finish
#   within <timeout_secs> seconds it is killed and 124 is returned.
#   Bash 3.2 compatible (no `timeout` binary, no `wait -n`).
#   Returns the command's exit status on success, 124 on timeout.
_run_with_timeout() {
    local timeout_secs=$1
    shift

    local tmp_in tmp_out tmp_rc
    tmp_in=$(mktemp)
    tmp_out=$(mktemp)
    tmp_rc=$(mktemp)

    # Capture any stdin before backgrounding. In non-interactive shells,
    # bash redirects stdin of background jobs to /dev/null, so we must feed
    # the command explicitly from a temp file.
    cat >"$tmp_in"

    {
        "$@" <"$tmp_in" >"$tmp_out" 2>&1
        printf '%s' "$?" >"$tmp_rc"
    } &
    local pid=$!

    local elapsed=0
    while [ "$elapsed" -lt "$timeout_secs" ]; do
        if ! kill -0 "$pid" 2>/dev/null; then
            break
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    if kill -0 "$pid" 2>/dev/null; then
        kill -9 "$pid" 2>/dev/null
        wait "$pid" 2>/dev/null
        printf '124' >"$tmp_rc"
    else
        wait "$pid" 2>/dev/null
    fi

    cat "$tmp_out"
    local rc
    rc=$(cat "$tmp_rc")
    rm -f "$tmp_in" "$tmp_out" "$tmp_rc"
    return "$rc"
}

# _se <applescript> [<timeout_secs>]
#   Execute an AppleScript block inside System Events process "MacLimitsTracker".
#   Defaults to a 10-second timeout. Prints osascript stdout on success.
#   Logs non-zero osascript exits via log_action.
_se() {
    local script=$1
    local timeout_secs=${2:-10}
    local output rc

    output=$(printf '%s\n' "$script" | _run_with_timeout "$timeout_secs" osascript)
    rc=$?

    if [ "$rc" -ne 0 ]; then
        log_action "osascript failed rc=$rc: ${output:-<no output>}"
    fi

    printf '%s\n' "$output"
    return "$rc"
}

# _poll_until <description> <max_attempts> <sleep_secs> <command...>
#   Repeatedly run <command...> until it returns 0 or <max_attempts> is reached.
#   Sleeps <sleep_secs> between attempts. <description> is not logged here;
#   callers log the retry count themselves.
_poll_until() {
    local max_attempts=$2
    local sleep_secs=$3
    shift 3

    local attempt=1
    while [ "$attempt" -le "$max_attempts" ]; do
        if "$@"; then
            return 0
        fi
        attempt=$((attempt + 1))
        if [ "$attempt" -le "$max_attempts" ]; then
            sleep "$sleep_secs"
        fi
    done
    return 1
}

# _process_exists
#   Returns 0 if a process named "MacLimitsTracker" is running.
_process_exists() {
    local output
    output=$(_se 'tell application "System Events" to return (exists process "MacLimitsTracker")')
    [ "$output" = "true" ]
}

# _process_absent
#   Returns 0 if a process named "MacLimitsTracker" is not running.
_process_absent() {
    local output
    output=$(_se 'tell application "System Events" to return not (exists process "MacLimitsTracker")')
    [ "$output" = "true" ]
}

# _popup_system_dialog_exists
#   Returns 0 if a *popup* window (AXSystemDialog that contains the popup's
#   characteristic buttons such as "Open Settings") exists for the process.
#   The desktop widget also uses AXSystemDialog, so we must distinguish it by
#   the presence of the popup's action buttons. Buttons are nested inside a
#   group in the popup, so we search both direct buttons and group buttons.
_popup_system_dialog_exists() {
    local output
    output=$(_se 'tell application "System Events" to tell process "MacLimitsTracker"
  set found to false
  repeat with w in (get windows)
    try
      if (value of attribute "AXSubrole" of w) is "AXSystemDialog" then
        repeat with btn in (get buttons of w)
          try
            set h to value of attribute "AXHelp" of btn
            if h contains "Open Settings" or h contains "Open Limits Tracker" then
              set found to true
              exit repeat
            end if
          end try
        end repeat
        if not found then
          repeat with g in (get groups of w)
            repeat with btn in (get buttons of g)
              try
                set h to value of attribute "AXHelp" of btn
                if h contains "Open Settings" or h contains "Open Limits Tracker" then
                  set found to true
                  exit repeat
                end if
              end try
            end repeat
            if found then exit repeat
          end repeat
        end if
      end if
    end try
    if found then exit repeat
  end repeat
  return found
end tell')
    [ "$output" = "true" ]
}

# _qa_widget_window_exists
#   Returns 0 if a desktop-widget window (AXSystemDialog that does NOT contain
#   the popup's action buttons) exists for the process. Buttons are checked in
#   direct buttons and in first-level groups.
_qa_widget_window_exists() {
    local output
    output=$(_se 'tell application "System Events" to tell process "MacLimitsTracker"
  set found to false
  repeat with w in (get windows)
    try
      if (value of attribute "AXSubrole" of w) is "AXSystemDialog" then
        set isPopup to false
        repeat with btn in (get buttons of w)
          try
            set h to value of attribute "AXHelp" of btn
            if h contains "Open Settings" or h contains "Open Limits Tracker" then
              set isPopup to true
              exit repeat
            end if
          end try
        end repeat
        if not isPopup then
          repeat with g in (get groups of w)
            repeat with btn in (get buttons of g)
              try
                set h to value of attribute "AXHelp" of btn
                if h contains "Open Settings" or h contains "Open Limits Tracker" then
                  set isPopup to true
                  exit repeat
                end if
              end try
            end repeat
            if isPopup then exit repeat
          end repeat
        end if
        if not isPopup then
          set found to true
          exit repeat
        end if
      end if
    end try
    if found then exit repeat
  end repeat
  return found
end tell')
    [ "$output" = "true" ]
}

# _popup_system_dialog_absent
#   Returns 0 if no AXSystemDialog window exists for the process.
_popup_system_dialog_absent() {
    ! _popup_system_dialog_exists
}

# _click_menu_bar_item
#   Clicks menu bar item 1 of menu bar 2 (the MenuBarExtra toggle).
#   Returns 0 if the click was issued, 1 on osascript failure.
_click_menu_bar_item() {
    _se 'tell application "System Events" to tell process "MacLimitsTracker"
  click menu bar item 1 of menu bar 2
  return true
end tell' >/dev/null
}

# _press_escape
#   Sends the Escape key via System Events (key code 53).
_press_escape() {
    _se 'tell application "System Events" to key code 53' >/dev/null
}

# _press_cmd_key <char>
#   Sends Cmd+<char> via System Events.
_press_cmd_key() {
    local char=$1
    _se "tell application \"System Events\" to keystroke \"$char\" using command down" >/dev/null
}

# _activate_app
#   Activates the MacLimitsTracker application. This is intentionally isolated
#   and only used in the explicit fallbacks of open_main_window and
#   open_settings_window because activating steals focus and dismisses the popup.
_activate_app() {
    _se 'tell application "MacLimitsTracker" to activate' >/dev/null
}

# _window_with_title_exists <title>
#   Returns 0 if the process has a window whose AXTitle exactly matches <title>.
_window_with_title_exists() {
    local title=$1
    local escaped output
    escaped=${title//'"'/'""'}
    output=$(_se "tell application \"System Events\" to tell process \"MacLimitsTracker\"
  set found to false
  repeat with w in (get windows)
    try
      if (value of attribute \"AXTitle\" of w) is \"$escaped\" then
        set found to true
        exit repeat
      end if
    end try
  end repeat
  return found
end tell")
    [ "$output" = "true" ]
}

# _window_with_title_absent <title>
#   Returns 0 if the process has no window whose AXTitle exactly matches <title>.
_window_with_title_absent() {
    ! _window_with_title_exists "$1"
}

# _window_title_contains <substring>
#   Returns 0 if the process has a window whose AXTitle contains <substring>.
_window_title_contains() {
    local substring=$1
    local escaped output
    escaped=${substring//'"'/'""'}
    output=$(_se "tell application \"System Events\" to tell process \"MacLimitsTracker\"
  set found to false
  repeat with w in (get windows)
    try
      if (value of attribute \"AXTitle\" of w) contains \"$escaped\" then
        set found to true
        exit repeat
      end if
    end try
  end repeat
  return found
end tell")
    [ "$output" = "true" ]
}

# _find_first_window_title_containing <substring>
#   Prints the AXTitle of the first window whose title contains <substring>.
#   Prints nothing if no such window exists.
_find_first_window_title_containing() {
    local substring=$1
    local escaped
    escaped=${substring//'"'/'""'}
    _se "tell application \"System Events\" to tell process \"MacLimitsTracker\"
  repeat with w in (get windows)
    try
      set t to value of attribute \"AXTitle\" of w
      if t contains \"$escaped\" then
        return t
      end if
    end try
  end repeat
  return \"\"
end tell"
}

# _find_window_title_matching <regex>
#   Prints the AXTitle of the first window whose title matches the bash regex
#   <regex>. Prints nothing if no match is found.
_find_window_title_matching() {
    local regex=$1
    local titles
    titles=$(_se 'tell application "System Events" to tell process "MacLimitsTracker"
  set out to ""
  repeat with w in (get windows)
    try
      set t to value of attribute "AXTitle" of w
      set out to out & t & "\n"
    end try
  end repeat
  return out
end tell')

    local IFS=$'\n'
    local title
    for title in $titles; do
        if [ -n "$title" ] && [[ "$title" =~ $regex ]]; then
            printf '%s' "$title"
            return 0
        fi
    done
    return 1
}

# _click_button_by_help <help-substring>
#   Finds a button inside an AXSystemDialog (popup) whose AXHelp contains
#   <help-substring> and clicks it. Buttons are nested inside a group, so we
#   search both direct buttons and group buttons. Returns 0 if clicked, 1 if
#   not found.
_click_button_by_help() {
    local substring=$1
    local escaped
    escaped=${substring//'"'/'""'}
    local output
    output=$(_se "tell application \"System Events\" to tell process \"MacLimitsTracker\"
  repeat with w in (get windows)
    try
      if (value of attribute \"AXSubrole\" of w) is \"AXSystemDialog\" then
        repeat with btn in (get buttons of w)
          try
            if (value of attribute \"AXHelp\" of btn) contains \"$escaped\" then
              click btn
              return \"clicked\"
            end if
          end try
        end repeat
        repeat with g in (get groups of w)
          repeat with btn in (get buttons of g)
            try
              if (value of attribute \"AXHelp\" of btn) contains \"$escaped\" then
                click btn
                return \"clicked\"
              end if
            end try
          end repeat
        end repeat
      end if
    end try
  end repeat
  return \"notfound\"
end tell")
    [ "$output" = "clicked" ]
}

# _close_window_by_title <title>
#   Clicks the AXCloseButton of the window whose AXTitle exactly matches <title>.
#   Returns 0 if the click was issued, 1 if the window was not found.
_close_window_by_title() {
    local title=$1
    local escaped output
    escaped=${title//'"'/'""'}
    output=$(_se "tell application \"System Events\" to tell process \"MacLimitsTracker\"
  repeat with w in (get windows)
    try
      if (value of attribute \"AXTitle\" of w) is \"$escaped\" then
        set closeBtn to first button of w whose (value of attribute \"AXSubrole\") is \"AXCloseButton\"
        click closeBtn
        return \"closed\"
      end if
    end try
  end repeat
  return \"notfound\"
end tell")
    [ "$output" = "closed" ]
}

# _make_window_key <title>
#   Sets AXMain=true on the window whose AXTitle exactly matches <title>.
#   Returns 0 if the window was found, 1 otherwise.
_make_window_key() {
    local title=$1
    local escaped output
    escaped=${title//'"'/'""'}
    output=$(_se "tell application \"System Events\" to tell process \"MacLimitsTracker\"
  repeat with w in (get windows)
    try
      if (value of attribute \"AXTitle\" of w) is \"$escaped\" then
        set value of attribute \"AXMain\" of w to true
        return \"madekey\"
      end if
    end try
  end repeat
  return \"notfound\"
end tell")
    [ "$output" = "madekey" ]
}

# _dump_entire_contents_of_window <title> [<timeout_secs>]
#   Prints the entire contents of the window whose AXTitle exactly matches
#   <title>. The default timeout is 4 seconds to guard against hangs.
_dump_entire_contents_of_window() {
    local title=$1
    local timeout_secs=${2:-4}
    local escaped
    escaped=${title//'"'/'""'}
    _se "tell application \"System Events\" to tell process \"MacLimitsTracker\"
  repeat with w in (get windows)
    try
      if (value of attribute \"AXTitle\" of w) is \"$escaped\" then
        return entire contents of w
      end if
    end try
  end repeat
  return \"\"
end tell" "$timeout_secs"
}

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

# popup_open
#   Opens the MacLimitsTracker MenuBarExtra popup if it is not already open.
#   The menu bar item click is a toggle, so the function first checks whether an
#   AXSystemDialog window already exists. If not, it clicks the menu bar item and
#   polls for up to 4 seconds for the popup to appear. The whole click+poll cycle
#   is retried up to 3 times.
#   Args: none
#   Returns: 0 on success, 1 on failure
#   Side effects: may click the menu bar item; logs every attempt and retry count
popup_open() {
    log_action "popup_open: begin"

    if _popup_system_dialog_exists; then
        log_action "popup_open: already open"
        return 0
    fi

    local attempt=1
    local max_attempts=3
    while [ "$attempt" -le "$max_attempts" ]; do
        log_action "popup_open: click attempt $attempt/$max_attempts"
        if _click_menu_bar_item; then
            if _poll_until "popup to appear" 20 0.2 _popup_system_dialog_exists; then
                log_action "popup_open: appeared on attempt $attempt"
                return 0
            fi
        else
            log_action "popup_open: menu bar click failed on attempt $attempt"
        fi
        attempt=$((attempt + 1))
    done

    log_action "popup_open: failed after $max_attempts attempts"
    return 1
}

# popup_is_open
#   Returns 0 if an AXSystemDialog window of process MacLimitsTracker exists.
#   Args: none
#   Returns: 0 if open, 1 if not
#   Side effects: logs the check
popup_is_open() {
    log_action "popup_is_open: checking"
    if _popup_system_dialog_exists; then
        log_action "popup_is_open: yes"
        return 0
    fi
    log_action "popup_is_open: no"
    return 1
}

# popup_close
#   Closes the popup if it is open. Clicks the menu bar item (toggle) and polls
#   for up to 4 seconds for the AXSystemDialog window to disappear. Retries the
#   click+poll up to 2 times. If the click path fails, falls back to sending the
#   Escape key.
#   Args: none
#   Returns: 0 if closed, 1 if still open
#   Side effects: may click the menu bar item or send Escape; logs attempts
popup_close() {
    log_action "popup_close: begin"

    if ! _popup_system_dialog_exists; then
        log_action "popup_close: already closed"
        return 0
    fi

    local attempt=1
    local max_attempts=2
    while [ "$attempt" -le "$max_attempts" ]; do
        log_action "popup_close: click attempt $attempt/$max_attempts"
        if _click_menu_bar_item; then
            if _poll_until "popup to close" 20 0.2 _popup_system_dialog_absent; then
                log_action "popup_close: closed on click attempt $attempt"
                return 0
            fi
        fi
        attempt=$((attempt + 1))
    done

    log_action "popup_close: click attempts exhausted; sending Escape"
    if _press_escape; then
        if _poll_until "popup to close after Escape" 20 0.2 _popup_system_dialog_absent; then
            log_action "popup_close: closed via Escape"
            return 0
        fi
    fi

    log_action "popup_close: failed"
    return 1
}

# popup_click_button <help-substring>
#   Finds a button inside the popup whose AXHelp attribute contains the given
#   substring and performs AXPress on it. SwiftUI buttons in the popup have an
#   empty AX name, so AXHelp is the reliable key. The search spans all windows
#   with subrole AXSystemDialog and retries for up to 4 seconds.
#   Args: help-substring (e.g. "Open Limits Tracker" or "Open Settings")
#   Returns: 0 if the button was found and clicked, 1 otherwise
#   Side effects: performs AXPress on the button; logs attempts
popup_click_button() {
    local help_substring=$1
    log_action "popup_click_button: looking for help='$help_substring'"

    if ! _popup_system_dialog_exists; then
        log_action "popup_click_button: popup is not open"
        return 1
    fi

    local attempt=1
    local max_attempts=20
    while [ "$attempt" -le "$max_attempts" ]; do
        if _click_button_by_help "$help_substring"; then
            log_action "popup_click_button: clicked '$help_substring' on attempt $attempt"
            return 0
        fi
        attempt=$((attempt + 1))
        if [ "$attempt" -le "$max_attempts" ]; then
            sleep 0.2
        fi
    done

    log_action "popup_click_button: button not found after $max_attempts attempts"
    return 1
}

# open_main_window
#   Ensures the "Limits Tracker" main window is present. If it already exists,
#   the function logs and returns 0 (singleton focus semantics). Otherwise it
#   opens the popup, clicks the "Open Limits Tracker" button, and polls for up
#   to 4 seconds. If that path fails, it activates the app and sends Cmd+0.
#   Args: none
#   Returns: 0 if the main window is present, 1 otherwise
#   Side effects: may open popup, click button, activate app, or send keystroke
open_main_window() {
    log_action "open_main_window: begin"

    if _window_with_title_exists "Limits Tracker"; then
        log_action "open_main_window: already present"
        return 0
    fi

    if popup_open; then
        if popup_click_button "Open Limits Tracker"; then
            if _poll_until "main window to appear" 20 0.2 _window_with_title_exists "Limits Tracker"; then
                log_action "open_main_window: opened via popup button"
                return 0
            fi
        fi
    fi

    log_action "open_main_window: button path failed; fallback activate + Cmd-0"
    _activate_app
    _press_cmd_key "0"
    if _poll_until "main window to appear via fallback" 20 0.2 _window_with_title_exists "Limits Tracker"; then
        log_action "open_main_window: opened via fallback"
        return 0
    fi

    log_action "open_main_window: failed"
    return 1
}

# open_settings_window
#   Ensures a Settings window is open. It opens the popup, clicks the
#   "Open Settings" button, and polls for up to 4 seconds. If that path fails,
#   it activates the app and sends Cmd+comma. The observed window title is
#   logged for later exact matching.
#   Args: none
#   Returns: 0 if a Settings window appears, 1 otherwise
#   Side effects: may open popup, click button, activate app, or send keystroke
open_settings_window() {
    log_action "open_settings_window: begin"

    if _window_title_contains "Settings"; then
        local title
        title=$(_find_first_window_title_containing "Settings")
        log_action "open_settings_window: already present (title: $title)"
        return 0
    fi

    if popup_open; then
        if popup_click_button "Open Settings"; then
            if _poll_until "settings window to appear" 20 0.2 _window_title_contains "Settings"; then
                local title
                title=$(_find_first_window_title_containing "Settings")
                log_action "open_settings_window: opened via popup button (title: $title)"
                return 0
            fi
        fi
    fi

    log_action "open_settings_window: button path failed; fallback activate + Cmd-comma"
    _activate_app
    _press_cmd_key ","
    if _poll_until "settings window to appear via fallback" 20 0.2 _window_title_contains "Settings"; then
        local title
        title=$(_find_first_window_title_containing "Settings")
        log_action "open_settings_window: opened via fallback (title: $title)"
        return 0
    fi

    log_action "open_settings_window: failed"
    return 1
}

# close_window <title-regex>
#   Finds a window whose AXTitle matches the bash regex <title-regex> and clicks
#   its close button (the button with subrole AXCloseButton). If the close button
#   path fails, it makes the window key and sends Cmd+W. Polls until the window
#   disappears.
#   Args: title-regex (bash regex, e.g. "Limits Tracker" or ".*Settings.*")
#   Returns: 0 if the window is gone, 1 otherwise
#   Side effects: may click close button, make window key, or send keystroke
close_window() {
    local title_regex=$1
    log_action "close_window: looking for title matching '$title_regex'"

    local title
    title=$(_find_window_title_matching "$title_regex")
    if [ -z "$title" ]; then
        log_action "close_window: no window matched '$title_regex'"
        return 1
    fi
    log_action "close_window: matched window '$title'"

    if _close_window_by_title "$title"; then
        if _poll_until "window to close" 20 0.2 _window_with_title_absent "$title"; then
            log_action "close_window: closed '$title' via close button"
            return 0
        fi
    fi

    log_action "close_window: close button path failed; fallback make key + Cmd-W"
    if _make_window_key "$title"; then
        _press_cmd_key "w"
        if _poll_until "window to close via Cmd-W" 20 0.2 _window_with_title_absent "$title"; then
            log_action "close_window: closed '$title' via Cmd-W"
            return 0
        fi
    fi

    log_action "close_window: failed to close '$title'"
    return 1
}

# quit_app
#   Tells the MacLimitsTracker application to quit and polls for up to 5 seconds
#   until the process disappears.
#   Args: none
#   Returns: 0 if the process exited, 1 if still alive
#   Side effects: sends quit to the application; logs attempts
quit_app() {
    log_action "quit_app: sending quit"

    local output rc
    output=$(_se 'tell application "MacLimitsTracker" to quit')
    rc=$?
    if [ "$rc" -ne 0 ]; then
        log_action "quit_app: quit command failed rc=$rc: ${output:-<no output>}"
    fi

    if _poll_until "process to exit" 10 0.5 _process_absent; then
        log_action "quit_app: process exited"
        return 0
    fi

    log_action "quit_app: process still alive after timeout"
    return 1
}

# screenshot <name>
#   Captures the full screen to <EVIDENCE_DIR>/<name>.png using screencapture.
#   Does NOT activate or focus any application; focus theft would dismiss the
#   popup by design.
#   Args: name (basename without extension)
#   Returns: 0 on success, 1 on screencapture failure
#   Side effects: writes a PNG to the evidence directory
screenshot() {
    local name=$1
    log_action "screenshot: capturing full screen to '$name.png'"

    local path
    path=$(evidence_file "$name.png")
    screencapture -x "$path"
    local rc=$?

    if [ "$rc" -ne 0 ]; then
        log_action "screenshot: screencapture failed rc=$rc"
        return 1
    fi

    log_action "screenshot: saved $path"
    return 0
}

# screenshot_window <window-id> <name>
#   Captures a single window by its window ID (from the windowlist helper,
#   $EVIDENCE_ROOT/bin/windowlist) to <EVIDENCE_DIR>/<name>.png.
#   The helper output format is: windowID|ownerPID|ownerName|layer|title|bounds.
#   Args: window-id, name (basename without extension)
#   Returns: 0 on success, 1 on screencapture failure
#   Side effects: writes a PNG to the evidence directory
screenshot_window() {
    local window_id=$1
    local name=$2
    log_action "screenshot_window: capturing window $window_id to '$name.png'"

    local path
    path=$(evidence_file "$name.png")
    screencapture -x -l"$window_id" "$path"
    local rc=$?

    if [ "$rc" -ne 0 ]; then
        log_action "screenshot_window: screencapture failed rc=$rc"
        return 1
    fi

    log_action "screenshot_window: saved $path"
    return 0
}

# dump_ax_tree <window-title-regex> <name>
#   Dumps the entire AX contents of the first window whose AXTitle matches the
#   bash regex <window-title-regex> to <EVIDENCE_DIR>/<name>.txt. The dump is
#   guarded by a 4-second timeout because entire contents can hang or return a
#   partial tree. If the dump times out or is empty, the partial/empty output is
#   still written and the function returns 1.
#   Args: window-title-regex, name (basename without extension)
#   Returns: 0 on success, 1 on timeout or empty/partial dump
#   Side effects: writes a text file to the evidence directory
dump_ax_tree() {
    local title_regex=$1
    local name=$2
    log_action "dump_ax_tree: dumping window matching '$title_regex' to '$name.txt'"

    local title
    title=$(_find_window_title_matching "$title_regex")
    if [ -z "$title" ]; then
        log_action "dump_ax_tree: no window matched '$title_regex'"
        return 1
    fi
    log_action "dump_ax_tree: matched window '$title'"

    local path
    path=$(evidence_file "$name.txt")

    local output rc
    output=$(_dump_entire_contents_of_window "$title" 4)
    rc=$?

    printf '%s' "$output" >"$path"

    if [ "$rc" -ne 0 ] || [ -z "$output" ]; then
        log_action "dump_ax_tree: timeout/partial/empty dump for '$title' (rc=$rc)"
        return 1
    fi

    log_action "dump_ax_tree: saved $path"
    return 0
}

# wait_seconds <n>
#   Sleeps for <n> seconds and logs the action for action-log readability.
#   Args: n (integer or fractional seconds supported by /bin/sleep)
#   Returns: 0
#   Side effects: sleeps, logs
wait_seconds() {
    local n=$1
    log_action "wait_seconds: sleeping $n"
    sleep "$n"
    log_action "wait_seconds: done"
    return 0
}
