"""Level 4 round: room-bounded light zones and a clearance-tested Usher graph.

Run after round_assets and ceilings.final_lighting_pass, through v3/blrun.py.
All geometry is read from the current scene; only our invisible marker collection
is rebuilt. No new lights and no master saves. Graph positions use layout +6000 X.
"""
import collections
import importlib.util
import json
import math
import os
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector

HERE = Path(r"G:\Roblox\MongoTV\tools\level4_blender")
OUT = Path(os.environ.get("L4_NAV_OUT", r"G:\Roblox\_local\l4facelift\v5\assets\nav"))
MODULE = Path(r"G:\Roblox\MongoTV\ServerScriptService\Level 4 Systems\Level 4 Usher Nav.ModuleScript.lua")
RADIUS, HEIGHT, STEP, SPACING = 1.25, 7.6, 2.5, 8.0
ROOM_COUNTS = {**{f"A{i}": 3 for i in range(1, 4)}, **{f"C{i}": 2 for i in range(2, 5)},
               "Gallery": 4, "Core": 2, "LobbyWest": 2, "LobbyCenter": 1, "LobbyEast": 2,
               "Service": 2, "Concession": 2, "Arcade": 2, "RestroomVestibule": 1,
               "RestroomMen": 1, "RestroomWomen": 1, **{f"Booth{i}": 1 for i in range(1, 4)}}


def room(p):
    x, y, z = p
    if 22647 <= x <= 22676 and 2 <= z <= 100:
        return "Core"
    if y >= 81:
        for i, cx in enumerate((22766, 23000, 23234), 1):
            if y <= 99 and abs(x - cx) <= 19 and -35 <= z <= -16:
                return f"Booth{i}"
        if y <= 100 and -20 <= z <= 15:
            return "Gallery"
    if 22647 <= x <= 22676 and 0 <= z <= 100:
        return "Core"
    if z < -20:
        for i, (lo, hi) in enumerate(((22677, 22856), (22910, 23090), (23144, 23324)), 1):
            if lo <= x <= hi:
                return f"A{i}"
        for i, (lo, hi) in zip((2, 3, 4), ((22856, 22910), (23090, 23144), (23324, 23378))):
            if lo <= x <= hi:
                return f"C{i}"
    if z >= 100.5:
        if x < 22879.5:
            return "Service"
        if x < 23120.5:
            return "Concession"
        if x < 23261:
            return "Arcade"
        if z < 125:
            return "RestroomVestibule"
        return "RestroomMen" if x < 23307 else "RestroomWomen"
    if x < 22936 or (z < 42 and x < 23000):
        return "LobbyWest"
    if x > 23064 or z < 42:
        return "LobbyEast"
    return "LobbyCenter"


def permitted(p):
    x, y, z = p
    if not (22624.5 <= x <= 23375.5 and -237.5 <= z <= 237.5 and 23.9 <= y <= 86.5):
        return False
    if y < 81 and ((x < 22677 and z < 0) or (x < 22647.5 and z < 100)):
        return False
    if y >= 81 and not (-35 <= z <= 15 or (22647.5 <= x <= 22668 and 0 <= z <= 100)):
        return False
    return True


def studio(v):
    return np.array((23000 + v[0] / .28, v[2] / .28, -v[1] / .28), float)


def exporter():
    ns = {"L4_EXPORT_NO_RUN": True, "__file__": str(HERE / "export_l4.py")}
    exec(compile((HERE / "export_l4.py").read_text(encoding="utf-8"), ns["__file__"], "exec"), ns)
    spec = importlib.util.spec_from_file_location("l4_nav_cull", HERE / "cull_hidden.py")
    cull = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(cull)
    return ns, cull


