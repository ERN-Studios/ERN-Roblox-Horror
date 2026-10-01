# Level 4 cinema: import a Meshy image-to-3D GLB as a prop asset (Blender 5.2).
#   exec(open(r"G:\Roblox\MongoTV\tools\level4_blender\import_meshy.py").read(), {"SPEC": spec})  # spec or [specs]
#   blender -b <blend> -P import_meshy.py -- spec.json
#   python import_meshy.py            # no Blender: self-test of the pure maths
#
# SPEC: glb (path), asset (name), dims (x, y, z metres; None = free axis), tris (triangle budget).
#   Optional: fit "contain" (uniform, fits inside dims) | "stretch" (per axis), yaw_deg (added after
#   auto_square; use multiples of 90 to fix the front), auto_square (True: turn the smallest amount that
#   squares the footprint), tex_size 1024, sem "prop" (export ROBLOX_MAT key), col_slices 1,
#   col_axis "z", sharp_angle 40 (hard edges when decimation drops the GLB normals), tex_dir.
#
# Result, same conventions as props.py: mesh "L4A_<asset>" (metres, origin bottom-centre, front -Y,
# up +Z, fake user, l4_asset=<asset>) with ONE material "L4A_<asset>" whose 1024 px maps are written to
# tex_dir as L4A_<asset>_albedo.png (sRGB), _normal.png (OpenGL tangent normal), _rough.png, _metal.png (grey),
# the same suffixes make_pbr.py uses for the architecture sets.
# The material carries l4_sem/l4_color/l4_tex/l4_tile/l4_alpha like pmat() plus l4_uv="mesh" and
# l4_normal/l4_rough/l4_metal (file names); the mesh carries l4_col = JSON [[cx,cy,cz,sx,sy,sz], ...]
# collision boxes in the same frame. export_l4.py box-projects UVs and ignores the extra maps and
# l4_col until it is patched to read them. A preview object (+ wire "_COL") lands in the
# "L4 Meshy Assets" collection, outside "L4 Cinema", so the exporter never picks it up.
import json, math, os, re, sys
import numpy as np

try:
    import bpy
    from mathutils import Matrix
except ImportError:
    bpy = None

TEX = r"G:\Blender\Level4_Cinema\textures"
DEFAULTS = {"fit": "contain", "yaw_deg": 0.0, "auto_square": True, "tex_size": 1024, "sem": "prop",
            "col_slices": 1, "col_axis": "z", "sharp_angle": 40.0, "tex_dir": TEX}
STAGE = "L4 Meshy Assets"


