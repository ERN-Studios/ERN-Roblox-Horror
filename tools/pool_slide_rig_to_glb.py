"""Rebuild the live Pool Slide rig as a Blender-importable GLB.

The source FBX/GLB/BLEND of the Pool Slide is lost (Trello rXhi1SZ8). Studio's
EditableMesh API still reads both uploaded meshes of
ServerStorage.Level2Assets."Level 2 Pool Slide Template" -- geometry, vertex
colours, UVs, per-vertex bone indices/weights and the 20-bone bind pose -- and
dumps them as JSON (see docs/POOL_SLIDE_RIG_CONTRACT_2026-09-23.md for the
Studio snippet). This script turns those two dumps into one skinned glTF 2.0
binary in the template's own model space, in STUDS (1 unit = 1 stud):

    python tools/pool_slide_rig_to_glb.py <mesh_0.json> <mesh_02.json> <out.glb> [clips.json]

clips.json (optional) holds the template's four KeyframeSequences (Idle, Walk,
Run, Attack; loaded with game:GetObjects(animationId) -- NOT through
KeyframeSequenceProvider, whose cached copy a :Destroy() empties). Each Pose is
what Roblox's Animator writes to Bone.Transform, so a bone's animated local
transform is its rest local CFrame times the pose; every clip becomes one glTF
animation (linear, the clips are baked at 60 fps).

EditableMesh positions are normalised to the mesh's own [-1, 1] box; both
meshes were imported at scale 6 (Mesh_0 12.00 tall = 2 x 6), so everything is
multiplied by MESH_SCALE. Mesh_02 (the head piece) is authored in its own space
and sits at HEAD_OFFSET from the model pivot; adding that offset puts both on
the one skeleton, whose Root bone is at the pivot. Winding is already glTF's
counter-clockwise. Vertex colours are converted from sRGB to linear, as glTF
requires.
"""

import json
import math
import struct
import sys

MESH_SCALE = 6.0
# Mesh_02's pivot-relative position read from the live template (studs).
HEAD_OFFSET = (-0.006, 3.283, -0.482)


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def mat_from_cframe(components, scale):
    x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = components
    return [[r00, r01, r02, x * scale], [r10, r11, r12, y * scale],
            [r20, r21, r22, z * scale], [0.0, 0.0, 0.0, 1.0]]


def mat_mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]


def mat_inverse_rigid(m):
    # Rotation part is orthonormal: inverse = [R^T | -R^T t].
    r = [[m[j][i] for j in range(3)] for i in range(3)]
    t = [m[0][3], m[1][3], m[2][3]]
    ti = [-sum(r[i][k] * t[k] for k in range(3)) for i in range(3)]
    return [r[0] + [ti[0]], r[1] + [ti[1]], r[2] + [ti[2]], [0.0, 0.0, 0.0, 1.0]]


def quat_from_matrix(m):
    trace = m[0][0] + m[1][1] + m[2][2]
    if trace > 0:
        s = math.sqrt(trace + 1.0) * 2
        w, x, y, z = 0.25 * s, (m[2][1] - m[1][2]) / s, (m[0][2] - m[2][0]) / s, (m[1][0] - m[0][1]) / s
    elif m[0][0] > m[1][1] and m[0][0] > m[2][2]:
        s = math.sqrt(1.0 + m[0][0] - m[1][1] - m[2][2]) * 2
        w, x, y, z = (m[2][1] - m[1][2]) / s, 0.25 * s, (m[0][1] + m[1][0]) / s, (m[0][2] + m[2][0]) / s
    elif m[1][1] > m[2][2]:
        s = math.sqrt(1.0 + m[1][1] - m[0][0] - m[2][2]) * 2
        w, x, y, z = (m[0][2] - m[2][0]) / s, (m[0][1] + m[1][0]) / s, 0.25 * s, (m[1][2] + m[2][1]) / s
    else:
        s = math.sqrt(1.0 + m[2][2] - m[0][0] - m[1][1]) * 2
        w, x, y, z = (m[1][0] - m[0][1]) / s, (m[0][2] + m[2][0]) / s, (m[1][2] + m[2][1]) / s, 0.25 * s
    length = math.sqrt(w * w + x * x + y * y + z * z)
    return [x / length, y / length, z / length, w / length]


