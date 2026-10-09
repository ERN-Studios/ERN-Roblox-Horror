"""Luna sit group: SitDown, Sit, GivePaw, StandUp (Blender 5.2, headless).

    D:\\Blender\\blender.exe -b luna_rig2.blend -P clips_sit.py -- <out.blend>

Every frame is solved analytically and keyed on every frame:
  * body (Hips/spine/neck/head/ears) from a small parametric STATE,
  * front legs: scapula auto-aims the shoulder joint at a target, then 2-bone IK (UpperArm/Forearm) to the wrist,
    FrontPaw keeps a world orientation (identity = planted exactly at rest),
  * hind legs: toe target + HindPaw world pitch, the hock pivots about the paw joint by `alpha` (in the transitions
    alpha follows the hip joint, see hock_follow), 2-bone IK (Thigh/Shin) from the hip joint to the heel,
  * body: in SitDown/StandUp the hips translation is solved so the scapulae stay over the planted forepaws,
  * tail: world yaw/elevation/roll per segment, moved along smooth arcs. A per-clip pass lifts a segment only if
    its own skinned mesh would dip under the floor, smoothed over time so contact never pops.
No constraints or helper objects are ever created. SIT is one STATE, reused exactly by all four clips.

The rig's standing stance is long (2.3 studs paw to paw): with the front paws pinned at rest, a dog can only sit
tall with straight, near-vertical forelegs if the hind paws come forward under the body. So SitDown tucks the hind
paws forward with one small lifted step each (no sliding), and StandUp steps them back to the rest stance.
"""
import sys, math
sys.path.insert(0, r"G:\Roblox\MongoTV\tools\luna\anim")
import bpy
from mathutils import Vector, Matrix
import lunalib as L

ARM = L.ARM
BD = ARM.data.bones
PB = ARM.pose.bones
I3 = Matrix.Identity(3)
TAILS = ("Tail1", "Tail2", "Tail3", "Tail4")
TAIL_FLOOR = 0.012          # lowest point of each tail segment's own skinned mesh rests this high


def R(axis, deg):
    return Matrix.Rotation(math.radians(deg), 3, axis)


def eul(p=0.0, r=0.0, y=0.0):
    """pitch about X, roll about Y, yaw about Z (armature axes), applied pitch -> roll -> yaw."""
    return R("Z", y) @ R("Y", r) @ R("X", p)


def rest3(n):
    return BD[n].matrix_local.to_3x3()


def hr(n):
    return BD[n].head_local.copy()


def tr(n):
    return BD[n].tail_local.copy()


def frame(d, n):
    d = d.normalized()
    n = (n - d * n.dot(d)).normalized()
    return Matrix((d, n, d.cross(n))).transposed()


def map_rot(d0, n0, d1, n1):
    """Rotation taking direction d0 -> d1 while the plane normal n0 -> n1."""
    return frame(d1, n1) @ frame(d0, n0).transposed()


def ik2(root, target, l1, l2, pole):
    d = target - root
    dist = min(max(d.length, abs(l1 - l2) + 1e-4), (l1 + l2) * 0.99995)
    u = d.normalized()
    v = (pole - u * pole.dot(u)).normalized()
    a = (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist)
    h = math.sqrt(max(l1 * l1 - a * a, 0.0))
    return root + u * a + v * h, root + u * dist, u.cross(v), d.length - dist


def yaw_elev(d):
    d = d.normalized()
    return math.degrees(math.atan2(d.x, -d.y)), math.degrees(math.asin(max(-1.0, min(1.0, d.z))))


def dir_ye(yaw, elev):
    """yaw 0 = straight back (-Y), +90 = her right (+X); elev + = up."""
    y, e = math.radians(yaw), math.radians(elev)
    return Vector((math.sin(y) * math.cos(e), -math.cos(y) * math.cos(e), math.sin(e)))


# ---------------------------------------------------------------- rest geometry
def _leg_rest(b1, b2, end):
    root, mid, tip = hr(b1), hr(b2), end
    u = (tip - root).normalized()
    v = ((mid - root) - u * (mid - root).dot(u)).normalized()
    return {"l1": (mid - root).length, "l2": (tip - mid).length, "pole": v, "n": u.cross(v),
            "d1": (mid - root).normalized(), "d2": (tip - mid).normalized()}


