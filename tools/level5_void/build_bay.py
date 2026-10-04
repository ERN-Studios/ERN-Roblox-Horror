"""The Level 5 and Level 4 queue bays in the lobby, dressed to match their levels (2026-10-04). Built in Blender.

    /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/level5_void/build_bay.py

Level 5: a small void room (the stair to the lit doorway, monoliths, balls). Level 4: the foyer of the synthwave
cinema (a NOW SHOWING marquee with bulbs over the seat row, neon poster frames, rope posts at the entrance).
Writes artifacts/level5-void-20261003/blend/Level5_Bay.blend and Level4_Bay.blend and injects each set as a Lua
table into ServerScriptService/LobbyReimaginedPreview/Builder.ModuleScript.lua between its LEVELn_BAY_SET markers
(the lobby is built by code at server start, so the sets live in the builder). Push Builder afterwards.

Bay-local coordinates: x across, y up from the floor's top, z toward the entrance. The four queue pads are
circles of radius 7.41 at (+-13.2, +-9); the wall is a 60-gon with its inner face at 27.7. Every piece is
asserted to stay off the pads and inside the wall. Level 5's pieces stand on the floor (nothing floats there).
"""
import json, math, re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
PADS, PAD_R, WALL_R, CEILING = [(13.2, 9.0), (-13.2, 9.0), (13.2, -9.0), (-13.2, -9.0)], 7.41, 27.5, 22.0
SETS = {5: [], 4: []}
SET = SETS[5]


def block(name, colour, w, h, d, x, z, y0=0.0, collide=True, yaw=0.0, **extra):
    c, s = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    for a in (-w / 2, w / 2):
        for b in (-d / 2, d / 2):
            cx, cz = x + c * a + s * b, z - s * a + c * b
            assert math.hypot(cx, cz) <= WALL_R + 0.45, f'{name} reaches into the wall ({math.hypot(cx, cz):.2f})'
            for px, pz in PADS:
                assert math.hypot(cx - px, cz - pz) >= PAD_R + 0.5, f'{name} stands on a queue pad'
    assert y0 + h <= CEILING, f'{name} goes through the roof'
    row = {'n': name, 'c': colour, 's': [w, h, d], 'p': [x, y0 + h / 2, z], 'sh': 'b', 'col': collide, **extra}
    if yaw:
        row['yaw'] = yaw
    SET.append(row)


def ball(colour, r, x, y, z, **extra):
    SET.append({'n': 'Ball', 'c': colour, 's': [r * 2] * 3, 'p': [x, y + r, z], 'sh': 's', 'col': True, **extra})


# ------------------------------------------------------------------------------------------------ Level 5
# the stair to the lit doorway: one step per room, in the level's order
z = -17.6
for k, colour in enumerate(('rose', 'blue', 'amber', 'mint', 'violet')):
    depth = 1.7 if k < 4 else 1.9
    block('Step', colour, 9.0, 0.8 * (k + 1), depth, 0.0, z - depth / 2)
    z -= depth
block('Door', 'black', 6.0, 11.0, 0.4, 0.0, -26.55, y0=4.0, material='SmoothPlastic')
for side in (-1, 1):
    block('DoorPost', 'coral', 1.0, 15.0, 1.0, side * 3.5, -26.55)
block('DoorLintel', 'coral', 8.0, 1.1, 1.0, 0.0, -26.55, y0=15.0)
SET.append({'n': 'Orb', 'c': 'orb', 's': [2.2] * 3, 'p': [0.0, 17.4, -22.0], 'sh': 's', 'col': False, 'material': 'Neon', 'light': [30, 1.3]})
SET.append({'n': 'OrbRod', 'c': 'black', 's': [0.2, CEILING - 18.5, 0.2], 'p': [0.0, (CEILING + 18.5) / 2, -22.0], 'sh': 'b', 'col': False, 'material': 'Metal'})
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

