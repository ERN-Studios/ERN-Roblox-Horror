"""Level 6 "Indoor Playground Backrooms" - deterministic Blender build.

Run headless:  Blender -b --python tools/level6_playground/build_playground.py -- [--render]
Coordinates are Roblox studs with Blender Z up (1 BU = 1 stud); no live place data is consumed.
Everything is generated from SEED, so the same script always gives the same map.
"""
import bpy, math, random, sys, json
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "artifacts" / "level6-playground-20261002"
SEED = 6
rng = random.Random(SEED)

# ---- dimensions (studs) ------------------------------------------------------------------
HALL_X, HALL_Y, HALL_Z = 600, 400, 60       # warehouse shell
TILE = 12                                   # foam puzzle-mat tile
C, H = 12, 10                               # play-frame cell and storey height
NX, NY, NZ = 22, 26, 3                      # play-frame cells; decks at z = 10 and 20, net roof at 30
SX, SY = 300, 44                            # play-frame south-west corner
POST_R, BEAM_R = 0.55, 0.42

# ---- scene reset -------------------------------------------------------------------------
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.unit_settings.system = 'NONE'
scene.unit_settings.scale_length = 1


def collection(name):
    col = bpy.data.collections.new(name)
    scene.collection.children.link(col)
    return col


# ---- materials ---------------------------------------------------------------------------
PALETTE = {
    # padded vinyl, slightly dirty 90s primaries
    'yellow': (0.92, 0.72, 0.05), 'red': (0.74, 0.07, 0.06), 'blue': (0.05, 0.16, 0.62),
    'green': (0.10, 0.50, 0.16), 'purple': (0.33, 0.12, 0.50), 'pink': (0.90, 0.22, 0.50),
    'cyan': (0.05, 0.55, 0.72), 'orange': (0.93, 0.38, 0.05), 'navy': (0.03, 0.05, 0.22),
    # floor
    'mat_green': (0.16, 0.52, 0.24), 'mat_blue': (0.12, 0.20, 0.58), 'concrete': (0.36, 0.33, 0.29),
    # shell
    'wall_yellow': (0.86, 0.66, 0.10), 'wall_blue': (0.07, 0.17, 0.60), 'wall_red': (0.66, 0.10, 0.08),
    'wall_white': (0.72, 0.70, 0.64), 'deck': (0.42, 0.41, 0.38), 'steel': (0.20, 0.20, 0.21),
    'duct': (0.55, 0.56, 0.57), 'pipe_red': (0.45, 0.06, 0.05),
    # props
    'white': (0.82, 0.80, 0.75), 'black': (0.02, 0.02, 0.02), 'counter': (0.80, 0.24, 0.10),
    'stainless': (0.55, 0.56, 0.58), 'paper': (0.85, 0.83, 0.74), 'wood': (0.45, 0.30, 0.16),
    'lamp_off': (0.30, 0.30, 0.28),
}
ROUGH = {'stainless': 0.3, 'duct': 0.4, 'steel': 0.55, 'deck': 0.6, 'concrete': 0.9}
VINYL = ['yellow', 'red', 'blue', 'green', 'purple', 'pink', 'cyan', 'orange']
MATS = {}


