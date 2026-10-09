"""Job A: offline architecture kit. All modelling inputs use Roblox studs/axes.

Run: D:/Blender/blender.exe -b --factory-startup --python-exit-code 1
     -P G:/Roblox/MongoTV/tools/level2_blender/modules_arch.py --
Outputs only jobs/A/export and review/A. Import build() from the kit master.
"""
import sys, math, json, argparse
from pathlib import Path
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import bpy
from mathutils import Vector, Matrix
import kit

OUT = Path('G:/Blender/Level2_Pool/jobs/A/export')
REVIEW = Path('G:/Blender/Level2_Pool/review/A')
BUDGETS = {}
S = kit.S


def band_uv(bottom, height, radius=None):
    def uv(co, normal):
        u = math.atan2(-co.y, co.x) * radius * S if radius else co.x
        return u, (co.z / S - bottom) / height
    return uv


def done(m, budget):
    import bmesh
    if m.name.startswith(('Column','SkylightWell')):
        bmesh.ops.remove_doubles(m.bm,verts=list(m.bm.verts),dist=.000001)
    m.finish()
    # Required registry IDs contain 'Skylight', but instance names must not.
    kit.COMPONENTS[m.name]['mesh'].name = 'L2K_' + m.name.replace('Skylight', 'Light')
    BUDGETS[m.name] = budget
    return m


def prism(m, profile, x0, x1, mat, uv=None):
    """Closed X extrusion of a (Y,Z) profile, no redundant internal boxes."""
    n = len(profile)
    verts = [(x, y, z) for x in (x0, x1) for y, z in profile]
    faces = [tuple(range(n-1, -1, -1)), tuple(range(n, 2*n))]
    faces += [(i, (i+1)%n, (i+1)%n+n, i+n) for i in range(n)]
    m.raw(verts, faces, mat, uv=uv)


def lathe(m, rings, mat, n=24, uv=None, caps=True):
    """Vertical closed annular/profile surface; rings are (height,radius)."""
    verts = [(r*math.cos(2*math.pi*i/n), y, r*math.sin(2*math.pi*i/n))
             for y,r in rings for i in range(n)]
    faces = [(j*n+i, j*n+(i+1)%n, (j+1)*n+(i+1)%n, (j+1)*n+i)
             for j in range(len(rings)-1) for i in range(n)]
    if caps:
        faces += [tuple(range(n-1,-1,-1)), tuple((len(rings)-1)*n+i for i in range(n))]
    m.raw(verts, faces, mat, uv=uv, smooth=True)


def tube(m, path, radius=.12, mat='Steel', n=6):
    """Mitered continuous rail, including closed ends, with no intersecting elbows."""
    pts = [Vector(p) for p in path]
    verts = []
    for i,p in enumerate(pts):
        t = (pts[min(i+1,len(pts)-1)]-pts[max(i-1,0)]).normalized()
        ref = Vector((1,0,0)) if abs(t.x)<.85 else Vector((0,0,1))
        a = t.cross(ref).normalized(); b = t.cross(a).normalized()
        for k in range(n):
            v = p + radius*(a*math.cos(k*2*math.pi/n)+b*math.sin(k*2*math.pi/n))
            verts.append(tuple(v))
    faces = [(j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i)
             for j in range(len(pts)-1) for i in range(n)]
    faces += [tuple(range(n-1,-1,-1)),tuple((len(pts)-1)*n+i for i in range(n))]
    m.raw(verts,faces,mat,smooth=True)


def arch():
    m = kit.Mesh('DoorArch30', Opening=[30,30], OuterWidth=36, WallDepth=3.5,
                 ProudPerSide=.6, VisualCrown=33, SpandrelTop=34.5)
    bottom, bh = 10, 1/S
    for sign in (-1,1):
        x = sign*16.5
        for lo,hi,mat in ((0,bottom,'Tile'),(bottom,bottom+bh,'Bands'),(bottom+bh,30,'Tile')):
            m.box((x,(lo+hi)/2,0),(3,hi-lo,4.4),mat,bevel=.035,
                  uv=band_uv(bottom,bh) if mat=='Bands' else None)
        m.box((sign*16.5,32.25,0),(3,4.5,4.4),'Tile',bevel=0)
    xs = [-15+30*i/18 for i in range(19)]
    ys = [math.sqrt(39**2-x*x)-6 for x in xs]
    # One watertight spandrel extrusion, lower edge follows the circular segment.
    verts = [(x,y,z) for z in (-2.2,2.2) for x,y in
             list(zip(xs,ys))+[(15,34.5),(-15,34.5)]]
    n=len(xs)+2
    faces=[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]
    faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    m.raw(verts,faces,'Tile')
    # Rounded cobalt bead on each mouth, completely outside the 30 x 30 opening.
    for side in (-1,1):
        z=side*2.25
        path=[(-15.05,.1,z),(-15.05,30,z)]
        path += [(x*39.12/39,-6+(y+6)*39.12/39,z) for x,y in zip(xs,ys)]
        path += [(15.05,.1,z)]
        tube(m,path,.1,'Cobalt',6)
        # Individual subtly proud voussoirs catch light; the solid spandrel behind
        # their fine grout joints seals the wall completely.
        for i in range(len(xs)-1):
            a0=math.atan2(ys[i]+6,xs[i])-.00035
            a1=math.atan2(ys[i+1]+6,xs[i+1])+.00035
            vv=[(r*math.cos(a),-6+r*math.sin(a),zz)
                for zz in (side*2.205,side*2.335)
                for r,a in ((39.15,a0),(39.15,a1),(39.85,a1),(39.85,a0))]
            m.raw(vv,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),
                      (2,3,7,6),(3,0,4,7)],'Tile')
    m.marker('Socket',(0,0,0), OpeningWidth=30, OpeningHeight=30)
    return done(m,1500)