def build_primitive(dump, bone_index, offset):
    """Unique (position, uv, normal, colour) corners -> glTF vertex arrays."""
    remap = [bone_index[b["name"]] for b in dump["bones"]]
    vertices, index_of, indices = [], {}, []
    for face in dump["faces"]:
        for corner in face:
            key = tuple(corner)
            if key not in index_of:
                index_of[key] = len(vertices)
                vertices.append(corner)
            indices.append(index_of[key])
    positions, normals, uvs, colours, joints, weights = [], [], [], [], [], []
    for corner in vertices:
        vi = corner[0]
        p = dump["positions"][vi]
        positions.append([p[0] * MESH_SCALE + offset[0], p[1] * MESH_SCALE + offset[1], p[2] * MESH_SCALE + offset[2]])
        n = corner[3:6]
        length = math.sqrt(sum(c * c for c in n)) or 1.0
        normals.append([c / length for c in n])
        uvs.append(corner[1:3])
        colours.append([srgb_to_linear(corner[6]), srgb_to_linear(corner[7]), srgb_to_linear(corner[8]), corner[9]])
        bones = [remap[b] for b in dump["skinBones"][vi]][:4]
        ws = dump["skinWeights"][vi][:4]
        while len(bones) < 4:
            bones.append(0)
            ws.append(0.0)
        total = sum(ws) or 1.0
        joints.append(bones)
        weights.append([w / total for w in ws])
    return positions, normals, uvs, colours, joints, weights, indices


def add_clips(gltf_nodes, bones, world, clips, add):
    """One glTF animation per clip: translation + rotation channels per bone."""
    rest_local = []
    for i, b in enumerate(bones):
        parent = b["parent"]
        rest_local.append(world[i] if parent < 0 else mat_mul(mat_inverse_rigid(world[parent]), world[i]))
    animations = []
    for clip in clips:
        times = [kf["time"] for kf in clip["keyframes"]]
        if not times:
            continue
        time_accessor = add(times, "f", 5126, "SCALAR", len(times), None, False, True)
        samplers, channels = [], []
        for i, b in enumerate(bones):
            translations, rotations = [], []
            for kf in clip["keyframes"]:
                pose = kf["poses"].get(b["name"])
                local = rest_local[i] if pose is None else mat_mul(rest_local[i], mat_from_cframe(pose, 1.0))
                translations.extend([local[0][3], local[1][3], local[2][3]])
                rotations.extend(quat_from_matrix(local))
            for path, values, type_ in (("translation", translations, "VEC3"), ("rotation", rotations, "VEC4")):
                samplers.append({"input": time_accessor, "output": add(values, "f", 5126, type_, len(times)), "interpolation": "LINEAR"})
                channels.append({"sampler": len(samplers) - 1, "target": {"node": i, "path": path}})
        animations.append({"name": clip["name"], "samplers": samplers, "channels": channels})
    return animations


