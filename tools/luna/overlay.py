# blender -b luna_rig.blend -P overlay.py -- <out_prefix> [action] [frame]
# X-ray render of the posed mesh with the bones drawn as red sticks (head = yellow dot).
import bpy, sys
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
out = argv[0]
action = argv[1] if len(argv) > 1 and argv[1] != "-" else None
frame = int(argv[2]) if len(argv) > 2 else 1
scene = bpy.context.scene
mesh = bpy.data.objects["LunaMesh"]
arm = bpy.data.objects.get("LunaRig")
if arm and action:
    arm.animation_data_create(); arm.animation_data.action = bpy.data.actions[action]
    if hasattr(arm.animation_data, "action_slot") and bpy.data.actions[action].slots:
        arm.animation_data.action_slot = bpy.data.actions[action].slots[0]
scene.frame_set(frame)
red = bpy.data.materials.new("red"); red.diffuse_color = (1, 0.1, 0.1, 1)
yel = bpy.data.materials.new("yel"); yel.diffuse_color = (1, 0.9, 0.1, 1)
if arm:
    for pb in arm.pose.bones:
        h = arm.matrix_world @ pb.head; t = arm.matrix_world @ pb.tail
        d = t - h
        bpy.ops.mesh.primitive_cylinder_add(radius=0.025, depth=d.length, location=(h + t) / 2)
        c = bpy.context.object; c.rotation_mode = "QUATERNION"; c.rotation_quaternion = d.to_track_quat("Z", "Y")
        c.data.materials.append(red); c.color = (1, 0.1, 0.1, 1)
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.045, location=h)
        s = bpy.context.object; s.data.materials.append(yel); s.color = (1, 0.9, 0.1, 1)
mesh.color = (0.85, 0.85, 0.85, 1)
scene.render.engine = "BLENDER_WORKBENCH"
sh = scene.display.shading
sh.light = "FLAT"; sh.color_type = "OBJECT"; sh.show_xray = True; sh.xray_alpha = 0.45
scene.render.resolution_x = scene.render.resolution_y = 720
if not scene.world:
    scene.world = bpy.data.worlds.new("w")
scene.world.color = (0.2, 0.2, 0.22)
cam = bpy.data.objects.new("ov_cam", bpy.data.cameras.new("ov_cam")); scene.collection.objects.link(cam); scene.camera = cam
cam.data.type = "ORTHO"; cam.data.ortho_scale = 5.2
center = Vector((0, 0, 1.6))
for name, d in {"side": (1, 0, 0), "front": (0, 1, 0), "top": (0, 0.001, 1)}.items():
    d = Vector(d).normalized()
    cam.location = center + d * 12
    cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = f"{out}_{name}.png"
    bpy.ops.render.render(write_still=True)
