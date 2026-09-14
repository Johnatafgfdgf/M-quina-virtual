#!/usr/bin/env bash
set -euo pipefail

RESOLUTION="${1:-1600x720}"
PASSWORD="${2:-}"
SESSION_USER="${SESSION_USER:-mvuser}"
DISPLAY_NUM="${DISPLAY_NUM:-10}"
DISPLAY=":${DISPLAY_NUM}"
VNC_PORT="${VNC_PORT:-5900}"
NOVNC_PORT="${NOVNC_PORT:-6080}"
BASE=/tmp/maquina-virtual
LOGDIR="$BASE/logs"
PIDDIR="$BASE/pids"
SESSION_FILE="$BASE/session.json"
DISPLAY_MODE_FILE="$BASE/display_mode"
SYSTEM_BUS_FILE="$BASE/system_bus"
GPU_MODE_FILE="$BASE/gpu_mode"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$LOGDIR" "$PIDDIR"
chmod 700 "$BASE"

if [[ ! "$RESOLUTION" =~ ^[0-9]+x[0-9]+$ ]]; then
  echo "Resolução inválida: $RESOLUTION" >&2
  exit 2
fi
WIDTH="${RESOLUTION%x*}"
HEIGHT="${RESOLUTION#*x}"
if [ "$WIDTH" -lt 800 ] || [ "$HEIGHT" -lt 480 ] || [ "$WIDTH" -gt 3840 ] || [ "$HEIGHT" -gt 2160 ]; then
  echo "Resolução fora do intervalo suportado: $RESOLUTION" >&2
  exit 2
fi

if [ -z "$PASSWORD" ]; then
  PASSWORD="$(python3 - <<'PY'
import secrets, string
alphabet = string.ascii_letters + string.digits
print(''.join(secrets.choice(alphabet) for _ in range(8)))
PY
)"
fi
PASSWORD="${PASSWORD:0:8}"

# MAX é padrão. performance.sh apenas detecta/expõe recursos; não modifica este arquivo.
if [ "${MV_PERFORMANCE_PROFILE:-}" != "max" ] && [ -f "$SCRIPT_DIR/performance.sh" ]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/performance.sh"
fi
GPU_AVAILABLE="${MV_GPU_AVAILABLE:-0}"
echo "$GPU_AVAILABLE" > "$GPU_MODE_FILE"

bash "$SCRIPT_DIR/stop.sh" >/dev/null 2>&1 || true
mkdir -p "$LOGDIR" "$PIDDIR"
: > "$LOGDIR/gnome-shell.log"
: > "$LOGDIR/gnome-flashback.log"
: > "$LOGDIR/openbox.log"

if ! id -u "$SESSION_USER" >/dev/null 2>&1; then
  echo "Usuário gráfico '$SESSION_USER' não existe. Execute install.sh primeiro." >&2
  exit 3
fi
SESSION_HOME="$(getent passwd "$SESSION_USER" | cut -d: -f6)"
RUNTIME_DIR="/tmp/runtime-$SESSION_USER"
mkdir -p "$RUNTIME_DIR"
chown "$SESSION_USER:$SESSION_USER" "$RUNTIME_DIR"
chmod 700 "$RUNTIME_DIR"
printf '%s:%s\n' "$SESSION_USER" "$PASSWORD" | chpasswd

export DISPLAY

spawn() {
  local name="$1"
  shift
  setsid nohup "$@" >"$LOGDIR/$name.log" 2>&1 < /dev/null &
  echo $! > "$PIDDIR/$name.pid"
}

spawn_user_log() {
  local pid_name="$1"
  local log_name="$2"
  shift 2
  setsid nohup runuser -u "$SESSION_USER" -- env \
    HOME="$SESSION_HOME" USER="$SESSION_USER" LOGNAME="$SESSION_USER" \
    DISPLAY="$DISPLAY" XDG_RUNTIME_DIR="$RUNTIME_DIR" \
    XDG_SESSION_TYPE=x11 XDG_SESSION_CLASS=user GDK_BACKEND=x11 \
    DBUS_SYSTEM_BUS_ADDRESS=unix:path=/run/dbus/system_bus_socket \
    NO_AT_BRIDGE=1 \
    "$@" >"$LOGDIR/$log_name.log" 2>&1 < /dev/null &
  echo $! > "$PIDDIR/$pid_name.pid"
}

