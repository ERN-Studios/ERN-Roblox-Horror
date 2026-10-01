# Level 4 facelift, package D1: Blender-modelled props for the concourse, corridors and auditoria
# (r8.md A1-A3 "B" rows plus the D dressing that belongs there).
#
# Run order (headless or MCP):  exec(slots.py) ; exec(props_lobby.py) ; build_lobby_props()
# build_lobby_props() is idempotent. Every run it
#   1. deletes its own objects (collection "L4 Props Lobby", lights with l4_pkg == "D1"), the architecture objects
#      whose obj["l4_path"] matches REPLACES, and the props.py assets it supersedes (OLD_PROPS);
#   2. rebuilds everything from l4_layout.json.
#
# Export contract (read by export_l4.py; see slots.py for the shared conventions):
#   * instanced assets (obj["l4_prop"], obj["l4_model"], obj["l4_src"] = layout index where one exists):
#     seats, tulip tables, cafe chairs, banquettes, queue stanchions, trash bins, the booth projectors and the
#     glass of every flickering fixture; everything else is pooled plain meshes (lightboxes, marquees, sconces,
#     EXIT signs, screens, drapes, ropes, litter, carpet wear).
#   * collision is always mesh["l4_col"] (boxes in the mesh's local metres). Cinema seats carry NO l4_tags: the
#     exporter drops the replaced A#_ChairSeat collider and hands its Level4V4Seat tag to the new box covering it
#     most, which is box 0 (the seat block, >= 30 % overlap even on tipped seats), so the tagged count stays 1188.
#     Cafe chairs: obj["l4_seat"] = True + obj["l4_seat_box"] = 0 -> a Roblox Seat facing the chair front (-Y).
#   * flicker: the fixture's glass is its own instanced prop (l4_attrs {"OccasionalFlicker": true}) with its light
#     parented to it, so place.luau hosts the light in the Neon part and OccasionalFixtureFlicker blinks both.
#   * lights go to "L4 Fixture Lights" with l4_range / l4_brightness (studs / Roblox brightness) and l4_pkg "D1".
#   * decal carriers: every lightbox glass sits 0.01 studs behind the original PosterArt face, the marquee header
#     panel and the EXIT face sit on the original label faces, so export_l4's carrier lift lands the original
#     Decals / SurfaceGuis ("CINEMA n" amber, "EXIT" white) on them. None of those words is modelled here.
#     CARRIER_SKIP leaves out the poster + title of the one empty lightbox.
#   * LIGHTS_SUPERSEDED: the original lights of the fixtures replaced here (export_l4 drops them from legacyLights;
#     the build also deletes them from "L4 Lights").
#   * dressing is split with package F (props_decay.py): F owns concourse popcorn/cup decals, loose cups, wear
#     lanes, stains and aisle trails; D1 adds ticket stubs, dropped buckets and seat-level litter.
import bpy, bmesh, json, math, os, re, random
from contextlib import contextmanager
import numpy as np
from mathutils import Matrix, Vector

HERE = r"G:\Roblox\MongoTV\tools\level4_blender"
if "slot" not in globals():
    exec(open(os.path.join(HERE, "slots.py")).read())

S, OX, FLOOR = 0.28, 23000.0, 24.0
FONT = r"C:\Windows\Fonts\arialbd.ttf"
PKG, COLL, LCOLL = "D1", "L4 Props Lobby", "L4 Fixture Lights"
D1_LAYOUT = json.load(open(os.path.join(HERE, "l4_layout.json")))
D1_P = D1_LAYOUT["parts"]

REPLACES = [
    r"^A\d/A\d_Chair(Seat|Back)$",
    r"^(Concourse|Concession)/(Lobby|WallCafe|Standing)Table(Foot|Rim|Stem|Top)$",
    r"^Concourse/WallCafeChair(Back|Leg|Seat)$",
    r"^Concourse/Lobby(Bench|Sofa)(Back|Seat|Arm)$",
    r"^(Concourse/(A\d_|South)|C\d/C\d_(Return)?|CentralFork/(East|West))Poster(Frame|Art|Title)$",
    r"^Concourse/A\d_Marquee(Bracket|Trim)?$",
    r"^(Concourse/South|C\d/C\d_(Return)?|CentralFork/(East|West))Sconce(Mount|Tube)$",
    r"^A\d/A\d_Sconce$",
    r"^A\d/A\d_ExitSign(Corridor)?$",
    r"^A\d/A\d_Screen(Mask)?$",
    r"^A\d/A\d_Projector(Stand|Lens)?$",
]
# Original preview lights whose fixture this package replaces with its own light (or leaves dark). export_l4 leaves
# them out of legacyLights, and build_lobby_props deletes them from "L4 Lights" so previews are not double-lit.
LIGHTS_SUPERSEDED = [
    r"^Concourse/SouthSconceTube/", r"^CentralFork/(East|West)SconceTube/", r"^A\d/A\d_Sconce/",
    r"^Concourse/A\d_MarqueeTrim/", r"^A\d/A\d_Projector/", r"^A\d/A\d_Screen/",
]
# The empty lightbox: its original poster decal and title must not be re-applied (path regex + original centre).
CARRIER_SKIP = [
    {"path": r"^Concourse/SouthPosterArt$", "at": [23215.0, 39.65, 99.07]},
    {"path": r"^Concourse/SouthPosterTitle$", "at": [23215.0, 30.18, 99.07]},
]
OLD_PROPS = {"CinemaSeat", "HighTable", "CafeChair", "LobbyBench", "LobbySofa"}   # props.py assets replaced here
DEAD_POSTER = ("Concourse/A2_PosterFrame", 22940)
EMPTY_POSTER = ("Concourse/SouthPosterFrame", 23215)


# ---------------------------------------------------------------- coordinates
def _rb(v):                     # Roblox studs point -> Blender metres
    return Vector(((v[0] - OX) * S, -v[2] * S, v[1] * S))


def _rbs(v):                    # Roblox studs point -> Blender axes, still studs (world-space builders)
    return Vector((v[0] - OX, -v[2], v[1]))


def _dir(v):                    # Roblox direction -> Blender direction
    return Vector((v[0], -v[2], v[1]))


def _parts(rx):
    r = re.compile(rx)
    return [(i, p) for i, p in enumerate(D1_P) if r.search(p["p"])]


def _R(p):
    return np.array(p["cf"][3:], dtype=float).reshape(3, 3)


def _aabb(p):
    c = np.array(p["cf"][:3], dtype=float)
    e = np.abs(_R(p)) @ np.array(p["s"], dtype=float) / 2
    return c - e, c + e


_FACE = {"Right": (0, 1), "Left": (0, -1), "Top": (1, 1), "Bottom": (1, -1), "Back": (2, 1), "Front": (2, -1)}


def _face(p, face):             # centre and outward normal of a named face, Roblox studs
    ax, sg = _FACE[face]
    n = _R(p)[:, ax] * sg
    return np.array(p["cf"][:3], dtype=float) + n * p["s"][ax] / 2, n


def _yaw(front):                # rotation about Z turning canonical -Y onto `front` (Blender)
    f = Vector((front[0], front[1], 0))
    if f.length < 1e-6:
        return Matrix.Identity(3)
    f.normalize()
    return Matrix.Rotation(math.atan2(f.x, -f.y), 3, "Z")


def _nearest(p, cands):
    c = np.array(p["cf"][:3])
    return min(cands, key=lambda q: np.linalg.norm(np.array(q[1]["cf"][:3]) - c))


# ---------------------------------------------------------------- materials
def _mats():
    return dict(
        velour=slot("VELOUR_SEAT"), black=slot("PLASTIC_BLACK"), formica=slot("FORMICA_SPECKLE", (46, 40, 50)),
        chrome=slot("CHROME_PITTED"), satin=slot("CHROME_PITTED", (150, 152, 156)), iron=slot("STEEL_PAINTED", (38, 36, 36)),
        vinyl_smooth=slot("PORCELAIN", (78, 12, 22)), brass=slot("BRASS_AGED"), velvet=slot("VELVET_FLUTE"),
        velour_black=slot("VELOUR_SEAT", (24, 20, 22)), glass=slot("GLASS_CLEAR"),
        board=slot("EMIT_WARM", (255, 240, 214)), glow=slot("EMIT_WARM", (255, 214, 160)), bulb=slot("EMIT_WARM"),
        magenta=slot("EMIT_MAGENTA"), cyan=slot("EMIT_CYAN"),
        exitface=slot("EMIT_RED", (225, 28, 28)), deadglass=slot("PORCELAIN", (92, 88, 86)),
        screen=slot("SCREEN_PERF"), aud=slot("CARPET_AUD"),
        bin=slot("STEEL_PAINTED", (104, 22, 28)), foam=slot("VINYL_TUFTED", (200, 172, 110)),
        popcorn=slot("FORMICA_SPECKLE", (234, 206, 140)), paper=slot("PORCELAIN"),
        red=slot("PORCELAIN", (176, 30, 36)), alu=slot("ALU_NOSING"),
    )


