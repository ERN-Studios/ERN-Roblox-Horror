# blender -b luna_norm.blend -P build_rig.py -- <out.blend>
# Quadruped armature for Luna (studs, nose +Y, +X = her right). Joint table below is the single source of truth.
import bpy, sys, json
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
out = argv[0]

# name: (head, tail, parent, deform)
J = {
    "Root":       ((0, 0, 0),            (0, 0.6, 0),           None,        False),
    "Hips":       ((0, -1.15, 1.85),     (0, -0.55, 1.92),      "Root",      True),
    "Spine1":     ((0, -0.55, 1.92),     (0, 0.0, 1.97),        "Hips",      True),
    "Spine2":     ((0, 0.0, 1.97),       (0, 0.5, 2.0),         "Spine1",    True),
    "Chest":      ((0, 0.5, 2.0),        (0, 0.95, 2.12),       "Spine2",    True),
    "Neck":       ((0, 0.95, 2.12),      (0.04, 1.38, 2.62),    "Chest",     True),
    "Head":       ((0.04, 1.38, 2.62),   (0.33, 2.12, 2.52),    "Neck",      True),
    "EarL":       ((-0.12, 1.5, 2.92),   (-0.09, 1.62, 3.22),   "Head",      True),
    "EarR":       ((0.2, 1.4, 2.88),     (0.25, 1.49, 3.17),    "Head",      True),
    "Tail1":      ((0, -1.5, 1.78),      (0.03, -1.74, 1.52),   "Hips",      True),
    "Tail2":      ((0.03, -1.74, 1.52),  (0.08, -1.94, 1.22),   "Tail1",     True),
    "Tail3":      ((0.08, -1.94, 1.22),  (0.17, -2.08, 0.95),   "Tail2",     True),
    "Tail4":      ((0.17, -2.08, 0.95),  (0.28, -2.18, 0.7),    "Tail3",     True),
}
for side, sx in (("L", -1), ("R", 1)):
    fx = 0.25 * sx
    hy = -1.33 if side == "L" else -1.11      # hind paw y differs per side in the scanned stance
    fy = 1.10 if side == "L" else 1.16
    J.update({
        f"Scapula{side}":  ((0.17 * sx, 0.85, 2.02), (fx, 1.02, 1.45), "Chest", True),
        f"UpperArm{side}": ((fx, 1.02, 1.45), (fx, 0.8, 1.02), f"Scapula{side}", True),
        f"Forearm{side}":  ((fx, 0.8, 1.02), (fx - 0.01 * sx, 0.8, 0.32), f"UpperArm{side}", True),
        f"FrontPaw{side}": ((fx - 0.01 * sx, 0.8, 0.32), (fx, fy + 0.05, 0.05), f"Forearm{side}", True),
        f"Thigh{side}":    ((0.24 * sx, -1.2, 1.72), (0.25 * sx, hy + 0.3, 1.12), "Hips", True),
        f"Shin{side}":     ((0.25 * sx, hy + 0.3, 1.12), (0.28 * sx, hy - 0.17, 0.58), f"Thigh{side}", True),
        f"Hock{side}":     ((0.28 * sx, hy - 0.17, 0.58), (0.3 * sx, hy - 0.05, 0.12), f"Shin{side}", True),
        f"HindPaw{side}":  ((0.3 * sx, hy - 0.05, 0.12), (0.32 * sx, hy + 0.2, 0.04), f"Hock{side}", True),
    })

mesh = bpy.data.objects["LunaMesh"]
arm_data = bpy.data.armatures.new("LunaRig")
arm = bpy.data.objects.new("LunaRig", arm_data)
bpy.context.scene.collection.objects.link(arm)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="EDIT")
for name, (h, t, parent, deform) in J.items():
    b = arm_data.edit_bones.new(name)
    b.head, b.tail = Vector(h), Vector(t)
    b.roll = 0.0
    b.use_deform = deform
for name, (h, t, parent, deform) in J.items():
    if parent:
        b = arm_data.edit_bones[name]
        b.parent = arm_data.edit_bones[parent]
        b.use_connect = False
bpy.ops.object.mode_set(mode="OBJECT")

# automatic (bone heat) weights
bpy.ops.object.select_all(action="DESELECT")
mesh.select_set(True); arm.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.parent_set(type="ARMATURE_AUTO")
deform = {n for n, j in J.items() if j[3]}
unweighted = 0
for v in mesh.data.vertices:
    if not any(g.weight > 1e-4 and mesh.vertex_groups[g.group].name in deform for g in v.groups):
        unweighted += 1
print("RIG", json.dumps({"bones": len(J), "unweighted": unweighted, "verts": len(mesh.data.vertices)}))
bpy.ops.wm.save_as_mainfile(filepath=out)
