# Level 4 facelift, package C: doors (r8.md A9). Replaces doors.py.
#
#   exec(open(slots.py).read()); exec(open(doors_v2.py).read()); build_doors_v2()
# build_doors_v2() is idempotent: it removes everything under "L4 Doors" and "L4 Door Frames", the objects it
# tagged l4_pkg = "C_doors", and the architecture objects whose l4_path matches REPLACES (the old hinge posts).
#
# What it builds (Studio studs in the comments; floor = the opening's floor Y):
#   * every leaf >= 9 studs wide becomes a mirrored PAIR, each half its own door: collection "Door <Name>",
#     Empty "DoorHinge_<Name>" on the hinge axis at floor level, leaf "DoorLeaf_<Name>" parented to it with its
#     origin ON the hinge (rotate the Empty about Z to swing it). Names: <original>_A (hinge at the original
#     post) and <original>_B (the partner, hinge at the far jamb, l4_open_angle mirrored). Openings that held two
#     leaves (Arcade, Service, MainEntry) get a 0.6-wide centre mullion, so they hold two pairs.
#     GalleryStair (7.5 wide) stays single; SecretPoster stays single AND full height with its original collider,
#     because its poster Decal is cloned onto the Leaf part's Front face (a split / shorter leaf squashes it).
#   * moving leaves are 7.88 tall (floor +0.12 .. +8.0); a fixed transom fills the opening above them
#     ("DoorTransom_<Opening>", pooled, l4_collide = "bounds").
#   * hollow-metal frames ("DoorFrame_<Opening>", pooled): jambs, head, transom bar, stops on the non-public side
#     (clear of every leaf's swing), jamb hinge leaves, aluminium threshold, centre mullion (mesh["l4_col"] box).
#     The throat liners and face casings of Level4V4Doorway openings are package A's (arch_detail B2.5).
#   * leaf styles: tufted (front exits, arcade: VINYL_TUFTED pads with mesh UVs laid so the geometry buttons sit on
#     the texture's buttons, brass porthole at floor +5, brass push plates around floor +3, 1.2 brass kick plates),
#     restroom (LAMINATE_WOOD, satin push/kick plates, surface closer, round pictogram), steel (STEEL_PAINTED,
#     wired-glass vision panel, lever at floor +3, closer, stencil), glass (black anodised storefront, grimy glass,
#     offset pulls, taped paper; the street doors are welded shut in game, so their chain + padlock is static),
#     poster (the concealed panel: black face under the poster Decal, steel back with a push bar).
#   * each leaf carries its Roblox collider: l4_leaf_cf (12 numbers, Studio layout frame), l4_leaf_size (studs),
#     l4_hinge_pos (Studio point on the hinge axis) - read by export_l4.door_info. The hinge axis sits 0.42 in from
#     the opening edge / mullion face, more than the leaf corner's swing radius, so the unanchored Leaf part never
#     meets a wall collider.
# EXIT boxes above the front exits are package D1's (props_lobby.py builds them on A#_ExitSign*), not repeated here.
#
# Facelift v3 (2026-10-01, owner points 8 + 11): the Arcade and Service openings no longer use the layout leaves.
# THEMED holds one SINGLE leaf each (the 9-stud pair rule does not apply), in the openings package P1 cuts:
#   * Arcade X 23187-23197, Y 24-37: full-height plum-black lacquer leaf, magenta + cyan neon edge inlay, big chrome
#     porthole (the "sun") over a cyan synthwave-grid inlay, chrome push + kick plates; an "Arcade" neon-script
#     marquee lightbox with chaser bulbs above the opening on the lobby face (ray-cast onto the final facade;
#     the old Concourse/ArcadeDoorwaySign slab and its SurfaceGui are superseded: REPLACES + CARRIER_SKIP).
#   * Service X 22860-22868, Y 24-36: plum-gunmetal steel leaf (stencil STAFF ONLY, wired-glass vision panel, lever,
#     closer, kick plates) under a transom with a cyan neon outline on the lobby face and a louvre on the room face.
# The span snaps to a Level4V4Doorway marker of l4_layout.json at that spot (P1's layout), else the spec coordinates.
# Each sign carries one small sign-glow PointLight ("L4 Fixture Lights", l4_kind "sign"); the rest is P2's light plan.
# Both doors stay double-acting PushDoors (they swing away from whoever pushes, OpenAngle 90).
import bpy, bmesh, json, math, os, re
from mathutils import Matrix, Vector

HERE = r"G:\Roblox\MongoTV\tools\level4_blender"
S, OX = 0.28, 23000.0
PKG = "C_doors"
FONT = r"C:\Windows\Fonts\bahnschrift.ttf"
if "slot" not in globals():
    exec(open(os.path.join(HERE, "slots.py")).read(), globals())
_L = json.load(open(os.path.join(HERE, "l4_layout.json")))
_P, _OTHER = _L["parts"], _L["other"]

# architecture objects (build_base l4_path) this module deletes: the old hinge posts; the new frames replace them;
# the old ARCADE sign slab over the closed-up opening (the marquee over the new door replaces it)
REPLACES = [r"^AutomaticDoors/.*_Post$", r"^Concourse/ArcadeDoorwaySign$"]
CARRIER_SKIP = [{"path": r"^Concourse/ArcadeDoorwaySign$", "at": None}]      # its "ARCADE" SurfaceGui

# opening: (original leaves, span a0..a1 along the leaf axis, top Y, wall thickness, public side (axis, sign))
OPENINGS = {
    "A1_FrontExit": (("A1_FrontExit",), -230, -218, 34, 2, ("x", 1)),
    "A2_FrontExit": (("A2_FrontExit",), -230, -218, 34, 2, ("x", 1)),
    "A3_FrontExit": (("A3_FrontExit",), -230, -218, 34, 2, ("x", 1)),
    "A1_BoothAccess": (("A1_BoothAccess",), 22761, 22771, 96, 4, ("z", 1)),
    "A2_BoothAccess": (("A2_BoothAccess",), 22995, 23005, 96, 4, ("z", 1)),
    "A3_BoothAccess": (("A3_BoothAccess",), 23229, 23239, 96, 4, ("z", 1)),
    "GalleryStair": (("GalleryStair",), 22666, 22674, 96, 2, ("z", -1)),
    "SecretPoster": (("SecretPoster",), 86, 96, 36, 2, ("x", 1)),
    "Men_Restroom": (("Men_Restroom",), 23276, 23286, 36, 2, ("z", -1)),
    "Women_Restroom": (("Women_Restroom",), 23326, 23336, 36, 2, ("z", -1)),
    "MainEntry": (("MainEntryWest", "MainEntryEast"), 22988.3, 23011.7, 38, 0.8, ("z", -1)),
}
SINGLE = {"GalleryStair", "SecretPoster"}
# themed single doors (v3): name -> (span X a0..a1, floor Y, top Y, wall plane Z, wall thickness, hinge end
# (-1 = a0, +1 = a1), open angle). Public side is the concourse (-Z) for both.
THEMED = {
    "Arcade": ((23187.0, 23197.0), 24.0, 37.0, 101.0, 2.0, -1, 90.0),
    "Service": ((22860.0, 22868.0), 24.0, 36.0, 101.0, 2.0, 1, 90.0),
}
SCRIPT_FONT = r"C:\Windows\Fonts\segoescb.ttf"
# stencils on the public face of the _A leaf; the third booth repeats "2" (r8 D: duplicate numbers in the gallery)
STENCIL = {"GalleryStair": "STAFF ONLY",
           "A1_BoothAccess": "BOOTH 1", "A2_BoothAccess": "BOOTH 2", "A3_BoothAccess": "BOOTH 2"}
PAPER = {"MainEntryWest_B": 1, "MainEntryEast_A": 2}      # taped-up paper sheets on the inside of the glass

HC = 0.42          # hinge axis in from the jamb / mullion face
HG = 0.03          # leaf edge to hinge axis
MG = 0.06          # gap between the meeting stiles of a pair
MW = 0.6           # centre mullion width
ZB, ZT = 0.12, 8.0 # moving leaf bottom / top above the floor
JW = 0.2           # jamb face width
TR0, TR1 = 8.16, 8.5   # transom bar
HINGE_Z = (0.95, 4.05, 7.15)


def _style(name):
    if re.search(r"_FrontExit$|^Arcade", name):
        return "tufted"
    if name.endswith("_Restroom"):
        return "restroom"
    if name.startswith("MainEntry"):
        return "glass"
    if name == "SecretPoster":
        return "poster"
    return "steel"


def _m(name, tint=None, uv="box"):
    return slot(name, tint, uv)


