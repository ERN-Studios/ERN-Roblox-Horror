# blender -b luna_rig2.blend -P posetest.py -- <out_prefix>
# Extreme test poses to judge skin weights. Rotations are given about WORLD axes at each bone's head (degrees).
import bpy, sys, math
from mathutils import Vector, Quaternion

argv = sys.argv[sys.argv.index("--") + 1:]
out = argv[0]
arm = bpy.data.objects["LunaRig"]
scene = bpy.context.scene

def reset():
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"; pb.rotation_quaternion = (1, 0, 0, 0); pb.location = (0, 0, 0)

def rot(name, axis, deg):
    """rotate bone about a world axis, composed in pose space (parents already applied)"""
    bpy.context.view_layer.update()
    pb = arm.pose.bones[name]
    world = pb.matrix.to_3x3()                      # current armature-space orientation
    local_axis = world.inverted() @ Vector(axis)
    pb.rotation_quaternion = pb.rotation_quaternion @ Quaternion(local_axis.normalized(), math.radians(deg))
    bpy.context.view_layer.update()

POSES = {
    "paw": [("ScapulaR", (1, 0, 0), -10), ("UpperArmR", (1, 0, 0), -70), ("ForearmR", (1, 0, 0), 40), ("FrontPawR", (1, 0, 0), 30)],
    "fold": [("Hips", (1, 0, 0), 25), ("ThighL", (1, 0, 0), -45), ("ShinL", (1, 0, 0), 70), ("HockL", (1, 0, 0), -60),
             ("ThighR", (1, 0, 0), -45), ("ShinR", (1, 0, 0), 70), ("HockR", (1, 0, 0), -60)],
    "sniff": [("Neck", (1, 0, 0), 35), ("Neck", (0, 0, 1), 20), ("Head", (0, 0, 1), 20), ("EarL", (1, 0, 0), 30)],
    "wag": [("Tail1", (0, 0, 1), 25), ("Tail2", (0, 0, 1), 25), ("Tail3", (0, 0, 1), 25), ("Tail4", (0, 0, 1), 20),
            ("Tail1", (1, 0, 0), -30)],
    "curl": [("Spine1", (0, 0, 1), 18), ("Spine2", (0, 0, 1), 18), ("Chest", (0, 0, 1), 18), ("Neck", (0, 0, 1), 30)],
}
sys.argv = [sys.argv[0], "--", out]
for name, ops in POSES.items():
    reset()
    for b, ax, d in ops:
        rot(b, ax, d)
    exec(open(r"G:\Roblox\_local\luna\scripts\render_views.py").read().replace("argv = sys.argv[sys.argv.index(\"--\") + 1:]",
         f"argv = [r'{out}_{name}', '-', '-', 'side,three,front']"))
