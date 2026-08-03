"""Build the Level 1 entity's ground-pin knockout kill in open Blender.

The entity catches the player with articulated fingers, drags them down, pins
them with its left hand, closes the right hand into a fist, and lands one clear
fatal punch. Roblox owns victim staging; this action remains in-place.
"""

from __future__ import annotations

import math

import bpy
from mathutils import Matrix, Vector


ACTION_NAME = "ENT_KILL_GroundPinPunch_IP_v002"
ARMATURE_NAME = "Armature"
FPS = 30
END_FRAME = 150
DEATH_FRAME = 124

armature = bpy.data.objects[ARMATURE_NAME]
if armature.animation_data is None:
    armature.animation_data_create()

for pose_bone in armature.pose.bones:
    for constraint in pose_bone.constraints:
        if constraint.type == "IK":
            constraint.influence = 1.0 if "Arm" in pose_bone.name else 0.0
            if pose_bone.name == "LeftForeArm":
                constraint.pole_target = armature
                constraint.pole_subtarget = "POLE_LeftArm"
            elif pose_bone.name == "RightForeArm":
                constraint.pole_target = armature
                constraint.pole_subtarget = "POLE_RightArm"


def sample(action_name: str, frame: int) -> dict[str, Matrix]:
    armature.animation_data.action = bpy.data.actions[action_name]
    bpy.context.scene.frame_set(frame)
    bpy.context.view_layer.update()
    evaluated = armature.evaluated_get(bpy.context.evaluated_depsgraph_get())
    return {bone.name: bone.matrix_basis.copy() for bone in evaluated.pose.bones}


watch = sample("ENT_IDLE_Watch_Loop_IP_v003", 1)
lunge = {
    frame: sample("ENT_ATK_Lunge_FromChase_IP_v003", frame)
    for frame in (1, 8, 16, 24, 34, 44, 52)
}

old = bpy.data.actions.get(ACTION_NAME)
if old:
    bpy.data.actions.remove(old)
action = bpy.data.actions.new(ACTION_NAME)
action.use_fake_user = True
action["MongoTVRole"] = "EntityKill"
action["MongoTVDesign"] = "finger grab, grounded pin, right-fist knockout"
action["MongoTVDeathFrame"] = DEATH_FRAME
armature.animation_data.action = action


def rotated(matrix: Matrix, x: float = 0, y: float = 0, z: float = 0) -> Matrix:
    result_matrix = matrix.copy()
    if x:
        result_matrix @= Matrix.Rotation(math.radians(x), 4, "X")
    if y:
        result_matrix @= Matrix.Rotation(math.radians(y), 4, "Y")
    if z:
        result_matrix @= Matrix.Rotation(math.radians(z), 4, "Z")
    return result_matrix


def finger_rotation(name: str, curl: float, thumb: float) -> tuple[float, float, float]:
    """Return a readable local flex pose for the imported finger chains."""
    if "Thumb" in name:
        segment = 2 if name.endswith("2") else 1
        side = -1 if name.startswith("Left") else 1
        return (28 * thumb * segment, 18 * thumb, side * 24 * thumb)
    for segment, degrees in (("1", 34), ("2", 58), ("3", 68)):
        if name.endswith(segment):
            return (degrees * curl, 0, 0)
    return (0, 0, 0)


def keyed_pose(
    frame: int,
    source: dict[str, Matrix],
    accents: dict[str, tuple[float, float, float]] | None = None,
    left_curl: float = 0,
    right_curl: float = 0,
) -> None:
    accents = accents or {}
    for bone in armature.pose.bones:
        matrix = source.get(bone.name, watch[bone.name]).copy()
        if bone.name == "Hips":
            matrix.translation = watch["Hips"].translation
        if bone.name in accents:
            matrix = rotated(matrix, *accents[bone.name])
        if bone.name.startswith("LeftHand") and bone.name != "LeftHand":
            matrix = rotated(matrix, *finger_rotation(bone.name, left_curl, left_curl))
        elif bone.name.startswith("RightHand") and bone.name != "RightHand":
            matrix = rotated(matrix, *finger_rotation(bone.name, right_curl, right_curl))
        bone.rotation_mode = "QUATERNION"
        bone.matrix_basis = matrix
        bone.keyframe_insert("location", frame=frame, group=bone.name)
        bone.keyframe_insert("rotation_quaternion", frame=frame, group=bone.name)
        bone.keyframe_insert("scale", frame=frame, group=bone.name)