class Clearance:
    """Exact yaw-OBB/disk overlap, conservative bounds for tilted collision boxes."""
    def __init__(self, boxes, floors):
        self.boxes = [b for b in boxes if b.get("kind") != "Marker"]
        self.centres = np.array([b["cf"][:3] for b in self.boxes], float)
        self.half = np.array([b["s"] for b in self.boxes], float) / 2
        self.rot = np.array([b["cf"][3:] for b in self.boxes], float).reshape(-1, 3, 3)
        ext = np.einsum("nij,nj->ni", np.abs(self.rot), self.half)
        self.lo, self.hi = self.centres - ext, self.centres + ext
        self.floor_box = np.array(["Level4V4Floor" in b.get("tags", [])
                                   or ("DoorFrame" in b.get("src", "") and b["s"][1] <= .25)
                                   for b in self.boxes])
        self.yaw = (np.abs(self.rot[:, 1, 1]) > .99999)
        self.floors = floors
        self.fi = collections.defaultdict(list)
        self.bi = collections.defaultdict(list)
        for i, f in enumerate(floors):
            for x in range(math.floor(f[0] / 16), math.floor(f[1] / 16) + 1):
                for z in range(math.floor(f[2] / 16), math.floor(f[3] / 16) + 1):
                    self.fi[x, z].append(i)
        for i, (lo, hi) in enumerate(zip(self.lo, self.hi)):
            for x in range(math.floor((lo[0] - RADIUS) / 16), math.floor((hi[0] + RADIUS) / 16) + 1):
                for z in range(math.floor((lo[2] - RADIUS) / 16), math.floor((hi[2] + RADIUS) / 16) + 1):
                    self.bi[x, z].append(i)
        self.cache = {}

    def floor(self, x, z, ref):
        found = [self.floors[i][4] for i in self.fi[math.floor(x / 16), math.floor(z / 16)]
                 if self.floors[i][0] - 1e-6 <= x <= self.floors[i][1] + 1e-6
                 and self.floors[i][2] - 1e-6 <= z <= self.floors[i][3] + 1e-6
                 and self.floors[i][4] <= ref + STEP + 1e-6]
        return max(found, default=None)

    def blocked(self, x, y, z):
        idx = np.asarray(self.bi[math.floor(x / 16), math.floor(z / 16)], int)
        if not len(idx):
            return False
        vertical = ((self.lo[idx, 1] < y + HEIGHT - .005)
                    & (self.hi[idx, 1] > y + np.where(self.floor_box[idx], STEP, .04)))
        idx = idx[vertical]
        if not len(idx):
            return False
        delta = np.array((x, y, z)) - self.centres[idx]
        local = np.einsum("nji,nj->ni", self.rot[idx], delta)
        dx = np.maximum(np.abs(local[:, 0]) - self.half[idx, 0], 0)
        dz = np.maximum(np.abs(local[:, 2]) - self.half[idx, 2], 0)
        disk = dx * dx + dz * dz < RADIUS * RADIUS - 1e-8
        general_dx = np.maximum(np.maximum(self.lo[idx, 0] - x, x - self.hi[idx, 0]), 0)
        general_dz = np.maximum(np.maximum(self.lo[idx, 2] - z, z - self.hi[idx, 2]), 0)
        disk[~self.yaw[idx]] = (general_dx * general_dx + general_dz * general_dz)[~self.yaw[idx]] < RADIUS * RADIUS
        return bool(np.any(disk))

    def walkable(self, x, z, ref, footprint=True):
        key = (round(x, 4), round(z, 4), round(ref, 3), footprint)
        if key in self.cache:
            return self.cache[key]
        y = self.floor(x, z, ref)
        okay = y is not None and abs(y - ref) <= STEP + 1e-5 and permitted((x, y, z))
        if okay and footprint:
            for a in range(8):
                xx, zz = x + RADIUS * math.cos(a * math.pi / 4), z + RADIUS * math.sin(a * math.pi / 4)
                f = self.floor(xx, zz, y)
                if f is None or abs(f - y) > STEP + 1e-5 or not permitted((xx, f, zz)):
                    okay = False
                    break
        if okay:
            okay = not self.blocked(x, y, z)
        result = float(y) if okay else None
        self.cache[key] = result
        return result

    def edge(self, a, b):
        distance = math.dist((a[0], a[2]), (b[0], b[2]))
        count = max(2, math.ceil(distance / .6))
        prior = a[1]
        for t in np.linspace(0, 1, count + 1):
            p = a + (b - a) * t
            y = self.walkable(p[0], p[2], p[1])
            if y is None or abs(y - prior) > STEP + 1e-5:
                return False
            prior = y
        return abs(prior - b[1]) < .05