def _brass():
    """Polished door brass. BRASS_AGED's coarse brushed streaks read as wood grain at door-hardware scale, so the
    hardware uses the finely pitted chrome set tinted gold."""
    return slot("CHROME_PITTED", (200, 160, 84))


# ------------------------------------------------------------------------------------------ geometry builder
def _poly(bm, pts, normal):
    """One face from points, wound so it faces `normal`."""
    f = bm.faces.new([bm.verts.new(p) for p in pts])
    f.normal_update()
    if f.normal.dot(Vector(normal)) < 0:
        f.normal_flip()
    return f


class Geo:
    """bmesh builder in studs (x along, y thickness, z up); finish() bakes a 4x4 into the vertices.
    Every primitive is made in its own temporary bmesh and copied in (absorb): bevel frees elements, and a later
    primitive can reuse those slots, so "the faces after index n" is not a safe way to find new geometry."""

    def __init__(self):
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.mats = []
        self.cols = []                                   # collider boxes (lo, hi) in local studs

    def _mi(self, m):
        if m not in self.mats:
            self.mats.append(m)
        return self.mats.index(m)

    def absorb(self, tb, m, smooth=False, flat_axis=None):
        """Copy the temporary bmesh tb in (verts, faces, UVs) with material m; cylinder caps (faces along
        flat_axis) stay flat. Frees tb."""
        mi = self._mi(m)
        tuv = tb.loops.layers.uv.active
        vmap = {v: self.bm.verts.new(v.co) for v in tb.verts}
        out = []
        for tf in tb.faces:
            tf.normal_update()
            f = self.bm.faces.new([vmap[v] for v in tf.verts])
            f.material_index = mi
            f.smooth = smooth and not (flat_axis is not None and abs(tf.normal.dot(flat_axis)) > 0.9)
            if tuv is not None:
                for lp, tl in zip(f.loops, tf.loops):
                    lp[self.uv].uv = tl[tuv].uv
            out.append(f)
        tb.free()
        return out

    def box(self, lo, hi, m, bev=0.0, rot=None):
        """Axis-aligned box lo..hi (corners in any order); rot = (angle, 'X'|'Y'|'Z') about its centre."""
        lo, hi = Vector(lo), Vector(hi)
        lo, hi = Vector(map(min, lo, hi)), Vector(map(max, lo, hi))
        s = hi - lo
        tb = bmesh.new()
        bmesh.ops.create_cube(tb, size=1.0)
        bmesh.ops.scale(tb, vec=s, verts=list(tb.verts))
        if bev > 0:
            bmesh.ops.bevel(tb, geom=list(tb.edges), offset=min(bev, min(s) * 0.45), segments=1, affect="EDGES",
                            profile=0.5)
        if rot:
            bmesh.ops.rotate(tb, cent=Vector(), matrix=Matrix.Rotation(rot[0], 3, rot[1]), verts=list(tb.verts))
        bmesh.ops.translate(tb, vec=(lo + hi) / 2, verts=list(tb.verts))
        return self.absorb(tb, m)

    def cyl(self, c, r, h, m, axis=(0, 0, 1), seg=12, r2=None, caps=True):
        """Cylinder / cone centred on c along axis (radius r at the -axis end, r2 at the +axis end)."""
        ax = Vector(axis).normalized()
        R = Vector((0, 0, 1)).rotation_difference(ax).to_matrix().to_4x4()
        tb = bmesh.new()
        bmesh.ops.create_cone(tb, cap_ends=caps, cap_tris=False, segments=seg, radius1=r,
                              radius2=r if r2 is None else r2, depth=h, matrix=Matrix.Translation(Vector(c)) @ R)
        return self.absorb(tb, m, smooth=True, flat_axis=ax)

    def poly(self, pts, m, normal, smooth=False):
        f = _poly(self.bm, pts, normal)
        f.material_index = self._mi(m)
        f.smooth = smooth
        return f

    def ring(self, c, r0, r1, y0, y1, m, seg=24, side=-1):
        """Flat annulus facing `side` (+-Y) at y1 with an outer rim down to y0 (a flange sitting on a face)."""
        cx, cz = c
        a = [2 * math.pi * i / seg for i in range(seg)]
        ci = [(cx + r0 * math.cos(t), cz + r0 * math.sin(t)) for t in a]
        co = [(cx + r1 * math.cos(t), cz + r1 * math.sin(t)) for t in a]
        for i in range(seg):
            j = (i + 1) % seg
            self.poly([(ci[i][0], y1, ci[i][1]), (co[i][0], y1, co[i][1]), (co[j][0], y1, co[j][1]),
                       (ci[j][0], y1, ci[j][1])], m, (0, side, 0))
            mid = ((co[i][0] + co[j][0]) / 2 - cx, 0, (co[i][1] + co[j][1]) / 2 - cz)
            self.poly([(co[i][0], y0, co[i][1]), (co[j][0], y0, co[j][1]), (co[j][0], y1, co[j][1]),
                       (co[i][0], y1, co[i][1])], m, mid)

    def tube(self, c, r, y0, y1, m, seg=24):
        """Open cylinder wall along Y, facing its axis (the bore of a porthole)."""
        cx, cz = c
        for i in range(seg):
            t0, t1 = 2 * math.pi * i / seg, 2 * math.pi * (i + 1) / seg
            p0 = (cx + r * math.cos(t0), cz + r * math.sin(t0))
            p1 = (cx + r * math.cos(t1), cz + r * math.sin(t1))
            mid = (-(p0[0] + p1[0]) / 2 + cx, 0, -(p0[1] + p1[1]) / 2 + cz)
            self.poly([(p0[0], y0, p0[1]), (p1[0], y0, p1[1]), (p1[0], y1, p1[1]), (p0[0], y1, p0[1])], m, mid,
                      smooth=True)

    def torus(self, M, R, r, m, seg=10, rseg=4, sx=1.0):
        """Torus in the local XY plane (ring axis Z), local X stretched by sx, placed by the 4x4 M."""
        tb = bmesh.new()
        rings = []
        for i in range(seg):
            t = 2 * math.pi * i / seg
            rings.append([tb.verts.new(M @ Vector(((R + r * math.cos(b)) * math.cos(t) * sx,
                                                   (R + r * math.cos(b)) * math.sin(t), r * math.sin(b))))
                          for b in (2 * math.pi * j / rseg for j in range(rseg))])
        for i in range(seg):
            for j in range(rseg):
                i2, j2 = (i + 1) % seg, (j + 1) % rseg
                tb.faces.new((rings[i][j], rings[i2][j], rings[i2][j2], rings[i][j2]))
        bmesh.ops.recalc_face_normals(tb, faces=list(tb.faces))
        return self.absorb(tb, m, smooth=True)

    def text(self, s, size, xc, zc, y, side, m, font=FONT, depth=0.0, fit=None, shear=0.0):
        """Text on the face y, readable from the `side` (+-Y) it faces, centred on (xc, zc). depth > 0 extrudes it
        from y out to y + side * depth; fit = (w, h) scales it down into that box, centred on its own bounds."""
        cu = bpy.data.curves.new("_c_txt", "FONT")
        cu.body = s
        if os.path.exists(font):
            cu.font = bpy.data.fonts.load(font, check_existing=True)
        cu.size, cu.resolution_u = size, 2
        cu.align_x, cu.align_y = "CENTER", "CENTER"
        cu.shear = shear
        cu.extrude = depth / 2
        ob = bpy.data.objects.new("_c_txt", cu)
        bpy.context.scene.collection.objects.link(ob)
        bpy.context.view_layer.update()
        me = bpy.data.meshes.new_from_object(ob.evaluated_get(bpy.context.evaluated_depsgraph_get()))
        bpy.data.objects.remove(ob)
        bpy.data.curves.remove(cu)
        k, cx, cz = 1.0, 0.0, 0.0
        if fit and me.vertices:
            xs, zs = [v.co.x for v in me.vertices], [v.co.y for v in me.vertices]
            k = min(1.0, fit[0] / (max(xs) - min(xs)), fit[1] / (max(zs) - min(zs)))
            cx, cz = (max(xs) + min(xs)) / 2, (max(zs) + min(zs)) / 2
        sx = 1 if side < 0 else -1                        # the reader's right is +X on the -Y face
        tb = bmesh.new()
        # (x, y, z) -> (sx x, side z, y) has determinant +1, so an extruded mesh keeps its outward normals
        vs = [tb.verts.new((xc + sx * k * (v.co.x - cx), y + side * (v.co.z + depth / 2), zc + k * (v.co.y - cz)))
              for v in me.vertices]
        for p in me.polygons:
            f = tb.faces.new([vs[i] for i in p.vertices])
            f.normal_update()
            if not depth and f.normal.y * side < 0:
                f.normal_flip()
        bpy.data.meshes.remove(me)
        return self.absorb(tb, m)

    def finish(self, name, M):
        """-> mesh 'L4A_<name>' (asset) with M (4x4, local studs -> Blender) applied to the vertices."""
        bmesh.ops.transform(self.bm, matrix=M, verts=self.bm.verts)
        me = bpy.data.meshes.get(name)
        if me:
            me.clear_geometry()
            me.materials.clear()
        else:
            me = bpy.data.meshes.new(name)
        self.bm.to_mesh(me)
        self.bm.free()
        for m in self.mats:
            me.materials.append(m)
        return me


