"""Blender-authored isolated lobby preview; one Blender unit is one Roblox stud.

Run with Blender --background --factory-startup --python this_file. Never opens
or overwrites the user's Blender scene or writes to Roblox. Shared prefab mesh
format is exported with the proper X,Z,-Y rotation. Runtime text stays native.
"""
from pathlib import Path
import sys, math, json, hashlib, base64, random, struct
import bpy
from mathutils import Vector, Matrix

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/models/lobby-reimagined-20261001'
OUT.mkdir(parents=True, exist_ok=True)
sys.path.insert(0, str(Path(__file__).parent))
sys.path.insert(0, str(ROOT / 'tools/level6_build/import'))
from export_prefabs import export_prefab

LIB = bpy.data.collections.new('Lobby Preview | Reusable Blender Kit')
bpy.context.scene.collection.children.link(LIB)
FAMILIES = {}
MATERIALS = {}
PLACEMENTS, COLLIDERS, SIGNS, LIGHTS, PADS = [], [], [], [], []

def material(name, rgb, rough=.72, metal=0):
    m = bpy.data.materials.new('LRP_'+name); m.use_nodes=True
    m.diffuse_color=tuple(rgb)+(1,)
    sh=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    sh.inputs['Base Color'].default_value=tuple(rgb)+(1,)
    sh.inputs['Roughness'].default_value=rough; sh.inputs['Metallic'].default_value=metal
    MATERIALS[name]=m
    return m

CONCRETE=material('aged_yellow_concrete',(.47,.39,.17))
ASPHALT=material('asphalt',(.052,.058,.059),.92)
CURB=material('sidewalk_concrete',(.35,.32,.21),.86)
STEEL=material('dark_steel',(.027,.032,.034),.52,.7)
EDGE=material('rubbed_steel',(.16,.175,.18),.42,.8)
CYAN=material('cyan_lens',(.035,.66,.63),.3)
AMBER=material('amber_lens',(.92,.48,.1),.4)
ORANGE=material('orange_wall',(.52,.17,.052),.86)
CARPET=material('party_carpet',(.065,.055,.065),.96)
PAINT=material('yellow_lane_paint',(.59,.42,.045),.9)
SCREEN=material('screen_black',(.011,.017,.018),.4)
for mat in (CYAN,AMBER):
    sh=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    sh.inputs['Emission Color'].default_value=mat.diffuse_color;sh.inputs['Emission Strength'].default_value=1.4

