"""Luna clips: LieDown, Sleep, WakeUp (group "sleep").

    D:\\Blender\\blender.exe -b G:\\Roblox\\_local\\luna\\blend\\luna_rig2.blend -P clips_sleep.py -- <out.blend>

Every frame is posed procedurally from a flat set of scalar parameters:
  * Hips translation (hx, hy, hz) and per-bone FK angles "<Bone>.x/.y/.z" (degrees about ARMATURE axes in the
    parent's rest frame, applied X then Y then Z), for the body, neck, head, ears, scapulae and tail;
  * leg IK targets: toe position + paw direction (and, for hind legs, metatarsus direction) and a pole twist.
    A two-bone analytic solve places the elbow/stifle, so planted paws stay exactly where they are while the
    body moves. Solving at the rest parameters reproduces the rest pose (identity) exactly.
Parameters are keyed on frames and interpolated with monotone cubic (PCHIP) curves, then the solved pose is keyed
on EVERY frame (rotation_quaternion on all bones, location on Hips only). No constraints or helper objects are used.
Tail floor contact is solved against the skinned mesh itself (see needed_lifts), because the brush hangs far off
its bones. ONE LIE pose (lie()) is the end of LieDown, both ends of Sleep and the start of WakeUp.
"""
import math
import sys

sys.path.insert(0, r"G:\Roblox\MongoTV\tools\luna\anim")
import bpy
import lunalib as L
from mathutils import Matrix, Quaternion, Vector

ARM = L.ARM
PB = ARM.pose.bones
BD = ARM.data.bones
FK = ["Hips", "Spine1", "Spine2", "Chest", "Neck", "Head", "EarL", "EarR", "ScapulaL", "ScapulaR",
      "Tail1", "Tail2", "Tail3", "Tail4"]
REST = {b.name: b.matrix_local.to_3x3() for b in BD}           # armature-space rest orientation per bone
LEN = {b.name: b.length for b in BD}
FRONT = {s: (f"UpperArm{s}", f"Forearm{s}", f"FrontPaw{s}") for s in "LR"}
HIND = {s: (f"Thigh{s}", f"Shin{s}", f"Hock{s}", f"HindPaw{s}") for s in "LR"}


def upd():
    bpy.context.view_layer.update()


# ---------------------------------------------------------------- math helpers
def qarm(x, y, z):
    r = math.radians
    return Quaternion((0, 0, 1), r(z)) @ Quaternion((0, 1, 0), r(y)) @ Quaternion((1, 0, 0), r(x))


def dvec(el, az):
    """Unit vector: elevation el above horizontal, azimuth az from +Y toward +X (degrees)."""
    e, a = math.radians(el), math.radians(az)
    return Vector((math.sin(a) * math.cos(e), math.cos(a) * math.cos(e), math.sin(e)))


def el_az(v):
    v = v.normalized()
    return math.degrees(math.asin(max(-1, min(1, v.z)))), math.degrees(math.atan2(v.x, v.y))


def frame_rot(d, n):
    d = d.normalized()
    n = (n - d * n.dot(d)).normalized()
    return Matrix((n, d, n.cross(d))).transposed()


def set_fk(name, x, y, z):
    R = REST[name].to_quaternion()
    if name == "Hips":       # roll about her own long axis first, then pitch, then yaw
        r = math.radians
        q = Quaternion((0, 0, 1), r(z)) @ Quaternion((1, 0, 0), r(x)) @ Quaternion((0, 1, 0), r(y))
    else:
        q = qarm(x, y, z)
    PB[name].rotation_quaternion = R.inverted() @ q @ R


def set_world_rot(name, Q):
    upd()
    pb = PB[name]
    cur = pb.matrix.to_quaternion()
    pb.rotation_quaternion = (pb.rotation_quaternion @ cur.inverted() @ Q).normalized()


def aim(name, target):
    upd()
    pb = PB[name]
    d = (pb.tail - pb.head).normalized()
    t = (Vector(target) - pb.head).normalized()
    set_world_rot(name, d.rotation_difference(t) @ pb.matrix.to_quaternion())


def twist(name, deg):
    if abs(deg) > 1e-9:
        upd()
        pb = PB[name]
        L.rot(name, tuple((pb.tail - pb.head).normalized()), deg)


