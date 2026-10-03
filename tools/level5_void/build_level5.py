"""Level 5 "the void rooms", built in Blender (2026-10-03): five single-colour rooms in a row, joined by dark corridors,
every path over a black drop. Writes artifacts/level5-void-20261003/build/level5.json (parts, lights, route).

    /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/level5_void/build_level5.py

Blender builds the scene (artifacts/.../blend/Level5_Void.blend, every part an object with its material, the
lamps as point lights) and writes the same parts out as level5.json for the Studio importer.

JUMPS ARE COMPUTED, NOT GUESSED. The body walks at 16 studs/s and jumps with JumpPower 50 under gravity 196.2.
`reach(dy)` is how far that carries to a landing dy studs higher (negative = lower); every gap is asserted to
be at most MAX_SHARE of it, and the share rises section by section. import_level5.py then walks the whole
route in Studio with a scripted player at walking speed, so the numbers are checked against the engine too.
"""
import json, math
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
OUT = ROOT / 'artifacts' / 'level5-void-20261003' / 'build'
WALK, JUMP, GRAVITY = 16.0, 50.0, 196.2
BOTTOM = -420.0            # the walls go this far down; nothing below the paths is lit
HALF = 60.0                # rooms are 120 wide inside
COLOURS = {
    'rose': (224, 150, 200), 'blue': (92, 150, 200), 'amber': (228, 180, 88),
    'mint': (150, 216, 182), 'violet': (164, 134, 214), 'black': (4, 4, 5),
    'sphere': (26, 38, 120), 'orb': (255, 255, 250),
}
PARTS, LIGHTS, ROUTE, CHECKPOINTS, GAPS = [], [], [], [], []
ENTRY, LOW = {}, {}   # section -> where a fall puts you back, and its lowest walking height
EXTENT = {}        # section -> [min x, max x, min z, max z] of its walkable pieces
CLEAR_Z = 41.0     # the folds' faces start at about 45; a path keeps this side of them


def reach(dy):
    disc = JUMP * JUMP - 2 * GRAVITY * dy
    assert disc > 0, f'a rise of {dy} is above the jump apex'
    return WALK * (JUMP + math.sqrt(disc)) / GRAVITY


def part(name, size, pos, colour, yaw=0.0, pitch=0.0, shape='b', collide=True, material='SmoothPlastic', extra=None):
    row = {'n': name, 's': [round(v, 3) for v in size], 'p': [round(v, 3) for v in pos], 'c': colour,
           'yaw': round(yaw, 3), 'pitch': round(pitch, 3), 'sh': shape, 'col': collide, 'm': material}
    if extra:
        row.update(extra)
    PARTS.append(row)


def light(pos, rng=60, brightness=1.0):
    LIGHTS.append({'p': [round(v, 2) for v in pos], 'r': rng, 'b': brightness})