class Geometry:
    def __init__(self,name): self.name=name; self.v=[]; self.f=[]; self.mi=[]; self.m=[]
    def face(self,points,mat):
        if mat not in self.m:self.m.append(mat)
        start=len(self.v); self.v.extend(points); self.f.append(tuple(range(start,start+len(points))));self.mi.append(self.m.index(mat))
    def box(self,c,s,mat,rotation=None):
        verts=[Vector((c[0]+a*s[0]/2,c[1]+b*s[1]/2,c[2]+d*s[2]/2)) for a,b,d in [(-1,-1,-1),(-1,-1,1),(-1,1,-1),(-1,1,1),(1,-1,-1),(1,-1,1),(1,1,-1),(1,1,1)]]
        if rotation:
            p=Vector(c); rot=Matrix.Rotation(rotation,3,'Z');verts=[p+rot@(v-p) for v in verts]
        for ids in [(0,4,6,2),(1,3,7,5),(0,1,5,4),(2,6,7,3),(0,2,3,1),(4,5,7,6)]:self.face([verts[i] for i in ids],mat)
    def cylinder(self,c,r,h,mat,n=40):
        lo=[(c[0]+r*math.cos(i*math.tau/n),c[1]+r*math.sin(i*math.tau/n),c[2]-h/2) for i in range(n)]
        hi=[(x,y,c[2]+h/2) for x,y,_ in lo]
        self.face(list(reversed(lo)),mat);self.face(hi,mat)
        for i in range(n):j=(i+1)%n;self.face([lo[i],lo[j],hi[j],hi[i]],mat)
    def ring(self,c,r,width,h,mat,n=64):
        for i in range(n):
            a=i*math.tau/n;b=(i+1)*math.tau/n
            coords=[(c[0]+rr*math.cos(t),c[1]+rr*math.sin(t),z) for z in (c[2]-h/2,c[2]+h/2) for rr in (r-width/2,r+width/2) for t in (a,b)]
            for ids in [(0,1,3,2),(4,6,7,5),(0,4,5,1),(2,3,7,6)]:self.face([coords[k] for k in ids],mat)
    def arc(self,r,t0,t1,y0,y1,thickness,mat,n=40):
        for i in range(n):
            a=t0+(t1-t0)*i/n;b=t0+(t1-t0)*(i+1)/n
            v=[(rr*math.cos(t),yy,1+rr*math.sin(t)) for yy in (y0,y1) for rr in (r,r+thickness) for t in (a,b)]
            for ids in [(0,4,5,1),(2,3,7,6),(0,1,3,2),(4,6,7,5),(0,2,6,4),(1,5,7,3)]:self.face([v[k] for k in ids],mat)
    def object(self):
        mesh=bpy.data.meshes.new(self.name);mesh.from_pydata(self.v,[],self.f);mesh.update()
        for m in self.m:mesh.materials.append(m)
        for p,i in zip(mesh.polygons,self.mi):p.material_index=i
        o=bpy.data.objects.new(self.name,mesh);LIB.objects.link(o);FAMILIES[self.name]=[o];return o

def place(family,x,y,z=0,yaw=0,kind=None):
    # Input in Blender coordinate frame, serialized positions in Roblox frame.
    item={'family':family,'robloxPosition':[x,z,-y],'yaw':yaw}
    if kind:item['runtimeKind']=kind
    PLACEMENTS.append(item)

def collider(name,c,s,yaw=0):COLLIDERS.append({'name':name,'position':[c[0],c[2],-c[1]],'size':[s[0],s[2],s[1]],'yaw':yaw})
def light(name,c,color,bright=1.4,rng=22):LIGHTS.append({'name':name,'position':[c[0],c[2],-c[1]],'color':color,'brightness':bright,'range':rng})

# Reusable plain and portal shells; portal gaps are genuinely open geometry.
for portal in (False,True):
    g=Geometry('PortalShell' if portal else 'PlainShell')
    runs=[(-20,-10,0,math.pi),(-10,10,.64,math.pi-.64),(10,20,0,math.pi)] if portal else [(-20,20,0,math.pi)]
    for y0,y1,a,b in runs:g.arc(35,a,b,y0,y1,1.1,CONCRETE,36)
    for side in (-1,1):
        for y0,y1 in ([(-20,-10),(10,20)] if portal else [(-20,20)]):g.box((side*34.5,(y0+y1)/2,4),(1.4,y1-y0,8),CONCRETE)
    g.object()
for i,y in enumerate(range(-120,121,40)):
    portal=y in (-80,0,80);place('PortalShell' if portal else 'PlainShell',0,y)
    runs=[(-20,-10,0,math.pi),(-10,10,.64,math.pi-.64),(10,20,0,math.pi)] if portal else [(-20,20,0,math.pi)]
    for ya,yb,ta,tb in runs:
        for j in range(24):
            angle=ta+(tb-ta)*(j+.5)/24
            collider('Arch Collision',(35.3*math.cos(angle),y+(ya+yb)/2,1+35.3*math.sin(angle)),(2*35.3*math.sin((tb-ta)/48)+.1,yb-ya,1.1))
            COLLIDERS[-1]['rotation']=[0,0,angle+math.pi/2]
    for side in (-1,1):
        for ya,yb in ([(-20,-10),(10,20)] if portal else [(-20,20)]):collider('Lower Tunnel Wall',(side*34.2,y+(ya+yb)/2,4),(1.3,yb-ya,8))

