"""Render the installed Poolrooms world, directly from dump_world.py JSON.

    D:/Blender/blender.exe -b --factory-startup --python-exit-code 1 -P \
        G:/Roblox/MongoTV/tools/level2_poolrooms/render_world.py -- \
        G:/Blender/Level2_Poolrooms/worlds/world_837834.json [--part-uv anchor|world]

Tiled Part UVs follow the rule measured in a Play client (G:/Roblox/_local/l2fix/studio/TILE_PHASE.md): each face's
texture is anchored at one corner of the face in object space (lattice_audit.ANCHOR), one texture = 8 tiles, the
pitch read from the dump's kit manifest (lattice_audit.tile_of). '--part-uv world' keeps the old world-aligned grid
for comparisons (it is NOT what Roblox draws).

The pure chunk helpers are also used by world_check.py. Wire vertices are
centered on each exported chunk; installed MeshPart Size/CFrame are authoritative
because the world builder stretches some modules after cloning them.
"""
from __future__ import annotations

import base64
import bisect
from collections import Counter
import hashlib
import json
import math
from pathlib import Path
import shutil
import subprocess
import sys

import numpy as np

S = 0.28
ROOT = Path(__file__).resolve().parents[2]
DEFAULT_WORLD = Path("G:/Blender/Level2_Poolrooms/worlds/world_837834.json")
REVIEW_ROOT = Path("G:/Blender/Level2_Poolrooms/review")
TILE_STUDS = 4.8         # one texture (8 tiles) at the old 0.6 pitch: the fallback when no tile is given
PART_UV_MODES = ("anchor", "world")
# Convert Roblox (x right, y up, z back) to Blender metres (x, -z, y).
B = np.array(((1, 0, 0), (0, 0, -1), (0, 1, 0)), dtype=float)


def load_kit_chunks(world):
    """Return {(component, material): decoded chunk}; verify the dump's manifests."""
    chunks = {}
    for job, receipt in world["kitExports"].items():
        path = Path(receipt["path"])
        raw_manifest = path.read_bytes()
        assert hashlib.sha256(raw_manifest).hexdigest() == receipt["sha256"], (job, path)
        manifest = json.loads(raw_manifest)
        for record in manifest["chunks"]:
            key = (record["component"], record["material"])
            assert key not in chunks, key
            wire = (path.parent / "chunks" / f"c{record['id']:05d}.b64").read_text(encoding="ascii").strip()
            assert hashlib.sha256(wire.encode("ascii")).hexdigest() == record["wireSha256"], key
            blob = base64.b64decode(wire)
            assert hashlib.sha256(blob).hexdigest() == record["sha256"], key
            npos, nnorm, nuv, ntri = np.frombuffer(blob, dtype="<u4", count=4)
            offset = 16
            pos = np.frombuffer(blob, dtype="<f4", count=int(npos) * 3, offset=offset).reshape(-1, 3).copy()
            offset += int(npos) * 12
            normal = np.frombuffer(blob, dtype="<f4", count=int(nnorm) * 3, offset=offset).reshape(-1, 3).copy()
            offset += int(nnorm) * 12
            uv = np.frombuffer(blob, dtype="<f4", count=int(nuv) * 2, offset=offset).reshape(-1, 2).copy()
            offset += int(nuv) * 8
            indices = np.frombuffer(blob, dtype="<u4", count=int(ntri) * 9, offset=offset).reshape(-1, 3, 3).copy()
            assert offset + int(ntri) * 36 == len(blob), key
            assert int(indices[:, :, 0].max()) < npos and int(indices[:, :, 1].max()) < nnorm
            assert int(indices[:, :, 2].max()) < nuv and ntri == record["tris"], key
            chunks[key] = {"record": record, "positions": pos, "normals": normal,
                           "uv": uv, "indices": indices, "job": job}
    return chunks


def fixture_chunk(part, chunks):
    """Resolve one installed mesh fixture to its exported material chunk."""
    component = part["fixtureComponent"]
    assert part["fixtureKind"] == "mesh", part["path"]
    # ExitSkylight is renamed ExitLightWell by the builder after cloning.
    key = (component, part["name"].rsplit("_", 1)[-1])
    assert key in chunks, (part["path"], key)
    return chunks[key]


