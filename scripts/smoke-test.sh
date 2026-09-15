#!/usr/bin/env bash
set -euo pipefail

debug() { echo "[smoke] $*" >&2; }

: "${PLATFORM:?PLATFORM requerido (linux-x64|darwin-x64|darwin-arm64|windows-x64)}"
: "${DOWNLOAD_BASE:?DOWNLOAD_BASE requerido}"
: "${EXPECTED_VERSION:?EXPECTED_VERSION requerido}"

case "$PLATFORM" in
  windows-x64) BIN="opencode.exe" ;;
  *)           BIN="opencode" ;;
esac

WORK="$RUNNER_TEMP/skiptest"
rm -rf "$WORK"
mkdir -p "$WORK/bin" "$WORK/proj/.opencode/skills/hello" "$WORK/home"
cd "$WORK/bin"

debug "descargando binario de $DOWNLOAD_BASE/opencode-$PLATFORM"
curl -fsSL --proto =https --tlsv1.2 "$DOWNLOAD_BASE/opencode-$PLATFORM" -o "$BIN"
chmod +x "$BIN" 2>/dev/null || true

V="$(./"$BIN" --version 2>/dev/null | head -1)"
debug "version = $V"
case "$V" in
  "$EXPECTED_VERSION"|*"$EXPECTED_VERSION"*) : ;;
  *) echo "FAIL: version inesperada '$V' (esperada $EXPECTED_VERSION)"; exit 1 ;;
esac

debug "creando skill de proyecto 'hello'"
cat > "$WORK/proj/.opencode/skills/hello/SKILL.md" <<'MD'
---
name: hello
description: Skill de prueba para validar el toggle persistente.
---
Saluda y devuelve hello-world.
MD
(
  cd "$WORK/proj"
  git init -q -b main
  git -c user.name=t -c user.email=t@t add -A
  git -c user.name=t -c user.email=t@t commit -qm init
)

debug "aislando dirs de datos/config"
export HOME="$WORK/home"
export XDG_DATA_HOME="$WORK/home/data" XDG_CONFIG_HOME="$WORK/home/config"
export LOCALAPPDATA="$WORK/home/data" APPDATA="$WORK/home/config" USERPROFILE="$WORK/home"
mkdir -p "$HOME"

PORT=4391
LOG="$WORK/serve.log"
debug "arrancando opencode serve en 127.0.0.1:$PORT"
./"$BIN" serve --port "$PORT" --log-level ERROR >"$LOG" 2>&1 &
SERVER_PID=$!
trap 'kill "$SERVER_PID" 2>/dev/null || true' EXIT

up() {
  for i in $(seq 1 30); do
    if curl -fsS --max-time 2 "http://127.0.0.1:$PORT/" >/dev/null 2>&1; then return 0; fi
    kill -0 "$SERVER_PID" 2>/dev/null || { echo "FAIL: server murió durante arranque"; tail -20 "$LOG"; return 1; }
    sleep 1
  done
  echo "FAIL: server no respondió en 30s"; cat "$LOG"; return 1
}
up

BASE="http://127.0.0.1:$PORT/skill"
status() { curl -fsSL -G --max-time 5 --data-urlencode "directory=$WORK/proj" "$BASE/status"; }
disable() { curl -fsSL -G --max-time 5 --data-urlencode "directory=$WORK/proj" -X POST "$BASE/hello/disable"; }
enable() { curl -fsSL -G --max-time 5 --data-urlencode "directory=$WORK/proj" -X POST "$BASE/hello/enable"; }

debug "1) status inicial debe incluir hello activo"
status | grep -q '"hello":true' || { echo "FAIL: hello no está activo inicialmente"; exit 1; }

debug "2) disable hello"
case "$(disable)" in
  true) : ;;
  *) echo "FAIL: disable no devolvió true"; exit 1 ;;
esac
status | grep -q '"hello":false' || { echo "FAIL: hello no quedó desactivado"; exit 1; }

debug "3) reinicio del server: el estado debe persistir desactivado"
kill "$SERVER_PID"; wait "$SERVER_PID" 2>/dev/null || true
sleep 1
./"$BIN" serve --port "$PORT" --log-level ERROR >>"$LOG" 2>&1 &
SERVER_PID=$!
trap 'kill "$SERVER_PID" 2>/dev/null || true' EXIT
up
status | grep -q '"hello":false' || { echo "FAIL: el estado desactivado no persistió tras reinicio"; exit 1; }

debug "4) enable hello"
case "$(enable)" in
  true) : ;;
  *) echo "FAIL: enable no devolvió true"; exit 1 ;;
esac
status | grep -q '"hello":true' || { echo "FAIL: hello no quedó activado"; exit 1; }

kill "$SERVER_PID" 2>/dev/null || true
wait "$SERVER_PID" 2>/dev/null || true
echo "[smoke] OK en $PLATFORM (version $EXPECTED_VERSION)"