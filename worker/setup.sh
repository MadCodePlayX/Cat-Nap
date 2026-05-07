#!/usr/bin/env bash
# ============================================================
# 3D Product Studio — Worker Setup Script
# Run this ONCE on your local GPU machine (WSL2, Linux, RunPod).
# ============================================================
# NOTE: set -e removed intentionally — optional steps (weight
# pre-fetch, rembg cache) should not abort the whole script.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Always use explicit venv paths — never rely on PATH / bash hash cache
VENV="$SCRIPT_DIR/.venv"
PY="$VENV/bin/python3"
PIP="$VENV/bin/pip"

echo ""
echo "=============================================="
echo "  3D Product Studio — Worker Setup"
echo "  RTX 4080 Super / 5090 / RunPod Edition"
echo "=============================================="
echo ""

# ── 0. System deps ────────────────────────────────────────
echo "[0/5] Installing system dependencies ..."

# ffmpeg — required for video compression before upload
if command -v ffmpeg &>/dev/null; then
  echo "      ffmpeg already installed ✓"
elif command -v apt-get &>/dev/null; then
  echo "      Installing ffmpeg via apt ..."
  sudo apt-get install -y ffmpeg --quiet 2>&1 | tail -1
  echo "      ffmpeg installed ✓"
else
  echo "      ⚠ apt-get not found — install ffmpeg manually: https://ffmpeg.org/download.html"
fi

# ── 1. Python env ─────────────────────────────────────────
echo ""
echo "[1/5] Creating Python virtual environment ..."

# --system-site-packages: inherit system torch/CUDA so we don't re-download 10GB
python3 -m venv --system-site-packages "$VENV"

"$PIP" install --upgrade pip wheel --quiet

# ── PyTorch ───────────────────────────────────────────────
if "$PY" -c "import torch; assert torch.cuda.is_available()" 2>/dev/null; then
  echo "      PyTorch with CUDA already available — skipping torch install ✓"
else
  echo "      Installing PyTorch with CUDA 12.4 ..."
  "$PIP" install torch torchvision torchaudio \
    --index-url https://download.pytorch.org/whl/cu124 --quiet
fi

# ── Python packages ───────────────────────────────────────
echo "      Installing Python packages ..."
"$PIP" install -r "$SCRIPT_DIR/requirements.txt" --quiet

# rembg[gpu] specifically needs onnxruntime-gpu for CUDA inference.
# Re-install explicitly because pip may have resolved the plain [gpu] extra
# to a cached/system onnxruntime without CUDA support.
echo "      Installing rembg[gpu] + onnxruntime-gpu ..."
"$PIP" install "rembg[gpu]>=2.0.50" onnxruntime-gpu --quiet

# Force huggingface_hub into the venv — hy3dgen install sometimes resolves
# to the system-site version which can be outdated or broken
"$PIP" install "huggingface-hub>=0.20.0" --force-reinstall --quiet

# ── nvdiffrast ────────────────────────────────────────────
# CUDA rasterizer for Hunyuan3D-2 texture baking — not on PyPI
if ! "$PY" -c "import nvdiffrast" 2>/dev/null; then
  echo "      Installing nvdiffrast from source (needs CUDA toolkit + gcc) ..."
  "$PIP" install git+https://github.com/NVlabs/nvdiffrast.git \
    --no-build-isolation --quiet \
    && echo "      nvdiffrast installed ✓" \
    || echo "      ⚠ nvdiffrast failed — texturing will use fallback materials"
else
  echo "      nvdiffrast already available ✓"
fi

echo "      Python env ready ✓"

# ── 2. Hunyuan3D-2 ────────────────────────────────────────
echo ""
echo "[2/5] Cloning Hunyuan3D-2 ..."
HUNYUAN_DIR="$PROJECT_ROOT/Hunyuan3D-2"

if [ ! -d "$HUNYUAN_DIR" ]; then
  git clone https://github.com/Tencent-Hunyuan/Hunyuan3D-2.git "$HUNYUAN_DIR"
  echo "      Cloned ✓"
else
  echo "      Already cloned — pulling latest ..."
  git -C "$HUNYUAN_DIR" pull
fi

echo "      Installing hy3dgen package ..."
"$PIP" install -e "$HUNYUAN_DIR" --quiet
# Re-pin huggingface_hub after hy3dgen may have downgraded it
"$PIP" install "huggingface-hub>=0.20.0" --force-reinstall --quiet
echo "      hy3dgen installed ✓"

# ── Pre-fetch weights (optional ~7GB) ─────────────────────
echo "      Pre-fetching Hunyuan3D-2 weights (~7GB, Ctrl-C to skip) ..."
"$PY" -c "
from huggingface_hub import snapshot_download
snapshot_download(
    repo_id='tencent/Hunyuan3D-2',
    local_dir='$HUNYUAN_DIR/weights',
    ignore_patterns=['*.md', '*.txt']
)
print('      Weights downloaded ✓')
" && true || echo "      ⚠ Weight pre-fetch skipped — worker downloads on first job automatically."

