"""Level 6 entity ("The Counter"): import Meshy's rigged doll, clean it for Roblox and save the base .blend.

Run from the repo root:
  Blender -b --python tools/level6_entity/build_base.py
"""
import bpy, os
from mathutils import Vector

ROOT = os.path.abspath("artifacts/level6-entity-20261003")
SRC = os.path.join(ROOT, "meshy")
OUT = os.path.join(ROOT, "blend")
os.makedirs(OUT, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.fps = 30  # Meshy's clips are 30 fps; keys land on whole frames

def import_glb(name):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, name))
    return [o for o in bpy.data.objects if o not in before]

new = import_glb("counter_rigged.glb")
arm = next(o for o in new if o.type == "ARMATURE")
mesh = next(o for o in new if o.type == "MESH" and o.vertex_groups)
for o in new:
    if o not in (arm, mesh):
        bpy.data.objects.remove(o, do_unlink=True)
arm.name = "CounterRig"; arm.data.name = "CounterRig"
mesh.name = "CounterDoll"; mesh.data.name = "CounterDoll"
if arm.animation_data:
    arm.animation_data.action = None

# Meshy's walk and run, kept as source actions for the legs
for fname, aname in (("meshy_walking.glb", "SRC_Walk"), ("meshy_running.glb", "SRC_Run")):
    objs = import_glb(fname)
    a = next(o for o in objs if o.type == "ARMATURE")
    act = a.animation_data.action
    act.name = aname
    act.use_fake_user = True
    for o in objs:
        bpy.data.objects.remove(o, do_unlink=True)
for a in list(bpy.data.actions):
    if not a.name.startswith("SRC_"):
        bpy.data.actions.remove(a)

# Metres with unit scale on both objects (Meshy ships a 0.01-scaled armature in centimetres).
# The SRC_ actions keep their Hips location in centimetres; build_animations.py converts.
bpy.ops.object.select_all(action="DESELECT")
arm.select_set(True); mesh.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
print("SCALES", tuple(arm.scale), tuple(mesh.scale), "DIMS", tuple(round(x, 3) for x in mesh.dimensions))
bpy.ops.object.select_all(action="DESELECT")

# Roblox skinning: at most 4 bone influences per vertex, normalised
bpy.context.view_layer.objects.active = mesh
mesh.select_set(True)
bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
bpy.ops.object.vertex_group_normalize_all(group_select_mode="ALL", lock_active=False)

me = mesh.data
print("TRIS", sum(len(p.vertices) - 2 for p in me.polygons), "VERTS", len(me.vertices))
mw = mesh.matrix_world
def bbox(group):
    gi = mesh.vertex_groups[group].index
    pts = [mw @ v.co for v in me.vertices if any(g.group == gi and g.weight > 0.5 for g in v.groups)]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return [round(x, 3) for x in (*lo, *hi)]
for g in ("Head", "LeftHand", "RightHand", "LeftFoot"):
    print("BBOX", g, bbox(g))

for b in arm.data.bones:
    print("BONE %-14s %-14s head=(%.3f, %.3f, %.3f)" % (b.name, b.parent.name if b.parent else "-", *b.head_local))
for an in ("SRC_Walk", "SRC_Run"):
    arm.animation_data.action = bpy.data.actions[an]
    a = bpy.data.actions[an]
    f0, f1 = (int(round(x)) for x in a.frame_range)
    locs = []
    for f in range(f0, f1 + 1):
        scene.frame_set(f)
        locs.append(tuple(round(x, 2) for x in arm.pose.bones["Hips"].location))
    print("ACTION", an, f0, f1, "hips loc first/mid/last", locs[0], locs[len(locs)//2], locs[-1])
    print("  bones with loc anim:", sorted({pb.name for pb in arm.pose.bones if pb.location.length > 1e-4}))
arm.animation_data.action = None
scene.frame_set(1)
for pb in arm.pose.bones:
    pb.location = (0, 0, 0); pb.rotation_quaternion = (1, 0, 0, 0); pb.rotation_mode = "QUATERNION"

# QA render of the rest pose
import math
cam = bpy.data.objects.new("QACam", bpy.data.cameras.new("QACam")); scene.collection.objects.link(cam)
cam.data.type = "ORTHO"; cam.data.ortho_scale = 1.7
scene.camera = cam
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"; scene.display.shading.color_type = "TEXTURE"
scene.render.resolution_x = 700; scene.render.resolution_y = 700
for tag, loc, rz in (("front", (0, -4, 0.68), 0), ("side", (-4, 0, 0.68), -90), ("back", (0, 4, 0.68), 180)):
    cam.location = loc; cam.rotation_euler = (math.radians(90), 0, math.radians(rz))
    scene.render.filepath = os.path.join(ROOT, "renders", "rest_" + tag + ".png")
    bpy.ops.render.render(write_still=True)

bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "counter_base.blend"))
print("SAVED")
