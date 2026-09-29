"""Render actual authored house previews without changing the saved source."""
import bpy, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]/'assets/models/aero-house'
scene=bpy.data.scenes['Aero House']
bpy.context.window.scene=scene
scene.render.resolution_x=1280
scene.render.resolution_y=880
scene.cycles.samples=16
scene.cycles.adaptive_threshold=.06
labels=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else ['Exterior','Lounge']
for label in labels:
    scene.camera=bpy.data.objects['Aero_Camera_'+label]
    scene.render.filepath=str(ROOT/'previews'/(label.lower()+'.png'))
    bpy.ops.render.render(write_still=True)
    print('AERO_PREVIEW '+label,flush=True)
