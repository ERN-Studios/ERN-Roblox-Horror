"""Luna locomotion group: Idle, Walk, Run, Sniff  (Blender 5.2, headless).

    D:\\Blender\\blender.exe -b G:\\Roblox\\_local\\luna\\blend\\luna_rig2.blend -P clips_loco.py -- <out.blend>

Legs are solved analytically every frame (no constraints, no helper objects): each paw gets a ground
contact pivot C (front-bottom of the pad), a paw pitch p about that pivot, and for the hind leg a hock
pitch; the two long bones (UpperArm+Forearm, Thigh+Shin) are a two-bone IK with a pole taken from the
rest pose. Every frame is keyed (rotation on all bones, location on Hips) through lunalib.key.

Reach: the fore leg stands only 0.03 stud short of full extension, so a two-bone solve on it saturates and
snaps straight for a frame. two_bone therefore eases into a 12 deg minimum bend (soft_cap), and with
bend_min the spare joint (scapula in front, hock behind) is solved (pivot_solve) to absorb reach the elbow /
stifle cannot give. LUNA_LOCO_DEBUG=1 prints every frame where a limiter engaged.
"""
import sys
import math

sys.path.insert(0, r"G:\Roblox\MongoTV\tools\luna\anim")
import bpy
import lunalib as L
from mathutils import Vector, Matrix

ARM = L.ARM
PB = ARM.pose.bones
DB = ARM.data.bones
TAU = 2 * math.pi
X, Y, Z = (1, 0, 0), (0, 1, 0), (0, 0, 1)
SIDES = ("L", "R")
UNREACH = {}       # clip -> frames where a reach limiter could not find a pose
MISS = {}          # clip -> worst IK reach miss (studs); per-frame detail with env LUNA_LOCO_DEBUG=1
DBG = {}
VERBOSE = bool(__import__("os").environ.get("LUNA_LOCO_DEBUG"))


def upd():
    bpy.context.view_layer.update()


def rx(deg):
    return Matrix.Rotation(math.radians(deg), 3, "X")


def set_rot(n, R):
    """Give bone n the armature-space orientation R (3x3); its head stays where the parent puts it."""
    upd()
    pb = PB[n]
    base = pb.matrix.to_3x3() @ pb.rotation_quaternion.to_matrix().inverted()
    pb.rotation_quaternion = (base.inverted() @ R).to_quaternion()
    upd()


def aim(n, target):
    upd()
    pb = PB[n]
    q = (pb.tail - pb.head).normalized().rotation_difference((target - pb.head).normalized())
    set_rot(n, q.to_matrix() @ pb.matrix.to_3x3())


def knee_dist(la, lb, bend):
    """Root-to-tip distance of a two-bone chain bent `bend` degrees away from straight."""
    return math.sqrt(la * la + lb * lb + 2 * la * lb * math.cos(math.radians(bend)))


def soft_cap(x, lim, w):
    """C1 soft ceiling: identity below lim - w, then eases asymptotically into lim (no hard saturation)."""
    k = lim - w
    return x if x <= k else lim - w * math.exp(-(x - k) / w)


def two_bone(a, b, target, pole):
    upd()
    S = PB[a].head.copy()
    la, lb = DB[a].length, DB[b].length
    v = target - S
    d0 = v.length
    dmin = abs(la - lb) + 1e-3
    # never let the solver run the joint straight: ease into a 12 deg bend instead of snapping onto the clamp
    d = max(soft_cap(d0, knee_dist(la, lb, 12.0), 0.02), dmin)
    miss = abs(d0 - d)
    u = v.normalized()
    along = (la * la - lb * lb + d * d) / (2 * d)
    h = math.sqrt(max(la * la - along * along, 0.0))
    nrm = pole - u * pole.dot(u)
    nrm.normalize()
    aim(a, S + u * along + nrm * h)
    aim(b, S + u * d)
    return miss


