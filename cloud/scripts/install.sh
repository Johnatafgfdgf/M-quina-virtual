#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
SESSION_USER="${SESSION_USER:-mvuser}"

echo "[Máquina Virtual] Atualizando pacotes..."
apt-get update -y

echo "[Máquina Virtual] Instalando base gráfica e acesso remoto..."
apt-get install -y --no-install-recommends \
  xserver-xorg-core xserver-xorg-video-dummy xserver-xorg-input-libinput xcvt \
  xvfb x11-xserver-utils xauth \
  dbus dbus-daemon dbus-x11 dbus-user-session libpam-systemd policykit-1 \
  xdg-user-dirs xdg-utils \
  x11vnc novnc websockify \
  curl wget ca-certificates gnupg procps iproute2 openssl sudo \
  fonts-noto fonts-dejavu fonts-liberation fonts-cantarell \
  mesa-utils mesa-vulkan-drivers vulkan-tools libgl1-mesa-dri

echo "[Máquina Virtual] Instalando GNOME principal..."
apt-get install -y --no-install-recommends \
  gnome-session gnome-session-bin gnome-shell gnome-settings-daemon \
  gnome-terminal nautilus gnome-control-center gsettings-desktop-schemas \
  gnome-backgrounds gnome-themes-extra gnome-keyring \
  xdg-desktop-portal xdg-desktop-portal-gnome \
  epiphany-browser eog evince file-roller

apt-get install -y --no-install-recommends \
  gnome-tweaks gnome-session-flashback gnome-panel metacity \
  adwaita-icon-theme-full yaru-theme-gtk yaru-theme-icon \
  || true

apt-get install -y --no-install-recommends \
  ubuntu-session gnome-shell-extension-ubuntu-dock \
  || apt-get install -y --no-install-recommends gnome-shell-extension-dashtodock \
  || true

TMP_CHROME=/tmp/google-chrome-stable_current_amd64.deb
if [ "$(dpkg --print-architecture)" = "amd64" ]; then
  if curl -fL --retry 3 \
    https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
    -o "$TMP_CHROME"; then
    apt-get install -y "$TMP_CHROME" || apt-get -f install -y || true
    rm -f "$TMP_CHROME"
  fi
fi

apt-get install -y --no-install-recommends \
  openbox tint2 feh librsvg2-bin papirus-icon-theme python3-xdg \
  qterminal pcmanfm-qt featherpad falkon \
  || true

# O GNOME 46 do Ubuntu 24.04 depende fortemente da sessão systemd/GDM.
# No Colab, o gnome-session chega a subir e depois derruba a sessão inteira.
# Para o modo GNOME principal, usamos o GNOME Shell X11 diretamente, que é uma
# opção suportada pelo próprio gnome-shell. Flashback continua usando o
# gnome-session real e permanece como fallback confiável.
GNOME_SHIM_DIR=/usr/libexec/maquina-virtual
mkdir -p "$GNOME_SHIM_DIR"

if [ -x /usr/libexec/gnome-session-binary ]; then
  GNOME_REAL=/usr/libexec/gnome-session-binary
else
  GNOME_REAL="$GNOME_SHIM_DIR/gnome-session-real"
  if [ ! -x "$GNOME_REAL" ]; then
    CURRENT="$(readlink -f /usr/bin/gnome-session 2>/dev/null || true)"
    if [ -n "$CURRENT" ] && [ -x "$CURRENT" ]; then
      cp -a "$CURRENT" "$GNOME_REAL"
    fi
  fi
fi

cat > /usr/bin/gnome-session <<'EOF'
#!/usr/bin/env bash
set -u

REAL="/usr/libexec/gnome-session-binary"
if [ ! -x "$REAL" ]; then
  REAL="/usr/libexec/maquina-virtual/gnome-session-real"
fi

SESSION_NAME=""
ARGS=()
HELP="$($REAL --help 2>&1 || true)"

for arg in "$@"; do
  case "$arg" in
    --session=*)
      SESSION_NAME="${arg#--session=}"
      ARGS+=("$arg")
      ;;
    --builtin|--systemd)
      # Removidos no GNOME 46.
      ;;
    --disable-acceleration-check)
      if printf '%s\n' "$HELP" | grep -q -- '--disable-acceleration-check'; then
        ARGS+=("$arg")
      fi
      ;;
    *)
      ARGS+=("$arg")
      ;;
  esac
done

if [ "$SESSION_NAME" = "gnome" ]; then
  echo "[Máquina Virtual] Iniciando GNOME Shell X11 direto." >&2

  if command -v gnome-keyring-daemon >/dev/null 2>&1; then
    eval "$(gnome-keyring-daemon --start --components=secrets 2>/dev/null || true)" || true
  fi

  # Serviços essenciais que normalmente seriam iniciados pelo gnome-session.
  for svc in \
    /usr/libexec/gsd-xsettings \
    /usr/libexec/gsd-keyboard \
    /usr/libexec/gsd-media-keys \
    /usr/libexec/gsd-a11y-settings \
    /usr/libexec/gsd-clipboard; do
    if [ -x "$svc" ]; then
      "$svc" >/dev/null 2>&1 &
    fi
  done

  export XDG_CURRENT_DESKTOP=GNOME
  export XDG_SESSION_DESKTOP=gnome
  export DESKTOP_SESSION=gnome
  export GNOME_SHELL_SESSION_MODE=gnome
  exec /usr/bin/gnome-shell --x11 --sm-disable
fi

exec "$REAL" "${ARGS[@]}"
EOF
chmod 755 /usr/bin/gnome-session

if ! id -u "$SESSION_USER" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$SESSION_USER"
fi
for group in sudo audio video render; do
  if getent group "$group" >/dev/null 2>&1; then
    usermod -aG "$group" "$SESSION_USER" || true
  fi
done

dbus-uuidgen --ensure=/etc/machine-id || true
mkdir -p /var/lib/dbus /run/dbus
if [ ! -e /var/lib/dbus/machine-id ]; then
  ln -s /etc/machine-id /var/lib/dbus/machine-id 2>/dev/null || \
    cp /etc/machine-id /var/lib/dbus/machine-id 2>/dev/null || true
fi

SESSION_HOME="$(getent passwd "$SESSION_USER" | cut -d: -f6)"
mkdir -p \
  "$SESSION_HOME/.config" \
  "$SESSION_HOME/.local/share" \
  "$SESSION_HOME/Downloads" \
  "$SESSION_HOME/Desktop" \
  "$SESSION_HOME/Documents" \
  "$SESSION_HOME/Pictures" \
  "$SESSION_HOME/Videos"
chown -R "$SESSION_USER:$SESSION_USER" \
  "$SESSION_HOME/.config" "$SESSION_HOME/.local" \
  "$SESSION_HOME/Downloads" "$SESSION_HOME/Desktop" \
  "$SESSION_HOME/Documents" "$SESSION_HOME/Pictures" "$SESSION_HOME/Videos"
runuser -u "$SESSION_USER" -- xdg-user-dirs-update >/dev/null 2>&1 || true

mkdir -p /tmp/maquina-virtual/{logs,pids}
chmod 700 /tmp/maquina-virtual

echo "[Máquina Virtual] Instalação concluída."
echo "Display prioritário: Xorg Dummy"
echo "Desktop prioritário: GNOME Shell X11 direto"
echo "Fallbacks: GNOME Flashback -> Openbox"
if command -v google-chrome >/dev/null 2>&1; then
  echo "Navegador principal: Google Chrome"
else
  echo "Navegador principal: GNOME Web (Epiphany)"
fi