def ventral(d, beta):
    """Tail underside direction: beta=-90 -> the rest underside (down for a level tail), 0 -> toward her right of
    the tail (h = Z x d)."""
    h = Vector((0, 0, 1)).cross(d)
    if h.length < 1e-6:
        h = Vector((1, 0, 0))
    h.normalize()
    k = d.normalized().cross(h)
    b = math.radians(beta)
    return h * math.cos(b) + k * math.sin(b)


TAIL_VEN = {t: ventral((tr(t) - hr(t)).normalized(), -90.0) for t in TAILS}

LEG = {}
for s in "LR":
    LEG["F" + s] = _leg_rest("UpperArm" + s, "Forearm" + s, hr("FrontPaw" + s))
    LEG["H" + s] = _leg_rest("Thigh" + s, "Shin" + s, hr("Hock" + s))


def _tail_skin():
    """Skinning data of the vertices each tail bone dominates: [(bone, normalised weight, rest offset from the bone
    head)] per vertex. The tail mesh hangs in FRONT of its bones (they run along its back edge) and is partly
    weighted to the thighs, so the floor test skins the real vertices (linear blend, as the Armature modifier)."""
    names = {g.index: g.name for g in L.MESH.vertex_groups}
    out = {t: [] for t in TAILS}
    for v in L.MESH.data.vertices:
        ws = [(names[g.group], g.weight) for g in v.groups
              if g.weight > 0 and names[g.group] in BD and BD[names[g.group]].use_deform]
        if not ws:
            continue
        dom = max(ws, key=lambda x: x[1])[0]
        if dom in out:
            tot = sum(w for _, w in ws)
            out[dom].append([(b, w / tot, tuple(v.co - hr(b))) for b, w in ws])
    return out


SKIN = _tail_skin()


def rest_state():
    st = {k: 0.0 for k in ("hx", "hy", "hz", "hp", "hr", "hyaw", "s1p", "s1r", "s1y", "s2p", "s2r", "s2y",
                           "cp", "cr", "cy", "np", "nr", "ny", "headp", "headr", "heady", "earb", "earo")}
    for i, t in enumerate(TAILS, 1):
        st[f"t{i}y"], st[f"t{i}e"] = yaw_elev(tr(t) - hr(t))
        st[f"t{i}b"] = -90.0
    for s in "LR":
        st[f"f{s}toe"] = tr("FrontPaw" + s)
        st[f"f{s}phi"] = 0.0
        st[f"f{s}sh"] = hr("UpperArm" + s)
        st[f"f{s}pole"] = LEG["F" + s]["pole"].copy()
        st[f"h{s}toe"] = tr("HindPaw" + s)
        st[f"h{s}pp"] = 0.0
        st[f"h{s}alpha"] = 0.0
        st[f"h{s}pole"] = LEG["H" + s]["pole"].copy()
    return st


def mix(a, b, w):
    """Blend two states; w is a number or a function key -> weight."""
    out = {}
    for k in a:
        t = w(k) if callable(w) else w
        out[k] = a[k] * (1 - t) + b[k] * t if not isinstance(a[k], Vector) else a[k].lerp(b[k], t)
    return out


# ---------------------------------------------------------------- tail helpers
def tail_D(i, yaw, elev, beta):
    t = TAILS[i - 1]
    d = dir_ye(yaw, elev)
    return map_rot(tr(t) - hr(t), TAIL_VEN[t], d, ventral(d, beta))


def skin_min_z(i, D, head):
    """Lowest skinned z of the vertices tail segment i dominates, for bone rotations D and posed heads `head`."""
    rows = {}
    best = 9.0
    for vert in SKIN[TAILS[i - 1]]:
        z = 0.0
        for b, w, (x, y, zz) in vert:
            r = rows.get(b)
            if r is None:
                m = D[b]
                r = rows[b] = (m[2][0], m[2][1], m[2][2], head[b].z)
            z += w * (r[3] + r[0] * x + r[1] * y + r[2] * zz)
        best = min(best, z)
    return best


def floor_need(st, i):
    """Degrees segment i must be raised so the mesh it dominates clears TAIL_FLOOR (0 if it already does)."""
    D, _, _, head = solve(st)
    y, e0, b = st[f"t{i}y"], st[f"t{i}e"], st[f"t{i}b"]

    def z(e):
        D2, h2 = dict(D), dict(head)
        for j in range(i, 5):
            t = TAILS[j - 1]
            if j > i:
                p = TAILS[j - 2]
                h2[t] = h2[p] + D2[p] @ (tr(p) - hr(p))
            D2[t] = tail_D(j, y, e, b) if j == i else D[t]
        return skin_min_z(i, D2, h2)
    if z(e0) >= TAIL_FLOOR:
        return 0.0
    lo, hi = e0, 80.0
    for _ in range(16):
        mid = 0.5 * (lo + hi)
        if z(mid) >= TAIL_FLOOR:
            hi = mid
        else:
            lo = mid
    return hi - e0


