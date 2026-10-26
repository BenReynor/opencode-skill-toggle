#!/usr/bin/env bash
set -euo pipefail

debug() { echo "[smoke] $*" >&2; }

: "${PLATFORM:?PLATFORM required (linux-x64|darwin-x64|darwin-arm64|windows-x64)}"
: "${DOWNLOAD_BASE:?DOWNLOAD_BASE required}"
: "${EXPECTED_VERSION:?EXPECTED_VERSION required}"

case "$PLATFORM" in
  windows-x64) NAME="opencode.exe" ;;
  *)           NAME="opencode" ;;
esac

WORK="$RUNNER_TEMP/skiptest"
rm -rf "$WORK"
mkdir -p "$WORK/bin" "$WORK/proj/.opencode/skills/hello" "$WORK/proj/.opencode/skills/hello2" "$WORK/proj/.opencode/skills/hello3"
BIN="$WORK/bin/$NAME"

debug "downloading binary from $DOWNLOAD_BASE/opencode-$PLATFORM"
curl -fsSL --proto =https --tlsv1.2 "$DOWNLOAD_BASE/opencode-$PLATFORM" -o "$BIN"
chmod +x "$BIN" 2>/dev/null || true

V="$("$BIN" --version 2>/dev/null | head -1)"
debug "version = $V"
case "$V" in
  "$EXPECTED_VERSION"|*"$EXPECTED_VERSION"*) : ;;
  *) echo "FAIL: unexpected version '$V' (expected $EXPECTED_VERSION)"; exit 1 ;;
esac

debug "creating project skill 'hello'"
cat > "$WORK/proj/.opencode/skills/hello/SKILL.md" <<'MD'
---
name: hello
description: Test skill to validate the per-session toggle.
---
Say hello and return hello-world.
MD

for extra in hello2 hello3; do
  printf -- '---\nname: %s\ndescription: Extra skill for the concurrency test.\n---\nSay hi.\n' "$extra" \
    > "$WORK/proj/.opencode/skills/$extra/SKILL.md"
done

export HOME="$WORK/home"
export XDG_DATA_HOME="$WORK/home/data" XDG_CONFIG_HOME="$WORK/home/config"
export LOCALAPPDATA="$WORK/home/data" APPDATA="$WORK/home/config" USERPROFILE="$WORK/home"
export OPENCODE_DISABLE_AUTOUPDATE=1
mkdir -p "$HOME"

PORT=4391
LOG="$WORK/serve.log"
cd "$WORK/proj"

start_server() {
  debug "starting opencode serve on 127.0.0.1:$PORT"
  "$BIN" serve --port "$PORT" --log-level ERROR >>"$LOG" 2>&1 &
  SERVER_PID=$!
  trap 'kill "$SERVER_PID" 2>/dev/null || true' EXIT
  for _ in $(seq 1 60); do
    if curl -fsS --max-time 2 "http://127.0.0.1:$PORT/global/health" >/dev/null 2>&1; then return 0; fi
    kill -0 "$SERVER_PID" 2>/dev/null || { echo "FAIL: server died during startup"; tail -20 "$LOG"; return 1; }
    sleep 1
  done
  echo "FAIL: server did not respond within 60s"; cat "$LOG"; return 1
}
start_server

BASE="http://127.0.0.1:$PORT"
api() { curl -fsSL --max-time 5 "$@"; }
status() { if [ -n "${1:-}" ]; then api "$BASE/skill/status?session=$1"; else api "$BASE/skill/status"; fi; }
enable() { api -X POST "$BASE/skill/$1/enable?session=$2"; }
disable() { api -X POST "$BASE/skill/$1/disable?session=$2"; }
list() { if [ -n "${1:-}" ]; then api "$BASE/skill?session=$1"; else api "$BASE/skill"; fi; }
has() { printf '%s' "$1" | grep -q "$2"; }
session_id() { sed -nE 's/.*"id"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' | head -1; }

S1="$(api -X POST "$BASE/session" -H 'content-type: application/json' -d '{}' | session_id)"
S2="$(api -X POST "$BASE/session" -H 'content-type: application/json' -d '{}' | session_id)"
[ -n "$S1" ] && [ -n "$S2" ] || { echo "FAIL: could not create sessions (got '$S1' / '$S2')"; exit 1; }
debug "sessions: $S1 $S2"

debug "1) defaults: only the built-in skill is enabled"
BODY="$(status)"
has "$BODY" '"hello":false' || { echo "FAIL: hello should be disabled by default"; exit 1; }
has "$BODY" '"customize-opencode":true' || { echo "FAIL: built-in skill should be enabled"; exit 1; }

