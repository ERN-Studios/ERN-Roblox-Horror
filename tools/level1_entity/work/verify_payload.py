"""Independent dense FK evaluation of the *quantized deliverable*.

No build_clips import, IK, pose correction or bpy. The decoder and sampler
operate on out/clips.json exactly as the client does: normalize integer
xyzw quaternions, slerp rotations and linearly interpolate Hips translation.
Four uniform substeps per source interval cover 0, .25, .50 and .75.
"""
from pathlib import Path
import argparse
import hashlib
import json
import math
import os
import numpy as np

from rig_math import Rig, quat_to_mat, slerp, rotation_angle

BASE=Path(__file__).resolve().parents[1]
DUTY={'Walk':.62,'Prowl':.42,'Run':.28}


def decode(entry):
    n=entry['frames']
    rotations={}
    raw_norm_error=0.
    raw_min_dot=1.
    for name,values in entry['bones'].items():
        raw=np.asarray(values,dtype=float).reshape(n,4)/10000.
        norms=np.linalg.norm(raw,axis=1)
        assert np.all(norms > 1e-8),(name,'zero encoded quaternion')
        raw_norm_error=max(raw_norm_error,float(np.max(np.abs(norms-1))))
        dots=np.sum(raw[:-1]*raw[1:],axis=1)
        if entry['loop']:
            dots=np.append(dots,np.dot(raw[-1],raw[0]))
        if len(dots): raw_min_dot=min(raw_min_dot,float(np.min(dots)))
        rotations[name]=raw/norms[:,None]
    return {'rotations':rotations,'hips':np.asarray(entry['hips'],dtype=float).reshape(n,3)/1000.,
            'frames':n,'loop':entry['loop'],'raw_norm_error':raw_norm_error,'raw_min_dot':raw_min_dot}


def sample(decoded,phase):
    n=decoded['frames']
    if decoded['loop']:
        x=(phase%1)*n
        i=int(math.floor(x)); j=(i+1)%n
    else:
        x=min(1.,max(0.,phase))*(n-1)
        i=min(n-1,int(math.floor(x))); j=min(i+1,n-1)
    fraction=x-i
    pose={}
    for name,qs in decoded['rotations'].items():
        t=np.eye(4)
        t[:3,:3]=quat_to_mat(slerp(qs[i],qs[j],fraction))
        pose[name]=t
    if 'Hips' not in pose: pose['Hips']=np.eye(4)
    pose['Hips'][:3,3]=decoded['hips'][i]*(1-fraction)+decoded['hips'][j]*fraction
    return pose


def stance(name,phase,side):
    if name in DUTY:
        q=(phase+(0 if side=='Left' else .5))%1
        return q < DUTY[name]-1e-9
    if name=='Lunge_Windup': return True
    if name=='Lunge_Land': return phase <= .70+1e-9
    return False


def knee_degrees(world,side):
    upper=world[side+'Leg'][:3,3]-world[side+'UpLeg'][:3,3]
    lower=world[side+'Foot'][:3,3]-world[side+'Leg'][:3,3]
    cosine=np.dot(upper,lower)/(np.linalg.norm(upper)*np.linalg.norm(lower))
    return math.degrees(math.acos(float(np.clip(cosine,-1,1))))


def span(world,a,b): return float(np.linalg.norm(world[a][:3,3]-world[b][:3,3]))


def extrema(values):
    return {'min':float(min(values)),'max':float(max(values))}


def playback_rotation(decoded,seconds,hz=60):
    # Quarter-dt offsets also catch a fast pose change between two nominal
    # render instants. Check the loop closure through the sampler's modulo.
    dt=1/hz
    worst={'degrees':0.,'bone':None,'time_start':None,'time_end':None}
    count=0
    for offset in (0.,.25,.5,.75):
        for i in range(math.ceil(seconds*hz)):
            start=(i+offset)*dt
            if start>=seconds: continue
            end=start+dt if decoded['loop'] else min(seconds,start+dt)
            a=sample(decoded,start/seconds);b=sample(decoded,end/seconds)
            for bone in decoded['rotations']:
                angle=math.degrees(rotation_angle(a[bone][:3,:3].T@b[bone][:3,:3]))
                if angle>worst['degrees']:
                    worst={'degrees':angle,'bone':bone,'time_start':start,'time_end':end}
            count+=1
    return {'hz':hz,'quarter_dt_offsets':4,'intervals_evaluated':count,'worst':worst,
            'passed':worst['degrees']<35}