def envelope(x, r, loop):
    """Smooth upper envelope: >= x everywhere (dilate by 2r, then two box blurs of radius r)."""
    n = len(x)
    idx = (lambda k: k % n) if loop else (lambda k: min(max(k, 0), n - 1))
    y = [max(x[idx(k + j)] for j in range(-2 * r, 2 * r + 1)) for k in range(n)]
    for _ in range(2):
        y = [sum(y[idx(k + j)] for j in range(-r, r + 1)) / (2 * r + 1) for k in range(n)]
    return y


def settle_tail(states, loop=False, pin=(False, False), r=2, passes=2, ramp=6):
    """Lift tail segments (root to tip) off the floor; the lift is smoothed over time so contact never pops.
    A second pass catches joint vertices that a later (child) lift pushed back down. `pin` (start, end) keeps those
    frames at exactly their own floor need (zero for SIT/REST), so clips join SIT/REST exactly."""
    n = len(states)

    def pin_w(f):
        w = 0.0
        if pin[0]:
            w = max(w, 1.0 - smooth(seg(f, 0, ramp)))
        if pin[1]:
            w = max(w, 1.0 - smooth(seg(n - 1 - f, 0, ramp)))
        return w
    for i in [i for _ in range(passes) for i in range(1, 5)]:
        need = [floor_need(st, i) for st in states]
        if max(need) <= 0.0:
            continue
        if n == 1:
            lift = need
        elif loop:                                   # last frame repeats the first
            lift = envelope(need[:-1], r, True)
            lift.append(lift[0])
        else:
            lift = envelope(need, r, False)
        for f, (st, d, nd) in enumerate(zip(states, lift, need)):
            st[f"t{i}e"] += nd + (d - nd) * (1.0 - pin_w(f))


# ---------------------------------------------------------------- solve one frame
def solve(st):
    """STATE -> {bone: armature-space delta rotation}, hips translation, diagnostics, posed bone heads."""
    D = {"Root": I3.copy()}
    head = {}
    hips_d = Vector((st["hx"], st["hy"], st["hz"]))
    D["Hips"] = eul(st["hp"], st["hr"], st["hyaw"])
    head["Hips"] = hr("Hips") + hips_d

    def place(n):                      # pose head of bone n from its parent (bones are never translated)
        p = BD[n].parent.name
        head[n] = head[p] + D[p] @ (hr(n) - hr(p))

    for n, pre in (("Spine1", "s1"), ("Spine2", "s2"), ("Chest", "c")):
        D[n] = eul(st[pre + "p"], st[pre + "r"], st[pre + "y"]) @ D[BD[n].parent.name]
        place(n)
    D["Neck"] = eul(st["np"], st["nr"], st["ny"]) @ D["Chest"]
    place("Neck")
    D["Head"] = eul(st["headp"], st["headr"], st["heady"])
    place("Head")
    for s, sx in (("L", -1), ("R", 1)):
        D["Ear" + s] = D["Head"] @ eul(st["earb"], -sx * st["earo"], 0.0)
        place("Ear" + s)
    diag = {}
    for i, t in enumerate(TAILS, 1):
        place(t)
        D[t] = tail_D(i, st[f"t{i}y"], st[f"t{i}e"], st[f"t{i}b"])

    for s in "LR":
        # front: scapula aims the shoulder joint at the target (rotation about X through its head)
        sc = "Scapula" + s
        D[sc] = D["Chest"].copy()
        place(sc)
        v = D[sc] @ (tr(sc) - hr(sc))
        w = st[f"f{s}sh"] - head[sc]
        a = math.atan2(w.z, w.y) - math.atan2(v.z, v.y)
        a = (a + math.pi) % (2 * math.pi) - math.pi
        ua, fa, fp = "UpperArm" + s, "Forearm" + s, "FrontPaw" + s
        Dp = R("X", st[f"f{s}phi"])
        wrist = st[f"f{s}toe"] - Dp @ (tr(fp) - hr(fp))
        lg = LEG["F" + s]
        reach = (lg["l1"] + lg["l2"]) * 0.985
        # if the arm cannot reach the wrist from there, take the nearest scapula angle that can
        for k in range(0, 721):
            cand = [a] if k == 0 else [a - math.radians(0.25 * k), a + math.radians(0.25 * k)]
            hit = [c for c in cand if (head[sc] + Matrix.Rotation(c, 3, "X") @ v - wrist).length <= reach]
            if hit:
                a = hit[0]
                break
        D[sc] = Matrix.Rotation(a, 3, "X") @ D[sc]
        place(ua)
        diag["F" + s + "shoulder_err"] = (head[ua] - st[f"f{s}sh"]).length
        elbow, end, n, miss = ik2(head[ua], wrist, lg["l1"], lg["l2"], st[f"f{s}pole"])
        D[ua] = map_rot(lg["d1"], lg["n"], elbow - head[ua], n)
        D[fa] = map_rot(lg["d2"], lg["n"], end - elbow, n)
        D[fp] = Dp
        place(fa); place(fp)
        diag["F" + s + "miss"] = miss
        # hind: toe target + paw pitch, the hock pivots about the paw joint, thigh/shin IK to the heel
        th, sh, hk, hp = "Thigh" + s, "Shin" + s, "Hock" + s, "HindPaw" + s
        place(th)
        Dpaw = R("X", st[f"h{s}pp"])
        P = st[f"h{s}toe"] - Dpaw @ (tr(hp) - hr(hp))
        heel = P - R("X", st[f"h{s}alpha"]) @ (tr(hk) - hr(hk))
        lg = LEG["H" + s]
        knee, end, n, miss = ik2(head[th], heel, lg["l1"], lg["l2"], st[f"h{s}pole"])
        D[th] = map_rot(lg["d1"], lg["n"], knee - head[th], n)
        D[sh] = map_rot(lg["d2"], lg["n"], end - knee, n)
        D[hk] = map_rot((tr(hk) - hr(hk)), lg["n"], P - end, n)
        D[hp] = Dpaw
        place(sh); place(hk); place(hp)
        diag["H" + s + "miss"] = miss
        diag["H" + s + "knee"] = knee
    return D, hips_d, diag, head