def floor_rectangles(layout, boxes=()):
    floors = [(p["cf"][0] - p["s"][0] / 2, p["cf"][0] + p["s"][0] / 2,
             p["cf"][2] - p["s"][2] / 2, p["cf"][2] + p["s"][2] / 2,
             p["cf"][1] + p["s"][1] / 2, p["p"])
            for p in layout["parts"] if not p.get("removed") and p["cc"]
            and ("Level4V4Floor" in p.get("tags", []) or p["p"].endswith("_BoothFloor"))]
    # Real door-frame threshold strips bridge the 2-stud wall opening. They are
    # walkable 0.06-stud metal sills, not obstructions or invented floor infill.
    floors += [(b["cf"][0] - b["s"][0] / 2, b["cf"][0] + b["s"][0] / 2,
                b["cf"][2] - b["s"][2] / 2, b["cf"][2] + b["s"][2] / 2,
                b["cf"][1] + b["s"][1] / 2, b["src"])
               for b in boxes if "DoorFrame" in b.get("src", "") and b["s"][1] <= .25]
    floors += [(b["cf"][0] - b["s"][0] / 2, b["cf"][0] + b["s"][0] / 2,
                b["cf"][2] - b["s"][2] / 2, b["cf"][2] + b["s"][2] / 2,
                b["cf"][1] + b["s"][1] / 2, b.get("src", "scene-floor"))
               for b in boxes if b.get("at", {}).get("L4NavThreshold") or b.get("at", {}).get("L4NavFloor")]
    return floors


def threshold():
    """Bridge only the verified 2-stud landing/gallery floor gap beneath the door."""
    name = "L4Nav_GalleryStairThreshold"
    old = bpy.data.objects.get(name)
    if old:
        bpy.data.objects.remove(old, do_unlink=True)
    bpy.ops.mesh.primitive_cube_add(size=1, location=((22658 - 23000) * .28, -.28, 85.7 * .28))
    o = bpy.context.object
    o.name = name
    o.scale = (18 * .28, 2 * .28, .6 * .28)
    for col in list(o.users_collection):
        col.objects.unlink(o)
    bpy.data.collections["L4 Cinema"].objects.link(o)
    floors = [f for f in bpy.data.collections["L4 Cinema"].all_objects
              if f.type == "MESH" and "GalleryFloor" in str(f.get("l4_path", f.name)) and f.material_slots]
    assert floors, "gallery carpet reference missing"
    reference = min(floors, key=lambda f: (f.matrix_world.translation - o.location).length)
    o.data.materials.append(reference.material_slots[0].material)
    o["l4_collide"] = "bounds"
    o["l4_occluder"] = True
    o["l4_tags"] = "Level4V4Floor"
    o["l4_attributes"] = json.dumps({"L4NavThreshold": True})
    bpy.context.view_layer.update()
    low, high = np.array([studio(o.matrix_world @ Vector(v)) for v in o.bound_box]).min(0), np.array([studio(o.matrix_world @ Vector(v)) for v in o.bound_box]).max(0)
    assert np.max(np.abs(high - np.array((22667, 86, 2)))) < 1e-4
    assert np.max(np.abs(low - np.array((22649, 85.4, 0)))) < 1e-4
    leaves = [f for f in bpy.data.collections["L4 Cinema"].all_objects if f.get("l4_door_leaf") and "GalleryStair" in f.name]
    assert len(leaves) == 2, [f.name for f in leaves]
    leaf_bottom = min(studio(f.matrix_world @ Vector(v))[1] for f in leaves for v in f.bound_box)
    assert leaf_bottom >= 86.1, f"threshold intersects moving door: bottom {leaf_bottom}"
    return {"bounds": [low.round(4).tolist(), high.round(4).tolist()], "door_leaf_bottom": leaf_bottom,
            "yaw_sweep_floor_clearance": leaf_bottom - high[1], "material": o.data.materials[0].name}


