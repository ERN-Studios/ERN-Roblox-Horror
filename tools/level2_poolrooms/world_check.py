"""Reconstruct dumped Luau Poolrooms worlds and audit visual/capsule escapes.

Run: D:/Blender/blender.exe -b --factory-startup --python-exit-code 1 \
    -P tools/level2_poolrooms/world_check.py -- 837834 1 101
Only reads the frozen world dumps and A/B/C kit exports. Reports go beside the dumps.
"""

from __future__ import annotations

import argparse
from collections import defaultdict
import json
import math
from pathlib import Path
import sys
import time

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree
import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from render_world import fixture_chunk, load_kit_chunks, mesh_triangles_world  # noqa: E402

WORLDS = Path("G:/Blender/Level2_Poolrooms/worlds")
VOXEL = 1.0
RAYS = 512
BOX_FACES = np.array(((0, 1, 2), (0, 2, 3), (4, 6, 5), (4, 7, 6),
                      (0, 4, 5), (0, 5, 1), (1, 5, 6), (1, 6, 2),
                      (2, 6, 7), (2, 7, 3), (3, 7, 4), (3, 4, 0)), dtype=np.int32)


def frame(cf):
    """Full row-major Roblox CFrame from the dump, as position and rotation."""
    return np.asarray(cf[:3], dtype=np.float64), np.asarray(cf[3:], dtype=np.float64).reshape(3, 3)


CYLINDER_SIDES = 64     # chord sag 0.02 at the pressure door's r 17.3 (24 sides sagged 0.15, half its 0.3 seat)


def part_triangles(part):
    from collision_audit import normalize_cylinder   # lazy: collision_audit imports this module
    # Dump fixture cylinders are logical vertical-Y (the fake installer does not apply the live importer's
    # nativeCylinder remap); the builder's own Parts (pressure doors, pump lamps, Column Block colliders) are native
    # Roblox cylinders, axis = local X. normalize_cylinder turns the native kind into the logical one (idempotent).
    part = normalize_cylinder(part)
    size = np.asarray(part["size"], dtype=np.float64)
    pos, rot = frame(part["cframe"])
    if "Cylinder" in str(part["shape"]):
        n = CYLINDER_SIDES
        a = np.arange(n, dtype=np.float64) * (2 * math.pi / n)
        ring = np.stack((np.cos(a) * size[0] / 2, np.zeros(n),
                         np.sin(a) * size[2] / 2), axis=1)
        bottom, top = ring.copy(), ring.copy()
        bottom[:, 1], top[:, 1] = -size[1] / 2, size[1] / 2
        verts = np.concatenate((bottom, top, [[0, -size[1] / 2, 0], [0, size[1] / 2, 0]]))
        faces = []
        for i in range(n):
            j = (i + 1) % n
            faces.extend(((i, j, n + j), (i, n + j, n + i),
                          (2 * n, j, i), (2 * n + 1, n + i, n + j)))
        faces = np.asarray(faces, dtype=np.int32)
    else:
        x, y, z = size / 2
        verts = np.asarray(((-x, -y, -z), (x, -y, -z), (x, y, -z), (-x, y, -z),
                            (-x, -y, z), (x, -y, z), (x, y, z), (-x, y, z)))
        if part["class"] == "WedgePart" or "Wedge" in str(part["shape"]):
            # Roblox wedge's high edge is local -Z; the low edge is local +Z.
            verts[[3, 2], 1] = -y
        faces = BOX_FACES
    return (verts @ rot.T + pos)[faces]


def visual_geometry(world, chunks):
    arrays, names = [], []
    for part in world["parts"]:
        if part["transparency"] >= 0.98:
            continue
        if part["fixtureKind"] == "mesh":
            tri = mesh_triangles_world(part, fixture_chunk(part, chunks))
        elif part["class"] != "MeshPart":
            tri = part_triangles(part)
        else:
            continue
        arrays.append(np.asarray(tri, dtype=np.float32))
        names.append((part["name"], len(tri)))
    triangles = np.concatenate(arrays)
    print(f"VISUAL_GEOMETRY parts={len(arrays)} tris={len(triangles)}", flush=True)
    return triangles


