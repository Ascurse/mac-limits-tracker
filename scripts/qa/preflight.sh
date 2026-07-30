#!/usr/bin/env bash
# scripts/qa/preflight.sh — 3ip.8 coexistence QA preflight.
#
# Runs ./make-app.sh, compiles the windowlist helper, checks Accessibility,
# records defaults/crash baselines, and creates a fresh evidence root.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ---------------------------------------------------------------------------
# Build the .app
# ---------------------------------------------------------------------------
echo "[preflight] Building app..."
(
    cd "$ROOT"
    ./make-app.sh
)

# ---------------------------------------------------------------------------
# Prepare evidence root
# ---------------------------------------------------------------------------
TIMESTAMP="$(date -u +%Y%m%d-%H%M%S)"
EVIDENCE_ROOT="/tmp/qa-3ip8/run-${TIMESTAMP}"
mkdir -p "$EVIDENCE_ROOT/bin"
export EVIDENCE_ROOT

# Write the latest pointer.
mkdir -p /tmp/qa-3ip8
echo "$EVIDENCE_ROOT" > /tmp/qa-3ip8/latest

# ---------------------------------------------------------------------------
# Compile windowlist helper
# ---------------------------------------------------------------------------
echo "[preflight] Compiling windowlist helper..."
swiftc -O -o "${EVIDENCE_ROOT}/bin/windowlist" "${SCRIPT_DIR}/lib/windowlist.swift"

# ---------------------------------------------------------------------------
# Accessibility permission check
# ---------------------------------------------------------------------------
echo "[preflight] Checking Accessibility permission for calling terminal..."
if osascript -e 'tell application "System Events" to tell process "Finder" to return count of windows' >/dev/null 2>&1; then
    echo "[preflight] Accessibility permission OK."
else
    echo "[preflight] ERROR: Accessibility permission missing for this terminal."
    echo ""
    echo "To fix:"
    echo "  1. Open System Settings → Privacy & Security → Accessibility"
    echo "  2. Add and enable your terminal application (e.g. Terminal, iTerm2, Cursor, Code)."
    echo "  3. Re-run this preflight."
    echo ""
    exit 1
fi

# ---------------------------------------------------------------------------
# Record defaults baseline
# ---------------------------------------------------------------------------
echo "[preflight] Recording defaults baseline..."
defaults export dev.ascurse.MacLimitsTracker - > "${EVIDENCE_ROOT}/defaults-baseline.txt" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Crash-report watermark
# ---------------------------------------------------------------------------
echo "[preflight] Recording crash-report watermark..."
WATERMARK="/tmp/qa-3ip8/crash-watermark"
touch "$WATERMARK"
# Also place a reference in the evidence root so scenarios can find it.
ln -sf "$WATERMARK" "${EVIDENCE_ROOT}/crash-watermark"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "[preflight] Done. Evidence root: $EVIDENCE_ROOT"
