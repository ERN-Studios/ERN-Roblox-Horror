"""Level 6 entity ("The Counter"): author every animation on Meshy's rig, render previews, export FBX.

Run from the repo root, after build_base.py:
  Blender -b --python tools/level6_entity/build_animations.py -- [--no-video] [--only=Idle,Catch]

Conventions (armature space, metres): Z up, the doll faces -Y, its left is +X, rest pose is a T-pose.
Every bone is posed by a "relative delta" D: a rotation expressed in the REST armature axes and applied
in the parent's posed frame. So Rx(+) on the head nods down, Rz(+) turns it to its left, Ry(+) tilts it
to its left, whatever the body below is doing. Legs and hips of the walk and run come from Meshy's two
clips (SRC_Walk, SRC_Run); everything else is written here.
"""
import bpy, os, sys, math, json
from mathutils import Matrix, Vector

ROOT = os.path.abspath("artifacts/level6-entity-20261003")
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
NO_VIDEO = "--no-video" in argv
ONLY = next((a.split("=", 1)[1].split(",") for a in argv if a.startswith("--only=")), None)
FPS = 30

bpy.ops.wm.open_mainfile(filepath=os.path.join(ROOT, "blend", "counter_base.blend"))
scene = bpy.context.scene
scene.render.fps = FPS
arm = bpy.data.objects["CounterRig"]
mesh = bpy.data.objects["CounterDoll"]

def depth(b):
    n = 0
    while b.parent:
        b = b.parent; n += 1
    return n
ORDER = [b.name for b in sorted(arm.data.bones, key=depth)]
REST = {b.name: b.matrix_local.to_3x3() for b in arm.data.bones}
HEAD = {b.name: b.head_local.copy() for b in arm.data.bones}
PARENT = {b.name: (b.parent.name if b.parent else None) for b in arm.data.bones}
I3 = Matrix.Identity(3)

def Rx(d): return Matrix.Rotation(math.radians(d), 3, "X")
def Ry(d): return Matrix.Rotation(math.radians(d), 3, "Y")
def Rz(d): return Matrix.Rotation(math.radians(d), 3, "Z")
def clamp(x, a=0.0, b=1.0): return max(a, min(b, x))
def smooth(x):
    x = clamp(x); return x * x * (3 - 2 * x)
def step(t, t0, dur=0.1): return smooth((t - t0) / dur)
TAU = math.tau


class Pose:
    def __init__(self):
        self.D = {}
        self.hips = Vector((0, 0, 0))

    def copy(self):
        p = Pose(); p.D = {k: v.copy() for k, v in self.D.items()}; p.hips = self.hips.copy(); return p

    def get(self, b): return self.D.get(b, I3)
    def pre(self, b, m): self.D[b] = m @ self.get(b)


def fk(p):
    A, P = {}, {}
    for b in ORDER:
        par = PARENT[b]
        if par is None:
            A[b] = p.get(b); P[b] = HEAD[b] + p.hips
        else:
            A[b] = A[par] @ p.get(b)
            P[b] = P[par] + A[par] @ (HEAD[b] - HEAD[par])
    return A, P


def ik(p, upper, lower, end, target, pole, end_abs=None):
    """Analytic two-bone IK: put `end`'s joint on `target`, bending towards `pole` (a direction)."""
    A, P = fk(p)
    S = P[upper]
    u_rest = HEAD[lower] - HEAD[upper]; l_rest = HEAD[end] - HEAD[lower]
    L1, L2 = u_rest.length, l_rest.length
    d = target - S
    dist = clamp(d.length, abs(L1 - L2) * 1.02, (L1 + L2) * 0.999)
    dirv = d.normalized()
    a = (L1 * L1 - L2 * L2 + dist * dist) / (2 * dist)
    h = math.sqrt(max(L1 * L1 - a * a, 0.0))
    pp = pole - dirv * pole.dot(dirv); pp.normalize()
    E = S + dirv * a + pp * h
    T = S + dirv * dist
    Qu = u_rest.rotation_difference(E - S).to_matrix()
    Ql = (Qu @ l_rest).rotation_difference(T - E).to_matrix() @ Qu
    p.D[upper] = A[PARENT[upper]].inverted() @ Qu
    p.D[lower] = Qu.inverted() @ Ql
    if end_abs is not None:
        p.D[end] = Ql.inverted() @ end_abs


