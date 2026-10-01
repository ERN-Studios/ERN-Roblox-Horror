# Level 4 facelift, package B: ceilings, light fixtures and the light language (r8.md B2.4 + the ceiling rows of A).
#
# exec() slots.py, then this file, then call build_ceilings(). Idempotent: everything lives in collection
# "L4 Ceilings" (plain meshes, pooled by export_l4.py) plus this package's lights in "L4 Fixture Lights"
# (obj["l4_pkg"] == "ceilings"); a re-run deletes and rebuilds both from the same seeds.
#
#   * Ceiling footprints are rasterised at 1 stud from l4_layout.json: the zone's ceiling parts, minus every visible
#     solid that reaches within 0.6 of the ceiling, minus the footprints of lower ceilings, flood-filled from seed
#     points so enclosed voids above masses get nothing.
#   * ACT: ring-free 4 x 2-stud panels, pooled quads, 4 x 2-stud louvred troffers on an 8-stud pitch.
#     Missing tiles and grilles are open; plenum follows the dilated room mask. Sagging tiles, ducts, joists,
#     wires and floor-verified broken shards dress the damage. Shards have no colliders. Stains use the decay
#     package's ceiling-ring decal; its fourteen roof-leak tiles are reserved before fixture/damage planning.
#   * Concourse: 4 elliptical drop coffers on the column pairs (magenta neon tube in the step reveal, cyan line on
#     the lower lip, one cove partly burnt out, cans inside), a black star deck in the nave, dark plum ACT with
#     brass drum fixtures and baffled cans in the aisles. Corridors: black deck + cans. Auditoria: black deck,
#     4 lighter stepped plaster bulkheads with low magenta/cyan PointLights on both faces and the same
#     magenta/cyan tubes, 6 hung acoustic clouds, one exposed duct on straps, cans. Arcade: dark ACT and a hung black bulkhead frame with
#     magenta/cyan tubes (it swallows the kept red flicker segment of the old frame). Restrooms, service (46.8),
#     vestibule, gallery (sickly green, long dark stretches), core and booths: ACT + troffers.
#   * Light language (owner, 2026-09-30): lit / dim / dark alternates. A low-frequency field per zone puts its
#     lowest DARK share of fixtures in dark stretches (grey dead lens, no light) and the next DIM share in dim ones
#     (darker lens, no light); 4 % more die at random; FLICKER (8 %) of all fixtures flicker, Poisson-spread.
#     A flicker lens is its own object: l4_prop = "FlickerLens", l4_attrs = {"OccasionalFlicker": true}, with a
#     POINT light on about a third, selected inside zone budgets. Other lenses still blink through the client.
#   * Lights (collection "L4 Fixture Lights"): POINT 1.5 studs below chosen troffers, SPOT per chosen can,
#     POINT for coves, frame, heat lamps and flicker lenses; l4_range (studs), l4_brightness, l4_shadows, l4_angle,
#     l4_color, l4_kind. Budget per zone (ZONES "lights"), shadows only on the "heroes" (~20 level-wide).
#   * Layout parts with OccasionalFlicker = "true" are never deleted (Studio clones them with their script); the
#     restroom fluorescents and the two auditorium ceiling squares get a housing around them instead.
#
# `python ceilings.py` (no Blender) runs the planner and asserts the counts.
import ast, collections, json, math, os, random, re
import numpy as np

try:
    import bpy
except ImportError:          # the planner and its self-check run in plain Python
    bpy = None

HERE = r"G:\Roblox\MongoTV\tools\level4_blender"
S, OX = 0.28, 23000.0

# Layout paths whose architecture objects this module deletes (parts with OccasionalFlicker = "true" are kept).
# The ceiling slabs are walls/floors to export_l4.py (<= 3 thick, >= 8 on both other axes), so their colliders stay.
REPLACES = [
    r"^Concourse/Downlight$",
    r"^Concession/Downlight$",
    r"^Concession/CounterWarmLight$",
    r"^A\d/A\d_CeilingLight$",
    r"^C\d/C\d_(CeilingLens|CeilingRecess|ReturnLight)$",
    r"^C\d/C\d_StairA\d(East|West)_Light$",
    r"^Service/(CagedServiceLamp|ServiceLampCage)$",
    r"^HiddenService/GalleryLamp$",
    r"^Shell/\w*Roof\w*$",
    r"^C\d/C\d_Roof$",
    r"^A\d/A\d_Roof$",
    r"^HiddenService/(Gallery|Core)Roof$",
    r"^Restrooms/(Men_LowerCeiling|Women_LowerCeiling|RestroomVestibuleCeiling)$",
    r"^Service/ServiceSuspendedCeiling$",
    r"^Arcade/ArcadeCeilingNeon$",
]

# Original preview lights whose fixture this module replaces (export_l4 leaves them out of legacyLights; the kept
# OccasionalFlicker parts carry their own lights in their Studio clones).
LIGHTS_SUPERSEDED = [
    r"^Concourse/Downlight/", r"^Concession/(Downlight|CounterWarmLight)/", r"^A\d/A\d_CeilingLight/",
    r"^C\d/C\d_(ReturnLight|CeilingLens|StairA\d(East|West)_Light)/", r"^Service/CagedServiceLamp/",
    r"^HiddenService/GalleryLamp/",
]

# sRGB light colours: 2700 K lobby, ~4000 K staff areas (reads cool next to 2700 K), sickly gallery fluorescent,
# synthwave neon (slots EMIT_MAGENTA / EMIT_CYAN)
LIGHT = {"warm": (255, 178, 108), "cool": (232, 240, 234), "sickly": (212, 236, 176), "magenta": (255, 40, 200),
         "cyan": (40, 230, 255), "amber": (255, 158, 84)}
BRIGHT = {"warm": 0.9, "cool": 1.1, "sickly": 0.7}
LIGHT_W = float(os.environ.get("L4C_LIGHT_W", 2500.0))   # shared Blender preview convention

# y = ceiling underside (studs); floor = typical floor under it (light range); lights = steady light budget;
# heroes = how many of those cast shadows; rect/roof give the raster window; seeds are points inside the room.
# dark / dim = share of the zone's fixtures in dark / dim stretches; clear = troffer clearance (studs).
ZONES = [
    dict(name="Concourse", y=60, kind="concourse", light="warm", floor=24, rect=(22622, 23378, -20, 102),
         seeds=[(22800, 50), (23200, 50), (22634, 50), (23000, 20)], tint="act_plum",
         lights=12, nave_lights=6, dark=0.2, dim=0.15),
    dict(name="Concession", y=52, kind="act", light="warm", floor=24, rect=(22879, 23121, 102, 240),
         seeds=[(23000, 140), (23000, 215)], lights=10, heroes=2, dark=0.1, dim=0.12),
    dict(name="Arcade", y=52, kind="act", light="warm", floor=24, rect=(23121, 23378, 102, 240),
         seeds=[(23192, 175)], tint="act_dark", dark=0.4, dim=0.25, missing=0.03, lights=1, heroes=1),
    dict(name="Service", y=46.8, kind="act", light="cool", floor=24, rect=(22622, 22879, 102, 240),
         seeds=[(22750, 170)], missing=0.03, plenum=5.2, lights=10, heroes=2, dark=0.18, dim=0.14),
    dict(name="RestroomMen", y=40.5, kind="act", light="cool", floor=24, rect=(23270, 23302, 126, 166),
         pitch=(3, 3), lights=1),
    dict(name="RestroomWomen", y=40.5, kind="act", light="cool", floor=24, rect=(23311, 23343, 126, 166),
         pitch=(3, 3), lights=1),
    dict(name="RestroomVestibule", y=41, kind="act", light="cool", floor=24, rect=(23270, 23343, 102, 124),
         pitch=(3, 3), lights=1),
] + [dict(name="C%d" % k, y=56, kind="deck", light="warm", floor=24, roof="C%d/C%d_Roof" % (k, k), lights=6,
          heroes=1, dark=0.36 if k == 3 else 0.12, dim=0.12) for k in (1, 2, 3, 4)] \
  + [dict(name="A%d" % k, y=104, kind="aud", light="warm", floor=56, roof="A%d/A%d_Roof" % (k, k), lights=3,
          heroes=2, dark=0.2, dim=0.15) for k in (1, 2, 3)] \
  + [dict(name="Booth%d" % k, y=98, kind="act", light="warm", floor=86, roof="A%d/A%d_BoothRoof" % (k, k),
          pitch=(3, 3), lights=1, missing=0, clear=1) for k in (1, 2, 3)] \
  + [dict(name="Gallery", y=99, kind="act", light="sickly", floor=86, roof="HiddenService/GalleryRoof",
          tint="act_mustard", dark=0.22, dim=0.18, lights=7, heroes=1),
     dict(name="Core", y=100, kind="act", light="cool", floor=86, roof="HiddenService/CoreRoof", lights=2)]

COFFERS = [(22720, 50), (22890, 50), (23110, 50), (23280, 50)]   # column pairs (x, mid z)
COFFER_AB = (32.0, 28.0)                                           # semi-axes (x, z)
COFFER_BURNT = (2, 3.6, 4.5)                                       # coffer index, cove arc (rad) whose tube is dead
COFFER_STEP = 3.0                                                  # width of the magenta step reveal
NAVE_CAN_ROWS = (38, 62)                                           # z of the nave can rows
NAVE = (26, 74)                                                    # concourse deck band (z)
FRAME_Y = 50.3                                                     # arcade frame underside (ceiling 52)
FLICKER, SPRINKLE = 0.08, 0.04     # flickering share of all fixtures; random dead outside the dark stretches
DARK, DIM = 0.12, 0.12             # default dark / dim stretch shares
STRETCH_MIN = 12                   # zones with fewer fixtures get no stretches


def _lens(state, lens_m):
    """Fixture state -> lens material key (a flicker lens is its own object)."""
    return {"lit": lens_m, "dim": lens_m + "_dim", "dead": "lens_dead", "flicker": None}[state]


# material key -> slot(name, tint)
MATS = {
    "act": ("ACT_2x4", None), "act_dark": ("ACT_2x4", (92, 86, 80)), "act_plum": ("ACT_2x4", (45, 30, 46)),
    "act_mustard": ("ACT_2x4", (186, 172, 126)),
    "act_stain": ("ACT_2x4", (182, 164, 130)), "act_back": ("CONCRETE_SEALED", (118, 110, 96)),
    "deck": ("DECK_BLACK", None), "plenum": ("DECK_BLACK", (10, 10, 10)),
    "frame": ("PORCELAIN", (214, 210, 198)), "lens_dead": ("PORCELAIN", (100, 97, 90)),
    "lens_warm": ("EMIT_WARM", LIGHT["warm"]), "lens_cool": ("EMIT_COOL", LIGHT["cool"]),
    "lens_sickly": ("EMIT_COOL", LIGHT["sickly"]), "lens_amber": ("EMIT_AMBER", None),
    "lens_warm_dim": ("EMIT_WARM", (122, 86, 54)), "lens_cool_dim": ("EMIT_COOL", (106, 110, 116)),
    "lens_sickly_dim": ("EMIT_COOL", (96, 110, 80)),
    "trim": ("CHROME_PITTED", None), "brass": ("BRASS_AGED", None), "baffle": ("PLASTIC_BLACK", None),
    "coffer": ("PLASTER_PEEL", (142, 116, 146)), "bulkhead": ("PLASTER_PEEL", (132, 110, 140)),
    "neon_m": ("EMIT_MAGENTA", None), "neon_c": ("EMIT_CYAN", None), "neon_dead": ("PORCELAIN", (74, 62, 76)),
    "cloud": ("VELOUR_SEAT", (40, 32, 50)), "cable": ("STEEL_PAINTED", None), "star": ("EMIT_WARM", (255, 236, 205)),
    "duct": ("CHROME_PITTED", (150, 150, 146)), "joist": ("STEEL_PAINTED", (60, 58, 56)),
    "tbar": ("PORCELAIN", (196, 192, 182)), "soffit": ("PLASTIC_BLACK", None), "cord": ("RUBBER_BLACK", None),
    "shade": ("BRASS_AGED", None),
}

