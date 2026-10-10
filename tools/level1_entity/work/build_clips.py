"""ENTITY_MOTION_20261010. Author on the measured Studio rig; Blender is only the preview/bake host.

Run Blender -b --python work/build_clips.py -- [--only=Walk] [--no-render] [--floor-up=8]
FLOOR_UP is also an environment override. No assets are downloaded or published.
"""
import sys, os, json, math, argparse
from pathlib import Path
import numpy as np

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
from rig_math import Rig, rot_x, rot_y, rot_z, mat_to_quat, quat_to_mat, slerp

FLOOR_UP = float(os.environ.get('FLOOR_UP', '8.0'))
RIG = None
TAU = math.tau

def smooth(x):
    x = np.clip(x, 0.0, 1.0)
    return x*x*(3-2*x)

def mix(a,b,u): return np.asarray(a)*(1-u)+np.asarray(b)*u
def deg(x): return math.radians(x)
def rotation(pitch=0,yaw=0,roll=0):
    return rot_y(deg(yaw)) @ rot_z(deg(roll)) @ rot_x(deg(-pitch))
def point(x,height,forward): return np.array([x,height-FLOOR_UP,-forward],float)
def sequence_keys(keys,u):
    if u <= keys[0][0]: return np.asarray(keys[0][1],float)
    for (a,va),(b,vb) in zip(keys,keys[1:]):
        if u <= b: return mix(va,vb,smooth((u-a)/(b-a)))
    return np.asarray(keys[-1][1],float)

GAITS = {
    'Walk':dict(seconds=1.20,frames=72,speed=8.0,duty=.62,front=3.13,width=1.15,clear=.72,
                height=4.12,bob=.17,lean=24,yaw=8,list=3.2,sway=.24,heel=48),
    'Prowl':dict(seconds=.80,frames=64,speed=17.0,duty=.42,front=2.87,width=1.12,clear=1.18,
                 height=3.97,bob=.18,lean=32,yaw=10,list=3.8,sway=.17,heel=55),
    # RUN_CHARGE_20261010 (owner: "its chase/run animation is absolute dog shit, remake it"). Seen on the real body
    # the first run was the walk folded double: head at chest height, feet pattering under the hips, one arm pawing
    # ahead. This one is a heavy charge: chest and head up, long reaching strides with a real flight, a hard drop on
    # each landing, both arms pumping with the claws open.
    'Run':dict(seconds=.72,frames=72,speed=27.2,duty=.30,front=2.95,width=1.20,clear=2.25,
               height=3.92,bob=.50,lean=25,yaw=17,list=6.5,sway=.20,heel=72),
}

def foot_path(p,g,side):
    q=(p+(0 if side=='Left' else .5))%1
    d=g['duty']; stride=g['seconds']*g['speed']
    off=g['front']-stride*d
    if q < d:
        s=q/d
        f=g['front']-stride*q
        # The TOE is the exact contact point; heel roll never moves it.
        if g['speed']==8:
            pitch=18*(1-smooth(s/.12))-g['heel']*smooth((s-.55)/.45)
        else:
            pitch=-12*(1-smooth(s/.18))-g['heel']*smooth((s-.5)/.5)
        h=.035
        stance=True
    else:
        u=(q-d)/(1-d)
        h00=2*u**3-3*u*u+1; h10=u**3-2*u*u+u
        h01=-2*u**3+3*u*u; h11=u**3-u*u
        v=-stride*(1-d)
        f=h00*off+h10*v+h01*g['front']+h11*v
        # the charge kicks the heel up early behind the body and brings the knee through high
        h=.035+g['clear']*math.sin(math.pi*(u**.72 if g['speed']>20 else u))**2
        entry=18 if g['speed']==8 else -12
        pitch=float(sequence_keys([(0,-g['heel']),(.32,-32),(.72,22),(1,entry)],u))
        stance=False
    sign=-1 if side=='Left' else 1
    # Tracks stay fixed in stance. Swing narrows slightly before reaching outward.
    x=-.0937+sign*g['width']
    if not stance: x-=sign*.10*math.sin(math.pi*(q-d)/(1-d))**2
    return dict(toe=point(x,h,f),pitch=pitch,yaw=sign*9,stance=stance,phase=q)

