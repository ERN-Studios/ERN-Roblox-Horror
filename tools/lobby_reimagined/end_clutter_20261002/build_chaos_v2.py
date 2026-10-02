"""V2 layout-only revision of pinned v1, preserving all meshes and family counts."""
from pathlib import Path
import json, math, random, hashlib
ROOT=Path(__file__).resolve().parents[3]
P=Path(__file__).resolve().parent
base=json.loads((P/'plan.v1.json').read_text())
m=json.loads((ROOT/'assets/models/lobby-reimagined-r4-20261001/manifest.json').read_text())
chunks={c['family']:c for c in m['chunks'] if c['materialKey']=='atlas'}
def rotation(rx,ry,rz):
 sx,cx=math.sin(rx),math.cos(rx);sy,cy=math.sin(ry),math.cos(ry);sz,cz=math.sin(rz),math.cos(rz)
 return [[cy*cz,-cy*sz,sy],[cx*sz+sx*sy*cz,cx*cz-sx*sy*sz,-sx*cy],[sx*sz-cx*sy*cz,sx*cz+cx*sy*sz,cx*cy]]
def mul(a,p):return [sum(a[i][j]*p[j] for j in range(3)) for i in range(3)]
def geometry(fam,angles):
 mat=rotation(*angles);s=chunks[fam]['size'];corners=[mul(mat,[a*s[0]/2,b*s[1]/2,c*s[2]/2])for a in [-1,1]for b in [-1,1]for c in [-1,1]]
 return mat,corners,[max(abs(p[i])for p in corners)for i in range(3)]
def fit(center,corners):return all(center[1]+p[1]>=-.025 and (center[0]+p[0])**2+max(0,center[1]+p[1]-1)**2<=33.55**2 for p in corners)
rng=random.Random(613221);rows=[];unchanged=[];changed=[];attenuations={};northmin=1000;radiusmax=0
for old in base['placements']:
 item=dict(old);fam=item['family'];end=1 if item['name'].startswith('NorthDJ')else -1
 c0=old['bboxCenter'];a0=old['rotation']
 if ' Embedded ' not in item['name']:
  rows.append(item);unchanged.append(item['name']);continue
 # Separate the planes: strong projected lean, side faces, occasional sideways
 # desks, and uneven recess depth give silhouette chaos rather than shelf rows.
 signx=rng.choice([-1,1]);signz=rng.choice([-1,1])
 rx=signx*rng.uniform(math.radians(15),math.radians(32))
 ry=a0[1]+rng.uniform(-.6,.6)
 if fam in ['Desk','Sofa','VinylBench'] and rng.random()<.28:ry+=rng.choice([-1,1])*math.pi/2
 rz=a0[2]+signz*rng.uniform(math.radians(17),math.radians(35))
 if fam=='Desk' and 6<c0[1]<26 and rng.random()<.24:rz+=rng.choice([-1,1])*math.pi/2
 goal=[c0[0]+rng.uniform(-.7,.7),c0[1]+rng.uniform(-.85,.85),0]
 desiredz=133.25+.040*c0[1]+rng.uniform(-1.4,1.4)
 accepted=None
 for k in [1,.85,.7,.55,.4,.25,.1,0]:
  a=[a0[i]+([rx,ry,rz][i]-a0[i])*k for i in range(3)]
  mat,cs,half=geometry(fam,a)
  c=[c0[i]+(goal[i]-c0[i])*k for i in range(2)]+[0]
  floor=.8 if abs(c[0])+half[0]>=16.2 else 0
  c[1]=max(c[1],floor+half[1])
  zlo=(130.05 if end>0 else 126.8)+half[2]
  zhi=138.35-half[2]
  if zlo>zhi:continue
  c[2]=end*max(zlo,min(zhi,desiredz))
  if not fit(c,cs):continue
  accepted=(a,mat,cs,half,c,k);break
 assert accepted is not None,item['name']
 a,mat,cs,half,c,k=accepted
 sourcecenter=mul(mat,chunks[fam]['center']);pose=[c[i]-sourcecenter[i]for i in range(3)]
 item.update(rotation=[round(x,8)for x in a],robloxPosition=[round(x,6)for x in pose],bboxCenter=[round(x,6)for x in c],bboxHalf=[round(x,6)for x in half])
 rows.append(item);changed.append(item['name']);attenuations[str(k)]=attenuations.get(str(k),0)+1
 # Recheck exact serialised candidate, not only its in-memory float precursor.
 mm,ss,hh=geometry(fam,item['rotation']);cc=[item['robloxPosition'][i]+mul(mm,chunks[fam]['center'])[i]for i in range(3)]
 assert fit(cc,ss),item['name']
 radiusmax=max(radiusmax,max(math.hypot(cc[0]+p[0],max(0,cc[1]+p[1]-1))for p in ss))
 if end>0:northmin=min(northmin,cc[2]-hh[2])
base['placements']=rows;base['layoutRevision']=2;base['notes'].append('V2: variable pitch/roll15–35degrees, side-facing upholstery and sideways desks; ragged depth/height courses, exact arch containment.')
assert len(rows)==179
base['layoutPlanSHA256']='computed-in-receipt'
(P/'plan.json').write_text(json.dumps(base,indent=2)+'\n')
proof={'schema':'lobby-r4-end-clutter-chaos-v2-verification','layoutRevision':2,'baselinePlanSHA256':hashlib.sha256((P/'plan.v1.json').read_bytes()).hexdigest(),'planSHA256':hashlib.sha256((P/'plan.json').read_bytes()).hexdigest(),'instances':len(rows),'familyCountsPreserved':True,'newMeshes':0,'instancedTriangles':base['statistics']['extraInstancedTriangles'],'reorientedEmbeddedPieces':len(changed),'foregroundCrownWedgedChairsUnchanged':len(unchanged),'attenuationCounts':attenuations,'exactSerializedCornerRadialMaximum':radiusmax,'archLimit':33.55,'northMinimumZ':northmin,'northDJRearClearance':northmin-128.49,'collidersPreserved':len(base['colliders'])==66,'sourceSHA256':'populated-after-module-build','verificationScope':'Offline exact geometry; no visual or gameplay pass implied.'}
(P/'geometry-checks-v2.json').write_text(json.dumps(proof,indent=2)+'\n')
print(proof)
