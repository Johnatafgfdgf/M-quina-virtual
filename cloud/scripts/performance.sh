#!/usr/bin/env bash
# Perfil MAX da Máquina Virtual.
# Pode ser executado ou usado com `source performance.sh` antes de start.sh.
# Nunca inventa recursos: usa o máximo que o runtime realmente disponibilizou.
set -u

SESSION_USER="${SESSION_USER:-mvuser}"
BASE=/tmp/maquina-virtual
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
START_SCRIPT="$SCRIPT_DIR/start.sh"
PERF_JSON="$BASE/performance.json"
mkdir -p "$BASE/logs" "$BASE/pids"

CPU_THREADS="$(nproc 2>/dev/null || echo 1)"
CPU_THREADS="${CPU_THREADS:-1}"
RAM_KB="$(awk '/^MemTotal:/ {print $2; exit}' /proc/meminfo 2>/dev/null || echo 0)"
RAM_MB=$(( RAM_KB / 1024 ))

GPU_AVAILABLE=0
GPU_NAME=""
GPU_VRAM_MB=0
if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
  GPU_AVAILABLE=1
  GPU_NAME="$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || true)"
  GPU_VRAM_MB="$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -n1 | tr -cd '0-9' || true)"
  GPU_VRAM_MB="${GPU_VRAM_MB:-0}"
fi

# Máximo de paralelismo para bibliotecas comuns de cálculo/renderização.
export MV_PERFORMANCE_PROFILE=max
export MV_CPU_THREADS="$CPU_THREADS"
export OMP_NUM_THREADS="$CPU_THREADS"
export OPENBLAS_NUM_THREADS="$CPU_THREADS"
export MKL_NUM_THREADS="$CPU_THREADS"
export NUMEXPR_MAX_THREADS="$CPU_THREADS"
export VECLIB_MAXIMUM_THREADS="$CPU_THREADS"
export LP_NUM_THREADS="$CPU_THREADS"
export MESA_GLTHREAD=true
export MESA_SHADER_CACHE_DISABLE=false
export MESA_SHADER_CACHE_MAX_SIZE=1G
export __GL_SHADER_DISK_CACHE=1
export __GL_THREADED_OPTIMIZATIONS=1

# Cache de shaders do usuário gráfico.
if id -u "$SESSION_USER" >/dev/null 2>&1; then
  USER_HOME="$(getent passwd "$SESSION_USER" | cut -d: -f6)"
  mkdir -p "$USER_HOME/.cache/mesa_shader_cache" "$USER_HOME/.cache/nvidia"
  chown -R "$SESSION_USER:$SESSION_USER" "$USER_HOME/.cache" 2>/dev/null || true
  export MESA_SHADER_CACHE_DIR="$USER_HOME/.cache/mesa_shader_cache"
  export __GL_SHADER_DISK_CACHE_PATH="$USER_HOME/.cache/nvidia"
fi

# Ajustes de kernel apenas quando o runtime permite. Falhar aqui não aborta a sessão.
if command -v sysctl >/dev/null 2>&1; then
  sysctl -w vm.swappiness=10 >/dev/null 2>&1 || true
  sysctl -w vm.vfs_cache_pressure=50 >/dev/null 2>&1 || true
  sysctl -w fs.inotify.max_user_watches=524288 >/dev/null 2>&1 || true
  sysctl -w fs.inotify.max_user_instances=1024 >/dev/null 2>&1 || true
fi

# Se o host expuser controle de frequência, pede governor performance.
for governor in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
  [ -w "$governor" ] || continue
  printf '%s' performance > "$governor" 2>/dev/null || true
done

# Limites de descritores maiores ajudam IDEs, engines e projetos grandes.
ulimit -n 1048576 2>/dev/null || ulimit -n 65535 2>/dev/null || true

