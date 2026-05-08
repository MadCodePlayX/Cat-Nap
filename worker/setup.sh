#!/usr/bin/env bash
# ==============================================================================
# Cat-Nap — GPU Worker Setup
# Run once from WSL2, Linux, or RunPod to bootstrap the full Python env.
#
# Usage:
#   bash worker/setup.sh
#
# What it does:
#   1. Validates Python 3.11 / 3.12 / 3.10 is available
#   2. Creates a venv with --copies (required for WSL on Windows NTFS drives)
#   3. Installs PyTorch 2.6.0 + torchvision from the CUDA 12.4 wheel index
#   4. Installs all Python deps
#   5. Clones Hunyuan3D-2.1 and installs its deps
#   6. Pre-fetches model weights and rembg model
#   7. Checks / installs Blender
#   8. Full verification pass with ✓ / ✗ per dep
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
HUNYUAN_DIR="$PROJECT_ROOT/Hunyuan3D-2.1"
# Venv location:
# - default: worker/.venv
# - WSL + /mnt/* workspace: use Linux filesystem to avoid NTFS symlink issues
# - override anytime via CATNAP_VENV=/path/to/venv
DEFAULT_VENV="$SCRIPT_DIR/.venv"
if [[ "$SCRIPT_DIR" == /mnt/* ]]; then
  SAFE_NAME="$(basename "$PROJECT_ROOT" | tr '[:space:]' '_' | tr -cd '[:alnum:]_-')"
  SAFE_VENV="$HOME/.venvs/${SAFE_NAME}-worker"
  VENV="${CATNAP_VENV:-$SAFE_VENV}"
  echo "      [info] Workspace is on /mnt/* (Windows drive)."
  echo "      [info] Using Linux-side venv at: $VENV"
else
  VENV="${CATNAP_VENV:-$DEFAULT_VENV}"
fi

print_header() {
  echo ""
  echo "=============================================="
  echo "  Cat-Nap GPU Worker Setup"
  echo "=============================================="
  echo ""
}

die() { echo ""; echo "ERROR: $*"; echo ""; exit 1; }

# ── 0. Find Python 3.10 / 3.11 / 3.12 ────────────────────────────────────────
print_header
echo "[0/6] Checking Python version ..."

PYTHON_BIN=""
for candidate in python3.12 python3.11 python3.10 python3; do
  if command -v "$candidate" &>/dev/null; then
    VER=$("$candidate" -c "import sys; print(sys.version_info[:2])" 2>/dev/null)
    if [[ "$VER" == "(3, 10)" || "$VER" == "(3, 11)" || "$VER" == "(3, 12)" ]]; then
      PYTHON_BIN="$candidate"
      break
    fi
  fi
done

if [ -z "$PYTHON_BIN" ]; then
  die "Python 3.10 / 3.11 / 3.12 not found.
Install it with: sudo apt-get install python3.11 python3.11-venv python3.11-dev"
fi
echo "      Using $PYTHON_BIN ($($PYTHON_BIN --version))"

# ── 1. System deps ─────────────────────────────────────────────────────────────
echo ""
echo "[1/6] System dependencies ..."

if command -v ffmpeg &>/dev/null; then
  echo "      ffmpeg ✓  ($(ffmpeg -version 2>&1 | head -1 | cut -d' ' -f3))"
elif command -v apt-get &>/dev/null; then
  echo "      Installing ffmpeg ..."
  sudo apt-get install -y ffmpeg --quiet 2>&1 | tail -1
  echo "      ffmpeg installed ✓"
else
  echo "      ⚠ ffmpeg not found — install it: https://ffmpeg.org/download.html"
fi

# ── 2. Virtual environment ─────────────────────────────────────────────────────
echo ""
echo "[2/6] Python virtual environment ..."

# --copies is critical for WSL running on a Windows NTFS mount (/mnt/d, /mnt/c …).
# NTFS does not support POSIX symlinks, so the default venv layout (lib64 -> lib)
# fails with "Operation not permitted". --copies avoids all symlinks.
if [ -d "$VENV" ]; then
  # Re-use existing venv only if it's healthy (pip + python both present)
  if [ -x "$VENV/bin/pip" ] && [ -x "$VENV/bin/python3" ]; then
    echo "      Existing venv looks healthy — reusing ✓"
  else
    echo "      Existing venv is broken — rebuilding with --copies ..."
    rm -rf "$VENV"
    "$PYTHON_BIN" -m venv --copies "$VENV" \
      || die "venv creation failed. Check that python3-venv is installed:
  sudo apt-get install python3.11-venv"
    echo "      Venv created ✓"
  fi
else
  echo "      Creating venv with --copies (symlink-safe) ..."
  "$PYTHON_BIN" -m venv --copies "$VENV" \
    || die "venv creation failed. Check that python3-venv is installed:
  sudo apt-get install python3.11-venv"
  echo "      Venv created ✓"
fi

PY="$VENV/bin/python3"
PIP="$VENV/bin/pip"

# Activate target venv for this script run when not already active.
# (If setup.sh is executed, activation only affects this process; users still
# need to `source <venv>/bin/activate` in their own shell after setup.)
if [ -z "${VIRTUAL_ENV:-}" ] || [ "$VIRTUAL_ENV" != "$VENV" ]; then
  if [ -f "$VENV/bin/activate" ]; then
    # shellcheck disable=SC1090
    source "$VENV/bin/activate"
    echo "      [info] Activated venv for setup: $VENV"
  fi
fi

"$PIP" install --upgrade pip wheel --quiet
echo "      pip upgraded ✓"

# ── 3. PyTorch (CUDA wheels) ───────────────────────────────────────────────────
echo ""
echo "[3/6] PyTorch 2.6.0 + CUDA 12.4 ..."

# Check if CUDA torch is already installed and correct
TORCH_OK=$("$PY" -c "
import sys
try:
    import torch
    ok = torch.__version__.startswith('2.6') and torch.cuda.is_available()
    print('yes' if ok else 'no')
except Exception:
    print('no')
" 2>/dev/null)

if [ "$TORCH_OK" = "yes" ]; then
  TORCH_VER=$("$PY" -c "import torch; print(torch.__version__)")
  echo "      torch $TORCH_VER + CUDA already installed ✓"
else
  echo "      Installing torch==2.6.0+cu124, torchvision==0.21.0+cu124 ..."
  "$PIP" install \
    "torch==2.6.0+cu124" \
    "torchvision==0.21.0+cu124" \
    "torchaudio==2.6.0+cu124" \
    --index-url https://download.pytorch.org/whl/cu124 \
    --quiet \
    && echo "      torch 2.6.0 + CUDA ✓" \
    || die "torch install failed — check internet and CUDA driver version."

  # Verify CUDA is actually usable
  "$PY" -c "
import torch, sys
if not torch.cuda.is_available():
    print('      ⚠ torch installed but CUDA not available (driver issue?)')
    print(f'        CUDA_HOME={torch.version.cuda}, devices={torch.cuda.device_count()}')
else:
    print(f'      CUDA {torch.version.cuda} on {torch.cuda.get_device_name(0)} ✓')
"
fi

# ── 4. Python packages ─────────────────────────────────────────────────────────
echo ""
echo "[4/6] Python packages ..."

echo "      Core worker deps ..."
"$PIP" install \
  "requests>=2.31.0" \
  "Pillow>=10.0.0" \
  "websocket-client>=1.7.0" \
  --quiet

echo "      Hunyuan3D-2.1 deps (pinned) ..."
"$PIP" install \
  "transformers==4.46.0" \
  "diffusers==0.30.0" \
  "accelerate==1.1.1" \
  "huggingface-hub==0.30.2" \
  "safetensors==0.4.4" \
  "numpy==1.24.4" \
  "scipy==1.14.1" \
  "einops==0.8.0" \
  "trimesh==4.4.7" \
  "pymeshlab==2022.2.post3" \
  "pygltflib==1.16.3" \
  "xatlas==0.0.9" \
  "open3d==0.18.0" \
  "omegaconf==2.3.0" \
  "tqdm==4.66.5" \
  "opencv-python==4.10.0.84" \
  "imageio==2.36.0" \
  "scikit-image==0.24.0" \
  "timm>=1.0.0" \
  "torchdiffeq>=0.2.4" \
  --quiet

echo "      rembg + onnxruntime-gpu ..."
"$PIP" install "rembg==2.0.65" "onnxruntime-gpu>=1.17.0" --quiet

echo "      All Python packages installed ✓"

# ── 5. Hunyuan3D-2.1 ──────────────────────────────────────────────────────────
echo ""
echo "[5/6] Hunyuan3D-2.1 ..."

# Rename legacy 2.0 dir if present
LEGACY_DIR="$PROJECT_ROOT/Hunyuan3D-2"
if [ -d "$LEGACY_DIR" ] && [ ! -d "$HUNYUAN_DIR" ]; then
  echo "      Renaming legacy Hunyuan3D-2 → Hunyuan3D-2.legacy ..."
  mv "$LEGACY_DIR" "$LEGACY_DIR.legacy" || true
fi

if [ ! -d "$HUNYUAN_DIR" ]; then
  echo "      Cloning Hunyuan3D-2.1 ..."
  git clone https://github.com/Tencent-Hunyuan/Hunyuan3D-2.1.git "$HUNYUAN_DIR" \
    || die "git clone failed — check internet connection."
  echo "      Cloned ✓"
else
  echo "      Already cloned — pulling latest ..."
  git -C "$HUNYUAN_DIR" pull --quiet
fi

# Validate structure
if [ ! -d "$HUNYUAN_DIR/hy3dshape" ]; then
  echo ""
  echo "  ✗ ERROR: $HUNYUAN_DIR/hy3dshape not found."
  echo "    Your clone is from the wrong repo or is incomplete."
  echo "    Fix: rm -rf $HUNYUAN_DIR"
  echo "         git clone https://github.com/Tencent-Hunyuan/Hunyuan3D-2.1.git $HUNYUAN_DIR"
  echo ""
else
  echo "      hy3dshape subdir present ✓"
fi

# Pre-fetch shape weights (shape model only, ~3 GB; paint skipped in Phase 1)
echo "      Pre-fetching shape weights (~3 GB, Ctrl-C to skip) ..."
"$PY" -c "
from huggingface_hub import snapshot_download
snapshot_download(
    repo_id='tencent/Hunyuan3D-2.1',
    allow_patterns=['hunyuan3d-dit-*/**', 'hunyuan3d-dit-*', '*.json'],
    ignore_patterns=['hunyuan3d-paint*/**', '*.txt', '*.md'],
)
print('      Shape weights cached ✓')
" && true || echo "      ⚠ Weight prefetch skipped — will auto-download on first job."

# Pre-cache rembg model
echo "      Pre-caching rembg model ..."
"$PY" -c "
from rembg import remove
from PIL import Image
remove(Image.new('RGBA', (32, 32)))
print('      rembg model cached ✓')
" && true || echo "      ⚠ rembg cache skipped — will download on first job."

# ── 6. Blender ─────────────────────────────────────────────────────────────────
echo ""
echo "[6/6] Blender ..."

BLENDER_BIN=""
for b in blender "$HOME/.local/bin/blender"; do
  if command -v "$b" &>/dev/null || [ -x "$b" ]; then
    BLENDER_BIN="$b"
    break
  fi
done

if [ -n "$BLENDER_BIN" ]; then
  echo "      $("$BLENDER_BIN" --version 2>&1 | head -1) ✓"
else
  echo "      Blender not found — installing Blender 4.3.2 ..."
  BV="4.3.2"
  BT="blender-${BV}-linux-x64.tar.xz"
  BU="https://download.blender.org/release/Blender4.3/${BT}"
  BD="$HOME/.local/blender"

  [ -f "/tmp/$BT" ] || wget -q --show-progress -O "/tmp/$BT" "$BU"
  mkdir -p "$BD"
  tar -xf "/tmp/$BT" -C "$BD" --strip-components=1
  rm -f "/tmp/$BT"
  mkdir -p "$HOME/.local/bin"
  ln -sf "$BD/blender" "$HOME/.local/bin/blender"
  BLENDER_BIN="$HOME/.local/bin/blender"
  echo "      $("$BLENDER_BIN" --version 2>&1 | head -1) installed ✓"
fi

# Persist ~/.local/bin in PATH
if ! grep -qF '.local/bin' "$HOME/.bashrc" 2>/dev/null; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
fi
export PATH="$HOME/.local/bin:$PATH"

# ── Verification ───────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Verification"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

"$PY" -c "
import sys, shutil
ok = True

def chk(name, fn):
    global ok
    try:
        result = fn()
        sym = '✓' if result else '⚠'
        if not result: ok = False
        print(f'  {sym}  {name}')
    except Exception as e:
        print(f'  ✗  {name}: {e}')
        ok = False

chk('Python',       lambda: sys.version.split()[0])
chk('torch + CUDA', lambda: __import__('torch').cuda.is_available())
chk('torchvision',  lambda: bool(__import__('torchvision').__version__))
chk('Pillow',       lambda: bool(__import__('PIL').__version__))
chk('rembg',        lambda: bool(__import__('rembg')))
chk('onnxruntime',  lambda: bool(__import__('onnxruntime').__version__))
chk('diffusers',    lambda: bool(__import__('diffusers').__version__))
chk('transformers', lambda: bool(__import__('transformers').__version__))
chk('accelerate',   lambda: bool(__import__('accelerate').__version__))
chk('huggingface_hub', lambda: bool(__import__('huggingface_hub').__version__))
chk('trimesh',      lambda: bool(__import__('trimesh').__version__))
chk('einops',       lambda: bool(__import__('einops').__version__))
chk('scipy',        lambda: bool(__import__('scipy').__version__))
chk('omegaconf',    lambda: bool(__import__('omegaconf').__version__))
chk('timm',         lambda: bool(__import__('timm').__version__))
chk('requests',     lambda: bool(__import__('requests').__version__))
chk('websocket',    lambda: bool(__import__('websocket').__version__))

import os
hy = os.path.join('$HUNYUAN_DIR', 'hy3dshape')
chk('hy3dshape dir', lambda: os.path.isdir(hy))

b = shutil.which('blender') or '$BLENDER_BIN'
chk(f'blender ({b})', lambda: bool(b) and os.path.isfile(b))

sys.exit(0 if ok else 1)
"
VERIFY_EXIT=$?

echo ""
if [ $VERIFY_EXIT -eq 0 ]; then
  echo "  All checks passed ✓"
else
  echo "  ⚠ Some checks failed — see ✗ / ⚠ lines above."
  echo ""
  echo "  Common fixes:"
  echo "    ✗ torch + CUDA  → re-run step 3: pip install torch==2.6.0+cu124 torchvision==0.21.0+cu124 --index-url https://download.pytorch.org/whl/cu124"
  echo "    ✗ hy3dshape dir → git clone https://github.com/Tencent-Hunyuan/Hunyuan3D-2.1.git $HUNYUAN_DIR"
  echo "    ✗ blender       → re-run this script or install manually from https://www.blender.org/download/"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Start the worker:"
echo ""
echo "  source $VENV/bin/activate"
echo ""
echo "  python $SCRIPT_DIR/worker.py \\"
echo "    --api-url https://cat-nap.replit.app \\"
echo "    --worker-name 'Local-RTX4080S' \\"
echo "    --gpu-model 'NVIDIA RTX 4080 Super' \\"
echo "    --hunyuan-dir $HUNYUAN_DIR \\"
echo "    --blender-path \$(which blender)"
echo ""
echo "  or use the launcher (auto-activates venv):"
echo "    bash $SCRIPT_DIR/run.sh --api-url https://cat-nap.replit.app"
echo ""
echo "  (on Windows add:)"
echo "    --blender-path 'D:\\blender-5.1.1\\...\\blender.exe' \\"
echo "    --ffmpeg-path 'D:\\ffmpeg\\bin\\ffmpeg.exe'"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
