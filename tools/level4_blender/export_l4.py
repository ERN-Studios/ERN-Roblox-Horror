# Level 4 cinema: Blender -> Roblox export (run inside Blender, MCP or `blender -b <blend> -P export_l4.py`).
# Writes <OUT>/chunks/cNNNNN.b64 + manifest.json:
#   * architecture (unit-mesh parts) is baked to world space and pooled per material;
#   * every prop and door leaf is an instanced asset (one mesh per material) placed per object, so each
#     one becomes its own Model in Roblox;
#   * UVs are box-projected (world metres for pools, object metres for assets) / the material's tile size,
#     matching the Blender materials, so SurfaceAppearance textures tile the same way;
#   * colliders, decal carriers and flicker fixtures come from l4_layout.json, so the invisible collision
#     is exactly the Studio layout plus the owner's edits.
# Chunk limits: <= 20,000 triangles, <= 60,000 vertices, <= 1800 studs on any axis.
import bpy, mathutils, json, os, math, re, base64, shutil, collections
import numpy as np

OUT = r"G:\Roblox\_local\l4blender\export"
HERE = r"G:\Roblox\MongoTV\tools\level4_blender"
K = 1 / 0.28
MAX_TRIS, MAX_SPAN = 20000, 1800.0
C = np.array(((1, 0, 0), (0, 0, 1), (0, -1, 0)), dtype=np.float64)   # Blender (x,y,z) -> Roblox (x,z,-y)
Cm = mathutils.Matrix(C.tolist())
LAYOUT = json.load(open(os.path.join(HERE, "l4_layout.json")))
DUMP = json.load(open(os.path.join(HERE, "l4_dump.json")))
shutil.rmtree(os.path.join(OUT, "chunks"), ignore_errors=True)
os.makedirs(os.path.join(OUT, "chunks"))

ROBLOX_MAT = {"carpet": "Carpet", "carpet_arcade": "Carpet", "velvet": "Fabric", "acoustic": "Fabric",
              "plaster": "Plaster", "wall_dark": "Plaster", "marble": "Marble", "granite": "Granite",
              "tile": "CeramicTiles", "ceiling": "SmoothPlastic", "wood": "Wood", "metal": "Metal",
              "concrete": "Concrete", "neon": "Neon", "glass": "Glass", "screen": "SmoothPlastic",
              "plastic": "SmoothPlastic", "prop": "SmoothPlastic"}
FLICKER = {p["p"] for p in LAYOUT["parts"] if (p.get("at") or {}).get("OccasionalFlicker") == "true"}


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
    return {"name": name, "sem": sem, "color": list(m.get("l4_color", [180, 180, 180])) if m else [180, 180, 180],
            "tex": tex, "tile": float(m.get("l4_tile", 1.0)) if m else 1.0,
            "alpha": float(m.get("l4_alpha", 1.0)) if m else 1.0, "roblox": rm}


def tris(o, world):
    """-> {material name: (P[n,3,3] blender metres, N[n,3,3])}."""
    me = o.data
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
    if world:
        Mw = np.array(o.matrix_world)
        P = P @ Mw[:3, :3].T + Mw[:3, 3]
        N = N @ np.linalg.inv(Mw[:3, :3])
        if np.linalg.det(Mw[:3, :3]) < 0:
            P = P[:, [0, 2, 1]]; N = N[:, [0, 2, 1]]
    N /= np.maximum(np.linalg.norm(N, axis=2, keepdims=True), 1e-9)
    slots = [s.material for s in o.material_slots] or [None]
    for idx in np.unique(mi):
        m = slots[idx] if idx < len(slots) else None
        name = m.name if m else "None"
        sel = mi == idx
        if name in out:
            out[name] = (np.concatenate([out[name][0], P[sel]]), np.concatenate([out[name][1], N[sel]]))
        else:
            out[name] = (P[sel], N[sel])
    return out


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


manifest = {"studsPerMetre": K, "materials": {}, "chunks": [], "placements": []}
cid = 0


def emit(P, N, mname, group, name, tile):
    global cid
    U = box_uv(P, tile)
    for p, n, u in split(P, N, U):
        pr = (p @ C.T) * K                          # studs, Roblox axes
        nr = n @ C.T
        lo = pr.reshape(-1, 3).min(0); hi = pr.reshape(-1, 3).max(0); ctr = (lo + hi) / 2
        u = u - np.floor(u.reshape(-1, 2).min(0))   # keep UVs small, whole-tile shift keeps the tiling
        pv, pi = np.unique(np.round(pr.reshape(-1, 3) - ctr, 4), axis=0, return_inverse=True)
        nv, ni = np.unique(np.round(nr.reshape(-1, 3), 3), axis=0, return_inverse=True)
        uv, ui = np.unique(np.round(u.reshape(-1, 2), 4), axis=0, return_inverse=True)
        assert len(pv) <= 60000 and len(p) <= MAX_TRIS
        faces = np.stack([pi.reshape(-1, 3), ni.reshape(-1, 3), ui.reshape(-1, 3)], axis=2).reshape(-1, 9)
        blob = (np.array([len(pv), len(nv), len(uv), len(p)], dtype="<u4").tobytes()
                + pv.astype("<f4").tobytes() + nv.astype("<f4").tobytes() + uv.astype("<f4").tobytes()
                + faces.astype("<u4").tobytes())
        with open(os.path.join(OUT, "chunks", "c%05d.b64" % cid), "w") as fh:
            fh.write(base64.b64encode(blob).decode())
        manifest["chunks"].append({"id": cid, "group": group, "material": mname, "tris": int(len(p)),
                                   "verts": int(len(pv)), "center": [round(float(x), 4) for x in ctr],
                                   "size": [round(float(x), 4) for x in np.maximum(hi - lo, 0.05)],
                                   "name": name[:90]})
        cid += 1