# ---------------------------------------------------------------- mesh builder (studs, Blender axes)
class D1Mesh:
    """bmesh-based builder. Geometry is authored in studs; finish() scales to metres. self.M is the current
    transform (use `with mb.at(M):`)."""

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

    def _done(self, verts, mat, smooth, faces=None):
        if self.M != Matrix.Identity(4):
            bmesh.ops.transform(self.bm, matrix=self.M, verts=verts)
        mi = self._mi(mat)
        for f in faces if faces is not None else {f for v in verts for f in v.link_faces}:
            f.material_index = mi
            f.smooth = smooth
        return verts

    def _mi(self, mat):
        if mat not in self.mats:
            self.mats.append(mat)
        return self.mats.index(mat)

    def col(self, box):
        self.cols.append([float(v) for v in box])

    def box(self, c, s, mat, bevel=0.0, seg=1):
        vs = bmesh.ops.create_cube(self.bm, size=1.0)["verts"]
        bmesh.ops.scale(self.bm, vec=Vector(s), verts=vs)
        bmesh.ops.translate(self.bm, vec=Vector(c), verts=vs)
        faces = {f for v in vs for f in v.link_faces}
        if bevel > 0:
            before = set(self.bm.faces) - faces
            edges = list({e for v in vs for e in v.link_edges})
            bmesh.ops.bevel(self.bm, geom=vs + edges, offset=min(bevel, min(s) * 0.45), segments=seg,
                            affect="EDGES", profile=0.5, clamp_overlap=True)
            faces = [f for f in self.bm.faces if f not in before]     # bevel rebuilds the box's own faces too
            vs = list({v for f in faces for v in f.verts})
        return self._done(vs, mat, bevel > 0, faces)

    def cyl(self, c, r, h, mat, axis="Z", seg=16, r2=None, caps=True):
        m = {"X": Matrix.Rotation(math.pi / 2, 4, "Y"), "Y": Matrix.Rotation(math.pi / 2, 4, "X")}.get(axis, Matrix.Identity(4))
        res = bmesh.ops.create_cone(self.bm, cap_ends=caps, segments=seg, radius1=r, radius2=r if r2 is None else r2,
                                    depth=h, matrix=Matrix.Translation(Vector(c)) @ m)
        vs = res["verts"]
        self._done(vs, mat, True)
        for f in {f for v in vs for f in v.link_faces}:
            if len(f.verts) > 4:
                f.smooth = False
        return vs

    def sphere(self, c, r, mat, seg=8, rings=4):
        vs = bmesh.ops.create_uvsphere(self.bm, u_segments=seg, v_segments=rings, radius=r,
                                       matrix=Matrix.Translation(Vector(c)))["verts"]
        return self._done(vs, mat, True)

    def lathe(self, prof, mat, seg=16, c=(0, 0, 0), smooth=True, arc=None, start=0.0):
        """Revolve [(r, z), ...] (bottom to top) around Z. r == 0 makes a pole. arc < 2pi -> open sector."""
        full = arc is None
        arc = 2 * math.pi if full else arc
        n = seg if full else seg + 1
        rings = []
        for r, z in prof:
            if r < 1e-6:
                rings.append([self.bm.verts.new((c[0], c[1], c[2] + z))])
            else:
                rings.append([self.bm.verts.new((c[0] + r * math.cos(start + arc * k / seg),
                                                 c[1] + r * math.sin(start + arc * k / seg), c[2] + z))
                              for k in range(n)])
        F = self.bm.faces.new
        for a, b in zip(rings, rings[1:]):
            if len(a) == 1 and len(b) == 1:
                continue
            for k in range(seg):
                j = (k + 1) % n
                if len(a) == 1:
                    F((a[0], b[j], b[k]))
                elif len(b) == 1:
                    F((a[k], a[j], b[0]))
                else:
                    F((a[k], a[j], b[j], b[k]))
        return self._done([v for r in rings for v in r], mat, smooth)

    def ring(self, c, ro, ri, h, mat, seg=12, depth=None):
        """Open-top cup: outer wall, top annulus, inner wall, inner floor (cupholders, ashtrays)."""
        depth = h * 0.85 if depth is None else depth
        cx, cy, cz = c

        def circ(r, z):
            return [self.bm.verts.new((cx + r * math.cos(2 * math.pi * k / seg), cy + r * math.sin(2 * math.pi * k / seg), z))
                    for k in range(seg)]
        ob, ot, it, ib = circ(ro, cz - h / 2), circ(ro, cz + h / 2), circ(ri, cz + h / 2), circ(ri, cz + h / 2 - depth)
        F = self.bm.faces.new
        for k in range(seg):
            j = (k + 1) % seg
            F((ob[k], ob[j], ot[j], ot[k]))
            F((ot[k], ot[j], it[j], it[k]))
            F((it[k], it[j], ib[j], ib[k]))
        F(list(reversed(ob)))
        F(ib)
        return self._done(ob + ot + it + ib, mat, True)

    def tube(self, pts, r, mat, seg=8, caps=True):
        """Circle swept along a polyline (parallel-transport frames). Fillet the path first for bends."""
        pts = [Vector(p) for p in pts]
        n = len(pts)
        T = []
        for i in range(n):
            t = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)])
            T.append(t.normalized())
        ref = Vector((0, 0, 1)) if abs(T[0].z) < 0.9 else Vector((1, 0, 0))
        N = (ref - ref.dot(T[0]) * T[0]).normalized()
        rings = []
        for i in range(n):
            if i:
                ax = T[i - 1].cross(T[i])
                if ax.length > 1e-7:
                    N = Matrix.Rotation(T[i - 1].angle(T[i]), 3, ax.normalized()) @ N
            B = T[i].cross(N)
            rings.append([self.bm.verts.new(pts[i] + r * (math.cos(2 * math.pi * k / seg) * N + math.sin(2 * math.pi * k / seg) * B))
                          for k in range(seg)])
        F = self.bm.faces.new
        for a, b in zip(rings, rings[1:]):
            for k in range(seg):
                j = (k + 1) % seg
                F((a[k], a[j], b[j], b[k]))
        vs = [v for rr in rings for v in rr]
        if caps:
            F(list(reversed(rings[0])))
            F(rings[-1])
        self._done(vs, mat, True)
        if caps:
            for f in (rings[0][0].link_faces[:] + rings[-1][0].link_faces[:]):
                if len(f.verts) > 4:
                    f.smooth = False
        return vs

    def grid(self, nu, nv, fn, mat, smooth=True):
        """Surface from fn(u, v) -> (x, y, z), u,v in [0, 1]. Faces point along (dP/du x dP/dv)."""
        V = [[self.bm.verts.new(fn(i / nu, j / nv)) for j in range(nv + 1)] for i in range(nu + 1)]
        F = self.bm.faces.new
        for i in range(nu):
            for j in range(nv):
                F((V[i][j], V[i + 1][j], V[i + 1][j + 1], V[i][j + 1]))
        return self._done([v for col in V for v in col], mat, smooth)

    def poly(self, pts, mat):
        vs = [self.bm.verts.new(p) for p in pts]
        self.bm.faces.new(vs)
        return self._done(vs, mat, False)

    def octa(self, c, s, rot, mat):
        """8-triangle lump (popcorn kernels, crumbs)."""
        ax = [Vector((s[0], 0, 0)), Vector((0, s[1], 0)), Vector((0, 0, s[2]))]
        ax = [rot @ a for a in ax]
        c = Vector(c)
        v = [self.bm.verts.new(c + a * sg) for a in ax for sg in (1, -1)]      # +x -x +y -y +z -z
        F = self.bm.faces.new
        for a, b in ((0, 2), (2, 1), (1, 3), (3, 0)):
            F((v[a], v[b], v[4]))
            F((v[b], v[a], v[5]))
        return self._done(v, mat, False)

    def add_geo(self, verts, faces, mat, M=None):
        """Merge raw geometry (text islands). verts: list of Vector, faces: tuples of indices into verts."""
        M = M or Matrix.Identity(4)
        vs = [self.bm.verts.new(M @ Vector(v)) for v in verts]
        for f in faces:
            try:
                self.bm.faces.new([vs[i] for i in f])
            except ValueError:
                pass
        return self._done(vs, mat, False)

    def finish(self, wn=True):
        mname = "L4D1_" + self.name
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
    ob = bpy.data.objects.new("_d1_wn", me)
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
        P, A, B = pts[i], pts[i - 1], pts[i + 1]
        u, w = (A - P), (B - P)
        d = min(rad, 0.45 * u.length, 0.45 * w.length)
        p0, p2 = P + u.normalized() * d, P + w.normalized() * d
        for k in range(nseg + 1):
            t = k / nseg
            out.append((1 - t) ** 2 * p0 + 2 * (1 - t) * t * P + t * t * p2)
    out.append(pts[-1])
    return out


def _text_islands(s, size, extrude=0.03):
    """Text -> list of letter islands [(verts, faces)], laid in the XZ plane facing -Y, centred on the origin."""
    font = bpy.data.fonts.load(FONT, check_existing=True) if os.path.exists(FONT) else None
    cu = bpy.data.curves.new("_d1_txt", "FONT")
    cu.body = s
    if font:
        cu.font = font
    cu.size, cu.extrude, cu.resolution_u = size, extrude, 2
    cu.align_x, cu.align_y = "CENTER", "CENTER"
    ob = bpy.data.objects.new("_d1_txt", cu)
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    bpy.data.objects.remove(ob)
    bpy.data.curves.remove(cu)
    rx = Matrix.Rotation(math.pi / 2, 3, "X")          # text +Z normal -> -Y, text up -> +Z
    co = [rx @ v.co for v in me.vertices]
    polys = [tuple(p.vertices) for p in me.polygons]
    bpy.data.meshes.remove(me)
    if not co:
        return []
    zc = (max(v.z for v in co) + min(v.z for v in co)) / 2
    co = [Vector((v.x, v.y, v.z - zc)) for v in co]
    parent = list(range(len(co)))                       # union-find over shared vertices

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
    out.sort(key=lambda g: sum(v.x for v in g[0]) / len(g[0]))
    return out


# ---------------------------------------------------------------- scene helpers
def _coll(name):
    c = bpy.data.collections.get(name)
    if not c:
        c = bpy.data.collections.new(name)
        root = bpy.data.collections.get("L4 Cinema")
        (root.children if root else bpy.context.scene.collection.children).link(c)
    return c


def _obj(me, name, M, **props):
    o = bpy.data.objects.new(name, me)
    o.matrix_world = M
    _coll(COLL).objects.link(o)
    o["l4_pkg"] = PKG
    for k, v in props.items():
        o[k] = v
    return o


def _place(me, name, base, R, model=None, **props):
    """Instanced asset placement (one Roblox Model each)."""
    return _obj(me, name, Matrix.Translation(base) @ R.to_4x4(), l4_prop=me["l4_asset"], l4_model=model or name, **props)


def _pool(me, name, M=None, **props):
    """Pooled plain mesh (merged per material by the exporter)."""
    props.setdefault("l4_role", "fixture")
    return _obj(me, name, M or Matrix.Identity(4), **props)