# ------------------------------------------------------------------------------------------ tufted pad
_ROWS = (144.9, 284.8, 431.7, 571.7, 717.2, 861.1, 1005.4)   # button rows of vinyl_tufted_albedo (px from top)
_R0, _RSPAN = _ROWS[0], _ROWS[-1] - _ROWS[0]                 # the texture only repeats cleanly between these


def pad(g, x0, x1, z0, z1, side, T, th, m_vinyl, m_button, hole=None, avoid=(), pitch=1.15, ch=0.07):
    """Button-tufted vinyl pad over the face y = side*T of a leaf: outer rect x0..x1 / z0..z1 on the core,
    front at side*(T+th), chamfered border ch. hole = (cx, cz, half, keep-out radius) for a porthole.
    UVs: the tile is 4 button pitches wide; vertically the texture is laid in strips spanning rows 144.9..1005.4,
    which do repeat, so every geometry button lands on a texture button."""
    n = max(2, round((x1 - x0) / pitch))
    p = (x1 - x0) / n
    tile = 4 * p
    sh = tile * _RSPAN / 1024.0                      # strip height (studs)
    rp = sh / 6
    ztop = z1 - 0.6 * rp                             # first button row below the top edge
    yf, yb = side * (T + th), side * T
    ix0, ix1, iz0, iz1 = x0 + ch, x1 - ch, z0 + ch, z1 - ch
    tb = bmesh.new()
    uvl = tb.loops.layers.uv.new("UVMap")
    nrm = (0, side, 0)
    if hole:
        hx, hz, hs, _ = hole
        rects = [(ix0, ix1, iz0, hz - hs), (ix0, ix1, hz + hs, iz1), (ix0, hx - hs, hz - hs, hz + hs),
                 (hx + hs, ix1, hz - hs, hz + hs)]
    else:
        rects = [(ix0, ix1, iz0, iz1)]
    for a0, a1, b0, b1 in rects:
        _poly(tb, [(a0, yf, b0), (a1, yf, b0), (a1, yf, b1), (a0, yf, b1)], nrm)
    # chamfered border: outer edge on the core, inner edge on the front
    O = [(x0, yb, z0), (x1, yb, z0), (x1, yb, z1), (x0, yb, z1)]
    I = [(ix0, yf, iz0), (ix1, yf, iz0), (ix1, yf, iz1), (ix0, yf, iz1)]
    for i, out in enumerate(((0, -1), (1, 0), (0, 1), (-1, 0))):
        j = (i + 1) % 4
        _poly(tb, [O[i], O[j], I[j], I[i]], (out[0], side * 0.5, out[1]))
    k = 1
    while ztop - k * sh > z0:                        # cut at every strip seam
        bmesh.ops.bisect_plane(tb, geom=list(tb.verts) + list(tb.edges) + list(tb.faces), dist=1e-5,
                               plane_co=(0, 0, ztop - k * sh), plane_no=(0, 0, 1))
        k += 1
    for f in tb.faces:
        ks = max(0, math.floor((ztop - f.calc_center_median().z) / sh))
        for lp in f.loops:
            x, z = lp.vert.co.x, lp.vert.co.z
            ypx = _R0 + (ztop - ks * sh - z) / sh * _RSPAN
            lp[uvl].uv = ((x - x0) / tile, 1 - ypx / 1024.0)
    g.absorb(tb, m_vinyl)
    # geometry buttons on the texture's buttons
    rows = {round(ztop + (_R0 - 2.5) / _RSPAN * sh, 4): 0}         # the half row above the first strip
    for ks in range(k + 1):
        for i, ypx in enumerate(_ROWS):
            rows.setdefault(round(ztop - ks * sh - (ypx - _R0) / _RSPAN * sh, 4), 1 - i % 2)
    btn = 0
    for z, odd in rows.items():
        if not (iz0 + 0.1 < z < iz1 - 0.1):
            continue
        j = 0
        while True:
            x = x0 + p * (j + (0.5 if odd else 0.0))
            j += 1
            if x > ix1 - 0.1:
                break
            if x < ix0 + 0.1:
                continue
            if hole and math.hypot(x - hole[0], z - hole[1]) < hole[3]:
                continue
            if any(a0 - 0.1 < x < a1 + 0.1 and b0 - 0.1 < z < b1 + 0.1 for a0, a1, b0, b1 in avoid):
                continue
            g.cyl((x, side * (T + th + 0.012), z), 0.072, 0.03, m_button, axis=(0, side, 0), seg=5, r2=0.03)
            btn += 1
    return btn


# ------------------------------------------------------------------------------------------ leaves
def _hinges(g, m, zs=HINGE_Z):
    for z in zs:
        g.cyl((0, 0, z), 0.075, 0.5, m, seg=10)
        g.cyl((0, 0, z + 0.27), 0.05, 0.04, m, seg=10)              # finial
        g.box((0.02, -0.02, z - 0.25), (0.34, 0.02, z + 0.25), m)    # leaf half of the butt hinge, in the edge gap


def _closer(g, T, pub, m):
    """Surface door closer on the public face near the hinge, arm up to the transom bar."""
    # kept within 0.33 of the leaf plane: the Leaf collider is 0.4 thick and C5 allows 0.3 proud of it
    y0, y1 = pub * T, pub * (T + 0.22)
    g.box((0.45, y0, 7.3), (1.95, y1, 7.7), m, bev=0.04)
    g.cyl((1.98, pub * (T + 0.11), 7.5), 0.05, 0.22, m, axis=(0, pub, 0), seg=8)
    g.cyl((0.75, pub * (T + 0.24), 7.78), 0.07, 0.06, m, axis=(0, pub, 0), seg=10)      # pinion
    g.box((0.75, pub * (T + 0.22), 7.76), (1.75, pub * (T + 0.27), 7.85), m, bev=0.02)    # main arm
    g.box((1.65, pub * (T + 0.27), 7.84), (2.6, pub * (T + 0.32), 7.93), m, bev=0.02)     # forearm to the frame shoe


def leaf_tufted(g, w, pub):
    T, th = 0.15, 0.09
    core = _m("STEEL_PAINTED", (46, 18, 22))
    brass = _brass()
    vinyl = _m("VINYL_TUFTED", uv="mesh")
    glass = _m("GLASS_CLEAR", (60, 66, 70))
    xc, zp, hs = (HG + w) / 2, 5.0, 0.5
    g.box((HG, -T, ZB), (w, T, zp - hs), core, bev=0.015)
    g.box((HG, -T, zp + hs), (w, T, ZT), core, bev=0.015)
    g.box((HG, -T, zp - hs), (xc - hs, T, zp + hs), core)
    g.box((xc + hs, -T, zp - hs), (w, T, zp + hs), core)
    push = (w - 0.78, w - 0.34, 2.25, 4.55)
    for side in (-1, 1):
        pad(g, HG + 0.1, w - 0.1, ZB + 1.32, ZT - 0.12, side, T, th, vinyl, brass,
            hole=(xc, zp, hs, 0.95), avoid=(push,))
        g.box((HG + 0.05, side * T, ZB + 0.03), (w - 0.05, side * (T + 0.035), ZB + 1.25), brass, bev=0.012)
        g.box((push[0], side * (T + th - 0.01), push[2]), (push[1], side * (T + th + 0.03), push[3]), brass, bev=0.012)
        yf = side * (T + th)
        g.ring((xc, zp), 0.5, 0.84, yf - side * 0.01, yf + side * 0.035, brass, seg=24, side=side)
        for k in range(8):                                             # rivets on the flange
            t = 2 * math.pi * (k + 0.5) / 8
            g.cyl((xc + 0.7 * math.cos(t), yf + side * 0.045, zp + 0.7 * math.sin(t)), 0.035, 0.025, brass,
                  axis=(0, side, 0), seg=5, r2=0.015)
    g.tube((xc, zp), 0.5, -(T + th + 0.03), T + th + 0.03, brass)
    g.cyl((xc, 0, zp), 0.5, 0.03, glass, axis=(0, 1, 0), seg=24)
    _hinges(g, brass)
    return T + th


