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
TINT_DIR="$USER_HOME/.config/tint2"
LAUNCH_DIR="$USER_HOME/.local/share/applications/maquina-virtual"
GTK_DIR="$USER_HOME/.config/gtk-3.0"
LOGDIR="$BASE/logs"
PIDDIR="$BASE/pids"

export DISPLAY="${DISPLAY:-:10}"
mkdir -p "$WALL_DIR" "$TINT_DIR" "$LAUNCH_DIR" "$GTK_DIR" "$LOGDIR" "$PIDDIR"

if command -v rsvg-convert >/dev/null 2>&1 && [ -f "$WALLPAPER_SVG" ]; then
  rsvg-convert -w "$WIDTH" -h "$HEIGHT" "$WALLPAPER_SVG" -o "$WALLPAPER_PNG" >/dev/null 2>&1 || true
fi
chown -R "$SESSION_USER:$SESSION_USER" "$USER_HOME/.config" "$USER_HOME/.local" 2>/dev/null || true

# Descobre o D-Bus da sessão GNOME já ativa para que gsettings e gnome-panel
# alterem a sessão real, não uma sessão temporária paralela.
SESSION_BUS=""
for pid in $(pgrep -u "$SESSION_USER" -f 'gnome-panel|gnome-session-binary|metacity' 2>/dev/null || true); do
  [ -r "/proc/$pid/environ" ] || continue
  SESSION_BUS="$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | sed -n 's/^DBUS_SESSION_BUS_ADDRESS=//p' | head -n1)"
  [ -n "$SESSION_BUS" ] && break
done

as_user() {
  if [ -n "$SESSION_BUS" ]; then
    runuser -u "$SESSION_USER" -- env \
      HOME="$USER_HOME" USER="$SESSION_USER" LOGNAME="$SESSION_USER" \
      DISPLAY="$DISPLAY" XDG_RUNTIME_DIR="$RUNTIME_DIR" \
      XDG_SESSION_TYPE=x11 GDK_BACKEND=x11 \
      DBUS_SESSION_BUS_ADDRESS="$SESSION_BUS" \
      "$@"
  else
    runuser -u "$SESSION_USER" -- env \
      HOME="$USER_HOME" USER="$SESSION_USER" LOGNAME="$SESSION_USER" \
      DISPLAY="$DISPLAY" XDG_RUNTIME_DIR="$RUNTIME_DIR" \
      XDG_SESSION_TYPE=x11 GDK_BACKEND=x11 \
      "$@"
  fi
}

run_user_shell() {
  if [ -n "$SESSION_BUS" ]; then
    as_user bash -lc "$1"
  else
    as_user dbus-run-session -- bash -lc "$1"
  fi
}

if command -v google-chrome >/dev/null 2>&1; then
  BROWSER_CMD="google-chrome --disable-dev-shm-usage"
elif command -v epiphany >/dev/null 2>&1; then
  BROWSER_CMD="epiphany"
else
  BROWSER_CMD="falkon"
fi

if command -v nautilus >/dev/null 2>&1; then
  FILES_CMD="nautilus --new-window"
else
  FILES_CMD="pcmanfm-qt"
fi

if command -v gnome-terminal >/dev/null 2>&1; then
  TERMINAL_CMD="gnome-terminal"
else
  TERMINAL_CMD="qterminal"
fi

# Atalhos usados pelo dock flutuante.
cat > "$LAUNCH_DIR/files.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Arquivos
Exec=$FILES_CMD
Icon=system-file-manager
Terminal=false
EOF

cat > "$LAUNCH_DIR/terminal.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Terminal
Exec=$TERMINAL_CMD
Icon=utilities-terminal
Terminal=false
EOF

cat > "$LAUNCH_DIR/browser.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Chrome
Exec=$BROWSER_CMD
Icon=google-chrome
Terminal=false
EOF

cat > "$LAUNCH_DIR/settings.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Configurações
Exec=gnome-control-center
Icon=org.gnome.Settings
Terminal=false
EOF

chmod 644 "$LAUNCH_DIR"/*.desktop
chown -R "$SESSION_USER:$SESSION_USER" "$LAUNCH_DIR"

# Tema escuro consistente para aplicações GTK e para o painel do Flashback.
cat > "$GTK_DIR/gtk.css" <<'EOF'
/* Máquina Virtual shell */
window,
dialog {
  color: #f4f7ff;
}

