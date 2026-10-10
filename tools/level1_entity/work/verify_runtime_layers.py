"""Offline geometry diagnostics for the final player correction layers."""
from pathlib import Path
import hashlib,json,math,re
import numpy as np
from rig_math import Rig,rot_x,mat_to_quat,quat_to_mat,slerp
from verify_payload import decode,sample

BASE=Path(__file__).resolve().parents[1]
player_path=BASE/'out/Level 1 Entity Motion.LocalScript.lua'
payload_path=BASE/'out/clips.json'
player=player_path.read_text()
data=json.loads(payload_path.read_text())
floor_up=float(json.loads((BASE/'out/qa.json').read_text())['_build']['floor_up'])
rig=Rig(BASE/'input/rig.json')
blend=json.loads((BASE/'work/blend_floor_report.json').read_text())
assert abs(blend['floor_up']-floor_up)<1e-9,'Re-run analyze_blends.py after changing FLOOR_UP'
assert blend['payload_sha256']==hashlib.sha256(payload_path.read_bytes()).hexdigest(),'Re-run analyze_blends.py after changing clips'
decoded=decode(data['Run'])
amps=(0.,.25,.5,.75,1.)
degrees_match=re.search(r'local LAND_COMPRESS_DEGREES = \{([^}]+)\}',player)
assert degrees_match,'Missing compression contract'
degrees={name:float(value) for name,value in re.findall(r'(\w+)\s*=\s*(-?\d+(?:\.\d+)?)',degrees_match.group(1))}
assert 'Hips' not in degrees,'Moving absorb must preserve the pelvis and legs'
checks=[]; before_min=math.inf;after_min=math.inf;base_min=math.inf
before_record,after_record=None,None
max_foot_change=0.
min_finger_after=math.inf
for i in range(256):
    phase=i/256
    base=sample(decoded,phase)
    original_world=rig.fk(base)
    for amp in amps:
        before={n:m.copy() for n,m in base.items()}
        rest=rig.rest_world['Hips'][:3,:3]
        before['Hips'][:3,3]+=np.linalg.solve(rest,np.array((0.,-.9*amp,0.)))
        before['Hips'][:3,:3]=(np.linalg.inv(rest)@rot_x(-math.radians(12)*amp)@rest)@before['Hips'][:3,:3]
        before_world=rig.fk(before)
        after={n:m.copy() for n,m in base.items()}
        for name,angle in degrees.items():
            rest=rig.rest_world[name][:3,:3]
            after[name][:3,:3]=(np.linalg.inv(rest)@rot_x(-math.radians(angle)*amp)@rest)@after[name][:3,:3]
        after_world=rig.fk(after)
        for name in ('LeftToeBase','RightToeBase','LeftFoot','RightFoot'):
            hb=float(before_world[name][1,3])+floor_up
            ha=float(after_world[name][1,3])+floor_up
            hbase=float(original_world[name][1,3])+floor_up
            base_min=min(base_min,hbase)
            if hb<before_min:
                before_min=hb;before_record={'phase':phase,'absorb_fraction':amp,'bone':name}
            if ha<after_min:
                after_min=ha;after_record={'phase':phase,'absorb_fraction':amp,'bone':name}
            max_foot_change=max(max_foot_change,float(np.linalg.norm(after_world[name][:3,3]-original_world[name][:3,3])))
        for name,m in after_world.items():
            if re.match(r'(Left|Right)Hand(Thumb2|Index3|Middle3|Ring3|Pinky3)$',name):
                min_finger_after=min(min_finger_after,float(m[1,3])+floor_up)
handoff_min=math.inf;handoff_worst=None
flight=decode(data['Lunge_Flight'])
for flight_phase in (.85,.90,.95,1.):
    a=sample(flight,flight_phase)
    for age in np.linspace(0,.06,61):
        b=sample(decoded,float(data['Run']['speed']*age/data['Run']['stride']))
        amp=(1-age/.25)**2
        for name,angle in degrees.items():
            rest=rig.rest_world[name][:3,:3]
            b[name][:3,:3]=(np.linalg.inv(rest)@rot_x(-math.radians(angle)*amp)@rest)@b[name][:3,:3]
        progress=float(age/.06)
        pose={}
        for name in a:
            t=np.eye(4)
            t[:3,:3]=quat_to_mat(slerp(mat_to_quat(a[name][:3,:3]),mat_to_quat(b[name][:3,:3]),progress))
            t[:3,3]=(1-progress)*a[name][:3,3]+progress*b[name][:3,3]
            pose[name]=t
        rest=rig.rest_world['Hips'][:3,:3]
        pose['Hips'][:3,3]+=np.linalg.solve(rest,np.array((0.,.06*math.sin(math.pi*progress)**2,0.)))
        world=rig.fk(pose)
        for name in ('LeftToeBase','RightToeBase','LeftFoot','RightFoot'):
            height=float(world[name][1,3])+floor_up
            if height<handoff_min:
                handoff_min=height;handoff_worst={'flight_phase':flight_phase,'transition_age':float(age),'bone':name}