def make_bvh(triangles):
    # BVHTree.FromPolygons is C-backed; numpy supplies the large input batches.
    vertices = triangles.reshape(-1, 3).tolist()
    faces = np.arange(len(vertices), dtype=np.int32).reshape(-1, 3).tolist()
    return BVHTree.FromPolygons(vertices, faces, all_triangles=True)


def volume_boxes(layout):
    boxes = []
    for h in layout["Halls"]:
        fy = h["FloorY"]
        top = fy + (96 if h["Type"] == "ExitHall" else h["CeilingClass"])
        boxes.append((h["MinX"], fy - 4, h["MinZ"], h["MaxX"], top + 2, h["MaxZ"]))
    for c in layout["Corridors"]:
        half = c["Width"] / 2
        fy = min(c["FromY"], c["ToY"])
        top = max(c["FromY"], c["ToY"]) + (12 if c["Width"] <= 12 else 32)
        if c["Axis"] == "X":
            boxes.append((c["From"], fy - 4, c["Cross"] - half,
                          c["To"], top + 2, c["Cross"] + half))
        else:
            boxes.append((c["Cross"] - half, fy - 4, c["From"],
                          c["Cross"] + half, top + 2, c["To"]))
    return np.asarray(boxes, dtype=np.float64)


def sample_points(layout):
    samples = []
    for h in layout["Halls"]:
        nx = max(2, math.ceil((h["MaxX"] - h["MinX"] - 6) / 22) + 1)
        nz = max(2, math.ceil((h["MaxZ"] - h["MinZ"] - 6) / 22) + 1)
        xs = np.linspace(h["MinX"] + 3, h["MaxX"] - 3, nx)
        zs = np.linspace(h["MinZ"] + 3, h["MaxZ"] - 3, nz)
        for x in xs:
            for z in zs:
                for height in (3, 6, min(15, h["CeilingClass"] - 2)):
                    samples.append((np.array((x, h["FloorY"] + height, z)), f"Hall {h['Index']} {h['Type']}"))
    for c in layout["Corridors"]:
        n = max(3, math.ceil(c["Length"] / 10) + 1)
        for axis in np.linspace(c["From"] + 2, c["To"] - 2, n):
            t = (axis - c["From"]) / max(1, c["Length"])
            floor = c["FromY"] + t * (c["ToY"] - c["FromY"])
            for side in (-0.28, 0, 0.28):
                cross = c["Cross"] + side * c["Width"]
                x, z = (axis, cross) if c["Axis"] == "X" else (cross, axis)
                for height in (3, 6, 9 if c["Width"] <= 12 else 15):
                    samples.append((np.array((x, floor + height, z)),
                                    f"{'Pipe' if c['Width'] <= 12 else 'Tunnel'} {c['Index']} {c['Variant']}"))
    return samples


def directions(n=RAYS):
    # Uniform Fibonacci sphere with a fixed phase; includes all six axial rays.
    k = np.arange(n, dtype=np.float64)
    y = 1 - 2 * (k + .5) / n
    theta = k * math.pi * (3 - math.sqrt(5))
    r = np.sqrt(1 - y * y)
    sphere = np.stack((r * np.cos(theta), y, r * np.sin(theta)), axis=1)
    return np.vstack((sphere, np.eye(3), -np.eye(3)))


def intended_sky(origin, ray, sky):
    if ray[1] <= 1e-5:
        return False
    for marker in sky:
        center = np.asarray(marker["cframe"][:3])
        kind = marker["attributes"]["Level2_OpenSkyKind"]
        # The marker is above the aperture. Classify at the actual narrow
        # throat, before an oblique ray fans beyond the declared radius.
        offset = .54 if kind == "SpiralWell" else (2.0 if kind == "ExitHall" else 1.46)
        t = (center[1] - offset - origin[1]) / ray[1]
        if t <= 0:
            continue
        hit = origin + t * ray
        if np.linalg.norm(hit[[0, 2]] - center[[0, 2]]) < marker["attributes"]["Level2_OpenSkyRadius"] - .02:
            return True
    return False


