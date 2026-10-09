"""Luna clips: RollOver, BellyUp, BellyRub, RollUp (group "belly").

    D:\\Blender\\blender.exe -b G:\\Roblox\\_local\\luna\\blend\\luna_rig2.blend -P clips_belly.py -- <out.blend>

She walks up to a player, rolls onto her back for a belly rub (the owner's photos refs/3.jpg and refs/4.jpg) and
gets up again. The framework is copied from clips_sleep.py (FK angles + analytic two-bone leg IK + PCHIP tracks,
a key on every frame, no constraints, no helper objects) and extended for a dog that turns over:
  * each leg is in one of two modes (sp): sp = 0 is world-space IK (a planted paw stays exactly where it is while
    the body moves; the same parameters as clips_sleep), sp = 1 is FK relative to the body (a paw in the air moves
    with her; the leg bones' local rotations are interpolated as rotation vectors, so a leg folding during the roll
    never flips its elbow or twists its paw). switch() hands a leg from one mode to the other at a frame, reading the
    current pose so nothing jumps; lift_off() and land() wrap it for a paw leaving and reaching the floor;
  * a body floor solve: with weight "fpitch" the hips pitch so the chest and pelvis touch together, with weight
    "floor" hz puts the lowest trunk vertex on Z = 0 (she lies on her side or back instead of floating or sinking);
    with weight "headrest" the neck settles the head onto the floor;
  * the tail and ears can be aimed at world directions (they lie on the floor and stay there while the body moves
    under them); the brush of the tail is a one-sided flag of hair and is rolled flat with "tailtw";
  * mesh-based floor lifts (as in clips_sleep) for the airborne legs, the neck, the ears and the tail: each bone is
    turned up by the smallest angle that keeps the vertices it carries above the floor, smoothed over the frames
    (cyclically in the loops, so the seam stays exact).
ONE BELLY pose (belly()) is the end of RollOver, both ends of BellyUp and BellyRub and the start of RollUp. The
photos show her legs falling to her right; this is the mirror image, so the kicking RIGHT hind leg is the free upper
one and the roll goes over her left side, the side she lies down on in clips_sleep.

Second fix pass (2026-10-05, after the second review):
  * BELLY's forelegs bend at the wrist on its hinge only (hinge_paw, about the paw's local -X, the way a carpus
    bends): the forearms rise off the chest leaning back over it, the elbows a little bent and out, and the paws flop
    over toward her belly with the fur up and the pads toward the chest. The upper arms sit near their standing angle,
    so the armpits are no longer stretched. Every foreleg shape in the rolls bends its paw the same way, so between
    them and BELLY the legs swing at the shoulder and the paws only ride along.
  * RollOver's head no longer rides the flop: its roll eases on its own (HEAD_TURN) and trails the chest's, and its
    height is keyed (headc, solved by the neck) from where it is at HEAD_FROM down to its rest on the floor at
    HEAD_REST, where the floor settle takes over. The upper (right) foreleg folds in at her side (FOLD_R) while she
    rolls over it, clear of the head she holds up.
  * RollUp's ears turn off the floor as one steady turn of their whole orientation (TURN_Q); the forelegs fold in
    against the chest as she rolls off her back (TUCK_F), and the upper one lands first, from wider out and with its
    elbow's pole held a little out (FR_POLE_LAND), so its forearm passes outside the lower leg's elbow.
"""
import math
import sys

sys.path.insert(0, r"G:\Roblox\MongoTV\tools\luna\anim")
import bpy
import numpy as np
import lunalib as L
from mathutils import Matrix, Quaternion, Vector

ARM = L.ARM
PB = ARM.pose.bones
BD = ARM.data.bones
FK = ["Hips", "Spine1", "Spine2", "Chest", "Neck", "Head", "EarL", "EarR", "ScapulaL", "ScapulaR",
      "Tail1", "Tail2", "Tail3", "Tail4"]
REST = {b.name: b.matrix_local.to_3x3() for b in BD}
LEN = {b.name: b.length for b in BD}
FRONT = {s: (f"UpperArm{s}", f"Forearm{s}", f"FrontPaw{s}") for s in "LR"}
HIND = {s: (f"Thigh{s}", f"Shin{s}", f"Hock{s}", f"HindPaw{s}") for s in "LR"}
LEGS = ("fL", "fR", "hL", "hR")
LEG_BONES = {"fL": FRONT["L"], "fR": FRONT["R"], "hL": HIND["L"], "hR": HIND["R"]}
TAILS = ("Tail1", "Tail2", "Tail3", "Tail4")


def upd():
    bpy.context.view_layer.update()


# ---------------------------------------------------------------- math helpers (from clips_sleep)
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


def qlog(q):
    """Rotation vector (degrees) of a quaternion, angle <= 180."""
    q = q.normalized()
    if q.w < 0:
        q = -q
    axis, ang = q.to_axis_angle()
    return Vector(axis) * math.degrees(ang)


def qexp(v):
    v = Vector(v)
    ang = v.length
    return Quaternion() if ang < 1e-9 else Quaternion(v / ang, math.radians(ang))


def set_fk(name, x, y, z):
    R = REST[name].to_quaternion()
    if name == "Hips":       # roll about her own long axis first, then pitch, then yaw (world axes)
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
POLE_DOWN = {"UpperArmL": 0.4, "UpperArmR": 0.4, "ThighL": 0.0, "ThighR": 0.0}
CAL = {}
REST_P = {}
GLOBAL = {"hx": 0.0, "hy": 0.0, "hz": 0.0, "floor": 0.0, "fpitch": 0.0, "headrest": 0.0, "tailw": 0.0, "earw": 0.0,
          "tailtw": 0.0, "floorz": 0.0, "headc": 0.0, "headcw": 0.0}
# bones that can be aimed at WORLD directions "<bone>.wel/.waz" (elevation, azimuth), blended over their FK pose by
# the weight of their group: a tail or ear lying on the floor stays where it lies while the body moves under it
AIMED = {"Tail1": "tailw", "Tail2": "tailw", "Tail3": "tailw", "Tail4": "tailw", "EarL": "earw", "EarR": "earw"}
WORLD_KEYS = {"f": ("tx", "ty", "tz", "pel", "paz"), "h": ("tx", "ty", "tz", "pel", "paz", "mel", "maz")}


def world_keys(s):
    return [f"{s}.{nm}" for nm in WORLD_KEYS[s[0]]]


def fk_keys(s):
    return [f"{b}.r{a}" for b in LEG_BONES[s] for a in "xyz"]


def calibrate():
    """Measure the rest pose: per-chain pole/frame offsets and the parameter set that reproduces identity."""
    if ARM.animation_data:
        ARM.animation_data.action = None
    L.reset()
    upd()
    CAL.clear()
    REST_P.clear()
    REST_P.update(GLOBAL)
    for b in FK:
        for ax in "xyz":
            REST_P[f"{b}.{ax}"] = 0.0
    for b in AIMED:
        REST_P[f"{b}.wel"], REST_P[f"{b}.waz"] = el_az(PB[b].tail - PB[b].head)
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
    for s in LEGS:
        REST_P.update(world_values(s, *toe_state(s)))
        REST_P.update({f"{s}.pole": 0.0, f"{s}.tw": 0.0, f"{s}.plan": 0.0, f"{s}.sp": 0.0})
        for b in LEG_BONES[s]:
            REST_P.update({f"{b}.rx": 0.0, f"{b}.ry": 0.0, f"{b}.rz": 0.0, f"{b}.ox": 0.0})


def toe_state(s):
    """World toe, paw direction and (hind) metatarsus direction of leg s in the current pose."""
    upd()
    paw = PB[LEG_BONES[s][-1]]
    T, P = Vector(paw.tail), Vector(paw.head)
    m = (Vector(PB[LEG_BONES[s][-2]].head) - P).normalized() if s[0] == "h" else None
    return T, (T - P).normalized(), m


def world_values(s, T, d, m):
    vals = [T.x, T.y, T.z, *el_az(d)] + (list(el_az(m)) if m is not None else [])
    return dict(zip(world_keys(s), vals))


WARN = []


def solve2(b1, b2, C, pole_deg, plane=None, w=0.0):
    """Two-bone solve to C (from clips_sleep). With `plane` and weight w the knee swings toward the plane through
    root, C and that point, so the next joint bends in its own hinge plane."""
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
    n = v.cross(u)      # = the direction of (K - A) x (Ce - K) while the joint bends, and still defined when straight
    set_world_rot(b1, (frame_rot(K - A, n) @ CAL[b1]["O1"]).to_quaternion())
    set_world_rot(b2, (frame_rot(Ce - K, n) @ CAL[b1]["O2"]).to_quaternion())


def anchor(s):
    """Pose delta of the leg's body space (Chest for front legs, Hips for hind legs); identity at rest."""
    nm = "Chest" if s[0] == "f" else "Hips"
    return PB[nm].matrix @ BD[nm].matrix_local.inverted()


def solve_leg(p, s):
    """World-space IK of leg s (sp = 0): toe target, paw direction, hind metatarsus direction, pole, paw twist."""
    k = f"{s}."
    T = Vector((p[k + "tx"], p[k + "ty"], p[k + "tz"]))
    d = dvec(p[k + "pel"], p[k + "paz"])
    if s[0] == "f":
        ua, fa, fp = FRONT[s[1]]
        solve2(ua, fa, T - d * LEN[fp], p[k + "pole"])
        aim(fp, T)
        twist(fp, p[k + "tw"])
    else:
        th, sh, hk, hp = HIND[s[1]]
        P = T - d * LEN[hp]
        K = P + dvec(p[k + "mel"], p[k + "maz"]) * LEN[hk]
        solve2(th, sh, K, p[k + "pole"], P, p[k + "plan"])
        aim(hk, P)
        aim(hp, T)
        twist(hp, p[k + "tw"])


