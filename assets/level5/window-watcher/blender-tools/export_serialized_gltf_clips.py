"""Derive runtime deltas against the actual immutable GLB joint-node rest matrices."""
from pathlib import Path
import sys,json,struct,hashlib,math
sys.path.insert(0,str(Path(__file__).resolve().parent))
import bpy
from mathutils import Matrix,Vector,Quaternion
from watcher_common import *
OUT=Path(__file__).resolve().parents[1]
path=OUT/"model.glb"
raw=path.read_bytes()
length,kind=struct.unpack_from("<II",raw,12)
gltf=json.loads(raw[20:20+length])
assert kind==0x4E4F534A
binary_offset=20+length
binary_length,binary_kind=struct.unpack_from("<II",raw,binary_offset)
assert binary_kind==0x004E4942
binary=raw[binary_offset+8:binary_offset+8+binary_length]
nodes=gltf["nodes"]
index={n["name"]:i for i,n in enumerate(nodes)}
parents={child:i for i,n in enumerate(nodes) for child in n.get("children",[])}
def local_matrix(node):
 if "matrix" in node:
  return Matrix([node["matrix"][i:i+4] for i in range(0,16,4)]).transposed()
 t=node.get("translation",[0,0,0]);r=node.get("rotation",[0,0,0,1]);s=node.get("scale",[1,1,1])
 return Matrix.LocRotScale(Vector(t),Quaternion((r[3],r[0],r[1],r[2])),Vector(s))
local={i:local_matrix(n) for i,n in enumerate(nodes)}
world={}
def world_matrix(i):
 if i not in world:world[i]=world_matrix(parents[i])@local[i] if i in parents else local[i]
 return world[i]
for i in range(len(nodes)):world_matrix(i)
import_asset(OUT/"model.blend")
rig=get_rig()
C=Matrix(((1,0,0,0),(0,0,1,0),(0,-1,0,0),(0,0,0,1)))
def array(m):return [[float(x) for x in row] for row in m]
def error(a,b):return max(abs(a[r][c]-b[r][c]) for r in range(4) for c in range(4))
bone_names=[b.name for b in rig.data.bones]
correction={name:(C@rig.data.bones[name].matrix_local).inverted()@world[index[name]] for name in bone_names}
max_basis_error=max(error(c,Matrix.Identity(4)) for c in correction.values())
assert max_basis_error<1e-4, f"Unexpected exported bone basis correction: {max_basis_error}"
skin=gltf["skins"][0]
acc=gltf["accessors"][skin["inverseBindMatrices"]]
view=gltf["bufferViews"][acc["bufferView"]]
offset=view.get("byteOffset",0)+acc.get("byteOffset",0)
stride=view.get("byteStride",64)
inversebind_error=0
for k,joint in enumerate(skin["joints"]):
 values=struct.unpack_from("<16f",binary,offset+k*stride)
 ibm=Matrix([values[i:i+4] for i in range(0,16,4)]).transposed()
 inversebind_error=max(inversebind_error,error(ibm,world[joint].inverted()))
assert inversebind_error<1e-4
proof={"model_glb_sha256":hashlib.sha256(raw).hexdigest(),"height_meters":2.4,
       "units":"meters","fps":30,"root_object":"WindowWatcherRig",
       "formula":"G_anim_world = C @ Blender_pose_world @ per_bone_basis_correction; D = inverse(serialized_G_rest_local) @ G_anim_local",
       "finding":"Bone locals retain Blender local bases; do not conjugate local deltas by the world Y-up conversion.",
       "max_exported_basis_correction_from_identity":max_basis_error,
       "max_inverse_bind_vs_serialized_world_inverse_error":inversebind_error,
       "bones":[],"clips":[]}
for name in bone_names:
 b=rig.data.bones[name];i=index[name]
 proof["bones"].append({"name":name,"parent":b.parent.name if b.parent else None,"gltf_node_index":i,
    "rest_local":array(local[i]),"rest_world":array(world[i]),"blender_to_export_basis":array(correction[name])})
expanded={"fps":30,"units":"meters","coordinate_contract":"Actual serialized model.glb joint-local bases",
          "model_glb_sha256":proof["model_glb_sha256"],"pose_definition":proof["formula"],
          "bones":proof["bones"],"clips":[]}
for name,(start,end) in CLIPS.items():
 activate_action(rig,bpy.data.actions[name])
 compact={"name":name,"fps":30,"duration":(end-start)/30,"loop":name=="WatchingIdle","units":"meters",
          "modelGlbSha256":proof["model_glb_sha256"],"format":"frames[frame].poses = [boneName,tx,ty,tz,qx,qy,qz,qw]",
          "boneNames":bone_names,"frames":[]}
 detailed={"name":name,"duration":compact["duration"],"loop":compact["loop"],"keyframes":[]}
 scale_error=0
 for frame in range(start,end+1):
  bpy.context.scene.frame_set(frame);bpy.context.view_layer.update()
  animated={n:C@rig.pose.bones[n].matrix@correction[n] for n in bone_names}
  poses=[];full={}
  for n in bone_names:
   pb=rig.pose.bones[n];i=index[n]
   if pb.parent:anim_local=animated[pb.parent.name].inverted()@animated[n]
   else:anim_local=world[parents[i]].inverted()@animated[n] if i in parents else animated[n]
   delta=local[i].inverted()@anim_local
   t,q,s=delta.decompose();q.normalize()
   if q.w<0:q.negate()
   scale_error=max(scale_error,max(abs(v-1) for v in s))
   poses.append([n,*[round(v,8) for v in t],round(q.x,8),round(q.y,8),round(q.z,8),round(q.w,8)])
   full[n]={"matrix":array(delta),"matrix_gltf":array(delta),"animated_local_gltf":array(anim_local)}
  compact["frames"].append({"time":round((frame-start)/30,8),"poses":poses})
  detailed["keyframes"].append({"time":(frame-start)/30,"poses":full})
 assert scale_error<1e-4,scale_error
 destination=OUT/(name+"-roblox-30fps.json")
 destination.write_text(json.dumps(compact,separators=(",",":"))+"\n")
 proof["clips"].append({"name":name,"frames":len(compact["frames"]),"path":destination.name,"bytes":destination.stat().st_size,
    "max_omitted_scale_error":scale_error,"sha256":hashlib.sha256(destination.read_bytes()).hexdigest()})
 expanded["clips"].append(detailed)
write_json(OUT/"animation-transforms-30fps.json",expanded)
write_json(OUT/"serialized-glb-coordinate-audit.json",proof)
assert hashlib.sha256(path.read_bytes()).hexdigest()==proof["model_glb_sha256"]
print("GLB_COORDINATE_AUDIT="+json.dumps({k:v for k,v in proof.items() if k!="bones"}))