stop_proc() {
  local name="$1"
  local pidfile="$PIDDIR/$name.pid"
  [ -f "$pidfile" ] || return 0
  local pid
  pid="$(cat "$pidfile" 2>/dev/null || true)"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
    sleep 0.6
    if kill -0 "$pid" 2>/dev/null; then
      kill -KILL -- "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
    fi
  fi
  rm -f "$pidfile"
}

pid_alive() {
  local name="$1"
  local pidfile="$PIDDIR/$name.pid"
  [ -f "$pidfile" ] || return 1
  local pid
  pid="$(cat "$pidfile" 2>/dev/null || true)"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

system_bus_ok() {
  dbus-send --system --type=method_call \
    --dest=org.freedesktop.DBus / org.freedesktop.DBus.ListNames \
    >/dev/null 2>&1
}

login1_ok() {
  command -v gdbus >/dev/null 2>&1 || return 1
  gdbus introspect --system \
    --dest org.freedesktop.login1 \
    --object-path /org/freedesktop/login1 \
    >/dev/null 2>&1
}

ensure_system_bus() {
  dbus-uuidgen --ensure=/etc/machine-id >/dev/null 2>&1 || true
  mkdir -p /run/dbus /var/lib/dbus
  if [ ! -e /var/lib/dbus/machine-id ]; then
    ln -s /etc/machine-id /var/lib/dbus/machine-id 2>/dev/null || \
      cp /etc/machine-id /var/lib/dbus/machine-id 2>/dev/null || true
  fi

  if system_bus_ok; then
    echo "ready" > "$SYSTEM_BUS_FILE"
    return 0
  fi

  if command -v systemctl >/dev/null 2>&1; then
    timeout 5s systemctl start dbus.service >/dev/null 2>&1 || true
    timeout 5s systemctl start systemd-logind.service >/dev/null 2>&1 || true
    timeout 5s systemctl start polkit.service >/dev/null 2>&1 || true
  fi

  if system_bus_ok; then
    echo "ready-systemd" > "$SYSTEM_BUS_FILE"
    return 0
  fi

  rm -f /run/dbus/system_bus_socket /run/dbus/pid 2>/dev/null || true
  if command -v dbus-daemon >/dev/null 2>&1; then
    dbus-daemon --system --fork --nopidfile >"$LOGDIR/system-dbus.log" 2>&1 || true
  fi
  for _ in $(seq 1 30); do
    if system_bus_ok; then
      echo "ready-manual" > "$SYSTEM_BUS_FILE"
      return 0
    fi
    sleep 0.1
  done

  echo "unavailable" > "$SYSTEM_BUS_FILE"
  return 1
}

wait_display() {
  local attempts="${1:-60}"
  for _ in $(seq 1 "$attempts"); do
    if DISPLAY="$DISPLAY" xdpyinfo >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.25
  done
  return 1
}

wait_port() {
  local port="$1"
  local attempts="${2:-40}"
  for _ in $(seq 1 "$attempts"); do
    if ss -ltn 2>/dev/null | grep -qE "127\\.0\\.0\\.1:${port}|\\[::1\\]:${port}"; then
      return 0
    fi
    sleep 0.25
  done
  return 1
}

public_ok() {
  local url="$1"
  local code
  code="$(curl -L -sS --max-time 8 -o /dev/null -w '%{http_code}' "${url%/}/vnc.html" 2>/dev/null || true)"
  [[ "$code" =~ ^2[0-9][0-9]$ ]]
}

start_xorg_nvidia() {
  [ "$GPU_AVAILABLE" = "1" ] || return 1
  command -v Xorg >/dev/null 2>&1 || return 1
  command -v nvidia-smi >/dev/null 2>&1 || return 1

  local pci_raw xorg_bus conf
  pci_raw="$(nvidia-smi --query-gpu=pci.bus_id --format=csv,noheader 2>/dev/null | head -n1 | xargs || true)"
  [ -n "$pci_raw" ] || return 1
  xorg_bus="$(python3 - "$pci_raw" <<'PY'
import sys
s=sys.argv[1].strip()
try:
    parts=s.split(':')
    bus=int(parts[-2],16)
    dev,func=parts[-1].split('.')
    print(f'PCI:{bus}:{int(dev,16)}:{int(func,16)}')
except Exception:
    pass
PY
)"
  [ -n "$xorg_bus" ] || return 1

  conf="$BASE/xorg-nvidia.conf"
  cat > "$conf" <<EOF
Section "ServerFlags"
    Option "AutoAddDevices" "false"
    Option "DontVTSwitch" "true"
    Option "AllowMouseOpenFail" "true"
EndSection
Section "Device"
    Identifier "NvidiaCard"
    Driver "nvidia"
    BusID "$xorg_bus"
    Option "AllowEmptyInitialConfiguration" "True"
    Option "UseDisplayDevice" "None"
    Option "HardDPMS" "False"
EndSection
Section "Screen"
    Identifier "NvidiaScreen"
    Device "NvidiaCard"
    DefaultDepth 24
    SubSection "Display"
        Depth 24
        Virtual $WIDTH $HEIGHT
    EndSubSection
EndSection
Section "ServerLayout"
    Identifier "NvidiaLayout"
    Screen "NvidiaScreen"
EndSection
EOF

  echo "  tentando Xorg NVIDIA headless..."
  spawn xvfb Xorg "$DISPLAY" -config "$conf" -noreset -nolisten tcp -ac \
    +extension GLX +extension RANDR +extension RENDER +extension XTEST
  if wait_display 100; then
    if DISPLAY="$DISPLAY" glxinfo -B 2>/dev/null | grep -qi 'NVIDIA'; then
      echo "xorg-nvidia" > "$DISPLAY_MODE_FILE"
      return 0
    fi
  fi
  stop_proc xvfb || true
  return 1
}

