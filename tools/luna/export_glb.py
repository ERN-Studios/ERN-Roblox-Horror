# blender -b <luna_*.blend> -P export_glb.py -- <out.glb> [--anim]
# Skinned GLB for Roblox's Open Cloud Model import: studs, +Y up, every bone kept (Root included),
# with --anim every action carrying a "luna_loop" property is exported as its own glTF animation, sampled per frame.
import bpy, sys

argv = sys.argv[sys.argv.index("--") + 1:]
out = argv[0]
anim = "--anim" in argv
for o in bpy.context.scene.objects:
    o.select_set(o.name in ("LunaRig", "LunaMesh"))
for o in list(bpy.context.scene.objects):          # helper objects from render scripts
    if o.name.startswith(("lib_", "render_cam", "ov_cam")):
        bpy.data.objects.remove(o)
arm = bpy.data.objects["LunaRig"]
if arm.animation_data:
    arm.animation_data.action = None
for pb in arm.pose.bones:
    pb.rotation_mode = "QUATERNION"; pb.rotation_quaternion = (1, 0, 0, 0); pb.location = (0, 0, 0)
kw = dict(filepath=out, export_format="GLB", use_selection=True, export_yup=True, export_apply=False,
          export_skins=True, export_def_bones=False, export_rest_position_armature=True,
          export_texcoords=True, export_normals=True, export_materials="EXPORT", export_image_format="AUTO",
          export_animations=anim, export_extras=True)
if anim:
    kw.update(export_animation_mode="ACTIONS", export_force_sampling=True, export_frame_step=1,
              export_optimize_animation_size=False, export_anim_single_armature=True, export_reset_pose_bones=True,
              export_bake_animation=False, export_anim_slide_to_zero=True)
bpy.ops.export_scene.gltf(**kw)
print("EXPORTED", out, "anim" if anim else "rest")
