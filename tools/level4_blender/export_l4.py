# Level 4 cinema: Blender -> Roblox export (run inside Blender: MCP exec, or `blender -b <blend> -P export_l4.py`).
# Writes <OUT>/chunks/cNNNNN.b64 + manifest.json. OUT = global L4_EXPORT_OUT, else env L4_EXPORT_OUT, else the
# default below. exec() with L4_EXPORT_NO_RUN = True to get the functions without exporting.
#   * plain meshes under "L4 Cinema" are baked to world space and pooled per material (modifiers applied);
#   * obj["l4_prop"] / obj["l4_door_leaf"] objects are instanced assets (one mesh per material) placed per object,
#     so each becomes its own Model in Roblox;
#   * UVs: materials with l4_uv == "mesh" keep the mesh's own UVs as (u, 1 - v); all others are box-projected
#     (world metres for pools, object metres for assets) / l4_tile, matching the Blender materials;
#   * materials carry l4_tex / l4_normal / l4_rough / l4_metal (file names), l4_roblox, l4_emit, l4_uv;
#   * colliders (Studio frame, studs):
#       - the layout's collidable parts, with their tags and gameplay attributes (ArcadeCabinet ...). A part replaced
#         by a build module (build_base.REPLACED, or any regex in the REPLACES list of arch_detail/ceilings/doors_v2/
#         props_lobby/props_rooms/props_decay) is dropped only where the scene's own colliders cover >= 30 % of it (its tags and
#         attributes move to the collider covering most of it, unless that object already carries the tag), so a
#         prop with no collision of its own keeps the old boxes. Floors (Level4V4Floor) and walls (<= 3 studs thick,
#         >= 8 on both other axes) are never dropped. Level4V4Doorway volumes export as non-colliding markers;
#       - obj["l4_collide"] = "bounds": one box from the object's local bounds under its matrix (an OBB; exactly
#         axis-aligned results get an identity rotation);
#       - mesh["l4_col"] (or obj["l4_col"]) = JSON [[cx,cy,cz,sx,sy,sz], ...] in the mesh's local metres, under each
#         placement's matrix; l4_col wins over l4_collide. (mesh or obj) l4_col_tags = JSON list parallel to l4_col,
#         one tag string per box; when present it replaces obj l4_tags for the colliders;
#       - a Seat: box index obj["l4_seat_box"], else (mesh or obj) l4_seat_col, else with obj["l4_seat"] = True the
#         box with the largest local XY footprint. It faces l4_seat_front ("+Y"/"-Y"/"+X"/"-X", object-local) when
#         set, else away from the tallest box rising above it (the back), else -Y. obj["l4_tags"] = "A,B" tags every
#         box of the object, or only the Seat box when there is one;
#       - colliders of instanced props go to propColliders (placement index) so Roblox parents them into the Model;
#         door leaves get no scene colliders (the door's Leaf part is its collision);
#   * lights: every LIGHT object in the "L4 Fixture Lights" collection. POINT/SPOT/AREA -> PointLight/SpotLight/
#     SurfaceLight shining along the object's -Z (Roblox Face = Bottom of the holder). l4_range (studs),
#     l4_brightness, l4_shadows, l4_angle (SurfaceLight), l4_color (sRGB 0-255, else the light colour), l4_flicker
#     (the holder gets OccasionalFlicker) on the object or the light data. A light parented to an l4_prop object
#     (e.g. FlickerLens) records that placement, and Roblox puts it inside the prop's Neon part;
#   * legacyLights: the original preview lights still in "L4 Lights" (lights_and_camera.build_lights; packages delete
#     the ones whose fixture they replace), minus every module's LIGHTS_SUPERSEDED path regexes and the lights of
#     cloned flicker fixtures. Studio clones them from the original preview with their exact properties;
#   * flicker fixtures: layout parts with OccasionalFlicker = "true" whose object is still in the scene are not
#     exported as meshes; Studio clones the original part with its light;
#   * door leaves: l4_leaf_cf (12 numbers, Studio frame) / l4_leaf_size (studs) / l4_hinge_pos (Studio frame, any
#     point on the hinge axis) when present; else the layout part (l4_src); else the leaf mesh bounds;
#   * decal carriers (the original Decals / SurfaceGuis) move to 0.02 studs in front of the first new surface a ray
#     finds from 1 stud in front of the original face (5 rays over the footprint, the most proud hit wins). Carriers
#     matching a module's CARRIER_SKIP ({"path": regex, "at": original position or None}) are left out.
# Chunk limits: <= 20,000 triangles, <= 60,000 vertices, <= 1800 studs on any axis.
import bpy, mathutils, json, os, math, re, base64, shutil, collections, ast
import numpy as np