start_xorg_dummy() {
  command -v Xorg >/dev/null 2>&1 || return 1
  command -v cvt >/dev/null 2>&1 || return 1
  local model_line mode_name conf
  model_line="$(cvt "$WIDTH" "$HEIGHT" 60 2>/dev/null | sed -n 's/^Modeline[[:space:]]*//p' | head -n1)"
  [ -n "$model_line" ] || return 1
  mode_name="$(printf '%s\n' "$model_line" | awk '{gsub(/\"/,"",$1); print $1}')"
  [ -n "$mode_name" ] || return 1
  conf="$BASE/xorg-dummy.conf"
  cat > "$conf" <<EOF
Section "ServerFlags"
    Option "AutoAddDevices" "false"
    Option "DontVTSwitch" "true"
    Option "AllowMouseOpenFail" "true"
EndSection
Section "Device"
    Identifier "DummyDevice"
    Driver "dummy"
    VideoRam 256000
EndSection
Section "Monitor"
    Identifier "DummyMonitor"
    HorizSync 28.0-100.0
    VertRefresh 40.0-90.0
    Modeline $model_line
EndSection
Section "Screen"
    Identifier "DummyScreen"
    Device "DummyDevice"
    Monitor "DummyMonitor"
    DefaultDepth 24
    SubSection "Display"
        Depth 24
        Modes "$mode_name"
        Virtual $WIDTH $HEIGHT
    EndSubSection
EndSection
Section "ServerLayout"
    Identifier "DummyLayout"
    Screen "DummyScreen"
EndSection
EOF
  echo "  tentando Xorg Dummy..."
  spawn xvfb Xorg "$DISPLAY" -config "$conf" -noreset -nolisten tcp -ac \
    +extension GLX +extension RANDR +extension RENDER +extension XTEST
  if wait_display 80; then
    echo "xorg-dummy" > "$DISPLAY_MODE_FILE"
    return 0
  fi
  stop_proc xvfb || true
  return 1
}

echo "[0/5] Preparando D-Bus do sistema..."
if ensure_system_bus; then
  echo "  system D-Bus: $(cat "$SYSTEM_BUS_FILE")"
else
  echo "  aviso: system D-Bus indisponível; usando fallbacks compatíveis."
fi

echo "[1/5] Iniciando display virtual..."
if ! start_xorg_nvidia; then
  if ! start_xorg_dummy; then
    echo "  Xorg falhou; usando Xvfb."
    spawn xvfb Xvfb "$DISPLAY" -screen 0 "${WIDTH}x${HEIGHT}x24" \
      -nolisten tcp -ac -noreset \
      +extension RANDR +extension RENDER +extension XTEST +extension GLX
    if ! wait_display 60; then
      echo "Nenhum display virtual conseguiu iniciar." >&2
      tail -n 60 "$LOGDIR/xvfb.log" >&2 || true
      exit 4
    fi
    echo "xvfb" > "$DISPLAY_MODE_FILE"
  fi
fi

