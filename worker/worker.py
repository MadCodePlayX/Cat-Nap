"""
3D Product Studio — Local GPU Worker
=====================================
Runs on your RTX 5090 machine. Polls the web API for pending jobs,
generates 3D models using Hunyuan3D-2 (highest quality, free),
composes scenes in Blender, and renders AR-quality videos.

Requirements:
  - Python 3.10+
  - CUDA 12+ (RTX 5090)
  - Blender 4.x installed and on PATH
  - See requirements.txt for Python packages
  - Hunyuan3D-2 cloned alongside this worker (see setup.sh)

Usage:
  python worker.py --api-url https://your-replit-app.replit.app --worker-name "RTX5090-Main"
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Callable, Optional

# Ensure ~/.local/bin is on PATH so blender installed by setup.sh is findable
# regardless of how the worker was launched (with or without source activate)
_local_bin = str(Path.home() / ".local" / "bin")
if _local_bin not in os.environ.get("PATH", ""):
    os.environ["PATH"] = _local_bin + os.pathsep + os.environ.get("PATH", "")

import requests
from PIL import Image

# ── GPU performance flags (set before any torch ops) ───────────────────────────
try:
    import torch
    if torch.cuda.is_available():
        torch.backends.cuda.matmul.allow_tf32 = True   # Tensor Cores for matmul
        torch.backends.cudnn.benchmark = True           # Auto-tune conv algorithms
        torch.backends.cudnn.allow_tf32 = True
except Exception:
    pass

# ── Constants ──────────────────────────────────────────────────────────────────
WORKER_DIR = Path(__file__).parent
SCENES_DIR = WORKER_DIR / "blender_scenes"
HEARTBEAT_INTERVAL = 15   # seconds
POLL_INTERVAL = 3         # seconds between job polls
MAX_IMAGE_SIZE = 1024     # px, resize inputs before 3D gen

# ── Pipeline cache — stay loaded in VRAM across jobs ───────────────────────────
SHAPE_PIPELINE = None


# ── API client ─────────────────────────────────────────────────────────────────
class StudioAPI:
    def __init__(self, base_url: str):
        self.base = base_url.rstrip("/")
        self.session = requests.Session()
        self.session.headers["Content-Type"] = "application/json"

    def _url(self, path: str) -> str:
        return f"{self.base}/api{path}"

    def health(self) -> bool:
        try:
            r = self.session.get(self._url("/healthz"), timeout=10)
            return r.status_code == 200
        except Exception:
            return False

    def register_worker(self, name: str, gpu_model: str) -> dict:
        r = self.session.post(self._url("/workers"), json={"name": name, "gpuModel": gpu_model}, timeout=10)
        r.raise_for_status()
        return r.json()

    def heartbeat(self, worker_id: int) -> None:
        try:
            self.session.post(self._url(f"/workers/{worker_id}/heartbeat"), timeout=5)
        except Exception:
            pass

    def get_next_job(self) -> dict | None:
        r = self.session.get(self._url("/jobs/next"), timeout=10)
        r.raise_for_status()
        return r.json().get("job")

    def update_status(self, job_id: int, **kwargs) -> None:
        self.session.patch(self._url(f"/jobs/{job_id}/status"), json=kwargs, timeout=10)

    def get_product(self, product_id: int) -> dict:
        r = self.session.get(self._url(f"/products/{product_id}"), timeout=10)
        r.raise_for_status()
        return r.json()

    def upload_file(self, job_id: int, field: str, file_path: Path) -> str:
        """
        Upload a rendered file. Returns a public URL.
        Since we're self-hosting outputs, we POST as multipart and the server
        saves it and returns a URL. Adjust this to your storage solution
        (e.g. upload to Cloudflare R2, S3, or serve from the API server).
        """
        with open(file_path, "rb") as f:
            files = {"file": (file_path.name, f)}
            data = {"jobId": str(job_id), "field": field}
            r = self.session.post(
                self._url("/uploads"),
                files=files,
                data=data,
                headers={},  # clear Content-Type so requests sets multipart boundary
                timeout=120,
            )
        if r.status_code == 200:
            return r.json().get("url", "")
        # Fallback: return a local file:// path for local dev
        return f"file://{file_path.resolve()}"


# ── Image utilities ────────────────────────────────────────────────────────────
def download_image(url: str, dest: Path, api_base: str = "") -> Path:
    # Handle relative URLs (e.g. /products/image.png served by the web app)
    if url.startswith("/"):
        url = api_base.rstrip("/") + url
    r = requests.get(url, timeout=30, stream=True)
    r.raise_for_status()
    with open(dest, "wb") as f:
        for chunk in r.iter_content(chunk_size=8192):
            f.write(chunk)
    return dest


def prepare_image(src: Path, dest: Path, size: int = MAX_IMAGE_SIZE) -> Path:
    """Resize to square, remove background with rembg."""
    from rembg import remove
    img = Image.open(src).convert("RGBA")
    # Remove background
    img_no_bg = remove(img)
    # Resize
    img_no_bg.thumbnail((size, size), Image.LANCZOS)
    # Pad to square on transparent canvas
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    offset = ((size - img_no_bg.width) // 2, (size - img_no_bg.height) // 2)
    canvas.paste(img_no_bg, offset)
    canvas.save(dest, "PNG")
    return dest


# ── 3D Generation via ComfyUI ─────────────────────────────────────────────────
def generate_3d_via_comfy(image_path: Path, output_glb: Path,
                          comfy_url: str, workflow_path: Path,
                          on_progress: Optional[Callable[[int, str], None]] = None
                          ) -> Path:
    """Run a ComfyUI workflow that takes one image and produces a GLB.

    The workflow JSON must declare which nodes the worker should patch and
    read. Either set these via the env vars CATNAP_LOAD_NODE / CATNAP_SAVE_NODE
    or rely on the defaults below (matching workflows/hunyuan3d_shape.api.json).
    """
    from comfy_client import ComfyClient

    load_node = os.environ.get("CATNAP_LOAD_NODE", "2")    # LoadImage
    save_node = os.environ.get("CATNAP_SAVE_NODE", "10")   # SaveGLB / Hy3DExportMesh

    workflow = json.loads(workflow_path.read_text())
    # Strip _comment_* keys ComfyUI doesn't understand
    workflow = {k: v for k, v in workflow.items() if not k.startswith("_")}
    if load_node not in workflow:
        raise RuntimeError(
            f"Workflow {workflow_path.name} has no node '{load_node}' to patch. "
            f"Set CATNAP_LOAD_NODE to the LoadImage node id. "
            f"Nodes present: {list(workflow.keys())}"
        )
    if save_node not in workflow:
        raise RuntimeError(
            f"Workflow {workflow_path.name} has no node '{save_node}' to read. "
            f"Set CATNAP_SAVE_NODE to your SaveGLB / Hy3DExportMesh node id."
        )

    client = ComfyClient(comfy_url)
    if not client.health():
        raise RuntimeError(
            f"ComfyUI not reachable at {comfy_url}. "
            "Start it with: python main.py --listen 127.0.0.1 --port 8188"
        )

    uploaded_name = client.upload_image(image_path)
    workflow[load_node]["inputs"]["image"] = uploaded_name
    print(f"      [comfy] Uploaded {uploaded_name}, queueing workflow ...")

    glb_bytes = client.run_workflow(
        workflow,
        output_node_id=save_node,
        on_progress=on_progress,
        pct_start=15,
        pct_end=55,
        label="ComfyUI 3D",
    )
    output_glb.write_bytes(glb_bytes)
    print(f"      [comfy] GLB saved: {output_glb.stat().st_size // 1024} KB")
    return output_glb


# ── Texture fallback: dominant color baked as PBR base ────────────────────────
def _apply_dominant_color_fallback(mesh, image_path: Path):
    """When Hunyuan paint fails, sample the dominant non-transparent color from
    the input image and apply it as a flat PBR base color on the mesh. This is
    far better than the default pure-white that Blender otherwise renders."""
    import numpy as np
    from PIL import Image as _PIL
    import trimesh
    import trimesh.visual

    img = _PIL.open(image_path).convert("RGBA").resize((128, 128), _PIL.LANCZOS)
    arr = np.asarray(img)
    rgb = arr[..., :3].astype(np.float32)
    alpha = arr[..., 3].astype(np.float32) / 255.0
    mask = alpha > 0.3
    if mask.sum() < 32:
        avg = rgb.reshape(-1, 3).mean(axis=0)
    else:
        avg = (rgb[mask]).mean(axis=0)
    base = np.clip(avg, 0, 255).astype(np.uint8)
    color_rgba = np.array([base[0], base[1], base[2], 255], dtype=np.uint8)

    # Apply to whatever mesh-like object hy3dgen returned
    meshes = mesh if isinstance(mesh, list) else [mesh]
    for m in meshes:
        try:
            material = trimesh.visual.material.PBRMaterial(
                baseColorFactor=color_rgba,
                metallicFactor=0.0,
                roughnessFactor=0.8,
            )
            m.visual = trimesh.visual.TextureVisuals(material=material)
        except Exception:
            try:
                m.visual.face_colors = color_rgba
            except Exception:
                pass
    print(f"      [fallback] Dominant color RGB=({base[0]},{base[1]},{base[2]})")
    return mesh if isinstance(mesh, list) else meshes[0]


# ── 3D Generation: Hunyuan3D-2 ─────────────────────────────────────────────────
def generate_3d_hunyuan(image_path: Path, output_glb: Path, work_dir: Path,
                        hunyuan_dir: Path | None = None,
                        on_progress: Optional[Callable[[int, str], None]] = None) -> Path:
    """
    Generate a .glb from a single image using Hunyuan3D-2.1 SHAPE pipeline.

    Phase 1 / Chunk 1: shape only. The multiview paint pipeline is intentionally
    skipped — it's the most fragile part of the stack (constant diffusers compat
    breakage, monkey-patched dynamic modules) and gives us no real benefit until
    we're ready to invest in proper PBR. Instead we always bake the dominant
    color of the input image as the mesh's base color, which is fast, never
    fails, and produces a recognizable preview render.

    hunyuan_dir defaults to worker/../Hunyuan3D-2.1/ (set by setup.sh).
    Override with --hunyuan-dir if you cloned it elsewhere.
    """
    import torch

    torch.backends.cuda.matmul.allow_tf32 = True
    torch.backends.cudnn.allow_tf32 = True
    torch.backends.cudnn.benchmark = True
    if torch.cuda.is_available():
        torch.set_float32_matmul_precision("high")

    global SHAPE_PIPELINE

    if hunyuan_dir is None:
        hunyuan_dir = WORKER_DIR.parent / "Hunyuan3D-2.1"

    if not (hunyuan_dir / "hy3dshape").exists():
        raise RuntimeError(
            f"Hunyuan3D-2.1 not found at {hunyuan_dir}.\n"
            "Run: git clone https://github.com/Tencent-Hunyuan/Hunyuan3D-2.1.git "
            f"{hunyuan_dir}\n"
            "Then install its deps — see worker/setup.sh [2/5] for the pip install list.\n"
            "(No pip install -e needed: the worker adds it to sys.path directly.)"
        )

    # 2.1 restructured: the importable package is inside hy3dshape/
    hy3dshape_dir = str(hunyuan_dir / "hy3dshape")
    if hy3dshape_dir not in sys.path:
        sys.path.insert(0, hy3dshape_dir)
    if str(hunyuan_dir) not in sys.path:
        sys.path.insert(0, str(hunyuan_dir))
    if str(WORKER_DIR) not in sys.path:
        sys.path.insert(0, str(WORKER_DIR))

    from PIL import Image as PILImage
    from hy3dshape.pipelines import Hunyuan3DDiTFlowMatchingPipeline

    work_dir.mkdir(parents=True, exist_ok=True)
    image = PILImage.open(image_path).convert("RGBA")

    torch.cuda.empty_cache()
    print(f"      GPU: {torch.cuda.get_device_name(0)}")
    print(f"      Total VRAM: {torch.cuda.get_device_properties(0).total_memory / 1024**3:.1f} GB")

    # ── tqdm progress hook ─────────────────────────────────────────────────────
    import contextlib
    import tqdm as _tqdm_mod

    @contextlib.contextmanager
    def _tqdm_progress(pct_start: int, pct_end: int, label: str):
        """Patch tqdm.update so diffusion steps fire on_progress.
        Only fires for bars with ≤200 total steps (diffusion, not volume decode)
        and throttles to at most one API call every 3 seconds."""
        if on_progress is None:
            yield
            return
        _orig = _tqdm_mod.tqdm.update
        _last_fire: list[float] = [0.0]
        def _hook(self, n: int = 1) -> None:
            _orig(self, n)
            if not self.total or self.total > 200:
                return  # skip volume decode (7k+ steps) and other heavy bars
            now = time.time()
            if now - _last_fire[0] < 3.0:
                return  # throttle: max one API call every 3 seconds
            _last_fire[0] = now
            frac = min(self.n / self.total, 1.0)
            pct = int(pct_start + frac * (pct_end - pct_start))
            elapsed = max(now - getattr(self, "start_t", now - 0.001), 0.001)
            remaining = (self.total - self.n) * (elapsed / max(self.n, 1))
            eta_str = f"ETA {int(remaining)}s" if remaining > 1 else "finishing…"
            on_progress(pct, f"{label} — step {self.n}/{self.total} ({eta_str})")
        _tqdm_mod.tqdm.update = _hook
        try:
            yield
        finally:
            _tqdm_mod.tqdm.update = _orig

    # ── Shape pipeline (cached in VRAM) ────────────────────────────────────────
    if SHAPE_PIPELINE is None:
        print("      Loading Hunyuan3D-2.1 shape pipeline (first run only) ...")
        SHAPE_PIPELINE = Hunyuan3DDiTFlowMatchingPipeline.from_pretrained(
            "tencent/Hunyuan3D-2.1",
            device="cuda",
            # Repo ships shape weights as model.fp16.ckpt (not safetensors).
            # Forcing safetensors makes the loader look for a non-existent file.
            use_safetensors=False,
        )
        if hasattr(SHAPE_PIPELINE, "model"):
            SHAPE_PIPELINE.model = SHAPE_PIPELINE.model.to(
                device="cuda", memory_format=torch.channels_last
            )
        print("      Shape pipeline cached in VRAM ✓")

    print("      Generating 3D mesh ...")
    _t0 = time.time()
    with _tqdm_progress(16, 50, "Shape gen"), \
         torch.inference_mode(), torch.autocast("cuda", dtype=torch.float16):
        mesh = SHAPE_PIPELINE(image=image)[0]
    print(f"      Shape done in {time.time() - _t0:.1f}s  |  "
          f"VRAM {torch.cuda.memory_allocated()/1024**3:.2f} GB allocated")

    # ── Always bake dominant input-image color as the mesh material ───────────
    # (Phase 1: paint pipeline intentionally disabled — see docstring above)
    try:
        mesh = _apply_dominant_color_fallback(mesh, image_path)
        print("      Dominant-color material applied ✓")
    except Exception as _fb_e:
        print(f"      ⚠ Dominant-color material failed ({_fb_e}) — mesh will export untextured")

    # ── Export ─────────────────────────────────────────────────────────────────
    generated = work_dir / "model.glb"
    mesh.export(str(generated))

    if not generated.exists():
        raise RuntimeError(f"Hunyuan3D-2 export failed — GLB not found at {generated}")

    shutil.copy(generated, output_glb)
    torch.cuda.empty_cache()
    return output_glb


def _convert_obj_to_glb(obj_path: Path, glb_path: Path) -> None:
    """Use Blender to convert OBJ → GLB."""
    script = f"""
