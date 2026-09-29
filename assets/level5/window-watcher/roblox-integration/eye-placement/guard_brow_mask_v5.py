from pathlib import Path
import sys,json,hashlib
import bpy,numpy as np
from mathutils import Vector
base=Path(__file__).resolve().parents[1];out=base/'eye-placement'
sys.path.insert(0,str(base.parent/'blender-tools'))
from watcher_common import *
import_asset(base.parent/'model.blend');rig=get_rig();mesh=bound_meshes(rig)[0];activate_action(rig,None);reset_pose(rig)
path=out/'window-watcher-eye-emission-mask.png';oldsha=hashlib.sha256(path.read_bytes()).hexdigest()
im=bpy.data.images.load(str(path),check_existing=False);im.colorspace_settings.name='Non-Color';w,h=im.size
px=np.empty(w*h*4,dtype=np.float32);im.pixels.foreach_get(px);original=px.reshape((h,w,4))[:,:,0].copy()
low=original.reshape(1024,2,1024,2).mean(axis=(1,3))

def morph(a,op,radius):
 for i in range(radius):
  pad=np.pad(a,1,mode='constant');shift=[pad[j:j+a.shape[0],k:k+a.shape[1]] for j in range(3) for k in range(3)]
  a=np.maximum.reduce(shift) if op=='max' else np.minimum.reduce(shift)
 return a

mesh.data.calc_loop_triangles();uv=mesh.data.uv_layers.active.data
tris=[]
for tri in mesh.data.loop_triangles:
 t=np.array([tuple(uv[i].uv) for i in tri.loops]);world=np.array([tuple(mesh.data.vertices[i].co) for i in tri.vertices]);tris.append((tri.index,t,world))
centers=np.array([e['surfaceMeshLocalMeters'] for e in json.loads((out/'eye-placement.json').read_text())['eyes']])

def audit(a,name):
 ys,xs=np.nonzero(a>0);points=np.stack(((xs+.5)/a.shape[1],(ys+.5)/a.shape[0]),axis=1)
 bad=[];nfrags=0;farthest=0;maxbleed=0;outsideiris=0
 for index,t,world in tris:
  inds=np.flatnonzero(np.all(points>=t.min(axis=0)-1e-8,axis=1)&np.all(points<=t.max(axis=0)+1e-8,axis=1))
  if not len(inds):continue
  ab=t[1]-t[0];ac=t[2]-t[0];det=ab[0]*ac[1]-ab[1]*ac[0]
  if abs(det)<1e-14:continue
  q=points[inds]-t[0];b=(q[:,0]*ac[1]-q[:,1]*ac[0])/det;c=(ab[0]*q[:,1]-ab[1]*q[:,0])/det;aa=1-b-c
  keep=(aa>=-1e-7)&(b>=-1e-7)&(c>=-1e-7);inds=inds[keep]
  if not len(inds):continue
  xyz=np.stack((aa[keep],b[keep],c[keep]),axis=1)@world
  distances=np.linalg.norm(xyz[:,None,:]-centers[None,:,:],axis=2).min(axis=1);nfrags+=len(inds);farthest=max(farthest,float(distances.max()))
  leak=distances>.0125;outsideiris+=int(leak.sum())
  if leak.any():
   rows=inds[leak];vals=a[ys[rows],xs[rows]];mi=int(np.argmax(vals));maxbleed=max(maxbleed,float(vals.max()))
   bad.append({'triangle':index,'samples':int(leak.sum()),'maxStrengthFraction':float(vals.max()),'maxDistanceMeters':float(distances[leak].max()),'brightestLeakWorld':xyz[leak][mi].tolist()})
 result={'name':name,'dimensions':list(a.shape[::-1]),'nonBlackTexels':len(xs),'mappedFragments':nfrags,'maxDistanceMeters':farthest,'outsideIrisFragments':outsideiris,'maxPotentialLeakFraction':maxbleed,'offendingTriangles':sorted(bad,key=lambda x:-x['maxStrengthFraction'])}
 print('FILTER_AUDIT='+json.dumps({k:v for k,v in result.items() if k!='offendingTriangles'}),flush=True)
 return result