def _light(name, pos_b, rgb, rng, bright, shadows=False, parent=None, kind="POINT", rot=None, size=None, angle=None):
    """Fixture light in "L4 Fixture Lights". parent: an l4_prop object (flicker glass) the light rides in.
    kind "AREA" + rot (3x3, light shines along its -Z) + size (studs w, h) -> Roblox SurfaceLight."""
    ld = bpy.data.lights.new("L4D1_" + name, kind)
    ld.color = tuple((c / 255) ** 2.2 for c in rgb)
    rm = rng * S
    ld.energy = 2500.0 * max(0.2, bright) * (rm / 4.0) ** 2
    ld.shadow_soft_size = 0.15
    ld.use_custom_distance = True
    ld.cutoff_distance = rm * 1.3
    if kind == "AREA":
        ld.shape, ld.size, ld.size_y = "RECTANGLE", size[0] * S, size[1] * S
        ld.energy = 4.0 * bright * size[0] * size[1] * S * S
    o = bpy.data.objects.new("L4D1_" + name, ld)
    o.matrix_world = Matrix.Translation(pos_b) @ (rot.to_4x4() if rot else Matrix.Identity(4))
    _coll(LCOLL).objects.link(o)
    o["l4_pkg"], o["l4_range"], o["l4_brightness"], o["l4_shadows"] = PKG, float(rng), float(bright), bool(shadows)
    o["l4_color"] = list(rgb)
    if angle is not None:
        o["l4_angle"] = float(angle)
    if parent is not None:
        mw = o.matrix_world.copy()
        o.parent = parent
        o.matrix_world = mw
    return o


def _flicker(me, name, M, light_args):
    """Glass of a flickering fixture: its own instanced prop carrying OccasionalFlicker, light parented to it."""
    o = _obj(me, name, M, l4_prop=me["l4_asset"], l4_model=name, l4_attrs=json.dumps({"OccasionalFlicker": True}))
    _light(*light_args, parent=o)
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
    sup = [re.compile(r) for r in LIGHTS_SUPERSEDED]
    lights = D1_LAYOUT["lights"]
    for o in list(bpy.data.collections["L4 Lights"].objects) if bpy.data.collections.get("L4 Lights") else []:
        i = o.get("l4_src_light")
        if i is not None and any(r.search(lights[int(i)]["p"]) for r in sup):
            bpy.data.objects.remove(o, do_unlink=True)
    for me in list(bpy.data.meshes):
        if me.users == 0 and (me.name.startswith("L4D1_") or me.get("l4_asset") in OLD_PROPS):
            bpy.data.meshes.remove(me)
    for ld in list(bpy.data.lights):
        if ld.users == 0 and ld.name.startswith("L4D1_"):
            bpy.data.lights.remove(ld)
    return gone


# ---------------------------------------------------------------- floor-space checks (Roblox studs, XZ)
class _Space:
    def __init__(self):
        boxes = []
        for p in D1_P:
            if not p["cc"] or "Level4V4Floor" in (p.get("tags") or []):
                continue
            lo, hi = _aabb(p)
            if hi[1] > FLOOR + 0.2 and lo[1] < FLOOR + 6:
                boxes.append((lo[0], lo[2], hi[0], hi[2]))
        self.B = np.array(boxes)

    def free(self, x, z, r):
        B = self.B
        return not np.any((B[:, 0] < x + r) & (B[:, 2] > x - r) & (B[:, 1] < z + r) & (B[:, 3] > z - r))

    def take(self, x, z, r):
        self.B = np.vstack([self.B, [(x - r, z - r, x + r, z + r)]])


# ================================================================ assets
def a_seat(m, kind):
    """90s loveseat rocker (~400 tris; the end seat's second console adds ~150). Canonical origin = centre of the original seat block footprint on the tier,
    front -Y. The shared armrest console sits on +X (halfway to the next seat); 'end' adds one on -X.
    Colliders: box 0 = the original 4.4 x 3.2 x 2 seat block (receives Level4V4Seat on export), box 1 = the back."""
    a = D1Mesh("CinemaSeat" + {"std": "", "end": "End", "tipped": "Tipped", "broken": "Broken"}[kind])
    V, K = m["velour"], m["black"]

    def console(x):
        a.box((x, 0.3, 1.72), (0.34, 2.9, 1.56), K, 0.07, 1)            # moulded side standard
        a.box((x, 0.18, 2.72), (1.12, 3.5, 0.36), K, 0.1, 1)            # armrest
        a.ring((x, -1.63, 2.69), 0.44, 0.32, 0.42, K, seg=6, depth=0.36)    # cupholder
        a.box((x, 0.6, 0.5), (0.26, 0.3, 1.0), K)                        # floor stanchion
        a.box((x, 0.6, 0.035), (0.62, 1.6, 0.07), K)                     # floor plate
    console(3.0)
    if kind == "end":
        console(-3.0)
    hinge = Matrix.Translation((0, 1.05, 1.15))
    ang = {"tipped": -82.0, "broken": 24.0}.get(kind, 0.0)
    with a.at(hinge @ Matrix.Rotation(math.radians(ang), 4, "X") @ hinge.inverted()):
        a.box((0, -0.12, 1.12), (4.2, 2.75, 0.34), K, 0.1, 1)            # seat pan
        a.box((0, -0.18, 1.62), (4.12, 2.95, 0.72), V, 0.26, 2)          # seat cushion, top at 1.98
    recline = Matrix.Translation((0, 1.9, 1.2)) @ Matrix.Rotation(math.radians(-7), 4, "X") @ Matrix.Translation((0, -1.9, -1.2))
    with a.at(recline):
        a.box((0, 2.0, 3.1), (4.3, 0.42, 3.9), K, 0.12, 1)                # back shell
        if kind == "broken":                                              # cushion ripped off the top third
            a.box((0, 1.62, 2.75), (4.05, 0.5, 1.7), V, 0.2, 1)
            a.box((0, 1.7, 4.1), (3.7, 0.3, 1.0), m["foam"], 0.1, 1)
        else:
            a.box((0, 1.62, 3.45), (4.05, 0.5, 3.4), V, 0.2, 1)           # back cushion
    if kind == "tipped":                                                  # pan stands up against the back
        a.col((0, 0.55, 1.9, 4.4, 2.1, 3.8))
    else:
        a.col((0, 0, 1.0, 4.4, 3.2, 2.0))
    a.col((0, 1.9, 3.1, 4.4, 0.6, 3.8))
    return a.finish()


def a_table(m, ashtray):
    """Tulip-base high-top: cast-iron trumpet base, speckled laminate top (5.44 dia), chrome edge band."""
    a = D1Mesh("TulipTable" + ("Ashtray" if ashtray else ""))
    prof = [(0, 0), (1.36, 0), (1.4, 0.05), (1.34, 0.14), (1.05, 0.28), (0.6, 0.48), (0.32, 0.8), (0.22, 1.2),
            (0.19, 2.3), (0.21, 3.25), (0.34, 3.56), (0.64, 3.72), (0, 3.72)]
    a.lathe(prof, m["iron"], seg=20)
    a.cyl((0, 0, 3.87), 2.72, 0.2, m["formica"], seg=32)
    a.cyl((0, 0, 3.855), 2.76, 0.15, m["chrome"], seg=32, caps=False)
    if ashtray:
        a.ring((0.95, 0.7, 4.03), 0.4, 0.3, 0.12, m["glass"], seg=12, depth=0.08)
        a.cyl((1.0, 0.72, 4.02), 0.03, 0.34, m["paper"], axis="X", seg=5)       # a stubbed-out butt
    for w, d in ((5.5, 2.3), (2.3, 5.5), (3.9, 3.9)):
        a.col((0, 0, 3.87, w, d, 0.2))
    a.col((0, 0, 1.95, 0.5, 0.5, 3.5))
    a.col((0, 0, 0.17, 2.0, 2.0, 0.34))
    return a.finish()


def a_cafechair(m, split):
    """80s tubular chrome chair, burgundy vinyl pads, front -Y (built back-to-front, then turned 180 deg).
    Box 0 becomes the Roblox Seat (obj l4_seat_box = 0)."""
    a = D1Mesh("CafeChair" + ("Split" if split else ""))
    C, V = m["chrome"], m["vinyl_smooth"]
    tr = 0.11
    with a.at(Matrix.Rotation(math.pi, 4, "Z")):
        a.box((0, 0.1, 2.12), (3.7, 3.6, 0.36), V, 0.14, 2)                 # seat pad, top 2.30
        a.box((0, 0.1, 1.89), (3.4, 3.3, 0.1), m["black"])                   # seat board
        tilt = Matrix.Translation((0, -1.75, 2.4)) @ Matrix.Rotation(math.radians(10), 4, "X") @ Matrix.Translation((0, 1.75, -2.4))
        with a.at(tilt):
            a.box((0, -1.8, 3.95), (3.2, 0.3, 1.7), V, 0.13, 2)              # back pad
            a.box((0, -1.99, 3.95), (3.0, 0.08, 1.4), m["black"])            # back board
        for x in (-1.72, 1.72):
            a.tube(_fillet([(x, 1.75, 0.06), (x, 1.72, 1.8), (x, -1.62, 1.8)], 0.4), tr, C, seg=8)
            top = Vector((x, -1.75, 2.4)) + Matrix.Rotation(math.radians(10), 3, "X") @ Vector((0, 0, 2.5))
            a.tube(_fillet([(x, -1.9, 0.06), (x, -1.75, 1.8), (x, -1.75, 2.4), top[:]], 0.3), tr, C, seg=8)
            for y in (1.75, -1.9):
                a.cyl((x, y, 0.04), 0.14, 0.08, m["black"], seg=8)            # glides
        a.tube([(-1.72, 1.55, 1.7), (1.72, 1.55, 1.7)], 0.08, C, seg=6)
        a.tube([(-1.72, -1.85, 0.7), (1.72, -1.85, 0.7)], 0.08, C, seg=6)
        if split:
            with a.at(Matrix.Translation((0.35, 0.3, 2.31)) @ Matrix.Rotation(math.radians(28), 4, "Z")):
                a.box((0, 0, 0), (1.9, 0.16, 0.04), m["foam"])
                a.box((0.1, 0, 0.012), (1.5, 0.05, 0.03), m["black"])
    a.col((0, 0, 1.9, 4.0, 4.0, 0.8))                                    # box 0 = the Roblox Seat
    a.col((0, 1.9, 3.75, 4.0, 0.6, 2.9))
    return a.finish()


