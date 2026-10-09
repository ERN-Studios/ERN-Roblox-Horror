"""Fit actual mesh convex hulls, with an upright gaze and anatomically tucked limbs."""
from pathlib import Path
import json
import numpy as np
from scipy.spatial import ConvexHull
from scipy.optimize import minimize, differential_evolution
from blender_mcp_client import execute
from prepare_table_hide_pose import poses, forward, matrix
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/animations/table-hiding'

export_code=r'''
import bpy,json
from mathutils import Matrix
B=Matrix(((1,0,0,0),(0,0,-1,0),(0,1,0,0),(0,0,0,1)))
scene=bpy.data.scenes['Zyntra_TableHide_Actual_20260916']
data={o['roblox_part']:[[*(B.inverted()@v.co)] for v in o.data.vertices] for o in scene.objects if o.get('roblox_part')}
open(r'G:\Roblox\MongoTV\_local\trello-20260916\character-export\local-vertices.json','w').write(json.dumps(data))
result={n:len(v) for n,v in data.items()}
'''

def main():
    execute(export_code)
    raw=json.loads((ROOT/'_local/trello-20260916/character-export/local-vertices.json').read_text())
    export=json.loads((ROOT/'artifacts/trello-20260916/character-export-rig.json').read_text())
    ep={p['name']:p for p in export['parts']}
    hulls={}
    for n,verts in raw.items():
        v=np.array(verts); v=v[ConvexHull(v).vertices]
        v=np.column_stack((v,np.ones(len(v))))
        if n.endswith('SeamLiner'):
            v=v@(np.linalg.inv(matrix(ep['UpperTorso']['cf']))@matrix(ep[n]['cf'])).T
        hulls[n]=v
    def points(v):
        world=forward(poses(v))
        return {n:(p@world[n if n in world else 'UpperTorso'].T)[:,:3] for n,p in hulls.items()}
    seed=np.array([-.4,.3,15,-85,55,135,-155,5,-30,-85,4,25,-20,15.])
    limits=[[-1.6,.3],[-.5,1.1],[-10,30],[-105,-55],[15,70],[90,170],[-170,-105],[-30,65],[-110,110],[-145,-35],[0,18],[-70,70],[-85,85],[-60,60]]
    scale=np.array([.5,.8]+[50]*12)
    def score(v):
        p=points(v); allp=np.concatenate(list(p.values()))
        bad=np.maximum(allp[:,1]-.49,0)**2+np.maximum(-2.15-allp[:,1],0)**2
        bad+=np.maximum(abs(allp[:,0])-1.49,0)**2+np.maximum(abs(allp[:,2])-2.02,0)**2
        gaze=v[2]+v[3]+v[4]
        regular=np.sum(((v-seed)/scale)**2)*.02
        regular+=(gaze/30)**2*.04
        regular+=sum((p[n][:,1].min()+2.12)**2 for n in ['LeftFoot','RightFoot'])*.08
        for n,sign in [('LeftHand',-1),('RightHand',1)]:
            regular+=np.sum((p[n].mean(0)-np.array([sign*.78,-1.6,-1.05]))**2)*.18
        return bad.sum()*30+regular
    rng=np.random.default_rng(316)
    best=None
    for i in range(8):
        start=seed if i==0 else np.clip(best.x+rng.normal(0,1,14)*np.array([.1,.1]+[8]*12),np.array(limits)[:,0],np.array(limits)[:,1])
        solved=minimize(score,start,method='L-BFGS-B',bounds=limits,options={'maxiter':600,'ftol':1e-11})
        if best is None or solved.fun<best.fun:best=solved
        print('restart',i,'score',float(best.fun),flush=True)
    arm_indices=[8,9,11,12,13]
    fixed=best.x.copy()
    def arm_score(a):
        v=fixed.copy();v[arm_indices]=a
        return score(v)
    arms=differential_evolution(arm_score,[limits[i] for i in arm_indices],seed=318,maxiter=260,popsize=14,tol=1e-8,polish=True)
    if arms.fun<best.fun:best.x[arm_indices]=arms.x;best.fun=arms.fun
    p=points(best.x)
    data={'parameters':best.x.tolist(),'jointTransforms':{n:m.tolist() for n,m in poses(best.x).items()},'bounds':{n:{'min':a.min(0).tolist(),'max':a.max(0).tolist()} for n,a in p.items()},'score':float(best.fun),'source':'Actual StarterCharacter mesh convex hulls including seam liners','rootFloorHeight':2.2,'colliderUnderside':2.76}
    (OUT/'authored-actual-pose.json').write_text(json.dumps(data,indent=2)+'\n')
    print(json.dumps({'parameters':data['parameters'],'score':data['score']}))

if __name__=='__main__':main()