# Tracker não funciona corretamente no kernel do runtime Colab (Landlock ausente)
# e estava consumindo CPU/log sem indexar. Desativamos só o minerador, não o Nautilus.
if id -u "$SESSION_USER" >/dev/null 2>&1; then
  USER_HOME="$(getent passwd "$SESSION_USER" | cut -d: -f6)"
  AUTOSTART="$USER_HOME/.config/autostart"
  mkdir -p "$AUTOSTART"
  for src in /etc/xdg/autostart/tracker-miner-fs-3.desktop /etc/xdg/autostart/tracker-miner-fs.desktop; do
    [ -f "$src" ] || continue
    dst="$AUTOSTART/$(basename "$src")"
    cp "$src" "$dst" 2>/dev/null || true
    if [ -f "$dst" ] && ! grep -q '^Hidden=true$' "$dst" 2>/dev/null; then
      printf '\nHidden=true\n' >> "$dst"
    fi
  done
  chown -R "$SESSION_USER:$SESSION_USER" "$AUTOSTART" 2>/dev/null || true
fi

# O start.sh antigo forçava llvmpipe mesmo quando uma NVIDIA estivesse presente.
# O perfil MAX remove essa trava. Sem GPU, Mesa volta naturalmente ao llvmpipe.
# Também reativa XDamage no x11vnc para evitar polling integral da tela e reduzir CPU.
if [ -f "$START_SCRIPT" ]; then
  python3 - "$START_SCRIPT" "$GPU_AVAILABLE" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
has_gpu = sys.argv[2] == '1'
s = p.read_text(encoding='utf-8')

# Não bloquear aceleração futura com software rendering explícito.
s = s.replace('    LIBGL_ALWAYS_SOFTWARE=1 \\\n    GALLIUM_DRIVER=llvmpipe \\\n', '')

# XDamage envia regiões alteradas em vez de fazer polling completo de todos os pixels.
s = s.replace(' -forever -shared -repeat -noxdamage \\\n', ' -forever -shared -repeat \\\n')

# Em CPU-only, GNOME Shell/Mutter por llvmpipe gasta muita CPU e neste runtime ainda
# depende de login1. O Flashback continua GNOME, é bem mais leve e recebe nosso tema.
old = '''if ! start_gnome_shell; then
  echo "  GNOME Shell não estabilizou; veja logs/gnome-shell.log."
  if ! start_gnome_flashback; then
    echo "  GNOME Flashback não estabilizou; veja logs/gnome-flashback.log."
  fi
fi'''
if has_gpu:
    new = old
else:
    new = '''echo "  perfil MAX sem GPU: priorizando GNOME Flashback para liberar CPU."
if ! start_gnome_flashback; then
  echo "  GNOME Flashback não estabilizou; tentando GNOME Shell como fallback."
  if ! start_gnome_shell; then
    echo "  GNOME Shell também não estabilizou."
  fi
fi'''
if old in s:
    s = s.replace(old, new)

p.write_text(s, encoding='utf-8')
PY
fi

# Registra os recursos reais para diagnóstico/app. Nenhuma métrica é inventada.
export MV_PERF_CPU="$CPU_THREADS" MV_PERF_RAM="$RAM_MB" MV_PERF_GPU="$GPU_AVAILABLE"
export MV_PERF_GPU_NAME="$GPU_NAME" MV_PERF_VRAM="$GPU_VRAM_MB" MV_PERF_JSON="$PERF_JSON"
python3 - <<'PY'
import json, os, time
p = os.environ['MV_PERF_JSON']
data = {
    'profile': 'max',
    'cpu_threads': int(os.environ.get('MV_PERF_CPU', '1') or 1),
    'ram_mb': int(os.environ.get('MV_PERF_RAM', '0') or 0),
    'gpu_available': os.environ.get('MV_PERF_GPU') == '1',
    'gpu_name': os.environ.get('MV_PERF_GPU_NAME', ''),
    'gpu_vram_mb': int(os.environ.get('MV_PERF_VRAM', '0') or 0),
    'mesa_glthread': True,
    'created_at': int(time.time()),
}
with open(p, 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
PY
chmod 600 "$PERF_JSON" 2>/dev/null || true

printf '[Máquina Virtual] Perfil MAX: %s threads | %s MB RAM' "$CPU_THREADS" "$RAM_MB"
if [ "$GPU_AVAILABLE" -eq 1 ]; then
  printf ' | GPU: %s (%s MB VRAM)\n' "${GPU_NAME:-NVIDIA}" "$GPU_VRAM_MB"
else
  printf ' | GPU: indisponível, usando renderização por CPU\n'
fi
