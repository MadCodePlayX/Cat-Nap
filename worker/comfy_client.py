"""
Minimal ComfyUI client.

Talks to a running ComfyUI server (default http://127.0.0.1:8188) over its
documented HTTP + WebSocket API:

  POST /upload/image         — upload an input image into ComfyUI's input dir
  POST /prompt               — queue a workflow (in API JSON format)
  WS   /ws?clientId=...      — stream progress / execution events
  GET  /history/{prompt_id}  — final node outputs (filenames, etc)
  GET  /view?filename=...    — download an output file

Why a thin client and not comfy_api_simplified / litegraph etc.? Two reasons:
  1. Zero new deps beyond `requests` + `websocket-client` (already on disk).
  2. Easier to forward ComfyUI's per-node progress to your existing
     on_progress(pct, stage) callback in worker.py.

Usage:

    client = ComfyClient("http://127.0.0.1:8188")
    workflow = json.loads(Path("workflows/hunyuan3d_shape.api.json").read_text())
    # Patch: tell the LoadImage node which file to use
    workflow["LOAD_IMAGE_NODE_ID"]["inputs"]["image"] = "input.png"
    client.upload_image(Path("input.png"))
    glb_bytes = client.run_workflow(
        workflow,
        output_node_id="SAVE_3D_NODE_ID",
        on_progress=lambda pct, stage: print(pct, stage),
    )
    Path("model.glb").write_bytes(glb_bytes)
"""
from __future__ import annotations

import json
import time
import uuid
from pathlib import Path
from typing import Callable, Optional

import requests


class ComfyClient:
    def __init__(self, base_url: str = "http://127.0.0.1:8188", timeout: float = 30.0):
        self.base = base_url.rstrip("/")
        self.timeout = timeout
        self.client_id = uuid.uuid4().hex
        self.session = requests.Session()

    def health(self) -> bool:
        try:
            r = self.session.get(f"{self.base}/system_stats", timeout=5)
            return r.status_code == 200
        except Exception:
            return False

    def upload_image(self, path: Path, overwrite: bool = True) -> str:
        """POST /upload/image. Returns the filename ComfyUI assigned (often
        unchanged from path.name). Use this name in LoadImage.inputs.image."""
        with open(path, "rb") as f:
            r = self.session.post(
                f"{self.base}/upload/image",
                files={"image": (path.name, f, "image/png")},
                data={"overwrite": "true" if overwrite else "false"},
                timeout=60,
            )
        r.raise_for_status()
        return r.json().get("name", path.name)

    def queue_prompt(self, workflow: dict) -> str:
        """POST /prompt. Returns prompt_id."""
        r = self.session.post(
            f"{self.base}/prompt",
            json={"prompt": workflow, "client_id": self.client_id},
            timeout=self.timeout,
        )
        r.raise_for_status()
        body = r.json()
        if "prompt_id" not in body:
            raise RuntimeError(f"ComfyUI rejected workflow: {body}")
        return body["prompt_id"]

    def get_history(self, prompt_id: str) -> Optional[dict]:
        r = self.session.get(f"{self.base}/history/{prompt_id}", timeout=self.timeout)
        r.raise_for_status()
        return r.json().get(prompt_id)

    def fetch_output(self, filename: str, subfolder: str = "", folder_type: str = "output") -> bytes:
        r = self.session.get(
            f"{self.base}/view",
            params={"filename": filename, "subfolder": subfolder, "type": folder_type},
            timeout=120,
        )
        r.raise_for_status()
        return r.content

    def run_workflow(
        self,
        workflow: dict,
        output_node_id: str,
        on_progress: Optional[Callable[[int, str], None]] = None,
        pct_start: int = 15,
        pct_end: int = 55,
        label: str = "ComfyUI 3D",
        poll_interval: float = 1.0,
        timeout_s: float = 1800.0,
    ) -> bytes:
        """Queue + wait + return the bytes of the first file produced by
        the node with id `output_node_id`. Streams progress via WebSocket
        if `websocket-client` is installed, otherwise falls back to polling
        /history every poll_interval seconds.
        """
        prompt_id = self.queue_prompt(workflow)

        try:
            self._wait_via_ws(prompt_id, on_progress, pct_start, pct_end, label, timeout_s)
        except Exception as ws_err:
            if on_progress:
                on_progress(pct_start, f"{label} (polling: {ws_err})")
            self._wait_via_polling(prompt_id, on_progress, pct_start, pct_end, label,
                                   poll_interval, timeout_s)

        history = self.get_history(prompt_id)
        if not history:
            raise RuntimeError(f"No history for prompt {prompt_id}")

        outputs = history.get("outputs", {}).get(output_node_id)
        if not outputs:
            raise RuntimeError(
                f"Node {output_node_id} produced no outputs. "
                f"Available nodes: {list(history.get('outputs', {}).keys())}"
            )

        # Hunyuan3D / SaveGLB nodes report under "result", "mesh", or "3d"
        candidates = (
            outputs.get("result")
            or outputs.get("mesh")
            or outputs.get("3d")
            or outputs.get("gltf")
            or outputs.get("models")
        )
        if not candidates:
            raise RuntimeError(
                f"Node {output_node_id} outputs missing file ref. Got keys: {list(outputs.keys())}"
            )

        first = candidates[0]
        if isinstance(first, str):
            return self.fetch_output(first)
        return self.fetch_output(
            first["filename"],
            first.get("subfolder", ""),
            first.get("type", "output"),
        )

    def _wait_via_ws(self, prompt_id, on_progress, p0, p1, label, timeout_s):
        try:
            from websocket import create_connection
        except ImportError as e:
            raise RuntimeError("websocket-client not installed") from e

        ws_url = self.base.replace("http", "ws", 1) + f"/ws?clientId={self.client_id}"
        ws = create_connection(ws_url, timeout=10)
        ws.settimeout(60)
        deadline = time.time() + timeout_s
        last_fire = 0.0
        try:
            while time.time() < deadline:
                msg = ws.recv()
                if isinstance(msg, bytes):
                    continue
                evt = json.loads(msg)
                etype = evt.get("type")
                data = evt.get("data", {})
                if data.get("prompt_id") and data["prompt_id"] != prompt_id:
                    continue

                if etype == "executing" and data.get("node") is None:
                    return
                if etype == "execution_error":
                    raise RuntimeError(f"ComfyUI execution error: {data}")
                if etype == "progress" and on_progress:
                    now = time.time()
                    if now - last_fire < 2.0:
                        continue
                    last_fire = now
                    val = data.get("value", 0)
                    mx = max(data.get("max", 1), 1)
                    pct = int(p0 + (val / mx) * (p1 - p0))
                    on_progress(pct, f"{label} — {val}/{mx}")
            raise TimeoutError("ComfyUI workflow timed out")
        finally:
            ws.close()

    def _wait_via_polling(self, prompt_id, on_progress, p0, p1, label,
                          interval, timeout_s):
        deadline = time.time() + timeout_s
        while time.time() < deadline:
            h = self.get_history(prompt_id)
            if h:
                status = h.get("status", {})
                if status.get("completed") or h.get("outputs"):
                    return
                if status.get("status_str") == "error":
                    raise RuntimeError(f"ComfyUI errored: {status}")
            if on_progress:
                on_progress(p0, f"{label} (waiting…)")
            time.sleep(interval)
        raise TimeoutError("ComfyUI workflow timed out")
