"""A look at the Level 6 PBR sets as materials, before anything is uploaded.

    /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/level6_playground/pbr/preview_pbr.py

A corner of the arena in Blender (one unit = one stud) wearing the maps from assets/level6-pbr-20261006 with the
repeat sizes of make_pbr.SETS: a foam floor, a padded wall in the frame's four colours, padded posts, a filthy
corner, a block wall, a ribbed roof and a length of slide, under a few lamps so the sheen and the relief show.
Writes artifacts/level6-pbr-20261006/preview/*.png and blend/Level6_PBR_Preview.blend.
"""
import json
import math
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[3]
MAPS = ROOT / 'assets' / 'level6-pbr-20261006'
OUT = ROOT / 'artifacts' / 'level6-pbr-20261006'
SETS = json.loads((MAPS / 'sets.json').read_text())

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
cache = {}


def material(name, tint=(1, 1, 1)):
    key = (name, tint)
    if key in cache:
        return cache[key]
    mat = bpy.data.materials.new(f'{name} {tint}')
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = next(n for n in nodes if n.type == 'BSDF_PRINCIPLED')

    def image(kind, colour):
        node = nodes.new('ShaderNodeTexImage')
        node.image = bpy.data.images.load(str(MAPS / f'{name}_{kind}.png'), check_existing=True)
        if not colour:
            node.image.colorspace_settings.name = 'Non-Color'
        return node
    colour, normal, rough = image('color', True), image('normal', False), image('roughness', False)
    mul = nodes.new('ShaderNodeMix')
    mul.data_type, mul.blend_type = 'RGBA', 'MULTIPLY'
    mul.inputs[0].default_value = 1.0
    links.new(colour.outputs['Color'], mul.inputs[6])
    mul.inputs[7].default_value = (*tint, 1)
    links.new(mul.outputs[2], bsdf.inputs['Base Color'])
    bump = nodes.new('ShaderNodeNormalMap')
    links.new(normal.outputs['Color'], bump.inputs['Color'])
    links.new(bump.outputs['Normal'], bsdf.inputs['Normal'])
    links.new(rough.outputs['Color'], bsdf.inputs['Roughness'])
    cache[key] = mat
    return mat


def quad(name, origin, across, up, set_name, tint=(1, 1, 1)):
    """A rectangle from `origin` along `across` and `up`, mapped at the set's own repeat."""
    o, a, u = Vector(origin), Vector(across), Vector(up)
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([o, o + a, o + a + u, o + u], [], [(0, 1, 2, 3)])
    studs = SETS[set_name]['studs']
    layer = mesh.uv_layers.new()
    for i, uv in enumerate(((0, 0), (a.length / studs, 0), (a.length / studs, u.length / studs), (0, u.length / studs))):
        layer.data[i].uv = uv
    mesh.materials.append(material(set_name, tint))
    obj = bpy.data.objects.new(name, mesh)
    scene.collection.objects.link(obj)
    return obj


def tube(name, at, radius, length, set_name, tint, axis='Z'):
    bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=radius, depth=length, location=at)
    obj = bpy.context.object
    obj.name = name
    if axis == 'X':
        obj.rotation_euler = (0, math.radians(90), 0)
    studs = SETS[set_name]['studs']
    for loop in obj.data.uv_layers.active.data:                    # the wrap: once round is the circumference in studs
        loop.uv = (loop.uv[0] * 2 * (2 * math.pi * radius) / studs, loop.uv[1] * 2 * length / studs)
    obj.data.materials.append(material(set_name, tint))
    for poly in obj.data.polygons:
        poly.use_smooth = True
    return obj