def torso(pose,p,lean,yaw_amp,list_amp,sway,hip_height,hip_forward=-.44,wind=0,head=None):
    sn=math.sin(TAU*p); cs=math.cos(TAU*p)
    # Hips is yawed 16.5 degrees at rest. All deltas below are ROOT-space.
    RIG.set_root_rotation(pose,'Hips',rotation(lean*.68,yaw_amp*sn,list_amp*sn) @ RIG.rest_world['Hips'][:3,:3])
    H=RIG.fk(pose)['Hips'][:3,3]
    hiplocal=(RIG.rest['LeftUpLeg'][:3,3]+RIG.rest['RightUpLeg'][:3,3])*.5
    hr=RIG.fk(pose)['Hips'][:3,:3]
    desired=point(-.0937+sway*sn,hip_height,hip_forward)
    RIG.set_root_position(pose,'Hips',desired-hr@hiplocal)
    # Root-relative delta over the rest chain keeps all joint axes measured.
    for name,share in [('Spine02',.16),('Spine01',.10),('Spine',.06)]:
        world=RIG.fk(pose)
        baseline=world[name][:3,:3]
        counter=(-yaw_amp*.85*sn+wind) if name=='Spine' else 0
        roll=-list_amp*.6*sn if name=='Spine' else 0
        RIG.set_root_rotation(pose,name,rotation(lean*share,counter,roll)@baseline)
    # The gaze is stable in root coordinates despite the whole spine moving.
    if head is None:
        RIG.set_root_rotation(pose,'neck',rotation(-7,wind*.12,0)@RIG.rest_world['neck'][:3,:3])
        RIG.set_root_rotation(pose,'Head',rotation(4,1.0*sn,4)@RIG.rest_world['Head'][:3,:3])
    else:
        # the charge: the head is thrown up out of the hunch and held on the prey, rocking a little with each landing
        nod=2.5*math.cos(2*TAU*(p-.10))
        RIG.set_root_rotation(pose,'neck',rotation(head[0]+nod*.5,wind*.12,0)@RIG.rest_world['neck'][:3,:3])
        RIG.set_root_rotation(pose,'Head',rotation(head[1]+nod,2.5*sn,head[2])@RIG.rest_world['Head'][:3,:3])

def safe_wrist(pose,side,target,pole_offset=None):
    S=RIG.fk(pose)[side+'Arm'][:3,3]
    v=np.asarray(target)-S
    d=float(np.linalg.norm(v))
    if d>4.04: target=S+v*(4.04/d)
    sign=-1 if side=='Left' else 1
    # A stable elbow pole avoids axial flips when the wrist swings past the shoulder.
    # Elbows follow the sagittal bend plane, with a small outward bias.
    # A fixed wide pole looked like chicken wings in the front contact sheets.
    pole=S+np.array([sign*.35,v[2],-v[1]] if pole_offset is None else pole_offset)
    result=RIG.solve_chain(pose,side+'Arm',side+'ForeArm',side+'Hand',target,pole,clamp=False)
    return np.asarray(target), result