def pivot_solve(P, v, W, dist, pref):
    """Angle a (deg) about armature +X through P such that |P + Rx(a) v - W| = dist; the root nearest `pref`.
    Returns (a, reachable). Out of reach -> the closest possible angle."""
    w = W - P
    rho, wr = math.hypot(v.y, v.z), math.hypot(w.y, w.z)
    c = (rho * rho + wr * wr + (v.x - w.x) ** 2 - dist * dist) / (2 * rho * wr)
    ok = abs(c) <= 1.0
    dl = math.acos(max(-1.0, min(1.0, c)))
    th0, phi = math.atan2(v.z, v.y), math.atan2(w.z, w.y)
    best = None
    for th in (phi + dl, phi - dl):
        a = math.degrees(th - th0)
        a = pref + (a - pref + 180.0) % 360.0 - 180.0
        if best is None or abs(a - pref) < abs(best - pref):
            best = a
    return best, ok


# ---------------------------------------------------------------- rest-pose leg data
def _pole_local(upper, lower, parent):
    S, K, T = DB[upper].head_local, DB[upper].tail_local, DB[lower].tail_local
    u = (T - S).normalized()
    n = (K - S) - u * (K - S).dot(u)
    return DB[parent].matrix_local.to_3x3().inverted() @ n.normalized()


FRONT, HIND = {}, {}
for s in SIDES:
    tail = DB[f"FrontPaw{s}"].tail_local
    C = Vector((tail.x, tail.y + 0.10, 0.0))
    FRONT[s] = dict(C=C, wrist=DB[f"FrontPaw{s}"].head_local - C, R=DB[f"FrontPaw{s}"].matrix_local.to_3x3(),
                    pole=_pole_local(f"UpperArm{s}", f"Forearm{s}", f"Scapula{s}"),
                    scap0=DB[f"Scapula{s}"].head_local.copy())
    tail = DB[f"HindPaw{s}"].tail_local
    C = Vector((tail.x, tail.y, 0.0))
    HIND[s] = dict(C=C, ankle=DB[f"HindPaw{s}"].head_local - C, R=DB[f"HindPaw{s}"].matrix_local.to_3x3(),
                   Rh=DB[f"Hock{s}"].matrix_local.to_3x3(),
                   hock=DB[f"Hock{s}"].tail_local - DB[f"Hock{s}"].head_local,
                   pole=_pole_local(f"Thigh{s}", f"Shin{s}", "Hips"),
                   hip0=DB[f"Thigh{s}"].head_local.copy())


def _leg_angle(top, C):
    """Sagittal angle of the line top->C from straight down, + = paw forward (degrees)."""
    return math.degrees(math.atan2(C.y - top.y, top.z - C.z))


def _note(tag, df, dt, ok):
    if VERBOSE and (dt < df - 1e-4 or not ok):
        print("LIMIT", DBG.get("clip"), DBG.get("f"), tag, "d", round(df, 3), "->", round(dt, 3), "" if ok else "UNREACHABLE")
    if not ok:
        UNREACH[DBG.get("clip")] = UNREACH.get(DBG.get("clip"), 0) + 1


def solve_front(s, C, p=0.0, scap_k=0.35, scap_extra=0.0, bend_min=None, knee=0.03):
    """Fore leg. The scapula follows the leg (scap_k); with bend_min the scapula also takes up any reach the
    elbow cannot give, so the elbow eases into `bend_min` instead of being pulled straight (the rig's fore leg
    stands only 0.03 stud short of full extension)."""
    F = FRONT[s]
    sn = f"Scapula{s}"
    upd()
    ang = _leg_angle(PB[sn].head, C) - _leg_angle(F["scap0"], F["C"])
    sc = scap_k * ang + scap_extra
    W = C + rx(p) @ F["wrist"]
    P, v = PB[sn].head.copy(), PB[sn].tail - PB[sn].head
    la, lb = DB[f"UpperArm{s}"].length, DB[f"Forearm{s}"].length
    if bend_min is not None:
        df = (P + rx(sc) @ v - W).length
        dt = soft_cap(df, knee_dist(la, lb, bend_min), knee)
        if dt < df - 1e-6:
            sc, ok = pivot_solve(P, v, W, dt, sc)
            _note("F" + s, df, dt, ok)
    if abs(sc) > 1e-6:
        L.rot(sn, X, sc)
    pole = PB[sn].matrix.to_3x3() @ F["pole"]
    miss = two_bone(f"UpperArm{s}", f"Forearm{s}", W, pole)
    set_rot(f"FrontPaw{s}", rx(p) @ F["R"])
    return miss