RED, YELLOW, BLUE, GREEN, NAVY = (0.67, 0.153, 0.13), (0.83, 0.65, 0.1), (0.13, 0.22, 0.58), (0.17, 0.49, 0.22), (0.086, 0.114, 0.3)
quad('Floor', (-28, -10, 0), (56, 0, 0), (0, 42, 0), 'foam_floor')
for i, tint in enumerate((RED, YELLOW, BLUE, GREEN, YELLOW, NAVY, RED, BLUE)):          # the padded back wall
    for j in range(2):
        t = tint if j == 0 else (NAVY, GREEN, YELLOW, RED, BLUE, YELLOW, GREEN, NAVY)[i]
        quad(f'Pad{i}_{j}', (-28 + 7 * i, 32, 7 * j), (7, 0, 0), (0, 0, 7), 'vinyl_quilt', t)
quad('Blocks', (-28, -10, 0), (0, 42, 0), (0, 0, 14), 'block_wall', (0.68, 0.675, 0.64))
for j in range(2):                                                                        # the filthy corner
    for i in range(6):
        quad(f'Filth{i}_{j}', (28, 32 - 7 * (i + 1), 7 * j), (0, 7, 0), (0, 0, 7), 'vinyl_filthy', (YELLOW, NAVY)[(i + j) % 2])
quad('Roof', (-28, -10, 14), (56, 0, 0), (0, 42, 0), 'roof_deck', (0.44, 0.44, 0.44))
for x, tint in ((-14, YELLOW), (0, RED), (14, YELLOW)):
    tube(f'Post{x}', (x, 18, 7), 0.7, 14, 'vinyl_plain', tint)
tube('Slide', (6, 9, 1.7), 1.7, 16, 'slide_plastic', (0.82, 0.36, 0.08), 'X')

world = bpy.data.worlds.new('Hall')
world.use_nodes = True
next(n for n in world.node_tree.nodes if n.type == 'BACKGROUND').inputs['Color'].default_value = (0.004, 0.004, 0.005, 1)
scene.world = world
for name, at, power, colour, size in (('Tube1', (-8, 14, 12.5), 2600, (1.0, 0.93, 0.8), 1.2), ('Tube2', (12, 24, 12.5), 2200, (1.0, 0.93, 0.8), 1.2),
                                      ('Exit', (23, 12, 11), 1500, (0.45, 1.0, 0.55), 0.8), ('Far', (-20, 28, 11), 1200, (1.0, 0.9, 0.75), 1.0)):
    light = bpy.data.lights.new(name, 'POINT')
    light.energy, light.color, light.shadow_soft_size = power, colour, size
    obj = bpy.data.objects.new(name, light)
    obj.location = at
    scene.collection.objects.link(obj)


def shot(name, eye, target, lens=24):
    cam = bpy.data.objects.new(name, bpy.data.cameras.new(name))
    cam.data.lens = lens
    cam.location = eye
    cam.rotation_euler = (Vector(target) - Vector(eye)).to_track_quat('-Z', 'Y').to_euler()
    scene.collection.objects.link(cam)
    scene.camera = cam
    scene.render.filepath = str(OUT / 'preview' / f'{name}.png')
    bpy.ops.render.render(write_still=True)


(OUT / 'preview').mkdir(parents=True, exist_ok=True)
(OUT / 'blend').mkdir(parents=True, exist_ok=True)
scene.render.engine = 'CYCLES'
scene.cycles.samples = 72
scene.cycles.use_denoising = True
scene.render.resolution_x, scene.render.resolution_y = 1280, 720
scene.view_settings.view_transform = 'Standard'
shot('1_floor_and_pads', (-6, -4, 5.0), (2, 24, 3.2))
shot('2_floor_close', (3, 3.5, 2.4), (-3, 14, 0))
shot('3_pads_close', (-9, 20, 5.2), (-10, 32, 6.5), 35)
shot('4_filthy_corner', (12, 14, 5.0), (28, 24, 5.5), 28)
shot('5_slide_and_post', (-4, 2, 4.2), (8, 12, 2.5), 32)
shot('6_block_wall_and_roof', (-8, 6, 5.0), (-28, 20, 9), 22)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / 'blend' / 'Level6_PBR_Preview.blend'))
print('preview written to', OUT / 'preview')
