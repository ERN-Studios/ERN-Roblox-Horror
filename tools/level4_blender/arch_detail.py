# Level 4 facelift, package A: architecture detailing and edge treatment.
#
# Implements r8.md section B (B1 classification, B2.1 baseboards incl. stepped stringer skirts, B2.2
# wainscot re-profile + brass cap rails, B2.3 crown / cove mouldings incl. the rebuilt projecting
# cornices and housed neon coves, B2.5 door casings + hollow-metal frames, B2.6 nosings + amber step
# lights, B2.7 handrails), r8 0.3 defect 1 (bevelled architecture boxes), the A1 north / south facades
# (acoustic panels, reeded deco pilasters with colliders, frieze + stepped cornices), the concourse
# column cladding and the neon along the corridor and concourse end walls.
#
# Synthwave language (owner pick F, 2026-09-30): the facades are matte black acoustic fabric panels
# (WALLPAPER_MAIN) on the texture's 8.57-stud world grid with real recessed reveals, crossed by thin
# magenta / cyan neon tubes sitting in recessed channels; every cove holds a real neon tube in its trough;
# the columns are black marble with magenta collar rings and cyan tubes in vertical channels. The neon is
# built one tube per 8.57-stud module, and each run gets dead stretches (~18 %, dead tubes, no light) and
# ~7 % flickering tubes (instanced "NeonFlicker" props, l4_attrs OccasionalFlicker, a PointLight inside
# on the runs that carry lights; the flicker script toggles PointLights only) so the
# concourse reads half dark in places. restyle_architecture() puts the CARPET_* / WALLPAPER_MAIN slots on
# the build_base floors and walls of the concourse, corridors and auditoria.
#
# Run in Blender after build_base / props / doors:
#     exec(open(slots.py).read()); exec(open(arch_detail.py).read()); build_detailing()
# build_detailing() is idempotent: it first removes its own output (collection "L4 Detail" and the
# lights it put in "L4 Fixture Lights", tagged l4_pkg = "A_detailing").
# `python arch_detail.py` (no Blender) runs the layout analysis self-check only.
#
# Everything is computed from l4_layout.json in Studio studs (Roblox axes, floor top Y 24) and converted
# to Blender metres when the meshes are made: blender = ((X - 23000) * 0.28, -Z * 0.28, Y * 0.28).
# All detail meshes are plain pooled meshes at the identity transform, so mesh["l4_col"] boxes are in
# Blender world metres (the flicker tubes are the only instanced objects).
# Lights (collection "L4 Fixture Lights", l4_pkg = "A_detailing", l4_kind): AREA facing up over the lit
# cove tubes and facing down under the magenta facade line (-> SurfaceLight), DISK over each lit column
# collar, POINT inside each flickering tube; no shadows. The layout colliders of ConcourseColumn / ConcourseColumnBase must stay: the new
# cladding is built inside them and carries no collider of its own.
import json, math, os, re, random, collections
import numpy as np

try:
    import bpy
except ImportError:                       # plain Python: layout analysis + self-check only
    bpy = None

HERE = r"G:\Roblox\MongoTV\tools\level4_blender"
S, OX = 0.28, 23000.0
PKG = "A_detailing"
MOD = 2.4 / S                             # 8.571 studs: WALLPAPER_MAIN repeat (world grid from X 23000 / Z 0);
                                          # its baked reveals sit at 1/4, 1/2, 3/4, the geometric ones at 0
if bpy and "slot" not in globals():
    exec(open(os.path.join(HERE, "slots.py")).read(), globals())
P = json.load(open(os.path.join(HERE, "l4_layout.json")))["parts"]

# Architecture objects (build_base l4_path) this package deletes and rebuilds.
REPLACES = [
    r"^Concourse/A\d_(Pilaster|PilasterBase|ProjectingCornice|CorniceCove|CorniceReturn)$",
    r"^Concourse/South(Pilaster|PilasterBase|FacadeCornice|FacadeUpperPlaster)$",
    r"^Concourse/Cove_(South|East|Core|WestMouth)$",
    r"^Concourse/(ColumnWornStone|ConcourseColumn|ConcourseColumnBase|ConcourseColumnAmberCollar)$",
    r"^A\d/A\d_WallCove$",
    r"^Concourse/\w+Doorway(DeepJamb|DeepHeader|Frame_Head|Frame_Jamb)$",
    r"^A\d/A\d_(Entry|Exit|BoothDoor)Frame_(Head|Jamb)$",
    r"^HiddenService/ConcealedPosterFrame_(Head|Jamb)$",
    r"^Restrooms/(Men|Women)_Door(Jamb|Lintel)$",
    r"^C\d/C\d_StairA\d(East|West)_(AmberRiser|Handrail|LandingRail)$",
    r"^HiddenService/(EastFlight_AmberNosing|EastFlight_WallHandrail|WestFlight_WallHandrail)$",
    r"^A\d/A\d_(StepDot|CrossAisleEdge)$",
    r"^CentralFork/Orange(ForkCove|CornerJoint)$",
    r"^HiddenService/GalleryNorthCove$",
]
_REP = re.compile("|".join(REPLACES))
# build_base.py REPLACED: parts modelled as props elsewhere (matched on the path with digits collapsed)
_PROPS = re.compile(
    r"^AutomaticDoors/(?!.*_Post$)|_Chair(Seat|Back)$|^Arcade/Arcade(Left|Right)#_"
    r"|/(Lobby|WallCafe|Standing)Table(Foot|Rim|Stem|Top)$|/WallCafeChair(Back|Leg|Seat)$"
    r"|/ConcourseColumn(AmberCollar|Base)?$|^Concession/PopcornCase/|^Restrooms/(Men|Women)_(Sink|Toilet)/"
    r"|^Service/StockBox/|^Service/(North|South)ServiceExtinguisher$|^Service/JanitorCart/"
    r"|/ArcadeStool(Seat|Stem)$|/Lobby(Bench|Sofa)(Back|Seat|Arm)$")

# ------------------------------------------------------------------------------------------ layout
N = len(P)
CEN = np.array([p["cf"][:3] for p in P], float)
ROT = np.array([p["cf"][3:] for p in P], float).reshape(-1, 3, 3)
HSZ = np.array([p["s"] for p in P], float) / 2
EXT = np.einsum("nij,nj->ni", np.abs(ROT), HSZ)
LO, HI = CEN - EXT, CEN + EXT
AXAL = np.all(np.abs(np.abs(ROT) - np.round(np.abs(ROT))) < 1e-3, axis=(1, 2))
PATH = [p["p"] for p in P]
NAME = [x.rsplit("/", 1)[-1] for x in PATH]
TOP = [x.split("/")[0] for x in PATH]
MAT = [p["m"] for p in P]
VIS = np.array([p["t"] < 0.95 for p in P])
FLOOR = np.array(["Level4V4Floor" in (p.get("tags") or []) for p in P])
PROP = np.array([bool(_PROPS.search(re.sub(r"\d+", "#", x))) for x in PATH])
MINE = np.array([bool(_REP.search(x)) for x in PATH])
RAIL = MINE & np.array([bool(re.search(r"Handrail|LandingRail", x)) for x in PATH])
DOORP = np.array([x.startswith("AutomaticDoors/") for x in PATH])
NEON = np.array([m == "Neon" for m in MAT])
# Solids that interrupt generated trims. Replaced parts still block: their new versions sit in the same
# place (pilasters, cornices, casings); emissive strips, props, door leaves and rails do not.
BLOCK = VIS & ~PROP & ~DOORP & ~NEON & ~RAIL
EXTRA = []                                  # generated solids (casings, plinths) that also block trims
VIS_OK = np.array([not x.startswith("Removed/") for x in PATH])    # layout_edits tombstones (index-aligned dump)

# v3 owner points 12/13: Cinema 1's west side is walled off at X 22676 and everything behind it is removed from the
# layout. Nothing of this package may stand there, whether or not the layout in hand still has those parts:
# trims are cut out of these boxes (free()), and every builder skips sources inside them. (lo, hi) in studs.
REMOVED_ZONES = [
    (np.array([22600.0, -50.0, -260.0]), np.array([22676.0, 400.0, -21.0])),    # C1 + its stair/return corridor
    (np.array([22600.0, -50.0, -21.0]), np.array([22676.0, 84.9, 0.0])),        # north passage under the gallery
    (np.array([22600.0, -50.0, 0.0]), np.array([22647.0, 84.9, 98.0])),         # west passage beside the core
    (np.array([22646.0, -50.0, 98.0]), np.array([22676.0, 84.9, 99.75])),       # strip south of the core (sealed)
]
CLOSED_OPENINGS = {"A1_EntryWest"}          # A1's west side entry is walled up (no casing on either face)


def in_removed(lo, hi=None, tol=0.05):
    """True when the point lo (hi None) is inside, or the box lo..hi overlaps, a removed zone (beyond tol)."""
    if hi is None:
        return any(np.all(lo > zl) and np.all(lo < zh) for zl, zh in REMOVED_ZONES)
    return any(np.all(lo < zh - tol) and np.all(hi > zl + tol) for zl, zh in REMOVED_ZONES)


def _box_of(rx):
    i = next(i for i, x in enumerate(PATH) if re.search(rx, x))
    return LO[i], HI[i]


ZONES = [(z, *_box_of(rx)) for z, rx in (
    ("Service", r"^Service/ServiceConcrete$"), ("Arcade", r"^Arcade/Arcade_Carpet$"),
    ("Concession", r"^Concession/Concession_RedCarpet$"), ("Concourse", r"^Shell/LobbyCarpet$"))]


def zone_at(x, z, fallback):
    for zn, lo, hi in ZONES:
        if lo[0] - 0.5 <= x <= hi[0] + 0.5 and lo[2] - 0.5 <= z <= hi[2] + 0.5:
            return zn
    return fallback


def _inside(j, p, pad=1e-3):
    q = ROT[j].T @ (p - CEN[j])
    return bool(np.all(np.abs(q) <= HSZ[j] + pad))


def occupied(p, mask=None, skip=()):
    """True when point p (studs) is inside a blocking solid (OBB test)."""
    m = (BLOCK if mask is None else mask) & np.all(LO <= p + 1e-3, 1) & np.all(HI >= p - 1e-3, 1)
    for j in np.nonzero(m)[0]:
        if j not in skip and _inside(j, p):
            return True
    return any(np.all(lo <= p) and np.all(p <= hi) for lo, hi in EXTRA)


def _sub(iv, cuts, minlen=0.5):
    out = [iv]
    for a, b in cuts:
        nxt = []
        for x, y in out:
            if b <= x or a >= y:
                nxt.append((x, y))
                continue
            if a > x:
                nxt.append((x, a))
            if b < y:
                nxt.append((b, y))
        out = nxt
    return [(x, y) for x, y in out if y - x > minlen]


def free(a, s, c, h, h0, h1, y0, y1, depth, skip=(), minlen=0.5, mask=None):
    """Free intervals along axis h of the strip in front of face (axis a, plane c, facing s)."""
    lo, hi = np.empty(3), np.empty(3)
    lo[a], hi[a] = (c, c + depth) if s > 0 else (c - depth, c)
    lo[1], hi[1] = y0, y1
    lo[h], hi[h] = h0, h1
    m = (BLOCK if mask is None else mask) & np.all(LO < hi - 1e-3, 1) & np.all(HI > lo + 1e-3, 1)
    cuts = []
    mid = (lo + hi) / 2
    for j in np.nonzero(m)[0]:
        if j in skip:
            continue
        if AXAL[j]:
            cuts.append((LO[j, h], HI[j, h]))
            continue
        run = None                                       # rotated solid: sample along the strip
        for t in np.arange(max(h0, LO[j, h]), min(h1, HI[j, h]) + 0.2, 0.2):
            q = mid.copy(); q[h] = t
            hit = any(_inside(j, np.array([q[0], yy, q[2]])) for yy in (y0 + 0.05, (y0 + y1) / 2, y1 - 0.05))
            if hit and run is None:
                run = t
            if not hit and run is not None:
                cuts.append((run - 0.1, t - 0.1)); run = None
        if run is not None:
            cuts.append((run - 0.1, min(h1, HI[j, h])))
    for elo, ehi in EXTRA + REMOVED_ZONES:
        if np.all(elo < hi - 1e-3) and np.all(ehi > lo + 1e-3):
            cuts.append((elo[h], ehi[h]))
    return _sub((h0, h1), cuts, minlen)


# ------------------------------------------------------------------------------------------ B1
WALLMAT = {"SmoothPlastic", "Plastic", "Fabric", "CeramicTiles", "Concrete"}
_EXCL = re.compile(r"Poster|Sign|Marquee|Menu|Screen|Board|Counter|Case|Box|Shelf|Stall|Mirror|Window|Glass|Door"
                   r"|Tier|Tread|Aisle|TopWalk|Landing|Roof|Ceiling|Floor|Carpet|Slab|Tile$|Projector|Pack|Wrapper"
                   r"|Tub|Bottle|Roll|Lip|Cap|Slot|Tape|Notice|Canopy|Bridge|Plinth|Seam|Fascia$|Valence|Backer"
                   r"|Cornice|Separator$|Guard")
_SKIRT = re.compile(r"Wainscot|Baseboard|Skirting|PilasterBase|SeparatorBase|ReturnBase|LowerBand|Plinth")


def classify():
    """-> walls, floors, ceilings (part indices) per r8 B1."""
    ext = HI - LO
    walls = [i for i in range(N) if VIS[i] and not PROP[i] and not MINE[i] and AXAL[i] and MAT[i] in WALLMAT
             and ext[i, 1] >= 6 and max(ext[i, 0], ext[i, 2]) >= 3
             and not _SKIRT.search(NAME[i]) and not _EXCL.search(NAME[i])]
    floors = [i for i in range(N) if AXAL[i] and (FLOOR[i] or re.search(r"Carpet$|RedCarpet|ServiceConcrete|Runner$", NAME[i]))]
    ceils = [i for i in range(N) if re.search(r"Roof(Main|CoreNorth|CoreSouth|WestEdge)?$|LowerCeiling|VestibuleCeiling"
                                             r"|SuspendedCeiling|BoothRoof", NAME[i]) and not PATH[i].startswith("Concession/")]
    return walls, floors, ceils


