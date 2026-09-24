"""Scale the recovered Pool Slide glTF rig and polish its walk/run in place."""
import argparse
import hashlib
import json
import math
import struct
from pathlib import Path
import numpy as np

WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
DTYPE = {5126: "<f4", 5123: "<u2", 5125: "<u4"}


def parse_glb(path):
    raw = path.read_bytes()
    magic, version, total = struct.unpack_from("<III", raw, 0)
    assert magic == 0x46546C67 and version == 2 and total == len(raw)
    json_length, json_type = struct.unpack_from("<II", raw, 12)
    assert json_type == 0x4E4F534A
    gltf = json.loads(raw[20:20 + json_length])
    bin_offset = 20 + json_length
    bin_length, bin_type = struct.unpack_from("<II", raw, bin_offset)
    assert bin_type == 0x004E4942
    blob = bytearray(raw[bin_offset + 8:bin_offset + 8 + bin_length])
    return gltf, blob


def view(gltf, blob, index):
    accessor = gltf["accessors"][index]
    buffer_view = gltf["bufferViews"][accessor["bufferView"]]
    assert "byteStride" not in buffer_view and accessor.get("byteOffset", 0) == 0
    size = accessor["count"] * WIDTH[accessor["type"]]
    offset = buffer_view.get("byteOffset", 0)
    dtype = np.dtype(DTYPE[accessor["componentType"]])
    shape = (accessor["count"], WIDTH[accessor["type"]])
    assert size * dtype.itemsize == buffer_view["byteLength"]
    return np.frombuffer(blob, dtype=dtype, count=size, offset=offset).reshape(shape)


def qmul(a, b):
    ax, ay, az, aw = np.moveaxis(a, -1, 0)
    bx, by, bz, bw = np.moveaxis(b, -1, 0)
    return np.stack((aw*bx + ax*bw + ay*bz - az*by,
                     aw*by - ax*bz + ay*bw + az*bx,
                     aw*bz + ax*by - ay*bx + az*bw,
                     aw*bw - ax*bx - ay*by - az*bz), axis=-1)


def qconj(q):
    out = np.array(q, dtype=np.float64, copy=True)
    out[..., :3] *= -1
    return out


def qstrength(rotations, rest, strength):
    original = np.asarray(rotations, dtype=np.float64)
    rest = np.asarray(rest, dtype=np.float64)
    delta = qmul(qconj(rest), original)
    delta[delta[:, 3] < 0] *= -1
    vector_length = np.linalg.norm(delta[:, :3], axis=1)
    angle = 2 * np.arctan2(vector_length, np.clip(delta[:, 3], -1, 1))
    scaled_half = angle * strength / 2
    ratio = np.divide(np.sin(scaled_half), vector_length, out=np.full_like(vector_length, strength), where=vector_length > 1e-8)
    powered = np.column_stack((delta[:, :3] * ratio[:, None], np.cos(scaled_half)))
    result = qmul(np.broadcast_to(rest, powered.shape), powered)
    result /= np.linalg.norm(result, axis=1)[:, None]
    result[-1] = result[0]
    return result.astype(np.float32)


def channel_map(anim, nodes):
    return {(nodes[ch["target"]["node"]]["name"], ch["target"]["path"]): anim["samplers"][ch["sampler"]]["output"]
            for ch in anim["channels"]}