# ---------------------------------------------------------------- layout
_L = json.load(open(os.path.join(HERE, "l4_layout.json")))
_P = _L["parts"]
# Read the authoritative dressing positions without importing/running the other package.
_decay_ast = ast.parse(open(os.path.join(HERE, "props_decay.py"), encoding="utf-8").read())
LEAKS = next(ast.literal_eval(n.value) for n in ast.walk(_decay_ast) if isinstance(n, ast.Assign)
             and any(isinstance(t, ast.Name) and t.id == "leaks" for t in n.targets))
_NAMES = [p["p"] for p in _P]
_ROT = np.array([p["cf"][3:] for p in _P], float).reshape(-1, 3, 3)
_EXT = np.einsum("nij,nj->ni", np.abs(_ROT), np.array([p["s"] for p in _P], float))
_CTR = np.array([p["cf"][:3] for p in _P], float)
_LO, _HI = _CTR - _EXT / 2, _CTR + _EXT / 2
_FLICK = {i for i, p in enumerate(_P) if (p.get("at") or {}).get("OccasionalFlicker") == "true"}
_REP = [re.compile(r) for r in REPLACES]
_CEIL = re.compile(r"^Shell/\w*Roof\w*$|^C\d/C\d_Roof$|^A\d/A\d_(Booth)?Roof$|^HiddenService/(Gallery|Core)Roof$"
                   r"|^Restrooms/(Men_LowerCeiling|Women_LowerCeiling|RestroomVestibuleCeiling)$"
                   r"|^Service/ServiceSuspendedCeiling$")
_CEIL_IDX = [i for i, n in enumerate(_NAMES) if _CEIL.search(n)]


def _replaced(path):
    return any(r.search(path) for r in _REP)


_OBST = np.array([p["t"] < 0.95 and p["m"] != "Neon" and not n.startswith("AutomaticDoors/") and not _replaced(n)
                  for p, n in zip(_P, _NAMES)]) & (np.minimum(_EXT[:, 0], _EXT[:, 2]) >= 0.25)
_OBST[_CEIL_IDX] = False
_KEPT = [i for i in sorted(_FLICK) if _CEIL.search(_NAMES[i]) is None]
_ARC_NEON = [i for i, n in enumerate(_NAMES) if n == "Arcade/ArcadeCeilingNeon"]


def _tile():
    sl = globals().get("SLOTS")
    return int(round((sl["ACT_2x4"][1] if sl else 1.232) / S / 2))   # short edge; each ACT panel is 2T x T


# ---------------------------------------------------------------- raster helpers (cell (r, c) = [z0+r, x0+c])
def _stamp(m, x0, z0, lo, hi, val, pad=0.0):
    a = max(0, math.ceil(lo[0] - pad - x0 - 0.5)); b = min(m.shape[1], math.floor(hi[0] + pad - x0 - 0.5) + 1)
    c = max(0, math.ceil(lo[2] - pad - z0 - 0.5)); d = min(m.shape[0], math.floor(hi[2] + pad - z0 - 0.5) + 1)
    if b > a and d > c:
        m[c:d, a:b] = val


def _erode(m, r):
    if r <= 0:
        return m.copy()
    k = 2 * r + 1
    ii = np.pad(np.pad(m.astype(np.int32), r).cumsum(0).cumsum(1), ((1, 0), (1, 0)))
    return (ii[k:, k:] - ii[:-k, k:] - ii[k:, :-k] + ii[:-k, :-k]) == k * k


def _dilate(m, r):
    return ~_erode(~np.pad(m, r, constant_values=False), r)[r:-r, r:-r]


def _footprint(m, x0, z0, i, val):
    """Rasterise a box in its local axes; diagonal fascias must not erase their whole AABB."""
    if np.all(np.max(np.abs(_ROT[i]), axis=0) > .999):
        _stamp(m, x0, z0, _LO[i], _HI[i], val)
        return
    c0 = max(0, math.floor(_LO[i, 0] - x0 - 1)); c1 = min(m.shape[1], math.ceil(_HI[i, 0] - x0 + 1))
    r0 = max(0, math.floor(_LO[i, 2] - z0 - 1)); r1 = min(m.shape[0], math.ceil(_HI[i, 2] - z0 + 1))
    zz, xx = np.mgrid[r0:r1, c0:c1]
    dx, dz = xx + x0 + .5 - _CTR[i, 0], zz + z0 + .5 - _CTR[i, 2]
    inside = np.ones(dx.shape, bool)
    for a in (0, 2):
        inside &= np.abs(dx * _ROT[i, 0, a] + dz * _ROT[i, 2, a]) <= _P[i]["s"][a] / 2 + .5
    m[r0:r1, c0:c1][inside] = val


def _flood(free, seeds):
    H, W = free.shape
    out = np.zeros_like(free)
    q = collections.deque()
    for r, c in seeds:
        near = [(abs(rr - r) + abs(cc - c), rr, cc) for rr in range(max(0, r - 4), min(H, r + 5))
                for cc in range(max(0, c - 4), min(W, c + 5)) if free[rr, cc]]
        if near:
            _, rr, cc = min(near)
            out[rr, cc] = True
            q.append((rr, cc))
    while q:
        r, c = q.popleft()
        for rr, cc in ((r + 1, c), (r - 1, c), (r, c + 1), (r, c - 1)):
            if 0 <= rr < H and 0 <= cc < W and free[rr, cc] and not out[rr, cc]:
                out[rr, cc] = True
                q.append((rr, cc))
    return out


def _rects(m):
    """Greedy merge of a bool grid -> [(c0, c1, r0, r1)] (runs per row, merged down while identical)."""
    H = m.shape[0]
    out, act = [], {}
    for r in range(H + 1):
        runs = set()
        if r < H:
            d = np.diff(np.concatenate(([0], m[r].astype(np.int8), [0])))
            runs = set(zip(np.nonzero(d == 1)[0].tolist(), np.nonzero(d == -1)[0].tolist()))
        for k in list(act):
            if k not in runs:
                out.append((k[0], k[1], act.pop(k), r))
        for k in runs:
            act.setdefault(k, r)
    return out


def _zone_mask(z):
    x0, x1, z0, z1 = z["rect"]
    y = z["y"]
    m = np.zeros((z1 - z0, x1 - x0), bool)
    for i in _CEIL_IDX:
        if abs(_LO[i, 1] - y) < 0.06:
            _stamp(m, x0, z0, _LO[i], _HI[i], True)
    band = _OBST & (_HI[:, 1] > y - 0.6) & (_LO[:, 1] < y - 0.05) & (_HI[:, 0] > x0) & (_LO[:, 0] < x1) \
        & (_HI[:, 2] > z0) & (_LO[:, 2] < z1)
    for j in np.nonzero(band)[0]:
        _footprint(m, x0, z0, j, False)
    for k in _CEIL_IDX:                         # lower ceilings claim their cells first
        if y - 13 < _HI[k, 1] <= y + 0.01 and _LO[k, 1] < y - 0.01:
            _stamp(m, x0, z0, _LO[k], _HI[k], False)
    return _flood(m, [(int(sz - z0), int(sx - x0)) for sx, sz in z["seeds"]])


# ---------------------------------------------------------------- mesh builder (Studio studs, Y up)
def _newell(P):
    nx = ny = nz = 0.0
    for i in range(len(P)):
        (x1, y1, z1), (x2, y2, z2) = P[i], P[(i + 1) % len(P)]
        nx += (y1 - y2) * (z1 + z2); ny += (z1 - z2) * (x1 + x2); nz += (x1 - x2) * (y1 + y2)
    return nx, ny, nz


class _MB:
    def __init__(self):
        self.V, self.F, self.M, self.SM, self.mats = [], [], [], [], []

    def v(self, p):
        self.V.append(tuple(p))
        return len(self.V) - 1

    def f(self, idx, m, want, smooth=False):
        n = _newell([self.V[i] for i in idx])
        if n[0] * want[0] + n[1] * want[1] + n[2] * want[2] < 0:
            idx = idx[::-1]
        if m not in self.mats:
            self.mats.append(m)
        self.F.append(list(idx)); self.M.append(self.mats.index(m)); self.SM.append(smooth)

    def poly(self, pts, m, want, smooth=False):
        self.f([self.v(p) for p in pts], m, want, smooth)

    def hquad(self, x0, x1, z0, z1, y, m, up=False):
        self.poly([(x0, y, z0), (x1, y, z0), (x1, y, z1), (x0, y, z1)], m, (0, 1 if up else -1, 0))

    def box(self, lo, hi, m, skip=()):
        (a, b, c), (d, e, g) = lo, hi
        F = {"-y": ([(a, b, c), (d, b, c), (d, b, g), (a, b, g)], (0, -1, 0)),
             "+y": ([(a, e, c), (d, e, c), (d, e, g), (a, e, g)], (0, 1, 0)),
             "-x": ([(a, b, c), (a, e, c), (a, e, g), (a, b, g)], (-1, 0, 0)),
             "+x": ([(d, b, c), (d, e, c), (d, e, g), (d, b, g)], (1, 0, 0)),
             "-z": ([(a, b, c), (d, b, c), (d, e, c), (a, e, c)], (0, 0, -1)),
             "+z": ([(a, b, g), (d, b, g), (d, e, g), (a, e, g)], (0, 0, 1))}
        for k, (pts, w) in F.items():
            if k not in skip:
                self.poly(pts, m, w)

    def ring_band(self, pts_a, pts_b, m, want_fn, smooth=True):
        """Quads between two closed loops of vertex indices; want_fn(i) -> desired normal."""
        n = len(pts_a)
        for i in range(n):
            j = (i + 1) % n
            self.f([pts_a[i], pts_a[j], pts_b[j], pts_b[i]], m, want_fn(i), smooth)

    def tris(self):
        return sum(len(f) - 2 for f in self.F)


def _circle(n, r, x, z):
    return [(x + r * math.cos(2 * math.pi * k / n), z + r * math.sin(2 * math.pi * k / n)) for k in range(n)]


