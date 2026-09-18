#!/usr/bin/env bash
#
# Compiles opencode + skill-toggle from the upstream tarball (anomalyco/opencode).
#
# Does NOT require git: it downloads the release tarball with curl, extracts it
# with tar and applies the patches with `patch -p1` (irreversible, but with no
# dependency on git or a clone).
#
# Usage:
#   ./build.sh                 # compiles the pinned validated version (1.18.30)
#   ./build.sh latest          # compiles the latest published version (requires updating patches)
#   ./build.sh 1.18.30         # compiles a specific version
#   MINIFY=0 ./build.sh        # without minification (debugging only)
#   KEEP_SRC=1 ./build.sh      # keeps the extracted source (debugging)
#
set -euo pipefail

VERSION="${1:-1.18.30}"
WORK="/tmp/opencode-toggle-build"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$WORK/src/opencode-$VERSION"

resolve_tag() {
  if [[ "$VERSION" == "latest" ]]; then
    echo ">> WARNING: 'latest' may require updating the patches." >&2
    echo ">>          the patches are validated for 1.18.30." >&2
    # Get the latest published release (skips pre-releases; no git needed)
    curl -fsSL --proto =https --tlsv1.2 "https://api.github.com/repos/anomalyco/opencode/releases/latest" \
      | grep -oE '"tag_name": *"[^"]+"' | head -1 | sed 's/.*"v\([0-9.]*\)".*/\1/'
  else
    echo "$VERSION"
  fi
}

VER="$(resolve_tag)"
TAG="v$VER"
if [[ -z "$VER" || "$VER" == ".*" ]]; then
  echo ">> Could not resolve the version. Usage: ./build.sh [1.18.30|latest]" >&2
  exit 1
fi
echo ">> Building opencode $VER (tag $TAG)"

# --- Download and extract the tarball -----------------------------------------
if [[ -d "$SRC" && "${KEEP_SRC:-0}" != "1" ]]; then
  echo ">> Reusing extracted source at $SRC"
elif [[ -d "$SRC" ]]; then
  echo ">> Reusing extracted source (KEEP_SRC=1) at $SRC"
else
  echo ">> Downloading opencode $VER..."
  mkdir -p "$WORK/src"
  curl -fsSL --proto =https --tlsv1.2 "https://codeload.github.com/anomalyco/opencode/tar.gz/refs/tags/$TAG" \
    -o "$WORK/src/opencode-$VER.tar.gz"
  tar -xzf "$WORK/src/opencode-$VER.tar.gz" -C "$WORK/src"
  rm -f "$WORK/src/opencode-$VER.tar.gz"
fi

echo ">> Applying patches..."
cd "$SRC"
patch -p1 --forward < "$SCRIPT_DIR/patches/00-skill-toggle.patch"
patch -p1 --forward < "$SCRIPT_DIR/patches/01-build-local-fix.patch"
echo ">> Patches applied."

echo ">> Installing dependencies..."
bun install --cwd "$SRC"

echo ">> Building..."
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
echo ">> Done:"
echo "   - $OUT/opencode-linux-x64 (the binary to install)"
echo "   Install with: ./install.sh   (or move the binary next to install.sh)"
