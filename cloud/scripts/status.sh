#!/usr/bin/env bash
set -u

BASE=/tmp/maquina-virtual
PIDDIR="$BASE/pids"
SESSION="$BASE/session.json"
PERF="$BASE/performance.json"
LOGDIR="$BASE/logs"
MODE_FILE="$BASE/desktop_mode"
DISPLAY_MODE_FILE="$BASE/display_mode"
SYSTEM_BUS_FILE="$BASE/system_bus"

pid_ok() {
  local name="$1"
  local file="$PIDDIR/$name.pid"
  [ -f "$file" ] || return 1
  local pid
  pid="$(cat "$file" 2>/dev/null || true)"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

show_pid() {
  local name="$1" label="$2"
  if pid_ok "$name"; then
    printf '✅ %-13s PID %s\n' "$label" "$(cat "$PIDDIR/$name.pid")"
  else
    printf '❌ %-13s parado\n' "$label"
  fi
}

system_bus_ok() {
  dbus-send --system --type=method_call --dest=org.freedesktop.DBus \
    / org.freedesktop.DBus.ListNames >/dev/null 2>&1
}

login1_ok() {
  command -v gdbus >/dev/null 2>&1 && \
    gdbus introspect --system --dest org.freedesktop.login1 \
      --object-path /org/freedesktop/login1 >/dev/null 2>&1
}

echo "=== Máquina Virtual · MAX ==="
show_pid xvfb display
show_pid lxqt desktop
show_pid x11vnc x11vnc
show_pid websockify websockify
show_pid cloudflared cloudflared
show_pid watchdog watchdog

echo
echo "=== Hardware real ==="
if [ -f "$PERF" ]; then
  python3 - <<'PY'
import json
p='/tmp/maquina-virtual/performance.json'
try:
    d=json.load(open(p, encoding='utf-8'))
except Exception:
    d={}
print('Perfil:         ', d.get('profile','?'))
print('CPU threads:    ', d.get('cpu_threads','?'))
print('RAM:            ', str(d.get('ram_mb','?'))+' MB')
if d.get('gpu_available'):
    print('GPU:            ', d.get('gpu_name') or 'NVIDIA')
    print('VRAM:           ', str(d.get('gpu_vram_mb','?'))+' MB')
    print('Driver NVIDIA:  ', d.get('gpu_driver') or '?')
else:
    print('GPU NVIDIA:      indisponível')
PY
else
  echo "Perfil MAX ainda não registrado."
fi

echo
echo "=== Ambiente gráfico ==="
echo "Display server: $(cat "$DISPLAY_MODE_FILE" 2>/dev/null || echo desconhecido)"
echo "Desktop:        $(cat "$MODE_FILE" 2>/dev/null || echo desconhecido)"
if system_bus_ok; then
  echo "System D-Bus:   ✅ ativo ($(cat "$SYSTEM_BUS_FILE" 2>/dev/null || echo existente))"
else
  echo "System D-Bus:   ❌ indisponível"
fi
if login1_ok; then
  echo "login1:         ✅ disponível"
else
  echo "login1:         ⚠️ indisponível (GNOME Shell moderno é evitado)"
fi

if command -v google-chrome >/dev/null 2>&1; then
  echo "Navegador:      Google Chrome"
elif command -v epiphany >/dev/null 2>&1; then
  echo "Navegador:      GNOME Web"
elif command -v falkon >/dev/null 2>&1; then
  echo "Navegador:      Falkon"
fi

echo
echo "=== Rede local ==="
ss -ltn 2>/dev/null | grep -E ':5900|:6080' || true
LOCAL_CODE="$(curl -sS --max-time 5 -o /dev/null -w '%{http_code}' http://127.0.0.1:6080/vnc.html 2>/dev/null || true)"
if [[ "$LOCAL_CODE" =~ ^2[0-9][0-9]$ ]]; then
  echo "✅ noVNC local HTTP $LOCAL_CODE"
else
  echo "❌ noVNC local HTTP ${LOCAL_CODE:-sem resposta}"
fi

echo
echo "=== Renderização ==="
if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
  nvidia-smi --query-gpu=name,memory.total,memory.free,driver_version --format=csv,noheader
else
  echo "Sem NVIDIA neste runtime."
fi
if command -v glxinfo >/dev/null 2>&1; then
  DISPLAY=:10 glxinfo -B 2>/dev/null | grep -E 'OpenGL vendor|OpenGL renderer|OpenGL version' || true
fi
if command -v vulkaninfo >/dev/null 2>&1; then
  VULKAN_DEVICE="$(vulkaninfo --summary 2>/dev/null | grep -m1 'deviceName' | sed 's/.*= *//' || true)"
  [ -n "$VULKAN_DEVICE" ] && echo "Vulkan: $VULKAN_DEVICE" || true
fi

echo
echo "=== Sessão ==="
URL=""
if [ -f "$SESSION" ]; then
  python3 - <<'PY'
import json
try:
    d=json.load(open('/tmp/maquina-virtual/session.json', encoding='utf-8'))
except Exception:
    d={}
for k,label in [('public_url','URL'),('resolution','Resolução'),('display_mode','Display'),('desktop_mode','Desktop'),('session_user','Usuário')]:
    print(f'{label}:', d.get(k,''))
print('Túnel verificado ao criar:', d.get('tunnel_verified', False))
PY
  URL="$(python3 - <<'PY'
import json
try:
 d=json.load(open('/tmp/maquina-virtual/session.json', encoding='utf-8'))
 print(d.get('public_url',''))
except Exception:
 pass
PY
)"
  if [ -n "$URL" ]; then
    PUBLIC_CODE="$(curl -L -sS --max-time 8 -o /dev/null -w '%{http_code}' "${URL%/}/vnc.html" 2>/dev/null || true)"
    [[ "$PUBLIC_CODE" =~ ^2[0-9][0-9]$ ]] && echo "✅ túnel público HTTP $PUBLIC_CODE" || echo "⚠️ túnel público HTTP ${PUBLIC_CODE:-sem resposta}"
  fi
else
  echo "Nenhuma sessão ativa registrada."
fi

if ! pid_ok lxqt; then
  echo
echo "=== Falha do desktop ==="
  tail -n 40 "$LOGDIR/gnome-flashback.log" 2>/dev/null || true
  grep -E 'CRITICAL|ERROR|login1|Segmentation|Aborted|failed|Failed' "$LOGDIR/gnome-shell.log" 2>/dev/null | tail -n 20 || true
fi

if ! pid_ok x11vnc; then
  echo
echo "=== Falha do x11vnc ==="
  tail -n 40 "$LOGDIR/x11vnc.log" 2>/dev/null || true
fi

if [ -s "$LOGDIR/watchdog.log" ]; then
  echo
echo "=== Watchdog ==="
  tail -n 12 "$LOGDIR/watchdog.log"
fi
