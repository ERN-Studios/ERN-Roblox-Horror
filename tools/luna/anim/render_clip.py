# blender -b <file.blend> -P render_clip.py -- <out_prefix> <action> <frames|step:N> [views]
# Renders an action's frames (workbench, textured, ground plane) for contact sheets.
import bpy, sys, os
sys.path.insert(0, os.path.dirname(__file__))
import lunalib as L

argv = sys.argv[sys.argv.index("--") + 1:]
prefix, name, spec = argv[0], argv[1], argv[2]
views = tuple(argv[3].split(",")) if len(argv) > 3 else ("side",)
act = bpy.data.actions[name]
L.ARM.animation_data_create()
L.ARM.animation_data.action = act
if hasattr(L.ARM.animation_data, "action_slot") and act.slots:
    L.ARM.animation_data.action_slot = act.slots[0]
f0, f1 = int(act.frame_range[0]), int(act.frame_range[1])
if spec.startswith("step:"):
    step = int(spec[5:])
    frames = list(range(f0, f1 + 1, step))
    if frames[-1] != f1:
        frames.append(f1)
else:
    frames = [int(x) for x in spec.split(",")]
for p in L.render_frames(prefix, frames, views, 360):
    print("FRAME", p)
