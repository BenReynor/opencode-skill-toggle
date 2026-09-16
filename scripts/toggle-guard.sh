#!/usr/bin/env bash
#
# toggle-guard.sh — Guardian del skill-toggle.
#
# Si el binario de opencode fue reemplazado (por el autoupdate oficial,
# por "opencode upgrade" o por cualquier otro medio), reinstala en segundo
# plano la build con skill-toggle descargándola del release versionado más
# nuevo (tag único por build) y verificando el SHA256 contra SHA256SUMS.
#
# Llámalo periódicamente (systemd .path/.timer, cron, launchd, Task Scheduler…):
#   bash toggle-guard.sh
#
# Cómo decide que hay que reinstalar:
#   - "#BIN.sha256" guarda el hash del último binario con toggle instalado.
#   - Si el hash actual de "#BIN" coincide con el marcado, no hace nada.
#   - Si difiere, descarga y reinstala el toggle.
#   - Si el marcado no existe, no hace nada: nunca secuestra un binario que
#     este proyecto no instaló.
#
# Variables opcionales:
#   GH_REPO=[usuario/repo]     repositorio del que descargar (por defecto BenReynor/opencode-skill-toggle)
#   TOGGLE_GUARD_BIN=[ruta]    ruta del binario a vigilar (por defecto $HOME/.opencode/bin/opencode)
#   TOGGLE_GUARD_LOG=[ruta]    fichero de log (por defecto $HOME/.opencode/toggle-guard.log)
set -euo pipefail

GH_REPO="${GH_REPO:-BenReynor/opencode-skill-toggle}"
BIN="${TOGGLE_GUARD_BIN:-$HOME/.opencode/bin/opencode}"
MARKER="$BIN.sha256"
LOG="${TOGGLE_GUARD_LOG:-$HOME/.opencode/toggle-guard.log}"
LOCK="/tmp/opencode-toggle-guard.lock"
TAG_CACHE="$HOME/.opencode/.toggle-guard-tag"

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"; }

# --- Resolver el release versionado más nuevo (con caché de 6 h) -------------
# Cada build se publica en un tag único (toggle-X.Y.Z o toggle-X.Y.Z-r<build>):
# su contenido nunca cambia, así que la descarga nunca mezcla bins viejos del
# CDN (como pasaría con "latest", que se sobrescribe en cada build).
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

# No dejes dos reinstalaciones a la vez.
if command -v flock >/dev/null 2>&1; then
  exec 9>"$LOCK"
  flock -n 9 || { log "ya hay una reinstalación en curso; se omite"; exit 0; }
fi

# --- Detectar plataforma ----------------------------------------------------
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

[[ -f "$BIN" ]] || { log "no hay binario en $BIN; se omite"; exit 0; }

PLATFORM="$(detect_platform)"
[[ "$PLATFORM" == unsupported:* ]] && { log "plataforma no soportada: $PLATFORM"; exit 1; }

sha() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

CUR="$(sha "$BIN")"
WANT="$(cat "$MARKER" 2>/dev/null || true)"

# Sin referencia o binario idéntico al marcado → nada que hacer.
if [[ -z "$WANT" || "$CUR" == "$WANT" ]]; then
  exit 0
fi

log "binario distinto al marcado (¿autoupdate oficial?): reinstalo skill-toggle"

TMP="$(mktemp)"
SHA_TMP="$(mktemp)"
cleanup() { rm -f "$TMP" "$SHA_TMP"; }
trap cleanup EXIT

RELEASE_BASE="$(resolve_release_base)"

URL="$RELEASE_BASE/opencode-$PLATFORM"
if ! curl -fsSL --proto =https --tlsv1.2 "$URL" -o "$TMP"; then
  log "ERROR: no se pudo descargar $URL"
  exit 1
fi

SHA_URL="$RELEASE_BASE/SHA256SUMS"
if ! curl -fsSL --proto =https --tlsv1.2 "$SHA_URL" -o "$SHA_TMP"; then
  log "ERROR: no se pudo descargar $SHA_URL"
  exit 1
fi

EXPECTED="$(awk -v a="opencode-$PLATFORM" '$2==a {print $1; exit}' "$SHA_TMP")"
if [[ -z "$EXPECTED" ]]; then
  log "ERROR: sin checksum para opencode-$PLATFORM en SHA256SUMS"
  exit 1
fi

ACTUAL="$(sha "$TMP")"
if [[ "$ACTUAL" != "$EXPECTED" ]]; then
  log "ERROR: SHA256 de la descarga no coincide (esperado $EXPECTED, obtenido $ACTUAL); binario descartado"
  exit 1
fi

chmod +x "$TMP"
mv -f "$TMP" "$BIN"                      # atómico: funciona aun con opencode corriendo
echo "$ACTUAL" > "$MARKER"
log "skill-toggle reinstalado OK ($PLATFORM, sha256 $ACTUAL)"

# Limpieza de residuos de versiones anteriores (backups .bak / temporales).
CLEANUP="$HOME/.opencode/toggle-cleanup.sh"
if [[ -f "$CLEANUP" ]]; then
  bash "$CLEANUP" >/dev/null 2>&1 || true
fi