"""Independently verify the revised Level 6 FBX in fresh background Blender.

Run with --background --factory-startup --python this_file. This script reads the
export and source manifests only; it neither saves a .blend nor edits exports.
"""
from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path
import sys

import bpy
import numpy as np
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
EXPORT = ROOT / "exports"
MANIFEST_PATH = EXPORT / "import-manifest.json"
FBX_PATH = EXPORT / "Level6_Revised_ReusableKit.fbx"
OUT = ROOT / "verification" / "fbx-roundtrip.json"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def child(element, name: bytes):
    return next((e for e in element.elems if e.id == name), None)


def children(element, name: bytes):
    return [e for e in element.elems if e.id == name]


def binary_tangent_audit(path: Path) -> dict:
    from io_scene_fbx import parse_fbx

    root, version = parse_fbx.parse(str(path))
    objects = child(root, b"Objects")
    geometries = children(objects, b"Geometry") if objects else []
    mesh_geometries = [g for g in geometries if any(p == b"Mesh" for p in g.props)]
    records = []
    all_tangent_vectors = 0
    all_normal_vectors = 0
    for geom in mesh_geometries:
        raw_name = next((p for p in geom.props if isinstance(p, bytes) and b"Geometry::" in p), b"")
        name = raw_name.decode("utf-8", "replace")
        tangent_layers = children(geom, b"LayerElementTangent")
        normal_layers = children(geom, b"LayerElementNormal")
        binormal_layers = children(geom, b"LayerElementBinormal")
        uv_layers = children(geom, b"LayerElementUV")
        normals = []
        for layer in normal_layers:
            element = child(layer, b"Normals")
            values = np.asarray(element.props[0], dtype=np.float64) if element and element.props else np.empty(0)
            if values.size % 3 == 0:
                vectors = values.reshape((-1, 3))
                lengths = np.linalg.norm(vectors, axis=1) if vectors.size else np.empty(0)
                nonfinite = int(np.count_nonzero(~np.isfinite(vectors)))
                degenerate = int(np.count_nonzero(lengths < 1e-6))
                vector_count = len(vectors)
            else:
                vector_count = 0
                nonfinite = int(values.size)
                degenerate = 0
            all_normal_vectors += vector_count
            normals.append({"floatCount": int(values.size), "vectorCount": vector_count,
                            "nonfiniteComponents": nonfinite, "degenerateVectors": degenerate})
        tangents = []
        for layer in tangent_layers:
            element = child(layer, b"Tangents")
            values = np.asarray(element.props[0], dtype=np.float64) if element and element.props else np.empty(0)
            if values.size % 3 == 0:
                vectors = values.reshape((-1, 3))
                lengths = np.linalg.norm(vectors, axis=1) if vectors.size else np.empty(0)
                nonfinite = int(np.count_nonzero(~np.isfinite(vectors)))
                degenerate = int(np.count_nonzero(lengths < 1e-6))
                mean_length = float(np.mean(lengths)) if lengths.size else None
                vector_count = len(vectors)
            else:
                vector_count = 0
                nonfinite = int(values.size)
                degenerate = 0
                mean_length = None
            all_tangent_vectors += vector_count
            tangents.append({"floatCount": int(values.size), "vectorCount": vector_count,
                             "nonfiniteComponents": nonfinite, "degenerateVectors": degenerate,
                             "meanLength": mean_length})
        records.append({"geometry": name, "normalLayerCount": len(normal_layers),
                        "normalLayers": normals, "binormalLayerCount": len(binormal_layers),
                        "uvLayerCount": len(uv_layers), "tangentLayerCount": len(tangent_layers),
                        "tangentLayers": tangents})
    return {"fbxVersion": version, "geometryCount": len(mesh_geometries),
            "geometriesWithNormals": sum(r["normalLayerCount"] > 0 for r in records),
            "geometriesWithBinormals": sum(r["binormalLayerCount"] > 0 for r in records),
            "geometriesWithUVs": sum(r["uvLayerCount"] > 0 for r in records),
            "geometriesWithTangents": sum(r["tangentLayerCount"] > 0 for r in records),
            "normalVectorCount": all_normal_vectors,
            "tangentVectorCount": all_tangent_vectors,
            "nonfiniteNormalComponents": sum(n["nonfiniteComponents"] for r in records for n in r["normalLayers"]),
            "degenerateNormalVectors": sum(n["degenerateVectors"] for r in records for n in r["normalLayers"]),
            "nonfiniteTangentComponents": sum(t["nonfiniteComponents"] for r in records for t in r["tangentLayers"]),
            "degenerateTangentVectors": sum(t["degenerateVectors"] for r in records for t in r["tangentLayers"]),
            "missingTangents": [r["geometry"] for r in records if not r["tangentLayerCount"]],
            "records": records}


