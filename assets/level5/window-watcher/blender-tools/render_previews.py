from pathlib import Path
import sys, math
sys.path.insert(0,str(Path(__file__).resolve().parent))
import bpy
from mathutils import Vector
from watcher_common import *

OUT=Path(__file__).resolve().parents[1]
RENDERS=OUT/"renders"
RENDERS.mkdir(exist_ok=True)
import_asset(OUT/"model.blend")
rig=get_rig()
mesh=bound_meshes(rig)[0]
scene=bpy.context.scene
scene.render.engine="BLENDER_EEVEE"
scene.render.resolution_x=1000
scene.render.resolution_y=1100
scene.render.resolution_percentage=100
scene.render.image_settings.file_format="PNG"
scene.render.film_transparent=False
scene.world=bpy.data.worlds.new("PreviewWorld")
scene.world.use_nodes=True
scene.world.node_tree.nodes["Background"].inputs[0].default_value=(.08,.09,.105,1)
scene.world.node_tree.nodes["Background"].inputs[1].default_value=.3
scene.view_settings.view_transform="AgX"

def mat(name,color):
 m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);return m

def area(name,location,energy,size):
 data=bpy.data.lights.new(name,"AREA");obj=bpy.data.objects.new(name,data)
 scene.collection.objects.link(obj);obj.location=location;data.energy=energy;data.shape="DISK";data.size=size
 obj.rotation_euler=(Vector((0,0,1.2))-obj.location).to_track_quat("-Z","Y").to_euler()

area("Key",(3,-4,5),550,4)
area("Fill",(-3,-2,3),230,3)
area("Rim",(0,3,4),400,3)
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.025))
floor=bpy.context.object;floor.name="PreviewFloor";floor.data.materials.append(mat("Floor",(.06,.065,.075)))
data=bpy.data.cameras.new("PreviewCamera");camera=bpy.data.objects.new("PreviewCamera",data)
scene.collection.objects.link(camera);scene.camera=camera;data.type="ORTHO"
def camera_at(pos,target,scale):
 camera.location=pos;camera.rotation_euler=(Vector(target)-camera.location).to_track_quat("-Z","Y").to_euler();data.ortho_scale=scale

poses=[("WatchingIdle",91),("SlowWindowLean",76),("GlassTap",50)]
for name,frame in poses:
 activate_action(rig,bpy.data.actions[name]);scene.frame_set(frame)
 camera_at((3,-7,2.8),(0,0,1.2),2.95)
 scene.render.filepath=str(RENDERS/(name+"-three-quarter.png"));bpy.ops.render.render(write_still=True)
 if name=="GlassTap":
  camera_at((-.9,-4,2.5),(-.08,-.20,1.90),1.25)
  scene.render.filepath=str(RENDERS/"GlassTap-palm-closeup.png");bpy.ops.render.render(write_still=True)

activate_action(rig,bpy.data.actions["GlassTap"]);scene.frame_set(24)
camera_at((3,-7,2.8),(0,0,1.2),2.95)
scene.render.filepath=str(RENDERS/"GlassTap-raising-arc.png");bpy.ops.render.render(write_still=True)

# Three frozen, genuinely evaluated poses in a single Blender scene, not a drawn mockup.
clones=[]
for index,(name,frame) in enumerate(poses):
 activate_action(rig,bpy.data.actions[name]);scene.frame_set(frame);bpy.context.view_layer.update()
 clone=rig.copy();clone.data=rig.data.copy();scene.collection.objects.link(clone)
 clone.animation_data_clear()
 clone.location.x+=(index-1)*1.75
 skin=mesh.copy();skin.data=mesh.data.copy();scene.collection.objects.link(skin)
 skin.parent=clone
 for modifier in skin.modifiers:
  if modifier.type=="ARMATURE":modifier.object=clone
 clones.extend([clone,skin])
 text_data=bpy.data.curves.new(name+" label","FONT");text_data.body=name;text_data.align_x="CENTER";text_data.size=.115
 label=bpy.data.objects.new(name+" label",text_data);scene.collection.objects.link(label)
 label.location=((index-1)*1.75,-.05,2.62);label.rotation_euler=(math.pi/2,0,0)
 label.data.materials.append(mat("Label",(.8,.82,.84)))
rig.hide_render=True;mesh.hide_render=True
scene.render.resolution_x=1800;scene.render.resolution_y=1100
camera_at((0,-10,2.25),(0,0,1.15),5.45)
scene.render.filepath=str(RENDERS/"WindowWatcher-contactsheet.png");bpy.ops.render.render(write_still=True)
print("WATCHER_RENDERS="+str(RENDERS))
