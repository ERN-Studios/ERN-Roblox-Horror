# blender -b G:\Roblox\_local\luna\blend\luna_rig2.blend -P build_all.py -- <out luna_anim.blend>
# Builds every clip group into one file (the order does not matter: each group starts from reset()).
import bpy, sys, os, importlib
sys.path.insert(0, os.path.dirname(__file__))
import lunalib as L

out = sys.argv[sys.argv.index("--") + 1]
for group in ("clips_loco", "clips_sit", "clips_sleep", "clips_belly"):
    mod = importlib.import_module(group)
    mod.build()
    L.reset()
for o in list(bpy.context.scene.objects):
    if o.name not in ("LunaRig", "LunaMesh"):
        bpy.data.objects.remove(o)
for pb in L.ARM.pose.bones:
    assert not pb.constraints, (pb.name, "constraint left behind")
if L.ARM.animation_data:
    L.ARM.animation_data.action = None
for a in list(bpy.data.actions):          # scratch/bake leftovers would be exported as clips
    if "luna_loop" not in a:
        bpy.data.actions.remove(a)
clips = sorted(a.name for a in bpy.data.actions)
print("BUILT", clips)
bpy.ops.wm.save_as_mainfile(filepath=out)