def basis(f, n):
    f = f.normalized(); n = (n - f * n.dot(f)).normalized()
    m = Matrix((f, n, f.cross(n))); m.transpose(); return m


def blend(a, b, s):
    p = Pose()
    for name in ORDER:
        qa = a.get(name).to_quaternion(); qb = b.get(name).to_quaternion()
        p.D[name] = qa.slerp(qb, s).to_matrix()
    p.hips = a.hips.lerp(b.hips, s)
    return p


# ---- Meshy source clips -----------------------------------------------------------------------
SRC = {"SRC_Walk": 31.0, "SRC_Run": 19.0}  # loop period in frames (the last key repeats the first)
_cache = {}
def sample(action, phase):
    key = (action, round(phase % 1.0, 5))
    if key not in _cache:
        if arm.animation_data is None: arm.animation_data_create()
        arm.animation_data.action = bpy.data.actions[action]
        f = 1.0 + (phase % 1.0) * SRC[action]
        scene.frame_set(int(math.floor(f)), subframe=f - math.floor(f))
        p = Pose()
        for pb in arm.pose.bones:
            R = REST[pb.name]
            p.D[pb.name] = R @ pb.rotation_quaternion.to_matrix() @ R.inverted()
        p.hips = REST["Hips"] @ (Vector(arm.pose.bones["Hips"].location) * 0.01)  # source is in cm
        _cache[key] = p
    return _cache[key].copy()

LOWER = ["Hips", "Spine02", "Spine01", "Spine", "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase",
         "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase"]
def lower_body(action, phase):
    b = sample(action, phase)
    p = Pose(); p.hips = b.hips
    for n in LOWER: p.D[n] = b.D[n]
    return p, b

def pitch(m): return math.degrees(m.to_euler("XYZ").x)


# ---- building blocks --------------------------------------------------------------------------
def arms_down(p, down=74.0, elbow=14.0, swing_l=0.0, swing_r=0.0):
    p.D["LeftArm"] = Rx(swing_l) @ Ry(down)
    p.D["RightArm"] = Rx(swing_r) @ Ry(-down)
    p.D["LeftForeArm"] = Rz(-elbow)
    p.D["RightForeArm"] = Rz(elbow)
    p.D["LeftHand"] = Rz(-8); p.D["RightHand"] = Rz(8)

def head(p, yaw=0.0, nod=4.0, tilt=9.0, share=0.35):
    for b, s in (("neck", share), ("Head", 1 - share)):
        p.D[b] = Rz(yaw * s) @ Rx(nod * s) @ Ry(tilt * s)

def tw(t, t0, hold=0.13):
    """Twitch envelope: snap out in 0.05 s, shiver while held, snap back past zero and settle."""
    x = t - t0
    if x < 0 or x > 0.05 + hold + 0.15: return 0.0
    if x < 0.05: return x / 0.05
    if x < 0.05 + hold: return 1.0 + 0.14 * math.sin(x * 95)
    y = (x - 0.05 - hold) / 0.15
    return 1.0 - 1.25 * y / 0.4 if y < 0.4 else -0.25 * (1 - (y - 0.4) / 0.6)

EYE = {"Left": Vector((0.036, -0.115, 1.02)), "Right": Vector((-0.036, -0.115, 1.02))}
def cover_eyes(p):
    """Both palms over the eyes, following wherever the head currently is."""
    A, P = fk(p)
    Ah, Ph = A["Head"], P["Head"]
    for side, sx in (("Left", 1.0), ("Right", -1.0)):
        fingers = Vector((-0.30 * sx, 0.0, 0.954))            # up and inwards
        wrist = EYE[side] - fingers * 0.07 + Vector((0.012 * sx, -0.014, 0.0))
        target = Ph + Ah @ (wrist - HEAD["Head"])
        rest_b = basis(Vector((sx, 0, 0)), Vector((0, 0, -1)))  # fingers along the arm, palm down
        want_b = basis(Ah @ fingers, Ah @ Vector((0, 1, 0)))    # palm towards the face
        ik(p, side + "Arm", side + "ForeArm", side + "Hand", target,
           Vector((0.55 * sx, -0.15, -1.0)), end_abs=want_b @ rest_b.transposed())


