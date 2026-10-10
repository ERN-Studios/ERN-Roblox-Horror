"""Level 6 "the Arena" - deterministic Blender build (concept v5, artifacts/level6-concept-20261006b).

Run headless:  Blender -b --python tools/level6_playground/build_arena.py -- [--render]

One soft-play frame fills a round hall. The post stands in a round court in the middle; round it the frame
rises as a wall of galleries: four floors, a ledge, four more, a ledge, four more. Players arrive in a tunnel
through the hall wall, pass the PLAY ZONE gate and walk one straight lane to the court. Under the post are a
shaft, a tube slide and the exit room.

Everything is laid out in polar cells round the centre:
    band b   = the ring between R[b] and R[b + 1]
    sector s = 15 degrees wide in the three inner bands, 7.5 in the outer ones (0 = east, 90 = north)
    floor k  = 0 .. 11, ten studs apart

The script writes, next to the .blend:
    export/prims.json   every primitive, for import_arena.py (native Parts in Studio)
    export/nav.json     the Counter's navigation graph: one node per cell, one edge per opening or stair
    export/Level6ArenaSlides.glb   the moulded slides and tubes (Studio: File > Import)
Coordinates are Roblox studs with Blender Z up (1 BU = 1 stud); the hall's centre is at (300, 200).
"""
import bpy, bmesh, math, random, sys, json
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "artifacts" / "level6-arena-20261006"
SEED = 6061
rng = random.Random(SEED)

# ---- dimensions (studs) ------------------------------------------------------------------
CX, CY = 300.0, 200.0
H = 10.0                                    # floor to floor
FLOORS = 12
R = [44.0, 60.0, 76.0, 92.0, 108.0, 122.0, 138.0, 154.0]
NSEC = [24, 24, 24, 48, 48, 48, 48]         # sectors in each band
TOPK = [3, 7, 11, 11, 11, 11, 11]           # the highest roofed floor of each band
TERRACE = {0: 4, 1: 8}                      # band -> the floor whose deck is an open ledge on top of it
RING = 4                                    # the band that is a ring corridor on every floor
NB = len(NSEC)
WALL_R, WALL_T, ROOF_Z = 156.0, 3.0, 150.0
LANE_HALF, LANE_S24 = 7.0, 18               # the way in: a straight lane where sector 18 (270 degrees) would be
TUNNEL_W, TUNNEL_L, TUNNEL_H = 14.0, 30.0, 13.0
POST_R, BEAM_R = 0.7, 0.45
GATES = (0, 3, 6, 9, 12, 15, 21)            # ground-floor openings from the court into the frame (sector 18 is the lane)
SHAFT_R, SHAFT_DEPTH = 5.7, 12.0
LID_CORE, LID_REACH = 4.0, 5.85              # the lid over the shaft is a cross: a square this far each way, arms out to this

# ---- the way out: under the post a funnel, a long spiral slide, and the small padded room it ends in ------------
# (worked out relative to the court's centre: x east, y north, z up)
EXIT_R = 3.2                                 # the slide's inner radius
RAMP_M, RAMP_Z0, RAMP_X1 = 0.45, -7.0, 6.5   # the shaft's floor: how steeply it tips east, its height at the west wall, where the tube takes over
HELIX_C, HELIX_R, HELIX_PITCH = (10.0, 14.0), 14.0, 10.0     # the spiral: its axis, its radius, studs down per turn
EXIT_DIR = (0.6, -0.8)                       # the way the slide runs when it comes into the room
# the height of the slide's centre line after the spiral, by studs run: level, then down through the room's ceiling
# at about 55 degrees, flattening onto the floor
EXIT_PROFILE = ((3.0, -0.4), (6.0, -1.7), (8.5, -4.1), (10.5, -6.8), (12.5, -9.6), (14.5, -12.2), (16.5, -14.1),
                (19.0, -15.3), (22.0, -15.7))
ROOM_W, ROOM_D, ROOM_H = 30.0, 24.0, 13.0    # the room: along the door wall, deep, high
ROOM_IN = (6.0, 5.0)                         # where the slide comes through its ceiling: from the west wall, from the door wall


def exit_layout():
    lift = 0.75 * EXIT_R * math.sqrt(1 + RAMP_M ** 2)               # the centre line above the trough's floor, on the ramp
    ramp_end = RAMP_Z0 - RAMP_M * (RAMP_X1 + SHAFT_R)
    top = [(RAMP_X1, 0.0, ramp_end + lift), (8.6, 0.0, ramp_end + lift - 0.85)]
    z0 = ramp_end + lift - 1.35                                     # at the spiral's south point, where it begins
    end = math.degrees(math.atan2(-EXIT_DIR[0], EXIT_DIR[1])) % 360    # where the spiral runs the way the room wants
    sweep = end + 90.0 + 720.0
    count = math.ceil(sweep / 15.0)
    helix = []
    for i in range(count + 1):
        a = -90.0 + sweep * i / count
        helix.append((HELIX_C[0] + HELIX_R * math.cos(math.radians(a)), HELIX_C[1] + HELIX_R * math.sin(math.radians(a)),
                      z0 - HELIX_PITCH * (a + 90.0) / 360.0))
    ex, ey, ez = helix[-1]
    tail = [(ex + EXIT_DIR[0] * s, ey + EXIT_DIR[1] * s, ez + dz) for s, dz in EXIT_PROFILE]
    floor = tail[-1][2] - 0.75 * EXIT_R - 0.05
    ceiling = floor + ROOM_H
    assert ez - EXIT_R - 0.35 > ceiling + 1.4, 'the spiral runs into the room'
    cross = None
    points = [helix[-1]] + tail
    for a_, b_ in zip(points, points[1:]):
        if a_[2] >= ceiling > b_[2]:
            t = (a_[2] - ceiling) / (a_[2] - b_[2])
            cross = (a_[0] + (b_[0] - a_[0]) * t, a_[1] + (b_[1] - a_[1]) * t)
    x0, y1 = cross[0] - ROOM_IN[0], cross[1] + ROOM_IN[1]
    return {'top': top, 'helix': helix[1:], 'tail': tail, 'cross': cross, 'turns': sweep / 360.0,
            'room': (x0, y1 - ROOM_D, x0 + ROOM_W, y1, floor, ceiling)}


EXIT = exit_layout()
EXIT_ROOM = tuple(v + o for v, o in zip(EXIT['room'], (CX, CY, CX, CY, 0.0, 0.0)))     # x0, y0, x1, y1, floor, ceiling

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
    # padded vinyl, the level's deep dusty primaries (linear RGB), as in build_playground.py
    'yellow': (0.66, 0.38, 0.01), 'red': (0.40, 0.02, 0.015), 'blue': (0.015, 0.04, 0.30),
    'green': (0.025, 0.21, 0.04), 'purple': (0.13, 0.03, 0.23), 'orange': (0.64, 0.15, 0.01), 'navy': (0.008, 0.012, 0.075),
    'mat_green': (0.055, 0.17, 0.05), 'mat_blue': (0.03, 0.055, 0.23), 'concrete': (0.20, 0.19, 0.17),
    'tile_green': (0.10, 0.30, 0.10), 'tile_blue': (0.06, 0.11, 0.40),     # the court and the lane: lighter, they carry the light
    'wall_white': (0.42, 0.41, 0.37), 'deck': (0.16, 0.16, 0.16), 'steel': (0.10, 0.10, 0.105),
    'duct': (0.55, 0.56, 0.57), 'white': (0.82, 0.80, 0.75), 'black': (0.02, 0.02, 0.02),
    'lamp_off': (0.30, 0.30, 0.28), 'stainless': (0.55, 0.56, 0.58),
    # the room under the court: the same vinyl after years in the damp, what has dried on the floor, and an unseen guide
    'yellow_worn': (0.40, 0.25, 0.015), 'yellow_dark': (0.25, 0.16, 0.014), 'navy_worn': (0.02, 0.03, 0.085),
    'blue_worn': (0.02, 0.045, 0.17), 'stain': (0.012, 0.010, 0.008), 'guide': (0.5, 0.5, 0.5),
}
ROUGH = {'stainless': 0.3, 'duct': 0.4, 'steel': 0.55, 'deck': 0.6, 'concrete': 0.9}
VINYL = ['yellow', 'red', 'blue', 'green', 'purple', 'orange']
FRAME_VINYL = ['yellow', 'red', 'blue', 'green', 'blue', 'red']
MATS = {}