_prevq = {}


def apply_state(st):
    D, hips_d, diag, _ = solve(st)
    for pb in PB:
        n = pb.name
        par = BD[n].parent
        Dp = D[par.name] if par else I3
        r = rest3(n)
        q = (r.inverted() @ Dp.inverted() @ D[n] @ r).to_quaternion()
        if n in _prevq and q.dot(_prevq[n]) < 0:
            q = -q
        _prevq[n] = q.copy()
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = q
        pb.location = (0, 0, 0)
        pb.scale = (1, 1, 1)
    PB["Hips"].location = rest3("Hips").inverted() @ hips_d
    return diag


# ---------------------------------------------------------------- the one SIT pose
SIT_SCAP = Vector((0.0, 0.56, 1.93))      # where the scapula heads sit: shoulders straight over the planted forepaws
SIT_HEEL = {"L": Vector((0.06, -0.06, 0.0)), "R": Vector((0.06, 0.02, 0.0))}   # heel from the hip joint (x out)
SIT_ALPHA = 72.0                         # hock pivot: metatarsus flat on the floor
SIT_HP, SIT_SPINE = 56.0, (39.0, 35.0, 33.0)   # pelvis pitch; Spine1/Spine2/Chest world pitch
SIT_POLE = Vector((0.2, 1.0, 0.3))      # knee direction (x outward)
SIT_FORE = (1.0, 22.0)          # forearm / upper-arm lean (deg)
SIT_NECK = -22.0                 # neck pitch on the chest (head stays level: its orientation is absolute)
# tail (yaw, elevation, roll) per segment: lies on the floor curling round to her right. The tail mesh hangs in front
# of its bones, so the bones arch over it while the mesh rests on the floor (found with an exact-skinning search, dev
# tool tailopt in the review folder: every segment's mesh touches the floor, <= 35 deg between segments, clear of the
# hind legs). SWEEP_TAIL is the other end of the Sit loop's floor sweep.
SIT_TAIL = ((14.7, 40.4, -97.5), (39.0, 13.0, -61.8), (60.5, -13.7, -63.3), (88.6, -30.8, -93.3))
SWEEP_TAIL = ((-5.0, 40.3, -81.2), (-10.0, 12.8, -59.5), (-15.0, -13.8, -66.4), (-20.0, -29.8, -92.9))


