"""Read-only geometric audit of the saved Level 6 Blender revision.

Run with Blender --background Level6_Revised_Full_Seed101.blend --python this_file.
The loaded .blend is never saved; only sections-validation.json is written.
"""

from __future__ import annotations

import hashlib
import json
import math
from collections import Counter
from pathlib import Path

import bpy
from mathutils import Matrix, Vector


OUT = Path(__file__).with_name("sections-validation.json")
REVISION = OUT.parents[1]
ROOT = REVISION.parents[1]
BLEND = REVISION / "Level6_Revised_Full_Seed101.blend"
MANIFEST = json.loads((REVISION / "build-manifest.json").read_text())
PLAN = json.loads((ROOT / "artifacts/level6-build-20260930/seed101-layout.json").read_text())["layout"]
SECTIONS = json.loads((REVISION / "sections-spec.json").read_text())
REVISED = bpy.data.scenes["Level 6 | Revised FULL seed 101 | 35 rooms"]
SOURCE = next(s for s in bpy.data.scenes if s.name.startswith("Level 6 | FULL seed 101"))
DEPSGRAPH = bpy.context.evaluated_depsgraph_get()


def round_vec(vector):
    return [round(float(v), 4) for v in vector]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def cast(start, end):
    start, end = Vector(start), Vector(end)
    delta = end - start
    hit, location, normal, face, obj, matrix = REVISED.ray_cast(
        DEPSGRAPH, start, delta.normalized(), distance=delta.length)
    if not hit:
        return {"hit": False}
    return {"hit": True, "xyz": round_vec(location), "object": obj.name,
            "distance": round(float((location-start).length), 4)}


def portal(name, y_start, y_end):
    samples = []
    for x in (234.5, 236, 238, 240, 241.5):
        for z in (1.0, 4.0, 9.5):
            result = cast((x, y_start, z), (x, y_end, z))
            samples.append({"x": x, "z": z, **result})
    blockers = [sample for sample in samples if sample["hit"]]
    return {"name": name, "y_segment": [y_start, y_end],
            "sample_count": len(samples), "clear": not blockers,
            "blockers": blockers}


def bbox(obj):
    points = [object_matrix(obj) @ Vector(v) for v in obj.bound_box]
    return [[round(min(v[i] for v in points), 4) for i in range(3)],
            [round(max(v[i] for v in points), 4) for i in range(3)]]


def object_matrix(obj):
    # matrix_world / matrix_local can be stale for objects in inactive scenes
    # and for freshly copied collection-instance empties.
    return Matrix.LocRotScale(obj.location, obj.rotation_euler.to_quaternion(), obj.scale)


def asset_counts(scene):
    return Counter(obj.instance_collection.name.removeprefix("L6K_")
                   for obj in scene.objects
                   if obj.type == "EMPTY" and obj.instance_collection)


def footprint_xy(objects, *, source_instances):
    bounds = [math.inf, -math.inf, math.inf, -math.inf]
    for obj in objects:
        if source_instances:
            members = ((child, object_matrix(obj) @ object_matrix(child))
                       for child in obj.instance_collection.objects
                       if child.type == "MESH" and not child.get("export_collision_only"))
        else:
            members = ((obj, object_matrix(obj)),)
        for member, matrix in members:
            for corner in member.bound_box:
                point = matrix @ Vector(corner)
                bounds[0] = min(bounds[0], point.x)
                bounds[1] = max(bounds[1], point.x)
                bounds[2] = min(bounds[2], point.y)
                bounds[3] = max(bounds[3], point.y)
    return [round(x, 4) for x in bounds]


