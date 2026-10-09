"""Bake a restrained gameplay walk from the correctly retargeted Blender clip."""

from __future__ import annotations

import json
import math
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets" / "animations" / "entity" / "keyframes_v3" / "walk.json"
OUTPUT = SOURCE.with_name("walk_restrained.json")


def damp_quaternion(values: list[float], factor: float) -> list[float]:
    x, y, z, w = values
    if w < 0:
        x, y, z, w = -x, -y, -z, -w
    w = max(-1.0, min(1.0, w))
    half_angle = math.acos(w)
    sine = math.sin(half_angle)
    if sine < 1e-8:
        return [0.0, 0.0, 0.0, 1.0]
    scale = math.sin(half_angle * factor) / sine
    return [x * scale, y * scale, z * scale, math.cos(half_angle * factor)]


def rotation_factor(name: str) -> float:
    if name == "Hips":
        return 0.42
    if name in {"Spine02", "Spine01", "Spine", "neck", "Head"}:
        return 0.5
    if "Shoulder" in name or name.endswith("Arm"):
        return 0.58
    if "ForeArm" in name or name.endswith("Hand"):
        return 0.72
    # Preserve the authored foot planting while slightly calming the very wide
    # thigh arcs that made the locomotion read as a dance.
    if "UpLeg" in name:
        return 0.82
    return 1.0


def main() -> int:
    payload = json.loads(SOURCE.read_text(encoding="utf-8"))
    payload["name"] = "Walk_Restrained"
    payload["retarget"] = "global-pose-delta-v6-restrained-walk"
    for _, transforms in payload["frames"]:
        for transform in transforms:
            name = transform[0]
            if name == "Hips":
                transform[1] *= 0.2
                transform[2] *= 0.45
                transform[3] *= 0.2
            transform[4:8] = [round(value, 7) for value in damp_quaternion(
                transform[4:8], rotation_factor(name))]
    OUTPUT.write_text(json.dumps(payload, separators=(",", ":")), encoding="utf-8")
    print(f"WROTE {OUTPUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
