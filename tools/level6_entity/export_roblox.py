"""Level 6 entity: write the skinned mesh and every clip as compact JSON for import_to_studio.py.

  Blender -b --python tools/level6_entity/export_roblox.py

Blender (x, y, z) metres, facing -Y, becomes Roblox (-x, z, y) * STUDS_PER_METRE, facing -Z (LookVector).
Bones carry no rest rotation on the Roblox side, so a clip is one quaternion per bone per frame: the bone's
rotation in rest axes relative to its posed parent, which is exactly what Bone.Transform takes.
"""
import bpy, os, json, math
from mathutils import Matrix, Vector

ROOT = os.path.abspath("artifacts/level6-entity-20261003")
STUDS_PER_METRE = 6.3   # 1.3 m doll -> 8.2 studs: 40% taller than an avatar (owner, 2026-10-03)
bpy.ops.wm.open_mainfile(filepath=os.path.join(ROOT, "blend", "counter_animated.blend"))
scene = bpy.context.scene
arm = bpy.data.objects["CounterRig"]; mesh = bpy.data.objects["CounterDoll"]
M = Matrix(((-1, 0, 0), (0, 0, 1), (0, 1, 0)))
def P(v): return M @ Vector(v) * STUDS_PER_METRE

arm.animation_data.action = None
for pb in arm.pose.bones:
    pb.rotation_quaternion = (1, 0, 0, 0); pb.location = (0, 0, 0)
scene.frame_set(1)

me = mesh.data
me.calc_loop_triangles()
verts = [P(mesh.matrix_world @ v.co) for v in me.vertices]
lo = Vector((min(v.x for v in verts), min(v.y for v in verts), min(v.z for v in verts)))
hi = Vector((max(v.x for v in verts), max(v.y for v in verts), max(v.z for v in verts)))
centre = (lo + hi) / 2            # the MeshPart sits on its bounding-box centre
feet = lo.y - centre.y            # sole height in mesh space

SKIP = {"head_end", "headfront"}
bones = [b for b in arm.data.bones if b.name not in SKIP]
bone_index = {b.name: i for i, b in enumerate(bones)}
bone_out = [{"name": b.name, "parent": b.parent.name if b.parent else None,
             "pos": [round(c, 4) for c in (P(b.head_local) - centre)]} for b in bones]

group_bone = {g.index: bone_index.get(g.name) for g in mesh.vertex_groups}
V, W = [], []
for v, p in zip(me.vertices, verts):
    q = p - centre
    V += [round(q.x * 1000), round(q.y * 1000), round(q.z * 1000)]
    inf = [(group_bone[g.group], g.weight) for g in v.groups if g.weight > 1e-4 and group_bone.get(g.group) is not None]
    inf.sort(key=lambda t: -t[1]); inf = inf[:4]
    if not inf: inf = [(bone_index["Hips"], 1.0)]
    total = sum(w for _, w in inf)
    W.append(len(inf))
    for b, w in inf: W += [b, round(w / total * 1000)]

uv_layer = me.uv_layers.active.data
uv_ids, uvs, n_ids, normals, T = {}, [], {}, [], []
corner_normals = me.corner_normals
for tri in me.loop_triangles:
    row_uv, row_n = [], []
    for loop in tri.loops:
        u = uv_layer[loop].uv
        key = (round(u.x * 10000), round((1 - u.y) * 10000))
        if key not in uv_ids: uv_ids[key] = len(uvs) // 2; uvs += key
        row_uv.append(uv_ids[key])
        n = M @ Vector(corner_normals[loop].vector)
        nk = (round(n.x * 1000), round(n.y * 1000), round(n.z * 1000))
        if nk not in n_ids: n_ids[nk] = len(normals) // 3; normals += nk
        row_n.append(n_ids[nk])
    T += [*tri.vertices, *row_uv, *row_n]

X = os.path.join(ROOT, "export"); os.makedirs(X, exist_ok=True)
json.dump({"studsPerMetre": STUDS_PER_METRE, "size": [round(c, 4) for c in (hi - lo)], "feetY": round(feet, 4),
           "bones": bone_out, "V": V, "W": W, "UV": uvs, "N": normals, "T": T},
          open(os.path.join(X, "roblox_mesh.json"), "w"), separators=(",", ":"))
print("MESH verts", len(V) // 3, "tris", len(T) // 9, "uvs", len(uvs) // 2, "normals", len(normals) // 3, "size", tuple(round(c, 2) for c in (hi - lo)))

REST = {b.name: b.matrix_local.to_3x3() for b in arm.data.bones}
meta = {c["name"]: c for c in json.load(open(os.path.join(X, "animations.json")))["clips"]}
clips = {}
for name, info in meta.items():
    for pb in arm.pose.bones:   # a clip that keys only some bones must not inherit the last clip's pose
        pb.rotation_quaternion = (1, 0, 0, 0); pb.location = (0, 0, 0)
    arm.animation_data.action = bpy.data.actions[name]
    tracks = {b.name: [] for b in bones}; hips = []
    for f in range(1, info["frames"] + 1):
        scene.frame_set(f)
        for b in bones:
            pb = arm.pose.bones[b.name]; R = REST[b.name]
            D = M @ (R @ pb.rotation_quaternion.to_matrix() @ R.inverted()) @ M.transposed()
            q = D.to_quaternion()
            t = tracks[b.name]
            if t and (t[-4] * q.x + t[-3] * q.y + t[-2] * q.z + t[-1] * q.w) < 0: q.negate()
            t += [round(q.x * 10000), round(q.y * 10000), round(q.z * 10000), round(q.w * 10000)]
        h = P(REST["Hips"] @ Vector(arm.pose.bones["Hips"].location))
        hips += [round(h.x * 1000), round(h.y * 1000), round(h.z * 1000)]
    keep = {}
    for b, t in tracks.items():
        if any(abs(t[i]) > 3 or abs(t[i + 1]) > 3 or abs(t[i + 2]) > 3 for i in range(0, len(t), 4)):
            keep[b] = t
    clip = {"frames": info["frames"], "fps": info["fps"], "loop": info["loop"], "bones": keep}
    if any(abs(c) > 1 for c in hips): clip["hips"] = hips
    clips[name] = clip
    print("CLIP %-12s frames %3d bones %2d json %d bytes" % (name, info["frames"], len(keep), len(json.dumps(clip, separators=(",", ":")))))
json.dump(clips, open(os.path.join(X, "roblox_clips.json"), "w"), separators=(",", ":"))
