#!/usr/bin/env bash
#
# Installs opencode + skill-toggle (custom build of the opencode binary).
#
# Usage:
#   ./install.sh                        # uses the binary next to this script, or
#                                       # downloads it from the GitHub release
#   GH_REPO=youruser/opencode-skill-toggle ./install.sh
#   TOGGLE_GUARD=0 ./install.sh         # don't install the anti-overwrite guard
#   ./install.sh --force                # reinstall even if already up to date
#
# By default it downloads the binary from the newest versioned release and
# verifies its SHA256 (one build per tag, assets are never overwritten — avoids
# mixing old/new binaries in the CDN cache). A binary next to the script is only
# used with TOGGLE_USE_LOCAL=1 (e.g. right after running ./build.sh).
set -euo pipefail

FORCE="${TOGGLE_FORCE:-0}"
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    -h | --help) echo "Usage: install.sh [--force]"; exit 0 ;;
    *) echo "Unknown argument: $arg" >&2; exit 2 ;;
  esac
done

GH_REPO="${GH_REPO:-BenReynor/opencode-skill-toggle}"
ORIG="$HOME/.opencode/bin/opencode"
# When the script is piped (curl | bash), BASH_SOURCE[0] is not a real file:
# resolving it would point at the current directory, which must not be treated
# as the repository. Only use it when it names an actual file.
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
  SCRIPT_DIR=""
fi
# Downloads go to the temp dir: the script dir may be read-only (installing
# from /usr/local/bin, a USB stick or a read-only mount) or nonexistent when
# run via "curl | bash".
DL_DIR="${TMPDIR:-/tmp}"

# Temporary files are created with mktemp (unpredictable names) and removed on
# exit, so another local user cannot plant a symlink or leave junk behind.
CLEANUP_FILES=()
cleanup_tmp() {
  local f
  for f in "${CLEANUP_FILES[@]:-}"; do
    [[ -n "$f" ]] && rm -f "$f"
  done
}
trap cleanup_tmp EXIT

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# Scripts (guard/cleanup) are published next to the binary with their own
# checksum file. Verification is best-effort for older releases that predate
# SHA256SUMS.scripts, but a mismatch is always fatal. SCRIPT_SUMS is set after
# resolving the release (it is scoped per tag so a cached file from another
# release can never be reused).
SCRIPT_SUMS=""
ensure_script_sums() {
  [[ -s "$SCRIPT_SUMS" ]] && return 0
  local part="${SCRIPT_SUMS}.part"
  CLEANUP_FILES+=("$part")
  if curl -fsSL --proto =https --tlsv1.2 \
       "$RELEASE_BASE/SHA256SUMS.scripts" -o "$part" 2>/dev/null && [[ -s "$part" ]]; then
    mv -f "$part" "$SCRIPT_SUMS"
    return 0
  fi
  rm -f "$part"
  return 1
}
script_expected() {
  local name="$1"
  ensure_script_sums || return 0
  awk -v a="$name" '$2==a || $2=="./"a {print $1; exit}' "$SCRIPT_SUMS"
}
verify_script() {
  local name="$1" file="$2" expected actual
  if ! ensure_script_sums; then
    echo ">> warning: no SHA256SUMS.scripts in this release; $name not verified" >&2
    return 0
  fi
  expected="$(script_expected "$name")"
  if [[ -z "$expected" ]]; then
    echo ">> warning: no checksum for $name; not verified" >&2
    return 0
  fi
  actual="$(sha256_of "$file")"
  if [[ "$actual" != "$expected" ]]; then
    echo "ERROR: SHA256 verification failed for $name" >&2
    return 1
  fi
  return 0
}

download_script() {
  local name="$1" dest="$2" tmp expected
  # Idempotent: if the installed copy already matches the published checksum,
  # leave it alone (no download, no rewrite).
  expected="$(script_expected "$name" || true)"
  if [[ -n "$expected" && -f "$dest" && "$(sha256_of "$dest")" == "$expected" ]]; then
    return 0
  fi
  tmp="$(mktemp)"
  if curl -fsSL --proto =https --tlsv1.2 "$RELEASE_BASE/$name" -o "$tmp" 2>/dev/null \
     && verify_script "$name" "$tmp"; then
    mv -f "$tmp" "$dest"
    chmod +x "$dest" 2>/dev/null || true
    return 0
  fi
  rm -f "$tmp"
  return 1
}