echo "  display ativo: $(cat "$DISPLAY_MODE_FILE")"
DISPLAY="$DISPLAY" xhost +SI:localuser:"$SESSION_USER" >/dev/null 2>&1 || true

# O layout do Flashback é preparado antes do painel iniciar. Nunca mais usamos
# gnome-panel --replace depois do boot, porque isso encerrava a sessão inteira.
bash "$SCRIPT_DIR/theme.sh" "$RESOLUTION" "$SESSION_USER" pre >"$LOGDIR/theme-pre.log" 2>&1 || true

echo "[2/5] Iniciando ambiente gráfico..."
DESKTOP_MODE=""

start_gnome_shell() {
  [ -x /usr/bin/gnome-session ] || return 1
  [ -f /usr/share/gnome-session/sessions/gnome.session ] || return 1
  echo "  tentando GNOME Shell..."
  spawn_user_log lxqt gnome-shell env \
    XDG_CURRENT_DESKTOP=GNOME \
    XDG_SESSION_DESKTOP=gnome \
    DESKTOP_SESSION=gnome \
    GDMSESSION=gnome \
    GNOME_SHELL_SESSION_MODE=gnome \
    XDG_MENU_PREFIX=gnome- \
    dbus-launch --exit-with-session \
    /usr/bin/gnome-session --disable-acceleration-check --debug --session=gnome

  for _ in $(seq 1 100); do
    if pgrep -u "$SESSION_USER" -x gnome-shell >/dev/null 2>&1; then
      sleep 3
      if pgrep -u "$SESSION_USER" -x gnome-shell >/dev/null 2>&1; then
        DESKTOP_MODE="gnome"
        return 0
      fi
    fi
    pid_alive lxqt || break
    sleep 0.5
  done
  stop_proc lxqt || true
  pkill -u "$SESSION_USER" -f 'gnome-session|gnome-shell|mutter' >/dev/null 2>&1 || true
  sleep 0.8
  return 1
}

start_gnome_flashback() {
  [ -x /usr/bin/gnome-session ] || return 1
  [ -f /usr/share/gnome-session/sessions/gnome-flashback-metacity.session ] || return 1
  echo "  tentando GNOME Flashback..."
  spawn_user_log lxqt gnome-flashback env \
    XDG_CURRENT_DESKTOP='GNOME-Flashback:GNOME' \
    XDG_SESSION_DESKTOP=gnome-flashback-metacity \
    DESKTOP_SESSION=gnome-flashback-metacity \
    XDG_MENU_PREFIX=gnome-flashback- \
    dbus-launch --exit-with-session \
    /usr/bin/gnome-session --disable-acceleration-check --debug --session=gnome-flashback-metacity

  for _ in $(seq 1 80); do
    if pgrep -u "$SESSION_USER" -x metacity >/dev/null 2>&1 || \
       pgrep -u "$SESSION_USER" -x gnome-panel >/dev/null 2>&1; then
      sleep 2
      if pgrep -u "$SESSION_USER" -x metacity >/dev/null 2>&1 || \
         pgrep -u "$SESSION_USER" -x gnome-panel >/dev/null 2>&1; then
        DESKTOP_MODE="gnome-flashback"
        return 0
      fi
    fi
    pid_alive lxqt || break
    sleep 0.5
  done
  stop_proc lxqt || true
  pkill -u "$SESSION_USER" -f 'gnome-session|gnome-panel|metacity' >/dev/null 2>&1 || true
  sleep 0.8
  return 1
}

# No runtime CPU-only já sabemos que o GNOME Shell 46 morre no login1 e ainda
# consome CPU via llvmpipe. MAX prioriza o Flashback moderno nesses casos.
if [ "$GPU_AVAILABLE" = "1" ] && login1_ok; then
  if ! start_gnome_shell; then
    echo "  GNOME Shell não estabilizou; usando Flashback."
    start_gnome_flashback || true
  fi
else
  echo "  MAX: CPU-only/login1 indisponível, priorizando GNOME Flashback."
  if ! start_gnome_flashback; then
    echo "  Flashback falhou; tentando GNOME Shell como fallback."
    start_gnome_shell || true
  fi
fi

