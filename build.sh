#!/usr/bin/env bash
#
# Compila opencode + skill-toggle desde el fuente de upstream.
#
# Uso:
#   ./build.sh                 # compila la versión more reciente (latest)
#   ./build.sh 1.18.30         # compila una versión específica
#   MINIFY=0 ./build.sh        # sin minificar (solo debugging)
#
set -euo pipefail

VERSION="${1:-latest}"
WORK="/tmp/opencode-toggle-build"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

resolve_tag() {
  if [[ "$VERSION" == "latest" ]]; then
    git ls-remote --tags --refs https://github.com/anomalyco/opencode.git | \
      awk -F'/' '{print $3}' | sed 's/^v//' | sort -V | tail -1
  else
    echo "$VERSION"
  fi
}

VER="$(resolve_tag)"
TAG="v$VER"
echo ">> Compilando opencode $VER (tag $TAG)"

# --- Clonar (o actualizar) el fuente ----------------------------------------
if [[ ! -d "$WORK/.git" ]]; then
  echo ">> Clonando opencode..."
  git clone https://github.com/anomalyco/opencode.git "$WORK"
else
  echo ">> Actualizando clon existente..."
  git -C "$WORK" fetch --tags origin
fi

# Si dependencias ya instaladas, la build reusa el lockfile actualizado
git -C "$WORK" checkout --force "$TAG" 2>/dev/null || true
git -C "$WORK" fetch --depth 1 origin tag "$TAG"
git -C "$WORK" checkout --force "$TAG"
git -C "$WORK" checkout --force --detach 2>/dev/null || true

echo ">> Aplicando patches (los fallos de 3way se pueden arreglar a mano)..."
git -C "$WORK" apply --3way "$SCRIPT_DIR/patches/00-skill-toggle.patch"
git -C "$WORK" apply --3way "$SCRIPT_DIR/patches/01-build-local-fix.patch"

echo ">> Instalando dependencias..."
bun install --frozen-lockfile --cwd "$WORK"

echo ">> Compilando..."
OPENCODE_CHANNEL=latest \
OPENCODE_VERSION="$VER" \
SPLIT=0 \
bun run --cwd "$WORK/packages/opencode" build --single --skip-embed-web-ui

OUT="$SCRIPT_DIR/dist"
mkdir -p "$OUT"
cp "$WORK/packages/opencode/dist/opencode-linux-x64/bin/opencode" "$OUT/opencode-$VER-toggle-linux-x64"
cp "$OUT/opencode-$VER-toggle-linux-x64" "$OUT/opencode-linux-x64"

echo
echo ">> Listo:"
echo "   - $OUT/opencode-linux-x64 (el binario para instalar)"
echo "   Copia con: ./install.sh   (o mueve el binario al lado de install.sh)"