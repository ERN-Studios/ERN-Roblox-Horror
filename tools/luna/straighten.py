# blender -b luna_rig.blend -P straighten.py -- <out.blend>
# Turns Neck/Head so the nose points straight ahead (+Y), bakes that into the mesh and makes it the rest pose.
import bpy, sys, math
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
out = argv[0]
arm = bpy.data.objects["LunaRig"]
mesh = bpy.data.objects["LunaMesh"]
v = [mesh.matrix_world @ vv.co for vv in mesh.data.vertices]
nose = max(v, key=lambda p: p.y)
base = arm.data.bones["Head"].head_local
yaw = math.atan2(nose.x - base.x, nose.y - base.y)          # positive = turned to her right (+X)
print("STRAIGHTEN yaw_deg", math.degrees(yaw), "nose", tuple(nose))
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="POSE")
for name, share in (("Neck", 0.35), ("Head", 0.65)):
    pb = arm.pose.bones[name]
    pb.rotation_mode = "XYZ"
    # rotation about world Z expressed in the bone's local frame
    rest = arm.data.bones[name].matrix_local.to_3x3()
    axis_local = rest.inverted() @ Vector((0, 0, 1))
    pb.rotation_mode = "AXIS_ANGLE"
    pb.rotation_axis_angle = (yaw * share, *axis_local)
    bpy.context.view_layer.update()
bpy.ops.object.mode_set(mode="OBJECT")
# bake the deformation into the mesh, then make the pose the new rest
mod = next(m for m in mesh.modifiers if m.type == "ARMATURE")
bpy.context.view_layer.objects.active = mesh
bpy.ops.object.modifier_apply(modifier=mod.name)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="POSE")
bpy.ops.pose.armature_apply(selected=False)
for pb in arm.pose.bones:
    pb.rotation_mode = "QUATERNION"
    pb.rotation_quaternion = (1, 0, 0, 0)
bpy.ops.object.mode_set(mode="OBJECT")
m = mesh.modifiers.new("Armature", "ARMATURE"); m.object = arm
v = [mesh.matrix_world @ vv.co for vv in mesh.data.vertices]
nose = max(v, key=lambda p: p.y)
print("STRAIGHTEN after nose", tuple(nose))
bpy.ops.wm.save_as_mainfile(filepath=out)
