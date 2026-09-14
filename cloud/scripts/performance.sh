#!/usr/bin/env bash
# Perfil MAX da Máquina Virtual.
# Detecta e expõe todos os recursos REAIS do runtime sem editar outros scripts.
set -u

SESSION_USER="${SESSION_USER:-mvuser}"
BASE=/tmp/maquina-virtual
PERF_JSON="$BASE/performance.json"
mkdir -p "$BASE/logs" "$BASE/pids"

CPU_THREADS="$(nproc 2>/dev/null || echo 1)"
CPU_THREADS="${CPU_THREADS:-1}"
RAM_KB="$(awk '/^MemTotal:/ {print $2; exit}' /proc/meminfo 2>/dev/null || echo 0)"
RAM_MB=$(( RAM_KB / 1024 ))

GPU_AVAILABLE=0
GPU_NAME=""
GPU_VRAM_MB=0
GPU_DRIVER=""
if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
  GPU_AVAILABLE=1
  GPU_NAME="$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || true)"
  GPU_VRAM_MB="$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -n1 | tr -cd '0-9' || true)"
  GPU_DRIVER="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -n1 | xargs || true)"
  GPU_VRAM_MB="${GPU_VRAM_MB:-0}"
fi

# Variáveis herdadas por IDEs, renderizadores e workloads científicos.
export MV_PERFORMANCE_PROFILE=max
export MV_CPU_THREADS="$CPU_THREADS"
export MV_RAM_MB="$RAM_MB"
export MV_GPU_AVAILABLE="$GPU_AVAILABLE"
export MV_GPU_NAME="$GPU_NAME"
export MV_GPU_VRAM_MB="$GPU_VRAM_MB"
export MV_GPU_DRIVER="$GPU_DRIVER"
export OMP_NUM_THREADS="$CPU_THREADS"
export OPENBLAS_NUM_THREADS="$CPU_THREADS"
export MKL_NUM_THREADS="$CPU_THREADS"
export NUMEXPR_MAX_THREADS="$CPU_THREADS"
export VECLIB_MAXIMUM_THREADS="$CPU_THREADS"
export LP_NUM_THREADS="$CPU_THREADS"

# Mesa: paralelismo e cache. Não forçamos llvmpipe; se uma GPU real existir,
# o stack gráfico fica livre para usá-la.
export MESA_GLTHREAD=true
export MESA_SHADER_CACHE_DISABLE=false
export MESA_SHADER_CACHE_MAX_SIZE=1G
export __GL_SHADER_DISK_CACHE=1
export __GL_THREADED_OPTIMIZATIONS=1

if id -u "$SESSION_USER" >/dev/null 2>&1; then
  USER_HOME="$(getent passwd "$SESSION_USER" | cut -d: -f6)"
  mkdir -p "$USER_HOME/.cache/mesa_shader_cache" "$USER_HOME/.cache/nvidia"
  chown -R "$SESSION_USER:$SESSION_USER" "$USER_HOME/.cache" 2>/dev/null || true
  export MESA_SHADER_CACHE_DIR="$USER_HOME/.cache/mesa_shader_cache"
  export __GL_SHADER_DISK_CACHE_PATH="$USER_HOME/.cache/nvidia"
fi

# Ajustes seguros quando o host permite. Falhas são ignoradas porque o Colab
# pode bloquear sysctls/governors mesmo quando a sessão está saudável.
if command -v sysctl >/dev/null 2>&1; then
  sysctl -w vm.swappiness=10 >/dev/null 2>&1 || true
  sysctl -w vm.vfs_cache_pressure=50 >/dev/null 2>&1 || true
  sysctl -w fs.inotify.max_user_watches=524288 >/dev/null 2>&1 || true
  sysctl -w fs.inotify.max_user_instances=1024 >/dev/null 2>&1 || true
fi

for governor in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
  [ -w "$governor" ] || continue
  printf '%s' performance > "$governor" 2>/dev/null || true
done

ulimit -n 1048576 2>/dev/null || ulimit -n 65535 2>/dev/null || true

# Tracker 3 não funciona corretamente no kernel Colab observado (Landlock
# ausente) e só estava consumindo CPU/log. Desabilitamos apenas o minerador.
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

export MV_PERF_JSON="$PERF_JSON"
python3 - <<'PY'
import json, os, time
p = os.environ['MV_PERF_JSON']
data = {
    'profile': 'max',
    'cpu_threads': int(os.environ.get('MV_CPU_THREADS', '1') or 1),
    'ram_mb': int(os.environ.get('MV_RAM_MB', '0') or 0),
    'gpu_available': os.environ.get('MV_GPU_AVAILABLE') == '1',
    'gpu_name': os.environ.get('MV_GPU_NAME', ''),
    'gpu_vram_mb': int(os.environ.get('MV_GPU_VRAM_MB', '0') or 0),
    'gpu_driver': os.environ.get('MV_GPU_DRIVER', ''),
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
  printf ' | GPU: indisponível, renderização gráfica por CPU\n'
fi
