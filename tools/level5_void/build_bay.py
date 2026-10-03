"""The Level 5 queue bay in the lobby, dressed as a small void room (2026-10-04). Built in Blender.

    /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/level5_void/build_bay.py

Writes artifacts/level5-void-20261003/blend/Level5_Bay.blend and injects the set as a Lua table into
ServerScriptService/LobbyReimaginedPreview/Builder.ModuleScript.lua between the LEVEL5_BAY_SET markers (the
lobby is built by code at server start, so the set has to live in the builder). Push Builder afterwards.

Bay-local coordinates: x across, y up from the floor's top, z toward the entrance. The four queue pads are
circles of radius 7.41 at (+-13.2, +-9); the wall is a 60-gon with its inner face at 27.7. Every piece is
asserted to stay off the pads and inside the wall, and stands on the floor: nothing floats here either.
"""
import json, math, re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
PADS, PAD_R, WALL_R, CEILING = [(13.2, 9.0), (-13.2, 9.0), (13.2, -9.0), (-13.2, -9.0)], 7.41, 27.5, 22.0
SET = []


def block(name, colour, w, h, d, x, z, y0=0.0, collide=True, **extra):
    for cx in (x - w / 2, x + w / 2):
        for cz in (z - d / 2, z + d / 2):
            assert math.hypot(cx, cz) <= WALL_R, f'{name} reaches into the wall'
    for px, pz in PADS:
        nx, nz = min(max(px, x - w / 2), x + w / 2), min(max(pz, z - d / 2), z + d / 2)
        assert math.hypot(nx - px, nz - pz) >= PAD_R + 0.6, f'{name} stands on a queue pad'
    assert y0 + h <= CEILING, f'{name} goes through the roof'
    SET.append({'n': name, 'c': colour, 's': [w, h, d], 'p': [x, y0 + h / 2, z], 'sh': 'b', 'col': collide, **extra})


def ball(colour, r, x, y, z, **extra):
    SET.append({'n': 'Ball', 'c': colour, 's': [r * 2] * 3, 'p': [x, y + r, z], 'sh': 's', 'col': True, **extra})


# the stair to the lit doorway: one step per room, in the level's order
z = -17.6
for k, colour in enumerate(('rose', 'blue', 'amber', 'mint', 'violet')):
    depth = 1.7 if k < 4 else 1.9
    block('Step', colour, 9.0, 0.8 * (k + 1), depth, 0.0, z - depth / 2)
    z -= depth
block('Door', 'black', 6.0, 11.0, 0.4, 0.0, -26.55, y0=4.0, material='SmoothPlastic')
for side in (-1, 1):
    block('DoorPost', 'violet', 1.0, 15.0, 1.0, side * 3.5, -26.55)
block('DoorLintel', 'violet', 8.0, 1.1, 1.0, 0.0, -26.55, y0=15.0)
SET.append({'n': 'Orb', 'c': 'orb', 's': [2.2] * 3, 'p': [0.0, 17.4, -22.0], 'sh': 's', 'col': False, 'material': 'Neon', 'light': [30, 1.3]})
SET.append({'n': 'OrbRod', 'c': 'black', 's': [0.2, CEILING - 18.5, 0.2], 'p': [0.0, (CEILING + 18.5) / 2, -22.0], 'sh': 'b', 'col': False, 'material': 'Metal'})
# monoliths beside the stair, and the low blocks to sit on where the sofa and the bench stood
block('Monolith', 'rose', 3.2, 13.0, 3.2, -8.2, -23.4)
block('Monolith', 'mint', 2.6, 8.5, 2.6, -11.6, -20.6)
block('Monolith', 'amber', 3.0, 10.5, 3.0, 8.0, -23.6)
block('Monolith', 'blue', 2.4, 6.0, 2.4, 11.4, -20.8)
block('Bench', 'rose', 2.6, 1.7, 8.0, -22.6, 0.0)
block('Bench', 'blue', 2.6, 1.7, 8.0, 22.6, 0.0)
block('Monolith', 'amber', 1.8, 9.0, 1.8, -23.2, -5.6)
block('Monolith', 'mint', 1.8, 9.0, 1.8, 23.2, 5.6)
ball('sphere', 0.8, 2.8, 1.6, -20.15)
ball('sphere', 1.5, -5.6, 0.0, -18.9)
ball('sphere', 1.0, 11.4, 6.0, -20.8)
ball('sphere', 0.7, -22.6, 1.7, 2.4)

