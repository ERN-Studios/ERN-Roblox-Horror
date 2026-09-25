"""Render exact canonical hazmat mesh/UVs in a standing shop-card pose.

Run with Blender 5.2: blender --background --factory-startup --python render_catalogue.py
The source rig and maps remain untouched. Output is local art, not a Studio edit.
"""

from pathlib import Path

import bpy
from mathutils import Matrix, Vector


ROOT = Path(__file__).resolve().parents[1]
OUT = Path(__file__).resolve().parent
SKINS = (
    "baseline-yellow",
    "pool-service",
    "suburb-survey",
    "blacksite-director",
    "static-wraith",
    "false-sun",
)


def point_bone_toward(armature, joint_name, child_name, target):
    joint = armature.pose.bones[joint_name]
    child = armature.pose.bones[child_name]
    bpy.context.view_layer.update()
    direction = (child.head - joint.head).normalized()
    target = Vector(target).normalized()
    pivot = joint.head.copy()
    rotation = direction.rotation_difference(target).to_matrix().to_4x4()
    joint.matrix = (
        Matrix.Translation(pivot)
        @ rotation
        @ Matrix.Translation(-pivot)
        @ joint.matrix.copy()
    )
    bpy.context.view_layer.update()


def setup_rig():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(ROOT / "baseline-rigged.glb"))
    armature = bpy.data.objects["Armature"]
    mesh = bpy.data.objects["char1"]
    for obj in list(bpy.data.objects):
        if obj not in (armature, mesh):
            bpy.data.objects.remove(obj, do_unlink=True)
    armature.animation_data_clear()
    for pose_bone in armature.pose.bones:
        pose_bone.rotation_mode = "QUATERNION"
    for side, sign in (("Left", 1), ("Right", -1)):
        point_bone_toward(armature, side + "Arm", side + "ForeArm", (sign * 0.22, 0, -1))
        point_bone_toward(armature, side + "ForeArm", side + "Hand", (sign * 0.12, 0, -1))
    return mesh


def setup_material(mesh):
    material = bpy.data.materials.new("Canonical hazmat catalogue")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    nodes.clear()
    texture = nodes.new("ShaderNodeTexImage")
    texture.interpolation = "Linear"
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = 0.86
    bsdf.inputs["Metallic"].default_value = 0.04
    output = nodes.new("ShaderNodeOutputMaterial")
    links = material.node_tree.links
    links.new(texture.outputs["Color"], bsdf.inputs["Base Color"])
    links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
    mesh.data.materials.clear()
    mesh.data.materials.append(material)
    return texture


def setup_scene():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1024
    scene.render.resolution_y = 1024
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = True
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "Medium High Contrast"
    scene.view_settings.exposure = 0
    scene.view_settings.gamma = 1
    scene.world = bpy.data.worlds.new("Catalogue ambient")
    scene.world.color = (0.13, 0.13, 0.13)

    camera_data = bpy.data.cameras.new("Shop card orthographic camera")
    camera = bpy.data.objects.new("Shop card orthographic camera", camera_data)
    scene.collection.objects.link(camera)
    camera.location = (0, -4.2, 0.91)
    target = Vector((0, 0, 0.88))
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = 2.12
    scene.camera = camera

    def area_light(name, location, power, size):
        data = bpy.data.lights.new(name, "AREA")
        data.energy = power
        data.shape = "DISK"
        data.size = size
        obj = bpy.data.objects.new(name, data)
        scene.collection.objects.link(obj)
        obj.location = location
        obj.rotation_euler = (Vector((0, 0, 0.9)) - obj.location).to_track_quat("-Z", "Y").to_euler()

    area_light("Soft key", (-2.0, -2.7, 2.7), 175, 3.0)
    area_light("Soft fill", (2.3, -1.7, 1.8), 95, 3.5)
    area_light("Rim", (0.5, 2.0, 2.4), 150, 2.2)


def main():
    mesh = setup_rig()
    texture = setup_material(mesh)
    setup_scene()
    scene = bpy.context.scene
    camera = scene.camera
    for skin in SKINS:
        texture.image = bpy.data.images.load(str(ROOT / "textures" / (skin + ".png")), check_existing=True)
        scene.render.resolution_x = 1024
        scene.render.resolution_y = 1024
        camera.location = (0, -4.2, 0.91)
        camera.rotation_euler = (Vector((0, 0, 0.88)) - camera.location).to_track_quat("-Z", "Y").to_euler()
        camera.data.ortho_scale = 2.12
        scene.render.filepath = str(OUT / (skin + "-standing-v1.png"))
        bpy.ops.render.render(write_still=True)
        print("CATALOGUE_RENDER", skin, scene.render.filepath)
        scene.render.resolution_x = 512
        scene.render.resolution_y = 512
        camera.location = (0, -4.2, 1.21)
        camera.rotation_euler = (Vector((0, 0, 1.18)) - camera.location).to_track_quat("-Z", "Y").to_euler()
        camera.data.ortho_scale = 1.15
        scene.render.filepath = str(OUT / (skin + "-standing-card-v1.png"))
        bpy.ops.render.render(write_still=True)
        print("CATALOGUE_RENDER", skin, scene.render.filepath)


if __name__ == "__main__":
    main()
