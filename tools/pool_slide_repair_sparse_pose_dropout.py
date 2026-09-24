"""Repair interleaved rest-pose dropouts in Pool Slide Walk/Run v1 GLB.

The live clip recovery contained sparse authored poses. The v1 GLB converter
filled absent poses with rest transforms, producing an all-bone rest flash on
31/64 Walk and 19/39 Run frames. This makes an OFFLINE candidate only. It does
not upload assets, modify the model/rig, or touch Idle/Attack.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import struct

import numpy as np

from pool_slide_polish_glb import parse_glb, view


V1_SHA256 = "d68ae9643bdf66e50cde89daff9235f0980ab328bf571a8ffbfca0cf6aba7926"


def slerp(a, b, weight):
    a = np.asarray(a, dtype=np.float64)
    b = np.asarray(b, dtype=np.float64)
    a /= np.linalg.norm(a)
    b /= np.linalg.norm(b)
    dot = float(np.dot(a, b))
    if dot < 0:
        b = -b
        dot = -dot
    dot = min(1.0, max(-1.0, dot))
    if dot > 0.9995:
        result = (1-weight)*a + weight*b
    else:
        theta = math.acos(dot)
        result = (math.sin((1-weight)*theta)*a + math.sin(weight*theta)*b)/math.sin(theta)
    return result/np.linalg.norm(result)


def repair(gltf, blob):
    nodes = gltf["nodes"]
    report = {}
    for anim in gltf["animations"]:
        name = anim["name"]
        if name not in ("Walk", "Run"):
            continue
        channels = {(ch["target"]["node"], ch["target"]["path"]):
                    view(gltf, blob, anim["samplers"][ch["sampler"]]["output"])
                    for ch in anim["channels"]}
        times = view(gltf, blob, anim["samplers"][0]["input"])[:, 0].astype(float)
        assert len(channels) == 40
        expected = 31 if name == "Walk" else 19
        dropouts = []
        for i in range(1, len(times)-1):
            all_rest = True
            for node in range(20):
                rest = np.asarray(nodes[node].get("rotation", (0, 0, 0, 1)))
                actual = channels[(node, "rotation")][i]
                if min(np.max(np.abs(actual-rest)), np.max(np.abs(actual+rest))) > 1e-6:
                    all_rest = False
                    break
            if all_rest:
                dropouts.append(i)
        assert len(dropouts) == expected, (name, len(dropouts))
        assert all(i-1 not in dropouts and i+1 not in dropouts for i in dropouts)
        before = {key: np.array(values, copy=True) for key, values in channels.items()}
        changed = {"rotation": 0, "translation": 0}
        for i in dropouts:
            alpha = (times[i]-times[i-1])/(times[i+1]-times[i-1])
            for node in range(20):
                q = channels[(node, "rotation")]
                q[i] = slerp(before[(node, "rotation")][i-1],
                             before[(node, "rotation")][i+1], alpha)
                changed["rotation"] += 1
                t = channels[(node, "translation")]
                rest = np.asarray(nodes[node].get("translation", (0, 0, 0)))
                # Root's bob is authored at these timestamps; preserve it.
                if np.max(np.abs(t[i]-rest)) <= 1e-6:
                    t[i] = (1-alpha)*before[(node, "translation")][i-1] + alpha*before[(node, "translation")][i+1]
                    changed["translation"] += 1
        anim["extras"] = {**anim.get("extras", {}), "poolSlideSparsePoseRepair": "v2-offline-candidate",
                          "repairedRestDropoutFrames": len(dropouts)}
        report[name] = {"frames": len(times), "duration": float(times[-1]),
                        "dropout_frame_indices": dropouts,
                        "repaired_channels": changed,
                        "first_last_unchanged": all(np.array_equal(values[0], before[key][0])
                                                    and np.array_equal(values[-1], before[key][-1])
                                                    for key, values in channels.items())}
        assert report[name]["first_last_unchanged"]
    return report


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    digest = hashlib.sha256(args.source.read_bytes()).hexdigest()
    assert digest == V1_SHA256, ("unexpected source", digest)
    gltf, blob = parse_glb(args.source)
    report = repair(gltf, blob)
    gltf["asset"]["generator"] = "tools/pool_slide_repair_sparse_pose_dropout.py; v2 offline candidate"
    encoded_json = json.dumps(gltf, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    encoded_json += b" " * ((4-len(encoded_json)%4)%4)
    while len(blob)%4:
        blob.append(0)
    output = struct.pack("<III", 0x46546C67, 2, 12+8+len(encoded_json)+8+len(blob))
    output += struct.pack("<II", len(encoded_json), 0x4E4F534A) + encoded_json
    output += struct.pack("<II", len(blob), 0x004E4942) + bytes(blob)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(output)
    report["output"] = str(args.output)
    report["sha256"] = hashlib.sha256(output).hexdigest()
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