g=Geometry('ArchRib');g.arc(33.9,0,math.pi,-.6,.6,.75,STEEL,40)
for side in (-1,1):
    g.box((side*33.5,0,1.4),(2.5,2.8,2.8),STEEL)
    for yy in (-.9,.9):
        for zz in (.6,2.1):g.box((side*32.22,yy,zz),(.13,.22,.22),EDGE)
for a in (.35,.65,1.05,1.5,1.95,2.5,2.8):g.box((33.85*math.cos(a),0,1+33.85*math.sin(a)),(.7,1.65,.7),EDGE)
g.object()
for y in range(-130,131,20):place('ArchRib',0,y)

g=Geometry('RoadSection');g.box((0,0,-.5),(33,40,1),ASPHALT)
for y in (-15,-5,5,15):g.box((0,y,.015),(.28,4,.035),PAINT)
for side in (-1,1):g.box((side*16.05,0,.01),(.12,40,.03),PAINT)
g.object()
g=Geometry('SidewalkSection');g.box((0,0,.4),(16.6,40,.8),CURB)
for y in (-16,-8,0,8,16):g.box((0,y,.812),(16.2,.04,.025),STEEL)
for x in (-5.4,0,5.4):g.box((x,0,.812),(.035,39.9,.025),STEEL)
for y in range(-18,19,4):
    g.box((-7.7,y,.84),(.65,2.7,.06),STEEL)
    for v in (-.9,-.5,-.1,.3,.7):g.box((-7.7,y+v,.88),(.59,.06,.03),EDGE)
    g.box((-8.2,y,.65),(.1,1.5,.16),CYAN)
g.object()
for y in range(-120,121,40):
    place('RoadSection',0,y);collider('Road',(0,y,-.5),(33,40,1))
    for side in (-1,1):place('SidewalkSection',side*25,y,yaw=0 if side==1 else math.pi);collider('Sidewalk',(side*25,y,.4),(16.6,40,.8))

g=Geometry('CableTray');
for x in (-1,1):g.box((x,0,0),(.16,20,.65),STEEL)
for y in range(-10,11,2):g.box((0,y,-.32),(2.05,.11,.12),EDGE)
for x in (-.65,-.25,.25,.65):g.box((x,0,.05),(.075,20,.1),STEEL)
g.object()
g=Geometry('Fluorescent');g.box((0,0,0),(3.7,1.2,.6),STEEL);g.box((0,0,-.32),(3.1,.8,.08),CYAN)
for side in (-1,1):g.box((side*1.6,0,-.35),(.14,.95,.14),EDGE)
g.object()
for y in range(-130,131,20):
    for side in (-1,1):place('CableTray',side*11,y,32.4);place('Fluorescent',side*11,y,30.6);light('Tunnel Lamp',(side*11,y,29.5),[.24,.78,.72],1.25,28)

g=Geometry('ServicePanel');g.box((0,0,0),(.4,3,2.2),STEEL)
for z in (-.8,-.5,-.2,.1,.4,.7):g.box((-.24,0,z),(.12,2.65,.12),EDGE)
g.box((-.29,1.1,-.78),(.11,.2,.2),AMBER);g.object()
g=Geometry('ConduitSection')
for z in (0,.38,.76):g.box((0,0,z),(.14,20,.14),STEEL)
for y in (-8,-2,4,9):g.box((0,y,.35),(.32,.18,1.1),EDGE)
g.object()
for side in (-1,1):
    for y in range(-130,131,20):
        if all(abs(y-gate)>10 for gate in (-80,0,80)):place('ConduitSection',side*32.85,y,12,yaw=0 if side<0 else math.pi)
    for y in (-120,-40,40,120):place('ServicePanel',side*32.6,y,6,yaw=0 if side>0 else math.pi)

