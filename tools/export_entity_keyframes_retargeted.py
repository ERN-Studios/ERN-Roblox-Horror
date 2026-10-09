"""Retarget open-Blender actions to the exact live Roblox Entity rest rig.

The old exporter applied one world-axis swap to every local bone delta.  FBX
import gives each Roblox Bone its own pre/post orientation, so that shortcut
reversed arm motion.  This exporter samples Blender global pose matrices through
localhost MCP, reads the actual Studio Bone CFrames, and solves the correct
per-bone basis mapping before producing KeyframeSequence JSON.
"""

from __future__ import annotations

import json
import math
from pathlib import Path
import statistics
import sys
import time

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))

from blender_mcp_client import execute as blender_execute  # noqa: E402
from sync_from_studio import StudioMcpClient, find_mcp_batch, select_studio  # noqa: E402


ROOT = Path(__file__).resolve().parents[1]
OUTPUT_DIR = ROOT / "assets" / "animations" / "entity" / "keyframes_v3"
FPS = 30.0

ACTIONS = {
    "Walk": "ENT_LOC_Walk_Fwd_Loop_IP_v003",
    "Run_Chase": "ENT_LOC_Chase_Fwd_Loop_IP_v003",
    "Watch": "ENT_IDLE_Watch_Loop_IP_v003",
    "Yell_Howl": "ENT_VOC_Howl_IP_v003",
    "Yell_FromRun": "ENT_VOC_Howl_FromChase_IP_v003",
    "Lunge": "ENT_ATK_Lunge_Fwd_IP_v003",
    "Lunge_FromRun": "ENT_ATK_Lunge_FromChase_IP_v003",
    "Kill_GroundPinPunch": "ENT_KILL_GroundPinPunch_IP_v002",
}
LOOPED = {"Walk", "Run_Chase", "Watch"}

PARENTS = {
    "Hips": None,
    "LeftUpLeg": "Hips", "LeftLeg": "LeftUpLeg",
    "LeftFoot": "LeftLeg", "LeftToeBase": "LeftFoot",
    "RightUpLeg": "Hips", "RightLeg": "RightUpLeg",
    "RightFoot": "RightLeg", "RightToeBase": "RightFoot",
    "Spine02": "Hips", "Spine01": "Spine02", "Spine": "Spine01",
    "LeftShoulder": "Spine", "LeftArm": "LeftShoulder",
    "LeftForeArm": "LeftArm", "LeftHand": "LeftForeArm",
    "RightShoulder": "Spine", "RightArm": "RightShoulder",
    "RightForeArm": "RightArm", "RightHand": "RightForeArm",
    "neck": "Spine", "Head": "neck",
}
# Finger chains are present on both the Blender source and the live Studio rig.
# Export them as real Bone tracks so the new grab and fist silhouettes survive
# the round-trip instead of being discarded at the wrist.
for side in ("Left", "Right"):
    hand = side + "Hand"
    PARENTS[side + "HandThumb1"] = hand
    PARENTS[side + "HandThumb2"] = side + "HandThumb1"
    for digit in ("Index", "Middle", "Ring", "Pinky"):
        first = side + "Hand" + digit + "1"
        PARENTS[first] = hand
        PARENTS[side + "Hand" + digit + "2"] = first
        PARENTS[side + "Hand" + digit + "3"] = side + "Hand" + digit + "2"
BONES = tuple(PARENTS)


