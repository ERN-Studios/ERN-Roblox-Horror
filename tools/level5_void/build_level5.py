"""Level 5 "the void rooms", v2 (2026-10-04): five single-colour rooms in a row over a black drop, each about
three times as long as v1, harder room by room. Built in Blender; writes artifacts/level5-void-20261003/build/
level5.json (parts, balls, lights, route, checkpoints, plates) and the plaster texture set (colour, normal, roughness).

    /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/level5_void/build_level5.py
    python3 tools/level5_void/build_level5.py            # json only (no .blend, no textures)

NOTHING FLOATS. Every piece you can stand on is the top of a block that goes all the way down into the dark
(`solid`), the lamps' orbs hang from the ceiling on rods, and the loose monoliths rise out of the drop too.
Because the blocks are solid to the bottom, the route never passes under itself: `no_crossing` asserts that no
two pieces of a room overlap in plan.

JUMPS ARE COMPUTED, NOT GUESSED. The body walks at 16 studs/s and jumps with JumpPower 50 under gravity 196.2.
`reach(dy)` is how far that carries to a landing dy studs higher (negative = lower); every gap is asserted to
be at most the room's cap of it (SHARE), and the cap rises room by room. Sprint (26 studs/s in a round body)
only ever makes a gap easier. import_level5.py then walks the whole route in Studio at walking speed.
"""
import json, math, random
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
OUT = ROOT / 'artifacts' / 'level5-void-20261003' / 'build'
WALK, JUMP, GRAVITY = 16.0, 50.0, 196.2
BOTTOM = -420.0            # everything goes this far down; nothing below the paths is lit
HALF = 70.0                # rooms are 140 wide inside
CLEAR_Z = 50.0             # the folds' faces start at about 55; a path's centre line keeps this side of them
SHARE = {'rose': 0.50, 'blue': 0.64, 'amber': 0.74, 'mint': 0.80, 'violet': 0.86, 'coral': 0.88}
COLOURS = {
    'rose': (224, 150, 200), 'blue': (92, 150, 200), 'amber': (228, 180, 88),
    'mint': (150, 216, 182), 'violet': (164, 134, 214), 'coral': (236, 118, 102), 'black': (4, 4, 5),
    'sphere': (26, 38, 120), 'orb': (255, 255, 250), 'plate': (236, 236, 230),
}
PARTS, BALLS, LIGHTS, ROUTE, CHECKPOINTS, GAPS, PLATES, FOOT = [], [], [], [], [], [], [], []
EXTENT = {}        # section -> [min x, max x, min z, max z, min y, max y] of its walkable pieces
random.seed(505)


def reach(dy):
    disc = JUMP * JUMP - 2 * GRAVITY * dy
    assert disc > 0, f'a rise of {dy} is above the jump apex'
    return WALK * (JUMP + math.sqrt(disc)) / GRAVITY


def part(name, size, pos, colour, yaw=0.0, shape='b', collide=True, material='Plaster', extra=None):
    row = {'n': name, 's': [round(v, 3) for v in size], 'p': [round(v, 3) for v in pos], 'c': colour,
           'yaw': round(yaw, 3), 'sh': shape, 'col': collide, 'm': material}
    if extra:
        row.update(extra)
    PARTS.append(row)


def solid(name, length, width, top, cx, cz, yaw, colour, bottom=BOTTOM):
    """A block whose top face is the surface and whose body runs down into the dark."""
    part(name, (length, top - bottom, width), (cx, (top + bottom) / 2, cz), colour, yaw=yaw)


def light(pos, rng=60, brightness=0.2):
    LIGHTS.append({'p': [round(v, 2) for v in pos], 'r': rng, 'b': round(brightness, 3)})


def corners(f, grow=0.0):
    c, s = math.cos(math.radians(f['yaw'])), math.sin(math.radians(f['yaw']))
    hl, hw = f['l'] / 2 + grow, f['w'] / 2 + grow
    return [(f['x'] + c * a - s * b, f['z'] + s * a + c * b) for a, b in ((hl, hw), (hl, -hw), (-hl, -hw), (-hl, hw))]


def overlap(a, b, grow=0.0):
    """Separating axes for two rectangles in plan."""
    pa, pb = corners(a, grow), corners(b)
    for poly in (pa, pb):
        for i in range(2):
            ex, ez = poly[i + 1][0] - poly[i][0], poly[i + 1][1] - poly[i][1]
            nx, nz = -ez, ex
            da = [nx * x + nz * z for x, z in pa]
            db = [nx * x + nz * z for x, z in pb]
            if max(da) < min(db) - 1e-6 or max(db) < min(da) - 1e-6:
                return False
    return True