# ---------------------------------------------------------------- rest calibration
POLE_DOWN = {"UpperArmL": 0.4, "UpperArmR": 0.4, "ThighL": 0.0, "ThighR": 0.0}   # pole hint = rest bend + k * root->end
CAL = {}
REST_P = {}


def calibrate():
    """Measure the rest pose: per-chain pole/frame offsets and the parameter set that reproduces identity."""
    if ARM.animation_data:
        ARM.animation_data.action = None
    L.reset()
    upd()
    CAL.clear()
    REST_P.clear()
    REST_P.update({"hx": 0.0, "hy": 0.0, "hz": 0.0})
    for b in FK:
        for ax in "xyz":
            REST_P[f"{b}.{ax}"] = 0.0
    for chain in list(FRONT.values()) + list(HIND.values()):
        b1, b2 = chain[0], chain[1]
        A, K, C = Vector(PB[b1].head), Vector(PB[b2].head), Vector(PB[b2].tail)
        u = (C - A).normalized()
        v = (K - A) - u * (K - A).dot(u)
        n = (K - A).cross(C - K)
        par = BD[b1].parent.name
        CAL[b1] = {"pole_par": REST[par].inverted() @ (v.normalized() + u * POLE_DOWN[b1]),
                   "O1": frame_rot(K - A, n).inverted() @ REST[b1],
                   "O2": frame_rot(C - K, n).inverted() @ REST[b2]}
    for s, (ua, fa, fp) in FRONT.items():
        T, W = Vector(PB[fp].tail), Vector(PB[fp].head)
        el, az = el_az(T - W)
        REST_P.update({f"f{s}.tx": T.x, f"f{s}.ty": T.y, f"f{s}.tz": T.z, f"f{s}.pel": el, f"f{s}.paz": az,
                       f"f{s}.pole": 0.0, f"f{s}.tw": 0.0})
    for s, (th, sh, hk, hp) in HIND.items():
        T, P, K = Vector(PB[hp].tail), Vector(PB[hp].head), Vector(PB[hk].head)
        el, az = el_az(T - P)
        mel, maz = el_az(K - P)
        REST_P.update({f"h{s}.tx": T.x, f"h{s}.ty": T.y, f"h{s}.tz": T.z, f"h{s}.pel": el, f"h{s}.paz": az,
                       f"h{s}.mel": mel, f"h{s}.maz": maz, f"h{s}.pole": 0.0, f"h{s}.tw": 0.0,
                       f"h{s}.plan": 0.0})


calibrate()
WARN = []


def solve2(b1, b2, C, pole_deg, plane=None, w=0.0):
    """Two-bone solve to C. With `plane` (a point further down the limb) and weight w, the knee swings toward the plane
    through root, C and that point, so the next joint bends in its own hinge plane instead of sideways."""
    upd()
    A = Vector(PB[b1].head)
    par = PB[b1].parent
    v = par.matrix.to_3x3() @ CAL[b1]["pole_par"]
    u = (C - A).normalized()
    if abs(pole_deg) > 1e-9:
        v = Quaternion(u, math.radians(pole_deg)) @ v
    v = (v - u * v.dot(u)).normalized()
    if plane is not None and w > 1e-9:
        t = plane - A
        t -= u * t.dot(u)
        if t.length > 1e-4:
            t.normalize()
            v = Quaternion(u, w * math.atan2(u.dot(v.cross(t)), v.dot(t))) @ v
    l1, l2 = LEN[b1], LEN[b2]
    d0 = (C - A).length
    d = min(max(d0, abs(l1 - l2) + 1e-4), l1 + l2 - 1e-5)
    if d0 > l1 + l2 - 1e-5:
        WARN.append((b1, round(d0 - (l1 + l2), 4)))
    a = (l1 * l1 - l2 * l2 + d * d) / (2 * d)
    h = math.sqrt(max(l1 * l1 - a * a, 0.0))
    K = A + u * a + v * h
    Ce = A + u * d
    n = (K - A).cross(Ce - K)
    set_world_rot(b1, (frame_rot(K - A, n) @ CAL[b1]["O1"]).to_quaternion())
    set_world_rot(b2, (frame_rot(Ce - K, n) @ CAL[b1]["O2"]).to_quaternion())


