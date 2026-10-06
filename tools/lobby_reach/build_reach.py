"""The thing behind the lobby's fence: its arms and eyes, modelled in Blender.

    /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/lobby_reach/build_reach.py
    ... --python tools/lobby_reach/build_reach.py -- --no-render

TUNNEL_REACH_20261006 (owner: jump the fence at the DJ end and big glowing eyes open in the dark; long, clammy arms
"made in Blender" creep toward whoever is over there, and if they do not jump back it takes them and pulls them into
the dark). Nothing of the creature is ever seen but the eyes, the arms and the hands, so that is all there is.

An arm is not one mesh: it is a chain of long bones with a knob at every elbow, and a hand with six digits of three
joints each, all posed by the client every frame (Lobby Tunnel Reach Client). This file makes the nine pieces:

    bone_a, bone_b, bone_c   one long bone of the arm, 20 studs, three different ones so a chain does not repeat
    elbow                    the knob over a joint
    palm                     the hand without its digits (the roots of the digits are in `hand` below)
    finger, thumb            a first or second joint of a digit
    claw                     the last joint, ending in a nail
    eye                      the iris of one eye, a shallow dome (the client scales it and lays a pupil on it)

Every piece is in ROBLOX's frame and in studs: x across, y up, and -z is the FAR end (toward the fingertips), which
is the way CFrame.lookAt points. Each is centred on its own bounding box, because that is where a MeshPart puts its
origin. Skin, veins, bruises, raw joints and nails are painted as vertex colours: there are no textures (an image
uploaded from a session belongs to the user and the group's place may not use it).

Written to artifacts/lobby-reach-20261006/: blend/Lobby_Reach.blend (the pieces, and one arm assembled the way the
game poses it), export/reach_meshes.json (what install_reach.py puts in the place), preview/*.png.
"""
import json
import math
import random
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'artifacts' / 'lobby-reach-20261006'
TAU = math.tau

# ---- skin ------------------------------------------------------------------------------------------------------------
SKIN = (0.71, 0.67, 0.60)        # bloodless, and none too clean
SALLOW = (0.60, 0.61, 0.47)      # the yellow-green of something kept in the dark
BRUISE = (0.43, 0.37, 0.45)
RAW = (0.44, 0.24, 0.23)         # rubbed raw over every joint
VEIN = (0.20, 0.15, 0.33)
SINEW = (0.84, 0.80, 0.72)       # skin stretched white over a cord
SORE = (0.27, 0.06, 0.07)
GRIME = (0.16, 0.14, 0.11)
NAIL = (0.33, 0.27, 0.14)
NAIL_TIP = (0.07, 0.06, 0.05)

# ---- the hand, in the palm's own frame (studs): the client reads these numbers from the export ----------------------
PALM = (4.4, 1.5, 5.0)           # across, thick, long
DIGITS = [                        # root on the palm, splay about the palm's up axis (degrees), the three joint lengths
    {'kind': 'finger', 'root': (-1.62, 0.05, -2.25), 'yaw': 15.0, 'lengths': (3.1, 2.7, 2.6), 'thick': 0.74},
    {'kind': 'finger', 'root': (-0.55, 0.12, -2.40), 'yaw': 5.0, 'lengths': (3.4, 2.9, 2.7), 'thick': 0.78},
    {'kind': 'finger', 'root': (0.55, 0.12, -2.40), 'yaw': -5.0, 'lengths': (3.3, 2.8, 2.7), 'thick': 0.78},
    {'kind': 'finger', 'root': (1.62, 0.05, -2.25), 'yaw': -15.0, 'lengths': (2.9, 2.6, 2.5), 'thick': 0.72},
    {'kind': 'thumb', 'root': (-2.05, -0.05, 0.55), 'yaw': 68.0, 'lengths': (2.7, 2.4, 2.3), 'thick': 0.80},
    {'kind': 'thumb', 'root': (2.05, -0.05, 0.55), 'yaw': -68.0, 'lengths': (2.7, 2.4, 2.3), 'thick': 0.80},
]


def clamp(v, a=0.0, b=1.0):
    return max(a, min(b, v))


def smooth(a, b, v):
    u = clamp((v - a) / (b - a))
    return u * u * (3 - 2 * u)


def mix(a, b, t):
    t = clamp(t)
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def angdist(a, b):
    return abs((a - b + math.pi) % TAU - math.pi)


