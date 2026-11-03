#!/usr/bin/env bash
# Runs the GUT suite headless, then a short headless boot of the main scene.
# Exits non-zero if any test fails or any script/parse error is logged.
# Usage: tools/run_tests.sh [--no-smoke] [extra GUT args, e.g. -gselect=test_economy.gd]
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-$(command -v godot || echo "$HOME/.local/bin/godot")}"
[[ -x "$GODOT" ]] || { echo "run_tests: Godot not found. Run tools/install_godot.sh or set GODOT=/path/to/godot" >&2; exit 2; }

SMOKE=1
if [[ "${1:-}" == "--no-smoke" ]]; then SMOKE=0; shift; fi

LOG_DIR="$(mktemp -d)"
trap 'rm -rf "$LOG_DIR"' EXIT
# Lines that mean broken code even if GUT still reports passing tests.
FATAL_PATTERN='SCRIPT ERROR|Parse Error|Failed to load script|Failed loading resource|Cannot (open|call) |Invalid (call|get|set|access)'

# 1) Import so class_name caches and .uid files exist in a fresh checkout.
"$GODOT" --headless --path "$ROOT" --import >"$LOG_DIR/import.log" 2>&1
if grep -E "$FATAL_PATTERN" "$LOG_DIR/import.log"; then
  echo "run_tests: errors during import (see above)" >&2; exit 1
fi

# 2) GUT.
echo "run_tests: running GUT"
"$GODOT" --headless --path "$ROOT" -s res://addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json "$@" 2>&1 | tee "$LOG_DIR/gut.log"
GUT_STATUS=${PIPESTATUS[0]}
if [[ $GUT_STATUS -ne 0 ]]; then
  echo "run_tests: GUT FAILED (exit $GUT_STATUS)" >&2; exit 1
fi
if grep -qE "$FATAL_PATTERN" "$LOG_DIR/gut.log"; then
  echo "run_tests: script errors in GUT log:" >&2; grep -E "$FATAL_PATTERN" "$LOG_DIR/gut.log" >&2; exit 1
fi

# 3) Smoke: boot the main scene for 120 frames with Steam absent. --dev-unlock-all keeps the
#    real save file out of it (never read or written) and loads every cheat.
if [[ $SMOKE -eq 1 ]]; then
  echo "run_tests: smoke-booting main scene"
  "$GODOT" --headless --path "$ROOT" --quit-after 120 -- --dev-unlock-all >"$LOG_DIR/smoke.log" 2>&1
  SMOKE_STATUS=$?
  cat "$LOG_DIR/smoke.log"
  if [[ $SMOKE_STATUS -ne 0 ]] || grep -qE "$FATAL_PATTERN|^ERROR:" "$LOG_DIR/smoke.log"; then
    echo "run_tests: smoke boot FAILED" >&2; exit 1
  fi
  if [[ "$(grep -c '\[SteamService\] backend:' "$LOG_DIR/smoke.log")" -ne 1 ]]; then
    echo "run_tests: expected exactly one SteamService backend log line" >&2; exit 1
  fi
fi

echo "run_tests: ALL PASSED"