# ---- clips ------------------------------------------------------------------------------------
def idle(i, N=120):
    t = i / FPS
    p = Pose()
    sway = math.sin(TAU * t / 4)
    p.D["Spine02"] = Ry(1.6 * sway)
    p.D["Spine01"] = Rx(1.5 + 1.0 * math.sin(TAU * t / 2))
    arms_down(p, 74 + 1.5 * math.sin(TAU * t / 2), 14, swing_l=1.5 * sway, swing_r=-1.5 * sway)
    a, b = tw(t, 1.4), tw(t, 3.0, 0.2)
    head(p, yaw=6 * sway + 20 * a - 26 * b, nod=4 - 5 * b, tilt=9 - 26 * a + 15 * b)
    return p

def count_pose(t):
    p = Pose()
    beat = max(0.0, math.sin(TAU * t)) ** 2            # one nod per second, in time with the count
    p.D["Spine02"] = Ry(2.5 * math.sin(math.pi * t))
    p.D["Spine01"] = Rx(7 + 2 * beat)
    head(p, yaw=0, nod=9 + 6 * beat, tilt=3 * math.sin(math.pi * t))
    cover_eyes(p)
    return p

def count_loop(i, N=60): return count_pose(i / FPS)

def count_start(i, N=24):
    return blend(idle(0), count_pose(0), smooth(i / (N - 4)))

def count_end(i, N=45):
    t = i / FPS
    p = blend(count_pose(0), idle(0), step(t, 0.0, 0.2))     # the hands drop fast
    up = step(t, 0.05, 0.12) - step(t, 0.9, 0.5)
    k = tw(t, 0.42, 0.22)
    p.pre("Head", Rz(-14 * k) @ Rx(-13 * up) @ Ry(-30 * k))
    p.pre("Spine01", Rx(-5 * up))
    return p

def walk_wander(i, N=120):
    t = i / FPS
    p, b = lower_body("SRC_Walk", i / 40.0)                   # 3 stiff cycles in 4 s
    p.pre("Spine01", Rx(5))
    arms_down(p, 72, 16, swing_l=0.32 * pitch(b.D["RightUpLeg"]), swing_r=0.32 * pitch(b.D["LeftUpLeg"]))
    a, b2, c, d = tw(t, 0.7), tw(t, 2.0, 0.06), tw(t, 2.27, 0.1), tw(t, 3.2, 0.18)
    head(p, yaw=18 * math.sin(TAU * t / 4) + 24 * a - 34 * d,
         nod=3 - 8 * d + 5 * (b2 + c),
         tilt=10 - 32 * a + 16 * (b2 + c) - 6 * d)
    return p

def search_look(i, N=105):
    t = i / FPS
    p = idle(0)
    env = step(t, 0.1, 0.35) - step(t, 2.9, 0.5)
    p.pre("Spine02", Rx(9 * env)); p.pre("Spine01", Rx(7 * env))
    yaw = 55 * step(t, 0.45, 0.09) - 118 * step(t, 1.6, 0.1) + 63 * step(t, 2.95, 0.3)
    k = tw(t, 1.05, 0.16)
    flip = step(t, 2.2, 0.07) - step(t, 2.95, 0.3)
    head(p, yaw=yaw + 10 * k, nod=4 + 9 * env, tilt=9 - 30 * k - 26 * flip)
    arms_down(p, 74 - 10 * env, 14 + 18 * env)               # arms lift away as it leans in
    return p

