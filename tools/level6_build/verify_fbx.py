"""Round-trip the standalone Roblox import kit through Blender's FBX importer."""

import json
from pathlib import Path

import bpy


root = Path(__file__).resolve().parents[2]
fbx = root / "assets/level6-worn-party/Level6_ReusableKit.fbx"
manifest = json.loads((root / "assets/level6-worn-party/exports-v2/manifest.json").read_text())
expected = {item["name"] for item in manifest["chunks"]}
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=str(fbx))
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
names = {o.name.removeprefix("L6K_") for o in meshes}
report = {
    "fbx": str(fbx),
    "meshObjects": len(meshes),
    "uniqueNames": len(names),
    "expectedPrefabs": len(expected),
    "missingPrefabs": sorted(expected - names),
    "extraMeshes": sorted(names - expected),
    "triangles": sum(len(p.vertices) - 2 for o in meshes for p in o.data.polygons),
    "uvMappedMeshes": sum(bool(o.data.uv_layers) for o in meshes),
    "materials": sorted({m.name for o in meshes for m in o.data.materials if m}),
}
assert report["meshObjects"] == len(expected), report
assert not report["missingPrefabs"] and not report["extraMeshes"], report
assert report["uvMappedMeshes"] == len(expected), report
target = root / "artifacts/level6-build-20260930/fbx-roundtrip.json"
target.write_text(json.dumps(report, indent=2) + "\n")
print("LEVEL6_FBX_ROUNDTRIP", json.dumps(report), flush=True)
