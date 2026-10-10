"""Studio-rest-space kinematics for the Level 1 Entity.

All matrices use Roblox root coordinates: +X right, +Y up, -Z forward.
An input pose is {bone_name: 4x4 Bone.Transform}; FK applies exactly
parent_global @ Bone.CFrame @ Bone.Transform. No Blender bone-axis
assumptions enter the IK. Child offsets, hinge planes and palm planes
are measured from the supplied Studio rest frames.
"""
from __future__ import annotations

import argparse
import json
import math
from dataclasses import dataclass
from pathlib import Path

import numpy as np


EPS = 1e-10
IDENTITY = np.eye(4, dtype=float)


def unit(v):
    v = np.asarray(v, dtype=float)
    length = np.linalg.norm(v)
    if length < EPS:
        raise ValueError("Cannot normalise a zero direction")
    return v / length


def matrix(components):
    """CFrame:GetComponents(): translation then row-major 3x3 rotation."""
    a = np.asarray(components, dtype=float)
    if a.shape == (4, 4):
        return a.copy()
    if a.shape != (12,):
        raise ValueError(f"Expected 12 CFrame components, got {a.shape}")
    out = np.eye(4)
    out[:3, 3] = a[:3]
    out[:3, :3] = a[3:].reshape(3, 3)
    return out


def transform(rotation=None, translation=None):
    out = np.eye(4)
    if rotation is not None:
        out[:3, :3] = np.asarray(rotation, dtype=float)
    if translation is not None:
        out[:3, 3] = np.asarray(translation, dtype=float)
    return out


def rigid_inverse(m):
    """Exact inversion keeps the tiny Studio float errors out of FK parity."""
    return np.linalg.inv(m)


def orthonormal(rotation):
    """Return a proper rotation, removing only floating-point scale/shear."""
    u, _, vt = np.linalg.svd(np.asarray(rotation, dtype=float))
    r = u @ vt
    if np.linalg.det(r) < 0:
        u[:, -1] *= -1
        r = u @ vt
    return r


def axis_rotation(axis, angle):
    """Radians, root or local axis as supplied by the caller."""
    x, y, z = unit(axis)
    c, s = math.cos(angle), math.sin(angle)
    d = 1 - c
    return np.array([[c + x*x*d, x*y*d-z*s, x*z*d+y*s],
                     [y*x*d+z*s, c+y*y*d, y*z*d-x*s],
                     [z*x*d-y*s, z*y*d+x*s, c+z*z*d]])


def rot_x(angle): return axis_rotation((1, 0, 0), angle)
def rot_y(angle): return axis_rotation((0, 1, 0), angle)
def rot_z(angle): return axis_rotation((0, 0, 1), angle)


def basis(axis, normal):
    """Orthonormal columns: along-bone, hinge normal, third direction."""
    a = unit(axis)
    n = np.asarray(normal, dtype=float) - a * np.dot(normal, a)
    if np.linalg.norm(n) < 1e-7:
        fallback = np.eye(3)[int(np.argmin(np.abs(a)))]
        n = fallback - a * np.dot(fallback, a)
    n = unit(n)
    return np.column_stack((a, n, np.cross(a, n)))


def basis_mapping(local_axis, local_normal, root_axis, root_normal):
    """Absolute root orientation mapping two measured local directions."""
    return basis(root_axis, root_normal) @ basis(local_axis, local_normal).T


def quat_to_mat(q):
    x, y, z, w = unit(q)
    return np.array([[1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w)],
                     [2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w)],
                     [2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y)]])