def arms_gait(pose,p,name):
    for side in ['Left','Right']:
        sign=-1 if side=='Left' else 1
        phase=p+(0 if side=='Left' else .5)
        S=RIG.fk(pose)[side+'Arm'][:3,3]
        if name=='Run':
            # Each arm pumps against its own leg: back and out as that foot lands, driven forward across the chest
            # as it pushes off. Elbows stay bent; the claws open at the front of the swing.
            fwd=-math.cos(TAU*(phase+.03))
            a=float(smooth(.5+.5*fwd))
            amp=1.08 if side=='Right' else .96
            # Seen from the front (where the hunted player is) the arms have to stay OUT of the face and read wide:
            # the forward hand comes up beside the chest, never across it; the back hand is thrown out behind the hip.
            front=np.array([sign*1.25,-1.00,-2.55*amp]); back=np.array([sign*1.95,-1.65,2.25*amp])
            target=S+mix(back,front,a)+np.array([0,-.50*(1-fwd*fwd),0])
            direction=mix(np.array([sign*.45,-.75,.50]),np.array([sign*.20,.15,-.97]),a)
            direction=direction/np.linalg.norm(direction)
            curl=.46-.28*a
        else:
            wave=math.sin(TAU*(phase+.07))
            amp=(1.03 if name=='Walk' else 1.50)*(1.12 if side=='Right' else .91)
            down=3.40 if name=='Walk' else 3.05
            target=S+np.array([sign*.12,-down+.20*wave,-(.5 if name=='Walk' else 1.05)-amp*wave])
            direction=np.array([sign*.14,-.94,-.30-.18*math.sin(TAU*(phase+.13))])
            curl=.23+.12*(1-wave)*.5
        safe_wrist(pose,side,target)
        RIG.orient_hand(pose,side,direction,np.array([-sign,0,-.2]))
        RIG.curl_fingers(pose,side,curl,.10 if name!='Run' else .24)

def reach_adjustment(pose,feet):
    world=RIG.fk(pose)
    required=0.0
    for side,foot in feet.items():
        ankle=foot['toe']-RIG.foot_rotation(side,foot['pitch'],foot['yaw'])@RIG.rest[side+'ToeBase'][:3,3]
        hip=world[side+'UpLeg'][:3,3]
        h2=float(np.sum((hip[[0,2]]-ankle[[0,2]])**2))
        if h2>=3.85**2:
            raise AssertionError(f'Horizontal {side} leg target unreachable: {math.sqrt(h2):.3f}')
        maxdy=math.sqrt(3.85**2-h2)
        required=max(required,float(hip[1]-ankle[1]-maxdy))
    return max(0,required)

def build_gait(name):
    g=GAITS[name]; N=g['frames']; poses=[]; feet_all=[]; lowers=[]
    for i in range(N):
        p=i/N
        pose={}
        # Contact dip followed by flight lift. Stance duty, not a sped-up walk, distinguishes the gaits.
        # the charge is lowest in the middle of each stance and highest in the middle of each flight
        bob=-g['bob']*math.cos(2*TAU*(p-(.09 if name=='Run' else .07)))
        lean=max(0,g['lean']-13.3)/.84+2*math.sin(2*TAU*(p-.07))
        torso(pose,p,lean,g['yaw'],g['list'],g['sway'],g['height']+bob,wind=3 if name!='Run' else -4,
              head=(-28,-30,3) if name=='Run' else None)
        feet={s:foot_path(p,g,s) for s in ['Left','Right']}
        poses.append(pose); feet_all.append(feet)
    origin=RIG.rest_world['Hips'][:3,3]
    mean=np.mean([RIG.fk(p)['Hips'][:3,3]-origin for p in poses],axis=0)
    for pose,feet in zip(poses,feet_all):
        H=RIG.fk(pose)['Hips'][:3,3].copy(); H[[0,2]]-=mean[[0,2]]
        RIG.set_root_position(pose,'Hips',H)
        lowers.append(reach_adjustment(pose,feet))
    # A periodic upper envelope lowers the hips BEFORE reach becomes impossible, with no target clamping/skating.
    sigma=N*.04
    envelopes=[]
    for i in range(N):
        envelopes.append(max(lowers[j]*math.exp(-min(abs(i-j),N-abs(i-j))**2/(2*sigma*sigma)) for j in range(N)))
    for i,pose in enumerate(poses):
        p=i/N; H=RIG.fk(pose)['Hips'][:3,3].copy(); H[1]-=envelopes[i]+.015
        RIG.set_root_position(pose,'Hips',H)
        for side,ft in feet_all[i].items():
            # the charge's foot leaves the floor fast: its toe unbends over more height or the joint snaps
            bend=max(0,-ft['pitch'])*(1-float(smooth((ft['toe'][1]+FLOOR_UP-.035)/(.9 if name=='Run' else .25))))
            RIG.solve_leg_toe(side,pose,ft['toe'],ft['pitch'],ft['yaw'],point(-.0937+(-1 if side=='Left' else 1)*1.3,2.0,5.0),toe_bend_deg=bend,clamp=False)
        arms_gait(pose,p,name)
    return dict(poses=poses,feet=feet_all,frames=N,fps=N/g['seconds'],seconds=g['seconds'],loop=True,
                stride=g['seconds']*g['speed'],speed=g['speed'],contacts=[0,.5],
                notes=f"IK toe tracks; duty {g['duty']:.2f}; max reach-driven hip correction {max(envelopes):.3f} stud; measured finger axes.")

