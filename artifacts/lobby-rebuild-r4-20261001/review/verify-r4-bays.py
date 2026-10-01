"""Isolated background Blender geometry check; never opens the user's file."""
from pathlib import Path
import sys, json, math, hashlib
import bpy
from mathutils import Vector, Matrix

ROOT=Path('/Users/zeanjuul4/Documents/Roblox Horror REPO')
sys.path.insert(0,str(ROOT/'tools/lobby_reimagined'))
import props, r4_bays
LIB=bpy.data.collections.new('R4 bay isolated verification')
bpy.context.scene.collection.children.link(LIB)
FAMILIES={}
PLACEMENTS=[]; COLLIDERS=[]; LIGHTS=[]; PADS=[]; BAYS=[]
def material(name,rgb,rough=.72,metal=0):
    m=bpy.data.materials.new(name);m.use_nodes=True;m.diffuse_color=(*rgb,1)
    bs=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    bs.inputs['Base Color'].default_value=(*rgb,1)
    bs.inputs['Roughness'].default_value=rough;bs.inputs['Metallic'].default_value=metal
    return m
STEEL=material('STEEL',(.03,.03,.03));EDGE=material('EDGE',(.16,.16,.16))
CYAN=material('CYAN',(.02,.64,.61));AMBER=material('AMBER',(.7,.3,.05))
SCREEN=material('SCREEN',(.006,.006,.006))
class Geometry:
    def __init__(self,name):self.name=name;self.v=[];self.f=[];self.mi=[];self.m=[]
    def face(self,points,mat):
        if mat not in self.m:self.m.append(mat)
        at=len(self.v);self.v.extend(points);self.f.append(tuple(range(at,at+len(points))));self.mi.append(self.m.index(mat))
    def box(self,c,s,mat,rotation=None):r4_bays._box(self,c,s,mat,(0,0,rotation or 0))
    def cylinder(self,c,r,h,mat,n=40):
        rings=[[(c[0]+r*math.cos(i*math.tau/n),c[1]+r*math.sin(i*math.tau/n),c[2]+z*h/2)for i in range(n)]for z in (-1,1)]
        self.face(list(reversed(rings[0])),mat);self.face(rings[1],mat)
        for i in range(n):j=(i+1)%n;self.face([rings[0][i],rings[0][j],rings[1][j],rings[1][i]],mat)
    def object(self):
        m=bpy.data.meshes.new(self.name);m.from_pydata(self.v,[],self.f);m.update()
        for mat in self.m:m.materials.append(mat)
        for p,mi in zip(m.polygons,self.mi):p.material_index=mi
        o=bpy.data.objects.new(self.name,m);LIB.objects.link(o);FAMILIES[self.name]=[o];return o
def place(family,x,y,z=0,yaw=0,kind=None):
    if family not in FAMILIES:raise ValueError('Missing family '+family)
    PLACEMENTS.append({'family':family,'robloxPosition':[x,z,-y],'yaw':yaw})
def collider(name,c,s,yaw=0):COLLIDERS.append({'name':name,'position':[c[0],c[2],-c[1]],'size':[s[0],s[2],s[1]],'yaw':yaw})
def light(name,c,color,bright=1.4,rng=22):LIGHTS.append({'name':name,'position':[c[0],c[2],-c[1]],'color':color,'brightness':bright,'range':rng})
library=props.build_library(LIB)
aliases={'BrownOfficeChair':'BrownOfficeChair','BrownStackChair':'StackChair','FourDrawerFilingCabinet':'FilingCabinet','OliveVinylBench':'VinylBench'}
for name,row in library.items():FAMILIES[aliases.get(name,name)]=row['objects']
g=Geometry('QueuePad');g.cylinder((0,0,.37),7.41,.74,STEEL,64);g.cylinder((0,0,.77),7.1,.1,SCREEN,64);g.object()
receipt=r4_bays.build_bays(globals())
for family in FAMILIES.values():
    for o in family:
        assert all(math.isfinite(v)for p in o.data.vertices for v in p.co)
for c in COLLIDERS:assert min(c['size'])>0
assert len(PADS)==24 and len(BAYS)==6
for p in PADS:
    x,y,z=p['kioskPosition'];target=p['position'];normal=Vector((math.sin(p['kioskYaw']),0,math.cos(p['kioskYaw'])))
    toward=Vector((target[0]-x,0,target[2]-z))
    assert normal.dot(toward)>0,'Monitor does not face its pad'
    assert p['statusLocalSize'][0]>11 and p['maxPartySize']==6
owned=[o for family in receipt['createdFamilies'] for o in FAMILIES[family]]
triangles={o.name:sum(len(p.vertices)-2 for p in o.data.polygons)for o in owned}
smooth_counts={o.name:sum(p.use_smooth for p in o.data.polygons)for o in owned if o.name.startswith('BayShell')}
receipt.update({'blenderVersion':bpy.app.version_string,'ownedUniqueTriangles':sum(triangles.values()),
   'trianglesByFamily':triangles,'smoothWallFaces':smooth_counts,'placements':len(PLACEMENTS),
   'colliders':len(COLLIDERS),'lights':len(LIGHTS),'materials':len(bpy.data.materials),
   'padAndMonitorFacingChecks':'passed','finiteMeshAndColliderChecks':'passed',
   'helperSha256':hashlib.sha256((ROOT/'tools/lobby_reimagined/r4_bays.py').read_bytes()).hexdigest(),
   'verificationScope':'isolated authoring geometry only, no Studio import or Play test'})
out=ROOT/'artifacts/lobby-rebuild-r4-20261001/review/r4-bay-helper-verification.json'
out.write_text(json.dumps(receipt,indent=2)+'\n')
print('R4_BAY_VERIFIED',json.dumps(receipt))
