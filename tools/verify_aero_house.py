"""Read-only geometry/GLB and analytic collision checks in disposable Blender.

Usage: blender -b assets/models/aero-house/AeroHouse.blend --python
tools/verify_aero_house.py [-- --report /tmp/aero-verification.json]

Only the named JSON report is written. The .blend and export files are untouched.
Analytic paths are not a Roblox Humanoid walkthrough or performance benchmark.
"""
import argparse
import hashlib
import json
import math
import sys
from pathlib import Path

import bmesh
import bpy

ROOT = Path(__file__).resolve().parents[1] / "assets/models/aero-house"
EPS = 1e-9


def finite(v):
    return all(math.isfinite(float(x)) for x in v)


def mesh_report(obj, topology):
    mesh = obj.data
    mesh.calc_loop_triangles()
    vertices = [obj.matrix_world @ v.co for v in mesh.vertices]
    errors = []
    areas = [(vertices[t.vertices[1]] - vertices[t.vertices[0]]).cross(
        vertices[t.vertices[2]] - vertices[t.vertices[0]]).length * .5
        for t in mesh.loop_triangles]
    uv = mesh.uv_layers.active
    uv_invalid = sum(not finite(x.uv) or any(v < -1e-6 or v > 1+1e-6 for v in x.uv)
                     for x in uv.data) if uv else 0
    uv_zero = 0
    if uv:
        for tri in mesh.loop_triangles:
            a, b, c = [uv.data[i].uv for i in tri.loops]
            uv_zero += abs((b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x)) < 1e-12
    normals_bad = sum(not finite(p.normal) or abs(p.normal.length-1) > 1e-4 for p in mesh.polygons)
    result = {"name": obj.name, "vertices": len(vertices), "triangles": len(areas),
              "material_slots": len(mesh.materials), "uv_layers": len(mesh.uv_layers),
              "invalid_uv_loops": uv_invalid, "zero_area_uv_triangles": uv_zero,
              "invalid_normals": normals_bad, "zero_area_triangles": sum(a <= EPS for a in areas),
              "surface_area": sum(areas), "bounds_blender": {
                  "min": [min(v[i] for v in vertices) for i in range(3)],
                  "max": [max(v[i] for v in vertices) for i in range(3)]}}
    for fail, label in [(len(areas) > 20000, "over 20000 triangles"),
                        (len(mesh.materials) != 1, "material count is not one"),
                        (not all(finite(v) for v in vertices), "nonfinite vertex"),
                        (len(mesh.uv_layers) != 1, "UV layer count is not one"),
                        (uv_invalid > 0, "UV outside 0..1 or nonfinite"),
                        (uv_zero > 0, "zero-area UV triangles"),
                        (normals_bad > 0, "invalid normal"),
                        (any(not math.isfinite(a) or a <= EPS for a in areas), "zero-area triangle")]:
        if fail: errors.append(label)
    if topology:
        bm = bmesh.new()
        bm.from_mesh(mesh)
        nonmanifold = sum(not e.is_manifold for e in bm.edges)
        inconsistent = sum(e.is_manifold and not e.is_contiguous for e in bm.edges)
        unseen, components, inward, zero_volume = set(bm.faces), 0, 0, 0
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
            components += 1
            origin = faces[0].verts[0].co
            volume = 0
            for f in faces:
                a = f.verts[0].co-origin
                for i in range(1, len(f.verts)-1):
                    b, c = f.verts[i].co-origin, f.verts[i+1].co-origin
                    volume += a.dot(b.cross(c))/6
            if all(e.is_manifold for f in faces for e in f.edges):
                inward += volume < -EPS
                zero_volume += abs(volume) <= EPS
        result["topology"] = {"components": components, "nonmanifold_edges": nonmanifold,
                              "inconsistent_winding_edges": inconsistent,
                              "inward_components": inward, "zero_volume_components": zero_volume}
        if any((nonmanifold, inconsistent, inward, zero_volume)):
            errors.append("source topology or winding problem")
        bm.free()
    result["errors"] = errors
    return result


