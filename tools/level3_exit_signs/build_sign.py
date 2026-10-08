"""The exit sign that hangs along Level 3's last corridor, built in Blender.

    /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/level3_exit_signs/build_sign.py

Owner, 2026-10-08: "the exit signs along the long corridor at the exit of Level 3 are to be made in Blender; the
light effect is yours to work out." One ceiling-hung sign, in two meshes because they take two materials in the game:

  housing   the box, its rim, two hanger rods and their ceiling roses (dark painted metal)
  glow      the lens and, standing a hair proud of it, the letters EXIT and an arrow (Neon; the lens is painted
            much darker than the letters in vertex colour, so the letters read and the plate only smoulders)

Modelled in studs. Blender is Z up with the lettered face toward -Y; the export turns that into the game's Y up
with the lettered face toward +Z, and puts each mesh's origin where the rods meet the ceiling, so the builder only
has to know the ceiling's height. Every triangle carries its own three corners (flat shading: the box has bevels).

Written to artifacts/level3-exit-signs-20261008/: blend/Level3_ExitSign.blend, export/exit_sign.json,
preview/exit_sign.png.
"""
import json
import math
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'artifacts' / 'level3-exit-signs-20261008'

W, H, D = 3.4, 1.2, 0.34          # the box
DROP = 1.15                        # ceiling to the top of the box
ROD_X, ROD_R = 1.2, 0.035
LENS_W, LENS_H = 3.06, 0.88
TEXT_H = 0.56

HOUSING = (0.085, 0.09, 0.095)
RIM = (0.13, 0.135, 0.14)
LENS = (0.055, 0.21, 0.13)        # the plate behind the letters: dark, so it only smoulders
LETTER = (0.62, 1.0, 0.74)


def clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def paint(obj, colour):
    layer = obj.data.color_attributes.new('Col', 'BYTE_COLOR', 'CORNER')
    for item in layer.data:
        item.color = (*colour, 1.0)


def box(name, size, at, bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=at)
    obj = bpy.context.object
    obj.name = name
    obj.scale = size
    bpy.ops.object.transform_apply(scale=True)
    if bevel:
        mod = obj.modifiers.new('bevel', 'BEVEL')
        mod.width, mod.segments = bevel, 2
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return obj


def cylinder(name, radius, depth, at, sides=10):
    bpy.ops.mesh.primitive_cylinder_add(vertices=sides, radius=radius, depth=depth, location=at)
    obj = bpy.context.object
    obj.name = name
    return obj


def join(name, parts):
    bpy.ops.object.select_all(action='DESELECT')
    for part in parts:
        part.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    obj = bpy.context.object
    obj.name = name
    return obj


def build_housing():
    centre_z = -DROP - H / 2
    parts = []
    body = box('Body', (W, D, H), (0, 0, centre_z), bevel=0.035)
    paint(body, HOUSING)
    parts.append(body)
    # a rim standing proud round the lens, four bars
    rim_t, rim_d = 0.085, 0.05
    y = -D / 2 - rim_d / 2 + 0.01
    for name, size, at in (
        ('RimTop', (LENS_W + 2 * rim_t, rim_d, rim_t), (0, y, centre_z + LENS_H / 2 + rim_t / 2)),
        ('RimBottom', (LENS_W + 2 * rim_t, rim_d, rim_t), (0, y, centre_z - LENS_H / 2 - rim_t / 2)),
        ('RimLeft', (rim_t, rim_d, LENS_H), (-LENS_W / 2 - rim_t / 2, y, centre_z)),
        ('RimRight', (rim_t, rim_d, LENS_H), (LENS_W / 2 + rim_t / 2, y, centre_z)),
    ):
        bar = box(name, size, at, bevel=0.012)
        paint(bar, RIM)
        parts.append(bar)
    for side in (-1, 1):
        rod = cylinder('Rod', ROD_R, DROP + 0.02, (side * ROD_X, 0, -DROP / 2))
        paint(rod, RIM)
        parts.append(rod)
        rose = cylinder('Rose', 0.15, 0.07, (side * ROD_X, 0, -0.035), sides=14)
        paint(rose, HOUSING)
        parts.append(rose)
        collar = cylinder('Collar', 0.075, 0.09, (side * ROD_X, 0, -DROP + 0.03), sides=10)
        paint(collar, HOUSING)
        parts.append(collar)
    # the ballast box on the back, and a short flex up to the ceiling
    ballast = box('Ballast', (1.1, 0.16, 0.5), (0, D / 2 + 0.07, centre_z + 0.05), bevel=0.02)
    paint(ballast, RIM)
    parts.append(ballast)
    return join('ExitSignHousing', parts)


