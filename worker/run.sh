#!/usr/bin/env bash
# ==============================================================================
# Cat-Nap — Worker Launcher
#
# Activates the same venv location logic as setup.sh and starts worker.py.
#
# Usage examples:
#   bash worker/run.sh
#   bash worker/run.sh --api-url https://cat-nap.replit.app --worker-name RTX4080S
#
# Optional env vars:
#   CATNAP_VENV            Override venv path
#   CATNAP_WORKER_NAME     Default worker name if --worker-name not provided
#   CATNAP_GPU_MODEL       Default GPU label if --gpu-model not provided
#   CATNAP_API_URL         Default API URL if --api-url not provided
#   CATNAP_BLENDER_PATH    Full path to blender executable (IMPORTANT on Windows/WSL)
#   CATNAP_FFMPEG_PATH     Full path to ffmpeg executable
#   CATNAP_AUTO_SETUP      If 1 (default), auto-run setup when venv missing/broken
#   CATNAP_AUTO_INSTALL    If 1 (default), auto-install missing Python deps
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
HUNYUAN_DIR="$PROJECT_ROOT/Hunyuan3D-2.1"

# Match setup.sh venv selection exactly.
DEFAULT_VENV="$SCRIPT_DIR/.venv"
if [[ "$SCRIPT_DIR" == /mnt/* ]]; then
  SAFE_NAME="$(basename "$PROJECT_ROOT" | tr '[:space:]' '_' | tr -cd '[:alnum:]_-')"
  SAFE_VENV="$HOME/.venvs/${SAFE_NAME}-worker"
  VENV="${CATNAP_VENV:-$SAFE_VENV}"
else
  VENV="${CATNAP_VENV:-$DEFAULT_VENV}"
fi

if [ ! -f "$VENV/bin/activate" ]; then
  if [ "${CATNAP_AUTO_SETUP:-1}" = "1" ]; then
    echo ""
    echo "[run] venv missing at $VENV — running setup.sh automatically ..."
    bash "$SCRIPT_DIR/setup.sh"
  else
    echo ""
    echo "ERROR: venv not found at $VENV"
    echo "Run setup first:  bash \"$SCRIPT_DIR/setup.sh\""
    echo ""
    exit 1
  fi
fi

# shellcheck disable=SC1090
source "$VENV/bin/activate"

PY="$VENV/bin/python3"
if [ ! -x "$PY" ]; then
  if [ "${CATNAP_AUTO_SETUP:-1}" = "1" ]; then
    echo ""
    echo "[run] python missing in venv ($PY) — running setup.sh automatically ..."
    bash "$SCRIPT_DIR/setup.sh"
  else
    echo ""
    echo "ERROR: python not found in venv: $PY"
    echo "Rebuild with:  bash \"$SCRIPT_DIR/setup.sh\""
    echo ""
    exit 1
  fi
fi

if [ ! -x "$PY" ]; then
  echo ""; echo "ERROR: setup did not produce a working python at $PY"; echo ""; exit 1
fi

if [ ! -d "$HUNYUAN_DIR/hy3dshape" ]; then
  echo ""
  echo "ERROR: Hunyuan3D-2.1 not found at: $HUNYUAN_DIR"
  echo "Fix with:  git clone https://github.com/Tencent-Hunyuan/Hunyuan3D-2.1.git \"$HUNYUAN_DIR\""
  echo ""
  exit 1
fi

# Auto-install any missing Python deps into the active venv.
REQ_CHECK=$("$PY" - <<'PY'
mods = [
    "requests", "PIL", "rembg", "onnxruntime", "torch", "torchvision",
    "diffusers", "transformers", "accelerate", "huggingface_hub",
    "einops", "scipy", "trimesh", "omegaconf", "timm", "torchdiffeq",
]
missing = []
for m in mods:
    try:
        __import__(m)
    except Exception:
        missing.append(m)
print(",".join(missing))
PY
)

if [ -n "$REQ_CHECK" ]; then
  if [ "${CATNAP_AUTO_INSTALL:-1}" = "1" ]; then
    echo ""
    echo "[run] Missing deps in $VENV: $REQ_CHECK"
    echo "[run] Installing from requirements.txt ..."
    "$PY" -m pip install -r "$SCRIPT_DIR/requirements.txt"
  else
    echo ""; echo "ERROR: Missing deps: $REQ_CHECK"; echo ""; exit 1
  fi
fi

# ── Blender path resolution ────────────────────────────────────────────────────
# KEY ISSUE: On Windows/WSL the WSL-installed Linux Blender reports OptiX as
# active but renders through a compatibility layer at ~CPU speed (~25s/frame).
# The Windows native blender.exe has direct GPU access (~1-3s/frame on 4080S).
# This function finds the Windows binary automatically.
_resolve_blender() {
  # Explicit env var always wins
  if [ -n "${CATNAP_BLENDER_PATH:-}" ]; then
    echo "$CATNAP_BLENDER_PATH"
    return
  fi
  # Under WSL on a /mnt/* path: scan for Windows Blender installations
  if [[ "$SCRIPT_DIR" == /mnt/* ]]; then
    local drive
    drive=$(echo "$SCRIPT_DIR" | cut -d/ -f3)  # e.g. "d"
    for candidate in \
      "/mnt/${drive}/blender-5.1.1/blender-5.1.1-windows-x64/blender.exe" \
      "/mnt/${drive}/blender-5.1.0/blender-5.1.0-windows-x64/blender.exe" \
      "/mnt/${drive}/blender-4.3.2/blender-4.3.2-windows-x64/blender.exe" \
      "/mnt/${drive}/blender-4.3.1/blender-4.3.1-windows-x64/blender.exe" \
      "/mnt/c/Program Files/Blender Foundation/Blender 5.1/blender.exe" \
      "/mnt/c/Program Files/Blender Foundation/Blender 4.3/blender.exe"; do
      if [ -f "$candidate" ]; then
        # Keep as /mnt/... WSL path — subprocess.Popen inside WSL needs this.
        # WSL interop automatically executes the .exe via the Windows kernel.
        echo "$candidate"
        return
      fi
    done
  fi
  echo ""  # fall back to worker.py PATH search
}

_BLENDER_PATH=$(_resolve_blender)

# ── Build worker args ─────────────────────────────────────────────────────────
HAS_WORKER_NAME=0; HAS_GPU_MODEL=0; HAS_HUNYUAN_DIR=0
HAS_API_URL=0; HAS_BLENDER=0; HAS_FFMPEG=0
for arg in "$@"; do
  case "$arg" in
    --api-url)      HAS_API_URL=1 ;;
    --worker-name)  HAS_WORKER_NAME=1 ;;
    --gpu-model)    HAS_GPU_MODEL=1 ;;
    --hunyuan-dir)  HAS_HUNYUAN_DIR=1 ;;
    --blender-path) HAS_BLENDER=1 ;;
    --ffmpeg-path)  HAS_FFMPEG=1 ;;
  esac
done

EXTRA_ARGS=()
[ $HAS_API_URL     -eq 0 ] && EXTRA_ARGS+=(--api-url "${CATNAP_API_URL:-https://cat-nap.replit.app}")
[ $HAS_WORKER_NAME -eq 0 ] && EXTRA_ARGS+=(--worker-name "${CATNAP_WORKER_NAME:-Local-RTX4080S}")
[ $HAS_GPU_MODEL   -eq 0 ] && EXTRA_ARGS+=(--gpu-model "${CATNAP_GPU_MODEL:-NVIDIA RTX 4080 Super}")
[ $HAS_HUNYUAN_DIR -eq 0 ] && EXTRA_ARGS+=(--hunyuan-dir "$HUNYUAN_DIR")
[ $HAS_BLENDER     -eq 0 ] && [ -n "$_BLENDER_PATH" ] && EXTRA_ARGS+=(--blender-path "$_BLENDER_PATH")
[ $HAS_FFMPEG      -eq 0 ] && [ -n "${CATNAP_FFMPEG_PATH:-}" ] && EXTRA_ARGS+=(--ffmpeg-path "$CATNAP_FFMPEG_PATH")

echo ""
echo "Launching worker with:"
echo "  venv:        $VENV"
echo "  python:      $PY"
echo "  hunyuan-dir: $HUNYUAN_DIR"
echo "  blender:     ${_BLENDER_PATH:-(system PATH — set CATNAP_BLENDER_PATH for GPU boost on WSL)}"
[ $HAS_API_URL -eq 0 ] && echo "  api-url:     ${CATNAP_API_URL:-https://cat-nap.replit.app}"
echo ""

exec "$PY" "$SCRIPT_DIR/worker.py" "${EXTRA_ARGS[@]}" "$@"