def mesh_triangles_world(part, chunk):
    """Installed chunk triangles in Roblox studs, shape (triangles, 3, xyz)."""
    cframe = np.asarray(part["cframe"], dtype=float)
    rotation = cframe[3:].reshape(3, 3)
    scale = np.asarray(part["size"], dtype=float) / np.asarray(chunk["record"]["size"], dtype=float)
    local = chunk["positions"][chunk["indices"][:, :, 0]] * scale
    return local @ rotation.T + cframe[:3]


def map_mesh_fixtures(world, chunks):
    """Associate every runtime mesh with the component clone that installed it."""
    placements = sorted(world["components"], key=lambda item: item["modelId"])
    ids = [item["modelId"] for item in placements]
    expected = Counter(component for component, _ in chunks)
    counts = Counter()
    result = []
    for part in world["parts"]:
        if part["fixtureKind"] != "mesh":
            continue
        index = bisect.bisect_left(ids, part["id"]) - 1
        assert index >= 0 and placements[index]["component"] == part["fixtureComponent"], part["path"]
        chunk = fixture_chunk(part, chunks)
        counts[index] += 1
        result.append((part, chunk, placements[index]))
    for index, placement in enumerate(placements):
        assert counts[index] == expected[placement["component"]], (placement, counts[index])
    return result