def arm_targets(s, lean_fore=1.0, lean_upper=8.0):
    """Shoulder target and pole for a front leg whose forearm is `lean_fore` deg off vertical (top back) over the
    planted wrist, with the upper arm `lean_upper` deg forward of vertical from the elbow."""
    fp = "FrontPaw" + s
    W = hr(fp)
    E = W + LEG["F" + s]["l2"] * Vector((0.0, -math.sin(math.radians(lean_fore)), math.cos(math.radians(lean_fore))))
    S = E + LEG["F" + s]["l1"] * Vector((0.0, math.sin(math.radians(lean_upper)), math.cos(math.radians(lean_upper))))
    u = (W - S).normalized()
    pole = (E - S) - u * (E - S).dot(u)
    S.x = hr("UpperArm" + s).x
    return S, pole.normalized() if pole.length > 1e-6 else Vector((0, -1, 0))


REST_SCAP = (hr("ScapulaL") + hr("ScapulaR")) * 0.5


def place_body(st, scap):
    """Set the hips translation so the scapula heads (mid point) land on `scap`: the forelegs stay in reach and the
    body pivots over them while the pitches change."""
    st.update(hx=0.0, hy=0.0, hz=0.0)
    head = solve(st)[3]
    d = scap - (head["ScapulaL"] + head["ScapulaR"]) * 0.5
    st["hx"], st["hy"], st["hz"] = d.x, d.y, d.z


def hind_toe_for_heel(s, heel, alpha):
    """Toe position that puts the heel at `heel` with the hock pivoted by alpha and the paw flat."""
    hk, hp = "Hock" + s, "HindPaw" + s
    return heel + R("X", alpha) @ (tr(hk) - hr(hk)) + (tr(hp) - hr(hp))


def sit_state():
    """The one SIT pose: sitting tall. Rump on the floor with the pelvis tipped down-back, hind legs folded forward
    under the body with the hocks flat, forelegs straight and near-vertical on their rest spots, chest up, head
    level, tail lying on the floor curled round to her right."""
    st = rest_state()
    w1, w2, w3 = SIT_SPINE
    st.update(hp=SIT_HP, s1p=w1 - SIT_HP, s2p=w2 - w1, cp=w3 - w2, np=SIT_NECK, headp=5.0, earb=-2.0)
    for s in "LR":
        st[f"f{s}sh"], st[f"f{s}pole"] = arm_targets(s, *SIT_FORE)
    place_body(st, SIT_SCAP)             # the chest sits where the scapulae can reach the shoulder targets
    head = solve(st)[3]
    for s, sx in (("L", -1), ("R", 1)):
        heel = head["Thigh" + s] + Vector((sx * SIT_HEEL[s].x, SIT_HEEL[s].y, 0.0))
        heel.z = hr("HindPaw" + s).z - (R("X", SIT_ALPHA) @ (tr("Hock" + s) - hr("Hock" + s))).z
        st[f"h{s}toe"] = hind_toe_for_heel(s, heel, SIT_ALPHA)
        st[f"h{s}toe"].z = tr("HindPaw" + s).z
        st[f"h{s}alpha"] = SIT_ALPHA
        st[f"h{s}pole"] = Vector((sx * SIT_POLE.x, SIT_POLE.y, SIT_POLE.z))
    # tail: lies on the floor behind her, curling round to her right (settle_tail is a no-op safety net here)
    for i, (y, e, b) in enumerate(SIT_TAIL, 1):
        st[f"t{i}y"], st[f"t{i}e"], st[f"t{i}b"] = y, e, b
    settle_tail([st])
    return st


# ---------------------------------------------------------------- timing helpers
def seg(t, a, b):
    return 0.0 if t <= a else 1.0 if t >= b else (t - a) / (b - a)


def smooth(x):                       # smootherstep: zero velocity and acceleration at both ends
    return x * x * x * (x * (6 * x - 15) + 10)


def win(t, a, b):                    # smooth 0 -> 1 between a and b
    return smooth(seg(t, a, b))


def bump(t, a, b):                   # smooth 0 -> 1 -> 0 over [a, b], flat ends
    return math.sin(math.pi * seg(t, a, b)) ** 2


