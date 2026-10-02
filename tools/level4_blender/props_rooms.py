# Level 4 facelift, package D2: Blender props for the restrooms, concession, service and arcade
# (r8.md A4-A7 "B" rows plus the section D decay dressing that belongs to those rooms).
# v3 (2026-10-01, owner points 5/7/8/9/11/14): the concession counter is 5 studs deep (Z 108-113 including its nosing) on carpet; the
# arcade is one hall between two solid wallpapered side walls (X 23172 / 23212, Z 102-238, the side spaces are
# closed voids) lined wall to wall with cabinets; the restrooms have white tile straight up to the wallpaper and
# wall-hung urinals with modelled flush valves; the service room is wallpapered; staff lockers stand at the east
# end of the projection gallery.
#
# Run order (headless or MCP):  exec(slots.py) ; exec(props_rooms.py) ; build_rooms_props()
# build_rooms_props() is idempotent. Every run it
#   1. deletes its own objects (collection "L4 Props Rooms", lights with l4_pkg == "D2"), the architecture objects
#      whose obj["l4_path"] matches REPLACES, and the props.py assets it supersedes (OLD_PROPS);
#   2. imports the Meshy meshes it needs when they are missing (import_meshy.py + meshy_specs.json);
#   3. rebuilds everything from l4_layout.json (seeded, so a re-run gives the same result).
#
# Export contract (read by export_l4.py; see slots.py for the shared conventions):
#   * instanced assets (obj["l4_prop"], obj["l4_model"], obj["l4_attrs"]): arcade cabinets (Meshy, attribute
#     ArcadeCabinet), toilets and urinals (Meshy), the popcorn machine (Meshy, Model "PopcornCase", Empty = true),
#     the soda fountain (Meshy), four carton variants, and the flicker lenses (l4_attrs OccasionalFlicker,
#     l4_prop FlickerLens, light parented to the lens);
#   * everything else is pooled plain meshes. World-space pools sit at the identity transform; pieces that need a
#     rotated collider (stall doors, the askew cabinet, rotated cartons, toppled things) are their own objects
#     with a matrix, so their l4_col boxes stay in the object's local metres;
#   * collision is always mesh["l4_col"] or obj["l4_col"] (boxes [cx,cy,cz,sx,sy,sz] in local metres), never
#     "bounds". obj["l4_col"] = "[]" switches a Meshy mesh's own boxes off for that placement.
#   * lights go to "L4 Fixture Lights" with l4_pkg "D2", l4_range (studs), l4_brightness, l4_shadows.
#   * CARRIER_SKIP: original Decal/SurfaceGui carriers the pipeline must NOT re-apply, because this package models
#     that content itself (arcade screens + marquees, restroom pictograms, the box-office header) or the host is
#     now askew/dead (menu box D). The other menu boards keep their labels: each menu box face sits within 1 stud
#     of the original board face, so the carrier ray lands on it.
#   * LIGHTS_SUPERSEDED: original lights (by parent path) whose fixture this package replaces with its own.
import bpy, bmesh, json, math, os, re, random
from contextlib import contextmanager
import numpy as np
from mathutils import Matrix, Vector

HERE = r"G:\Roblox\MongoTV\tools\level4_blender"
if "slot" not in globals():
    exec(open(os.path.join(HERE, "slots.py")).read())

S, OX, FLOOR = 0.28, 23000.0, 24.0
FONT = r"C:\Windows\Fonts\arialbd.ttf"
PKG, COLL, LCOLL = "D2", "L4 Props Rooms", "L4 Fixture Lights"
D2_LAYOUT = json.load(open(os.path.join(HERE, "l4_layout.json")))
D2_P = D2_LAYOUT["parts"]
D2_OTHER = D2_LAYOUT["other"]
MESHY_SPECS = os.path.join(HERE, "meshy_specs.json")
MESHY_USED = ("ArcadeUprightA", "ArcadeUprightB", "ArcadeRacing", "Pinball", "ToiletFlush", "Urinal",
              "PopcornMachine", "SodaFountain")
MESHY_OPTIONAL = ("LockerBank", "SupplyCabinet")    # a proxy stands in until the GLB has been imported

REPLACES = [
    # restrooms (the tile cap and the plaster above the tiles are rebuilt here: white tile up to the wallpaper)
    r"^Restrooms/(Men|Women)_Stall(Side|Header|Door|Hinge|Latch)$",
    r"^Restrooms/(Men|Women)_(MirrorFrame|MirrorGlass|TrashBin|Sign)$",
    r"^Restrooms/(Men|Women)_(Back)?(TealStripe|UpperPlaster)$",
    r"^Restrooms/(Men|Women)_(Sink|Toilet)/",
    # concession
    r"^Concession/Counter(Top|Plinth|PanelSeam|TopWornFrontLip|Trim)?$",
    r"^Concession/(CurvedMarqueeFascia|CurvedMarqueeTube|MarqueeGlow|MenuBoard|MenuBoardEdge)$",
    r"^Concession/Ticket\w+$",
    r"^Concession/(CandyCase\w*|CandyShelf|CandyPack|CandyWrapper)$",
    r"^Concession/Soda\w+$",
    r"^Concession/Register$",
    r"^Concession/PopcornCase/",
    # arcade
    r"^Arcade/Arcade(Left|Right)\d+_(Body|Controls|Marquee|Screen|Button)$",
    r"^Arcade/ArcadeStonePier$",
    r"^Arcade/Prize(Counter|Glass|Shelf|Box|SideDoor|DoorHandle)$",
    r"^Arcade/ArcadeStool(Seat|Stem)$",
    # service
    r"^Service/Service(North|South|East|West)WallFinish$",
    r"^Service/(StorageShelf|StorageUpright|ShelfLip)$",
    r"^Service/StockBox/",
    r"^Service/(CartonHandSlot|CartonPackingTape|FilmTin)$",
    r"^Service/(ServiceWorkbench\w+|WorkbenchLamp\w*|WorkbenchWallShelf)$",
    r"^Service/(North|South)Service(Panel\w*|Conduit)$",
    r"^Service/JanitorCart/",
    r"^Service/Mop(Head|Pole)$",
    r"^Service/ServiceCleaning(Top|Leg|Shelf)$",
    r"^Service/(North|South)ExtinguisherBracket$",
    r"^Service/(PopcornTub|PopcornRim|PopcornStripe|CleaningBottle|BottleCap|PosterRoll)$",
    r"^Service/(CagedServiceLamp|ServiceLampCage|ServiceLampHousing)$",
]
# path regex + original part centre (studs, None = every part with that path)
CARRIER_SKIP = [
    {"path": r"^Arcade/Arcade(Left|Right)\d+_Screen$", "at": None},     # Meshy cabinets carry their own screens
    {"path": r"^Arcade/Arcade(Left|Right)\d+_Marquee$", "at": None},
    {"path": r"^Restrooms/(Men|Women)_Sign$", "at": None},              # modelled round pictogram signs
    {"path": r"^Concession/MenuBoard$", "at": [22981.0, 42.15, 102.92]},  # box-office header: modelled TICKETS
    {"path": r"^Concession/MenuBoard$", "at": [23042.0, 42.15, 102.92]},  # menu box D hangs askew on one chain
    {"path": r"^Concession/PopcornCase/CaseSign$", "at": None},          # the Meshy machines carry POPCORN headers
]
LIGHTS_SUPERSEDED = [
    r"^Concession/MarqueeGlow/", r"^Concession/PopcornCase/CaseLamp/", r"^Concession/CandyCaseWarmStrip/",
    r"^Service/WorkbenchLamp/", r"^Service/CagedServiceLamp/",
]
OLD_PROPS = {"Toilet", "Sink", "StockBox", "ArcadeCabinet", "PopcornCase", "ArcadeStool", "JanitorCart"}

# mean albedo (sRGB 0-255) of each slot's PBR texture, so tints can be authored as target colours (see _t)
ALBEDO = {"STEEL_PAINTED": (75, 76, 76), "PORCELAIN": (239, 236, 229), "FORMICA_SPECKLE": (159, 144, 134),
          "CHROME_PITTED": (160, 160, 161), "ALU_NOSING": (134, 133, 132), "TILE_CREAM": (235, 225, 205),
          "TILE_TEAL": (46, 115, 113), "CONCRETE_SEALED": (131, 126, 121), "CMU_PAINT": (213, 199, 178),
          "SCREEN_PERF": (211, 198, 174), "LAMINATE_WOOD": (175, 128, 73), "PLASTIC_BLACK": (52, 51, 51),
          "RUBBER_BLACK": (44, 44, 44), "BRASS_AGED": (153, 117, 59), "MARBLE_BLACK": (37, 34, 30),
          "VINYL_TUFTED": (82, 41, 39), "CHECKER_VCT": (176, 136, 122), "ACT_2x4": (205, 202, 196),
          "WAINSCOT_LACQUER": (44, 43, 43), "MOSAIC_BLACK": (45, 41, 38), "VELOUR_SEAT": (111, 13, 16),
          "CARPET_STAFF": (150, 130, 93)}