class Path_:
    """A cursor that lays walkable pieces end to end. x runs along the level, z across it, y is the walking surface."""
    def __init__(self, section, colour, x, y, z, heading=0.0):
        self.section, self.colour = section, colour
        self.x, self.y, self.z, self.h = x, y, z, heading
        self.jump_next = False
        ENTRY[section] = (x + 6 * math.cos(math.radians(heading)), y, z + 6 * math.sin(math.radians(heading)))

    def dir(self):
        r = math.radians(self.h)
        return math.cos(r), math.sin(r)

    def point(self, along=0.0):
        dx, dz = self.dir()
        return self.x + dx * along, self.y, self.z + dz * along

    def way(self, along, jump=False):
        x, y, z = self.point(along)
        e = EXTENT.setdefault(self.section, [x, x, z, z])
        e[0], e[1], e[2], e[3] = min(e[0], x), max(e[1], x), min(e[2], z), max(e[3], z)
        LOW[self.section] = min(LOW.get(self.section, y), y)
        ROUTE.append({'x': round(x, 2), 'y': round(y, 2), 'z': round(z, 2), 'jump': jump, 'sec': self.section})

    def plat(self, length, width, thick=3.0, name='Walk'):
        dx, dz = self.dir()
        cx, cz = self.x + dx * length / 2, self.z + dz * length / 2
        part(name, (length, thick, width), (cx, self.y - thick / 2, cz), self.colour, yaw=self.h)
        self.way(min(2.0, length / 2), jump=self.jump_next)
        self.jump_next = False
        self.x, self.z = self.x + dx * length, self.z + dz * length
        self.way(-0.9)
        return self

    def joint(self, width, thick=3.0):
        """A square pad centred on the cursor, so a turn has no notch in it."""
        part('Walk', (width, thick, width), (self.x, self.y - thick / 2, self.z), self.colour, yaw=self.h)
        return self

    def turn(self, degrees, width=None):
        if width:
            self.joint(width)
        self.h += degrees
        return self

    def gap(self, distance, dy=0.0, share=0.75):
        limit = reach(dy)
        assert distance <= limit * share + 1e-6, \
            f'{self.section}: gap {distance} with dy {dy} is {distance / limit:.0%} of the {limit:.2f} reach (cap {share:.0%})'
        GAPS.append({'sec': self.section, 'gap': distance, 'dy': dy, 'reach': round(limit, 2), 'share': round(distance / limit, 3)})
        dx, dz = self.dir()
        self.x, self.z, self.y = self.x + dx * distance, self.z + dz * distance, self.y + dy
        self.jump_next = True
        return self

    def ramp(self, length, dy, width, thick=2.0):
        dx, dz = self.dir()
        slope = math.degrees(math.atan2(dy, length))
        real = math.hypot(length, dy)
        cx, cz = self.x + dx * length / 2, self.z + dz * length / 2
        part('Walk', (real, thick, width), (cx, self.y + dy / 2 - thick / 2, cz), self.colour, yaw=self.h, pitch=slope)
        self.way(min(2.0, length / 2), jump=self.jump_next)
        self.jump_next = False
        self.x, self.z, self.y = self.x + dx * length, self.z + dz * length, self.y + dy
        self.way(-0.9)
        return self

    def stairs(self, steps, run, rise, w0, w1, thick=3.0):
        dx, dz = self.dir()
        self.way(0.5, jump=self.jump_next)
        self.jump_next = False
        for i in range(steps):
            width = w0 + (w1 - w0) * i / max(1, steps - 1)
            self.y += rise
            cx, cz = self.x + dx * run / 2, self.z + dz * run / 2
            part('Step', (run, thick, width), (cx, self.y - thick / 2, cz), self.colour, yaw=self.h)
            self.x, self.z = self.x + dx * run, self.z + dz * run
            if i % 6 == 5:
                self.way(-run / 2)
        self.way(-0.5)
        return self


def sphere(x, y, z, r=1.4):
    part('Sphere', (r * 2, r * 2, r * 2), (x, y + r, z), 'sphere', shape='s', extra={'refl': 0.3})


def orb(x, y, z):
    part('Orb', (5, 5, 5), (x, y, z), 'orb', shape='s', collide=False, material='Neon', extra={'light': [46, 2.6]})


def wall_with_door(x, colour, top, door_z, door_y, thick=8.0, door_w=9.0, door_h=13.0):
    """An end wall (constant x) with a doorway at walking height door_y, centred on door_z."""
    def slab(z0, z1, y0, y1):
        if z1 - z0 > 0.05 and y1 - y0 > 0.05:
            part('Wall', (thick, y1 - y0, z1 - z0), (x, (y0 + y1) / 2, (z0 + z1) / 2), colour)
    slab(-HALF - 8, door_z - door_w / 2, BOTTOM, top)
    slab(door_z + door_w / 2, HALF + 8, BOTTOM, top)
    slab(door_z - door_w / 2, door_z + door_w / 2, door_y + door_h, top)
    slab(door_z - door_w / 2, door_z + door_w / 2, BOTTOM, door_y)        # the sill is the floor of the doorway