def visible_meshes():
    root = bpy.data.collections["L4 Cinema"]
    for o in root.all_objects:
        if o.type == "MESH" and not o.hide_render and o.visible_get():
            yield o


for m in bpy.data.materials:
    if m.name.startswith("L4"):
        manifest["materials"][m.name] = mat_info(m)
manifest["materials"]["None"] = mat_info(None)

groups = collections.OrderedDict()
pooled = collections.defaultdict(lambda: ([], []))
for o in visible_meshes():
    if o.get("l4_path") in FLICKER:
        continue                                    # Studio clones these fixtures with their lights
    if o.get("l4_prop") or o.get("l4_door_leaf"):
        groups.setdefault(o.data.name, []).append(o)
    else:
        for mname, (P, N) in tris(o, True).items():
            pooled[mname][0].append(P); pooled[mname][1].append(N)

gi = 0
for mesh_name, objs in groups.items():
    for mname, (P, N) in tris(objs[0], False).items():
        emit(P, N, mname, gi, "%s_%s" % (mesh_name, mname), manifest["materials"].get(mname, {}).get("tile", 1))
    for o in objs:
        loc, rot, sc = o.matrix_world.decompose()
        Rr = Cm @ rot.to_matrix() @ Cm.transposed()
        pl = {"group": gi, "name": o.name, "model": o.get("l4_model", o.name),
              "pos": [round(x * K, 4) for x in (Cm @ loc)],
              "rot": [round(Rr[i][j], 6) for i in range(3) for j in range(3)],
              "scale": [round(sc[0], 6), round(sc[2], 6), round(sc[1], 6)]}
        if o.get("l4_attrs"):
            pl["attrs"] = json.loads(o["l4_attrs"])
        if o.get("l4_door_leaf"):
            src = LAYOUT["parts"][o["l4_src"]]
            pl["door"] = {"name": o["l4_door"], "style": o["l4_door_style"], "openAngle": o["l4_open_angle"],
                          "fixedOpenAngle": o.get("l4_fixed_open_angle"),
                          "nonBlocking": bool(o.get("l4_nonblocking_open")),
                          "leafCf": src["cf"], "leafSize": src["s"],
                          "decalFrom": DUMP["parts"][o["l4_src"]]["p"] if o.get("l4_decals") else None}
        manifest["placements"].append(pl)
    gi += 1
print("instanced groups", gi, "chunks", cid, flush=True)
for mname, (Ps, Ns) in pooled.items():
    emit(np.concatenate(Ps), np.concatenate(Ns), mname, -1, "World_" + mname,
         manifest["materials"].get(mname, {}).get("tile", 1))
print("after pooling chunks", cid, flush=True)

# ---- colliders, decal carriers, flicker fixtures, exit: straight from the layout (studs, Studio frame)
door_parts = re.compile(r"^AutomaticDoors/(?!.*_Post$)")
cols, carriers, flick = [], [], []
for i, p in enumerate(LAYOUT["parts"]):
    orig = DUMP["parts"][i]["cf"][:3] if i < len(DUMP["parts"]) else None
    if p["cc"] and not door_parts.search(p["p"]):
        cols.append({"cf": p["cf"], "s": p["s"], "m": p["m"], "tags": p.get("tags", []),
                     "sh": p.get("sh") or ("Block" if p["c"] != "WedgePart" else "Wedge")})
    if orig and any(d[0] in ("Decal", "SurfaceGui") for d in p.get("dec", [])) and not p["p"].startswith("AutomaticDoors/"):
        carriers.append({"path": DUMP["parts"][i]["p"], "orig": orig, "cf": p["cf"], "s": p["s"]})
    if p["p"] in FLICKER and orig:
        flick.append({"path": p["p"], "orig": orig})
manifest["colliders"] = cols
manifest["carriers"] = carriers
manifest["flicker"] = flick
manifest["flickerPaths"] = sorted(FLICKER)
with open(os.path.join(OUT, "manifest.json"), "w") as fh:
    json.dump(manifest, fh)
ch = manifest["chunks"]
print("DONE chunks", len(ch), "tris", sum(c["tris"] for c in ch), "maxtris", max(c["tris"] for c in ch),
      "placements", len(manifest["placements"]), "colliders", len(cols), "carriers", len(carriers),
      "flicker", len(flick), flush=True)