def apply_params(p):
    """Pose the rig from a full parameter dict (see REST_P for the keys)."""
    L.reset()
    PB["Hips"].location = REST["Hips"].inverted() @ Vector((p["hx"], p["hy"], p["hz"]))
    for b in FK:
        set_fk(b, p[f"{b}.x"], p[f"{b}.y"], p[f"{b}.z"])
    upd()
    for s, (ua, fa, fp) in FRONT.items():
        T = Vector((p[f"f{s}.tx"], p[f"f{s}.ty"], p[f"f{s}.tz"]))
        W = T - dvec(p[f"f{s}.pel"], p[f"f{s}.paz"]) * LEN[fp]
        solve2(ua, fa, W, p[f"f{s}.pole"])
        aim(fp, T)
        twist(fp, p[f"f{s}.tw"])
    for s, (th, sh, hk, hp) in HIND.items():
        T = Vector((p[f"h{s}.tx"], p[f"h{s}.ty"], p[f"h{s}.tz"]))
        P = T - dvec(p[f"h{s}.pel"], p[f"h{s}.paz"]) * LEN[hp]
        K = P + dvec(p[f"h{s}.mel"], p[f"h{s}.maz"]) * LEN[hk]
        solve2(th, sh, K, p[f"h{s}.pole"], P, p[f"h{s}.plan"])
        aim(hk, P)
        aim(hp, T)
        twist(hp, p[f"h{s}.tw"])
    upd()


# ---------------------------------------------------------------- the LIE pose (single source of truth)
LIE_SET = {
    "hy": -0.3, "hz": -1.21,
    # rump tipped down and rolled onto her LEFT hip (right hip up, left outer thigh on the floor); the spine
    # untwists and Spine1 counter-pitches so the chest still lies level on the elbows
    "Hips.x": 12.0, "Hips.y": -46.0, "Spine1.x": -14.5, "Spine1.y": 22.0, "Spine2.y": 14.0, "Chest.y": 7.0,
    "Spine2.z": -4.0, "Chest.z": -4.0,                       # soft curve toward her right (legs + tail side)
    "Neck.x": -91.0, "Neck.z": -6.0, "Head.x": 76.0, "Head.y": 6.0, "Head.z": -5.0,   # chin down on the paws
    "EarL.x": 42.0, "EarL.z": 12.0, "EarR.x": 42.0, "EarR.z": -12.0,                 # ears relaxed back/out
    "fL.tx": -0.22, "fL.ty": 1.5, "fL.tz": 0.12, "fL.pel": -15.0, "fL.paz": 0.0,
    "fR.tx": 0.22, "fR.ty": 1.5, "fR.tz": 0.13, "fR.pel": -15.0, "fR.paz": 0.0,
    # both hind legs folded to her RIGHT, each Z-fold in its own hinge plane (poles chosen so the hock does not
    # bend sideways): the right (upper) leg lies along the flank with its hock out wide and the foot forward on the
    # floor; the left (lower) leg lies folded flat under the belly, its foot peeking out under the right knee
    "hR.tx": 0.95, "hR.ty": -0.66, "hR.tz": 0.04, "hR.pel": -8.0, "hR.paz": 12.0, "hR.mel": 6.0, "hR.maz": 186.0,
    "hR.pole": -12.0,
    "hL.tx": 0.55, "hL.ty": -0.92, "hL.tz": 0.12, "hL.pel": -3.0, "hL.paz": 11.0, "hL.mel": 12.0, "hL.maz": 190.0,
    "hL.pole": -12.0, "hL.tw": -30.0,
}
# tail lies on the floor and curls around behind the hind legs toward her right (solved once, stored as FK angles)
LIE_TAIL = [(0.1, -2.2, 0.45), (0.45, -2.45, 0.3), (0.9, -2.4, 0.28), (1.2, -2.1, 0.27)]
TAILS = ("Tail1", "Tail2", "Tail3", "Tail4")
_LIE = None