# ------------------------------------------------------------------------------------------------ Level 4
SET = SETS[4]
# the marquee: over the seat row on the rear wall (the row is 10.8 high), lettering lit, a line of bulbs under it
block('Marquee', 'screen', 14.0, 3.4, 0.6, 0.0, -26.3, y0=12.6, collide=False, material='SmoothPlastic', text='NOW SHOWING', tc='warm')
block('MarqueeTrim', 'magenta', 14.6, 0.24, 0.7, 0.0, -26.3, y0=16.0, collide=False, material='Neon')
block('MarqueeTrim', 'cyan', 14.6, 0.24, 0.7, 0.0, -26.3, y0=12.36, collide=False, material='Neon')
for k in range(9):
    SET.append({'n': 'Bulb', 'c': 'warm', 's': [0.5] * 3, 'p': [-6.4 + k * 1.6, 12.0, -25.9], 'sh': 's', 'col': False, 'material': 'Neon',
                **({'light': [16, 0.7]} if k in (1, 4, 7) else {})})
# four poster cases round the wall, each a one-sheet in a neon frame, turned to face the middle. The images are
# the four "films" of the cinema (assets/lobby-posters-20261004, made from the level's own screenshots).
POSTERS = [(-1, 132.0, 'cyan', 111560448892703), (1, 132.0, 'magenta', 99844209195430)]
for side, angle, glow, image in POSTERS:
    px, pz = side * 26.5 * math.sin(math.radians(angle)), -26.5 * math.cos(math.radians(angle))
    yaw = -side * angle
    block('Poster', 'screen', 5.4, 8.1, 0.3, px, pz, y0=3.4, collide=False, yaw=yaw, material='SmoothPlastic', img=image)
    block('PosterFrame', glow, 6.0, 0.22, 0.4, px, pz, y0=11.5, collide=False, yaw=yaw, material='Neon', light=[14, 0.6], lc=glow)
    block('PosterFrame', glow, 6.0, 0.22, 0.4, px, pz, y0=3.18, collide=False, yaw=yaw, material='Neon')
# The two posters the bay's original decor carries on its back panel, either side of the desk, are the ones
# the owner called "very bad". They are part of that mesh's texture, so each is covered by a new one-sheet
# standing just in front of it.
for side, glow, image in ((-1, 'magenta', 107732660117869), (1, 'cyan', 70389718286652)):
    block('Poster', 'screen', 5.8, 8.7, 0.3, side * 7.0, -23.5, y0=3.0, collide=False, material='SmoothPlastic', img=image)
    block('PosterFrame', glow, 6.4, 0.22, 0.4, side * 7.0, -23.5, y0=11.72, collide=False, material='Neon', light=[14, 0.6], lc=glow)
    block('PosterFrame', glow, 6.4, 0.22, 0.4, side * 7.0, -23.5, y0=2.78, collide=False, material='Neon')
# rope posts either side of the way in
for side in (-1, 1):
    for pz in (17.0, 21.5, 26.0):
        block('RopePost', 'gold', 0.5, 3.2, 0.5, side * 3.6, pz, material='Metal')
        SET.append({'n': 'RopeCap', 'c': 'gold', 's': [0.8] * 3, 'p': [side * 3.6, 3.4, pz], 'sh': 's', 'col': False, 'material': 'Metal'})
    for pz in (19.25, 23.75):
        block('Rope', 'velvet', 0.22, 0.22, 4.2, side * 3.6, pz, y0=2.5, collide=False, material='Fabric')

