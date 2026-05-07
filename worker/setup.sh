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
# --system-site-packages: inherit system torch/CUDA — avoids re-downloading on RunPod
python3 -m venv --system-site-packages "$SCRIPT_DIR/.venv"
source "$SCRIPT_DIR/.venv/bin/activate"

pip install --upgrade pip wheel --quiet

# Skip torch reinstall if already present with CUDA (common on RunPod)
if python3 -c "import torch; assert torch.cuda.is_available()" 2>/dev/null; then
  echo "      PyTorch with CUDA already available — skipping torch install ✓"
  pip install -r "$SCRIPT_DIR/requirements.txt" --quiet
else
  echo "      Installing PyTorch with CUDA 12.4 ..."
  pip install torch torchvision torchaudio \
    --index-url https://download.pytorch.org/whl/cu124 --quiet
  pip install -r "$SCRIPT_DIR/requirements.txt" --quiet
fi

# nvdiffrast — CUDA rasterizer used by the custom_rasterizer shim for texturing
# Not on PyPI — install from GitHub source (requires CUDA toolkit + C++ compiler)
if ! python3 -c "import nvdiffrast" 2>/dev/null; then
  echo "      Installing nvdiffrast from source (needs CUDA toolkit) ..."
  pip install git+https://github.com/NVlabs/nvdiffrast.git --no-build-isolation --quiet
  echo "      nvdiffrast installed ✓"
else
  echo "      nvdiffrast already available ✓"
fi

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
pip install huggingface_hub --upgrade --quiet
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

# ── 4. Blender 4.x ────────────────────────────────────────
echo ""
echo "[4/5] Checking / installing Blender 4.x ..."
if command -v blender &> /dev/null; then
  BLENDER_VER=$(blender --version 2>&1 | head -1)
  echo "      $BLENDER_VER ✓"
else
  echo "      Blender not found — downloading Blender 4.3.2 ..."
  BLENDER_VERSION="4.3.2"
  BLENDER_TARBALL="blender-${BLENDER_VERSION}-linux-x64.tar.xz"
  BLENDER_URL="https://download.blender.org/release/Blender4.3/${BLENDER_TARBALL}"
  BLENDER_INSTALL_DIR="/opt/blender"

  wget -q --show-progress -O "/tmp/${BLENDER_TARBALL}" "${BLENDER_URL}"
  mkdir -p "${BLENDER_INSTALL_DIR}"
  tar -xf "/tmp/${BLENDER_TARBALL}" -C "${BLENDER_INSTALL_DIR}" --strip-components=1
  rm "/tmp/${BLENDER_TARBALL}"

  ln -sf "${BLENDER_INSTALL_DIR}/blender" /usr/local/bin/blender
  echo "      Blender $(blender --version 2>&1 | head -1) installed ✓"
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
