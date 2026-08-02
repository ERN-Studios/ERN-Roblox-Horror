"""Export each gameplay action from the current Blender file as a Roblox FBX."""

from __future__ import annotations

from pathlib import Path
import re

import bpy


ACTION_NAMES = (
    "Walk",
    "Run_Chase",
    "Watch",
    "Yell_Howl",
    "Yell_FromRun",
    "Lunge",
    "Lunge_FromRun",
)
OUTPUT_DIR = Path(r"G:\Roblox\MongoTV\assets\animations\entity")


def safe_name(name: str) -> str:
    return re.sub(r"[^A-Za-z0-9_-]+", "_", name).strip("_").lower()


armatures = [obj for obj in bpy.data.objects if obj.type == "ARMATURE"]
if len(armatures) != 1:
    raise RuntimeError(f"Expected one armature, found {[obj.name for obj in armatures]}")
armature = armatures[0]
if not armature.animation_data:
    armature.animation_data_create()

export_objects = [armature]
export_objects.extend(
    obj
    for obj in bpy.data.objects
    if obj.type == "MESH" and obj.find_armature() == armature
)
if len(export_objects) == 1:
    raise RuntimeError("No mesh bound to the armature was found")

OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

for obj in bpy.context.scene.objects:
    obj.select_set(False)
for obj in export_objects:
    obj.hide_set(False)
    obj.select_set(True)
bpy.context.view_layer.objects.active = armature

for track in armature.animation_data.nla_tracks:
    track.mute = True

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
    bpy.context.scene.frame_start = start
    bpy.context.scene.frame_end = end
    bpy.context.scene.frame_set(start)

    destination = OUTPUT_DIR / f"entity_{safe_name(action_name)}_v1.fbx"
    bpy.ops.export_scene.fbx(
        filepath=str(destination),
        use_selection=True,
        object_types={"ARMATURE", "MESH"},
        use_mesh_modifiers=True,
        add_leaf_bones=False,
        use_armature_deform_only=False,
        apply_scale_options="FBX_SCALE_UNITS",
        axis_forward="-Z",
        axis_up="Y",
        bake_anim=True,
        bake_anim_use_all_bones=True,
        bake_anim_use_nla_strips=False,
        bake_anim_use_all_actions=False,
        bake_anim_force_startend_keying=True,
        bake_anim_step=1.0,
        bake_anim_simplify_factor=0.0,
        path_mode="AUTO",
        embed_textures=False,
    )
    print(f"MONGOTV_EXPORTED={action_name}|{start}|{end}|{destination}")
