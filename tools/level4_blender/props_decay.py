# Level 4 cinema, package F: deterministic decay / abandoned multiplex dressing.
# Run slots.py first, then exec this file and call build_decay(). No build on import.
# Coordinates are original Studio studs: Blender=((X-23000)*.28,-Z*.28,Y*.28).
# Owns ONLY "L4 Decay" under "L4 Cinema". The layout and current scene are read-only.
import bpy
import bmesh as _fd_bmesh
import math as _fd_math
import os as _fd_os
import random as _fd_random
import collections as _fd_collections
import numpy as _fd_np
from mathutils import Vector as _FDVector

_FD_HERE = r"G:\Roblox\MongoTV\tools\level4_blender"
_FD_TEX = r"G:\Blender\Level4_Cinema\textures\pbr"
_FD_S, _FD_OX = .28, 23000.0
_FD_SEED = 40930
_FD_UP = _fd_np.array((0., 1., 0.))


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
        me = bpy.data.meshes.new(name + "_Mesh")
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
        o = bpy.data.objects.new(name, me)
        coll.objects.link(o)
        o["l4_pkg"], o["l4_kind"] = "F_decay", kind
        if collider:
            o["l4_collide"] = "bounds"
        return o


def _fd_quad(c, u, v, width, height, mat, coll, name, kind):
    c, u, v = (_fd_np.array(p, float) for p in (c, u, v))
    g = _FDGeo()
    g.poly([c + a * u * width / 2 + b * v * height / 2 for a, b in ((-1, -1), (1, -1), (1, 1), (-1, 1))], mat,
           [(0, 0), (1, 0), (1, 1), (0, 1)])
    return g.object(name, coll, kind)


def _fd_cast(dg, origin, direction, distance):
    hit, loc, n, _, obj, _ = bpy.context.scene.ray_cast(dg, _fd_b(origin),
                                                     (direction[0], -direction[2], direction[1]), distance=distance * _FD_S)
    if not hit:
        return None
    return _fd_s(loc), _fd_np.array((n.x, n.z, -n.y)), obj


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
    # Exactly 200, weighted by crown-run length, with modest asymmetric dimensions.
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


