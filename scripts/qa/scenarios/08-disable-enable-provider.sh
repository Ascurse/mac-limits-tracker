#!/usr/bin/env bash
# scripts/qa/scenarios/08-disable-enable-provider.sh
#
# EXPECTED RESULTS:
# - A provider can be disabled via the Settings UI; its id appears exactly once
#   in providerSettings.disabledIds.
# - After a refresh cycle, the disabled provider is absent from the popup and the
#   main window.
# - Re-enabling the same provider brings it back without duplicate rows.
# - A refresh is recorded during the re-enable phase.

source "${SCRIPT_DIR}/lib/ax.sh"
source "${SCRIPT_DIR}/scenarios/_common.sh"

_qa_launch_clean
open_settings_window

# Discover the provider settings structure before toggling.
dump_ax_tree ".*Settings.*" "ax-settings-providers"

# Prefer Kimi; fall back to Claude or Codex if Kimi is not available in UI.
provider_name="Kimi"
provider_id="kimi"
if ! _qa_toggle_provider_in_settings "$provider_name"; then
    log_action "disable-enable: Kimi toggle failed, falling back to Claude"
    provider_name="Claude"
    provider_id="claude"
    if ! _qa_toggle_provider_in_settings "$provider_name"; then
        log_action "disable-enable: Claude toggle failed, falling back to Codex"
        provider_name="Codex"
        provider_id="codex"
        if ! _qa_toggle_provider_in_settings "$provider_name"; then
            _qa_fail "toggle_provider" "could not toggle any provider row in Settings"
        fi
    fi
fi

log_action "disable-enable: disabled provider $provider_name (id=$provider_id)"
wait_seconds 12

display_name="$(_qa_provider_display_name "$provider_id")"

# Defaults: disabled id appears exactly once.
disabled_count="$(_qa_count_defaults_disabled "$provider_id")"
_qa_manual_assert "disabled_id_exactly_once" "$(( disabled_count == 1 ? 0 : 1 ))" "expected provider id '$provider_id' exactly once in disabledIds, found $disabled_count"

# Popup should no longer contain the provider.
popup_open
_qa_dump_popup_contents_to_evidence "ax-popup-disabled"
popup_close
popup_disabled_count="$(grep -c "$display_name" "$(evidence_file ax-popup-disabled.txt)" 2>/dev/null || true)"
_qa_manual_assert "provider_absent_from_popup" "$(( popup_disabled_count == 0 ? 0 : 1 ))" "$display_name found $popup_disabled_count times in popup after disable (expected 0)"

# Main window should no longer contain the provider.
open_main_window
dump_ax_tree "^Limits Tracker$" "ax-main-after-disable"
close_window "^Limits Tracker$"
main_disabled_count="$(grep -c "$display_name" "$(evidence_file ax-main-after-disable.txt)" 2>/dev/null || true)"
_qa_manual_assert "provider_absent_from_main" "$(( main_disabled_count == 0 ? 0 : 1 ))" "$display_name found $main_disabled_count times in main window after disable (expected 0)"

# Widget check: only if the user has it enabled. Toggling one provider must not
# destroy the panel; the borderless NSPanel has no AX title, so visibility is
# the only reachable check from here.
widget_enabled="$(defaults read dev.ascurse.MacLimitsTracker showDesktopWidget 2>/dev/null || echo 0)"
if [[ "$widget_enabled" == "1" ]]; then
    assert_widget_visible true
else
    log_action "disable-enable: widget check skipped because showDesktopWidget is off"
fi

screenshot "provider-disabled"

# Re-enable the same provider.
open_settings_window
if _qa_toggle_provider_in_settings "$provider_name"; then
    log_action "disable-enable: re-enabled provider $provider_name"
else
    _qa_fail "re_enable_provider" "could not re-enable provider $provider_name"
fi

# Record a fresh baseline just before waiting for the post-re-enable refresh.
history_file="${HOME}/Library/Application Support/dev.ascurse.MacLimitsTracker/history.json"
reenable_baseline="$(evidence_file history-mtime-reenable-baseline.txt)"
printf '%s\n' "$(stat -f %m "$history_file" 2>/dev/null || echo 0)" > "$reenable_baseline"

wait_seconds 12
if ! _qa_wait_for_refresh "$reenable_baseline" 10 2; then
    log_action "disable-enable: no additional refresh detected within 20s after re-enable; continuing with UI checks"
fi
assert_refresh_happened "$reenable_baseline"

disabled_count_after="$(_qa_count_defaults_disabled "$provider_id")"
_qa_manual_assert "disabled_id_cleared" "$(( disabled_count_after == 0 ? 0 : 1 ))" "expected 0 disabled ids containing '$provider_id' after re-enable, found $disabled_count_after"

# Popup should show the provider again, exactly once.
popup_open
_qa_dump_popup_contents_to_evidence "ax-popup-reenabled"
popup_close
popup_enabled_count="$(grep -c "$display_name" "$(evidence_file ax-popup-reenabled.txt)" 2>/dev/null || true)"
_qa_manual_assert "provider_present_in_popup_after_reenable" "$(( popup_enabled_count == 1 ? 0 : 1 ))" "$display_name found $popup_enabled_count times in popup after re-enable (expected 1)"

# Main window should show the provider again, exactly once.
open_main_window
dump_ax_tree "^Limits Tracker$" "ax-main-reenabled"
close_window "^Limits Tracker$"
main_enabled_count="$(grep -c "$display_name" "$(evidence_file ax-main-reenabled.txt)" 2>/dev/null || true)"
_qa_manual_assert "provider_present_in_main_after_reenable" "$(( main_enabled_count == 1 ? 0 : 1 ))" "$display_name found $main_enabled_count times in main window after re-enable (expected 1)"

# Settings dump in the re-enabled state for duplicate checks.
open_settings_window
dump_ax_tree ".*Settings.*" "ax-settings-reenabled"
close_window ".*Settings.*"
settings_enabled_count="$(grep -c "$display_name" "$(evidence_file ax-settings-reenabled.txt)" 2>/dev/null || true)"
_qa_manual_assert "provider_no_duplicate_rows_settings" "$(( settings_enabled_count == 1 ? 0 : 1 ))" "$display_name found $settings_enabled_count times in Settings after re-enable (expected 1)"

screenshot "provider-reenabled"
assert_single_process
log_action "disable-enable: complete"
