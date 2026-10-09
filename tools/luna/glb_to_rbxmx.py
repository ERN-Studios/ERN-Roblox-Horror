"""Convert every glTF animation in Luna's skinned GLB into a Roblox KeyframeSequence (.rbxmx).

    python tools/luna/glb_to_rbxmx.py <luna_anim.glb> <out_dir> [--label v1]

Generalised from the Pool Slide converter (worktree wall-depth-v2-20260924, tools/pool_slide_glb_to_rbxmx.py):
Roblox's Animator writes Pose.CFrame into Bone.Transform, and the Open Cloud import keeps each child bone's glTF
local rest transform verbatim, so for every joint  Pose = rest_local^-1 * animated_local  (no axis conversion).
Clip settings come from the animation's glTF extras (Blender action custom properties, export_extras=True):
luna_loop, luna_priority ("Idle" | "Movement" | "Action"), luna_ref_speed.
"""
import argparse
import hashlib
import json
import math
import struct
import xml.etree.ElementTree as ET
from pathlib import Path

import numpy as np

WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
DTYPE = {5126: "<f4", 5123: "<u2", 5125: "<u4", 5121: "<u1"}
FIELDS = ("X", "Y", "Z", "R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22")
PRIORITY = {"Core": 1000, "Idle": 0, "Movement": 1, "Action": 2}


def parse_glb(path):
    raw = Path(path).read_bytes()
    magic, version, total = struct.unpack_from("<III", raw, 0)
    assert magic == 0x46546C67 and version == 2 and total == len(raw)
    jlen, jtype = struct.unpack_from("<II", raw, 12)
    assert jtype == 0x4E4F534A
    gltf = json.loads(raw[20:20 + jlen])
    boff = 20 + jlen
    blen, btype = struct.unpack_from("<II", raw, boff)
    assert btype == 0x004E4942
    return gltf, raw[boff + 8:boff + 8 + blen]


def view(gltf, blob, index):
    acc = gltf["accessors"][index]
    bv = gltf["bufferViews"][acc["bufferView"]]
    width = WIDTH[acc["type"]]
    dtype = np.dtype(DTYPE[acc["componentType"]])
    assert bv.get("byteStride", width * dtype.itemsize) == width * dtype.itemsize, "interleaved accessor"
    offset = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    return np.frombuffer(blob, dtype=dtype, count=acc["count"] * width, offset=offset).reshape(acc["count"], width)


def qmul(a, b):
    ax, ay, az, aw = np.moveaxis(a, -1, 0)
    bx, by, bz, bw = np.moveaxis(b, -1, 0)
    return np.stack((aw * bx + ax * bw + ay * bz - az * by, aw * by - ax * bz + ay * bw + az * bx,
                     aw * bz + ax * by - ay * bx + az * bw, aw * bw - ax * bx - ay * by - az * bz), axis=-1)


def qconj(q):
    out = np.array(q, dtype=np.float64, copy=True)
    out[..., :3] *= -1
    return out


def rotate(q, v):
    pure = np.concatenate([v, np.zeros(v.shape[:-1] + (1,))], axis=-1)
    return qmul(qmul(q, pure), qconj(q))[..., :3]


def matrix(q):
    x, y, z, w = q / np.linalg.norm(q)
    return np.array(((1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)),
                     (2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)),
                     (2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y))))


def fmt(v):
    assert math.isfinite(v)
    return format(float(v), ".9g")


def prop(parent, tag, name, value):
    ET.SubElement(parent, tag, {"name": name}).text = value


def skeleton(gltf):
    nodes = gltf["nodes"]
    joints = gltf["skins"][0]["joints"]
    assert len(gltf["skins"]) == 1
    names = [nodes[j]["name"] for j in joints]
    assert len(set(names)) == len(names)
    parent = {}
    for j in joints:
        for c in nodes[j].get("children", []):
            if c in joints:
                parent[c] = j
    roots = [j for j in joints if j not in parent]
    assert len(roots) == 1, roots
    children = {j: [c for c in nodes[j].get("children", []) if c in joints] for j in joints}
    return joints, roots[0], children


