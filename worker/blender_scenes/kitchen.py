"""
Blender scene: Kitchen
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
    bg.inputs["Color"].default_value = (0.85, 0.87, 0.9, 1.0)
    bg.inputs["Strength"].default_value = 2.0
    out = nt.nodes.new("ShaderNodeOutputWorld")
    nt.links.new(bg.outputs["Background"], out.inputs["Surface"])

    # Floor (tiles)
    bpy.ops.mesh.primitive_plane_add(size=8, location=(0, 0, 0))
    floor = bpy.context.active_object
    mat = bpy.data.materials.new("KitchenFloor")
    mat.use_nodes = True
    mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.9, 0.88, 0.84, 1.0)
    mat.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.3
    floor.data.materials.append(mat)

    # Back wall
    bpy.ops.mesh.primitive_plane_add(size=8, location=(0, -4, 2))
    wall = bpy.context.active_object
    wall.rotation_euler = (math.radians(90), 0, 0)
    mat2 = bpy.data.materials.new("KitchenWall")
    mat2.use_nodes = True
    mat2.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.95, 0.94, 0.92, 1.0)
    wall.data.materials.append(mat2)

    # Counter top
    bpy.ops.mesh.primitive_cube_add(size=1, location=(-1.5, -3.2, 0.45))
    counter = bpy.context.active_object
    counter.scale = (2.0, 0.5, 0.45)
    mat3 = bpy.data.materials.new("CounterMat")
    mat3.use_nodes = True
    mat3.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.8, 0.78, 0.75, 1.0)
    mat3.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.2
    counter.data.materials.append(mat3)

    # Import product
    bpy.ops.import_scene.gltf(filepath=model_glb_path)
    _imported = list(bpy.context.selected_objects)
    if not _imported:
        print(f"[ERROR] GLB import returned 0 objects — bad path or corrupt file: {model_glb_path}")
        sys.exit(1)
    # Centre and scale product to 0.5 m tall, placed on floor at target XY
    import mathutils as _mu
    _min_b = _mu.Vector((1e9, 1e9, 1e9))
    _max_b = _mu.Vector((-1e9, -1e9, -1e9))
    for _obj in _imported:
        for _c in _obj.bound_box:
            _wc = _obj.matrix_world @ _mu.Vector(_c)
            for _i in range(3):
                _min_b[_i] = min(_min_b[_i], _wc[_i])
                _max_b[_i] = max(_max_b[_i], _wc[_i])
    _height = max(_max_b.z - _min_b.z, 0.01)
    _scale = 1.2 / _height
    _cx = (_min_b.x + _max_b.x) / 2
    _cy = (_min_b.y + _max_b.y) / 2
    for _obj in _imported:
        _obj.scale = (_scale, _scale, _scale)
        _obj.location = (0.8 - _cx * _scale, -0.5 - _cy * _scale, -_min_b.z * _scale)
    print(f"  [scene] Product: {len(_imported)} obj, h={_height:.3f}m -> {_height*_scale:.2f}m after scale")

    # Lights
    bpy.ops.object.light_add(type="AREA", location=(0, 0, 3.5))
    key = bpy.context.active_object
    key.data.energy = 500
    key.data.size = 3.0

    bpy.ops.object.light_add(type="AREA", location=(2, -2, 2.5))
    fill = bpy.context.active_object
    fill.data.energy = 200
    fill.data.size = 2.0
    fill.data.color = (1.0, 0.97, 0.88)

    # Camera
    bpy.ops.object.camera_add(location=(3.0, 2.5, 1.8))
    cam = bpy.context.active_object
    cam.rotation_euler = (math.radians(70), 0, math.radians(135))
    bpy.context.scene.camera = cam
    cam.data.lens = 35

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
        # Blender 5.x can expose both APIs; run both to reliably populate
        # _cprefs.devices across Linux/WSL builds.
        _refresh = getattr(_cprefs, 'refresh_devices', None)
        _get = getattr(_cprefs, 'get_devices', None)
        try:
            if callable(_refresh):
                _refresh()
            if callable(_get):
                _get()
        except Exception as _e:
            print(f"  [GPU] {_dtype}: device refresh failed: {_e}", flush=True)
            continue
        _gpu_devs = [d for d in _cprefs.devices if d.type != 'CPU']
        if not _gpu_devs:
            print(f"  [GPU] {_dtype}: no non-CPU devices found", flush=True)
            continue
        for _dev in _cprefs.devices:
            _dev.use = (_dev.type != 'CPU')
        _chosen_backend = _dtype
        print(f"  [GPU] Cycles backend: {_dtype} ✓ ({len(_gpu_devs)} device(s))", flush=True)
        for _dev in _gpu_devs:
            print(f"        • {_dev.name}", flush=True)
        break
    if _chosen_backend is None:
        print("  [GPU] ⚠ No Cycles GPU backend available — falling back to CPU", flush=True)
        print(f"        Available devices: {[(d.name, d.type) for d in _cprefs.devices]}", flush=True)
        scene.cycles.device = 'CPU'
    else:
        scene.cycles.device = 'GPU'
    print(f"  [GPU] Final cycles device: {scene.cycles.device}", flush=True)
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
    cam.location = (2.0, 3.0, 1.6)
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
