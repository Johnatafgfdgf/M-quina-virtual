#!/usr/bin/env bash
set -u

BASE=/tmp/maquina-virtual
PIDDIR="$BASE/pids"
SESSION_USER="${SESSION_USER:-mvuser}"

stop_one() {
  local name="$1"
  local file="$PIDDIR/$name.pid"
  [ -f "$file" ] || return 0
  local pid
  pid="$(cat "$file" 2>/dev/null || true)"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    kill -- "-$pid" 2>/dev/null || kill "$pid" 2>/dev/null || true
    sleep 0.5
    if kill -0 "$pid" 2>/dev/null; then
      kill -9 -- "-$pid" 2>/dev/null || kill -9 "$pid" 2>/dev/null || true
    fi
  fi
  rm -f "$file"
}

# Watchdog primeiro para ele não tentar ressuscitar serviços enquanto paramos.
for name in watchdog cloudflared websockify x11vnc tint2 lxqt xvfb; do
  stop_one "$name"
done

if id -u "$SESSION_USER" >/dev/null 2>&1; then
  pkill -TERM -u "$SESSION_USER" >/dev/null 2>&1 || true
  sleep 0.3
  pkill -KILL -u "$SESSION_USER" >/dev/null 2>&1 || true
fi

rm -f \
  "$BASE/session.json" \
  "$BASE/vnc.pass" \
  "$BASE/desktop_mode" \
  "$BASE/display_mode" \
  "$BASE/gpu_mode"
echo "[Máquina Virtual] Sessão encerrada."