# 1–24: readable catch. Hands stay open on the reach so the finger closure reads.
keyed_pose(1, watch)
keyed_pose(10, lunge[8], {
    "Spine02": (-7, 0, 0), "Spine": (8, 0, 0), "neck": (-5, 0, 0),
})
keyed_pose(24, lunge[16], {
    "Spine02": (10, 0, 0), "Spine": (-8, 0, 0),
    "LeftArm": (-10, 0, 7), "RightArm": (-10, 0, -7),
    "LeftForeArm": (-14, 0, 4), "RightForeArm": (-14, 0, -4),
})

# 36–54: both hands close around the victim and pull them off balance.
keyed_pose(36, lunge[24], {
    "LeftForeArm": (-24, 0, 7), "RightForeArm": (-24, 0, -7),
    "LeftHand": (0, -10, 12), "RightHand": (0, 10, -12),
}, left_curl=0.58, right_curl=0.58)
keyed_pose(46, lunge[34], {
    "Hips": (-5, 0, 0), "Spine02": (-15, 0, 0), "Spine": (17, 0, 0),
    "LeftArm": (-23, 0, 8), "RightArm": (-23, 0, -8),
    "LeftForeArm": (-28, 0, 5), "RightForeArm": (-28, 0, -5),
}, left_curl=0.78, right_curl=0.78)
keyed_pose(56, lunge[44], {
    "Spine02": (16, 0, 0), "Spine": (-20, 0, 0),
    "neck": (-16, 0, 0), "Head": (-10, 0, 0),
}, left_curl=0.85, right_curl=0.85)

# 68–88: drive down, settle above the victim, keep the left hand as the pin.
keyed_pose(68, lunge[44], {
    "Spine02": (24, 0, 0), "Spine": (-28, 0, 0),
    "LeftArm": (-32, 0, 8), "RightArm": (-30, 0, -8),
    "LeftForeArm": (-34, 0, 5), "RightForeArm": (-32, 0, -5),
}, left_curl=0.88, right_curl=0.82)
keyed_pose(82, lunge[52], {
    "Spine02": (-24, 0, 0), "Spine": (31, 0, 0),
    "neck": (18, 0, 0), "Head": (10, 0, 0),
    "LeftArm": (-38, 0, 12), "LeftForeArm": (-42, 0, 8),
    "RightArm": (-16, 0, -10), "RightForeArm": (-18, 0, -8),
}, left_curl=0.92, right_curl=0.35)
keyed_pose(92, lunge[34], {
    "Spine02": (-28, 0, -7), "Spine": (34, 0, 8),
    "LeftArm": (-42, 0, 14), "LeftForeArm": (-46, 0, 10),
    "RightShoulder": (0, 0, 12), "RightArm": (18, -8, -28),
    "RightForeArm": (42, 0, -18), "RightHand": (8, 4, -10),
}, left_curl=0.95, right_curl=0.75)

# 104–124: close a clear fist, hold a short anticipation, then punch through.
keyed_pose(104, lunge[34], {
    "Spine02": (-34, 0, -10), "Spine": (38, 0, 12),
    "LeftArm": (-43, 0, 14), "LeftForeArm": (-46, 0, 10),
    "RightShoulder": (0, 0, 18), "RightArm": (32, -12, -42),
    "RightForeArm": (58, 0, -24), "RightHand": (14, 8, -14),
    "neck": (18, 0, -8), "Head": (12, 0, -5),
}, left_curl=0.95, right_curl=1.0)
keyed_pose(114, lunge[34], {
    "Spine02": (-38, 0, -14), "Spine": (42, 0, 17),
    "LeftArm": (-44, 0, 14), "LeftForeArm": (-48, 0, 10),
    "RightShoulder": (0, 0, 22), "RightArm": (38, -14, -50),
    "RightForeArm": (66, 0, -28), "RightHand": (16, 9, -16),
    "neck": (24, 0, -10), "Head": (15, 0, -7),
}, left_curl=0.96, right_curl=1.0)
keyed_pose(DEATH_FRAME, lunge[34], {
    "Spine02": (27, 0, 14), "Spine": (-38, 0, -20),
    "LeftArm": (-45, 0, 12), "LeftForeArm": (-48, 0, 9),
    "RightShoulder": (0, 0, -12), "RightArm": (-58, 8, 24),
    "RightForeArm": (-70, 0, 18), "RightHand": (-10, -4, 8),
    "neck": (-28, 0, 12), "Head": (-18, 0, 8),
}, left_curl=0.96, right_curl=1.0)

