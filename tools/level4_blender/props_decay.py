# Level 4 cinema, package F: deterministic decay / abandoned multiplex dressing.
# Run slots.py first, then exec this file and call build_decay(). No build on import.
# Coordinates are original Studio studs: Blender=((X-23000)*.28,-Z*.28,Y*.28).
# Owns ONLY "L4 Decay" under "L4 Cinema". The layout and current scene are read-only.
#
# Facelift v3 (2026-10-01):
#   * Floor litter is 3D (owner point 1): instanced props of the Meshy meshes L4A_LitterPopcornSpill / LitterCups /
#     LitterPopcornPile / LitterPaper (meshy_specs.json; imported here when the mesh is missing and the GLB exists, else
#     a procedural stand-in mesh "L4F_LitterProxy_<asset>" of the same size is used). Every placement carries
#     obj["l4_prop"] = <asset> and obj["l4_col"] = "[]": NO collider. Clusters are ray-cast onto real floor (floor
#     material, flat under the whole footprint, nothing inside the litter volume, not inside a solid, clear of walls
#     and door swings). The flat popcorn/cup decals and the procedural loose cups are gone.
#   * Nothing of F stands in DROP_ZONES (Cinema 1's west side, walled off and deleted) or on SURFACE_DROP (surfaces
#     other packages delete or cut open: concession checker strip, staff-side checker, the new arcade/service doors).
#   * Every decal is verified on its real surface before it is built (centre, corners and edge midpoints hit a surface at
#     the decal plane, with a material that suits the decal), so nothing floats after a wall or ceiling change, and
#     near-identical overlapping decals are thinned out. Ceiling leak stains remain only on the Service ceiling;
#     clean starlight headliner decks carry no old ceiling-ring dressing.
import bpy
import bmesh as _fd_bmesh
import json as _fd_json
import math as _fd_math
import os as _fd_os
import random as _fd_random
import collections as _fd_collections
import numpy as _fd_np
from mathutils import Matrix as _FDMatrix, Vector as _FDVector
from mathutils.bvhtree import BVHTree as _FDBVH

_FD_HERE = r"G:\Roblox\MongoTV\tools\level4_blender"
_FD_TEX = r"G:\Blender\Level4_Cinema\textures\pbr"
_FD_S, _FD_OX = .28, 23000.0
_FD_SEED = 40930
_FD_UP = _fd_np.array((0., 1., 0.))

# (x0, x1, y0, y1, z0, z1) studs. Cinema 1's west side is walled off at X 22676 and deleted (owner points 12/13).
_FD_DROP_ZONES = (
    ("C1", (22600., 22676.5, -1e4, 1e4, -260., -20.)),
    ("C1NorthPassage", (22600., 22676.5, -1e4, 84., -21., .5)),
    ("WestPassage", (22600., 22647.5, -1e4, 84., 0., 101.)),
    ("CoreSouthGap", (22600., 22676.5, -1e4, 84., 97.5, 101.)),
    ("A1WestEntry", (22670., 22690., 40., 56., -142., -118.)),
)
# Surfaces other packages delete or cut open: a decal there would float, or hang in a doorway.
_FD_SURFACE_DROP = (
    ("ConcessionChecker", (22888., 23054., 23.5, 24.4, 124.5, 132.5)),  # P1: carpet only (floor decals)
    ("StaffChecker", (22878., 23122., 23.5, 24.4, 100.5, 125.5)),       # P3: carpet, counter 5 studs deep
    ("ArcadeDoor", (23185., 23199., 23.5, 38.5, 97., 105.)),            # P1/P5: new arcade opening
    ("ServiceDoor", (22852., 22876., 23.5, 37., 97., 105.)),            # P1/P5: narrowed service opening
)
_FD_NEW_DOORS = ((23187., 23197., 24., 37., 100., 102.), (22860., 22868., 24., 36., 100., 102.))

_FD_LITTER = ("LitterPopcornSpill", "LitterCups", "LitterPopcornPile", "LitterPaper")
_FD_LITTER_M = {"LitterPopcornSpill": .45, "LitterCups": .40, "LitterPopcornPile": .35, "LitterPaper": .40}
_FD_FLOOR_SEMS = {"carpet", "carpet_arcade", "tile", "concrete", "wall_dark", "marble", "granite"}
_FD_DENY = {"glass", "neon", "screen", "decal", "metal"}
# name, rects (x0, x1, z0, z1), highest floor top considered, clusters, loose singles,
# weights (PopcornSpill, Cups, PopcornPile, Paper)
_FD_LITTER_ZONES = (
    ("Lobby", ((22677, 23375, -19, 99),), 80, 14, 2, (2, 3, 2, 3)),
    ("ConcessionFront", ((22884, 23116, 113.5, 142),), 30, 10, 1, (4, 3, 3, 1)),
    ("Concession", ((22884, 23116, 142, 236),), 30, 6, 1, (3, 3, 2, 2)),
    ("A1", ((22679, 22853, -237, -22),), 80, 12, 1, (3, 3, 4, 1)),
    ("A2", ((22913, 23087, -237, -22),), 80, 12, 1, (3, 3, 4, 1)),
    ("A3", ((23147, 23321, -237, -22),), 80, 12, 1, (3, 3, 4, 1)),
    ("Arcade", ((23174, 23210, 116, 225),), 30, 8, 1, (.5, 3, .5, 4)),
    ("C2", ((22856, 22910, -238, -21),), 80, 4, 1, (1, 3, 1, 3)),
    ("C3", ((23090, 23144, -238, -21),), 80, 4, 1, (1, 3, 1, 3)),
    ("C4", ((23324, 23376, -238, -21),), 80, 4, 1, (1, 3, 1, 3)),
    ("Gallery", ((22677, 23374, -19, -1),), 100, 4, 0, (0, 2, 0, 5)),
    ("Restrooms", ((23270, 23302, 126, 166), (23311, 23343, 126, 166)), 30, 3, 0, (0, 0, 0, 1)),
    ("Service", ((22626, 22878, 103, 237),), 30, 4, 1, (0, 2, 0, 5)),
)
# Lobby props litter gathers around: name prefix, chance, cluster size range, ring (inner, outer) x footprint radius
_FD_ANCHORS = (("LobbyTable", .9, (1, 3), (.2, 1.2)), ("StandingTable", .8, (1, 3), (.2, 1.3)),
               ("WallCafeTable", .7, (1, 2), (.2, 1.3)), ("LobbyBench", 1., (2, 3), (.6, 1.6)),
               ("LobbySofa", 1., (2, 3), (.6, 1.6)), ("TrashBin", .75, (2, 4), (1.2, 3.)),
               ("QueueStanchion", .12, (1, 2), (1.5, 4.)))
# Fixed piles kept from v2: zone, x, z, floor top, items, wet cartons (solid, with a collider)
_FD_HEAPS = (("ConcessionFront", 22911, 136, 30, 3, False), ("Service", 22772, 166, 30, 2, True),
             ("Lobby", 23369, 94, 30, 3, False), ("Lobby", 23023, 95, 30, 3, False),
             ("Lobby", 23121, -16, 30, 3, False), ("Concession", 23113, 231, 30, 2, True),
             ("Service", 22629, 232, 30, 1, True), ("Service", 22871, 209, 30, 2, True),
             ("Arcade", 23198, 221, 30, 3, False), ("Gallery", 23043, -16, 100, 2, False),
             ("Gallery", 23270, -16, 100, 2, False))
_FD_CONE_SPOTS = ((23050, 83), (22780, 164), (22921, 144), (23312, 117))
_FD_BUCKET_SPOT = (22774, 158)


def _fd_b(p):
    return ((p[0] - _FD_OX) * _FD_S, -p[2] * _FD_S, p[1] * _FD_S)


def _fd_s(p):
    return _fd_np.array((p[0] / _FD_S + _FD_OX, p[2] / _FD_S, -p[1] / _FD_S))


def _fd_lin(c):
    c /= 255.
    return c / 12.92 if c <= .04045 else ((c + .055) / 1.055) ** 2.4


