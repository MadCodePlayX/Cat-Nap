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
  echo ""
  echo "ERROR: venv not found at $VENV"
  echo "Run setup first:"
  echo "  bash \"$SCRIPT_DIR/setup.sh\""
  echo ""
  exit 1
fi

# shellcheck disable=SC1090
source "$VENV/bin/activate"

PY="$VENV/bin/python3"
if [ ! -x "$PY" ]; then
  echo ""
  echo "ERROR: python not found in venv: $PY"
  echo "Rebuild with:"
  echo "  bash \"$SCRIPT_DIR/setup.sh\""
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

# Build defaults only when user didn't pass corresponding args.
HAS_WORKER_NAME=0
HAS_GPU_MODEL=0
HAS_HUNYUAN_DIR=0
for arg in "$@"; do
  case "$arg" in
    --worker-name) HAS_WORKER_NAME=1 ;;
    --gpu-model) HAS_GPU_MODEL=1 ;;
    --hunyuan-dir) HAS_HUNYUAN_DIR=1 ;;
  esac
done

EXTRA_ARGS=()
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
echo ""

exec "$PY" "$SCRIPT_DIR/worker.py" "${EXTRA_ARGS[@]}" "$@"