def build_glow():
    centre_z = -DROP - H / 2
    front = -D / 2 - 0.012
    parts = []
    lens = box('Lens', (LENS_W, 0.012, LENS_H), (0, front, centre_z))
    paint(lens, LENS)
    parts.append(lens)
    # the letters: a font curve turned into a flat mesh, standing a hair proud of the lens
    bpy.ops.object.text_add(location=(0, 0, 0))
    text = bpy.context.object
    text.data.body = 'EXIT'
    text.data.align_x, text.data.align_y = 'CENTER', 'CENTER'
    text.data.size = 1.0
    text.data.space_character = 1.12
    text.data.extrude = 0.0
    bpy.ops.object.convert(target='MESH')
    letters = bpy.context.object
    letters.name = 'Letters'
    box_min = Vector((min(v.co.x for v in letters.data.vertices), min(v.co.y for v in letters.data.vertices)))
    box_max = Vector((max(v.co.x for v in letters.data.vertices), max(v.co.y for v in letters.data.vertices)))
    scale = TEXT_H / (box_max.y - box_min.y)
    middle = (box_min + box_max) / 2
    arrow_room = 0.62                                              # the arrow stands to the right of the word
    for v in letters.data.vertices:
        x = (v.co.x - middle.x) * scale - arrow_room / 2
        z = (v.co.y - middle.y) * scale
        v.co = Vector((x, front - 0.014, centre_z + z))
    paint(letters, LETTER)
    parts.append(letters)
    word_right = (box_max.x - middle.x) * scale - arrow_room / 2
    # the arrow: straight on. A shaft and a head, flat, drawn anticlockwise seen from the front (-Y)
    mesh = bpy.data.meshes.new('Arrow')
    ax = word_right + 0.36
    y = front - 0.014
    s, hw, hh, top = 0.075, 0.2, 0.24, TEXT_H / 2
    pts = [(ax - s, -top), (ax + s, -top), (ax + s, top - hh), (ax + hw, top - hh), (ax, top), (ax - hw, top - hh), (ax - s, top - hh)]
    verts = [(px, y, centre_z + pz) for px, pz in pts]
    mesh.from_pydata(verts, [], [(0, 1, 2, 6), (6, 2, 3, 4, 5)])
    arrow = bpy.data.objects.new('Arrow', mesh)
    bpy.context.collection.objects.link(arrow)
    paint(arrow, LETTER)
    parts.append(arrow)
    glow = join('ExitSignGlow', parts)
    return glow