def set_leg_fk(p, s):
    """Body-relative FK of leg s (sp = 1): local rotation vectors, plus an "ox" bend about each bone's hinge."""
    for b in LEG_BONES[s]:
        q = qexp((p[f"{b}.rx"], p[f"{b}.ry"], p[f"{b}.rz"]))
        if abs(p[f"{b}.ox"]) > 1e-9:
            q = q @ Quaternion((1, 0, 0), math.radians(p[f"{b}.ox"]))
        if abs(p.get(f"{b}.oz", 0.0)) > 1e-9:       # (optional) swing out of the hinge plane
            q = q @ Quaternion((0, 0, 1), math.radians(p[f"{b}.oz"]))
        PB[b].rotation_quaternion = q


def read_fk(s):
    out = {}
    for b in LEG_BONES[s]:
        out[f"{b}.rx"], out[f"{b}.ry"], out[f"{b}.rz"] = qlog(PB[b].rotation_quaternion)
    return out


TURN_Q = {}       # bone -> world orientations to turn through, used while a clip's params carry "<bone>.qu" (0..1)


def world_aims(p):
    """Turn the AIMED bones (root to tip) from their FK pose toward their world directions, by their group weight."""
    for b, wk in AIMED.items():
        w = p[wk]
        if w > 1e-9:
            upd()
            pb = PB[b]
            d = (pb.tail - pb.head).normalized()
            q = pb.matrix.to_quaternion()
            if f"{b}.qu" in p and b in TURN_Q:      # a whole world orientation, turning through the keyed ones
                qs, u = TURN_Q[b], p[f"{b}.qu"] * (len(TURN_Q[b]) - 1)
                i = min(int(u), len(qs) - 2)
                target = qs[i].slerp(qs[i + 1], u - i)
            else:
                target = d.rotation_difference(dvec(p[f"{b}.wel"], p[f"{b}.waz"])) @ q
            set_world_rot(b, q.slerp(target, w) if w < 1.0 else target)
            if b == "Tail1":          # the brush is a one-sided flag of hair: roll it so it lies flat on the floor
                twist(b, w * p["tailtw"])


def apply_params(p):
    """Pose the rig from a full parameter dict (see REST_P for the keys)."""
    L.reset()
    PB["Hips"].location = REST["Hips"].inverted() @ Vector((p["hx"], p["hy"], p["hz"]))
    for b in FK:
        set_fk(b, p[f"{b}.x"], p[f"{b}.y"], p[f"{b}.z"])
    upd()
    world_aims(p)
    for s in LEGS:
        if p[f"{s}.sp"] >= 0.5:
            set_leg_fk(p, s)
        else:
            solve_leg(p, s)
    upd()


calibrate()


# ---------------------------------------------------------------- mesh: floor solve and floor lifts
assert all(abs(a - b) < 1e-6 for r1, r2 in zip(L.MESH.matrix_world, Matrix.Identity(4)) for a, b in zip(r1, r2))
REAR = {"Hips", "Spine1"}
FORE = {"Spine2", "Chest", "ScapulaL", "ScapulaR"}
# the haunch and shoulder belong to the trunk, the rest of the thigh / upper arm to the leg (a planted leg's knee
# must not lift the body): rest-Z floors of the vertices that count
TRUNK_LIMB_Z = {"ThighL": ("rear", 1.45), "ThighR": ("rear", 1.45), "UpperArmL": ("fore", 1.25),
                "UpperArmR": ("fore", 1.25)}
NECK_BASE_Y = 1.15        # neck vertices behind this (rest Y) belong to the fore trunk
EAR_ROOT = 0.16           # ear vertices this close (rest) to the ear joint count as the head for the head rest
TAIL_BASE_Y = -1.42       # tail-root vertices in front of this (rest Y) are the rump: rear trunk
PITCH_ARM = 1.7           # studs from the hips joint to the fore contact (gain of the pitch solve)
FLOOR_Z = 0.0             # where the trunk rests
LIFT_FLOOR = {"Neck": 0.0, "EarL": -0.025, "EarR": -0.025, "Tail1": -0.02, "Tail2": -0.02, "Tail3": -0.02,
              "Tail4": -0.02}
LIFTS = ("Neck", "EarL", "EarR") + TAILS
LIFT_MAX_EL = 60.0        # a floor lift never turns a bone steeper than this (near vertical its axis is singular)
LEG_FLOOR = -0.02         # an airborne (FK) leg whose mesh dips below this is swung up from its root
PAW_HOVER = 0.135         # lowest toe of an airborne paw (lower would count as a paw sliding along the floor)
LEG_OF = {**{f"{b}{x}": f"f{x}" for b in ("UpperArm", "Forearm", "FrontPaw") for x in "LR"},
          **{f"{b}{x}": f"h{x}" for b in ("Thigh", "Shin", "Hock", "HindPaw") for x in "LR"}}
_IDX = {}


def groups():
    if not _IDX:
        gn = {g.index: g.name for g in L.MESH.vertex_groups}
        dom = {}
        for v in L.MESH.data.vertices:
            if v.groups:
                dom[v.index] = gn[max(v.groups, key=lambda g: g.weight).group]
        sets = {"rear": [], "fore": [], "Neck": [], "EarL": [], "EarR": [], **{t: [] for t in TAILS},
                **{"leg" + s: [] for s in LEGS}}
        for i, n in dom.items():
            co = L.MESH.data.vertices[i].co
            if n in REAR:
                sets["rear"].append(i)
            elif n in FORE or (n == "Neck" and co.y < NECK_BASE_Y):
                sets["fore"].append(i)
            elif n == "Tail1" and co.y > TAIL_BASE_Y:
                sets["rear"].append(i)
            elif n in TRUNK_LIMB_Z and co.z > TRUNK_LIMB_Z[n][1]:
                sets[TRUNK_LIMB_Z[n][0]].append(i)
            elif n in LEG_OF:
                sets["leg" + LEG_OF[n]].append(i)
            elif n in ("Neck", "Head"):
                sets["Neck"].append(i)          # settling / lifting the neck carries the head
            elif n in ("EarL", "EarR") and (co - BD[n].head_local).length < EAR_ROOT:
                sets["Neck"].append(i)          # the ear roots rest with the head; the ear lift turns the rest
            elif n in sets:
                sets[n].append(i)
        for a, b in zip(TAILS, TAILS[1:]):     # each tail bone also carries the root half of the next one
            h = BD[b].head_local
            sets[a] += [i for i in sets[b] if (L.MESH.data.vertices[i].co - h).length < 0.5 * LEN[b]]
        sets["trunk"] = sets["rear"] + sets["fore"]
        _IDX.update({k: np.array(v, dtype=np.int64) for k, v in sets.items()})
    return _IDX


def deformed():
    ev = L.MESH.evaluated_get(bpy.context.evaluated_depsgraph_get())
    me = ev.to_mesh()
    co = np.empty(len(me.vertices) * 3)
    me.vertices.foreach_get("co", co)
    ev.to_mesh_clear()
    return co.reshape(-1, 3)          # the mesh object sits at the identity under the rig


def set_min(name):
    return deformed()[groups()[name], 2].min()


LIFT_TIP = {LEG_BONES[s][0]: LEG_BONES[s][-1] for s in LEGS}    # a leg is swung up about its root-to-toe line


def lift_dir(bone):
    upd()
    pb = PB[bone]
    tip = PB[LIFT_TIP[bone]].tail if bone in LIFT_TIP else pb.tail
    return (tip - pb.head).normalized()


def lift_bone(bone, deg):
    """Turn `bone` so its tip (for a leg root: the toe) rises, about the level axis across it."""
    if abs(deg) > 1e-6:
        a = lift_dir(bone).cross(Vector((0, 0, 1)))
        L.rot(bone, tuple(a.normalized()) if a.length > 1e-4 else (1, 0, 0), deg)


def bisect_lift(bone, ok, cap=70.0, it=11):
    """Smallest lift of `bone` (degrees, capped so it never turns steeper than LIFT_MAX_EL) for which ok() holds;
    applied. 0 when ok() already holds."""
    if ok():
        return 0.0
    q0 = PB[bone].rotation_quaternion.copy()
    el0 = math.degrees(math.asin(max(-1.0, min(1.0, lift_dir(bone).z))))
    lo, hi = 0.0, max(0.0, min(cap, LIFT_MAX_EL - el0))
    for _ in range(it):
        mid = 0.5 * (lo + hi)
        PB[bone].rotation_quaternion = q0
        lift_bone(bone, mid)
        lo, hi = (lo, mid) if ok() else (mid, hi)
    PB[bone].rotation_quaternion = q0
    lift_bone(bone, hi)
    return hi


def needed_lifts(p):
    """The floor lifts of one frame (applied): per airborne leg a swing up from its root, then one per LIFTS bone."""
    out = []
    for s in LEGS:
        lift = 0.0
        if p[f"{s}.sp"] >= 0.5:
            paw = PB[LEG_BONES[s][-1]]
            lift = bisect_lift(LEG_BONES[s][0], lambda: set_min("leg" + s) >= LEG_FLOOR and paw.tail.z >= PAW_HOVER)
        out.append(lift)
    for b in LIFTS:
        out.append(bisect_lift(b, lambda: set_min(b) >= LIFT_FLOOR[b]))
    return out


def apply_lifts(lifts):
    for s, d in zip(LEGS, lifts[:4]):
        lift_bone(LEG_BONES[s][0], d)
    for b, d in zip(LIFTS, lifts[4:]):
        lift_bone(b, d)


