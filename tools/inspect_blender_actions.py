"""Print a compact JSON inventory of rigs and animation actions in Blender.

Run with Blender, for example:
    blender --background file.blend --python tools/inspect_blender_actions.py
"""

from __future__ import annotations

import json
import re

import bpy


def slot_info(slot: object) -> dict[str, str]:
    return {
        "identifier": str(getattr(slot, "identifier", "")),
        "target_id_type": str(getattr(slot, "target_id_type", "")),
    }


def action_fcurves(action: object) -> list[object]:
    """Return legacy or layered-action FCurves without assuming a Blender version."""
    legacy = getattr(action, "fcurves", None)
    if legacy is not None:
        return list(legacy)
    curves: list[object] = []
    for layer in getattr(action, "layers", []):
        for strip in getattr(layer, "strips", []):
            for bag in getattr(strip, "channelbags", []):
                curves.extend(getattr(bag, "fcurves", []))
    return curves


inventory: dict[str, object] = {
    "blend_file": bpy.data.filepath,
    "scene": bpy.context.scene.name,
    "fps": bpy.context.scene.render.fps,
    "frame_start": bpy.context.scene.frame_start,
    "frame_end": bpy.context.scene.frame_end,
    "armatures": [],
    "actions": [],
}

for obj in bpy.data.objects:
    if obj.type != "ARMATURE":
        continue
    animation_data = obj.animation_data
    inventory["armatures"].append(
        {
            "name": obj.name,
            "bones": [bone.name for bone in obj.data.bones],
            "active_action": (
                animation_data.action.name
                if animation_data and animation_data.action
                else None
            ),
            "nla_tracks": [
                {
                    "name": track.name,
                    "strips": [
                        {
                            "name": strip.name,
                            "action": strip.action.name if strip.action else None,
                            "start": strip.frame_start,
                            "end": strip.frame_end,
                        }
                        for strip in track.strips
                    ],
                }
                for track in animation_data.nla_tracks
            ]
            if animation_data
            else [],
        }
    )

for action in bpy.data.actions:
    animated_bones = sorted(
        {
            match.group(1)
            for curve in action_fcurves(action)
            if (match := re.search(r'pose\.bones\["([^"]+)"\]', curve.data_path))
        }
    )
    inventory["actions"].append(
        {
            "name": action.name,
            "frame_range": [float(action.frame_range[0]), float(action.frame_range[1])],
            "users": action.users,
            "slots": [slot_info(slot) for slot in getattr(action, "slots", [])],
            "animated_bones": animated_bones,
        }
    )

print("MONGOTV_ANIMATION_INVENTORY=" + json.dumps(inventory, ensure_ascii=False))