def run_chase(i, N=38):
    ph = i / 19.0
    p, b = lower_body("SRC_Run", ph)
    p.pre("Spine01", Rx(9))
    s = math.sin(TAU * ph)
    p.D["LeftArm"] = Rz(-80) @ Ry(6 + 7 * s)
    p.D["RightArm"] = Rz(80) @ Ry(-(6 - 7 * s))
    p.D["LeftForeArm"] = Ry(-22 - 6 * s); p.D["RightForeArm"] = Ry(22 - 6 * s)
    p.D["LeftHand"] = Ry(-28); p.D["RightHand"] = Ry(28)
    jit = math.sin(TAU * 7 * i / N)
    head(p, yaw=3 * jit, nod=-14, tilt=22 + 5 * jit)
    return p

def spotted(i, N=30):
    t = i / FPS
    p = idle(0)
    jolt = step(t, 0.06, 0.07)
    p.pre("Spine01", Rx(-7 * jolt))
    head(p, yaw=0, nod=4 - 9 * jolt, tilt=9 - 36 * jolt + 3 * math.sin(i * 2.6) * jolt)
    s = step(t, 0.22, 0.14)
    aim = Pose(); aim.D["RightArm"] = Rz(84) @ Ry(4); aim.D["RightForeArm"] = Rz(4); aim.D["RightHand"] = I3
    for n in ("RightArm", "RightForeArm", "RightHand"):
        p.D[n] = p.get(n).to_quaternion().slerp(aim.get(n).to_quaternion(), s).to_matrix()
    p.pre("RightArm", Ry(2.2 * math.sin(i * 2.6) * s))        # the pointing arm trembles
    return p

def catch(i, N=36):
    t = i / FPS
    s = step(t, 0.0, 0.16)
    grab = step(t, 0.26, 0.08)
    p = Pose()
    p.hips = Vector((0, -0.20 * s, -0.075 * s))
    p.D["Spine02"] = Rx(14 * s); p.D["Spine01"] = Rx(14 * s)
    p.D["LeftArm"] = Rz(-80 - 4 * s) @ Ry(8 - 14 * s)
    p.D["RightArm"] = Rz(80 + 4 * s) @ Ry(-(8 - 14 * s))
    p.D["LeftForeArm"] = Rz(-(6 + 22 * grab)); p.D["RightForeArm"] = Rz(6 + 22 * grab)
    p.D["LeftHand"] = Rz(-25 * grab); p.D["RightHand"] = Rz(25 * grab)
    shake = clamp(1.6 * math.sin(TAU * 5 * t), -1, 1) * step(t, 0.3, 0.05)
    head(p, yaw=6 * shake, nod=-24 * s, tilt=9 + 24 * shake)
    # feet: left steps into the lunge, right stays planted
    flat = I3
    ik(p, "LeftUpLeg", "LeftLeg", "LeftFoot", HEAD["LeftFoot"] + Vector((0.02, -0.34 * s, 0.035 * math.sin(math.pi * s))),
       Vector((0.15, -1, 0)), end_abs=flat)
    ik(p, "RightUpLeg", "RightLeg", "RightFoot", HEAD["RightFoot"] + Vector((0, 0.0, 0.0)),
       Vector((-0.15, -1, 0)), end_abs=Rx(18 * s))
    return p

def head_twitch(i, N=14):
    t = i / FPS
    k = tw(t, 0.03, 0.12)
    p = Pose(); head(p, yaw=20 * k, nod=4 - 4 * k, tilt=9 - 34 * k)
    return p

HEAD_ONLY = ["neck", "Head"]
CLIPS = [
    # name, function, frames, loop, bones (None = all), Roblox priority, what it is for
    ("Idle", idle, 120, True, None, "Idle", "Standing still, slow sway, two head twitches."),
    ("Count_Start", count_start, 24, False, None, "Action", "Raises both hands over its eyes."),
    ("Count_Loop", count_loop, 60, True, None, "Action", "Hands over eyes, nods once per second while it counts."),
    ("Count_End", count_end, 45, False, None, "Action", "Hands drop, head snaps up and twitches: ready or not."),
    ("Walk_Wander", walk_wander, 120, True, None, "Movement", "Stiff walk while searching, head scans and twitches."),
    ("Search_Look", search_look, 105, False, None, "Action", "Stops at a hiding spot, leans in, looks left then right."),
    ("Spotted", spotted, 30, False, None, "Action", "Sees a player: jolts upright, head snaps over, points."),
    ("Run_Chase", run_chase, 38, True, None, "Movement", "Sprint with both arms reaching forward."),
    ("Catch", catch, 36, False, None, "Action4", "Lunge and grab with a shaking head, for the catch."),
    ("Head_Twitch", head_twitch, 14, False, HEAD_ONLY, "Action2", "Head and neck only, to layer over anything."),
]
if ONLY: CLIPS = [c for c in CLIPS if c[0] in ONLY]