def smooth_lift(lam, cyclic=False):
    """Widen and blur per-frame lifts so contact eases in and out; never below the raw lift, and exactly the raw
    lift at both ends (so a clip meets the next one in the same pose). In a loop (frame n is frame 1 again) the
    window wraps around the seam."""
    n = len(lam)
    if cyclic:
        P = n - 1
        wide = [max(lam[(i + k) % P] for k in range(-2, 3)) for i in range(P)]
        blur = [sum(wide[(i + k) % P] * (4 - abs(k)) for k in range(-3, 4)) / 16.0 for i in range(P)]
        out = [max(lam[i], blur[i] * min(1.0, i / 4.0, (P - i) / 4.0)) for i in range(P)]
        return out + [out[0]]
    wide = [max(lam[max(0, i - 2):i + 3]) for i in range(n)]
    blur = [sum(wide[j] * (4 - abs(j - i)) for j in range(max(0, i - 3), min(n, i + 4))) /
            sum(4 - abs(j - i) for j in range(max(0, i - 3), min(n, i + 4))) for i in range(n)]
    taper = [min(1.0, i / 4.0, (n - 1 - i) / 4.0) for i in range(n)]
    return [max(l, b * t) for l, b, t in zip(lam, blur, taper)]


def floor_solve(p):
    """Rest the trunk on the floor. With weight "fpitch" the hips pitch so the fore trunk (chest, shoulders) and the
    rear trunk (pelvis, haunches) touch together; with weight "floor" hz puts the lowest trunk vertex on FLOOR_Z;
    with weight "headrest" the head settles onto the floor. "floorz" raises that floor (a leg pressed under the
    trunk). Leaves the rig posed; returns the solved params."""
    p = dict(p)
    if p["fpitch"] > 1e-9:
        x0, cp = p["Hips.x"], 0.0
        for _ in range(8):
            p["Hips.x"] = x0 + cp
            apply_params(p)
            co = deformed()[:, 2]
            err = co[groups()["fore"]].min() - co[groups()["rear"]].min()
            if abs(err) < 2e-4:
                break
            cp -= math.degrees(err / PITCH_ARM)
        p["Hips.x"] = x0 + p["fpitch"] * cp
    if p["floor"] > 1e-9:
        hz0, c = p["hz"], 0.0
        for _ in range(5):
            p["hz"] = hz0 + c
            apply_params(p)
            err = FLOOR_Z + p["floorz"] - set_min("trunk")
            c += err
            if abs(err) < 1e-4:
                break
        p["hz"] = hz0 + p["floor"] * c
    apply_params(p)
    settle_head(p["headrest"], p["headcw"], p["headc"])
    return p


def head_centre_z():
    upd()
    return 0.5 * (PB["Head"].head.z + PB["Head"].tail.z)


def settle_head(w, wc=0.0, zc=0.0):
    """Pitch the neck (about the level axis across it): with weight w so the head rests on the floor (its lowest
    vertex on Z = 0, from above or below), with weight wc so the middle of the head bone is at height zc (she holds
    her head up, or lowers it at a chosen pace, while the body rolls under it). The two blend by weight."""
    if w <= 1e-9 and wc <= 1e-9:
        return 0.0
    q0 = PB["Neck"].rotation_quaternion.copy()

    def solve(f, lo, hi):
        def at(a):
            PB["Neck"].rotation_quaternion = q0
            lift_bone("Neck", a)
            return f()
        if at(lo) > 0.0:
            return lo
        if at(hi) < 0.0:
            return hi
        for _ in range(14):
            mid = 0.5 * (lo + hi)
            lo, hi = (mid, hi) if at(mid) < 0.0 else (lo, mid)
        return 0.5 * (lo + hi)
    a = 0.0
    if w > 1e-9:
        a += w * solve(lambda: set_min("Neck"), -40.0, 40.0)
    if wc > 1e-9:
        a += wc * solve(lambda: head_centre_z() - zc, -70.0, 70.0)
    PB["Neck"].rotation_quaternion = q0
    lift_bone("Neck", a)
    upd()
    return a


def pose(p, lifts=None):
    """Full pose of one frame: params -> FK/IK -> floor solve -> floor lifts (solved when lifts is None)."""
    p = floor_solve(p)
    if lifts is None:
        lifts = needed_lifts(p)
    else:
        apply_lifts(lifts)
    return p, lifts


# ---------------------------------------------------------------- tracks (from clips_sleep)
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


def unwrap(pts):
    """Azimuth keys take the short way round: each key moves by whole turns to within 180 deg of the one before."""
    out = []
    for x, y in sorted(dict(pts).items()):
        out.append((x, y + 360.0 * round((out[-1][1] - y) / 360.0) if out else y))
    return out


def track_at(pts, nm, f):
    return curve(unwrap(pts) if nm.endswith("az") else pts, f)


class Clip:
    """Per-parameter key lists from start set `a` (frame 1) to end set `b` (frame n). Unset params ramp over the clip."""

    def __init__(self, a, b, n):
        self.a, self.b, self.n, self.k = a, b, n, {}

    def track(self, nm):
        return self.k.get(nm) or [(1, self.a[nm]), (self.n, self.b[nm])]

    def set(self, nm, pts):
        """Inbetween keys (frame, value); value "A"/"B" = the start/end value, a dict = that pose's value."""
        def val(x):
            return {"A": self.a[nm], "B": self.b[nm]}[x] if isinstance(x, str) else x[nm] if isinstance(x, dict) else x
        self.k[nm] = [(1, self.a[nm])] + [(f, val(x)) for f, x in pts] + [(self.n, self.b[nm])]

    def via(self, names, pts):
        for nm in names:
            self.set(nm, pts)

    def at(self, f):
        return {nm: track_at(self.track(nm), nm, f) for nm in self.a}


def keep_until(c, k, f):
    """The keys of track k before frame f, ending in a hold of its value at f."""
    tr = c.track(k)
    return [kk for kk in tr if kk[0] < f] + [(f, track_at(tr, k, f))]


# ---------------------------------------------------------------- legs changing mode
def switch(c, s, f, to_fk, frame_params, later=(), keep=0):
    """Hand leg s between world IK (planted) and body FK (airborne) at frame f: sp steps at f, and the tracks of the
    new mode get a key at f read from the pose the old mode gives at f, so the leg does not move. `later` =
    [(frame, {param: value} or "hold")] adds keys after it ("hold" = keep that shape); the new mode's tracks keep
    their keys up to frame `keep` (a leg returning to a mode it had before an earlier switch). Switches of one leg
    must be made in frame order."""
    old, new = (0.0, 1.0) if to_fk else (1.0, 0.0)
    sp = [k for k in c.track(f"{s}.sp") if k[0] < f - 0.5]
    c.k[f"{s}.sp"] = sp + [(f - 0.5, old), (f, new), (c.n, new)]
    p = frame_params(f)
    p[f"{s}.sp"] = old
    floor_solve(p)
    vals = read_fk(s) if to_fk else world_values(s, *toe_state(s))
    for k in vals:
        prior = keep_until(c, k, keep) if keep else [(1, vals[k])]
        c.k[k] = prior + [(f, vals[k])] + [(g, vals[k] if v == "hold" else v[k]) for g, v in later
                                           if v == "hold" or k in v] + [(c.n, c.b[k])]
    return vals


def lift_off(c, s, f, fp, later, keep=0, up=0.24):
    """A planted (world) paw rises straight up over 3 frames to `up`, then the leg moves with her (FK)."""
    k = f"{s}.tz"
    c.k[k] = keep_until(c, k, f - 3) + [(f, up), (c.n, up)]
    return switch(c, s, f, True, fp, later, keep)


def reach_off(c, s, f, fp, later, up=0.22, fwd=0.45, n=8, side=0.0):
    """A planted front paw lifts and reaches forward over n frames (world IK), then the leg moves with her (FK).
    Reaching straightens the leg, so the elbow comes up off the floor; a paw lifted straight up would fold it down
    into the floor. The paw rises first, then travels."""
    cf = chest_forward(fp(f - n))
    ahead = cf * fwd + Vector((cf.y, -cf.x, 0.0)) * side      # side > 0: out to her right
    for nm in ("tz", "tx", "ty"):
        k = f"{s}.{nm}"
        tr = keep_until(c, k, f - n)
        v0 = tr[-1][1]
        if nm == "tz":
            c.k[k] = tr + [(f - n + 2, v0 + 0.5 * (up - v0)), (f, up), (c.n, up)]
        else:
            v = v0 + (ahead.x if nm == "tx" else ahead.y)
            c.k[k] = tr + [(f - n + 1, v0), (f, v), (c.n, v)]
    return switch(c, s, f, True, fp, later)


def head_z_at(fp, f, rest):
    """Height of the middle of the head bone at frame f: left where the body carries it, or rested on the floor."""
    p = fp(f)
    p["headrest"], p["headcw"] = (1.0 if rest else 0.0), 0.0
    floor_solve(p)
    return head_centre_z()


def chest_forward(p):
    """Level unit vector along which the chest points in the pose of params p."""
    floor_solve(p)
    v = PB["Chest"].matrix.to_3x3() @ REST["Chest"].inverted() @ Vector((0, 1, 0))
    v.z = 0.0
    return v.normalized()


def ik_fk(p, s, T, d, m, pole=0.0, tw=0.0, plan=1.0):
    """FK values of leg s solved by IK to a world target, on the trunk as currently posed."""
    q = dict(p)
    q.update(world_values(s, T, d, m))
    q.update({f"{s}.pole": pole, f"{s}.tw": tw, f"{s}.plan": plan})
    for b in LEG_BONES[s]:              # as in apply_params: the paw is aimed from the rest of its parent
        PB[b].rotation_quaternion = (1, 0, 0, 0)
    solve_leg(q, s)
    upd()
    return read_fk(s)