def _can(mb, x, ys, z, r, trim, lens, seg=10):
    """Trim, black ribbed baffle and a small visible lamp inside the recess."""
    ri, yb, yl = 0.72 * r, ys - 0.42, ys - 0.12
    o_top = [mb.v((px, ys, pz)) for px, pz in _circle(seg, r, x, z)]
    o_bot = [mb.v((px, yb, pz)) for px, pz in _circle(seg, r, x, z)]
    i_bot = [mb.v((px, yb, pz)) for px, pz in _circle(seg, ri, x, z)]
    i_top = [mb.v((px, yl, pz)) for px, pz in _circle(seg, ri, x, z)]
    ang = lambda i, s=1: (s * math.cos(2 * math.pi * (i + .5) / seg), 0, s * math.sin(2 * math.pi * (i + .5) / seg))
    mb.ring_band(o_top, o_bot, trim, lambda i: ang(i))
    mb.ring_band(o_bot, i_bot, trim, lambda i: (0, -1, 0), smooth=False)
    mb.ring_band(i_bot, i_top, "baffle", lambda i: ang(i, -1))
    mb.f(list(i_top), "baffle", (0, -1, 0))
    if lens:
        mb.poly([(px, yl - .015, pz) for px, pz in _circle(seg, ri * .53, x, z)], lens, (0, -1, 0))
    for yy in (ys - .23, ys - .34):
        a = [mb.v((px, yy, pz)) for px, pz in _circle(seg, ri, x, z)]
        b = [mb.v((px, yy, pz)) for px, pz in _circle(seg, ri - .045, x, z)]
        mb.ring_band(a, b, "baffle", lambda i: (0, -1, 0), smooth=False)


def _drum(mb, x, ys, z, r, lens):
    path = _circle(24, r, x, z)
    normals = [(math.cos(2 * math.pi * k / 24), math.sin(2 * math.pi * k / 24)) for k in range(24)]
    _sweep(mb, path, normals, [(0, ys), (0, ys - .6), (-.12, ys - .72), (-.22, ys - .72)],
           ["brass", "trim", "brass"])
    _tube(mb, path, normals, .035, ys - .42, .055, lambda i: "neon_m", seg=6)
    if lens:
        mb.poly([(px, ys - .64, pz) for px, pz in _circle(24, r - .22, x, z)], lens, (0, -1, 0))


def _troffer(mb, x0, x1, z0, z1, ya, lens):
    """Lay-in enamel frame with a recessed lens; fixture louvres are added separately."""
    e, w, yf, yl = 0.04, 0.2, ya - 0.07, ya - 0.03
    O = (x0 + e, x1 - e, z0 + e, z1 - e)
    I = (O[0] + w, O[1] - w, O[2] + w, O[3] - w)
    corners = lambda R, y: [(R[0], y, R[2]), (R[1], y, R[2]), (R[1], y, R[3]), (R[0], y, R[3])]
    ob, ot, ib, it = corners(O, yf), corners(O, ya), corners(I, yf), corners(I, yl)
    out = [(0, 0, -1), (1, 0, 0), (0, 0, 1), (-1, 0, 0)]
    for k in range(4):
        j = (k + 1) % 4
        mb.poly([ob[k], ob[j], ib[j], ib[k]], "frame", (0, -1, 0))
        mb.poly([ob[k], ob[j], ot[j], ot[k]], "frame", out[k])
        mb.poly([ib[k], ib[j], it[j], it[k]], "frame", tuple(-v for v in out[k]))
    if lens:
        mb.poly(it, lens, (0, -1, 0))
    return I


def _louvres(mb, I, ya):
    """Three by six cells, with reflective vertical webs beneath a dim recessed lens."""
    x0, x1, z0, z1 = I
    along_x = x1 - x0 >= z1 - z0
    for axis, count in ((0, 6 if along_x else 3), (2, 3 if along_x else 6)):
        for k in range(1, count):
            if axis == 0:
                v = x0 + (x1 - x0) * k / count
                mb.box((v - .018, ya - .17, z0), (v + .018, ya - .025, z1), "trim", skip=("+y", "-z", "+z"))
            else:
                v = z0 + (z1 - z0) * k / count
                mb.box((x0, ya - .17, v - .018), (x1, ya - .025, v + .018), "trim", skip=("+y", "-x", "+x"))


def _sweep(mb, path, normals, profile, mats, closed=True):
    """Profile [(d, y)] offset d along each path point's outward normal; faces point to the profile's right."""
    rows = [[mb.v((px + nx * d, y, pz + nz * d)) for d, y in profile] for (px, pz), (nx, nz) in zip(path, normals)]
    n = len(path)
    for i in range(n if closed else n - 1):
        j = (i + 1) % n
        nx, nz = (normals[i][0] + normals[j][0]) / 2, (normals[i][1] + normals[j][1]) / 2
        for k in range(len(profile) - 1):
            (d0, y0), (d1, y1) = profile[k], profile[k + 1]
            a, b = -(y1 - y0), d1 - d0
            mb.f([rows[i][k], rows[j][k], rows[j][k + 1], rows[i][k + 1]], mats[k], (nx * a, b, nz * a), True)
    return rows


def _cyl(mb, p0, p1, r, m, seg=10):
    """Closed cylinder; also handles the sloping radial bars of service lamp cages."""
    direction = np.array(p1, float) - p0
    direction /= np.linalg.norm(direction)
    u = np.array((0, 1, 0) if abs(direction[1]) < .95 else (1, 0, 0), float)
    u -= direction * np.dot(u, direction); u /= np.linalg.norm(u)
    v = np.cross(direction, u)
    loops = []
    for p in (p0, p1):
        pts = []
        for k in range(seg):
            a = 2 * math.pi * k / seg
            pts.append(mb.v(np.array(p) + r * (u * math.cos(a) + v * math.sin(a))))
        loops.append(pts)
    def want(i):
        a = 2 * math.pi * (i + .5) / seg
        return u * math.cos(a) + v * math.sin(a)
    mb.ring_band(loops[0], loops[1], m, want)
    mb.f(loops[0], m, -direction); mb.f(loops[1], m, direction)


def _tube(mb, path, normals, dc, yc, r, mat_of, closed=True, seg=6):
    """Round tube swept along path, its axis at offset dc (along the path normals) and height yc."""
    ang = [-2 * math.pi * k / seg for k in range(seg)]
    rows = [[mb.v((px + nx * (dc + r * math.cos(t)), yc + r * math.sin(t), pz + nz * (dc + r * math.cos(t))))
             for t in ang] for (px, pz), (nx, nz) in zip(path, normals)]
    n = len(path)
    for i in range(n if closed else n - 1):
        j = (i + 1) % n
        nx, nz = (normals[i][0] + normals[j][0]) / 2, (normals[i][1] + normals[j][1]) / 2
        for k in range(seg):
            kk, t = (k + 1) % seg, -2 * math.pi * (k + 0.5) / seg
            mb.f([rows[i][k], rows[j][k], rows[j][kk], rows[i][kk]], mat_of(i),
                 (nx * math.cos(t), math.sin(t), nz * math.cos(t)), True)


def _split(poly, a, b):
    """Split a convex polygon [(u, v)] by the line a->b."""
    side = lambda p: (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0])
    L, R = [], []
    for i, p in enumerate(poly):
        q = poly[(i + 1) % len(poly)]
        sp, sq = side(p), side(q)
        (L if sp >= 0 else R).append(p)
        if sp * sq < 0:
            t = sp / (sp - sq)
            x = (p[0] + t * (q[0] - p[0]), p[1] + t * (q[1] - p[1]))
            L.append(x); R.append(x)
    return [s for s in (L, R) if len(s) >= 3]


# ---------------------------------------------------------------- planning (pure python)
def _zone_rect(z):
    if "rect" not in z:
        i = _NAMES.index(z["roof"])
        z["rect"] = (int(math.floor(_LO[i, 0])), int(math.ceil(_HI[i, 0])),
                     int(math.floor(_LO[i, 2])), int(math.ceil(_HI[i, 2])))
    if "seeds" not in z:
        x0, x1, z0, z1 = z["rect"]
        z["seeds"] = [((x0 + x1) / 2, (z0 + z1) / 2)]
    return z


def _kept_mask(x0, z0, shape, pad):
    m = np.zeros(shape, bool)
    for i in _KEPT:
        _stamp(m, x0, z0, _LO[i], _HI[i], True, pad)
    return m


def _ellipse_mask(shape, x0, z0, cx, cz, a, b):
    zz, xx = np.mgrid[0:shape[0], 0:shape[1]]
    return ((xx + x0 + 0.5 - cx) / a) ** 2 + ((zz + z0 + 0.5 - cz) / b) ** 2 <= 1.0


def _troffer_slots(act, x0, z0, T, pitch, orient, block, clear=2):
    H, W = act.shape
    ok = _erode(act, clear) & ~block
    La, Lb = (2, 1) if orient == "x" else (1, 2)
    pa, pb = (pitch[0], pitch[1]) if orient == "x" else (pitch[1], pitch[0])
    pa += pa % 2 if La == 2 else 0                # a long panel spans two short-edge units
    rr, cc = np.nonzero(act)
    if not len(cc):
        return []
    ca = (x0 + (cc.min() + cc.max() + 1) / 2 - OX) / T
    cb = (z0 + (rr.min() + rr.max() + 1) / 2) / T
    pha, phb = round(ca - La / 2) % pa, round(cb - Lb / 2) % pb
    if orient == "x":
        pha = round(pha / 2) * 2 % pa              # whole 4x2 panel boundaries
    out = []
    for a in range(math.floor((x0 - OX) / T), math.floor((x0 + W - OX) / T) + 1):
        if (a - pha) % pa:
            continue
        for b in range(math.floor(z0 / T), math.floor((z0 + H) / T) + 1):
            if (b - phb) % pb:
                continue
            X0, Z0 = OX + a * T, b * T
            c0, r0 = int(X0 - x0), int(Z0 - z0)
            c1, r1 = c0 + La * T, r0 + Lb * T
            if c0 >= 0 and r0 >= 0 and c1 <= W and r1 <= H and ok[r0:r1, c0:c1].all():
                out.append((X0, X0 + La * T, Z0, Z0 + Lb * T))
    return out


def _free_tiles(act, x0, z0, T, block, margin):
    ok = _erode(act, margin) & ~block
    H, W = act.shape
    out = []
    for a in range(math.floor((x0 - OX) / T), math.floor((x0 + W - OX) / T) + 1):
        for b in range(math.floor(z0 / T), math.floor((z0 + H) / T) + 1):
            if a % 2:
                continue
            c0, r0 = int(OX + a * T - x0), int(b * T - z0)
            if c0 >= 0 and r0 >= 0 and c0 + 2 * T <= W and r0 + T <= H and ok[r0:r0 + T, c0:c0 + 2 * T].all():
                out.append((OX + a * T, OX + a * T + 2 * T, b * T, b * T + T))
    return out


def _cells(tiles, x0, z0, shape, pad=0):
    m = np.zeros(shape, bool)
    for X0, X1, Z0, Z1 in tiles:
        m[max(0, int(Z0 - z0) - pad):max(0, int(Z1 - z0) + pad), max(0, int(X0 - x0) - pad):max(0, int(X1 - x0) + pad)] = True
    return m


