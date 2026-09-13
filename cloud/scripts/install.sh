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

# Camada visual. É opcional: uma falha aqui nunca impede a máquina de iniciar.
apt-get install -y --no-install-recommends tint2 feh librsvg2-bin papirus-icon-theme \
  || apt-get install -y --no-install-recommends tint2 feh librsvg2-bin \
  || true

# Aplicativos úteis e leves para a sessão. Falkon evita depender de snaps no Colab.
apt-get install -y --no-install-recommends falkon featherpad \
  || true

mkdir -p /tmp/maquina-virtual/{logs,pids}
chmod 700 /tmp/maquina-virtual

echo "[Máquina Virtual] Instalação concluída."