def land(c, s, f, fp, spot, keep=0, drop=3, above=0.15, via=(), ease_in=0.0):
    """Bring an airborne (FK) leg down onto the world spot of pose `spot`: at frame f the paw is `above` over it,
    then the leg is handed to world IK and lowered straight down onto it over `drop` frames, and stays there.
    `via` = [(frame, FK values)] waypoints on the way (before f); with ease_in the leg already arrives over the spot
    that many frames before f and slows to a stop there (no hard stop at the hand-over)."""
    T = Vector((spot[f"{s}.tx"], spot[f"{s}.ty"], spot[f"{s}.tz"] + above))
    d = dvec(spot[f"{s}.pel"], spot[f"{s}.paz"])
    m = dvec(spot[f"{s}.mel"], spot[f"{s}.maz"]) if s[0] == "h" else None
    for nm in ("pole", "tw", "plan"):
        k = f"{s}.{nm}"
        c.k[k] = (keep_until(c, k, keep) if keep else [(1, c.a[k])]) + [(f - 2, spot[k]), (c.n, spot[k])]
    floor_solve(fp(f))
    vals = ik_fk({}, s, T, d, m, spot[f"{s}.pole"], spot[f"{s}.tw"], spot[f"{s}.plan"])
    for k in fk_keys(s):
        c.k[k] = ([kk for kk in c.track(k) if kk[0] < f] + [(g, v[k]) for g, v in via] +
                  ([(f - ease_in, vals[k])] if ease_in > 0 else []) + [(f, vals[k]), (c.n, c.b[k])])
    switch(c, s, f, False, fp, [(f + drop, {k: spot[k] for k in world_keys(s)})], keep=keep)
    for k in world_keys(s):
        c.k[k] = c.k[k][:-1] + [(c.n, spot[k])]


def land_fwd(c, s, f, fp, spot, via, fwd=0.55, above=0.12, drop=6, side=0.0):
    """land(), reach_off in reverse: at frame f the paw is `fwd` ahead of and `above` over its spot, and it travels
    back and down onto it over `drop` frames, landing last (the leg bends into its stance as it loads)."""
    off = dict(spot)
    cf = chest_forward(fp(f + drop))
    ahead = cf * fwd + Vector((cf.y, -cf.x, 0.0)) * side      # side > 0: from out to her right
    off[f"{s}.tx"] += ahead.x
    off[f"{s}.ty"] += ahead.y
    land(c, s, f, fp, off, drop=drop, above=above, via=via)
    for k in world_keys(s):
        tr = [kk for kk in c.k[k] if kk[0] <= f]
        if k.endswith(".tz"):
            c.k[k] = tr + [(f + drop - 2, spot[k] + 0.5 * (tr[-1][1] - spot[k])), (f + drop, spot[k]), (c.n, spot[k])]
        else:
            c.k[k] = tr + [(f + drop - 1, spot[k]), (c.n, spot[k])]


def step_world(c, s, f0, f1, lift, to=None):
    """Lift-and-place a planted (world) paw over [f0, f1] from where its track holds it to the clip's end pose (or to
    pose `to`)."""
    b, n = to or c.b, c.n
    for nm in WORLD_KEYS[s[0]] + ("pole", "tw"):
        k = f"{s}.{nm}"
        keep = keep_until(c, k, f0)
        held = keep[-1][1]
        if nm in ("tx", "ty"):
            c.k[k] = keep + [(f0 + 1.5, held), (f1 - 2, b[k]), (n, b[k])]
        elif nm == "tz":
            c.k[k] = keep + [(f0 + 3, lift), (f1 - 2.5, lift * 0.8 + b[k] * 0.2), (f1, b[k]), (n, b[k])]
        else:
            c.k[k] = keep + [(f1, b[k]), (n, b[k])]


def unwrap_fk(c):
    """Rotation-vector keys of the FK legs take the short way round: each key is replaced by its equivalent (the same
    rotation, 360 deg further along its axis) nearest to the key before, so no interpolation spins a bone the long way
    (two rotations near 180 deg about opposite axes are close, their rotation vectors are not)."""
    for b in LEG_OF:
        names = [f"{b}.r{a}" for a in "xyz"]
        if not any(nm in c.k for nm in names):
            continue
        tr = [c.track(nm) for nm in names]
        if len({tuple(k[0] for k in t) for t in tr}) != 1:
            continue
        out, prev = [], None
        for i in range(len(tr[0])):
            v = Vector([t[i][1] for t in tr])
            if prev is not None and v.length > 1e-6:
                u = v.normalized() * 360.0
                v = min((v, v - u, v + u), key=lambda w: (w - prev).length)
            out.append(v)
            prev = v
        for j, nm in enumerate(names):
            c.k[nm] = [(tr[j][i][0], out[i][j]) for i in range(len(out))]


# ---------------------------------------------------------------- baking
def key_frame(frame, prev):
    for pb in PB:
        q = Quaternion(pb.rotation_quaternion)
        if pb.name in prev and prev[pb.name].dot(q) < 0:
            q.negate()
            pb.rotation_quaternion = q
        prev[pb.name] = q.copy()
    L.key(frame)


def bake(name, n, frame_params, loop):
    if ARM.animation_data:
        ARM.animation_data.action = None
    raw = [pose(frame_params(f))[1] for f in range(1, n + 1)]
    lam = list(zip(*[smooth_lift([r[k] for r in raw], loop) for k in range(len(raw[0]))]))
    act = L.new_action(name)
    prev = {}
    for f in range(1, n + 1):
        pose(frame_params(f), lam[f - 1])
        key_frame(f, prev)
    L.finish(act, 1, n, loop)
    act["luna_priority"] = "Action"
    return act


# ---------------------------------------------------------------- key poses
def leg_spec(s, kw, dx=0.0):
    """(T, d, m) of a leg spec: toe (or front wrist) position, paw direction, hind metatarsus direction."""
    d = dvec(kw["pel"], kw["paz"])
    T = Vector(kw["wrist"]) + d * LEN[f"FrontPaw{s[1]}"] if "wrist" in kw else Vector(kw["toe"])
    m = dvec(kw["mel"], kw["maz"]) if s[0] == "h" else None
    return T + Vector((dx, 0, 0)), d, m


def rest_fk(s, kw, T=None, d=None, m=None):
    """FK values of leg s for a body-space spec given in the rest frame (as if she were standing): solved by IK on
    the rest pose (the leg's rotations relative to the body do not depend on how the body lies)."""
    if T is None:
        T, d, m = leg_spec(s, kw)
    L.reset()
    upd()
    fk = ik_fk(dict(REST_P), s, T, d, m, kw.get("pole", 0.0), kw.get("tw", 0.0), kw.get("plan", 1.0))
    if "flex" in kw:          # a front paw bent on its hinge instead of aimed (pel/paz are then ignored)
        fk.update(hinge_paw(s, kw["flex"]))
    return fk


def hinge_paw(s, flex):
    """FK of a front paw bent `flex` degrees on its hinge (palmar, about its local -X), the way a carpus bends: the
    back of the paw (fur) stays on the outside of the fold, the pads face the back of the forearm."""
    x = s[1]
    return {f"FrontPaw{x}.rx": -flex, f"FrontPaw{x}.ry": 0.0, f"FrontPaw{x}.rz": 0.0}


def make_pose(pose_set, legs, aims):
    """A settled key pose. legs: {leg: (mode, frame, spec)} - mode "body" (FK, moves with her) or "world" (IK,
    stays put); the spec is in the rest frame ("rest": as if she were standing) or in the world at this pose
    ("world", X relative to hx). aims: {bone: (elevation, azimuth)} world directions of AIMED bones (their group
    weight comes from pose_set)."""
    p = dict(REST_P)
    p.update(pose_set)
    for b, (el, az) in aims.items():
        p[f"{b}.wel"], p[f"{b}.waz"] = el, az
    for s, (mode, frame, kw) in legs.items():
        p[f"{s}.sp"] = 1.0 if mode == "body" else 0.0
        if s[0] == "h":
            p[f"{s}.plan"] = 1.0
        p.update({f"{s}.{k}": kw[k] for k in ("plan", "pole", "tw") if k in kw})
    p = floor_solve(p)
    for _ in range(2):                   # legs given in world coordinates are converted at the settled pose
        body = {}
        for s, (mode, frame, kw) in legs.items():
            T, d, m = leg_spec(s, kw, p["hx"] if frame == "world" else 0.0)
            if mode == "world":
                p.update(world_values(s, T, d, m))
            elif frame == "world":
                Mi = anchor(s).inverted()
                R = Mi.to_3x3()
                body[s] = (kw, Mi @ T, R @ d, R @ m if m is not None else None)
            else:
                body[s] = (kw, T, d, m)
        for s, (kw, T, d, m) in body.items():
            p.update(rest_fk(s, kw, T, d, m))
        p = floor_solve(p)
    p["hz"], p["Hips.x"] = round(p["hz"], 4), round(p["Hips.x"], 3)
    return floor_solve(p)