def service():
    m=kit.Mesh('DoorService12',Opening=[12,16],WallDepth=3.5)
    for s in (-1,1):
        m.box((s*6.75,8,0),(1.5,16,3.5),'Tile',bevel=.035)
        m.box((s*6.14,8,-1.81),(.28,16,.25),'Steel',bevel=.035)
        m.box((s*6.14,8,1.81),(.28,16,.25),'Steel',bevel=.035)
    m.box((0,16.55,0),(15,1.1,3.5),'Tile',bevel=.04)
    for z in (-1.81,1.81):
        m.box((0,16.14,z),(12.55,.28,.25),'Steel',bevel=.025)
    m.marker('Socket',(0,0,0),OpeningWidth=12,OpeningHeight=16)
    return done(m,600)


# Bullnose occupies z=-.3..+.9; top y=0. Water lies on -Z.
COPING_PROFILE=[(0,-.05),(0,.86),(-.04,.9),(-.46,.9),(-.5,-.05),
                (-.427,-.227),(-.25,-.3),(-.073,-.227)]


def coping(length):
    m=kit.Mesh('Coping'+str(length),WaterSide='-Z',DeckTop=0,Width=1.2,Overhang=.3)
    # Shallow integral expansion grooves every four studs, no holes or added materials.
    stations=[(-length/2,0)]
    pitch=8 if length==64 else 4
    for i in range(1,int(length/pitch)):
        x=-length/2+pitch*i
        stations.extend([(x-.025,0),(x,-.018),(x+.025,0)])
    stations.append((length/2,0))
    n=len(COPING_PROFILE)
    verts=[(x,y+(d if y>-.46 else 0),z) for x,d in stations for y,z in COPING_PROFILE]
    faces=[(j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i)
           for j in range(len(stations)-1) for i in range(n)]
    faces += [tuple(range(n-1,-1,-1)),tuple((len(stations)-1)*n+i for i in range(n))]
    m.raw(verts,faces,'Terrazzo')
    # Only the deck-supported portion is walkable; hull stays a noncolliding mesh.
    m.marker('Edge',(0,0,0),WaterSide='-Z')
    return done(m,{8:120,16:240,32:400,64:600}[length])


def corner():
    m=kit.Mesh('CopingCorner',WaterSide='outside quadrant -X,-Z',DeckTop=0)
    # Quarter-turn of the exact straight-piece profile, tangent sockets at both ends.
    n=len(COPING_PROFILE); count=8
    verts=[(-(1.3-z)*math.sin(a),y,-(1.3-z)*math.cos(a))
           for a in [i*math.pi/2/count for i in range(count+1)] for y,z in COPING_PROFILE]
    faces=[(j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i)
           for j in range(count) for i in range(n)]
    faces += [tuple(range(n-1,-1,-1)),tuple(count*n+i for i in range(n))]
    m.raw(verts,faces,'Terrazzo')
    m.marker('TangentX',(0,0,-1.3)); m.marker('TangentZ',(-1.3,0,0),yaw=90)
    return done(m,600)


def gutter(length):
    m=kit.Mesh('Gutter'+str(length),DeckTop=0,Width=1.1,Depth=.6)
    # U channel: bottom and walls, open top, tucked behind coping at placement z=1.5.
    prism(m,[(-.57,-.55),(-.57,.55),(-.03,.55),(-.03,.43),(-.45,.43),
             (-.45,-.43),(-.03,-.43),(-.03,-.55)],-length/2,length/2,'Mosaic')
    for z in (-.48,.48): m.box((0,-.075,z),(length,.15,.14),'Steel',bevel=0)
    count=math.ceil(length/1.15)
    for i in range(count):
        m.box((-length/2+(i+.5)*length/count,-.055,0),(.12,.11,.84),'Steel',bevel=0)
    m.marker('DeckInset',(0,0,0))
    return done(m,{16:300,32:500,64:800}[length])


