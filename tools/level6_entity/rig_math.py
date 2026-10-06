"""Forward kinematics and a two-bone arm solver for the Counter's rig, in plain Python.

The rig (export/roblox_mesh.json) is a T-pose with identity bone frames: a bone's Transform is a rotation in its
parent's frame, in model axes (X across with the left limbs at -X, Y up, the face toward -Z), and a child bone
sits at its parent's position plus the parent's rotation applied to their rest offset. That is exactly what
Roblox does with Bone.CFrame * Bone.Transform, so positions worked out here are the positions in the game
(checked against TransformedWorldCFrame on 2026-10-06: under a hundredth of a stud).
"""
import json, math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MESH = json.loads((ROOT / 'artifacts' / 'level6-entity-20261003' / 'export' / 'roblox_mesh.json').read_text())
BONES = [b['name'] for b in MESH['bones']]
REST = {b['name']: tuple(b['pos']) for b in MESH['bones']}
PARENT = {b['name']: b['parent'] for b in MESH['bones']}
IDENT = (0.0, 0.0, 0.0, 1.0)
PALM_REST = (0.0, -1.0, 0.0)            # in the T-pose the palms face the floor and the thumbs point forward (-Z)


def add(a, b): return (a[0] + b[0], a[1] + b[1], a[2] + b[2])
def sub(a, b): return (a[0] - b[0], a[1] - b[1], a[2] - b[2])
def mul(a, k): return (a[0] * k, a[1] * k, a[2] * k)
def dot(a, b): return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
def cross(a, b): return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])
def length(a): return math.sqrt(dot(a, a))


def unit(a):
    n = length(a)
    return (a[0] / n, a[1] / n, a[2] / n)


def lerp(a, b, t): return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)


def qmul(a, b):
    """a after b."""
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return (aw * bx + ax * bw + ay * bz - az * by, aw * by - ax * bz + ay * bw + az * bx,
            aw * bz + ax * by - ay * bx + az * bw, aw * bw - ax * bx - ay * by - az * bz)


def qinv(q): return (-q[0], -q[1], -q[2], q[3])


def qrot(q, v):
    u = (q[0], q[1], q[2])
    t = mul(cross(u, v), 2.0)
    return add(add(v, mul(t, q[3])), cross(u, t))


def qaxis(axis, degrees):
    h = math.radians(degrees) / 2
    a = unit(axis)
    s = math.sin(h)
    return (a[0] * s, a[1] * s, a[2] * s, math.cos(h))


def R(axis, degrees):
    return qaxis({'x': (1, 0, 0), 'y': (0, 1, 0), 'z': (0, 0, 1)}[axis], degrees)


def chain(*parts):
    """chain(a, b, c) = a after b after c."""
    q = IDENT
    for part in reversed(parts):
        q = qmul(part, q)
    return q


def qmatrix(c0, c1, c2):
    """The rotation whose matrix has these columns."""
    m00, m10, m20 = c0
    m01, m11, m21 = c1
    m02, m12, m22 = c2
    tr = m00 + m11 + m22
    if tr > 0:
        s = math.sqrt(tr + 1.0) * 2
        q = ((m21 - m12) / s, (m02 - m20) / s, (m10 - m01) / s, 0.25 * s)
    elif m00 > m11 and m00 > m22:
        s = math.sqrt(1.0 + m00 - m11 - m22) * 2
        q = (0.25 * s, (m01 + m10) / s, (m02 + m20) / s, (m21 - m12) / s)
    elif m11 > m22:
        s = math.sqrt(1.0 + m11 - m00 - m22) * 2
        q = ((m01 + m10) / s, 0.25 * s, (m12 + m21) / s, (m02 - m20) / s)
    else:
        s = math.sqrt(1.0 + m22 - m00 - m11) * 2
        q = ((m02 + m20) / s, (m12 + m21) / s, 0.25 * s, (m10 - m01) / s)
    n = math.sqrt(sum(v * v for v in q))
    return tuple(v / n for v in q)


def basis(axis, normal):
    a = unit(axis)
    n = unit(sub(normal, mul(a, dot(normal, a))))
    return a, n, cross(a, n)


def frame(rest_axis, rest_normal, axis, normal):
    """The rotation that carries a limb's rest axis onto `axis` and its rest normal (as nearly as it can) onto `normal`."""
    a0, n0, t0 = basis(rest_axis, rest_normal)
    a, n, t = basis(axis, normal)
    # columns of B * B0^T
    cols = []
    for k in range(3):
        cols.append(tuple(a[i] * a0[k] + n[i] * n0[k] + t[i] * t0[k] for i in range(3)))
    return qmatrix(*cols)


def fk(pose, hips=(0.0, 0.0, 0.0)):
    """name -> (position, rotation) in model space for a pose {bone: quaternion}."""
    world = {}
    for name in BONES:
        q = pose.get(name, IDENT)
        parent = PARENT[name]
        if parent is None:
            world[name] = (add(REST[name], hips), q)
        else:
            ppos, prot = world[parent]
            world[name] = (add(ppos, qrot(prot, sub(REST[name], REST[parent]))), qmul(prot, q))
    return world


def solve_arm(side, pose, wrist, pole, palm, hand_axis, hand_palm, hips=(0.0, 0.0, 0.0)):
    """Put a wrist on `wrist` (model space) with the elbow toward `pole`, the forearm's palm side toward `palm`, and the
    hand's fingers along `hand_axis` with its palm toward `hand_palm`. Writes the three arm bones into `pose` and
    returns (elbow, wrist actually reached): a target out of reach is pulled in to arm's length."""
    arm, fore, hand = side + 'Arm', side + 'ForeArm', side + 'Hand'
    world = fk(pose, hips)
    S = world[arm][0]
    parent_rot = world[PARENT[arm]][1]
    u0, f0 = sub(REST[fore], REST[arm]), sub(REST[hand], REST[fore])
    L1, L2 = length(u0), length(f0)
    to = sub(wrist, S)
    d = min(length(to), L1 + L2 - 0.004)
    along = unit(to)
    T = add(S, mul(along, d))
    a = (L1 * L1 - L2 * L2 + d * d) / (2 * d)
    h = math.sqrt(max(L1 * L1 - a * a, 0.0))
    side_way = sub(pole, mul(along, dot(pole, along)))
    E = add(add(S, mul(along, a)), mul(unit(side_way), h))
    w_arm = frame(u0, PALM_REST, sub(E, S), palm)
    w_fore = frame(f0, PALM_REST, sub(T, E), palm)
    w_hand = frame((-1.0 if side == 'Left' else 1.0, 0.0, 0.0), PALM_REST, hand_axis, hand_palm)
    pose[arm] = qmul(qinv(parent_rot), w_arm)
    pose[fore] = qmul(qinv(w_arm), w_fore)
    pose[hand] = qmul(qinv(w_fore), w_hand)
    return E, T
