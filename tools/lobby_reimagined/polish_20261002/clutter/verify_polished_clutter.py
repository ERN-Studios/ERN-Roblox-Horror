"""Independently recompute serialized placement envelopes and preservation."""
from collections import Counter
import hashlib
import itertools
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
ART = ROOT / "artifacts/lobby-polish-20261002/clutter"
BASE = ROOT / "tools/lobby_reimagined/end_clutter_20261002"
sha = lambda b: hashlib.sha256(b).hexdigest()
old = (ART / "EndBlockades.live-baseline.luau").read_bytes()
new = (HERE / "EndBlockades.ModuleScript.candidate.luau").read_bytes()
a = json.loads((BASE / "plan.json").read_text())
b = json.loads((HERE / "plan.json").read_text())
delta = json.loads((ART / "placement-delta.json").read_text())
assert sha(old) == delta["baselineSourceSHA256"]
assert sha(new) == delta["candidateSourceSHA256"]
without_plan = lambda raw: b"\n".join(line for line in raw.split(b"\n") if not line.startswith(b"local PLAN = "))
assert without_plan(old) == without_plan(new)
assert len(a["placements"]) == len(b["placements"]) == 219
assert b["placements"][:179] == a["placements"][:179]
assert a["colliders"] == b["colliders"] and len(b["colliders"]) == 66
assert a["statistics"] == b["statistics"]
assert Counter(p["family"] for p in a["placements"]) == Counter(p["family"] for p in b["placements"])
assert [p["name"] for p in a["placements"]] == [p["name"] for p in b["placements"]]
assert len({p["name"] for p in b["placements"]}) == 219
changed = [i for i, (x, y) in enumerate(zip(a["placements"], b["placements"])) if x != y]
assert len(changed) == 16 and min(changed) >= 179
assert Counter(b["placements"][i]["name"].split()[0] for i in changed) == {"South":8, "NorthDJ":8}
manifest = json.loads((ROOT / "assets/models/lobby-reimagined-r4-20261001/manifest.json").read_text())
chunks = {c["family"]:c for c in manifest["chunks"] if c["materialKey"] == "atlas"}


def rotate(p, angles):
    # Apply Z, then Y, then X independently of generator's matrix expansion.
    x, y, z = p
    rx, ry, rz = angles
    x, y = x*math.cos(rz)-y*math.sin(rz), x*math.sin(rz)+y*math.cos(rz)
    x, z = x*math.cos(ry)+z*math.sin(ry), -x*math.sin(ry)+z*math.cos(ry)
    y, z = y*math.cos(rx)-z*math.sin(rx), y*math.sin(rx)+z*math.cos(rx)
    return [x,y,z]


def dot(a, b):
    return sum(x*y for x,y in zip(a,b))


def cross(a, b):
    return [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]]


def sat_overlap(left, right):
    # All six box-face axes and nine edge cross-products. Intersection only of
    # oriented bounds, not proof that hollow furniture meshes visibly touch.
    axes = left["axes"]+right["axes"]+[cross(x,y) for x in left["axes"] for y in right["axes"]]
    penetration = []
    separation = [right["center"][i]-left["center"][i] for i in range(3)]
    for axis in axes:
        norm = math.sqrt(dot(axis,axis))
        if norm < 1e-8:
            continue
        axis = [v/norm for v in axis]
        radius_l = sum(left["size"][i]*abs(dot(axis,left["axes"][i]))/2 for i in range(3))
        radius_r = sum(right["size"][i]*abs(dot(axis,right["axes"][i]))/2 for i in range(3))
        penetration.append(radius_l+radius_r-abs(dot(axis,separation)))
    return min(penetration)