def solve_hind(s, C, p=0.0, hock_k=0.8, hock_extra=0.0, bend_min=None, knee=0.04):
    """Hind leg. With bend_min the hock angle (stifle and hock work together in a dog) takes up any reach the
    stifle cannot give, so the stifle never runs straight."""
    Hd = HIND[s]
    upd()
    ang = _leg_angle(PB[f"Thigh{s}"].head, C) - _leg_angle(Hd["hip0"], Hd["C"])
    al = hock_k * ang + hock_extra
    A = C + rx(p) @ Hd["ankle"]
    if bend_min is not None:
        Hp = PB[f"Thigh{s}"].head.copy()
        df = (A - rx(al) @ Hd["hock"] - Hp).length
        dt = soft_cap(df, knee_dist(DB[f"Thigh{s}"].length, DB[f"Shin{s}"].length, bend_min), knee)
        if dt < df - 1e-6:
            al, ok = pivot_solve(A, -Hd["hock"], Hp, dt, al)
            _note("H" + s, df, dt, ok)
    top = A - rx(al) @ Hd["hock"]
    pole = PB["Hips"].matrix.to_3x3() @ Hd["pole"]
    miss = two_bone(f"Thigh{s}", f"Shin{s}", top, pole)
    set_rot(f"Hock{s}", rx(al) @ Hd["Rh"])
    set_rot(f"HindPaw{s}", rx(p) @ Hd["R"])
    return miss


FRONT_MEAN = sum(FRONT[s]["C"].y for s in SIDES) / 2
HIND_MEAN = sum(HIND[s]["C"].y for s in SIDES) / 2


# ---------------------------------------------------------------- curves
def smooth_keys(pts, x):
    """Pose-to-pose: smoothstep between (x, value) keys (eases in and out of every key). Clamped ends."""
    if x <= pts[0][0]:
        return pts[0][1]
    for (x0, v0), (x1, v1) in zip(pts, pts[1:]):
        if x <= x1:
            return v0 + (v1 - v0) * L.ease((x - x0) / (x1 - x0))
    return pts[-1][1]


def cyc_keys(pts, ph):
    """Periodic smoothstep keys over phase 0..1 (pts sorted, first x may be > 0)."""
    ph %= 1.0
    ext = [(pts[-1][0] - 1.0, pts[-1][1])] + list(pts) + [(pts[0][0] + 1.0, pts[0][1])]
    return smooth_keys(ext, ph)


def hermite(p0, p1, m0, m1, u):
    u2, u3 = u * u, u * u * u
    return (2 * u3 - 3 * u2 + 1) * p0 + (u3 - 2 * u2 + u) * m0 + (-2 * u3 + 3 * u2) * p1 + (u3 - u2) * m1


def lag(x, b):
    """sin(x) whose peaks arrive later as b grows, still exactly 0 at x = 0 and 2*pi (follow-through for chains)."""
    return math.sin(x) - b * math.sin(2 * x)


# ---------------------------------------------------------------- framing
class Clip:
    def __init__(self, name, frames, loop, priority, ref_speed=None):
        self.name, self.frames, self.loop = name, frames, loop
        self.act = L.new_action(name)
        self.act["luna_priority"] = priority
        if ref_speed is not None:
            self.act["luna_ref_speed"] = float(ref_speed)
        self.prev = {}
        MISS[name] = 0.0
        DBG["clip"] = name

    def key(self, f):
        for pb in PB:
            q = pb.rotation_quaternion
            pq = self.prev.get(pb.name)
            if pq is not None and q.dot(pq) < 0:
                pb.rotation_quaternion = -q
            self.prev[pb.name] = pb.rotation_quaternion.copy()
        L.key(f)

    def done(self):
        L.finish(self.act, 1, self.frames, self.loop)


