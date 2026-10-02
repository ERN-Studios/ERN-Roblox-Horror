"""Restore dense pinned V1 and add exactly 20 irregular overlays per end.

No Studio writes. Original 179 placements, foreground supports, crowns, lenses,
and 66 blockers remain unchanged. V2 rotations are used only in front overlays.
"""
from pathlib import Path
import json,math,hashlib,random,collections
ROOT=Path(__file__).resolve().parents[3];P=Path(__file__).resolve().parent
v1=json.loads((P/'plan.v1.json').read_text());v2=json.loads((P/'plan.v2.json').read_text());m=json.loads((ROOT/'assets/models/lobby-reimagined-r4-20261001/manifest.json').read_text());chunks={x['family']:x for x in m['chunks']if x['materialKey']=='atlas'}
old_by_name={x['name']:x for x in v1['placements']}
def rotation(rx,ry,rz):
 sx,cx=math.sin(rx),math.cos(rx);sy,cy=math.sin(ry),math.cos(ry);sz,cz=math.sin(rz),math.cos(rz)
 return [[cy*cz,-cy*sz,sy],[cx*sz+sx*sy*cz,cx*cz-sx*sy*sz,-sx*cy],[sx*sz-cx*sy*cz,sx*cz+cx*sy*sz,cx*cy]]
def mul(a,p):return [sum(a[i][j]*p[j]for j in range(3))for i in range(3)]
def geo(fam,angles):
 mat=rotation(*angles);s=chunks[fam]['size'];cs=[mul(mat,[a*s[0]/2,b*s[1]/2,c*s[2]/2])for a in [-1,1]for b in [-1,1]for c in [-1,1]]
 return mat,cs,[max(abs(x[i])for x in cs)for i in range(3)]
overlays=[];support_proofs=[];rng=random.Random(332016)
quota={'South':{'Desk':12,'VinylBench':4,'FilingCabinet':2,'Sofa':2},'NorthDJ':{'Desk':11,'VinylBench':5,'FilingCabinet':2,'Sofa':2}}
for end in ['South','NorthDJ']:
 sg=1 if end=='NorthDJ'else -1;pool=[]
 for a in v2['placements']:
  if not a['name'].startswith(end)or' Embedded 'not in a['name']or not 6<a['bboxCenter'][1]<26:continue
  b=old_by_name[a['name']];depth=abs(b['bboxCenter'][2])-.8
  if sg>0 and depth-a['bboxHalf'][2]<129.95:continue
  if depth+a['bboxHalf'][2]>138.35:continue
  if abs(a['rotation'][0])<math.radians(14.9)or abs(a['rotation'][2]-b['rotation'][2])<math.radians(14.9):continue
  pool.append(a)
 rng.shuffle(pool)
 selected=[]
 for fam,count in quota[end].items():
  options=[x for x in pool if x['family']==fam]
  assert len(options)>=count,(end,fam,len(options))
  selected+=options[:count]
 for idx,a in enumerate(selected):
  b=old_by_name[a['name']];fam=a['family'];mat,cs,half=geo(fam,a['rotation']);center=a['bboxCenter'][:];center[2]=sg*(abs(b['bboxCenter'][2])-.8)
  posed=mul(mat,chunks[fam]['center']);pose=[center[i]-posed[i]for i in range(3)]
  item=dict(a);item.update(name=f'{end} Chaotic front overlay {idx:02d} {fam}',robloxPosition=[round(x,6)for x in pose],bboxCenter=[round(x,6)for x in center],bboxHalf=[round(x,6)for x in half],overlaySupport=b['name'])
  overlaps=[min(center[i]+half[i],b['bboxCenter'][i]+b['bboxHalf'][i])-max(center[i]-half[i],b['bboxCenter'][i]-b['bboxHalf'][i])for i in range(3)]
  assert min(overlaps)>.25,(item['name'],overlaps)
  overlays.append(item);support_proofs.append({'overlay':item['name'],'base':b['name'],'overlapXYZ':overlaps,'towardViewerStuds':.8})
assert len(overlays)==40
plan=json.loads(json.dumps(v1));plan['placements']+=overlays;plan['layoutRevision']=3
extra=sum(chunks[x['family']]['triangles']for x in overlays)
plan['statistics']['instances']=len(plan['placements']);plan['statistics']['extraInstancedTriangles']+=extra
plan['notes'].append('V3 restores dense179-piece V1 backing and adds40strongly angled front overlays with overlapping support volumes; foreground/crown/blockers preserved.')
(P/'plan.json').write_text(json.dumps(plan,indent=2)+'\n')
maxrad=0;nmin=1000;below=0
for x in plan['placements']:
 mat,cs,half=geo(x['family'],x['rotation']);cc=[x['robloxPosition'][i]+mul(mat,chunks[x['family']]['center'])[i]for i in range(3)]
 for q in cs:
  maxrad=max(maxrad,math.hypot(cc[0]+q[0],max(0,cc[1]+q[1]-1)))
  assert cc[1]+q[1]>=-.025,x['name']
 if x['name'].startswith('NorthDJ'):nmin=min(nmin,cc[2]-half[2])
assert maxrad<33.55 and nmin-128.49>=1.4
assert plan['placements'][:179]==v1['placements'];assert plan['colliders']==v1['colliders']
proof={'schema':'lobby-r4-end-clutter-chaos-v3-verification','layoutRevision':3,'baselineV1PlanSHA256':hashlib.sha256((P/'plan.v1.json').read_bytes()).hexdigest(),'baselineV2PlanSHA256':hashlib.sha256((P/'plan.v2.json').read_bytes()).hexdigest(),'planSHA256':hashlib.sha256((P/'plan.json').read_bytes()).hexdigest(),'sourceSHA256':'populate-after-module-build','base179ExactlyRestored':True,'foregroundAndCrownExactlyRestored':True,'instances':219,'overlays':40,'overlaysPerEnd':20,'familyCounts':dict(collections.Counter(x['family']for x in overlays)),'baseInstancedTriangles':180840,'overlayTriangles':extra,'totalExtraInstancedTriangles':plan['statistics']['extraInstancedTriangles'],'newUniqueMeshes':0,'blockersUnchanged':66,'exactSerializedCornerMaximumRadius':maxrad,'archRadiusLimit':33.55,'northMinZ':nmin,'northDJRearClearance':nmin-128.49,'minOverlayUnderlyingAABBIntersection':min(min(x['overlapXYZ'])for x in support_proofs),'overlapProofs':support_proofs,'verificationScope':'Offline exact geometry/support-volume overlap. Root must inspect actual Play for visible contacts and texture/lighting.'}
(P/'geometry-checks-v3.json').write_text(json.dumps(proof,indent=2)+'\n');print({k:v for k,v in proof.items()if k!='overlapProofs'})
