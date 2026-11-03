#!/usr/bin/env bash
# Headless export. Usage: tools/export.sh linux|windows|all [--debug]
# Output: build/<platform>/ (see export_presets.cfg). Needs export templates
# from tools/install_godot.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-$(command -v godot || echo "$HOME/.local/bin/godot")}"
[[ -x "$GODOT" ]] || { echo "export: Godot not found. Run tools/install_godot.sh or set GODOT=..." >&2; exit 2; }

TARGET="${1:-}"
MODE="--export-release"
[[ "${2:-}" == "--debug" ]] && MODE="--export-debug"

export_one() {
  local preset="$1" out="$2"
  mkdir -p "$ROOT/$(dirname "$out")"
  echo "export: $preset -> $out ($MODE)"
  local log; log="$(mktemp)"
  "$GODOT" --headless --path "$ROOT" "$MODE" "$preset" "$ROOT/$out" 2>&1 | tee "$log"
  local status=${PIPESTATUS[0]}
  if [[ $status -ne 0 || ! -f "$ROOT/$out" ]] || grep -qE "SCRIPT ERROR|Parse Error|No export template found" "$log"; then
    rm -f "$log"; echo "export: $preset FAILED" >&2; return 1
  fi
  rm -f "$log"
  echo "export: $preset OK -> $ROOT/$out"
}

# Fresh checkouts need an import pass first (class_name cache, .uid files).
[[ -d "$ROOT/.godot" ]] || "$GODOT" --headless --path "$ROOT" --import >/dev/null 2>&1 || true

case "$TARGET" in
  linux)   export_one "Linux" "build/linux/CheatCodeIdle.x86_64" ;;
  windows) export_one "Windows" "build/windows/CheatCodeIdle.exe" ;;
  all)     export_one "Linux" "build/linux/CheatCodeIdle.x86_64"
           export_one "Windows" "build/windows/CheatCodeIdle.exe" ;;
  *) echo "usage: tools/export.sh linux|windows|all [--debug]" >&2; exit 2 ;;
esac
