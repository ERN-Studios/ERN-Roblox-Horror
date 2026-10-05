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
# v3 (2026-10-05, owner: "make the level 5 much harder, and add 4 more levels ... the rooms' geometry each level
# become different and harder"): every cap is up, every ledge is narrower (WIDER) and every gap longer (LONGER)
# than v2, and four rooms follow Coral: ORANGE the double spiral, CRIMSON the ring round the great pillar, TEAL the
# field of small pillars, IVORY the tower with the stair round its column. There are no checkpoints any more (a
# fall is a death), so the caps stop short of 100%: the last rooms need a clean jump every time, not a perfect one.
SHARE = {'rose': 0.62, 'blue': 0.74, 'amber': 0.82, 'mint': 0.87, 'violet': 0.90, 'coral': 0.92,
         'orange': 0.93, 'crimson': 0.94, 'teal': 0.95, 'ivory': 0.95}
LONGER = {'rose': 1.22, 'blue': 1.14, 'amber': 1.10, 'mint': 1.08, 'violet': 1.05, 'coral': 1.04}     # gap length, v2 -> v3
WIDER = {'rose': 0.80, 'blue': 0.78, 'amber': 0.80, 'mint': 0.84, 'violet': 0.86, 'coral': 0.88}      # ledge width, v2 -> v3
COLOURS = {
    'rose': (224, 150, 200), 'blue': (92, 150, 200), 'amber': (228, 180, 88),
    'mint': (150, 216, 182), 'violet': (164, 134, 214), 'coral': (236, 118, 102), 'black': (4, 4, 5),
    'orange': (244, 142, 44), 'crimson': (188, 34, 46), 'teal': (44, 178, 184), 'ivory': (232, 228, 212),
    'stone': (74, 72, 68), 'slab': (30, 29, 28), 'glass': (150, 190, 200),
    'sphere': (26, 38, 120), 'orb': (150, 146, 134), 'plate': (236, 236, 230),
}
PARTS, BALLS, LIGHTS, ROUTE, CHECKPOINTS, GAPS, PLATES, FOOT = [], [], [], [], [], [], [], []
ROOFED = {'rose', 'blue', 'amber'}       # owner, 2026-10-05: only these have a ceiling you can see; the rest go up into black
RISE = 320.0                              # how far an open room's walls carry on above the route
STACKED = {'crimson', 'ivory'}   # a stair fixed to a column winds up over itself: no solid blocks, no crossing test
FINALE = {}               # the last room's closing corridor: what the server needs to run it
EXTENT = {}        # section -> [min x, max x, min z, max z, min y, max y] of its walkable pieces
random.seed(505)


def reach(dy):
    disc = JUMP * JUMP - 2 * GRAVITY * dy
    assert disc > 0, f'a rise of {dy} is above the jump apex'
    return WALK * (JUMP + math.sqrt(disc)) / GRAVITY


def part(name, size, pos, colour, yaw=0.0, shape='b', collide=True, material='SmoothPlastic', extra=None):
    row = {'n': name, 's': [round(v, 3) for v in size], 'p': [round(v, 3) for v in pos], 'c': colour,
           'yaw': round(yaw, 3), 'sh': shape, 'col': collide, 'm': material}
    if extra:
        row.update(extra)
    PARTS.append(row)


def solid(name, length, width, top, cx, cz, yaw, colour, bottom=BOTTOM):
    """A block whose top face is the surface and whose body runs down into the dark."""
    part(name, (length, top - bottom, width), (cx, (top + bottom) / 2, cz), colour, yaw=yaw)


