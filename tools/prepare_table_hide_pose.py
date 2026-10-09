"""Fit a compact authored hide pose against the measured R15 joint attachments.

Read-only geometry math. This prepares authoring parameters; Blender bakes the
actual action and Roblox performs the final visual/runtime validation.
"""
from pathlib import Path
import json
import math
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/animations/table-hiding'
DATA = json.loads((ROOT / 'artifacts/trello-20260915/codex-hiding-rig.json').read_text())
PARTS = {p['name']: p for p in DATA['parts']}
JOINTS = DATA['joints']

def matrix(a):
    m = np.eye(4)
    m[:3, 3] = a[:3]
    m[:3, :3] = np.array(a[3:]).reshape(3, 3)
    return m

def transform(x=0, y=0, z=0, rx=0, ry=0, rz=0):
    a,b,c = np.radians([rx,ry,rz])
    cx,sx,cy,sy,cz,sz = math.cos(a),math.sin(a),math.cos(b),math.sin(b),math.cos(c),math.sin(c)
    m = np.eye(4)
    m[:3,:3] = np.array([[1,0,0],[0,cx,-sx],[0,sx,cx]]) @ np.array([[cy,0,sy],[0,1,0],[-sy,0,cy]]) @ np.array([[cz,-sz,0],[sz,cz,0],[0,0,1]])
    m[:3,3] = [x,y,z]
    return m

ORDER = []
known = {'HumanoidRootPart'}
while len(ORDER) < len(JOINTS):
    eligible = [j for j in JOINTS if j['part0'] in known and j['part1'] not in known]
    if not eligible: raise RuntimeError('Disconnected rig')
    for j in eligible:
        j = dict(j, C0=matrix(j['c0']), C1inv=np.linalg.inv(matrix(j['c1'])))
        ORDER.append(j)
        known.add(j['part1'])

def poses(v):
    dy,dz,root,waist,neck,hip,knee,ankle,shoulder,elbow,spread,armRoll,armYaw,elbowYaw = v
    out = {'Root':transform(y=dy,z=dz,rx=root), 'Waist':transform(rx=waist), 'Neck':transform(rx=neck)}
    for side,sign in [('Left',1),('Right',-1)]:
        out[side+'Hip']=transform(rx=hip,ry=sign*7,rz=-sign*spread)
        out[side+'Knee']=transform(rx=knee)
        out[side+'Ankle']=transform(rx=ankle)
        out[side+'Shoulder']=transform(rx=shoulder,ry=sign*armYaw,rz=sign*armRoll)
        out[side+'Elbow']=transform(rx=elbow,ry=sign*elbowYaw,rz=-sign*5)
        out[side+'Wrist']=np.eye(4)
    return out

def forward(pose):
    world={'HumanoidRootPart':np.eye(4)}
    for j in ORDER:
        world[j['part1']]=world[j['part0']] @ j['C0'] @ pose.get(j['name'],np.eye(4)) @ j['C1inv']
    return world

CORNERS={}
for name in known-{'HumanoidRootPart'}:
    size=np.array(PARTS[name]['size'])/2
    CORNERS[name]=np.array([[x*size[0],y*size[1],z*size[2],1] for x in [-1,1] for y in [-1,1] for z in [-1,1]])

def bounds(v):
    world=forward(poses(v))
    return {n:(c @ world[n].T)[:,:3] for n,c in CORNERS.items()}

SEED=np.array([-.4,.5,5,-80,10,120,-135,25,55,-95,4,35,20,15],dtype=float)
LIMITS=np.array([[-1.7,.5],[-1,1.2],[-30,30],[-120,-15],[-50,60],[65,170],[-175,-70],[-60,90],[-100,130],[-160,20],[0,20],[-30,70],[-80,80],[-90,90]])

def score(v):
    points=bounds(v)
    allp=np.concatenate(list(points.values()))
    # The actual table collider underside is root+.56. Keep 0.05 stud clearance.
    violation=np.maximum(allp[:,1]-.50,0)**2 + np.maximum(-2.18-allp[:,1],0)**2
    violation+=np.maximum(abs(allp[:,0])-1.50,0)**2
    violation+=np.maximum(abs(allp[:,2])-2.05,0)**2
    # Avoid solving fit with an inverted neck/limb; keep near a recognisable crouch.
    regular=np.sum(((v-SEED)/np.array([1,1]+[100]*12))**2)*.007
    # Feet should be close to the floor, chest facing forward, hands drawn inward.
    foot_centres=[points[n].mean(0)[1] for n in ['LeftFoot','RightFoot']]
    return violation.sum()*10 + regular + sum((y+1.82)**2 for y in foot_centres)*.02

def solve():
    rng=np.random.default_rng(99)
    best=SEED.copy(); bestscore=score(best)
    for restart in range(16):
        v=best.copy() if restart==0 else np.clip(best+rng.normal(0,1,14)*np.array([.18,.15]+[12]*12),LIMITS[:,0],LIMITS[:,1])
        s=score(v)
        for scale in [1,.5,.2,.08,.03]:
            steps=np.array([.09,.09]+[4]*12)*scale
            for _ in range(18):
                changed=False
                for i in rng.permutation(14):
                    for sign in [-1,1]:
                        candidate=v.copy();candidate[i]=np.clip(candidate[i]+steps[i]*sign,*LIMITS[i])
                        trial=score(candidate)
                        if trial<s: v,s=candidate,trial;changed=True
                if not changed: break
        if s<bestscore: best,bestscore=v.copy(),s
    OUT.mkdir(parents=True,exist_ok=True)
    bb=bounds(best)
    report={n:{'min':p.min(0).tolist(),'max':p.max(0).tolist()} for n,p in bb.items()}
    result={'parameters':best.tolist(),'parameterNames':['rootY','rootZ','rootPitch','waistPitch','neckPitch','hipPitch','kneePitch','anklePitch','shoulderPitch','elbowPitch','hipSpread','armRoll','armYaw','elbowYaw'],'score':bestscore,'jointTransforms':{n:m.tolist() for n,m in poses(best).items()},'bounds':report,'rootFloorHeight':2.20,'colliderUnderside':2.76,'note':'Full MeshPart bounding boxes; render and native verification still required. Excludes seam liners not joined by AnimationConstraints. Physical table depth permits +/-2.05 while hide volume is +/-1.5; verify body stays visually concealed.'}
    (OUT/'authored-pose.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({'score':bestscore,'parameters':best.tolist(),'min':np.concatenate(list(bb.values())).min(0).tolist(),'max':np.concatenate(list(bb.values())).max(0).tolist()}))

if __name__=='__main__': solve()
