"""Reopen both .blend files and verify the saved geometry, UV and material keys."""
import bpy
import hashlib
import json
import struct
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SOURCE = ROOT / "assets/level6-worn-party/Level6_WornParty_v2.blend"
CANDIDATE = HERE / "Level6_WornParty_Level3Reference_candidate.blend"
ATLAS = HERE / "textures/WornParty_Level3Reference_Atlas.png"


def digest(data):
    return hashlib.sha256(data).hexdigest()


def json_digest(value):
    return digest(json.dumps(value, sort_keys=True, separators=(",", ":")).encode())


def inspect(path):
    bpy.ops.wm.open_mainfile(filepath=str(path))
    geometry, uv, material_keys, instances = [], [], [], []
    for obj in sorted(bpy.data.objects, key=lambda item: item.name):
        instances.append({"name": obj.name, "type": obj.type,
                          "matrixWorld": [list(row) for row in obj.matrix_world],
                          "collectionInstance": obj.instance_collection.name if obj.instance_collection else None,
                          "collections": sorted(collection.name for collection in obj.users_collection)})
        if obj.type != "MESH":
            continue
        mesh = obj.data
        geometry.append({"object": obj.name, "mesh": mesh.name,
                         "vertices": digest(b"".join(struct.pack("<3f", *vertex.co) for vertex in mesh.vertices)),
                         "normals": digest(b"".join(struct.pack("<3f", *vertex.normal) for vertex in mesh.vertices)),
                         "polygons": digest(b"".join(struct.pack("<" + "I" * len(face.vertices), *face.vertices) for face in mesh.polygons)),
                         "matrixWorld": [list(row) for row in obj.matrix_world]})
        uv.append({"object": obj.name, "layers": [
            {"name": layer.name, "uv": digest(b"".join(struct.pack("<2f", *item.uv) for item in layer.data))}
            for layer in mesh.uv_layers]})
        material_keys.append({"object": obj.name,
                              "objectMaterialKey": obj.get("l6_material_key"),
                              "slots": [{"name": material.name, "key": material.get("l6_material_key")}
                                        if material else None for material in mesh.materials],
                              "faceMaterialIndices": digest(b"".join(struct.pack("<I", face.material_index) for face in mesh.polygons))})
    material_keys.append({"allMaterials": [{"name": material.name, "key": material.get("l6_material_key")}
                                           for material in sorted(bpy.data.materials, key=lambda item: item.name)]})
    return {"geometrySHA256": json_digest(geometry), "uvSHA256": json_digest(uv),
            "materialKeysSHA256": json_digest(material_keys), "instancesSHA256": json_digest(instances),
            "objectCount": len(bpy.data.objects), "materialCount": len(bpy.data.materials),
            "meshObjectCount": len(geometry), "sceneNames": sorted(scene.name for scene in bpy.data.scenes),
            "instanceRecords": instances}


baseline = inspect(SOURCE)
candidate = inspect(CANDIDATE)
before_instances = {item["name"]: item for item in baseline.pop("instanceRecords")}
after_instances = {item["name"]: item for item in candidate.pop("instanceRecords")}
for key in baseline.keys() - {"instancesSHA256"}:
    assert baseline[key] == candidate[key], (key, baseline[key], candidate[key])
expected_routes = {"Floor.003": ("L6K_FloorOrange", "L6K_FloorBeige"),
                   "Floor.004": ("L6K_FloorService", "L6K_FloorOrange")}
assert before_instances.keys() == after_instances.keys()
actual_changes = []
for name, original in before_instances.items():
    changed = after_instances[name]
    if original == changed:
        continue
    assert name in expected_routes
    before_collection, after_collection = expected_routes[name]
    assert original["collectionInstance"] == before_collection
    assert changed["collectionInstance"] == after_collection
    normalized = changed.copy()
    normalized["collectionInstance"] = before_collection
    assert original == normalized, (name, original, normalized)
    actual_changes.append({"object": name, "beforeCollection": before_collection,
                           "afterCollection": after_collection, "transformAndMembershipUnchanged": True})
assert len(actual_changes) == len(expected_routes)
assert after_instances["Floor.005"] == before_instances["Floor.005"]
packed_atlas = bpy.data.images["WornParty_Level3Reference_Atlas.png"]
assert packed_atlas.packed_file
assert digest(packed_atlas.packed_file.data) == digest(ATLAS.read_bytes())
manifest = json.loads((HERE / "blend-candidate-manifest.json").read_text())
assert digest(SOURCE.read_bytes()) == manifest["sourceBlendSha256"]
assert digest(CANDIDATE.read_bytes()) == manifest["candidateBlendSha256"]
result = {"schema": "level6-offline-blender-saved-parity-v1", "installedInStudio": False,
          "sourceBlendSha256": digest(SOURCE.read_bytes()), "candidateBlendSha256": digest(CANDIDATE.read_bytes()),
          "baseline": baseline, "candidate": candidate,
          "savedGeometryUVMaterialKeysMatch": True,
          "savedSceneInstanceRoutingChangesMatchScope": True,
          "sceneInstanceRoutingChanges": actual_changes,
          "maintenanceStudyFloorServiceUnchanged": True,
          "sourceBlendUnchanged": True, "packedAtlasMatchesCandidatePNG": True,
          "candidateAtlasSha256": digest(ATLAS.read_bytes()), "blenderVersion": bpy.app.version_string,
          "limitations": ["Offline authoring source comparison, not current Studio parity.",
                          "Physical texture repeat remains the original Blender mesh-face repeat.",
                          "Live Roblox native A/B, floor routing, gameplay and performance remain separate checks."]}
(HERE / "saved-blend-parity.json").write_text(json.dumps(result, indent=2) + "\n")
print("CANDIDATE_SAVED_PARITY", json.dumps(result))