# ONE BELLY pose: the end of RollOver, both ends of BellyUp and BellyRub, the start of RollUp (refs/4.jpg, 3.jpg).
BELLY_SET = {
    "hx": -0.45, "hz": -1.6, "floor": 1.0, "fpitch": 1.0, "headrest": 1.0, "tailw": 1.0, "earw": 1.0, "tailtw": 110.0,
    # on her back: the chest lies flat, the pelvis is turned onto its left side so the hind legs fall that way
    "Hips.y": -135.0, "Spine1.y": -15.0, "Spine2.y": -14.0, "Chest.y": -12.0,
    # C-curve toward her left (the legs' side), as in the photos
    "Spine1.z": 8.0, "Spine2.z": 10.0, "Chest.z": 8.0,
    # head tipped back onto its crown, nose up toward the person at her head (settle_head rests it on the floor)
    "Neck.x": -22.0, "Neck.z": 12.0, "Head.x": -14.0, "Head.z": 4.0,
}
BELLY_LEGS = {
    # forelegs up off the chest, elbows bent and a little out, the forearms leaning back over the chest; the wrists
    # bent on their hinge (hinge_paw) so the paws flop over toward her belly, fur up and pads toward the chest. The
    # upper arms sit close to their standing angle, so the armpits are not stretched; the right leg is folded a
    # little more than the left (in the rest frame: shoulder (-+0.25, 1.02, 1.45), humerus 150/158 deg and forearm
    # 98/96 deg round from straight ahead)
    "fL": ("body", "rest", dict(wrist=(-0.34, 0.505, 0.515), pel=-90.0, paz=0.0, pole=22.0, flex=125.0)),
    "fR": ("body", "rest", dict(wrist=(0.30, 0.499, 0.573), pel=-90.0, paz=0.0, pole=-14.0, flex=130.0)),
    # right (upper) hind leg fallen open and up, knee bent, hock and paw hanging relaxed
    "hR": ("body", "world", dict(toe=(1.10, -0.60, 1.15), pel=-45.0, paz=60.0, mel=30.0, maz=215.0, pole=25.0)),
    # left (lower) hind leg stretched out along the floor; world IK, so it stays put while she wriggles
    "hL": ("world", "world", dict(toe=(1.5, -2.6, 0.14), pel=-4.0, paz=136.0, mel=6.0, maz=-44.0, plan=0.0)),
}
# tail laid out along the floor behind her, ears flopped out onto the floor (the floor lifts settle them)
BELLY_AIM = {"Tail1": (5.0, 200.0), "Tail2": (4.0, 208.0), "Tail3": (1.0, 205.0), "Tail4": (0.0, 195.0),
             "EarL": (-8.0, 55.0), "EarR": (-8.0, -50.0)}

# lying on her LEFT hip, hind legs folded to her right (clips_sleep's LIE body and legs, copied), head up looking
# at the person: where the lying-down half of RollOver arrives, and where RollUp props herself up
LIE_SET = {
    "hy": -0.3, "hz": -1.21, "tailw": 1.0, "tailtw": 95.0,
    "Hips.x": 12.0, "Hips.y": -46.0, "Spine1.x": -14.5, "Spine1.y": 22.0, "Spine2.y": 14.0, "Chest.y": 7.0,
    "Spine2.z": -4.0, "Chest.z": -4.0,
    "Neck.x": -6.0, "Neck.z": -4.0, "Head.x": 6.0, "EarL.x": 12.0, "EarR.x": 12.0,
    "fL.tx": -0.22, "fL.ty": 1.5, "fL.tz": 0.12, "fL.pel": -15.0, "fL.paz": 0.0,
    "fR.tx": 0.22, "fR.ty": 1.5, "fR.tz": 0.13, "fR.pel": -15.0, "fR.paz": 0.0,
    "hR.tx": 0.95, "hR.ty": -0.66, "hR.tz": 0.04, "hR.pel": -8.0, "hR.paz": 12.0, "hR.mel": 6.0, "hR.maz": 186.0,
    "hR.pole": -12.0, "hR.plan": 1.0,
    "hL.tx": 0.55, "hL.ty": -0.92, "hL.tz": 0.12, "hL.pel": -3.0, "hL.paz": 11.0, "hL.mel": 12.0, "hL.maz": 190.0,
    "hL.pole": -12.0, "hL.tw": -30.0, "hL.plan": 1.0,
}
LIE_AIM = {"Tail1": (-50.0, 185.0), "Tail2": (-25.0, 182.0), "Tail3": (-6.0, 178.0), "Tail4": (0.0, 174.0)}

# legs drawn in close to the body while she rolls over them (rest frame, FK): the hind legs in both rolls; the front
# entries only shape SIDE's trunk (its floor solve), the forelegs themselves go through FWD / FWD_FLEX below
TUCK = {
    "fL": dict(wrist=(-0.30, 1.12, 0.72), pel=-10.0, paz=180.0),
    "fR": dict(wrist=(0.30, 1.15, 0.76), pel=-10.0, paz=180.0),
    "hL": dict(toe=(-0.36, -0.72, 0.70), pel=-10.0, paz=0.0, mel=35.0, maz=180.0),
    "hR": dict(toe=(0.36, -0.70, 0.74), pel=-10.0, paz=0.0, mel=35.0, maz=180.0),
}
# lying flat on her LEFT side on the way over (RollOver) and back (RollUp), legs tucked
SIDE_SET = {
    "hx": -0.2, "hz": -1.45, "floor": 1.0, "fpitch": 1.0, "headrest": 1.0, "tailw": 1.0, "earw": 1.0, "tailtw": 35.0,
    "Hips.y": -92.0, "Spine1.y": 2.0, "Spine2.y": 1.0, "Chest.y": 1.0,
    "Spine1.z": 3.0, "Spine2.z": 4.0, "Chest.z": 3.0,
    "Neck.x": -25.0, "Neck.z": 4.0, "Head.x": -4.0,
    "EarL.x": 25.0, "EarR.x": 25.0,
}
SIDE_AIM = {"Tail1": (-35.0, 185.0), "Tail2": (-10.0, 182.0), "Tail3": (0.0, 178.0), "Tail4": (2.0, 172.0),
            "EarL": (22.0, 175.0), "EarR": (20.0, 185.0)}           # ears laid back along the neck
# ears laid back along the neck (FK, relative to the head) while she rolls
EAR_FK = [f"{e}.{a}" for e in ("EarL", "EarR") for a in "xyz"]
EAR_AIM = [f"{e}.{a}" for e in ("EarL", "EarR") for a in ("wel", "waz")]
EARS_BACK = {"EarL.x": 40.0, "EarL.y": 0.0, "EarL.z": 6.0, "EarR.x": 40.0, "EarR.y": 0.0, "EarR.z": -6.0}
_POSES = {}


def belly():
    if "belly" not in _POSES:
        _POSES["belly"] = make_pose(BELLY_SET, BELLY_LEGS, BELLY_AIM)
    return dict(_POSES["belly"])


def side():
    if "side" not in _POSES:
        _POSES["side"] = make_pose(SIDE_SET, {s: ("body", "rest", TUCK[s]) for s in LEGS}, SIDE_AIM)
    return dict(_POSES["side"])


def lie():
    if "lie" not in _POSES:
        _POSES["lie"] = make_pose(LIE_SET, {}, LIE_AIM)
    return dict(_POSES["lie"])


def only(p, keys):
    return {k: p[k] for k in keys}


# the forelegs while she rolls between her chest and her back (rest frame, FK): reaching forward and down, elbows
# open, wrists relaxed. Forward is her roll axis, so the forearms stay clear of the floor whichever way the chest
# faces, clear of the throat and of each other. Every paw here bends on its hinge only (as in BELLY), so between
# these shapes and BELLY the legs swing at the shoulder and the paws barely turn
FWD = {"fL": dict(wrist=(-0.25, 1.92, 1.40), pel=-45.0, paz=0.0, flex=126.0),
       "fR": dict(wrist=(0.36, 1.92, 1.40), pel=-45.0, paz=8.0, flex=120.0)}
# RollOver: the upper (right) foreleg folds in at her side while she rolls over it (close to the roll axis and out of
# the way of the head she holds up), then opens up into BELLY
FOLD_R = dict(wrist=(0.50, 1.02, 0.84), pel=-90.0, paz=0.0, flex=125.0)
# the same on her side, the wrists relaxed (flexed) so the paws hang toward her belly
FWD_FLEX = {"fL": dict(wrist=(-0.25, 2.0, 1.27), pel=-65.0, paz=0.0, flex=132.0),
            "fR": dict(wrist=(0.36, 2.0, 1.27), pel=-65.0, paz=8.0, flex=130.0)}
# RollUp: the forelegs fold in against the chest as she rolls off her back (close to the roll axis, so the paws do
# not swing round wide), then reach forward
TUCK_F = {"fL": dict(wrist=(-0.30, 1.10, 0.82), pel=-90.0, paz=0.0, flex=128.0),
          "fR": dict(wrist=(0.38, 1.10, 0.86), pel=-90.0, paz=0.0, flex=128.0)}
# RollUp: on her side the upper foreleg is held a little higher and further out, clear of the lower one (which the
# floor lift raises as the chest rolls up over it)
FLEX_UP_R = dict(wrist=(0.55, 1.95, 1.30), pel=-60.0, paz=15.0, flex=125.0)


# ---------------------------------------------------------------- front-first lowering (from clips_sleep)
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
    for _ in range(10):
        if abs(f1) < 1e-6 or f1 == f0:
            break
        x0, x1, f0 = x1, x1 - f1 * (x1 - x0) / (f1 - f0), f1
        f1 = shoulder_z(p, x1) - cz
    return x1


TAIL_LEVEL = 0.8
# RollOver's flop: the head's roll eases from the chest's roll at frame HEAD_TURN[0] to the chest's at HEAD_TURN[1]
# (about 11 deg per frame at most, the chest turns up to 14), and its height comes down along HEAD_DOWN (fraction of
# the way from frame HEAD_FROM's height to its rest on the floor at HEAD_REST): about 0.12 stud per frame at most,
# and onto the floor gently
HEAD_TURN = (34, 56)
HEAD_FROM, HEAD_REST = 34, 52
HEAD_DOWN = [(f, 1.0 - L.ease((f - HEAD_FROM) / (HEAD_REST - HEAD_FROM))) for f in range(HEAD_FROM + 2, HEAD_REST + 1, 2)]
EAR_HAND = 14            # RollUp: the frame by which the ears have come off the floor onto the head
FR_POLE_LAND = -10.0      # RollUp: the right elbow's pole while that paw lands
HR_WIDE, HL_NARROW = 0.35, 0.05   # RollOver: the hind paws' steps, relative to LIE's spots (wider apart)
TWIST = (("Spine1.y", 15.0 / 41.0), ("Spine2.y", 14.0 / 41.0), ("Chest.y", 12.0 / 41.0))