def numbers(obj):
    """Each triangle with its own corners, in the game's axes (x, z, -y), origin where the rods meet the ceiling."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.transform(obj.matrix_world)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.normal_update()
    layer = bm.loops.layers.color.get('Col')
    verts, normals, colours, tris = [], [], [], []
    for face in bm.faces:
        if face.calc_area() < 1e-9:
            continue
        n = face.normal
        for loop in face.loops:
            p = loop.vert.co
            verts += [round(p.x * 1000), round(p.z * 1000), round(-p.y * 1000)]
            normals += [round(n.x * 1000), round(n.z * 1000), round(-n.y * 1000)]
            c = loop[layer]
            colours += [round(max(0.0, min(1.0, c[i])) * 255) for i in range(3)]
        base = len(tris)
        tris += [base, base + 1, base + 2]
    bm.free()
    xs, ys, zs = verts[0::3], verts[1::3], verts[2::3]
    middle = [(min(a) + max(a)) / 2000 for a in (xs, ys, zs)]
    size = [(max(a) - min(a)) / 1000 for a in (xs, ys, zs)]
    return {'verts': verts, 'normals': normals, 'colours': colours, 'tris': tris,
            'middle': [round(v, 4) for v in middle], 'size': [round(v, 4) for v in size], 'triangles': len(tris) // 3}


def material(name, emission):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    shader = next(n for n in nodes if n.type == 'BSDF_PRINCIPLED')
    attribute = nodes.new('ShaderNodeVertexColor')
    attribute.layer_name = 'Col'
    links.new(attribute.outputs['Color'], shader.inputs['Base Color'])
    if emission:
        links.new(attribute.outputs['Color'], shader.inputs['Emission Color'])
        shader.inputs['Emission Strength'].default_value = emission
    else:
        shader.inputs['Roughness'].default_value = 0.55
        shader.inputs['Metallic'].default_value = 0.6
    return mat


def preview(path):
    scene = bpy.context.scene
    # a strip of ceiling and wall so the sign hangs from something
    bpy.ops.mesh.primitive_plane_add(size=14, location=(0, 0, 0), rotation=(math.pi, 0, 0))
    ceiling = bpy.context.object
    bpy.ops.mesh.primitive_plane_add(size=14, location=(0, 6, -5), rotation=(math.pi / 2, 0, 0))
    wall = bpy.context.object
    grey = bpy.data.materials.new('Room')
    grey.use_nodes = True
    next(n for n in grey.node_tree.nodes if n.type == 'BSDF_PRINCIPLED').inputs['Base Color'].default_value = (0.32, 0.3, 0.27, 1)
    ceiling.data.materials.append(grey)
    wall.data.materials.append(grey)
    bpy.ops.object.light_add(type='POINT', location=(0, -0.9, -DROP - H - 0.25))
    lamp = bpy.context.object
    lamp.data.energy, lamp.data.color = 26, (0.35, 1.0, 0.6)
    bpy.ops.object.light_add(type='AREA', location=(-3, -6, -0.6))
    fill = bpy.context.object
    fill.data.energy, fill.data.size = 18, 4
    bpy.ops.object.camera_add(location=(-2.6, -6.2, -3.4))
    camera = bpy.context.object
    target = Vector((0, 0, -DROP - H / 2 + 0.2))
    camera.rotation_euler = (target - camera.location).to_track_quat('-Z', 'Y').to_euler()
    camera.data.lens = 40
    scene.camera = camera
    engines = [item.identifier for item in scene.render.bl_rna.properties['engine'].enum_items]
    for engine in ('CYCLES', 'BLENDER_EEVEE_NEXT', 'BLENDER_EEVEE', 'BLENDER_WORKBENCH'):
        try:
            scene.render.engine = engine
            break
        except TypeError:
            continue
    if scene.render.engine == 'CYCLES':
        scene.cycles.samples = 48
        scene.cycles.device = 'CPU'
    world = bpy.data.worlds.new('Dark')
    world.use_nodes = True
    world.node_tree.nodes['Background'].inputs['Color'].default_value = (0.004, 0.005, 0.006, 1)
    scene.world = world
    scene.render.resolution_x, scene.render.resolution_y = 1280, 720
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    return scene.render.engine, engines


def main():
    for sub in ('blend', 'export', 'preview'):
        (OUT / sub).mkdir(parents=True, exist_ok=True)
    clear()
    housing = build_housing()
    glow = build_glow()
    housing.data.materials.append(material('Housing', 0))
    glow.data.materials.append(material('Glow', 3.0))
    export = {'origin': 'where the rods meet the ceiling; +z is the lettered face', 'drop': DROP, 'box': [W, H, D],
              'meshes': {housing.name: numbers(housing), glow.name: numbers(glow)}}
    (OUT / 'export' / 'exit_sign.json').write_text(json.dumps(export, separators=(',', ':')))
    for name, mesh in export['meshes'].items():
        print('MESH', name, mesh['triangles'], 'triangles, size', mesh['size'], 'middle', mesh['middle'])
    engine = None
    try:
        engine, _ = preview(OUT / 'preview' / 'exit_sign.png')
    except Exception as problem:                                    # the preview is a look, not a product
        print('PREVIEW FAILED', problem)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT / 'blend' / 'Level3_ExitSign.blend'))
    print('DONE', engine)


main()
