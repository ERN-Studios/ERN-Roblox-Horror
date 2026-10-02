"""Read-only independent verification of the frozen R4 V3 dense-backing/overlay delta."""
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
assert sha(old) == proof["baselineV1SourceSHA256"]
assert sha(new) == proof["candidateSourceSHA256"]
assert without_plan(old) == without_plan(new)
assert sha(without_plan(new)) == proof["nonPLANSourceSHA256"]
a = json.loads((WORK / "plan.v1.json").read_text())
b = json.loads((HERE / "plan.json").read_text())
assert sha((WORK / "plan.v1.json").read_bytes()) == proof["baselineV1PlanSHA256"]
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
assert len(b["placements"]) == 219 and b["placements"][:179] == a["placements"]
added = b["placements"][179:]
assert len(added) == 40 and len({p["name"] for p in b["placements"]}) == 219
assert Counter(p["name"].split()[0] for p in added) == {"South": 20, "NorthDJ": 20}
assert a["colliders"] == b["colliders"] and len(b["colliders"]) == 66
for key in a:
    if key not in ("placements", "notes", "statistics"):
        assert a[key] == b[key], key
assert b["statistics"] == {**a["statistics"], "instances": 219, "extraInstancedTriangles": 220612}
assert b["notes"][:-1] == a["notes"] and b["layoutRevision"] == 3
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
boxes = {}
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
    boxes[row["name"]] = [[min(c[i] for c in corners), max(c[i] for c in corners)] for i in range(3)]
    if row["name"].startswith("NorthDJ"):
        north_minimum = min(north_minimum, min(c[2] for c in corners))
    half = [(max(c[i] for c in corners) - min(c[i] for c in corners)) / 2 for i in range(3)]
    assert max(abs(center[i] - row["bboxCenter"][i]) for i in range(3)) < 0.000002
    assert max(abs(half[i] - row["bboxHalf"][i]) for i in range(3)) < 0.000002
assert math.isclose(max_radius, proof["maxRadialCorner"], abs_tol=1e-10)
assert math.isclose(north_minimum, proof["northMinZ"], abs_tol=1e-10)
assert sum(chunks[p["family"]]["triangles"] for p in b["placements"]) == 220612
assert dict(Counter(p["family"] for p in added)) == proof["overlayFamilyCounts"]
base_by_name = {p["name"]: p for p in a["placements"]}
overlaps = []
for overlay in added:
    support = base_by_name[overlay["overlaySupport"]]
    assert support["family"] == overlay["family"] and " Embedded " in support["name"]
    aa, bb = boxes[overlay["name"]], boxes[support["name"]]
    overlap = [min(aa[i][1], bb[i][1]) - max(aa[i][0], bb[i][0]) for i in range(3)]
    assert min(overlap) > 0.25
    assert abs(abs(support["bboxCenter"][2]) - abs(overlay["bboxCenter"][2]) - 0.8) < 0.000002
    overlaps.append(min(overlap))
assert math.isclose(min(overlaps), proof["minimumOverlayBaseAABBOverlap"], abs_tol=1e-10)
print(json.dumps({"status": "PASS", "scope": "Frozen offline source/data/1752 corner and AABB envelope checks only", "maxRadialCorner": max_radius, "northGuardBackClearance": north_minimum - 128.49}))
