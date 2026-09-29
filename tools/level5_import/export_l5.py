# Headless: blender -b <blend> -P export_l5.py  (reads the .blend, writes only to OUT)
# Instanced geometry (2+ placements) -> one local-space asset per material, placed per copy.
# Everything else -> baked to world space and pooled per material.
# Every chunk: <= 20,000 triangles, <= 60,000 vertices, <= MAX_SPAN studs on any axis.
import bpy, mathutils, json, os, collections, math, base64, shutil
import numpy as np

OUT = r"G:\Roblox\_local\l5import"
K = 1 / 0.28                     # studs per metre
MAX_TRIS = 20000
MAX_SPAN = 1800.0                # studs; MeshPart hard limit is 2048
MAX_EDGE = 500.0                 # longer triangle edges are subdivided so chunks can stay small
shutil.rmtree(os.path.join(OUT, "chunks"), ignore_errors=True)
os.makedirs(os.path.join(OUT, "chunks"))
# Z-up metres -> Y-up studs: (x, y, z) -> (x, z, -y), a proper rotation.
C = np.array(((1, 0, 0), (0, 0, 1), (0, -1, 0)), dtype=np.float64)
Cm = mathutils.Matrix(C.tolist())

dg = bpy.context.evaluated_depsgraph_get()
vis = [o for o in bpy.data.objects if o.type == 'MESH' and o.visible_get()
       and not o.hide_render and all(not c.hide_render for c in o.users_collection)]
# volumetric haze has no Roblox equivalent (atmosphere is the shared Lighting's job)
vis = [o for o in vis if not any(s.material and s.material.name == "L4_Haze" for s in o.material_slots)]


