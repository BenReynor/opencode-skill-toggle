#!/usr/bin/env bash
#
# Instala opencode + skill-toggle (build personalizada del binario de opencode).
#
# Uso:
#   ./install.sh                          # usa el binario junto a este script, o
#                                         # descarga de GitHub Releases/latest
#   GH_REPO=tudusuario/opencode-skill-toggle ./install.sh
#
# Si se encuentra un binario local (opencode-<platform>) al lado de install.sh
# se usa primero; si no, se descarga del release "latest" del repo.
set -euo pipefail

GH_REPO="${GH_REPO:-benjametalsp/opencode-skill-toggle}"
ORIG="$HOME/.opencode/bin/opencode"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Detectar plataforma ----------------------------------------------------
detect_platform() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"
  case "$os:$arch" in
    Linux:x86_64)  echo "linux-x64" ;;
    Linux:aarch64 | Linux:arm64) echo "linux-arm64" ;;
    Darwin:arm64)  echo "darwin-arm64" ;;
    Darwin:x86_64) echo "darwin-x64" ;;
    *) echo "unsupported:$os:$arch" ;;
  esac
}

PLATFORM="$(detect_platform)"
if [[ "$PLATFORM" == unsupported:* ]]; then
  echo "Plataforma no soportada: $PLATFORM" >&2
  exit 1
fi
echo ">> Plataforma: $PLATFORM"

# --- Obtener el binario -----------------------------------------------------
BIN_SRC=""
for candidate in "$SCRIPT_DIR/opencode-$PLATFORM" "$SCRIPT_DIR/dist/opencode-$PLATFORM"; do
  if [[ -f "$candidate" ]]; then
    BIN_SRC="$candidate"
    break
  fi
done
if [[ -z "$BIN_SRC" ]]; then
  URL="https://github.com/$GH_REPO/releases/latest/download/opencode-$PLATFORM"
  echo ">> Descargando: $URL"
  BIN_SRC="$SCRIPT_DIR/.opencode-$PLATFORM.download"
  curl -fsSL "$URL" -o "$BIN_SRC"
fi

# --- Backup del binario actual ----------------------------------------------
mkdir -p "$HOME/.opencode/bin"
if [[ -f "$ORIG" && ! -f "$ORIG.bak" ]]; then
  cp "$ORIG" "$ORIG.bak"
  echo ">> Backup guardado: $ORIG.bak"
elif [[ -f "$ORIG" ]]; then
  echo ">> Backup existente: $ORIG.bak (no se sobreescribe)"
fi

# --- Instalar ---------------------------------------------------------------
chmod +x "$BIN_SRC"
cp "$BIN_SRC" "$ORIG"
rm -f "$SCRIPT_DIR/.opencode-$PLATFORM.download"
echo ">> opencode con skill-toggle instalado: $ORIG"
echo

cat <<'EOF'
Aviso importante:
  - Esta es una build personalizada (no oficial). Mantiene tu opencode.db real.
  - Configura "autoupdate": false en opencode.json para que no la reemplace
    el instalador oficial.
  - Reinicia opencode para que el binario nuevo quede activo.
EOF