def pose(hips=(0, 0, 0), ops=(), front=None, hind=None, clip=None):
    """front/hind: {side: dict(C=Vector, p=deg, ...extra kwargs)}; None = planted at rest."""
    L.reset()
    if any(hips):
        L.move_hips(*hips)
    for b, ax, d in ops:
        if abs(d) > 1e-7:
            L.rot(b, ax, d)
    miss = 0.0
    for s in SIDES:
        a = dict(C=FRONT[s]["C"]) if front is None else front[s]
        mm = solve_front(s, **a)
        if mm > 1e-3 and clip and VERBOSE:
            print("MISS", clip, DBG.get("f"), "F" + s, round(DBG.get("F" + s, -1), 2), round(mm, 3))
        miss = max(miss, mm)
    for s in SIDES:
        a = dict(C=HIND[s]["C"]) if hind is None else hind[s]
        mm = solve_hind(s, **a)
        if mm > 1e-3 and clip and VERBOSE:
            print("MISS", clip, DBG.get("f"), "H" + s, round(DBG.get("H" + s, -1), 2), round(mm, 3))
        miss = max(miss, mm)
    if clip:
        MISS[clip] = max(MISS[clip], miss)
    return miss


# ================================================================ IDLE
IDLE = dict(breath=3.5, hipbob=0.0)


def build_idle():
    N = 120
    c = Clip("Idle", N, True, "Idle")
    P = N - 1
    look = [(1, 0), (14, 0), (38, 1), (52, 1), (74, -0.8), (86, -0.8), (106, 0), (120, 0)]   # +1 = her left
    tilt = [(1, 0), (20, 0), (42, 1), (56, 0.4), (78, -0.6), (90, -0.4), (106, 0), (120, 0)]
    for f in range(1, N + 1):
        if f in (1, N):
            L.reset(); c.key(f); continue
        t = (f - 1) / P
        x = TAU * 2 * t                                  # two slow breaths per loop
        br = math.sin(x - 0.35 * math.sin(x))            # quicker inhale, longer exhale (still 0 at both ends)
        lk = smooth_keys(look, f)
        tl = smooth_keys(tilt, f)
        # one ear flick: right ear snaps back/out around f60, settles with a small overshoot
        fl = smooth_keys([(1, 0), (58, 0), (61, 1), (65, -0.25), (70, 0.1), (75, 0), (120, 0)], f)
        sway = math.sin(TAU * t)
        ops = [
            # breathing: the ribcage behind the shoulders rises (+a, -2a, +a leaves the chest, scapulae and
            # neck where they were, so the near-straight fore legs keep their reach)
            ("Spine1", X, IDLE["breath"] * br), ("Spine2", X, -2 * IDLE["breath"] * br), ("Chest", X, IDLE["breath"] * br),
            ("Neck", Z, 11 * lk), ("Head", Z, 13 * lk), ("Head", Y, -4 * tl),
            ("Neck", X, -1.5 * abs(lk)), ("Head", X, 0.6 * br),
            ("EarR", X, 28 * fl - 4 * abs(lk)), ("EarR", Y, 14 * fl), ("EarL", X, 3 * max(fl, 0) - 4 * abs(lk)),
            ("Tail1", Z, 4 * lag(TAU * t, 0.0)), ("Tail2", Z, 6 * lag(TAU * t, 0.12)),
            ("Tail3", Z, 8 * lag(TAU * t, 0.22)), ("Tail4", Z, 9 * lag(TAU * t, 0.3)),
            ("Tail1", X, 1.5 * math.sin(TAU * 2 * t)),
        ]
        pose(hips=(0.012 * sway, 0, IDLE["hipbob"] * br), ops=ops, clip="Idle")
        c.key(f)
    c.done()