def _tufted(a, mat, x0, x1, z0, z1, y_face, bulge=0.42, px=2.0, pz=1.15, step=0.25):
    """Button-tufted panel facing -Y whose edges sit on the plane y = y_face."""
    W, H = x1 - x0, z1 - z0
    nu, nv = max(4, int(W / step)), max(3, int(H / (step * 0.9)))
    rows = int(H / pz)
    btn = []
    for r in range(rows):
        zb = z0 + (H - (rows - 1) * pz) / 2 + r * pz
        off = 0 if r % 2 == 0 else px / 2
        xb = x0 + off + px / 2
        while xb < x1 - 0.3:
            btn.append((xb, zb))
            xb += px
    B = np.array(btn)

    def fn(u, v):
        x, z = x0 + u * W, z0 + v * H
        e = min(x - x0, x1 - x, z - z0, z1 - z)
        edge = min(1.0, e / 0.45)
        edge = edge * edge * (3 - 2 * edge)
        d = np.sqrt(((B - (x, z)) ** 2).sum(1)).min() if len(B) else 9
        pillow = 1 - math.exp(-(d / 0.55) ** 2)
        return (x, y_face - bulge * edge * (0.25 + 0.75 * pillow), z)
    a.grid(nu, nv, fn, mat)
    for xb, zb in btn:
        a.sphere((xb, y_face - bulge * 0.25 - 0.02, zb), 0.09, mat, seg=6, rings=3)


def a_banquette(m, kind, slashed):
    """Button-tufted vinyl banquette on a black plinth with a brass kick strip. Canonical origin = original seat
    centre on the floor, front -Y. Sizes follow the original seat/back(/arm) boxes, which are also the colliders."""
    V, K, Bz = m["vinyl_smooth"], m["black"], m["brass"]
    if kind == "bench":
        a = D1Mesh("Banquette" + ("Slashed" if slashed else ""))
        W, sd, sh, by0, by1, bh = 32.0, 6.0, 2.2, 1.5, 3.5, 6.2
    else:
        a = D1Mesh("BanquetteSofa" + ("Slashed" if slashed else ""))
        W, sd, sh, by0, by1, bh = 40.0, 7.0, 3.0, 1.5, 4.5, 7.0
    hw, fy = W / 2, -sd / 2
    a.box((0, (fy + by1) / 2 + 0.2, 0.4), (W - 0.6, by1 - fy - 0.5, 0.8), K, 0.03, 1)      # plinth (recessed)
    a.box((0, fy + 0.27, 0.27), (W - 0.5, 0.06, 0.3), Bz, 0.01, 1)                          # brass kick strip
    a.box((0, (fy + by0) / 2, 0.8 + 0.28), (W, by0 - fy, 0.56), V, 0.1, 1)                  # upholstered base
    n = int(round(W / 4))
    cw = W / n
    for i in range(n):
        x = -hw + cw * (i + 0.5)
        a.box((x, (fy + by0) / 2 - 0.02, (1.36 + sh) / 2), (cw - 0.06, by0 - fy - 0.04, sh - 1.36), V, 0.34, 2)
        if slashed and i == n // 2 + 1:
            with a.at(Matrix.Translation((x + 0.2, fy + 1.9, sh + 0.005)) @ Matrix.Rotation(math.radians(24), 4, "Z")):
                a.box((0, 0, 0), (2.4, 0.26, 0.05), m["foam"])
                a.box((0.05, 0, 0.02), (2.0, 0.07, 0.04), K)
    bz0 = sh + 0.08
    shell_y = by0 + 0.55
    a.box((0, (shell_y + by1) / 2, (1.2 + bh) / 2), (W, by1 - shell_y, bh - 1.2), K, 0.05, 1)   # back shell
    a.box((0, shell_y + 0.02, bh - 0.12), (W, 0.3, 0.24), K, 0.05, 1)                           # capping
    _tufted(a, V, -hw + 0.2, hw - 0.2, bz0, bh - 0.3, shell_y, bulge=0.45)
    a.col((0, 0, sh / 2, W, sd, sh))
    a.col((0, (by0 + by1) / 2, (sh + bh) / 2, W, by1 - by0, bh - sh))
    if kind == "sofa":
        for sx in (-1, 1):
            x = sx * (hw + 2)
            a.box((x, 0.5, 0.4), (3.6, 7.6, 0.8), K, 0.03, 1)
            a.box((x, 0.5 - 3.8 - 0.03, 0.27), (3.7, 0.06, 0.3), Bz, 0.01, 1)
            a.box((x, 0.5, 2.9), (4.0, 8.0, 4.2), V, 0.85, 3)                 # rolled arm
            a.col((x, 0.5, 2.5, 4.0, 8.0, 5.0))
    return a.finish()


def a_stanchion(m):
    """Brass queue post, 3.63 studs (1.02 m) tall. The rope ends (pooled) carry their own brass caps."""
    a = D1Mesh("QueueStanchion")
    prof = [(0, 0), (0.72, 0), (0.74, 0.05), (0.7, 0.14), (0.5, 0.25), (0.22, 0.33), (0.15, 0.42), (0.13, 0.6),
            (0.13, 3.05), (0.17, 3.1), (0.17, 3.2), (0.1, 3.25), (0, 3.25)]
    a.lathe(prof, m["brass"], seg=16)
    a.sphere((0, 0, 3.42), 0.21, m["brass"], seg=10, rings=6)
    a.col((0, 0, 1.8, 0.45, 0.45, 3.6))
    a.col((0, 0, 0.17, 1.45, 1.45, 0.34))
    return a.finish()


def a_bin(m):
    """Dome-top lobby trash bin: burgundy steel drum, aged brass bands, dome and push flap."""
    a = D1Mesh("TrashBin")
    Bz = m["brass"]
    a.cyl((0, 0, 0.12), 0.84, 0.24, Bz, seg=24)
    a.cyl((0, 0, 1.7), 0.8, 2.96, m["bin"], seg=24, caps=False)
    a.cyl((0, 0, 3.24), 0.84, 0.16, Bz, seg=24)
    dome = [(0.83, 3.32)] + [(0.83 * math.cos(t), 3.32 + 0.83 * math.sin(t)) for t in np.linspace(0.12, math.pi / 2 - 0.15, 6)] + [(0, 4.15)]
    a.lathe(dome, Bz, seg=24)
    flap = [(0.86 * math.cos(t), 3.32 + 0.86 * math.sin(t)) for t in np.linspace(0.2, 1.05, 5)]
    a.lathe(flap, Bz, seg=6, arc=math.radians(64), start=math.radians(-90 - 32))
    a.col((0, 0, 2.07, 1.7, 1.7, 4.15))
    return a.finish()


def a_sconce(m, tall, glass):
    """Deco half-drum uplighter on a brass plate. Origin on the wall face, front -Y. glass: material of the glass
    drum, or None for the body alone (a flickering sconce carries its glass as a separate prop)."""
    a = D1Mesh("Sconce" + ("Torch" if tall else "Drum") + ("_" + glass.name[4:] if glass else "_Body"))
    r, h, bands = (0.78, 4.4, 4) if tall else (1.05, 2.6, 2)
    Bz = m["brass"]
    a.box((0, -0.06, 0), (1.3 if not tall else 1.1, 0.12, h + 1.0), Bz, 0.04, 1)
    c = (0, -0.12, 0)
    half = dict(arc=math.pi, start=math.pi, seg=12)
    if glass:
        a.lathe([(0, -h / 2), (r * 0.9, -h / 2), (r, -h / 2 + 0.1), (r, h / 2 - 0.1), (r * 0.94, h / 2)], glass, c=c, **half)
    for k in range(bands):
        z = -h / 2 + 0.07 + k * (h - 0.14) / (bands - 1)
        a.lathe([(r + 0.04, z - 0.07), (r + 0.07, z), (r + 0.04, z + 0.07)], Bz, c=c, **half)
    a.lathe([(0, -h / 2 - 0.55), (0.12, -h / 2 - 0.4), (0.26, -h / 2 - 0.12), (0.34, -h / 2), (0, -h / 2)], Bz,
            c=(0, -0.12 - r * 0.45, 0), seg=10)
    return a.finish()


def a_sconce_glass(m, tall, glow):
    a = D1Mesh("SconceGlass" + ("Torch" if tall else "Drum") + "_" + glow.name[4:])
    r, h = (0.78, 4.4) if tall else (1.05, 2.6)
    a.lathe([(0, -h / 2), (r * 0.9, -h / 2), (r, -h / 2 + 0.1), (r, h / 2 - 0.1), (r * 0.94, h / 2)], glow,
            c=(0, -0.12, 0), arc=math.pi, start=math.pi, seg=12)
    return a.finish()


# ================================================================ builders
def build_seats(m, rng):
    seats, backs = _parts(r"^A\d/A\d_ChairSeat$"), _parts(r"^A\d/A\d_ChairBack$")
    bpos = np.array([p["cf"][:3] for _, p in backs])
    mesh = {k: a_seat(m, k) for k in ("std", "end", "tipped", "broken")}
    xz = np.array([[p["cf"][0], p["cf"][2]] for _, p in seats])
    placed = []
    for k, (i, p) in enumerate(seats):
        c = np.array(p["cf"][:3])
        bp = backs[int(np.argmin(((bpos - c) ** 2).sum(1)))][1]
        R = _yaw(_dir(c - np.array(bp["cf"][:3])))
        right = R @ Vector((1, 0, 0))                        # canonical +X in Blender == Roblox (x, -z)
        left = np.array([c[0] - 6 * right.x, c[2] + 6 * right.y])
        end = not np.any(((xz - left) ** 2).sum(1) < 1.5 ** 2)
        kind = "end" if end else "std"
        if not end:
            roll = rng.random()
            kind = "tipped" if roll < 0.05 else "broken" if roll < 0.06 else "std"
        base = _rb([c[0], p["cf"][1] - p["s"][1] / 2, c[2]])
        o = _place(mesh[kind], "CinemaSeat", base, R, model="Seat", l4_src=i)
        placed.append((o, kind))
    return placed


def build_tables(m, rng):
    me = {False: a_table(m, False), True: a_table(m, True)}
    out = []
    for i, top in _parts(r"^(Concourse|Concession)/(Lobby|WallCafe|Standing)TableTop$"):
        base = _rb([top["cf"][0], FLOOR, top["cf"][2]])
        R = Matrix.Rotation(rng.uniform(0, 2 * math.pi), 3, "Z")
        name = top["p"].rsplit("/", 1)[-1].replace("Top", "")
        out.append(_place(me[rng.random() < 0.5], name, base, R, l4_src=i))
    return out


