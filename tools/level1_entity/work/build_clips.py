"""ENTITY_MOTION_20261010. Author on the measured Studio rig; Blender is only the preview/bake host.

Run Blender -b --python work/build_clips.py -- [--only=Walk] [--no-render] [--floor-up=8]
FLOOR_UP is also an environment override. No assets are downloaded or published.
"""
import sys, os, json, math, argparse, hashlib
sys.dont_write_bytecode = True
from pathlib import Path
import numpy as np

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
from rig_math import Rig, rot_x, rot_y, rot_z, mat_to_quat, quat_to_mat, slerp, basis_mapping, unit

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
    # RUN_FRONT_20261010: the charge above was built for a side view. The hunted player sees it head on, as a black
    # shape: its lean and stride lay along the line of sight, its arms (kept wide of the face) barely rose or fell,
    # and its feet tracked 2.4 studs apart, so in the game it was an upright waddle with hanging arms. This one is
    # built for the front silhouette: low and far forward with the head thrust out, a narrow track, a hard drop and
    # rise, shoulders rolling and swaying, and arms that pump from the hip to the shoulder at the sides.
    # RUN_HUNT_20261011 (owner, after filming it in the live game: "Du skal seriøst fikse entity run/chase
    # animation"). Frame by frame the RUN_FRONT charge read, head on, as a gorilla's waddle: the arms flew out to the
    # sides (the back hand 1.9 studs wide of the shoulder), the feet tracked 1.8 apart and the body rocked ten
    # degrees from side to side. This one comes AT the player: a narrow track, the body lower and further over its
    # feet with the head down between the shoulders, hardly any side-rock, a harder rise and fall, and arms that
    # reach forward at the prey one after the other, close to the body, instead of out to the sides.
    'Run':dict(seconds=.70,frames=70,speed=27.2,duty=.30,front=2.90,width=.58,clear=1.85,
               height=3.62,bob=.66,lean=43,yaw=15,list=4.0,sway=.16,heel=72),
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

def run_arm(S,side,p):
    """The charge's wrist target, finger direction and curl for one arm at gait phase p (S = that shoulder)."""
    sign=-1 if side=='Left' else 1
    phase=p+(0 if side=='Left' else .5)
    # Each arm works against its own leg; the claws open at the front of the reach.
    fwd=-math.cos(TAU*(phase+.03))
    a=float(smooth(.5+.5*fwd))
    amp=1.08 if side=='Right' else .96
    # RUN_HUNT_20261011: arms flung out to the sides read as flapping, and a hand reaching forward at shoulder
    # height read, from the player's low eye, as an arm waved over the head. Both hands stay IN FRONT of the body
    # and below the shoulders, a little wide of the chest so they show beside it: each in turn stretches out at
    # the prey with the claws open, then is drawn back, cocked, beside the ribs. It runs to grab, it does not pump.
    front=np.array([sign*1.05,-.55,-3.25*amp]); back=np.array([sign*1.25,-1.90,-1.55*amp])
    target=S+mix(back,front,a)+np.array([0,-.50*(1-fwd*fwd),0])
    direction=mix(np.array([sign*.10,-.55,-.83]),np.array([sign*.12,-.10,-.99]),a)       # fingers at the prey throughout
    return target,direction/np.linalg.norm(direction),.46-.28*a

def arms_gait(pose,p,name):
    for side in ['Left','Right']:
        sign=-1 if side=='Left' else 1
        phase=p+(0 if side=='Left' else .5)
        S=RIG.fk(pose)[side+'Arm'][:3,3]
        if name=='Run':
            target,direction,curl=run_arm(S,side,p)
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
              head=(-38,-40,3) if name=='Run' else None)
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

# LUNGE_GATHER_20261011 (owner's film of a chase: just before it sprang, the Entity stood up straight with its arms
# down and stopped coming for half a second). The wind-up was a planted brace that began upright, and the server froze
# the body for it. It is now the LAST STRIDE OF THE CHARGE, at the charge's speed: the leading foot lands, the body
# sinks low over it and both arms swing down and back, and it leaves the ground from that foot's push-off. The server
# keeps the Entity running through it (EntityAI, LUNGE_GATHER_20261011), so the feet track the floor.
WINDUP_P0, WINDUP_SPAN = .84, .46          # gait phases covered: .46 of a .70 s cycle = .322 s
WIND_END = (3.22, -.35, 50.0, 8.0)          # hip height, hip forward, lean, wind at push-off = the flight's first key

def gather_gait(s):
    # as the body sinks the swinging foot is carried lower: a high knee under a low hip whips the thigh round
    return dict(GAITS['Run'],clear=GAITS['Run']['clear']*(1-.60*s))

def windup_end_feet():
    return {side:foot_path((WINDUP_P0+WINDUP_SPAN)%1,gather_gait(1.0),side) for side in ['Left','Right']}

def windup_pose(u):
    g=GAITS['Run']; p=WINDUP_P0+WINDUP_SPAN*u
    s=float(smooth((u-.10)/.90)); k=1-s
    bob=-g['bob']*math.cos(2*TAU*(p-.09))
    lean_run=max(0,g['lean']-13.3)/.84+2*math.sin(2*TAU*(p-.07))
    height=float(mix(g['height']+bob,WIND_END[0],s)); forward=float(mix(-.44,WIND_END[1],s))
    lean=float(mix(lean_run,WIND_END[2],s)); wind=float(mix(-4,WIND_END[3],s))
    pose={}
    torso(pose,p,lean,g['yaw']*k,g['list']*k,g['sway']*k,height,forward,wind)
    # the head stays on the prey through the stride and settles into the flight's
    sn=math.sin(TAU*p); nod=2.5*math.cos(2*TAU*(p-.10))*k
    RIG.set_root_rotation(pose,'neck',rotation(float(mix(-38+nod*.5,-7,s)),wind*.12,0)@RIG.rest_world['neck'][:3,:3])
    RIG.set_root_rotation(pose,'Head',rotation(float(mix(-40+nod,-6,s)),2.5*sn*k,float(mix(3,5,s)))@RIG.rest_world['Head'][:3,:3])
    feet={side:foot_path(p%1,gather_gait(s),side) for side in ['Left','Right']}
    H=RIG.fk(pose)['Hips'][:3,3].copy(); H[1]-=reach_adjustment(pose,feet)+.015
    RIG.set_root_position(pose,'Hips',H)
    for side,ft in feet.items():
        sign=-1 if side=='Left' else 1
        bend=max(0,-ft['pitch'])*(1-float(smooth((ft['toe'][1]+FLOOR_UP-.035)/.9)))
        RIG.solve_leg_toe(side,pose,ft['toe'],ft['pitch'],ft['yaw'],point(-.0937*k+sign*1.3,2.0,5.0),toe_bend_deg=bend,clamp=False)
    a=float(smooth((u-.05)/.80))                     # the sweep: down past the hip and back, on an arc under the shoulder
    for side in ['Left','Right']:
        sign=-1 if side=='Left' else 1
        S=RIG.fk(pose)[side+'Arm'][:3,3]
        target,direction,curl=run_arm(S,side,p)
        v=target-S
        theta=float(mix(math.degrees(math.atan2(-v[2],-v[1])),-65,a)); radius=float(mix(math.hypot(v[1],v[2]),3.40,a))
        lateral=float(mix(sign*v[0],1.0,a))
        target=S+np.array([sign*lateral,-radius*math.cos(deg(theta)),-radius*math.sin(deg(theta))])
        direction=mix(direction,np.array([sign*.08,-.25,-1]),a)
        safe_wrist(pose,side,target)
        RIG.orient_hand(pose,side,direction/np.linalg.norm(direction),mix(np.array([-sign,0,-.2]),np.array([-sign,0,-.15]),a))
        RIG.curl_fingers(pose,side,float(mix(curl,.12,a)),float(mix(.24,.43,a)))
    return pose,feet

