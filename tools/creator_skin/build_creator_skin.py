"""The creator skin ("Creator Gold"): the suit's colour map, the camcorder-and-antenna topper, pictures, a .blend.

    /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --threads 2 --python tools/creator_skin/build_creator_skin.py
    /usr/local/bin/python3 tools/creator_skin/install_creator_skin.py        # Studio in Edit: uploads and templates

CREATOR_SKIN_20261012. The owner's pick of 2026-10-11 ("7 GOLD + CAMCORDER": the gold skin, "a hand held camera from
the 90s on like a stick that points forward and an antenna"), ordered built on 2026-10-12 as the skin the developers
give to streamers. Like every skin it is the game's one suit (assets/hazmat/baseline-rigged.glb) with another colour
map, plus an object on the backpack: paint_creator.py paints the map on the suit itself, and the topper is modelled
here from plain solids, in studs, about the wearer's UpperTorso (x to their right, y up, z behind them).
Writes artifacts/creator-skin-20261012/: creator_gold.png (1024, the map), topper.json (the mesh, x1000, with where its
middle sits), preview_front/back.png, card.png (the shop's picture), creator_skin.blend. No Meshy, no generated art.
"""
import json, math, subprocess, sys, tempfile
from pathlib import Path
import bpy, numpy as np
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'artifacts' / 'creator-skin-20261012'
STUDS = 3.632                      # the suit is 1.7 in the model and 6.17 studs in the game
TORSO = Vector((0, 0.02, 1.07))    # the wearer's UpperTorso in the suit's model space (it faces -y, z up)
DARK, BODY, PANEL, RUBBER = (20, 20, 22), (30, 30, 34), (46, 46, 52), (12, 12, 13)
GLASS, GOLD, RED, STEEL, FOAM = (22, 34, 66), (206, 164, 62), (232, 44, 34), (156, 158, 164), (64, 64, 66)

verts, normals, colours, tris = [], [], [], []


def add(points, norms, colour, faces):
    base = len(verts)
    verts.extend(points); normals.extend(norms); colours.extend([colour] * len(points))
    tris.extend((base + a, base + b, base + c) for a, b, c in faces)