class Field:
    """A smooth made-up function of (z, angle) in about -1..1, periodic in the angle."""

    def __init__(self, rng, terms, zfreq, kmax):
        self.terms = [(rng.uniform(0.4, 1.0), rng.randint(0, kmax), rng.uniform(*zfreq), rng.uniform(0, TAU), rng.uniform(0, TAU))
                      for _ in range(terms)]
        self.norm = sum(t[0] for t in self.terms) * 0.6

    def __call__(self, z, th):
        return sum(a * math.sin(k * th + p) * math.sin(TAU * f * z + q) if k else a * math.sin(TAU * f * z + q)
                   for a, k, f, p, q in self.terms) / self.norm


class Mesh:
    def __init__(self, name):
        self.name, self.verts, self.colours, self.tris = name, [], [], []

    def ring(self, points, colours):
        start = len(self.verts)
        self.verts += points
        self.colours += colours
        return list(range(start, start + len(points)))

    def bridge(self, a, b):
        n = len(a)
        for k in range(n):
            k2 = (k + 1) % n
            self.tris += [(a[k], a[k2], b[k2]), (a[k], b[k2], b[k])]

    def fan(self, centre, ring, flip=None):
        """Close a ring. The body already runs each of the ring's edges one way round; the cap must run them the
        other way, or it faces inward and the game culls it (a hole in a knuckle, seen in the first build)."""
        n = len(ring)
        directed = {(t[i], t[(i + 1) % 3]) for t in self.tris for i in range(3)}
        flip = (ring[0], ring[1]) in directed
        for k in range(n):
            k2 = (k + 1) % n
            self.tris.append((centre, ring[k2], ring[k]) if flip else (centre, ring[k], ring[k2]))

    def finish(self):
        """Outward faces, a box-centred origin, smooth normals."""
        vol = 0.0
        for a, b, c in self.tris:
            va, vb, vc = (Vector(self.verts[i]) for i in (a, b, c))
            vol += va.dot(vb.cross(vc))
        if vol < 0:
            self.tris = [(a, c, b) for a, b, c in self.tris]
        seen = set()
        for t in self.tris:                                        # a closed skin: every edge once in each direction
            for i in range(3):
                edge = (t[i], t[(i + 1) % 3])
                assert edge not in seen, f'{self.name}: two faces wound the same way along one edge'
                seen.add(edge)
        assert all((b, a) in seen for a, b in seen), f'{self.name}: the skin is not closed'
        lo = [min(v[i] for v in self.verts) for i in range(3)]
        hi = [max(v[i] for v in self.verts) for i in range(3)]
        mid = [(lo[i] + hi[i]) / 2 for i in range(3)]
        self.offset = tuple(mid)                                   # where the box's centre was in the modelled frame
        self.verts = [tuple(v[i] - mid[i] for i in range(3)) for v in self.verts]
        self.size = tuple(hi[i] - lo[i] for i in range(3))
        normals = [Vector((0, 0, 0)) for _ in self.verts]
        for a, b, c in self.tris:
            va, vb, vc = (Vector(self.verts[i]) for i in (a, b, c))
            n = (vb - va).cross(vc - va)
            for i in (a, b, c):
                normals[i] += n
        self.normals = [tuple(n.normalized()) if n.length > 1e-12 else (0.0, 1.0, 0.0) for n in normals]
        return self


def tube(name, length, rings, sides, centre, shape, cap=0.035, cap_rings=4, point=False):
    """A limb along z: z=0 is the near end (+length/2), z=1 the far end (-length/2).
    centre(z) -> (x, y); shape(z, th) -> (radius, colour). `point`: the far end closes to a tip instead of a cap."""
    mesh = Mesh(name)
    stations = []                                                  # (z, scale of the radius)
    for i in range(1, cap_rings + 1):
        a = i / cap_rings * math.pi / 2
        stations.append((cap * (1 - math.cos(a)), math.sin(a)))
    body = [cap + (1 - 2 * cap) * j / (rings - 1) for j in range(rings)]
    stations += [(z, 1.0) for z in body[1:-1]]
    if point:
        stations.append((body[-1], 1.0))
        stations.append((1.0 - cap * 0.3, 0.55))
    else:
        for i in range(cap_rings, 0, -1):
            a = i / cap_rings * math.pi / 2
            stations.append((1 - cap * (1 - math.cos(a)), math.sin(a)))
    loops = []
    for z, scale in stations:
        cx, cy = centre(z)
        points, colours = [], []
        for k in range(sides):
            th = TAU * k / sides
            r, colour = shape(z, th)
            r *= scale
            points.append((cx + r * math.cos(th), cy + r * math.sin(th), length * (0.5 - z)))
            colours.append(colour)
        loops.append(mesh.ring(points, colours))
    for a, b in zip(loops, loops[1:]):
        mesh.bridge(a, b)
    for z, loop, flip in ((0.0, loops[0], False), (1.0, loops[-1], True)):
        cx, cy = centre(z)
        colour = shape(z, 0.0)[1]
        pole = mesh.ring([(cx, cy, length * (0.5 - z))], [colour])[0]
        mesh.fan(pole, loop, flip)
    return mesh.finish()