def shots(layout, placements=()):
    """Eye-level locations chosen inside the dumped layout, including seam views."""
    halls, corridors = layout["Halls"], layout["Corridors"]
    by_type = {kind: next((hall for hall in halls if hall["Type"] == kind), None)
               for kind in {hall["Type"] for hall in halls}}

    def inside(placement, hall):
        x, _, z = placement["pivot"][:3]
        return hall["MinX"] <= x <= hall["MaxX"] and hall["MinZ"] <= z <= hall["MaxZ"]

    def placed(prefix, hall):
        return [item for item in placements if item["component"].startswith(prefix) and inside(item, hall)]

    winding = [hall for hall in halls if hall["Type"] == "CurvedChannel" and placed("SwerveS_", hall)]
    if winding:
        by_type["CurvedChannel"] = max(winding, key=lambda hall: hall["Area"])

    def center(hall, dy=8):
        return ((hall["MinX"] + hall["MaxX"]) / 2, hall["FloorY"] + dy,
                (hall["MinZ"] + hall["MaxZ"]) / 2)

    def view(hall, fx, fz, dy=8):
        return ((hall["MinX"] + (hall["MaxX"] - hall["MinX"]) * fx,
                 hall["FloorY"] + 4.5,
                 hall["MinZ"] + (hall["MaxZ"] - hall["MinZ"]) * fz), center(hall, dy))

    specs = [("00_overview", (1650, 1750, -1260), (0, 0, 240), 2600, 50),
             ("00b_top_down", (0, 1900, 240), (0, 0, 240), 2800, 50)]
    for title, typ, fx, fz, dy in (
        ("01_column_hall", "ColumnHall", .22, .10, 9),
        ("02_big_pool", "BigPool", .18, .15, 9),
        ("03_vault_arcade", "VaultArcade", .17, .16, 13),
        ("04_curved_channel", "CurvedChannel", .50, .10, 8),
        ("05_spiral_well", "SpiralWell", .12, .16, 20),
        ("06_paddling_room", "PaddlingRoom", .20, .16, 7),
        ("07_pump_hall", "PumpHall", .28, .20, 5),
        ("09_arrival", "Arrival", .50, .18, 8),
        ("13_chamber", "Chamber", .18, .18, 7)):
        hall = by_type.get(typ)
        if hall is None:
            continue
        eye, target = view(hall, fx, fz, dy)
        cx, _, cz = center(hall)
        if typ == "PumpHall":
            eye, target = (cx - 18, hall["FloorY"] + 4.5, cz + 11), (cx, hall["FloorY"] + 4, cz)
        elif typ == "Arrival":
            door = placed("ArrivalDoor", hall)
            dx, _, dz = door[0]["pivot"][:3] if door else (hall["MinX"], 0, cz)
            eye, target = (cx + 15, hall["FloorY"] + 4.5, cz + 15), \
                          (dx, hall["FloorY"] + 9, dz)
        elif typ == "SpiralWell":
            stairs = placed("SpiralStairWell_", hall)
            wx, _, wz = stairs[0]["pivot"][:3] if stairs else (cx, 0, cz)
            eye = (max(hall["MinX"] + 10, wx - 45), hall["FloorY"] + 4.4,
                   min(hall["MaxZ"] - 10, wz + 35))
            target = (wx, hall["FloorY"] + 21, wz)
        elif typ == "BigPool":
            eye = (hall["MinX"] + 44, hall["FloorY"] + 4.2, hall["MinZ"] + 8)
            target = (hall["MinX"] + 48, hall["FloorY"] + 8, hall["MaxZ"] - 9)
        elif typ == "Chamber":
            eye, target = (cx - 10, hall["FloorY"] + 3.5, cz + 12), \
                          (cx + 11, hall["FloorY"] + 8.2, hall["MinZ"] + 2)
        elif typ == "CurvedChannel":
            curve = placed("SwerveS_", hall)          # an S bulge sits on a wall: look at it from the room
            wx, _, wz = curve[0]["pivot"][:3] if curve else (hall["MaxX"], 0, cz)
            k = min(1.0, 40 / max(math.hypot(cx - wx, cz - wz), 1e-6))
            eye = (wx + (cx - wx) * k, hall["FloorY"] + 4.5, wz + (cz - wz) * k)
            target = (wx, hall["FloorY"] + 10, wz)
        specs.append((title, eye, target, None, 18 if typ == "SpiralWell" else 24))

    exit_hall = by_type.get("ExitHall")
    if exit_hall:
        spiral = placed("ExitSpiral", exit_hall)
        x, _, z = spiral[0]["pivot"][:3] if spiral else \
                  (exit_hall["MaxX"] - 29, 0, (exit_hall["MinZ"] + exit_hall["MaxZ"]) / 2)
        y = exit_hall["FloorY"]
        specs.insert(9, ("08_exit_hall", (x - 95, y + 4.5, z + 80),
                         (x - 25, y + 28, z), None, 16))
        specs.append(("15_exit_platform", (x - 14, y + 79, z + 18),
                      (x + 25, y + 83.3, z - 10), None, 16))

    def corridor_view(title, corridor):
        along = corridor["From"] + 6
        fraction = min(1, 6 / corridor["Length"])
        eye_y = corridor["FromY"] + (corridor["ToY"] - corridor["FromY"]) * fraction + 4.2
        far = corridor["To"] + 14
        if corridor["Axis"] == "X":
            eye, target = (along, eye_y, corridor["Cross"]), \
                          (far, corridor["ToY"] + 5, corridor["Cross"])
        else:
            eye, target = (corridor["Cross"], eye_y, along), \
                          (corridor["Cross"], corridor["ToY"] + 5, far)
        return (title, eye, target, None, 21 if corridor["Width"] <= 12 else 19)

    for title, predicate in (
        ("10_round_tunnel_wet", lambda c: c["Variant"] == "Wet" and c["Kind"] == "Open"),
        ("11_stair_tunnel", lambda c: c["Variant"] == "Stair8" and c["Kind"] == "Open"),
        ("12_narrow_pipe", lambda c: c["Kind"] == "Narrow" and c["Length"] >= 48),
        ("16_round_tunnel_dry", lambda c: c["Variant"] == "Dry" and c["Kind"] == "Open")):
        corridor = next((c for c in corridors if predicate(c)), None)
        if corridor:
            specs.append(corridor_view(title, corridor))

    arrival = layout["Arrival"]
    connector = next(c for c in corridors if arrival["Index"] in (c["A"], c["B"]))
    other_index = connector["B"] if connector["A"] == arrival["Index"] else connector["A"]
    other = next(h for h in halls if h["Index"] == other_index)
    specs.append(("14_connected_spaces", center(arrival, 4.5), center(other, 8), None, 24))
    return sorted(specs, key=lambda shot: shot[0])


def as_blender(position):
    from mathutils import Vector
    return Vector((position[0] * S, -position[2] * S, position[1] * S))


def frame_matrix(cframe, scale=(1, 1, 1)):
    from mathutils import Matrix
    frame = np.asarray(cframe, dtype=float)
    rotation = B @ frame[3:].reshape(3, 3) @ B.T
    # Local Blender coordinates are (Roblox x, -Roblox z, Roblox y).
    rotation = rotation @ np.diag((scale[0], scale[2], scale[1]))
    matrix = Matrix(rotation.tolist()).to_4x4()
    matrix.translation = as_blender(frame[:3])
    return matrix


