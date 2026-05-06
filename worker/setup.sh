#!/usr/bin/env bash
# ============================================================
# 3D Product Studio — Worker Setup Script
# Run this ONCE on your RTX 5090 machine.
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo ""
echo "=============================================="
echo "  3D Product Studio — Worker Setup"
echo "  RTX 5090 Edition"
echo "=============================================="
echo ""

# ── 1. Python env ─────────────────────────────────────────
echo "[1/5] Creating Python virtual environment ..."
python3 -m venv "$SCRIPT_DIR/.venv"
source "$SCRIPT_DIR/.venv/bin/activate"

pip install --upgrade pip wheel
pip install -r "$SCRIPT_DIR/requirements.txt"

# Install PyTorch with CUDA 12.4 support for RTX 5090
pip install torch torchvision torchaudio \
  --index-url https://download.pytorch.org/whl/cu124

echo "      Python env ready ✓"

# ── 2. Hunyuan3D-2 ────────────────────────────────────────
echo ""
echo "[2/5] Cloning Hunyuan3D-2 (highest quality free 3D model) ..."
HUNYUAN_DIR="$PROJECT_ROOT/Hunyuan3D-2"

if [ ! -d "$HUNYUAN_DIR" ]; then
  git clone https://github.com/Tencent-Hunyuan/Hunyuan3D-2.git "$HUNYUAN_DIR"
  echo "      Cloned ✓"
else
  echo "      Already cloned — pulling latest ..."
  git -C "$HUNYUAN_DIR" pull
fi

echo "      Installing Hunyuan3D-2 dependencies ..."
pip install -e "$HUNYUAN_DIR"

# Download model weights (first run only — ~7GB)
echo "      Downloading model weights (this may take a while on first run) ..."
python3 -c "
from huggingface_hub import snapshot_download
snapshot_download(
    repo_id='tencent/Hunyuan3D-2',
    local_dir='$HUNYUAN_DIR/weights',
    ignore_patterns=['*.md', '*.txt']
)
print('      Weights downloaded ✓')
"

# ── 3. rembg model ────────────────────────────────────────
echo ""
echo "[3/5] Pre-downloading rembg background removal model ..."
python3 -c "from rembg import remove; from PIL import Image; remove(Image.new('RGB', (64,64)))"
echo "      rembg model cached ✓"

# ── 4. Blender check ──────────────────────────────────────
echo ""
echo "[4/5] Checking Blender installation ..."
if command -v blender &> /dev/null; then
  BLENDER_VER=$(blender --version 2>&1 | head -1)
  echo "      $BLENDER_VER ✓"
else
  echo ""
  echo "  ⚠️  Blender not found on PATH."
  echo "  Download Blender 4.x from https://www.blender.org/download/"
  echo "  Then add it to your PATH, e.g.:"
  echo "    export PATH=\$PATH:/path/to/blender-4.x/bin"
  echo ""
fi

# ── 5. Done ───────────────────────────────────────────────
echo ""
echo "[5/5] Setup complete!"
echo ""
echo "=============================================="
echo "  To start the worker:"
echo ""
echo "  source worker/.venv/bin/activate"
echo "  python worker/worker.py \\"
echo "    --api-url https://YOUR-APP.replit.app \\"
echo "    --worker-name 'RTX5090-Main'"
echo ""
echo "  Your RTX 5090 will automatically:"
echo "    1. Register in the Workers page"
echo "    2. Poll for pending render jobs"
echo "    3. Run Hunyuan3D-2 for 3D generation"
echo "    4. Render scenes with Blender Cycles (GPU)"
echo "    5. Upload results back to the web app"
echo "=============================================="