# ================================================================ WALK
def gait_contact(base, q, duty, D, yoff, zkeys, match=1.0, match0=None, ua=None, ub=None):
    """Contact pivot for leg-phase q (0 = touchdown). Stance: slides back at constant speed. Swing: Hermite
    with ground-speed-matched end tangents (no scuff at lift-off / touchdown); height from zkeys over u.
    With ua/ub the paw keeps exact ground speed for the first ua and the last 1-ub of the swing, so it leaves
    the ground and sets down again while travelling with it (no slide while it is still close to the floor)."""
    yc = base.y + yoff
    if q < duty:
        return Vector((base.x, yc + D / 2 - D * q / duty, 0.0)), q / duty
    u = (q - duty) / (1 - duty)
    m = -D * (1 - duty) / duty
    u1, z1 = zkeys[1]
    # quarter-sine pick-up: the paw leaves the ground at full speed, then pose-to-pose keys for the rest
    z = z1 * math.sin(0.5 * math.pi * u / u1) if u < u1 else smooth_keys(zkeys, u)
    y0, y1 = yc - D / 2, yc + D / 2
    if ua is None:
        y = hermite(y0, y1, m * (match if match0 is None else match0), m * match, u)
    elif u < ua:
        y = y0 + m * u
    elif u > ub:
        y = y1 + m * (u - 1)
    else:
        y = hermite(y0 + m * ua, y1 + m * (ub - 1), m * (ub - ua), m * (ub - ua), (u - ua) / (ub - ua))
    return Vector((base.x, y, z)), 1 + u


WALK = dict(P=30, duty=0.62, D=1.9, drop=-0.03, foff=-0.25, hoff=-0.12, scap_k=0.6, fbend=20.0, fknee=0.03, hbend=25.0,
            flift=0.13, fcarpus=-55.0, hlift=0.18, tail_lift=-20.0, tail_bias=-7.0, tail_ph=0.37, bobf=0.022, bobh=0.022,
            fpeel=0.5, hpeel=0.5,
            ua=0.08, ub=0.88, fset=0.075, hset=0.09)