OUT = globals().get("L4_EXPORT_OUT") or os.environ.get("L4_EXPORT_OUT") or r"G:\Roblox\_local\l4blender\export"
HERE = r"G:\Roblox\MongoTV\tools\level4_blender"
BUILD_MODULES = ("arch_detail.py", "ceilings.py", "doors_v2.py", "props_lobby.py", "props_rooms.py", "props_decay.py")
K = 1 / 0.28
OX = 23000.0
MAX_TRIS, MAX_SPAN = 20000, 1800.0
C = np.array(((1, 0, 0), (0, 0, 1), (0, -1, 0)), dtype=np.float64)   # Blender (x,y,z) -> Roblox (x,z,-y)
Cm = mathutils.Matrix(C.tolist())
LAYOUT = json.load(open(os.path.join(HERE, "l4_layout.json")))
DUMP = json.load(open(os.path.join(HERE, "l4_dump.json")))

ROBLOX_MAT = {"carpet": "Carpet", "carpet_arcade": "Carpet", "velvet": "Fabric", "acoustic": "Fabric",
              "plaster": "Plaster", "wall_dark": "Plaster", "marble": "Marble", "granite": "Granite",
              "tile": "CeramicTiles", "ceiling": "SmoothPlastic", "wood": "Wood", "metal": "Metal",
              "concrete": "Concrete", "neon": "Neon", "glass": "Glass", "screen": "SmoothPlastic",
              "plastic": "SmoothPlastic", "prop": "SmoothPlastic"}
FLICKER = {p["p"] for p in LAYOUT["parts"] if (p.get("at") or {}).get("OccasionalFlicker") == "true"}
DOOR_PARTS = re.compile(r"^AutomaticDoors/(?!.*_Post$)")      # leaves + hardware: the door Models replace them
FACE_N = {"Front": (0, 0, -1), "Back": (0, 0, 1), "Right": (1, 0, 0), "Left": (-1, 0, 0),
          "Top": (0, 1, 0), "Bottom": (0, -1, 0)}
PROBE, PROBE_INSIDE = 1.0, 3.0                                 # studs (place.luau adds the 0.02 gap)
COVER = 0.3                                                     # share of an old box the new colliders must cover


# ---------------------------------------------------------------- frames
def studio_pos(v):
    """Blender metres -> Studio studs, original layout frame."""
    return [v[0] * K + OX, v[2] * K, -v[1] * K]


def key(path):
    return re.sub(r"\d+", "#", path)


FRONT_Q = {   # Blender-local turn about Z that takes +Y (a Seat's LookVector after the axis swap) to the front
    "+Y": np.eye(3), "-Y": np.diag((-1.0, -1.0, 1.0)),
    "+X": np.array(((0, 1, 0), (-1, 0, 0), (0, 0, 1)), float), "-X": np.array(((0, -1, 0), (1, 0, 0), (0, 0, 1)), float)}


def box_cf(Mw, c, s, front=None, plain=True):
    """A box (centre c, size s in object-local metres) under a 4x4 world matrix -> (cf12 Studio frame, size studs).
    front: "+Y"/"-Y"/"+X"/"-X" turns the box so its Roblox LookVector (-Z) points along that object-local axis
    (a Seat faces its LookVector). plain: an exactly axis-aligned box gets an identity rotation (sizes permuted)."""
    Mw = np.asarray(Mw, dtype=np.float64)
    A = Mw[:3, :3]
    sc = np.linalg.norm(A, axis=0)
    u, _, vt = np.linalg.svd(A / np.maximum(sc, 1e-12))
    R = u @ vt
    if np.linalg.det(R) < 0:                    # mirrored object: a box is symmetric, flip one axis back
        R[:, 0] = -R[:, 0]
    sb = np.abs(np.asarray(s, float)) * sc
    if front:
        Q = FRONT_Q[front]
        R, sb = R @ Q, np.abs(Q.T) @ sb
    Rr = C @ R @ C.T
    sr = np.array((sb[0], sb[2], sb[1])) * K    # Roblox local X, Y, Z = Blender local x, z, y
    if not front and plain and np.all(np.minimum(np.abs(Rr), np.abs(np.abs(Rr) - 1)) < 1e-5):
        sr = np.abs(Rr) @ sr                    # axis-aligned: plain world box
        Rr = np.eye(3)
    p = studio_pos(A @ np.asarray(c, float) + Mw[:3, 3])
    return ([round(float(x), 4) for x in p] + [round(float(x), 6) for x in Rr.flatten()],
            [round(float(max(x, 0.05)), 4) for x in sr])


def aabb(cf, s):
    R = np.abs(np.array(cf[3:12], float).reshape(3, 3))
    e = R @ np.asarray(s, float) / 2
    c = np.asarray(cf[:3], float)
    return c - e, c + e


def as_list(v):
    if v is None:
        return None
    return json.loads(v) if isinstance(v, str) else [as_list(x) if hasattr(x, "__len__") and not isinstance(x, str)
                                                     else x for x in v]


