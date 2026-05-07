#!/usr/bin/env bash
# ============================================================
# 3D Product Studio — Repair Script
# Rebuilds the venv using the SYSTEM torch (which already has
# CUDA working), then installs the matching torchvision from
# the correct index so torchvision::nms ops work on GPU.
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
HUNYUAN_DIR="$PROJECT_ROOT/Hunyuan3D-2"

VENV="$SCRIPT_DIR/.venv"
PY="$VENV/bin/python3"
PIP="$VENV/bin/pip"

# Prefer python3.11 — PyTorch has wheels for 3.10-3.12 but NOT 3.13/3.14 yet.
# Falls back to python3.12, then python3.10, then system python3.
PYTHON_BIN=""
for candidate in python3.11 python3.12 python3.10 python3; do
  if command -v "$candidate" &>/dev/null; then
    VER=$("$candidate" -c "import sys; print(sys.version_info[:2])")
    if [[ "$VER" == "(3, 10)" || "$VER" == "(3, 11)" || "$VER" == "(3, 12)" ]]; then
      PYTHON_BIN="$candidate"
      break
    fi
  fi
done
if [ -z "$PYTHON_BIN" ]; then
  echo "ERROR: Python 3.10/3.11/3.12 not found."
  echo "Install it with: sudo apt-get install python3.11 python3.11-venv"
  exit 1
fi
echo "Using $PYTHON_BIN ($($PYTHON_BIN --version))"

echo ""
echo "=============================================="
echo "  3D Product Studio — Worker Repair"
echo "=============================================="

# ── ffmpeg ────────────────────────────────────────────────
echo ""
echo "[0] Checking ffmpeg ..."
if command -v ffmpeg &>/dev/null; then
  echo "    ffmpeg already installed ✓"
elif command -v apt-get &>/dev/null; then
  sudo apt-get install -y ffmpeg -qq && echo "    ffmpeg installed ✓"
else
  echo "    ⚠ Install ffmpeg manually: https://ffmpeg.org/download.html"
fi

# ── Rebuild venv WITH system-site-packages ────────────────
# We inherit the system torch (which has working CUDA drivers).
# Then we install matching torchvision on top.
echo ""
echo "[1] Rebuilding venv with Python 3.11 (system-site-packages for torch) ..."
rm -rf "$VENV"
"$PYTHON_BIN" -m venv --system-site-packages "$VENV"
"$PIP" install --upgrade pip wheel --quiet
"$PIP" cache purge 2>/dev/null || true
echo "    Venv ready ✓ ($("$PY" --version))"

# ── Detect torch in the venv (inherited from system) ──────
echo ""
echo "[2] Detecting torch version in venv ..."
TORCH_VER=$("$PY" -c "import torch; print(torch.__version__)" 2>/dev/null || echo "")
if [ -z "$TORCH_VER" ]; then
  echo "    torch not found via system-site-packages — installing from CUDA index ..."
  "$PIP" install torch torchvision torchaudio \
    --index-url https://download.pytorch.org/whl/cu124 \
    --no-cache-dir --quiet \
    && echo "    torch installed from CUDA index ✓" \
    || { echo "    ✗ torch install failed — check internet connection"; exit 1; }
  TORCH_VER=$("$PY" -c "import torch; print(torch.__version__)" 2>/dev/null || echo "")
fi

TORCH_CUDA=$("$PY" -c "import torch; print(torch.cuda.is_available())" 2>/dev/null || echo "False")
echo "    torch: $TORCH_VER  CUDA available: $TORCH_CUDA"

# Extract major.minor (e.g. 2.11 from 2.11.0+cu124)
TORCH_MAJOR_MINOR=$(echo "$TORCH_VER" | grep -oP '^\d+\.\d+')
echo "    Torch major.minor: $TORCH_MAJOR_MINOR"

# ── Install matching torchvision ──────────────────────────
# torchvision version = 0.{torch_minor+15}.0 for torch 2.x
# e.g. torch 2.6 → torchvision 0.21  (6+15=21)
#      torch 2.7 → torchvision 0.22
# For nightly builds (torch 2.11+), use the nightly index.
echo ""
echo "[3] Installing torchvision that matches torch $TORCH_MAJOR_MINOR ..."

TORCH_MINOR=$(echo "$TORCH_MAJOR_MINOR" | cut -d. -f2)
TV_MINOR=$((TORCH_MINOR + 15))
TV_VER="0.${TV_MINOR}.0"

# Determine which CUDA index to use (stable vs nightly)
# Torch 2.7+ is on the stable cu124 index; older nightlies use the nightly index
TORCH_MINOR_INT=$(echo "$TORCH_MINOR" | grep -oP '^\d+')
if [ "$TORCH_MINOR_INT" -ge 8 ]; then
  WHEEL_INDEX="https://download.pytorch.org/whl/nightly/cu124"
  echo "    Using nightly index (torch $TORCH_MAJOR_MINOR is a nightly build)"
else
  WHEEL_INDEX="https://download.pytorch.org/whl/cu124"
  echo "    Using stable index"
fi

echo "    Installing torchvision==${TV_VER} from $WHEEL_INDEX ..."
"$PIP" install "torchvision==${TV_VER}" \
  --index-url "$WHEEL_INDEX" \
  --no-cache-dir --quiet \
  && echo "    torchvision ${TV_VER} installed ✓" \
  || {
    # Fallback: install without version pin from same index
    echo "    Exact version not found — installing latest torchvision from index ..."
    "$PIP" install torchvision \
      --index-url "$WHEEL_INDEX" \
      --no-cache-dir --quiet \
      && echo "    torchvision installed ✓" \
      || echo "    ✗ torchvision install failed — will try to continue anyway"
  }