def sequence(gltf, blob, anim, label):
    nodes = gltf["nodes"]
    joints, root, children = skeleton(gltf)
    extras = anim.get("extras", {})
    loop = bool(extras.get("luna_loop", False))
    priority = extras.get("luna_priority", "Action")
    times, chan = None, {}
    for ch in anim["channels"]:
        node, path = ch["target"].get("node"), ch["target"]["path"]
        if node not in joints:
            continue
        s = anim["samplers"][ch["sampler"]]
        assert s.get("interpolation", "LINEAR") in ("LINEAR", "STEP"), s.get("interpolation")
        t = view(gltf, blob, s["input"])[:, 0].astype(np.float64)
        out = view(gltf, blob, s["output"]).astype(np.float64)
        if path == "scale":
            assert np.allclose(out, 1, atol=1e-3), (nodes[node]["name"], "scaled bone")
            continue
        if times is None or len(t) > len(times):
            times = t
        chan[(node, path)] = (t, out)
    assert times is not None and len(times) >= 2 and abs(times[0]) < 1e-6 and np.all(np.diff(times) > 0)

    def sample(node, path, rest):
        if (node, path) not in chan:
            return np.tile(rest, (len(times), 1))
        t, out = chan[(node, path)]
        if len(t) == len(times) and np.allclose(t, times):
            return out
        if path == "translation":
            return np.stack([np.interp(times, t, out[:, k]) for k in range(3)], axis=1)
        idx = np.clip(np.searchsorted(t, times) , 1, len(t) - 1)        # nlerp between neighbours
        a, b = out[idx - 1], out[idx].copy()
        w = ((times - t[idx - 1]) / (t[idx] - t[idx - 1]))[:, None].clip(0, 1)
        b[np.sum(a * b, axis=1) < 0] *= -1
        q = a * (1 - w) + b * w
        return q / np.linalg.norm(q, axis=1)[:, None]

    poses, err_t, err_r = {}, 0.0, 0.0
    for j in joints:
        rt = np.asarray(nodes[j].get("translation", (0, 0, 0)), dtype=np.float64)
        rq = np.asarray(nodes[j].get("rotation", (0, 0, 0, 1)), dtype=np.float64)
        rq /= np.linalg.norm(rq)
        at, aq = sample(j, "translation", rt), sample(j, "rotation", rq)
        rqb = np.broadcast_to(rq, aq.shape)
        pt = rotate(np.broadcast_to(qconj(rq), aq.shape), at - rt)
        pq = qmul(qconj(rqb), aq)
        pq /= np.linalg.norm(pq, axis=1)[:, None]
        err_t = max(err_t, float(np.abs(rt + rotate(rqb, pt) - at).max()))
        rec = qmul(rqb, pq)
        err_r = max(err_r, float(np.min(np.stack([np.abs(rec - aq).max(1), np.abs(rec + aq).max(1)]), axis=0).max()))
        poses[j] = (pt, pq)
    assert err_t < 1e-5 and err_r < 1e-5, (err_t, err_r)
    if loop:
        for j, (pt, pq) in poses.items():
            assert np.abs(pt[0] - pt[-1]).max() < 1e-4 and abs(float(np.dot(pq[0], pq[-1]))) > 0.9999, \
                (anim["name"], nodes[j]["name"], "loop seam")
    rx = poses[root][0]
    assert np.abs(rx).max() < 1e-4, "root bone moves; clips must be in place"

    xml = ET.Element("roblox", {"version": "4"})
    ref = [0]

    def item(parent, cls):
        e = ET.SubElement(parent, "Item", {"class": cls, "referent": f"RBX{ref[0]}"})
        ref[0] += 1
        return e

    seq = item(xml, "KeyframeSequence")
    p = ET.SubElement(seq, "Properties")
    prop(p, "string", "Name", f"Luna {anim['name']} {label}")
    prop(p, "bool", "Loop", "true" if loop else "false")
    prop(p, "token", "Priority", str(PRIORITY[priority]))
    for fi, t in enumerate(times):
        key = item(seq, "Keyframe")
        kp = ET.SubElement(key, "Properties")
        prop(kp, "string", "Name", "Keyframe")
        prop(kp, "float", "Time", fmt(t))

        def write(parent, j):
            pose = item(parent, "Pose")
            pp = ET.SubElement(pose, "Properties")
            prop(pp, "string", "Name", nodes[j]["name"])
            cf = ET.SubElement(pp, "CoordinateFrame", {"name": "CFrame"})
            pt, pq = poses[j]
            for tag, v in zip(FIELDS, tuple(pt[fi]) + tuple(matrix(pq[fi]).reshape(-1))):
                ET.SubElement(cf, tag).text = fmt(v)
            prop(pp, "float", "Weight", "1")
            prop(pp, "float", "MaskWeight", "0")
            prop(pp, "token", "EasingDirection", "2")
            prop(pp, "token", "EasingStyle", "0")
            for c in children[j]:
                write(pose, c)

        write(key, root)
    meta = {"clip": anim["name"], "frames": len(times), "duration": float(times[-1]), "loop": loop, "priority": priority,
            "ref_speed": extras.get("luna_ref_speed"), "bones": len(joints), "max_err_t": err_t, "max_err_r": err_r}
    return ET.ElementTree(xml), meta


def validate(path, frames, bones):
    root = ET.parse(path).getroot()
    seq = root.find("Item")
    assert seq.attrib["class"] == "KeyframeSequence"
    keys = seq.findall("Item")
    assert len(keys) == frames
    for key in keys:
        poses = key.findall(".//Item[@class='Pose']")
        assert len(poses) == bones and len({x.find("Properties/string").text for x in poses}) == bones
        for pose in poses:
            v = [float(pose.find(f"Properties/CoordinateFrame/{t}").text) for t in FIELDS]
            R = np.array(v[3:]).reshape(3, 3)
            assert np.abs(R.T @ R - np.eye(3)).max() < 2e-5 and abs(np.linalg.det(R) - 1) < 2e-5


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("glb")
    ap.add_argument("out_dir", type=Path)
    ap.add_argument("--label", default="v1")
    a = ap.parse_args()
    gltf, blob = parse_glb(a.glb)
    a.out_dir.mkdir(parents=True, exist_ok=True)
    report = []
    for anim in gltf.get("animations", []):
        tree, meta = sequence(gltf, blob, anim, a.label)
        path = a.out_dir / f"luna_{anim['name'].lower()}_{a.label}.rbxmx"
        tree.write(path, encoding="utf-8", xml_declaration=False)
        validate(path, meta["frames"], meta["bones"])
        meta.update(file=path.name, bytes=path.stat().st_size, sha256=hashlib.sha256(path.read_bytes()).hexdigest())
        report.append(meta)
        print(json.dumps(meta))
    (a.out_dir / f"clips_{a.label}.json").write_text(json.dumps(report, indent=1) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