def graph(clear, layout):
    candidates = set()
    for x0, x1, z0, z1, y, path in clear.floors:
        if y > 86.5:
            continue
        for x in np.arange(math.ceil((x0 - 22624) / SPACING) * SPACING + 22624, x1, SPACING):
            for z in np.arange(math.ceil(z0 / SPACING) * SPACING, z1, SPACING):
                candidates.add((float(x), float(z), y))
        # Tread centres preserve exact step Y. Row-edge lanes avoid the seat centres.
        if "Tread" in path or "Tier" in path or "Landing" in path or "Platform" in path:
            xs = list(np.arange(x0 + RADIUS + .25, x1 - RADIUS, SPACING)) + [(x0 + x1) / 2]
            zs = [(z0 + z1) / 2] if z1 - z0 < 4 else [z0 + RADIUS + .15, z1 - RADIUS - .15]
            if "Tier" in path:
                zs += [z0 + .1, z1 - .1]
            if "Platform" in path:
                zs += [(z0 + z1) / 2]
            for x in xs:
                for z in zs:
                    candidates.add((round(float(x), 4), round(float(z), 4), y))
    for p in layout["parts"]:
        if p.get("removed") or "Level4V4Doorway" not in p.get("tags", []):
            continue
        x, y, z = p["cf"][:3]
        y -= p["s"][1] / 2
        short_x = p["s"][0] < p["s"][2]
        for d in (-6, -3, 0, 3, 6):
            candidates.add((x + (d if short_x else 0), z + (0 if short_x else d), y))
    points = set()
    for x, z, ref in sorted(candidates):
        y = clear.walkable(x, z, ref)
        if y is not None:
            points.add((round(x, 4), round(y, 4), round(z, 4)))
    # Keep the 8-stud lattice first. Supplementary floor/door probes fill real
    # narrow lanes; remove near-duplicates rather than inflate the runtime graph.
    sparse, occupied = [], collections.defaultdict(list)
    priority = lambda p: (0 if abs((p[0] - 22624) % 8) < 1e-5 and abs(p[2] % 8) < 1e-5 else 1, p)
    for p in sorted(points, key=priority):
        key = tuple(math.floor(v / 4) for v in p)
        close = [q for dx in (-1, 0, 1) for dy in (-1, 0, 1) for dz in (-1, 0, 1)
                 for q in occupied[key[0] + dx, key[1] + dy, key[2] + dz]]
        # Seat-row/aisle turns need both corner probes; other rooms can discard
        # points within one agent width without losing those narrow bends.
        minimum = 2.1 if room(p) in ("A1", "A2", "A3") else (2.5 if room(p) == "Core" else 4.8)
        if not any(math.dist(p, q) < minimum for q in close):
            sparse.append(p)
            occupied[key].append(p)
    points = np.array(sorted(sparse), float)
    grid = collections.defaultdict(list)
    for i, p in enumerate(points):
        grid[math.floor(p[0] / 12), math.floor(p[2] / 12)].append(i)
    edges = []
    for i, p in enumerate(points):
        gx, gz = math.floor(p[0] / 12), math.floor(p[2] / 12)
        for dx in (-1, 0, 1):
            for dz in (-1, 0, 1):
                for j in grid[gx + dx, gz + dz]:
                    if j > i and math.dist(p[[0, 2]], points[j, [0, 2]]) <= 11.6 and abs(p[1] - points[j, 1]) <= 10:
                        if clear.edge(p, points[j]):
                            edges.append((i, j))
    adjacency = collections.defaultdict(list)
    for a, b in edges:
        adjacency[a].append(b)
        adjacency[b].append(a)
    seen, components = set(), []
    for i in range(len(points)):
        if i in seen:
            continue
        comp, todo = [], [i]
        seen.add(i)
        while todo:
            a = todo.pop()
            comp.append(a)
            for b in adjacency[a]:
                if b not in seen:
                    seen.add(b)
                    todo.append(b)
        components.append(comp)
    # Reachability is rooted on the actual concession/service lobby entry floor.
    entry = np.array((22870, 24, 91))
    start = int(np.argmin(np.linalg.norm(points - entry, axis=1)))
    reachable = next(c for c in components if start in c)
    mapping = {old: new for new, old in enumerate(sorted(reachable))}
    kept_edges = [(mapping[a], mapping[b]) for a, b in edges if a in mapping and b in mapping]
    rejected = [{"count": len(c), "rooms": dict(collections.Counter(room(points[i]) for i in c)),
                 "centre": points[c].mean(0).round(3).tolist()} for c in components if c is not reachable]
    (OUT / "candidate_graph.json").write_text(json.dumps({"Nodes": points.tolist(), "Edges": edges,
             "Components": components, "Entry": start, "Rejected": rejected}), encoding="utf-8")
    print("Usher graph candidate:", len(points), "points", len(edges), "edges", "components", [len(c) for c in components], flush=True)
    return points[sorted(reachable)], kept_edges, rejected


