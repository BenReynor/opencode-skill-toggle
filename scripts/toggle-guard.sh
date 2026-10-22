#!/usr/bin/env bash
#
# toggle-guard.sh — Guard and auto-updater for skill-toggle.
#
# Two jobs, both using the newest versioned release (one tag per build, so the
# content of every URL never changes) and verifying the SHA256 against
# SHA256SUMS:
#
#   1. Restore — if the opencode binary was replaced (official autoupdate,
#      "opencode upgrade", or a manual install of the clean binary), the
#      skill-toggle build is reinstalled.
#   2. Update — if a newer skill-toggle build has been published, it is
#      installed. The check is cached, so it costs one API call per hour.
#
# Call it periodically (systemd .path/.timer, cron, launchd, Task Scheduler…):
#   bash toggle-guard.sh
#
# Or force a version check right now:
#   bash toggle-guard.sh --update
#
# How it decides what to do:
#   - "$BIN.sha256" (the marker) stores the hash of the installed binary and
#     proves that this project installed it: without a marker the binary is
#     never touched.
#   - If the current hash differs from the marked one, the binary was replaced
#     → reinstall.
#   - If it matches, the hashes published in the newest release are compared:
#     a hash that is not published anymore means an older build → update.
#
# Optional variables:
#   GH_REPO=[user/repo]         repository to download from (default BenReynor/opencode-skill-toggle)
#   TOGGLE_GUARD_BIN=[path]     binary to watch (default $HOME/.opencode/bin/opencode)
#   TOGGLE_GUARD_LOG=[path]     log file (default $HOME/.opencode/toggle-guard.log)
#   TOGGLE_GUARD_CACHE_MIN=[n]  minutes the version check is cached (default 60)
set -euo pipefail

GH_REPO="${GH_REPO:-BenReynor/opencode-skill-toggle}"
BIN="${TOGGLE_GUARD_BIN:-$HOME/.opencode/bin/opencode}"
MARKER="$BIN.sha256"
LOG="${TOGGLE_GUARD_LOG:-$HOME/.opencode/toggle-guard.log}"
LOCK="/tmp/opencode-toggle-guard.$(id -u).lock"
CACHE_DIR="$HOME/.opencode"
CACHE_TAG="$CACHE_DIR/.toggle-guard-tag"
CACHE_SUMS="$CACHE_DIR/.toggle-guard-sums"
CACHE_MIN="${TOGGLE_GUARD_CACHE_MIN:-60}"

FORCE=0
if [[ "${1:-}" == "--update" || "${1:-}" == "-u" ]]; then
  FORCE=1
fi

log() {
  local line
  line="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
  printf '%s\n' "$line" >> "$LOG" 2>/dev/null || true
  printf '%s\n' "$line"
}

sha() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

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

# --- Release info (cached) ----------------------------------------------------
# Each build is published to a unique tag (toggle-X.Y.Z or toggle-X.Y.Z-r<build>):
# its content never changes, so the download never mixes old binaries from the
# CDN (unlike "latest", which is overwritten on every build).
#
# The cache keeps the tag and the SHA256SUMS of that release, so a normal run
# only hashes the local binary and compares it: one API call per hour.
cache_is_fresh() {
  [[ -f "$CACHE_TAG" && -f "$CACHE_SUMS" ]] || return 1
  find "$CACHE_TAG" -mmin "-$CACHE_MIN" >/dev/null 2>&1
}

load_cache() {
  TAG="$(cat "$CACHE_TAG" 2>/dev/null || true)"
  [[ -n "$TAG" ]] || return 1
  RELEASE_BASE="https://github.com/$GH_REPO/releases/download/$TAG"
  return 0
}