class Path_:
    """A cursor that lays walkable pieces end to end. x runs along the level, z across it, y is the walking surface."""
    def __init__(self, section, x, y, z, heading=0.0):
        self.section, self.colour = section, section
        self.x, self.y, self.z, self.h = x, y, z, heading
        self.jump_next = False
        self.order = 0
        self.mirror = 1          # -1 lays the same room mirrored, to keep a drifting route off the walls

    def dir(self):
        r = math.radians(self.h)
        return math.cos(r), math.sin(r)

    def point(self, along=0.0, side=0.0):
        dx, dz = self.dir()
        return self.x + dx * along - dz * side, self.y, self.z + dz * along + dx * side

    def way(self, along, jump=False, **flags):
        x, y, z = self.point(along)
        e = EXTENT.setdefault(self.section, [x, x, z, z, y, y])
        e[0], e[1], e[2], e[3], e[4], e[5] = min(e[0], x), max(e[1], x), min(e[2], z), max(e[3], z), min(e[4], y), max(e[5], y)
        ROUTE.append({'x': round(x, 2), 'y': round(y, 2), 'z': round(z, 2), 'jump': jump, 'sec': self.section, **flags})

    def foot(self, length, width, cx, cz):
        self.order += 1
        FOOT.append({'sec': self.section, 'i': self.order, 'x': cx, 'z': cz, 'l': length, 'w': width, 'yaw': self.h, 'top': self.y})

    def plat(self, length, width, name='Walk'):
        dx, dz = self.dir()
        cx, cz = self.x + dx * length / 2, self.z + dz * length / 2
        solid(name, length, width, self.y, cx, cz, self.h, self.colour)
        self.foot(length, width, cx, cz)
        self.way(min(2.0, length / 2), jump=self.jump_next)
        self.jump_next = False
        self.x, self.z = self.x + dx * length, self.z + dz * length
        self.way(-0.9)
        return self

    def rest(self, length, width):
        """A wide landing: a checkpoint (a fall puts you back here) with a lamp hanging over it."""
        cx, cy, cz = self.point(length / 2)
        CHECKPOINTS.append({'sec': self.section, 'x': round(cx, 2), 'y': round(cy, 2), 'z': round(cz, 2), 'at': len(ROUTE)})
        orb(cx, cy + 20, cz, self.section)
        return self.plat(length, width, 'Rest')

    def turn(self, degrees, width=None):
        if width:
            solid('Walk', width, width, self.y, self.x, self.z, self.h, self.colour)
        self.h += degrees * self.mirror
        return self

    def corner(self, degrees, width):
        """A square landing where the route turns: a checkpoint with a lamp over it."""
        CHECKPOINTS.append({'sec': self.section, 'x': round(self.x, 2), 'y': round(self.y, 2), 'z': round(self.z, 2), 'at': len(ROUTE)})
        orb(self.x, self.y + 20, self.z, self.section)
        return self.turn(degrees, width)

    def gap(self, distance, dy=0.0):
        limit, cap = reach(dy), SHARE[self.section]
        assert distance <= limit * cap + 1e-6, \
            f'{self.section}: gap {distance} with dy {dy} is {distance / limit:.0%} of the {limit:.2f} reach (cap {cap:.0%})'
        GAPS.append({'sec': self.section, 'gap': distance, 'dy': dy, 'reach': round(limit, 2), 'share': round(distance / limit, 3)})
        dx, dz = self.dir()
        self.x, self.z, self.y = self.x + dx * distance, self.z + dz * distance, self.y + dy
        self.jump_next = True
        return self

    def stairs(self, steps, run, rise, w0, w1):
        """Never the take-off for a jump when it descends: the body is airborne half the way down a stair."""
        dx, dz = self.dir()
        self.way(0.5, jump=self.jump_next)
        self.jump_next = False
        x0, z0 = self.x, self.z
        for i in range(steps):
            width = w0 + (w1 - w0) * i / max(1, steps - 1)
            self.y += rise
            cx, cz = self.x + dx * run / 2, self.z + dz * run / 2
            solid('Step', run, width, self.y, cx, cz, self.h, self.colour)
            self.x, self.z = self.x + dx * run, self.z + dz * run
            if i % 6 == 5:
                self.way(-run / 2)
        self.order += 1
        FOOT.append({'sec': self.section, 'i': self.order, 'x': (x0 + self.x) / 2, 'z': (z0 + self.z) / 2,
                     'l': steps * run, 'w': max(w0, w1), 'yaw': self.h, 'top': self.y})
        self.way(-0.5)
        return self

    def ball(self, back, side, r=1.4):
        """A loose ball on the piece just laid, `back` studs behind the cursor and `side` studs off its centre line."""
        x, y, z = self.point(-back, side)
        BALLS.append({'p': [round(x, 2), round(y + r + 0.05, 2), round(z, 2)], 'r': r})
        return self

    def home(self, width, target=0.0, angle=30.0):
        """Walk back to the middle of the room: a diagonal ledge that undoes whatever the zig-zag drifted."""
        assert abs(self.h % 360) < 1e-6
        off = target - self.z
        if abs(off) < 3:
            return self
        sign = 1 if off > 0 else -1
        self.h += sign * angle
        solid('Walk', width, width, self.y, self.x, self.z, self.h, self.colour)
        self.plat(abs(off) / math.sin(math.radians(angle)), width)
        solid('Walk', width, width, self.y, self.x, self.z, self.h, self.colour)
        self.h -= sign * angle
        return self

    def plaza(self, last=False):
        """The end of a room: a wide floor, the plate every player in the room has to stand on, and the gated door."""
        assert abs(self.h % 360) < 1e-6, f'{self.section}: the room has to end heading straight on (heading {self.h})'
        cx, cy, cz = self.point(17)
        CHECKPOINTS.append({'sec': self.section, 'x': round(cx - 9, 2), 'y': round(cy, 2), 'z': round(cz, 2), 'at': len(ROUTE)})
        self.plat(12, 30, 'Rest')
        ROUTE.pop()                                               # no pause at a seam inside the plaza
        if not last:
            self.way(5.0, plate=self.section)
            PLATES.append({'sec': self.section, 'x': round(cx, 2), 'y': round(cy, 2), 'z': round(cz, 2)})
        self.plat(24, 30, 'Rest')
        orb(cx, cy + 22, cz, self.section)
        return self


