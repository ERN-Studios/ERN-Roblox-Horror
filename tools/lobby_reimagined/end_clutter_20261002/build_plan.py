"""Additive layout only; reuses the installed R4 Blender mesh kit unchanged.

This script does not contact Studio, mutate the authoritative manifest, or edit
existing authoring files. Output positions and rotations use Roblox coordinates.
"""
from pathlib import Path
import json, math, random
ROOT=Path(__file__).resolve().parents[3]
OUT=Path(__file__).resolve().parent
m=json.loads((ROOT/'assets/models/lobby-reimagined-r4-20261001/manifest.json').read_text())
families=['Sofa','Desk','FilingCabinet','CRTMonitor','Photocopier','StackChair','VinylBench','WireTrolley','RolledCarpet']
chunks={f:next(c for c in m['chunks'] if c['family']==f) for f in families}

def rotation(rx,ry,rz):
    # Roblox CFrame.Angles Rx*Ry*Rz; same matrix order as the runtime emitter.
    sx,cx=math.sin(rx),math.cos(rx);sy,cy=math.sin(ry),math.cos(ry);sz,cz=math.sin(rz),math.cos(rz)
    return [[cy*cz,-cy*sz,sy], [cx*sz+sx*sy*cz,cx*cz-sx*sy*sz,-sx*cy], [sx*sz-cx*sy*cz,sx*cz+cx*sy*sz,cx*cy]]
def mul(a,p):return [sum(a[i][j]*p[j] for j in range(3)) for i in range(3)]
def bounds(fam,rot):
    mat=rotation(*rot); size=chunks[fam]['size']; corners=[mul(mat,[a*size[0]/2,b*size[1]/2,c*size[2]/2]) for a in (-1,1) for b in (-1,1) for c in (-1,1)]
    half=[max(abs(p[i]) for p in corners) for i in range(3)]
    return mat,corners,half
placements=[]; barriers=[];failures=[]
def emit(fam,center,rot,label):
    mat,corners,half=bounds(fam,rot)
    pose=[center[i]-mul(mat,chunks[fam]['center'])[i] for i in range(3)]
    for p in corners:
        x,y=center[0]+p[0],center[1]+p[1]
        if y<-.03 or x*x+max(0,y-1)**2>33.7**2:failures.append((label,x,y))
    placements.append({'name':label,'family':fam,'robloxPosition':[round(p,6) for p in pose], 'rotation':[round(p,8) for p in rot], 'bboxCenter':[round(p,6) for p in center], 'bboxHalf':[round(p,6) for p in half]})
    return half