g=Geometry('LevelGate')
for side in (-1,1):
    g.box((side*10.7,0,9.7),(1.5,2,19.4),STEEL)
    g.box((side*10.7,-1.08,4.6),(.16,.13,7),CYAN)
    g.box((side*10.7,-1.08,1.4),(1.3,.12,2.8),PAINT)
    for z in (1,3,6,9,12,15,18):g.box((side*10.7,-1.08,z),(.22,.1,.22),EDGE)
g.box((0,0,20),(24,2.6,4.2),STEEL);g.box((0,-1.38,17.9),(21.8,.18,.2),CYAN)
g.box((-11,-9.1,18.4),(.75,7.8,3.4),STEEL)
g.box((-11,-9.1,16.6),(.82,7.2,.13),CYAN)
g.box((-11,-5.2,14.1),(.65,7.9,.4),EDGE)
g.box((-11,-9.1,16.1),(.65,.4,4.1),EDGE)
g.object()

g=Geometry('QueueRoom')
g.cylinder((0,0,.38),27.7,.76,CARPET,72)
g.cylinder((0,0,22),28,.6,CURB,72)
for i in range(52):
    a=math.radians(-66+312*i/52);b=math.radians(-66+312*(i+1)/52)
    v=[(rr*math.cos(t),rr*math.sin(t),z) for z in (.8,21.8) for rr in (27.5,28.15) for t in (a,b)]
    for ids in [(0,1,5,4),(2,6,7,3),(4,5,7,6),(0,2,3,1)]:g.face([v[k] for k in ids],ORANGE)
    g.box((27.15*math.cos(a),27.15*math.sin(a),10.8),(.11,.11,20),STEEL)
g.object()
g=Geometry('QueuePad');g.cylinder((0,0,.37),7.4,.74,STEEL,64);g.cylinder((0,0,.77),7.1,.1,SCREEN,64);g.ring((0,0,.79),7.2,.11,.055,CYAN);g.ring((0,0,.8),6.85,.06,.025,EDGE);g.object()
g=Geometry('QueueKiosk');g.box((0,0,1.7),(1.6,1.2,3.4),STEEL);g.box((0,-.2,3.45),(1.7,.2,1.6),STEEL);g.box((0,-.33,3.47),(1.5,.045,1.35),SCREEN);g.box((0,-.4,2.65),(1.4,.05,.12),CYAN);g.object()
g=Geometry('DoorThreshold');g.box((0,0,.55),(20,6.2,1.1),CURB);g.box((0,-3,1.105),(19.6,.08,.025),EDGE);g.object()
g=Geometry('HologramRing');g.ring((0,0,.04),7.18,.085,.07,CYAN);g.object()
g=Geometry('HologramBand')
for i in range(64):
    a=i*math.tau/64;b=(i+1)*math.tau/64;r=7.18
    g.face([(r*math.cos(a),r*math.sin(a),0),(r*math.cos(b),r*math.sin(b),0),(r*math.cos(b),r*math.sin(b),.6),(r*math.cos(a),r*math.sin(a),.6)],CYAN)