def make_material(name, rgb, rough=0.5, emission=0.0, metallic=0.0):
    mat = bpy.data.materials.new('L6_' + name)
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
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
make_material('lamp_green', (0.2, 1.0, 0.4), emission=8.0)
make_material('dial', (0.80, 0.55, 0.03), 0.5)


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
            i = (y * size + x) * 4
            px[i:i + 4] = (*rgb, 1.0) if (fx < line or fy < line) else (*rgb, 0.0)
    img.pixels = px
    tex_dir = OUT / 'blend' / 'textures'
    tex_dir.mkdir(parents=True, exist_ok=True)
    img.filepath_raw = str(tex_dir / (name + '.png'))
    img.file_format = 'PNG'
    img.save()
    mat = bpy.data.materials.new('L6_' + name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
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


make_net_material('net_black', (0.03, 0.03, 0.03))
make_net_material('net_yellow', (0.80, 0.62, 0.08), cells=12, line=0.2)

PRIMS = []       # [group, kind, numbers, material]
SLIDES = []      # (mesh name, kind, path, radius, colour, arc): one moulded mesh each
SLIDE_PLACES = []   # (mesh name, centre or None, yaw degrees): where a mesh stands (None = where it was modelled)
SLIDE_RGB = {'red': (214, 30, 22), 'yellow': (246, 188, 16), 'green': (36, 158, 58), 'blue': (26, 88, 214),
             'orange': (238, 106, 18)}
PROPS, SIGNS, LIGHTS, EMPTIES, HIDE = [], [], [], [], []


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

    def _hexa(self, v, mat):
        was, self.rec = self.rec, False
        for idx in ((0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)):
            self.face([v[i] for i in idx], mat)
        self.rec = was

    def box(self, lo, hi, mat):
        x0, y0, z0 = lo
        x1, y1, z1 = hi
        self.prim('b', [x0, y0, z0, x1, y1, z1], mat)
        self._hexa([(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
                    (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)], mat)

    def sector(self, ra, rb, a0, a1, zc, thick, mat, split=False):
        """A mat between radii ra and rb and the sector lines a0 and a1 (degrees): its corners lie ON the two circles,
        so it meets its neighbours edge to edge and never lies over them. `split`: the outer edge has a corner in the
        middle as well, where the next band out has two sectors to this one. Studio cuts it from a block ('p')."""
        am = (a0 + a1) / 2
        self.prim('p', [ra, rb, a1 - a0, 1 if split else 0, am, zc, thick], mat)
        ring = [P(ra, a0), P(ra, a1), P(rb, a1)] + ([P(rb, am)] if split else []) + [P(rb, a0)]
        lo = [(x, y, zc - thick / 2) for x, y, _ in ring]
        hi = [(x, y, zc + thick / 2) for x, y, _ in ring]
        was, self.rec = self.rec, False
        self.face(list(reversed(lo)), mat)
        self.face(hi, mat)
        for i in range(len(ring)):
            j = (i + 1) % len(ring)
            self.face([lo[i], lo[j], hi[j], hi[i]], mat)
        self.rec = was

    def obox(self, c, size, yaw, mat):
        """A box centred on c; size = (along its own x, along its own y, up); its x is turned yaw degrees from +X."""
        self.prim('o', [*c, *size, yaw], mat)
        ca, sa = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
        hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2

        def pt(dx, dy, dz):
            return (c[0] + dx * ca - dy * sa, c[1] + dx * sa + dy * ca, c[2] + dz)
        self._hexa([pt(-hx, -hy, -hz), pt(hx, -hy, -hz), pt(hx, hy, -hz), pt(-hx, hy, -hz),
                    pt(-hx, -hy, hz), pt(hx, -hy, hz), pt(hx, hy, hz), pt(-hx, hy, hz)], mat)

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

    def tube(self, path, r, colour, n=10, record=True, speeds=None, open_last=0, open_first=0):
        """Sweep a tube along a polyline. Each segment is also a 't' primitive: the invisible trough you ride."""
        path = [Vector(p) for p in path]
        rings = []
        for i, p in enumerate(path):
            t = (path[min(i + 1, len(path) - 1)] - path[max(i - 1, 0)]).normalized()
            s = t.cross(Vector((0, 0, 1)))
            s = s.normalized() if s.length > 1e-4 else Vector((1, 0, 0))
            u = s.cross(t).normalized()
            rings.append([p + (math.cos(2 * math.pi * k / n) * s + math.sin(2 * math.pi * k / n) * u) * r for k in range(n)])
        was, self.rec = self.rec, False
        for i in range(len(path) - 1):
            if was and record:
                # after the radius: the pace along this stretch (0 = the slope decides) and 1 where the trough has no
                # roof (a slide's mouth, so a standing body can step in, and the open lip at the end of the way out)
                roofless = 1 if i < open_first or i >= len(path) - 1 - open_last else 0
                more = [speeds[i] if speeds else 0, roofless] if (speeds or roofless) else []
                PRIMS.append([self.name, 't', [*path[i], *path[i + 1], r, *more], colour])
            for k in range(n):
                k2 = (k + 1) % n
                self.face([rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]], colour, True)
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


shell_col = collection('L6_Shell')
lights_col = collection('L6_Lights')
frame_col = collection('L6_Frame')
finale_col = collection('L6_Finale')
slide_col = collection('L6_Slides')


def prop(name, x, y, z, facing, size, collide=False):
    """A hero mesh from ReplicatedStorage.Level6PropKit, its front turned to `facing` degrees (0 = east)."""
    PROPS.append([name, x, y, z, 90.0 - facing, size, 1 if collide else 0])


def light(name, pos, kind, rng_, brightness, angle=120, rgb=(255, 236, 205), energy=4000):
    LIGHTS.append([name, [round(c, 3) for c in pos], kind, rng_, brightness, angle, list(rgb)])
    data = bpy.data.lights.new(name, 'SPOT' if kind == 'spot' else 'POINT')
    data.energy, data.color = energy, tuple(c / 255 for c in rgb)
    if kind == 'spot':
        data.spot_size = math.radians(min(angle, 170))
    obj = bpy.data.objects.new(name, data)
    obj.location = pos
    lights_col.objects.link(obj)


def anchor(name, loc):
    EMPTIES.append([name, [round(c, 3) for c in loc]])
    empty = bpy.data.objects.new(name, None)
    empty.location = loc
    scene.collection.objects.link(empty)


# ==========================================================================================
# polar helpers and the cell grid
# ==========================================================================================
def P(r, a, z=0.0):
    return (CX + r * math.cos(math.radians(a)), CY + r * math.sin(math.radians(a)), z)


def ftop(k):
    """The walking surface of floor k."""
    return 0.95 if k == 0 else k * H + 0.35


def span(b, s):
    if NSEC[b] == 24:
        return 15.0 * s - 7.5, 15.0 * s + 7.5
    return 7.5 * s - 7.5, 7.5 * s


def mid(b, s):
    a0, a1 = span(b, s)
    return (a0 + a1) / 2


def in_lane(b, s):
    return s == LANE_S24 if NSEC[b] == 24 else s in (2 * LANE_S24, 2 * LANE_S24 + 1)


def kind(k, b, s):
    if b < 0 or b >= NB or k < 0:
        return None
    s %= NSEC[b]
    if in_lane(b, s):
        return None
    if k <= TOPK[b]:
        return 'cell'
    if TERRACE.get(b) == k:
        return 'terrace'
    return None


def front(k, b):
    """The band whose cells are the gallery looking into the court on this floor."""
    return (b == 0 and k <= 3) or (b == 1 and 4 <= k <= 7) or (b == 2 and k >= 8)


def chord(radius, a0, a1, inset=POST_R + 0.1):
    p0, p1 = Vector(P(radius, a0)), Vector(P(radius, a1))
    d = (p1 - p0).normalized()
    return p0 + d * inset, p1 - d * inset


# ---- stairwells: two neighbouring cells with switchback flights, an aisle running between the two flight lanes
WELLS = []
for s in (1, 7, 13, 19):
    WELLS.append({'b': 1, 'c0': s, 'c1': s + 1, 'k0': 0, 'k1': 8})
for s in (4, 10, 16, 22):
    WELLS.append({'b': 2, 'c0': s, 'c1': s + 1, 'k0': 0, 'k1': 11})
for s in (6, 18, 30, 42):
    WELLS.append({'b': 5, 'c0': s, 'c1': s + 1, 'k0': 0, 'k1': 11})
WELL_OF = {}
for w in WELLS:
    WELL_OF[(w['b'], w['c0'])] = (w, 'c0')
    WELL_OF[(w['b'], w['c1'])] = (w, 'c1')


def flight(w, k):
    """The flight that leaves floor k in this well: (cell it stands in, lane, direction) or None."""
    if not (w['k0'] <= k < w['k1']):
        return None
    if (k - w['k0']) % 2 == 0:
        return w['c0'], 'outer', 1          # in the first cell's outer lane, rising counter-clockwise
    return w['c1'], 'inner', -1             # in the second cell's inner lane, rising clockwise


def hole(k, b, s):
    """The lane of this cell's deck that is open because a flight comes up through it, or None."""
    hit = WELL_OF.get((b, s))
    if not hit:
        return None
    f = flight(hit[0], k - 1)
    if f and f[0] == s:
        return f[1]
    return None


LANES = {'inner': (0.0, 5.5), 'aisle': (5.5, 10.5), 'outer': (10.5, 16.0)}     # radial offsets from the band's inner radius


# ==========================================================================================
# which neighbouring cells are open to each other
# ==========================================================================================
def neighbours(k, b, s):
    """(other cell, 'tan' or 'rad') for the two neighbours counted from this cell: next sector, next band out."""
    out = []
    n = NSEC[b]
    if kind(k, b, s + 1):
        out.append(((k, b, (s + 1) % n), 'tan'))
    if b + 1 < NB:
        for s2 in ([s] if NSEC[b + 1] == n else [2 * s, 2 * s + 1]):
            if kind(k, b + 1, s2):
                out.append(((k, b + 1, s2), 'rad'))
    return out


CELLS = [(k, b, s) for k in range(FLOORS) for b in range(NB) for s in range(NSEC[b]) if kind(k, b, s)]
OPEN, FACE = set(), set()          # frozenset of two cells: an opening / a gallery face with a rail (never opened)
candidates = []
for cell in CELLS:
    k, b, s = cell
    for other, way in neighbours(k, b, s):
        k2, b2, s2 = other
        pair = frozenset((cell, other))
        both = (kind(k, b, s), kind(k2, b2, s2))
        well_a, well_b = WELL_OF.get((b, s)), WELL_OF.get((b2, s2))
        if way == 'tan':
            if well_a and well_b and well_a[0] is well_b[0]:
                OPEN.add(pair)                                    # the two cells of a stairwell
            elif 'terrace' in both or front(k, b) or b == RING:
                OPEN.add(pair)                                    # galleries, ledges and the ring corridor run right round
            else:
                candidates.append(pair)
        else:
            # a flight lane is never a doorway: the first cell's outer side and the second cell's inner side stay shut
            blocked = (well_a and well_a[1] == 'c0') or (well_b and well_b[1] == 'c1')
            if 'terrace' in both:
                if s % 3 == 1 and not blocked:
                    OPEN.add(pair)                                # a door from the gallery onto its ledge
                else:
                    FACE.add(pair)
            elif blocked:
                pass
            else:
                candidates.append(pair)

# every floor is one connected maze: openings are added until all its cells hang together, then a few more for loops
parent = {c: c for c in CELLS}


def find(c):
    while parent[c] != c:
        parent[c] = parent[parent[c]]
        c = parent[c]
    return c


for pair in OPEN:
    a, b_ = tuple(pair)
    parent[find(a)] = find(b_)
rng.shuffle(candidates)
candidates.sort(key=lambda pr: min(c[0] for c in pr))       # floor by floor, in the shuffled order
for pair in candidates:
    a, b_ = tuple(pair)
    if find(a) != find(b_):
        parent[find(a)] = find(b_)
        OPEN.add(pair)
    elif rng.random() < 0.2:
        OPEN.add(pair)
for k in range(FLOORS):
    roots = {find(c) for c in CELLS if c[0] == k}
    assert len(roots) == 1, f'floor {k} is in {len(roots)} pieces'


def is_open(a, b_):
    return frozenset((a, b_)) in OPEN


# ==========================================================================================
# the navigation graph: one node per cell, one edge per opening, stair, bridge
# ==========================================================================================
NODES, NODE_ID, EDGES = [], {}, []


def node(key, pos):
    if key not in NODE_ID:
        NODE_ID[key] = len(NODES)
        NODES.append([round(c, 2) for c in pos])
    return NODE_ID[key]


def edge(a, b_, via=()):
    EDGES.append([a, b_, [[round(c, 2) for c in p] for p in via]])


def walk_radius(k, b, s):
    """Where the way through a cell runs: down its middle, or along the back of a ledge."""
    return R[b] + (11.0 if kind(k, b, s) == 'terrace' else 8.0)


def cell_node(k, b, s):
    return node(('c', k, b, s % NSEC[b]), P(walk_radius(k, b, s), mid(b, s), ftop(k)))


for cell in CELLS:
    k, b, s = cell
    cell_node(k, b, s)
for pair in OPEN:
    a, b_ = sorted(pair)
    (k, b, s), (k2, b2, s2) = a, b_
    if b == b2:                                   # through the side of the sector
        lo, hi = (s, s2) if (s + 1) % NSEC[b] == s2 else (s2, s)
        via = P(walk_radius(k, b, lo), span(b, lo)[1], ftop(k))
    else:                                         # through the ring between two bands
        via = P(R[b2], mid(b2, s2) if NSEC[b2] >= NSEC[b] else mid(b, s), ftop(k))
    edge(cell_node(*a), cell_node(*b_), [via])


def flight_frame(w, k):
    """Where a flight stands: (cell, base point on the lane's centre line, tangent, half width of the cell there,
    direction, z at the bottom, z at the top)."""
    s, lane, direction = flight(w, k)
    b = w['b']
    r0 = R[b]
    rl = r0 + sum(LANES[lane]) / 2
    a = mid(b, s)
    delta = span(b, s)[1] - span(b, s)[0]
    half = rl * math.tan(math.radians(delta / 2))
    base = Vector(P(rl, a))
    tangent = Vector((-math.sin(math.radians(a)), math.cos(math.radians(a)), 0.0)) * direction
    return s, base, tangent, half, direction, ftop(k), ftop(k + 1)


RUN = 12.0          # five soft steps of 2.4 studs
for w in WELLS:
    for k in range(w['k0'], w['k1']):
        s, base, tangent, half, direction, z0, z1 = flight_frame(w, k)
        other = w['c1'] if s == w['c0'] else w['c0']
        bottom = base + tangent * (half - RUN - 2.0)
        top = base + tangent * half
        land = base + tangent * (half + 3.0)
        radial = Vector((math.cos(math.radians(mid(w['b'], s))), math.sin(math.radians(mid(w['b'], s))), 0.0))
        aisle = (R[w['b']] + 8.0) - (base - Vector((CX, CY, 0.0))).dot(radial)      # from the flight's lane to the aisle
        beside_foot, beside_head = bottom + radial * aisle, land + radial * aisle
        edge(cell_node(k, w['b'], s), cell_node(k + 1, w['b'], other),
             [(beside_foot.x, beside_foot.y, z0), (bottom.x, bottom.y, z0), (top.x, top.y, z1), (land.x, land.y, z1),
              (beside_head.x, beside_head.y, z1)])

# the court: a ring of nodes inside the gallery face, a smaller ring round the post, and where the Counter stands to count
COURT_Z = 0.95
for s in range(24):
    node(('court', s), P(31.0, 15.0 * s, COURT_Z))
for s in range(24):
    edge(NODE_ID[('court', s)], NODE_ID[('court', (s + 1) % 24)])
    if s in GATES:
        edge(NODE_ID[('court', s)], cell_node(0, 0, s), [P(R[0], 15.0 * s, COURT_Z)])
for i in range(8):
    node(('inner', i), P(15.0, 22.5 + 45.0 * i, COURT_Z))
for i in range(8):
    edge(NODE_ID[('inner', i)], NODE_ID[('inner', (i + 1) % 8)])
    for s in range(24):
        if abs((15.0 * s - (22.5 + 45.0 * i) + 180) % 360 - 180) <= 22.5:
            edge(NODE_ID[('inner', i)], NODE_ID[('court', s)])
HOME_STAND = P(4.0, 270.0, COURT_Z)
node(('home',), HOME_STAND)
for i in (4, 5, 6, 7):                      # only the south half: a line to the others would run through the post
    edge(NODE_ID[('home',)], NODE_ID[('inner', i)])
LANE_Y = [CY - 50.0 - 12.5 * i for i in range(8)] + [CY - 143.0]   # down the lane to just inside the gate
for i, y in enumerate(LANE_Y):
    node(('lane', i), (CX, y, COURT_Z))
    edge(NODE_ID[('lane', i)], NODE_ID[('lane', i - 1)] if i else NODE_ID[('court', LANE_S24)])
# the two net bridges over the court, from ledge to ledge at the second terrace, crossing eighty studs above the post
BRIDGE_K, BRIDGE_B = 8, 1                   # the floor and the band of the ledge they join
BRIDGE_Z = ftop(BRIDGE_K)
# sectors of that ledge. Not 2, 8, 14 or 20: the stairwells of this band come up through the ledge there, and a
# bridge that lands on one drops whoever steps off it into the stairs (found walking it, 2026-10-06)
BRIDGES = ((4, 16), (10, 22))
assert not any((BRIDGE_B, s) in WELL_OF for pair in BRIDGES for s in pair), 'a bridge lands on a stairwell'
node(('bridge', 'mid'), (CX, CY, BRIDGE_Z))
# OVERPASS_20261007 (owner: "the entity gets stuck in the middle of the overpass"). Each arm used to be ONE link from
# the ledge to the middle, so the only place on the whole crossing the Counter could be sent to was the middle: a
# player standing anywhere else on a bridge had it walk to the hub and stop there, sixteen to forty studs short,
# for as long as they stayed. Now there is a point every twelve studs along every arm.
BRIDGE_STOPS = (12.0, 24.0, 36.0, 48.0)
for pair in BRIDGES:
    for s in pair:
        chain = [NODE_ID[('bridge', 'mid')]] + [node(('bridge', s, r), P(r, 15.0 * s, BRIDGE_Z)) for r in BRIDGE_STOPS]
        for a, b_ in zip(chain, chain[1:]):
            edge(a, b_)
        edge(chain[-1], cell_node(BRIDGE_K, BRIDGE_B, s), [P(R[BRIDGE_B], 15.0 * s, BRIDGE_Z)])

# every node must be reachable from where the Counter stands
adjacent = {i: [] for i in range(len(NODES))}
for a, b_, _ in EDGES:
    adjacent[a].append(b_)
    adjacent[b_].append(a)
seen, stack = {NODE_ID[('home',)]}, [NODE_ID[('home',)]]
while stack:
    for nxt in adjacent[stack.pop()]:
        if nxt not in seen:
            seen.add(nxt)
            stack.append(nxt)
assert len(seen) == len(NODES), f'{len(NODES) - len(seen)} nodes cannot be reached from home'

# ==========================================================================================
# the shell: ground, hall wall, roof, the tunnel and the PLAY ZONE gate
# ==========================================================================================
def build_shell():
    g = Builder('Floor_Concrete', shell_col)
    lo, hi = WALL_R + 8.0, 6.0
    g.box((CX - lo, CY - lo - TUNNEL_L, -1.0), (CX - hi, CY + lo, 0.3), 'concrete')       # a slab under everything,
    g.box((CX + hi, CY - lo - TUNNEL_L, -1.0), (CX + lo, CY + lo, 0.3), 'concrete')       # with a hole for the shaft
    g.box((CX - hi, CY - lo - TUNNEL_L, -1.0), (CX + hi, CY - hi, 0.3), 'concrete')
    g.box((CX - hi, CY + hi, -1.0), (CX + hi, CY + lo, 0.3), 'concrete')
    g.finish()

    w = Builder('Walls', shell_col)
    panel = 2 * (WALL_R + WALL_T) * math.tan(math.radians(3.75)) + 0.3
    for j in range(48):
        a = 7.5 * j + 3.75
        if abs((a - 270.0 + 180) % 360 - 180) < 7.5:
            continue                                   # the two panels the tunnel comes through: built square below
        c = P(WALL_R + WALL_T / 2, a, ROOF_Z / 2)
        w.obox(c, (WALL_T, panel, ROOF_Z), a, 'wall_white')
    south = CY - WALL_R * math.cos(math.radians(7.5)) + 0.4
    edge_x = (WALL_R + WALL_T) * math.sin(math.radians(7.5)) + 0.4
    # (0.9 back from the tunnel's width: the tunnel's side pads are that thick and stood INSIDE these two blocks,
    # their faces in the same plane as the blocks' own for the last three studs of the tunnel)
    w.box((CX - edge_x, CY - WALL_R - WALL_T, 0.0), (CX - TUNNEL_W / 2 - 0.9, south, ROOF_Z), 'wall_white')
    w.box((CX + TUNNEL_W / 2 + 0.9, CY - WALL_R - WALL_T, 0.0), (CX + edge_x, south, ROOF_Z), 'wall_white')
    w.box((CX - TUNNEL_W / 2 - 0.9, CY - WALL_R - WALL_T, TUNNEL_H + 1.0), (CX + TUNNEL_W / 2 + 0.9, south, ROOF_Z), 'wall_white')
    w.finish()

    c = Builder('Ceiling_Structure', shell_col)
    c.box((CX - 162, CY - 162, ROOF_Z), (CX + 162, CY + 162, ROOF_Z + 2), 'deck')
    for i in range(-3, 4):
        c.box((CX - 158, CY + i * 44 - 0.6, ROOF_Z - 4.0), (CX + 158, CY + i * 44 + 0.6, ROOF_Z), 'steel')
    for i in (-2, 0, 2):
        c.box((CX + i * 52 - 0.5, CY - 158, ROOF_Z - 2.6), (CX + i * 52 + 0.5, CY + 158, ROOF_Z - 1.4), 'steel')
    c.finish()
    f = Builder('Ceiling_Fixtures', shell_col)
    n = 0
    for ix in range(-4, 5):
        for iy in range(-4, 5):
            x, y = CX + ix * 34.0 + (iy % 2) * 6, CY + iy * 34.0
            if math.hypot(x - CX, y - CY) > WALL_R - 12:
                continue
            n += 1
            f.box((x - 5.5, y - 0.9, ROOF_Z - 5.0), (x + 5.5, y + 0.9, ROOF_Z - 4.4), 'wall_white')
            f.box((x - 5.0, y - 0.55, ROOF_Z - 5.25), (x + 5.0, y + 0.55, ROOF_Z - 5.0), 'lamp_off' if n % 4 == 0 else 'lamp_on')
    f.finish()

    # the tunnel: a small padded hole through the hall wall, tall enough that the PLAY ZONE sign fills its mouth
    t = Builder('Tunnel', shell_col)
    x0, x1 = CX - TUNNEL_W / 2, CX + TUNNEL_W / 2
    y_in, y_out = CY - WALL_R + 0.2, CY - WALL_R - WALL_T - TUNNEL_L
    rows = ((0.3, 4.9), (4.9, 9.5), (9.5, TUNNEL_H + 1.0))          # three courses of pads, laid like bricks in two colours
    n = 0
    y = y_out
    while y < y_in - 0.1:
        y2 = min(y + 5.5, y_in)
        for side, x in ((-1, x0), (1, x1)):
            for r, (za, zb) in enumerate(rows):
                t.box((x - (0.9 if side < 0 else 0), y, za), (x + (0.9 if side > 0 else 0), y2, zb), ('blue', 'yellow')[(n + r + (side > 0)) % 2])
        t.box((x0, y, TUNNEL_H + 0.95), (x1, y2, TUNNEL_H + 1.8), ('yellow', 'navy', 'blue')[n % 3])
        y, n = y2, n + 1
    for r, (za, zb) in enumerate(rows):                              # the closed end behind you
        for c in range(3):
            xa = x0 - 0.9 + c * (TUNNEL_W + 1.8) / 3
            t.box((xa, y_out - 0.9, za), (xa + (TUNNEL_W + 1.8) / 3, y_out, zb), ('yellow', 'blue')[(r + c) % 2])
    t.box((x0 - 0.9, y_out - 0.9, TUNNEL_H + 1.0), (x1 + 0.9, y_out, TUNNEL_H + 1.8), 'blue')
    for i, off in enumerate((7.0, TUNNEL_L - 6.0)):                  # two caged bulkhead lamps in the roof
        t.box((CX - 1.6, y_out + off - 1.0, TUNNEL_H + 0.55), (CX + 1.6, y_out + off + 1.0, TUNNEL_H + 0.95), 'steel')
        t.box((CX - 1.25, y_out + off - 0.7, TUNNEL_H + 0.35), (CX + 1.25, y_out + off + 0.7, TUNNEL_H + 0.6), 'lamp_warm')
        light(f'L6_Tunnel_{i}', (CX, y_out + off, TUNNEL_H - 0.8), 'point', 30, 1.0, rgb=(255, 214, 150), energy=1200)
    t.finish()

    # the gate: two padded posts and the blue lintel that carries the sign
    gate_y = CY - WALL_R + 6.0
    gt = Builder('Gate', shell_col)
    for side in (-1, 1):
        for i, (za, zb) in enumerate(((0.3, 3.2), (3.2, 6.1), (6.1, 9.0), (9.0, 12.4))):
            gt.cyl((CX + side * (LANE_HALF + 0.3), gate_y, za), (CX + side * (LANE_HALF + 0.3), gate_y, zb), 1.25,
                   ('red', 'yellow')[(i + (side > 0)) % 2], 10, True)
    gt.box((CX - LANE_HALF - 1.6, gate_y - 0.8, 9.0), (CX + LANE_HALF + 1.6, gate_y + 0.8, 12.4), 'blue')
    gt.finish()
    SIGNS.append([[CX, gate_y - 0.82, 10.7], 13.4, 2.9, '-y', 'PLAY ZONE', [22, 40, 150], [255, 255, 255], 'playzone_letters'])
    SIGNS.append([[CX, gate_y + 0.82, 10.7], 13.4, 2.9, '+y', 'PLAY ZONE', [22, 40, 150], [255, 255, 255], 'playzone_letters'])
    light('L6_Gate', (CX, gate_y - 3.0, 8.4), 'spot', 30, 1.4, 120, energy=1500)
    anchor('L6_Anchor_Spawn', (CX, y_out + 7.0, 3.0))
    anchor('L6_Anchor_Gate', (CX, gate_y, 3.0))
    return gate_y


# ==========================================================================================
# floors: the court, the lane, the dial round the post
# ==========================================================================================
def build_floors():
    f = Builder('Floor_FoamTiles', shell_col)
    worn = {(-3, 1), (2, -3), (1, 2)}
    for i in range(-4, 4):
        for j in range(-4, 4):
            x, y = CX + i * 12.0, CY + j * 12.0
            near = math.hypot(max(abs(x + 6 - CX) - 6, 0), max(abs(y + 6 - CY) - 6, 0))
            if near > R[0] + 1.5 or (i in (-1, 0) and j in (-1, 0)):
                continue
            f.box((x, y, 0.3), (x + 12, y + 12, 0.9), 'concrete' if (i, j) in worn else ('tile_green', 'tile_blue')[(i + j) % 2])
    q, c = LID_REACH, LID_CORE                   # the four centre tiles, cut back round the lid (a cross: see build_finale)
    for n, (xa, ya, xb, yb) in enumerate(((-12, -12, -q, 12), (q, -12, 12, 12), (-q, -12, q, -q), (-q, q, q, 12))):
        f.box((CX + xa, CY + ya, 0.3), (CX + xb, CY + yb, 0.9), ('tile_blue', 'tile_green')[n % 2])
    for sx in (-1, 1):
        for sy in (-1, 1):
            f.box((CX + min(sx * c, sx * q), CY + min(sy * c, sy * q), 0.3), (CX + max(sx * c, sx * q), CY + max(sy * c, sy * q), 0.9), 'tile_blue')
    # (the lane began six studs inside the court's own tiles: 84 square studs of two floors in one plane, which is
    # the patch of flickering mats in the owner's picture of 2026-10-07)
    y, n = CY - 48.0, 0                          # the lane, the gate and the tunnel
    end = CY - WALL_R - WALL_T - TUNNEL_L
    while y > end + 0.1:
        y2 = max(y - 12.0, end)
        half = LANE_HALF if y2 >= CY - WALL_R else TUNNEL_W / 2
        f.box((CX - half, y2, 0.3), (CX + half, y, 0.9), ('tile_green', 'tile_blue')[n % 2])
        y, n = y2, n + 1
    x0, y0, x1, y1, zf, zc = EXIT_ROOM                 # the same mats in the room under the court, worn through in places
    for i in range(round(ROOM_W / 6.0)):
        for j in range(round(ROOM_D / 6.0)):
            f.box((x0 + 6.0 * i, y0 + 6.0 * j, zf - 0.17), (x0 + 6.0 * i + 6.0, y0 + 6.0 * j + 6.0, zf),
                  'concrete' if (i * 7 + j * 3) % 11 == 0 else ('tile_green', 'tile_blue')[(i + j) % 2])
    f.finish()
    balls = Builder('Hall_Balls', shell_col)      # a few loose balls on the court
    for n in range(26):
        a, r = rng.uniform(0, 360), rng.uniform(9, 41)
        balls.ball(P(r, a, 1.45), 0.55, ('red', 'yellow', 'blue', 'green', 'orange')[n % 5])
    balls.finish()


# ==========================================================================================
# the frame
# ==========================================================================================
SKIP_RAIL = set()       # (floor, band, sector) of a ledge whose front rail a slide or a bridge comes through
SKIP_FACE = set()       # (floor, band, sector) of a gallery whose face net a slide comes through


def wall_style(nets, pads, p0, p1, zb, zt, key):
    """A closed side between two cells: netting, sometimes with a padded lower panel."""
    p0, p1 = Vector(p0), Vector(p1)
    if key % 9 == 0 and zt - zb > 8:
        c = (p0 + p1) / 2
        yaw = math.degrees(math.atan2(p1.y - p0.y, p1.x - p0.x))
        pads.obox((c.x, c.y, zb + 2.5), ((p1 - p0).length, 0.9, 5.0), yaw, FRAME_VINYL[key % len(FRAME_VINYL)])
        zb += 5.0
    nets.face([(p0.x, p0.y, zb), (p1.x, p1.y, zb), (p1.x, p1.y, zt), (p0.x, p0.y, zt)],
              'net_yellow' if key % 13 == 0 else 'net_black')


# A player-only escape from the gate lane. The straight lane fence AND the polar
# cell boundary need an aperture: cutting only the first leaves a second net ahead.
ESCAPE_SIDE, ESCAPE_Y = 1, CY - WALL_R + 15.6
ESCAPE_WIDTH, ESCAPE_HEIGHT, ESCAPE_PAD = 3.2, 6.5, 0.45
ESCAPE_CELL = (0, 6, 38)
ESCAPE_ANGLE = span(6, 38)[0]
ESCAPE_X = CX + (CY - ESCAPE_Y) * math.tan(math.radians(ESCAPE_ANGLE - 270.0))
ESCAPE_CUTS = []


def escape_net(nets, arches, p0, p1, zb, zt):
    """Replace one net sheet with three disjoint sheets and a padded portal.

    Both apertures share their Y interval; their 3.2-stud projected width remains
    clear all the way from the lane into the actual polar ground-floor cell.
    """
    p0, p1 = Vector(p0), Vector(p1)
    if p0.y > p1.y:
        p0, p1 = p1, p0
    ya, yb = ESCAPE_Y - ESCAPE_WIDTH / 2, ESCAPE_Y + ESCAPE_WIDTH / 2
    assert p0.y < ya - 2 * ESCAPE_PAD and p1.y > yb + 2 * ESCAPE_PAD
    at = lambda y: p0 + (p1 - p0) * ((y - p0.y) / (p1.y - p0.y))
    lo, hi = at(ya), at(yb)
    roof = zb + ESCAPE_HEIGHT
    assert 5.5 < ESCAPE_HEIGHT < 8.2 and roof + 2 * ESCAPE_PAD < zt

    def sheet(a, b, bottom, upper):
        nets.face([(a.x, a.y, bottom), (b.x, b.y, bottom),
                   (b.x, b.y, upper), (a.x, a.y, upper)], 'net_black')
    sheet(p0, lo, zb, zt)
    sheet(hi, p1, zb, zt)
    sheet(lo, hi, roof, zt)
    # Shift along Y, rather than along the diagonal, to preserve the clear width.
    left, right = at(ya - ESCAPE_PAD), at(yb + ESCAPE_PAD)
    for q in (left, right):
        arches.cyl((q.x, q.y, zb), (q.x, q.y, roof + ESCAPE_PAD), ESCAPE_PAD, 'yellow', 8, True)
    arches.cyl((left.x, left.y, roof + ESCAPE_PAD),
               (right.x, right.y, roof + ESCAPE_PAD), ESCAPE_PAD, 'blue', 8, True)
    ESCAPE_CUTS.append((tuple(lo), tuple(hi)))


def build_frame():
    posts, beams = Builder('Frame_Posts', frame_col), Builder('Frame_Beams', frame_col)
    decks, nets, pads = Builder('Frame_Decks', frame_col), Builder('Frame_Nets', frame_col), Builder('Frame_Panels', frame_col)
    deep = Builder('Frame_DecksDeep', frame_col)       # the same mats, further in: the importer textures only their tops
    arches, steps = Builder('Frame_Entrances', frame_col), Builder('Frame_SoftSteps', frame_col)
    post_cols = ['yellow', 'yellow', 'green', 'red', 'yellow', 'blue']
    rail_cols = ['blue', 'red', 'yellow', 'green']
    tops = [4 * H + 4.9, 8 * H + 4.9] + [FLOORS * H + 0.4] * 5

    # posts: one tall padded post at every corner of the grid
    for i in range(7):
        count = 24 if i <= 2 else 48
        for j in range(count):
            a = 15.0 * j + 7.5 if count == 24 else 7.5 * j
            x, y, _ = P(R[i], a)
            if y < CY and abs(x - CX) < LANE_HALF - 0.4:
                continue
            posts.cyl((x, y, 0.3), (x, y, tops[i]), POST_R, post_cols[(j // 2 + i * 2) % len(post_cols)], 8)
    lane_posts = [CY - 48.0 - 12.0 * i for i in range(10)]
    for y in lane_posts:
        r = CY - y
        top = tops[0] if r < R[1] else tops[1] if r < R[2] else tops[2]
        for side in (-1, 1):
            posts.cyl((CX + side * LANE_HALF, y, 0.3), (CX + side * LANE_HALF, y, top), POST_R, post_cols[int(r // 12) % len(post_cols)], 8)
    posts.finish()

    # decks: one slab per cell, three strips where a stairwell needs one of them open.
    # MATS_20261007 (owner: "we have overlapping textures several places"). A slab was a rectangle as wide as its
    # cell's OUTER edge, so every slab lay over its two neighbours in a wedge up to four studs wide, every other
    # one 0.04 higher so that the two did not flicker. With one flat colour nobody saw it; with a printed mat on
    # every slab each cell showed its neighbours' mats lying across its own at an angle. A slab is now the shape of
    # its cell (Builder.sector), they all lie at one height, and where a band of 24 meets a band of 48 the outer
    # edge of the inner one has the extra corner that makes the two edges the same line.
    def slab(k, b, s, ra, rb, colour):
        a0, a1 = span(b, s)
        z = 0.65 if k == 0 else k * H
        split = b + 1 < NB and abs(rb - R[b + 1]) < 1e-6 and NSEC[b + 1] == 2 * NSEC[b]
        (decks if b <= 2 else deep).sector(ra, rb, a0, a1, z, 0.6 if k == 0 else 0.7, colour, split)

    def deck_colour(k, b, s):
        if (s * 7 + b * 3 + k) % 5 == 0:
            return FRAME_VINYL[(s * 3 + b * 5 + k * 2) % len(FRAME_VINYL)]
        return ('navy', 'mat_blue')[(s + b + k) % 2]

    for k in range(FLOORS + 1):
        for b in range(NB):
            for s in range(NSEC[b]):
                roofed = k == TOPK[b] + 1 and TERRACE.get(b) is None        # the roof over the top floor
                if in_lane(b, s) or not (kind(k, b, s) or roofed):
                    continue
                if (b, s) in WELL_OF:
                    gone = hole(k, b, s)
                    for lane, (la, lb) in LANES.items():
                        if lane != gone:
                            slab(k, b, s, R[b] + la, R[b] + lb, deck_colour(k, b, s))
                else:
                    slab(k, b, s, R[b], R[b + 1], 'navy' if roofed else deck_colour(k, b, s))
    decks.finish()
    deep.finish()

    # walls between cells, gallery faces, ledge rails
    def face_bay(k, radius, a0, a1, gate=False):
        """The side of a gallery that looks into the court: a padded rail at the foot and netting to the ceiling."""
        p0, p1 = chord(radius, a0, a1)
        zb, zt = ftop(k), (k + 1) * H - 0.35
        if gate:
            c = (p0 + p1) / 2
            arches.obox((c.x, c.y, zt - 0.2), ((p1 - p0).length, 1.2, 0.5), math.degrees(math.atan2(p1.y - p0.y, p1.x - p0.x)), 'red')
            return
        beams.cyl((p0.x, p0.y, zb + 0.6), (p1.x, p1.y, zb + 0.6), 0.55, rail_cols[k % 4], 6)
        nets.face([(p0.x, p0.y, zb + 1.15), (p1.x, p1.y, zb + 1.15), (p1.x, p1.y, zt), (p0.x, p0.y, zt)], 'net_black')

    def rail_bay(k, p0, p1):
        """The edge of a ledge: a net to chest height with a padded rail along the top."""
        p0, p1 = Vector(p0), Vector(p1)
        zb = ftop(k)
        beams.cyl((p0.x, p0.y, zb + 0.5), (p1.x, p1.y, zb + 0.5), 0.5, rail_cols[(k + 1) % 4], 6)
        beams.cyl((p0.x, p0.y, zb + 4.7), (p1.x, p1.y, zb + 4.7), 0.42, 'yellow', 6)
        nets.face([(p0.x, p0.y, zb + 1.2), (p1.x, p1.y, zb + 1.2), (p1.x, p1.y, zb + 4.2), (p0.x, p0.y, zb + 4.2)], 'net_black')

    key = 0
    for cell in CELLS:
        k, b, s = cell
        what = kind(k, b, s)
        a0, a1 = span(b, s)
        zb, zt = ftop(k), (k + 1) * H - 0.35
        n = NSEC[b]
        # the side toward the next sector
        nxt = (k, b, (s + 1) % n)
        if kind(*nxt):
            if not is_open(cell, nxt):
                key += 1
                wall_style(nets, pads, P(R[b] + POST_R + 0.1, a1), P(R[b + 1] - POST_R - 0.1, a1), zb, zt, key)
        elif what == 'terrace':
            rail_bay(k, P(R[b] + 0.9, a1), P(R[b + 1] - 0.9, a1))
        else:
            nets.face([P(R[b] + 0.9, a1, zb), P(R[b + 1] - 0.9, a1, zb), P(R[b + 1] - 0.9, a1, zt), P(R[b] + 0.9, a1, zt)], 'net_black')
        # the side toward the previous sector only needs closing when nothing is there (the lane)
        if not kind(k, b, s - 1):
            if what == 'terrace':
                rail_bay(k, P(R[b] + 0.9, a0), P(R[b + 1] - 0.9, a0))
            else:
                if cell == ESCAPE_CELL:
                    escape_net(nets, arches, P(R[b] + 0.9, a0), P(R[b + 1] - 0.9, a0), zb, zt)
                else:
                    nets.face([P(R[b] + 0.9, a0, zb), P(R[b + 1] - 0.9, a0, zb), P(R[b + 1] - 0.9, a0, zt), P(R[b] + 0.9, a0, zt)], 'net_black')
        # the side toward the next band out
        if b + 1 < NB:
            for s2 in ([s] if NSEC[b + 1] == n else [2 * s, 2 * s + 1]):
                other = (k, b + 1, s2)
                if not kind(*other) or is_open(cell, other):
                    continue
                b0_, b1_ = span(b + 1, s2)
                if frozenset((cell, other)) in FACE:
                    face_bay(k, R[b + 1], b0_, b1_)
                else:
                    key += 1
                    p0, p1 = chord(R[b + 1], b0_, b1_)
                    wall_style(nets, pads, p0, p1, zb, zt, key)
        # the side toward the court when no band stands in front of it
        inner = (k, b - 1, s if b == 0 or NSEC[b - 1] == n else s // 2)
        if b == 0 or not kind(*inner):
            if what == 'terrace':
                if (k, b, s) not in SKIP_RAIL:
                    rail_bay(k, *chord(R[b], a0, a1))
            elif (k, b, s) not in SKIP_FACE:
                face_bay(k, R[b], a0, a1, gate=(k == 0 and b == 0 and s in GATES))
    # the lane: netting on both sides as high as the frame stands beside it, a rail on every floor
    lane_posts = [CY - 43.5] + [CY - 48.0 - 12.0 * i for i in range(10)]
    for side in (-1, 1):
        x = CX + side * LANE_HALF
        for ya, yb in zip(lane_posts, lane_posts[1:]):
            r = CY - (ya + yb) / 2
            floors_here = 4 if r < R[1] else 8 if r < R[2] else 12
            for k in range(floors_here):
                zb, zt = ftop(k), (k + 1) * H - 0.35
                if side == ESCAPE_SIDE and k == 0 and yb < ESCAPE_Y < ya:
                    escape_net(nets, arches, (x, yb + 0.9, 0), (x, ya - 0.9, 0), zb, zt)
                else:
                    nets.face([(x, ya - 0.9, zb), (x, yb + 0.9, zb), (x, yb + 0.9, zt), (x, ya - 0.9, zt)], 'net_black')
                if k:
                    beams.cyl((x, ya, k * H), (x, yb, k * H), BEAM_R, rail_cols[k % 4], 6)
            if floors_here < 12:
                rail_bay(floors_here, (x, ya - 0.9), (x, yb + 0.9))
    nets.finish()
    pads.finish()
    arches.finish()
    beams.finish()

    # the stair flights: five soft steps each
    for w in WELLS:
        for k in range(w['k0'], w['k1']):
            s, base, tangent, half, direction, z0, z1 = flight_frame(w, k)
            yaw = math.degrees(math.atan2(tangent.y, tangent.x))
            for n in range(5):
                c = base + tangent * (half - RUN + 2.4 * (n + 0.5))
                # (the top step ended flush with the deck above and stood partly in it: two surfaces in one plane. It
                # stops 0.04 short now and reaches 0.4 under the mat it leads to: mats meet edge to edge since
                # 2026-10-07, and a step that ended exactly on that edge left a seam with nothing under it)
                height = (z1 - z0) * (n + 1) / 5 - (0.04 if n == 4 else 0.0)
                reach = 0.4 if n == 4 else 0.0
                c = c + tangent * (reach / 2)
                steps.obox((c.x, c.y, z0 + height / 2), (2.4 + reach, 4.9, height), yaw, FRAME_VINYL[(n + s + k) % len(FRAME_VINYL)])
    steps.finish()


# ==========================================================================================
# bridges, slides, things to hide in and behind
# ==========================================================================================
def smooth_path(points, step=1.5):
    """Catmull-Rom through the authored points, resampled about every `step` studs."""
    pts = [Vector(q) for q in points]
    out = []
    for i in range(len(pts) - 1):
        p0, p1, p2, p3 = pts[max(i - 1, 0)], pts[i], pts[i + 1], pts[min(i + 2, len(pts) - 1)]
        n = max(1, math.ceil((p2 - p1).length / step))
        for k in range(n):
            t = k / n
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t +
                              (-p0 + 3 * p1 - 3 * p2 + p3) * t * t * t))
    out.append(pts[-1])
    return out


def frames(path):
    """A side and an up vector for every point of a path, carried from point to point (parallel transport).
    Taking them from the world's up axis instead pinches the tube wherever the path runs steeply."""
    out = []
    side = None
    for i, q in enumerate(path):
        t = (path[min(i + 1, len(path) - 1)] - path[max(i - 1, 0)]).normalized()
        if side is None:
            side = t.cross(Vector((0, 0, 1)))
            side = side.normalized() if side.length > 1e-4 else Vector((1, 0, 0))
        else:
            side = side - t * side.dot(t)
            side = side.normalized() if side.length > 1e-6 else out[-1][0]
        out.append((side, side.cross(t).normalized()))
    return out


def sector_of(angle):
    return int(((angle + 7.5) % 360) // 15)


def plan_slides():
    """The slides that hang down the gallery face into the court. Each is a list of (radius, angle, height)."""
    out = {}

    # A slide's mouth stands in the MIDDLE of a sector. At a sector's edge there is a post on the ledge's rim, and the
    # first three of these ran straight into one a few studs in (found riding them, 2026-10-06).
    # The two tall slides run ONE way: off the second ledge, round the face over the first ledge, and out along the
    # first ledge's inner side (between its rail and the walk the Counter uses). The first version zig-zagged down
    # to the court and doubled back on itself twice; a rider stuck fast in both hairpins (found riding them).
    def tall(top, d):
        return [(64, top, 83.4), (59.5, top, 82.9), (56, top + 3 * d, 80.0), (55.5, top + 15 * d, 73.0), (55.5, top + 30 * d, 62.0),
                (51.5, top + 40 * d, 55.0), (49.5, top + 48 * d, 49.5), (48.7, top + 56 * d, 45.0), (48.5, top + 64 * d, 43.1),
                (48.5, top + 71 * d, 42.8)]
    out['arena_orange'] = ('orange', tall(75.0, -1), [(8, 1, sector_of(75.0))], [])
    out['arena_yellow'] = ('yellow', tall(255.0, -1), [(8, 1, sector_of(255.0))], [])
    # from the first ledge to the court, one way too: over the rim, down under the court lamp that hangs at 112.5
    # degrees (the first version ran through that lamp and doubled back twice), round past the gateway at 135 with
    # room for the Counter under it, and out between the gateways at 135 and 180
    out['arena_blue'] = ('blue', [(49.2, 105.0, 43.4), (45.2, 105.0, 43.0), (41.5, 107.0, 40.6), (40.3, 113.0, 33.0),
                                  (40, 126.0, 25.0), (40, 140.0, 17.5), (39.8, 152.0, 11.0), (39.2, 161.0, 5.8),
                                  (38.6, 166.0, 3.9), (38.2, 170.0, 3.45)],
                         [(4, 0, sector_of(105.0))], [])
    a0, d = 300.0, 1         # from the gallery on the second floor
    out['arena_green'] = ('green', [(47.8, a0, 23.5), (45.0, a0, 23.2), (41, a0 + 8 * d, 20.2), (39.8, a0 + 24 * d, 10.6),
                                    (38.6, a0 + 32 * d, 4.4), (38.2, a0 + 38 * d, 3.45)],
                          [], [(2, 0, sector_of(a0))])
    return out


SLIDE_PLANS = plan_slides()
for colour, path, rails, faces in SLIDE_PLANS.values():
    SKIP_RAIL.update(rails)
    SKIP_FACE.update(faces)
for pair in BRIDGES:
    for s in pair:
        SKIP_RAIL.add((BRIDGE_K, BRIDGE_B, s))


def build_bridges():
    b = Builder('Frame_Bridges', frame_col)
    n = Builder('Frame_BridgeNets', frame_col)
    z, rad = BRIDGE_K * H, R[BRIDGE_B]
    top = ftop(BRIDGE_K)
    before = len(PRIMS)
    rail_offset, beam_radius = 3.05, 0.55
    assert 2 * (rail_offset - beam_radius) >= 5.0, 'bridge must stay five studs clear'
    # what you walk on is rope net with a padded slat every few studs: from the bridge you look straight down
    # through it at the post, and from the court you look up through it at whoever is crossing
    hub = 3.7
    n.face([(CX - hub, CY - hub, top - 0.12), (CX + hub, CY - hub, top - 0.12), (CX + hub, CY + hub, top - 0.12),
            (CX - hub, CY + hub, top - 0.12)], 'net_yellow')
    for i, pair in enumerate(BRIDGES):
        for j, s in enumerate(pair):
            a = 15.0 * s
            across = Vector((-math.sin(math.radians(a)), math.cos(math.radians(a)), 0))
            zq = top - 0.08 + 0.01 * (2 * i + j)
            q0, q1 = Vector(P(2.6, a, zq)), Vector(P(rad + 0.6, a, zq))
            n.face([tuple(q0 - across * 2.5), tuple(q1 - across * 2.5), tuple(q1 + across * 2.5), tuple(q0 + across * 2.5)], 'net_yellow')
            r, k = 8.0, 0
            while r < rad - 2.0:
                b.obox(P(r, a, top - 0.2), (0.8, 5.6, 0.4), a, ('yellow', 'blue', 'yellow', 'red')[k % 4])
                for side in (-1, 1):
                    q = Vector(P(r, a)) + across * (rail_offset * side)
                    b.cyl((q.x, q.y, top - 0.1), (q.x, q.y, z + 4.7),
                          0.45, ('yellow', 'blue', 'red')[k % 3], 8, True)
                r, k = r + 6.0, k + 1
            for side in (-1, 1):
                off = across * (rail_offset * side)
                p0, p1 = Vector(P(4.5, a)) + off, Vector(P(rad + 0.4, a)) + off
                b.cyl((p0.x, p0.y, top - 0.1), (p1.x, p1.y, top - 0.1), beam_radius, 'blue', 8, True)
                n.face([(p0.x, p0.y, z + 0.4), (p1.x, p1.y, z + 0.4), (p1.x, p1.y, z + 4.6), (p0.x, p0.y, z + 4.6)], 'net_yellow')
                b.cyl((p0.x, p0.y, z + 4.7), (p1.x, p1.y, z + 4.7), 0.35, 'yellow', 6)
                # what is left of the ledge's rail either side of the bridge
                q0, q1 = chord(rad, a - 7.5, a + 7.5)
                near = Vector(P(rad, a)) + off
                far = q1 if side > 0 else q0
                n.face([(near.x, near.y, z + 1.5), (far.x, far.y, z + 1.5), (far.x, far.y, z + 4.5), (near.x, near.y, z + 4.5)], 'net_black')
                b.cyl((near.x, near.y, z + 5.05), (far.x, far.y, z + 5.05), 0.55, 'yellow', 6)
                # One end post per rail reaches both the bridge rail and the
                # ledge rail (their centres differ in height by 0.35 studs).
                b.cyl((p1.x, p1.y, top - 0.1), (p1.x, p1.y, z + 5.05),
                      beam_radius, 'red', 8, True)
                assert (p1 - near).length < 2 * beam_radius, 'landing rails must meet the end post'

    # A ring around the hub with four open portals. Each corner is an L joining
    # the rails of two adjacent arms; no rail crosses a walking/nav centre line.
    angle = math.radians(15.0 * BRIDGES[0][0])
    u = Vector((math.cos(angle), math.sin(angle), 0))
    v = Vector((-math.sin(angle), math.cos(angle), 0))
    centre = Vector((CX, CY, 0))
    for su in (-1, 1):
        for sv in (-1, 1):
            corner = centre + rail_offset * (su * u + sv * v)
            ends = (centre + 4.5 * su * u + rail_offset * sv * v,
                    centre + rail_offset * su * u + 4.5 * sv * v)
            for end in ends:
                b.cyl((corner.x, corner.y, z + 4.7), (end.x, end.y, z + 4.7), 0.35, 'yellow', 8, True)
                b.cyl((corner.x, corner.y, top - 0.1), (end.x, end.y, top - 0.1), beam_radius, 'blue', 8, True)
                b.cyl((end.x, end.y, top - 0.1), (end.x, end.y, z + 4.7), 0.45, 'yellow', 8, True)
            b.cyl((corner.x, corner.y, top - 0.1), (corner.x, corner.y, z + 4.7), 0.45, 'red', 8, True)
    # 60 original bridge solids, plus 72 slat uprights, eight landing posts and
    # 28 hub parts. Existing side beams are enlarged, not duplicated.
    assert sum(row[0] == 'Frame_Bridges' for row in PRIMS[before:]) == 168
    b.finish()
    n.finish()


def build_slides():
    sl = Builder('Frame_Slides', frame_col)
    post_tops = (4 * H + 4.9, 8 * H + 4.9, FLOORS * H + 0.4)
    for name, (colour, polar, rails, faces) in SLIDE_PLANS.items():
        path = smooth_path([P(r, a, z) for r, a, z in polar], 3.6)
        # no post may stand inside the trough you ride (its inside is 2.1 studs either side of the centre line; the
        # moulded tube round it is wider and may brush a post)
        nearest = min(math.hypot(q.x - P(R[i], 15.0 * j + 7.5)[0], q.y - P(R[i], 15.0 * j + 7.5)[1])
                      for q in path for i in range(3) if q.z - 3.1 < post_tops[i] for j in range(24))
        print('L6 SLIDE', name, 'passes its nearest post at %.2f studs (a post is inside the trough under %.2f)' % (nearest, 2.1 + POST_R))
        assert nearest > 2.1 + POST_R + 0.12, f'{name} runs into a post'
        # a set pace: brisk down the slide, easing off over the last stretch so you step out instead of shooting out
        rest = [0.0] * len(path)
        for i in range(len(path) - 2, -1, -1):
            rest[i] = rest[i + 1] + (path[i + 1] - path[i]).length
        sl.tube(path, 3.1, colour, 10, open_first=3, open_last=2,
                speeds=[round(38.0 if rest[i] > 26.0 else 15.0 + 23.0 * rest[i] / 26.0, 1) for i in range(len(path) - 1)])
        SLIDES.append((name, 'tube', [tuple(q) for q in path], 3.1, colour, (0.0, 360.0)))
        SLIDE_PLACES.append((name, None, 0.0))
    # the way out: the funnel under the post tips you into a tube that winds down three turns and comes out of the
    # ceiling of the small room below. Its pace is set along the way (import: L6SlideSpeed), easing off over the last turn.
    centre = Vector((CX, CY, 0.0))
    route = [Vector(q) + centre for q in EXIT['top'] + EXIT['helix'] + EXIT['tail']]
    ride = smooth_path(route, 2.6)
    left = [0.0] * len(ride)
    for i in range(len(ride) - 2, -1, -1):
        left[i] = left[i + 1] + (ride[i + 1] - ride[i]).length

    def pace(rest):
        if rest > 115.0:
            return 40.0
        if rest > 27.0:
            return 18.0 + 22.0 * (rest - 27.0) / 88.0
        return 12.0 + 6.0 * rest / 27.0
    sl.tube(ride, EXIT_R, 'yellow', 10, speeds=[round(min(pace(left[i]), 30.0 + 2.0 * i), 1) for i in range(len(ride) - 1)], open_last=3)
    # to look at: one long mesh from the mouth in the shaft to just above the room, and the end piece in the room,
    # which is the one in the owner's picture: clamp bands, a cut-back lip on the floor, years of dirt
    mouth = route[0] + Vector((-1.9, 0.0, 0.86))
    whole = smooth_path([mouth] + route, 2.4)
    split = next(i for i, q in enumerate(whole) if q.z < EXIT_ROOM[5] + 5.2 and i > len(whole) // 2)
    SLIDES.append(('arena_exit', 'tube', [tuple(q) for q in whole[:split + 2]], EXIT_R, 'yellow', (0.0, 360.0),
                   {'resample': False, 'flare': (True, False), 'dirt': 0.22}))
    SLIDES.append(('arena_exit_end', 'tube', [tuple(q) for q in whole[split:]], EXIT_R, 'yellow', (0.0, 360.0),
                   {'resample': False, 'flare': (False, True), 'scoop': 3, 'bands': (7.5, 12.0, 16.5), 'dirt': 0.72}))
    SLIDE_PLACES.append(('arena_exit', None, 0.0))
    SLIDE_PLACES.append(('arena_exit_end', None, 0.0))
    sl.finish()


def build_features():
    """Punch bags, soft blocks, bubble-window panels, crawl tubes: what the photographs are full of."""
    f = Builder('Frame_PlayFeatures', frame_col)
    blocks = Builder('Hall_SoftBlocks', frame_col)
    tubes = Builder('Frame_CrawlTubes', frame_col)
    degree = {}
    for pair in OPEN:
        for c in pair:
            degree[c] = degree.get(c, 0) + 1
    plain = [c for c in CELLS if kind(*c) == 'cell' and (c[1], c[2]) not in WELL_OF and c[1] != RING and not front(c[0], c[1])]
    rng.shuffle(plain)
    used = set()
    nooks = [c for c in plain if degree.get(c, 0) == 1]
    for c in nooks[:150]:
        k, b, s = c
        HIDE.append(('frame_nook', *P(R[b] + 8.0, mid(b, s), ftop(k) + 1.0)))
        used.add(c)
    rest = [c for c in plain if c not in used]
    def corner(b, s, which):
        """A corner of a cell: clear of the cross of ways between its middle and the middles of its sides."""
        delta = span(b, s)[1] - span(b, s)[0]
        return R[b] + (3.3, 12.7, 12.7, 3.3)[which % 4], mid(b, s) + delta * (-0.31, 0.31, -0.31, 0.31)[which % 4]

    for n, c in enumerate(rest[:46]):                  # clusters of punch bags
        k, b, s = c
        z = ftop(k)
        for j in range(2 + n % 2):
            x, y, _ = P(*corner(b, s, n + j))
            f.cyl((x, y, z + 9.0), (x, y, z + 7.4), 0.07, 'black', 3)
            f.cyl((x, y, z + 7.4), (x, y, z + 2.0), 1.15, ('navy', 'red', 'blue', 'purple')[(n + j) % 4], 8, True)
        HIDE.append(('punchbag', *P(R[b] + 8.0, mid(b, s), z + 1.0)))
        used.add(c)
    for n, c in enumerate(rest[46:96]):                # soft blocks left lying about
        k, b, s = c
        z = ftop(k)
        size = (2.6, 3.2, 3.8)[n % 3] if NSEC[b] == 48 else (3.0, 4.0, 4.6)[n % 3]
        blocks.obox(P(*corner(b, s, n), z + size / 2), (size, size, size), mid(b, s) + 15 * (n % 4), VINYL[n % len(VINYL)])
        if n % 2 == 0:
            HIDE.append(('softblock', *P(R[b] + 8.0, mid(b, s), z + 1.0)))
        used.add(c)
    # crawl tubes to hide in: one straight moulded tube in four colours, laid along the back of a cell
    length = 11.0
    for colour in ('red', 'yellow', 'green', 'blue'):
        path = [(-length / 2 + i * length / 4, 0.0, 0.0) for i in range(5)]
        SLIDES.append(('arena_tube_' + colour, 'tube', path, 2.9, colour, (0.0, 360.0)))
    tubes_laid = 0
    for c in rest[96:]:
        k, b, s = c
        # only along a closed back wall, so it never lies across a way through
        outward = [(k, b + 1, s2) for s2 in ([s] if b + 1 < NB and NSEC[b + 1] == NSEC[b] else [2 * s, 2 * s + 1])] if b + 1 < NB else []
        if any(kind(*o) and is_open(c, o) for o in outward):
            continue
        n = tubes_laid
        tubes_laid += 1
        if tubes_laid > 26:
            break
        z = ftop(k) + 2.95
        a = mid(b, s)
        centre = Vector(P(R[b] + 12.7, a, z))
        t = Vector((-math.sin(math.radians(a)), math.cos(math.radians(a)), 0.0))
        colour = ('red', 'yellow', 'green', 'blue')[n % 4]
        pts = [centre + t * (-length / 2 + i * length / 4) for i in range(5)]
        tubes.tube(pts, 2.9, colour, 10)
        SLIDE_PLACES.append(('arena_tube_' + colour, tuple(centre), a + 90.0))
        HIDE.append(('tube', centre.x, centre.y, z - 2.0))
        used.add(c)
    f.finish()
    blocks.finish()
    tubes.finish()
    # bubble-window panels on closed walls, most of them where a gallery can show them off
    n = 0
    for k in range(FLOORS):
        fb = 0 if k <= 3 else 1 if k <= 7 else 2
        for s in range(24):
            if kind(k, fb, s) != 'cell' or (fb, s) in WELL_OF or (s + k * 5) % 4:
                continue
            back = (k, fb + 1, s) if NSEC[fb + 1] == 24 else (k, fb + 1, 2 * s)
            if kind(*back) and not is_open((k, fb, s), back):
                x, y, _ = P(R[fb + 1] - 0.75, 15.0 * s if NSEC[fb + 1] == 24 else mid(fb + 1, 2 * s))
                prop('tube_window_panel', x, y, ftop(k) + 0.5, 15.0 * s + 180.0, 8.4)
                n += 1
    return n


# ==========================================================================================
# light
# ==========================================================================================
def build_lights():
    lamps = Builder('Frame_Lamps', frame_col)

    def fixture(pos, yaw=0.0, warm=False):
        x, y, z = pos
        lamps.obox((x, y, z + 0.32), (3.0, 1.0, 0.5), yaw, 'wall_white')
        lamps.obox((x, y, z + 0.02), (2.6, 0.7, 0.14), yaw, 'lamp_warm' if warm else 'lamp_on')

    # over the post: the brightest light in the level, on a long rod from the crossing of the two bridges
    light('L6_CourtSpot', (CX, CY, 38.4), 'spot', 60, 3.2, 62, energy=30000)
    fixture((CX, CY, 38.7))
    lamps.cyl((CX, CY, 39.2), (CX, CY, BRIDGE_K * H - 0.3), 0.16, 'steel', 6)
    # fill: a light's range ends at 60 studs, so the roof lamps reach nothing. Faint shadowless points hung in the
    # open well stand in for the wash they would give the gallery faces; without them the upper floors are black
    for h in (26.0, 62.0, 98.0, 132.0):
        for i in range(6):
            light(f'L6_Fill_{int(h)}_{i}', P(30.0, 60.0 * i + (h % 4) * 15, h), 'point', 60, 0.06, rgb=(214, 224, 236), energy=300)
    for i in range(8):                               # under the first ledge, washing the court's edge and the low face
        a = 22.5 + 45.0 * i
        if abs((a - 270 + 180) % 360 - 180) < 20:
            continue
        light(f'L6_Court_{i}', P(41.5, a, 38.2), 'spot', 52, 1.0, 110, energy=9000)
        fixture(P(41.5, a, 38.5), a + 90)
    # galleries: a lamp in some bays of every floor, so the wall of galleries is pools of light and long dark stretches
    count = 0
    for k in range(FLOORS):
        fb = 0 if k <= 3 else 1 if k <= 7 else 2
        for s in range(24):
            if kind(k, fb, s) != 'cell' or (s * 5 + k * 7) % 3:
                continue
            pos = P(R[fb] + 5.0, 15.0 * s, (k + 1) * H - 1.25)
            dead = (s + k) % 7 == 0
            if not dead:
                light(f'L6_Gallery_{k}_{s}', (pos[0], pos[1], pos[2] - 0.5), 'spot', 34, 1.4, 150,
                      rgb=(255, 226, 180) if (s + k) % 3 == 0 else (236, 240, 255), energy=1800)
                count += 1
            lamps.obox((pos[0], pos[1], pos[2] + 0.32), (3.0, 1.0, 0.5), 15.0 * s + 90, 'wall_white')
            lamps.obox((pos[0], pos[1], pos[2] + 0.02), (2.6, 0.7, 0.14), 15.0 * s + 90, 'lamp_off' if dead else 'lamp_on')
    # the ledges: open to the roof, lit from posts on their rail
    for b, k in TERRACE.items():
        for s in range(0, 24, 3):
            if in_lane(b, s):
                continue
            light(f'L6_Ledge_{k}_{s}', P(R[b] + 8.0, 15.0 * s + 7.5, k * H + 8.6), 'spot', 34, 0.9, 150, energy=2500)
            fixture(P(R[b] + 8.0, 15.0 * s + 7.5, k * H + 8.9), 15.0 * s + 97.5)
    # the ring corridor and the deep cells: sparse
    for k in range(FLOORS):
        for s in range(48):
            if in_lane(RING, s) or (s * 3 + k * 5) % 8:
                continue
            pos = P(R[RING] + 7.0, mid(RING, s), (k + 1) * H - 1.25)
            light(f'L6_Ring_{k}_{s}', (pos[0], pos[1], pos[2] - 0.5), 'spot', 32, 1.7, 150, energy=1500)
            fixture(pos, mid(RING, s) + 90, warm=(s + k) % 2 == 0)
        for b in (3, 5, 6):
            for s in range(48):
                if kind(k, b, s) and (s * 11 + k * 3 + b * 5) % 23 == 0:
                    pos = P(R[b] + 8.0, mid(b, s), (k + 1) * H - 1.25)
                    light(f'L6_Deep_{k}_{b}_{s}', (pos[0], pos[1], pos[2] - 0.5), 'spot', 30, 1.5, 150, rgb=(255, 214, 150), energy=1200)
                    fixture(pos, mid(b, s) + 90, warm=True)
    # the lane: three lamps hung low between the nets
    for i, y in enumerate((CY - 66.0, CY - 100.0, CY - 134.0)):
        light(f'L6_Lane_{i}', (CX, y, 30.0), 'spot', 50, 1.3, 95, energy=9000)
        fixture((CX, y, 30.3), 90)
    lamps.finish()
    return count


# ==========================================================================================
# the post and what is under it
# ==========================================================================================
def build_finale():
    post = Builder('Finale_Post', finale_col)
    post.cyl((CX, CY, 0.9), (CX, CY, 6.9), 1.6, 'red', 12, True)
    post.cyl((CX, CY, 6.9), (CX, CY, 7.15), 1.72, 'yellow', 12, True)
    post.finish()
    dial = Builder('Finale_Dial', finale_col)                 # the yellow ring is sixty marks: the clock of the last minute
    for i in range(60):
        a = 90.0 - 6.0 * i - 3.0
        dial.obox(P(28.0, a, 0.94), (1.5, 2.3, 0.1), a, 'dial')
    dial.finish()
    # MATS_20261007. The lid was twelve flaps, each a rectangle as wide as the shaft's rim, turned thirty degrees
    # from the last: they lay over one another like a hand of cards, every other one 0.03 higher, each with its own
    # piece of the printed mat at its own angle. It is six pads now that do not touch each other's ground, square to
    # the court's tiles: a cross over the shaft with a square hole for the post, one dark colour, and a yellow
    # collar round the foot of the post over the hole's corners. Everything in the group drops when the minute is up.
    lid = Builder('Finale_Lid', finale_col)
    c, q, hole = LID_CORE, LID_REACH, 1.7
    for xa, ya, xb, yb in ((-c, hole, c, q), (-c, -q, c, -hole), (-q, -c, -c, c), (c, -c, q, c),
                           (-c, -hole, -hole, hole), (hole, -hole, c, hole)):
        lid.box((CX + xa, CY + ya, 0.54), (CX + xb, CY + yb, 0.9), 'navy')
    lid.cyl((CX, CY, 0.9), (CX, CY, 1.0), 2.45, 'yellow', 16, True)
    lid.finish()
    # The ring round it was sixteen flat pads, each overlapping the next where the ring turns. It is one padded roll
    # now: a round tube of twenty-four lengths, a ball in every joint, half sunk in the floor. Round things that run
    # into each other meet in a line; flat ones that lie in one plane fight over it. It hides where lid meets floor.
    rim = Builder('Finale_Rim', finale_col)
    ring_r, roll = SHAFT_R + 0.75, 0.66
    joints = [P(ring_r, 15.0 * i, 0.9) for i in range(24)]
    for i, a in enumerate(joints):
        rim.cyl(a, joints[(i + 1) % 24], roll, 'yellow', 10)
        rim.ball(a, roll, 'yellow')
    rim.finish()

    sh = Builder('Finale_Shaft', finale_col)
    for i in range(12):
        a = 30.0 * i + 15.0
        if abs((a + 180) % 360 - 180) < 31:              # the east side opens into the slide
            sh.obox(P(SHAFT_R + 0.3, a, -2.65), (0.6, 2 * (SHAFT_R + 0.6) * math.tan(math.radians(15.0)) + 0.1, 5.9), a, ('yellow', 'blue')[i % 2])
        else:
            sh.obox(P(SHAFT_R + 0.3, a, -6.45), (0.6, 2 * (SHAFT_R + 0.6) * math.tan(math.radians(15.0)) + 0.1, 13.5), a, ('yellow', 'blue')[i % 2])
    sh.box((CX - SHAFT_R - 1.0, CY - SHAFT_R - 1.0, -14.6), (CX + SHAFT_R + 1.0, CY + SHAFT_R + 1.0, -13.8), 'navy')
    for side in (-1, 1):                                  # unseen: they steer a body off the wall's edge and into the mouth
        sh.obox((CX + 5.8, CY + side * 2.95, -9.4), (2.4, 0.4, 7.4), -26.6 * side, 'guide')
    sh.finish()
    # the shaft's floor is a funnel: whichever side you drop in from, it tips you east into the mouth of the slide
    ramp = Builder('Arena_SlideSurfaces', finale_col)
    za, zb = RAMP_Z0, RAMP_Z0 - RAMP_M * (RAMP_X1 + SHAFT_R)
    ramp.face([(CX - SHAFT_R, CY - 2.4, za), (CX - SHAFT_R, CY + 2.4, za),
               (CX + RAMP_X1, CY + 2.4, zb), (CX + RAMP_X1, CY - 2.4, zb)], 'yellow', True)
    # the two side panels lean in to the middle strip and tip east with it. In Studio each becomes one flat part, so
    # its two edges must be at right angles IN ITS OWN PLANE: straight across in plan they are not (the first version
    # was, came out skewed, and left a ledge a body could stand on). The across edge therefore runs a little east.
    rise = 0.743                                                    # studs up per stud out from the strip
    over = RAMP_M * rise / (1 + RAMP_M ** 2)                        # studs east per stud out, to stay square
    for side in (-1, 1):
        p0 = Vector((CX - SHAFT_R - 1.2, CY + side * 2.4, za + RAMP_M * 1.2))
        out_ = Vector((over, side, rise / (1 + RAMP_M ** 2))) * 3.5
        down = Vector((1.0, 0.0, -RAMP_M)) * (RAMP_X1 + SHAFT_R + 1.2)
        assert abs(out_.dot(down)) < 1e-6
        ramp.face([tuple(p0), tuple(p0 + out_), tuple(p0 + out_ + down), tuple(p0 + down)], 'blue', True)
    ramp.finish()

    # ---- the room the slide ends in: small, padded wall to wall, and long out of use -------------------------
    x0, y0, x1, y1, zf, zc = EXIT_ROOM
    dice = random.Random(SEED + 61)
    room = Builder('ExitRoom', finale_col)
    door0, door1, door_h = x0 + 17.4, x0 + 22.6, 8.4      # the doorway in the north wall
    door_x = (door0 + door1) / 2
    # the bare shell behind the padding: it shows wherever a pad has come away
    room.box((x0 - 1.6, y0 - 1.6, zf - 1.0), (x1 + 1.6, y1 + 1.6, zf - 0.17), 'concrete')
    room.box((x0 - 1.6, y0 - 1.6, zf - 0.17), (x0 - 1.0, y1 + 1.6, zc + 1.4), 'concrete')
    room.box((x1 + 1.0, y0 - 1.6, zf - 0.17), (x1 + 1.6, y1 + 1.6, zc + 1.4), 'concrete')
    room.box((x0 - 1.0, y0 - 1.6, zf - 0.17), (x1 + 1.0, y0 - 1.0, zc + 1.4), 'concrete')
    room.box((x0 - 1.0, y1 + 1.0, zf - 0.17), (door0 - 0.4, y1 + 1.6, zc + 1.4), 'concrete')
    room.box((door1 + 0.4, y1 + 1.0, zf - 0.17), (x1 + 1.0, y1 + 1.6, zc + 1.4), 'concrete')
    room.box((door0 - 0.4, y1 + 1.0, zf + door_h + 0.4), (door1 + 0.4, y1 + 1.6, zc + 1.4), 'concrete')

    def vinyl(i, j):
        tone = (i + j) % 2
        if dice.random() < 0.22:
            tone = 1 - tone
        return (('yellow_worn', 'yellow_dark', 'yellow_worn'), ('navy', 'navy_worn', 'blue_worn'))[tone][dice.randrange(3)]
    rows = ((0.0, 4.4), (4.4, 9.0), (9.0, ROOM_H))
    gone = {('w', 1, 2), ('s', 3, 0), ('e', 2, 1), ('s', 0, 2), ('e', 0, 0), ('w', 3, 1), ('s', 2, 2)}      # pads that have come off the wall
    for j, (za, zb) in enumerate(rows):
        for i in range(round(ROOM_D / 6.0)):               # west and east walls
            ya, yb = y0 + 6.0 * i, y0 + 6.0 * i + 6.0
            for wall, xa in (('w', x0), ('e', x1)):
                if (wall, i, j) in gone:
                    continue
                thick = dice.choice((0.9, 0.9, 0.72))
                if wall == 'w':
                    room.box((xa - thick, ya, zf + za), (xa, yb, zf + zb), vinyl(i, j))
                else:
                    room.box((xa, ya, zf + za), (xa + thick, yb, zf + zb), vinyl(i + 1, j))
        for i in range(round(ROOM_W / 6.0)):               # the south wall
            if ('s', i, j) not in gone:
                thick = dice.choice((0.9, 0.9, 0.72))
                room.box((x0 + 6.0 * i, y0 - thick, zf + za), (x0 + 6.0 * i + 6.0, y0, zf + zb), vinyl(i, j + 1))
        for i, (xa, xb) in enumerate(((x0, x0 + 6.0), (x0 + 6.0, x0 + 12.0), (x0 + 12.0, door0 - 1.5),
                                     (door1 + 1.5, x1))):  # the north wall, either side of the door
            thick = dice.choice((0.9, 0.9, 0.72))
            room.box((xa, y1, zf + za), (xb, y1 + thick, zf + zb), vinyl(i, j))
    room.box((door0 - 1.5, y1, zf + door_h + 0.4), (door1 + 1.5, y1 + 0.9, zf + ROOM_H), 'navy_worn')     # over the door
    for x in (door0 - 0.95, door1 + 0.95):                # the two round pads that flank it
        room.cyl((x, y1 - 0.15, zf), (x, y1 - 0.15, zf + door_h + 0.4), 0.55, 'yellow_worn', 8, True)

    # the ceiling: pads again, cut round the slide where it comes through, with a padded collar
    cross = Vector((EXIT['cross'][0] + CX, EXIT['cross'][1] + CY, zc))
    along = Vector((EXIT_DIR[0], EXIT_DIR[1], 0.0))
    across = Vector((-EXIT_DIR[1], EXIT_DIR[0], 0.0))
    tail = EXIT['tail']
    steep = max(abs(b[2] - a[2]) / math.dist(a[:2], b[:2]) for a, b in zip(tail, tail[1:]) if a[2] >= zc > b[2])
    half_a, half_b = (EXIT_R + 0.75) / math.sin(math.atan(steep)), EXIT_R + 0.75

    def in_hole(x, y):
        d = Vector((x, y, zc)) - cross
        return (d.dot(along) / half_a) ** 2 + (d.dot(across) / half_b) ** 2 < 1.0
    for i in range(round(ROOM_W / 6.0)):
        for j in range(round(ROOM_D / 6.0)):
            xa, ya = x0 + 6.0 * i, y0 + 6.0 * j
            tone = vinyl(i, j)
            if (i, j) in ((3, 0), (1, 1)):                  # two have fallen: bare concrete shows
                room.box((xa, ya, zc + 0.35), (xa + 6.0, ya + 6.0, zc + 0.8), 'concrete')
                continue
            cells = [(xa + 2.0 * u, ya + 2.0 * v) for u in range(3) for v in range(3)]
            if not any(in_hole(x + dx, y + dy) for x, y in cells for dx in (0.0, 1.0, 2.0) for dy in (0.0, 1.0, 2.0)):
                room.box((xa, ya, zc), (xa + 6.0, ya + 6.0, zc + 0.8), tone)
                continue
            for x, y in cells:
                if not any(in_hole(x + dx, y + dy) for dx in (0.0, 1.0, 2.0) for dy in (0.0, 1.0, 2.0)):
                    room.box((x, y, zc), (x + 2.0, y + 2.0, zc + 0.8), tone)
    for n in range(14):                                    # the collar
        a = math.radians(360.0 * n / 14)
        q = cross + along * (half_a + 0.75) * math.cos(a) + across * (half_b + 0.75) * math.sin(a)
        tangent = -along * (half_a + 0.75) * math.sin(a) + across * (half_b + 0.75) * math.cos(a)
        # (every other one hangs a little lower: they lie over each other where the collar turns, in two colours,
        # and with their undersides in one plane the two colours flickered through each other)
        room.obox((q.x, q.y, zc - 0.3 - (0.07 if n % 2 else 0.0)), (tangent.length * 2 * math.pi / 14 + 0.5, 1.7, 0.6),
                  math.degrees(math.atan2(tangent.y, tangent.x)), ('navy_worn', 'navy')[n % 2])

    # the door: a steel frame, the leaf pushed half open into the passage behind, the EXIT sign over it
    room.box((door0 - 0.4, y1 - 0.12, zf), (door0, y1 + 1.7, zf + door_h + 0.4), 'steel')
    room.box((door1, y1 - 0.12, zf), (door1 + 0.4, y1 + 1.7, zf + door_h + 0.4), 'steel')
    room.box((door0, y1 - 0.12, zf + door_h), (door1, y1 + 1.7, zf + door_h + 0.4), 'steel')
    swing = math.radians(72.0)
    leaf = Vector((door0 + 0.1 + 2.5 * math.cos(swing), y1 + 1.5 + 2.5 * math.sin(swing), zf + door_h / 2))
    room.obox(tuple(leaf), (5.0, 0.3, door_h - 0.1), 72.0, 'steel')
    face = Vector((math.sin(swing), -math.cos(swing), 0.0))
    room.obox((leaf.x + face.x * 0.3, leaf.y + face.y * 0.3, zf + 3.9), (3.6, 0.18, 0.24), 72.0, 'stainless')   # the push bar
    room.box((door0 - 1.2, y1 + 1.7, zf - 1.0), (door1 + 1.2, y1 + 14.0, zf), 'concrete')                 # the passage
    room.box((door0 - 1.8, y1 + 1.7, zf), (door0 - 1.2, y1 + 14.0, zf + 10.0), 'white')
    room.box((door1 + 1.2, y1 + 1.7, zf), (door1 + 1.8, y1 + 14.0, zf + 10.0), 'white')
    room.box((door0 - 1.8, y1 + 14.0, zf), (door1 + 1.8, y1 + 14.6, zf + 10.0), 'white')
    room.box((door0 - 1.8, y1 + 1.7, zf + 10.0), (door1 + 1.8, y1 + 14.6, zf + 10.6), 'white')
    room.box((door_x - 1.6, y1 + 6.4, zf + 9.7), (door_x + 1.6, y1 + 7.4, zf + 10.0), 'lamp_green')
    room.box((door_x - 2.5, y1 - 0.5, zf + door_h + 0.55), (door_x + 2.5, y1 - 0.12, zf + door_h + 2.25), 'lamp_green')   # the sign's box
    SIGNS.append([[door_x, y1 - 0.55, zf + door_h + 1.4], 4.6, 1.5, '-y', 'EXIT', [10, 60, 24], [120, 255, 150], 'exit_green'])

    # one caged strip light on the ceiling in front of the door: the only lamp in the room
    lamp_y = y1 - 6.4
    room.box((door_x - 4.6, lamp_y - 0.9, zc - 0.5), (door_x + 4.6, lamp_y + 0.9, zc), 'steel')
    room.box((door_x - 4.3, lamp_y - 0.5, zc - 0.78), (door_x + 4.3, lamp_y + 0.5, zc - 0.5), 'lamp_on')
    for n in range(6):
        x = door_x - 4.4 + 8.8 * n / 5
        room.box((x - 0.06, lamp_y - 0.95, zc - 1.0), (x + 0.06, lamp_y + 0.95, zc - 0.5), 'steel')
    for y in (lamp_y - 0.9, lamp_y, lamp_y + 0.9):
        room.box((door_x - 4.5, y - 0.05, zc - 1.05), (door_x + 4.5, y + 0.05, zc - 0.95), 'steel')
    light('L6_ExitRoom_Lamp', (door_x, lamp_y, zc - 1.6), 'spot', 34, 1.05, 150, rgb=(176, 255, 190), energy=2500)
    light('L6_ExitRoom_Fill', ((x0 + x1) / 2, (y0 + y1) / 2 - 2.0, zf + 7.0), 'point', 26, 0.08, rgb=(150, 255, 170), energy=300)
    glow = Vector((EXIT['helix'][-1][0] + CX, EXIT['helix'][-1][1] + CY, 0.0)) + along * 7.4
    light('L6_ExitRoom_Tube', (glow.x, glow.y, zc + 2.6), 'point', 12, 1.9, rgb=(255, 44, 30), energy=600)

    # what the years left: a pad on the floor, dark stains, a few balls nobody came back for
    room.obox((x0 + 23.0, y0 + 3.6, zf + 0.4), (5.2, 3.8, 0.8), 17.0, 'yellow_dark')
    room.obox((x0 + 3.4, y0 + 9.0, zf + 0.35), (4.4, 0.7, 5.6), 82.0, 'navy_worn')        # one more, stood against the west wall
    for n in range(9):
        room.obox((x0 + 2.5 + dice.random() * (ROOM_W - 5.0), y0 + 2.5 + dice.random() * (ROOM_D - 5.0), zf + 0.03 + 0.012 * n),
                  (2.2 + dice.random() * 4.5, 1.4 + dice.random() * 3.0, 0.04), dice.random() * 180.0, 'stain')
    for n, (dx, dy) in enumerate(((4.0, 4.5), (25.5, 18.5), (20.0, 6.0), (9.5, 13.0), (27.0, 9.0))):
        room.ball((x0 + dx, y0 + dy, zf + 0.55), 0.55, ('red', 'yellow_dark', 'blue_worn', 'red', 'yellow_worn')[n])
    room.finish()
    anchor('L6_Anchor_HomeBase', (CX, CY, 3.0))
    anchor('L6_Anchor_EntitySpawn', (HOME_STAND[0], HOME_STAND[1], 3.0))
    anchor('L6_Anchor_Exit', (door_x, y1 + 6.0, zf + 3.0))            # in the passage: you are out when you are through the door
    anchor('L6_Anchor_ExitRoom', ((x0 + x1) / 2, (y0 + y1) / 2, zf + 3.0))
    anchor('L6_Anchor_PartyStage', (CX, CY + 9.0, 3.0))


def build_sound_and_signs():
    # PA horns round the court and out in the ring corridor: the Counter's voice comes from the five nearest
    for i in range(6):
        a = 30.0 + 60.0 * i
        x, y, _ = P(R[0] - 1.6, a)
        prop('pa_speaker', x, y, 34.0, a + 180.0, 4.2)
    for i in range(6):
        a = 60.0 * i
        if abs((a - 270 + 180) % 360 - 180) < 20:
            continue
        x, y, _ = P(R[RING] + 1.4, a)
        prop('pa_speaker', x, y, 44.0, a, 4.2)
        x, y, _ = P(R[RING] + 1.4, a + 30.0)
        prop('pa_speaker', x, y, 94.0, a + 30.0, 4.2)
    # the hidden button of the easter egg: on the floor of a dead end, three floors up
    spot = next((h for h in HIDE if h[0] == 'frame_nook' and 20 < h[3] < 32), HIDE[0])
    anchor('L6_Anchor_PartyButton', (spot[1], spot[2], spot[3] - 0.9))


# Freeze the pre-geometry navigation data; neither player aperture nor railwork
# authorizes adding a Counter route or moving an existing bridge node.
NAV_BEFORE_GEOMETRY = json.dumps([NODES, NODE_ID.keys().__repr__(), EDGES], sort_keys=True)


def verify_escape():
    assert len(ESCAPE_CUTS) == 2, 'cut exactly the lane net and its matching polar cell net'
    assert 6.0 <= ESCAPE_Y - gate_y <= 14.0
    assert ESCAPE_CELL in CELLS and kind(*ESCAPE_CELL) == 'cell'
    assert (ESCAPE_CELL[1], ESCAPE_CELL[2]) not in WELL_OF
    # Walk only ground-floor cell openings, never lane/court/stair/bridge links.
    ground = {c for c in CELLS if c[0] == 0}
    graph = {c: [] for c in ground}
    for pair in OPEN:
        a, b = tuple(pair)
        if a in ground and b in ground:
            graph[a].append(b)
            graph[b].append(a)
    reached, pending = {ESCAPE_CELL}, [ESCAPE_CELL]
    while pending:
        for other in graph[pending.pop()]:
            if other not in reached:
                reached.add(other)
                pending.append(other)
    assert reached == ground, 'escape cell must connect to the entire ground floor'
    assert json.dumps([NODES, NODE_ID.keys().__repr__(), EDGES], sort_keys=True) == NAV_BEFORE_GEOMETRY

    # Conservative bounding boxes over every exported primitive, including nets
    # (solid in the importer) and invisible slide/crawl-tube collision channels.
    # Test the full approach from the lane and the first six studs IN the cell.
    tilt = math.tan(math.radians(ESCAPE_ANGLE - 270.0))
    xa, xb = CX + LANE_HALF + 0.076, ESCAPE_X + ESCAPE_WIDTH / 2 * tilt + 6.0
    ya, yb = ESCAPE_Y - ESCAPE_WIDTH / 2, ESCAPE_Y + ESCAPE_WIDTH / 2
    za, zb = ftop(0) + 0.01, ftop(0) + ESCAPE_HEIGHT - 0.01
    for group, shape, d, mat in PRIMS:
        if shape in ('b', 'q'):
            points = [d[i:i + 3] for i in range(0, len(d), 3)]
            if shape == 'q':
                points.append([d[3 + i] + d[6 + i] - d[i] for i in range(3)])
            margin = 0.075 if shape == 'q' else 0.0
        elif shape == 'o':
            x, y, z, dx, dy, dz, yaw = d
            ca, sa = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
            points = [(x + a * ca - b * sa, y + a * sa + b * ca, z + c)
                      for a in (-dx / 2, dx / 2) for b in (-dy / 2, dy / 2) for c in (-dz / 2, dz / 2)]
            margin = 0.0
        elif shape in ('c', 't', 's'):
            points = [d[:3]] if shape == 's' else [d[:3], d[3:6]]
            margin = d[3] if shape == 's' else d[6]
            if shape == 't':
                margin = 1.5 * margin + 0.6
        elif shape == 'p':
            ra, rb, delta, split, angle, zc, thick = d
            points = [P(r, a, z) for r in (ra, rb) for a in (angle - delta / 2, angle, angle + delta / 2)
                      for z in (zc - thick / 2, zc + thick / 2)]
            margin = 0.0
        else:
            raise AssertionError(f'unchecked escape obstacle: {shape}')
        low = [min(q[i] for q in points) - margin for i in range(3)]
        high = [max(q[i] for q in points) + margin for i in range(3)]
        # Net thickness is perpendicular to a sheet, not beyond its Y/Z edges.
        # All sheets near this opening are upright; retain exact Y/Z cut edges.
        if shape == 'q' and mat.startswith('net_'):
            for i in (1, 2):
                low[i], high[i] = min(q[i] for q in points), max(q[i] for q in points)
        hit = all(high[i] > a + 1e-5 and low[i] < b - 1e-5
                  for i, (a, b) in enumerate(((xa, xb), (ya, yb), (za, zb))))
        assert not hit, f'escape approach / first six studs obstructed by {group} {shape} {d}'
    # At the far side of the clear area, the full width is on this cell's mat.
    for y in (ya, ESCAPE_Y, yb):
        x = xb
        radius = math.hypot(x - CX, y - CY)
        angle = math.degrees(math.atan2(y - CY, x - CX)) % 360
        a0, a1 = span(ESCAPE_CELL[1], ESCAPE_CELL[2])
        assert R[6] < radius < R[7] and a0 < angle < a1
    print('L6 ESCAPE', json.dumps({'side': 'right', 'lane_distance_from_gate': ESCAPE_Y - gate_y,
          'centre_xyz_model': [CX + LANE_HALF, ESCAPE_Y, ftop(0) + ESCAPE_HEIGHT / 2],
          'width': ESCAPE_WIDTH, 'height': ESCAPE_HEIGHT, 'cell_behind': list(ESCAPE_CELL),
          'ground_cells_reached': len(reached), 'cell_aperture_x': ESCAPE_X}))


gate_y = build_shell()
build_floors()
build_frame()
build_bridges()
build_slides()
panel_count = build_features()
light_count = build_lights()
build_finale()
build_sound_and_signs()
verify_escape()

hide_counts = {}
for kind_, x, y, z in HIDE:
    hide_counts[kind_] = hide_counts.get(kind_, 0) + 1
    anchor(f'L6_Hide_{kind_}_{hide_counts[kind_]:03d}', (x, y, z))


# ==========================================================================================
# the moulded slides and tubes (one mesh each, colour and gloss painted into the vertices)
# ==========================================================================================
def srgb_to_linear(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def gloss(rgb, a, inner):
    def bump(centre, width):
        d = (a - centre + 180) % 360 - 180
        return math.exp(-(d / width) ** 2)
    if inner:
        shade = 0.72 + 0.2 * max(0.0, -math.sin(math.radians(a)))
        white = 0.7 * bump(248, 9) + 0.3 * bump(300, 12)
    else:
        shade = 0.55 + 0.45 * (0.5 + 0.5 * math.sin(math.radians(a)))
        white = 0.9 * bump(64, 11) + 0.35 * bump(128, 16) + 0.18 * bump(20, 10)
    white = min(white, 0.92)
    lin = [srgb_to_linear(c) * shade for c in rgb]
    return (*[v + (1.0 - v) * white for v in lin], 1.0)


SLIDE_MAT = bpy.data.materials.new('L6_SlidePlastic')
SLIDE_MAT.use_nodes = True
_attr = SLIDE_MAT.node_tree.nodes.new('ShaderNodeVertexColor')
_attr.layer_name = 'Col'
_bsdf = next(n for n in SLIDE_MAT.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
SLIDE_MAT.node_tree.links.new(_attr.outputs['Color'], _bsdf.inputs['Base Color'])
_bsdf.inputs['Roughness'].default_value = 0.12


def with_bands(path, bands):
    """Add four close rings round each clamp band (given in studs from the end of the path): the two middle ones
    are the band itself. Returns the new path and the indices of the band rings."""
    if not bands:
        return path, set()
    back = [0.0] * len(path)
    for i in range(len(path) - 2, -1, -1):
        back[i] = back[i + 1] + (path[i + 1] - path[i]).length
    extra = {}
    for d in bands:
        i = max(j for j in range(len(path) - 1) if back[j] >= d)
        span = path[i + 1] - path[i]
        t = span.normalized()
        q = path[i] + t * min(max(back[i] - d, 0.62), span.length - 0.62)     # all four rings stay inside this stretch
        extra.setdefault(i, []).append([(q - t * 0.55, False), (q - t * 0.36, True), (q + t * 0.36, True), (q + t * 0.55, False)])
    out, marked = [], set()
    for i, q in enumerate(path):
        out.append(q)
        for group in extra.get(i, []):
            for point, is_band in group:
                if is_band:
                    marked.add(len(out))
                out.append(point)
    return out, marked


def moulded(name, points, r, rgb, wall=0.32, sides=20, step=2.4, resample=True, flare=(True, True), scoop=0, bands=(), dirt=0.0):
    """One moulded tube. scoop = how many rings at the end have their top cut back into an open lip; bands = clamp
    bands (studs from the end); dirt = how much grime is painted into it (0 = new plastic)."""
    path = smooth_path(points, step) if resample else [Vector(q) for q in points]
    path, banded = with_bands(path, bands)
    last = len(path) - 1
    bm = bmesh.new()
    tint, rings = {}, []
    for i, (q, (side, up)) in enumerate(zip(path, frames(path))):
        edge_ = min(i if flare[0] else 99, (last - i) if flare[1] else 99)
        widen = 1.0 + 0.2 * max(0.0, 1 - edge_ / 4.0) ** 2       # the mouth opens out like a trumpet
        outer, inner = [], []
        # the painted gloss follows the world's up, not the carried frame, so the highlight stays on top of the tube
        t = (path[min(i + 1, last)] - path[max(i - 1, 0)]).normalized()
        ref = Vector((0, 0, 1)) - t * t.z
        ref = ref.normalized() if ref.length > 0.2 else up
        lateral = t.cross(ref)
        # the lip: over the last rings everything above a falling line is folded down onto that line, which gives
        # the mouth one clean edge running from the full tube down to a scoop on the floor
        cut = 90.1 if last - i >= scoop else 90.0 - 100.0 * (1 - (last - i) / scoop) ** 0.8
        folded, hands, heights = [], [], []
        for k in range(sides):
            deg = 360.0 * k / sides
            d = math.cos(math.radians(deg)) * side + math.sin(math.radians(deg)) * up
            look = math.degrees(math.atan2(d.dot(ref), abs(d.dot(lateral))))
            hand = 1 if d.dot(lateral) >= 0 else -1
            folded.append(look > cut)
            hands.append(hand)
            heights.append(look)
            if look > cut:
                d = (math.cos(math.radians(cut)) * hand * lateral.normalized() + math.sin(math.radians(cut)) * ref).normalized()
                look = cut
            outer.append(bm.verts.new(q + d * (r * widen + wall + (0.3 if i in banded else 0.0))))
            inner.append(bm.verts.new(q + d * (r * widen)))
            grime = 1.0
            if dirt:
                blot = 0.5 + 0.25 * math.sin(1.3 * i + 0.9 * k) + 0.25 * math.sin(0.37 * i * k + 2.1 * k)
                low = max(0.0, -look / 90.0)                      # dirt gathers along the bottom
                grime = 1.0 - dirt * (0.3 + 0.5 * blot + 0.2 * low)
            for vert, is_inner in ((outer[-1], False), (inner[-1], True)):
                c = gloss(rgb, look, is_inner)
                if i in banded and not is_inner:
                    c = (0.035, 0.036, 0.04, 1.0)                 # the clamp band: dull dark steel
                # dirt also browns the plastic; a slide with none keeps exactly the colour it was painted
                tint[vert] = (c[0] * grime, c[1] * grime * 0.97, c[2] * grime * 0.82, 1.0) if dirt else c
        rings.append((outer, inner, folded, hands, heights))
    first_outer = None
    for (o0, i0, f0, h0, e0), (o1, i1, f1, h1, e1) in zip(rings, rings[1:]):
        for k in range(sides):
            k2 = (k + 1) % sides
            if f1[k] and f1[k2]:
                if f0[k] and f0[k2]:
                    continue                                       # all four lie on the fold: nothing there
                if h1[k] != h1[k2]:
                    continue                                       # straight over the top of the opening
                bm.faces.new((o0[k], o0[k2], o1[k]))               # the wall runs out to a point on the fold
                bm.faces.new((i0[k], i1[k], i0[k2]))
                continue
            face = bm.faces.new((o0[k], o0[k2], o1[k2], o1[k]))
            if first_outer is None:
                first_outer = face
            bm.faces.new((i0[k], i1[k], i1[k2], i0[k2]))
        for hand in (1, -1):                                       # the thickness of the plastic along the fold
            on1 = [k for k in range(sides) if f1[k] and h1[k] == hand]
            if not on1:
                continue
            on0 = [k for k in range(sides) if f0[k] and h0[k] == hand]
            k0 = on0[0] if on0 else max(range(sides), key=lambda k: e0[k])     # the fold starts at the top of a whole ring
            bm.faces.new((o0[k0], i0[k0], i1[on1[0]], o1[on1[0]]))
    for o, i, f, h, e in (rings[0], rings[-1]):
        for k in range(sides):
            k2 = (k + 1) % sides
            if f[k] and f[k2]:
                continue
            bm.faces.new((o[k], i[k], i[k2], o[k2]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    # an open lip leaves the shell open: make sure "outside" still means away from the tube's axis
    if (first_outer.calc_center_median() - (path[0] + path[1]) / 2).dot(first_outer.normal) < 0:
        bmesh.ops.reverse_faces(bm, faces=bm.faces)
    layer = bm.loops.layers.float_color.new('Col')
    for f in bm.faces:
        f.smooth = True
        for loop in f.loops:
            loop[layer] = tint[loop.vert]
    bm.verts.index_update()
    paint = [tint[v] for v in bm.verts]
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    me.materials.append(SLIDE_MAT)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    slide_col.objects.link(ob)
    xs, ys, zs = zip(*[tuple(v.co) for v in me.vertices])
    centre = ((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, (min(zs) + max(zs)) / 2)

    # the same mesh as plain numbers, for upload_arena_slides.py: Roblox axes (x, up, -y), relative to the centre
    def lin_to_srgb(v):
        v = max(0.0, min(1.0, v))
        return round(255 * (12.92 * v if v <= 0.0031308 else 1.055 * v ** (1 / 2.4) - 0.055))
    verts, normals, colours, tris = [], [], [], []
    for v, c in zip(me.vertices, paint):
        verts += [round((v.co.x - centre[0]) * 1000), round((v.co.z - centre[2]) * 1000), round(-(v.co.y - centre[1]) * 1000)]
        normals += [round(v.normal.x * 1000), round(v.normal.z * 1000), round(-v.normal.y * 1000)]
        colours += [lin_to_srgb(c[0]), lin_to_srgb(c[1]), lin_to_srgb(c[2])]
    for pl in me.polygons:
        idx = list(pl.vertices)
        for k in range(1, len(idx) - 1):
            tris += [idx[0], idx[k], idx[k + 1]]
    MESH_DATA[name] = {'verts': verts, 'normals': normals, 'colours': colours, 'tris': tris}
    return ob, centre, sum(len(pl.vertices) - 2 for pl in me.polygons)


MESH_CENTRE, MESH_DATA = {}, {}
for name, kind_, points, r, colour, arc, *more in SLIDES:
    ob, centre, tris = moulded(name, points, r, SLIDE_RGB[colour], **(more[0] if more else {}))
    MESH_CENTRE[name] = centre
    print('L6 SLIDE', name, colour, 'tris', tris)
SLIDE_ROWS = []
for name, centre, yaw in SLIDE_PLACES:
    c = centre if centre is not None else MESH_CENTRE[name]
    SLIDE_ROWS.append([name, [round(v, 3) for v in c], round(yaw, 3)])
(OUT / 'export').mkdir(parents=True, exist_ok=True)
(OUT / 'export' / 'slide_meshes.json').write_text(json.dumps(MESH_DATA, separators=(',', ':')))
bpy.ops.object.select_all(action='DESELECT')
for ob in slide_col.objects:
    if ob.type == 'MESH' and ob.name.startswith('arena_'):
        ob.select_set(True)
        ob.data.color_attributes.active_color = ob.data.color_attributes['Col']
        ob.data.color_attributes.render_color_index = 0
_kw = dict(filepath=str(OUT / 'export' / 'Level6ArenaSlides.glb'), export_format='GLB', use_selection=True, export_apply=True)
try:
    bpy.ops.export_scene.gltf(export_vertex_color='ACTIVE', export_all_vertex_colors=True, **_kw)
except TypeError:
    bpy.ops.export_scene.gltf(**_kw)

# ---- world, cameras, render ----------------------------------------------------------------
world = bpy.data.worlds.new('L6_World')
world.use_nodes = True
world.node_tree.nodes['Background'].inputs['Color'].default_value = (0.012, 0.014, 0.02, 1)
scene.world = world
cam_col = collection('L6_Cameras')
CAMERAS = {
    'court': ((CX + 30, CY - 34, 6.5), (CX - 6, CY + 30, 40), 14),
    'gallery': (P(52.0, 200.0, 26.0), P(10.0, 20.0, 4.0), 16),
    'high_gallery': (P(84.0, 160.0, 105.5), (CX, CY, 0.0), 16),
    'lane': ((CX, CY - 146, 6.0), (CX, CY, 24.0), 16),
    'tunnel': ((CX, CY - WALL_R - 30, 5.2), (CX, CY - 100, 9.0), 18),
    'aerial': ((CX + 120, CY - 330, 330), (CX, CY, 20), 26),
    'exit_room': ((EXIT_ROOM[0] + 6, CY - 6, EXIT_ROOM[4] + 5.5), (EXIT_ROOM[2], CY, EXIT_ROOM[4] + 5), 16),
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
scene.render.resolution_x, scene.render.resolution_y = 1280, 720
scene.view_settings.exposure = 1.6
try:
    scene.view_settings.view_transform = 'AgX'
    scene.view_settings.look = 'AgX - Medium High Contrast'
except (AttributeError, TypeError):
    pass

parts = {}
for row in PRIMS:
    parts[row[0]] = parts.get(row[0], 0) + (4 if row[1] == 't' else 1)
stats = {
    'layout': 'the Arena, concept v5', 'hall_radius': WALL_R, 'roof': ROOF_Z, 'floors': FLOORS, 'bands': R,
    'cells': len(CELLS), 'openings': len(OPEN), 'primitives': len(PRIMS), 'parts_in_studio': sum(parts.values()),
    'parts_by_group': dict(sorted(parts.items(), key=lambda kv: -kv[1])),
    'nav_nodes': len(NODES), 'nav_edges': len(EDGES), 'hide_spots': hide_counts, 'lights': len(LIGHTS),
    'bubble_panels': panel_count, 'slides': [s[0] for s in SLIDES],
}
(OUT / 'blend').mkdir(parents=True, exist_ok=True)
(OUT / 'build-stats.json').write_text(json.dumps(stats, indent=1))
(OUT / 'export' / 'prims.json').write_text(json.dumps({
    'prims': [[n, k, [round(float(v), 3) for v in d], m] for n, k, d, m in PRIMS],
    'empties': EMPTIES, 'lights': LIGHTS, 'signs': SIGNS, 'props': PROPS, 'slides': SLIDE_ROWS,
    'palette': {k: list(v) for k, v in PALETTE.items()},
}))
(OUT / 'export' / 'nav.json').write_text(json.dumps({
    'nodes': NODES, 'edges': EDGES, 'home': NODE_ID[('home',)],
    'cells': {f'{key[1]},{key[2]},{key[3]}': i for key, i in NODE_ID.items() if key[0] == 'c'},
    'open': [i for key, i in NODE_ID.items() if key[0] != 'c'],
    'radii': R, 'sectors': NSEC, 'floorHeight': H,
}))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / 'blend' / 'Level6_Arena.blend'))
print('L6 ARENA', json.dumps({k: stats[k] for k in ('cells', 'openings', 'primitives', 'parts_in_studio', 'nav_nodes', 'nav_edges', 'lights')}),
      json.dumps(hide_counts))
print('L6 GROUPS', json.dumps(stats['parts_by_group']))

argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
if '--render' in argv:
    only = [a.split('=', 1)[1] for a in argv if a.startswith('--only=')]
    (OUT / 'renders').mkdir(exist_ok=True)
    for label in CAMERAS:
        if only and label not in only[0].split(','):
            continue
        scene.camera = bpy.data.objects['L6_Cam_' + label]
        scene.render.filepath = str(OUT / 'renders' / f'arena_{label}.jpg')
        scene.render.image_settings.file_format = 'JPEG'
        scene.render.image_settings.quality = 88
        bpy.ops.render.render(write_still=True)
        print('L6 RENDER', label)
