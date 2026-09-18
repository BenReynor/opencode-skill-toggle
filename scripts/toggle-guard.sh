#!/usr/bin/env bash
#
# toggle-guard.sh — Guard for skill-toggle.
#
# If the opencode binary was replaced (by the official autoupdate, by
# "opencode upgrade" or by any other means), reinstalls the skill-toggle build
# in the background, downloading it from the newest versioned release (one tag
# per build) and verifying the SHA256 against SHA256SUMS.
#
# Call it periodically (systemd .path/.timer, cron, launchd, Task Scheduler…):
#   bash toggle-guard.sh
#
# How it decides whether to reinstall:
#   - "$BIN.sha256" stores the hash of the last installed toggle binary.
#   - If the current hash of "$BIN" matches the marked one, it does nothing.
#   - If it differs, it downloads and reinstalls the toggle.
#   - If the marker does not exist, it does nothing: it never hijacks a binary
#     this project did not install.
#
# Optional variables:
#   GH_REPO=[user/repo]      repository to download from (default BenReynor/opencode-skill-toggle)
#   TOGGLE_GUARD_BIN=[path]  binary to watch (default $HOME/.opencode/bin/opencode)
#   TOGGLE_GUARD_LOG=[path]  log file (default $HOME/.opencode/toggle-guard.log)
set -euo pipefail

GH_REPO="${GH_REPO:-BenReynor/opencode-skill-toggle}"
BIN="${TOGGLE_GUARD_BIN:-$HOME/.opencode/bin/opencode}"
MARKER="$BIN.sha256"
LOG="${TOGGLE_GUARD_LOG:-$HOME/.opencode/toggle-guard.log}"
LOCK="/tmp/opencode-toggle-guard.lock"
TAG_CACHE="$HOME/.opencode/.toggle-guard-tag"

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"; }

# --- Resolve the newest versioned release (with a 6-hour cache) ---------------
# Each build is published to a unique tag (toggle-X.Y.Z or toggle-X.Y.Z-r<build>):
# its content never changes, so the download never mixes old binaries from the
# CDN (unlike "latest", which is overwritten on every build).
resolve_release_base() {
  if [[ -f "$TAG_CACHE" ]] && find "$TAG_CACHE" -mmin -360 >/dev/null 2>&1; then
    local cached
    cached="$(cat "$TAG_CACHE")"
    [[ -n "$cached" ]] && { echo "https://github.com/$GH_REPO/releases/download/$cached"; return; }
  fi
  local tags t
  tags="$(curl -fsSL --proto =https --tlsv1.2 \
    "https://api.github.com/repos/$GH_REPO/releases?per_page=30" 2>/dev/null || true)"
  t="$(printf '%s\n' "$tags" | grep -oE '"tag_name": ?"[^"]+"' | sed -E 's/.*": ?"([^"]+)".*/\1/' | grep '^toggle-' | head -n1)"
  if [[ -n "$t" ]]; then
    mkdir -p "$(dirname "$TAG_CACHE")"
    printf '%s\n' "$t" > "$TAG_CACHE"
    echo "https://github.com/$GH_REPO/releases/download/$t"
  else
    echo "https://github.com/$GH_REPO/releases/download/latest"
  fi
}

# Do not run two reinstalls at the same time.
if command -v flock >/dev/null 2>&1; then
  exec 9>"$LOCK"
  flock -n 9 || { log "a reinstall is already in progress; skipping"; exit 0; }
fi

# --- Detect platform ----------------------------------------------------------
detect_platform() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"
  case "$os:$arch" in
    Linux:x86_64)                echo "linux-x64" ;;
    Linux:aarch64 | Linux:arm64) echo "linux-arm64" ;;
    Darwin:arm64)                echo "darwin-arm64" ;;
    Darwin:x86_64)               echo "darwin-x64" ;;
    *)                           echo "unsupported:$os:$arch" ;;
  esac
}

[[ -f "$BIN" ]] || { log "no binary at $BIN; skipping"; exit 0; }

PLATFORM="$(detect_platform)"
[[ "$PLATFORM" == unsupported:* ]] && { log "unsupported platform: $PLATFORM"; exit 1; }

sha() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

CUR="$(sha "$BIN")"
WANT="$(cat "$MARKER" 2>/dev/null || true)"

# No marker or binary identical to the marked one → nothing to do.
if [[ -z "$WANT" || "$CUR" == "$WANT" ]]; then
  exit 0
fi

log "binary differs from the marker (official autoupdate?): reinstalling skill-toggle"

TMP="$(mktemp)"
SHA_TMP="$(mktemp)"
cleanup() { rm -f "$TMP" "$SHA_TMP"; }
trap cleanup EXIT

RELEASE_BASE="$(resolve_release_base)"

URL="$RELEASE_BASE/opencode-$PLATFORM"
if ! curl -fsSL --proto =https --tlsv1.2 "$URL" -o "$TMP"; then
  log "ERROR: could not download $URL"
  exit 1
fi

SHA_URL="$RELEASE_BASE/SHA256SUMS"
if ! curl -fsSL --proto =https --tlsv1.2 "$SHA_URL" -o "$SHA_TMP"; then
  log "ERROR: could not download $SHA_URL"
  exit 1
fi

EXPECTED="$(awk -v a="opencode-$PLATFORM" '$2==a {print $1; exit}' "$SHA_TMP")"
if [[ -z "$EXPECTED" ]]; then
  log "ERROR: no checksum for opencode-$PLATFORM in SHA256SUMS"
  exit 1
fi

ACTUAL="$(sha "$TMP")"
if [[ "$ACTUAL" != "$EXPECTED" ]]; then
  log "ERROR: SHA256 of the download does not match (expected $EXPECTED, got $ACTUAL); binary discarded"
  exit 1
fi

chmod +x "$TMP"
mv -f "$TMP" "$BIN"                      # atomic: works even while opencode is running
echo "$ACTUAL" > "$MARKER"
log "skill-toggle reinstalled OK ($PLATFORM, sha256 $ACTUAL)"

# Residue cleanup from previous versions (backups .bak / temporary files).
CLEANUP="$HOME/.opencode/toggle-cleanup.sh"
if [[ -f "$CLEANUP" ]]; then
  bash "$CLEANUP" >/dev/null 2>&1 || true
fi