def skin(rng):
    """The colour of a patch of skin from a few masks; every limb shares the recipe so they read as one body."""
    blotch, sallow, dirt = Field(rng, 6, (0.5, 2.6), 2), Field(rng, 5, (0.4, 2.2), 2), Field(rng, 7, (1.5, 6.0), 4)

    def colour(z, th, raw=0.0, cord=0.0, vein=0.0, sore=0.0, pit=0.0, under=0.0):
        c = mix(SKIN, SALLOW, 0.5 * smooth(-0.1, 0.7, sallow(z, th)))
        c = mix(c, BRUISE, 0.5 * smooth(0.2, 0.85, blotch(z, th)))
        c = mix(c, SINEW, 0.4 * cord)
        c = mix(c, RAW, 0.62 * raw)
        c = mix(c, GRIME, 0.55 * under + 0.45 * pit + 0.34 * smooth(0.15, 0.85, dirt(z, th)))
        c = mix(c, VEIN, 0.85 * vein)
        return mix(c, SORE, sore)
    return colour


def make_bone(name, seed, length=20.0, radius=1.0):
    rng = random.Random(seed)
    lump, fine = Field(rng, 8, (1.5, 7.0), 5), Field(rng, 10, (7.0, 19.0), 9)
    colour = skin(rng)
    cords = [(rng.uniform(0, TAU), rng.uniform(-1.3, 1.3), rng.uniform(0.7, 1.2)) for _ in range(4)]
    veins = [{'at': rng.uniform(0, TAU), 'amp': rng.uniform(0.3, 0.7), 'freq': rng.uniform(1.3, 3.2), 'phase': rng.uniform(0, TAU),
              'drift': rng.uniform(-1.6, 1.6), 'from': rng.uniform(0.02, 0.3), 'to': rng.uniform(0.6, 0.98),
              'fork': rng.uniform(0.35, 0.65), 'side': rng.choice((-1, 1))} for _ in range(5)]
    belly, belly_side = rng.uniform(0.24, 0.42), rng.uniform(0, TAU)
    bow_dir, bow = rng.uniform(0, TAU), rng.uniform(0.2, 0.5)
    sores = [(rng.uniform(0.1, 0.9), rng.uniform(0, TAU), rng.uniform(0.3, 0.7)) for _ in range(rng.randint(4, 7))]

    def centre(z):
        b = bow * math.sin(math.pi * z)
        return b * math.cos(bow_dir), b * math.sin(bow_dir)

    def shape(z, th):
        ends = abs(2 * z - 1) ** 2.6
        r = radius * (0.60 + 0.40 * ends)                          # a thin shaft between two swollen heads
        r += radius * 0.24 * math.exp(-((z - belly) / 0.15) ** 2) * max(0.0, math.cos(th - belly_side)) ** 2
        cord = 0.0
        for at, twist, strength in cords:
            cord = max(cord, strength * math.exp(-(angdist(th, at + twist * z) / 0.2) ** 2))
        cord *= 1 - ends
        vein = 0.0
        for v in veins:
            if v['from'] < z < v['to']:
                fade = smooth(v['from'], v['from'] + 0.06, z) * (1 - smooth(v['to'] - 0.06, v['to'], z))
                path = v['at'] + v['amp'] * math.sin(TAU * v['freq'] * z + v['phase']) + v['drift'] * z
                vein = max(vein, fade * math.exp(-(angdist(th, path) * r / 0.12) ** 2))
                if z > v['fork']:                                  # a branch that leaves the main vessel and thins out
                    off = v['side'] * 1.6 * (z - v['fork']) / max(0.05, v['to'] - v['fork'])
                    vein = max(vein, 0.7 * fade * math.exp(-(angdist(th, path + off) * r / 0.085) ** 2))
        sore = 0.0
        for sz, sa, size in sores:
            d = math.hypot((z - sz) * length, angdist(th, sa) * r)
            sore = max(sore, math.exp(-(d / size) ** 2))
        bump = lump(z, th)
        r += radius * (0.06 * cord + 0.055 * bump + 0.016 * fine(z, th)) + 0.055 * vein - 0.05 * sore
        return r, colour(z, th, raw=ends ** 0.8, cord=cord, vein=vein, sore=sore * 0.9, pit=max(0.0, -bump))
    return tube(name, length, 44, 22, centre, shape, cap=0.03)