def lunge_pose(name,u,run_zero):
    if name=='Lunge_Windup':
        height,f,lean,wind=sequence_keys([(0,[4.08,-.44,15,0]),(.31,[3.90,-.75,28,5]),(1,[3.02,-1.1,49,12])],u)
        left=point(-1.1,.035,2.25); right=point(1.05,.035,-2.4)
        feet={'Left':dict(toe=left,pitch=0,yaw=-9,stance=True),'Right':dict(toe=right,pitch=-48,yaw=9,stance=True)}
        wrists=sequence_keys([(0,[2.4,4.4,-1.1]),(.31,[2.4,4.25,-1.6]),(1,[2.65,4.65,-1.8])],u)
        curl=.12; spread=.40
    elif name=='Lunge_Flight':
        height,f,lean,wind=sequence_keys([(0,[3.02,-1.1,49,12]),(.25,[4.10,.30,65,-8]),(.5,[4.08,.32,68,-8]),(.78,[3.70,.45,72,-4]),(1,[3.2,.25,72,0])],u)
        feet={}
        for side in ['Left','Right']:
            sign=-1 if side=='Left' else 1
            # Let the heels trail below the hip rather than sweep through its IK pole.
            toe=sequence_keys([(0,[sign*1.08,.06,2.25 if side=='Left' else -2.4]),(.35,[sign*1.0,.90,-3.0]),(.55,[sign*1.05,1.0,-2.9]),(1,[sign*1.05,.15,1.6 if side=='Left' else -1.4])],u)
            feet[side]=dict(toe=point(*toe),pitch=float(sequence_keys([(0,0 if side=='Left' else -48),(.25,-55),(.6,-35),(1,-10)],u)),yaw=sign*7,stance=False)
        wrists=sequence_keys([(0,[2.65,4.65,-1.8]),(.10,[3.8,5.3,1.5]),(.22,[1.35,6.9,6.2]),(.5,[1.35,6.95,6.35]),(.78,[1.2,4.1,5.5]),(1,[1.25,2.4,4.8])],u)
        curl=float(sequence_keys([(0,.12),(.22,.04),(.55,.16),(1,.60)],u)); spread=.35*(1-u)+.08
    else:
        height,f,lean,wind=sequence_keys([(0,[3.2,.25,72,0]),(.23,[2.60,.45,72,-3]),(.57,[3.55,.0,44,-2]),(1,[4.0,-.44,32,0])],u)
        feet={'Left':dict(toe=point(-1.05,.035,1.6),pitch=-10,yaw=-7,stance=True),
              'Right':dict(toe=point(1.05,.035,-1.4),pitch=-10,yaw=7,stance=True)}
        wrists=None; curl=.55*(1-u)+.15; spread=.1
    pose={}
    torso(pose,0,float(lean),0,0,0,float(height),float(f),float(wind))
    # Larger lunge head lift follows the arch while the face stays target-facing.
    RIG.set_root_rotation(pose,'Head',rotation(-6,0,5)@RIG.rest_world['Head'][:3,:3])
    H=RIG.fk(pose)['Hips'][:3,3].copy(); H[1]-=reach_adjustment(pose,feet)+.015
    RIG.set_root_position(pose,'Hips',H)
    for side,ft in feet.items():
        bend=0 if name=='Lunge_Flight' else max(0,-ft['pitch'])
        RIG.solve_leg_toe(side,pose,ft['toe'],ft['pitch'],ft['yaw'],point(-1.3 if side=='Left' else 1.3,2.0,5),toe_bend_deg=bend,clamp=False)
    for side in ['Left','Right']:
        sign=-1 if side=='Left' else 1
        if wrists is not None:
            target=point(-.0937+sign*wrists[0],wrists[1]+(.20 if side=='Right' and name=='Lunge_Flight' else 0),wrists[2]+(.25 if side=='Right' and name=='Lunge_Flight' else 0))
            if name=='Lunge_Flight':
                # Sweep under the shoulder on a constant-radius arc. A linear throw
                # crossed the elbow pole and produced a visible IK snap.
                S=RIG.fk(pose)[side+'Arm'][:3,3]
                theta,radius,lateral=sequence_keys([(0,[-65,3.40,1.0]),(.35,[94,3.72,-.48]),(.5,[96,3.70,-.48]),(.78,[55,3.65,-.60]),(1,[36,3.72,-.58])],u)
                target=S+np.array([sign*lateral,-radius*math.cos(deg(theta)),-radius*math.sin(deg(theta))])
                if side=='Right': target+=np.array([0,.16,-.20])*smooth(u/.35)
        elif side=='Left':
            target=point(*sequence_keys([(0,[-1.35,2.4,4.8]),(.23,[-1.6,.50,4.3]),(.57,[-1.65,3.3,3.4]),(1,[-1.8,6.8,4.4])],u))
        else:
            target=point(*sequence_keys([(0,[1.35,2.6,5.05]),(.23,[-.4,3.2,3.0]),(.57,[1.7,4.7,2.7]),(1,[1.3,7.3,5.4])],u))
        safe_wrist(pose,side,target, [sign*.4,-3,1] if name=='Lunge_Land' and side=='Right' else None)
        direction=np.array([sign*.08,-.25 if name=='Lunge_Flight' else -.7,-1])
        palm=np.array([-sign,0,-.15])
        handcurl=float(curl); handspread=float(spread)
        catch=0.0
        if name=='Lunge_Flight' and side=='Left':
            # Prepare the supporting palm during descent instead of snapping it at impact.
            catch=.5*float(smooth((u-.75)/.25))
        if name=='Lunge_Land' and side=='Left':
            catch=float(sequence_keys([(0,.5),(.18,1),(.40,1),(.70,0)],u))
        if catch>0:
            handcurl=float(mix(handcurl,.05,catch)); handspread=float(mix(handspread,.35,catch))
        RIG.orient_hand(pose,side,direction,palm)
        if catch>0:
            A=RIG.fk(pose)[side+'Hand'][:3,:3]
            RIG.orient_hand(pose,side,[0,.30,-1],[0,-1,0])
            B=RIG.fk(pose)[side+'Hand'][:3,:3]
            RIG.set_root_rotation(pose,side+'Hand',quat_to_mat(slerp(mat_to_quat(A),mat_to_quat(B),catch)))
        RIG.curl_fingers(pose,side,handcurl,handspread)
    if name=='Lunge_Land':
        # Last 0.10s settles exactly to the Run contact, including fingers and gaze.
        t=float(smooth((u-.70)/.30))
        if t>0: pose=blend_pose(pose,run_zero,t)
        # Blend poses can sink a toe; re-solve the same toe tracks towards Run's contact positions.
        if t>0:
            W=RIG.fk(run_zero)
            for side,ft in feet.items():
                toe=mix(ft['toe'],W[side+'ToeBase'][:3,3],t)
                toe[1]+=.24*math.sin(math.pi*t)**2
                ft['stance']=False
                ft['toe']=toe
                current=RIG.fk(pose)[side+'Foot'][:3,:3]
                ankle=toe-current@RIG.rest[side+'ToeBase'][:3,3]
                RIG.solve_chain(pose,side+'UpLeg',side+'Leg',side+'Foot',ankle,point(-1.3 if side=='Left' else 1.3,2,5),clamp=False)
                RIG.set_root_rotation(pose,side+'Foot',current)
    return pose,feet

