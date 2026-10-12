"""The mall lobby's Halloween dressing: a kit of low-polygon props, where each one stands, the sale signs, a .blend.

    /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --threads 2 --python tools/lobby_mall/build_halloween.py
    /usr/local/bin/python3 tools/lobby_mall/install_halloween.py          # Studio in Edit: uploads the kit, places it

LOBBY_HALLOWEEN_20261013. The owner: "Via blender I want you to make the lobby be halloween decorated 90s middle class
mall style, with jack o lanterns, and such", with "halloween sale signs around the lobby and at the shop saying 66,6
halloween discount on everything" and a re-entry package, three for the price of one. The look follows the concept
pictures in artifacts/lobby-halloween-20261013/concepts (H01: pennant strings across the hall, crepe swags from pier
to pier, corn stalks and lit pumpkins at the piers, ghosts and bats on lines, an orange banner over the stand).

Everything is modelled here from plain solids with a colour per vertex, in studs (x right, y up, a prop's front is -z),
and laid out in the mall's own build coordinates (artifacts/lobby-mall-20261011/build/mall.json; the importer adds the
same OFFSET the mall has). Nothing here collides with the queue pads, the boards or the walking lanes; check_halloween()
proves the rules that matter and stops the build if one is broken.
Writes artifacts/lobby-halloween-20261013/build/: halloween.json (kit meshes x1000, placements, signs, lights),
halloween.blend (the kit and the dressed hall, the mall as plain boxes), kit.png and four views of the hall.
"""
import json, math, random
from pathlib import Path
import bpy, numpy as np
from mathutils import Vector, Matrix
from mathutils.geometry import tessellate_polygon

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'artifacts' / 'lobby-halloween-20261013' / 'build'
MALL = json.loads((ROOT / 'artifacts' / 'lobby-mall-20261011' / 'build' / 'mall.json').read_text())
FONT = '/System/Library/Fonts/Supplemental/DIN Condensed Bold.ttf'

ORANGE, DEEP, BLACK, PURPLE = (236, 120, 26), (204, 92, 16), (26, 22, 26), (112, 54, 152)
STRAW, TWINE, STALK, HUSK = (214, 182, 96), (150, 112, 52), (198, 172, 98), (168, 146, 80)
WHITE, BONE, SHEET = (245, 245, 245), (238, 234, 220), (236, 236, 228)
SALE_ORANGE, SALE_YELLOW, SALE_RED = (240, 112, 20), (250, 214, 40), (214, 52, 36)
FLOOR, CEIL, WING_CEIL, TAPE_Z = 30.0, 57.04, 46.0, -621.0
SALE, OFF, REENTRY, THREE = 'HALLOWEEN SALE', '66.6% OFF EVERYTHING', 'RE-ENTRY', '3 FOR 1'


def turn_y(deg):
    a = math.radians(deg)
    return np.array([[math.cos(a), 0, math.sin(a)], [0, 1, 0], [-math.sin(a), 0, math.cos(a)]])


def turn_x(deg):
    a = math.radians(deg)
    return np.array([[1, 0, 0], [0, math.cos(a), -math.sin(a)], [0, math.sin(a), math.cos(a)]])


def turn_z(deg):
    a = math.radians(deg)
    return np.array([[math.cos(a), -math.sin(a), 0], [math.sin(a), math.cos(a), 0], [0, 0, 1]])


