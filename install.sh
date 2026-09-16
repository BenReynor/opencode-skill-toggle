#!/usr/bin/env bash
#
# Instala opencode + skill-toggle (build personalizada del binario de opencode).
#
# Uso:
#   ./install.sh                          # usa el binario junto a este script, o
#                                         # descarga de GitHub Releases/latest
#   GH_REPO=tudusuario/opencode-skill-toggle ./install.sh
#   TOGGLE_GUARD=0 ./install.sh           # no activar el guardián anti-borrado
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

# Marcador para el guardián: hash del binario con toggle recién instalado.
if command -v sha256sum >/dev/null 2>&1; then
  HASH_ACTUAL="$(sha256sum "$BIN_SRC" | awk '{print $1}')"
else
  HASH_ACTUAL="$(shasum -a 256 "$BIN_SRC" | awk '{print $1}')"
fi
echo "$HASH_ACTUAL" > "$ORIG.sha256"

echo ">> opencode con skill-toggle instalado: $ORIG"
echo

# --- Guardián anti-borrado (opcional, Linux con systemd) ---------------------
# Si el installador oficial (autoupdate / "opencode upgrade") reemplaza el
# binario, toggle-guard.sh lo restaura en segundo plano.
if [[ "${TOGGLE_GUARD:-1}" == "1" ]] && command -v systemctl >/dev/null 2>&1 \
   && [[ "$(uname -s)" == "Linux" ]]; then
  GUARD="$HOME/.opencode/toggle-guard.sh"
  if [[ -f "$SCRIPT_DIR/scripts/toggle-guard.sh" ]]; then
    cp "$SCRIPT_DIR/scripts/toggle-guard.sh" "$GUARD"
  else
    echo ">> Descargando toggle-guard.sh"
    curl -fsSL --proto =https --tlsv1.2 \
      "https://github.com/$GH_REPO/releases/download/latest/toggle-guard.sh" \
      -o "$GUARD"
  fi
  chmod +x "$GUARD"

  UDIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
  mkdir -p "$UDIR"

  cat > "$UDIR/opencode-toggle-guard.path" <<EOF
[Unit]
Description=Detecta cambios en el binario de opencode (skill-toggle)

[Path]
PathChanged=%h/.opencode/bin/opencode
Unit=opencode-toggle-guard.service

[Install]
WantedBy=default.target
EOF

  cat > "$UDIR/opencode-toggle-guard.service" <<EOF
[Unit]
Description=Reinstala el skill-toggle si el binario de opencode fue reemplazado

[Service]
Type=oneshot
ExecStart=%h/.opencode/toggle-guard.sh
EOF

  cat > "$UDIR/opencode-toggle-guard.timer" <<EOF
[Unit]
Description=Copia de seguridad del skill-toggle (cada 15 min)

[Timer]
OnBootSec=2min
OnUnitActiveSec=15min

[Install]
WantedBy=default.target
EOF

  if systemctl --user daemon-reload 2>/dev/null; then
    systemctl --user enable --now opencode-toggle-guard.path \
      opencode-toggle-guard.timer >/dev/null 2>&1 || true
    systemctl --user start opencode-toggle-guard.service >/dev/null 2>&1 || true
    echo ">> Guardián anti-borrado activado (systemd --user):"
    echo ">>   - reinstala el toggle si el autoupdate oficial lo reemplaza"
    echo ">>   - log: $HOME/.opencode/toggle-guard.log"
    echo ">>   - desactivar: TOGGLE_GUARD=0 $0  y  systemctl --user disable --now opencode-toggle-guard.path opencode-toggle-guard.timer"
  else
    echo ">> Aviso: systemd --user no disponible; guardián instalado pero sin activar" >&2
  fi
else
  echo ">> Guardián anti-borrado no instalado (TOGGLE_GUARD=0 o sin systemd)"
fi

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