def blend_pose(a,b,t):
    result={}
    for name in set(a)|set(b):
        A=a.get(name,np.eye(4)); B=b.get(name,np.eye(4))
        qa=mat_to_quat(A[:3,:3]); qb=mat_to_quat(B[:3,:3])
        Q=slerp(qa,qb,t)
        T=np.eye(4); T[:3,:3]=quat_to_mat(Q); T[:3,3]=mix(A[:3,3],B[:3,3],t)
        result[name]=T
    return result

def build_lunge(name,run_zero):
    seconds={'Lunge_Windup':.32,'Lunge_Flight':.428,'Lunge_Land':.35}[name]
    N={'Lunge_Windup':33,'Lunge_Flight':85,'Lunge_Land':43}[name]
    poses=[]; feet=[]
    for i in range(N):
        pose,ft=lunge_pose(name,i/(N-1),run_zero)
        poses.append(pose); feet.append(ft)
    return dict(poses=poses,feet=feet,frames=N,fps=N/seconds,seconds=seconds,loop=False,stride=0,speed=0,contacts=[],
                notes={'Lunge_Windup':'Stopped brace to asymmetric coil; planted toes, hold endpoint.',
                'Lunge_Flight':'Body-relative .428s arc; claw reach completes by u=.35 (.150s) and holds through apex; root carries ballistic motion.',
                'Lunge_Land':'Stationary hand catch and hip absorb; finishes exactly at Run phase zero.'}[name])