def build_cafe_chairs(m, rng):
    me = {False: a_cafechair(m, False), True: a_cafechair(m, True)}
    backs = _parts(r"^Concourse/WallCafeChairBack$")
    seats = _parts(r"^Concourse/WallCafeChairSeat$")
    split = set(rng.sample(range(len(seats)), 3))
    out = []
    for k, (i, seat) in enumerate(seats):
        bk = _nearest(seat, backs)[1]
        front = _dir(np.array(seat["cf"][:3]) - np.array(bk["cf"][:3]))
        base = _rb([seat["cf"][0], FLOOR, seat["cf"][2]])
        R = _yaw(front) @ Matrix.Rotation(rng.uniform(-0.12, 0.12), 3, "Z")
        out.append(_place(me[k in split], "WallCafeChair", base, R, l4_src=i, l4_seat=True, l4_seat_box=0))
    return out


def build_banquettes(m, rng):
    out = []
    for kind, rx in (("bench", "LobbyBench"), ("sofa", "LobbySofa")):
        backs = _parts(r"^Concourse/%sBack$" % rx)
        for n, (i, seat) in enumerate(_parts(r"^Concourse/%sSeat$" % rx)):
            bk = _nearest(seat, backs)[1]
            front = _dir(np.array(seat["cf"][:3]) - np.array(bk["cf"][:3]))
            me = a_banquette(m, kind, slashed=(kind == "sofa"))
            base = _rb([seat["cf"][0], FLOOR, seat["cf"][2]])
            out.append(_place(me, rx, base, _yaw(front), l4_src=i))
    return out


def build_stanchions(m, rng, space):
    """42 brass posts: 6 per station (two rows of 3) at the 4 corridor mouths and the 3 ticket windows,
    30 % toppled; velvet ropes between neighbours (pooled), 2 of them lying on the floor."""
    post = a_stanchion(m)
    pv = [v.co.copy() for v in post.vertices]
    stations = [((cx, -16.0), (0, 1), 3.0) for cx in (22649.0, 22883.0, 23117.0, 23351.0)]
    stations += [((wx, 128.5), (0, 1), 2.6) for wx in (22959.0, 22980.0, 23001.0)]
    posts = []
    for (cx, cz), (dx, dz), half in stations:
        row = []
        for side in (-1, 1):
            for k in range(3):
                x, z = cx + side * half, cz + dz * 5.0 * k
                row.append((x, z))
        posts.append(row)
    flat = [(s, k) for s in range(len(posts)) for k in range(6)]
    toppled = set(rng.sample(flat, round(0.3 * len(flat))))
    rope = D1Mesh("QueueRopes")
    out, hooks = [], {}
    for s, row in enumerate(posts):
        for k, (x, z) in enumerate(row):
            if not space.free(x, z, 0.75):
                print("[D1] stanchion spot blocked", x, z)
            base = _rb([x, FLOOR, z])
            if (s, k) in toppled:
                fall = rng.uniform(0, 2 * math.pi)
                d = Vector((math.cos(fall), math.sin(fall), 0))
                ax = Vector((0, 0, 1)).cross(d).normalized()
                R = Matrix.Rotation(math.radians(81), 3, ax) @ Matrix.Rotation(rng.uniform(0, 6.28), 3, "Z")
                lift = -min((R @ v).z for v in pv)
                base = base + Vector((0, 0, lift))
                hooks[(s, k)] = (base + R @ Vector((0, 0, 3.05 * S)), True)
            else:
                R = Matrix.Rotation(rng.uniform(0, 6.28), 3, "Z")
                hooks[(s, k)] = (base + Vector((0, 0, 3.05 * S)), False)
            out.append(_place(post, "QueueStanchion", base, R))
            space.take(x, z, 0.8)
    on_floor = set(rng.sample([(s, k) for s in range(len(posts)) for k in (0, 1, 3, 4)
                               if (s, k) not in toppled and (s, k + 1) not in toppled], 2))
    for s in range(len(posts)):
        for k in (0, 1, 3, 4):
            _rope(rope, m, hooks[(s, k)], hooks[(s, k + 1)], (s, k) in on_floor, rng)
    _pool(rope.finish(wn=False), "QueueRopes", l4_role="dressing")
    return out


def _rope(a, m, ha, hb, dropped, rng):
    (pa, fa), (pb, fb) = ha, hb
    pa, pb = pa / S, pb / S                                   # studs, Blender axes
    d = (pb - pa)
    dh = Vector((d.x, d.y, 0)).normalized()
    fz = FLOOR + 0.13
    if dropped:                                               # unhooked at one end, lying in an S on the floor
        pa, pb = pa + dh * 0.15, pb - dh * 0.15
        side = Vector((-dh.y, dh.x, 0))
        pts = [pa, Vector((pa.x, pa.y, fz + 0.4)) + dh * 0.3]
        for t in np.linspace(0.15, 1.0, 7):
            p = pa.lerp(pb, t) + side * math.sin(t * 5.5) * 0.9
            pts.append(Vector((p.x, p.y, fz)))
        pts = _fillet(pts, 0.5, 3)
    elif fa or fb:                                            # one post down: droops to the floor
        a0 = pa + (dh * 0.17 if not fa else Vector())
        b0 = pb - (dh * 0.17 if not fb else Vector())
        mid = a0.lerp(b0, 0.5)
        pts = _fillet([a0, Vector((a0.x, a0.y, a0.z)).lerp(Vector((mid.x, mid.y, fz)), 0.6),
                       Vector((mid.x, mid.y, fz)),
                       Vector((b0.x, b0.y, b0.z)).lerp(Vector((mid.x, mid.y, fz)), 0.6), b0], 0.8, 4)
    else:                                                     # hung: catenary with 0.7 sag
        a0, b0 = pa + dh * 0.17, pb - dh * 0.17
        pts = []
        for t in np.linspace(0, 1, 13):
            p = a0.lerp(b0, t)
            p.z -= 0.7 * 4 * t * (1 - t)
            pts.append(p)
    a.tube(pts, 0.12, m["velour"], seg=7)
    for p, q in ((pts[0], pts[1]), (pts[-1], pts[-2])):      # brass end caps
        u = (q - p).normalized()
        a.tube([p - u * 0.05, p + u * 0.3], 0.16, m["brass"], seg=8)


def build_bins(m, rng, space):
    me = a_bin(m)
    cands = []
    for cx in (22649.0, 22883.0, 23117.0, 23351.0):
        cands += [(cx - 29.0, -18.0), (cx + 29.0, -18.0)]
    cands += [(22842.0, 97.8), (22886.0, 97.8), (23046.0, 97.8), (23104.0, 97.8), (23190.0, 97.8), (23270.0, 97.8),
              (22898.0, 76.0), (23102.0, 76.0)]
    out = []
    for x, z in cands:
        if len(out) >= 12:
            break
        if space.free(x, z, 1.0):
            out.append(_place(me, "TrashBin", _rb([x, FLOOR, z]), Matrix.Rotation(rng.uniform(0, 6.28), 3, "Z")))
            space.take(x, z, 1.0)
    return out


# ---------------------------------------------------------------- wall fixtures
def _frame_in_plane(p, n):
    """(width, height, thickness) of a part in the plane with normal n (Roblox)."""
    R = _R(p)
    dots = [abs(float(R[:, k] @ n)) for k in range(3)]
    t = int(np.argmax(dots))
    rest = [k for k in range(3) if k != t]
    up = max(rest, key=lambda k: abs(R[1, k]))
    w = [k for k in rest if k != up][0]
    return p["s"][w], p["s"][up], p["s"][t]


def _outline(a, mat, cx, cz, w, h, y, t=0.16):
    """Rectangular neon tube loop (4 boxes) centred (cx, cz), outer size w x h, in the plane y."""
    for x, z, ww, hh in ((cx, cz + h / 2 - t / 2, w, t), (cx, cz - h / 2 + t / 2, w, t),
                         (cx - w / 2 + t / 2, cz, t, h - 2 * t), (cx + w / 2 - t / 2, cz, t, h - 2 * t)):
        a.box((x, y, z), (ww, t, hh), mat)


