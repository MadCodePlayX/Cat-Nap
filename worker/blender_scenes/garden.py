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
    for obj in bpy.context.selected_objects:
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
    scene.cycles.device = "GPU"
    scene.cycles.samples = 128
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