def world_bounds(obj) -> list[float]:
    corners = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    return [min(p[axis] for p in corners) for axis in range(3)] + [max(p[axis] for p in corners) for axis in range(3)]


def expected_bounds(entry) -> list[float]:
    corners = [Vector(entry["showroomXYZ"]) + Vector(corner) for corner in entry["localBoundingBoxXYZ"]]
    return [min(p[axis] for p in corners) for axis in range(3)] + [max(p[axis] for p in corners) for axis in range(3)]


def imported_material_maps(mat) -> dict:
    found = []
    if mat and mat.use_nodes:
        def principled_destinations(start):
            reached = set()
            pending = [(start, 0)]
            visited = set()
            while pending:
                node, depth = pending.pop()
                if node in visited or depth > 5:
                    continue
                visited.add(node)
                for link in mat.node_tree.links:
                    if link.from_node != node:
                        continue
                    if link.to_node.type == "BSDF_PRINCIPLED":
                        reached.add(link.to_socket.name)
                    else:
                        pending.append((link.to_node, depth + 1))
            return sorted(reached)

        for node in mat.node_tree.nodes:
            if node.type != "TEX_IMAGE" or not node.image:
                continue
            image = node.image
            path = Path(bpy.path.abspath(image.filepath)) if image.filepath else None
            found.append({"image": image.name, "filepath": image.filepath,
                          "resolvedPath": str(path) if path else None,
                          "fileExists": bool(path and path.exists()),
                          "packed": image.packed_file is not None,
                          "colorSpace": image.colorspace_settings.name,
                          "principledDestinations": principled_destinations(node)})
    return {"imageNodes": found, "imageNodeCount": len(found),
            "allPathsResolve": all(node["fileExists"] or node["packed"] for node in found)}


