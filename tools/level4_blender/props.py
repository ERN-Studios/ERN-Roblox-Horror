# Level 4 cinema, Blender rebuild - stage 2: modelled props replacing the primitive-built ones.
# Every prop is one mesh asset built in a canonical frame (metres, origin bottom-centre, front = -Y,
# up = +Z) and placed as a linked duplicate at the spot the Studio parts occupied. Each placed prop is
# its own object (a gameplay object in Roblox keeps its own Model); "l4_prop" names the asset,
# "l4_model" the Roblox model name, "l4_attrs" the attributes the original carried.
import bpy, bmesh, json, math, os, re
import numpy as np
from mathutils import Matrix, Vector

HERE = r"G:\Roblox\MongoTV\tools\level4_blender"
TEX = r"G:\Blender\Level4_Cinema\textures"
S, OX = 0.28, 23000.0
C3 = np.array(((1, 0, 0), (0, 0, -1), (0, 1, 0)), dtype=float)
D = json.load(open(os.path.join(HERE, "l4_layout.json")))
P = D["parts"]
OTHER = D["other"]


def rb(v):                                   # Roblox studs point -> Blender metres
    return Vector(((v[0] - OX) * S, -v[2] * S, v[1] * S))


def pos(p):
    return rb(p["cf"][:3])


def rot(p):                                  # Blender 3x3 of a part
    R = np.array(p["cf"][3:]).reshape(3, 3)
    return Matrix((C3 @ R @ C3.T).tolist())


def world_size(p):                           # axis-aligned extent in Blender metres
    R = np.array(p["cf"][3:]).reshape(3, 3)
    e = np.abs(R) @ np.array(p["s"])
    return Vector((e[0] * S, e[2] * S, e[1] * S))


def parts(rx):
    r = re.compile(rx)
    return [(i, p) for i, p in enumerate(P) if r.search(p["p"])]


# ---------------------------------------------------------------- materials for props
def srgb(c):
    return tuple((v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4) for v in c)


