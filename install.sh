#!/usr/bin/env bash
#
# Installs opencode + skill-toggle (custom build of the opencode binary).
#
# Usage:
#   ./install.sh                        # uses the binary next to this script, or
#                                       # downloads it from the GitHub release
#   GH_REPO=youruser/opencode-skill-toggle ./install.sh
#   TOGGLE_GUARD=0 ./install.sh         # don't install the anti-overwrite guard
#
# If a local binary (opencode-<platform>) is found next to install.sh it is
# used first; otherwise it downloads from the newest versioned release (one
# build per tag, assets are never overwritten — avoids mixing old/new binaries
# in the CDN cache).
set -euo pipefail

GH_REPO="${GH_REPO:-BenReynor/opencode-skill-toggle}"
ORIG="$HOME/.opencode/bin/opencode"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" && pwd 2>/dev/null || echo "$PWD")"
# Downloads go to the temp dir: the script dir may be read-only (installing
# from /usr/local/bin, a USB stick or a read-only mount) or the current
# directory when run via "curl | bash".
DL_DIR="${TMPDIR:-/tmp}"

# --- Detect platform --------------------------------------------------------
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
  echo "Unsupported platform: $PLATFORM" >&2
  exit 1
fi
echo ">> Platform: $PLATFORM"

# --- Resolve the newest release (unique builds, assets never overwritten) ----
# Each build is published to a unique versioned release (toggle-X.Y.Z or
# toggle-X.Y.Z-r<build>). We resolve the most recent tag via the API and
# download from there: since the content of every URL never changes, there is no
# mixing of old/new binaries in the CDN cache (which is what happens with
# "latest", overwritten on every build).
resolve_release_base() {
  local tags t
  tags="$(curl -fsSL --proto =https --tlsv1.2 \
    "https://api.github.com/repos/$GH_REPO/releases?per_page=30" 2>/dev/null || true)"
  t="$(printf '%s\n' "$tags" | grep -oE '"tag_name": ?"[^"]+"' | sed -E 's/.*": ?"([^"]+)".*/\1/' | grep '^toggle-' | head -n1)"
  if [[ -n "$t" ]]; then
    echo "https://github.com/$GH_REPO/releases/download/$t"
  else
    echo "https://github.com/$GH_REPO/releases/download/latest"
  fi
}
RELEASE_BASE="$(resolve_release_base)"
echo ">> Release: ${RELEASE_BASE#https://github.com/$GH_REPO/releases/download/}"

# --- Obtain the binary ------------------------------------------------------
BIN_SRC=""
for candidate in "$SCRIPT_DIR/opencode-$PLATFORM" "$SCRIPT_DIR/dist/opencode-$PLATFORM"; do
  if [[ -f "$candidate" ]]; then
    BIN_SRC="$candidate"
    break
  fi
done
if [[ -z "$BIN_SRC" ]]; then
  URL="$RELEASE_BASE/opencode-$PLATFORM"
  echo ">> Downloading: $URL"
  BIN_SRC="$DL_DIR/.opencode-toggle-$PLATFORM.download"
  curl -fsSL --proto =https --tlsv1.2 "$URL" -o "$BIN_SRC"

  # --- SHA256 verification --------------------------------------------------
  SHA_URL="$RELEASE_BASE/SHA256SUMS"
  SHA_FILE="$DL_DIR/.opencode-toggle-sha256.download"
  echo ">> Verifying SHA256 against $SHA_URL"
  if curl -fsSL --proto =https --tlsv1.2 "$SHA_URL" -o "$SHA_FILE"; then
    EXPECTED="$(awk -v a="opencode-$PLATFORM" '$2==a {print $1; exit}' "$SHA_FILE")"
    if [[ -z "$EXPECTED" ]]; then
      echo ">> warning: no checksum for opencode-$PLATFORM; continuing without verification" >&2
    else
      if command -v sha256sum >/dev/null 2>&1; then
        ACTUAL="$(sha256sum "$BIN_SRC" | awk '{print $1}')"
      else
        ACTUAL="$(shasum -a 256 "$BIN_SRC" | awk '{print $1}')"
      fi
      if [[ "$ACTUAL" != "$EXPECTED" ]]; then
        echo "ERROR: SHA256 verification failed for opencode-$PLATFORM" >&2
        echo "  expected: $EXPECTED" >&2
        echo "  got: $ACTUAL" >&2
        rm -f "$BIN_SRC" "$SHA_FILE"
        echo "  The binary was discarded because of possible tampering." >&2
        exit 1
      fi
      echo ">> SHA256 verified correctly"
    fi
  else
    echo ">> warning: could not download SHA256SUMS; continuing without verification" >&2
  fi
  rm -f "$SHA_FILE"
fi

# --- Backup of the current binary -------------------------------------------
mkdir -p "$HOME/.opencode/bin"
if [[ -f "$ORIG" && ! -f "$ORIG.bak" ]]; then
  cp "$ORIG" "$ORIG.bak"
  echo ">> Backup saved: $ORIG.bak"
elif [[ -f "$ORIG" ]]; then
  echo ">> Backup exists: $ORIG.bak (not overwritten)"
fi

# --- Install ----------------------------------------------------------------
# Atomic replacement (mv): does not fail with "Text file busy" even when
# opencode is running. The running process keeps its old inode, and new
# sessions use the new binary.
TMP="$ORIG.tmp.$$"
cp "$BIN_SRC" "$TMP"
chmod +x "$TMP"
mv -f "$TMP" "$ORIG"
rm -f "$BIN_SRC"

# Marker for the guard: hash of the just-installed toggle binary.
if command -v sha256sum >/dev/null 2>&1; then
  HASH_ACTUAL="$(sha256sum "$ORIG" | awk '{print $1}')"
else
  HASH_ACTUAL="$(shasum -a 256 "$ORIG" | awk '{print $1}')"
fi
echo "$HASH_ACTUAL" > "$ORIG.sha256"

echo ">> opencode with skill-toggle installed: $ORIG"
echo

# --- Residue cleanup --------------------------------------------------------
# Removes backups and temporary files from previous versions on update, so
# hundreds of MB never pile up. Keeps the binary + marker.
#   - keep a single .bak of the previous one: TOGGLE_CLEANUP_KEEP_BACKUP=1
#   - dry run (list only):                   TOGGLE_CLEANUP_DRY_RUN=1
CLEANUP="$HOME/.opencode/toggle-cleanup.sh"
if [[ -f "$SCRIPT_DIR/scripts/toggle-cleanup.sh" ]]; then
  cp "$SCRIPT_DIR/scripts/toggle-cleanup.sh" "$CLEANUP"
elif [[ ! -f "$CLEANUP" ]]; then
  echo ">> Downloading toggle-cleanup.sh"
  curl -fsSL --proto =https --tlsv1.2 \
    "$RELEASE_BASE/toggle-cleanup.sh" \
    -o "$CLEANUP" || rm -f "$CLEANUP"
fi
if [[ -f "$CLEANUP" ]]; then
  chmod +x "$CLEANUP" 2>/dev/null || true
  if bash "$CLEANUP"; then
    echo ">> Residues of previous versions removed"
  else
    echo ">> Warning: residue cleanup did not finish properly; retry with: bash $CLEANUP" >&2
  fi
fi
echo

# --- Anti-overwrite guard ---------------------------------------------------
# If the official installer (autoupdate / "opencode upgrade") replaces the
# binary, toggle-guard.sh restores it in the background.
#   - Linux:   systemd --user (.path with inotify + .timer every 15 min)
#   - macOS:   launchd (LaunchAgent with a 15-min StartInterval)
#   - Windows: Scheduled Task (handled by install.ps1)
if [[ "${TOGGLE_GUARD:-1}" == "1" ]]; then
  GUARD="$HOME/.opencode/toggle-guard.sh"
  if [[ -f "$SCRIPT_DIR/scripts/toggle-guard.sh" ]]; then
    cp "$SCRIPT_DIR/scripts/toggle-guard.sh" "$GUARD"
  elif ! curl -fsSL --proto =https --tlsv1.2 \
    "$RELEASE_BASE/toggle-guard.sh" \
    -o "$GUARD" 2>/dev/null; then
    echo ">> Warning: could not download toggle-guard.sh; anti-overwrite guard NOT installed" >&2
    GUARD=""
  fi

  if [[ -n "$GUARD" ]]; then
    chmod +x "$GUARD" 2>/dev/null || true

    OS="$(uname -s)"
    if [[ "$OS" == "Linux" ]] && command -v systemctl >/dev/null 2>&1; then
      UDIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
      mkdir -p "$UDIR"

      cat > "$UDIR/opencode-toggle-guard.path" <<EOF
[Unit]
Description=Detects changes in the opencode binary (skill-toggle)

[Path]
PathChanged=%h/.opencode/bin/opencode
Unit=opencode-toggle-guard.service

[Install]
WantedBy=default.target
EOF

      cat > "$UDIR/opencode-toggle-guard.service" <<EOF
[Unit]
Description=Reinstalls skill-toggle if the opencode binary was replaced

[Service]
Type=oneshot
ExecStart=%h/.opencode/toggle-guard.sh
EOF

      cat > "$UDIR/opencode-toggle-guard.timer" <<EOF
[Unit]
Description=skill-toggle backup (every 15 min)

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
        echo ">> Anti-overwrite guard enabled (systemd --user)"
        echo ">>   - disable: systemctl --user disable --now opencode-toggle-guard.path opencode-toggle-guard.timer"
      else
        echo ">> Warning: systemd --user not available; add to cron: */15 * * * * $GUARD" >&2
      fi

    elif [[ "$OS" == "Darwin" ]]; then
      LA="$HOME/Library/LaunchAgents/com.opencode.skill-toggle-guard.plist"
      mkdir -p "$HOME/Library/LaunchAgents"
      cat > "$LA" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.opencode.skill-toggle-guard</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>$GUARD</string>
    </array>
    <key>StartInterval</key>
    <integer>900</integer>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
EOF
      launchctl unload "$LA" >/dev/null 2>&1 || true
      if launchctl load -w "$LA" >/dev/null 2>&1; then
        echo ">> Anti-overwrite guard enabled (launchd: $LA)"
        echo ">>   - disable: launchctl unload -w $LA"
      else
        echo ">> Warning: could not load LaunchAgent $LA" >&2
      fi

    else
      echo ">> Guard deployed at $GUARD but no scheduler for $OS;"
      echo ">>   add it to cron: */15 * * * * $GUARD"
    fi
  else
    echo ">> Anti-overwrite guard not installed (download failed)"
  fi
else
  echo ">> Anti-overwrite guard not installed (TOGGLE_GUARD=0)"
fi

cat <<'EOF'
Important notice:
  - This is a custom (non-official) build. It keeps your real opencode.db.
  - When downloading from GitHub Releases, the binary is verified against SHA256SUMS.
  - The anti-overwrite guard is enabled by default: it restores the toggle if the
    official update replaces it. (Alternative: "autoupdate": false in
    opencode.json disables the official autoupdate; both are explained in the
    README, Updates section.)
  - The replacement is atomic: you can reinstall even while opencode is open.
  - Automatic residue cleanup on update (removes .bak and temporary files from
    previous versions; keeps one with TOGGLE_CLEANUP_KEEP_BACKUP=1).
  - Restart opencode for the new binary to take effect.
EOF