def group(k):
    if k in ("hx", "hy", "hz", "hp", "hr", "hyaw"):
        return k
    if k[:2] in ("s1", "s2") or k in ("cp", "cr", "cy"):
        return "spine"
    if k in ("np", "nr", "ny"):
        return "neck"
    if k.startswith("head") or k.startswith("ear"):
        return "head"
    if k[0] == "t":                  # tail{i}e = elevation, tail{i}y = yaw + roll
        return "tail" + k[1] + ("e" if k[2] == "e" else "y")
    if k[0] == "f":
        return "fsh" if k.endswith("sh") else "fpole" if k.endswith("pole") else "fpaw"
    return "h" + k[1] + ("alpha" if k.endswith("alpha") else "pole" if k.endswith("pole") else "toe")


def timed(a, b, t, windows):
    """Blend a -> b with a per-group time window {group: (start, end)} (missing group -> (0, 1))."""
    def w(k):
        lo, hi = windows.get(group(k), (0.0, 1.0))
        return win(t, lo, hi)
    return mix(a, b, w)


def vadd(st, key, v):
    st[key] = st[key] + v


def tail_path(st, A, M, B, t, a, b, lag):
    """Tail follow-through along a smooth arc A -> (control M) -> B; segment i runs `lag` later than its parent."""
    for i in range(1, 5):
        u = win(t, a + lag * (i - 1), b + lag * (i - 1))
        for k in ("y", "e", "b"):
            key = f"t{i}{k}"
            st[key] = (1 - u) ** 2 * A[key] + 2 * u * (1 - u) * M[i - 1][" yeb".index(k) - 1] + u * u * B[key]


def step(st, s, a, b, t, frm, to, lift=0.17):
    """Hind paw s steps from toe `frm` to `to` between t=a and t=b: quick lift, long carry, quick set-down; it only
    travels while the toe is well clear of the floor (no sliding), toes droop a little in the air."""
    u = seg(t, a, b)
    up = smooth(seg(u, 0.0, 0.25)) * (1.0 - smooth(seg(u, 0.75, 1.0)))
    k = smooth(seg(u, 0.15, 0.85))
    st[f"h{s}toe"] = frm.lerp(to, k) + Vector((0.0, 0.0, lift * up))
    st[f"h{s}pp"] += -10.0 * up
    return up


def hock_gap(st, s, head=None):
    """Angle (deg, in the side plane, seen from the paw joint) between the hip joint and the heel. Small = the heel is
    tucked up against the hip and the knee IK flips; SIT and REST both keep it above ~20 deg."""
    head = head or solve(st)[3]
    hp = "HindPaw" + s
    P = st[f"h{s}toe"] - R("X", st[f"h{s}pp"]) @ (tr(hp) - hr(hp))
    hip = head["Thigh" + s] - P
    return HOCK0[s] + st[f"h{s}alpha"] - math.degrees(math.atan2(hip.z, hip.y))


HOCK0 = {s: math.degrees(math.atan2(-(tr("Hock" + s) - hr("Hock" + s)).z, -(tr("Hock" + s) - hr("Hock" + s)).y))
         for s in "LR"}


def hock_follow(st, gaps):
    """Drive the hock angle from where the hip joint is: keeps the heel-to-hip gap at gaps[s] (deg), so the hock
    folds and unfolds with the rump instead of on its own clock (no knee flips when a paw steps under the body)."""
    head = solve(st)[3]
    for s in "LR":                   # never past the SIT angle: beyond flat the heel would dig into the floor
        st[f"h{s}alpha"] = min(SIT_ALPHA, st[f"h{s}alpha"] + gaps[s] - hock_gap(st, s, head))


FLARE = 0.4                     # knee swing-out while a folded hind leg passes under the belly


def flare(st, s, w):
    """Swing the knee out to the side (w 0..1) while the folded hind leg passes under the belly."""
    st[f"h{s}pole"] = st[f"h{s}pole"] + Vector(((1 if s == "R" else -1) * FLARE * w, 0.0, 0.0))


# ---------------------------------------------------------------- clips
TAIL_MID_DOWN = ((8, -5, -80), (20, -5, -60), (40, -5, -50), (60, -5, -50))     # arc control points (yaw, elev, roll)
TAIL_MID_UP = ((10, 5, -70), (25, -5, -60), (40, -15, -60), (55, -20, -60))