# Target only distant UV neighbors. Keep internal seams between iris triangles.
spread=morph(low,'max',8);ys,xs=np.nonzero(spread>0);points=np.stack(((xs+.5)/1024,(ys+.5)/1024),axis=1)
unsafe=np.zeros_like(low);unsafe_rows=[]
for index,t,world in tris:
 inds=np.flatnonzero(np.all(points>=t.min(axis=0)-1e-8,axis=1)&np.all(points<=t.max(axis=0)+1e-8,axis=1))
 if not len(inds):continue
 ab=t[1]-t[0];ac=t[2]-t[0];det=ab[0]*ac[1]-ab[1]*ac[0]
 if abs(det)<1e-14:continue
 q=points[inds]-t[0];b=(q[:,0]*ac[1]-q[:,1]*ac[0])/det;c=(ab[0]*q[:,1]-ab[1]*q[:,0])/det;aa=1-b-c
 keep=(aa>=-1e-7)&(b>=-1e-7)&(c>=-1e-7);inds=inds[keep]
 if not len(inds):continue
 xyz=np.stack((aa[keep],b[keep],c[keep]),axis=1)@world
 distances=np.linalg.norm(xyz[:,None,:]-centers[None,:,:],axis=2).min(axis=1);bad=(distances>.018) & (index in (5787,5789))
 if bad.any():
  badinds=inds[bad];unsafe[ys[badinds],xs[badinds]]=1;unsafe_rows.append({'triangle':index,'samples':int(bad.sum()),'maxDistanceMeters':float(distances[bad].max())})
guard=morph(unsafe,'max',8);v2=np.where(guard>0,0,low)
cases=[audit(v2,'targetedGuard1024'),audit(morph(v2,'max',8),'targetedGuard1024-eightPixelSupport')]
print('TARGETED_GUARD='+json.dumps({'originalNonBlack':int((low>0).sum()),'remainingNonBlack':int((v2>0).sum()),'energyRetained':float(v2.sum()/low.sum()),'unsafeTriangles':unsafe_rows}),flush=True)
rgba=np.ones((1024,1024,4),dtype=np.float32);rgba[:,:,:3]=v2[:,:,None]
new=bpy.data.images.new('WatcherIrisMaskV2_Guarded1024',width=1024,height=1024,alpha=False,float_buffer=False);new.colorspace_settings.name='Non-Color';new.pixels.foreach_set(rgba.ravel());new.update();new.file_format='PNG';new.filepath_raw=str(out/'window-watcher-eye-emission-mask-v5.png');new.save()
# Preview the candidate at strong100 white emission to reveal tiny filtered leaks.
for mat in mesh.data.materials:
 n=mat.node_tree.nodes;l=mat.node_tree.links;bsdf=next(n for n in n if n.type=='BSDF_PRINCIPLED')
 for slot in ['Emission Color','Emission Strength']:
  for link in list(bsdf.inputs[slot].links):l.remove(link)
 tex=n.new('ShaderNodeTexImage');tex.image=new;tex.interpolation='Linear';l.new(tex.outputs['Color'],bsdf.inputs['Emission Color']);bsdf.inputs['Emission Strength'].default_value=100
scene=bpy.context.scene;scene.render.engine='BLENDER_EEVEE';scene.render.resolution_x=1000;scene.render.resolution_y=1000;scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG';scene.view_settings.view_transform='AgX'
scene.world=bpy.data.worlds.new('FilterQAWorld');scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.02,.025,.03,1);scene.world.node_tree.nodes['Background'].inputs[1].default_value=.15
for name,loc,power in [('Key',(1,-3,4),100),('Fill',(-2,-3,2.5),60)]:
 d=bpy.data.lights.new(name,'AREA');o=bpy.data.objects.new(name,d);scene.collection.objects.link(o);o.location=loc;d.energy=power;d.size=3;o.rotation_euler=(Vector((0,0,2.2))-o.location).to_track_quat('-Z','Y').to_euler()
d=bpy.data.cameras.new('FilterQACamera');cam=bpy.data.objects.new('FilterQACamera',d);scene.collection.objects.link(cam);scene.camera=cam;d.type='ORTHO';d.ortho_scale=.45;cam.location=(0,-5,2.23);cam.rotation_euler=(Vector((0,0,2.23))-cam.location).to_track_quat('-Z','Y').to_euler()
scene.render.filepath=str(out/'emission-v5-face-strength100.png');bpy.ops.render.render(write_still=True)
assert hashlib.sha256(path.read_bytes()).hexdigest()==oldsha
report={'publishedMaskUnchangedSha256':oldsha,'candidatePath':new.filepath_raw,'candidateSha256':hashlib.sha256(Path(new.filepath_raw).read_bytes()).hexdigest(),'candidateTreatment':'2x2 area downsample to1024; retain internal iris UV seams, remove only pixels within8px of the two upper-right brow triangles5787/5789 that sample distant iris UV islands under8px filtering. Technical mask only.','cases':cases,'unsafeUvTriangles':unsafe_rows,'originalNonBlack':int((low>0).sum()),'remainingNonBlack':int((v2>0).sum()),'energyRetained':float(v2.sum()/low.sum()),'qualification':'Eight-pixel support bound is deliberately pessimistic. It does not reproduce proprietary Roblox compression; native visual QA required.'}
write_json(out/'emission-brow-guard-v5-audit.json',report)