def main() -> None:
    manifest = json.loads(MANIFEST_PATH.read_text())
    fbx_hash = sha256(FBX_PATH)
    source_blend = ROOT / "Level6_Revised_Full_Seed101.blend"
    kit_blend = EXPORT / "Level6_Revised_ImportKit.blend"
    hashes = {"fbx": fbx_hash, "manifestFbx": manifest["fbxSha256"],
              "sourceBlend": sha256(source_blend), "manifestSourceBlend": manifest["sourceBlendSha256"],
              "importKitBlend": sha256(kit_blend), "manifestImportKitBlend": manifest["importKitBlendSha256"]}
    hashes["allMatch"] = all(hashes[a] == hashes[b] for a, b in (
        ("fbx", "manifestFbx"), ("sourceBlend", "manifestSourceBlend"),
        ("importKitBlend", "manifestImportKitBlend")))

    raw = binary_tangent_audit(FBX_PATH)

    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.fbx(filepath=str(FBX_PATH), use_image_search=False)
    imported = {obj.name: obj for obj in bpy.data.objects if obj.type == "MESH"}
    expected = {entry["object"]: entry for entry in manifest["meshes"]}
    rows = []
    for name, entry in sorted(expected.items()):
        obj = imported.get(name)
        if obj is None:
            rows.append({"object": name, "imported": False})
            continue
        mesh = obj.data
        mesh.calc_loop_triangles()
        uv = mesh.uv_layers.active
        uv_bounds = ([min(loop.uv[axis] for loop in uv.data) for axis in range(2)]
                     + [max(loop.uv[axis] for loop in uv.data) for axis in range(2)]) if uv and uv.data else None
        triangle_count = len(mesh.loop_triangles)
        material_names = [mat.name for mat in mesh.materials if mat]
        actual_bounds = world_bounds(obj)
        expected_world = expected_bounds(entry)
        bound_error = max(abs(a - b) for a, b in zip(actual_bounds, expected_world))
        location_error = max(abs(obj.location[i] - entry["showroomXYZ"][i]) for i in range(3))
        uv_bound_error = (max(abs(a - b) for a, b in zip(uv_bounds, entry["uvBounds"]))
                          if uv_bounds else None)
        row = {"object": name, "imported": True, "asset": entry["asset"],
               "triangles": triangle_count, "expectedTriangles": entry["triangles"],
               "vertices": len(mesh.vertices), "expectedVertices": entry["vertices"],
               "materials": material_names, "expectedMaterial": entry["material"],
               "uvLayer": uv.name if uv else None, "expectedUVLayer": entry["uvLayer"],
               "uvBounds": uv_bounds, "expectedUVBounds": entry["uvBounds"],
               "uvBoundMaximumError": uv_bound_error,
               "boundsXYZMinMax": actual_bounds, "expectedBoundsXYZMinMax": expected_world,
               "boundsMaximumErrorStuds": bound_error,
               "locationMaximumErrorStuds": location_error,
               "materialImageMaps": imported_material_maps(mesh.materials[0] if mesh.materials else None),
               "surface": entry["surface"], "sidecarMaps": entry["maps"]}
        expected_role_sockets = {"color": "Base Color", "normalOpenGL": "Normal",
                                 "roughness": "Roughness", "metalness": "Metallic"}
        checks = {}
        for role, relative in entry["maps"].items():
            if role == "height":
                continue  # Authoring intermediate; intentionally not an FBX PBR map.
            expected_path = (ROOT / relative).resolve()
            nodes = [n for n in row["materialImageMaps"]["imageNodes"]
                     if n["resolvedPath"] and Path(n["resolvedPath"]).resolve() == expected_path]
            checks[role] = {"expectedPath": str(expected_path), "sidecarExists": expected_path.exists(),
                            "importedMatchingImageNodes": len(nodes),
                            "importedColorSpaces": sorted({n["colorSpace"] for n in nodes}),
                            "reachesExpectedPrincipledSocket": any(
                                expected_role_sockets.get(role) in n["principledDestinations"] for n in nodes)}
        row["mapRoleChecks"] = checks
        rows.append(row)

    present = [r for r in rows if r["imported"]]
    summary = {"manifestMeshObjects": manifest["meshObjects"], "importedMeshObjects": len(imported),
               "matchedMeshObjects": len(present), "missingMeshObjects": sorted(set(expected) - set(imported)),
               "unexpectedMeshObjects": sorted(set(imported) - set(expected)),
               "manifestKitCollections": manifest["kitCollections"],
               "importedKitPrefixes": len({name.split("__", 1)[0] for name in imported}),
               "manifestTriangles": manifest["totalUniqueTriangles"],
               "importedTriangles": sum(r["triangles"] for r in present),
               "maximumImportedTrianglesPerMesh": max((r["triangles"] for r in present), default=0),
               "trianglesMismatched": [r["object"] for r in present if r["triangles"] != r["expectedTriangles"]],
               "verticesMismatched": [r["object"] for r in present if r["vertices"] != r["expectedVertices"]],
               "materialsMismatched": [r["object"] for r in present if r["materials"] != [r["expectedMaterial"]]],
               "uvLayerMismatched": [r["object"] for r in present if r["uvLayer"] != r["expectedUVLayer"]],
               "uvOutOfRange": [r["object"] for r in present if r["uvBounds"] is None or
                                min(r["uvBounds"]) < -1e-5 or max(r["uvBounds"]) > 1.00001],
               "uvBoundsMismatched": [r["object"] for r in present if r["uvBoundMaximumError"] is None or
                                      r["uvBoundMaximumError"] > 1e-4],
               "boundsMismatched": [r["object"] for r in present if r["boundsMaximumErrorStuds"] > 1e-3],
               "locationsMismatched": [r["object"] for r in present if r["locationMaximumErrorStuds"] > 1e-3],
               "maximumBoundsErrorStuds": max((r["boundsMaximumErrorStuds"] for r in present), default=None),
               "maximumLocationErrorStuds": max((r["locationMaximumErrorStuds"] for r in present), default=None),
               "maximumUVBoundsError": max((r["uvBoundMaximumError"] for r in present
                                             if r["uvBoundMaximumError"] is not None), default=None),
               "importedMaterialCount": len({name for r in present for name in r["materials"]}),
               "materialsWithNoImageNodes": sorted({r["materials"][0] for r in present
                                                     if r["materials"] and not r["materialImageMaps"]["imageNodeCount"]}),
               "materialsWithUnresolvedImages": sorted({r["materials"][0] for r in present
                                                         if r["materials"] and not r["materialImageMaps"]["allPathsResolve"]}),
               "mapFilesMissing": [r["object"] + ":" + role for r in present
                                   for role, check in r["mapRoleChecks"].items() if not check["sidecarExists"]],
               "mapPathsMismatched": [r["object"] + ":" + role for r in present
                                      for role, check in r["mapRoleChecks"].items()
                                      if check["importedMatchingImageNodes"] == 0],
               "mapRolesNotLinked": [r["object"] + ":" + role for r in present
                                     for role, check in r["mapRoleChecks"].items()
                                     if not check["reachesExpectedPrincipledSocket"]],
               "mapColorSpacesUnexpected": [r["object"] + ":" + role for r in present
                                            for role, check in r["mapRoleChecks"].items()
                                            if check["importedMatchingImageNodes"] and
                                            ("Non-Color" not in check["importedColorSpaces"] if role != "color"
                                             else "sRGB" not in check["importedColorSpaces"])]}
    # The importer may recalculate rather than read tangents. The binary audit
    # above proves whether the exported FBX actually contains them.
    gates = {"hashes": hashes["allMatch"], "objectCount": summary["importedMeshObjects"] == manifest["meshObjects"],
             "objectNames": not summary["missingMeshObjects"] and not summary["unexpectedMeshObjects"],
             "kitCount": summary["importedKitPrefixes"] == manifest["kitCollections"],
             "triangles": summary["importedTriangles"] == manifest["totalUniqueTriangles"] and
                          not summary["trianglesMismatched"],
             "oneExpectedMaterialPerMesh": not summary["materialsMismatched"],
             "sidecarFilesAndImportedPaths": not summary["mapFilesMissing"] and
                                              not summary["mapPathsMismatched"],
             "sidecarRoleLinks": not summary["mapRolesNotLinked"],
             "sidecarColorSpaces": not summary["mapColorSpacesUnexpected"],
             "uv0to1": not summary["uvOutOfRange"], "uvBounds": not summary["uvBoundsMismatched"],
             "worldBounds": not summary["boundsMismatched"],
             "fbxNormals": raw["geometriesWithNormals"] == manifest["meshObjects"] and
                           not raw["nonfiniteNormalComponents"] and not raw["degenerateNormalVectors"],
             "fbxTangents": raw["geometriesWithTangents"] == manifest["meshObjects"] and
                             not raw["nonfiniteTangentComponents"] and not raw["degenerateTangentVectors"]}
    report = {"schemaVersion": 1, "verification": "fresh Blender 5.2 FBX import plus raw binary FBX layer audit",
              "blenderVersion": bpy.app.version_string, "fbxPath": str(FBX_PATH),
              "hashes": hashes, "summary": summary, "rawFbx": raw, "gates": gates,
              "allRequiredGatesPassed": all(gates.values()),
              "limitations": ["Blender reimport does not prove Roblox Studio map assignment or visual quality.",
                              "Blender's FBX importer can recompute tangent space; raw LayerElementTangent audit checks the exported file.",
                              "PBR image-node/path findings describe Blender reimport, not Studio import."],
              "meshes": rows}
    # Opening the compact .blend replaces the current imported FBX scene. The
    # startup was factory-clean; this is an independent fresh-load check of the
    # library-written ImportKit, without saving or touching its file.
    bpy.ops.wm.open_mainfile(filepath=str(kit_blend), load_ui=False)
    scenes = sorted(s.name for s in bpy.data.scenes)
    kit_scene_name = "Roblox import | revised reusable Level 6 kit"
    kit_scene = bpy.data.scenes.get(kit_scene_name)
    scene_meshes = [o for o in kit_scene.objects if o.type == "MESH"] if kit_scene else []
    scene_prefixes = {o.name.split("__", 1)[0] for o in scene_meshes if o.name.startswith("L6K_")}
    all_scene_objects = [o for s in bpy.data.scenes for o in s.objects]
    image_details = []
    for image in bpy.data.images:
        if image.source != "FILE":
            continue
        path = Path(bpy.path.abspath(image.filepath)) if image.filepath else None
        image_details.append({"image": image.name, "size": list(image.size),
                              "packed": image.packed_file is not None,
                              "resolvedPath": str(path) if path else None,
                              "fileExists": bool(path and path.exists())})
    kit_audit = {"scenes": scenes,
                 "contextSceneAfterOpen": bpy.context.scene.name if bpy.context.scene else None,
                 "kitScenePresent": kit_scene is not None,
                 "sceneMeshObjects": len(scene_meshes),
                 "sceneKitPrefixes": len(scene_prefixes),
                 "sceneNonMeshObjects": len(kit_scene.objects) - len(scene_meshes) if kit_scene else None,
                 "sourceKitCollections": len([c for c in bpy.data.collections if c.name.startswith("L6K_")]),
                 "allSceneObjectTypes": sorted({o.type for o in all_scene_objects}),
                 "fullMapScenePresent": any("FULL" in name.upper() or "35 ROOM" in name.upper()
                                            for name in scenes),
                 "collectionInstances": sum(o.instance_type == "COLLECTION" for o in all_scene_objects),
                 "imageFileCount": len(image_details),
                 "unresolvedImages": [i["image"] for i in image_details if not i["packed"] and not i["fileExists"]],
                 "images": image_details}
    kit_audit["passed"] = (kit_audit["kitScenePresent"] and len(scenes) == 1 and
                           kit_audit["sceneMeshObjects"] == manifest["meshObjects"] and
                           kit_audit["sceneKitPrefixes"] == manifest["kitCollections"] and
                           not kit_audit["fullMapScenePresent"] and not kit_audit["collectionInstances"] and
                           not kit_audit["unresolvedImages"])
    report["importKitFreshLoad"] = kit_audit
    report["gates"]["importKitFreshLoad"] = kit_audit["passed"]
    report["allRequiredGatesPassed"] = all(report["gates"].values())
    OUT.write_text(json.dumps(report, indent=2) + "\n")
    print("LEVEL6_FBX_ROUNDTRIP", json.dumps({"allRequiredGatesPassed": report["allRequiredGatesPassed"],
                                                "summary": summary, "rawFbx": {k: v for k, v in raw.items() if k != "records"},
                                                "gates": gates}), flush=True)


if __name__ == "__main__":
    main()