def _fd_rubbish(x, fy, z, coll, idx, rng, mats, hero=False, cartons=False):
    g = _FDGeo()
    popcorn, paper, rim, straw, carton = mats
    n = 130 if hero else rng.randint(8, 20)
    rad = 3.4 if hero else 1.7
    for _ in range(n):
        a, r = rng.uniform(0, 6.28), rad * rng.random() ** .6
        size = rng.uniform(.065, .14)
        _fd_kernel(g, (x + r * _fd_math.cos(a), fy + size * .65 + max(0, 1 - r / rad) * (.62 if hero else .09),
                       z + r * _fd_math.sin(a)), size, popcorn, rng)
    for _ in range(5 if hero else 2):
        yaw = rng.uniform(0, 6.28)
        p = (x + rng.uniform(-rad * .7, rad * .7), fy + .46, z + rng.uniform(-rad * .7, rad * .7))
        _fd_cup(g, p, yaw, paper, rim, collapsed=True)
        end = _fd_np.array(p) + (.7, .02, .6)
        g.tube(end, end + (1.2 * _fd_math.cos(yaw), .03, 1.2 * _fd_math.sin(yaw)), .025, .025, straw, n=5)
    for _ in range(5):
        xx, zz = x + rng.uniform(-rad, rad), z + rng.uniform(-rad, rad)
        g.poly(((xx, fy + .04, zz), (xx + .45, fy + .06, zz + .07), (xx + .4, fy + .03, zz + .38),
                (xx - .02, fy + .055, zz + .3)), rim, normal=(0, 1, 0))
    if cartons:
        # Wet carton has skewed flattened walls and half-open flaps.
        g.box((x - .5, fy + .7, z), (2.7, 1.3, 1.9), carton)
        for sg in (-1, 1):
            g.poly(((x - 1.85, fy + 1.35, z + sg * .95), (x + .85, fy + 1.35, z + sg * .95),
                    (x + .85, fy + .98, z + sg * 1.8), (x - 1.85, fy + 1.02, z + sg * 1.8)), carton)
    height = max(p[1] for p in g.v) - fy
    o = g.object("L4F_RubbishPile_%03d" % idx, coll, "rubbish", height >= 1.)
    o["l4_height_studs"] = float(height)
    return o


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
    rng = _fd_random.Random(_FD_SEED)
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    ns, bases, crowns = _fd_measured()
    plans = _fd_surface_plan(dg, ns, bases, crowns, rng)
    mats = {name: _fd_decal(name, .82 if name == "rising_damp" else 1.) for name in
            ("water_streaks", "rising_damp", "ceiling_rings", "carpet_stains", "puddle_outline",
             "peeling_wallpaper", "cobweb", "soot_plume", "popcorn_cups", "carpet_wear")}
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
    rubbish_mats = (popcorn, paper, rim, straw, carton)
    # All placements are planned against the fresh scene before our surfaces can intercept raycasts.
    leaks = [("Concourse", 23045, 80, 24.05, 60), ("Concourse", 22744, 83, 24.05, 60),
             ("Concourse", 23142, 18, 24.05, 60), ("Concourse", 23300, 81, 24.05, 60),
             ("Concession", 22928, 151, 24.05, 52), ("Concession", 23083, 203, 24.05, 52),
             ("Gallery", 23040, -12, 86., 99), ("Gallery", 22738, -13, 86., 99), ("Gallery", 23278, -12, 86., 99),
             ("Service", 22772, 158, 24.05, 46.8), ("Service", 22688, 210, 24.05, 46.8),
             ("Men", 23281, 142, 24.05, 40.5), ("Women", 23332, 142, 24.05, 40.5),
             ("Arcade", 23196, 213, 24.05, 52)]
    leak_plans = []
    for zone, x, z, fy, cy in leaks:
        floor = _fd_floor_hit(dg, x, fy, z)
        if floor is None:
            raise RuntimeError("F_decay roof leak has no verified floor: %s %.1f %.1f" % (zone, x, z))
        ceil = _fd_cast(dg, (x, cy - 3, z), (0, 1, 0), 5)
        if ceil is None or ceil[1][1] > -.6 or abs(ceil[0][1] - cy) > 2.1:
            raise RuntimeError("F_decay roof leak has no verified ceiling: " + zone)
        leak_plans.append((zone, x, z, floor, ceil[0][1], rng.uniform(4.8, 7.8)))
    scatter = []
    for zone, rect, count, fy in (("Concourse", (22626, 23374, -18, 98), 140, 24.05),
                                 ("Concession", (22883, 23117, 128, 234), 60, 24.05)):
        accepted = 0
        for _ in range(count * 30):
            if accepted == count:
                break
            x, z = rng.uniform(rect[0], rect[1]), rng.uniform(rect[2], rect[3])
            # Most debris hugs an edge; the remaining clusters interrupt the empty expanse sparingly.
            if accepted % 4 != 0:
                z = rng.uniform(rect[2] + 1, rect[2] + 5) if accepted % 2 else rng.uniform(rect[3] - 5, rect[3] - 1)
            f = _fd_floor_hit(dg, x, fy, z)
            if f is not None:
                scatter.append((zone, x, z, f, rng.uniform(1.8, 3.6)))
                accepted += 1
    # 54 actual aisle trails, using the measured top of each corresponding aisle tread.
    treads = [i for i, p in enumerate(ns["P"]) if _fd_os.path.basename(p["p"]).find("AisleTread") >= 0]
    if not treads:
        treads = [i for i, p in enumerate(ns["P"]) if "Aisle" in p["p"] and "Tread" in p["p"]]
    for i in treads[::max(1, len(treads) // 54)][:54]:
        lo, hi = ns["LO"][i], ns["HI"][i]
        x, z = (lo[0] + hi[0]) / 2, (lo[2] + hi[2]) / 2
        f = _fd_floor_hit(dg, x, hi[1], z)
        if f is not None:
            scatter.append(("Aisle", x, z, f, 2.3))
    lanes = [((23000., 226.), (23075., 101.))] + [((23075., 101.), p) for p in
             ((22649., -21.), (22883., -21.), (23117., -21.), (23351., -21.), (23164., 101.), (23288., 101.), (22864., 101.))]
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
            # Avoid painting through a wall: both lateral edges and the centre must remain walkable.
            if f is not None and all(_fd_floor_hit(dg, pos[0] + q * right[0], f, pos[1] + q * right[2]) is not None for q in (-3.6, 3.6)):
                lane_plan.append(((pos[0], f + .017, pos[1]), right, along, 8., ll))
    # Build the mesh collection only after planning.
    for kind, rows in plans.items():
        for idx, (p, u, v, w, h) in enumerate(rows):
            if kind == "peeling_wallpaper":
                _fd_peel(p, u, v, w, h, mats[kind], backing, coll, idx, rng)
            else:
                _fd_quad(p, u, v, w, h, mats[kind], coll, "L4F_%s_%04d" % (kind, idx), kind)
    for idx, (zone, x, z, fy, cy, dia) in enumerate(leak_plans):
        stain = _fd_quad((x, cy - .017, z), (1, 0, 0), (0, 0, 1), dia * 1.15, dia, mats["ceiling_rings"], coll,
                         "L4F_CeilingLeak_%02d_%s" % (idx, zone), "ceiling_rings")
        stain["l4_leak_zone"] = zone
        _fd_quad((x, fy + .018, z), (1, 0, 0), (0, 0, -1), dia * 1.25, dia * .98, mats["puddle_outline"], coll,
                 "L4F_DarkLeakRing_%02d" % idx, "puddle_outline")
        _fd_puddle(x, fy, z, dia, wet, coll, idx, rng)
    for idx, (zone, x, z, fy, size) in enumerate(scatter):
        o = _fd_quad((x, fy + .019, z), (1, 0, 0), (0, 0, -1), size, size * (1.6 if zone == "Aisle" else 1),
                     mats["popcorn_cups"], coll, "L4F_PopcornScatter_%03d" % idx, "popcorn_scatter")
        o["l4_scatter_zone"] = zone
        if idx % 7 == 0:
            _fd_quad((x + .35, fy + .016, z), (1, 0, 0), (0, 0, -1), size * 1.5, size * 1.2,
                     mats["carpet_stains"], coll, "L4F_CarpetStain_%03d" % idx, "carpet_stains")
    for idx, row in enumerate(lane_plan):
        _fd_quad(*row, mats["carpet_wear"], coll, "L4F_WearLane_%03d" % idx, "carpet_wear")
    heap_sites = [("Concession", 22911, 131, 24.05, True, False), ("Service", 22772, 166, 24.05, False, True),
                  ("Concourse", 22629, 89, 24.05, False, False), ("Concourse", 23369, 94, 24.05, False, False),
                  ("Concourse", 23023, 95, 24.05, False, False), ("Concourse", 23121, -16, 24.05, False, False),
                  ("Concession", 23113, 231, 24.05, False, True), ("Service", 22629, 232, 24.05, False, True),
                  ("Service", 22871, 209, 24.05, False, True), ("Arcade", 23247, 229, 24.05, False, False),
                  ("Gallery", 23043, -16, 86., False, False), ("Gallery", 23270, -16, 86., False, False)]
    for idx, (zone, x, z, fy, hero, cartons) in enumerate(heap_sites):
        _fd_rubbish(x, fy, z, coll, idx, rng, rubbish_mats, hero, cartons)
    # Individual loose paper cups. Standing cups are collidable; fallen cups are below the 1-stud rule.
    for idx, (_, x, z, fy, _) in enumerate(scatter[:95]):
        g = _FDGeo()
        standing = idx % 11 == 0
        _fd_cup(g, (x + .4, fy + (.06 if standing else .34), z + .4), rng.uniform(0, 6.28), paper, rim, not standing)
        g.object("L4F_LooseCup_%03d" % idx, coll, "cup", standing)
    for idx, (x, z) in enumerate(((23050, 83), (22780, 164), (22921, 144), (23312, 117))):
        _fd_cone(x, 24.05, z, coll, idx, yellow, dark)
    _fd_bucket(22774, 24.05, 158, coll, yellow, dark, steel, rng)
    _fd_puddle(22776, 24.05, 159, 5.6, wet, coll, 14, rng, "BucketSpill")
    bpy.context.view_layer.update()
    stats = _fd_collections.Counter(o.get("l4_kind", "unknown") for o in coll.all_objects)
    stats["objects"] = len(coll.all_objects)
    stats["triangles"] = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in coll.all_objects if o.type == "MESH")
    stats["colliders"] = sum(o.get("l4_collide") == "bounds" for o in coll.all_objects)
    stats["roof_leaks"] = len(leak_plans)
    stats["damp_run_studs"] = round(sum(row[3] for row in plans["rising_damp"]))
    stats["desire_line_studs"] = round(lane_length)
    stats["placed_wear_studs"] = round(sum(row[4] for row in lane_plan))
    assert stats["water_streaks"] == 200 and stats["peeling_wallpaper"] == 90, dict(stats)
    assert stats["roof_leaks"] == 14 and stats["cone"] == 4 and stats["bucket"] == 1, dict(stats)
    assert stats["triangles"] <= 60000, "F_decay triangle budget exceeded"
    for o in coll.all_objects:
        assert o.type == "MESH" and o.data.uv_layers.active is not None, o.name
        assert all(-1.e-5 <= q <= 1.00001 for loop in o.data.uv_layers.active.data for q in loop.uv), o.name
        if o.get("l4_kind") in ("cone", "bucket") or o.get("l4_height_studs", 0) >= 1.:
            assert o.get("l4_collide") == "bounds", o.name
        if o.get("l4_kind") in ("cup", "rubbish", "cone", "bucket"):
            height = (max(v.co.z for v in o.data.vertices) - min(v.co.z for v in o.data.vertices)) / _FD_S
            if height >= 1.:
                assert o.get("l4_collide") == "bounds", o.name
    print("F_decay:", dict(stats))
    return dict(stats)