def lunge_pose(name,u,run_zero):
    if name=='Lunge_Windup':
        height,f,lean,wind=sequence_keys([(0,[4.08,-.44,15,0]),(.31,[3.90,-.75,28,5]),(1,[3.02,-1.1,49,12])],u)
        left=point(-1.1,.035,2.25); right=point(1.05,.035,-2.4)
        feet={'Left':dict(toe=left,pitch=0,yaw=-9,stance=True),'Right':dict(toe=right,pitch=-48,yaw=9,stance=True)}
        wrists=sequence_keys([(0,[2.4,4.4,-1.1]),(.31,[2.4,4.25,-1.6]),(1,[2.65,4.65,-1.8])],u)
        curl=.12; spread=.40
    elif name=='Lunge_Flight':
        height,f,lean,wind=sequence_keys([(0,list(WIND_END)),(.25,[4.10,.30,65,-8]),(.5,[4.08,.32,68,-8]),(.78,[3.70,.45,72,-4]),(1,[3.2,.25,72,0])],u)
        feet={}; start=windup_end_feet()
        for side in ['Left','Right']:
            sign=-1 if side=='Left' else 1
            first=start[side]['toe']
            # Let the heels trail below the hip rather than sweep through its IK pole.
            toe=sequence_keys([(0,[first[0],first[1]+FLOOR_UP,-first[2]]),(.35,[sign*1.0,.90,-3.0]),(.55,[sign*1.05,1.0,-2.9]),(1,[sign*1.05,.15,1.6 if side=='Left' else -1.4])],u)
            feet[side]=dict(toe=point(*toe),pitch=float(sequence_keys([(0,start[side]['pitch']),(.25,-55),(.6,-35),(1,-10)],u)),yaw=sign*7,stance=False,
                            bend0=max(0,-start[side]['pitch'])*(1-float(smooth((first[1]+FLOOR_UP-.035)/.9))))
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
        # the pushing foot's toe unbends as it leaves the floor (it was bent under the heel at the gather's end)
        bend=ft.get('bend0',0)*(1-float(smooth(u/.15))) if name=='Lunge_Flight' else max(0,-ft['pitch'])
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
    seconds={'Lunge_Windup':WINDUP_SPAN*GAITS['Run']['seconds'],'Lunge_Flight':.428,'Lunge_Land':.35}[name]
    N={'Lunge_Windup':33,'Lunge_Flight':85,'Lunge_Land':43}[name]
    poses=[]; feet=[]
    for i in range(N):
        pose,ft=windup_pose(i/(N-1)) if name=='Lunge_Windup' else lunge_pose(name,i/(N-1),run_zero)
        poses.append(pose); feet.append(ft)
    # the gather is run at the charge's speed: its stance foot is judged against a floor moving at that speed
    return dict(poses=poses,feet=feet,frames=N,fps=N/seconds,seconds=seconds,loop=False,stride=0,
                speed=GAITS['Run']['speed'] if name=='Lunge_Windup' else 0,contacts=[],
                notes={'Lunge_Windup':'The last stride of the charge at its speed: lands, sinks, arms swept back, ends at push-off.',
                'Lunge_Flight':'Body-relative .428s arc; claw reach completes by u=.35 (.150s) and holds through apex; root carries ballistic motion.',
                'Lunge_Land':'Stationary hand catch and hip absorb; finishes exactly at Run phase zero.'}[name])

# KILL_CHOKE_20261011. Mesh-space measurements are deliberately independent of Blender.
# The exported mesh has geometry/weights but no UVs or texture. These two measured
# visor-surface samples are eye-placement references, not a claim to recover texture pixels.
CHOKE_EYE_SAMPLES = np.array([[-.36827253,2.63174619,-.01394369],
                              [.34959571,2.63818334,.02056613]])
CHOKE_EYES = CHOKE_EYE_SAMPLES.mean(axis=0)
CHOKE_EYE_VERTEX_IDS = [5729,7487]
CHOKE_MARKS = dict(grab=.30,lifted=1.30,tilt=2.90,squeeze=3.40,dark=4.10,release=4.20)
CHOKE_SECONDS = 5.40

def real_body():
    mesh=json.loads((ROOT/'input/mesh.json').read_text())
    scale=float(mesh['head'].split()[3].split(',')[1])/float(mesh['head'].split()[1].split(',')[1])
    v=np.array(mesh['verts'],float).reshape(-1,11)
    ids=v[:,3:7].astype(int); weights=v[:,7:11]/1000
    weights[ids<0]=0; ids[ids<0]=0; weights/=np.maximum(weights.sum(1,keepdims=True),1e-9)
    binds=[]
    for c in mesh['bone_cframes']:
        m=np.eye(4);m[:3,3]=np.array(c[:3])*scale;m[:3,:3]=np.array(c[3:]).reshape(3,3)
        binds.append(np.linalg.inv(m))
    return dict(positions=np.c_[v[:,:3]*scale/10000,np.ones(len(v))],bones=ids,weights=weights,
                inverse_bind=np.array(binds),names=mesh['bones'],tris=np.array(mesh['tris']).reshape(-1,3),
                dominant=ids[np.arange(len(v)),weights.argmax(1)])

def skin_root(body,world):
    matrices=np.array([world[n]@body['inverse_bind'][i] for i,n in enumerate(body['names'])])
    return sum(np.einsum('nij,nj->ni',matrices[body['bones'][:,k]],body['positions'])[:,:3]*body['weights'][:,k:k+1]
               for k in range(4))

def choke_hand_rotation():
    # Fingers sweep across the front of the throat; palm faces inward from the right.
    a=RIG.hand_axes['Right']
    return rot_x(deg(20))@basis_mapping(a['finger'],a['palm'],[0,0,-1],[-1,0,0])

def choke_grip_local():
    # Measured centre of palm/knuckle cup: 1.55 beyond wrist, .43 into the curl.
    # On the skinned, curled hand Middle1/2/3 lie .326/.335/.322 studs
    # above the horizontal plane. With the final 20-degree rising palm, their
    # cup centre is .365 above the finger/palm plane. Including it seats the throat inside the
    # middle-finger cup rather than putting those fingers against the jaw.
    a=RIG.hand_axes['Right']
    return a['finger']*1.55+a['palm']*.43+choke_hand_rotation().T@np.array([0,.365,0])

def choke_points(world):
    hand=world['RightHand']; head=world['Head']
    return dict(grip=hand[:3,3]+hand[:3,:3]@choke_grip_local(),head=head[:3,3],
                eyes=head[:3,3]+head[:3,:3]@CHOKE_EYES)

def victim_eye(grip,head):
    away=np.asarray(grip)-np.asarray(head);away[1]=0;away=unit(away)
    return np.asarray(grip)+np.array([0,.5,0])+away*.25

def victim_basis(grip,head):
    forward=np.asarray(head)-np.asarray(grip);forward[1]=0;forward=unit(forward)
    right=unit(np.cross(forward,[0,1,0]))
    return np.column_stack([right,[0,1,0],-forward])

def victim_blocks():
    # Offsets relative to throat. Feet at -4.1; crown at +1.1 = 5.2 tall.
    return [('torso',[0,-1.05,0],[1.45,1.70,1.0]),('neck',[0,0,0],[.80,.30,.80]),
            ('head',[0,.55,0],[1.20,1.10,1.0]),
            ('armL',[-.925,-1.25,0],[.40,2.20,.80]),('armR',[.925,-1.25,0],[.40,2.20,.80]),
            ('legL',[-.39,-3.0,0],[.65,2.20,.90]),('legR',[.39,-3.0,0],[.65,2.20,.90])]