def tail_fk():
    out = {}
    for b in TAILS:
        R = REST[b].to_quaternion()
        e = (R @ PB[b].rotation_quaternion @ R.inverted()).to_euler("XYZ")
        out[f"{b}.x"], out[f"{b}.y"], out[f"{b}.z"] = (math.degrees(a) for a in e)
    return out


def lie():
    global _LIE
    if _LIE is None:
        p = dict(REST_P)
        p.update(LIE_SET)
        apply_params(p)
        for b, t in zip(TAILS, LIE_TAIL):
            aim(b, Vector(t))
        p.update(tail_fk())
        _LIE = p
    return dict(_LIE)


# ---------------------------------------------------------------- tracks
def pchip(xs, ys, x):
    """Monotone cubic through (xs, ys), zero slope at both ends and at local extrema / holds."""
    n = len(xs)
    if n == 1 or x <= xs[0]:
        return ys[0]
    if x >= xs[-1]:
        return ys[-1]
    h = [xs[i + 1] - xs[i] for i in range(n - 1)]
    d = [(ys[i + 1] - ys[i]) / h[i] for i in range(n - 1)]
    m = [0.0] * n
    for i in range(1, n - 1):
        if d[i - 1] * d[i] > 0:
            w1, w2 = 2 * h[i] + h[i - 1], h[i] + 2 * h[i - 1]
            m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])
    i = max(j for j in range(n - 1) if xs[j] <= x)
    t = (x - xs[i]) / h[i]
    t2, t3 = t * t, t * t * t
    return ((2 * t3 - 3 * t2 + 1) * ys[i] + (t3 - 2 * t2 + t) * h[i] * m[i] +
            (-2 * t3 + 3 * t2) * ys[i + 1] + (t3 - t2) * h[i] * m[i + 1])


def curve(pts, f):
    pts = sorted(dict(pts).items())
    return pchip([x for x, _ in pts], [y for _, y in pts], f)


class Clip:
    """Per-parameter key lists from start set `a` (frame 1) to end set `b` (frame n). Unset params ramp over the clip."""

    def __init__(self, a, b, n):
        self.a, self.b, self.n, self.k = a, b, n, {}

    def ramp(self, names, f0, f1):
        for nm in names:
            self.k[nm] = [(1, self.a[nm]), (f0, self.a[nm]), (f1, self.b[nm]), (self.n, self.b[nm])]

    def set(self, nm, pts):
        """Inbetween keys (frame, value); value "A"/"B" = the start/end value. Start and end keys are implied."""
        v = {"A": self.a[nm], "B": self.b[nm]}
        self.k[nm] = [(1, self.a[nm])] + [(f, v[x] if isinstance(x, str) else x) for f, x in pts] + [(self.n, self.b[nm])]

    def at(self, f):
        out = {}
        for nm in self.a:
            pts = self.k.get(nm) or [(1, self.a[nm]), (self.n, self.b[nm])]
            out[nm] = curve(unwrap(pts) if nm.endswith("az") else pts, f)
        return out


def unwrap(pts):
    """Azimuth keys take the short way round: each key moves by whole turns to within 180 deg of the one before."""
    out = []
    for x, y in sorted(dict(pts).items()):
        out.append((x, y + 360.0 * round((out[-1][1] - y) / 360.0) if out else y))
    return out


def step(c, side, f0, f1, lift):
    """Lift-and-place a paw over [f0, f1]: it eases off the floor over 3 frames, clears it before it travels and is
    down again 2 frames after it stops travelling."""
    a, b, n = c.a, c.b, c.n
    for ax in ("tx", "ty"):
        nm = f"{side}.{ax}"
        c.k[nm] = [(1, a[nm]), (f0 + 1.5, a[nm]), (f1 - 2, b[nm]), (n, b[nm])]
    nm = f"{side}.tz"
    c.k[nm] = [(1, a[nm]), (f0, a[nm]), (f0 + 3, lift), (f1 - 2.5, lift * 0.8 + b[nm] * 0.2), (f1, b[nm]), (n, b[nm])]
    for ax in ("pel", "paz", "pole", "tw"):
        nm = f"{side}.{ax}"
        c.k[nm] = [(1, a[nm]), (f0, a[nm]), (f1, b[nm]), (n, b[nm])]