# ── 3. rembg model cache ──────────────────────────────────
echo ""
echo "[3/5] Pre-caching rembg background removal model ..."
"$PY" -c "
from rembg import remove
from PIL import Image
remove(Image.new('RGBA', (64,64)))
print('      rembg model cached ✓')
" && true || echo "      ⚠ rembg cache skipped — will download on first job."

# ── 4. Blender 4.x ────────────────────────────────────────
echo ""
echo "[4/5] Checking / installing Blender 4.x ..."

# Check PATH and also ~/.local/bin (our install location)
BLENDER_BIN=""
if command -v blender &>/dev/null; then
  BLENDER_BIN="$(command -v blender)"
elif [ -f "$HOME/.local/bin/blender" ]; then
  BLENDER_BIN="$HOME/.local/bin/blender"
fi

if [ -n "$BLENDER_BIN" ]; then
  echo "      $("$BLENDER_BIN" --version 2>&1 | head -1) already installed ✓"
else
  echo "      Blender not found — downloading Blender 4.3.2 ..."
  BLENDER_VERSION="4.3.2"
  BLENDER_TARBALL="blender-${BLENDER_VERSION}-linux-x64.tar.xz"
  BLENDER_URL="https://download.blender.org/release/Blender4.3/${BLENDER_TARBALL}"
  BLENDER_INSTALL_DIR="$HOME/.local/blender"

  # Reuse already-downloaded tarball if present
  if [ ! -f "/tmp/${BLENDER_TARBALL}" ]; then
    wget -q --show-progress -O "/tmp/${BLENDER_TARBALL}" "${BLENDER_URL}"
  else
    echo "      Tarball already in /tmp — reusing ✓"
  fi

  mkdir -p "${BLENDER_INSTALL_DIR}"
  tar -xf "/tmp/${BLENDER_TARBALL}" -C "${BLENDER_INSTALL_DIR}" --strip-components=1
  rm -f "/tmp/${BLENDER_TARBALL}"

  mkdir -p "$HOME/.local/bin"
  ln -sf "${BLENDER_INSTALL_DIR}/blender" "$HOME/.local/bin/blender"
  BLENDER_BIN="$HOME/.local/bin/blender"
  echo "      $("$BLENDER_BIN" --version 2>&1 | head -1) installed ✓"
fi

# ── Persist ~/.local/bin in PATH ──────────────────────────
BASHRC="$HOME/.bashrc"
PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'
if ! grep -qF '.local/bin' "$BASHRC" 2>/dev/null; then
  echo "$PATH_LINE" >> "$BASHRC"
  echo "      Added ~/.local/bin to ~/.bashrc ✓"
fi
# Apply for this session too
export PATH="$HOME/.local/bin:$PATH"

# ── 5. Done ───────────────────────────────────────────────
echo ""
echo "[5/5] Verifying installation ..."
echo ""

# Quick sanity check — print version/status for each critical dep
"$PY" -c "
import sys
ok = True
deps = [
    ('torch + CUDA', lambda: __import__('torch').cuda.is_available()),
    ('PIL',          lambda: bool(__import__('PIL').__version__)),
    ('rembg',        lambda: bool(__import__('rembg'))),
    ('huggingface_hub', lambda: bool(__import__('huggingface_hub').__version__)),
    ('diffusers',    lambda: bool(__import__('diffusers').__version__)),
    ('transformers', lambda: bool(__import__('transformers').__version__)),
    ('accelerate',   lambda: bool(__import__('accelerate').__version__)),
    ('einops',       lambda: bool(__import__('einops').__version__)),
    ('scipy',        lambda: bool(__import__('scipy').__version__)),
    ('trimesh',      lambda: bool(__import__('trimesh').__version__)),
    ('requests',     lambda: bool(__import__('requests').__version__)),
]
for name, check in deps:
    try:
        result = check()
        status = '✓' if result else '⚠'
        print(f'      {status} {name}')
        if not result: ok = False
    except Exception as e:
        print(f'      ✗ {name}: {e}')
        ok = False
sys.exit(0 if ok else 1)
" && echo "" || echo "      ⚠ Some deps missing — check output above"

echo "=============================================="
echo "  Setup complete! Start the worker with:"
echo ""
echo "  source $VENV/bin/activate"
echo "  python $SCRIPT_DIR/worker.py \\"
echo "    --api-url https://cat-nap.replit.app \\"
echo "    --worker-name 'Local-RTX4080S' \\"
echo "    --gpu-model 'NVIDIA RTX 4080 Super' \\"
echo "    --hunyuan-dir $HUNYUAN_DIR"
echo "=============================================="
