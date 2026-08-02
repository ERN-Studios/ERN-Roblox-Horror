"""Bake Blender actions into compact Roblox KeyframeSequence source data."""

from __future__ import annotations

import json
from pathlib import Path
import re

import bpy
from mathutils import Matrix


ACTION_NAMES = (
    "Walk",
    "Run_Chase",
    "Watch",
    "Yell_Howl",
    "Yell_FromRun",
    "Lunge",
    "Lunge_FromRun",
)
LOOPED = {"Walk", "Run_Chase", "Watch"}
ROBLOX_BONES = (
    "Hips",
    "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase",
    "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase",
    "Spine02", "Spine01", "Spine",
    "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
    "RightShoulder", "RightArm", "RightForeArm", "RightHand",
    "neck", "Head",
)
OUTPUT_DIR = Path(r"G:\Roblox\MongoTV\assets\animations\entity\keyframes")


def safe_name(name: str) -> str:
    return re.sub(r"[^A-Za-z0-9_-]+", "_", name).strip("_").lower()


armatures = [obj for obj in bpy.data.objects if obj.type == "ARMATURE"]
if len(armatures) != 1:
    raise RuntimeError(f"Expected one armature, found {[obj.name for obj in armatures]}")
armature = armatures[0]
if not armature.animation_data:
    armature.animation_data_create()

missing = [name for name in ROBLOX_BONES if name not in armature.pose.bones]
if missing:
    raise RuntimeError(f"Roblox bones missing in Blender: {missing}")

for track in armature.animation_data.nla_tracks:
    track.mute = True

# Blender (X right, Y forward, Z up) -> Roblox (X right, Y up, -Z forward).
axis = Matrix(((1, 0, 0, 0), (0, 0, 1, 0), (0, -1, 0, 0), (0, 0, 0, 1)))
axis_inv = axis.inverted()
fps = bpy.context.scene.render.fps / bpy.context.scene.render.fps_base
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

for action_name in ACTION_NAMES:
    action = bpy.data.actions.get(action_name)
    if not action:
        raise RuntimeError(f"Missing action: {action_name}")
    armature.animation_data.action = action
    if getattr(action, "slots", None):
        try:
            armature.animation_data.action_slot = action.slots[0]
        except (AttributeError, TypeError):
            pass

    start, end = (round(value) for value in action.frame_range)
    frames: list[list[object]] = []
    for frame in range(start, end + 1):
        bpy.context.scene.frame_set(frame)
        depsgraph = bpy.context.evaluated_depsgraph_get()
        evaluated = armature.evaluated_get(depsgraph)
        transforms: list[list[float | str]] = []
        for bone_name in ROBLOX_BONES:
            pose_bone = evaluated.pose.bones[bone_name]
            rest_bone = armature.data.bones[bone_name]
            if rest_bone.parent:
                parent_pose = evaluated.pose.bones[rest_bone.parent.name].matrix
                parent_rest = rest_bone.parent.matrix_local
                pose_local = parent_pose.inverted_safe() @ pose_bone.matrix
                rest_local = parent_rest.inverted_safe() @ rest_bone.matrix_local
            else:
                pose_local = pose_bone.matrix
                rest_local = rest_bone.matrix_local
            delta = rest_local.inverted_safe() @ pose_local
            converted = axis @ delta @ axis_inv
            location, rotation, _scale = converted.decompose()
            transforms.append(
                [
                    bone_name,
                    round(location.x, 6), round(location.y, 6), round(location.z, 6),
                    round(rotation.x, 7), round(rotation.y, 7),
                    round(rotation.z, 7), round(rotation.w, 7),
                ]
            )
        frames.append([round((frame - start) / fps, 6), transforms])

    payload = {
        "name": action_name,
        "looped": action_name in LOOPED,
        "priority": (
            "Idle" if action_name == "Watch"
            else "Movement" if action_name in LOOPED
            else "Action4"
        ),
        "frames": frames,
    }
    destination = OUTPUT_DIR / f"{safe_name(action_name)}.json"
    destination.write_text(
        json.dumps(payload, separators=(",", ":")), encoding="utf-8"
    )
    print(f"MONGOTV_KEYFRAMES={action_name}|{len(frames)}|{destination}")
