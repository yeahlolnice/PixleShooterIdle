#!/usr/bin/env bash
# Compiles res://shaders/*.gdshader under Forward+ and Compatibility by rendering
# a few frames with each (uses xvfb-run when no display). Fails on shader errors
# or when the requested renderer could not start (e.g. no Vulkan -> fallback).
# Without a GPU, Forward+ needs a software Vulkan ICD (mesa lavapipe): set
# VK_ICD_FILENAMES=/path/to/lvp_icd.x86_64.json.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-$(command -v godot || echo "$HOME/.local/bin/godot")}"
RUN=()
[[ -z "${DISPLAY:-}" ]] && RUN=(xvfb-run -a)
STATUS=0
for method in forward_plus gl_compatibility; do
  LOG="$("${RUN[@]}" "$GODOT" --path "$ROOT" --rendering-method "$method" -s res://tools/check_shaders.gd 2>&1)"
  echo "$LOG" | grep -E "check_shaders|SHADER ERROR|ERROR" 
  if echo "$LOG" | grep -qE "SHADER ERROR|LOAD FAILED|shader.*(error|fail)"; then
    echo "check_shaders: $method FAILED" >&2; STATUS=1
  elif ! echo "$LOG" | grep -q "renderer: $method"; then
    echo "check_shaders: $method did not start (no GPU/driver?)" >&2; STATUS=1
  else
    echo "check_shaders: $method OK"
  fi
done
exit $STATUS
