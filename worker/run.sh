#!/usr/bin/env bash
# ==============================================================================
# Cat-Nap — Worker Launcher
#
# Activates the same venv location logic as setup.sh and starts worker.py.
#
# Usage examples:
#   bash worker/run.sh --api-url https://cat-nap.replit.app --worker-name RTX4080S
#   CATNAP_VENV=/home/me/.venvs/catnap-worker bash worker/run.sh --api-url ...
#
# Optional env vars:
#   CATNAP_VENV          Override venv path
#   CATNAP_WORKER_NAME   Default worker name if --worker-name not provided
#   CATNAP_GPU_MODEL     Default GPU label if --gpu-model not provided
#   CATNAP_API_URL       Default API URL if --api-url not provided
#   CATNAP_AUTO_SETUP    If 1 (default), auto-run setup when venv missing/broken
#   CATNAP_AUTO_INSTALL  If 1 (default), auto-install missing Python deps
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
    echo "Run setup first:"
    echo "  bash \"$SCRIPT_DIR/setup.sh\""
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
    echo "Rebuild with:"
    echo "  bash \"$SCRIPT_DIR/setup.sh\""
    echo ""
    exit 1
  fi
fi

# Re-check after potential auto-setup
if [ ! -x "$PY" ]; then
  echo ""
  echo "ERROR: setup did not produce a working python at $PY"
  echo ""
  exit 1
fi

if [ ! -d "$HUNYUAN_DIR/hy3dshape" ]; then
  echo ""
  echo "ERROR: Hunyuan3D-2.1 not found at: $HUNYUAN_DIR"
  echo "Fix with:"
  echo "  git clone https://github.com/Tencent-Hunyuan/Hunyuan3D-2.1.git \"$HUNYUAN_DIR\""
  echo ""
  exit 1
fi

# Ensure required Python modules exist in the SAME venv this launcher uses.
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
    echo "[run] Installing from requirements.txt into launcher venv ..."
    "$PY" -m pip install -r "$SCRIPT_DIR/requirements.txt"
  else
    echo ""
    echo "ERROR: Missing deps in $VENV: $REQ_CHECK"
    echo "Install with:"
    echo "  \"$PY\" -m pip install -r \"$SCRIPT_DIR/requirements.txt\""
    echo ""
    exit 1
  fi
fi

# Build defaults only when user didn't pass corresponding args.
HAS_WORKER_NAME=0
HAS_GPU_MODEL=0
HAS_HUNYUAN_DIR=0
HAS_API_URL=0
for arg in "$@"; do
  case "$arg" in
    --api-url) HAS_API_URL=1 ;;
    --worker-name) HAS_WORKER_NAME=1 ;;
    --gpu-model) HAS_GPU_MODEL=1 ;;
    --hunyuan-dir) HAS_HUNYUAN_DIR=1 ;;
  esac
done

EXTRA_ARGS=()
if [ $HAS_API_URL -eq 0 ]; then
  EXTRA_ARGS+=(--api-url "${CATNAP_API_URL:-https://cat-nap.replit.app}")
fi
if [ $HAS_WORKER_NAME -eq 0 ]; then
  EXTRA_ARGS+=(--worker-name "${CATNAP_WORKER_NAME:-Local-RTX4080S}")
fi
if [ $HAS_GPU_MODEL -eq 0 ]; then
  EXTRA_ARGS+=(--gpu-model "${CATNAP_GPU_MODEL:-NVIDIA RTX 4080 Super}")
fi
if [ $HAS_HUNYUAN_DIR -eq 0 ]; then
  EXTRA_ARGS+=(--hunyuan-dir "$HUNYUAN_DIR")
fi

echo ""
echo "Launching worker with:"
echo "  venv:        $VENV"
echo "  python:      $PY"
echo "  hunyuan-dir: $HUNYUAN_DIR"
if [ $HAS_API_URL -eq 0 ]; then
  echo "  api-url:     ${CATNAP_API_URL:-https://cat-nap.replit.app} (default)"
fi
echo ""

exec "$PY" "$SCRIPT_DIR/worker.py" "${EXTRA_ARGS[@]}" "$@"
