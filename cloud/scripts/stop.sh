#!/usr/bin/env bash
set -u

BASE=/tmp/maquina-virtual
PIDDIR="$BASE/pids"

stop_one() {
  local name="$1"
  local file="$PIDDIR/$name.pid"
  [ -f "$file" ] || return 0
  local pid
  pid="$(cat "$file" 2>/dev/null || true)"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    sleep 0.3
    kill -9 "$pid" 2>/dev/null || true
  fi
  rm -f "$file"
}

for name in cloudflared websockify x11vnc lxqt xvfb; do
  stop_one "$name"
done

rm -f "$BASE/session.json"
echo "[Máquina Virtual] Sessão encerrada."