def evaluate(rig,name,entry,floor_up,substeps):
    decoded=decode(entry)
    n=entry['frames']
    source_intervals=n if entry['loop'] else n-1
    intervals=source_intervals*substeps
    seconds=n/entry['fps']
    dt=seconds/intervals
    records=[]
    foot_heights=[]
    ankle={'Left':[],'Right':[]}
    knee={'Left':[],'Right':[]}
    leg_spans=[]; arm_spans=[]; upper_length_errors=[]; lower_length_errors=[]
    shoulder_lean=[]; hips_y=[]; distal_fingers=[]
    max_distal_forward={'value':-math.inf,'phase':None,'bone':None}
    min_distal_height={'value':math.inf,'phase':None,'bone':None}
    min_foot={'value':math.inf,'phase':None,'bone':None}
    max_rotation_step=0.
    previous_pose=None
    for i in range(intervals+1):
        phase=i/intervals
        pose=sample(decoded,phase)
        world=rig.fk(pose)
        toes={}
        hips_y.append(float(world['Hips'][1,3])+floor_up)
        hip_mid=(world['LeftUpLeg'][:3,3]+world['RightUpLeg'][:3,3])/2
        shoulder_mid=(world['LeftArm'][:3,3]+world['RightArm'][:3,3])/2
        trunk=shoulder_mid-hip_mid
        shoulder_lean.append(math.degrees(math.atan2(-trunk[2],trunk[1])))
        for side in ('Left','Right'):
            toes[side]=world[side+'ToeBase'][:3,3].copy()
            ankle[side].append(float(world[side+'Foot'][1,3])+floor_up)
            knee[side].append(knee_degrees(world,side))
            leg_spans.append(span(world,side+'UpLeg',side+'Foot'))
            arm_spans.append(span(world,side+'Arm',side+'Hand'))
            for start,mid,end in ((side+'UpLeg',side+'Leg',side+'Foot'),
                                  (side+'Arm',side+'ForeArm',side+'Hand')):
                l1,l2=rig.lengths[start]
                upper_length_errors.append(abs(span(world,start,mid)-l1))
                lower_length_errors.append(abs(span(world,mid,end)-l2))
            for suffix in ('Foot','ToeBase'):
                bone=side+suffix
                h=float(world[bone][1,3])+floor_up
                foot_heights.append(h)
                if h<min_foot['value']: min_foot={'value':h,'phase':phase,'bone':bone}
            for digit in ('Thumb','Index','Middle','Ring','Pinky'):
                bone=side+'Hand'+digit+('2' if digit=='Thumb' else '3')
                h=float(world[bone][1,3])+floor_up
                f=-float(world[bone][2,3])
                distal_fingers.append(h)
                if h<min_distal_height['value']: min_distal_height={'value':h,'phase':phase,'bone':bone}
                if f>max_distal_forward['value']: max_distal_forward={'value':f,'phase':phase,'bone':bone}
        records.append((phase,toes))
        if previous_pose is not None:
            for bone in decoded['rotations']:
                d=previous_pose[bone][:3,:3].T@pose[bone][:3,:3]
                max_rotation_step=max(max_rotation_step,math.degrees(rotation_angle(d)))
        previous_pose=pose
    max_slide=0.; max_slide_xy=0.; max_slide_record=None
    stance_segments=0
    for (pa,a),(pb,b) in zip(records,records[1:]):
        for side in ('Left','Right'):
            # Exclude the contact-boundary segment unless both ends are planted.
            if not (stance(name,pa,side) and stance(name,pb,side)): continue
            delta=b[side]-a[side]
            delta[2]-=float(entry['stride'])*(pb-pa)
            slide=float(np.linalg.norm(delta))
            xy_slide=float(np.linalg.norm(delta[[0,2]]))
            stance_segments+=1
            if slide>max_slide:
                max_slide=slide
                max_slide_record={'side':side,'phase_start':pa,'phase_end':pb,'floor_delta':delta.tolist()}
            max_slide_xy=max(max_slide_xy,xy_slide)
    # Per-source-frame equivalent makes the denser sampling's units explicit.
    frame_slide=max_slide*substeps
    # Root-at-launch-height is a conservative floor reference for the flight
    # data: an actual upward ballistic root only adds clearance to these poses.
    floor_assert=True
    playback=playback_rotation(decoded,seconds)
    checks={
        'rest_fk':rig.rest_error['max_position_studs']<.001,
        'leg_reach_under_3_86':max(leg_spans)<=3.86,
        'arm_reach_under_4_10':max(arm_spans)<=4.10,
        'segment_lengths_preserved':max(upper_length_errors+lower_length_errors)<.0001,
        'stance_slide_under_0_05_per_source_frame':frame_slide<.05,
        'grounded_feet_above_minus_0_02':(not floor_assert) or min(foot_heights)>=-.02,
        'encoded_quaternions_within_0_0001_of_unit':decoded['raw_norm_error']<.0001,
        'encoded_quaternions_sign_continuous':decoded['raw_min_dot']>0,
        'interpolation_rotation_under_35_degrees_per_source_frame':max_rotation_step*substeps<35,
        'nominal_60Hz_rotation_under_35_degrees':playback['passed'],
    }
    return {
        'frames':n,'fps':entry['fps'],'seconds':seconds,'source_intervals':source_intervals,
        'samples':len(records),'substeps_per_source_interval':substeps,
        'duties':DUTY.get(name),'stance_segments_evaluated':stance_segments,
        'max_stance_slide_per_substep':max_slide,
        'max_stance_slide_per_source_frame_equivalent':frame_slide,
        'max_stance_horizontal_slide_per_source_frame_equivalent':max_slide_xy*substeps,
        'max_stance_floor_velocity_error_studs_per_second':max_slide/dt if stance_segments else None,
        'worst_stance_segment':max_slide_record,
        'minimum_foot_joint_height':min_foot,
        'floor_assert_applied':floor_assert,
        'max_leg_reach':max(leg_spans),'max_arm_reach':max(arm_spans),
        'max_upper_segment_length_error':max(upper_length_errors),
        'max_lower_segment_length_error':max(lower_length_errors),
        'knee_flexion_degrees':{s:extrema(v) for s,v in knee.items()},
        'ankle_height_above_floor':{s:extrema(v) for s,v in ankle.items()},
        'hip_bone_height_above_floor':extrema(hips_y),
        'hip_to_midshoulder_sagittal_lean_degrees':extrema(shoulder_lean),
        'distal_finger_joint_height':extrema(distal_fingers),
        'lowest_distal_finger_joint':min_distal_height,
        'furthest_distal_finger_joint_forward':max_distal_forward,
        'max_encoded_quaternion_norm_error':decoded['raw_norm_error'],
        'min_encoded_quaternion_adjacent_dot':decoded['raw_min_dot'],
        'max_interpolation_rotation_degrees_per_source_frame_equivalent':max_rotation_step*substeps,
        'nominal_60Hz_rotation':playback,
        'asserts':checks,'passed':all(checks.values()),
    }


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--clips',default=str(BASE/'out/clips.json'))
    parser.add_argument('--rig',default=str(BASE/'input/rig.json'))
    parser.add_argument('--floor-up',type=float,default=float(os.environ.get('FLOOR_UP','8.0')))
    parser.add_argument('--substeps',type=int,default=4)
    parser.add_argument('--report',default=str(BASE/'work/payload_validation.json'))
    args=parser.parse_args()
    path=Path(args.clips)
    payload=path.read_bytes()
    data=json.loads(payload)
    rig=Rig(args.rig)
    clips={name:evaluate(rig,name,entry,args.floor_up,args.substeps) for name,entry in data.items()}
    report={
        'provenance':{'input':str(path.relative_to(BASE)),
                      'payload_sha256':hashlib.sha256(payload).hexdigest(),
                      'rig_sha256':hashlib.sha256(Path(args.rig).read_bytes()).hexdigest(),
                      'evaluator_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest()},
        'floor_up':args.floor_up,'rest_fk':rig.rest_error,
        'method':'Independent integer payload decode; normalized quaternion slerp plus linear Hips translation; dense FK at quarter intervals.',
        'stance_inference':'Walk .62, Prowl .42, Run .28; phase0 left and phase.5 right; Windup planted; Land planted until phase.70.',
        'notes':[
            'Flight floor is checked conservatively with the root at launch height; the actual upward ballistic arc adds clearance.',
            'Distal finger joints are the last measured bone pivots, not mesh fingertips. Finger-floor penetration is diagnostic only.',
            'Land final30% shifts its toes toward Run contact, so that section is intentionally excluded from planted-stance slide.',
            'Per-source-frame slide/rotation equivalents multiply each quarter-interval result by4; all intermediate sample points are checked.',
            'This evaluator does not import build_clips, use IK, repair poses or read the authoring foot targets.',
            'All geometric checks concern bone pivots. Mesh soles, skinning, streamed replication and Blender/Roblox runtime parity need in-game checks.',
        ],
        'clips':clips,'passed':all(c['passed'] for c in clips.values()),
    }
    Path(args.report).write_text(json.dumps(report,indent=2)+'\n')
    print('Clip              Samples  slide/frame  min foot  leg reach  arm reach  knee max  lean min/max  PASS')
    for name,c in clips.items():
        knee=max(v['max'] for v in c['knee_flexion_degrees'].values())
        lean=c['hip_to_midshoulder_sagittal_lean_degrees']
        print(f'{name:18} {c["samples"]:7d} {c["max_stance_slide_per_source_frame_equivalent"]:12.6f}'
              f' {c["minimum_foot_joint_height"]["value"]:9.4f} {c["max_leg_reach"]:10.4f}'
              f' {c["max_arm_reach"]:10.4f} {knee:9.2f} {lean["min"]:6.1f}/{lean["max"]:5.1f} {c["passed"]}')
    if not report['passed']:
        failed={name:[k for k,v in c['asserts'].items() if not v] for name,c in clips.items() if not c['passed']}
        raise AssertionError(failed)


if __name__=='__main__': main()
