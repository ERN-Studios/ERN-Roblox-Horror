"""Read-only, independent material and UV inspection of the revised .blend.

Run with Blender in background mode after opening the revised place. It writes
only material-validation.json beside this script; it never saves the blend.
"""

from __future__ import annotations

import hashlib
import json
import os
import struct
import subprocess
import tempfile
from collections import defaultdict
from pathlib import Path

import bpy
import numpy as np


TASK = Path(__file__).resolve().parents[1]
ROOT = TASK.parents[1]
REPORT = TASK / "verification/material-validation.json"
MATERIAL_MANIFEST = json.loads((TASK / "materials/material-manifest.json").read_text())
BUILD_MANIFEST = json.loads((TASK / "build-manifest.json").read_text())
SOURCE = ROOT / "assets/level6-worn-party/Level6_FULL_Seed101.blend"
issues = []


def error(code, detail):
    issues.append({"code": code, "detail": detail})


def digest(data):
    return hashlib.sha256(data).hexdigest()


def vertex_hash(obj):
    return digest(b"".join(struct.pack("<3f", *v.co) for v in obj.data.vertices))


def inputs_to(tree, node, socket_name):
    return [link for link in tree.links if link.to_node == node and link.to_socket.name == socket_name]


def packed_bytes(image):
    packed = image.packed_file
    return bytes(packed.data) if packed else None


def validate_material(material):
    identifier = material.get("l6_surface_id")
    expected = MATERIAL_MANIFEST["materials"][identifier]
    result = {"material": material.name, "surface": identifier, "maps": {}, "issues": []}
    if not material.use_nodes:
        error("MATERIAL_NODES_MISSING", material.name)
        return result
    repeat = float(material.get("l6_physical_repeat_studs", -1))
    bump = float(material.get("l6_bump_distance_studs", -1))
    result["repeatStuds"] = repeat
    result["bumpDistanceStuds"] = bump
    if abs(repeat - expected["physicalRepeatStuds"]) > 1e-6:
        error("REPEAT_PROPERTY_MISMATCH", {"material": material.name, "actual": repeat})
    if abs(bump - expected["bumpDistanceStuds"]) > 1e-6:
        error("BUMP_PROPERTY_MISMATCH", {"material": material.name, "actual": bump})
    nodes = material.node_tree.nodes
    tree = material.node_tree
    shader = next((n for n in nodes if n.type == "BSDF_PRINCIPLED"), None)
    output = next((n for n in nodes if n.type == "OUTPUT_MATERIAL"), None)
    if shader is None or output is None:
        error("BSDF_OR_OUTPUT_MISSING", material.name)
        return result
    if not any(link.from_node == shader for link in inputs_to(tree, output, "Surface")):
        error("BSDF_NOT_ACTIVE", material.name)

    uv_nodes = [n for n in nodes if n.type == "UVMAP"]
    if not uv_nodes or any(n.uv_map != "SurfaceUV" for n in uv_nodes):
        error("MATERIAL_UV_NAME", material.name)
    textures = {n.label: n for n in nodes if n.type == "TEX_IMAGE" and n.label}
    for key, path in expected["maps"].items():
        texture = textures.get(key)
        if texture is None or texture.image is None:
            error("MAP_NODE_MISSING", {"material": material.name, "map": key})
            continue
        image = texture.image
        embedded = packed_bytes(image)
        expected_hash = expected["sha256"]["sourceColor"] if key == "color" and expected.get("sourceColor") else expected["sha256"][key]
        actual_hash = digest(embedded) if embedded is not None else None
        colorspace = image.colorspace_settings.name
        expected_space = "sRGB" if key == "color" else "Non-Color"
        if actual_hash != expected_hash:
            error("PACKED_MAP_HASH", {"material": material.name, "map": key, "actual": actual_hash, "expected": expected_hash})
        if colorspace != expected_space:
            error("MAP_COLORSPACE", {"material": material.name, "map": key, "actual": colorspace, "expected": expected_space})
        if not any(link.from_node in uv_nodes for link in inputs_to(tree, texture, "Vector")):
            error("MAP_UV_UNLINKED", {"material": material.name, "map": key})
        result["maps"][key] = {"image": image.name, "packed": embedded is not None, "sha256": actual_hash,
                               "colorspace": colorspace, "pixels": list(image.size)}

    normals = [n for n in nodes if n.type == "NORMAL_MAP"]
    bumps = [n for n in nodes if n.type == "BUMP"]
    normal_texture = textures.get("normalOpenGL")
    height_texture = textures.get("height")
    active_normal = inputs_to(tree, shader, "Normal")
    normal_ok = len(active_normal) == 1 and active_normal[0].from_node in normals
    if not normal_ok:
        error("NORMAL_NOT_ACTIVE_BSDF", material.name)
    for normal in normals:
        if normal.uv_map != "SurfaceUV":
            error("NORMAL_UV_NAME", {"material": material.name, "actual": normal.uv_map})
        if normal_texture and not any(link.from_node == normal_texture for link in inputs_to(tree, normal, "Color")):
            error("NORMAL_TEXTURE_DISCONNECTED", material.name)
    if not bumps or any(link.from_node in bumps for link in active_normal):
        error("BUMP_ALTERNATE_ROUTE", material.name)
    if height_texture and not any(bump for bump in bumps if any(link.from_node == height_texture for link in inputs_to(tree, bump, "Height"))):
        error("HEIGHT_ALTERNATE_DISCONNECTED", material.name)
    if "roughness" in textures and not any(link.from_node == textures["roughness"] for link in inputs_to(tree, shader, "Roughness")):
        error("ROUGHNESS_DISCONNECTED", material.name)
    if "metalness" in textures and not any(link.from_node == textures["metalness"] for link in inputs_to(tree, shader, "Metallic")):
        error("METALNESS_DISCONNECTED", material.name)
    if "color" in textures and not any(link.from_node == textures["color"] for link in tree.links):
        error("COLOR_DISCONNECTED", material.name)
    result["activeNormalNode"] = active_normal[0].from_node.name if normal_ok else None
    result["heightAlternativeConnectedToBSDF"] = any(link.from_node in bumps for link in active_normal)
    return result