def intended_exit(origin, ray, exit_hall):
    if ray[0] <= 0 or not exit_hall:
        return False
    t = (exit_hall["MaxX"] - origin[0]) / ray[0]
    if t <= 0:
        return False
    p = origin + t * ray
    return abs(p[1] - 83.3) < 9 and abs(p[2] - 724.75) < 9


def intended_slit(origin, ray, slits):
    for slit in slits:
        center, rot = frame(slit["pivot"])
        local_o = (origin - center) @ rot
        local_d = ray @ rot
        if abs(local_d[2]) < 1e-8:
            continue
        t = -local_o[2] / local_d[2]
        if t <= 0:
            continue
        hit = local_o + t * local_d
        if abs(hit[0]) < .8 and 3 < hit[1] < 17:
            return True
    return False


def first_volume_exit(origin, ray, boxes):
    lo, hi = boxes[:, :3], boxes[:, 3:]
    with np.errstate(divide="ignore", invalid="ignore"):
        a = (lo - origin) / ray
        b = (hi - origin) / ray
    for axis in range(3):
        if abs(ray[axis]) < 1e-9:
            inside = (lo[:, axis] <= origin[axis]) & (origin[axis] <= hi[:, axis])
            a[:, axis] = np.where(inside, -np.inf, np.inf)
            b[:, axis] = np.where(inside, np.inf, -np.inf)
    starts, ends = np.minimum(a, b).max(axis=1), np.maximum(a, b).min(axis=1)
    intervals = sorted((max(0, s), e) for s, e in zip(starts, ends) if e >= max(0, s))
    end = 0.0
    for start, finish in intervals:
        if start > end + .05:
            break
        end = max(end, finish)
    return origin + max(0, end) * ray


def nearest_parts(point, world, limit=5):
    best = []
    for p in world["parts"]:
        if p["transparency"] >= .98 and not p["canCollide"]:
            continue
        center, rot = frame(p["cframe"])
        extent = np.abs(rot) @ (np.asarray(p["size"]) / 2)
        distance = float(np.linalg.norm(np.maximum(np.abs(point - center) - extent, 0)))
        best.append((distance, p["name"], p["fixtureComponent"], p["path"]))
    best.sort(key=lambda v: v[0])
    return [{"distance": round(v[0], 2), "name": v[1], "component": v[2], "path": v[3]}
            for v in best[:limit]]


def visual_check(world, bvh, boxes):
    samples = sample_points(world["layout"])
    rays = directions()
    sky = [p for p in world["parts"] if "Level2_OpenSkyRadius" in p["attributes"]]
    slits = [p for p in world["components"] if p["component"] == "SunSlit"]
    exit_hall = next((h for h in world["layout"]["Halls"] if h["Type"] == "ExitHall"), None)
    clusters = defaultdict(lambda: {"count": 0, "pointSum": np.zeros(3), "example": None, "sources": set()})
    intended = leaks = 0
    for si, (origin, label) in enumerate(samples):
        v = Vector(origin)
        for ray in rays:
            hit = bvh.ray_cast(v, Vector(ray), 2500)[0]
            if hit is not None:
                continue
            if intended_sky(origin, ray, sky) or intended_exit(origin, ray, exit_hall) or intended_slit(origin, ray, slits):
                intended += 1
                continue
            leaks += 1
            point = first_volume_exit(origin, ray, boxes)
            key = tuple(np.floor(point / 12).astype(int))
            cluster = clusters[key]
            cluster["count"] += 1
            cluster["pointSum"] += point
            cluster["sources"].add(label)
            if cluster["example"] is None:
                cluster["example"] = {"sample": origin.tolist(), "direction": ray.tolist(), "source": label}
        if si and si % 500 == 0:
            print(f"VISUAL_PROGRESS {si}/{len(samples)} leaks={leaks}", flush=True)
    records = []
    for cluster in clusters.values():
        point = cluster["pointSum"] / cluster["count"]
        records.append({"position": np.round(point, 2).tolist(), "rays": cluster["count"],
                        "sample": np.round(cluster["example"]["sample"], 2).tolist(),
                        "direction": np.round(cluster["example"]["direction"], 5).tolist(),
                        "sources": sorted(cluster["sources"]), "nearest": nearest_parts(point, world)})
    records.sort(key=lambda c: (-c["rays"], c["position"]))
    return {"samplePoints": len(samples), "raysPerPoint": len(rays),
            "raysCast": len(samples) * len(rays), "intendedOpenRays": intended,
            "leakRays": leaks, "clusters": records}