def _grid_points(mask, x0, z0, px, pz, block, erode=1):
    ok = _erode(mask, erode) & ~block
    rr, cc = np.nonzero(mask)
    if not len(cc):
        return []
    cx, cz = x0 + (cc.min() + cc.max() + 1) / 2, z0 + (rr.min() + rr.max() + 1) / 2
    out = []
    for i in range(-int(mask.shape[1] / px) - 1, int(mask.shape[1] / px) + 2):
        for j in range(-int(mask.shape[0] / pz) - 1, int(mask.shape[0] / pz) + 2):
            x, z = cx + (i + 0.5 * (int(mask.shape[1] / px) % 2 == 0)) * px, cz + (j + 0.5 * (int(mask.shape[0] / pz) % 2 == 0)) * pz
            c, r = int(math.floor(x - x0)), int(math.floor(z - z0))
            if 0 <= r < mask.shape[0] and 0 <= c < mask.shape[1] and ok[r, c]:
                out.append((x, z))
    return out


def _fps(pts, k):
    """Farthest-point sampling: k well-spread indices, the first near the centroid."""
    if k <= 0 or not pts:
        return []
    A = np.array(pts, float)
    first = int(np.argmin(((A - A.mean(0)) ** 2).sum(1)))
    out, d = [first], ((A - A[first]) ** 2).sum(1)
    while len(out) < min(k, len(A)):
        i = int(d.argmax())
        out.append(i)
        d = np.minimum(d, ((A - A[i]) ** 2).sum(1))
    return out


def _field(name):
    """Smooth zone-seeded field over (x, z): three plane waves, wavelengths 90-220 studs (stretches of 2-8 fixtures)."""
    rng = random.Random("l4field:" + name)
    w = []
    for _ in range(3):
        th, lam = rng.uniform(0, math.pi), rng.uniform(90, 220)
        w.append((math.cos(th) * 2 * math.pi / lam, math.sin(th) * 2 * math.pi / lam, rng.uniform(0, 2 * math.pi)))
    return lambda x, z: sum(math.cos(kx * x + kz * z + ph) for kx, kz, ph in w)


def _spread(pts, n, rng):
    """n indices of pts, Poisson-disk spread (the minimum spacing relaxes until n fit)."""
    n = min(n, len(pts))
    if n <= 0:
        return []
    A = np.array(pts, float)
    ext = A.max(0) - A.min(0) + 1
    d = math.sqrt(ext[0] * ext[1] / n)
    order = list(range(len(pts)))
    rng.shuffle(order)
    while True:
        out = []
        for i in order:
            if all((A[i, 0] - A[j, 0]) ** 2 + (A[i, 1] - A[j, 1]) ** 2 >= d * d for j in out):
                out.append(i)
                if len(out) == n:
                    return out
        d *= 0.8


def _assign_states(fx, z, rng):
    """fx: fixture dicts with x, z. Sets state = lit / dim / dead / flicker (dark and dim come in stretches)."""
    n = len(fx)
    if not n:
        return
    dark, dim = (z.get("dark", DARK), z.get("dim", DIM)) if n >= STRETCH_MIN else (0.0, 0.0)
    f = _field(z["name"])
    order = sorted(range(n), key=lambda k: f(fx[k]["x"], fx[k]["z"]))
    nd, nm = round(dark * n), round(dim * n)
    for r, k in enumerate(order):
        fx[k]["state"] = "dead" if r < nd else "dim" if r < nd + nm else \
            ("dead" if rng.random() < SPRINKLE else "lit")
    for k in _spread([(c["x"], c["z"]) for c in fx], round(FLICKER * n), rng):
        fx[k]["state"] = "flicker"


def plan_zone(z):
    z = _zone_rect(dict(z))
    rng = random.Random("l4ceil:" + z["name"])
    T = _tile()
    x0, x1, z0, z1 = z["rect"]
    y = z["y"]
    mask = _zone_mask(z)
    kept = _kept_mask(x0, z0, mask.shape, 2.0)
    zp = dict(z=z, x0=x0, z0=z0, mask=mask, T=T, act=np.zeros_like(mask), deck=np.zeros_like(mask),
              troffers=[], cans=[], holes=[], sag=[], stain=[], coffers=[], bulkheads=[], clouds=[], stars=[],
              pendants=[], cages=[], housings=[], lights=[], grilles=[], detectors=[], plenum=z.get("plenum", 3.0))
    block = kept.copy()
    kind = z["kind"]
    if kind in ("act", "concourse"):
        zp["act"] = mask.copy()
    if kind in ("deck", "aud"):
        zp["deck"] = mask.copy()

    for leak_zone, lx, lz, _, _ in LEAKS:
        leak_zone = {"Men": "RestroomMen", "Women": "RestroomWomen"}.get(leak_zone, leak_zone)
        if leak_zone == z["name"]:
            tx = OX + math.floor((lx - OX) / (2 * T)) * 2 * T
            tz = math.floor(lz / T) * T
            t = (tx, tx + 2 * T, tz, tz + T)
            zp["stain"].append(t)
            block |= _cells([t], x0, z0, mask.shape, 1)

    if kind == "concourse":
        rows = np.arange(mask.shape[0]) + z0 + 0.5
        nave = ((rows >= NAVE[0]) & (rows < NAVE[1]))[:, None] & np.ones_like(mask)
        zp["deck"] = mask & nave
        zp["act"] = mask & ~nave
        colpts = [(_CTR[i, 0], _CTR[i, 2]) for i, n in enumerate(_NAMES) if n == "Concourse/ConcourseColumn"]
        zp["columns"] = colpts
        near_col = np.zeros_like(mask)
        for cx, cz in colpts:
            near_col |= _ellipse_mask(mask.shape, x0, z0, cx, cz, 5.5, 5.5)
        for cx, cz in COFFERS:
            f = 1.0
            while f > 0.6:                        # shrink a coffer that would cut into a mass
                e = _ellipse_mask(mask.shape, x0, z0, cx, cz, COFFER_AB[0] * f + 1, COFFER_AB[1] * f + 1)
                if (mask | near_col)[e].all():
                    break
                f -= 0.02
            a, b = COFFER_AB[0] * f, COFFER_AB[1] * f
            zp["coffers"].append((cx, cz, a, b))
            block |= _ellipse_mask(mask.shape, x0, z0, cx, cz, a + 2, b + 2)
            cans = [(cx, cz)]                     # centre + a ring of 10 on the dropped disc
            for k in range(10):
                th = 2 * math.pi * (k + 0.5) / 10
                cans.append((cx + (a - COFFER_STEP - 4.5) * math.cos(th), cz + (b - COFFER_STEP - 4.5) * math.sin(th)))
            for px, pz in cans:
                if all(math.hypot(px - qx, pz - qz) >= 6.5 for qx, qz in colpts):
                    zp["cans"].append(dict(x=px, z=pz, ys=y - 2.0, r=0.8, group="coffer%d" % len(zp["coffers"]),
                                           trim="brass"))
        # nave: star pinlights + a row of cans between the coffers
        deckok = zp["deck"] & ~block
        rr, cc = np.nonzero(deckok)
        for k in rng.sample(range(len(rr)), min(len(rr), int(len(rr) / 40))):
            zp["stars"].append((x0 + cc[k] + rng.random(), z0 + rr[k] + rng.random(), rng.uniform(0.35, 0.5)))
        ok = _erode(zp["deck"], 2) & ~block
        for pz in NAVE_CAN_ROWS:                  # two rows of cans between the coffers
            for px in range(x0 + 8, x1 - 7, 16):
                if ok[int(pz - z0), int(px - x0)]:
                    zp["cans"].append(dict(x=px + 0.5, z=pz, ys=y - 0.02, r=0.7, group="nave", trim="brass"))
        for px, pz in _grid_points(zp["act"], x0, z0, 36, 16, block, 3):
            drum = round((px - x0) / 36) % 3 == 0
            zp["cans"].append(dict(x=px, z=pz, ys=y - .08, r=1.6 if drum else .65,
                                   group="aisle", trim="brass", shape="drum" if drum else "can"))
    elif kind == "deck":
        for px, pz in _grid_points(mask, x0, z0, 12, 12, block, 2):
            zp["cans"].append(dict(x=px, z=pz, ys=y - 0.02, r=0.62, group="deck", trim="trim"))
    elif kind == "aud":
        zb = [z0 + 44 * k for k in (1, 2, 3, 4)]
        cxm = (x0 + x1) / 2
        for b in zb:
            r = int(b - z0)
            c = np.nonzero(mask[r])[0]
            if len(c):
                zp["bulkheads"].append((x0 + c.min() - 0.3, x0 + c.max() + 1.3, b))
                block[max(0, r - 9):r + 9, :] = True
        for i in range(len(zb) - 1):
            cz = (zb[i] + zb[i + 1]) / 2
            for sx in (-1, 1):
                cl = (cxm + sx * 28 - 14, cxm + sx * 28 + 14, cz - 12, cz + 12)
                zp["clouds"].append(cl)
                _stamp(block, x0, z0, (cl[0], 0, cl[2]), (cl[1], 0, cl[3]), True, 1.5)
        for px, pz in _grid_points(mask, x0, z0, 15, 11, block, 2):
            zp["cans"].append(dict(x=px, z=pz, ys=y - 0.02, r=0.62, group="aud", trim="brass"))

    if zp["act"].any():
        act = zp["act"]
        orient = z.get("orient", "x")
        zp["orient"] = orient
        # things hung from the ACT
        if z["name"] == "Arcade":              # the old neon rectangle becomes a hung bulkhead frame
            lo, hi = _LO[_ARC_NEON].min(0), _HI[_ARC_NEON].max(0)
            zp["frame"] = (lo[0], hi[0], lo[2], hi[2])
            _stamp(block, x0, z0, lo, hi, True, 3.0)
        if z["name"] == "Concession":
            for i, n in enumerate(_NAMES):
                if n == "Concession/CounterWarmLight":
                    zp["pendants"].append((_CTR[i, 0], _CTR[i, 2]))
                    _stamp(block, x0, z0, _LO[i], _HI[i], True, 3.0)
            for px, pz in _grid_points(act, x0, z0, 28, 24, block, 3):
                zp["cans"].append(dict(x=px, z=pz, ys=y - .08, r=.65, group="concession", trim="brass"))
                _stamp(block, x0, z0, (px, 0, pz), (px, 0, pz), True, 3)
        if z["name"] == "Service":
            for i, n in enumerate(_NAMES):
                if n == "Service/CagedServiceLamp":
                    px, pz = _CTR[i, 0], _CTR[i, 2]
                    zp["cages"].append((px, pz))
                    _stamp(block, x0, z0, _LO[i], _HI[i], True, 2)
        for c in zp["cans"]:
            _stamp(block, x0, z0, (c["x"], 0, c["z"]), (c["x"], 0, c["z"]), True, c["r"] + 1.5)
        troffers = [] if kind == "concourse" else _troffer_slots(act, x0, z0, T, z.get("pitch", (4, 4)),
                                                                orient, block, z.get("clear", 2))
        zp["troffers"] = [dict(rect=t, x=(t[0] + t[1]) / 2, z=(t[2] + t[3]) / 2) for t in troffers]
        tro = _cells(troffers, x0, z0, act.shape, 0)
        cand = _free_tiles(act, x0, z0, T, block | tro, 3)
        rng.shuffle(cand)
        ntiles = act.sum() / (2 * T * T)
        miss = z.get("missing", 0.01)
        want = [max(1 if miss and ntiles > 60 else 0, round(miss * ntiles)),
                max(1 if miss and ntiles > 120 else 0, round(0.5 * miss * ntiles)),
                round(0.02 * ntiles)]
        if z["name"] in ("RestroomMen", "RestroomWomen"):
            want[:2] = [2, 1]
        taken = np.zeros_like(act)
        for key, n in zip(("holes", "sag", "stain"), want):
            for t in cand:
                if len(zp[key]) >= n:
                    break
                c0, r0 = int(t[0] - x0), int(t[2] - z0)
                if not taken[max(0, r0 - T):r0 + 2 * T, max(0, c0 - T):c0 + 2 * T].any():
                    zp[key].append(t)
                    taken[r0:r0 + T, c0:c0 + 2 * T] = True
        zp["fallen"] = zp["holes"][::3]
        for t in cand:                            # slotted return-air grilles, ~1 per 80 tiles
            if len(zp["grilles"]) >= round(0.012 * ntiles):
                break
            c0, r0 = int(t[0] - x0), int(t[2] - z0)
            if not taken[max(0, r0 - T):r0 + 2 * T, max(0, c0 - T):c0 + 2 * T].any():
                zp["grilles"].append(t)
                taken[r0:r0 + T, c0:c0 + 2 * T] = True
        block |= _cells(zp["holes"] + zp["sag"] + zp["grilles"], x0, z0, act.shape, 1) | tro
    # smoke detectors on a loose 28-stud grid, clear of fixtures
    fx_blk = block.copy()
    for c in zp["cans"]:
        _stamp(fx_blk, x0, z0, (c["x"], 0, c["z"]), (c["x"], 0, c["z"]), True, 3.0)
    if kind != "aud":
        for px, pz in _grid_points(mask, x0, z0, 28, 28, fx_blk, 3):
            zp["detectors"].append((px + rng.uniform(-3, 3), pz + rng.uniform(-3, 3)))

    # housings for the kept flicker fixtures inside this zone (the arcade's is buried in the new frame)
    for i in _KEPT:
        if (not _NAMES[i].startswith("Arcade/") and x0 <= _CTR[i, 0] <= x1 and z0 <= _CTR[i, 2] <= z1
                and abs(_HI[i, 1] - y) < 1.0):
            zp["housings"].append(i)

    # fixture states + lights
    lk = z["light"]
    _assign_states(zp["troffers"] + zp["cans"], z, rng)
    rng_lt = min(60.0, y - z["floor"] + 10)
    ya = y - 0.08

    def troffer_light(t):
        X0, X1, Z0, Z1 = t["rect"]
        return dict(type="POINT", pos=((X0 + X1) / 2, ya - 1.53, (Z0 + Z1) / 2), color=LIGHT[lk],
                    range=rng_lt, b=BRIGHT[lk], size=(X1 - X0 - 0.48, Z1 - Z0 - 0.48), angle=110, kind="troffer",
                    shadows=False)

    def can_light(c, rng_c, b, angle=70):
        return dict(type="SPOT", pos=(c["x"], c["ys"] - 0.2, c["z"]), color=LIGHT[lk], range=rng_c, b=b,
                    angle=angle, kind="can", shadows=False)

    def point(pos, col, rng_p, b, kind):
        return dict(type="POINT", pos=pos, color=LIGHT[col], range=rng_p, b=b, kind=kind, shadows=False)

    heroes = z.get("heroes", 0)
    # Flicker lights share each zone's allocation: select about one third, then fill with steady fixtures.
    fx = zp["troffers"] + zp["cans"]
    flickers = [f for f in fx if f["state"] == "flicker"]
    # Some zones have fewer light slots than blinking lenses; oversample candidates, then apply the zone cap.
    chosen_flick = {id(flickers[k]) for k in _fps([(f["x"], f["z"]) for f in flickers], round(len(flickers) * .45))}
    def eligible(f):
        return f["state"] == "lit" or id(f) in chosen_flick
    def allocation(group, count):
        blinking = [i for i, f in enumerate(group) if id(f) in chosen_flick]
        steady = [i for i, f in enumerate(group) if f["state"] == "lit"]
        return [blinking[k] for k in _fps([(group[i]["x"], group[i]["z"]) for i in blinking], count)] + \
            [steady[k] for k in _fps([(group[i]["x"], group[i]["z"]) for i in steady],
                                                          max(0, count - len(blinking)))]
    lit_t = [t for t in zp["troffers"] if eligible(t)]
    act_budget = max(0, z.get("lights", 0) - len(zp["cages"]))
    g_act = lit_t + [c for c in zp["cans"] if eligible(c) and c["group"] == "concession"]
    pick = allocation(g_act, act_budget if kind == "act" else 0)
    for n, k in enumerate(pick):
        f = g_act[k]
        L = troffer_light(f) if "rect" in f else can_light(f, rng_lt, BRIGHT[lk])
        L["shadows"] = n < heroes
        f["light"] = L
    if kind == "concourse":
        for gi, (cx, cz, a, b) in enumerate(zp["coffers"]):
            g = [c for c in zp["cans"] if c["group"] == "coffer%d" % (gi + 1) and eligible(c)]
            for n, k in enumerate(allocation(g, 2)):
                g[k]["light"] = can_light(g[k], 45, 1.2, angle=75)
                g[k]["light"]["shadows"] = n == 0
            for th in (math.pi / 2, math.pi * 3 / 2):          # magenta wash in the step reveal, N and S
                if gi == COFFER_BURNT[0] and COFFER_BURNT[1] <= th <= COFFER_BURNT[2]:
                    continue
                nx, nz = math.cos(th) / a, math.sin(th) / b
                ln = math.hypot(nx, nz)
                zp["lights"].append(point((cx + a * math.cos(th) - 1.5 * nx / ln, y - 2.8,
                                           cz + b * math.sin(th) - 1.5 * nz / ln), "magenta", 22, 0.9, "cove"))
        g = [c for c in zp["cans"] if c["group"] == "nave" and eligible(c)]
        for k in allocation(g, z.get("nave_lights", 0)):
            g[k]["light"] = can_light(g[k], 48, 1.0)
        g = [c for c in zp["cans"] if c["group"] == "aisle" and eligible(c)]
        for k in allocation(g, z["lights"]):
            g[k]["light"] = point((g[k]["x"], y - 1.5, g[k]["z"]), "warm", 48, .9, "drum")
    elif kind in ("deck", "aud"):
        g = [c for c in zp["cans"] if eligible(c)]
        for n, k in enumerate(allocation(g, z.get("lights", 0))):
            g[k]["light"] = can_light(g[k], min(60.0, y - z["floor"] + 12), 1.1 if kind == "deck" else 1.3)
            g[k]["light"]["shadows"] = n < heroes
        if kind == "aud":
            for bx0, bx1, bz in zp["bulkheads"]:
                for side in (-1, 1):
                    for u in (.27, .73):
                        zp["lights"].append(point((bx0 + (bx1 - bx0) * u, y - 4.8, bz + side * 7.8),
                                                   "magenta" if side == 1 else "cyan", 52, .4, "cove"))
    for f in fx:
        if f["state"] == "flicker" and f.get("light"):
            f["light"]["type"] = "POINT"
            f["light"]["kind"] = "flicker"
    for px, pz in zp["cages"]:
        zp["lights"].append(point((px, ya - 1.1, pz), "cool", 30, .7, "caged"))
    for px, pz in zp["pendants"]:
        zp["lights"].append(point((px, ya - 6.1, pz), "amber", 22, 0.6, "pendant"))
    if "frame" in zp:                                            # arcade frame: magenta + cyan wash, one hero
        fx0, fx1, fz0, fz1 = zp["frame"]
        fy = FRAME_Y - 1.2
        zp["lights"] += [point(((fx0 + fx1) / 2, fy, fz0 + 3), "magenta", 26, 0.8, "frame"),
                         point(((fx0 + fx1) / 2, fy, (fz0 + fz1) / 2), "cyan", 22, 0.6, "frame")]
        zp["lights"][-2]["shadows"] = True
        zp["frame_flicker"] = point(((fx0 + fx1) / 2, fy, fz1 - 0.2), "magenta", 22, 0.8, "flicker")
    return zp