def cluster(points, count):
    points = np.asarray(points, float)
    # Deterministic farthest-point seeds, then room-only Lloyd iterations.
    centres = [points.mean(0)]
    while len(centres) < count:
        distances = np.min(np.sum((points[:, None, :] - np.asarray(centres)[None, :, :]) ** 2, axis=2), axis=1)
        centres.append(points[int(np.argmax(distances))])
    centres = np.array(centres)
    for _ in range(24):
        assignments = np.argmin(np.sum((points[:, None, :] - centres[None, :, :]) ** 2, axis=2), axis=1)
        new = np.array([points[assignments == i].mean(0) if np.any(assignments == i) else centres[i] for i in range(count)])
        if np.max(np.abs(new - centres)) < .01:
            break
        centres = new
    return centres


def zone_lights(points):
    holders = list(bpy.data.collections.get("L4 Fixture Lights").all_objects)
    lights = [o for o in holders if o.type == "LIGHT"]
    assert len(lights) <= 260, f"light budget exceeded: {len(lights)}"
    by_room = collections.defaultdict(list)
    for o in lights:
        if not o.get("l4_zone_parent"):
            p = studio(Vector(o.get("l4_zone_position", o.matrix_world.translation)))
            by_room[room(p)].append(o)
    zones, room_zones = [], {}
    for name, count in ROOM_COUNTS.items():
        positions = [studio(Vector(o.get("l4_zone_position", o.matrix_world.translation))) for o in by_room[name]]
        if not positions:
            positions = [p for p in points if room(p) == name]
        assert len(positions), f"no geometry or lights in required room {name}"
        centres = cluster([p for p in points if room(p) == name] if name == "Core" else positions, count)
        room_zones[name] = []
        for centre in sorted(centres, key=lambda p: (p[0], p[2], p[1])):
            zid = len(zones) + 1
            floor_points = np.array([p for p in points if room(p) == name])
            assert len(floor_points), f"no reachable Usher floor in {name}"
            close = np.sum((floor_points[:, [0, 2]] - centre[[0, 2]]) ** 2, axis=1)
            if name == "Core":
                close += ((floor_points[:, 1] - centre[1] + 5) * .8) ** 2
            marker_pos = floor_points[int(np.argmin(close))]
            zones.append({"id": zid, "room": name, "centre": centre.tolist(), "position": marker_pos.tolist(),
                          "radius": 0, "lights": []})
            room_zones[name].append(zid)

    def nearest(p):
        ids = room_zones[room(p)]
        weights = np.array((1, 1 if room(p) == "Core" else .08, 1))
        return min(ids, key=lambda i: float(np.sum(((p - np.array(zones[i - 1]["centre"])) * weights) ** 2)))

    for o in lights:
        parent = bpy.data.objects.get(o.get("l4_zone_parent", ""))
        source = parent if parent is not None else o
        p = studio(Vector(source.get("l4_zone_position", source.matrix_world.translation)))
        zid = nearest(p)
        o["l4_zone"] = zid
        zones[zid - 1]["lights"].append(o.name)
    root = bpy.data.collections.get("L4 Cinema")
    emit_count = 0
    for o in root.all_objects:
        if o.type != "MESH" or o.get("l4_marker"):
            continue
        tags = str(o.get("l4_tags", ""))
        star = "L4Star" in tags or "Stars" in o.name or "Starfield" in o.name
        materials = [s.material for s in o.material_slots if s.material]
        emissive = any(m.get("l4_sem") == "neon" or float(m.get("l4_emit", 0) or 0) >= 2 for m in materials)
        if star or any("L4Star" in str(m.get("l4_tags", "")) for m in materials):
            if "l4_zone" in o:
                del o["l4_zone"]
            o["l4_global_emission"] = True
        elif emissive:
            p = studio(sum((o.matrix_world @ Vector(v) for v in o.bound_box), Vector()) / 8)
            zid = nearest(p)
            o["l4_zone"] = zid
            o["l4_zone_split"] = True  # exporter must classify each world-space triangle, not this large pool's centre
            emit_count += 1
    # Painted menu faces no longer qualify as emissive; their Neon trim still shares the box's circuit.
    for o in root.all_objects:
        if o.type != "MESH" or not o.get("l4_zone_parent"):
            continue
        parent = bpy.data.objects[o["l4_zone_parent"]]
        p = studio(sum((parent.matrix_world @ Vector(v) for v in parent.bound_box), Vector()) / 8)
        parent["l4_zone"] = nearest(p)
        o["l4_zone"], o["l4_zone_split"] = parent["l4_zone"], True
    for p in points:
        zid = nearest(p)
        z = zones[zid - 1]
        z["radius"] = max(z["radius"], math.dist(p[[0, 2]], np.array(z["position"])[[0, 2]]) + 6)
    bpy.context.scene["l4_light_zones"] = json.dumps(zones, separators=(",", ":"))
    return zones, nearest, emit_count