# Follow-through stays heavy; the entity does not snap upright over the corpse.
keyed_pose(134, lunge[44], {
    "Spine02": (18, 0, 8), "Spine": (-25, 0, -12),
    "LeftArm": (-38, 0, 10), "RightArm": (-40, 0, -10),
}, left_curl=0.8, right_curl=0.94)
keyed_pose(150, lunge[52], {
    "Spine02": (-12, 0, 0), "Spine": (16, 0, 0), "neck": (8, 0, 0),
}, left_curl=0.45, right_curl=0.65)

# Drive the hand contact points with the rig's real IK controls. The source
# action supplies weight and torso motion; these targets make the grab, pin and
# punch geometrically readable from the victim's low camera angle.
ik_targets = {
    1:   ((48, -2, 81), (-48, -2, 81)),
    10:  ((48, -18, 86), (-48, -18, 86)),
    24:  ((34, -55, 90), (-34, -55, 90)),
    36:  ((28, -68, 80), (-28, -68, 80)),
    46:  ((25, -55, 68), (-25, -55, 68)),
    56:  ((27, -50, 47), (-27, -50, 47)),
    68:  ((24, -62, 27), (-24, -62, 27)),
    82:  ((20, -54, 23), (-30, -46, 38)),
    92:  ((18, -54, 22), (-56, 12, 112)),
    104: ((18, -54, 22), (-55, 27, 128)),
    114: ((18, -54, 22), (-58, 34, 138)),
    DEATH_FRAME: ((18, -54, 22), (-12, -69, 22)),
    134: ((20, -52, 24), (-10, -54, 32)),
    150: ((32, -30, 58), (-32, -30, 58)),
}
for frame, (left_target, right_target) in ik_targets.items():
    bpy.context.scene.frame_set(frame)
    for name, target in (("IK_LeftHand", left_target), ("IK_RightHand", right_target)):
        control = armature.pose.bones[name]
        control_matrix = control.matrix.copy()
        control_matrix.translation = Vector(target)
        control.matrix = control_matrix
        control.keyframe_insert("location", frame=frame, group=name)
        control.keyframe_insert("rotation_quaternion", frame=frame, group=name)

# Stable outward elbow planes stop the arms flipping through the chest as the
# hands pass from standing height to the floor.
for frame in ik_targets:
    bpy.context.scene.frame_set(frame)
    for name, target in (("POLE_LeftArm", (58, 12, 105)), ("POLE_RightArm", (-58, 12, 105))):
        pole = armature.pose.bones[name]
        pole_matrix = pole.matrix.copy()
        pole_matrix.translation = Vector(target)
        pole.matrix = pole_matrix
        pole.keyframe_insert("location", frame=frame, group=name)

for layer in action.layers:
    for strip in layer.strips:
        for bag in strip.channelbags:
            for curve in bag.fcurves:
                for point in curve.keyframe_points:
                    point.interpolation = "BEZIER"
                    point.easing = "AUTO"

scene = bpy.context.scene
scene.render.fps = FPS
scene.frame_start = 1
scene.frame_end = END_FRAME
scene.timeline_markers.clear()
for name, frame in (
    ("REACH", 24), ("FINGER_GRAB", 36), ("TAKEDOWN", 68),
    ("GROUND_PIN", 82), ("FIST", 104), ("PUNCH", DEATH_FRAME),
):
    scene.timeline_markers.new(name, frame=frame)

armature.animation_data.action = action
scene.frame_set(1)
bpy.context.view_layer.update()
bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)

result = {
    "action": ACTION_NAME,
    "frame_start": 1,
    "frame_end": END_FRAME,
    "death_frame": DEATH_FRAME,
    "duration": END_FRAME / FPS,
    "blend_file": bpy.data.filepath,
}
