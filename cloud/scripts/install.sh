#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
SESSION_USER="${SESSION_USER:-mvuser}"

echo "[Máquina Virtual] Atualizando pacotes..."
apt-get update -y

echo "[Máquina Virtual] Instalando base gráfica e acesso remoto..."
apt-get install -y --no-install-recommends \
  xserver-xorg-core xserver-xorg-video-dummy xserver-xorg-input-libinput xcvt \
  xvfb x11-xserver-utils xauth dbus-x11 dbus-user-session \
  x11vnc novnc websockify \
  curl wget ca-certificates gnupg procps iproute2 openssl sudo policykit-1 \
  fonts-noto fonts-dejavu fonts-liberation fonts-cantarell \
  mesa-utils mesa-vulkan-drivers vulkan-tools libgl1-mesa-dri

echo "[Máquina Virtual] Instalando GNOME principal..."
apt-get install -y --no-install-recommends \
  gnome-session gnome-session-bin gnome-shell gnome-settings-daemon \
  gnome-terminal nautilus gnome-control-center gsettings-desktop-schemas \
  gnome-backgrounds gnome-themes-extra gnome-keyring \
  xdg-desktop-portal xdg-desktop-portal-gnome \
  epiphany-browser eog evince file-roller

# Flashback é o primeiro fallback visual porque continua sendo GNOME e aceita
# displays headless com muito mais facilidade que Mutter/GNOME Shell.
apt-get install -y --no-install-recommends \
  gnome-tweaks gnome-session-flashback gnome-panel metacity \
  adwaita-icon-theme-full yaru-theme-gtk yaru-theme-icon \
  || true

# Sessão Ubuntu/GNOME e dock são opcionais. Quando disponíveis, deixam o GNOME
# com integração visual melhor sem puxar o meta-pacote ubuntu-desktop inteiro.
apt-get install -y --no-install-recommends \
  ubuntu-session gnome-shell-extension-ubuntu-dock \
  || apt-get install -y --no-install-recommends gnome-shell-extension-dashtodock \
  || true

# Google Chrome é usado como navegador principal quando a instalação .deb for
# compatível com o runtime. Epiphany continua instalado como fallback nativo GNOME.
TMP_CHROME=/tmp/google-chrome-stable_current_amd64.deb
if [ "$(dpkg --print-architecture)" = "amd64" ]; then
  if curl -fL --retry 3 \
    https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
    -o "$TMP_CHROME"; then
    apt-get install -y "$TMP_CHROME" || apt-get -f install -y || true
    rm -f "$TMP_CHROME"
  fi
fi

# Fallback leve. Ele existe somente para manter a máquina acessível se as duas
# sessões GNOME falharem naquele runtime.
apt-get install -y --no-install-recommends \
  openbox tint2 feh librsvg2-bin papirus-icon-theme python3-xdg \
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

# No Colab não existe um login gráfico tradicional via GDM. O GNOME moderno
# normalmente delega partes da sessão ao systemd --user, o que pode abortar
# quando iniciado via runuser. Este wrapper força o gerenciador builtin, ignora
# a checagem de aceleração e preserva um log separado mesmo se houver fallback.
cat > /usr/local/bin/gnome-session <<'EOF'
#!/usr/bin/env bash
set -u
REAL=/usr/bin/gnome-session
LOG=/tmp/maquina-virtual/logs/gnome-session.log
mkdir -p /tmp/maquina-virtual/logs
{
  echo
  echo "===== $(date -Is) gnome-session $* ====="
  exec "$REAL" --builtin --disable-acceleration-check --debug "$@"
} >>"$LOG" 2>&1
EOF
chmod 755 /usr/local/bin/gnome-session

# Evita primeiro-uso excessivo do GNOME e cria diretórios esperados.
SESSION_HOME="$(getent passwd "$SESSION_USER" | cut -d: -f6)"
mkdir -p "$SESSION_HOME/.config" "$SESSION_HOME/.local/share" "$SESSION_HOME/Downloads"
chown -R "$SESSION_USER:$SESSION_USER" "$SESSION_HOME/.config" "$SESSION_HOME/.local" "$SESSION_HOME/Downloads"

mkdir -p /tmp/maquina-virtual/{logs,pids}
chmod 700 /tmp/maquina-virtual

echo "[Máquina Virtual] Instalação concluída."
echo "Display prioritário: Xorg Dummy"
echo "Desktop prioritário: GNOME Shell (builtin)"
echo "Fallbacks: GNOME Flashback -> Openbox"
if command -v google-chrome >/dev/null 2>&1; then
  echo "Navegador principal: Google Chrome"
else
  echo "Navegador principal: GNOME Web (Epiphany)"
fi