g.object()
for side in (-1,1):
    angle=math.pi/2 if side<0 else -math.pi/2
    for row in (-80,0,80):
        level={(-1,-80):1,(-1,0):3,(-1,80):5,(1,-80):2,(1,0):4,(1,80):6}[(side,row)]
        y=-row;place('LevelGate',side*33.1,y,.8,yaw=angle)
        place('QueueRoom',side*63,y,.4,yaw=angle)
        place('DoorThreshold',side*34.4,y,yaw=angle)
        collider('Door Threshold',(side*34.4,y,.55),(6.2,20,1.1))
        # Collider floor and walls; opening is kept free of collision geometry.
        collider('Bay Floor',(side*63,y,.76),(55.4,55.4,.8));COLLIDERS[-1]['shape']='Cylinder'
        rot=Matrix.Rotation(angle,3,'Z')
        for i in range(32):
            t=math.radians(-66+312*(i+.5)/32);p=rot@Vector((27.8*math.cos(t),27.8*math.sin(t),11))
            collider('Bay Wall',(side*63+p.x,y+p.y,11.4),(.6,4.8,21.2),t+angle)
        collider('Bay Roof',(side*63,y,22.4),(55,55,.5))
        # Native signs match the exact Blender lintel and separate blade host.
        SIGNS.append({'level':level,'side':side,'row':row,'gatePosition':[side*33.1,.8,row],'yaw':angle})
        for dx,dy in [(-11,-9),(11,-9),(-11,10),(11,10)]:
            point=rot@Vector((dx,dy,0));cx,cy=side*63+point.x,y+point.y
            place('QueuePad',cx,cy,1.0);place('QueueKiosk',cx-8,cy,1.0,yaw=angle)
            PADS.append({'level':level,'position':[cx,1.79,-cy],'radius':7.18})
            collider('Queue Pad',(cx,cy,1.42),(14.8,14.8,.8));COLLIDERS[-1]['shape']='Cylinder'
        for dx,dy in [(-12,-12),(12,-12),(-12,12),(12,12)]:
            v=rot@Vector((dx,dy,0));place('Fluorescent',side*63+v.x,y+v.y,21.4);light('Bay Lamp',(side*63+v.x,y+v.y,20.5),[1,.72,.38],1.35,24)

g=Geometry('StageDeck');g.box((0,0,2.25),(30,17,4.5),STEEL)
for i in range(6):
    z=4.5*(i+1)/6;yy=14.5-i
    g.box((0,yy,z/2),(30,2.02 if i==5 else 1.02,z),STEEL);g.box((0,yy+.51,z+.02),(28,.06,.06),AMBER)
g.box((0,8.5,4.52),(29.8,.06,.08),AMBER);g.object();place('StageDeck',0,-120)
collider('Stage Deck',(0,-120,2.25),(30,17,4.5))
for i in range(6):z=4.5*(i+1)/6;collider('Stage Step',(0,-120+14.5-i,z/2),(30,2.02 if i==5 else 1.02,z))
for x in (-10,0,10):light('Stage Fill',(x,-114,17),[1,.57,.23],1.6,22)
for side in (-1,1):
    for y in range(-120,121,40):light('Warm Wall Fill',(side*27,y,12),[1,.68,.3],1.0,23)

# Add the independently authored, measured prop kit.
import props
prop_assets=props.build_library(LIB)
aliases={'FloralSofa90s':'Sofa','OliveVinylBench':'VinylBench','LaminateOfficeDesk':'Desk','FourDrawerFilingCabinet':'FilingCabinet','BeigeCRTMonitor':'CRTMonitor','OfficePhotocopier':'Photocopier','BrownStackChair':'StackChair','WireServiceTrolley':'WireTrolley','TwinDeckDJConsole':'DJConsole','FestivalTrussSpeakerTower':'SpeakerTower','TwinSubwoofer':'Subwoofer'}
for name,row in prop_assets.items():FAMILIES[aliases.get(name,name)]=row['objects'] if isinstance(row,dict) else row
place('DJConsole',0,-121,4.5,yaw=math.pi)
for x in (-21,21):place('SpeakerTower',x,-120,.8,yaw=math.pi);place('Subwoofer',x,-114,.8,yaw=math.pi)
dj_meta=prop_assets['TwinDeckDJConsole']['metadata']
disc_anchors=dj_meta['anchors_xyz']
for key,a in disc_anchors.items():
    v=Matrix.Rotation(math.pi,3,'Z')@Vector(a)
    place(dj_meta['record_assets'][key],v.x,-121+v.y,4.5+v.z,yaw=math.pi,kind='VinylDisc')