def main(body_path, head_path, out_path, clips_path=None):
    body = json.load(open(body_path, encoding="utf-8"))
    head = json.load(open(head_path, encoding="utf-8"))
    bones = body["bones"]
    bone_index = {b["name"]: i for i, b in enumerate(bones)}
    world = [mat_from_cframe(b["cframe"], MESH_SCALE) for b in bones]

    blob = bytearray()
    buffer_views, accessors = [], []

    def add(data, fmt, component_type, type_, count, target=None, minmax=False, scalar_minmax=False):
        while len(blob) % 4:
            blob.append(0)
        offset = len(blob)
        blob.extend(struct.pack("<%d%s" % (len(data), fmt), *data))
        view = {"buffer": 0, "byteOffset": offset, "byteLength": len(blob) - offset}
        if target:
            view["target"] = target
        buffer_views.append(view)
        accessor = {"bufferView": len(buffer_views) - 1, "componentType": component_type, "count": count, "type": type_}
        if minmax:
            width = {"VEC3": 3}[type_]
            columns = [data[i::width] for i in range(width)]
            accessor["min"] = [min(c) for c in columns]
            accessor["max"] = [max(c) for c in columns]
        if scalar_minmax:
            accessor["min"], accessor["max"] = [min(data)], [max(data)]
        accessors.append(accessor)
        return len(accessors) - 1

    meshes = []
    for name, dump, offset in (("Mesh_0", body, (0.0, 0.0, 0.0)), ("Mesh_02", head, HEAD_OFFSET)):
        positions, normals, uvs, colours, joints, weights, indices = build_primitive(dump, bone_index, offset)
        flat = lambda rows: [v for row in rows for v in row]
        attributes = {
            "POSITION": add(flat(positions), "f", 5126, "VEC3", len(positions), 34962, True),
            "NORMAL": add(flat(normals), "f", 5126, "VEC3", len(normals), 34962),
            "TEXCOORD_0": add(flat(uvs), "f", 5126, "VEC2", len(uvs), 34962),
            "COLOR_0": add(flat(colours), "f", 5126, "VEC4", len(colours), 34962),
            "JOINTS_0": add(flat(joints), "H", 5123, "VEC4", len(joints), 34962),
            "WEIGHTS_0": add(flat(weights), "f", 5126, "VEC4", len(weights), 34962),
        }
        index_accessor = add(indices, "I", 5125, "SCALAR", len(indices), 34963)
        meshes.append({"name": name, "primitives": [{"attributes": attributes, "indices": index_accessor, "material": 0}]})

    inverse_bind = []
    for m in world:
        inv = mat_inverse_rigid(m)
        inverse_bind.extend(inv[r][c] for c in range(4) for r in range(4))  # column-major
    ibm_accessor = add(inverse_bind, "f", 5126, "MAT4", len(world))

    nodes = []
    for i, b in enumerate(bones):
        parent = b["parent"]
        local = world[i] if parent < 0 else mat_mul(mat_inverse_rigid(world[parent]), world[i])
        nodes.append({"name": b["name"], "translation": [local[0][3], local[1][3], local[2][3]],
                      "rotation": quat_from_matrix(local)})
    for i, b in enumerate(bones):
        children = [j for j, c in enumerate(bones) if c["parent"] == i]
        if children:
            nodes[i]["children"] = children
    root_bones = [i for i, b in enumerate(bones) if b["parent"] < 0]
    armature = len(nodes)
    nodes.append({"name": "PipeEntityRig", "children": root_bones})
    body_node, head_node = len(nodes), len(nodes) + 1
    nodes.append({"name": "Mesh_0", "mesh": 0, "skin": 0})
    nodes.append({"name": "Mesh_02", "mesh": 1, "skin": 0})

    gltf = {
        "asset": {"version": "2.0", "generator": "tools/pool_slide_rig_to_glb.py (live Roblox template, 2026-09-23)"},
        "scene": 0,
        "scenes": [{"name": "Level 2 Pool Slide Template", "nodes": [armature, body_node, head_node]}],
        "nodes": nodes,
        "meshes": meshes,
        "skins": [{"name": "PipeEntityRig", "joints": list(range(len(bones))), "inverseBindMatrices": ibm_accessor,
                   "skeleton": root_bones[0]}],
        "materials": [{"name": "ExactPalette_vertexcolour", "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1],
                                                                                    "metallicFactor": 0, "roughnessFactor": 0.8}}],
        "animations": add_clips(nodes, bones, world, json.load(open(clips_path, encoding="utf-8")), add) if clips_path else [],
        "accessors": accessors,
        "bufferViews": buffer_views,
        "buffers": [{"byteLength": len(blob)}],
    }
    js = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    js += b" " * ((4 - len(js) % 4) % 4)
    while len(blob) % 4:
        blob.append(0)
    with open(out_path, "wb") as out:
        out.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob)))
        out.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        out.write(struct.pack("<II", len(blob), 0x004E4942) + bytes(blob))
    print(f"{out_path}: {len(bones)} bones, meshes {[m['name'] for m in meshes]}, {12 + 8 + len(js) + 8 + len(blob)} bytes")


if __name__ == "__main__":
    main(*sys.argv[1:5])