def sitdown_pose(REST, SIT, t):
    st = timed(REST, SIT, t, {
        "hp": (0.12, 0.88), "spine": (0.12, 0.92),
        "neck": (0.18, 1.0), "head": (0.22, 1.0), "fsh": (0.10, 0.94), "fpole": (0.0, 0.8),
        "hLpole": (0.0, 0.7), "hRpole": (0.05, 0.75),
        "hLtoe": (2.0, 3.0), "hRtoe": (2.0, 3.0)})
    # the tail swings back out of the way while the rump comes down, then lies down and curls onto the floor
    tail_path(st, REST, TAIL_MID_DOWN, SIT, t, 0.10, 0.80, 0.05)
    step(st, "L", 0.08, 0.44, t, REST["hLtoe"], SIT["hLtoe"])   # the hind paws tuck forward as the rump goes down
    step(st, "R", 0.26, 0.62, t, REST["hRtoe"], SIT["hRtoe"])
    flare(st, "L", bump(t, 0.15, 1.0))
    flare(st, "R", bump(t, 0.30, 1.0))
    fwd = bump(t, 0.0, 0.45)                         # small forward weight shift onto the forelegs
    shift = Vector((0.0, 0.05 * fwd, -0.01 * fwd))
    for s in "LR":
        vadd(st, f"f{s}sh", shift)
    st["headp"] += 2.5 * fwd - 1.5 * bump(t, 0.6, 1.0)   # head stays up, a little nod as the rump lands
    st["s2p"] += 1.5 * bump(t, 0.74, 1.0)            # chest settles after the rump lands
    st["earb"] += 6.0 * bump(t, 0.3, 1.0)
    place_body(st, REST_SCAP.lerp(SIT_SCAP, win(t, 0.10, 0.92)) + shift)
    hock_follow(st, {s: GAP_REST[s] + (GAP_SIT[s] - GAP_REST[s]) * win(t, 0.12, 0.88) + 18.0 * bump(t, 0.1, 0.95)
                     for s in "LR"})
    return st


def sit_loop_pose(SIT, p):
    st = dict(SIT)
    b = math.sin(2 * math.pi * 2 * p)                # two slow breaths: the ribcage lifts, the head stays put
    st["s1p"] += 0.4 * b
    st["s2p"] += 0.6 * b
    st["cp"] += 1.0 * b
    st["np"] -= 2.8 * b
    st["hz"] += 0.004 * b
    st["earb"] -= 1.0 * b

    def sweep(lag):                                  # two floor sweeps, flat (zero) near p = 0 and p = 1
        c = seg(p, 0.04 + lag, 0.86 + lag)
        return math.sin(math.pi * 2 * c) ** 2
    for i in range(1, 5):                            # the tail sweeps along the floor to behind her and back
        g = sweep(0.025 * (i - 1))
        for j, k in enumerate("yeb"):
            st[f"t{i}{k}"] += (SWEEP_TAIL[i - 1][j] - SIT[f"t{i}{k}"]) * g
    g0 = sweep(0.0)
    st["hyaw"] += 1.0 * g0                           # the rump wiggles a little with the tail
    st["s1y"] -= 1.0 * g0
    tilt = bump(p, 0.36, 0.78)                       # one gentle, curious head tilt
    st["headr"] += 10.0 * tilt
    st["heady"] -= 3.0 * tilt
    st["headp"] += 2.0 * tilt
    soft = bump(p, 0.30, 0.86)                       # ears soften back/out around it
    st["earb"] += 12.0 * soft
    st["earo"] += 7.0 * soft
    return st


def givepaw_pose(SIT, f):
    st = dict(SIT)
    shift = win(f, 1, 13) * (1 - win(f, 57, 70))     # weight to her left
    st["s1r"] -= 1.0 * shift
    st["s2r"] -= 2.0 * shift
    st["cr"] -= 2.5 * shift
    look = win(f, 5, 19) * (1 - win(f, 58, 70))      # look up at the person in front
    st["headp"] += 10.0 * look
    st["headr"] += 4.0 * look
    st["earb"] += 9.0 * look
    st["earo"] += 6.0 * look
    # right forepaw: heel-up pivot on the toe, lift forward/up, hold with a small shake, put down, roll flat
    toe_r = SIT["fRtoe"]
    # the offered paw continues the forearm, pad towards the hand (owner 2026-10-04: -36 left it hanging straight down)
    offer_toe, offer_phi = toe_r + Vector((0.05, 0.50, 0.86)), 28.0
    up = win(f, 12, 27) * (1 - win(f, 54, 66))       # 0 planted .. 1 offered
    pivot = win(f, 9, 14) * (1 - win(f, 64, 69))     # heel lifts first / rolls down last
    # the toe clears the floor first (no sliding), then the paw travels forward before it rises past the chest
    lift_z, lift_y = up, smooth(seg(up, 0.15, 0.8))
    shake = 0.0
    if 27 <= f <= 54:
        shake = math.sin(2 * math.pi * (f - 27) / 9.0) * bump(f, 26, 55)
    st["fRtoe"] = toe_r + Vector(((offer_toe.x - toe_r.x) * lift_y, (offer_toe.y - toe_r.y) * lift_y,
                                  (offer_toe.z - toe_r.z) * lift_z + 0.035 * shake + 0.03 * pivot))
    st["fRphi"] = -18.0 * pivot + (offer_phi + 18.0) * up + 3.0 * shake
    st["fRpole"] = SIT["fRpole"].lerp(Vector((0.0, -0.35, -1.0)), up).normalized()
    vadd(st, "fRsh", Vector((0.0, 0.14, 0.03)) * win(f, 11, 22) * (1 - win(f, 60, 69)))   # shoulder leads, lags back
    return st