def _lin(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _srgb(c):
    c = max(0.0, min(1.0, c))
    return int(round(255 * (12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055)))


def _t(name, target):
    """Slot material that renders ~target (sRGB) on a textured slot: slots.py multiplies the albedo map by
    tint/0.75 (linear), so the tint is solved from the map's mean albedo. Untextured slots take target as is."""
    alb = ALBEDO.get(name)
    if not alb:
        return slot(name, tuple(target))
    tint = tuple(_srgb(min(1.0, _lin(t) / max(_lin(a), 1e-4)) * 0.75) for t, a in zip(target, alb))
    return slot(name, tint)


# ---------------------------------------------------------------- coordinates
def _rb(v):                     # Roblox studs point -> Blender metres
    return Vector(((v[0] - OX) * S, -v[2] * S, v[1] * S))


def _B(x, y, z):                # Roblox studs point -> Blender axes, still studs (world-space builders)
    return Vector((x - OX, -z, y))


def _parts(rx):
    r = re.compile(rx)
    return [(i, p) for i, p in enumerate(D2_P) if r.search(p["p"])]


def _R(p):
    return np.array(p["cf"][3:], dtype=float).reshape(3, 3)


def _aabb(p):
    c = np.array(p["cf"][:3], dtype=float)
    e = np.abs(_R(p)) @ np.array(p["s"], dtype=float) / 2
    return c - e, c + e


def _yaw(front):                # rotation about Z turning canonical -Y onto `front` (Blender direction)
    f = Vector((front[0], front[1], 0))
    if f.length < 1e-6:
        return Matrix.Identity(3)
    f.normalize()
    return Matrix.Rotation(math.atan2(f.x, -f.y), 3, "Z")


# Roblox horizontal facing -> Blender direction
FACE = {"+X": (1, 0), "-X": (-1, 0), "+Z": (0, -1), "-Z": (0, 1)}


def _M(pos_rb, facing="-Z", ang=0.0, scale=1.0):
    """Placement matrix (Blender metres): origin at the Roblox studs point, canonical -Y turned to `facing`
    (a FACE key or a Blender direction), plus an extra yaw in degrees."""
    f = FACE.get(facing, facing) if isinstance(facing, str) else facing
    R = _yaw(f) @ Matrix.Rotation(math.radians(ang), 3, "Z")
    return Matrix.Translation(_rb(pos_rb)) @ R.to_4x4() @ Matrix.Diagonal((scale, scale, scale, 1))


# ---------------------------------------------------------------- mesh builder (studs, Blender axes)
class RMesh:
    """bmesh builder. Geometry is authored in studs (Blender axes); finish() scales to metres. self.M is the
    current transform (`with mb.at(M):`). Colliders: col() in the builder's own frame (not self.M)."""

    def __init__(self, name):
        self.name, self.bm, self.mats = name, bmesh.new(), []
        self.M = Matrix.Identity(4)
        self.cols = []

    @contextmanager
    def at(self, M):
        prev = self.M
        self.M = prev @ (M.to_4x4() if len(M) == 3 else M)
        try:
            yield
        finally:
            self.M = prev

    def _mi(self, mat):
        if mat not in self.mats:
            self.mats.append(mat)
        return self.mats.index(mat)

    def _done(self, verts, mat, smooth, faces=None):
        if self.M != Matrix.Identity(4):
            bmesh.ops.transform(self.bm, matrix=self.M, verts=verts)
        mi = self._mi(mat)
        for f in faces if faces is not None else {f for v in verts for f in v.link_faces}:
            f.material_index = mi
            f.smooth = smooth
        return verts

    def col(self, c, s):
        self.cols.append([float(v) for v in (*c, *s)])

    def box(self, c, s, mat, bevel=0.0, seg=1):
        vs = bmesh.ops.create_cube(self.bm, size=1.0)["verts"]
        bmesh.ops.scale(self.bm, vec=Vector(s), verts=vs)
        bmesh.ops.translate(self.bm, vec=Vector(c), verts=vs)
        faces = {f for v in vs for f in v.link_faces}
        if bevel > 0:
            mi = self._mi(mat)                  # set before the bevel: the inset faces it rebuilds inherit it
            for f in faces:
                f.material_index = mi
            edges = list({e for v in vs for e in v.link_edges})
            r = bmesh.ops.bevel(self.bm, geom=vs + edges, offset=min(bevel, min(s) * 0.45), segments=seg,
                                affect="EDGES", profile=0.5, clamp_overlap=True)
            faces = {f for f in faces if f.is_valid} | set(r["faces"])
            vs = list({v for f in faces for v in f.verts})
        return self._done(vs, mat, bevel > 0, faces)

    def cyl(self, c, r, h, mat, axis="Z", seg=16, r2=None, caps=True):
        m = {"X": Matrix.Rotation(math.pi / 2, 4, "Y"), "Y": Matrix.Rotation(math.pi / 2, 4, "X")}.get(axis, Matrix.Identity(4))
        vs = bmesh.ops.create_cone(self.bm, cap_ends=caps, segments=seg, radius1=r, radius2=r if r2 is None else r2,
                                   depth=h, matrix=Matrix.Translation(Vector(c)) @ m)["verts"]
        self._done(vs, mat, True)
        for f in {f for v in vs for f in v.link_faces}:
            if len(f.verts) > 4:
                f.smooth = False
        return vs

    def sphere(self, c, r, mat, seg=8, rings=4):
        vs = bmesh.ops.create_uvsphere(self.bm, u_segments=seg, v_segments=rings, radius=r,
                                       matrix=Matrix.Translation(Vector(c)))["verts"]
        return self._done(vs, mat, True)

    def lathe(self, prof, mat, seg=16, c=(0, 0, 0), smooth=True, sx=1.0, sy=1.0):
        """Revolve [(r, z), ...] (bottom to top) around Z; sx/sy squash it into an ellipse. r == 0 makes a pole."""
        rings = []
        for r, z in prof:
            if r < 1e-6:
                rings.append([self.bm.verts.new((c[0], c[1], c[2] + z))])
            else:
                rings.append([self.bm.verts.new((c[0] + sx * r * math.cos(2 * math.pi * k / seg),
                                                 c[1] + sy * r * math.sin(2 * math.pi * k / seg), c[2] + z))
                              for k in range(seg)])
        F = self.bm.faces.new
        for a, b in zip(rings, rings[1:]):
            for k in range(seg):
                j = (k + 1) % seg
                if len(a) == 1 and len(b) == 1:
                    continue
                if len(a) == 1:
                    F((a[0], b[j], b[k]))
                elif len(b) == 1:
                    F((a[k], a[j], b[0]))
                else:
                    F((a[k], a[j], b[j], b[k]))
        return self._done([v for r in rings for v in r], mat, smooth)

    def tube(self, pts, r, mat, seg=8, caps=True):
        """Circle swept along a polyline (parallel-transport frames). Fillet the path first for bends."""
        pts = [Vector(p) for p in pts]
        n = len(pts)
        T = [(pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized() for i in range(n)]
        ref = Vector((0, 0, 1)) if abs(T[0].z) < 0.9 else Vector((1, 0, 0))
        N = (ref - ref.dot(T[0]) * T[0]).normalized()
        rings = []
        for i in range(n):
            if i:
                ax = T[i - 1].cross(T[i])
                if ax.length > 1e-7:
                    N = Matrix.Rotation(T[i - 1].angle(T[i]), 3, ax.normalized()) @ N
            Bv = T[i].cross(N)
            rings.append([self.bm.verts.new(pts[i] + r * (math.cos(2 * math.pi * k / seg) * N + math.sin(2 * math.pi * k / seg) * Bv))
                          for k in range(seg)])
        F = self.bm.faces.new
        for a, b in zip(rings, rings[1:]):
            for k in range(seg):
                j = (k + 1) % seg
                F((a[k], a[j], b[j], b[k]))
        if caps:
            F(list(reversed(rings[0])))
            F(rings[-1])
        return self._done([v for rr in rings for v in rr], mat, True)

    def grid(self, nu, nv, fn, mat, smooth=True):
        """Surface from fn(u, v) -> (x, y, z), u,v in [0, 1]. Faces point along (dP/du x dP/dv)."""
        V = [[self.bm.verts.new(fn(i / nu, j / nv)) for j in range(nv + 1)] for i in range(nu + 1)]
        F = self.bm.faces.new
        for i in range(nu):
            for j in range(nv):
                F((V[i][j], V[i + 1][j], V[i + 1][j + 1], V[i][j + 1]))
        return self._done([v for col in V for v in col], mat, smooth)

    def poly(self, pts, mat, face=None):
        pts = [Vector(p) for p in pts]
        if face is not None:
            n = Vector((0, 0, 0))
            for a, b in zip(pts, pts[1:] + pts[:1]):
                n += a.cross(b)
            if n.dot(Vector(face)) < 0:
                pts.reverse()
        vs = [self.bm.verts.new(p) for p in pts]
        self.bm.faces.new(vs)
        return self._done(vs, mat, False)

    def prism(self, pts, z0, z1, mat, smooth=False):
        """Extrude a CCW polygon (xy) from z0 to z1."""
        lo = [self.bm.verts.new((x, y, z0)) for x, y in pts]
        hi = [self.bm.verts.new((x, y, z1)) for x, y in pts]
        F = self.bm.faces.new
        n = len(pts)
        for k in range(n):
            j = (k + 1) % n
            F((lo[k], lo[j], hi[j], hi[k]))
        F(list(reversed(lo)))
        F(hi)
        return self._done(lo + hi, mat, smooth)

    def octa(self, c, s, rot, mat):
        """8-triangle lump (popcorn, crumbs, gumballs far away)."""
        ax = [rot @ Vector((s[0], 0, 0)), rot @ Vector((0, s[1], 0)), rot @ Vector((0, 0, s[2]))]
        c = Vector(c)
        v = [self.bm.verts.new(c + a * sg) for a in ax for sg in (1, -1)]
        F = self.bm.faces.new
        for a, b in ((0, 2), (2, 1), (1, 3), (3, 0)):
            F((v[a], v[b], v[4]))
            F((v[b], v[a], v[5]))
        return self._done(v, mat, False)

    def add_geo(self, verts, faces, mat, M=None):
        M = M or Matrix.Identity(4)
        vs = [self.bm.verts.new(M @ Vector(v)) for v in verts]
        for f in faces:
            try:
                self.bm.faces.new([vs[i] for i in f])
            except ValueError:
                pass
        return self._done(vs, mat, False)

    # -- Roblox-frame shortcuts for world-space pools (lo/hi = Roblox studs corners)
    def rbox(self, lo, hi, mat, bevel=0.0, seg=1):
        c = _B(*((a + b) / 2 for a, b in zip(lo, hi)))
        return self.box(c, (abs(hi[0] - lo[0]), abs(hi[2] - lo[2]), abs(hi[1] - lo[1])), mat, bevel, seg)

    def rcol(self, lo, hi):
        c = _B(*((a + b) / 2 for a, b in zip(lo, hi)))
        self.col(c, (abs(hi[0] - lo[0]), abs(hi[2] - lo[2]), abs(hi[1] - lo[1])))

    def empty(self):
        return not self.bm.verts

    def finish(self, wn=True):
        mname = "L4D2_" + self.name
        bmesh.ops.scale(self.bm, vec=(S, S, S), verts=self.bm.verts)
        old = bpy.data.meshes.get(mname)
        if old:
            bpy.data.meshes.remove(old)
        me = bpy.data.meshes.new(mname)
        self.bm.to_mesh(me)
        self.bm.free()
        for m in self.mats:
            me.materials.append(m)
        if wn and len(me.polygons):
            me = _weighted(me, mname)
        me["l4_asset"] = self.name
        if self.cols:
            me["l4_col"] = json.dumps([[round(v * S, 4) for v in b] for b in self.cols])
        return me


def _weighted(me, name):
    """Face-area weighted normals (flat faces stay flat, bevels and round parts smooth)."""
    me.set_sharp_from_angle(angle=math.radians(40))
    ob = bpy.data.objects.new("_d2_wn", me)
    bpy.context.scene.collection.objects.link(ob)
    md = ob.modifiers.new("wn", "WEIGHTED_NORMAL")
    md.mode, md.weight, md.keep_sharp = "FACE_AREA", 50, True
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    out = bpy.data.meshes.new_from_object(ob.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
    bpy.data.objects.remove(ob)
    bpy.data.meshes.remove(me)
    out.name = name
    return out


def _fillet(pts, rad, nseg=4):
    """Round the interior corners of a polyline with quadratic Beziers."""
    pts = [Vector(p) for p in pts]
    out = [pts[0]]
    for i in range(1, len(pts) - 1):
        P, A, Bp = pts[i], pts[i - 1], pts[i + 1]
        u, w = (A - P), (Bp - P)
        d = min(rad, 0.45 * u.length, 0.45 * w.length)
        p0, p2 = P + u.normalized() * d, P + w.normalized() * d
        for k in range(nseg + 1):
            t = k / nseg
            out.append((1 - t) ** 2 * p0 + 2 * (1 - t) * t * P + t * t * p2)
    out.append(pts[-1])
    return out


def _text_geo(s, size, extrude=0.05):
    """Text -> (verts, faces) laid in the XZ plane facing -Y, centred on the origin (studs)."""
    font = bpy.data.fonts.load(FONT, check_existing=True) if os.path.exists(FONT) else None
    cu = bpy.data.curves.new("_d2_txt", "FONT")
    cu.body = s
    if font:
        cu.font = font
    cu.size, cu.extrude, cu.resolution_u = size, extrude, 2
    cu.align_x, cu.align_y = "CENTER", "CENTER"
    ob = bpy.data.objects.new("_d2_txt", cu)
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    bpy.data.objects.remove(ob)
    bpy.data.curves.remove(cu)
    rx = Matrix.Rotation(math.pi / 2, 3, "X")
    co = [rx @ v.co for v in me.vertices]
    polys = [tuple(p.vertices) for p in me.polygons]
    bpy.data.meshes.remove(me)
    if co:
        zc = (max(v.z for v in co) + min(v.z for v in co)) / 2
        co = [Vector((v.x, v.y, v.z - zc)) for v in co]
    return co, polys


# ---------------------------------------------------------------- scene helpers
def _coll(name):
    c = bpy.data.collections.get(name)
    if not c:
        c = bpy.data.collections.new(name)
        root = bpy.data.collections.get("L4 Cinema")
        (root.children if root else bpy.context.scene.collection.children).link(c)
    return c


def _bake(me, M):
    """Bake a quarter-turn placement into a fresh pooled mesh (world-space box UVs then match the preview) and move
    its l4_col boxes with it. -> True when baked; other rotations keep their matrix."""
    R = np.array(M.to_3x3())
    if me.users or np.abs(np.abs(R) - np.round(np.abs(R))).max() > 1e-4 or abs(abs(R[2, 2]) - 1) > 1e-4:
        return False
    me.transform(M)
    if me.get("l4_col"):
        out = []
        for c in json.loads(me["l4_col"]):
            ctr = M @ Vector(c[:3])
            sz = np.abs(R) @ np.array(c[3:6])
            out.append([round(v, 4) for v in (*ctr, *sz)])
        me["l4_col"] = json.dumps(out)
    return True


def _obj(me, name, M, **props):
    nobake = props.pop("_nobake", False)
    if not nobake and not props.get("l4_prop") and M != Matrix.Identity(4) and _bake(me, M):
        M = Matrix.Identity(4)
    o = bpy.data.objects.new(name, me)
    o.matrix_world = M
    _coll(COLL).objects.link(o)
    o["l4_pkg"] = PKG
    for k, v in props.items():
        o[k] = v
    return o


def _place(me, name, M, model=None, attrs=None, **props):
    """Instanced asset placement (one Roblox Model each)."""
    if attrs:
        props["l4_attrs"] = json.dumps(attrs)
    return _obj(me, name, M, l4_prop=me["l4_asset"], l4_model=model or name, **props)


def _pool(mb, name, M=None, wn=True, **props):
    """Finish a builder and link it as a pooled plain mesh (merged per material by the exporter)."""
    if mb.empty():
        mb.bm.free()
        return None
    return _obj(mb.finish(wn), name, M or Matrix.Identity(4), l4_role="fixture", **props)


def _light(name, pos, rgb, rng, bright, kind="POINT", shadows=False, host=None, spot=None, energy_k=1.0,
           direction=None, size=(1.0, 1.0)):
    """pos = Roblox studs. SPOT lights point down (-Z) unless the object is rotated after."""
    ld = bpy.data.lights.new("L4D2_" + name, kind)
    ld.color = tuple(_lin(c) for c in rgb)
    rm = rng * S
    ld.energy = 2500.0 * max(0.2, bright) * (rm / 4.0) ** 2 * energy_k
    ld.shadow_soft_size = 0.15
    ld.use_custom_distance = True
    ld.cutoff_distance = rm * 1.3
    ld.use_shadow = bool(shadows)
    if kind == "SPOT":
        ld.spot_size = math.radians(spot or 70)
        ld.spot_blend = 0.5
    elif kind == "AREA":
        ld.shape, ld.size, ld.size_y = "RECTANGLE", size[0] * S, size[1] * S
    o = bpy.data.objects.new("L4D2_" + name, ld)
    o.location = _rb(pos)
    if direction is not None:
        o.rotation_euler = Vector(direction).to_track_quat("-Z", "Y").to_euler()
    _coll(LCOLL).objects.link(o)
    o["l4_pkg"], o["l4_range"], o["l4_brightness"], o["l4_shadows"] = PKG, float(rng), float(bright), bool(shadows)
    o["l4_color"] = list(rgb)
    if spot:
        o["l4_angle"] = float(spot)
    if host is not None:
        o.parent = host
        o.matrix_parent_inverse = host.matrix_world.inverted()
        o["l4_host"] = host.name
    return o


def _flicker(mb, name, rgb, rng, bright, light_pos):
    """A flicker fixture: the lens is its own instanced object (OccasionalFlicker) with its light parented."""
    me = mb.finish(False)
    o = _place(me, name, Matrix.Identity(4), model=name, attrs={"OccasionalFlicker": True})
    o["l4_prop"] = "FlickerLens"
    _light(name, light_pos, rgb, rng, bright, host=o)
    return o


def _clear():
    rx = [re.compile(r) for r in REPLACES]
    gone = 0
    for o in list(bpy.data.objects):
        mine = o.get("l4_pkg") == PKG
        arch = o.get("l4_path") and not o.get("l4_prop") and any(r.search(o["l4_path"]) for r in rx)
        old = o.get("l4_prop") in OLD_PROPS and not o.get("l4_pkg")
        if mine or arch or old:
            bpy.data.objects.remove(o, do_unlink=True)
            gone += 1
    for me in list(bpy.data.meshes):
        if (me.name.startswith("L4D2_") and me.users == int(me.use_fake_user)) or (me.users == 0 and me.get("l4_asset") in OLD_PROPS):
            bpy.data.meshes.remove(me)
    for ld in list(bpy.data.lights):
        if ld.users == 0 and ld.name.startswith("L4D2_"):
            bpy.data.lights.remove(ld)
    return gone


def _meshy():
    """-> {asset: mesh}; imports the missing Meshy meshes whose GLB exists (fake users keep them in the blend).
    MESHY_OPTIONAL assets without a GLB get a proxy box (L4D2_Proxy_<asset>, rebuilt every run)."""
    used = MESHY_USED + MESHY_OPTIONAL
    need = [s for s in json.load(open(MESHY_SPECS)) if s["asset"] in used and not bpy.data.meshes.get("L4A_" + s["asset"])
            and os.path.isfile(s["glb"])]
    if need:
        exec(open(os.path.join(HERE, "import_meshy.py")).read(), {"SPEC": need, "__name__": "d2_meshy"})
    out = {}
    for a in used:
        me = bpy.data.meshes.get("L4A_" + a)
        if me is None and a in MESHY_OPTIONAL:
            me = _proxy_cabinet(a)
        assert me is not None, "Meshy mesh L4A_%s missing" % a
        out[a] = me
    return out


def _proxy_cabinet(asset):
    """Stand-in for a Meshy locker/cabinet (0.9 x 0.45 x 1.8 m, front -Y, origin bottom centre)."""
    a = RMesh("Proxy_" + asset)
    w, d, h = 0.9 / S, 0.45 / S, 1.8 / S
    body = _t("STEEL_PAINTED", (70, 40, 66) if asset == "LockerBank" else (84, 88, 90))
    a.box((0, 0, h / 2 + 0.2), (w, d, h - 0.4), body, 0.04)
    a.box((0, 0, 0.1), (w - 0.1, d - 0.1, 0.2), slot("PLASTIC_BLACK"))
    n = 3 if asset == "LockerBank" else 2
    for k in range(1, n):
        a.box((-w / 2 + w * k / n, -d / 2 - 0.01, h / 2 + 0.2), (0.04, 0.02, h - 0.6), slot("PLASTIC_BLACK"))
    for k in range(n):
        a.box((-w / 2 + w * (k + 0.5) / n + 0.25, -d / 2 - 0.04, h * 0.55), (0.08, 0.06, 0.5), slot("CHROME_PITTED"))
    a.col((0, 0, h / 2), (w, d, h))
    me = a.finish(False)
    me["l4_asset"] = asset + "Proxy"
    return me


def _mdims(me):
    co = np.array([v.co[:] for v in me.vertices])
    return co.min(0) / S, co.max(0) / S          # studs


# ---------------------------------------------------------------- materials
# Saturated enamel and rough paper need a neutral base: dark steel/Formica maps clip the
# orange/blue tint and make cardboard look like particleboard. These slots belong only to D2.
SLOTS.update({
    "D2_PAINT": (None, 1.0, (180, 180, 180), 0.6, 0.1, "Metal", "metal"),
    "D2_KRAFT": (None, 1.0, (150, 118, 84), 0.95, 0, "SmoothPlastic", "paper"),
})


def _mats():
    return dict(
        teal=_t("STEEL_PAINTED", (54, 82, 78)), teal_dk=_t("STEEL_PAINTED", (40, 52, 50)),
        rust=_t("STEEL_PAINTED", (84, 52, 34)), chrome=slot("CHROME_PITTED"), alu=slot("ALU_NOSING"),
        steel=slot("STEEL_PAINTED"), steel_lt=_t("STEEL_PAINTED", (120, 122, 124)),
        porcelain=slot("PORCELAIN"), vanity=_t("FORMICA_SPECKLE", (196, 184, 164)),
        vanity_base=_t("PORCELAIN", (150, 142, 128)), mirror=slot("MIRROR", (78, 86, 90)), desilver=_t("STEEL_PAINTED", (66, 58, 44)),
        tile_teal=slot("TILE_TEAL"), mortar=_t("CONCRETE_SEALED", (92, 84, 72)), black=slot("PLASTIC_BLACK"),
        rubber=slot("RUBBER_BLACK"), glass=slot("GLASS_CLEAR"), frost=slot("GLASS_FROSTED"),
        water=slot("GLASS_CLEAR", (18, 20, 22)), paper=_t("PORCELAIN", (226, 222, 208)),
        magenta=slot("EMIT_MAGENTA"), cyan=slot("EMIT_CYAN"), warm=slot("EMIT_WARM"),
        board=slot("EMIT_WARM", (255, 240, 214)), amber=slot("EMIT_AMBER"),
        formica=slot("FORMICA_SPECKLE"),
        marble=slot("MARBLE_BLACK"), brass=slot("BRASS_AGED"), burgundy=_t("STEEL_PAINTED", (78, 18, 28)),
        lacquer=slot("WAINSCOT_LACQUER"), plum=_t("PORCELAIN", (46, 16, 44)), plum_dk=_t("STEEL_PAINTED", (26, 12, 26)),
        sign_m=_t("PORCELAIN", (24, 84, 104)), sign_w=_t("PORCELAIN", (128, 30, 88)),
        dead_panel=_t("SCREEN_PERF", (92, 88, 80)), soot=_t("CONCRETE_SEALED", (30, 26, 22)),
        neon_dead=_t("PORCELAIN", (112, 96, 108)), notice=_t("PORCELAIN", (214, 200, 160)),
        red_dk=_t("PORCELAIN", (120, 20, 26)), popcorn=_t("PORCELAIN", (236, 206, 140)),
        cup=_t("PORCELAIN", (230, 226, 216)), cup_rim=_t("PORCELAIN", (170, 28, 40)),
        sticky=slot("GLASS_CLEAR", (40, 18, 10)), glass_dk=slot("GLASS_CLEAR", (40, 44, 48)),
        warm_dim=slot("EMIT_WARM", (200, 150, 100)), candy0=_t("PORCELAIN", (150, 64, 60)),
        candy1=_t("PORCELAIN", (176, 146, 76)), candy2=_t("PORCELAIN", (96, 84, 128)),
        register=_t("PORCELAIN", (178, 170, 150)), key=_t("PORCELAIN", (60, 58, 56)),
        key_red=_t("PORCELAIN", (170, 40, 40)), vfd=slot("EMIT_COOL", (80, 255, 170)),
        butter=_t("PORCELAIN", (226, 184, 70)), bucket=_t("PORCELAIN", (232, 228, 218)),
        kraft=_t("D2_KRAFT", (150, 118, 84)),
        mirror_dk=slot("MIRROR", (40, 44, 50)), crt_dead=_t("PLASTIC_BLACK", (26, 30, 29)),
        crack=_t("PORCELAIN", (200, 205, 210)), vein=_t("BRASS_AGED", (170, 130, 60)),
        plush0=_t("CARPET_STAFF", (120, 78, 46)), plush1=_t("CARPET_STAFF", (150, 128, 90)),
        plush2=_t("CARPET_STAFF", (96, 104, 93)), plush3=_t("CARPET_STAFF", (150, 90, 93)),
        plush_muzzle=_t("CARPET_STAFF", (150, 130, 93)), ball0=_t("PORCELAIN", (200, 40, 40)),
        ball1=_t("PORCELAIN", (40, 90, 200)), ball2=_t("PORCELAIN", (230, 190, 40)),
        wood=_t("LAMINATE_WOOD", (110, 70, 40)), door_red=_t("STEEL_PAINTED", (74, 20, 24)),
        glass_wire=slot("GLASS_FROSTED", (150, 160, 160)), red_enamel=_t("PORCELAIN", (170, 24, 30)),
        vinyl=slot("VINYL_TUFTED"), ticket0=_t("PORCELAIN", (176, 104, 78)), ticket1=_t("PORCELAIN", (184, 160, 86)),
        **{"crt%d" % i: slot("EMIT_COOL", rgb) for i, rgb in enumerate(CRT_FACE)},
        rack_blue=_t("D2_PAINT", (28, 64, 140)), rack_orange=_t("D2_PAINT", (220, 96, 18)),
        deck=_t("CHROME_PITTED", (120, 122, 124)), kraft_wet=_t("D2_KRAFT", (110, 84, 58)),
        kraft_dk=_t("D2_KRAFT", (80, 60, 42)), tape=_t("D2_KRAFT", (186, 150, 96)),
        print_red=_t("PORCELAIN", (168, 30, 36)), print_blue=_t("PORCELAIN", (36, 70, 150)),
        print_orange=_t("PORCELAIN", (220, 120, 30)), film_tin=_t("CHROME_PITTED", (130, 128, 122)),
        label0=_t("PORCELAIN", (220, 210, 170)), label1=_t("PORCELAIN", (200, 60, 50)),
        film=_t("PLASTIC_BLACK", (40, 30, 24)), bench_top=_t("STEEL_PAINTED", (110, 115, 112)),
        steel_grey=_t("STEEL_PAINTED", (70, 74, 76)), toolbox=_t("PORCELAIN", (170, 28, 30)),
        pegboard=_t("SCREEN_PERF", (150, 120, 80)), jug=_t("PORCELAIN", (210, 200, 160)),
        vice=_t("STEEL_PAINTED", (40, 70, 60)), lamp_green=_t("PORCELAIN", (30, 80, 50)),
        panel_grey=_t("D2_PAINT", (118, 122, 122)), placard=_t("PORCELAIN", (230, 190, 30)),
        emt=slot("CHROME_PITTED"), bulk_body=_t("STEEL_PAINTED", (60, 62, 60)),
        sickly=slot("EMIT_COOL", (211, 235, 162)),
        cart_yellow=_t("PORCELAIN", (220, 170, 20)), bag=_t("PLASTIC_BLACK", (50, 50, 52)),
        mop=_t("CARPET_STAFF", (140, 130, 110)),
        wallpaper=slot("WALLPAPER_MAIN"), damp=slot("WALLPAPER_MAIN", (16, 11, 12)),
    )


# ================================================================ restrooms (r8 A6)
ROOMS = [
    dict(name="Men", x0=23270.32, x1=23301.68, door=(23276.0, 23286.0), sink_x=23270.32, sink_face="+X",
         panels=(23273.25, 23284.25, 23288.25, 23299.25), bin=(23298.0, 23300.5, 130.0, 132.5), bin_wall=23301.68),
    dict(name="Women", x0=23311.32, x1=23342.68, door=(23326.0, 23336.0), sink_x=23342.68, sink_face="-X",
         panels=(23314.25, 23325.25, 23329.25, 23340.25), bin=(23312.0, 23314.5, 130.0, 132.5), bin_wall=23311.32),
]
RZ0, RZ1 = 126.2, 165.8          # restroom wainscot faces (front wall, back wall)
STALL_Z = 151.0                  # stall front line
FIX_SCALE = 1.15                 # Meshy toilets / urinals at 1.15x character scale (r8 0.2 b)
PANEL_Y = (25.2, 36.4)


def _vanity(m, name, L, D, basins):
    """Marble vanity in a local frame (studs): X along the wall (0..L), wall at y = 0, front at y = -D, floor z = 0.
    basins = [x centres]. Under-mount oval basins, apron, backsplash, end legs, exposed P-traps and supplies,
    deck faucets and countertop soap dispensers."""
    a = RMesh(name)
    top, th, ap = 3.3, 0.36, 0.95
    rx, ry, depth = 1.25, 0.82, 0.62
    yc = -D * 0.55
    seg = 28
    cells = []
    for bx in basins:
        cells.append((bx - 1.9, bx + 1.9, bx))
    xs = [0.0] + [v for c in cells for v in c[:2]] + [L]
    # plain slab strips between the basin cells
    for x0, x1 in zip(xs[0::2], xs[1::2]):
        if x1 - x0 > 1e-3:
            a.poly([(x0, -D, top), (x1, -D, top), (x1, 0, top), (x0, 0, top)], m["vanity"], face=(0, 0, 1))
    for x0, x1, bx in cells:
        # rectangle -> ellipse ring (top face), bowl, bottom ring
        def rect_pt(t):
            dx, dy = math.cos(t), math.sin(t)
            sx = (x1 - bx) / abs(dx) if abs(dx) > 1e-9 else 1e9
            sy = ((0 - yc) if dy > 0 else (yc + D)) / abs(dy) if abs(dy) > 1e-9 else 1e9
            k = min(sx, sy)
            return Vector((bx + dx * k, yc + dy * k, top))
        ts = [2 * math.pi * k / seg for k in range(seg)]
        # snap the rectangle corners in so the ring covers the whole cell
        outer = [rect_pt(t) for t in ts]
        for cang in (math.atan2(-yc, x1 - bx), math.atan2(-yc, x0 - bx), math.atan2(-D - yc, x0 - bx), math.atan2(-D - yc, x1 - bx)):
            k = min(range(seg), key=lambda i: abs(math.atan2(math.sin(ts[i] - cang), math.cos(ts[i] - cang))))
            outer[k] = rect_pt(cang)
        rings = []
        K = 5
        for j in range(K + 1):
            f = j / K
            d = depth * f
            s = math.sqrt(max(0.0, 1 - f * f)) * 0.96 + 0.04 if j else 1.0
            rings.append([Vector((bx + rx * s * math.cos(t), yc + ry * s * math.sin(t), top - d)) for t in ts])
        vo = [a.bm.verts.new(p) for p in outer]
        vr = [[a.bm.verts.new(p) for p in r] for r in rings]
        F = a.bm.faces.new
        faces_top, faces_bowl = [], []
        for k in range(seg):
            j = (k + 1) % seg
            faces_top.append(F((vo[k], vo[j], vr[0][j], vr[0][k])))
            for r in range(K):
                faces_bowl.append(F((vr[r][k], vr[r][j], vr[r + 1][j], vr[r + 1][k])))
        faces_bowl.append(F(vr[K]))
        a._done(vo, m["vanity"], False, faces_top)
        a._done([v for r in vr for v in r], m["porcelain"], True, faces_bowl)
        # outside of the bowl below the slab + slab underside ring
        vr2 = [[a.bm.verts.new(p - Vector((0, 0, 0.03))) for p in r] for r in rings[1:]]
        fo = []
        for k in range(seg):
            j = (k + 1) % seg
            for r in range(K - 1):
                fo.append(F((vr2[r][j], vr2[r][k], vr2[r + 1][k], vr2[r + 1][j])))
        a._done([v for r in vr2 for v in r], m["porcelain"], True, fo)
        vb = [a.bm.verts.new(p - Vector((0, 0, th))) for p in outer]
        fb = [F((vb[j], vb[k], vr2[2][k], vr2[2][j])) for k in range(seg) for j in [(k + 1) % seg]]
        a._done(vb, m["vanity"], False, fb)
        a.cyl((bx, yc, top - depth - 0.005), 0.16, 0.02, m["chrome"], seg=10)          # drain
        # P-trap: tailpiece, U-bend, trap arm into the wall, escutcheon
        z0 = top - depth - 0.1
        path = [(bx, yc, z0), (bx, yc, z0 - 0.9), (bx, yc + 0.55, z0 - 0.9), (bx, yc + 0.55, z0 - 0.45), (bx, 0.0, z0 - 0.45)]
        a.tube(_fillet(path, 0.22, 3), 0.1, m["chrome"], seg=8)
        a.cyl((bx, -0.03, z0 - 0.45), 0.24, 0.06, m["chrome"], axis="Y", seg=12)
        for sx in (-0.55, 0.55):                                                         # angle stops + risers
            a.cyl((bx + sx, -0.12, z0 - 0.75), 0.07, 0.24, m["chrome"], axis="Y", seg=8)
            a.tube(_fillet([(bx + sx, -0.24, z0 - 0.75), (bx + sx, -0.3, z0 - 0.75), (bx + sx * 0.5, -0.45, top - th - 0.02)], 0.15, 2),
                   0.035, m["chrome"], seg=6)
        # deck faucet (single lever gooseneck) and soap dispenser
        fy = -0.42
        a.cyl((bx, fy, top + 0.06), 0.2, 0.12, m["chrome"], seg=14)
        a.tube(_fillet([(bx, fy, top + 0.1), (bx, fy, top + 0.75), (bx, fy - 0.55, top + 0.75), (bx, fy - 0.62, top + 0.52)], 0.2, 4),
               0.07, m["chrome"], seg=8)
        a.box((bx, fy + 0.1, top + 0.85), (0.1, 0.4, 0.08), m["chrome"], 0.03, 1)
        sdx = bx + 1.55
        a.box((sdx, -0.45, top + 0.42), (0.62, 0.62, 0.84), m["chrome"], 0.06, 1)
        a.box((sdx, -0.8, top + 0.28), (0.3, 0.12, 0.12), m["black"], 0.03, 1)
    # front apron, backsplash, end legs with stainless shoes, rear ledger
    a.box((L / 2, -D + 0.09, top - 0.005 - ap / 2), (L, 0.18, ap), m["vanity"], 0.05, 2)
    a.box((L / 2, -0.09, top + 0.41), (L, 0.18, 0.86), m["vanity"], 0.04, 1)
    for x in (0.25, L - 0.25):
        a.box((x, -D / 2 + 0.05, (top - th) / 2), (0.5, D - 0.3, top - th), m["vanity_base"], 0.04, 1)
        a.box((x, -D / 2 + 0.05, 0.16), (0.56, D - 0.24, 0.32), m["chrome"], 0.02, 1)
    for x0, x1, bx in cells:
        a.box((bx, -D + 0.1, top - ap - 0.02), (3.4, 0.2, 0.04), m["chrome"])              # apron stiffener lip
    a.col((L / 2, -D / 2, top / 2), (L, D, top))
    a.col((L / 2, -0.09, top + 0.42), (L, 0.18, 0.84))
    return a.finish()


def _mirror(m, name, L, H, rng, cracked):
    """Stainless-frame mirror in a local frame: X along the wall (centred), wall at y = 0, glass faces -Y,
    Z centred. Desilvered edges (jagged dark bands), optional crack star."""
    a = RMesh(name)
    fw, fd = 0.32, 0.26
    a.box((0, -0.06, 0), (L - 0.1, 0.02, H - 0.1), m["mirror"])
    for sgn in (-1, 1):                                                   # frame: angle profile, mitred look
        a.box((sgn * (L / 2 - fw / 2), -fd / 2, 0), (fw, fd, H), m["chrome"], 0.04, 1)
        a.box((0, -fd / 2, sgn * (H / 2 - fw / 2)), (L, fd, fw), m["chrome"], 0.04, 1)
    # desilvering: jagged dark bands creeping in from the frame, strongest along the bottom
    y = -0.075
    ix, iz = L / 2 - fw, H / 2 - fw
    for edge in range(4):
        n = 18 if edge < 2 else 8
        span = 2 * ix if edge < 2 else 2 * iz
        us = [-span / 2 + span * k / n for k in range(n + 1)]
        ds = [rng.uniform(0.1, 0.9 if edge == 0 else 0.5) * (1.7 if rng.random() < 0.15 else 1) for _ in us]
        for k in range(n):
            u0, u1, e0, e1 = us[k], us[k + 1], ds[k], ds[k + 1]
            if edge < 2:
                zs, sg = (-iz, 1) if edge == 0 else (iz, -1)
                pts = [(u0, y, zs), (u1, y, zs), (u1, y, zs + sg * e1), (u0, y, zs + sg * e0)]
            else:
                xs, sg = (-ix, 1) if edge == 2 else (ix, -1)
                pts = [(xs, y, u0), (xs + sg * e0, y, u0), (xs + sg * e1, y, u1), (xs, y, u1)]
            a.poly(pts, m["desilver"], face=(0, -1, 0))
    for _ in range(26):                                                   # splotches
        cx, cz = rng.uniform(-ix + 0.3, ix - 0.3), -iz + abs(rng.gauss(0, 1.3))
        if cz > iz - 0.3:
            continue
        r0 = rng.uniform(0.05, 0.28)
        pts = [(cx + math.cos(t) * r0 * rng.uniform(0.6, 1.4), y - 0.001, cz + math.sin(t) * r0 * rng.uniform(0.6, 1.4))
               for t in [2 * math.pi * k / 7 for k in range(7)]]
        a.poly(pts, m["desilver"], face=(0, -1, 0))
    if cracked:                                                           # impact star
        cx, cz = L * 0.18, H * 0.08
        for k in range(9):
            ang = k * 2 * math.pi / 9 + rng.uniform(-0.2, 0.2)
            ln = rng.uniform(1.2, 3.2)
            px, pz = cx, cz
            for s in range(3):
                nx = px + math.cos(ang) * ln / 3
                nz = pz + math.sin(ang) * ln / 3
                ang += rng.uniform(-0.35, 0.35)
                d = Vector((nx - px, 0, nz - pz)).normalized()
                n = Vector((-d.z, 0, d.x)) * 0.025
                a.poly([(px - n.x, y - 0.004, pz - n.z), (px + n.x, y - 0.004, pz + n.z),
                        (nx + n.x, y - 0.004, nz + n.z), (nx - n.x, y - 0.004, nz - n.z)], m["black"], face=(0, -1, 0))
                px, pz = nx, nz
        a.cyl((cx, y - 0.004, cz), 0.18, 0.004, m["desilver"], axis="Y", seg=10)
    return a.finish()


def build_restrooms(m, rng, meshy):
    objs = []
    t_me, u_me = meshy["ToiletFlush"], _urinal_body(meshy["Urinal"])
    tlo, thi = _mdims(t_me)
    ulo, uhi = _mdims(u_me)
    u_back = uhi[1]
    doors = {p["p"].split("/")[1].split("_")[0] + "%.0f" % p["cf"][0]: p for _, p in _parts(r"^Restrooms/(Men|Women)_StallDoor$")}
    for room in ROOMS:
        nm = room["name"]
        mb = RMesh("Restroom_" + nm)
        P = room["panels"]
        for bi in range(2):
            pl, pr = P[2 * bi], P[2 * bi + 1]
            # side panels (layout StallSide colliders stay; they are protected walls)
            for pc in (pl, pr):
                # Match retained .5-stud StallSide boxes so their opaque insets stay behind every visible face.
                mb.rbox((pc - 0.25, PANEL_Y[0], STALL_Z), (pc + 0.25, PANEL_Y[1], RZ1 - 0.12), m["teal"], 0.06, 1)
                for zb in (156.0, 163.0):                                          # wall-side U brackets
                    mb.rbox((pc - 0.26, PANEL_Y[0] + 1.0, RZ1 - 0.5), (pc + 0.26, PANEL_Y[0] + 1.5, RZ1), m["chrome"], 0.03)
                    mb.rbox((pc - 0.26, PANEL_Y[1] - 1.5, RZ1 - 0.5), (pc + 0.26, PANEL_Y[1] - 1.0, RZ1), m["chrome"], 0.03)
                mb.rbox((pc - 0.2, PANEL_Y[1], STALL_Z), (pc + 0.2, PANEL_Y[1] + 0.3, RZ1), m["teal_dk"], 0.04)   # side headrail
            # the ajar door, from the layout's hinge and angle
            dp = next(p for k, p in doors.items() if k.startswith(nm) and abs(p["cf"][0] - (pl + 4.33)) < 2.5)
            R = _R(dp)
            ax = R[:, 0]
            hinge = np.array(dp["cf"][:3]) - ax * dp["s"][0] / 2
            dw = dp["s"][0] - 0.1
            free_x = hinge[0] + dw + 0.1                                          # closed free edge (x)
            # pilasters (floor to headrail) with stainless shoes and a rusty band above them
            for x0, x1 in ((pl - 0.4, pl + 0.3), (free_x + 0.08, pr + 0.3)):
                mb.rbox((x0, FLOOR, STALL_Z - 0.35), (x1, PANEL_Y[1], STALL_Z + 0.25), m["teal"], 0.06, 1)
                mb.rbox((x0 - 0.05, FLOOR, STALL_Z - 0.4), (x1 + 0.05, FLOOR + 0.75, STALL_Z + 0.3), m["chrome"], 0.03)
                mb.rbox((x0 - 0.01, FLOOR + 0.75, STALL_Z - 0.36), (x1 + 0.01, FLOOR + 1.1, STALL_Z + 0.26), m["rust"])
                mb.rcol((x0 - 0.05, FLOOR, STALL_Z - 0.4), (x1 + 0.05, PANEL_Y[1], STALL_Z + 0.3))
            # front headrail (anti-grip) across the booth
            mb.rbox((pl - 0.45, PANEL_Y[1], STALL_Z - 0.4), (pr + 0.35, PANEL_Y[1] + 0.5, STALL_Z + 0.3), m["teal_dk"], 0.05, 1)
            mb.rcol((pl - 0.45, PANEL_Y[1], STALL_Z - 0.4), (pr + 0.35, PANEL_Y[1] + 0.5, STALL_Z + 0.3))
            # latch keeper on the latch pilaster
            mb.rbox((free_x + 0.02, 28.2, STALL_Z - 0.05), (free_x + 0.12, 28.7, STALL_Z + 0.25), m["chrome"])
            objs.append(_stall_door(m, "%s_StallDoor%d" % (nm, bi + 1), hinge, R, dw, rng))
            # toilet (Meshy), back to the wall, facing the door
            tx = (pl + free_x) / 2
            base = (tx, FLOOR, RZ1 - 0.05 - thi[1] * FIX_SCALE)
            objs.append(_place(t_me, "%s_Toilet" % nm, _M(base, "-Z", scale=FIX_SCALE), model="%s_Toilet" % nm))
            # jumbo roll paper dispenser on the right panel, one roll unspooled to the floor
            px = pr - 0.18
            mb.rbox((px - 0.5, 26.0, 158.4), (px, 28.0, 160.6), m["chrome"], 0.12, 2)
            mb.rcol((px - 0.5, 26.0, 158.4), (px, 28.0, 160.6))
            if (nm, bi) in (("Men", 1), ("Women", 0)):
                for k in range(7):
                    y0 = 25.9 - k * 0.3
                    mb.rbox((px - 0.62 - 0.02 * k, max(FLOOR + 0.02, y0 - 0.3), 159.0 - 0.1 * k),
                            (px - 0.58 - 0.02 * k, y0, 160.0 - 0.1 * k), m["paper"])
                trail = [(px - 0.6, 159.5), (px - 1.4, 158.8), (px - 2.4, 157.2), (px - 2.9, 155.6)]
                for (xa, za), (xb, zc) in zip(trail, trail[1:]):
                    d = Vector((xb - xa, 0, zc - za)).normalized()
                    n = Vector((-d.z, 0, d.x)) * 0.5
                    mb.poly([_B(xa - n.x, FLOOR + 0.03, za - n.z), _B(xb - n.x, FLOOR + 0.03, zc - n.z),
                             _B(xb + n.x, FLOOR + 0.03, zc + n.z), _B(xa + n.x, FLOOR + 0.03, za + n.z)], m["paper"], face=(0, 0, 1))
        # --- vanity + mirror on the sink wall
        L, D = 19.0, 3.2
        wall_x = room["sink_x"]
        face = room["sink_face"]
        sgn = 1 if face == "+X" else -1
        # local frame: X along the wall, wall at y=0, front -Y. facing +X -> local X runs toward -Z (Roblox)
        Mv = _M((wall_x, FLOOR, 149.5 if face == "+X" else 130.5), face)
        objs.append(_obj(_vanity(m, nm + "_Vanity", L, D, (4.5, 14.5)), nm + "_Vanity", Mv, l4_role="fixture"))
        Mm = _M((wall_x, 32.5, 140.5), face)
        objs.append(_obj(_mirror(m, nm + "_Mirror", 20.0, 7.8, rng, cracked=nm == "Women"), nm + "_Mirror", Mm, l4_role="fixture"))
        # puddle under the vanity
        pz = 136.0 if nm == "Men" else 146.0
        px = wall_x + sgn * 3.6
        pts = []
        for k in range(12):
            ang = 2 * math.pi * k / 12
            r = rng.uniform(1.1, 2.0)
            pts.append(_B(px + math.cos(ang) * r * 1.3, FLOOR + 0.06, pz + math.sin(ang) * r * 1.8))
        mb.poly(pts, m["water"], face=(0, 0, 1))
        # --- towel dispenser on the wall + stainless floor waste receptacle at the old bin
        bx0, bx1, bz0, bz1 = room["bin"]
        bw = room["bin_wall"]
        ws = 1 if bw > bx1 else -1                     # +1: wall on +X, the room side faces -X
        fx = bx0 if ws > 0 else bx1                    # room-facing face of the bin
        mb.rbox((bx0, FLOOR, bz0), (bx1, 27.3, bz1), m["chrome"], 0.08, 1)
        mb.rbox((fx - 0.03, 26.1, bz0 + 0.25), (fx + 0.03, 27.0, bz1 - 0.25), m["chrome"])      # push flap
        mb.rbox((bx0 - 0.03, 27.3, bz0 - 0.03), (bx1 + 0.03, 27.5, bz1 + 0.03), m["chrome"], 0.03)
        mb.rcol((bx0, FLOOR, bz0), (bx1, 27.5, bz1))
        tx0, tx1 = (bw - 0.9, bw) if ws > 0 else (bw, bw + 0.9)
        tf = tx0 if ws > 0 else tx1
        mb.rbox((tx0, 28.4, bz0 + 0.2), (tx1, 31.6, bz1 - 0.2), m["chrome"], 0.1, 2)
        mb.rbox((tf - 0.02, 28.55, bz0 + 0.6), (tf + 0.02, 28.75, bz1 - 0.6), m["black"])              # towel slot
        mb.rcol((tx0, 28.4, bz0 + 0.2), (tx1, 31.6, bz1 - 0.2))
        mb.rbox((tf - 0.03, 28.05, bz0 + 0.8), (tf + 0.03, 28.6, bz1 - 0.8), m["paper"])               # towel tongue
        mb.rbox((tf - 0.02, 30.4, bz0 + 0.9), (tf + 0.02, 30.9, bz1 - 0.9), m["black"])                # sight window
        # --- white tile wear and fallen shards; no coloured tile cap
        _tile_trim(mb, m, room, rng)
        # --- round pictogram sign over the door (vestibule side)
        _pictogram(mb, m, (room["door"][0] + room["door"][1]) / 2, 38.5, 124.0, nm)
        objs.append(_pool(mb, "Restroom_" + nm))
    # --- urinals + privacy screen (men's east wall)
    ux = 23301.68
    for k, uz in enumerate((136.2, 140.4, 144.6)):
        Mu = _M((ux - u_back * FIX_SCALE, FLOOR + 0.7, uz), "-X", scale=FIX_SCALE)
        objs.append(_place(u_me, "Men_Urinal%d" % (k + 1), Mu, model="Men_Urinal%d" % (k + 1)))
        objs.append(_urinal_pipes(m, k + 1, Mu, u_back))
    sc = RMesh("UrinalScreen")
    sc.rbox((ux - 3.3, 25.3, 142.36), (ux - 0.12, 32.2, 142.64), m["teal"], 0.06, 1)
    sc.rbox((ux - 0.35, 25.6, 142.2), (ux, 31.9, 142.8), m["chrome"], 0.03)
    sc.rbox((ux - 3.35, 25.1, 142.3), (ux - 3.1, 32.3, 142.7), m["teal_dk"], 0.04)
    sc.rcol((ux - 3.35, 25.1, 142.3), (ux, 32.3, 142.8))
    objs.append(_pool(sc, "Men_UrinalScreen"))
    return [o for o in objs if o]


def _urinal_body(source):
    """Meshy was squared -37.75deg into a side-facing frame. Undo it and replace its tilted chrome plumbing.
    Ceramic ends at 0.9673m; the separate chrome components begin at 0.9872m (verified asset preview)."""
    me = source.copy()
    me.use_fake_user = False
    me.name = "L4D2_UrinalCorrected"
    bm = bmesh.new(); bm.from_mesh(me)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z > 0.975], context="VERTS")
    bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(37.75), 3, "Z"), verts=bm.verts)
    bm.to_mesh(me); bm.free()
    me["l4_asset"] = "UrinalStraight"
    co = np.array([v.co[:] for v in me.vertices]); lo, hi = co.min(0), co.max(0)
    me["l4_col"] = json.dumps([[float(v) for v in (*(lo + hi) / 2, *(hi - lo))]])
    return me