def export_clip(clip):
    # Neutral scapula tracks prevent the old server gait from changing our arm IK basis.
    names=[n for n in RIG.order if n!='Root']
    bones={}; previous={}; keyframes=[]
    float_quats={}
    for n in names:
        values=[]; qs=[]
        for pose in clip['poses']:
            q=np.array(mat_to_quat(pose.get(n,np.eye(4))[:3,:3])); q/=np.linalg.norm(q)
            if n in previous and np.dot(q,previous[n])<0: q=-q
            previous[n]=q; qs.append(q); values.extend(int(round(float(v)*10000)) for v in q)
        bones[n]=values; float_quats[n]=qs
    hips=[]
    for i,pose in enumerate(clip['poses']):
        h=pose.get('Hips',np.eye(4))[:3,3]; hips.extend(int(round(float(v)*1000)) for v in h)
        rows=[]
        for n in names:
            xyz=pose.get(n,np.eye(4))[:3,3]; q=float_quats[n][i]
            rows.append([n,*map(float,xyz),*map(float,q)])
        time=i/clip['fps'] if clip['loop'] else i/(clip['frames']-1)*clip['seconds']
        keyframes.append([time,rows])
    data={k:clip[k] for k in ['frames','fps','loop','stride','speed','contacts']}
    data['bones']=bones; data['hips']=hips
    return data,keyframes,float_quats

def decode_export(data):
    poses=[]
    for i in range(data['frames']):
        pose={}
        for n,qs in data['bones'].items():
            q=np.array(qs[4*i:4*i+4],float); q/=np.linalg.norm(q)
            T=np.eye(4); T[:3,:3]=quat_to_mat(q); pose[n]=T
        if 'Hips' in pose: pose['Hips'][:3,3]=np.array(data['hips'][3*i:3*i+3])/1000
        poses.append(pose)
    return poses