def projected_axes(normal):
    axis = max(range(3), key=lambda a: abs(normal[a]))
    return (0, 1) if axis == 2 else ((1, 2) if axis == 0 else (0, 2))


def validate_uv_object(obj, relevant_scene_names):
    surface_materials = [m for m in obj.data.materials if m and m.get("l6_surface_id")]
    if not surface_materials:
        return None
    expected_repeats = {float(MATERIAL_MANIFEST["materials"][m["l6_surface_id"]]["physicalRepeatStuds"])
                        for m in surface_materials}
    tagged_repeat = obj.get("l6_uv_repeat_studs")
    if tagged_repeat is None:
        error("PLACED_PBR_OBJECT_NOT_TILED", {"object": obj.name, "scenes": relevant_scene_names})
        return None
    repeat = float(tagged_repeat)
    if len(expected_repeats) != 1 or any(abs(repeat - x) > 1e-6 for x in expected_repeats):
        error("OBJECT_REPEAT_MISMATCH", {"object": obj.name, "tagged": repeat, "materialRepeats": sorted(expected_repeats)})
    layer = obj.data.uv_layers.get("SurfaceUV")
    if layer is None or not layer.active_render:
        error("SURFACE_UV_MISSING", obj.name)
        return None
    uvs = layer.data
    uv_min = min(min(item.uv) for item in uvs) if uvs else None
    uv_max = max(max(item.uv) for item in uvs) if uvs else None
    if uv_min is None or uv_min < -1e-4 or uv_max > 1.0001:
        error("UV_OUT_OF_UNIT_TILE", {"object": obj.name, "min": uv_min, "max": uv_max})

    max_residual = 0.0
    measured_edges = 0
    sample_residuals = []
    matrix = obj.matrix_world
    for polygon in obj.data.polygons:
        normal_world = matrix.to_3x3() @ polygon.normal
        uaxis, vaxis = projected_axes(normal_world)
        indices = list(polygon.loop_indices)
        for index, current in enumerate(indices):
            following = indices[(index + 1) % len(indices)]
            a = matrix @ obj.data.vertices[obj.data.loops[current].vertex_index].co
            b = matrix @ obj.data.vertices[obj.data.loops[following].vertex_index].co
            uv_a, uv_b = uvs[current].uv, uvs[following].uv
            for axis, uv_axis in ((uaxis, 0), (vaxis, 1)):
                physical = abs(b[axis] - a[axis])
                mapped = abs(uv_b[uv_axis] - uv_a[uv_axis]) * repeat
                if physical > 1e-4 or mapped > 1e-4:
                    residual = abs(physical - mapped)
                    max_residual = max(max_residual, residual)
                    measured_edges += 1
                    if residual > 0.03 and len(sample_residuals) < 3:
                        sample_residuals.append({"polygon": polygon.index, "axis": axis, "physicalStuds": round(physical, 5),
                                                 "uvStuds": round(mapped, 5), "residualStuds": round(residual, 5)})
    if max_residual > 0.03:
        error("PHYSICAL_UV_SCALE", {"object": obj.name, "repeatStuds": repeat,
                                    "maxResidualStuds": round(max_residual, 5), "examples": sample_residuals})
    return {"name": obj.name, "surfaces": sorted(m["l6_surface_id"] for m in surface_materials),
            "scenes": relevant_scene_names, "repeatStuds": repeat, "uvRange": [uv_min, uv_max],
            "edgesMeasured": measured_edges, "maxEdgeScaleResidualStuds": round(max_residual, 6),
            "polygonCount": len(obj.data.polygons), "worldDimensions": [round(x, 4) for x in obj.dimensions]}


