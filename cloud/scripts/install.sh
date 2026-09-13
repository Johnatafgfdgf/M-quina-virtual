#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "[Máquina Virtual] Atualizando pacotes..."
apt-get update -y

echo "[Máquina Virtual] Instalando desktop e acesso remoto..."
apt-get install -y --no-install-recommends \
  lxqt-core lxqt-session lxqt-panel lxqt-qtplugin lxqt-config \
  openbox pcmanfm-qt qterminal \
  xvfb x11-xserver-utils xauth dbus-x11 \
  x11vnc novnc websockify \
  curl ca-certificates procps iproute2 openssl \
  libqt5svg5 \
  fonts-noto fonts-dejavu fonts-liberation

# Pacotes de acabamento visual. Se o tema de ícones não estiver disponível
# nessa imagem do Ubuntu, o desktop continua funcionando com os ícones padrão.
apt-get install -y --no-install-recommends tint2 feh librsvg2-bin papirus-icon-theme \
  || apt-get install -y --no-install-recommends tint2 feh librsvg2-bin \
  || true

mkdir -p /tmp/maquina-virtual/{logs,pids}
chmod 700 /tmp/maquina-virtual

echo "[Máquina Virtual] Instalação concluída."
