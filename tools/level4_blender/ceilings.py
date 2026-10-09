# Level 4 facelift v3, package P2: starlight ceilings, the Service room's Backrooms ACT, and the level's light plan.
#
# exec() slots.py, then this file, then call build_ceilings(). Idempotent: everything lives in collection
# "L4 Ceilings" (plain meshes, pooled by export_l4.py, plus FlickerLens props) and this package's lights in
# "L4 Fixture Lights" (obj["l4_pkg"] == "ceilings"); a re-run deletes and rebuilds both from the same seeds.
#
# Owner (2026-10-01, points 3 / 9 / 14): a Rolls-Royce starlight headliner everywhere except the Service room; neon is
# the primary light; some neon blinks and its area then goes dark; some lights are simply weaker; all readable.
#
#   * Star/detail footprints are rasterised at 1 stud from l4_layout.json, excluding solids, lower ceilings and the
#     removed Cinema 1 west zone. Structural decks retain exact roof extents, including over walls, coves and booths.
#   * Star zones: a near-black HEADLINER deck at the layout roof underside, so the visible ceiling and the camera stop
#     coincide (obj["l4_occluder"] + mesh["l4_col"] boxes 1 stud thick; the coffers, bulkheads and arcade frame carry
#     boxes too). Poisson-disc stars (0.08-0.25 studs, ~1 per 5 sq studs, warm / cool / dim emissive tiers, a rare faint
#     magenta or cyan one, a few tight clusters) pooled per zone and twinkle group; the materials of group k carry
#     m["l4_tags"] = "L4StarTwinkleA|B|C" (export_l4 copies material tags onto the pooled MeshParts).
#     Concourse: 4 elliptical drop coffers (magenta tube in the step reveal, cyan lip, one arc burnt out, one coffer's
#     tube is a FlickerLens). Auditoria: 4 stepped bulkheads with magenta / cyan tubes (one per room blinks). Arcade: the
#     hung black frame with magenta / cyan tubes over the old neon rectangle (its north tube blinks).
#   * Service (the Backrooms room, no stars): ACT + louvred troffers, plenum, missing / sagging / stained tiles with
#     ducts and joists over the gaps, grilles, smoke detectors, floor-verified fallen shards, caged lamps; lit / dim /
#     dead stretches and flickering lenses (FlickerLens props with a POINT light inside).
#   * light_pass() runs last and owns the level's light plan (see its docstring): cleanup of the removed zone and the
#     gallery, budgeted practicals along the neon geometry, the blink share, the star fill, the light / shadow budget.
#   * Lights (collection "L4 Fixture Lights"): l4_range (studs), l4_brightness, l4_shadows, l4_angle (AREA ->
#     SurfaceLight), l4_color, l4_kind, l4_flicker (the holder blinks). AREA / SPOT lights shine along their local -Z.
#
# `python ceilings.py` (no Blender) runs the planner and asserts the counts.
import ast, collections, colorsys, json, math, os, random, re, zlib
import numpy as np

try:
    import bpy
except ImportError:          # the planner and its self-check run in plain Python
    bpy = None

HERE = r"G:\Roblox\MongoTV\tools\level4_blender"
S, OX = 0.28, 23000.0

# Layout paths whose architecture objects this module deletes (their colliders stay where export_l4 protects them).
REPLACES = [
    r"^Concourse/Downlight$",
    r"^Concession/Downlight$",
    r"^Concession/CounterWarmLight$",
    r"^A\d/A\d_CeilingLight$",
    r"^C\d/C\d_(CeilingLens|CeilingRecess|ReturnLight)$",
    r"^C\d/C\d_StairA\d(East|West)_Light$",
    r"^Service/(CagedServiceLamp|ServiceLampCage)$",
    r"^HiddenService/(GalleryLamp|GallerySconce)$",
    r"^Shell/\w*Roof\w*$",
    r"^C\d/C\d_Roof$",
    r"^A\d/A\d_(Booth)?Roof$",
    r"^HiddenService/(GalleryRoof\w*|CoreRoof)$",
    r"^Restrooms/(Men_LowerCeiling|Women_LowerCeiling|RestroomVestibuleCeiling)$",
    r"^Restrooms/(Men|Women)_Fluorescent$",
    r"^Service/ServiceSuspendedCeiling$",
    r"^Arcade/(ArcadeCeilingNeon|ArcadeFlickerTube)$",
]

# Original preview lights of the ceiling fixtures this module removes. export_l4 leaves them out of legacyLights and
# lights_and_camera.build_lights no longer creates them.
LIGHTS_SUPERSEDED = [
    r"^Concourse/Downlight/", r"^Concession/(Downlight|CounterWarmLight)/", r"^A\d/A\d_CeilingLight/",
    r"^C\d/C\d_(ReturnLight|CeilingLens|StairA\d(East|West)_Light)/", r"^Service/CagedServiceLamp/",
    r"^HiddenService/(GalleryLamp|GallerySconce)/", r"^Restrooms/(Men|Women)_Fluorescent/",
    r"^HiddenService/(East|West)(Upper|Middle|Stair)Lamp/",
    r"^Arcade/(ArcadeCeilingNeon|ArcadeFlickerTube)/", r"^C1/",
]

# The removed Cinema 1 west zone (owner points 12/13): (x0, x1, z0, z1, y_top). Nothing of this package in there.
REMOVED = [(22600, 22676, -260, 0, 85), (22600, 22647, 0, 100, 85)]

# sRGB light colours: ~4000 K Service fluorescent, star fill (cool neutral), synthwave neon
LIGHT = {"cool": (232, 240, 234), "star": (214, 222, 240), "magenta": (255, 40, 200), "cyan": (40, 230, 255),
         "amber": (255, 158, 84), "red": (255, 44, 34), "orange": (255, 146, 72), "blue": (110, 150, 255)}
BRIGHT = {"cool": 1.1}
LIGHT_W = float(os.environ.get("L4C_LIGHT_W", 2500.0))   # shared Blender preview convention (POINT / SPOT)
AREA_K = 0.3                                              # AREA preview energy relative to a POINT of the same reach

# y = ceiling underside (studs); floor = typical floor under it (light range). Star zones: kind "star".
# Service: lights = steady light budget, heroes = shadow casters, dark / dim = shares in dark / dim stretches.
ZONES = [
    dict(name="Concourse", y=60, kind="star", floor=24, rect=(22622, 23378, -20, 102),
         seeds=[(22800, 50), (23200, 50), (23000, 20)], coffers=True, fill=1.0),
    dict(name="Concession", y=52, kind="star", floor=24, rect=(22879, 23121, 102, 240),
         seeds=[(23000, 140), (23000, 215)], fill=1.0),
    dict(name="Arcade", y=52, kind="star", floor=24, rect=(23121, 23378, 102, 240), seeds=[(23192, 175)],
         frame=True, fill=0.7),
    dict(name="Service", y=46.8, kind="act", light="cool", floor=24, rect=(22622, 22879, 102, 240),
         seeds=[(22750, 170)], missing=0.03, plenum=5.2, lights=10, heroes=2, dark=0.18, dim=0.14),
    dict(name="RestroomMen", y=40.5, kind="star", floor=24, rect=(23270, 23302, 126, 166), fill=0.8),
    dict(name="RestroomWomen", y=40.5, kind="star", floor=24, rect=(23311, 23343, 126, 166), fill=0.8),
    dict(name="RestroomVestibule", y=41, kind="star", floor=24, rect=(23270, 23343, 102, 124), fill=0.9),
] + [dict(name="C%d" % k, y=56, kind="star", floor=26, roof="C%d/C%d_Roof" % (k, k), fill=0.65 if k == 3 else 0.85)
     for k in (2, 3, 4)] \
  + [dict(name="A%d" % k, y=104, kind="star", floor=56, roof="A%d/A%d_Roof" % (k, k), bulkheads=True,
          fill=(0.8, 0.9, 0.7)[k - 1]) for k in (1, 2, 3)] \
  + [dict(name="Booth%d" % k, y=98, kind="star", floor=86, roof="A%d/A%d_BoothRoof" % (k, k), fill=0.8)
     for k in (1, 2, 3)] \
  + [dict(name="Gallery", y=99, kind="star", floor=86, roof="HiddenService/GalleryRoof", fill=1.15),
     dict(name="Core", y=100, kind="star", floor=42, roof="HiddenService/CoreRoof", fill=1.2)]

COFFERS = [(22720, 50), (22890, 50), (23110, 50), (23280, 50)]   # column pairs (x, mid z)
COFFER_AB = (32.0, 28.0)                                           # semi-axes (x, z)
COFFER_BURNT = (2, 3.6, 4.5)                                       # coffer index, cove arc (rad) whose tube is dead
COFFER_BLINK = 1                                                   # this coffer's magenta tube is a FlickerLens
COFFER_STEP = 3.0                                                  # width of the magenta step reveal
FRAME_Y = 50.3                                                     # arcade frame underside (ceiling 52)
FLICKER, SPRINKLE = 0.08, 0.04     # Service: flickering share of fixtures; random dead outside the dark stretches
DARK, DIM = 0.12, 0.12             # default dark / dim stretch shares
STRETCH_MIN = 12                   # zones with fewer fixtures get no stretches

# stars: density (per sq stud), Poisson-disc spacing, size tiers (lo, hi, share), material tiers (slot, sRGB, share)
# V6 owner selections: service pools OFF; stars at 25% in every zone.
V6_EDITS = {"item4_service_pools": False, "service_hanging_ceiling": True,
            # owner 2026-10-03: "kun selve rummet nu" -- neighbour lights stay untouched; the wall question comes later
            "service_no_incoming_bleed": False}
SERVICE_FLICKER_FIXTURE = 5       # 1..9; set to 0 for nine steady fixtures.
SERVICE_CEILING_Y, SERVICE_FIXTURE_Y = 51.2, 48.2
SERVICE_FIXTURE_SIZE = (20.0, 3.0)
SERVICE_FIXTURE_POSITIONS = [(x, SERVICE_FIXTURE_Y, z) for z in (134.0, 170.0, 206.0)
                            for x in (22666.0, 22751.0, 22836.0)]
SERVICE_LIGHT_RANGE, SERVICE_LIGHT_ANGLE, SERVICE_LIGHT_B = 36.0, 58.0, 1.0
SERVICE_LIGHT_FACE_OFFSET = .60  # Emitting Bottom face inside housing; holder centre is another .1 above.
STAR_DENSITY = 0.25              # owner-selected density for every star ceiling
STAR_PER_SQ_STUD, STAR_R = 0.2, 1.15
V6_PLACE_RANGE_GAIN = 1.56       # make_place's existing gain; geometry must contain the final Roblox reach
STAR_SIZES = ((0.08, 0.11, .5), (0.11, 0.15, .3), (0.15, 0.2, .15), (0.2, 0.25, .05))
STAR_TIERS = (("warm", "EMIT_STAR", (255, 244, 225), .44), ("cool", "EMIT_STAR_COOL", (220, 232, 255), .34),
              ("dim", "EMIT_STAR", (150, 142, 130), .2), ("rare_m", "EMIT_MAGENTA", (170, 70, 150), .01),
              ("rare_c", "EMIT_CYAN", (70, 160, 180), .01))
GROUPS = "ABC"
# slots this module needs when slots.py does not define them yet (P1 owns the real entries)
SLOT_FALLBACK = {
    "HEADLINER": ("headliner_suede", 1.0, (14, 12, 18), 0.95, 0, "Fabric", "velvet"),
    "EMIT_STAR": (None, 1.0, (255, 244, 225), 0.5, 0, "Neon", "neon"),
    "EMIT_STAR_COOL": (None, 1.0, (220, 232, 255), 0.5, 0, "Neon", "neon"),
}

# light plan (light_pass)
BUDGET, SHADOW_MAX = 260, 6        # every exported light (fixture + legacy) / shadow casters
BLINK = (0.12, 0.18)               # share of neon light groups that blink
STAR_B = 0.22                      # star fill brightness (Roblox), x zone fill, +-40 % smooth field
NEON_B = 1.0                       # neon practical brightness (Roblox)
GALLERY_LIGHT = (255, 184, 122)     # warm cove output; visible orange neon materials stay unchanged
CORE_LAMP = re.compile(r"^HiddenService/(East|West)(Upper|Middle|Stair)Lamp/")
SEG_LEN = 44.0                     # longest neon run one practical covers (studs)
PROP_LIGHT = re.compile(r"CRT|Marquee|Screen|Menu|Candy|Popcorn|Kettle|Exit|Projector|Prize|Workbench|Sign|Kick|"
                        r"Ticket|Register|Soda|Locker|Board", re.I)


def _lens(state, lens_m):
    """Fixture state -> lens material key (a flicker lens is its own object)."""
    return {"lit": lens_m, "dim": lens_m + "_dim", "dead": "lens_dead", "flicker": None}[state]


# material key -> slot(name, tint)
MATS = {
    "act": ("ACT_2x4", None), "act_stain": ("ACT_2x4", (182, 164, 130)), "act_back": ("CONCRETE_SEALED", (118, 110, 96)),
    "plenum": ("DECK_BLACK", (10, 10, 10)),
    "frame": ("PORCELAIN", (214, 210, 198)), "lens_dead": ("PORCELAIN", (100, 97, 90)),
    "lens_cool": ("EMIT_COOL", LIGHT["cool"]), "lens_cool_dim": ("EMIT_COOL", (106, 110, 116)),
    "trim": ("CHROME_PITTED", None), "brass": ("BRASS_AGED", None), "baffle": ("PLASTIC_BLACK", None),
    "headliner": ("HEADLINER", None), "coffer": ("HEADLINER", (40, 32, 46)), "bulkhead": ("HEADLINER", (40, 32, 46)),
    "neon_m": ("EMIT_MAGENTA", None), "neon_c": ("EMIT_CYAN", None), "neon_dead": ("PORCELAIN", (74, 62, 76)),
    "cable": ("STEEL_PAINTED", None), "duct": ("CHROME_PITTED", (150, 150, 146)), "joist": ("STEEL_PAINTED", (60, 58, 56)),
    "tbar": ("PORCELAIN", (196, 192, 182)), "soffit": ("PLASTIC_BLACK", None),
    "lens_service_v6": ("EMIT_COOL", (104, 118, 99)),
}
STAR_TAG = {}
for _t, _sl, _rgb, _ in STAR_TIERS:
    for _k, _g in enumerate(GROUPS):      # one material per tier and twinkle group (the blue channel keeps names apart)
        MATS["star_%s_%s" % (_t, _g)] = (_sl, (_rgb[0], _rgb[1], max(0, _rgb[2] - _k)))
        STAR_TAG["star_%s_%s" % (_t, _g)] = "L4StarTwinkle" + _g

# ---------------------------------------------------------------- layout
_L = json.load(open(os.path.join(HERE, "l4_layout.json")))
_P = _L["parts"]
# Read the authoritative dressing positions without importing/running the other package.
_decay_ast = ast.parse(open(os.path.join(HERE, "props_decay.py"), encoding="utf-8").read())
LEAKS = next((ast.literal_eval(n.value) for n in ast.walk(_decay_ast) if isinstance(n, ast.Assign)
              and any(isinstance(t, ast.Name) and t.id == "leaks" for t in n.targets)), [])
_NAMES = [p["p"] for p in _P]
_ROT = np.array([p["cf"][3:] for p in _P], float).reshape(-1, 3, 3)
_EXT = np.einsum("nij,nj->ni", np.abs(_ROT), np.array([p["s"] for p in _P], float))
_CTR = np.array([p["cf"][:3] for p in _P], float)
_LO, _HI = _CTR - _EXT / 2, _CTR + _EXT / 2
_REP = [re.compile(r) for r in REPLACES]
_SUP = [re.compile(r) for r in LIGHTS_SUPERSEDED]
_CEIL = re.compile(r"^Shell/\w*Roof\w*$|^C\d/C\d_Roof$|^A\d/A\d_(Booth)?Roof$|^HiddenService/(GalleryRoof\w*|CoreRoof)$"
                   r"|^Restrooms/(Men_LowerCeiling|Women_LowerCeiling|RestroomVestibuleCeiling)$"
                   r"|^Service/ServiceSuspendedCeiling$")