def mat_to_quat(rotation):
    """Quaternion xyzw, unit length (the data and Roblox exporter order)."""
    m = orthonormal(np.asarray(rotation)[:3, :3])
    trace = np.trace(m)
    if trace > 0:
        s = math.sqrt(trace + 1) * 2
        q = np.array(((m[2,1]-m[1,2])/s, (m[0,2]-m[2,0])/s,
                      (m[1,0]-m[0,1])/s, s/4))
    else:
        i = int(np.argmax(np.diag(m)))
        if i == 0:
            s = math.sqrt(max(0., 1+m[0,0]-m[1,1]-m[2,2]))*2
            q = np.array((s/4, (m[0,1]+m[1,0])/s, (m[0,2]+m[2,0])/s,
                          (m[2,1]-m[1,2])/s))
        elif i == 1:
            s = math.sqrt(max(0., 1+m[1,1]-m[0,0]-m[2,2]))*2
            q = np.array(((m[0,1]+m[1,0])/s, s/4, (m[1,2]+m[2,1])/s,
                          (m[0,2]-m[2,0])/s))
        else:
            s = math.sqrt(max(0., 1+m[2,2]-m[0,0]-m[1,1]))*2
            q = np.array(((m[0,2]+m[2,0])/s, (m[1,2]+m[2,1])/s, s/4,
                          (m[1,0]-m[0,1])/s))
    return unit(q)


def slerp(a, b, amount):
    a, b = unit(a), unit(b)
    dot = float(np.dot(a, b))
    if dot < 0:
        b, dot = -b, -dot
    dot = min(1., max(-1., dot))
    if dot > 0.9995:
        return unit(a + amount*(b-a))
    theta = math.acos(dot)
    return (math.sin((1-amount)*theta)*a + math.sin(amount*theta)*b) / math.sin(theta)


def rotation_angle(rotation):
    m = orthonormal(np.asarray(rotation)[:3, :3])
    return math.acos(min(1., max(-1., (np.trace(m)-1)/2)))


@dataclass
class IKResult:
    start: np.ndarray
    joint: np.ndarray
    requested: np.ndarray
    reached: np.ndarray
    lengths: tuple[float, float]
    requested_distance: float
    reachable: bool
    bend_degrees: float
    endpoint_error: float


