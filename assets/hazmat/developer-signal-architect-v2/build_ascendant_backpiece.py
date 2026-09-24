"""Build one mobile-sized Signal Architect halo backpiece and accurate shop renders.

Run with Blender 5.2: blender --background --factory-startup --python build_ascendant_backpiece.py
The canonical rig is imported only for rendering; the exported prop is a single mesh.
"""

from math import pi
from pathlib import Path

import bpy
from mathutils import Matrix, Vector


HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
BACKPIECE = HERE / "ascendant-halo-backpiece.glb"
ATLAS = HERE / "ascendant-halo-atlas.png"
COLOR_MAP = HERE / "ascendant-color-map.png"

COLORS = {
    "obsidian": (0.018, 0.032, 0.061, 1),
    "slate": (0.095, 0.135, 0.195, 1),
    "cyan": (0.005, 0.76, 0.91, 1),
    "gold": (0.83, 0.51, 0.18, 1),
}
UV_CENTERS = {
    "obsidian": (0.25, 0.25),
    "slate": (0.75, 0.25),
    "cyan": (0.25, 0.75),
    "gold": (0.75, 0.75),
}


def make_atlas():
    image = bpy.data.images.new("Ascendant four-colour atlas", width=256, height=256)
    pixels = [0.0] * (256 * 256 * 4)
    for y in range(256):
        for x in range(256):
            slot = ("cyan" if x < 128 else "gold") if y >= 128 else (
                "obsidian" if x < 128 else "slate"
            )
            i = (y * 256 + x) * 4
            pixels[i:i + 4] = COLORS[slot]
    image.pixels[:] = pixels
    image.filepath_raw = str(ATLAS)
    image.file_format = "PNG"
    image.save()
    return image


def make_material(image):
    material = bpy.data.materials.new("Ascendant unified atlas")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    nodes.clear()
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = image
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Metallic"].default_value = 0.38
    bsdf.inputs["Roughness"].default_value = 0.34
    output = nodes.new("ShaderNodeOutputMaterial")
    material.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    material.node_tree.links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
    return material


def paint_object(obj, color, material):
    uv = obj.data.uv_layers.active or obj.data.uv_layers.new(name="AtlasUV")
    center = UV_CENTERS[color]
    for loop in uv.data:
        loop.uv = center
    obj.data.materials.clear()
    obj.data.materials.append(material)
    return obj


def cube(name, location, dimensions, color, material, bevel=0.018):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        modifier = obj.modifiers.new("Soft machined edge", "BEVEL")
        modifier.width = bevel
        modifier.segments = 1
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        weighted = obj.modifiers.new("Weighted normals", "WEIGHTED_NORMAL")
        bpy.ops.object.modifier_apply(modifier=weighted.name)
    return paint_object(obj, color, material)


def ring(name, center, major, minor, color, material):
    bpy.ops.mesh.primitive_torus_add(
        major_segments=48, minor_segments=8,
        location=center, rotation=(pi / 2, 0, 0),
        major_radius=major, minor_radius=minor,
    )
    obj = bpy.context.object
    obj.name = name
    return paint_object(obj, color, material)


def fin(name, x, height, material):
    # A dark thick fin with a readable cyan blade and gold cap, all physically
    # connected to the ring/backpack after the final mesh join.
    y = 0.19
    z = 0.51 + height / 2
    pieces = [
        cube(name + " body", (x, y, z), (0.12, 0.10, height),
             "obsidian", material, 0.015),
        cube(name + " signal", (x, y - 0.056, z + 0.025),
             (0.048, 0.008, max(0.10, height - 0.10)), "cyan", material, 0.004),
        cube(name + " crown", (x, y, z + height / 2 - 0.026),
             (0.132, 0.112, 0.05), "gold", material, 0.008),
    ]
    return pieces