def build_lightboxes(m, rng):
    """Satin-aluminium snap-frame poster lightboxes replacing every PosterFrame/Art/Title, each haloed by a thin
    magenta or cyan neon tube. The lit face sits 0.01 studs behind the original PosterArt front face, so the
    re-applied art decal lands on it. Titles below the frame get a black plaque 0.01 behind the title face.
    One lightbox (A2 west) is dead: grey diffuser, dark halo; one (south, x 23215) is empty (CARRIER_SKIP)."""
    frames = _parts(r"^(Concourse/(A\d_|South)|C\d/C\d_(Return)?|CentralFork/(East|West))PosterFrame$")
    arts = _parts(r"PosterArt$")
    titles = _parts(r"PosterTitle$")
    out = []
    for n_, (i, fr) in enumerate(frames):
        art = _nearest(fr, arts)[1]
        fc, nrm = _face(art, art["dec"][0][1])
        O = fc - nrm * 0.01                                       # lit face plane origin (Roblox)
        R = _yaw(_dir(nrm))
        Ri = R.transposed()

        def loc(v):                                               # Roblox point -> canonical studs
            return Ri @ (_rbs(v) - _rbs(O))
        fw, fh, ft = _frame_in_plane(fr, nrm)
        fcen = loc(fr["cf"][:3])
        wall_y = fcen.y + ft / 2                                  # frame back face = wall plane
        depth = max(0.15, wall_y)
        cx, cz = fcen.x, fcen.z
        dead = fr["p"] == DEAD_POSTER[0] and abs(fr["cf"][0] - DEAD_POSTER[1]) < 1
        empty = fr["p"] == EMPTY_POSTER[0] and abs(fr["cf"][0] - EMPTY_POSTER[1]) < 1
        a = D1Mesh("Lightbox_%02d" % n_)
        rail = 0.45
        a.box((cx, (0.04 + depth) / 2, cz), (fw - 0.1, depth - 0.04, fh - 0.1), m["satin"])          # back box
        a.box((cx, 0.02, cz), (fw - 2 * rail + 0.1, 0.02, fh - 2 * rail + 0.1), m["deadglass"] if dead else m["board"])
        for (x, z, w, h) in ((cx, cz + fh / 2 - rail / 2, fw, rail), (cx, cz - fh / 2 + rail / 2, fw, rail),
                             (cx - fw / 2 + rail / 2, cz, rail, fh - 2 * rail), (cx + fw / 2 - rail / 2, cz, rail, fh - 2 * rail)):
            a.box((x, (-0.12 + depth) / 2, z), (w, depth + 0.12, h), m["satin"], 0.06, 2)
        if empty:                                                 # poster gone: a pale sun-ghost where it hung
            aw, ah, _ = _frame_in_plane(art, nrm)
            ac = loc(art["cf"][:3])
            a.box((ac.x, 0.005, ac.z), (aw, 0.005, ah), m["glow"])
        halo = m["deadglass"] if dead else (m["magenta"], m["cyan"])[n_ % 2]
        _outline(a, halo, cx, cz, fw + 0.7, fh + 0.7, wall_y - 0.12)
        if fr["p"].startswith("Concourse/"):                      # header plaque above the concourse lightboxes
            hz, py = cz + fh / 2 + 1.05, wall_y - 0.3
            a.box((cx, (py + wall_y) / 2, hz), (fw * 0.8, 0.3, 1.0), m["black"], 0.03, 1)
            for verts, faces in _text_islands("COMING SOON" if empty else "NOW SHOWING", 0.62, extrude=0.0):
                a.add_geo(verts, faces, m["deadglass"] if dead else halo, Matrix.Translation((cx, py - 0.01, hz)))
        tt = _nearest(fr, titles)
        lo_z = cz - fh / 2
        if tt and np.linalg.norm(np.array(tt[1]["cf"][:3]) - np.array(fr["cf"][:3])) < 14:
            t = tt[1]
            tc, _ = _face(t, t["dec"][0][1])
            tl = loc(tc)
            tw, th, _ = _frame_in_plane(t, nrm)
            if tl.z - th / 2 < lo_z - 0.05:                         # title below the frame -> own plaque
                a.box((tl.x, (tl.y + 0.01 + wall_y) / 2, tl.z), (tw + 0.3, wall_y - tl.y - 0.01, th + 0.24), m["black"], 0.03, 1)
                lo_z = min(lo_z, tl.z - th / 2 - 0.12)
        if depth + 0.12 > 0.3 and O[1] + lo_z < FLOOR + 7.5:
            hz = cz + fh / 2
            a.col((cx, (-0.12 + depth) / 2, (hz + lo_z) / 2, fw, depth + 0.12, hz - lo_z))
        M = Matrix.Translation(_rb(O)) @ R.to_4x4()
        out.append(_pool(a.finish(), "Lightbox", M, l4_src=i, l4_dead=dead, l4_empty=empty))
    return out


MARQUEE_ROWS = {
    "A1": ("ECLIPSE VOYAGE   7:15  9:40", "LAST SHOWING   11:55"),
    "A2": ("AFTERLIGHT RUN   6:30  8:50", "THE GLASS TIDE   11:10"),
    "A3": ("VIOLET PIER   7:00  9:25", "LAST SHOWING   12:00  12:00"),
}


def build_marquees(m, rng):
    """80s marquee over each auditorium: a black glass header on the original marquee face (the original amber
    "CINEMA n" SurfaceGui is lifted onto it), a back-lit milk-plexi letter board below with black changeable
    letters (missing, crooked, one dropped on the carpet), chaser bulbs at 1-stud pitch round the whole box
    (20 % dead; A3 is the dark one), a magenta top / cyan bottom neon edge, riveted brackets and conduit."""
    out = []
    for i, mq in _parts(r"^Concourse/A\d_Marquee$"):
        aid = mq["p"].split("/")[1][:2]
        dark = aid == "A3"
        fc, nrm = _face(mq, "Back")
        R = _yaw(_dir(nrm))
        wall_d = 2.4                                         # face -> north wall plaster face
        W, B = 60.0, 1.2
        zt, zb = 3.5, -9.3                                   # header top / letter board bottom (face centre = 0)
        H, zc = zt - zb, (zt + zb) / 2
        a = D1Mesh("Marquee_" + aid)
        K = m["black"]
        a.box((0, 0.15, 0), (W, 0.3, 7.0), K)                                                     # header panel
        a.box((0, 0.03, -6.7), (W, 0.06, 5.2), m["deadglass"] if dark else m["board"])           # milk plexi
        a.box((0, 0.0, -3.8), (W, 0.3, 0.6), K, 0.04, 1)                                          # divider
        a.box((0, 1.5, zc), (W + 2 * B, 0.2, H + 2 * B), K)                                       # back pan
        for x, z, w, h in ((0, zt + B / 2, W + 2 * B, B), (0, zb - B / 2, W + 2 * B, B),
                           (-W / 2 - B / 2, zc, B, H), (W / 2 + B / 2, zc, B, H)):
            a.box((x, (-0.35 + 1.5) / 2, z), (w, 1.85, h), K, 0.06, 1)                            # border box
        for z, mat in ((zt + B + 0.1, m["deadglass"] if dark else m["magenta"]), (zb - B - 0.1, m["cyan"])):
            a.box((0, -0.2, z), (W + 2 * B + 0.4, 0.22, 0.2), mat)                                # neon edges
        for sx in (-1, 1):
            a.box((sx * (W / 2 + B + 0.1), -0.2, zc), (0.2, 0.22, H + 2 * B + 0.4), m["chrome"], 0.05, 1)
        for z in (-5.4 - 0.95, -8.0 - 0.95):
            a.box((0, -0.01, z), (W, 0.05, 0.07), K)                                              # letter tracks
        spots = [(x, zt + B / 2) for x in np.arange(-W / 2 - 0.6, W / 2 + 0.7, 1.0)]
        spots += [(x, zb - B / 2) for x in np.arange(-W / 2 - 0.6, W / 2 + 0.7, 1.0)]
        spots += [(sx * (W / 2 + B / 2), z) for sx in (-1, 1) for z in np.arange(zb + 0.5, zt, 1.0)]
        dead_rate = 0.6 if dark else 0.2
        for x, z in spots:
            a.sphere((float(x), -0.5, float(z)), 0.2, m["deadglass"] if rng.random() < dead_rate else m["bulb"], seg=5, rings=3)
        miss = 0.18 if dark else 0.07
        dropped = None
        for txt, zr in zip(MARQUEE_ROWS[aid], (-5.4, -8.0)):
            for verts, faces in _text_islands(txt, 1.9, extrude=0.0):
                if rng.random() < miss:
                    dropped = dropped or (verts, faces)
                    continue
                cxl = sum(v.x for v in verts) / len(verts)
                tilt = rng.uniform(6, 13) * rng.choice((-1, 1)) if rng.random() < 0.1 else rng.uniform(-1.2, 1.2)
                drop = -0.12 if abs(tilt) > 5 else 0.0
                Mt = Matrix.Translation((cxl, -0.03, zr + drop)) @ Matrix.Rotation(math.radians(tilt), 4, "Y") @ \
                    Matrix.Translation((-cxl, 0, 0))
                a.add_geo(verts, faces, K, Mt)
        for bx in (-26.0, 26.0):                                                                  # brackets
            for bz in (1.8, -6.5):
                a.box((bx, (1.6 + wall_d) / 2, bz), (0.14, wall_d - 1.6 + 0.1, 1.4), m["iron"], 0.02, 1)
                a.box((bx, (1.6 + wall_d) / 2, bz + 0.66), (0.9, wall_d - 1.6 + 0.1, 0.1), m["iron"])
            a.box((bx, wall_d - 0.05, -2.3), (1.3, 0.1, 10.5), m["iron"], 0.02, 1)                 # wall plate
        ct = zt + B
        a.tube(_fillet([(28.0, 0.9, ct), (28.0, 0.9, ct + 0.8), (28.0, wall_d - 0.12, ct + 0.8),
                        (28.0, wall_d - 0.12, 7.6)], 0.35), 0.1, m["iron"], seg=6)
        a.box((28.0, wall_d - 0.2, 8.0), (0.8, 0.3, 0.8), m["iron"], 0.02, 1)
        M = Matrix.Translation(_rb(fc)) @ R.to_4x4()
        out.append(_pool(a.finish(), "Marquee_" + aid, M, l4_src=i))
        if dark:
            _light("Marquee_%s_0" % aid, _rb(fc) + R @ Vector((0, -3.0 * S, -6.7 * S)), (255, 190, 140), 12, 0.15)
        else:
            for lx in (-18.0, 18.0):
                _light("Marquee_%s_%d" % (aid, lx), _rb(fc) + R @ Vector((lx * S, -3.0 * S, -6.7 * S)), (255, 214, 170), 18, 0.5)
        if dropped and not dark:                             # one missing letter lies on the carpet below
            verts, faces = dropped
            f = D1Mesh("MarqueeDroppedLetter_" + aid)
            Mf = Matrix.Translation((rng.uniform(-18, 18), -rng.uniform(3, 7), FLOOR + 0.07 - fc[1])) @ \
                Matrix.Rotation(rng.uniform(0, 6.28), 4, "Z") @ Matrix.Rotation(-math.pi / 2, 4, "X") @ \
                Matrix.Translation((-sum(v.x for v in verts) / len(verts), 0, 0))
            f.add_geo(verts, faces, K, Mf)
            _pool(f.finish(wn=False), "MarqueeDroppedLetter", M, l4_role="dressing")
    return out