if [ -z "$DESKTOP_MODE" ]; then
  DESKTOP_BIN="$(command -v openbox-session || command -v openbox || true)"
  if [ -z "$DESKTOP_BIN" ]; then
    echo "Nenhum desktop utilizável encontrado." >&2
    exit 5
  fi
  echo "  iniciando Openbox de emergência..."
  spawn_user_log lxqt openbox env XDG_CURRENT_DESKTOP=MaquinaVirtual DESKTOP_SESSION=openbox \
    dbus-launch --exit-with-session "$DESKTOP_BIN"
  sleep 1
  DESKTOP_MODE="openbox"
fi

echo "$DESKTOP_MODE" > "$BASE/desktop_mode"
echo "  desktop ativo: $DESKTOP_MODE"
bash "$SCRIPT_DIR/theme.sh" "$RESOLUTION" "$SESSION_USER" post >"$LOGDIR/theme.log" 2>&1 || true
sleep 0.5

echo "[3/5] Iniciando VNC local..."
VNC_PASS="$BASE/vnc.pass"
x11vnc -storepasswd "$PASSWORD" "$VNC_PASS" >/dev/null 2>&1
chmod 600 "$VNC_PASS"

VNC_ARGS=(x11vnc -display "$DISPLAY" -forever -shared -repeat \
  -rfbport "$VNC_PORT" -rfbauth "$VNC_PASS" -localhost)
# XDamage no Xorg Dummy/llvmpipe foi instável no teste real. Mantemos o modo
# seguro em CPU-only; com Xorg NVIDIA real podemos aproveitar damage tracking.
DISPLAY_MODE_NOW="$(cat "$DISPLAY_MODE_FILE" 2>/dev/null || echo unknown)"
if [ "$GPU_AVAILABLE" != "1" ] || [ "$DISPLAY_MODE_NOW" != "xorg-nvidia" ]; then
  VNC_ARGS+=( -noxdamage )
fi
spawn x11vnc "${VNC_ARGS[@]}"
if ! wait_port "$VNC_PORT" 50; then
  tail -n 60 "$LOGDIR/x11vnc.log" >&2 || true
  exit 6
fi

echo "[4/5] Iniciando noVNC..."
NOVNC_ROOT=""
for candidate in /usr/share/novnc /usr/share/noVNC; do
  if [ -f "$candidate/vnc.html" ]; then
    NOVNC_ROOT="$candidate"
    break
  fi
done
if [ -z "$NOVNC_ROOT" ]; then
  VNC_HTML="$(dpkg -L novnc 2>/dev/null | grep '/vnc.html$' | head -n1 || true)"
  [ -n "$VNC_HTML" ] && NOVNC_ROOT="$(dirname "$VNC_HTML")"
fi
if [ -z "$NOVNC_ROOT" ]; then
  echo "Não foi possível localizar os arquivos do noVNC." >&2
  exit 7
fi
spawn websockify websockify --web "$NOVNC_ROOT" \
  "127.0.0.1:${NOVNC_PORT}" "127.0.0.1:${VNC_PORT}"
if ! wait_port "$NOVNC_PORT" 50; then
  tail -n 40 "$LOGDIR/websockify.log" >&2 || true
  exit 8
fi
LOCAL_CODE="$(curl -sS --max-time 5 -o /dev/null -w '%{http_code}' "http://127.0.0.1:${NOVNC_PORT}/vnc.html" 2>/dev/null || true)"
if [[ ! "$LOCAL_CODE" =~ ^2[0-9][0-9]$ ]]; then
  echo "noVNC local não respondeu corretamente (HTTP $LOCAL_CODE)." >&2
  exit 8
fi

echo "[5/5] Criando túnel HTTPS temporário..."
CLOUDFLARED=/usr/local/bin/cloudflared
if [ ! -x "$CLOUDFLARED" ]; then
  ARCH="$(uname -m)"
  case "$ARCH" in
    x86_64|amd64) ASSET=cloudflared-linux-amd64 ;;
    aarch64|arm64) ASSET=cloudflared-linux-arm64 ;;
    *) echo "Arquitetura não suportada para cloudflared: $ARCH" >&2; exit 9 ;;
  esac
  curl -fL --retry 3 "https://github.com/cloudflare/cloudflared/releases/latest/download/${ASSET}" -o "$CLOUDFLARED"
  chmod 755 "$CLOUDFLARED"
fi

