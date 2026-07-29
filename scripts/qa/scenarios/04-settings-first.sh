# scripts/qa/scenarios/04-settings-first.sh
# 3ip.8 coexistence QA — first-surface: Settings window.
#
# Expected results:
#   - App launches from clean state and the Settings window is opened as the first surface.
#   - A window whose title contains "Settings" is present (actual title recorded).
#   - The "Limits Tracker" main window is absent.
#   - Activation policy is regular.
#   - The AX tree dump of the Settings window contains the sections:
#       Theme, Refresh, Providers, Desktop widget.
#     (The Settings UI groups display options under Theme/Menu bar, refresh
#     options under Refresh every, provider toggles under Providers, and system
#     options under Desktop widget/Notifications/Launch at login.)
#   - No crash.
# Leaves the app quit.
source "${SCRIPT_DIR}/lib/ax.sh"

APP_BUNDLE="${SCRIPT_DIR}/../../dist/MacLimitsTracker.app"
CRASH_WATERMARK="${CRASH_WATERMARK:-/tmp/qa-3ip8/crash-watermark}"

log_action "S04: begin settings-first scenario"

# Clean state.
if [[ -n "$(app_pid 2>/dev/null || true)" ]]; then
    log_action "S04: app already running, quitting"
    quit_app || true
fi
_poll_until "process absent before launch" 20 0.5 _process_absent || true

# Launch.
open -a "$APP_BUNDLE" || true
if ! _poll_until "process to appear" 10 1 _process_exists; then
    log_action "S04: error: process did not appear within 10 s"
fi
wait_seconds 1

# First surface: Settings window.
if open_settings_window; then
    _qa_pass "open_settings_window" "settings window opened as first surface"
else
    _qa_fail "open_settings_window" "settings window failed to open"
fi

# Record actual title for the report.
settings_title=$(_find_first_window_title_containing "Settings" 2>/dev/null || true)
log_action "S04: actual Settings window title: '${settings_title:-<none>}'"

assert_window_present ".*Settings.*"
assert_window_absent "^Limits Tracker$"
assert_activation_policy regular

# Dump AX tree and assert the four sections.
if dump_ax_tree ".*Settings.*" ax-tree-settings; then
    ax_file="$(evidence_file ax-tree-settings.txt)"
    for section in Theme Refresh Providers "Desktop widget"; do
        if grep -q "$section" "$ax_file"; then
            _qa_pass "settings_section_${section}" "section '$section' found in AX tree"
        else
            _qa_fail "settings_section_${section}" "section '$section' not found in AX tree"
        fi
    done
else
    log_action "S04: AX tree dump failed, skipping section checks"
    for section in Display Refresh Providers System; do
        _qa_fail "settings_section_${section}" "AX tree dump unavailable"
    done
fi

# Evidence screenshot.
screenshot "settings-window" || true

# Crash check.
assert_no_crash "$CRASH_WATERMARK"

# Documented end state.
quit_app || true