def tag_list(v):
    if not v:
        return []
    return [t.strip() for t in (v.split(",") if isinstance(v, str) else list(v)) if t.strip()]


# ---------------------------------------------------------------- replaced layout parts
def module_constant(path, name):
    """Value of a module-level `name = ...` in a build script, evaluated on its own (the script is not run)."""
    for node in ast.parse(open(path, encoding="utf-8").read()).body:
        targets = node.targets if isinstance(node, ast.Assign) else [node.target] if isinstance(node, ast.AnnAssign) else []
        if targets and node.value is not None and any(getattr(t, "id", None) == name for t in targets):
            return eval(compile(ast.Expression(node.value), path, "eval"), {"re": re})
    return None


def module_list(name, build_dir=HERE):
    """Every build module's `name` constant (a list, or one item), concatenated in BUILD_MODULES order."""
    out = []
    for fn in BUILD_MODULES:
        path = os.path.join(build_dir, fn)
        v = module_constant(path, name) if os.path.exists(path) else None
        if v is not None:
            out += [v] if isinstance(v, (str, re.Pattern, dict)) else list(v)
    return out


def replaced_patterns(build_dir=HERE):
    """-> (compiled REPLACES regexes matched on the raw path, build_base.REPLACED matched on key(path))."""
    rx = [re.compile(r) if isinstance(r, str) else r for r in module_list("REPLACES", build_dir)]
    base = os.path.join(build_dir, "build_base.py")
    rep = module_constant(base, "REPLACED") if os.path.exists(base) else None
    return rx, rep


def protected(p):
    s = sorted(p["s"])
    return "Level4V4Floor" in (p.get("tags") or []) or (s[0] <= 3 and s[1] >= 8)


def prune_replaced(layout_cols, new_cols, is_replaced):
    """layout_cols: [(path, collider dict)]. Drops replaced, unprotected ones the new colliders cover by >= COVER
    of their volume, moving their tags and attributes to the new collider that covers most (a tag another box of
    that object already carries is not added again, so tag counts survive). -> (kept dicts, stats)."""
    if new_cols:
        lo_n, hi_n = map(np.array, zip(*(aabb(c["cf"], c["s"]) for c in new_cols)))
    src_tags = collections.defaultdict(set)
    for c in new_cols:
        src_tags[c.get("src")].update(c["tags"])
    kept, dropped, uncovered = [], 0, []
    for path, c in layout_cols:
        if not is_replaced(path) or c.get("kind") == "Marker" or c.get("_protected"):
            kept.append(c)
            continue
        lo, hi = aabb(c["cf"], c["s"])
        if new_cols:
            ov = np.prod(np.clip(np.minimum(hi, hi_n) - np.maximum(lo, lo_n), 0, None), axis=1)
            if ov.sum() >= COVER * np.prod(hi - lo):
                best = new_cols[int(ov.argmax())]
                have = src_tags[best.get("src")]
                add = [t for t in c["tags"] if t not in have]
                best["tags"] = best["tags"] + add
                have.update(add)
                if c.get("at"):
                    best["at"] = dict(c["at"], **(best.get("at") or {}))
                dropped += 1
                continue
        kept.append(c)
        uncovered.append(path)
    return kept, {"dropped": dropped, "keptReplaced": len(uncovered), "keptReplacedSample": sorted(set(uncovered))[:25]}


# ---------------------------------------------------------------- materials and triangles
def mat_info(m):
    sem = m.get("l4_sem", "prop") if m else "plastic"
    tex = m.get("l4_tex", "") if m else ""
    rm = ROBLOX_MAT.get(sem, "SmoothPlastic")
    name = m.name if m else "None"
    if m and name.startswith("L4P_"):
        if "cardboard" in name: rm = "Cardboard"
        elif "leather" in name: rm = "Leather"
        elif "velvet" in name: rm = "Fabric"
        elif "marble" in name: rm = "Marble"
        elif "wood" in name or "laminate" in name or "cabinet" in name: rm = "Wood"
        elif m.get("l4_sem") == "metal" or "steel" in name or "brass" in name or "chrome" in name: rm = "Metal"
    if m and m.get("l4_roblox"):
        rm = m["l4_roblox"]
    return {"name": name, "sem": sem, "color": list(m.get("l4_color", [180, 180, 180])) if m else [180, 180, 180],
            "tex": tex, "normal": m.get("l4_normal", "") if m else "", "rough": m.get("l4_rough", "") if m else "",
            "metal": m.get("l4_metal", "") if m else "", "tile": float(m.get("l4_tile", 1.0)) if m else 1.0,
            "alpha": float(m.get("l4_alpha", 1.0)) if m else 1.0, "roblox": rm,
            "emit": float(m.get("l4_emit", 0.0)) if m else 0.0, "uv": m.get("l4_uv", "box") if m else "box",
            # albedo multiplied by the colour in Blender: legacy "_n" detail maps, and slot(name, tint) copies
            "tinted": bool(tex) and (tex.endswith("_n.png") or bool(m.get("l4_slot") and re.search(r"_[0-9a-f]{6}(_uv)?$", name)))}


