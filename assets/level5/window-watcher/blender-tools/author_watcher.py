"""Author the inspected 24-bone Meshy rig plus unweighted Root; no paid clips."""
from pathlib import Path
import sys, math
sys.path.insert(0, str(Path(__file__).resolve().parent))
import bpy
from mathutils import Vector, Quaternion, Matrix
from watcher_common import *

OUT = Path(__file__).resolve().parents[1]
import_asset(OUT / "prepared-rig.blend")
rig = get_rig()
mesh = bound_meshes(rig)[0]
required = {"Root", "Hips", "Spine02", "Spine01", "Spine", "neck", "Head",
            "LeftArm", "LeftForeArm", "LeftHand", "RightArm", "RightForeArm", "RightHand"}
assert required <= set(rig.pose.bones.keys())


def smooth(x):
    x = max(0, min(1, x))
    return x * x * (3 - 2 * x)


def world_delta(name, axis, degrees):
    pb = rig.pose.bones[name]
    q = Quaternion(Vector(axis), math.radians(degrees))
    origin = pb.matrix.translation.copy()
    pb.matrix = Matrix.Translation(origin) @ q.to_matrix().to_4x4() @ Matrix.Translation(-origin) @ pb.matrix
    bpy.context.view_layer.update()


def point(name):
    return rig.pose.bones[name].matrix.translation.copy()


def aim(name, child, target):
    pb = rig.pose.bones[name]
    head = point(name)
    q = (point(child) - head).normalized().rotation_difference((target - head).normalized())
    pb.matrix = Matrix.Translation(head) @ q.to_matrix().to_4x4() @ Matrix.Translation(-head) @ pb.matrix
    bpy.context.view_layer.update()


def arm_ik(side, wrist_target, pole):
    upper, lower, hand = side + "Arm", side + "ForeArm", side + "Hand"
    shoulder = point(upper)
    a = (point(lower) - shoulder).length
    b = (point(hand) - point(lower)).length
    direction = wrist_target - shoulder
    d = max(abs(a-b)+1e-5, min(direction.length, (a+b)*0.995))
    direction.normalize()
    along = (a*a - b*b + d*d) / (2*d)
    height = math.sqrt(max(0, a*a - along*along))
    bend = pole - shoulder
    bend = (bend - direction * bend.dot(direction)).normalized()
    elbow = shoulder + direction*along + bend*height
    aim(upper, lower, elbow)
    aim(lower, hand, shoulder + direction*d)


def key_all(frame):
    for pb in rig.pose.bones:
        pb.keyframe_insert(data_path="rotation_quaternion", frame=frame, group=pb.name)
        pb.keyframe_insert(data_path="location", frame=frame, group=pb.name)
        pb.keyframe_insert(data_path="scale", frame=frame, group=pb.name)


def base_pose(breath=0):
    reset_pose(rig)
    world_delta("LeftArm", (0,1,0), 35)
    world_delta("RightArm", (0,1,0), -35)
    world_delta("LeftForeArm", (1,0,0), -6)
    world_delta("RightForeArm", (1,0,0), -8)
    world_delta("Spine01", (1,0,0), .35 + breath*.25)
    world_delta("neck", (0,1,0), -1.8)
    world_delta("Head", (1,0,0), -1.0)


for name, (start,end) in CLIPS.items():
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    activate_action(rig, action)
    for frame in range(start,end+1):
        t = (frame - start)/FPS
        duration = (end-start)/FPS
        envelope = math.sin(math.pi*t/duration)**2
        base_pose(math.sin(t/duration*math.tau))
        if name == "WatchingIdle":
            world_delta("Spine", (1,0,0), math.sin(t/duration*math.tau)*.28)
            world_delta("Head", (0,1,0), 1.6*envelope)
            world_delta("neck", (0,0,1), .65*math.sin(t/duration*math.tau)*envelope)
        elif name == "SlowWindowLean":
            amount = smooth((t-.6)/1.7) * (1-smooth((t-3.4)/1.6))
            world_delta("Spine02", (1,0,0), 3.0*amount)
            world_delta("Spine01", (1,0,0), 4.0*amount)
            world_delta("Spine", (1,0,0), 2.5*amount)
            world_delta("neck", (0,1,0), 4.0*amount)
            world_delta("Head", (1,0,0), -3.5*amount)
        else:
            amount = smooth((t-.35)/.85) * (1-smooth((t-2.85)/1.15))
            world_delta("neck", (0,1,0), -2.0*amount)
            base_arm = {n:rig.pose.bones[n].rotation_quaternion.copy()
                        for n in ("RightArm","RightForeArm")}
            target = Vector((-.27, -.43, 1.78))
            pulse = sum(math.exp(-((t-center)/.07)**2) for center in (1.62,2.25))
            target.y -= .015*pulse
            arm_ik("Right", target, Vector((-.8,-.1,1.20)))
            for n,q in base_arm.items():
                rig.pose.bones[n].rotation_quaternion = q.slerp(rig.pose.bones[n].rotation_quaternion,amount)
            bpy.context.view_layer.update()
            hand = rig.pose.bones["RightHand"]
            q0 = hand.matrix.to_quaternion()
            # Actual Meshy hand +Y follows its fingers. +Y points upwards at glass.
            q1 = Quaternion(Vector((0,0,1)),math.radians(-60)) @ Matrix(((1,0,0),(0,0,-1),(0,1,0))).to_quaternion()
            q = q0.slerp(q1, amount)
            hand.matrix = Matrix.LocRotScale(hand.matrix.translation, q, Vector((1,1,1)))
            bpy.context.view_layer.update()
            world_delta("RightHand", (1,0,0), 4.0*pulse*amount)
            # Keep the complete deformed hand arc behind the same glass plane.
            # Reposition through the actual two-bone chain, preserving hand world
            # orientation, rather than translating a hand bone or stretching skin.
            for _ in range(3):
                evaluated=mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
                front=min((evaluated.matrix_world@v.co).y for v in evaluated.data.vertices)
                if front >= -.524:break
                hand_world=rig.pose.bones["RightHand"].matrix.copy()
                wrist=hand_world.translation.copy()
                wrist.y += -.524-front+.0005
                arm_ik("Right",wrist,point("RightForeArm"))
                hand=rig.pose.bones["RightHand"]
                hand.matrix=Matrix.LocRotScale(hand.matrix.translation,hand_world.to_quaternion(),Vector((1,1,1)))
                bpy.context.view_layer.update()
        key_all(frame)
    for curve in action_fcurves(action):
        for key in curve.keyframe_points:
            key.interpolation = "LINEAR"
    print("AUTHORED=" + name)