def original_floor_preservation():
    room_ids = [room["Id"] for room in PLAN["Rooms"]]
    link_ids = [link["Id"] for link in PLAN["Links"]]
    source_names = {obj.name for obj in SOURCE.objects}
    architecture = REVISED.collection.children[
        REVISED.name + " | architecture"]
    revised_names = {obj.name for obj in architecture.objects}
    rooms = {
        name: {"source_floor": any(x.startswith(name + " | floor")
                                   for x in source_names),
               "revised_floor": any(x.startswith(name + " | floor /")
                                    for x in revised_names)}
        for name in room_ids
    }
    links = {
        name: {"source_corridor_floor": any(x.startswith(name + " | corridor floor")
                                            for x in source_names),
               "revised_corridor_floor": any(x.startswith(name + " | corridor floor /")
                                             for x in revised_names)}
        for name in link_ids
    }
    # Compare the union of each source collection-instance floor footprint to
    # its placed/UV-bisected revised mesh footprint, including every corridor
    # segment when one logical link spans multiple floor instances.
    footprint_mismatches = []
    for label in ([name + " | floor" for name in room_ids] +
                  [name + " | corridor floor" for name in link_ids]):
        before = [obj for obj in SOURCE.objects
                  if obj.name.startswith(label) and obj.instance_collection]
        after = [obj for obj in architecture.objects
                 if obj.name.startswith(label) and obj.type == "MESH"]
        if not before or not after:
            footprint_mismatches.append({"label": label, "reason": "missing source or revised floor"})
            continue
        a = footprint_xy(before, source_instances=True)
        b = footprint_xy(after, source_instances=False)
        if max(abs(x-y) for x, y in zip(a, b)) > .01:
            footprint_mismatches.append({"label": label,
                                         "source_bounds_xy": a,
                                         "revised_bounds_xy": b})
    return {"layout_room_count": len(room_ids), "layout_link_count": len(link_ids),
            "calculated_original_room_floor_area_stud2": sum(r["W"]*r["D"] for r in PLAN["Rooms"]),
            "layout_room_floor_area_stud2": PLAN["RoomFloorArea"],
            "scene_original_floor_area_property": REVISED.get("original_room_floor_area_stud2"),
            "original_room_floors_present": sum(all(v.values()) for v in rooms.values()),
            "original_link_floors_present": sum(all(v.values()) for v in links.values()),
            "floor_footprints_compared": len(room_ids)+len(link_ids),
            "floor_footprint_mismatches": footprint_mismatches,
            "missing_room_floors": [name for name, flags in rooms.items() if not all(flags.values())],
            "missing_link_floors": [name for name, flags in links.items() if not all(flags.values())]}


def join_anchors():
    placements = {row["asset"]: row for row in MANIFEST["newRoomPlacements"]}
    pairs = [
        ("RoomKitchenPrep", "JoinSouth", [238, 128, 0]),
        ("RoomKitchenPrep", "JoinNorth", [238, 152, 0]),
        ("RoomStaffNook", "JoinSouth", [238, 152, 0]),
        ("RoomStaffNook", "JoinNorth", [238, 176, 0]),
        ("RoomUtilityHall", "JoinSouth", [238, -716, 0]),
        ("RoomUtilityHall", "JoinNorth", [238, -740, 0]),
    ]
    records = []
    for asset, label, expected in pairs:
        row = placements[asset]
        collection = bpy.data.collections["L6K_" + asset]
        anchor = next(obj for obj in collection.objects if obj.get("l6_anchor") == label)
        matrix = Matrix.Translation(Vector(row["xyz"])) @ Matrix.Rotation(row["angle"], 4, "Z")
        actual = matrix @ anchor.location
        records.append({"asset": asset, "anchor": label, "actual_xyz": round_vec(actual),
                        "expected_xyz": expected, "aligned": (actual-Vector(expected)).length < 1e-4,
                        "port_width": anchor.get("l6_port_width"),
                        "port_height": anchor.get("l6_port_height")})
    return {"all_aligned": all(item["aligned"] for item in records), "anchors": records}


def room_lanes():
    records = {}
    for asset in ("RoomKitchenPrep", "RoomUtilityHall", "RoomStaffNook"):
        col = bpy.data.collections["L6K_" + asset]
        proxies = [obj for obj in col.objects if obj.get("export_collision_only")]
        blockers = []
        for obj in proxies:
            center = obj["center_xyz"]
            size = obj["dimensions_xyz"]
            # A proxy merely touching the floor or the lane edge is clear.
            if (center[0]-size[0]/2 < 3 and center[0]+size[0]/2 > -3
                    and center[2]-size[2]/2 < 6 and center[2]+size[2]/2 > 0):
                blockers.append({"name": obj.name, "center_xyz": list(center),
                                 "size_xyz": list(size)})
        records[asset] = {"collision_proxy_count": len(proxies),
                          "clear_six_stud_center_lane": not blockers,
                          "blockers": blockers}
    return records