def leaf_restroom(g, w, pub, sign):
    T = 0.1
    lam = _m("LAMINATE_WOOD")
    sat = _m("CHROME_PITTED")
    g.box((HG, -T, ZB), (w, T, ZT), lam, bev=0.015)
    for side in (-1, 1):
        g.box((HG + 0.05, side * T, ZB + 0.03), (w - 0.05, side * (T + 0.025), ZB + 1.2), sat, bev=0.008)
        g.box((w - 0.7, side * T, 2.5), (w - 0.28, side * (T + 0.025), 4.4), sat, bev=0.008)
    _closer(g, T, pub, sat)
    _hinges(g, sat)
    if sign:                                                            # round pictogram, public face
        xc, zc, y = (HG + w) / 2, 5.5, pub * T
        blk, fig = _m("PLASTIC_BLACK"), _m("PORCELAIN", (214, 200, 164))
        g.cyl((xc, pub * (T + 0.015), zc), 0.72, 0.03, blk, axis=(0, pub, 0), seg=32)
        yf0, yf1 = pub * (T + 0.03), pub * (T + 0.045)
        g.cyl((xc, pub * (T + 0.037), zc + 0.36), 0.085, 0.015, fig, axis=(0, pub, 0), seg=12)
        if sign == "MEN":
            g.box((xc - 0.14, yf0, zc - 0.02), (xc + 0.14, yf1, zc + 0.25), fig)          # torso + arms
            g.box((xc - 0.19, yf0, zc - 0.02), (xc - 0.14, yf1, zc + 0.22), fig)
            g.box((xc + 0.14, yf0, zc - 0.02), (xc + 0.19, yf1, zc + 0.22), fig)
            g.box((xc - 0.12, yf0, zc - 0.36), (xc - 0.02, yf1, zc - 0.02), fig)
            g.box((xc + 0.02, yf0, zc - 0.36), (xc + 0.12, yf1, zc - 0.02), fig)
        else:
            g.poly([(xc - 0.22, yf1, zc - 0.14), (xc + 0.22, yf1, zc - 0.14), (xc + 0.08, yf1, zc + 0.25),
                    (xc - 0.08, yf1, zc + 0.25)], fig, (0, pub, 0))                        # dress
            g.box((xc - 0.1, yf0, zc - 0.36), (xc - 0.03, yf1, zc - 0.14), fig)
            g.box((xc + 0.03, yf0, zc - 0.36), (xc + 0.1, yf1, zc - 0.14), fig)
            g.box((xc - 0.2, yf0, zc + 0.02), (xc - 0.15, yf1, zc + 0.22), fig)
            g.box((xc + 0.15, yf0, zc + 0.02), (xc + 0.2, yf1, zc + 0.22), fig)
        g.text(sign, 0.16, xc, zc - 0.5, yf1, pub, fig)
    return T


def leaf_steel(g, w, pub, stencil, paint=None, kick=False):
    T = 0.1
    paint = paint or _m("STEEL_PAINTED")
    sat = _m("CHROME_PITTED")
    if kick:                                                           # satin kick plates, both faces
        for side in (-1, 1):
            g.box((HG + 0.05, side * T, ZB + 0.03), (w - 0.05, side * (T + 0.025), ZB + 1.2), sat, bev=0.008)
    glass = _m("GLASS_CLEAR", (175, 185, 180))
    xc = (HG + w) / 2
    hx0, hx1, hz0, hz1 = xc - 0.5, xc + 0.5, 4.95, 6.45
    g.box((HG, -T, ZB), (w, T, hz0), paint, bev=0.012)
    g.box((HG, -T, hz1), (w, T, ZT), paint, bev=0.012)
    g.box((HG, -T, hz0), (hx0, T, hz1), paint)
    g.box((hx1, -T, hz0), (w, T, hz1), paint)
    g.box((hx0, -0.012, hz0), (hx1, 0.012, hz1), glass)
    for k in range(1, 4):                                              # wire mesh in the glass
        x = hx0 + k * 0.25
        g.box((x - 0.01, -0.016, hz0), (x + 0.01, 0.016, hz1), sat)
    for k in range(1, 6):
        z = hz0 + k * 0.25
        g.box((hx0, -0.016, z - 0.01), (hx1, 0.016, z + 0.01), sat)
    for side in (-1, 1):
        y0, y1 = side * T, side * (T + 0.05)
        g.box((hx0 - 0.1, y0, hz0 - 0.1), (hx1 + 0.1, y1, hz0), paint, bev=0.01)         # glazing bead
        g.box((hx0 - 0.1, y0, hz1), (hx1 + 0.1, y1, hz1 + 0.1), paint, bev=0.01)
        g.box((hx0 - 0.1, y0, hz0), (hx0, y1, hz1), paint, bev=0.01)
        g.box((hx1, y0, hz0), (hx1 + 0.1, y1, hz1), paint, bev=0.01)
        lx = w - 0.5
        g.cyl((lx, side * (T + 0.025), 3.0), 0.15, 0.05, sat, axis=(0, side, 0), seg=14)  # rose
        g.cyl((lx, side * (T + 0.13), 3.0), 0.05, 0.18, sat, axis=(0, side, 0), seg=8)    # neck
        g.box((lx - 0.6, side * (T + 0.18), 2.96), (lx + 0.04, side * (T + 0.26), 3.05), sat, bev=0.03)
        if side == pub:
            g.cyl((lx, side * (T + 0.02), 3.55), 0.08, 0.04, sat, axis=(0, side, 0), seg=10)  # key cylinder
    _closer(g, T, pub, sat)
    _hinges(g, sat)
    if stencil:
        g.text(stencil, 0.42, xc, 4.2, pub * (T + 0.004), pub, _m("CMU_PAINT", (205, 200, 188)))
    return T


ARC_HINGE_Z = (1.0, 4.7, 8.4, 11.7)
ARC_PORT = (6.6, 1.45, 2.1)        # porthole centre z, glass radius (= square hole half), bezel outer radius
ARC_FRAME, SVC_PAINT, SVC_FRAME = (30, 18, 34), (62, 46, 70), (40, 32, 46)   # plum-black / plum-gunmetal paints


def leaf_arcade(g, w, zt):
    """The arcade's single full-height leaf, the same on both faces (it swings both ways): plum-black lacquer,
    magenta outer + cyan inner neon edge inlay, a big chrome porthole whose bottom sits on the horizon of a cyan
    synthwave grid inlay (the porthole is the sun), chrome push plate at the free edge, chrome kick plate."""
    T = 0.16
    core = _m("STEEL_PAINTED", (36, 22, 42))
    chrome = _m("CHROME_PITTED")
    mag, cyan = _m("EMIT_MAGENTA"), _m("EMIT_CYAN")
    glass = _m("GLASS_CLEAR", (135, 158, 165))
    xc = (HG + w) / 2
    zp, hs, rb = ARC_PORT
    g.box((HG, -T, ZB), (w, T, zp - hs), core)                         # continuous painted skin around the hole
    g.box((HG, -T, zp + hs), (w, T, zt), core)
    g.box((HG, -T, zp - hs), (xc - hs, T, zp + hs), core)
    g.box((xc + hs, -T, zp - hs), (w, T, zp + hs), core)
    hz, gx0, gx1, gz0 = zp - rb, HG + 0.8, w - 0.8, 2.05                # grid: horizon z, x range, bottom z
    for side in (-1, 1):
        y = side * T

        def strip(x0, x1, z0, z1, m, d=0.012):
            g.box((x0, y, z0), (x1, y + side * d, z1), m)

        def line(p0, p1, wd, m, d=0.012):                              # a rotated strip in the leaf face
            (x0, z0), (x1, z1) = p0, p1
            ln = math.hypot(x1 - x0, z1 - z0)
            cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
            g.box((cx - ln / 2, y, cz - wd / 2), (cx + ln / 2, y + side * d, cz + wd / 2), m,
                  rot=(-math.atan2(z1 - z0, x1 - x0), "Y"))

        g.box((HG + 0.05, y, ZB + 0.03), (w - 0.05, y + side * 0.03, 1.4), chrome, bev=0.012)     # kick plate
        for inset, wd, m in ((0.3, 0.08, mag), (0.5, 0.06, cyan)):      # edge inlay loops
            x0, x1, z0, z1 = HG + inset, w - inset, 1.3 + inset, zt - inset
            strip(x0, x1, z0, z0 + wd, m)
            strip(x0, x1, z1 - wd, z1, m)
            strip(x0, x0 + wd, z0 + wd, z1 - wd, m)
            strip(x1 - wd, x1, z0 + wd, z1 - wd, m)
        strip(gx0, gx1, hz - 0.035, hz + 0.035, mag)                    # horizon
        for k in range(6):                                              # grid rows, closer towards the horizon
            z = hz - 0.13 * 1.72 ** k
            if z > gz0 + 0.1:
                strip(gx0, gx1, z - 0.022, z + 0.022, cyan)
        strip(gx0, gx1, gz0 - 0.022, gz0 + 0.022, cyan)
        n = 11
        for i in range(n):                                              # rays from the vanishing point
            xb = gx0 + (gx1 - gx0) * i / (n - 1)
            t0 = 0.13 / (hz - gz0)                                      # start at the first row, not in a knot
            line((xc + (xb - xc) * t0, hz - 0.13), (xb, gz0), 0.044, cyan)
        g.box((w - 1.42, y, 4.75), (w - 0.86, y + side * 0.03, 7.7), chrome, bev=0.012)          # push plate
        yf = y
        g.ring((xc, zp), hs, rb, yf - side * 0.01, yf + side * 0.06, chrome, seg=32, side=side)  # bezel
        for k in range(12):                                             # bezel screws
            t = 2 * math.pi * (k + 0.5) / 12
            g.cyl((xc + (hs + rb) / 2 * math.cos(t), yf + side * 0.07, zp + (hs + rb) / 2 * math.sin(t)), 0.045,
                  0.025, chrome, axis=(0, side, 0), seg=6, r2=0.02)
        g.ring((xc, zp), rb + 0.12, rb + 0.22, yf - side * 0.002, yf + side * 0.012, mag, seg=32, side=side)
    g.tube((xc, zp), hs, -(T + 0.07), T + 0.07, chrome, seg=32)
    g.cyl((xc, 0, zp), hs, 0.03, glass, axis=(0, 1, 0), seg=32)
    _hinges(g, chrome, ARC_HINGE_Z)
    return T + 0.07