def column(d,h):
    name='Column'+str(d).replace('.','_').removesuffix('_0')+'_H'+str(h)
    m=kit.Mesh(name,Diameter=d,Height=h)
    r=d/2; bot=h/3; bh=1/S
    uv=lambda co,no:(math.atan2(-co.y,co.x)*r*S,co.z)
    lathe(m,[(0,r+.38),(.15,r+.4),(.4,r+.36),(1.3,r),(bot,r)],'Tile',24,uv,caps=False)
    lathe(m,[(bot,r),(bot+bh,r)],'Bands',24,band_uv(bot,bh,r),caps=False)
    lathe(m,[(bot+bh,r),(h-1.3,r),(h-.5,r+.32),(h-.18,r+.4),(h,r+.4)],'Tile',24,uv,caps=False)
    # Close floor and top without creating hidden internal caps.
    verts=[(rr*math.cos(2*math.pi*i/24),y,rr*math.sin(2*math.pi*i/24))
           for y,rr in [(0,r+.38),(h,r+.4)] for i in range(24)]
    m.raw(verts,[tuple(range(23,-1,-1)),tuple(range(24,48))],'Tile')
    # kit cf supports yaw only; explicit orientation metadata tells importer to turn
    # Roblox's X-axis native cylinder vertical. Geometric size remains Roblox XYZ.
    m.collider('ColumnCollider',(0,h/2,0),(d,h,d),shape='Cylinder',
               attrs={'CylinderAxis':'Y','NativeSizeX':h,'NativeSizeY':d,'NativeSizeZ':d,'NativeRotationZ':90})
    m.marker('Capital',(0,h,0))
    return done(m,800)


def well(size,r,letter):
    m=kit.Mesh('SkylightWell'+letter,PanelWidth=size,HoleRadius=r,WellDepth=6,
               InstanceName='L2K LightWell'+letter)
    n=32
    verts=[]
    for y in (0,.6):
        for kind in ('outer','inner'):
            for i in range(n):
                a=2*math.pi*i/n; c,s=math.cos(a),math.sin(a)
                rr=size/2/max(abs(c),abs(s)) if kind=='outer' else r
                verts.append((rr*c,y,rr*s))
    faces=[]
    for i in range(n):
        j=(i+1)%n
        faces.extend([(i,j,n+j,n+i),(2*n+i,3*n+i,3*n+j,2*n+j),
                      (i,2*n+i,2*n+j,j),(n+i,n+j,3*n+j,3*n+i)])
    m.raw(verts,faces,'Tile')
    # Closed wall profile, inner bands replace tile rather than overlaying it.
    uv=lambda co,no:(math.atan2(-co.y,co.x)*r*S,co.z)
    bh=1/S; bot=1.1
    lathe(m,[(.59,r),(bot,r)],'Tile',n,uv,caps=False)
    lathe(m,[(bot,r),(bot+bh,r)],'Bands',n,band_uv(bot,bh,r),caps=False)
    lathe(m,[(bot+bh,r),(6,r),(6,r+.45),(.59,r+.45),(.59,r)],'Tile',n,uv,caps=False)
    # Thin folded steel rim atop the well (task calls for a third material).
    lathe(m,[(5.92,r-.06),(6.1,r-.06),(6.1,r+.51),(5.92,r+.51),(5.92,r-.06)],
          'Steel',n,caps=False)
    m.marker('LightOpening',(0,6,0),Radius=r)
    return done(m,900)


def cove(length):
    m=kit.Mesh('Cove'+str(length),WallSide='+Z',Top=0)
    # Concave glazed cove, closed back and underside, real .15 minimum thickness.
    profile=[(0,.95),(0,-.7),(-.12,-.7),(-.17,-.35),(-.3,0),
             (-.53,.3),(-.86,.53),(-1.25,.7),(-1.6,.76),(-1.6,.95)]
    prism(m,profile,-length/2,length/2,'Tile')
    return done(m,150)


def ladder():
    m=kit.Mesh('Ladder',BasinReach=4,WaterSide='-Z')
    for x in (-1.3,1.3):
        path=[(x,0,1.1),(x,1.1,1.1),(x,1.65,.9),(x,1.9,.4),
              (x,1.65,-.1),(x,1.1,-.35),(x,-3.9,-.35)]
        tube(m,path,.13,n=8)
        m.cylinder((x,.03,1.1),.28,.06,'Steel',segments=8)
    for y in (-.9,-2.1,-3.3):
        tube(m,[(-1.3,y,-.35),(1.3,y,-.35)],.17,n=8)
    m.marker('DeckAnchor',(0,0,1.1))
    return done(m,600)


def pool_steps():
    m=kit.Mesh('PoolSteps',Width=12,Rise=.6,WaterSide='-Z')
    for i in range(2):
        top=-(i+1)*.6; z=-(i+.5)*4
        m.box((0,top-.16,z),(12,.32,4),'Terrazzo',bevel=.04)
        # Separate riser fills the drop, with .02 setback from bullnose tread.
        m.box((0,top-.43,z-1.96),(12,.54,.07),'Mosaic',bevel=0)
        m.collider('Step'+str(i+1),(0,top-.3,z),(12,.6,4),ground=True)
    return done(m,300)


