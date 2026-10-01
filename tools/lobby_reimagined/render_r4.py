from pathlib import Path
import sys
import bpy
from mathutils import Vector
root=Path(__file__).resolve().parents[2]
out=root/'assets/models/lobby-reimagined-r4-20261001'
bpy.ops.wm.open_mainfile(filepath=str(out/'LobbyReimaginedPreview.blend'))
scene=bpy.data.scenes['Lobby Reimagined | Full Preview'];bpy.context.window.scene=scene
cam=scene.camera
scene.render.resolution_x=1400;scene.render.resolution_y=820;scene.render.resolution_percentage=100
scene.render.engine='CYCLES';scene.cycles.samples=24
views=[('blender-tunnel-preview.png',(0,112,6.2),(0,-110,13),22),('blender-gate3-approach-north.png',(-13,31,5.8),(-27,0,15),27),('blender-gate3-approach-south.png',(-13,-35,5.8),(-27,0,15),27),('blender-level3-bay.png',(-43,-2,5.8),(-72,3,6),18),('blender-dj-stage.png',(0,-93,5.8),(0,-122,8),23)]
for name,position,target,lens in views:
 cam.location=position;cam.rotation_euler=(Vector(target)-Vector(position)).to_track_quat('-Z','Y').to_euler();cam.data.lens=lens
 scene.render.filepath=str(out/name);bpy.ops.render.render(write_still=True)
print('R4_RENDERED',flush=True)
