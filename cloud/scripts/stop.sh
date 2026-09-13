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
    # start.sh cria cada serviço em uma sessão/grupo próprio via setsid.
    # Encerrar o grupo evita deixar processos filhos órfãos (ex.: dbus/LXQt).
    kill -- "-$pid" 2>/dev/null || kill "$pid" 2>/dev/null || true
    sleep 0.4
    if kill -0 "$pid" 2>/dev/null; then
      kill -9 -- "-$pid" 2>/dev/null || kill -9 "$pid" 2>/dev/null || true
    fi
  fi
  rm -f "$file"
}

for name in cloudflared websockify x11vnc lxqt xvfb; do
  stop_one "$name"
done

rm -f "$BASE/session.json" "$BASE/vnc.pass"
echo "[Máquina Virtual] Sessão encerrada."
