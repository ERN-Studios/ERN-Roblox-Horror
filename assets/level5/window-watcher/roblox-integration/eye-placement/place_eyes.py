"""Read frozen model; raycast two visible irises, derive attachment offsets, render QA.
No frozen model/export is written. Pixel centers were selected visually on rest-face-front.png.
"""
from pathlib import Path
import sys,json,hashlib
import bpy
from mathutils import Vector,Matrix
base=Path(__file__).resolve().parents[1];out=base/'eye-placement'
sys.path.insert(0,str(base.parent/'blender-tools'))
from watcher_common import *
source=base.parent/'model.blend';glb=base.parent/'model.glb'
frozen={str(p.relative_to(base.parent)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (source,glb)}
import_asset(source);rig=get_rig();mesh=bound_meshes(rig)[0]
activate_action(rig,None);reset_pose(rig)
head=rig.data.bones['Head'].matrix_local.copy();hi=head.inverted()
C=Matrix(((1,0,0,0),(0,0,1,0),(0,-1,0,0),(0,0,0,1)))
A=Matrix(((-1,0,0,0),(0,0,1,0),(0,1,0,0),(0,0,0,1)))
gltf_audit=json.loads((base.parent/'serialized-glb-coordinate-audit.json').read_text())
gh=Matrix(next(b['rest_world'] for b in gltf_audit['bones'] if b['name']=='Head'))
S=8/2.4
scene=bpy.context.scene;scene.render.engine='BLENDER_EEVEE';scene.render.resolution_x=1000;scene.render.resolution_y=1000;scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG'
scene.world=bpy.data.worlds.new('EyeQAWorld');scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.025,.03,.04,1);scene.world.node_tree.nodes['Background'].inputs[1].default_value=.3
scene.view_settings.view_transform='AgX'
for name,loc,power,size in [('Key',(1,-3,4),170,3),('Fill',(-2,-3,2.5),110,3)]:
 d=bpy.data.lights.new(name,'AREA');o=bpy.data.objects.new(name,d);scene.collection.objects.link(o);o.location=loc;d.energy=power;d.size=size;o.rotation_euler=(Vector((0,0,2.2))-o.location).to_track_quat('-Z','Y').to_euler()
d=bpy.data.cameras.new('EyeQACamera');camera=bpy.data.objects.new('EyeQACamera',d);scene.collection.objects.link(camera);scene.camera=camera;d.type='ORTHO';d.ortho_scale=.45
material=bpy.data.materials.new('TemporaryWhiteEyeEmitter');material.use_nodes=True
bsdf=material.node_tree.nodes.get('Principled BSDF');bsdf.inputs['Base Color'].default_value=(1,1,1,1);bsdf.inputs['Emission Color'].default_value=(1,1,1,1);bsdf.inputs['Emission Strength'].default_value=3.0
# Anatomical right is negative Blender X, visible viewer-left in front image.
samples=[('RightEye',413,458),('LeftEye',582,458)]
report={'sourceModelSha256':frozen[str(glb.relative_to(base))],'sourceBlendSha256':frozen[str(source.relative_to(base))],'units':'meters unless suffixed studs','heightMeters':2.4,'actorHeightStuds':8,'studsPerMeter':S,'actorBasis':'X=-BlenderX, Y=BlenderZ, Z=BlenderY; forward=-Z','selectionMethod':'Visually selected iris centers in orthographic front render (1000x1000, scale0.45m, center[0,0,2.23]); raycast actual rest mesh at X/Z to measure its Y surface. Emitter offset toward viewer -Y by 0.002m avoids surface occlusion.','headRestBlenderArmatureMatrix':rounded_matrix(head),'headRestSerializedGltfWorldMatrix':rounded_matrix(gh),'headRestCanonicalActorMetersMatrix':rounded_matrix(A@head),'attachmentRule':'If native bone bases preserve serialized GLB local bases, use headLocalSerializedGltfMeters * studsPerMeter directly as Attachment.Position under Head; do NOT rotate/conjugate this local vector by actor/world basis. Otherwise native rest Head CFrame:PointToObjectSpace(actorFrame:PointToWorldSpace(canonicalActorStuds)) gives the matching local offset.','billboardRecommendation':{'AlwaysOnTop':False,'LightInfluence':0,'colorRGB':[255,255,255],'diameterStuds':0.067,'maxSuggestedDiameterStuds':0.075,'worldOcclusion':'Retain wall/window occlusion; do not force rendering through architecture. White core plus a subtle halo, not a PointLight.'},'eyes':[],'qa':{'nativeRobloxPlaybackVerified':False,'frozenModelModified':False},'renderMethod':'Temporary white emissive ellipsoids at attachment centers. Not a Roblox BillboardGui simulation.'}
markers=[]
for name,px,py in samples:
 x=(px-500)*.45/1000;z=2.23+(500-py)*.45/1000
 ok,p,n,face=mesh.ray_cast(Vector((x,-1,z)),Vector((0,1,0)))
 assert ok,(name,'ray missed')
 center=p+Vector((0,-.002,0));local=hi@center;glocal=gh.inverted()@(C@center)
 row={'name':name,'referenceIrisPixel':[px,py],'surfaceMeshLocalMeters':list(p),'surfaceNormalMeshLocal':list(n),'surfaceFaceIndex':face,'emitterBlenderArmatureMeters':list(center),'headLocalBlenderMeters':list(local),'headLocalSerializedGltfMeters':list(glocal),'headLocalAttachmentStuds':list(glocal*S),'canonicalActorMeters':list(A@center),'canonicalActorStuds':list((A@center)*S),'localBasisDifferenceMeters':(local-glocal).length}
 row['nearbyVertexWeights']=[]
 for v in sorted(mesh.data.vertices,key=lambda v:(v.co-p).length)[:3]:
  row['nearbyVertexWeights'].append({'vertex':v.index,'distanceMeters':(v.co-p).length,'weights':{mesh.vertex_groups[g.group].name:g.weight for g in v.groups if g.weight>.00001}})
 report['eyes'].append(row)
 bpy.ops.mesh.primitive_uv_sphere_add(segments=24,ring_count=12,radius=1,location=center)
 marker=bpy.context.object;marker.name='QA_'+name;marker.scale=(.010,.003,.010);marker.data.materials.append(material);markers.append((marker,local))
 for f in marker.data.polygons:f.use_smooth=True

def render(name,position,target,clip=None,frame=1):
 activate_action(rig,bpy.data.actions[clip] if clip else None)
 if clip:scene.frame_set(frame)
 else:reset_pose(rig)
 bpy.context.view_layer.update()
 for marker,local in markers:
  marker.location=rig.pose.bones['Head'].matrix@local
  marker.rotation_euler=(rig.pose.bones['Head'].matrix.to_quaternion()@head.to_quaternion().inverted()).to_euler()
 camera.location=position;camera.rotation_euler=(Vector(target)-camera.location).to_track_quat('-Z','Y').to_euler()
 scene.render.filepath=str(out/name);bpy.ops.render.render(write_still=True)
render('eyes-white-rest-front.png',(0,-5,2.23),(0,0,2.23))
render('eyes-white-rest-three-quarter.png',(.8,-4,2.23),(0,0,2.23))
render('eyes-white-lean-three-quarter.png',(.8,-4,2.23),(0,-.065,2.205),'SlowWindowLean',76)
for p,h in frozen.items():assert hashlib.sha256((base/p).read_bytes()).hexdigest()==h
write_json(out/'eye-placement.json',report)
print('EYE_PLACEMENT='+json.dumps({'eyes':report['eyes'],'frozenHashesVerified':True}))