def orb(x, y, z, colour):
    """The lamp: a white ball on a rod from the ceiling (the rod's top is set by `room`, which knows the ceiling)."""
    part('Orb', (5, 5, 5), (x, y, z), 'orb', shape='s', collide=False, material='Neon', extra={'light': [46, 2.6], 'rod': colour})


def wall_with_door(x, colour, top, door_z, door_y, thick=8.0, door_w=9.0, door_h=13.0):
    """An end wall (constant x) with a doorway at walking height door_y, centred on door_z."""
    def slab(z0, z1, y0, y1):
        z0, z1 = max(z0, -HALF - 8), min(z1, HALF + 8)
        if z1 - z0 > 0.05 and y1 - y0 > 0.05:
            part('Wall', (thick, y1 - y0, z1 - z0), (x, (y0 + y1) / 2, (z0 + z1) / 2), colour)
    slab(-HALF - 8, door_z - door_w / 2, BOTTOM, top)
    slab(door_z + door_w / 2, HALF + 8, BOTTOM, top)
    slab(door_z - door_w / 2, door_z + door_w / 2, door_y + door_h, top)
    slab(door_z - door_w / 2, door_z + door_w / 2, BOTTOM, door_y)        # the sill is the floor of the doorway


def no_crossing(name):
    feet = [f for f in FOOT if f['sec'] == name]
    for a in feet:
        for b in feet:
            if b['i'] - a['i'] > 3 and overlap(a, b, 1.5):
                raise AssertionError(f"{name}: piece {a['i']} and piece {b['i']} overlap in plan, so one would stand in the other's block")


def route_y(name, x):
    pts = [r for r in ROUTE if r['sec'] == name]
    return min(pts, key=lambda r: abs(r['x'] - x))['y']