def zone_for_position(p, zones=None):
    """Original Studio studs -> room-restricted zone; exporter uses triangle centres for pooled neon."""
    zones = zones or json.loads(bpy.context.scene["l4_light_zones"])
    choices = [z for z in zones if z["room"] == room(p)]
    p = np.asarray(p, float)
    weights = np.array((1, 1 if room(p) == "Core" else .08, 1))
    return min(choices, key=lambda z: float(np.sum(((p - np.array(z["centre"])) * weights) ** 2)))["id"]


def markers(points, zones, nearest):
    old = bpy.data.collections.get("L4 Round Navigation")
    if old:
        for o in list(old.objects):
            bpy.data.objects.remove(o, do_unlink=True)
        bpy.data.collections.remove(old)
    col = bpy.data.collections.new("L4 Round Navigation")
    bpy.data.collections["L4 Cinema"].children.link(col)
    me = bpy.data.meshes.new("L4NavMarkerBox")
    me.from_pydata([(-.5, -.5, -.5), (.5, -.5, -.5), (.5, .5, -.5), (-.5, .5, -.5),
                   (-.5, -.5, .5), (.5, -.5, .5), (.5, .5, .5), (-.5, .5, .5)], [],
                  [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)])
    def add(name, p, tag, attrs, size):
        o = bpy.data.objects.new(name, me)
        col.objects.link(o)
        o.location = ((p[0] - 23000) * .28, -p[2] * .28, p[1] * .28)
        o.scale = (size[0] * .28, size[2] * .28, size[1] * .28)
        o.hide_render = True
        o.display_type = "WIRE"
        o["l4_marker"] = True
        o["l4_tags"] = tag
        o["l4_attributes"] = json.dumps(attrs, separators=(",", ":"))
        o["l4_collide"] = "bounds"
    for i, p in enumerate(points, 1):
        add(f"L4UsherNode_{i:04}", p + (0, .5, 0), "L4UsherNode", {"Zone": nearest(p)}, (1, 1, 1))
    for z in zones:
        p = np.array(z["position"]) + (0, .025, 0)
        add(f"L4LightZone_{z['id']:02}", p, "L4LightZone", {"Zone": z["id"], "Radius": round(z["radius"], 3)}, (1, .05, 1))


