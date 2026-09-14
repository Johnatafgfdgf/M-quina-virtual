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

# GNOME 46 (Ubuntu 24.04) removeu --builtin/--systemd. O start.sh ainda usa
# --builtin por compatibilidade com imagens GNOME antigas. Este shim filtra
# opções ausentes na versão instalada e, se o gnome-session moderno não puder
# montar a sessão fora do GDM/systemd --user, tenta o GNOME Shell diretamente.
GNOME_SHIM_DIR=/usr/libexec/maquina-virtual
GNOME_REAL="$GNOME_SHIM_DIR/gnome-session-real"
mkdir -p "$GNOME_SHIM_DIR"

if [ ! -x "$GNOME_REAL" ]; then
  RESOLVED="$(readlink -f /usr/bin/gnome-session 2>/dev/null || true)"
  if [ -n "$RESOLVED" ] && [ "$RESOLVED" != "/usr/bin/gnome-session" ] && [ -x "$RESOLVED" ]; then
    ln -sf "$RESOLVED" "$GNOME_REAL"
  elif [ -x /usr/bin/gnome-session ]; then
    cp -a /usr/bin/gnome-session "$GNOME_REAL"
  fi
fi

if [ -x "$GNOME_REAL" ]; then
  rm -f /usr/bin/gnome-session
  cat > /usr/bin/gnome-session <<'EOF'
#!/usr/bin/env bash
set -u
REAL=/usr/libexec/maquina-virtual/gnome-session-real
SESSION_NAME=""
ARGS=()
HELP="$($REAL --help 2>&1 || true)"

for arg in "$@"; do
  case "$arg" in
    --builtin|--systemd)
      # Removidos no GNOME 46. Ignorar mantém compatibilidade com versões novas.
      continue
      ;;
    --disable-acceleration-check)
      if printf '%s\n' "$HELP" | grep -q -- '--disable-acceleration-check'; then
        ARGS+=("$arg")
      fi
      ;;
    --session=*)
      SESSION_NAME="${arg#--session=}"
      ARGS+=("$arg")
      ;;
    *)
      ARGS+=("$arg")
      ;;
  esac
done

"$REAL" "${ARGS[@]}"
RC=$?

# Se o GNOME moderno saiu sem deixar o Shell vivo, fazemos um boot direto do
# Shell X11. Isso evita depender de um login GDM tradicional no Colab.
if [ "$SESSION_NAME" = "gnome" ] && ! pgrep -u "$(id -u)" -x gnome-shell >/dev/null 2>&1; then
  echo "[Máquina Virtual] gnome-session saiu (rc=$RC); tentando GNOME Shell X11 direto." >&2
  if command -v gnome-keyring-daemon >/dev/null 2>&1; then
    eval "$(gnome-keyring-daemon --start --components=secrets 2>/dev/null || true)" || true
  fi
  for svc in /usr/libexec/gsd-xsettings /usr/libexec/gsd-keyboard /usr/libexec/gsd-media-keys; do
    if [ -x "$svc" ]; then
      "$svc" >/dev/null 2>&1 &
    fi
  done
  exec /usr/bin/gnome-shell --x11 --sm-disable
fi

# Flashback manual como fallback GNOME antes de o start.sh cair para Openbox.
if [ "$SESSION_NAME" = "gnome-flashback-metacity" ] && \
   ! pgrep -u "$(id -u)" -x metacity >/dev/null 2>&1 && \
   ! pgrep -u "$(id -u)" -x gnome-panel >/dev/null 2>&1; then
  echo "[Máquina Virtual] gnome-session Flashback saiu (rc=$RC); tentando painel GNOME manual." >&2
  if command -v metacity >/dev/null 2>&1 && command -v gnome-panel >/dev/null 2>&1; then
    metacity --replace >/dev/null 2>&1 &
    gnome-panel >/dev/null 2>&1 &
    wait
  fi
fi

exit "$RC"
EOF
  chmod 755 /usr/bin/gnome-session
fi

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
echo "Desktop prioritário: GNOME Shell"
echo "Fallbacks: GNOME Shell X11 direto -> GNOME Flashback -> Openbox"
if command -v google-chrome >/dev/null 2>&1; then
  echo "Navegador principal: Google Chrome"
else
  echo "Navegador principal: GNOME Web (Epiphany)"
fi