def build_choke(run,walk):
    N=162;times=np.linspace(0,CHOKE_SECONDS,N);poses=[];feet_all=[]
    # Exact Run phase .10 upper body, with a mesh-clear stopping plant below it.
    start=run['poses'][7];finish=blend_pose(walk['poses'][0],walk['poses'][0],0)
    endW=RIG.fk(finish);handR=endW['RightHand'][:3,:3].copy()
    RIG.solve_chain(finish,'RightArm','RightForeArm','RightHand',endW['RightHand'][:3,3]+[.35,0,-.50],
                    endW['RightForeArm'][:3,3],clamp=False)
    RIG.set_root_rotation(finish,'RightHand',handR)
    startW=RIG.fk(start);finishW=RIG.fk(finish)
    body=real_body();solemask=np.array(['Foot' in body['names'][d] or 'Toe' in body['names'][d] for d in body['dominant']])
    finalsole=skin_root(body,finishW)[solemask,1].min()+FLOOR_UP
    for t in times:
        lift=float(smooth((t-.30)/1.0));settle=float(smooth((t-4.20)/1.20))
        breath=.022*math.sin(TAU*(t-1.3)/2.1)*float(smooth((t-1.3)/.35))*(1-settle)
        # Tilt has only head/neck movement. Effort/breath resume after its stop.
        if 2.0<=t<=2.9: breath=0
        pitch=float(sequence_keys([(0,35),(.30,27),(1.30,17),(3.40,17),(4.10,23),(4.30,21),(5.20,13)],t))
        height=float(sequence_keys([(0,3.42),(.30,3.42),(1.30,4.08),(4.10,4.08),(4.30,4.04),(5.20,4.12)],t))+breath
        pose={};torso(pose,0,pitch,0,0,0,height,hip_forward=-.60+.25*lift,wind=-5*lift)
        # Counterbalance: pelvis under the load, ribs rotate back, right shoulder
        # drops under the weight and rolls forward. These are rotations, not arm stretch.
        for n,k in [('Spine02',.45),('Spine01',.30),('Spine',.25)]:
            W=RIG.fk(pose);RIG.set_root_rotation(pose,n,rotation(-5*lift*k,0,-3*lift*k)@W[n][:3,:3])
        W=RIG.fk(pose)
        RIG.set_root_rotation(pose,'RightShoulder',rotation(2*lift+breath*18,4*lift,-5*lift)@W['RightShoulder'][:3,:3])
        tilt=30*float(smooth((t-2.0)/.90))*(1-float(smooth((t-3.40)/.70)))
        W=RIG.fk(pose)
        RIG.set_root_rotation(pose,'neck',rotation(-25+10*float(smooth((t-3.4)/.7)),-5*lift, -tilt*.15)@RIG.rest_world['neck'][:3,:3])
        RIG.set_root_rotation(pose,'Head',rotation(-36+7*float(smooth((t-3.4)/.7)),2,tilt)@RIG.rest_world['Head'][:3,:3])
        # Fixed, wide, staggered soles from .65s until release. Opening/closing
        # phases are explicit steps and are excluded from planted-slide assertions.
        feet={}
        plant=float(smooth(t/.65))
        for side in ['Left','Right']:
            sign=-1 if side=='Left' else 1
            initial=startW[side+'ToeBase'][:3,3].copy();initial[1]=max(initial[1],-FLOOR_UP+.35)
            fixed=point(sign*1.22,.40,1.15 if side=='Left' else -.55)
            toe=mix(initial,fixed,plant)
            ft=dict(toe=toe,pitch=0,yaw=sign*8,stance=t>=.65 and t<=4.20)
            feet[side]=ft
        H=RIG.fk(pose)['Hips'][:3,3].copy();H[1]-=reach_adjustment(pose,feet)+.015;RIG.set_root_position(pose,'Hips',H)
        for side,ft in feet.items():
            RIG.solve_leg_toe(side,pose,ft['toe'],0,ft['yaw'],point(-1.3 if side=='Left' else 1.3,2,4),clamp=False)
        W=RIG.fk(pose)
        grip=sequence_keys([(0,choke_points(startW)['grip']),(.30,[0,-3.90,-3.70]),
                            (1.30,[0,.20,-5.55]),(3.40,[0,.20,-5.55]),
                            (4.10,[0,.40,-4.95]),(5.40,[0,.40,-4.95])],t)
        if t>1.3 and not 2<=t<=2.9 and t<4.1:
            grip+=np.array([.007*math.sin(TAU*t*6),breath*.4,.007*math.cos(TAU*t*7)])
        hr=rot_x(deg(-20*(1-lift)))@choke_hand_rotation()
        if t<.20:
            hr=quat_to_mat(slerp(mat_to_quat(startW['RightHand'][:3,:3]),mat_to_quat(hr),float(smooth(t/.20))))
        wrist=grip-hr@choke_grip_local()
        S=W['RightArm'][:3,3]
        RIG.solve_chain(pose,'RightArm','RightForeArm','RightHand',wrist,S+[1.2,-3.2,-.8],clamp=False)
        RIG.set_root_rotation(pose,'RightHand',hr)
        curl=float(sequence_keys([(0,.12),(.30,.58),(1.30,.61),(1.65,.65),(2.0,.65),(2.90,.65),(3.20,.70),(3.40,.70),(4.10,.82),(4.20,.08),(5.40,.23)],t))
        RIG.curl_fingers(pose,'Right',curl,.10)
        S=RIG.fk(pose)['LeftArm'][:3,3]
        safe_wrist(pose,'Left',S+np.array([-.22,-3.6,-.20]))
        RIG.orient_hand(pose,'Left',[-.06,-1,-.15],[1,0,0])
        RIG.curl_fingers(pose,'Left',.24+.045*math.sin(TAU*t/2.4) if not 2<=t<=2.9 else .20,.13)
        # .12s start blending conserves the run's pose while the catch arrives.
        if t<.20: pose=blend_pose(start,pose,float(smooth(t/.20)))
        if settle:
            pose=blend_pose(pose,finish,settle)
            # Walk@0 has a sole .894 under the floor on this exported body.
            # Preserve its upper body; settle to a floor-corrected lower-body
            # standing pose, recording the handoff discrepancy in QA/report.
            for side,ft in feet.items():
                toe=mix(ft['toe'],finishW[side+'ToeBase'][:3,3]+[0,-finalsole+.04,0],settle)
                current=RIG.fk(pose)[side+'Foot'][:3,:3]
                ankle=toe-current@RIG.rest[side+'ToeBase'][:3,3]
                RIG.solve_chain(pose,side+'UpLeg',side+'Leg',side+'Foot',ankle,point(-1.3 if side=='Left' else 1.3,2,5),clamp=False)
                RIG.set_root_rotation(pose,side+'Foot',current)
                ft['toe']=toe;ft['stance']=False
        # Mesh soles, not just pivots, must clear. Raise each requested toe by
        # its measured skin penetration while preserving the pelvis/upper body.
        for unused in range(2):
            W=RIG.fk(pose);verts=skin_root(body,W)
            for side in ['Left','Right']:
                mask=np.array([body['names'][d].startswith(side) and ('Foot' in body['names'][d] or 'Toe' in body['names'][d]) for d in body['dominant']])
                pen=max(0,.025-(verts[mask,1].min()+FLOOR_UP))
                if pen:
                    r=W[side+'Foot'][:3,:3];ankle=W[side+'Foot'][:3,3]+[0,pen,0]
                    RIG.solve_chain(pose,side+'UpLeg',side+'Leg',side+'Foot',ankle,point(-1.3 if side=='Left' else 1.3,2,5),clamp=False)
                    RIG.set_root_rotation(pose,side+'Foot',r)
        poses.append(pose);feet_all.append(feet)
    # Local quaternion blends follow curved wrist arcs. Equalize those arcs in
    # the unplanted catch and release intervals rather than speeding through
    # their middle. The pose endpoints and fixed-foot hold stay unchanged.
    for first,last in [(0,int(np.argmin(abs(times-.30)))),(int(np.searchsorted(times,4.20)),N-1)]:
        originals=poses[first:last+1];points=np.array([choke_points(RIG.fk(p))['grip'] for p in originals])
        arc=np.r_[0,np.cumsum(np.linalg.norm(np.diff(points,axis=0),axis=1))]
        for j,target in enumerate(np.linspace(0,arc[-1],len(originals))):
            k=min(len(originals)-2,max(0,int(np.searchsorted(arc,target)-1)))
            u=float((target-arc[k])/max(arc[k+1]-arc[k],1e-9))
            retimed=blend_pose(originals[k],originals[k+1],u)
            if first==0:
                # The stopping feet have their own .65s plant. Do not compress
                # their orientation changes to match the claw's faster arc.
                for side in ['Left','Right']:
                    for suffix in ['UpLeg','Leg','Foot','ToeBase']:
                        n=side+suffix
                        if n in originals[j]:retimed[n]=originals[j][n].copy()
            poses[first+j]=retimed
    return dict(poses=poses,feet=feet_all,frames=N,fps=30,seconds=CHOKE_SECONDS,loop=False,stride=0,speed=0,contacts=[],
                marks=CHOKE_MARKS,notes='One-arm throat cup, body rise/counterbalance, planted mesh soles; curious 30-degree roll; release after dark.')

# KILL_SLAM_20261011: independent offline authoring; existing Actions stay immutable.
SLAM_SECONDS=5.4
SLAM_TIMES=np.linspace(0,SLAM_SECONDS,162)
SLAM_MARKS={k:float(SLAM_TIMES[i]) for k,i in dict(grab=9,lifted=24,slam=32,windup=88,strike=93,release=104).items()}
SLAM_FIST_LOCAL=None
SLAM_FIST_VERTEX=None
SLAM_BODY=None

def slam_attitude(t):
    angle=float(sequence_keys([(0,0),(SLAM_MARKS['grab'],0),(SLAM_MARKS['lifted'],20),
                               (SLAM_MARKS['slam'],90),(SLAM_SECONDS,90)],t))
    r=rot_x(deg(-angle))
    return r@np.array([0,1,0]),r@np.array([0,0,1])

def slam_basis(up,front):
    return np.column_stack([unit(np.cross(up,front)),up,front])

def slam_fist_local():
    global SLAM_FIST_LOCAL,SLAM_FIST_VERTEX,SLAM_BODY
    if SLAM_FIST_LOCAL is None:
        pose={};RIG.curl_fingers(pose,'Left',1.0,.02)
        W=RIG.fk(pose);body=real_body();v=skin_root(body,W)
        hand=W['LeftHand'];local=(v-hand[:3,3])@hand[:3,:3]
        mask=np.array([body['names'][d].startswith('LeftHandMiddle') for d in body['dominant']])
        ids=np.where(mask)[0];a=RIG.hand_axes['Left']
        # Actual closed middle-knuckle skin vertex, leading along the finger axis.
        vid=int(ids[np.argmax(local[ids]@a['finger'])])
        SLAM_FIST_LOCAL=local[vid].copy();SLAM_FIST_VERTEX=vid;SLAM_BODY=body
        print('SLAM FIST skin vertex',vid,'local',SLAM_FIST_LOCAL.tolist(),flush=True)
    return SLAM_FIST_LOCAL

def slam_points(W):
    p=choke_points(W)
    slam_fist_local()
    p['fist']=skin_root(SLAM_BODY,W)[SLAM_FIST_VERTEX]
    return p

