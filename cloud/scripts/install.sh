#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "[Máquina Virtual] Atualizando pacotes..."
apt-get update -y

echo "[Máquina Virtual] Instalando desktop e acesso remoto..."
apt-get install -y --no-install-recommends \
  lxqt-core lxqt-session lxqt-panel lxqt-qtplugin \
  openbox pcmanfm-qt qterminal \
  xvfb x11-xserver-utils xauth dbus-x11 \
  x11vnc novnc websockify \
  curl ca-certificates procps iproute2 openssl \
  fonts-noto fonts-dejavu fonts-liberation

mkdir -p /tmp/maquina-virtual/{logs,pids}
chmod 700 /tmp/maquina-virtual

echo "[Máquina Virtual] Instalação concluída."