class Rig:
    def __init__(self, path):
        self.path = Path(path)
        self.data = json.loads(self.path.read_text())
        self.mesh = matrix(self.data['meshInRoot'])
        self.parents = {b['name']: b.get('parent') for b in self.data['bones']}
        self.rest = {b['name']: matrix(b['cframe']) for b in self.data['bones']}
        self.studio_world = {b['name']: matrix(b['inRoot']) for b in self.data['bones']}
        pending, self.order = list(self.rest), []
        while pending:
            ready = [n for n in pending if self.parents[n] is None or self.parents[n] in self.order]
            if not ready:
                raise ValueError('Rig contains a cycle or a missing parent')
            self.order.extend(ready)
            pending = [n for n in pending if n not in ready]
        self.names, self.parent = self.order, self.parents
        self.children = {n: [c for c in self.order if self.parents[c] == n] for n in self.order}
        self.rest_world = self.fk({})
        self.lengths = {}
        self.chain_axes = {}
        for side in ('Left', 'Right'):
            for part, middle, end in (('UpLeg', 'Leg', 'Foot'), ('Arm', 'ForeArm', 'Hand')):
                start, mid, finish = side+part, side+middle, side+end
                a = self.rest[mid][:3, 3]
                b = self.rest[finish][:3, 3]
                l1, l2 = float(np.linalg.norm(a)), float(np.linalg.norm(b))
                self.lengths[start] = (l1, l2)
                world_a = self.rest_world[mid][:3,3] - self.rest_world[start][:3,3]
                world_b = self.rest_world[finish][:3,3] - self.rest_world[mid][:3,3]
                normal = np.cross(world_a, world_b)
                if np.linalg.norm(normal) < 1e-7:
                    normal = self.rest_world[start][:3, 0]
                normal = unit(normal)
                self.chain_axes[(start, mid, finish)] = {
                    'upper_axis': unit(a), 'lower_axis': unit(b),
                    'upper_normal': unit(np.linalg.solve(self.rest_world[start][:3,:3], normal)),
                    'lower_normal': unit(np.linalg.solve(self.rest_world[mid][:3,:3], normal)),
                    'rest_hinge_root': normal,
                }
        self.hand_axes, self.finger_axes, self.finger_spread_axes = {}, {}, {}
        self._measure_hands()
        self.rest_error = self.verify_rest()

    def fk(self, pose):
        world = {}
        for name in self.order:
            parent = self.parents[name]
            g = self.mesh if parent is None else world[parent]
            world[name] = g @ self.rest[name] @ pose.get(name, IDENTITY)
        return world

    def verify_rest(self, tolerance=0.001):
        world = self.fk({})
        position_error = max(float(np.linalg.norm(world[n][:3,3]-self.studio_world[n][:3,3]))
                             for n in self.order)
        rotation_error = max(float(np.max(np.abs(world[n][:3,:3]-self.studio_world[n][:3,:3])))
                             for n in self.order)
        assert position_error <= tolerance, (position_error, tolerance)
        assert rotation_error <= tolerance, (rotation_error, tolerance)
        return {'max_position_studs': position_error, 'max_rotation_component': rotation_error,
                'tolerance_studs': tolerance, 'bones': len(self.order)}

    def set_root_transform(self, pose, name, desired):
        """Absolute root-space CFrame -> Bone.Transform, including translation."""
        parent = self.parents[name]
        parent_global = self.mesh if parent is None else self.fk(pose)[parent]
        pose[name] = rigid_inverse(parent_global @ self.rest[name]) @ np.asarray(desired)
        return pose[name]

    def set_root_rotation(self, pose, name, rotation):
        """Absolute root orientation; preserve the bone's Transform translation."""
        parent = self.parents[name]
        parent_global = self.mesh if parent is None else self.fk(pose)[parent]
        out = pose.get(name, IDENTITY).copy()
        out[:3,:3] = np.linalg.solve((parent_global @ self.rest[name])[:3,:3], rotation)
        pose[name] = out
        return out

    def set_root_position(self, pose, name, position):
        desired = self.fk(pose)[name].copy()
        desired[:3,3] = position
        return self.set_root_transform(pose, name, desired)

    def solve_chain(self, pose, start, mid, end, target, pole, clamp=False, reach_margin=0.002):
        """Analytic two-bone IK in measured bone axes, preserving translations.

        pole is a root-space *point* toward which the knee/elbow bends. A target
        beyond reach raises unless clamp=True; every result reports the original
        distance so clipping cannot silently count as a reach QA pass.
        """
        world = self.fk(pose)
        s = world[start][:3,3].copy()
        requested = np.asarray(target, dtype=float)
        to_target = requested-s
        distance = float(np.linalg.norm(to_target))
        l1, l2 = self.lengths[start]
        min_d, max_d = abs(l1-l2)+reach_margin, l1+l2-reach_margin
        reachable = min_d <= distance <= max_d
        if not reachable and not clamp:
            raise ValueError(f'{start} target {distance:.6f} outside [{min_d:.6f}, {max_d:.6f}]')
        d = float(np.clip(distance, min_d, max_d))
        along = unit(to_target) if distance > EPS else unit(world[end][:3,3]-s)
        target_actual = s + along*d
        pole_vector = np.asarray(pole, dtype=float)-s
        lateral = pole_vector-along*np.dot(pole_vector, along)
        if np.linalg.norm(lateral) < 1e-6:
            rest_normal = self.chain_axes[(start,mid,end)]['rest_hinge_root']
            lateral = np.cross(rest_normal, along)
        lateral = unit(lateral)
        projection = (l1*l1-l2*l2+d*d)/(2*d)
        height = math.sqrt(max(0., l1*l1-projection*projection))
        joint = s + projection*along + height*lateral
        upper, lower = joint-s, target_actual-joint
        hinge = unit(np.cross(upper, lower))
        axes = self.chain_axes[(start,mid,end)]
        self.set_root_rotation(pose, start, basis_mapping(axes['upper_axis'],axes['upper_normal'],upper,hinge))
        self.set_root_rotation(pose, mid, basis_mapping(axes['lower_axis'],axes['lower_normal'],lower,hinge))
        final = self.fk(pose)
        endpoint_error = float(np.linalg.norm(final[end][:3,3]-target_actual))
        assert endpoint_error < 0.0001, (start, endpoint_error)
        bend = math.degrees(math.acos(float(np.clip(np.dot(unit(upper),unit(lower)),-1,1))))
        return IKResult(s,joint,requested,target_actual,(l1,l2),distance,reachable,bend,endpoint_error)

    def foot_rotation(self, side, pitch_deg=0., yaw_deg=0.):
        """Root-space foot orientation. +pitch lifts toes, yaw is root +Y.

        Zero pitch retains the measured ankle-to-toe downward slope. Zero yaw
        places the toe directly forward, correcting the Studio toe-out rather
        than assuming the local Foot X/Y/Z are root X/Y/Z.
        """
        name, toe = side+'Foot', side+'ToeBase'
        rest_r = self.rest_world[name][:3,:3]
        axis = self.rest[toe][:3,3]
        rest_direction = rest_r @ unit(axis)
        original_yaw = math.atan2(-rest_direction[0],-rest_direction[2])
        flat = rot_y(-original_yaw) @ rest_r
        return rot_y(math.radians(yaw_deg)) @ rot_x(math.radians(pitch_deg)) @ flat

    def solve_leg_toe(self, side, pose, toe_target, pitch_deg=0., yaw_deg=0., pole=None,
                      toe_bend_deg=0., clamp=False, reach_margin=0.002):
        """Solve ankle from the desired planted toe, then leg and foot orientation."""
        foot, toe = side+'Foot', side+'ToeBase'
        r = self.foot_rotation(side,pitch_deg,yaw_deg)
        ankle = np.asarray(toe_target,dtype=float)-r @ self.rest[toe][:3,3]
        hip = self.fk(pose)[side+'UpLeg'][:3,3]
        if pole is None:
            pole = hip + np.array((0.,-1.,-5.))
        result = self.solve_chain(pose,side+'UpLeg',side+'Leg',foot,ankle,pole,clamp,reach_margin)
        self.set_root_rotation(pose,foot,r)
        foot_delta = r @ np.linalg.inv(self.rest_world[foot][:3,:3])
        toe_r = foot_delta @ rot_x(math.radians(toe_bend_deg)) @ self.rest_world[toe][:3,:3]
        self.set_root_rotation(pose,toe,toe_r)
        result.toe_error = float(np.linalg.norm(self.fk(pose)[toe][:3,3]-toe_target))
        return result

    def orient_foot_toe(self, pose, side, toe_target, pitch=0., yaw=0., **kwargs):
        return self.solve_leg_toe(side,pose,toe_target,pitch,yaw,**kwargs)

    def _measure_hands(self):
        for side in ('Left','Right'):
            hand = side+'Hand'
            g = self.rest_world
            finger = unit(g[hand+'Middle3'][:3,3]-g[hand+'Middle1'][:3,3])
            across = g[hand+'Pinky1'][:3,3]-g[hand+'Index1'][:3,3]
            palm = unit(np.cross(across,finger))
            inward = np.array((1.,0.,0.)) if side == 'Left' else np.array((-1.,0.,0.))
            if np.dot(palm,inward) < 0:
                palm = -palm
            hand_r = g[hand][:3,:3]
            self.hand_axes[side] = {'finger':unit(np.linalg.solve(hand_r,finger)),
                                    'palm':unit(np.linalg.solve(hand_r,palm)),
                                    'palm_root':palm,'finger_root':finger}
            for digit in ('Thumb','Index','Middle','Ring','Pinky'):
                count = 2 if digit == 'Thumb' else 3
                for number in range(1,count+1):
                    name = hand+digit+str(number)
                    if number < count:
                        next_name = hand+digit+str(number+1)
                        direction = g[next_name][:3,3]-g[name][:3,3]
                    else:
                        prev_name = hand+digit+str(number-1)
                        direction = g[name][:3,3]-g[prev_name][:3,3]
                    direction = unit(direction)
                    curl_axis = np.cross(direction,palm)
                    if np.linalg.norm(curl_axis) < 1e-6:
                        curl_axis = np.cross(direction,inward)
                    self.finger_axes[name] = unit(np.linalg.solve(g[name][:3,:3],curl_axis))
                    self.finger_spread_axes[name] = unit(np.linalg.solve(g[name][:3,:3],palm))

    def orient_hand(self, pose, side, finger_direction, palm_normal):
        axes = self.hand_axes[side]
        return self.set_root_rotation(pose,side+'Hand',
            basis_mapping(axes['finger'],axes['palm'],finger_direction,palm_normal))

    def curl_fingers(self, pose, side, curl=0., spread=0.):
        """curl/spread fractions. Axes measured separately for every phalanx.

        Full curl is 58/78/65 degrees at the three joints; spread affects
        proximal knuckles, with digit-specific signs in the measured palm plane.
        """
        hand = side+'Hand'
        for digit, spread_degrees in (('Thumb',-30),('Index',-13),('Middle',0),('Ring',7),('Pinky',16)):
            count = 2 if digit == 'Thumb' else 3
            for number in range(1,count+1):
                name = hand+digit+str(number)
                angle = (45 if digit == 'Thumb' else (58,78,65)[number-1])*curl
                r = axis_rotation(self.finger_axes[name],math.radians(angle))
                if number == 1 and spread:
                    # Mirrored hands need mirrored spread in their palm planes.
                    sign = 1 if side == 'Right' else -1
                    r = axis_rotation(self.finger_spread_axes[name],math.radians(sign*spread_degrees*spread)) @ r
                pose[name] = transform(r,pose.get(name,IDENTITY)[:3,3])

    def report(self):
        return {'rest_fk':self.rest_error,
                'limbs':{k:{'upper':v[0],'lower':v[1],'total':sum(v)} for k,v in self.lengths.items()},
                'measured_chain_axes':{':'.join(k):{a:b.tolist() for a,b in v.items()}
                                       for k,v in self.chain_axes.items()},
                'finger_curl_axes':{k:v.tolist() for k,v in self.finger_axes.items()},
                'hand_axes':{s:{k:v.tolist() for k,v in a.items()} for s,a in self.hand_axes.items()},
                'coordinates':'Root space: +X right, +Y up, -Z forward; matrices row-major; quaternions xyzw'}


