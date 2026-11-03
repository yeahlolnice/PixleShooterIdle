#!/usr/bin/env bash
# Downloads the pinned Godot 4 Linux editor (usable headless) and export templates.
# Usage: tools/install_godot.sh [--no-templates]
# Installs into $GODOT_HOME (default: ~/.local/godot) and symlinks ~/.local/bin/godot.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/tools/godot_version.txt")"   # e.g. 4.7.2-stable
GODOT_HOME="${GODOT_HOME:-$HOME/.local/godot}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
BASE_URL="https://github.com/godotengine/godot/releases/download/${VERSION}"
EDITOR_ZIP="Godot_v${VERSION}_linux.x86_64.zip"
TEMPLATES_TPZ="Godot_v${VERSION}_export_templates.tpz"
# Templates live in ~/.local/share/godot/export_templates/<version with '-' -> '.'>
TEMPLATE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/${VERSION/-/.}"

WITH_TEMPLATES=1
[[ "${1:-}" == "--no-templates" ]] && WITH_TEMPLATES=0

need() { command -v "$1" >/dev/null 2>&1 || { echo "install_godot: missing '$1'" >&2; exit 1; }; }
need curl
# Extract a zip with unzip, or Python's zipfile when unzip is absent (fresh containers).
extract() {
  if command -v unzip >/dev/null 2>&1; then unzip -q -o "$1" -d "$2"
  else need python3; python3 -I -m zipfile -e "$1" "$2"; fi
}

mkdir -p "$GODOT_HOME" "$BIN_DIR"
EDITOR_BIN="$GODOT_HOME/Godot_v${VERSION}_linux.x86_64"

if [[ ! -x "$EDITOR_BIN" ]]; then
  echo "install_godot: downloading $EDITOR_ZIP"
  TMP="$(mktemp -d)"
  curl -fsSL --retry 3 -o "$TMP/editor.zip" "$BASE_URL/$EDITOR_ZIP"
  extract "$TMP/editor.zip" "$GODOT_HOME"
  chmod +x "$EDITOR_BIN"
  rm -rf "$TMP"
else
  echo "install_godot: editor $VERSION already present"
fi
ln -sf "$EDITOR_BIN" "$BIN_DIR/godot"

if [[ $WITH_TEMPLATES -eq 1 ]]; then
  if [[ ! -f "$TEMPLATE_DIR/linux_release.x86_64" ]]; then
    echo "install_godot: downloading $TEMPLATES_TPZ (~1 GB)"
    TMP="$(mktemp -d)"
    curl -fsSL --retry 3 -o "$TMP/templates.tpz" "$BASE_URL/$TEMPLATES_TPZ"
    mkdir -p "$TEMPLATE_DIR"
    extract "$TMP/templates.tpz" "$TMP/t"
    cp -r "$TMP/t/templates/." "$TEMPLATE_DIR/"
    rm -rf "$TMP"
  else
    echo "install_godot: export templates $VERSION already present"
  fi
fi

"$BIN_DIR/godot" --headless --version
echo "install_godot: done. Binary: $BIN_DIR/godot (add $BIN_DIR to PATH, or set GODOT=$BIN_DIR/godot)"