def box_uv(P, tile):
    """Blender box projection: X-facing -> (y,z), Y-facing -> (x,z), Z-facing -> (x,y)."""
    fn = np.cross(P[:, 1] - P[:, 0], P[:, 2] - P[:, 0])
    ax = np.argmax(np.abs(fn), axis=1)
    U = np.empty(P.shape[:2] + (2,))
    for a, (i, j) in enumerate(((1, 2), (0, 2), (0, 1))):
        s = ax == a
        U[s, :, 0] = P[s][:, :, i]
        U[s, :, 1] = P[s][:, :, j]
    U /= tile
    U[:, :, 1] = -U[:, :, 1]                       # Roblox V runs down
    return U


def mesh_of(o, dg):
    """(mesh, evaluated object or None); objects with modifiers export their evaluated mesh."""
    if o.modifiers:
        ev = o.evaluated_get(dg)
        return ev.to_mesh(), ev
    return o.data, None


def tris(o, me, world, mats):
    """-> {material name: (P[n,3,3] blender metres, N[n,3,3], U[n,3,2] Roblox UVs)}."""
    me.calc_loop_triangles()
    nt = len(me.loop_triangles)
    out = {}
    if not nt:
        return out
    co = np.empty(len(me.vertices) * 3); me.vertices.foreach_get("co", co); co = co.reshape(-1, 3)
    tv = np.empty(nt * 3, dtype=np.int64); me.loop_triangles.foreach_get("vertices", tv)
    tl = np.empty(nt * 3, dtype=np.int64); me.loop_triangles.foreach_get("loops", tl)
    mi = np.empty(nt, dtype=np.int64); me.loop_triangles.foreach_get("material_index", mi)
    cn = np.empty(len(me.loops) * 3); me.corner_normals.foreach_get("vector", cn); cn = cn.reshape(-1, 3)
    P = co[tv].reshape(nt, 3, 3); N = cn[tl].reshape(nt, 3, 3)
    UV = None
    if me.uv_layers.active is not None:
        uv = np.empty(len(me.loops) * 2)
        me.uv_layers.active.uv.foreach_get("vector", uv)
        UV = uv.reshape(-1, 2)[tl].reshape(nt, 3, 2)
    if world:
        Mw = np.array(o.matrix_world)
        P = P @ Mw[:3, :3].T + Mw[:3, 3]
        N = N @ np.linalg.inv(Mw[:3, :3])
        if np.linalg.det(Mw[:3, :3]) < 0:
            P = P[:, [0, 2, 1]]; N = N[:, [0, 2, 1]]
            UV = UV[:, [0, 2, 1]] if UV is not None else None
    N /= np.maximum(np.linalg.norm(N, axis=2, keepdims=True), 1e-9)
    slots = [s.material for s in o.material_slots] or [None]
    for idx in np.unique(mi):
        m = slots[idx] if idx < len(slots) else None
        name = m.name if m else "None"
        info = mats.get(name, {})
        sel = mi == idx
        if info.get("uv") == "mesh" and UV is not None:
            U = UV[sel].copy()
            U[:, :, 1] = 1 - U[:, :, 1]
        else:
            U = box_uv(P[sel], info.get("tile", 1.0))
        if name in out:
            out[name] = tuple(np.concatenate([a, b]) for a, b in zip(out[name], (P[sel], N[sel], U)))
        else:
            out[name] = (P[sel], N[sel], U)
    return out


def split(P, N, U):
    Pr = (P @ C.T) * K
    lo = Pr.reshape(-1, 3).min(0); hi = Pr.reshape(-1, 3).max(0); span = hi - lo
    if (len(P) <= MAX_TRIS and span.max() <= MAX_SPAN) or len(P) <= 1:
        return [(P, N, U)]
    ax = int(span.argmax())
    order = np.argsort(Pr[:, :, ax].mean(1), kind="stable")
    h = len(P) // 2
    a, b = order[:h], order[h:]
    return split(P[a], N[a], U[a]) + split(P[b], N[b], U[b])


def visible_meshes():
    root = bpy.data.collections["L4 Cinema"]
    for o in root.all_objects:
        if o.type == "MESH" and not o.hide_render and o.visible_get() and o.display_type not in ("WIRE", "BOUNDS"):
            yield o


