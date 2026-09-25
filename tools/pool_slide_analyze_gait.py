"""Offline glTF gait measurements for the recovered Pool Slide rig.

This reads a GLB and never touches Studio or Roblox assets. It reports deformed
sole geometry in model space and the world-space slip implied by a given
in-place-animation reference speed.
"""
import argparse
import json
from pathlib import Path
import sys

import numpy as np
from scipy.spatial.transform import Rotation

sys.path.insert(0, str(Path(__file__).resolve().parent))
from pool_slide_polish_glb import parse_glb, view


def local_matrix(translation, rotation):
    out = np.eye(4)
    out[:3, :3] = Rotation.from_quat(rotation).as_matrix()
    out[:3, 3] = translation
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("glb", type=Path)
    ap.add_argument("--walk-reference", type=float, default=14.85)
    ap.add_argument("--run-reference", type=float, default=36.8)
    args = ap.parse_args()
    gltf, blob = parse_glb(args.glb)
    nodes = gltf["nodes"]
    children = {c for n in nodes for c in n.get("children", [])}
    parents = {c: i for i, n in enumerate(nodes) for c in n.get("children", [])}
    joints = gltf["skins"][0]["joints"]
    ibm_flat = view(gltf, blob, gltf["skins"][0]["inverseBindMatrices"])
    ibm = np.array([row.reshape((4, 4), order="F") for row in ibm_flat])
    primitive = gltf["meshes"][0]["primitives"][0]
    attrs = primitive["attributes"]
    pos = view(gltf, blob, attrs["POSITION"]).astype(float)
    joint_ids = view(gltf, blob, attrs["JOINTS_0"]).astype(int)
    weights = view(gltf, blob, attrs["WEIGHTS_0"]).astype(float)
    homo = np.column_stack((pos, np.ones(len(pos))))
    # Foot-dominant vertices from the actual mesh; no guessed ankle location.
    mask = {side: np.any((joint_ids == idx) & (weights >= 0.5), axis=1)
            for side, idx in (("left", 4), ("right", 7))}
    outsole = {side: foot & (pos[:, 1] < -6.8) for side, foot in mask.items()}
    result = {}
    for anim in gltf["animations"]:
        name = anim["name"]
        if name not in ("Walk", "Run"):
            continue
        channels = {}
        for ch in anim["channels"]:
            sampler = anim["samplers"][ch["sampler"]]
            assert sampler.get("interpolation", "LINEAR") == "LINEAR"
            times = view(gltf, blob, sampler["input"])[:, 0].astype(float)
            values = view(gltf, blob, sampler["output"]).astype(float)
            channels[(ch["target"]["node"], ch["target"]["path"])] = (times, values)
        times = channels[(0, "translation")][0]
        assert all(np.array_equal(t, times) for t, _ in channels.values())
        data = {side: [] for side in mask}
        for frame, at in enumerate(times):
            world = {}
            for idx in joints:
                node = nodes[idx]
                translation = channels[(idx, "translation")][1][frame]
                rotation = channels[(idx, "rotation")][1][frame]
                transform = local_matrix(translation, rotation)
                world[idx] = world[parents[idx]] @ transform if parents.get(idx) in world else transform
            skin = np.array([world[idx] @ ibm[k] for k, idx in enumerate(joints)])
            for side in mask:
                which = outsole[side]
                points = homo[which]
                ids = joint_ids[which]
                wts = weights[which]
                deformed = np.zeros((len(points), 4))
                for k in range(4):
                    deformed += wts[:, k, None] * np.einsum("nij,nj->ni", skin[ids[:, k]], points)
                xyz = deformed[:, :3]
                # Keep a fixed outsole vertex cohort across frames; selecting
                # the currently lowest vertices makes the landmark jump as
                # toe and heel alternate contact.
                data[side].append({"time": round(float(at), 6),
                                   "min_y": float(np.min(xyz[:, 1])),
                                   "p05_y": float(np.quantile(xyz[:, 1], 0.05)),
                                   "sole_z": float(np.median(xyz[:, 2])),
                                   "sole_x": float(np.median(xyz[:, 0])),
                                   "bone_z": float(world[4 if side == "left" else 7][2, 3])})
        reference = args.walk_reference if name == "Walk" else args.run_reference
        duration = float(times[-1])
        # Contact-band travel: world movement is reference_speed * animation
        # time, independent of the actual NPC speed after AdjustSpeed.
        floor = float(min(pos[:, 1]))
        for side, rows in data.items():
            y = np.array([r["min_y"] for r in rows])
            z = np.array([r["sole_z"] for r in rows])
            contact = y <= floor + 0.2
            data[side] = {
                "outsole_vertices": int(outsole[side].sum()),
                "min_y": round(float(y.min()), 4),
                "max_y": round(float(y.max()), 4),
                "min_relative_to_rest_floor": round(float(y.min()-floor), 4),
                "contact_band_frames": int(contact.sum()),
                "sole_z_span": round(float(z.max()-z.min()), 4),
                "max_contact_velocity_z": round(float(np.max(np.abs(np.diff(z)[contact[:-1] & contact[1:]] / np.diff(times)[contact[:-1] & contact[1:]]))) if np.any(contact[:-1] & contact[1:]) else float("nan"), 3),
                "sampled": rows,
            }
        result[name] = {"duration": round(duration, 6), "reference_speed": reference,
                        "ground_distance_per_cycle": round(reference*duration, 4),
                        "rest_floor_y": floor, "feet": data}
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
