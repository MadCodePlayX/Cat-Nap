"""
Blender scene: Garden / Outdoor
"""
import bpy
import sys
import math


def setup_scene(model_glb_path, animal_type, output_video_path, output_thumbnail_path):
    bpy.ops.wm.read_homefile(use_empty=True)

    world = bpy.data.worlds.new("World")
    bpy.context.scene.world = world
    world.use_nodes = True
    nt = world.node_tree
    nt.nodes.clear()
    bg = nt.nodes.new("ShaderNodeBackground")
    bg.inputs["Color"].default_value = (0.5, 0.75, 1.0, 1.0)
    bg.inputs["Strength"].default_value = 3.0
    output = nt.nodes.new("ShaderNodeOutputWorld")
    nt.links.new(bg.outputs["Background"], output.inputs["Surface"])

    # Grass ground
    bpy.ops.mesh.primitive_plane_add(size=12, location=(0, 0, 0))
    ground = bpy.context.active_object
    mat = bpy.data.materials.new("GrassMat")
    mat.use_nodes = True
    mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.15, 0.45, 0.1, 1.0)
    mat.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.95
    ground.data.materials.append(mat)

    # Import product
    bpy.ops.import_scene.gltf(filepath=model_glb_path)
    _imported = list(bpy.context.selected_objects)
    if not _imported:
        print(f"[ERROR] GLB import returned 0 objects — bad path or corrupt file: {model_glb_path}")
        sys.exit(1)
    for obj in _imported:
        obj.location = (0.0, 0.0, 0.0)

    # Sun light
    bpy.ops.object.light_add(type="SUN", location=(5, 3, 8))
    sun = bpy.context.active_object
    sun.data.energy = 5.0
    sun.rotation_euler = (math.radians(40), math.radians(10), math.radians(45))

    bpy.ops.object.light_add(type="AREA", location=(-3, -2, 4))
    fill = bpy.context.active_object
    fill.data.energy = 300
    fill.data.size = 4.0

    # Camera
    bpy.ops.object.camera_add(location=(3.0, 3.0, 2.0))
    cam = bpy.context.active_object
    cam.rotation_euler = (math.radians(65), 0, math.radians(135))
    bpy.context.scene.camera = cam
    cam.data.lens = 28

    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    _cprefs = bpy.context.preferences.addons['cycles'].preferences
    _chosen_backend = None
    for _dtype in ('OPTIX', 'CUDA', 'HIP', 'METAL', 'ONEAPI'):
        try:
            _cprefs.compute_device_type = _dtype
        except TypeError:
            print(f"  [GPU] backend {_dtype} not compiled into this Blender build")
            continue
        _refresh = getattr(_cprefs, 'refresh_devices', None) or getattr(_cprefs, 'get_devices', None)
        if _refresh is not None:
            try:
                _refresh()
            except Exception as _e:
                print(f"  [GPU] {_dtype}: refresh_devices() failed: {_e}")
                continue
        _gpu_devs = [d for d in _cprefs.devices if d.type != 'CPU']
        if not _gpu_devs:
            print(f"  [GPU] {_dtype}: no non-CPU devices found")
            continue
        for _dev in _cprefs.devices:
            _dev.use = (_dev.type != 'CPU')
        _chosen_backend = _dtype
        print(f"  [GPU] Cycles backend: {_dtype} ✓ ({len(_gpu_devs)} device(s))")
        for _dev in _gpu_devs:
            print(f"        • {_dev.name}")
        break
    if _chosen_backend is None:
        print("  [GPU] ⚠ No Cycles GPU backend available — falling back to CPU")
        print(f"        Available devices: {[(d.name, d.type) for d in _cprefs.devices]}")
        scene.cycles.device = 'CPU'
    else:
        scene.cycles.device = 'GPU'
    scene.cycles.use_denoising = True
    try:
        scene.cycles.denoiser = 'OPTIX'
    except Exception:
        scene.cycles.denoiser = 'OPENIMAGEDENOISE'
    scene.cycles.samples = 64
    scene.render.resolution_x = 1920
    scene.render.resolution_y = 1080
    scene.render.fps = 24
    scene.frame_start = 1
    scene.frame_end = 72

    cam.keyframe_insert("location", frame=1)
    cam.location = (2.0, 3.5, 1.8)
    cam.keyframe_insert("location", frame=72)

    scene.render.filepath = output_thumbnail_path
    scene.render.image_settings.file_format = "PNG"
    scene.frame_set(1)
    bpy.ops.render.render(write_still=True)

    # FFMPEG output removed in Blender 5.x — render PNG frame sequence instead.
    # worker.py encodes the frames to MP4 using system ffmpeg.
    import os as _os
    _os.makedirs(output_video_path, exist_ok=True)
    scene.render.filepath = output_video_path + "/frame_####"
    scene.render.image_settings.file_format = "PNG"
    bpy.ops.render.render(animation=True)


if __name__ == "__main__":
    argv = sys.argv
    argv = argv[argv.index("--") + 1:]
    setup_scene(argv[0], argv[1], argv[2], argv[3])
