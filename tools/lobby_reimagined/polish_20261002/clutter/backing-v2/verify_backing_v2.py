"""Independent checks of the serialized backing candidate; no Studio access."""
from collections import Counter
import hashlib
import itertools
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[5]
HERE = Path(__file__).resolve().parent
ART = ROOT / "artifacts/lobby-polish-20261002/clutter/backing-v2"
sha = lambda raw: hashlib.sha256(raw).hexdigest()
old = (ART / "EndBlockades.runtime-reference426.luau").read_bytes()
new = (HERE / "EndBlockades.ModuleScript.candidate.luau").read_bytes()
a = json.loads((HERE.parent / "plan.json").read_text())
b = json.loads((HERE / "plan.json").read_text())
delta = json.loads((ART / "placement-delta.json").read_text())
assert sha(old) == delta["baselineSourceSHA256"]
assert sha(new) == delta["candidateSourceSHA256"]
without_plan = lambda raw: b"\n".join(line for line in raw.split(b"\n") if not line.startswith(b"local PLAN = "))
assert without_plan(old) == without_plan(new)
assert len(a["placements"]) == len(b["placements"]) == 219
assert a["colliders"] == b["colliders"] and len(b["colliders"]) == 66
assert a["statistics"] == b["statistics"]
assert Counter(p["family"] for p in a["placements"]) == Counter(p["family"] for p in b["placements"])
assert [p["name"] for p in a["placements"]] == [p["name"] for p in b["placements"]]
assert len({p["name"] for p in b["placements"]}) == 219
changed = [i for i, (x, y) in enumerate(zip(a["placements"], b["placements"])) if x != y]
assert len(changed) == 12 and max(changed) < 179
assert Counter(b["placements"][i]["name"].split()[0] for i in changed) == {"South":4, "NorthDJ":8}
assert all(" Embedded " in a["placements"][i]["name"] and a["placements"][i]["bboxCenter"][1] >= 20 for i in changed)
assert all(x == y for x, y in zip(a["placements"],b["placements"]) if x["bboxCenter"][1] < 20)
assert a["placements"][179:] == b["placements"][179:]
assert {b["placements"][i]["name"] for i in changed} == {x["name"] for x in delta["changes"]}
manifest = json.loads((ROOT / "assets/models/lobby-reimagined-r4-20261001/manifest.json").read_text())
chunks = {c["family"]:c for c in manifest["chunks"] if c["materialKey"] == "atlas"}


def rotate(p, angles):
    # Independent sequential Euler operations, Z then Y then X.
    x,y,z = p
    rx,ry,rz = angles
    x,y = x*math.cos(rz)-y*math.sin(rz),x*math.sin(rz)+y*math.cos(rz)
    x,z = x*math.cos(ry)+z*math.sin(ry),-x*math.sin(ry)+z*math.cos(ry)
    y,z = y*math.cos(rx)-z*math.sin(rx),y*math.sin(rx)+z*math.cos(rx)
    return [x,y,z]


def dot(a,b):
    return sum(x*y for x,y in zip(a,b))


def cross(a,b):
    return [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]


def sat_overlap(left,right):
    axes = left["axes"]+right["axes"]+[cross(x,y) for x in left["axes"] for y in right["axes"]]
    delta = [right["center"][i]-left["center"][i] for i in range(3)]
    overlaps = []
    for axis in axes:
        norm = math.sqrt(dot(axis,axis))
        if norm < 1e-8:
            continue
        axis = [v/norm for v in axis]
        lr = sum(left["size"][i]*abs(dot(axis,left["axes"][i]))/2 for i in range(3))
        rr = sum(right["size"][i]*abs(dot(axis,right["axes"][i]))/2 for i in range(3))
        overlaps.append(lr+rr-abs(dot(axis,delta)))
    return min(overlaps)


