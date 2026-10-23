#!/usr/bin/env bash
#
# Removes the skill-toggle install: the anti-overwrite guard, the helper
# scripts, the toggle state and the patched binary.
#
# Usage:
#   toggle-uninstall.sh                 # restore official opencode (asks first)
#   toggle-uninstall.sh --yes           # no questions (used by the TUI command)
#   toggle-uninstall.sh --purge         # delete the opencode binary instead
#   toggle-uninstall.sh --from-backup   # offline: use ~/.opencode/bin/opencode.bak
#
# Conversation data (opencode.db), settings and snapshots are always kept.
set -euo pipefail

ASSUME_YES=0
PURGE=0
FROM_BACKUP=0
for arg in "$@"; do
  case "$arg" in
    --yes | -y) ASSUME_YES=1 ;;
    --purge) PURGE=1 ;;
    --from-backup) FROM_BACKUP=1 ;;
    -h | --help)
      sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      exit 2
      ;;
  esac
done

OC_DIR="$HOME/.opencode"
BIN_DIR="$OC_DIR/bin"
BIN="$BIN_DIR/opencode"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}/opencode"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/opencode"
LOG="$STATE/toggle-uninstall.log"
SYSTEMD_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
LAUNCHD_PLIST="$HOME/Library/LaunchAgents/com.opencode.skill-toggle-guard.plist"

# The TUI launches this detached with stdio ignored, so keep a log there.
if [[ "$ASSUME_YES" == 1 ]]; then
  mkdir -p "$STATE"
  exec >>"$LOG" 2>&1
  printf '\n=== %s uninstall (purge=%s) ===\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$PURGE"
fi

say() { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }

installed=0
[[ -e "$BIN" ]] && installed=1
[[ -f "$OC_DIR/toggle-guard.sh" ]] && installed=1
[[ -f "$OC_DIR/.toggle-guard-tag" ]] && installed=1
[[ -f "$OC_DIR/toggle-uninstall.sh" ]] && installed=1
if [[ "$installed" == 0 ]]; then
  say "skill-toggle is not installed."
  exit 0
fi

say "This will remove the skill-toggle install:"
say "  - anti-overwrite guard (systemd/launchd)"
say "  - helper scripts in $OC_DIR"
say "  - toggle state $DATA/skills-toggle.json"
if [[ "$PURGE" == 1 ]]; then
  say "  - opencode binary $BIN (deleted)"
else
  say "  - opencode binary $BIN (replaced by the official build)"
fi
say "Your conversations, settings and snapshots are kept."
say

if [[ "$ASSUME_YES" != 1 ]]; then
  read -r -p "Continue? [y/N] " reply
  if [[ ! "$reply" =~ ^[Yy]([Ee][Ss])?$ ]]; then
    say "Cancelled."
    exit 1
  fi
fi

# --- Stop and remove the guard before touching the binary -------------------
if [[ "$(uname -s)" == "Linux" ]] && command -v systemctl >/dev/null 2>&1; then
  systemctl --user disable --now opencode-toggle-guard.path opencode-toggle-guard.timer >/dev/null 2>&1 || true
  systemctl --user stop opencode-toggle-guard.service >/dev/null 2>&1 || true
  rm -f "$SYSTEMD_DIR/opencode-toggle-guard.path" \
    "$SYSTEMD_DIR/opencode-toggle-guard.service" \
    "$SYSTEMD_DIR/opencode-toggle-guard.timer"
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  say ">> guard stopped (systemd)"
elif [[ "$(uname -s)" == "Darwin" ]]; then
  launchctl unload -w "$LAUNCHD_PLIST" >/dev/null 2>&1 || true
  rm -f "$LAUNCHD_PLIST"
  say ">> guard stopped (launchd)"
fi

# --- Helper functions -------------------------------------------------------
fetch() {
  local url="$1" dest="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --proto =https --tlsv1.2 "$url" -o "$dest"
  elif command -v wget >/dev/null 2>&1; then
    wget -q --https-only "$url" -O "$dest"
  else
    warn "neither curl nor wget is available"
    return 1
  fi
}

install_binary() {
  local src="$1" tmp="$BIN.new.$$"
  mkdir -p "$BIN_DIR"
  cp "$src" "$tmp"
  chmod 755 "$tmp"
  mv -f "$tmp" "$BIN"
}