def combined_bounds(reports):
    return {key: [op(r["bounds_blender"][key][i] for r in reports) for i in range(3)]
            for key, op in (("min", min), ("max", max))}


def analytic_collision_checks(manifest):
    """Probe authored OBBs in Blender coordinates; yaw conversion is +Y -> +Z."""
    boxes = []
    for c in manifest["colliders"]:
        px, pz, ny = c["position"]
        sx, sz, sy = c["size"]
        theta = math.radians(c.get("rotation", [0, 0, 0])[1])
        boxes.append((c["name"], px, -ny, pz, sx/2, sy/2, sz/2, theta))

    def proximity(box, x, y, radius=0):
        _, cx, cy, cz, hx, hy, hz, theta = box
        dx, dy = x-cx, y-cy
        u = math.cos(theta)*dx+math.sin(theta)*dy
        v = -math.sin(theta)*dx+math.cos(theta)*dy
        return max(abs(u)-hx, 0)**2 + max(abs(v)-hy, 0)**2 <= radius**2+1e-9

    def probe(x, y, expected):
        surfaces = [(b[3]+b[6], b[0]) for b in boxes
                    if proximity(b, x, y) and b[3]+b[6] <= expected+.55]
        floor, support = max(surfaces, default=(-999, "none"))
        blockers = [b[0] for b in boxes if proximity(b, x, y, .75)
                    and b[3]+b[6] > floor+.60 and b[3]-b[6] < floor+5.5]
        return {"position_blender": [round(x, 4), round(y, 4), round(expected, 4)],
                "actual_floor": floor, "support": support, "blockers": blockers,
                "pass": abs(floor-expected) <= .56 and not blockers}

    routes = {}
    def route(name, points):
        checks = []
        for a, b in zip(points, points[1:]):
            length = math.sqrt(sum((b[i]-a[i])**2 for i in range(3)))
            count = max(1, math.ceil(length/.3))
            for j in range(count):
                t = j/count
                checks.append(probe(*[a[i]*(1-t)+b[i]*t for i in range(3)]))
        checks.append(probe(*points[-1]))
        routes[name] = {"samples": len(checks), "pass": all(c["pass"] for c in checks),
                        "failures": [c for c in checks if not c["pass"]][:30]}

    stair = []
    for j in range(131):
        y = -16 + (j+.01)/131*21
        stair.append((6.5, y, 1+.5*min(13, math.ceil((y+16)/21*13))))
    for j in range(161):
        theta = (j+.01)/161*math.pi
        stair.append((1+5.5*math.cos(theta), 5+5.5*math.sin(theta),
                      7.5+.5*min(8, math.ceil(theta/math.pi*8))))
    for j in range(131):
        y = 5-(j+.01)/131*14
        stair.append((-4.5, y, 11.5+.5*min(13, math.ceil((5-y)/14*13))))
    checks = [probe(*p) for p in stair]
    routes["stair_centerline"] = {"samples": len(checks), "pass": all(c["pass"] for c in checks),
                                 "failures": [c for c in checks if not c["pass"]][:40]}
    route("entry_steps", [(0,-48,.18),(0,-46,.18),(0,-45.6,.36),(0,-44.7,.82),(0,-43,1),(0,-40,1)])
    route("ground_entry_and_lounge", [(0,-40,1),(0,-30,1),(-12,-30,1),(-29,-30,1)])
    route("ground_guest_room", [(-12,-30,1),(-12,12,1),(-29,12,1),(-29,20,1)])
    route("ground_bathroom", [(0,15,1),(0,24,1),(0,27,1)])
    route("ground_study", [(15,12,1),(29,12,1),(29,20,1)])
    route("upper_terrace", [(-4.5,-10,18),(0,-30,18),(28.5,-34,18),(28.5,-48,18)])
    route("upper_reading_and_lime_bedroom", [(20,-34,18),(20,-5,18),(29,-5,18),(29,24,18)])
    route("upper_cyan_bedroom", [(29,8,18),(18,8,18),(18,19.25,18),(-29,19.25,18),(-29,24,18)])
    route("upper_front_window_floor", [(-4,-41.5,18),(10,-41.5,18),(20,-41.5,18)])
    route("upper_rear_window_floor", [(20,41,18),(39,41,18)])
    return {"scope": "Analytic static OBB probes with 0.75-stud horizontal radius and 5.5-stud height; not a Humanoid simulation.",
            "routes": routes, "pass": all(r["pass"] for r in routes.values()),
            "duplicate_collider_names": len(boxes)-len(set(b[0] for b in boxes))}