# ---------------------------------------------------------------- scene colliders, lights, carriers
def seat_front(boxes, seat, hint=None):
    """Object-local axis a Seat faces: the hint ("+Y" ...), else away from the tallest box that rises above the
    seat box (its back), snapped to an axis, else -Y (the prop convention: front -Y)."""
    if hint in FRONT_Q:
        return hint
    sc, ss = boxes[seat]
    backs = [b for i, b in enumerate(boxes) if i != seat and b[0][2] + b[1][2] / 2 > sc[2] + ss[2] / 2 + 1e-4]
    if backs:
        bc = max(backs, key=lambda b: b[0][2] + b[1][2] / 2)[0]
        d = sc[:2] - bc[:2]
        if np.abs(d).max() > 1e-3:
            return ("+X" if d[0] > 0 else "-X") if abs(d[0]) > abs(d[1]) else ("+Y" if d[1] > 0 else "-Y")
    return "-Y"


def object_colliders(o):
    """Collider dicts (Studio frame) from obj l4_collide / (obj or mesh) l4_col, l4_col_tags, l4_seat_col /
    obj l4_seat, l4_seat_box, l4_tags."""
    me = o.data if o.type == "MESH" else None
    get = lambda k: o.get(k, me.get(k) if me is not None else None)
    raw = as_list(get("l4_col"))
    if raw:
        boxes = [(np.array(b[:3], float), np.array(b[3:6], float)) for b in raw]
    elif o.get("l4_collide") == "bounds":
        bb = np.array([list(v) for v in o.bound_box])
        boxes = [((bb.min(0) + bb.max(0)) / 2, bb.max(0) - bb.min(0))]
    else:
        if o.get("l4_collide"):
            print("WARNING %s: l4_collide=%r is not supported (use 'bounds')" % (o.name, o.get("l4_collide")))
        return []
    seat = o.get("l4_seat_box", get("l4_seat_col"))
    if seat is None and o.get("l4_seat"):
        seat = max(range(len(boxes)), key=lambda i: (boxes[i][1][0] * boxes[i][1][1], -boxes[i][0][2]))
    if seat is not None and not 0 <= int(seat) < len(boxes):
        print("WARNING %s: seat box %r out of range" % (o.name, seat))
        seat = None
    seat = None if seat is None else int(seat)
    front = seat_front(boxes, seat, get("l4_seat_front")) if seat is not None else None
    per_box = as_list(get("l4_col_tags")) if raw else None
    if per_box:                                 # per-box tags win; obj l4_tags would double-count them
        box_tags = [tag_list(per_box[i]) if i < len(per_box) else [] for i in range(len(boxes))]
    else:
        tags = tag_list(o.get("l4_tags"))
        box_tags = [list(tags) if seat is None or i == seat else [] for i in range(len(boxes))]
    m0 = o.material_slots[0].material if o.material_slots else None
    phys = mat_info(m0)["roblox"] if m0 else "SmoothPlastic"
    phys = "SmoothPlastic" if phys == "Neon" else phys
    Mw = np.array(o.matrix_world)
    out = []
    for i, (c, s) in enumerate(boxes):
        cf, size = box_cf(Mw, c, s, front=front if i == seat else None)
        out.append({"cf": cf, "s": size, "sh": "Block", "m": "Fabric" if i == seat else phys,
                    "tags": box_tags[i], "kind": "Seat" if i == seat else "Part", "src": o.name})
    return out


def lin2srgb(c):
    c = max(0.0, float(c))
    return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def export_lights(placement_of):
    col = bpy.data.collections.get("L4 Fixture Lights")
    out = []
    for o in (col.all_objects if col else []):
        ld = o.data
        if o.type != "LIGHT" or ld.type not in ("POINT", "SPOT", "AREA"):
            continue
        get = lambda k, d=None: o.get(k, ld.get(k, d))
        cf, _ = box_cf(np.array(o.matrix_world), (0, 0, 0), (1, 1, 1), plain=False)
        rng = get("l4_range")
        if rng is None:
            rng = ld.cutoff_distance * K if ld.use_custom_distance else 16.0
        col = get("l4_color")                   # sRGB 0-255 as the package meant it; else the light's colour
        col = [c / 255 for c in col] if col is not None else [lin2srgb(c) for c in ld.color]
        e = {"type": {"POINT": "PointLight", "SPOT": "SpotLight", "AREA": "SurfaceLight"}[ld.type],
             "pos": cf[:3], "rot": cf[3:], "color": [round(min(1.0, max(0.0, float(c))), 4) for c in col],
             "range": round(float(rng), 3), "brightness": round(float(get("l4_brightness", 1.0)), 3),
             "shadows": bool(get("l4_shadows", False)), "name": o.name}
        if get("l4_flicker"):
            e["flicker"] = True
        if ld.type == "SPOT":
            e["angle"] = round(math.degrees(ld.spot_size), 2)
        elif ld.type == "AREA":
            sx = ld.size
            sy = ld.size_y if ld.shape in ("RECTANGLE", "ELLIPSE") else ld.size
            e["size"] = [round(sx * K, 3), 0.2, round(sy * K, 3)]
            e["angle"] = float(get("l4_angle", 90))
        p = o.parent
        while p is not None and not p.get("l4_prop"):
            p = p.parent
        if p is not None and p.name in placement_of:
            e["prop"] = placement_of[p.name]
            e["propName"] = p.name
        out.append(e)
    return out