def _fd_solid(name, rgb, rough=.8, metal=0., sem="prop", rmat="SmoothPlastic"):
    m = bpy.data.materials.get("L4S_F_" + name)
    if m:
        return m
    m = bpy.data.materials.new("L4S_F_" + name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    col = tuple(_fd_lin(c) for c in rgb)
    b.inputs["Base Color"].default_value = (*col, 1.)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    m.diffuse_color = (*col, 1.)
    for k, v in dict(l4_sem=sem, l4_roblox=rmat, l4_color=list(rgb), l4_alpha=1., l4_tile=1.,
                     l4_uv="mesh", l4_tex="", l4_normal="", l4_rough="", l4_metal="", l4_emit=0.).items():
        m[k] = v
    return m


def _fd_decal(name, alpha=1.):
    """Reload own material so a later build sees maps generated since the previous build."""
    m = bpy.data.materials.get("L4S_DECAL_" + name) or bpy.data.materials.new("L4S_DECAL_" + name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    b = nt.nodes.new("ShaderNodeBsdfPrincipled")
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(b.outputs["BSDF"], out.inputs["Surface"])
    b.inputs["Base Color"].default_value = (.065, .045, .027, 1.)
    b.inputs["Roughness"].default_value = .91
    b.inputs["Alpha"].default_value = .25 * alpha
    uv = nt.nodes.new("ShaderNodeTexCoord").outputs["UV"]
    for suffix in ("albedo", "normal", "rough"):
        fname = "decal_" + name + "_" + suffix + ".png"
        path = _fd_os.path.join(_FD_TEX, fname)
        m[{"albedo": "l4_tex", "normal": "l4_normal", "rough": "l4_rough"}[suffix]] = fname
        if not _fd_os.path.isfile(path):
            continue
        im = bpy.data.images.get(fname) or bpy.data.images.load(path, check_existing=True)
        im.alpha_mode = "STRAIGHT"
        if suffix != "albedo":
            im.colorspace_settings.name = "Non-Color"
        tx = nt.nodes.new("ShaderNodeTexImage")
        tx.image = im
        tx.extension = "REPEAT" if name in ("rising_damp", "carpet_wear") else "CLIP"
        nt.links.new(uv, tx.inputs["Vector"])
        if suffix == "albedo":
            nt.links.new(tx.outputs["Color"], b.inputs["Base Color"])
            mul = nt.nodes.new("ShaderNodeMath")
            mul.operation = "MULTIPLY"
            mul.inputs[1].default_value = alpha
            nt.links.new(tx.outputs["Alpha"], mul.inputs[0])
            nt.links.new(mul.outputs[0], b.inputs["Alpha"])
        elif suffix == "normal":
            nm = nt.nodes.new("ShaderNodeNormalMap")
            nm.inputs["Strength"].default_value = .22 if name != "peeling_wallpaper" else .5
            nt.links.new(tx.outputs["Color"], nm.inputs["Color"])
            nt.links.new(nm.outputs["Normal"], b.inputs["Normal"])
        else:
            nt.links.new(tx.outputs["Color"], b.inputs["Roughness"])
    try:
        m.surface_render_method = "DITHERED"
    except (AttributeError, TypeError):
        if hasattr(m, "blend_method"):
            m.blend_method = "HASHED"
    m.use_backface_culling = False
    m.diffuse_color = (.11, .075, .045, alpha)
    for k, v in dict(l4_sem="decal", l4_roblox="SmoothPlastic", l4_alpha=alpha, l4_color=[255, 255, 255],
                     l4_tile=1., l4_uv="mesh", l4_metal="", l4_emit=0.).items():
        m[k] = v
    return m


def _fd_paper_reverse():
    # Root derives a kraft-coloured map with precisely the same torn alpha as the front.
    return _fd_decal("peeling_wallpaper_back")


def _fd_weather(m, stem, normal_strength=.2):
    """Use existing physical maps for colour wear; these same maps are recorded for export."""
    nt = m.node_tree
    b = nt.nodes.get("Principled BSDF")
    uv = nt.nodes.get("WeatherUV") or nt.nodes.new("ShaderNodeTexCoord")
    uv.name = "WeatherUV"
    for suffix in ("albedo", "rough", "normal"):
        fname = stem + "_" + suffix + ".png"
        path = _fd_os.path.join(_FD_TEX, fname)
        if not _fd_os.path.isfile(path):
            continue
        tx = nt.nodes.get("Weather_" + suffix) or nt.nodes.new("ShaderNodeTexImage")
        tx.name = "Weather_" + suffix
        tx.image = bpy.data.images.get(fname) or bpy.data.images.load(path)
        if suffix != "albedo":
            tx.image.colorspace_settings.name = "Non-Color"
        nt.links.new(uv.outputs["UV"], tx.inputs["Vector"])
        m[{"albedo": "l4_tex", "rough": "l4_rough", "normal": "l4_normal"}[suffix]] = fname
        if suffix == "albedo":
            mix = nt.nodes.get("WeatherTint") or nt.nodes.new("ShaderNodeMixRGB")
            mix.name = "WeatherTint"
            mix.blend_type = "MULTIPLY"
            mix.inputs[0].default_value = 1.
            mix.inputs[1].default_value = (*[_fd_lin(c) for c in m["l4_color"]], 1.)
            nt.links.new(tx.outputs["Color"], mix.inputs[2])
            nt.links.new(mix.outputs[0], b.inputs["Base Color"])
        elif suffix == "normal":
            nm = nt.nodes.get("WeatherNormal") or nt.nodes.new("ShaderNodeNormalMap")
            nm.name = "WeatherNormal"
            nm.inputs["Strength"].default_value = normal_strength
            nt.links.new(tx.outputs["Color"], nm.inputs["Color"])
            nt.links.new(nm.outputs["Normal"], b.inputs["Normal"])
        else:
            nt.links.new(tx.outputs["Color"], b.inputs["Roughness"])


class _FDGeo:
    """One small mesh accumulator; studs in, metres out. Every face has explicit UVs."""
    def __init__(self):
        self.v, self.f, self.uv, self.mi, self.smooth, self.mats = [], [], [], [], [], []

    def poly(self, pts, mat, uv=None, normal=None, smooth=False):
        pts = [tuple(float(q) for q in p) for p in pts]
        if uv is None:
            uv = [(0., 0.), (1., 0.), (1., 1.), (0., 1.)][:len(pts)] if len(pts) <= 4 else \
                [(.5 + .5 * _fd_math.cos(2 * _fd_math.pi * i / len(pts)),
                  .5 + .5 * _fd_math.sin(2 * _fd_math.pi * i / len(pts))) for i in range(len(pts))]
        if normal is not None:
            n = sum((_fd_np.cross(p, q) for p, q in zip(_fd_np.array(pts), _fd_np.roll(pts, -1, axis=0))), _fd_np.zeros(3))
            if _fd_np.dot(n, normal) < 0:
                pts, uv = pts[::-1], uv[::-1]
        if mat not in self.mats:
            self.mats.append(mat)
        start = len(self.v)
        self.v.extend(pts)
        self.f.append(tuple(range(start, start + len(pts))))
        self.uv.append(uv)
        self.mi.append(self.mats.index(mat))
        self.smooth.append(smooth)

    def box(self, c, size, mat, axes=None):
        c, h = _fd_np.array(c), _fd_np.array(size) / 2
        ax = _fd_np.eye(3) if axes is None else _fd_np.array(axes)
        for k in range(3):
            a, b = (k + 1) % 3, (k + 2) % 3
            for sg in (-1, 1):
                self.poly([c + sg * ax[k] * h[k] + sa * ax[a] * h[a] + sb * ax[b] * h[b]
                           for sa, sb in ((-1, -1), (1, -1), (1, 1), (-1, 1))], mat, normal=sg * ax[k])

    def tube(self, p, q, r0, r1, mat, n=12, caps=True):
        p, q = _fd_np.array(p), _fd_np.array(q)
        d = q - p
        d /= max(_fd_np.linalg.norm(d), 1.e-9)
        u = _fd_np.cross(d, (0, 1, 0) if abs(d[1]) < .9 else (1, 0, 0))
        u /= _fd_np.linalg.norm(u)
        v = _fd_np.cross(d, u)
        rows = [[c + r * (u * _fd_math.cos(2 * _fd_math.pi * k / n) + v * _fd_math.sin(2 * _fd_math.pi * k / n))
                 for k in range(n)] for c, r in ((p, r0), (q, r1))]
        for k in range(n):
            j = (k + 1) % n
            self.poly((rows[0][k], rows[0][j], rows[1][j], rows[1][k]), mat,
                      [(k / n, 0), ((k + 1) / n, 0), ((k + 1) / n, 1), (k / n, 1)],
                      normal=u * _fd_math.cos(2 * _fd_math.pi * (k + .5) / n) + v * _fd_math.sin(2 * _fd_math.pi * (k + .5) / n),
                      smooth=True)
        if caps:
            self.poly(rows[0], mat, normal=-d)
            self.poly(rows[1], mat, normal=d)

    def object(self, name, coll, kind, collider=False):
        if not self.f:
            return None
        o = bpy.data.objects.new(name, self.mesh(name + "_Mesh"))
        coll.objects.link(o)
        o["l4_pkg"], o["l4_kind"] = "F_decay", kind
        if collider:
            o["l4_collide"] = "bounds"
        return o

    def mesh(self, name):
        me = bpy.data.meshes.new(name)
        me.from_pydata([_fd_b(p) for p in self.v], [], self.f)
        for m in self.mats:
            me.materials.append(m)
        layer = me.uv_layers.new(name="UVMap")
        for p, uv, mi, sm in zip(me.polygons, self.uv, self.mi, self.smooth):
            p.material_index, p.use_smooth = mi, sm
            for li, tex in zip(p.loop_indices, uv):
                layer.data[li].uv = tex
        # Faces deliberately carry independent UV corners. Weld positions so smooth surfaces really
        # share vertex normals; bmesh preserves the separate UV corners at paper seams.
        bm = _fd_bmesh.new()
        bm.from_mesh(me)
        _fd_bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1.e-6)
        bm.to_mesh(me)
        bm.free()
        me.update()
        return me


def _fd_quad(c, u, v, width, height, mat, coll, name, kind):
    c, u, v = (_fd_np.array(p, float) for p in (c, u, v))
    g = _FDGeo()
    g.poly([c + a * u * width / 2 + b * v * height / 2 for a, b in ((-1, -1), (1, -1), (1, 1), (-1, 1))], mat,
           [(0, 0), (1, 0), (1, 1), (0, 1)])
    o = g.object(name, coll, kind)
    o["l4_decay_support"] = _fd_json.dumps([p.tolist() for p in (c, u, v)] + [width, height])
    return o


def _fd_cast(dg, origin, direction, distance):
    """-> (hit studs, normal studs frame, object, face index) or None."""
    hit, loc, n, fi, obj, _ = bpy.context.scene.ray_cast(dg, _fd_b(origin),
                                                      (direction[0], -direction[2], direction[1]), distance=distance * _FD_S)
    if not hit:
        return None
    return _fd_s(loc), _fd_np.array((n.x, n.z, -n.y)), obj, fi


_FD_SEMS = {}


def _fd_sem(dg, obj, fi):
    """l4_sem of the material on face `fi` of the evaluated object (None for non-mesh hits)."""
    rec = _FD_SEMS.get(obj.name)
    if rec is None:
        ev = obj.evaluated_get(dg).data
        rec = ()
        if hasattr(ev, "polygons"):
            mi = _fd_np.empty(len(ev.polygons), dtype=_fd_np.int32)
            ev.polygons.foreach_get("material_index", mi)
            rec = (mi, [s.material.get("l4_sem") if s.material else None for s in obj.material_slots])
        _FD_SEMS[obj.name] = rec
    if not rec or fi >= len(rec[0]):
        return None
    i = rec[0][fi]
    return rec[1][i] if i < len(rec[1]) else None


def _fd_in(p, zones):
    return next((name for name, (x0, x1, y0, y1, z0, z1) in zones
                 if x0 < p[0] < x1 and y0 < p[1] < y1 and z0 < p[2] < z1), None)


def _fd_dropped(p):
    return _fd_in(p, _FD_DROP_ZONES) or _fd_in(p, _FD_SURFACE_DROP)


def _fd_sem_ok(kind, sem):
    if kind == "peeling_wallpaper":
        return sem in ("plaster", "wall_dark")           # wallpaper only, never panels, tile or glass
    if kind in ("carpet_stains", "puddle_outline", "carpet_wear"):
        return sem in _FD_FLOOR_SEMS
    if kind == "water_streaks":
        return sem is not None and sem not in _FD_DENY | {"velvet", "acoustic"}
    return sem is not None and sem not in _FD_DENY


def _fd_settled(dg, kind, p, u, v, w, h):
    """Keep a quad only when its centre, corners and edge midpoints all have matching support behind the plane."""
    p, u, v = (_fd_np.asarray(q, float) for q in (p, u, v))
    n = _fd_np.cross(u, v)
    n /= max(_fd_np.linalg.norm(n), 1.e-9)
    corners = ((-1, -1), (1, -1), (1, 1), (-1, 1))
    if _fd_dropped(p) or any(_fd_dropped(p + u * a * w / 2 + v * b * h / 2) for a, b in corners):
        return False
    for a, b in ((0, 0),) + corners + ((0, -1), (1, 0), (0, 1), (-1, 0)):
        q = p + u * a * .995 * w / 2 + v * b * .995 * h / 2
        hit = _fd_cast(dg, q + n * .6, -n, 1.)
        ok = hit is not None and _fd_np.dot(hit[1], n) > .7 and abs(_fd_np.dot(hit[0] - q, n)) < .15
        if not (ok and _fd_sem_ok(kind, _fd_sem(dg, hit[2], hit[3]))):
            return False
    return True


def _fd_thin(rows, frac=.35):
    """Drop a decal when more than `frac` of it lies on an already kept decal of the same kind and plane."""
    groups, out = _fd_collections.defaultdict(list), []
    for row in rows:
        p, u, v, w, h = (_fd_np.asarray(q, float) if i < 3 else q for i, q in enumerate(row))
        n = _fd_np.cross(u, v)
        key = (tuple(_fd_np.round(n * 4).astype(int)), round(float(_fd_np.dot(p, n)) * 2))
        cu, cv = float(_fd_np.dot(p, u)), float(_fd_np.dot(p, v))
        mine = w * h
        if any(max(0., min(cu + w / 2, ku + kw / 2) - max(cu - w / 2, ku - kw / 2)) *
               max(0., min(cv + h / 2, kv + kh / 2) - max(cv - h / 2, kv - kh / 2)) > frac * min(mine, kw * kh)
               for ku, kv, kw, kh in groups[key]):
            continue
        groups[key].append((cu, cv, w, h))
        out.append(row)
    return out


def _fd_wall_hit(dg, pos, normal, reach=6):
    pos, normal = _fd_np.array(pos, float), _fd_np.array(normal, float)
    hit = _fd_cast(dg, pos + normal * reach, -normal, reach + 1)
    if hit and _fd_np.dot(hit[1], normal) > .7 and _fd_np.linalg.norm(hit[0] - pos) < 1.2:
        return hit[0] + normal * .018
    return None


def _fd_floor_hit(dg, x, y, z):
    hit = _fd_cast(dg, (x, y + 3, z), (0, -1, 0), 4)
    if hit and hit[1][1] > .8 and abs(hit[0][1] - y) < .6:
        return float(hit[0][1])
    return None


def _fd_measured():
    # Reuse package A's measured exposed-run planner. Loading its definitions never calls a builder.
    ns = {"__name__": "F_decay_readonly_plan", "__file__": _fd_os.path.join(_FD_HERE, "arch_detail.py")}
    exec(compile(open(ns["__file__"], encoding="utf-8").read(), ns["__file__"], "exec"), ns)
    walls, floors, ceilings = ns["classify"]()
    faces = ns["wall_faces"](walls)
    bases = ns["base_runs"](faces, floors)
    crowns = ns["crown_runs"](faces, ceilings)
    # Low wainscot is a separate facing below its plaster wall, not a second layer on that plaster.
    for i in ns["low_bands"]():
        if not ns["AXAL"][i]:
            continue
        lo, hi = ns["LO"][i], ns["HI"][i]
        a = 0 if hi[0] - lo[0] < hi[2] - lo[2] else 2
        h = 2 - a
        for s, c in ((-1, lo[a]), (1, hi[a])):
            fy = lo[1]
            for x0, x1 in ns["free"](a, s, c, h, lo[h], hi[h], fy + .1, fy + .5, .35, skip={i}):
                bases.append(((a, s, round(c, 3), round(fy, 3)), x0, x1, (i, -1)))
    return ns, bases, crowns


def _fd_weighted(rng, rows):
    return rng.choices(rows, weights=[r[2] - r[1] for r in rows], k=1)[0]


def _fd_surface_plan(dg, ns, bases, crowns, rng):
    plans = _fd_collections.defaultdict(list)
    # Bands tile horizontally in <=16-stud pieces. Every candidate is checked against the live mesh.
    seen = set()
    for key, x0, x1, info in bases:
        a, s, c, fy = key
        h = 2 - a
        if fy not in (24., 24.05, 24.1, 42., 72., 86.):
            continue
        strong = any(k in ns["PATH"][info[0]] for k in ("Service/", "Restrooms/", "Gallery"))
        height = rng.uniform(1.9, 3.) if strong else rng.uniform(.8, 1.7)
        n = _fd_np.eye(3)[a] * s
        u = _fd_np.cross(_FD_UP, n)
        for lo in _fd_np.arange(x0, x1, 16.):
            hi = min(lo + 16., x1)
            p = _fd_np.zeros(3)
            p[a], p[h], p[1] = c, (lo + hi) / 2, fy + .5 + height / 2
            hit = _fd_wall_hit(dg, p, n, 2)
            if hit is None:
                continue
            sig = tuple(round(q, 2) for q in hit)
            if sig in seen:
                continue
            seen.add(sig)
            plans["rising_damp"].append((hit, u, _FD_UP, hi - lo, height))
    # The gallery's waving south wall is built from rotated panels; continue the damp around its bends.
    for i in ns["low_bands"]():
        if ns["AXAL"][i]:
            continue
        p = ns["P"][i]
        c, rt, size = ns["CEN"][i], ns["ROT"][i], _fd_np.array(p["s"], float)
        a = 0 if size[0] < size[2] else 2
        h = 2 - a
        fy = float(c[1] - size[1] / 2)
        height = 2.5 if "Gallery" in p["p"] else 1.45
        length = float(size[h])
        for sg in (-1, 1):
            normal = rt[:, a] * sg
            axis = rt[:, h]
            for lo in _fd_np.arange(-length / 2, length / 2, 16.):
                hi = min(lo + 16., length / 2)
                pos = c + normal * size[a] / 2 + axis * (lo + hi) / 2
                pos[1] = fy + .5 + height / 2
                hit = _fd_wall_hit(dg, pos, normal, 2)
                if hit is not None:
                    plans["rising_damp"].append((hit, _fd_np.cross(_FD_UP, normal), _FD_UP, hi - lo, height))
    # Up to 200 candidates, weighted by crown-run length, with modest asymmetric dimensions.
    for _ in range(4000):
        if len(plans["water_streaks"]) == 200:
            break
        key, x0, x1, info = _fd_weighted(rng, crowns)
        a, s, c, cy = key
        h = 2 - a
        width = min(rng.uniform(2., 5.2), (x1 - x0) * .8)
        height = rng.uniform(4.5, 10.5) if cy > 52 else rng.uniform(3.5, 6.5)
        p = _fd_np.zeros(3)
        p[a], p[h], p[1] = c, rng.uniform(x0 + width / 2, x1 - width / 2), cy - 3.2 - height / 2
        n = _fd_np.eye(3)[a] * s
        hit = _fd_wall_hit(dg, p, n)
        if hit is not None:
            plans["water_streaks"].append((hit, _fd_np.cross(_FD_UP, n), _FD_UP, width, height))
    candidates = [r for r in crowns if any(ns["PATH"][r[3][0]].startswith(t) for t in
                  ("Concourse/", "Shell/", "C1/", "C2/", "C3/", "C4/", "HiddenService/Gallery")) and r[0][3] <= 99]
    for _ in range(5000):
        if len(plans["peeling_wallpaper"]) == 90:
            break
        key, x0, x1, info = _fd_weighted(rng, candidates)
        a, s, c, cy = key
        h = 2 - a
        w, ht = min(rng.uniform(1.2, 3.2), (x1 - x0) * .75), rng.uniform(2.8, 6.)
        floor = 86. if cy > 90 else 24.1
        ym = rng.uniform(floor + ht / 2 + 5, max(floor + ht / 2 + 5, cy - ht / 2 - 5))
        p = _fd_np.zeros(3)
        p[a], p[h], p[1] = c, rng.uniform(x0 + w / 2, x1 - w / 2), ym
        n = _fd_np.eye(3)[a] * s
        hit = _fd_wall_hit(dg, p, n)
        if hit is not None:
            plans["peeling_wallpaper"].append((hit, _fd_np.cross(_FD_UP, n), _FD_UP, w, ht))
    # Dedicated close-up sheet and drip beside the concessions sconce.
    hero = _fd_wall_hit(dg, (23022, 43, 99.7), (0, 0, -1))
    if hero is not None:
        plans["peeling_wallpaper"][0] = (hero, _fd_np.array((-1., 0., 0.)), _FD_UP, 2.8, 5.4)
        plans["water_streaks"][0] = (hero + _FD_UP * 5, _fd_np.array((-1., 0., 0.)), _FD_UP, 3.5, 7.)
    # Soot above every original wall lamp; tube/mount pairs identify the outward direction.
    parts = ns["P"]
    mounts = [p for p in parts if "SconceMount" in p["p"] or p["p"].endswith("_Sconce") or p["p"].endswith("/GallerySconce")]
    for p in mounts:
        pos = _fd_np.array(p["cf"][:3], float)
        rt = _fd_np.array(p["cf"][3:], float).reshape(3, 3)
        if "Mount" in p["p"]:
            tubes = [q for q in parts if q["p"] == p["p"].replace("Mount", "Tube")]
            if not tubes:
                continue
            tube = min(tubes, key=lambda q: _fd_np.linalg.norm(_fd_np.array(q["cf"][:3]) - pos))
            n = _fd_np.array(tube["cf"][:3]) - pos
            n[1] = 0
            n /= max(_fd_np.linalg.norm(n), 1.e-9)
        else:
            ax = 0 if p["s"][0] < p["s"][2] else 2
            n = rt[:, ax]
            # The inward-facing side is the one with a wall immediately behind it.
            for sg in (1, -1):
                if _fd_wall_hit(dg, pos + _FD_UP * (p["s"][1] / 2 + 1.4), n * sg, 2) is not None:
                    n *= sg
                    break
        pos[1] += p["s"][1] / 2 + 1.5
        hit = _fd_wall_hit(dg, pos, n, 2)
        if hit is not None:
            plans["soot_plume"].append((hit, _fd_np.cross(_FD_UP, n), _FD_UP, 2.2, 3.))
    # Corner webs include two offset wall quads; a radial silk fan spans the actual corner.
    for key, x0, x1, info in crowns:
        a, s, c, cy = key
        if x1 - x0 < 8 or rng.random() > .24:
            continue
        h = 2 - a
        n = _fd_np.eye(3)[a] * s
        for t in (x0 + 1.1, x1 - 1.1):
            p = _fd_np.zeros(3)
            p[a], p[h], p[1] = c, t, cy - 2.6
            hit = _fd_wall_hit(dg, p, n)
            if hit is not None:
                plans["cobweb"].append((hit, _fd_np.cross(_FD_UP, n), _FD_UP, 2.4, 2.8))
    return plans


def _fd_peel(p, u, v, w, h, mat, backing, coll, idx, rng):
    # The top remains glued; the lower edge curls through 120–200 degrees into the room.
    p, u, v = (_fd_np.array(q) for q in (p, u, v))
    n = _fd_np.cross(u, v)
    g = _FDGeo()
    nx, ny = 4, 8
    curl = rng.uniform(.25, .6)
    theta = rng.uniform(2.1, 3.4)
    grid = []
    for j in range(ny + 1):
        t = j / ny
        tc = max(0., (t - .58) / .42)
        yy = h / 2 - h * min(t, .58) - curl * _fd_math.sin(tc * theta)
        depth = .005 + curl * (1 - _fd_math.cos(tc * theta))
        grid.append([p + u * ((i / nx - .5) * w * (1 - .08 * t)) + v * yy + n *
                     (depth + .07 * _fd_math.sin(i * 1.8 + idx) * t * t) for i in range(nx + 1)])
    for j in range(ny):
        for i in range(nx):
            pts = [grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]]
            uv = [(i / nx, 1 - j / ny), ((i + 1) / nx, 1 - j / ny),
                  ((i + 1) / nx, 1 - (j + 1) / ny), (i / nx, 1 - (j + 1) / ny)]
            front, front_uv = pts[::-1], uv[::-1]
            local_n = sum((_fd_np.cross(a, b) for a, b in zip(front, front[1:] + front[:1])), _fd_np.zeros(3))
            local_n /= max(_fd_np.linalg.norm(local_n), 1.e-9)
            g.poly(front, mat, front_uv, smooth=True)
            g.poly([q - local_n * .006 for q in front[::-1]], backing, front_uv[::-1], smooth=True)
    o = g.object("L4F_Peel_%03d" % idx, coll, "peeling_wallpaper")
    o["l4_curl_studs"] = curl
    o["l4_decay_support"] = _fd_json.dumps([p.tolist(), u.tolist(), v.tolist(), w, h])
    return o


