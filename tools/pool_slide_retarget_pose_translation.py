"""Make an offline Pool Slide A/B candidate for the ScaleTo(6.6) Studio rig.

Only Roblox Pose.CFrame translation is divided by 1.20. Rotations, keyframe
times, easing, rig hierarchy, loop flags, and the original candidate are left
unchanged. This does not upload or modify Studio assets.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import xml.etree.ElementTree as ET

from pool_slide_glb_to_rbxmx import fmt, validate_xml


SCALE = 1.20
TRANSLATION = ("X", "Y", "Z")
ROTATION = ("R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22")


def keyframes(tree):
    seq = tree.getroot().find("Item")
    assert seq is not None and seq.attrib.get("class") == "KeyframeSequence"
    return seq, seq.findall("Item[@class='Keyframe']")


def pose_map(key):
    poses = key.findall(".//Item[@class='Pose']")
    result = {p.find("Properties/string[@name='Name']").text: p for p in poses}
    assert len(result) == len(poses) == 20
    return result


def cf(pose):
    result = pose.find("Properties/CoordinateFrame[@name='CFrame']")
    assert result is not None
    return result


def process(source: Path, output: Path, name: str):
    original = ET.parse(source)
    candidate = ET.parse(source)
    old_seq, old_keys = keyframes(original)
    new_seq, new_keys = keyframes(candidate)
    assert old_seq.find("Properties/bool[@name='Loop']").text == "true"
    assert len(old_keys) == len(new_keys) == (64 if name == "Walk" else 39)
    new_seq.find("Properties/string[@name='Name']").text = f"Pool Slide {name} v2 Studio Scale Neutral"
    max_translation_error = 0.0
    changed_pose_components = 0
    for old_key, new_key in zip(old_keys, new_keys):
        assert old_key.find("Properties/float[@name='Time']").text == new_key.find("Properties/float[@name='Time']").text
        old_poses = pose_map(old_key)
        new_poses = pose_map(new_key)
        assert old_poses.keys() == new_poses.keys()
        for bone in old_poses:
            old_cf, new_cf = cf(old_poses[bone]), cf(new_poses[bone])
            assert all(old_cf.find(tag).text == new_cf.find(tag).text for tag in ROTATION)
            for tag in TRANSLATION:
                value = float(old_cf.find(tag).text)
                assert math.isfinite(value)
                scaled = value / SCALE
                new_cf.find(tag).text = fmt(scaled)
                max_translation_error = max(max_translation_error, abs(float(new_cf.find(tag).text)-scaled))
                if abs(value) > 1e-7:
                    changed_pose_components += 1
    assert changed_pose_components > 0
    output.parent.mkdir(parents=True, exist_ok=True)
    ET.indent(candidate, space="  ")
    candidate.write(output, encoding="utf-8", xml_declaration=False)
    with output.open("ab") as f:
        f.write(b"\n")
    validate_xml(output, len(new_keys))
    # Loop seam, key times and rotation matrices survive XML serialization.
    _, check_keys = keyframes(ET.parse(output))
    for old_key, check_key in zip(old_keys, check_keys):
        assert old_key.find("Properties/float[@name='Time']").text == check_key.find("Properties/float[@name='Time']").text
        for bone, old_pose in pose_map(old_key).items():
            check_pose = pose_map(check_key)[bone]
            assert all(cf(old_pose).find(tag).text == cf(check_pose).find(tag).text for tag in ROTATION)
            assert all(abs(float(cf(check_pose).find(tag).text)-float(cf(old_pose).find(tag).text)/SCALE) < 1e-8
                       for tag in TRANSLATION)
    first, last = pose_map(check_keys[0]), pose_map(check_keys[-1])
    max_loop_error = max(abs(float(cf(first[bone]).find(tag).text)-float(cf(last[bone]).find(tag).text))
                         for bone in first for tag in TRANSLATION + ROTATION)
    assert max_loop_error < 1e-5
    assert max_translation_error < 1e-8
    return {"clip": name, "input": str(source), "output": str(output),
            "frames": len(new_keys), "poses_per_frame": 20,
            "pose_translation_multiplier": 1/SCALE,
            "changed_nonzero_components": changed_pose_components,
            "max_translation_roundtrip_error": max_translation_error,
            "max_loop_seam_error": max_loop_error,
            "rotations_and_times_unchanged": True,
            "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
            "output_sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
            "output_bytes": output.stat().st_size}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("source_dir", type=Path)
    ap.add_argument("output_dir", type=Path)
    args = ap.parse_args()
    result = []
    for name in ("Walk", "Run"):
        stem = name.lower()
        source = args.source_dir / f"pool_slide_{stem}_1p20_v2-candidate.rbxmx"
        output = args.output_dir / f"pool_slide_{stem}_v2-scale-neutral.rbxmx"
        result.append(process(source, output, name))
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
