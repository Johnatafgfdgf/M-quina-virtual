#!/usr/bin/env bash
set -u

RESOLUTION="${1:-1600x720}"
WIDTH="${RESOLUTION%x*}"
HEIGHT="${RESOLUTION#*x}"
BASE=/tmp/maquina-virtual
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSET_DIR="$(cd "$SCRIPT_DIR/../assets" && pwd)"
WALLPAPER_SVG="$ASSET_DIR/wallpaper.svg"
WALLPAPER_PNG="$BASE/wallpaper.png"
TINT_DIR="$BASE/tint2"
LAUNCH_DIR="$BASE/launchers"
mkdir -p "$TINT_DIR" "$LAUNCH_DIR"

export DISPLAY="${DISPLAY:-:10}"

# Converte o wallpaper do projeto para o tamanho exato da sessão.
if command -v rsvg-convert >/dev/null 2>&1 && [ -f "$WALLPAPER_SVG" ]; then
  rsvg-convert -w "$WIDTH" -h "$HEIGHT" "$WALLPAPER_SVG" -o "$WALLPAPER_PNG" >/dev/null 2>&1 || true
fi

# Launchers próprios para não depender do menu visual padrão do LXQt.
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

cat > "$LAUNCH_DIR/settings.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Aparência
Exec=lxqt-config-appearance
Icon=preferences-desktop-theme
Terminal=false
EOF

chmod 644 "$LAUNCH_DIR"/*.desktop

# Um painel simples e consistente, em vez do painel LXQt padrão apertado.
cat > "$TINT_DIR/maquina.tint2rc" <<EOF
# Máquina Virtual - painel móvel
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
panel_size = 96% 50
panel_margin = 0 10
panel_padding = 12 5 12
panel_position = bottom center horizontal
panel_layer = top
panel_monitor = all
panel_shrink = 0
panel_background_id = 1
wm_menu = 1
panel_dock = 0

launcher_padding = 6 6 6
launcher_background_id = 0
launcher_icon_background_id = 0
launcher_icon_size = 28
launcher_icon_theme = Papirus-Dark
launcher_item_app = $LAUNCH_DIR/files.desktop
launcher_item_app = $LAUNCH_DIR/terminal.desktop
launcher_item_app = $LAUNCH_DIR/settings.desktop

# Tarefas
task_text = 1
task_icon = 1
task_centered = 1
task_maximum_size = 190 38
task_padding = 8 4 8
task_font = Noto Sans 10
task_font_color = #eef2ff 100
task_background_id = 0
task_active_background_id = 2
task_iconified_background_id = 0
taskbar_mode = single_desktop

# Systray
systray_padding = 6 4 6
systray_icon_size = 24
systray_icon_asb = 100 0 0

# Relógio
time1_format = %H:%M
time1_font = Noto Sans Bold 11
time1_timezone = :/etc/localtime
clock_font_color = #f5f7ff 100
clock_padding = 10 4
clock_background_id = 0
clock_lclick_command = qterminal

tooltip = 1
tooltip_show_timeout = 0.4
tooltip_hide_timeout = 0.2
tooltip_padding = 8 6
tooltip_background_id = 1
tooltip_font = Noto Sans 10
tooltip_font_color = #ffffff 100
EOF

# Remove apenas a casca visual do LXQt. O session manager e Openbox continuam ativos.
pkill -x lxqt-panel >/dev/null 2>&1 || true
pkill -f 'pcmanfm-qt.*--desktop' >/dev/null 2>&1 || true
sleep 0.4

# Wallpaper limpo. Sem ícones root/Network espalhados pela tela.
if [ -f "$WALLPAPER_PNG" ] && command -v feh >/dev/null 2>&1; then
  feh --no-fehbg --bg-fill "$WALLPAPER_PNG" >/dev/null 2>&1 &
else
  xsetroot -solid '#091225' >/dev/null 2>&1 || true
fi

# Painel moderno; se tint2 não existir, reabre o painel LXQt como fallback.
if command -v tint2 >/dev/null 2>&1; then
  tint2 -c "$TINT_DIR/maquina.tint2rc" >"$BASE/logs/tint2.log" 2>&1 &
  echo $! > "$BASE/pids/tint2.pid"
else
  lxqt-panel >"$BASE/logs/lxqt-panel.log" 2>&1 &
fi

# Preferências visuais que não são críticas para a sessão.
mkdir -p "$HOME/.config/lxqt"
cat > "$HOME/.config/lxqt/lxqt.conf" <<'EOF'
[General]
icon_theme=Papirus-Dark
single_click_activate=false
tool_button_style=ToolButtonTextBesideIcon
EOF

# Aumenta levemente o cursor e a escala para toque/tela pequena.
export XCURSOR_SIZE=28
xrdb -merge <<'EOF' >/dev/null 2>&1 || true
Xcursor.size: 28
Xft.dpi: 108
EOF

echo "[Máquina Virtual] Tema mobile aplicado."