def pmat(name, col, rough=0.5, metal=0.0, emit=0.0, tex=None, tile=1.0, alpha=1.0, sem=None):
    mat = bpy.data.materials.get("L4P_" + name)
    if mat:
        return mat
    mat = bpy.data.materials.new("L4P_" + name)
    mat.use_nodes = True
    nt = mat.node_tree
    b = nt.nodes["Principled BSDF"]
    lin = srgb([c / 255 for c in col])
    b.inputs["Base Color"].default_value = (*lin, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if tex and os.path.exists(os.path.join(TEX, tex)):
        img = bpy.data.images.get(tex) or bpy.data.images.load(os.path.join(TEX, tex))
        tc = nt.nodes.new("ShaderNodeTexCoord")
        sc = nt.nodes.new("ShaderNodeVectorMath"); sc.operation = "SCALE"; sc.inputs["Scale"].default_value = 1 / tile
        it = nt.nodes.new("ShaderNodeTexImage"); it.image = img; it.projection = "BOX"; it.projection_blend = 0.2
        nt.links.new(tc.outputs["Object"], sc.inputs[0]); nt.links.new(sc.outputs["Vector"], it.inputs["Vector"])
        if tex.endswith("_n.png"):
            mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = "RGBA"; mix.blend_type = "MULTIPLY"
            mix.inputs["Factor"].default_value = 1
            mix.inputs["A"].default_value = (*[min(1, c / 0.75) for c in lin], 1)
            nt.links.new(it.outputs["Color"], mix.inputs["B"]); nt.links.new(mix.outputs["Result"], b.inputs["Base Color"])
        else:
            nt.links.new(it.outputs["Color"], b.inputs["Base Color"])
    if emit:
        b.inputs["Emission Color"].default_value = (*lin, 1)
        b.inputs["Emission Strength"].default_value = emit
    if alpha < 1:
        b.inputs["Alpha"].default_value = alpha
        try:
            mat.surface_render_method = "BLENDED"
        except Exception:
            pass
    mat.diffuse_color = (*lin, alpha)
    mat["l4_sem"] = sem or ("neon" if emit >= 2 else "glass" if alpha < 1 else "metal" if metal > 0.5 else "prop")
    mat["l4_color"] = list(col)
    mat["l4_tex"] = tex or ""
    mat["l4_tile"] = tile
    mat["l4_alpha"] = alpha
    return mat


def M():
    return {
        "velvet": pmat("velvet_red", (120, 22, 30), 0.92, tex="tex_velvet_red_n.png", tile=0.5),
        "velvet_dark": pmat("velvet_oxblood", (74, 16, 24), 0.92, tex="tex_velvet_red_n.png", tile=0.5),
        "velvet_teal": pmat("velvet_teal", (20, 58, 62), 0.92, tex="tex_velvet_red_n.png", tile=0.5),
        "plastic_black": pmat("plastic_black", (22, 20, 22), 0.55),
        "metal_black": pmat("metal_black", (34, 30, 32), 0.4, 0.85),
        "chrome": pmat("chrome", (200, 198, 194), 0.18, 1.0),
        "brass": pmat("brass", (176, 132, 62), 0.3, 1.0),
        "steel": pmat("steel", (120, 122, 126), 0.45, 0.8),
        "red_enamel": pmat("red_enamel", (150, 16, 22), 0.35),
        "glass": pmat("glass", (180, 200, 205), 0.05, alpha=0.3),
        "neon_red": pmat("neon_red", (255, 40, 30), emit=8),
        "neon_amber": pmat("neon_amber", (255, 158, 84), emit=8),
        "screen": pmat("crt_screen", (40, 170, 190), emit=3, tex="art_arcade_screen.png", tile=1.0, sem="screen"),
        "cab_wood": pmat("cabinet_black", (26, 22, 24), 0.6, tex="tex_wood_door_n.png", tile=0.8),
        "marble": pmat("marble_black", (40, 36, 38), 0.25, tex="tex_marble_black_gold.png", tile=1.5, sem="marble"),
        "porcelain": pmat("porcelain", (228, 226, 218), 0.2),
        "cardboard": pmat("cardboard", (150, 112, 70), 0.9, tex="tex_cardboard.png", tile=0.8),
        "tabletop": pmat("tabletop", (30, 14, 16), 0.3),
        "extinguisher": pmat("extinguisher_red", (170, 14, 18), 0.3),
        "popcorn": pmat("popcorn", (238, 206, 120), 0.8),
        "wood": pmat("wood", (70, 38, 24), 0.6, tex="tex_wood_door_n.png", tile=1.0),
        "mop": pmat("mop_grey", (130, 128, 120), 0.95),
        "yellow": pmat("cart_yellow", (200, 160, 20), 0.5),
    }


# ---------------------------------------------------------------- modelling helpers
class Asset:
    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.mats = []

    def _mi(self, mat):
        if mat not in self.mats:
            self.mats.append(mat)
        return self.mats.index(mat)

    def _tag(self, geom, mat, smooth=False):
        mi = self._mi(mat)
        for f in [g for g in geom if isinstance(g, bmesh.types.BMFace)]:
            f.material_index = mi
            f.smooth = smooth

    def box(self, c, s, mat, bevel=0.0, seg=2):
        before = set(self.bm.faces)
        r = bmesh.ops.create_cube(self.bm, size=1.0)
        vs = r["verts"]
        bmesh.ops.scale(self.bm, vec=Vector(s), verts=vs)
        bmesh.ops.translate(self.bm, vec=Vector(c), verts=vs)
        if bevel > 0:
            edges = list({e for v in vs for e in v.link_edges})
            bmesh.ops.bevel(self.bm, geom=edges, offset=min(bevel, min(s) * 0.45), segments=seg,
                            affect="EDGES", profile=0.5)
        self._tag([f for f in self.bm.faces if f not in before], mat, smooth=bevel > 0)

    def cyl(self, c, r, h, mat, axis="Z", seg=20, r2=None, smooth=True):
        m = Matrix.Identity(4)
        if axis == "X":
            m = Matrix.Rotation(math.radians(90), 4, "Y")
        elif axis == "Y":
            m = Matrix.Rotation(math.radians(90), 4, "X")
        m = Matrix.Translation(Vector(c)) @ m
        res = bmesh.ops.create_cone(self.bm, cap_ends=True, segments=seg, radius1=r,
                                    radius2=r if r2 is None else r2, depth=h, matrix=m)
        faces = list({f for v in res["verts"] for f in v.link_faces})
        self._tag(faces, mat, smooth=smooth)

    def sphere(self, c, r, mat, seg=16):
        res = bmesh.ops.create_uvsphere(self.bm, u_segments=seg, v_segments=max(6, seg // 2), radius=r,
                                        matrix=Matrix.Translation(Vector(c)))
        self._tag(list({f for v in res["verts"] for f in v.link_faces}), mat, smooth=True)

    def torus(self, c, R, r, mat, seg=24, rseg=8):
        verts = []
        for i in range(seg):
            a = 2 * math.pi * i / seg
            ring = []
            for j in range(rseg):
                b = 2 * math.pi * j / rseg
                ring.append(self.bm.verts.new((c[0] + (R + r * math.cos(b)) * math.cos(a),
                                               c[1] + (R + r * math.cos(b)) * math.sin(a),
                                               c[2] + r * math.sin(b))))
            verts.append(ring)
        faces = []
        for i in range(seg):
            for j in range(rseg):
                faces.append(self.bm.faces.new((verts[i][j], verts[(i + 1) % seg][j],
                                                verts[(i + 1) % seg][(j + 1) % rseg], verts[i][(j + 1) % rseg])))
        self._tag(faces, mat, smooth=True)

    def finish(self):
        me = bpy.data.meshes.get("L4A_" + self.name)
        if me:
            me.clear_geometry(); me.materials.clear()
        else:
            me = bpy.data.meshes.new("L4A_" + self.name)
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        self.bm.to_mesh(me)
        self.bm.free()
        for m in self.mats:
            me.materials.append(m)
        me["l4_asset"] = self.name
        return me


# ---------------------------------------------------------------- assets (canonical, metres)
def a_seat(m, w, d, h, seat_h):
    """Cinema recliner: velvet seat + padded back, black shell, armrest with cupholder, foot. Two materials,
    so each of the 1188 seats is two MeshParts in Roblox."""
    a = Asset("CinemaSeat")
    a.box((0, -d * 0.12, seat_h * 0.75), (w * 0.82, d * 0.62, seat_h * 0.5), m["velvet"], bevel=0.05)
    a.box((0, d * 0.28, h * 0.62), (w * 0.84, d * 0.22, h * 0.72), m["velvet"], bevel=0.06)
    a.box((0, d * 0.4, h * 0.6), (w * 0.9, d * 0.08, h * 0.78), m["plastic_black"], bevel=0.02)
    a.box((0, -d * 0.1, seat_h * 0.32), (w * 0.8, d * 0.55, seat_h * 0.3), m["plastic_black"], bevel=0.02)
    ax = w * 0.46
    a.box((ax, 0, seat_h * 1.05), (w * 0.08, d * 0.78, 0.07), m["plastic_black"], bevel=0.02)
    a.box((ax, d * 0.05, seat_h * 0.55), (w * 0.06, d * 0.5, seat_h * 0.9), m["plastic_black"], bevel=0.015)
    a.cyl((ax, -d * 0.32, seat_h * 1.07), 0.045, 0.06, m["plastic_black"], seg=12)
    a.box((0, d * 0.1, 0.03), (w * 0.3, d * 0.3, 0.06), m["plastic_black"])
    a.box((0, d * 0.1, seat_h * 0.3), (0.08, 0.08, seat_h * 0.55), m["plastic_black"])
    return a.finish()


def a_arcade(m, w, d, h):
    """Fills the Studio cabinet block (w x d x h); the control deck juts out of the front like the original."""
    a = Asset("ArcadeCabinet")
    fy = -d / 2
    a.box((0, 0, h * 0.5), (w, d, h), m["cab_wood"], bevel=0.03)                     # cabinet block
    # screen and marquee stay just behind the Studio screen/marquee planes: Roblox lays the original
    # screen decals and marquee titles over them from invisible carriers
    a.box((0, fy - 0.004, h * 0.69), (w * 0.8, 0.012, h * 0.4), m["plastic_black"])      # bezel
    a.box((0, fy - 0.012, h * 0.69), (w * 0.72, 0.008, h * 0.33), m["screen"])           # CRT
    a.box((0, fy - 0.01, h * 0.94), (w * 0.9, 0.02, h * 0.1), m["neon_red"])             # marquee
    a.box((0, fy - d * 0.08, h * 0.42), (w * 0.75, d * 0.17, h * 0.09), m["metal_black"], bevel=0.02)  # controls
    for x in (-0.22, 0.22):
        a.cyl((x * w, fy - d * 0.1, h * 0.475), 0.035, 0.03, m["neon_amber"], seg=10)
        a.cyl((x * w - 0.14, fy - d * 0.12, h * 0.5), 0.02, 0.1, m["metal_black"], seg=8)
        a.sphere((x * w - 0.14, fy - d * 0.12, h * 0.55), 0.04, m["red_enamel"], seg=10)
    a.box((0, fy - 0.01, h * 0.2), (w * 0.3, 0.03, h * 0.2), m["metal_black"])          # coin door
    for x in (-0.06, 0.06):
        a.box((x * w, fy - 0.03, h * 0.24), (0.05, 0.02, 0.09), m["neon_red"])
    for x in (-1, 1):                                                                   # side trim
        a.box((x * (w / 2 + 0.005), 0, h * 0.1), (0.02, d * 0.96, 0.05), m["neon_red"])
    return a.finish()


def a_table(m, r, h):
    a = Asset("HighTable")
    a.cyl((0, 0, h - 0.025), r, 0.05, m["tabletop"], seg=28)
    a.cyl((0, 0, h - 0.055), r * 1.02, 0.02, m["brass"], seg=28)
    a.cyl((0, 0, h / 2), 0.045, h - 0.08, m["metal_black"], seg=12)
    a.cyl((0, 0, 0.02), r * 0.55, 0.04, m["metal_black"], seg=24, r2=r * 0.5)
    return a.finish()


def a_cafechair(m, w, d, h, seat_h):
    a = Asset("CafeChair")
    a.box((0, 0, seat_h), (w * 0.9, d * 0.9, 0.08), m["velvet_dark"], bevel=0.025)
    a.box((0, d * 0.42, seat_h + (h - seat_h) * 0.55), (w * 0.85, 0.06, (h - seat_h) * 0.8), m["velvet_dark"], bevel=0.02)
    for x in (-1, 1):
        for y in (-1, 1):
            a.cyl((x * w * 0.38, y * d * 0.38, seat_h / 2), 0.015, seat_h, m["brass"], seg=8)
    for x in (-1, 1):
        a.cyl((x * w * 0.38, d * 0.42, seat_h + (h - seat_h) / 2), 0.012, h - seat_h, m["brass"], seg=8)
    return a.finish()


def a_column(m, r, h, base_h, collar_z):
    a = Asset("MarbleColumn")
    a.cyl((0, 0, base_h / 2), r * 1.12, base_h, m["metal_black"], seg=32)
    a.cyl((0, 0, base_h + 0.05), r * 1.06, 0.1, m["brass"], seg=32)
    a.cyl((0, 0, base_h + (h - base_h) / 2), r, h - base_h, m["marble"], seg=32)
    a.cyl((0, 0, collar_z), r * 1.04, 0.07, m["neon_amber"], seg=32)
    a.cyl((0, 0, h - 0.2), r * 1.08, 0.4, m["metal_black"], seg=32)
    a.cyl((0, 0, h - 0.42), r * 1.05, 0.04, m["brass"], seg=32)
    return a.finish()


def a_popcorn(m, w, d, h):
    a = Asset("PopcornCase")
    a.box((0, 0, 0.14), (w * 0.98, d * 0.95, 0.28), m["red_enamel"], bevel=0.02)
    a.box((0, 0, 0.29), (w * 0.94, d * 0.86, 0.02), m["steel"])
    for x in (-1, 1):
        for y in (-1, 1):
            a.box((x * w * 0.47, y * d * 0.43, h * 0.5), (0.1, 0.1, h * 0.62), m["chrome"])
    a.box((0, 0, h * 0.5), (w * 0.93, d * 0.85, h * 0.6), m["glass"])
    a.box((0, 0, h * 0.86), (w, d, 0.28), m["red_enamel"], bevel=0.03)
    a.box((0, -d * 0.51, h * 0.95), (w * 0.96, 0.04, 0.42), m["neon_amber"])
    a.box((0, 0, h * 0.8), (w * 0.88, 0.06, 0.05), m["neon_amber"])
    a.cyl((0, 0, h * 0.62), 0.4, 0.42, m["steel"], seg=20, r2=0.32)
    a.cyl((0, 0, h * 0.72), 0.03, 0.4, m["steel"], seg=8)
    a.box((0, 0, 0.36), (w * 0.8, d * 0.6, 0.12), m["popcorn"], bevel=0.04)
    return a.finish()


def a_toilet(m, w, d, h):
    a = Asset("Toilet")
    a.box((0, d * 0.34, h * 0.62), (w * 0.8, d * 0.26, h * 0.42), m["porcelain"], bevel=0.04)
    a.cyl((0, -d * 0.02, h * 0.2), w * 0.24, h * 0.4, m["porcelain"], seg=20, r2=w * 0.2)
    a.cyl((0, -d * 0.08, h * 0.42), w * 0.36, h * 0.12, m["porcelain"], seg=24)
    a.torus((0, -d * 0.08, h * 0.49), w * 0.3, 0.025, m["plastic_black"], seg=24)
    a.box((w * 0.25, d * 0.2, h * 0.8), (0.1, 0.02, 0.025), m["chrome"])
    return a.finish()


def a_sink(m, w, d, h):
    a = Asset("Sink")
    a.box((0, d * 0.1, h * 0.8), (w, d * 0.8, h * 0.12), m["porcelain"], bevel=0.03)
    a.box((0, d * 0.05, h * 0.78), (w * 0.6, d * 0.5, h * 0.1), m["steel"])
    a.box((0, d * 0.35, h * 0.4), (w * 0.12, 0.08, h * 0.8), m["chrome"])
    a.cyl((0, d * 0.38, h * 0.92), 0.025, 0.2, m["chrome"], seg=10)
    a.cyl((0, d * 0.28, h * 1.01), 0.02, 0.2, m["chrome"], axis="Y", seg=10)
    for x in (-0.12, 0.12):
        a.cyl((x, d * 0.38, h * 0.9), 0.03, 0.04, m["chrome"], seg=10)
    return a.finish()


def a_box(m, w, d, h):
    a = Asset("StockBox")
    a.box((0, 0, h / 2), (w, d, h), m["cardboard"], bevel=0.01, seg=1)
    a.box((0, 0, h + 0.002), (0.08, d * 1.004, 0.004), m["plastic_black"])
    return a.finish()


def a_extinguisher(m, w, d, h):
    a = Asset("Extinguisher")
    a.cyl((0, 0, h * 0.42), w * 0.25, h * 0.8, m["extinguisher"], seg=18)
    a.sphere((0, 0, h * 0.82), w * 0.25, m["extinguisher"], seg=14)
    a.cyl((0, 0, h * 0.92), 0.03, 0.12, m["metal_black"], seg=10)
    a.box((0.06, 0, h * 0.97), (0.14, 0.03, 0.02), m["metal_black"])
    a.cyl((-w * 0.2, -0.02, h * 0.6), 0.012, h * 0.55, m["plastic_black"], seg=8)
    return a.finish()


def a_bench(m, w, d, h, seat_h, cushion, arms=False):
    a = Asset("LobbySofa" if arms else "LobbyBench")
    a.box((0, -d * 0.08, seat_h * 0.3), (w * 0.98, d * 0.8, seat_h * 0.6), m["metal_black"], bevel=0.02)
    a.box((0, -d * 0.08, seat_h * 0.8), (w * 0.96, d * 0.78, seat_h * 0.4), cushion, bevel=0.05)
    a.box((0, d * 0.38, (seat_h + h) / 2 * 0.95), (w * 0.96, d * 0.22, h - seat_h * 0.4), cushion, bevel=0.06)
    if arms:
        for x in (-1, 1):
            a.box((x * w * 0.47, 0, h * 0.4), (w * 0.06, d, h * 0.8), m["metal_black"], bevel=0.03)
    return a.finish()


def a_stool(m, r, h):
    a = Asset("ArcadeStool")
    a.cyl((0, 0, h - 0.04), r, 0.08, m["velvet_dark"], seg=20)
    a.cyl((0, 0, h / 2), 0.04, h, m["chrome"], seg=10)
    a.torus((0, 0, h * 0.35), r * 0.7, 0.012, m["chrome"])
    a.cyl((0, 0, 0.015), r * 0.8, 0.03, m["chrome"], seg=20)
    return a.finish()


def a_cart(m, w, d, h):
    a = Asset("JanitorCart")
    a.box((0, 0, h * 0.12), (w, d, 0.05), m["yellow"])
    a.box((0, 0, h * 0.55), (w, d, 0.05), m["yellow"])
    for x in (-1, 1):
        for y in (-1, 1):
            a.cyl((x * w * 0.45, y * d * 0.45, h * 0.35), 0.02, h * 0.6, m["steel"], seg=8)
            a.cyl((x * w * 0.42, y * d * 0.42, 0.05), 0.05, 0.04, m["plastic_black"], axis="X", seg=12)
    a.cyl((w * 0.2, 0, h * 0.3), w * 0.18, h * 0.3, m["yellow"], seg=16)
    a.box((-w * 0.2, 0, h * 0.72), (w * 0.3, d * 0.6, h * 0.3), m["cardboard"])
    a.box((0, d * 0.48, h * 0.8), (w, 0.03, 0.03), m["steel"])
    return a.finish()


# ---------------------------------------------------------------- placement
def coll(name):
    c = bpy.data.collections.get(name)
    if not c:
        c = bpy.data.collections.new(name)
        bpy.data.collections["L4 Cinema"].children.link(c)
    return c


def yaw_to(front):                   # rotation about Z that turns canonical -Y onto `front`
    f = Vector((front.x, front.y, 0))
    if f.length < 1e-6:
        return Matrix.Identity(3)
    f.normalize()
    return Matrix.Rotation(math.atan2(f.x, -f.y), 3, "Z")


def place(me, name, base, R, scale=(1, 1, 1), model=None, attrs=None, src=None):
    o = bpy.data.objects.new(name, me)
    o.matrix_world = Matrix.Translation(base) @ R.to_4x4() @ Matrix.Diagonal((*scale, 1))
    coll("L4 Props").objects.link(o)
    o["l4_prop"] = me["l4_asset"]
    o["l4_model"] = model or name
    if attrs:
        o["l4_attrs"] = json.dumps(attrs)
    if src is not None:
        o["l4_src"] = src
    return o


def away_from_wall(center, reach=6.0):
    """Horizontal direction pointing away from the nearest wall (ray-cast against the architecture)."""
    dg = bpy.context.evaluated_depsgraph_get()
    best, bdir = 1e9, Vector((0, -1, 0))
    for d in (Vector((1, 0, 0)), Vector((-1, 0, 0)), Vector((0, 1, 0)), Vector((0, -1, 0))):
        hit, loc, *_ = bpy.context.scene.ray_cast(dg, center, d, distance=reach)
        if hit and (loc - center).length < best:
            best, bdir = (loc - center).length, -d
    return bdir


def nearest(src_pts, dst_pts):
    a, b = np.array(src_pts), np.array(dst_pts)
    return [int(np.argmin(((b - p) ** 2).sum(1))) for p in a]


def build():
    c = bpy.data.collections.get("L4 Props")
    if c:
        for o in list(c.objects):
            bpy.data.objects.remove(o, do_unlink=True)
    m = M()
    n = 0

    # --- auditorium seats: pair each seat block with its nearest back block
    seats, backs = parts(r"_ChairSeat$"), parts(r"_ChairBack$")
    bi = nearest([p["cf"][:3] for _, p in seats], [p["cf"][:3] for _, p in backs])
    _, s0 = seats[0]; _, b0 = backs[bi[0]]
    floor0 = s0["cf"][1] - s0["s"][1] / 2
    w = 4.4 * S; d = (3.2 + 0.6) * S
    h = (b0["cf"][1] + b0["s"][1] / 2 - floor0) * S
    seat_me = a_seat(m, w, d, h, s0["s"][1] * S)
    for k, (i, p) in enumerate(seats):
        bp = backs[bi[k]][1]
        front = pos(p) - pos(bp)
        base = pos(p); base.z = (p["cf"][1] - p["s"][1] / 2) * S
        mid = (pos(p) + pos(bp)) / 2
        base.x, base.y = mid.x, mid.y
        place(seat_me, "CinemaSeat", base, yaw_to(front), model="Seat", src=i); n += 1

    # --- arcade cabinets
    arc_me = None
    for i, body in parts(r"^Arcade/Arcade(Left|Right)\d+_Body$"):
        pre = body["p"].rsplit("_", 1)[0]
        scr = next(p for _, p in parts("^" + re.escape(pre) + "_Screen$"))
        e = world_size(body)
        front = pos(scr) - pos(body)
        horiz = Vector((front.x, front.y, 0)).normalized()
        wdt = e.x if abs(horiz.y) > abs(horiz.x) else e.y
        dep = e.y if abs(horiz.y) > abs(horiz.x) else e.x
        hgt = e.z
        if arc_me is None:
            arc_me = a_arcade(m, wdt, dep, hgt); aw, ad, ah = wdt, dep, hgt
        base = pos(body); base.z -= e.z / 2
        place(arc_me, pre.split("/")[-1], base, yaw_to(horiz), (wdt / aw, dep / ad, hgt / ah),
              model=pre.split("/")[-1], attrs={"ArcadeCabinet": True}, src=i); n += 1

    # --- high tables (lobby, wall cafe, standing)
    tab_me = None
    feet = parts(r"Table(Foot)$")
    for i, top in parts(r"/(Lobby|WallCafe|Standing)TableTop$"):
        foot = min(feet, key=lambda fp: (Vector(fp[1]["cf"][:3]) - Vector(top["cf"][:3])).length)[1]
        floor = foot["cf"][1] - 0.15
        h = (top["cf"][1] + 0.15 - floor) * S
        r = top["s"][1] / 2 * S
        if tab_me is None:
            tab_me = a_table(m, r, h); th = h
        base = pos(top); base.z = floor * S
        place(tab_me, top["p"].rsplit("/", 1)[-1].replace("Top", ""), base, Matrix.Identity(3), (1, 1, h / th), src=i); n += 1

    # --- wall cafe chairs
    cbacks = parts(r"WallCafeChairBack$")
    ch_me = None
    for i, seat in parts(r"WallCafeChairSeat$"):
        bk = min(cbacks, key=lambda bp: (Vector(bp[1]["cf"][:3]) - Vector(seat["cf"][:3])).length)[1]
        floor = seat["cf"][1] - 0.4 - 1.5
        sh = (seat["cf"][1] - floor) * S
        hh = (bk["cf"][1] + bk["s"][1] / 2 - floor) * S
        if ch_me is None:
            ch_me = a_cafechair(m, 4 * S, 4 * S, hh, sh)
        base = pos(seat); base.z = floor * S
        place(ch_me, "WallCafeChair", base, yaw_to(pos(seat) - pos(bk)), src=i); n += 1

    # --- concourse columns
    col_me = None
    bases = parts(r"ConcourseColumnBase$")
    for i, colp in parts(r"/ConcourseColumn$"):
        bs = min(bases, key=lambda bp: (Vector(bp[1]["cf"][:3]) - Vector(colp["cf"][:3])).length)[1]
        floor = bs["cf"][1] - bs["s"][0] / 2
        top = colp["cf"][1] + colp["s"][0] / 2
        if col_me is None:
            col_me = a_column(m, colp["s"][1] / 2 * S, (top - floor) * S, bs["s"][0] * S, (59.02 - floor) * S)
        base = pos(colp); base.z = floor * S
        place(col_me, "ConcourseColumn", base, Matrix.Identity(3), src=i); n += 1

    # --- popcorn case (a Studio Model with Empty=true)
    pc = [p for _, p in parts(r"^Concession/PopcornCase/")]
    lo = np.min([np.array(p["cf"][:3]) - np.abs(np.array(p["cf"][3:]).reshape(3, 3)) @ np.array(p["s"]) / 2 for p in pc], 0)
    hi = np.max([np.array(p["cf"][:3]) + np.abs(np.array(p["cf"][3:]).reshape(3, 3)) @ np.array(p["s"]) / 2 for p in pc], 0)
    sign = next(p for p in pc if p["p"].endswith("CaseSign"))
    ctr = (lo + hi) / 2
    pme = a_popcorn(m, (hi[0] - lo[0]) * S, (hi[2] - lo[2]) * S, (hi[1] - lo[1]) * S)
    base = rb([ctr[0], lo[1], ctr[2]])
    place(pme, "PopcornCase", base, yaw_to(pos(sign) - rb(ctr)), model="PopcornCase", attrs={"Empty": True}); n += 1

    # --- restroom toilets and sinks (Studio Models, bounding boxes in `other`)
    t_me = s_me = None
    for o in OTHER:
        nm = o["p"].rsplit("/", 1)[-1]
        if o["c"] != "Model" or not re.match(r"^(Men|Women)_(Toilet|Sink)$", nm):
            continue
        bx, by, bz, sx, sy, sz = o["bb"]
        base = rb([bx, by - sy / 2, bz])
        mid = rb([bx, by, bz])
        front = away_from_wall(mid, 8)
        wdt, dep = (sx, sz) if abs(front.y) > abs(front.x) else (sz, sx)
        if nm.endswith("Toilet"):
            t_me = t_me or a_toilet(m, 2.2 * S * 1.6, 3.2 * S, 4 * S)
            place(t_me, nm, base, yaw_to(front), model=nm); n += 1
        else:
            s_me = s_me or a_sink(m, wdt * S, dep * S, sy * S)
            place(s_me, nm, base, yaw_to(front), model=nm); n += 1

    # --- stock boxes (keep their exact size and rotation)
    bx_me = None
    for i, body in parts(r"^Service/StockBox/Body$"):
        w, h, d = body["s"][0] * S, body["s"][1] * S, body["s"][2] * S
        if bx_me is None:
            bx_me = a_box(m, w, d, h); bw, bh, bd = w, h, d
        base = pos(body) - rot(body) @ Vector((0, 0, h / 2))
        place(bx_me, "StockBox", base, rot(body), (w / bw, d / bd, h / bh), model="StockBox", src=i); n += 1

    # --- extinguishers
    ex_me = None
    for i, p in parts(r"ServiceExtinguisher$"):
        e = world_size(p)
        ex_me = ex_me or a_extinguisher(m, 2.4 * S, 1.2 * S, 4.4 * S)
        base = pos(p); base.z -= e.z / 2
        place(ex_me, p["p"].rsplit("/", 1)[-1], base, yaw_to(away_from_wall(pos(p), 4)), src=i); n += 1

    # --- lobby bench(es) and sofa
    for kind, arms, cushion in (("Bench", False, m["velvet_teal"]), ("Sofa", True, m["velvet_teal"])):
        backs_ = parts(r"Lobby%sBack$" % kind)
        me = None
        for i, seat in parts(r"Lobby%sSeat$" % kind):
            bk = min(backs_, key=lambda bp: (Vector(bp[1]["cf"][:3]) - Vector(seat["cf"][:3])).length)[1]
            floor = 24.0
            wdt = seat["s"][0] * S + (8 * S if arms else 0)
            dep = (seat["s"][2] + bk["s"][2]) * S
            hh = (bk["cf"][1] + bk["s"][1] / 2 - floor) * S
            sh = (seat["cf"][1] + seat["s"][1] / 2 - floor) * S
            me = me or a_bench(m, wdt, dep, hh, sh, cushion, arms)
            mid = (pos(seat) + pos(bk)) / 2
            base = Vector((mid.x, mid.y, floor * S))
            place(me, "Lobby" + kind, base, yaw_to(pos(seat) - pos(bk)), src=i); n += 1

    # --- arcade stools
    st_me = None
    for i, p in parts(r"ArcadeStoolSeat$"):
        st_me = st_me or a_stool(m, p["s"][1] / 2 * S, (p["cf"][1] - 24) * S)
        base = pos(p); base.z = 24 * S
        place(st_me, "ArcadeStool", base, Matrix.Identity(3), src=i); n += 1

    # --- janitor cart (Studio Model)
    jc = next(o for o in OTHER if o["p"] == "Service/JanitorCart")
    bx, by, bz, sx, sy, sz = jc["bb"]
    cart = a_cart(m, sx * S, sz * S, sy * S)
    place(cart, "JanitorCart", rb([bx, by - sy / 2, bz]), Matrix.Identity(3), model="JanitorCart"); n += 1
    return n


n = build()
print("props placed", n)