def qa_clip(name,clip,data,float_q):
    # QA the quantized payload the player will decode, not just perfect pre-export targets.
    poses=decode_export(data); worlds=[RIG.fk(p) for p in poses]
    N=len(poses); dt=clip['seconds']/N if clip['loop'] else clip['seconds']/(N-1)
    max_slide=0.; min_foot=100.; max_leg=0.; max_arm=0.; max_rotation=0.; frame_changes=[]; worst=('',0)
    for i,W in enumerate(worlds):
        for side in ['Left','Right']:
            max_leg=max(max_leg,float(np.linalg.norm(W[side+'Foot'][:3,3]-W[side+'UpLeg'][:3,3])))
            max_arm=max(max_arm,float(np.linalg.norm(W[side+'Hand'][:3,3]-W[side+'Arm'][:3,3])))
            min_foot=min(min_foot,float(W[side+'ToeBase'][1,3]+FLOOR_UP),float(W[side+'Foot'][1,3]+FLOOR_UP))
            j=(i+1)%N
            if j==0 and not clip['loop']: continue
            if clip['feet'][i][side]['stance'] and clip['feet'][j][side]['stance']:
                step=worlds[j][side+'ToeBase'][:3,3]-W[side+'ToeBase'][:3,3]
                step[2]-=clip['speed']*dt
                max_slide=max(max_slide,float(np.linalg.norm(step)))
        j=(i+1)%N
        if j==0 and not clip['loop']: continue
        deltas=[]
        for n in data['bones']:
            qa=np.array(mat_to_quat(poses[i][n][:3,:3])); qb=np.array(mat_to_quat(poses[j][n][:3,:3]))
            angle=2*math.acos(min(1,abs(float(np.dot(qa,qb)))))
            if math.degrees(angle)>max_rotation: worst=(n,i)
            max_rotation=max(max_rotation,math.degrees(angle)); deltas.append(angle**2)
        hip_delta=float(np.linalg.norm(poses[j]['Hips'][:3,3]-poses[i]['Hips'][:3,3]))
        frame_changes.append(math.sqrt(sum(deltas)/len(deltas))+hip_delta)
    ratio=frame_changes[-1]/(sum(frame_changes[:-1])/len(frame_changes[:-1])) if clip['loop'] else 0
    max_q_error=0.; min_dot=1.
    for n,flat in data['bones'].items():
        qs=np.array(flat,float).reshape(-1,4)/10000
        max_q_error=max(max_q_error,float(np.max(np.abs(np.linalg.norm(qs,axis=1)-1))))
        min_dot=min(min_dot,float(np.min(np.sum(qs[:-1]*qs[1:],axis=1))))
        if clip['loop']: min_dot=min(min_dot,float(np.dot(qs[-1],qs[0])))
    mean_hips=np.mean([W['Hips'][:3,3]-RIG.rest_world['Hips'][:3,3] for W in worlds],axis=0)
    mean_horizontal=max(abs(float(mean_hips[0])),abs(float(mean_hips[2])))
    report=dict(frames=N,fps=clip['fps'],seconds=clip['seconds'],stride=clip['stride'],authored_speed=clip['speed'],
                max_stance_slide_per_frame=max_slide,loop_ratio=ratio,max_leg_reach=max_leg,max_arm_reach=max_arm,
                min_foot_height=min_foot,max_joint_rotation_degrees=max_rotation,fastest_joint=list(worst),
                max_encoded_quaternion_norm_error=max_q_error,min_quaternion_adjacent_dot=min_dot,
                max_mean_horizontal_hips_offset=mean_horizontal if clip['loop'] else None,
                notes=clip['notes'])
    checks=dict(rest_fk=RIG.verify_rest()['max_position_studs']<=.001,
                leg_reach=max_leg<=3.86,arm_reach=max_arm<=4.10,stance_slide=max_slide<.05,
                floor=min_foot>=-.02,loop=not clip['loop'] or ratio<1.5,
                joint_flips=max_rotation<35,quaternion_normalized=max_q_error<.0001,quaternion_sign_continuous=min_dot>=0,
                loop_zero_mean=not clip['loop'] or mean_horizontal<.001)
    report['asserts']=checks; report['passed']=all(checks.values())
    return report