#PanelToplevel,
panel-toplevel,
.gnome-panel-menu-bar,
.gnome-panel-menu-bar menubar,
.gnome-panel-menu-bar menuitem {
  background-image: none;
  background-color: rgba(8, 13, 28, 0.97);
  color: #f5f7ff;
  border: 0;
}

#PanelToplevel button,
panel-toplevel button,
.gnome-panel-menu-bar menuitem {
  background-image: none;
  background-color: transparent;
  border: 0;
  border-radius: 10px;
  padding: 5px 9px;
  color: #f5f7ff;
}

#PanelToplevel button:hover,
panel-toplevel button:hover,
.gnome-panel-menu-bar menuitem:hover {
  background-color: rgba(99, 102, 241, 0.22);
}
EOF
chown -R "$SESSION_USER:$SESSION_USER" "$GTK_DIR"

apply_common_gnome_settings() {
  run_user_shell "
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true
    gsettings set org.gnome.desktop.interface gtk-theme 'Yaru-dark' 2>/dev/null || gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark' 2>/dev/null || true
    gsettings set org.gnome.desktop.interface icon-theme 'Yaru' 2>/dev/null || gsettings set org.gnome.desktop.interface icon-theme 'Adwaita' 2>/dev/null || true
    gsettings set org.gnome.desktop.interface cursor-size 28 2>/dev/null || true
    gsettings set org.gnome.desktop.interface text-scaling-factor 1.03 2>/dev/null || true
    gsettings set org.gnome.desktop.wm.preferences button-layout ':minimize,maximize,close' 2>/dev/null || true
    gsettings set org.gnome.desktop.wm.preferences theme 'Yaru-dark' 2>/dev/null || true
    gsettings set org.gnome.desktop.background picture-options 'zoom' 2>/dev/null || true
    gsettings set org.gnome.desktop.background picture-uri 'file://$WALLPAPER_PNG' 2>/dev/null || true
    gsettings set org.gnome.desktop.background picture-uri-dark 'file://$WALLPAPER_PNG' 2>/dev/null || true
  " >/dev/null 2>&1 || true
}

start_modern_dock() {
  command -v tint2 >/dev/null 2>&1 || return 0

  cat > "$TINT_DIR/maquina-dock.tint2rc" <<EOF
rounded = 20
border_width = 1
border_sides = TBLR
background_color = #080d1c 92
border_color = #7c83ff 38
background_color_hover = #151c34 96
border_color_hover = #8f96ff 55
background_color_pressed = #232d50 98
border_color_pressed = #a58cff 70

panel_items = LT
panel_size = 68% 62
panel_margin = 0 14
panel_padding = 14 6 14
panel_position = bottom center horizontal
panel_layer = top
panel_monitor = all
panel_shrink = 0
panel_background_id = 1
panel_dock = 0
wm_menu = 1
strut_policy = follow_size

launcher_padding = 8 7 8
launcher_icon_size = 38
launcher_icon_theme = Papirus-Dark
launcher_item_app = $LAUNCH_DIR/files.desktop
launcher_item_app = $LAUNCH_DIR/terminal.desktop
launcher_item_app = $LAUNCH_DIR/browser.desktop
launcher_item_app = $LAUNCH_DIR/settings.desktop

launcher_tooltip = 1

task_text = 0
task_icon = 1
task_centered = 1
task_maximum_size = 48 46
task_padding = 6 5 6
task_icon_asb = 100 0 0
task_active_background_id = 2
taskbar_mode = single_desktop
taskbar_hide_if_empty = 1
mouse_left = toggle_iconify
mouse_middle = close
mouse_right = none

tooltip = 1
tooltip_background_id = 1
tooltip_font = Noto Sans 10
tooltip_font_color = #ffffff 100
EOF

  chown -R "$SESSION_USER:$SESSION_USER" "$TINT_DIR"
  pkill -u "$SESSION_USER" -x tint2 >/dev/null 2>&1 || true
  sleep 0.2

  setsid runuser -u "$SESSION_USER" -- env \
    HOME="$USER_HOME" USER="$SESSION_USER" LOGNAME="$SESSION_USER" \
    DISPLAY="$DISPLAY" XDG_RUNTIME_DIR="$RUNTIME_DIR" \
    tint2 -c "$TINT_DIR/maquina-dock.tint2rc" \
    >"$LOGDIR/tint2.log" 2>&1 < /dev/null &
  echo $! > "$PIDDIR/tint2.pid"
}

