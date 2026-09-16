#!/usr/bin/env bash
#
# toggle-cleanup.sh — Limpieza de residuos del skill-toggle.
#
# Cada vez que se actualiza o se restaura el binario, elimina los restos de
# versiones anteriores que se acumulan en $HOME/.opencode/bin (backups .bak y
# temporales *.download / *.tmp), evitando que se coman cientos de MB.
#
# Qué conserva:
#   - $BIN             (el binario activo con skill-toggle)
#   - $BIN.sha256      (marcador del guardián)
#
# Qué elimina:
#   - $BIN.bak y $BIN.<version>.bak     (backups de versiones anteriores)
#   - $BIN.tmp*, $BIN.download          (temporales del instalador)
#   - .opencode-*.download              (descargas SHA256/temporales)
#
# Variables opcionales:
#   TOGGLE_GUARD_BIN            ruta del binario (por defecto $HOME/.opencode/bin/opencode)
#   TOGGLE_CLEANUP_KEEP_BACKUP=1  conservar un único .bak de la versión anterior
#   TOGGLE_CLEANUP_DRY_RUN=1      listar sin borrar (ensayo)
#   TOGGLE_CLEANUP_LOG            fichero de log (por defecto $HOME/.opencode/toggle-cleanup.log)
#
# Uso:
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

# --- Reunir candidatos (backups + temporales) --------------------------------
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
  echo ">> (ensayo) pending de eliminar:"
  for f in "${targets[@]}"; do
    echo "   - $f"
  done
  exit 0
fi

for f in "${targets[@]}"; do
  rm -f "$f"
  log "eliminado residuo: $f"
done