# ---------------------------------------------------------------- RollOver: rest -> BELLY
def roll_over():
    N = 64
    A, H, S, B = dict(REST_P), lie(), side(), belly()
    c = Clip(A, B, N)
    k1 = 30.0 / 47.0

    def T(t):                 # clips_sleep's LieDown frame t, compressed into frames 1..31 here
        return 1.0 + (t - 1.0) * k1
    # ---- lying down (clips_sleep LieDown, faster): front end first, hindquarters fold, rump rolls onto the hip
    c.set("hz", [(T(6), -0.03), (T(12), -0.08), (T(22), -0.4), (T(28), -0.62), (T(35), H["hz"] + 0.1), (31, H),
                 (40, S)])
    c.set("hy", [(T(6), -0.03), (T(14), -0.06), (31, H), (41, -0.2)])
    c.set("Hips.x", [(T(26), 0.0), (31, H), (41, S)])
    c.set("Spine1.x", [(T(26), 0.0), (31, H), (44, "B")])
    cz0, cz1 = shoulder_z(A), shoulder_z(H)
    czk = [(1, cz0), (T(5), cz0 - 0.02), (T(20), cz1 + 0.15), (T(28), cz1 + 0.13), (T(36), cz1 + 0.06),
           (T(42), cz1 + 0.02), (31, cz1), (N, cz1)]
    fwk = [(1, 1.0), (31, 1.0), (38, 0.0), (N, 0.0)]
    # ---- the flop: from the hip over the left side onto her back, the chest leading; then a happy wriggle of the
    # hips against the chest before she settles. The floor solve takes the height, then the pitch, then the head.
    c.set("floor", [(25, 0.0), (30, 1.0)])
    c.set("fpitch", [(32, 0.0), (40, 1.0)])
    # the head does not ride the flop: from frame 35 its height is keyed (headc, solved by the neck), held up while
    # the chest turns under it and then lowered with an ease until it rests on the floor, where the floor settle
    # (headrest) takes over (the keys are set below, once the frame params exist); its roll trails the chest's
    # (HEAD_TURN)
    c.set("headcw", [(HEAD_FROM - 2, 0.0), (HEAD_FROM, 1.0), (HEAD_REST - 4, 1.0), (HEAD_REST, 0.0)])
    c.set("headrest", [(HEAD_REST - 4, 0.0), (HEAD_REST, 1.0)])
    c.set("hx", [(T(24), 0.0), (31, 0.0), (41, S), (50, -0.52)])
    c.set("Hips.y", [(T(24), 0.0), (31, H), (36, -68.0), (41, -95.0), (46, -128.0), (50, -146.0), (54, -128.0),
                     (58, -141.0), (61, -133.0)])
    twist = [(36, 38.0), (41, 5.0), (46, -25.0), (50, -30.0), (54, -52.0), (58, -35.0), (61, -44.0)]
    for nm, w in TWIST:
        c.set(nm, [(T(24), 0.0), (31, H)] + [(f, v * w) for f, v in twist])
    c.set("Spine1.z", [(31, 0.0), (44, S), (56, "B")])
    for nm in ("Spine2.z", "Chest.z"):
        c.set(nm, [(T(24), 0.0), (31, H), (44, S), (56, "B")])
    # head: glances down at the spot, keeps looking at the person while she lies down, lays on the floor as she
    # flops, then tips back onto its crown
    c.set("Neck.x", [(T(7), -12.0), (T(13), -6.0), (T(22), 4.0), (31, H), (38, -15.0), (44, S), (52, -30.0),
                     (58, "B")])
    c.set("Head.x", [(T(7), 4.0), (T(22), 6.0), (31, H), (44, S), (52, -6.0), (58, "B")])
    c.via(["Neck.z", "Neck.y", "Head.z", "Head.y"], [(T(20), "A"), (31, H), (44, S), (56, "B")])
    # ears: they turn with the head (FK, laid back) while she rolls over and only drop onto the floor (world aims)
    # once the head lies still on its crown; world aims during the roll would point them through the skull
    c.via(EAR_FK, [(T(20), "A"), (31, H), (36, H), (42, EARS_BACK), (50, EARS_BACK), (57, "B")])
    c.set("earw", [(51, 0.0), (58, 1.0)])
    c.via(EAR_AIM, [(50, "B")])
    # tail: drawn back as the hips drop, then laid on the floor (world aims), each segment a little later
    c.set("tailw", [(T(22), 0.0), (T(36), 1.0)])
    c.set("tailtw", [(T(36), H), (31, H), (44, S), (58, "B")])
    for i, b in enumerate(TAILS):
        c.via([f"{b}.wel", f"{b}.waz"], [(T(27 + 2 * i), "A"), (T(40 + 2 * i), H), (31, H), (44, S), (58, "B")])

    def roll(g):
        return sum(track_at(c.track(nm), nm, g) for nm in ("Hips.y", "Spine1.y", "Spine2.y", "Chest.y"))

    def fp(f):
        p = c.at(f)
        fw = curve(fwk, f)
        if fw > 1e-6:
            pitch = fw * pitch_for(p, curve(czk, f))
            p["Hips.x"] += pitch
            p["Tail1.x"] -= TAIL_LEVEL * pitch     # gravity: the tail keeps hanging while the body pitches
        # the head does not turn with the chest: its roll follows its own slow ease from where the chest is at
        # HEAD_TURN[0] to where it is at HEAD_TURN[1], so it trails the chest and comes round after it
        lag = 0.0
        if HEAD_TURN[0] < f < HEAD_TURN[1]:
            u = (f - HEAD_TURN[0]) / (HEAD_TURN[1] - HEAD_TURN[0])
            lag = roll(HEAD_TURN[0]) + (roll(HEAD_TURN[1]) - roll(HEAD_TURN[0])) * L.ease(u) - roll(f)
        p["Neck.y"] += 0.6 * lag
        p["Head.y"] += 0.4 * lag
        return p


    # ---- legs, lying down (world IK, planted): front paws walk forward one at a time while the elbows go down;
    # hind paws stay while the hocks lay down, then the right foot steps out wide and the left one in under the belly
    for s, f0 in (("fL", 6), ("fR", 10)):
        k = f"{s}."
        y1 = H[k + "ty"] - 0.07
        c.k[k + "tx"] = [(1, A[k + "tx"]), (T(f0 + 2), A[k + "tx"]), (T(f0 + 7), H[k + "tx"]), (N, H[k + "tx"])]
        c.k[k + "ty"] = [(1, A[k + "ty"]), (T(f0 + 2), A[k + "ty"]), (T(f0 + 7), y1), (T(f0 + 11), y1),
                         (T(f0 + 22), H[k + "ty"]), (N, H[k + "ty"])]
        c.k[k + "tz"] = [(1, A[k + "tz"]), (T(f0), A[k + "tz"]), (T(f0 + 3.5), 0.19), (T(f0 + 5.5), 0.18),
                         (T(f0 + 8.5), H[k + "tz"]), (N, H[k + "tz"])]
        c.k[k + "pel"] = [(1, A[k + "pel"]), (T(f0), A[k + "pel"]), (T(f0 + 3.5), A[k + "pel"] - 10),
                          (T(f0 + 8), -28.0), (T(f0 + 20), H[k + "pel"]), (N, H[k + "pel"])]
        c.k[k + "paz"] = [(1, A[k + "paz"]), (N, H[k + "paz"])]
        for nm in ("pole", "tw"):            # planted elbows keep their bend (BELLY's poles belong to its FK legs)
            c.k[k + nm] = [(1, A[k + nm]), (N, A[k + nm])]
    for s in ("hL", "hR"):
        k = f"{s}."
        c.k[k + "mel"] = [(1, A[k + "mel"]), (T(13), A[k + "mel"]), (T(26), 26.0), (T(38), H[k + "mel"]),
                          (N, H[k + "mel"])]
        c.k[k + "plan"] = [(1, 0.0), (T(5), 1.0), (N, 1.0)]
    for s, f0, f1, lift in (("hR", T(19), T(30), 0.16), ("hL", T(27), T(39), 0.15)):
        k = f"{s}."
        for nm in ("tx", "ty"):
            # the right paw steps out a little wider than LIE's spot and the left one not quite as far in under the
            # belly (both lift off again before LIE matters), so the left thigh coming in under the belly does not
            # meet the right one
            to = H[k + nm] + {("hR", "tx"): HR_WIDE, ("hL", "tx"): -HL_NARROW}.get((s, nm), 0.0)
            c.k[k + nm] = [(1, A[k + nm]), (f0 + 1.0, A[k + nm]), (f1 - 1.3, to), (N, to)]
        c.k[k + "tz"] = [(1, A[k + "tz"]), (f0, A[k + "tz"]), (f0 + 2.0, lift),
                         (f1 - 1.6, lift * 0.8 + H[k + "tz"] * 0.2), (f1, H[k + "tz"]), (N, H[k + "tz"])]
        for nm in ("paz", "maz", "pole", "tw"):
            c.k[k + nm] = [(1, A[k + nm]), (f0, A[k + nm]), (f1, H[k + nm]), (N, H[k + nm])]
        c.k[k + "pel"] = [(1, A[k + "pel"]), (T(13), A[k + "pel"]), (f0, -24.0), (f1, H[k + "pel"]),
                          (N, H[k + "pel"])]
    # ---- legs, the flop: each paw rises off the floor and the leg moves with her (FK). The hind legs first keep
    # their shape, tuck in while she rolls over them, then unfold into the BELLY pose.
    tuck = {s: rest_fk(s, TUCK[s]) for s in ("hL", "hR")}
    lift_off(c, "hR", 33, fp, [(36, "hold"), (42, tuck["hR"]), (46, tuck["hR"]), (54, only(B, fk_keys("hR")))])
    lift_off(c, "hL", 35, fp, [(37, "hold")])
    # forelegs: as the chest starts to turn each paw lifts and reaches forward (world IK; the upper, right one also
    # out to her right, so the hand-over to its stretch is small), then the leg moves with her in the forward stretch
    # (the roll axis: clear of the floor, the throat and the other leg) while she goes over her side, the wrists relax,
    # and once the chest faces up the legs swing up at the shoulder into BELLY (the wrists stay bent on their hinge,
    # so the paws only ride along). The upper leg leads by a couple of frames
    fwd = {s: rest_fk(s, FWD[s]) for s in ("fL", "fR")}
    flx = {s: rest_fk(s, FWD_FLEX[s]) for s in ("fL", "fR")}
    reach_off(c, "fR", 35, fp, [(41, rest_fk("fR", FOLD_R)), (53, only(B, fk_keys("fR")))],
              up=0.28, fwd=0.25, side=0.4, n=9)
    reach_off(c, "fL", 33, fp, [(38, fwd["fL"]), (42, flx["fL"]), (44, flx["fL"]), (57, only(B, fk_keys("fL")))])
    # the left hind leg unfolds over ten frames as she goes over onto her back, hangs a moment over its spot, settles
    # onto the floor stretched out over nine more, and stays put there (world IK in BELLY)
    land(c, "hL", 50, fp, B, keep=35, drop=8, above=0.45, ease_in=1.0)
    # the head's keyed height runs from where the body carries it at frame 34 to where it rests on the floor at
    # HEAD_REST (both measured now that the legs, which shape the trunk's floor solve, are all set)
    z0 = head_z_at(fp, HEAD_FROM, rest=False)
    z1 = head_z_at(fp, HEAD_REST, rest=True)
    c.set("headc", [(HEAD_FROM, z0)] + [(f, z1 + (z0 - z1) * v) for f, v in HEAD_DOWN])
    unwrap_fk(c)
    return bake("RollOver", N, fp, False)