def main():
    expected_output = ROOT / BUILD_MANIFEST["outputBlend"]
    if Path(bpy.data.filepath).resolve() != expected_output.resolve():
        error("WRONG_OPEN_BLEND", bpy.data.filepath)
    blend_hash = digest(expected_output.read_bytes())
    if blend_hash != BUILD_MANIFEST["outputSha256"]:
        error("BUILD_BLEND_HASH", {"actual": blend_hash, "expected": BUILD_MANIFEST["outputSha256"]})
    material_rows = []
    by_surface = defaultdict(list)
    for material in bpy.data.materials:
        if material.get("l6_surface_id"):
            row = validate_material(material)
            material_rows.append(row)
            by_surface[row["surface"]].append(row["material"])
    for identifier in MATERIAL_MANIFEST["materials"]:
        if not by_surface[identifier]:
            error("MATERIAL_ID_MISSING", identifier)
    normal_quantization = {}
    for identifier, names in by_surface.items():
        material = bpy.data.materials[names[0]]
        texture = next((n for n in material.node_tree.nodes if n.type == "TEX_IMAGE" and n.label == "normalOpenGL"), None)
        if texture is None or texture.image is None:
            continue
        image = texture.image
        packed_rgba = np.empty(len(image.pixels), dtype=np.float32)
        image.pixels.foreach_get(packed_rgba)
        rgb = packed_rgba.reshape(-1, 4)[:, :3]
        normal = rgb * 2.0 - 1.0
        xy_span_8bit = [round(float((rgb[:, c].max() - rgb[:, c].min()) * 255), 3) for c in (0, 1)]
        xy_std_8bit = [round(float(rgb[:, c].std() * 255), 3) for c in (0, 1)]
        unit_error = float(np.max(np.abs(np.linalg.norm(normal, axis=1) - 1.0)))
        normal_quantization[identifier] = {"xyRangeIn8BitLevels": xy_span_8bit,
                                           "xyStandardDeviationIn8BitLevels": xy_std_8bit,
                                           "maximumUnitLengthError": round(unit_error, 6)}
        if min(xy_span_8bit) < 3 or min(xy_std_8bit) < 0.3:
            error("NORMAL_EFFECTIVELY_FLAT", {"surface": identifier, "metrics": normal_quantization[identifier]})
        if unit_error > 0.012:
            error("NORMAL_NOT_UNIT", {"surface": identifier, "maxError": unit_error})

    scenes = [scene for scene in bpy.data.scenes if scene.name.startswith("Level 6 | Revised FULL") or scene.name.startswith("Revision study")]
    scene_summary = {}
    relevant_objects = defaultdict(list)
    for scene in scenes:
        pbr_count = 0
        for obj in scene.objects:
            if obj.type == "MESH" and any(m and m.get("l6_surface_id") for m in obj.data.materials):
                pbr_count += 1
                relevant_objects[obj.name].append(scene.name)
        scene_summary[scene.name] = {"objectCount": len(scene.objects), "pbrMeshCount": pbr_count}
    if len(scenes) != 10:
        error("REVISION_SCENES_MISSING", {"found": [s.name for s in scenes]})
    uv_rows = []
    for name, scene_names in relevant_objects.items():
        obj = bpy.data.objects[name]
        row = validate_uv_object(obj, scene_names)
        if row:
            uv_rows.append(row)

    # Append the pristine source datablocks into memory only. Keep references
    # returned by the library loader so Blender's name suffixes do not matter.
    revised_geometry = {o.name: vertex_hash(o) for o in bpy.data.objects if o.type == "MESH"}
    with bpy.data.libraries.load(str(SOURCE), link=False) as (library, loaded):
        source_names = list(library.objects)
        loaded.objects = source_names.copy()
    original_geometry = {name: vertex_hash(obj) for name, obj in zip(source_names, loaded.objects)
                         if obj is not None and obj.type == "MESH"}
    missing_original = sorted(name for name in original_geometry if name not in revised_geometry)
    changed_original = sorted(name for name, value in original_geometry.items() if revised_geometry.get(name) not in (None, value))
    if missing_original:
        error("ORIGINAL_MESH_MISSING", missing_original[:20])
    if changed_original:
        error("ORIGINAL_MESH_VERTICES_CHANGED", changed_original[:20])
    original_kits = BUILD_MANIFEST["originalKitCollections"]
    missing_kits = [name for name in original_kits if bpy.data.collections.get(name) is None]
    if missing_kits:
        error("ORIGINAL_KIT_COLLECTION_MISSING", missing_kits)

    # Asset-side checks stay independent of Blender node graph inspection.
    source_copy_checks = {}
    for identifier, archived in (("carpet_default", "party-carpet.png"),
                                 ("carpet_neon", "party-carpet-neon-v1.png"),
                                 ("carpet_red", "party-carpet-red-v1.png"),
                                 ("carpet_city", "city-play-carpet.png"),
                                 ("wallpaper", "pastel-wallpaper.png"),
                                 ("orange_wall", "orange-wall-worn-v1.png")):
        path = TASK / MATERIAL_MANIFEST["materials"][identifier]["sourceColor"]
        archive = ROOT / "artifacts/level6-textures-20260930/reference-textures" / archived
        matches = digest(path.read_bytes()) == digest(archive.read_bytes())
        source_copy_checks[identifier] = matches
        if not matches:
            error("SOURCE_COLOR_COPY_CHANGED", identifier)

    edge_count = sum(row["edgesMeasured"] for row in uv_rows)
    report = {
        "schemaVersion": 1,
        "blend": str(expected_output.relative_to(ROOT)),
        "blendSha256": blend_hash,
        "passed": not issues,
        "issues": issues,
        "materialCount": len(material_rows),
        "surfaceIds": {key: value for key, value in sorted(by_surface.items())},
        "materials": material_rows,
        "normalMapQuantization": normal_quantization,
        "sourceColorCopiesByteIdentical": source_copy_checks,
        "originalMeshes": {"sourceMeshCount": len(original_geometry), "missing": missing_original,
                           "changedVertexPositions": changed_original, "allOriginalKitCollectionsPresent": not missing_kits},
        "scenes": scene_summary,
        "physicalUv": {"scenePbrObjectCount": len(relevant_objects), "validatedObjects": len(uv_rows),
                       "measuredProjectedEdgeComponents": edge_count,
                       "maximumEdgeScaleResidualStuds": max((r["maxEdgeScaleResidualStuds"] for r in uv_rows), default=None),
                       "minimumUv": min((r["uvRange"][0] for r in uv_rows), default=None),
                       "maximumUv": max((r["uvRange"][1] for r in uv_rows), default=None),
                       "largestObjectsByArea": sorted(uv_rows, key=lambda r: max(r["worldDimensions"]), reverse=True)[:12]},
        "limitations": ["Inspection is of the offline Blender file; no live Studio parity, Roblox import, gameplay, or runtime performance claim."],
    }
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".material-validation-", dir=REPORT.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write((json.dumps(report, indent=2) + "\n").encode())
        subprocess.run(["cp", "-f", temporary, str(REPORT)], check=True)
    finally:
        subprocess.run(["rm", "-f", temporary], check=True)
    print("MATERIAL_VALIDATION_RESULT", json.dumps({"passed": report["passed"], "issueCount": len(issues),
                                                     "materialCount": len(material_rows), "uvObjects": len(uv_rows),
                                                     "edgesMeasured": edge_count}), flush=True)
    if issues:
        raise SystemExit(2)


if __name__ == "__main__":
    main()
