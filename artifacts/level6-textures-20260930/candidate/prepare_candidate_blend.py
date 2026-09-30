"""Run in Blender to copy the authored project with a packed candidate atlas.

Usage: Blender --background --python prepare_candidate_blend.py -- [--render]
The source .blend is loaded but never saved back to its original path.
"""
import bpy
import hashlib
import json
import struct
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SOURCE = ROOT / "assets/level6-worn-party/Level6_WornParty_v2.blend"
ATLAS = HERE / "textures/WornParty_Level3Reference_Atlas.png"
OUTPUT = HERE / "Level6_WornParty_Level3Reference_candidate.blend"


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def geometry_fingerprint():
    result = []
    for obj in sorted(bpy.data.objects, key=lambda o: o.name):
        if obj.type != "MESH":
            continue
        result.append({"name": obj.name, "vertices": len(obj.data.vertices),
                       "polygons": len(obj.data.polygons), "loops": len(obj.data.loops),
                       "vertexHash": hashlib.sha256(b"".join(struct.pack("<3f", *vertex.co) for vertex in obj.data.vertices)).hexdigest(),
                       "polygonHash": hashlib.sha256(b"".join(struct.pack("<" + "I" * len(face.vertices), *face.vertices) for face in obj.data.polygons)).hexdigest(),
                       "worldMatrix": [list(row) for row in obj.matrix_world],
                       "materials": [material.name if material else None for material in obj.data.materials],
                       "uvHash": hashlib.sha256(b"".join(
                           str(tuple(item.uv)).encode() for layer in obj.data.uv_layers for item in layer.data
                       )).hexdigest()})
    return hashlib.sha256(json.dumps(result, sort_keys=True).encode()).hexdigest()


def render_study(scene, prefix):
    bpy.context.window.scene = scene
    scene.render.resolution_x = 960
    scene.render.resolution_y = 640
    scene.render.resolution_percentage = 100
    scene.cycles.samples = 24
    scene.cycles.use_denoising = True
    scene.render.filepath = str(HERE / "previews" / (prefix + ".png"))
    bpy.ops.render.render(write_still=True)


source_sha = sha256(SOURCE)
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
geometry_before = geometry_fingerprint()
object_count_before, material_count_before = len(bpy.data.objects), len(bpy.data.materials)
studies = [bpy.data.scenes["Study 01 | Beige Party Hall"],
           bpy.data.scenes["Study 02 | Orange Birthday Rooms"],
           bpy.data.scenes["Study 03 | Red Party Maze"]]
do_render = "--render" in sys.argv or "--render-after-only" in sys.argv
if do_render and "--render-after-only" not in sys.argv:
    (HERE / "previews").mkdir(exist_ok=True)
    for index, scene in enumerate(studies, start=1):
        render_study(scene, f"{index:02d}-before")

old_atlases = [image for image in bpy.data.images if image.name.startswith("WornParty_Atlas")]
assert len(old_atlases) == 1
new_atlas = bpy.data.images.load(str(ATLAS), check_existing=False)
new_atlas.name = "WornParty_Level3Reference_Atlas.png"
new_atlas.pack()
replaced_nodes = 0
for material in bpy.data.materials:
    if not material.use_nodes:
        continue
    for node in material.node_tree.nodes:
        if node.type == "TEX_IMAGE" and node.image in old_atlases:
            node.image = new_atlas
            replaced_nodes += 1
assert replaced_nodes > 0
floor_routes = [
    ("Study 04 | Budget Arcade", "Floor.003", "L6K_FloorOrange", "L6K_FloorBeige"),
    ("Study 05 | Party Supply Store", "Floor.004", "L6K_FloorService", "L6K_FloorOrange"),
]
floor_route_changes = []
for scene_name, object_name, before_collection, after_collection in floor_routes:
    obj = bpy.data.scenes[scene_name].objects[object_name]
    assert obj.instance_collection.name == before_collection
    obj.instance_collection = bpy.data.collections[after_collection]
    floor_route_changes.append({"scene": scene_name, "object": object_name,
                                "beforeCollection": before_collection, "afterCollection": after_collection})
assert bpy.data.scenes["Study 06 | Maintenance Workshop"].objects["Floor.005"].instance_collection.name == "L6K_FloorService"
geometry_after = geometry_fingerprint()
assert geometry_before == geometry_after
assert (len(bpy.data.objects), len(bpy.data.materials)) == (object_count_before, material_count_before)
assert sha256(SOURCE) == source_sha
bpy.context.window.scene = studies[0]
bpy.context.scene["candidate_status"] = "OFFLINE ONLY — NOT INSTALLED IN STUDIO"
bpy.context.scene["candidate_reference"] = "Verified historical Level3 original texture source pack. Current Studio parity pending."
bpy.context.scene["candidate_uv_limitation"] = "Original mesh UVs preserved. Native fixed-repeat floor routing must be handled independently."
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT))
assert sha256(SOURCE) == source_sha

if do_render:
    (HERE / "previews").mkdir(exist_ok=True)
    for index, scene in enumerate(studies, start=1):
        render_study(scene, f"{index:02d}-candidate")

manifest = {"schema": "level6-offline-blender-candidate-v1", "installedInStudio": False,
            "sourceBlend": str(SOURCE.relative_to(ROOT)), "sourceBlendSha256": source_sha,
            "candidateBlend": str(OUTPUT.relative_to(ROOT)), "candidateBlendSha256": sha256(OUTPUT),
            "atlasSha256": sha256(ATLAS), "atlasPacked": bool(new_atlas.packed_file),
            "materialImageNodesChanged": replaced_nodes, "meshUVGeometryFingerprint": geometry_after,
            "objectCount": len(bpy.data.objects), "materialCount": len(bpy.data.materials),
            "objectMaterialCountsUnchanged": True,
            "authoredStudyFloorRoutingChanges": floor_route_changes,
            "maintenanceStudyFloorServiceUnchanged": True,
            "meshUVGeometryUnchanged": geometry_before == geometry_after,
            "sourceBlendUnchanged": sha256(SOURCE) == source_sha,
            "renderedStudies": [scene.name for scene in studies] if do_render or all((HERE / "previews" / f"{index:02d}-candidate.png").exists() for index in range(1, 4)) else [],
            "renderedInThisRun": do_render,
            "blenderVersion": bpy.app.version_string,
            "limitations": ["Not a live Studio export.", "No mesh reimport or runtime route changes.",
                            "Original mesh face repeat remains different from native Level3 studs-per-tile.",
                            "Blender lighting studies do not prove Roblox rendering or gameplay performance."]}
(HERE / "blend-candidate-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
print("L6_OFFLINE_CANDIDATE_COMPLETE", json.dumps(manifest))