# Large recognizable families form the near blockoff and far wings/backstop.
rng=random.Random(61322)
furniture=[n for n in ('Sofa','VinylBench','Desk','FilingCabinet','CRTMonitor','Photocopier','StackChair','WireTrolley') if n in FAMILIES]
furniture_bounds={aliases.get(name,name):row['bounds_xyz'] for name,row in prop_assets.items() if aliases.get(name,name) in furniture}
for far in (False,True):
    pile_tops,pile_x={},{}
    for tier in range(3):
        for idx,x in enumerate((-27,-17,-7,7,17,27)):
            if far and tier<2 and abs(x)<17:continue
            family=furniture[(idx+tier*3+(2 if far else 0))%len(furniture)]
            lower,upper=furniture_bounds[family]
            stacked=idx in pile_tops
            floor=.8 if abs(x)>=16.5 else 0
            base=pile_tops.get(idx,floor)-lower[2]-(.15 if stacked else 0)
            jitter=rng.uniform(-1,1)
            pile_x.setdefault(idx,x+jitter)
            # Actual grounded mesh heights support the next object, with a small
            # overlap and limited drift. Far-center singletons start on the road.
            y=(-134-tier*.25) if far else (132+tier*.25)
            place(family,pile_x[idx]+(jitter*.15 if stacked else 0),y,base,yaw=rng.uniform(-.55,.55)+(math.pi if far else 0))
            pile_tops[idx]=base+upper[2]
            if tier==0:collider('Furniture Base',(x,y,2.4),(8,5,4))
    collider('Opaque End Cap',(0,-139 if far else 139,18),(70,2,36))
g=Geometry('EndBackstop');g.box((0,0,18),(70,1.2,36),CONCRETE);g.object();place('EndBackstop',0,-139);place('EndBackstop',0,139)