def build_sconces(m, rng):
    """Deco half-drum sconces, each with a small light unless dead:
    * concourse south wall + central fork: tall torches with magenta glass (the synthwave wall lights);
    * corridors: warm drums; C3 is the half-dark stretch, all of its sconces dead;
    * auditoria: warm (A2: blue) torches as in the original; A3 is the dark auditorium, its torches dead.
    Elsewhere ~12 % dead at random, and 3 flicker (glass = OccasionalFlicker prop with the light inside)."""
    out, cache = [], {}

    def mesh(fn, *args):
        return cache.get((fn, args)) or cache.setdefault((fn, args), fn(m, *args))
    spots = []
    for i, tube in _parts(r"^(Concourse/South|C\d/C\d_(Return)?|CentralFork/(East|West))SconceTube$"):
        mount = _nearest(tube, _parts("^" + re.escape(tube["p"].replace("Tube", "Mount")) + "$"))[1]
        n = np.array(tube["cf"][:3]) - np.array(mount["cf"][:3])
        n[1] = 0
        n /= np.linalg.norm(n)
        _, _, mt = _frame_in_plane(mount, n)
        wall = np.array(mount["cf"][:3]) - n * mt / 2
        wall[1] = tube["cf"][1]
        zone = tube["p"].split("/")[0]
        lobby = zone in ("Concourse", "CentralFork")
        spots.append((i, zone, wall, n, lobby, m["magenta"] if lobby else m["glow"], (255, 70, 200) if lobby else (255, 190, 130)))
    for i, sc in _parts(r"^A\d/A\d_Sconce$"):
        aid = sc["p"][:2]
        scr = next(p for _, p in _parts(r"^%s/%s_Screen$" % (aid, aid)))
        n = np.array([np.sign(scr["cf"][0] - sc["cf"][0]), 0.0, 0.0])
        wall = np.array(sc["cf"][:3]) - n * sc["s"][0] / 2
        cool = sc["col"][2] >= 200
        glow = slot("EMIT_COOL", (120, 180, 255)) if cool else m["glow"]
        spots.append((i, aid, wall, n, True, glow, (90, 170, 255) if cool else (255, 170, 110)))
    loose = [k for k, s_ in enumerate(spots) if s_[1] not in ("C3", "A3")]
    flick = {next(k for k in loose if spots[k][1] == z) for z in ("Concourse", "C2", "A1")}
    dead = {k for k, s_ in enumerate(spots) if s_[1] in ("C3", "A3")}
    dead |= set(rng.sample([k for k in loose if k not in flick], round(0.12 * len(loose))))
    for k, (i, zone, wall, n, tall, glow, lrgb) in enumerate(spots):
        R = _yaw(_dir(n))
        M = Matrix.Translation(_rb(wall)) @ R.to_4x4()
        lpos = _rb(wall) + R @ Vector((0, -1.3 * S, 1.0 * S))
        largs = ("Sconce_%d" % i, lpos, lrgb, 16 if tall else 14, 0.35)
        if k in flick:
            out.append(_pool(mesh(a_sconce, tall, None), "Sconce", M, l4_src=i))
            _flicker(mesh(a_sconce_glass, tall, glow), "SconceFlicker", M, largs)
        elif k in dead:
            out.append(_pool(mesh(a_sconce, tall, m["deadglass"]), "Sconce", M, l4_src=i, l4_dead=True))
        else:
            out.append(_pool(mesh(a_sconce, tall, glow), "Sconce", M, l4_src=i))
            _light(*largs)
    return out


def build_exit_signs(m, rng):
    """Period EXIT boxes: satin housing and bezel round a red lit face that sits on the original label face, so
    the original white "EXIT" SurfaceGui lands on it. A small red light each; A2's auditorium-side sign flickers."""
    out, faces = [], {}
    for n_, (i, sg) in enumerate(_parts(r"^A\d/A\d_ExitSign(Corridor)?$")):
        fc, nrm = _face(sg, sg["dec"][0][1])
        R = _yaw(_dir(nrm))
        w, h, t = _frame_in_plane(sg, nrm)
        flick = sg["p"] == "A2/A2_ExitSign"
        a = D1Mesh("ExitSign_%d" % n_)
        a.box((0, 0.35, 0), (w + 0.5, 0.7, h + 0.5), m["satin"], 0.05, 1)                          # housing
        for x, z, ww, hh in ((0, h / 2 + 0.13, w + 0.5, 0.26), (0, -h / 2 - 0.13, w + 0.5, 0.26),
                             (-w / 2 - 0.13, 0, 0.26, h), (w / 2 + 0.13, 0, 0.26, h)):
            a.box((x, -0.04, z), (ww, 0.1, hh), m["satin"], 0.03, 1)                               # bezel
        M = Matrix.Translation(_rb(fc)) @ R.to_4x4()
        largs = ("Exit_%d" % i, _rb(fc) + R @ Vector((0, -0.8 * S, 0)), (255, 60, 50), 7, 0.25)
        if not flick:
            a.box((0, -0.03, 0), (w, 0.06, h), m["exitface"])                                    # lit face
            _light(*largs)
        out.append(_pool(a.finish(), "ExitSign", M, l4_src=i))
        if flick:
            key = (round(w, 2), round(h, 2))
            if key not in faces:
                f = D1Mesh("ExitFace_%d" % len(faces))
                f.box((0, -0.03, 0), (w, 0.06, h), m["exitface"])
                faces[key] = f.finish()
            _flicker(faces[key], "ExitSignFlicker", M, largs)
    return out


def _drape(a, mat, x0, x1, z0, z1, y0, amp=0.32, lam=1.3, sag=0.0, sag_x0=False, pool=0.0):
    """Pleated drape facing -Y. sag lowers one end of the top edge (the x1 end, or x0 with sag_x0: a torn rail);
    pool pushes the lower part forward onto the floor (a fallen drape)."""
    W = x1 - x0
    nu = max(8, int(W / lam * 6))
    nv = 10 if (sag or pool) else 4

    def fn(u, v):
        x = x0 + u * W
        top = z1 - sag * ((1 - u) if sag_x0 else u)
        z = z0 + v * (top - z0)
        flare = 1.0 + 0.35 * (1 - v) ** 2
        y = y0 + amp * flare * math.sin(2 * math.pi * (x - x0) / lam)
        if pool:
            k = max(0.0, 0.45 - v) / 0.45
            y -= pool * k * k
            z = z0 + (z - z0) * (1 - 0.8 * k) + 0.25 * k * math.sin(7 * u + 3 * v)
        return (x, y, z)
    a.grid(nu, nv, fn, mat)


def build_screens(m, rng):
    """Per auditorium: SCREEN_PERF screen on the original face plane, black velour masking, carpeted stage lip,
    fixed pleated leg drapes + valance and pelmet, and the screen's SurfaceLight (A1/A2 cast shadows; A3 is the
    dark auditorium, its screen barely glows). A2's west leg has come half down; A3's screen is torn."""
    out = []
    for i, scr in _parts(r"^A\d/A\d_Screen$"):
        aid = scr["p"][:2]
        fc, nrm = _face(scr, "Back")
        O = np.array([fc[0], FLOOR, fc[2]])
        R = _yaw(_dir(nrm))
        M = Matrix.Translation(_rb(O)) @ R.to_4x4()
        W, H = scr["s"][0], scr["s"][1]
        zc = scr["cf"][1] - FLOOR
        a = D1Mesh("Screen_" + aid)
        a.box((0, 0.06, zc), (W, 0.12, H), m["screen"])
        V = m["velour_black"]
        a.box((0, 0.0, zc + H / 2 + 1.5), (W + 6, 0.4, 3), V, 0.05, 1)
        a.box((0, 0.0, zc - H / 2 - 1.5), (W + 6, 0.4, 3), V, 0.05, 1)
        for sx in (-1, 1):
            a.box((sx * (W / 2 + 1.5), 0.0, zc), (3, 0.4, H + 6), V, 0.05, 1)
        if aid == "A3":                                                  # a 6-stud tear, lower right
            tx, tz = 31.0, zc - 12.0
            pts = [(tx + 0.0, -0.005, tz + 3.2), (tx + 0.35, -0.005, tz + 1.6), (tx + 0.15, -0.005, tz + 0.2),
                   (tx + 0.55, -0.005, tz - 1.4), (tx + 0.3, -0.005, tz - 2.8), (tx - 0.05, -0.005, tz - 1.2),
                   (tx - 0.2, -0.005, tz + 0.6), (tx - 0.1, -0.005, tz + 2.0)]
            a.poly(pts[::-1], m["black"])
            a.poly([(tx + 0.35, -0.01, tz + 1.6), (tx + 1.5, -0.45, tz + 0.9), (tx + 0.15, -0.01, tz + 0.2)], m["screen"])
        a.col((0, 0.06, zc, W, 0.12, H))
        out.append(_pool(a.finish(), "Screen_" + aid, M, l4_src=i))
        f = R @ Vector((0, -1, 0))
        up = Vector((0, 0, 1))
        rot = Matrix((up.cross(-f), up, -f)).transposed()               # columns x, y, z; shines along -Z = f
        lit = aid != "A3"
        _light("Screen_" + aid, _rb(O) + R @ Vector((0, -0.6 * S, zc * S)), (200, 214, 255), 60,
               0.55 if lit else 0.05, shadows=lit, kind="AREA", rot=rot, size=(W, H), angle=80)

        st = D1Mesh("Stage_" + aid)
        SW, SD = 144.0, 4.2
        st.box((0, 0.2 - SD / 2, 0.975), (SW, SD, 1.95), m["black"], 0.03, 1)
        st.box((0, 0.2 - SD / 2, 2.0), (SW, SD, 0.1), m["aud"])
        st.box((0, 0.2 - SD + 0.06, 1.98), (SW, 0.16, 0.16), m["alu"], 0.03, 1)
        st.col((0, 0.2 - SD / 2, 1.025, SW, SD, 2.05))
        out.append(_pool(st.finish(), "Stage_" + aid, M))

        dr = D1Mesh("Drapes_" + aid)
        for sx in (-1, 1):
            x0, x1 = (W / 2 + 1.0, W / 2 + 13.0) if sx > 0 else (-W / 2 - 13.0, -W / 2 - 1.0)
            if aid == "A2" and sx < 0:                                  # fallen: rail torn at the outer end
                _drape(dr, m["velvet"], x0, x1, 2.05, 69.0, -0.9, sag=38.0, sag_x0=True, pool=3.6)
                for k in range(26):
                    dr.octa((rng.uniform(x0 - 0.5, x1 - 1.5), rng.uniform(-5.8, -1.2), rng.uniform(1.9, 3.2)),
                            (rng.uniform(0.9, 1.8), rng.uniform(0.6, 1.2), rng.uniform(0.35, 0.8)),
                            Matrix.Rotation(rng.uniform(0, 6.28), 3, "Z"), m["velvet"])
                dr.col(((x0 + x1) / 2, -3.3, 1.6, x1 - x0 + 1, 6.8, 3.2))
                dr.col(((x0 + x1) / 2, -0.9, 30.0, x1 - x0, 1.4, 56.0))
            else:
                _drape(dr, m["velvet"], x0, x1, 2.05, 69.0, -0.9)
                dr.col(((x0 + x1) / 2, -0.9, 35.5, x1 - x0, 1.4, 67.0))
        _drape(dr, m["velvet"], -W / 2 - 14, W / 2 + 14, zc + H / 2 + 1.8, zc + H / 2 + 8.6, -2.0, amp=0.25, lam=1.0)
        dr.box((0, -2.1, zc + H / 2 + 1.75), (W + 28, 0.35, 0.28), m["brass"])                   # fringe rail
        dr.box((0, -1.2, zc + H / 2 + 9.2), (W + 30, 2.4, 1.2), m["black"], 0.04, 1)            # pelmet
        out.append(_pool(dr.finish(), "Drapes_" + aid, M))
    return out


