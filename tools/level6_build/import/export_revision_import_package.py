"""Export the *revised* Blender kit as one upload/runtime chunk per material mesh.

Run with Blender in background mode. The import-kit .blend contains the exact
triangulated, UV-authored geometry; the full source .blend contains authored
collision boxes, anchors, fixture instances, and room light placements.
Neither input is modified. No Roblox or Studio API is called here.
"""

from __future__ import annotations

import base64
import hashlib
import json
import math
import struct
from pathlib import Path

import bpy
from mathutils import Matrix, Vector


ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "artifacts/level6-studio-revision-20261001"
IMPORT_KIT = SOURCE / "exports-portal14/Level6_Revised_ImportKit.blend"
FULL_SOURCE = SOURCE / "StudioImport_Portal14_Full_Seed101.blend"
IMPORT_RECORD = SOURCE / "exports-portal14/import-manifest.json"
OUTPUT = ROOT / "artifacts/level6-studio-revision-20261001/import-package"
EXPECTED_SHA = {
    IMPORT_KIT: "645badc9c54690a43a38bf30c26048f549d719f08e665280f23c2eac10a7769d",
    FULL_SOURCE: "d2eddfce3820a27f01cdd53b93b719ec8bf8d048b9313bc6cdf29610344acc6b",
}
MAGIC = 0x364D564C  # LVM6, little-endian
AXIS = Matrix(((1, 0, 0), (0, 0, 1), (0, -1, 0)))
FLAT_SIZE_EPSILON = 0.01
VARIANTS = {
    "carpet_city": "L6R_CarpetCity",
    "carpet_default": "L6R_CarpetDefault",
    "carpet_neon": "L6R_CarpetNeon",
    "carpet_red": "L6R_CarpetRed",
    "diamondplate": "L6R_Diamondplate",
    "kitchen_tile": "L6R_KitchenTile",
    "orange_wall": "L6R_OrangeWall",
    "wallpaper": "L6R_Wallpaper",
    "red_wall": "L6R_RedWall",
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def clean(values, places=7):
    return [round(float(value), places) for value in values]


def to_roblox(values):
    return clean(AXIS @ Vector(values))


def intern(value, values, lookup, places):
    key = tuple(clean(value, places))
    if key not in lookup:
        lookup[key] = len(values)
        values.append(key)
    return lookup[key]


def mesh_chunk(obj, row, index):
    assert obj.type == "MESH" and obj.name == row["object"]
    assert len(obj.data.materials) == 1 and obj.data.materials[0].name == row["material"]
    assert all(abs(float(s) - 1) < 1e-7 for s in obj.scale), obj.name
    assert all(abs(float(r)) < 1e-7 for r in obj.rotation_euler), obj.name
    mesh = obj.data
    mesh.calc_loop_triangles()
    assert len(mesh.loop_triangles) == row["triangles"], obj.name
    assert len(mesh.vertices) == row["vertices"], obj.name
    assert mesh.uv_layers.active and mesh.uv_layers.active.name == row["uvLayer"], obj.name

    # Showroom positions belong to the isolated kit display, not prefab origins.
    # The joined mesh vertex coordinates are already in each family local space.
    vertices, normals, uvs, faces = [], [], [], []
    vertex_lookup, normal_lookup, uv_lookup = {}, {}, {}
    for tri in mesh.loop_triangles:
        face = []
        for loop_index in tri.loops:
            loop = mesh.loops[loop_index]
            point = AXIS @ mesh.vertices[loop.vertex_index].co
            normal = (AXIS @ mesh.corner_normals[loop_index].vector).normalized()
            uv = mesh.uv_layers.active.data[loop_index].uv
            assert -0.00001 <= uv.x <= 1.00001 and -0.00001 <= uv.y <= 1.00001, obj.name
            face.extend((
                intern(point, vertices, vertex_lookup, 6),
                intern(normal, normals, normal_lookup, 6),
                intern(uv, uvs, uv_lookup, 7),
            ))
        faces.append(face)
    assert len(vertices) <= 60000 and 0 < len(faces) <= 20000, obj.name
    lower = [min(v[i] for v in vertices) for i in range(3)]
    upper = [max(v[i] for v in vertices) for i in range(3)]
    center = [(lower[i] + upper[i]) / 2 for i in range(3)]
    geometry_size = [upper[i] - lower[i] for i in range(3)]
    # Roblox BasePart.Size cannot contain zero, but five authored architecture
    # finishes are legitimate flat planes. The epsilon does not move vertices.
    part_size = [max(value, FLAT_SIZE_EPSILON) for value in geometry_size]
    assert max(part_size) < 2048 and min(part_size) >= FLAT_SIZE_EPSILON, obj.name

    raw = bytearray(struct.pack("<5I", MAGIC, len(vertices), len(normals), len(uvs), len(faces)))
    for vertex in vertices:
        raw.extend(struct.pack("<3f", *(vertex[i] - center[i] for i in range(3))))
    for normal in normals:
        raw.extend(struct.pack("<3f", *normal))
    for uv in uvs:
        raw.extend(struct.pack("<2f", *uv))
    for face in faces:
        raw.extend(struct.pack("<9I", *face))
    family = row["asset"]
    suffix = obj.name.split("__", 1)[1]
    name = f"m{index:03d}__{suffix}"
    runtime_surface = ("red_wall" if row["maps"].get("color") == "exports/red-wall-color-1024.png"
                       else row["surface"])
    assert runtime_surface is None or runtime_surface in VARIANTS, obj.name
    relative = f"chunks/c{index:03d}.b64"
    path = OUTPUT / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(base64.b64encode(raw))
    return {
        "id": index,
        "name": name,
        "family": family,
        "object": obj.name,
        "material": row["material"],
        "materialKey": suffix,
        "surface": row["surface"],
        "runtimeSurface": runtime_surface,
        "materialVariant": VARIANTS[runtime_surface] if runtime_surface else None,
        "maps": row["maps"],
        "repeatStuds": row["repeatStuds"],
        "file": relative,
        "sha256": hashlib.sha256(raw).hexdigest(),
        "bytes": len(raw),
        "vertices": len(vertices),
        "normals": len(normals),
        "uvs": len(uvs),
        "triangles": len(faces),
        "center": clean(center, 6),
        "size": clean(part_size, 6),
        "geometrySize": clean(geometry_size, 6),
        "uvLayer": row["uvLayer"],
        "uvBounds": row["uvBounds"],
    }


def source_metadata(names, chunks):
    bpy.ops.wm.open_mainfile(filepath=str(FULL_SOURCE))
    collections = {c.name[4:]: c for c in bpy.data.collections if c.name.startswith("L6K_")}
    assert set(collections) == set(names), (len(collections), len(names), set(names) ^ set(collections))
    by_family = {name: [] for name in names}
    for chunk in chunks:
        by_family[chunk["family"]].append(chunk)
    metadata = {}
    for family in names:
        collection = collections[family]
        parts = by_family[family]
        assert parts, family
        low = [min(p["center"][i] - p["geometrySize"][i]/2 for p in parts) for i in range(3)]
        high = [max(p["center"][i] + p["geometrySize"][i]/2 for p in parts) for i in range(3)]
        boxes, anchors, anchor_details, fixtures, lights = [], {}, {}, [], []
        for obj in sorted(collection.objects, key=lambda o: o.name):
            if obj.get("export_collision_only") or obj.get("L6Collider") or obj.get("l6_role") == "collision":
                assert "center_xyz" in obj and "dimensions_xyz" in obj, obj.name
                boxes.append({"center": clean(obj["center_xyz"]), "size": clean(obj["dimensions_xyz"]), "sourceObject": obj.name})
            elif obj.type == "EMPTY" and obj.get("l6_role") == "fixture_instance":
                assert obj.instance_collection and obj.get("l6_child_asset"), obj.name
                fixtures.append({
                    "asset": str(obj["l6_child_asset"]),
                    "sourceObject": obj.name,
                    "positionXYZ": clean(obj.location),
                    "rotationZDegrees": round(math.degrees(obj.rotation_euler.z), 6),
                })
            elif obj.type == "EMPTY" and obj.get("l6_anchor"):
                key = str(obj.get("l6_anchor")) if obj.get("l6_anchor") is not True else obj.name
                anchors[key] = clean(obj.location)
                anchor_details[key] = {"sourceObject": obj.name, "role": obj.get("l6_role") or "anchor"}
                for attr in ("l6_connection_normal_xyz", "l6_port_width", "l6_port_height"):
                    if attr in obj:
                        value = obj[attr]
                        anchor_details[key][attr] = clean(value) if attr == "l6_connection_normal_xyz" else float(value)
            elif obj.type == "LIGHT":
                lights.append({"sourceObject": obj.name, "positionXYZ": clean(obj.location),
                               "type": obj.data.type, "energy": float(obj.data.energy)})
        if family.startswith("Room") and family in ("RoomKitchenPrep", "RoomUtilityHall", "RoomStaffNook"):
            matching = [s for s in bpy.data.scenes if s.name.startswith("Revision study ") and s.name.endswith("| " + family)]
            assert len(matching) == 1, family
            for obj in matching[0].objects:
                if obj.type == "LIGHT":
                    lights.append({"sourceObject": obj.name, "sourceScene": matching[0].name,
                                   "positionXYZ": clean(obj.location), "type": obj.data.type,
                                   "energy": float(obj.data.energy), "colorRGB": clean(obj.data.color)})
        # The early architecture collections do not contain collision proxies;
        # their exact simple boxes are declared alongside those collections in
        # build.py and match the visible wall/slab dimensions in this source.
        if family.startswith("Wall") and family in ("WallBeige", "WallOrange", "WallRed", "WallService"):
            assert not boxes, family
            boxes.append({"center": [0, 0, 6], "size": [8, 1.5, 12], "sourceObject": "build.py:architecture/COLLIDERS"})
        if family.startswith("Floor") and family in ("FloorBeige", "FloorOrange", "FloorRed", "FloorService", "FloorDefault"):
            assert not boxes, family
            boxes.append({"center": [0, 0, -0.5], "size": [80, 64, 1], "sourceObject": "build.py:architecture/COLLIDERS"})
        metadata[family] = {
            "collection": collection.name,
            "familyType": collection.get("l6_family") or "architecture",
            "center": clean([(low[i]+high[i])/2 for i in range(3)], 6),
            "size": clean([max(high[i]-low[i], FLAT_SIZE_EPSILON) for i in range(3)], 6),
            "colliders_xyz": boxes,
            "anchors_xyz": anchors,
            "anchorDetails": anchor_details,
            "fixtureInstances": fixtures,
            "lights_xyz": lights,
            "triangles": sum(p["triangles"] for p in parts),
            "chunkCount": len(parts),
            "hasFlattenedFixtureVisuals": bool(fixtures),
            "hasIntegratedFixtureCollision": family in ("RoomKitchenPrep", "RoomUtilityHall", "RoomStaffNook"),
        }
    return metadata


def luau(value):
    if value is None:
        return "nil"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return json.dumps(value, allow_nan=False)
    if isinstance(value, str):
        return json.dumps(value)
    if isinstance(value, (list, tuple)):
        return "{" + ",".join(luau(item) for item in value) + "}"
    if isinstance(value, dict):
        return "{" + ",".join("[" + luau(key) + "]=" + luau(item)
                              for key, item in sorted(value.items())) + "}"
    raise TypeError(type(value))


def write_runtime_contract(package):
    # Keep persistent StringValue payload small; the full authoring/receipt
    # manifest stays on disk. Runtime needs only mesh assembly and material IDs.
    runtime = {
        "schema": package["schema"],
        "sourceBlendSha256": package["sourceBlendSha256"],
        "importKitBlendSha256": package["importKitBlendSha256"],
        "axisMapping": package["axisMapping"],
        "studsPerUnit": 1,
        "groupId": package["groupId"],
        "placeId": package["placeId"],
        "chunks": [{key: chunk[key] for key in (
            "id", "name", "family", "materialKey", "surface", "runtimeSurface", "materialVariant",
            "center", "size", "sha256", "vertices", "triangles", "bytes")}
            for chunk in package["chunks"]],
        "families": sorted(package["families"]),
        "uniqueTriangles": package["uniqueTriangles"],
    }
    (OUTPUT / "runtime-manifest.json").write_text(json.dumps(runtime, separators=(",", ":")) + "\n")
    metadata = {}
    for family, data in package["families"].items():
        metadata[family] = {
            "Center": data["center"],
            "Size": data["size"],
            "Colliders": [{"center": c["center"], "size": c["size"]} for c in data["colliders_xyz"]],
            "Anchors": data["anchors_xyz"],
            "AnchorDetails": data["anchorDetails"],
            "Lights": data["lights_xyz"],
            "Triangles": data["triangles"],
            "ChunkCount": data["chunkCount"],
            "FixtureInstances": data["fixtureInstances"],
            "HasFlattenedFixtureVisuals": data["hasFlattenedFixtureVisuals"],
            "HasIntegratedFixtureCollision": data["hasIntegratedFixtureCollision"],
        }
    (OUTPUT / "Level 6 Kit Metadata.v2.ModuleScript.luau").write_text(
        "-- Generated from the two SHA-pinned revised Level 6 Blender files.\n"
        "-- Center/Size use Roblox XYZ; boxes/anchors/lights use Blender XYZ.\n"
        "return " + luau(metadata) + "\n")


def main():
    for path, expected in EXPECTED_SHA.items():
        actual = sha256(path)
        assert actual == expected, (path, actual, expected)
    source_record = json.loads(IMPORT_RECORD.read_text())
    assert source_record["meshObjects"] == 279 and source_record["kitCollections"] == 61
    OUTPUT.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.open_mainfile(filepath=str(IMPORT_KIT))
    rows = source_record["meshes"]
    chunks = []
    for index, row in enumerate(rows):
        obj = bpy.data.objects.get(row["object"])
        assert obj is not None, row["object"]
        chunks.append(mesh_chunk(obj, row, index))
    assert len(chunks) == 279 and sum(c["triangles"] for c in chunks) == source_record["totalUniqueTriangles"] == 74092
    names = sorted({chunk["family"] for chunk in chunks})
    families = source_metadata(names, chunks)
    assert len(families) == 61
    package = {
        "schema": "level6-blender-prefabs-v2",
        "sourceBlend": str(FULL_SOURCE.relative_to(ROOT)),
        "sourceBlendSha256": EXPECTED_SHA[FULL_SOURCE],
        "importKitBlend": str(IMPORT_KIT.relative_to(ROOT)),
        "importKitBlendSha256": EXPECTED_SHA[IMPORT_KIT],
        "importManifestSha256": sha256(IMPORT_RECORD),
        "axisMapping": "X,Z,-Y",
        "studsPerUnit": 1,
        "uvVForRoblox": "1 - BlenderV",
        "groupId": 1039373905,
        "placeId": 131311258779917,
        "families": families,
        "chunks": chunks,
        "uniqueTriangles": sum(c["triangles"] for c in chunks),
        "flatGeometryMinimumPartSize": FLAT_SIZE_EPSILON,
    }
    (OUTPUT / "manifest.json").write_text(json.dumps(package, indent=2) + "\n")
    write_runtime_contract(package)
    print("LEVEL6_REVISION_IMPORT_PACKAGE", json.dumps({"families":len(families),
        "chunks":len(chunks), "uniqueTriangles":package["uniqueTriangles"],
        "bytes":sum(c["bytes"] for c in chunks)}), flush=True)


if __name__ == "__main__":
    main()