def leaf_glass(g, w, pub, paper):
    T = 0.2
    alu = _m("STEEL_PAINTED", (28, 28, 30))                           # black anodised storefront
    glass = _m("GLASS_FROSTED", (150, 146, 128))                     # grimy: the street beyond is a void
    sat = _m("CHROME_PITTED")
    st, top, bot = 0.45, 0.45, 1.1
    g.box((HG, -T, ZB), (HG + st, T, ZT), alu, bev=0.02)
    g.box((w - st, -T, ZB), (w, T, ZT), alu, bev=0.02)
    g.box((HG + st, -T, ZT - top), (w - st, T, ZT), alu, bev=0.02)
    g.box((HG + st, -T, ZB), (w - st, T, ZB + bot), alu, bev=0.02)
    g.box((HG + st, -0.03, ZB + bot), (w - st, 0.03, ZT - top), glass)
    for side in (-1, 1):                                               # glazing beads
        y0, y1 = side * 0.03, side * 0.1
        g.box((HG + st, y0, ZB + bot), (w - st, y1, ZB + bot + 0.06), alu)
        g.box((HG + st, y0, ZT - top - 0.06), (w - st, y1, ZT - top), alu)
        g.box((HG + st, y0, ZB + bot), (HG + st + 0.06, y1, ZT - top), alu)
        g.box((w - st - 0.06, y0, ZB + bot), (w - st, y1, ZT - top), alu)
        hx = w - st / 2                                                # offset pull on the lock stile
        g.cyl((hx, side * 0.45, 3.9), 0.065, 2.8, sat, seg=10)
        for z in (2.8, 5.0):
            g.cyl((hx, side * (T + 0.125), z), 0.045, 0.25, sat, axis=(0, 1, 0), seg=8)
    pap = _m("FORMICA_SPECKLE", (214, 204, 172))
    xs = [(HG + st + 0.9, 5.4, 0.08)] if paper == 1 else [(HG + st + 1.1, 5.9, -0.06), (w - st - 1.2, 3.2, 0.1)] \
        if paper == 2 else []
    for x, z, a in xs:
        g.box((x - 0.65, pub * 0.032, z - 0.85), (x + 0.65, pub * 0.042, z + 0.85), pap, rot=(a, "Y"))
    return 0.3                                                         # collider 0.6: the pulls stay within 0.3


def leaf_poster(g, w, pub, z0, z1):
    T = 0.2
    steel = _m("STEEL_PAINTED")
    blk = _m("PLASTIC_BLACK")
    sat = _m("CHROME_PITTED")
    g.box((0.0, -T, z0), (w, T, z1), steel, bev=0.012)
    g.box((0.04, pub * T, z0 + 0.04), (w - 0.04, pub * (T + 0.012), z1 - 0.04), blk)     # under the poster Decal
    hid = -pub
    g.cyl(((1.3 + w - 0.6) / 2, hid * (T + 0.2), 3.4), 0.06, w - 1.9, sat, axis=(1, 0, 0), seg=10)
    for x in (1.5, w - 0.8):
        g.cyl((x, hid * (T + 0.1), 3.4), 0.045, 0.2, sat, axis=(0, 1, 0), seg=8)
    for z in HINGE_Z:
        g.cyl((0, 0, z), 0.075, 0.5, sat, seg=10)
    return 0.275


def leaf_mesh(style, w, pub, var):
    """-> (mesh, visual half thickness). Assets are shared by every leaf with the same key."""
    oneside = style in ("restroom", "steel", "glass", "poster", "service")
    key = "L4A_Door2_%s_%d%s%s" % (style, round(w * 100), ("_p%d" % pub) if oneside else "",
                                    "".join("_%s" % re.sub(r"\W", "", str(v)) for v in var if v))
    g = Geo()
    if style == "arcade":
        half = leaf_arcade(g, w, var[0])
    elif style == "service":
        half = leaf_steel(g, w, pub, "STAFF ONLY", paint=_m("STEEL_PAINTED", SVC_PAINT), kick=True)
    elif style == "tufted":
        half = leaf_tufted(g, w, pub)
    elif style == "restroom":
        half = leaf_restroom(g, w, pub, var[0])
    elif style == "steel":
        half = leaf_steel(g, w, pub, var[0])
    elif style == "glass":
        half = leaf_glass(g, w, pub, var[0])
    else:
        half = leaf_poster(g, w, pub, var[0], var[1])
    me = g.finish(key, Matrix.Scale(S, 4))
    me["l4_asset"] = key[4:]
    return me, half