def stair(height):
    # Exact endpoint, nominal .78 rise; the top step absorbs the small remainder.
    n=math.ceil(height/.78); m=kit.Mesh('StairFlight'+str(height),Width=10,Run=2.3,
                                      NominalRise=.78,Height=height)
    for i in range(n):
        top=min((i+1)*.78,height); z=(i+.5)*2.3
        # Efficient stepped solid with a tiny bevel only on the tread's leading edge.
        prism(m,[(0,z-1.15),(0,z+1.15),(top,z+1.15),(top,z-1.11),
                 (top-.04,z-1.15)],-5,5,'Terrazzo')
        # Extended uphill underneath next step; no extra raised walking surface.
        m.collider('Tread'+str(i+1),(0,top/2,z+.85),(10,top,4),ground=True)
    # Tiled cheeks are thin stepped profiles, no broad invisible collider.
    profile=[(0,0),(0,n*2.3)]
    for i in range(n-1,-1,-1):
        top=min((i+1)*.78,height)
        profile.extend([(top-.08,(i+1)*2.3),(top-.08,i*2.3)])
    for x in (-5.2,5.2): prism(m,profile,x-.18,x+.18,'Tile')
    # The final four-stud collider's uphill extension is a visible landing.
    m.part('L2K Upper Landing',(0,height/2,n*2.3+.85),(10,height,1.7),
           'Terrazzo',collide=False,show=False)
    m.marker('Start',(0,0,0));m.marker('End',(0,height,n*2.3))
    return done(m,400)


def lamp():
    m=kit.Mesh('LampPanel',Size=[8,3],Mount='underside')
    # Folded steel tray with recessed, enclosed warm diffuser.
    m.box((0,.23,0),(8,.4,3),'Steel',bevel=.055)
    m.box((0,-.015,0),(7.55,.09,2.55),'LampGlow',bevel=.035)
    m.marker('Light',(0,-.09,0),Shadows=False)
    return done(m,200)


def glass():
    m=kit.Mesh('GlassBlockPanel8',PanelSize=[8,8],Inset=.3)
    # Flat window remains a Part record, not a duplicate glass chunk.
    m.part('L2K Glass Block Pane',(0,4,.45),(8,8,.3),'GlassBlock',collide=False,show=False)
    for x in (-4.35,4.35):m.box((x,4,0),(.7,8.7,1.2),'Tile',bevel=.04)
    for y in (-.35,8.35):m.box((0,y,0),(8,.7,1.2),'Tile',bevel=.04)
    m.marker('WallInset',(0,0,0))
    return done(m,600)


def tower():
    m=kit.Mesh('DivingTower',PlatformHeights=[4.5,7.5,10.5],Width=10)
    # Period concrete spine, tiled cladding; platforms project toward water (-Z).
    for x in (-3.8,3.8):m.box((x,5.2,2.8),(1,10.4,1.5),'Tile',bevel=.05)
    for x in (-3.8,3.8):m.collider('TowerPier',(x,5.2,2.8),(1,10.4,1.5))
    for h in (4.5,7.5,10.5):
        # Offset alternate decks: 3-stud-separated levels never cover one another.
        cx=-10 if h!=7.5 else 0
        front=-10 if h==4.5 else -6
        prism(m,[(h-.5,front),(h-.5,4),(h,4),(h,front+.07),(h-.07,front)],cx-5,cx+5,'Terrazzo')
        m.collider('Platform'+str(h),(cx,h-.25,(front+4)/2),(10,.5,4-front),ground=True)
        if cx:
            m.box((-6,h-.8,2.8),(13,.6,1.5),'Tile',bevel=.04)
        # Side rails and rear return. The dive edge stays open.
        for x in (cx-4.65,cx+4.65):
            tube(m,[(x,h,front+1.2),(x,h+2.7,front+1.2),(x,h+2.7,3.6),(x,h,3.6)],.095)
            tube(m,[(x,h+1.35,front+1.2),(x,h+1.35,3.6)],.075)
            tube(m,[(x,h,.2),(x,h+2.7,.2)],.085)
        tube(m,[(cx-4.65,h+2.7,3.6),(cx-1.8,h+2.7,3.6)],.095)
        tube(m,[(cx+1.8,h+2.7,3.6),(cx+4.65,h+2.7,3.6)],.095)
    m.part('L2K Tower Front Landing',(3,4.3,-8),(16,.4,4),'Terrazzo',ground=True,show=False)
    m.part('L2K Tower Right Access',(8,4.3,-1),(6,.4,10),'Terrazzo',ground=True,show=False)
    # Three six-wide switchback flights. Landings start AFTER the last tread;
    # no high platform slab conceals or blocks the lower flight.
    start=0
    for flight,end in enumerate((4.5,7.5,10.5)):
        count=math.ceil((end-start)/.78); rise=(end-start)/count
        x=-8 if flight%2==0 else 8
        direction=-1 if flight%2==0 else 1
        z0=(4+count*2.3) if direction==-1 else 4
        for i in range(count):
            top=start+(i+1)*rise; z=z0+direction*(i+.5)*2.3
            m.box((x,top-.18,z),(6,.36,2.3),'Terrazzo',bevel=0)
            # Mosaic-free tiled riser closes the front, thick enough to read in silhouette.
            m.box((x,top-rise/2,z-direction*1.12),(6,rise,.06),'Tile',bevel=0)
            m.collider('TowerTread'+str(flight)+'_'+str(i),(x,top-.18,z+direction*.85),
                       (6,.36,4),ground=True)
        profile=[(start-.4,z0),(end-.9,z0+direction*count*2.3)]
        for i in range(count-1,-1,-1):
            top=start+(i+1)*rise-.36
            profile.extend([(top,z0+direction*(i+1)*2.3),(top,z0+direction*i*2.3)])
        prism(m,profile,x-2.9,x+2.9,'Tile')
        zend=z0+direction*count*2.3
        if direction==1:
            m.part('L2K Tower Rear Landing',(0,end-.2,zend+2),
                   (22,.4,4),'Terrazzo',ground=True,show=False)
            m.part('L2K Tower Centre Access',(0,end-.2,(4+zend)/2),
                   (4,.4,zend-4),'Terrazzo',ground=True,show=False)
            m.part('L2K Tower Rear Support',(0,end/2-.2,zend+2),
                   (2,end-.4,2),'Tile',show=False)
        for side in (-1,1):
            tube(m,[(x+side*2.8,start+.5,z0),(x+side*2.8,start+2.5,z0),
                    (x+side*2.8,end+2.5,zend),(x+side*2.8,end+.1,zend)],.095)
        start=end
    m.marker('Deck',(0,0,0));m.marker('DiveEdge',(-10,10.5,-6))
    return done(m,2500)