def chunk_mesh(chunk):
    import bpy
    record = chunk["record"]
    indices = chunk["indices"]
    pn = indices[:, :, :2].reshape(-1, 2)
    pairs, inverse = np.unique(pn, axis=0, return_inverse=True)
    positions = (chunk["positions"][pairs[:, 0]] @ B.T * S).tolist()
    faces = inverse.reshape(-1, 3).tolist()
    mesh = bpy.data.meshes.new(f"{record['component']}_{record['material']}")
    mesh.from_pydata(positions, [], faces)
    mesh.update()
    layer = mesh.uv_layers.new(name="UVMap")
    uv = chunk["uv"][indices[:, :, 2]].reshape(-1, 2)
    for loop, coord in zip(layer.data, uv):
        loop.uv = (float(coord[0]), 1 - float(coord[1]))
    for face in mesh.polygons:
        face.use_smooth = True
    return mesh


def anchor_uv(local, size, texture, anchor):
    """UVs (one unit = one texture = 8 tiles) of one block face given by its vertices in object space: the distance
    from the face's anchored edges along its two axes (anchor = lattice_audit.ANCHOR)."""
    n = np.cross(local[1] - local[0], local[2] - local[0])
    a = int(np.abs(n).argmax())
    (i, si), (j, sj) = anchor[(a, 1 if local[0, a] > 0 else -1)]
    return np.stack(((local[:, i] - si * size[i] / 2) / texture, (local[:, j] - sj * size[j] / 2) / texture), 1)


def part_mesh(part, material, tile=None, uv="anchor"):
    """A visible runtime Part with its exact CFrame. Block faces get tile UVs per the measured face-anchor rule
    (uv='anchor': grout lines every `tile` studs from the face's anchored corner, object space) or the old
    world-aligned grid (uv='world'); cylinder faces keep the world-aligned projection (their rule is unmeasured)."""
    import bpy
    from collision_audit import normalize_cylinder   # lazy: collision_audit imports this module
    from world_check import CYLINDER_SIDES
    part = normalize_cylinder(part)     # a native Roblox cylinder (pressure door, pump lamp) has its axis on local X
    size = np.asarray(part["size"], dtype=float)
    frame = np.asarray(part["cframe"], dtype=float)
    rotation = frame[3:].reshape(3, 3)
    if part["shape"] == "PartType.Cylinder":
        count = CYLINDER_SIDES
        verts = []
        for y in (-size[1] / 2, size[1] / 2):
            for i in range(count):
                angle = math.tau * i / count
                verts.append((math.cos(angle) * size[0] / 2, y,
                              math.sin(angle) * size[2] / 2))
        faces = [tuple(reversed(range(count))), tuple(range(count, 2 * count))]
        faces += [(i, (i + 1) % count, (i + 1) % count + count, i + count)
                  for i in range(count)]
    else:
        x, y, z = size / 2
        verts = [(-x, -y, -z), (x, -y, -z), (x, y, -z), (-x, y, -z),
                 (-x, -y, z), (x, -y, z), (x, y, z), (-x, y, z)]
        faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4),
                 (3, 7, 6, 2), (0, 4, 7, 3), (1, 2, 6, 5)]
    vertices = (np.asarray(verts) @ rotation.T + frame[:3])
    mesh = bpy.data.meshes.new(part["name"])
    mesh.from_pydata((vertices @ B.T * S).tolist(), [], faces)
    mesh.materials.append(material)
    layer = mesh.uv_layers.new(name="UVMap")
    assert uv in PART_UV_MODES, uv
    texture = 8 * tile if tile else TILE_STUDS          # studs per texture (8 x 8 tiles)
    anchored = uv == "anchor" and part["shape"] != "PartType.Cylinder"
    if anchored:
        from lattice_audit import ANCHOR               # lazy: lattice_audit imports this module
    local_all = np.asarray(verts, float)
    for polygon in mesh.polygons:
        face_vertices = vertices[list(polygon.vertices)]
        if anchored:
            coords = anchor_uv(local_all[list(polygon.vertices)], size, texture, ANCHOR)
        else:
            normal = np.cross(face_vertices[1] - face_vertices[0], face_vertices[2] - face_vertices[0])
            axis = int(np.abs(normal).argmax())
            coords = face_vertices[:, (2, 1) if axis == 0 else ((0, 2) if axis == 1 else (0, 1))] / texture
        for loop, coord in zip(polygon.loop_indices, coords):
            layer.data[loop].uv = tuple(coord)
    mesh.update()
    return mesh


