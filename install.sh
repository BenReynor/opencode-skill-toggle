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

GH_REPO="${GH_REPO:-BenReynor/opencode-skill-toggle}"
ORIG="$HOME/.opencode/bin/opencode"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" && pwd 2>/dev/null || echo "$PWD")"

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
  URL="https://github.com/$GH_REPO/releases/download/latest/opencode-$PLATFORM"
  echo ">> Descargando: $URL"
  BIN_SRC="$SCRIPT_DIR/.opencode-$PLATFORM.download"
  curl -fsSL --proto =https --tlsv1.2 "$URL" -o "$BIN_SRC"

  # --- Verificación SHA256 ---------------------------------------------------
  SHA_URL="https://github.com/$GH_REPO/releases/download/latest/SHA256SUMS"
  SHA_FILE="$SCRIPT_DIR/.opencode-sha256.download"
  echo ">> Verificando SHA256 contra $SHA_URL"
  if curl -fsSL --proto =https --tlsv1.2 "$SHA_URL" -o "$SHA_FILE"; then
    EXPECTED="$(awk -v a="opencode-$PLATFORM" '$2==a {print $1; exit}' "$SHA_FILE")"
    if [[ -z "$EXPECTED" ]]; then
      echo ">> aviso: no hay checksum para opencode-$PLATFORM; se continúa sin verificar" >&2
    else
      if command -v sha256sum >/dev/null 2>&1; then
        ACTUAL="$(sha256sum "$BIN_SRC" | awk '{print $1}')"
      else
        ACTUAL="$(shasum -a 256 "$BIN_SRC" | awk '{print $1}')"
      fi
      if [[ "$ACTUAL" != "$EXPECTED" ]]; then
        echo "ERROR: la verificación SHA256 falló para opencode-$PLATFORM" >&2
        echo "  esperado: $EXPECTED" >&2
        echo "  obtenido: $ACTUAL" >&2
        rm -f "$BIN_SRC" "$SHA_FILE"
        echo "  El binario se descartó por posible manipulación." >&2
        exit 1
      fi
      echo ">> SHA256 verificado correctamente"
    fi
  else
    echo ">> aviso: no se pudo descargar SHA256SUMS; se continúa sin verificar" >&2
  fi
  rm -f "$SHA_FILE"
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
# Reemplazo atómico (mv): no falla con "Text file busy" aunque opencode esté
# en ejecución. El proceso en marcha conserva su inode viejo y las sesiones
# nuevas usan el binario nuevo.
TMP="$ORIG.tmp.$$"
cp "$BIN_SRC" "$TMP"
chmod +x "$TMP"
mv -f "$TMP" "$ORIG"
rm -f "$SCRIPT_DIR/.opencode-$PLATFORM.download"
echo ">> opencode con skill-toggle instalado: $ORIG"
echo

cat <<'EOF'
Aviso importante:
  - Esta es una build personalizada (no oficial). Mantiene tu opencode.db real.
  - Al descargar de GitHub Releases, el binario se verifica contra SHA256SUMS.
  - Configura "autoupdate": false en opencode.json para que el instalador
    oficial no la reemplace al actualizar (este repo reconstruye la build con
    cada versión nueva de upstream; actualizar = volver a correr este script).
  - El reemplazo es atómico: puedes reinstalar incluso con opencode abierto.
  - Reinicia opencode para que el binario nuevo quede activo.
EOF