def box(centre, size, colour, turn=None):
    c, h = np.array(centre, float), np.array(size, float) / 2
    turn = np.eye(3) if turn is None else turn
    for axis in range(3):
        for sign in (-1, 1):
            n = np.zeros(3); n[axis] = sign
            u, v = np.zeros(3), np.zeros(3)
            u[(axis + 1) % 3], v[(axis + 2) % 3] = 1, 1
            quad = [n * h + su * u * h + sv * v * h for su, sv in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
            add([c + turn @ p for p in quad], [turn @ n] * 4, colour, [(0, 1, 2), (0, 2, 3)] if sign > 0 else [(0, 2, 1), (0, 3, 2)])


def rod(a, b, ra, rb, colour, sides=12, caps=True):
    a, b = np.array(a, float), np.array(b, float)
    axis = (b - a) / np.linalg.norm(b - a)
    side = np.cross(axis, [0, 1, 0] if abs(axis[1]) < 0.9 else [1, 0, 0]); side /= np.linalg.norm(side)
    up = np.cross(axis, side)
    ring = [side * math.cos(t) + up * math.sin(t) for t in np.linspace(0, math.tau, sides, endpoint=False)]
    points = [a + r * ra for r in ring] + [b + r * rb for r in ring]
    faces = []
    for i in range(sides):
        j = (i + 1) % sides
        faces += [(i, j, sides + j), (i, sides + j, sides + i)]
    add(points, ring + ring, colour, faces)
    if caps:
        for centre, r, n, flip in ((a, ra, -axis, True), (b, rb, axis, False)):
            add([centre] + [centre + q * r for q in ring], [n] * (sides + 1), colour,
                [((0, 1 + (i + 1) % sides, 1 + i) if flip else (0, 1 + i, 1 + (i + 1) % sides)) for i in range(sides)])


def ball(centre, r, colour, rings=6, sides=10):
    c = np.array(centre, float)
    points, norms, faces = [], [], []
    for i in range(rings + 1):
        phi = math.pi * i / rings
        for j in range(sides):
            n = np.array([math.sin(phi) * math.cos(math.tau * j / sides), math.cos(phi), math.sin(phi) * math.sin(math.tau * j / sides)])
            points.append(c + n * r); norms.append(n)
    for i in range(rings):
        for j in range(sides):
            p, q = i * sides + j, i * sides + (j + 1) % sides
            faces += [(p, q, q + sides), (p, q + sides, p + sides)]
    add(points, norms, colour, faces)


def topper():
    """x: the wearer's right. y: up. z: behind. Studs from the UpperTorso's middle. The backpack's top is near y 0.9."""
    box((-0.1, 0.96, 1.2), (2.0, 0.13, 0.42), DARK)                               # the rail across the backpack's top
    # the camera's arm, on the wearer's right: up, an elbow, forward and up beside the hood
    cam = np.array([1.22, 2.08, 0.42])                                            # the camcorder's middle: beside the hood, at head height
    rod((0.74, 1.02, 1.2), (0.74, 1.4, 1.2), 0.08, 0.075, DARK)
    ball((0.74, 1.4, 1.2), 0.115, BODY)
    rod((0.74, 1.4, 1.2), (1.22, 1.68, 0.72), 0.07, 0.07, DARK)
    ball((1.22, 1.68, 0.72), 0.105, BODY)
    box(cam + (0, -0.345, 0.12), (0.34, 0.09, 0.5), DARK)                         # its shoe
    # the camcorder: a boxy 1990s palmcorder looking forward (-z)
    box(cam, (0.52, 0.6, 1.06), BODY)
    box(cam + (0.268, -0.02, 0.1), (0.03, 0.4, 0.66), PANEL)                      # the tape door
    box(cam + (0.275, 0.06, 0.1), (0.02, 0.1, 0.36), RUBBER)                      # its window
    rod(cam + (0, -0.02, -0.53), cam + (0, -0.02, -0.86), 0.2, 0.2, RUBBER, 14)   # the lens barrel
    rod(cam + (0, -0.02, -0.6), cam + (0, -0.02, -0.66), 0.215, 0.215, GOLD, 14)  # one gold ring on it
    rod(cam + (0, -0.02, -0.86), cam + (0, -0.02, -1.04), 0.22, 0.275, RUBBER, 14, caps=False)   # the hood
    rod(cam + (0, -0.02, -0.865), cam + (0, -0.02, -0.875), 0.185, 0.185, GLASS, 14)             # the glass
    box(cam + (-0.17, 0.38, 0.26), (0.2, 0.2, 0.52), BODY)                        # the viewfinder
    rod(cam + (-0.17, 0.38, 0.52), cam + (-0.17, 0.38, 0.66), 0.125, 0.14, RUBBER, 10)           # its eyecup
    for z in (-0.3, 0.3):
        box(cam + (0.14, 0.36, z), (0.1, 0.14, 0.1), DARK)                        # the carrying handle
    box(cam + (0.14, 0.45, 0), (0.12, 0.08, 0.74), DARK)
    rod(cam + (0.14, 0.33, -0.36), cam + (0.14, 0.33, -0.78), 0.062, 0.062, FOAM, 8)             # the microphone
    box(cam + (0, -0.04, 0.585), (0.42, 0.44, 0.11), DARK)                        # the battery on its back
    rod(cam + (0.12, 0.2, 0.53), cam + (0.12, 0.2, 0.552), 0.05, 0.05, RED, 10)   # the REC light, seen from behind
    # the aerial, on the wearer's left: a base, a spring, three lengths and a tip
    rod((-0.94, 1.05, 1.2), (-0.94, 1.4, 1.2), 0.12, 0.1, DARK)
    rod((-0.94, 1.4, 1.2), (-0.94, 1.68, 1.2), 0.07, 0.06, RUBBER, 10)
    rod((-0.94, 1.68, 1.2), (-0.94, 2.75, 1.2), 0.055, 0.055, STEEL, 8)          # (thicker than a real one: thinner did not draw in play)
    rod((-0.94, 2.75, 1.2), (-0.94, 3.55, 1.2), 0.042, 0.042, STEEL, 8)
    rod((-0.94, 3.55, 1.2), (-0.94, 4.15, 1.2), 0.032, 0.032, STEEL, 6)
    ball((-0.94, 4.17, 1.2), 0.07, STEEL, 4, 8)


def to_model(p):
    """Topper studs (x right, y up, z back) to the suit's model space (it faces -y, its right is -x)."""
    return TORSO + Vector((-p[0], p[2], p[1])) / STUDS


def emission(name, colour_node_builder):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    nodes, links = material.node_tree.nodes, material.node_tree.links
    shader = next(n for n in nodes if n.type == 'BSDF_PRINCIPLED')
    colour_node_builder(nodes, links, shader)
    return material


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    with tempfile.TemporaryDirectory(prefix='creator_skin_', dir='/tmp') as scratch:
        scratch = Path(scratch)
        for name in ('baseline-rigged.glb', 'textures/baseline-yellow.png'):
            (scratch / Path(name).name).write_bytes(subprocess.run(['git', 'show', 'HEAD:assets/hazmat/' + name], cwd=ROOT, capture_output=True, check=True).stdout)
        bpy.ops.import_scene.gltf(filepath=str(scratch / 'baseline-rigged.glb'))
        suit = bpy.data.objects['char1']
        stray = bpy.data.objects.get('Icosphere')
        if stray: bpy.data.objects.remove(stray)
        mesh = suit.data
        mesh.calc_loop_triangles()
        where = np.array([suit.matrix_world @ v.co for v in mesh.vertices], np.float32)
        uv = mesh.uv_layers[0].data
        np.savez(scratch / 'suit_mesh.npz', tri_pos=np.array([[where[v] for v in t.vertices] for t in mesh.loop_triangles], np.float32),
                 tri_uv=np.array([[tuple(uv[l].uv) for l in t.loops] for t in mesh.loop_triangles], np.float32))
        painted = subprocess.run(['/usr/local/bin/python3', '-B', str(Path(__file__).with_name('paint_creator.py')), str(scratch / 'suit_mesh.npz'),
                                  str(scratch / 'baseline-yellow.png'), str(OUT)], capture_output=True, text=True, check=True)
        print(painted.stdout.strip())

    # the suit wears the new map; lit, not self-lit (the Meshy export made every skin glow)
    image = bpy.data.images.load(str(OUT / 'creator_gold_2048.png'))
    def suit_nodes(nodes, links, shader):
        tex = nodes.new('ShaderNodeTexImage'); tex.image = image
        links.new(tex.outputs['Color'], shader.inputs['Base Color'])
        shader.inputs['Roughness'].default_value = 0.62
    mesh.materials.clear(); mesh.materials.append(emission('CreatorGoldSuit', suit_nodes))

    # arms down at the sides, as the shop stands the suits
    rig = bpy.data.objects['Armature']
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode='POSE')
    for side, sign in (('Left', 1), ('Right', -1)):
        bone = rig.pose.bones.get(side + 'Arm')
        if bone:
            bone.rotation_mode = 'XYZ'
            world = rig.matrix_world @ bone.matrix
            pivot = world.translation.copy()
            turned = Matrix.Translation(pivot) @ Matrix.Rotation(math.radians(64 * sign), 4, Vector((0, 1, 0))) @ Matrix.Translation(-pivot) @ world
            bone.matrix = rig.matrix_world.inverted() @ turned
            bpy.context.view_layer.update()
    bpy.ops.object.mode_set(mode='OBJECT')

    topper()
    V, Nm, C, T = np.array(verts), np.array(normals), np.array(colours), np.array(tris)
    middle = (V.min(0) + V.max(0)) / 2
    (OUT / 'topper.json').write_text(json.dumps({
        'centre': [round(float(v), 4) for v in middle], 'size': [round(float(v), 4) for v in V.max(0) - V.min(0)],
        'verts': np.rint((V - middle) * 1000).astype(int).ravel().tolist(), 'normals': np.rint(Nm * 1000).astype(int).ravel().tolist(),
        'colours': C.astype(int).ravel().tolist(), 'tris': T.ravel().tolist()}, separators=(',', ':')) + '\n')
    top = bpy.data.meshes.new('CreatorGoldTopper')
    top.from_pydata([tuple(to_model(p)) for p in V], [], [tuple(int(i) for i in t) for t in T])
    layer = top.color_attributes.new('Col', 'FLOAT_COLOR', 'POINT')
    for i, c in enumerate(C): layer.data[i].color = (*[(v / 255) ** 2.2 for v in c], 1)
    top.normals_split_custom_set_from_vertices([tuple(Vector((-n[0], n[2], n[1])).normalized()) for n in Nm])
    def top_nodes(nodes, links, shader):
        attr = nodes.new('ShaderNodeVertexColor'); attr.layer_name = 'Col'
        links.new(attr.outputs['Color'], shader.inputs['Base Color'])
        shader.inputs['Roughness'].default_value = 0.5
    top.materials.append(emission('CreatorGoldTopper', top_nodes))
    top_object = bpy.data.objects.new('CreatorGoldTopper', top)
    bpy.context.scene.collection.objects.link(top_object)

    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_EEVEE'; scene.render.threads_mode = 'FIXED'; scene.render.threads = 2
    if hasattr(scene, 'eevee'): scene.eevee.taa_render_samples = 32
    scene.render.film_transparent = True
    scene.view_settings.view_transform = 'Standard'
    world = bpy.data.worlds.new('Studio'); world.use_nodes = True
    world.node_tree.nodes['Background'].inputs['Color'].default_value = (0.16, 0.16, 0.17, 1)
    world.node_tree.nodes['Background'].inputs['Strength'].default_value = 0.35
    scene.world = world
    for name, at, power, size in (('Key', (-2.2, -3.2, 3.4), 210, 3), ('Fill', (2.6, -2.4, 1.6), 55, 4), ('Rim', (0.6, 3.2, 3.0), 230, 3), ('Back', (-2.0, 3.0, 2.2), 120, 4)):
        lamp = bpy.data.lights.new(name, 'AREA'); lamp.energy, lamp.size = power, size
        o = bpy.data.objects.new(name, lamp); o.location = at
        o.rotation_euler = (Vector((0, 0, 1.0)) - Vector(at)).to_track_quat('-Z', 'Y').to_euler()
        scene.collection.objects.link(o)
    camera = bpy.data.objects.new('Camera', bpy.data.cameras.new('Camera')); scene.collection.objects.link(camera); scene.camera = camera
    camera.data.lens = 70
    def shot(name, at, look, size):
        camera.location = at
        camera.rotation_euler = (Vector(look) - Vector(at)).to_track_quat('-Z', 'Y').to_euler()
        scene.render.resolution_x, scene.render.resolution_y = size
        scene.render.filepath = str(OUT / name)
        bpy.ops.render.render(write_still=True)
    shot('preview_front.png', (-2.6, -5.4, 1.5), (0, 0, 1.12), (900, 1200))
    shot('preview_back.png', (2.4, 5.5, 1.6), (0, 0, 1.12), (900, 1200))
    shot('card.png', (-1.9, -5.8, 1.35), (0, 0, 1.1), (768, 1024))
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT / 'creator_skin.blend'))
    print(f'BUILT topper {len(V)} vertices {len(T)} triangles, middle {middle.round(3).tolist()}, size {(V.max(0) - V.min(0)).round(3).tolist()}')


main()