def build_slam(existing):
    choke_poses=decode_export(existing['Kill_Choke'])
    start={n:T.copy() for n,T in choke_poses[0].items()}
    finish=choke_poses[-1]
    startW=RIG.fk(start);finishW=RIG.fk(finish)
    marks=SLAM_MARKS;top=marks['lifted'];hit=marks['slam'];wind=marks['windup'];strike=marks['strike'];release=marks['release']
    body=real_body();poses=[];allfeet=[];errors=[]
    for t in SLAM_TIMES:
        pitch=float(sequence_keys([(0,35),(.30,27),(top,12),(hit,72),(hit+.07,76),(hit+.15,70),
                                  (1.55,74),(2.15,68),(wind,61),(strike,73),(release,70),(5.4,24)],t))
        height=float(sequence_keys([(0,3.42),(.30,3.42),(top,4.1),(hit,2.05),(hit+.07,1.96),(hit+.15,2.12),
                                   (1.55,1.9),(wind,2.18),(strike,2.05),(release,2.12),(5.4,4.12)],t))
        forward=float(sequence_keys([(0,-.60),(top,-.35),(hit,1.8),(wind,1.45),(strike,1.8),(release,1.8),(5.4,-.60)],t))
        pose={};torso(pose,0,pitch,0,0,0,height,hip_forward=forward)
        W=RIG.fk(pose)
        headpitch=float(sequence_keys([(0,-36),(top,-32),(hit,20),(1.75,28),(wind,-15),(strike,20),(release,25),(5.4,4)],t))
        RIG.set_root_rotation(pose,'neck',rotation(headpitch*.4)@RIG.rest_world['neck'][:3,:3])
        RIG.set_root_rotation(pose,'Head',rotation(headpitch)@RIG.rest_world['Head'][:3,:3])
        feet={}
        for side in ['Left','Right']:
            sign=-1 if side=='Left' else 1
            fixed=point(sign*1.85,.50,1.1 if side=='Left' else .3)
            toe=mix(startW[side+'ToeBase'][:3,3],fixed,float(smooth(t/.65)))
            if t>release:toe=mix(fixed,finishW[side+'ToeBase'][:3,3],float(smooth((t-release)/(5.4-release))))
            feet[side]=dict(toe=toe,pitch=0,yaw=(-1 if side=='Left' else 1)*8,stance=.65<=t<=release)
        H=RIG.fk(pose)['Hips'][:3,3].copy();H[1]-=reach_adjustment(pose,feet)+.015;RIG.set_root_position(pose,'Hips',H)
        for side,ft in feet.items():
            RIG.solve_leg_toe(side,pose,ft['toe'],0,(-1 if side=='Left' else 1)*8,
                              mix(startW[side+'Leg'][:3,3],point(-2.2 if side=='Left' else 2.2,1.3,3),float(smooth(t/.65))),clamp=True)
        grip=sequence_keys([(0,choke_points(startW)['grip']),(marks['grab'],[0,-3.9,-3.7]),
                            (top,[0,-.65,-5.1]),(top+(hit-top)*.5,[0,-4.05,-6.35]),(hit,[0,-7.45,-6.48]),
                            (hit+.067,[0,-7.23,-6.48]),(hit+.15,[0,-7.45,-6.48]),(release,[0,-7.45,-6.48])],t)
        up,front=slam_attitude(t)
        a=RIG.hand_axes['Right'];pin=basis_mapping(a['finger'],a['palm'],[-1,0,0],[0,-1,0])
        hr=quat_to_mat(slerp(mat_to_quat(choke_hand_rotation()),mat_to_quat(pin),float(smooth((t-top)/(hit-top)))))
        wrist=grip-hr@choke_grip_local();W=RIG.fk(pose);S=W['RightArm'][:3,3]
        # Load the planted pin almost straight (about 23 degrees elbow flex),
        # with the shoulder over the wrist. Pelvis height takes the constraint;
        # the victim's throat and both soles remain independently fixed.
        if t>top:
            horizontal=float(np.sum((S-wrist)[[0,2]]**2))
            loaded_reach=float(sequence_keys([(hit,4.06),(hit+.067,3.88),(hit+.15,4.06)],t))
            desired_y=wrist[1]+math.sqrt(max(0,loaded_reach**2-horizontal))
            rise=max(0,desired_y-S[1])*float(smooth((t-top)/(hit-top)))
            if t>release:rise*=1-float(smooth((t-release)/(5.4-release)))
            H=W['Hips'][:3,3]+[0,rise,0];RIG.set_root_position(pose,'Hips',H)
            for side,ft in feet.items():
                RIG.solve_leg_toe(side,pose,ft['toe'],0,(-1 if side=='Left' else 1)*8,point(-2.2 if side=='Left' else 2.2,1.3,3),clamp=True)
            W=RIG.fk(pose);S=W['RightArm'][:3,3]
        result=RIG.solve_chain(pose,'RightArm','RightForeArm','RightHand',wrist,S+[2.3,-1,0],clamp=True,reach_margin=.052)
        errors.append(float(np.linalg.norm(result.reached-wrist)) if any(abs(t-marks[k])<1e-7 for k in marks) else 0.)
        RIG.set_root_rotation(pose,'RightHand',hr)
        RIG.curl_fingers(pose,'Right',.65-.53*float(smooth((t-release)/.15)),.1)
        face=grip+.55*up+.35*front
        # Slowly cock the fist above the shoulder, stop, then drive in five samples.
        W=RIG.fk(pose);S=W['LeftArm'][:3,3]
        raised=np.array([-2.6,-.35,-6.8])
        fist=sequence_keys([(0,slam_points(startW)['fist']),(.65,[-2.8,-3.8,-2.8]),
                            (1.75,[-2.7,-4.4,-4.0]),(wind,raised),
                            (strike,face),(strike+.20,face),(release,face),(5.4,slam_points(finishW)['fist'])],t)
        # The closed knuckles face forward; the loaded arm drives them downward.
        a=RIG.hand_axes['Left'];load=float(smooth((t-1.75)/(wind-1.75)));down=float(smooth((t-wind)/(strike-wind)))
        lr=rot_x(deg(110*load*(1-down)))@basis_mapping(a['finger'],a['palm'],[0,-1,0],[0,0,-1])
        if wind<t<strike:fist=mix(raised,face,(t-wind)/(strike-wind))
        target=fist-lr@slam_fist_local()
        result=RIG.solve_chain(pose,'LeftArm','LeftForeArm','LeftHand',target,S+[-2,1,3.0],clamp=True,reach_margin=.052)
        errors.append(float(np.linalg.norm(result.reached-target)) if abs(t-wind)<1e-7 or abs(t-strike)<1e-7 else 0.)
        RIG.set_root_rotation(pose,'LeftHand',lr);RIG.curl_fingers(pose,'Left',.24+.76*load,.02)
        # Carry the passive left arm out of the known charge before cocking it.
        carry=choke_poses[min(24,int(np.argmin(abs(SLAM_TIMES-t))))]
        carryweight=1-float(smooth((t-top)/.55))
        for n in RIG.order:
            if n.startswith(('LeftArm','LeftForeArm','LeftHand')):
                blended=blend_pose({n:pose.get(n,np.eye(4))},{n:carry.get(n,np.eye(4))},carryweight)
                pose[n]=blended[n]
        if t<=marks['grab']:pose={n:T.copy() for n,T in choke_poses[int(np.argmin(abs(SLAM_TIMES-t)))].items()}
        elif t<marks['grab']+.12:pose=blend_pose(choke_poses[9],pose,float(smooth((t-marks['grab'])/.12)))
        if t>release:pose=blend_pose(pose,finish,float(smooth((t-release)/(5.4-release))))
        # Keep the soles from drifting in the pinned interval; choose one fixed
        # correction per boot rather than a frame-dependent floor correction.
        if poses and t<=1.8:
            # Bounded passive-arm turn resolves IK's equivalent elbow basis near
            # its singular entry; held/striking poses remain exact thereafter.
            for n in RIG.order:
                if n.startswith(('LeftArm','LeftForeArm','LeftHand')):
                    A=poses[-1].get(n,np.eye(4));B=pose.get(n,np.eye(4))
                    qa=mat_to_quat(A[:3,:3]);qb=mat_to_quat(B[:3,:3])
                    angle=2*math.acos(min(1,abs(float(np.dot(qa,qb)))))
                    if angle>deg(26):pose[n]=blend_pose({n:A},{n:B},deg(26)/angle)[n]
        poses.append(pose);allfeet.append(feet)
    # Solve the strike endpoints, then interpolate local joint rotations along
    # one continuous branch. Per-frame IK can switch its equivalent hinge basis
    # as this huge hand passes beside the shoulder.
    li=int(np.argmin(abs(SLAM_TIMES-top)));hi=int(np.argmin(abs(SLAM_TIMES-hit)))
    for i in range(li+1,hi):
        eased=blend_pose(poses[li],poses[hi],(i-li)/(hi-li))
        for n in RIG.order:
            if n.startswith(('RightArm','RightForeArm','RightHand')):poses[i][n]=eased[n]
    wi=int(np.argmin(abs(SLAM_TIMES-wind)));si=int(np.argmin(abs(SLAM_TIMES-strike)))
    for i in range(wi+1,si):
        eased=blend_pose(poses[wi],poses[si],(i-wi)/(si-wi))
        for n in RIG.order:
            if n.startswith(('LeftArm','LeftForeArm','LeftHand')):poses[i][n]=eased[n]
    # Throw the striking scapula forward at the start of the blow. This carries
    # the arm's weight and prevents the enormous closed hand from rising along
    # the quaternion arc after its highest, stopped windup pose.
    for i,load in zip(range(wi,si+1),[0,34,25,12,0,0]):
        W=RIG.fk(poses[i])
        RIG.set_root_rotation(poses[i],'LeftShoulder',rotation(load)@W['LeftShoulder'][:3,:3])
    for side in ['Left','Right']:
        mask=np.array([body['names'][d].startswith(side) and ('Foot' in body['names'][d] or 'Toe' in body['names'][d]) for d in body['dominant']])
        correction=max(0,.035-min(float(skin_root(body,RIG.fk(p))[mask,1].min()+FLOOR_UP) for p in poses))
        for i,pose in enumerate(poses):
            W=RIG.fk(pose);r=W[side+'Foot'][:3,:3];ankle=W[side+'Foot'][:3,3]+[0,correction,0]
            RIG.solve_chain(pose,side+'UpLeg',side+'Leg',side+'Foot',ankle,
                            mix(startW[side+'Leg'][:3,3],point(-2.2 if side=='Left' else 2.2,1.3,3),float(smooth(SLAM_TIMES[i]/.65))),clamp=True)
            RIG.set_root_rotation(pose,side+'Foot',r)
    # Recover toward the known floor-corrected choke exit, including its leg
    # branch. Re-solving its knee with the slam pole would swing the thigh into
    # the otherwise safe resting claw.
    ri=int(np.argmin(abs(SLAM_TIMES-release)))
    for i in range(ri+1,len(poses)):
        u=float(smooth((SLAM_TIMES[i]-release)/(5.4-release)))
        legs=blend_pose(poses[ri],finish,u)
        for n in RIG.order:
            if n.startswith(('LeftUpLeg','LeftLeg','LeftFoot','LeftToe','RightUpLeg','RightLeg','RightFoot','RightToe')):poses[i][n]=legs[n]
        W=RIG.fk(poses[i]);v=skin_root(body,W)
        for side in ['Left','Right']:
            mask=np.array([body['names'][d].startswith(side) and ('Foot' in body['names'][d] or 'Toe' in body['names'][d]) for d in body['dominant']])
            pen=max(0,.025-float(v[mask,1].min()+8))
            if pen:
                r=W[side+'Foot'][:3,:3]
                RIG.solve_chain(poses[i],side+'UpLeg',side+'Leg',side+'Foot',W[side+'Foot'][:3,3]+[0,pen,0],W[side+'Leg'][:3,3],clamp=True)
                RIG.set_root_rotation(poses[i],side+'Foot',r)
    poses[-1]={n:T.copy() for n,T in finish.items()}
    poses[0]={n:T.copy() for n,T in start.items()}
    return dict(poses=poses,feet=allfeet,frames=162,fps=30,seconds=5.4,loop=False,stride=0,speed=0,contacts=[],
                marks=marks,slam=True,reach_target_error=max(errors),notes='Heave, back slam, one damped rebound, planted throat pin, slow left-fist threat and trunk-driven hammer strike.')

