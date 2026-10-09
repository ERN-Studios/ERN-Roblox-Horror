"""Shared helpers for Luna's Blender animation scripts (Blender 5.2, run headless).

Conventions (luna_rig2.blend):
  * 1 Blender unit = 1 stud. Nose points +Y, +Z is up, +X is Luna's RIGHT side. Ground is Z = 0.
  * Rest pose (all identity) = natural standing pose "STAND". The head is already straight.
  * Rotation about armature +X by a positive angle pitches a bone's tip UP (nose up / leg forward-up);
    about +Z positive turns the tip toward -X (her LEFT). Use rot() so you never think in bone-local axes.
  * Bones (29): Root (non-deform, at ground origin; never key it except where noted), Hips, Spine1, Spine2, Chest,
    Neck, Head, EarL, EarR, Tail1..Tail4, Scapula/UpperArm/Forearm/FrontPaw{L,R}, Thigh/Shin/Hock/HindPaw{L,R}.
  * 30 fps. Clips are IN PLACE: Root never translates; locomotion speed is reported as a reference speed.
  * Only rotation_quaternion is keyed on every bone; location is keyed only on Hips (body height / shift).
"""
import bpy, math, json
from mathutils import Vector, Quaternion, Matrix

FPS = 30
ARM = bpy.data.objects["LunaRig"]
MESH = bpy.data.objects["LunaMesh"]
BONES = [b.name for b in ARM.data.bones]
bpy.context.scene.render.fps = FPS


def reset():
    for pb in ARM.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0)
        pb.scale = (1, 1, 1)
    bpy.context.view_layer.update()


def rot(name, axis, deg):
    """Rotate bone `name` about an ARMATURE-space axis (e.g. (1,0,0)) by deg, on top of its current pose."""
    bpy.context.view_layer.update()
    pb = ARM.pose.bones[name]
    cur = pb.matrix.to_3x3()
    local_axis = (cur.inverted() @ Vector(axis)).normalized()
    pb.rotation_quaternion = pb.rotation_quaternion @ Quaternion(local_axis, math.radians(deg))
    bpy.context.view_layer.update()


def move_hips(dx=0.0, dy=0.0, dz=0.0):
    """Translate the Hips bone in ARMATURE space (studs). Everything above/below follows."""
    bpy.context.view_layer.update()
    pb = ARM.pose.bones["Hips"]
    rest = ARM.data.bones["Hips"].matrix_local.to_3x3()
    pb.location = Vector(pb.location) + rest.inverted() @ Vector((dx, dy, dz))
    bpy.context.view_layer.update()


def snapshot():
    """Current pose as {bone: (quat tuple, loc tuple)} — store key poses with this, restore with apply()."""
    return {pb.name: (tuple(pb.rotation_quaternion), tuple(pb.location)) for pb in ARM.pose.bones}


def apply(pose):
    for name, (q, l) in pose.items():
        pb = ARM.pose.bones[name]
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = q
        pb.location = l
    bpy.context.view_layer.update()


def blend(a, b, t):
    """Per-bone slerp/lerp between two snapshots (t in 0..1)."""
    out = {}
    for name in a:
        qa, la = Quaternion(a[name][0]), Vector(a[name][1])
        qb, lb = Quaternion(b[name][0]), Vector(b[name][1])
        if qa.dot(qb) < 0:
            qb = -qb
        out[name] = (tuple(qa.slerp(qb, t)), tuple(la.lerp(lb, t)))
    return out


def ease(t):
    return t * t * (3 - 2 * t)


def new_action(name):
    """Create (or replace) an action and bind it to the armature. Returns the action."""
    old = bpy.data.actions.get(name)
    if old:
        bpy.data.actions.remove(old)
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    ARM.animation_data_create()
    ARM.animation_data.action = act
    return act


def key(frame):
    """Key every bone's rotation (and Hips location) at `frame` from the current pose."""
    for pb in ARM.pose.bones:
        pb.keyframe_insert("rotation_quaternion", frame=frame)
    ARM.pose.bones["Hips"].keyframe_insert("location", frame=frame)


def finish(act, first, last, loop):
    act.frame_range = (first, last)
    act.use_frame_range = True
    act["luna_loop"] = bool(loop)
    act["luna_fps"] = FPS
    for fc in _fcurves(act):
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"


def _fcurves(act):
    if hasattr(act, "fcurves") and len(getattr(act, "fcurves", [])):
        return list(act.fcurves)
    out = []
    for layer in getattr(act, "layers", []):
        for strip in layer.strips:
            for bag in strip.channelbags:
                out.extend(bag.fcurves)
    return out


def bone_world(name, end="tail"):
    bpy.context.view_layer.update()
    pb = ARM.pose.bones[name]
    return ARM.matrix_world @ (pb.tail if end == "tail" else pb.head)


def mesh_min_z():
    """Lowest Z of the deformed mesh at the current frame/pose (ground penetration check)."""
    dg = bpy.context.evaluated_depsgraph_get()
    ev = MESH.evaluated_get(dg)
    me = ev.to_mesh()
    z = min((ev.matrix_world @ v.co).z for v in me.vertices)
    ev.to_mesh_clear()
    return z


def paws_world():
    return {n: tuple(round(c, 3) for c in bone_world(n, "tail")) for n in
            ("FrontPawL", "FrontPawR", "HindPawL", "HindPawR")}


def render_frames(prefix, frames, views=("side",), size=480):
    """Workbench renders of the current action at the given frames: <prefix>_f###_<view>.png"""
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "TEXTURE"
    scene.render.resolution_x = scene.render.resolution_y = size
    if not scene.world:
        scene.world = bpy.data.worlds.new("w")
    scene.world.color = (0.35, 0.35, 0.38)
    cam = bpy.data.objects.get("lib_cam")
    if not cam:
        cam = bpy.data.objects.new("lib_cam", bpy.data.cameras.new("lib_cam"))
        scene.collection.objects.link(cam)
        # ground plane so foot contact is visible
        bpy.ops.mesh.primitive_plane_add(size=40, location=(0, 0, 0))
        plane = bpy.context.object; plane.name = "lib_ground"; plane.color = (0.25, 0.25, 0.27, 1)
    scene.camera = cam
    cam.data.type = "ORTHO"; cam.data.ortho_scale = 6.0
    center = Vector((0, 0, 1.5))
    dirs = {"side": (1, 0, 0), "left": (-1, 0, 0), "front": (0, 1, 0), "top": (0, 0.001, 1), "three": (0.75, 0.6, 0.35)}
    paths = []
    for f in frames:
        scene.frame_set(f)
        for v in views:
            d = Vector(dirs[v]).normalized()
            cam.location = center + d * 14
            cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()
            scene.render.filepath = f"{prefix}_f{f:03d}_{v}.png"
            bpy.ops.render.render(write_still=True)
            paths.append(scene.render.filepath)
    return paths
