"""Read-only source / GLB checks, run in a separate Blender background process.

blender -b assets/maps/vesper-cathedral/VesperCathedral.blend \
  --python tools/verify_cathedral_export.py

Only verification.json is written. Blender imports GLB into temporary process
memory; the .blend and interchange assets are never saved or modified.
"""

import bpy
import bmesh
import hashlib
import json
import math
from pathlib import Path
from mathutils import Matrix, Vector


ROOT = Path(__file__).resolve().parents[1] / "assets/maps/vesper-cathedral"
TRIANGLE_LIMIT = 20000
AREA_EPSILON = 1e-9
POSITION_TOLERANCE = 1e-4


def finite(sequence):
    return all(math.isfinite(float(v)) for v in sequence)


def mesh_report(obj, source_topology=True):
    mesh = obj.data
    mesh.calc_loop_triangles()
    world = obj.matrix_world
    points = [world @ vertex.co for vertex in mesh.vertices]
    low = [min(p[i] for p in points) for i in range(3)] if points else [0, 0, 0]
    high = [max(p[i] for p in points) for i in range(3)] if points else [0, 0, 0]
    triangles = list(mesh.loop_triangles)
    zero_areas = []
    total_area = 0.0
    signed_volume = 0.0
    geometry_fingerprints = []
    for triangle in triangles:
        a, b, c = [points[index] for index in triangle.vertices]
        area = (b - a).cross(c - a).length * 0.5
        total_area += area
        signed_volume += a.dot(b.cross(c)) / 6.0
        if not math.isfinite(area) or area <= AREA_EPSILON:
            zero_areas.append(triangle.index)
        coordinates = [tuple(round(float(value), 4) or 0.0 for value in point) for point in (a, b, c)]
        geometry_fingerprints.append(tuple(sorted(coordinates)))
    triangle_fingerprint = hashlib.sha256(repr(sorted(geometry_fingerprints)).encode()).hexdigest()
    uv = mesh.uv_layers.active
    nonfinite_uv = []
    uv_outside = []
    uv_atlas_padding = []
    if uv:
        for loop in mesh.loops:
            coords = uv.data[loop.index].uv
            if not finite(coords):
                nonfinite_uv.append(loop.index)
            elif not all(0 <= value <= 1 for value in coords):
                uv_outside.append(loop.index)
            elif not all(12 / 256 - 1e-6 <= (float(value) * 4) % 1 <= 244 / 256 + 1e-6 for value in coords):
                uv_atlas_padding.append(loop.index)
    transform_delta = max(abs(world[row][col] - (1 if row == col else 0)) for row in range(4) for col in range(4))
    result = {
        "name": obj.name,
        "vertices": len(mesh.vertices),
        "triangles": len(triangles),
        "triangle_limit": TRIANGLE_LIMIT,
        "under_triangle_limit": len(triangles) < TRIANGLE_LIMIT,
        "material_slots": len(mesh.materials),
        "materials": [material.name if material else None for material in mesh.materials],
        "finite_vertex_coordinates": all(finite(point) for point in points),
        "has_uv_map": uv is not None,
        "nonfinite_uv_count": len(nonfinite_uv),
        "uv_outside_image_count": len(uv_outside),
        "uv_in_atlas_padding_count": len(uv_atlas_padding),
        "identity_world_transform": transform_delta < 1e-6,
        "maximum_transform_delta": transform_delta,
        "zero_area_triangle_count": len(zero_areas),
        "zero_area_triangle_indices": zero_areas[:20],
        "surface_area": total_area,
        "signed_volume": signed_volume,
        "bounds_blender": {"min": low, "max": high},
        "geometry_fingerprint_round_4dp": triangle_fingerprint,
    }
    if source_topology:
        bm = bmesh.new()
        bm.from_mesh(mesh)
        bm.faces.ensure_lookup_table()
        bm.verts.ensure_lookup_table()
        boundary = sum(edge.is_boundary for edge in bm.edges)
        nonmanifold = sum(not edge.is_manifold for edge in bm.edges)
        inconsistent_winding = sum(edge.is_manifold and not edge.is_contiguous for edge in bm.edges)
        unseen = set(bm.faces)
        component_count = 0
        inward = []
        zero_volume = []
        while unseen:
            seed = unseen.pop()
            stack, faces = [seed], [seed]
            while stack:
                face = stack.pop()
                for edge in face.edges:
                    for neighbor in edge.link_faces:
                        if neighbor in unseen:
                            unseen.remove(neighbor)
                            stack.append(neighbor)
                            faces.append(neighbor)
            component_count += 1
            # Local origin avoids cancellation for small ornaments far from world origin.
            origin = faces[0].verts[0].co
            volume = 0.0
            for face in faces:
                a = face.verts[0].co - origin
                for i in range(1, len(face.verts) - 1):
                    b = face.verts[i].co - origin
                    c = face.verts[i + 1].co - origin
                    volume += a.dot(b.cross(c)) / 6.0
            closed = all(edge.is_manifold for face in faces for edge in face.edges)
            if closed and volume < -1e-9:
                inward.append({"component": component_count, "signed_volume": volume})
            if closed and abs(volume) <= 1e-9:
                zero_volume.append({"component": component_count, "signed_volume": volume})
        result["topology"] = {
            "boundary_edges": boundary,
            "nonmanifold_edges_including_boundary": nonmanifold,
            "inconsistent_winding_edges": inconsistent_winding,
            "connected_surface_components": component_count,
            "inward_closed_components": inward,
            "zero_volume_closed_components": zero_volume,
            "disconnected_components_allowed": True,
        }
        bm.free()
    errors = []
    for condition, label in [
        (result["under_triangle_limit"], "mesh triangle budget exceeded"),
        (result["material_slots"] == 1, "expected one material slot"),
        (result["finite_vertex_coordinates"], "nonfinite vertex coordinate"),
        (result["has_uv_map"], "missing UV map"),
        (not result["nonfinite_uv_count"], "nonfinite UV"),
        (not result["uv_outside_image_count"], "UV outside atlas image"),
        (result["identity_world_transform"], "nonidentity object transform"),
        (not result["zero_area_triangle_count"], "zero-area triangle"),
    ]:
        if not condition:
            errors.append(label)
    if source_topology:
        topo = result["topology"]
        for key in ("boundary_edges", "nonmanifold_edges_including_boundary", "inconsistent_winding_edges", "inward_closed_components", "zero_volume_closed_components"):
            if topo[key]:
                errors.append(key)
    result["errors"] = errors
    result["warnings"] = ["UVs touch texture-atlas padding"] if uv_atlas_padding else []
    return result