# ---------------------------------------------------------------- geometry (pure python, Studio studs)
def zone_geometry(zp):
    """-> pooled _MB and flicker lens dicts."""
    z, x0, z0, T = zp["z"], zp["x0"], zp["z0"], zp["T"]
    y = z["y"]
    ya, yd = y - 0.08, y - 0.02
    lens_m = "lens_" + z["light"]
    act_m = z.get("tint", "act")
    mb = _MB()
    flick = []
    rng = random.Random("l4ceilgeo:" + z["name"])
    # Plenum follows the room; it cannot bridge the open core stairwell.
    X0, X1, Z0, Z1 = z["rect"]
    for c0, c1, r0, r1 in _rects(_dilate(zp["mask"], 2)):
        mb.hquad(x0 + c0, x0 + c1, z0 + r0, z0 + r1, y + zp["plenum"], "plenum")
    # ACT field with holes for missing / sagging / stained tiles
    if zp["act"].any():
        cut = _cells(zp["holes"] + zp["sag"] + zp["stain"] + zp["grilles"], x0, z0, zp["act"].shape)
        for c0, c1, r0, r1 in _rects(zp["act"] & ~cut):
            mb.hquad(x0 + c0, x0 + c1, z0 + r0, z0 + r1, ya, act_m)
        for t in zp["stain"]:
            mb.hquad(t[0], t[1], t[2], t[3], ya, act_m)
            mb.hquad(t[0] + .06, t[1] - .06, t[2] + .06, t[3] - .06, ya - .012, "ceiling_rings")
        for t in zp["holes"] + zp["sag"]:                 # the grid stays: T-bar flange + web around the gap
            tx0, tx1, tz0, tz1 = t
            w = 0.09
            for lo, hi in (((tx0, tz0), (tx1, tz0 + w)), ((tx0, tz1 - w), (tx1, tz1)),
                           ((tx0, tz0 + w), (tx0 + w, tz1 - w)), ((tx1 - w, tz0 + w), (tx1, tz1 - w))):
                mb.hquad(lo[0], hi[0], lo[1], hi[1], ya - 0.01, "tbar")
            mb.box((tx0 + w - 0.02, ya - 0.01, tz0 + w - 0.02), (tx1 - w + 0.02, ya + 0.16, tz1 - w + 0.02), "tbar",
                   skip=("-y", "+y"))
        for t in zp["holes"]:
            tx0, tx1, tz0, tz1 = t
            cx, cz = (tx0 + tx1) / 2, (tz0 + tz1) / 2
            pl = zp["plenum"]
            if rng.random() < 0.55:                        # a galvanised duct runs over the gap
                r = min(0.8, pl * 0.3)
                yc = y + min(pl - r - 0.3, 0.4 + r + rng.uniform(0, 0.6))
                if zp.get("orient", "x") == "x":
                    _cyl(mb, (cx - 11, yc, cz + rng.uniform(-1, 1)), (cx + 11, yc, cz + rng.uniform(-1, 1)), r, "duct")
                else:
                    _cyl(mb, (cx + rng.uniform(-1, 1), yc, cz - 11), (cx + rng.uniform(-1, 1), yc, cz + 11), r, "duct")
            else:                                          # a steel joist chord crosses it
                yj = y + pl - 0.7
                if zp.get("orient", "x") == "x":
                    mb.box((cx - 0.15, yj, cz - 9), (cx + 0.15, yj + 0.35, cz + 9), "joist")
                else:
                    mb.box((cx - 9, yj, cz - 0.15), (cx + 9, yj + 0.35, cz + 0.15), "joist")
            if rng.random() < 0.4:                         # a hanger wire dangling through the gap
                wx, wz = cx + rng.uniform(-1.2, 1.2), cz + rng.uniform(-1.2, 1.2)
                mb.box((wx - 0.03, ya - rng.uniform(0.8, 2.6), wz - 0.03), (wx + 0.03, y + pl, wz + 0.03), "cable")
        for t in zp["sag"]:                                # one edge still on the grid, the far edge dropped
            tx0, tx1, tz0, tz1 = t
            drop = rng.uniform(0.7, 1.5)
            hinge = rng.randrange(4)
            n = 4
            grid = []
            for i in range(n + 1):
                row = []
                for j in range(n + 1):
                    u, v = i / n, j / n                  # u across X, v across Z
                    t_ = (u, 1 - u, v, 1 - v)[hinge]     # 0 at the hinge edge
                    bow = 0.12 * math.sin(math.pi * (v if hinge < 2 else u))
                    row.append((tx0 + 0.1 + u * (tx1 - tx0 - 0.2), ya - 0.02 - drop * t_ ** 1.6 - bow * t_,
                                tz0 + 0.1 + v * (tz1 - tz0 - 0.2)))
                grid.append(row)
            for i in range(n):
                for j in range(n):
                    q = [grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]]
                    mb.poly(q, "act_stain", (0, -1, 0), True)
                    mb.poly([(p[0], p[1] + 0.05, p[2]) for p in q], "act_back", (0, 1, 0), True)
    # black deck (corridors, auditoria, concourse nave)
    if zp["deck"].any():
        for c0, c1, r0, r1 in _rects(zp["deck"]):
            mb.hquad(x0 + c0, x0 + c1, z0 + r0, z0 + r1, yd, "deck")
    for sx, sz, s in zp["stars"]:
        mb.hquad(sx - s / 2, sx + s / 2, sz - s / 2, sz + s / 2, yd - 0.01, "star")
    if z["kind"] == "concourse":                          # brass reveal where the aisle ACT meets the nave deck
        for zz in NAVE:
            r = int(zz - z0)
            both = zp["mask"][r - 1] & zp["mask"][r]
            d = np.diff(np.concatenate(([0], both.astype(np.int8), [0])))
            for c0, c1 in zip(np.nonzero(d == 1)[0], np.nonzero(d == -1)[0]):
                mb.box((x0 + c0, ya - 0.05, zz - 0.18), (x0 + c1, yd, zz + 0.18), "brass", skip=("+y",))
    # coffers: two-step elliptical drop, magenta tube tucked in the step reveal, cyan line on the lower lip
    for gi, (cx, cz, a, b) in enumerate(zp["coffers"]):
        n = 72
        path, nrm, ths = [], [], []
        for k in range(n):
            th = 2 * math.pi * k / n
            path.append((cx + a * math.cos(th), cz + b * math.sin(th)))
            nx, nz = math.cos(th) / a, math.sin(th) / b
            ln = math.hypot(nx, nz)
            nrm.append((nx / ln, nz / ln))
            ths.append(th)
        w = COFFER_STEP
        prof = [(0, y), (0, y - 0.9), (-0.12, y - 1.02), (-w, y - 1.02), (-w, y - 1.3), (-w, y - 1.88),
                (-w - 0.12, y - 2.0), (-w - 0.8, y - 2.0)]
        rows = _sweep(mb, path, nrm, prof, ["coffer"] * 7)
        mb.f([r[-1] for r in rows], "coffer", (0, -1, 0))
        burnt = lambda i, gi=gi: gi == COFFER_BURNT[0] and COFFER_BURNT[1] <= ths[i] <= COFFER_BURNT[2]
        _tube(mb, path, nrm, -w + 0.16, y - 1.17, 0.13, lambda i: "neon_dead" if burnt(i) else "neon_m")
        _tube(mb, path, nrm, -w - 0.04, y - 1.96, 0.06, lambda i: "neon_c", seg=5)
        for px, pz in zp["columns"]:
            if ((px - cx) / a) ** 2 + ((pz - cz) / b) ** 2 < .8:
                cp = _circle(24, 4.32, px, pz)
                cn = [(math.cos(2 * math.pi * k / 24), math.sin(2 * math.pi * k / 24)) for k in range(24)]
                _sweep(mb, cp, cn, [(0, y - 1.84), (0, y - 2.16), (-.24, y - 2.16)], ["brass", "brass"])
    # auditorium bulkheads (stepped plaster, magenta tube in the upper reveal, cyan line on the lower lip) and clouds
    for bx0, bx1, bz in zp["bulkheads"]:
        prof = [(7.0, y), (7.0, y - 1.7), (6.88, y - 1.82), (4.6, y - 1.82), (4.6, y - 2.12), (4.6, y - 3.48),
                (4.48, y - 3.6), (0.0, y - 3.6)]
        for s in (1, -1):
            _sweep(mb, [(bx0, bz), (bx1, bz)], [(0, s), (0, s)], prof, ["bulkhead"] * 7, closed=False)
            _cyl(mb, (bx0 + 0.3, y - 1.97, bz + s * 4.75), (bx1 - 0.3, y - 1.97, bz + s * 4.75), 0.13, "neon_m", 6)
            _cyl(mb, (bx0 + 0.3, y - 3.54, bz + s * 4.54), (bx1 - 0.3, y - 3.54, bz + s * 4.54), 0.06, "neon_c", 5)
    if z["kind"] == "aud":                                # one exposed spiral duct under the bulkheads, on straps
        X0_, X1_, Z0_, Z1_ = z["rect"]
        dx, dy = X1_ - 14, y - 5.2
        _cyl(mb, (dx, dy, Z0_ + 12), (dx, dy, Z1_ - 16), 1.1, "duct", 12)
        for sz in np.arange(Z0_ + 20, Z1_ - 16, 22.0):
            mb.box((dx - 1.2, dy - 1.2, sz - 0.12), (dx + 1.2, dy - 1.1, sz + 0.12), "joist")
            for sx in (dx - 1.2, dx + 1.1):
                mb.box((sx, dy - 1.1, sz - 0.12), (sx + 0.1, yd, sz + 0.12), "joist", skip=("+y",))
    for cx0, cx1, cz0, cz1 in zp["clouds"]:
        yb, yt, ch = y - 4.4, y - 3.6, 0.22
        ob = [(cx0 + ch, yb, cz0 + ch), (cx1 - ch, yb, cz0 + ch), (cx1 - ch, yb, cz1 - ch), (cx0 + ch, yb, cz1 - ch)]
        om = [(cx0, yb + ch, cz0), (cx1, yb + ch, cz0), (cx1, yb + ch, cz1), (cx0, yb + ch, cz1)]
        ot = [(p[0], yt, p[2]) for p in om]
        mb.poly(ob, "cloud", (0, -1, 0))
        out = [(0, -1, -1), (1, -1, 0), (0, -1, 1), (-1, -1, 0)]
        for k in range(4):
            j = (k + 1) % 4
            mb.poly([ob[k], ob[j], om[j], om[k]], "cloud", out[k])
            mb.poly([om[k], om[j], ot[j], ot[k]], "cloud", (out[k][0], 0, out[k][2]))
        for px, pz in ((cx0 + 2, cz0 + 2), (cx1 - 2, cz0 + 2), (cx1 - 2, cz1 - 2), (cx0 + 2, cz1 - 2)):
            mb.box((px - 0.04, yt, pz - 0.04), (px + 0.04, yd, pz + 0.04), "cable", skip=("-y", "+y"))
    # arcade: black bulkhead frame on the old neon rectangle (it encloses the kept red flicker segment), magenta
    # tube ring underneath, cyan tubes on two crossbars; the north tube is a flicker lens
    if "frame" in zp:
        fx0, fx1, fz0, fz1 = zp["frame"]
        w, fy = 1.4, FRAME_Y
        for lo, hi in (((fx0 - w, fz0 - w), (fx1 + w, fz0 + w)), ((fx0 - w, fz1 - w), (fx1 + w, fz1 + w)),
                       ((fx0 - w, fz0 + w), (fx0 + w, fz1 - w)), ((fx1 - w, fz0 + w), (fx1 + w, fz1 - w))):
            mb.box((lo[0], fy, lo[1]), (hi[0], ya, hi[1]), "soffit", skip=("+y",))
        xb0, xb1 = (fx0 + fx1) / 2 - 10.5, (fx0 + fx1) / 2 + 10.5
        for zc in (fz0 + 5.15, fz1 - 5.15):
            mb.box((fx0 + w, fy + 0.4, zc - 0.6), (fx1 - w, ya, zc + 0.6), "soffit", skip=("+y",))
            _cyl(mb, (xb0, fy + 0.28, zc), (xb1, fy + 0.28, zc), 0.12, "neon_c", 6)
        yt = fy - 0.16
        _cyl(mb, (fx0, yt, fz0 + 0.15), (fx1, yt, fz0 + 0.15), 0.14, "neon_m", 6)
        _cyl(mb, (fx0 + 0.15, yt, fz0 + 0.3), (fx0 + 0.15, yt, fz1 - 0.3), 0.14, "neon_m", 6)
        _cyl(mb, (fx1 - 0.15, yt, fz0 + 0.3), (fx1 - 0.15, yt, fz1 - 0.3), 0.14, "neon_m", 6)
        flick.append(dict(shape="bar", mat="neon_m", pos=((fx0 + fx1) / 2, yt, fz1 - 0.15),
                          size3=(fx1 - fx0, 0.28, 0.28), light=zp.get("frame_flicker")))
    # concession: heat-lamp pendants
    for px, pz in zp["pendants"]:
        mb.box((px - 0.05, ya - 5.0, pz - 0.05), (px + 0.05, ya, pz + 0.05), "cord", skip=("+y", "-y"))
        top = [mb.v((qx, ya - 5.0, qz)) for qx, qz in _circle(14, 0.35, px, pz)]
        bot = [mb.v((qx, ya - 6.2, qz)) for qx, qz in _circle(14, 1.0, px, pz)]
        mb.f(top, "shade", (0, 1, 0))
        mb.ring_band(top, bot, "shade", lambda i: (math.cos(2 * math.pi * (i + .5) / 14), 0.5,
                                                   math.sin(2 * math.pi * (i + .5) / 14)))
        mb.f(list(bot), "lens_amber", (0, -1, 0))
    for px, pz in zp["cages"]:
        path = _circle(16, 1.0, px, pz)
        normals = [(math.cos(2 * math.pi * k / 16), math.sin(2 * math.pi * k / 16)) for k in range(16)]
        _sweep(mb, path, normals, [(0, ya), (0, ya - .24), (-.18, ya - .28)], ["joist", "joist"])
        _sweep(mb, path, normals, [(-.18, ya - .28), (-.18, ya - .7), (-.45, ya - .88)],
               ["lens_cool_dim", "lens_cool_dim"])
        mb.poly([(qx, ya - .87, qz) for qx, qz in _circle(16, .55, px, pz)], "lens_cool", (0, -1, 0))
        for k in range(8):
            th = 2 * math.pi * k / 8
            qx, qz = px + .94 * math.cos(th), pz + .94 * math.sin(th)
            mb.box((qx - .035, ya - .86, qz - .035), (qx + .035, ya - .2, qz + .035), "joist")
            _cyl(mb, (qx, ya - .86, qz), (px, ya - .99, pz), .035, "joist", 6)
        _tube(mb, path, normals, -.08, ya - .65, .045, lambda i: "joist", seg=6)
    # housings around the kept flicker fixtures (restroom fluorescents, auditorium ceiling squares)
    for i in zp["housings"]:
        lo, hi = _LO[i], _HI[i]
        e = 0.16
        mb.box((lo[0] - e, lo[1] - 0.06, lo[2] - e), (hi[0] + e, ya if z["kind"] != "aud" else yd, hi[2] + e),
               "frame", skip=("+y", "-y"))
        for a_, b_ in (((lo[0] - e, lo[2] - e), (hi[0] + e, lo[2])), ((lo[0] - e, hi[2]), (hi[0] + e, hi[2] + e)),
                       ((lo[0] - e, lo[2]), (lo[0], hi[2])), ((hi[0], lo[2]), (hi[0] + e, hi[2]))):
            mb.hquad(a_[0], b_[0], a_[1], b_[1], lo[1] - 0.06, "frame")
    # return-air grilles (frame, recessed dark throat, 6 slats) and smoke detectors
    for tx0, tx1, tz0, tz1 in zp["grilles"]:
        e, w_ = 0.04, 0.18
        _troffer(mb, tx0, tx1, tz0, tz1, ya + 0.04, None)
        mb.hquad(tx0 + e + w_, tx1 - e - w_, tz0 + e + w_, tz1 - e - w_, ya + 0.35, "baffle")
        n_ = 6
        for k in range(n_):
            u = tx0 + e + w_ + (k + 0.5) * (tx1 - tx0 - 2 * (e + w_)) / n_
            mb.box((u - 0.06, ya - 0.02, tz0 + e + w_), (u + 0.06, ya + 0.3, tz1 - e - w_), "frame",
                   skip=("+y", "-z", "+z"))
    for px, pz in zp["detectors"]:
        ys = y - 0.02 if zp["deck"].any() and not zp["act"][int(pz - z0), int(px - x0)] else ya
        top = [mb.v((qx, ys, qz)) for qx, qz in _circle(10, 0.4, px, pz)]
        bot = [mb.v((qx, ys - 0.22, qz)) for qx, qz in _circle(10, 0.36, px, pz)]
        mb.ring_band(top, bot, "frame", lambda i: (math.cos(2 * math.pi * (i + .5) / 10), 0,
                                                   math.sin(2 * math.pi * (i + .5) / 10)))
        mb.f(list(bot), "frame", (0, -1, 0))
    # fixtures
    for t in zp["troffers"]:
        X0, X1, Z0, Z1 = t["rect"]
        st = t["state"]
        I = _troffer(mb, X0, X1, Z0, Z1, ya, _lens(st, lens_m))
        _louvres(mb, I, ya)
        if st == "flicker":
            flick.append(dict(shape="troffer", mat=lens_m, pos=((I[0] + I[1]) / 2, ya - 0.03, (I[2] + I[3]) / 2),
                              size=(I[1] - I[0], I[3] - I[2]), light=t.get("light")))
        t["lens_rect"] = I
    for c in zp["cans"]:
        st = c["state"]
        drum = c.get("shape") == "drum"
        if drum:
            _drum(mb, c["x"], c["ys"], c["z"], c["r"], _lens(st, lens_m))
        else:
            _can(mb, c["x"], c["ys"], c["z"], c["r"], c["trim"], _lens(st, lens_m))
        if st == "flicker":
            flick.append(dict(shape="can", mat=lens_m, pos=(c["x"], c["ys"] - (.64 if drum else .135), c["z"]),
                              r=c["r"] - .22 if drum else .72 * .53 * c["r"],
                              light=c.get("light")))
    return mb, flick


