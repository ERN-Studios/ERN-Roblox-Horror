"""Level 6 "Indoor Playground Backrooms" - deterministic Blender build.

Run headless:  Blender -b --python tools/level6_playground/build_playground.py -- [--render]
Coordinates are Roblox studs with Blender Z up (1 BU = 1 stud); no live place data is consumed.
The layout is fixed and follows concepts/10_map_overview.png: one hall, nine zones. The few seeded
choices (frame maze, staff corridors, stray balls) use fixed seeds, so every build gives the same map.
The earlier single-hall version is build_playground_v1_single_hall.py.
"""
import bpy, math, random, sys, json
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "artifacts" / "level6-playground-20261002"
SEED = 6
rng = random.Random(SEED)

# ---- dimensions (studs) ------------------------------------------------------------------
HALL_X, HALL_Y, HALL_Z = 600, 400, 46       # warehouse shell
TILE = 12                                   # foam puzzle-mat tile
C, H = 12, 10                               # play-frame cell and storey height
NX, NY, NZ = 22, 26, 3                      # play-frame cells; decks at z = 10 and 20, net roof at 30
SX, SY = 300, 44                            # play-frame south-west corner
POST_R, BEAM_R = 0.85, 0.5

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
    # the concept art's deep, dusty colours, a little more saturated on the owner's request (linear RGB)
    'yellow': (0.66, 0.38, 0.01), 'red': (0.40, 0.02, 0.015), 'blue': (0.015, 0.04, 0.30),
    'green': (0.025, 0.21, 0.04), 'purple': (0.13, 0.03, 0.23), 'pink': (0.56, 0.07, 0.21),
    'cyan': (0.02, 0.25, 0.38), 'orange': (0.64, 0.15, 0.01), 'navy': (0.008, 0.012, 0.075),
    # floor
    'mat_green': (0.055, 0.17, 0.05), 'mat_blue': (0.03, 0.055, 0.23), 'concrete': (0.20, 0.19, 0.17),
    # shell
    'wall_yellow': (0.42, 0.26, 0.02), 'wall_blue': (0.02, 0.05, 0.22), 'wall_red': (0.36, 0.03, 0.02),
    'wall_white': (0.42, 0.41, 0.37), 'deck': (0.16, 0.16, 0.16), 'steel': (0.10, 0.10, 0.105),
    'duct': (0.55, 0.56, 0.57), 'pipe_red': (0.45, 0.06, 0.05),
    # props
    'white': (0.82, 0.80, 0.75), 'black': (0.02, 0.02, 0.02), 'counter': (0.80, 0.24, 0.10),
    'stainless': (0.55, 0.56, 0.58), 'paper': (0.85, 0.83, 0.74), 'wood': (0.45, 0.30, 0.16),
    'lamp_off': (0.30, 0.30, 0.28),
    # zone floors and walls
    'floor_pink': (0.17, 0.05, 0.05), 'snack_a': (0.22, 0.05, 0.02), 'snack_b': (0.30, 0.22, 0.11),
    'floor_purple': (0.26, 0.21, 0.15), 'arcade_carpet': (0.06, 0.03, 0.13), 'arcade_carpet2': (0.14, 0.04, 0.20),
    'carpet': (0.20, 0.15, 0.08), 'wall_staff': (0.55, 0.42, 0.10), 'ceiling_tile': (0.45, 0.42, 0.32),
    'mat_pink': (0.50, 0.16, 0.24), 'mat_mint': (0.14, 0.40, 0.30), 'inflate_a': (0.055, 0.17, 0.05),
    'inflate_b': (0.03, 0.055, 0.23), 'wall_pink': (0.42, 0.13, 0.16), 'wall_purple': (0.12, 0.04, 0.20),
    'column': (0.55, 0.52, 0.42), 'room_wall': (0.62, 0.56, 0.46), 'ballsea': (0.5, 0.5, 0.5), 'plant': (0.06, 0.26, 0.08), 'pot': (0.36, 0.16, 0.08), 'glass': (0.55, 0.75, 0.85),
}
ROUGH = {'stainless': 0.3, 'duct': 0.4, 'steel': 0.55, 'deck': 0.6, 'concrete': 0.9}
VINYL = ['yellow', 'red', 'blue', 'green', 'purple', 'pink', 'cyan', 'orange']
FRAME_VINYL = ['yellow', 'red', 'blue', 'green', 'blue', 'red']   # the frame keeps to the four primaries, like the concept art
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
make_material('lamp_magenta', (1.0, 0.15, 0.75), emission=9.0)


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
TUBE_COLOURS = ['red', 'yellow', 'green', 'blue']
SLIDES = []      # every slide and crawl tube, for the moulded-plastic meshes: (kind, path, radius, colour, arc)
SLIDE_RGB = {'red': (214, 30, 22), 'yellow': (246, 188, 16), 'green': (36, 158, 58), 'blue': (26, 88, 214)}


class Builder:
    tubes = 0
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
        # owner: each tube is ONE solid colour (never striped, never black); the tubes differ from each other
        mats = TUBE_COLOURS[Builder.tubes % len(TUBE_COLOURS)]
        Builder.tubes += 1
        SLIDES.append(('tube', [tuple(q) for q in path], r, mats, (0.0, 360.0)))
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
# Layout: one hall, nine zones, following concepts/10_map_overview.png (north is up on the map)
# ==========================================================================================
shell_col = collection('L6_Shell')
lights_col = collection('L6_Lights')
zones_col = collection('L6_Zones')
frame_col = collection('L6_PlayFrame')

RECEPTION = (0, 0, 150, 108)        # bottom-left, behind the entrance doors
SNACK = (0, 132, 150, 288)          # left wall: counter, then picnic tables
PARTY = (0, 312, 174, 400)          # top-left block: corridor of birthday rooms
ARCADE = (186, 330, 330, 400)       # top wall
PRIZES = (330, 330, 432, 400)
STAFF = (444, 304, 600, 400)        # top-right block: Backrooms corridors, exit inside
BALL = (330, 12, 486, 120)          # Ball Ocean, below the frame
TODDLER = (168, 12, 312, 120)
INFLATE = (504, 12, 600, 288)       # right side
HOME = (236, 214)                   # where the child counts
ENTRANCE_X = (54, 78)               # main doors in the south wall
EXIT_X = (576, 588)                 # emergency exit in the north wall, inside STAFF
SIGNS, LIGHTS, HIDE = [], [], []
PROPS = []      # hero meshes from ReplicatedStorage.Level6PropKit: (name, x, y, z, yaw degrees, longest side, collide)
BOARDS = []     # textured panels: (centre, width, height, facing, texture key, self-lit)


def prop(name, x, y, z=0.35, yaw=0, size=10, collide=True):
    PROPS.append([name, x, y, z, yaw, size, 1 if collide else 0])


def board(pos, w, h, facing, tex, lit=False):
    BOARDS.append([list(pos), w, h, facing, tex, 1 if lit else 0])


def in_rect(x, y, r, pad=0):
    return r[0] - pad <= x <= r[2] + pad and r[1] - pad <= y <= r[3] + pad


def light(name, pos, kind='AREA', energy=9000, color=(1.0, 0.94, 0.82), size=(11, 3)):
    data = bpy.data.lights.new(name, kind)
    if kind == 'AREA':
        data.shape, data.size, data.size_y = 'RECTANGLE', size[0], size[1]
    data.energy, data.color = energy, color
    obj = bpy.data.objects.new(name, data)
    obj.location = pos
    lights_col.objects.link(obj)


SIGN_ART = {   # first words of the text -> (texture key, width / height)
    'FUN FACTORY': ('sign_playland', 3), 'SNACK SHACK': ('sign_snack', 3), 'ARCADE': ('sign_arcade', 3),
    'PRIZES': ('sign_prizes', 3), 'PARTY ROOMS': ('sign_party', 3), 'THE BIG FRAME': ('sign_frame', 3),
    'BALL OCEAN': ('sign_ball', 3), 'TODDLER TOWN': ('sign_toddler', 3), 'INFLATABLES': ('sign_inflatables', 3),
    'STAFF ONLY': ('sign_staff', 3), 'RECEPTION': ('sign_reception', 3), 'PLAY ZONE': ('sign_playzone', 3),
    'NO ADULTS': ('sign_noadults', 3), 'EXIT': ('sign_exit', 3), 'BIRTHDAYS': ('sign_birthdays', 3),
    'HOME BASE': ('sign_home', 1), "UNDER 5": ('sign_under5', 1), 'PLAY RULES': ('sign_rules', 2 / 3),
    'PARTY\nROOM': ('sign_partyroom', 2 / 3),
}


def sign(pos, w, h, facing, text, bg, fg):
    tex = ''
    for start, (key, aspect) in SIGN_ART.items():
        if text.startswith(start):
            tex = key
            if aspect >= 1:
                h = max(h, min(w / aspect, 7.5))
                w = h * aspect
            else:
                w = max(w, 3.2)
                h = w / aspect
            break
    SIGNS.append([list(pos), w, h, facing, text, list(bg), list(fg), tex])


def wall_run(b, a, c, height, mat, openings=(), t=1.5, z0=0):
    """Axis-aligned wall from a to c (x, y) with door openings [(start, end, door height)] along it."""
    (x0, y0), (x1, y1) = a, c
    along_x = abs(x1 - x0) >= abs(y1 - y0)
    lo, hi = (min(x0, x1), max(x0, x1)) if along_x else (min(y0, y1), max(y0, y1))
    fixed = y0 if along_x else x0

    def piece(s, e, za, zb):
        if e - s < 0.05 or zb - za < 0.05:
            return
        if along_x:
            b.box((s, fixed - t / 2, za), (e, fixed + t / 2, zb), mat)
        else:
            b.box((fixed - t / 2, s, za), (fixed + t / 2, e, zb), mat)

    cursor = lo
    for s, e, door in sorted(openings):
        piece(cursor, s, z0, height)
        piece(s, e, door, height)
        cursor = e
    piece(cursor, hi, z0, height)


# ---- floor ---------------------------------------------------------------------------------
MISSING_TILES = {(22, 20), (22, 21), (14, 13), (26, 25), (26, 26), (16, 24), (40, 26), (41, 26), (20, 11),
                 (13, 18), (23, 9), (24, 9), (27, 14), (15, 21)}          # torn-up patches in the open hall


def tile_surface(i, j):
    x, y = i * TILE + 6, j * TILE + 6
    alt = (i + j) % 2
    if in_rect(x, y, (0, 132, 60, 288)):
        return 'other', ('snack_a', 'snack_b')[alt]
    if in_rect(x, y, (PARTY[0], 340, PARTY[2], PARTY[3])):
        return 'other', 'floor_purple'
    if in_rect(x, y, ARCADE) or in_rect(x, y, PRIZES):
        return 'other', ('arcade_carpet', 'arcade_carpet2')[alt]
    if in_rect(x, y, STAFF):
        return 'other', 'carpet'
    if in_rect(x, y, BALL):
        return 'foam', 'navy'
    if in_rect(x, y, TODDLER):
        return 'foam', ('mat_pink', 'mat_mint')[alt]
    if in_rect(x, y, INFLATE):
        return 'foam', ('inflate_a', 'inflate_b')[alt]
    if (i, j) in MISSING_TILES:
        return None, None
    return 'foam', ('mat_blue', 'mat_green')[alt]


