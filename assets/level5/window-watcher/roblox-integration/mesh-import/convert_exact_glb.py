"""Transfer the frozen GLB to EditableMesh JSON, without Blender/source mutations.

Geometry, UV seams, normals, triangle winding, joint indices and weights come
directly from the serialized GLB. Uniform metres->studs scale and Y half-turn
place the original model facing Roblox -Z at eight studs tall.
"""
from pathlib import Path
import json,struct,math,hashlib,argparse

OUT=Path(__file__).resolve().parent
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source',type=Path,default=OUT.parents[1],
                    help='Directory containing model.glb and the three *-roblox-30fps.json clips')
SOURCE=parser.parse_args().source.resolve()
EXPECTED="cbf260ff36b8c7226f27271456eae6bf4db7fd266bdce82dda8b0eae7cbc051e"
SCALE=8/2.4
raw=(SOURCE/"model.glb").read_bytes()
assert hashlib.sha256(raw).hexdigest()==EXPECTED
size,kind=struct.unpack_from("<II",raw,12);assert kind==0x4e4f534a
g=json.loads(raw[20:20+size]);at=20+size
size,kind=struct.unpack_from("<II",raw,at);assert kind==0x004e4942
blob=raw[at+8:at+8+size]

def accessor(idx):
 a=g['accessors'][idx];v=g['bufferViews'][a['bufferView']]
 assert not a.get('sparse') and not a.get('normalized'), 'Unexpected encoded accessor'
 code,width={5126:('f',4),5125:('I',4),5123:('H',2),5121:('B',1)}[a['componentType']]
 count={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[a['type']]
 start=v.get('byteOffset',0)+a.get('byteOffset',0);stride=v.get('byteStride',width*count)
 return [list(struct.unpack_from('<'+code*count,blob,start+i*stride)) for i in range(a['count'])]

def eye():return [[float(i==j) for j in range(4)] for i in range(4)]
def mul(a,b):return [[sum(a[i][k]*b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]
def vdot(a,b):return sum(x*y for x,y in zip(a,b))
def vcross(a,b):return [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]
def unit(v):
 l=math.sqrt(vdot(v,v));return [x/l for x in v]
def rigid(m):
 x=unit([m[i][0] for i in range(3)]);y0=[m[i][1] for i in range(3)]
 y=unit([y0[i]-x[i]*vdot(x,y0) for i in range(3)]);z=vcross(x,y)
 return [[x[i],y[i],z[i],m[i][3]] for i in range(3)]+[[0,0,0,1]]
def inverse(m):
 r=[[m[j][i] for j in range(3)] for i in range(3)];t=[m[i][3] for i in range(3)]
 return [r[i]+[-vdot(r[i],t)] for i in range(3)]+[[0,0,0,1]]
def cf(m):return [m[0][3],m[1][3],m[2][3],*[m[i][j] for i in range(3) for j in range(3)]]
def apply(m,p):return [sum(m[i][j]*p[j] for j in range(3))+m[i][3] for i in range(3)]
def node_matrix(n):
 if 'matrix' in n:return [[n['matrix'][j*4+i] for j in range(4)] for i in range(4)]
 x,y,z,w=n.get('rotation',[0,0,0,1]);s=n.get('scale',[1,1,1]);t=n.get('translation',[0,0,0])
 r=[[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],
    [2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],
    [2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]]
 return [[r[i][j]*s[j] for j in range(3)]+[t[i]] for i in range(3)]+[[0,0,0,1]]
def write(name,data):
 p=OUT/name;p.write_text(json.dumps(data,separators=(',',':'),allow_nan=False)+'\n')
 return {'path':name,'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}

nodes=g['nodes'];parents={c:i for i,n in enumerate(nodes) for c in n.get('children',[])}
world={}
def w(i):
 if i not in world:world[i]=mul(w(parents[i]),node_matrix(nodes[i])) if i in parents else node_matrix(nodes[i])
 return world[i]
for i in range(len(nodes)):w(i)
mesh_nodes=[i for i,n in enumerate(nodes) if 'mesh' in n]
assert len(mesh_nodes)==1
mesh_node=mesh_nodes[0]
assert max(abs(world[mesh_node][i][j]-eye()[i][j]) for i in range(4) for j in range(4))<1e-6
prims=g['meshes'][nodes[mesh_node]['mesh']]['primitives'];assert len(prims)==1
p=prims[0];assert p.get('mode',4)==4
a=p['attributes']
positions=accessor(a['POSITION']);normals=accessor(a['NORMAL']);uvs=accessor(a['TEXCOORD_0'])
joints=accessor(a['JOINTS_0']);weights=accessor(a['WEIGHTS_0']);indices=[r[0] for r in accessor(p['indices'])]
assert len(positions)==len(normals)==len(uvs)==len(joints)==len(weights)
assert len(indices)%3==0 and len(indices)//3<=20000
skin=g['skins'][nodes[mesh_node]['skin']];joint_nodes=skin['joints'];joint_names=[nodes[i]['name'] for i in joint_nodes]
turn=[[-1,0,0,0],[0,1,0,0],[0,0,-1,0],[0,0,0,1]]
binds={};max_rigid_error=0
for i in joint_nodes:
 m=mul(turn,world[i])
 for k in range(3):m[k][3]*=SCALE
 clean=rigid(m)
 max_rigid_error=max(max_rigid_error,max(abs(m[r][c]-clean[r][c]) for r in range(3) for c in range(3)))
 binds[i]=clean
assert max_rigid_error<1e-5
topological=[]
while len(topological)<len(joint_nodes):
 before=len(topological)
 for i in joint_nodes:
  if i not in topological and (parents.get(i) not in joint_nodes or parents[i] in topological):topological.append(i)
 assert len(topological)>before
bones=[]
for i in topological:
 parent=parents.get(i);is_parent=parent in joint_nodes
 local=mul(inverse(binds[parent]),binds[i]) if is_parent else binds[i]
 bones.append({'name':nodes[i]['name'],'parent':nodes[parent]['name'] if is_parent else None,
               'bindWorld':cf(binds[i]),'restLocal':cf(local),'virtual':False})
vertices=[]
maximum_weight_error=0
for pos,n,uv,js,ws in zip(positions,normals,uvs,joints,weights):
 assert abs(sum(ws)-1)<2e-6 and all(0<=j<len(joint_names) for j in js)
 maximum_weight_error=max(maximum_weight_error,abs(sum(ws)-1))
 q=[-pos[0]*SCALE,pos[1]*SCALE,-pos[2]*SCALE]
 nn=[-n[0],n[1],-n[2]]
 row=[*q,*nn,*uv]
 for j,weight in zip(js,ws):row.extend([j+1,weight])
 vertices.append(row)
faces=[[indices[k]+1,indices[k+1]+1,indices[k+2]+1] for k in range(0,len(indices),3)]
minimum=[min(v[i] for v in vertices) for i in range(3)];maximum=[max(v[i] for v in vertices) for i in range(3)]
vertex_chunks=[];face_chunks=[]
for at in range(0,len(vertices),1500):vertex_chunks.append(write(f'vertices-{at//1500+1:02}.json',{'start':at+1,'rows':vertices[at:at+1500]}))
for at in range(0,len(faces),3000):face_chunks.append(write(f'faces-{at//3000+1:02}.json',{'start':at+1,'rows':faces[at:at+3000]}))
material=g['materials'][p['material']]
images=[]
for image_index,image in enumerate(g['images']):
 view=g['bufferViews'][image['bufferView']];at=view.get('byteOffset',0);data=blob[at:at+view['byteLength']]
 extension='png' if image['mimeType']=='image/png' else 'jpg'
 path=OUT/f'texture-{image_index}.{extension}';path.write_bytes(data)
 images.append({'imageIndex':image_index,'path':path.name,'mimeType':image['mimeType'],'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()})
clips=[]
for name in ('WatchingIdle','SlowWindowLean','GlassTap'):
 source=SOURCE/(name+'-roblox-30fps.json');clip=json.loads(source.read_text());assert clip['modelGlbSha256']==EXPECTED
 clip['units']='studs';clip['metresToStuds']=SCALE;clip['actorForward']='-Z';clip['geometryWorldTurnYDegrees']=180
 for frame in clip['frames']:
  for row in frame['poses']:
   for i in (1,2,3):row[i]*=SCALE
 entry=write(name+'-8stud.json',clip);entry['name']=name;entry['frames']=len(clip['frames']);entry['duration']=clip['duration'];clips.append(entry)
manifest={'sourceGlbSha256':EXPECTED,'conversion':'Exact GLB arrays; uniform 8/2.4 scale and Y180 world turn. No remeshing, decimation, weld, UV flip or re-rig.',
 'units':'studs','actorForward':'-Z','metresToStuds':SCALE,'targetHeight':8,'vertices':len(vertices),'triangles':len(faces),'jointNames':joint_names,'bones':bones,
 'bounds':{'min':minimum,'max':maximum,'size':[maximum[i]-minimum[i] for i in range(3)],'center':[(maximum[i]+minimum[i])/2 for i in range(3)]},
 'vertexFormat':'[x,y,z,nx,ny,nz,u,v,jointIndex1,weight1,jointIndex2,weight2,jointIndex3,weight3,jointIndex4,weight4]; joint indices are ONE-based into jointNames',
 'faceFormat':'ONE-based vertex indices; GLB triangle winding preserved','vertexChunks':vertex_chunks,'faceChunks':face_chunks,
 'material':material,'textures':g.get('textures',[]),'samplers':g.get('samplers',[]),'images':images,'clips':clips,
 'validation':{'maxOriginalWeightSumError':maximum_weight_error,'maxBindRotationOrthonormalizationError':max_rigid_error,
 'note':'CFrame cannot encode exporter epsilon scale/shear; bind rotation is orthonormalized within stated error. Geometry/UV/normals/weights remain exact float values under stated rigid/uniform transform.'}}
write('manifest.json',manifest)
print(json.dumps({k:manifest[k] for k in ['sourceGlbSha256','vertices','triangles','bounds','validation']},indent=2))
print('OUTPUT='+str(OUT))
