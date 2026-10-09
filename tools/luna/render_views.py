# blender -b <file.blend> -P render_views.py -- <out_prefix> [action] [frame,frame,...] [views=side,front,top,three]
# Workbench texture renders, orthographic, framed on the dog's rest bounds. With an action, renders each frame given.
import bpy, sys
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
out = argv[0]
action = argv[1] if len(argv) > 1 and argv[1] != "-" else None
frames = [int(f) for f in argv[2].split(",")] if len(argv) > 2 and argv[2] != "-" else [None]
views = argv[3].split(",") if len(argv) > 3 else ["side", "front", "top", "three"]
scene = bpy.context.scene
mesh = next(o for o in scene.objects if o.type == "MESH" and o.name.startswith("Luna"))
arm = next((o for o in scene.objects if o.type == "ARMATURE"), None)
if arm and action:
    arm.animation_data_create()
    arm.animation_data.action = bpy.data.actions[action]
    if hasattr(arm.animation_data, "action_slot") and bpy.data.actions[action].slots:
        arm.animation_data.action_slot = bpy.data.actions[action].slots[0]
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"
scene.display.shading.color_type = "TEXTURE"
scene.render.resolution_x = scene.render.resolution_y = 640
if not scene.world:
    scene.world = bpy.data.worlds.new("w")
scene.world.color = (0.35, 0.35, 0.38)
pts = [mesh.matrix_world @ Vector(b) for b in mesh.bound_box]
lo = Vector([min(p[i] for p in pts) for i in range(3)]); hi = Vector([max(p[i] for p in pts) for i in range(3)])
center = (lo + hi) / 2
size = max(hi - lo) * 1.35
cam = bpy.data.objects.get("render_cam")
if not cam:
    cam = bpy.data.objects.new("render_cam", bpy.data.cameras.new("render_cam"))
    scene.collection.objects.link(cam)
scene.camera = cam
cam.data.type = "ORTHO"; cam.data.ortho_scale = size
# a floor line helps judge foot contact
dirs = {"side": (1, 0, 0), "front": (0, 1, 0), "back": (0, -1, 0), "top": (0, 0.001, 1), "three": (0.75, 0.6, 0.35), "left": (-1, 0, 0)}
for f in frames:
    if f is not None:
        scene.frame_set(f)
    for name in views:
        d = Vector(dirs[name]).normalized()
        cam.location = center + d * size * 3
        cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()
        tag = f"_f{f:03d}" if f is not None else ""
        scene.render.filepath = f"{out}{tag}_{name}.png"
        bpy.ops.render.render(write_still=True)