# ---------------------------------------------------------------- pure maths (no bpy)
def rot_z(deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return np.array(((c, -s, 0, 0), (s, c, 0, 0), (0, 0, 1, 0), (0, 0, 0, 1)), dtype=float)


def min_area_yaw(pts, step=0.25):
    """Yaw in degrees, (-45, 45], that gives the points the smallest XY bounding box. Angles are tried
    smallest first and must win by 0.1%, so round or already-square shapes stay put."""
    xy = np.asarray(pts, float)[:, :2]
    best, best_a = None, 0.0
    for a in sorted(np.arange(-45 + step, 45 + step / 2, step), key=abs):
        c, s = math.cos(math.radians(a)), math.sin(math.radians(a))
        x = xy[:, 0] * c - xy[:, 1] * s
        y = xy[:, 0] * s + xy[:, 1] * c
        area = (x.max() - x.min()) * (y.max() - y.min())
        if best is None or area < best * 0.999:
            best, best_a = area, float(a)
    return best_a


def fit_scale(size, dims, fit="contain"):
    """Per-axis scale that fits `size` to `dims` (None = free). contain: uniform, the tightest given axis.
    stretch: each given axis exactly, free axes take the contain factor."""
    size = np.maximum(np.asarray(size, float), 1e-9)
    f = np.array([d / s if d else np.nan for d, s in zip(dims, size)])
    if np.isnan(f).all():
        raise ValueError("dims needs at least one axis")
    u = np.nanmin(f)
    if fit == "contain":
        return np.array([u, u, u])
    if fit == "stretch":
        return np.where(np.isnan(f), u, f)
    raise ValueError("fit must be contain or stretch, not %r" % fit)


def canonical_matrix(verts, dims, fit="contain", yaw_deg=0.0, auto_square=True):
    """4x4 that turns, scales and moves the vertices into the canonical frame: footprint centred on the
    origin, bottom at z = 0. Returns (matrix, yaw in degrees)."""
    v = np.asarray(verts, float)
    yaw = (min_area_yaw(v) if auto_square else 0.0) + yaw_deg
    R = rot_z(yaw)
    r = v @ R[:3, :3].T
    lo, hi = r.min(0), r.max(0)
    s = fit_scale(hi - lo, dims, fit)
    T = np.eye(4)
    T[:3, 3] = (-(lo[0] + hi[0]) / 2 * s[0], -(lo[1] + hi[1]) / 2 * s[1], -lo[2] * s[2])
    return T @ np.diag([*s, 1.0]) @ R, yaw


def slab_boxes(tri, n=1, axis=2):
    """Collision boxes [cx, cy, cz, sx, sy, sz]: n equal slabs along `axis`, each the bounding box of every
    triangle that overlaps it (triangles, not vertices, so a tall face leaves no gap in a middle slab)."""
    tri = np.asarray(tri, float)
    tmin, tmax = tri.min(1), tri.max(1)
    edges = np.linspace(tmin[:, axis].min(), tmax[:, axis].max(), n + 1)
    out = []
    for a, b in zip(edges[:-1], edges[1:]):
        sel = (tmin[:, axis] <= b) & (tmax[:, axis] >= a)
        if not sel.any():
            continue
        lo, hi = tmin[sel].min(0), tmax[sel].max(0)
        lo[axis], hi[axis] = a, b
        out.append([round(float(x), 4) for x in (*((lo + hi) / 2), *np.maximum(hi - lo, 0.01))])
    return out


def _selftest():
    corners = np.array([(x, y, z) for x in (-1, 1) for y in (-0.5, 0.5) for z in (0, 1.6)], float)
    pts = np.concatenate([corners, np.random.default_rng(1).uniform(-0.4, 0.4, (500, 3)) + (0, 0, 0.8)])
    pts = pts @ rot_z(30)[:3, :3].T + (3, -2, 5)                 # 2 x 1 x 1.6 box, turned 30 deg, off-centre
    assert abs(min_area_yaw(pts) + 30) <= 0.25, min_area_yaw(pts)
    M, yaw = canonical_matrix(pts, (None, None, 3.2))
    q = pts @ M[:3, :3].T + M[:3, 3]
    lo, hi = q.min(0), q.max(0)
    assert np.allclose(lo[2], 0) and np.allclose(hi - lo, (4, 2, 3.2), atol=1e-6), (lo, hi)
    assert np.allclose((lo + hi)[:2], 0, atol=1e-9)
    M, _ = canonical_matrix(pts, (1, 1, 1), "stretch")
    q = pts @ M[:3, :3].T + M[:3, 3]
    assert np.allclose(q.max(0) - q.min(0), 1)
    M, yaw = canonical_matrix(pts, (None, None, 1.6), yaw_deg=180)   # front flipped: long side still on X
    q = pts @ M[:3, :3].T + M[:3, 3]
    assert abs(yaw - 150) <= 0.25 and np.allclose(q.max(0) - q.min(0), (2, 1, 1.6), atol=1e-6)
    ring = np.array([(math.cos(t), math.sin(t), 0) for t in np.linspace(0, 2 * math.pi, 64, endpoint=False)])
    assert abs(min_area_yaw(ring)) <= 3                          # a round bin is not spun 45 degrees
    tall = np.array([[(0, 0, 0), (1, 0, 0), (1, 0, 3)], [(0, 0, 0), (1, 0, 3), (0, 0, 3)],   # a 1 x 3 face
                     [(0, -2, 0), (1, -2, 0), (1, 0, 0)]])                                  # + a floor tri
    b = slab_boxes(tall, 3)
    assert len(b) == 3 and np.allclose([x[5] for x in b], 1), b                          # no gap mid-height
    assert np.allclose(b[0][4], 2) and np.allclose(b[2][4], 0.01), b                     # floor only in slab 0
    print("import_meshy self-test ok")


# ---------------------------------------------------------------- Blender side
def _co(me):
    a = np.empty(len(me.vertices) * 3)
    me.vertices.foreach_get("co", a)
    return a.reshape(-1, 3)


def _tris(me):
    me.calc_loop_triangles()
    tv = np.empty(len(me.loop_triangles) * 3, dtype=np.int64)
    me.loop_triangles.foreach_get("vertices", tv)
    return _co(me)[tv].reshape(-1, 3, 3)


def _tri_count(me):
    lt = np.empty(len(me.polygons), dtype=np.int64)
    me.polygons.foreach_get("loop_total", lt)
    return int((lt - 2).sum())


def _principled(mat):
    return next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None) if mat and mat.node_tree else None