# --- Detect platform --------------------------------------------------------
detect_platform() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"
  case "$os:$arch" in
    Linux:x86_64 | Linux:amd64)
      # musl (Alpine) and CPUs without AVX2 need their own builds: the plain
      # linux-x64 binary crashes there. (No baseline+musl build is published.)
      if ls /lib/ld-musl-*.so.1 >/dev/null 2>&1 || ldd --version 2>&1 | grep -qi musl; then
        echo "linux-x64-musl"
      elif grep -qw avx2 /proc/cpuinfo 2>/dev/null; then
        echo "linux-x64"
      else
        echo "linux-x64-baseline"
      fi
      ;;
    Linux:aarch64 | Linux:arm64)
      if ls /lib/ld-musl-*.so.1 >/dev/null 2>&1 || ldd --version 2>&1 | grep -qi musl; then
        echo "linux-arm64-musl"
      else
        echo "linux-arm64"
      fi
      ;;
    Darwin:arm64)                echo "darwin-arm64" ;;
    Darwin:x86_64)               echo "darwin-x64" ;;
    *)                           echo "unsupported:$os:$arch" ;;
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
SCRIPT_SUMS="$(mktemp "$DL_DIR/.opencode-toggle-scripts-sums.XXXXXX")"
CLEANUP_FILES+=("$SCRIPT_SUMS")
echo ">> Release: ${RELEASE_BASE#https://github.com/$GH_REPO/releases/download/}"

# --- Obtain the binary ------------------------------------------------------
# A local binary is only used on explicit request (TOGGLE_USE_LOCAL=1). The
# default is a verified download: with `curl | bash` the "local" file would come
# from whatever directory the command happened to run in.
BIN_SRC=""
BIN_DOWNLOADED=0
TARGET_HASH=""
SHA_URL="$RELEASE_BASE/SHA256SUMS"
SHA_FILE="$(mktemp "$DL_DIR/.opencode-toggle-sha256.XXXXXX")"
CLEANUP_FILES+=("$SHA_FILE")
EXPECTED=""
if curl -fsSL --proto =https --tlsv1.2 "$SHA_URL" -o "$SHA_FILE" 2>/dev/null; then
  EXPECTED="$(awk -v a="opencode-$PLATFORM" '$2==a {print $1; exit}' "$SHA_FILE")"
fi
rm -f "$SHA_FILE"

if [[ "${TOGGLE_USE_LOCAL:-0}" == "1" && -n "$SCRIPT_DIR" ]]; then
  for candidate in "$SCRIPT_DIR/opencode-$PLATFORM" "$SCRIPT_DIR/dist/opencode-$PLATFORM"; do
    if [[ -f "$candidate" ]]; then
      BIN_SRC="$candidate"
      TARGET_HASH="$(sha256_of "$candidate")"
      echo ">> Using local binary (TOGGLE_USE_LOCAL=1): $BIN_SRC"
      echo ">> warning: a local binary is not verified against the release" >&2
      break
    fi
  done
fi
if [[ -z "$BIN_SRC" ]]; then
  TARGET_HASH="$EXPECTED"
fi

CUR_HASH=""
[[ -f "$ORIG" ]] && CUR_HASH="$(sha256_of "$ORIG")"
MARKER_HASH="$(cat "$ORIG.sha256" 2>/dev/null || true)"
UP_TO_DATE=0
if [[ "$FORCE" != "1" && -n "$TARGET_HASH" && -n "$CUR_HASH" \
      && "$CUR_HASH" == "$TARGET_HASH" && "$MARKER_HASH" == "$TARGET_HASH" ]]; then
  UP_TO_DATE=1
fi

if [[ "$UP_TO_DATE" == "1" ]]; then
  echo ">> Already up to date: $ORIG (SHA256 $TARGET_HASH)"
else
  if [[ -z "$BIN_SRC" ]]; then
    URL="$RELEASE_BASE/opencode-$PLATFORM"
    echo ">> Downloading: $URL"
    BIN_SRC="$(mktemp "$DL_DIR/.opencode-toggle-$PLATFORM.XXXXXX")"
    CLEANUP_FILES+=("$BIN_SRC")
    BIN_DOWNLOADED=1
    curl -fsSL --proto =https --tlsv1.2 "$URL" -o "$BIN_SRC"

    if [[ -z "$EXPECTED" ]]; then
      if [[ "${TOGGLE_ALLOW_UNVERIFIED:-0}" == "1" ]]; then
        echo ">> warning: no checksum for opencode-$PLATFORM; continuing unverified (TOGGLE_ALLOW_UNVERIFIED=1)" >&2
      else
        echo "ERROR: no SHA256 checksum for opencode-$PLATFORM in $SHA_URL" >&2
        echo "  Refusing to install an unverified binary." >&2
        echo "  Set TOGGLE_ALLOW_UNVERIFIED=1 to override (not recommended)." >&2
        exit 1
      fi
    else
      echo ">> Verifying SHA256 against $SHA_URL"
      ACTUAL="$(sha256_of "$BIN_SRC")"
      if [[ "$ACTUAL" != "$EXPECTED" ]]; then
        echo "ERROR: SHA256 verification failed for opencode-$PLATFORM" >&2
        echo "  expected: $EXPECTED" >&2
        echo "  got: $ACTUAL" >&2
        rm -f "$BIN_SRC"
        echo "  The binary was discarded because of possible tampering." >&2
        exit 1
      fi
      echo ">> SHA256 verified correctly"
    fi
  fi