def make_backpiece(material):
    pieces = [
        cube("Backpack core", (0, 0.18, 0.04), (0.49, 0.23, 0.55),
             "obsidian", material, 0.045),
        cube("Backpack panel", (0, 0.306, 0.03), (0.32, 0.018, 0.38),
             "slate", material, 0.028),
        cube("Backpack glyph", (0, 0.32, 0.04), (0.15, 0.014, 0.21),
             "cyan", material, 0.018),
        cube("Backpack lower badge", (0, 0.326, -0.13), (0.25, 0.012, 0.035),
             "gold", material, 0.007),
        ring("Obsidian antenna halo", (0, 0.185, 0.50), 0.45, 0.047,
             "obsidian", material),
        ring("Cyan antenna channel", (0, 0.135, 0.50), 0.388, 0.021,
             "cyan", material),
        ring("Gold outer rim", (0, 0.225, 0.50), 0.455, 0.010,
             "gold", material),
    ]
    for side in (-1, 1):
        pieces.extend(fin("Side antenna " + str(side), side * 0.38, 0.32, material))
        pieces.append(cube("Shoulder rail " + str(side),
                           (side * 0.25, 0.18, 0.17), (0.28, 0.11, 0.07),
                           "gold", material, 0.012))
    pieces.extend(fin("Center antenna", 0, 0.45, material))
    bpy.ops.object.select_all(action="DESELECT")
    for obj in pieces:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = pieces[0]
    bpy.ops.object.join()
    result = bpy.context.object
    result.name = "SignalArchitectAscendantBackpiece"
    bpy.context.scene.cursor.location = (0, 0, 0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return result


def export_single_mesh(backpiece):
    bpy.ops.object.select_all(action="DESELECT")
    backpiece.select_set(True)
    bpy.context.view_layer.objects.active = backpiece
    bpy.ops.export_scene.gltf(
        filepath=str(BACKPIECE), export_format="GLB",
        use_selection=True, export_apply=True,
    )
    print("ASCENDANT_BACKPIECE", BACKPIECE, len(backpiece.data.polygons))


def pose_arm(armature, joint_name, child_name, target):
    joint = armature.pose.bones[joint_name]
    child = armature.pose.bones[child_name]
    bpy.context.view_layer.update()
    direction = (child.head - joint.head).normalized()
    pivot = joint.head.copy()
    rotation = direction.rotation_difference(Vector(target).normalized()).to_matrix().to_4x4()
    joint.matrix = Matrix.Translation(pivot) @ rotation @ Matrix.Translation(-pivot) @ joint.matrix.copy()
    bpy.context.view_layer.update()


def add_suit():
    bpy.ops.import_scene.gltf(filepath=str(ROOT / "baseline-rigged.glb"))
    armature = bpy.data.objects["Armature"]
    suit = bpy.data.objects["char1"]
    armature.animation_data_clear()
    for bone in armature.pose.bones:
        bone.rotation_mode = "QUATERNION"
    for side, sign in (("Left", 1), ("Right", -1)):
        pose_arm(armature, side + "Arm", side + "ForeArm", (sign * 0.22, 0, -1))
        pose_arm(armature, side + "ForeArm", side + "Hand", (sign * 0.12, 0, -1))
    image = bpy.data.images.load(str(COLOR_MAP), check_existing=True)
    material = bpy.data.materials.new("Ascendant suit ColorMap")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    nodes.clear()
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = image
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = 0.78
    output = nodes.new("ShaderNodeOutputMaterial")
    material.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    material.node_tree.links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
    suit.data.materials.clear()
    suit.data.materials.append(material)


def setup_render():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = True
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "Medium High Contrast"
    camera_data = bpy.data.cameras.new("Ascendant portrait camera")
    camera = bpy.data.objects.new("Ascendant portrait camera", camera_data)
    scene.collection.objects.link(camera)
    camera_data.type = "ORTHO"
    scene.camera = camera
    for name, location, power, size in (
        ("Soft key", (-2.0, -2.7, 2.8), 210, 3.0),
        ("Soft fill", (2.2, -1.8, 1.7), 100, 3.5),
        ("Cyan rim", (0.0, 2.0, 2.5), 195, 2.4),
    ):
        light_data = bpy.data.lights.new(name, "AREA")
        light_data.energy = power
        light_data.shape = "DISK"
        light_data.size = size
        light = bpy.data.objects.new(name, light_data)
        scene.collection.objects.link(light)
        light.location = location
        light.rotation_euler = (Vector((0, 0, 1.0)) - light.location).to_track_quat("-Z", "Y").to_euler()
    return camera


def render(camera, backpiece):
    # The suit is 1.7 m tall. The prop is placed behind its UpperTorso only
    # for art renders; Studio's actual weld and scale must be checked separately.
    backpiece.location = (0, 0.27, 1.13)
    backpiece.scale = (0.72, 0.72, 0.72)
    scene = bpy.context.scene
    for label, camera_y in (("front", -4.2), ("back", 4.2)):
        scene.render.resolution_x = 1024
        scene.render.resolution_y = 1024
        camera.location = (0, camera_y, 1.0)
        target = Vector((0, 0, 0.96))
        camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
        camera.data.ortho_scale = 2.30
        scene.render.filepath = str(HERE / ("ascendant-" + label + "-preview.png"))
        bpy.ops.render.render(write_still=True)
    scene.render.resolution_x = 512
    scene.render.resolution_y = 512
    camera.location = (0, -4.2, 1.31)
    target = Vector((0, 0, 1.24))
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.ortho_scale = 1.65
    scene.render.filepath = str(HERE / "ascendant-standing-card.png")
    bpy.ops.render.render(write_still=True)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    image = make_atlas()
    material = make_material(image)
    backpiece = make_backpiece(material)
    export_single_mesh(backpiece)
    add_suit()
    camera = setup_render()
    render(camera, backpiece)


if __name__ == "__main__":
    main()