def _fd_puddle(x, fy, z, diameter, mat, coll, idx, rng, name="RoofLeak"):
    # Two extremely thin, slightly raised layers make the outline irregular and catch neon reflections.
    g = _FDGeo()
    n = 80
    phase = rng.uniform(0, 6.28)
    edge = []
    for k in range(n):
        a = 2 * _fd_math.pi * k / n
        r = diameter / 2 * (1 + .095 * _fd_math.sin(3 * a + phase) + .035 * _fd_math.sin(5 * a - phase))
        edge.append((x + r * _fd_math.cos(a), fy + .035, z + r * .7 * _fd_math.sin(a)))
    for k in range(n):
        j = (k + 1) % n
        g.poly(((x, fy + .04, z), edge[k], edge[j]), mat, normal=(0, 1, 0), smooth=True)
        g.poly((edge[k], (edge[k][0], fy + .015, edge[k][2]),
                (edge[j][0], fy + .015, edge[j][2]), edge[j]), mat, normal=(edge[k][0] - x, 0, edge[k][2] - z))
    return g.object("L4F_%s_Puddle_%02d" % (name, idx), coll, "puddle")


def _fd_cup(g, p, yaw, mat, rim, collapsed=False):
    # A slightly squeezed, dented paper shell, with a pale inner wall and a rolled lip.
    p = _fd_np.array(p)
    axis = _fd_np.array((_fd_math.cos(yaw), .15, _fd_math.sin(yaw))) if collapsed else _FD_UP.copy()
    axis /= _fd_np.linalg.norm(axis)
    q = p + axis * 1.15
    u = _fd_np.cross(axis, (0, 1, 0) if abs(axis[1]) < .9 else (1, 0, 0)); u /= _fd_np.linalg.norm(u)
    v = _fd_np.cross(axis, u)
    n = 20
    rings = []
    for t in (0., .5, 1.):
        row = []
        for k in range(n):
            a = 2 * _fd_math.pi * k / n
            dent = 1 + .065 * _fd_math.sin(3 * a + yaw) * t + .035 * _fd_math.sin(7 * a) * t
            squash = .89 if collapsed else .97
            row.append(p + axis * (1.15 * t) + (.32 + .12 * t) * dent * (u * _fd_math.cos(a) + v * squash * _fd_math.sin(a)))
        rings.append(row)
    for j in range(2):
        for k in range(n):
            kk = (k + 1) % n
            g.poly((rings[j][k], rings[j][kk], rings[j + 1][kk], rings[j + 1][k]), mat,
                   [(k / n, j / 2), ((k + 1) / n, j / 2), ((k + 1) / n, (j + 1) / 2), (k / n, (j + 1) / 2)], smooth=True)
    inner = [[c - (q - p) * .025 / 1.15 - (c - p - axis * t * 1.15) * .04 for c in row]
             for row, t in ((rings[0], 0.), (rings[2], 1.))]
    for k in range(n):
        kk = (k + 1) % n
        g.poly((inner[0][kk], inner[0][k], inner[1][k], inner[1][kk]), rim, smooth=True)
    for k in range(n):
        kk = (k + 1) % n
        g.poly((rings[2][k], rings[2][kk], inner[1][kk], inner[1][k]), rim, smooth=True)
    g.poly(inner[0], rim, normal=axis)
    g.poly(rings[0], mat, normal=-axis)


