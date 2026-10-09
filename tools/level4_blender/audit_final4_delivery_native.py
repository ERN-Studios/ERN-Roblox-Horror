"""Read-only texture/UV audit of the copied final4 native scenes in headless Blender.

D:/Blender/blender.exe -b --factory-startup --python-exit-code 1 -P tools/level4_blender/audit_final4_delivery_native.py
Does not save or change either native scene or the user's open Blender session.
"""
from pathlib import Path
import hashlib, json
import bpy

ROOT = Path(__file__).resolve().parents[2] / "assets/level4/cinema-final4"
SOURCE = Path("G:/Roblox/_local/l4facelift/v5")
assert bpy.app.background
records = []
bundled_images = {path: hashlib.sha256(path.read_bytes()).hexdigest()
                  for folder in (ROOT / "world/textures", ROOT / "templates/export/textures")
                  for path in folder.iterdir() if path.is_file()}
for file in (ROOT / "world/Cinema_Final4.blend", ROOT / "templates/Cinema_Templates.blend"):
    before = hashlib.sha256(file.read_bytes()).hexdigest()
    bpy.ops.wm.open_mainfile(filepath=str(file))
    meshes = [mesh for mesh in bpy.data.meshes if len(mesh.polygons)]
    images = []
    for image in bpy.data.images:
        if image.source != "FILE":
            continue
        packed = bool(image.packed_file or image.packed_files)
        basename = Path(image.filepath.replace("\\", "/")).name
        bundled = [p.relative_to(ROOT).as_posix() for p in
                   (ROOT / "world/textures" / basename, ROOT / "templates/export/textures" / basename) if p.is_file()]
        # Renamed exported atlases are byte-identical to these eight original
        # Meshy image files; keep one copy and record exact bindings by hash.
        original_scene = SOURCE / ("final4/final.blend" if file.parent.name == "world"
                                    else "assets/templates/templates.blend")
        raw = image.filepath.replace("\\", "/")
        original_image = (original_scene.parent / raw[2:]).resolve() if raw.startswith("//") else Path(raw)
        original_sha = None
        if not packed and original_image.is_file():
            assert original_image.is_relative_to(Path("G:/Blender/Level4_Cinema/textures")) or \
                   original_image.is_relative_to(Path("G:/Roblox/_local/l4meshy")), original_image
            original_sha = hashlib.sha256(original_image.read_bytes()).hexdigest()
            if not bundled:
                bundled = [p.relative_to(ROOT).as_posix() for p, digest in bundled_images.items() if digest == original_sha]
        assert packed or bundled, "Native texture not bundled: " + image.name
        images.append({"name": image.name, "originalPath": image.filepath, "packed": packed,
                       "originalFileSha256": original_sha, "bundledMatches": bundled, "size": list(image.size)})
    assert hashlib.sha256(file.read_bytes()).hexdigest() == before
    records.append({"file": file.relative_to(ROOT).as_posix(), "sha256": before,
                    "meshes": len(meshes), "uvMeshes": sum(mesh.uv_layers.active is not None for mesh in meshes),
                    "images": images, "unpackedImagePathsRequireRelink": any(not p["packed"] for p in images)})
result = {"readOnly": True, "nativeFilesUnchanged": True, "blenderVersion": bpy.app.version_string,
          "files": records, "studioGameplayVerified": False}
(ROOT / "native-audit.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
print("FINAL4_NATIVE=" + json.dumps({"readOnly": True, "files": [dict(file=r["file"], meshes=r["meshes"],
       uvMeshes=r["uvMeshes"], images=len(r["images"]), packed=sum(i["packed"] for i in r["images"]),
       unbundled=sum(not i["packed"] and not i["bundledMatches"] for i in r["images"])) for r in records]}))