def voxel_grid(world, open_doors=False):
    layout = world["layout"]
    bounds = layout["Bounds"]
    low = np.array((math.floor(bounds["MinX"]) - 8,
                    min(math.floor(h["FloorY"]) for h in layout["Halls"]) - 9,
                    math.floor(bounds["MinZ"]) - 8), dtype=int)
    high = np.array((math.ceil(bounds["MaxX"]) + 8,
                     max(h["FloorY"] + (96 if h["Type"] == "ExitHall" else h["CeilingClass"])
                         for h in layout["Halls"]) + 12,
                     math.ceil(bounds["MaxZ"]) + 8), dtype=int)
    nx, ny, nz = (high - low).astype(int)
    occ = np.zeros((ny, nz, nx), dtype=np.bool_)
    count = 0
    for index, part in enumerate(world["parts"]):
        if not part["canCollide"] or (open_doors and part["name"].startswith("Level 2 Pressure Door ")):
            continue
        center, rot = frame(part["cframe"])
        size = np.asarray(part["size"], dtype=float)
        ext = np.abs(rot) @ (size / 2)
        begin = np.maximum(np.floor(center - ext - .6 - low).astype(int), 0)
        end = np.minimum(np.ceil(center + ext + .6 - low).astype(int), (nx, ny, nz))
        if np.any(begin >= end):
            continue
        xx = low[0] + np.arange(begin[0], end[0]) + .5
        yy = low[1] + np.arange(begin[1], end[1]) + .5
        zz = low[2] + np.arange(begin[2], end[2]) + .5
        y, z, x = np.ogrid[yy[0]:yy[-1] + .5:1, zz[0]:zz[-1] + .5:1, xx[0]:xx[-1] + .5:1]
        dx, dy, dz = x - center[0], y - center[1], z - center[2]
        lx = dx * rot[0, 0] + dy * rot[1, 0] + dz * rot[2, 0]
        ly = dx * rot[0, 1] + dy * rot[1, 1] + dz * rot[2, 1]
        lz = dx * rot[0, 2] + dy * rot[1, 2] + dz * rot[2, 2]
        pad = np.where(size < 1.0, .42, .02)
        if "Cylinder" in str(part["shape"]):
            mask = (np.abs(ly) <= size[1] / 2 + pad[1]) & \
                   ((lx / (size[0] / 2 + pad[0])) ** 2 + (lz / (size[2] / 2 + pad[2])) ** 2 <= 1)
        elif part["fixtureKind"] == "slide-template":
            # The fake engine dumps a ring's bounding box, not its hollow hull.
            # Keep the nominal bore open; exact ride hull fidelity is unverified.
            radial = (lx / max(size[0], .1) * 16) ** 2 + (ly / max(size[1], .1) * 16) ** 2
            mask = (radial >= 6.8 ** 2) & (radial <= 8.25 ** 2) & \
                   (np.abs(lz) <= size[2] / 2 + pad[2])
        else:
            mask = (np.abs(lx) <= size[0] / 2 + pad[0]) & \
                   (np.abs(ly) <= size[1] / 2 + pad[1]) & \
                   (np.abs(lz) <= size[2] / 2 + pad[2])
        occ[begin[1]:end[1], begin[2]:end[2], begin[0]:end[0]] |= mask
        count += 1
        if index and index % 1500 == 0:
            print(f"VOXEL_PROGRESS {index}/{len(world['parts'])}", flush=True)
    print(f"VOXELS dimensions={occ.shape} solid={int(occ.sum())} parts={count} openDoors={open_doors}", flush=True)
    return low, occ, count