def main():
    global RIG,FLOOR_UP
    parser=argparse.ArgumentParser(); parser.add_argument('--only'); parser.add_argument('--no-render',action='store_true')
    parser.add_argument('--qa-only',action='store_true')
    parser.add_argument('--floor-up',type=float,default=FLOOR_UP)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    FLOOR_UP=args.floor_up; RIG=Rig(ROOT/'input/rig.json')
    rest=RIG.verify_rest(); print('REST',rest,flush=True)
    names=list(GAITS)+['Lunge_Windup','Lunge_Flight','Lunge_Land']
    if args.only and args.only not in names: parser.error('Unknown clip')
    clips={n:build_gait(n) for n in GAITS}
    run_zero=clips['Run']['poses'][0]
    clips.update({n:build_lunge(n,run_zero) for n in names[3:]})
    out=ROOT/'out'; (out/'keyframes_v4').mkdir(parents=True,exist_ok=True)
    # --only replaces that entry; .blend is always rebuilt with all six Actions.
    selected=[args.only] if args.only else names
    data=json.loads((out/'clips.json').read_text()) if args.only and (out/'clips.json').exists() else {}
    qa=json.loads((out/'qa.json').read_text()) if args.only and (out/'qa.json').exists() else {}
    for name in names:
        payload,keys,qs=export_clip(clips[name]); report=qa_clip(name,clips[name],payload,qs)
        print('FASTEST',name,report['fastest_joint'],round(report['max_joint_rotation_degrees'],1))
        print(f"{name:15} {report['frames']:3} {report['max_leg_reach']:.4f} leg {report['max_arm_reach']:.4f} arm {report['max_stance_slide_per_frame']:.5f} slide {report['loop_ratio']:.3f} loop {report['max_joint_rotation_degrees']:.2f} deg {report['passed']}",flush=True)
        if name in selected:
            data[name]=payload; qa[name]=report
            publish=dict(name=name,looped=clips[name]['loop'],priority='Movement' if clips[name]['loop'] else 'Action4',
                         retarget='Studio-rest-direct-ENTITY_MOTION_20261010',duration=clips[name]['seconds'],frames=keys)
            (out/'keyframes_v4'/f'{name}.json').write_text(json.dumps(publish,separators=(',',':')))
    (out/'clips.json').write_text(json.dumps(data,separators=(',',':')))
    qa['_build']=dict(floor_up=FLOOR_UP,rest=rest,loop_metric='RMS local joint angle + Hips translation; wrap / mean interior transition',
        quantization='xyzw x10000 integers re-normalized on decode; Hips local xyz x1000',flight_floor='Conservative launch-height root; positive root flight height only adds floor clearance',
        floor_points='ToeBase joint and ankle joint; sole mesh contact needs Studio validation')
    (out/'qa.json').write_text(json.dumps(qa,indent=2))
    failures={n:[k for k,v in qa[n]['asserts'].items() if not v] for n in selected if not qa[n]['passed']}
    if failures: raise AssertionError(json.dumps(failures))
    if args.qa_only: return
    from preview import build_preview
    for name,c in clips.items(): c['poses']=decode_export(export_clip(c)[0])
    build_preview(RIG,clips,out,FLOOR_UP,ROOT/'input/entity_watch_v1.fbx',render=not args.no_render,only=args.only)
    print('BUILD COMPLETE',flush=True)

if __name__=='__main__': main()
