"""Shared Blender utilities; operate on the real imported asset, never synthesize a rig."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

import bpy


CLIPS = {"WatchingIdle": (1, 181), "SlowWindowLean": (1, 151), "GlassTap": (1, 121)}
FPS = 30


def write_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")


def import_asset(path):
    """Isolated factory scene. Source files and user preferences are untouched."""
    path = Path(path).resolve()
    if not path.is_file():
        raise FileNotFoundError(path)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if path.suffix.lower() == ".blend":
        bpy.ops.wm.open_mainfile(filepath=str(path), load_ui=False)
    elif path.suffix.lower() in {".glb", ".gltf"}:
        bpy.ops.import_scene.gltf(filepath=str(path))
    elif path.suffix.lower() == ".fbx":
        bpy.context.scene.render.fps = FPS
        bpy.ops.import_scene.fbx(filepath=str(path), use_anim=True)
    else:
        raise ValueError(f"Unsupported model source: {path}")
    return path


def get_rig():
    rigs = [obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"]
    if len(rigs) != 1:
        raise RuntimeError(f"Expected one real armature, found {[obj.name for obj in rigs]}")
    return rigs[0]


def bound_meshes(rig):
    return [obj for obj in bpy.context.scene.objects
            if obj.type == "MESH" and obj.find_armature() == rig]


def action_fcurves(action):
    legacy = getattr(action, "fcurves", None)
    if legacy is not None:
        return list(legacy)
    return [curve for layer in getattr(action, "layers", [])
            for strip in getattr(layer, "strips", [])
            for bag in getattr(strip, "channelbags", [])
            for curve in bag.fcurves]


def activate_action(rig, action):
    rig.animation_data_create()
    rig.animation_data.action = action
    if action and getattr(action, "slots", None):
        object_slots = [s for s in action.slots if s.target_id_type == "OBJECT"]
        if len(object_slots) == 1:
            rig.animation_data.action_slot = object_slots[0]
        elif len(object_slots) > 1:
            raise RuntimeError(f"Ambiguous action slots: {action.name}")
    for track in rig.animation_data.nla_tracks:
        track.mute = True


def reset_pose(rig):
    for bone in rig.pose.bones:
        bone.location = (0, 0, 0)
        bone.rotation_mode = "QUATERNION"
        bone.rotation_quaternion = (1, 0, 0, 0)
        bone.scale = (1, 1, 1)
    bpy.context.view_layer.update()


def select_export_objects(rig):
    bpy.ops.object.select_all(action="DESELECT")
    objects = [rig, *bound_meshes(rig)]
    if len(objects) < 2:
        raise RuntimeError("No mesh is bound to the imported armature")
    for obj in objects:
        obj.hide_set(False)
        obj.select_set(True)
    bpy.context.view_layer.objects.active = rig
    return objects


def rounded_matrix(matrix):
    return [[round(float(v), 7) for v in row] for row in matrix]


def inventory():
    """Inspect actual geometry, bone tree, weights, materials and action payload."""
    report = {"blender_version": bpy.app.version_string, "blend_file": bpy.data.filepath,
              "fps": bpy.context.scene.render.fps, "armatures": [], "meshes": [],
              "actions": [], "issues": [], "warnings": []}
    roots = set()
    for rig in [o for o in bpy.context.scene.objects if o.type == "ARMATURE"]:
        bones = [{"name": b.name, "parent": b.parent.name if b.parent else None,
                  "deform": b.use_deform, "head": list(b.head_local), "tail": list(b.tail_local),
                  "rest_matrix": rounded_matrix(b.matrix_local)} for b in rig.data.bones]
        roots.update(b["name"] for b in bones if b["parent"] is None)
        report["armatures"].append({"name": rig.name, "bones": bones,
            "matrix_world": rounded_matrix(rig.matrix_world),
            "bone_contract_sha256": hashlib.sha256(json.dumps(bones, sort_keys=True).encode()).hexdigest()})
    for obj in [o for o in bpy.context.scene.objects if o.type == "MESH"]:
        obj.data.calc_loop_triangles()
        rig = obj.find_armature()
        deform_names = {b.name for b in rig.data.bones if b.use_deform} if rig else set()
        groups = {g.index: g.name for g in obj.vertex_groups}
        histogram = {}
        weight_sums = []
        unweighted, too_many, root_weighted = [], [], []
        for vertex in obj.data.vertices:
            influences = [(groups.get(g.group), g.weight) for g in vertex.groups
                          if groups.get(g.group) in deform_names and g.weight > 1e-6]
            count = len(influences)
            histogram[str(count)] = histogram.get(str(count), 0) + 1
            if count == 0:
                unweighted.append(vertex.index)
            if count > 4:
                too_many.append(vertex.index)
            if any(name in roots for name, _ in influences):
                root_weighted.append(vertex.index)
            weight_sums.append(sum(w for _, w in influences))
        row = {"name": obj.name, "armature": rig.name if rig else None,
               "vertices": len(obj.data.vertices), "faces": len(obj.data.polygons),
               "triangles": len(obj.data.loop_triangles), "dimensions": list(obj.dimensions),
               "matrix_world": rounded_matrix(obj.matrix_world),
               "uv_layers": [uv.name for uv in obj.data.uv_layers],
               "materials": [m.name if m else None for m in obj.data.materials],
               "influence_histogram": histogram, "unweighted_count": len(unweighted),
               "more_than_four_count": len(too_many), "root_weighted_count": len(root_weighted),
               "weight_sum_min": min(weight_sums, default=0), "weight_sum_max": max(weight_sums, default=0),
               "non_normalized_count": sum(abs(s - 1) > 1e-4 for s in weight_sums),
               "problem_samples": {"unweighted": unweighted[:20], "more_than_four": too_many[:20],
                                   "root_weighted": root_weighted[:20]}}
        report["meshes"].append(row)
        if row["triangles"] > 20000:
            report["issues"].append(f"{obj.name}: exceeds 20,000 triangles")
        if rig and (unweighted or too_many):
            report["issues"].append(f"{obj.name}: invalid bone influence counts")
        if rig and root_weighted:
            report["warnings"].append(f"{obj.name}: root weights require Roblox import review")
        if rig and row["non_normalized_count"]:
            report["warnings"].append(f"{obj.name}: non-normalized deform weights")
    for action in bpy.data.actions:
        curves = action_fcurves(action)
        report["actions"].append({"name": action.name, "frame_range": list(action.frame_range),
            "fcurves": len(curves), "keyframes": sum(len(c.keyframe_points) for c in curves),
            "paths": sorted(set(c.data_path for c in curves)),
            "slots": [s.identifier for s in getattr(action, "slots", [])]})
    report["images"] = [{"name": image.name, "size": list(image.size),
                         "packed": bool(image.packed_file), "filepath": image.filepath}
                        for image in bpy.data.images if image.type == "IMAGE"]
    return report


def export_fbx(path, rig, animated):
    select_export_objects(rig)
    bpy.ops.export_scene.fbx(filepath=str(path), use_selection=True,
        object_types={"ARMATURE", "MESH"}, use_mesh_modifiers=True,
        add_leaf_bones=False, use_armature_deform_only=False,
        apply_scale_options="FBX_SCALE_UNITS", axis_forward="Z", axis_up="Y",
        bake_anim=animated, bake_anim_use_all_bones=True,
        bake_anim_use_nla_strips=False, bake_anim_use_all_actions=False,
        bake_anim_force_startend_keying=True, bake_anim_step=1.0,
        bake_anim_simplify_factor=0.0, path_mode="COPY", embed_textures=True)


def export_model_and_clips(output, rig, export_model=True):
    """Keep all named clips in blend, but exactly one clip per animated FBX."""
    output = Path(output).resolve()
    output.mkdir(parents=True, exist_ok=True)
    bpy.context.scene.render.fps = FPS
    missing = set(CLIPS) - {a.name for a in bpy.data.actions}
    if missing:
        raise RuntimeError(f"Missing authored clips: {sorted(missing)}")
    for name in CLIPS:
        bpy.data.actions[name].use_fake_user = True
    activate_action(rig, None)
    reset_pose(rig)
    select_export_objects(rig)
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=str(output / "model.blend"))
    if export_model:
        export_fbx(output / "model.fbx", rig, False)
        bpy.ops.export_scene.gltf(filepath=str(output / "model.glb"), export_format="GLB",
            use_selection=True, export_animations=False, export_skins=True,
            export_influence_nb=4, export_all_influences=False)
    for name, (start, end) in CLIPS.items():
        activate_action(rig, bpy.data.actions[name])
        bpy.context.scene.frame_start, bpy.context.scene.frame_end = start, end
        bpy.context.scene.frame_set(start)
        export_fbx(output / f"{name}.fbx", rig, True)
    activate_action(rig, bpy.data.actions["WatchingIdle"])
    bpy.context.scene.frame_start, bpy.context.scene.frame_end = CLIPS["WatchingIdle"]
    bpy.context.scene.frame_set(1)
    bpy.ops.wm.save_as_mainfile(filepath=str(output / "model.blend"))
    write_json(output / "export-inventory.json", inventory())