max_radius = 0
north_min = math.inf
boxes = {}
for item in b["placements"]:
    c = chunks[item["family"]]
    offset = rotate(c["center"],item["rotation"])
    center = [item["robloxPosition"][i]+offset[i] for i in range(3)]
    corners = []
    for signs in itertools.product((-1,1),repeat=3):
        q = rotate([signs[i]*c["size"][i]/2 for i in range(3)],item["rotation"])
        q = [center[i]+q[i] for i in range(3)]
        corners.append(q)
        radius = math.hypot(q[0],max(0,q[1]-1))
        max_radius = max(max_radius,radius)
        assert radius <= 33.55 and q[1] >= -.025,item["name"]
    half = [(max(q[i]for q in corners)-min(q[i]for q in corners))/2 for i in range(3)]
    assert max(abs(center[i]-item["bboxCenter"][i])for i in range(3)) < 2e-6
    assert max(abs(half[i]-item["bboxHalf"][i])for i in range(3)) < 2e-6
    axes = [rotate([int(i==j)for i in range(3)],item["rotation"])for j in range(3)]
    boxes[item["name"]] = {"center":center,"half":half,"corners":corners,"size":c["size"],"axes":axes}
    if item["name"].startswith("NorthDJ"):
        north_min = min(north_min,min(q[2] for q in corners))
assert north_min-128.49 >= 1.4885588
assert sum(chunks[p["family"]]["triangles"]for p in b["placements"]) == 220612
by_name = {p["name"]:p for p in b["placements"]}
supports = []
for overlay in b["placements"][179:]:
    support = by_name[overlay["overlaySupport"]]
    assert support["family"] == overlay["family"] and " Embedded " in support["name"]
    left,right = boxes[overlay["name"]],boxes[support["name"]]
    xyz = [min(left["center"][i]+left["half"][i],right["center"][i]+right["half"][i])-
           max(left["center"][i]-left["half"][i],right["center"][i]-right["half"][i])for i in range(3)]
    penetration = sat_overlap(left,right)
    assert min(xyz) > 1.0 and penetration > .25,(overlay["name"],xyz,penetration)
    supports.append({"overlay":overlay["name"],"support":support["name"],"AABBOverlapXYZ":xyz,"OBBMinimumSATAxisOverlap":penetration})

# Investigate deletions conservatively: exact duplicate poses are safe to
# flag, while box containment alone cannot prove an interior mesh is hidden.
fingerprints = Counter((p["family"],tuple(p["robloxPosition"]),tuple(p["rotation"]))for p in b["placements"])
duplicates = [key for key,count in fingerprints.items()if count>1]
assert not duplicates
contained = []
for item in b["placements"]:
    left = boxes[item["name"]]
    for other in b["placements"]:
        if item is other:
            continue
        right = boxes[other["name"]]
        if all(all(abs(dot([q[i]-right["center"][i]for i in range(3)],right["axes"][j]))
                   <= right["size"][j]/2-1e-5 for j in range(3))for q in left["corners"]):
            contained.append({"contained":item["name"],"container":other["name"]})
receipt = {"status":"PASS","scope":"Offline exact-source preservation, 1752 serialized corners, 40 AABB/OBB support volumes; not visible contact, gameplay or performance", "baselineSourceSHA256":sha(old),"candidateSourceSHA256":sha(new),
           "nonPLANSourceSHA256":sha(without_plan(new)),"candidatePlanSHA256":sha((HERE/"plan.json").read_bytes()),
           "instances":219,"extraInstancedTriangles":220612,"cornersChecked":219*8,
           "maxRadialCorner":max_radius,"archRadiusLimit":33.55,"northMinZ":north_min,"northDJRearClearance":north_min-128.49,
           "dense179ExactlyUnchanged":True,"other24OverlaysUnchanged":True,"66CurtainsExactlyUnchanged":True,
           "functionsOutsidePLANExactlyUnchanged":True,"movedOverlays":16,
           "minimumSupportAABBOverlap":min(min(s["AABBOverlapXYZ"])for s in supports),
           "minimumSupportOBBSATAxisOverlap":min(s["OBBMinimumSATAxisOverlap"]for s in supports),
           "uniqueFamiliesUsed":len(fingerprints and Counter(p["family"]for p in b["placements"])),"newUniqueMeshes":0,
           "hiddenDuplicateInvestigation":{"exactDuplicatePoses":len(duplicates),"wholeBoxContainmentCandidates":contained,"removed":0,"reason":"No identical poses; bounds alone do not prove occlusion of hollow furniture. Preserve backing until actual visibility/profiling evidence supports removal."},
           "supportProofs":supports}
(ART/"geometry-preservation-receipt.json").write_text(json.dumps(receipt,indent=2)+"\n")
print(json.dumps({k:v for k,v in receipt.items()if k not in ("supportProofs","hiddenDuplicateInvestigation")},indent=2))