def material_for_part(part, cache):
    import bpy
    import prkit as kit
    variant = part["materialVariant"]
    rgb = tuple(round(float(value), 5) for value in part["color"])
    key = (variant, part["material"], rgb)
    if key in cache:
        return cache[key]
    palette = {}                        # Roblox MaterialVariant -> kit material, from the kit's current palette
    for name, (_, mv, _, _) in kit.PALETTE.items():
        if mv:
            palette.setdefault(mv, name)
    if variant in palette:
        base = kit.MATERIALS[kit.material(palette[variant])]["blender"]
        material = base.copy()
        tint = next(node for node in material.node_tree.nodes if node.type == "MIX")
        tint.inputs["B"].default_value = (*(kit.linear(value * 255) for value in rgb), 1)
    else:
        material = bpy.data.materials.new(f"Runtime {variant or part['material']} {rgb}")
        material.use_nodes = True
        bsdf = material.node_tree.nodes.get("Principled BSDF")
        color = tuple(kit.linear(value * 255) for value in rgb)
        bsdf.inputs["Base Color"].default_value = (*color, 1)
        bsdf.inputs["Roughness"].default_value = .28 if "Metal" in part["material"] else .7
        if "Neon" in part["material"]:
            bsdf.inputs["Emission Color"].default_value = (*color, 1)
            bsdf.inputs["Emission Strength"].default_value = 4
    cache[key] = material
    return material


def make_water_material():
    import bpy
    material = bpy.data.materials.new("PR shallow green water")
    material.use_nodes = True
    nodes, links = material.node_tree.nodes, material.node_tree.links
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    clear = nodes.new("ShaderNodeBsdfTransparent")
    clear.inputs["Color"].default_value = (.94, .99, .93, 1)
    shine = nodes.new("ShaderNodeBsdfGlossy")
    shine.inputs["Color"].default_value = (.62, .78, .66, 1)
    shine.inputs["Roughness"].default_value = .07
    mix = nodes.new("ShaderNodeMixShader")
    fresnel = nodes.new("ShaderNodeFresnel")
    fresnel.inputs["IOR"].default_value = 1.333
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = .02
    ramp.color_ramp.elements[0].color = (.13, .13, .13, 1)
    ramp.color_ramp.elements[1].position = .55
    ramp.color_ramp.elements[1].color = (.78, .78, .78, 1)
    links.new(fresnel.outputs["Fac"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], mix.inputs[0])
    links.new(clear.outputs[0], mix.inputs[1])
    links.new(shine.outputs[0], mix.inputs[2])
    links.new(mix.outputs[0], output.inputs["Surface"])
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = .22
    bump.inputs["Distance"].default_value = .035
    noise = nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 2.5
    noise.inputs["Detail"].default_value = 2
    geom = nodes.new("ShaderNodeNewGeometry")
    links.new(geom.outputs["Position"], noise.inputs["Vector"])
    links.new(noise.outputs["Fac"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], shine.inputs["Normal"])
    return material


def add_water(col, region, material):
    import bpy
    cframe = region["cframe"]
    size = region["size"]
    x, z = size[0] * S / 2, size[2] * S / 2
    mesh = bpy.data.meshes.new("Terrain water " + str(region["label"]))
    mesh.from_pydata([(-x, -z, 0), (x, -z, 0), (x, z, 0), (-x, z, 0)], [], [(0, 1, 2, 3)])
    mesh.materials.append(material)
    obj = bpy.data.objects.new(mesh.name, mesh)
    col.objects.link(obj)
    top = list(cframe)
    top[1] += size[1] / 2
    obj.matrix_world = frame_matrix(top)
    obj["world_water"] = True
    return obj