def standup_pose(REST, SIT, t):
    st = timed(SIT, REST, t, {
        "hp": (0.04, 0.80), "spine": (0.04, 0.84), "neck": (0.15, 1.0), "head": (0.2, 1.0), "fsh": (0.08, 0.9), "fpole": (0.2, 1.0),
        "hLpole": (0.15, 0.8), "hRpole": (0.2, 0.85), "hLtoe": (2.0, 3.0), "hRtoe": (2.0, 3.0)})
    tail_path(st, SIT, TAIL_MID_UP, REST, t, 0.02, 0.80, 0.06)   # lifts off the floor first, then hangs
    step(st, "L", 0.22, 0.60, t, SIT["hLtoe"], REST["hLtoe"])   # the hind paws step back as the rump rises
    step(st, "R", 0.46, 0.86, t, SIT["hRtoe"], REST["hRtoe"])
    flare(st, "L", bump(t, 0.0, 0.6))
    flare(st, "R", bump(t, 0.0, 0.8))
    fwd = bump(t, 0.0, 0.5)                          # weight forward over the forelegs to unload the rump
    shift = Vector((0.0, 0.07 * fwd, 0.0))
    for s in "LR":
        vadd(st, f"f{s}sh", shift)
    st["headp"] -= 2.0 * fwd
    for i in range(1, 5):                            # tail swings a touch past hanging, then settles
        st[f"t{i}e"] -= (3.0 + 2.0 * i) * bump(t, 0.55 + 0.04 * i, 1.0)
    place_body(st, SIT_SCAP.lerp(REST_SCAP, win(t, 0.06, 0.86)) + shift)
    hock_follow(st, {s: GAP_SIT[s] + (GAP_REST[s] - GAP_SIT[s]) * win(t, 0.04, 0.80) + 18.0 * bump(t, 0.02, 0.9)
                     for s in "LR"})
    return st


def key_state(st, frame):
    apply_state(st)
    L.key(frame)


def run_clip(name, REST, SIT, loop, priority):
    act = L.new_action(name)
    L.reset()
    _prevq.clear()
    states = clip_states(name, REST, SIT)
    settle_tail(states, loop, pin=(True, True))
    for f, st in enumerate(states, 1):
        key_state(st, f)
    n = len(states)
    L.finish(act, 1, n, loop)
    act["luna_priority"] = priority
    return act


CLIPS = {"SitDown": 30, "Sit": 90, "GivePaw": 70, "StandUp": 24}
GAP_REST, GAP_SIT = {}, {}


def clip_states(name, REST, SIT):
    """Unsettled per-frame states of a clip."""
    for s in "LR":
        GAP_REST[s], GAP_SIT[s] = hock_gap(REST, s), hock_gap(SIT, s)
    n = CLIPS[name]
    fn = {"SitDown": lambda t, f: sitdown_pose(REST, SIT, t), "Sit": lambda t, f: sit_loop_pose(SIT, t),
          "GivePaw": lambda t, f: givepaw_pose(SIT, f), "StandUp": lambda t, f: standup_pose(REST, SIT, t)}[name]
    return [fn((f - 1) / (n - 1), f) for f in range(1, n + 1)]


def build():
    L.reset()
    REST, SIT = rest_state(), sit_state()
    for name, loop in (("SitDown", False), ("Sit", True), ("GivePaw", False), ("StandUp", False)):
        run_clip(name, REST, SIT, loop, "Action")
    if ARM.animation_data:
        ARM.animation_data.action = None
    L.reset()


if __name__ == "__main__":
    import sys, bpy; a = sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []; build()
    if a: bpy.ops.wm.save_as_mainfile(filepath=a[0])
