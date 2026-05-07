#!/usr/bin/env bash
# ============================================================
# 3D Product Studio — Quick Repair Script
# Run this if setup.sh failed partway through, or after
# pulling updates that add new dependencies.
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
HUNYUAN_DIR="$PROJECT_ROOT/Hunyuan3D-2"

VENV="$SCRIPT_DIR/.venv"
PY="$VENV/bin/python3"
PIP="$VENV/bin/pip"

echo ""
echo "=============================================="
echo "  3D Product Studio — Quick Repair"
echo "=============================================="

# ── ffmpeg ────────────────────────────────────────────────
echo ""
echo "[1/4] Checking ffmpeg ..."
if command -v ffmpeg &>/dev/null; then
  echo "      ffmpeg already installed ✓"
elif command -v apt-get &>/dev/null; then
  echo "      Installing ffmpeg ..."
  sudo apt-get install -y ffmpeg -qq
  echo "      ffmpeg installed ✓"
else
  echo "      ⚠ Install ffmpeg manually: https://ffmpeg.org/download.html"
fi

# ── Python packages ───────────────────────────────────────
echo ""
echo "[2/4] Installing / repairing Python packages ..."
"$PIP" install --upgrade pip wheel --quiet

"$PIP" install \
  "Pillow>=10.0.0" \
  "requests>=2.31.0" \
  "numpy>=1.24.0" \
  "trimesh>=4.0.0" \
  "diffusers>=0.27.0" \
  "transformers>=4.38.0" \
  "accelerate>=0.27.0" \
  "einops>=0.7.0" \
  "scipy>=1.11.0" \
  "huggingface-hub>=0.20.0" \
  --force-reinstall --quiet

echo "      Core packages installed ✓"

# rembg[gpu] needs onnxruntime-gpu for CUDA inference
"$PIP" install "rembg[gpu]>=2.0.50" onnxruntime-gpu --quiet
echo "      rembg[gpu] + onnxruntime-gpu installed ✓"

# hy3dgen (Hunyuan3D-2 Python API)
if [ -d "$HUNYUAN_DIR" ]; then
  "$PIP" install -e "$HUNYUAN_DIR" --quiet
  echo "      hy3dgen installed ✓"
else
  echo "      ⚠ Hunyuan3D-2 not found at $HUNYUAN_DIR — run setup.sh first"
fi

# nvdiffrast (optional — CUDA texture baking)
if ! "$PY" -c "import nvdiffrast" 2>/dev/null; then
  echo "      Installing nvdiffrast from source ..."
  "$PIP" install git+https://github.com/NVlabs/nvdiffrast.git \
    --no-build-isolation --quiet \
    && echo "      nvdiffrast installed ✓" \
    || echo "      ⚠ nvdiffrast failed — texturing will use fallback materials"
else
  echo "      nvdiffrast already available ✓"
fi

# ── Blender PATH ──────────────────────────────────────────
echo ""
echo "[3/4] Checking Blender ..."
BLENDER_BIN=""
if command -v blender &>/dev/null; then
  BLENDER_BIN="$(command -v blender)"
elif [ -f "$HOME/.local/bin/blender" ]; then
  BLENDER_BIN="$HOME/.local/bin/blender"
fi

if [ -n "$BLENDER_BIN" ]; then
  echo "      $("$BLENDER_BIN" --version 2>&1 | head -1) ✓"
else
  echo "      ⚠ Blender not found — run setup.sh to install it"
fi

# Persist and apply ~/.local/bin in PATH
BASHRC="$HOME/.bashrc"
if ! grep -qF '.local/bin' "$BASHRC" 2>/dev/null; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$BASHRC"
fi
export PATH="$HOME/.local/bin:$PATH"

# ── Sanity check ──────────────────────────────────────────
echo ""
echo "[4/4] Dependency check ..."
"$PY" -c "
import shutil, sys
results = []
deps = [
    ('torch + CUDA', lambda: __import__('torch').cuda.is_available()),
    ('PIL',          lambda: bool(__import__('PIL').__version__)),
    ('rembg',        lambda: bool(__import__('rembg'))),
    ('onnxruntime',  lambda: bool(__import__('onnxruntime').__version__)),
    ('huggingface_hub', lambda: bool(__import__('huggingface_hub').__version__)),
    ('diffusers',    lambda: bool(__import__('diffusers').__version__)),
    ('transformers', lambda: bool(__import__('transformers').__version__)),
    ('accelerate',   lambda: bool(__import__('accelerate').__version__)),
    ('einops',       lambda: bool(__import__('einops').__version__)),
    ('scipy',        lambda: bool(__import__('scipy').__version__)),
    ('trimesh',      lambda: bool(__import__('trimesh').__version__)),
    ('requests',     lambda: bool(__import__('requests').__version__)),
]
all_ok = True
for name, check in deps:
    try:
        ok = check()
        icon = '✓' if ok else '⚠'
        print(f'      {icon} {name}')
        if not ok: all_ok = False
    except Exception as e:
        print(f'      ✗ {name}: {e}')
        all_ok = False

blender = shutil.which('blender')
print(f\"      {'✓' if blender else '✗'} blender ({blender or 'not on PATH'})\")
if not blender: all_ok = False

sys.exit(0 if all_ok else 1)
"

EXIT=$?

echo ""
echo "=============================================="
if [ $EXIT -eq 0 ]; then
  echo "  All good! Start the worker:"
  echo ""
  echo "  source $VENV/bin/activate"
  echo "  python $SCRIPT_DIR/worker.py \\"
  echo "    --api-url https://cat-nap.replit.app \\"
  echo "    --worker-name 'Local-RTX4080S' \\"
  echo "    --gpu-model 'NVIDIA RTX 4080 Super' \\"
  echo "    --hunyuan-dir $HUNYUAN_DIR"
else
  echo "  ⚠ Some checks failed — see ✗ lines above."
  echo "  If Blender is missing, run setup.sh first."
fi
echo "=============================================="