def build_walk(**kw):
    W = dict(WALK, **kw)
    P, duty, D = W["P"], W["duty"], W["D"]
    v = D * 30.0 / (duty * P)
    N = P + 1
    c = Clip("Walk", N, True, "Movement", ref_speed=round(v, 4))
    TD = {"HL": 0.0, "FL": 0.25, "HR": 0.5, "FR": 0.75}          # lateral sequence LH, LF, RH, RF
    # paw pitch over leg phase (0 = touchdown): flat in stance, heel peels before lift-off, carpus folds in swing
    sw = lambda u: duty + u * (1 - duty)
    # no key AT lift-off: the heel keeps peeling through it (a key there would pause the paw and kick the leg straight)
    fp = [(0.0, 0.0), (W["fpeel"] * duty, 0.0), (sw(0.3), W["fcarpus"]), (sw(0.7), -15.0), (sw(0.9), 0.0)]
    hp = [(0.0, 0.0), (W["hpeel"] * duty, 0.0), (sw(0.35), -42.0), (sw(0.78), -6.0), (sw(0.92), 0.0)]
    fl, hl = W["flift"], W["hlift"]
    ua, ub = W["ua"], W["ub"]
    fz = [(0, 0), (0.25, fl), (0.55, 0.85 * fl), (ub, W["fset"]), (1, 0)]
    hz = [(0, 0), (0.3, hl), (0.6, 0.8 * hl), (ub, W["hset"]), (1, 0)]
    hkx = [(0, 0), (0.3, -24.0), (0.65, -8.0), (1, 0)]
    for f in range(1, N + 1):
        ph = ((f - 1) % P) / P
        DBG["f"] = f
        front, hind = {}, {}
        for s in SIDES:
            q = (ph - TD["F" + s]) % 1.0
            C, w = gait_contact(FRONT[s]["C"], q, duty, D, W["foff"] + (FRONT_MEAN - FRONT[s]["C"].y), fz, ua=ua, ub=ub)
            front[s] = dict(C=C, p=cyc_keys(fp, q), scap_k=W["scap_k"], bend_min=W["fbend"], knee=W["fknee"])
            q = (ph - TD["H" + s]) % 1.0
            C, w = gait_contact(HIND[s]["C"], q, duty, D, W["hoff"] + (HIND_MEAN - HIND[s]["C"].y), hz, ua=ua, ub=ub)
            hind[s] = dict(C=C, p=cyc_keys(hp, q), hock_k=0.9, hock_extra=smooth_keys(hkx, w - 1) if w > 1 else 0.0,
                           bend_min=W["hbend"])
        bob_h = W["bobh"] * math.cos(2 * TAU * (ph - 0.31))
        bob_f = W["bobf"] * math.cos(2 * TAU * (ph - 0.56))
        pitch = math.degrees((bob_f - bob_h) / 2.2)
        yaw_h = -3.0 * math.cos(TAU * ph)
        yaw_c = -3.0 * math.cos(TAU * (ph - 0.25))
        dyaw = yaw_c - yaw_h
        nod = math.cos(2 * TAU * (ph - 0.34))
        # tail: carried a little higher than at rest and biased to her left, clear of the right hock; the sway
        # puts it on the side of the hind leg that is swinging forward, away from the one pushing back
        tl, tp = W["tail_lift"], W["tail_ph"]
        ops = [
            ("Hips", Z, yaw_h), ("Hips", Y, 1.4 * math.cos(TAU * (ph - 0.31))), ("Hips", X, pitch - 2.0),
            ("Spine1", Z, 0.3 * dyaw), ("Spine2", Z, 0.4 * dyaw), ("Chest", Z, 0.3 * dyaw),
            ("Chest", Y, -0.8 * math.cos(TAU * (ph - 0.56))),
            ("Neck", X, -7.0 - 2.5 * nod), ("Neck", Z, -0.6 * yaw_c), ("Head", Z, -0.3 * yaw_c),
            ("Head", X, 4.0 + 1.0 * nod),
            ("EarL", X, 3 + 2.5 * math.cos(2 * TAU * (ph - 0.46))), ("EarR", X, 3 + 2.5 * math.cos(2 * TAU * (ph - 0.48))),
            ("Tail1", X, tl + 1.5 * math.cos(2 * TAU * (ph - 0.40))), ("Tail2", X, 0.3 * tl),
            ("Tail1", Z, W["tail_bias"] + 4 * math.sin(TAU * (ph - tp))), ("Tail2", Z, 6 * math.sin(TAU * (ph - tp - 0.07))),
            ("Tail3", Z, 8 * math.sin(TAU * (ph - tp - 0.14))), ("Tail4", Z, 10 * math.sin(TAU * (ph - tp - 0.21))),
        ]
        hx = -0.018 * math.cos(TAU * (ph - 0.31))
        pose(hips=(hx, 0, W["drop"] + bob_h), ops=ops, front=front, hind=hind, clip="Walk")
        c.key(f)
    c.done()


# ================================================================ SNIFF
def bump(x, c, w):
    """Smooth 0..1..0 bump of half-width w centred on c (cos window)."""
    d = abs(x - c)
    return 0.5 * (1 + math.cos(math.pi * d / w)) if d < w else 0.0


def cyc_bump(ph, c, w):
    return max(bump(ph, c, w), bump(ph, c - 1.0, w), bump(ph, c + 1.0, w))


# the drop is carried by the chest pitch (and a crouch of the fore legs), not by folding the neck under: a neck
# that turns more than ~10 deg below the chest line crushes the throat skin (99 inverted triangles at -27 deg)
SNIFF = dict(hp=-8.0, s1=-2.0, s2=-6.0, ch=-18.0, ty=1.6, tz=0.40, drop=-0.06, scap=0.6, pole=(0, 1, 1))