# ---------------------------------------------------------------- loops on the BELLY pose
def wave(t, k, lag=0.0):
    """sin of k whole cycles over the clip, delayed by `lag` (fraction of a cycle), shifted so it is exactly 0 at
    both ends: the loop starts and ends in the BELLY pose and stays smooth across the seam."""
    return math.sin(2.0 * math.pi * (k * t - lag)) - math.sin(-2.0 * math.pi * lag)


def breath(p, a):
    """Ribcage rise of `a` degrees that leaves the chest and pelvis where they are (clips_sleep): the mid-ribs move
    toward the back for a > 0; on her back a < 0 lifts the belly."""
    p["Spine1.x"] += a
    p["Spine2.x"] -= 2.0 * a
    p["Chest.x"] += a


def breaths(t, n):
    """n breaths over the clip: in over 40%, out over 60%, exactly 0 at both ends (clips_sleep)."""
    ph = (n * t) % 1.0
    return L.ease(ph / 0.4) if ph < 0.4 else 1.0 - L.ease((ph - 0.4) / 0.6)


def add_twist(p, deg):
    for nm, w in TWIST:
        p[nm] += deg * w


def belly_up():
    N = 120
    B = belly()
    twitch = [(1, 0.0), (68, 0.0), (70, 9.0), (73, -3.0), (77, 0.0), (N, 0.0)]     # one ear flick

    def fp(f):
        t = (f - 1.0) / (N - 1.0)
        p = dict(B)
        breath(p, -3.5 * breaths(t, 3))                    # slow breaths: the belly rises
        p["Hips.y"] += 2.5 * wave(t, 1)                     # a slow rock from side to side, the chest a beat later
        add_twist(p, 2.5 * (wave(t, 1, 0.07) - wave(t, 1)))
        for x, lag in (("L", 0.0), ("R", 0.35)):             # front paws curl and uncurl, out of step, the
            p[f"FrontPaw{x}.ox"] += 9.0 * wave(t, 2, lag)       # elbow following a little later
            p[f"Forearm{x}.ox"] -= 3.0 * wave(t, 2, lag + 0.1)
        for i, b in enumerate(TAILS):                        # the tail sweeps the floor, the tip trailing
            p[f"{b}.waz"] += (7.0 + 4.0 * i) * wave(t, 2, 0.06 * i)
        p["Neck.y"] += 4.0 * wave(t, 1, 0.1)                # the head rolls a little on its crown
        p["Head.z"] += 3.0 * wave(t, 1, 0.2)
        p["EarR.waz"] += curve(twitch, f)
        p["EarL.waz"] += 3.0 * wave(t, 1, 0.15)
        return p
    return bake("BellyUp", N, fp, True)


OZ_KICK = 10.0      # the kicking thigh swings a little out from her side (straight in its hinge plane the shin brushes it)


def belly_rub():
    N = 90
    B = belly()
    kick = [(1, 0.0), (16, 0.0), (24, 1.0), (62, 1.0), (70, 0.0), (N, 0.0)]      # kick envelope
    curl = [(1, 0.0), (6, 0.0), (16, 1.0), (74, 1.0), (86, 0.0), (N, 0.0)]       # front paws curled tighter

    def fp(f):
        t = (f - 1.0) / (N - 1.0)
        p = dict(B)
        breath(p, -2.5 * breaths(t, 4))                     # quicker, happy breaths
        # playful wriggle: hips and chest twist against each other, the spine bending with them
        p["Hips.y"] -= 4.0 * wave(t, 2)
        add_twist(p, 9.0 * wave(t, 2, 0.04))
        for nm, a in (("Spine1.z", 2.0), ("Spine2.z", 3.0), ("Chest.z", 2.0)):
            p[nm] += a * wave(t, 2, 0.12)
        # the right hind leg paddles: 5 quick strokes, hip, stifle and hock flexing and extending together, each
        # joint a touch behind the one above (follow-through). The leg is drawn up while it kicks (the -20 deg
        # offset), so the paw paddles in the air beside her belly and never dips into it
        e = curve(kick, f)
        if e > 1e-9:
            ph = 2.0 * math.pi * (f - 18.0) / 10.0
            p["ThighR.ox"] += e * (-20.0 + 22.0 * math.sin(ph))
            p["ThighR.oz"] = e * OZ_KICK
            p["ShinR.ox"] -= e * 18.0 * math.sin(ph - 0.35)
            p["HockR.ox"] += e * 18.0 * math.sin(ph - 0.7)
            p["HindPawR.ox"] += e * 14.0 * math.sin(ph - 1.0)
        c = curve(curl, f)
        for x, lag in (("L", 0.0), ("R", 0.25)):             # forepaws pulled in and curled tighter, little kneading
            p[f"FrontPaw{x}.ox"] -= c * (10.0 + 4.0 * math.sin(2.0 * math.pi * (4.0 * t - lag)))
            p[f"Forearm{x}.ox"] += c * 8.0                    # (elbow and shoulder fold together: the paws come
            p[f"UpperArm{x}.ox"] -= c * 6.0                   # down toward the chest)
        for i, b in enumerate(TAILS):                        # tail wags on the floor
            p[f"{b}.waz"] += (10.0 + 4.0 * i) * wave(t, 6, 0.05 * i)
        p["Neck.y"] += 7.0 * wave(t, 2, 0.08)                # head tossing gently
        p["Head.z"] += 5.0 * wave(t, 2, 0.18)
        p["Head.x"] += 3.0 * wave(t, 4, 0.1)
        for e_, a in (("EarL", 4.0), ("EarR", -4.0)):
            p[f"{e_}.waz"] += a * wave(t, 2, 0.15)
        return p
    return bake("BellyRub", N, fp, True)