def fallen_shards(t, floor_y, rng):
    """A third of the missing tiles lie broken on the floor: 2-3 shards, flat or leaning on each other."""
    tx0, tx1, tz0, tz1 = t
    cx, cz = (tx0 + tx1) / 2 + rng.uniform(-1.5, 1.5), (tz0 + tz1) / 2 + rng.uniform(-1.5, 1.5)
    h, hz = (tx1 - tx0) / 2 - .05, (tz1 - tz0) / 2 - .05
    sq = [(-h, -hz), (h, -hz), (h, hz), (-h, hz)]
    parts = _split(sq, (rng.uniform(-h, h), -hz - 1), (rng.uniform(-h, h), hz + 1))
    if rng.random() < 0.6 and parts:
        big = max(parts, key=lambda p: abs(_newell([(u, 0, v) for u, v in p])[1]))
        parts.remove(big)
        parts += _split(big, (-h - 1, rng.uniform(-h, h)), (h + 1, rng.uniform(-h, h)))
    out = []
    for k, poly in enumerate(parts):
        mb = _MB()
        yaw = rng.uniform(0, 2 * math.pi)
        ox, oz = cx + rng.uniform(-1.4, 1.4), cz + rng.uniform(-1.4, 1.4)
        lean = rng.uniform(0.02, 0.09) if k else rng.uniform(0, 0.03)     # radians about the local u axis
        face_up = rng.random() < 0.5
        th = 0.06
        def xf(u, v, w):
            v2, w2 = v * math.cos(lean) - w * math.sin(lean), v * math.sin(lean) + w * math.cos(lean)
            return (ox + u * math.cos(yaw) - v2 * math.sin(yaw), w2, oz + u * math.sin(yaw) + v2 * math.cos(yaw))
        bot = [xf(u, v, 0) for u, v in poly]
        top = [xf(u, v, th) for u, v in poly]
        lift = floor_y + 0.005 - min(p[1] for p in bot)
        bot = [(p[0], p[1] + lift, p[2]) for p in bot]
        top = [(p[0], p[1] + lift, p[2]) for p in top]
        mb.poly(top, "act_stain" if face_up else "act_back", (0, 1, 0))
        mb.poly(bot, "act_back", (0, -1, 0))
        for i in range(len(poly)):
            j = (i + 1) % len(poly)
            mx, mz = (bot[i][0] + bot[j][0]) / 2 - ox, (bot[i][2] + bot[j][2]) / 2 - oz
            mb.poly([bot[i], bot[j], top[j], top[i]], "act_back", (mx, 0, mz))
        height = max(p[1] for p in top) - floor_y
        out.append((mb, height))
    return out