def legacy_lights(superseded, cloned_hosts):
    """Original preview lights still standing in "L4 Lights" (build_lights; a package that replaces a fixture deletes
    its light there), minus LIGHTS_SUPERSEDED paths and lights whose host is a cloned flicker fixture (the clone
    carries them). -> [[light path, original host position]]; place.luau clones them from the original preview."""
    col = bpy.data.collections.get("L4 Lights")
    out = []
    for o in (col.all_objects if col else []):
        i = o.get("l4_src_light")
        if o.type != "LIGHT" or i is None:
            continue
        l = DUMP["lights"][int(i)]
        host = (l["p"].rsplit("/", 1)[0], tuple(round(v, 2) for v in l["pos"]))
        if host in cloned_hosts or any(r.search(l["p"]) for r in superseded):
            continue
        out.append([l["p"], l["pos"]])
    return out


def rb2b(v):
    return mathutils.Vector(((v[0] - OX) / K, -v[2] / K, v[1] / K))


def lift_carrier(cf, s, face, dg, allowed):
    """Carrier cf moved along its face normal so its face lies on the first new surface in front of the old one.
    -> (cf, shift in studs; 0 when nothing was found)."""
    R = np.array(cf[3:12], float).reshape(3, 3)
    c = np.array(cf[:3], float)
    s = np.array(s, float)
    ln = np.array(FACE_N[face], float)
    ax = int(np.argmax(np.abs(ln)))
    n = R @ ln
    a, b = [i for i in range(3) if i != ax]
    face_c = c + n * s[ax] / 2
    reach = s[ax] + 0.1                                    # down to the back of the original part
    best = None
    for fu, fv in ((0, 0), (.6, .6), (.6, -.6), (-.6, .6), (-.6, -.6)):
        pt = face_c + R[:, a] * s[a] / 2 * fu + R[:, b] * s[b] / 2 * fv
        for probe in (PROBE, PROBE_INSIDE):
            origin, left, inside, d_hit = pt + n * probe, probe + reach, False, None
            travelled = 0.0
            for _ in range(8):
                hit, loc, nrm, _, obj, _ = bpy.context.scene.ray_cast(
                    dg, rb2b(origin), mathutils.Vector((-n[0], n[2], -n[1])), distance=left / K)
                if not hit:
                    break
                d = (mathutils.Vector(loc) - rb2b(origin)).length * K
                facing = nrm[0] * n[0] + nrm[2] * n[1] - nrm[1] * n[2] > 0.2
                if obj is not None and obj.name in allowed and facing:
                    d_hit = travelled + d
                    break
                if not facing and obj is not None and obj.name in allowed:
                    inside = True                          # started inside something: back face first
                step = d + 1e-3
                origin, left, travelled = origin - n * step, left - step, travelled + step
            if d_hit is not None and not (probe == PROBE and inside):
                delta = probe - d_hit                       # > 0: the new surface is in front of the old face
                best = delta if best is None else max(best, delta)
            if not inside:
                break
    if best is None:
        return cf, 0.0
    best = float(np.clip(best, -reach, PROBE_INSIDE))
    return [round(float(x), 4) for x in c + n * best] + list(cf[3:12]), best