apply_flashback_shell() {
  echo "[Máquina Virtual] Redesenhando GNOME Flashback..."

  # Um único painel superior. Sai a barra branca inferior e sai o menu
  # Applications/Places. O botão à esquerda abre somente os aplicativos.
  cat > /usr/share/gnome-panel/layouts/maquina-virtual.layout <<'EOF'
[Toplevel top-panel]
expand=true
orientation=top
size=42

[Object main-menu]
module-id=org.gnome.gnome-panel.menu
applet-id=menu-button
toplevel-id=top-panel
pack-index=0

[Object clock]
module-id=org.gnome.gnome-panel.clock
applet-id=clock
toplevel-id=top-panel
pack-type=end
pack-index=1

[Object notification-area]
module-id=org.gnome.gnome-panel.notification-area
applet-id=notification-area
toplevel-id=top-panel
pack-type=end
pack-index=2

[Object user-menu]
module-id=org.gnome.gnome-panel.menu
applet-id=user-menu
toplevel-id=top-panel
pack-type=end
pack-index=0
EOF

  apply_common_gnome_settings

  # Recria o painel a partir do layout moderno. dconf-cli pode não estar
  # presente em imagens mínimas, então há fallback por gsettings.
  if command -v dconf >/dev/null 2>&1; then
    run_user_shell "
      dconf reset -f /org/gnome/gnome-panel/ 2>/dev/null || true
      gsettings set org.gnome.gnome-panel.general default-layout 'maquina-virtual' 2>/dev/null || true
    " >/dev/null 2>&1 || true
  else
    run_user_shell "
      gsettings set org.gnome.gnome-panel.general default-layout 'maquina-virtual' 2>/dev/null || true
    " >/dev/null 2>&1 || true
  fi

  # O --replace faz o painel reler o tema e o layout sem matar o Flashback.
  if command -v gnome-panel >/dev/null 2>&1; then
    if [ -n "$SESSION_BUS" ]; then
      setsid runuser -u "$SESSION_USER" -- env \
        HOME="$USER_HOME" USER="$SESSION_USER" LOGNAME="$SESSION_USER" \
        DISPLAY="$DISPLAY" XDG_RUNTIME_DIR="$RUNTIME_DIR" \
        DBUS_SESSION_BUS_ADDRESS="$SESSION_BUS" \
        GTK_THEME=Yaru-dark \
        gnome-panel --replace >"$LOGDIR/gnome-panel-modern.log" 2>&1 < /dev/null &
    else
      setsid runuser -u "$SESSION_USER" -- env \
        HOME="$USER_HOME" USER="$SESSION_USER" LOGNAME="$SESSION_USER" \
        DISPLAY="$DISPLAY" XDG_RUNTIME_DIR="$RUNTIME_DIR" \
        GTK_THEME=Yaru-dark \
        dbus-launch --exit-with-session gnome-panel --replace \
        >"$LOGDIR/gnome-panel-modern.log" 2>&1 < /dev/null &
    fi
    sleep 1.2
  fi

  if [ -f "$WALLPAPER_PNG" ] && command -v feh >/dev/null 2>&1; then
    as_user feh --no-fehbg --bg-fill "$WALLPAPER_PNG" >/dev/null 2>&1 &
  fi

  start_modern_dock
  echo "[Máquina Virtual] GNOME Flashback convertido para shell moderno."
}

if [ "$MODE" = "gnome-flashback" ]; then
  apply_flashback_shell
  exit 0
fi

if [ "$MODE" = "gnome" ]; then
  echo "[Máquina Virtual] Aplicando visual GNOME Shell..."
  apply_common_gnome_settings
  echo "[Máquina Virtual] Tema GNOME Shell aplicado."
  exit 0
fi

# Openbox continua como último fallback, mas recebe o mesmo dock e identidade.
echo "[Máquina Virtual] Aplicando fallback Openbox..."
if [ -f "$WALLPAPER_PNG" ] && command -v feh >/dev/null 2>&1; then
  as_user feh --no-fehbg --bg-fill "$WALLPAPER_PNG" >/dev/null 2>&1 &
else
  xsetroot -solid '#091225' >/dev/null 2>&1 || true
fi
start_modern_dock

echo "[Máquina Virtual] Fallback visual aplicado."