def plan_all():
    return [plan_zone(z) for z in ZONES]


# ---------------------------------------------------------------- Blender side
def _c_lin(c):
    c /= 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _b(p):
    return ((p[0] - OX) * S, -p[2] * S, p[1] * S)


def _mat(key):
    if key == "ceiling_rings":
        # Reuse the decay package's exact decal/export convention without running its builder.
        m = bpy.data.materials.get("L4C_M_ceiling_rings")
        if m is not None:
            return m
        fn = next(n for n in _decay_ast.body if isinstance(n, ast.FunctionDef) and n.name == "_fd_decal")
        for n in ast.walk(fn):
            if isinstance(n, ast.Constant) and n.value == "L4S_DECAL_":
                n.value = "L4C_M_"                # leave F's material untouched on a B-only rebuild
        ns = dict(bpy=bpy, _fd_os=os, _FD_TEX=TEX)
        exec(compile(ast.Module(body=[fn], type_ignores=[]), "props_decay._fd_decal", "exec"), ns)
        return ns["_fd_decal"]("ceiling_rings", .85)
    name, tint = MATS[key]
    base = slot(name, tint, uv="mesh" if name == "ACT_2x4" else "box")  # noqa: F821 (slots.py)
    if key.startswith("lens_") and key != "lens_dead":
        mname = "L4C_M_" + key
        m = bpy.data.materials.get(mname)
        if m is None:
            m = base.copy(); m.name = mname
            m.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = 2.2
            m["l4_emit"] = 2.2
        return m
    return base


def _coll(name, parent):
    c = bpy.data.collections.get(name)
    if c is None:
        c = bpy.data.collections.new(name)
        parent.children.link(c)
    return c


def _mkobj(mb, name, coll):
    if not mb.F:
        return None
    V = np.array(mb.V, float)
    B = np.stack([(V[:, 0] - OX) * S, -V[:, 2] * S, V[:, 1] * S], 1)
    me = bpy.data.meshes.new(name)
    me.from_pydata(B.tolist(), [], mb.F)
    for k in mb.mats:
        me.materials.append(_mat(k))
    me.polygons.foreach_set("material_index", mb.M)
    me.polygons.foreach_set("use_smooth", mb.SM)
    if "ceiling_rings" in mb.mats or any(MATS.get(k, (None,))[0] == "ACT_2x4" for k in mb.mats):
        uv = me.uv_layers.new(name="UVMap")
        for p in me.polygons:
            key = mb.mats[p.material_index]
            if MATS.get(key, (None,))[0] == "ACT_2x4":
                for li, vi in zip(p.loop_indices, p.vertices):
                    x, _, z = mb.V[vi]
                    uv.data[li].uv = ((x - OX) / 4, z / 4)
            elif key == "ceiling_rings":
                verts = [mb.V[v] for v in p.vertices]
                x0, x1 = min(v[0] for v in verts), max(v[0] for v in verts)
                z0, z1 = min(v[2] for v in verts), max(v[2] for v in verts)
                for li, vi in zip(p.loop_indices, p.vertices):
                    x, _, z = mb.V[vi]
                    uv.data[li].uv = ((x - x0) / (x1 - x0), (z - z0) / (z1 - z0))
    if any(mb.SM):
        try:
            me.set_sharp_from_angle(angle=math.radians(35))
        except Exception:
            pass
    me.update()
    o = bpy.data.objects.new(name, me)
    coll.objects.link(o)
    return o


def _lens_mesh(shape, mat):
    name = "L4C_FlickerLens_%s_%s" % (shape, mat)
    me = bpy.data.meshes.get(name)
    if me:
        return me
    if shape == "troffer":                        # unit rectangle in local metres (X long), facing -Z
        v = [(-0.5, -0.5, 0), (-0.5, 0.5, 0), (0.5, 0.5, 0), (0.5, -0.5, 0)]
        f = [list(range(4))]
    elif shape == "bar":                          # round eight-segment neon tube along local X
        v = [(x, .5 * math.cos(2 * math.pi * k / 8), .5 * math.sin(2 * math.pi * k / 8))
             for x in (-.5, .5) for k in range(8)]
        f = [[k, (k + 1) % 8, (k + 1) % 8 + 8, k + 8] for k in range(8)]
        f += [list(reversed(range(8))), list(range(8, 16))]
    else:                                         # unit disc (radius 1 m), facing -Z
        v = [(math.cos(-2 * math.pi * k / 12), math.sin(-2 * math.pi * k / 12), 0) for k in range(12)]
        f = [list(range(12))]
    me = bpy.data.meshes.new(name)
    me.from_pydata(v, [], f)
    me.materials.append(_mat(mat))
    me.update()
    return me