# ---------------------------------------------------------------- export
def export(out=OUT):
    shutil.rmtree(os.path.join(out, "chunks"), ignore_errors=True)
    os.makedirs(os.path.join(out, "chunks"))
    dg = bpy.context.evaluated_depsgraph_get()
    manifest = {"version": 2, "studsPerMetre": K, "materials": {}, "chunks": [], "placements": []}
    mats = manifest["materials"]
    cid = [0]

    def emit(P, N, U, mname, group, name):
        box = mats.get(mname, {}).get("uv", "box") != "mesh"
        for p, n, u in split(P, N, U):
            pr = (p @ C.T) * K                          # studs, Roblox axes
            nr = n @ C.T
            lo = pr.reshape(-1, 3).min(0); hi = pr.reshape(-1, 3).max(0); ctr = (lo + hi) / 2
            if box:
                u = u - np.floor(u.reshape(-1, 2).min(0))   # keep UVs small; a whole-tile shift keeps the tiling
            pv, pi = np.unique(np.round(pr.reshape(-1, 3) - ctr, 4), axis=0, return_inverse=True)
            nv, ni = np.unique(np.round(nr.reshape(-1, 3), 3), axis=0, return_inverse=True)
            uv, ui = np.unique(np.round(u.reshape(-1, 2), 4), axis=0, return_inverse=True)
            assert len(pv) <= 60000 and len(p) <= MAX_TRIS
            faces = np.stack([pi.reshape(-1, 3), ni.reshape(-1, 3), ui.reshape(-1, 3)], axis=2).reshape(-1, 9)
            blob = (np.array([len(pv), len(nv), len(uv), len(p)], dtype="<u4").tobytes()
                    + pv.astype("<f4").tobytes() + nv.astype("<f4").tobytes() + uv.astype("<f4").tobytes()
                    + faces.astype("<u4").tobytes())
            with open(os.path.join(out, "chunks", "c%05d.b64" % cid[0]), "w") as fh:
                fh.write(base64.b64encode(blob).decode())
            manifest["chunks"].append({"id": cid[0], "group": group, "material": mname, "tris": int(len(p)),
                                       "verts": int(len(pv)), "center": [round(float(x), 4) for x in ctr],
                                       "size": [round(float(x), 4) for x in np.maximum(hi - lo, 0.05)],
                                       "name": name[:90]})
            cid[0] += 1

    for m in bpy.data.materials:
        if m.name.startswith("L4"):
            mats[m.name] = mat_info(m)
    mats["None"] = mat_info(None)

    groups = collections.OrderedDict()
    pooled = collections.defaultdict(list)
    scene_cols = []
    allowed = set()
    flicker_src = set()
    for o in visible_meshes():
        allowed.add(o.name)
        if o.get("l4_path") in FLICKER and o.get("l4_src") is not None:
            flicker_src.add(int(o["l4_src"]))
            continue                                    # Studio clones these fixtures with their lights
        if o.get("l4_prop") or o.get("l4_door_leaf"):
            groups.setdefault(o.data.name, []).append(o)
            continue
        me, ev = mesh_of(o, dg)
        for mname, t in tris(o, me, True, mats).items():
            pooled[mname].append(t)
        if ev:
            ev.to_mesh_clear()
        scene_cols += object_colliders(o)

    prop_cols, placement_of = [], {}
    for gi, (mesh_name, objs) in enumerate(groups.items()):
        me, ev = mesh_of(objs[0], dg)
        for mname, (P, N, U) in tris(objs[0], me, False, mats).items():
            emit(P, N, U, mname, gi, "%s_%s" % (mesh_name, mname))
        if ev:
            ev.to_mesh_clear()
        for o in objs:
            loc, rot, sc = o.matrix_world.decompose()
            Rr = Cm @ rot.to_matrix() @ Cm.transposed()
            pl = {"group": gi, "name": o.name, "model": o.get("l4_model", o.name),
                  "pos": [round(x * K, 4) for x in (Cm @ loc)],
                  "rot": [round(Rr[i][j], 6) for i in range(3) for j in range(3)],
                  "scale": [round(sc[0], 6), round(sc[2], 6), round(sc[1], 6)]}
            if o.get("l4_attrs"):
                pl["attrs"] = json.loads(o["l4_attrs"])
            idx = len(manifest["placements"])
            if o.get("l4_door_leaf"):
                pl["door"] = door_info(o, pl)
            else:
                placement_of[o.name] = idx
                for c in object_colliders(o):
                    c["placement"] = idx
                    prop_cols.append(c)
            manifest["placements"].append(pl)
    print("instanced groups", len(groups), "chunks", cid[0], flush=True)
    for mname, ts in pooled.items():
        emit(*(np.concatenate(x) for x in zip(*ts)), mname, -1, "World_" + mname)
    print("after pooling chunks", cid[0], flush=True)

    # ---- layout colliders (minus covered replaced props) + scene colliders, markers, carriers, flicker fixtures
    rx, rep = replaced_patterns()
    is_replaced = lambda path: any(r.search(path) for r in rx) or bool(rep and rep.search(key(path)))
    skip = [(re.compile(s["path"]), s.get("at")) for s in module_list("CARRIER_SKIP")]
    skipped = lambda path, orig: any(r.search(path) and (at is None or np.allclose(at, orig, atol=0.1))
                                     for r, at in skip)
    layout_cols, carriers, flick, n_skip = [], [], [], 0
    for i, p in enumerate(LAYOUT["parts"]):
        orig = DUMP["parts"][i]["cf"][:3] if i < len(DUMP["parts"]) else None
        tags = p.get("tags") or []
        at = {k: v for k, v in (p.get("at") or {}).items() if k not in ("OccasionalFlicker", "AutoDoorLeaf")}
        if p["cc"] and not DOOR_PARTS.search(p["p"]):
            layout_cols.append((p["p"], {"cf": p["cf"], "s": p["s"], "m": p["m"], "tags": list(tags), "at": at,
                                         "sh": p.get("sh") or ("Block" if p["c"] != "WedgePart" else "Wedge"),
                                         "kind": "Seat" if p["c"] == "Seat" else "Part",
                                         "_protected": protected(p)}))
        elif "Level4V4Doorway" in tags:
            layout_cols.append((p["p"], {"cf": p["cf"], "s": p["s"], "m": p["m"], "tags": list(tags), "at": at,
                                         "sh": "Block", "kind": "Marker"}))
        decs = [d for d in p.get("dec", []) if d[0] in ("Decal", "SurfaceGui")]
        if orig and decs and not p["p"].startswith("AutomaticDoors/"):
            if skipped(p["p"], orig):
                n_skip += 1
            else:
                carriers.append({"path": DUMP["parts"][i]["p"], "orig": orig, "cf": p["cf"], "s": p["s"],
                                 "face": decs[0][1]})
        if i in flicker_src and orig:                   # a flicker fixture still standing in the scene
            flick.append({"path": p["p"], "orig": orig})
    kept, prune = prune_replaced(layout_cols, scene_cols + prop_cols, is_replaced)
    for c in kept:
        c.pop("_protected", None)
    manifest["colliders"] = kept + scene_cols
    manifest["propColliders"] = prop_cols
    moved = []
    for c in carriers:
        c["cf"], shift = lift_carrier(c["cf"], c["s"], c.pop("face"), dg, allowed)
        if abs(shift) > 1e-3:
            moved.append(round(shift, 3))
    manifest["carriers"] = carriers
    manifest["flicker"] = flick
    manifest["flickerPaths"] = sorted(FLICKER)
    manifest["lights"] = export_lights(placement_of)
    superseded = [re.compile(r) for r in module_list("LIGHTS_SUPERSEDED")]
    cloned = {(f["path"], tuple(round(v, 2) for v in f["orig"])) for f in flick}
    manifest["legacyLights"] = legacy_lights(superseded, cloned)
    manifest["replaces"] = [r.pattern for r in rx] + ([rep.pattern] if rep else [])
    manifest["prune"] = prune
    manifest["carriersMoved"] = len(moved)
    manifest["carriersSkipped"] = n_skip
    with open(os.path.join(out, "manifest.json"), "w") as fh:
        json.dump(manifest, fh)
    ch = manifest["chunks"]
    print("DONE chunks", len(ch), "tris", sum(c["tris"] for c in ch), "maxtris", max(c["tris"] for c in ch),
          "placements", len(manifest["placements"]), "colliders", len(manifest["colliders"]),
          "(scene %d, seats %d)" % (len(scene_cols), sum(c["kind"] == "Seat" for c in manifest["colliders"] + prop_cols)),
          "propColliders", len(prop_cols), "carriers", len(carriers), "moved", len(moved),
          "skipped", n_skip, "flicker", len(flick), "lights", len(manifest["lights"]),
          "legacyLights", len(manifest["legacyLights"]), "prune", json.dumps(prune), flush=True)
    return manifest