debug "2) a new session starts with hello disabled"
BODY="$(status "$S1")"
has "$BODY" '"hello":false' || { echo "FAIL: hello should be disabled in a new session"; exit 1; }
BODY="$(list "$S1")"
if has "$BODY" '"name":"hello"'; then echo "FAIL: a disabled skill must not be listed as available"; exit 1; fi
has "$BODY" 'customize-opencode' || { echo "FAIL: the built-in skill must stay available"; exit 1; }

debug "3) enable hello in session 1 only"
case "$(enable hello "$S1")" in true) : ;; *) echo "FAIL: enable did not return true"; exit 1 ;; esac
BODY="$(status "$S1")"
has "$BODY" '"hello":true' || { echo "FAIL: hello is not enabled in session 1"; exit 1; }
BODY="$(list "$S1")"
has "$BODY" '"name":"hello"' || { echo "FAIL: the enabled skill is not listed"; exit 1; }
BODY="$(status "$S2")"
has "$BODY" '"hello":false' || { echo "FAIL: session 2 must not inherit session 1's change"; exit 1; }
BODY="$(status)"
has "$BODY" '"hello":false' || { echo "FAIL: defaults must not change when a session is toggled"; exit 1; }

debug "4) state persists across a server restart"
kill "$SERVER_PID"; wait "$SERVER_PID" 2>/dev/null || true
sleep 1
start_server
BODY="$(status "$S1")"
has "$BODY" '"hello":true' || { echo "FAIL: session 1 lost its state after restart"; exit 1; }
BODY="$(status "$S2")"
has "$BODY" '"hello":false' || { echo "FAIL: session 2 state changed after restart"; exit 1; }

debug "5) disable hello in session 1"
case "$(disable hello "$S1")" in true) : ;; *) echo "FAIL: disable did not return true"; exit 1 ;; esac
BODY="$(status "$S1")"
has "$BODY" '"hello":false' || { echo "FAIL: hello is still enabled in session 1"; exit 1; }

debug "6) the built-in skill cannot be disabled"
case "$(disable customize-opencode "$S1")" in true) echo "FAIL: disabling the built-in skill must return false"; exit 1 ;; *) : ;; esac
BODY="$(status "$S1")"
has "$BODY" '"customize-opencode":true' || { echo "FAIL: the built-in skill was disabled"; exit 1; }

debug "7) a disabled skill's slash command is rejected"
HTTP="$(curl -s --max-time 10 -o /dev/null -w '%{http_code}' -X POST "$BASE/session/$S2/command" \
  -H 'content-type: application/json' -d '{"command":"hello","arguments":""}')"
case "$HTTP" in
  2*) echo "FAIL: a disabled skill's command was accepted (HTTP $HTTP)"; exit 1 ;;
  "" | 000*) echo "FAIL: the command request failed (no HTTP response)"; exit 1 ;;
esac

debug "8) state file uses the per-session format"
STATE="$XDG_DATA_HOME/opencode/skills-toggle.json"
[ -f "$STATE" ] || { echo "FAIL: $STATE was not created"; exit 1; }
grep -q '"version": *2' "$STATE" || { echo "FAIL: state file is not version 2"; exit 1; }
grep -q "$S1" "$STATE" || { echo "FAIL: session $S1 is not recorded in the state file"; exit 1; }

debug "9) invalid skill names and session ids are rejected, never stored"
case "$(enable toString "$S1")" in true) echo "FAIL: an inherited property name was accepted as a skill"; exit 1 ;; esac
case "$(enable nosuchskill "$S1")" in true) echo "FAIL: an unknown skill was enabled"; exit 1 ;; esac
case "$(enable hello nope_123)" in true) echo "FAIL: an unknown session id was accepted"; exit 1 ;; esac
case "$(enable hello ses_doesnotexist0000)" in true) echo "FAIL: a session that does not exist was accepted"; exit 1 ;; esac
case "$(enable hello __proto__)" in true) echo "FAIL: __proto__ was accepted as a session id"; exit 1 ;; esac
for bad in toString nope_123 ses_doesnotexist0000 __proto__; do
  if grep -q "\"$bad\"" "$STATE"; then echo "FAIL: '$bad' was written to the state file"; exit 1; fi
done

