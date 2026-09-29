"""Check that the complete Blender scene and source kit are self-contained."""

import json
from pathlib import Path

import bpy


root = Path(__file__).resolve().parents[2]
out = root / "artifacts/level6-build-20260930/blend-verification.json"
scene = next(s for s in bpy.data.scenes if s.name.startswith("Level 6 | FULL"))
instances = [o for o in scene.objects if o.instance_type == "COLLECTION"]
kit = {c.name.removeprefix("L6K_") for c in bpy.data.collections if c.name.startswith("L6K_")}
kit_triangles = {
    c.name.removeprefix("L6K_"): sum(
        len(poly.vertices) - 2
        for obj in c.all_objects if obj.type == "MESH" and not obj.get("export_collision_only")
        for poly in obj.data.polygons
    )
    for c in bpy.data.collections if c.name.startswith("L6K_")
}
used = {o.get("Level6_KitAsset") for o in instances}
images = [i for i in bpy.data.images if i.source == "FILE" and i.name.startswith("WornParty")]
report = {
    "source": bpy.data.filepath,
    "fullScene": scene.name,
    "instances": len(instances),
    "instancedVisualTriangles": sum(kit_triangles[o.get("Level6_KitAsset")] for o in instances),
    "roomFloorInstances": sum(o.name.endswith(" | floor") for o in instances),
    "prefabCollections": len(kit),
    "usedPrefabs": len(used),
    "cdInstances": sum(o.get("Level6_KitAsset") == "CD" for o in instances),
    "cdPlayerInstances": sum(o.get("Level6_KitAsset") == "CDPlayer" for o in instances),
    "missingReferencedPrefabs": sorted(used - kit),
    "atlasImages": [
        {"name": i.name, "size": list(i.size), "packed": i.packed_file is not None,
         "path": i.filepath}
        for i in images
    ],
}
assert report["instances"] >= 3200, report
assert report["instancedVisualTriangles"] <= 1_500_000, report
assert report["prefabCollections"] == 49 and not report["missingReferencedPrefabs"], report
assert report["roomFloorInstances"] == 32, report
assert report["cdInstances"] == 5 and report["cdPlayerInstances"] == 1, report
assert any(i["packed"] for i in report["atlasImages"]), report
out.write_text(json.dumps(report, indent=2) + "\n")
print("LEVEL6_BLEND_VERIFIED", json.dumps(report), flush=True)