def build():
    """Register the 32 architecture components; never place or export on import."""
    arch();service()
    for length in (8,16,32,64):coping(length)
    corner()
    for length in (16,32,64):gutter(length)
    for height in (34,42,52):
        for diameter in (4.5,5.5,9):column(diameter,height)
    for size,r,letter in ((36,10,'S'),(44,14,'M'),(52,18,'L')):well(size,r,letter)
    for length in (16,32,64):cove(length)
    ladder();pool_steps();stair(4);stair(8);lamp();glass();tower()
    return {name:kit.COMPONENTS[name] for name in BUDGETS}


def validate():
    rows=[]
    for name,budget in BUDGETS.items():
        info=kit.COMPONENTS[name]; mesh=info['mesh'];mesh.calc_loop_triangles()
        tris=len(mesh.loop_triangles)
        assert tris<=budget,(name,tris,budget)
        assert all(p.area>1e-10 for p in mesh.polygons),name+' zero area'
        assert all(math.isfinite(c) for v in mesh.vertices for c in v.co),name
        assert all(math.isfinite(c) for uv in mesh.uv_layers.active.data for c in uv.uv),name
        assert len(mesh.materials)==len(set(mat.name for mat in mesh.materials)),name
        for rec in info['parts']+info['colliders']+info['markers']:
            assert not any(w in rec['name'] for w in ('Ceiling','Skylight','Roof')),rec
        for rec in info['colliders']:
            if rec['ground']:
                assert rec['size'][0]>=4 and rec['size'][2]>=4,rec
                # Boxes have flat tops: thickness is not a change in ground height.
                assert rec['shape']=='Block',rec
        # Face closure: every edge on each disconnected solid has exactly two users.
        import bmesh
        bm=bmesh.new();bm.from_mesh(mesh)
        assert all(e.is_manifold for e in bm.edges),(name,'non-manifold solid')
        bm.free()
        rows.append({'name':name,'chunks':len(mesh.materials),'tris':tris,'budget':budget,
                     'parts':len(info['parts']),'colliders':len(info['colliders'])})
    print('\nNAME                         CHUNKS  TRIS  BUDGET')
    for r in rows:print(f"{r['name']:28} {r['chunks']:6} {r['tris']:5} {r['budget']:7}")
    return rows


def review_place(col,name,pos=(0,0,0),yaw=0):
    ob=kit.place(col,name,pos,yaw);ob.name=ob.name.replace('Skylight','Light')
    # Flat Part records are deliberately absent from runtime mesh chunks.
    for i,rec in enumerate(kit.COMPONENTS[name]['parts']):
        if rec.get('_drawn'):continue
        tmp=kit.Mesh('ReviewPart');tmp.box(rec['cf'][:3],rec['size'],rec['material'],bevel=0,
            rotation=Matrix.Rotation(-math.radians(rec['cf'][3]),4,'Z'))
        tmp.finish();me=kit.COMPONENTS.pop('ReviewPart')['mesh']
        po=bpy.data.objects.new(rec['name'],me);col.objects.link(po);po.matrix_world=ob.matrix_world
    return ob


