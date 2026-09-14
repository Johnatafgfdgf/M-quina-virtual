#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
SESSION_USER="${SESSION_USER:-mvuser}"

echo "[Máquina Virtual] Atualizando pacotes..."
apt-get update -y

echo "[Máquina Virtual] Instalando base de desktop remoto..."
apt-get install -y --no-install-recommends \
  xvfb x11-xserver-utils xauth dbus-x11 \
  x11vnc novnc websockify \
  curl ca-certificates procps iproute2 openssl sudo \
  fonts-noto fonts-dejavu fonts-liberation fonts-cantarell \
  mesa-utils mesa-vulkan-drivers vulkan-tools

echo "[Máquina Virtual] Instalando GNOME principal..."
apt-get install -y --no-install-recommends \
  gnome-session gnome-shell gnome-terminal nautilus \
  gnome-control-center gsettings-desktop-schemas \
  epiphany-browser eog evince file-roller

# Pacotes visuais e sessão Flashback variam um pouco entre imagens Ubuntu.
# São opcionais porque o GNOME principal deve continuar instalável mesmo se algum deles mudar de nome.
apt-get install -y --no-install-recommends \
  gnome-tweaks gnome-session-flashback metacity \
  adwaita-icon-theme-full yaru-theme-gtk yaru-theme-icon \
  || true

# Dock opcional.
apt-get install -y --no-install-recommends gnome-shell-extension-ubuntu-dock \
  || apt-get install -y --no-install-recommends gnome-shell-extension-dashtodock \
  || true

# Fallback leve para runtimes onde GNOME Shell não consiga subir em modo headless.
apt-get install -y --no-install-recommends \
  openbox tint2 feh librsvg2-bin papirus-icon-theme \
  qterminal pcmanfm-qt featherpad falkon \
  || true

# Usuário gráfico real. Navegadores, IDEs e engines não devem rodar como root.
if ! id -u "$SESSION_USER" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$SESSION_USER"
fi
for group in sudo audio video render; do
  if getent group "$group" >/dev/null 2>&1; then
    usermod -aG "$group" "$SESSION_USER" || true
  fi
done

mkdir -p /tmp/maquina-virtual/{logs,pids}
chmod 700 /tmp/maquina-virtual

echo "[Máquina Virtual] Instalação concluída."
echo "Desktop prioritário: GNOME"
echo "Fallbacks: GNOME Flashback -> Openbox"