def run():
    args = argparse.ArgumentParser()
    args.add_argument("--report", type=Path, default=ROOT/"verification.json")
    options = args.parse_args(sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else [])
    source_path = Path(bpy.data.filepath)
    manifest = json.loads((ROOT/"manifest.json").read_text())
    collection = bpy.data.collections["AERO | Import Geometry"]
    reports = [mesh_report(o, True) for o in sorted(collection.objects, key=lambda o:o.name) if o.type == "MESH"]
    bounds = combined_bounds(reports)
    size = [bounds["max"][i]-bounds["min"][i] for i in range(3)]
    expected = manifest["expectedBoundsRoblox"]["size"]
    dimension_delta = max(abs(a-b) for a,b in zip([size[0],size[2],size[1]], expected))
    result = {"asset": "Aero House", "scope": "Offline geometry and analytic collision only",
              "source_sha256": hashlib.sha256(source_path.read_bytes()).hexdigest(),
              "blender_version": bpy.app.version_string, "meshes": len(reports),
              "triangles": sum(r["triangles"] for r in reports),
              "maximum_mesh_triangles": max(r["triangles"] for r in reports),
              "bounds_blender": bounds, "size_roblox": [size[0],size[2],size[1]],
              "expected_dimension_delta": dimension_delta,
              "source_geometry_pass": all(not r["errors"] for r in reports) and dimension_delta < 1e-4,
              "source_meshes": reports, "analytic_collisions": analytic_collision_checks(manifest),
              "studio_import": "unverified", "roblox_walkthrough": "unverified", "runtime_performance": "unverified"}
    original = {r["name"]:r for r in reports}
    bpy.ops.wm.read_factory_settings(use_empty=True)
    path = ROOT/"AeroHouse.glb"
    bpy.ops.import_scene.gltf(filepath=str(path))
    imported = {o.name:mesh_report(o, False) for o in bpy.context.scene.objects if o.type == "MESH"}
    comparisons = []
    for name in sorted(set(original)|set(imported)):
        a, b = original.get(name), imported.get(name)
        if not a or not b:
            comparisons.append({"name":name,"pass":False,"error":"missing mesh"})
            continue
        delta = max(abs(a["bounds_blender"][key][i]-b["bounds_blender"][key][i]) for key in ("min","max") for i in range(3))
        area_delta = abs(a["surface_area"]-b["surface_area"])
        passed = a["triangles"] == b["triangles"] and delta < 1e-4 and area_delta < max(1e-4, a["surface_area"]*1e-6) and not b["errors"]
        comparisons.append({"name": name, "pass": passed, "triangles_equal":a["triangles"]==b["triangles"],
                            "bounds_delta": delta, "surface_area_delta": area_delta, "import_errors": b["errors"]})
    result["glb_roundtrip"] = {"pass": all(c["pass"] for c in comparisons),
                               "sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "meshes": comparisons}
    result["overall_offline_pass"] = result["source_geometry_pass"] and result["glb_roundtrip"]["pass"] and result["analytic_collisions"]["pass"]
    options.report.write_text(json.dumps(result, indent=2)+"\n")
    print("AERO_VERIFICATION "+json.dumps({"report":str(options.report),
          "geometry_pass":result["source_geometry_pass"], "roundtrip_pass":result["glb_roundtrip"]["pass"],
          "analytic_collisions_pass":result["analytic_collisions"]["pass"],
          "source_errors":[{"name":r["name"],"errors":r["errors"]} for r in reports if r["errors"]],
          "failed_routes":[name for name,r in result["analytic_collisions"]["routes"].items() if not r["pass"]]}),flush=True)


if __name__ == "__main__":
    run()