import bpy
bpy.ops.wm.read_homefile(use_empty=True)
bpy.ops.import_scene.obj(filepath=r'{obj_path}')
bpy.ops.export_scene.gltf(filepath=r'{glb_path}', export_format='GLB')
"""
    tmp = obj_path.with_suffix(".blend_convert.py")
    tmp.write_text(script)
    subprocess.run(["blender", "--background", "--python", str(tmp)], check=True)
    tmp.unlink()


# ── Scene Rendering via Blender ────────────────────────────────────────────────
def render_scene(
    model_glb: Path,
    scene_type: str,
    animal_type: str,
    output_video: Path,
    output_thumbnail: Path,
    blender_bin: str | None = None,
) -> None:
    scene_script = SCENES_DIR / f"{scene_type}.py"
    if not scene_script.exists():
        # Fall back to living_room if scene script missing
        scene_script = SCENES_DIR / "living_room.py"

    if not blender_bin:
        blender_bin = shutil.which("blender")
    if not blender_bin:
        raise RuntimeError(
            "Blender not found. Use --blender-path to specify the Blender executable, "
            "e.g. --blender-path \"D:\\blender-5.1.1\\blender-5.1.1-windows-x64\\blender.exe\""
        )
    print(f"      [render] Using Blender: {blender_bin}")

    # ── Free VRAM held by the shape pipeline so Blender Cycles has room ───────
    try:
        import gc
        import torch
        global SHAPE_PIPELINE
        if SHAPE_PIPELINE is not None:
            SHAPE_PIPELINE = None
            gc.collect()
            torch.cuda.empty_cache()
            torch.cuda.synchronize()
            free, total = torch.cuda.mem_get_info()
            print(f"      [render] Released Hunyuan VRAM — "
                  f"free {free/1024**3:.1f} / {total/1024**3:.1f} GB")
    except Exception as _e:
        print(f"      [render] VRAM release skipped: {_e}")

    # GPU device is configured inside each scene script via
    # bpy.context.preferences.addons['cycles'].preferences
    cmd = [
        blender_bin,
        "--background",
        "--python", str(scene_script),
        "--",
        model_glb.as_posix(),      # forward slashes — Blender cross-platform
        animal_type,
        output_video.as_posix(),   # forward slashes
        output_thumbnail.as_posix(),
    ]

    # Ensure Blender can find NVIDIA libs when running under WSL.
    # WSL ships libcuda.so.1, libnvoptix_loader.so.1, etc. in /usr/lib/wsl/lib,
    # but Blender's subprocess doesn't always pick them up via ldconfig alone.
    # Prepending here is harmless on non-WSL systems (the dir simply won't exist).
    blender_env = os.environ.copy()
    wsl_lib = "/usr/lib/wsl/lib"
    if Path(wsl_lib).is_dir():
        existing = blender_env.get("LD_LIBRARY_PATH", "")
        blender_env["LD_LIBRARY_PATH"] = (
            f"{wsl_lib}:{existing}" if existing else wsl_lib
        )

    # Stream Blender output live — capture_output=True buffers until exit so
    # GPU diagnostic lines are invisible if the worker is killed mid-render.
    import threading
    needles = (
        "[gpu]", "[scene]", "cycles", "cuda", "optix", "device:", "rendered ",
        "fall", "error", "warning", "fail", "saved:", "fra:", "import",
    )
    seen: set = set()
    stdout_lines: list = []
    stderr_lines: list = []

    def _drain(stream, store, prefix):
        for raw in stream:
            line = raw.rstrip()
            store.append(line)
            if any(n in line.lower() for n in needles) and line not in seen:
                print(f"      {prefix} {line}", flush=True)
                seen.add(line)

    with subprocess.Popen(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, env=blender_env
    ) as proc:
        t_out = threading.Thread(target=_drain, args=(proc.stdout, stdout_lines, "[blender]"))
        t_err = threading.Thread(target=_drain, args=(proc.stderr, stderr_lines, "[blender:err]"))
        t_out.start(); t_err.start()
        try:
            proc.wait(timeout=1800)
        except subprocess.TimeoutExpired:
            proc.kill()
            raise RuntimeError("Blender render timed out after 30 minutes")
        finally:
            t_out.join(); t_err.join()

    if proc.returncode != 0:
        raise RuntimeError(
            "Blender render failed:\n--- stdout ---\n" + "\n".join(stdout_lines[-60:]) +
            "\n--- stderr ---\n" + "\n".join(stderr_lines[-60:])
        )


# ── Job processor ──────────────────────────────────────────────────────────────
def process_job(api: StudioAPI, job: dict, worker_id: int,
                hunyuan_dir: Path | None = None, api_base: str = "",
                blender_bin: str | None = None,
                ffmpeg_bin: str | None = None,
                comfy_url: str | None = None,
                comfy_workflow: Path | None = None) -> None:
    job_id = job["id"]
    product_id = job["productId"]
    scene_type = job["sceneType"]          # living_room | bedroom | balcony | garden | kitchen
    animal_type = job["animalType"]        # cat | dog | none

    print(f"\n[Job {job_id}] Starting — product={product_id} scene={scene_type} animal={animal_type}")

    def progress(status: str, stage: str, pct: int, **extra):
        print(f"  [{pct}%] {stage}")
        api.update_status(job_id, status=status, stage=stage, progressPct=pct,
                          workerId=worker_id, **extra)

    with tempfile.TemporaryDirectory(prefix=f"job_{job_id}_") as tmp_str:
        tmp = Path(tmp_str)

        try:
            # ── 1. Claim job ───────────────────────────────────────────────
            progress("claimed", "Preparing inputs", 2)

            # ── 2. Fetch product + images ──────────────────────────────────
            product = api.get_product(product_id)
            image_urls = product.get("imageUrls", [])
            if not image_urls:
                raise RuntimeError("Product has no images. Add at least one image URL first.")

            progress("claimed", "Downloading images", 5)
            raw_images = []
            for i, url in enumerate(image_urls[:4]):  # use up to 4 images
                dest = tmp / f"raw_{i}.jpg"
                download_image(url, dest, api_base=api_base)
                raw_images.append(dest)

            # ── 3. Remove background + prepare ────────────────────────────
            progress("generating_3d", "Removing background", 10)
            prepared_images = []
            for i, img_path in enumerate(raw_images):
                out = tmp / f"prepared_{i}.png"
                prepare_image(img_path, out)
                prepared_images.append(out)

            # Use best image (first) as primary for 3D generation
            primary_image = prepared_images[0]

            # ── 4. Hunyuan3D-2: Image → 3D model ──────────────────────────
            progress("generating_3d", "Running Hunyuan3D-2 (3D generation)", 15)
            model_glb = tmp / "product_model.glb"

            def _on_3d_progress(pct: int, stage: str) -> None:
                progress("generating_3d", stage, pct)

            if comfy_url:
                generate_3d_via_comfy(
                    primary_image, model_glb,
                    comfy_url=comfy_url, workflow_path=comfy_workflow,
                    on_progress=_on_3d_progress,
                )
            else:
                generate_3d_hunyuan(primary_image, model_glb, tmp / "hunyuan_out",
                                   hunyuan_dir=hunyuan_dir,
                                   on_progress=_on_3d_progress)
            progress("generating_3d", "3D model generated", 55)

            # ── 5. Upload GLB model ──────────────────────────────────────────
            progress("compositing", "Uploading 3D model", 57)
            try:
                model_url = api.upload_file(job_id, "glb", model_glb)
                print(f"      GLB uploaded ✓")
            except Exception as _glb_e:
                model_url = None
                print(f"      ⚠ GLB upload failed ({_glb_e}) — 3D viewer unavailable")
            progress("compositing", "Compositing scene in Blender", 60)

            # ── 6. Blender: compose scene + render PNG frame sequence ──────
            # Blender 5.x removed FFMPEG output; we render frames then encode.
            frames_dir = tmp / "frames"
            output_video = tmp / "output.mp4"
            output_thumb = tmp / "thumbnail.png"

            progress("rendering_video", f"Rendering {scene_type} scene", 65)
            render_scene(model_glb, scene_type, animal_type, frames_dir, output_thumb,
                         blender_bin=blender_bin)

            progress("rendering_video", "Encoding video", 90)

            # ── 7. Encode PNG frame sequence → MP4 with ffmpeg ────────────
            _ffmpeg = ffmpeg_bin or shutil.which("ffmpeg") or "ffmpeg"
            frame_pattern = frames_dir.as_posix() + "/frame_%04d.png"
            ffmpeg_cmd = [
                _ffmpeg, "-y",
                "-framerate", "24",
                "-start_number", "1",
                "-i", frame_pattern,
                "-vcodec", "libx264", "-crf", "23",
                "-preset", "fast", "-vf", "scale=-2:720",
                "-pix_fmt", "yuv420p",
                "-movflags", "+faststart",
                str(output_video),
            ]
            ffmpeg_result = subprocess.run(
                ffmpeg_cmd, capture_output=True, text=True, timeout=300)
            if ffmpeg_result.returncode == 0 and output_video.exists():
                upload_video = output_video
                _frame_count = len(list(frames_dir.glob("frame_*.png")))
                _size_kb = output_video.stat().st_size // 1024
                print(f"      Video encoded: {_size_kb} KB ({_frame_count} frames)")
                if _frame_count == 0:
                    raise RuntimeError(
                        "Blender produced 0 frames — scene likely failed silently. "
                        "Check the [scene] / [blender] log lines above.")
                if _size_kb < 150:
                    print(f"      ⚠ Video suspiciously small ({_size_kb} KB) — "
                          "scene may be empty/black. Check product placement & lighting.")
            else:
                raise RuntimeError(
                    f"ffmpeg encoding failed.\n{ffmpeg_result.stderr[-1000:]}")

            # ── 8. Upload outputs ──────────────────────────────────────────
            video_url = api.upload_file(job_id, "video", upload_video)
            thumb_url = api.upload_file(job_id, "thumbnail", output_thumb)

            # ── 8. Mark complete ───────────────────────────────────────────
            api.update_status(
                job_id,
                status="completed",
                stage="Done",
                progressPct=100,
                workerId=worker_id,
                modelUrl=model_url,
                videoUrl=video_url,
                thumbnailUrl=thumb_url,
            )
            print(f"[Job {job_id}] ✓ Completed")

        except Exception as e:
            err = str(e)
            print(f"[Job {job_id}] ✗ Failed: {err}")
            api.update_status(
                job_id,
                status="failed",
                stage="Error",
                errorMessage=err[:1000],
                workerId=worker_id,
            )


# ── Heartbeat thread ───────────────────────────────────────────────────────────
def heartbeat_loop(api: StudioAPI, worker_id: int, stop_event) -> None:
    import threading
    def _loop():
        while not stop_event.is_set():
            api.heartbeat(worker_id)
            stop_event.wait(HEARTBEAT_INTERVAL)
    t = threading.Thread(target=_loop, daemon=True)
    t.start()
    return t


# ── Main ───────────────────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(description="3D Product Studio — Local GPU Worker")
    parser.add_argument("--api-url", required=True,
                        help="Base URL of your Replit app, e.g. https://myapp.replit.app")
    parser.add_argument("--worker-name", default="RTX5090-Worker",
                        help="Display name for this worker in the dashboard")
    parser.add_argument("--gpu-model", default="NVIDIA GeForce RTX 5090",
                        help="GPU model label shown in the Workers page")
    parser.add_argument("--poll-interval", type=float, default=POLL_INTERVAL,
                        help="Seconds between job polls when idle")
    parser.add_argument("--hunyuan-dir", default=None,
                        help="Path to Hunyuan3D-2 repo (default: ../Hunyuan3D-2 relative to worker/)")
    parser.add_argument("--blender-path", default=None,
                        help="Full path to blender executable, e.g. D:\\blender-5.1\\blender.exe")
    parser.add_argument("--ffmpeg-path", default=None,
                        help="Full path to ffmpeg executable, e.g. D:\\ffmpeg\\bin\\ffmpeg.exe")
    parser.add_argument("--comfy-url", default=None,
                        help="If set (e.g. http://127.0.0.1:8188), use a running ComfyUI "
                             "server for 3D generation instead of in-process hy3dgen.")
    parser.add_argument("--comfy-workflow", default=None,
                        help="Path to the ComfyUI workflow JSON (API format). "
                             "Defaults to worker/workflows/hunyuan3d_shape.api.json")
    args = parser.parse_args()

    hunyuan_dir = Path(args.hunyuan_dir) if args.hunyuan_dir else None
    blender_bin = args.blender_path or None
    ffmpeg_bin = args.ffmpeg_path or None
    api_base = args.api_url
    comfy_url = args.comfy_url
    comfy_workflow = (Path(args.comfy_workflow)
                      if args.comfy_workflow
                      else WORKER_DIR / "workflows" / "hunyuan3d_shape.api.json")
    if comfy_url and not comfy_workflow.exists():
        print(f"ERROR: Comfy workflow not found: {comfy_workflow}")
        sys.exit(1)

    api = StudioAPI(args.api_url)

    # ── Sanity check ────────────────────────────────────────────────────────
    print(f"Connecting to {args.api_url} ...")
    for attempt in range(10):
        if api.health():
            print("  API reachable ✓")
            break
        print(f"  Waiting for API... ({attempt+1}/10)")
        time.sleep(3)
    else:
        print("ERROR: Cannot reach API. Check --api-url and your network.")
        sys.exit(1)

    # ── Register ─────────────────────────────────────────────────────────────
    worker = api.register_worker(args.worker_name, args.gpu_model)
    worker_id = worker["id"]
    print(f"Registered as worker #{worker_id}: {args.worker_name}")

    # ── Heartbeat ────────────────────────────────────────────────────────────
    import threading
    stop_event = threading.Event()
    heartbeat_loop(api, worker_id, stop_event)

    # ── Poll loop ─────────────────────────────────────────────────────────────
    print(f"\nListening for jobs (polling every {args.poll_interval}s) ...\n")
    try:
        while True:
            job = api.get_next_job()
            if job:
                process_job(api, job, worker_id,
                            hunyuan_dir=hunyuan_dir, api_base=api_base,
                            blender_bin=blender_bin, ffmpeg_bin=ffmpeg_bin,
                            comfy_url=comfy_url, comfy_workflow=comfy_workflow)
            else:
                time.sleep(args.poll_interval)
    except KeyboardInterrupt:
        print("\nWorker stopped.")
        stop_event.set()


if __name__ == "__main__":
    main()
