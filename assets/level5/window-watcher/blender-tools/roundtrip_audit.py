"""Fresh imports compare exported skeleton, influences, clip count and sampled motion.

Run after exports: blender ... --python roundtrip_audit.py -- export-directory
This never modifies the exported files. The report describes failures rather than hiding
them behind a successful file export. Visual inspection and Studio import remain separate.
"""
import json
import math
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
import bpy
from watcher_common import CLIPS, FPS, activate_action, get_rig, import_asset, inventory, reset_pose, write_json


def rig_state(rig):
    return {p.name: [float(v) for v in (rig.matrix_world @ p.matrix).translation]
            for p in rig.pose.bones}


def hierarchy(rig):
    return {b.name: b.parent.name if b.parent else None for b in rig.data.bones}


def motion_samples(rig, action, fractions=(0, .2, .4, .6, .8, 1)):
    activate_action(rig, action)
    start, end = action.frame_range
    result = []
    for fraction in fractions:
        f = float(start + (end - start) * fraction)
        bpy.context.scene.frame_set(math.floor(f), subframe=f - math.floor(f))
        bpy.context.view_layer.update()
        result.append(rig_state(rig))
    return result


def distance(a, b):
    return math.sqrt(sum((x - y) ** 2 for x, y in zip(a, b)))


def max_sample_delta(a, b):
    return max((distance(sa[n], sb[n]) for sa, sb in zip(a, b)
                for n in sa.keys() & sb.keys()), default=0)


args = sys.argv[sys.argv.index("--") + 1:]
if len(args) != 1:
    raise SystemExit("Expected directory containing model.blend and exported files")
output = Path(args[0]).resolve()
import_asset(output / "model.blend")
rig = get_rig()
contract = hierarchy(rig)
source_inventory = inventory()
source_samples = {name: motion_samples(rig, bpy.data.actions[name]) for name in CLIPS}
activate_action(rig, None)
reset_pose(rig)
rest = rig_state(rig)
height = max((m["dimensions"][2] for m in source_inventory["meshes"]), default=1)
tolerance = max(height * 0.002, 1e-5)
report = {"reference": str(output / "model.blend"), "fps": FPS,
          "world_position_tolerance": tolerance, "files": [], "issues": []}
for filename in ["model.glb", "model.fbx", *[name + ".fbx" for name in CLIPS]]:
    source = import_asset(output / filename)
    rig = get_rig()
    current = inventory()
    row = {"file": filename, "bytes": source.stat().st_size,
           "hierarchy_equal": hierarchy(rig) == contract,
           "inventory": current, "issues": list(current["issues"])}
    if not row["hierarchy_equal"]:
        row["issues"].append("Exported bone hierarchy differs from source")
    is_clip = source.stem in CLIPS
    actions = list(bpy.data.actions)
    if len(actions) != (1 if is_clip else 0):
        row["issues"].append(f"Unexpected animation count: {len(actions)}")
    if is_clip and len(actions) == 1:
        samples = motion_samples(rig, actions[0])
        row["duration_seconds"] = (actions[0].frame_range[1] - actions[0].frame_range[0]) / FPS
        row["max_bone_head_delta_from_authored"] = max_sample_delta(source_samples[source.stem], samples)
        row["max_bone_motion"] = max_sample_delta([samples[0]] * len(samples), samples)
        row["first_last_bone_head_delta"] = max_sample_delta([samples[0]], [samples[-1]])
        if row["max_bone_head_delta_from_authored"] > tolerance:
            row["issues"].append("Sampled motion deviates from authored clip")
        if row["max_bone_motion"] <= 1e-5:
            row["issues"].append("Clip has no detectable bone-head movement")
    else:
        activate_action(rig, None)
        reset_pose(rig)
        row["max_rest_bone_head_delta"] = max_sample_delta([rest], [rig_state(rig)])
        if row["max_rest_bone_head_delta"] > tolerance:
            row["issues"].append("Imported rest pose world scale/orientation differs")
    report["files"].append(row)
    report["issues"].extend(f"{filename}: {issue}" for issue in row["issues"])
report["pass"] = not report["issues"]
write_json(output / "roundtrip-audit.json", report)
print("WATCHER_ROUNDTRIP=" + json.dumps({"pass": report["pass"], "issues": report["issues"]}))
if not report["pass"]:
    raise SystemExit(2)