def make_digit(name, seed, length, radius, claw=False):
    rng = random.Random(seed)
    lump, fine = Field(rng, 6, (1.0, 4.0), 3), Field(rng, 8, (4.0, 10.0), 6)
    colour = skin(rng)
    creases = [0.07, 0.11, 0.15] + ([] if claw else [0.88, 0.92])

    def centre(z):
        if claw:
            return 0.0, -0.95 * z ** 2.1                           # hooks down toward the palm side
        return 0.0, 0.10 * math.sin(math.pi * z)

    def shape(z, th):
        top = math.sin(th)                                         # +1 on the back of the digit
        if claw:
            r = radius * (1.25 - 0.3 * smooth(0.0, 0.2, z)) * (1 - z) ** 0.72 + 0.035
            nail = smooth(0.34, 0.5, z) * smooth(-0.15, 0.35, top)
            r += 0.05 * nail * (1 - z)
        else:
            knuckle = math.exp(-(z / 0.13) ** 2) + 0.55 * math.exp(-((1 - z) / 0.1) ** 2)
            r = radius * (0.74 + 0.5 * knuckle)
            nail = 0.0
        fold = max(math.exp(-((z - c) / 0.012) ** 2) for c in creases) * smooth(-0.2, 0.5, top)
        r += radius * (0.07 * lump(z, th) + 0.02 * fine(z, th)) - radius * 0.1 * fold
        raw = max(math.exp(-(z / 0.16) ** 2), 0.0 if claw else 0.7 * math.exp(-((1 - z) / 0.12) ** 2))
        c = colour(z, th, raw=raw, pit=fold, under=0.55 * smooth(0.1, 0.9, -top))
        if claw:
            c = mix(c, mix(NAIL, NAIL_TIP, smooth(0.5, 0.95, z)), nail)
            c = mix(c, NAIL_TIP, smooth(0.86, 1.0, z))
        return r, c
    return tube(name, length, 20, 12, centre, shape, cap=0.05, cap_rings=3, point=claw)


def make_elbow(name, seed, radius=1.6):
    rng = random.Random(seed)
    lump, fine = Field(rng, 9, (0.5, 2.5), 4), Field(rng, 10, (3.0, 8.0), 7)
    colour = skin(rng)
    spurs = [(rng.uniform(0.28, 0.72), rng.uniform(0, TAU), rng.uniform(0.2, 0.36), rng.uniform(0.3, 0.5)) for _ in range(4)]
    folds = [rng.uniform(0.18, 0.82) for _ in range(4)]
    sores = [(rng.uniform(0.2, 0.8), rng.uniform(0, TAU)) for _ in range(4)]
    mesh = Mesh(name)
    loops, rings, sides = [], 16, 20
    for j in range(1, rings):
        z = j / rings
        lat = math.pi * z
        points, colours = [], []
        for k in range(sides):
            th = TAU * k / sides
            spur = sum(h * math.exp(-(math.hypot((z - sz) * math.pi, angdist(th, sa) * math.sin(lat)) / w) ** 2) for sz, sa, h, w in spurs)
            fold = max(math.exp(-((z - f) / 0.022) ** 2) for f in folds)
            sore = max(math.exp(-(math.hypot((z - sz) * math.pi, angdist(th, sa) * math.sin(lat)) / 0.2) ** 2) for sz, sa in sores)
            bump = lump(z, th)
            r = radius * (1 + 0.17 * bump + 0.03 * fine(z, th) + spur - 0.07 * fold - 0.012 * sore)
            # not a ball: a swollen joint is broader than it is deep, and lopsided
            points.append((r * math.sin(lat) * math.cos(th), 0.8 * r * math.sin(lat) * math.sin(th), r * math.cos(lat) * 0.92))
            colours.append(colour(z, th, raw=0.5 + 0.5 * spur, pit=max(fold, max(0.0, -bump)), sore=sore * 0.55))
        loops.append(mesh.ring(points, colours))
    for a, b in zip(loops, loops[1:]):
        mesh.bridge(a, b)
    for z, loop, flip in ((0.0, loops[0], False), (1.0, loops[-1], True)):
        pole = mesh.ring([(0.0, 0.0, radius * 0.92 * (1 if z == 0 else -1))], [colour(z, 0.0, raw=0.6)])[0]
        mesh.fan(pole, loop, flip)
    return mesh.finish()