def build_sniff(**kw):
    S = dict(SNIFF, **kw)
    N = 60
    P = N - 1
    c = Clip("Sniff", N, True, "Idle")
    # three-sniff bursts (frames), the nose lifting a touch on each inhale
    bursts = [12, 17, 22, 40, 44.5, 49]
    for f in range(1, N + 1):
        DBG["f"] = f
        t = (f - 1) / P
        sweep = math.sin(TAU * t)                                   # nose drifts to her right, then left
        sn = sum(bump(f, b, 2.6) for b in bursts)
        br = math.sin(TAU * 2 * t)
        tw = 0.5 * math.sin(TAU * 3 * t)
        T = Vector((0.13 * sweep, S["ty"] + 0.04 * math.sin(TAU * t + 1.2), S["tz"] + 0.035 * sn + 0.01 * br))
        hp, s1, s2, ch = S["hp"], S["s1"], S["s2"] + 0.4 * br, S["ch"] - 0.6 * br
        ops = [("Hips", X, hp), ("Hips", Z, -1.0 * sweep), ("Hips", Y, 0.8 * sweep),
               ("Spine1", X, s1), ("Spine2", X, s2), ("Chest", X, ch),
               ("Spine2", Z, -1.5 * sweep), ("Chest", Z, -2.5 * sweep),
               ("Tail1", X, -3.0), ("Tail1", Z, 5 * math.sin(TAU * 2 * t)), ("Tail2", Z, 7 * math.sin(TAU * 2 * t - 0.5)),
               ("Tail3", Z, 9 * math.sin(TAU * 2 * t - 1.0)), ("Tail4", Z, 11 * math.sin(TAU * 2 * t - 1.5))]
        tot = hp + s1 + s2 + ch
        fr = {sd: dict(C=FRONT[sd]["C"], scap_extra=-S["scap"] * tot) for sd in SIDES}
        pose(hips=(0.01 * sweep, 0, S["drop"]), ops=ops, front=fr, clip="Sniff")
        MISS["Sniff"] = max(MISS["Sniff"], two_bone("Neck", "Head", T, Vector(S["pole"])))
        L.rot("Head", X, 4.0 * sn)                                  # nose tips up on each sniff
        L.rot("EarL", X, 12 - 4 * sn + 3 * tw)                       # ears relax back while the head is down
        L.rot("EarR", X, 12 - 4 * sn - 3 * tw)
        if VERBOSE and f in (1, 30):
            upd()
            def ang(n):
                v = PB[n].tail - PB[n].head
                return round(math.degrees(math.atan2(v.z, v.y)), 1)
            print("SNIFFPOSE", f, {n: ang(n) for n in ("Chest", "Neck", "Head", "Spine2")}, "neckbase z",
                  round(PB["Neck"].head.z, 3), "nose", tuple(round(x, 3) for x in PB["Head"].tail))
        c.key(f)
    c.done()


# ================================================================ RUN (rotary gallop)
RUN = dict(foff=-0.3, hoff=-0.2, drop=-0.12, hbend=30.0, hknee=0.1, flo=-65.0, scap_k=0.8, flift=0.34, fcarpus=-100.0)