def _fd_kernel(g, p, size, mat, rng):
    # A rounded, irregular popped kernel with six shallow lobes, smooth shared normals.
    p = _fd_np.array(p)
    size *= .5
    x, y, z = size, size * rng.uniform(.55, .8), size * rng.uniform(.7, 1.1)
    n, phase = 8, rng.uniform(0, 6.28)
    rows = []
    for j in range(1, 4):
        lat = _fd_math.pi * j / 4
        row = []
        for k in range(n):
            a = 2 * _fd_math.pi * k / n
            r = 1 + .15 * _fd_math.sin(3 * a + phase) * _fd_math.sin(lat) + .055 * _fd_math.cos(5 * a) * _fd_math.sin(2 * lat)
            row.append(p + (x * r * _fd_math.sin(lat) * _fd_math.cos(a), y * r * _fd_math.cos(lat), z * r * _fd_math.sin(lat) * _fd_math.sin(a)))
        rows.append(row)
    for k in range(n):
        kk = (k + 1) % n
        g.poly((p + (0, y, 0), rows[0][k], rows[0][kk]), mat, normal=(0, 1, 0), smooth=True)
        g.poly((p - (0, y, 0), rows[2][kk], rows[2][k]), mat, normal=(0, -1, 0), smooth=True)
        for j in range(2):
            g.poly((rows[j][k], rows[j + 1][k], rows[j + 1][kk], rows[j][kk]), mat,
                   normal=(rows[j][k] - p), smooth=True)