def make_palm(name, seed):
    rng = random.Random(seed)
    lump, fine = Field(rng, 7, (0.6, 2.4), 3), Field(rng, 9, (2.5, 7.0), 8)
    colour = skin(rng)
    width, thick, length = PALM
    knuckles = [d['root'][0] for d in DIGITS if d['kind'] == 'finger']
    lines = [(rng.uniform(0.25, 0.8), rng.uniform(-0.5, 0.5)) for _ in range(3)]

    def half(z):                                                    # half the width: a narrow wrist, a broad row of knuckles
        return width / 2 * (0.40 + 0.60 * smooth(0.0, 0.7, z)) * (1 - 0.10 * smooth(0.86, 1.0, z))

    def shape(z, th):
        w, t = half(z), thick / 2 * (1.0 - 0.22 * z)
        cx, sy = math.cos(th), math.sin(th)
        ex = (abs(cx) ** 0.86) * (1 if cx >= 0 else -1)            # between a slab and an ellipse
        ey = (abs(sy) ** 0.86) * (1 if sy >= 0 else -1)
        x, y = w * ex, t * ey
        y *= 0.72 + 0.42 * math.exp(-(x / (0.62 * w)) ** 2)        # thick down the middle, thin at the edges
        back, under = smooth(0.0, 0.5, sy), smooth(0.0, 0.5, -sy)
        cord = 0.0
        for kx in knuckles:                                        # a tendon from the wrist to each knuckle
            at = kx * (0.22 + 0.78 * z)
            cord = max(cord, math.exp(-((x - at) / 0.2) ** 2))
        head = max(math.exp(-((x - kx) / 0.44) ** 2 - ((z - 0.9) / 0.1) ** 2) for kx in knuckles)
        vein = 0.0
        for i, kx in enumerate(knuckles[:-1]):                     # vessels in the hollows between the tendons
            at = (kx + knuckles[i + 1]) / 2 * (0.3 + 0.7 * z) + 0.12 * math.sin(TAU * 1.7 * z + i)
            vein = max(vein, smooth(0.08, 0.2, z) * (1 - smooth(0.7, 0.86, z)) * math.exp(-((x - at) / 0.1) ** 2))
        hollow = math.exp(-(x / 1.25) ** 2 - ((z - 0.5) / 0.3) ** 2)
        crease = max(math.exp(-((z - c - s * x / width) / 0.018) ** 2) for c, s in lines)
        bump = lump(z, th)
        # the back rises over its tendons and knuckles; the underside is hollowed and creased (it is at -y, so
        # adding there pushes the surface up into the hand)
        y += back * (0.3 * cord * (0.25 + 0.75 * z) + 0.26 * head + 0.09 * vein - 0.1 * (1 - cord) * smooth(0.25, 0.8, z)) \
            + under * (0.34 * hollow + 0.07 * crease)
        grow = 1 + 0.05 * bump + 0.015 * fine(z, th)
        x, y = x * grow, y * grow
        raw = max(0.9 * head * back, 0.5 * math.exp(-(z / 0.12) ** 2), 0.45 * under * hollow)
        c = colour(z, th, raw=raw, cord=cord * back * (0.3 + 0.7 * z), vein=vein * back, pit=under * crease, under=0.6 * under)
        return math.hypot(x, y), c, math.atan2(y, x)

    shaped = shape
    mesh = Mesh(name)
    rings, sides, cap, cap_rings = 26, 30, 0.07, 4
    stations = [(cap * (1 - math.cos(i / cap_rings * math.pi / 2)), math.sin(i / cap_rings * math.pi / 2)) for i in range(1, cap_rings + 1)]
    body = [cap + (1 - 2 * cap) * j / (rings - 1) for j in range(rings)]
    stations += [(z, 1.0) for z in body[1:-1]]
    stations += [(1 - cap * (1 - math.cos(i / cap_rings * math.pi / 2)), math.sin(i / cap_rings * math.pi / 2)) for i in range(cap_rings, 0, -1)]
    loops = []
    for z, scale in stations:
        points, colours = [], []
        for k in range(sides):
            r, c, at = shaped(z, TAU * k / sides)
            points.append((r * scale * math.cos(at), r * scale * math.sin(at), length * (0.5 - z)))
            colours.append(c)
        loops.append(mesh.ring(points, colours))
    for a, b in zip(loops, loops[1:]):
        mesh.bridge(a, b)
    for z, loop, flip in ((0.0, loops[0], False), (1.0, loops[-1], True)):
        pole = mesh.ring([(0.0, 0.0, length * (0.5 - z))], [shaped(z, 0.0)[1]])[0]
        mesh.fan(pole, loop, flip)
    return mesh.finish()