refresh_cache() {
  local tags all t tmp
  tags="$(curl -fsSL --proto =https --tlsv1.2 \
    "https://api.github.com/repos/$GH_REPO/releases?per_page=30" 2>/dev/null || true)"
  all="$(printf '%s\n' "$tags" | grep -oE '"tag_name": ?"[^"]+"' \
    | sed -E 's/.*": ?"([^"]+)".*/\1/' | grep '^toggle-' || true)"
  t="$(printf '%s\n' "$all" | sed -n '1p')"
  if [[ -z "$t" ]]; then
    t="latest"
  fi
  tmp="$(mktemp)"
  if ! curl -fsSL --proto =https --tlsv1.2 \
      "https://github.com/$GH_REPO/releases/download/$t/SHA256SUMS" -o "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    return 1
  fi
  mkdir -p "$CACHE_DIR"
  printf '%s\n' "$t" > "$CACHE_TAG"
  cp "$tmp" "$CACHE_SUMS"
  rm -f "$tmp"
  TAG="$t"
  RELEASE_BASE="https://github.com/$GH_REPO/releases/download/$t"
  return 0
}

# Do not run two reinstalls at the same time.
if command -v flock >/dev/null 2>&1; then
  exec 9>"$LOCK"
  flock -n 9 || { log "a reinstall is already in progress; skipping"; exit 0; }
fi

[[ -f "$BIN" ]] || { log "no binary at $BIN; skipping"; exit 0; }

PLATFORM="$(detect_platform)"
if [[ "$PLATFORM" == unsupported:* ]]; then
  log "unsupported platform: $PLATFORM"
  exit 1
fi

# --- Which release are we on, and is a newer one published? --------------------
if (( FORCE )) || ! cache_is_fresh; then
  refresh_cache || log "could not refresh the release info (offline?); using the cached one"
fi
load_cache || true

if [[ -z "${TAG:-}" ]]; then
  log "could not resolve the newest release; skipping"
  exit 0
fi

CUR="$(sha "$BIN")"
WANT="$(cat "$MARKER" 2>/dev/null || true)"

# No marker → this binary was not installed by us: never hijack it.
if [[ -z "$WANT" ]]; then
  exit 0
fi

REASON=""
if [[ "$CUR" != "$WANT" ]]; then
  REASON="restore"      # the binary was replaced (official autoupdate)
elif [[ -f "$CACHE_SUMS" ]] &&
     ! awk -v h="$CUR" '$1==h {f=1} END {exit !f}' "$CACHE_SUMS"; then
  REASON="update"       # our hash is not published anymore → older build
fi

if [[ -z "$REASON" ]]; then
  exit 0
fi

if [[ "$REASON" == "restore" ]]; then
  log "binary differs from the marker (official autoupdate?): reinstalling skill-toggle"
else
  log "a newer skill-toggle build is published ($TAG): updating"
fi

TMP="$(mktemp)"
cleanup() { rm -f "$TMP"; }
trap cleanup EXIT

URL="$RELEASE_BASE/opencode-$PLATFORM"
if ! curl -fsSL --proto =https --tlsv1.2 "$URL" -o "$TMP"; then
  log "ERROR: could not download $URL"
  exit 1
fi

EXPECTED="$(awk -v a="opencode-$PLATFORM" '$2==a {print $1; exit}' "$CACHE_SUMS" 2>/dev/null || true)"
if [[ -z "$EXPECTED" ]]; then
  log "ERROR: no checksum for opencode-$PLATFORM in SHA256SUMS"
  exit 1
fi

ACTUAL="$(sha "$TMP")"
if [[ "$ACTUAL" != "$EXPECTED" ]]; then
  log "ERROR: SHA256 of the download does not match (expected $EXPECTED, got $ACTUAL); binary discarded"
  exit 1
fi

chmod 755 "$TMP"

# Keep the current binary until the new one is proven to work (rollback).
BACKUP="$BIN.bak"
rm -f "$BACKUP"
if ! ln "$BIN" "$BACKUP" 2>/dev/null; then
  cp -p "$BIN" "$BACKUP" 2>/dev/null || BACKUP=""
fi

mv -f "$TMP" "$BIN"                      # atomic: works even while opencode is running

VER="$("$BIN" --version 2>/dev/null | sed -n '1p' || true)"
if [[ -z "$VER" ]]; then
  log "ERROR: the new binary does not run; restoring the previous one"
  if [[ -n "$BACKUP" && -f "$BACKUP" ]]; then
    mv -f "$BACKUP" "$BIN" || true
  fi
  exit 1
fi

echo "$ACTUAL" > "$MARKER"
log "skill-toggle installed OK ($PLATFORM, $VER, sha256 $ACTUAL)"

# Residue cleanup from previous versions (backups .bak / temporary files).
CLEANUP="$HOME/.opencode/toggle-cleanup.sh"
if [[ -f "$CLEANUP" ]]; then
  bash "$CLEANUP" >/dev/null 2>&1 || true
fi
