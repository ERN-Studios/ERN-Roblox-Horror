"""Convert the exact Pool Slide GLB actions into Roblox KeyframeSequence XML.

The recovered GLB was assembled from live Roblox Bone.CFrames and its channels
are rest-local * Pose.CFrame. Undoing the rest-local transform recovers the
Roblox Pose.CFrame without a coordinate-system guess or Studio round-trip.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import xml.etree.ElementTree as ET

import numpy as np

from pool_slide_polish_glb import parse_glb, qconj, qmul, view


FIELDS = ("X", "Y", "Z", "R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22")


def fmt(value: float) -> str:
    assert math.isfinite(value)
    return format(float(value), ".10g")


def rotate(quaternion: np.ndarray, vector: np.ndarray) -> np.ndarray:
    pure = np.array((vector[0], vector[1], vector[2], 0.0), dtype=np.float64)
    return qmul(qmul(quaternion, pure), qconj(quaternion))[:3]


def matrix(quaternion: np.ndarray) -> np.ndarray:
    x, y, z, w = quaternion / np.linalg.norm(quaternion)
    return np.array(((1 - 2*(y*y + z*z), 2*(x*y - z*w), 2*(x*z + y*w)),
                     (2*(x*y + z*w), 1 - 2*(x*x + z*z), 2*(y*z - x*w)),
                     (2*(x*z - y*w), 2*(y*z + x*w), 1 - 2*(x*x + y*y))), dtype=np.float64)


def prop(parent: ET.Element, tag: str, name: str, value: str) -> None:
    ET.SubElement(parent, tag, {"name": name}).text = value


def sequence_xml(gltf: dict, blob: bytearray, action_name: str) -> tuple[ET.ElementTree, dict]:
    anim = next(a for a in gltf["animations"] if a["name"] == action_name)
    nodes = gltf["nodes"]
    joints = gltf["skins"][0]["joints"]
    assert len(joints) == 20 and joints == list(range(20))
    names = [nodes[i]["name"] for i in joints]
    assert len(set(names)) == 20 and names[0] == "Root"
    parents = {}
    for node_idx in joints:
        for child in nodes[node_idx].get("children", []):
            if child in joints:
                assert child not in parents
                parents[child] = node_idx
    assert set(parents) == set(joints) - {0}
    channels = {}
    all_times = []
    for ch in anim["channels"]:
        idx = ch["target"]["node"]
        path = ch["target"]["path"]
        assert idx in joints and path in ("translation", "rotation")
        sampler = anim["samplers"][ch["sampler"]]
        channels[(idx, path)] = view(gltf, blob, sampler["output"]).astype(np.float64)
        all_times.append(view(gltf, blob, sampler["input"])[:, 0].astype(np.float64))
    assert len(channels) == 40
    times = all_times[0]
    assert len(times) > 2 and abs(times[0]) < 1e-8 and np.all(np.diff(times) > 0)
    assert all(np.array_equal(times, other) for other in all_times)
    assert all(len(arr) == len(times) for arr in channels.values())
    assert action_name in ("Walk", "Run")

    root = ET.Element("roblox", {"version": "4"})
    ref = 0
    def item(parent: ET.Element, cls: str) -> ET.Element:
        nonlocal ref
        result = ET.SubElement(parent, "Item", {"class": cls, "referent": f"RBX{ref}"})
        ref += 1
        return result
    seq = item(root, "KeyframeSequence")
    props = ET.SubElement(seq, "Properties")
    prop(props, "string", "Name", f"Pool Slide {action_name} 1.20x v1")
    prop(props, "bool", "Loop", "true")
    prop(props, "token", "Priority", "1")  # Enum.AnimationPriority.Movement
    max_t_error = 0.0
    max_r_error = 0.0
    per_bone = {}
    for i in joints:
        rest_t = np.asarray(nodes[i].get("translation", (0, 0, 0)), dtype=np.float64)
        rest_q = np.asarray(nodes[i].get("rotation", (0, 0, 0, 1)), dtype=np.float64)
        rest_q /= np.linalg.norm(rest_q)
        animated_t = channels[(i, "translation")]
        animated_q = channels[(i, "rotation")]
        pose_t = np.asarray([rotate(qconj(rest_q), value - rest_t) for value in animated_t])
        pose_q = qmul(np.broadcast_to(qconj(rest_q), animated_q.shape), animated_q)
        pose_q /= np.linalg.norm(pose_q, axis=1)[:, None]
        # Verify that each serialized Pose exactly reconstructs the GLB channel.
        reconstructed_t = np.asarray([rest_t + rotate(rest_q, value) for value in pose_t])
        reconstructed_q = qmul(np.broadcast_to(rest_q, pose_q.shape), pose_q)
        max_t_error = max(max_t_error, float(np.max(np.abs(reconstructed_t - animated_t))))
        max_r_error = max(max_r_error, float(np.max(np.abs(reconstructed_q - animated_q))))
        assert np.max(np.abs(pose_t[0] - pose_t[-1])) < 1e-5
        assert abs(float(np.dot(pose_q[0], pose_q[-1]))) > 0.99999
        per_bone[i] = (pose_t, pose_q)
    assert max_t_error < 1e-5 and max_r_error < 1e-5
    assert np.max(np.abs(per_bone[0][0][:, (0, 2)])) < 1e-4, "Root is not in place"

    children = {i: [] for i in joints}
    for child, parent in parents.items():
        children[parent].append(child)
    for frame_idx, time in enumerate(times):
        key = item(seq, "Keyframe")
        key_props = ET.SubElement(key, "Properties")
        prop(key_props, "string", "Name", "Keyframe")
        prop(key_props, "float", "Time", fmt(time))
        def write_pose(parent_xml: ET.Element, idx: int) -> None:
            pose = item(parent_xml, "Pose")
            p = ET.SubElement(pose, "Properties")
            prop(p, "string", "Name", names[idx])
            t, q = per_bone[idx]
            cf = ET.SubElement(p, "CoordinateFrame", {"name": "CFrame"})
            values = tuple(t[frame_idx]) + tuple(matrix(q[frame_idx]).reshape(-1))
            for tag, value in zip(FIELDS, values):
                ET.SubElement(cf, tag).text = fmt(value)
            prop(p, "float", "Weight", "1")
            prop(p, "float", "MaskWeight", "0")
            prop(p, "token", "EasingDirection", "2")
            prop(p, "token", "EasingStyle", "0")
            for child_idx in children[idx]:
                write_pose(pose, child_idx)
        write_pose(key, 0)
    report = {"clip": action_name, "frames": len(times), "duration_seconds": float(times[-1]),
              "pose_count_per_frame": len(joints), "max_translation_reconstruction_error": max_t_error,
              "max_quaternion_reconstruction_error": max_r_error,
              "root_horizontal_motion_max": float(np.max(np.abs(per_bone[0][0][:, (0, 2)])))}
    return ET.ElementTree(root), report


def validate_xml(path: Path, expected_frames: int) -> None:
    root = ET.parse(path).getroot()
    assert root.tag == "roblox" and root.attrib["version"] == "4"
    seq = root.find("Item")
    assert seq is not None and seq.attrib["class"] == "KeyframeSequence"
    keys = seq.findall("Item")
    assert len(keys) == expected_frames
    for key in keys:
        assert key.attrib["class"] == "Keyframe"
        poses = key.findall(".//Item[@class='Pose']")
        assert len(poses) == 20
        assert len({p.find("Properties/string[@name='Name']").text for p in poses}) == 20
        for pose in poses:
            cf = pose.find("Properties/CoordinateFrame[@name='CFrame']")
            assert cf is not None and len(cf) == 12
            values = [float(cf.find(tag).text) for tag in FIELDS]
            assert all(math.isfinite(v) for v in values)
            R = np.array(values[3:]).reshape(3, 3)
            assert np.max(np.abs(R.T @ R - np.eye(3))) < 2e-5
            assert abs(float(np.linalg.det(R)) - 1) < 2e-5


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("glb", type=Path)
    parser.add_argument("out_dir", type=Path)
    args = parser.parse_args()
    gltf, blob = parse_glb(args.glb)
    args.out_dir.mkdir(parents=True, exist_ok=True)
    reports = []
    for name in ("Walk", "Run"):
        tree, report = sequence_xml(gltf, blob, name)
        path = args.out_dir / f"pool_slide_{name.lower()}_1p20_v1.rbxmx"
        ET.indent(tree, space="  ")
        tree.write(path, encoding="utf-8", xml_declaration=False)
        with path.open("ab") as file:
            file.write(b"\n")
        validate_xml(path, report["frames"])
        assert path.stat().st_size < 20_000_000
        report.update({"file": path.name, "bytes": path.stat().st_size,
                       "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
        reports.append(report)
    print(json.dumps(reports, indent=2))


if __name__ == "__main__":
    main()