def collection(name):
    col=bpy.data.collections.new(name);bpy.context.scene.collection.children.link(col);return col


def look(ob,point):
    ob.rotation_euler=(kit.to_blender(point)-ob.location).to_track_quat('-Z','Y').to_euler()


def text(col,string,pos,size=.85):
    cu=bpy.data.curves.new('Label','FONT');cu.body=string;cu.size=size*S;cu.align_x='CENTER'
    ob=bpy.data.objects.new('Label',cu);col.objects.link(ob);ob.location=kit.to_blender(pos)
    # Stand upright facing the -Z review camera.
    ob.rotation_euler=(math.pi/2,0,0)
    mat=bpy.data.materials.get('Review ink')
    if not mat:
        mat=bpy.data.materials.new('Review ink');mat.use_nodes=True
        bs=mat.node_tree.nodes['Principled BSDF'];bs.inputs['Base Color'].default_value=(.008,.016,.018,1)
    cu.materials.append(mat)


def stage(col):
    # Review-only surface, never registered or exported.
    bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.18))
    ob=bpy.context.object;ob.name='Review ground'
    for c in list(ob.users_collection):c.objects.unlink(ob)
    col.objects.link(ob)
    mat=bpy.data.materials.get('Review ground')
    if not mat:
        mat=bpy.data.materials.new('Review ground');mat.use_nodes=True
        bs=mat.node_tree.nodes['Principled BSDF'];bs.inputs['Base Color'].default_value=(.14,.19,.19,1)
        bs.inputs['Roughness'].default_value=.85
    ob.data.materials.append(mat)


def render(col,filename,eye,target,ortho=None,res=(1600,1100)):
    sc=bpy.context.scene
    for c in sc.collection.children:c.hide_render=c!=col
    cam=bpy.data.objects.new('Review Camera',bpy.data.cameras.new('Review Camera'));col.objects.link(cam)
    cam.location=kit.to_blender(eye);look(cam,target);cam.data.clip_end=500
    if ortho:cam.data.type='ORTHO';cam.data.ortho_scale=ortho*S
    else:cam.data.lens=24
    sc.camera=cam
    for ob in col.objects:
        if ob.type=='FONT':
            ob.rotation_euler=(cam.location-ob.location).to_track_quat('Z','Y').to_euler()
    sun=bpy.data.objects.new('Review Sun',bpy.data.lights.new('Review Sun','SUN'));col.objects.link(sun)
    sun.data.energy=2.2;sun.data.angle=.15;sun.rotation_euler=(.45,-.45,-.6)
    for pos,energy,size in [((-25,40,-35),2800,15),((30,55,15),3500,18)]:
        light=bpy.data.objects.new('Review Softbox',bpy.data.lights.new('Review Softbox','AREA'))
        col.objects.link(light);light.location=kit.to_blender(pos);light.data.energy=energy;light.data.shape='DISK'
        light.data.size=size*S;look(light,target)
    if filename=='06_assembled.png':
        for pos,energy,size,aim in [((0,28,-18),850,12,(0,15,0)),
                                  ((0,48,-4),2400,10,(0,0,-4)),
                                  ((0,30,14),250,6,(0,0,14))]:
            light=bpy.data.objects.new('Review Interior Fill',bpy.data.lights.new('Review Interior Fill','AREA'))
            col.objects.link(light);light.location=kit.to_blender(pos)
            light.data.energy=energy;light.data.size=size*S;look(light,aim)
    if not sc.world:sc.world=bpy.data.worlds.new('Review daylight')
    sc.world.use_nodes=True;sc.world.node_tree.nodes['Background'].inputs[0].default_value=(.38,.48,.6,1)
    sc.world.node_tree.nodes['Background'].inputs[1].default_value=.5
    sc.render.engine='BLENDER_EEVEE';sc.render.resolution_x,sc.render.resolution_y=res
    sc.render.resolution_percentage=100;sc.render.image_settings.file_format='PNG'
    sc.view_settings.view_transform='AgX';sc.render.filepath=str(REVIEW/filename)
    bpy.ops.render.render(write_still=True)


def edge_detail():
    col=collection('A bullnose and grate detail');stage(col)
    review_place(col,'Coping16',(0,2.5,0))
    review_place(col,'Gutter16',(0,2.5,1.5))
    review_place(col,'Ladder',(4,2.5,0))
    review_place(col,'CopingCorner',(-12,2.5,0))
    text(col,'Bullnose + overflow',(-1,.3,-7),size=.65)
    text(col,'Outside corner',(-12,1.1,-4),size=.5)
    render(col,'07_edge_detail.png',(22,15,-27),(-2,2,0),ortho=31,res=(1600,1000))