def door_info(o, pl):
    src = o.get("l4_src")
    lp = LAYOUT["parts"][src] if src is not None else None
    leaf_cf = as_list(o.get("l4_leaf_cf")) or (lp["cf"] if lp else None)
    leaf_size = as_list(o.get("l4_leaf_size")) or (lp["s"] if lp else None)
    if leaf_cf is None or leaf_size is None:
        bb = np.array([list(v) for v in o.bound_box])
        leaf_cf, leaf_size = box_cf(np.array(o.matrix_world), (bb.min(0) + bb.max(0)) / 2, bb.max(0) - bb.min(0))
    hinge = as_list(o.get("l4_hinge_pos"))
    name = o.get("l4_door", o.name)
    for label, v in (("l4_leaf_cf", leaf_cf), ("l4_hinge_pos", hinge)):
        if v is not None and abs(v[0] - OX) > 1500:
            print("WARNING door %s: %s x=%.1f is not in the Studio layout frame" % (name, label, v[0]))
    axis = hinge if hinge is not None else [pl["pos"][0] + OX, pl["pos"][1], pl["pos"][2]]
    off = math.hypot(axis[0] - leaf_cf[0], axis[2] - leaf_cf[2])
    if off < 0.3 * max(leaf_size[0], leaf_size[2]):
        print("WARNING door %s: hinge axis %.2f studs from the leaf centre; set l4_hinge_pos or put the asset "
              "origin on the hinge edge" % (name, off))
    return {"name": name, "style": o.get("l4_door_style", "steel"), "openAngle": o.get("l4_open_angle", 95.0),
            "fixedOpenAngle": o.get("l4_fixed_open_angle"), "nonBlocking": bool(o.get("l4_nonblocking_open")),
            "leafCf": [float(x) for x in leaf_cf], "leafSize": [float(x) for x in leaf_size],
            "hingePos": [float(x) for x in hinge] if hinge is not None else None,
            "decalFrom": DUMP["parts"][src]["p"] if o.get("l4_decals") and src is not None else None,
            "decalOrig": DUMP["parts"][src]["cf"][:3] if o.get("l4_decals") and src is not None else None}


if not globals().get("L4_EXPORT_NO_RUN"):
    export()
