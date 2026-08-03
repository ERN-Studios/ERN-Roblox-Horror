"""Bake corrected Run and Kill clips from the verified v5 Blender retarget."""

from __future__ import annotations

import json
import math
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets" / "animations" / "entity" / "keyframes_v3"


def normalize(q: list[float]) -> list[float]:
    length = math.sqrt(sum(value * value for value in q))
    return [value / length for value in q]


def multiply(a: list[float], b: list[float]) -> list[float]:
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return normalize([
        aw * bx + ax * bw + ay * bz - az * by,
        aw * by - ax * bz + ay * bw + az * bx,
        aw * bz + ax * by - ay * bx + az * bw,
        aw * bw - ax * bx - ay * by - az * bz,
    ])


def x_rotation(degrees: float) -> list[float]:
    half = math.radians(degrees) * 0.5
    return [math.sin(half), 0.0, 0.0, math.cos(half)]


def damp(q: list[float], factor: float) -> list[float]:
    x, y, z, w = normalize(q)
    if w < 0:
        x, y, z, w = -x, -y, -z, -w
    half = math.acos(max(-1.0, min(1.0, w)))
    sine = math.sin(half)
    if sine < 1e-8:
        return [0.0, 0.0, 0.0, 1.0]
    scale = math.sin(half * factor) / sine
    return [x * scale, y * scale, z * scale, math.cos(half * factor)]


def clamp_angle(q: list[float], maximum_degrees: float) -> list[float]:
    q = normalize(q)
    angle = 2 * math.degrees(math.acos(max(-1.0, min(1.0, abs(q[3])))))
    return damp(q, maximum_degrees / angle) if angle > maximum_degrees else q


def slerp(a: list[float], b: list[float], alpha: float) -> list[float]:
    """Shortest-path quaternion interpolation."""
    a = normalize(a)
    b = normalize(b)
    dot = sum(x * y for x, y in zip(a, b))
    if dot < 0:
        b = [-value for value in b]
        dot = -dot
    alpha = max(0.0, min(1.0, alpha))
    if dot > 0.9995:
        return normalize([x + (y - x) * alpha for x, y in zip(a, b)])
    theta = math.acos(max(-1.0, min(1.0, dot)))
    sine = math.sin(theta)
    return normalize([
        (math.sin((1 - alpha) * theta) * x + math.sin(alpha * theta) * y) / sine
        for x, y in zip(a, b)
    ])


def bake_run() -> None:
    # The original Blender Run action drives both thighs mostly in the same
    # rotational direction. Stop inheriting that broken lower body entirely.
    # Start from the accepted restrained Walk and turn it into a short, stronger
    # predatory jog while preserving its clean alternating gait.
    payload = json.loads((SOURCE / "walk_restrained.json").read_text(encoding="utf-8"))
    payload["name"] = "Run_PredatoryJog"
    payload["retarget"] = "global-pose-delta-v8-walk-derived-predatory-jog"
    for frame in payload["frames"]:
        frame[0] = round(frame[0] * 0.62, 6)
    for _, transforms in payload["frames"]:
        for transform in transforms:
            name = transform[0]
            q = transform[4:8]
            if name == "Hips":
                q = multiply(q, x_rotation(-5))
            elif name == "Spine02":
                q = multiply(q, x_rotation(-3))
            elif "UpLeg" in name:
                q = damp(q, 1.22)
            elif name.endswith("Leg"):
                q = damp(q, 1.14)
            elif "Shoulder" in name:
                q = damp(q, 1.12)
            elif "ForeArm" in name:
                q = damp(q, 1.08)
            elif name.endswith("Arm"):
                q = damp(q, 1.28)
            transform[4:8] = [round(value, 7) for value in q]
    (SOURCE / "run_chase_corrected.json").write_text(
        json.dumps(payload, separators=(",", ":")), encoding="utf-8")


def bake_kill() -> None:
    payload = json.loads((SOURCE / "kill_groundpinpunch.json").read_text(encoding="utf-8"))
    payload["name"] = "Kill_CloseHunchPunch"
    payload["retarget"] = "global-pose-delta-v9-side-windup-ground-punch"
    hunch_angles = {"Hips": -8, "Spine02": -12, "Spine01": -10, "Spine": -10}
    # Solved against the live v3 Studio rig: this points the upper arm outward
    # to Entity-right and slightly upward. The old clip's rotation axis sent the
    # elbow across/behind the helmet even after its total angle was clamped.
    right_arm_side_pose = [0.05963, 0.0, -0.32719, 0.94307]
    for time_value, transforms in payload["frames"]:
        hunch = max(0.0, min(1.0, (time_value - 1.05) / 0.75))
        hunch = hunch * hunch * (3 - 2 * hunch)
        for transform in transforms:
            name = transform[0]
            q = transform[4:8]
            if name in hunch_angles:
                q = multiply(q, x_rotation(hunch_angles[name] * hunch))
            # Move the wind-up laterally beside the helmet, hold it there, then
            # blend back into the authored downward impact instead of travelling
            # behind the head and cutting through the body.
            if 2.9 <= time_value <= 4.2:
                if name == "RightArm":
                    q = clamp_angle(q, 58)
                    rise = max(0.0, min(1.0, (time_value - 2.84) / 0.30))
                    rise = rise * rise * (3 - 2 * rise)
                    release = max(0.0, min(1.0, (3.96 - time_value) / 0.24))
                    release = release * release * (3 - 2 * release)
                    q = slerp(q, right_arm_side_pose, rise * release)
                elif name == "RightForeArm":
                    q = clamp_angle(q, 46)
                elif name == "LeftArm":
                    q = clamp_angle(q, 72)
            transform[4:8] = [round(value, 7) for value in q]
    (SOURCE / "kill_hunched_groundpunch.json").write_text(
        json.dumps(payload, separators=(",", ":")), encoding="utf-8")


def main() -> int:
    bake_run()
    bake_kill()
    print("WROTE run_chase_corrected.json and kill_hunched_groundpunch.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
