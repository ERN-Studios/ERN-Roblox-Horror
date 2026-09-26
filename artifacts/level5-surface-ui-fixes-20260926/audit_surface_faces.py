#!/usr/bin/env python3
"""Bounded offline overlap audit of exported Roblox BasePart cf/size geometry.

This is a rendering-risk diagnostic, not a rasterizer or a collision test. It
compares same-facing cardinal planes (including yawed horizontal rectangles),
clips their actual rectangles and samples outward visibility against other
opaque boxes. Exact overlaps and deliberately separated close layers are kept
in distinct categories. It never modifies a place, source or input export.
"""
import argparse
import collections
import glob
import hashlib
import itertools
import json
import math
from pathlib import Path
import time

CELL = 32.0


def cross(a, b, p):
    return (b[0]-a[0])*(p[1]-a[1])-(b[1]-a[1])*(p[0]-a[0])


def polygon_area(poly):
    return abs(sum(a[0]*b[1]-a[1]*b[0] for a, b in zip(poly, poly[1:]+poly[:1])))*.5


def ccw(poly):
    signed=sum(a[0]*b[1]-a[1]*b[0] for a, b in zip(poly, poly[1:]+poly[:1]))
    return poly if signed >= 0 else list(reversed(poly))


def intersection(subject, clip):
    out=subject
    for a, b in zip(clip, clip[1:]+clip[:1]):
        inp=out;out=[]
        if not inp:
            break
        prev=inp[-1];dp=cross(a,b,prev)
        for current in inp:
            dc=cross(a,b,current)
            if (dc>=-1e-7)!=(dp>=-1e-7):
                ratio=dp/(dp-dc)
                out.append((prev[0]+ratio*(current[0]-prev[0]),prev[1]+ratio*(current[1]-prev[1])))
            if dc>=-1e-7:
                out.append(current)
            prev=current;dp=dc
    return out


def tiles(low, high):
    return range(math.floor(low/CELL),math.floor(high/CELL)+1)


def is_textured(row):
    material=row["material"].rsplit(".",1)[-1]
    return bool(row.get("variant")) or material not in {"SmoothPlastic","Glass","Metal","Neon"}


def prepare(rows):
    boxes=[];grid=collections.defaultdict(list);skipped=collections.Counter()
    for row in rows:
        if row.get("transparency",0)>.01:
            skipped["nonopaque"]+=1;continue
        if row["class"]!="Part":
            skipped["nonbox_class"]+=1;continue
        cf=row["cf"];c=cf[:3];s=row["size"]
        columns=[(cf[3+i],cf[6+i],cf[9+i]) for i in range(3)]
        extent=[sum(abs(columns[j][i])*s[j]/2 for j in range(3)) for i in range(3)]
        box={"row":row,"center":c,"columns":columns,"half":[x/2 for x in s],
             "min":[c[i]-extent[i] for i in range(3)],"max":[c[i]+extent[i] for i in range(3)],"textured":is_textured(row)}
        idx=len(boxes);boxes.append(box)
        for cell in itertools.product(*(tiles(box["min"][i],box["max"][i]) for i in range(3))):
            grid[cell].append(idx)
    return boxes,grid,skipped


def faces_for(box,index,min_area):
    c=box["center"];cols=box["columns"];half=box["half"]
    for local_axis,normal in enumerate(cols):
        axis=max(range(3),key=lambda i:abs(normal[i]))
        if abs(normal[axis])<1-1e-6:
            continue
        rest=[i for i in range(3) if i!=axis]
        axes=[i for i in range(3) if i!=local_axis]
        if 4*half[axes[0]]*half[axes[1]]<min_area:
            continue
        for side in (-1,1):
            origin=[c[i]+normal[i]*side*half[local_axis] for i in range(3)]
            points=[]
            for su,sv in ((-1,-1),(1,-1),(1,1),(-1,1)):
                world=[origin[i]+su*half[axes[0]]*cols[axes[0]][i]+sv*half[axes[1]]*cols[axes[1]][i] for i in range(3)]
                points.append(tuple(world[i] for i in rest))
            polygon=ccw(points)
            yield {"box":index,"axis":axis,"sign":1 if side*normal[axis]>0 else -1,
                   "plane":origin[axis],"rest":rest,"poly":polygon,
                   "min":[min(v[i] for v in polygon) for i in range(2)],
                   "max":[max(v[i] for v in polygon) for i in range(2)],
                   "face":("X","Y","Z")[local_axis]+("+" if side>0 else "-")}


def point_inside(box,point):
    delta=[point[i]-box["center"][i] for i in range(3)]
    return all(abs(sum(delta[i]*column[i] for i in range(3)))<box["half"][j]-1e-5
               for j,column in enumerate(box["columns"]))


