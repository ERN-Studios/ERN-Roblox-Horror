from pathlib import Path
import sys,json,math
import bpy
from mathutils import Vector
base=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(base.parent/'blender-tools'))
from watcher_common import *
import_asset(base.parent/'model.blend')
rig=get_rig();mesh=bound_meshes(rig)[0]
activate_action(rig,None);reset_pose(rig)
print('EYE_INSPECT='+json.dumps({'rig':rounded_matrix(rig.matrix_world),'mesh':rounded_matrix(mesh.matrix_world),'bones':{n:{'head':list(rig.data.bones[n].head_local),'rest':rounded_matrix(rig.data.bones[n].matrix_local)} for n in ['Head','headfront','neck']}}))
scene=bpy.context.scene
scene.render.engine='BLENDER_EEVEE';scene.render.resolution_x=1000;scene.render.resolution_y=1000;scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG'
scene.world=bpy.data.worlds.new('EyeQAWorld');scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.025,.03,.04,1);scene.world.node_tree.nodes['Background'].inputs[1].default_value=.3
scene.view_settings.view_transform='AgX'
for name,loc,power,size in [('Key',(1,-3,4),170,3),('Fill',(-2,-3,2.5),110,3)]:
 d=bpy.data.lights.new(name,'AREA');o=bpy.data.objects.new(name,d);scene.collection.objects.link(o);o.location=loc;d.energy=power;d.size=size;o.rotation_euler=(Vector((0,0,2.2))-o.location).to_track_quat('-Z','Y').to_euler()
d=bpy.data.cameras.new('Front');o=bpy.data.objects.new('Front',d);scene.collection.objects.link(o);scene.camera=o
o.location=(0,-5,2.23);o.rotation_euler=(Vector((0,0,2.23))-o.location).to_track_quat('-Z','Y').to_euler();d.type='ORTHO';d.ortho_scale=.45
scene.render.filepath=str(base/'eye-placement/rest-face-front.png');bpy.ops.render.render(write_still=True)
