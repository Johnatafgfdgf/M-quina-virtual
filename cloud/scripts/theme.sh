#!/usr/bin/env bash
set -u

RESOLUTION="${1:-1600x720}"
SESSION_USER="${2:-mvuser}"
WIDTH="${RESOLUTION%x*}"
HEIGHT="${RESOLUTION#*x}"
BASE=/tmp/maquina-virtual
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSET_DIR="$(cd "$SCRIPT_DIR/../assets" && pwd)"
WALLPAPER_SVG="$ASSET_DIR/wallpaper.svg"
MODE="$(cat "$BASE/desktop_mode" 2>/dev/null || echo openbox)"
USER_HOME="$(getent passwd "$SESSION_USER" | cut -d: -f6)"
[ -n "$USER_HOME" ] || USER_HOME="/home/$SESSION_USER"
WALL_DIR="$USER_HOME/.local/share/backgrounds"
WALLPAPER_PNG="$WALL_DIR/maquina-virtual.png"
RUNTIME_DIR="/tmp/runtime-$SESSION_USER"

export DISPLAY="${DISPLAY:-:10}"

mkdir -p "$WALL_DIR"
if command -v rsvg-convert >/dev/null 2>&1 && [ -f "$WALLPAPER_SVG" ]; then
  rsvg-convert -w "$WIDTH" -h "$HEIGHT" "$WALLPAPER_SVG" -o "$WALLPAPER_PNG" >/dev/null 2>&1 || true
fi
chown -R "$SESSION_USER:$SESSION_USER" "$USER_HOME/.local" 2>/dev/null || true

as_user() {
  runuser -u "$SESSION_USER" -- env \
    HOME="$USER_HOME" USER="$SESSION_USER" LOGNAME="$SESSION_USER" \
    DISPLAY="$DISPLAY" XDG_RUNTIME_DIR="$RUNTIME_DIR" \
    XDG_SESSION_TYPE=x11 GDK_BACKEND=x11 \
    "$@"
}

if command -v google-chrome >/dev/null 2>&1; then
  BROWSER_CMD="google-chrome --disable-dev-shm-usage"
  BROWSER_DESKTOP="google-chrome.desktop"
elif command -v epiphany >/dev/null 2>&1; then
  BROWSER_CMD="epiphany"
  BROWSER_DESKTOP="org.gnome.Epiphany.desktop"
else
  BROWSER_CMD="falkon"
  BROWSER_DESKTOP="org.kde.falkon.desktop"
fi

if [[ "$MODE" == gnome* ]]; then
  echo "[Máquina Virtual] Aplicando visual GNOME ($MODE)..."

  FAVORITES="['org.gnome.Nautilus.desktop','org.gnome.Terminal.desktop','$BROWSER_DESKTOP','org.gnome.Settings.desktop']"
  as_user dbus-run-session -- bash -lc "
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true
    gsettings set org.gnome.desktop.interface gtk-theme 'Yaru-dark' 2>/dev/null || gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark' 2>/dev/null || true
    gsettings set org.gnome.desktop.interface icon-theme 'Yaru' 2>/dev/null || gsettings set org.gnome.desktop.interface icon-theme 'Adwaita' 2>/dev/null || true
    gsettings set org.gnome.desktop.interface cursor-size 28 2>/dev/null || true
    gsettings set org.gnome.desktop.interface text-scaling-factor 1.05 2>/dev/null || true
    gsettings set org.gnome.desktop.wm.preferences button-layout ':minimize,maximize,close' 2>/dev/null || true
    gsettings set org.gnome.desktop.background picture-options 'zoom' 2>/dev/null || true
    gsettings set org.gnome.desktop.background picture-uri 'file://$WALLPAPER_PNG' 2>/dev/null || true
    gsettings set org.gnome.desktop.background picture-uri-dark 'file://$WALLPAPER_PNG' 2>/dev/null || true
    gsettings set org.gnome.shell favorite-apps \"$FAVORITES\" 2>/dev/null || true
  " >/dev/null 2>&1 || true

  if command -v feh >/dev/null 2>&1 && [ -f "$WALLPAPER_PNG" ] && [[ "$MODE" == *flashback* ]]; then
    as_user feh --no-fehbg --bg-fill "$WALLPAPER_PNG" >/dev/null 2>&1 &
  fi

  echo "[Máquina Virtual] Tema GNOME aplicado."
  exit 0