def light(pos, rng=60, brightness=0.2, name=None):
    row = {'p': [round(v, 2) for v in pos], 'r': rng, 'b': round(brightness, 3)}
    if name:
        row['n'] = name
    LIGHTS.append(row)


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

    def narrow(self, width, least=2.0):
        """v3: the same route on narrower ledges. Beams never go under a body's width."""
        return max(least, width * WIDER.get(self.section, 1.0))

    def plat(self, length, width, name='Walk'):
        width = self.narrow(width, 6.0 if name == 'Rest' else 2.0) if name != 'Plaza' else width
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
        distance = round(min(distance * LONGER.get(self.section, 1.0), limit * cap - 0.01), 2)
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
        w0, w1 = self.narrow(w0), self.narrow(w1)
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
        self.plat(12, 30, 'Plaza')
        ROUTE.pop()                                               # no pause at a seam inside the plaza
        if not last:
            self.way(5.0, plate=self.section)
            PLATES.append({'sec': self.section, 'x': round(cx, 2), 'y': round(cy, 2), 'z': round(cz, 2)})
        self.plat(24, 30, 'Plaza')
        orb(cx, cy + 22, cz, self.section)
        return self


def orb(x, y, z, colour):
    """The lamp: a white ball on a rod from the ceiling (the rod's top is set by `room`, which knows the ceiling)."""
    # Owner, 2026-10-04: the first lamps (a 5-stud white neon globe, light 2.6 over 46 studs) were blinding and hid
    # the way ahead. A 3-stud dull globe and a light a sixth as strong.
    part('Orb', (3, 3, 3), (x, y + 0.9, z), 'orb', shape='s', collide=False, material='Neon', extra={'light': [30, 0.45], 'rod': colour})


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