def qa_slam(clip,data,worlds):
    tracks={k:np.array(v).reshape(-1,3)/1000 for k,v in data['tracks'].items()}
    m=data['marks'];ts=SLAM_TIMES;idx=lambda k:int(np.argmin(abs(ts-m[k])))
    up=tracks['vup'];front=tracks['vfront'];grip=tracks['grip'];centre=grip-1.1*up
    # Full envelope has throat-relative longitudinal limits -4.1 .. +1.1.
    half=np.array([1.1,2.6,.5]);body=real_body();dom=[body['names'][d] for d in body['dominant']];tris=body['tris']
    torso=np.array([n in ['Hips','Spine02','Spine01','Spine'] or 'Leg' in n or 'Foot' in n or 'Toe' in n for n in dom])
    safe=np.array([not ('Hand' in n or 'ForeArm' in n) for n in dom])
    nonstriking=np.array([not(n.startswith('LeftHand') or n=='LeftForeArm') for n in dom])
    nonstriking_tris=tris[np.all(nonstriking[tris],axis=1)]
    handmask=np.array([n.startswith('RightHand') for n in dom]);handtris=tris[np.all(handmask[tris],axis=1)]
    foot=np.array(['Foot' in n or 'Toe' in n for n in dom]);torso_tris=tris[np.any(torso[tris],axis=1)];safe_tris=tris[np.all(safe[tris],axis=1)]
    camera=100.;literal_camera=100.;sole=100.;knees=100.;handhits=0;pinbends=[];intersections=0;volume_frames=[];vf=100.;trackerr=0.
    for i,(t,W) in enumerate(zip(ts,worlds)):
        v=skin_root(body,W);handhits+=mesh_pair_intersections(v[handtris],v[torso_tris]);sole=min(sole,float(v[foot,1].min()+8));knees=min(knees,*[float(W[s+'Leg'][1,3]+8) for s in ['Left','Right']])
        if m['grab']<=t<=m['release']:
            basis=slam_basis(up[i],front[i]);local=(v-grip[i])@basis-[0,-1.5,0]
            hits=triangle_box_overlap(local[torso_tris],half);intersections+=hits
            if hits:volume_frames.append([i,hits])
            vf=min(vf,float(grip[i,1]-1.5*up[i,1]-np.dot(half,np.abs(basis[1]))+8))
        if m['slam']<=t<=m['release']:
            a=W['RightArm'][:3,3];e=W['RightForeArm'][:3,3];h=W['RightHand'][:3,3]
            pinbends.append((t,math.degrees(math.acos(float(np.clip(np.dot(unit(e-a),unit(h-e)),-1,1))))))
        if m['slam']<=t<=m['windup']:
            cam=grip[i]+.55*up[i]+.35*front[i];camera=min(camera,point_tri_distance(cam,v[safe_tris]));literal_camera=min(literal_camera,point_tri_distance(cam,v[nonstriking_tris]))
        exact=slam_points(W)
        trackerr=max(trackerr,max(float(np.max(abs(exact[k]-tracks[k][i]))) for k in exact))
    i=idx('lifted');basis=slam_basis(up[i],front[i]);clear=float(grip[i,1]-1.5*up[i,1]-np.dot(half,np.abs(basis[1]))+8)
    i=idx('windup');cam=grip[i]+.55*up[i]+.35*front[i]
    angle=math.degrees(math.acos(float(np.clip(np.dot(unit(tracks['eyes'][i]-cam),unit(tracks['fist'][i]-cam)),-1,1))))
    i=idx('strike');face=grip[i]+.55*up[i]+.35*front[i];miss=float(np.linalg.norm(tracks['fist'][i]-face))
    delta=np.linalg.norm(np.diff(grip,axis=0),axis=1);slam=(ts[1:]>m['lifted'])&(ts[1:]<=m['slam']+.16)
    held=(ts>=m['slam']+.2)&(ts<=m['release']);heights=centre[held,1]+8
    fistheight=float(tracks['fist'][idx('windup'),1]+8);fistabove=float(tracks['fist'][idx('windup'),1]-tracks['eyes'][idx('windup'),1])
    normerr=float(max(np.max(abs(np.linalg.norm(up,axis=1)-1)),np.max(abs(np.linalg.norm(front,axis=1)-1))))
    dot=float(np.max(abs(np.sum(up*front,axis=1))))
    steady_bends=[v for t,v in pinbends if t>=m['slam']+.2]
    impact_peak=max(v for t,v in pinbends if t<=m['slam']+.15)
    report=dict(marks=m,feet_clear_at_lifted=clear,heave_to_floor_seconds=m['slam']-m['lifted'],
                pinned_centre_min=float(heights.min()),pinned_centre_max=float(heights.max()),
                victim_vector_norm_error=normerr,victim_vector_dot=dot,max_grip_step_slam=float(delta[slam].max()),
                max_grip_step_elsewhere=float(delta[~slam].max()),windup_fist_floor_height=fistheight,
                windup_fist_above_eyes=fistabove,windup_eye_fist_angle_degrees=angle,
                windup_to_strike_seconds=m['strike']-m['windup'],strike_face_error=miss,
                min_camera_to_non_striking_mesh=literal_camera,min_camera_to_non_contact_mesh=camera,min_mesh_sole_height=sole,min_knee_height=knees,
                min_victim_volume_floor_height=vf,victim_body_intersecting_triangles=intersections,victim_intersection_frames=volume_frames,
                pin_elbow_min_degrees=min(steady_bends),pin_elbow_max_degrees=max(steady_bends),impact_elbow_peak_degrees=impact_peak,impact_elbow_compression_degrees=impact_peak-min(steady_bends),max_track_rounding_error=trackerr,max_required_mark_ik_error=clip['reach_target_error'],right_hand_body_triangle_pairs=handhits,
                fist_reference_left_hand_local=slam_fist_local().tolist(),fist_surface_vertex_index=SLAM_FIST_VERTEX,
                measurement_scope='Exported quantized FK; actual skinned mesh triangles; full victim OBB at every source frame. No runtime claim.')
    checks=dict(lifted_feet=clear>=2.5,heave_duration=m['slam']-m['lifted']<=.3,
                pinned_height=heights.min()>=.5 and heights.max()<=.6,vectors_unit=normerr<=.01,vectors_perpendicular=dot<=.01,
                slam_grip_step=delta[slam].max()<=1.6,other_grip_step=delta[~slam].max()<=.9,
                windup_highest=tracks['fist'][idx('windup'),1]>=float(tracks['fist'][idx('lifted'):idx('strike')+1,1].max())-.01,windup_height=fistheight>=7 or fistabove>=3,windup_visibility=angle<=32,
                strike_duration=m['strike']-m['windup']<=.2,strike_on_face=miss<=.5,camera_clearance=literal_camera>=1.2,camera_clearance_excluding_contact_arms=camera>=1.2,
                impact_arm_compression=impact_peak-min(steady_bends)>=10,pin_arm_nearly_straight=max(steady_bends)<=30,hand_mesh_body_clearance=handhits==0,mesh_floor=sole>=-.002,knee_floor=knees>=0,victim_floor=vf>=-.05,victim_body_clearance=intersections==0,
                quantized_fk_tracks=trackerr<=.000501,json_size=len(json.dumps(data,separators=(',',':')))<=185000)
    between=dict(samples=0,min_camera=100.,min_sole=100.,min_victim_floor=100.,victim_body_triangles=0,right_hand_body_pairs=0,max_grip_linear_to_fk_error=0.)
    decoded=decode_export(data)
    for i in range(len(decoded)-1):
        for u in [.25,.5,.75]:
            t=float(mix(ts[i],ts[i+1],u));W=RIG.fk(blend_pose(decoded[i],decoded[i+1],u));v=skin_root(body,W)
            between['samples']+=1
            between['min_sole']=min(between['min_sole'],float(v[foot,1].min()+8))
            between['right_hand_body_pairs']+=mesh_pair_intersections(v[handtris],v[torso_tris])
            if m['grab']<=t<=m['release']:
                g=mix(grip[i],grip[i+1],u);vu=unit(mix(up[i],up[i+1],u));ff=mix(front[i],front[i+1],u);ff=unit(ff-vu*np.dot(vu,ff));basis=slam_basis(vu,ff)
                between['min_victim_floor']=min(between['min_victim_floor'],float(g[1]-1.5*vu[1]-np.dot(half,np.abs(basis[1]))+8))
                between['victim_body_triangles']+=triangle_box_overlap(((v-g)@basis-[0,-1.5,0])[torso_tris],half)
                between['max_grip_linear_to_fk_error']=max(between['max_grip_linear_to_fk_error'],float(np.linalg.norm(g-choke_points(W)['grip'])))
                if m['slam']<=t<=m['windup']:between['min_camera']=min(between['min_camera'],point_tri_distance(g+.55*vu+.35*ff,v[safe_tris]))
    report['between_frames']=between
    report['farthest_neck_point_from_fixed_eye']=math.sqrt(.4**2+.7**2+.75**2)
    report['camera_scope']='Strict non-striking mesh includes the RIGHT gripping arm/hand; contact-arm exclusion is a separately named diagnostic.'
    if literal_camera<1.2:report['known_constraint']='Literal camera clearance fails at the right gripping claw; do not claim full brief compliance.'
    checks.update(interpolated_floor=between['min_sole']>=-.002,interpolated_victim_floor=between['min_victim_floor']>=-.05,
                  interpolated_victim_body=between['victim_body_triangles']==0,interpolated_hand_body=between['right_hand_body_pairs']==0,
                  interpolated_camera_excluding_contact_arms=between['min_camera']>=1.2)
    return report,checks

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
    if 'marks' in clip:
        data['seconds']=clip['seconds'];data['marks']=dict(clip['marks'])
        data['tracks']={n:[] for n in (['grip','head','eyes','fist','vup','vfront'] if clip.get('slam') else ['grip','head','eyes'])}
        for i,pose in enumerate(decode_export(data)):
            points=slam_points(RIG.fk(pose)) if clip.get('slam') else choke_points(RIG.fk(pose))
            if clip.get('slam'):points['vup'],points['vfront']=slam_attitude(SLAM_TIMES[i])
            for n,p in points.items():
                data['tracks'][n].extend(int(round(float(v)*1000)) for v in p)
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