def blender_sample_code() -> str:
    return f'''import bpy
arm = bpy.data.objects["Armature"]
if arm.animation_data is None:
    arm.animation_data_create()
for track in arm.animation_data.nla_tracks:
    track.mute = True
bones = {list(BONES)!r}
actions = {ACTIONS!r}
out = {{"rest": {{}}, "actions": {{}}}}
for name in bones:
    out["rest"][name] = [value for row in arm.data.bones[name].matrix_local for value in row]
for public_name, blender_name in actions.items():
    action = bpy.data.actions.get(blender_name)
    if action is None:
        raise RuntimeError("Missing Blender action: " + blender_name)
    arm.animation_data.action = action
    if getattr(action, "slots", None):
        try:
            arm.animation_data.action_slot = action.slots[0]
        except (AttributeError, TypeError):
            pass
    start, end = (round(value) for value in action.frame_range)
    sampled = []
    for frame in range(start, end + 1):
        bpy.context.scene.frame_set(frame)
        evaluated = arm.evaluated_get(bpy.context.evaluated_depsgraph_get())
        sampled.append({{
            name: [value for row in evaluated.pose.bones[name].matrix for value in row]
            for name in bones
        }})
    out["actions"][public_name] = {{"start": start, "end": end, "frames": sampled}}
result = out'''


def studio_rest() -> dict[str, list[float]]:
    client = StudioMcpClient(find_mcp_batch())
    try:
        client.initialize()
        time.sleep(3)
        select_studio(client, "BACKROOMS: STAY QUIET [CO-OP HORROR]", 20)
        encoded = client.call("execute_luau", {
            "datamodel_type": "Edit",
            "code": '''local H=game:GetService("HttpService")
local entity=workspace:FindFirstChild("Entity")
local out={}
if entity then
    for _,item in ipairs(entity:GetDescendants()) do
        if item:IsA("Bone") then out[item.Name]={item.CFrame:GetComponents()} end
    end
end
return H:JSONEncode(out)''',
        })
        return json.loads(encoded)
    finally:
        client.close()


def matrix(values: list[float]) -> np.ndarray:
    return np.array(values, dtype=float).reshape((4, 4))


def roblox_local(values: list[float]) -> np.ndarray:
    result = np.eye(4)
    result[:3, 3] = values[:3]
    result[:3, :3] = np.array(values[3:], dtype=float).reshape((3, 3))
    return result


def convert_blender(transform: np.ndarray, scale: float) -> np.ndarray:
    # The imported Studio bone bases include the FBX forward-axis reflection.
    # Empirical runtime sampling against the face markers shows that preserving
    # that reflection here maps a Blender -Y hand reach onto the Entity's actual
    # face direction. The opposite sign leaves the rest pose plausible but moves
    # both hands three studs behind HumanoidRootPart during the reach beat.
    axis = np.array(((1, 0, 0), (0, 0, 1), (0, -1, 0)), dtype=float)
    converted = np.eye(4)
    converted[:3, :3] = axis @ transform[:3, :3] @ axis.T
    converted[:3, 3] = axis @ transform[:3, 3] * scale
    return converted


def quaternion_xyzw(rotation: np.ndarray) -> tuple[float, float, float, float]:
    # Strip numerical scale/shear before converting the 3x3 matrix.
    u, _, vh = np.linalg.svd(rotation)
    rotation = u @ vh
    if np.linalg.det(rotation) < 0:
        u[:, -1] *= -1
        rotation = u @ vh
    trace = float(np.trace(rotation))
    if trace > 0:
        s = math.sqrt(trace + 1.0) * 2
        w = 0.25 * s
        x = (rotation[2, 1] - rotation[1, 2]) / s
        y = (rotation[0, 2] - rotation[2, 0]) / s
        z = (rotation[1, 0] - rotation[0, 1]) / s
    else:
        index = int(np.argmax(np.diag(rotation)))
        if index == 0:
            s = math.sqrt(1 + rotation[0, 0] - rotation[1, 1] - rotation[2, 2]) * 2
            x = 0.25 * s
            y = (rotation[0, 1] + rotation[1, 0]) / s
            z = (rotation[0, 2] + rotation[2, 0]) / s
            w = (rotation[2, 1] - rotation[1, 2]) / s
        elif index == 1:
            s = math.sqrt(1 + rotation[1, 1] - rotation[0, 0] - rotation[2, 2]) * 2
            x = (rotation[0, 1] + rotation[1, 0]) / s
            y = 0.25 * s
            z = (rotation[1, 2] + rotation[2, 1]) / s
            w = (rotation[0, 2] - rotation[2, 0]) / s
        else:
            s = math.sqrt(1 + rotation[2, 2] - rotation[0, 0] - rotation[1, 1]) * 2
            x = (rotation[0, 2] + rotation[2, 0]) / s
            y = (rotation[1, 2] + rotation[2, 1]) / s
            z = 0.25 * s
            w = (rotation[1, 0] - rotation[0, 1]) / s
    length = math.sqrt(x*x + y*y + z*z + w*w)
    return x/length, y/length, z/length, w/length


