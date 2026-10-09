# blender -b <luna_anim.blend> -P check_clips.py -- [out.json] [action,action,...]
# Numeric QA for Luna's actions: ground penetration/floating, planted-paw sliding, loop seams, clip-to-clip continuity.
import bpy, sys, json, math
from mathutils import Quaternion

sys.path.insert(0, __import__("os").path.dirname(__file__))
import lunalib as L

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
out_path = argv[0] if argv else None
only = set(argv[1].split(",")) if len(argv) > 1 else None
PAWS = ("FrontPawL", "FrontPawR", "HindPawL", "HindPawR")
CONTACT_Z = 0.12
# (from clip, at end?) -> (to clip, at start?) ; None = the rest pose
CONTINUITY = [("SitDown", "end", "Sit", "start"), ("Sit", "end", "GivePaw", "start"), ("GivePaw", "end", "Sit", "start"),
              ("Sit", "end", "StandUp", "start"), ("StandUp", "end", None, None), (None, None, "SitDown", "start"),
              (None, None, "LieDown", "start"), ("LieDown", "end", "Sleep", "start"), ("Sleep", "end", "WakeUp", "start"),
              ("WakeUp", "end", None, None), (None, None, "Idle", "start"),
              # belly-up group (2026-10-04 evening): she rolls over in front of a player for a belly rub
              (None, None, "RollOver", "start"), ("RollOver", "end", "BellyUp", "start"),
              ("BellyUp", "end", "BellyRub", "start"), ("BellyRub", "end", "BellyUp", "start"),
              ("BellyUp", "end", "RollUp", "start"), ("RollUp", "end", None, None)]


def actions():
    return [a for a in bpy.data.actions if "luna_loop" in a and (only is None or a.name in only)]


def bind(act):
    L.ARM.animation_data_create()
    L.ARM.animation_data.action = act
    if hasattr(L.ARM.animation_data, "action_slot") and act.slots:
        L.ARM.animation_data.action_slot = act.slots[0]


def pose_at(act, frame):
    bind(act); bpy.context.scene.frame_set(frame)
    return {pb.name: Quaternion(pb.rotation_quaternion) for pb in L.ARM.pose.bones}, tuple(L.ARM.pose.bones["Hips"].location)


def rest_pose():
    if L.ARM.animation_data:
        L.ARM.animation_data.action = None
    L.reset()
    return {pb.name: Quaternion((1, 0, 0, 0)) for pb in L.ARM.pose.bones}, (0.0, 0.0, 0.0)


def max_angle(a, b):
    worst, name = 0.0, None
    for k in a[0]:
        d = math.degrees(a[0][k].rotation_difference(b[0][k]).angle)
        d = min(d, 360 - d)
        if d > worst:
            worst, name = d, k
    dl = math.dist(a[1], b[1])
    return round(worst, 2), name, round(dl, 3)


report = {}
for act in actions():
    f0, f1 = int(act.frame_range[0]), int(act.frame_range[1])
    ref = float(act.get("luna_ref_speed", 0.0))
    bind(act)
    minz, slide, prev = [], {p: 0.0 for p in PAWS}, None
    for f in range(f0, f1 + 1):
        bpy.context.scene.frame_set(f)
        minz.append(L.mesh_min_z())
        paws = {p: L.bone_world(p, "tail") for p in PAWS}
        if prev:
            for p in PAWS:
                if paws[p].z < CONTACT_Z and prev[p].z < CONTACT_Z:
                    expected_dy = -ref / L.FPS            # in-place: a planted paw drifts backward at the ref speed
                    err = math.hypot(paws[p].x - prev[p].x, (paws[p].y - prev[p].y) - expected_dy)
                    slide[p] = max(slide[p], err * L.FPS)  # studs/s of unexplained paw motion
        prev = paws
    entry = {"frames": f1 - f0 + 1, "loop": bool(act["luna_loop"]), "ref_speed": ref,
             "min_z": round(min(minz), 3), "max_of_frame_min_z": round(max(minz), 3),
             "paw_slide_studs_per_s": {p: round(v, 2) for p, v in slide.items()}}
    if act["luna_loop"]:
        entry["loop_seam_deg_bone_dloc"] = max_angle(pose_at(act, f0), pose_at(act, f1))
    report[act.name] = entry
byname = {a.name: a for a in bpy.data.actions if "luna_loop" in a}
cont = []
for a, ae, b, be in CONTINUITY:
    if (a and a not in byname) or (b and b not in byname):
        continue
    pa = rest_pose() if a is None else pose_at(byname[a], int(byname[a].frame_range[1 if ae == "end" else 0]))
    pb = rest_pose() if b is None else pose_at(byname[b], int(byname[b].frame_range[1 if be == "end" else 0]))
    cont.append({"from": f"{a or 'REST'}:{ae or ''}", "to": f"{b or 'REST'}:{be or ''}", "max_deg_bone_dloc": max_angle(pa, pb)})
report["_continuity"] = cont
text = json.dumps(report, indent=1)
print("CHECK", text)
if out_path:
    open(out_path, "w").write(text)
