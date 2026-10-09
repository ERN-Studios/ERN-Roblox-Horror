"""C2: offline authored small rooms; no GUI, Studio, git or external writes.
D:/Blender/blender.exe -b --factory-startup --python-exit-code 1 -P G:/Roblox/MongoTV/tools/level2_blender/rooms_small.py -- --samples 48
All modelling inputs are Roblox studs/axes. Part previews never export.
"""
import argparse
import base64
import hashlib
import json
import math
import struct
import sys
from pathlib import Path
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).parent))
import bpy
import bmesh
from mathutils import Matrix, Vector
import kit

EXPORT = Path('G:/Blender/Level2_Pool/jobs/C/export')
REVIEW = Path('G:/Blender/Level2_Pool/review/C')
ROOMS = {'ChangingRoom_A': (64,48,22), 'ChangingRoom_B': (64,80,22),
         'PlantRoom_A': (64,64,24), 'PlantRoom_B': (80,64,24)}
THICK = 1.75
FOOTPRINTS, DETAIL_TRIS = {}, {}


def tris(m):
    return sum(len(f.verts)-2 for f in m.bm.faces)


def edge_box(m, center, size, mat, bevel=.045, yaw=0, uv=None):
    """One bevel segment: small physical tile/metal edges without subdivision."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1)
    bmesh.ops.scale(bm, vec=Vector((size[0],size[2],size[1])), verts=list(bm.verts))
    if bevel:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=min(bevel,min(size)*.25),
                       segments=1, affect='EDGES')
    kit.Mesh._xf(bm, center, Matrix.Rotation(-math.radians(yaw),4,'Z') if yaw else None)
    m.absorb(bm,mat,uv)


def obstacle(m, label, center, size):
    FOOTPRINTS[m.name].append((label,center,size))


def block(m, label, center, size):
    m.collider('L2K '+label,center,size)
    obstacle(m,label,center,size)


def wall_record(m, wall, along, y, length, height, depth, mat, name, inset=0, attrs=None):
    w,d,_ = ROOMS[m.name]
    if wall in 'NS':
        sign = -1 if wall=='N' else 1
        center = (along,y,sign*(d/2-THICK/2-inset)); size = (length,height,depth)
    else:
        sign = 1 if wall=='E' else -1
        center = (sign*(w/2-THICK/2-inset),y,along); size = (depth,height,length)
    m.part(name,center,size,mat,attrs=attrs)


def shell(m,w,d,h,changing):
    mat = 'Tile' if changing else 'ServiceGrey'
    m.part('Level 2 Room Floor',(0,-.5,0),(w,1,d),'Terrazzo' if changing else 'ServiceGrey',ground=True)
    m.part('Level 2 Overhead Tile Slab' if changing else 'Level 2 Overhead Service Slab',
           (0,h+.375,0),(w,.75,d),'Tile' if changing else 'Service',collide=False)
    m.collider('Level 2 Room Roof Collider',(0,h+.375,0),(w,.75,d),attrs={'Level2_NoEntityGround':True})
    for wall in ('N','E','S','W'):
        length = w if wall in 'NS' else d
        half = length/2 if wall in 'NS' else length/2-THICK
        offsets = [0,-16,16] if length>=64 else [0]
        runs=[]; start=-half
        for offset,index in sorted((v,i) for i,v in enumerate(offsets)):
            runs.extend(((start,offset-6,None),(offset-6,offset+6,f'{wall}{index}')))
            start=offset+6
            pos = ((offset,0,-d/2) if wall=='N' else (offset,0,d/2) if wall=='S'
                   else (w/2,0,offset) if wall=='E' else (-w/2,0,offset))
            m.marker('Socket',pos,{'N':0,'E':-90,'S':180,'W':90}[wall],Wall=wall,Index=index,Width=12,Height=16)
        runs.append((start,half,None))
        for i,(a,b,plug) in enumerate(runs):
            assert b>a
            attrs={'SocketPlug':plug} if plug else {}
            wall_record(m,wall,(a+b)/2,8,b-a,16,THICK,mat,
                        f"Level 2 Room {wall} {'Plug '+plug if plug else 'Wall Run '+str(i)}",attrs=attrs)
        wall_record(m,wall,0,(16+h)/2,half*2,h-16,THICK,mat,f'Level 2 Room {wall} Lintel')
    if changing:
        # One continuous closed band ring, without overlapping corner faces.
        bottom=17; bh=1/kit.S
        verts=[]
        for y in (bottom,bottom+bh):
            for inset in (.01,.16):
                xx=w/2-THICK-inset; zz=d/2-THICK-inset
                verts.extend((x,y,z) for x,z in ((-xx,-zz),(xx,-zz),(xx,zz),(-xx,zz)))
        faces=[]
        for i in range(4):
            j=(i+1)%4
            faces.extend(((i,j,8+j,8+i),(4+i,12+i,12+j,4+j),
                          (i,4+i,4+j,j),(8+i,8+j,12+j,12+i)))
        m.raw(verts,faces,'Bands',uv=lambda co,no:
              (-co.y if abs(no.x)>abs(no.y) else co.x,(co.z/kit.S-bottom)/bh))


def ring(m,center,outer=.65,inner=.47,depth=.13,mat='Steel',n=8):
    x,y,z=center
    verts=[(x+r*math.cos(i*math.tau/n),y+r*math.sin(i*math.tau/n),zz)
           for zz,r in ((z-depth/2,outer),(z-depth/2,inner),(z+depth/2,outer),(z+depth/2,inner)) for i in range(n)]
    faces=[]
    for i in range(n):
        j=(i+1)%n
        faces.extend(((i,j,n+j,n+i),(2*n+i,3*n+i,3*n+j,2*n+j),
                      (i,2*n+i,2*n+j,j),(n+i,n+j,3*n+j,3*n+i)))
    m.raw(verts,faces,mat)


def profile(m,x,z,rings,mat,n=12):
    verts=[(x+r*math.cos(i*math.tau/n),y,z+r*math.sin(i*math.tau/n)) for y,r in rings for i in range(n)]
    faces=[(j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i) for j in range(len(rings)-1) for i in range(n)]
    faces.extend((tuple(range(n-1,-1,-1)),tuple((len(rings)-1)*n+i for i in range(n))))
    m.raw(verts,faces,mat,smooth=True)


def cubicle_row(m,x,zs):
    """Tiled sides/back are colliding Parts; rolled coping/doors are meshes.
    E/W wall rows face inward. Cubicle width 4.4, depth 5.5, height 8.6.
    """
    sign=1 if x>0 else -1
    back=x+sign*2.48; front=x-sign*2.48
    m.part('L2K Cubicle Row Tile Back',(back,4.3,(min(zs)+max(zs))/2),(.26,8.6,max(zs)-min(zs)+4.4),'Tile')
    for j,z in enumerate(zs):
        before=tris(m)
        for zz in (z-2.2,z+2.2):
            # Shared divider emitted once; adjacent cells touch with no void gap.
            if j and abs(zz-(zs[j-1]+2.2))<.01: continue
            m.part('L2K Cubicle Tile Divider',(x,4.3,zz),(5.5,8.6,.22),'Tile')
            m.cylinder((x,8.62,zz),.16,5.54,'Tile',segments=8,axis='X')
        m.box((front,4.15,z),(.17,7.7,3.98),'SteelTeal',bevel=0)
        m.collider('L2K Cubicle Door',(front,4.15,z),(.17,7.7,3.98))
        for y in (1.7,6.5):
            m.box((front-sign*.13,y,z-1.94),(.12,.5,.2),'Steel',bevel=0)
        m.cylinder((front-sign*.19,4.25,z+1.38),.12,.35,'Steel',segments=6,axis='X')
        m.box((front-sign*.38,4.25,z+1.2),(.13,.13,.65),'Steel',bevel=0)
        # Glazed lower tile strip gives each stall the period pale-teal dado.
        m.box((front-sign*.01,.5,z),(.19,.14,4.3),'TileTeal',bevel=0)
        obstacle(m,'Cubicle',(x,4.3,z),(5.5,8.7,4.62))
        count=tris(m)-before; DETAIL_TRIS[m.name].append(('Cubicle',count)); assert count<=800


def locker_island(m,x,z,doors=4,width=8):
    before=tris(m)
    edge_box(m,(x,4.05,z),(width,7.9,3.4),'SteelTeal',.075)
    for side in (-1,1):
        for i in range(doors):
            xx=x-width/2+(i+.5)*width/doors
            # Separate door with narrow dark cabinet reveals, hinge, latch, vents.
            m.box((xx,4.1,z+side*1.73),(width/doors-.14,7.35,.10),'SteelTeal',bevel=0)
            m.box((xx+.6,4.1,z+side*1.82),(.10,.6,.11),'Steel',bevel=0)
            for y in (6.85,7.05):
                m.box((xx,y,z+side*1.80),(1.05,.055,.03),'Steel',bevel=0)
            m.box((xx,6.1,z+side*1.80),(.36,.18,.025),'Tile',bevel=0)
    block(m,'Back To Back Locker Island',(x,4.05,z),(width,8,3.5))
    DETAIL_TRIS[m.name].append(('LockerIsland',tris(m)-before))


def bench(m,x,z):
    for zz in (-.56,0,.56):
        edge_box(m,(x,1.65,z+zz),(8,.28,.48),'TileTeal',.055)
    for xx in (-2.8,2.8):
        m.box((x+xx,.77,z),(.32,1.54,1.55),'Steel',bevel=0)
    block(m,'Bench',(x,.94,z),(8,1.88,1.64))


def partition(m,x,z,length):
    m.part('L2K Half Height Tiled Partition',(x,2.8,z),(.45,5.6,length),'TileTeal')
    m.cylinder((x,5.63,z),.28,length+.08,'Tile',segments=8,axis='Z')
    # Full-round bullnose is physically closed with a solid partition beneath.
    obstacle(m,'Half Height Partition',(x,2.8,z),(.56,5.9,length+.08))


def changing_detail(m,w,d,large):
    for sign in (-1,1):
        x=sign*(w/2-THICK-.35); z=-sign*(d/2-8)
        edge_box(m,(x,6.2,z),(.13,4.6,4.4),'Steel',.035)  # steel wall mirror
        m.box((x-sign*.16,3.15,z),(.15,.35,4.6),'Steel',bevel=0)
        for zz in (-1.6,0,1.6):
            m.box((x-sign*.34,3.45,z+zz),(.5,.1,.12),'Steel',bevel=0)
            m.box((x-sign*.56,3.6,z+zz),(.1,.4,.12),'Steel',bevel=0)
        edge_box(m,(x-sign*.25,4.4,z+sign*4.1),(.65,1.5,1.3),'Tile',.09)
        m.box((x-sign*.6,3.9,z+sign*4.1),(.07,.14,.85),'Steel',bevel=0)
        # These fixtures stand only in the corner service bay, away from sockets.
        obstacle(m,'Mirror Hook Rail Dryer',(x-sign*.3,4,z+sign*1.7),(1.05,7,8.5))
    # A dropped kickboard is visibly coloured and grounded outside every lane.
    edge_box(m,(7.8,.17,8.3),(1.5,.30,2.8),'TileTeal',.14,yaw=18)
    obstacle(m,'Dropped Kickboard',(7.8,.17,8.3),(2.31,.30,3.13))
    if large:
        x,z=-25,8
        for xx in (-1.7,1.7): m.box((x+xx,2.8,z),(.16,5.6,.2),'Steel',bevel=0)
        for y in (.5,2.5,4.5): m.box((x,y,z),(3.6,.15,1.4),'Steel',bevel=0)
        for xx in (-1,0,1): edge_box(m,(x+xx,3.1,z),( .75,4.6,.32),'TileTeal',.08)
        block(m,'Kickboard Rack',(x,2.8,z),(3.8,5.6,1.7))
    else:
        profile(m,-25, -8,[(.05,.9),(.25,.95),(2,.95),(2.12,1.02)],'Steel',10)
        m.cylinder((-25,2.13,-8),.78,.08,'ServiceBlack',segments=10)
        m.cylinder((-25,4,-8),.06,5.8,'Steel',segments=6)
        block(m,'Mop Bucket',(-25,2.5,-8),(2.1,5,2.1))
    for x,z in ((-8,-5),(8,5)):
        grate(m,x,z,3,1.2,8)


def grate(m,x,z,length,width,bars):
    m.box((x,.025,z),(length,.04,width),'ServiceBlack',bevel=0)
    for zz in (-width/2,width/2): m.box((x,.063,z+zz),(length,.07,.09),'Steel',bevel=0)
    for i in range(bars):
        m.box((x-length/2+(i+.5)*length/bars,.067,z),(.10,.065,width),'Steel',bevel=0)


def plinth(m,x,z,sx,sz):
    m.part('L2K Raised Concrete Plinth',(x,.45,z),(sx,.9,sz),'Service',ground=True)
    obstacle(m,'Raised Plinth',(x,.45,z),(sx,.9,sz))


def filter_unit(m,x,z):
    plinth(m,x,z,7.2,7.2)
    profile(m,x,z,[(.92,1.5),(1.35,2.5),(2.3,3.1),(6.9,3.1),(8.3,2.4),(8.8,1.25)],'Service',12)
    for y in (2.4,6.8): m.cylinder((x,y,z),3.18,.17,'Steel',segments=12)
    m.cylinder((x,9,z),.45,.5,'Steel',segments=8)
    m.cylinder((x,3,z-3.5),.35,1.4,'Steel',segments=8,axis='Z')
    m.cylinder((x,3,z-4.05),.62,.15,'Steel',segments=8,axis='Z')
    service_riser(m,x,z,9.2)
    # Same plan footprint as plinth; append machinery to its occupied envelope.
    m.collider('L2K Sand Filter',(x,5.2,z),(6.2,8.6,6.2))
    # The outlet is separately tested because it protrudes beyond the plinth.
    obstacle(m,'Filter Outlet',(x,3,z-3.6),(1.25,1.25,1.2))


def pump(m,x,z):
    plinth(m,x,z,8,5)
    m.cylinder((x+1.2,2.3,z),1.18,3.8,'Steel',segments=10,axis='X')
    m.cylinder((x-1.9,2.1,z),1.3,1.6,'Steel',segments=10,axis='X')
    m.cylinder((x-2.1,3.4,z),.38,1.6,'Steel',segments=8)
    edge_box(m,(x+1.3,3.45,z), (1.5,.55,1.1),'Steel',.06)
    for dx in (.1,.7,1.3,1.9,2.5):
        m.cylinder((x+dx,2.3,z),1.24,.09,'Steel',segments=10,axis='X')
    service_riser(m,x-2.1,z,4.2)
    m.collider('L2K Pump Machinery',(x,2.4,z),(7.3,3.8,3))


def service_riser(m,x,z,bottom):
    m.cylinder((x,(bottom+17.4)/2,z),.27,17.4-bottom,'Steel',segments=6)
    m.cylinder((x/2,17.4,z),.27,abs(x)+.2,'Steel',segments=6,axis='X')
    m.cylinder((x,12.7,z),.49,.20,'Steel',segments=6)


def manifold(m,x,z):
    before=tris(m)
    for y in (1.2,9): m.cylinder((x,y,z),.36,10,'Steel',segments=8,axis='X')
    for dx in (-3,0,3):
        m.cylinder((x+dx,5.1,z),.25,7.8,'Steel',segments=8)
        m.cylinder((x+dx,5.5,z-.6),.15,1.2,'Steel',segments=8,axis='Z')
        m.cylinder((x+dx,5.5,z),.48,.4,'Steel',segments=8)
        ring(m,(x+dx,5.5,z-1.22),.83,.62)
        m.box((x+dx,5.5,z-1.22),(1.4,.1,.12),'Steel',bevel=0)
        m.box((x+dx,5.5,z-1.22),(.1,1.4,.12),'Steel',bevel=0)
    for dx in (-4.4,4.4): m.box((x+dx,4.8,z+.55),(.2,9.6,.2),'Steel',bevel=0)
    m.cylinder((x+4.2,10,z),.55,.3,'Steel',segments=10,axis='Z')
    m.cylinder((x+4.2,10,z-.17),.45,.04,'Tile',segments=10,axis='Z')
    m.box((x+4.2,10.13,z-.21),(.06,.43,.03),'Steel',bevel=0)
    service_riser(m,x,z,9.2)
    block(m,'Manifold',(x,5.3,z-.35),(10.8,10.6,2.2))
    count=tris(m)-before; DETAIL_TRIS[m.name].append(('Manifold',count)); assert count<=800


def plant_services(m,w,d,h):
    m.cylinder((0,17.4,0),.4,d-6,'Steel',segments=8,axis='Z')
    # Continuous upper services clear the 16-high aperture at all sockets.
    for y in (18.1,20.5):
        for sign in (-1,1):
            z=sign*(d/2-THICK-.6)
            m.cylinder((0,y,z),.25,w-2*THICK-1.2,'Steel',segments=8,axis='X')
            m.cylinder((sign*(w/2-THICK-.6),y,0),.25,d-2*THICK-1.2,'Steel',segments=8,axis='Z')
            for x in (-w/4,w/4):
                m.cylinder((x,y,z),.48,.18,'Steel',segments=8,axis='X')
    # Low pipe run and valves in each corner bay, never across a socket mouth.
    for sign in (-1,1):
        x=sign*(w/2-THICK-1.4); z=sign*(d/2-6)
        m.cylinder((x,7,z),.28,4,'Steel',segments=8,axis='Z')
        m.cylinder((x,7,z),.49,.20,'Steel',segments=8,axis='Z')
        # Handwheels face the room; two low service pipes add the third height.
        ring(m,(x-sign*.55,7,z-.5),.72,.53)
        m.box((x-sign*.55,7,z-.5),(1.2,.10,.12),'Steel',bevel=0)
        obstacle(m,'Low Wall Pipe Valve',(x-sign*.2,7,z),(1.8,1.6,4))
    for z in (-d/4,0,d/4):
        edge_box(m,(0,h-1.0,z),(w-2*THICK,1.5,1.2),'Service',.04)
    # Twin longitudinal open cable trays with folded lips and cross ties.
    for x in (-8,8):
        for dx in (-.7,.7): m.box((x+dx,h-2.4,0),(.12,.55,d-5),'Steel',bevel=0)
        for z in range(-int(d/2)+4,int(d/2)-3,8):
            m.box((x,h-2.58,z),(1.5,.12,.20),'Steel',bevel=0)
    for x,z in ((-8,25),(8,25),(25,-8)):
        profile(m,x,z,[(.04,1.15),(.22,1.2),(3.3,1.2),(3.5,1.1)],'HazardYellow',8)
        m.box((x,1.8,z-1.22),(1.1,.65,.06),'Tile',bevel=0)
        for y in (.5,2.9): m.cylinder((x,y,z),1.24,.13,'Steel',segments=8)
        block(m,'Chemical Drum',(x,1.8,z),(2.5,3.6,2.5))
    # Hose-reel slot includes bracket and a steel wound reel, no grey placeholder.
    x,z=-w/2+THICK+1.3,-d/2+5.8
    m.box((x,6,z),(.4,4.6,4.6),'Steel',bevel=0)
    m.cylinder((x+.6,6,z),1.7,1.1,'Steel',segments=12,axis='X')
    for dx in (.1,1.2): m.cylinder((x+dx,6,z),1.9,.15,'Steel',segments=12,axis='X')
    obstacle(m,'Hose Reel Slot',(x+.6,6,z),(1.9,4.6,4.6))
    # Large period switchboards on solid wall runs between the reserved mouths.
    for sign in (-1,1):
        x=sign*(w/2-THICK-.35); z=-sign*26.8
        edge_box(m,(x,8.0,z),(.55,7.5,3.2),'Steel',.06)
        for zz in (-.7,.7):
            m.box((x-sign*.32,9.3,z+zz),(.08,1.3,1.0),'Tile',bevel=0)
            m.box((x-sign*.39,9.4,z+zz),(.08,.55,.10),'Steel',bevel=0)
        for zz in (-.85,0,.85):
            m.cylinder((x-sign*.38,6.7,z+zz),.18,.14,'HazardYellow',segments=6,axis='X')
        obstacle(m,'Wall Switchboard',(x-sign*.15,8,z),(.95,7.5,3.3))
    # Steel trench is flush to the ground: navigation sees the flat floor Part.
    for a,b in ((-w/2+3.5,-12.5),(-3.5,w/2-3.5)):
        grate(m,(a+b)/2,8,b-a,1.8,max(2,round((b-a)/1.05)))
    # Hazard hatch at a service-bay edge, raised .02 above the slab, one chunk/colour.
    m.box((w/2-7,.022,10.3),(7,.035,1.8),'ServiceBlack',bevel=0)
    for i in range(6):
        m.box((w/2-10+i*1.05,.047,10.3),(.48,.025,1.45),'HazardYellow',bevel=0,
              rotation=Matrix.Rotation(math.radians(25),4,'Z'))


def lamp_geometry():
    """Reuse the architecture LampPanel without exporting unrelated components."""
    if 'LampPanel' in kit.COMPONENTS: return kit.COMPONENTS['LampPanel']['mesh']
    path=Path(__file__).with_name('modules_arch.py')
    if path.exists():
        import modules_arch
        if hasattr(modules_arch,'lamp'):
            modules_arch.lamp()
            return kit.COMPONENTS.pop('LampPanel')['mesh']
    return None


def append_mesh(m,mesh,pos):
    bm=bmesh.new(); bm.from_mesh(mesh)
    # Already-metres mesh: reverse scale before absorb(), translate in studs.
    bmesh.ops.scale(bm,vec=Vector((1/kit.S,)*3),verts=list(bm.verts))
    kit.Mesh._xf(bm,pos,None)
    for idx,mat in enumerate(mesh.materials):
        tmp=bm.copy()
        bmesh.ops.delete(tmp,geom=[f for f in tmp.faces if f.material_index!=idx],context='FACES')
        key=mat.name.removeprefix('L2K_')
        m.absorb(tmp,key)
    bm.free()


def fixtures(m,w,d,h,changing,panel):
    # Four runtime lights per room. Review lighting derives from these markers.
    for x,z in ((-w/4,-d/4),(w/4,-d/4),(-w/4,d/4),(w/4,d/4)):
        if changing:
            y=h-.42
            if panel: append_mesh(m,panel,(x,y,z))
            else:
                edge_box(m,(x,y,z),(8,.4,3),'Steel')
                m.box((x,y-.23,z),(7.6,.08,2.6),'LampGlow',bevel=0)
            m.marker('Light',(x,y-.09,z),Fixture='LampPanel',Shadows=False)
        else:
            y=h-3.5
            m.cylinder((x,y,z),1,.35,'Steel',segments=8)
            m.cylinder((x,y-.32,z),.85,.35,'LampGlow',segments=8)
            for dx in (-.8,.8): m.box((x+dx,y-.5,z),(.10,.7,1.3),'Steel',bevel=0)
            for zz in (-.6,0,.6): m.box((x,y-.65,z+zz),(1.7,.1,.10),'Steel',bevel=0)
            m.marker('Light',(x,y-.75,z),Fixture='CagedBulkhead',Shadows=False)


def build():
    kit.PALETTE.setdefault('ServiceBlack',('concrete_paint','L2K Service',(35,40,41)))
    kit.PALETTE.setdefault('HazardYellow',('concrete_paint','L2K Service',(244,196,72)))
    panel=lamp_geometry()
    for name,(w,d,h) in ROOMS.items():
        assert name not in kit.COMPONENTS,name
        FOOTPRINTS[name],DETAIL_TRIS[name]=[],[]
        changing=name.startswith('Changing'); large=name.endswith('_B')
        m=kit.Mesh(name,Role='Small',Archetype='Changing Room' if changing else 'Plant Room',PoolType='Dry',
                   Width=w,Depth=d,Height=h,Pivot='FloorCentre',SocketIndexConvention='0=centre, 1=-16, 2=+16',
                   MeshCanCollide=False,MeshCanQuery=False,MeshCanTouch=False,MeshCastShadow=True,
                   RouteRule='6-wide central cross; off-centre sockets perpendicular to matching centre axis')
        shell(m,w,d,h,changing)
        if changing:
            zs=[26.5,30.9,35.3] if large else [10.5,14.9]
            cx=26.9 if large else 26.1; cubicle_row(m,cx,zs); cubicle_row(m,-cx,[-z for z in reversed(zs)])
            islands=[(-8,-27),(8,-27),(-8,27),(8,27)] if large else [(-8,-12),(8,12)]
            for x,z in islands: locker_island(m,x,z)
            if large:
                for x,z in ((-8,-8),(8,8)):
                    locker_island(m,x,z,doors=3,width=6)
                    bench(m,x,z-3.5 if z<0 else z+3.5)
            benches=[(-8,-22),(8,22),(-8,32)] if large else [(-8,-6.5),(8,6.5)]
            for x,z in benches: bench(m,x,z)
            for sign in (-1,1): partition(m,sign*25.8,-sign*(27 if large else 13),10)
            changing_detail(m,w,d,large)
        else:
            filters=[(-29,-24),(29,-24),(-8,-8)] if large else [(-8,-8),(8,-8)]
            for x,z in filters: filter_unit(m,x,z)
            for x,z in ([(-8,8),(8,-8)] if large else [(-8,8)]): pump(m,x,z)
            manifold(m,w/2-7.35,d/2-6)
            plant_services(m,w,d,h)
        fixtures(m,w,d,h,changing,panel)
        m.finish()
    return {name:kit.COMPONENTS[name] for name in ROOMS}


def segment_box_distance(a,b,rect):
    xmin,xmax,zmin,zmax=rect; ax,az=a; bx,bz=b; dx,dz=bx-ax,bz-az
    lo,hi=0.,1.
    for p,v,low,high in ((ax,dx,xmin,xmax),(az,dz,zmin,zmax)):
        if abs(v)<1e-9:
            if p<low or p>high: break
        else:
            t0,t1=sorted(((low-p)/v,(high-p)/v)); lo,hi=max(lo,t0),min(hi,t1)
            if lo>hi: break
    else:
        if lo<=hi: return 0.
    def point_segment(x,z):
        t=max(0.,min(1.,((x-ax)*dx+(z-az)*dz)/(dx*dx+dz*dz)))
        return math.hypot(x-ax-t*dx,z-az-t*dz)
    def point_box(x,z): return math.hypot(max(xmin-x,0,x-xmax),max(zmin-z,0,z-zmax))
    return min(point_box(ax,az),point_box(bx,bz),*(point_segment(x,z) for x in (xmin,xmax) for z in (zmin,zmax)))


def route_segments(info,w,d):
    routes=[((-w/2,0),(w/2,0)),((0,-d/2),(0,d/2))]
    for s in info['markers']:
        if s['name']!='Socket': continue
        x,_,z,_=s['cf']; wall=s['attrs']['Wall']
        if (x if wall in 'NS' else z)!=0:
            routes.append(((x,z),(x,0) if wall in 'NS' else (0,z)))
    return routes


def verify():
    results={}
    for name,(w,d,h) in ROOMS.items():
        info=kit.COMPONENTS[name]; mesh=info['mesh']; mesh.calc_loop_triangles(); count=len(mesh.loop_triangles)
        assert 0<count<=6000,(name,count)
        assert not mesh.validate(verbose=True),name
        bm=bmesh.new(); bm.from_mesh(mesh)
        assert all(e.is_manifold for e in bm.edges),(name,'open surface')
        assert all(f.calc_area()>1e-10 for f in bm.faces),(name,'degenerate face')
        # Recalculated normals must point outward on each disconnected solid.
        remaining=set(bm.faces)
        while remaining:
            pending=[remaining.pop()]; group=[]
            while pending:
                f=pending.pop(); group.append(f)
                for e in f.edges:
                    for other in e.link_faces:
                        if other in remaining: remaining.remove(other); pending.append(other)
            vol=0.
            for f in group:
                v=[v.co for v in f.verts]
                vol+=sum(v[0].dot(v[i].cross(v[i+1]))/6 for i in range(1,len(v)-1))
            assert vol>0,(name,'inward normals',vol)
        bm.free()
        assert all(math.isfinite(c) for v in mesh.vertices for c in v.co)
        assert all(math.isfinite(c) for uv in mesh.uv_layers.active.data for c in uv.uv)
        assert sum('Roof' in c['name'] for c in info['colliders'])==1
        assert not any(any(t in p['name'] for t in ('Roof','Ceiling','Skylight')) for p in info['parts']+info['markers'])
        assert info['parts'][0]['ground']
        for p in info['parts']+info['colliders']:
            if p['ground']: assert p['size'][0]>=4 and p['size'][2]>=4,p
        sockets=[s for s in info['markers'] if s['name']=='Socket']
        assert len(sockets)==2*(3 if w>=64 else 1)+2*(3 if d>=64 else 1)
        for s in sockets:
            key=s['attrs']['Wall']+str(s['attrs']['Index'])
            plugs=[p for p in info['parts'] if p['attrs'].get('SocketPlug')==key]
            assert len(plugs)==1 and plugs[0]['size'][1]==16 and 12 in plugs[0]['size']
            wall=s['attrs']['Wall']; axis=0 if wall in 'NS' else 2; along=s['cf'][axis]
            for p in info['parts']:
                if p['name'].startswith(f'Level 2 Room {wall} Wall Run'):
                    assert p['cf'][axis]+p['size'][axis]/2<=along-6+1e-6 or p['cf'][axis]-p['size'][axis]/2>=along+6-1e-6
        lane_min=door_min=float('inf')
        for label,(x,y,z),(sx,sy,sz) in FOOTPRINTS[name]:
            rect=(x-sx/2,x+sx/2,z-sz/2,z+sz/2)
            assert rect[0]>=-w/2+THICK-1e-6 and rect[1]<=w/2-THICK+1e-6,(name,label,'X bounds',rect)
            assert rect[2]>=-d/2+THICK-1e-6 and rect[3]<=d/2-THICK+1e-6,(name,label,'Z bounds',rect)
            for a,b in route_segments(info,w,d):
                dist=segment_box_distance(a,b,rect); lane_min=min(lane_min,dist)
                assert dist>=3-1e-6,(name,label,'lane',dist,rect)
            for s in sockets:
                px,_,pz,_=s['cf']; wall=s['attrs']['Wall']
                if wall in 'NS':
                    inside=pz+(THICK if wall=='N' else -THICK); a,b=(px-6,inside),(px+6,inside)
                else:
                    inside=px+(-THICK if wall=='E' else THICK); a,b=(inside,pz-6),(inside,pz+6)
                dist=segment_box_distance(a,b,rect); door_min=min(door_min,dist)
                assert dist>=2-1e-6,(name,label,'socket setback',dist,rect)
        # Occupied envelopes may nest (machinery on plinths), but never intrude into routes.
        mats=[mat.name.removeprefix('L2K_') for mat in mesh.materials]
        assert len(mats)==len(set(mats)) and mats.count('Bands')<=1
        if name.startswith('Changing'):
            bands_idx=mats.index('Bands'); vals=[mesh.uv_layers.active.data[l].uv.y for p in mesh.polygons if p.material_index==bands_idx for l in p.loop_indices]
            assert min(vals)>=-1e-5 and max(vals)<=1+1e-5
            assert next(p for p in info['parts'] if 'Overhead' in p['name'])['material']=='Tile'
        results[name]={'tris':count,'parts':len(info['parts']),'colliders':len(info['colliders']),
                       'chunks':len(mats),'lights':4,'markers':len(info['markers']),
                       'runtimeInstancesExcludingMarkers':len(info['parts'])+len(info['colliders'])+len(mats)+4,
                       'minLaneEdgeDistanceStuds':round(lane_min,4),'minDoorwayClearanceStuds':round(door_min,4),
                       'details':DETAIL_TRIS[name]}
        print(name,json.dumps(results[name]),flush=True)
    return results


def review_record(col,rec):
    tmp=kit.Mesh('ReviewOnly'); tmp.box(rec['cf'][:3],rec['size'],rec['material'],bevel=0,
                                     rotation=Matrix.Rotation(-math.radians(rec['cf'][3]),4,'Z'))
    mesh=tmp.finish(register=False)
    ob=bpy.data.objects.new(rec['name'],mesh); col.objects.link(ob); return ob


def plain_material(name,rgb):
    m=bpy.data.materials.new(name); m.use_nodes=True
    b=m.node_tree.nodes['Principled BSDF']; b.inputs['Base Color'].default_value=(*rgb,1); b.inputs['Roughness'].default_value=.75
    return m


def camera(col,pos,target,ortho=None):
    ob=bpy.data.objects.new('Review Camera',bpy.data.cameras.new('Review Camera')); col.objects.link(ob)
    ob.location=kit.to_blender(pos); ob.rotation_euler=(kit.to_blender(target)-ob.location).to_track_quat('-Z','Y').to_euler()
    ob.data.lens=23; ob.data.clip_start=.025; ob.data.clip_end=200
    if ortho: ob.data.type='ORTHO'; ob.data.ortho_scale=ortho*kit.S
    bpy.context.scene.camera=ob; return ob


def label(col,text,x,z,mat,size=1.6):
    cu=bpy.data.curves.new('Review label','FONT'); cu.body=text; cu.size=size*kit.S; cu.align_x='CENTER'
    ob=bpy.data.objects.new('Plan label '+text,cu); col.objects.link(ob); ob.location=kit.to_blender((x,28,z)); cu.materials.append(mat)


def lane_overlay(col,a,b,mat):
    x,z=a; xx,zz=b; length=math.hypot(xx-x,zz-z); dx,dz=-(zz-z)/length*3,(xx-x)/length*3
    me=bpy.data.meshes.new('Plan six stud lane'); me.from_pydata([kit.to_blender(p) for p in
        ((x+dx,.08,z+dz),(x-dx,.08,z-dz),(xx-dx,.08,zz-dz),(xx+dx,.08,zz+dz))],[],[(0,1,2,3)])
    me.materials.append(mat); ob=bpy.data.objects.new('Review route',me); col.objects.link(ob)


def area(col,pos,target,energy,size,color=(1,.91,.79),shadows=True):
    data=bpy.data.lights.new('Review light','AREA'); data.energy=energy; data.shape='DISK'; data.size=size*kit.S; data.color=color; data.use_shadow=shadows
    ob=bpy.data.objects.new('Review light',data); col.objects.link(ob); ob.location=kit.to_blender(pos)
    ob.rotation_euler=(kit.to_blender(target)-ob.location).to_track_quat('-Z','Y').to_euler()


def render_reviews(samples=48,only=None):
    REVIEW.mkdir(parents=True,exist_ok=True); sc=bpy.context.scene; sc.render.engine='BLENDER_EEVEE'; sc.eevee.taa_render_samples=samples
    sc.render.image_settings.file_format='PNG'; sc.render.resolution_percentage=100; sc.view_settings.view_transform='AgX'
    sc.world=bpy.data.worlds.new('Review World'); sc.world.use_nodes=True
    ink=plain_material('Plan Ink',(.02,.04,.05)); lane=plain_material('Clear Route',(.12,.46,.47))
    for name,(w,d,h) in ROOMS.items():
        if only and only!=name: continue
        sc.world.node_tree.nodes['Background'].inputs[0].default_value=(.30,.38,.43,1)
        sc.world.node_tree.nodes['Background'].inputs[1].default_value=.45
        col=bpy.data.collections.new('Review '+name); sc.collection.children.link(col)
        info=kit.COMPONENTS[name]; ob=kit.place(col,name)
        # Per-record preview is needed to selectively open sockets and make plans.
        # Suppress kit.place's aggregate Part preview; no duplicate rendered shells.
        for other in col.objects:
            if other!=ob: other.hide_render=True
        records=[(review_record(col,p),p) for p in info['parts']]
        for p in info['markers']:
            if p['name']=='Light':
                x,y,z,_=p['cf']; area(col,(x,y-.25,z),(x,0,z),550 if name.startswith('Changing') else 400,8)
        if name.startswith('Changing'): area(col,(0,-2,0),(0,h,0),650,w/2,(1,.95,.86),shadows=False)
        area(col,(0,10,-d/2+2),(0,5,0),450,10,(.82,.91,1))
        area(col,(0,11,d/2-2),(0,5,0),350,9,(.84,.94,1))
        for suffix,wall,pos,target in (
            ('eye','N0',(0,5.7,-d/2+.25),(3,6.0,d/4)),
            ('eye_E2' if d>=64 else 'eye_E0','E2' if d>=64 else 'E0',
             (w/2-.25,5.7,16 if d>=64 else 0),(-w/4,6,-d/7))):
            for o,p in records: o.hide_render=p['attrs'].get('SocketPlug')==wall
            camera(col,pos,target)
            sc.render.resolution_x,sc.render.resolution_y=1440,900
            sc.render.filepath=str(REVIEW/f'{name}_{suffix}.png'); bpy.ops.render.render(write_still=True)
        # Open all sockets, remove overhead detail above the plan cut plane.
        for o,p in records:
            o.hide_render=bool(p['attrs'].get('SocketPlug')) or 'Overhead' in p['name'] or p['cf'][1]>16
        ob.hide_render=True; plan=ob.data.copy(); bm=bmesh.new(); bm.from_mesh(plan)
        bmesh.ops.delete(bm,geom=[v for v in bm.verts if v.co.z>11*kit.S],context='VERTS'); bm.to_mesh(plan); bm.free()
        po=bpy.data.objects.new('Review Cutaway Detail',plan); col.objects.link(po)
        for a,b in route_segments(info,w,d): lane_overlay(col,a,b,lane)
        for s in info['markers']:
            if s['name']!='Socket': continue
            x,_,z,_=s['cf']; wall=s['attrs']['Wall']
            label(col,wall+str(s['attrs']['Index']),x+(4 if wall=='E' else -4 if wall=='W' else 0),z+(4 if wall=='S' else -4 if wall=='N' else 0),ink)
        label(col,name+f'  |  {w} x {d}  |  h {h}',0,-d/2-10,ink,2)
        label(col,'Teal: 6-stud centre cross + perpendicular socket routes\nAll sockets open; overhead cut away\nFurnishings are exported geometry',0,d/2+10,ink,1.35)
        sc.world.node_tree.nodes['Background'].inputs[0].default_value=(.7,.78,.80,1); sc.world.node_tree.nodes['Background'].inputs[1].default_value=.65
        area(col,(0,70,0),(0,0,0),2500,70,(1,1,1))
        camera(col,(0,125,0),(0,0,0),ortho=max(w+32,(d+38)*1.2))
        sc.render.resolution_x,sc.render.resolution_y=1500,1250
        sc.render.filepath=str(REVIEW/f'{name}_plan.png'); bpy.ops.render.render(write_still=True)
        col.hide_render=True
    print('L2K_ROOM_REVIEWS_OK',flush=True)


def main():
    p=argparse.ArgumentParser(); p.add_argument('--samples',type=int,default=48); p.add_argument('--only',choices=list(ROOMS)); p.add_argument('--export-only',action='store_true')
    args=p.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    bpy.ops.wm.read_factory_settings(use_empty=True); build(); results=verify(); kit.EXPORT_DIR=EXPORT
    manifest=kit.export(); assert set(manifest['components'])==set(ROOMS)
    # Retire only this job's numbered wire outputs, after successful export.
    expected={f"c{c['id']:05d}.b64" for c in manifest['chunks']}
    for old in (EXPORT/'chunks').glob('c[0-9][0-9][0-9][0-9][0-9].b64'):
        if old.name not in expected:
            assert old.resolve().parent==(EXPORT/'chunks').resolve()
            assert old.resolve().is_relative_to(EXPORT.resolve())
            old.unlink()
    assert {f.name for f in (EXPORT/'chunks').glob('*.b64')}==expected
    assert sum(c['tris'] for c in manifest['chunks'])==sum(r['tris'] for r in results.values())
    for c in manifest['chunks']:
        wire=(EXPORT/'chunks'/f"c{c['id']:05d}.b64").read_text(); blob=base64.b64decode(wire,validate=True)
        assert hashlib.sha256(blob).hexdigest()==c['sha256'] and hashlib.sha256(wire.encode()).hexdigest()==c['wireSha256']
        nv,nn,nu,nt=struct.unpack('<4I',blob[:16]); assert nt==c['tris'] and len(blob)==16+nv*12+nn*12+nu*8+nt*36
        if c['material']=='Bands':
            start=16+nv*12+nn*12; values=struct.unpack('<%df'%(nu*2),blob[start:start+nu*8]); assert min(values[1::2])>=-1e-5 and max(values[1::2])<=1+1e-5
    (EXPORT/'verification.json').write_text(json.dumps({'rooms':results,'checks':['<=6000 visual tris per room','closed nondegenerate solids and outward normals',
        'finite coordinates/UVs','one material per chunk','one Bands chunk and V 0..1','socket apertures/plugs','6-wide centre cross and perpendicular routes',
        '2-stud full aperture setback','ground collider footprints','one roof collider','wire lengths and SHA256'],
        'notes':['Kit Part previews excluded from wire export; review per-record previews are identical to runtime records.',
                 'Cubicle doors are static, with scoped box collision; no interaction system.',
                 'Locker islands, benches, filters, pumps, drums and hose reel are native merged kit geometry, not PropSlot stand-ins.',
                 'Raised plinths are ground-tagged Parts; flush grates use the flat ground slab beneath.',
                 'LampPanel geometry reused from modules_arch.lamp and merged into the four room components.',
                 'ChangingRoom_B adds two smaller back-to-back locker islands and two benches to fill the centre bays beyond the original sparse contents list.',
                 'Socket count drives shell records above the typical ~40-instance estimate; four runtime lights per room.',
                 'Offline checks only; Studio, gameplay, multiplayer and device performance unverified.']},indent=2),encoding='utf-8')
    if not args.export_only: render_reviews(args.samples,args.only)
    print('C2_COMPLETE',flush=True)


if __name__=='__main__': main()






