#!/usr/bin/env bash
set -euo pipefail

RESOLUTION="${1:-1600x900}"
PASSWORD="${2:-}"
DISPLAY_NUM="${DISPLAY_NUM:-10}"
DISPLAY=":${DISPLAY_NUM}"
VNC_PORT="${VNC_PORT:-5900}"
NOVNC_PORT="${NOVNC_PORT:-6080}"
BASE=/tmp/maquina-virtual
LOGDIR="$BASE/logs"
PIDDIR="$BASE/pids"
SESSION_FILE="$BASE/session.json"

mkdir -p "$LOGDIR" "$PIDDIR"
chmod 700 "$BASE"

if [[ ! "$RESOLUTION" =~ ^[0-9]+x[0-9]+$ ]]; then
  echo "Resolução inválida: $RESOLUTION" >&2
  exit 2
fi

if [ -z "$PASSWORD" ]; then
  PASSWORD="$(openssl rand -base64 18 | tr -dc 'A-Za-z0-9' | head -c 8)"
fi
PASSWORD="${PASSWORD:0:8}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$SCRIPT_DIR/stop.sh" >/dev/null 2>&1 || true
mkdir -p "$LOGDIR" "$PIDDIR"

WIDTH="${RESOLUTION%x*}"
HEIGHT="${RESOLUTION#*x}"
export DISPLAY
export XDG_RUNTIME_DIR="/tmp/runtime-$(id -u)"
export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=LXQt
export DESKTOP_SESSION=lxqt
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

spawn() {
  local name="$1"
  shift
  nohup "$@" >"$LOGDIR/$name.log" 2>&1 < /dev/null &
  echo $! > "$PIDDIR/$name.pid"
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

echo "[1/5] Iniciando display X virtual..."
spawn xvfb Xvfb "$DISPLAY" \
  -screen 0 "${WIDTH}x${HEIGHT}x24" \
  -nolisten tcp -ac -noreset \
  +extension RANDR +extension RENDER +extension XTEST +extension GLX

for _ in $(seq 1 40); do
  [ -S "/tmp/.X11-unix/X${DISPLAY_NUM}" ] && break
  sleep 0.25
done
if [ ! -S "/tmp/.X11-unix/X${DISPLAY_NUM}" ]; then
  tail -n 30 "$LOGDIR/xvfb.log" >&2 || true
  exit 3
fi

echo "[2/5] Iniciando LXQt..."
DESKTOP_BIN="$(command -v startlxqt || command -v lxqt-session || true)"
if [ -z "$DESKTOP_BIN" ]; then
  echo "LXQt não encontrado. Execute install.sh primeiro." >&2
  exit 4
fi
spawn lxqt dbus-run-session -- "$DESKTOP_BIN"
sleep 2

echo "[3/5] Iniciando VNC local..."
VNC_PASS="$BASE/vnc.pass"
x11vnc -storepasswd "$PASSWORD" "$VNC_PASS" >/dev/null 2>&1
chmod 600 "$VNC_PASS"
spawn x11vnc x11vnc \
  -display "$DISPLAY" \
  -forever -shared -repeat -noxdamage \
  -rfbport "$VNC_PORT" \
  -rfbauth "$VNC_PASS" \
  -localhost

if ! wait_port "$VNC_PORT" 50; then
  tail -n 40 "$LOGDIR/x11vnc.log" >&2 || true
  exit 5
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
  exit 6
fi

spawn websockify websockify \
  --web "$NOVNC_ROOT" \
  "127.0.0.1:${NOVNC_PORT}" \
  "127.0.0.1:${VNC_PORT}"

if ! wait_port "$NOVNC_PORT" 50; then
  tail -n 40 "$LOGDIR/websockify.log" >&2 || true
  exit 7
fi

echo "[5/5] Criando túnel HTTPS temporário..."
CLOUDFLARED=/usr/local/bin/cloudflared
if [ ! -x "$CLOUDFLARED" ]; then
  ARCH="$(uname -m)"
  case "$ARCH" in
    x86_64|amd64) ASSET=cloudflared-linux-amd64 ;;
    aarch64|arm64) ASSET=cloudflared-linux-arm64 ;;
    *) echo "Arquitetura não suportada para cloudflared: $ARCH" >&2; exit 8 ;;
  esac
  curl -fL --retry 3 \
    "https://github.com/cloudflare/cloudflared/releases/latest/download/${ASSET}" \
    -o "$CLOUDFLARED"
  chmod 755 "$CLOUDFLARED"
fi

spawn cloudflared "$CLOUDFLARED" tunnel --no-autoupdate --url "http://127.0.0.1:${NOVNC_PORT}"

PUBLIC_URL=""
for _ in $(seq 1 80); do
  PUBLIC_URL="$(grep -oE 'https://[A-Za-z0-9-]+\.trycloudflare\.com' "$LOGDIR/cloudflared.log" 2>/dev/null | head -n1 || true)"
  [ -n "$PUBLIC_URL" ] && break
  sleep 0.5
done

if [ -z "$PUBLIC_URL" ]; then
  tail -n 60 "$LOGDIR/cloudflared.log" >&2 || true
  echo "O túnel HTTPS não retornou uma URL." >&2
  exit 9
fi

export MV_PUBLIC_URL="$PUBLIC_URL"
export MV_PASSWORD="$PASSWORD"
export MV_RESOLUTION="$RESOLUTION"
export MV_SESSION_FILE="$SESSION_FILE"
python3 - <<'PY'
import json, os, time, urllib.parse
base = os.environ["MV_PUBLIC_URL"].rstrip("/")
password = os.environ["MV_PASSWORD"]
resolution = os.environ["MV_RESOLUTION"]
viewer = base + "/vnc.html?autoconnect=true&resize=scale&reconnect=true&path=websockify"
deep = "maquinavirtual://connect?" + urllib.parse.urlencode({
    "url": base,
    "password": password,
    "resolution": resolution,
})
data = {
    "public_url": base,
    "viewer_url": viewer,
    "password": password,
    "resolution": resolution,
    "deep_link": deep,
    "created_at": int(time.time()),
}
with open(os.environ["MV_SESSION_FILE"], "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
print(json.dumps(data, ensure_ascii=False))
PY

chmod 600 "$SESSION_FILE"
echo
 echo "[Máquina Virtual] Sessão pronta."
echo "URL: $PUBLIC_URL"
echo "Senha: $PASSWORD"
