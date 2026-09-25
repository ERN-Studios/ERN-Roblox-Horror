from pathlib import Path
import sys
p=Path(__file__).with_name("render_previews.py")
source=p.read_text().split("poses=[")[0]
exec(compile(source,str(p),"exec"))
from mathutils import Quaternion,Matrix
activate_action(rig,bpy.data.actions["GlassTap"])
scene.frame_set(61)
activate_action(rig,None)
pose=rig.pose.bones["RightHand"]
matrix=pose.matrix.copy()
scene.render.resolution_x=600;scene.render.resolution_y=800
camera_at((0,-4,2.1),(-.23,-.34,1.92),.85)
for degrees in [-60,-30,30,60,90]:
 q=Quaternion(Vector((0,0,1)),math.radians(degrees))@matrix.to_quaternion()
 pose.matrix=Matrix.LocRotScale(matrix.translation,q,Vector((1,1,1)))
 bpy.context.view_layer.update()
 scene.render.filepath=str(RENDERS/("hand-study-"+str(degrees)+".png"))
 bpy.ops.render.render(write_still=True)