# ------------------------------------------------------------------------------------------ frames
def frame_geo(op, L, H, D2, style, pub, bays, hinges, mullion, fmat=None, transom=True, stops=True,
              hz=HINGE_Z, thr_d=None, grille=(-1, 1), pmat=None):
    """Opening-local studs: x along (0..L), y across (leaf plane 0), z up from the floor.
    fmat / pmat override the frame / transom panel paint; transom=False: no transom bar/panels (full-height leaf under the head); stops=False
    for a double-acting leaf; hz = hinge heights; thr_d = threshold half depth; grille = faces with a louvre.
    -> (frame Geo, transom Geo)."""
    f, t = Geo(), Geo()
    mat = fmat or {"tufted": _m("STEEL_PAINTED", (30, 22, 28)), "restroom": _m("STEEL_PAINTED", (58, 50, 46)),
                   "steel": _m("STEEL_PAINTED"), "glass": _m("STEEL_PAINTED", (28, 28, 30))}[style]
    hmat = _brass() if style == "tufted" else _m("CHROME_PITTED")
    top = H - 0.08 if op != "MainEntry" else H                          # under package A's head liner
    sy = -pub                                                           # stops sit on the non-public side
    for x0, x1 in ((0, JW), (L - JW, L)):
        f.box((x0, -D2, 0.06), (x1, D2, top), mat, bev=0.02)
    f.box((JW, -D2, top - 0.3), (L - JW, D2, top), mat, bev=0.02)       # head
    if transom:
        f.box((JW, -D2, TR0), (L - JW, D2, TR1), mat, bev=0.02)         # transom bar
    faces = [JW, L - JW]
    if mullion:
        m0, m1 = L / 2 - MW / 2, L / 2 + MW / 2
        f.box((m0, -D2, 0.06), (m1, D2, top), mat, bev=0.03)
        f.cols.append(((m0, -D2, 0.0), (m1, D2, top)))
        faces += [m0, m1]
    if stops:
        for x in faces:                                                 # jamb / mullion stops
            s = 1 if x in (JW, L / 2 + MW / 2) else -1
            f.box((x, sy * 0.3, 0.06), (x + s * 0.1, sy * 0.5, TR0), mat, bev=0.01)
        f.box((JW, sy * 0.3, ZT), (L - JW, sy * 0.5, TR0), mat, bev=0.01)   # head stop
    for u, d in hinges:                                                 # jamb halves of the butt hinges
        face = min(faces, key=lambda x: abs(x - u))
        for z in hz:
            f.box((face, -0.02, z - 0.25), (u - d * 0.07, 0.02, z + 0.25), hmat)
    thr = _m("ALU_NOSING") if style != "glass" else mat
    td = thr_d or min(D2 + 0.1, 0.65)
    f.box((0, -td, 0), (L, td, 0.06), thr, bev=0.025)
    # transom panels, one per bay
    for b0, b1 in (bays if transom else ()):
        if style == "glass":
            gl = _m("GLASS_FROSTED", (150, 146, 128))
            t.box((b0, -0.03, TR1), (b1, 0.03, top), gl)
            c = (b0 + b1) / 2
            t.box((c - 0.15, -0.2, TR1), (c + 0.15, 0.2, top), mat, bev=0.02)
            for side in (-1, 1):
                t.box((b0, side * 0.03, TR1), (b1, side * 0.1, TR1 + 0.06), mat)
                t.box((b0, side * 0.03, top - 0.36), (b1, side * 0.1, top - 0.3), mat)
            continue
        pm = pmat or {"tufted": _m("WAINSCOT_LACQUER"), "restroom": _m("LAMINATE_WOOD"),
                      "steel": _m("STEEL_PAINTED")}[style]
        th = 0.12 if style == "tufted" else 0.1
        t.box((b0, -th, TR1), (b1, th, top - 0.3), pm, bev=0.015)
        hgt = top - 0.3 - TR1
        if style == "tufted":                                            # brass reeds, as on the reference
            for k in range(3):
                z = TR1 + hgt * (k + 1) / 4
                for side in (-1, 1):
                    t.cyl(((b0 + b1) / 2, side * (th + 0.02), z), 0.05, b1 - b0 - 0.1, _brass(),
                          axis=(1, 0, 0), seg=8)
        elif style == "steel" and hgt > 1.0:                             # louvred transfer grille
            c, gw, gh = (b0 + b1) / 2, min(2.4, b1 - b0 - 0.8), min(1.4, hgt - 0.4)
            zc = TR1 + hgt / 2
            for side in grille:
                y0, y1 = side * th, side * (th + 0.06)
                t.box((c - gw / 2 - 0.08, y0, zc - gh / 2 - 0.08), (c + gw / 2 + 0.08, y1, zc - gh / 2), pm)
                t.box((c - gw / 2 - 0.08, y0, zc + gh / 2), (c + gw / 2 + 0.08, y1, zc + gh / 2 + 0.08), pm)
                t.box((c - gw / 2 - 0.08, y0, zc - gh / 2), (c - gw / 2, y1, zc + gh / 2), pm)
                t.box((c + gw / 2, y0, zc - gh / 2), (c + gw / 2 + 0.08, y1, zc + gh / 2), pm)
                nsl = max(3, int(gh / 0.2))
                for k in range(nsl):
                    z = zc - gh / 2 + (k + 0.5) * gh / nsl
                    t.box((c - gw / 2, side * (th + 0.01), z - 0.07), (c + gw / 2, side * (th + 0.03), z + 0.07),
                          _m("STEEL_PAINTED", (40, 42, 44)), rot=(side * 0.6, "X"))
    return f, t


def chain_and_lock(g, xc, y, z, a=0.43, b=0.17, n=16):
    """Chain looped around the two pull handles of a welded-shut street pair, with a padlock."""
    steel, brass = _m("CHROME_PITTED", (150, 140, 128)), _brass()
    for k in range(n):
        t = 2 * math.pi * k / n
        p = Vector((xc + a * math.cos(t), y + b * math.sin(t), z - 0.05 * math.sin(2 * t)))
        tan = Vector((-a * math.sin(t), b * math.cos(t), 0)).normalized()
        up = Vector((0, 0, 1)) if k % 2 == 0 else tan.cross(Vector((0, 0, 1)))
        R = Matrix((tan, up.cross(tan), up)).transposed().to_4x4()
        g.torus(Matrix.Translation(p) @ R, 0.065, 0.02, steel, seg=8, rseg=3, sx=1.45)
    ly = y + b * (1 if y > 0 else -1)
    g.box((xc - 0.12, ly - 0.05, z - 0.52), (xc + 0.12, ly + 0.05, z - 0.22), brass, bev=0.02)
    g.torus(Matrix.Translation((xc, ly, z - 0.2)) @ Matrix.Rotation(math.pi / 2, 4, "X"), 0.08, 0.018, steel,
            seg=10, rseg=3)


# ------------------------------------------------------------------------------------------ scene
def _coll(name, parent):
    c = bpy.data.collections.get(name)
    if not c:
        c = bpy.data.collections.new(name)
        parent.children.link(c)
    return c


def _clear():
    rx = [re.compile(r) for r in REPLACES]
    gone = set()
    for cname in ("L4 Doors", "L4 Door Frames"):
        c = bpy.data.collections.get(cname)
        if c:
            gone |= {o.name for o in c.all_objects}
    for o in bpy.data.objects:
        if o.get("l4_pkg") == PKG or (o.get("l4_path") and any(r.search(o["l4_path"]) for r in rx)):
            gone.add(o.name)
    for n in gone:
        o = bpy.data.objects.get(n)
        if o:
            bpy.data.objects.remove(o, do_unlink=True)
    for c in list(bpy.data.collections):
        if c.name.startswith("Door ") or c.name == "L4 Door Frames":
            bpy.data.collections.remove(c)
    for me in list(bpy.data.meshes):
        if me.users == 0 and re.match(r"L4A_Door|L4C_Door", me.name):
            bpy.data.meshes.remove(me)
    return len(gone)


def _rb(x, y, z):
    return Vector(((x - OX) * S, -z * S, y * S))


def _rbdir(v):
    return Vector((v[0], -v[2], v[1]))


def _cf12(pos, X):
    Y = Vector((0, 1, 0))
    Z = X.cross(Y)
    return [pos[0], pos[1], pos[2], X.x, Y.x, Z.x, X.y, Y.y, Z.y, X.z, Y.z, Z.z]


def _col_boxes(cols, M):
    out = []
    for lo, hi in cols:
        pts = [M @ Vector((x, y, z)) for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])]
        a = Vector([min(p[i] for p in pts) for i in range(3)])
        b = Vector([max(p[i] for p in pts) for i in range(3)])
        out.append([round(v, 5) for v in (*(a + b) / 2, *(b - a))])
    return out


def _frame_objects(fcoll, op, fg, tg, M, stats, transom=True):
    """Pooled frame (mesh l4_col boxes) + transom (one bounds collider, a solid panel: camera occluder) objects."""
    cols = _col_boxes(fg.cols, M)
    me = fg.finish("L4C_DoorFrame_" + op, M)
    if cols:
        me["l4_col"] = json.dumps(cols)
    fo = bpy.data.objects.new("DoorFrame_" + op, me)
    fcoll.objects.link(fo)
    fo["l4_pkg"] = PKG
    fo["l4_role"] = "door_frame"
    stats["frame_colliders"] += len(cols)
    stats["objects"] += 1
    if not transom:
        tg.bm.free()
        return
    me = tg.finish("L4C_DoorTransom_" + op, M)
    to = bpy.data.objects.new("DoorTransom_" + op, me)
    fcoll.objects.link(to)
    to["l4_pkg"] = PKG
    to["l4_collide"] = "bounds"
    to["l4_occluder"] = True
    stats["transom_colliders"] += 1
    stats["objects"] += 1