def atlasify():
    # A deterministic color/wear atlas, created from the authored materials.
    # Each face stays inside its material tile; never edits a reference image.
    mats=[]
    for objs in FAMILIES.values():
        for o in objs:
            if o.type=='MESH':
                for m in o.data.materials:
                    if m and m not in mats:mats.append(m)
    assert len(mats)<=64, len(mats)
    w=1024;raw=bytearray(w*w*4);tile=128
    for index,m in enumerate(mats):
        sh=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED');rgb=list(sh.inputs['Base Color'].default_value)[:3]
        # Blender shader colors are linear; texture's sRGB encoding is explicit.
        rgb=[int(255*(12.92*c if c<=.0031308 else 1.055*c**(1/2.4)-.055)) for c in rgb]
        tr=random.Random(900+index);tx=(index%8)*tile;ty=(index//8)*tile
        for yy in range(tile):
            for xx in range(tile):
                noise=tr.uniform(.9,1.035);name=m.name.lower()
                if 'concrete' in name:noise*=.7 if tr.random()<.035 else 1
                if 'carpet' in name and ((xx%31<2 and yy%21<8) or (xx%27<8 and yy%33<2)):color=(153,71,22)
                elif ('uphol' in name or 'sofa' in name) and (xx%25-12)**2+(yy%25-12)**2<20:color=(87,66,34)
                elif 'wood' in name:color=tuple(max(0,min(255,int(c*(.82+.18*math.sin(xx*.6+math.sin(yy*.15)))))) for c in rgb)
                else:color=tuple(max(0,min(255,int(c*noise))) for c in rgb)
                off=((ty+yy)*w+tx+xx)*4;raw[off:off+4]=bytes((*color,255))
    image=bpy.data.images.new('Lobby Preview | Color Wear Atlas',width=w,height=w,alpha=True)
    image.pixels.foreach_set([v/255 for v in raw]);image.update();image.filepath_raw=str(OUT/'atlas.png')
    formats=[i.identifier for i in bpy.context.scene.render.image_settings.bl_rna.properties['file_format'].enum_items]
    assert 'PNG' in formats;image.file_format='PNG';image.save();image.pack()
    (OUT/'atlas.rgba.b64').write_bytes(base64.b64encode(raw))
    for m in mats:
        sh=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED');node=m.node_tree.nodes.new('ShaderNodeTexImage');node.image=image
        m.node_tree.links.new(node.outputs['Color'],sh.inputs['Base Color'])
    for objs in FAMILIES.values():
        for o in objs:
            if o.type!='MESH':continue
            uv=o.data.uv_layers.get('AtlasUV') or o.data.uv_layers.new(name='AtlasUV')
            o.data.uv_layers.active_index=list(o.data.uv_layers).index(uv)
            uv.active_render=True
            for p in o.data.polygons:
                mat=o.data.materials[p.material_index];i=mats.index(mat);normal=p.normal;drop=max(range(3),key=lambda a:abs(normal[a]));axes=[a for a in range(3) if a!=drop]
                coords=[o.data.vertices[o.data.loops[l].vertex_index].co for l in p.loop_indices]
                mins=[min(v[a] for v in coords) for a in axes];maxs=[max(v[a] for v in coords) for a in axes]
                for l,v in zip(p.loop_indices,coords):
                    q=[.04+.92*(v[a]-mi)/max(.001,ma-mi) for a,mi,ma in zip(axes,mins,maxs)]
                    uv.data[l].uv=((i%8+q[0])/8,(i//8+q[1])/8)
    return raw,mats

raw,mats=atlasify()
chunks=[]
for name,objs in sorted(FAMILIES.items()):chunks.append(export_prefab(name,objs,OUT,len(chunks),metadata={'family':name}))

# Full assembled scene is editable and uses linked data for repeated assets.
scene=bpy.data.scenes.new('Lobby Reimagined | Full Preview')
bpy.context.window.scene=scene
for item in PLACEMENTS:
    x,z,minusy=item['robloxPosition'];point=Vector((x,-minusy,z));rot=Matrix.Rotation(item['yaw'],4,'Z')
    for src in FAMILIES[item['family']]:
        o=src.copy();o.data=src.data;scene.collection.objects.link(o);o.matrix_world=Matrix.Translation(point)@rot@src.matrix_world
for li in LIGHTS:
    x,z,minusy=li['position'];data=bpy.data.lights.new(li['name'],'POINT');data.energy=420 if 'Bay' in li['name'] else 600;data.color=li['color'];data.shadow_soft_size=1
    data.energy=1450 if 'Warm Wall' in li['name'] else (1200 if 'Stage' in li['name'] else 800)
    o=bpy.data.objects.new(li['name'],data);o.location=(x,-minusy,z);scene.collection.objects.link(o)
for s in SIGNS:
    side,row=s['side'],s['row'];data=bpy.data.curves.new('LEVEL '+str(s['level']),'FONT');data.body='LEVEL '+str(s['level']);data.size=2.65;data.align_x='CENTER';data.extrude=.015
    o=bpy.data.objects.new(data.body,data);scene.collection.objects.link(o);o.location=(side*31.72,-row,20.05);o.rotation_euler=(math.pi/2,0,math.pi/2 if side<0 else -math.pi/2);o.data.materials.append(CYAN if s['level']<=3 else AMBER)
    gate=Matrix.Translation(Vector((side*33.1,-row,.8)))@Matrix.Rotation(s['yaw'],4,'Z')
    for face in (-1,1):
        font=bpy.data.curves.new('Projecting LEVEL '+str(s['level']),'FONT');font.body=('LEVEL '+str(s['level'])+' →') if face>0 else ('← LEVEL '+str(s['level']))
        font.size=1.12;font.align_x='CENTER';font.extrude=.008;font.materials.append(CYAN if s['level']<=3 else AMBER)
        sign=bpy.data.objects.new(font.body,font);scene.collection.objects.link(sign)
        orientation=Matrix(((0,0,face,0),(face,0,0,0),(0,1,0,0),(0,0,0,1)))
        sign.matrix_world=gate@Matrix.Translation(Vector((-11+face*.385,-9.1,17.75)))@orientation
world=bpy.data.worlds.new('Enclosed night preview');world.use_nodes=True;scene.world=world
bg=next(n for n in world.node_tree.nodes if n.type=='BACKGROUND');bg.inputs['Color'].default_value=(.025,.028,.03,1);bg.inputs['Strength'].default_value=.08
camdata=bpy.data.cameras.new('Full tunnel camera');cam=bpy.data.objects.new('Full tunnel camera',camdata);scene.collection.objects.link(cam)
cam.location=(0,118,7);target=Vector((0,-100,12));cam.rotation_euler=(target-Vector(cam.location)).to_track_quat('-Z','Y').to_euler();camdata.lens=22;scene.camera=cam
scene.render.resolution_x=1400;scene.render.resolution_y=820;scene.render.resolution_percentage=100
try:scene.render.engine='CYCLES';scene.cycles.samples=24
except TypeError:pass
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'LobbyReimaginedPreview.blend'),compress=True)
manifest={'schema':'lobby-reimagined-blender-v1','placeId':131311258779917,'groupId':1039373905,'previewCenter':[220,30,-760],'axisMapping':'X,Z,-Y','studsPerUnit':1,
    'sourceBlendSha256':hashlib.sha256((OUT/'LobbyReimaginedPreview.blend').read_bytes()).hexdigest(),'atlas':{'width':1024,'height':1024,'file':'atlas.rgba.b64','bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest()},
    'chunks':chunks,'prefabs':[c['family'] for c in chunks],'placements':PLACEMENTS,'colliders':COLLIDERS,'signs':SIGNS,'lights':LIGHTS,'pads':PADS,
    'uniqueTriangles':sum(c['triangles'] for c in chunks),'instantiatedTriangles':sum(next(c['triangles'] for c in chunks if c['family']==p['family']) for p in PLACEMENTS),'materialCount':len(mats),
    'vinylDiscCount':len(disc_anchors),'runtimeNotes':'Isolated dev preview; no actual level launches or live queue edits. E demo controls visual queue cylinder.'}
(OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
export_scene=bpy.data.scenes.new('Roblox FBX | Opaque Color Atlas')
export_mat=bpy.data.materials.new('LRP_FBX_Atlas');export_mat.use_nodes=True
shader=next(n for n in export_mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED');node=export_mat.node_tree.nodes.new('ShaderNodeTexImage');node.image=bpy.data.images['Lobby Preview | Color Wear Atlas'];export_mat.node_tree.links.new(node.outputs['Color'],shader.inputs['Base Color'])
export_data={}
for src in scene.objects:
    if src.type!='MESH':continue
    if src.data.name not in export_data:
        mesh=src.data.copy();mesh.materials.clear();mesh.materials.append(export_mat)
        for polygon in mesh.polygons:polygon.material_index=0
        export_data[src.data.name]=mesh
    o=bpy.data.objects.new(src.name,export_data[src.data.name]);o.matrix_world=src.matrix_world;export_scene.collection.objects.link(o)
bpy.context.window.scene=export_scene
for o in export_scene.objects:o.select_set(True)
bpy.ops.export_scene.fbx(filepath=str(OUT/'LobbyReimaginedPreview.fbx'),use_selection=True,object_types={'MESH'},axis_forward='-Z',axis_up='Y',global_scale=1,apply_unit_scale=True,bake_anim=False,use_mesh_modifiers=True,path_mode='COPY',embed_textures=True,add_leaf_bones=False)
bpy.context.window.scene=scene
scene.render.filepath=str(OUT/'blender-tunnel-preview.png');bpy.ops.render.render(write_still=True)
print('LOBBY_PREVIEW_BUILT',json.dumps({k:v for k,v in manifest.items() if k not in ('chunks','placements','colliders','signs','lights','pads')}),flush=True)
