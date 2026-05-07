"""
Blender scene: Bedroom
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
    bg.inputs["Color"].default_value = (0.6, 0.55, 0.5, 1.0)
    bg.inputs["Strength"].default_value = 1.2
    output = nt.nodes.new("ShaderNodeOutputWorld")
    nt.links.new(bg.outputs["Background"], output.inputs["Surface"])

    # Floor
    bpy.ops.mesh.primitive_plane_add(size=8, location=(0, 0, 0))
    floor = bpy.context.active_object
    mat = bpy.data.materials.new("FloorMat")
    mat.use_nodes = True
    mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.6, 0.5, 0.38, 1.0)
    mat.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.7
    floor.data.materials.append(mat)

    # Wall
    bpy.ops.mesh.primitive_plane_add(size=8, location=(0, -4, 2))
    wall = bpy.context.active_object
    wall.rotation_euler = (math.radians(90), 0, 0)
    mat2 = bpy.data.materials.new("WallMat")
    mat2.use_nodes = True
    mat2.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.88, 0.85, 0.80, 1.0)
    wall.data.materials.append(mat2)

    # Bed (simplified)
    bpy.ops.mesh.primitive_cube_add(size=1, location=(-1.0, -2.5, 0.25))
    bed = bpy.context.active_object
    bed.scale = (1.0, 1.2, 0.25)
    mat3 = bpy.data.materials.new("BedMat")
    mat3.use_nodes = True
    mat3.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.9, 0.88, 0.85, 1.0)
    bed.data.materials.append(mat3)

    # Import product
    bpy.ops.import_scene.gltf(filepath=model_glb_path)
    for obj in bpy.context.selected_objects:
        obj.location = (1.2, -0.5, 0.0)

    # Lights
    bpy.ops.object.light_add(type="AREA", location=(0, 2, 3.5))
    key = bpy.context.active_object
    key.data.energy = 400
    key.data.size = 2.0
    key.rotation_euler = (math.radians(-50), 0, 0)

    bpy.ops.object.light_add(type="POINT", location=(-1, -1, 2.8))
    lamp = bpy.context.active_object
    lamp.data.energy = 200
    lamp.data.color = (1.0, 0.9, 0.7)

    # Camera
    bpy.ops.object.camera_add(location=(3.2, 2.8, 1.6))
    cam = bpy.context.active_object
    cam.rotation_euler = (math.radians(70), 0, math.radians(135))
    bpy.context.scene.camera = cam
    cam.data.lens = 35

    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 128
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
        _gpu_devs = [d for d in _cprefs.devices if d.type == _dtype]
        if not _gpu_devs:
            print(f"  [GPU] {_dtype}: no devices found")
            continue
        for _dev in _cprefs.devices:
            _dev.use = (_dev.type == _dtype)
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
    cam.location = (2.2, 3.2, 1.4)
    cam.keyframe_insert("location", frame=72)

    scene.render.filepath = output_thumbnail_path
    scene.render.image_settings.file_format = "PNG"
    scene.frame_set(1)
    bpy.ops.render.render(write_still=True)

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