def self_test(rig):
    tests=[]
    for side in ('Left','Right'):
        for suffix,middle,end in (('UpLeg','Leg','Foot'),('Arm','ForeArm','Hand')):
            pose={}
            start=side+suffix
            target=rig.rest_world[side+end][:3,3].copy()
            pole=rig.rest_world[side+middle][:3,3].copy()
            result=rig.solve_chain(pose,start,side+middle,side+end,target,pole)
            assert result.endpoint_error < 0.001
            tests.append({'chain':start,'endpoint_error':result.endpoint_error,'bend_degrees':result.bend_degrees})
        pose={}
        hip=rig.rest_world[side+'UpLeg'][:3,3]
        # A reachable forward plant exercises measured foot axes and exact pinning.
        toe=np.array((hip[0],hip[1]-3.9,hip[2]-1.5))
        result=rig.solve_leg_toe(side,pose,toe,pitch_deg=10,yaw_deg=8 if side=='Left' else -8)
        assert result.toe_error < 0.001
        rig.curl_fingers(pose,side,.6,.5)
        for name,m in pose.items():
            q=mat_to_quat(m[:3,:3])
            assert abs(float(np.linalg.norm(q))-1) < 1e-9
            assert np.max(np.abs(quat_to_mat(q)-orthonormal(m[:3,:3]))) < 1e-8
        tests.append({'chain':side+' toe plant','toe_error':result.toe_error})
    return tests


if __name__ == '__main__':
    # Blender supplies its script flags before --; regular Python does not.
    import sys
    args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else sys.argv[1:]
    parser=argparse.ArgumentParser()
    base=Path(__file__).resolve().parents[1]
    parser.add_argument('--rig',default=str(base/'input/rig.json'))
    parser.add_argument('--report',default=str(base/'work/rig_math_report.json'))
    options=parser.parse_args(args)
    rig=Rig(options.rig)
    report=rig.report()
    report['self_test']=self_test(rig)
    Path(options.report).write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({'rest_fk':report['rest_fk'],'self_test':report['self_test']},indent=2))
