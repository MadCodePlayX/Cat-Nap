"""
custom_rasterizer.py
====================
Drop-in implementation of the rasterize / interpolate interface expected by
hy3dgen/texgen/differentiable_renderer/mesh_render.py.

Uses nvdiffrast (NVIDIA, pip-installable) for CUDA-accelerated rasterisation
and pure PyTorch for barycentric UV interpolation.

Install:
    pip install nvdiffrast
"""
import torch

_glctx = None


def _ctx():
    global _glctx
    if _glctx is None:
        import nvdiffrast.torch as dr
        try:
            _glctx = dr.RasterizeCudaContext()
        except Exception:
            _glctx = dr.RasterizeGLContext()
    return _glctx


def rasterize(pos, tri, resolution):
    """
    CUDA rasterisation via nvdiffrast.

    Args:
        pos:        [B, N, 4]  clip-space positions (x, y, z, w)
        tri:        [M, 3]     triangle vertex indices
        resolution: int | [H, W]

    Returns:
        findices:   [B, H, W]     1-indexed face id per pixel  (0 = background)
        barycentric:[B, H, W, 2]  barycentric u, v  (third weight = 1-u-v)
    """
    import nvdiffrast.torch as dr

    if isinstance(resolution, (int, float)):
        resolution = [int(resolution), int(resolution)]

    pos = pos.float().contiguous()
    tri = tri.to(torch.int32).contiguous()

    rast_out, _ = dr.rasterize(_ctx(), pos, tri, resolution=resolution)
    # rast_out: [B, H, W, 4]  →  (bary_u, bary_v, z/w, tri_id_float)

    findices   = rast_out[..., 3].long()           # [B, H, W]
    barycentric = rast_out[..., :2].contiguous()   # [B, H, W, 2]
    return findices, barycentric


def interpolate(attr, findices, barycentric, attr_idx):
    """
    Barycentric interpolation of per-vertex attributes.

    Handles meshes with separate UV index buffers (seams) correctly by
    using attr_idx directly instead of the rasterisation face buffer.

    Args:
        attr:       [1, N, C]    per-vertex attributes  (UVs, normals, depth…)
        findices:   [B, H, W]    1-indexed face ids  (may arrive as float)
        barycentric:[B, H, W, 2] barycentric (u, v);  third = 1-u-v
        attr_idx:   [M, 3]       per-face vertex indices into attr

    Returns:
        out:        [B, H, W, C]  interpolated attributes
    """
    findices  = findices.long()
    visible   = findices > 0                        # [B, H, W]
    face_ids  = (findices - 1).clamp(min=0)         # 0-indexed

    attr_idx  = attr_idx.long()
    i0 = attr_idx[face_ids, 0]                      # [B, H, W]
    i1 = attr_idx[face_ids, 1]
    i2 = attr_idx[face_ids, 2]

    a  = attr.squeeze(0)                            # [N, C]
    a0 = a[i0]                                      # [B, H, W, C]
    a1 = a[i1]
    a2 = a[i2]

    w0 = barycentric[..., 0:1]                      # [B, H, W, 1]
    w1 = barycentric[..., 1:2]
    w2 = 1.0 - w0 - w1

    out = w0 * a0 + w1 * a1 + w2 * a2              # [B, H, W, C]
    out = out * visible.unsqueeze(-1).float()       # zero background

    return out                                       # [B, H, W, C]