def _door(root, name, style, me, half, hinge_st, dvec, w, ang, zt, extra, stats):
    """Collection "Door <name>": Empty DoorHinge_<name> on the hinge axis (Studio hinge_st, leaf towards dvec) and
    the leaf DoorLeaf_<name> parented to it, with its Roblox collider l4_leaf_cf / l4_leaf_size / l4_hinge_pos."""
    db = _rbdir(dvec)
    stats["leaf_meshes"].add(me.name)
    dc = bpy.data.collections.new("Door " + name)
    root.children.link(dc)
    emp = bpy.data.objects.new("DoorHinge_" + name, None)
    emp.empty_display_type = "SINGLE_ARROW"
    emp.empty_display_size = 0.6
    emp.matrix_world = Matrix.Translation(_rb(*hinge_st)) @ Matrix.Rotation(math.atan2(db.y, db.x), 4, "Z")
    dc.objects.link(emp)
    lo = bpy.data.objects.new("DoorLeaf_" + name, me)
    dc.objects.link(lo)
    lo.parent = emp
    lo.matrix_parent_inverse = Matrix.Identity(4)
    lo.matrix_basis = Matrix.Identity(4)
    for o in (emp, lo):
        o["l4_door"] = name
        o["l4_door_style"] = style
        o["l4_open_angle"] = ang
        o["l4_pkg"] = PKG
        for k, v in extra.items():
            o[k] = v
    lo["l4_door_leaf"] = True
    lo["l4_model"] = "Door_" + name
    c = Vector(hinge_st) + dvec * ((HG + w) / 2) + Vector((0, (ZB + zt) / 2, 0))
    lo["l4_leaf_cf"] = [round(v, 5) for v in _cf12(c, dvec)]
    lo["l4_leaf_size"] = [round(w - HG, 4), round(zt - ZB, 4), round(max(0.4, 2 * half), 4)]
    lo["l4_hinge_pos"] = [round(v, 5) for v in hinge_st]
    stats["doors"] += 1
    stats["leaf_colliders"] += 1
    stats["objects"] += 2
    return lo


# ------------------------------------------------------------------------------------------ themed doors (v3)
def _themed_span(name):
    """-> (a0, a1, floor y, top y): the THEMED spec, snapped to a Level4V4Doorway marker of the layout on that wall
    whose centre, width and top are each within 2 studs of it (P1's cut); else the spec itself."""
    (a0, a1), y0, y1, plane = THEMED[name][:4]
    for p in _P:
        if "Level4V4Doorway" not in (p.get("tags") or []):
            continue
        R = [abs(v) for v in p["cf"][3:]]
        ex = [sum(R[3 * i + j] * p["s"][j] for j in range(3)) / 2 for i in range(3)]
        x, y, z = p["cf"][:3]
        if (abs(z - plane) < 1.5 and ex[0] > ex[2] and abs(x - (a0 + a1) / 2) < 2 and abs(2 * ex[0] - (a1 - a0)) < 2
                and abs(y + ex[1] - y1) < 2):
            return x - ex[0], x + ex[0], y - ex[1], y + ex[1]
    return a0, a1, y0, y1


def _facade_z(x0, x1, y0, y1, plane, reach=6.0):
    """Studio Z of the most proud surface on the concourse (-Z) side of the wall plane over x0..x1, y0..y1
    (9 rays from the concourse towards +Z), or None when nothing is there."""
    dg = bpy.context.evaluated_depsgraph_get()
    best = None
    for x in (x0, (x0 + x1) / 2, x1):
        for y in (y0, (y0 + y1) / 2, y1):
            hit, loc = bpy.context.scene.ray_cast(dg, _rb(x, y, plane - reach), Vector((0, -1, 0)),
                                                  distance=reach * S)[:2]
            if hit:
                best = -loc.y / S if best is None else min(best, -loc.y / S)
    return best


def _bulb(g, c, r, m):
    tb = bmesh.new()
    bmesh.ops.create_uvsphere(tb, u_segments=8, v_segments=5, radius=r, matrix=Matrix.Translation(Vector(c)))
    g.absorb(tb, m, smooth=True)


def marquee_arcade(g, xc, yb, z0):
    """'Arcade' neon-script lightbox with chaser bulbs, in opening-local studs (+y = concourse): back on the facade
    at y = yb, bottom at z0. -> (front y, top z)."""
    W, Hs, D = 14.0, 4.2, 0.7
    chrome = _m("CHROME_PITTED")
    mag, cyan, warm = _m("EMIT_MAGENTA"), _m("EMIT_CYAN"), _m("EMIT_WARM")
    dead = _m("GLASS_FROSTED", (96, 88, 84))
    x0, x1, z1 = xc - W / 2, xc + W / 2, z0 + Hs
    yf = yb + D
    g.box((x0, yb, z0), (x1, yf, z1), _m("STEEL_PAINTED", (34, 16, 38)), bev=0.06)
    for a, b, c, d in ((x0, x1, z0, z0 + 0.14), (x0, x1, z1 - 0.14, z1), (x0, x0 + 0.14, z0, z1),
                       (x1 - 0.14, x1, z0, z1)):
        g.box((a, yf - 0.02, c), (b, yf + 0.06, d), chrome, bev=0.02)                     # chrome bezel
    g.box((x0 + 0.35, yf, z0 + 1.0), (x1 - 0.35, yf + 0.02, z1 - 1.0), _m("PLASTIC_BLACK"))   # dark face panel
    for zr in (z0 + 0.5, z1 - 0.5):                                     # chaser bulbs, a few dead
        n = 22
        for i in range(n):
            x = x0 + 0.6 + (W - 1.2) * i / (n - 1)
            g.cyl((x, yf + 0.03, zr), 0.14, 0.06, chrome, axis=(0, 1, 0), seg=8)
            _bulb(g, (x, yf + 0.14, zr), 0.12, dead if (i * 7 + round(zr)) % 11 in (3, 8) else warm)
    zt = (z0 + z1) / 2 + 0.15
    g.text("Arcade", 2.6, xc - 0.2, zt, yf + 0.02, 1, mag, font=SCRIPT_FONT, depth=0.08, fit=(W - 3.0, Hs - 2.3))
    a = -0.035                                                          # cyan swoosh under the script
    g.box((xc - 4.6, yf + 0.02, z0 + 1.12), (xc + 4.4, yf + 0.08, z0 + 1.24), cyan, rot=(a, "Y"))
    g.box((xc + 4.6, yf + 0.02, z0 + 1.22), (xc + 5.3, yf + 0.08, z0 + 1.3), cyan, rot=(a, "Y"))
    return yf, z1


def _glow(cin, name, pos_st, rgb, rng, bright):
    """The sign's own small glow: a shadowless PointLight in "L4 Fixture Lights" (P2 owns the light plan)."""
    ld = bpy.data.lights.new("C_" + name, "POINT")
    ld.color = tuple(_srgb2lin(c / 255) for c in rgb)
    rm = rng * S
    ld.energy = 2500.0 * max(0.2, bright) * (rm / 4.0) ** 2
    ld.shadow_soft_size = 0.15
    ld.use_custom_distance = True
    ld.cutoff_distance = rm * 1.3
    ld.use_shadow = False
    o = bpy.data.objects.new("C_" + name, ld)
    o.location = _rb(*pos_st)
    _coll("L4 Fixture Lights", cin).objects.link(o)
    o["l4_pkg"], o["l4_range"], o["l4_brightness"], o["l4_shadows"] = PKG, float(rng), float(bright), False
    o["l4_color"] = list(rgb)
    o["l4_kind"] = "sign"
    return o


