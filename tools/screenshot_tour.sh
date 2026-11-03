#!/usr/bin/env bash
# Windowed screenshot tour (TASK-018): boots the game with --dev-unlock-all state,
# walks through menus, every cheat, a live round, noclip, pause and the summary,
# and writes PNGs to build/screens/ (or --out=DIR). Never touches the real save.
# Needs a display; on headless Linux run it under xvfb-run.
# Usage: tools/screenshot_tour.sh [--out=/abs/dir]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-$(command -v godot || echo "$HOME/.local/bin/godot")}"
[[ -x "$GODOT" ]] || { echo "screenshot_tour: Godot not found. Set GODOT=/path/to/godot" >&2; exit 2; }

LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT
"$GODOT" --path "$ROOT" res://tools/screenshot_tour.tscn -- "$@" 2>&1 | tee "$LOG"
if grep -qE "SCRIPT ERROR|^ERROR:" "$LOG"; then
  echo "screenshot_tour: engine errors during the tour (see above)" >&2; exit 1
fi