def _fd_carton(x, fy, z, coll, idx, carton):
    """Wet collapsed carton with skewed half-open flaps. Solid: its body (not the flaps) is a collider."""
    g = _FDGeo()
    g.box((x - .5, fy + .7, z), (2.7, 1.3, 1.9), carton)
    for sg in (-1, 1):
        g.poly(((x - 1.85, fy + 1.35, z + sg * .95), (x + .85, fy + 1.35, z + sg * .95),
                (x + .85, fy + .98, z + sg * 1.8), (x - 1.85, fy + 1.02, z + sg * 1.8)), carton)
    o = g.object("L4F_WetCarton_%02d" % idx, coll, "carton")
    c = _fd_b((x - .5, fy + .7, z))
    o["l4_col"] = _fd_json.dumps([[round(c[0], 4), round(c[1], 4), round(c[2], 4),
                                   round(2.7 * _FD_S, 4), round(1.9 * _FD_S, 4), round(1.3 * _FD_S, 4)]])
    return o


# ---------------------------------------------------------------- 3D floor litter
def _fd_crumple(g, c, r, mat, rng):
    """Crumpled paper ball: a jittered, faceted sphere."""
    c = _fd_np.array(c, float)
    lat, lon = 5, 8
    rows = [[c + r * rng.uniform(.72, 1.12) * _fd_np.array((_fd_math.sin(t) * _fd_math.cos(a), .85 * _fd_math.cos(t),
                                                            _fd_math.sin(t) * _fd_math.sin(a)))
             for a in (2 * _fd_math.pi * (k + .5 * (i % 2)) / lon for k in range(lon))]
            for i, t in ((i, _fd_math.pi * i / lat) for i in range(1, lat))]
    top, bot = c + (0, r * .85, 0), c - (0, r * .8, 0)
    for k in range(lon):
        kk = (k + 1) % lon
        for tri in ((top, rows[0][kk], rows[0][k]), (bot, rows[-1][k], rows[-1][kk])):
            g.poly(tri, mat, normal=sum(tri) / 3 - c)
        for j in range(lat - 2):
            for tri in ((rows[j][k], rows[j][kk], rows[j + 1][kk]), (rows[j][k], rows[j + 1][kk], rows[j + 1][k])):
                g.poly(tri, mat, normal=sum(tri) / 3 - c)


def _fd_flat(g, c, yaw, w, d, mat, bend=.04):
    """A ticket stub / torn flyer lying on the floor, creased once across the middle."""
    c = _fd_np.array(c, float)
    u = _fd_np.array((_fd_math.cos(yaw), 0, _fd_math.sin(yaw))) * w / 2
    v = _fd_np.array((-_fd_math.sin(yaw), 0, _fd_math.cos(yaw))) * d / 2
    m = _fd_np.array((0, bend, 0))
    g.poly((c - u - v, c - v + m, c + v + m, c - u + v), mat, [(0, 0), (.5, 0), (.5, 1), (0, 1)], normal=(0, 1, 0))
    g.poly((c - v + m, c + u - v, c + u + v, c + v + m), mat, [(.5, 0), (1, 0), (1, 1), (.5, 1)], normal=(0, 1, 0))


def _fd_proxy_geo(asset, mats, rng):
    """Procedural stand-in for a Meshy litter asset (built around stud X 23000, floor y 0; normalised later)."""
    popcorn, paper, rim, straw = mats
    g = _FDGeo()
    o = _fd_np.array((_FD_OX, 0., 0.))

    def kernels(n, cx, cz, rad, mound):
        for _ in range(n):
            a, r = rng.uniform(0, 2 * _fd_math.pi), rad * rng.random() ** .7
            s = rng.uniform(.17, .25)
            _fd_kernel(g, o + (cx + r * _fd_math.cos(a), s * .3 + mound * max(0., 1 - r / rad), cz + r * _fd_math.sin(a)),
                       s, popcorn, rng)
    if asset == "LitterPopcornSpill":
        _fd_cup(g, o + (-.62, .36, 0.), 0., paper, rim, collapsed=True)          # tipped bucket, mouth towards +X
        kernels(18, .85, 0., .6, .1)
    elif asset == "LitterCups":
        _fd_cup(g, o + (-.45, .34, -.3), .35, paper, rim, collapsed=True)
        _fd_cup(g, o + (.15, .34, .45), 2.7, paper, rim, collapsed=True)
        g.tube(o + (-.7, .03, .75), o + (.55, .03, .95), .03, .03, straw, n=5)
        g.poly([o + (.75 + .36 * _fd_math.cos(a), .02, -.45 + .36 * _fd_math.sin(a))
                for a in (2 * _fd_math.pi * k / 14 for k in range(14))], rim, normal=(0, 1, 0))
    elif asset == "LitterPopcornPile":
        kernels(24, 0., 0., .75, .3)
    else:
        _fd_crumple(g, o + (-.3, .27, .05), .32, rim, rng)
        _fd_flat(g, o + (.35, .012, -.25), .5, .62, .26, rim)
        _fd_flat(g, o + (.2, .02, .35), 2.1, .55, .24, paper, .03)
        _fd_crumple(g, o + (.7, .1, .2), .12, straw, rng)                       # balled candy wrapper
    return g


def _fd_normalize(g, longest):
    """Scale uniformly to `longest` studs on the longest axis; footprint centred on X 23000 / Z 0, bottom at y 0."""
    v = _fd_np.array(g.v, float)
    lo, hi = v.min(0), v.max(0)
    c = _fd_np.array(((lo[0] + hi[0]) / 2, lo[1], (lo[2] + hi[2]) / 2))
    g.v = [tuple(q) for q in (v - c) * (longest / max(hi - lo)) + (_FD_OX, 0., 0.)]


