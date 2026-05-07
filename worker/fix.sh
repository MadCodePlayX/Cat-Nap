#!/usr/bin/env bash
# ============================================================
# 3D Product Studio — Clean Rebuild Script
# Deletes the old venv and rebuilds it from scratch.
# Fixes torch/torchvision version conflicts from --system-site-packages.
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
HUNYUAN_DIR="$PROJECT_ROOT/Hunyuan3D-2"

VENV="$SCRIPT_DIR/.venv"
PY="$VENV/bin/python3"
PIP="$VENV/bin/pip"

echo ""
echo "=============================================="
echo "  3D Product Studio — Clean Venv Rebuild"
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

# ── Nuke old venv ─────────────────────────────────────────
echo ""
echo "[1] Removing old venv (eliminates inherited system package conflicts) ..."
rm -rf "$VENV"
echo "    Old venv removed ✓"

# ── Fresh venv — NO --system-site-packages ────────────────
echo ""
echo "[2] Creating clean venv ..."
python3 -m venv "$VENV"
"$PIP" install --upgrade pip wheel --quiet
echo "    Clean venv created ✓"

# ── torch + torchvision pinned together from CUDA index ───
# MUST be installed together and from the CUDA index.
# torch==2.6.0 + torchvision==0.21.0 are the matching stable cu124 builds.
# Never install torchvision from PyPI — it ships without CUDA ops.
echo ""
echo "[3] Installing torch 2.6.0 + torchvision 0.21.0 (CUDA 12.4) ..."
"$PIP" install \
  "torch==2.6.0+cu124" \
  "torchvision==0.21.0+cu124" \
  "torchaudio==2.6.0+cu124" \
  --index-url https://download.pytorch.org/whl/cu124 \
  --quiet
echo "    torch + torchvision (CUDA) installed ✓"

# Verify CUDA is available
"$PY" -c "
import torch
assert torch.cuda.is_available(), 'CUDA not available — check your GPU drivers'
print(f'    torch {torch.__version__}, CUDA {torch.version.cuda}, device: {torch.cuda.get_device_name(0)} ✓')
" || echo "    ⚠ CUDA check failed — GPU may still work at runtime"

# ── All other Python packages ─────────────────────────────
echo ""
echo "[4] Installing Python packages ..."
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

# rembg[gpu] — CUDA onnxruntime for background removal
"$PIP" install "rembg[gpu]>=2.0.50" onnxruntime-gpu --quiet
echo "    rembg[gpu] + onnxruntime-gpu installed ✓"

# ── hy3dgen ───────────────────────────────────────────────
if [ -d "$HUNYUAN_DIR" ]; then
  echo ""
  echo "[5] Installing hy3dgen ..."
  "$PIP" install -e "$HUNYUAN_DIR" --quiet
  # Re-pin huggingface_hub — hy3dgen may have changed it
  "$PIP" install "huggingface-hub>=0.20.0" --force-reinstall --quiet
  echo "    hy3dgen installed ✓"
else
  echo ""
  echo "[5] ⚠ Hunyuan3D-2 not found at $HUNYUAN_DIR"
  echo "    Run setup.sh to clone it, then re-run fix.sh"
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
BLENDER_BIN=""
if command -v blender &>/dev/null; then
  BLENDER_BIN="$(command -v blender)"
elif [ -f "$HOME/.local/bin/blender" ]; then
  export PATH="$HOME/.local/bin:$PATH"
  BLENDER_BIN="$HOME/.local/bin/blender"
fi

BASHRC="$HOME/.bashrc"
if ! grep -qF '.local/bin' "$BASHRC" 2>/dev/null; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$BASHRC"
fi
export PATH="$HOME/.local/bin:$PATH"

# ── Sanity check ──────────────────────────────────────────
echo ""
echo "[7] Final dependency check ..."
"$PY" -c "
import shutil, sys

checks = [
    ('torch + CUDA',     lambda: __import__('torch').cuda.is_available()),
    ('torchvision',      lambda: bool(__import__('torchvision').__version__)),
    ('PIL',              lambda: bool(__import__('PIL').__version__)),
    ('rembg',            lambda: bool(__import__('rembg'))),
    ('onnxruntime',      lambda: bool(__import__('onnxruntime').__version__)),
    ('diffusers',        lambda: bool(__import__('diffusers').__version__)),
    ('transformers',     lambda: bool(__import__('transformers').__version__)),
    ('huggingface_hub',  lambda: bool(__import__('huggingface_hub').__version__)),
    ('einops',           lambda: bool(__import__('einops'))),
    ('scipy',            lambda: bool(__import__('scipy').__version__)),
    ('trimesh',          lambda: bool(__import__('trimesh').__version__)),
    ('requests',         lambda: bool(__import__('requests').__version__)),
]

# Also verify torch/torchvision ops actually work
def check_torchvision_ops():
    import torch, torchvision.ops
    boxes = torch.tensor([[0.0,0.0,1.0,1.0]])
    scores = torch.tensor([0.9])
    torchvision.ops.nms(boxes.cuda(), scores.cuda(), 0.5)
    return True

checks.append(('torchvision::nms (GPU)', check_torchvision_ops))

all_ok = True
for name, fn in checks:
    try:
        ok = fn()
        print(f'    {\"✓\" if ok else \"⚠\"} {name}')
        if not ok: all_ok = False
    except Exception as e:
        print(f'    ✗ {name}: {e}')
        all_ok = False

blender = shutil.which('blender')
print(f'    {\"✓\" if blender else \"✗\"} blender ({blender or \"not on PATH\"})')
if not blender: all_ok = False
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
fi
echo "=============================================="