def slerp_xyzw(a: list[float], b: list[float], alpha: float) -> list[float]:
    """Shortest-path quaternion interpolation for a seamless loop tail."""
    av = np.array(a, dtype=float)
    bv = np.array(b, dtype=float)
    av /= np.linalg.norm(av)
    bv /= np.linalg.norm(bv)
    dot = float(np.dot(av, bv))
    if dot < 0:
        bv = -bv
        dot = -dot
    alpha = max(0.0, min(1.0, alpha))
    if dot > 0.9995:
        result = av + (bv - av) * alpha
        result /= np.linalg.norm(result)
        return result.tolist()
    theta = math.acos(max(-1.0, min(1.0, dot)))
    sine = math.sin(theta)
    result = (
        math.sin((1 - alpha) * theta) * av
        + math.sin(alpha * theta) * bv
    ) / sine
    return result.tolist()


def main() -> int:
    blender = blender_execute(blender_sample_code(), timeout=240)["result"]
    studio = studio_rest()
    missing = [name for name in BONES if name not in studio]
    if missing:
        raise RuntimeError(f"Studio Entity is missing bones: {missing}")

    blender_rest = {name: matrix(blender["rest"][name]) for name in BONES}
    studio_local = {name: roblox_local(studio[name]) for name in BONES}

    ratios = []
    for name, parent in PARENTS.items():
        if parent is None:
            continue
        blender_local = np.linalg.inv(blender_rest[parent]) @ blender_rest[name]
        source_length = float(np.linalg.norm(blender_local[:3, 3]))
        target_length = float(np.linalg.norm(studio_local[name][:3, 3]))
        if source_length > 1e-6 and target_length > 1e-6:
            ratios.append(target_length / source_length)
    scale = statistics.median(ratios)

    studio_global: dict[str, np.ndarray] = {}
    for name, parent in PARENTS.items():
        studio_global[name] = (
            studio_local[name]
            if parent is None
            else studio_global[parent] @ studio_local[name]
        )
    converted_rest = {
        name: convert_blender(blender_rest[name], scale) for name in BONES
    }
    # The Studio mesh was imported in the relaxed Watch pose, not in Blender's
    # armature edit-mode T-pose. Use that authored neutral frame as the motion
    # reference or every clip reapplies the T-pose-to-relaxed shoulder rotation
    # on top of an already-relaxed Studio rig (arms shoot sideways).
    watch_reference_frame = blender["actions"]["Watch"]["frames"][0]
    converted_reference = {
        name: convert_blender(matrix(watch_reference_frame[name]), scale)
        for name in BONES
    }
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    diagnostics: dict[str, object] = {"scale": scale, "actions": {}}
    for public_name, action_data in blender["actions"].items():
        output_frames = []
        max_rest_error = 0.0
        # Every action is authored in-place, but several Blender clips begin at
        # a different Hips offset. Normalize that hidden per-clip origin so a
        # crossfade cannot pop the whole rig by 0.3-1.25 studs.
        first_hips_pose = convert_blender(
            matrix(action_data["frames"][0]["Hips"]), scale)
        first_hips_mapped = np.eye(4)
        first_hips_world_delta = (
            first_hips_pose[:3, :3]
            @ converted_reference["Hips"][:3, :3].T
        )
        first_hips_mapped[:3, :3] = (
            first_hips_world_delta @ studio_global["Hips"][:3, :3]
        )
        first_hips_mapped[:3, 3] = (
            studio_global["Hips"][:3, 3]
            + first_hips_pose[:3, 3]
            - converted_reference["Hips"][:3, 3]
        )
        first_hips_delta = np.linalg.inv(studio_local["Hips"]) @ first_hips_mapped
        hips_origin = first_hips_delta[:3, 3].copy()
        for frame_index, frame in enumerate(action_data["frames"]):
            mapped_global = {}
            for name in BONES:
                converted_pose = convert_blender(matrix(frame[name]), scale)
                # Apply the source bone's GLOBAL animation delta to the matching
                # Studio rest bone. This remains a proper rotation even when FBX
                # rest bases differ in handedness; multiplying a pose directly by
                # an improper rest-basis correction was what produced 90° T-pose
                # arms in v4.
                mapped = np.eye(4)
                world_delta = (
                    converted_pose[:3, :3]
                    @ converted_reference[name][:3, :3].T
                )
                mapped[:3, :3] = world_delta @ studio_global[name][:3, :3]
                mapped[:3, 3] = (
                    studio_global[name][:3, 3]
                    + converted_pose[:3, 3]
                    - converted_reference[name][:3, 3]
                )
                mapped_global[name] = mapped
            transforms = []
            for name, parent in PARENTS.items():
                posed_local = (
                    mapped_global[name]
                    if parent is None
                    else np.linalg.inv(mapped_global[parent]) @ mapped_global[name]
                )
                delta = np.linalg.inv(studio_local[name]) @ posed_local
                location = delta[:3, 3]
                # The source actions key location only on Hips.  Small imported
                # rest-length differences on child bones must not become fake
                # joint translations in Roblox.
                if name != "Hips":
                    location = np.zeros(3)
                else:
                    location = location - hips_origin
                    magnitude = float(np.linalg.norm(location))
                    if magnitude > 1.25:
                        location = location * (1.25 / magnitude)
                x, y, z, w = quaternion_xyzw(delta[:3, :3])
                transforms.append([
                    name,
                    round(float(location[0]), 6),
                    round(float(location[1]), 6),
                    round(float(location[2]), 6),
                    round(x, 7), round(y, 7), round(z, 7), round(w, 7),
                ])
                if frame_index == 0:
                    max_rest_error = max(max_rest_error, float(np.linalg.norm(location)))
            output_frames.append([round(frame_index / FPS, 6), transforms])

        # Blender's locomotion ranges stop one sample before an exact duplicate
        # of frame 1. Ease the final five samples back into frame 1 so Roblox's
        # loop boundary has no knee/hip snap.
        if public_name in LOOPED and len(output_frames) >= 7:
            first = {values[0]: values for values in output_frames[0][1]}
            tail_start = len(output_frames) - 5
            for index in range(tail_start, len(output_frames)):
                alpha = (index - tail_start + 1) / 5
                for values in output_frames[index][1]:
                    target = first[values[0]]
                    for component in range(1, 4):
                        values[component] = round(
                            values[component]
                            + (target[component] - values[component]) * alpha, 6)
                    values[4:8] = [round(value, 7) for value in slerp_xyzw(
                        values[4:8], target[4:8], alpha)]
        payload = {
            "name": public_name,
            "looped": public_name in LOOPED,
            "priority": (
                "Idle" if public_name == "Watch"
                else "Movement" if public_name in LOOPED
                else "Action4"
            ),
            "retarget": "global-pose-delta-v10-normalized-origin-loop-closure",
            "frames": output_frames,
        }
        filename = public_name.lower() + ".json"
        (OUTPUT_DIR / filename).write_text(
            json.dumps(payload, separators=(",", ":")), encoding="utf-8"
        )
        diagnostics["actions"][public_name] = {
            "frames": len(output_frames), "first_frame_translation_max": max_rest_error,
            "removed_hips_origin": [round(float(value), 6) for value in hips_origin],
        }
        print(f"RETARGETED {public_name}: {len(output_frames)} frames -> {filename}")

    (OUTPUT_DIR / "retarget-diagnostics.json").write_text(
        json.dumps(diagnostics, indent=2) + "\n", encoding="utf-8"
    )
    print(f"STUDIO_RIG_SCALE={scale:.9f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