def room(name, colour, x0, x1, top, lights_y, light_gain=1.0, light_step=34.0):
    length = x1 - x0
    e = EXTENT[name]
    assert e[0] >= x0 - 0.01 and e[1] <= x1 + 0.01, f'{name}: the path runs x {e[0]:.1f}..{e[1]:.1f}, outside the room {x0:.1f}..{x1:.1f}'
    assert e[2] >= -CLEAR_Z and e[3] <= CLEAR_Z, f'{name}: the path runs z {e[2]:.1f}..{e[3]:.1f}, into the walls (limit {CLEAR_Z})'
    for side in (-1, 1):
        part('Wall', (length, top - BOTTOM, 8), ((x0 + x1) / 2, (top + BOTTOM) / 2, side * (HALF + 4)), colour)
    part('Ceiling', (length + 8, 6, HALF * 2 + 16), ((x0 + x1) / 2, top + 3, 0), colour)
    # the references' walls are huge curved sheets: tall cylinders sunk most of the way into the side walls
    radii = [34, 26, 40, 30, 36]
    n = max(2, int(length // 62))
    for k in range(n):
        cx = x0 + (k + 0.5) * length / n
        for side in (-1, 1):
            r = radii[(k + (0 if side < 0 else 2)) % len(radii)]
            part('Fold', (top - BOTTOM, r * 2, r * 2), (cx + side * 9, (top + BOTTOM) / 2, side * (HALF + r * 0.62)),
                 colour, shape='c', extra={'roll': 90})
    # Measured in Studio (2026-10-03): brightness 1 at 26 studs from the walls blew the room out to white and
    # left hot pools on the folds; 0.2 from two rows near the middle reads as the references' soft gradient.
    # The last level sits just under the ceiling, which was black without it.
    xs = [x0 + 18 + i * light_step for i in range(int((length - 36) // light_step) + 1)]
    for lx in xs:
        for lz in (-14, 14):
            for ly in list(lights_y) + [top - 12]:
                light((lx, ly, lz), 60, 0.2 * light_gain)
    CHECKPOINTS.append({'name': name, 'x0': x0, 'x1': x1, 'entry': [round(v, 2) for v in ENTRY[name]], 'low': round(LOW[name], 2)})


def link(x0, x1, y, z):
    """The pitch-dark corridor between two rooms."""
    length = x1 - x0
    cx = (x0 + x1) / 2
    part('LinkFloor', (length, 3, 9), (cx, y - 1.5, z), 'black')
    part('LinkCeiling', (length, 3, 9), (cx, y + 14.5, z), 'black')
    for side in (-1, 1):
        part('LinkWall', (length, 19, 2), (cx, y + 6.5, z + side * 5.5), 'black')
    ROUTE.append({'x': x0 + 2, 'y': y, 'z': z, 'jump': False, 'sec': 'link'})
    ROUTE.append({'x': x1 - 2, 'y': y, 'z': z, 'jump': False, 'sec': 'link'})


# ---------------------------------------------------------------------------------------------- 1. ROSE
# No jumps at all: a wide ledge, a landing, and one very long staircase that narrows toward a black doorway.
X = 0.0
p = Path_('rose', 'rose', X + 4, 0.0, 0.0)
START = (X + 16, 0.0, 0.0)
p.plat(26, 22).plat(60, 12).plat(20, 24)
sphere(p.x - 12, 0, 7)
p.stairs(56, 2.0, 0.9, 10.0, 5.0)
p.plat(10, 5.5)
rose_end = (p.x, p.y, p.z)
room('rose', 'rose', X, rose_end[0], rose_end[1] + 62, [10, 42, 74])
wall_with_door(X - 4, 'rose', rose_end[1] + 62, 200, -200)                      # solid west wall (door far off the wall)
wall_with_door(rose_end[0] + 4, 'rose', rose_end[1] + 62, rose_end[2], rose_end[1])
link(rose_end[0] + 8, rose_end[0] + 38, rose_end[1], rose_end[2])

# ---------------------------------------------------------------------------------------------- 2. BLUE
# A ledge two bodies wide, three short jumps on the level, then the corridor of doorways inside doorways.
bx = rose_end[0] + 46
Y = rose_end[1]
p = Path_('blue', 'blue', bx, Y, rose_end[2])
p.plat(18, 14).turn(24, 7).plat(44, 7).turn(-24, 7).plat(30, 7)
p.gap(4.0, share=0.52).plat(26, 7)
sphere(p.x - 9, Y, p.z + 1.6)
p.turn(-22, 7).plat(34, 7).gap(4.5, share=0.58).plat(22, 7).turn(22, 7)
p.gap(5.0, share=0.64).plat(20, 7)
p.plat(8, 12)
corridor_x = p.x
for k, (w, h) in enumerate(((30, 34), (22, 26), (16, 19), (11, 14))):                 # nested frames, shrinking
    fx = corridor_x + k * 12
    for side in (-1, 1):
        part('Frame', (12, 60, (HALF * 2 - w) / 2 + 8), (fx + 6, Y + 22, p.z + side * (w / 2 + ((HALF * 2 - w) / 2 + 8) / 2)), 'blue')
    part('Frame', (12, 62 - h, w), (fx + 6, Y + h + (62 - h) / 2 - 8, p.z), 'blue')
p.plat(48, 9)
sphere(p.x - 14, Y, p.z - 2.2)
sphere(p.x - 10, Y, p.z + 1.8, 1.2)
blue_end = (p.x, p.y, p.z)
room('blue', 'blue', bx, blue_end[0], Y + 92, [Y + 10, Y + 44])
wall_with_door(bx - 4, 'blue', Y + 92, rose_end[2], Y)
wall_with_door(blue_end[0] + 4, 'blue', Y + 92, blue_end[2], Y)
orb(blue_end[0] - 1, Y + 19, blue_end[2])
link(blue_end[0] + 8, blue_end[0] + 38, Y, blue_end[2])

# ---------------------------------------------------------------------------------------------- 3. AMBER
# Floating blocks and short beams in a zig-zag. Each jump a little longer; one block sits lower.
ax = blue_end[0] + 46
p = Path_('amber', 'amber', ax, Y, blue_end[2])
p.plat(16, 14)
sphere(p.x - 11, Y, p.z + 4)
sphere(p.x - 8, Y, p.z + 6.2, 1.0)
p.gap(5.0, share=0.64).plat(9, 9)
p.turn(34).gap(5.0, share=0.64).plat(9, 9)
p.gap(5.4, share=0.68).plat(15, 3.4)                                              # a short beam
p.turn(-68).gap(5.4, dy=-3.0, share=0.68).plat(9, 9)                             # the low block
p.gap(5.0, dy=1.5, share=0.68).plat(9, 9)
p.gap(5.0, dy=1.5, share=0.68).plat(9, 9)
p.turn(34).gap(5.7, share=0.70).plat(15, 3.4)
p.gap(5.7, share=0.70).plat(9, 9)
p.turn(-20).gap(5.8, share=0.72).plat(9, 9)
p.turn(20).gap(5.8, share=0.72).plat(18, 12)
amber_end = (p.x, p.y, p.z)
room('amber', 'amber', ax, amber_end[0], Y + 92, [Y + 10, Y + 44])
wall_with_door(ax - 4, 'amber', Y + 92, blue_end[2], Y)
wall_with_door(amber_end[0] + 4, 'amber', Y + 92, amber_end[2], amber_end[1])
orb(amber_end[0] - 1, amber_end[1] + 19, amber_end[2])
link(amber_end[0] + 8, amber_end[0] + 38, amber_end[1], amber_end[2])

# ---------------------------------------------------------------------------------------------- 4. MINT
# Beams one body wide, ramps between heights, and you can see the beams you came from below.
mx = amber_end[0] + 46
BEAM = 2.6
p = Path_('mint', 'mint', mx, amber_end[1], amber_end[2])
p.plat(14, 12)
p.turn(18).ramp(30, 4.0, BEAM)
p.gap(5.5, share=0.70).turn(-36).plat(32, BEAM)
p.gap(5.6, dy=-2.0, share=0.70).ramp(28, -4.0, BEAM)
sphere(p.x - 6, p.y, p.z)
p.turn(40).gap(5.8, share=0.73).ramp(34, 5.0, BEAM)
p.gap(5.4, dy=1.0, share=0.74).turn(-22).plat(30, BEAM)
p.gap(6.0, share=0.75).plat(16, 12)
mint_end = (p.x, p.y, p.z)
for k, (dz, dy, yaw) in enumerate(((-30, -26, 30), (24, -44, -24), (-8, -70, 14), (34, 30, -32))):   # beams that are not the route
    part('Beam', (150, 2.0, BEAM), ((mx + mint_end[0]) / 2, mint_end[1] + dy, dz), 'mint', yaw=yaw, collide=False)
room('mint', 'mint', mx, mint_end[0], Y + 98, [Y + 10, Y + 46])
wall_with_door(mx - 4, 'mint', Y + 98, amber_end[2], amber_end[1])
wall_with_door(mint_end[0] + 4, 'mint', Y + 98, mint_end[2], mint_end[1])
orb(mint_end[0] - 1, mint_end[1] + 19, mint_end[2])
link(mint_end[0] + 8, mint_end[0] + 38, mint_end[1], mint_end[2])

# ---------------------------------------------------------------------------------------------- 5. VIOLET
# The descent: a narrow stair with missing steps going DOWN round a black pit to one lit doorway.
vx = mint_end[0] + 46
p = Path_('violet', 'violet', vx, mint_end[1], mint_end[2])
SPIN = 90 if mint_end[2] < 0 else -90          # the spiral turns toward the middle of the room
p.plat(26, 10)
violet_top = p.y
p.stairs(7, 2.2, -1.0, 4.6, 4.4).plat(5, 4.4)
p.gap(5.6, dy=-2.0, share=0.72).plat(4, 4.4).stairs(6, 2.2, -1.0, 4.4, 4.2)
p.plat(7, 7).turn(SPIN, 7).plat(3, 4.2)
p.stairs(4, 2.2, -1.0, 4.2, 4.0).plat(5, 4.0)
p.gap(6.0, dy=-2.5, share=0.72).plat(4, 4.0).stairs(4, 2.2, -1.0, 4.0, 3.8)
p.plat(7, 7)
sphere(p.x + 2.3, p.y, p.z + 2.3, 0.9)             # in the landing's corner, never in the line you walk
p.turn(SPIN, 7).plat(3, 4.0)
p.stairs(5, 2.2, -1.0, 4.0, 3.8).plat(5, 3.8)
p.gap(6.3, dy=-3.0, share=0.72).plat(4, 3.8).stairs(5, 2.2, -1.0, 3.8, 3.6).plat(5, 3.6)
p.gap(6.3, dy=-3.0, share=0.72).plat(8, 3.6)
p.plat(7, 7).turn(SPIN, 7).plat(3, 3.8)
p.stairs(4, 2.2, -1.0, 3.8, 3.6).plat(5, 3.6)
p.gap(6.5, dy=-3.0, share=0.74).plat(16, 9)
finish = (p.x - 5, p.y, p.z)
for side in (-1, 1):                                                               # the lit doorway at the bottom
    part('ExitFrame', (3, 16, 3), (p.x + 1.5, p.y + 8, p.z + side * 5.5), 'violet')
part('ExitFrame', (3, 3, 14), (p.x + 1.5, p.y + 16.5, p.z), 'violet')
part('ExitDark', (1, 14, 8), (p.x + 2.2, p.y + 7, p.z), 'black')
orb(p.x - 1, p.y + 21, p.z)
violet_x1 = vx + 118
room('violet', 'violet', vx, violet_x1, violet_top + 60, [violet_top + 10, violet_top - 26], light_gain=0.5, light_step=44.0)
wall_with_door(vx - 4, 'violet', violet_top + 60, mint_end[2], mint_end[1])
wall_with_door(violet_x1 + 4, 'violet', violet_top + 60, 200, -200)

OUT.mkdir(parents=True, exist_ok=True)
data = {'origin': [40000, 600, 0], 'colours': COLOURS, 'parts': PARTS, 'lights': LIGHTS, 'route': ROUTE,
        'checkpoints': CHECKPOINTS, 'start': START, 'finish': finish, 'gaps': GAPS,
        'physics': {'walk': WALK, 'jump': JUMP, 'gravity': GRAVITY, 'flat_reach': round(reach(0), 2)}}
(OUT / 'level5.json').write_text(json.dumps(data))
print(f"parts {len(PARTS)}, lights {len(LIGHTS)}, route points {len(ROUTE)}, length {violet_x1:.0f} studs, flat reach {reach(0):.2f}")
for sec in ('blue', 'amber', 'mint', 'violet'):
    g = [x for x in GAPS if x['sec'] == sec]
    print(f"  {sec:7s} {len(g)} jumps, gaps {min(x['gap'] for x in g)}-{max(x['gap'] for x in g)}, hardest {max(x['share'] for x in g):.0%} of reach")


# ---------------------------------------------------------------------------------------------- Blender scene
try:
    import bpy
except ImportError:
    bpy = None
if bpy:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    mats = {}
    for key, rgb in COLOURS.items():
        m = bpy.data.materials.new('L5_' + key)
        m.diffuse_color = (*[(c / 255) ** 2.2 for c in rgb], 1)
        mats[key] = m
    col = bpy.data.collections.new('Level5_Void')
    bpy.context.scene.collection.children.link(col)
    cube = bpy.data.meshes.new('L5Cube')
    import bmesh
    bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0); bm.to_mesh(cube); bm.free()
    ball = bpy.data.meshes.new('L5Ball')
    bm = bmesh.new(); bmesh.ops.create_uvsphere(bm, u_segments=24, v_segments=12, radius=0.5); bm.to_mesh(ball); bm.free()
    tube = bpy.data.meshes.new('L5Cylinder')
    bm = bmesh.new(); bmesh.ops.create_cone(bm, cap_ends=True, segments=40, radius1=0.5, radius2=0.5, depth=1.0); bm.to_mesh(tube); bm.free()
    for i, row in enumerate(PARTS):
        mesh = {'b': cube, 's': ball, 'c': tube}[row['sh']]
        ob = bpy.data.objects.new(f"{row['n']}_{i:03d}", mesh.copy())
        x, y, z = row['p']
        ob.location = (x, -z, y)                                  # Blender is Z-up; the level's z runs across
        sx, sy, sz = row['s']
        if row['sh'] == 'c':
            ob.scale = (sy, sz, sx)                               # a vertical fold: Roblox length = Blender height
        else:
            ob.scale = (sx, sz, sy)
            ob.rotation_euler = (0, -math.radians(row['pitch']), math.radians(row['yaw']) * -1)
        ob.data.materials.append(mats[row['c']])
        col.objects.link(ob)
    for i, row in enumerate(LIGHTS):
        lamp = bpy.data.lights.new(f'L5Lamp_{i:03d}', 'POINT')
        lamp.energy = 4000 * row['b']
        ob = bpy.data.objects.new(lamp.name, lamp)
        ob.location = (row['p'][0], -row['p'][2], row['p'][1])
        col.objects.link(ob)
    blend = OUT.parent / 'blend'
    blend.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(blend / 'Level5_Void.blend'))
    print('saved', blend / 'Level5_Void.blend')