def build_themed(cin, root, fcoll, stats):
    """The v3 single doors (THEMED): Arcade (full-height leaf + marquee) and Service (steel leaf + transom)."""
    for name, (_, _, _, plane, wall, hend, ang) in THEMED.items():
        a0, a1, y0, y1 = _themed_span(name)
        L, H = a1 - a0, y1 - y0
        arcade = name == "Arcade"
        M = Matrix(((S, 0, 0, (a0 - OX) * S), (0, S, 0, -plane * S), (0, 0, S, y0 * S), (0, 0, 0, 1)))  # +y = -Z
        top = H - 0.08
        zt = top - 0.36 if arcade else ZT
        hc = 0.5                                                        # clears the collidable jamb at every angle
        u, d = (hc, 1) if hend < 0 else (L - hc, -1)
        w = L - hc - JW - 0.06
        fg, tg = frame_geo(name, L, H, min(1.1, wall) / 2, "arcade" if arcade else "steel", 1, [(JW, L - JW)],
                           [(u, d)], False, fmat=_m("STEEL_PAINTED", ARC_FRAME if arcade else SVC_FRAME),
                           transom=not arcade, stops=False, hz=ARC_HINGE_Z if arcade else HINGE_Z, thr_d=wall / 2,
                           grille=(-1,), pmat=_m("STEEL_PAINTED", SVC_PAINT))
        depth = min(1.1, wall) / 2
        fg.cols += [((x0, -depth, 0.06), (x1, depth, top)) for x0, x1 in ((0, JW), (L - JW, L))]
        fg.cols += [((JW, -depth, top - 0.3), (L - JW, depth, top)),
                    ((0, -wall / 2, 0), (L, wall / 2, 0.06))]
        if not arcade:                                                  # cyan neon outline on the lobby face
            cyan, x0, x1, z0, z1 = _m("EMIT_CYAN"), JW + 0.3, L - JW - 0.3, TR1 + 0.3, top - 0.6
            for a, b, c, e in ((x0, x1, z0, z0 + 0.07), (x0, x1, z1 - 0.07, z1), (x0, x0 + 0.07, z0, z1),
                               (x1 - 0.07, x1, z0, z1)):
                tg.box((a, 0.1, c), (b, 0.112, e), cyan)
        _frame_objects(fcoll, name, fg, tg, M, stats, transom=not arcade)
        hinge_st = [a0 + u, y0, plane]
        dvec = Vector((d, 0, 0))
        lpub = 1 if d > 0 else -1                                       # leaf-local side facing the concourse
        me, half = leaf_mesh("arcade" if arcade else "service", w, lpub, (round(zt, 3),))
        _door(root, name, "arcade" if arcade else "steel", me, half, hinge_st, dvec, w, ang, zt, {}, stats)
        if arcade:                                                      # marquee on the lobby face
            sx0, sx1, sz0 = a0 + L / 2 - 7.0, a0 + L / 2 + 7.0, y1 + 2.3
            fz = _facade_z(sx0, sx1, sz0, sz0 + 4.2, plane)
            fz = fz if fz is not None and fz > plane - wall / 2 - 1.5 else plane - wall / 2 - 0.22
            g = Geo()
            yb = plane - fz + 0.01
            marquee_arcade(g, L / 2, yb, sz0 - y0)
            so = bpy.data.objects.new("DoorSign_Arcade", g.finish("L4C_DoorSign_Arcade", M))
            fcoll.objects.link(so)
            so["l4_pkg"] = PKG
            so["l4_collide"] = "bounds"
            stats["objects"] += 1
            stats["sign_face_z"] = round(fz, 3)
            _glow(cin, "ArcadeMarqueeGlow", (a0 + L / 2, sz0 - 0.6, fz - 1.8), (255, 70, 205), 8, 0.25)
        else:
            _glow(cin, "ServiceSignGlow", (a0 + L / 2, y0 + (TR1 + top) / 2, plane - 2.2), (70, 225, 255), 5, 0.2)
        stats["lights"] += 1


def build_doors_v2():
    removed = _clear()
    cin = bpy.data.collections["L4 Cinema"]
    root = _coll("L4 Doors", cin)
    fcoll = _coll("L4 Door Frames", cin)
    hinge_at = {o["p"].split("/")[1].rsplit("_Post", 1)[0]: o.get("at", {}) for o in _OTHER
                if o["c"] == "HingeConstraint" and o["p"].startswith("AutomaticDoors/")}
    idx = {p["p"]: i for i, p in enumerate(_P)}
    stats = {"removed": removed, "doors": 0, "leaf_meshes": set(), "tris": 0, "leaf_colliders": 0,
             "frame_colliders": 0, "transom_colliders": 0, "objects": 0, "lights": 0}
    for op, (orig, a0, a1, y1, wall, pubax) in OPENINGS.items():
        li = [idx["AutomaticDoors/%s_Leaf" % n] for n in orig]
        leaves = [_P[i] for i in li]
        posts = [_P[idx["AutomaticDoors/%s_Post" % n]] for n in orig]
        R0 = leaves[0]["cf"][3:]
        X0 = (R0[0], R0[3], R0[6])
        ax = 0 if abs(X0[0]) > abs(X0[2]) else 2
        A = Vector((1, 0, 0)) if ax == 0 else Vector((0, 0, 1))          # opening axis, Studio
        plane = leaves[0]["cf"][2 - ax]                                  # the other horizontal coordinate
        y0 = math.floor(leaves[0]["cf"][1] - leaves[0]["s"][1] / 2 + 1e-6)
        H, L = y1 - y0, a1 - a0
        style = _style(orig[0])
        pub_st = Vector((1, 0, 0)) if pubax[0] == "x" else Vector((0, 0, 1))
        pub_st *= pubax[1]
        # opening frame (Blender): x along A, y = Z x x, z up
        xb = _rbdir(A)
        yb = Vector((0, 0, 1)).cross(xb)
        o_st = [0, y0, 0]
        o_st[ax], o_st[2 - ax] = a0, plane
        ob = _rb(*o_st)
        M = Matrix((list(xb * S) + [0], list(yb * S) + [0], [0, 0, S, 0], list(ob) + [1])).transposed()
        pub = 1 if _rbdir(pub_st).dot(yb) > 0 else -1                   # public side in opening-local y
        # regions -> leaves (u = along-coordinate relative to a0)
        mullion = len(orig) == 2
        specs = []                                                       # (name, orig index, hinge u, dir, w)
        for k, (lf, po) in enumerate(zip(leaves, posts)):
            lc, pc = lf["cf"][ax] - a0, po["cf"][ax] - a0
            if mullion:
                r0, r1 = (0, L / 2 - MW / 2) if lc < L / 2 else (L / 2 + MW / 2, L)
            else:
                r0, r1 = 0, L
            e0 = pc < lc                                                 # post at the r0 end
            name = orig[k]
            if name == "SecretPoster":
                specs.append((name, k, pc, 1 if e0 else -1, lf["s"][0]))
            elif name in SINGLE:
                specs.append((name, k, r0 + HC if e0 else r1 - HC, 1 if e0 else -1, r1 - r0 - HC - JW - 0.06))
            else:
                w = (r1 - r0 - 2 * HC - MG) / 2
                specs.append((name + "_A", k, r0 + HC if e0 else r1 - HC, 1 if e0 else -1, w))
                specs.append((name + "_B", k, r1 - HC if e0 else r0 + HC, -1 if e0 else 1, w))
        # frames + transom (not for the concealed poster panel: package A frames it as wall)
        if style != "poster":
            bays = [(JW, L / 2 - MW / 2), (L / 2 + MW / 2, L - JW)] if mullion else [(JW, L - JW)]
            fg, tg = frame_geo(op, L, H, min(1.1, wall) / 2, style, pub,
                               bays, [(u, d) for _, _, u, d, _ in specs], mullion)
            if op == "MainEntry":                                         # round the pulls of each pair
                for xc in ((L / 2 - MW / 2) / 2, (L / 2 + MW / 2 + L) / 2):
                    chain_and_lock(fg, xc, pub * 0.45, 3.9)
            _frame_objects(fcoll, op, fg, tg, M, stats)
        at_all = [hinge_at.get(n, {}) for n in orig]
        for name, k, u, d, w in specs:
            lf, at = leaves[k], at_all[k]
            dvec = A * d                                                  # Studio, hinge -> free edge
            hinge_st = [0, y0, 0]
            hinge_st[ax], hinge_st[2 - ax] = a0 + u, plane
            lpub = 1 if _rbdir(pub_st).dot(Vector((0, 0, 1)).cross(_rbdir(dvec))) > 0 else -1
            if style == "poster":
                var = (lf["cf"][1] - lf["s"][1] / 2 - y0, lf["cf"][1] + lf["s"][1] / 2 - y0)
            elif style == "restroom":
                var = ((orig[k].split("_")[0].upper() if name.endswith("_A") else None),)
            elif style == "steel":
                var = ((STENCIL.get(orig[k]) if name.endswith("_A") or name in SINGLE else None),)
            elif style == "glass":
                var = (PAPER.get(name, 0),)
            else:
                var = ()
            me, half = leaf_mesh(style, w, lpub, var)
            ang = float(at.get("OpenAngle", 95))
            if name.endswith("_B"):
                ang = -ang                                                # the partner swings mirrored
            extra = {}
            if at.get("FixedOpenAngle"):
                extra["l4_fixed_open_angle"] = float(at["FixedOpenAngle"])
            if at.get("NonBlockingWhenOpen"):
                extra["l4_nonblocking_open"] = True
            lo = _door(root, name, style, me, half, hinge_st, dvec, w, ang, ZT, extra, stats)
            lo["l4_src"] = li[k]
            if style == "poster":                                         # the original collider carries the poster
                lo["l4_leaf_cf"] = list(lf["cf"])
                lo["l4_leaf_size"] = list(lf["s"])
                lo["l4_decals"] = 1
                lo["l4_attrs"] = json.dumps({"ConcealedEntrance": True})
    build_themed(cin, root, fcoll, stats)
    # triangles as placed (instanced leaves count once per door)
    for o in list(fcoll.objects) + [o for o in root.all_objects if o.type == "MESH"]:
        o.data.calc_loop_triangles()
        stats["tris"] += len(o.data.loop_triangles)
    stats["leaf_meshes"] = len(stats["leaf_meshes"])
    print("doors_v2:", json.dumps(stats), flush=True)
    return stats


if __name__ == "__main__":
    build_doors_v2()
