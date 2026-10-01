"""Read-only render pass over the saved R3 Blender scene; never resaves it."""
from pathlib import Path
import hashlib
import json
import bpy
from mathutils import Vector

out=Path(__file__).resolve().parent
scene=bpy.data.scenes['Lobby Reimagined | Full Preview']
bpy.context.window.scene=scene
cam=scene.camera
scene.render.engine='CYCLES'
scene.cycles.samples=12
scene.cycles.use_denoising=True
scene.render.resolution_x=1120
scene.render.resolution_y=656
scene.render.resolution_percentage=100
views=[
    ('blender-gate3-front.png',(-3,0,8),(-28.6,0,10),26),
    ('blender-gate3-approach-north.png',(-13,30,5.8),(-25,-1,14),28),
    ('blender-gate3-approach-south.png',(-13,-35,5.8),(-25,-3,14),28),
    ('blender-gate3-connector.png',(-24,0,5.8),(-55,0,13),24),
    ('blender-tunnel-preview.png',(0,118,7),(0,-100,12),22),
    ('blender-dj-stage.png',(5,-113,11),(0,-121,8),45),
]
if '--gate-only' in __import__('sys').argv:
    views=views[:3]
for name,position,target,lens in views:
    cam.location=position
    cam.rotation_euler=(Vector(target)-Vector(position)).to_track_quat('-Z','Y').to_euler()
    cam.data.lens=lens
    scene.render.filepath=str(out/name)
    bpy.ops.render.render(write_still=True)
receipt={
    'sourceBlendSha256':hashlib.sha256((out/'LobbyReimaginedPreview.blend').read_bytes()).hexdigest(),
    'manifestSha256':hashlib.sha256((out/'manifest.json').read_bytes()).hexdigest(),
    'views':[name for name,*_ in views],
    'readOnlySource':True,
}
(out/'render-qa-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
print('R3_RENDER_QA_FINISHED',json.dumps(receipt),flush=True)