def make_eye(name, seed):
    """One iris, a shallow dome one stud across that faces -z. Painted from the pupil outward: a hot ring, fibres,
    a dark rim. The client puts the pupil on it and opens it by scaling."""
    rng = random.Random(seed)
    fibre = [(rng.uniform(0.3, 1.0), rng.randint(9, 53), rng.uniform(0, TAU)) for _ in range(9)]
    total = sum(f[0] for f in fibre)
    HOT, GOLD, AMBER, RIM = (1.0, 0.97, 0.72), (1.0, 0.80, 0.22), (0.95, 0.42, 0.05), (0.30, 0.07, 0.01)
    mesh = Mesh(name)
    rings, sides = 14, 48
    loops = []
    for j in range(1, rings + 1):
        rho = j / rings
        points, colours = [], []
        for k in range(sides):
            th = TAU * k / sides
            f = 0.5 + 0.5 * sum(a * math.sin(n * th + p) for a, n, p in fibre) / total
            c = mix(GOLD, AMBER, smooth(0.25, 0.8, rho) * (0.55 + 0.6 * f))
            c = mix(c, HOT, (1 - smooth(0.12, 0.42, rho)) * (0.6 + 0.4 * f))
            c = mix(c, RIM, smooth(0.80, 0.98, rho + 0.05 * (f - 0.5)))
            points.append((0.5 * rho * math.cos(th), 0.5 * rho * math.sin(th), -0.11 * (1 - rho * rho)))
            colours.append(c)
        loops.append(mesh.ring(points, colours))
    for a, b in zip(loops, loops[1:]):
        mesh.bridge(a, b)
    front = mesh.ring([(0.0, 0.0, -0.11)], [HOT])[0]
    mesh.fan(front, loops[0], False)
    back = mesh.ring([(0.0, 0.0, 0.03)], [RIM])[0]
    mesh.fan(back, loops[-1], True)
    return mesh.finish()


# ---- how the game poses a hand: the client's `poseHand` is this, line for line ---------------------------------------
POSES = {                        # the three joints of a finger, degrees; negative closes toward the palm
    'crawl': (24.0, -62.0, -38.0),
    'open': (40.0, -22.0, -16.0),
    'cage': (-50.0, -40.0, -20.0),
    'grip': (-62.0, -62.0, -40.0),
}


def digit_frames(palm, digit, curls, splay=1.0):
    """The world frame of each joint's piece (a frame looks down its own -z)."""
    frame = palm @ Matrix.Translation(digit['root']) @ Matrix.Rotation(math.radians(digit['yaw'] * splay), 4, 'Y')
    out = []
    for length, curl in zip(digit['lengths'], curls):
        frame = frame @ Matrix.Rotation(math.radians(curl), 4, 'X')
        out.append((frame @ Matrix.Translation((0, 0, -length / 2)), length))
        frame = frame @ Matrix.Translation((0, 0, -length))
    return out


def look(at, to, up=(0, 1, 0)):
    """CFrame.lookAt: -z toward `to`."""
    back = (Vector(at) - Vector(to)).normalized()
    right = Vector(up).cross(back)
    right = right.normalized() if right.length > 1e-6 else Vector((1, 0, 0))
    top = back.cross(right)
    m = Matrix.Identity(4)
    for i in range(3):
        m[i][0], m[i][1], m[i][2], m[i][3] = right[i], top[i], back[i], at[i]
    return m


# ---- Blender ---------------------------------------------------------------------------------------------------------
TO_BLENDER = Matrix.Rotation(math.radians(90), 4, 'X')            # Roblox (x, y, z) -> Blender (x, -z, y)


def material():
    mat = bpy.data.materials.new('ClammySkin')
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = next(n for n in nodes if n.type == 'BSDF_PRINCIPLED')
    attr = nodes.new('ShaderNodeVertexColor')
    attr.layer_name = 'Col'
    links.new(attr.outputs['Color'], bsdf.inputs['Base Color'])
    bsdf.inputs['Roughness'].default_value = 0.32
    return mat