detect_platform() {
  local os arch base libc=""
  os="$(uname -s)"
  arch="$(uname -m)"
  case "$os" in
    Linux)
      if ls /lib/ld-musl-*.so.1 >/dev/null 2>&1 || ldd --version 2>&1 | grep -qi musl; then
        libc="-musl"
      fi
      case "$arch" in
        x86_64 | amd64)
          if grep -qw avx2 /proc/cpuinfo 2>/dev/null; then
            base="linux-x64"
          else
            base="linux-x64-baseline"
          fi
          ;;
        aarch64 | arm64) base="linux-arm64" ;;
        *) return 1 ;;
      esac
      printf '%s%s\n' "$base" "$libc"
      ;;
    Darwin)
      case "$arch" in
        arm64) printf 'darwin-arm64\n' ;;
        x86_64) printf 'darwin-x64\n' ;;
        *) return 1 ;;
      esac
      ;;
    *) return 1 ;;
  esac
}

download_official() {
  local platform asset url tmp found
  platform="$(detect_platform)" || {
    warn "unsupported platform: $(uname -s) $(uname -m)"
    return 1
  }
  case "$platform" in
    linux-*) asset="opencode-$platform.tar.gz" ;;
    darwin-*) asset="opencode-$platform.zip" ;;
    *) return 1 ;;
  esac
  url="https://github.com/anomalyco/opencode/releases/latest/download/$asset"
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/opencode-restore.XXXXXX")"

  say ">> downloading official opencode ($platform)"
  if ! fetch "$url" "$tmp/$asset"; then
    warn "could not download $url"
    rm -rf "$tmp"
    return 1
  fi

  case "$asset" in
    *.tar.gz) tar -xzf "$tmp/$asset" -C "$tmp" || true ;;
    *.zip)
      if command -v unzip >/dev/null 2>&1; then
        unzip -oq "$tmp/$asset" -d "$tmp" || true
      else
        ditto -x -k "$tmp/$asset" "$tmp" || true
      fi
      ;;
  esac

  found="$tmp/opencode"
  [[ -f "$found" ]] || found="$(find "$tmp" -type f -name opencode 2>/dev/null | head -n1)"
  if [[ -z "$found" || ! -f "$found" ]]; then
    warn "official archive did not contain an opencode binary"
    rm -rf "$tmp"
    return 1
  fi
  if ! "$found" --version >/dev/null 2>&1; then
    warn "the downloaded binary does not run on this machine"
    rm -rf "$tmp"
    return 1
  fi

  install_binary "$found"
  rm -rf "$tmp"
  return 0
}

# --- Restore or delete the binary ------------------------------------------
KEEP_BIN=0
if [[ "$PURGE" == 1 ]]; then
  rm -f "$BIN" "$BIN.bak" "$BIN.sha256"
  say ">> removed $BIN"
elif [[ "$FROM_BACKUP" == 1 && -f "$BIN.bak" ]]; then
  install_binary "$BIN.bak"
  rm -f "$BIN.bak"
  say ">> restored $BIN from the local backup (unverified)"
elif download_official; then
  rm -f "$BIN.bak"
  say ">> official opencode installed"
else
  KEEP_BIN=1
  warn "the official binary could not be restored; the current binary was left in place"
  warn "install opencode with: curl -fsSL https://opencode.ai/install | bash"
fi

# --- Remove guard state, helper scripts and toggle state --------------------
rm -f "$OC_DIR/.toggle-guard-tag" "$OC_DIR/.toggle-guard-sums" "$BIN.sha256"
rm -f "$OC_DIR/toggle-guard.sh" "$OC_DIR/toggle-cleanup.sh"
rm -f "$OC_DIR/toggle-guard.log" "$OC_DIR/toggle-cleanup.log"
rm -f "$DATA/skills-toggle.json" 2>/dev/null || true
rm -f "$DATA"/skills-toggle.json.*.tmp 2>/dev/null || true
say ">> removed guard files and toggle state"

if [[ "$PURGE" == 1 ]]; then
  rm -f "$BIN_DIR/opencode2"
  if [[ "$KEEP_BIN" == 0 ]]; then
    rmdir "$BIN_DIR" 2>/dev/null || true
  fi
elif [[ "$KEEP_BIN" == 0 ]]; then
  rm -f "$BIN_DIR/opencode2"
fi

rm -f "$OC_DIR/toggle-uninstall.sh"
say ">> done. Open a new terminal (or restart your shell) to use opencode again."