def point_tri_distance(p,tris):
    a,b,c=tris[:,0],tris[:,1],tris[:,2]
    ab=b-a;ac=c-a;n=np.cross(ab,ac);norm=np.sum(n*n,axis=1)
    ap=p-a;distance=np.sum(ap*n,axis=1)/np.maximum(norm,1e-18)
    proj=p-distance[:,None]*n
    d00=np.sum(ab*ab,axis=1);d01=np.sum(ab*ac,axis=1);d11=np.sum(ac*ac,axis=1)
    pp=proj-a;d20=np.sum(pp*ab,axis=1);d21=np.sum(pp*ac,axis=1);den=d00*d11-d01*d01
    v=(d11*d20-d01*d21)/np.maximum(den,1e-18);w=(d00*d21-d01*d20)/np.maximum(den,1e-18)
    best=np.where((v>=0)&(w>=0)&(v+w<=1)&(norm>1e-18),distance*distance*norm,np.inf)
    for x,y in [(a,b),(b,c),(c,a)]:
        edge=y-x;u=np.clip(np.sum((p-x)*edge,axis=1)/np.maximum(np.sum(edge*edge,axis=1),1e-18),0,1)
        best=np.minimum(best,np.sum((p-x-u[:,None]*edge)**2,axis=1))
    return math.sqrt(float(best.min()))

def triangle_box_overlap(tris,half):
    # Triangle-vs-box SAT: 3 box axes, face normal, 9 edge cross axes.
    live=np.all(tris.min(1)<=half,axis=1)&np.all(tris.max(1)>=-half,axis=1)
    tris=tris[live]
    if len(tris)==0:return 0
    edges=[tris[:,1]-tris[:,0],tris[:,2]-tris[:,1],tris[:,0]-tris[:,2]]
    axes=[np.cross(edges[0],edges[1])]+[np.cross(e,np.eye(3)[j]) for e in edges for j in range(3)]
    ok=np.ones(len(tris),bool)
    for axis in axes:
        projections=np.einsum('nkj,nj->nk',tris,axis);radius=np.abs(axis)@half
        ok&=(projections.min(1)<=radius+1e-8)&(projections.max(1)>=-radius-1e-8)
    return int(ok.sum())

def triangle_pairs_overlap(a,b):
    # SAT for two triangles, including in-plane separating axes for coplanar pairs.
    ea=[a[:,1]-a[:,0],a[:,2]-a[:,1],a[:,0]-a[:,2]]
    eb=[b[:,1]-b[:,0],b[:,2]-b[:,1],b[:,0]-b[:,2]]
    na=np.cross(ea[0],ea[1]);nb=np.cross(eb[0],eb[1])
    axes=[na,nb]+[np.cross(x,y) for x in ea for y in eb]+[np.cross(na,x) for x in ea]+[np.cross(nb,x) for x in eb]
    live=np.ones(len(a),bool)
    for axis in axes:
        pa=np.einsum('nkj,nj->nk',a,axis);pb=np.einsum('nkj,nj->nk',b,axis)
        live&=(pa.min(1)<=pb.max(1)+1e-9)&(pb.min(1)<=pa.max(1)+1e-9)
    return int(live.sum())

def mesh_pair_intersections(a,b):
    # Broad phase is bounded: filter the body to the hand's overall AABB, then
    # pair only overlapping triangle AABBs in small batches.
    lo=a.min((0,1));hi=a.max((0,1));bl=b.min(1);bh=b.max(1)
    b=b[np.all(bh>=lo,axis=1)&np.all(bl<=hi,axis=1)]
    if not len(b):return 0
    bl=b.min(1);bh=b.max(1);count=0
    for start in range(0,len(a),128):
        aa=a[start:start+128];al=aa.min(1);ah=aa.max(1)
        pairs=np.all(ah[:,None,:]>=bl[None,:,:],axis=2)&np.all(al[:,None,:]<=bh[None,:,:],axis=2)
        ia,ib=np.where(pairs)
        if len(ia):count+=triangle_pairs_overlap(aa[ia],b[ib])
    return count

def grabbing_arm_max_ndc(vertices,cam,eyes):
    forward=unit(eyes-cam);right=unit(np.cross(forward,[0,1,0]));up=np.cross(right,forward)
    v=vertices-cam;z=v@forward;x=v@right;y=v@up;tan=math.tan(deg(35))
    inside=(z>.01)&(np.abs(x/np.maximum(z,.01))<tan)
    return float(np.max(y[inside]/(z[inside]*tan))) if inside.any() else -100.

