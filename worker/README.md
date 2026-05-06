# 3D Product Studio — Worker

This runs on your **RTX 5090 local machine** and connects to the web app to process render jobs.

## Pipeline

```
Product Images
     ↓
[rembg] Background removal
     ↓
[Hunyuan3D-2] Image → 3D model (.glb)   ← BEST quality, free, MIT license
     ↓
[Blender 4.x] Scene composition + lighting + camera
   • Living Room / Bedroom / Balcony / Garden / Kitchen
   • Cat or dog placement (via free CC0 3D assets)
   • Blender Cycles GPU rendering (RTX 5090)
     ↓
3-second cinematic video (.mp4 1080p)
     ↓
Upload results → Web App
```

## One-time Setup

```bash
bash worker/setup.sh
```

This will:
1. Create a Python virtual environment
2. Clone and install **Hunyuan3D-2** (~7GB weights downloaded from HuggingFace)
3. Pre-cache the **rembg** background removal model
4. Check **Blender 4.x** is installed

### Install Blender (if needed)
Download from https://www.blender.org/download/ and add to PATH:
```bash
export PATH=$PATH:/path/to/blender-4.x/bin
```

## Running the Worker

```bash
source worker/.venv/bin/activate

python worker/worker.py \
  --api-url https://YOUR-APP.replit.app \
  --worker-name "RTX5090-Main" \
  --gpu-model "NVIDIA GeForce RTX 5090"
```

The worker will:
- Register itself in the **Workers** page of the web app
- Poll for pending jobs every 3 seconds
- Process each job end-to-end
- Push live progress updates (visible in the Jobs dashboard)
- Upload the rendered video + thumbnail

## GPU Performance (RTX 5090 estimates)

| Stage | Time |
|---|---|
| Background removal (rembg) | ~1s |
| Hunyuan3D-2 3D generation | ~15-30s |
| Blender scene setup | ~5s |
| Blender Cycles render (72 frames, 128 samples) | ~60-120s |
| **Total per job** | **~2-3 minutes** |

## Tuning Quality

Edit `worker/blender_scenes/*.py` to adjust:
- `scene.cycles.samples` — higher = better quality, slower (128 → 256 → 512)
- `scene.frame_end` — longer video (72 = 3s at 24fps)
- `scene.render.resolution_x/y` — 4K output: set to 3840×2160

Edit `worker/worker.py` line in `generate_3d_hunyuan()`:
- `--steps 50` → `--steps 100` for even higher 3D quality (doubles generation time)

## Adding Animals (Cat/Dog)

Download free CC0 cat/dog 3D models from:
- https://sketchfab.com/search?q=cat&features=downloadable&licenses=7c23a1ba438d4306920229c12afcb5f9
- https://www.cgtrader.com/free-3d-models/animals

Save them as:
```
worker/assets/cat.glb
worker/assets/dog.glb
```

The Blender scene scripts will automatically import and place them next to the product.

## Troubleshooting

**Hunyuan3D-2 not found**: Run `bash worker/setup.sh` first

**Blender not found**: Install Blender 4.x and add to PATH

**CUDA out of memory**: Lower `--steps` to 25 in `generate_3d_hunyuan()`, or use `--device cpu` (slow)

**Job shows "failed"**: Click the job in the web app to see the full error message