def room(name, x0, x1, monoliths=True, shaft=False):
    e = EXTENT[name]
    print(f'    {name}: z {e[2]:.1f}..{e[3]:.1f}, ends at z {ROUTE[-1]["z"]:.1f}')
    assert e[0] >= x0 - 0.01 and e[1] <= x1 + 0.01, f'{name}: the path runs x {e[0]:.1f}..{e[1]:.1f}, outside the room {x0:.1f}..{x1:.1f}'
    limit = HALF - 2 if shaft else CLEAR_Z                 # a shaft's stair runs along the walls themselves
    assert e[2] >= -limit and e[3] <= limit, f'{name}: the path runs z {e[2]:.1f}..{e[3]:.1f}, into the walls (limit {limit})'
    no_crossing(name)
    length, top = x1 - x0, e[5] + 64
    for side in (-1, 1):
        part('Wall', (length, top - BOTTOM, 8), ((x0 + x1) / 2, (top + BOTTOM) / 2, side * (HALF + 4)), name)
    part('Ceiling', (length + 8, 6, HALF * 2 + 16), ((x0 + x1) / 2, top + 3, 0), name)
    # the references' walls are huge curved sheets: tall cylinders sunk most of the way into the side walls
    radii = [34, 26, 40, 30, 36]
    n = 0 if shaft else max(2, int(length // 62))
    for k in range(n):
        cx = x0 + (k + 0.5) * length / n
        for side in (-1, 1):
            r = radii[(k + (0 if side < 0 else 2)) % len(radii)]
            part('Fold', (top - BOTTOM, r * 2, r * 2), (cx + side * 9, (top + BOTTOM) / 2, side * (HALF + r * 0.62)),
                 name, shape='c', extra={'roll': 90})
    # loose monoliths standing in the drop: they give the dark a scale and are never on the route
    feet = [f for f in FOOT if f['sec'] == name]
    made, tries = 0, 0
    while monoliths and not shaft and made < int(length // 34) and tries < 4000:
        tries += 1
        w, d = random.choice((6, 8, 10, 14, 18)), random.choice((6, 8, 10, 14))
        m = {'x': random.uniform(x0 + 14, x1 - 14), 'z': random.uniform(-HALF + 20, HALF - 20), 'l': w, 'w': d,
             'yaw': random.choice((0, 0, 12, -18, 30, 45))}
        if any(overlap(m, f, 7.0) for f in feet):
            continue
        feet.append(m)
        base = route_y(name, m['x'])
        solid('Monolith', w, d, base + random.choice((-74, -52, -38, -24, -16, 9, 20, 34)), m['x'], m['z'], m['yaw'], name)
        made += 1
    # Measured in Studio (2026-10-03): brightness 1 at 26 studs from the walls blew the room out to white;
    # 0.2 from two rows near the middle reads as the references' soft gradient. The rows follow the route's
    # height, and a last row sits just under the ceiling, which is black without it.
    if shaft:
        # lamps follow the stair round the walls, a little toward the middle; the middle itself stays black
        pts = [r for r in ROUTE if r['sec'] == name]
        mid, walked = (x0 + x1) / 2, 0.0
        for a, b in zip(pts, pts[1:]):
            walked += math.hypot(b['x'] - a['x'], b['z'] - a['z'])
            if walked >= 26:
                walked = 0.0
                dx, dz = mid - b['x'], -b['z']
                d = math.hypot(dx, dz) or 1.0
                light((b['x'] + dx / d * 12, b['y'] + 10, b['z'] + dz / d * 12))
                light((b['x'] + dx / d * 12, b['y'] + 36, b['z'] + dz / d * 12))
    for i in range(0 if shaft else int((length - 36) // 34) + 1):
        lx = x0 + 18 + i * 34
        y = route_y(name, lx)
        for lz in (-18, 18):
            for ly in (y + 10, y + 44):
                if ly < top - 16:
                    light((lx, ly, lz))
            light((lx, top - 12, lz))
    for row in PARTS:                                             # hang this room's lamps from its ceiling
        if row.get('rod') == name:
            x, y, z = row['p']
            part('OrbRod', (0.35, top - y - 2.2, 0.35), (x, (top + y + 2.2) / 2, z), 'black', collide=False, material='Metal')
            row['rod'] = True
    return top


def link(x0, x1, y, z, sec):
    """The pitch-dark corridor between two rooms."""
    length, cx = x1 - x0, (x0 + x1) / 2
    solid('LinkFloor', length, 9, y, cx, z, 0, 'black')
    part('LinkCeiling', (length, 3, 9), (cx, y + 14.5, z), 'black')
    for side in (-1, 1):
        part('LinkWall', (length, 19, 2), (cx, y + 6.5, z + side * 5.5), 'black')
    ROUTE.append({'x': x0 + 2, 'y': y, 'z': z, 'jump': False, 'sec': sec, 'gate': sec})
    ROUTE.append({'x': x1 - 2, 'y': y, 'z': z, 'jump': False, 'sec': sec})


def close(p, x0, last=False, x1=None, shaft=False):
    """Walls, ceiling, lamps and the two end walls for the room `p` has just finished; returns where the next starts."""
    name = p.section
    x1 = p.x if x1 is None else x1
    top = room(name, x0, x1, shaft=shaft)
    wall_with_door(x1 + 4, name, top, p.z if not last else 300, p.y if not last else -200)
    if last:
        return None
    for row in PLATES:
        if row['sec'] == name:
            row['gate'] = [round(x1 + 4, 2), round(p.y, 2), round(p.z, 2)]
    link(x1 + 8, x1 + 38, p.y, p.z, name)
    return x1 + 46, p.y, p.z, top


def open_room(name, start, mirror=1):
    x, y, z = start
    p = Path_(name, x, y, z)
    p.x0, p.mirror = x, mirror
    return p


# ---------------------------------------------------------------------------------------------- 1. ROSE
# Learning the body: wide ledges, a long climb, and six jumps you can clear from a standstill walk (<= 50%).
p = open_room('rose', (4.0, 0.0, 0.0))
START = (16.0, 0.0, 0.0)
p.rest(30, 26).ball(9, 8).ball(15, -9, 1.9).ball(6, -5, 1.0)
p.plat(70, 12).ball(30, 3.5)
p.turn(20, 12).plat(52, 9).turn(-40, 9).plat(62, 8).turn(20, 8).plat(10, 8)
p.gap(3.0).plat(24, 8)
p.gap(3.4).plat(20, 8)
p.stairs(30, 2.0, 0.9, 9.0, 7.0)
p.rest(22, 20).ball(8, 6, 1.6).ball(12, -6)
p.plat(40, 7).turn(-25, 7).plat(46, 6.5)
p.gap(3.8).plat(30, 6.5).turn(50, 7).plat(52, 6).turn(-25, 7).plat(8, 6)
p.gap(4.0).plat(18, 6)
p.stairs(26, 2.0, 0.9, 8.0, 6.0)
p.rest(20, 18).ball(9, 5, 1.2)
p.plat(40, 6)
p.gap(4.0).plat(26, 6)
p.gap(4.0).plat(22, 6)
p.plaza().ball(8, 10, 2.2).ball(14, -11, 1.3)
wall_with_door(p.x0 - 8, 'rose', EXTENT['rose'][5] + 64, 300, -200)                # the solid west wall
nxt = close(p, p.x0 - 4)

# ---------------------------------------------------------------------------------------------- 2. BLUE
# Ledges two bodies wide, then one and a half; ten jumps on the level (<= 64%); the corridor of doorways in doorways.
p = open_room('blue', nxt[:3], mirror=-1)
Y = p.y
blue_in = (p.z, p.y)
p.rest(24, 20).ball(8, 6)
p.turn(24, 7).plat(46, 7).turn(-24, 7).plat(30, 7)
p.gap(4.2).plat(26, 7)
p.turn(-22, 7).plat(36, 6.5)
p.gap(4.5).plat(22, 6.5).turn(22, 7).plat(8, 6.5)
p.gap(4.8).plat(22, 6)
for g, w in ((4.6, 8), (4.8, 8), (5.0, 7), (5.0, 7)):                                 # a row of stepping blocks
    p.gap(g).plat(w, w)
p.gap(5.0).plat(14, 6)
p.rest(22, 18).ball(9, -5, 1.8).ball(13, 6, 1.1)
corridor_x = p.x
for k, (w, h) in enumerate(((34, 36), (26, 28), (18, 20), (12, 14))):                # nested frames, shrinking
    fx = corridor_x + k * 14
    side_w = HALF - w / 2 + 8
    for side in (-1, 1):
        part('Frame', (12, Y + 72 - BOTTOM, side_w), (fx + 6, (Y + 72 + BOTTOM) / 2, p.z + side * (w / 2 + side_w / 2)), 'blue')
    part('Frame', (12, 72 - h, w), (fx + 6, Y + h + (72 - h) / 2, p.z), 'blue')
p.plat(58, 8).ball(20, -2.2).ball(14, 1.8, 1.2)
p.turn(-20, 8).plat(40, 5.5)
p.gap(5.0).plat(24, 5.5).turn(40, 6).plat(44, 5.5).turn(-20, 6).plat(8, 5.5)
p.gap(5.2).plat(20, 5.5)
p.gap(5.2).plat(18, 5.5)
p.plaza().ball(10, -10, 2.0).ball(6, 11)
nxt = close(p, p.x0 - 4)
wall_with_door(p.x0 - 4, 'blue', nxt[3], blue_in[0], blue_in[1])

# ---------------------------------------------------------------------------------------------- 3. AMBER
# Blocks and short beams in a zig-zag, each jump a little longer (<= 74%), heights that step up and down.
p = open_room('amber', nxt[:3], mirror=-1)
amber_in = (p.z, p.y)
p.rest(20, 18).ball(8, 5).ball(11, -6, 1.0)
p.gap(5.0).plat(9, 9)
p.turn(34).gap(5.0).plat(9, 9)
p.gap(5.4).plat(16, 3.6)                                                           # a short beam
p.turn(-68).gap(5.4, dy=-3.0).plat(9, 9)                                           # the low block
p.gap(5.2, dy=1.5).plat(9, 9)
p.gap(5.2, dy=1.5).plat(9, 9)
p.turn(34).gap(5.7).plat(16, 3.4)
p.gap(5.7).plat(8, 8)
p.turn(-20).gap(5.8).plat(8, 8)
p.turn(20).gap(5.8).plat(10, 8)
p.rest(20, 16).ball(8, 4, 1.5)
p.turn(-30).gap(5.4, dy=2.0).plat(7, 7)
p.gap(5.4, dy=2.0).plat(7, 7)
p.turn(60).gap(5.8).plat(18, 3.2)
p.gap(6.0).plat(7, 7)
p.gap(6.0, dy=-2.5).plat(7, 7)
p.turn(-60).gap(6.0).plat(18, 3.2)
p.gap(6.0).plat(6, 6)
p.turn(30).gap(6.0, dy=-1.5).plat(6, 6)
p.gap(6.0).plat(10, 6)
p.rest(18, 14).ball(7, -4, 1.2)
p.turn(26).gap(6.0).plat(6, 6)
p.gap(5.5, dy=2.0).plat(6, 6)
p.turn(-52).gap(6.0).plat(20, 3.0)
p.gap(6.0).plat(6, 6)
p.turn(26).gap(6.0).plat(6, 6)
p.gap(6.0).plat(10, 6)
p.plaza().ball(9, 10, 1.8)
nxt = close(p, p.x0 - 4)
wall_with_door(p.x0 - 4, 'amber', nxt[3], amber_in[0], amber_in[1])

# ---------------------------------------------------------------------------------------------- 4. MINT
# Beams one body wide, climbs between them, small landings (<= 80%).
BEAM = 2.4
p = open_room('mint', nxt[:3], mirror=-1)
mint_in = (p.z, p.y)
p.rest(18, 16).ball(7, 4)
p.turn(18).plat(34, BEAM)
p.gap(5.8).turn(-36).plat(30, BEAM).stairs(5, 2.0, 0.9, BEAM, BEAM).plat(6, BEAM)
p.gap(6.0, dy=-2.0).plat(28, BEAM)
p.turn(40).gap(6.2).plat(5, 5)
p.gap(6.2).plat(26, BEAM).stairs(6, 2.0, 0.9, BEAM, BEAM).plat(5, BEAM)
p.gap(5.8, dy=1.0).turn(-22).plat(30, BEAM)
p.gap(6.4).plat(10, 6)
p.rest(18, 14).ball(8, 4, 1.3)
p.turn(-28).gap(6.4).plat(5, 5)
p.gap(6.4).plat(5, 5)
p.turn(56).gap(6.4, dy=-2.0).plat(30, BEAM)
p.gap(6.5).plat(4.5, 4.5)
p.gap(6.1, dy=1.5).plat(4.5, 4.5)
p.turn(-56).gap(6.5).plat(32, BEAM).stairs(5, 2.0, 0.9, BEAM, BEAM).plat(5, BEAM)
p.turn(28).gap(6.5).plat(5, 5)
p.gap(6.5).plat(10, 6)
p.rest(16, 12)
p.turn(22).gap(6.5).plat(28, BEAM)
p.gap(6.5, dy=-1.5).plat(4.5, 4.5)
p.turn(-44).gap(6.5).plat(4.5, 4.5)
p.gap(6.1, dy=1.5).plat(30, BEAM)
p.turn(22).gap(6.5).plat(4.5, 4.5)
p.gap(6.5).plat(10, 6)
p.plaza().ball(8, -10, 1.6)
nxt = close(p, p.x0 - 4)
wall_with_door(p.x0 - 4, 'mint', nxt[3], mint_in[0], mint_in[1])

# ---------------------------------------------------------------------------------------------- 5. VIOLET
# The descent: narrow stairs with missing steps going DOWN in long switchbacks to one lit doorway (<= 86%).
# Every gap leaves from a flat tread and lands on one.
p = open_room('violet', nxt[:3])
violet_in = (p.z, p.y)
p.rest(22, 14)
p.stairs(7, 2.2, -1.0, 4.6, 4.4).plat(5, 4.4)
p.gap(6.6, dy=-2.0).plat(4.5, 4.4).stairs(6, 2.2, -1.0, 4.4, 4.2).plat(5, 4.2)
p.turn(30).gap(6.8, dy=-2.5).plat(4.5, 4.2).stairs(5, 2.2, -1.0, 4.2, 4.0).plat(5, 4.0)
p.gap(7.0, dy=-3.0).plat(4.5, 4.0)
p.turn(-60).gap(6.6).plat(4.5, 4.0).stairs(5, 2.2, -1.0, 4.0, 3.8).plat(5, 3.8)
p.gap(7.0, dy=-3.0).plat(4.5, 3.8)
p.turn(30).gap(6.8).plat(10, 6)
p.rest(16, 12)
p.turn(-28).gap(6.4, dy=1.0).plat(4, 4)
p.gap(7.0, dy=-2.0).plat(4, 4).stairs(6, 2.2, -1.0, 3.8, 3.6).plat(5, 3.6)
p.turn(56).gap(7.2, dy=-3.0).plat(4, 4)
p.gap(6.9).plat(4, 4)
p.gap(7.2, dy=-3.0).plat(4, 3.6).stairs(5, 2.2, -1.0, 3.6, 3.4).plat(5, 3.4)
p.turn(-56).gap(7.0, dy=-1.0).plat(4, 4)
p.turn(28).gap(7.0).plat(10, 6)
p.rest(16, 12)
p.turn(24).gap(7.0, dy=-2.0).plat(3.6, 3.6)
p.gap(7.0, dy=-2.0).plat(3.6, 3.6)
p.turn(-48).gap(7.0).plat(3.6, 3.6).stairs(6, 2.2, -1.0, 3.4, 3.2).plat(5, 3.2)
p.gap(7.4, dy=-3.0).plat(3.6, 3.6)
p.gap(7.0).plat(3.6, 3.6)
p.turn(24).gap(7.4, dy=-3.0).plat(10, 6)
p.plaza()
nxt = close(p, p.x0 - 4)
wall_with_door(p.x0 - 4, 'violet', nxt[3], violet_in[0], violet_in[1])

# ---------------------------------------------------------------------------------------------- 6. CORAL
# The shaft: a square well with nothing in the middle, and the stair goes UP round its four walls, once
# round, with a missing piece in every stretch (<= 88%, most of them with a rise). Every gap leaves from a
# flat tread and lands on one. The lit doorway is at the top, above the door you came in by.
cx0, cy0, cz0 = nxt[:3]
SHAFT = 140.0
p = Path_('coral', cx0 + 3.0, cy0, cz0 - 5.0, heading=90.0)          # along the west wall, toward +z
p.x0 = cx0
coral_in = (cz0, cy0)
p.rest(10, 6)
GAPS_UP = [(6.4, 0.0), (6.0, 1.0), (6.7, 0.0), (6.2, 1.5), (6.9, 0.0), (6.4, 1.0), (7.0, 0.0), (6.4, 2.0),
           (7.1, 0.0), (6.6, 1.5), (7.1, 0.0), (6.5, 2.0), (7.15, 0.0), (6.8, 1.0), (7.15, 0.0), (6.5, 2.0)]
unit = 0

def climb(length, width):
    """Fill one wall's stretch: steps up, a flat tread, a gap, a flat tread, again, and a flat run to the corner."""
    global unit
    left = length
    while left > 34 and unit < len(GAPS_UP):
        g, dy = GAPS_UP[unit]
        unit += 1
        p.stairs(6, 2.0, 0.9, width, width).plat(4.5, width).gap(g, dy).plat(4.0, width)
        left -= 12 + 4.5 + g + 4.0
    steps = int((left - 6) // 2)
    p.stairs(steps, 2.0, 0.9, width, width)
    p.plat(left - steps * 2, width)

climb(HALF - 3 - p.z, 5.0)                       # west wall to the north-west corner
p.corner(-90, 6)
climb(SHAFT - 6, 4.6)                            # north wall
p.corner(-90, 6)
climb(SHAFT - 6, 4.2)                            # east wall
p.corner(-90, 6)
climb(SHAFT - 6, 3.8)                            # south wall
p.corner(-90, 6)
climb((coral_in[0] - 22) - p.z, 3.6)             # west wall again, stopping short of the stretch it began on
p.rest(12, 6)
finish = (p.x, p.y, p.z - 6)
for side in (-1, 1):                                                               # the lit doorway at the top
    part('ExitFrame', (3, 16, 3), (cx0 + 1.5, p.y + 8, p.z - 6 + side * 5.5), 'coral')
part('ExitFrame', (3, 3, 14), (cx0 + 1.5, p.y + 16.5, p.z - 6), 'coral')
part('ExitDark', (1, 14, 8), (cx0 + 0.6, p.y + 7, p.z - 6), 'black')
orb(cx0 + 5, p.y + 21, p.z - 6, 'coral')
close(p, cx0, last=True, x1=cx0 + SHAFT, shaft=True)
wall_with_door(cx0 - 4, 'coral', EXTENT['coral'][5] + 64, coral_in[0], coral_in[1])
TOTAL = cx0 + SHAFT

# a fall is judged against the lowest walking height between a checkpoint and the next one
for i, cp in enumerate(CHECKPOINTS):
    end = CHECKPOINTS[i + 1]['at'] + 2 if i + 1 < len(CHECKPOINTS) else len(ROUTE)
    cp['low'] = round(min(r['y'] for r in ROUTE[cp['at']:end]), 2)
    cp['i'] = i

OUT.mkdir(parents=True, exist_ok=True)
data = {'origin': [40000, 600, 0], 'colours': COLOURS, 'parts': PARTS, 'balls': BALLS, 'lights': LIGHTS, 'route': ROUTE,
        'checkpoints': CHECKPOINTS, 'plates': PLATES, 'start': START, 'finish': finish, 'gaps': GAPS,
        'sections': ['rose', 'blue', 'amber', 'mint', 'violet', 'coral'],
        'physics': {'walk': WALK, 'jump': JUMP, 'gravity': GRAVITY, 'flat_reach': round(reach(0), 2)}}
(OUT / 'level5.json').write_text(json.dumps(data))
print(f"parts {len(PARTS)}, balls {len(BALLS)}, lights {len(LIGHTS)}, route points {len(ROUTE)}, checkpoints {len(CHECKPOINTS)}, "
      f"length {TOTAL:.0f} studs, flat reach {reach(0):.2f}")
for sec in data['sections']:
    g = [x for x in GAPS if x['sec'] == sec]
    e = EXTENT[sec]
    print(f"  {sec:7s} x {e[0]:6.0f}..{e[1]:6.0f} ({e[1] - e[0]:4.0f} long)  z {e[2]:5.1f}..{e[3]:5.1f}  y {e[4]:6.1f}..{e[5]:6.1f}  "
          f"{len(g):2d} jumps, gaps {min(x['gap'] for x in g)}-{max(x['gap'] for x in g)}, hardest {max(x['share'] for x in g):.0%} of reach")


# ---------------------------------------------------------------------------------------------- Blender scene
try:
    import bpy
except ImportError:
    bpy = None
if bpy:
    import bmesh
    import numpy as np

    # The plaster: a tileable height field (broad trowel lumps + grain + a few pits), from which the normal,
    # the roughness and a near-white colour map are derived. Roblox tints the colour map with each part's Color,
    # so one set serves all five rooms.
    N = 1024
    rng = np.random.default_rng(55)
    fx = np.fft.fftfreq(N)[:, None]
    fy = np.fft.fftfreq(N)[None, :]
    radius = np.sqrt(fx * fx + fy * fy)

    def band(lo, hi):
        spectrum = np.fft.fft2(rng.standard_normal((N, N))) * ((radius >= lo) & (radius < hi))
        field = np.real(np.fft.ifft2(spectrum))
        return field / np.abs(field).max()

    lumps, trowel, grain = band(0.002, 0.012), band(0.012, 0.05), band(0.08, 0.32)
    pits = np.clip(band(0.03, 0.09) - 0.55, 0, None) * 2.2
    height = 0.55 * lumps + 0.30 * trowel + 0.10 * grain - 0.45 * pits
    height = (height - height.min()) / (height.max() - height.min())
    strength = 2.0
    gx = (np.roll(height, -1, 1) - np.roll(height, 1, 1)) * strength * N / 256
    gy = (np.roll(height, -1, 0) - np.roll(height, 1, 0)) * strength * N / 256
    inv = 1.0 / np.sqrt(gx * gx + gy * gy + 1.0)
    normal = np.stack([-gx * inv * 0.5 + 0.5, -gy * inv * 0.5 + 0.5, inv * 0.5 + 0.5, np.ones_like(inv)], -1)
    shade = 0.90 + 0.10 * height - 0.10 * np.clip(pits, 0, 1)
    colour = np.stack([shade, shade, shade, np.ones_like(shade)], -1)
    rough_v = np.clip(0.80 + 0.14 * grain * 0.5 + 0.10 * (1 - height), 0, 1)
    rough = np.stack([rough_v, rough_v, rough_v, np.ones_like(rough_v)], -1)
    tex = OUT.parent / 'textures'
    tex.mkdir(parents=True, exist_ok=True)
    images = {}
    for key, pixels, space in (('colour', colour, 'sRGB'), ('normal', normal, 'Non-Color'), ('roughness', rough, 'Non-Color')):
        img = bpy.data.images.new(f'l5_plaster_{key}', N, N, alpha=False)
        img.colorspace_settings.name = space
        img.pixels.foreach_set(pixels.astype(np.float32).ravel())
        img.filepath_raw = str(tex / f'l5_plaster_{key}.png')
        img.file_format = 'PNG'
        img.save()
        images[key] = img

    bpy.ops.wm.read_factory_settings(use_empty=True)
    for key in ('colour', 'normal', 'roughness'):
        images[key] = bpy.data.images.load(str(tex / f'l5_plaster_{key}.png'))
        images[key].colorspace_settings.name = 'sRGB' if key == 'colour' else 'Non-Color'
    mats = {}
    for key, rgb in COLOURS.items():
        m = bpy.data.materials.new('L5_' + key)
        tint = (*[(c / 255) ** 2.2 for c in rgb], 1)
        m.diffuse_color = tint
        m.use_nodes = True
        nodes, links = m.node_tree.nodes, m.node_tree.links
        bsdf = next(n for n in nodes if n.type == 'BSDF_PRINCIPLED')
        if key in ('orb',):
            bsdf.inputs['Base Color'].default_value = tint
        else:
            coord = nodes.new('ShaderNodeTexCoord')
            scale = nodes.new('ShaderNodeMapping')
            scale.inputs['Scale'].default_value = (0.08, 0.08, 0.08)       # one tile is about 12 studs
            links.new(coord.outputs['Object'], scale.inputs['Vector'])
            def image(name):
                node = nodes.new('ShaderNodeTexImage')
                node.image, node.projection = images[name], 'BOX'
                node.projection_blend = 0.2
                links.new(scale.outputs['Vector'], node.inputs['Vector'])
                return node
            mix = nodes.new('ShaderNodeMixRGB')
            mix.blend_type = 'MULTIPLY'
            mix.inputs['Fac'].default_value = 1.0
            mix.inputs['Color2'].default_value = tint
            links.new(image('colour').outputs['Color'], mix.inputs['Color1'])
            links.new(mix.outputs['Color'], bsdf.inputs['Base Color'])
            links.new(image('roughness').outputs['Color'], bsdf.inputs['Roughness'])
            bump = nodes.new('ShaderNodeNormalMap')
            links.new(image('normal').outputs['Color'], bump.inputs['Color'])
            links.new(bump.outputs['Normal'], bsdf.inputs['Normal'])
        mats[key] = m
    col = bpy.data.collections.new('Level5_Void')
    bpy.context.scene.collection.children.link(col)
    cube = bpy.data.meshes.new('L5Cube')
    bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0); bm.to_mesh(cube); bm.free()
    ball = bpy.data.meshes.new('L5Ball')
    bm = bmesh.new(); bmesh.ops.create_uvsphere(bm, u_segments=24, v_segments=12, radius=0.5); bm.to_mesh(ball); bm.free()
    tube = bpy.data.meshes.new('L5Cylinder')
    bm = bmesh.new(); bmesh.ops.create_cone(bm, cap_ends=True, segments=40, radius1=0.5, radius2=0.5, depth=1.0); bm.to_mesh(tube); bm.free()
    meshes = {}
    def mesh_for(shape, colour):
        key = (shape, colour)
        if key not in meshes:
            meshes[key] = {'b': cube, 's': ball, 'c': tube}[shape].copy()
            meshes[key].materials.append(mats[colour])
        return meshes[key]
    for i, row in enumerate(PARTS):
        ob = bpy.data.objects.new(f"{row['n']}_{i:04d}", mesh_for(row['sh'], row['c']))
        x, y, z = row['p']
        ob.location = (x, -z, y)                                  # Blender is Z-up; the level's z runs across
        sx, sy, sz = row['s']
        if row['sh'] == 'c':
            ob.scale = (sy, sz, sx)                               # a vertical fold: Roblox length = Blender height
        else:
            ob.scale = (sx, sz, sy)
            ob.rotation_euler = (0, 0, -math.radians(row['yaw']))
        col.objects.link(ob)
    for i, row in enumerate(BALLS):
        ob = bpy.data.objects.new(f'Ball_{i:03d}', mesh_for('s', 'sphere'))
        x, y, z = row['p']
        ob.location, ob.scale = (x, -z, y), (row['r'] * 2,) * 3
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
    print('saved', blend / 'Level5_Void.blend', 'and the plaster maps in', tex)