def qa_choke_between_frames(data,body,foot_mask,safe_tris,torso_tris,hand_tris,grab_mask):
    poses=decode_export(data)
    result=dict(samples=0,min_mesh_sole_height=100.,min_camera_clearance=100.,hand_body_intersections=0,
                victim_envelope_intersections=0,min_victim_feet_height=100.,hold_eye_distance_min=100.,hold_eye_distance_max=0.,
                max_held_grip_interpolation_error=0.,max_grabbing_arm_vertical_ndc=-100.)
    tracks=np.array(data['tracks']['grip']).reshape(-1,3)/1000
    for i in range(len(poses)-1):
        for u in [.25,.5,.75]:
            W=RIG.fk(blend_pose(poses[i],poses[i+1],u));P=choke_points(W)
            t=(i+u)*data['seconds']/(data['frames']-1);v=skin_root(body,W);result['samples']+=1
            result['min_mesh_sole_height']=min(result['min_mesh_sole_height'],float(v[foot_mask,1].min()+FLOOR_UP))
            result['hand_body_intersections']+=mesh_pair_intersections(v[hand_tris],v[torso_tris])
            if data['marks']['grab']<=t<=data['marks']['release']:
                cam=victim_eye(P['grip'],P['head'])
                result['min_camera_clearance']=min(result['min_camera_clearance'],point_tri_distance(cam,v[safe_tris]))
                local=(v-P['grip'])@victim_basis(P['grip'],P['head'])-[0,-1.5,0]
                result['victim_envelope_intersections']+=triangle_box_overlap(local[torso_tris],np.array([1.1,2.6,.5]))
                error=float(np.linalg.norm(P['grip']-mix(tracks[i],tracks[i+1],u)))
                result['max_held_grip_interpolation_error']=max(result['max_held_grip_interpolation_error'],error)
                if t<=data['marks']['dark']:
                    result['max_grabbing_arm_vertical_ndc']=max(result['max_grabbing_arm_vertical_ndc'],
                        grabbing_arm_max_ndc(v[grab_mask],cam,P['eyes']))
            if data['marks']['lifted']<=t<=data['marks']['dark']:
                result['min_victim_feet_height']=min(result['min_victim_feet_height'],float(P['grip'][1]+FLOOR_UP-4.1))
            if data['marks']['lifted']<=t<=data['marks']['squeeze']:
                distance=float(np.linalg.norm(victim_eye(P['grip'],P['head'])-P['eyes']))
                result['hold_eye_distance_min']=min(result['hold_eye_distance_min'],distance)
                result['hold_eye_distance_max']=max(result['hold_eye_distance_max'],distance)
    checks=dict(interpolated_mesh_floor=result['min_mesh_sole_height']>=0,
                interpolated_camera=result['min_camera_clearance']>=1.2,
                interpolated_hand_body=result['hand_body_intersections']==0,
                interpolated_victim_body=result['victim_envelope_intersections']==0,
                interpolated_lift=result['min_victim_feet_height']>=1.5,
                interpolated_hold_distance=3<=result['hold_eye_distance_min']<=result['hold_eye_distance_max']<=4.5,
                held_grip_interpolation=result['max_held_grip_interpolation_error']<.05,
                interpolated_grab_arm_below_view=result['max_grabbing_arm_vertical_ndc']<=-1.)
    result['scope']='Three interior quaternion-interpolated samples per source interval; sampled evidence, not an analytic continuous collision proof.'
    return result,checks

def qa_choke(clip,data,worlds):
    body=real_body();names=body['names'];dom=np.array([names[x] for x in body['dominant']])
    safe=np.array([not (n.startswith('RightHand') or n=='RightForeArm') for n in dom])
    torso=np.array([n in ['Hips','Spine02','Spine01','Spine','LeftShoulder','LeftArm','LeftForeArm'] or
                    n.startswith(('LeftHand','LeftUpLeg','LeftLeg','LeftFoot','LeftToe','RightUpLeg','RightLeg','RightFoot','RightToe')) for n in dom])
    foot=np.array(['Foot' in n or 'Toe' in n for n in dom]);tris=body['tris']
    safe_tris=tris[np.all(safe[tris],axis=1)];torso_tris=tris[np.any(torso[tris],axis=1)]
    tracks={k:np.array(v).reshape(-1,3)/1000 for k,v in data['tracks'].items()}
    times=np.linspace(0,clip['seconds'],clip['frames']);marks=clip['marks']
    heights=[];dists=[];deltas=np.linalg.norm(np.diff(tracks['grip'],axis=0),axis=1)
    bends=[];rolls=[];mincamera=100;minsole=100;intersections=0;minvolume=100;maxtrack=0
    handbody=100;hand_mesh_intersections=0;hand_intersection_frames=[];max_grab_ndc=-100.
    handmask=np.array([n.startswith('RightHand') for n in dom])
    grabmask=~safe
    hand_tris=tris[np.all(handmask[tris],axis=1)]
    for i,(t,W) in enumerate(zip(times,worlds)):
        grip,head,eyes=[tracks[k][i] for k in ['grip','head','eyes']];cam=victim_eye(grip,head)
        exact=choke_points(W)
        maxtrack=max(maxtrack,max(float(np.max(np.abs(exact[k]-tracks[k][i]))) for k in tracks))
        v=skin_root(body,W);minsole=min(minsole,float(v[foot,1].min()+FLOOR_UP))
        hits=mesh_pair_intersections(v[hand_tris],v[torso_tris]);hand_mesh_intersections+=hits
        if hits:hand_intersection_frames.append([i,hits])
        A=W['RightArm'][:3,3];B=W['RightForeArm'][:3,3];C=W['RightHand'][:3,3]
        bends.append(math.degrees(math.acos(float(np.clip(np.dot(unit(B-A),unit(C-B)),-1,1)))))
        # Root Z roll of Head delta over its measured rest basis.
        delta=W['Head'][:3,:3]@np.linalg.inv(RIG.rest_world['Head'][:3,:3]);rolls.append(math.degrees(math.atan2(delta[1,0],delta[0,0])))
        if marks['grab']<=t<=marks['release']:
            mincamera=min(mincamera,point_tri_distance(cam,v[safe_tris]))
            if t<=marks['dark']:max_grab_ndc=max(max_grab_ndc,grabbing_arm_max_ndc(v[grabmask],cam,eyes))
            basis=victim_basis(grip,head);local=(v-grip)@basis
            # Full requested 2.2 x 5.2 x 1 envelope, not only the thinner blocks.
            centred=local-np.array([0,-1.5,0]);half=np.array([1.1,2.6,.5])
            intersections+=triangle_box_overlap(centred[torso_tris],half)
            signed=np.linalg.norm(np.maximum(np.abs(centred[torso])-half,0),axis=1)
            minvolume=min(minvolume,float(signed.min()))
            # Wrist, palm cup and every phalanx against torso/legs/left arm skin.
            for n in ['RightHand']+[n for n in RIG.order if n.startswith('RightHand') and n!='RightHand']:
                handbody=min(handbody,point_tri_distance(W[n][:3,3],v[torso_tris]))
        if marks['lifted']<=t<=marks['dark']:heights.append(grip[1]+FLOOR_UP)
        if marks['lifted']<=t<=marks['squeeze']:dists.append(float(np.linalg.norm(cam-eyes)))
    holdroll=rolls[np.argmin(abs(times-marks['tilt']))]
    grab_delta=float(deltas[times[1:]<=marks['grab']+.04].max())
    after_delta=float(deltas[times[1:]>marks['grab']+.04].max())
    report=dict(marks=marks,min_grip_height_lifted_to_dark=min(heights),min_victim_feet_clearance=min(heights)-4.1,
                hold_eye_distance_min=min(dists),hold_eye_distance_max=max(dists),tilt_end_head_roll_degrees=holdroll,
                max_grip_step_grab=grab_delta,max_grip_step_after_grab=after_delta,min_right_elbow_bend_degrees=min(bends),
                min_mesh_sole_height=minsole,min_camera_to_non_grab_mesh=mincamera,
                victim_envelope_intersecting_triangles=intersections,min_victim_envelope_to_skin_vertex=minvolume,
                min_hand_joint_to_body_surface=handbody,max_track_rounding_error=maxtrack,
                right_hand_body_intersecting_triangle_pairs=hand_mesh_intersections,
                right_hand_body_intersection_frames=hand_intersection_frames,
                max_grabbing_arm_vertical_ndc=max_grab_ndc,
                eye_reference_head_local=CHOKE_EYES.tolist(),grip_reference_hand_local=choke_grip_local().tolist(),
                eye_surface_vertex_indices=CHOKE_EYE_VERTEX_IDS,
                measurement_scope='Quantized FK, real linear-blend skin, triangle camera distance, triangle/OBB victim envelope and triangle/triangle hand/body SAT at all source frames.')
    checks=dict(victim_feet_lift=min(heights)>=5.6,hold_camera_distance=min(dists)>=3 and max(dists)<=4.5,
                head_tilt=25<=abs(holdroll)<=35,grab_grip_step=grab_delta<=.9,after_grab_grip_step=after_delta<=.25,
                bent_right_elbow=min(bends)>8,mesh_floor=minsole>=-.002,camera_clearance=mincamera>=1.2,
                victim_body_clearance=intersections==0,hand_body_joint_clearance=handbody>.05,
                hand_mesh_body_clearance=hand_mesh_intersections==0,
                grab_arm_below_view=max_grab_ndc<=-1.,
                quantized_fk_tracks=maxtrack<=.000501)
    between,between_checks=qa_choke_between_frames(data,body,foot,safe_tris,torso_tris,hand_tris,grabmask)
    report['between_frames']=between;checks.update(between_checks)
    return report,checks

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
    if name=='Kill_Choke':
        extra,extra_checks=qa_choke(clip,data,worlds);report.update(extra);checks.update(extra_checks)
    if name=='Kill_Slam':
        extra,extra_checks=qa_slam(clip,data,worlds);report.update(extra);checks.update(extra_checks)
    checks={k:bool(v) for k,v in checks.items()}
    report['asserts']=checks; report['passed']=all(checks.values())
    return report