PROJECTOR_SPEC = {"asset": "Projector35", "glb": "G:/Roblox/_local/l4meshy/Projector35/Projector35.glb",
                  "dims": [1.7, 1.7, 2.24], "tris": 8000, "sem": "metal", "col_slices": 2}
PROJECTOR_YAW = -90.0          # the Meshy projector's lens points along its +X; this turns it onto canonical -Y


def build_projectors(m, rng):
    """The Meshy 35 mm projector on each booth floor where A#_Projector/Stand stood, lens toward the screen through
    the booth window, with a small warm lens light (A3's booth is dark)."""
    me = bpy.data.meshes.get("L4A_Projector35")
    if me is None:
        exec(open(os.path.join(HERE, "import_meshy.py")).read(), {"SPEC": PROJECTOR_SPEC})
        me = bpy.data.meshes["L4A_Projector35"]
    out = []
    for i, pj in _parts(r"^A\d/A\d_Projector$"):
        aid = pj["p"][:2]
        lens = next(p for _, p in _parts(r"^%s/%s_ProjectorLens$" % (aid, aid)))
        stand = next(p for _, p in _parts(r"^%s/%s_ProjectorStand$" % (aid, aid)))
        floor = stand["cf"][1] - stand["s"][1] / 2
        f = _dir(np.array(lens["cf"][:3]) - np.array(pj["cf"][:3]))
        R = _yaw(f) @ Matrix.Rotation(math.radians(PROJECTOR_YAW), 3, "Z")
        base = _rb([pj["cf"][0], floor, pj["cf"][2]])
        out.append(_place(me, aid + "_Projector", base, R, l4_src=i))
        if aid != "A3":
            _light("Projector_" + aid, _rb(lens["cf"][:3]), (255, 214, 170), 14, 0.6)
    return out


# ---------------------------------------------------------------- dressing (pooled, no collision)
def _cup(a, m, c, rng, lying):
    x, y, z = c
    if lying:
        yaw = rng.uniform(0, 6.28)
        with a.at(Matrix.Translation((x, y, z + 0.24)) @ Matrix.Rotation(yaw, 4, "Z") @ Matrix.Rotation(math.pi / 2, 4, "Y")):
            a.cyl((0, 0, 0), 0.2, 0.75, m["paper"], seg=7, r2=0.27)
            a.cyl((0, 0, 0.05), 0.245, 0.18, m["red"], seg=7, caps=False)
    else:
        a.cyl((x, y, z + 0.375), 0.2, 0.75, m["paper"], seg=7, r2=0.27)
        a.cyl((x, y, z + 0.42), 0.245, 0.18, m["red"], seg=7, caps=False)
        a.cyl((x, y, z + 0.77), 0.29, 0.05, m["paper"], seg=7)
        a.tube([(x + 0.05, y, z + 0.5), (x + 0.12, y + 0.04, z + 1.2)], 0.035, m["red"], seg=4)


def _popcorn(a, m, c, rng, n, spread):
    for _ in range(n):
        dx, dy = rng.gauss(0, spread), rng.gauss(0, spread)
        s = rng.uniform(0.11, 0.19)
        a.octa((c[0] + dx, c[1] + dy, c[2] + s * 0.6), (s, s * rng.uniform(0.7, 1.1), s * rng.uniform(0.6, 0.9)),
               Matrix.Rotation(rng.uniform(0, 6.28), 3, (rng.random(), rng.random(), rng.random())), m["popcorn"])


def _bucket(a, m, c, rng):
    yaw = rng.uniform(0, 6.28)
    with a.at(Matrix.Translation((c[0], c[1], c[2] + 0.5)) @ Matrix.Rotation(yaw, 4, "Z") @ Matrix.Rotation(math.radians(96), 4, "Y")):
        a.cyl((0, 0, 0), 0.42, 1.2, m["paper"], seg=8, r2=0.56)
        for zz in (-0.3, 0.25):
            a.cyl((0, 0, zz), 0.47 + 0.06 * zz, 0.18, m["red"], seg=8, caps=False)
    _popcorn(a, m, (c[0] + math.cos(yaw) * 1.1, c[1] + math.sin(yaw) * 1.1, c[2]), rng, 14, 0.5)


def _stub(a, m, c, rng):
    yaw = rng.uniform(0, 6.28)
    u, v = Vector((math.cos(yaw), math.sin(yaw), 0)) * 0.36, Vector((-math.sin(yaw), math.cos(yaw), 0)) * 0.15
    p = Vector(c) + Vector((0, 0, 0.012))
    a.poly([p - u - v, p + u - v, p + u + v, p - u + v], m["popcorn"])


def build_dressing(m, rng, seats, space):
    """Litter that complements package F (props_decay.py owns the concourse popcorn/cup decals, loose cups, wear
    lanes, stains and the 54 aisle trails): ticket stubs and a few dropped popcorn buckets on the concourse, and at
    seat level in the auditoria cups left in cupholders plus popcorn, cups and stubs in the legroom."""
    out = []
    lit = D1Mesh("LitterConcourse")
    fz = FLOOR + 0.045
    area = (22630, 23370, -17.0, 97.0)
    for kind, count in (("stub", 70), ("bucket", 12)):
        k = tries = 0
        while k < count and tries < count * 20:
            tries += 1
            x, z = rng.uniform(area[0], area[1]), rng.uniform(area[2], area[3])
            if not space.free(x, z, 0.8):
                continue
            (_stub if kind == "stub" else _bucket)(lit, m, _rbs([x, fz, z]), rng)
            k += 1
    out.append(_pool(lit.finish(wn=False), "LitterConcourse", l4_role="dressing"))

    # --- auditoria: cups in cupholders, litter in legroom, popcorn trails down the aisle treads
    for aid in ("A1", "A2", "A3"):
        au = D1Mesh("LitterAud_" + aid)
        for o, kind in seats:
            if not o.name or o.get("l4_src") is None or not D1_P[o["l4_src"]]["p"].startswith(aid + "/"):
                continue
            Mw = o.matrix_world
            to_studs = Matrix.Scale(1 / S, 4) @ Mw @ Matrix.Scale(S, 4)
            if kind != "tipped" and rng.random() < 0.05:
                with au.at(to_studs):
                    _cup(au, m, (3.0, -1.63, 2.53), rng, lying=False)
            if rng.random() < 0.1:
                c = (rng.uniform(-1.8, 1.8), rng.uniform(-3.5, -2.0), 0.0)
                with au.at(to_studs):
                    roll = rng.random()
                    if roll < 0.45:
                        _popcorn(au, m, c, rng, rng.randint(4, 9), 0.4)
                    elif roll < 0.8:
                        _cup(au, m, c, rng, lying=True)
                    elif roll < 0.9:
                        _bucket(au, m, c, rng)
                    else:
                        _stub(au, m, c, rng)
        out.append(_pool(au.finish(wn=False), "LitterAud_" + aid, l4_role="dressing"))
    return out


# ================================================================ entry point
def build_lobby_props(seed=1987):
    rng = random.Random(seed)
    gone = _clear()
    m = _mats()
    space = _Space()
    counts = {"deleted": gone}
    seats = build_seats(m, rng)
    counts["seats"] = len(seats)
    counts["seat_kinds"] = {k: sum(1 for _, kk in seats if kk == k) for k in ("std", "end", "tipped", "broken")}
    counts["tables"] = len(build_tables(m, rng))
    counts["cafe_chairs"] = len(build_cafe_chairs(m, rng))
    counts["banquettes"] = len(build_banquettes(m, rng))
    counts["stanchions"] = len(build_stanchions(m, rng, space))
    counts["bins"] = len(build_bins(m, rng, space))
    counts["lightboxes"] = len(build_lightboxes(m, rng))
    counts["marquees"] = len(build_marquees(m, rng))
    counts["sconces"] = len(build_sconces(m, rng))
    counts["exit_signs"] = len(build_exit_signs(m, rng))
    counts["screen_objects"] = len(build_screens(m, rng))
    counts["projectors"] = len(build_projectors(m, rng))
    counts["dressing_objects"] = len(build_dressing(m, rng, seats, space))
    counts.update(stats())
    return counts


def stats():
    objs = [o for o in bpy.data.collections[COLL].objects]
    tri = lambda me: sum(len(p.vertices) - 2 for p in me.polygons)
    inst = [o for o in objs if o.get("l4_prop")]
    pooled = [o for o in objs if not o.get("l4_prop")]
    per_asset = {}
    for o in inst:
        per_asset.setdefault(o.data.name, [tri(o.data), 0])[1] += 1
    cols = sum(len(json.loads(o.data.get("l4_col", "[]"))) for o in objs)
    lights = [o for o in bpy.data.collections[LCOLL].objects if o.get("l4_pkg") == PKG] if bpy.data.collections.get(LCOLL) else []
    pool_tris = {}
    for o in pooled:
        k = re.sub(r"_(A\d|\d+)$", "", o.data.name)
        pool_tris[k] = pool_tris.get(k, 0) + tri(o.data)
    return {"objects": len(objs), "instanced": len(inst), "pooled": len(pooled),
            "tris_instanced": sum(t * n for t, n in per_asset.values()),
            "tris_pooled": sum(pool_tris.values()),
            "per_asset_tris": {k: v for k, v in sorted(per_asset.items())},
            "pooled_tris": dict(sorted(pool_tris.items(), key=lambda kv: -kv[1])),
            "colliders": cols, "lights": len(lights),
            "flicker": sum(1 for o in inst if "OccasionalFlicker" in o.get("l4_attrs", "")),
            "dead_fixtures": sum(1 for o in pooled if o.get("l4_dead"))}