def standing_space(occupied):
    # A 2-stud capsule needs a 5-stud tall, approximately 2-stud wide gap.
    blocked = occupied.copy()
    for dy in range(1, 5):
        blocked[:-dy] |= occupied[dy:]
    body = blocked.copy()
    for dz in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if dx == dz == 0:
                continue
            z_dst = slice(max(0, -dz), min(body.shape[1], body.shape[1] - dz))
            z_src = slice(max(0, dz), min(body.shape[1], body.shape[1] + dz))
            x_dst = slice(max(0, -dx), min(body.shape[2], body.shape[2] - dx))
            x_src = slice(max(0, dx), min(body.shape[2], body.shape[2] + dx))
            blocked[:, z_dst, x_dst] |= body[:, z_src, x_src]
    free = ~blocked
    free[1:] &= occupied[:-1]
    free[0] = False
    return free, blocked


def inside_volume(point, halls, corridors):
    x, foot, z = point
    for h in halls:
        if h["MinX"] - .5 <= x <= h["MaxX"] + .5 and h["MinZ"] - .5 <= z <= h["MaxZ"] + .5:
            top = h["FloorY"] + (96 if h["Type"] == "ExitHall" else h["CeilingClass"])
            if h["FloorY"] - 3 <= foot and foot + 5 <= top + 2:
                return True
    for c in corridors:
        if c["Axis"] == "X":
            along, cross = x, z
        else:
            along, cross = z, x
        if c["From"] - .5 <= along <= c["To"] + .5 and abs(cross - c["Cross"]) <= c["Width"] / 2 + .5:
            f = (along - c["From"]) / max(1, c["Length"])
            floor = c["FromY"] + f * (c["ToY"] - c["FromY"])
            if floor - 3 <= foot and foot + 5 <= floor + (12 if c["Width"] <= 12 else 32) + 2:
                return True
    return False


def volume_masks(world, low, shape):
    ny, nz, nx = shape
    allowed = np.zeros(shape, dtype=np.bool_)
    near = np.zeros((nz, nx), dtype=np.bool_)

    def ranges(x1, x2, y1, y2, z1, z2):
        # Ranges are voxel-center inclusive in world studs.
        a = np.ceil(np.array((x1, y1, z1)) - low - .5).astype(int)
        b = np.floor(np.array((x2, y2, z2)) - low - .5).astype(int) + 1
        a = np.maximum(a, 0)
        b = np.minimum(b, (nx, ny, nz))
        return a, b

    for hall in world["layout"]["Halls"]:
        fy = hall["FloorY"]
        top = fy + (96 if hall["Type"] == "ExitHall" else hall["CeilingClass"])
        a, b = ranges(hall["MinX"] - .5, hall["MaxX"] + .5, fy - 3, top - 3,
                      hall["MinZ"] - .5, hall["MaxZ"] + .5)
        allowed[a[1]:b[1], a[2]:b[2], a[0]:b[0]] = True
        a, b = ranges(hall["MinX"] - 8, hall["MaxX"] + 8, 0, 0,
                      hall["MinZ"] - 8, hall["MaxZ"] + 8)
        near[a[2]:b[2], a[0]:b[0]] = True
    for corridor in world["layout"]["Corridors"]:
        c = corridor
        width = c["Width"] / 2
        lo = math.ceil(c["From"] - .5)
        hi = math.floor(c["To"] + .5)
        for axis in range(lo, hi + 1):
            fraction = (axis - c["From"]) / max(1, c["Length"])
            floor = c["FromY"] + fraction * (c["ToY"] - c["FromY"])
            top = floor + (12 if c["Width"] <= 12 else 32)
            if c["Axis"] == "X":
                a, b = ranges(axis - .5, axis + .5, floor - 3, top - 3,
                              c["Cross"] - width - .5, c["Cross"] + width + .5)
            else:
                a, b = ranges(c["Cross"] - width - .5, c["Cross"] + width + .5,
                              floor - 3, top - 3, axis - .5, axis + .5)
            allowed[a[1]:b[1], a[2]:b[2], a[0]:b[0]] = True
        if c["Axis"] == "X":
            a, b = ranges(c["From"] - 8, c["To"] + 8, 0, 0,
                          c["Cross"] - width - 8, c["Cross"] + width + 8)
        else:
            a, b = ranges(c["Cross"] - width - 8, c["Cross"] + width + 8, 0, 0,
                          c["From"] - 8, c["To"] + 8)
        near[a[2]:b[2], a[0]:b[0]] = True
    return allowed, near