# shoulder-height constraint: the extra hips pitch that puts the shoulder joints at height cz. Solved on the real FK
# chain (the spine is bent and twisted in the LIE, so a rigid-body formula would misplace the chest).
def shoulder_z(p, pitch=0.0):
    L.reset()
    PB["Hips"].location = REST["Hips"].inverted() @ Vector((p["hx"], p["hy"], p["hz"]))
    for b in ("Hips", "Spine1", "Spine2", "Chest", "ScapulaL", "ScapulaR"):
        set_fk(b, p[f"{b}.x"] + (pitch if b == "Hips" else 0.0), p[f"{b}.y"], p[f"{b}.z"])
    upd()
    return 0.5 * (PB["UpperArmL"].head.z + PB["UpperArmR"].head.z)


def pitch_for(p, cz):
    x0, x1 = 0.0, 4.0
    f0 = shoulder_z(p, x0) - cz
    if abs(f0) < 1e-7:
        return 0.0
    f1 = shoulder_z(p, x1) - cz
    for _ in range(10):                    # secant; converges in 3-4 steps
        if abs(f1) < 1e-6 or f1 == f0:
            break
        x0, x1, f0 = x1, x1 - f1 * (x1 - x0) / (f1 - f0), f1
        f1 = shoulder_z(p, x1) - cz
    return x1


def key_frame(frame, prev):
    for pb in PB:
        q = Quaternion(pb.rotation_quaternion)
        if pb.name in prev and prev[pb.name].dot(q) < 0:
            q.negate()
            pb.rotation_quaternion = q
        prev[pb.name] = q.copy()
    L.key(frame)


# The tail brush hangs up to ~0.6 stud off its bones, so floor contact is solved against the real skinned mesh.
# Root to tip, each tail bone is lifted (about the horizontal axis across it) by the smallest angle that keeps the
# vertices it dominates above TAIL_FLOOR_Z, so a tail that meets the floor bends along it instead of sinking.
# The per-frame lifts are then widened and blurred so contact eases in and out.
TAIL_FLOOR_Z = -0.02
_TV = None


def tail_min(bone):
    global _TV
    if _TV is None:
        gn = {g.index: g.name for g in L.MESH.vertex_groups}
        _TV = {b: [] for b in TAILS}
        for v in L.MESH.data.vertices:
            if v.groups:
                n = gn[max(v.groups, key=lambda g: g.weight).group]
                if n in _TV:
                    _TV[n].append(v.index)
    ev = L.MESH.evaluated_get(bpy.context.evaluated_depsgraph_get())
    me = ev.to_mesh()
    mw = ev.matrix_world
    z = min((mw @ me.vertices[i].co).z for i in _TV[bone])
    ev.to_mesh_clear()
    return z


def lift_tail(bone, deg):
    if deg > 1e-6:
        upd()
        pb = PB[bone]
        a = (pb.tail - pb.head).normalized().cross(Vector((0, 0, 1)))
        L.rot(bone, tuple(a.normalized()) if a.length > 1e-4 else (1, 0, 0), deg)


def needed_lifts():
    out = []
    for b in TAILS:
        lift = 0.0
        if tail_min(b) < TAIL_FLOOR_Z:
            q0 = PB[b].rotation_quaternion.copy()
            lo, hi = 0.0, 60.0
            for _ in range(12):
                mid = 0.5 * (lo + hi)
                PB[b].rotation_quaternion = q0
                lift_tail(b, mid)
                lo, hi = (lo, mid) if tail_min(b) >= TAIL_FLOOR_Z else (mid, hi)
            PB[b].rotation_quaternion = q0
            lift = hi
            lift_tail(b, lift)
        out.append(lift)
    return out


def smooth_lift(lam):
    n = len(lam)
    wide = [max(lam[max(0, i - 2):i + 3]) for i in range(n)]
    blur = [sum(wide[j] * (4 - abs(j - i)) for j in range(max(0, i - 3), min(n, i + 4))) /
            sum(4 - abs(j - i) for j in range(max(0, i - 3), min(n, i + 4))) for i in range(n)]
    taper = [min(1.0, i / 4.0, (n - 1 - i) / 4.0) for i in range(n)]
    return [max(l, b * t) for l, b, t in zip(lam, blur, taper)]