def _source(sock):
    """(image, channel) feeding a Principled input; channel is 0/1/2 when it comes through a Separate
    Color output (the glTF importer's metallicRoughness split), else None."""
    if not sock.is_linked:
        return None, None
    link = sock.links[0]
    ch = {"Red": 0, "Green": 1, "Blue": 2}.get(link.from_socket.name)
    node = link.from_node
    while node.type != "TEX_IMAGE":
        ins = [i for i in node.inputs if i.is_linked]
        if not ins:
            return None, None
        node = ins[0].links[0].from_node
    return node.image, ch


def _pixels(img, size):
    im = img.copy()
    im.scale(size, size)
    a = np.empty(size * size * 4, dtype=np.float32)
    im.pixels.foreach_get(a)                     # raw stored values, no colour management
    bpy.data.images.remove(im)
    return a.reshape(size, size, 4)


def _save(a, path, data):
    h, w = a.shape[:2]
    name = os.path.basename(path)
    old = bpy.data.images.get(name)
    if old:
        bpy.data.images.remove(old)
    im = bpy.data.images.new(name, w, h, alpha=False)
    if data:
        im.colorspace_settings.name = "Non-Color"
    rgba = np.ones((h, w, 4), dtype=np.float32)
    rgba[..., :3] = a[..., :3] if a.ndim == 3 else a[..., None]
    im.pixels.foreach_set(rgba.ravel())
    im.filepath_raw = path
    im.file_format = "PNG"
    im.save()
    return im


def _material(asset, maps, color, sem):
    name = "L4A_" + asset
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        if n.type not in ("BSDF_PRINCIPLED", "OUTPUT_MATERIAL"):
            nt.nodes.remove(n)
    b = _principled(mat)
    for key, sock in (("albedo", "Base Color"), ("rough", "Roughness"), ("metal", "Metallic"), ("normal", None)):
        if key not in maps:
            continue
        it = nt.nodes.new("ShaderNodeTexImage")
        it.image = maps[key]
        if sock:
            nt.links.new(it.outputs["Color"], b.inputs[sock])
        else:
            nm = nt.nodes.new("ShaderNodeNormalMap")
            nt.links.new(it.outputs["Color"], nm.inputs["Color"])
            nt.links.new(nm.outputs["Normal"], b.inputs["Normal"])
    lin = [(c / 255 / 12.92 if c / 255 <= 0.04045 else ((c / 255 + 0.055) / 1.055) ** 2.4) for c in color]
    mat.diffuse_color = (*lin, 1)
    fn = {k: (maps[k].name if k in maps else "") for k in ("albedo", "normal", "rough", "metal")}
    mat["l4_sem"] = sem
    mat["l4_color"] = list(color)
    mat["l4_tex"] = fn["albedo"]
    mat["l4_tile"] = 1.0
    mat["l4_alpha"] = 1.0
    mat["l4_uv"] = "mesh"
    mat["l4_normal"], mat["l4_rough"], mat["l4_metal"] = fn["normal"], fn["rough"], fn["metal"]
    return mat


