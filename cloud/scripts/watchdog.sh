#!/usr/bin/env bash
set -u

DISPLAY_VALUE="${1:-:10}"
VNC_PORT="${2:-5900}"
NOVNC_PORT="${3:-6080}"
BASE=/tmp/maquina-virtual
PIDDIR="$BASE/pids"
LOGDIR="$BASE/logs"
VNC_PASS="$BASE/vnc.pass"
GPU_MODE_FILE="$BASE/gpu_mode"
DISPLAY_MODE_FILE="$BASE/display_mode"

log() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

port_up() {
  local port="$1"
  ss -ltn 2>/dev/null | grep -qE "127\\.0\\.0\\.1:${port}|\\[::1\\]:${port}"
}

start_vnc() {
  [ -f "$VNC_PASS" ] || return 1
  local gpu display_mode
  gpu="$(cat "$GPU_MODE_FILE" 2>/dev/null || echo 0)"
  display_mode="$(cat "$DISPLAY_MODE_FILE" 2>/dev/null || echo unknown)"
  args=(x11vnc -display "$DISPLAY_VALUE" -forever -shared -repeat \
    -rfbport "$VNC_PORT" -rfbauth "$VNC_PASS" -localhost)
  if [ "$gpu" != "1" ] || [ "$display_mode" != "xorg-nvidia" ]; then
    args+=( -noxdamage )
  fi
  setsid nohup "${args[@]}" >"$LOGDIR/x11vnc.log" 2>&1 < /dev/null &
  echo $! > "$PIDDIR/x11vnc.pid"
  log "x11vnc reiniciado."
}

find_novnc_root() {
  local candidate
  for candidate in /usr/share/novnc /usr/share/noVNC; do
    if [ -f "$candidate/vnc.html" ]; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  local html
  html="$(dpkg -L novnc 2>/dev/null | grep '/vnc.html$' | head -n1 || true)"
  [ -n "$html" ] && dirname "$html"
}

start_websockify() {
  local root
  root="$(find_novnc_root)"
  [ -n "$root" ] || return 1
  setsid nohup websockify --web "$root" \
    "127.0.0.1:${NOVNC_PORT}" "127.0.0.1:${VNC_PORT}" \
    >"$LOGDIR/websockify.log" 2>&1 < /dev/null &
  echo $! > "$PIDDIR/websockify.pid"
  log "websockify reiniciado."
}

log "watchdog iniciado."
while true; do
  # Se o display morreu, não adianta reiniciar os proxies.
  if ! DISPLAY="$DISPLAY_VALUE" xdpyinfo >/dev/null 2>&1; then
    log "display indisponível; aguardando recuperação."
    sleep 5
    continue
  fi

  if ! port_up "$VNC_PORT"; then
    start_vnc || true
    sleep 1
  fi

  if ! port_up "$NOVNC_PORT"; then
    start_websockify || true
  fi

  sleep 5
done