lines = []
for row in SET:
    fields = [f'n="{row["n"]}"', f'c="{row["c"]}"', 's={%s}' % ','.join(f'{v:g}' for v in row['s']),
              'p={%s}' % ','.join(f'{v:g}' for v in row['p'])]
    if row['sh'] == 's':
        fields.append('ball=true')
    if not row['col']:
        fields.append('ghost=true')
    if row.get('material'):
        fields.append(f'm="{row["material"]}"')
    if row.get('light'):
        fields.append('light={%g,%g}' % tuple(row['light']))
    lines.append('\t\t\t{' + ', '.join(fields) + '},')
builder = ROOT / 'ServerScriptService' / 'LobbyReimaginedPreview' / 'Builder.ModuleScript.lua'
source = builder.read_text()
pattern = re.compile(r'(-- LEVEL5_BAY_SET_BEGIN[^\n]*\n).*?(\t\t\t-- LEVEL5_BAY_SET_END)', re.S)
assert pattern.search(source), 'the builder has no LEVEL5_BAY_SET markers'
builder.write_text(pattern.sub(lambda m: m.group(1) + '\n'.join(lines) + '\n' + m.group(2), source))
print(f'{len(SET)} pieces written into the lobby builder')

try:
    import bpy
except ImportError:
    bpy = None
if bpy:
    import bmesh
    bpy.ops.wm.read_factory_settings(use_empty=True)
    COLOURS = {'rose': (224, 150, 200), 'blue': (92, 150, 200), 'amber': (228, 180, 88), 'mint': (150, 216, 182),
               'violet': (164, 134, 214), 'black': (4, 4, 5), 'sphere': (26, 38, 120), 'orb': (255, 255, 250)}
    mats = {}
    for key, rgb in COLOURS.items():
        m = bpy.data.materials.new('L5_' + key)
        m.diffuse_color = (*[(c / 255) ** 2.2 for c in rgb], 1)
        mats[key] = m
    col = bpy.data.collections.new('Level5_Bay')
    bpy.context.scene.collection.children.link(col)
    cube = bpy.data.meshes.new('Cube'); bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0); bm.to_mesh(cube); bm.free()
    sphere = bpy.data.meshes.new('Ball'); bm = bmesh.new(); bmesh.ops.create_uvsphere(bm, u_segments=24, v_segments=12, radius=0.5); bm.to_mesh(sphere); bm.free()
    floor = bpy.data.meshes.new('Floor'); bm = bmesh.new(); bmesh.ops.create_cone(bm, cap_ends=True, segments=60, radius1=27.9, radius2=27.9, depth=0.05); bm.to_mesh(floor); bm.free()
    floor.materials.append(mats['black'])
    col.objects.link(bpy.data.objects.new('VoidFloor', floor))
    for i, row in enumerate(SET):
        mesh = (sphere if row['sh'] == 's' else cube).copy()
        mesh.materials.append(mats[row['c']])
        ob = bpy.data.objects.new(f"{row['n']}_{i:02d}", mesh)
        x, y, z = row['p']
        ob.location = (x, -z, y)
        ob.scale = (row['s'][0], row['s'][2], row['s'][1])
        col.objects.link(ob)
    out = ROOT / 'artifacts' / 'level5-void-20261003' / 'blend'
    out.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(out / 'Level5_Bay.blend'))
    print('saved', out / 'Level5_Bay.blend')