def quat_x(angles):
    return np.column_stack((np.sin(angles/2), np.zeros_like(angles), np.zeros_like(angles), np.cos(angles/2)))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--scale", type=float, default=1.2)
    args = parser.parse_args()
    assert 1 <= args.scale <= 1.25
    source_bytes = args.source.read_bytes()
    source_sha = hashlib.sha256(source_bytes).hexdigest()
    assert source_sha == "12e70fe4e0c2724dc50d74add4f7074fe5679408410dafebf96b3b3d52b6a763", source_sha
    gltf, blob = parse_glb(args.source)
    assert [a["name"] for a in gltf["animations"]] == ["Attack", "Run", "Idle", "Walk"]
    assert len(gltf["skins"][0]["joints"]) == 20
    nodes = gltf["nodes"]
    original_rest = {node["name"]: list(node.get("translation", [0, 0, 0])) for node in nodes}
    original_rot = {node["name"]: list(node.get("rotation", [0, 0, 0, 1])) for node in nodes}

    # Mesh vertex positions, bind matrices, node rest locations and every action
    # translation are all scaled together: no object-level scale is left to Roblox.
    for mesh in gltf["meshes"]:
        for primitive in mesh["primitives"]:
            idx = primitive["attributes"]["POSITION"]
            values = view(gltf, blob, idx)
            joints = view(gltf, blob, primitive["attributes"]["JOINTS_0"])
            weights = view(gltf, blob, primitive["attributes"]["WEIGHTS_0"])
            joints[weights == 0] = 0  # no deformation change; valid zero-weight slots
            values *= args.scale
            gltf["accessors"][idx]["min"] = values.min(axis=0).astype(float).tolist()
            gltf["accessors"][idx]["max"] = values.max(axis=0).astype(float).tolist()
    ibm = view(gltf, blob, gltf["skins"][0]["inverseBindMatrices"])
    ibm[:, 12:15] *= args.scale
    for node in nodes:
        if "translation" in node:
            node["translation"] = [float(v) * args.scale for v in node["translation"]]
    for anim in gltf["animations"]:
        for ch in anim["channels"]:
            if ch["target"]["path"] == "translation":
                view(gltf, blob, anim["samplers"][ch["sampler"]]["output"])[:] *= args.scale

    strengths = {
        "Walk": {"Hips": 1.12, "Spine": 1.08, "Chest": 1.13, "Neck": 1.05, "Head": 1.06,
                 "LeftShoulder": 1.06, "RightShoulder": 1.06,
                 "LeftUpperArm": 1.15, "RightUpperArm": 1.15,
                 "LeftLowerArm": 1.15, "RightLowerArm": 1.15,
                 "LeftUpperLeg": 1.17, "RightUpperLeg": 1.17,
                 "LeftLowerLeg": 1.12, "RightLowerLeg": 1.12},
        "Run": {"Hips": 1.17, "Spine": 1.18, "Chest": 1.17, "Neck": 1.08, "Head": 1.07,
                "LeftShoulder": 1.10, "RightShoulder": 1.10,
                "LeftUpperArm": 1.25, "RightUpperArm": 1.25,
                "LeftLowerArm": 1.17, "RightLowerArm": 1.17,
                "LeftUpperLeg": 1.19, "RightUpperLeg": 1.19,
                "LeftLowerLeg": 1.08, "RightLowerLeg": 1.08},
    }
    bob = {"Walk": {"Root": 1.08, "Hips": 1.07}, "Run": {"Root": 1.18, "Hips": 1.08}}
    for anim in gltf["animations"]:
        name = anim["name"]
        if name not in strengths:
            continue
        channels = channel_map(anim, nodes)
        for bone, strength in strengths[name].items():
            rotations = view(gltf, blob, channels[(bone, "rotation")])
            rotations[:] = qstrength(rotations, original_rot[bone], strength)
        for bone, strength in bob[name].items():
            translations = view(gltf, blob, channels[(bone, "translation")])
            rest = np.asarray(original_rest[bone], dtype=np.float32) * args.scale
            translations[:] = rest + (translations - rest) * strength
            translations[-1] = translations[0]
        # Bend the previously rigid foot as the lower leg folds, countering the
        # huge pipe-foot's upward whip while making heel/toe motion visible.
        for side in ("Left", "Right"):
            knee = view(gltf, blob, channels[(side + "LowerLeg", "rotation")]).astype(np.float64)
            knee_rest = np.asarray(original_rot[side + "LowerLeg"], dtype=np.float64)
            delta = qmul(qconj(knee_rest), knee)
            delta[delta[:, 3] < 0] *= -1
            knee_x = 2 * np.arctan2(delta[:, 0], delta[:, 3])
            foot = side + "Foot"
            angles = np.clip(-0.22 * knee_x, -0.32, 0.10)
            source_foot = view(gltf, blob, channels[(foot, "rotation")]).astype(np.float64)
            result = qmul(source_foot, quat_x(angles))
            result /= np.linalg.norm(result, axis=1)[:, None]
            result[-1] = result[0]
            view(gltf, blob, channels[(foot, "rotation")])[:] = result.astype(np.float32)
        anim["extras"] = {"poolSlidePolish": "2026-09-24-v1", "inPlace": True, "scale": args.scale}

    gltf["asset"]["generator"] = "tools/pool_slide_polish_glb.py; exact live rig, scaled/animated 2026-09-24"
    encoded_json = json.dumps(gltf, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    encoded_json += b" " * ((4 - len(encoded_json) % 4) % 4)
    while len(blob) % 4:
        blob.append(0)
    output = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(encoded_json) + 8 + len(blob))
    output += struct.pack("<II", len(encoded_json), 0x4E4F534A) + encoded_json
    output += struct.pack("<II", len(blob), 0x004E4942) + bytes(blob)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(output)
    print(json.dumps({"source": str(args.source), "source_sha256": source_sha,
                      "output": str(args.output), "output_sha256": hashlib.sha256(output).hexdigest(),
                      "bytes": len(output), "scale": args.scale,
                      "triangles": sum(gltf["accessors"][p["indices"]]["count"] // 3 for m in gltf["meshes"] for p in m["primitives"]),
                      "joint_count": len(gltf["skins"][0]["joints"]),
                      "animations": [a["name"] for a in gltf["animations"]]}, indent=2))


if __name__ == "__main__":
    main()

