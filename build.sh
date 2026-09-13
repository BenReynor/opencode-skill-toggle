#!/usr/bin/env bash
#
# Compila opencode + skill-toggle desde el tarball de upstream (anomalyco/opencode).
#
# NO requiere git: descarga el tarball del release con curl, extrae con tar y
# aplica los patches con `patch -p1` (irreversible, pero sin ninguna dependencia
# de git ni de un clon).
#
# Uso:
#   ./build.sh                 # compila la versión validada anclada (1.18.30)
#   ./build.sh latest          # compila la última versión publicada (requiere actualizar patches)
#   ./build.sh 1.18.30         # compila una versión concreta
#   MINIFY=0 ./build.sh        # sin minificar (solo debugging)
#   KEEP_SRC=1 ./build.sh      # conserva el fuente extraído (debugging)
#
set -euo pipefail

VERSION="${1:-1.18.30}"
WORK="/tmp/opencode-toggle-build"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$WORK/src/opencode-$VERSION"

resolve_tag() {
  if [[ "$VERSION" == "latest" ]]; then
    echo ">> ATENCION: 'latest' puede requerir actualizar los patches." >&2
    echo ">>           los patches estan validados para 1.18.30." >&2
    # Obtener la última tag publicada vía el tarball (sin git)
    curl -fsSL "https://api.github.com/repos/anomalyco/opencode/tags" \
      | grep -oE '"name": *"v[0-9][^"]*"' | head -1 | sed 's/.*"v\([0-9.]*\)".*/\1/'
  else
    echo "$VERSION"
  fi
}

VER="$(resolve_tag)"
TAG="v$VER"
if [[ -z "$VER" || "$VER" == ".*" ]]; then
  echo ">> No se pudo resolver la versión. Uso: ./build.sh [1.18.30|latest]" >&2
  exit 1
fi
echo ">> Compilando opencode $VER (tag $TAG)"

# --- Descargar y extraer el tarball ------------------------------------------
if [[ -d "$SRC" && "${KEEP_SRC:-0}" != "1" ]]; then
  echo ">> Reutilizando fuente extraído en $SRC"
elif [[ -d "$SRC" ]]; then
  echo ">> Reutilizando fuente extraído (KEEP_SRC=1) en $SRC"
else
  echo ">> Descargando opencode $VER..."
  mkdir -p "$WORK/src"
  curl -fsSL "https://codeload.github.com/anomalyco/opencode/tar.gz/refs/tags/$TAG" \
    -o "$WORK/src/opencode-$VER.tar.gz"
  tar -xzf "$WORK/src/opencode-$VER.tar.gz" -C "$WORK/src"
  rm -f "$WORK/src/opencode-$VER.tar.gz"
fi

echo ">> Aplicando patches..."
cd "$SRC"
patch -p1 --forward < "$SCRIPT_DIR/patches/00-skill-toggle.patch"
patch -p1 --forward < "$SCRIPT_DIR/patches/01-build-local-fix.patch"
echo ">> Patches aplicados."

echo ">> Instalando dependencias..."
bun install --cwd "$SRC"

echo ">> Compilando..."
OPENCODE_CHANNEL=latest \
OPENCODE_VERSION="$VER" \
SPLIT=0 \
bun run --cwd "$SRC/packages/opencode" build --single --skip-embed-web-ui

OUT="$SCRIPT_DIR/dist"
mkdir -p "$OUT"
cp "$SRC/packages/opencode/dist/opencode-linux-x64/bin/opencode" \
   "$OUT/opencode-$VER-toggle-linux-x64"
cp "$OUT/opencode-$VER-toggle-linux-x64" "$OUT/opencode-linux-x64"

echo
echo ">> Listo:"
echo "   - $OUT/opencode-linux-x64 (el binario para instalar)"
echo "   Copia con: ./install.sh   (o mueve el binario al lado de install.sh)"
