#!/usr/bin/env bash
set -u

BASE=/tmp/maquina-virtual
PIDDIR="$BASE/pids"
SESSION="$BASE/session.json"

check_pid() {
  local name="$1"
  local file="$PIDDIR/$name.pid"
  if [ -f "$file" ]; then
    local pid
    pid="$(cat "$file" 2>/dev/null || true)"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      printf '✅ %-12s PID %s\n' "$name" "$pid"
      return
    fi
  fi
  printf '❌ %-12s parado\n' "$name"
}

echo "=== Máquina Virtual ==="
for name in xvfb lxqt x11vnc websockify cloudflared; do
  check_pid "$name"
done

echo
echo "=== Portas locais ==="
ss -ltn 2>/dev/null | grep -E ':5900|:6080' || true

echo
echo "=== GPU ==="
if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
  nvidia-smi --query-gpu=name,memory.total,memory.free --format=csv,noheader
else
  echo "Nenhuma GPU NVIDIA disponível neste runtime."
fi

echo
echo "=== Sessão ==="
if [ -f "$SESSION" ]; then
  python3 - <<'PY'
import json
p='/tmp/maquina-virtual/session.json'
with open(p, encoding='utf-8') as f:
    d=json.load(f)
print('URL:', d.get('public_url',''))
print('Resolução:', d.get('resolution',''))
print('Deep link:', d.get('deep_link',''))
PY
else
  echo "Nenhuma sessão ativa registrada."
fi
