"""New technical UV mask baked from rest-mesh iris anatomy; frozen inputs read-only."""
from pathlib import Path
import sys,json,hashlib,math
import bpy,numpy as np
from mathutils import Vector
base=Path(__file__).resolve().parents[1];out=base/'eye-placement'
sys.path.insert(0,str(base.parent/'blender-tools'))
from watcher_common import *
frozen_paths=[base.parent/'model.blend',base.parent/'model.glb',base.parent/'WindowWatcher-basecolor.png']
frozen={str(p.relative_to(base.parent)):hashlib.sha256(p.read_bytes()).hexdigest() for p in frozen_paths}
import_asset(frozen_paths[0]);rig=get_rig();mesh=bound_meshes(rig)[0]
activate_action(rig,None);reset_pose(rig)
data=json.loads((out/'eye-placement.json').read_text());centers=[Vector(e['surfaceMeshLocalMeters']) for e in data['eyes']]
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=1
scene.render.bake.use_clear=True;scene.render.bake.margin=0;scene.render.bake.use_selected_to_active=False
image=bpy.data.images.new('WindowWatcher_Eyes_EmissionMask',width=2048,height=2048,alpha=False,float_buffer=False)
image.colorspace_settings.name='Non-Color';image.generated_color=(0,0,0,1)
originals=list(mesh.data.materials);bake_materials=[]
for old in originals:
 mat=bpy.data.materials.new('TemporaryIrisMaskBake');mat.use_nodes=True;n=mat.node_tree.nodes;l=mat.node_tree.links;n.clear()
 tex=n.new('ShaderNodeTexImage');tex.image=image;n.active=tex;tex.select=True
 pos=n.new('ShaderNodeNewGeometry');values=[]
 for center in centers:
  dist=n.new('ShaderNodeVectorMath');dist.operation='DISTANCE';l.new(pos.outputs['Position'],dist.inputs[0]);dist.inputs[1].default_value=center
  falloff=n.new('ShaderNodeMapRange');falloff.clamp=True;falloff.interpolation_type='SMOOTHERSTEP';falloff.inputs['From Min'].default_value=.01005;falloff.inputs['From Max'].default_value=.01125;falloff.inputs['To Min'].default_value=1;falloff.inputs['To Max'].default_value=0;l.new(dist.outputs['Value'],falloff.inputs['Value']);values.append(falloff.outputs['Result'])
 union=n.new('ShaderNodeMath');union.operation='MAXIMUM';l.new(values[0],union.inputs[0]);l.new(values[1],union.inputs[1])
 emit=n.new('ShaderNodeEmission');l.new(union.outputs[0],emit.inputs['Color']);emit.inputs['Strength'].default_value=1
 target=n.new('ShaderNodeOutputMaterial');l.new(emit.outputs[0],target.inputs['Surface']);bake_materials.append(mat)
mesh.data.materials.clear()
for mat in bake_materials:mesh.data.materials.append(mat)
bpy.ops.object.select_all(action='DESELECT');mesh.select_set(True);bpy.context.view_layer.objects.active=mesh
bpy.ops.object.bake(type='EMIT')
image.filepath_raw=str(out/'window-watcher-eye-emission-mask.png');image.file_format='PNG';image.save()
# Independently check every triangle that maps a non-black mask texel. Shared UVs
# elsewhere on the body would also be found, not merely the intended eye triangles.
w,h=image.size;pixels=np.empty(w*h*4,dtype=np.float32);image.pixels.foreach_get(pixels);pixels=pixels.reshape((h,w,4))
ys,xs=np.nonzero(pixels[:,:,0]>1/255);points=np.stack(((xs+.5)/w,(ys+.5)/h),axis=1);values=pixels[ys,xs,0]
mesh.data.calc_loop_triangles();uv=mesh.data.uv_layers.active.data;verts=mesh.data.vertices
claims=[];leaks=[];max_dist=0.;mapped=np.zeros(len(xs),dtype=bool)
head_index=mesh.vertex_groups['Head'].index
for tri in mesh.data.loop_triangles:
 t=np.array([tuple(uv[i].uv) for i in tri.loops],dtype=float)
 selector=np.all(points>=t.min(axis=0)-1e-8,axis=1)&np.all(points<=t.max(axis=0)+1e-8,axis=1)
 indexes=np.flatnonzero(selector)
 if not len(indexes):continue
 ab=t[1]-t[0];ac=t[2]-t[0];det=ab[0]*ac[1]-ab[1]*ac[0]
 if abs(det)<1e-14:continue
 q=points[indexes]-t[0];b=(q[:,0]*ac[1]-q[:,1]*ac[0])/det;c=(ab[0]*q[:,1]-ab[1]*q[:,0])/det;a=1-b-c
 inside=(a>=-1e-7)&(b>=-1e-7)&(c>=-1e-7);indexes=indexes[inside]
 if not len(indexes):continue
 bary=np.stack((a[inside],b[inside],c[inside]),axis=1)
 world=bary@np.array([tuple(verts[i].co) for i in tri.vertices])
 distances=np.stack([np.linalg.norm(world-np.array(c),axis=1) for c in centers],axis=1).min(axis=1)
 max_dist=max(max_dist,float(distances.max()));mapped[indexes]=True
 weights=[sum(g.weight for g in verts[i].groups if g.group==head_index) for i in tri.vertices]
 row={'triangle':tri.index,'whiteTexelFragments':len(indexes),'maxDistanceToIrisMeters':float(distances.max()),'minVertexHeadWeight':min(weights)};claims.append(row)
 if np.any(distances>.0125) or min(weights)<.999:leaks.append(row)