def _urinal_pipes(m, index, placement, back):
    """Straight vertical flush pipe and horizontal supply, ending at the mounting plane (not through it)."""
    mb = RMesh("UrinalPipes%d" % index)
    x, y, z0, zv = -0.06766 / S, 0.14219 / S, 0.960 / S, 1.22 / S
    chrome = m["chrome"]
    mb.cyl((x, y, (z0 + zv) / 2), 0.065, zv - z0, chrome, seg=10)
    for z in (z0 + 0.08, zv - 0.3):
        mb.cyl((x, y, z), 0.1, 0.16, chrome, seg=10)
    mb.cyl((x, y, zv), 0.14, 0.42, chrome, seg=12)
    mb.cyl((x, y, zv + 0.24), 0.18, 0.08, chrome, seg=12)
    # Supply is perfectly horizontal. Escutcheon's outer end is exactly the wall plane.
    mb.cyl((x, (y + back - 0.06) / 2, zv), 0.065, back - 0.06 - y, chrome, axis="Y", seg=10)
    mb.cyl((x, back - 0.03, zv), 0.15, 0.06, chrome, axis="Y", seg=12)
    mb.cyl((x - 0.25, y, zv - 0.05), 0.055, 0.5, chrome, axis="X", seg=8)
    mb.cyl((x - 0.5, y, zv - 0.05), 0.085, 0.1, chrome, axis="X", seg=8)
    mb.col((x, y, (z0 + zv) / 2), (0.22, 0.22, zv - z0))
    return _pool(mb, "Men_UrinalPipes%d" % index, placement)


def _stall_door(m, name, hinge, R, dw, rng):
    """Ajar stall door as its own object: local X from the hinge along the leaf, local -Y = inside face."""
    ax = Vector((R[0, 0], -R[2, 0], 0)).normalized()                     # leaf direction in Blender
    ang = math.atan2(ax.y, ax.x)
    a = RMesh(name)
    y0, y1 = 25.9 - FLOOR, 35.1 - FLOOR
    a.box((dw / 2 + 0.12, 0, (y0 + y1) / 2), (dw, 0.28, y1 - y0), m["teal"], 0.06, 1)
    a.cyl((0.02, 0, (y0 + y1) / 2), 0.08, y1 - y0, m["chrome"], seg=8)          # piano hinge
    # slide latch (inside face) and pull knob + indicator (outside face)
    a.box((dw - 0.2, -0.2, 4.4), (0.9, 0.1, 0.28), m["chrome"], 0.03)
    a.box((dw - 0.55, -0.24, 4.4), (0.12, 0.14, 0.4), m["chrome"], 0.03)
    a.cyl((dw - 0.35, 0.22, 4.4), 0.14, 0.18, m["chrome"], axis="Y", seg=10)
    a.box((dw - 0.35, 0.16, 4.95), (0.5, 0.06, 0.22), m["black"], 0.02)
    a.box((dw - 0.35, 0.2, 4.95), (0.2, 0.04, 0.12), m["cyan"])                  # VACANT window
    a.box((1.3, 0.2, 5.6), (0.08, 0.14, 0.5), m["chrome"], 0.02)                 # coat hook stem (outside)
    a.col((dw / 2 + 0.12, 0, (y0 + y1) / 2), (dw, 0.36, y1 - y0))
    M = Matrix.Translation(_rb((hinge[0], FLOOR, hinge[2]))) @ Matrix.Rotation(ang, 4, "Z")
    return _obj(a.finish(), name, M, l4_role="fixture")