def bake(name, n, frame_params, loop):
    raw = []
    for f in range(1, n + 1):
        apply_params(frame_params(f))
        raw.append(needed_lifts())
    lam = list(zip(*[smooth_lift([r[k] for r in raw]) for k in range(len(TAILS))]))
    act = L.new_action(name)
    prev = {}
    for f in range(1, n + 1):
        apply_params(frame_params(f))
        for b, d in zip(TAILS, lam[f - 1]):
            lift_tail(b, d)
        key_frame(f, prev)
    L.finish(act, 1, n, loop)
    act["luna_priority"] = "Action"
    return act


TAIL_LEVEL = 0.8
ROLL = ["Hips.y", "Spine1.y", "Spine2.y", "Chest.y", "Spine2.z", "Chest.z", "hx"]
RUMP = ["Hips.x", "Spine1.x"]          # the rump tipping down onto the hip (Spine1 counter-pitches the chest level)


def breath(p, a):
    """Ribcage rise of `a` degrees that leaves the chest, elbows and head where they are: the back arches up at the
    Spine1/Spine2 joint (mid-ribs) and Spine2/Chest bend back so the chest neither lifts nor tilts."""
    p["Spine1.x"] += a
    p["Spine2.x"] -= 2.0 * a
    p["Chest.x"] += a


# ---------------------------------------------------------------- LieDown: rest -> LIE
def lie_down():
    N = 48
    A, B = dict(REST_P), lie()
    c = Clip(A, B, N)
    # rear: knees soften, the hindquarters fold down to a crouch, then the rump rolls and settles onto the left hip
    c.set("hz", [(6, -0.03), (12, -0.08), (22, -0.4), (28, -0.62), (35, B["hz"] + 0.1), (41, "B")])
    c.set("hy", [(6, -0.03), (14, -0.06), (40, "B")])
    c.ramp(RUMP, 26, 41)
    cz0, cz1 = shoulder_z(A), shoulder_z(B)
    czk = [(1, cz0), (5, cz0 - 0.02), (20, cz1 + 0.15), (28, cz1 + 0.13), (36, cz1 + 0.06), (42, cz1 + 0.02), (N, cz1)]   # front end first
    # front paws walk forward one at a time while the elbows go down; the last few cm slide in slowly
    for s, f0 in (("fL", 6), ("fR", 10)):
        y1 = B[f"{s}.ty"] - 0.07
        c.k[f"{s}.tx"] = [(1, A[f"{s}.tx"]), (f0 + 2, A[f"{s}.tx"]), (f0 + 7, B[f"{s}.tx"]), (N, B[f"{s}.tx"])]
        c.k[f"{s}.ty"] = [(1, A[f"{s}.ty"]), (f0 + 2, A[f"{s}.ty"]), (f0 + 7, y1), (f0 + 11, y1),
                          (f0 + 22, B[f"{s}.ty"]), (N, B[f"{s}.ty"])]
        c.k[f"{s}.tz"] = [(1, A[f"{s}.tz"]), (f0, A[f"{s}.tz"]), (f0 + 3.5, 0.19), (f0 + 5.5, 0.18),
                          (f0 + 8.5, B[f"{s}.tz"]), (N, B[f"{s}.tz"])]
        c.k[f"{s}.pel"] = [(1, A[f"{s}.pel"]), (f0, A[f"{s}.pel"]), (f0 + 3.5, A[f"{s}.pel"] - 10),
                           (f0 + 8, -28.0), (f0 + 20, B[f"{s}.pel"]), (N, B[f"{s}.pel"])]
    # hind paws stay planted while the hocks lay down; then, as she rolls onto her left hip, the right foot steps out
    # wide and the left foot is drawn under the belly to her right
    for s, mid in (("hR", 26.0), ("hL", 26.0)):
        c.k[f"{s}.mel"] = [(1, A[f"{s}.mel"]), (13, A[f"{s}.mel"]), (26, mid), (38, B[f"{s}.mel"]), (N, B[f"{s}.mel"])]
    for s, f0, f1, lift in (("hR", 19, 30, 0.16), ("hL", 27, 39, 0.15)):
        step(c, s, f0, f1, lift)
        c.k[f"{s}.maz"] = [(1, A[f"{s}.maz"]), (f0, A[f"{s}.maz"]), (f1, B[f"{s}.maz"]), (N, B[f"{s}.maz"])]
        c.k[f"{s}.pel"] = [(1, A[f"{s}.pel"]), (13, A[f"{s}.pel"]), (f0, -24.0), (f1, B[f"{s}.pel"]), (N, B[f"{s}.pel"])]
    c.ramp(ROLL, 24, 42)
    for s in ("hL", "hR"):          # knees stay in the plane of hip, hock and fetlock while the legs move
        c.k[f"{s}.plan"] = [(1, 0.0), (5, 1.0), (N - 6, 1.0), (N, 0.0)]
    # tail: drawn back off the floor as the hips drop, then curls around her legs (each segment a little later)
    for i, b in enumerate(TAILS):
        for ax in "xyz":
            c.ramp([f"{b}.{ax}"], 27 + 2 * i, 40 + 2 * i)
    c.set("Tail1.x", [(22, "A"), (32, -22.0), (42, "B")])
    # head: glances down at the spot, keeps looking ahead while the front bows, then settles onto the paws
    c.set("Neck.x", [(7, -12.0), (13, -6.0), (22, 6.0), (30, -35.0), (40, B["Neck.x"] + 8.0), (44, B["Neck.x"] + 2.0)])
    c.set("Head.x", [(7, 4.0), (22, 6.0), (31, 40.0), (40, 70.0), (44, 75.0)])
    c.ramp(["Neck.z", "Head.y", "Head.z"], 30, 46)
    c.ramp(["EarL.x", "EarL.z", "EarR.x", "EarR.z"], 30, 47)
    exhale = [(1, 0.0), (33, 0.0), (38, 3.0), (41, 3.0), (47, 0.0), (N, 0.0)]   # in-breath as she settles, then out

    def fp(f):
        p = c.at(f)
        pitch = pitch_for(p, curve(czk, f))
        p["Hips.x"] += pitch
        p["Tail1.x"] -= TAIL_LEVEL * pitch        # gravity: the tail keeps hanging while the body pitches
        breath(p, curve(exhale, f))
        return p
    return bake("LieDown", N, fp, False)