def _mklight(L, name, coll, host=None):
    t = L["type"]
    ld = bpy.data.lights.new(name, t)
    ld.color = tuple(_c_lin(c) for c in L["color"])
    rm = L["range"] * S
    ld.energy = LIGHT_W * max(0.2, L["b"]) * (rm / 4.0) ** 2
    ld.use_custom_distance = True
    ld.cutoff_distance = rm * 1.3
    ld.use_shadow = bool(L["shadows"])
    ld.shadow_soft_size = 0.15
    if t == "SPOT":
        ld.spot_size = math.radians(L["angle"])
        ld.spot_blend = 0.6
    elif t == "AREA":
        ld.shape = "RECTANGLE"
        ld.size, ld.size_y = L["size"][0] * S, L["size"][1] * S
    o = bpy.data.objects.new(name, ld)
    o.location = _b(L["pos"])
    coll.objects.link(o)
    o["l4_pkg"] = "ceilings"
    o["l4_kind"] = L["kind"]
    o["l4_range"] = float(L["range"])
    o["l4_brightness"] = float(L["b"])
    o["l4_shadows"] = bool(L["shadows"])
    o["l4_color"] = list(L["color"])
    if t == "AREA":
        o["l4_angle"] = float(L["angle"])
    if host is not None:
        o["l4_host"] = host.name
        if host.data.name.startswith("L4C_FlickerLens_troffer_"):
            # place.luau centres prop lights on the lens. Its native flicker holder keeps this 1.5-stud offset.
            o["l4_flicker"] = True
        else:
            o.parent = host
            o.matrix_parent_inverse = host.matrix_world.inverted()
    return o


def _old_light_replaced(i):
    lp = _L["lights"][i]
    host = lp["p"].rsplit("/", 1)[0]
    if not _replaced(host):
        return False
    return not any(_NAMES[k] == host and np.allclose(_CTR[k], lp["pos"], atol=0.05) for k in _FLICK)


def _clear():
    root = bpy.data.collections.get("L4 Cinema")
    if root is None:
        root = bpy.data.collections.new("L4 Cinema")
        bpy.context.scene.collection.children.link(root)
    mine = _coll("L4 Ceilings", root)
    lights = _coll("L4 Fixture Lights", root)
    for o in list(mine.all_objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for o in list(lights.all_objects):
        if o.get("l4_pkg") == "ceilings":
            bpy.data.objects.remove(o, do_unlink=True)
    gone = 0
    for o in list(bpy.data.objects):
        p = o.get("l4_path")
        if p and _replaced(p) and o.get("l4_src") not in _FLICK:
            bpy.data.objects.remove(o, do_unlink=True)
            gone += 1
    old = bpy.data.collections.get("L4 Lights")
    for o in (list(old.objects) if old else []):
        if o.get("l4_src_light") is not None and _old_light_replaced(int(o["l4_src_light"])):
            bpy.data.objects.remove(o, do_unlink=True)
            gone += 1
    for me in list(bpy.data.meshes):
        if me.name.startswith("L4C_") and me.users == 0:
            bpy.data.meshes.remove(me)
    for ld in list(bpy.data.lights):
        if ld.name.startswith("L4C_") and ld.users == 0:
            bpy.data.lights.remove(ld)
    for im in bpy.data.images:
        if im.name.startswith("act_2x4_") and im.source == "FILE":
            im.reload()
    return mine, lights, gone


def _floor_below(x, y, z):
    dg = bpy.context.evaluated_depsgraph_get()
    origin = _b((x, y, z))
    for _ in range(12):                          # bounded: skip thin decay overlays, not solid props
        hit, loc, nrm, face, obj, _ = bpy.context.scene.ray_cast(dg, origin, (0, 0, -1))
        if not hit:
            return None
        mat = obj.data.materials[obj.data.polygons[face].material_index] if obj.type == "MESH" and obj.data.materials else None
        if not ((mat is not None and mat.get("l4_sem") == "decal") or obj.get("l4_kind") == "puddle"):
            break
        origin = (loc.x, loc.y, loc.z - .001)
    else:
        return None
    if not hit or nrm.z < 0.8:
        return None
    idx = obj.get("l4_src")
    path = obj.get("l4_path", "")
    tags = str(_P[int(idx)].get("tags", [])) if idx is not None else str(obj.get("l4_tags", ""))
    if "Level4V4Floor" not in tags and not re.search(r"Floor|Carpet|Concrete|Runner|BaseSlab|Tread|Landing", path):
        return None
    return loc.z / S


def build_ceilings():
    """Build every ceiling zone; -> stats dict."""
    if "slot" not in globals():
        exec(open(os.path.join(HERE, "slots.py"), encoding="utf-8").read(), globals())
    mine, lcol, gone = _clear()
    plans = plan_all()
    stats = collections.Counter(deleted=gone)
    # floors for fallen tiles, before any of our own geometry exists
    falls = []
    for zp in plans:
        rng = random.Random("l4ceilfall:" + zp["z"]["name"])
        for t in zp.get("fallen", []):
            fy = _floor_below((t[0] + t[1]) / 2, zp["z"]["y"] - 0.6, (t[2] + t[3]) / 2)
            if fy is not None and abs(fy - zp["z"]["floor"]) < .6:
                shards = fallen_shards(t, fy, rng)
                corners = {(v[0], v[2]) for mb, _ in shards for v in mb.V}
                hits = [_floor_below(x, zp["z"]["y"] - .6, z) for x, z in corners]
                if all(h is not None and abs(h - fy) <= .2 for h in hits):
                    falls.append((zp["z"]["name"], shards))
    bpy.context.view_layer.update()
    for zp in plans:
        zn = zp["z"]["name"]
        mb, flick = zone_geometry(zp)
        _mkobj(mb, "L4C_" + zn, mine)
        stats["tris"] += mb.tris()
        stats["objects"] += 1
        hosts = []
        for k, f in enumerate(flick):
            o = bpy.data.objects.new("L4C_FlickerLens_%s_%d" % (zn, k), _lens_mesh(f["shape"], f["mat"]))
            o.location = _b(f["pos"])
            if f["shape"] == "troffer":
                w, l = f["size"][0] * S, f["size"][1] * S
                o.scale = (w, l, 1)                 # local X = Studio X, local Y = Studio -Z
            elif f["shape"] == "bar":
                sx, sy, sz = f["size3"]
                o.scale = (sx * S, sz * S, sy * S)  # local Z = Studio Y
            else:
                o.scale = (f["r"] * S, f["r"] * S, 1)
            o["l4_prop"] = "FlickerLens"
            o["l4_model"] = "FlickerLens"
            o["l4_attrs"] = '{"OccasionalFlicker": true}'
            mine.objects.link(o)
            hosts.append((o, f))
            stats["tris"] += sum(len(p.vertices) - 2 for p in o.data.polygons)
            stats["objects"] += 1
            stats["flicker_props"] += 1
        bpy.context.view_layer.update()
        n = 0
        for o, f in hosts:
            if f.get("light"):
                _mklight(f["light"], "L4C_L_%s_f%d" % (zn, n), lcol, host=o); n += 1
                stats["lights_flicker"] += 1
                stats["shadows"] += bool(f["light"]["shadows"])
        for L in [t["light"] for t in zp["troffers"] if t.get("light") and t["state"] != "flicker"] + \
                 [c["light"] for c in zp["cans"] if c.get("light") and c["state"] != "flicker"] + zp["lights"]:
            _mklight(L, "L4C_L_%s_%d" % (zn, n), lcol); n += 1
            stats["lights_" + L["kind"]] += 1
            stats["shadows"] += bool(L["shadows"])
        for key, v in (("troffers", len(zp["troffers"])), ("cans", len(zp["cans"])), ("missing", len(zp["holes"])),
                       ("sagging", len(zp["sag"])), ("stained", len(zp["stain"])), ("grilles", len(zp["grilles"])),
                       ("drums", sum(c.get("shape") == "drum" for c in zp["cans"])), ("caged", len(zp["cages"]))):
            stats[key] += v
        for c in zp["troffers"] + zp["cans"]:
            stats["fixtures_" + c["state"]] += 1
    for zn, shards in falls:
        for k, (mb, h) in enumerate(shards):
            o = _mkobj(mb, "L4C_FallenTile_%s_%d" % (zn, stats["fallen_shards"]), mine)
            stats["fallen_shards"] += 1
            stats["tris"] += mb.tris()
            stats["objects"] += 1
        stats["fallen_tiles"] += 1
    stats["lights"] = sum(v for k, v in stats.items() if k.startswith("lights_"))
    print("L4 ceilings:", dict(stats))
    return dict(stats)


if __name__ == "__main__":                        # planner self-check, no Blender needed
    plans = plan_all()
    tot = collections.Counter()
    for zp in plans:
        mb, flick = zone_geometry(zp)
        nm = zp["z"]["name"]
        area = int(zp["mask"].sum())
        assert area > 0, nm + ": empty ceiling"
        for t in zp["troffers"]:
            X0, X1, Z0, Z1 = t["rect"]
            assert zp["act"][int(Z0 - zp["z0"]):int(Z1 - zp["z0"]), int(X0 - zp["x0"]):int(X1 - zp["x0"])].all(), nm
            assert (X0 - OX) % zp["T"] == 0 and Z0 % zp["T"] == 0, nm + ": troffer off the tile grid"
            assert sorted((X1 - X0, Z1 - Z0)) == [2, 4], nm + ": troffer scale"
            assert (X0 - OX) % 4 == 0, nm + ": troffer not on a whole panel"
        for zone, x, z_, _, _ in LEAKS:
            if {"Men": "RestroomMen", "Women": "RestroomWomen"}.get(zone, zone) == nm:
                assert any(t[0] <= x < t[1] and t[2] <= z_ < t[3] for t in zp["stain"]), nm + ": unreserved leak"
        if nm in ("RestroomMen", "RestroomWomen"):
            assert len(zp["holes"]) == 2 and len(zp["sag"]) == 1, nm + ": restroom damage"
        fx_ = zp["troffers"] + zp["cans"]
        nl = sum(1 for f in fx_ if f.get("light")) + len(zp["lights"]) + ("frame_flicker" in zp)
        st = collections.Counter(f["state"] for f in fx_)
        assert zp["troffers"] or zp["z"]["kind"] != "act", nm + ": ACT zone without troffers"
        tot.update(area=area, troffers=len(zp["troffers"]), cans=len(zp["cans"]), lights=nl, tris=mb.tris(),
                   missing=len(zp["holes"]), sag=len(zp["sag"]), shadows=sum(bool(L["shadows"]) for L in
                   [f["light"] for f in fx_ if f.get("light")] + zp["lights"]), **st)
        print("%-18s area %6d  troffers %4d  cans %4d  lights %3d  missing %2d sag %2d stain %2d  tris %6d  %s"
              % (nm, area, len(zp["troffers"]), len(zp["cans"]), nl, len(zp["holes"]), len(zp["sag"]),
                 len(zp["stain"]), mb.tris(), dict(st)))
    fx = tot["troffers"] + tot["cans"]
    share = {k: round(tot[k] / fx, 3) for k in ("lit", "dim", "dead", "flicker")}
    print(dict(tot), share)
    assert tot["lights"] <= 160, "light budget"
    assert 0.06 < share["flicker"] < 0.1 and 0.12 < share["dead"] < 0.3 and 0.08 < share["dim"] < 0.2, share
    assert 12 <= tot["shadows"] <= 24, tot["shadows"]
    assert tot["tris"] < 250000
    print("ok")