fi

# --- Backup + install -------------------------------------------------------
if [[ "$UP_TO_DATE" != "1" ]]; then
  mkdir -p "$HOME/.opencode/bin"
  if [[ -f "$ORIG" && ! -f "$ORIG.bak" ]]; then
    cp "$ORIG" "$ORIG.bak"
    echo ">> Backup saved: $ORIG.bak"
  elif [[ -f "$ORIG" ]]; then
    echo ">> Backup exists: $ORIG.bak (not overwritten)"
  fi

  # Atomic replacement (mv): does not fail with "Text file busy" even when
  # opencode is running. The running process keeps its old inode, and new
  # sessions use the new binary.
  TMP="$(mktemp "$ORIG.XXXXXX")"
  CLEANUP_FILES+=("$TMP")
  cp "$BIN_SRC" "$TMP"
  chmod +x "$TMP"
  mv -f "$TMP" "$ORIG"
  # Never delete a local build supplied through TOGGLE_USE_LOCAL.
  if [[ "$BIN_DOWNLOADED" == "1" ]]; then
    rm -f "$BIN_SRC"
  fi

  # Marker for the guard: hash of the just-installed toggle binary.
  HASH_ACTUAL="$(sha256_of "$ORIG")"
  echo "$HASH_ACTUAL" > "$ORIG.sha256"
  # Drop the guard's release cache: it may point at the previous tag, and the
  # guard would otherwise see this binary as "not published" and downgrade it.
  rm -f "$HOME/.opencode/.toggle-guard-tag" "$HOME/.opencode/.toggle-guard-sums"
fi

echo ">> opencode with skill-toggle installed: $ORIG"
echo

# --- Residue cleanup --------------------------------------------------------
# Removes backups and temporary files from previous versions on update, so
# hundreds of MB never pile up. Keeps the binary + marker.
#   - keep a single .bak of the previous one: TOGGLE_CLEANUP_KEEP_BACKUP=1
#   - dry run (list only):                   TOGGLE_CLEANUP_DRY_RUN=1
CLEANUP="$HOME/.opencode/toggle-cleanup.sh"
if [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/scripts/toggle-cleanup.sh" ]]; then
  if [[ ! -f "$CLEANUP" ]] || \
     [[ "$(sha256_of "$SCRIPT_DIR/scripts/toggle-cleanup.sh")" != "$(sha256_of "$CLEANUP")" ]]; then
    cp "$SCRIPT_DIR/scripts/toggle-cleanup.sh" "$CLEANUP"
  fi
elif ! download_script "toggle-cleanup.sh" "$CLEANUP"; then
  if [[ ! -f "$CLEANUP" ]]; then
    echo ">> Warning: could not download toggle-cleanup.sh" >&2
  else
    echo ">> Keeping the existing toggle-cleanup.sh (download failed)"
  fi
fi
if [[ -f "$CLEANUP" ]]; then
  chmod +x "$CLEANUP" 2>/dev/null || true
  # Keep the .bak: it is the only copy of the previous working binary.
  if TOGGLE_CLEANUP_KEEP_BACKUP=1 bash "$CLEANUP"; then
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
  if [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/scripts/toggle-guard.sh" ]]; then
    if [[ ! -f "$GUARD" ]] || \
       [[ "$(sha256_of "$SCRIPT_DIR/scripts/toggle-guard.sh")" != "$(sha256_of "$GUARD")" ]]; then
      cp "$SCRIPT_DIR/scripts/toggle-guard.sh" "$GUARD"
    fi
  elif ! download_script "toggle-guard.sh" "$GUARD"; then
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

# --- Uninstaller ------------------------------------------------------------
# Installed even when the guard is disabled: the slash command and the manual
# script are the supported way out of a custom build.
UNINSTALL="$HOME/.opencode/toggle-uninstall.sh"
if [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/scripts/toggle-uninstall.sh" ]]; then
  if [[ ! -f "$UNINSTALL" ]] || \
     [[ "$(sha256_of "$SCRIPT_DIR/scripts/toggle-uninstall.sh")" != "$(sha256_of "$UNINSTALL")" ]]; then
    cp "$SCRIPT_DIR/scripts/toggle-uninstall.sh" "$UNINSTALL"
  fi
elif ! download_script "toggle-uninstall.sh" "$UNINSTALL"; then
  if [[ ! -f "$UNINSTALL" ]]; then
    echo ">> Warning: could not download toggle-uninstall.sh" >&2
  fi
fi
chmod +x "$UNINSTALL" 2>/dev/null || true

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
  - Uninstall: /skill-toggle-uninstall inside opencode, or
    bash ~/.opencode/toggle-uninstall.sh
  - Restart opencode for the new binary to take effect.
EOF