# Verify the nms op actually works on GPU before wasting time on a job
echo ""
echo "    Verifying torchvision::nms on GPU ..."
"$PY" -c "
import torch, torchvision.ops as ops
if not torch.cuda.is_available():
    print('    ⚠ CUDA not available — skipping GPU NMS test')
else:
    boxes  = torch.tensor([[0.0,0.0,1.0,1.0],[0.1,0.1,0.9,0.9]], device='cuda')
    scores = torch.tensor([0.9, 0.8], device='cuda')
    ops.nms(boxes, scores, 0.5)
    print('    torchvision::nms on GPU ✓')
" || echo "    ✗ NMS test failed — torchvision CUDA ops still broken (see above)"

# ── All other Python packages ─────────────────────────────
echo ""
echo "[4] Installing remaining Python packages ..."
"$PIP" install \
  "Pillow>=10.0.0" \
  "requests>=2.31.0" \
  "numpy>=1.24.0" \
  "tqdm>=4.65.0" \
  "trimesh>=4.0.0" \
  "diffusers>=0.27.0" \
  "transformers>=4.38.0" \
  "accelerate>=0.27.0" \
  "einops>=0.7.0" \
  "scipy>=1.11.0" \
  "huggingface-hub>=0.20.0" \
  --quiet
echo "    Core packages installed ✓"

"$PIP" install "rembg[gpu]>=2.0.50" onnxruntime-gpu --quiet
echo "    rembg[gpu] + onnxruntime-gpu installed ✓"

# ── hy3dgen ───────────────────────────────────────────────
if [ -d "$HUNYUAN_DIR" ]; then
  echo ""
  echo "[5] Installing hy3dgen ..."
  "$PIP" install -e "$HUNYUAN_DIR" --quiet
  "$PIP" install "huggingface-hub>=0.20.0" --force-reinstall --quiet
  echo "    hy3dgen installed ✓"
else
  echo ""
  echo "[5] ⚠ Hunyuan3D-2 not found at $HUNYUAN_DIR — run setup.sh first"
fi

# ── nvdiffrast (optional) ─────────────────────────────────
if ! "$PY" -c "import nvdiffrast" 2>/dev/null; then
  echo ""
  echo "[6] Installing nvdiffrast (optional, needs CUDA toolkit + gcc) ..."
  "$PIP" install git+https://github.com/NVlabs/nvdiffrast.git \
    --no-build-isolation --quiet 2>/dev/null \
    && echo "    nvdiffrast installed ✓" \
    || echo "    ⚠ nvdiffrast skipped — texturing will use Blender materials instead"
fi

# ── Blender PATH ──────────────────────────────────────────
if ! grep -qF '.local/bin' "$HOME/.bashrc" 2>/dev/null; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
fi
export PATH="$HOME/.local/bin:$PATH"

# ── Final sanity check ────────────────────────────────────
echo ""
echo "[7] Final dependency check ..."
"$PY" -c "
import shutil, sys

def chk(name, fn):
    try:
        ok = fn()
        print(f'    {\"✓\" if ok else \"⚠\"} {name}')
        return ok
    except Exception as e:
        print(f'    ✗ {name}: {e}')
        return False

all_ok = True
all_ok &= chk('torch + CUDA',    lambda: __import__('torch').cuda.is_available())
all_ok &= chk('torchvision NMS', lambda: (
    __import__('torchvision.ops', fromlist=['nms']).nms(
        __import__('torch').tensor([[0.,0.,1.,1.]], device='cuda'),
        __import__('torch').tensor([0.9], device='cuda'), 0.5
    ) is not None or True
))
all_ok &= chk('PIL',             lambda: bool(__import__('PIL').__version__))
all_ok &= chk('rembg',          lambda: bool(__import__('rembg')))
all_ok &= chk('diffusers',      lambda: bool(__import__('diffusers').__version__))
all_ok &= chk('transformers',   lambda: bool(__import__('transformers').__version__))
all_ok &= chk('huggingface_hub',lambda: bool(__import__('huggingface_hub').__version__))
all_ok &= chk('einops',         lambda: bool(__import__('einops')))
all_ok &= chk('scipy',          lambda: bool(__import__('scipy').__version__))
all_ok &= chk('trimesh',        lambda: bool(__import__('trimesh').__version__))
all_ok &= chk('requests',       lambda: bool(__import__('requests').__version__))

blender = shutil.which('blender')
all_ok &= bool(blender)
print(f'    {\"✓\" if blender else \"✗\"} blender ({blender or \"not on PATH\"})')

sys.exit(0 if all_ok else 1)
"
EXIT=$?

echo ""
echo "=============================================="
if [ $EXIT -eq 0 ]; then
  echo "  All checks passed! Start the worker:"
  echo ""
  echo "  source $VENV/bin/activate"
  echo "  python $SCRIPT_DIR/worker.py \\"
  echo "    --api-url https://cat-nap.replit.app \\"
  echo "    --worker-name 'Local-RTX4080S' \\"
  echo "    --gpu-model 'NVIDIA RTX 4080 Super' \\"
  echo "    --hunyuan-dir $HUNYUAN_DIR"
else
  echo "  ⚠ Some checks failed — see ✗ lines above."
  echo ""
  echo "  If torchvision NMS still fails, run this to see your exact"
  echo "  system torch version and manually find the matching torchvision:"
  echo "    python3 -c \"import torch; print(torch.__version__)\""
  echo "    # Then check: https://github.com/pytorch/vision#installation"
fi
echo "=============================================="