def visibility(poly,a,b,boxes,grid):
    center=tuple(sum(v[i] for v in poly)/len(poly) for i in range(2))
    samples=[center]
    for p,q in zip(poly,poly[1:]+poly[:1]):
        samples.append(tuple(center[i]+.65*(p[i]-center[i]) for i in range(2)))
        samples.append(tuple(center[i]+.65*((p[i]+q[i])/2-center[i]) for i in range(2)))
    plane=(max(a["plane"],b["plane"]) if a["sign"]>0 else min(a["plane"],b["plane"]))+a["sign"]*.006
    exposed=0
    for sample in samples:
        point=[0.,0.,0.];point[a["axis"]]=plane
        for i,axis in enumerate(a["rest"]):point[axis]=sample[i]
        cell=tuple(math.floor(x/CELL) for x in point)
        covered=False
        for idx in grid.get(cell,()):
            if idx not in (a["box"],b["box"]) and point_inside(boxes[idx],point):
                covered=True;break
        if not covered:exposed+=1
    return exposed,len(samples),center,plane


def descriptor(face,boxes):
    row=boxes[face["box"]]["row"]
    return {"path":row["path"],"name":row["name"],"face":face["face"],
            "center":[round(v,4) for v in row["cf"][:3]],"size":[round(v,4) for v in row["size"]],
            "material":row["material"],"variant":row["variant"]}


def floor_like(face,boxes):
    box=boxes[face["box"]];row=box["row"]
    return (row["material"].rsplit(".",1)[-1] in {"Fabric","Grass"}
            and box["max"][1]-box["min"][1]<=2
            and ".DomesticFurniture." not in row["path"])