def actual_room_interior_rays():
    # These start and end inside each shell, so the intentional far end caps
    # and doorway lintels do not count as route obstructions.
    segments = {
        "RoomKitchenPrep": ((238, 131, 0), (238, 149, 0)),
        "RoomStaffNook": ((238, 155, 0), (238, 173, 0)),
        "RoomUtilityHall": ((238, -719, 0), (238, -737, 0)),
    }
    rows = {}
    for asset, (start, end) in segments.items():
        samples = []
        for dx in (-3, -2.4, -1.8, -1.2, -.6, 0, .6, 1.2, 1.8, 2.4, 3):
            for z in (.9, 2.1, 3.3, 4.5, 5.7):
                result = cast((start[0]+dx, start[1], z),
                              (end[0]+dx, end[1], z))
                if result["hit"]:
                    samples.append({"lane_x_offset": dx, "z": z, **result})
        rows[asset] = {"sample_count": 55, "clear": not samples,
                       "blockers": samples}
    return rows


def furnishing_world_bounds():
    architecture = REVISED.collection.children[REVISED.name + " | architecture"]
    placements = {row["asset"]: row for row in MANIFEST["newRoomPlacements"]}
    rows = {}
    for room, info in SECTIONS["rooms"].items():
        row = placements[room]
        room_matrix = Matrix.Translation(Vector(row["xyz"])) @ Matrix.Rotation(row["angle"], 4, "Z")
        fixtures = []
        room_col = bpy.data.collections["L6K_" + room]
        for asset, local_xyz, local_angle_degrees in info["fixture_instances"]:
            instance = next(obj for obj in room_col.objects
                            if obj.get("l6_child_asset") == asset and
                            (obj.location-Vector(local_xyz)).length < 1e-4)
            prefab = bpy.data.collections["L6K_" + asset]
            expected_points = []
            for source_obj in prefab.objects:
                if source_obj.type != "MESH" or source_obj.get("export_collision_only"):
                    continue
                matrix = room_matrix @ object_matrix(instance) @ object_matrix(source_obj)
                expected_points += [matrix @ Vector(v) for v in source_obj.bound_box]
            actual = [obj for obj in architecture.objects
                      if obj.name.startswith(room + " /") and obj.get("l6_asset") == asset]
            actual_points = [object_matrix(obj) @ Vector(v)
                             for obj in actual for v in obj.bound_box]
            if expected_points and actual_points:
                expected_bounds = [[min(v[i] for v in expected_points) for i in range(3)],
                                   [max(v[i] for v in expected_points) for i in range(3)]]
                actual_bounds = [[min(v[i] for v in actual_points) for i in range(3)],
                                 [max(v[i] for v in actual_points) for i in range(3)]]
                max_error = max(abs(a-b) for aa, bb in zip(expected_bounds, actual_bounds)
                                for a, b in zip(aa, bb))
            else:
                expected_bounds = actual_bounds = None
                max_error = None
            fixtures.append({"asset": asset, "expected_bounds_xyz": expected_bounds,
                             "actual_bounds_xyz": actual_bounds,
                             "actual_mesh_objects": len(actual),
                             "max_axis_error_studs": max_error,
                             "placed_correctly": max_error is not None and max_error < .02})
        rows[room] = {"fixtures": fixtures,
                      "all_placed_correctly": all(x["placed_correctly"] for x in fixtures)}
    return rows


