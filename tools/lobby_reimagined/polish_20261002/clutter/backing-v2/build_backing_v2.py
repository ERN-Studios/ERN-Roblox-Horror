"""Local PLAN-only revision: twelve backing faces, no Studio connection."""
from collections import Counter
from copy import deepcopy
import hashlib
import itertools
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[5]
HERE = Path(__file__).resolve().parent
ART = ROOT / "artifacts/lobby-polish-20261002/clutter/backing-v2"
BASE = HERE.parent
PIN = "4269373d1ddd04106a082e3f859222a691ed7faedb46c0ec03116beeff50a78d"
sha = lambda b: hashlib.sha256(b).hexdigest()
source = (ART / "EndBlockades.runtime-reference426.luau").read_text()
assert sha(source.encode()) == PIN
assert source == (BASE / "EndBlockades.ModuleScript.candidate.luau").read_text()
a = json.loads((BASE / "plan.json").read_text())
b = deepcopy(a)
manifest = json.loads((ROOT / "assets/models/lobby-reimagined-r4-20261001/manifest.json").read_text())
chunks = {c["family"]:c for c in manifest["chunks"] if c["materialKey"] == "atlas"}
by_name = {p["name"]:p for p in b["placements"]}


def rotation(t):
    sx,cx = math.sin(t[0]),math.cos(t[0])
    sy,cy = math.sin(t[1]),math.cos(t[1])
    sz,cz = math.sin(t[2]),math.cos(t[2])
    return [[cy*cz,-cy*sz,sy],[cx*sz+sx*sy*cz,cx*cz-sx*sy*sz,-sx*cy],
            [sx*sz-cx*sy*cz,sx*cz+cx*sy*sz,cx*cy]]


def mul(m,p):
    return [sum(m[i][j]*p[j] for j in range(3))for i in range(3)]


def posed(item,angles,center):
    r = [round(x,8)for x in angles]
    matrix = rotation(r)
    chunk = chunks[item["family"]]
    offset = mul(matrix,chunk["center"])
    position = [round(center[i]-offset[i],6)for i in range(3)]
    actual = [position[i]+offset[i]for i in range(3)]
    corners = []
    for signs in itertools.product((-1,1),repeat=3):
        d = mul(matrix,[signs[i]*chunk["size"][i]/2 for i in range(3)])
        corners.append([actual[i]+d[i]for i in range(3)])
    half = [(max(q[i]for q in corners)-min(q[i]for q in corners))/2 for i in range(3)]
    return r,position,actual,half,corners


# Pitch/yaw/roll deltas in degrees and X/Y center shifts. Nonmirrored, small
# departures; shoulder pieces lean outward, while cream faces break bands.
specs = [
    ("South Embedded 06-02", (6,22,-8), (-.62,.35), "left shoulder"),
    ("South Embedded 06-07", (-5,-26,11), (.25,.18), "right shoulder"),
    ("South Embedded 07-03", (7,24,-11), (-.16,-.38), "upper drawer face"),
    ("South Embedded 08-04", (-4,-24,7), (.17,-.32), "upper desk face"),
    ("NorthDJ Embedded 05-04", (-6,-31,-12), (-.15,.50), "middle drawer band"),
    ("NorthDJ Embedded 06-02", (5,23,12), (.12,.10), "left shoulder/drawer"),
    ("NorthDJ Embedded 06-04", (-4,-27,-11), (.12,-.65), "middle drawer band"),
    ("NorthDJ Embedded 06-05", (7,31,10), (-.08,.40), "central drawer band"),
    ("NorthDJ Embedded 07-04", (-5,-28,11), (-.15,.33), "upper drawer band"),
    ("NorthDJ Embedded 07-05", (6,23,-10), (.11,-.34), "upper drawer band"),
    ("NorthDJ Embedded 08-05", (-4,-21,6), (.18,-.80), "crest drawer face"),
    ("NorthDJ Embedded 05-07", (-5,-18,-12), (.65,.30), "right shoulder"),
]
changes = []
for name,degrees,shift,reason in specs:
    item = by_name[name]
    old = deepcopy(item)
    for factor in (1.0,.90,.80,.70):
        angles = [old["rotation"][i]+math.radians(degrees[i])*factor for i in range(3)]
        center = old["bboxCenter"][:]
        center[0] += shift[0]*factor
        center[1] += shift[1]*factor
        r,p,c,h,corners = posed(item,angles,center)
        if max(math.hypot(q[0],max(0,q[1]-1))for q in corners)>33.55:
            continue
        if name.startswith("NorthDJ") and min(q[2]for q in corners)<129.9815615356461:
            continue
        if min(q[1]for q in corners)<-.025:
            continue
        item.update(rotation=r,robloxPosition=p,bboxCenter=[round(v,6)for v in c],bboxHalf=[round(v,6)for v in h])
        changes.append({"name":name,"reason":reason,"factor":factor,"degreeDeltas":[d*factor for d in degrees],"centerShiftXY":[d*factor for d in shift],"before":old,"after":deepcopy(item)})
        break
    else:
        raise AssertionError(name)

assert len(changes)==12
assert b["placements"][179:] == a["placements"][179:]
assert b["colliders"] == a["colliders"] and len(b["colliders"])==66
assert b["statistics"] == a["statistics"]
assert Counter(p["family"]for p in b["placements"])==Counter(p["family"]for p in a["placements"])
b["layoutRevision"] = 5
b["notes"].append("Second polish reposes twelve upper/middle backing faces and shoulder-edge pieces; all forty overlays, lower backing, foreground/crown and sixty-six curtains preserved. Counts/assets unchanged.")


def serialize(v):
    if isinstance(v,dict):return "{"+",".join("["+json.dumps(k)+"]="+serialize(x)for k,x in v.items())+"}"
    if isinstance(v,list):return "{"+",".join(map(serialize,v))+"}"
    if isinstance(v,str):return json.dumps(v,ensure_ascii=False)
    if isinstance(v,bool):return "true"if v else"false"
    return "nil"if v is None else str(v)


assert next(x for x in source.splitlines()if x.startswith("local PLAN = "))=="local PLAN = "+serialize(a)
candidate = "\n".join("local PLAN = "+serialize(b)if x.startswith("local PLAN = ")else x for x in source.split("\n"))
(HERE/"plan.json").write_text(json.dumps(b,indent=2)+"\n")
(HERE/"EndBlockades.ModuleScript.candidate.luau").write_text(candidate)
receipt = {"schema":"r4-backing-face-polish-v2","baselineSourceSHA256":PIN,"candidateSourceSHA256":sha(candidate.encode()),"candidatePlanSHA256":sha((HERE/"plan.json").read_bytes()),"changedBackingFaces":12,"instances":219,"extraInstancedTriangles":220612,"all40OverlaysPreserved":True,"all66CurtainsPreserved":True,"runtimeFunctionsUnchanged":True,"newUniqueMeshes":0,"interface":"Add(model, kit, manifest)","changes":changes,"authorityLimit":"Runtime Server reference only; root must compare fresh Edit Source/editor/identity inside CAS."}
(ART/"placement-delta.json").write_text(json.dumps(receipt,indent=2)+"\n")
print(json.dumps({k:v for k,v in receipt.items()if k!="changes"},indent=2))