def combine_bounds(reports):
    return {
        "min": [min(report["bounds_blender"]["min"][axis] for report in reports) for axis in range(3)],
        "max": [max(report["bounds_blender"]["max"][axis] for report in reports) for axis in range(3)],
    }


def compare_roundtrip(source_by_name, imported_reports, path):
    imported_by_name = {item["name"]: item for item in imported_reports}
    comparisons = []
    for name in sorted(set(source_by_name) | set(imported_by_name)):
        original, new = source_by_name.get(name), imported_by_name.get(name)
        if original is None or new is None:
            comparisons.append({"name": name, "pass": False, "reason": "mesh missing from source or interchange file"})
            continue
        max_bound_delta = max(abs(original["bounds_blender"][key][axis] - new["bounds_blender"][key][axis]) for key in ("min", "max") for axis in range(3))
        area_delta = abs(original["surface_area"] - new["surface_area"])
        area_tolerance = max(0.0001, original["surface_area"] * 1e-6)
        # FBX's importer can represent its axis conversion in object transforms.
        # Evaluate geometry in world space, and report that transform explicitly.
        significant_errors = [error for error in new["errors"] if error != "nonidentity object transform" or path.suffix != ".fbx"]
        passed = original["triangles"] == new["triangles"] and max_bound_delta < POSITION_TOLERANCE and area_delta < area_tolerance and not significant_errors
        comparisons.append({
            "name": name, "pass": passed,
            "triangles_equal": original["triangles"] == new["triangles"],
            "maximum_bounds_delta": max_bound_delta,
            "surface_area_delta": area_delta,
            "surface_area_tolerance": area_tolerance,
            "triangle_fingerprint_equal": original["geometry_fingerprint_round_4dp"] == new["geometry_fingerprint_round_4dp"],
            "import_identity_world_transform": new["identity_world_transform"],
            "import_errors": significant_errors,
        })
    return {
        "status": "pass" if all(item["pass"] for item in comparisons) else "fail",
        "file": path.name,
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "mesh_count": len(imported_reports),
        "triangles": sum(item["triangles"] for item in imported_reports),
        "bounds_blender": combine_bounds(imported_reports),
        "note": "Interchange files may split UV/normal seams into new vertices; source topology is checked before export. Roundtrip compares names, triangle counts, world bounds, areas, finite coordinates/UVs, material slots, transforms and nonzero triangle areas. FBX axis-conversion transforms are allowed when world geometry matches.",
        "mesh_comparisons": comparisons,
    }