def build_run(P=14, v=16.0, duty_f=0.26, duty_h=0.30, **kw):
    R = dict(RUN, **kw)
    RUN_FOFF, RUN_HOFF, RUN_DROP = R["foff"], R["hoff"], R["drop"]
    N = P + 1
    c = Clip("Run", N, True, "Movement", ref_speed=v)
    TD = {"HL": 0.0, "HR": 0.10, "FR": 0.42, "FL": 0.52}   # rotary: LH, RH, RF, LF, then gathered suspension
    Df, Dh = v * duty_f * P / 30.0, v * duty_h * P / 30.0
    swf = lambda u: duty_f + u * (1 - duty_f)
    swh = lambda u: duty_h + u * (1 - duty_h)
    fp = [(0.0, 0.0), (0.45 * duty_f, 0.0), (duty_f, R["flo"]), (swf(0.35), R["fcarpus"]), (swf(0.75), -15.0), (swf(0.92), 0.0)]
    hp = [(0.0, 0.0), (0.45 * duty_h, 0.0), (duty_h, -40.0), (swh(0.35), -60.0), (swh(0.78), -8.0), (swh(0.92), 0.0)]
    fl = R["flift"]
    fz = [(0, 0), (0.22, fl), (0.5, 0.81 * fl), (0.8, 0.48 * fl), (0.93, 0.33 * fl), (1, 0)]
    hz = [(0, 0), (0.25, 0.36), (0.6, 0.30), (0.93, 0.17), (1, 0)]
    hkx = [(0, 0), (0.3, -30.0), (0.7, 6.0), (1, 0)]
    for f in range(1, N + 1):
        ph = ((f - 1) % P) / P
        DBG["f"] = f
        front, hind = {}, {}
        for s in SIDES:
            q = (ph - TD["F" + s]) % 1.0
            DBG["F" + s] = q
            C, w = gait_contact(FRONT[s]["C"], q, duty_f, Df, RUN_FOFF + (FRONT_MEAN - FRONT[s]["C"].y), fz, match=1.0, match0=0.5)
            C.x *= 0.85                                             # fore paws track a little under the chest
            front[s] = dict(C=C, p=cyc_keys(fp, q), scap_k=R["scap_k"])
            q = (ph - TD["H" + s]) % 1.0
            DBG["H" + s] = q
            C, w = gait_contact(HIND[s]["C"], q, duty_h, Dh, RUN_HOFF + (HIND_MEAN - HIND[s]["C"].y), hz, match=0.85, match0=0.5)
            # hind paws run a wider track and swing forward outside the fore legs
            C.x += math.copysign(smooth_keys([(0, 0.06), (0.3, 0.17), (0.85, 0.17), (1, 0.06)], w - 1) if w > 1 else 0.06, C.x)
            hind[s] = dict(C=C, p=cyc_keys(hp, q), hock_k=0.9, hock_extra=smooth_keys(hkx, w - 1) if w > 1 else 0.0,
                           bend_min=R["hbend"], knee=R["hknee"])
        lift = 0.05 * cyc_bump(ph, 0.9, 0.14)                      # ballistic rise in the gathered suspension
        zr = -0.09 * math.cos(TAU * (ph - 0.20)) + lift
        zf = -0.09 * math.cos(TAU * (ph - 0.63)) + lift
        pitch = math.degrees((zf - zr) / 2.2)
        flex = math.cos(TAU * (ph - 0.92))
        F = 12.0
        chest_pitch = pitch - 2.0                                   # world pitch change of the chest
        ops = [
            ("Hips", X, pitch - 2.0 + F * flex),
            ("Spine1", X, -0.4 * F * flex), ("Spine2", X, -0.35 * F * flex), ("Chest", X, -0.25 * F * flex),
            ("Hips", Z, 2.0 * math.sin(TAU * (ph - 0.05))), ("Chest", Z, -2.0 * math.sin(TAU * (ph - 0.5))),
            ("Neck", X, -12.0 - 0.7 * chest_pitch), ("Head", X, 7.0 - 0.2 * chest_pitch + 2.0 * math.cos(TAU * (ph - 0.7))),
            ("EarL", X, 20 + 4 * math.cos(TAU * (ph - 0.75))), ("EarR", X, 20 + 4 * math.cos(TAU * (ph - 0.78))),
            ("EarL", Y, -6), ("EarR", Y, 6),
            ("Tail1", X, -38 + 6 * math.sin(TAU * (ph - 0.15))), ("Tail2", X, -12 + 5 * math.sin(TAU * (ph - 0.25))),
            ("Tail3", X, -6 + 5 * math.sin(TAU * (ph - 0.35))), ("Tail4", X, -4 + 5 * math.sin(TAU * (ph - 0.45))),
            ("Tail2", Z, 3 * math.sin(TAU * (ph - 0.3))), ("Tail4", Z, 4 * math.sin(TAU * (ph - 0.45))),
        ]
        pose(hips=(0, 0, RUN_DROP + zr), ops=ops, front=front, hind=hind, clip="Run")
        c.key(f)
    c.done()


def build():
    L.reset()
    build_idle()
    build_walk()
    build_sniff()
    build_run()
    ARM.animation_data.action = None
    L.reset()


if __name__ == "__main__":
    import sys, bpy
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    build()
    print("LOCO_MISS", MISS)
    if a:
        bpy.ops.wm.save_as_mainfile(filepath=a[0])