fi

# Fallback Openbox: mantém uma interface utilizável se GNOME não subir no runtime.
echo "[Máquina Virtual] Aplicando fallback Openbox..."
TINT_DIR="$USER_HOME/.config/tint2"
LAUNCH_DIR="$USER_HOME/.local/share/applications/maquina-virtual"
mkdir -p "$TINT_DIR" "$LAUNCH_DIR"
chown -R "$SESSION_USER:$SESSION_USER" "$USER_HOME/.config" "$USER_HOME/.local" 2>/dev/null || true

cat > "$LAUNCH_DIR/files.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Arquivos
Exec=pcmanfm-qt
Icon=system-file-manager
Terminal=false
EOF
cat > "$LAUNCH_DIR/terminal.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Terminal
Exec=qterminal
Icon=utilities-terminal
Terminal=false
EOF
cat > "$LAUNCH_DIR/browser.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Navegador
Exec=$BROWSER_CMD
Icon=web-browser
Terminal=false
EOF
chmod 644 "$LAUNCH_DIR"/*.desktop
chown -R "$SESSION_USER:$SESSION_USER" "$LAUNCH_DIR"

cat > "$TINT_DIR/maquina.tint2rc" <<EOF
rounded = 16
border_width = 1
border_sides = TBLR
background_color = #0b1020 92
border_color = #5263a0 35
background_color_hover = #18213a 96
border_color_hover = #6f7fe0 50
background_color_pressed = #242f50 98
border_color_pressed = #8e72ff 65
panel_items = LTSC
panel_size = 96% 52
panel_margin = 0 10
panel_padding = 12 5 12
panel_position = bottom center horizontal
panel_layer = top
panel_monitor = all
panel_shrink = 0
panel_background_id = 1
wm_menu = 1
launcher_padding = 7 6 7
launcher_icon_size = 30
launcher_icon_theme = Papirus-Dark
launcher_item_app = $LAUNCH_DIR/files.desktop
launcher_item_app = $LAUNCH_DIR/terminal.desktop
launcher_item_app = $LAUNCH_DIR/browser.desktop
task_text = 1
task_icon = 1
task_centered = 1
task_maximum_size = 190 38
task_padding = 8 4 8
task_font = Noto Sans 10
task_font_color = #eef2ff 100
task_active_background_id = 2
taskbar_mode = single_desktop
systray_padding = 6 4 6
systray_icon_size = 24
time1_format = %H:%M
time1_font = Noto Sans Bold 11
clock_font_color = #f5f7ff 100
clock_padding = 10 4
tooltip = 1
tooltip_background_id = 1
tooltip_font = Noto Sans 10
tooltip_font_color = #ffffff 100
EOF
chown -R "$SESSION_USER:$SESSION_USER" "$TINT_DIR"

if [ -f "$WALLPAPER_PNG" ] && command -v feh >/dev/null 2>&1; then
  as_user feh --no-fehbg --bg-fill "$WALLPAPER_PNG" >/dev/null 2>&1 &
else
  xsetroot -solid '#091225' >/dev/null 2>&1 || true
fi
if command -v tint2 >/dev/null 2>&1; then
  setsid runuser -u "$SESSION_USER" -- env HOME="$USER_HOME" DISPLAY="$DISPLAY" XDG_RUNTIME_DIR="$RUNTIME_DIR" \
    tint2 -c "$TINT_DIR/maquina.tint2rc" >"$BASE/logs/tint2.log" 2>&1 < /dev/null &
  echo $! > "$BASE/pids/tint2.pid"
fi

echo "[Máquina Virtual] Fallback visual aplicado."