def contact_sheets():
    col=collection('A portals and access');stage(col)
    for name,pos in [('DoorArch30',(-24,0,10)),('DoorService12',(11,0,10)),
                     ('GlassBlockPanel8',(31,0,10)),('StairFlight4',(-23,0,-18)),
                     ('StairFlight8',(0,0,-18)),('PoolSteps',(23,1.2,-11))]:
        review_place(col,name,pos)
        label=(pos[0],.3,pos[2]-4)
        if name=='DoorArch30':label=(pos[0],7,pos[2]-4)
        if name=='PoolSteps':label=(pos[0],.2,pos[2]-11)
        text(col,name,label,size=1)
    render(col,'01_portals_steps.png',(63,53,-93),(0,14,0),ortho=99)
    col=collection('A pool edges');stage(col)
    for i,length in enumerate((8,16,32,64)):
        p=(0,1,18-i*8);review_place(col,'Coping'+str(length),p)
        text(col,'Coping'+str(length),(length/2+8,1,p[2]))
    for i,length in enumerate((16,32,64)):
        p=(0,1,-22-i*8);review_place(col,'Gutter'+str(length),p)
        text(col,'Gutter'+str(length),(length/2+8,1,p[2]))
    review_place(col,'CopingCorner',(-36,1,-2));text(col,'CopingCorner',(-35,1,-7))
    review_place(col,'Ladder',(-35,4,-27));text(col,'Ladder',(-35,1,-34))
    render(col,'02_pool_edges.png',(30,68,-95),(2,0,-12),ortho=105)
    col=collection('A columns');stage(col)
    for row,h in enumerate((34,42,52)):
        for i,d in enumerate((4.5,5.5,9)):
            name='Column'+str(d).replace('.','_')+'_H'+str(h)
            x=(row*3+i-4)*12;review_place(col,name,(x,0,0))
            text(col,name,(x+3,.2,-9),size=.8)
    render(col,'03_columns.png',(72,62,-160),(0,24,0),ortho=130)
    col=collection('A overhead details');stage(col)
    for name,x,width in [('SkylightWellS',-53,36),('SkylightWellM',-7,44),('SkylightWellL',45,52)]:
        review_place(col,name,(x,4,13));text(col,name,(x,.2,13-width/2-5),size=1.1)
    for i,length in enumerate((16,32,64)):
        review_place(col,'Cove'+str(length),(0,3,-20-i*7));text(col,'Cove'+str(length),(length/2+8,1,-20-i*7))
    lp=review_place(col,'LampPanel',(-45,2,-30))
    lp.rotation_euler=(math.pi,0,0)
    text(col,'LampPanel underside',(-45,.2,-35))
    render(col,'04_overhead.png',(78,99,-125),(0,2,0),ortho=165)
    col=collection('A diving tower');stage(col);review_place(col,'DivingTower')
    text(col,'DivingTower',(0,.2,-9),size=1.2)
    render(col,'05_diving_tower.png',(34,30,-48),(-3,5,3),ortho=52,res=(1400,1200))


