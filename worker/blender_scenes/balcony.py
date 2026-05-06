"""
Blender scene: Balcony
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
    bg.inputs["Color"].default_value = (0.55, 0.78, 1.0, 1.0)
    bg.inputs["Strength"].default_value = 2.5
    out = nt.nodes.new("ShaderNodeOutputWorld")
    nt.links.new(bg.outputs["Background"], out.inputs["Surface"])

    # Tiled floor
    bpy.ops.mesh.primitive_plane_add(size=6, location=(0, 0, 0))
    floor = bpy.context.active_object
    mat = bpy.data.materials.new("TileFloor")
    mat.use_nodes = True
    mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.82, 0.80, 0.76, 1.0)
    mat.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.4
    floor.data.materials.append(mat)

    # Railing (simple bars)
    for i in range(5):
        bpy.ops.mesh.primitive_cylinder_add(radius=0.02, depth=1.0,
                                             location=(-1.5 + i * 0.75, -2.5, 0.5))

    # Import product
    bpy.ops.import_scene.gltf(filepath=model_glb_path)
    for obj in bpy.context.selected_objects:
        obj.location = (0.2, -0.5, 0.0)

    # Sun
    bpy.ops.object.light_add(type="SUN", location=(4, 4, 8))
    sun = bpy.context.active_object
    sun.data.energy = 6.0
    sun.rotation_euler = (math.radians(35), 0, math.radians(45))

    # Camera
    bpy.ops.object.camera_add(location=(2.8, 2.5, 1.7))
    cam = bpy.context.active_object
    cam.rotation_euler = (math.radians(68), 0, math.radians(130))
    bpy.context.scene.camera = cam
    cam.data.lens = 28

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
    scene.render.resolution_x = 1920
    scene.render.resolution_y = 1080
    scene.render.fps = 24
    scene.frame_start = 1
    scene.frame_end = 72

    cam.keyframe_insert("location", frame=1)
    cam.location = (1.8, 3.0, 1.5)
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