for end,sign in [('South',-1),('NorthDJ',1)]:
    rng=random.Random(516029+(1 if sign>0 else 0))
    # A dense back layer follows the round arch; turned desks/cabinets are
    # interlocked like the reference rather than individual upright columns.
    for row, y in enumerate([2.05,5.6,9.2,12.8,16.4,20.0,23.6,27.2,30.7,33.2]):
        x=-31.5
        col=0
        while x<31.5:
            fam=rng.choice(['Desk','Desk','Sofa','VinylBench','FilingCabinet'])
            # Cabinet on its side becomes a broad, distinct drawer face.
            rolled=fam=='FilingCabinet'
            rot=(rng.uniform(-.10,.10), (math.pi if sign>0 else 0)+rng.uniform(-.20,.20), (math.pi/2 if rolled else 0)+rng.uniform(-.10,.10))
            mat,corners,half=bounds(fam,rot)
            cx=x+half[0]
            floor=.8 if abs(cx)+half[0]>=16.2 else 0
            center=[cx,max(y,floor+half[1]),sign*rng.uniform(134.2,134.6)]
            # Reject an entire bounding box if it pierces the curved shell.
            fits=all((center[0]+p[0])**2+max(0,center[1]+p[1]-1)**2<=33.55**2 for p in corners)
            if fits:emit(fam,center,rot,f'{end} Embedded {row:02d}-{col:02d}')
            x+=max(2.4,half[0]*2-.30)
            col+=1
    # A small irregular crown closes the last course towards the ceiling.
    # Narrow CRTs and one sideways cabinet fit where wide sofas cannot.
    for crown,fam,cx,cy,roll in [(0,'CRTMonitor',-3.9,32.55,-.025),(1,'FilingCabinet',.1,32.85,math.pi/2),(2,'CRTMonitor',3.8,32.58,.022)]:
        rot=(0,math.pi if sign>0 else 0,roll)
        _,corners,half=bounds(fam,rot)
        if all((cx+p[0])**2+max(0,cy+p[1]-1)**2<33.55**2 for p in corners):
            emit(fam,[cx,cy,sign*134.8],rot,f'{end} Ceiling crown {crown:02d}')
    # Foreground legged furniture and recognisable CRT/copier clutter disguise
    # the background's packed courses. DJ-front clearance is deliberate.
    for idx,x in enumerate([-29,-23,-17,-11,-5,1,7,13,19,25,30]):
        if sign>0 and abs(x)<17:continue
        fam=['Sofa','Photocopier','FilingCabinet','WireTrolley','VinylBench','Desk'][idx%6]
        rot=(0,(math.pi if sign>0 else 0)+rng.uniform(-.33,.33),0)
        _,corners,half=bounds(fam,rot)
        floor=.8 if abs(x)+half[0]>=16.2 else 0
        # Near-end foreground reaches z=-128, far-end pieces remain beyond+130.8.
        zz=sign*(132.6 if sign>0 else 129.6)
        center=[x,floor+half[1],zz]
        if all((x+p[0])**2+max(0,center[1]+p[1]-1)**2<33.55**2 for p in corners):
            emit(fam,center,rot,f'{end} Foreground {idx:02d}')
            # CRTs sit on genuine desk/copier/cabinet support tops only.
            if fam in ['Desk','Photocopier','FilingCabinet']:
                cfamily='CRTMonitor'; crot=(0,rot[1]+rng.uniform(-.25,.25),0)
                _,_,ch=bounds(cfamily,crot)
                emit(cfamily,[x,center[1]+half[1]+ch[1]-.04,zz],crot,f'{end} Supported CRT {idx:02d}')
    # A few chairs are visibly wedged into the packed background, not used as
    # supports. Their deep side parts overlap a background volume by design.
    for idx,x in enumerate([-26,-19,-12,-5,4,11,18,25]):
        y=rng.uniform(7,19)
        rot=(rng.uniform(-.5,.5), (math.pi if sign>0 else 0)+rng.uniform(-.5,.5), rng.choice([-1,1])*rng.uniform(.25,.8))
        _,corners,half=bounds('StackChair',rot)
        if all((x+p[0])**2+max(0,y+p[1]-1)**2<33.55**2 for p in corners):emit('StackChair',[x,y,sign*132.2],rot,f'{end} Wedged chair {idx:02d}')
    # Transparent full-width barrier is wholly behind DJ rail / foreground.
    # Top edges follow the arch; separate columns avoid square overhangs.
    for idx,x in enumerate(range(-32,33,2)):
        width=2.08; edge=min(33.78,abs(x)+width/2)
        # Narrow outer columns have >8-stud tops instead of a low jumpable
        # side step, while every rectangle stays below the curved shell.
        height=1+math.sqrt(max(0,33.8**2-edge**2))
        barriers.append({'name':f'{end} Furniture Blocker {idx:02d}','position':[x,height/2,sign*132.0], 'size':[width,height,1.0]})
# Inspect exact measured load, not an estimate of unique geometry.
triangles=sum(chunks[p['family']]['triangles'] for p in placements)
plan={'schema':'lobby-r4-additive-end-clutter-v1','baseManifestSHA256':'17b68efc473a0f100cf6ce6b9389332a5f2a87d82faf7694a0536a82483bc995','previewCenter':m['previewCenter'],'axisMapping':'Roblox X,Y,Z; CFrame.Angles XYZ radians','reuseInstalledBlenderFamilies':True,'placements':placements,'colliders':barriers,'statistics':{'instances':len(placements),'extraInstancedTriangles':triangles,'uniqueNewMeshes':0,'archCornerFailures':len(failures)}, 'notes':['Dense lower-middle-class 1990s furniture blockade at both tunnel ends.','Central north pile stays behind DJ rear guard at local z=128.4.','Intentional embedding in clutter; no unrelated lobby edits.','Use center-relative placements; source mesh offset is already compensated.']}
assert not failures,failures[:6]
(OUT/'plan.json').write_text(json.dumps(plan,indent=2)+'\n')
print(plan['statistics'])