def lin2srgb(c):
    return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def mat_info(m):
    info = {"name": m.name if m else "None", "color": [0.7, 0.7, 0.7], "alpha": 1.0,
            "emit": 0.0, "rough": 0.5, "metal": 0.0}
    if not m:
        return info
    col = list(m.diffuse_color[:3]); a = m.diffuse_color[3]
    if m.use_nodes:
        for n in m.node_tree.nodes:
            if n.type == 'BSDF_PRINCIPLED':
                bc = n.inputs['Base Color']
                if not bc.is_linked:
                    col = list(bc.default_value[:3])
                else:
                    src = bc.links[0].from_node
                    if src.type == 'VALTORGB':
                        els = src.color_ramp.elements
                        col = list(els[len(els) // 2].color[:3])
                    else:
                        for inp in getattr(src, "inputs", []):
                            if inp.type == 'RGBA' and not inp.is_linked:
                                col = list(inp.default_value[:3]); break
                a = n.inputs['Alpha'].default_value
                info["rough"] = n.inputs['Roughness'].default_value
                info["metal"] = n.inputs['Metallic'].default_value
                tw = n.inputs.get('Transmission Weight')
                if tw and tw.default_value > 0.3:
                    a = min(a, 0.35)
                es = n.inputs['Emission Strength'].default_value
                ec = n.inputs['Emission Color'].default_value
                if es > 0 and max(ec[:3]) > 0:
                    info["emit"] = es
                    if max(col) < 0.05:
                        col = list(ec[:3])
            elif n.type == 'EMISSION':
                info["emit"] = max(info["emit"], n.inputs['Strength'].default_value)
                col = list(n.inputs['Color'].default_value[:3])
    info["color"] = [round(min(1, max(0, lin2srgb(c))), 4) for c in col]
    info["alpha"] = round(a, 3)
    return info


def decompose(mw):
    loc, rot, sc = mw.decompose()
    rebuilt = mathutils.Matrix.LocRotScale(loc, rot, sc)
    ok = all(abs(rebuilt[i][j] - mw[i][j]) < 1e-4 * (1 + abs(mw[i][j])) for i in range(4) for j in range(4))
    return ok and all(s > 1e-6 for s in sc), loc, rot, sc


def mesh_tris(o, world):
    """-> {material name: (P[n,3,3], N[n,3,3])} in Roblox studs, local or world space."""
    ev = o.evaluated_get(dg)
    me = ev.to_mesh()
    me.calc_loop_triangles()
    nt = len(me.loop_triangles)
    out = {}
    if nt:
        co = np.empty(len(me.vertices) * 3); me.vertices.foreach_get("co", co); co = co.reshape(-1, 3)
        tv = np.empty(nt * 3, dtype=np.int64); me.loop_triangles.foreach_get("vertices", tv)
        tl = np.empty(nt * 3, dtype=np.int64); me.loop_triangles.foreach_get("loops", tl)
        mi = np.empty(nt, dtype=np.int64); me.loop_triangles.foreach_get("material_index", mi)
        cn = np.empty(len(me.loops) * 3); me.corner_normals.foreach_get("vector", cn); cn = cn.reshape(-1, 3)
        P = co[tv].reshape(nt, 3, 3); N = cn[tl].reshape(nt, 3, 3)
        if world:
            M = np.array(o.matrix_world)
            P = P @ M[:3, :3].T + M[:3, 3]
            N = N @ np.linalg.inv(M[:3, :3])     # inverse-transpose applied to row vectors
            if np.linalg.det(M[:3, :3]) < 0:     # mirrored: keep the winding facing outwards
                P = P[:, [0, 2, 1]]; N = N[:, [0, 2, 1]]
        P = (P @ C.T) * K
        N = N @ C.T
        N /= np.maximum(np.linalg.norm(N, axis=2, keepdims=True), 1e-9)
        slots = [s.material.name if s.material else "None" for s in ev.material_slots] or ["None"]
        for idx in np.unique(mi):
            name = slots[idx] if idx < len(slots) else "None"
            sel = mi == idx
            out[name] = (P[sel], N[sel])
    ev.to_mesh_clear()
    return out


def subdivide(P, N):
    for _ in range(12):
        e = np.max(np.linalg.norm(P - np.roll(P, 1, axis=1), axis=2), axis=1)
        big = e > MAX_EDGE
        if not big.any():
            return P, N
        bp, bn = P[big], N[big]
        mp = (bp + np.roll(bp, -1, axis=1)) / 2          # midpoint of edge i -> i+1
        mn = bn + np.roll(bn, -1, axis=1); mn /= np.maximum(np.linalg.norm(mn, axis=2, keepdims=True), 1e-9)
        def tri(a, b, c): return np.stack([a, b, c], axis=1)
        v0, v1, v2 = bp[:, 0], bp[:, 1], bp[:, 2]; m01, m12, m20 = mp[:, 0], mp[:, 1], mp[:, 2]
        n0, n1, n2 = bn[:, 0], bn[:, 1], bn[:, 2]; q01, q12, q20 = mn[:, 0], mn[:, 1], mn[:, 2]
        P = np.concatenate([P[~big], tri(v0, m01, m20), tri(m01, v1, m12), tri(m20, m12, v2), tri(m01, m12, m20)])
        N = np.concatenate([N[~big], tri(n0, q01, q20), tri(q01, n1, q12), tri(q20, q12, n2), tri(q01, q12, q20)])
    return P, N


def split(P, N):
    lo = P.reshape(-1, 3).min(0); hi = P.reshape(-1, 3).max(0); span = hi - lo
    if (len(P) <= MAX_TRIS and span.max() <= MAX_SPAN) or len(P) <= 1:
        return [(P, N)]
    ax = int(span.argmax())
    order = np.argsort(P[:, :, ax].mean(1), kind="stable")
    h = len(P) // 2
    a, b = order[:h], order[h:]
    return split(P[a], N[a]) + split(P[b], N[b])


manifest = {"studsPerMetre": K, "materials": {}, "chunks": [], "placements": [], "lights": []}
for m in bpy.data.materials:
    manifest["materials"][m.name] = mat_info(m)
manifest["materials"]["None"] = mat_info(None)
cid = 0


def emit(P, N, material, group, name):
    global cid
    P, N = subdivide(P, N)
    for p, n in split(P, N):
        lo = p.reshape(-1, 3).min(0); hi = p.reshape(-1, 3).max(0); ctr = (lo + hi) / 2
        pv, pi = np.unique(np.round(p.reshape(-1, 3) - ctr, 4), axis=0, return_inverse=True)
        nv, ni = np.unique(np.round(n.reshape(-1, 3), 3), axis=0, return_inverse=True)
        assert len(pv) <= 60000 and len(p) <= MAX_TRIS
        faces = np.stack([pi.reshape(-1, 3), ni.reshape(-1, 3)], axis=2).reshape(-1, 6)
        blob = (np.array([len(pv), len(nv), len(p)], dtype="<u4").tobytes()
                + pv.astype("<f4").tobytes() + nv.astype("<f4").tobytes() + faces.astype("<u4").tobytes())
        with open(os.path.join(OUT, "chunks", f"c{cid:05d}.b64"), "w") as fh:
            fh.write(base64.b64encode(blob).decode())
        manifest["chunks"].append({"id": cid, "group": group, "material": material, "tris": int(len(p)),
                                   "verts": int(len(pv)), "center": [round(float(x), 4) for x in ctr],
                                   "size": [round(float(x), 4) for x in hi - lo], "name": name[:90]})
        cid += 1


def mod_sig(m):
    # every setting of the modifier, so objects with different array counts/offsets never share an asset
    vals = []
    for p in m.bl_rna.properties:
        if p.identifier in ("rna_type", "name") or p.identifier.startswith("show_"):
            continue
        v = getattr(m, p.identifier)
        v = v.name if hasattr(v, "name") else (tuple(v) if hasattr(v, "__len__") and not isinstance(v, str) else v)
        vals.append((p.identifier, repr(v)))
    return (m.type, tuple(vals))


groups = collections.OrderedDict()
for o in vis:
    mats = tuple(s.material.name if s.material else "" for s in o.material_slots)
    if o.modifiers and not all(m.type == 'ARRAY' for m in o.modifiers):
        key = ("__obj__", o.name)
    else:
        key = (o.data.name, tuple(mod_sig(m) for m in o.modifiers), mats)
    if decompose(o.matrix_world)[0]:
        groups.setdefault(key, []).append(o)
    else:
        groups.setdefault(("__baked__", o.name), []).append(o)

pooled = collections.defaultdict(lambda: ([], []))
gi = 0
for key, objs in groups.items():
    if len(objs) >= 2 and key[0] not in ("__obj__", "__baked__"):
        for mname, (P, N) in mesh_tris(objs[0], world=False).items():
            emit(P, N, mname, gi, f"{objs[0].data.name}_{mname}")
        for o in objs:
            _, loc, rot, sc = decompose(o.matrix_world)
            Rr = Cm @ rot.to_matrix() @ Cm.transposed()
            manifest["placements"].append({
                "group": gi, "obj": o.name, "pos": [round(x * K, 4) for x in (Cm @ loc)],
                "rot": [round(Rr[i][j], 6) for i in range(3) for j in range(3)],
                # local-axis scale expressed in the Roblox local frame: X->X, Z->Y, Y->Z
                "scale": [round(sc[0], 6), round(sc[2], 6), round(sc[1], 6)]})
        gi += 1
    else:
        for o in objs:
            for mname, (P, N) in mesh_tris(o, world=True).items():
                pooled[mname][0].append(P); pooled[mname][1].append(N)
print("instanced groups", gi, "chunks", cid, "pooled materials", len(pooled), flush=True)
for mname, (Ps, Ns) in pooled.items():
    emit(np.concatenate(Ps), np.concatenate(Ns), mname, -1, f"World_{mname}")
print("after pooling chunks", cid, flush=True)

for o in bpy.data.objects:
    if o.type == 'LIGHT' and o.visible_get() and o.data.type in ('POINT', 'SPOT', 'AREA'):
        d = o.data
        fwd = Cm @ (o.matrix_world.to_3x3() @ mathutils.Vector((0, 0, -1)))
        manifest["lights"].append({"type": d.type, "pos": [x * K for x in (Cm @ o.matrix_world.translation)],
                                   "dir": list(fwd), "color": [round(min(1, lin2srgb(c)), 3) for c in d.color],
                                   "energy": d.energy, "angle": math.degrees(getattr(d, "spot_size", math.pi)),
                                   "name": o.name})
with open(os.path.join(OUT, "manifest.json"), "w") as fh:
    json.dump(manifest, fh)
ch = manifest["chunks"]
print("DONE chunks", len(ch), "tris", sum(c["tris"] for c in ch), "maxtris", max(c["tris"] for c in ch),
      "maxverts", max(c["verts"] for c in ch), "maxspan", max(max(c["size"]) for c in ch),
      "placements", len(manifest["placements"]), "lights", len(manifest["lights"]), flush=True)