_CEIL_IDX = [i for i, n in enumerate(_NAMES) if _CEIL.search(n)]
# The v4 gallery grows south over the concourse roof. Classify its practicals from the physical roof parts,
# while keeping booth/core interiors on their own light plans even where roof rectangles overlap.
_GALLERY_ROOFS = [i for i, n in enumerate(_NAMES) if n.startswith("HiddenService/GalleryRoof") and _P[i]["t"] < .95]
_GALLERY_INTERIORS = [i for i, n in enumerate(_NAMES)
                      if re.match(r"A\d/A\d_BoothFloor$|HiddenService/CoreRoof$", n) and _P[i]["t"] < .95]


def _replaced(path):
    return any(r.search(path) for r in _REP)


_OBST = np.array([p["t"] < 0.95 and p["m"] != "Neon" and not n.startswith("AutomaticDoors/") and not _replaced(n)
                  for p, n in zip(_P, _NAMES)]) & (np.minimum(_EXT[:, 0], _EXT[:, 2]) >= 0.25)
_OBST[_CEIL_IDX] = False
_ARC_NEON = [i for i, n in enumerate(_NAMES) if n == "Arcade/ArcadeCeilingNeon"]


def _tile():
    sl = globals().get("SLOTS")
    return int(round((sl["ACT_2x4"][1] if sl else 1.232) / S / 2))   # short edge; each ACT panel is 2T x T


def in_removed(x, y, z):
    return any(a <= x <= b and c <= z <= d and y < t for a, b, c, d, t in REMOVED)


def in_gallery(x, y, z):
    return 85 <= y <= 100 and any(_LO[i, 0] <= x <= _HI[i, 0] and _LO[i, 2] <= z <= _HI[i, 2]
                                  for i in _GALLERY_ROOFS) and not any(
        _LO[i, 0] < x < _HI[i, 0] and _LO[i, 2] < z < _HI[i, 2] for i in _GALLERY_INTERIORS)


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


def _close(m, r):
    return _erode(np.pad(_dilate(np.pad(m, r), r), r), r)[2 * r:-2 * r, 2 * r:-2 * r]


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
        # A booth roof closes the booth, but its open space above still needs the auditorium's upper deck.
        if _NAMES[k] == "%s/%s_BoothRoof" % (z["name"], z["name"]):
            continue
        if y - 13 < _HI[k, 1] <= y + 0.01 and _LO[k, 1] < y - 0.01:
            _stamp(m, x0, z0, _LO[k], _HI[k], False)
    for a, b, c, d, top in REMOVED:
        if y < top:
            _stamp(m, x0, z0, (a, 0, c), (b, 0, d), False)
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
        if z["name"] == "Gallery":
            z["rect"] = (int(math.floor(_LO[_GALLERY_ROOFS, 0].min())), int(math.ceil(_HI[_GALLERY_ROOFS, 0].max())),
                         int(math.floor(_LO[_GALLERY_ROOFS, 2].min())), int(math.ceil(_HI[_GALLERY_ROOFS, 2].max())))
    if "seeds" not in z:
        x0, x1, z0, z1 = z["rect"]
        z["seeds"] = [((x0 + x1) / 2, (z0 + z1) / 2)]
    return z


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
    """Smooth zone-seeded field over (x, z) in [-1, 1]: three plane waves, wavelengths 90-220 studs."""
    rng = random.Random("l4field:" + name)
    w = []
    for _ in range(3):
        th, lam = rng.uniform(0, math.pi), rng.uniform(90, 220)
        w.append((math.cos(th) * 2 * math.pi / lam, math.sin(th) * 2 * math.pi / lam, rng.uniform(0, 2 * math.pi)))
    return lambda x, z: sum(math.cos(kx * x + kz * z + ph) for kx, kz, ph in w) / 3


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


def _point(pos, col, rng_p, b, kind, shadows=False):
    return dict(type="POINT", pos=pos, color=LIGHT[col] if isinstance(col, str) else tuple(col), range=rng_p, b=b,
                kind=kind, shadows=shadows)


def _area(pos, col, rng_p, b, kind, size, face=(0, -1, 0), along=(1, 0, 0), angle=90):
    return dict(type="AREA", pos=pos, color=LIGHT[col] if isinstance(col, str) else tuple(col), range=rng_p, b=b,
                kind=kind, shadows=False, size=size, face=face, along=along, angle=angle)


def _poisson(free, x0, z0, n, r, seed):
    """Dart throwing over the free 1-stud cells: up to n points at least r apart -> [(x, z)]."""
    cells = np.argwhere(free)
    if not len(cells) or n <= 0:
        return []
    g = np.random.default_rng(seed)
    m = 3 * n
    pick = cells[g.integers(0, len(cells), m)]
    pts = np.stack([x0 + pick[:, 1] + g.random(m), z0 + pick[:, 0] + g.random(m)], 1).tolist()
    cs, r2 = r / math.sqrt(2), r * r                # a grid cell holds at most one point
    grid, out = {}, []
    for x, zz in pts:
        gx, gz = int(math.floor(x / cs)), int(math.floor(zz / cs))
        if (gx, gz) in grid:
            continue
        ok = True
        for dx in (-2, -1, 0, 1, 2):
            for dz in (-2, -1, 0, 1, 2):
                q = grid.get((gx + dx, gz + dz))
                if q is not None and (q[0] - x) ** 2 + (q[1] - zz) ** 2 < r2:
                    ok = False
                    break
            if not ok:
                break
        if ok:
            grid[(gx, gz)] = (x, zz)
            out.append((x, zz))
            if len(out) >= n:
                break
    return out


def _pick(rng, table, k):
    u, acc = rng.random(), 0.0
    for row in table:
        acc += row[k]
        if u < acc:
            return row
    return table[0]


def _make_stars(pts, y, rng, small=False):
    """-> [(x, z, y, size, tier, group, yaw)]: size tiers, material tiers and twinkle groups at random."""
    out = []
    for x, zz in pts:
        lo, hi, _ = STAR_SIZES[0] if small else _pick(rng, STAR_SIZES, 2)
        s = rng.uniform(lo, hi)
        tier = _pick(rng, STAR_TIERS, 3)[0]
        if tier.startswith("rare"):
            s = min(s, 0.13)
        out.append((x, zz, y, s, tier, rng.choice(GROUPS), rng.uniform(0, math.pi / 2)))
    return out


def _clusters(free, x0, z0, y, rng, n):
    """n tight clusters of 5-10 small stars (a hint of constellations)."""
    cells = np.argwhere(_erode(free, 3))
    out = []
    for _ in range(n if len(cells) else 0):
        r, c = cells[rng.randrange(len(cells))]
        cx, cz = x0 + c + .5, z0 + r + .5
        pts = []
        while len(pts) < rng.randint(5, 10):
            a, d = rng.uniform(0, 2 * math.pi), rng.uniform(0.3, 2.2)
            p = (cx + d * math.cos(a), cz + d * math.sin(a))
            if all((p[0] - q[0]) ** 2 + (p[1] - q[1]) ** 2 > 0.3 ** 2 for q in pts):
                pts.append(p)
        out += _make_stars(pts, y, rng, small=True)
    return out


