"""Read-only independent verification of the frozen R4 V2 placement delta."""
from collections import Counter
from pathlib import Path
import hashlib
import itertools
import json
import math

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
WORK = ROOT / "tools/lobby_reimagined/end_clutter_20261002"
BASE = HERE.parent / "final-candidate-snapshot/EndBlockades.ModuleScript.luau"
old = BASE.read_bytes()
new = (HERE / "EndBlockades.ModuleScript.luau").read_bytes()
proof = json.loads((HERE / "delta-evidence.json").read_text())
sha = lambda raw: hashlib.sha256(raw).hexdigest()
without_plan = lambda raw: b"\n".join(
    line for line in raw.split(b"\n") if not line.startswith(b"local PLAN = ")
)
assert sha(old) == proof["baselineSourceSHA256"]
assert sha(new) == proof["candidateSourceSHA256"]
assert without_plan(old) == without_plan(new)
assert sha(without_plan(new)) == proof["nonPLANSourceSHA256"]
a = json.loads((WORK / "plan.v1.json").read_text())
b = json.loads((HERE / "plan.json").read_text())
assert sha((WORK / "plan.v1.json").read_bytes()) == proof["baselinePlanSHA256"]
assert sha((HERE / "plan.json").read_bytes()) == proof["candidatePlanSHA256"]


def serialize(value):
    if isinstance(value, dict):
        return "{" + ",".join("[" + json.dumps(k) + "]=" + serialize(v) for k, v in value.items()) + "}"
    if isinstance(value, list):
        return "{" + ",".join(map(serialize, value)) + "}"
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, bool):
        return "true" if value else "false"
    return "nil" if value is None else str(value)


assert next(line for line in new.decode().splitlines() if line.startswith("local PLAN = ")) == "local PLAN = " + serialize(b)
changed = 0
assert len(a["placements"]) == len(b["placements"]) == 179
for before, after in zip(a["placements"], b["placements"]):
    assert before["name"] == after["name"] and before["family"] == after["family"]
    assert before.keys() == after.keys()
    if before != after:
        changed += 1
        assert " Embedded " in before["name"]
        assert {k for k in before if before[k] != after[k]} <= {"rotation", "robloxPosition", "bboxCenter", "bboxHalf"}
assert changed == 132
assert a["colliders"] == b["colliders"] and len(b["colliders"]) == 66
for key in a:
    if key not in ("placements", "notes"):
        assert a[key] == b[key], key
assert b["notes"][:-1] == a["notes"] and b["layoutRevision"] == 2
manifest = json.loads((ROOT / "assets/models/lobby-reimagined-r4-20261001/manifest.json").read_text())
chunks = {c["family"]: c for c in manifest["chunks"] if c["materialKey"] == "atlas"}


def rotate(point, angles):
    """Apply Rz then Ry then Rx independently of the generator's expanded matrix."""
    x, y, z = point
    rx, ry, rz = angles
    x, y = x * math.cos(rz) - y * math.sin(rz), x * math.sin(rz) + y * math.cos(rz)
    x, z = x * math.cos(ry) + z * math.sin(ry), -x * math.sin(ry) + z * math.cos(ry)
    y, z = y * math.cos(rx) - z * math.sin(rx), y * math.sin(rx) + z * math.cos(rx)
    return [x, y, z]


max_radius = 0
north_minimum = math.inf
for row in b["placements"]:
    chunk = chunks[row["family"]]
    rotated_center = rotate(chunk["center"], row["rotation"])
    center = [row["robloxPosition"][i] + rotated_center[i] for i in range(3)]
    corners = []
    for signs in itertools.product((-1, 1), repeat=3):
        local = [signs[i] * chunk["size"][i] / 2 for i in range(3)]
        offset = rotate(local, row["rotation"])
        corner = [center[i] + offset[i] for i in range(3)]
        corners.append(corner)
        radius = math.hypot(corner[0], max(0, corner[1] - 1))
        max_radius = max(max_radius, radius)
        assert radius <= 33.55 and corner[1] >= -0.025, row["name"]
    if row["name"].startswith("NorthDJ"):
        north_minimum = min(north_minimum, min(c[2] for c in corners))
    half = [(max(c[i] for c in corners) - min(c[i] for c in corners)) / 2 for i in range(3)]
    assert max(abs(center[i] - row["bboxCenter"][i]) for i in range(3)) < 0.000002
    assert max(abs(half[i] - row["bboxHalf"][i]) for i in range(3)) < 0.000002
assert math.isclose(max_radius, proof["maxRadialCorner"], abs_tol=1e-10)
assert math.isclose(north_minimum, proof["northMinimumZ"], abs_tol=1e-10)
assert sum(chunks[p["family"]]["triangles"] for p in b["placements"]) == 180840
assert dict(Counter(p["family"] for p in b["placements"])) == proof["familyCounts"]
print(json.dumps({"status": "PASS", "scope": "Frozen offline source/data/1432 corner checks only", "maxRadialCorner": max_radius, "northGuardBackClearance": north_minimum - 128.49}))
