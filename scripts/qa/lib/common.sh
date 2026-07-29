#!/usr/bin/env bash
# scripts/qa/lib/common.sh — shared helpers for the 3ip.8 coexistence QA harness.
#
# SHARED CONTRACT (must match lib/ax.sh built by the parallel agent):
#   EVIDENCE_ROOT  -> /tmp/qa-3ip8/run-<timestamp>/
#   EVIDENCE_DIR   -> $EVIDENCE_ROOT/<scenario-name>/
#
# This file is SOURCED by scenario scripts and libs; it does NOT set -e.
# Bash 3.2 compatible: no associative arrays, mapfile, ${var^^}, or globstar.

# Ensure required evidence directories exist. Callers may rely on these dirs.
_ensure_evidence_dir() {
    if [[ -n "${EVIDENCE_DIR:-}" ]]; then
        mkdir -p "$EVIDENCE_DIR"
    fi
}

# log_action "msg" -> appends [ISO8601] msg to $EVIDENCE_DIR/actions.log
log_action() {
    local msg="$1"
    _ensure_evidence_dir
    local ts
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '[%s] %s\n' "$ts" "$msg" >> "${EVIDENCE_DIR}/actions.log"
}

# log_info "msg" -> stdout + actions.log
log_info() {
    local msg="$1"
    echo "$msg"
    log_action "$msg"
}

# classify_prompt <class> <detail> -> appends [ISO8601] <class> <scenario> <detail>
# to $EVIDENCE_ROOT/prompts.log. Classes: keychain-acl, notification-permission,
# accessibility-permission.
classify_prompt() {
    local class="$1"
    shift
    local detail="$*"
    local scenario="${QA_SCENARIO_NAME:-unknown}"
    local root="${EVIDENCE_ROOT:-}"
    if [[ -z "$root" ]]; then
        return 0
    fi
    mkdir -p "$root"
    local ts
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '[%s] %s %s %s\n' "$ts" "$class" "$scenario" "$detail" >> "$root/prompts.log"
}

# evidence_file <name> -> echoes $EVIDENCE_DIR/<name>
evidence_file() {
    local name="$1"
    _ensure_evidence_dir
    echo "${EVIDENCE_DIR}/${name}"
}

# app_pid -> echoes pid of running MacLimitsTracker (empty if none).
# Prefers an exact process-name match; falls back to bundle identifier lookup.
app_pid() {
    local pid
    pid="$(pgrep -x MacLimitsTracker 2>/dev/null | head -n 1 || true)"
    if [[ -n "$pid" ]]; then
        echo "$pid"
        return 0
    fi
    # Fallback via lsappinfo for the bundled app.
    pid="$(lsappinfo info "dev.ascurse.MacLimitsTracker" 2>/dev/null \
        | sed -nE 's/.*pid *= *([0-9]+).*/\1/p' | head -n 1 || true)"
    echo "$pid"
}

# _qa_iso8601 -> current UTC timestamp for internal use.
_qa_iso8601() {
    date -u +%Y-%m-%dT%H:%M:%SZ
}
