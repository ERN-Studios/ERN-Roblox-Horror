"""Local R4 placement-only polish; never connects to Studio.

Keep the dense 179 backing, foreground/crown, kit, curtains and runtime code.
Re-use sixteen existing overlays to break visible upper courses at both ends.
"""
from collections import Counter
from copy import deepcopy
import hashlib
import itertools
import json
import math
from pathlib import Path
import random

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
ART = ROOT / "artifacts/lobby-polish-20261002/clutter"
BASE = ROOT / "tools/lobby_reimagined/end_clutter_20261002"
PIN = "a0153febfe35686a6d71e7a1cae3881069486fcdfdf71e734d980b30bd76280d"
sha = lambda b: hashlib.sha256(b).hexdigest()
source = (ART / "EndBlockades.live-baseline.luau").read_text()
assert sha(source.encode()) == PIN
assert source == (BASE / "EndBlockades.ModuleScript.luau").read_text()
original = json.loads((BASE / "plan.json").read_text())
plan = deepcopy(original)
manifest = json.loads((ROOT / "assets/models/lobby-reimagined-r4-20261001/manifest.json").read_text())
chunks = {c["family"]: c for c in manifest["chunks"] if c["materialKey"] == "atlas"}
by_name = {a["name"]: a for a in original["placements"]}


def rotation(a):
    sx, cx = math.sin(a[0]), math.cos(a[0])
    sy, cy = math.sin(a[1]), math.cos(a[1])
    sz, cz = math.sin(a[2]), math.cos(a[2])
    return [[cy*cz, -cy*sz, sy],
            [cx*sz+sx*sy*cz, cx*cz-sx*sy*sz, -sx*cy],
            [sx*sz-cx*sy*cz, sx*cz+cx*sy*sz, cx*cy]]


def mul(m, p):
    return [sum(m[i][j]*p[j] for j in range(3)) for i in range(3)]


def pose(family, angles, center):
    # Round before proof: the final serialized source is what Studio receives.
    angles = [round(v, 8) for v in angles]
    mat = rotation(angles)
    chunk = chunks[family]
    offset = mul(mat, chunk["center"])
    position = [round(center[i]-offset[i], 6) for i in range(3)]
    actual_center = [position[i]+offset[i] for i in range(3)]
    corners = []
    for signs in itertools.product((-1, 1), repeat=3):
        q = mul(mat, [signs[i]*chunk["size"][i]/2 for i in range(3)])
        corners.append([actual_center[i]+q[i] for i in range(3)])
    half = [(max(c[i] for c in corners)-min(c[i] for c in corners))/2 for i in range(3)]
    return angles, position, actual_center, half, corners