# ---------------------------------------------------------------- Sleep: LIE loop
def sleep():
    N = 150
    B = lie()
    zero = {k: 0.0 for k in B}
    d = Clip(zero, zero, N)
    d.set("EarR.x", [(43, 0.0), (45, -16.0), (48, 5.0), (52, -3.0), (58, 0.0)])     # one ear twitch
    d.set("EarR.z", [(43, 0.0), (45, 6.0), (50, 0.0)])
    d.set("Tail3.z", [(96, 0.0), (101, 10.0), (107, -3.0), (113, 0.0)])             # one soft tail flick
    d.set("Tail4.z", [(98, 0.0), (103, 16.0), (109, -4.0), (116, 0.0)])
    d.set("fR.tz", [(122, 0.0), (124, 0.03), (127, 0.0), (129, 0.015), (132, 0.0)])  # tiny dream twitch of a paw
    d.set("fR.pel", [(122, 0.0), (124, -7.0), (127, 0.0), (129, -3.0), (132, 0.0)])

    def fp(f):
        off = d.at(f)
        ph = (3.0 * (f - 1) / (N - 1)) % 1.0      # 3 slow breaths: in over 40%, out over 60%, exactly 0 at both ends
        b = L.ease(ph / 0.4) if ph < 0.4 else 1.0 - L.ease((ph - 0.4) / 0.6)
        p = {k: B[k] + off[k] for k in B}
        breath(p, 4.0 * b)
        p["Head.x"] += 0.4 * b
        return p
    return bake("Sleep", N, fp, True)