debug "10) a subagent (child) session inherits its parent's skills"
enable hello "$S1" >/dev/null
CHILD="$(api -X POST "$BASE/session" -H 'content-type: application/json' -d "{\"parentID\":\"$S1\"}" | session_id)"
[ -n "$CHILD" ] || { echo "FAIL: could not create a child session"; exit 1; }
has "$(status "$CHILD")" '"hello":true' || { echo "FAIL: the child session did not inherit hello"; exit 1; }
has "$(status "$CHILD")" '"hello2":false' || { echo "FAIL: the child session enabled a skill its parent does not have"; exit 1; }

debug "11) parallel toggles on one session are not lost"
S3="$(api -X POST "$BASE/session" -H 'content-type: application/json' -d '{}' | session_id)"
for round in 1 2 3; do
  pids=()
  for sk in hello hello2 hello3; do api -X POST "$BASE/skill/$sk/enable?session=$S3" >/dev/null & pids+=("$!"); done
  wait "${pids[@]}"
  BODY="$(status "$S3")"
  for sk in hello hello2 hello3; do has "$BODY" "\"$sk\":true" || { echo "FAIL: parallel enable of $sk was lost (round $round): $BODY"; exit 1; }; done
  pids=()
  for sk in hello hello2 hello3; do api -X POST "$BASE/skill/$sk/disable?session=$S3" >/dev/null & pids+=("$!"); done
  wait "${pids[@]}"
  BODY="$(status "$S3")"
  for sk in hello hello2 hello3; do has "$BODY" "\"$sk\":false" || { echo "FAIL: parallel disable of $sk was lost (round $round): $BODY"; exit 1; }; done
done

debug "12) two opencode processes sharing the state file do not lose each other's changes"
PORT2=$((PORT + 1))
"$BIN" serve --port "$PORT2" --log-level ERROR >>"$LOG" 2>&1 &
SERVER2_PID=$!
trap 'kill "$SERVER_PID" "$SERVER2_PID" 2>/dev/null || true' EXIT
for _ in $(seq 1 60); do curl -fs --max-time 2 "http://127.0.0.1:$PORT2/global/health" >/dev/null 2>&1 && break; sleep 1; done
BASE2="http://127.0.0.1:$PORT2"
S4="$(api -X POST "$BASE2/session" -H 'content-type: application/json' -d '{}' | session_id)"
for round in 1 2 3; do
  pids=()
  for sk in hello hello2 hello3; do
    api -X POST "$BASE/skill/$sk/enable?session=$S3" >/dev/null & pids+=("$!")
    api -X POST "$BASE2/skill/$sk/enable?session=$S4" >/dev/null & pids+=("$!")
  done
  wait "${pids[@]}"
  for target in "$BASE $S3" "$BASE2 $S4"; do
    set -- $target
    BODY="$(api "$1/skill/status?session=$2")"
    for sk in hello hello2 hello3; do has "$BODY" "\"$sk\":true" || { echo "FAIL: cross-process enable of $sk lost on $2 (round $round): $BODY"; exit 1; }; done
  done
  pids=()
  for sk in hello hello2 hello3; do
    api -X POST "$BASE/skill/$sk/disable?session=$S3" >/dev/null & pids+=("$!")
    api -X POST "$BASE2/skill/$sk/disable?session=$S4" >/dev/null & pids+=("$!")
  done
  wait "${pids[@]}"
done
kill "$SERVER2_PID" 2>/dev/null || true
wait "$SERVER2_PID" 2>/dev/null || true

debug "13) a state file from a newer version or a corrupt one is backed up, not destroyed"
kill "$SERVER_PID"; wait "$SERVER_PID" 2>/dev/null || true
sleep 1
FUTURE='{"version":3,"sessions":{"ses_future1":{"enabled":{"hello":true},"touchedAt":1}}}'
printf '%s' "$FUTURE" > "$STATE"
start_server
status >/dev/null
[ -f "$STATE.v3.bak" ] && [ "$(cat "$STATE.v3.bak")" = "$FUTURE" ] || { echo "FAIL: a version-3 state file was not backed up"; exit 1; }
kill "$SERVER_PID"; wait "$SERVER_PID" 2>/dev/null || true
sleep 1
printf '{ "version": 2, "sessions": {' > "$STATE"
start_server
status >/dev/null
[ -f "$STATE.corrupt.bak" ] || { echo "FAIL: a corrupt state file was not backed up"; exit 1; }

kill "$SERVER_PID" 2>/dev/null || true
wait "$SERVER_PID" 2>/dev/null || true
echo "[smoke] OK on $PLATFORM (version $EXPECTED_VERSION)"
