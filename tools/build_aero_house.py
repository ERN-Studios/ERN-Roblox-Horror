"""Original Frutiger Aero house; run in a separate Blender background process.

Coordinates are Roblox studs with Blender Z up; no live place data is consumed.
All render styling is kept in the source; only selected authored meshes export.
"""
import bpy, bmesh, math, json, sys, random
from pathlib import Path
from mathutils import Vector, Matrix

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/models/aero-house'
sys.path.insert(0, str(ROOT/'tools'))
random.seed(2909)
BUILDERS, COLLIDERS, LIGHTS = {}, [], []

def enum(obj, prop, value):
    valid = {i.identifier for i in obj.bl_rna.properties[prop].enum_items}
    if value not in valid: raise ValueError((prop,value,sorted(valid)))
    setattr(obj,prop,value)

scene = bpy.data.scenes.new('Aero House')
bpy.context.window.scene = scene
enum(scene.unit_settings,'system','NONE')
scene.unit_settings.scale_length=1
geo=bpy.data.collections.new('AERO | Import Geometry')
scene.collection.children.link(geo)
pres=bpy.data.collections.new('AERO | Presentation only')
scene.collection.children.link(pres)

PALETTE={
 'White':('#e9f6ef',.25,0), 'Pearl':('#d3e9e5',.30,0),
 'Cyan':('#10aec7',.24,.10), 'Aqua':('#6bdddb',.27,0),
 'Lime':('#9bd92b',.31,0), 'Leaf':('#459927',.50,0),
 'Navy':('#15446b',.32,0), 'Chrome':('#a1c4c7',.23,.78),
 'FabricWhite':('#e0eee2',.60,0), 'FabricLime':('#8dcb39',.56,0),
 'FabricCyan':('#55c7cc',.55,0), 'Glow':('#e2fff8',.28,0),
 'Glass':('#8bdae0',.10,0), 'Grass':('#7abd39',.85,0),
 'Dark':('#243f46',.44,0), 'Screen':('#49bace',.35,0),
}
KEYS=list(PALETTE)
def srgb(v):return v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4
def rgb(key):return tuple(int(PALETTE[key][0][i:i+2],16)/255 for i in (1,3,5))

class Batch:
    def __init__(self,name,kind):self.name=name;self.kind=kind;self.v=[];self.f=[];self.tiles=[];self.smooth=[]
    def add(self,vs,fs,key,smooth=False):
        n=len(self.v);self.v.extend(tuple(v) for v in vs);self.f.extend(tuple(n+i for i in f) for f in fs)
        self.tiles.extend([KEYS.index(key)]*len(fs))
        self.smooth.extend(smooth if isinstance(smooth,list) else [smooth]*len(fs))
def batch(name,key):
    prefix=name.split('__')[0];kind='Glass' if key=='Glass' else ('Glow' if key in ('Glow','Screen') else 'Palette')
    k=(prefix,kind)
    if k not in BUILDERS:BUILDERS[k]=Batch(prefix if prefix.startswith('Aero_Anchor_') else 'Aero_'+prefix+'_'+kind,kind)
    return BUILDERS[k]

def collider(name,c,d,rz=0):
    COLLIDERS.append({'name':name+'_'+str(len(COLLIDERS)+1).zfill(3),'position':[c[0],c[2],-c[1]],'size':[d[0],d[2],d[1]],'rotation':[0,math.degrees(rz),0]})

def box(name,c,d,mat='White',bevel=.15,segments=2,solid=False):
    if min(d)<=0:return
    bm=bmesh.new();bmesh.ops.create_cube(bm,size=1)
    for v in bm.verts:v.co=Vector((v.co.x*d[0],v.co.y*d[1],v.co.z*d[2]))
    bm.normal_update()
    if bevel>0:
        bmesh.ops.bevel(bm,geom=list(bm.edges),offset=min(bevel,min(d)*.45),segments=segments,profile=.5,affect='EDGES',clamp_overlap=True)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.verts.ensure_lookup_table();bm.verts.index_update()
    batch(name,mat).add([v.co+Vector(c) for v in bm.verts],[tuple(v.index for v in f.verts) for f in bm.faces],mat,[max(abs(n) for n in f.normal)<.999 for f in bm.faces])
    bm.free()
    if solid:collider(name,c,d)