def _reshade(o, angle):
    me = o.data
    cn = me.attributes.get("custom_normal")
    if cn:
        me.attributes.remove(cn)
    if me.has_custom_normals:
        with bpy.context.temp_override(object=o, active_object=o, selected_editable_objects=[o]):
            bpy.ops.mesh.customdata_custom_splitnormals_clear()
    me.shade_smooth()
    if angle:
        me.set_sharp_from_angle(angle=math.radians(angle))


def _box_mesh(name, boxes):
    v, f = [], []
    for cx, cy, cz, sx, sy, sz in boxes:
        k = len(v)
        v += [(cx + sx / 2 * i, cy + sy / 2 * j, cz + sz / 2 * l) for i in (-1, 1) for j in (-1, 1) for l in (-1, 1)]
        f += [tuple(k + i for i in q) for q in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3))]
    me = bpy.data.meshes.new(name)
    me.from_pydata(v, [], f)
    return me


def run(spec):
    missing = {"glb", "asset", "dims", "tris"} - set(spec)
    if missing:
        raise ValueError("spec is missing %s" % sorted(missing))
    sp = dict(DEFAULTS, **spec)
    asset, glb = sp["asset"], sp["glb"]
    if not re.fullmatch(r"[A-Za-z0-9_]+", asset):
        raise ValueError("asset must be [A-Za-z0-9_]+: %r" % asset)
    if not os.path.isfile(glb):
        raise FileNotFoundError(glb)
    name = "L4A_" + asset
    kinds = ("objects", "meshes", "materials", "images")
    before = {k: {x.as_pointer() for x in getattr(bpy.data, k)} for k in kinds}

    bpy.ops.import_scene.gltf(filepath=glb, merge_vertices=True)
    objs = [o for o in bpy.data.objects if o.as_pointer() not in before["objects"]]
    meshes = [o for o in objs if o.type == "MESH"]
    if not meshes:
        raise RuntimeError("no mesh in " + glb)
    for o in meshes:                             # bake the glTF hierarchy (Y-up -> Z-up) into the vertices
        if o.data.users > 1:
            o.data = o.data.copy()
        mw = o.matrix_world.copy()
        o.parent = None
        o.data.transform(mw)
        o.matrix_world = Matrix.Identity(4)
    for o in objs:
        if o.type != "MESH":
            bpy.data.objects.remove(o)
    o = meshes[0]
    if len(meshes) > 1:
        with bpy.context.temp_override(object=o, active_object=o, selected_objects=meshes,
                                       selected_editable_objects=meshes):
            bpy.ops.object.join()

    M, yaw = canonical_matrix(_co(o.data), sp["dims"], sp["fit"], sp["yaw_deg"], sp["auto_square"])
    o.data.transform(Matrix(M.tolist()))

    decimated = False
    for _ in range(3):                           # Meshy's target_polycount should make this a no-op
        n = _tri_count(o.data)
        if n <= sp["tris"]:
            break
        mod = o.modifiers.new("L4Decimate", "DECIMATE")
        mod.ratio = sp["tris"] / n * 0.98
        mod.use_collapse_triangulate = True
        dg = bpy.context.evaluated_depsgraph_get()
        low = bpy.data.meshes.new_from_object(o.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
        o.modifiers.remove(mod)
        old, o.data = o.data, low
        bpy.data.meshes.remove(old)
        decimated = True
    me = o.data
    if decimated:
        _reshade(o, sp["sharp_angle"])

    # ---- maps: keep Meshy's UV atlas, resample to tex_size, split metallicRoughness into two grey maps
    textured = [m for m in me.materials if _principled(m) and _source(_principled(m).inputs["Base Color"])[0]]
    if len(textured) != 1:
        raise RuntimeError("%s: expected one textured material, found %d; bake to one atlas first" % (asset, len(textured)))
    b = _principled(textured[0])
    size, tex_dir = sp["tex_size"], sp["tex_dir"]
    os.makedirs(tex_dir, exist_ok=True)
    path = lambda k: os.path.join(tex_dir, "%s_%s.png" % (name, k))
    col = _pixels(_source(b.inputs["Base Color"])[0], size)
    maps = {"albedo": _save(col, path("albedo"), False)}
    for key, sock in (("rough", "Roughness"), ("metal", "Metallic")):
        img, ch = _source(b.inputs[sock])
        if img:
            maps[key] = _save(_pixels(img, size)[..., ch or 0], path(key), True)
    img, _ = _source(b.inputs["Normal"])
    if img:
        maps["normal"] = _save(_pixels(img, size), path("normal"), True)
    color = [int(round(c * 255)) for c in col[..., :3].reshape(-1, 3).mean(0)]
    mat = _material(asset, maps, color, sp["sem"])
    me.materials.clear()
    me.materials.append(mat)
    me.polygons.foreach_set("material_index", np.zeros(len(me.polygons), dtype=np.int32))
    if me.uv_layers:
        me.uv_layers.active_index = 0

    boxes = slab_boxes(_tris(me), sp["col_slices"], "xyz".index(sp["col_axis"]))

    # ---- take over the asset name; objects already placed with the old mesh switch to the new one
    for stale in (name, name + "_COL"):
        prev = bpy.data.objects.get(stale)
        if prev and prev != o:
            bpy.data.objects.remove(prev)
    old = bpy.data.meshes.get(name)
    if old and old != me:
        old.user_remap(me)
        bpy.data.meshes.remove(old)
    me.name = name
    me["l4_asset"] = asset
    me["l4_col"] = json.dumps(boxes)
    me["l4_meshy_glb"] = glb
    me.use_fake_user = True

    stage = bpy.data.collections.get(STAGE)
    if not stage:
        stage = bpy.data.collections.new(STAGE)
        bpy.context.scene.collection.children.link(stage)
    for c in list(o.users_collection):
        c.objects.unlink(o)
    stage.objects.link(o)
    o.name = name
    o.location = (-100 - 6 * (len(stage.objects) - 1), 0, 0)
    o.hide_render = True
    old = bpy.data.meshes.get(name + "_COL")
    if old:
        bpy.data.meshes.remove(old)
    wire = bpy.data.objects.new(name + "_COL", _box_mesh(name + "_COL", boxes))
    wire.parent = o
    wire.display_type = "WIRE"
    wire.hide_render = True
    stage.objects.link(wire)

    for k in ("meshes", "materials", "images"):  # drop what the import left behind, nothing older;
                                                 # meshes first: joined-away meshes still hold the material
        coll = getattr(bpy.data, k)
        for x in list(coll):
            if x.as_pointer() not in before[k] and x.users == 0 and not x.use_fake_user:
                coll.remove(x)

    lo, hi = _co(me).min(0), _co(me).max(0)
    res = {"asset": asset, "mesh": name, "tris": _tri_count(me), "dims": [round(float(x), 3) for x in hi - lo],
           "yaw": round(yaw, 2), "decimated": decimated,
           "maps": {k: path(k) for k in maps}, "col": boxes}
    print("import_meshy", json.dumps(res), flush=True)
    return res


if "SPEC" in globals():
    RESULT = [run(s) for s in SPEC] if isinstance(SPEC, list) else run(SPEC)
elif bpy is None:
    _selftest()
elif "--" in sys.argv:
    s = json.load(open(sys.argv[sys.argv.index("--") + 1]))
    RESULT = [run(x) for x in s] if isinstance(s, list) else run(s)