builder = ROOT / 'ServerScriptService' / 'LobbyReimaginedPreview' / 'Builder.ModuleScript.lua'
source = builder.read_text()
for level, rows in SETS.items():
    lines = []
    for row in rows:
        fields = [f'n="{row["n"]}"', f'c="{row["c"]}"', 's={%s}' % ','.join(f'{v:g}' for v in row['s']),
                  'p={%s}' % ','.join(f'{v:.3f}'.rstrip('0').rstrip('.') for v in row['p'])]
        if row['sh'] == 's':
            fields.append('ball=true')
        if not row['col']:
            fields.append('ghost=true')
        for key, lua in (('material', 'm'), ('text', 'text'), ('tc', 'tc'), ('lc', 'lc')):
            if row.get(key):
                fields.append(f'{lua}="{row[key]}"')
        if row.get('yaw'):
            fields.append('yaw=%g' % row['yaw'])
        if row.get('light'):
            fields.append('light={%g,%g}' % tuple(row['light']))
        if row.get('img'):
            fields.append('img="rbxassetid://%d"' % row['img'])
        lines.append('\t\t\t\t{' + ', '.join(fields) + '},')
    pattern = re.compile(r'(-- LEVEL%d_BAY_SET_BEGIN[^\n]*\n).*?(\t\t\t\t-- LEVEL%d_BAY_SET_END)' % (level, level), re.S)
    assert pattern.search(source), f'the builder has no LEVEL{level}_BAY_SET markers'
    source = pattern.sub(lambda m: m.group(1) + '\n'.join(lines) + '\n' + m.group(2), source)
    print(f'Level {level} bay: {len(rows)} pieces written into the lobby builder')
builder.write_text(source)

try:
    import bpy
except ImportError:
    bpy = None
if bpy:
    import bmesh
    COLOURS = {'rose': (224, 150, 200), 'blue': (92, 150, 200), 'amber': (228, 180, 88), 'mint': (150, 216, 182),
               'violet': (164, 134, 214), 'coral': (236, 118, 102), 'black': (4, 4, 5), 'sphere': (26, 38, 120),
               'orb': (255, 255, 250), 'navy': (34, 20, 64), 'magenta': (255, 64, 176), 'cyan': (70, 230, 255),
               'gold': (212, 170, 80), 'velvet': (150, 22, 44), 'carpet': (46, 22, 60), 'screen': (12, 10, 20), 'warm': (255, 214, 150)}
    for level, rows in SETS.items():
        bpy.ops.wm.read_factory_settings(use_empty=True)
        mats = {}
        for key, rgb in COLOURS.items():
            m = bpy.data.materials.new('Bay_' + key)
            m.diffuse_color = (*[(c / 255) ** 2.2 for c in rgb], 1)
            mats[key] = m
        col = bpy.data.collections.new(f'Level{level}_Bay')
        bpy.context.scene.collection.children.link(col)
        cube = bpy.data.meshes.new('Cube'); bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0); bm.to_mesh(cube); bm.free()
        sphere = bpy.data.meshes.new('Ball'); bm = bmesh.new(); bmesh.ops.create_uvsphere(bm, u_segments=24, v_segments=12, radius=0.5); bm.to_mesh(sphere); bm.free()
        floor = bpy.data.meshes.new('Floor'); bm = bmesh.new(); bmesh.ops.create_cone(bm, cap_ends=True, segments=60, radius1=27.9, radius2=27.9, depth=0.05); bm.to_mesh(floor); bm.free()
        floor.materials.append(mats['black' if level == 5 else 'carpet'])
        col.objects.link(bpy.data.objects.new('BayFloor', floor))
        for i, row in enumerate(rows):
            mesh = (sphere if row['sh'] == 's' else cube).copy()
            mesh.materials.append(mats[row['c']])
            ob = bpy.data.objects.new(f"{row['n']}_{i:02d}", mesh)
            x, y, z = row['p']
            ob.location = (x, -z, y)
            ob.scale = (row['s'][0], row['s'][2], row['s'][1])
            ob.rotation_euler = (0, 0, math.radians(row.get('yaw', 0)))
            col.objects.link(ob)
        out = ROOT / 'artifacts' / 'level5-void-20261003' / 'blend'
        out.mkdir(parents=True, exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=str(out / f'Level{level}_Bay.blend'))
        print('saved', out / f'Level{level}_Bay.blend')