assert '0.68 * walkWeight * prowlWeight' in player,'Player needs agreed pair-specific clearance lift'
assert '0.68 * prowlWeight * runWeight' in player
assert '1.40 * walkWeight * runWeight' in player
assert '0.06 * math.sin(math.pi * transition) ^ 2' in player,'Missing verified moving-handoff clearance'
checks={
    'crossblend_corrected_feet_above_minus_0_02':blend['lower_normal_blend_lift_minimum_height']>=-.02,
    'moving_absorb_keeps_run_feet_above_minus_0_02':after_min>=-.02,
    'moving_absorb_preserves_foot_positions':max_foot_change<1e-8,
    'moving_absorb_distal_finger_joints_above_floor':min_finger_after>=0,
    'player_uses_verified_pair_lift_coefficients':True,
    'moving_absorb_has_no_Hips_or_leg_rotation':all(n in ('Spine02','Spine01','Spine','Head') for n in degrees),
    'sampled_Flight_to_Run_handoff_feet_above_minus_0_02':handoff_min>=-.02,
}
report={
    'payload_sha256':hashlib.sha256(payload_path.read_bytes()).hexdigest(),
    'player_sha256':hashlib.sha256(player_path.read_bytes()).hexdigest(),
    'floor_up':floor_up,
    'audit_tool_sha256':{name:hashlib.sha256((BASE/name).read_bytes()).hexdigest()
                         for name in ('work/analyze_blends.py','work/verify_runtime_layers.py')},
    'tools':['work/analyze_blends.py','work/verify_runtime_layers.py'],
    'crossblend':{
        'weight_grid_step':blend['weights_grid_step'],'phase_samples':blend['phases'],
        'weight_combinations':blend['weight_combinations'],'evaluated_pose_samples':blend['all_compared_pose_samples'],
        'blend_order':'Walk/Prowl normalized within their sum, then Run; matching player CFrame:Lerp sequence',
        'minimum_foot_height_before':blend['worst_unlifted']['value'],'worst_before':blend['worst_unlifted'],
        'lift_formula':blend['lower_normal_blend_lift_formula'],
        'minimum_foot_height_after':blend['lower_normal_blend_lift_minimum_height'],
        'lift_at_pure_gaits':0.,'lift_at_half_Walk_Prowl_or_Prowl_Run':.17,'lift_at_half_Walk_Run':.35,
    },
    'moving_land_absorb':{
        'gait_phase_samples':256,'absorb_fractions':list(amps),'evaluated_pose_samples':256*len(amps),
        'before_method':'Counterfactual original brief layer: Hips rootY -0.9*absorb and rootX forward12deg*absorb',
        'minimum_foot_height_before':before_min,'worst_before':before_record,
        'after_method':'Player local Transform rotations converted through measured rest root orientations; upper-body compression only',
        'compression_degrees':degrees,'minimum_foot_height_after':after_min,'worst_after':after_record,
        'baseline_Run_minimum_foot_height':base_min,
        'maximum_foot_position_change_from_Run':max_foot_change,
        'minimum_distal_finger_joint_height_after':min_finger_after,
    },
    'moving_land_handoff_subset':{
        'flight_from_phases':[.85,.90,.95,1.], 'transition_seconds':.06,
        'time_samples_per_transition':61,'evaluated_pose_samples':244,
        'run_speed':data['Run']['speed'],'run_stride':data['Run']['stride'],
        'postblend_clearance_formula':'Hips root+Y 0.06*sin(pi*transition)^2, zero at both .06-second handoff endpoints',
        'root_floor_assumption':f'Root at original launch/standing height, FLOOR_UP{floor_up:g}; straight Run travel.',
        'minimum_foot_height':handoff_min,'worst':handoff_worst,
        'method':'Match final .06s local-CFrame transition from cached Flight target to advancing Run plus chest-only absorb.',
    },
    'asserts':checks,'passed':all(checks.values()),
    'limits':[
        f'Root launch/floor assumed{floor_up:g}studs from out/qa.json. Coordinates refer to ankle/ToeBase and distal finger bone pivots, not skinned soles/fingertips.',
        'The fixed-weight clearance lift leaves horizontal foot speed unchanged but changes contact height. Changing blend weights add vertical motion.',
        'Weights/phase are sampled on a dense grid, not analytically proved at every continuous value.',
        'Animator weight fade, capture handoff and arbitrary lunge crossfades are not covered; only the stated Flight-to-Run subset is sampled.',
        'Roblox CFrame:Lerp, replicated burst timing and actual streaming/Animator override behavior remain in-game checks.',
        'Activation baseline and first contact can coalesce before the audio Heartbeat; check the first visible footfall when the gait wakes.',
    ],
}
(BASE/'work/runtime_validation.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({'crossblend':report['crossblend'],'moving_land_absorb':report['moving_land_absorb'],'passed':report['passed']},indent=2))
assert report['passed'],checks