def v6_thin_stars(stars, density=None):
    """Keep the original 100% set; lower densities are nested, spatially spread, balanced A/B/C subsets."""
    density = STAR_DENSITY if density is None else float(density)
    assert 0 <= density <= 1, 'STAR_DENSITY must be between 0 and 1'
    if density == 1:
        return stars
    target = round(len(stars) * density)
    groups = [[i for i, s in enumerate(stars) if s[5] == g] for g in GROUPS]
    counts = [min(len(ids), target // 3 + (k < target % 3)) for k, ids in enumerate(groups)]
    # Near 100%, a group's original population can limit exact equality; keep its tags and the requested count.
    while sum(counts) < target:
        k = min((k for k in range(3) if counts[k] < len(groups[k])), key=lambda k: counts[k])
        counts[k] += 1
    keep = set()
    for k, ids in enumerate(groups):
        # Existing farthest-point planner: every prefix is evenly spread, so percentages compare the same stars.
        keep.update(ids[i] for i in _fps([(stars[i][0], stars[i][1]) for i in ids], counts[k]))
    return [s for i, s in enumerate(stars) if i in keep]


def plan_star(z):
    """Starlight zone: deck mask, coffers / bulkheads / frame, stars, deck colliders and the zone's neon lights."""
    z = _zone_rect(dict(z))
    rng = random.Random("l4star:" + z["name"])
    x0, x1, z0, z1 = z["rect"]
    y = z["y"]
    yd = y
    mask = _zone_mask(z)
    # Decorative solids and lower ceilings do not remove the structural roof above them. Keep exact extents here;
    # the one-stud placement raster otherwise leaves stair-step slots alongside curved coves and thin fascias.
    decks = []
    for i in _CEIL_IDX:
        if abs(_LO[i, 1] - y) < .06:
            lo = (max(x0, _LO[i, 0]), yd, max(z0, _LO[i, 2]))
            hi = (min(x1, _HI[i, 0]), yd + 1, min(z1, _HI[i, 2]))
            if lo[0] < hi[0] and lo[2] < hi[2]:
                assert not any(y < top and max(lo[0], a) < min(hi[0], b) and max(lo[2], c) < min(hi[2], d)
                               for a, b, c, d, top in REMOVED), z["name"] + ": roof in removed zone"
                decks.append((lo, hi))
    zp = dict(z=z, x0=x0, z0=z0, mask=mask, coffers=[], bulkheads=[], stars=[], lights=[], cols=[], columns=[],
              blink_bulkhead=None, decks=decks)
    block = np.zeros_like(mask)
    if z.get("coffers"):
        colpts = [(_CTR[i, 0], _CTR[i, 2]) for i, n in enumerate(_NAMES) if n == "Concourse/ConcourseColumn"]
        zp["columns"] = colpts
        near_col = np.zeros_like(mask)
        for cx, cz in colpts:
            near_col |= _ellipse_mask(mask.shape, x0, z0, cx, cz, 5.5, 5.5)
        for gi, (cx, cz) in enumerate(COFFERS):
            f = 1.0
            while f > 0.6:                        # shrink a coffer that would cut into a mass
                e = _ellipse_mask(mask.shape, x0, z0, cx, cz, COFFER_AB[0] * f + 1, COFFER_AB[1] * f + 1)
                if (mask | near_col)[e].all():
                    break
                f -= 0.02
            a, b = COFFER_AB[0] * f, COFFER_AB[1] * f
            zp["coffers"].append((cx, cz, a, b))
            block |= _ellipse_mask(mask.shape, x0, z0, cx, cz, a + 1, b + 1)
            disc = _ellipse_mask(mask.shape, x0, z0, cx, cz, a - COFFER_STEP - 1.6, b - COFFER_STEP - 1.6) & ~near_col
            pts = _poisson(disc, x0, z0, int(disc.sum() * STAR_PER_SQ_STUD), STAR_R, zlib.crc32(b"coffer%d" % gi))
            zp["stars"] += _make_stars(pts, y - 2.0 - 0.012, rng)
            # magenta wash from the step reveal, N and S; the blinking coffer gets one light inside its tube prop
            if gi == COFFER_BLINK:
                L = _point((cx, y - 3.0, cz), "magenta", 30, 1.1, "cove")
                zp["lights"].append(dict(L, host="coffer%d" % gi))
                continue
            for th in (math.pi / 2, math.pi * 3 / 2):
                if gi == COFFER_BURNT[0] and COFFER_BURNT[1] <= th <= COFFER_BURNT[2]:
                    continue
                nx, nz = math.cos(th) / a, math.sin(th) / b
                ln = math.hypot(nx, nz)
                zp["lights"].append(_point((cx + a * math.cos(th) - 1.5 * nx / ln, y - 2.8,
                                            cz + b * math.sin(th) - 1.5 * nz / ln), "magenta", 22, 0.9, "cove"))
            zp["cols"] += [((cx - .92 * (a - COFFER_STEP - .9), y - 1.9, cz - .38 * (b - COFFER_STEP - .9)),
                            (cx + .92 * (a - COFFER_STEP - .9), yd, cz + .38 * (b - COFFER_STEP - .9))),
                           ((cx - .38 * (a - COFFER_STEP - .9), y - 1.9, cz - .92 * (b - COFFER_STEP - .9)),
                            (cx + .38 * (a - COFFER_STEP - .9), yd, cz + .92 * (b - COFFER_STEP - .9)))]
        for gi, (cx, cz, a, b) in enumerate(zp["coffers"]):
            if gi == COFFER_BLINK:                 # the loop above skipped its colliders with the `continue`
                w = a - COFFER_STEP - .9; h = b - COFFER_STEP - .9
                zp["cols"] += [((cx - .92 * w, y - 1.9, cz - .38 * h), (cx + .92 * w, yd, cz + .38 * h)),
                               ((cx - .38 * w, y - 1.9, cz - .92 * h), (cx + .38 * w, yd, cz + .92 * h))]
    if z.get("bulkheads"):
        zb = [z0 + 44 * k for k in (1, 2, 3, 4)]
        zp["blink_bulkhead"] = rng.randrange(len(zb))
        for i, bz in enumerate(zb):
            r = int(bz - z0)
            c = np.nonzero(mask[r])[0]
            if not len(c):
                continue
            bx0, bx1 = x0 + c.min() - 0.3, x0 + c.max() + 1.3
            zp["bulkheads"].append((bx0, bx1, bz))
            block[max(0, r - 8):r + 8, :] = True
            # The lower face is also a star headliner, rather than a broad empty stripe.
            strip = np.zeros_like(mask)
            strip[max(0, r - 4):r + 4, :] = True
            strip &= mask
            pts = _poisson(strip, x0, z0, int(strip.sum() * STAR_PER_SQ_STUD), STAR_R,
                           zlib.crc32((z['name'] + ':bulkhead%d' % i).encode()))
            zp['stars'] += _make_stars(pts, y - 3.612, rng)
            zp["cols"] += [((bx0, y - 1.82, bz - 7.0), (bx1, yd, bz + 7.0)), ((bx0, y - 3.6, bz - 4.6), (bx1, y - 1.82, bz + 4.6))]
            for side, col in ((1, "magenta"), (-1, "cyan")):   # a wash from each face's reveal, outward and down
                L = _area(((bx0 + bx1) / 2, y - 2.4, bz + side * 5.3), col, 30, 0.6, "cove", (bx1 - bx0 - 6, 0.4),
                          face=(0, -0.55, side * 0.835))
                if len(zp["bulkheads"]) - 1 == zp["blink_bulkhead"]:
                    L["host"] = "bulkhead"
                zp["lights"].append(L)
    if z.get("frame"):
        lo, hi = _LO[_ARC_NEON].min(0), _HI[_ARC_NEON].max(0)
        fx0, fx1, fz0, fz1 = lo[0], hi[0], lo[2], hi[2]
        zp["frame"] = (fx0, fx1, fz0, fz1)
        w = 1.4
        for a_, b_ in (((fx0 - w, fz0 - w), (fx1 + w, fz0 + w)), ((fx0 - w, fz1 - w), (fx1 + w, fz1 + w)),
                       ((fx0 - w, fz0), (fx0 + w, fz1)), ((fx1 - w, fz0), (fx1 + w, fz1))):
            _stamp(block, x0, z0, (a_[0], 0, a_[1]), (b_[0], 0, b_[1]), True, 0.6)
            zp["cols"].append(((a_[0], FRAME_Y, a_[1]), (b_[0], yd, b_[1])))
        for zc in (fz0 + 5.15, fz1 - 5.15):
            _stamp(block, x0, z0, (fx0, 0, zc - 0.6), (fx1, 0, zc + 0.6), True, 0.6)
        fy = FRAME_Y - 1.2
        zp["lights"] += [_point(((fx0 + fx1) / 2, fy, fz0 + 3), "magenta", 26, 0.8, "frame", shadows=True),
                         _point(((fx0 + fx1) / 2, fy, (fz0 + fz1) / 2), "cyan", 22, 0.6, "frame")]
        zp["frame_flicker"] = _point(((fx0 + fx1) / 2, fy, fz1 - 0.2), "magenta", 22, 0.8, "frame")
    free = _erode(mask, 1) & ~block
    pts = _poisson(free, x0, z0, int(free.sum() * STAR_PER_SQ_STUD), STAR_R, zlib.crc32(z["name"].encode()))
    zp["stars"] += _make_stars(pts, yd - 0.012, rng)
    zp["stars"] += _clusters(free, x0, z0, yd - 0.012, rng, int(free.sum() // 6000) + (free.sum() > 800))
    zp["stars"] = v6_thin_stars(zp["stars"])
    # Every deck collider lies behind the matching visible underside, rather than spanning holes in a raster mask.
    zp["cols"] += decks
    return zp


def plan_act(z):
    """Service: the Backrooms ACT room (troffers, damage, caged lamps, lit / dim / dead / flicker states)."""
    z = _zone_rect(dict(z))
    rng = random.Random("l4ceil:" + z["name"])
    T = _tile()
    x0, x1, z0, z1 = z["rect"]
    y = z["y"]
    mask = _zone_mask(z)
    zp = dict(z=z, x0=x0, z0=z0, mask=mask, T=T, act=mask.copy(), troffers=[], holes=[], sag=[], stain=[],
              cages=[], lights=[], grilles=[], detectors=[], plenum=z.get("plenum", 3.0), orient="x")
    block = np.zeros_like(mask)
    for leak_zone, lx, lz, _, _ in LEAKS:
        if leak_zone == z["name"]:
            tx = OX + math.floor((lx - OX) / (2 * T)) * 2 * T
            tz = math.floor(lz / T) * T
            t = (tx, tx + 2 * T, tz, tz + T)
            zp["stain"].append(t)
            block |= _cells([t], x0, z0, mask.shape, 1)
    act = zp["act"]
    for i, n in enumerate(_NAMES):
        if n == "Service/CagedServiceLamp":
            zp["cages"].append((_CTR[i, 0], _CTR[i, 2]))
            _stamp(block, x0, z0, _LO[i], _HI[i], True, 2)
    troffers = _troffer_slots(act, x0, z0, T, z.get("pitch", (4, 4)), "x", block, z.get("clear", 2))
    zp["troffers"] = [dict(rect=t, x=(t[0] + t[1]) / 2, z=(t[2] + t[3]) / 2) for t in troffers]
    tro = _cells(troffers, x0, z0, act.shape, 0)
    cand = _free_tiles(act, x0, z0, T, block | tro, 3)
    rng.shuffle(cand)
    ntiles = act.sum() / (2 * T * T)
    miss = z.get("missing", 0.01)
    want = [max(1 if miss and ntiles > 60 else 0, round(miss * ntiles)),
            max(1 if miss and ntiles > 120 else 0, round(0.5 * miss * ntiles)),
            round(0.02 * ntiles)]
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
    for t in cand:                                # slotted return-air grilles, ~1 per 80 tiles
        if len(zp["grilles"]) >= round(0.012 * ntiles):
            break
        c0, r0 = int(t[0] - x0), int(t[2] - z0)
        if not taken[max(0, r0 - T):r0 + 2 * T, max(0, c0 - T):c0 + 2 * T].any():
            zp["grilles"].append(t)
            taken[r0:r0 + T, c0:c0 + 2 * T] = True
    block |= _cells(zp["holes"] + zp["sag"] + zp["grilles"], x0, z0, act.shape, 1) | tro
    for px, pz in _grid_points(mask, x0, z0, 28, 28, block, 3):     # smoke detectors, clear of fixtures
        zp["detectors"].append((px + rng.uniform(-3, 3), pz + rng.uniform(-3, 3)))
    _assign_states(zp["troffers"], z, rng)
    rng_lt = min(60.0, y - z["floor"] + 10)
    ya = y - 0.08
    # flicker lights share the allocation: about a third of the blinking lenses get one, then steady troffers
    fx = zp["troffers"]
    flickers = [f for f in fx if f["state"] == "flicker"]
    chosen = {id(flickers[k]) for k in _fps([(f["x"], f["z"]) for f in flickers], round(len(flickers) * .45))}
    blinking = [f for f in fx if id(f) in chosen]
    steady = [f for f in fx if f["state"] == "lit"]
    budget = max(0, z.get("lights", 0) - len(zp["cages"]))
    pick = [blinking[k] for k in _fps([(f["x"], f["z"]) for f in blinking], budget)]
    pick += [steady[k] for k in _fps([(f["x"], f["z"]) for f in steady], max(0, budget - len(pick)))]
    for n, f in enumerate(pick):
        X0, X1, Z0, Z1 = f["rect"]
        f["light"] = _point(((X0 + X1) / 2, ya - 1.53, (Z0 + Z1) / 2), z["light"], rng_lt, BRIGHT[z["light"]],
                            "flicker" if f["state"] == "flicker" else "troffer", shadows=n < z.get("heroes", 0))
    for px, pz in zp["cages"]:
        zp["lights"].append(_point((px, ya - 1.1, pz), "cool", 30, .7, "caged"))
    if V6_EDITS["item4_service_pools"] and z['name'] == 'Service':
        v6_service_pool_plan(zp)
    return zp


def v6_service_bounds():
    """Exact inner wall finishes from the authoritative layout, including the north doorway's closed envelope."""
    west = [i for i, n in enumerate(_NAMES) if n == 'Service/ServiceWestWallFinish']
    east = [i for i, n in enumerate(_NAMES) if n == 'Service/ServiceEastWallFinish']
    north = [i for i, n in enumerate(_NAMES) if n == 'Service/ServiceNorthWallFinish']
    south = [i for i, n in enumerate(_NAMES) if n == 'Service/ServiceSouthWallFinish']
    return (max(_HI[west, 0]), min(_LO[east, 0]), max(_HI[north, 2]), min(_LO[south, 2]))


def v6_service_pool_plan(zp):
    """Item 4: one third visible lenses, six modest downward pools; dark cages do not wash the ceiling."""
    fx = zp['troffers']
    on = _spread([(f['x'], f['z']) for f in fx], round(len(fx) / 3), random.Random('v6_service_lenses'))
    for k, f in enumerate(fx):
        f['state'] = 'lit' if k in on else 'dead'
        f.pop('light', None)
    a, b, c, d = v6_service_bounds()
    eligible = [k for k in on if min(fx[k]['x'] - a, b - fx[k]['x'], fx[k]['z'] - c, d - fx[k]['z']) > 15.0]
    pools = [eligible[k] for k in _fps([(fx[k]['x'], fx[k]['z']) for k in eligible], 6)]
    for n, k in enumerate(pools):
        f = fx[k]
        f['state'] = 'flicker' if n in (1, 4) else 'lit'
        f['light'] = dict(_point((f['x'], zp['z']['y'] - 1.61, f['z']), 'cool',
                                30 / V6_PLACE_RANGE_GAIN, .45, 'troffer', shadows=False),
                          type='SPOT', face=(0, -1, 0), angle=52)
    candidates = [k for k in on if k not in pools]
    for j in _fps([(fx[k]['x'], fx[k]['z']) for k in candidates], 12):
        fx[candidates[j]]['state'] = 'flicker'
    zp['lights'] = []
    zp['v6_service_states'] = dict(collections.Counter(f['state'] for f in fx))


def plan_zone(z):
    return plan_act(z) if z["kind"] == "act" else plan_star(z)


# ---------------------------------------------------------------- geometry (pure python, Studio studs)
def star_geometry(zp):
    """-> (pooled _MB of the zone, {group: stars _MB}, flicker props)."""
    z, x0, z0 = zp["z"], zp["x0"], zp["z0"]
    y = z["y"]
    yd = y
    mb = _MB()
    flick = []
    for lo, hi in zp["decks"]:
        mb.box(lo, hi, "headliner")
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
        if gi == COFFER_BLINK:
            pm = _MB()
            _tube(pm, path, nrm, -w + 0.16, y - 1.17, 0.13, lambda i: "neon_m")
            flick.append(dict(mb=pm, pos=(cx, y - 1.17, cz), host="coffer%d" % gi))
        else:
            _tube(mb, path, nrm, -w + 0.16, y - 1.17, 0.13, lambda i: "neon_dead" if burnt(i) else "neon_m")
        _tube(mb, path, nrm, -w - 0.04, y - 1.96, 0.06, lambda i: "neon_c", seg=5)
        for px, pz in zp["columns"]:
            if ((px - cx) / a) ** 2 + ((pz - cz) / b) ** 2 < .8:
                cp = _circle(24, 4.32, px, pz)
                cn = [(math.cos(2 * math.pi * k / 24), math.sin(2 * math.pi * k / 24)) for k in range(24)]
                _sweep(mb, cp, cn, [(0, y - 1.84), (0, y - 2.16), (-.24, y - 2.16)], ["brass", "brass"])
    # auditorium bulkheads: stepped, magenta tube in the upper reveal, cyan line on the lower lip
    for i, (bx0, bx1, bz) in enumerate(zp["bulkheads"]):
        prof = [(7.0, y), (7.0, y - 1.7), (6.88, y - 1.82), (4.6, y - 1.82), (4.6, y - 2.12), (4.6, y - 3.48),
                (4.48, y - 3.6), (0.0, y - 3.6)]
        blink = i == zp["blink_bulkhead"]
        pm = _MB() if blink else mb
        for s in (1, -1):
            _sweep(mb, [(bx0, bz), (bx1, bz)], [(0, s), (0, s)], prof, ["bulkhead"] * 7, closed=False)
            _cyl(pm, (bx0 + 0.3, y - 1.97, bz + s * 4.75), (bx1 - 0.3, y - 1.97, bz + s * 4.75), 0.13, "neon_m", 6)
            _cyl(mb, (bx0 + 0.3, y - 3.54, bz + s * 4.54), (bx1 - 0.3, y - 3.54, bz + s * 4.54), 0.06, "neon_c", 5)
        for xe in (bx0, bx1):                      # end caps
            mb.poly([(xe, y, bz - 7), (xe, y - 1.82, bz - 7), (xe, y - 1.82, bz + 7), (xe, y, bz + 7)], "bulkhead",
                    (1 if xe == bx1 else -1, 0, 0))
            mb.poly([(xe, y - 1.82, bz - 4.6), (xe, y - 3.6, bz - 4.6), (xe, y - 3.6, bz + 4.6), (xe, y - 1.82, bz + 4.6)],
                    "bulkhead", (1 if xe == bx1 else -1, 0, 0))
        if blink:
            flick.append(dict(mb=pm, pos=((bx0 + bx1) / 2, y - 1.97, bz), host="bulkhead"))
    # arcade: black bulkhead frame on the old neon rectangle, magenta tube ring underneath, cyan tubes on two
    # crossbars; the north tube is a flicker lens
    if "frame" in zp:
        fx0, fx1, fz0, fz1 = zp["frame"]
        w, fy, ya = 1.4, FRAME_Y, yd
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
        pm = _MB()
        _cyl(pm, (fx0, yt, fz1 - 0.15), (fx1, yt, fz1 - 0.15), 0.14, "neon_m", 6)
        flick.append(dict(mb=pm, pos=((fx0 + fx1) / 2, yt, fz1 - 0.15), host="frame",
                          lights=[zp["frame_flicker"]]))
    stars = {g: _MB() for g in GROUPS}
    for x, zz, ys, s, tier, g, yaw in zp["stars"]:
        h = s / 2
        c, sn = math.cos(yaw) * h, math.sin(yaw) * h
        stars[g].poly([(x - c + sn, ys, zz - sn - c), (x + c + sn, ys, zz + sn - c), (x + c - sn, ys, zz + sn + c),
                       (x - c - sn, ys, zz - sn + c)], "star_%s_%s" % (tier, g), (0, -1, 0))
    for f in flick:                                 # lights that ride in a tube prop
        f.setdefault("lights", [])
        f["lights"] += [L for L in zp["lights"] if L.get("host") == f["host"]]
    return mb, stars, flick


def act_geometry(zp):
    """Service ACT -> (pooled _MB, flicker lens dicts)."""
    z, x0, z0, T = zp["z"], zp["x0"], zp["z0"], zp["T"]
    y = z["y"]
    ya = y - 0.08
    lens_m = "lens_service_v6" if V6_EDITS['item4_service_pools'] and z['name'] == 'Service' else "lens_" + z["light"]
    mb = _MB()
    flick = []
    rng = random.Random("l4ceilgeo:" + z["name"])
    for c0, c1, r0, r1 in _rects(_dilate(zp["mask"], 2)):     # plenum follows the room
        mb.hquad(x0 + c0, x0 + c1, z0 + r0, z0 + r1, y + zp["plenum"], "plenum")
    cut = _cells(zp["holes"] + zp["sag"] + zp["stain"] + zp["grilles"], x0, z0, zp["act"].shape)
    for c0, c1, r0, r1 in _rects(zp["act"] & ~cut):
        mb.hquad(x0 + c0, x0 + c1, z0 + r0, z0 + r1, ya, "act")
    for t in zp["stain"]:
        mb.hquad(t[0], t[1], t[2], t[3], ya, "act")
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
            _cyl(mb, (cx - 11, yc, cz + rng.uniform(-1, 1)), (cx + 11, yc, cz + rng.uniform(-1, 1)), r, "duct")
        else:                                          # a steel joist chord crosses it
            yj = y + pl - 0.7
            mb.box((cx - 0.15, yj, cz - 9), (cx + 0.15, yj + 0.35, cz + 9), "joist")
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
    for px, pz in zp["cages"]:
        path = _circle(16, 1.0, px, pz)
        normals = [(math.cos(2 * math.pi * k / 16), math.sin(2 * math.pi * k / 16)) for k in range(16)]
        _sweep(mb, path, normals, [(0, ya), (0, ya - .24), (-.18, ya - .28)], ["joist", "joist"])
        _sweep(mb, path, normals, [(-.18, ya - .28), (-.18, ya - .7), (-.45, ya - .88)],
               ["lens_dead", "lens_dead"] if lens_m == 'lens_service_v6' else ["lens_cool_dim", "lens_cool_dim"])
        mb.poly([(qx, ya - .87, qz) for qx, qz in _circle(16, .55, px, pz)],
                "lens_dead" if lens_m == 'lens_service_v6' else "lens_cool", (0, -1, 0))
        for k in range(8):
            th = 2 * math.pi * k / 8
            qx, qz = px + .94 * math.cos(th), pz + .94 * math.sin(th)
            mb.box((qx - .035, ya - .86, qz - .035), (qx + .035, ya - .2, qz + .035), "joist")
            _cyl(mb, (qx, ya - .86, qz), (px, ya - .99, pz), .035, "joist", 6)
        _tube(mb, path, normals, -.08, ya - .65, .045, lambda i: "joist", seg=6)
    for tx0, tx1, tz0, tz1 in zp["grilles"]:          # return-air grilles: frame, dark throat, 6 slats
        e, w_ = 0.04, 0.18
        _troffer(mb, tx0, tx1, tz0, tz1, ya + 0.04, None)
        mb.hquad(tx0 + e + w_, tx1 - e - w_, tz0 + e + w_, tz1 - e - w_, ya + 0.35, "baffle")
        n_ = 6
        for k in range(n_):
            u = tx0 + e + w_ + (k + 0.5) * (tx1 - tx0 - 2 * (e + w_)) / n_
            mb.box((u - 0.06, ya - 0.02, tz0 + e + w_), (u + 0.06, ya + 0.3, tz1 - e - w_), "frame",
                   skip=("+y", "-z", "+z"))
    for px, pz in zp["detectors"]:
        top = [mb.v((qx, ya, qz)) for qx, qz in _circle(10, 0.4, px, pz)]
        bot = [mb.v((qx, ya - 0.22, qz)) for qx, qz in _circle(10, 0.36, px, pz)]
        mb.ring_band(top, bot, "frame", lambda i: (math.cos(2 * math.pi * (i + .5) / 10), 0,
                                                   math.sin(2 * math.pi * (i + .5) / 10)))
        mb.f(list(bot), "frame", (0, -1, 0))
    for t in zp["troffers"]:
        X0, X1, Z0, Z1 = t["rect"]
        st = t["state"]
        I = _troffer(mb, X0, X1, Z0, Z1, ya, _lens(st, lens_m))
        _louvres(mb, I, ya)
        if st == "flicker":
            flick.append(dict(shape="troffer", mat=lens_m, pos=((I[0] + I[1]) / 2, ya - 0.03, (I[2] + I[3]) / 2),
                              size=(I[1] - I[0], I[3] - I[2]), lights=[t["light"]] if t.get("light") else []))
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


def star_fill_plan(zp, n):
    """n downward star-fill lights over the zone mask: a sparse grid of cells, one AREA light per cell."""
    z, mask, x0, z0 = zp["z"], zp["mask"], zp["x0"], zp["z0"]
    rr, cc = np.nonzero(mask)
    if not len(rr) or n <= 0:
        return []
    H, W = rr.max() - rr.min() + 1, cc.max() - cc.min() + 1

    def cells(size):
        nx, nz = max(1, round(W / size)), max(1, round(H / size))
        out = []
        for i in range(nx):
            for j in range(nz):
                c0, c1 = cc.min() + W * i // nx, cc.min() + W * (i + 1) // nx
                r0, r1 = rr.min() + H * j // nz, rr.min() + H * (j + 1) // nz
                sub = mask[r0:r1, c0:c1]
                if sub.mean() >= 0.3:
                    sr, sc = np.nonzero(sub)
                    nearest = int(np.argmin((sc - sc.mean()) ** 2 + (sr - sr.mean()) ** 2))
                    out.append((x0 + c0 + sc[nearest] + .5, z0 + r0 + sr[nearest] + .5,
                                (sc.max() - sc.min() + 1), (sr.max() - sr.min() + 1)))
        return out
    lo, hi = 6.0, float(max(W, H)) + 1
    best = cells(hi)
    for _ in range(24):                            # largest cell size that still gives >= n cells
        mid = (lo + hi) / 2
        c = cells(mid)
        if len(c) >= n:
            best, lo = c, mid
        else:
            hi = mid
    best = [best[k] for k in _fps([(c[0], c[1]) for c in best], n)]
    f = _field("fill:" + z["name"])
    y = z["y"]
    out = []
    for x, zz, sx, sz in best:
        floor = _layout_floor(x, zz, y, z['floor'])
        # Roblox range stops at 60. Concealed fill holders follow the tier height in tall rooms.
        ly = min(y - .6, floor + 50)
        rng_l = min(60.0, ly - floor + 10)
        b = STAR_B * z.get("fill", 1.0) * (1 + 0.4 * f(x, zz))
        out.append(_area((x, ly, zz), "star", rng_l, round(b, 3), "star", (min(60, sx * .8), min(60, sz * .8)),
                         angle=85))
    return out


def _layout_floor(x, z, ceiling, fallback=24):
    hits = [i for i, p in enumerate(_P) if (_LO[i, 0] <= x <= _HI[i, 0] and _LO[i, 2] <= z <= _HI[i, 2]
            and _HI[i, 1] < ceiling - 1) and ('Level4V4Floor' in p.get('tags', [])
            or re.search(r'Floor|Tier|Tread|Landing|BaseSlab', p['p']))]
    return float(max((_HI[i, 1] for i in hits), default=fallback))


# ---------------------------------------------------------------- Blender side
def _c_lin(c):
    c /= 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _lin2srgb(c):
    c = max(0.0, float(c))
    return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def _b(p):
    return ((p[0] - OX) * S, -p[2] * S, p[1] * S)


def _bdir(d):
    return (d[0], -d[2], d[1])


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
        ns = dict(bpy=bpy, _fd_os=os, _FD_TEX=TEX)  # noqa: F821 (slots.py)
        exec(compile(ast.Module(body=[fn], type_ignores=[]), "props_decay._fd_decal", "exec"), ns)
        return ns["_fd_decal"]("ceiling_rings", .85)
    name, tint = MATS[key]
    base = slot(name, tint, uv="mesh" if name == "ACT_2x4" else "box")  # noqa: F821 (slots.py)
    if key in STAR_TAG:
        base["l4_tags"] = STAR_TAG[key]
    if key.startswith("lens_") and key != "lens_dead":
        mname = "L4C_M_" + key
        m = bpy.data.materials.get(mname)
        if m is None:
            m = base.copy(); m.name = mname
            emission = .45 if key == 'lens_service_v6' else 2.2
            m.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = emission
            m["l4_emit"] = emission
        return m
    return base


def _coll(name, parent):
    c = bpy.data.collections.get(name)
    if c is None:
        c = bpy.data.collections.new(name)
        parent.children.link(c)
    return c


def _mkmesh(mb, name, origin=(0, 0, 0)):
    V = np.array(mb.V, float) - np.array(origin, float)
    B = np.stack([V[:, 0] * S, -V[:, 2] * S, V[:, 1] * S], 1)
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
    return me


def _mkobj(mb, name, coll, origin=None):
    if not mb.F:
        return None
    o = bpy.data.objects.new(name, _mkmesh(mb, name, origin or (OX, 0, 0)))
    if origin:
        o.location = _b(origin)
    coll.objects.link(o)
    return o


def _lens_mesh(shape, mat):
    name = "L4C_FlickerLens_%s_%s" % (shape, mat)
    me = bpy.data.meshes.get(name)
    if me:
        return me
    v = [(-0.5, -0.5, 0), (-0.5, 0.5, 0), (0.5, 0.5, 0), (0.5, -0.5, 0)]   # unit rectangle (X long), facing -Z
    me = bpy.data.meshes.new(name)
    me.from_pydata(v, [], [list(range(4))])
    me.materials.append(_mat(mat))
    me.update()
    return me


def _orient(face, along):
    """Rotation whose local -Z shines to Studio direction face and whose local X follows along."""
    from mathutils import Matrix, Vector
    z = -Vector(_bdir(face)).normalized()
    x = Vector(_bdir(along))
    x = (x - z * x.dot(z)).normalized()
    return Matrix((x, z.cross(x), z)).transposed().to_4x4()


def _energy(t, rng, b):
    rm = rng * S
    return LIGHT_W * max(0.0, b) * (rm / 4.0) ** 2 * (AREA_K if t == "AREA" else 1.0)


def _mklight(L, name, coll, host=None):
    from mathutils import Matrix, Vector
    t = L["type"]
    ld = bpy.data.lights.new(name, t)
    ld.color = tuple(_c_lin(c) for c in L["color"])
    ld.energy = _energy(t, L["range"], L["b"])
    ld.use_custom_distance = True
    ld.cutoff_distance = L["range"] * S * 1.3
    ld.use_shadow = bool(L["shadows"])
    ld.shadow_soft_size = 0.15
    if t == "SPOT":
        ld.spot_size = math.radians(L["angle"])
        ld.spot_blend = 0.6
    elif t == "AREA":
        ld.shape = "RECTANGLE"
        ld.size, ld.size_y = max(0.05, L["size"][0] * S), max(0.05, L["size"][1] * S)
    o = bpy.data.objects.new(name, ld)
    M = Matrix.Translation(Vector(_b(L["pos"])))
    if t != "POINT" and L.get("face"):
        M = M @ _orient(L["face"], L.get("along", (1, 0, 0)))
    o.matrix_world = M
    coll.objects.link(o)
    o["l4_pkg"] = "ceilings"
    o["l4_kind"] = L["kind"]
    o["l4_range"] = float(L["range"])
    o["l4_brightness"] = float(L["b"])
    o["l4_shadows"] = bool(L["shadows"])
    o["l4_color"] = list(L["color"])
    if t == "AREA":
        o["l4_angle"] = float(L.get("angle", 90))
    if L.get("flicker"):
        o["l4_flicker"] = True
    if host is not None:
        o["l4_host"] = host.name
        if host.data.name.startswith("L4C_FlickerLens_troffer_"):
            # place.luau centres prop lights on the lens. Its native flicker holder keeps this 1.5-stud offset.
            o["l4_flicker"] = True
        else:
            o.parent = host
            o.matrix_parent_inverse = host.matrix_world.inverted()
            o.matrix_world = M
    return o


def _module_list(name):
    """Every build module's `name` literal (like export_l4.module_list)."""
    out = []
    for fn in ("arch_detail.py", "ceilings.py", "doors_v2.py", "props_lobby.py", "props_rooms.py", "props_decay.py"):
        path = os.path.join(HERE, fn)
        if not os.path.exists(path):
            continue
        for n in ast.parse(open(path, encoding="utf-8").read()).body:
            if isinstance(n, ast.Assign) and any(isinstance(t, ast.Name) and t.id == name for t in n.targets):
                try:
                    v = ast.literal_eval(n.value)
                except ValueError:
                    continue
                out += [v] if isinstance(v, str) else list(v)
    return out


def _restore_flicker_state():
    for o in bpy.data.objects:
        if 'l4_p2_original_parent' in o:
            M = o.matrix_world.copy()
            o.parent = bpy.data.objects.get(o['l4_p2_original_parent'])
            o['l4_host'] = o.get('l4_p2_original_host', '')
            o.matrix_world = M
        if 'l4_p2_original_attrs' in o:
            o['l4_attrs'] = o['l4_p2_original_attrs']
        if 'l4_p2_original_flicker' in o:
            o['l4_flicker'] = o['l4_p2_original_flicker']


def _clear():
    root = bpy.data.collections.get("L4 Cinema")
    if root is None:
        root = bpy.data.collections.new("L4 Cinema")
        bpy.context.scene.collection.children.link(root)
    mine = _coll("L4 Ceilings", root)
    lights = _coll("L4 Fixture Lights", root)
    _restore_flicker_state()
    for o in list(mine.all_objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for o in list(lights.all_objects):
        if o.get("l4_pkg") == "ceilings":
            bpy.data.objects.remove(o, do_unlink=True)
    gone = collections.Counter()
    for o in list(bpy.data.objects):
        p = o.get("l4_path")
        if p and _replaced(p):
            bpy.data.objects.remove(o, do_unlink=True)
            gone["layout_objects"] += 1
    sup = [re.compile(r) for r in _module_list("LIGHTS_SUPERSEDED")]
    old = bpy.data.collections.get("L4 Lights")
    for o in (list(old.objects) if old else []):
        i = o.get("l4_src_light")
        if i is not None and any(r.search(_L["lights"][int(i)]["p"]) for r in sup):
            gone["legacy:" + _L["lights"][int(i)]["p"].rsplit("/", 1)[0]] += 1
            bpy.data.objects.remove(o, do_unlink=True)
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


def _bl_box(lo, hi):
    c = [(lo[i] + hi[i]) / 2 for i in range(3)]
    return [round(v, 5) for v in (*_b(c), (hi[0] - lo[0]) * S, (hi[2] - lo[2]) * S, (hi[1] - lo[1]) * S)]


# ---------------------------------------------------------------- light plan
def _hue_class(rgb):
    """sRGB 0-255 -> neon colour class, or None for whites / dull colours."""
    r, g, b = [max(0.0, float(c)) / 255 for c in rgb]
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    if v < 0.25 or s < 0.45:
        return None
    h *= 360
    return "red" if (h < 15 or h >= 345) else "amber" if h < 45 else "cyan" if 165 <= h < 215 else \
        "blue" if 215 <= h < 265 else "magenta" if 265 <= h < 345 else None


def _studs(o):
    p = o.matrix_world.translation
    return np.array((p.x / S + OX, p.z / S, -p.y / S))


def v6_service_lights():
    z = next(z for z in ZONES if z['name'] == 'Service')
    a, b, c, d = z['rect']
    cols = [bpy.data.collections.get(n) for n in ('L4 Fixture Lights', 'L4 Lights')]
    return [o for col in cols if col for o in col.all_objects if o.type == 'LIGHT'
            and a <= _studs(o)[0] <= b and c <= _studs(o)[2] <= d
            and z['floor'] <= _studs(o)[1] <= z['y'] + z.get('plenum', 1)]


def _v6_cone_extent(axis, half):
    """Conservative axial cone support, also containing a spherical-range cone; includes the apex."""
    return max(0.0, axis + math.sqrt(max(0.0, 1 - axis * axis)) * math.tan(half))


def v6_service_cone_range(pos, direction, angle, wanted):
    a, b, c, d = v6_service_bounds()
    direction = np.array(direction, float) / np.linalg.norm(direction)
    half = math.radians(angle / 2)
    reach = float(wanted)
    for axis, low, high in ((0, a, b), (2, c, d)):
        for sign, distance in ((-1, pos[axis] - low), (1, high - pos[axis])):
            extent = _v6_cone_extent(sign * direction[axis], half)
            if extent > 1e-9:
                reach = min(reach, max(0.0, distance - .25) / extent)
    return reach


def v6_clip_service_lights():
    """Contain every Service practical after Roblox's range gain; wall lamps shine into the room/down."""
    if not (V6_EDITS['item4_service_pools'] or V6_EDITS['service_hanging_ceiling']):
        return []
    from mathutils import Matrix, Vector
    a, b, c, d = v6_service_bounds()
    records = []
    for o in v6_service_lights():
        p = _studs(o)
        if o.get('l4_kind') == 'service_hanging':
            # SurfaceLight starts across the full 20x3 holder, not at its centre.
            face_size = SERVICE_FIXTURE_SIZE
            wanted = SERVICE_LIGHT_RANGE
            reach = wanted
            half = math.radians(SERVICE_LIGHT_ANGLE / 2)
            for axis, low, high, size in ((0, a, b, face_size[0]), (2, c, d, face_size[1])):
                reach = min(reach, (min(p[axis] - low, high - p[axis]) - size / 2 - .25) / math.tan(half))
            assert reach > SERVICE_FIXTURE_Y - 24.05
            o['l4_range'] = reach / V6_PLACE_RANGE_GAIN
            o['l4_v6_final_range'] = reach
            o.data.cutoff_distance = reach / V6_PLACE_RANGE_GAIN * S
            o.data.energy = _energy('AREA', float(o['l4_range']), float(o['l4_brightness']))
            records.append(dict(name=o.name, type='AREA', pos=list(p), direction=(0,-1,0),
                                angle=SERVICE_LIGHT_ANGLE, range=reach, source_range=float(o['l4_range']),
                                brightness=float(o['l4_brightness']), face_size=face_size,
                                zone=int(o.get('l4_zone', 0))))
            continue
        if o.name.startswith('L4D2_Bulkhead'):
            nearest = min(((p[0] - a, (1, 0, 0)), (b - p[0], (-1, 0, 0)),
                           (p[2] - c, (0, 0, 1)), (d - p[2], (0, 0, -1))), key=lambda v: v[0])[1]
            direction = (nearest[0], -.9, nearest[2])
            o.data.type = 'SPOT'
            o.data.spot_size, o.data.spot_blend = math.radians(50), .65
            o.matrix_world = Matrix.Translation(o.matrix_world.translation) @ _orient(direction, (1, 0, 0)
                             if nearest[0] == 0 else (0, 0, 1))
        if o.data.type == 'SPOT':
            bl = o.matrix_world.to_3x3() @ Vector((0, 0, -1))
            direction = (bl.x, bl.z, -bl.y)
            angle = math.degrees(o.data.spot_size)
            wanted = 30.0 if o.get('l4_pkg') == 'ceilings' else 20.0
            reach = v6_service_cone_range(p, direction, angle, wanted)
        else:
            reach = max(0.0, min(18, p[0] - a - .25, b - p[0] - .25, p[2] - c - .25, d - p[2] - .25))
            angle, direction = 360.0, None
        assert reach > .1, 'Service light outside its room: ' + o.name
        o['l4_range'] = reach / V6_PLACE_RANGE_GAIN
        brightness = .45 if o.get('l4_pkg') == 'ceilings' else (.40 if 'Workbench' in o.name else .28)
        o['l4_brightness'] = min(float(o.get('l4_brightness', 1)), brightness)
        o['l4_v6_service_pool'] = True
        o['l4_v6_final_range'] = reach
        o.data.use_custom_distance = True
        o.data.cutoff_distance = reach / V6_PLACE_RANGE_GAIN * S
        o.data.energy = _energy(o.data.type, float(o['l4_range']), float(o['l4_brightness']))
        records.append(dict(name=o.name, type=o.data.type, pos=list(p), direction=direction, angle=angle,
                            range=reach, source_range=float(o['l4_range']), brightness=float(o['l4_brightness'])))
    return records


def _rgb(o):
    c = o.get("l4_color")
    return [float(v) for v in c] if c is not None else [255 * _lin2srgb(v) for v in o.data.color]


def _blinks(o):
    if o.get("l4_flicker") or o.data.get("l4_flicker"):
        return True
    p = o.parent
    while p is not None:
        if json.loads(p.get("l4_attrs", "{}") or '{}').get('OccasionalFlicker'):
            return True
        p = p.parent
    return False


def _info(o):
    """Light object -> dict(pos, cls, range, axis, half, blink, mine, kind, prop)."""
    pos = _studs(o)
    rng = float(o.get("l4_range", o.data.get("l4_range", 16.0)))
    axis, half = np.zeros(3), 0.0
    if o.data.type == "AREA":
        X = o.matrix_world.to_3x3().col[0].normalized()
        axis = np.array((X.x, X.z, -X.y))
        half = o.data.size / 2 / S
    host = o.parent
    while host is not None and not host.get('l4_prop'):
        host = host.parent
    if host is None:
        host = bpy.data.objects.get(o.get('l4_host', ''))
    return dict(o=o, host=host, pos=pos, cls=_hue_class(_rgb(o)), range=rng, axis=axis, half=half, blink=_blinks(o),
                mine=o.get("l4_pkg") == "ceilings", kind=o.get("l4_kind", ""), prop=bool(PROP_LIGHT.search(o.name)))


def _reaches(L, p):
    d = p - L["pos"]
    if L["half"] > 0:
        d = d - L["axis"] * max(-L["half"], min(L["half"], float(d @ L["axis"])))
    return float(np.linalg.norm(d)) <= max(5.0, min(12.0, 0.45 * L["range"]))


def neon_segments():
    """Lit, saturated emissive faces of the plain (non-prop) meshes, clustered per colour class into runs and cut into
    pieces <= SEG_LEN -> [dict(cls, rgb, ctr, axis, length, weight)] (Studio studs)."""
    root = bpy.data.collections.get("L4 Cinema")
    mats, pts = {}, collections.defaultdict(list)
    for o in (root.all_objects if root else []):
        if o.type != "MESH" or o.get("l4_prop") or o.get("l4_door_leaf") or o.name.startswith("L4C_Stars_"):
            continue
        sl = []
        for k, s in enumerate(o.material_slots):
            m = s.material
            if m is None:
                continue
            if m.name not in mats:
                mats[m.name] = None
                if (m.get("l4_sem") == "neon" or float(m.get("l4_emit", 0) or 0) >= 2) and m.get("l4_color") \
                        and not m.name.startswith("L4C_M_lens"):
                    cls = _hue_class(m["l4_color"])
                    mats[m.name] = (cls, [float(v) for v in m["l4_color"]]) if cls else None
            if mats[m.name]:
                sl.append((k, mats[m.name]))
        if not sl:
            continue
        me = o.data
        n = len(me.polygons)
        mi = np.empty(n, np.int32); me.polygons.foreach_get("material_index", mi)
        ctr = np.empty(n * 3); me.polygons.foreach_get("center", ctr)
        ar = np.empty(n); me.polygons.foreach_get("area", ar)
        M = np.array(o.matrix_world)
        W = ctr.reshape(-1, 3) @ M[:3, :3].T + M[:3, 3]
        st = np.stack([W[:, 0] / S + OX, W[:, 2] / S, -W[:, 1] / S], 1)
        sc = abs(np.linalg.det(M[:3, :3])) ** (2 / 3) / S ** 2
        vc = np.empty(len(me.vertices) * 3); me.vertices.foreach_get('co', vc)
        vw = vc.reshape(-1, 3) @ M[:3, :3].T + M[:3, 3]
        vs = np.stack([vw[:, 0] / S + OX, vw[:, 2] / S, -vw[:, 1] / S], 1)
        for k, (cls, rgb) in sl:
            samples, weights = [], []
            for j in np.nonzero(mi == k)[0]:
                face = me.polygons[int(j)]
                pp = [st[j]]
                vi = list(face.vertices)
                for ia, ib in zip(vi, vi[1:] + vi[:1]):
                    a, b = vs[ia], vs[ib]
                    length = np.linalg.norm(b - a)
                    if length > 2.5:
                        pp.extend(a + (b - a) * t for t in np.linspace(0, 1, math.ceil(length / 1.2) + 1))
                samples.extend(pp)
                weights.extend([ar[j] * sc / len(pp)] * len(pp))
            if samples:
                pts[cls].append((np.array(samples), np.array(weights), rgb))
    out = []
    for cls, chunks in pts.items():
        P = np.concatenate([c[0] for c in chunks]); A = np.concatenate([c[1] for c in chunks])
        RGB = np.concatenate([np.tile(c[2], (len(c[0]), 1)) for c in chunks])
        vox = collections.defaultdict(list)
        for i, key in enumerate(map(tuple, np.floor(P / 1.5).astype(int))):
            vox[key].append(i)
        seen = set()
        for key in vox:
            if key in seen:
                continue
            comp, q = [], [key]
            seen.add(key)
            while q:
                k = q.pop()
                comp += vox[k]
                for d in ((a, b, c) for a in (-1, 0, 1) for b in (-1, 0, 1) for c in (-1, 0, 1)):
                    nk = (k[0] + d[0], k[1] + d[1], k[2] + d[2])
                    if nk in vox and nk not in seen:
                        seen.add(nk)
                        q.append(nk)
            idx = np.array(comp)
            p, a = P[idx], A[idx]
            if a.sum() < 0.25:
                continue                                       # buttons, pilot dots
            c = (p * a[:, None]).sum(0) / a.sum()
            u = np.linalg.svd(p - c, full_matrices=False)[2][0] if len(p) > 2 else np.array((1.0, 0, 0))
            t = (p - c) @ u
            t0, t1 = float(t.min()), float(t.max())
            npc = max(1, math.ceil((t1 - t0) / SEG_LEN))
            for j in range(npc):
                lo_, hi_ = t0 + (t1 - t0) * j / npc, t0 + (t1 - t0) * (j + 1) / npc
                sel = (t >= lo_ - 1e-6) & (t <= hi_ + 1e-6)
                if not sel.any():
                    continue
                out.append(dict(cls=cls, rgb=[float(v) for v in RGB[idx][sel].mean(0)], axis=u, length=hi_ - lo_,
                                ctr=c + u * (lo_ + hi_) / 2, weight=float(a[sel].sum())))
    return out


def _open_dir(ctr, axis, dg):
    """Direction from a neon run into open space (ray casts; horizontal sides first, then down / up)."""
    up = np.array((0, 1.0, 0))
    h = np.cross(axis, up)
    h = h / np.linalg.norm(h) if np.linalg.norm(h) > 0.3 else np.array((1.0, 0, 0))
    h2 = np.cross(axis, h)
    h2 = h2 / max(1e-6, np.linalg.norm(h2))

    def free(d):
        o = ctr + d * 0.4
        hit, loc, *_ = bpy.context.scene.ray_cast(dg, _b(o), _bdir(d), distance=30 * S)
        return (np.linalg.norm(np.array((loc.x / S + OX, loc.z / S, -loc.y / S)) - o) if hit else 30.0)
    horiz = [d for d in (h, -h, h2, -h2) if abs(d[1]) < 0.5]
    best = max(horiz, key=free) if horiz else None
    if best is not None and free(best) >= 3:
        return best
    return np.array((0, -1.0, 0)) if free(np.array((0, -1.0, 0))) >= 3 else up


def _groups(infos, link=14.0):
    """A real prop is one neon unit; unparented same-colour practicals cluster at 14 studs."""
    n = len(infos)
    par = list(range(n))

    def find(i):
        while par[i] != i:
            par[i] = par[par[i]]
            i = par[i]
        return i
    P = np.array([L["pos"] for L in infos]) if n else np.zeros((0, 3))
    for i in range(n):
        d = np.linalg.norm(P[i + 1:] - P[i], axis=1)
        for j in np.nonzero(d <= link)[0]:
            k = i + 1 + int(j)
            a, b = infos[i], infos[k]
            if (a.get('host') is not None or b.get('host') is not None):
                if a.get('host') == b.get('host'):
                    par[find(i)] = find(k)
            elif a['cls'] == b['cls']:
                par[find(i)] = find(k)
    # A long FlickerLens can carry lights farther apart than the proximity threshold.
    hosts = {}
    for i, info in enumerate(infos):
        h = info.get('host')
        if h is not None:
            if h.name in hosts: par[find(i)] = find(hosts[h.name])
            else: hosts[h.name] = i
    g = collections.defaultdict(list)
    for i in range(n):
        g[find(i)].append(i)
    return list(g.values())


def _zone_of(plans):
    order = sorted(plans, key=lambda zp: (zp["z"]["rect"][1] - zp["z"]["rect"][0]) * (zp["z"]["rect"][3] - zp["z"]["rect"][2]))

    def zone(p):
        x, y, z = p
        for zp in order:
            x0, x1, z0, z1 = zp["z"]["rect"]
            if x0 <= x <= x1 and z0 <= z <= z1 and zp["z"]["floor"] - 14 <= y <= zp["z"]["y"] + 1:
                return zp["z"]["name"]
        return "other"
    return zone


def light_pass(plans, lcol, apply_service=True):
    """Final, repeatable light plan: keep prop lights, replace the old generic neon washes, reserve distributed star
    fill, and spend the remaining budget on real neon runs. Blinking units are actual FlickerLens props, including
    their child lights and visible neon; excess v2 flickering units become steady. Gallery: stars + orange only."""
    _restore_flicker_state()
    st = collections.Counter()
    removed = []
    for o in list(lcol.all_objects):
        if o.type != "LIGHT":
            continue
        p = _studs(o)
        repeated = o.get('l4_pkg') == 'ceilings' and o.get('l4_kind') in ('star', 'neon_fill', 'core_sconce')
        duplicate = o.get('l4_pkg') == 'A_detailing' and o.get('l4_kind') in ('neon_up', 'neon_wall', 'cove')
        gallery_lamp = in_gallery(*p) and (_hue_class(_rgb(o)) != 'amber'
                                           or re.search(r'Lamp|Sconce', o.name, re.I))
        if repeated or duplicate or in_removed(*p) or gallery_lamp:
            removed.append(o.name)
            bpy.data.objects.remove(o, do_unlink=True)
    st['removed_or_replanned'] = len(removed)
    for ld in list(bpy.data.lights):
        if ld.name.startswith('L4C_') and ld.users == 0:
            bpy.data.lights.remove(ld)
    old = bpy.data.collections.get('L4 Lights')
    # Legacy export clones the original light unchanged. Replace these six outputs as tuned fixture records instead.
    for o in list(old.objects if old else []):
        i = o.get('l4_src_light')
        if o.type == 'LIGHT' and i is not None and CORE_LAMP.search(_L['lights'][int(i)]['p']):
            bpy.data.objects.remove(o, do_unlink=True)
    for k, source in enumerate(l for l in _L['lights'] if CORE_LAMP.search(l['p'])):
        _mklight(_point(source['pos'], (255, 219, 185), 16, .09, 'core_sconce'),
                 'L4C_L_Core_sconce%d' % k, lcol)
    legacy = sum(o.type == 'LIGHT' for o in (old.objects if old else []))
    for o in (old.objects if old else []):
        if o.type == 'LIGHT':
            o.data.use_shadow = False
            o['l4_shadows'] = False
    stars = [zp for zp in plans if zp['z']['kind'] == 'star']
    area = {zp['z']['name']: int(zp['mask'].sum()) for zp in stars}
    alloc = {k: max(1, math.ceil(v / 5500)) for k, v in area.items()}
    # The narrow 752-stud gallery needs continuous floor reach, even when its orange practicals are dim.
    for zp in stars:
        if zp['z']['name'] == 'Gallery':
            alloc['Gallery'] = math.ceil((zp['z']['rect'][1] - zp['z']['rect'][0]) / 64)
    fixed = sum(o.type == 'LIGHT' for o in lcol.all_objects)
    # A future package cannot silently steal all of the fill budget.
    assert fixed + legacy + sum(alloc.values()) <= BUDGET, 'Fixed prop/fixture lights exceed the reserved light budget'
    infos = [_info(o) for o in lcol.all_objects if o.type == "LIGHT"]
    neon = [L for L in infos if L["cls"] and L["kind"] != "star"]
    for L in neon:
        if in_gallery(*L['pos']):
            # P4's retained north-cove washes need the same restraint as the replanned south-cove lights.
            o = L['o']
            o['l4_brightness'], o['l4_color'] = .14, list(GALLERY_LIGHT)
            o.data.color = tuple(_c_lin(c) for c in GALLERY_LIGHT)
            L['range'] = 14.0
        if L['mine'] or not L['prop']:
            o = L['o']
            L['range'] = max(12.0, min(24.0, L['range']))
            o['l4_range'] = L['range']
            o.data.cutoff_distance = L['range'] * S * 1.3
            o.data.energy = _energy(o.data.type, L['range'], float(o.get('l4_brightness', 1)))
    # Plan first; do not create hundreds of temporary lights only to delete them for the budget.
    rng = random.Random("l4neonfill")
    capacity = BUDGET - fixed - legacy - sum(alloc.values())
    candidates = []
    for seg in sorted(neon_segments(), key=lambda s: -s['weight']):
        if in_removed(*seg['ctr']) or (in_gallery(*seg['ctr']) and seg['cls'] != 'amber'):
            continue
        n = max(1, int(seg["length"] // 4))
        smp = [seg["ctr"] + seg["axis"] * (seg["length"] * ((k + .5) / n - .5)) for k in range(n)]
        same = [L for L in neon + candidates if L['cls'] == seg['cls']]
        cov = sum(any(_reaches(L, p) for L in same) for p in smp) / n
        if cov >= 0.6:
            continue
        if len(candidates) >= capacity:
            st['neon_runs_deferred'] += 1
            continue
        candidates.append(dict(seg, pos=seg['ctr'], range=24, half=seg['length'] * .45,
                               blink=False, host=None))
    dg = bpy.context.evaluated_depsgraph_get()
    added = []
    for seg in candidates:
        # Gallery coves wash downward; a sideways wash lights the nearby black deck orange.
        d = np.array((0, -1.0, 0)) if in_gallery(*seg['ctr']) else _open_dir(seg['ctr'], seg['axis'], dg)
        col = tuple(int(c) for c in np.array(seg["rgb"]) * 255 / max(seg["rgb"]))
        b = NEON_B * rng.uniform(0.75, 1.25) * (0.45 if rng.random() < 0.15 else 1.0)
        if in_gallery(*seg['ctr']):
            b *= .16
            col = GALLERY_LIGHT
        r_ = 14.0 if in_gallery(*seg['ctr']) else 16 + min(8.0, seg["length"] / 6)
        if seg["length"] >= 10 or in_gallery(*seg['ctr']):
            L = _area(tuple(seg["ctr"] + d * 0.8), col, round(r_, 1), round(b, 3), "neon_fill",
                      (seg["length"] * .9, 0.5), face=tuple(d), along=tuple(seg["axis"]))
        else:
            L = _point(tuple(seg["ctr"] + d * 1.0), col, round(r_, 1), round(b, 3), "neon_fill")
        L["weight"] = seg["weight"]
        o = _mklight(L, "L4C_L_neon_%d" % len(added), lcol)
        added.append(dict(_info(o), weight=seg["weight"]))
    st["neon_practicals"] = len(added)
    neon += added
    zone = _zone_of(plans)
    units = [L for L in neon if L['blink'] and L.get('host') is not None]
    # ponytail: pair generic washes within 12 studs; explicit emitter IDs if future rooms pack unrelated runs tightly.
    for L in neon:
        if L.get('host') is not None or L['prop']:
            continue
        # Pooled prop meshes can have a world-zero origin; use their actual child-light positions.
        near = [(float(np.linalg.norm(L['pos'] - N['pos'])), N['host']) for N in units
                if zone(L['pos']) == zone(N['pos'])]
        if not near:
            continue
        distance, host = min(near, key=lambda x: x[0])
        if distance > 12:
            continue
        o = L['o']; M = o.matrix_world.copy()
        if 'l4_p2_original_parent' not in o:
            o['l4_p2_original_parent'] = o.parent.name if o.parent else ''
            o['l4_p2_original_host'] = o.get('l4_host', '')
        o.parent = host
        o.matrix_parent_inverse = host.matrix_world.inverted()
        o.matrix_world = M
        o['l4_host'] = host.name
        L['host'], L['blink'] = host, True
    # All lights of a prop share its OccasionalFlicker unit. A proximity group cannot claim to blink while some
    # members remain steady, and a static pooled tube never receives a light-only fake flicker.
    groups = _groups(neon)
    blinking = [g for g in groups if all(neon[i]['blink'] and neon[i].get('host') is not None for i in g)]
    want = min(len(blinking), math.ceil(.15 * len(groups)))
    own = [g for g in blinking if any(neon[i]['mine'] for i in g)]
    others = [g for g in blinking if g not in own]
    chosen = own[:want] + [others[k] for k in _fps([tuple(neon[g[0]]['pos'][[0, 2]]) for g in others], want - len(own))]
    for g in blinking:
        if g in chosen:
            continue
        for i in g:
            o, host = neon[i]['o'], neon[i]['host']
            if 'l4_p2_original_attrs' not in host:
                host['l4_p2_original_attrs'] = host.get('l4_attrs', '{}')
            attrs = json.loads(host.get('l4_attrs', '{}') or '{}'); attrs['OccasionalFlicker'] = False
            host['l4_attrs'] = json.dumps(attrs)
            if o.get('l4_flicker'):
                if 'l4_p2_original_flicker' not in o:
                    o['l4_p2_original_flicker'] = bool(o.get('l4_flicker'))
                o['l4_flicker'] = False
    st['neon_groups'], st['neon_groups_blinking'] = len(groups), len(chosen)
    assert not groups or BLINK[0] <= len(chosen) / len(groups) <= BLINK[1], 'Need real neon flicker units for 12-18% share'
    left = BUDGET - fixed - legacy - len(added)
    cap = {k: max(alloc[k], math.ceil(v / 1800)) for k, v in area.items()}
    while sum(alloc.values()) < left and any(alloc[k] < cap[k] for k in alloc):
        k = max((k for k in alloc if alloc[k] < cap[k]), key=lambda k: area[k] ** 0.75 / alloc[k])
        alloc[k] += 1
    for zp in stars:
        for k, L in enumerate(star_fill_plan(zp, alloc[zp["z"]["name"]])):
            _mklight(L, "L4C_L_%s_star%d" % (zp["z"]["name"], k), lcol)
            st["star_fill"] += 1
    # 5. shadows
    sh = sorted([o for o in lcol.all_objects if o.type == "LIGHT" and o.get("l4_shadows")],
                key=lambda o: o.get("l4_pkg") == "ceilings")
    for o in sh[SHADOW_MAX:]:
        o["l4_shadows"] = False
    for o in lcol.all_objects:
        if o.type == 'LIGHT':
            o.data.use_shadow = bool(o.get('l4_shadows', False))
    if apply_service:
        if V6_EDITS['service_hanging_ceiling']:
            apply_v6_service_hanging_ceiling()
        apply_v6_service_no_incoming_bleed()
        v6_clip_service_lights()
    sh = [o for o in lcol.all_objects if o.type=='LIGHT' and o.get('l4_shadows')]
    st["shadows"] = min(len(sh), SHADOW_MAX)
    st["legacy"] = legacy
    st["total"] = sum(1 for o in lcol.all_objects if o.type == "LIGHT") + legacy
    assert st['total'] <= BUDGET and st['shadows'] <= SHADOW_MAX
    # per-zone plan
    zone = _zone_of(plans)
    plan = collections.defaultdict(collections.Counter)
    for o in lcol.all_objects:
        if o.type == "LIGHT":
            k = o.get("l4_kind") or ("neon" if _hue_class(_rgb(o)) else "prop")
            plan[zone(_studs(o))]["%s:%s%s" % (o.get("l4_pkg", "?"), k, "*" if _blinks(o) else "")] += 1
    return dict(st), {k: dict(v) for k, v in sorted(plan.items())}, removed


def final_lighting_pass():
    """build_all's zero-argument hook; re-running it replaces the fill/practicals rather than duplicating lights."""
    plans = globals().get('LAST_CEILING_PLANS') or plan_all()
    lc = bpy.data.collections.get('L4 Fixture Lights')
    if lc is None:
        return {}
    result, plan, removed = light_pass(plans, lc)
    globals()['LAST_LIGHT_PASS'] = dict(stats=result, plan=plan, removed=removed)
    print('L4 final light plan:', json.dumps(globals()['LAST_LIGHT_PASS']), flush=True)
    # Final7: use the free post-Service budget for DRINKS without reallocating any existing fill lights.
    menu_path = os.path.join(HERE, 'props_rooms.py')
    menu_ns = {'__name__': 'l4_v6_menu_lights', '__file__': menu_path}
    exec(compile(open(menu_path, encoding='utf-8').read(), menu_path, 'exec'), menu_ns)
    menu_ns['apply_v6_menu_lights']()
    return result


def apply_v6_service_lighting():
    """Approval-only hook on final4: rebuild ONLY the Service ceiling, keep the authored zones/nav intact."""
    if not V6_EDITS['item4_service_pools']:
        return {'enabled': False}
    if 'slot' not in globals():
        exec(open(os.path.join(HERE, 'slots.py'), encoding='utf-8').read(), globals())
    before = v6_service_lights()
    old_zones = [(tuple(_studs(o)), int(o['l4_zone'])) for o in before if o.get('l4_zone') is not None]
    old = bpy.data.objects.get('L4C_Service')
    props = {k: old[k] for k in old.keys()} if old else {}
    mine, lcol = bpy.data.collections['L4 Ceilings'], bpy.data.collections['L4 Fixture Lights']
    replaced = []
    for o in list(mine.all_objects) + list(lcol.all_objects):
        if o.name == 'L4C_Service' or o.name.startswith(('L4C_FlickerLens_Service_', 'L4C_L_Service_')):
            replaced.append(o.name)
            bpy.data.objects.remove(o, do_unlink=True)
    zp = plan_act(next(z for z in ZONES if z['name'] == 'Service'))
    mb, flick = act_geometry(zp)
    o = _mkobj(mb, 'L4C_Service', mine)
    for k, value in props.items():
        o[k] = value
    def zone(obj, pos):
        if old_zones:
            obj['l4_zone'] = min(old_zones, key=lambda v: sum((v[0][i] - pos[i]) ** 2 for i in (0, 2)))[1]
    for k, f in enumerate(flick):
        po = bpy.data.objects.new('L4C_FlickerLens_Service_%d' % k, _lens_mesh(f['shape'], f['mat']))
        po.location = _b(f['pos'])
        po.scale = (f['size'][0] * S, f['size'][1] * S, 1)
        mine.objects.link(po)
        po['l4_prop'], po['l4_model'], po['l4_attrs'] = 'FlickerLens', 'FlickerLens', '{"OccasionalFlicker": true}'
        po['l4_zone_split'] = True
        zone(po, f['pos'])
        for L in f['lights']:
            lo = _mklight(L, 'L4C_L_Service_f%d' % k, lcol, host=po)
            zone(lo, L['pos'])
    for k, t in enumerate(zp['troffers']):
        if t.get('light') and t['state'] != 'flicker':
            lo = _mklight(t['light'], 'L4C_L_Service_%d' % k, lcol)
            zone(lo, t['light']['pos'])
    bpy.context.view_layer.update()
    records = v6_clip_service_lights()
    allowed = [o for name in ('L4 Fixture Lights', 'L4 Lights') for o in bpy.data.collections[name].all_objects
               if o.type == 'LIGHT']
    assert len(allowed) <= BUDGET and sum(bool(o.get('l4_shadows', False)) for o in allowed) <= SHADOW_MAX
    return dict(enabled=True, before_lights=len(before), after_lights=len(records), troffers=len(zp['troffers']),
                states=zp['v6_service_states'], bounds=list(v6_service_bounds()), lights=records,
                total_lights=len(allowed), shadows=sum(bool(o.get('l4_shadows', False)) for o in allowed),
                rebuilt_objects=replaced)


def _v6_service_materials():
    """Dedicated dim tube colour survives export; no shared cinema material is changed."""
    extra = {
        'service_tile': ('act_2x4', 1.232, (110,100,88), .94, 0, 'SmoothPlastic', 'ceiling'),
        'service_tile_stain': (None, 1, (83,75,63), .98, 0, 'SmoothPlastic', 'ceiling'),
        'service_grid': (None, 1, (76,73,65), .85, .1, 'SmoothPlastic', 'metal'),
        'service_housing': (None, 1, (112,117,119), .72, .05, 'SmoothPlastic', 'metal'),
        'service_frame': (None, 1, (89,94,97), .76, .05, 'SmoothPlastic', 'metal'),
        'service_steel': (None, 1, (200,204,196), .42, .15, 'SmoothPlastic', 'metal'),
        'service_galvanized': (None, 1, (188,197,195), .55, .12, 'SmoothPlastic', 'metal'),
        'service_cap': (None, 1, (218,214,192), .25, 0, 'SmoothPlastic', 'plastic'),
        # About .59 of the unchanged light RGB; only these thin tubes are Neon.
        # Max sRGB .561 is well below the .92 Bloom threshold; no luminous housing.
        'service_tube': (None, 1, (138,143,130), .5, 0, 'Neon', 'neon'),
    }
    for key, value in extra.items():
        SLOTS[key.upper()] = value
        MATS[key] = (key.upper(), value[2] if value[0] else None)
    m = _mat('service_tube')
    m.node_tree.nodes['Principled BSDF'].inputs['Emission Strength'].default_value = .65
    m['l4_emit'] = .65


def _v6_hanging_fixture_mesh(body_y=None):
    """One real mesh, shared by all nine Models; long X axis, three banks and twenty louver cells."""
    mb = _MB()
    L, W = SERVICE_FIXTURE_SIZE
    a, b, c, d = -L/2, L/2, -W/2, W/2
    mb.box((a,.68,c), (b,.8,d), 'service_housing')
    for z0, z1 in ((c,c+.16),(d-.16,d)):
        mb.box((a,0,z0), (b,.68,z1), 'service_housing')
        mb.box((a,.57,z0-.025), (b,.72,z1+.025), 'service_frame')
    for x0,x1 in ((a,a+.22),(b-.22,b)):
        mb.box((x0,0,c+.16), (x1,.68,d-.16), 'service_housing')
    for bank in (-.82,0,.82):
        # Folded, parabolic-style V wings behind the round tubes, as in Level1.
        for side in (-1,1):
            mb.poly([(a+.3,.65,bank),(b-.3,.65,bank),
                     (b-.3,.45,bank+side*.36),(a+.3,.45,bank+side*.36)],
                    'service_steel', (0,-1,0))
        _cyl(mb,(a+.5,.13,bank),(b-.5,.13,bank),.085,'service_tube',10)
        for x0,x1 in ((a+.32,a+.56),(b-.56,b-.32)):
            _cyl(mb,(x0,.13,bank),(x1,.13,bank),.12,'service_cap',8)
    for k in range(1,20):
        x = a+.25+(L-.5)*k/20
        mb.box((x-.022,.025,c+.18),(x+.022,.435,d-.18),'service_steel')
    for z in (-.41,.41):
        mb.box((a+.24,.025,z-.025),(b-.24,.435,z+.025),'service_steel')
    for x in (a+.35,b-.35):
        for z in (c+.08,d-.08):
            _cyl(mb,(x,-.012,z),(x,.035,z),.09,'service_steel',6)
    # 0.22-stud galvanized rods, nuts, and top plates gripping the unistrut rail.
    top = SERVICE_CEILING_Y - (SERVICE_FIXTURE_Y if body_y is None else body_y) - .28
    for x in (-7.6,7.6):
        _cyl(mb,(x,.8,0),(x,top,0),.11,'service_galvanized',8)
        mb.box((x-.24,.78,-.24),(x+.24,.9,.24),'service_frame')
        mb.box((x-.42,top-.14,-.42),(x+.42,top+.06,.42),'service_galvanized')
        for z in (-.33,.33):
            mb.box((x-.34,top-.12,z-.045),(x+.34,top+.22,z+.045),'service_galvanized')
        for yy in (.92,top-.20):
            _cyl(mb,(x,yy-.055,0),(x,yy+.055,0),.19,'service_galvanized',6)
    return mb


def _v6_service_append_passive_devices(mb):
    """Rehouse the former passive returns/detectors on the raised ceiling; no lights or collision."""
    original = plan_act(next(z for z in ZONES if z['name'] == 'Service'))
    y = SERVICE_CEILING_Y
    for x0, x1, z0, z1 in original['grilles']:
        # The throat sits just below the uncut tile, so this is a visible passive return, not a sky hole.
        _troffer(mb, x0, x1, z0, z1, y - .04, None)
        inset = .24
        mb.hquad(x0 + inset, x1 - inset, z0 + inset, z1 - inset, y - .08, 'service_grid')
        for k in range(6):
            x = x0 + inset + (k + .5) * (x1 - x0 - 2 * inset) / 6
            mb.box((x - .06, y - .11, z0 + inset),
                   (x + .06, y - .06, z1 - inset), 'service_steel')
    for x, z in original['detectors']:
        _cyl(mb, (x, y - .16, z), (x, y - .02, z), .40, 'service_cap', 10)
    return dict(return_air_grilles=len(original['grilles']), smoke_detectors=len(original['detectors']),
                positions_preserved=True, ceiling_y=y, sprinklers_found=0)


def _v6_service_height_dependencies(mine):
    """Raise the noncolliding ACT trim. Cabinet conduits use props_rooms.SERV_CEIL."""
    from mathutils import Vector
    crown = bpy.data.objects.get('L4D_Crown_Service')
    crown_bounds = None
    if crown:
        assert not crown.get('l4_collide') and not crown.get('l4_occluder') and not crown.data.get('l4_col')
        top = max((crown.matrix_world @ Vector(v)).z / S for v in crown.bound_box)
        # Target the absolute top, so applying the hook twice never raises it twice.
        delta = SERVICE_CEILING_Y - top
        if abs(delta) > 1e-5:
            crown.location.z += delta * S
        bpy.context.view_layer.update()
        ys = [(crown.matrix_world @ Vector(v)).z / S for v in crown.bound_box]
        crown_bounds = [min(ys), max(ys)]
    return dict(crown_y_bounds=crown_bounds, conduit_extensions=0,
                conduit_height_source='props_rooms.SERV_CEIL', collision_changed=False)


def _v6_service_damage_plan():
    """Keep ceiling damage above the retained fallen shards and two leak puddles."""
    from mathutils import Vector
    a, b, c, d = v6_service_bounds()
    cells, shards = set(), []
    for o in bpy.data.objects:
        if not o.name.startswith('L4C_FallenTile_Service_'):
            continue
        centre = sum((o.matrix_world @ Vector(v) for v in o.bound_box), Vector()) / 8
        x, _, z = (centre.x / S + OX, centre.z / S, -centre.y / S)
        cell = (int((x-a)//8), int((z-c)//4))
        cells.add(cell)
        shards.append(dict(name=o.name, centre=(x,z), cell=cell))
        # The old cream shards now have the same acoustic-tile finish as the new ceiling.
        for k, m in enumerate(o.data.materials):
            if m and ('ACT_' in m.name or 'ACT_2X4' in m.name.upper()):
                o.data.materials[k] = _mat('service_tile')
    ordered = sorted(cells)
    sags = set(ordered[::max(1,len(ordered)//3)][:3])
    damaged = {cell: ('sag' if cell in sags else 'hole') for cell in cells}
    leaks = [(x,z) for zone,x,z,_,_ in LEAKS if zone == 'Service']
    leak_cells = {(int((x-a)//8),int((z-c)//4)) for x,z in leaks}
    for cell in leak_cells & cells:
        damaged[cell] = 'sag'  # A stained, retained tile must exist above each puddle.
    stain_cells = leak_cells | sags
    for i,j in ordered:
        for neighbour in ((i+1,j),(i,j+1),(i-1,j)):
            if 0 <= neighbour[0] < math.ceil((b-a)/8) and 0 <= neighbour[1] < math.ceil((d-c)/4) and neighbour not in damaged:
                stain_cells.add(neighbour)
                if len(stain_cells) >= 18:
                    break
        if len(stain_cells) >= 18:
            break
    return dict(damaged=damaged, stain_cells=stain_cells, leaks=leaks, shards=shards)


def _v6_service_dark_ceiling():
    """Replace the complete old ACT/troffer dressing with non-emissive stained tiles and dark steel grid."""
    a,b,c,d = v6_service_bounds()
    y = SERVICE_CEILING_Y
    mb, rng = _MB(), random.Random('service_hanging_dark_ACT')
    nx, nz = math.ceil((b-a)/8), math.ceil((d-c)/4)
    damage_plan = _v6_service_damage_plan()
    damaged = damage_plan['damaged']
    mb.hquad(a,b,c,d,52,'plenum')
    for i in range(nx):
        x0,x1 = a+i*8, min(b,a+(i+1)*8)
        for j in range(nz):
            z0,z1 = c+j*4, min(d,c+(j+1)*4)
            damage = damaged.get((i,j))
            if damage == 'hole':
                mb.box((x0+1,y+.35,z0),(x0+1.2,51.95,z1),'service_grid')
                continue
            pts=[(x0+.06,y,z0+.06),(x1-.06,y,z0+.06),
                 (x1-.06,y-(.65 if damage=='sag' else 0),z1-.06),(x0+.06,y,z1-.06)]
            mb.poly(pts,'service_tile',(0,-1,0))
            # Eighteen partial, irregular water marks; never whole dark squares.
            if (i,j) in damage_plan['stain_cells']:
                cx,cz=(x0+x1)/2,(z0+z1)/2
                for lx,lz in damage_plan['leaks']:
                    if x0 <= lx < x1 and z0 <= lz < z1:
                        cx,cz=lx,lz
                for k in range(3):
                    dx,dz=rng.uniform(-1.7,1.7),rng.uniform(-.55,.55)
                    rx,rz=rng.uniform(.8,1.6),rng.uniform(.35,.7)
                    patch=[]
                    for n in range(8):
                        t=2*math.pi*n/8; jitter=rng.uniform(.72,1)
                        px,pz=cx+dx+rx*math.cos(t)*jitter,cz+dz+rz*math.sin(t)*jitter
                        py=y-(.65*(pz-z0)/(z1-z0) if damage=='sag' else 0)-.008-k*.002
                        patch.append((px,py,pz))
                    mb.poly(patch,'service_tile_stain',(0,-1,0))
    for i in range(nx+1):
        x=min(b,a+i*8)
        mb.box((x-.055,y-.065,c),(x+.055,y+.06,d),'service_grid')
    for j in range(nz+1):
        z=min(d,c+j*4)
        mb.box((a,y-.065,z-.055),(b,y+.06,z+.055),'service_grid')
    # Three unistrut runs; small drilled cells make them read as rails, not glowing strips.
    for z in (134,170,206):
        mb.box((a+6,y-.32,z-.28),(b-6,y-.18,z-.18),'service_grid')
        mb.box((a+6,y-.32,z+.18),(b-6,y-.18,z+.28),'service_grid')
        for x in np.arange(a+6,b-6,4):
            mb.box((x,y-.32,z-.18),(min(x+.25,b-6),y-.21,z+.18),'service_grid')
    _v6_service_append_passive_devices(mb)
    return mb


def apply_v6_service_hanging_ceiling():
    """Replace the Service ceiling during the production build; flag OFF restores the old design."""
    if not V6_EDITS['service_hanging_ceiling']:
        return {'enabled': False}
    assert not V6_EDITS['item4_service_pools'], 'Rejected item4 must stay disabled'
    if 'slot' not in globals():
        exec(open(os.path.join(HERE,'slots.py'),encoding='utf8').read(),globals())
    _v6_service_materials()
    root = bpy.data.collections['L4 Cinema']
    mine = _coll('L4 Ceilings',root)
    lcol = _coll('L4 Fixture Lights',root)
    before = v6_service_lights()
    zones = [(tuple(_studs(o)),int(o['l4_zone'])) for o in before if o.get('l4_zone') is not None]
    if not zones:
        zones = [((22670,48.2,170),27),((22840,48.2,170),28)]
    removed = []
    removed_decals = []
    # The lobby-facing Service sign lies outside the room and is retained.
    for o in list(bpy.data.objects):
        if o.name.startswith('L4F_CeilingLeak_') and o.get('l4_leak_zone')=='Service':
            removed_decals.append(o.name)
            bpy.data.objects.remove(o,do_unlink=True)
            continue
        if o.type=='LIGHT' and o in before:
            removed.append(dict(name=o.name,package=o.get('l4_pkg','legacy'),
                                kind=o.get('l4_kind','prop'),source_range=float(o.get('l4_range',0)),
                                brightness=float(o.get('l4_brightness',0))))
            bpy.data.objects.remove(o,do_unlink=True)
    old = bpy.data.objects.get('L4C_Service')
    props = dict(old.items()) if old else {}
    old_cols = old.data.get('l4_col') if old else None
    for o in list(mine.all_objects):
        if o.name=='L4C_Service' or o.name.startswith(('L4C_FlickerLens_Service_', 'ServiceHanging_')):
            bpy.data.objects.remove(o,do_unlink=True)
    ceiling = _mkobj(_v6_service_dark_ceiling(),'L4C_Service',mine)
    height_dependencies = _v6_service_height_dependencies(mine)
    for key,value in props.items():
        ceiling[key] = value
    if old_cols:
        ceiling.data['l4_col'] = old_cols
    # Dead practical housings stay as props; their lenses/sign no longer glow.
    a,b,c,d = v6_service_bounds()
    darkened = []
    for o in list(bpy.data.objects):
        if o.type!='MESH' or o==ceiling:
            continue
        from mathutils import Vector
        bounds = [o.matrix_world @ Vector(v) for v in o.bound_box]
        centre = sum(bounds,Vector())/8
        p = (centre.x/S+OX,centre.z/S,-centre.y/S)
        inside = a-.15<=p[0]<=b+.15 and c-.15<=p[2]<=d+.15 and 24<=p[1]<=52
        if not inside:
            continue
        indices = [i for i,m in enumerate(o.data.materials) if m and
                   (m.get('l4_roblox')=='Neon' or float(m.get('l4_emit',0))>0)]
        if indices:
            o.data = o.data.copy()
            for i in indices:
                original=o.data.materials[i]
                name='L4C_ServiceDead_'+original.name
                mat=bpy.data.materials.get(name)
                if not mat:
                    mat=original.copy();mat.name=name
                    mat['l4_roblox']='SmoothPlastic';mat['l4_sem']='plastic';mat['l4_emit']=0
                    bs=mat.node_tree.nodes.get('Principled BSDF') if mat.use_nodes else None
                    if bs:bs.inputs['Emission Strength'].default_value=0
                mat['l4_sem']='plastic'
                o.data.materials[i]=mat
            darkened.append(o.name)
    mb = _v6_hanging_fixture_mesh()
    mesh = _mkmesh(mb,'L4C_ServiceHangingFluorescent',origin=(0,0,0))
    for n,p in enumerate(SERVICE_FIXTURE_POSITIONS,1):
        o=bpy.data.objects.new('ServiceHanging_%02d'%n,mesh);mine.objects.link(o)
        o.location=_b(p)
        o['l4_prop']=o['l4_model']='ServiceHangingFluorescent'
        o['l4_col']='[]'
        o['l4_zone']=min(zones,key=lambda v:sum((v[0][i]-p[i])**2 for i in (0,2)))[1]
        o['l4_zone_split']=True
        if n==SERVICE_FLICKER_FIXTURE:
            o['l4_attrs']='{"OccasionalFlicker": true}'
        bpy.context.view_layer.update()
        L=dict(type='AREA',pos=(p[0],p[1]+SERVICE_LIGHT_FACE_OFFSET+.1,p[2]),color=(236,242,220),
               range=SERVICE_LIGHT_RANGE/V6_PLACE_RANGE_GAIN,b=SERVICE_LIGHT_B,kind='service_hanging',
               shadows=False,size=SERVICE_FIXTURE_SIZE,face=(0,-1,0),along=(1,0,0),angle=SERVICE_LIGHT_ANGLE,
               flicker=n==SERVICE_FLICKER_FIXTURE)
        lo=_mklight(L,'L4C_L_Service_Hanging_%02d'%n,lcol,host=o)
        lo['l4_zone']=o['l4_zone'];lo['l4_angle']=SERVICE_LIGHT_ANGLE
        lo.data.spread=math.radians(SERVICE_LIGHT_ANGLE)
    bpy.context.view_layer.update()
    records=v6_clip_service_lights()
    assert len(records)==9, 'Service light count: '+str([r['name'] for r in records])
    assert len({o.data.as_pointer() for o in mine.objects if o.name.startswith('ServiceHanging_')})==1
    return dict(enabled=True,removed_lights=removed,removed_ceiling_decals=removed_decals,
                darkened_props=darkened,lights=records,
                bounds=list(v6_service_bounds()),positions=SERVICE_FIXTURE_POSITIONS,
                fixture_dimensions=(20,3,.8),fixture_bottom=SERVICE_FIXTURE_Y,
                ceiling=SERVICE_CEILING_Y,fixture_triangles=mb.tris(),height_dependencies=height_dependencies,
                passive_devices=dict(return_air_grilles=52,smoke_detectors=18,ceiling_y=SERVICE_CEILING_Y))


def v6_incoming_service_limit(o, wanted, angle=None):
    """Largest conservative reach separated from the finished Service volume, including AREA emitter size."""
    from mathutils import Vector
    p = _studs(o)
    a, b, c, d = v6_service_bounds()
    low = np.array((a, 24.05, c))
    high = np.array((b, SERVICE_CEILING_Y if V6_EDITS['service_hanging_ceiling'] else next(z['y'] for z in ZONES if z['name'] == 'Service'), d))
    if np.all(p >= low) and np.all(p <= high):
        return float(wanted)       # own room lights are handled by v6_clip_service_lights
    ext = np.zeros(3)
    if o.data.type == 'AREA':
        for col, size in ((0, o.data.size), (1, o.data.size_y if o.data.shape in ('RECTANGLE', 'ELLIPSE') else o.data.size)):
            v = o.matrix_world.to_3x3().col[col].normalized()
            ext += np.abs(np.array((v.x, v.z, -v.y))) * size / S / 2
    # Invisible exported AREA/Spot holder has a 0.2-stud depth. Allow its face offset and a wall safety margin.
    pad = .35
    separation = np.maximum(low - p - ext, p - high - ext)
    sphere = max(0., float(np.linalg.norm(np.maximum(0., separation))) - pad)
    if o.data.type == 'POINT':
        return min(float(wanted), sphere)
    bl = o.matrix_world.to_3x3() @ Vector((0, 0, -1))
    direction = np.array((bl.x, bl.z, -bl.y))
    direction /= np.linalg.norm(direction)
    angle = float(angle if angle is not None else math.degrees(o.data.spot_size) if o.data.type == 'SPOT' else o.get('l4_angle', 90))
    half = math.radians(angle / 2)
    reach = sphere
    for axis in range(3):
        for sign, gap in ((1, low[axis] - p[axis] - ext[axis]), (-1, p[axis] - high[axis] - ext[axis])):
            if gap <= pad:
                continue
            support = _v6_cone_extent(sign * direction[axis], half)
            if support <= 1e-9:
                return float(wanted)
            reach = max(reach, (gap - pad) / support)
    # A vertical downward cone cannot hit the room below its finished floor; avoid clipping harmless far fills.
    cap = float(wanted)
    if abs(direction[0]) < 1e-7 and abs(direction[2]) < 1e-7 and direction[1] < -.999:
        cap = min(cap, max(0., p[1] + ext[1] + .1 - low[1]))
    return float(wanted) if reach >= cap else min(float(wanted), reach)


def apply_v6_service_no_incoming_bleed():
    """V3 candidate: retain shadowed Core/two Concession fills; split unshadowed fills at shared walls.

    Equality remains a measured render requirement. BLEED_EQUALITY_TUNING holds only explicit calibrated gains.
    """
    from mathutils import Matrix
    names = ('L4 Fixture Lights', 'L4 Lights')
    for coll in (bpy.data.collections.get(n) for n in names):
        if coll:
            for o in list(coll.all_objects):
                if o.name.startswith('L4C_L_V3_Equal_'):
                    bpy.data.objects.remove(o, do_unlink=True)
    lights = list({o.name: o for coll in (bpy.data.collections.get(n) for n in names) if coll
                   for o in coll.all_objects if o.type == 'LIGHT'}.values())
    attr_keys = ('l4_range','l4_angle','l4_brightness','l4_shadows')
    for o in lights:
        saved = o.get('l4_v6_bleed_before')
        if not saved: continue
        s = json.loads(saved)
        o.data.type = s['type']; o.matrix_world = Matrix(s['matrix'])
        o.data.energy = s['energy']; o.data.cutoff_distance = s['cutoff_distance']
        o.data.use_custom_distance = s['custom_distance']
        if o.data.type == 'SPOT':
            o.data.spot_size, o.data.spot_blend = s['spot_size'], s['spot_blend']
        if o.data.type == 'AREA':
            o.data.shape, o.data.size, o.data.size_y = s['shape'], s['size'], s['size_y']
            if hasattr(o.data, 'spread'): o.data.spread = s['spread']
        for key in attr_keys:
            if key in s:
                if s[key] is None:
                    if key in o: del o[key]
                else: o[key] = s[key]
        o.data.use_shadow = bool(o.get('l4_shadows',False))
        for key in ('l4_v6_bleed_before','l4_v6_no_incoming_bleed','l4_v6_final_range'):
            if key in o: del o[key]
    if not V6_EDITS.get('service_no_incoming_bleed'): return []
    tune = globals().get('BLEED_EQUALITY_TUNING', {})
    coll = bpy.data.collections['L4 Fixture Lights']
    records = []
    def save(o):
        s = dict(type=o.data.type,matrix=[list(r) for r in o.matrix_world],energy=o.data.energy,
                 cutoff_distance=o.data.cutoff_distance,custom_distance=o.data.use_custom_distance,
                 spot_size=getattr(o.data,'spot_size',math.pi/3),spot_blend=getattr(o.data,'spot_blend',.65),
                 spread=getattr(o.data,'spread',math.pi),shape=getattr(o.data,'shape','RECTANGLE'),
                 size=getattr(o.data,'size',1.),size_y=getattr(o.data,'size_y',1.))
        s.update({key:o.get(key) for key in attr_keys})
        o['l4_v6_bleed_before'] = json.dumps(s)
        return s
    def finish(o, before, action):
        gain = V6_PLACE_RANGE_GAIN * (1.5/1.3 if o.get('l4_kind')=='star' else 1.)
        reach = min(60.,float(o.get('l4_range',16))*gain)
        o.data.use_custom_distance = True; o.data.cutoff_distance = float(o['l4_range'])*S
        o.data.energy = _energy(o.data.type,float(o['l4_range']),float(o.get('l4_brightness',1)))
        o.data.use_shadow = bool(o.get('l4_shadows',False))
        o['l4_v6_no_incoming_bleed'] = True; o['l4_v6_final_range'] = reach
        records.append(dict(name=o.name,action=action,before=before,pos_after=list(_studs(o)),
                            source_range_after=float(o['l4_range']),final_range_after=reach,
                            brightness_after=float(o.get('l4_brightness',1)),shadows=bool(o.get('l4_shadows',False)),
                            angle_after=float(o.get('l4_angle',math.degrees(o.data.spot_size) if o.data.type=='SPOT' else 360))))
    # Three available shadow slots preserve the three largest otherwise-unavoidable shared-wall halos.
    shadow_names = ('L4C_L_Core_star0','L4C_L_Concession_star2','L4C_L_Concession_star4')
    for name in shadow_names:
        o = bpy.data.objects.get(name)
        if o is None: continue
        before=save(o); o['l4_shadows']=True
        finish(o,before,'unchanged source / size / cone / reach / output; enable wall occlusion')
    # Split each Concourse rectangle along Z; its union retains the exact original emitting face.
    # North half keeps the original cone. South half uses a contained cone instead of moving the whole fill.
    for name in ('L4C_L_Concourse_star6','L4C_L_Concourse_star9','L4C_L_Concourse_star12'):
        o=bpy.data.objects.get(name)
        if o is None: continue
        before=save(o); p=_studs(o); width=o.data.size/S; height=o.data.size_y/S
        north,south=p[2]-height/2,p[2]+height/2
        floor_depth=p[1]+.1-24.05
        cut=v6_service_bounds()[2]-.36-floor_depth*math.tan(math.radians(before['l4_angle']/2))
        cut=math.floor(cut*100)/100
        first,second=cut-north,south-cut
        assert first>0 and second>0,(name,cut,north,south)
        o.matrix_world.translation=_b((p[0],p[1],(north+cut)/2)); o.data.size_y=first*S
        o['l4_brightness']=before['l4_brightness']*(first/height)*float(tune.get(name+'_north',1))
        finish(o,before,'north face retained at original 85-degree cone')
        q=(p[0],p[1],(cut+south)/2)
        extra=_mklight(dict(type='AREA',pos=q,color=tuple(o['l4_color']),range=before['l4_range'],
                           b=before['l4_brightness']*(second/height)*float(tune.get(name+'_south',1)),kind='star',
                           shadows=False,size=(width,second),face=(0,-1,0),along=(1,0,0),angle=24),
                       'L4C_L_V3_Equal_'+name,coll)
        extra['l4_zone']=int(o.get('l4_zone',23)); extra['l4_angle']=24
        finish(extra,{},'south face at original position; 24-degree contained cone')
    # Border practicals keep all north-facing directions rather than v2's 60-degree downward cone.
    for name in ('L4D_fl_s22676_mag_22676_3','L4D_fl_s22709_mag_22710_3','L4D1_Sconce_2405','L4C_L_Concourse_1'):
        o=bpy.data.objects.get(name)
        if o is None: continue
        before=save(o); o.data.type='SPOT'; o.data.spot_size=math.radians(179.8); o.data.spot_blend=0
        o.matrix_world=Matrix.Translation(o.matrix_world.translation)@_orient((0,0,-1),(1,0,0))
        if 'l4_angle' in o: del o['l4_angle']
        o['l4_brightness']=before['l4_brightness']*float(tune.get(name,1))
        finish(o,before,'179.8-degree north hemisphere; original position / reach')
    # The sign must be safe even while the automatic door is open. Its lobby hemisphere has no southern rays.
    # A thin rectangular upwash reproduces the sign/header halo without reaching the Service volume.
    o=bpy.data.objects.get('C_ServiceSignGlow')
    if o is not None:
        before=save(o); p=_studs(o)
        o.data.type='SPOT'; o.data.spot_size=math.radians(179.8); o.data.spot_blend=0
        o.matrix_world=Matrix.Translation(o.matrix_world.translation)@_orient((0,0,-1),(1,0,0))
        o['l4_shadows']=False; o['l4_brightness']=before['l4_brightness']*float(tune.get('sign_north',1))
        finish(o,before,'door-independent north hemisphere at original sign position / reach')
        extra=_mklight(dict(type='AREA',pos=tuple(p),color=tuple(o['l4_color']),range=before['l4_range'],
                           b=before['l4_brightness']*float(tune.get('sign_upwash',1)),kind='sign',shadows=False,
                           size=(14,.1),face=(0,1,.15),along=(1,0,0),angle=23.8),
                       'L4C_L_V3_Equal_SignUpwash',coll)
        extra['l4_zone']=int(o.get('l4_zone',23)); extra['l4_angle']=23.8
        finish(extra,{},'14-stud original-position sign/header upwash; strictly contained 23.8-degree envelope')
    o=bpy.data.objects.get('L4C_L_neon_27')
    if o is not None:
        before=save(o); o.matrix_world=Matrix.Translation(o.matrix_world.translation)@_orient((0,1,-1),(1,0,0))
        o['l4_angle']=90; o.data.spread=math.pi/2
        o['l4_brightness']=before['l4_brightness']*float(tune.get(o.name,1))
        finish(o,before,'upward-north 90-degree SurfaceLight; full face / reach retained')
    o=bpy.data.objects.get('L4D2_ArcNeon0')
    if o is not None:
        before=save(o); wanted=min(60.,float(o['l4_range'])*V6_PLACE_RANGE_GAIN)
        o['l4_range']=v6_incoming_service_limit(o,wanted)/V6_PLACE_RANGE_GAIN
        o['l4_brightness']=before['l4_brightness']*float(tune.get(o.name,1))
        finish(o,before,'2-percent range containment; calibrated own-side output')
    # Same-colour own-side replacements for the removed f5 / Bulkhead0 outgoing Concourse illumination.
    # Initial gains are candidates; acceptance requires the matched native-build luminance table.
    default_fills = (
        dict(type='SPOT',pos=(22862,45.19,97.2),color=(232,240,234),range=32.8,
             b=1.1*float(tune.get('outgoing_f5',.70)),kind='service_neighbour_equal',shadows=False,
             face=(0,0,-1),along=(1,0,0),angle=179.8,zone=23),
        dict(type='SPOT',pos=(22864,38.6,98.66),color=(211,235,162),range=22.,
             b=.5*float(tune.get('outgoing_bulkhead',.72)),kind='service_neighbour_equal',shadows=False,
             face=(0,0,-1),along=(1,0,0),angle=179.8,zone=23))
    for n,L in enumerate(globals().get('BLEED_EQUALITY_FILLS',default_fills),1):
        extra=_mklight(L,'L4C_L_V3_Equal_Fill_%02d'%n,coll)
        extra['l4_zone']=int(L.get('zone',23))
        if extra.data.type=='SPOT': extra.data.spot_blend=0
        finish(extra,{},'calibrated own-side equality fill; contained envelope')
    bpy.context.view_layer.update()
    all_lights=list({o.name:o for coll in (bpy.data.collections.get(n) for n in names) if coll
                     for o in coll.all_objects if o.type=='LIGHT'}.values())
    a,b,c,d=v6_service_bounds(); cy=SERVICE_CEILING_Y
    for o in all_lights:
        p=_studs(o)
        if a<=p[0]<=b and c<=p[2]<=d and 24.05<=p[1]<=cy: continue
        if o.get('l4_shadows'): continue  # Native wall-occlusion ray audit is additionally mandatory for these sources.
        gain=V6_PLACE_RANGE_GAIN*(1.5/1.3 if o.get('l4_kind')=='star' else 1.)
        reach=min(60.,float(o.get('l4_range',o.data.get('l4_range',16)))*gain)
        assert v6_incoming_service_limit(o,reach)>=reach-1e-6,'V3 incoming envelope: '+o.name
    assert len(all_lights)<=BUDGET
    assert sum(bool(o.get('l4_shadows',False)) for o in all_lights)<=SHADOW_MAX
    return records

def apply_v6_star_density(density=None, zones=None):
    """Replace only pooled star meshes for the comparison, with identical geometry and materials at 100%."""
    if 'slot' not in globals():
        exec(open(os.path.join(HERE, 'slots.py'), encoding='utf-8').read(), globals())
    global STAR_DENSITY
    if density is not None:
        STAR_DENSITY = float(density)
    out = {}
    for z in ZONES:
        if z['kind'] != 'star' or (zones is not None and z['name'] not in zones):
            continue
        zp = plan_star(z)
        _, stars, _ = star_geometry(zp)
        out[z['name']] = dict(collections.Counter(s[5] for s in zp['stars']))
        for g in GROUPS:
            o = bpy.data.objects.get('L4C_Stars_%s_%s' % (z['name'], g))
            if o is not None:
                if stars[g].F:
                    o.data = _mkmesh(stars[g], o.name, origin=(OX, 0, 0))
                    o.hide_render = False
                else:
                    o.data = bpy.data.meshes.new(o.name)
    return out


def build_ceilings():
    """Build every ceiling zone and the light plan; -> stats dict."""
    g = globals()
    if "slot" not in g:
        exec(open(os.path.join(HERE, "slots.py"), encoding="utf-8").read(), g)
    for k, v in SLOT_FALLBACK.items():
        g["SLOTS"].setdefault(k, v)
    mine, lcol, gone = _clear()
    plans = plan_all()
    globals()['LAST_CEILING_PLANS'] = plans
    stats = collections.Counter(deleted=sum(gone.values()))
    # floors for the Service's fallen tiles, before any of our own geometry exists
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
        if zp["z"]["kind"] == "act":
            mb, flick = act_geometry(zp)
            stars = {}
        else:
            mb, stars, flick = star_geometry(zp)
        o = _mkobj(mb, "L4C_" + zn, mine)
        if zp.get("cols") and o is not None:
            o.data["l4_col"] = json.dumps([_bl_box(lo, hi) for lo, hi in zp["cols"]])
            o["l4_collide"] = "bounds"
            o["l4_occluder"] = True
            stats["colliders"] += len(zp["cols"])
        stats["tris"] += mb.tris()
        stats["objects"] += 1
        for gk, smb in stars.items():
            so = _mkobj(smb, "L4C_Stars_%s_%s" % (zn, gk), mine)
            if so is not None:
                so["l4_tags"] = "L4StarTwinkle" + gk
                stats["star_tris"] += smb.tris()
                stats["objects"] += 1
        stats["stars"] += len(zp.get("stars", []))
        hosts = []
        for k, f in enumerate(flick):
            if "mb" in f:
                po = _mkobj(f["mb"], "L4C_FlickerLens_%s_%d" % (zn, k), mine, origin=f["pos"])
                stats["tris"] += f["mb"].tris()
            else:
                po = bpy.data.objects.new("L4C_FlickerLens_%s_%d" % (zn, k), _lens_mesh(f["shape"], f["mat"]))
                po.location = _b(f["pos"])
                po.scale = (f["size"][0] * S, f["size"][1] * S, 1)     # local X = Studio X, local Y = Studio -Z
                mine.objects.link(po)
                stats["tris"] += 2
            po["l4_prop"] = "FlickerLens"
            po["l4_model"] = "FlickerLens"
            po["l4_attrs"] = '{"OccasionalFlicker": true}'
            hosts.append((po, f))
            stats["objects"] += 1
            stats["flicker_props"] += 1
        bpy.context.view_layer.update()
        n = 0
        for po, f in hosts:
            for L in f["lights"]:
                _mklight(L, "L4C_L_%s_f%d" % (zn, n), lcol, host=po); n += 1
                stats["lights_flicker"] += 1
        for L in [t["light"] for t in zp.get("troffers", []) if t.get("light") and t["state"] != "flicker"] + \
                 [L for L in zp["lights"] if not L.get("host")]:
            _mklight(L, "L4C_L_%s_%d" % (zn, n), lcol); n += 1
            stats["lights_" + L["kind"]] += 1
        for key in ("troffers", "holes", "sag", "stain", "grilles", "cages"):
            stats[key] += len(zp.get(key, []))
    for zn, shards in falls:
        for k, (mb, h) in enumerate(shards):
            _mkobj(mb, "L4C_FallenTile_%s_%d" % (zn, stats["fallen_shards"]), mine)
            stats["fallen_shards"] += 1
            stats["tris"] += mb.tris()
            stats["objects"] += 1
        stats["fallen_tiles"] += 1
    bpy.context.view_layer.update()
    # build_all runs final_lighting_pass after decay. Keep the original Service
    # allocation until that final pass, then replace 16 lights with 9 and reserve
    # the freed slots for neighbour equivalents, without replanning other rooms.
    lp, plan, removed = light_pass(plans, lcol, apply_service=False)
    stats.update({"pass_" + k: v for k, v in lp.items()})
    stats["lights"] = sum(1 for o in lcol.all_objects if o.type == "LIGHT" and o.get("l4_pkg") == "ceilings")
    print("L4 ceilings:", dict(stats))
    print("L4 ceilings deleted:", dict(gone))
    print("L4 light plan:", json.dumps(plan))
    print("L4 lights removed by the pass:", removed)
    globals()["LAST_PLAN"] = dict(stats=dict(stats), plan=plan, removed=removed, deleted=dict(gone))
    return dict(stats)


if __name__ == "__main__":                        # planner self-check, no Blender needed
    import time
    t0 = time.time()
    plans = plan_all()
    tot = collections.Counter()
    for zp in plans:
        nm = zp["z"]["name"]
        area = int(zp["mask"].sum())
        assert area > 0, nm + ": empty ceiling"
        x0, z0 = zp["x0"], zp["z0"]
        if zp["z"].get("bulkheads"):
            booth = _NAMES.index("%s/%s_BoothRoof" % (nm, nm))
            assert zp["mask"][int(_CTR[booth, 2] - z0), int(_CTR[booth, 0] - x0)], nm + ": open upper deck above booth"
        rr, cc = np.nonzero(zp["mask"])
        for r, c in zip(rr[::97], cc[::97]):
            assert not in_removed(x0 + c + .5, zp["z"]["y"] - 1, z0 + r + .5), nm + ": ceiling in the removed zone"
        if zp["z"]["kind"] == "act":
            mb, flick = act_geometry(zp)
            for t in zp["troffers"]:
                X0, X1, Z0, Z1 = t["rect"]
                assert sorted((X1 - X0, Z1 - Z0)) == [2, 4], nm + ": troffer scale"
            st = collections.Counter(f["state"] for f in zp["troffers"])
            nl = sum(1 for f in zp["troffers"] if f.get("light")) + len(zp["lights"])
            if V6_EDITS['item4_service_pools'] and nm == 'Service':
                assert st['lit'] + st['flicker'] == round(len(zp['troffers']) / 3) and nl == 6
                for t in zp['troffers']:
                    if t.get('light'):
                        L = t['light']; reach = L['range'] * V6_PLACE_RANGE_GAIN
                        assert v6_service_cone_range(L['pos'], L['face'], L['angle'], reach) >= reach - 1e-6
            print("%-18s area %6d  troffers %4d  lights %3d  missing %2d sag %2d  tris %6d  %s"
                  % (nm, area, len(zp["troffers"]), nl, len(zp["holes"]), len(zp["sag"]), mb.tris(), dict(st)))
            tot.update(tris=mb.tris(), lights=nl)
            continue
        mb, stars, flick = star_geometry(zp)
        assert zp["decks"] and all(box in zp["cols"] for box in zp["decks"]), nm + ": roof/collider mismatch"
        bottom_area = sum(abs(_newell([mb.V[i] for i in face])[1]) / 2 for face, mat in zip(mb.F, mb.M)
                          if mb.mats[mat] == "headliner" and all(abs(mb.V[i][1] - zp["z"]["y"]) < 1e-6 for i in face))
        assert abs(bottom_area - sum((hi[0] - lo[0]) * (hi[2] - lo[2]) for lo, hi in zp["decks"])) < 1e-5, nm + ": structural roof lost to placement mask"
        if nm == "Gallery":
            assert any(lo[0] <= 23000 <= hi[0] and lo[2] <= -2.5 <= hi[2] for lo, hi in zp["decks"]), "Gallery: cove-to-roof slot"
            for i in _GALLERY_ROOFS:
                assert any(abs(lo[0] - _LO[i, 0]) < 1e-6 and abs(hi[0] - _HI[i, 0]) < 1e-6
                           and abs(lo[2] - _LO[i, 2]) < 1e-6 and abs(hi[2] - _HI[i, 2]) < 1e-6
                           for lo, hi in zp["decks"]), "Gallery: widened roof lost to placement mask"
        if nm == "Concession":
            assert any(lo[0] <= 23000 <= hi[0] and lo[2] <= 170 <= hi[2] for lo, hi in zp["decks"]), "Concession: fascia-to-roof slot"
        ns, stris = len(zp["stars"]), sum(s.tris() for s in stars.values())
        free_area = area - (0 if not zp["coffers"] else 0)
        for x, zz, ys, s, tier, g, yaw in zp["stars"][::53]:
            assert 0.079 <= s <= 0.251 and g in GROUPS, (nm, s, g)
            assert not in_removed(x, ys, zz), nm + ": star in the removed zone"
        tiers = collections.Counter(s[4] for s in zp["stars"])
        if STAR_DENSITY < 1:
            counts = collections.Counter(s[5] for s in zp['stars'])
            assert max(counts.values()) - min(counts.values()) <= 1, nm + ': twinkle balance'
        if nm in ('Concourse', 'A2'):
            selected_density = STAR_DENSITY
            STAR_DENSITY = 1
            original = plan_star(zp['z'])['stars']
            STAR_DENSITY = selected_density
            assert zp['stars'] == v6_thin_stars(original), nm + ': selected density'
            previous = set(original)
            for density in (.75, .5, .25):
                thin = v6_thin_stars(original, density)
                counts = collections.Counter(s[5] for s in thin)
                assert len(thin) == round(len(original) * density) and set(thin) <= previous
                assert max(counts.values()) - min(counts.values()) <= 1
                previous = set(thin)
        print("%-18s area %6d  stars %6d (%.2f/sq)  star tris %6d  deck tris %6d  cols %3d  lights %2d  flick %d  %s"
              % (nm, area, ns, ns / area, stris, mb.tris(), len(zp["cols"]), len(zp["lights"]), len(flick),
                 dict(tiers)))
        fill = star_fill_plan(zp, 3)
        assert fill and all(L["range"] <= 60 for L in fill), nm
        tot.update(tris=mb.tris(), star_tris=stris, stars=ns, cols=len(zp["cols"]), lights=len(zp["lights"]),
                   area=area)
    print(dict(tot), "%.1f s" % (time.time() - t0))
    assert 0.14 * STAR_DENSITY < tot["stars"] / tot["area"] < 0.24 * STAR_DENSITY, "star density"
    assert tot["star_tris"] <= 185000, "star triangle budget"
    assert tot["lights"] <= 80, "fixed ceiling lights"
    assert _hue_class((152, 96, 56)) == "amber" and _hue_class((255, 40, 200)) == "magenta" \
        and _hue_class((40, 230, 255)) == "cyan" and _hue_class((255, 240, 214)) is None
    assert _hue_class(GALLERY_LIGHT) == 'amber', 'Gallery output must remain an orange cove light on repeat passes'
    assert len([l for l in _L['lights'] if CORE_LAMP.search(l['p'])]) == 6, 'Core lamp replacement scope'
    print("ok")