def wall_faces(walls):
    """Exposed faces of wall parts: (i, a, s, c, h)."""
    out = []
    for i in walls:
        lo, hi = LO[i], HI[i]
        for a in (0, 2):
            h = 2 - a
            if hi[h] - lo[h] < 2:
                continue
            for s, c in ((-1, lo[a]), (1, hi[a])):
                ym = (lo[1] + hi[1]) / 2
                if free(a, s, c, h, lo[h], hi[h], ym - 1, ym + 1, 0.3, skip={i}):
                    out.append((i, a, s, c, h))
    return out


def _merge(segs):
    g = collections.defaultdict(list)
    for k, x0, x1, info in segs:
        g[k].append((x0, x1, info))
    out = []
    for k, v in g.items():
        v.sort(key=lambda t: t[0])
        cur = list(v[0])
        for x0, x1, info in v[1:]:
            if x0 <= cur[1] + 0.05:
                cur[1] = max(cur[1], x1)
            else:
                out.append((k, cur[0], cur[1], cur[2])); cur = [x0, x1, info]
        out.append((k, cur[0], cur[1], cur[2]))
    return out


def base_runs(faces, floors):
    """B2.1: (a, s, c, fy) -> merged runs where a floor meets an exposed wall face."""
    segs = []
    for i, a, s, c, h in faces:
        lo, hi = LO[i], HI[i]
        for f in floors:
            fy = HI[f, 1]
            if not (lo[1] - 0.3 <= fy <= hi[1] - 2):
                continue
            s0, s1 = (c, c + 0.6) if s > 0 else (c - 0.6, c)
            if HI[f, a] < s0 + 1e-3 or LO[f, a] > s1 - 1e-3:
                continue
            h0, h1 = max(lo[h], LO[f, h]), min(hi[h], HI[f, h])
            if h1 - h0 < 0.5:
                continue
            for x, y in free(a, s, c, h, h0, h1, fy + 0.1, fy + 0.5, 0.35, skip={i}):
                segs.append(((a, s, round(c, 3), round(fy, 3)), x, y, (i, f)))
    return _merge(segs)


def crown_runs(faces, ceils):
    """B2.3: (a, s, c, cy) -> merged visible runs where a wall face meets a ceiling."""
    segs = []
    for i, a, s, c, h in faces:
        lo, hi = LO[i], HI[i]
        for f in ceils:
            cy = LO[f, 1]
            if not (lo[1] + 2 <= cy <= hi[1] + 0.3):
                continue
            s0, s1 = (c, c + 0.6) if s > 0 else (c - 0.6, c)
            if HI[f, a] < s0 + 1e-3 or LO[f, a] > s1 - 1e-3:
                continue
            h0, h1 = max(lo[h], LO[f, h]), min(hi[h], HI[f, h])
            if h1 - h0 < 0.5:
                continue
            for x, y in free(a, s, c, h, h0, h1, cy - 0.6, cy - 0.1, 0.6, skip={i}):
                segs.append(((a, s, round(c, 3), round(cy, 3)), x, y, (i, f)))
    keep = []
    for k, x0, x1, info in _merge(segs):                    # drop runs hidden above a lower ceiling
        a, s, c, cy = k
        h = 2 - a
        s0, s1 = (c, c + 0.6) if s > 0 else (c - 0.6, c)
        hidden = any(cy - 12 < LO[g, 1] < cy - 0.5 and HI[g, a] > s0 and LO[g, a] < s1
                     and HI[g, h] >= x1 - 0.5 and LO[g, h] <= x0 + 0.5 for g in ceils)
        if not hidden:
            keep.append((k, x0, x1, info))
    return keep


def low_bands():
    """B1 existing low bands: visible, <= 2.5 thick, 1.5-4.6 tall, standing on a floor level."""
    floors = (24.0, 24.05, 24.1, 42.0, 72.0, 86.0)
    ext = HI - LO
    out = []
    for i in range(N):
        if not VIS[i] or MAT[i] in ("Neon", "Glass") or DOORP[i] or PROP[i] or MINE[i]:
            continue
        loc = HSZ[i] * 2
        th, ln = (min(loc[0], loc[2]), max(loc[0], loc[2])) if not AXAL[i] else (min(ext[i, 0], ext[i, 2]), max(ext[i, 0], ext[i, 2]))
        if not (1.5 <= ext[i, 1] <= 4.6) or th > 2.5 or ln < 2:
            continue
        if not any(abs(LO[i, 1] - f) < 0.16 for f in floors):
            continue
        if re.search(r"Tread|Tier|Aisle|Landing|Case|Counter|Table|Chair|Bench|Sofa|Stool|Box|Shelf|Tub|Bottle|Bin|Cart"
                     r"|Stall|Leg|Foot|Stem|Toilet|Sink|Arcade(Left|Right)|Body|Prize|Soda|Candy|Register|Workbench"
                     r"|Cleaning|Threshold|Joint|Curb|Step", PATH[i]):
            continue
        out.append(i)
    return out


# ------------------------------------------------------------------------------------------ mesh kernel
def _n(v):
    v = np.asarray(v, float)
    return v / max(np.linalg.norm(v), 1e-12)


def _newell(pts):
    n = np.zeros(3)
    for p, q in zip(pts, np.roll(pts, -1, axis=0)):
        n += np.cross(p, q)
    return n


def _ccw(prof):
    a = sum(u0 * v1 - u1 * v0 for (u0, v0), (u1, v1) in zip(prof, prof[1:] + prof[:1]))
    return 1.0 if a > 0 else -1.0


Y = np.array([0.0, 1.0, 0.0])
AXV = np.eye(3)


