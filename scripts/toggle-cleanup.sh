#!/usr/bin/env bash
#
# toggle-cleanup.sh — Residue cleanup for skill-toggle.
#
# Every time the binary is updated or restored, removes leftovers from previous
# versions that pile up in $HOME/.opencode/bin (.bak backups and *.download /
# *.tmp temporary files), so they never eat hundreds of MB.
#
# What it keeps:
#   - $BIN             (the active binary with skill-toggle)
#   - $BIN.sha256      (the guard's marker)
#
# What it removes:
#   - $BIN.bak and $BIN.<version>.bak     (backups from previous versions)
#   - $BIN.tmp*, $BIN.download            (installer temporary files)
#   - .opencode-*.download                (SHA256 / temporary downloads)
#
# Optional variables:
#   TOGGLE_GUARD_BIN            binary path (default $HOME/.opencode/bin/opencode)
#   TOGGLE_CLEANUP_KEEP_BACKUP=1  keep a single .bak of the previous version
#   TOGGLE_CLEANUP_DRY_RUN=1      list without deleting (dry run)
#   TOGGLE_CLEANUP_LOG            log file (default $HOME/.opencode/toggle-cleanup.log)
#
# Usage:
#   bash toggle-cleanup.sh
#
set -euo pipefail

BIN="${TOGGLE_GUARD_BIN:-$HOME/.opencode/bin/opencode}"
KEEP_BACKUP="${TOGGLE_CLEANUP_KEEP_BACKUP:-0}"
DRY_RUN="${TOGGLE_CLEANUP_DRY_RUN:-0}"
LOG="${TOGGLE_CLEANUP_LOG:-$HOME/.opencode/toggle-cleanup.log}"

DIR="$(dirname "$BIN")"
[[ -d "$DIR" ]] || exit 0
NAME="$(basename "$BIN")"
[[ -n "$NAME" ]] || exit 1

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"; }

# --- Collect candidates (backups + temporary files) ---------------------------
shopt -s nullglob dotglob
candidates=(
  "$DIR"/"$NAME"*.bak
  "$DIR"/"$NAME".tmp*
  "$DIR"/"$NAME".download
  "$DIR"/.opencode-*.download
)

targets=()
for f in "${candidates[@]}"; do
  [[ -f "$f" ]] || continue
  if [[ "$KEEP_BACKUP" == "1" && "$(basename "$f")" == "$NAME.bak" ]]; then
    continue
  fi
  targets+=("$f")
done

if [[ "${#targets[@]}" -eq 0 ]]; then
  exit 0
fi

if [[ "$DRY_RUN" == "1" ]]; then
  echo ">> (dry run) pending deletion:"
  for f in "${targets[@]}"; do
    echo "   - $f"
  done
  exit 0
fi

for f in "${targets[@]}"; do
  rm -f "$f"
  log "removed residue: $f"
done