targets = {
    "South": ["06-02", "06-03", "06-05", "06-07", "07-03", "07-04", "07-06", "08-04"],
    "NorthDJ": ["06-03", "06-04", "06-06", "06-07", "07-03", "07-05", "07-06", "08-04"],
}
changes = []
used = set()
for end, suffixes in targets.items():
    sign = 1 if end == "NorthDJ" else -1
    rng = random.Random(20261002 + (73 if sign > 0 else 0))
    for index, suffix in enumerate(suffixes):
        support = by_name[f"{end} Embedded {suffix}"]
        family = support["family"]
        candidates = sorted((a for a in plan["placements"][179:]
                             if a["name"].startswith(end) and a["family"] == family
                             and a["name"] not in used), key=lambda a: (a["bboxCenter"][1], a["name"]))
        assert candidates, (end, suffix, family)
        overlay = candidates[0]
        old = deepcopy(overlay)
        used.add(overlay["name"])
        # Distinct restrained upper tilts, not a repeated mirrored prescription.
        desired = [rng.choice((-1, 1))*math.radians(rng.uniform(6, 12)),
                   support["rotation"][1]+math.radians(rng.choice((-1, 1))*rng.uniform(14, 25)),
                   support["rotation"][2]+rng.choice((-1, 1))*math.radians(rng.uniform(7, 12))]
        center = support["bboxCenter"][:]
        center[0] += rng.uniform(-.22, .22)
        center[1] += rng.uniform(-.48, .38)
        center[2] = sign*(abs(center[2])-.82-rng.uniform(0, .16))
        solved = None
        for drop in (0, .25, .50, .75, 1.0, 1.25):
            for factor in (1.0, .85, .70, .55):
                angles = [support["rotation"][j]+factor*(desired[j]-support["rotation"][j]) for j in range(3)]
                proposed = [center[0], center[1]-drop, center[2]]
                a, position, cc, half, corners = pose(family, angles, proposed)
                overlap = [min(cc[j]+half[j], support["bboxCenter"][j]+support["bboxHalf"][j])-
                           max(cc[j]-half[j], support["bboxCenter"][j]-support["bboxHalf"][j]) for j in range(3)]
                if min(overlap) < 1.0:
                    continue
                if max(math.hypot(q[0], max(0, q[1]-1)) for q in corners) > 33.55:
                    continue
                if min(q[1] for q in corners) < -.025:
                    continue
                if sign > 0 and min(q[2] for q in corners) < 129.97855894706973:
                    continue
                solved = (a, position, cc, half, overlap)
                break
            if solved:
                break
        assert solved, (overlay["name"], support["name"])
        angles, position, cc, half, overlap = solved
        overlay.update(rotation=angles, robloxPosition=position,
                       bboxCenter=[round(v, 6) for v in cc], bboxHalf=[round(v, 6) for v in half],
                       overlaySupport=support["name"])
        changes.append({"name": overlay["name"], "family": family,
                        "support": support["name"], "before": old, "after": deepcopy(overlay),
                        "supportAABBOverlapXYZ": overlap,
                        "towardViewerStuds": abs(support["bboxCenter"][2])-abs(cc[2])})

assert len(changes) == 16
assert plan["placements"][:179] == original["placements"][:179]
assert plan["colliders"] == original["colliders"] and len(plan["colliders"]) == 66
assert Counter(a["family"] for a in plan["placements"]) == Counter(a["family"] for a in original["placements"])
plan["layoutRevision"] = 4
plan["notes"].append("Polish keeps dense179 backing and40existing overlays; sixteen overlays move to supported upper faces with nonmirrored restrained tilt/yaw. No additional meshes or collision changes.")


def serialize(v):
    if isinstance(v, dict):
        return "{"+",".join("["+json.dumps(k)+"]="+serialize(a) for k, a in v.items())+"}"
    if isinstance(v, list):
        return "{"+",".join(map(serialize, v))+"}"
    if isinstance(v, str):
        return json.dumps(v, ensure_ascii=False)
    if isinstance(v, bool):
        return "true" if v else "false"
    return "nil" if v is None else str(v)


assert next(x for x in source.splitlines() if x.startswith("local PLAN = ")) == "local PLAN = "+serialize(original)
candidate = "\n".join("local PLAN = "+serialize(plan) if line.startswith("local PLAN = ") else line for line in source.split("\n"))
(HERE / "plan.json").write_text(json.dumps(plan, indent=2)+"\n")
(HERE / "EndBlockades.ModuleScript.candidate.luau").write_text(candidate)
receipt = {"schema": "lobby-r4-clutter-polish-delta-v1", "baselineSourceSHA256": PIN,
           "candidateSourceSHA256": sha(candidate.encode()),
           "candidatePlanSHA256": sha((HERE / "plan.json").read_bytes()),
           "instances": 219, "extraInstancedTriangles": 220612,
           "changedOverlays": len(changes), "unchangedDenseBacking": 179,
           "unchangedOtherOverlays": 24, "collidersUnchanged": 66,
           "newUniqueMeshes": 0, "runtimeFunctionsUnchanged": True,
           "interface": "Add(model, kit, manifest)", "changes": changes,
           "limits": "Bounding support volumes do not prove visible mesh contact or lighting; root must inspect actual Play."}
(ART / "placement-delta.json").write_text(json.dumps(receipt, indent=2)+"\n")
print(json.dumps({k:v for k,v in receipt.items() if k != "changes"}, indent=2))
