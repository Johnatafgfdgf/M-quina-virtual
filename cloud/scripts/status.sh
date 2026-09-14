#!/usr/bin/env bash
set -u

BASE=/tmp/maquina-virtual
PIDDIR="$BASE/pids"
SESSION="$BASE/session.json"
LOGDIR="$BASE/logs"
MODE_FILE="$BASE/desktop_mode"

check_pid() {
  local name="$1"
  local file="$PIDDIR/$name.pid"
  if [ -f "$file" ]; then
    local pid
    pid="$(cat "$file" 2>/dev/null || true)"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      printf '✅ %-12s PID %s\n' "$name" "$pid"
      return 0
    fi
  fi
  printf '❌ %-12s parado\n' "$name"
  return 1
}

echo "=== Máquina Virtual ==="
for name in xvfb lxqt x11vnc websockify cloudflared; do
  check_pid "$name" || true
done

if [ -f "$MODE_FILE" ]; then
  echo "Desktop: $(cat "$MODE_FILE")"
fi

echo
echo "=== Portas locais ==="
ss -ltn 2>/dev/null | grep -E ':5900|:6080' || true

LOCAL_CODE="$(curl -sS --max-time 5 -o /dev/null -w '%{http_code}' http://127.0.0.1:6080/vnc.html 2>/dev/null || true)"
if [[ "$LOCAL_CODE" =~ ^2[0-9][0-9]$ ]]; then
  echo "✅ noVNC local HTTP $LOCAL_CODE"
else
  echo "❌ noVNC local HTTP ${LOCAL_CODE:-sem resposta}"
fi

echo
echo "=== GPU / gráficos ==="
if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
  nvidia-smi --query-gpu=name,memory.total,memory.free,driver_version --format=csv,noheader
else
  echo "Nenhuma GPU NVIDIA disponível neste runtime."
fi
if command -v glxinfo >/dev/null 2>&1; then
  DISPLAY=:10 glxinfo -B 2>/dev/null | grep -E 'OpenGL vendor|OpenGL renderer|OpenGL core profile version|OpenGL version' || true
fi
if command -v vulkaninfo >/dev/null 2>&1; then
  echo "Vulkan tool: instalado"
fi

echo
echo "=== Sessão / túnel ==="
if [ -f "$SESSION" ]; then
  URL="$(python3 - <<'PY'
import json
p='/tmp/maquina-virtual/session.json'
with open(p, encoding='utf-8') as f:
    d=json.load(f)
print(d.get('public_url',''))
PY
)"
  python3 - <<'PY'
import json
p='/tmp/maquina-virtual/session.json'
with open(p, encoding='utf-8') as f:
    d=json.load(f)
print('URL:', d.get('public_url',''))
print('Resolução:', d.get('resolution',''))
print('Desktop:', d.get('desktop_mode',''))
print('Usuário:', d.get('session_user',''))
print('Túnel verificado ao criar:', d.get('tunnel_verified', False))
print('Deep link:', d.get('deep_link',''))
PY
  if [ -n "$URL" ]; then
    PUBLIC_CODE="$(curl -L -sS --max-time 8 -o /dev/null -w '%{http_code}' "${URL%/}/vnc.html" 2>/dev/null || true)"
    if [[ "$PUBLIC_CODE" =~ ^2[0-9][0-9]$ ]]; then
      echo "✅ túnel público HTTP $PUBLIC_CODE"
    else
      echo "❌ túnel público HTTP ${PUBLIC_CODE:-sem resposta}"
    fi
  fi
else
  echo "Nenhuma sessão ativa registrada."
fi

echo
echo "=== Últimas linhas do desktop ==="
tail -n 30 "$LOGDIR/lxqt.log" 2>/dev/null || echo "Sem log do desktop."

echo
echo "=== Últimas linhas do cloudflared ==="
tail -n 25 "$LOGDIR/cloudflared.log" 2>/dev/null || echo "Sem log do cloudflared."