def glow():
    mat = bpy.data.materials.new('EyeGlow')
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = next(n for n in nodes if n.type == 'BSDF_PRINCIPLED')
    attr = nodes.new('ShaderNodeVertexColor')
    attr.layer_name = 'Col'
    links.new(attr.outputs['Color'], bsdf.inputs['Base Color'])
    for key in ('Emission Color', 'Emission'):
        if key in bsdf.inputs:
            links.new(attr.outputs['Color'], bsdf.inputs[key])
    if 'Emission Strength' in bsdf.inputs:
        bsdf.inputs['Emission Strength'].default_value = 4.0
    return mat


def to_linear(c):
    return tuple(v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in c)


def blender_mesh(mesh, mat):
    data = bpy.data.meshes.new(mesh.name)
    data.from_pydata(mesh.verts, [], mesh.tris)
    data.update()
    layer = data.color_attributes.new('Col', 'FLOAT_COLOR', 'POINT')
    for i, c in enumerate(mesh.colours):
        layer.data[i].color = (*to_linear(c), 1.0)
    for poly in data.polygons:
        poly.use_smooth = True
    data.materials.append(mat)
    return data


def place(name, data, matrix, scale, parent, collection):
    obj = bpy.data.objects.new(name, data)
    obj.matrix_world = TO_BLENDER @ matrix @ Matrix.Diagonal((*scale, 1.0))
    collection.objects.link(obj)
    return obj


def build_scene(meshes):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    mats = {'skin': material(), 'eye': glow()}
    datas = {name: blender_mesh(m, mats['eye' if name == 'eye' else 'skin']) for name, m in meshes.items()}
    pieces = bpy.data.collections.new('Pieces')
    arm = bpy.data.collections.new('Arm (as the game poses it)')
    scene.collection.children.link(pieces)
    scene.collection.children.link(arm)
    x = -24.0
    for name, mesh in meshes.items():                              # the kit, laid out side by side
        scale = (5.0, 5.0, 5.0) if name == 'eye' else (1.0, 1.0, 1.0)
        place(name, datas[name], Matrix.Translation((x, 3.0, 60.0)), scale, None, pieces)
        x += max(mesh.size[0] * scale[0], 3.0) + 2.5

    # one arm: six bones folded the way the client folds them, the hand crawling on its fingertips
    joints = [Vector(p) for p in ((0, 13, 40), (7, 3.5, 24), (-3, 12, 8), (5, 3.2, -9), (-2, 9.5, -24), (2, 4.4, -37), (0, 3.6, -44))]
    for i, (a, b) in enumerate(zip(joints, joints[1:])):
        last = i == len(joints) - 2
        dist = (b - a).length
        key = ('bone_a', 'bone_b', 'bone_c')[i % 3]
        t = 1.35 - 0.11 * i
        size = meshes[key].size
        place(f'Bone{i}', datas[key], look((a + b) / 2, b) @ Matrix.Rotation(i * 2.1, 4, 'Z'),
              (t, t, (dist + 0.6) / size[2]), None, arm)
        if not last:
            k = 0.62 + 0.3 * t
            place(f'Elbow{i}', datas['elbow'], Matrix.Translation(b) @ Matrix.Rotation(i * 1.3, 4, 'Y'), (k, k, k), None, arm)
    wrist = joints[-1]
    palm = Matrix.Translation(wrist + Vector((0, -0.4, -PALM[2] / 2 + 0.4)))
    place('Palm', datas['palm'], palm @ Matrix.Translation(meshes['palm'].offset), (1, 1, 1), None, arm)
    for n, digit in enumerate(DIGITS):
        curls = [c + 9 * math.sin(n * 1.7 + j) for j, c in enumerate(POSES['crawl'])]
        for j, (frame, length) in enumerate(digit_frames(palm, digit, curls)):
            key = 'claw' if j == 2 else digit['kind']
            size = meshes[key].size
            t = digit['thick'] * (1.0 - 0.12 * j) / 0.74
            place(f'Digit{n}_{j}', datas[key], frame @ Matrix.Translation((0, meshes[key].offset[1] * t, 0)),
                  (t, t, length * 1.06 / size[2]), None, arm)
    return scene


def render(scene, path, eye, target, lens=32):
    cam_data = bpy.data.cameras.new('Camera')
    cam_data.lens = lens
    cam = bpy.data.objects.new('Camera', cam_data)
    scene.collection.objects.link(cam)
    e, t = TO_BLENDER @ Vector(eye), TO_BLENDER @ Vector(target)
    cam.location = e
    cam.rotation_euler = (t - e).to_track_quat('-Z', 'Y').to_euler()
    scene.camera = cam
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam)


