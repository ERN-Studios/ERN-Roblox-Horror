"""Read-only native/interchange QA in an independent headless Blender process.

D:/Blender/blender.exe -b assets/level1/blender/Level1_ModularKit.blend --python-exit-code 1 -P tools/level1_blender/verify_native.py
Does not save the imported FBX scene or mutate the author's open scene.
"""
from pathlib import Path
import argparse, hashlib, json, sys
import bpy

ROOT = Path(__file__).resolve().parents[2] / "assets/level1/blender"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--assets", type=Path, default=ROOT)
ROOT = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []).assets.resolve()
assert bpy.app.background
data = json.loads((ROOT / "export/manifest.json").read_text())
texture_names = {filename for material in data["materials"].values() for filename in material["maps"].values()}
relative_textures = {}
for image in bpy.data.images:
    if image.name in texture_names:
        # Blender saves Windows-native separators after the relative // prefix.
        relative = image.filepath.replace("\\", "/")
        assert relative == "//textures/" + image.name, image.filepath
        assert (ROOT / "textures" / image.name).is_file(), image.name
        relative_textures[image.name] = relative
assert set(relative_textures) == texture_names
catalogue = bpy.data.collections["L1 Room Catalogue"]
assert len(catalogue.children) == len(data["rooms"])
expected = {}
for name in data["components"]:
    mesh = bpy.data.meshes["L1Asset_" + name]
    assert mesh.uv_layers.active and len(mesh.polygons) > 0, name
    expected[name] = sorted(m.name for m in mesh.materials)
for room in catalogue.children:
    assert room["OpenMask"] == data["rooms"][room.name]["mask"], room.name
    assert len(room.objects) == len(data["rooms"][room.name]["placements"])
    if data["version"] >= 2:
        assert room["SelectionWeight"] == data["rooms"][room.name]["selectionWeight"]
        if data["rooms"][room.name].get("shortWall"):
            assert room["ShortWall"] and room["ShortWallHeight"] == 8.5
# Remove only this verification process's loaded data, then test a fresh FBX import.
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=str(ROOT / "Level1_ModularKit.fbx"))
objects = [ob for ob in bpy.data.objects if ob.type == "MESH"]
assert len(objects) == len(expected)
for ob in objects:
    name = ob.name.split(".")[0]  # catalogue instances reserve Blender's unsuffixed object names
    assert name in expected and ob.data.uv_layers.active, ob.name
    assert sorted(m.name for m in ob.data.materials) == expected[name], ob.name
files = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in
         (ROOT / "Level1_ModularKit.blend", ROOT / "Level1_ModularKit.fbx")}
(ROOT / "native-files.json").write_text(json.dumps(files, indent=2), encoding="utf-8")
record = {"blenderVersion": bpy.app.version_string, "nativeRoomCollections": len(data["rooms"]),
          "fbxComponentMeshes": len(expected), "fbxUVMeshes": len(objects), "fbxMaterialsMatchNative": True,
          "nativeFiles": files, "relativeTextureReferences": relative_textures,
          "studioGameplayVerified": False}
(ROOT / "native-verification.json").write_text(json.dumps(record, indent=2), encoding="utf-8")
print("L1_NATIVE_QA=" + json.dumps(record))
