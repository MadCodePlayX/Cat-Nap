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
    for obj in bpy.context.selected_objects:
        obj.location = (0.8, -0.5, 0.0)

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
    scene.cycles.device = "GPU"
    scene.cycles.samples = 128
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