def lighting():
    import bpy
    from mathutils import Vector
    world = bpy.data.worlds.new("Poolrooms green sky")
    world.use_nodes = True
    nodes, links = world.node_tree.nodes, world.node_tree.links
    background = nodes.get("Background")
    background.inputs["Color"].default_value = (.09, .17, .105, 1)
    background.inputs["Strength"].default_value = .32
    sky = nodes.new("ShaderNodeTexSky")
    sky.sky_type = "MULTIPLE_SCATTERING"
    sky.sun_elevation = math.radians(28)
    sky_background = nodes.new("ShaderNodeBackground")
    sky_background.inputs["Strength"].default_value = .8
    links.new(sky.outputs["Color"], sky_background.inputs["Color"])
    path = nodes.new("ShaderNodeLightPath")
    mix = nodes.new("ShaderNodeMixShader")
    links.new(path.outputs["Is Camera Ray"], mix.inputs[0])
    links.new(background.outputs[0], mix.inputs[1])
    links.new(sky_background.outputs[0], mix.inputs[2])
    links.new(mix.outputs[0], nodes["World Output"].inputs["Surface"])
    bpy.context.scene.world = world
    sun_data = bpy.data.lights.new("Hard warm daylight 5300 K", "SUN")
    sun_data.energy = 5.0
    sun_data.angle = math.radians(.4)
    sun_data.color = (1, .87, .69)
    sun = bpy.data.objects.new(sun_data.name, sun_data)
    bpy.context.scene.collection.objects.link(sun)
    sun.rotation_euler = Vector((-.2, .12, -1)).normalized().to_track_quat("-Z", "Y").to_euler()
    import prkit as kit
    for name, strength in (("Tile", .025), ("Aqua", .09)):     # TileShade/Worn are retired (FIX_SPEC G1)
        material = kit.MATERIALS[kit.material(name)]["blender"]
        bsdf = material.node_tree.nodes.get("Principled BSDF")
        source = next((link.from_socket for link in material.node_tree.links
                       if link.to_socket == bsdf.inputs["Base Color"]), None)
        if source:
            material.node_tree.links.new(source, bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = strength


def add_review_lights(world, col):
    import bpy
    from mathutils import Vector
    manifests = {}
    for receipt in world["kitExports"].values():
        manifests.update(json.loads(Path(receipt["path"]).read_text())["components"])
    lights = []
    rounds = 0
    for placement in world["components"]:
        component = placement["component"]
        if component == "LightRound":
            rounds += 1
            if rounds % 2:
                continue
        if component not in ("LightRound", "LightWell_R6", "SunSlit", "ExitSkylight") and \
                not component.startswith(("RoundTunnel_", "Pipe_")):
            continue
        pivot = np.asarray(placement["pivot"], dtype=float)
        rotation = pivot[3:].reshape(3, 3)
        for marker in manifests[component]["markers"]:
            name = marker["name"]
            if name not in ("Light", "OpenSky", "LightOpening", "LampLight"):
                continue
            pos = pivot[:3] + rotation @ np.asarray(marker["cf"][:3], dtype=float)
            if name in ("Light", "LampLight"):
                data = bpy.data.lights.new("Warm recessed light", "POINT")
                data.energy = 210 if name == "LampLight" else 145
                data.color = (1, .86, .68)
                data.shadow_soft_size = S * .2
                data.use_shadow = False
            else:
                data = bpy.data.lights.new("Hard daylight through well", "SPOT")
                data.energy = 2800 if component == "LightWell_R6" else 5000
                data.color = (1, .88, .71)
                data.spot_size = math.radians(53 if component == "LightWell_R6" else 68)
                data.spot_blend = .015
                data.shadow_soft_size = S * .08
            obj = bpy.data.objects.new(data.name, data)
            col.objects.link(obj)
            obj.location = as_blender(pos)
            if data.type == "SPOT":
                obj.rotation_euler = (Vector((0, 0, -1))).to_track_quat("-Z", "Y").to_euler()
            lights.append(obj)

    def bounce(position, energy):
        data = bpy.data.lights.new("Warm aperture bounce", "POINT")
        data.energy = energy
        data.color = (1, .86, .68)
        data.shadow_soft_size = S * .2
        data.use_shadow = False
        obj = bpy.data.objects.new(data.name, data)
        col.objects.link(obj)
        obj.location = as_blender(position)
        lights.append(obj)

    wells = [placement["pivot"][:3] for placement in world["components"]
             if placement["component"] == "LightWell_R6"]
    for hall in world["layout"]["Halls"]:
        x = (hall["MinX"] + hall["MaxX"]) / 2
        z = (hall["MinZ"] + hall["MaxZ"]) / 2
        floor = hall["FloorY"]
        if hall["Type"] == "Chamber":
            bounce((x + 9, floor + 11, z - 10), 150)
            continue
        inside = [well for well in wells if hall["MinX"] < well[0] < hall["MaxX"] and
                  hall["MinZ"] < well[2] < hall["MaxZ"]]
        if inside:
            for well in inside:
                bounce((well[0], floor + hall["CeilingClass"] - 6, well[2]), 630)
        else:
            bounce((x, floor + min(hall["CeilingClass"] - 5, 30), z), 540)
        if hall["Type"] == "BigPool":
            for px in range(int(hall["MinX"] + 16), int(hall["MaxX"] - 16), 48):
                for pz in range(int(hall["MinZ"] + 16), int(hall["MaxZ"] - 16), 48):
                    bounce((px, floor + hall["CeilingClass"] - 2, pz), 210)
        if hall["Type"] == "ExitHall":
            source = as_blender((hall["MaxX"] - 73, floor + hall["CeilingClass"] - 16, z + 12))
            target = as_blender((hall["MaxX"] - 58, floor + 28, z + 7))
            data = bpy.data.lights.new("Exit stair daylight", "SPOT")
            data.energy = 4800
            data.color = (1, .87, .68)
            data.spot_size = math.radians(45)
            data.spot_blend = .02
            obj = bpy.data.objects.new(data.name, data)
            col.objects.link(obj)
            obj.location = source
            obj.rotation_euler = (target - source).to_track_quat("-Z", "Y").to_euler()
            lights.append(obj)
    return lights


def build_scene(world, chunks, part_uv="anchor"):
    import bpy
    import prkit as kit
    from lattice_audit import tile_of                 # lazy: lattice_audit imports this module
    tile = tile_of(world)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.engine = "CYCLES"
    col = bpy.data.collections.new("Installed Level 2 world")
    bpy.context.scene.collection.children.link(col)
    lighting()
    kit_materials = {}
    for (component, name), chunk in chunks.items():
        kit.material(name)
        mesh = chunk_mesh(chunk)
        mesh.materials.append(kit.MATERIALS[name]["blender"])
        kit_materials[(component, name)] = mesh
    mesh_fixtures = map_mesh_fixtures(world, chunks)
    for part, chunk, placement in mesh_fixtures:
        key = (chunk["record"]["component"], chunk["record"]["material"])
        obj = bpy.data.objects.new(part["name"], kit_materials[key])
        col.objects.link(obj)
        scale = np.asarray(part["size"]) / np.asarray(chunk["record"]["size"])
        obj.matrix_world = frame_matrix(part["cframe"], scale)
        obj["component"] = placement["component"]
        obj["world_path"] = part["path"]
        obj["overhead"] = placement["component"] == "ExitSkylight"
        obj.visible_shadow = bool(part["castShadow"])
    material_cache = {}
    part_count = 0
    for part in world["parts"]:
        if part["class"] not in ("Part", "WedgePart", "SpawnLocation") or part["transparency"] >= .99:
            continue
        material = material_for_part(part, material_cache)
        mesh = part_mesh(part, material, tile, part_uv)
        obj = bpy.data.objects.new(part["name"], mesh)
        col.objects.link(obj)
        obj["world_path"] = part["path"]
        obj["overhead"] = "Overhead" in part["name"] or "Overhead" in part["parentPath"]
        obj.visible_shadow = bool(part["castShadow"])
        part_count += 1
    water_mat = make_water_material()
    for region in world["terrainWaterRegions"]:
        add_water(col, region, water_mat)
    lights = add_review_lights(world, col)
    print("WORLD_SCENE=" + json.dumps({"parts": part_count, "meshFixtures": len(mesh_fixtures),
                                       "waterRegions": len(world["terrainWaterRegions"]),
                                       "reviewLights": len(lights), "tile": tile, "partUV": part_uv}),
          flush=True)
    return col, lights


def configure_render(samples=64, draft=False):
    import bpy
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 16 if draft else samples
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 960 if draft else 1920
    scene.render.resolution_y = 540 if draft else 1080
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.view_settings.exposure = .35
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = "OPTIX"
        prefs.get_devices()
        for device in prefs.devices:
            device.use = device.type == "OPTIX"
        if any(device.use for device in prefs.devices):
            scene.cycles.device = "GPU"
            print("WORLD_RENDER_DEVICE=OPTIX", flush=True)
        else:
            print("WORLD_RENDER_DEVICE=CPU", flush=True)
    except (KeyError, RuntimeError, TypeError) as exc:
        print("WORLD_RENDER_DEVICE=CPU " + str(exc), flush=True)


def camera(col, eye, target, ortho, lens):
    import bpy
    data = bpy.data.cameras.new("World review camera")
    obj = bpy.data.objects.new(data.name, data)
    col.objects.link(obj)
    obj.location = as_blender(eye)
    obj.rotation_euler = (as_blender(target) - obj.location).to_track_quat("-Z", "Y").to_euler()
    data.clip_end = 4000
    if ortho:
        data.type = "ORTHO"
        data.ortho_scale = ortho * S
    else:
        data.lens = lens
    bpy.context.scene.camera = obj
    return obj


def contact_sheet(out, names):
    python = shutil.which("python")
    assert python, "Python with Pillow is needed to write the review sheet"
    code = '''from PIL import Image,ImageDraw
from pathlib import Path
import json,sys
p=Path(sys.argv[1]); names=json.loads(sys.argv[2]); columns=4; cell_w=600; cell_h=365
sheet=Image.new('RGB',(columns*cell_w,((len(names)+columns-1)//columns)*cell_h),'#17231f')
draw=ImageDraw.Draw(sheet)
for i,name in enumerate(names):
    image=Image.open(p/(name+'.png')).convert('RGB'); image.thumbnail((590,332))
    x=(i%columns)*cell_w; y=(i//columns)*cell_h
    sheet.paste(image,(x+(cell_w-image.width)//2,y+26))
    draw.text((x+8,y+6),name.replace('_',' ').title(),fill='white')
sheet.save(p/'_sheet.jpg',quality=93,subsampling=0)
'''
    subprocess.run([python, "-c", code, str(out), json.dumps(names)], check=True)


def main():
    import bpy
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    world_path = Path(next((arg for arg in args if arg.endswith(".json")), DEFAULT_WORLD))
    draft = "--draft" in args
    only = set(args[args.index("--only") + 1].split(",")) if "--only" in args else None
    samples = int(args[args.index("--samples") + 1]) if "--samples" in args else 64
    part_uv = args[args.index("--part-uv") + 1] if "--part-uv" in args else "anchor"
    assert part_uv in PART_UV_MODES, part_uv
    assert 64 <= samples <= 128 or draft, samples
    world = json.loads(world_path.read_text(encoding="utf-8"))
    root = Path(args[args.index("--out") + 1]) if "--out" in args else REVIEW_ROOT
    out = root / f"WORLD_{world['requestedSeed']}"
    out.mkdir(parents=True, exist_ok=True)
    chunks = load_kit_chunks(world)
    col, lights = build_scene(world, chunks, part_uv)
    configure_render(samples, draft)
    specs = shots(world["layout"], world["components"])
    assert len({item[0] for item in specs}) == len(specs)
    names = []
    for name, eye, target, ortho, lens in specs:
        if only and name not in only:
            continue
        for obj in col.objects:
            if obj.type == "MESH":
                obj.hide_render = (ortho is not None and bool(obj.get("overhead"))) or \
                                  (name == "00b_top_down" and bool(obj.get("world_water")))
        for lamp in lights:
            lamp.hide_render = bool(ortho) or (lamp.location - as_blender(eye)).length > 230 * S
        cam = camera(col, eye, target, ortho, lens)
        path = out / (name + ("_draft" if draft else "") + ".png")
        bpy.context.scene.render.filepath = str(path)
        bpy.ops.render.render(write_still=True)
        print("WORLD_RENDER=" + str(path), flush=True)
        names.append(name)
        bpy.data.objects.remove(cam, do_unlink=True)
    if not draft and not only:
        contact_sheet(out, names)
        print("WORLD_SHEET=" + str(out / "_sheet.jpg"), flush=True)
    print("WORLD_DONE=" + json.dumps({"requestedSeed": world["requestedSeed"],
                                      "actualSeed": world["seed"], "shots": names}), flush=True)


if __name__ == "__main__":
    sys.dont_write_bytecode = True
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    main()