def build_floor():
    slab = Builder('Floor_Concrete', shell_col)
    slab.box((0, 0, -2), (HALL_X, HALL_Y, 0), 'concrete')
    slab.finish()
    foam, other = Builder('Floor_FoamTiles', shell_col), Builder('Floor_Other', shell_col)
    for i in range(HALL_X // TILE):
        for j in range(HALL_Y // TILE + 1):
            kind, mat = tile_surface(i, j)
            y0, y1 = j * TILE, min(j * TILE + TILE, HALL_Y)
            if kind and y1 > y0:
                (foam if kind == 'foam' else other).box((i * TILE, y0, 0), (i * TILE + TILE, y1, 0.35), mat)
    foam.finish()
    other.finish()


def build_walls():
    w = Builder('Walls', shell_col)
    band = 16

    def run(axis, fixed, colours, inward, openings=()):
        length = HALL_X if axis == 'x' else HALL_Y
        seg = length / len(colours)
        for k, (low, high) in enumerate(colours):
            a, b = k * seg, (k + 1) * seg
            for z0, z1, mat in ((0, band, low), (band, HALL_Z, high)):
                cuts = [(max(a, s), min(b, e), top) for s, e, top in openings if s < b and e > a and z0 == 0]
                if axis == 'x':
                    cursor = a
                    for s, e, top in cuts:
                        w.box((cursor, fixed, z0), (s, fixed + inward, z1), mat)
                        w.box((s, fixed, top), (e, fixed + inward, z1), mat)
                        cursor = e
                    w.box((cursor, fixed, z0), (b, fixed + inward, z1), mat)
                else:
                    w.box((fixed, a, z0), (fixed + inward, b, z1), mat)

    run('y', -2, [('wall_yellow', 'wall_yellow'), ('wall_yellow', 'wall_white'), ('wall_yellow', 'wall_yellow'),
                  ('wall_blue', 'wall_white')], 2)
    run('y', HALL_X, [('inflate_a', 'wall_white'), ('wall_blue', 'wall_white'), ('wall_yellow', 'wall_white'),
                      ('wall_staff', 'wall_white')], 2)
    run('x', -2, [('wall_yellow', 'wall_yellow'), ('wall_yellow', 'wall_white'), ('wall_blue', 'wall_white'),
                  ('wall_blue', 'wall_white'), ('inflate_a', 'wall_white')], 2,
        openings=[(ENTRANCE_X[0], ENTRANCE_X[1], 13)])
    run('x', HALL_Y, [('wall_blue', 'wall_blue'), ('wall_purple', 'wall_blue'), ('wall_purple', 'wall_red'),
                      ('wall_pink', 'wall_red'), ('wall_staff', 'wall_white')], 2,
        openings=[(EXIT_X[0], EXIT_X[1], 12)])
    for a, b in (((0, 0.2), (HALL_X, 0.2)), ((0, HALL_Y - 0.2), (HALL_X, HALL_Y - 0.2))):
        wall_run(w, a, b, 1.2, 'black', t=0.4, openings=[(ENTRANCE_X[0], ENTRANCE_X[1], 99)] if a[1] < 1 else
                 [(EXIT_X[0], EXIT_X[1], 99)])
    wall_run(w, (0.2, 0), (0.2, HALL_Y), 1.2, 'black', t=0.4)
    wall_run(w, (HALL_X - 0.2, 0), (HALL_X - 0.2, HALL_Y), 1.2, 'black', t=0.4)
    # the way in: glass doors that will not open again, and a mat
    w.box((ENTRANCE_X[0], -2.2, 0), (ENTRANCE_X[0] + 1, 0.2, 13), 'steel')
    w.box((ENTRANCE_X[1] - 1, -2.2, 0), (ENTRANCE_X[1], 0.2, 13), 'steel')
    w.box((ENTRANCE_X[0] + 11.5, -2.2, 0), (ENTRANCE_X[0] + 12.5, 0.2, 13), 'steel')
    w.box((ENTRANCE_X[0] + 1, -1.6, 0.4), (ENTRANCE_X[1] - 1, -1.2, 13), 'black')
    w.box((ENTRANCE_X[0] - 2, 1, 0.35), (ENTRANCE_X[1] + 2, 12, 0.55), 'black')
    # the way out: red emergency door at the end of the staff corridors
    w.box((EXIT_X[0], HALL_Y + 0.6, 0), (EXIT_X[1], HALL_Y + 1.4, 12), 'wall_red')
    w.box((EXIT_X[0] + 2, HALL_Y + 0.1, 5.4), (EXIT_X[1] - 2, HALL_Y + 0.6, 6.0), 'stainless')
    w.box((EXIT_X[0] + 3, HALL_Y - 1.2, 12.2), (EXIT_X[1] - 3, HALL_Y - 0.6, 13.0), 'exit_sign')
    w.finish()
    sign((66, 0.4, 16), 22, 3.5, '+y', 'FUN FACTORY PLAYLAND', (250, 205, 30), (200, 25, 25))
    sign((300, 399.0, 32), 120, 9, '-y', 'FUN FACTORY PLAYLAND', (250, 205, 30), (200, 25, 25))
    sign((0.9, 215, 30), 90, 7, '+x', 'BIRTHDAYS · PLAY · FUN!', (20, 50, 170), (255, 220, 40))


def build_ceiling():
    c = Builder('Ceiling_Structure', shell_col)
    c.box((0, 0, HALL_Z), (HALL_X, HALL_Y, HALL_Z + 1), 'deck')
    for x in range(0, HALL_X + 1, 12):
        c.box((x - 0.5, 0, HALL_Z - 0.6), (x + 0.5, HALL_Y, HALL_Z), 'deck')
    for gx in range(100, HALL_X, 100):
        c.box((gx - 1, 0, HALL_Z - 7), (gx + 1, HALL_Y, HALL_Z - 6.4), 'steel')
        c.box((gx - 0.3, 0, HALL_Z - 6.4), (gx + 0.3, HALL_Y, HALL_Z - 1.2), 'steel')
    for y in range(20, HALL_Y, 20):
        c.box((0, y - 0.5, HALL_Z - 1.1), (HALL_X, y + 0.5, HALL_Z - 0.6), 'steel')
        c.box((0, y - 0.5, HALL_Z - 5.0), (HALL_X, y + 0.5, HALL_Z - 4.5), 'steel')
        for x in range(0, HALL_X, 20):
            up = (x // 20) % 2 == 0
            c.cyl((x, y, HALL_Z - (4.6 if up else 1.0)), (x + 20, y, HALL_Z - (1.0 if up else 4.6)), 0.22, 'steel', 4)
    c.finish()
    m = Builder('Ceiling_Services', shell_col)
    for dy in (118, 296):
        m.cyl((10, dy, HALL_Z - 12), (HALL_X - 10, dy, HALL_Z - 12), 3.6, 'duct', 12, True)
        for x in range(40, HALL_X - 20, 70):
            m.cyl((x, dy, HALL_Z - 15.4), (x, dy, HALL_Z - 17.5), 2.2, 'duct', 8, True)
    for x in range(30, HALL_X, 60):
        m.cyl((x, 4, HALL_Z - 8.5), (x, HALL_Y - 4, HALL_Z - 8.5), 0.35, 'pipe_red', 5)
    m.finish()
    # twin-tube fluorescent fixtures on a regular grid; most still work, a few are dead
    fx = Builder('Ceiling_Fixtures', shell_col)
    n = 0
    for ix, x in enumerate(range(20, HALL_X, 40)):
        for iy, y in enumerate(range(20, HALL_Y, 40)):
            if in_rect(x, y, (PARTY[0], 340, PARTY[2], PARTY[3]), 2) or in_rect(x, y, STAFF, 2):
                continue                                   # those blocks have their own low ceilings
            z = HALL_Z - 9
            on = (ix * 7 + iy * 3) % 11 != 0
            fx.box((x - 5, y - 1.6, z), (x + 5, y + 1.6, z + 0.8), 'wall_white')
            for oy in (-0.8, 0.8):
                fx.box((x - 4.7, y + oy - 0.3, z - 0.25), (x + 4.7, y + oy + 0.3, z), 'lamp_on' if on else 'lamp_off')
            for ox in (-4, 4):
                fx.cyl((x + ox, y, z + 0.8), (x + ox, y, HALL_Z - 4.6), 0.08, 'steel', 3)
            if on:
                light(f'L6_Troffer_{n:03d}', (x, y, z - 0.4), energy=26000)
                n += 1
    fx.finish()
    # building columns: cream steel wrapped in safety padding up to head height, like the concept art
    col = Builder('Hall_Columns', shell_col)
    frame_rect = (SX - 6, SY - 6, SX + NX * C + 6, SY + NY * C + 6)
    n = 0
    for gx in range(100, HALL_X, 100):
        for gy in (60, 160, 260, 340):
            if any(in_rect(gx, gy, r, 4) for r in (frame_rect, PARTY, STAFF, ARCADE, PRIZES, BALL, TODDLER, (0, 132, 60, 288))):
                continue
            if abs(gx - HOME[0]) < 30 and abs(gy - HOME[1]) < 30:
                continue
            col.box((gx - 1.3, gy - 1.3, 0), (gx + 1.3, gy + 1.3, HALL_Z - 6), 'column')
            col.box((gx - 2.1, gy - 2.1, 0.35), (gx + 2.1, gy + 2.1, 10.5), 'yellow' if n % 3 else 'blue')
            n += 1
    col.finish()


# ==========================================================================================
# The Big Frame (centre-right) - a fixed three-storey soft-play maze
# ==========================================================================================
NX, NY, NZ = 12, 14, 3
SX, SY = 336, 128                # y 128..296: an 8-stud walkway is left before the staff block
ATRIUM = (4, 6, 8, 10)            # cells (i0, j0, i1, j1): open through all storeys
PUNCH = (1, 11, 3, 13)            # punch-bag forest on the ground
SPIRAL = (10, 1)
WEST_DOORS, EAST_DOORS = (2, 7, 12), (7,)
# (storey, cell, cell) bays left open so a slide, tube or bridge can be entered
PASSAGES = {
    (2, (3, -1), (3, 0)), (2, (9, -1), (9, 0)),             # tube slides south into Ball Ocean
    (2, (-1, 6), (0, 6)),                                   # red tube slide west into the hall
    (1, (6, -1), (6, 0)),                                   # open green slide into Ball Ocean
    (2, (8, 6), (9, 6)), (2, (8, 7), (9, 7)),               # top of the wave slide
    (1, (4, 5), (4, 6)), (1, (4, 10), (4, 11)),             # crawl tube, storey 1
    (2, (3, 10), (4, 10)), (2, (8, 10), (9, 10)),           # crawl tube, storey 2
    (2, (3, 8), (4, 8)), (2, (8, 8), (9, 8)),               # net bridge
    (2, (9, 1), (10, 1)),                                   # spiral slide entry
    (1, (2, 2), (3, 2)), (1, (7, 12), (8, 12)), (2, (5, 3), (6, 3)), (2, (1, 12), (2, 12)), (2, (10, 9), (11, 9)),  # roller squeezes
}
NO_STAIRS = {cell for _, a, b in PASSAGES for cell in (a, b)} | {SPIRAL}
# soft-step flights, fixed by hand: (storey, i, j), rising toward +x and landing on (i + 1, j)
STAIRS = {(0, 1, 1): True, (0, 6, 3): True, (0, 9, 8): True, (0, 2, 9): True, (0, 6, 13): True,
          (1, 2, 4): True, (1, 9, 4): True, (1, 1, 7): True, (1, 9, 12): True, (1, 5, 12): True}


def in_cells(i, j, r):
    return r[0] <= i <= r[2] and r[1] <= j <= r[3]


def void(k, i, j):
    return k >= 1 and ((i, j) == SPIRAL or in_cells(i, j, ATRIUM))


def stairwell(k, i, j):
    return k >= 1 and (k - 1, i, j) in STAIRS


def walkable(k, i, j):
    if not (0 <= i < NX and 0 <= j < NY and 0 <= k < NZ):
        return False
    return not void(k, i, j) and not stairwell(k, i, j)


def plan_maze():
    opened = set()
    for k in range(NZ):
        cells = [(i, j) for i in range(NX) for j in range(NY) if walkable(k, i, j)]
        seen = set()
        for start in cells:                                 # one spanning tree per connected island
            if start in seen:
                continue
            seen.add(start)
            stack = [start]
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
        extra = 0.45 if k == 0 else 0.28
        for i, j in cells:
            for a, b in ((i + 1, j), (i, j + 1)):
                if walkable(k, a, b) and rng.random() < extra:
                    opened.add((k, (i, j), (a, b)))
    return opened


OPENED = plan_maze()


def interface(k, a, b):
    (i, j), (p, q) = a, b
    if (k, min(a, b), max(a, b)) in PASSAGES:
        return 'none'
    inside_a, inside_b = 0 <= i < NX and 0 <= j < NY, 0 <= p < NX and 0 <= q < NY
    if not inside_a and not inside_b:
        return 'none'
    if not (inside_a and inside_b):
        ii, jj = (i, j) if inside_a else (p, q)
        if k == 0 and (i < 0 or p < 0) and jj in WEST_DOORS:
            return 'arch'
        if k == 0 and (i >= NX or p >= NX) and jj in EAST_DOORS:
            return 'arch'
        return 'net'
    for r in (ATRIUM, PUNCH):
        if in_cells(i, j, r) and in_cells(p, q, r) and k == 0:
            return 'open'
    va, vb = void(k, i, j), void(k, p, q)
    if va and vb:
        return 'none'
    if va or vb:
        return 'net'
    sa, sb = stairwell(k, i, j), stairwell(k, p, q)
    if sa or sb:
        (wi, wj), (oi, oj) = (a, b) if sa else (b, a)
        return 'open' if (oi, oj) == (wi + 1, wj) else 'net'
    if (k, i, j) in STAIRS or (k, p, q) in STAIRS:
        (ti, tj), (oi, oj) = (a, b) if (k, i, j) in STAIRS else (b, a)
        if (oi, oj) == (ti - 1, tj):
            return 'open'
        return 'panel' if (oi, oj) == (ti + 1, tj) else 'net'
    if (k, min(a, b), max(a, b)) in OPENED:
        return 'open'
    return 'panel' if rng.random() < 0.28 else 'net'


def build_frame():
    posts, beams = Builder('Frame_Posts', frame_col), Builder('Frame_Beams', frame_col)
    post_cols = ['yellow', 'yellow', 'green', 'red', 'yellow', 'blue']
    top = NZ * H
    for i in range(NX + 1):
        for j in range(NY + 1):
            if all(in_cells(a, b, ATRIUM) for a in (i - 1, i) for b in (j - 1, j)):
                continue
            x, y = SX + i * C, SY + j * C
            posts.cyl((x, y, 0), (x, y, top), POST_R, post_cols[(i // 4 + (j // 5) * 2) % len(post_cols)], 8)
            posts.cyl((x, y, 0), (x, y, 0.5), POST_R + 0.35, 'black', 8, True)
    posts.finish()
    beam_cols = ['green', 'red', 'blue', 'yellow']
    for k in range(1, NZ + 1):
        z = k * H
        for j in range(NY + 1):
            for i in range(NX):
                if k < NZ and all(void(k, i, b) for b in (j - 1, j) if 0 <= b < NY):
                    continue
                beams.cyl((SX + i * C, SY + j * C, z), (SX + (i + 1) * C, SY + j * C, z), BEAM_R, beam_cols[(j + k) % 4], 6)
        for i in range(NX + 1):
            for j in range(NY):
                if k < NZ and all(void(k, a, j) for a in (i - 1, i) if 0 <= a < NX):
                    continue
                beams.cyl((SX + i * C, SY + j * C, z), (SX + i * C, SY + (j + 1) * C, z), BEAM_R,
                          beam_cols[(i + k + 1) % 4], 6)
    beams.finish()
    decks = Builder('Frame_Decks', frame_col)
    for k in range(NZ):
        for i in range(NX):
            for j in range(NY):
                if k and (void(k, i, j) or stairwell(k, i, j)):
                    continue
                x, y, z = SX + i * C, SY + j * C, k * H
                mat = FRAME_VINYL[(i * 3 + j * 5 + k * 2) % len(FRAME_VINYL)] if (i * 7 + j * 3 + k) % 5 == 0 else ('navy', 'mat_blue')[(i + j) % 2]
                if k == 0:
                    decks.box((x + 0.15, y + 0.15, 0.35), (x + C - 0.15, y + C - 0.15, 0.95), mat)
                else:
                    decks.box((x + 0.3, y + 0.3, z - 0.35), (x + C - 0.3, y + C - 0.3, z + 0.35), mat)
    decks.finish()
    roof = Builder('Frame_RoofNet', frame_col)
    roof.face([(SX, SY, top), (SX + NX * C, SY, top), (SX + NX * C, SY + NY * C, top), (SX, SY + NY * C, top)], 'net_black')
    roof.finish()

    nets, pads = Builder('Frame_Nets', frame_col), Builder('Frame_Panels', frame_col)
    arches = Builder('Frame_Entrances', frame_col)

    def wall(kind, k, p0, p1):
        z = k * H
        (x0, y0), (x1, y1) = p0, p1
        along_x = abs(x1 - x0) > abs(y1 - y0)
        inset = POST_R + 0.1
        if along_x:
            x0, x1 = x0 + inset, x1 - inset
        else:
            y0, y1 = y0 + inset, y1 - inset
        zb, zt = z + (0.95 if k == 0 else 0.35), z + H - BEAM_R

        def net(za, zc, mat='net_blue'):
            nets.face([(x0, y0, za), (x1, y1, za), (x1, y1, zc), (x0, y0, zc)], mat)

        def pad(za, zc, mat, thick=0.9):
            if along_x:
                pads.box((x0, y0 - thick / 2, za), (x1, y0 + thick / 2, zc), mat)
            else:
                pads.box((x0 - thick / 2, y0, za), (x0 + thick / 2, y1, zc), mat)

        if kind == 'net':
            net(zb, zt, 'net_yellow' if (int(x0) + int(y0) + k) % 5 == 0 else 'net_blue')
        elif kind == 'panel':
            pad(zb, z + 5, FRAME_VINYL[(int(x0) // 12 + int(y0) // 12 + k) % len(FRAME_VINYL)])
            net(z + 5, zt)
        elif kind == 'arch':
            pad(z + 9.2, zt, 'red', 1.2)        # high enough for the 8.2-stud doll to walk in

    for k in range(NZ):
        for i in range(-1, NX):
            for j in range(NY):
                kind = interface(k, (i, j), (i + 1, j))
                if kind not in ('open', 'none'):
                    x = SX + (i + 1) * C
                    wall(kind, k, (x, SY + j * C), (x, SY + (j + 1) * C))
        for j in range(-1, NY):
            for i in range(NX):
                kind = interface(k, (i, j), (i, j + 1))
                if kind not in ('open', 'none'):
                    y = SY + (j + 1) * C
                    wall(kind, k, (SX + i * C, y), (SX + (i + 1) * C, y))
    nets.finish()
    pads.finish()
    arches.finish()
    for n, (j, k) in enumerate(((1, 1), (4, 2), (5, 1), (9, 2), (10, 1), (13, 2), (0, 2), (8, 1))):   # bubble-window panels on the hall side
        prop('tube_window_panel', SX - 0.7, SY + j * C + 6, z=k * H + 0.6, yaw=-90, size=8.6, collide=False)
    for n, (i, k) in enumerate(((1, 1), (4, 2), (7, 1), (10, 2))):                                      # and facing Ball Ocean
        prop('tube_window_panel', SX + i * C + 6, SY - 0.7, z=k * H + 0.6, yaw=180, size=8.6, collide=False)
    for j in WEST_DOORS:
        sign((SX - 0.8, SY + j * C + 6, 9.2), 10, 2.6, '-x', 'PLAY ZONE  ▶', (215, 30, 30), (255, 220, 40))
    sign((SX - 1.0, SY + NY * C / 2, 26), 46, 4.5, '-x', 'THE BIG FRAME', (255, 200, 20), (180, 20, 20))
    sign((SX - 1.0, SY + 30, 16.5), 34, 3, '-x', 'NO ADULTS ON UPPER LEVEL', (255, 255, 255), (180, 20, 20))

    s = Builder('Frame_SoftSteps', frame_col)
    for (k, i, j) in STAIRS:
        x, y = SX + i * C, SY + j * C
        z = k * H + (0.95 if k == 0 else 0.35)
        rise = (k + 1) * H + 0.35 - z
        for n in range(5):
            s.box((x + n * 2.4, y + 0.8, z), (x + (n + 1) * 2.4, y + C - 0.8, z + rise * (n + 1) / 5),
                  FRAME_VINYL[(n + i + j) % len(FRAME_VINYL)])
    s.finish()

    f = Builder('Frame_PlayFeatures', frame_col)
    rollers = Builder('Frame_Rollers', frame_col)
    n = 0
    for i in range(PUNCH[0], PUNCH[2] + 1):
        for j in range(PUNCH[1], PUNCH[3] + 1):
            for ox, oy in ((3.5, 4), (8.5, 8)):
                x, y = SX + i * C + ox, SY + j * C + oy
                f.cyl((x, y, 9.4), (x, y, 7.6), 0.07, 'black', 3)
                f.cyl((x, y, 7.6), (x, y, 2.2), 1.15, ('navy', 'red', 'blue', 'purple')[n % 4], 8, True)
                n += 1
            HIDE.append(('punchbag', SX + i * C + 6, SY + j * C + 6, 1))
    for k, i, j in ((1, 2, 2), (1, 7, 12), (2, 5, 3), (2, 1, 12), (2, 10, 9)):      # roller squeezes
        x, y, z = SX + (i + 1) * C, SY + j * C, k * H
        for m, zz in enumerate((2.0, 4.3, 6.6, 8.6)):
            rollers.cyl((x, y + 1, z + zz), (x, y + C - 1, z + zz), 1.05, FRAME_VINYL[(m + i) % len(FRAME_VINYL)], 8, True)
    rollers.finish()
    ax0, ay0 = SX + ATRIUM[0] * C, SY + ATRIUM[1] * C
    ax1, ay1 = SX + (ATRIUM[2] + 1) * C, SY + (ATRIUM[3] + 1) * C
    f.tube([(ax0 + 6, ay0 - 1, 13.2)] + [(ax0 + 6, ay0 + t, 13.2) for t in range(0, int(ay1 - ay0) + 1, 6)] +
           [(ax0 + 6, ay1 + 1, 13.2)], 2.9, ['red', 'yellow', 'blue', 'green'], 10)
    f.tube([(ax0 - 1, ay1 - 6, 23.2)] + [(ax0 + t, ay1 - 6, 23.2) for t in range(0, int(ax1 - ax0) + 1, 6)] +
           [(ax1 + 1, ay1 - 6, 23.2)], 2.9, ['blue', 'yellow', 'red', 'green'], 10)
    by = ay0 + 30
    f.box((ax0, by - 2.5, 19.65), (ax1, by + 2.5, 20.35), 'yellow')
    f.tube([(SX - 3.4, SY + t, 13.4) for t in range(18, 67, 6)], 3.0, ['blue', 'yellow', 'red', 'green'], 10)
    f.tube([(SX - 3.4, SY + t, 23.4) for t in range(96, 151, 6)], 3.0, ['red', 'blue', 'yellow'], 10)
    f.ball((SX - 3.4, SY + 16, 13.4), 3.3, 'yellow')
    f.ball((SX - 3.4, SY + 152, 23.4), 3.3, 'yellow')
    f.finish()
    HIDE.extend([('tube', ax0 + 6, ay0 + 30, 11.2), ('tube', ax0 + 30, ay1 - 6, 21.2), ('under_slide', ax1 - 14, ay0 + 12, 1)])
    bn = Builder('Frame_BridgeNets', frame_col)
    for side in (-2.5, 2.5):
        bn.face([(ax0, by + side, 20.35), (ax1, by + side, 20.35), (ax1, by + side, 26), (ax0, by + side, 26)], 'net_yellow')
    bn.finish()

    wave = Builder('Frame_WaveSlide', frame_col)
    sl = Builder('Frame_Slides', frame_col)
    y0, lane_w = ay0 + 5, 5.0                                          # triple wave slide into the atrium
    pts = []
    for n in range(0, 23):
        t = n / 22
        pts.append((ax1 - t * 52, max(20.3 - 19.2 * t + 1.1 * math.sin(t * math.pi * 3) * (1 - t), 1.0)))
    for lane in range(3):
        ya, yb = y0 + lane * lane_w, y0 + (lane + 1) * lane_w
        SLIDES.append(('chute', [(px, (ya + yb) / 2, pz) for px, pz in pts], 3.0, ('yellow', 'red', 'blue')[lane], (213.0, 327.0)))
        for (xa, za), (xb, zb) in zip(pts, pts[1:]):
            wave.face([(xa, ya, za), (xa, yb, za), (xb, yb, zb), (xb, ya, zb)], ('yellow', 'red', 'blue')[lane], True)
            for yy in (ya, yb):
                wave.face([(xa, yy, za), (xb, yy, zb), (xb, yy, zb + 1.3), (xa, yy, za + 1.3)], 'green')
    gx = SX + 6 * C + 1                                                # open green slide, storey 1 -> Ball Ocean
    gpts = [(SY + 0.5 - 30 * (n / 12), max(10.35 - 9.2 * (n / 12), 1.4)) for n in range(13)]
    SLIDES.append(('chute', [(gx + 5, py, pz) for py, pz in gpts], 6.0, 'green', (215.0, 325.0)))
    for (ya, za), (yb, zb) in zip(gpts, gpts[1:]):
        wave.face([(gx, ya, za), (gx + 10, ya, za), (gx + 10, yb, zb), (gx, yb, zb)], 'green', True)
        for xx in (gx, gx + 10):
            wave.face([(xx, ya, za), (xx, yb, zb), (xx, yb, zb + 1.4), (xx, ya, za + 1.4)], 'yellow')
    wave.finish()
    for ci, bend, cols in ((3, -1, ['blue', 'green', 'blue', 'yellow']), (9, 1, ['red', 'red', 'yellow'])):
        x = SX + ci * C + C / 2                                        # tube slides curling into Ball Ocean
        path = [(x, SY + 3, 23.3), (x, SY - 4, 23.0)]
        for n in range(1, 15):
            t = n / 14
            path.append((x + bend * 20 * math.sin(t * math.pi / 2) ** 2, SY - 4 - 44 * t, 23.0 - 19.2 * t ** 0.85))
        path.append((path[-1][0] + bend * 1.5, path[-1][1] - 6, 3.4))
        sl.tube(path, 3.1, cols, 12)
        for p in path[4::4]:
            sl.cyl((p[0], p[1], 0.35), (p[0], p[1], p[2] - 3.0), 0.35, 'steel', 5)
    wy = SY + 6 * C + C / 2                                            # the big red tube slide out into the hall
    path = [(SX + 3, wy, 23.3), (SX - 4, wy, 23.0)]
    for n in range(1, 13):
        t = n / 12
        path.append((SX - 4 - 40 * t, wy + 10 * math.sin(t * math.pi / 2) ** 2, 23.0 - 19.4 * t ** 0.85))
    path.append((path[-1][0] - 6, path[-1][1] + 1, 3.4))
    sl.tube(path, 3.2, ['red', 'red', 'yellow', 'red', 'blue'], 12)
    for q in path[4::4]:
        sl.cyl((q[0], q[1], 0.35), (q[0], q[1], q[2] - 3.1), 0.35, 'steel', 5)
    cx, cy = SX + SPIRAL[0] * C + C / 2, SY + SPIRAL[1] * C + C / 2      # spiral tube in its own shaft
    path = [(cx + 5.2 * math.cos(math.pi + a), cy + 5.2 * math.sin(math.pi + a), 23.4 - 20.2 * (a / (math.pi * 5)))
            for a in [n * math.pi / 8 for n in range(0, 41)]]
    path.append((path[-1][0] - 5, path[-1][1] - 5, 3.0))
    sl.tube(path, 2.7, ['blue', 'yellow', 'green', 'red'], 10)
    sl.cyl((cx, cy, 0.9), (cx, cy, 26), 0.6, 'steel', 8)
    sl.finish()

    lamps = Builder('Frame_Lamps', frame_col)
    for n, (i, j, k) in enumerate(((2, 2, 2), (6, 8, 2), (2, 12, 0), (10, 4, 1), (5, 13, 1), (10, 12, 2), (7, 1, 0))):
        x, y, z = SX + i * C + C / 2, SY + j * C + C / 2, (k + 1) * H - 1.2
        lamps.cbox((x, y, z + 0.4), (3.0, 1.0, 0.5), 'wall_white')
        lamps.cbox((x, y, z + 0.1), (2.6, 0.7, 0.14), 'lamp_warm' if n % 3 == 0 else 'lamp_on')
        light(f'L6_FrameLamp_{n}', (x, y, z - 0.6), 'POINT', 2600, (1.0, 0.86, 0.62))
    lamps.finish()
    for k in range(NZ):                                                 # dead ends make hiding nooks
        for i in range(NX):
            for j in range(NY):
                if not walkable(k, i, j) or in_cells(i, j, ATRIUM) or in_cells(i, j, PUNCH) or (k, i, j) in STAIRS:
                    continue
                exits = sum(1 for a, b in ((i + 1, j), (i - 1, j), (i, j + 1), (i, j - 1))
                            if walkable(k, a, b) and (k, min((i, j), (a, b)), max((i, j), (a, b))) in OPENED)
                if exits == 1:
                    HIDE.append(('frame_nook', SX + i * C + 6, SY + j * C + 6, k * H + 1))


# ==========================================================================================
# Zones
# ==========================================================================================
BALL_COLOURS = ('red', 'yellow', 'blue', 'green', 'orange')


def planter(b, x, y):
    prop('fake_plant', x, y, yaw=(x * 7 + y * 3) % 360, size=8.5, collide=False)


def picnic_table(b, x, y, top, along_x=True):
    w, d = (22, 7) if along_x else (7, 22)
    b.box((x, y, 3.4), (x + w, y + d, 3.9), top)
    legs = ((x + 2, y + 0.5, x + 3, y + d - 0.5), (x + w - 3, y + 0.5, x + w - 2, y + d - 0.5)) if along_x else \
        ((x + 0.5, y + 2, x + w - 0.5, y + 3), (x + 0.5, y + d - 3, x + w - 0.5, y + d - 2))
    for x0, y0, x1, y1 in legs:
        b.box((x0, y0, 0.35), (x1, y1, 3.4), 'black')
    for off in (-5, d + 2) if along_x else (-5, w + 2):
        if along_x:
            b.box((x, y + off, 2.0), (x + w, y + off + 3, 2.4), top)
            b.box((x + 2, y + off + 1, 0.35), (x + 3, y + off + 2, 2.0), 'black')
            b.box((x + w - 3, y + off + 1, 0.35), (x + w - 2, y + off + 2, 2.0), 'black')
        else:
            b.box((x + off, y, 2.0), (x + off + 3, y + d, 2.4), top)
            b.box((x + off + 1, y + 2, 0.35), (x + off + 2, y + 3, 2.0), 'black')
            b.box((x + off + 1, y + d - 3, 0.35), (x + off + 2, y + d - 2, 2.0), 'black')
    HIDE.append(('table', x + w / 2, y + d / 2, 0.6))


def playhouse(b, px, py, mat, roof, door='north'):
    """A plastic playhouse from the prop kit (10 x 10 footprint); still a hiding spot."""
    prop('playhouse', px + 5, py + 5, yaw=180 if door == 'south' else 0, size=11)
    HIDE.append(('playhouse', px + 5, py + 5, 1))


def build_reception():
    r = Builder('Reception', zones_col)
    x0, y0, x1, y1 = RECEPTION
    r.box((96, 30, 0.35), (132, 36, 4.6), 'blue')                    # L-shaped desk facing the doors
    r.box((94, 29, 4.6), (134, 37, 5.1), 'yellow')
    r.box((126, 36, 0.35), (132, 62, 4.6), 'blue')
    r.box((124, 36, 4.6), (134, 64, 5.1), 'yellow')
    r.box((104, 32, 5.1), (110, 35, 8.0), 'black')                   # till and monitor
    r.box((116, 31, 5.1), (121, 34, 6.2), 'stainless')
    for n in range(4):                                               # turnstiles between the desk and the hall
        y = 66 + n * 8
        r.box((128, y, 0.35), (133, y + 1.6, 4.6), 'stainless')
        if n < 3:
            r.cyl((130.5, y + 1.6, 3.6), (130.5, y + 6.2, 3.0), 0.22, 'stainless', 6)
            r.cyl((130.5, y + 1.6, 3.6), (132.5, y + 5.4, 4.4), 0.22, 'stainless', 6)
    for n in range(4):                                               # rope barrier to the desk
        x = 62 + n * 9
        r.cyl((x, 22, 0.35), (x, 22, 4.2), 0.35, 'stainless', 6, True)
        if n:
            r.cyl((x - 9, 22, 3.8), (x, 22, 3.8), 0.15, 'red', 4)
    sx0, sx1 = 6, 46                                                 # shoe cubbies on the west wall
    for row in range(6):
        r.box((1, sx0, row * 2.5 + 0.35), (5.5, sx1 + 46, row * 2.5 + 0.65), 'wood')
    for cy in range(sx0, sx1 + 47, 4):
        r.box((1, cy, 0.35), (5.5, cy + 0.3, 13.2), 'wood')
    for n, (cy, row) in enumerate(((10, 0), (18, 2), (26, 1), (38, 0), (46, 3), (58, 1), (66, 0), (74, 2), (82, 4), (30, 3))):
        r.box((2, cy + 0.7, row * 2.5 + 0.7), (4.6, cy + 2.9, row * 2.5 + 1.6),
              ('white', 'red', 'navy', 'pink', 'black')[n % 5])
    r.box((8, 10, 0.35), (12, 88, 2.4), 'red')                       # bench
    for px, py in ((20, 100), (140, 6), (140, 100)):
        planter(r, px, py)
    r.box((0.9, 96, 5), (1.2, 112, 13), 'paper')                     # rules board on the west wall
    r.finish()
    sign((113, 28.4, 3), 14, 2.4, '-y', 'RECEPTION', (255, 210, 30), (20, 40, 160))
    sign((1.3, 104, 9), 15, 7.4, '+x', 'PLAY RULES\n1. SOCKS ON\n2. NO RUNNING\n3. NO HIDING', (245, 240, 220), (30, 30, 30))
    light('L6_Reception_0', (75, 55, 46), energy=20000)
    HIDE.extend([('counter', 112, 44, 1), ('cubby_bench', 16, 50, 1)])


def build_snack_shack():
    s = Builder('SnackShack', zones_col)
    x0, y0, x1, y1 = 0, 150, 40, 270
    s.box((0, y0, 0), (1, y1, 24), 'wall_yellow')                    # back wall
    s.box((0, y0 - 2, 0), (x1, y0, 24), 'navy')                      # side returns
    s.box((0, y1, 0), (x1, y1 + 2, 24), 'navy')
    s.box((x1 - 2, y0 - 2, 15), (x1, y1 + 2, 24), 'navy')            # the fascia above the opening
    s.box((0, y0, 15), (x1 - 2, y1, 15.6), 'wall_white')             # ceiling of the bar
    for n in range(8):                                               # counter front: yellow and red panels
        ya = y0 + n * 15
        s.box((x1 - 5, ya, 0), (x1 - 3.4, ya + 15, 4.4), 'wall_yellow' if n % 3 else 'wall_red')
    s.box((x1 - 8, y0, 4.4), (x1 - 2.6, y1, 4.9), 'stainless')       # counter top
    s.box((2, y0 + 4, 0), (9, y1 - 4, 4.4), 'stainless')             # back counter
    s.box((2, y0 + 12, 4.4), (8, y0 + 24, 11), 'stainless')          # fridge
    s.box((2, y0 + 30, 4.4), (7, y0 + 37, 8), 'stainless')           # oven
    s.box((x1 - 7.5, y0 + 20, 4.9), (x1 - 4.5, y0 + 24, 7.2), 'black')   # till
    s.box((x1 - 7.5, y0 + 86, 4.9), (x1 - 4.5, y0 + 90, 6.4), 'red')     # napkin box
    prop('slush_machine', x1 - 6, y0 + 106, z=4.9, yaw=-90, size=5.5, collide=False)
    prop('slush_machine', 5, y0 + 72, z=4.4, yaw=-90, size=5.5, collide=False)
    for n, y in enumerate((y0 + 20, y0 + 60, y0 + 100)):
        s.box((10, y - 0.4, 15.1), (30, y + 0.4, 15.4), 'lamp_warm')     # tubes on the bar's ceiling
        light(f'L6_SnackBar_{n}', (20, y, 13.5), energy=9000, color=(1.0, 0.78, 0.40), size=(14, 9))
        board((1.65, y, 11.5), 26, 5.4, '+x', 'menu_boards', lit=True)
    s.cyl((x1 + 6, y1 - 6, 0.35), (x1 + 6, y1 - 6, 5.2), 2.0, 'black', 10, True)   # bin
    for px, py in ((46, 138), (46, 284), (144, 138), (144, 284)):
        planter(s, px, py)
    s.finish()
    t = Builder('PartyTables', zones_col)
    for n, ty in enumerate((146, 178, 210, 242)):
        picnic_table(t, 70, ty, ('red', 'blue')[n % 2])
        picnic_table(t, 108, ty + 8, ('blue', 'red')[n % 2])
    for px, py in ((76, 149), (84, 150.5), (116, 189), (90, 214), (120, 252), (126, 250)):   # a party never cleared
        t.cyl((px, py, 3.9), (px, py, 4.0), 1.1, 'paper', 8, True)
    t.finish()
    sign((x1 + 0.2, 210, 19.5), 60, 4.6, '+x', 'SNACK SHACK', (250, 205, 30), (200, 25, 25))
    HIDE.extend([('counter', 8, 176, 1), ('counter', 8, 244, 1)])


def build_party_rooms():
    p = Builder('PartyRooms', zones_col)
    x0, y0, x1, y1 = PARTY
    ceil = 16
    rooms = [(4, 42), (46, 84), (88, 126), (130, 170)]
    doors = [((a + b) / 2 - 4, (a + b) / 2 + 4, 10.5) for a, b in rooms]
    wall_run(p, (x0, 340), (x1, 340), 26, 'wall_blue', openings=doors)                # the long blue wall
    wall_run(p, (x1, 340), (x1, y1), ceil, 'wall_blue')
    p.box((x0, 340.75, ceil), (x1 + 0.75, y1, ceil + 0.8), 'wall_white')              # the rooms' ceiling
    for a, b in rooms[1:]:
        wall_run(p, (a - 2, 340.75), (a - 2, y1), ceil, 'room_wall')
    p.box((x0 + 0.1, 340.8, 0.35), (x0 + 0.5, y1, ceil), 'room_wall')
    p.box((x0, y1 - 0.6, 0.35), (x1, y1 - 0.2, ceil), 'room_wall')
    door_cols = ('wall_red', 'wall_yellow', 'wall_red', 'wall_yellow')
    for n, (a, b) in enumerate(rooms):
        mid = (a + b) / 2
        fx = mid - 14                                                                 # a second door, shut, per room
        for side in (-4.6, 4):                                                        # blue door frame
            p.box((mid + side, 338.9, 0.35), (mid + side + 0.6, 340, 11), 'blue')
        p.box((mid - 4.6, 338.9, 10.5), (mid + 4.6, 340, 11.1), 'blue')
        p.box((mid + 4, 331.2, 0.35), (mid + 4.6, 339, 10.3), door_cols[n])           # door standing open
        p.box((mid + 3.85, 331.2, 0.35), (mid + 4.0, 339, 1.5), 'stainless')               # kick plate and handle
        p.cyl((mid + 3.7, 332.4, 5.0), (mid + 3.7, 333.6, 5.0), 0.16, 'stainless', 6)
        p.box((fx - 3.6, 338.85, 0.35), (fx + 3.6, 339.0, 1.5), 'stainless')
        p.cyl((fx + 2.4, 338.8, 5.0), (fx + 3.3, 338.8, 5.0), 0.16, 'stainless', 6)
        p.box((fx - 1.2, 338.8, 6.2), (fx + 1.2, 338.98, 8.4), 'paper')                    # a notice taped to the shut door
        for k in range(9):                                                                # bunting across the room
            bx = a + 3 + k * (b - a - 6) / 8
            p.box((bx - 0.7, 352, 12.6 - abs(k - 4) * 0.25), (bx + 0.7, 352.15, 14.2 - abs(k - 4) * 0.25),
                  ('red', 'yellow', 'blue', 'green')[k % 4])
        p.cyl((a + 2, 352.07, 14.6), (b - 2, 352.07, 13.2), 0.05, 'white', 3)
        p.box((fx - 3.6, 339.0, 0.35), (fx + 3.6, 339.4, 10.3), door_cols[(n + 1) % 4])
        for side in (-4.2, 3.6):
            p.box((fx + side, 338.9, 0.35), (fx + side + 0.6, 340, 11), 'blue')
        p.box((fx - 4.2, 338.9, 10.5), (fx + 4.2, 340, 11.1), 'blue')
        p.box((mid + 6, 339.0, 5.4), (mid + 8.4, 339.25, 8.6), 'paper')
        p.box((mid - 9, 372, 3.4), (mid + 9, 380, 3.9), 'paper')                      # party table with a cloth
        p.box((mid - 8, 373, 0.35), (mid + 8, 379, 3.4), ('pink', 'cyan', 'yellow', 'pink')[n])
        for side in (368, 381.5):
            p.box((mid - 9, side, 0.35), (mid + 9, side + 2.5, 2.2), 'wood')
        for k in range(4):
            p.cyl((mid - 6 + k * 4, 376, 3.9), (mid - 6 + k * 4, 376, 4.0), 1.0, 'white', 8, True)
        p.cyl((mid, 376, 3.9), (mid, 376, 5.6), 1.6, ('pink', 'white', 'cyan', 'yellow')[n], 10, True)   # cake
        for k, (bx, by, bz) in enumerate(((a + 4, 396, 9), (b - 4, 396, 11), (mid, 397, 12.5))):
            p.ball((bx, by, bz), 1.5, ('red', 'yellow', 'blue', 'green')[(n + k) % 4])
            p.cyl((bx, by, 0.4), (bx, by, bz - 1.4), 0.05, 'white', 3)
        p.box((a + 2, y1 - 1.0, 12.4), (b - 2, y1 - 0.8, 13.6), ('pink', 'cyan', 'yellow', 'green')[n])   # banner
        p.box((mid - 5, 358, ceil - 0.5), (mid + 5, 362, ceil - 0.05), 'lamp_warm' if n != 2 else 'lamp_off')
        if n != 2:
            light(f'L6_PartyBlock_{n}', (mid, 360, ceil - 1.5), energy=7000, color=(1.0, 0.9, 0.75), size=(10, 4))
        board((mid, y1 - 0.75, 8.2), 15, 5, '-y', 'sign_birthdays')                      # banner on the back wall
        for k, (px, py, mat) in enumerate(((a + 5, 392, 'red'), (a + 8, 394, 'blue'), (b - 6, 391, 'yellow'), (b - 9, 394, 'green'))):
            p.box((px, py, 0.35), (px + 2.4, py + 2.4, 2.4 + (k % 2)), mat)                # presents
            p.box((px + 1.0, py - 0.02, 0.35), (px + 1.4, py + 2.42, 2.45 + (k % 2)), 'white')
        for k in range(6):                                                                # chairs pushed back from the table
            cx2 = mid - 7.5 + k * 3
            p.box((cx2, 365.5, 0.35), (cx2 + 2, 367.5, 2.2), ('red', 'blue', 'yellow')[k % 3])
            p.box((cx2, 365.5, 2.2), (cx2 + 2, 365.9, 4.6), ('red', 'blue', 'yellow')[k % 3])
        for k, (bx, by, bz) in enumerate(((a + 6, 356, 13.5), (b - 6, 358, 12.5), (mid - 5, 388, 13), (mid + 6, 386, 14))):
            p.ball((bx, by, bz), 1.5, ('pink', 'yellow', 'cyan', 'red')[(n + k) % 4])           # balloons on the ceiling
        HIDE.append(('table', mid, 376, 0.6))
        sign((mid + 7.2, 338.85, 7), 2.6, 3.2, '-y', f'PARTY\nROOM\n{n + 1}', (245, 240, 220), (30, 30, 30))
    for n, (bx, by, mat) in enumerate(((20, 334, 'red'), (58, 336, 'yellow'), (96, 333, 'blue'), (132, 335, 'green'),
                                       (150, 336, 'pink'), (70, 330, 'blue'), (112, 337, 'yellow'))):   # balloons gone soft
        p.ball((bx, by, 1.5), 1.2, mat)
    p.box((x0, 338.6, 0.35), (x1, 339.25, 1.3), 'navy')                              # skirting along the blue wall
    for n in range(14):                                                               # streamers and cups left on the floor
        sx, sy = 12 + n * 11.5, 330 + (n * 7) % 8
        p.box((sx, sy, 0.36), (sx + 3.2, sy + 0.35, 0.42), ('yellow', 'red', 'pink', 'cyan')[n % 4])
        if n % 3 == 0:
            p.cyl((sx + 5, sy + 2, 0.36), (sx + 5, sy + 2, 1.1), 0.4, 'paper', 6, True)
    p.finish()
    sign((84, 339.1, 19), 60, 3.6, '-y', 'PARTY ROOMS', (120, 60, 170), (255, 255, 255))


def cabinet(b, x, y, facing, mat, lit=False):
    """Arcade cabinet from the prop kit (about 6.6 studs tall); facing +1: the screen looks toward +y, -1 toward -y."""
    prop('arcade_cabinet_a' if mat in ('navy', 'purple', 'black', 'blue') else 'arcade_cabinet_b', x + 1.6, y + 1.8 * facing,
         yaw=180 if facing < 0 else 0, size=6.6)


def claw_machine(b, x, y, facing):
    """Claw machine from the kit, 7.2 studs tall, with the glass box the generated model lacks."""
    prop('claw_machine', x, y, yaw=90 if facing < 0 else -90, size=7.2)   # this model's front is its +x side; the importer adds the glass


def build_arcade():
    a = Builder('Arcade', zones_col)
    x0, y0, x1, y1 = ARCADE
    wall_run(a, (x0, y0), (x0, y1), 14, 'wall_purple', openings=[(346, 372, 14)])
    for n in range(17):                                              # cabinets along the north wall
        if n not in (15,):
            cabinet(a, x0 + 6 + n * 7.6, y1 - 1, -1, ('navy', 'red', 'purple', 'black', 'blue')[n % 5], lit=(n == 6))
    for n in range(9):                                               # island row, back to back
        cabinet(a, x0 + 28 + n * 8, 358, -1, ('purple', 'navy', 'red')[n % 3])
        cabinet(a, x0 + 28 + n * 8, 358, 1, ('black', 'purple', 'blue')[n % 3], lit=(n == 1))
    a.box((x0 + 100, 336, 0.35), (x0 + 122, 346, 3.6), 'navy')        # air hockey
    a.box((x0 + 101, 337, 3.6), (x0 + 121, 345, 3.9), 'white')
    claw_machine(a, x0 + 14, 342, 1)
    claw_machine(a, x0 + 21, 342, 1)
    claw_machine(a, x0 + 124, 396, -1)
    a.finish()
    light('L6_Arcade_0', (x0 + 77, y1 - 12, 9), 'POINT', 3500, (1.0, 0.2, 0.8))
    light('L6_Arcade_1', (x0 + 49, 366, 9), 'POINT', 2500, (1.0, 0.2, 0.8))
    sign((258, y1 - 0.9, 17), 64, 4.5, '-y', 'ARCADE', (40, 10, 70), (255, 60, 200))
    HIDE.extend([('counter', x0 + 16, 350, 1), ('counter', x0 + 111, 350, 1)])
    p = Builder('Prizes', zones_col)
    x0, y0, x1, y1 = PRIZES
    p.box((x0 + 8, 352, 0.35), (x1 - 8, 358, 4.6), 'pink')            # glass-fronted counter
    p.box((x0 + 7, 351, 4.6), (x1 - 7, 359, 5.0), 'yellow')
    p.box((x0 + 9, 351.6, 1), (x1 - 9, 352, 4.2), 'glass')
    board(((x0 + x1) / 2, y1 - 0.7, 8.6), x1 - x0 - 12, 13.5, '-y', 'prize_wall')
    wall_run(p, (x1, y0), (x1, y1), 14, 'wall_pink')
    p.finish()
    sign(((x0 + x1) / 2, y1 - 0.9, 17), 40, 4.5, '-y', 'PRIZES', (230, 90, 150), (255, 255, 255))
    HIDE.append(('counter', (x0 + x1) / 2, 364, 1))


STAFF_C, STAFF_NX, STAFF_NY = 12, 13, 8


def build_staff_only():
    s = Builder('StaffOnly', zones_col)
    x0, y0, x1, y1 = STAFF
    ceil = 13
    entry, exit_cell = (2, 0), ((EXIT_X[0] - x0) // STAFF_C, STAFF_NY - 1)
    maze = random.Random(66)                                         # fixed corridors: same every build
    opened, seen, stack = set(), {entry}, [entry]
    while stack:
        i, j = stack[-1]
        nbrs = [(a, b) for a, b in ((i + 1, j), (i - 1, j), (i, j + 1), (i, j - 1))
                if 0 <= a < STAFF_NX and 0 <= b < STAFF_NY and (a, b) not in seen]
        if not nbrs:
            stack.pop()
            continue
        nxt = maze.choice(nbrs)
        opened.add((min((i, j), nxt), max((i, j), nxt)))
        seen.add(nxt)
        stack.append(nxt)
    for extra in (((4, 3), (5, 3)), ((8, 2), (8, 3)), ((10, 5), (11, 5)), ((1, 5), (1, 6)), ((6, 6), (7, 6))):
        opened.add(extra)                                            # a few loops so it is not one long snake
    for j in range(0, STAFF_NY - 2):
        opened.add(((entry[0], j), (entry[0], j + 1)))               # the long corridor in from the door
    # The way in is on the west wall, facing the arcade and prize counter, in plain view from the hall
    # (owner, 2026-10-03: it used to sit in the narrow walkway behind the frame). The south wall is solid.
    door = (0, 1)                                                    # the cell behind the doorway
    dy0, dy1 = y0 + door[1] * STAFF_C + 1.5, y0 + door[1] * STAFF_C + 10.5
    opened.add(((0, 0), (0, 1)))
    opened.add(((0, 1), (1, 1)))                                     # straight on from the door ...
    opened.add(((1, 1), (2, 1)))                                     # ... into the long shelved corridor
    wall_run(s, (x0, y0), (x1, y0), ceil, 'wall_staff', t=1.2)
    wall_run(s, (x0, y0), (x0, y1), ceil, 'wall_staff', t=1.2, openings=[(dy0, dy1, 10.5)])
    for fy in (dy0 - 0.5, dy1):                                      # steel door frame
        s.box((x0 - 0.9, fy, 0.35), (x0 + 0.9, fy + 0.5, 10.9), 'steel')
    s.box((x0 - 0.9, dy0 - 0.5, 10.5), (x0 + 0.9, dy1 + 0.5, 10.9), 'steel')
    for i in range(STAFF_NX):
        for j in range(STAFF_NY):
            cx, cy = x0 + i * STAFF_C, y0 + j * STAFF_C
            if i + 1 < STAFF_NX and ((i, j), (i + 1, j)) not in opened:
                wall_run(s, (cx + STAFF_C, cy), (cx + STAFF_C, cy + STAFF_C), ceil, 'wall_staff', t=1.0)
            if j + 1 < STAFF_NY and ((i, j), (i, j + 1)) not in opened:
                wall_run(s, (cx, cy + STAFF_C), (cx + STAFF_C, cy + STAFF_C), ceil, 'wall_staff', t=1.0)
            lit = (i * 3 + j * 5) % 4 == 0 or (i == entry[0] and j % 2 == 0)
            if i == entry[0] and 1 <= j <= STAFF_NY - 2 and j != door[1]:   # shelving down the long corridor (not across the way in)
                for sx in ((cx + 0.7, cx + 2.7),) + (((cx + 9.3, cx + 11.3),) if j % 2 else ()):
                    for z in (0.5, 4.0, 7.5):
                        s.box((sx[0], cy + 1, z), (sx[1], cy + 11, z + 0.25), 'steel')
                    for yy in (cy + 1, cy + 10.7):
                        s.box((sx[0], yy, 0.35), (sx[1], yy + 0.3, 11), 'steel')
                    mid = (sx[0] + sx[1]) / 2
                    head = ('mascot_head_bear', 'mascot_head_dog', 'mascot_head_chicken')[j % 3]
                    prop(head, mid, cy + 3.2, z=7.75, yaw=90 if sx[0] < cx + 5 else -90, size=3.0, collide=False)
                    s.box((sx[0] + 0.2, cy + 6, 4.25), (sx[1] - 0.2, cy + 9.5, 6.4), ('blue', 'red', 'yellow', 'green')[j % 4])
                    s.box((sx[0] + 0.2, cy + 2, 0.75), (sx[1] - 0.2, cy + 5.5, 3.2), ('yellow', 'green', 'blue', 'red')[j % 4])
                    s.ball((mid, cy + 8, 1.6), 0.85, BALL_COLOURS[j % 5])
            s.box((cx + 3, cy + 4, ceil - 0.5), (cx + 9, cy + 8, ceil - 0.05), 'lamp_warm' if lit else 'lamp_off')
            if lit:
                light(f'L6_Staff_{i}_{j}', (cx + 6, cy + 6, ceil - 1.2), 'POINT', 1100, (1.0, 0.82, 0.45))
            exits = sum(1 for a, b in ((i + 1, j), (i - 1, j), (i, j + 1), (i, j - 1))
                        if (min((i, j), (a, b)), max((i, j), (a, b))) in opened)
            if exits == 1 and (i, j) not in (entry, exit_cell, door, (0, 0), (1, 1)):   # dead ends are storage
                kind = (i + j) % 4
                if kind == 0:                                        # stacked soft-play blocks
                    for n, mat in enumerate(('blue', 'yellow', 'red')):
                        s.box((cx + 2, cy + 2, 0.35 + n * 3), (cx + 6, cy + 6, 3.35 + n * 3), mat)
                    s.box((cx + 6.4, cy + 2, 0.35), (cx + 10, cy + 5.5, 3.2), 'green')
                elif kind == 1:                                      # shelf of mascot heads
                    s.box((cx + 1.5, cy + 8.5, 0.35), (cx + 10.5, cy + 11, 0.7), 'steel')
                    for z in (4, 8):
                        s.box((cx + 1.5, cy + 8.5, z), (cx + 10.5, cy + 11, z + 0.3), 'steel')
                    for n, head in enumerate(('mascot_head_bear', 'mascot_head_dog', 'mascot_head_chicken')):
                        prop(head, cx + 3 + n * 3, cy + 9.6, z=8.3, yaw=180, size=3.4, collide=False)
                elif kind == 2:                                      # bags of balls
                    prop('ball_bag', cx + 3, cy + 3, yaw=10, size=7.5)
                    prop('ball_bag', cx + 6.5, cy + 4, yaw=80, size=6.5)
                    prop('ball_bag', cx + 4.5, cy + 7.5, yaw=200, size=7)
                elif kind == 99:
                    for bx, by in ((cx + 3, cy + 3), (cx + 6.5, cy + 3.5), (cx + 4.5, cy + 7)):
                        s.cyl((bx, by, 0.35), (bx, by, 4.2), 1.7, 'paper', 8, True)
                        s.ball((bx, by, 4.6), 1.5, BALL_COLOURS[int(bx + by) % 5])
                else:                                                # mop bucket and folded nets
                    prop('mop_bucket', cx + 3.5, cy + 3.5, yaw=35, size=6, collide=False)
                    s.box((cx + 6, cy + 6, 0.35), (cx + 10, cy + 10, 1.6), 'navy')
                HIDE.append(('staff_nook', cx + 6, cy + 6, 1))
    s.box((x0 - 0.6, y0 - 0.6, ceil), (x1, y1, ceil + 0.8), 'ceiling_tile')
    ex = x0 + entry[0] * STAFF_C
    s.box((x0 - 8.6, dy1, 0.35), (x0 - 0.9, dy1 + 0.6, 10.3), 'steel')                # staff door left open, swung into the hall
    s.finish()
    sign((x0 - 1.0, (dy0 + dy1) / 2, 12.3), 9, 3, '-x', 'STAFF ONLY', (245, 240, 220), (180, 20, 20))   # on the door frame
    sign(((EXIT_X[0] + EXIT_X[1]) / 2, HALL_Y - 1.3, 12.6), 5.4, 0.9, '-y', 'EXIT', (200, 15, 10), (255, 245, 235))
    return ex + 6


def build_ball_ocean():
    b = Builder('BallOcean', zones_col)
    x0, y0, x1, y1 = BALL
    rim, top = 3.0, 4.2
    gaps_s = [(x0 + 60, x0 + 76)]                                     # way in from the hall side
    for a, c, openings in (((x0, y0), (x1, y0), gaps_s), ((x0, y1), (x1, y1), [(SX + 3 * C - 6, SX + 10 * C + 6)]),
                           ((x0, y0), (x0, y1), [(y0 + 40, y0 + 56)]), ((x1, y0), (x1, y1), [])):
        wall_run(b, a, c, top, 'blue', t=rim, z0=0.35, openings=[(s, e, top) for s, e in openings])
    for px, py in ((x0, y0), (x1, y0), (x0, y1), (x1, y1), ((x0 + x1) / 2, y0), (x0, (y0 + y1) / 2), (x1, (y0 + y1) / 2)):
        b.cyl((px, py, 0.35), (px, py, 16), 0.7, 'yellow', 8)
    for gx, gy in ((x0 + 60, y0 - 4), (x0 - 4, y0 + 40)):             # soft steps over the rim
        b.box((gx, gy, 0.35), (gx + 16, gy + 5, 1.6), 'yellow') if gy < y0 else b.box((gx, gy, 0.35), (gx + 5, gy + 16, 1.6), 'yellow')
    b.box((x0 + 30, y0 + 20, 0.35), (x0 + 46, y0 + 36, 3.4), 'red')    # two padded islands
    b.cyl((x1 - 40, y0 + 34, 0.35), (x1 - 40, y0 + 34, 2.8), 7, 'yellow', 12, True)
    b.finish()
    n = Builder('BallOcean_Nets', zones_col)
    for a, c in (((x0, y0), (x0 + 60, y0)), ((x0 + 76, y0), (x1, y0)), ((x1, y0), (x1, y1)), ((x0, y0 + 56), (x0, y1)),
                 ((x0, y0), (x0, y0 + 40))):
        n.face([(a[0], a[1], top), (c[0], c[1], top), (c[0], c[1], 16), (a[0], a[1], 16)], 'net_blue')
    n.finish()
    balls = Builder('BallOcean_Balls', zones_col)                     # owner: the pit is EMPTY, only a few loose balls on its floor
    spread = random.Random(7)
    for _ in range(64):
        balls.ball((spread.uniform(x0 + 5, x1 - 5), spread.uniform(y0 + 5, y1 - 5), 0.95), 0.6, spread.choice(BALL_COLOURS))
    for cx, cy in ((x0 + 8, y1 - 8), (x1 - 9, y0 + 9)):               # swept into two corners
        for _ in range(18):
            balls.ball((cx + spread.uniform(-5, 5), cy + spread.uniform(-5, 5), spread.uniform(0.95, 1.9)), 0.6,
                       spread.choice(BALL_COLOURS))
    balls.finish()
    sign(((x0 + x1) / 2, y0 - 1.7, 7.5), 34, 3.6, '-y', 'BALL OCEAN', (20, 60, 190), (255, 255, 255))
    HIDE.extend([('ballpit', x0 + 8, y1 - 8, 0.8), ('ballpit', x1 - 9, y0 + 9, 0.8), ('ballpit', x0 + 38, y0 + 42, 0.8),
                 ('ballpit', x1 - 40, y0 + 46, 0.8)])


def build_toddler_town():
    t = Builder('ToddlerTown', zones_col)
    x0, y0, x1, y1 = TODDLER
    cols = ('red', 'yellow', 'blue', 'green')
    n = 0
    for x in range(x0, x1, 6):                                       # low padded fence, gate on the north side
        for y in (y0, y1):
            if y == y1 and x0 + 60 <= x < x0 + 78:
                continue
            t.box((x, y - 0.7, 0.35), (x + 5.8, y + 0.7, 3.6), cols[n % 4])
            n += 1
    for y in range(y0, y1, 6):
        for x in (x0, x1):
            t.box((x - 0.7, y, 0.35), (x + 0.7, y + 5.8, 3.6), cols[n % 4])
            n += 1
    for n, (px, mat, roof) in enumerate(((x0 + 10, 'pink', 'blue'), (x0 + 30, 'cyan', 'red'), (x0 + 50, 'yellow', 'green'),
                                         (x0 + 96, 'purple', 'yellow'), (x0 + 116, 'orange', 'blue'))):
        playhouse(t, px, y1 - 22, mat, roof, door='south')          # the little street along the north fence
    t.box((x0 + 4, y0 + 2.4, 0.35), (x0 + 64, y0 + 3.6, 11), 'blue')  # painted farm-animal panel
    board((x0 + 34, y0 + 3.7, 5.9), 58, 10, '+y', 'animal_mural')
    for k in range(6):                                               # caterpillar crawl tunnel
        t.cyl((x0 + 22 + k * 5, y0 + 34, 2.9), (x0 + 26.6 + k * 5, y0 + 34, 2.9), 2.6, cols[k % 4], 10)
    t.ball((x0 + 19.5, y0 + 34, 3.2), 3.0, 'green')
    t.box((x0 + 70, y0 + 40, 0.35), (x0 + 78, y0 + 48, 4.4), 'yellow')   # soft shapes
    t.box((x0 + 78, y0 + 40, 0.35), (x0 + 86, y0 + 48, 2.4), 'blue')
    t.cyl((x0 + 104, y0 + 44, 0.35), (x0 + 104, y0 + 44, 5.0), 3.0, 'purple', 10, True)
    for cx, cy, mat in ((x0 + 60, y0 + 62, 'pink'), (x0 + 72, y0 + 66, 'cyan'), (x0 + 112, y0 + 62, 'orange')):   # rockers
        t.cbox((cx, cy, 1.9), (5.5, 2.2, 2.2), mat)
        t.cbox((cx + 2.8, cy, 3.3), (1.8, 1.8, 2.0), 'white')
    t.box((x0 + 112, y0 + 10, 0.35), (x0 + 136, y0 + 26, 2.6), 'cyan')   # mini ball pool rim
    t.box((x0 + 113.5, y0 + 11.5, 0.35), (x0 + 134.5, y0 + 24.5, 2.7), 'navy')
    t.finish()
    balls = Builder('Toddler_Balls', zones_col)
    spread = random.Random(11)
    for _ in range(14):
        balls.ball((spread.uniform(x0 + 115, x0 + 133), spread.uniform(y0 + 13, y0 + 23), 3.2), 0.55, spread.choice(BALL_COLOURS))
    balls.finish()
    sign((x0 + 69, y1 + 0.9, 7.6), 30, 3.2, '+y', 'TODDLER TOWN', (240, 130, 160), (255, 255, 255))
    sign((x0 + 8, y1 + 0.9, 6.5), 8, 4, '+y', "UNDER 5's\nONLY", (255, 210, 30), (20, 40, 160))
    HIDE.extend([('softblock', x0 + 36, y0 + 34, 1), ('toddler_pool', x0 + 124, y0 + 18, 1.2)])


def build_inflatables():
    f = Builder('Inflatables', zones_col)
    x0, y0, x1, y1 = INFLATE
    f.box((x0 + 2, 100, 0.35), (x0 + 8, 106, 0.6), 'navy')            # a stray landing mat
    f.finish()
    prop('bouncy_castle', 562, 262, yaw=90, size=40)
    prop('bouncy_castle', 566, 96, yaw=90, size=34)
    prop('inflatable_slide', 560, 196, yaw=90, size=34)
    prop('inflatable_slide', 568, 34, yaw=90, size=28)
    prop('deflated_castle', 548, 146, yaw=30, size=44, collide=False)  # the ones that have gone flat
    prop('deflated_castle', 524, 226, yaw=200, size=26, collide=False)
    prop('deflated_castle', 530, 60, yaw=100, size=30, collide=False)
    prop('inflatable_dino', 528, 180, yaw=-60, size=17)
    for bx, by, yaw in ((520, 34, 40), (522, 268, 140), (524, 120, 90), (518, 200, 20)):
        prop('blower_fan', bx, by, yaw=yaw, size=5)
    sign((x1 - 0.9, 150, 26), 60, 5, '-x', 'INFLATABLES', (120, 180, 70), (255, 255, 255))
    HIDE.extend([('inflatable', 573, 262, 3), ('inflatable', 552, 110, 1), ('softblock', 540, 214, 1)])


def build_home_base():
    h = Builder('HideAndSeek_Props', zones_col)
    hx, hy = HOME
    h.cyl((hx, hy, 0.35), (hx, hy, 0.8), 13, 'yellow', 20, True)
    h.cyl((hx, hy, 0.8), (hx, hy, 0.95), 9, 'white', 20, True)
    h.cyl((hx, hy, 0.95), (hx, hy, 16), 1.3, 'yellow', 10, True)
    for z in (4.0, 8.0, 12.0):
        h.cyl((hx, hy, z), (hx, hy, z + 0.25), 1.42, 'black', 10)
    h.cbox((hx, hy - 1.6, 11), (7, 0.4, 4.5), 'white')
    for n, (bx, by, along, mat) in enumerate(((hx - 34, hy + 22, True, 'blue'), (hx + 14, hy + 24, True, 'red'),
                                               (hx - 34, hy - 28, True, 'red'), (hx + 14, hy - 30, True, 'green'))):
        h.box((bx, by, 2.0), (bx + 20, by + 4, 2.5), mat)             # benches round the circle
        h.box((bx + 2, by + 1, 0.35), (bx + 3, by + 3, 2.0), 'steel')
        h.box((bx + 17, by + 1, 0.35), (bx + 18, by + 3, 2.0), 'steel')
    for px, py in ((hx - 22, hy), (hx + 22, hy), (hx, hy + 24), (hx, hy - 24)):
        planter(h, px, py)
    h.finish()
    sign((hx, hy - 1.95, 11), 6.6, 4.0, '-y', 'HOME BASE\n1, 2, 3 . . . 20', (245, 240, 220), (200, 30, 30))
    HIDE.append(('home', hx, hy - 4, 1))


def build_hall_litter():
    b = Builder('Hall_SoftBlocks', zones_col)
    spots = ((306, 250, 'yellow', 7, 4, 4), (318, 262, 'red', 5, 5, 3), (300, 180, 'blue', 4, 4, 8), (312, 150, 'green', 6, 4, 3),
             (500, 300, 'red', 5, 5, 5), (496, 150, 'yellow', 6, 4, 3), (180, 250, 'blue', 5, 5, 4), (268, 300, 'green', 7, 4, 3),
             (160, 150, 'red', 4, 4, 4), (404, 300, 'yellow', 6, 5, 3), (322, 300, 'blue', 4, 4, 4))
    for x, y, mat, w, d, h in spots:
        b.box((x, y, 0.35), (x + w, y + d, 0.35 + h), mat)
        HIDE.append(('softblock', x + w / 2, y + d + 2.5, 1))
    b.finish()
    balls = Builder('Hall_Balls', zones_col)
    spread = random.Random(21)
    n = 0
    while n < 90:
        x, y = spread.uniform(160, 596), spread.uniform(4, 320)
        if in_rect(x, y, BALL, 2) or in_rect(x, y, STAFF, 2) or in_rect(x, y, TODDLER, 2) or in_rect(x, y, (SX, SY, SX + NX * C, SY + NY * C)):
            continue
        balls.ball((x, y, 0.95), 0.6, spread.choice(BALL_COLOURS))
        n += 1
    balls.finish()


# ==========================================================================================
# Assemble
# ==========================================================================================
build_floor()
build_walls()
build_ceiling()
build_frame()
build_reception()
build_snack_shack()
build_party_rooms()
build_arcade()
staff_door_x = build_staff_only()
build_ball_ocean()
build_toddler_town()
build_inflatables()
build_home_base()
build_hall_litter()
pa = Builder('PA_Mounts', shell_col)
for hx in range(60, HALL_X, 120):
    for hy in (50, 150, 250, 330):
        if in_rect(hx, hy, (PARTY[0], 340, PARTY[2], PARTY[3]), 2) or in_rect(hx, hy, STAFF, 2):
            continue
        prop('pa_speaker', hx + 10, hy + 10, z=HALL_Z - 12.5, yaw=0, size=4.2, collide=False)
        pa.cyl((hx + 10, hy + 10, HALL_Z - 8.6), (hx + 10, hy + 10, HALL_Z - 4.6), 0.12, 'steel', 4)
prop('pa_speaker', STAFF[0] + 30, STAFF[1] + 40, z=8.6, yaw=0, size=3.2, collide=False)     # one in the staff corridors
prop('pa_speaker', 86, 372, z=11.4, yaw=0, size=3.2, collide=False)                         # and one in a party room
pa.finish()

# ---- slides as single moulded pieces --------------------------------------------------------------
import bmesh
slide_col = collection('L6_SlideMeshes')


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


def srgb_to_linear(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def gloss(rgb, a, inner):
    """Vertex colour for ring angle `a` (degrees, 90 = up): the plastic's colour with the long white highlights
    and the darker underside of a shiny moulded slide painted in, so it reads as glossy under any lighting."""
    def bump(centre, width):
        d = (a - centre + 180) % 360 - 180
        return math.exp(-(d / width) ** 2)
    if inner:      # the riding surface of a trough, or the inside of a tube mouth
        shade = 0.72 + 0.2 * max(0.0, -math.sin(math.radians(a)))
        white = 0.7 * bump(248, 9) + 0.3 * bump(300, 12)
    else:
        shade = 0.55 + 0.45 * (0.5 + 0.5 * math.sin(math.radians(a)))
        white = 0.9 * bump(64, 11) + 0.35 * bump(128, 16) + 0.18 * bump(20, 10)
    white = min(white, 0.92)
    lin = [srgb_to_linear(c) * shade for c in rgb]
    return (*[v + (1.0 - v) * white for v in lin], 1.0)


def moulded(name, kind, points, r, arc, rgb, wall=0.32, sides=32):
    path = smooth_path(points)
    closed = arc[1] - arc[0] >= 359.9
    steps = sides if closed else sides + 1
    bm = bmesh.new()
    tint = {}                                    # vertex -> painted colour
    rings = []                                   # per path point: (outer ring, inner ring)
    for i, q in enumerate(path):
        t = (path[min(i + 1, len(path) - 1)] - path[max(i - 1, 0)]).normalized()
        side = t.cross(Vector((0, 0, 1)))
        side = side.normalized() if side.length > 1e-4 else Vector((1, 0, 0))
        up = side.cross(t).normalized()
        flare = 1.0
        if closed and kind == 'tube':            # the mouth opens out like a trumpet at both ends
            edge = min(i, len(path) - 1 - i)
            flare = 1.0 + 0.2 * max(0.0, 1 - edge / 4.0) ** 2
        centre = q
        if not closed:                           # a trough: its bottom sits on the riding surface
            centre = q + up * (r - 0.12)
        outer, inner = [], []
        for k in range(steps):
            a = math.radians(arc[0] + (arc[1] - arc[0]) * k / sides)
            d = math.cos(a) * side + math.sin(a) * up
            deg = arc[0] + (arc[1] - arc[0]) * k / sides
            outer.append(bm.verts.new(centre + d * (r * flare + wall)))
            inner.append(bm.verts.new(centre + d * (r * flare)))
            tint[outer[-1]] = gloss(rgb, deg, False)
            tint[inner[-1]] = gloss(rgb, deg, True)
        rings.append((outer, inner))
    for (o0, i0), (o1, i1) in zip(rings, rings[1:]):
        for k in range(sides if closed else sides):
            k2 = (k + 1) % steps
            bm.faces.new((o0[k], o0[k2], o1[k2], o1[k]))
            bm.faces.new((i0[k], i1[k], i1[k2], i0[k2]))
        if not closed:                           # the two lips
            for k in (0, steps - 1):
                bm.faces.new((o0[k], o1[k], i1[k], i0[k]))
    for o, i in (rings[0], rings[-1]):           # wall thickness at both ends
        for k in range(sides if closed else sides):
            k2 = (k + 1) % steps
            bm.faces.new((o[k], i[k], i[k2], o[k2]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    layer = bm.loops.layers.float_color.new('Col')
    for f in bm.faces:
        f.smooth = True
        for loop in f.loops:
            loop[layer] = tint[loop.vert]
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    me.materials.append(SLIDE_MAT)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    slide_col.objects.link(ob)
    xs, ys, zs = zip(*[tuple(v.co) for v in me.vertices])
    centre = ((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, (min(zs) + max(zs)) / 2)
    size = (max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs))
    return ob, centre, size, sum(len(pl.vertices) - 2 for pl in me.polygons)


SLIDE_MAT = bpy.data.materials.new('L6_SlidePlastic')       # so the exporter writes the painted colours
SLIDE_MAT.use_nodes = True
_attr = SLIDE_MAT.node_tree.nodes.new('ShaderNodeVertexColor')
_attr.layer_name = 'Col'
_bsdf = next(n for n in SLIDE_MAT.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
SLIDE_MAT.node_tree.links.new(_attr.outputs['Color'], _bsdf.inputs['Base Color'])
_bsdf.inputs['Roughness'].default_value = 0.12
SLIDE_ROWS = []
for n, (kind, points, r, colour, arc) in enumerate(SLIDES):
    name = 'slide_%02d' % (n + 1)
    ob, centre, size, tris = moulded(name, kind, points, r, arc, SLIDE_RGB[colour])
    SLIDE_ROWS.append([name, [round(c, 3) for c in centre], [round(c, 3) for c in size], list(SLIDE_RGB[colour])])
    print('L6 SLIDE', name, kind, colour, 'tris', tris, 'size', [round(c, 1) for c in size])
(OUT / 'export').mkdir(exist_ok=True)
bpy.ops.object.select_all(action='DESELECT')
for ob in slide_col.objects:
    ob.select_set(True)
for ob in slide_col.objects:
    ob.data.color_attributes.active_color = ob.data.color_attributes['Col']
    ob.data.color_attributes.render_color_index = 0
_kw = dict(filepath=str(OUT / 'export' / 'Level6Slides.glb'), export_format='GLB', use_selection=True, export_apply=True)
try:
    bpy.ops.export_scene.gltf(export_vertex_color='ACTIVE', export_all_vertex_colors=True, **_kw)
except TypeError:
    bpy.ops.export_scene.gltf(**_kw)

anchors_col = collection('L6_Anchors')
for name, loc in (('Spawn', (66, 20, 3)), ('Exit', ((EXIT_X[0] + EXIT_X[1]) / 2, HALL_Y - 6, 3)),
                  ('EntitySpawn', (HOME[0], HOME[1] + 6, 3)), ('HomeBase', (HOME[0], HOME[1], 3))):
    empty = bpy.data.objects.new('L6_Anchor_' + name, None)
    empty.location = loc
    anchors_col.objects.link(empty)
hide_counts = {}
for kind, x, y, z in HIDE:
    hide_counts[kind] = hide_counts.get(kind, 0) + 1
    empty = bpy.data.objects.new(f'L6_Hide_{kind}_{hide_counts[kind]:02d}', None)
    empty.location = (x, y, z)
    empty.empty_display_type, empty.empty_display_size = 'SPHERE', 2
    anchors_col.objects.link(empty)

# ---- world, cameras, render ----------------------------------------------------------------
world = bpy.data.worlds.new('L6_World')
world.use_nodes = True
world.node_tree.nodes['Background'].inputs['Color'].default_value = (0.030, 0.034, 0.046, 1)
scene.world = world
cam_col = collection('L6_Cameras')
CAMERAS = {
    'overview': ((40, 30, 44), (430, 290, 2), 18),
    'reception': ((66, 14, 6.5), (120, 70, 7), 18),
    'home_base': ((170, 190, 7), (HOME[0], HOME[1], 7), 20),
    'big_frame': ((270, 210, 7), (400, 230, 14), 18),
    'ball_ocean': ((320, 30, 8), (430, 80, 4), 18),
    'toddler_town': ((240, 132, 8), (240, 60, 4), 18),
    'snack_shack': ((150, 250, 7), (20, 200, 8), 18),
    'party_rooms': ((166, 327, 6), (10, 327, 6), 18),
    'arcade': ((330, 344, 6.5), (200, 372, 6), 18),
    'staff_only': ((staff_door_x - 3, 308, 6), (staff_door_x + 20, 340, 5.5), 16),
    'inflatables': ((500, 180, 8), (556, 150, 10), 16),
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
scene.view_settings.exposure = 0.9
try:
    scene.eevee.shadow_pool_size = '1024'
    scene.view_settings.view_transform = 'AgX'
    scene.view_settings.look = 'AgX - Medium High Contrast'
except (AttributeError, TypeError):
    pass

stats = {
    'layout': 'v2 zoned map after concepts/10_map_overview.png', 'hall_studs': [HALL_X, HALL_Y, HALL_Z],
    'frame_cells': [NX, NY, NZ], 'primitives': len(PRIMS),
    'objects': sum(1 for o in bpy.data.objects if o.type == 'MESH'),
    'triangles': sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in bpy.data.objects if o.type == 'MESH'),
    'hide_spots': hide_counts, 'signs': len(SIGNS), 'authoring': 'Blender Z up, 1 BU = 1 Roblox stud',
}
(OUT / 'blend').mkdir(parents=True, exist_ok=True)
(OUT / 'export').mkdir(exist_ok=True)
(OUT / 'build-stats.json').write_text(json.dumps(stats, indent=1))
(OUT / 'export' / 'prims.json').write_text(json.dumps({
    'prims': [[n, k, [round(float(v), 3) for v in d], m] for n, k, d, m in PRIMS],
    'empties': [[o.name, [round(c, 3) for c in o.location]] for o in bpy.data.objects if o.type == 'EMPTY'],
    'lights': [[o.name, [round(c, 3) for c in o.location]] for o in bpy.data.objects if o.type == 'LIGHT'],
    'signs': SIGNS, 'props': PROPS, 'boards': BOARDS, 'slides': SLIDE_ROWS,
    'palette': {k: list(v) for k, v in PALETTE.items()},
}))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / 'blend' / 'Level6_IndoorPlayground.blend'))
print('L6 BUILD', json.dumps({k: stats[k] for k in ('objects', 'triangles', 'primitives', 'signs')}), json.dumps(hide_counts))

argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
if '--render' in argv:
    only = [a.split('=', 1)[1] for a in argv if a.startswith('--only=')]
    (OUT / 'renders').mkdir(exist_ok=True)
    for label in CAMERAS:
        if only and label not in only[0].split(','):
            continue
        scene.camera = bpy.data.objects['L6_Cam_' + label]
        scene.render.filepath = str(OUT / 'renders' / f'v2_{label}.jpg')
        scene.render.image_settings.file_format = 'JPEG'
        scene.render.image_settings.quality = 88
        bpy.ops.render.render(write_still=True)
        print('L6 RENDER', label)