def build_usher_nav():
    OUT.mkdir(parents=True, exist_ok=True)
    threshold_audit = threshold()
    ex, cull = exporter()
    objects = [o for o in bpy.data.collections["L4 Cinema"].all_objects if o.type == "MESH" and not o.get("l4_marker")]
    boxes, _, _, mismatch = cull.gather_colliders(objects, ex)
    assert not mismatch, f"scene/layout index conflict: {mismatch[:8]}"
    clear = Clearance(boxes, floor_rectangles(ex["LAYOUT"], boxes))
    (OUT / "collisions.json").write_text(json.dumps(clear.boxes), encoding="utf-8")
    points, edges, rejected = graph(clear, ex["LAYOUT"])
    row_counts = {}
    for f in clear.floors:
        if "Tier" in f[5]:
            x0, x1, z0, z1, y, path = f
            row_counts[path] = int(np.sum((points[:, 0] > x0 + 12) & (points[:, 0] < x1 - 12)
                                          & (points[:, 2] > z0) & (points[:, 2] < z1)
                                          & (np.abs(points[:, 1] - y) < .05)))
    assert len(row_counts) == 54 and all(row_counts.values()), f"seat-row coverage missing: {row_counts}"
    assert not any(any(name in ("A1", "A2", "A3") and count > 3 for name, count in c["rooms"].items())
                   for c in rejected), f"reachable row lane was disconnected: {rejected}"
    exit_floor_counts = {}
    for x0, x1, z0, z1, y, path in clear.floors:
        if "L4ExitAccess" in path:
            exit_floor_counts[path] = int(np.sum((points[:, 0] > x0) & (points[:, 0] < x1)
                                                & (points[:, 2] > z0) & (points[:, 2] < z1)
                                                & (np.abs(points[:, 1] - y) < .05)))
    if exit_floor_counts:
        assert len(exit_floor_counts) == 7 and all(exit_floor_counts.values()), exit_floor_counts
    zones, nearest, emit_count = zone_lights(points)
    node_rooms = collections.Counter(room(p) for p in points)
    assert all(node_rooms[name] for name in ROOM_COUNTS), node_rooms
    nodes = [[round(p[0] + 6000, 4), round(p[1], 4), round(p[2], 4), nearest(p)] for p in points]
    markers(points, zones, nearest)
    def n(v):
        return str(int(v)) if float(v).is_integer() else f"{v:.4f}".rstrip("0").rstrip(".")
    MODULE.parent.mkdir(parents=True, exist_ok=True)
    MODULE.write_text("-- Generated from current Blender collision geometry; layout +6000 X.\nreturn { Nodes = {\n"
                      + ",\n".join("{" + ",".join(map(n, p)) + "}" for p in nodes)
                      + "\n}, Edges = {\n" + ",\n".join(f"{{{a + 1},{b + 1}}}" for a, b in edges) + "\n} }\n", encoding="utf-8")
    audit = {"nodes": len(points), "edges": len(edges), "connected_components": 1, "node_rooms": dict(node_rooms),
             "seat_rows": row_counts,
             "exit_access_floors": exit_floor_counts,
             "zones": zones, "light_count": sum(len(z["lights"]) for z in zones), "emissive_objects": emit_count,
             "collision_boxes": len(clear.boxes), "threshold": threshold_audit, "clearance": {"height": HEIGHT, "width": RADIUS * 2,
             "max_step": STEP, "edge_sample_spacing": .6}, "rejected_components": rejected,
             "coordinate_transform": "Blender (x,y,z) / .28 -> (x+29000,z,-y)", "module": str(MODULE)}
    (OUT / "audit.json").write_text(json.dumps(audit, indent=2), encoding="utf-8")
    (OUT / "graph.json").write_text(json.dumps({"Nodes": nodes, "Edges": [[a + 1, b + 1] for a, b in edges]}), encoding="utf-8")
    (OUT / "collisions.json").write_text(json.dumps(clear.boxes), encoding="utf-8")
    print("Usher nav:", len(points), "nodes", len(edges), "edges", len(zones), "zones", audit["light_count"], "lights", flush=True)
    return audit


def selfcheck():
    I = [1, 0, 0, 0, 1, 0, 0, 0, 1]
    floor = (22677, 22710, 0, 30, 24, "floor")
    box = {"cf": [22695, 30, 15] + I, "s": [2, 12, 10]}
    c = Clearance([box], [floor])
    assert c.walkable(22690, 15, 24) == 24
    assert c.walkable(22694, 15, 24) is None
    assert not c.edge(np.array((22690, 24, 15)), np.array((22700, 24, 15)))
    assert c.edge(np.array((22690, 24, 3)), np.array((22700, 24, 3)))
    assert room((22766, 86, -25)) == "Booth1"
    assert room((22766, 95, -8)) == "Gallery"
    assert not permitted((22650, 24, -80))
    assert len(ROOM_COUNTS) == 20 and sum(ROOM_COUNTS.values()) == 38
    print("usher_nav selfcheck passed", flush=True)


if __name__ == "__main__":
    selfcheck()
    build_usher_nav()