def main():
    assert Path(bpy.data.filepath).resolve() == BLEND.resolve(), bpy.data.filepath
    cd_source = asset_counts(SOURCE)
    cd_revised = asset_counts(REVISED)
    cd = {name: {"source": cd_source[name], "revised": cd_revised[name],
                 "preserved": cd_source[name] == cd_revised[name]}
          for name in ("CD", "CDCase", "CDPlayer")}
    portals = [
        portal("CityR02 north to kitchen", 125, 131),
        portal("Kitchen to staff nook", 149, 155),
        portal("RedR07 south to utility", -713, -719),
    ]
    caps = [
        {"name": "Staff nook outer end cap", "expected_y": 176,
         "samples": [cast((x, 173, z), (x, 179, z))
                     for x in (235, 238, 241) for z in (1, 5, 10)]},
        {"name": "Utility outer end cap", "expected_y": -740,
         "samples": [cast((x, -737, z), (x, -743, z))
                     for x in (235, 238, 241) for z in (1, 5, 10)]},
    ]
    for cap in caps:
        obj = REVISED.objects.get(cap["name"])
        cap["object_present"] = obj is not None
        cap["bounds_xyz"] = bbox(obj) if obj else None
        cap["blocks_all_samples"] = all(sample["hit"] and
                                         sample["object"] == cap["name"]
                                         for sample in cap["samples"])
    ceilings = {}
    for name, y in (("RoomKitchenPrep", 140), ("RoomStaffNook", 164),
                    ("RoomUtilityHall", -728)):
        samples = [cast((x, y, 10.8), (x, y, 12.5)) for x in (235, 238, 241)]
        ceilings[name] = {"samples": samples,
                          "covered": all(s["hit"] and s["object"].startswith(name)
                                         for s in samples)}
    floors = original_floor_preservation()
    lanes = room_lanes()
    actual_lanes = actual_room_interior_rays()
    fixtures = furnishing_world_bounds()
    anchors = join_anchors()
    result = {
        "schema": "level6-sections-validation/1",
        "source_blend": str(BLEND.relative_to(ROOT)),
        "source_blend_sha256": sha(BLEND),
        "manifest_sha256_matches": sha(BLEND) == MANIFEST["outputSha256"],
        "scope": "Read-only Blender geometry/instance audit; no Roblox gameplay or Studio validation",
        "original_layout_preservation": floors,
        "cd_and_player_instances": cd,
        "join_anchors": anchors,
        "doorway_raycast_samples": portals,
        "room_collision_lanes": lanes,
        "actual_geometry_center_lane_rays": actual_lanes,
        "furnishing_world_bounds": fixtures,
        "outer_caps": caps,
        "ceilings": ceilings,
    }
    result["passed"] = all((
        result["manifest_sha256_matches"],
        floors["layout_room_count"] == 32,
        floors["layout_link_count"] == 37,
        floors["calculated_original_room_floor_area_stud2"] == 189656,
        floors["original_room_floors_present"] == 32,
        floors["original_link_floors_present"] == 37,
        not floors["floor_footprint_mismatches"],
        all(item["preserved"] for item in cd.values()),
        anchors["all_aligned"],
        all(item["clear"] for item in portals),
        all(item["clear_six_stud_center_lane"] for item in lanes.values()),
        all(item["clear"] for item in actual_lanes.values()),
        all(item["all_placed_correctly"] for item in fixtures.values()),
        all(item["blocks_all_samples"] for item in caps),
        all(item["covered"] for item in ceilings.values()),
    ))
    OUT.write_text(json.dumps(result, indent=2) + "\n")
    print("L6_SECTION_VALIDATION", json.dumps({
        "passed": result["passed"],
        "portals_clear": [p["clear"] for p in portals],
        "center_lanes_clear": [v["clear_six_stud_center_lane"] for v in lanes.values()],
        "actual_lanes_clear": [v["clear"] for v in actual_lanes.values()],
        "furnishings_placed": [v["all_placed_correctly"] for v in fixtures.values()],
        "caps_block": [c["blocks_all_samples"] for c in caps],
        "ceilings_cover": [c["covered"] for c in ceilings.values()],
        "cd": cd,
        "floors": {"rooms": floors["original_room_floors_present"],
                    "links": floors["original_link_floors_present"]},
    }), flush=True)


if __name__ == "__main__":
    main()