# ---- compute, then key ------------------------------------------------------------------------
computed = {}
for name, fn, N, loop, bones, prio, note in CLIPS:
    computed[name] = [fn(i, N) for i in range(N + 1)]
    if loop:  # a loop has to close exactly
        a, b = computed[name][0], computed[name][-1]
        worst = max((a.get(n).to_quaternion().rotation_difference(b.get(n).to_quaternion()).angle for n in ORDER))
        print("LOOP %-12s end/start mismatch %.2f deg, hips %.4f m" % (name, math.degrees(worst), (a.hips - b.hips).length))

for a in list(bpy.data.actions):
    if not a.name.startswith("SRC_"): bpy.data.actions.remove(a)
arm.animation_data.action = None
for pb in arm.pose.bones:
    pb.rotation_mode = "QUATERNION"; pb.rotation_quaternion = (1, 0, 0, 0); pb.location = (0, 0, 0)

RINV = {n: REST[n].inverted() for n in ORDER}
for name, fn, N, loop, bones, prio, note in CLIPS:
    act = bpy.data.actions.new(name); act.use_fake_user = True
    arm.animation_data.action = act
    last = {}
    for i, p in enumerate(computed[name]):
        f = i + 1
        for n in (bones or ORDER):
            if n in ("head_end", "headfront"): continue
            pb = arm.pose.bones[n]
            q = (RINV[n] @ p.get(n) @ REST[n]).to_quaternion()
            if n in last and last[n].dot(q) < 0: q.negate()
            last[n] = q.copy()
            pb.rotation_quaternion = q
            pb.keyframe_insert("rotation_quaternion", frame=f)
            if n == "Hips":
                pb.location = RINV[n] @ p.hips
                pb.keyframe_insert("location", frame=f)
    print("KEYED", name, N + 1, "frames")

