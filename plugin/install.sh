#!/usr/bin/env bash
#
# Installs the skill-toggle plugin for opencode 2.x (Linux / macOS).
#
#   curl -fsSL https://raw.githubusercontent.com/BenReynor/opencode-skill-toggle/main/plugin/install.sh | bash
#
# Downloads skill-toggle-tui.js from the "latest" release, verifies it against
# SHA256SUMS.scripts and copies it to $XDG_CONFIG_HOME/opencode/plugins/skill-toggle/
# (default ~/.config/opencode/...). Nothing else is touched: not the opencode
# binary and not your sessions. Restart opencode afterwards (a running TUI
# usually picks it up by itself).
#
#   --uninstall   remove the plugin
#   TOGGLE_USE_LOCAL=1 ./plugin/install.sh   install the copy from this checkout
set -euo pipefail

GH_REPO="${GH_REPO:-BenReynor/opencode-skill-toggle}"
BASE="https://github.com/$GH_REPO/releases/download/latest"
DEST_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/plugins/skill-toggle"
DEST="$DEST_DIR/tui.js"

if [[ "${1:-}" == "--uninstall" ]]; then
  rm -rf "$DEST_DIR"
  echo ">> skill-toggle plugin removed ($DEST_DIR). Restart opencode."
  exit 0
fi

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [[ "${TOGGLE_USE_LOCAL:-0}" == "1" ]]; then
  SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/skill-toggle/tui.js"
  [[ -f "$SRC" ]] || { echo ">> ERROR: $SRC not found" >&2; exit 1; }
  cp "$SRC" "$TMP/tui.js"
  echo ">> Using local copy (not verified): $SRC"
else
  curl -fsSL --proto =https --tlsv1.2 "$BASE/SHA256SUMS.scripts" -o "$TMP/sums"
  curl -fsSL --proto =https --tlsv1.2 "$BASE/skill-toggle-tui.js" -o "$TMP/tui.js"
  EXPECTED="$(awk '$2=="skill-toggle-tui.js" || $2=="./skill-toggle-tui.js" {print $1; exit}' "$TMP/sums")"
  [[ -n "$EXPECTED" ]] || { echo ">> ERROR: no checksum for skill-toggle-tui.js in the release" >&2; exit 1; }
  [[ "$(sha256_of "$TMP/tui.js")" == "$EXPECTED" ]] || { echo ">> ERROR: SHA256 mismatch; nothing installed" >&2; exit 1; }
  echo ">> Downloaded and verified skill-toggle-tui.js (SHA256 $EXPECTED)"
fi

mkdir -p "$DEST_DIR"
cp "$TMP/tui.js" "$DEST_DIR/.tui.js.tmp"
mv -f "$DEST_DIR/.tui.js.tmp" "$DEST"
echo ">> Installed: $DEST"
echo ">> Restart opencode, open a session and type /skill-toggle"
