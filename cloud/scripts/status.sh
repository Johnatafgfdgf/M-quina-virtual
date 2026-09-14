#!/usr/bin/env bash
set -u

BASE=/tmp/maquina-virtual
PIDDIR="$BASE/pids"
SESSION="$BASE/session.json"
LOGDIR="$BASE/logs"
MODE_FILE="$BASE/desktop_mode"
DISPLAY_MODE_FILE="$BASE/display_mode"
SYSTEM_BUS_FILE="$BASE/system_bus"

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

system_bus_ok() {
  dbus-send --system --type=method_call --dest=org.freedesktop.DBus \
    / org.freedesktop.DBus.ListNames >/dev/null 2>&1
}

echo "=== Máquina Virtual ==="
for name in xvfb lxqt x11vnc websockify cloudflared; do
  check_pid "$name" || true
done

echo
echo "=== Ambiente gráfico ==="
echo "Display server: $(cat "$DISPLAY_MODE_FILE" 2>/dev/null || echo desconhecido)"
echo "Desktop:        $(cat "$MODE_FILE" 2>/dev/null || echo desconhecido)"
if system_bus_ok; then
  echo "System D-Bus:   ✅ ativo ($(cat "$SYSTEM_BUS_FILE" 2>/dev/null || echo existente))"
else
  echo "System D-Bus:   ❌ indisponível"
fi
if command -v google-chrome >/dev/null 2>&1; then
  echo "Navegador:      Google Chrome"
elif command -v epiphany >/dev/null 2>&1; then
  echo "Navegador:      GNOME Web"
elif command -v falkon >/dev/null 2>&1; then
  echo "Navegador:      Falkon"
else
  echo "Navegador:      não encontrado"
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
  VULKAN_DEVICE="$(vulkaninfo --summary 2>/dev/null | grep -m1 'deviceName' | sed 's/.*= *//' || true)"
  [ -n "$VULKAN_DEVICE" ] && echo "Vulkan: $VULKAN_DEVICE" || echo "Vulkan: não disponível"
fi

echo
echo "=== Sessão / túnel ==="
if [ -f "$SESSION" ]; then
  URL="$(python3 - <<'PY'
import json
p='/tmp/maquina-virtual/session.json'
with open(p, encoding='utf-8') as f: d=json.load(f)
print(d.get('public_url',''))
PY
)"
  python3 - <<'PY'
import json
p='/tmp/maquina-virtual/session.json'
with open(p, encoding='utf-8') as f: d=json.load(f)
print('URL:', d.get('public_url',''))
print('Resolução:', d.get('resolution',''))
print('Display:', d.get('display_mode',''))
print('Desktop:', d.get('desktop_mode',''))
print('Usuário:', d.get('session_user',''))
print('System D-Bus:', d.get('system_bus',''))
print('Túnel verificado ao criar:', d.get('tunnel_verified', False))
print('Deep link:', d.get('deep_link',''))
PY
  if [ -n "$URL" ]; then
    PUBLIC_CODE="$(curl -L -sS --max-time 8 -o /dev/null -w '%{http_code}' "${URL%/}/vnc.html" 2>/dev/null || true)"
    [[ "$PUBLIC_CODE" =~ ^2[0-9][0-9]$ ]] && echo "✅ túnel público HTTP $PUBLIC_CODE" || echo "❌ túnel público HTTP ${PUBLIC_CODE:-sem resposta}"
  fi
else
  echo "Nenhuma sessão ativa registrada."
fi

echo
echo "=== GNOME Shell ==="
if [ -s "$LOGDIR/gnome-shell.log" ]; then
  tail -n 100 "$LOGDIR/gnome-shell.log"
else
  echo "Sem saída do GNOME Shell."
fi

echo
echo "=== GNOME Flashback ==="
if [ -s "$LOGDIR/gnome-flashback.log" ]; then
  tail -n 100 "$LOGDIR/gnome-flashback.log"
else
  echo "Sem saída do GNOME Flashback."
fi

echo
echo "=== Desktop ativo / Openbox ==="
if [ -s "$LOGDIR/openbox.log" ]; then
  tail -n 50 "$LOGDIR/openbox.log"
else
  echo "Openbox não foi usado ou não gerou log."
fi

echo
echo "=== Últimas linhas do Xorg/Xvfb ==="
tail -n 40 "$LOGDIR/xvfb.log" 2>/dev/null || true

echo
echo "=== Últimas linhas do cloudflared ==="
tail -n 20 "$LOGDIR/cloudflared.log" 2>/dev/null || echo "Sem log do cloudflared."
