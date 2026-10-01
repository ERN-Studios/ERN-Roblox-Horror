#!/usr/bin/env python3
"""Check the imported room collision geometry against Level 6 Manager clearance."""

import json
import sys
from pathlib import Path


ROOMS = ("RoomKitchenPrep", "RoomUtilityHall", "RoomStaffNook")
MIN_CLEAR_WIDTH = 12.0  # 10-stud Manager body plus one stud of margin on each side.


def check_room(name: str, family: dict) -> list[str]:
    issues = []
    anchors = family["anchorDetails"]
    for portal in ("JoinNorth", "JoinSouth"):
        detail = anchors[portal]
        if detail["l6_port_width"] < 14 or detail["l6_port_height"] < 10.5:
            issues.append(f"{portal} clear opening is too small")
    if not family["hasFlattenedFixtureVisuals"] or not family["hasIntegratedFixtureCollision"]:
        issues.append("child fixtures are not integrated into visual and collision exports")

    boxes = []
    for box in family["colliders_xyz"]:
        x, z, y = box["center"]  # Blender XY is Roblox X,-Z; Blender Z is height.
        width, depth, height = box["size"]
        if y + height / 2 <= 0.05 or y - height / 2 >= 8:
            continue  # Floor and high lintels do not constrain the Manager body.
        boxes.append((x - width / 2, x + width / 2, z - depth / 2, z + depth / 2))

    minimum = (float("inf"), None)
    for step in range(481):
        z = -12 + step * 0.05
        left, right = -float("inf"), float("inf")
        for x0, x1, z0, z1 in boxes:
            if z < z0 or z > z1:
                continue
            if x0 < 0 < x1:
                issues.append(f"central path is blocked at local z={z:.2f}")
                return issues
            if x1 <= 0:
                left = max(left, x1)
            if x0 >= 0:
                right = min(right, x0)
        clearance = right - left
        if clearance < minimum[0]:
            minimum = (clearance, z)
    if minimum[0] < MIN_CLEAR_WIDTH:
        issues.append(
            f"minimum central clearance is {minimum[0]:.2f} studs at local z={minimum[1]:.2f}; "
            f"need {MIN_CLEAR_WIDTH:.2f}"
        )
    print(f"{name}: central clearance {minimum[0]:.2f} studs at z={minimum[1]:.2f}")
    return issues


def main() -> int:
    path = Path(sys.argv[1])
    families = json.loads(path.read_text())["families"]
    failures = []
    for name in ROOMS:
        failures.extend(f"{name}: {issue}" for issue in check_room(name, families[name]))
    for failure in failures:
        print(f"FAIL {failure}", file=sys.stderr)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