def main():
    args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    meshes = {
        'bone_a': make_bone('bone_a', 11), 'bone_b': make_bone('bone_b', 23), 'bone_c': make_bone('bone_c', 37),
        'elbow': make_elbow('elbow', 5),
        'palm': make_palm('palm', 3),
        'finger': make_digit('finger', 7, 3.0, 0.37),
        'thumb': make_digit('thumb', 13, 2.6, 0.42),
        'claw': make_digit('claw', 17, 2.6, 0.31, claw=True),
        'eye': make_eye('eye', 29),
    }
    for sub in ('blend', 'export', 'preview'):
        (OUT / sub).mkdir(parents=True, exist_ok=True)
    export = {'hand': {'palm': PALM, 'digits': DIGITS, 'poses': POSES}, 'meshes': {}}
    total = 0
    for name, m in meshes.items():
        export['meshes'][name] = {
            'size': [round(v, 4) for v in m.size], 'offset': [round(v, 4) for v in m.offset],
            'verts': [round(c * 1000) for v in m.verts for c in v],
            'normals': [round(c * 1000) for n in m.normals for c in n],
            'colours': [max(0, min(255, round(c * 255))) for col in m.colours for c in col],
            'tris': [i for t in m.tris for i in t],
        }
        total += len(m.tris)
        print(f'{name:8s} {len(m.verts):5d} verts {len(m.tris):5d} tris  size {tuple(round(v, 2) for v in m.size)}')
    path = OUT / 'export' / 'reach_meshes.json'
    path.write_text(json.dumps(export, separators=(',', ':')))
    print('export', path.stat().st_size, 'bytes,', total, 'triangles in the kit')

    scene = build_scene(meshes)
    world = bpy.data.worlds.new('Dark')
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == 'BACKGROUND')
    bg.inputs['Color'].default_value = (0.012, 0.012, 0.016, 1)
    scene.world = world
    for name, at, power, colour in (('Key', (16, 26, -52), 9000, (1.0, 0.93, 0.82)), ('Rim', (-22, 10, 20), 5000, (0.55, 0.7, 1.0)),
                                    ('Kit', (-6, 22, 50), 9000, (1.0, 0.96, 0.9))):
        light = bpy.data.lights.new(name, 'POINT')
        light.energy, light.color, light.shadow_soft_size = power, colour, 2.0
        obj = bpy.data.objects.new(name, light)
        obj.location = TO_BLENDER @ Vector(at)
        scene.collection.objects.link(obj)
    floor = bpy.data.meshes.new('Floor')
    floor.from_pydata([(-80, -80, 0), (80, -80, 0), (80, 80, 0), (-80, 80, 0)], [], [(0, 1, 2, 3)])
    ground = bpy.data.objects.new('Floor', floor)
    dark = bpy.data.materials.new('Asphalt')
    dark.use_nodes = True
    shader = next(n for n in dark.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    shader.inputs['Base Color'].default_value = (0.03, 0.03, 0.035, 1)
    shader.inputs['Roughness'].default_value = 0.55
    floor.materials.append(dark)
    scene.collection.objects.link(ground)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT / 'blend' / 'Lobby_Reach.blend'))
    print('saved', OUT / 'blend' / 'Lobby_Reach.blend')

    if '--no-render' not in args:
        engines = [e for e in ('BLENDER_EEVEE_NEXT', 'BLENDER_EEVEE', 'CYCLES')]
        for engine in engines:
            try:
                scene.render.engine = engine
                break
            except TypeError:
                continue
        if scene.render.engine == 'CYCLES':
            scene.cycles.samples = 48
        scene.render.resolution_x, scene.render.resolution_y = 1280, 720
        scene.view_settings.view_transform = 'Standard'
        print('render engine', scene.render.engine)
        render(scene, OUT / 'preview' / 'hand.png', (9.5, 6.5, -62), (0, 3.0, -45), 35)
        render(scene, OUT / 'preview' / 'arm.png', (38, 12, -20), (0, 7, 0), 28)
        render(scene, OUT / 'preview' / 'arm_front.png', (6, 5.5, -78), (0, 6, -20), 40)
        render(scene, OUT / 'preview' / 'kit.png', (-6, 34, 52), (-6, 3, 60), 30)


main()