assert len(xs)>0 and not leaks,{'nonBlack':len(xs),'leaks':leaks}
# Restore original material appearance, adding only the new mask to white emission.
mesh.data.materials.clear()
for old in originals:
 mat=old.copy();mat.name='EyeMaskPhysicalPreview';n=mat.node_tree.nodes;l=mat.node_tree.links
 bsdf=next(n for n in n if n.type=='BSDF_PRINCIPLED')
 for socket in ['Emission Color','Emission Strength']:
  for link in list(bsdf.inputs[socket].links):l.remove(link)
 tex=n.new('ShaderNodeTexImage');tex.image=image;tex.interpolation='Linear';l.new(tex.outputs['Color'],bsdf.inputs['Emission Color']);bsdf.inputs['Emission Strength'].default_value=15
 mesh.data.materials.append(mat)
scene.render.engine='BLENDER_EEVEE';scene.render.resolution_x=1000;scene.render.resolution_y=1000;scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG'
scene.world=bpy.data.worlds.new('EmissionQAWorld');scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.025,.03,.04,1);scene.world.node_tree.nodes['Background'].inputs[1].default_value=.15
scene.view_settings.view_transform='AgX'
lights=[]
for name,loc,power,size in [('Key',(1,-3,4),100,3),('Fill',(-2,-3,2.5),60,3)]:
 d=bpy.data.lights.new(name,'AREA');o=bpy.data.objects.new(name,d);scene.collection.objects.link(o);o.location=loc;d.energy=power;d.size=size;o.rotation_euler=(Vector((0,0,2.2))-o.location).to_track_quat('-Z','Y').to_euler();lights.append(o)
d=bpy.data.cameras.new('EmissionQACamera');camera=bpy.data.objects.new('EmissionQACamera',d);scene.collection.objects.link(camera);scene.camera=camera;d.type='ORTHO'
def render(name,position,target,scale,clip=None,frame=1):
 activate_action(rig,bpy.data.actions[clip] if clip else None)
 if clip:scene.frame_set(frame)
 else:reset_pose(rig)
 camera.location=position;camera.rotation_euler=(Vector(target)-camera.location).to_track_quat('-Z','Y').to_euler();d.ortho_scale=scale
 scene.render.filepath=str(out/name);bpy.ops.render.render(write_still=True)
render('emission-mask-rest-face.png',(0,-5,2.23),(0,0,2.23),.45)
render('emission-mask-lean-face.png',(.8,-4,2.23),(0,-.065,2.205),.45,'SlowWindowLean',76)
render('emission-mask-whole-body.png',(0,-5,1.25),(0,0,1.25),2.7)
# Literal mask visualization on mesh: black everywhere except the two eye patches.
for mat in mesh.data.materials:
 n=mat.node_tree.nodes;l=mat.node_tree.links;target=next(n for n in n if n.type=='OUTPUT_MATERIAL')
 emit=n.new('ShaderNodeEmission');emit.inputs['Strength'].default_value=1;tex=n.new('ShaderNodeTexImage');tex.image=image;l.new(tex.outputs['Color'],emit.inputs['Color']);l.new(emit.outputs[0],target.inputs['Surface'])
render('emission-mask-uv-mapping-proof.png',(0,-5,1.25),(0,0,1.25),2.7)
for p,hsh in frozen.items():assert hashlib.sha256((base/p).read_bytes()).hexdigest()==hsh
report={'sourceFiles':frozen,'maskPath':image.filepath_raw,'maskSha256':hashlib.sha256(Path(image.filepath_raw).read_bytes()).hexdigest(),'resolution':[w,h],'method':'Blender Cycles EMIT bake from world-position distance to actual raycast iris surfaces. New black/white technical mask; original albedo not edited. Exact original UVMap. No bake margin.','whiteCoreDiameterMeters':.0201,'whiteCoreDiameterStudsAtEightStudHeight':.067,'outerSoftEdgeDiameterStuds':.075,'nonBlackPixels':len(xs),'mappedNonBlackPixels':int(mapped.sum()),'unmappedNonBlackPixels':int((~mapped).sum()),'triangleMaskCoverage':claims,'maxNonBlackFragmentDistanceToNearestIrisMeters':max_dist,'leakTriangles':leaks,'geometryUvLeakCheckPass':len(leaks)==0,'frozenInputsUnchanged':True,'nativeRobloxEmissionVerified':False,'nativeNote':'SurfaceAppearance.EmissiveMaskContent should use this mask, EmissiveTint white, EmissiveStrength start15. Native albedo multiplication/Glass visibility require native QA; Blender preview white emission is a placement proof.'}
write_json(out/'emission-mask-audit.json',report)
print('EMISSION_MASK_RESULT='+json.dumps({k:v for k,v in report.items() if k not in ('triangleMaskCoverage','sourceFiles')}))