def bounds(plan):
    boxes = {}
    for item in plan["placements"]:
        c = chunks[item["family"]]
        offset = rotate(c["center"],item["rotation"])
        center = [item["robloxPosition"][i]+offset[i] for i in range(3)]
        corners = []
        for signs in itertools.product((-1,1),repeat=3):
            p = rotate([signs[i]*c["size"][i]/2 for i in range(3)],item["rotation"])
            corners.append([center[i]+p[i] for i in range(3)])
        half = [(max(p[i] for p in corners)-min(p[i] for p in corners))/2 for i in range(3)]
        assert max(abs(center[i]-item["bboxCenter"][i]) for i in range(3)) < 2e-6
        assert max(abs(half[i]-item["bboxHalf"][i]) for i in range(3)) < 2e-6
        axes = [rotate([int(i==j) for i in range(3)],item["rotation"]) for j in range(3)]
        boxes[item["name"]] = {"center":center,"half":half,"size":c["size"],"axes":axes,"corners":corners}
    return boxes


old_boxes,new_boxes = bounds(a),bounds(b)
all_corners = [p for box in new_boxes.values() for p in box["corners"]]
max_radius = max(math.hypot(p[0],max(0,p[1]-1)) for p in all_corners)
minimum_y = min(p[1] for p in all_corners)
assert max_radius <= 33.55 and minimum_y >= -.025
north_min = min(p[2] for name,box in new_boxes.items() if name.startswith("NorthDJ") for p in box["corners"])
old_north_min = min(p[2] for name,box in old_boxes.items() if name.startswith("NorthDJ") for p in box["corners"])
assert north_min >= old_north_min-1e-9 and north_min-128.49 >= 1.4885588
assert sum(chunks[p["family"]]["triangles"] for p in b["placements"]) == 220612
by_name = {p["name"]:p for p in b["placements"]}
supports = []
for overlay in b["placements"][179:]:
    support = by_name[overlay["overlaySupport"]]
    assert support["family"] == overlay["family"] and " Embedded " in support["name"]
    left,right = new_boxes[overlay["name"]],new_boxes[support["name"]]
    xyz = [min(left["center"][i]+left["half"][i],right["center"][i]+right["half"][i])-
           max(left["center"][i]-left["half"][i],right["center"][i]-right["half"][i]) for i in range(3)]
    penetration = sat_overlap(left,right)
    assert min(xyz) > 1 and penetration > .25,(overlay["name"],xyz,penetration)
    supports.append({"overlay":overlay["name"],"support":support["name"],"AABBOverlapXYZ":xyz,"OBBMinimumSATAxisOverlap":penetration})

# Each moved upper backing box must remain connected by oriented bounds to
# another backing box whose centre is below it. This is support plausibility,
# not a claim that hollow furniture surfaces physically touch.
backing_connections = []
for i in changed:
    item = b["placements"][i]
    box = new_boxes[item["name"]]
    overlaps = []
    for other in b["placements"][:179]:
        if other["name"] == item["name"] or " Embedded " not in other["name"] or other["name"].split()[0] != item["name"].split()[0]:
            continue
        right = new_boxes[other["name"]]
        if right["center"][1] >= box["center"][1]:
            continue
        overlap = sat_overlap(box,right)
        if overlap > .15:
            overlaps.append({"lowerBacking":other["name"],"OBBMinimumSATAxisOverlap":overlap})
    assert overlaps,item["name"]
    backing_connections.append({"movedBacking":item["name"],"lowerConnections":sorted(overlaps,key=lambda p:-p["OBBMinimumSATAxisOverlap"])})


def hull(points):
    points = sorted(set((p[0],p[1]) for p in points))
    turn = lambda a,b,c:(b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])
    lower,upper = [],[]
    for p in points:
        while len(lower)>=2 and turn(lower[-2],lower[-1],p)<=0:
            lower.pop()
        lower.append(p)
    for p in reversed(points):
        while len(upper)>=2 and turn(upper[-2],upper[-1],p)<=0:
            upper.pop()
        upper.append(p)
    return lower[:-1]+upper[:-1]