# ---------------------------------------------------------------- WakeUp: LIE -> rest
def wake_up():
    N = 45
    A, B = lie(), dict(REST_P)
    c = Clip(A, B, N)
    # head lifts first, ears come up
    c.set("Neck.x", [(3, A["Neck.x"] + 1.0), (10, -30.0), (20, -14.0), (30, -4.0), (38, 5.0)])
    c.set("Head.x", [(3, 75.0), (10, 22.0), (20, 6.0), (38, -3.0)])
    c.ramp(["Neck.z", "Head.y", "Head.z"], 2, 12)
    c.set("EarL.x", [(2, "A"), (8, -5.0), (15, "B")])
    c.set("EarR.x", [(2, "A"), (8, -5.0), (15, "B")])
    c.ramp(["EarL.z", "EarR.z"], 2, 10)
    # the chest rises and the front legs come back under the shoulders, one at a time
    step(c, "fL", 7, 17, 0.2)
    step(c, "fR", 11, 21, 0.2)
    cza, czr = shoulder_z(A), shoulder_z(B)
    czk = [(1, cza), (5, cza + 0.03), (12, cza + 0.22), (20, 1.25), (34, czr - 0.01), (39, czr - 0.03), (N, czr)]
    # the hips roll upright and the rump lifts off the hip; the hind legs come back under her (the lower, left one
    # first); then the hindquarters push up and the body rolls forward over the front legs; tiny stretch, settle
    c.ramp(ROLL, 9, 24)
    for s in ("hL", "hR"):          # knees stay in the plane of hip, hock and fetlock while the legs move
        c.k[f"{s}.plan"] = [(1, 0.0), (5, 1.0), (N - 6, 1.0), (N, 0.0)]
    c.ramp(RUMP, 12, 30)
    c.set("hz", [(8, A["hz"] + 0.02), (16, A["hz"] + 0.24), (22, A["hz"] + 0.42), (36, 0.01), (40, 0.0)])
    c.set("hy", [(20, -0.26), (36, 0.03), (40, 0.05)])
    for s, f0, f1, lift in (("hL", 12, 23, 0.18), ("hR", 16, 27, 0.16)):
        step(c, s, f0, f1, lift)
        c.k[f"{s}.mel"] = [(1, A[f"{s}.mel"]), (f0, A[f"{s}.mel"]), (f0 + 4, 34.0), (f1, 45.0), (36, B[f"{s}.mel"]),
                           (N, B[f"{s}.mel"])]                      # the hock lifts as the foot comes in
        c.k[f"{s}.maz"] = [(1, A[f"{s}.maz"]), (f0, A[f"{s}.maz"]), (f1, B[f"{s}.maz"]), (N, B[f"{s}.maz"])]
        c.k[f"{s}.pel"] = [(1, A[f"{s}.pel"]), (f0, A[f"{s}.pel"]), (f1, -24.0), (28, -24.0), (36, B[f"{s}.pel"]),
                           (N, B[f"{s}.pel"])]
    for i, b in enumerate(TAILS):          # tail stays curled on the floor until the hind legs are out of its way
        for ax in "xyz":
            c.ramp([f"{b}.{ax}"], 20 + 2 * i, 34 + 2 * i)
    hold = [(1, 1.0), (20, 1.0), (34, 0.0), (N, 0.0)]   # while curled, the tail root ignores the hips unrolling
    c.set("Tail1.x", [(16, "A"), (26, -26.0), (37, "B")])      # relaxed tail swings back and drags as she rises
    stretch = [(1, 0.0), (35, 0.0), (39, -1.5), (N - 1, 0.0), (N, 0.0)]    # tiny stretch through the back

    def fp(f):
        p = c.at(f)
        pitch = pitch_for(p, curve(czk, f))
        p["Hips.x"] += pitch
        p["Tail1.x"] -= TAIL_LEVEL * pitch        # gravity: the tail keeps hanging while the body pitches
        p["Spine1.x"] += curve(stretch, f)
        p["Tail1.y"] -= curve(hold, f) * (p["Hips.y"] - A["Hips.y"])
        return p
    return bake("WakeUp", N, fp, False)


def build():
    global _LIE
    _LIE = None
    calibrate()
    acts = [lie_down(), sleep(), wake_up()]
    if ARM.animation_data:
        ARM.animation_data.action = None
    L.reset()
    return acts


if __name__ == "__main__":
    import sys, bpy
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    build()
    if a:
        bpy.ops.wm.save_as_mainfile(filepath=a[0])