def cylinder(name,c,r,h,mat='White',n=24,r2=None,solid=False):
    r2=r if r2 is None else r2
    vs=[(c[0]+rr*math.cos(i*math.tau/n),c[1]+rr*math.sin(i*math.tau/n),c[2]+z) for rr,z in ((r,-h/2),(r2,h/2)) for i in range(n)]
    fs=[tuple(range(n-1,-1,-1)),tuple(range(n,n*2))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    batch(name,mat).add(vs,fs,mat,[False,False]+[True]*n)
    if solid:collider(name,c,(r*1.7,r*1.7,h))

def sphere(name,c,scale,mat='White',segments=16,rings=8):
    bm=bmesh.new();bmesh.ops.create_uvsphere(bm,u_segments=segments,v_segments=rings,radius=1)
    bm.verts.ensure_lookup_table();bm.verts.index_update()
    batch(name,mat).add([(c[0]+v.co.x*scale[0],c[1]+v.co.y*scale[1],c[2]+v.co.z*scale[2]) for v in bm.verts],[tuple(v.index for v in f.verts) for f in bm.faces],mat,True);bm.free()

def tube(name,points,r,mat='White',sides=8,closed=False):
    ps=[Vector(p) for p in points];vs=[]
    for i,p in enumerate(ps):
        tangent=(ps[(i+1)%len(ps)]-ps[(i-1)%len(ps)] if closed else (ps[min(i+1,len(ps)-1)]-ps[max(i-1,0)])).normalized()
        up=Vector((0,0,1)) if abs(tangent.z)<.95 else Vector((1,0,0))
        a=tangent.cross(up).normalized();b=tangent.cross(a).normalized()
        vs.extend(p+r*(a*math.cos(j*math.tau/sides)+b*math.sin(j*math.tau/sides)) for j in range(sides))
    fs=[]
    for i in range(len(ps) if closed else len(ps)-1):
        k=(i+1)%len(ps)
        fs.extend((i*sides+j,i*sides+(j+1)%sides,k*sides+(j+1)%sides,k*sides+j) for j in range(sides))
    if not closed:fs.extend([tuple(range(sides-1,-1,-1)),tuple((len(ps)-1)*sides+j for j in range(sides))])
    batch(name,mat).add(vs,fs,mat,True)

def ring(name,c,r,tube_radius=None,mat='White',n=48,sides=6,**kw):
    radius=tube_radius if tube_radius is not None else kw.get('tube',.12)
    tube(name,[(c[0]+r*math.cos(i*math.tau/n),c[1]+r*math.sin(i*math.tau/n),c[2]) for i in range(n)],radius,mat,sides,True)

def polygon_prism(name,pts,bottom,top,mat):
    n=len(pts);vs=[(x,y,z) for z in (bottom,top) for x,y in pts]
    fs=[tuple(range(n-1,-1,-1)),tuple(range(n,n*2))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    batch(name,mat).add(vs,fs,mat)

def rounded_rect(w,d,r,n=8):
    p=[]
    for cx,cy,a in ((w/2-r,d/2-r,0),(-w/2+r,d/2-r,90),(-w/2+r,-d/2+r,180),(w/2-r,-d/2+r,270)):
        for i in range(n+1):
            t=math.radians(a+i*90/n);p.append((cx+r*math.cos(t),cy+r*math.sin(t)))
    return p

def clipped_footprint(xmin,xmax,ymin,ymax):
    pts=rounded_rect(108,88,8)
    for axis,limit,greater in ((0,xmin,True),(0,xmax,False),(1,ymin,True),(1,ymax,False)):
        output=[]
        for a,b in zip(pts,pts[1:]+pts[:1]):
            ai=a[axis]>=limit if greater else a[axis]<=limit
            bi=b[axis]>=limit if greater else b[axis]<=limit
            if ai:output.append(a)
            if ai!=bi:
                t=(limit-a[axis])/(b[axis]-a[axis]);output.append((a[0]+t*(b[0]-a[0]),a[1]+t*(b[1]-a[1])))
        pts=output
    return pts

def ribbon(name,w,d,r,bottom,height,thick,mat):
    outer=rounded_rect(w,d,r);inner=rounded_rect(w-2*thick,d-2*thick,max(.5,r-thick));n=len(outer)
    vs=[(x,y,z) for z in (bottom,bottom+height) for pts in (outer,inner) for x,y in pts]
    fs=[]
    for i in range(n):
        j=(i+1)%n
        fs.extend([(i,j,2*n+j,2*n+i),(n+j,n+i,3*n+i,3*n+j),(2*n+i,2*n+j,3*n+j,3*n+i),(j,i,n+i,n+j)])
    batch(name,mat).add(vs,fs,mat)

def wall(name,axis,fixed,start,end,bottom,top,mat='White',door=None):
    def piece(a,b,z1,z2):
        c=((a+b)/2,fixed,(z1+z2)/2) if axis=='X' else (fixed,(a+b)/2,(z1+z2)/2)
        d=(b-a,.7,z2-z1) if axis=='X' else (.7,b-a,z2-z1)
        box(name,c,d,mat,.12,2,True)
    if door:
        u,w,h=door;piece(start,u-w/2,bottom,top);piece(u+w/2,end,bottom,top);piece(u-w/2,u+w/2,bottom+h,top)
        # Rounded casing; open passage, no blocked door collider.
        for sign in (-1,1):
            c=(u+sign*(w/2+.18),fixed-.1,bottom+h/2) if axis=='X' else (fixed-.1,u+sign*(w/2+.18),bottom+h/2)
            d=(.34,1.0,h) if axis=='X' else (1.0,.34,h)
            box(name+'__jamb',c,d,'Cyan' if mat=='White' else 'White',.16,3)
    else:piece(start,end,bottom,top)

def window_wall(name,a,b,bottom,top):
    a,b=Vector(a),Vector(b);delta=b-a;length=delta.length;count=max(1,round(length/12))
    for i in range(count):
        p=a+delta*((i+.5)/count);w=length/count
        axis_x=abs(delta.x)>abs(delta.y)
        d=(w-.35,.10,top-bottom-.5) if axis_x else (.10,w-.35,top-bottom-.5)
        box(name+'__pane',(p.x,p.y,(bottom+top)/2),d,'Glass',0)
        collider(name+'__glass',(p.x,p.y,(bottom+top)/2),(w,.28,top-bottom) if axis_x else (.28,w,top-bottom))
    for i in range(count+1):
        p=a+delta*(i/count)
        box(name+'__mullion',(p.x,p.y,(bottom+top)/2),(.35,.35,top-bottom),'White',.10,2)
    for z in (bottom,top):
        p=(a+b)/2;d=(length,.4,.38) if abs(delta.x)>abs(delta.y) else (.4,length,.38)
        box(name+'__track',(p.x,p.y,z),d,'Pearl',.10,2)

def build_architecture():
    polygon_prism('Site',rounded_rect(124,108,12),-.75,-.10,'Grass')
    collider('Site',(0,0,-.45),(118,102,.7))
    polygon_prism('GroundFloor',rounded_rect(108,88,8),-.10,1.0,'White')
    collider('GroundFloor',(0,0,.45),(102,80,1.1))
    # Curved footprint supported by short invisible boxes, avoiding a single filled hull.
    collider('FrontPorch',(0,-41,.40),(86,6,1.2));collider('RearEdge',(0,42,.4),(86,7,1.2))
    collider('WestEdge',(-51,0,.4),(7,70,1.2));collider('EastEdge',(51,0,.4),(7,70,1.2))
    box('Entry__path',(0,-49,.06),(14,10,.24),'Pearl',.12,2,True)
    for y in (-49,-46.5):box('Entry__inlay',(0,y,.20),(13.6,.10,.02),'Cyan',0)
    for i in range(2):box('Entry__step',(0,-45.0+i*.65,.18+i*.23),(14,1.6,.36+i*.46),'White',.14,3,True)
    ribbon('LowerRibbon',108,88,8,1,1.1,1.2,'White')
    # Keep the central front entrance physically open through the decorative sill.
    # Ground sill above is interrupted in finalize_sill() to match this opening.
    ribbon('MiddleRibbon',110,90,9,16.5,1.62,1.5,'White')
    ribbon('MiddleAccent',110.2,90.2,9.1,16.85,.30,.20,'Cyan')
    ribbon('RoofRibbon',110,90,9,33.5,1.8,2.0,'White')
    ribbon('RoofAccent',110.2,90.2,9.1,33.85,.32,.20,'Cyan')
    # Extensive but sparse glazing: large panels with a minimum of framing.
    for level,bottom,top in (('G',2.1,16.5),('U',18,33.5)):
        window_wall('FrontLeft'+level,(-44,-43),( -9,-43),bottom,top)
        window_wall('FrontRight'+level,(9,-43),(44,-43),bottom,top)
        window_wall('West'+level,(-53,-35),(-53,35),bottom,top)
        window_wall('East'+level,(53,-35),(53,35),bottom,top)
        window_wall('Rear'+level,(-44,43),(44,43),bottom,top)
    # Opaque broad rounded corner pylons give the home its flowing silhouette.
    for x in (-47.5,47.5):
        for y in (-37.5,37.5):
            box('CornerShell',(x,y,17.1),(11,11,32.4),'White',5,6)
            collider('CornerShell',(x,y,17.1),(9.5,9.5,32.4))
    for x in (-8.4,8.4):box('Entry__jamb',(x,-43,8.8),(1.2,1.8,15.4),'Cyan',.5,4,True)
    box('Entry__header',(0,-43,14.5),(16,1.8,4.2),'Cyan',.5,4,True)
    # Open front door, two narrow sidelights.
    for x in (-6.6,6.6):box('Entry__sidelight',(x,-43,6.4),(2.1,.14,10.5),'Glass',0);collider('EntrySide',(x,-43,6.4),(2.1,.3,10.5))
    box('Entry__canopy',(0,-45.7,14.9),(23,9,1.1),'White',.5,4)
    # Upper floors form two wings around the stair and double-height lounge void.
    box('UpperFloorEast',(33,0,17.5),(40,86,1),'White',.18,2,True)
    box('UpperFloorRear',(-19.5,30,17.5),(65,26,1),'White',.18,2,True)
    box('UpperBridge',(0,-26,17.5),(26,34,1),'White',.18,2,True)
    # Upper front central window above entrance.
    window_wall('EntryUpper',(-8.0,-43),(8.0,-43),18,33.5)
    # Internal doors remain generous (7 to 9 studs) and tall (10.5 studs).
    wall('GuestWall','X',17,-46,-14,1,16.5,'Aqua',(-29,8,10.5))
    wall('StudyWall','X',17,15,46,1,16.5,'Lime',(29,8,10.5))
    wall('BathFront','X',22,-12,12,1,16.5,'White',(0,7,10.5))
    wall('GuestSide','Y',-14,17,43,1,16.5,'White')
    wall('StudySide','Y',15,17,43,1,16.5,'White')
    wall('BathSideL','Y',-12,22,43,1,16.5,'White')
    wall('BathSideR','Y',12,22,43,1,16.5,'White')
    wall('MasterFront','X',21.5,-46,-14,18,33.5,'Aqua',(-29,8,10.5))
    wall('UpperGuestFront','X',21.5,15,46,18,33.5,'Lime',(29,8,10.5))
    wall('UpperMasterSide','Y',-14,21.5,43,18,33.5,'White')
    wall('UpperGuestSide','Y',15,21.5,43,18,33.5,'White')
    # Lime feature wall between reading room and upper hall, broad opening.
    wall('ReadingWall','X',1,16,46,18,33.5,'Lime',(29,10,11))
    # Continuous roof with a framed rectangular skylight over the atrium.
    for name,extents in [('RoofBack',(-54,54,16,44)),('RoofFront',(-54,54,-44,-17.5)),('RoofLeft',(-54,-41,-17.5,16)),('RoofRight',(-3.5,54,-17.5,16))]:
        polygon_prism(name,clipped_footprint(*extents),34.3,35.2,'White')
        x1,x2,y1,y2=extents;collider(name,((x1+x2)/2,(y1+y2)/2,34.75),(x2-x1,y2-y1,.9))
    box('Skylight',(-22,-.75,35.1),(38,33.4,.12),'Glass',0)
    for x in (-40.5,-3.5):box('SkylightFrame',(x,-.75,35.2),(.5,34,.6),'Cyan',.2,3)
    for y in (-17.5,16):box('SkylightFrame',(-22,y,35.2),(37,.5,.6),'Cyan',.2,3)
    # A walkable front upper balcony beyond the facade, reached through a side opening.
    box('Terrace',(31,-49,17.5),(36,12,1),'White',.45,3,True)
    box('Terrace__deck',(31,-49,18.05),(34,10,.09),'Aqua',.04,1)
    # Terrace access doorway replaces one glazing bay in finalize_windows().
    for i in range(12):box('Terrace__deckline',(16+i*2.7,-49,18.105),(.045,9,.012),'Pearl',0)
    rail('TerraceRail',[(13,-54,18),(49,-54,18),(49,-44,18)])
    rail('AtriumRearRail',[(-49,17.0,18),(-14,17.0,18)])
    rail('AtriumBridgeRail',[(-13,-38,18),(-13,-6,18)])
    # Roof is ornamental; the first-floor terrace is the accessible outdoor space.
    for i in range(6):box('RoofFin',(27+i*2.7,18,36),( .42,22,1.8),'Pearl',.2,3)

def rail(name,points):
    for a,b in zip(points,points[1:]):
        a,b=Vector(a),Vector(b);delta=b-a;num=max(1,int(delta.length/9))
        tube(name+'__top',[a+Vector((0,0,4)),b+Vector((0,0,4))],.16,'Cyan',8)
        for i in range(num+1):
            p=a+delta*(i/num);box(name+'__post',(p.x,p.y,p.z+2),(.22,.22,4),'Chrome',.04,1)
        center=(a+b)/2;size=(delta.length,.12,3.6) if abs(delta.x)>abs(delta.y) else (.12,delta.length,3.6)
        box(name+'__glass',(center.x,center.y,center.z+2),size,'Glass',0)
        collider(name+'__guard',(center.x,center.y,center.z+2),(delta.length,.4,4) if abs(delta.x)>abs(delta.y) else (.4,delta.length,4))

def build_stair():
    # Wide U stair, 34 sub-0.51 stud risers. Curved middle flight is actual treads.
    inner,outer,cx,cy=2,9,1,5
    n1,n2,n3=13,8,13;rise=17/(n1+n2+n3);index=0;innerpts=[];outerpts=[]
    for i in range(n1):
        index+=1;top=1+index*rise;y=-16+(i+.5)*21/n1
        box('StairFlightA',(6.5,y,(top+1)/2),(7,21/n1+.015,top-1),'White',.06,1,True)
        box('StairNosingA',(6.5,y-21/n1/2+.10,top+.012),(6.7,.10,.025),'Cyan',0)
        innerpts.append((3,y,top+3.7));outerpts.append((10,y,top+3.7))
    arcinner=[];arcouter=[]
    for i in range(n2):
        index+=1;top=1+index*rise;a=i*math.pi/n2;b=(i+1)*math.pi/n2
        pts=[(cx+inner*math.cos(a),cy+inner*math.sin(a)),(cx+outer*math.cos(a),cy+outer*math.sin(a)),(cx+outer*math.cos(b),cy+outer*math.sin(b)),(cx+inner*math.cos(b),cy+inner*math.sin(b))]
        polygon_prism('StairTurn',pts,1,top,'White')
        # Two oriented rectangular proxies closely cover each annular tread; no convex blocking hull.
        mid=(a+b)/2
        for rr in (3.75,7.25):
            collider('StairTurn', (cx+rr*math.cos(mid),cy+rr*math.sin(mid),(top+1)/2),(4.0,(rr+1.75)*(b-a)*1.05,top-1),mid)
        arcinner.append((cx+inner*math.cos((a+b)/2),cy+inner*math.sin((a+b)/2),top+3.7))
        arcouter.append((cx+outer*math.cos((a+b)/2),cy+outer*math.sin((a+b)/2),top+3.7))
    endinner=[];endouter=[]
    for i in range(n3):
        index+=1;top=1+index*rise;y=5-(i+.5)*14/n3
        box('StairFlightB',(-4.5,y,(top+1)/2),(7,14/n3+.02,top-1),'White',.06,1,True)
        box('StairNosingB',(-4.5,y+14/n3/2-.1,top+.012),(6.7,.1,.025),'Cyan',0)
        endinner.append((-1,y,top+3.7));endouter.append((-8,y,top+3.7))
    # Inner railing follows the continuous flight. Outer railing ends at the landing.
    for label,pts in [('Inner',innerpts+arcinner+endinner),('Outer',outerpts+arcouter+endouter)]:
        tube('StairRails__'+label,pts,.17,'Cyan',8)
        for j,p in enumerate(pts):
            if j%3==0:
                box('StairRails__post',(p[0],p[1],p[2]-1.8),(.19,.19,3.6),'Chrome',.06,2)
    # The slab stops in front of the stair opening, preserving full head clearance.
    rail('StairVoidEast',[(13,-5.5,18),(13,15.6,18)])
    rail('StairVoidRear',[(-12,17.0,18),(12.5,17.0,18)])

def area_light(name,c,power,color,size,target):
    data=bpy.data.lights.new(name,'AREA');data.energy=power;data.color=color;data.shape='DISK';data.size=size
    obj=bpy.data.objects.new(name,data);pres.objects.link(obj);obj.location=c;obj.rotation_euler=(Vector(target)-obj.location).to_track_quat('-Z','Y').to_euler();return obj

def make_materials():
    mats={}
    for channel in ('Color','Roughness','Metallic'):
        image=bpy.data.images.new('Aero_'+channel,width=256,height=256,alpha=False)
        if channel!='Color':image.colorspace_settings.name='Non-Color'
        pixels=[]
        for y in range(256):
            for x in range(256):
                index=(y//64)*4+x//64;key=KEYS[index]
                if channel=='Color':v=tuple(srgb(a) for a in rgb(key))
                else:v=(PALETTE[key][1 if channel=='Roughness' else 2],)*3
                pixels.extend((*v,1))
        image.pixels.foreach_set(pixels)
        image.filepath_raw=str(OUT/'textures'/('Aero_'+channel+'.png'));enum(image,'file_format','PNG');image.save();image.pack()
    for kind in ('Palette','Glow','Glass'):
        mat=bpy.data.materials.new('Aero_'+kind);mat.use_nodes=True
        bs=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
        if kind=='Glass':
            bs.inputs['Base Color'].default_value=(*[srgb(v) for v in rgb('Glass')],1)
            bs.inputs['Roughness'].default_value=.12;bs.inputs['Alpha'].default_value=.17
            if hasattr(mat,'surface_render_method'):enum(mat,'surface_render_method','DITHERED')
            mat.diffuse_color=(*rgb('Glass'),.17)
        else:
            for channel,socket in (('Color','Base Color'),('Roughness','Roughness'),('Metallic','Metallic')):
                node=mat.node_tree.nodes.new('ShaderNodeTexImage');node.image=bpy.data.images['Aero_'+channel]
                if channel!='Color':node.image.colorspace_settings.name='Non-Color'
                node.interpolation='Closest';mat.node_tree.links.new(node.outputs['Color'],bs.inputs[socket])
            if kind=='Glow':
                bs.inputs['Emission Color'].default_value=(.42,.85,.8,1);bs.inputs['Emission Strength'].default_value=.7
        mats[kind]=mat
    return mats

def realize():
    mats=make_materials();report=[]
    for builder in BUILDERS.values():
        mesh=bpy.data.meshes.new(builder.name);mesh.from_pydata(builder.v,[],builder.f);mesh.update()
        # Resolve winding for all disconnected closed primitives.
        bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(mesh);bm.free()
        uv=mesh.uv_layers.new(name='UVMap')
        for i,poly in enumerate(mesh.polygons):
            tile=builder.tiles[i];tx=tile%4;ty=tile//4
            for j,li in enumerate(poly.loop_indices):
                angle=j*math.tau/len(poly.loop_indices)
                uv.data[li].uv=((tx+.5+.25*math.cos(angle))/4,(ty+.5+.25*math.sin(angle))/4)
            poly.use_smooth=builder.smooth[i]
        mesh.materials.append(mats[builder.kind])
        obj=bpy.data.objects.new(builder.name,mesh);geo.objects.link(obj)
        mesh.calc_loop_triangles()
        report.append({'name':obj.name,'triangles':len(mesh.loop_triangles),'vertices':len(mesh.vertices),'material':mats[builder.kind].name})
    return report

def camera(name,loc,target,lens=28):
    data=bpy.data.cameras.new(name);obj=bpy.data.objects.new(name,data);pres.objects.link(obj);obj.location=loc;data.lens=lens;data.clip_end=1500;obj.rotation_euler=(Vector(target)-obj.location).to_track_quat('-Z','Y').to_euler();return obj

def presentation():
    try:scene.render.engine='CYCLES'
    except TypeError:scene.render.engine='BLENDER_EEVEE'
    if scene.render.engine=='CYCLES':scene.cycles.samples=40;scene.cycles.use_denoising=True
    world=bpy.data.worlds.new('Aero Daylight');world.use_nodes=True
    bg=next(n for n in world.node_tree.nodes if n.type=='BACKGROUND');bg.inputs['Color'].default_value=(.63,.81,.95,1);bg.inputs['Strength'].default_value=.6;scene.world=world
    sun=bpy.data.lights.new('Sun','SUN');sun.energy=2.0;sun.angle=math.radians(12)
    obj=bpy.data.objects.new('Sun',sun);pres.objects.link(obj);obj.rotation_euler=(math.radians(25),math.radians(-22),math.radians(-35))
    area_light('Softbox_Front',(0,-72,58),48000,(.8,.93,1),65,(0,0,12))
    area_light('Atrium_Daylight',(-25,-1,32.5),10000,(.8,.98,1),24,(-25,-1,0))
    area_light('Kitchen_Fill',(30,-15,15.3),3600,(.96,1,.83),16,(30,-15,1))
    area_light('Upper_Fill',(28,-17,32.5),3200,(.92,1,.85),18,(28,-17,18))
    area_light('Hall_Fill',(0,20,31.5),5000,(.9,1,1),18,(0,15,1))
    camera('Aero_Camera_Exterior',(123,-154,91),(0,-1,13),43)
    camera('Aero_Camera_Lounge',(-39,-34,7.0),(-13,6,10),20)
    camera('Aero_Camera_Kitchen',(46,-35,7),(17,-5,7),22)
    camera('Aero_Camera_Upper',(36,-29,24),(20,-5,23),22)
    camera('Aero_Camera_Plan',(0,-.01,160),(0,0,0),38)
    scene.camera=bpy.data.objects['Aero_Camera_Exterior']
    scene.render.resolution_x=1600;scene.render.resolution_y=1100;scene.render.resolution_percentage=100
    enum(scene.render.image_settings,'file_format','PNG')
    scene.view_settings.exposure=0
    # Preview ground is excluded from all mesh exports.
    mesh=bpy.data.meshes.new('Backdrop');mesh.from_pydata([(-2000,-2000,-.8),(2000,-2000,-.8),(2000,2000,-.8),(-2000,2000,-.8)],[],[(0,1,2,3)])
    obj=bpy.data.objects.new('Backdrop',mesh);pres.objects.link(obj)
    mat=bpy.data.materials.new('Backdrop');mat.use_nodes=True
    bs=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED');bs.inputs['Base Color'].default_value=(.32,.51,.19,1);bs.inputs['Roughness'].default_value=.85;mesh.materials.append(mat)

def finalize_openings():
    # Remove only our decorative sill geometry and rebuild segments around the entry.
    BUILDERS.pop(('LowerRibbon','Palette'))
    for a,b in ((-45,-8),(8,45)):
        box('LowerRibbon',((a+b)/2,-43,1.55),(b-a,1.1,1.1),'White',.4,3)
    for x in (-53,53):box('LowerRibbon',(x,0,1.55),(1.1,70,1.1),'White',.4,3)
    box('LowerRibbon',(0,43,1.55),(88,1.1,1.1),'White',.4,3)
    # Rebuild upstairs front-right glazing with a 9-stud clear terrace access.
    for k in [('FrontRightU','Glass'),('FrontRightU','Palette')]:BUILDERS.pop(k,None)
    COLLIDERS[:]=[c for c in COLLIDERS if not c['name'].startswith('FrontRightU')]
    window_wall('FrontRightU',(9,-43),(24,-43),18,33.5)
    window_wall('FrontRightU',(33,-43),(44,-43),18,33.5)
    box('TerraceDoorHeader',(28.5,-43,31.0),(9,.7,5),'White',.2,3,True)

def main():
    OUT.mkdir(parents=True,exist_ok=True);(OUT/'textures').mkdir(exist_ok=True);(OUT/'previews').mkdir(exist_ok=True)
    build_architecture();build_stair();finalize_openings()
    import aero_house_furniture
    aero_house_furniture.build_furniture(sys.modules[__name__])
    for name,c in [('Aero_Anchor_Entry',(0,-42,2)),('Aero_Anchor_RearRight',(40,36,2)),('Aero_Anchor_RearLeft',(-40,36,2))]:box(name,c,(.6,.6,.6),'Cyan',.1,2)
    report=realize();presentation()
    lights=[{'name':n,'position':[c[0],c[2],-c[1]],'color':co,'range':r,'brightness':b} for n,c,co,r,b in [
      ('Lounge',(-28,-9,13),[.65,.95,1],32,1.2),('Kitchen',(30,-13,13),[.92,1,.70],27,1),('Hall',(0,18,14),[.8,1,1],24,1),('Reading',(28,-17,29),[.90,1,.75],26,1)]]
    points=[v.co for o in geo.objects for v in o.data.vertices]
    lo=[min(p[i] for p in points) for i in range(3)];hi=[max(p[i] for p in points) for i in range(3)]
    bounds={'size':[hi[0]-lo[0],hi[2]-lo[2],hi[1]-lo[1]],'min':[lo[0],lo[2],-hi[1]],'max':[hi[0],hi[2],-lo[1]]}
    manifest={'version':1,'modelName':'Aero House','anchorSizeRoblox':[.6,.6,.6],'authoring':'Blender Z up, 1 unit = 1 Roblox stud','exportMapping':'(x,y,z) -> (x,z,-y), setup derives import yaw from 3 geometry markers','colliders':COLLIDERS,'lights':lights,'meshReport':report,'triangleCount':sum(x['triangles'] for x in report),'meshCount':len(report),'expectedBoundsRoblox':bounds,'playModeVerified':False}
    (OUT/'manifest.json').write_text(json.dumps(manifest,indent=2))
    for obj in bpy.context.selected_objects:obj.select_set(False)
    for obj in geo.objects:obj.select_set(True)
    bpy.context.view_layer.objects.active=next(iter(geo.objects))
    bpy.ops.export_scene.gltf(filepath=str(OUT/'AeroHouse.glb'),use_selection=True,use_active_scene=True,export_yup=True,export_apply=True,export_animations=False,export_cameras=False,export_lights=False,export_extras=True)
    bpy.ops.export_scene.fbx(filepath=str(OUT/'AeroHouse.fbx'),use_selection=True,object_types={'MESH'},global_scale=1,apply_unit_scale=True,apply_scale_options='FBX_SCALE_UNITS',axis_forward='-Z',axis_up='Y',use_mesh_modifiers=True,mesh_smooth_type='OFF',use_triangles=True,add_leaf_bones=False,bake_anim=False,path_mode='COPY',embed_textures=True)
    # Save only the new house scene in its native project.
    for s in list(bpy.data.scenes):
        if s!=scene:bpy.data.scenes.remove(s)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'AeroHouse.blend'),check_existing=False)
    print('AERO_BUILD_RESULT '+json.dumps({'meshes':len(report),'triangles':manifest['triangleCount'],'maxMeshTriangles':max(x['triangles'] for x in report),'colliders':len(COLLIDERS)}),flush=True)

if __name__=='__main__':main()
