"""The shop's product carton for the mall lobby: a taped cardboard box, one mesh, a .blend and a picture.

    /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --threads 2 --python tools/lobby_mall/build_carton.py
    /usr/local/bin/python3 tools/lobby_mall/install_carton.py        # Studio in Edit: uploads it, ServerStorage.MallShopCarton

MALL_CARTON_20261013. The owner: "Kasserne med items passer ikke længere til vores nye lobby stil, kan du ændre
kasserne i shoppen så de faktisk gør?" The crates over the buy spots were the first lobby's holograms (a glowing
see-through cube in teal, gold or red with a lit edge). In a dead 1990s mall the thing on show is a shipping carton:
kraft cardboard, a strip of brown packing tape over the top and a hand's width down two sides, the flaps' seam under
it. The printed label on its four sides (the mall's stripe band, the product's picture, its name) is drawn by
LobbyShopDisplay as SurfaceGuis, so one mesh serves every product. A unit cube; the game scales it.
Writes artifacts/lobby-mall-20261011/carton/: carton.json (the mesh x1000), carton.blend, carton.png.
"""
import json, math
from pathlib import Path
import bpy, numpy as np
from mathutils import Vector

OUT = Path(__file__).resolve().parents[2] / 'artifacts' / 'lobby-mall-20261011' / 'carton'
KRAFT, KRAFT_DARK, TAPE, SEAM = (214, 190, 142), (186, 160, 112), (150, 108, 62), (120, 98, 66)
verts, normals, colours, tris = [], [], [], []


def box(centre, size, colour):
    c, h = np.array(centre, float), np.array(size, float) / 2
    for axis in range(3):
        for sign in (-1, 1):
            n = np.zeros(3); n[axis] = sign
            u, v = np.zeros(3), np.zeros(3)
            u[(axis + 1) % 3], v[(axis + 2) % 3] = 1, 1
            quad = [c + n * h + su * u * h + sv * v * h for su, sv in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
            base = len(verts)
            verts.extend(quad); normals.extend([n] * 4); colours.extend([colour] * 4)
            flat = np.cross(quad[1] - quad[0], quad[2] - quad[0])
            tris.extend([(base, base + 1, base + 2), (base, base + 2, base + 3)] if np.dot(flat, n) > 0 else [(base, base + 2, base + 1), (base, base + 3, base + 2)])


def carton():
    box((0, 0, 0), (1, 1, 1), KRAFT)
    for x in (-0.5, 0.5):                                   # the top flaps' outer edges, a shade darker, and the seam they meet in
        box((x * 0.985, 0.5, 0), (0.03, 0.006, 1.0), KRAFT_DARK)
    box((0, 0.5, 0), (1.0, 0.004, 0.02), SEAM)
    box((0, 0.5, 0), (0.17, 0.012, 1.0), TAPE)              # packing tape over the seam...
    for z in (-0.5, 0.5):
        box((0, 0.445, z), (0.17, 0.11, 0.012), TAPE)       # ...and a hand's width down the front and the back
    for x in (-0.5, 0.5):                                   # the same underneath, where a hovering box shows its bottom
        box((x * 0.985, -0.5, 0), (0.03, 0.006, 1.0), KRAFT_DARK)
    box((0, -0.5, 0), (0.17, 0.012, 1.0), TAPE)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    carton()
    V, N, C, T = np.array(verts), np.array(normals), np.array(colours), np.array(tris)
    middle = (V.min(0) + V.max(0)) / 2
    (OUT / 'carton.json').write_text(json.dumps({'centre': [round(float(v), 4) for v in middle], 'size': [round(float(v), 4) for v in V.max(0) - V.min(0)],
        'triangles': len(T), 'verts': np.rint((V - middle) * 1000).astype(int).ravel().tolist(), 'normals': np.rint(N * 1000).astype(int).ravel().tolist(),
        'colours': C.astype(int).ravel().tolist(), 'tris': T.ravel().tolist()}, separators=(',', ':')) + '\n')
    mesh = bpy.data.meshes.new('MallShopCarton')
    mesh.from_pydata([(p[0], -p[2], p[1]) for p in V], [], [tuple(int(i) for i in t) for t in T])
    layer = mesh.color_attributes.new('Col', 'FLOAT_COLOR', 'POINT')
    for i, c in enumerate(C): layer.data[i].color = (*[(v / 255) ** 2.2 for v in c], 1)
    mat = bpy.data.materials.new('Cardboard'); mat.use_nodes = True
    shader = next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    attr = mat.node_tree.nodes.new('ShaderNodeVertexColor'); attr.layer_name = 'Col'
    mat.node_tree.links.new(attr.outputs['Color'], shader.inputs['Base Color'])
    shader.inputs['Roughness'].default_value = 0.85
    mesh.materials.append(mat)
    scene = bpy.context.scene
    scene.collection.objects.link(bpy.data.objects.new('MallShopCarton', mesh))
    scene.render.engine = 'BLENDER_EEVEE'; scene.render.threads_mode = 'FIXED'; scene.render.threads = 2
    scene.view_settings.view_transform = 'Standard'
    world = bpy.data.worlds.new('Studio'); world.use_nodes = True
    world.node_tree.nodes['Background'].inputs['Color'].default_value = (0.3, 0.28, 0.24, 1)
    scene.world = world
    sun = bpy.data.lights.new('Sun', 'SUN'); sun.energy = 3
    o = bpy.data.objects.new('Sun', sun); o.rotation_euler = (math.radians(50), 0, math.radians(35)); scene.collection.objects.link(o)
    camera = bpy.data.objects.new('Camera', bpy.data.cameras.new('Camera')); scene.collection.objects.link(camera); scene.camera = camera
    camera.location = (1.9, -2.2, 1.5)
    camera.rotation_euler = (Vector((0, 0, 0)) - Vector(camera.location)).to_track_quat('-Z', 'Y').to_euler()
    scene.render.resolution_x, scene.render.resolution_y = 800, 800
    scene.render.filepath = str(OUT / 'carton.png')
    bpy.ops.render.render(write_still=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT / 'carton.blend'))
    print('BUILT carton %d triangles, size %s' % (len(T), (V.max(0) - V.min(0)).round(3).tolist()))


main()