export_model_and_clips(OUT, rig, export_model=False) # Base model files frozen after native-import handoff.

# Full-rate transform payload: rest and pose deltas in both Blender armature
# coordinates. Serialized exporter keeps bone-local bases; C changes world basis only.
C = Matrix(((1,0,0,0),(0,0,1,0),(0,-1,0,0),(0,0,0,1)))
Ci = C.inverted()
def array(m): return [[float(x) for x in row] for row in m]
rest = {b.name: b.matrix_local.copy() for b in rig.data.bones}
parents = {b.name: b.parent.name if b.parent else None for b in rig.data.bones}
payload = {"fps":FPS,"height_meters":2.4,"blender_forward":"-Y", "gltf_forward":"+Z",
           "to_gltf_y_up":array(C),"units":"meters","matrix_layout":"row-major 4x4",
           "pose_definition":"inverse(rest_local) @ animated_local; bone-local basis preserved. Run export_serialized_gltf_clips.py for serialized-node evidence.",
           "bones":[],"clips":[]}
for name,r in rest.items():
    local = rest[parents[name]].inverted() @ r if parents[name] else r
    payload["bones"].append({"name":name,"parent":parents[name],"rest_world":array(r),
        "rest_local":array(local),"rest_world_gltf":array(C@r),"rest_local_gltf":array(local if parents[name] else C@local)})
mesh = bound_meshes(rig)[0]
placement = {"actor_basis":"X=-BlenderX, Y=BlenderZ, Z=BlenderY; forward=-Z",
             "height_meters":2.4,"intended_height_studs":8,"scale_studs_per_meter":8/2.4,
             "reference_points":"Eye and palm are anatomical estimates; mesh extrema are evaluated vertices.","clips":{}}
for name,(start,end) in CLIPS.items():
    activate_action(rig,bpy.data.actions[name])
    clip = {"name":name,"loop":name=="WatchingIdle","duration":(end-start)/FPS,"keyframes":[]}
    extrema = {"min_forward_z_meters":1e9,"max_forward_z_meters":-1e9,"frames":[]}
    for frame in range(start,end+1):
        bpy.context.scene.frame_set(frame)
        bpy.context.view_layer.update()
        poses={}
        for pb in rig.pose.bones:
            local=pb.parent.matrix.inverted()@pb.matrix if pb.parent else pb.matrix
            rest_local=rest[parents[pb.name]].inverted()@rest[pb.name] if parents[pb.name] else rest[pb.name]
            delta=rest_local.inverted()@local
            poses[pb.name]={"matrix":array(delta),"matrix_gltf":array(delta)}
        clip["keyframes"].append({"time":(frame-start)/FPS,"poses":poses})
        evaluated=mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
        min_y=min((evaluated.matrix_world@v.co).y for v in evaluated.data.vertices)
        max_y=max((evaluated.matrix_world@v.co).y for v in evaluated.data.vertices)
        extrema["min_forward_z_meters"]=min(extrema["min_forward_z_meters"],min_y)
        extrema["max_forward_z_meters"]=max(extrema["max_forward_z_meters"],max_y)
        if frame in {start, round((start+end)/2), end, 49, 69}:
            head=rig.pose.bones["Head"].matrix
            # The facial point uses the real headfront joint, with a slight upward offset.
            eye=point("headfront")+Vector((0,0,.055))
            hand=rig.pose.bones["RightHand"].matrix
            palm=hand@Vector((0,.095,0))
            convert=lambda v:[-float(v.x),float(v.z),float(v.y)]
            extrema["frames"].append({"frame":frame,"time":(frame-start)/FPS,
                "eye_actor_meters":convert(eye),"right_palm_actor_meters":convert(palm),
                "right_wrist_actor_meters":convert(hand.translation),"mesh_min_z":min_y})
    placement["clips"][name]=extrema
    payload["clips"].append(clip)
write_json(OUT/"animation-transforms-30fps.json",payload)
write_json(OUT/"placement-reference.json",placement)
print("WATCHER_ANIMATIONS_READY="+str(OUT))