class Geo:
    """Mesh accumulator in studs (Roblox axes); faces are oriented from an outward hint."""

    def __init__(self):
        self.v, self.f, self.fm, self.fs, self.mats = [], [], [], [], []
        self.cols = []                         # collider boxes (lo, hi) in studs

    def _mi(self, m):
        if m not in self.mats:
            self.mats.append(m)
        return self.mats.index(m)

    def vs(self, pts):
        b = len(self.v)
        self.v.extend(tuple(float(c) for c in p) for p in pts)
        return list(range(b, b + len(pts)))

    def face(self, idx, mat, out=None, smooth=False):
        if out is not None and np.dot(_newell(np.array([self.v[i] for i in idx])), out) < 0:
            idx = idx[::-1]
        self.f.append(tuple(idx)); self.fm.append(self._mi(mat)); self.fs.append(smooth)

    def tris(self):
        return sum(len(f) - 2 for f in self.f)

    # -- primitives
    def box(self, lo, hi, mat, e=0.0, axes=None, center=None):
        """Box with chamfered edges (e); axis-aligned from lo/hi, or oriented (axes rows, center, lo=half)."""
        if axes is None:
            lo, hi = np.asarray(lo, float), np.asarray(hi, float)
            c, hsz, ax = (lo + hi) / 2, (hi - lo) / 2, AXV
        else:
            c, hsz, ax = np.asarray(center, float), np.asarray(lo, float), np.asarray(axes, float)
        e = min(e, 0.45 * hsz.min())
        if e <= 1e-4:
            vid = {}
            pts = []
            for sx in (-1, 1):
                for sy in (-1, 1):
                    for sz in (-1, 1):
                        vid[(sx, sy, sz)] = len(pts)
                        pts.append(c + ax[0] * sx * hsz[0] + ax[1] * sy * hsz[1] + ax[2] * sz * hsz[2])
            ids = self.vs(pts)
            for k in range(3):
                for sk in (-1, 1):
                    q = [key for key in vid if key[k] == sk]
                    q.sort(key=lambda t: math.atan2(t[(k + 2) % 3], t[(k + 1) % 3]))
                    self.face([ids[vid[t]] for t in q], mat, ax[k] * sk)
            return
        vid, pts = {}, []
        for sx in (-1, 1):
            for sy in (-1, 1):
                for sz in (-1, 1):
                    sg = (sx, sy, sz)
                    for k in range(3):             # vertex on face k of this corner
                        d = [hsz[m] - e for m in range(3)]
                        d[k] = hsz[k]
                        vid[(sg, k)] = len(pts)
                        pts.append(c + sum(ax[m] * sg[m] * d[m] for m in range(3)))
        ids = self.vs(pts)
        corners = [(sx, sy, sz) for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
        for k in range(3):                         # main faces
            for sk in (-1, 1):
                q = [t for t in corners if t[k] == sk]
                q.sort(key=lambda t: math.atan2(t[(k + 2) % 3], t[(k + 1) % 3]))
                self.face([ids[vid[(t, k)]] for t in q], mat, ax[k] * sk)
        for k in range(3):                         # edge chamfers along axis k
            i, j = (k + 1) % 3, (k + 2) % 3
            for si in (-1, 1):
                for sj in (-1, 1):
                    ends = []
                    for sk in (-1, 1):
                        t = [0, 0, 0]; t[k], t[i], t[j] = sk, si, sj
                        t = tuple(t)
                        ends.append((ids[vid[(t, i)]], ids[vid[(t, j)]]))
                    out = ax[i] * si + ax[j] * sj
                    self.face([ends[0][0], ends[0][1], ends[1][1], ends[1][0]], mat, out, True)
        for t in corners:                          # corner triangles
            self.face([ids[vid[(t, k)]] for k in range(3)], mat, sum(ax[m] * t[m] for m in range(3)), True)

    def panel(self, x0, x1, y0, y1, z, s, depth, mat, e=0.025):
        """Wall panel on the plane Z = z facing s: sides + chamfered front only (no hidden back), 18 tris."""
        zf = z + s * depth
        zc = zf - s * e
        rings = [[(x0, y0, zz), (x1, y0, zz), (x1, y1, zz), (x0, y1, zz)] for zz in (z, zc)]
        rings.append([(x0 + e, y0 + e, zf), (x1 - e, y0 + e, zf), (x1 - e, y1 - e, zf), (x0 + e, y1 - e, zf)])
        ids = [self.vs(r) for r in rings]
        ctr = np.array([(x0 + x1) / 2, (y0 + y1) / 2, z])
        for a, b in ((0, 1), (1, 2)):
            for k in range(4):
                q = [ids[a][k], ids[a][(k + 1) % 4], ids[b][(k + 1) % 4], ids[b][k]]
                mid = np.mean([self.v[j] for j in q], axis=0)
                out = mid - ctr
                out[2] = s if a == 1 else 0.0
                self.face(q, mat, out, smooth=False)
        self.face(ids[2], mat, AXV[2] * s)

    def sweep(self, O, T, Nn, prof, s0, s1, mat, smooth=False, skip_wall=True, caps=True, U=Y):
        """Extrude closed profile [(u, v)] (u along Nn, v along U) along T from s0 to s1."""
        O, T, Nn, U = (np.asarray(x, float) for x in (O, T, Nn, U))
        if s1 < s0:
            s0, s1 = s1, s0
        sg = _ccw(prof)
        r0 = self.vs([O + T * s0 + Nn * u + U * v for u, v in prof])
        r1 = self.vs([O + T * s1 + Nn * u + U * v for u, v in prof])
        n = len(prof)
        for i in range(n):
            j = (i + 1) % n
            (u0, v0), (u1, v1) = prof[i], prof[j]
            if skip_wall and u0 <= 1e-6 and u1 <= 1e-6:
                continue
            self.face([r0[i], r0[j], r1[j], r1[i]], mat, sg * (Nn * (v1 - v0) - U * (u1 - u0)), smooth)
        if caps:
            self.face(r1, mat, T); self.face(r0, mat, -T)

    def wall_sweep(self, a, s, c, h, h0, h1, prof, mat, **kw):
        """Sweep along world axis h on the wall plane (axis a, coordinate c, facing s); v = world Y."""
        Nn = AXV[a] * s
        T = np.cross(Nn, Y)
        ts = T[h]                                  # +-1: sign of T along h
        self.sweep(AXV[a] * c, T, Nn, prof, h0 * ts, h1 * ts, mat, **kw)

    def loft(self, path, closed, D, Nn, prof, mat, field=None, smooth=False):
        """Offset-polyline loft, mitred: profile [(w, u)], w along the segment offsets D, u along Nn."""
        path = [np.asarray(p, float) for p in path]
        D = [np.asarray(d, float) for d in D]
        m = len(path)
        nseg = m if closed else m - 1
        offs = []
        for j in range(m):
            if not closed and j == 0:
                offs.append(D[0]); continue
            if not closed and j == m - 1:
                offs.append(D[nseg - 1]); continue
            a, b = D[(j - 1) % nseg], D[j % nseg]
            o = a + b
            offs.append(o / max(np.dot(o, a), 1e-6))
        sg = _ccw(prof)
        rings = [self.vs([path[j] + offs[j] * w + Nn * u for j in range(m)]) for w, u in prof]
        for i in range(len(prof) - 1):
            (w0, u0), (w1, u1) = prof[i], prof[i + 1]
            for k in range(nseg):
                j0, j1 = k, (k + 1) % m
                out = sg * (D[k] * (u1 - u0) - Nn * (w1 - w0))
                self.face([rings[i][j0], rings[i][j1], rings[i + 1][j1], rings[i + 1][j0]], mat, out, smooth)
        if field is not None and closed:
            self.face(rings[-1], field, Nn)

    def lathe(self, cx, cz, prof, mat, seg=24, phase=0.0, smooth=True, y0=0.0):
        """Surface of revolution about the vertical axis at (cx, cz); profile [(r, y)], CCW-closed."""
        sg = _ccw(prof)
        angs = [phase + 2 * math.pi * k / seg for k in range(seg)]
        rings = [self.vs([(cx + r * math.cos(t), y + y0, cz + r * math.sin(t)) for t in angs]) for r, y in prof]
        for i in range(len(prof) - 1):
            (r0, yy0), (r1, yy1) = prof[i], prof[i + 1]
            if r0 < 1e-6 and r1 < 1e-6:
                continue
            for k in range(seg):
                k1 = (k + 1) % seg
                tm = phase + 2 * math.pi * (k + 0.5) / seg
                rad = np.array([math.cos(tm), 0, math.sin(tm)])
                out = sg * (rad * (yy1 - yy0) - Y * (r1 - r0))
                self.face([rings[i][k], rings[i][k1], rings[i + 1][k1], rings[i + 1][k]], mat, out, smooth)

    def tube(self, pts, r, mat, seg=12, caps=True):
        """Round tube along a polyline with mitred joints."""
        pts = [np.asarray(p, float) for p in pts]
        d = [_n(pts[i + 1] - pts[i]) for i in range(len(pts) - 1)]
        x = np.cross(d[0], Y if abs(d[0][1]) < 0.9 else AXV[0])
        x = _n(x)
        rings = []
        for i, p in enumerate(pts):
            din = d[max(i - 1, 0)]
            x = _n(x - din * np.dot(x, din))
            yv = np.cross(din, x)
            circ = [p + r * (math.cos(2 * math.pi * k / seg) * x + math.sin(2 * math.pi * k / seg) * yv) for k in range(seg)]
            if 0 < i < len(pts) - 1:                 # project onto the bisector plane (mitre)
                t = _n(d[i - 1] + d[i])
                circ = [q - din * (np.dot(q - p, t) / np.dot(din, t)) for q in circ]
            rings.append((self.vs(circ), p))
        for i in range(len(rings) - 1):
            (ra, pa), (rb, pb) = rings[i], rings[i + 1]
            for k in range(seg):
                k1 = (k + 1) % seg
                q = [ra[k], ra[k1], rb[k1], rb[k]]
                ctr = np.mean([self.v[j] for j in q], axis=0)
                ax = _n(pb - pa)
                foot = pa + ax * np.dot(ctr - pa, ax)
                self.face(q, mat, ctr - foot, True)
        if caps:
            self.face(rings[0][0], mat, -d[0]); self.face(rings[-1][0], mat, d[-1])

    def prism(self, poly, y0, y1, mats):
        """Vertical prism from a convex XZ polygon; mats[k] for the side face k -> k+1."""
        c = np.mean(poly, axis=0)
        bot = self.vs([(x, y0, z) for x, z in poly])
        top = self.vs([(x, y1, z) for x, z in poly])
        n = len(poly)
        for k in range(n):
            k1 = (k + 1) % n
            mid = (np.array(poly[k]) + np.array(poly[k1])) / 2 - c
            self.face([bot[k], bot[k1], top[k1], top[k]], mats[k], np.array([mid[0], 0, mid[1]]))


def _lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def rbv(p):
    return ((p[0] - OX) * S, -p[2] * S, p[1] * S)


def bl_box(lo, hi):
    """Studs AABB -> [cx, cy, cz, sx, sy, sz] in Blender metres."""
    c = (np.asarray(lo) + np.asarray(hi)) / 2
    s = np.asarray(hi) - np.asarray(lo)
    return [round(v, 5) for v in (*rbv(c), s[0] * S, s[2] * S, s[1] * S)]


# ------------------------------------------------------------------------------------------ output
COLL = "L4 Detail"
LIGHTS = "L4 Fixture Lights"
STATS = collections.Counter()


def _coll(name, parent="L4 Cinema"):
    c = bpy.data.collections.get(name)
    if not c:
        c = bpy.data.collections.new(name)
        (bpy.data.collections.get(parent) or bpy.context.scene.collection).children.link(c)
    return c


def emit(name, g):
    if not g.f:
        return None
    me = bpy.data.meshes.new("L4D_" + name)
    me.from_pydata([rbv(v) for v in g.v], [], g.f)
    for m in g.mats:
        me.materials.append(m)
    me.polygons.foreach_set("material_index", g.fm)
    me.polygons.foreach_set("use_smooth", g.fs)
    me.validate(clean_customdata=False)
    me.update()
    if g.cols:
        me["l4_col"] = json.dumps([bl_box(lo, hi) for lo, hi in g.cols])
        STATS["colliders"] += len(g.cols)
    o = bpy.data.objects.new("L4D_" + name, me)
    o["l4_pkg"] = PKG
    _coll(COLL).objects.link(o)
    STATS["objects"] += 1
    STATS["tris"] += sum(len(p.vertices) - 2 for p in me.polygons)
    return o


def _bv(d):
    """Studio direction -> Blender direction (mathutils)."""
    from mathutils import Vector
    return Vector((d[0], -d[2], d[1]))


def _light_obj(ld, name, loc, face=None, along=None, rng=16, bright=1.0, parent=None, kind="neon"):
    """Link a light into L4 Fixture Lights. face: Studio direction the light shines to (its local -Z);
    along: Studio direction of its local X (strip lights)."""
    from mathutils import Matrix, Vector
    o = bpy.data.objects.new("L4D_" + name, ld)
    M4 = Matrix.Translation(Vector(rbv(loc)))
    if face is not None:
        z = -_bv(face).normalized()
        x = _bv(along if along is not None else (1, 0, 0) if abs(face[0]) < 0.9 else (0, 0, 1))
        x = (x - z * x.dot(z)).normalized()
        R = Matrix((x, z.cross(x), z)).transposed().to_4x4()
        M4 = M4 @ R
    if parent is not None:
        o.parent = parent
        o.matrix_parent_inverse = parent.matrix_world.inverted()
    o.matrix_world = M4
    o["l4_pkg"], o["l4_range"], o["l4_brightness"], o["l4_shadows"], o["l4_kind"] = PKG, rng, bright, False, kind
    _coll(LIGHTS).objects.link(o)
    STATS["lights"] += 1
    STATS["lights_" + kind] += 1
    return o


def area_light(p0, p1, color, w_per_m, name, width=0.25, rng=16, bright=1.2, face=(0, 1, 0)):
    """Strip light (AREA -> Roblox SurfaceLight) between stud points p0 and p1, shining to face."""
    p0, p1 = np.asarray(p0, float), np.asarray(p1, float)
    ln = max(np.linalg.norm(p1 - p0), 0.5)
    ld = bpy.data.lights.new("L4D_" + name, "AREA")
    ld.shape = "RECTANGLE"
    ld.size, ld.size_y = ln * S, width * S
    ld.color = tuple(_lin(c / 255) for c in color)
    ld.energy = w_per_m * ln * S
    return _light_obj(ld, name, (p0 + p1) / 2, face=face, along=p1 - p0, rng=rng, bright=bright,
                      kind="neon_up" if face[1] > 0.5 else "neon_wall")


# ------------------------------------------------------------------------------------------ neon
P_DEAD_RUN, P_FLICKER = 0.06, 0.08      # per tube: start of a dead stretch (2-6 tubes, ~18 % dark) / flicker


def neon_states(n, key):
    """Deterministic 'on' / 'dead' / 'flicker' per tube for one run."""
    rng = random.Random("l4neon:" + key)
    out = []
    while len(out) < n:
        if rng.random() < P_DEAD_RUN:
            out += ["dead"] * rng.randint(2, 6)
        else:
            out.append("flicker" if rng.random() < P_FLICKER else "on")
    return out[:n]


def modules(s0, s1, org, minlen=1.5):
    """Cut [s0, s1] at the grid org + k * MOD, never leaving a piece shorter than minlen."""
    js = [org + k * MOD for k in range(math.ceil((s0 - org) / MOD), math.floor((s1 - org) / MOD) + 1)]
    e = [s0] + [j for j in js if s0 + minlen < j < s1 - minlen] + [s1]
    return list(zip(e, e[1:]))


def _local_mesh(name, g):
    """Geo built around the origin (studs) -> mesh in local metres (shared by instanced props)."""
    me = bpy.data.meshes.get(name)
    if me:
        return me
    me = bpy.data.meshes.new(name)
    me.from_pydata([(v[0] * S, -v[2] * S, v[1] * S) for v in g.v], [], g.f)
    for mt in g.mats:
        me.materials.append(mt)
    me.polygons.foreach_set("material_index", g.fm)
    me.polygons.foreach_set("use_smooth", g.fs)
    me.update()
    return me


def flicker_prop(me, center, d, length_scale, col, name, rng=9, bright=0.9, light=True):
    """Instanced flickering neon (OccasionalFlicker) with a PointLight inside, so the flicker script dims both.
    me points along its local +X; d = Studio direction of the tube; length_scale scales local X."""
    from mathutils import Matrix, Vector
    o = bpy.data.objects.new("L4D_Flicker_" + name, me)
    q = Vector((1, 0, 0)).rotation_difference(_bv(_n(d)))
    o.matrix_world = Matrix.LocRotScale(Vector(rbv(center)), q, (length_scale, 1, 1))
    o["l4_prop"] = o["l4_model"] = "NeonFlicker"
    o["l4_attrs"] = '{"OccasionalFlicker": true}'
    o["l4_pkg"] = PKG
    _coll(COLL).objects.link(o)
    if light:
        ld = bpy.data.lights.new("L4D_fl_" + name, "POINT")
        ld.color = tuple(_lin(c / 255) for c in NEONRGB[col])
        ld.energy = 60
        ld.shadow_soft_size = 0.05
        _light_obj(ld, "fl_" + name, center, rng=rng, bright=bright, parent=o, kind="neon_flicker")
    STATS["objects"] += 1
    STATS["tris"] += sum(len(p.vertices) - 2 for p in me.polygons)
    return o


def _unit_tube(m, col, r):
    """1 m long neon tube along local X (the flicker instance mesh)."""
    name = "L4D_NeonUnit_%s_%03d" % (col, int(r * 1000))
    if bpy.data.meshes.get(name):
        return bpy.data.meshes[name]
    g = Geo()
    h = 0.5 / S
    g.tube([(-h, 0, 0), (h, 0, 0)], r, m[col], seg=6)
    return _local_mesh(name, g)


def neon_line(g, m, col, O, T, s0, s1, key, r=0.07, org=None, light=None, sleeve=True):
    """Neon tubes along O + T * s, s0..s1, one per MOD module (grid origin org), each with electrode sleeves.
    light = (face, span, range, brightness, w_per_m): one SurfaceLight per span over the lit tubes.
    -> [(sa, sb, state)]"""
    O, T = np.asarray(O, float), _n(T)
    secs = modules(s0, s1, s0 if org is None else org)
    out = []
    for (sa, sb), st in zip(secs, neon_states(len(secs), key)):
        ta, tb = sa + 0.12, sb - 0.12
        if tb - ta < 0.8:
            continue
        p0, p1 = O + T * ta, O + T * tb
        g0, g1 = (p0 + T * 0.2, p1 - T * 0.2) if sleeve else (p0, p1)
        if st == "flicker":
            ln = np.linalg.norm(g1 - g0)
            flicker_prop(_unit_tube(m, col, r), (g0 + g1) / 2, T, ln * S, col, "%s_%d" % (key, len(out)),
                         light=light is not None)
        else:
            g.tube([g0, g1], r, m[col] if st == "on" else m["dead_" + col], seg=6, caps=not sleeve)
        if sleeve:                                       # electrode sleeves (they also cap the tube ends)
            for pe, dd in ((p0, 1), (p1, -1)):
                g.tube([pe, pe + T * dd * 0.26], r * 1.45, m["black"], seg=4)
        out.append((ta, tb, st))
        STATS["neon_" + st] += 1
        STATS["neon_studs"] += round(float(tb - ta), 1)
    if light:
        face, span, rng, bright, wpm = light
        grp = []
        for sec in out + [None]:
            if sec is not None and (not grp or sec[1] - grp[0][0] <= span):
                grp.append(sec)
                continue
            lit = [x for x in grp if x[2] == "on"]
            if lit:
                q0, q1 = O + T * lit[0][0], O + T * lit[-1][1]
                off = np.asarray(face, float) * 0.25
                area_light(q0 + off, q1 + off, NEONRGB[col], wpm, "%s_L%d" % (key, int(lit[0][0])),
                           width=0.3, rng=rng, bright=bright, face=face)
            grp = [sec] if sec is not None else []
    return out


def neon_ring(g, m, col, cx, y, cz, R, r, key, seg=40, light=False):
    """Horizontal neon ring (column collars); flickering rings become an instanced prop."""
    st = neon_states(1, key)[0]
    STATS["neon_" + st] += 1
    prof = [(R + r * math.cos(t), r * math.sin(t)) for t in np.linspace(0, 2 * math.pi, 9)[:-1]]
    prof = prof + prof[:1]
    if st == "flicker":
        name = "L4D_NeonRing_%s_%d" % (col, int(R * 100))
        me = bpy.data.meshes.get(name)
        if not me:
            gl = Geo()
            gl.lathe(0, 0, prof, m[col], seg=seg)
            me = _local_mesh(name, gl)
        return flicker_prop(me, (cx, y, cz), (1, 0, 0), 1.0, col, key, rng=12, bright=1.0, light=light)
    g.lathe(cx, cz, prof, m[col] if st == "on" else m["dead_" + col], seg=seg, y0=y)
    return st == "on"


def clear_output():
    c = bpy.data.collections.get(COLL)
    if c:
        for o in list(c.all_objects):
            me = o.data
            bpy.data.objects.remove(o, do_unlink=True)
            if me and me.users == 0:
                bpy.data.meshes.remove(me)
        bpy.data.collections.remove(c)
    lc = bpy.data.collections.get(LIGHTS)
    if lc:
        for o in list(lc.objects):
            if o.get("l4_pkg") == PKG:
                ld = o.data
                bpy.data.objects.remove(o, do_unlink=True)
                if ld and ld.users == 0:
                    bpy.data.lights.remove(ld)


def delete_replaced():
    """Remove the architecture objects this package rebuilds, and props.py's column assets."""
    n = 0
    for o in list(bpy.data.objects):
        if (o.get("l4_path") and _REP.search(o["l4_path"])) or o.get("l4_prop") == "MarbleColumn":
            bpy.data.objects.remove(o, do_unlink=True)
            n += 1
    return n


# ------------------------------------------------------------------------------------------ materials
NEONRGB = {"mag": (255, 40, 200), "cyan": (40, 230, 255), "mag_dim": (178, 34, 150)}    # sRGB, = the EMIT slots


def M():
    return {k: slot(v) for k, v in dict(
        lac="WAINSCOT_LACQUER", brass="BRASS_AGED", marble="MARBLE_BLACK", paper="WALLPAPER_MAIN",
        plaster="PLASTER_PEEL", alu="ALU_NOSING", steel="STEEL_PAINTED", rubber="RUBBER_BLACK",
        black="PLASTIC_BLACK", chrome="CHROME_PITTED", tile="TILE_CREAM", wood="LAMINATE_WOOD",
        amber="EMIT_AMBER", mag="EMIT_MAGENTA", cyan="EMIT_CYAN").items()} | {
        "mag_dim": slot("EMIT_MAGENTA", tint=NEONRGB["mag_dim"]),
        # dead tubes: unlit glass with a trace of the phosphor colour
        "dead_mag": slot("PORCELAIN", tint=(84, 58, 80)), "dead_cyan": slot("PORCELAIN", tint=(58, 78, 84)),
        "dead_mag_dim": slot("PORCELAIN", tint=(84, 58, 80))}


# ------------------------------------------------------------------------------------------ profiles
# (u = out of the wall, v = up), closed CCW polygons; edges lying on the wall plane (u = 0) are skipped.
PROF_BASE = [(0, 0), (0.12, 0), (0.12, 0.31), (0.105, 0.38), (0.075, 0.425), (0.035, 0.45), (0, 0.45)]
PROF_COVEBASE = [(0, 0), (0.11, 0), (0.1, 0.025), (0.05, 0.06), (0.035, 0.1), (0.035, 0.35), (0, 0.35)]
PROF_TILEBASE = [(0, 0), (0.1, 0), (0.1, 0.04), (0.06, 0.08), (0.05, 0.14), (0.05, 0.5), (0.035, 0.53), (0, 0.53)]


def prof_crown(cy):
    return [(0, cy - 0.62), (0.05, cy - 0.62), (0.07, cy - 0.58), (0.07, cy - 0.5), (0.2, cy - 0.47),
            (0.24, cy - 0.42), (0.27, cy - 0.33), (0.4, cy - 0.29), (0.44, cy - 0.22), (0.5, cy - 0.18),
            (0.53, cy - 0.11), (0.55, cy), (0, cy)]


def prof_angle(cy):                             # ACT wall angle
    return [(0, cy - 0.16), (0.03, cy - 0.16), (0.03, cy - 0.03), (0.16, cy - 0.03), (0.16, cy), (0, cy)]


def prof_cove(cy):
    """Housed cove cornice: stepped fascia, trough floor at cy-1.3, lip top at cy-0.9 (strip hidden)."""
    return [(0, cy - 2.6), (0.18, cy - 2.6), (0.22, cy - 2.55), (0.22, cy - 2.36), (0.5, cy - 2.32),
            (0.55, cy - 2.24), (0.55, cy - 1.98), (0.94, cy - 1.93), (1.0, cy - 1.83), (1.0, cy - 1.58),
            (1.3, cy - 1.53), (1.36, cy - 1.42), (1.38, cy - 1.12), (1.36, cy - 0.96), (1.3, cy - 0.9),
            (1.24, cy - 0.96), (1.24, cy - 1.3), (0, cy - 1.3)]



PROF_NORTH_CORNICE = [(0, 55.8), (1.22, 55.8), (1.3, 55.88), (1.3, 56.72), (1.36, 56.8), (1.64, 56.84),
                      (1.7, 56.92), (1.7, 57.74), (1.76, 57.82), (1.98, 57.86), (2.06, 57.95), (2.12, 58.12),
                      (2.14, 58.34), (2.12, 58.56), (2.06, 58.7), (1.98, 58.76), (1.92, 58.7), (1.92, 58.25),
                      (0, 58.25)]


def prof_wallcove(y):                           # auditorium side-wall cove ledge, strip at y
    return [(0, y - 0.8), (0.3, y - 0.75), (0.72, y - 0.5), (0.8, y - 0.38), (0.84, y - 0.2), (0.84, y + 0.5),
            (0.78, y + 0.56), (0.72, y + 0.5), (0.72, y - 0.25), (0, y - 0.25)]


# nosing (u = out past the edge, v relative to the tread top); tread-top and riser contact edges skipped
PROF_NOSE = [(-0.42, 0.0), (0.0, 0.0), (0.0, -0.28), (0.035, -0.28), (0.035, -0.03), (0.022, 0.012),
             (-0.02, 0.035), (-0.38, 0.035), (-0.42, 0.018)]


# ------------------------------------------------------------------------------------------ builders
def build_baseboards(m, faces, floors):
    runs = base_runs(faces, floors)
    geos = collections.defaultdict(Geo)
    total = 0.0
    by_plane = collections.defaultdict(list)
    for (a, s, c, fy), x0, x1, (wi, fi) in runs:
        h = 2 - a
        xm = (x0 + x1) / 2
        zn = TOP[wi] if TOP[wi] != "Shell" else zone_at(*((xm, c) if h == 0 else (c, xm)), "Shell")
        if zn in ("Service", "HiddenService"):
            prof, mat = PROF_COVEBASE, m["rubber"]
        elif zn == "Restrooms":
            prof, mat = PROF_TILEBASE, m["tile"]
        else:
            prof, mat = PROF_BASE, m["lac"]
        ht = prof[-1][1]
        # external corners: extend past a free end so the boards meet
        for end, dirn in ((x0, -1), (x1, 1)):
            q = np.zeros(3); q[a] = c + s * 0.06; q[1] = fy + 0.2; q[h] = end + dirn * 0.06
            if not occupied(q) and not in_removed(q):
                if dirn < 0:
                    x0 -= prof[1][0]
                else:
                    x1 += prof[1][0]
        g = geos[zn]
        g.wall_sweep(a, s, c, h, x0, x1, [(u, v + fy) for u, v in prof], mat)
        total += x1 - x0
        by_plane[(a, s, c)].append((x0, x1, fy, prof, mat, zn))
    # stepped stringer skirts: a riser return where two runs on one plane meet at different heights
    risers = 0
    for (a, s, c), rs in by_plane.items():
        h = 2 - a
        rs.sort()
        for (ax0, ax1, afy, prof, mat, zn), (bx0, bx1, bfy, _, _, _) in zip(rs, rs[1:]):
            if abs(bx0 - ax1) > 0.3 or abs(bfy - afy) < 0.4:
                continue
            ht, dp = prof[-1][1], prof[1][0]
            lowfy, highfy = min(afy, bfy), max(afy, bfy)
            t = (ax1 + bx0) / 2
            # the return sits on the lower run's side of the step
            h0, h1 = (t - ht, t) if afy < bfy else (t, t + ht)
            lo, hi = np.zeros(3), np.zeros(3)
            lo[a], hi[a] = sorted((c, c + s * dp))
            lo[1], hi[1] = lowfy + ht - 0.01, highfy + ht
            lo[h], hi[h] = h0, h1
            geos[zn].box(lo, hi, mat)
            risers += 1
    for zn, g in geos.items():
        emit("Baseboards_" + zn, g)
    STATS["baseboard_studs"] = round(total)
    STATS["skirt_risers"] = risers
    return len(runs)


def build_crowns(m, runs):
    geos = collections.defaultdict(Geo)
    total = 0.0
    for (a, s, c, cy), x0, x1, (wi, fi) in runs:
        h = 2 - a
        xm = (x0 + x1) / 2
        px, pz = (xm, c) if h == 0 else (c, xm)
        zn = TOP[wi] if TOP[wi] != "Shell" else zone_at(px, pz, "Shell")
        if TOP[wi] == "Concourse" or (abs(cy - 60) < 0.2 and zone_at(px, pz, "") == "Concourse"):
            continue                              # concourse coves are built by build_concourse_coves
        if zn in ("Service", "HiddenService", "Restrooms", "Arcade", "Concession") or "Booth" in NAME[wi]:
            prof, mat = prof_angle(cy), m["alu"]
        else:
            prof, mat = prof_crown(cy), m["lac"]
        g = geos[zn]
        g.wall_sweep(a, s, c, h, x0, x1, prof, mat)
        total += x1 - x0
    for zn, g in geos.items():
        emit("Crown_" + zn, g)
    STATS["crown_studs"] = round(total)
    return runs


def wall_frame(a, s, c, h, x0, x1):
    """Axis-aligned wall run -> (O, T, Nn, s0, s1, org): the frame Geo.sweep / neon_line use, org = the world
    MOD grid expressed along T."""
    Nn = AXV[a] * s
    T = np.cross(Nn, Y)
    ts = T[h]
    s0, s1 = sorted((x0 * ts, x1 * ts))
    return AXV[a] * c, T, Nn, s0, s1, (OX if h == 0 else 0.0) * ts


# cove neon: tube centre (u out of the wall, depth below the ceiling), radius; light = up into the ceiling
COVE_TUBE = (0.86, 1.18, 0.08)
COVE_LIGHT = ((0, 1, 0), 120.0, 20, 1.2, 30)    # span 72 -> 120: level-wide light budget ~300


def cove_run(g, m, O, T, Nn, s0, s1, cy, key, col="mag", org=None, light=COVE_LIGHT):
    """Housed cove cornice (stepped fascia + trough) on the wall plane through O facing Nn, along T; a real
    neon tube lies in the trough below the lip, so from the floor only its glow on the ceiling shows."""
    O = np.array([O[0], 0.0, O[2]], float)
    g.sweep(O, T, Nn, prof_cove(cy), s0, s1, m["lac"])
    u, d, r = COVE_TUBE
    neon_line(g, m, col, O + Nn * u + Y * (cy - d), T, s0 + 0.2, s1 - 0.2, key, r=r, org=org, light=light)
    STATS["cove_studs"] += round(s1 - s0)


def build_concourse_coves(m, runs):
    """Housed magenta cove along the concourse walls at the Y 60 ceiling (the facades have their own), and
    along the CentralFork fascias (rotated walls: built in the old neon's own frame)."""
    g = Geo()
    for (a, s, c, cy), x0, x1, (wi, fi) in runs:
        h = 2 - a
        xm = (x0 + x1) / 2
        px, pz = (xm, c) if h == 0 else (c, xm)
        if abs(cy - 60) > 0.2 or zone_at(px, pz, "") != "Concourse":
            continue
        O, T, Nn, s0, s1, org = wall_frame(a, s, c, h, x0, x1)
        cove_run(g, m, O, T, Nn, s0, s1, cy, "ccove_%d_%d" % (int(c), int(x0)), org=org)
    for i in [i for i in range(N) if PATH[i] == "CentralFork/OrangeForkCove"]:
        R, hs = ROT[i], HSZ[i]
        T, X = R[:, 2], R[:, 0]
        sg = -1 if occupied(CEN[i] + X * 0.4) else 1          # the fascia is on the other side
        Nn = X * sg
        O = CEN[i] - Nn * hs[0]
        cove_run(g, m, O, T, Nn, -hs[2] - 0.4, hs[2] + 0.4, 60.0, "fork_%d" % i)
    emit("Cove_Concourse", g)


def build_wall_coves(m):
    """A#_WallCove: the auditorium side-wall neon becomes a housed ledge with a dim magenta tube inside."""
    g = Geo()
    for i in [i for i in range(N) if re.search(r"^A\d/A\d_WallCove$", PATH[i])]:
        a = 0 if HI[i, 0] - LO[i, 0] < HI[i, 2] - LO[i, 2] else 2
        h = 2 - a
        # the wall is on the side whose probe is occupied
        pl = CEN[i].copy(); pl[a] = LO[i, a] - 0.2
        s, c = (1, LO[i, a]) if occupied(pl) else (-1, HI[i, a])
        y = (LO[i, 1] + HI[i, 1]) / 2
        x0, x1 = LO[i, h], HI[i, h]
        g.wall_sweep(a, s, c, h, x0, x1, prof_wallcove(y), m["lac"])
        O, T, Nn, s0, s1, org = wall_frame(a, s, c, h, x0, x1)
        neon_line(g, m, "mag_dim", O + Nn * 0.42 + Y * (y - 0.17), T, s0 + 0.2, s1 - 0.2, "acove_%d" % i,
                  r=0.07, org=org, light=((0, 1, 0), 160.0, 24, 1.0, 22))
        STATS["cove_studs"] += round(x1 - x0)
    emit("Cove_Auditoria", g)


# ---- bands (B2.2)
def build_bands(m):
    geos = collections.defaultdict(Geo)
    total = 0.0
    for i in low_bands():
        zn = TOP[i] if TOP[i] != "Shell" else zone_at(CEN[i, 0], CEN[i, 2], "Shell")
        staff = zn in ("Service", "HiddenService")
        y0, y1 = LO[i, 1], HI[i, 1]
        g = geos[zn]
        if AXAL[i]:
            a = 0 if HI[i, 0] - LO[i, 0] < HI[i, 2] - LO[i, 2] else 2
            h = 2 - a
            for s, c in ((-1, LO[i, a]), (1, HI[i, a])):
                ym = (y0 + y1) / 2
                if not free(a, s, c, h, LO[i, h], HI[i, h], ym - 0.4, ym + 0.4, 0.25, skip={i}):
                    continue
                for x0, x1 in free(a, s, c, h, LO[i, h], HI[i, h], y0 + 0.08, y1 + 0.2, 0.3, skip={i}):
                    _band_piece(g, m, i, a, s, c, h, x0, x1, y0, y1, staff)
                    total += x1 - x0
        else:                                         # rotated band: local frame, face away from the wall
            R = ROT[i]
            loc = HSZ[i]
            ta = 0 if loc[0] > loc[2] else 2          # local tangent axis
            na = 2 - ta
            T, Nl = R[:, ta], R[:, na]
            for sg in (-1, 1):
                q = CEN[i] + Nl * sg * (loc[na] + 0.25)
                q[1] = (y0 + y1) / 2
                if occupied(q, skip={i}):
                    continue
                Nn = Nl * sg
                c0 = CEN[i] + Nn * loc[na]
                c0[1] = 0
                _band_frame(g, m, c0, T, Nn, -loc[ta], loc[ta], y0, y1, loc[na] * 2, staff)
                total += loc[ta] * 2
                break
    for zn, g in geos.items():
        emit("Wainscot_" + zn, g)
    STATS["band_studs"] = round(total)


def _band_piece(g, m, i, a, s, c, h, x0, x1, y0, y1, staff):
    Nn = AXV[a] * s
    T = np.cross(Nn, Y)
    ts = T[h]
    th = HI[i, a] - LO[i, a]
    _band_frame(g, m, AXV[a] * c, T, Nn, min(x0 * ts, x1 * ts), max(x0 * ts, x1 * ts), y0, y1, th, staff)


def _band_frame(g, m, O, T, Nn, s0, s1, y0, y1, th, staff):
    """Wainscot re-profile on one band face: ribbed field, stiles, baseboard, cap rail."""
    if staff:                                        # staff areas: rubber cove base + wood chair-rail cap
        g.sweep(O, T, Nn, [(u, v + y0) for u, v in PROF_COVEBASE], s0, s1, m["rubber"])
        cap = [(-th, y1 - 0.02), (0.12, y1 - 0.02), (0.14, y1 + 0.03), (0.12, y1 + 0.1), (-th, y1 + 0.1)]
        g.sweep(O, T, Nn, cap, s0, s1, m["wood"], skip_wall=False)
        return
    g.sweep(O, T, Nn, [(0, y0 + 0.4), (0.03, y0 + 0.4), (0.03, y1 - 0.12), (0, y1 - 0.12)], s0, s1, m["lac"])
    n = max(1, int(round((s1 - s0) / 6.0)))
    for k in range(n + 1):                           # stiles every ~6 studs
        t = s0 + (s1 - s0) * k / n
        t = min(max(t, s0 + 0.2), s1 - 0.2)
        ctr = O + T * t + Nn * 0.045 + Y * ((y0 + 0.4 + y1 - 0.12) / 2)
        g.box((0.2, (y1 - y0 - 0.52) / 2, 0.045), None, m["lac"], e=0.02, axes=(T, Y, Nn), center=ctr)
    g.sweep(O, T, Nn, [(u, v + y0) for u, v in PROF_BASE], s0, s1, m["lac"])
    cap = [(-th, y1 - 0.02), (0.02, y1 - 0.02), (0.02, y1 - 0.2), (0.12, y1 - 0.2), (0.2, y1 - 0.14),
           (0.24, y1 - 0.04), (0.24, y1 + 0.04), (0.2, y1 + 0.1), (0.1, y1 + 0.13), (-th, y1 + 0.13)]
    g.sweep(O, T, Nn, cap, s0, s1, m["brass"], skip_wall=False)


# ---- door casings (B2.5)
def _markers():
    return [i for i in range(N) if "Level4V4Doorway" in (P[i].get("tags") or []) and NAME[i] not in CLOSED_OPENINGS
            and VIS_OK[i]]


def _leaves_in(i):
    lo, hi = LO[i] - 1.0, HI[i] + 1.0
    return [j for j in range(N) if re.search(r"_Leaf$", PATH[j]) and np.all(CEN[j] >= lo) and np.all(CEN[j] <= hi)]


CASE_PROF = {    # (w out from the opening edge, u proud)
    "portal": [(0, 0), (0, 0.46), (0.06, 0.54), (0.62, 0.54), (0.68, 0.48), (0.68, 0.34), (0.74, 0.3),
               (1.7, 0.26), (1.76, 0.2), (1.8, 0.0)],
    "casing": [(0, 0), (0, 0.2), (0.06, 0.26), (0.34, 0.26), (0.4, 0.2), (0.9, 0.15), (1.0, 0.08), (1.02, 0.0)],
    "hm": [(0, 0), (0, 0.13), (0.04, 0.16), (0.42, 0.16), (0.45, 0.12), (0.46, 0.0)],
    "poster": [(0, 0), (0, 0.08), (0.03, 0.1), (0.46, 0.1), (0.5, 0.0)],
}


def build_casings(m):
    """Computed before the trims so their bounds interrupt baseboards and wainscots (EXTRA)."""
    g = Geo()
    n = 0
    for i in _markers():
        sz = HI[i] - LO[i]
        a = 0 if sz[0] < sz[2] else 2
        h = 2 - a
        h0, h1, y0, y1 = LO[i, h], HI[i, h], LO[i, 1], HI[i, 1]
        leaves = _leaves_in(i)
        name = NAME[i]
        for s, c in ((-1, LO[i, a]), (1, HI[i, a])):
            # the real face: the outermost solid next to the jambs on this side
            face = c
            for hh0, hh1 in ((h0 - 2.0, h0), (h1, h1 + 2.0)):
                lo, hi = np.zeros(3), np.zeros(3)
                lo[a], hi[a] = sorted((c - s * 0.5, c + s * 1.2))
                lo[1], hi[1] = y0 + 2, y1 - 1
                lo[h], hi[h] = hh0, hh1
                mm = BLOCK & ~FLOOR & np.all(LO < hi, 1) & np.all(HI > lo, 1)
                for j in np.nonzero(mm)[0]:
                    if MINE[j] and re.search(r"Frame_|DeepJamb|DeepHeader|DoorJamb|DoorLintel", PATH[j]):
                        continue
                    fj = HI[j, a] if s > 0 else LO[j, a]
                    if s * (fj - c) < 1.2 and s * (fj - face) > 0:
                        face = fj
            lo, hi = np.zeros(3), np.zeros(3)                  # this face's casing footprint
            lo[a], hi[a] = sorted((face, face + s * 0.6))
            lo[1], hi[1], lo[h], hi[h] = y0, y1 + 1.0, h0 - 1.0, h1 + 1.0
            if in_removed(lo, hi):
                continue
            # the concourse (open) side of the south portals gets the stepped portal casing
            conc = re.match(r"(Restrooms|Arcade|Concessions|Service)Doorway$", name) and s < 0
            if name == "SecretPosterEntry":
                style = "poster" if s > 0 else "hm"
            elif conc:
                style = "portal"
            elif leaves or "Booth" in name or "Gallery" in name or name in ("MenDoorway", "WomenDoorway"):
                style = "hm"
            else:
                style = "casing"
            prof = CASE_PROF[style]
            W = prof[-1][0]
            # head casing stops short of a sign above the opening. Only parts whose bottom is at or above the
            # opening head count: a wall beside the jamb (bottom at the floor) used to give a negative head room,
            # which mirrored the profile into a flat sheet up to 72 studs wide (v3 owner point 12: the thin
            # "wall" X 22602-22738 at Z 2 was GalleryStairEntry's casing measured against CoreEast).
            head_room = W
            lo, hi = np.zeros(3), np.zeros(3)
            lo[a], hi[a] = sorted((face, face + s * max(u for _, u in prof)))
            lo[1], hi[1] = y1 + 0.01, y1 + W
            lo[h], hi[h] = h0 - W, h1 + W
            above = VIS & ~MINE & ~DOORP & np.all(LO < hi - 1e-3, 1) & np.all(HI > lo + 1e-3, 1) & (LO[:, 1] >= y1 - 0.05)
            for j in np.nonzero(above)[0]:
                head_room = min(head_room, LO[j, 1] - y1 - 0.06)
            head_room = max(head_room, 0.3)
            if head_room < W:
                prof = [(w * head_room / W, u) for w, u in prof]
                W = head_room
            Nn = AXV[a] * s
            path = []
            for hh, yy in ((h0, y0), (h0, y1), (h1, y1), (h1, y0)):
                q = np.zeros(3); q[a] = face; q[1] = yy; q[h] = hh
                path.append(q)
            Hd = AXV[h]
            mat = {"portal": m["lac"], "casing": m["lac"], "hm": m["steel"], "poster": m["alu"]}[style]
            g.loft(path, False, [-Hd, Y, Hd], Nn, prof, mat)
            n += 1
            umax = max(u for _, u in prof)
            lo, hi = np.zeros(3), np.zeros(3)
            lo[a], hi[a] = sorted((face, face + s * umax))
            for hh0, hh1 in ((h0 - W, h0), (h1, h1 + W)):
                lo[1], hi[1] = y0, y1 + W
                lo[h], hi[h] = hh0, hh1
                EXTRA.append((lo.copy(), hi.copy()))
                if umax > 0.3:                         # jambs proud of the wall within reach: collide
                    g.cols.append((lo.copy(), hi.copy()))
            lo[1], hi[1] = y1, y1 + W
            lo[h], hi[h] = h0 - W, h1 + W
            EXTRA.append((lo.copy(), hi.copy()))
            if style == "portal":                   # brass bullnose on the inner arris + kick guards
                for hh, sgn in ((h0, -1), (h1, 1)):
                    q0 = np.zeros(3); q0[a] = face + s * 0.5; q0[h] = hh - sgn * 0.0 + sgn * 0.06; q0[1] = y0 + 0.02
                    q1 = q0.copy(); q1[1] = y1 + 0.06
                    g.tube([q0, q1], 0.1, m["brass"], seg=8)
                    lo2, hi2 = np.zeros(3), np.zeros(3)
                    lo2[a], hi2[a] = sorted((face + s * 0.54, face + s * 0.58))
                    lo2[1], hi2[1] = y0 + 0.05, y0 + 2.6
                    lo2[h], hi2[h] = sorted((hh + sgn * 0.08, hh + sgn * 0.6))
                    g.box(lo2, hi2, m["chrome"], e=0.01)
                q0 = np.zeros(3); q0[a] = face + s * 0.5; q0[1] = y1 + 0.06; q0[h] = h0 - 0.06
                q1 = q0.copy(); q1[h] = h1 + 0.06
                g.tube([q0, q1], 0.1, m["brass"], seg=8)
        # jamb liner through the wall thickness (one per opening)
        th = HI[i, a] - LO[i, a]
        liner = m["steel"] if (leaves or name in ("MenDoorway", "WomenDoorway")) else m["lac"]
        for hh, sgn in ((h0, 1), (h1, -1)):
            lo, hi = np.zeros(3), np.zeros(3)
            lo[a], hi[a] = LO[i, a] - 0.02, HI[i, a] + 0.02
            lo[1], hi[1] = y0 + 0.02, y1
            lo[h], hi[h] = sorted((hh, hh + sgn * 0.08))
            g.box(lo, hi, liner, e=0.015)
        lo, hi = np.zeros(3), np.zeros(3)
        lo[a], hi[a] = LO[i, a] - 0.02, HI[i, a] + 0.02
        lo[1], hi[1] = y1 - 0.08, y1
        lo[h], hi[h] = h0 + 0.08, h1 - 0.08
        g.box(lo, hi, liner, e=0.015)
    emit("Casings", g)
    STATS["casings"] = n


# ---- nosings + step lights (B2.6)
def build_nosings(m):
    fl = [i for i in range(N) if FLOOR[i] and AXAL[i]]
    FLO, FHI = LO[fl], HI[fl]
    solid = BLOCK & ~FLOOR
    geos = collections.defaultdict(Geo)
    total, n_runs, pucks = 0.0, 0, 0

    def tops_at(x, z):
        m_ = (FLO[:, 0] <= x) & (FHI[:, 0] >= x) & (FLO[:, 2] <= z) & (FHI[:, 2] >= z)
        return FHI[m_, 1]

    for k, i in enumerate(fl):
        fy = HI[i, 1]
        if HI[i, 1] - LO[i, 1] < 0.4 and not re.search(r"Tread|Tier|Landing|Aisle|TopWalk", NAME[i]):
            continue
        if in_removed(CEN[i]):
            continue
        for a, s in ((0, -1), (0, 1), (2, -1), (2, 1)):
            h = 2 - a
            e = HI[i, a] if s > 0 else LO[i, a]
            cuts = sorted({LO[i, h], HI[i, h]} | {v for j in range(len(fl)) for v in (FLO[j, h], FHI[j, h])
                                                 if LO[i, h] < v < HI[i, h] and FLO[j, a] - 0.3 <= e <= FHI[j, a] + 0.3})
            segs = []
            for x0, x1 in zip(cuts, cuts[1:]):
                if x1 - x0 < 0.3:
                    continue
                xm = (x0 + x1) / 2
                po = np.zeros(3); po[a] = e + s * 0.25; po[h] = xm
                pi_ = np.zeros(3); pi_[a] = e - s * 0.25; pi_[h] = xm
                to = tops_at(po[0], po[2])
                ti = tops_at(pi_[0], pi_[2])
                if not len(to) or (len(ti) and ti.max() > fy + 0.05) or to.max() > fy - 0.4:
                    continue
                drop = fy - to.max()
                if not (0.5 <= drop <= 3.6):
                    continue
                q = po.copy(); q[1] = fy + 0.6; q[a] = e + s * 0.1
                q2 = q.copy(); q2[a] = e - s * 0.1
                if occupied(q, solid) or occupied(q2, solid):
                    continue
                segs.append((x0, x1, drop))
            merged = []
            for x0, x1, d in segs:
                if merged and abs(merged[-1][1] - x0) < 0.05 and abs(merged[-1][2] - d) < 0.05:
                    merged[-1][1] = x1
                else:
                    merged.append([x0, x1, d])
            for x0, x1, drop in merged:
                if x1 - x0 < 2.0:
                    continue
                zn = TOP[i]
                staff = zn == "HiddenService"
                aisle = bool(re.search(r"AisleTread$", NAME[i]))
                stair = bool(re.search(r"_Tread\d+$|Landing$", NAME[i]))
                cross = "RearTier1" in NAME[i]
                led = stair or aisle or cross
                if staff:
                    led = int(re.search(r"\d+$", NAME[i]).group()) % 2 == 0 if re.search(r"Tread\d+$", NAME[i]) else False
                g = geos[zn]
                mat = m["steel"] if staff else m["alu"]
                Nn = AXV[a] * s
                T = np.cross(Nn, Y)
                ts = T[h]
                O = AXV[a] * e + Y * fy
                g.sweep(O, T, Nn, PROF_NOSE, x0 * ts, x1 * ts, mat, skip_wall=False)
                if led:
                    lo, hi = np.zeros(3), np.zeros(3)
                    lo[a], hi[a] = sorted((e + s * 0.03, e + s * 0.045))
                    lo[1], hi[1] = fy - 0.13, fy - 0.07
                    lo[h], hi[h] = x0 + 0.25, x1 - 0.25
                    g.box(lo, hi, m["amber"])
                if aisle:                             # step-light puck on the riser, at the seat-side end
                    ends = []
                    for end, dirn in ((x0, 1), (x1, -1)):
                        q = np.zeros(3); q[a] = e - s * 0.3; q[1] = fy + 1.0; q[h] = end - dirn * 0.4
                        ends.append((occupied(q, solid), end, dirn))
                    ends.sort(key=lambda t: t[0])
                    _, end, dirn = ends[0]
                    hc = end + dirn * 1.1
                    yc = fy - min(drop, 1.0) * 0.55
                    for (hw, vh, u0, u1, mat_) in ((0.36, 0.2, 0.0, 0.06, m["steel"]), (0.26, 0.1, 0.06, 0.075, m["amber"])):
                        lo, hi = np.zeros(3), np.zeros(3)
                        lo[a], hi[a] = sorted((e + s * u0, e + s * u1))
                        lo[1], hi[1] = yc - vh, yc + vh
                        lo[h], hi[h] = hc - hw, hc + hw
                        g.box(lo, hi, mat_, e=0.015 if mat_ is m["steel"] else 0)
                    pucks += 1
                total += x1 - x0
                n_runs += 1
    for zn, g in geos.items():
        emit("Nosings_" + zn, g)
    STATS.update(nosings=n_runs, nosing_studs=round(total), step_lights=pucks)


# ---- handrails (B2.7)
def build_handrails(m):
    g = Geo()
    n_br = 0
    for i in [i for i in range(N) if RAIL[i] and not in_removed(CEN[i])]:
        R, hs = ROT[i], HSZ[i]
        la = int(np.argmax(hs))
        ax = R[:, la]
        p0, p1 = CEN[i] - ax * hs[la], CEN[i] + ax * hs[la]
        # wall side: the horizontal perpendicular whose probe hits a solid first
        side = _n(np.cross(ax, Y)) if abs(ax[1]) < 0.99 else AXV[0]
        best = None
        for sg in (1, -1):
            for d in np.arange(0.1, 1.2, 0.05):
                if occupied(CEN[i] + side * sg * d, BLOCK & ~FLOOR):
                    if best is None or d < best[0]:
                        best = (d, sg)
                    break
        if best is None:
            continue
        gap, sg = best
        wdir = side * sg
        staff = TOP[i] == "HiddenService"
        r = 0.16 if not staff else 0.14
        off = max(0.0, r + 0.26 - gap)                 # hand clearance from the wall
        q0, q1 = p0 - wdir * off, p1 - wdir * off
        gw = gap + off                                  # rail centre -> wall face
        w0, w1 = q0 + wdir * (gw - 0.02), q1 + wdir * (gw - 0.02)
        g.tube([w0, q0, q1, w1], r, m["steel"] if staff else m["black"], seg=12)
        ln = np.linalg.norm(q1 - q0)
        nb = max(2, int(ln // 6) + 1)
        for k in range(nb):
            t = 0.08 + 0.84 * k / (nb - 1)
            c = q0 + (q1 - q0) * t
            foot = c - Y * (r + 0.28)
            wall_pt = foot + wdir * (gw - 0.02)
            g.tube([wall_pt - wdir * 0.07, wall_pt], 0.2, m["brass"], seg=10)           # rosette
            g.tube([wall_pt - wdir * 0.05, foot, c - Y * r * 0.8], 0.055, m["brass"], seg=8, caps=False)
            n_br += 1
    emit("Handrails", g)
    STATS["handrail_brackets"] = n_br


# ---- facades (A1), Synthwave: black acoustic panels on the texture grid, neon in recessed channels
FAC_JOINTS = [(y, y) for y in (34.15, 40.0, 45.85)]   # horizontal reveals (zero width: the panel gaps make them)
FAC_NEON = [("cyan", 52.0), ("mag", 53.8)]   # tube centre heights; each sits in a 0.6-tall channel
PANEL_DEPTH, PANEL_GAP = 0.1, 0.12


def _channels():
    return [(yc - 0.3, yc + 0.3) for _, yc in FAC_NEON]


def acoustic_panels(g, m, z, s, x0, x1, y0, y1, ygaps, holes=()):
    """Matte black acoustic fabric panels (WALLPAPER_MAIN) on the plane Z = z facing s. Vertical reveals
    fall on the texture's world grid (X = 23000 + k * MOD, where the baked reveals leave a gap), horizontal
    ones at ygaps; a black backing shows in every reveal. holes: (x0, x1, y0, y1) openings."""
    ys = sorted({y0, y1} | {v for hx0, hx1, hy0, hy1 in holes for v in (hy0, hy1) if y0 < v < y1})
    zb = z + s * 0.004
    gp = PANEL_GAP / 2
    for b0, b1 in zip(ys, ys[1:]):
        cuts = [(hx0, hx1) for hx0, hx1, hy0, hy1 in holes if hy0 < b1 - 1e-3 and hy1 > b0 + 1e-3]
        for xa, xb in _sub((x0, x1), cuts, 0.8):
            g.face(g.vs([(xa, b0, zb), (xb, b0, zb), (xb, b1, zb), (xa, b1, zb)]), m["black"], AXV[2] * s)
            for ya, yb in _sub((b0, b1), ygaps, 0.5):
                for pa, pb in modules(xa, xb, OX, 1.2):
                    g.panel(pa + gp, pb - gp, ya + gp, yb - gp, z - s * 0.01, s, PANEL_DEPTH + 0.01, m["paper"])
                    STATS["acoustic_panels"] += 1


def _keepouts(z, s, x0, x1, y0, y1, margin=0.9):
    """Parts standing proud of the facade plane in front of a bay (posters, marquees, sconces, signs)."""
    lo, hi = np.array([x0, y0, min(z, z + s * 3)]), np.array([x1, y1, max(z, z + s * 3)])
    mm = VIS & ~PROP & ~DOORP & np.all(LO < hi, 1) & np.all(HI > lo, 1)
    out = []
    for j in np.nonzero(mm)[0]:
        if MINE[j] and re.search(r"Pilaster|Cornice|UpperPlaster|Cove", PATH[j]):
            continue
        front = HI[j, 2] if s > 0 else LO[j, 2]
        if s * (front - z) > 0.03:
            out.append((LO[j, 0] - margin, HI[j, 0] + margin, LO[j, 1] - margin, HI[j, 1] + margin))
    return out + _holes(z, x0, x1, 2.6)


def _holes(z, x0, x1, pad=0.3):
    """Doorway openings (Level4V4Doorway markers) in the facade plane Z = z."""
    return [(LO[i, 0] - pad, HI[i, 0] + pad, LO[i, 1] - 1.0, HI[i, 1] + pad) for i in _markers()
            if LO[i, 2] - 1 < z < HI[i, 2] + 1 and HI[i, 0] > x0 and LO[i, 0] < x1 and LO[i, 1] < 60]


def facade_neon(g, m, z, s, x0, x1, keep, key):
    """The two horizontal neon lines of a bay, broken around anything proud of the wall; the magenta line
    carries a SurfaceLight per ~5 tubes, shining down the wall so it grazes the panels under the line."""
    for col, yc in FAC_NEON:
        cuts = [(k0, k1) for k0, k1, ky0, ky1 in keep if ky0 + 0.6 < yc + 0.4 and ky1 - 0.6 > yc - 0.4]
        for xa, xb in _sub((x0, x1), cuts, 3.0):
            O, T, Nn, s0, s1, org = wall_frame(2, s, z, 0, xa, xb)
            light = ((0, -1, 0), 9 * MOD, 16, 1.1, 12) if col == "mag" else None   # ~1 per 9 tubes (light budget)
            neon_line(g, m, col, O + Nn * 0.075 + Y * yc, T, s0, s1, "%s_%s_%d" % (key, col, int(xa)),
                      r=0.06, org=org, light=light)


def _reeds(g, m, xs, z, s, y0, y1, r):
    Nn = AXV[2] * s
    for x in xs:
        pts0, pts1 = [], []
        for k in range(9):
            ph = -math.pi / 2 + math.pi * k / 8
            d = Nn * math.cos(ph) + AXV[0] * math.sin(ph)
            pts0.append(np.array([x, y0, z]) + d * r)
            pts1.append(np.array([x, y1, z]) + d * r)
        a, b = g.vs(pts0), g.vs(pts1)
        for k in range(8):
            ctr = (np.array(pts0[k]) + pts0[k + 1] + pts1[k] + pts1[k + 1]) / 4
            g.face([a[k], a[k + 1], b[k + 1], b[k]], m["lac"], ctr - np.array([x, ctr[1], z]), True)
        g.face(b, m["lac"], Y); g.face(a, m["lac"], -Y)


def _pilaster(g, m, x0, x1, z, s, dims):
    """Reeded 80s-deco pilaster on the plane Z = z facing s. dims: plinth depth, shaft depth, reeds, tops."""
    pd, sd, nreed, rr, ytop, ycap = dims
    # The A1 end capital/plinth must finish on the new lobby boundary, never overhang into C1.
    x0 = max(x0, LOBBY_WEST_X + 0.5) if x0 < LOBBY_WEST_X + 0.5 and z < 0 else x0
    def zz(u0, u1):
        return sorted((z + s * u0, z + s * u1))
    za, zb = zz(-0.1, pd)
    g.box((x0 - 0.25, 24.0, za), (x1 + 0.25, 27.4, zb), m["marble"], e=0.07)
    za, zb = zz(-0.05, pd - 0.12)
    g.box((x0 - 0.12, 27.4, za), (x1 + 0.12, 27.62, zb), m["brass"], e=0.03)
    za, zb = zz(-0.05, sd)
    g.box((x0, 27.62, za), (x1, ycap, zb), m["lac"], e=0.05)
    w = x1 - x0
    pitch = w / nreed
    _reeds(g, m, [x0 + pitch * (k + 0.5) for k in range(nreed)], z + s * sd, s, 28.3, ycap - 0.5, rr)
    # stepped capital: three tiers with a brass band
    tiers = [(ycap, ycap + (ytop - ycap) * 0.3, 0.18, sd + 0.2, m["lac"]),
             (ycap + (ytop - ycap) * 0.3, ycap + (ytop - ycap) * 0.36, 0.28, sd + 0.3, m["brass"]),
             (ycap + (ytop - ycap) * 0.36, ycap + (ytop - ycap) * 0.66, 0.36, sd + 0.42, m["lac"]),
             (ycap + (ytop - ycap) * 0.66, ytop, 0.5, sd + 0.6, m["lac"])]
    for y0, y1, grow, dep, mat in tiers:
        za, zb = zz(-0.05, dep)
        g.box((x0 - grow, y0, za), (x1 + grow, y1, zb), mat, e=0.04)
    za, zb = zz(0, pd)
    g.cols.append((np.array([x0 - 0.25, 24.0, za]), np.array([x1 + 0.25, 27.62, zb])))
    za, zb = zz(0, sd + rr)
    g.cols.append((np.array([x0, 27.62, za]), np.array([x1, 34.0, zb])))
    EXTRA.append((np.array([x0 - 0.25, 24.0, min(za, zb) - 0.2]), np.array([x1 + 0.25, 28.3, max(za, zb) + 0.2])))


LOBBY_WEST_X = 22676.0                         # the lobby's west wall plane: block wall (v3) + the core's east face


def _lobby_west(i):
    """Walls whose east face is the lobby's west end (Z -21..99): the C1 block wall and the maintenance core. The
    facade neon pair runs along them so the north facade, the block wall, the core and the south facade read as one
    continuous wall (v3 points 12/13)."""
    return bool(VIS[i] and VIS_OK[i] and AXAL[i] and abs(HI[i, 0] - LOBBY_WEST_X) < 0.35 and HI[i, 0] - LO[i, 0] <= 4.5
                and LO[i, 2] > -22.5 and HI[i, 2] < 100.5 and LO[i, 1] < 50 and HI[i, 1] > 56)


def build_wall_neon(m):
    """The facade neon pair continues along the corridor walls and the concourse end walls, on slim black
    channels. Emissive only (plus flicker): the corridors' light comes from the ceiling fixtures."""
    g = Geo()
    sel = [i for i in range(N) if HI[i, 1] - LO[i, 1] > 20 and (
        re.search(r"^C\d/C\d_((West|East)Cladding|Separator)$", PATH[i])
        or (PATH[i] == "Shell/ShellSide" and zone_at(CEN[i, 0], np.clip(CEN[i, 2], -19, 99), "") == "Concourse")
        or _lobby_west(i))]
    for i in sel:
        a = 0 if HI[i, 0] - LO[i, 0] < HI[i, 2] - LO[i, 2] else 2
        h = 2 - a
        h0, h1 = LO[i, h], HI[i, h]
        if PATH[i] == "Shell/ShellSide":
            h0, h1 = max(h0, -20.0), min(h1, 100.0)
        for s, c in ((-1, LO[i, a]), (1, HI[i, a])):
            if _lobby_west(i) and s < 0:                     # the core / block wall: lobby face only
                continue
            if not free(a, s, c, h, h0, h1, 39, 41, 0.3, skip={i}):
                continue
            for col, yc in FAC_NEON:
                for x0, x1 in free(a, s, c, h, h0 + 0.5, h1 - 0.5, yc - 0.35, yc + 0.35, 0.3, skip={i}, minlen=3.0):
                    O, T, Nn, s0, s1, org = wall_frame(a, s, c, h, x0, x1)
                    lo, hi = np.zeros(3), np.zeros(3)
                    lo[a], hi[a] = sorted((c, c + s * 0.05))
                    lo[1], hi[1] = yc - 0.15, yc + 0.15
                    lo[h], hi[h] = x0, x1
                    g.box(lo, hi, m["black"], e=0.01)
                    neon_line(g, m, col, O + Nn * 0.12 + Y * yc, T, s0, s1, "wall%d_%s_%d" % (i, col, int(x0)),
                              r=0.06, org=org)
    emit("Neon_Walls", g)


def build_north_facades(m):
    """A1 / A3 north facades (A2's sits inside the CentralFork, unseen: its old trim is just removed)."""
    for aud in ("A1", "A3"):
        g = Geo()
        pil = sorted([i for i in range(N) if PATH[i] == "Concourse/%s_Pilaster" % aud], key=lambda i: LO[i, 0])
        cor = next(i for i in range(N) if PATH[i] == "Concourse/%s_ProjectingCornice" % aud)
        z = next(HI[i, 2] for i in range(N) if PATH[i] == "Concourse/%s_RearPlaster" % aud)
        s = 1
        for i in pil:
            _pilaster(g, m, LO[i, 0], HI[i, 0], z, s, (2.55, 1.75, 5, 0.34, 55.8, 51.8))
        for i0, i1 in zip(pil, pil[1:]):
            bx0, bx1 = HI[i0, 0], LO[i1, 0]
            acoustic_panels(g, m, z, s, bx0, bx1, 28.3, 55.8, FAC_JOINTS + _channels(), _holes(z, bx0, bx1))
            facade_neon(g, m, z, s, bx0 + 0.75, bx1 - 0.75, _keepouts(z, s, bx0, bx1, 28.5, 55.5), "n%d" % bx0)
        x0, x1 = LO[cor, 0], HI[cor, 0]
        g.wall_sweep(2, s, z, 0, x0, x1, PROF_NORTH_CORNICE, m["lac"])
        O, T, Nn, s0, s1, org = wall_frame(2, s, z, 0, x0 + 0.3, x1 - 0.3)
        neon_line(g, m, "mag", O + Nn * 1.6 + Y * 58.37, T, s0, s1, "ncove_" + aud, r=0.08, org=org,
                  light=COVE_LIGHT)
        STATS["cove_studs"] += round(x1 - x0)
        emit("Facade_North_" + aud, g)


def build_south_facade(m):
    g = Geo()
    z = 99.72
    s = -1
    pil = sorted([i for i in range(N) if PATH[i] == "Concourse/SouthPilaster"], key=lambda i: LO[i, 0])
    for i in pil:
        _pilaster(g, m, LO[i, 0], HI[i, 0], z, s, (0.95, 0.45, 5, 0.26, 55.5, 53.4))
    xs = [22624.0] + [v for i in pil for v in (LO[i, 0], HI[i, 0])] + [23376.0]
    for bx0, bx1 in zip(xs[0::2], xs[1::2]):                 # bays between pilasters and the wall ends
        for bx0, bx1 in zone_cut(2, s, z, 0, bx0, bx1, 24.0, 60.0):
            acoustic_panels(g, m, z, s, bx0, bx1, 28.3, 55.3, FAC_JOINTS + _channels(), _holes(z, bx0, bx1))
            facade_neon(g, m, z, s, bx0 + 0.75, bx1 - 0.75, _keepouts(z, s, bx0, bx1, 28.5, 55.2), "s%d" % bx0)
    for x0, x1 in zone_cut(2, s, z, 0, 22624.0, 23376.0, 24.0, 60.0):
        # frieze: glossy black band between brass beads, then the housed cove cornice
        g.wall_sweep(2, s, z, 0, x0, x1, [(0, 55.3), (0.06, 55.3), (0.06, 57.4), (0, 57.4)], m["lac"])
        for yb in (55.4, 57.4):
            g.wall_sweep(2, s, z, 0, x0, x1, [(0, yb - 0.12), (0.1, yb - 0.1), (0.14, yb - 0.04), (0.14, yb + 0.04),
                                              (0.1, yb + 0.1), (0, yb + 0.12)], m["brass"])
        O, T, Nn, s0, s1, org = wall_frame(2, s, z, 0, x0, x1)
        cove_run(g, m, O, T, Nn, s0, s1, 60.0, "scove_%d" % int(x0), org=org)
    emit("Facade_South", g)


def zone_cut(a, s, c, h, h0, h1, y0, y1, depth=0.6):
    """[h0, h1] minus the removed zones, on the strip in front of the wall plane (axis a, coordinate c, facing s)."""
    lo, hi = np.empty(3), np.empty(3)
    lo[a], hi[a] = (c, c + depth) if s > 0 else (c - depth, c)
    lo[1], hi[1], lo[h], hi[h] = y0, y1, h0, h1
    return _sub((h0, h1), [(zl[h], zh[h]) for zl, zh in REMOVED_ZONES
                           if np.all(zl < hi - 1e-3) and np.all(zh > lo + 1e-3)], 0.5)


def build_c1_block_facade(m):
    """Finish the new west closure with the neighbouring wallpaper panels and neon pair."""
    g = Geo()
    x, z0, z1 = LOBBY_WEST_X, -21.0, 0.0
    g.box((x, 24, z0), (x + 0.10, 28.3, z1), m["lac"])
    for y0, y1 in _sub((28.3, 85), FAC_JOINTS + _channels(), 0.5):
        for a, b in modules(z0, z1, 0):
            g.box((x, y0 + 0.06, a + 0.06), (x + PANEL_DEPTH, y1 - 0.06, b - 0.06), m["paper"], e=0.025)
    g.wall_sweep(0, 1, x, 2, z0, z1, [(u, y + 24) for u, y in PROF_BASE], m["lac"])
    emit("C1BlockFacade", g)
    # build_wall_neon supplies the lines on this exact face and on the adjoining core wall.
    o = area_light((x + 2, 51, -19), (x + 2, 51, -2), (210, 80, 230), 180,
                   "C1ClosureNeonWash", rng=24, bright=0.85, face=(-0.12, -1, 0))
    o["l4_kind"] = "neon_detail"           # keep the scoped practical in P2's final budget pass
    o.data.use_shadow = False


def build_gallery_north(m):
    """Reflect the 24 south curve modules into the north wall, returning into untouched booth frames.

    The three door/sign alcoves stay on the original wall plane. Their original leaves, frames and signage
    therefore keep their CFrames and their full clear openings; the new panels terminate beside each frame.
    """
    g, glow = Geo(), Geo()
    paper, dark, orange = m["paper"], m["lac"], slot("EMIT_ORANGE")
    heads = sorted([i for i in range(N) if re.match(r"HiddenService/A\d_GalleryBoothFrame_Head$", PATH[i])],
                   key=lambda i: LO[i, 0])
    alcoves = [(LO[i, 0] - 1.2, HI[i, 0] + 16.2) for i in heads]
    pieces = []
    for i in range(N):
        if not re.match(r"HiddenService/GalleryCurve(Panel|Cove|CoveJoint|Valence|Skirting|Backer)$", PATH[i]):
            continue
        center, ax, hs = CEN[i].copy(), ROT[i].T.copy(), HSZ[i].copy()
        center[2] = -19 - center[2]          # south inner wall Z=0 -> north inner wall Z=-19
        ax[:, 2] *= -1
        kind = NAME[i].removeprefix("GalleryCurve")
        # Cut along the actual local length axis, rather than rescaling a rotated world bounding box.
        ta = int(np.argmax(hs * (np.abs(ax[:, 0]) > 0.5)))
        if abs(ax[ta, 0]) < 0.5:             # the small cove-joint cubes
            if any(a < center[0] < b for a, b in alcoves):
                continue
            glow.box(hs, None, orange, axes=ax, center=center)
            continue
        ends = sorted((center[0] - ax[ta, 0] * hs[ta], center[0] + ax[ta, 0] * hs[ta]))
        for a, b in _sub(ends, alcoves, 0.08):
            tt = sorted(((a - center[0]) / ax[ta, 0], (b - center[0]) / ax[ta, 0]))
            ctr = center + ax[ta] * sum(tt) / 2
            half = hs.copy(); half[ta] = (tt[1] - tt[0]) / 2
            target = glow if kind in ("Cove", "CoveJoint") else g
            target.box(half, None, orange if kind in ("Cove", "CoveJoint") else paper if kind in ("Panel", "Valence") else dark,
                       axes=ax, center=ctr)
            extent = np.abs(ax).T @ half
            if kind in ("Panel", "Valence", "Backer"):
                g.cols.append((ctr - extent, ctr + extent))
            if kind == "Panel":
                pieces.append((a, b, center, ax[ta]))
    # Vertical panel returns and skirting are attached to the existing north wall beside the booth frames.
    for a, b in alcoves:
        for x in (a, b):
            edge = next((c + t * ((x - c[0]) / t[0]) for aa, bb, c, t in pieces
                         if abs(aa - x) < 0.02 or abs(bb - x) < 0.02), None)
            if edge is None:
                continue
            z = edge[2] + 0.5
            lo, hi = np.array([x - 0.12, 86, -19]), np.array([x + 0.12, 96.2, z])
            g.box(lo, hi, paper); g.cols.append((lo, hi))
            g.box((x - 0.14, 86, -19), (x + 0.14, 88, z + 0.08), dark)
        # The cove rises over the frame, follows the alcove wall, and returns onto the curve.
        pts = []
        for x in (a, b):
            edge = next((c + t * ((x - c[0]) / t[0]) for aa, bb, c, t in pieces
                         if abs(aa - x) < 0.02 or abs(bb - x) < 0.02), np.array([x, 0, -18.8]))
            pts.append((x, 96.6, edge[2] + 0.3))
        glow.tube([pts[0], (a, 97.8, -18.35), (b, 97.8, -18.35), pts[1]], 0.14, orange, seg=6)
    # The short end sections retain the same original north wall, with the new cove at curve height.
    for a, b in ((22624, 22700), (23352, 23376)):
        glow.box((a, 96.4, -18.5), (b, 96.8, -18.2), orange)
    for x in (22700, 23352):
        edge = next((c + t * ((x - c[0]) / t[0]) for aa, bb, c, t in pieces
                     if abs(aa - x) < 0.15 or abs(bb - x) < 0.15), None)
        if edge is not None:
            z = edge[2] + 0.5
            lo, hi = np.array([x - 0.12, 86, -19]), np.array([x + 0.12, 99, z])
            g.box(lo, hi, paper); g.cols.append((lo, hi))
            g.box((x - 0.14, 86, -19), (x + 0.14, 88, z + 0.08), dark)
            glow.box((x - 0.2, 96.4, -18.35), (x + 0.2, 96.8, z - 0.2), orange)
    # Decorative rotated panels use world-AABB collision boxes; keep them invisible.
    # The retained straight GalleryNorth wall behind the curve blocks the camera.
    emit("GalleryNorthCurve", g)
    emit("GalleryNorthCurveNeon", glow)
    for n, x in enumerate((22670, 22800, 22930, 23060, 23190, 23320)):
        o = area_light((x - 15, 95.8, -12.5), (x + 15, 95.8, -12.5), (255, 120, 40), 45,
                       "GalleryNorthOrange%d" % n, rng=18, bright=0.8, face=(0, -0.35, -1))
        o["l4_kind"] = "gallery_cove"
        o.data.use_shadow = False
    STATS["gallery_north_modules"] = 24


def build_main_entry_boards(m):
    """Owner point 2: the welded street entry is fully boarded on BOTH faces.

    Boards outside Z 239 are intentional: the owner explicitly requested an exterior skin too.
    Six overlapping sheets per face cover all the glass (X 22976..23024, Y 24..38), including the
    transom. Cracks and the pried brace are surface damage; the plywood behind remains opaque.
    """
    wood = slot("BOARD_WEATHERED")
    sheet_mats = [wood] * 3             # the weathered albedo already contains the variation
    sheets, braces, damage, litter = Geo(), Geo(), Geo(), Geo()
    x0, x1, y0, y1 = 22975.65, 23024.35, 24.0, 38.15
    sheet_w = (x1 - x0) / 6
    coverage = []

    def solid(g, lo, hi, mat, e=0.0):
        g.box(lo, hi, mat, e=e)
        g.cols.append((np.asarray(lo, float), np.asarray(hi, float)))

    def nail(g, x, y, z, s):
        # Low-poly, rust-dark nail heads with a narrow central metal highlight.
        g.tube([(x, y, z), (x, y, z + s * 0.035)], 0.07, m["steel"], seg=6)
        g.tube([(x, y, z + s * 0.035), (x, y, z + s * 0.044)], 0.028, m["chrome"], seg=4)

    for side, (s, za, zb) in enumerate(((-1, 237.30, 237.55), (1, 239.45, 239.70))):
        face_z = za if s < 0 else zb
        for k in range(6):
            xa = max(x0, x0 + sheet_w * k - 0.04)
            xb = min(x1, x0 + sheet_w * (k + 1) + 0.04)
            # No bevel on the sheet envelope: even a grazing ray cannot see between sheets.
            solid(sheets, (xa, y0, za), (xb, y1, zb), sheet_mats[(k + side) % 3])
            coverage.append((side, xa, xb, y0, y1))
            # Thin inset scores read as plywood joints without cutting the opaque sheets.
            if k:
                damage.box((xa + 0.03, y0 + 0.03, face_z + min(0, s * 0.006)),
                           (xa + 0.06, y1 - 0.03, face_z + max(0, s * 0.006)), m["black"])
            for xx in (xa + 0.40, xb - 0.40):
                for yy in (24.65, 37.45):
                    nail(damage, xx, yy, face_z, s)

        for row, yy in enumerate((26.3, 30.9, 35.4)):
            for k in range(3):
                xa, xb = x0 + (x1 - x0) * k / 3, x0 + (x1 - x0) * (k + 1) / 3
                znear, zfar = sorted((face_z + s * 0.018, face_z + s * 0.29))
                if row == 1 and k == 1 and side == 0:
                    # One end still nailed to the inner face; the freed end hangs down and out.
                    a = np.array([xa + 0.10, yy + 0.20, face_z + s * 0.18])
                    b = np.array([xb - 0.30, yy - 3.85, face_z + s * 0.92])
                    T = _n(b - a)
                    U = _n(Y - T * np.dot(Y, T))
                    Nn = _n(np.cross(T, U))
                    start = len(braces.v)
                    braces.box((np.linalg.norm(b - a) / 2, 0.52, 0.135), None, wood, e=0.025,
                               axes=(T, U, Nn), center=(a + b) / 2)
                    verts = np.array(braces.v[start:])
                    braces.cols.append((verts.min(axis=0), verts.max(axis=0)))
                    nail(damage, a[0] + 0.35, a[1] - 0.08, a[2] + s * 0.14, s)
                    # Empty screw hole where the far end was pried away.
                    damage.tube([(xb - 0.65, yy, face_z), (xb - 0.65, yy, face_z + s * 0.008)],
                                0.055, m["black"], seg=6)
                else:
                    solid(braces, (xa + 0.025, yy - 0.49, znear), (xb - 0.025, yy + 0.49, zfar),
                          sheet_mats[(row + k) % 3], e=0.025)
                    for xx in (xa + 0.65, xb - 0.65):
                        nail(damage, xx, yy, face_z + s * 0.30, s)

        # Split/cracked plywood: a branching dark fissure and lifted wooden splinter; no through-hole.
        zz = face_z + s * 0.013
        crack = [(22996.2, 37.5), (22996.8, 36.65), (22996.35, 35.9),
                 (22997.3, 34.7), (22997.0, 33.85), (22997.75, 32.9)]
        for (ax, ay), (bx, by) in zip(crack, crack[1:]):
            damage.tube([(ax, ay, zz), (bx, by, zz)], 0.024, m["black"], seg=3)
        damage.tube([(22997.3, 34.7, zz), (22998.45, 34.95, zz), (22999.1, 34.45, zz)],
                    0.018, m["black"], seg=3)
        # A wafer of veneer kicked off the crack, with actual depth and shadow.
        q = [(22996.4, 35.85, zz + s * 0.01), (22997.2, 34.72, zz + s * 0.10),
             (22997.7, 35.05, zz + s * 0.23)]
        damage.face(damage.vs(q), sheet_mats[0], AXV[2] * s)

    # Coverage self-check is part of the builder: damage must never expose glass between sheets.
    for side in (0, 1):
        spans = sorted((a, b) for si, a, b, low, high in coverage if si == side)
        assert spans[0][0] <= 22976 and spans[-1][1] >= 23024
        assert all(a <= last + 1e-6 for (_, last), (a, _) in zip(spans, spans[1:]))
    sheet_obj = emit("MainEntry_Boards_Sheets", sheets)
    sheet_obj["l4_occluder"] = True
    sheet_obj["l4_note"] = "Owner point 2: intentional exterior boards beyond Z 239; both faces fully opaque"
    emit("MainEntry_Boards_Braces", braces)
    emit("MainEntry_Boards_Damage", damage)

    # A small, grounded trail of thick triangular glass shards on the INSIDE floor: no colliders.
    rng = random.Random("L4_main_entry_breakin")
    glass = slot("GLASS_FROSTED", tint=(160, 184, 200))
    for k in range(18):
        cx = 22998.7 + rng.uniform(-3.7, 3.7)
        cz = 235.9 - rng.uniform(0.0, 3.3)
        ang, r = rng.random() * math.tau, rng.uniform(0.22, 0.64)
        tri = [(cx + r * math.cos(ang + t), cz + r * math.sin(ang + t)) for t in (0, 2.2, 4.15)]
        bot = litter.vs([(x, 24.025, z) for x, z in tri])
        top = litter.vs([(x, 24.047 + (0.015 if j == 0 else 0), z) for j, (x, z) in enumerate(tri)])
        litter.face(top, glass, Y)
        litter.face(bot, glass, -Y)
        for j in range(3):
            nj = (j + 1) % 3
            litter.face([bot[j], bot[nj], top[nj], top[j]], m["chrome"] if j == 0 else glass)
    # Dropped pry bar beside the glass; floor litter likewise has no collider.
    litter.tube([(23003.8, 24.09, 234.0), (23003.6, 24.09, 234.3), (23002.2, 24.09, 236.8),
                 (23002.3, 24.13, 237.05), (23002.55, 24.14, 237.03)], 0.065, m["steel"], seg=6)
    emit("MainEntry_BreakinLitter", litter)
    # A surviving cyan entrance edge is the practical light on the boarded face and broken glass.
    glow = Geo()
    for a, b in ((22976, 22988), (23000, 23012), (23012, 23024)):
        glow.box((a, 38.45, 237.15), (b, 38.85, 237.75), m["black"])
        glow.tube([(a + 0.1, 38.7, 237.2), (b - 0.1, 38.7, 237.2)], 0.06, m["cyan"], seg=6)
    emit("MainEntry_Boards_Neon", glow)
    o = area_light((22978, 38, 234.5), (23022, 38, 234.5), (120, 206, 255), 60,
                   "MainEntryBoardNeonWash", rng=22, bright=0.85, face=(0, -0.25, 1))
    o["l4_kind"] = "neon_detail"
    o.data.use_shadow = False
    STATS["main_entry_board_sheets"] = 12
    STATS["main_entry_braces"] = 18
    STATS["main_entry_glass_shards"] = 18


# ---- columns (A1 ConcourseColumn)
COL_R = 3.96                                   # shaft radius: inside the 8.0-dia layout collider


def build_columns(m):
    """Black marble drums with a brass foot, a magenta ring at the foot and in the ceiling collar, and four cyan
    tubes in vertical channels. Everything stays inside the layout's 8.0 / 8.6-dia colliders (kept)."""
    g = Geo()
    cols = sorted([i for i in range(N) if PATH[i] == "Concourse/ConcourseColumn"], key=lambda i: tuple(CEN[i]))
    R = COL_R
    for n, i in enumerate(cols):
        cx, cz = CEN[i, 0], CEN[i, 2]
        g.lathe(cx, cz, [(4.24, 24.0), (4.24, 26.4), (4.18, 26.56), (4.06, 26.62), (3.9, 26.62)], m["marble"], seg=40)
        g.lathe(cx, cz, [(4.06, 26.62), (4.16, 26.7), (4.2, 26.86), (4.16, 27.02), (4.06, 27.1), (3.9, 27.1)],
                m["brass"], seg=40)
        g.lathe(cx, cz, [(R, 27.1), (R, 60.0), (3.0, 60.0)], m["marble"], seg=40)
        neon_ring(g, m, "mag", cx, 27.3, cz, R + 0.07, 0.06, "colfoot%d" % n)
        # four cyan tubes in channels (two black fins each), on the diagonals
        for k in range(4):
            t = math.pi / 4 + k * math.pi / 2
            rad, tan = np.array([math.cos(t), 0, math.sin(t)]), np.array([-math.sin(t), 0, math.cos(t)])
            base = np.array([cx, 0, cz]) + rad * (R + 0.05)
            for sg in (-1, 1):
                ctr = base + rad * 0.03 + tan * sg * 0.17 + Y * 42.3
                g.box((0.035, 14.6, 0.09), None, m["lac"], e=0.012, axes=(tan, Y, rad), center=ctr)
            neon_line(g, m, "cyan", base + rad * 0.03, Y, 28.0, 56.7, "colv%d_%d" % (n, k), r=0.055, org=28.0)
        # ceiling collar: flared lacquer dish with a brass rim, magenta ring in the trough
        g.lathe(cx, cz, [(R, 57.4), (4.3, 57.5), (4.72, 57.86), (4.95, 58.3), (5.02, 58.82), (4.96, 58.9),
                         (4.88, 58.84), (4.88, 58.5), (R, 58.5)], m["lac"], seg=40)
        g.lathe(cx, cz, [(4.86, 58.82), (5.05, 58.8), (5.08, 58.9), (5.0, 58.97), (4.86, 58.95)], m["brass"], seg=40)
        if neon_ring(g, m, "mag", cx, 58.62, cz, 4.45, 0.08, "colring%d" % n, light=True) is True:
            ld = bpy.data.lights.new("L4D_colcove_%d" % n, "AREA")
            ld.shape, ld.size = "DISK", 9.4 * S
            ld.color = tuple(_lin(c / 255) for c in NEONRGB["mag"])
            ld.energy = 120
            _light_obj(ld, "colcove_%d" % n, (cx, 58.8, cz), face=(0, 1, 0), rng=14, bright=1.0, kind="cove")
    emit("Columns", g)
    STATS["columns"] = len(cols)


# ---- material slots on the build_base architecture (owner pick F: synthwave carpets, black acoustic walls)
# (l4_path regex, slot, height rule): "low" = Studio height <= 5 (base bands), "tall" = above that
RESTYLE = [
    (r"^Shell/LobbyCarpet$|^Shell/C\d_GroundJoint$|^C\d/C\d_(ReturnCarpet|StairA\d(East|West)_GroundCarpet)$"
     r"|^Concession/Concession_RedCarpet$|^Restrooms/RestroomVestibuleCarpet$", "CARPET_LOBBY", None),
    (r"^C\d/C\d_StairA\d(East|West)_(Tread\d+|Landing)$"
     r"|^A\d/A\d_(FrontTier\d+|RearTier\d+|CrossAisle|TopWalk|FrontApron|FrontAisleTread|RearAisleTread)$",
     "CARPET_AUD", None),
    (r"^Arcade/Arcade_Carpet$", "CARPET_ARCADE", None),
    (r"^Concourse/(A\d_RearPlaster|SouthFacadePlaster)$", "PLASTIC_BLACK", None),      # reveals behind panels
    (r"^C\d/C\d_(West|East)Cladding$", "WAINSCOT_LACQUER", "low"),
    (r"^C\d/C\d_(West|East)Cladding$|^C\d/C\d_Separator$|^CentralFork/(East|West|Tip)Plaster$|^Shell/ShellSide$",
     "WALLPAPER_MAIN", "tall"),
    (r"^CentralFork/TipPier(Base)?$|^C\d/C\d_StairA\d(East|West)_LandingGuard$", "WAINSCOT_LACQUER", None),
    (r"^Concourse/(A\d_RearWainscot|SouthFacadeWainscot)$|^C\d/C\d_SeparatorBase(East|West)$"
     r"|^CentralFork/\w*(Wainscot|Fascia|CoveBacker)$|^C\d/C\d_MouthFascia$", "WAINSCOT_LACQUER", None),
]


def restyle_architecture():
    rules = [(re.compile(rx), name, cond) for rx, name, cond in RESTYLE]
    n = 0
    for o in bpy.data.objects:
        p = o.get("l4_path")
        if not p or o.type != "MESH" or not o.material_slots or o.get("l4_pkg"):
            continue
        tall = o.dimensions.z / S > 5.0
        for rx, name, cond in rules:
            if rx.search(p) and (cond is None or (cond == "tall") == tall):
                o.material_slots[0].link = "OBJECT"
                o.material_slots[0].material = slot(name)
                n += 1
                break
    STATS["restyled"] = n
    return n


# ---- 0.3 defect 1: bevelled architecture boxes
# Gallery sealing walls meet edge-to-edge: chamfering both boxes opens a slit into the void.
_NOBEVEL = re.compile(r"BaseSlab|Roof|Ceiling|Carpet|Apron|Runner$|_Tile$|Checker_|ThresholdTile|GroundJoint"
                      r"|WallFinish|FlushSkin|Concrete$|GalleryFloor|Gallery(North|South|East|West)")


def _chamfer_box_mesh(name, sx, sy, sz, e):
    g = Geo()
    g.box((-sx / 2, -sy / 2, -sz / 2), (sx / 2, sy / 2, sz / 2), None, e=e)
    me = bpy.data.meshes.new(name)
    me.from_pydata(g.v, [], g.f)
    me.materials.append(None)
    me.polygons.foreach_set("use_smooth", g.fs)
    me.update()
    return me


def bevel_architecture():
    arch = bpy.data.collections.get("L4 Architecture")
    if not arch:
        return 0
    n = 0
    for o in list(arch.all_objects):
        if o.type != "MESH" or o.data.name != "L4U_Box":
            continue
        sx, sy, sz = (abs(v) for v in o.scale)
        mn = min(sx, sy, sz)
        if mn < 0.014 or _NOBEVEL.search(o.get("l4_path", "")):
            continue
        e = min(0.022 if mn > 0.12 else 0.012, 0.3 * mn)
        mat = o.material_slots[0].material if o.material_slots else None
        me = _chamfer_box_mesh("L4B_%s" % o.get("l4_src", o.name), sx, sy, sz, e)
        o.data = me
        o.scale = (1, 1, 1)
        if o.material_slots:
            o.material_slots[0].link = "OBJECT"
            o.material_slots[0].material = mat
        n += 1
    STATS["bevelled_boxes"] = n
    return n


# ------------------------------------------------------------------------------------------ entry
def build_detailing(bevel=True):
    import time
    t0 = time.time()
    STATS.clear()
    EXTRA.clear()
    clear_output()
    STATS["deleted_originals"] = delete_replaced()
    m = M()
    walls, floors, ceils = classify()
    faces = wall_faces(walls)
    STATS["wall_parts"], STATS["exposed_faces"] = len(walls), len(faces)
    runs = crown_runs(faces, ceils)
    steps = [                                # order matters: facades and casings join EXTRA before the trims
        lambda: build_north_facades(m), lambda: build_south_facade(m), lambda: build_casings(m),
        lambda: build_baseboards(m, faces, floors), lambda: build_bands(m), lambda: build_crowns(m, runs),
        lambda: build_concourse_coves(m, runs), lambda: build_wall_coves(m), lambda: build_nosings(m),
        lambda: build_handrails(m), lambda: build_columns(m), lambda: build_wall_neon(m),
        lambda: build_c1_block_facade(m), lambda: build_gallery_north(m), lambda: build_main_entry_boards(m), restyle_architecture]
    if bevel:
        steps.append(bevel_architecture)
    times = []
    for f in steps:
        t = time.time()
        f()
        times.append(round(time.time() - t, 1))
    STATS["seconds"] = round(time.time() - t0, 1)
    print("[arch_detail] step seconds", times)
    print("[arch_detail]", dict(STATS))
    return dict(STATS)


if __name__ == "__main__":                 # plain-Python self-check of the layout analysis and the neon states
    assert all(_NOBEVEL.search("HiddenService/Gallery" + side) for side in ("North", "South", "East", "West"))
    walls, floors, ceils = classify()
    faces = wall_faces(walls)
    assert 200 <= len(walls) <= 350 and len(faces) > 250, (len(walls), len(faces))
    assert all(VIS_OK[i] and NAME[i] not in CLOSED_OPENINGS for i in _markers())
    st = neon_states(4000, "selfcheck")
    assert st == neon_states(4000, "selfcheck")
    dead, fl = st.count("dead") / 4000, st.count("flicker") / 4000
    assert 0.1 < dead < 0.22 and 0.05 < fl < 0.1, (dead, fl)
    assert all(b - a >= 1.5 for a, b in modules(3.0, 60.0, OX)) and modules(0, 5, 0)[0] == (0, 5)
    print("arch_detail self-check ok: walls %d faces %d dead %.2f flicker %.2f" % (len(walls), len(faces), dead, fl))