def exit_transition(point, hall):
    # Exit ride beyond the high platform is an intentional continuation, not
    # hall space. Stop the flood at its mouth to keep the audit about this level.
    x, y, z = point
    return x >= hall["MaxX"] - 2 and abs(y - 83.3) < 10 and abs(z - 724.75) < 10


def collision_check(world, open_doors=False):
    low, occupied, n_parts = voxel_grid(world, open_doors)
    standable, blocked = standing_space(occupied)
    allowed, near = volume_masks(world, low, occupied.shape)
    ny, nz, nx = occupied.shape
    spawn = next(p for p in world["parts"] if p["name"] == "ElevatorSpawn")
    s = np.floor(np.asarray(spawn["cframe"][:3]) - low).astype(int)
    # The marker sits one tenth above the deck; its capsule base occupies the
    # first empty layer immediately above the support voxel.
    while s[1] < ny - 5 and not standable[s[1], s[2], s[0]]:
        s[1] += 1
    if s[1] >= ny - 5:
        raise RuntimeError("arrival spawn has no 2 x 5 standing voxel")
    queue = [int((s[1] * nz + s[2]) * nx + s[0])]
    standable[s[1], s[2], s[0]] = False
    head = 0
    reach = drop = skipped_exit = 0
    reached_min = np.array((np.inf, np.inf, np.inf))
    reached_max = np.array((-np.inf, -np.inf, -np.inf))
    low_floor = min(h["FloorY"] for h in world["layout"]["Halls"])
    exit_hall = next(h for h in world["layout"]["Halls"] if h["Type"] == "ExitHall")
    clusters = defaultdict(lambda: {"count": 0, "sum": np.zeros(3), "example": None, "kind": "outside"})

    def record(point, kind):
        key = (kind, *np.floor(point / 8).astype(int))
        c = clusters[key]
        c["count"] += 1
        c["sum"] += point
        c["kind"] = kind
        if c["example"] is None:
            c["example"] = point.tolist()

    while head < len(queue):
        index = queue[head]
        head += 1
        ix = index % nx
        iz = (index // nx) % nz
        iy = index // (nx * nz)
        point = low + np.array((ix + .5, iy + .5, iz + .5))
        reach += 1
        reached_min = np.minimum(reached_min, point)
        reached_max = np.maximum(reached_max, point)
        if exit_transition(point, exit_hall):
            skipped_exit += 1
            continue
        if not allowed[iy, iz, ix]:
            record(point, "outside")
            # An 8-stud halo is enough to locate the opening without flooding
            # the entire exterior of the world.
            if not near[iz, ix]:
                continue
        if point[1] < low_floor - 4:
            record(point, "drop")
            drop += 1
            continue
        for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            xx, zz = ix + dx, iz + dz
            if not (1 <= xx < nx - 1 and 1 <= zz < nz - 1):
                record(point, "world-grid-edge")
                continue
            next_y = None
            for delta in (0, 1, -1, 2, -2, 3, -3):
                yy = iy + delta
                if 1 <= yy < ny - 5 and standable[yy, zz, xx]:
                    next_y = yy
                    break
            if next_y is not None:
                standable[next_y, zz, xx] = False
                queue.append(int((next_y * nz + zz) * nx + xx))
                continue
            # A clear unsupported neighboring capsule can fall through a floor
            # seam. Follow gravity down instead of treating the air as walkable.
            if not blocked[iy, zz, xx]:
                for yy in range(iy - 1, 0, -1):
                    if blocked[yy, zz, xx]:
                        break
                    if standable[yy, zz, xx]:
                        standable[yy, zz, xx] = False
                        queue.append(int((yy * nz + zz) * nx + xx))
                        break
                    if low[1] + yy + .5 < low_floor - 4:
                        p = low + np.array((xx + .5, yy + .5, zz + .5))
                        record(p, "drop")
                        drop += 1
                        break
        if reach % 250000 == 0:
            print(f"FLOOD_PROGRESS state={'open' if open_doors else 'closed'} reached={reach} queue={len(queue)-head}", flush=True)
    records = []
    for c in clusters.values():
        p = c["sum"] / c["count"]
        records.append({"kind": c["kind"], "position": np.round(p, 2).tolist(),
                        "reachableVoxels": c["count"], "nearest": nearest_parts(p, world)})
    records.sort(key=lambda c: (-c["reachableVoxels"], c["position"]))
    del occupied, standable, blocked, allowed, near
    return {"doorState": "open" if open_doors else "closed", "voxelSize": VOXEL,
            "voxelizedParts": n_parts, "reachableVoxels": reach,
            "reachableBounds": {"min": reached_min.tolist(), "max": reached_max.tolist()},
            "exitTransitionVoxels": skipped_exit, "dropEvents": drop,
            "leakVoxels": sum(c["reachableVoxels"] for c in records),
            "clusters": records}


def render_cluster_crops(triangles, clusters, requested_seed):
    if not clusters:
        return
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x, scene.render.resolution_y = 640, 360
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    scene.render.film_transparent = False
    world = bpy.data.worlds.new("Leak diagnostic ambient")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (.35, .42, .37, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = .8
    scene.world = world
    mat = bpy.data.materials.new("Cream tile diagnostic")
    mat.diffuse_color = (.72, .69, .59, 1)
    mat.use_nodes = True
    mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (.72, .69, .59, 1)
    marker_mat = bpy.data.materials.new("Leak exit red")
    marker_mat.diffuse_color = (1, .05, .02, 1)
    marker_mat.use_nodes = True
    marker_mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (1, .05, .02, 1)
    sun = bpy.data.lights.new("Hard diagnostic sun", "SUN")
    sun.energy = 3
    sun.angle = math.radians(.5)
    sun_obj = bpy.data.objects.new("Hard diagnostic sun", sun)
    scene.collection.objects.link(sun_obj)
    sun_obj.rotation_euler = (math.radians(38), math.radians(-22), math.radians(12))
    camera_data = bpy.data.cameras.new("Leak camera")
    camera_data.lens = 20
    camera = bpy.data.objects.new("Leak camera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    basis = np.array(((1, 0, 0), (0, 0, -1), (0, 1, 0)), dtype=float)
    centers = triangles.mean(axis=1)
    for i, cluster in enumerate(clusters):
        origin = np.asarray(cluster["sample"], dtype=float)
        direction = np.asarray(cluster["direction"], dtype=float)
        exit_point = np.asarray(cluster["position"], dtype=float)
        segment = exit_point - origin
        length_sq = max(1, float(np.dot(segment, segment)))
        along = np.clip((centers - origin) @ segment / length_sq, 0, 1)
        distance = np.linalg.norm(centers - (origin + along[:, None] * segment), axis=1)
        selected = triangles[distance < 55]
        if len(selected) == 0:
            selected = triangles[np.argsort(distance)[:500]]
        blender_verts = (selected.reshape(-1, 3) @ basis.T * .28).tolist()
        mesh = bpy.data.meshes.new(f"Leak {i} geometry")
        mesh.from_pydata(blender_verts, [], np.arange(len(blender_verts)).reshape(-1, 3).tolist())
        mesh.materials.append(mat)
        obj = bpy.data.objects.new(mesh.name, mesh)
        scene.collection.objects.link(obj)
        camera.location = Vector(origin @ basis.T * .28)
        aim = Vector((origin + direction * min(80, np.linalg.norm(segment))) @ basis.T * .28)
        camera.rotation_euler = (aim - camera.location).to_track_quat("-Z", "Y").to_euler()
        bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=6, radius=.28,
                                             location=Vector(exit_point @ basis.T * .28))
        marker = bpy.context.object
        marker.name = "Leak exit position"
        marker.data.materials.append(marker_mat)
        target = WORLDS / f"check_{requested_seed}_visual_{i + 1:03d}.png"
        scene.render.filepath = str(target)
        bpy.ops.render.render(write_still=True)
        cluster["screenshot"] = str(target)
        bpy.data.objects.remove(marker, do_unlink=True)
        bpy.data.objects.remove(obj, do_unlink=True)
        bpy.data.meshes.remove(mesh)
        print(f"LEAK_CROP {target}", flush=True)


def run_seed(path, crops=True):
    started = time.monotonic()
    world = json.loads(path.read_text(encoding="utf-8"))
    seed = world["requestedSeed"]
    chunks = load_kit_chunks(world)
    triangles = visual_geometry(world, chunks)
    bvh = make_bvh(triangles)
    visual = visual_check(world, bvh, volume_boxes(world["layout"]))
    del bvh
    collision_closed = collision_check(world, False)
    collision_open = collision_check(world, True)
    if crops:
        render_cluster_crops(triangles, visual["clusters"], seed)
    passed = visual["leakRays"] == 0 and collision_closed["leakVoxels"] == 0 and \
        collision_open["leakVoxels"] == 0
    report = {"requestedSeed": seed, "layoutSeed": world["seed"],
              "builderSha256": world["builderSha256"], "visual": visual,
              "collision": {"doorsClosed": collision_closed, "doorsOpen": collision_open},
              "passed": passed, "elapsedSeconds": round(time.monotonic() - started, 1),
              "limitations": ["The fake Luau dump gives exit slide collision MeshParts as boxes; "
                              "the voxel audit uses a nominal radius-8 annular hull for those 274 pieces."]}
    target = WORLDS / f"check_{seed}.json"
    target.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(f"WORLD_CHECK {seed} visual={visual['leakRays']} rays/{len(visual['clusters'])} clusters "
          f"collisionClosed={collision_closed['leakVoxels']} voxels/"
          f"{len(collision_closed['clusters'])} clusters "
          f"collisionOpen={collision_open['leakVoxels']} voxels/"
          f"{len(collision_open['clusters'])} clusters pass={passed} "
          f"time={report['elapsedSeconds']}s report={target}", flush=True)
    return passed


def main():
    assert bpy.app.background, "Use independent headless Blender"
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("seeds", nargs="*", type=int, default=[837834, 1, 101])
    parser.add_argument("--no-crops", action="store_true", help="fast validation of the audit script")
    args = parser.parse_args(argv)
    all_passed = True
    for seed in args.seeds:
        all_passed = run_seed(WORLDS / f"world_{seed}.json", not args.no_crops) and all_passed
    if not all_passed:
        raise SystemExit(2)


if __name__ == "__main__":
    main()
