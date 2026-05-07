"""
Blender scene: Living Room
Run via: blender --background --python living_room.py -- <args>
"""
import bpy
import sys
import os
import math

def setup_scene(model_glb_path, animal_type, output_video_path, output_thumbnail_path):
    bpy.ops.wm.read_homefile(use_empty=True)

    # ── World / HDRI ──────────────────────────────────────────────────────────
    world = bpy.data.worlds.new("World")
    bpy.context.scene.world = world
    world.use_nodes = True
    nt = world.node_tree
    nt.nodes.clear()
    bg = nt.nodes.new("ShaderNodeBackground")
    bg.inputs["Color"].default_value = (0.8, 0.75, 0.65, 1.0)
    bg.inputs["Strength"].default_value = 2.0
    output = nt.nodes.new("ShaderNodeOutputWorld")
    nt.links.new(bg.outputs["Background"], output.inputs["Surface"])

    # ── Floor ─────────────────────────────────────────────────────────────────
    bpy.ops.mesh.primitive_plane_add(size=10, location=(0, 0, 0))
    floor = bpy.context.active_object
    floor.name = "Floor"
    mat = bpy.data.materials.new("FloorMat")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (0.72, 0.58, 0.42, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.8
    floor.data.materials.append(mat)

    # ── Back wall ─────────────────────────────────────────────────────────────
    bpy.ops.mesh.primitive_plane_add(size=10, location=(0, -5, 2.5))
    wall = bpy.context.active_object
    wall.name = "Wall"
    wall.rotation_euler = (math.radians(90), 0, 0)
    mat2 = bpy.data.materials.new("WallMat")
    mat2.use_nodes = True
    bsdf2 = mat2.node_tree.nodes["Principled BSDF"]
    bsdf2.inputs["Base Color"].default_value = (0.93, 0.90, 0.85, 1.0)
    wall.data.materials.append(mat2)

    # ── Sofa (simple box) ──────────────────────────────────────────────────────
    bpy.ops.mesh.primitive_cube_add(size=1, location=(-1.5, -2.5, 0.35))
    sofa = bpy.context.active_object
    sofa.name = "Sofa"
    sofa.scale = (1.4, 0.7, 0.35)
    mat3 = bpy.data.materials.new("SofaMat")
    mat3.use_nodes = True
    mat3.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.4, 0.3, 0.25, 1.0)
    sofa.data.materials.append(mat3)

    # ── Import product model ───────────────────────────────────────────────────
    bpy.ops.import_scene.gltf(filepath=model_glb_path)
    product_objs = [o for o in bpy.context.selected_objects]

    # Centre and scale product to ~0.5m tall
    for obj in product_objs:
        obj.location = (0.8, -1.0, 0.0)

    # ── Lighting ──────────────────────────────────────────────────────────────
    bpy.ops.object.light_add(type="AREA", location=(2, 1, 4))
    key = bpy.context.active_object
    key.data.energy = 600
    key.data.size = 2.0
    key.rotation_euler = (math.radians(-45), math.radians(20), 0)

    bpy.ops.object.light_add(type="AREA", location=(-2, -1, 3))
    fill = bpy.context.active_object
    fill.data.energy = 200
    fill.data.size = 3.0

    # ── Camera ────────────────────────────────────────────────────────────────
    bpy.ops.object.camera_add(location=(3.5, 2.5, 1.8))
    cam = bpy.context.active_object
    cam.name = "Camera"
    cam.rotation_euler = (math.radians(72), 0, math.radians(135))
    bpy.context.scene.camera = cam
    cam.data.lens = 35

    # ── Render settings ───────────────────────────────────────────────────────
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 128
    _cprefs = bpy.context.preferences.addons['cycles'].preferences
    for _dtype in ('OPTIX', 'CUDA'):
        try:
            _cprefs.compute_device_type = _dtype
            _cprefs.get_devices()
            for _dev in _cprefs.devices:
                _dev.use = True
            print(f"Cycles GPU backend: {_dtype} ✓")
            break
        except Exception:
            continue
    scene.cycles.device = 'GPU'
    # OptiX denoiser: 64 samples + denoising ≈ 512 samples without, far faster
    scene.cycles.use_denoising = True
    try:
        scene.cycles.denoiser = 'OPTIX'          # RTX GPU denoiser
    except Exception:
        scene.cycles.denoiser = 'OPENIMAGEDENOISE'  # CPU fallback
    scene.cycles.samples = 64
    scene.render.resolution_x = 1920
    scene.render.resolution_y = 1080
    scene.render.fps = 24
    scene.frame_start = 1
    scene.frame_end = 72  # 3 seconds

    # ── Camera dolly animation ─────────────────────────────────────────────────
    cam.location = (3.5, 2.5, 1.8)
    cam.keyframe_insert("location", frame=1)
    cam.location = (2.5, 3.5, 1.6)
    cam.keyframe_insert("location", frame=36)
    cam.location = (1.5, 2.8, 1.4)
    cam.keyframe_insert("location", frame=72)

    # ── Thumbnail (frame 1) ────────────────────────────────────────────────────
    scene.render.filepath = output_thumbnail_path
    scene.render.image_settings.file_format = "PNG"
    scene.frame_set(1)
    bpy.ops.render.render(write_still=True)

    # ── Video ─────────────────────────────────────────────────────────────────
    scene.render.filepath = output_video_path
    scene.render.image_settings.file_format = "FFMPEG"
    scene.render.ffmpeg.format = "MPEG4"
    scene.render.ffmpeg.codec = "H264"
    scene.render.ffmpeg.constant_rate_factor = "HIGH"
    bpy.ops.render.render(animation=True)


if __name__ == "__main__":
    argv = sys.argv
    argv = argv[argv.index("--") + 1:]
    setup_scene(argv[0], argv[1], argv[2], argv[3])