def projected_grid(boxes,end):
    polygons = [hull(box["corners"]) for name,box in boxes.items() if name.startswith(end)]
    # Horizontal scanlines of convex XY projections; 0.25-stud sample centres.
    covered = set()
    for yi in range(64,140):
        y = (yi+.5)*.25
        intervals = []
        for polygon in polygons:
            intersections = []
            for left,right in zip(polygon,polygon[1:]+polygon[:1]):
                if min(left[1],right[1]) <= y < max(left[1],right[1]):
                    intersections.append(left[0]+(y-left[1])*(right[0]-left[0])/(right[1]-left[1]))
            if intersections:
                intervals.append((min(intersections),max(intersections)))
        for left,right in intervals:
            start = max(-134,math.ceil(left/.25-.5))
            stop = min(133,math.floor(right/.25-.5))
            covered.update((xi,yi) for xi in range(start,stop+1))
    return covered


coverage = {}
for end in ("South","NorthDJ"):
    before,after = projected_grid(old_boxes,end),projected_grid(new_boxes,end)
    lost,gained = before-after,after-before
    retained = len(before&after)/len(before)
    # Avoid recreating the broad reorientation which opened visible holes.
    assert retained >= .97,(end,retained)
    shoulder = lambda points:{p for p in points if abs((p[0]+.5)*.25)>=12 and (p[1]+.5)*.25>=18}
    bs,cs = shoulder(before),shoulder(after)
    coverage[end] = {"baselineUpperEnvelopeArea":len(before)*.0625,"candidateUpperEnvelopeArea":len(after)*.0625,
                     "retainedBaselineEnvelopeFraction":retained,"lostEnvelopeArea":len(lost)*.0625,"gainedEnvelopeArea":len(gained)*.0625,
                     "baselineShoulderEnvelopeArea":len(bs)*.0625,"candidateShoulderEnvelopeArea":len(cs)*.0625,
                     "shoulderEnvelopeAreaChange":(len(cs)-len(bs))*.0625}

receipt = {"status":"PASS","scope":"Offline exact-source and volume-envelope preservation; not rendered opaque coverage, visible contact, gameplay, multiplayer or performance",
           "baselineSourceSHA256":sha(old),"candidateSourceSHA256":sha(new),"candidatePlanSHA256":sha((HERE/"plan.json").read_bytes()),
           "nonPLANSourceSHA256":sha(without_plan(new)),"runtimeFunctionsUnchanged":True,"instances":219,"extraInstancedTriangles":220612,"newUniqueMeshes":0,
           "changedUpperBackingFaces":12,"other167OriginalPlacementsExactlyUnchanged":True,"all40OverlaysExactlyUnchanged":True,
           "all66CurtainsExactlyUnchanged":True,"cornersChecked":1752,"maximumRadialCorner":max_radius,"radialLimit":33.55,"minimumCornerY":minimum_y,
           "northMinZ":north_min,"northDJRearClearance":north_min-128.49,"baselineDJRearClearance":old_north_min-128.49,
           "minimumOverlaySupportAABBOverlap":min(min(s["AABBOverlapXYZ"]) for s in supports),
           "minimumOverlaySupportOBBSATAxisOverlap":min(s["OBBMinimumSATAxisOverlap"] for s in supports),
           "minimumBestLowerBackingConnection":min(max(c["OBBMinimumSATAxisOverlap"] for c in x["lowerConnections"]) for x in backing_connections),
           "projectedEnvelopeCoverage":{"samplePitch":.25,"minimumSampleY":16,"maximumSampleY":35,"shoulderMinimumAbsX":12,
                                        "limit":"Convex projected bounding volumes only; hollow mesh opacity/contact and pale-shoulder appearance require actual Play images.","ends":coverage},
           "overlaySupportProofs":supports,"backingConnectionProofs":backing_connections,
           "authorityLimit":"Runtime Server baseline reference; root must CAS against fresh authoritative Edit Source/editor and identity."}
(ART/"geometry-preservation-receipt.json").write_text(json.dumps(receipt,indent=2)+"\n")
print(json.dumps({k:v for k,v in receipt.items() if k not in ("overlaySupportProofs","backingConnectionProofs")},indent=2))