# ---------------------------------------------------------------- RollUp: BELLY -> rest
def roll_up():
    N = 50
    A, S, H, B = belly(), side(), lie(), dict(REST_P)
    c = Clip(A, B, N)
    k2 = 28.0 / 44.0

    def W(t):                 # clips_sleep's WakeUp frame t, compressed into frames 22..50 here
        return 22.0 + (t - 1.0) * k2
    # ---- roll back up: the chest leads over onto the left side and up onto the chest; the pelvis follows onto the
    # left hip (the LIE pose at frame 22); the floor solve hands the height back to the keys
    c.set("floor", [(18, 1.0), (23, 0.0)])
    c.set("floorz", [(15, 0.0), (18, 0.035), (21, 0.0)])     # the downside haunch rolls under the pelvis
    c.set("fpitch", [(11, 1.0), (17, 0.0)])
    c.set("headrest", [(5, 1.0), (12, 0.0)])
    c.set("hx", [(12, S), (22, H)])
    c.set("hy", [(12, -0.15), (22, H), (W(20), -0.26), (W(36), 0.03), (W(40), 0.05)])
    c.set("hz", [(12, S), (22, H), (W(8), H["hz"] + 0.02), (W(16), H["hz"] + 0.24), (W(22), H["hz"] + 0.42),
                 (W(36), 0.01), (W(40), 0.0)])
    c.set("Hips.x", [(12, S), (22, H), (W(12), H), (W(30), "B")])
    c.set("Spine1.x", [(22, H), (W(12), H), (W(30), "B")])
    c.set("Hips.y", [(4, -139.0), (8, -122.0), (12, -95.0), (16, -72.0), (19, -55.0), (22, H), (W(9), H),
                     (W(24), "B")])
    chest = [(4, -172.0), (10, -100.0), (14, -55.0), (18, -15.0)]
    for nm, w in TWIST:
        c.set(nm, [(f, (v - curve(c.k["Hips.y"], f)) * w) for f, v in chest] + [(22, H), (W(9), H), (W(24), "B")])
    for nm in ("Spine1.z", "Spine2.z", "Chest.z"):
        c.set(nm, [(12, S), (22, H), (W(9), H), (W(24), "B")])
    # head: tips forward off its crown and comes up as she rolls, looks ahead while she gets up
    c.set("Neck.x", [(6, -32.0), (12, -18.0), (22, H), (W(10), -8.0), (W(20), -4.0), (W(30), -2.0), (W(38), 3.0)])
    c.set("Head.x", [(6, -6.0), (12, 0.0), (22, H), (W(20), 4.0), (W(38), -2.0)])
    c.via(["Neck.z", "Neck.y", "Head.z", "Head.y"], [(12, S), (22, H), (W(12), "B")])
    # ears: they leave the floor as the head turns and stay laid back (FK) until the head is upright again
    # (they leave the floor as world aims that turn steadily, over about ten frames, to where the laid-back ears point at
    # EAR_HAND, and only then hand over to the head; blending the floor aims straight into the turning head instead
    # swept the left ear across the floor in three frames)
    c.set("earw", [(EAR_HAND - 3, 1.0), (EAR_HAND, 0.0)])
    c.via(EAR_FK, [(2, "A"), (11, EARS_BACK), (16, EARS_BACK), (22, H), (W(15), "B")])
    # the left ear swings out past the cheek on its way up off the floor (straight across it would pass through it)
    c.k["EarL.y"] = sorted(c.k["EarL.y"] + [(6.0, -28.0)])
    # tail: lies on the floor (world aims) until the hind legs are under her, then swings back and drags as she
    # rises
    c.set("tailw", [(W(18), 1.0), (W(34), 0.0)])
    c.set("tailtw", [(12, S), (22, H)])
    for b in TAILS:
        c.via([f"{b}.wel", f"{b}.waz"], [(12, S), (22, H)])
    c.set("Tail1.x", [(W(16), 0.0), (W(26), -26.0), (W(37), 0.0)])
    # and swings to her left as it comes off the floor, out of the way of the right hind paw stepping in under her
    c.set("Tail1.z", [(W(12), 0.0), (W(22), -24.0), (W(32), -16.0), (W(40), 0.0)])
    # as the rump rises the root of the tail flattens out and the rest keeps lying along the floor (with the root
    # still aimed steeply down, as it is in LIE, the tail would be jammed into the floor and its tip folded up)
    for b, dwn in (("Tail1", -24.0), ("Tail2", -10.0), ("Tail3", 4.0), ("Tail4", 6.0)):
        tr = c.track(f"{b}.wel")
        c.k[f"{b}.wel"] = [kk for kk in tr if kk[0] <= W(9)] + [(W(9), track_at(tr, f"{b}.wel", W(9))),
                                                                  (W(21), H[f"{b}.wel"] - dwn), (N, B[f"{b}.wel"])]
    for i, b in enumerate(TAILS):
        c.set(f"{b}.waz", keep_until(c, f"{b}.waz", W(10))[1:] + [(W(20), H[f"{b}.waz"] + 18.0 + 4.0 * i)])
    cza, czr = shoulder_z(H), shoulder_z(B)
    czk = [(1, cza), (W(1), cza), (W(5), cza + 0.03), (W(12), cza + 0.22), (W(20), 1.25), (W(34), czr - 0.01),
           (W(39), czr - 0.03), (N, czr)]
    fwk = [(1, 0.0), (16, 0.0), (22, 1.0), (N, 1.0)]
    stretch = [(1, 0.0), (W(35), 0.0), (W(39), -1.5), (N - 1, 0.0), (N, 0.0)]

    def fp(f):
        p = c.at(f)
        fw = curve(fwk, f)
        if fw > 1e-6:
            pitch = fw * pitch_for(p, curve(czk, f))
            p["Hips.x"] += pitch
            p["Tail1.x"] -= TAIL_LEVEL * pitch
        p["Spine1.x"] += curve(stretch, f)
        return p

    # ---- legs: the stretched left hind leg rises off the floor; all legs tuck in while she rolls, then come down
    # where she lies on her left hip (clips_sleep's LIE spots, the downside hind leg first, folded under her), then
    # step under her as she gets up (clips_sleep's WakeUp)
    tuck = {s: rest_fk(s, TUCK[s]) for s in ("hL", "hR")}
    for k in world_keys("hL"):                       # planted where it lay until it lifts
        c.k[k] = [(1, A[k]), (N, A[k])]
    lift_off(c, "hL", 4, fp, [(10, tuck["hL"])])
    for k in fk_keys("hR"):
        c.k[k] = [(1, A[k]), (9, tuck["hR"][k]), (N, B[k])]
    # forelegs: RollOver's in reverse. They swing down at the shoulder from BELLY into the relaxed forward stretch
    # (the wrists stay bent on their hinge; the two legs a couple of frames apart so the paws do not meet over the
    # chest) while the chest turns onto its side, keep it while she rolls up onto her chest (the upper one held
    # higher, FLEX_UP_R), and come down onto their LIE spots from in front of them (land_fwd), the upper one first and
    # wider, so its forearm passes outside the lower leg's elbow
    flx = {s: rest_fk(s, FWD_FLEX[s]) for s in ("fL", "fR")}
    tuck_f = {s: rest_fk(s, TUCK_F[s]) for s in ("fL", "fR")}
    land_fwd(c, "fR", 17, fp, H, [(6, tuck_f["fR"]), (12, rest_fk("fR", FLEX_UP_R))], side=0.36)
    land(c, "hL", 15, fp, H, keep=4)
    land_fwd(c, "fL", 19, fp, H, [(7, tuck_f["fL"]), (13, flx["fL"])])
    land(c, "hR", 18, fp, H)
    # the right elbow's pole while that paw lands (LIE's own pole lets the elbow swing round as the shoulder rises)
    c.k["fR.pole"] = keep_until(c, "fR.pole", 15) + [(18, FR_POLE_LAND), (23, FR_POLE_LAND), (W(9), H["fR.pole"]),
                                                       (N, B["fR.pole"])]
    for s in ("hL", "hR"):
        c.k[f"{s}.plan"] = keep_until(c, f"{s}.plan", 20) + [(N - 6, 1.0), (N, 0.0)]
    # (the left paw steps under her once the chest is up off the floor: stepped earlier, while the shoulder is still
    # low, the leg would have to fold tighter than its bones allow and the elbow would flip up over the shoulder)
    step_world(c, "fL", W(9), W(19.5), 0.15)
    step_world(c, "fR", W(11), W(21), 0.2)
    for s, f0, f1 in (("hL", W(11.5), W(24.5)), ("hR", W(16), W(27))):
        step_world(c, s, f0, f1, 0.18 if s == "hL" else 0.16)
        k = f"{s}."
        c.k[k + "mel"] = keep_until(c, k + "mel", f0) + [(f0 + 4 * k2, 34.0), (f1, 45.0), (W(36), B[k + "mel"]),
                                                         (N, B[k + "mel"])]
        c.k[k + "pel"] = keep_until(c, k + "pel", f0) + [(f1, -24.0), (W(28), -24.0), (W(36), B[k + "pel"]),
                                                         (N, B[k + "pel"])]
    # the ears' floor aims: their direction turns from where they lie at frame 2 to where the head carries them at
    # EAR_HAND ...
    for e in ("EarL", "EarR"):
        q = fp(EAR_HAND)
        q["earw"] = 0.0
        floor_solve(q)
        el, az = el_az(PB[e].tail - PB[e].head)
        az0 = A[f"{e}.waz"]
        az = az + 360.0 * round((az0 - az) / 360.0)
        c.set(f"{e}.wel", [(2, "A"), (EAR_HAND, el)])
        c.set(f"{e}.waz", [(2, "A"), (EAR_HAND, az)])
    # ... and their whole orientation turns steadily through how they lie at frame 2, how that aim holds them halfway
    # and how the head carries them at EAR_HAND (aiming only the direction lets an ear spin about its own length;
    # one turn straight from the floor to the head passes through the skull)
    qs = {}
    for f, earw in ((2, None), ((2 + EAR_HAND) / 2.0, None), (EAR_HAND, 0.0)):
        q = fp(f)
        if earw is not None:
            q["earw"] = earw
        floor_solve(q)
        for e in ("EarL", "EarR"):
            qs.setdefault(e, []).append(PB[e].matrix.to_quaternion())
    for e, ql in qs.items():
        for i in range(1, len(ql)):
            if ql[i].dot(ql[i - 1]) < 0:
                ql[i].negate()
    TURN_Q.clear()
    TURN_Q.update(qs)

    def fp_ears(f):
        p = fp(f)
        u = L.ease(min(1.0, max(0.0, (f - 2.0) / (EAR_HAND - 2.0))))
        if f > 2.0:          # (frame 1 is BELLY exactly; the turn starts from frame 2's pose)
            p["EarL.qu"] = p["EarR.qu"] = u
        return p
    unwrap_fk(c)
    act = bake("RollUp", N, fp_ears, False)
    TURN_Q.clear()
    return act


def build():
    _POSES.clear()
    calibrate()
    acts = [roll_over(), belly_up(), belly_rub(), roll_up()]
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
