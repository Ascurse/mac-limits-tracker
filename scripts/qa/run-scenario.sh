#!/usr/bin/env bash
# scripts/qa/run-scenario.sh <scenario-name> [script-path]
# Driver for a single 3ip.8 coexistence QA scenario.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <scenario-name> [script-path]" >&2
    exit 2
fi

SCENARIO_NAME="$1"
SCENARIO_SCRIPT="${2:-}"

if [[ -z "${EVIDENCE_ROOT:-}" ]]; then
    echo "Error: EVIDENCE_ROOT is not set. Run preflight.sh first." >&2
    exit 1
fi

export EVIDENCE_DIR="${EVIDENCE_ROOT}/${SCENARIO_NAME}"
export QA_SCENARIO_NAME="$SCENARIO_NAME"
mkdir -p "$EVIDENCE_DIR"

# Ensure compiled windowlist helper is available.
export BIN_DIR="${EVIDENCE_ROOT}/bin"
mkdir -p "$BIN_DIR"
if [[ ! -x "${BIN_DIR}/windowlist" ]]; then
    swiftc -O -o "${BIN_DIR}/windowlist" "${SCRIPT_DIR}/lib/windowlist.swift"
fi

# Source shared libs so scenario scripts get helpers and assert primitives.
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/assert.sh"

log_info "Starting scenario: $SCENARIO_NAME"

# Snapshot defaults before the scenario.
defaults export dev.ascurse.MacLimitsTracker - > "${EVIDENCE_DIR}/defaults-before.txt" 2>/dev/null || true

# Record history.json mtime baseline.
HISTORY_PATH="${HOME}/Library/Application Support/dev.ascurse.MacLimitsTracker/history.json"
if [[ -f "$HISTORY_PATH" ]]; then
    stat -f %m "$HISTORY_PATH" > "${EVIDENCE_DIR}/history-mtime-baseline.txt"
else
    echo "0" > "${EVIDENCE_DIR}/history-mtime-baseline.txt"
fi

# Initialize fail counter.
printf '0\n' > "${EVIDENCE_DIR}/.failcount"

# Run the scenario script if provided.
if [[ -n "$SCENARIO_SCRIPT" ]]; then
    if [[ ! -f "$SCENARIO_SCRIPT" ]]; then
        echo "FAIL: scenario script not found: $SCENARIO_SCRIPT" | tee -a "${EVIDENCE_DIR}/assert.log"
        printf '1\n' > "${EVIDENCE_DIR}/.failcount"
    else
        log_action "Sourcing scenario script: $SCENARIO_SCRIPT"
        # A failed scenario ACTION (e.g. AX retry budget exhausted) must not
        # abort the driver: failures belong in assert.log/.failcount, and
        # defaults-after.txt + VERDICT must always be written. Suspend -e/-u
        # while sourcing, restore right after.
        set +eu
        # shellcheck source=/dev/null
        source "$SCENARIO_SCRIPT"
        set -eu
    fi
fi

# Snapshot defaults after the scenario.
defaults export dev.ascurse.MacLimitsTracker - > "${EVIDENCE_DIR}/defaults-after.txt" 2>/dev/null || true

# Write verdict based on fail counter.
FAILCOUNT="$(cat "${EVIDENCE_DIR}/.failcount" 2>/dev/null || echo 0)"
if [[ "$FAILCOUNT" == "0" ]]; then
    VERDICT="PASS"
else
    VERDICT="FAIL"
fi
printf '%s\n' "$VERDICT" > "${EVIDENCE_DIR}/VERDICT"
log_info "Verdict for $SCENARIO_NAME: $VERDICT (failcount=$FAILCOUNT)"