def _tile_trim(mb, m, room, rng):
    """Clusters of missing white wall tiles (mortar showing) and their shards; no cap or trim line."""
    x0, x1 = room["x0"], room["x1"]
    d0, d1 = room["door"]
    y = 31.95
    runs = [((x0, RZ0), (x0, RZ1), "+X"), ((x1, RZ0), (x1, RZ1), "-X"),
            ((x0, RZ1), (x1, RZ1), "-Z"), ((x0, RZ0), (d0, RZ0), "+Z"), ((d1, RZ0), (x1, RZ0), "+Z")]
    TILE = 0.1 / S                         # TILE_CREAM: 12 tiles per 1.2 m repeat, grid on the Blender origin
    for (ax, az), (bx, bz), face in runs:
        xw = face in ("+X", "-X")                        # wall along Z
        u_a, u_b, off = (az, bz, 0.0) if xw else (ax, bx, OX)
        nrm = {"+X": (1, 0, 0), "-X": (-1, 0, 0), "+Z": (0, -1, 0), "-Z": (0, 1, 0)}[face]   # Blender normal
        for _ in range(3 if xw else 2):
            u = u_a + (u_b - u_a) * rng.uniform(0.08, 0.92)
            ci, cj = int((u - off) // TILE), int(rng.uniform(25.2, 31.0) // TILE)
            cells = {(ci, cj)}
            for _k in range(rng.randrange(0, 4)):
                c2 = rng.choice(sorted(cells))
                cells.add((c2[0] + rng.choice((-1, 0, 1)), c2[1] + rng.choice((-1, 0, 1))))
            for i, j in sorted(cells):
                u0, u1 = off + i * TILE + 0.02, off + (i + 1) * TILE - 0.02
                v0, v1 = j * TILE + 0.02, (j + 1) * TILE - 0.02
                if not (FLOOR + 0.9 < v0 and v1 < 31.4 and min(u_a, u_b) < u0 and u1 < max(u_a, u_b)):
                    continue
                if xw:
                    xf = ax + (0.012 if face == "+X" else -0.012)
                    pts = [_B(xf, v0, u0), _B(xf, v0, u1), _B(xf, v1, u1), _B(xf, v1, u0)]
                else:
                    zf = az + (-0.012 if face == "-Z" else 0.012)
                    pts = [_B(u0, v0, zf), _B(u1, v0, zf), _B(u1, v1, zf), _B(u0, v1, zf)]
                mb.poly(pts, m["mortar"], face=nrm)
                if rng.random() < 0.5:                   # its shard on the floor below
                    o = rng.uniform(0.4, 1.4)
                    um = (u0 + u1) / 2 + rng.uniform(-0.5, 0.5)
                    cx, cz = (ax + o * nrm[0], um) if xw else (um, az - o * nrm[1])
                    with mb.at(Matrix.Translation(_B(cx, FLOOR + 0.04, cz)) @ Matrix.Rotation(rng.uniform(0, 6.28), 4, "Z")):
                        mb.box((0, 0, 0), (TILE * rng.uniform(0.4, 0.9), TILE * rng.uniform(0.3, 0.8), 0.05), m["porcelain"])


def _pictogram(mb, m, x, y, z, kind):
    """Round enamel sign on the wall plane z (facing -Z, Blender +Y) with a modelled white pictogram."""
    disc = m["sign_m"] if kind == "Men" else m["sign_w"]
    c = _B(x, y, z)
    mb.cyl(c + Vector((0, 0.06, 0)), 1.35, 0.12, disc, axis="Y", seg=28)
    mb.cyl(c + Vector((0, 0.02, 0)), 1.44, 0.04, m["chrome"], axis="Y", seg=28)
    wy = c.y + 0.14
    W = m["porcelain"]
    mb.cyl(Vector((c.x, wy, c.z + 0.68)), 0.2, 0.04, W, axis="Y", seg=12)          # head
    if kind == "Men":
        mb.box(Vector((c.x, wy, c.z + 0.12)), (0.62, 0.04, 0.8), W)                 # torso
        for sg in (-1, 1):
            mb.box(Vector((c.x + sg * 0.17, wy, c.z - 0.6)), (0.22, 0.04, 0.72), W)  # legs
            mb.box(Vector((c.x + sg * 0.4, wy, c.z + 0.1)), (0.14, 0.04, 0.72), W)   # arms
    else:
        mb.poly([(c.x - 0.18, wy + 0.02, c.z + 0.44), (c.x + 0.18, wy + 0.02, c.z + 0.44),
                 (c.x + 0.5, wy + 0.02, c.z - 0.36), (c.x - 0.5, wy + 0.02, c.z - 0.36)], W, face=(0, 1, 0))
        for sg in (-1, 1):
            mb.box(Vector((c.x + sg * 0.16, wy, c.z - 0.66)), (0.16, 0.04, 0.6), W)
            mb.box(Vector((c.x + sg * 0.34, wy, c.z + 0.18)), (0.12, 0.04, 0.6), W)


# ================================================================ concession (r8 A4)
# Owner v3 point 5: the counter keeps its back (staff) edge at Z 108 and is 5 studs deep; the customer side in front
# is the room's carpet (layout Concession_RedCarpet). Point 7: no checker floor behind it, the carpet runs through.
# COLLIDERS_SUPERSEDED names the old wide layout boxes for P8; the new collider is exactly 5 studs deep.
CX0, CX1, CZ0, CZ1 = 22890.0, 23050.0, 108.0, 112.5      # counter block
COLLIDERS_SUPERSEDED = [r"^Concession/Counter(Top|Plinth|PanelSeam|TopWornFrontLip|Trim)?$",
                         r"^Concession/PopcornCase/"]  # both Meshy machines replace the old deep case collision
CTOP = 28.5
WALL_Z = 102.02                                           # back wall face (skins)
ARC_Z0, ARC_K = 169.0, 0.001325                           # curved marquee soffit: z = ARC_Z0 + ARC_K (x - 23000)^2
KICK_LIT = (22890.0, 23008.0)                             # the magenta kick glow is dead east of this
MENUS = [  # x0, x1, state
    (22895.8, 22934.2, "lit"), (23017.8, 23032.2, "dead"), (23033.8, 23050.2, "askew")]


def _counter(m, rng):
    mb = RMesh("Concession_Counter")
    # body, kick recess, collider (the layout Counter block)
    mb.rbox((CX0 + 0.05, 24.75, CZ0 + 0.1), (CX1 - 0.05, 28.1, CZ1 - 0.02), m["plum_dk"])
    mb.rbox((CX0 + 0.3, FLOOR, CZ0 + 0.4), (CX1 - 0.3, 24.75, CZ1 - 0.5), m["black"])
    mb.rcol((CX0 - 0.3, FLOOR, CZ0), (CX1 + 0.3, CTOP, CZ1 + 0.5))
    # vertical ribbed front (flutes 0.6 pitch), chrome pinstripe battens every 8 studs
    L = CX1 - CX0
    mb.grid(int(L / 0.6) * 4, 1, lambda u, v: _B(CX0 + L * u, 24.75 + 3.0 * v,
                                                  CZ1 + 0.02 + 0.07 * (0.5 + 0.5 * math.cos(2 * math.pi * L * u / 0.6))),
            m["plum"], smooth=True)
    for k in range(int(L / 8) + 1):
        x = CX0 + 8 * k
        mb.rbox((x - 0.08, 24.75, CZ1), (x + 0.08, 27.75, CZ1 + 0.2), m["chrome"], 0.03)
    for x in (CX0, CX1):                                                      # chrome corner guards
        mb.rbox((x - 0.12, 24.75, CZ1 - 0.25), (x + 0.12, 28.1, CZ1 + 0.22), m["chrome"], 0.04)
    mb.rbox((CX0, 27.75, CZ1 - 0.02), (CX1, 28.1, CZ1 + 0.18), m["lacquer"])  # top band
    mb.tube([_B(CX0 + 0.3, 27.93, CZ1 + 0.21), _B(CX1 - 0.3, 27.93, CZ1 + 0.21)], 0.04, m["cyan"], seg=6)
    # magenta kick glow: lit west + middle, dead (dark tube) at the east end
    x_lit = KICK_LIT[1]
    mb.tube([_B(CX0 + 0.4, 24.38, CZ1 - 0.35), _B(x_lit, 24.38, CZ1 - 0.35)], 0.07, m["magenta"], seg=6)
    mb.tube([_B(x_lit + 0.2, 24.38, CZ1 - 0.35), _B(CX1 - 0.4, 24.38, CZ1 - 0.35)], 0.07, m["neon_dead"], seg=6)
    # formica top with a chrome bullnose
    mb.rbox((CX0 - 0.3, 28.1, CZ0), (CX1 + 0.3, CTOP, CZ1 + 0.28), m["formica"], 0.04)
    mb.tube([_B(CX0 - 0.3, 28.3, CZ1 + 0.28), _B(CX1 + 0.3, 28.3, CZ1 + 0.28)], 0.22, m["chrome"], seg=10)
    for x in (CX0 - 0.3, CX1 + 0.3):
        mb.tube([_B(x, 28.3, CZ0 + 0.22), _B(x, 28.3, CZ1 + 0.28)], 0.22, m["chrome"], seg=10)
    # sneeze guards (3) and napkin / straw dispensers
    zg = CZ1 - 1.1                                                            # sneeze-guard post line
    for x0, x1 in ((22924.0, 22944.0), (22966.5, 22978.5), (22990.0, 23010.0)):
        for x in (x0, x1):
            mb.cyl(_B(x, CTOP + 1.85, zg), 0.12, 3.7, m["chrome"], seg=10)
        mb.tube([_B(x0, 32.3, zg), _B(x1, 32.3, zg)], 0.1, m["chrome"], seg=8)
        mb.grid(1, 1, lambda u, v: _B(x0 + 0.15 + (x1 - x0 - 0.3) * u, 29.5 + 2.7 * v, zg - 0.7 + 1.3 * v), m["glass"], smooth=False)
        mb.rcol((x0 - 0.15, CTOP, zg - 0.8), (x1 + 0.15, 32.45, zg + 0.7))
    zn = CZ1 - 2.0                                                            # napkin / straw dispensers
    for x in (22949.0, 23013.5):
        mb.rbox((x - 0.6, CTOP, zn - 0.4), (x + 0.6, CTOP + 1.3, zn + 0.4), m["chrome"], 0.08, 1)
        mb.rbox((x - 0.45, CTOP + 0.3, zn + 0.39), (x + 0.45, CTOP + 1.0, zn + 0.42), m["paper"])
        mb.cyl(_B(x + 1.3, CTOP + 0.9, zn), 0.38, 1.8, m["frost"], seg=12)
        mb.cyl(_B(x + 1.3, CTOP + 0.05, zn), 0.42, 0.1, m["chrome"], seg=12)
        mb.rcol((x - 0.6, CTOP, zn - 0.42), (x + 1.75, CTOP + 1.8, zn + 0.45))
    return _pool(mb, "Concession_Counter")


def _arc_z(x):
    return ARC_Z0 + ARC_K * (x - 23000.0) ** 2


def _arc(m, rng):
    """The curved marquee soffit rebuilt as one continuous band: 8.4 deep x 1.8 tall under the ceiling, rounded
    bottom edges, two recessed channels in the underside housing a magenta and a cyan tube. The east end of the
    cyan channel is dead."""
    mb = RMesh("Concession_Arc")
    xs = [22880.3 + (23119.7 - 22880.3) * k / 64 for k in range(65)]
    W, y0, y1 = 8.4, 50.04, 51.9

    def frame(x):
        dz = 2 * ARC_K * (x - 23000.0)
        t = Vector((1.0, dz)).normalized()                  # tangent in (x, z)
        n = Vector((-t.y, t.x))                             # normal in (x, z), points +z at the apex
        return Vector((x, _arc_z(x))), n

    def sweep(prof, mat, smooth=True):
        """prof: [(offset along n, y)] -> grid along the arc (profile reversed so the faces point outward)"""
        prof = prof[::-1]

        def fn(u, v):
            x = xs[0] + (xs[-1] - xs[0]) * u
            c, n = frame(x)
            k = v * (len(prof) - 1)
            j = min(int(k), len(prof) - 2)
            f = k - j
            o = prof[j][0] * (1 - f) + prof[j + 1][0] * f
            yy = prof[j][1] * (1 - f) + prof[j + 1][1] * f
            return _B(c.x + n.x * o, yy, c.y + n.y * o)
        mb.grid(len(xs) - 1, len(prof) - 1, fn, mat, smooth)
    r = 0.4
    bull = [(W / 2 - r + r * math.sin(a), y0 + r - r * math.cos(a)) for a in [math.pi / 2 * k / 4 for k in range(5)]]
    # outer skin: back face (+n side) -> bullnose -> underside to channel 1
    sweep([(W / 2, y1), (W / 2, y0 + r)] + list(reversed(bull))[1:] + [(1.9, y0)], m["plum"])
    sweep([(-1.9, y0)] + [(-o, yy) for o, yy in bull] + [(-W / 2, y1)], m["plum"])
    sweep([(0.5, y0), (-0.5, y0)], m["plum"])                                       # rib between the channels
    for c0, c1 in ((0.5, 1.9), (-1.9, -0.5)):                                       # channels: sides + roof, black
        sweep([(c1, y0), (c1, y0 + 0.55), (c0, y0 + 0.55), (c0, y0)], m["black"], smooth=False)
    for o in (W / 2 + 0.02, -W / 2 - 0.02):                                          # chrome edge trims
        pts = []
        for x in xs:
            c, n = frame(x)
            pts.append(_B(c.x + n.x * o, y0 + 0.9, c.y + n.y * o))
        mb.tube(pts, 0.06, m["chrome"], seg=6)
    # housed neon: magenta in channel +, cyan in channel - (dead east of x 23060)
    for o, mat in ((1.2, m["magenta"]), (-1.2, m["cyan"])):
        run, dead = [], []
        for x in xs:
            c, n = frame(x)
            p = _B(c.x + n.x * o, y0 + 0.3, c.y + n.y * o)
            (dead if (mat is m["cyan"] and x > 23060) else run).append(p)
        mb.tube(run, 0.09, mat, seg=6, caps=True)
        if dead:
            mb.tube(dead, 0.09, m["neon_dead"], seg=6)
    obj = _pool(mb, "Concession_Arc")
    for i, (x, rgb, b) in enumerate(((22915.0, (255, 40, 200), 0.75), (22975.0, (40, 230, 255), 0.75),
                                     (23035.0, (255, 40, 200), 0.75), (23095.0, (255, 40, 200), 0.35))):
        _light("ArcNeon%d" % i, (x, 48.6, _arc_z(x)), rgb, 30, b, host=obj)
    return obj


def _box_office(m, rng):
    """80s box office frontage fitted to the three Ticket* windows (x 22944-23018 on the back wall)."""
    mb = RMesh("Concession_BoxOffice")
    X0, X1 = 22944.0, 23018.0
    wins = [(22950.0, 22968.0), (22971.0, 22989.0), (22992.0, 23010.0)]
    zf = 103.3                                                                      # frame face
    # sill ledge + brass money troughs
    mb.rbox((X0 + 1.5, 28.05, WALL_Z), (X1 - 1.5, 28.5, 103.9), m["formica"], 0.04)
    mb.tube([_B(X0 + 1.5, 28.28, 103.9), _B(X1 - 1.5, 28.28, 103.9)], 0.2, m["chrome"], seg=8)
    mb.rcol((X0 + 1.5, 28.05, WALL_Z), (X1 - 1.5, 28.5, 104.1))
    # burgundy pilasters with chrome banding between and beside the windows
    piers = [(X0, wins[0][0] + 0.2), (wins[0][1] - 0.2, wins[1][0] + 0.2), (wins[1][1] - 0.2, wins[2][0] + 0.2), (wins[2][1] - 0.2, X1)]
    for x0, x1 in piers:
        mb.rbox((x0, CTOP, WALL_Z), (x1, 39.0, zf), m["burgundy"], 0.08, 1)
        for x in (x0 + 0.12, x1 - 0.12):
            mb.rbox((x - 0.1, CTOP, zf - 0.1), (x + 0.1, 39.0, zf + 0.06), m["chrome"], 0.03)
        mb.rbox((x0 - 0.02, CTOP, WALL_Z), (x1 + 0.02, CTOP + 0.6, zf + 0.08), m["chrome"], 0.03)
    for wi, (x0, x1) in enumerate(wins):
        # booth interior (1 stud deep): dark back, a shelf, a ticket spitter
        mb.rbox((x0, CTOP, WALL_Z), (x1, 39.0, WALL_Z + 0.05), m["plum_dk"])
        mb.rbox((x0 + 1, 30.2, WALL_Z), (x1 - 1, 30.4, 102.8), m["formica"])
        mb.rbox(((x0 + x1) / 2 - 0.8, 30.4, WALL_Z), ((x0 + x1) / 2 + 0.8, 31.3, 102.7), m["black"], 0.05)
        # glass, chrome mullion + transom, lintel
        mb.rbox((x0 + 0.2, CTOP + 0.1, 102.98), (x1 - 0.2, 38.9, 103.02), m["glass"])
        xm = (x0 + x1) / 2
        mb.rbox((xm - 0.15, CTOP, 102.9), (xm + 0.15, 39.0, 103.25), m["chrome"], 0.04)
        mb.rbox((x0, 37.2, 102.9), (x1, 37.45, 103.25), m["chrome"], 0.03)
        mb.rbox((x0 - 0.1, 38.9, WALL_Z), (x1 + 0.1, 39.4, zf + 0.05), m["chrome"], 0.04)
        # speaking grille on a stem, off-centre to the left of the mullion
        gx = xm - 3.2
        mb.cyl(_B(gx, 32.9, 103.1), 0.7, 0.1, m["chrome"], axis="Y", seg=18)
        mb.cyl(_B(gx, 32.9, 103.16), 0.55, 0.02, m["black"], axis="Y", seg=18)
        mb.cyl(_B(gx, 30.6, 103.1), 0.06, 3.9, m["chrome"], seg=6)
        # money trough in the sill
        mb.rbox((xm - 1.4, CTOP, 103.2), (xm + 1.4, CTOP + 0.12, 104.2), m["brass"], 0.04)
        mb.rbox((xm - 1.2, CTOP + 0.02, 103.3), (xm + 1.2, CTOP + 0.13, 104.1), m["black"])
        # sun-faded notice cards taped inside the glass; the east booth has a CLOSED card
        for k in range(rng.randrange(1, 4)):
            nx = rng.uniform(x0 + 1.0, x1 - 2.5)
            ny = rng.uniform(33.8, 36.6)
            mb.rbox((nx, ny, 102.93), (nx + rng.uniform(1.0, 1.8), ny + rng.uniform(1.2, 1.9), 102.96), m["notice"])
        if wi == 2:
            mb.rbox((xm + 1.0, 33.0, 102.93), (xm + 4.4, 34.6, 102.96), m["paper"])
            mb.rbox((xm + 1.4, 33.55, 102.9), (xm + 4.0, 34.05, 102.93), m["red_dk"])
    # header sign can with the modelled TICKETS letters and cyan speed lines
    hz = 104.0
    mb.rbox((X0, 39.4, WALL_Z), (X1, 45.5, hz), m["burgundy"], 0.12, 2)
    for y in (39.55, 45.35):
        mb.tube([_B(X0 - 0.05, y, hz + 0.02), _B(X1 + 0.05, y, hz + 0.02)], 0.13, m["chrome"], seg=8)
    mb.rbox((X0 - 0.3, 45.5, WALL_Z), (X1 + 0.3, 46.0, hz + 0.4), m["chrome"], 0.06, 1)
    mb.rbox((X0 - 0.5, 46.0, WALL_Z), (X1 + 0.5, 46.4, hz + 0.6), m["burgundy"], 0.05, 1)
    for x0, x1 in ((X0 + 1.5, 22966.0), (22996.0, X1 - 1.5)):
        for y in (41.0, 42.3, 43.6):
            mb.tube([_B(x0, y, hz + 0.1), _B(x1, y, hz + 0.1)], 0.07, m["cyan"], seg=6)
    co, faces = _text_geo("TICKETS", 3.3, 0.12)
    # split the K (index by x) into its own flicker lens
    groups = _islands(co, faces)
    groups.sort(key=lambda g: sum(v.x for v in g[0]) / len(g[0]))
    xs_c = [sum(v.x for v in g[0]) / len(g[0]) for g in groups]
    kx = sorted(set(round(x, 1) for x in xs_c))
    k_center = kx[3] if len(kx) > 3 else None                  # T I C K E T S -> 4th letter
    lens = RMesh("TicketsK")
    Mtxt = Matrix.Translation(_B(22981.0, 42.45, hz + 0.25))
    for (gv, gf), gx in zip(groups, xs_c):
        tgt = lens if k_center is not None and abs(round(gx, 1) - k_center) < 0.05 else mb
        tgt.add_geo(gv, gf, m["magenta"], Mtxt)
    for sx in (-8.5, 8.5):
        mb.cyl(_B(22981.0 + sx, 42.45, hz + 0.12), 0.06, 0.25, m["chrome"], axis="Y", seg=6)
    mb.rcol((X0 - 0.5, 28.05, WALL_Z), (X1 + 0.5, 46.4, hz + 0.6))                                # the frontage
    o = _pool(mb, "Concession_BoxOffice", wn=False)
    _flicker(lens, "TicketsK_Flicker", (255, 40, 200), 10, 0.5, (22979.0, 42.4, 105.5))
    _light("TicketsSign", (22981.0, 40.5, 110.0), (255, 40, 200), 16, 0.45)
    return o


def _islands(co, polys):
    parent = list(range(len(co)))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a
    for f in polys:
        for v in f[1:]:
            ra, rb_ = find(f[0]), find(v)
            if ra != rb_:
                parent[ra] = rb_
    groups = {}
    for f in polys:
        groups.setdefault(find(f[0]), []).append(f)
    out = []
    for fs in groups.values():
        idx = sorted({v for f in fs for v in f})
        remap = {v: k for k, v in enumerate(idx)}
        out.append(([co[v] for v in idx], [tuple(remap[v] for v in f) for f in fs]))
    # letters with holes (e.g. none here) are separate islands per contour only if disconnected; merge islands
    # whose centres fall within 0.6 studs of each other so a letter stays one piece
    merged = []
    for gv, gf in sorted(out, key=lambda g: sum(v.x for v in g[0]) / len(g[0])):
        cx = sum(v.x for v in gv) / len(gv)
        if merged and abs(cx - merged[-1][2]) < 0.6:
            pv, pf, pc = merged[-1]
            off = len(pv)
            merged[-1] = (pv + gv, pf + [tuple(i + off for i in f) for f in gf], pc)
        else:
            merged.append((gv, gf, cx))
    return [(gv, gf) for gv, gf, _ in merged]


def _menus(m, rng):
    """Back-lit menu boxes hung on chains from wall brackets at the original board positions. Faces sit < 1 stud
    proud of the old board face so the menu SurfaceGuis land on them. Box A lit, C dead, D dead and hanging
    askew on its west chain."""
    objs = []
    y0, y1, zb, zf = 39.3, 45.3, 102.45, 103.95
    for i, (x0, x1, state) in enumerate(MENUS):
        mb = RMesh("MenuBox%d" % i)
        face = m["board"] if state == "lit" else m["dead_panel"]
        if state == "askew":
            piv = _B(x0 + 0.3, y1, (zb + zf) / 2)
            Mr = Matrix.Translation(piv) @ Matrix.Rotation(math.radians(12), 4, "Y") @ Matrix.Translation(-piv)
        else:
            Mr = Matrix.Identity(4)
        with mb.at(Mr):
            mb.rbox((x0, y0, zb), (x1, y1, zf - 0.05), m["black"], 0.1, 1)
            mb.rbox((x0 + 0.35, y0 + 0.35, zf - 0.06), (x1 - 0.35, y1 - 0.35, zf), face)
            mb.rbox((x0 - 0.04, y1 - 0.12, zb), (x1 + 0.04, y1 + 0.02, zf + 0.04), m["chrome"], 0.03)
            mb.rbox((x0 - 0.04, y0 - 0.02, zb), (x1 + 0.04, y0 + 0.12, zf + 0.04), m["chrome"], 0.03)
            if state != "lit":                                  # grime + a torn corner on the dead faces
                mb.poly([_B(x1 - 0.35, y0 + 0.35, zf + 0.004), _B(x1 - 2.8, y0 + 0.35, zf + 0.004),
                         _B(x1 - 0.35, y0 + 2.2, zf + 0.004)], m["soot"], face=(0, 1, 0))
        # wall brackets + chains (the askew box keeps only its west chain; the east one dangles)
        for j, x in enumerate((x0 + 0.3, x1 - 0.3)):
            mb.rbox((x - 0.12, 47.3, WALL_Z), (x + 0.12, 47.7, 103.4), m["steel"], 0.04)
            mb.rbox((x - 0.16, 47.0, WALL_Z), (x + 0.16, 48.0, WALL_Z + 0.15), m["steel"], 0.03)
            broken = state == "askew" and j == 1
            ytop, ybot = 47.3, (46.0 if broken else y1)
            n = max(2, int((ytop - ybot) / 0.32))
            for k in range(n):
                yy = ytop - (ytop - ybot) * (k + 0.5) / n
                with mb.at(Matrix.Translation(_B(x, yy, 103.2)) @ Matrix.Rotation(math.pi / 2 * (k % 2), 4, "Z")):
                    mb.box((0, 0, 0), (0.18, 0.04, 0.3), m["steel"])
        objs.append(_pool(mb, "MenuBox_%s" % "ACD"[i], wn=False))
        if state == "lit":
            _light("MenuBoxA", ((x0 + x1) / 2, 42.3, 107.0), (255, 236, 205), 16, 0.6)
    return objs


def _popcorn(m, rng, meshy):
    """PopcornCase: Meshy machine (Model PopcornCase, Empty = true) + a second machine, a stainless warmer between,
    a chrome canopy with the POPCORN header (the CaseSign label lands on it), a spilled heap."""
    me = meshy["PopcornMachine"]
    lo, hi = _mdims(me)
    sc = 1.1
    X0, X1, Z0, Z1, YT = 22898.8, 22919.2, CZ0 + 0.6, CZ1 - 0.4, 38.8
    objs = []
    zc = CZ0 + 2.6                                       # machine depth 3.3: back 108.9, front 112.3
    for k, x in enumerate((22903.4, 22914.6)):
        M = _M((x, CTOP, zc), "+Z", scale=sc)
        if k == 0:
            # station collider (whole old case footprint), in this placement's local metres
            c = [((X0 + X1) / 2 - x) * S / sc, -((Z0 + Z1) / 2 - zc) * S / sc, (YT - CTOP) / 2 * S / sc,
                 (X1 - X0) * S / sc, (Z1 - Z0) * S / sc, (YT - CTOP) * S / sc]
            objs.append(_place(me, "PopcornCase", M, model="PopcornCase", attrs={"Empty": True},
                               l4_col=json.dumps([[round(v, 4) for v in c]])))
        else:
            objs.append(_place(me, "PopcornMachine2", M, model="PopcornMachine2", l4_col="[]"))
    mb = RMesh("PopcornStation")
    xm = (22903.4 + 22914.6) / 2
    zw0, zw1 = CZ0 + 1.0, CZ1 - 0.8                                                            # 109.0 .. 112.2
    mb.rbox((xm - 1.5, CTOP, zw0), (xm + 1.5, CTOP + 3.2, zw1), m["chrome"], 0.1, 1)            # warmer cabinet
    mb.rbox((xm - 1.3, CTOP + 0.4, zw1 - 0.01), (xm + 1.3, CTOP + 2.8, zw1 + 0.03), m["glass"])
    mb.rbox((xm - 1.2, CTOP + 0.45, zw0 + 0.4), (xm + 1.2, CTOP + 1.3, zw1 - 0.3), m["popcorn"], 0.2, 1)
    # west end: butter / topping pump dispenser on a stainless stand; east end: nested bucket stacks + bags
    mb.rbox((X0 + 0.2, CTOP, CZ0 + 1.2), (X0 + 2.2, CTOP + 1.6, CZ1 - 0.6), m["chrome"], 0.08, 1)
    for k, z in enumerate((CZ0 + 2.0, CZ0 + 3.5)):
        mb.cyl(_B(X0 + 1.2, CTOP + 2.6, z), 0.55, 2.0, m["butter"], seg=12)
        mb.cyl(_B(X0 + 1.2, CTOP + 3.75, z), 0.35, 0.3, m["black"], seg=10)
        mb.cyl(_B(X0 + 1.2, CTOP + 4.2, z), 0.08, 0.6, m["chrome"], seg=6)
        mb.tube([_B(X0 + 1.2, CTOP + 4.45, z), _B(X0 + 1.2, CTOP + 4.45, z + 0.9), _B(X0 + 1.2, CTOP + 4.1, z + 1.0)], 0.06, m["chrome"], seg=6)
    for k, (x, z, n) in enumerate(((X1 - 1.4, CZ0 + 1.6, 9), (X1 - 1.4, CZ0 + 3.7, 6), (22896.0, CZ0 + 2.2, 4))):
        h = 1.3 + 0.28 * n
        mb.lathe([(0, 0), (0.62, 0), (0.95, h), (0.98, h + 0.06), (0, h + 0.06)], m["bucket"], seg=14, c=_B(x, CTOP, z))
        for j in range(n):
            mb.cyl(_B(x, CTOP + 1.3 + 0.28 * j, z), 0.97, 0.05, m["cup_rim"], seg=14)
    mb.rbox((22891.0, CTOP, CZ0 + 0.4), (22893.9, CTOP + 0.5, CZ0 + 1.6), m["kraft"], 0.03)            # bag bundle
    mb.rbox((22891.2, CTOP + 0.5, CZ0 + 0.5), (22893.7, CTOP + 0.9, CZ0 + 1.5), m["kraft"], 0.03)
    mb.rcol((22891.0, CTOP, CZ0 + 0.4), (22897.0, CTOP + 2.5, CZ0 + 3.2))
    # spilled heap: on the counter in front of the machines, over the nosing and on the carpet below
    for k in range(320):
        if k < 150:
            x, z, y = rng.gauss(22905.0, 3.0), CZ1 - 0.7 + abs(rng.gauss(0, 0.5)), CTOP
            if z > CZ1 + 0.2:
                continue
        else:
            x, z, y = rng.gauss(22906.0, 4.0), CZ1 + 0.6 + abs(rng.gauss(0, 2.2)), FLOOR + 0.05
        h = 0.075 * rng.uniform(0.7, 1.3)
        rot = Matrix.Rotation(rng.uniform(0, 6.28), 3, "Z") @ Matrix.Rotation(rng.uniform(0, 6.28), 3, "X")
        mb.octa(_B(x, y + h * 0.8, z), (h, h * 0.9, h * 0.8), rot, m["popcorn"])
    mb.rbox((22901.0, CTOP, CZ1 - 0.6), (22904.5, CTOP + 0.35, CZ1 + 0.1), m["popcorn"], 0.15, 1)  # the heap core
    objs.append(_pool(mb, "PopcornStation", wn=False))
    _light("PopcornKettle", (22903.4, 35.8, zc), (255, 190, 120), 12, 0.6)
    return objs


def _soda(m, rng, meshy):
    me = meshy["SodaFountain"]
    lo, hi = _mdims(me)
    sc = 1.15                                                  # 4.3 deep: fits the 5-stud counter
    zc = (CZ1 - 0.1) + lo[1] * sc                              # front (drip tray, local -Y) at z 112.9
    objs = [_place(me, "SodaFountain", _M((23025.0, CTOP, zc), "+Z", scale=sc), model="SodaFountain")]
    mb = RMesh("SodaCups")
    zcup = CZ0 + 1.3
    for x, n, lid in ((23016.6, 11, False), (23017.9, 8, True), (23030.6, 13, False)):
        # a nested cup stack is one tall tapered tube with rolled rims
        h = 0.35 * n + 0.9
        mb.lathe([(0, 0), (0.32, 0), (0.44, h), (0.46, h + 0.05), (0, h + 0.05)], m["cup"] if not lid else m["chrome"],
                 seg=12, c=_B(x, CTOP, zcup))
        for k in range(n):
            mb.cyl(_B(x, CTOP + 0.9 + 0.35 * k, zcup), 0.44, 0.05, m["cup_rim"], seg=12)
        mb.rcol((x - 0.46, CTOP, zcup - 0.46), (x + 0.46, CTOP + h + 0.05, zcup + 0.46))
    # toppled cups + sticky stain
    for k in range(4):
        x, z = 23018.8 + rng.uniform(-1.6, 1.6), CZ1 - 0.9 + rng.uniform(-0.4, 0.4)
        with mb.at(Matrix.Translation(_B(x, CTOP + 0.4, z)) @ Matrix.Rotation(rng.uniform(0, 6.28), 4, "Z") @ Matrix.Rotation(math.pi / 2, 4, "Y")):
            mb.lathe([(0, -0.45), (0.3, -0.45), (0.4, 0.45), (0, 0.45)], m["cup"], seg=10)
    pts = [_B(23024.0 + math.cos(t) * rng.uniform(1.2, 2.2) * 1.6, CTOP + 0.012, CZ1 - 0.6 + math.sin(t) * rng.uniform(0.3, 0.6))
           for t in [2 * math.pi * k / 11 for k in range(11)]]
    mb.poly(pts, m["sticky"], face=(0, 0, 1))
    objs.append(_pool(mb, "SodaCups", wn=False))
    return objs


def _candy(m, rng):
    """Curved-glass candy showcase on the counter (x 23033-23049, 4.5 deep), dusty trays, six faded boxes."""
    mb = RMesh("CandyCase")
    X0, X1, ZB, ZF = 23033.0, 23049.0, CZ0 + 0.4, CZ1 - 0.1
    yb, yv, rr = CTOP + 0.7, 33.4, 1.5
    yt = yv + rr
    mb.rbox((X0, CTOP, ZB), (X1, yb, ZF), m["lacquer"], 0.06, 1)                                  # base
    mb.rbox((X0 - 0.03, CTOP, ZF - 0.1), (X1 + 0.03, CTOP + 0.18, ZF + 0.05), m["chrome"], 0.03)
    # section outline: front vertical glass, quarter curve back to the flat top
    sec = [(ZF, yb), (ZF, yv)] + [(ZF - rr + rr * math.cos(a), yv + rr * math.sin(a)) for a in [math.pi / 2 * k / 8 for k in range(1, 9)]]
    sec += [(ZB, yt)]
    mb.grid(1, len(sec) - 1, lambda u, v: _sec_pt(sec, X0 + 0.15 + (X1 - X0 - 0.3) * u, v), m["glass"], smooth=True)
    for x in (X0 + 0.08, X1 - 0.08):                                                            # end frames
        pts = [_B(x, yy, z) for z, yy in sec] + [_B(x, yb, ZB)]
        mb.poly(pts, m["glass"], face=(1 if x > X0 + 1 else -1, 0, 0))
        mb.tube([_B(x, yy, z) for z, yy in sec], 0.1, m["chrome"], seg=6)
    mb.tube([_B(X0, yb + 0.05, ZF), _B(X1, yb + 0.05, ZF)], 0.09, m["chrome"], seg=6)
    mb.tube([_B(X0, yt, ZB + 0.05), _B(X1, yt, ZB + 0.05)], 0.09, m["chrome"], seg=6)
    mb.rbox((X0 + 0.15, yb, ZB), (X1 - 0.15, yt, ZB + 0.08), m["glass_dk"])                       # staff sliders
    mb.rbox((X0 + 0.3, yt - 0.25, ZB + 0.2), (X1 - 0.3, yt - 0.1, ZB + 0.6), m["warm_dim"])      # warm strip
    for k, y in enumerate((30.5, 32.0, 33.5)):                                                  # glass shelves
        zf = ZF - 0.3 - (rr - math.sqrt(max(0, rr * rr - (y - yv) ** 2)) if y > yv else 0) - 0.2
        mb.rbox((X0 + 0.3, y, ZB + 0.3), (X1 - 0.3, y + 0.08, zf), m["glass"])
        for t in range(3):                                                                      # dusty steel trays
            tx = X0 + 1.2 + t * 4.8
            if rng.random() < 0.8:
                mb.rbox((tx, y + 0.08, ZB + 0.8), (tx + 4.0, y + 0.3, zf - 0.4), m["steel_lt"], 0.05)
    boxes = [(23035.0, 30.8), (23040.0, 30.8), (23044.8, 32.3), (23036.2, 33.8), (23041.5, 33.8), (23046.0, 30.8)]
    for k, (bx, by) in enumerate(boxes):
        col = m["candy%d" % (k % 3)]
        w, h, d = rng.uniform(1.6, 2.4), rng.uniform(0.9, 1.3), rng.uniform(0.4, 0.6)
        h = min(h, yt - 0.2 - by)                                                              # under the glass top
        with mb.at(Matrix.Translation(_B(bx, by + h / 2, (ZB + ZF) / 2 + rng.uniform(-0.5, 0.5))) @ Matrix.Rotation(rng.uniform(-0.3, 0.3), 4, "Z")):
            mb.box((0, 0, 0), (w, d, h), col, 0.03)
    mb.rcol((X0, CTOP, ZB), (X1, yt + 0.1, ZF))
    _light("CandyCase", (23041.0, 34.6, ZB + 0.6), (255, 190, 120), 10, 0.3)
    return _pool(mb, "CandyCase", wn=False)


def _sec_pt(sec, x, v):
    k = v * (len(sec) - 1)
    j = min(int(k), len(sec) - 2)
    f = k - j
    z = sec[j][0] * (1 - f) + sec[j + 1][0] * f
    y = sec[j][1] * (1 - f) + sec[j + 1][1] * f
    return _B(x, y, z)


def _register(mb, m, x, z, open_drawer):
    """80s electronic cash register on the counter; the operator stands on the staff side (-Z)."""
    y = CTOP
    mb.rbox((x - 1.8, y, z - 1.7), (x + 1.8, y + 0.9, z + 1.7), m["register"], 0.08, 1)          # drawer box
    if open_drawer:
        mb.rbox((x - 1.6, y + 0.1, z - 2.3), (x + 1.6, y + 0.75, z - 1.7), m["register"], 0.04)
        for k in range(5):
            mb.rbox((x - 1.5 + k * 0.62, y + 0.72, z - 2.2), (x - 1.0 + k * 0.62, y + 0.76, z - 2.0), m["black"])
        mb.rbox((x - 1.5, y + 0.72, z - 2.3), (x + 1.5, y + 0.76, z - 1.8), m["black"])
    # sloped keyboard: low edge on the operator side (z - 1.6, h 1.1) rising to (z + 0.2, h 1.8)
    za, zb, ya, yb = z - 1.6, z + 0.2, y + 1.1, y + 1.8
    for sx in (-1.7, 1.7):
        mb.poly([_B(x + sx, y + 0.9, za), _B(x + sx, ya, za), _B(x + sx, yb, zb), _B(x + sx, y + 0.9, zb)],
                m["register"], face=(1 if sx > 0 else -1, 0, 0))
    mb.poly([_B(x - 1.7, y + 0.9, za), _B(x + 1.7, y + 0.9, za), _B(x + 1.7, ya, za), _B(x - 1.7, ya, za)], m["register"], face=(0, 1, 0))
    mb.poly([_B(x - 1.7, ya, za), _B(x + 1.7, ya, za), _B(x + 1.7, yb, zb), _B(x - 1.7, yb, zb)], m["register"], face=(0, 1, 1))
    slope = math.atan2(yb - ya, zb - za)
    for i in range(6):
        for j in range(3):
            t = (j + 0.5) / 3
            kz, ky = za + (zb - za) * t, ya + (yb - ya) * t
            with mb.at(Matrix.Translation(_B(x - 1.25 + i * 0.5, ky + 0.03, kz)) @ Matrix.Rotation(slope, 4, "X")):
                mb.box((0, 0, 0), (0.34, 0.34, 0.08), m["key"] if (i + j) % 5 else m["key_red"])
    # rear tower with the operator display, pole customer display, receipt roll
    mb.rbox((x - 1.7, y + 0.9, zb), (x + 1.7, y + 2.4, z + 1.7), m["register"], 0.06, 1)
    mb.rbox((x - 1.0, y + 1.9, zb - 0.02), (x + 1.0, y + 2.25, zb), m["vfd"])
    mb.cyl(_B(x + 1.0, y + 2.9, z + 1.4), 0.1, 1.0, m["register"], seg=8)
    mb.rbox((x + 0.4, y + 3.3, z + 1.3), (x + 1.6, y + 3.8, z + 1.5), m["register"], 0.04)
    mb.rbox((x + 0.55, y + 3.4, z + 1.5), (x + 1.45, y + 3.7, z + 1.52), m["vfd"])
    mb.cyl(_B(x - 1.1, y + 2.55, z + 0.9), 0.3, 0.6, m["paper"], axis="X", seg=10)
    mb.rcol((x - 1.8, y, z - (2.3 if open_drawer else 1.7)), (x + 1.8, y + 2.6, z + 1.7))


def build_concession(m, rng, meshy):
    objs = [_counter(m, rng), _arc(m, rng), _box_office(m, rng)]
    objs += _menus(m, rng)
    objs += _popcorn(m, rng, meshy)
    objs += _soda(m, rng, meshy)
    objs.append(_candy(m, rng))
    mb = RMesh("Registers")
    _register(mb, m, 22962.0, CZ0 + 2.3, False)
    _register(mb, m, 22983.0, CZ0 + 2.3, True)
    objs.append(_pool(mb, "Registers"))
    # counter kick glow lights (west + middle lit; the east end is the dead stretch)
    for i, x in enumerate((22920.0, 22975.0)):
        _light("CounterKick%d" % i, (x, 24.4, CZ1 + 2.8), (255, 40, 200), 8, 0.25)
    return [o for o in objs if o]


# ================================================================ arcade (r8 A5; owner v3 point 8)
# One hall between two solid side walls. The side spaces behind them (X 23122-23172 / 23212-23259) are closed voids
# filled by the walls' colliders (obj l4_occluder: the pipeline makes them opaque camera blockers). Cabinets line
# both walls from the front wall to the prize counter; the single door is centred on the hall at X 23192 (P5).
AL_WALL, AR_WALL = 23172.0, 23212.0            # side wall faces (left faces +X, right faces -X)
A_ROOM = (23122.0, 23259.0)                    # the arcade room's own inner wall faces
AZ0, AZ1, A_TOP = 102.0, 238.0, 52.0           # front / back wall faces, roof underside
A_WALL_T = 0.6                                 # visible wall slab thickness
LINE = {"L": (102.3, 221.6), "R": (102.3, 221.3)}   # cabinet runs; the ticket terminal / gumball close each run
# screen glass of the Meshy uprights (local metres, measured by ray profile): (y0, z0) -> (y1, z1), half width
SCREENS = {"ArcadeUprightA": ((-0.150, 1.18), (-0.035, 1.58), 0.22),
           "ArcadeUprightB": ((-0.115, 1.16), (0.045, 1.60), 0.28)}
CRT = [(40, 230, 255), (255, 40, 200), (120, 150, 255), (60, 255, 170), (255, 170, 60)]        # glow light colours
CRT_FACE = [(24, 96, 128), (112, 18, 92), (44, 56, 136), (24, 112, 76), (124, 76, 26)]         # dim neon screen faces
NEON_RGB = {"magenta": (255, 40, 200), "cyan": (40, 230, 255)}


def _arcade_wall(mb, m, rng, side, flick):
    """One solid side wall: wallpaper slab up to the roof, black lacquer skirting with a chrome cap line, a lacquer
    channel carrying a magenta and a cyan neon line above the cabinets, and a cyan cove line under a lacquer cornice.
    The lines run in eight segments with a few dead; segment flick["key"] = (side, line, index) is left out and
    returned in flick["out"] so the caller can build it as a flicker lens."""
    face = 1 if side == "L" else -1
    xw = AL_WALL if side == "L" else AR_WALL

    def X(o):
        return xw + face * o

    def rb(o0, o1, y0, y1, z0, z1, mat, bev=0.0):
        xa, xb = sorted((X(o0), X(o1)))
        mb.rbox((xa, y0, z0), (xb, y1, z1), mat, bev)
    rb(-A_WALL_T, 0.0, FLOOR, A_TOP, AZ0, AZ1, m["wallpaper"])
    rb(0.0, 0.16, FLOOR, FLOOR + 1.3, AZ0, AZ1, m["lacquer"], 0.03)
    rb(0.0, 0.06, FLOOR + 1.3, FLOOR + 1.42, AZ0, AZ1, m["chrome"])
    rb(0.0, 0.1, 33.9, 35.9, AZ0, AZ1, m["lacquer"], 0.03)
    rb(0.0, 0.4, A_TOP - 1.3, A_TOP, AZ0, AZ1, m["lacquer"], 0.05)
    rb(0.38, 0.44, A_TOP - 1.3, A_TOP - 1.18, AZ0, AZ1, m["chrome"])
    n = 8
    for li, (y, col, r) in enumerate(((34.45, "magenta", 0.06), (35.35, "cyan", 0.06), (A_TOP - 1.6, "cyan", 0.05))):
        for k in range(n):
            z0 = AZ0 + 0.5 + (AZ1 - AZ0 - 1.0) * k / n + 0.1
            z1 = AZ0 + 0.5 + (AZ1 - AZ0 - 1.0) * (k + 1) / n - 0.1
            pts = [_B(X(0.2), y, z0), _B(X(0.2), y, z1)]
            if (side, li, k) == flick["key"]:
                flick["out"] = (pts, r, col, (X(1.2), y, (z0 + z1) / 2))
                continue
            dead = rng.random() < 0.12
            mb.tube(pts, r, m["neon_dead"] if dead else m[col], seg=6)
            for z in (z0 + 0.25, z1 - 0.25):                                # standoff clips
                rb(0.08, 0.24, y - 0.08, y + 0.08, z - 0.05, z + 0.05, m["chrome"])
    void = (A_ROOM[0], AL_WALL) if side == "L" else (AR_WALL, A_ROOM[1])
    mb.rcol((void[0], FLOOR, AZ0), (void[1], A_TOP, AZ1))
    for z, col in ((125.0, "magenta"), (165.0, "cyan"), (205.0, "magenta")):
        c = col if side == "L" else ("cyan" if col == "magenta" else "magenta")
        _light("ArcadeWall%s%.0f" % (side, z), (X(1.4), 35.0, z), NEON_RGB[c], 18, 0.35)


def _arcade_run(side, rng, width):
    """-> kinds filling the run: upright runs (A/B, rarely the same twice), pinball pairs/trios and twin racing
    cabinets (never in the first 14 studs, so the deep seats stand clear of the entrance)."""
    z0, z1 = LINE[side]
    L = z1 - z0
    seq, tot, special = [], 0.0, rng.random() < 0.5
    cur = rng.choice(("ArcadeUprightA", "ArcadeUprightB"))
    while tot < L:
        for _ in range(rng.randint(3, 6)):
            seq.append(cur)
            tot += width[cur] + 0.15
            if rng.random() < 0.75:
                cur = "ArcadeUprightB" if cur == "ArcadeUprightA" else "ArcadeUprightA"
        if tot > 14.0:
            kind = "ArcadeRacing" if special else "Pinball"
            for _ in range(2 if special else rng.randint(2, 3)):
                seq.append(kind)
                tot += width[kind] + 0.15
            special = not special
    while sum(width[k] + 0.15 for k in seq) > L:
        seq.pop()
    if seq and seq[-1] == "ArcadeRacing" and seq.count("ArcadeRacing") % 2:   # no orphaned twin seat
        seq.pop()
    for kind in sorted(("ArcadeUprightA", "ArcadeUprightB"), key=width.get):
        while sum(width[k] + 0.15 for k in seq) + width[kind] + 0.15 <= L:
            seq.append(kind)
    return seq


def build_arcade(m, rng, meshy):
    objs = []
    kinds_all = ("ArcadeUprightA", "ArcadeUprightB", "Pinball", "ArcadeRacing")
    dims = {a: _mdims(meshy[a]) for a in kinds_all}
    vertices = {a: np.array([v.co[:] for v in meshy[a].vertices]) / S for a in kinds_all}
    width = {a: d[1][0] - d[0][0] + 0.04 * (d[1][1] - d[0][1]) for a, d in dims.items()}
    scr = RMesh("ArcadeScreens")
    uprights, placed = [], {"L": [], "R": []}
    for side in ("L", "R"):
        seq = _arcade_run(side, rng, width)
        z0, z1 = LINE[side]
        angles = [max(-1.5, min(1.5, rng.gauss(0, 0.7))) for _ in seq]
        face = 1 if side == "L" else -1
        # Pack actual rotated silhouettes with an 0.08stud joining seam. Mesh and collision share the
        # slight width adjustment; using vertices also accounts for racing seats' irregular outlines.
        projections = [(-face * vertices[kind][:, 0] * math.cos(math.radians(a)),
                         face * vertices[kind][:, 1] * math.sin(math.radians(a)))
                       for kind, a in zip(seq, angles)]
        seam = 0.08
        available = z1 - z0 - seam * (len(seq) - 1)
        stretch = 1.0
        for _ in range(4):
            span = [np.ptp(x * stretch + y) for x, y in projections]
            stretch *= available / sum(span)
        assert 0.98 <= stretch <= 1.15, "arcade packing must preserve cabinet proportions"
        extents = [(float(p.min()), float(p.max())) for x, y in projections for p in [x * stretch + y]]
        z = z0
        xw = AL_WALL if side == "L" else AR_WALL
        for i, kind in enumerate(seq):
            edge0, edge1 = extents[i]
            zc = z - edge0
            z += edge1 - edge0 + seam
            lo, hi = dims[kind]
            ang = angles[i]
            off = 0.04 + (hi[0] - lo[0]) * stretch / 2 * abs(math.sin(math.radians(ang))) + rng.uniform(0, 0.05)
            pos = (xw + face * (hi[1] + off), FLOOR, zc)
            M = _M(pos, "+X" if side == "L" else "-X", ang=ang) @ Matrix.Diagonal((stretch, 1, 1, 1))
            name = "Arcade%s_%02d" % ("Left" if side == "L" else "Right", i + 1)
            objs.append(_place(meshy[kind], name, M, model=name, attrs={"ArcadeCabinet": True}))
            placed[side].append((kind, zc, xw + face * (hi[1] - lo[1] + off)))   # (kind, z, front line x)
            if kind in SCREENS:
                uprights.append((M, kind, side))
    # screens: ~78 % glowing CRT quads, the rest dead (dark glass), two of the dead ones cracked
    order = list(range(len(uprights)))
    rng.shuffle(order)
    ndead = int(round(len(uprights) * 0.22))
    dead = set(order[:ndead])
    cracked = set(order[:2])
    lit = [i for i in range(len(uprights)) if i not in dead]
    surface, marquee = set(), set()
    for side in ("L", "R"):                                                  # three glowing CRTs light each aisle
        ls = [i for i in lit if uprights[i][2] == side]
        pick = [ls[int(len(ls) * f)] for f in (0.15, 0.5, 0.85)] if ls else []
        surface |= set(pick)
        marquee |= set(pick[1:2])
    for i, (M, kind, side) in enumerate(uprights):
        (y0, z0), (y1, z1), hw = SCREENS[kind]
        d = Vector((0, y1 - y0, z1 - z0)).normalized()
        nrm = Vector((0, -d.z, d.y))                                        # toward the viewer (-Y, up)
        off = nrm * 0.012
        c0 = Vector((0, y0, z0)) + off
        c1 = Vector((0, y1, z1)) + off
        pts = [c0 + Vector((-hw, 0, 0)), c0 + Vector((hw, 0, 0)), c1 + Vector((hw, 0, 0)), c1 + Vector((-hw, 0, 0))]
        Ms = Matrix.Diagonal((1 / S, 1 / S, 1 / S, 1)) @ M                  # local metres -> world studs
        mat = m["crt_dead"] if i in dead else m["crt%d" % (i % len(CRT))]
        with scr.at(Ms):
            scr.poly(pts, mat, face=nrm)
            if i in cracked:
                cx = (c0 + c1) / 2 + nrm * 0.004
                for k in range(7):
                    a = k * 2 * math.pi / 7 + rng.uniform(-0.3, 0.3)
                    e = cx + Vector((math.cos(a) * hw * 0.9, 0, 0)) + d * math.sin(a) * 0.18
                    tvec = (e - cx).normalized()
                    side_v = tvec.cross(nrm).normalized() * 0.006
                    scr.poly([cx - side_v, cx + side_v, e + side_v, e - side_v], m["crack"], face=nrm)
        if i in surface:
            pos = M @ ((c0 + c1) / 2 + nrm * 0.025)
            direction = M.to_3x3() @ nrm
            _light("ArcadeCRT%d" % i, (pos.x / S + OX, pos.z / S, -pos.y / S), CRT[i % len(CRT)],
                   9, 0.3, kind="AREA", direction=direction, size=(2 * hw / S, (c1 - c0).length / S), energy_k=0.08)
        if i in marquee:                                                     # one marquee box glows per side
            pos = M @ Vector((0, -0.24, 1.94))
            _light("ArcadeMarquee%d" % i, (pos.x / S + OX, pos.z / S, -pos.y / S), CRT[i % len(CRT)],
                   8, 0.22, kind="AREA", direction=M.to_3x3() @ Vector((0, -1, 0)),
                   size=(2 * hw / S, 0.55), energy_k=0.08)
    objs.append(_pool(scr, "ArcadeScreens", wn=False))
    # the two solid side walls (+ their void colliders); one neon segment flickers
    wall = RMesh("ArcadeSideWalls")
    flick = {"key": ("R", 0, 5), "out": None}
    for side in ("L", "R"):
        _arcade_wall(wall, m, rng, side, flick)
    objs.append(_pool(wall, "ArcadeSideWalls", wn=False, l4_occluder=True))
    if flick["out"]:
        pts, r, col, lpos = flick["out"]
        lens = RMesh("ArcadeWallNeonFlicker")
        lens.tube(pts, r, m[col], seg=6)
        _flicker(lens, "ArcadeWallNeon_Flicker", NEON_RGB[col], 16, 0.4, lpos)
    objs += _prize(m, rng)
    objs += _arcade_dressing(m, rng, placed)
    return [o for o in objs if o]


def _plush(mb, m, c, s, col, rng, yaw=0.0):
    """Sitting plush bear: body, head, ears, muzzle, arms, feet. c = Roblox base point, s = scale (studs)."""
    x, y, z = c
    rot = Matrix.Rotation(yaw, 4, "Z")
    with mb.at(Matrix.Translation(_B(x, y, z)) @ rot):
        mb.sphere((0, 0, 0.55 * s), 0.55 * s, col, seg=7, rings=4)
        mb.sphere((0, -0.05 * s, 1.3 * s), 0.42 * s, col, seg=7, rings=4)
        for sx in (-1, 1):
            mb.sphere((sx * 0.3 * s, 0.0, 1.66 * s), 0.14 * s, col, seg=5, rings=3)
            mb.sphere((sx * 0.5 * s, -0.25 * s, 0.7 * s), 0.18 * s, col, seg=5, rings=3)
            mb.sphere((sx * 0.3 * s, -0.45 * s, 0.18 * s), 0.2 * s, col, seg=5, rings=3)
        mb.sphere((0, -0.4 * s, 1.22 * s), 0.14 * s, m["plush_muzzle"], seg=5, rings=3)


def _prize(m, rng):
    """Glass-front prize showcase + back shelving with plush and balls, staff door with a vision panel, gumball
    machine, redemption terminal."""
    objs = []
    mb = RMesh("ArcadePrize")
    X0, X1, ZF, ZB = 23175.0, 23209.0, 224.0, 230.0
    yt = 28.6
    mb.rbox((X0, FLOOR, ZF + 0.3), (X1, FLOOR + 0.5, ZB), m["black"])                              # kick
    mb.rbox((X0, FLOOR + 0.5, ZF + 0.05), (X1, FLOOR + 0.9, ZB), m["lacquer"])
    mb.rbox((X0 + 0.1, FLOOR + 0.9, ZF + 0.08), (X1 - 0.1, yt - 0.3, ZF + 0.12), m["glass"])        # front glass
    for x in [X0 + (X1 - X0) * k / 4 for k in range(5)]:
        mb.rbox((x - 0.15, FLOOR + 0.5, ZF), (x + 0.15, yt, ZF + 0.3), m["chrome"], 0.04)
    for x in (X0, X1):                                                                           # end glass
        mb.rbox((x - 0.05, FLOOR + 0.9, ZF + 0.3), (x + 0.05, yt - 0.3, ZB - 0.3), m["glass"])
    mb.rbox((X0 - 0.2, yt - 0.3, ZF - 0.2), (X1 + 0.2, yt, ZB + 0.1), m["formica"], 0.04)          # top
    mb.tube([_B(X0 - 0.2, yt - 0.15, ZF - 0.2), _B(X1 + 0.2, yt - 0.15, ZF - 0.2)], 0.16, m["chrome"], seg=8)
    mb.rbox((X0 + 0.2, FLOOR + 0.9, ZB - 0.2), (X1 - 0.2, yt - 0.3, ZB), m["mirror_dk"])             # mirrored back
    for y in (25.9, 27.1):                                                                       # glass shelves
        mb.rbox((X0 + 0.3, y, ZF + 0.4), (X1 - 0.3, y + 0.06, ZB - 0.3), m["glass"])
    for k in range(26):                                                                          # balls, small plush
        x = rng.uniform(X0 + 1, X1 - 1)
        z = rng.uniform(ZF + 1.2, ZB - 1.2)
        y = rng.choice((FLOOR + 0.9, 25.96, 27.16))
        if rng.random() < 0.5:
            r = rng.uniform(0.25, 0.45)
            mb.sphere(_B(x, y + r, z), r, m["ball%d" % (k % 3)], seg=10, rings=6)
        else:
            _plush(mb, m, (x, y, z), rng.uniform(0.45, 0.6), m["plush%d" % (k % 4)], rng, yaw=rng.uniform(2.6, 3.7))
    # Steady showcase strip under the top.
    mb.rcol((X0 - 0.2, FLOOR, ZF - 0.2), (X1 + 0.2, yt, 237.0))
    mb.rbox((X0 + 1, yt - 0.42, ZF + 0.6), (X1 - 1, yt - 0.32, ZF + 0.9), m["warm"])
    _light("PrizeLamp", ((X0 + X1) / 2, 27.6, ZF + 2.0), (255, 196, 140), 12, 0.5)
    # back shelving on the rear wall
    SZ0, SZ1 = 234.6, 237.6
    for x in [23174.0 + 36.0 * k / 4 for k in range(5)]:
        mb.rbox((x - 0.3, 28.4, SZ0), (x + 0.3, 47.6, SZ1), m["wood"], 0.04)
    for y in (28.6, 33.0, 38.0, 43.0, 47.4):
        mb.rbox((23174.0, y, SZ0), (23210.0, y + 0.4, SZ1), m["wood"], 0.04)
        mb.rbox((23174.0, y - 0.05, SZ0 - 0.05), (23210.0, y + 0.45, SZ0 + 0.05), m["brass"])
    mb.rbox((23174.3, 28.4, SZ1 - 0.1), (23209.7, 47.6, SZ1), m["plum_dk"])
    mb.rbox((23174.0, FLOOR, SZ0), (23210.0, 28.4, SZ1), m["wood"], 0.05)                         # base cabinet
    for y in (29.0, 33.4, 38.4, 43.4):
        x = 23175.2
        while x < 23208.5:
            if rng.random() < 0.28:                                           # gaps: long-gone prizes
                x += rng.uniform(1.5, 3.0)
                continue
            if rng.random() < 0.7:
                sc = rng.uniform(0.8, 1.25)
                _plush(mb, m, (x + 0.8 * sc, y, 236.0), sc, m["plush%d" % rng.randrange(4)], rng, yaw=rng.uniform(-0.4, 0.4))
                x += 1.9 * sc
            else:
                r = rng.uniform(0.45, 0.8)
                mb.sphere(_B(x + r, y + r, 236.0), r, m["ball%d" % rng.randrange(3)], seg=12, rings=7)
                x += 2 * r + 0.2
    # a big star and a rocket on the top shelf (as in the reference)
    star = []
    for k in range(10):
        a = math.pi / 2 + k * math.pi / 5
        r = 1.6 if k % 2 == 0 else 0.7
        star.append((23180.0 + r * math.cos(a), 49.6 + r * math.sin(a)))
    with mb.at(Matrix.Translation(_B(23180.0, 49.5, 236.0)) @ Matrix.Rotation(math.pi / 2, 4, "X")):
        mb.prism([(sx - 23180.0, sy - 49.6) for sx, sy in star], 0.0, 0.3, m["brass"])
    mb.rcol((23174.0, 28.4, SZ0), (23210.0, 47.8, SZ1))
    objs.append(_pool(mb, "ArcadePrize", wn=False))
    # staff door on the right side wall behind the prize counter (the rear-wall pair now opens into the void)
    dr = RMesh("ArcadeStaffDoor")
    dx, dz0, dz1 = AR_WALL, 229.2, 236.8
    dr.rbox((dx - 0.35, FLOOR, dz0), (dx, 37.5, dz1), m["steel"], 0.04)                         # hollow-metal frame
    dr.rbox((dx - 0.34, FLOOR + 0.1, dz0 + 0.5), (dx - 0.3, 37.0, dz1 - 0.5), m["door_red"])
    dr.rbox((dx - 0.36, 30.0, 231.6), (dx - 0.35, 34.5, 234.4), m["glass_wire"])                # vision panel
    dr.rbox((dx - 0.37, 29.8, 231.4), (dx - 0.36, 34.7, 234.6), m["steel"])
    dr.rbox((dx - 0.6, 28.2, dz0 + 1.0), (dx - 0.4, 28.6, dz1 - 1.0), m["chrome"], 0.08)        # push bar
    dr.rbox((dx - 0.36, FLOOR + 0.1, dz0 + 0.6), (dx - 0.35, FLOOR + 1.6, dz1 - 0.6), m["chrome"])  # kick plate
    dr.rbox((dx - 0.38, 35.3, 231.3), (dx - 0.37, 36.2, 234.7), m["placard"])
    co, faces = _text_geo("STAFF ONLY", 0.5, 0)
    dr.add_geo(co, faces, m["black"], Matrix.Translation(_B(dx - 0.39, 35.75, 233.0)) @ Matrix.Rotation(-math.pi / 2, 4, "Z"))
    dr.rcol((dx - 0.6, FLOOR, dz0), (dx, 37.5, dz1))
    objs.append(_pool(dr, "ArcadeStaffDoor", wn=False))
    # gumball machine closes the right cabinet run
    gb = RMesh("Gumball")
    gx, gz = AR_WALL - 1.35, LINE["R"][1] + 1.6
    gb.lathe([(0, 0), (1.1, 0), (1.1, 0.2), (0.35, 0.5), (0.25, 2.6), (0.55, 2.8), (0.62, 3.6), (0.3, 3.7), (0, 3.7)],
             m["red_enamel"], seg=16, c=_B(gx, FLOOR, gz))
    gb.box(_B(gx - 0.62, 27.1, gz), (0.12, 0.5, 0.6), m["chrome"], 0.03)                          # coin mech
    gb.sphere(_B(gx, 29.05, gz), 1.25, m["glass"], seg=16, rings=10)
    for k in range(40):
        a, b_, r = rng.uniform(0, 6.28), rng.uniform(-1.2, 0.2), rng.uniform(0, 0.95)
        gb.sphere(_B(gx + math.cos(a) * r, 29.05 + b_ * 0.9, gz + math.sin(a) * r), 0.17, m["ball%d" % (k % 3)], seg=6, rings=4)
    gb.lathe([(0, 0), (0.55, 0), (0.5, 0.35), (0.15, 0.5), (0, 0.55)], m["red_enamel"], seg=14, c=_B(gx, 30.2, gz))
    gb.rcol((gx - 1.25, FLOOR, gz - 1.25), (gx + 1.25, 30.8, gz + 1.25))
    objs.append(_pool(gb, "Gumball", wn=False))
    # redemption terminal (ticket eater) closes the left run, facing the aisle (+X)
    rt = RMesh("RedemptionTerminal")
    tz = LINE["L"][1] + 1.3
    with rt.at(Matrix.Translation(_B(AL_WALL + 0.85, FLOOR, tz)) @ Matrix.Rotation(math.pi / 2, 4, "Z")):
        rt.box((0, 0, 2.2), (1.9, 1.6, 4.4), m["black"], 0.12, 2)
        rt.box((0, -0.3, 4.85), (2.1, 1.0, 0.9), m["magenta"])                                      # lit header
        rt.box((0, -0.82, 3.5), (1.3, 0.05, 0.9), m["crt0"])
        rt.box((0, -0.84, 2.3), (0.9, 0.08, 0.25), m["chrome"], 0.03)                               # ticket slot
        rt.box((0, -0.86, 2.3), (0.7, 0.04, 0.06), m["black"])
        rt.box((0, -0.9, 1.4), (1.3, 0.2, 0.5), m["chrome"], 0.05)                                 # receipt tray
    rt.rcol((AL_WALL, FLOOR, tz - 1.05), (AL_WALL + 1.75, FLOOR + 5.4, tz + 1.05))
    objs.append(_pool(rt, "RedemptionTerminal", wn=False))
    return objs


def _stool(mb, m, x, z, tipped, rng):
    """Chrome-ring bar stool with a burgundy vinyl seat (1.25x scale). tipped: lying on its side."""
    M = Matrix.Translation(_B(x, FLOOR, z)) @ Matrix.Rotation(rng.uniform(0, 6.28), 4, "Z")
    if tipped:
        M = Matrix.Translation(_B(x, FLOOR + 0.95, z)) @ Matrix.Rotation(rng.uniform(0, 6.28), 4, "Z") @ Matrix.Rotation(math.pi / 2 - 0.25, 4, "X") @ Matrix.Translation((0, 0, -1.8))
    with mb.at(M):
        mb.cyl((0, 0, 3.35), 0.95, 0.35, m["vinyl"], seg=16)
        mb.cyl((0, 0, 3.13), 0.8, 0.12, m["chrome"], seg=16)
        for k in range(4):
            a = k * math.pi / 2 + math.pi / 4
            mb.tube([(0.35 * math.cos(a), 0.35 * math.sin(a), 3.1), (0.85 * math.cos(a), 0.85 * math.sin(a), 0.05)], 0.07, m["chrome"], seg=6)
        mb.tube([(0.72 * math.cos(t), 0.72 * math.sin(t), 1.1) for t in [2 * math.pi * k / 16 for k in range(17)]], 0.05, m["chrome"], seg=5, caps=False)
    if not tipped:
        mb.rcol((x - 0.95, FLOOR, z - 0.95), (x + 0.95, FLOOR + 3.55, z + 0.95))
    else:
        mb.rcol((x - 1.9, FLOOR, z - 1.9), (x + 1.9, FLOOR + 1.9, z + 1.9))


def _arcade_dressing(m, rng, placed):
    mb = RMesh("ArcadeDressing")
    for side in ("L", "R"):
        candidates = [p for p in placed[side] if p[0].startswith("ArcadeUpright") and 140 < p[1] < 210]
        for kind, z, front in candidates[::max(1, len(candidates) // 2)][:2]:
            _stool(mb, m, front + (1.5 if side == "L" else -1.5), z, False, rng)
    # redemption-ticket streamers: folded strips on the carpet near the prize counter and the cabinet fronts
    spots = [(rng.uniform(23177, 23207), rng.uniform(215, 223.5)) for _ in range(40)]
    spots += [(rng.uniform(23176.5, 23180), rng.uniform(133, 214)) for _ in range(20)]
    spots += [(rng.uniform(23204, 23207.5), rng.uniform(119, 214)) for _ in range(20)]
    for sx, sz in spots:
        n = rng.randrange(3, 9)
        a = rng.uniform(0, 6.28)
        mat = m["ticket%d" % rng.randrange(2)]
        x, z = sx, sz
        for k in range(n):
            a += rng.uniform(-1.3, 1.3)
            dx, dz = math.cos(a) * 0.5, math.sin(a) * 0.5
            nx, nz = -math.sin(a) * 0.14, math.cos(a) * 0.14
            y0 = FLOOR + 0.055 + (0.03 if k % 2 else 0.0)
            y1 = FLOOR + 0.055 + (0.0 if k % 2 else 0.03)
            mb.poly([_B(x - nx, y0, z - nz), _B(x + dx - nx, y1, z + dz - nz), _B(x + dx + nx, y1, z + dz + nz), _B(x + nx, y0, z + nz)],
                    mat, face=(0, 0, 1))
            x, z = x + dx, z + dz
    # scattered tokens
    for _ in range(40):
        x, z = rng.uniform(23177, 23207), rng.uniform(118, 223)
        mb.cyl(_B(x, FLOOR + 0.07, z), 0.18, 0.04, m["brass"], seg=8)
    return [_pool(mb, "ArcadeDressing", wn=False)]


# ================================================================ service (r8 A7)
SERV = (22624.1, 22877.9, 102.04, 237.94)          # interior wall faces (x0, x1, z0, z1)
SERV_CEIL = 46.8
RACK_LEVELS = (24.7, 28.1, 31.5, 34.9, 38.3)        # layout shelf bottoms (tops +0.28)


def _rack_units():
    units = {}
    for i, p in _parts(r"^Service/StorageShelf$"):
        lo, hi = _aabb(p)
        units[(round(lo[0], 2), round(lo[2], 2), round(hi[0], 2), round(hi[2], 2))] = True
    return sorted(units)


def _racks(m, rng):
    """Teardrop pallet racking, back-to-back: blue punched uprights, orange step beams at the layout shelf levels,
    wire decks with support channels, braced frames, row spacers and matching post/deck collision."""
    mb = RMesh("ServiceRacks")
    for x0, z0, x1, z1 in _rack_units():
        rows = ((z0, z0 + 7.4), (z1 - 7.4, z1))
        frames = [x0 + (x1 - x0) * k / 3 for k in range(4)]
        for rz0, rz1 in rows:
            for fi, fx in enumerate(frames):
                ux0 = min(max(fx - 0.2, x0), x1 - 0.4)
                for uz in (rz0, rz1 - 0.4):
                    mb.rbox((ux0, FLOOR, uz), (ux0 + 0.4, 42.0, uz + 0.4), m["rack_blue"], 0.03)
                    face_z = uz if uz == rz0 else uz + 0.4                  # punched hole strip on the aisle face
                    fz = face_z - 0.005 if uz == rz0 else face_z + 0.005
                    for k in range(29):                                      # individual teardrop punches
                        hy = 24.6 + k * 0.58
                        mb.poly([_B(ux0 + 0.14, hy, fz), _B(ux0 + 0.26, hy, fz),
                                 _B(ux0 + 0.29, hy + 0.12, fz), _B(ux0 + 0.25, hy + 0.23, fz),
                                 _B(ux0 + 0.15, hy + 0.23, fz), _B(ux0 + 0.11, hy + 0.12, fz)],
                                m["black"], face=(0, 1 if uz == rz0 else -1, 0))
                    mb.rbox((ux0 - 0.2, FLOOR, uz - 0.2), (ux0 + 0.6, FLOOR + 0.1, uz + 0.6), m["rack_blue"])
                    mb.rcol((ux0 - 0.02, FLOOR, uz - 0.02), (ux0 + 0.42, 42.0, uz + 0.42))
                    for ax in (ux0 - 0.1, ux0 + 0.5):
                        mb.cyl(_B(ax, FLOOR + 0.13, uz + 0.2), 0.06, 0.06, m["emt"], seg=6)
                # frame bracing between the front and back uprights
                xc = ux0 + 0.2
                ys = [24.9, 28.3, 31.7, 35.1, 38.5, 41.6]
                pts = []
                for k, y in enumerate(ys):
                    pts.append(_B(xc, y, rz0 + 0.4 if k % 2 == 0 else rz1 - 0.4))
                mb.tube(pts, 0.06, m["rack_blue"], seg=5)
                mb.tube([_B(xc, 24.9, rz0 + 0.4), _B(xc, 24.9, rz1 - 0.4)], 0.06, m["rack_blue"], seg=5)
                mb.tube([_B(xc, 41.6, rz0 + 0.4), _B(xc, 41.6, rz1 - 0.4)], 0.06, m["rack_blue"], seg=5)
            # beams + decks per bay and level
            for bx0, bx1 in zip(frames, frames[1:]):
                a, b = bx0 + 0.2, bx1 - 0.2
                for lv in RACK_LEVELS:
                    top = lv + 0.28
                    for bz in (rz0 - 0.06, rz1 - 0.26):
                        mb.rbox((a, top - 0.62, bz), (b, top, bz + 0.32), m["rack_orange"], 0.03)
                        for ex in (a, b - 0.25):
                            mb.rbox((ex, top - 0.8, bz - 0.025), (ex + 0.25, top + 0.1, bz + 0.345), m["rack_orange"])
                    # Galvanized welded mesh, with open cells rather than a solid shelf slab.
                    for k in range(18):
                        wx = a + 0.1 + (b - a - 0.2) * k / 17
                        mb.rbox((wx - 0.018, top - 0.05, rz0 + 0.26), (wx + 0.018, top - 0.015, rz1 - 0.26), m["deck"])
                    for k in range(12):
                        wz = rz0 + 0.3 + (rz1 - rz0 - 0.6) * k / 11
                        mb.rbox((a + 0.05, top - 0.075, wz - 0.018), (b - 0.05, top - 0.04, wz + 0.018), m["deck"])
                    mb.rcol((a, top - 0.62, rz0 - 0.06), (b, top, rz1 + 0.06))
                    for k in range(3):
                        cx = a + (b - a) * (k + 0.5) / 3
                        mb.rbox((cx - 0.1, top - 0.3, rz0 + 0.26), (cx + 0.1, top - 0.07, rz1 - 0.26), m["deck"])
        # row spacers across the flue
        for fx in frames:
            xc = min(max(fx, x0 + 0.2), x1 - 0.2)
            for y in (30.0, 37.0):
                mb.rbox((xc - 0.06, y - 0.1, z0 + 7.0), (xc + 0.06, y + 0.1, z1 - 7.0), m["steel"])
    return _pool(mb, "ServiceRacks", wn=False)


def _carton_meshes(m):
    """Four carton variants at unit size (1 x 1 x 1 studs, origin bottom centre); placements scale them."""
    out = []
    for v in range(4):
        a = RMesh("Carton%d" % v)
        crushed = v == 3
        if crushed:                                                          # dented sides and collapsed lid
            verts = [(-0.5, -0.5, 0), (0.5, -0.5, 0), (0.5, 0.5, 0), (-0.5, 0.5, 0),
                     (-0.5, -0.5, 1), (0.5, -0.5, 0.92), (0.37, 0.5, 0.8), (-0.5, 0.5, 0.9),
                     (0.12, 0.08, 0.68)]
            a.add_geo(verts, [(3, 2, 1, 0), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7),
                              (4, 5, 8), (5, 6, 8), (6, 7, 8), (7, 4, 8)], m["kraft_wet"])
            a.poly([(-0.5, -0.501, 0.0), (0.5, -0.501, 0.0), (0.5, -0.501, 0.35), (-0.5, -0.501, 0.28)], m["kraft_dk"], face=(0, -1, 0))
            a.poly([(-0.49, -0.5, 1.001), (-0.06, -0.5, 0.96), (0.08, -0.08, 0.76), (-0.4, 0.02, 0.85)], m["kraft_dk"], face=(0, 0, 1))
        else:
            a.box((0, 0, 0.5), (1, 1, 1), m["kraft"], 0.012, 1)
            a.box((0, 0, 1.001), (0.008, 1.0, 0.002), m["kraft_dk"])
            a.box((0, 0, 1.006), (0.085 if v != 2 else 0.13, 1.004, 0.01), m["tape"])
        for sy in (-1, 1):
            a.box((0, sy * 0.5, 0.8 if crushed and sy > 0 else 0.92 if crushed else 0.95),
                  (0.1, 0.012, 0.1), m["tape"])
        prints = (m["print_red"], m["print_blue"], m["print_orange"], m["print_red"])
        for sy in (-1, 1):                                                   # printed panels, front and back
            y = sy * 0.502
            a.poly([(-0.3, y, 0.35), (0.3, y, 0.35), (0.3, y, 0.7), (-0.3, y, 0.7)], prints[v], face=(0, sy, 0))
            a.poly([(-0.3, y * 1.001, 0.74), (0.3, y * 1.001, 0.74), (0.3, y * 1.001, 0.8), (-0.3, y * 1.001, 0.8)], m["black"], face=(0, sy, 0))
            label = ("POPCORN", "CUP LIDS", "COLA SYRUP", "POPCORN")[v]
            co, faces = _text_geo(label, 0.074, 0)
            Mprint = Matrix.Translation((0, sy * 0.504, 0.53)) @ Matrix.Rotation(math.pi if sy > 0 else 0, 4, "Z")
            a.add_geo(co, faces, m["label0"], Mprint)
            for k in range(11):                                               # printed shipping barcode
                a.box((-0.22 + k * 0.014, sy * 0.504, 0.22), (0.006 + (k % 3) * 0.002, 0.002, 0.065), m["black"])
            for sx in (-0.4, 0.4):                                            # this-way-up arrows
                a.poly([(sx - 0.025, y, 0.4), (sx + 0.025, y, 0.4), (sx + 0.025, y, 0.6),
                        (sx + 0.06, y, 0.6), (sx, y, 0.68), (sx - 0.06, y, 0.6), (sx - 0.025, y, 0.6)],
                       prints[v], face=(0, sy, 0))
        if v == 2:
            a.box((0.25, -0.505, 0.2), (0.16, 0.006, 0.14), m["label0"])
        elif v == 1:
            a.box((0, 0.48, 1.016), (0.7, 0.04, 0.02), m["kraft_dk"])
        for sx in (-1, 1):                                                   # hand slots
            x = sx * 0.502
            a.poly([(x, -0.18, 0.72), (x, 0.18, 0.72), (x, 0.18, 0.82), (x, -0.18, 0.82)], m["black"], face=(sx, 0, 0))
        out.append(a.finish(False))
    return out


def _cartons(m, rng):
    meshes = _carton_meshes(m)
    C3 = np.array(((1, 0, 0), (0, 0, -1), (0, 1, 0)), dtype=float)
    objs = []
    bodies = _parts(r"^Service/StockBox/Body$")
    crushed = set(rng.sample(range(len(bodies)), max(1, len(bodies) // 5)))
    for k, (i, p) in enumerate(bodies):
        R = _R(p)
        Rb = Matrix((C3 @ R @ C3.T).tolist())
        w, h, d = p["s"]
        up = Vector((R[0, 1], -R[2, 1], R[1, 1]))
        base = _rb(p["cf"][:3]) - up * (h / 2 * S)
        v = 3 if k in crushed else rng.randrange(3)
        M = Matrix.Translation(base) @ Rb.to_4x4() @ Matrix.Diagonal((w, d, h * (0.82 if v == 3 else 1.0), 1))
        lo, hi = _aabb(p)
        props = {"l4_role": "fixture", "l4_src": i}
        if lo[1] < FLOOR + 7.5:                                              # within reach: collide
            props["l4_col"] = json.dumps([[0.0, 0.0, 0.5 * S, S, S, S]])
        objs.append(_place(meshes[v], "StockBox%02d" % (k + 1), M, _nobake=True, **props))
    # collapsed wet cartons in a puddle by the west racks
    wet = RMesh("CollapsedCartons")
    for cx, cz, rot in ((22702.0, 150.5, 0.3), (22706.5, 153.0, -0.6)):
        with wet.at(Matrix.Translation(_B(cx, FLOOR, cz)) @ Matrix.Rotation(rot, 4, "Z")):
            # Saturated corrugated board folds sharply; it should not resemble a padded block.
            wet.add_geo([(-2.3,-1.9,0.04),(2.3,-1.9,0.04),(2.3,1.9,0.04),(-2.3,1.9,0.04),
                         (-2.3,-1.9,0.82),(2.2,-1.9,0.58),(1.7,1.9,0.92),(-2.15,1.9,0.67),(-0.4,-1.65,0.3)],
                        [(3,2,1,0),(0,1,5,8,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)], m["kraft_wet"])
            wet.poly([(-2.3,-1.9,0.83),(2.2,-1.9,0.59),(2.0,-0.65,0.28),(-0.5,-0.4,0.20),(-2.0,-0.6,0.36)],
                     m["kraft_dk"], face=(0,0,1))
            wet.poly([(-2.15,1.9,0.68),(1.7,1.9,0.93),(1.1,0.15,0.44),(0.6,-0.15,0.62),(-0.8,0.3,0.38),(-1.9,0.25,0.4)],
                     m["kraft_wet"], face=(0,0,1))
            wet.poly([(1.7,1.9,0.94),(2.2,-1.9,0.60),(3.0,-1.15,0.08),(2.9,-0.45,0.1),(3.2,0.15,0.09),(2.6,1.45,0.1)],
                     m["kraft"], face=(0,0,1))
            for z in (-1.88, 1.88):
                wet.tube([(-2.15,z,0.65),(-0.4,z,0.30),(2.1,z,0.58)], 0.012, m["kraft_dk"], seg=4)
            co, faces = _text_geo("POPCORN", 0.34, 0)
            wet.add_geo(co, faces, m["print_red"], Matrix.Translation((0,-1.905,0.24)))
            wet.poly([(-0.13,-1.89,0.8),(0.13,-1.89,0.8),(0.13,-0.7,0.30),(-0.13,-0.7,0.30)], m["tape"], face=(0,0,1))
            wet.poly([(-0.13,-0.7,0.31),(0.13,-0.7,0.31),(0.2,-0.25,0.75),(-0.1,-0.25,0.75)], m["tape"], face=(0,0,1))
        wet.rcol((cx - 2.6, FLOOR, cz - 2.4), (cx + 2.6, FLOOR + 1.3, cz + 2.4))
    wet.poly([_B(22704.0 + math.cos(t) * 5.5 * rng.uniform(0.8, 1.1), FLOOR + 0.06, 152.0 + math.sin(t) * 3.6 * rng.uniform(0.8, 1.1))
              for t in [2 * math.pi * k / 14 for k in range(14)]], m["water"], face=(0, 0, 1))
    objs.append(_pool(wet, "CollapsedCartons"))
    return objs


def _film_cans(m, rng):
    """Film-can stacks at the FilmTin spots; one open can from each of three stacks has spilled."""
    tins = [p for _, p in _parts(r"^Service/FilmTin$")]
    stacks = {}
    for p in tins:
        lo, hi = _aabb(p)
        key = (round((lo[0] + hi[0]) / 2), round((lo[2] + hi[2]) / 2))
        stacks.setdefault(key, []).append((lo, hi))
    keys = sorted(stacks)
    low = [k for k in keys if min(lo[1] for lo, hi in stacks[k]) < 31.0]
    spilled = set(rng.sample(low, min(3, len(low))))
    mb = RMesh("FilmCans")
    spill_positions = []

    def can(c, r, h, tilt=None):
        prof = [(0, 0), (r * 0.97, 0), (r, 0.06), (r, h * 0.55), (r * 1.03, h * 0.6), (r * 1.03, h), (r * 0.9, h), (0, h * 1.01)]
        M = Matrix.Translation(c) if tilt is None else tilt
        with mb.at(M):
            mb.lathe(prof, m["film_tin"], seg=10)
            mb.box((0, 0, h * 1.015), (r * 1.1, r * 0.65, 0.012), m["label0"])
            co, faces = _text_geo("REEL / RETURN", r * 0.11, 0)
            mb.add_geo(co, faces, m["black"], Matrix.Translation((0, 0, h * 1.03)) @ Matrix.Rotation(-math.pi / 2, 4, "X"))
    for key in keys:
        parts_ = sorted(stacks[key], key=lambda t: t[0][1])
        lo0, hi0 = parts_[0]
        r = (hi0[0] - lo0[0]) / 2
        h = hi0[1] - lo0[1]
        if key in spilled:
            for lo, hi in parts_[:-1]:
                can(_B(key[0], lo[1], key[1]), r, h)
            if len(parts_) > 1 and lo0[1] < FLOOR + 7.5:
                mb.rcol((key[0] - r, lo0[1], key[1] - r), (key[0] + r, parts_[-2][1][1], key[1] + r))
            fx, fz = key[0] + rng.uniform(-2, 2), key[1]
            unit = next((u for u in _rack_units() if u[0] <= key[0] <= u[2] and u[1] <= fz <= u[3]), None)
            side = -1 if fz < ((unit[1] + unit[3]) / 2 if unit else 170) else 1
            edge = (unit[1] if side < 0 else unit[3]) if unit else fz + side * 11.0
            cx, cz = fx, edge + side * (r + 1.25)
            spill_positions.append((cx, FLOOR, cz))
            with mb.at(Matrix.Translation(_B(cx, FLOOR, cz))):
                mb.lathe([(0, 0), (r, 0), (r, h), (r * 0.94, h), (r * 0.94, 0.12), (0, 0.12)], m["film_tin"], seg=16)
                mb.cyl((0, 0, h * 0.55), r * 0.86, h * 0.6, m["film"], seg=20)
                mb.cyl((0, 0, h * 0.9), r * 0.16, 0.08, m["emt"], seg=10)
                for k in range(4):
                    with mb.at(Matrix.Rotation(k * math.pi / 2, 4, "Z")):
                        mb.box((r * 0.48, 0, h * 0.91), (r * 0.58, r * 0.06, 0.04), m["film_tin"])
            mb.rcol((cx - r, FLOOR, cz - r), (cx + r, FLOOR + h, cz + r))
            # Detached lid leans against the can; film leads from the exposed reel to the floor.
            lid = Matrix.Translation(_B(cx + r * 1.6, FLOOR + r, cz)) @ Matrix.Rotation(1.2, 4, "Y")
            with mb.at(lid):
                mb.lathe([(0, 0), (r, 0), (r * 1.03, 0.06), (r * 1.03, 0.14), (0, 0.14)], m["film_tin"], seg=16)
            mb.rcol((cx + r * 1.1, FLOOR, cz - r), (cx + r * 2.1, FLOOR + 2 * r, cz + r))
            # unspooled film: a flat wavy ribbon snaking away from the open can
            x, z, a = cx, cz + side * r, rng.uniform(0, 6.28)
            pts = [(x, z)]
            for k in range(26):
                a += rng.uniform(-0.7, 0.7)
                x, z = x + math.cos(a) * 0.9, z + math.sin(a) * 0.9
                pts.append((x, z))
            for (xa, za), (xb, zb) in zip(pts, pts[1:]):
                dx, dz = xb - xa, zb - za
                L = math.hypot(dx, dz) or 1
                nx, nz = -dz / L * 0.17, dx / L * 0.17
                y = FLOOR + 0.05
                q = lambda t, w: _B(xa + dx * t + nx * w, y, za + dz * t + nz * w)
                mb.poly([q(0, -0.64), q(1, -0.64), q(1, 0.64), q(0, 0.64)], m["film"], face=(0, 0, 1))
                for sg in (-1, 1):                                           # actual sprocket apertures
                    mb.poly([q(0, sg * 0.92), q(1, sg * 0.92), q(1, sg), q(0, sg)], m["film"], face=(0, 0, 1))
                    for ta, tb in ((0, 0.2), (0.4, 0.6), (0.8, 1)):
                        mb.poly([q(ta, sg * 0.64), q(tb, sg * 0.64), q(tb, sg * 0.92), q(ta, sg * 0.92)],
                                m["film"], face=(0, 0, 1))
            continue
        for lo, hi in parts_:
            can(_B(key[0], lo[1], key[1]), r, h)
        top = max(hi[1] for lo, hi in parts_)
        if lo0[1] < FLOOR + 7.5:
            mb.rcol((key[0] - r, lo0[1], key[1] - r), (key[0] + r, top, key[1] + r))
    return _pool(mb, "FilmCans", wn=False, l4_spills=json.dumps(spill_positions))


def _workbench(m, rng):
    """Steel workbench (x 22796-22840, z 225-237.7): top, frame, lower shelf, pegboard with tools, vice, task lamp."""
    mb = RMesh("Workbench")
    X0, X1, Z0, Z1, YT = 22796.0, 22840.0, 225.0, 237.7, 27.95
    mb.rbox((X0, 27.5, Z0), (X1, YT, Z1), m["bench_top"], 0.05, 1)
    mb.rbox((X0 - 0.05, 27.3, Z0 - 0.05), (X1 + 0.05, 27.55, Z0 + 0.25), m["steel"], 0.02)
    for x in (X0 + 0.6, (X0 + X1) / 2, X1 - 0.6):
        for z in (Z0 + 0.6, Z1 - 0.6):
            mb.rbox((x - 0.25, FLOOR, z - 0.25), (x + 0.25, 27.5, z + 0.25), m["steel_grey"], 0.03)
            mb.rbox((x - 0.35, FLOOR, z - 0.35), (x + 0.35, FLOOR + 0.12, z + 0.35), m["steel_grey"])
    mb.rbox((X0 + 0.4, 24.7, Z0 + 0.4), (X1 - 0.4, 24.98, Z1 - 0.4), m["steel_grey"], 0.02)
    for k in range(4):                                                  # boxes / a toolbox on the lower shelf
        x = X0 + 3 + k * 10 + rng.uniform(-1, 1)
        mb.rbox((x, 24.98, 229.0), (x + rng.uniform(2.5, 4), 24.98 + rng.uniform(1.0, 2.0), 234.0), m["kraft"] if k % 2 else m["toolbox"], 0.05)
    mb.rcol((X0, FLOOR, Z0), (X1, YT, Z1))
    # pegboard on the wall with hanging tools
    wz = SERV[3] - 0.02
    mb.rbox((X0 + 1, YT + 0.2, wz - 0.12), (X1 - 1, 36.5, wz), m["pegboard"])
    mb.rbox((X0 + 0.8, YT + 0.1, wz - 0.15), (X1 - 0.8, YT + 0.3, wz), m["steel"])
    for ix in range(56):
        for iy in range(10):
            mb.cyl(_B(X0 + 1.6 + ix * 0.72, YT + 0.55 + iy * 0.72, wz - 0.125),
                   0.055, 0.008, m["black"], axis="Y", seg=6)
    for k in range(9):
        x = X0 + 3 + k * 4.4
        y = rng.uniform(30.0, 33.5)
        kind = k % 3
        if kind == 0:                                                   # wrench
            mb.rbox((x - 0.08, y - 1.2, wz - 0.18), (x + 0.08, y + 0.6, wz - 0.12), m["chrome"])
            mb.cyl(_B(x, y + 0.75, wz - 0.15), 0.28, 0.06, m["chrome"], axis="Y", seg=8)
        elif kind == 1:                                                 # hammer
            mb.cyl(_B(x, y - 0.4, wz - 0.2), 0.1, 2.0, m["wood"], seg=6)
            mb.rbox((x - 0.5, y + 0.55, wz - 0.3), (x + 0.5, y + 0.85, wz - 0.1), m["steel"], 0.03)
        else:                                                           # saw
            mb.poly([_B(x - 0.4, y + 0.6, wz - 0.16), _B(x + 0.4, y + 0.6, wz - 0.16), _B(x + 0.25, y - 2.0, wz - 0.16), _B(x - 0.1, y - 2.0, wz - 0.16)],
                    m["chrome"], face=(0, 1, 0))
            mb.rbox((x - 0.45, y + 0.5, wz - 0.22), (x + 0.45, y + 1.2, wz - 0.1), m["red_dk"], 0.05)
        mb.cyl(_B(x, y + 1.3, wz - 0.3), 0.04, 0.4, m["steel"], axis="Y", seg=5)       # peg hook
    # Wall shelf with brackets and its own collision (the old slab is superseded).
    mb.rbox((X0, 34.2, 229.0), (X1, 34.5, Z1), m["steel_grey"], 0.02)
    mb.rcol((X0, 34.2, 229.0), (X1, 34.5, Z1))
    for x in (X0 + 2, (X0 + X1) / 2, X1 - 2):
        mb.poly([_B(x, 34.2, wz), _B(x, 34.2, 230.0), _B(x, 32.2, wz)], m["steel_grey"], face=(1, 0, 0))
    for k in (1, 3):                                                    # boxes; labelled jugs built by _service_supplies
        x = X0 + 4 + k * 8.5
        mb.rbox((x, 34.5, 231.0), (x + 3.0, 34.5 + rng.uniform(1.5, 2.5), 235.0), m["kraft"], 0.05)
    # bench vice (front-left) + clutter
    vx, vz = X0 + 2.5, Z0 + 0.8
    mb.rbox((vx - 0.9, YT, vz - 0.6), (vx + 0.9, YT + 0.5, vz + 1.2), m["vice"], 0.06)
    mb.rbox((vx - 0.7, YT + 0.5, vz - 0.7), (vx + 0.7, YT + 1.5, vz - 0.2), m["vice"], 0.05)
    mb.rbox((vx - 0.7, YT + 0.5, vz + 0.3), (vx + 0.7, YT + 1.5, vz + 0.8), m["vice"], 0.05)
    mb.cyl(_B(vx, YT + 0.9, vz - 1.1), 0.1, 1.0, m["chrome"], axis="Y", seg=10)
    mb.cyl(_B(vx, YT + 0.9, vz - 1.6), 0.06, 1.8, m["chrome"], axis="X", seg=6)
    for zz in (vz - 0.19, vz + 0.29):
        mb.rbox((vx - 0.65, YT + 1.15, zz), (vx + 0.65, YT + 1.45, zz + 0.035), m["chrome"])
    mb.rcol((vx - 0.9, YT, vz - 1.7), (vx + 0.9, YT + 1.5, vz + 1.2))
    mb.cyl(_B(22815.0, YT + 0.45, 228.0), 0.35, 0.9, m["cup"], seg=10)                # coffee mug
    mb.rbox((22820.0, YT, 229.0), (22822.4, YT + 0.08, 232.2), m["notice"])             # clipboard
    mb.cyl(_B(22826.0, YT + 0.12, 227.5), 0.08, 1.6, m["red_dk"], axis="X", seg=6)       # screwdriver
    # articulated task lamp clamped at the back left, shade over the bench
    lx, lz = X0 + 5.0, Z1 - 1.0
    mb.cyl(_B(lx, YT + 0.2, lz), 0.5, 0.4, m["black"], seg=12)
    mb.tube([_B(lx, YT + 0.4, lz), _B(lx, YT + 3.4, lz - 1.8), _B(lx + 1.2, YT + 4.6, lz - 4.6)], 0.07, m["black"], seg=6)
    shade = _B(lx + 1.5, YT + 4.3, lz - 5.4)
    prof = [(0.15, 0.6), (0.3, 0.55), (0.9, 0.0), (0.95, -0.05)]
    mb.lathe(prof, m["lamp_green"], seg=14, c=shade)
    mb.lathe([(r * 0.98, z - 0.02) for r, z in reversed(prof)], m["lamp_green"], seg=14, c=shade)
    mb.sphere(shade + Vector((0, 0, 0.12)), 0.28, m["warm"], seg=8, rings=4)
    objs = [_pool(mb, "Workbench", wn=False)]
    _light("WorkbenchLamp", (lx + 1.5, YT + 4.2, lz - 5.4), (255, 214, 155), 20, 1.1, kind="SPOT", shadows=True, spot=80)
    return objs


def _panels(m, rng):
    """Grey breaker panels with EMT conduit runs to the ceiling, warning placards, a disconnect box."""
    mb = RMesh("ServicePanels")
    for (x0, x1, wz, face, conduits) in ((22785.0, 22796.0, SERV[2], 1, (22788.2, 22793.2)),
                                         (22736.0, 22747.0, SERV[3], -1, (22739.2, 22744.2))):
        d = 1.3
        z_out = wz + face * d
        lo, hi = (x0, 31.0, min(wz, z_out)), (x1, 41.0, max(wz, z_out))
        mb.rbox(lo, hi, m["panel_grey"], 0.06, 1)
        # door, slightly ajar on the north panel (hinge on the west edge)
        dz = z_out + face * 0.08
        ang = 0.45 if face > 0 else 0.0
        piv = _B(x0 + 0.3, 36.0, dz)
        # dead front with two columns of breakers (seen through the ajar door)
        zi = z_out + face * 0.01
        mb.rbox((x0 + 0.6, 31.6, min(zi, zi - face * 0.3)), (x1 - 0.6, 40.4, max(zi, zi - face * 0.3)), m["steel_grey"])
        for col in range(2):
            for row in range(9):
                bx0 = x0 + 2.2 + col * 3.6
                by0 = 32.4 + row * 0.85
                mb.rbox((bx0, by0, min(zi, zi + face * 0.12)), (bx0 + 2.6, by0 + 0.6, max(zi, zi + face * 0.12)), m["black"])
                mb.rbox((bx0 + 1.15, by0 + 0.15, min(zi, zi + face * 0.2)), (bx0 + 1.45, by0 + 0.45, max(zi, zi + face * 0.2)),
                        m["label0"] if (row + col) % 4 else m["red_dk"])
        with mb.at(Matrix.Translation(piv) @ Matrix.Rotation(-ang * face, 4, "Z") @ Matrix.Translation(-piv)):
            mb.rbox((x0 + 0.3, 31.4, dz - 0.07), (x1 - 0.3, 40.6, dz + 0.07), m["panel_grey"], 0.04)
            mb.rbox((x1 - 1.1, 35.3, dz + face * 0.06 - 0.06), (x1 - 0.8, 36.3, dz + face * 0.06 + 0.06), m["chrome"], 0.03)
            yz = dz + face * 0.08                                            # warning placard
            mb.poly([_B(x0 + 1.4, 33.0, yz), _B(x0 + 4.4, 33.0, yz), _B(x0 + 4.4, 34.6, yz), _B(x0 + 1.4, 34.6, yz)], m["placard"], face=(0, -face, 0))
            co, faces = _text_geo("DANGER", 0.40, 0)
            txt = Matrix.Translation(_B(x0 + 2.9, 34.08, yz + face * 0.006)) @ _yaw((0, -face)).to_4x4()
            mb.add_geo(co, faces, m["black"], txt)
            co, faces = _text_geo("HIGH VOLTAGE", 0.21, 0)
            txt = Matrix.Translation(_B(x0 + 2.9, 33.67, yz + face * 0.006)) @ _yaw((0, -face)).to_4x4()
            mb.add_geo(co, faces, m["black"], txt)
            for k in range(4):
                xa = x0 + 1.5 + k * 0.75
                mb.poly([_B(xa, 33.05, yz + face * 0.002), _B(xa + 0.3, 33.05, yz + face * 0.002), _B(xa + 0.55, 33.3, yz + face * 0.002), _B(xa + 0.25, 33.3, yz + face * 0.002)],
                        m["black"], face=(0, -face, 0))
        za, zb = sorted((wz, z_out + face * 0.3))
        mb.rcol((x0, 31.0, za), (x1, 41.0, zb))
        # EMT conduit: up from the panel top with an offset bend, couplings, straps
        for cx in conduits:
            cz = wz + face * 0.5
            path = [_B(cx, 41.0, cz), _B(cx, 43.2, cz), _B(cx + 0.9, 44.2, cz), _B(cx + 0.9, SERV_CEIL, cz)]
            mb.tube(_fillet(path, 0.5, 3), 0.18, m["emt"], seg=8)
            for y in (42.2, 45.4):
                xx = cx if y < 43 else cx + 0.9
                mb.cyl(_B(xx, y, cz), 0.23, 0.3, m["emt"], seg=8)
                za, zb = sorted((wz, cz + face * 0.25))
                mb.rbox((xx - 0.3, y + 0.2, za), (xx + 0.3, y + 0.35, zb), m["steel"])
        # disconnect box beside the panel with its own conduit
        bx = x1 + 1.2
        mb.rbox((bx, 33.0, min(wz, wz + face * 0.9)), (bx + 2.2, 36.4, max(wz, wz + face * 0.9)), m["panel_grey"], 0.05)
        mb.rbox((bx + 2.2, 34.2, min(wz, wz + face * 0.5)), (bx + 2.5, 35.2, max(wz, wz + face * 0.5)), m["red_dk"], 0.03)
        mb.tube([_B(bx + 1.1, 36.4, wz + face * 0.45), _B(bx + 1.1, SERV_CEIL, wz + face * 0.45)], 0.14, m["emt"], seg=8)
        mb.rcol((bx, 33.0, min(wz, wz + face * 0.9)), (bx + 2.5, 36.4, max(wz, wz + face * 0.9)))
    return _pool(mb, "ServicePanels", wn=False)


BULKHEADS = [  # x, y, z, facing (Blender dir of the wall normal into the room), state
    (22864.0, 38.6, SERV[2], (0, -1), "lit"), (22716.0, 38.0, SERV[2], (0, -1), "lit"),
    (22700.0, 38.0, SERV[3], (0, 1), "lit"), (22770.0, 38.0, SERV[3], (0, 1), "lit"),
    (SERV[0], 38.0, 200.0, (1, 0), "flicker"), (SERV[1], 38.0, 172.0, (-1, 0), "dead"),
]


def _bulkhead(mb, m, x, y, z, f, lens_mat, lens_mb=None):
    """Caged bulkhead: cast base, glass dome, four cage ribs and a ring. f = Blender (x, y) wall normal."""
    nrm = Vector((f[0], f[1], 0))
    R = Matrix.Rotation(math.atan2(-nrm.x, nrm.y), 3, "Z")            # local +Y -> out of the wall
    M = Matrix.Translation(_B(x, y, z)) @ R.to_4x4() @ Matrix.Rotation(-math.pi / 2, 4, "X")   # local +Z = out
    with mb.at(M):
        mb.lathe([(0, 0), (0.95, 0), (0.95, 0.15), (0.8, 0.35), (0, 0.36)], m["bulk_body"], seg=14)
        for k in range(4):
            a = k * math.pi / 2 + math.pi / 4
            pts = [(0.72 * math.cos(a) * math.cos(t), 0.72 * math.sin(a) * math.cos(t), 0.36 + 0.72 * math.sin(t)) for t in [math.pi / 2 * j / 5 for j in range(6)]]
            mb.tube(pts, 0.035, m["bulk_body"], seg=4, caps=False)
        mb.tube([(0.72 * math.cos(t), 0.72 * math.sin(t), 0.5) for t in [2 * math.pi * j / 14 for j in range(15)]], 0.035, m["bulk_body"], seg=4, caps=False)
    tgt = lens_mb or mb
    with tgt.at(M):
        tgt.lathe([(0.6, 0.36), (0.58, 0.6), (0.45, 0.85), (0.2, 0.98), (0, 1.0)], lens_mat, seg=12)


def _bulkheads(m, rng):
    mb = RMesh("Bulkheads")
    objs = []
    for i, (x, y, z, f, state) in enumerate(BULKHEADS):
        lens_mat = m["frost"] if state == "dead" else m["sickly"]
        if state == "flicker":
            lens = RMesh("BulkheadFlickerLens")
            _bulkhead(mb, m, x, y, z, f, lens_mat, lens)
            off = _B(x, y, z) + Vector((f[0], f[1], 0)) * 1.5
            _flicker(lens, "Bulkhead_Flicker", (211, 235, 162), 20, 0.45, (off.x + OX, off.z, -off.y))
        else:
            _bulkhead(mb, m, x, y, z, f, lens_mat)
            if state == "lit":
                off = _B(x, y, z) + Vector((f[0], f[1], 0)) * 1.5
                _light("Bulkhead%d" % i, (off.x + OX, off.z, -off.y), (211, 235, 162), 22, 0.5, energy_k=0.3)
    objs.append(_pool(mb, "Bulkheads", wn=False))
    return objs


def _janitor(m, rng):
    """Yellow janitor cart with mop bucket, wringer and mop, a tipped bucket in a puddle, a wet-floor sign."""
    mb = RMesh("Janitor")
    cx, cz = 22695.0, 123.0
    with mb.at(Matrix.Translation(_B(cx, FLOOR, cz))):
        L, W = 4.4, 2.2
        mb.box((0, 0, 0.55), (L, W, 0.2), m["cart_yellow"], 0.06, 1)                # chassis
        mb.box((0, 0, 2.3), (L, W, 0.14), m["cart_yellow"], 0.05, 1)                # top shelf
        mb.box((-L / 2 + 0.15, 0, 1.4), (0.2, W, 1.8), m["cart_yellow"], 0.04)      # end panel
        for sx in (-1, 1):
            for sy in (-1, 1):
                mb.cyl((sx * (L / 2 - 0.4), sy * (W / 2 - 0.25), 0.22), 0.22, 0.14, m["black"], axis="Y", seg=10)
        mb.tube([(L / 2 - 0.1, -W / 2, 2.3), (L / 2 + 0.2, -W / 2, 3.6), (L / 2 + 0.2, W / 2, 3.6), (L / 2 - 0.1, W / 2, 2.3)], 0.07, m["steel_grey"], seg=6)
        # hanging vinyl bag
        mb.lathe([(0, 0.8), (0.85, 0.9), (1.0, 1.8), (1.05, 2.25), (0, 2.25)], m["bag"], seg=12, c=(0.6, 0, 0))
        # spray bottles + rolls on the top shelf
        for k in range(3):
            mb.cyl((-1.4 + k * 0.6, 0.4, 2.8), 0.22, 0.9, m["jug"], seg=8)
            mb.cyl((-1.4 + k * 0.6, 0.4, 3.35), 0.1, 0.25, m["red_dk"], seg=6)
        mb.cyl((-0.2, -0.4, 2.65), 0.4, 0.55, m["paper"], seg=10)
    # mop bucket with wringer beside the cart + the mop
    bx, bz = cx - 3.6, cz + 0.2
    with mb.at(Matrix.Translation(_B(bx, FLOOR, bz))):
        mb.lathe([(0, 0.25), (1.0, 0.25), (1.15, 1.9), (1.2, 2.0), (1.08, 2.0), (0.93, 0.4), (0, 0.4)],
                 m["cart_yellow"], seg=16, sx=1.25)
        mb.cyl((0, 0, 1.75), 1.05, 0.02, m["water"], seg=14)
        for sx in (-1, 1):
            for sy in (-1, 1):
                mb.cyl((sx * 0.9, sy * 0.7, 0.15), 0.15, 0.12, m["black"], axis="Y", seg=8)
        mb.box((0.55, 0, 2.3), (0.9, 1.6, 0.9), m["steel_grey"], 0.08, 1)             # wringer
        mb.box((0.55, 0, 2.76), (0.65, 1.3, 0.025), m["black"])
        for k in range(6):
            mb.box((0.04, -0.6 + 0.24 * k, 2.32), (0.02, 0.09, 0.5), m["black"])
        mb.tube([(0.9, 0, 2.6), (1.6, 0, 3.6), (1.7, 0, 4.4)], 0.07, m["steel_grey"], seg=6)
        mb.tube([(0.3, 0.1, 0.7), (0.0, 0.25, 7.0)], 0.08, m["wood"], seg=6)             # mop handle
        mb.lathe([(0, 0.35), (0.55, 0.4), (0.45, 1.3), (0, 1.4)], m["mop"], seg=10, c=(0.25, 0.1, 0.0))
        for k in range(14):
            a = k * 2 * math.pi / 14
            mb.tube([(0.25, 0.1, 1.1), (0.25 + 0.45 * math.cos(a), 0.1 + 0.45 * math.sin(a), 0.6),
                     (0.25 + 0.55 * math.cos(a), 0.1 + 0.55 * math.sin(a), 0.36)], 0.045, m["mop"], seg=4)
    mb.rcol((cx - 2.3, FLOOR, cz - 1.2), (cx + 2.5, FLOOR + 3.7, cz + 1.2))
    mb.rcol((bx - 1.5, FLOOR, bz - 1.2), (bx + 1.5, FLOOR + 2.4, bz + 1.2))
    # a second bucket on its side with a puddle
    tx, tz = 22704.0, 115.5
    with mb.at(Matrix.Translation(_B(tx, FLOOR + 1.1, tz)) @ Matrix.Rotation(0.7, 4, "Z") @ Matrix.Rotation(math.pi / 2, 4, "Y") @ Matrix.Translation((0, 0, -1.0))):
        mb.lathe([(0, 0.25), (1.0, 0.25), (1.15, 1.9), (1.2, 2.0), (0.9, 2.0)], m["cart_yellow"], seg=14, sx=1.1)
    mb.poly([_B(tx + 2.5 + math.cos(t) * 4.2 * rng.uniform(0.7, 1.1), FLOOR + 0.06, tz + math.sin(t) * 3.0 * rng.uniform(0.7, 1.1))
             for t in [2 * math.pi * k / 14 for k in range(14)]], m["water"], face=(0, 0, 1))
    mb.rcol((tx - 1.3, FLOOR, tz - 1.3), (tx + 1.3, FLOOR + 2.3, tz + 1.3))
    # Industrial wet-floor cone with weighted square base and reflective collar.
    sx_, sz_ = 22701.0, 126.5
    with mb.at(Matrix.Translation(_B(sx_, FLOOR, sz_)) @ Matrix.Rotation(0.4, 4, "Z")):
        mb.box((0, 0, 0.12), (2.2, 2.2, 0.24), m["rubber"], 0.08)
        mb.lathe([(0, 0.24), (0.95, 0.24), (0.17, 3.5), (0.12, 3.5), (0.12, 3.3)], m["cart_yellow"], seg=20)
        mb.lathe([(0.46, 2.28), (0.38, 2.62)], m["paper"], seg=20)
        for label, h in (("WET", 1.65), ("FLOOR", 1.32)):
            co, faces = _text_geo(label, 0.28, 0)
            mb.add_geo(co, faces, m["black"], Matrix.Translation((0, -0.95 + (h - 0.24) * 0.24 - 0.015, h)))
    mb.rcol((sx_ - 1.4, FLOOR, sz_ - 1.4), (sx_ + 1.4, FLOOR + 3.5, sz_ + 1.4))
    return [_pool(mb, "Janitor", wn=False)]


def _service_supplies(m, rng):
    """Nested printed tub sleeves, handled HDPE chemical jugs and paper one-sheets in open storage bins."""
    mb = RMesh("ServiceSupplies")
    letters = {s: _text_geo(s, size, 0.0) for s, size in
               (("POP\nCORN", 0.25), ("CLEANER", 0.15), ("DEGREASER", 0.12), ("FLOOR WAX", 0.13), ("ONE SHEETS", 0.25))}
    for i, p in _parts(r"^Service/PopcornTub$"):
        lo, hi = _aabb(p)
        x, z, y = p["cf"][0], p["cf"][2], lo[1]
        with mb.at(Matrix.Translation(_B(x, y, z))):
            # A sleeve of nested tapered paper tubs: lip rings, open top, red printed stripes.
            mb.lathe([(0, 0), (0.96, 0), (1.13, 1.7), (1.20, 2.5), (1.13, 2.5), (1.04, 2.0), (0, 2.0)], m["cup"], seg=20)
            for k in range(9):
                h = 1.55 + k * 0.12
                r = 1.12 + k * 0.01
                mb.lathe([(r - 0.04, h), (r + 0.035, h), (r + 0.045, h + 0.035), (r - 0.02, h + 0.06)], m["paper"], seg=20)
            for k in range(10):
                a, b = 2 * math.pi * k / 10, 2 * math.pi * (k + 0.42) / 10
                mb.poly([(0.975 * math.cos(a), 0.975 * math.sin(a), 0.10),
                         (0.975 * math.cos(b), 0.975 * math.sin(b), 0.10),
                         (1.122 * math.cos(b), 1.122 * math.sin(b), 1.56),
                         (1.122 * math.cos(a), 1.122 * math.sin(a), 1.56)], m["print_red"])
            mb.box((0, -1.115, 0.93), (1.05, 0.015, 0.72), m["cup"])
            vs, fs = letters["POP\nCORN"]
            mb.add_geo(vs, fs, m["print_red"], Matrix.Translation((0, -1.13, 0.93)))
        if lo[1] < FLOOR + 7.5:
            mb.rcol((x - 1.25, y, z - 1.25), (x + 1.25, y + 2.55, z + 1.25))
    for k, (i, p) in enumerate(_parts(r"^Service/CleaningBottle$")):
        lo, hi = _aabb(p)
        x, z, y = p["cf"][0], p["cf"][2], lo[1]
        front = 1 if z > 170 else -1
        R = Matrix.Rotation(0 if front < 0 else math.pi, 4, "Z")
        with mb.at(Matrix.Translation(_B(x, y, z)) @ R):
            # Rounded HDPE body, sloped shoulder, offset neck, hollow handle and ribbed screw cap.
            mb.box((0, 0, 0.76), (1.50, 1.05, 1.52), m["jug"], 0.12, 2)
            mb.add_geo([(-0.68,-0.48,1.40),(0.68,-0.48,1.40),(0.68,0.48,1.40),(-0.68,0.48,1.40),
                        (-0.30,-0.28,1.78),(0.60,-0.28,1.78),(0.60,0.28,1.78),(-0.30,0.28,1.78)],
                       [(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7),(4,5,6,7)], m["jug"])
            mb.cyl((0.38, 0, 1.88), 0.26, 0.23, m["jug"], seg=12)
            mb.cyl((0.38, 0, 2.02), 0.30, 0.18, m["red_dk"] if k % 3 == 0 else m["print_blue"], seg=12)
            for h in (1.96, 2.00, 2.04, 2.08):
                mb.cyl((0.38, 0, h), 0.305, 0.018, m["black"], seg=12, caps=False)
            mb.tube(_fillet([(-0.60,0,1.42),(-0.70,0,1.82),(-0.48,0,1.96),(-0.03,0,1.94),(-0.02,0,1.69)], 0.12, 3),
                    0.085, m["jug"], seg=6)
            mb.box((0, -0.537, 0.87), (1.1, 0.01, 0.87), m["paper"])
            mb.box((0, -0.548, 1.15), (1.08, 0.012, 0.18), (m["print_blue"],m["print_orange"],m["print_red"])[k % 3])
            vs, fs = letters[("CLEANER", "DEGREASER", "FLOOR WAX")[k % 3]]
            mb.add_geo(vs, fs, m["black"], Matrix.Translation((0, -0.554, 0.94)))
            mb.poly([(-0.2,-0.558,0.54),(0,-0.558,0.74),(0.2,-0.558,0.54),(0,-0.558,0.34)], m["print_red"], face=(0,-1,0))
            mb.box((0,-0.563,0.53), (0.025,0.005,0.14), m["black"])
            mb.box((0,-0.563,0.42), (0.025,0.005,0.025), m["black"])
        if lo[1] < FLOOR + 7.5:
            mb.rcol((x - 0.82, y, z - 0.6), (x + 0.82, y + 2.12, z + 0.6))
    groups = {}
    for i, p in _parts(r"^Service/PosterRoll$"):
        groups.setdefault((round(p["cf"][0], 2), round(p["cf"][1], 2)), []).append(p)
    bins = []
    for key, group in sorted(groups.items()):
        cluster = []
        for p in sorted(group, key=lambda p: p["cf"][2]):
            if cluster and p["cf"][2] - cluster[-1]["cf"][2] > 3.0:
                bins.append((key, cluster))
                cluster = []
            cluster.append(p)
        bins.append((key, cluster))
    for k, ((x, yc), group) in enumerate(bins):
        z0 = min(p["cf"][2] for p in group) - 0.62
        z1 = max(p["cf"][2] for p in group) + 0.62
        y = yc - 0.50
        # An open kraft bin, with each one-sheet still horizontal at its measured location.
        mb.rbox((x-3.1,y-0.05,z0-0.10),(x+3.1,y+0.08,z1+0.10),m["kraft"],0.03)
        for zz in (z0-0.10,z1):
            mb.rbox((x-3.1,y,zz),(x+3.1,y+0.64,zz+0.10),m["kraft"],0.025)
        for xx in (x-3.1,x+3.0):
            mb.rbox((xx,y,z0),(xx+0.10,y+0.64,z1),m["kraft"],0.025)
        for j, p in enumerate(group):
            cz = p["cf"][2]
            with mb.at(Matrix.Translation(_B(x-2.75,y+0.53,cz)) @ Matrix.Rotation(math.pi/2,4,"Y")):
                mb.lathe([(0.43,0),(0.43,5.5),(0.12,5.5),(0.12,0),(0.43,0)],m["paper"],seg=14)
                for h in (0.8,4.7):
                    mb.lathe([(0.432,h),(0.445,h),(0.445,h+0.10),(0.432,h+0.10)],m["kraft_dk"],seg=14)
                # Coloured edge of the print and rolled paper rings on the exposed ends.
                mb.lathe([(0.44,0.005),(0.36,0.005)],(m["print_blue"],m["print_red"],m["print_orange"])[j % 3],seg=14)
                for rr in (0.16,0.22,0.28,0.34,0.40):
                    mb.lathe([(rr,5.505),(rr+0.012,5.505)],m["kraft"],seg=14)
        vs, fs = letters["ONE SHEETS"]
        mb.add_geo(vs,fs,m["black"],Matrix.Translation(_B(x,y+0.34,z1+0.102)))
        if y < FLOOR + 7.5:
            mb.rcol((x-3.1,y-0.05,z0-0.1),(x+3.1,y+1.0,z1+0.1))
    # Steel chemical staging table: same footprint, top height and lower shelf as the original cleaning table.
    for i, p in _parts(r"^Service/ServiceCleaningTop$"):
        lo, hi = _aabb(p)
        mb.rbox(tuple(lo),tuple(hi),m["steel_lt"],0.05)
        mb.rbox((lo[0],lo[1]-0.45,lo[2]),(hi[0],lo[1],lo[2]+0.16),m["steel_grey"],0.025)
        mb.rcol((lo[0],FLOOR,lo[2]),tuple(hi))
    for i, p in _parts(r"^Service/ServiceCleaning(Leg|Shelf)$"):
        lo, hi = _aabb(p)
        mb.rbox(tuple(lo),tuple(hi),m["steel_grey"],0.04)
    return _pool(mb,"ServiceSupplies",wn=False)


def _extinguisher_cabinets(m):
    """Wall cabinets wrap the retained original extinguisher assets; brackets become cabinet backing/mounts."""
    mb = RMesh("ExtinguisherCabinets")
    letters = _text_geo("FIRE",0.48,0.0)
    for i, p in _parts(r"^Service/(North|South)ServiceExtinguisher$"):
        x, z = p["cf"][0], p["cf"][2]
        north = z < 170
        wall, face = (SERV[2], 1) if north else (SERV[3], -1)
        y0, w, h, d = 26.7, 3.6, 5.6, 3.4
        R = _yaw((0,-face)).to_4x4()
        with mb.at(Matrix.Translation(_B(x,y0,wall)) @ R):
            mb.box((0,-0.08,h/2),(w,0.16,h),m["panel_grey"],0.04)
            for xx in (-w/2+0.08,w/2-0.08):
                mb.box((xx,-d/2,h/2),(0.16,d,h),m["panel_grey"],0.04)
            for hh in (0.08,h-0.08):
                mb.box((0,-d/2,hh),(w,d,0.16),m["panel_grey"],0.04)
            # Cabinet has a glazed, red-edged door and retaining strap behind the existing bottle.
            mb.box((0,-d+0.08,h/2),(w-0.26,0.04,h-0.30),m["glass_dk"])
            for xx in (-w/2+0.16,w/2-0.16):
                mb.box((xx,-d,h/2),(0.25,0.16,h-0.15),m["red_dk"],0.025)
            for hh in (0.16,h-0.16):
                mb.box((0,-d,hh),(w-0.2,0.16,0.25),m["red_dk"],0.025)
            mb.box((0,-1.1,2.1),(1.5,0.1,0.18),m["steel_grey"],0.02)
            mb.box((1.25,-d-0.08,h/2),(0.12,0.1,0.60),m["chrome"],0.02)
            for hh in (0.8,h-0.8):
                mb.cyl((-w/2+0.16,-d-0.05,hh),0.09,0.45,m["chrome"],seg=8)
            mb.box((0,-0.1,h+0.92),(3.1,0.10,1.25),m["red_enamel"],0.025)
            vs,fs=letters
            mb.add_geo(vs,fs,m["paper"],Matrix.Translation((0,-0.157,h+0.92)))
            mb.poly([(-0.28,-0.159,h+0.45),(0.28,-0.159,h+0.45),(0,-0.159,h+0.18)],m["paper"],face=(0,-1,0))
        za, zb = sorted((wall,wall+face*(d+0.15)))
        mb.rcol((x-w/2,y0,za),(x+w/2,y0+h,zb))
    return _pool(mb,"ExtinguisherCabinets",wn=False)



def _room_wallpaper(m):
    mb = RMesh("RoomWallpaper")
    for _, p in _parts(r"^Service/Service(North|South|East|West)WallFinish$|^Restrooms/(Men|Women)_(Back)?UpperPlaster$"):
        lo, hi = _aabb(p)
        if p["p"].startswith("Restrooms/"):
            # White wainscot ends at 31.5; replacing the old stripe with paper makes the two surfaces meet.
            lo[1] = 31.5
        mb.rbox(tuple(lo), tuple(hi), m["wallpaper"])
    for _, p in _parts(r"^Restrooms/RestroomEntryWall(_Header)?$"):
        lo, hi = _aabb(p)
        lo[1], hi[1] = max(31.5, lo[1]), min(40.5, hi[1])
        lo[2], hi[2] = RZ0 - 0.02, RZ0
        if hi[1] > lo[1]:
            mb.rbox(tuple(lo), tuple(hi), m["wallpaper"])
    return _pool(mb, "RoomWallpaper", wn=False)


def build_gallery_lockers(meshy):
    objs = []
    # GalleryFloor top is 86 (its datum is 85), with the carpet at 86.065. East wall face X23376.
    # Against the end wall, these leave the entire approach and the core stair route clear.
    z = -17.5
    for i, kind in enumerate(("LockerBank", "LockerBank", "LockerBank", "SupplyCabinet")):
        me = meshy[kind]
        lo, hi = _mdims(me)
        width = hi[0] - lo[0]
        zc = z + width / 2
        assert zc + width / 2 < -1.5, "gallery cabinets must stay clear of the south wall"
        pos = (23376.0 - hi[1] - 0.06, 86.065, zc)
        name = "Gallery_%s%d" % (kind, i + 1)
        objs.append(_place(me, name, _M(pos, "-X"), model=name))
        z += width + 0.2
    return objs


def build_service(m, rng):
    objs = [_racks(m, rng)]
    objs += _cartons(m, rng)
    objs.append(_film_cans(m, rng))
    objs.append(_service_supplies(m, rng))
    objs.append(_extinguisher_cabinets(m))
    objs += _workbench(m, rng)
    objs.append(_panels(m, rng))
    objs += _bulkheads(m, rng)
    objs += _janitor(m, rng)
    return [o for o in objs if o]


# ================================================================ entry
def build_rooms_props(seed=1990):
    rng = random.Random(seed)
    gone = _clear()
    m = _mats()
    meshy = _meshy()
    counts = {"deleted": gone}
    counts["wallpaper"] = int(_room_wallpaper(m) is not None)
    counts["gallery_lockers"] = len(build_gallery_lockers(meshy))
    counts["restrooms"] = len(build_restrooms(m, rng, meshy))
    counts["concession"] = len(build_concession(m, rng, meshy))
    counts["arcade"] = len(build_arcade(m, rng, meshy))
    counts["service"] = len(build_service(m, rng))
    counts.update(stats())
    return counts


build_props_rooms = build_rooms_props            # the name build_all.py looks for


def stats():
    objs = [o for o in bpy.data.collections[COLL].objects]
    tri = lambda me: sum(len(p.vertices) - 2 for p in me.polygons)
    inst = [o for o in objs if o.get("l4_prop")]
    pooled = [o for o in objs if not o.get("l4_prop")]
    per_asset = {}
    for o in inst:
        per_asset.setdefault(o.data.name, [tri(o.data), 0])[1] += 1

    def ncol(o):
        v = o.get("l4_col", o.data.get("l4_col", "[]"))
        return len(json.loads(v)) if isinstance(v, str) else len(v)
    lights = [o for o in bpy.data.collections[LCOLL].objects if o.get("l4_pkg") == PKG] if bpy.data.collections.get(LCOLL) else []
    return {"objects": len(objs), "instanced": len(inst), "pooled": len(pooled),
            "tris": sum(tri(o.data) for o in objs),
            "tris_unique": sum(tri(me) for me in {o.data for o in objs}),
            "tris_instanced": sum(t * n for t, n in per_asset.values()),
            "tris_pooled": sum(tri(o.data) for o in pooled),
            "per_asset_tris": {k: v for k, v in sorted(per_asset.items())},
            "colliders": sum(ncol(o) for o in objs), "lights": len(lights),
            "surface_lights": sum(o.data.type == "AREA" for o in lights),
            "shadow_lights": sum(bool(o.get("l4_shadows")) for o in lights),
            "flicker": sum(1 for o in inst if "OccasionalFlicker" in o.get("l4_attrs", ""))}