def main():
    global RIG,FLOOR_UP
    parser=argparse.ArgumentParser(); parser.add_argument('--only'); parser.add_argument('--no-render',action='store_true')
    parser.add_argument('--qa-only',action='store_true')
    parser.add_argument('--blend-only',action='store_true',help='Kill_Slam: bake the already QA-verified payload without reauthoring')
    parser.add_argument('--kill-job',action='store_true',help='write only clips/QA and the dedicated real-mesh kill blend')
    parser.add_argument('--floor-up',type=float,default=FLOOR_UP)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    FLOOR_UP=args.floor_up; RIG=Rig(ROOT/'input/rig.json')
    rest=RIG.verify_rest(); print('REST',rest,flush=True)
    if args.blend_only and args.only!='Kill_Slam':parser.error('--blend-only requires --only Kill_Slam')
    if args.only=='Kill_Slam':
        return main_slam(args)
    old_names=list(GAITS)+['Lunge_Windup','Lunge_Flight','Lunge_Land'];names=old_names+['Kill_Choke']
    if args.only and args.only not in names: parser.error('Unknown clip')
    clips={n:build_gait(n) for n in GAITS}
    run_zero=clips['Run']['poses'][0]
    clips.update({n:build_lunge(n,run_zero) for n in old_names[3:]})
    clips['Kill_Choke']=build_choke(clips['Run'],clips['Walk'])
    out=ROOT/'out'
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
            if not args.qa_only and not args.kill_job:
                publish=dict(name=name,looped=clips[name]['loop'],priority='Movement' if clips[name]['loop'] else 'Action4',
                             retarget='Studio-rest-direct-ENTITY_MOTION_20261010',duration=clips[name]['seconds'],frames=keys)
                (out/'keyframes_v4').mkdir(exist_ok=True)
                (out/'keyframes_v4'/f'{name}.json').write_text(json.dumps(publish,separators=(',',':')))
    (out/'clips.json').write_text(json.dumps(data,separators=(',',':')))
    qa['_build']=dict(floor_up=FLOOR_UP,rest=rest,loop_metric='RMS local joint angle + Hips translation; wrap / mean interior transition',
        quantization='xyzw x10000 integers re-normalized on decode; Hips local xyz x1000',flight_floor='Conservative launch-height root; positive root flight height only adds floor clearance',
        floor_points='ToeBase joint and ankle joint; sole mesh contact needs Studio validation')
    (out/'qa.json').write_text(json.dumps(qa,indent=2))
    failures={n:[k for k,v in qa[n]['asserts'].items() if not v] for n in selected if not qa[n]['passed']}
    if failures: raise AssertionError(json.dumps(failures))
    if args.qa_only: return
    if not args.kill_job:
        from preview import build_preview
        for name,c in clips.items():c['poses']=decode_export(export_clip(c)[0])
        build_preview(RIG,clips,out,FLOOR_UP,ROOT/'input/entity_watch_v1.fbx',render=not args.no_render,only=args.only)
        print('BUILD COMPLETE',flush=True)
        return
    # Keep this scoped build inside the authorized outputs. The legacy preview
    # also writes work/preview_report.json and keyframes, which this job cannot.
    import bpy
    from preview import _make_armature,_key_actions
    for name,c in clips.items(): c['poses']=decode_export(export_clip(c)[0])
    bpy.ops.wm.read_factory_settings(use_empty=True)
    armature=_make_armature(RIG);parity=_key_actions(armature,RIG,clips)
    body=real_body();mesh=bpy.data.meshes.new('Real_Entity_Studio_Mesh')
    mesh.from_pydata(skin_root(body,RIG.rest_world).tolist(),[],body['tris'].tolist())
    obj=bpy.data.objects.new('Real_Entity',mesh);bpy.context.collection.objects.link(obj);obj.matrix_world=armature.matrix_world.copy()
    for j,n in enumerate(body['names']):
        group=obj.vertex_groups.new(name=n)
        for k in range(4):
            for i in np.where((body['bones'][:,k]==j)&(body['weights'][:,k]>0))[0]:
                group.add([int(i)],float(body['weights'][i,k]),'ADD')
    mod=obj.modifiers.new('Studio_exact_rig','ARMATURE');mod.object=armature
    armature.animation_data.action=bpy.data.actions['Kill_Choke']
    action=armature.animation_data.action
    for k,v in CHOKE_MARKS.items():action.pose_markers.new(k).frame=round(1+v*30)
    scene=bpy.context.scene;scene.render.fps=30;scene.frame_start=1;scene.frame_end=163;scene.frame_set(1)
    (out/'blend').mkdir(exist_ok=True);bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(out/'blend'/'kill_choke.blend'))
    print('BLENDER FK',parity,flush=True)
    print('BUILD COMPLETE',flush=True)

def main_slam(args):
    out=ROOT/'out';raw=(out/'clips.json').read_text();existing=json.loads(raw)
    if args.blend_only:
        payload=existing['Kill_Slam'];report=json.loads((out/'qa.json').read_text())['Kill_Slam']
        digest=hashlib.sha256(json.dumps(payload,separators=(',',':')).encode()).hexdigest()
        assert all(v for k,v in report['asserts'].items() if k!='camera_clearance') and report['payload_sha256']==digest,'Payload differs from the pose/geometry-verified clip'
        assert report['input_sha256']=={n:hashlib.sha256((ROOT/'input'/n).read_bytes()).hexdigest() for n in ['rig.json','mesh.json']},'QA rig/mesh inputs changed'
        clip=dict(payload,poses=decode_export(payload))
    else:
        clip=build_slam(existing);payload,keys,qs=export_clip(clip)
        report=qa_clip('Kill_Slam',clip,payload,qs)
        # Remove only this entry on repeat; on first build retain the complete old prefix.
        encoded=json.dumps(payload,separators=(',',':'))
        if 'Kill_Slam' in existing:
            start=raw.index('"Kill_Slam"');start=raw.index(':',start)+1
            while raw[start].isspace():start+=1
            unused,end=json.JSONDecoder().raw_decode(raw,start)
            updated=raw[:start]+encoded+raw[end:]
        else:
            end=raw.rfind('}');updated=raw[:end]+',"Kill_Slam":'+encoded+raw[end:]
        assert (out/'clips.json').read_text()==raw,'Clips changed during authoring; reread the fresh baseline'
        (out/'clips.json').write_text(updated)
        qa=json.loads((out/'qa.json').read_text())
        report['payload_sha256']=hashlib.sha256(json.dumps(payload,separators=(',',':')).encode()).hexdigest()
        report['input_sha256']={n:hashlib.sha256((ROOT/'input'/n).read_bytes()).hexdigest() for n in ['rig.json','mesh.json']}
        qa['Kill_Slam']=report;(out/'qa.json').write_text(json.dumps(qa,indent=2))
        print('SLAM QA',json.dumps(report),flush=True)
    failures=[k for k,v in report['asserts'].items() if not v]
    if failures:
        # Review-only native artifacts are allowed with the documented, literal
        # gripping-claw clearance failure. Never label that failed QA as passed.
        if failures!=['camera_clearance'] or args.qa_only:raise AssertionError(json.dumps(failures))
        print('KNOWN RIG CONSTRAINT: gripping claw camera clearance',report['min_camera_to_non_striking_mesh'],'< 1.2',flush=True)
    if args.qa_only:return
    import bpy
    from preview import _make_armature,_key_actions
    bpy.ops.wm.read_factory_settings(use_empty=True)
    armature=_make_armature(RIG)
    clips={n:dict(poses=decode_export(d),seconds=d.get('seconds',d['frames']/d['fps']),frames=d['frames'],fps=d['fps'],loop=d['loop']) for n,d in existing.items() if n!='Kill_Slam'}
    clip['poses']=decode_export(payload);clips['Kill_Slam']=clip
    parity=_key_actions(armature,RIG,clips)
    body=real_body();mesh=bpy.data.meshes.new('Real_Entity_Studio_Mesh')
    mesh.from_pydata(skin_root(body,RIG.rest_world).tolist(),[],body['tris'].tolist())
    obj=bpy.data.objects.new('Real_Entity',mesh);bpy.context.collection.objects.link(obj);obj.matrix_world=armature.matrix_world.copy()
    for j,n in enumerate(body['names']):
        group=obj.vertex_groups.new(name=n)
        for k in range(4):
            for i in np.where((body['bones'][:,k]==j)&(body['weights'][:,k]>0))[0]:group.add([int(i)],float(body['weights'][i,k]),'ADD')
    mod=obj.modifiers.new('Studio_exact_rig','ARMATURE');mod.object=armature
    armature.animation_data.action=bpy.data.actions['Kill_Slam']
    armature.animation_data.action['qa_passed']=report['passed']
    armature.animation_data.action['failed_checks']=json.dumps([k for k,v in report['asserts'].items() if not v])
    armature.animation_data.action['payload_sha256']=report['payload_sha256']
    for k,v in SLAM_MARKS.items():armature.animation_data.action.pose_markers.new(k).frame=round(1+v*30)
    sc=bpy.context.scene;sc.render.fps=30;sc.frame_start=1;sc.frame_end=163;sc.frame_set(1)
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(out/'blend'/'kill_slam.blend'))
    print('BLENDER FK',parity,flush=True)

if __name__=='__main__': main()