# ---- previews ---------------------------------------------------------------------------------
import numpy as np
R = os.path.join(ROOT, "renders"); os.makedirs(R, exist_ok=True)
cam = bpy.data.objects.new("QACam", bpy.data.cameras.new("QACam")); scene.collection.objects.link(cam)
cam.data.type = "ORTHO"; cam.data.ortho_scale = 1.75
scene.camera = cam
def aim(loc, at):
    cam.location = loc
    cam.rotation_euler = (Vector(at) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
world = bpy.data.worlds.new("QA"); world.color = (0.16, 0.17, 0.19); scene.world = world
scene.render.engine = "BLENDER_WORKBENCH"
sh = scene.display.shading
sh.light = "STUDIO"; sh.color_type = "TEXTURE"; sh.show_cavity = True
scene.render.film_transparent = False
W, H = 320, 420
scene.render.resolution_x = W; scene.render.resolution_y = H; scene.render.resolution_percentage = 100

def set_pose_defaults():
    for pb in arm.pose.bones:
        pb.rotation_quaternion = (1, 0, 0, 0); pb.location = (0, 0, 0)

VIEWS = {"front34": ((1.9, -3.3, 1.25), (0, -0.05, 0.70)), "side": ((-3.8, -0.1, 0.72), (0, -0.1, 0.70))}
tmp = os.path.join(R, "_tmp.png")
for name, fn, N, loop, bones, prio, note in CLIPS:
    set_pose_defaults()
    arm.animation_data.action = bpy.data.actions[name]
    cols = 8
    frames = [1 + round(k * N / (cols - 1)) for k in range(cols)] if N > cols else list(range(1, N + 2))[:cols]
    sheet = np.zeros((H * 2, W * len(frames), 4), dtype=np.float32)
    for r, view in enumerate(("front34", "side")):
        aim(*VIEWS[view])
        for c, f in enumerate(frames):
            scene.frame_set(f)
            scene.render.image_settings.file_format = "PNG"
            scene.render.filepath = tmp
            bpy.ops.render.render(write_still=True)
            img = bpy.data.images.load(tmp)
            px = np.array(img.pixels[:], dtype=np.float32).reshape(H, W, 4)
            sheet[(1 - r) * H:(2 - r) * H, c * W:(c + 1) * W] = px
            bpy.data.images.remove(img)
    out = bpy.data.images.new("sheet", W * len(frames), H * 2)
    out.pixels = sheet.ravel()
    out.filepath_raw = os.path.join(R, "sheet_%s.jpg" % name); out.file_format = "JPEG"
    out.save(); bpy.data.images.remove(out)
    print("SHEET", name, frames)
if os.path.exists(tmp): os.remove(tmp)

if not NO_VIDEO:
    aim(*VIEWS["front34"])
    scene.render.resolution_x = 480; scene.render.resolution_y = 640
    try:
        ims = scene.render.image_settings
        if hasattr(ims, "media_type"): ims.media_type = "VIDEO"
        ims.file_format = "FFMPEG"
        scene.render.ffmpeg.format = "MPEG4"; scene.render.ffmpeg.codec = "H264"
        scene.render.ffmpeg.constant_rate_factor = "MEDIUM"
        for name, fn, N, loop, bones, prio, note in CLIPS:
            set_pose_defaults()
            arm.animation_data.action = bpy.data.actions[name]
            scene.frame_start = 1; scene.frame_end = N if loop else N + 1
            scene.render.filepath = os.path.join(R, "preview_%s.mp4" % name)
            bpy.ops.render.render(animation=True)
            print("VIDEO", name)
    except Exception as e:
        print("VIDEO FAILED", repr(e))

# ---- exports ----------------------------------------------------------------------------------
X = os.path.join(ROOT, "export"); os.makedirs(X, exist_ok=True)
bpy.data.objects.remove(cam, do_unlink=True)
bpy.ops.object.select_all(action="DESELECT")
arm.select_set(True); mesh.select_set(True)
bpy.context.view_layer.objects.active = arm
common = dict(use_selection=True, add_leaf_bones=False, bake_anim_use_nla_strips=False,
              bake_anim_use_all_actions=False, bake_anim_step=1.0, bake_anim_simplify_factor=0.0,
              path_mode="COPY", embed_textures=True, mesh_smooth_type="FACE")
set_pose_defaults(); arm.animation_data.action = None; scene.frame_set(1)
bpy.ops.export_scene.fbx(filepath=os.path.join(X, "Counter_Model.fbx"), object_types={"ARMATURE", "MESH"},
                         bake_anim=False, **common)
mesh.select_set(False)
manifest = []
for name, fn, N, loop, bones, prio, note in CLIPS:
    set_pose_defaults()
    arm.animation_data.action = bpy.data.actions[name]
    scene.frame_start = 1; scene.frame_end = N + 1
    bpy.ops.export_scene.fbx(filepath=os.path.join(X, "Counter_Anim_%s.fbx" % name), object_types={"ARMATURE"},
                             bake_anim=True, bake_anim_use_all_bones=bones is None, **common)
    manifest.append({"name": name, "file": "Counter_Anim_%s.fbx" % name, "frames": N + 1, "fps": FPS,
                     "seconds": round(N / FPS, 3), "loop": loop, "bones": bones or "all",
                     "robloxPriority": prio, "use": note})
    print("FBX", name)
if not ONLY:
    json.dump({"rig": "Meshy 24-bone humanoid", "heightMetres": round(mesh.dimensions.z, 3),
               "triangles": sum(len(p.vertices) - 2 for p in mesh.data.polygons), "clips": manifest},
              open(os.path.join(X, "animations.json"), "w"), indent=1)
    arm.animation_data.action = bpy.data.actions["Idle"]
    scene.frame_start = 1; scene.frame_end = 120
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT, "blend", "counter_animated.blend"))
print("DONE")