def _fd_litter_meshes(mats):
    """-> {asset: mesh}: the Meshy mesh L4A_<asset> (imported from its GLB when missing), else a stand-in mesh."""
    path = _fd_os.path.join(_FD_HERE, "meshy_specs.json")
    specs = {s["asset"]: s for s in _fd_json.load(open(path, encoding="utf-8")) if s["asset"] in _FD_LITTER}
    need = [s for a, s in specs.items() if bpy.data.meshes.get("L4A_" + a) is None and _fd_os.path.isfile(s["glb"])]
    if need:
        imp = _fd_os.path.join(_FD_HERE, "import_meshy.py")
        exec(compile(open(imp, encoding="utf-8").read(), imp, "exec"), {"SPEC": need, "__name__": "f_meshy", "__file__": imp})
    out = {}
    for i, a in enumerate(_FD_LITTER):
        me = bpy.data.meshes.get("L4A_" + a)
        if me is None:
            g = _fd_proxy_geo(a, mats, _fd_random.Random(_FD_SEED + i))
            _fd_normalize(g, _FD_LITTER_M[a] / _FD_S)
            me = g.mesh("L4F_LitterProxy_" + a)
            me["l4_asset"] = a
        if not me.get("l4_litter_cleaned"):
            bm = _fd_bmesh.new()
            bm.from_mesh(me)
            _fd_bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
            # UV corners survive welding; shared positions give the tiny kernels smooth normals at this budget.
            _fd_bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1.e-6)
            bm.to_mesh(me)
            bm.free()
            me["l4_litter_cleaned"] = True
        # Decimation can move the imported bottom below zero and grow its bounds. Refit THIS litter mesh only.
        co = _fd_np.empty(len(me.vertices) * 3)
        me.vertices.foreach_get("co", co)
        co = co.reshape(-1, 3)
        lo, hi = co.min(0), co.max(0)
        base = _FDVector(((lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, lo[2]))
        scale = _FD_LITTER_M[a] / max(hi - lo)
        if base.length > 1.e-6 or abs(scale - 1.) > 1.e-6:
            me.transform(_FDMatrix.Scale(scale, 4) @ _FDMatrix.Translation(-base))
        if me.name.startswith("L4A_"):
            me.shade_smooth()
            me.set_sharp_from_angle(angle=_fd_math.radians(specs.get(a, {}).get("sharp_angle", 75)))
        me["l4_col"] = "[]"
        out[a] = me
    return out


def _fd_dims(me):
    """(footprint radius, height) in studs of an asset mesh (metres, origin bottom-centre, Z up)."""
    co = _fd_np.empty(len(me.vertices) * 3)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    return float(_fd_np.hypot(co[:, 0], co[:, 1]).max() / _FD_S), float(co[:, 2].max() / _FD_S)


class _FDSpots:
    """Floor spots for loose litter: real floor material, flat under the whole footprint, an empty litter volume, not
    inside a solid, clear of walls, door swings and the removed zones."""

    def __init__(self, dg, ns, meshes=None):
        self.dg = dg
        self.meshes, self.geometry = meshes or {}, {}
        root = bpy.data.collections["L4 Cinema"]
        self.obstacles, boxes = [], []
        for o in root.all_objects:
            if o.type != "MESH" or o.hide_render or o.get("l4_kind") in ("litter", "puddle", "star", "stars"):
                continue
            sems = {m.get("l4_sem") for m in o.data.materials if m}
            if sems and sems <= {"decal", "neon"}:
                continue
            ev = o.evaluated_get(dg)
            v = _fd_np.array([ev.matrix_world @ _FDVector(p) for p in ev.bound_box])
            self.obstacles.append(o)
            boxes.append((v.min(0), v.max(0)))
        self.ob_lo = _fd_np.array([b[0] for b in boxes])
        self.ob_hi = _fd_np.array([b[1] for b in boxes])
        idx = [i for i, p in enumerate(ns["P"]) if "Level4V4Floor" in (p.get("tags") or []) and ns["AXAL"][i]]
        self.lo, self.hi = ns["LO"][idx], ns["HI"][idx]
        doors = list(_FD_NEW_DOORS)
        for i, p in enumerate(ns["P"]):
            if "Level4V4Doorway" in (p.get("tags") or []) or (p["p"].startswith("AutomaticDoors/") and p["p"].endswith("_Leaf")):
                lo, hi = ns["LO"][i], ns["HI"][i]
                doors.append((lo[0], hi[0], lo[1], hi[1], lo[2], hi[2]))
        self.swing = []
        for x0, x1, y0, y1, z0, z1 in doors:            # a leaf as wide as the opening swings into either side
            w = max(x1 - x0, z1 - z0)
            ex, ez = (.8, w + 1.2) if x1 - x0 >= z1 - z0 else (w + 1.2, .8)
            self.swing.append((x0 - ex, x1 + ex, y0 - 1.5, y0 + 4., z0 - ez, z1 + ez))
        self.rejects = _fd_collections.Counter()

    def floor_y(self, x, z, ymax):
        m = (self.lo[:, 0] <= x) & (x <= self.hi[:, 0]) & (self.lo[:, 2] <= z) & (z <= self.hi[:, 2]) & (self.hi[:, 1] <= ymax)
        return float(self.hi[m, 1].max()) if m.any() else None

    def _no(self, why):
        self.rejects[why] += 1

    def spot(self, x, z, ymax, r, h):
        """Floor height for a litter item of footprint radius r and height h at (x, z), or None."""
        dg = self.dg
        fe = self.floor_y(x, z, ymax)
        if fe is None or _fd_dropped((x, fe + .05, z)) or any(
                _fd_dropped((x + r * _fd_math.cos(a), fe + .05, z + r * _fd_math.sin(a)))
                for a in (k * _fd_math.pi / 4 for k in range(8))):
            return self._no("zone")
        if any(x0 - r < x < x1 + r and y0 < fe < y1 and z0 - r < z < z1 + r for x0, x1, y0, y1, z0, z1 in self.swing):
            return self._no("door swing")
        hit = _fd_cast(dg, (x, fe + 1.3, z), (0, -1, 0), 2.)
        if hit is None or hit[1][1] < .97 or abs(hit[0][1] - fe) > .35:
            return self._no("covered")
        if _fd_sem(dg, hit[2], hit[3]) not in _FD_FLOOR_SEMS:
            return self._no("not floor")
        fy = float(hit[0][1])
        for k in range(9):                              # flat floor under the rim, nothing in the litter volume
            a = k * _fd_math.pi / 4
            px, pz = (x + r * _fd_math.cos(a), z + r * _fd_math.sin(a)) if k < 8 else (x, z)
            q = _fd_cast(dg, (px, fy + h + .15, pz), (0, -1, 0), h + .5)
            if q is None or q[1][1] < .95 or abs(q[0][1] - fy) > .12:
                return self._no("footprint")
        for k in range(8):                              # thin uprights between the rim samples: legs, poles, walls
            a = (k + .5) * _fd_math.pi / 4
            if _fd_cast(dg, (x, fy + .3, z), (_fd_math.cos(a), 0, _fd_math.sin(a)), r + .25):
                return self._no("upright")
        up = _fd_cast(dg, (x, fy + .04, z), (0, 1, 0), 9.)
        if up is not None and (up[0][1] - fy < h + .25 or up[1][1] > .2):   # low overhang, or a back face: inside a solid
            return self._no("overhead")
        return fy

    def clear_mesh(self, asset, x, fy, z, yaw, scale):
        """Native triangle overlap catches thin seat arms/prop edges missed by the cheap footprint rays."""
        me = self.meshes[asset]
        M = _FDMatrix.Translation(_fd_b((x, fy, z))) @ _FDMatrix.Rotation(yaw, 4, "Z") @ _FDMatrix.Scale(scale, 4)
        v = _fd_np.array([M @ p.co for p in me.vertices])
        lo, hi = v.min(0), v.max(0)
        ids = _fd_np.flatnonzero(((self.ob_hi > lo + 1.e-6) & (self.ob_lo < hi - 1.e-6)).all(1))
        tree = None
        for j in ids:
            if self.ob_hi[j, 2] <= fy * _FD_S + .0005:
                continue
            if tree is None:
                tree = _FDBVH.FromPolygons(v.tolist(), [p.vertices[:] for p in me.polygons], epsilon=0.)
            o = self.obstacles[j]
            if o.name not in self.geometry:
                ev = o.evaluated_get(self.dg)
                points = _fd_np.array([ev.matrix_world @ p.co for p in ev.data.vertices])
                faces = [p.vertices[:] for p in ev.data.polygons]
                self.geometry[o.name] = points, faces, _FDBVH.FromPolygons(points.tolist(), faces, epsilon=0.)
            points, faces, other = self.geometry[o.name]
            for _, face in tree.overlap(other):
                if max(abs(points[i, 2] - fy * _FD_S) for i in faces[face]) >= .002:
                    self._no("mesh overlap")
                    return False
            # Surface intersections miss a disconnected component wholly inside a solid (e.g. a stage).
            inner = v[((v > self.ob_lo[j] + .001) & (v < self.ob_hi[j] - .001)).all(1)
                      & (v[:, 2] > fy * _FD_S + .002)]
            for p in inner:
                near, normal, _, _ = other.find_nearest(_FDVector(p))
                if near is not None and (_FDVector(p) - near).dot(normal) < -.001 and _fd_inside(other, p):
                    self._no("inside solid")
                    return False
        return True


def _fd_inside(tree, point):
    """Two non-axis parity rays distinguish a closed solid from open decorative faces."""
    for direction in ((_FDVector((1., .237, .171))).normalized(), (_FDVector((.137, 1., .193))).normalized()):
        p, hits = _FDVector(point), 0
        for _ in range(64):
            hit, _, _, _ = tree.ray_cast(p, direction, 500.)
            if hit is None:
                break
            hits += 1
            p = hit + direction * .00005
        else:
            return False
        if hits % 2 == 0:
            return False
    return True


def _fd_cluster(spots, dims, x, z, ymax, n, mix, rng, taken, jitter=0.):
    """Up to n litter items (asset, x, floor, z, yaw, radius, scale) around (x, z); [] when the first finds no spot."""
    out = []
    for i in range(n):
        asset = rng.choices(_FD_LITTER, weights=mix)[0]
        s = rng.uniform(.9, 1.1)
        r, h = dims[asset][0] * s, dims[asset][1] * s
        for _ in range(12 if i == 0 else 6):
            if i == 0:
                px, pz = x + rng.uniform(-jitter, jitter), z + rng.uniform(-jitter, jitter)
            else:
                b = out[rng.randrange(len(out))]
                a, d = rng.uniform(0, 2 * _fd_math.pi), b[5] + r + rng.uniform(-.05, .6)
                px, pz = b[1] + d * _fd_math.cos(a), b[3] + d * _fd_math.sin(a)
            if any(_fd_math.hypot(px - q[1], pz - q[3]) < r + q[5] + .05 for q in taken + out):
                continue
            fy = spots.spot(px, pz, ymax, r, h)
            if fy is not None:
                yaw = rng.uniform(0, 2 * _fd_math.pi)
                if spots.clear_mesh(asset, px, fy, pz, yaw, s):
                    out.append((asset, px, fy, pz, yaw, r, s))
                    break
        else:
            if i == 0:
                return []
    return out


def _fd_plan_litter(spots, dims, rng, anchors):
    """-> (clusters [(zone, kind, items)], cartons [(x, floor, z)]). Heaps first, then lobby props, then the zones."""
    zones = {z[0]: z for z in _FD_LITTER_ZONES}
    items, blockers, centres, clusters, cartons = [], [], [], [], []
    # Cleaning props are built after the ray plans; reserve their footprints before scattering litter.
    blockers.extend((None, x, 24., z, 0., 1.7, 1.) for x, z in _FD_CONE_SPOTS)
    bx, bz = _FD_BUCKET_SPOT
    blockers.append((None, bx, 24., bz, 0., 3., 1.))

    def size(lo=1, hi=4):
        return max(lo, min(hi, rng.choices((1, 2, 3, 4), (35, 40, 20, 5))[0]))

    def add(zone, kind, x, z, n, jitter=0., spacing=4.):
        if kind != "single" and sum(k != "single" for _, k, _ in clusters) >= 145:
            return False
        if any(_fd_math.hypot(x - cx, z - cz) < spacing for cx, cz in centres):
            return False
        got = _fd_cluster(spots, dims, x, z, zones[zone][2], n, zones[zone][5], rng, items + blockers, jitter)
        if got:
            items.extend(got)
            centres.append((got[0][1], got[0][3]))
            clusters.append((zone, kind, got))
        return bool(got)

    for zone, x, z, ymax, n, carton in _FD_HEAPS:
        if carton:                                      # the carton stands on the site, its litter beside it
            fy = spots.spot(x - .5, z, ymax, 1.9, 1.5)
            if fy is not None:
                cartons.append((x, fy, z))
                blockers.append((None, x - .5, fy, z, 0., 2., 1.))
            x += 2.8
        add(zone, "heap", x, z, n, jitter=1.5, spacing=0.)
    for name, o in anchors:
        spec = next((a for a in _FD_ANCHORS if name.startswith(a[0])), None)
        if spec is None or rng.random() > spec[1]:
            continue
        c = _fd_s(o.matrix_world.translation)
        rad = max(o.dimensions.x, o.dimensions.y) / 2 / _FD_S
        zone = next((zn for zn, rects, *_ in _FD_LITTER_ZONES if zn in ("Lobby", "ConcessionFront", "Concession")
                     and any(x0 <= c[0] <= x1 and z0 <= c[2] <= z1 for x0, x1, z0, z1 in rects)), None)
        if zone is None:
            continue
        for _ in range(8):
            a, d = rng.uniform(0, 2 * _fd_math.pi), rad * rng.uniform(*spec[3])
            if add(zone, "anchor:" + spec[0], c[0] + d * _fd_math.cos(a), c[2] + d * _fd_math.sin(a), size(*spec[2])):
                break
    for zone, rects, ymax, n_cl, n_one, mix in _FD_LITTER_ZONES:
        area = [(x1 - x0) * (z1 - z0) for x0, x1, z0, z1 in rects]
        for kind, target, spacing in (("cluster", n_cl, 4.), ("single", n_one, 2.5)):
            got = 0
            for _ in range(target * 80):
                if got >= target:
                    break
                x0, x1, z0, z1 = rng.choices(rects, area)[0]
                x, z = rng.uniform(x0, x1), rng.uniform(z0, z1)
                if zone == "Lobby" and rng.random() < .6:   # litter drifts to the walls; the middle stays walkable
                    z = rng.uniform(z0, z0 + 6) if rng.random() < .5 else rng.uniform(z1 - 6, z1)
                got += add(zone, kind, x, z, size() if kind == "cluster" else 1, spacing=spacing)
    return clusters, cartons


def _fd_cone(x, fy, z, coll, idx, yellow, dark):
    g = _FDGeo()
    g.box((x, fy + .13, z), (2.3, .26, 2.1), dark)
    # Native folded wet-floor sign, 3.3 studs tall, with a real hollow triangular section.
    for sg in (-1, 1):
        def facepoint(xx, yy):
            return (x + xx, fy + yy, z + sg * (.85 - (yy - .24) * .75 / 3.16 + .012))
        def shell(poly):
            pts = [facepoint(xx, yy) for xx, yy in poly]
            back = [tuple(_fd_np.array(p) - (0, 0, sg * .055)) for p in pts]
            uv = [((xx + .92) / 1.84, (yy - .24) / 3.16) for xx, yy in poly]
            g.poly(pts, yellow, uv, normal=(0, .2, sg))
            g.poly(back, yellow, uv, normal=(0, -.2, -sg))
            for k in range(len(pts)):
                j = (k + 1) % len(pts)
                g.poly((pts[k], pts[j], back[j], back[k]), yellow)
        # Four pieces leave an actual hand slot instead of a black painted rectangle.
        shell(((-.92, .24), (.92, .24), (.78, 2.94), (-.78, 2.94)))
        shell(((-.78, 2.94), (-.35, 2.94), (-.35, 3.25), (-.76, 3.25)))
        shell(((.35, 2.94), (.78, 2.94), (.76, 3.25), (.35, 3.25)))
        shell(((-.76, 3.25), (.76, 3.25), (.75, 3.4), (-.75, 3.4)))
        # Raised black hazard triangle on both outward faces; explicit decal-free warning icon.
        tri = [facepoint(-.51, 1.1), facepoint(.51, 1.1), facepoint(0, 2.18)]
        g.poly(tri, dark, normal=(0, .2, sg))
        # Yellow smaller triangle leaves the dark border visible.
        g.poly([tuple(_fd_np.array(facepoint(xx, yy)) + (0, 0, sg * .008)) for xx, yy in
                ((-.39, 1.18), (.39, 1.18), (0, 2.01))], yellow, normal=(0, .2, sg))
        g.tube(facepoint(-.06, 1.62), facepoint(.15, 1.75), .045, .045, dark, n=6)
        for a, b in (((.1, 1.64), (.25, 1.42)), ((.02, 1.61), (-.21, 1.41)), ((-.21, 1.41), (-.36, 1.4))):
            g.tube(facepoint(*a), facepoint(*b), .03, .03, dark, n=5)
    for sg in (-1, 1):
        g.tube((x + sg * .6, fy + 1.0, z - .67), (x + sg * .6, fy + 1.0, z + .67), .045, .045, dark, n=8)
    g.tube((x - .8, fy + 3.4, z), (x + .8, fy + 3.4, z), .07, .07, dark, n=12)
    o = g.object("L4F_WetFloorCone_%d" % idx, coll, "cone", True)
    o["l4_prop"] = "WetFloorCone"
    return o


def _fd_bucket(x, fy, z, coll, yellow, dark, steel, rng):
    g = _FDGeo()
    # Open rolled rim, thick bottom, inner wall and ridged wringer. Axis nearly horizontal: toppled.
    c = _fd_np.array((x + 2., fy + 1.2, z + .8))
    d = _fd_np.array((-.92, .11, -.38)); d /= _fd_np.linalg.norm(d)
    u = _fd_np.cross(d, _FD_UP); u /= _fd_np.linalg.norm(u)
    v = _fd_np.cross(d, u)
    n, length, radius = 32, 2.9, 1.08
    rings = []
    for t, r in ((0, radius * .83), (length, radius), (length, radius - .12), (.16, radius * .83 - .12)):
        rings.append([c + d * t + r * (u * _fd_math.cos(2 * _fd_math.pi * k / n) + v * _fd_math.sin(2 * _fd_math.pi * k / n)) for k in range(n)])
    for j in range(3):
        for k in range(n):
            kk = (k + 1) % n
            g.poly((rings[j][k], rings[j][kk], rings[j + 1][kk], rings[j + 1][k]), yellow,
                   [(k / n, j / 3), ((k + 1) / n, j / 3), ((k + 1) / n, (j + 1) / 3), (k / n, (j + 1) / 3)], smooth=True)
    g.poly(rings[0], yellow, normal=-d)
    g.poly(rings[3], dark, normal=d)
    g.tube(c + d * (length - .07), c + d * (length + .07), radius + .04, radius + .04, yellow, n=32, caps=False)
    wr = c + d * 1.8 + v * .98
    g.box(wr, (.65, .55, 1.3), yellow, axes=(d, v, u))
    for k in range(8):
        q = wr + u * (k * .14 - .5) + v * .3
        g.tube(q - d * .35, q + d * .35, .027, .027, dark, n=5)
    # Wire bail folded onto the ground beside the bucket.
    last = None
    for k in range(15):
        a = _fd_math.pi * k / 14
        q = c + d * 1.1 + u * (1.27 * _fd_math.cos(a)) + v * (1.05 * _fd_math.sin(a))
        if last is not None:
            g.tube(last, q, .035, .035, steel, n=6)
        last = q
    for sg in (-1, 1):
        q = c + d * .3 + u * sg * .8 - v * .6
        g.tube(q - u * .09, q + u * .09, .18, .18, dark, n=10)
    bottom = min(p[1] for p in g.v)
    g.v = [(x, y + fy - bottom, z) for x, y, z in g.v]
    o = g.object("L4F_ToppledMopBucket", coll, "bucket", True)
    o["l4_prop"] = "ToppledMopBucket"
    return o


def build_decay():
    """Build only F_decay, return verified object/triangle/collider and dressing counts."""
    root = bpy.data.collections.get("L4 Cinema")
    if root is None:
        raise RuntimeError("Load the Level 4 Cinema base scene before build_decay().")
    coll = bpy.data.collections.get("L4 Decay")
    if coll is None:
        coll = bpy.data.collections.new("L4 Decay")
        root.children.link(coll)
    elif coll.name not in root.children:
        root.children.link(coll)
    for o in list(coll.all_objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for me in list(bpy.data.meshes):
        if me.name.startswith("L4F_") and me.users == 0:
            bpy.data.meshes.remove(me)
    _FD_SEMS.clear()
    rng = _fd_random.Random(_FD_SEED)
    mats = {name: _fd_decal(name, .82 if name == "rising_damp" else 1.) for name in
            ("water_streaks", "rising_damp", "ceiling_rings", "carpet_stains", "puddle_outline",
             "peeling_wallpaper", "cobweb", "soot_plume", "carpet_wear")}
    backing = _fd_paper_reverse()
    mats["peeling_wallpaper"].use_backface_culling = True
    backing.use_backface_culling = True
    wet = _fd_solid("Water", (18, 14, 21), .05)
    b = wet.node_tree.nodes.get("Principled BSDF")
    b.inputs["IOR"].default_value = 1.333
    b.inputs["Coat Weight"].default_value = .7
    b.inputs["Coat Roughness"].default_value = .035
    yellow = _fd_solid("SafetyYellow", (194, 146, 24), .58)
    _fd_weather(yellow, "steel_painted", .1)
    dark = _fd_solid("RubberBlack", (19, 20, 20), .82, rmat="Rubber")
    steel = _fd_solid("BucketWire", (104, 102, 92), .43, .8, "metal", "Metal")
    paper = _fd_solid("CupPaper", (119, 31, 64), .88)
    rim = _fd_solid("WastePaper", (158, 148, 111), .93)
    popcorn = _fd_solid("Popcorn", (203, 178, 126), .9)
    straw = _fd_solid("Straw", (100, 175, 178), .72)
    carton = _fd_solid("WetCardboard", (76, 61, 43), .96)
    litter_me = _fd_litter_meshes((popcorn, paper, rim, straw))
    dims = {a: _fd_dims(me) for a, me in litter_me.items()}
    # Everything is planned against the fresh scene before any of our surfaces can intercept a ray.
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    ns, bases, crowns = _fd_measured()
    plans = _fd_surface_plan(dg, ns, bases, crowns, rng)
    planned = {k: len(v) for k, v in plans.items()}
    for kind in list(plans):
        plans[kind] = _fd_thin([row for row in plans[kind] if _fd_settled(dg, kind, *row)])
    # ceilings.py reads this literal (zone, x, z, floor y, v2 ceiling y) to reserve its stained ceiling cells.
    leaks = [("Concourse", 23045, 80, 24.05, 60), ("Concourse", 22744, 83, 24.05, 60),
             ("Concourse", 23142, 18, 24.05, 60), ("Concourse", 23300, 81, 24.05, 60),
             ("Concession", 22928, 151, 24.05, 52), ("Concession", 23083, 203, 24.05, 52),
             ("Gallery", 23040, -12, 86., 99), ("Gallery", 22738, -13, 86., 99), ("Gallery", 23278, -12, 86., 99),
             ("Service", 22772, 158, 24.05, 46.8), ("Service", 22688, 210, 24.05, 46.8),
             ("Men", 23281, 142, 24.05, 40.5), ("Women", 23332, 142, 24.05, 40.5),
             ("Arcade", 23196, 213, 24.05, 52)]
    leak_plans = []
    for zone, x, z, fy, _ in leaks:
        floor = _fd_floor_hit(dg, x, fy, z)
        if floor is None or _fd_in((x, fy + 1, z), _FD_DROP_ZONES):
            print("F_decay: roof leak skipped (no floor):", zone, x, z)
            continue
        dia = rng.uniform(4.8, 7.8)
        stain = None
        up = _fd_cast(dg, (x, floor + 6, z), (0, 1, 0), 90) if zone == "Service" else None
        if up is not None and up[1][1] < -.9:          # Service keeps its stained fluorescent ceiling
            p = (x, float(up[0][1]) - .017, z)
            if _fd_settled(dg, "ceiling_rings", p, (1, 0, 0), (0, 0, 1), dia * 1.15, dia):
                stain = p
        ring = _fd_settled(dg, "puddle_outline", (x, floor + .018, z), (1, 0, 0), (0, 0, -1), dia * 1.25, dia * .98)
        leak_plans.append((zone, x, z, floor, stain, ring, dia))
    spots = _FDSpots(dg, ns, litter_me)
    lobby = bpy.data.collections.get("L4 Props Lobby")
    anchors = sorted(((o.name, o) for o in (lobby.all_objects if lobby else ()) if o.type in ("MESH", "EMPTY")),
                     key=lambda t: t[0])
    clusters, cartons = _fd_plan_litter(spots, dims, rng, anchors)
    cleaning_floors = [_fd_floor_hit(dg, x, 24.05, z) for x, z in _FD_CONE_SPOTS]
    bx, bz = _FD_BUCKET_SPOT
    bucket_floor = _fd_floor_hit(dg, bx, 24.05, bz)
    # A spilt-soda stain under some of the clusters, never on its own.
    stains = []
    for zone, kind, got in clusters:
        if kind != "single" and rng.random() < .25:
            _, x, fy, z = got[0][:4]
            w = rng.uniform(1.8, 3.2)
            row = ((x + .3, fy + .016, z), (1., 0., 0.), (0., 0., -1.), w * 1.2, w)
            if _fd_settled(dg, "carpet_stains", *row):
                stains.append(row)
    # Worn desire lines from the street doors to the doors people actually used (C1 is gone; arcade door moved).
    lanes = [((23000., 226.), (23075., 101.))] + [((23075., 101.), p) for p in
             ((22883., -21.), (23117., -21.), (23351., -21.), (23192., 101.), (23288., 101.), (22864., 101.))]
    lane_plan = []
    lane_length = 0.
    for start, end in lanes:
        a, b = _fd_np.array(start), _fd_np.array(end)
        ln = float(_fd_np.linalg.norm(b - a)); lane_length += ln
        d = (b - a) / ln
        right = _fd_np.array((-d[1], 0, d[0]))
        along = _fd_np.array((d[0], 0, d[1]))
        pieces = int(_fd_math.ceil(ln / 16))
        for j in range(pieces):
            ll = min(16., ln - j * 16.)
            pos = a + d * (j * 16 + ll / 2)
            f = _fd_floor_hit(dg, pos[0], 24.05, pos[1])
            if f is not None and _fd_settled(dg, "carpet_wear", (pos[0], f + .017, pos[1]), right, along, 8., ll):
                lane_plan.append(((pos[0], f + .017, pos[1]), right, along, 8., ll))
    # Build the mesh collection only after planning.
    for kind, rows in plans.items():
        for idx, (p, u, v, w, h) in enumerate(rows):
            if kind == "peeling_wallpaper":
                _fd_peel(p, u, v, w, h, mats[kind], backing, coll, idx, rng)
            else:
                _fd_quad(p, u, v, w, h, mats[kind], coll, "L4F_%s_%04d" % (kind, idx), kind)
    for idx, (zone, x, z, fy, stain, ring, dia) in enumerate(leak_plans):
        if stain is not None:
            o = _fd_quad(stain, (1, 0, 0), (0, 0, 1), dia * 1.15, dia, mats["ceiling_rings"], coll,
                         "L4F_CeilingLeak_%02d_%s" % (idx, zone), "ceiling_rings")
            o["l4_leak_zone"] = zone
        if ring:
            _fd_quad((x, fy + .018, z), (1, 0, 0), (0, 0, -1), dia * 1.25, dia * .98, mats["puddle_outline"], coll,
                     "L4F_DarkLeakRing_%02d" % idx, "puddle_outline")
        _fd_puddle(x, fy, z, dia, wet, coll, idx, rng)
    for idx, row in enumerate(stains):
        _fd_quad(*row, mats["carpet_stains"], coll, "L4F_CarpetStain_%03d" % idx, "carpet_stains")
    for idx, row in enumerate(lane_plan):
        _fd_quad(*row, mats["carpet_wear"], coll, "L4F_WearLane_%03d" % idx, "carpet_wear")
    n = 0
    litter_zone, litter_asset = _fd_collections.Counter(), _fd_collections.Counter()
    for ci, (zone, kind, got) in enumerate(clusters):
        for asset, x, fy, z, yaw, _, s in got:
            o = bpy.data.objects.new("L4F_Litter_%03d_%s" % (n, asset), litter_me[asset])
            o.matrix_world = (_FDMatrix.Translation(_fd_b((x, fy, z))) @ _FDMatrix.Rotation(yaw, 4, "Z")
                              @ _FDMatrix.Scale(s, 4))
            coll.objects.link(o)
            o["l4_pkg"], o["l4_kind"] = "F_decay", "litter"
            o["l4_prop"], o["l4_model"] = asset, asset
            o["l4_col"] = "[]"                          # owner: floor litter has no collision
            o["l4_litter_zone"], o["l4_litter_cluster"] = zone, ci
            litter_zone[zone] += 1
            litter_asset[asset] += 1
            n += 1
    for idx, (x, fy, z) in enumerate(cartons):
        _fd_carton(x, fy, z, coll, idx, carton)
    for idx, (x, z) in enumerate(_FD_CONE_SPOTS):
        fy = cleaning_floors[idx]
        if fy is not None:
            _fd_cone(x, fy, z, coll, idx, yellow, dark)
    bx, bz = _FD_BUCKET_SPOT
    if bucket_floor is not None:
        _fd_bucket(bx, bucket_floor, bz, coll, yellow, dark, steel, rng)
    _fd_puddle(22776, 24.05, 159, 5.6, wet, coll, 14, rng, "BucketSpill")
    bpy.context.view_layer.update()
    objs = list(coll.all_objects)
    stats = _fd_collections.Counter(o.get("l4_kind", "unknown") for o in objs)
    tris = lambda me: sum(len(p.vertices) - 2 for p in me.polygons)
    unique = {o.data.name: o.data for o in objs if o.get("l4_prop")}
    stats["objects"] = len(objs)
    stats["triangles"] = sum(tris(o.data) for o in objs if not o.get("l4_prop")) + sum(map(tris, unique.values()))
    stats["colliders"] = sum(o.get("l4_collide") == "bounds" or o.get("l4_col", "[]") != "[]" for o in objs)
    stats["roof_leaks"] = len(leak_plans)
    stats["damp_run_studs"] = round(sum(row[3] for row in plans["rising_damp"]))
    stats["desire_line_studs"] = round(lane_length)
    stats["placed_wear_studs"] = round(sum(row[4] for row in lane_plan))
    stats["litter_clusters"] = sum(k != "single" for _, k, _ in clusters)
    stats["litter_singles"] = sum(k == "single" for _, k, _ in clusters)
    stats["litter_meshes"] = ",".join(sorted(me.name for me in unique.values() if me.name.startswith(("L4A_Litter", "L4F_Litter"))))
    print("F_decay planned decals:", planned)
    stats["decal_candidates"] = planned
    stats["decal_kept"] = {k: len(v) for k, v in plans.items()}
    stats["litter_per_zone"] = dict(litter_zone)
    stats["litter_per_asset"] = dict(litter_asset)
    stats["lights"] = 0
    print("F_decay litter per zone:", dict(litter_zone), "per asset:", dict(litter_asset),
          "spot rejects:", dict(spots.rejects))
    assert stats["triangles"] <= 60000, "F_decay triangle budget exceeded"
    if stats["litter_clusters"] < 100:
        print("WARNING F_decay: only %d litter clusters found room" % stats["litter_clusters"])
    for o in objs:
        assert o.type == "MESH" and o.data.uv_layers.active is not None, o.name
        c = _fd_s(o.matrix_world @ (sum((_FDVector(v) for v in o.bound_box), _FDVector()) / 8))
        assert not _fd_in(c, _FD_DROP_ZONES), "F_decay object in a removed zone: " + o.name
        if o.get("l4_kind") == "litter":
            assert not _fd_dropped(_fd_s(o.location) + (0, .05, 0)), o.name
            assert o.get("l4_prop") and o["l4_col"] == o.data["l4_col"] == "[]" and not o.get("l4_collide"), o.name
            continue
        assert all(-1.e-5 <= q <= 1.00001 for loop in o.data.uv_layers.active.data for q in loop.uv), o.name
        if o.get("l4_kind") in ("cone", "bucket", "carton"):
            assert o.get("l4_collide") == "bounds" or o.get("l4_col"), o.name
    print("F_decay:", dict(stats))
    return dict(stats)