PUBLIC_URL=""
TUNNEL_OK=0
for attempt in 1 2 3; do
  echo "  tentativa de túnel $attempt/3..."
  stop_proc cloudflared || true
  : > "$LOGDIR/cloudflared.log"
  spawn cloudflared "$CLOUDFLARED" tunnel \
    --no-autoupdate --protocol http2 --edge-ip-version 4 \
    --url "http://127.0.0.1:${NOVNC_PORT}"
  PUBLIC_URL=""
  for _ in $(seq 1 120); do
    if ! pid_alive cloudflared; then break; fi
    if [ -z "$PUBLIC_URL" ]; then
      PUBLIC_URL="$(grep -oE 'https://[A-Za-z0-9-]+\.trycloudflare\.com' "$LOGDIR/cloudflared.log" 2>/dev/null | head -n1 || true)"
    fi
    if [ -n "$PUBLIC_URL" ] && public_ok "$PUBLIC_URL"; then
      TUNNEL_OK=1
      break
    fi
    sleep 0.5
  done
  [ "$TUNNEL_OK" -eq 1 ] && break
  sleep 1
done
if [ "$TUNNEL_OK" -ne 1 ] || [ -z "$PUBLIC_URL" ]; then
  echo "Não foi possível estabelecer um túnel HTTPS saudável." >&2
  tail -n 80 "$LOGDIR/cloudflared.log" >&2 || true
  exit 10
fi

DISPLAY_MODE="$(cat "$DISPLAY_MODE_FILE" 2>/dev/null || echo unknown)"
SYSTEM_BUS_MODE="$(cat "$SYSTEM_BUS_FILE" 2>/dev/null || echo unknown)"
export MV_PUBLIC_URL="$PUBLIC_URL" MV_PASSWORD="$PASSWORD" MV_RESOLUTION="$RESOLUTION"
export MV_SESSION_FILE="$SESSION_FILE" MV_DESKTOP_MODE="$DESKTOP_MODE"
export MV_DISPLAY_MODE="$DISPLAY_MODE" MV_SESSION_USER="$SESSION_USER" MV_SYSTEM_BUS="$SYSTEM_BUS_MODE"
python3 - <<'PY'
import json, os, time, urllib.parse
base = os.environ["MV_PUBLIC_URL"].rstrip("/")
password = os.environ["MV_PASSWORD"]
resolution = os.environ["MV_RESOLUTION"]
desktop = os.environ["MV_DESKTOP_MODE"]
display_mode = os.environ["MV_DISPLAY_MODE"]
user = os.environ["MV_SESSION_USER"]
system_bus = os.environ["MV_SYSTEM_BUS"]
viewer = base + "/vnc.html?autoconnect=true&resize=scale&reconnect=true&path=websockify"
deep = "maquinavirtual://connect?" + urllib.parse.urlencode({"url": base, "password": password, "resolution": resolution})
data = {
  "public_url": base,
  "viewer_url": viewer,
  "password": password,
  "resolution": resolution,
  "deep_link": deep,
  "desktop_mode": desktop,
  "display_mode": display_mode,
  "session_user": user,
  "system_bus": system_bus,
  "created_at": int(time.time()),
  "tunnel_verified": True,
}
perf_path = "/tmp/maquina-virtual/performance.json"
try:
    with open(perf_path, encoding="utf-8") as f:
        data["performance"] = json.load(f)
except Exception:
    pass
with open(os.environ["MV_SESSION_FILE"], "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
print(json.dumps(data, ensure_ascii=False))
PY
chmod 600 "$SESSION_FILE"

# Watchdog local muito leve: só recupera x11vnc/websockify se um deles cair.
if [ -x "$SCRIPT_DIR/watchdog.sh" ]; then
  spawn watchdog bash "$SCRIPT_DIR/watchdog.sh" "$DISPLAY" "$VNC_PORT" "$NOVNC_PORT"
fi

echo
echo "[Máquina Virtual] Sessão pronta e túnel verificado."
echo "Perfil: ${MV_PERFORMANCE_PROFILE:-max}"
echo "CPU: ${MV_CPU_THREADS:-?} threads | RAM: ${MV_RAM_MB:-?} MB"
if [ "$GPU_AVAILABLE" = "1" ]; then
  echo "GPU: ${MV_GPU_NAME:-NVIDIA} | Display: $DISPLAY_MODE"
else
  echo "GPU: indisponível | Display: $DISPLAY_MODE"
fi
echo "System D-Bus: $SYSTEM_BUS_MODE"
echo "Desktop: $DESKTOP_MODE"
echo "Usuário: $SESSION_USER"
echo "URL: $PUBLIC_URL"
echo "Senha: $PASSWORD"