def run(files,args):
    start=time.monotonic();rows=[];digests=[]
    for file in files:
        data=file.read_bytes();chunk=json.loads(data)
        if not isinstance(chunk,list):raise ValueError(f"Expected list in {file}")
        rows.extend(chunk);digests.append({"file":file.name,"records":len(chunk),"sha256":hashlib.sha256(data).hexdigest()})
    boxes,box_grid,skipped=prepare(rows)
    faces=[];face_grid=collections.defaultdict(list)
    for i,box in enumerate(boxes):
        for face in faces_for(box,i,args.min_area):
            idx=len(faces);faces.append(face)
            bucket=math.floor(face["plane"]/args.near)
            for u,v in itertools.product(tiles(face["min"][0],face["max"][0]),tiles(face["min"][1],face["max"][1])):
                face_grid[(face["axis"],face["sign"],bucket,u,v)].append(idx)
    totals=collections.Counter();near_occlusion=collections.Counter();groups=collections.defaultdict(lambda:{"count":0,"overlapArea":0.,"names":None,"samplePairs":[]})
    candidates=[];pairs_considered=0;limited=False
    for i,a in enumerate(faces):
        if time.monotonic()-start>args.max_seconds:
            limited=True;break
        peers=set();bucket=math.floor(a["plane"]/args.near)
        for offset in (-1,0,1):
            for u,v in itertools.product(tiles(a["min"][0],a["max"][0]),tiles(a["min"][1],a["max"][1])):
                peers.update(face_grid.get((a["axis"],a["sign"],bucket+offset,u,v),()))
        for j in peers:
            if j<=i:continue
            b=faces[j]
            if a["box"]==b["box"] or not (boxes[a["box"]]["textured"] or boxes[b["box"]]["textured"]):continue
            gap=abs(a["plane"]-b["plane"])
            if gap>args.near:continue
            if any(min(a["max"][k],b["max"][k])-max(a["min"][k],b["min"][k])<=.001 for k in range(2)):continue
            pairs_considered+=1
            poly=intersection(a["poly"],b["poly"])
            if len(poly)<3:continue
            area=polygon_area(poly)
            if area<args.min_area:continue
            if a["axis"]==1 and a["sign"]>0:
                category="floor_top" if floor_like(a,boxes) or floor_like(b,boxes) else "other_horizontal_top"
            else:
                category="underside" if a["axis"]==1 else "wall"
            kind="exact" if gap<=args.exact else "near_layer"
            visible,total,center,plane=visibility(poly,a,b,boxes,box_grid)
            if visible==0:
                totals["suppressed_buried_"+kind]+=1;continue
            pair_occlusion=None
            if kind=="near_layer":
                # Supplemental classification only: the original near-layer
                # count intentionally means plane proximity, not two separately
                # visible surfaces. Keep counts comparable with baseline v3.
                inside=[]
                for face,other in ((a,b),(b,a)):
                    point=[0.,0.,0.];point[face["axis"]]=face["plane"]+face["sign"]*min(.0001,gap/4)
                    for k,axis in enumerate(face["rest"]):point[axis]=center[k]
                    inside.append(point_inside(boxes[other["box"]],point))
                pair_occlusion="a_inside_b" if inside[0] else "b_inside_a" if inside[1] else "neither_inside_at_center"
                near_occlusion[category+":"+pair_occlusion]+=1
            totals[kind+"_"+category]+=1
            da,db=descriptor(a,boxes),descriptor(b,boxes)
            names=tuple(sorted((da["name"],db["name"])))
            group=groups[(kind,category,names)];group["count"]+=1;group["overlapArea"]+=area;group["names"]=names
            if len(group["samplePairs"])<2:
                group["samplePairs"].append({"a":da,"b":db,"nearPairOcclusionAtCenter":pair_occlusion})
            point=[0.,0.,0.];point[a["axis"]]=plane
            for k,axis in enumerate(a["rest"]):point[axis]=center[k]
            candidates.append({"kind":kind,"category":category,"planeGap":round(gap,6),"overlapArea":round(area,4),
                "exposedSamples":visible,"visibilitySamples":total,"samplePosition":[round(v,4) for v in point],
                "nearPairOcclusionAtCenter":pair_occlusion,"a":da,"b":db})
    candidates.sort(key=lambda x:(x["kind"]=="exact",x["category"]=="floor_top",x["overlapArea"]*x["exposedSamples"]/x["visibilitySamples"]),reverse=True)
    ranking=[]
    for (kind,category,names),group in groups.items():
        ranking.append({"kind":kind,"category":category,"names":list(names),"count":group["count"],"overlapArea":round(group["overlapArea"],3),"samplePairs":group["samplePairs"]})
    ranking.sort(key=lambda x:(x["kind"]=="exact",x["overlapArea"]),reverse=True)
    return {"version":"2026-09-26.offline-surfaces.5","status":"INCOMPLETE" if limited else "COMPLETE_AUDIT",
        "durationSeconds":round(time.monotonic()-start,3),"inputRecords":len(rows),"opaqueBoxes":len(boxes),"testedFaces":len(faces),
        "inputFiles":digests,"skipped":dict(skipped),"settings":{"nearPlaneDistance":args.near,"exactTolerance":args.exact,"minimumOverlapArea":args.min_area,"maxSeconds":args.max_seconds},
        "pairsConsidered":pairs_considered,"counts":dict(totals),"topGroups":ranking[:80],"nearGroups":[g for g in ranking if g["kind"]=="near_layer"][:60],
        "nearPairOcclusionAtCenter":dict(near_occlusion),"candidateCount":len(candidates),
        "topCandidates":candidates[:args.top],"omittedCandidates":max(0,len(candidates)-args.top),
        "limitations":["Candidate rendering risks, not observed pixel flicker or a pass/fail gameplay verdict",
            "Export lacks Part.Shape and mesh geometry; opaque Part records are modeled as boxes; WedgePart and transparent parts are excluded",
            "Same-facing cardinal normals only; includes yawed floor/ceiling polygons, excludes noncardinal roof/wall planes",
            "Minimum overlap and sampled visibility intentionally bound the audit; fully buried sampled faces are suppressed but complete visibility is not proven",
            "Near layers are separate from exact duplicates and may be intentional; small plane separation alone does not prove a rendering artifact",
            "Near-layer outward visibility tests the outermost plane with both candidate boxes excluded; nearPairOcclusionAtCenter explicitly records when the lower candidate is geometrically inside its partner",
            "Overlap-area totals sum face pairs and are not a union of unique surface area",
            "floor_top means a thin (<=2 studs vertical) Fabric/Grass part outside DomesticFurniture participates; other upward faces such as wall caps are categorized separately",
            "Includes material-variant and built-in textured materials; export does not include separate Texture/Decal/SurfaceGui properties"]}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prefix",required=True,help="Export prefix, e.g. qa/before-geometry (matches -N.json)")
    parser.add_argument("--output",required=True)
    parser.add_argument("--compare",help="Optional previous audit JSON")
    parser.add_argument("--near",type=float,default=.05)
    parser.add_argument("--exact",type=float,default=.002)
    parser.add_argument("--min-area",type=float,default=1.)
    parser.add_argument("--top",type=int,default=200)
    parser.add_argument("--max-seconds",type=float,default=120.)
    args=parser.parse_args()
    if args.near<=0 or not 0<=args.exact<=args.near:parser.error("Require 0 <= exact <= near, near > 0")
    files=[Path(p) for p in glob.glob(args.prefix+"-*.json")]
    files.sort(key=lambda p:int(p.stem.rsplit("-",1)[1]))
    if not files:parser.error("No export chunks found")
    report=run(files,args)
    if args.compare:
        before=json.loads(Path(args.compare).read_text());keys=sorted(set(before["counts"])|set(report["counts"]))
        report["comparison"]={"before":str(args.compare),"beforeStatus":before["status"],"sameSettings":before["settings"]==report["settings"],
            "countChanges":{k:{"before":before["counts"].get(k,0),"after":report["counts"].get(k,0),"delta":report["counts"].get(k,0)-before["counts"].get(k,0)} for k in keys}}
    Path(args.output).write_text(json.dumps(report,indent=2)+"\n")
    print(json.dumps({k:report[k] for k in ("status","durationSeconds","inputRecords","testedFaces","candidateCount","counts")},indent=2))
    print("TOP GROUPS",json.dumps([{k:v for k,v in x.items() if k!="samplePairs"} for x in report["topGroups"][:12]]))


if __name__=="__main__":main()