def assembled():
    col=collection('A assembled review')
    m=kit.Mesh('AssemblyOnly')
    # Shell: exact rectangular 30x30 opening, 60-wide wall, y=34 top.
    for x in (-22.5,22.5):
        m.part('Level 2 Wall Tile',(x,17,0),(15,34,3.5),'Tile',show=False)
        m.part('Level 2 Dado',(x,1.5,-1.8),(15,3,.1),'TileTeal',show=False)
    m.part('Level 2 Lintel',(0,33.75,0),(30,.5,3.5),'Tile',show=False)
    m.collider('L2K Portal Header Collision',(0,32,0),(30,4,3.5))
    for i,mat in enumerate(('BandCoral','BandYellow','BandBlue')):
        for x in (-24,24):m.part('Level 2 Colour Strip',(x,31.2+i*.8,-1.82),(12,.6,.12),mat,show=False)
    # Revealed rear gallery seals the view beyond the portal.
    m.part('Level 2 Rear Wall',(0,17,24),(60,34,1),'Tile',show=False)
    m.part('Level 2 Rear Dado',(0,1.5,23.45),(60,3,.1),'TileTeal',show=False)
    for x in (-30,30):m.part('Level 2 Return Wall',(x,17,-3),(1,34,54),'Tile',show=False)
    m.part('Level 2 Deck',(0,-.4,-5),(60,.8,10),'Terrazzo',ground=True,show=False)
    m.part('Level 2 Gallery Deck',(0,-.4,12),(60,.8,24),'Terrazzo',ground=True,show=False)
    m.part('Level 2 Basin Floor',(0,-2.8,-22),(60,.6,24),'Mosaic',ground=True,show=False)
    m.part('Level 2 Basin Edge',(0,-1.25,-10),(60,2.5,.5),'Mosaic',show=False)
    for x in (-29.75,29.75):m.part('Level 2 Basin Side',(x,-1.25,-22),(.5,2.5,24),'Mosaic',show=False)
    for x in (-20,-10,0,10,20):m.part('Level 2 Lane Line',(x,-2.485,-22),(.35,.02,24),'Cobalt',collide=False,show=False)
    # Slot-grid overhead Parts leave a 36 square aperture for the S light well.
    m.part('Level 2 Overhead Tile Left',(-24,34.3,-4),(12,.6,60),'Tile',show=False)
    m.part('Level 2 Overhead Tile Right',(24,34.3,-4),(12,.6,60),'Tile',show=False)
    m.part('Level 2 Overhead Tile Front',(0,34.3,-28),(36,.6,12),'Tile',show=False)
    m.part('Level 2 Overhead Tile Back',(0,34.3,20),(36,.6,12),'Tile',show=False)
    m.finish();review_place(col,'AssemblyOnly');kit.COMPONENTS.pop('AssemblyOnly')
    review_place(col,'DoorArch30');review_place(col,'Coping64',(0,0,-10))
    review_place(col,'Gutter64',(0,0,-8.5));review_place(col,'Column5_5_H34',(-22,0,-4))
    review_place(col,'Column4_5_H34',(23,0,12));review_place(col,'SkylightWellS',(0,34,-4))
    review_place(col,'Ladder',(20,0,-10));review_place(col,'PoolSteps',(-18,0,-10))
    review_place(col,'LampPanel',(0,33.5,12))
    # Review-only water-coloured glass; runtime water is exclusively Terrain.
    bpy.ops.mesh.primitive_plane_add(size=2,location=kit.to_blender((0,-.65,-22)))
    water=bpy.context.object;water.name='Review water glass';water.scale=(30*S,12*S,1)
    for c in list(water.users_collection):c.objects.unlink(water)
    col.objects.link(water)
    mat=bpy.data.materials.new('Review water');mat.use_nodes=True
    bs=mat.node_tree.nodes['Principled BSDF'];bs.inputs['Base Color'].default_value=(.025,.32,.39,1)
    bs.inputs['Roughness'].default_value=.17;bs.inputs['Transmission Weight'].default_value=.55
    bs.inputs['IOR'].default_value=1.333;bs.inputs['Alpha'].default_value=.62
    if hasattr(mat,'surface_render_method'):mat.surface_render_method='DITHERED'
    water.data.materials.append(mat)
    render(col,'06_assembled.png',(14,12,-52),(0,17,0),res=(1800,1400))


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--export-only',action='store_true')
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    bpy.ops.wm.read_factory_settings(use_empty=True)
    build();rows=validate();kit.EXPORT_DIR=OUT
    manifest=kit.export()
    assert len(manifest['components'])==32 and len(manifest['chunks'])==59
    for name in BUDGETS:
        chunks=[c for c in manifest['chunks'] if c['component']==name]
        assert sum(c['tris'] for c in chunks)<=BUDGETS[name]
        assert len({c['material'] for c in chunks})==len(chunks)
        assert sum(c['material']=='Bands' for c in chunks)<=1
    import hashlib,base64,struct
    for rec in manifest['chunks']:
        wire=(OUT/'chunks'/('c%05d.b64'%rec['id'])).read_text(encoding='ascii')
        blob=base64.b64decode(wire,validate=True)
        assert hashlib.sha256(blob).hexdigest()==rec['sha256']
        nv,nn,nu,nt=struct.unpack('<4I',blob[:16])
        assert nt==rec['tris']
        assert len(blob)==16+nv*12+nn*12+nu*8+nt*36
        if rec['material']=='Bands':
            offset=16+nv*12+nn*12
            values=struct.unpack('<%df'%(nu*2),blob[offset:offset+nu*8])
            assert min(values[1::2])>=-.00001 and max(values[1::2])<=1.00001
    OUT.mkdir(parents=True,exist_ok=True)
    (OUT/'architecture_checks.json').write_text(json.dumps({'components':rows,
        'verified':['Triangle budgets','Closed manifold mesh solids','No zero-area faces',
                    'Finite vertices and UVs','One material per chunk','One Bands chunk per module',
                    'Bands wire V in 0..1','Wire lengths, triangle headers and SHA256',
                    'Collider/marker naming','Ground collider footprint >=4 studs'],
        'notes':['Registry SkylightWell IDs retained; all instance and mesh names use LightWell.',
                 'Flat Part records exported without duplicate mesh geometry (show=False).',
                 'Vertical cylinder orientation metadata requires importer support.',
                 'Stair ground boxes extend uphill to four studs; .78 nominal rise, exact endpoint.',
                 'Final stair collider extension has a visible 1.7-stud upper landing Part.',
                 'Alternate diving decks offset laterally to avoid 2.5-stud clearances.',
                 'Wells include the explicitly requested Steel rim: three chunks rather than table two.',
                 'Stair flights include explicitly requested Tile cheeks: two chunks rather than table one.',
                 'GlassBlockPanel8 and CopingCorner budgets absent from spec: conservative 600 adopted.']},indent=2))
    if not args.export_only:
        REVIEW.mkdir(parents=True,exist_ok=True);contact_sheets();assembled();edge_detail()
    print('ARCHITECTURE_OK',len(rows),sum(r['tris'] for r in rows),flush=True)


if __name__=='__main__':main()
