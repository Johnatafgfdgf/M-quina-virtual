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

# GNOME Flashback continua como primeiro fallback porque preserva a linguagem
# do GNOME e tolera ambientes headless melhor que Mutter/GNOME Shell.
apt-get install -y --no-install-recommends \
  gnome-tweaks gnome-session-flashback gnome-panel metacity \
  adwaita-icon-theme-full yaru-theme-gtk yaru-theme-icon \
  || true

# Sessão Ubuntu/dock são opcionais.
apt-get install -y --no-install-recommends \
  ubuntu-session gnome-shell-extension-ubuntu-dock \
  || apt-get install -y --no-install-recommends gnome-shell-extension-dashtodock \
  || true

# Google Chrome é o navegador principal quando o .deb for compatível.
TMP_CHROME=/tmp/google-chrome-stable_current_amd64.deb
if [ "$(dpkg --print-architecture)" = "amd64" ]; then
  if curl -fL --retry 3 \
    https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
    -o "$TMP_CHROME"; then
    apt-get install -y "$TMP_CHROME" || apt-get -f install -y || true
    rm -f "$TMP_CHROME"
  fi
fi

# Último fallback, só para manter a máquina acessível se GNOME falhar.
apt-get install -y --no-install-recommends \
  openbox tint2 feh librsvg2-bin papirus-icon-theme python3-xdg \
  qterminal pcmanfm-qt featherpad falkon \
  || true

# Usuário gráfico real.
if ! id -u "$SESSION_USER" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$SESSION_USER"
fi
for group in sudo audio video render; do
  if getent group "$group" >/dev/null 2>&1; then
    usermod -aG "$group" "$SESSION_USER" || true
  fi
done

# IDs e diretórios esperados pelo D-Bus/GNOME.
dbus-uuidgen --ensure=/etc/machine-id || true
mkdir -p /var/lib/dbus /run/dbus
if [ ! -e /var/lib/dbus/machine-id ]; then
  ln -s /etc/machine-id /var/lib/dbus/machine-id 2>/dev/null || cp /etc/machine-id /var/lib/dbus/machine-id 2>/dev/null || true
fi

SESSION_HOME="$(getent passwd "$SESSION_USER" | cut -d: -f6)"
mkdir -p "$SESSION_HOME/.config" "$SESSION_HOME/.local/share" "$SESSION_HOME/Downloads"
chown -R "$SESSION_USER:$SESSION_USER" "$SESSION_HOME/.config" "$SESSION_HOME/.local" "$SESSION_HOME/Downloads"
runuser -u "$SESSION_USER" -- xdg-user-dirs-update >/dev/null 2>&1 || true

mkdir -p /tmp/maquina-virtual/{logs,pids}
chmod 700 /tmp/maquina-virtual

echo "[Máquina Virtual] Instalação concluída."
echo "Display prioritário: Xorg Dummy"
echo "Desktop prioritário: GNOME Shell (sessão builtin)"
echo "Fallbacks: GNOME Flashback -> Openbox"
if command -v google-chrome >/dev/null 2>&1; then
  echo "Navegador principal: Google Chrome"
else
  echo "Navegador principal: GNOME Web (Epiphany)"
fi