def make_material(name, rgb, rough=0.5, emission=0.0, metallic=0.0):
    mat = bpy.data.materials.new('L6_' + name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes['Principled BSDF']
    bsdf.inputs['Base Color'].default_value = (*rgb, 1)
    bsdf.inputs['Roughness'].default_value = rough
    bsdf.inputs['Metallic'].default_value = metallic
    if emission:
        bsdf.inputs['Emission Color'].default_value = (*rgb, 1)
        bsdf.inputs['Emission Strength'].default_value = emission
    mat.diffuse_color = (*rgb, 1)
    MATS[name] = mat
    return mat


for key, rgb in PALETTE.items():
    make_material(key, rgb, ROUGH.get(key, 0.45 if key in VINYL or key == 'navy' else 0.7),
                  metallic=1.0 if key in ('stainless', 'duct') else 0.0)
make_material('lamp_on', (1.0, 0.93, 0.78), emission=14.0)
make_material('lamp_warm', (1.0, 0.80, 0.45), emission=10.0)
make_material('exit_sign', (0.9, 0.08, 0.05), emission=6.0)


def make_net_material(name, rgb, cells=16, line=0.16):
    """Knotted safety net as an alpha texture; 1 UV unit = 8 studs, so a mesh is 0.5 stud."""
    size = 256
    img = bpy.data.images.new('L6_' + name, size, size, alpha=True)
    px = [0.0] * (size * size * 4)
    step = size / cells
    for y in range(size):
        fy = (y % step) / step
        for x in range(size):
            fx = (x % step) / step
            on = fx < line or fy < line
            i = (y * size + x) * 4
            px[i:i + 4] = (*rgb, 1.0) if on else (*rgb, 0.0)
    img.pixels = px
    tex_dir = OUT / 'blend' / 'textures'
    tex_dir.mkdir(parents=True, exist_ok=True)
    img.filepath_raw = str(tex_dir / (name + '.png'))
    img.file_format = 'PNG'
    img.save()
    mat = bpy.data.materials.new('L6_' + name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes['Principled BSDF']
    tex = nt.nodes.new('ShaderNodeTexImage')
    tex.image = img
    tex.interpolation = 'Closest'
    nt.links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
    nt.links.new(tex.outputs['Alpha'], bsdf.inputs['Alpha'])
    bsdf.inputs['Roughness'].default_value = 0.8
    try:
        mat.surface_render_method = 'DITHERED'
    except AttributeError:
        mat.blend_method = 'HASHED'
    mat.use_backface_culling = False
    mat.diffuse_color = (*rgb, 0.5)
    MATS[name] = mat


make_net_material('net_blue', (0.05, 0.10, 0.45))
make_net_material('net_black', (0.03, 0.03, 0.03))
make_net_material('net_yellow', (0.80, 0.62, 0.08), cells=12, line=0.2)


PRIMS = []


# ---- mesh builder ------------------------------------------------------------------------
class Builder:
    """Accumulates one mesh object; faces carry a material and get box-projected UVs."""

    def __init__(self, name, col):
        self.name, self.col = name, col
        self.verts, self.faces, self.fmat, self.smooth, self.slots = [], [], [], [], []
        self.rec = True                      # primitives are also recorded for the Studio part import

    def prim(self, *row):
        if self.rec:
            PRIMS.append([self.name, *row])

    def slot(self, mat):
        if mat not in self.slots:
            self.slots.append(mat)
        return self.slots.index(mat)

    def face(self, pts, mat, smooth=False):
        if len(pts) == 4:
            self.prim('q', [*map(float, pts[0]), *map(float, pts[1]), *map(float, pts[3])], mat)
        base = len(self.verts)
        self.verts.extend(tuple(p) for p in pts)
        self.faces.append(tuple(range(base, base + len(pts))))
        self.fmat.append(self.slot(mat))
        self.smooth.append(smooth)

    def box(self, lo, hi, mat):
        x0, y0, z0 = lo
        x1, y1, z1 = hi
        self.prim('b', [x0, y0, z0, x1, y1, z1], mat)
        was, self.rec = self.rec, False
        v = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
             (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
        for idx in ((0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)):
            self.face([v[i] for i in idx], mat)
        self.rec = was

    def cbox(self, c, size, mat):
        self.box((c[0] - size[0] / 2, c[1] - size[1] / 2, c[2] - size[2] / 2),
                 (c[0] + size[0] / 2, c[1] + size[1] / 2, c[2] + size[2] / 2), mat)

    @staticmethod
    def _basis(axis):
        t = Vector(axis).normalized()
        ref = Vector((0, 0, 1)) if abs(t.z) < 0.9 else Vector((1, 0, 0))
        s = t.cross(ref).normalized()
        return t, s, s.cross(t).normalized()

    def cyl(self, p0, p1, r, mat, n=6, caps=False):
        p0, p1 = Vector(p0), Vector(p1)
        self.prim('c', [*p0, *p1, r], mat)
        was, self.rec = self.rec, False
        _, s, u = self._basis(p1 - p0)
        ring = [(math.cos(2 * math.pi * k / n) * s + math.sin(2 * math.pi * k / n) * u) * r for k in range(n)]
        for k in range(n):
            a, b = ring[k], ring[(k + 1) % n]
            self.face([p0 + a, p0 + b, p1 + b, p1 + a], mat, True)
        if caps:
            self.face([p0 + q for q in reversed(ring)], mat)
            self.face([p1 + q for q in ring], mat)
        self.rec = was

    def tube(self, path, r, mats, n=10, a0=0.0, a1=360.0):
        """Sweep along a polyline. a0..a1 (degrees, 270 = straight down) opens it into a chute."""
        path = [Vector(p) for p in path]
        closed = (a1 - a0) >= 359.9
        steps = n if closed else n + 1
        rings = []
        for i, p in enumerate(path):
            t = (path[min(i + 1, len(path) - 1)] - path[max(i - 1, 0)]).normalized()
            s = t.cross(Vector((0, 0, 1)))
            s = s.normalized() if s.length > 1e-4 else Vector((1, 0, 0))
            u = s.cross(t).normalized()
            rings.append([p + (math.cos(math.radians(a0 + (a1 - a0) * k / n)) * s +
                               math.sin(math.radians(a0 + (a1 - a0) * k / n)) * u) * r for k in range(steps)])
        if isinstance(mats, str):
            mats = [mats]
        was, self.rec = self.rec, False
        for i in range(len(path) - 1):
            mat = mats[i % len(mats)]
            if was:
                PRIMS.append([self.name, 't', [*path[i], *path[i + 1], r], mat])
            for k in range(n):
                k2 = (k + 1) % steps if closed else k + 1
                self.face([rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]], mat, True)
        self.rec = was

    def ball(self, c, r, mat):
        c = Vector(c)
        self.prim('s', [*c, r], mat)
        was, self.rec = self.rec, False
        top, bot = c + Vector((0, 0, r)), c - Vector((0, 0, r))
        ring = [c + Vector((math.cos(k * math.pi / 3) * r * 0.87, math.sin(k * math.pi / 3) * r * 0.87, r * 0.5 * z))
                for z in (1, -1) for k in range(6)]
        for k in range(6):
            k2 = (k + 1) % 6
            self.face([top, ring[k], ring[k2]], mat, True)
            self.face([ring[k], ring[6 + k], ring[6 + k2], ring[k2]], mat, True)
            self.face([bot, ring[6 + k2], ring[6 + k]], mat, True)
        self.rec = was

    def finish(self):
        if not self.faces:
            return None
        mesh = bpy.data.meshes.new(self.name)
        mesh.from_pydata(self.verts, [], self.faces)
        for mat in self.slots:
            mesh.materials.append(MATS[mat])
        mesh.polygons.foreach_set('material_index', self.fmat)
        mesh.polygons.foreach_set('use_smooth', self.smooth)
        uv = mesh.uv_layers.new(name='UVMap').data
        for poly in mesh.polygons:
            nrm = poly.normal
            ax = max(range(3), key=lambda a: abs(nrm[a]))
            a, b = [(1, 2), (0, 2), (0, 1)][ax]
            for li in poly.loop_indices:
                co = mesh.vertices[mesh.loops[li].vertex_index].co
                uv[li].uv = (co[a] / 8.0, co[b] / 8.0)
        mesh.update()
        obj = bpy.data.objects.new(self.name, mesh)
        self.col.objects.link(obj)
        return obj


# ==========================================================================================
# 1. Warehouse shell
# ==========================================================================================
shell_col = collection('L6_Shell')
lights_col = collection('L6_Lights')
PARTY = (60, 330, 180, 400)       # blue party/restroom block footprint (x0, y0, x1, y1)
SNACK = (0, 150, 36, 250)         # snack bar alcove


def in_rect(x, y, r, pad=0):
    return r[0] - pad <= x <= r[2] + pad and r[1] - pad <= y <= r[3] + pad


def build_floor():
    slab = Builder('Floor_Concrete', shell_col)
    slab.box((0, 0, -2), (HALL_X, HALL_Y, 0), 'concrete')
    slab.finish()
    tiles = Builder('Floor_FoamTiles', shell_col)
    missing = set()
    for _ in range(26):                                   # torn-up patches, like the reference hall
        cx, cy = rng.randrange(2, HALL_X // TILE - 2), rng.randrange(2, HALL_Y // TILE - 2)
        for dx in range(rng.choice((1, 1, 2))):
            for dy in range(rng.choice((1, 2, 3))):
                missing.add((cx + dx, cy + dy))
    for i in range(HALL_X // TILE):
        for j in range(HALL_Y // TILE + 1):
            if (i, j) in missing:
                continue
            x0, y0 = i * TILE, j * TILE
            y1 = min(y0 + TILE, HALL_Y)
            if y1 <= y0:
                continue
            tiles.box((x0, y0, 0), (x0 + TILE, y1, 0.35), 'mat_green' if (i + j) % 2 else 'mat_blue')
    tiles.finish()


def build_walls():
    w = Builder('Walls', shell_col)
    band = 16

    def run(axis, fixed, colours, inward):
        length = HALL_X if axis == 'x' else HALL_Y
        seg = length / len(colours)
        for k, (low, high) in enumerate(colours):
            a, b = k * seg, (k + 1) * seg
            for z0, z1, mat in ((0, band, low), (band, HALL_Z, high)):
                if axis == 'x':
                    w.box((a, fixed, z0), (b, fixed + inward, z1), mat)
                else:
                    w.box((fixed, a, z0), (fixed + inward, b, z1), mat)

    run('y', -2, [('wall_yellow', 'wall_yellow'), ('wall_yellow', 'wall_white'), ('wall_yellow', 'wall_yellow'),
                  ('wall_blue', 'wall_white')], 2)                                   # west
    run('y', HALL_X, [('wall_red', 'wall_white'), ('wall_blue', 'wall_white'), ('wall_yellow', 'wall_white'),
                      ('wall_red', 'wall_white')], 2)                                # east
    run('x', -2, [('wall_blue', 'wall_yellow'), ('wall_yellow', 'wall_white'), ('wall_red', 'wall_white'),
                  ('wall_blue', 'wall_white'), ('wall_yellow', 'wall_white')], 2)    # south
    run('x', HALL_Y, [('wall_blue', 'wall_blue'), ('wall_blue', 'wall_blue'), ('wall_red', 'wall_red'),
                      ('wall_blue', 'wall_red'), ('wall_yellow', 'wall_white')], 2)  # north
    # skirting + emergency exit on the north wall (the level's way out)
    w.box((0, 0, 0), (HALL_X, 0.4, 1.2), 'black')
    w.box((0, HALL_Y - 0.4, 0), (HALL_X, HALL_Y, 1.2), 'black')
    w.box((0, 0, 0), (0.4, HALL_Y, 1.2), 'black')
    w.box((HALL_X - 0.4, 0, 0), (HALL_X, HALL_Y, 1.2), 'black')
    w.box((540, HALL_Y - 1.0, 0), (556, HALL_Y, 14), 'steel')
    w.box((541, HALL_Y - 1.4, 0.3), (548.5, HALL_Y - 0.9, 13.4), 'wall_red')
    w.box((549, HALL_Y - 1.4, 0.3), (555, HALL_Y - 0.9, 13.4), 'wall_red')
    w.box((545, HALL_Y - 1.6, 15), (551, HALL_Y - 1.0, 17.5), 'exit_sign')
    w.finish()


def build_ceiling():
    c = Builder('Ceiling_Structure', shell_col)
    c.box((0, 0, HALL_Z), (HALL_X, HALL_Y, HALL_Z + 1), 'deck')
    for x in range(0, HALL_X + 1, 8):                                  # deck ribs
        c.box((x - 0.5, 0, HALL_Z - 0.6), (x + 0.5, HALL_Y, HALL_Z), 'deck')
    for gx in range(100, HALL_X, 100):                                 # girders on column lines
        c.box((gx - 1, 0, HALL_Z - 7), (gx + 1, HALL_Y, HALL_Z - 6.4), 'steel')
        c.box((gx - 0.3, 0, HALL_Z - 6.4), (gx + 0.3, HALL_Y, HALL_Z - 1.2), 'steel')
        c.box((gx - 1, 0, HALL_Z - 1.2), (gx + 1, HALL_Y, HALL_Z - 0.6), 'steel')
    for y in range(20, HALL_Y, 20):                                    # open-web joists
        c.box((0, y - 0.5, HALL_Z - 1.1), (HALL_X, y + 0.5, HALL_Z - 0.6), 'steel')
        c.box((0, y - 0.5, HALL_Z - 5.0), (HALL_X, y + 0.5, HALL_Z - 4.5), 'steel')
        for x in range(0, HALL_X, 10):
            up = (x // 10) % 2 == 0
            c.cyl((x, y, HALL_Z - (4.6 if up else 1.0)), (x + 10, y, HALL_Z - (1.0 if up else 4.6)), 0.22, 'steel', 4)
    c.finish()

    m = Builder('Ceiling_Services', shell_col)
    for dy in (118, 286):                                              # main ducts with drops
        m.cyl((10, dy, HALL_Z - 12), (HALL_X - 10, dy, HALL_Z - 12), 3.6, 'duct', 12, True)
        for x in range(40, HALL_X - 20, 70):
            m.cyl((x, dy, HALL_Z - 15.4), (x, dy, HALL_Z - 17.5), 2.2, 'duct', 8, True)
            m.cyl((x, dy, HALL_Z - 8.4), (x, dy, HALL_Z - 5), 0.15, 'steel', 4)
    m.box((300, 196, HALL_Z - 14), (340, 212, HALL_Z - 8), 'duct')    # rooftop unit plenum
    for x in range(30, HALL_X, 60):                                    # sprinkler mains
        m.cyl((x, 4, HALL_Z - 8.5), (x, HALL_Y - 4, HALL_Z - 8.5), 0.35, 'pipe_red', 5)
    m.cyl((6, 60, HALL_Z - 9.5), (HALL_X - 6, 60, HALL_Z - 9.5), 0.5, 'pipe_red', 6)
    m.finish()

    # fluorescent troffers: most are dead, a handful still burn
    fx = Builder('Ceiling_Fixtures', shell_col)
    lit = []
    forced = {(25, 175), (25, 225), (125, 375), (275, 75), (525, 375)}
    for x in range(25, HALL_X, 50):
        for y in range(25, HALL_Y, 50):
            z = HALL_Z - 13
            on = (x, y) in forced or rng.random() < 0.16
            fx.box((x - 6, y - 2, z), (x + 6, y + 2, z + 1.2), 'wall_white')
            fx.box((x - 5.6, y - 1.6, z - 0.12), (x + 5.6, y + 1.6, z), 'lamp_on' if on else 'lamp_off')
            for ox in (-5, 5):
                fx.cyl((x + ox, y, z + 1.2), (x + ox, y, HALL_Z - 4.6), 0.08, 'steel', 3)
            if on:
                lit.append((x, y, z))
    fx.finish()
    for n, (x, y, z) in enumerate(lit):
        data = bpy.data.lights.new(f'L6_Troffer_{n:02d}', 'AREA')
        data.shape, data.size, data.size_y = 'RECTANGLE', 11, 3
        data.energy, data.color = 26000, (1.0, 0.94, 0.82)
        obj = bpy.data.objects.new(data.name, data)
        obj.location = (x, y, z - 0.4)
        lights_col.objects.link(obj)
    return lit


def build_columns():
    col = Builder('Hall_Columns', shell_col)
    for gx in range(100, HALL_X, 100):
        for gy in (100, 200, 300):
            if SX - 4 <= gx <= SX + NX * C + 4 and SY - 4 <= gy <= SY + NY * C + 4:
                continue                                   # the play frame carries its own posts
            if in_rect(gx, gy, PARTY, 4):
                continue
            col.box((gx - 1, gy - 1, 0), (gx + 1, gy + 1, HALL_Z - 7), 'steel')
            col.box((gx - 1.8, gy - 1.8, 0.35), (gx + 1.8, gy + 1.8, 9), 'blue' if (gx + gy) % 200 else 'yellow')
            col.cyl((gx, gy, 9), (gx, gy, 9.3), 2.2, 'black', 8, True)
    col.finish()


# ==========================================================================================
# 2. The play frame
# ==========================================================================================
frame_col = collection('L6_PlayFrame')
BALLPIT = (2, 2, 7, 6)            # cell rectangles (i0, j0, i1, j1), inclusive
ATRIUM = (10, 9, 15, 14)
PUNCH = (2, 16, 6, 20)
ENTRANCES = (4, 12, 21)           # west-face ground openings (cell j)
SPIRAL = (19, 3)                  # the spiral slide drops through this cell's decks
# (storey, cell, cell) bays left completely open so a slide, tube or bridge can be entered
PASSAGES = {
    (2, (-1, 8), (0, 8)), (2, (-1, 18), (0, 18)),           # tube slides out of the west face
    (2, (15, 9), (16, 9)), (2, (15, 10), (16, 10)),         # top of the wave slide
    (1, (10, 8), (10, 9)), (1, (10, 14), (10, 15)),         # crawl tube across the atrium, storey 1
    (2, (9, 14), (10, 14)), (2, (15, 14), (16, 14)),        # crawl tube, storey 2
    (2, (9, 11), (10, 11)), (2, (15, 11), (16, 11)),        # net bridge ends
    (2, (18, 3), (19, 3)),                                  # spiral slide entry
}
NO_STAIRS = {cell for _, a, b in PASSAGES for cell in (a, b)} | {SPIRAL}


def in_cells(i, j, r):
    return r[0] <= i <= r[2] and r[1] <= j <= r[3]


def void(k, i, j):
    """No deck here: the space is open to the storey below."""
    if k == 1 and in_cells(i, j, BALLPIT):
        return True
    if k >= 1 and (i, j) == SPIRAL:
        return True
    return k >= 1 and in_cells(i, j, ATRIUM)


def cell_origin(i, j, k):
    return SX + i * C, SY + j * C, k * H


def plan_stairs():
    """Soft-step flights rising toward +X; the cell above loses its deck and lands on (i+1, j)."""
    stairs, taken = {}, set()
    for k in (0, 1):
        want, tries = 9, 0
        while want and tries < 4000:
            tries += 1
            i, j = rng.randrange(1, NX - 1), rng.randrange(0, NY)
            if (i, j) in taken or (i + 1, j) in taken or (i - 1, j) in taken:
                continue
            if any(c in NO_STAIRS for c in ((i, j), (i + 1, j), (i - 1, j))):
                continue
            if any(in_cells(a, j, r) for a in (i - 1, i, i + 1) for r in (BALLPIT, ATRIUM, PUNCH)):
                continue
            if any(abs(i - a) + abs(j - b) < 5 for (kk, a, b) in stairs if kk == k):
                continue
            stairs[(k, i, j)] = True
            taken.update({(i, j), (i + 1, j), (i - 1, j)})
            want -= 1
    return stairs


STAIRS = plan_stairs()


def stairwell(k, i, j):
    return k >= 1 and (k - 1, i, j) in STAIRS


def walkable(k, i, j):
    if not (0 <= i < NX and 0 <= j < NY and 0 <= k < NZ):
        return False
    return not void(k, i, j) and not stairwell(k, i, j)


def plan_maze():
    """Per storey: a spanning tree of openings so every cell is reachable, plus extra loops."""
    opened = set()
    for k in range(NZ):
        cells = [(i, j) for i in range(NX) for j in range(NY) if walkable(k, i, j)]
        seen, stack = {cells[0]}, [cells[0]]
        while stack:
            i, j = stack[-1]
            nbrs = [(a, b) for a, b in ((i + 1, j), (i - 1, j), (i, j + 1), (i, j - 1))
                    if walkable(k, a, b) and (a, b) not in seen]
            if not nbrs:
                stack.pop()
                continue
            nxt = rng.choice(nbrs)
            opened.add((k, min((i, j), nxt), max((i, j), nxt)))
            seen.add(nxt)
            stack.append(nxt)
        for comp_seed in cells:                      # islands cut off by voids get their own tree
            if comp_seed in seen:
                continue
            seen.add(comp_seed)
            stack = [comp_seed]
            while stack:
                i, j = stack[-1]
                nbrs = [(a, b) for a, b in ((i + 1, j), (i - 1, j), (i, j + 1), (i, j - 1))
                        if walkable(k, a, b) and (a, b) not in seen]
                if not nbrs:
                    stack.pop()
                    continue
                nxt = rng.choice(nbrs)
                opened.add((k, min((i, j), nxt), max((i, j), nxt)))
                seen.add(nxt)
                stack.append(nxt)
        extra = 0.42 if k == 0 else 0.26
        for i, j in cells:
            for a, b in ((i + 1, j), (i, j + 1)):
                if walkable(k, a, b) and rng.random() < extra:
                    opened.add((k, (i, j), (a, b)))
    return opened


OPENED = plan_maze()


def interface(k, a, b):
    """What stands between neighbouring cells a and b on storey k."""
    (i, j), (p, q) = a, b
    if (k, min(a, b), max(a, b)) in PASSAGES:
        return 'none'
    inside_a = 0 <= i < NX and 0 <= j < NY
    inside_b = 0 <= p < NX and 0 <= q < NY
    if not inside_a and not inside_b:
        return 'none'
    if not (inside_a and inside_b):                                   # frame perimeter
        ii, jj = (i, j) if inside_a else (p, q)
        if k == 0 and (i < 0 or p < 0) and jj in ENTRANCES:
            return 'arch'
        return 'net'
    for r in (BALLPIT, ATRIUM, PUNCH):                                # feature zones stay open inside
        if in_cells(i, j, r) and in_cells(p, q, r) and (k == 0 or r is PUNCH):
            return 'open'
    va, vb = void(k, i, j), void(k, p, q)
    if va and vb:
        return 'none'
    if va or vb:
        return 'net'
    if k == 0 and (in_cells(i, j, BALLPIT) != in_cells(p, q, BALLPIT)):
        return 'pit_gap' if (min(a, b), max(a, b)) in PIT_GAPS else 'pit'
    sa, sb = stairwell(k, i, j), stairwell(k, p, q)
    if sa or sb:
        (wi, wj), (oi, oj) = (a, b) if sa else (b, a)
        return 'open' if (oi, oj) == (wi + 1, wj) else 'net'          # only the landing side is open
    if (k, i, j) in STAIRS or (k, p, q) in STAIRS:
        (ti, tj), (oi, oj) = (a, b) if (k, i, j) in STAIRS else (b, a)
        if (oi, oj) == (ti - 1, tj):
            return 'open'                                             # foot of the flight
        if (oi, oj) == (ti + 1, tj):
            return 'panel'                                            # under the top steps
        return 'net'
    if (k, min(a, b), max(a, b)) in OPENED:
        return 'open'
    return 'panel' if rng.random() < 0.28 else 'net'


PIT_GAPS = {((1, 4), (2, 4)), ((7, 3), (8, 3)), ((5, 6), (5, 7))}


def build_frame():
    posts, beams = Builder('Frame_Posts', frame_col), Builder('Frame_Beams', frame_col)
    post_cols = ['yellow', 'yellow', 'green', 'red', 'yellow', 'blue']
    top = NZ * H
    for i in range(NX + 1):
        for j in range(NY + 1):
            if all(in_cells(a, b, ATRIUM) for a in (i - 1, i) for b in (j - 1, j)):
                continue                                              # keep the atrium clear
            if all(in_cells(a, b, BALLPIT) for a in (i - 1, i) for b in (j - 1, j)):
                z0 = H * 2                                            # pit is double height
            else:
                z0 = 0
            x, y = SX + i * C, SY + j * C
            posts.cyl((x, y, z0), (x, y, top), POST_R, post_cols[(i // 5 + (j // 6) * 2) % len(post_cols)], 8)
            if z0 == 0:
                posts.cyl((x, y, 0), (x, y, 0.5), POST_R + 0.35, 'black', 8, True)
    posts.finish()
    beam_cols = ['green', 'red', 'blue', 'yellow']
    for k in range(1, NZ + 1):
        z = k * H
        for j in range(NY + 1):
            for i in range(NX):
                if k < NZ and all(void(k, i, b) for b in (j - 1, j) if 0 <= b < NY):
                    continue
                beams.cyl((SX + i * C, SY + j * C, z), (SX + (i + 1) * C, SY + j * C, z), BEAM_R,
                          beam_cols[(j + k) % 4], 6)
        for i in range(NX + 1):
            for j in range(NY):
                if k < NZ and all(void(k, a, j) for a in (i - 1, i) if 0 <= a < NX):
                    continue
                beams.cyl((SX + i * C, SY + j * C, z), (SX + i * C, SY + (j + 1) * C, z), BEAM_R,
                          beam_cols[(i + k + 1) % 4], 6)
    beams.finish()


def build_decks():
    decks = Builder('Frame_Decks', frame_col)
    for k in range(NZ):
        for i in range(NX):
            for j in range(NY):
                if k and (void(k, i, j) or stairwell(k, i, j)):
                    continue
                x, y, z = cell_origin(i, j, k)
                if k == 0 and in_cells(i, j, BALLPIT):
                    decks.box((x, y, 0.35), (x + C, y + C, 0.6), 'navy')
                    continue
                mat = rng.choice(VINYL)
                if k == 0:
                    decks.box((x + 0.15, y + 0.15, 0.35), (x + C - 0.15, y + C - 0.15, 0.95), mat)
                else:
                    decks.box((x + 0.3, y + 0.3, z - 0.35), (x + C - 0.3, y + C - 0.3, z + 0.35), mat)
    decks.finish()
    roof = Builder('Frame_RoofNet', frame_col)
    roof.face([(SX, SY, NZ * H), (SX + NX * C, SY, NZ * H), (SX + NX * C, SY + NY * C, NZ * H),
               (SX, SY + NY * C, NZ * H)], 'net_black')
    roof.finish()


def build_walls_of_frame():
    nets, pads = Builder('Frame_Nets', frame_col), Builder('Frame_Panels', frame_col)
    arches = Builder('Frame_Entrances', frame_col)

    def wall(kind, k, p0, p1):
        """p0 -> p1 is the bottom edge of the bay, post to post."""
        z = k * H
        (x0, y0), (x1, y1) = p0, p1
        along_x = abs(x1 - x0) > abs(y1 - y0)
        inset = POST_R + 0.1
        if along_x:
            x0, x1 = x0 + inset, x1 - inset
        else:
            y0, y1 = y0 + inset, y1 - inset
        zb = z + (0.95 if k == 0 else 0.35)
        zt = z + H - BEAM_R

        def net(za, zc, mat='net_blue'):
            nets.face([(x0, y0, za), (x1, y1, za), (x1, y1, zc), (x0, y0, zc)], mat)

        def pad(za, zc, mat, thick=0.9):
            if along_x:
                pads.box((x0, y0 - thick / 2, za), (x1, y0 + thick / 2, zc), mat)
            else:
                pads.box((x0 - thick / 2, y0, za), (x0 + thick / 2, y1, zc), mat)

        if kind == 'net':
            net(zb, zt, 'net_blue' if rng.random() < 0.8 else 'net_yellow')
        elif kind == 'panel':
            pad(zb, z + 5, rng.choice(VINYL))
            net(z + 5, zt)
        elif kind == 'pit':
            pad(0.35, 3.4, rng.choice(('red', 'blue', 'yellow')), 1.6)
            net(3.4, zt)
        elif kind == 'pit_gap':
            pad(0.35, 3.4, 'green', 1.6)
        elif kind == 'arch':
            pad(z + 7.6, zt, 'red', 1.2)
            if along_x:
                arches.box((x0, y0 - 0.7, z + 8.2), (x1, y0 - 0.6, z + 9.4), 'yellow')
            else:
                arches.box((x0 - 0.7, y0, z + 8.2), (x0 - 0.6, y1, z + 9.4), 'yellow')

    for k in range(NZ):
        for i in range(-1, NX):
            for j in range(NY):                                       # walls on the x = const plane
                kind = interface(k, (i, j), (i + 1, j))
                if kind not in ('open', 'none'):
                    x = SX + (i + 1) * C
                    wall(kind, k, (x, SY + j * C), (x, SY + (j + 1) * C))
        for j in range(-1, NY):
            for i in range(NX):                                       # walls on the y = const plane
                kind = interface(k, (i, j), (i, j + 1))
                if kind not in ('open', 'none'):
                    y = SY + (j + 1) * C
                    wall(kind, k, (SX + i * C, y), (SX + (i + 1) * C, y))
    nets.finish()
    pads.finish()
    arches.finish()


def build_stairs():
    s = Builder('Frame_SoftSteps', frame_col)
    for (k, i, j) in STAIRS:
        x, y, z = cell_origin(i, j, k)
        z += 0.95 if k == 0 else 0.35
        rise = (k + 1) * H + 0.35 - z
        for n in range(5):
            s.box((x + n * 2.4, y + 0.8, z), (x + (n + 1) * 2.4, y + C - 0.8, z + rise * (n + 1) / 5),
                  VINYL[(n + i + j) % len(VINYL)])
    s.finish()


def build_play_features():
    f = Builder('Frame_PlayFeatures', frame_col)
    # punch-bag forest hanging from the first deck
    for i in range(PUNCH[0], PUNCH[2] + 1):
        for j in range(PUNCH[1], PUNCH[3] + 1):
            for _ in range(2):
                x = SX + i * C + rng.uniform(2.5, 9.5)
                y = SY + j * C + rng.uniform(2.5, 9.5)
                f.cyl((x, y, 9.4), (x, y, 7.6), 0.07, 'black', 3)
                f.cyl((x, y, 7.6), (x, y, 2.2), 1.15, rng.choice(('navy', 'red', 'blue', 'purple')), 8, True)
    # roller squeezes and hanging barrel rows across open bays on the upper storeys (soft: no collision)
    rollers = Builder('Frame_Rollers', frame_col)
    placed = 0
    for k in (1, 2):
        for i in range(NX - 1):
            for j in range(NY):
                if placed > 26 or not (walkable(k, i, j) and walkable(k, i + 1, j)):
                    continue
                if (k, (i, j), (i + 1, j)) in OPENED and rng.random() < 0.10:
                    x, y, z = SX + (i + 1) * C, SY + j * C, k * H
                    cols = [rng.choice(VINYL) for _ in range(4)]
                    for n, zz in enumerate((2.0, 4.3, 6.6, 8.6)):
                        rollers.cyl((x, y + 1, z + zz), (x, y + C - 1, z + zz), 1.05, cols[n], 8, True)
                    f.box((x - 0.25, y + 0.7, z + 0.6), (x + 0.25, y + 1.0, z + 9.5), 'black')
                    f.box((x - 0.25, y + C - 1.0, z + 0.6), (x + 0.25, y + C - 0.7, z + 9.5), 'black')
                    placed += 1
    rollers.finish()
    # crawl tubes spanning the atrium and a net bridge across it
    ax0, ay0 = SX + ATRIUM[0] * C, SY + ATRIUM[1] * C
    ax1, ay1 = SX + (ATRIUM[2] + 1) * C, SY + (ATRIUM[3] + 1) * C
    f.tube([(ax0 + 6, ay0 - 1, 13.2)] + [(ax0 + 6, ay0 + t, 13.2) for t in range(0, int(ay1 - ay0) + 1, 6)] +
           [(ax0 + 6, ay1 + 1, 13.2)], 2.9, ['red', 'yellow', 'blue', 'green'], 10)
    f.tube([(ax0 - 1, ay1 - 6, 23.2)] + [(ax0 + t, ay1 - 6, 23.2) for t in range(0, int(ax1 - ax0) + 1, 6)] +
           [(ax1 + 1, ay1 - 6, 23.2)], 2.9, ['cyan', 'purple', 'orange', 'pink'], 10)
    by = ay0 + 30
    f.box((ax0, by - 2.5, 19.65), (ax1, by + 2.5, 20.35), 'yellow')
    f.finish()
    bn = Builder('Frame_BridgeNets', frame_col)
    for s in (-2.5, 2.5):
        bn.face([(ax0, by + s, 20.35), (ax1, by + s, 20.35), (ax1, by + s, 26), (ax0, by + s, 26)], 'net_yellow')
    bn.finish()


def build_slides():
    s = Builder('Frame_Slides', frame_col)
    ax0, ay0 = SX + ATRIUM[0] * C, SY + ATRIUM[1] * C
    ax1 = SX + (ATRIUM[2] + 1) * C
    # triple wave slide dropping from the second deck into the atrium
    y0, lanes, lane_w = ay0 + 5, 3, 5.0
    pts = []
    for n in range(0, 25):
        t = n / 24
        x = ax1 - t * 62
        z = 20.3 - 19.2 * t + 1.1 * math.sin(t * math.pi * 3) * (1 - t)
        pts.append((x, max(z, 1.0)))
    wave = Builder('Frame_WaveSlide', frame_col)
    for lane in range(lanes):
        ya, yb = y0 + lane * lane_w, y0 + (lane + 1) * lane_w
        mat = ('yellow', 'red', 'blue')[lane]
        for (xa, za), (xb, zb) in zip(pts, pts[1:]):
            wave.face([(xa, ya, za), (xa, yb, za), (xb, yb, zb), (xb, ya, zb)], mat, True)
            for yy in (ya, yb):
                wave.face([(xa, yy, za), (xb, yy, zb), (xb, yy, zb + 1.3), (xa, yy, za + 1.3)], 'green')
    wave.finish()
    for (x, z) in pts[::4]:
        for yy in (y0, y0 + lanes * lane_w):
            if z > 2:
                s.cyl((x, yy, 0.9), (x, yy, z), 0.3, 'steel', 5)
    # two tube slides leaving the west face from the top storey
    for jy, bend in ((8, -1), (18, 1)):
        y = SY + jy * C + C / 2
        path = [(SX + 3, y, 23.3), (SX - 4, y, 23.0)]
        for n in range(1, 15):
            t = n / 14
            path.append((SX - 4 - 46 * t, y + bend * 22 * math.sin(t * math.pi / 2) ** 2, 23.0 - 19.5 * t ** 0.85))
        path.append((path[-1][0] - 6, path[-1][1] + bend * 1.5, 3.2))
        s.tube(path, 3.1, ['red', 'red', 'yellow'] if bend < 0 else ['blue', 'green', 'blue', 'yellow'], 12)
        for p in path[4::4]:
            s.cyl((p[0], p[1], 0.35), (p[0], p[1], p[2] - 3.0), 0.35, 'steel', 5)
    # spiral tube in the south-east tower
    cx, cy = SX + 19 * C + C / 2, SY + 3 * C + C / 2
    path = [(cx + 5.2 * math.cos(math.pi + a), cy + 5.2 * math.sin(math.pi + a), 23.4 - 20.2 * (a / (math.pi * 5)))
            for a in [n * math.pi / 8 for n in range(0, 41)]]     # starts on the west side, by the entry bay
    path.append((path[-1][0] - 5, path[-1][1] - 5, 3.0))
    s.tube(path, 2.7, ['purple', 'yellow', 'cyan', 'red'], 10)
    s.cyl((cx, cy, 0.9), (cx, cy, 26), 0.6, 'steel', 8)
    s.finish()


def build_ball_pit():
    b = Builder('BallPit_Balls', frame_col)
    x0, y0 = SX + BALLPIT[0] * C + 1.5, SY + BALLPIT[1] * C + 1.5
    x1, y1 = SX + (BALLPIT[2] + 1) * C - 1.5, SY + (BALLPIT[3] + 1) * C - 1.5
    cols = ('red', 'yellow', 'blue', 'green', 'orange')
    for _ in range(1500):
        b.ball((rng.uniform(x0, x1), rng.uniform(y0, y1), rng.uniform(1.0, 2.6)), 0.55, rng.choice(cols))
    b.finish()
    stray = Builder('Stray_Balls', frame_col)
    for _ in range(170):                                             # the ones that got away
        cx, cy = rng.choice(((x0 - 25, y0 + 30), (x0 + 30, y0 - 20), (200, 200), (120, 90), (260, 300)))
        stray.ball((cx + rng.gauss(0, 30), max(3, cy + rng.gauss(0, 30)), 0.9), 0.55, rng.choice(cols))
    stray.finish()


def build_frame_lights():
    """A few caged work lamps still burning inside the frame; the rest of it stays dark."""
    lamps = Builder('Frame_Lamps', frame_col)
    spots = [(4, 4, 2), (12, 11, 2), (4, 18, 0), (18, 6, 1), (9, 22, 1), (19, 19, 2), (14, 3, 0), (8, 13, 0)]
    for n, (i, j, k) in enumerate(spots):
        x, y, z = SX + i * C + C / 2, SY + j * C + C / 2, (k + 1) * H - 1.2
        lamps.cbox((x, y, z + 0.4), (3.0, 1.0, 0.5), 'wall_white')
        lamps.cbox((x, y, z + 0.1), (2.6, 0.7, 0.14), 'lamp_warm' if n % 3 == 0 else 'lamp_on')
        data = bpy.data.lights.new(f'L6_FrameLamp_{n}', 'POINT')
        data.energy, data.color = 2600, (1.0, 0.86, 0.62) if n % 3 == 0 else (0.95, 0.97, 1.0)
        data.shadow_soft_size = 0.6
        obj = bpy.data.objects.new(data.name, data)
        obj.location = (x, y, z - 0.6)
        lights_col.objects.link(obj)
    lamps.finish()


# ==========================================================================================
# 3. Front of house: snack bar, party block, reception, toddler corner, party tables
# ==========================================================================================
foh_col = collection('L6_FrontOfHouse')


def build_snack_bar():
    s = Builder('SnackBar', foh_col)
    x0, y0, x1, y1 = SNACK
    s.box((0, y0, 0), (1, y1, 22), 'wall_yellow')                    # back wall
    s.box((0, y0, 16), (x1 - 4, y1, 22), 'wall_yellow')              # header
    s.box((0, y0, 15.4), (x1 - 4, y1, 16), 'wall_white')
    for y in (y0, y0 + 33, y0 + 66, y1 - 2):
        s.box((x1 - 7, y, 0), (x1 - 4, y + 2, 16), 'wall_yellow')    # pillars
    s.box((x1 - 6.5, y0 + 2, 0), (x1 - 4.5, y1 - 2, 4.2), 'white')   # counter front
    s.box((x1 - 9.5, y0 + 2, 4.2), (x1 - 3.4, y1 - 2, 4.7), 'counter')
    s.box((x1 - 6.5, y0 + 40, 0), (x1 - 4.5, y0 + 48, 4.7), 'steel')  # staff gate
    for y in range(y0 + 6, y1 - 12, 22):
        s.box((1, y, 9.5), (1.5, y + 14, 14.5), 'black')             # menu boards
        s.box((1.5, y + 1, 10.2), (1.6, y + 13, 13.8), 'paper')
    s.box((2, y0 + 4, 0), (9, y1 - 4, 4.4), 'stainless')             # back counter
    s.box((2, y0 + 12, 4.4), (7, y0 + 20, 8.5), 'stainless')         # popcorn / slush machines
    s.box((2, y0 + 60, 4.4), (7, y0 + 67, 9.5), 'red')
    s.box((x1 + 2, y0 - 12, 0), (x1 + 9, y0 - 3, 11), 'stainless')   # drinks fridge
    s.box((x1 + 8.6, y0 - 11.4, 1), (x1 + 9.1, y0 - 3.6, 10.4), 'black')
    for y in (y0 + 16, y0 + 50, y0 + 83):
        s.box((6, y - 5, 15.2), (22, y - 4, 15.4), 'lamp_warm')
        s.box((6, y + 4, 15.2), (22, y + 5, 15.4), 'lamp_warm')
    s.finish()
    for n, y in enumerate((y0 + 16, y0 + 50, y0 + 83)):
        data = bpy.data.lights.new(f'L6_SnackBar_{n}', 'AREA')
        data.shape, data.size, data.size_y = 'RECTANGLE', 14, 9
        data.energy, data.color = 9000, (1.0, 0.78, 0.40)
        obj = bpy.data.objects.new(data.name, data)
        obj.location = (14, y, 15.0)
        lights_col.objects.link(obj)


def build_party_block():
    p = Builder('PartyBlock', foh_col)
    x0, y0, x1, y1 = PARTY
    h, t = 26, 1.5
    door0, door1 = 112, 128
    p.box((x0, y0, 0), (door0, y0 + t, h), 'wall_blue')              # south face with the doorway
    p.box((door1, y0, 0), (x1, y0 + t, h), 'wall_blue')
    p.box((door0, y0, 13), (door1, y0 + t, h), 'wall_blue')
    p.box((x0, y0, 0), (x0 + t, y1, h), 'wall_blue')
    p.box((x1 - t, y0, 0), (x1, y1, h), 'wall_blue')
    p.box((x0, y0, h), (x1, y1, h + 0.6), 'wall_white')
    p.box((x0 + t, y0 + t, 0.02), (x1 - t, y1, 0.1), 'wall_white')   # bare vinyl floor inside
    for n, mat in enumerate(('wall_blue', 'wall_red', 'wall_yellow')):
        xa = 104 + n * 10                                            # stall partitions seen through the door
        p.box((xa, y0 + 22, 0.6), (xa + 9.4, y0 + 22.6, 12), mat)
        p.box((xa + 4, y0 + 21.7, 6), (xa + 5.4, y0 + 22, 8.4), 'paper')
    p.box((x0 + t, y0 + 40, 0), (x1 - t, y0 + 40.8, 14), 'wall_white')
    for xa, za, w_, h_ in ((84, 7, 3.2, 2.2), (92, 6, 1.4, 4.4), (133, 6.4, 3.6, 2.6), (140, 6.4, 1.6, 4.0)):
        p.box((xa, y0 - 0.12, za), (xa + w_, y0, za + h_), 'paper')  # taped notices
    p.box((150, y0 - 4, 0), (156, y0, 5.2), 'stainless')             # drinking fountains
    p.box((158, y0 - 4, 0), (164, y0, 4.2), 'stainless')
    p.cyl((132, y0 - 3, 0.35), (132, y0 - 3, 0.6), 1.5, 'orange', 8, True)
    p.tube([(132, y0 - 3, 0.6), (132, y0 - 3, 4.4)], 1.1, 'orange', 8)
    p.finish()
    data = bpy.data.lights.new('L6_PartyBlock', 'AREA')
    data.shape, data.size, data.size_y = 'RECTANGLE', 20, 8
    data.energy, data.color = 7000, (0.92, 0.95, 1.0)
    obj = bpy.data.objects.new(data.name, data)
    obj.location = (120, y0 + 18, 24)
    lights_col.objects.link(obj)


def build_reception():
    r = Builder('Reception', foh_col)
    r.box((40, 24, 0), (96, 30, 4.6), 'blue')                        # desk
    r.box((38, 23, 4.6), (98, 31, 5.1), 'yellow')
    r.box((40, 30, 0), (46, 52, 4.6), 'blue')
    r.box((38, 30, 4.6), (48, 54, 5.1), 'yellow')
    r.box((56, 31, 5.1), (62, 34, 8.2), 'black')                     # till
    for n in range(4):                                               # entry gates
        x = 112 + n * 9
        r.box((x, 22, 0), (x + 1.2, 34, 4.4), 'stainless')
        if n < 3:
            r.box((x + 1.2, 27.6, 3.2), (x + 8, 28.2, 3.8), 'red')
    # shoe cubbies along the south wall
    x0, x1 = 160, 256
    r.box((x0, 1, 0), (x1, 5.5, 0.5), 'wood')
    for row in range(1, 6):
        r.box((x0, 1, row * 2.5), (x1, 5.5, row * 2.5 + 0.3), 'wood')
    for cx in range(x0, x1 + 1, 4):
        r.box((cx, 1, 0), (cx + 0.3, 5.5, 12.8), 'wood')
    r.box((x0, 0.4, 0), (x1, 1, 12.8), 'wood')
    for _ in range(46):                                              # shoes nobody came back for
        cx = x0 + 4 * rng.randrange(0, 24) + 0.7
        cz = 2.5 * rng.randrange(0, 5) + 0.5
        r.box((cx, 2, cz), (cx + 2.2, 4.6, cz + 0.9), rng.choice(('white', 'red', 'navy', 'black', 'pink')))
    r.box((x0, 7, 0), (x1, 11, 2.2), 'red')                          # bench
    r.finish()


def build_toddler_corner():
    t = Builder('ToddlerCorner', foh_col)
    x0, y0, x1, y1 = 192, 44, 282, 128
    cols = ('red', 'yellow', 'blue', 'green')
    n = 0
    for x in range(x0, x1, 6):                                       # low padded fence, gap on the north side
        for y in (y0, y1):
            if y == y1 and x0 + 36 <= x < x0 + 48:
                continue
            t.box((x, y - 0.7, 0.35), (x + 5.8, y + 0.7, 3.6), cols[n % 4])
            n += 1
    for y in range(y0, y1, 6):
        for x in (x0, x1):
            t.box((x - 0.7, y, 0.35), (x + 0.7, y + 5.8, 3.6), cols[n % 4])
            n += 1
    t.box((x0 + 2, y0 + 2, 0.35), (x1 - 2, y1 - 2, 0.9), 'red')      # crash mat
    t.box((x0 + 6, y0 + 3, 0.9), (x0 + 60, y0 + 4.2, 11), 'blue')    # painted farm-animal panel
    t.box((x0 + 6, y0 + 4.2, 0.9), (x0 + 60, y0 + 4.4, 4.2), 'green')
    for cx, rad, mat in ((x0 + 18, 3.2, 'pink'), (x0 + 34, 3.4, 'white'), (x0 + 49, 2.8, 'yellow')):
        t.cyl((cx, y0 + 4.2, 5.4), (cx, y0 + 4.6, 5.4), rad, mat, 12, True)
        t.cyl((cx + rad * 0.8, y0 + 4.2, 7.6), (cx + rad * 0.8, y0 + 4.7, 7.6), rad * 0.55, mat, 10, True)
    # soft shapes
    t.box((x0 + 14, y0 + 30, 0.9), (x0 + 22, y0 + 38, 4.9), 'yellow')
    t.box((x0 + 22, y0 + 30, 0.9), (x0 + 30, y0 + 38, 2.9), 'blue')
    t.cyl((x0 + 44, y0 + 30, 2.9), (x0 + 44, y0 + 44, 2.9), 2.0, 'green', 10, True)
    t.cyl((x0 + 58, y0 + 52, 0.9), (x0 + 58, y0 + 52, 5.4), 3.0, 'purple', 10, True)
    t.box((x0 + 66, y0 + 20, 0.9), (x0 + 74, y0 + 26, 7.0), 'red')   # baby slide
    for n in range(9):
        t.box((x0 + 66 + 0.6, y0 + 26 + n * 1.6, 0.9), (x0 + 74 - 0.6, y0 + 27.6 + n * 1.6, 6.6 - n * 0.62),
              'yellow')
    for cx, cy in ((x0 + 20, y0 + 60), (x0 + 30, y0 + 66), (x0 + 72, y0 + 62)):  # rocking animals
        t.cbox((cx, cy, 2.0), (5.5, 2.2, 2.2), rng.choice(('pink', 'cyan', 'orange')))
        t.cbox((cx + 2.8, cy, 3.4), (1.8, 1.8, 2.0), 'white')
    t.box((x0 + 40, y1 - 14, 0.9), (x0 + 62, y1 - 4, 2.6), 'cyan')   # mini ball pool rim
    t.box((x0 + 41.5, y1 - 12.5, 0.9), (x0 + 60.5, y1 - 5.5, 2.7), 'navy')
    for sx, sy in ((x0 + 5, y1 + 0.8), (x0 + 60, y1 + 0.8)):         # rule signs
        t.box((sx, sy, 4.5), (sx + 7, sy + 0.2, 8.5), 'yellow')
    t.finish()
    balls = Builder('Toddler_Balls', foh_col)
    for _ in range(190):
        balls.ball((rng.uniform(x0 + 42.5, x0 + 59.5), rng.uniform(y1 - 11.5, y1 - 6.5), rng.uniform(1.3, 2.4)),
                   0.55, rng.choice(('red', 'yellow', 'blue', 'green')))
    balls.finish()


TABLES = []
HOME = (262, 214)                 # where the child counts; players "dunk" here to score


def build_party_tables():
    t = Builder('PartyTables', foh_col)
    for gx in range(70, 250, 42):
        for gy in range(160, 310, 34):
            if rng.random() < 0.12 or (abs(gx + 11 - HOME[0]) < 34 and abs(gy + 3 - HOME[1]) < 26):
                continue                                             # keep the counting mat clear
            x, y = gx + rng.uniform(-3, 3), gy + rng.uniform(-3, 3)
            top = rng.choice(('red', 'blue', 'yellow', 'green'))
            TABLES.append((x + 11, y + 3.5))
            t.box((x, y, 3.4), (x + 22, y + 7, 3.9), top)
            for bx in (x + 2, x + 19):
                t.box((bx, y + 0.5, 0.35), (bx + 1, y + 6.5, 3.4), 'steel')
            for by in (y - 5, y + 9):
                t.box((x, by, 2.0), (x + 22, by + 3, 2.4), top)
                for bx in (x + 2, x + 19):
                    t.box((bx, by + 0.4, 0.35), (bx + 1, by + 2.6, 2.0), 'steel')
            if rng.random() < 0.5:                                   # a party that never got cleared
                for _ in range(rng.randrange(2, 6)):
                    px, py = x + rng.uniform(1.5, 20), y + rng.uniform(1.5, 5.5)
                    t.cyl((px, py, 3.9), (px, py, 4.0), 1.1, 'paper', 8, True)
                t.tube([(x + 11, y + 3.5, 3.9), (x + 11, y + 3.5, 6.2)], 0.9, rng.choice(('pink', 'cyan')), 6)
    t.finish()


def build_arcade():
    a = Builder('ArcadeCorner', foh_col)
    for n in range(9):                                               # cabinets along the north wall
        x = 222 + n * 8
        mat = ('navy', 'red', 'purple', 'black')[n % 4]
        a.box((x, 388, 0.35), (x + 6, 398, 9), mat)
        a.box((x, 384, 0.35), (x + 6, 388, 5.2), mat)
        a.box((x + 0.6, 387.4, 5.6), (x + 5.4, 388, 8.6), 'black')
        a.box((x + 0.3, 388, 9), (x + 5.7, 396, 12.4), 'yellow')
    a.box((190, 384, 0.35), (214, 390, 4.6), 'purple')               # prize counter
    a.box((189, 383, 4.6), (215, 391, 5.0), 'yellow')
    a.box((190, 396, 0.35), (214, 399, 13), 'wood')
    for row in range(1, 5):
        for n in range(5):
            a.cbox((193 + n * 4.5, 395, 2.2 + row * 2.6), (2.4, 1.4, 1.8), rng.choice(VINYL))
    a.finish()


# ==========================================================================================
# 4. Hide and seek: the counting post and everywhere a player can hide
# ==========================================================================================
PLAYHOUSES = ((150, 110, 'red'), (70, 128, 'blue'), (236, 330, 'yellow'), (520, 20, 'green'),
              (576, 190, 'pink'), (470, 374, 'cyan'), (30, 290, 'purple'))


def build_hide_and_seek():
    hide_col = collection('L6_HideSpots')
    h = Builder('HideAndSeek_Props', foh_col)
    hx, hy = HOME
    h.cyl((hx, hy, 0.35), (hx, hy, 0.8), 11, 'red', 16, True)                  # counting mat
    h.cyl((hx, hy, 0.8), (hx, hy, 0.95), 7.5, 'yellow', 16, True)
    h.cyl((hx, hy, 0.95), (hx, hy, 16), 1.3, 'yellow', 10, True)               # the post it leans on
    for z in (4.0, 8.0, 12.0):
        h.cyl((hx, hy, z), (hx, hy, z + 0.25), 1.42, 'black', 10)
    h.cbox((hx, hy - 1.6, 11), (7, 0.4, 4.5), 'white')                         # "1 2 3 ... 20" board
    h.cbox((hx, hy - 1.85, 11), (6.2, 0.1, 3.7), 'paper')
    spots = [('home', hx, hy - 4, 1)]
    for px, py, mat in PLAYHOUSES:                                            # little houses with one doorway
        h.box((px, py, 0.35), (px + 12, py + 0.6, 9), mat)
        h.box((px, py + 11.4, 0.35), (px + 4, py + 12, 9), mat)
        h.box((px + 8, py + 11.4, 0.35), (px + 12, py + 12, 9), mat)
        h.box((px + 4, py + 11.4, 6.5), (px + 8, py + 12, 9), mat)
        h.box((px, py, 0.35), (px + 0.6, py + 12, 9), mat)
        h.box((px + 11.4, py, 0.35), (px + 12, py + 12, 9), mat)
        h.box((px + 11.4, py + 3.5, 3.5), (px + 12.1, py + 8.5, 6.5), 'black')  # window
        h.box((px - 1, py - 1, 9), (px + 13, py + 13, 9.8), 'white')
        h.box((px + 1.5, py + 1.5, 9.8), (px + 10.5, py + 10.5, 12.4), 'red' if mat != 'red' else 'blue')
        spots.append(('playhouse', px + 6, py + 5, 1))
    for n, (cx, cy) in enumerate(((120, 60), (268, 262), (40, 100), (560, 300), (500, 368), (180, 140))):
        mat = VINYL[n % len(VINYL)]                                           # hollow soft blocks to crawl into
        h.box((cx, cy, 0.35), (cx + 10, cy + 1, 6), mat)
        h.box((cx, cy + 7, 0.35), (cx + 10, cy + 8, 6), mat)
        h.box((cx, cy, 6), (cx + 10, cy + 8, 7), mat)
        h.box((cx + 9, cy + 1, 0.35), (cx + 10, cy + 7, 6), mat)
        spots.append(('softblock', cx + 5, cy + 4, 1))
    h.finish()
    for x, y in TABLES:
        spots.append(('table', x, y, 0.6))
    px0, py0 = SX + BALLPIT[0] * C, SY + BALLPIT[1] * C
    for dx, dy in ((14, 14), (40, 30), (60, 48), (22, 50), (56, 12)):
        spots.append(('ballpit', px0 + dx, py0 + dy, 0.8))
    for i in range(PUNCH[0], PUNCH[2] + 1, 2):
        for j in range(PUNCH[1], PUNCH[3] + 1, 2):
            spots.append(('punchbag', SX + i * C + 6, SY + j * C + 6, 1))
    ax0, ay0 = SX + ATRIUM[0] * C, SY + ATRIUM[1] * C
    spots += [('tube', ax0 + 6, ay0 + 24, 11.2), ('tube', ax0 + 6, ay0 + 54, 11.2),
              ('tube', ax0 + 22, ay0 + 66, 21.2), ('tube', ax0 + 52, ay0 + 66, 21.2),
              ('under_slide', ax0 + 50, ay0 + 12, 1), ('under_slide', ax0 + 34, ay0 + 12, 1),
              ('counter', 8, SNACK[1] + 26, 1), ('counter', 8, SNACK[1] + 74, 1),
              ('stall', 108.5, PARTY[1] + 30, 1), ('stall', 118.5, PARTY[1] + 30, 1), ('stall', 128.5, PARTY[1] + 30, 1),
              ('counter', 202, 393, 1), ('counter', 68, 40, 1), ('cubby_bench', 208, 9, 1),
              ('toddler_pool', 243, 119, 1.2)]
    for k in range(NZ):                                                       # dead-end cells in the frame
        for i in range(NX):
            for j in range(NY):
                if not walkable(k, i, j) or any(in_cells(i, j, r) for r in (BALLPIT, ATRIUM, PUNCH)):
                    continue
                exits = sum(1 for a, b in ((i + 1, j), (i - 1, j), (i, j + 1), (i, j - 1))
                            if walkable(k, a, b) and (k, min((i, j), (a, b)), max((i, j), (a, b))) in OPENED)
                if exits == 1 and (k, i, j) not in STAIRS:
                    spots.append(('frame_nook', SX + i * C + 6, SY + j * C + 6, k * H + 1))
    counts = {}
    for kind, x, y, z in spots:
        counts[kind] = counts.get(kind, 0) + 1
        empty = bpy.data.objects.new(f'L6_Hide_{kind}_{counts[kind]:02d}', None)
        empty.location = (x, y, z)
        empty.empty_display_type = 'SPHERE'
        empty.empty_display_size = 2
        empty['hide_kind'] = kind
        hide_col.objects.link(empty)
    return counts


# ==========================================================================================
# 5. Assemble
# ==========================================================================================
build_floor()
build_walls()
lit_fixtures = build_ceiling()
build_columns()
build_frame()
build_decks()
build_walls_of_frame()
build_stairs()
build_play_features()
build_slides()
build_ball_pit()
build_frame_lights()
build_snack_bar()
build_party_block()
build_reception()
build_toddler_corner()
build_party_tables()
build_arcade()
hide_counts = build_hide_and_seek()

# gameplay anchors for the Studio import
anchors_col = collection('L6_Anchors')
for name, loc in (('Spawn', (130, 60, 3)), ('Exit', (548, HALL_Y - 6, 3)),
                  ('EntitySpawn', (SX + 15 * C, SY + 22 * C, 3)), ('HomeBase', (HOME[0], HOME[1], 3))):
    empty = bpy.data.objects.new('L6_Anchor_' + name, None)
    empty.location = loc
    empty.empty_display_size = 4
    anchors_col.objects.link(empty)

# ---- world, cameras, render ----------------------------------------------------------------
world = bpy.data.worlds.new('L6_World')
world.use_nodes = True
world.node_tree.nodes['Background'].inputs['Color'].default_value = (0.030, 0.034, 0.046, 1)
world.node_tree.nodes['Background'].inputs['Strength'].default_value = 1.0
scene.world = world

cam_col = collection('L6_Cameras')
CAMERAS = {
    'overview': ((40, 30, 40), (430, 260, 2), 20),
    'hall_floor': ((286, 140, 6), (284, 390, 18), 18),
    'frame_front': ((236, 150, 7), (330, 190, 14), 22),
    'ball_pit': ((318, 62, 8), (372, 98, 3), 20),
    'inside_frame': ((SX + 8.5 * C, SY + 17.5 * C, 5.5), (SX + 2 * C, SY + 20 * C, 5), 18),
    'atrium': ((SX + 10.3 * C, SY + 9.3 * C, 6), (SX + 15.5 * C, SY + 13 * C, 17), 18),
    'snack_bar': ((92, 268, 6), (10, 186, 8), 22),
    'party_block': ((176, 262, 6), (118, 336, 9), 22),
    'toddler': ((300, 150, 9), (226, 70, 3), 22),
    'home_base': ((206, 176, 7), (262, 214, 7), 20),
}
for label, (loc, target, lens) in CAMERAS.items():
    data = bpy.data.cameras.new('L6_Cam_' + label)
    data.lens, data.clip_start, data.clip_end = lens, 0.5, 2000
    obj = bpy.data.objects.new(data.name, data)
    obj.location = loc
    obj.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    cam_col.objects.link(obj)

for engine in ('BLENDER_EEVEE_NEXT', 'BLENDER_EEVEE'):
    try:
        scene.render.engine = engine
        break
    except TypeError:
        continue
scene.render.resolution_x, scene.render.resolution_y = 1600, 900
scene.view_settings.exposure = 0.6
try:
    scene.eevee.shadow_pool_size = '1024'
except (AttributeError, TypeError):
    pass
try:
    scene.view_settings.view_transform = 'AgX'
    scene.view_settings.look = 'AgX - Medium High Contrast'
except TypeError:
    pass

stats = {
    'seed': SEED, 'hall_studs': [HALL_X, HALL_Y, HALL_Z], 'frame_cells': [NX, NY, NZ],
    'objects': sum(1 for o in bpy.data.objects if o.type == 'MESH'),
    'triangles': sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in bpy.data.objects if o.type == 'MESH'),
    'per_object': {o.name: sum(len(p.vertices) - 2 for p in o.data.polygons)
                   for o in bpy.data.objects if o.type == 'MESH'},
    'lit_fixtures': len(lit_fixtures), 'stair_flights': len(STAIRS), 'hide_spots': hide_counts,
    'authoring': 'Blender Z up, 1 BU = 1 Roblox stud',
}
(OUT / 'blend').mkdir(parents=True, exist_ok=True)
(OUT / 'build-stats.json').write_text(json.dumps(stats, indent=1))
(OUT / 'export').mkdir(exist_ok=True)
(OUT / 'export' / 'prims.json').write_text(json.dumps({
    'prims': [[n, k, [round(float(v), 3) for v in d], m] for n, k, d, m in PRIMS],
    'empties': [[o.name, [round(c, 3) for c in o.location]] for o in bpy.data.objects if o.type == 'EMPTY'],
    'lights': [[o.name, [round(c, 3) for c in o.location]] for o in bpy.data.objects if o.type == 'LIGHT'],
    'palette': {k: list(v) for k, v in PALETTE.items()},
}))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / 'blend' / 'Level6_IndoorPlayground.blend'))
print('L6 BUILD', json.dumps({k: stats[k] for k in ('objects', 'triangles', 'lit_fixtures', 'stair_flights')}))

argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
if '--render' in argv:
    only = [a.split('=', 1)[1] for a in argv if a.startswith('--only=')]
    (OUT / 'renders').mkdir(exist_ok=True)
    for label in CAMERAS:
        if only and label not in only[0].split(','):
            continue
        scene.camera = bpy.data.objects['L6_Cam_' + label]
        scene.render.filepath = str(OUT / 'renders' / f'{label}.jpg')
        scene.render.image_settings.file_format = 'JPEG'
        scene.render.image_settings.quality = 88
        bpy.ops.render.render(write_still=True)
        print('L6 RENDER', label)