def run():
    source_path = Path(bpy.data.filepath)
    scene = bpy.data.scenes.get("Vesper Cathedral")
    if scene is None:
        raise RuntimeError("Expected Vesper Cathedral scene in supplied .blend")
    source_meshes = sorted([obj for obj in scene.objects if obj.type == "MESH"], key=lambda obj: obj.name)
    reports = [mesh_report(obj) for obj in source_meshes]
    report = {
        "asset": "Vesper Cathedral",
        "verification_scope": "Offline Blender source mesh checks and optional GLB / FBX import roundtrip; no Roblox Studio execution",
        "source_file": source_path.name,
        "source_sha256": hashlib.sha256(source_path.read_bytes()).hexdigest(),
        "blender_version": bpy.app.version_string,
        "mesh_count": len(reports),
        "triangles": sum(item["triangles"] for item in reports),
        "max_mesh_triangles": max(item["triangles"] for item in reports),
        "bounds_blender": combine_bounds(reports),
        "source_geometry_pass": all(not item["errors"] for item in reports),
        "source_meshes": reports,
        "studio_import": "unverified",
        "roblox_avatar_walkthrough": "unverified",
        "runtime_performance": "unverified",
        "glb_roundtrip": {"status": "pending", "reason": "VesperCathedral.glb not present at verification time"},
        "fbx_roundtrip": {"status": "pending", "reason": "VesperCathedral.fbx not present at verification time"},
    }
    source_by_name = {item["name"]: item for item in reports}
    for file_type in ("glb", "fbx"):
        path = ROOT / ("VesperCathedral." + file_type)
        if not path.is_file():
            continue
        # This process is disposable. Factory reset prevents name suffixes on import.
        bpy.ops.wm.read_factory_settings(use_empty=True)
        if file_type == "glb":
            bpy.ops.import_scene.gltf(filepath=str(path))
        else:
            bpy.ops.import_scene.fbx(filepath=str(path))
        imported = sorted([obj for obj in bpy.context.scene.objects if obj.type == "MESH"], key=lambda obj: obj.name)
        imported_reports = [mesh_report(obj, source_topology=False) for obj in imported]
        report[file_type + "_roundtrip"] = compare_roundtrip(source_by_name, imported_reports, path)
    report["overall_offline_pass"] = report["source_geometry_pass"] and report["glb_roundtrip"]["status"] == "pass" and report["fbx_roundtrip"]["status"] == "pass"
    (ROOT / "verification.json").write_text(json.dumps(report, indent=2) + "\n")
    print("VESPER_VERIFICATION " + json.dumps({
        "source_geometry_pass": report["source_geometry_pass"],
        "mesh_count": report["mesh_count"], "triangles": report["triangles"],
        "source_errors": [{"name": item["name"], "errors": item["errors"]} for item in reports if item["errors"]],
        "source_warnings": [{"name": item["name"], "warnings": item["warnings"]} for item in reports if item["warnings"]],
        "glb_roundtrip_status": report["glb_roundtrip"]["status"],
        "fbx_roundtrip_status": report["fbx_roundtrip"]["status"],
        "overall_offline_pass": report["overall_offline_pass"],
    }))


run()