class Mesh:
    """One prop. `double`: drawn from both sides (MeshPart.DoubleSided), for cloth, paper and leaves."""

    def __init__(self, name, double=False, collide=False, material='SmoothPlastic'):
        self.name, self.double, self.collide, self.material = name, double, collide, material
        self.v, self.n, self.c, self.t = [], [], [], []

    def add(self, points, norms, colour, faces):
        base = len(self.v)
        points, norms = [np.array(p, float) for p in points], [np.array(n, float) for n in norms]
        self.v.extend(points); self.n.extend(norms)
        self.c.extend(colour if isinstance(colour, list) else [colour] * len(points))
        for a, b, c in faces:                      # every triangle is wound to agree with its normals
            flat = np.cross(points[b] - points[a], points[c] - points[a])
            if np.dot(flat, norms[a] + norms[b] + norms[c]) < 0: b, c = c, b
            self.t.append((base + a, base + b, base + c))

    def box(self, centre, size, colour, turn=None):
        c, h = np.array(centre, float), np.array(size, float) / 2
        turn = np.eye(3) if turn is None else turn
        for axis in range(3):
            for sign in (-1, 1):
                n = np.zeros(3); n[axis] = sign
                u, v = np.zeros(3), np.zeros(3)
                u[(axis + 1) % 3], v[(axis + 2) % 3] = 1, 1
                quad = [n * h + su * u * h + sv * v * h for su, sv in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
                self.add([c + turn @ p for p in quad], [turn @ n] * 4, colour, [(0, 1, 2), (0, 2, 3)])

    def rod(self, a, b, ra, rb, colour, sides=10, caps=True):
        a, b = np.array(a, float), np.array(b, float)
        axis = (b - a) / np.linalg.norm(b - a)
        side = np.cross(axis, [0, 1, 0] if abs(axis[1]) < 0.9 else [1, 0, 0]); side /= np.linalg.norm(side)
        up = np.cross(axis, side)
        ring = [side * math.cos(t) + up * math.sin(t) for t in np.linspace(0, math.tau, sides, endpoint=False)]
        faces = []
        for i in range(sides):
            j = (i + 1) % sides
            faces += [(i, j, sides + j), (i, sides + j, sides + i)]
        self.add([a + r * ra for r in ring] + [b + r * rb for r in ring], ring + ring, colour, faces)
        if caps:
            for centre, r, n in ((a, ra, -axis), (b, rb, axis)):
                if r > 1e-6:
                    self.add([centre] + [centre + q * r for q in ring], [n] * (sides + 1), colour, [(0, 1 + i, 1 + (i + 1) % sides) for i in range(sides)])

    def ball(self, centre, radii, colour, rings=6, sides=10):
        c = np.array(centre, float)
        radii = np.array([radii] * 3 if np.isscalar(radii) else radii, float)
        points, norms, faces = [], [], []
        for i in range(rings + 1):
            phi = math.pi * i / rings
            for j in range(sides):
                n = np.array([math.sin(phi) * math.cos(math.tau * j / sides), math.cos(phi), math.sin(phi) * math.sin(math.tau * j / sides)])
                points.append(c + n * radii)
                m = n / radii; norms.append(m / np.linalg.norm(m))
        for i in range(rings):
            for j in range(sides):
                p, q = i * sides + j, i * sides + (j + 1) % sides
                if i > 0: faces.append((p, q, q + sides))
                if i < rings - 1: faces.append((p, q + sides, p + sides))
        self.add(points, norms, colour, faces)

    def flat(self, outline, colour, z=0.0):
        """A paper shape in the prop's xy plane at depth z, facing the front (-z)."""
        points = [np.array([x, y, z]) for x, y in outline]
        faces = tessellate_polygon([[Vector(p) for p in points]])
        self.add(points, [np.array([0, 0, -1.0])] * len(points), colour, [tuple(f) for f in faces])

    def strip(self, a, b, width, colour, z=0.0):
        a, b = np.array(a, float), np.array(b, float)
        along = (b - a) / np.linalg.norm(b - a)
        w = np.array([-along[1], along[0]]) * width / 2
        self.flat([a - w, b - w, b + w, a + w], colour, z)

    def disc(self, centre, rx, ry, colour, z=0.0, sides=10):
        self.flat([(centre[0] + rx * math.cos(math.tau * i / sides), centre[1] + ry * math.sin(math.tau * i / sides)) for i in range(sides)], colour, z)

    def ribbon(self, points, widths, colour, back=None):
        """A strip through `points`, `widths` the half-width vector at each; `back` paints the other side another colour."""
        points, widths = [np.array(p, float) for p in points], [np.array(w, float) for w in widths]
        for i in range(len(points) - 1):
            quad = [points[i] - widths[i], points[i + 1] - widths[i + 1], points[i + 1] + widths[i + 1], points[i] + widths[i]]
            n = np.cross(quad[1] - quad[0], quad[3] - quad[0]); n /= np.linalg.norm(n)
            self.add(quad, [n] * 4, colour[i % len(colour)] if isinstance(colour, list) else colour, [(0, 1, 2), (0, 2, 3)])
            if back is not None: self.add(quad, [-n] * 4, back, [(0, 1, 2), (0, 2, 3)])

    def export(self):
        V, N, C, T = np.array(self.v), np.array(self.n), np.array(self.c), np.array(self.t)
        middle = (V.min(0) + V.max(0)) / 2
        return {'centre': [round(float(v), 4) for v in middle], 'size': [round(float(v), 4) for v in np.maximum(V.max(0) - V.min(0), 0.02)],
                'double': self.double, 'collide': self.collide, 'material': self.material, 'triangles': len(T),
                'verts': np.rint((V - middle) * 1000).astype(int).ravel().tolist(), 'normals': np.rint(N * 1000).astype(int).ravel().tolist(),
                'colours': C.astype(int).ravel().tolist(), 'tris': T.ravel().tolist()}


# ---------------------------------------------------------------------------------------------------------- the kit
def pumpkins():
    """A blow-mould jack-o'-lantern, radius 1 (the layout scales it). Its face is painted black on the body; a second
    mesh is the same face a hair further out, which the game makes glow on the lit ones."""
    body, face = Mesh('pumpkin', collide=True), Mesh('pumpkin_face', material='Neon')
    R, H, S, RINGS = 1.0, 1.5, 16, 6       # 70 of them stand in the hall: kept light
    rib = lambda th: 0.93 + 0.07 * abs(math.sin(4 * th)) ** 0.6
    P, N = np.zeros((RINGS + 1, S, 3)), np.zeros((RINGS + 1, S, 3))
    for i in range(RINGS + 1):
        phi = -math.pi / 2 + math.pi * i / RINGS
        for j in range(S):
            th = math.tau * j / S
            r = R * max(math.cos(phi), 0) ** 0.75 * rib(th)
            y = H / 2 * (1 + math.sin(phi)) - (0.09 * H if i == RINGS else 0)
            P[i, j] = (r * math.sin(th), y, -r * math.cos(th))
            n = np.array([P[i, j][0] / R ** 2, (y - H / 2) / (H / 2) ** 2, P[i, j][2] / R ** 2])
            N[i, j] = n / np.linalg.norm(n) if np.linalg.norm(n) > 1e-6 else (0, 1 if i else -1, 0)
    N[0, :], N[RINGS, :] = (0, -1, 0), (0, 1, 0)
    points, norms, colours, faces = [], [], [], []
    for i in range(RINGS + 1):
        for j in range(S):
            points.append(P[i, j]); norms.append(N[i, j]); colours.append(DEEP if j % 2 == 0 else ORANGE)
    for i in range(RINGS):
        for j in range(S):
            p, q = i * S + j, i * S + (j + 1) % S
            if i > 0: faces.append((p, q, q + S))
            if i < RINGS - 1: faces.append((p, q + S, p + S))
    body.add(points, norms, colours, faces)
    body.rod((0, H * 0.88, 0), (0.1, H * 1.16, 0.05), 0.15, 0.09, (96, 88, 44), 6)

    def surface(th, h, lift):
        fj, fi = (th / math.tau * S) % S, (math.asin(max(-1, min(1, 2 * h - 1))) + math.pi / 2) / math.pi * RINGS
        j0, i0 = int(fj), min(int(fi), RINGS - 1)
        u, v = fj - j0, fi - i0
        mix = lambda A: (A[i0, j0] * (1 - u) + A[i0, (j0 + 1) % S] * u) * (1 - v) + (A[i0 + 1, j0] * (1 - u) + A[i0 + 1, (j0 + 1) % S] * u) * v
        n = mix(N); n = n / np.linalg.norm(n)
        return mix(P) + n * lift, n

    def paint(tri, depth=1):
        if depth:
            a, b, c = [np.array(p, float) for p in tri]
            ab, bc, ca = (a + b) / 2, (b + c) / 2, (c + a) / 2
            for small in ((a, ab, ca), (ab, b, bc), (ca, bc, c), (ab, bc, ca)): paint(small, depth - 1)
            return
        for mesh, lift, colour in ((body, 0.012, (24, 14, 8)), (face, 0.03, WHITE)):
            pts = [surface(th, h, lift) for th, h in tri]
            mesh.add([p for p, _ in pts], [n for _, n in pts], colour, [(0, 1, 2)])

    for sign in (-1, 1):
        paint([(sign * 0.44, 0.56), (sign * 0.14, 0.58), (sign * 0.30, 0.76)])
    paint([(-0.07, 0.44), (0.07, 0.44), (0, 0.53)])
    edge = np.linspace(-0.52, 0.52, 9)
    low = lambda a: 0.20 + 0.13 * (a / 0.52) ** 2
    high = lambda a, k: 0.33 + 0.09 * (a / 0.52) ** 2 - (0.055 if k % 2 else 0)
    for k in range(8):
        a, b = edge[k], edge[k + 1]
        paint([(a, low(a)), (b, low(b)), (b, high(b, k + 1))], 0)
        paint([(a, low(a)), (b, high(b, k + 1)), (a, high(a, k))], 0)
    return body, face


def hay_bale():
    m = Mesh('hay_bale', collide=True)
    m.box((0, 1, 0), (4, 2, 2), STRAW)
    for x in (-1.1, 1.1): m.box((x, 1, 0), (0.12, 2.05, 2.05), TWINE)
    rnd = random.Random(7)
    for _ in range(14):                              # loose straws at both ends
        side = rnd.choice((-1, 1))
        m.box((side * 2.05, rnd.uniform(0.2, 1.8), rnd.uniform(-0.85, 0.85)), (rnd.uniform(0.25, 0.5), 0.05, 0.05), (228, 198, 112),
              turn_z(rnd.uniform(-25, 25)) @ turn_y(rnd.uniform(-25, 25)))
    return m


def corn_stalks():
    m = Mesh('corn_stalks', double=True)
    rnd = random.Random(11)
    for k in range(7):
        a = math.tau * k / 7 + rnd.uniform(-0.2, 0.2)
        foot = np.array([0.5 * math.cos(a), 0, 0.5 * math.sin(a)])
        waist = np.array([0.16 * math.cos(a), 3.2, 0.16 * math.sin(a)])
        top = np.array([rnd.uniform(0.6, 1.0) * math.cos(a), rnd.uniform(8.2, 9.6), rnd.uniform(0.6, 1.0) * math.sin(a)])
        m.rod(foot, waist, 0.09, 0.08, STALK, 5, caps=False)
        m.rod(waist, top, 0.08, 0.03, STALK, 5, caps=False)
        for _ in range(3):                           # dry leaves: out and down
            f = rnd.uniform(0.25, 0.9)
            root = waist + (top - waist) * f
            b = a + rnd.uniform(-1.2, 1.2)
            out = np.array([math.cos(b), 0, math.sin(b)])
            side = np.array([-out[2], 0, out[0]]) * 0.13
            reach = rnd.uniform(1.3, 2.0)
            m.ribbon([root, root + out * reach * 0.5 + (0, 0.35, 0), root + out * reach - (0, 0.5, 0)], [side, side * 1.1, side * 0.2],
                     rnd.choice((HUSK, (184, 160, 90), (150, 134, 72))))
    m.rod((0, 3.05, 0), (0, 3.35, 0), 0.27, 0.27, ORANGE, 8)          # the ribbon that ties it
    return m


def mums(name, bloom):
    m = Mesh(name)
    m.rod((0, 0, 0), (0, 0.9, 0), 0.42, 0.6, (168, 92, 56), 10)
    m.ball((0, 1.2, 0), (0.85, 0.58, 0.85), (58, 100, 50), 5, 10)
    rnd = random.Random(3)
    for _ in range(14):
        a, up = rnd.uniform(0, math.tau), rnd.uniform(0.15, 1.0)
        r = 0.85 * math.sqrt(max(0, 1 - up * up))
        m.ball((r * math.cos(a), 1.2 + 0.58 * up, r * math.sin(a)), 0.18, bloom if rnd.random() < 0.8 else tuple(min(255, v + 30) for v in bloom), 3, 5)
    return m


def scarecrow():
    m = Mesh('scarecrow', collide=False)
    WOOD, SHIRT, DENIM, BURLAP = (120, 86, 52), (164, 52, 40), (58, 82, 128), (206, 176, 120)
    m.box((0, 3.2, 0.1), (0.3, 6.4, 0.3), WOOD)
    m.box((0, 4.95, 0.1), (5.0, 0.24, 0.24), WOOD)
    m.box((0, 4.35, 0), (1.7, 1.9, 0.9), SHIRT)
    for y in (3.8, 4.4, 5.0): m.box((0, y, 0), (1.72, 0.1, 0.92), (110, 30, 26))      # the plaid
    for x in (-0.45, 0.45): m.box((x, 4.35, 0), (0.1, 1.9, 0.92), (110, 30, 26))
    for side in (-1, 1):
        m.box((side * 1.6, 4.95, 0), (1.5, 0.62, 0.62), SHIRT)
        for k in range(5): m.box((side * 2.55, 4.95, 0), (0.6, 0.05, 0.05), STRAW, turn_z(-40 + 20 * k) @ turn_y(side * 8 * k - 16))
        m.box((side * 0.42, 2.45, 0), (0.62, 2.0, 0.62), DENIM)
        for k in range(4): m.box((side * 0.42, 1.35, 0), (0.05, 0.5, 0.05), STRAW, turn_z(-24 + 16 * k) @ turn_x(10 * k - 15))
        m.box((side * 0.34, 4.9, -0.47), (0.14, 1.0, 0.06), DENIM)                     # the braces
        m.box((side * 0.26, 6.2, -0.69), (0.16, 0.16, 0.06), BLACK)                    # button eyes
    m.box((0, 4.0, -0.47), (1.0, 1.0, 0.06), DENIM)
    m.ball((0, 6.1, 0), 0.72, BURLAP, 5, 8)
    m.box((0, 5.86, -0.68), (0.52, 0.05, 0.05), BLACK)
    for x in (-0.2, 0, 0.2): m.box((x, 5.86, -0.69), (0.05, 0.2, 0.05), BLACK)
    m.rod((0, 6.05, -0.7), (0, 6.02, -1.0), 0.09, 0.02, ORANGE, 5)
    m.rod((0, 6.58, 0), (0, 6.66, 0), 1.15, 1.15, (190, 150, 70), 10)
    m.rod((0, 6.66, 0), (0.12, 7.5, 0.1), 0.62, 0.16, (190, 150, 70), 8)
    return m


def ghost():
    """A bedsheet ghost on a line; its top is the origin."""
    m = Mesh('ghost', double=True)
    S = 12
    rows = [(0.0, 0.05), (-0.25, 0.55), (-0.7, 0.8), (-1.5, 0.9), (-2.2, 1.02), (-3.0, 1.15)]
    points, norms, faces = [], [], []
    for i, (y, r) in enumerate(rows):
        for j in range(S):
            th = math.tau * j / S
            wave = (1 + 0.12 * math.sin(5 * th)) if i == len(rows) - 1 else 1
            drop = 0.18 * math.sin(5 * th + 1) if i == len(rows) - 1 else 0
            points.append((r * wave * math.sin(th), y + drop, -r * wave * math.cos(th)))
            n = np.array([math.sin(th), 0.9 if i < 2 else 0.15, -math.cos(th)]); norms.append(n / np.linalg.norm(n))
    for i in range(len(rows) - 1):
        for j in range(S):
            p, q = i * S + j, i * S + (j + 1) % S
            faces += [(p, q, q + S), (p, q + S, p + S)]
    m.add(points, norms, SHEET, faces)
    for x in (-0.3, 0.3): m.ball((x, -0.85, -0.8), (0.14, 0.21, 0.06), BLACK, 4, 8)
    m.ball((0, -1.3, -0.88), (0.12, 0.17, 0.06), BLACK, 4, 8)
    return m


WING = [(0.15, -0.2), (0.6, 0.05), (1.25, -0.1), (1.1, -0.35), (0.9, -0.3), (0.75, -0.55), (0.55, -0.42), (0.35, -0.62), (0.15, -0.5)]


def bat():
    """A rubber bat on a line; its top is the origin."""
    m = Mesh('bat', double=True)
    m.ball((0, -0.35, 0), (0.22, 0.32, 0.2), BLACK, 5, 8)
    for side in (-1, 1):
        m.flat([(side * x, y) for x, y in WING], BLACK)
        m.rod((side * 0.1, -0.1, 0), (side * 0.17, 0.12, 0), 0.07, 0.01, BLACK, 4)
    return m


def pail():
    m = Mesh('pail')
    m.rod((0, 0, 0), (0, 0.85, 0), 0.36, 0.5, ORANGE, 12)
    m.rod((0, 0.86, 0), (0, 0.87, 0), 0.44, 0.44, (60, 30, 10), 12)
    at = lambda a, h, lift=0.012: ((0.36 + 0.14 * h / 0.85 + lift) * math.sin(a), h, -(0.36 + 0.14 * h / 0.85 + lift) * math.cos(a))
    def paint(tri):
        pts = [at(a, h) for a, h in tri]
        m.add(pts, [np.array([p[0], 0, p[2]]) / math.hypot(p[0], p[2]) for p in pts], (24, 14, 8), [(0, 1, 2)])
    for s in (-1, 1): paint([(s * 0.55, 0.5), (s * 0.2, 0.5), (s * 0.38, 0.68)])
    for k, a in enumerate(np.linspace(-0.6, 0.45, 6)):
        paint([(a, 0.22), (a + 0.15, 0.22), (a + 0.075, 0.36 if k % 2 else 0.3)])
    arc = [(-0.5 * math.cos(t), 0.82 + 0.5 * math.sin(t), 0) for t in np.linspace(0, math.pi, 9)]
    for a, b in zip(arc, arc[1:]): m.rod(a, b, 0.03, 0.03, BLACK, 4, caps=False)
    return m


def balloon():
    """White, so the game can tint it; the knot is the origin."""
    m = Mesh('balloon')
    m.ball((0, 0.66, 0), (0.5, 0.6, 0.5), WHITE, 6, 10)
    m.rod((0, 0, 0), (0, 0.1, 0), 0.04, 0.1, WHITE, 6)
    return m


def balloon_bunch():
    m = Mesh('balloon_bunch')
    for (x, y, z), colour in (((-0.55, 4.2, 0.1), ORANGE), ((0.5, 4.6, -0.2), BLACK), ((0.05, 5.3, 0.3), PURPLE)):
        m.rod((0, 0, 0), (x, y, z), 0.03, 0.03, (230, 230, 230), 4, caps=False)
        m.ball((x, y + 0.66, z), (0.5, 0.6, 0.5), colour, 6, 10)
        m.rod((x, y, z), (x, y + 0.1, z), 0.04, 0.1, colour, 6)
    return m


def swag(name='swag', span=12.0, sag=1.3):
    """Twisted crepe paper, orange on one side and black on the other; it hangs between (-span/2, 0) and (span/2, 0)."""
    m = Mesh(name)
    points, widths = [], []
    for i in range(25):
        s = i / 24
        x = -span / 2 + span * s
        points.append((x, -sag * (1 - (2 * s - 1) ** 2), 0))
        a = s * math.pi * 6
        widths.append((0, 0.3 * math.cos(a), 0.3 * math.sin(a)))
    m.ribbon(points, widths, ORANGE, back=BLACK)
    return m


def pennants(name, span, sag, pitch, wide, tall):
    """A string of paper pennants; it hangs between (-span/2, 0) and (span/2, 0)."""
    m = Mesh(name, double=True)
    y = lambda x: -sag * (1 - (2 * x / span) ** 2)
    xs = np.linspace(-span / 2, span / 2, int(span / pitch) * 2 + 1)
    m.ribbon([(x, y(x), 0) for x in xs], [(0, 0.04, 0)] * len(xs), (40, 36, 36))
    count = int((span - pitch) / pitch)
    for k in range(count):
        x = -span / 2 + pitch * (k + 1)
        pts = [np.array((x - wide / 2, y(x - wide / 2), 0)), np.array((x + wide / 2, y(x + wide / 2), 0)), np.array((x, y(x) - tall, 0))]
        m.add(pts, [np.array([0, 0, -1.0])] * 3, (ORANGE, BLACK, PURPLE)[k % 3], [(0, 1, 2)])
    return m


def skeleton():
    """A jointed cardboard skeleton, waving; taped flat to a pier."""
    m = Mesh('cut_skeleton')
    m.disc((0, 2.35), 0.62, 0.7, BONE, sides=10)
    m.strip((0, 1.78), (0, 1.5), 0.6, BONE)
    for x in (-0.24, 0.24): m.disc((x, 2.42), 0.17, 0.2, BLACK, -0.012, 8)
    m.flat([(-0.07, 2.08), (0.07, 2.08), (0, 2.24)], BLACK, -0.012)
    for x in (-0.18, -0.06, 0.06, 0.18): m.strip((x, 1.74), (x, 1.56), 0.03, BLACK, -0.012)
    m.strip((0, 1.5), (0, -0.4), 0.18, BONE)
    for k, y in enumerate((1.25, 0.95, 0.65, 0.35)): m.strip((-0.65 + 0.07 * k, y), (0.65 - 0.07 * k, y), 0.14, BONE)
    m.flat([(-0.55, -0.3), (0.55, -0.3), (0.3, -0.75), (-0.3, -0.75)], BONE)
    limbs = [((-0.7, 1.3), (-1.45, 0.65), (-1.2, -0.3)), ((0.7, 1.3), (1.5, 1.85), (1.2, 2.8)),
             ((-0.3, -0.7), (-0.62, -1.8), (-0.45, -2.85)), ((0.3, -0.7), (0.72, -1.75), (0.55, -2.85))]
    for a, b, c in limbs:
        m.strip(a, b, 0.17, BONE); m.strip(b, c, 0.15, BONE)
        m.disc(b, 0.14, 0.14, BONE, sides=8); m.disc(c, 0.2, 0.16, BONE, sides=8)
    return m


def cat():
    m = Mesh('cut_cat')
    m.flat([(-1.2, -1.2), (-0.95, -1.2), (-0.9, -0.3), (-0.6, 0.15), (0.0, 0.45), (0.5, 0.3), (0.75, -0.3), (0.8, -1.2), (1.05, -1.2), (1.1, -0.2),
            (1.0, 0.4), (1.45, 0.9), (1.6, 1.5), (1.45, 1.55), (1.25, 1.0), (0.8, 0.75), (0.2, 0.95), (-0.5, 0.8), (-0.9, 0.45), (-1.05, 0.75),
            (-1.0, 1.15), (-1.2, 0.95), (-1.45, 1.2), (-1.5, 0.8), (-1.65, 0.45), (-1.45, 0.2), (-1.25, 0.15), (-1.25, -0.3)], BLACK)
    for x in (-1.42, -1.16): m.flat([(x - 0.08, 0.6), (x + 0.08, 0.6), (x, 0.72)], SALE_YELLOW, -0.012)
    return m


def bat_cut():
    m = Mesh('cut_bat')
    k = 1.7
    for side in (-1, 1): m.flat([(side * x * k, y * k) for x, y in WING], BLACK)
    m.disc((0, -0.6), 0.36, 0.5, BLACK, sides=10)
    for side in (-1, 1): m.flat([(side * 0.08, -0.2), (side * 0.3, -0.2), (side * 0.24, 0.12)], BLACK)
    return m


def cobweb():
    """A corner web: the corner is the origin, it spreads along +x and down."""
    m = Mesh('cobweb', double=True)
    WEB = (232, 232, 226)
    spokes = [(a, l) for a, l in zip((0, -22.5, -45, -67.5, -90), (4.5, 4.2, 4.7, 4.0, 4.4))]
    tip = lambda a, l, f: np.array([math.cos(math.radians(a)) * l * f, math.sin(math.radians(a)) * l * f])
    for a, l in spokes: m.strip((0, 0), tip(a, l, 1), 0.05, WEB)
    for f in (0.28, 0.52, 0.76, 0.96):
        for (a0, l0), (a1, l1) in zip(spokes, spokes[1:]):
            p, q = tip(a0, l0, f), tip(a1, l1, f)
            mid = (p + q) / 2 * 0.9
            m.strip(p, mid, 0.04, WEB); m.strip(mid, q, 0.04, WEB)
    return m


def starburst():
    """A price burst, yellow on red; the game writes on its front."""
    m = Mesh('starburst')
    star = lambda outer, inner: [((outer if i % 2 == 0 else inner) * math.cos(math.tau * i / 32), (outer if i % 2 == 0 else inner) * math.sin(math.tau * i / 32)) for i in range(32)]
    m.flat(star(1.1, 0.88), SALE_RED, 0.0)
    m.flat(star(1.0, 0.8), SALE_YELLOW, -0.02)
    return m


def kit():
    body, face = pumpkins()
    return [body, face, hay_bale(), corn_stalks(), mums('mums_orange', (232, 112, 28)), mums('mums_yellow', (240, 196, 44)), scarecrow(), ghost(), bat(),
            pail(), balloon(), balloon_bunch(), swag(), pennants('pennants_hall', 80, 3.2, 2.0, 1.3, 1.8), pennants('pennants_shop', 40, 0.9, 1.6, 1.1, 1.4),
            skeleton(), cat(), bat_cut(), cobweb(), starburst()]


# ------------------------------------------------------------------------------------------------------- the layout
def layout():
    """Mall build coordinates. `face`: the world direction (x, z) the prop's front looks along."""
    rnd = random.Random(1031)
    items, signs, lights = [], [], []

    def put(kind, x, y, z, face=(0, -1), scale=1.0, **more):
        items.append({'kind': kind, 'pos': [round(x, 3), round(y, 3), round(z, 3)], 'face': [round(face[0], 4), round(face[1], 4)],
                      'scale': scale if isinstance(scale, list) else [scale] * 3, **more})

    def pumpkin(x, z, size, face, y=FLOOR, lit=True, light=False):
        r = {'L': 1.6, 'M': 1.1, 'S': 0.7}[size]
        jitter = rnd.uniform(-0.35, 0.35)
        face = (face[0] * math.cos(jitter) - face[1] * math.sin(jitter), face[0] * math.sin(jitter) + face[1] * math.cos(jitter))
        put('pumpkin', x, y, z, face, r, lit=lit, light=light or size == 'L', collide=size != 'S')   # every big lantern carries a light (HALLOWEEN_DUSK_20261013)

    def hang(kind, x, y, z, face=(0, -1), scale=1.0, **more):
        put(kind, x, y, z, face, scale, line=CEIL, **more)

    def banner(name, pos, size, face, lines, two=False, line=None, colour=SALE_ORANGE):
        signs.append({'name': name, 'kind': 'banner', 'pos': list(pos), 'size': list(size), 'face': list(face), 'lines': lines, 'two': two, 'line': line, 'colour': list(colour)})

    def a_frame(name, x, z, face, lines):
        signs.append({'name': name, 'kind': 'aframe', 'pos': [x, FLOOR, z], 'size': [3.2, 4.6], 'face': list(face), 'lines': lines, 'colour': list(SALE_ORANGE)})

    def burst(name, x, y, z, face, r, lines, line=None, two=False):
        signs.append({'name': name, 'kind': 'burst', 'pos': [x, y, z], 'size': [2 * r, 2 * r], 'face': list(face), 'lines': lines, 'line': line, 'two': two})

    # --- the piers: corn stalks or a cardboard skeleton, pumpkins at the foot
    boards = [(b['normal'][0], b['pos'][2] - b['size'][0] / 2, b['pos'][2] + b['size'][0] / 2) for b in MALL['anchors']['boards']]
    tubs = [(p['pos'][0], p['pos'][2]) for p in MALL['parts'] if p['name'].startswith('PlantTub')]
    for side, x_face, into in ((-1, 184.0, (1, 0)), (1, 256.0, (-1, 0))):
        # what already stands along this wall: the boards (they face into the hall) and the round planters
        taken = [(lo, hi) for n, lo, hi in boards if n == into[0]] + [(z - 2.2, z + 2.2) for x, z in tubs if abs(x - x_face) < 5]
        for k, zc in enumerate((-868, -812, -788, -732, -708, -652)):
            covered = next(((lo, hi) for lo, hi in taken if lo - 0.2 <= zc <= hi + 0.2), None)
            near = next(((lo, hi) for lo, hi in taken if min(abs(zc - lo), abs(zc - hi)) < 2.6), None)
            shift = 0 if near is None else (1.2 if (near[0] + near[1]) / 2 < zc else -1.2)   # lean away from a board at the pier's edge
            hit = lambda a, b: any(lo - 0.6 < max(a, b) and min(a, b) < hi + 0.6 for lo, hi in taken)
            open_side = next((s for s in (1, -1) if not hit(zc + s * 0.6, zc + s * 6.2)), None)
            x_out = x_face + into[0]
            if covered is None:
                if k % 2 == 0:
                    put('corn_stalks', x_face + into[0] * 0.75, FLOOR, zc + shift, into, 1.0)
                else:
                    put('cut_skeleton', x_face + into[0] * 0.04, 36.3, zc, into, 1.0)
                put('cut_cat' if k % 3 == 0 else 'cut_bat', x_face + into[0] * 0.04, 45.6 if k % 2 == 0 else 43.6, zc + 0.2, into, 0.9 if k % 3 == 0 else 0.75)
            if open_side is None: continue
            z0 = zc + open_side * 2.5
            pumpkin(x_out + into[0] * 1.9, z0, 'L', into, light=zc in (-868, -708))
            pumpkin(x_out + into[0] * 0.9, z0 + open_side * 2.4, 'M', into)
            if k % 3 != 1: pumpkin(x_out + into[0] * 3.4, z0 + open_side * 1.7, 'S', into)
            if k % 2 == 1: put('pail', x_out + into[0] * 3.2, FLOOR, z0 - open_side * 0.9, into, 1.0)
        # --- crepe swags pier to pier, high on the wall, and a string of small pennants under each shop's sign
        wall = x_face - into[0] * 3.9                                                 # the wall's own face, behind the piers
        for a, b in ((-868, -812), (-812, -788), (-788, -732), (-732, -708), (-708, -652)):
            count = round((b - a) / 12)
            span = (b - a - 4) / count
            for i in range(count):
                put('swag', wall + into[0] * 0.45, 49.0, a + 2 + span * (i + 0.5), into, [span / 12, 1, 1])
        for zc in (-840, -760, -680):
            put('pennants_shop', wall + into[0] * 0.5, 42.0, zc, into, 1.0)
            for corner, turn in ((zc - 26, (1, 0)), (zc + 26, (-1, 0))):                  # cobwebs in the top corners of each entry (drawn from both sides)
                put('cobweb', wall + into[0] * 0.3, 46.0, corner, turn, 1.0, transparency=0.25)

    # --- pennant strings across the hall, wall to wall
    for z in (-884, -858, -806, -742, -716, -690, -664):
        put('pennants_hall', 220, 53.0, z, (0, -1), 1.0)

    # --- ghosts and bats on lines from the ceiling
    for x, y, z in ((199, 46.5, -852), (241, 47.5, -824), (196, 46.0, -746), (244, 47.0, -694), (206, 45.5, -676), (236, 46.5, -872)):
        hang('ghost', x, y, z, (rnd.uniform(-0.4, 0.4), -1), rnd.uniform(1.0, 1.25))
    put('ghost', 222, 41.5, -611, (0.2, -1), 1.15, line=WING_CEIL)                 # one hangs just past the tape
    for _ in range(16):
        while True:
            x, z = rnd.uniform(190, 250), rnd.uniform(-884, -640)
            if math.hypot(x - 220, z + 770) > 12: break
        a = rnd.uniform(0, math.tau)
        hang('bat', x, rnd.uniform(44.5, 50.5), z, (math.cos(a), math.sin(a)), rnd.uniform(0.9, 1.4))

    # --- the shop stand: an orange band over its signs, bursts on the counters, danglers, standees, pumpkins at its corners
    cx, cz = 220, -770
    for k in range(6):
        a = math.radians(60 * k)
        out = (math.sin(a), -math.cos(a))                                              # k = 0 looks at the spawn (-z)
        banner('StandBand%d' % k, (cx + out[0] * 6.2, 44.15, cz + out[1] * 6.2), (6.4, 1.2), out, [SALE if k % 2 == 0 else OFF])
        side = (-out[1], out[0])
        burst('CounterBurst%d' % k, cx + out[0] * 11.0 + side[0] * 4.3, 33.55, cz + out[1] * 11.0 + side[1] * 4.3, out, 0.95, ['66.6%', 'OFF'])
        b = math.radians(60 * k + 30)
        corner = (math.sin(b), -math.cos(b))
        burst('Dangler%d' % k, cx + corner[0] * 13.5, 47.0, cz + corner[1] * 13.5, corner, 2.1, ['66.6%', 'OFF'] if k % 2 == 0 else ['HALLOWEEN', 'SALE'], line=CEIL, two=True)
        vx, vz = cx + corner[0] * 23.2, cz + corner[1] * 23.2
        pumpkin(vx, vz, 'L', corner, light=k % 2 == 0)
        pumpkin(vx - corner[1] * 2.3, vz + corner[0] * 2.3, 'S', corner)
        if k % 2 == 1: put('balloon_bunch', vx + corner[1] * 1.6, FLOOR + 0.05, vz - corner[0] * 1.6, corner, 1.0)
        else: put('pail', vx + corner[1] * 2.0, FLOOR, vz - corner[0] * 2.0, corner, 1.0)
    a_frame('StandeeSaleSouth', 214.4, -791.6, (0, -1), [SALE, '66.6% OFF', 'EVERYTHING'])
    a_frame('StandeeReentrySouth', 225.6, -791.6, (0, -1), [REENTRY, THREE, 'HALLOWEEN ONLY'])
    a_frame('StandeeReentryNorth', 227.8, -748.6, (0, 1), [REENTRY, THREE, 'HALLOWEEN ONLY'])
    a_frame('StandeeSaleNorth', 212.2, -748.6, (0, 1), [SALE, '66.6% OFF', 'EVERYTHING'])

    # --- the big banner the arriving player sees, and banners on the free walls
    banner('HallBanner', (220, 49.4, -822), (24, 5.6), (0, -1), [SALE, OFF], two=True, line=CEIL)
    banner('WallBannerEast', (259.92, 40.6, -800), (18, 4.2), (-1, 0), [SALE, OFF])
    banner('WallBannerSouthWest', (180.08, 41.5, -886), (18, 4.2), (1, 0), [SALE, OFF])
    banner('WallBannerSouthEast', (259.92, 41.5, -886), (18, 4.2), (-1, 0), [SALE, OFF])
    banner('StageBannerSale', (220, 42.2, -632.35), (27, 2.6), (0, -1), [OFF])

    # --- the two planters become the mall's seasonal display
    for pz in (-835, -700):
        put('scarecrow', 220, 32.85, pz, (0, -1) if pz < -770 else (0, 1), 1.0)
        for sx, kind in ((-4.4, 'mums_orange'), (4.4, 'mums_yellow'), (-2.4, 'mums_yellow'), (2.4, 'mums_orange')):
            put(kind, 220 + sx, 32.85, pz + (0.8 if abs(sx) < 3 else 0), (0, -1), 1.0)
        for sx in (-1, 1):
            put('hay_bale', 220 + sx * 8.4, FLOOR, pz, (1, 0), 1.0, collide=True)
            pumpkin(220 + sx * 8.4, pz + 0.1, 'M', (0, -1) if pz < -770 else (0, 1), y=FLOOR + 2.0, light=sx == 1)
            pumpkin(220 + sx * 11.2, pz - 1.2, 'L', (sx * 0.4, -1 if pz < -770 else 1))
            pumpkin(220 + sx * 10.6, pz + 1.9, 'S', (sx * 0.4, -1 if pz < -770 else 1))
        put('pail', 216.5, 32.47, pz - 5.0, (0, -1), 1.0)
        put('pail', 224.2, 32.47, pz + 5.0, (0, 1), 1.0)

    # --- the stage: pumpkins along its edge, balloons at its corners
    for x in (207.0, 209.6, 212.0, 228.0, 230.4, 233.0):
        pumpkin(x, -653.4, 'M' if round(x) % 2 else 'S', (0, -1), y=32.0, light=x in (209.6, 230.4))
    for x in (205.8, 234.2): put('balloon_bunch', x, 32.05, -653.6, (0, -1), 1.0)

    # --- the tape and the dark wing: a row of lanterns on the line, and a few alone in the dark beyond it
    for x in (190, 202, 214, 226, 238, 250):
        pumpkin(x, TAPE_Z - 1.9, 'M', (0, -1), light=True)
    for x, z, size in ((205, -606, 'M'), (233, -588, 'S'), (214, -562, 'S'), (229, -534, 'S'), (219, -498, 'S')):
        pumpkin(x, z, size, (220 - x, -770 - z), light=True)

    # --- loose ends: sagging balloons and a streamer that has come down
    for x, z, tint in ((193, -846, ORANGE), (247, -796, BLACK), (203, -668, PURPLE), (239, -672, ORANGE), (188, -700, BLACK)):
        put('balloon', x, FLOOR + 0.5, z, (rnd.uniform(-1, 1), rnd.uniform(-1, 1)), 1.0, tint=list(tint), tilt=90)
    put('swag', 196, FLOOR + 0.32, -818, (0.3, -1), [0.7, 0.1, 1], tilt=0)

    for item in items:                                # which of the lit lanterns carry a real light
        if item['kind'] == 'pumpkin' and item.get('light'):
            x, y, z = item['pos']
            lights.append({'pos': [x, round(y + item['scale'][0] * 0.8, 3), z], 'range': round(7 + 4 * item['scale'][0], 1), 'wing': z > TAPE_Z})
    return items, signs, lights


def check_halloween(items, signs, sizes):
    """The rules that keep the lobby working: nothing solid where people walk, queue or read."""
    errors = []
    pads = [(p['pos'][0], p['pos'][2], p['radius']) for p in MALL['anchors']['pads']]
    spots = [(s['pos'][0], s['pos'][2]) for s in MALL['anchors']['shop_spots']] + [(s['pos'][0], s['pos'][2]) for s in MALL['anchors']['skin_plinths']]
    spawn = MALL['anchors']['spawn']
    for item in items:
        x, y, z = item['pos']
        reach = max(sizes[item['kind']][0] * item['scale'][0], sizes[item['kind']][2] * item['scale'][2]) / 2
        low = y < FLOOR + 6.5 and 'line' not in item
        if not (180 <= x <= 260 and -900 <= z <= -421): errors.append('%s outside the hall at %s' % (item['kind'], item['pos']))
        if 'line' in item and y < FLOOR + 9: errors.append('%s hangs into head height at %s' % (item['kind'], item['pos']))
        if low:
            for px, pz, pr in pads:
                if math.hypot(x - px, z - pz) < pr + reach: errors.append('%s on a queue pad at %s' % (item['kind'], item['pos']))
            for sx, sz in spots:
                if math.hypot(x - sx, z - sz) < 2.6 + reach: errors.append('%s on a shop spot at %s' % (item['kind'], item['pos']))
            if math.hypot(x - spawn[0], z - spawn[2]) < 9 + reach: errors.append('%s on the spawn at %s' % (item['kind'], item['pos']))
            if item.get('collide', False) and 188.5 < x < 251.5 and math.hypot(x - 220, z + 770) > 26 and not any(abs(z - pz) < 4 for pz in (-835, -700)) \
                    and not (z > -656) and item['kind'] != 'pumpkin':
                errors.append('solid %s in the walking lane at %s' % (item['kind'], item['pos']))
    for sign in signs:
        if sign['kind'] == 'aframe':
            x, _, z = sign['pos']
            for sx, sz in spots:
                if math.hypot(x - sx, z - sz) < 4.2: errors.append('%s too near a shop spot' % sign['name'])
        for line in sign['lines']:
            if line not in (SALE, OFF, REENTRY, THREE, '66.6%', 'OFF', '66.6% OFF', 'EVERYTHING', 'HALLOWEEN', 'SALE', 'HALLOWEEN ONLY'):
                errors.append('%s carries unexpected lettering: %s' % (sign['name'], line))
    return errors


# ---------------------------------------------------------------------------------------------------------- blender
def to_blender(p):
    return Vector((p[0], -p[2], p[1]))


def frame(pos, face, tilt=0):
    """Blender matrix for a prop at a Roblox position whose front (-z) looks along `face`."""
    f = np.array([face[0], 0, face[1]], float); f /= np.linalg.norm(f)
    right = np.cross(f, [0, 1, 0])
    rot = np.column_stack([right, [0, 1, 0], -f]) @ turn_x(tilt)
    swap = np.array([[1, 0, 0], [0, 0, -1], [0, 1, 0]])
    m = Matrix.Identity(4)
    b = swap @ rot @ swap.T
    for i in range(3):
        for j in range(3): m[i][j] = b[i][j]
    m.translation = to_blender(pos)
    return m


def material(name, colour=None, vertex=False, glow=0):
    mat = bpy.data.materials.new(name); mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    shader = next(n for n in nodes if n.type == 'BSDF_PRINCIPLED')
    shader.inputs['Roughness'].default_value = 0.7
    if vertex:
        attr = nodes.new('ShaderNodeVertexColor'); attr.layer_name = 'Col'
        links.new(attr.outputs['Color'], shader.inputs['Base Color'])
    else:
        shader.inputs['Base Color'].default_value = (*[(v / 255) ** 2.2 for v in colour], 1)
    if glow:
        shader.inputs['Emission Color'].default_value = (1.0, 0.55, 0.12, 1)
        shader.inputs['Emission Strength'].default_value = glow
    return mat


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    meshes = kit()
    data = {m.name: m.export() for m in meshes}
    sizes = {name: d['size'] for name, d in data.items()}
    items, signs, lights = layout()
    errors = check_halloween(items, signs, sizes)
    if errors:
        print('CHECK FAILED'); [print('  ' + e) for e in sorted(set(errors))[:40]]
        raise SystemExit(1)
    (OUT / 'halloween.json').write_text(json.dumps({'version': 1, 'kit': data, 'items': items, 'signs': signs, 'lights': lights,
                                                     'ceiling': CEIL, 'floor': FLOOR, 'tape_z': TAPE_Z}, separators=(',', ':')) + '\n')

    paint = material('KitPaint', vertex=True)
    lantern = material('LanternGlow', (255, 180, 60), glow=6)
    kit_col = bpy.data.collections.new('Kit'); scene.collection.children.link(kit_col)
    hall_col = bpy.data.collections.new('HallDressing'); scene.collection.children.link(hall_col)
    mall_col = bpy.data.collections.new('MallShell'); scene.collection.children.link(mall_col)
    bmeshes = {}
    for i, m in enumerate(meshes):
        mesh = bpy.data.meshes.new(m.name)
        mesh.from_pydata([tuple(to_blender(p)) for p in m.v], [], [tuple(int(k) for k in t) for t in m.t])
        layer = mesh.color_attributes.new('Col', 'FLOAT_COLOR', 'POINT')
        for k, c in enumerate(m.c): layer.data[k].color = (*[(v / 255) ** 2.2 for v in c], 1)
        mesh.materials.append(lantern if m.name == 'pumpkin_face' else paint)
        bmeshes[m.name] = mesh
    for i, m in enumerate(meshes):
        mesh = bmeshes[m.name]
        if m.name != 'pumpkin_face':                 # the kit, in a row beside the hall
            o = bpy.data.objects.new('Kit_' + m.name, mesh); kit_col.objects.link(o)
            o.location = to_blender((60 + (i % 7) * 9, 30 if 'pennants' not in m.name else 40, -1000 - (i // 7) * 12))
            if m.name == 'pumpkin':
                g = bpy.data.objects.new('Kit_pumpkin_face', bmeshes['pumpkin_face']); kit_col.objects.link(g); g.location = o.location
    for n, item in enumerate(items):
        o = bpy.data.objects.new('%s_%03d' % (item['kind'], n), bmeshes[item['kind']]); hall_col.objects.link(o)
        o.matrix_world = frame(item['pos'], item['face'], item.get('tilt', 0)) @ Matrix.Diagonal((item['scale'][0], item['scale'][2], item['scale'][1], 1))
        if item['kind'] == 'pumpkin' and item.get('lit'):
            g = bpy.data.objects.new('face_%03d' % n, bmeshes['pumpkin_face']); hall_col.objects.link(g); g.matrix_world = o.matrix_world
        if 'line' in item:
            top = item['line'] - item['pos'][1]
            if '__line' not in bmeshes: bmeshes['__line'] = bpy.data.meshes.new('line')
            cord = bpy.data.objects.new('line_%03d' % n, bmeshes['__line'])
            if not cord.data.vertices:
                cord.data.from_pydata([(-0.02, 0, 0), (0.02, 0, 0), (0.02, 0, 1), (-0.02, 0, 1), (0, -0.02, 0), (0, 0.02, 0), (0, 0.02, 1), (0, -0.02, 1)], [], [(0, 1, 2, 3), (4, 5, 6, 7)])
                cord.data.materials.append(material('Line', (30, 30, 30)))
            hall_col.objects.link(cord); cord.location = to_blender(item['pos']); cord.scale = (1, 1, top)
    font = bpy.data.fonts.load(FONT)
    cloth, ink = material('SaleCloth', SALE_ORANGE), material('SaleInk', (20, 16, 12))
    for sign in signs:
        w, h = sign['size']
        x, y, z = sign['pos']
        if sign['kind'] == 'aframe': y += h / 2
        if sign['kind'] == 'burst':
            o = bpy.data.objects.new(sign['name'], bmeshes['starburst']); hall_col.objects.link(o)
            o.matrix_world = frame((x, y, z), sign['face']) @ Matrix.Diagonal((w / 2, 1, h / 2, 1))
        else:
            bpy.ops.mesh.primitive_cube_add(size=1)
            o = bpy.context.active_object; o.name = sign['name']
            o.matrix_world = frame((x, y, z), sign['face']) @ Matrix.Diagonal((w, 0.08, h, 1))
            o.data.materials.append(cloth)
            for c in list(o.users_collection): c.objects.unlink(o)
            hall_col.objects.link(o)
        curve = bpy.data.curves.new(sign['name'] + '_Text', 'FONT'); curve.body = '\n'.join(sign['lines']); curve.font = font
        curve.align_x, curve.align_y = 'CENTER', 'CENTER'
        curve.size = min(h / (len(sign['lines']) * 1.05), w / (max(len(l) for l in sign['lines']) * 0.42)) * 0.86
        t = bpy.data.objects.new(sign['name'] + '_Text', curve); hall_col.objects.link(t); curve.materials.append(ink)
        f = np.array([sign['face'][0], 0, sign['face'][1]], float); f /= np.linalg.norm(f)
        t.matrix_world = frame((x + f[0] * 0.07, y, z + f[2] * 0.07), sign['face']) @ Matrix.Rotation(math.radians(90), 4, 'X') @ Matrix.Rotation(math.radians(180), 4, 'Y')
    shell = material('Shell', (214, 204, 168))
    dark = material('ShellDark', (60, 56, 50))
    skip = ('Trolley', 'Goods', 'Product', 'Chair', 'Leaf', 'Stem', 'Pier', 'CeilingGap')
    for p in MALL['parts']:
        if p['shape'] != 'Block' or p['name'].startswith(skip) or p['pos'][2] > -590 or max(p['size']) < 1.0: continue
        bpy.ops.mesh.primitive_cube_add(size=1)
        o = bpy.context.active_object; o.name = 'mall_' + p['name']
        rx, ry, rz = [math.radians(v) for v in p['rot']]
        rot = turn_y(p['rot'][1]) @ turn_x(p['rot'][0]) @ turn_z(p['rot'][2])
        swap = np.array([[1, 0, 0], [0, 0, -1], [0, 1, 0]])
        b = swap @ rot @ swap.T
        m = Matrix.Identity(4)
        for i in range(3):
            for j in range(3): m[i][j] = b[i][j]
        m.translation = to_blender(p['pos'])
        o.matrix_world = m @ Matrix.Diagonal((p['size'][0], p['size'][2], p['size'][1], 1))
        o.data.materials.append(dark if p['material'] in ('black', 'frame', 'stage_carpet') or p['name'].startswith(('Shop', 'Dark')) and 'Floor' in p['name'] else shell)
        for c in list(o.users_collection): c.objects.unlink(o)
        mall_col.objects.link(o)

    scene.render.engine = 'BLENDER_EEVEE'; scene.render.threads_mode = 'FIXED'; scene.render.threads = 2
    if hasattr(scene, 'eevee'): scene.eevee.taa_render_samples = 16
    scene.view_settings.view_transform = 'Standard'
    world = bpy.data.worlds.new('Hall'); world.use_nodes = True
    world.node_tree.nodes['Background'].inputs['Color'].default_value = (0.5, 0.46, 0.34, 1)
    world.node_tree.nodes['Background'].inputs['Strength'].default_value = 0.55
    scene.world = world
    for x, z in ((200, -850), (240, -790), (200, -730), (240, -670), (220, -900)):
        lamp = bpy.data.lights.new('Panel', 'POINT'); lamp.energy = 90000; lamp.shadow_soft_size = 3
        o = bpy.data.objects.new('Panel', lamp); o.location = to_blender((x, 54, z)); scene.collection.objects.link(o)
    sun = bpy.data.lights.new('KitSun', 'SUN'); sun.energy = 2.5
    o = bpy.data.objects.new('KitSun', sun); o.rotation_euler = (math.radians(50), 0, math.radians(30)); scene.collection.objects.link(o)
    camera = bpy.data.objects.new('Camera', bpy.data.cameras.new('Camera')); scene.collection.objects.link(camera); scene.camera = camera
    camera.data.lens, camera.data.clip_end = 20, 2000
    scene.render.resolution_x, scene.render.resolution_y = 1600, 900

    def shot(name, at, look, lens=20):
        camera.data.lens = lens
        camera.location = to_blender(at)
        camera.rotation_euler = (to_blender(look) - to_blender(at)).to_track_quat('-Z', 'Y').to_euler()
        scene.render.filepath = str(OUT / name)
        bpy.ops.render.render(write_still=True)

    shot('kit.png', (88, 44, -1052), (88, 33, -1008), 30)
    shot('view_hall_from_spawn.png', (220, 37, -874), (220, 38, -770))
    shot('view_stand.png', (203, 37, -806), (220, 37, -772), 24)
    shot('view_entry.png', (214, 36, -846), (182, 36, -862), 24)
    shot('view_stage_tape.png', (220, 37, -690), (220, 35, -630), 22)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT / 'halloween.blend'))
    by = {}
    for item in items: by[item['kind']] = by.get(item['kind'], 0) + 1
    tris = sum(data[i['kind']]['triangles'] for i in items)
    print('BUILT kit %d meshes; placed %d props (%s); %d signs; %d lights; %d triangles in the hall' % (len(meshes), len(items), ', '.join('%s %d' % kv for kv in sorted(by.items())), len(signs), len(lights), tris))


main()