def room(name, x0, x1, monoliths=True, shaft=False, dense=1, column=None):
    e = EXTENT[name]
    print(f'    {name}: z {e[2]:.1f}..{e[3]:.1f}, ends at z {ROUTE[-1]["z"]:.1f}')
    assert e[0] >= x0 - 0.01 and e[1] <= x1 + 0.01, f'{name}: the path runs x {e[0]:.1f}..{e[1]:.1f}, outside the room {x0:.1f}..{x1:.1f}'
    limit = HALF - 2 if shaft else CLEAR_Z                 # a shaft's stair runs along the walls themselves
    assert e[2] >= -limit and e[3] <= limit, f'{name}: the path runs z {e[2]:.1f}..{e[3]:.1f}, into the walls (limit {limit})'
    if name not in STACKED:
        no_crossing(name)
    length, top = x1 - x0, e[5] + 64
    roofed = name in ROOFED
    lamp_top = top                                 # the lamps and their rods are placed as if the ceiling were there
    if not roofed:
        top = e[5] + RISE                          # no ceiling: the walls carry on up, past where any light reaches
    for side in (-1, 1):
        part('Wall', (length, top - BOTTOM, 8), ((x0 + x1) / 2, (top + BOTTOM) / 2, side * (HALF + 4)), name)
    if roofed:
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
    while monoliths and not shaft and made < int(length // 34) * dense and tries < 9000:
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
                if column:                                 # a stair round a column is lit from outside it
                    dx, dz = b['x'] - column[0], b['z'] - column[1]
                d = math.hypot(dx, dz) or 1.0
                light((b['x'] + dx / d * 12, b['y'] + 10, b['z'] + dz / d * 12))
                light((b['x'] + dx / d * 12, b['y'] + 36, b['z'] + dz / d * 12))
    for i in range(0 if shaft else int((length - 36) // 34) + 1):
        lx = x0 + 18 + i * 34
        y = route_y(name, lx)
        for lz in (-18, 18):
            for ly in (y + 10, y + 44):
                if ly < lamp_top - 16:
                    light((lx, ly, lz))
            if roofed:
                light((lx, top - 12, lz))              # the row that shows the ceiling; an open room has none
    for row in PARTS:                                             # hang this room's lamps from its ceiling
        if row.get('rod') == name:
            x, y, z = row['p']
            part('OrbRod', (0.35, top - y - 1.4, 0.35), (x, (top + y + 1.4) / 2, z), 'black', collide=False, material='Metal')
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


def close(p, x0, last=False, x1=None, shaft=False, dense=1, column=None, door=None):
    """Walls, ceiling, lamps and the two end walls for the room `p` has just finished; returns where the next starts.
    `door` = (width, height) of the way out of the last room, which has no plate and no link."""
    name = p.section
    x1 = p.x if x1 is None else x1
    top = room(name, x0, x1, shaft=shaft, dense=dense, column=column)
    if last and door:
        wall_with_door(x1 + 4, name, top, p.z, p.y, door_w=door[0], door_h=door[1])
        return top
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
# The shaft: a well with nothing in the middle. The stair climbs the west wall, the north wall and half the east
# side, with a missing piece in every stretch (<= 92%, most with a rise), to a ledge and a door high in the east
# wall. (In v2 this was the last room and went once round to a doorway above the entrance.)
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
        before = (p.x, p.z)
        p.stairs(6, 2.0, 0.9, width, width).plat(4.5, width).gap(g, dy).plat(4.0, width)
        left -= math.hypot(p.x - before[0], p.z - before[1])
    steps = int((left - 6) // 2)
    p.stairs(steps, 2.0, 0.9, width, width)
    p.plat(left - steps * 2, width)

climb(HALF - 3 - p.z, 5.0)                       # west wall to the north-west corner
p.corner(-90, 6)
climb(SHAFT - 6 - 36, 4.6)                       # north wall, stopping where the east ledge will be
p.corner(-90, 6)
climb(p.z - coral_in[0], 4.2)                    # south along the east side, to the height of the door
p.turn(90, 6)
p.plaza()
nxt = close(p, cx0, shaft=True)
wall_with_door(cx0 - 4, 'coral', nxt[3], coral_in[0], coral_in[1])


def mark(sec, x, y, z, jump=False, **flags):
    e = EXTENT.setdefault(sec, [x, x, z, z, y, y])
    e[0], e[1], e[2], e[3], e[4], e[5] = min(e[0], x), max(e[1], x), min(e[2], z), max(e[3], z), min(e[4], y), max(e[5], y)
    ROUTE.append({'x': round(x, 2), 'y': round(y, 2), 'z': round(z, 2), 'jump': jump, 'sec': sec, **flags})


def follow(p, points, width, plan):
    """Walk the cursor along `points` (x, z). `plan(i)` says what segment i is: None = a ledge that steps up 0.9,
    'flat' = a ledge at the same height, or (gap, dy) = a jump at the start of the segment and a ledge after it."""
    for i, (x, z) in enumerate(points):
        d = math.hypot(x - p.x, z - p.z)
        if d < 0.05:
            continue
        p.h = math.degrees(math.atan2(z - p.z, x - p.x))
        what = plan(i)
        if isinstance(what, tuple):
            p.gap(what[0], what[1])
            p.plat(math.hypot(x - p.x, z - p.z), width)
        else:
            solid('Walk', width, width, p.y, p.x, p.z, p.h, p.colour)                # the joint the turn pivots on
            if what is None:
                p.y += 0.9
            p.plat(d, width)
        p.x, p.z = x, z


def centre_room(p, target=0.0):
    """Bring the route to the middle of the room (the round rooms are built about z = 0)."""
    if abs(p.z - target) > 0.5:
        sign = 1 if target > p.z else -1
        run = abs(target - p.z)
        p.turn(sign * 90 * p.mirror, 5).plat(run, 5).turn(-sign * 90 * p.mirror, 5)
    return p


def spiral(sec, cx, cz, column, y0, sweep, width, units, tread=4.0, thick=1.4, a0=180.0):
    """A stair fixed to a round column of radius `column`: treads from the column's face outward, each `tread`
    long, laid clockwise seen from above (toward +z first) from the angle `a0` through `sweep` degrees.
    `width(t)` is the tread width at progress t (0 at the foot, 1 at the top). `units(k)` gives the k-th stretch
    as a list of (dy, gap): dy = how much higher this tread is than the last, gap = None for the next tread of a
    stair, or the length of the jump that lands on it. The last few treads are level, for the arrival.
    Returns (x, y, z, heading, radius of the last tread's centre line)."""
    cap = SHARE[sec]
    ang, y, done = math.radians(a0), y0, 0.0
    total = math.radians(sweep)
    laid = []                                                 # (sweep so far, y) of every tread, for the headroom test
    prev = None                                               # (x, z, heading, rt) of the last tread
    queue, k = [], 0
    while True:
        left = total - done
        if not queue:
            queue = list(units(k))
            k += 1
        dy, gap = queue.pop(0)
        w = width(min(1.0, done / total))
        rt = column + w / 2 - 0.4                             # centre line; the inner edge is sunk into the column
        if left * rt < tread * 2.6:                           # the arrival: level treads up to the end angle
            dy, gap, queue = 0.0, None, [(0.0, None)] * 4
        step = 0.0
        if prev:
            chord = tread + (gap or 0.0)
            step = 2 * math.asin(min(1.0, chord / (rt + prev[3])))
            if step > left + 1e-9:
                if gap:
                    dy, gap = 0.0, None
                    continue
                step = left
        ang -= step
        done += step
        y += dy
        x, z = cx + rt * math.cos(ang), cz + rt * math.sin(ang)
        heading = math.degrees(ang) - 90
        hx, hz = math.cos(math.radians(heading)), math.sin(math.radians(heading))
        if prev and gap:
            # edge to edge, as the body crosses it: from the end of the last tread to the start of this one
            px, pz, ph = prev[0], prev[1], math.radians(prev[2])
            ex, ez = px + math.cos(ph) * tread / 2, pz + math.sin(ph) * tread / 2
            real = math.hypot(x - hx * tread / 2 - ex, z - hz * tread / 2 - ez)
            assert real <= reach(dy) * cap + 1e-6, f'{sec}: spiral gap {real:.2f} with dy {dy} is over the cap {reach(dy) * cap:.2f}'
            GAPS.append({'sec': sec, 'gap': round(real, 2), 'dy': dy, 'reach': round(reach(dy), 2), 'share': round(real / reach(dy), 3)})
        # long enough that neighbours meet at the OUTER edge too (a wide tread on a tight column fans out)
        length = tread * (column + w - 0.4) / rt + 0.4
        part('Step', (length, thick, w), (x, y - thick / 2, z), sec, yaw=heading)
        mark(sec, x, y, z, jump=bool(gap))
        laid.append((done, y))
        prev = (x, z, heading, rt)
        if total - done < 1e-6:
            break
    # headroom: a body under the turn above needs its own height and the top of a jump (6.4)
    turn = 2 * math.pi
    for a, ya in laid:
        over = [yb for b, yb in laid if abs((b - a) - turn) < 0.06]
        assert all(yb - ya >= 15.0 for yb in over), f'{sec}: the stair passes {min(over) - ya:.1f} above itself'
    return x, y, z, heading, rt


# ---------------------------------------------------------------------------------------------- 7. ORANGE
# The double spiral: one arm winds in to an island in the middle, climbing all the way, and its twin winds out
# again to the far side. A jump on every other ledge (<= 93%), the ledges 3 studs wide.
p = open_room('orange', nxt[:3])
orange_in = (p.z, p.y)
p.rest(14, 10)
centre_room(p)
p.plat(6, 5)
R_OUT, R_IN, TURNS, PIECE = 56.0, 17.0, 1.25, 10.6            # PIECE: a ledge, or a jump and its landing
ocx, ocz = p.x + R_OUT, 0.0
arm = []
sweep, most = 0.0, 2 * math.pi * TURNS
while True:
    r = R_OUT - (R_OUT - R_IN) * sweep / most
    sweep += PIECE / r                                           # equal lengths, not equal angles: the middle is not a knot
    if sweep >= most:
        break
    r = R_OUT - (R_OUT - R_IN) * sweep / most
    ang = math.pi + sweep                                        # from the west point, turning toward +z first
    arm.append((ocx + r * math.cos(ang), ocz + r * math.sin(ang)))
ORANGE_GAPS = [(7.2, 0.0), (6.9, 1.0), (7.3, 0.0), (6.7, 1.5), (7.4, 0.0), (6.9, 1.0), (7.3, -1.0), (6.6, 2.0)]
def orange_plan(i, offset=0):
    return ORANGE_GAPS[((i + offset) // 2) % len(ORANGE_GAPS)] if (i + offset) % 2 == 1 else None
follow(p, arm, 3.0, orange_plan)
island = (2 * ocx - p.x, 2 * ocz - p.z)                         # straight across the middle to the twin arm's start
p.h = math.degrees(math.atan2(island[1] - p.z, island[0] - p.x))
CHECKPOINTS.append({'sec': 'orange', 'x': round(ocx, 2), 'y': round(p.y, 2), 'z': round(ocz, 2), 'at': len(ROUTE)})
orb(ocx, p.y + 20, ocz, 'orange')
solid('Walk', 9, 9, p.y, p.x, p.z, p.h, 'orange')
p.plat(math.hypot(island[0] - p.x, island[1] - p.z), 9, 'Rest').ball(8, 2.5, 1.5).ball(13, -2.5, 1.1)
p.x, p.z = island
out = [(2 * ocx - x, 2 * ocz - z) for x, z in reversed(arm[:-1])] + [(ocx + R_OUT, ocz)]
follow(p, out, 3.0, lambda i: orange_plan(i, 1))
p.h = 0.0
solid('Walk', 6, 6, p.y, p.x, p.z, 0, 'orange')
p.plaza()
nxt = close(p, p.x0 - 4, shaft=True)
wall_with_door(p.x0 - 4, 'orange', nxt[3], orange_in[0], orange_in[1])

# ---------------------------------------------------------------------------------------------- 8. CRIMSON
# The spiral (owner, 2026-10-05: "the red level should be much more for a spiral going high up to the next
# level"). A great pillar stands in the middle of the drop and a stair fixed to it winds four and a half times
# round, 130 studs up, a missing stretch after every short flight (<= 94%, half of them with a rise), to a bridge
# and a door high in the east wall. (v3 was half a ring of single blocks at one height.)
p = open_room('crimson', nxt[:3])
crimson_in = (p.z, p.y)
p.rest(14, 10)
centre_room(p)
PILLAR, C_TREAD_W = 30.0, 5.0
p.plat(12, 4)                                                    # the beam out to the foot of the stair
rcx, rcz, ry0 = p.x + PILLAR + C_TREAD_W - 0.4, 0.0, p.y
CRIMSON_GAPS = [(7.3, 0.0), (6.9, 1.0), (7.4, 0.0), (6.8, 1.5), (7.5, 0.0), (7.0, 1.0), (7.5, -1.0), (6.7, 2.0)]
def crimson_unit(k):
    first = [(0.0, None)] if k == 0 else [(CRIMSON_GAPS[k % len(CRIMSON_GAPS)][1], CRIMSON_GAPS[k % len(CRIMSON_GAPS)][0])]
    return first + [(0.9, None)] * 5 + [(0.0, None)]
x, y, z, heading, rt = spiral('crimson', rcx, rcz, PILLAR, ry0, 360 * 4.5, lambda t: C_TREAD_W, crimson_unit)
part('Fold', (y + RISE - BOTTOM, PILLAR * 2, PILLAR * 2), (rcx, (y + RISE + BOTTOM) / 2, rcz), 'crimson', shape='c', extra={'roll': 90})   # the pillar, up into the dark
# The stair carries on above the door, broken: the next tread is twenty studs away and the rest thin out.
ruin = random.Random(88)
ang, ry = math.radians(-34.0), y + 4.0
for k in range(26):
    ang -= math.radians(8.0)
    ry += 0.9
    if ruin.random() < 0.45:
        continue
    rr = PILLAR + C_TREAD_W / 2 - 0.4
    part('Ruin', (4.6, 1.4, C_TREAD_W * ruin.uniform(0.5, 1.0)), (rcx + rr * math.cos(ang), ry - 0.7, rcz + rr * math.sin(ang)),
         'crimson', yaw=math.degrees(ang) - 90, collide=False)
# the bridge from the top of the stair to the plaza: not a solid block, the lower turns pass under it
bridge = 9.0
part('Walk', (bridge + 1.0, 1.4, 5.0), (rcx + PILLAR + C_TREAD_W - 0.9 + bridge / 2, y - 0.7, rcz), 'crimson')
p.x, p.y, p.z, p.h = rcx + PILLAR + C_TREAD_W - 0.4 + bridge, y, rcz, 0.0
mark('crimson', p.x - 1.0, p.y, p.z)
p.plaza()
nxt = close(p, p.x0 - 4, shaft=True, column=(rcx, rcz))
wall_with_door(p.x0 - 4, 'crimson', nxt[3], crimson_in[0], crimson_in[1])

# ---------------------------------------------------------------------------------------------- 9. TEAL
# The field: no ledge at all, only the tops of small pillars, each a jump from the last (<= 95%), in a zig-zag
# through a forest of pillars that are not the way.
p = open_room('teal', nxt[:3])
teal_in = (p.z, p.y)
p.rest(12, 9)
centre_room(p)
TEAL = [(0, 7.3, 0.0), (28, 7.0, 1.0), (0, 7.4, 0.0), (-56, 7.2, -1.5), (0, 6.9, 1.5), (0, 7.5, 0.0), (56, 7.0, 2.0),
        (0, 7.4, -2.0), (0, 7.5, 0.0), (-56, 6.8, 1.5), (0, 7.5, 0.0), (0, 7.3, -1.0), (56, 7.0, 2.0), (0, 7.5, 0.0),
        (-28, 7.4, -2.5), (0, 7.5, 0.0), (-28, 7.0, 1.5), (0, 7.5, 0.0), (56, 7.3, -1.5), (0, 7.1, 2.0), (0, 7.5, 0.0),
        (-56, 7.5, -3.0), (0, 7.0, 1.0), (0, 7.5, 0.0), (56, 7.2, 1.5), (0, 7.5, 0.0), (-28, 7.5, -2.0), (0, 7.5, 0.0)]
for k, (turn, g, dy) in enumerate(TEAL):
    if turn:
        p.h += turn
    size = 4.6 if k % 7 == 6 else 2.8
    p.gap(g, dy).plat(size, size)
assert abs(p.h % 360) < 1e-6, p.h
p.gap(7.2).plat(6, 5)
p.plaza()
nxt = close(p, p.x0 - 4, dense=3)
wall_with_door(p.x0 - 4, 'teal', nxt[3], teal_in[0], teal_in[1])

# ---------------------------------------------------------------------------------------------- 10. IVORY
# The tower and the way out (owner, 2026-10-05: "make the last section staircase start wide and then become very
# thin and have them walk a great amount of up ... in the top of the staircase, create a platform and a long
# corridor that goes into the exit door"). One column in the middle of a square well and a stair fixed to it,
# seven and a half times round: ten studs wide at the foot and a body's width at the top, a missing stretch in
# every flight (<= 95%). A body that falls from the thin top is usually caught by a wider turn further down.
# The column's top is the platform where a party gathers. A pier leads east from it through a great doorway
# into THE CORRIDOR: when the whole party is inside, a block comes down in the doorway behind them, the gate
# ahead sinks, and the two walls start to close. The exit door is in a small room at the far end that the walls
# do not reach, with windows back into the corridor. Level5PreviewAccess runs it; `finale` in the json is what
# it needs to know.
ix0, iy0, iz0 = nxt[:3]
p = open_room('ivory', nxt[:3])
ivory_in = (p.z, p.y)
p.rest(12, 9)
centre_room(p)
COLUMN, I_W0, I_W1, I_TREAD = 12.0, 10.0, 2.2, 3.6
icx, icz = ix0 + SHAFT / 2, 0.0
p.plat((icx - COLUMN - I_W0 + 0.4) - p.x, 3.0)                   # the beam out to the foot of the stair
IVORY_GAPS = [(6.9, 1.0), (7.1, 0.0), (6.8, 1.0), (7.2, 0.0), (6.9, 1.0), (7.2, 0.0)]
def ivory_unit(k):
    g, dy = IVORY_GAPS[k % len(IVORY_GAPS)]
    if k >= 15:
        g -= 0.3                                                 # the last turns are a body wide: the jumps ease a little
    first = [(0.0, None)] if k == 0 else [(dy, g)]
    return first + [(1.25, None)] * 6 + [(0.0, None)]             # steep enough that the thin top turns still clear each other
x, y, z, heading, rt = spiral('ivory', icx, icz, COLUMN, p.y, 360 * 7.5, lambda t: I_W0 + (I_W1 - I_W0) * t, ivory_unit, tread=I_TREAD)
YT = y                                                           # the height of the platform, the corridor and the exit
x1 = ix0 + SHAFT
part('Fold', (YT - BOTTOM, COLUMN * 2, COLUMN * 2), (icx, (YT + BOTTOM) / 2, icz), 'ivory', shape='c', extra={'roll': 90})   # the column: its top is the platform
part('Rest', (16, 1.4, 14), (icx + 16.0, YT - 0.7, icz), 'ivory')                # the deck east of it
solid('Walk', x1 - (icx + 24), 12, YT, (icx + 24 + x1) / 2, icz, 0, 'ivory')     # the pier to the great doorway
CHECKPOINTS.append({'sec': 'ivory', 'x': round(icx, 2), 'y': round(YT, 2), 'z': round(icz, 2), 'at': len(ROUTE)})
mark('ivory', icx + 6, YT, icz)
mark('ivory', icx + 30, YT, icz)
mark('ivory', x1 - 12, YT, icz)                                  # the walk-through stops here: the corridor is its own test
orb(icx, YT + 21, icz, 'ivory')
p.x, p.y, p.z, p.h = x1, YT, icz, 0.0
DOOR_IN = (14.0, 16.0)
close(p, ix0, last=True, x1=x1, shaft=True, column=(icx, icz), door=DOOR_IN)
wall_with_door(ix0 - 4, 'ivory', EXTENT['ivory'][5] + RISE, ivory_in[0], ivory_in[1])

WX = x1 + 8.0                 # the corridor begins at the east face of the well's wall
L, HALF_W, H = 226.0, 13.0, 16.4
EX = WX + L                   # the west face of the end wall
ROOM_LEN = 30.0
SHELL = L + 4 + ROOM_LEN + 4
solid('FinaleFloor', SHELL, 72, YT, WX + SHELL / 2, 0, 0, 'stone')                 # carried from the bottom of the drop, like everything
part('FinaleCeiling', (SHELL, 3, 72), (WX + SHELL / 2, YT + H + 1.6, 0), 'black')
for side in (-1, 1):
    part('FinaleShell', (SHELL, H + 3.2, 3), (WX + SHELL / 2, YT + (H + 3.2) / 2 - 0.1, side * 34.6), 'black')
    # a closing wall: it fills its side from the corridor's face to the shell, and comes in until the two meet
    part('CrusherWall', (L - 0.4, H, 20.0), (WX + L / 2, YT + H / 2, side * (HALF_W + 10.0)), 'slab', extra={'g': 'Finale', 'side': side})
# the block waits inside the wall over the doorway; the gate stands 28 studs in and sinks into the floor
part('CrusherBlock', (7.6, H, DOOR_IN[0] - 0.1), (x1 + 4, YT + DOOR_IN[1] + 0.3 + H / 2, 0), 'slab', extra={'g': 'Finale'})
part('CrusherGate', (2.4, H, HALF_W * 2 + 0.4), (WX + 28.0, YT + H / 2, 0), 'slab', extra={'g': 'Finale'})

def end_slab(z0, z1, y0, y1):
    part('FinaleWall', (4.0, y1 - y0, z1 - z0), (EX + 2, YT + (y0 + y1) / 2, (z0 + z1) / 2), 'stone')
for z0, z1 in ((-36.0, -12.5), (12.5, 36.0), (-5.5, -4.0), (4.0, 5.5)):       # the ends and the piers beside the door
    end_slab(z0, z1, 0.0, H + 0.1)
end_slab(-4.0, 4.0, 13.0, H + 0.1)                                            # over the door (8 wide, 13 high)
for z0, z1 in ((-12.5, -5.5), (5.5, 12.5)):                                    # a window each side: the room looks back down the corridor
    end_slab(z0, z1, 0.0, 2.5)
    end_slab(z0, z1, 10.5, H + 0.1)
    part('FinaleGlass', (0.8, 8.0, 7.0), (EX + 2, YT + 6.5, (z0 + z1) / 2), 'glass', material='Glass', extra={'t': 0.6})
for side in (-1, 1):                                                           # the small room the walls do not reach
    part('FinaleWall', (ROOM_LEN, H + 0.1, 4), (EX + 4 + ROOM_LEN / 2, YT + (H + 0.1) / 2, side * 15.0), 'stone')
FX = EX + 4 + ROOM_LEN
part('FinaleWall', (4, H + 0.1, 72), (FX + 2, YT + (H + 0.1) / 2, 0), 'stone')
for side in (-1, 1):                                                           # the lit doorway out of the level
    part('ExitFrame', (3, 14, 3), (FX - 1.2, YT + 7, side * 5.5), 'ivory')
part('ExitFrame', (3, 3, 14), (FX - 1.2, YT + 14.5, 0), 'ivory')
part('ExitDark', (1, 13, 8), (FX - 0.2, YT + 6.5, 0), 'black')
finish = (FX - 4.5, YT, 0.0)
for i in range(int(L // 28) + 1):
    light((WX + 12 + i * 28, YT + 13.4, 0), 34, 0.4, name='CrusherLight')
light((EX + 4 + ROOM_LEN / 2, YT + 12.5, 0), 34, 0.55)
light((FX - 5, YT + 9, 0), 20, 0.7)
FINALE.update({
    'floor': round(YT, 2), 'height': H, 'half': HALF_W, 'z': 0.0,
    'entry_x': round(x1 + 4, 2),        # the block's doorway
    'inside_x': round(WX + 5.0, 2),     # past this line a body is in the corridor
    'gate_x': round(WX + 28.0, 2), 'end_x': round(EX, 2),
    'room': [round(EX + 4, 2), round(FX, 2), 13.0],
    'reentry': [round(EX + 14, 2), round(YT, 2), 0.0],
    'block_drop': DOOR_IN[1] + 0.3, 'wall_travel': HALF_W,
})
TOTAL = WX + SHELL

# a fall is judged against the lowest walking height between a checkpoint and the next one
for i, cp in enumerate(CHECKPOINTS):
    end = CHECKPOINTS[i + 1]['at'] + 2 if i + 1 < len(CHECKPOINTS) else len(ROUTE)
    cp['low'] = round(min(r['y'] for r in ROUTE[cp['at']:end]), 2)
    cp['i'] = i

OUT.mkdir(parents=True, exist_ok=True)
data = {'origin': [40000, 600, 0], 'colours': COLOURS, 'parts': PARTS, 'balls': BALLS, 'lights': LIGHTS, 'route': ROUTE,
        'checkpoints': CHECKPOINTS, 'plates': PLATES, 'start': START, 'finish': finish, 'gaps': GAPS, 'finale': FINALE,
        'sections': ['rose', 'blue', 'amber', 'mint', 'violet', 'coral', 'orange', 'crimson', 'teal', 'ivory'],
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
