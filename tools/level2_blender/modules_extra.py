"""V1 Leisure Centre 1989 set pieces. Run only in independent headless Blender.

D:/Blender/blender.exe -b --factory-startup --python-exit-code 1 -P G:/Roblox/MongoTV/tools/level2_blender/modules_extra.py
"""
import sys
sys.dont_write_bytecode = True
import math
from pathlib import Path
import bpy
from mathutils import Vector
sys.path.insert(0, str(Path(__file__).parent))
import kit

OUT = Path('G:/Blender/Level2_Pool/review/V1')
EXPORT = Path('G:/Blender/Level2_Pool/jobs/V1/export')
BUDGETS = {}


def finish(m, limit):
    m.finish()
    mesh = kit.COMPONENTS[m.name]['mesh']
    mesh.calc_loop_triangles()
    count = len(mesh.loop_triangles)
    assert count <= limit, (m.name, count, limit)
    BUDGETS[m.name] = (count, limit)
    return m


def band_uv(bottom, height, along='x'):
    # Blender coordinates are metres; kit divides by Bands.tile_m (1 metre).
    return lambda co, normal: (co.x if along == 'x' else -co.y,
                               (co.z / kit.S - bottom) / height)


def tube(m, path, radius=.095, mat='Steel', sides=6):
    pts = [Vector(p) for p in path]
    if len(pts) < 2:
        return
    vertices = []
    for i, p in enumerate(pts):
        tangent = (pts[min(i+1, len(pts)-1)] - pts[max(i-1, 0)]).normalized()
        reference = Vector((1, 0, 0)) if abs(tangent.x) < .85 else Vector((0, 0, 1))
        a = tangent.cross(reference).normalized()
        b = tangent.cross(a).normalized()
        for j in range(sides):
            q = p + radius * (a*math.cos(j*math.tau/sides) + b*math.sin(j*math.tau/sides))
            vertices.append(tuple(q))
    faces = [(i*sides+j, i*sides+(j+1)%sides,
              (i+1)*sides+(j+1)%sides, (i+1)*sides+j)
             for i in range(len(pts)-1) for j in range(sides)]
    faces += [tuple(range(sides-1, -1, -1)),
              tuple((len(pts)-1)*sides+j for j in range(sides))]
    m.raw(vertices, faces, mat, smooth=True)


def rail(m, x0, x1, y, z, high=3):
    for x in (x0, x1):
        tube(m, [(x, y, z), (x, y+high, z)])
    tube(m, [(x0, y+high, z), (x1, y+high, z)])
    tube(m, [(x0, y+high*.5, z), (x1, y+high*.5, z)], .07)


def tread(m, label, x, y, z, width, depth, mat='Terrazzo'):
    m.box((x, y-.19, z), (width, .38, depth), mat, bevel=.06)
    m.collider(label, (x, y-.19, z), (width, .38, depth), ground=True)


def tower(height):
    levels = (8, 14) if height == 42 else (8, 14, 20)
    m = kit.Mesh(f'DivingPlatform_H{height}', PlatformHeights=list(levels),
                 Footprint=[20, 20], WaterOverhang=10)
    # Tiled twin piers and a cross brace retain a clear stair well.
    for x in (-8.6, 8.6):
        m.box((x, height*.37, 8.5), (1.8, height*.74, 3), 'Tile', bevel=.09)
        m.collider('L2K Tower Pier', (x, height*.37, 8.5), (1.8, height*.74, 3))
    for index, h in enumerate(levels):
        # Broad cantilever slab: diving edge at z=-10, stair access at z=+11.
        m.box((0, h-.42, .5), (20, .84, 21), 'Tile', bevel=.09)
        m.box((0, h+.045, .5), (20, .09, 21), 'Terrazzo', bevel=.035)
        m.box((0, h-.64, -9.94), (20, .75, .15), 'Bands', bevel=0,
              uv=band_uv(h-1.015, .75))
        m.collider(f'L2K Tower Platform {index+1}', (0, h-.22, .5),
                   (20, .44, 21), ground=True)
        # No barrier at z=-10: that is the diving edge.
        for x in (-9.6, 9.6):
            tube(m, [(x,h,-9.9),(x,h+3,-9.9),(x,h+3,10.3),(x,h,10.3)])
            tube(m, [(x,h+1.5,-9.9),(x,h+1.5,10.3)], .065)
            m.collider(f'L2K Tower Side Guard {index} {x}',
                       (x,h+1.5,.2), (.35,3,20.2))
        rail(m, -9.6, 9.6, h, 10.3)
        m.collider(f'L2K Tower Rear Guard {index}', (0,h+1.5,10.3),
                   (19.2,3,.35))
        # Cantilever brackets, visibly thick below the platform.
        for x in (-6.7,6.7):
            tube(m, [(x,h-3,8.6),(x,h-.8,-6.5)], .34, 'Tile', 8)
    previous = 0
    for flight, target in enumerate(levels):
        steps = int(target-previous)
        x = -4.8 if flight % 2 == 0 else 4.8
        direction = -1 if flight % 2 == 0 else 1
        start_z = 18 if flight == 0 else (10 if direction < 0 else -2)
        span = 16 if steps == 8 else 12
        pitch = span/steps
        for i in range(steps):
            y = previous+i+1
            z = start_z + direction*(i+.5)*pitch
            tread(m, f'L2K Tower Tread {flight}-{i}', x, y, z, 5, pitch)
            m.box((x,y-.55,z-direction*(pitch/2-.04)),
                  (5,.9,.09), 'Tile', bevel=0)
        end_z = start_z + direction*span
        for side in (-1, 1):
            xx = x+side*2.45
            tube(m, [(xx,previous+2.5,start_z),
                     (xx,target+2.5,end_z)], .09)
            for i in (0, steps//2, steps):
                yy = previous+i
                zz = start_z+direction*i*pitch
                tube(m, [(xx,yy,zz),(xx,yy+2.5,zz)], .065)
            m.collider(f'L2K Tower Stair Guard {flight} {side}',
                       (xx,(previous+target)/2+1.2,(start_z+end_z)/2),
                       (.25,target-previous+2.5,span))
        previous = target
    m.marker('DiveEdge', (0,levels[-1],-10))
    return finish(m, 3500)


def springboard(long):
    name = 'Springboard3' if long else 'Springboard1'
    h = 8.5 if long else 3
    m = kit.Mesh(name, BoardTipY=h, WaterSide='-Z')
    m.box((0,h-.26,-3.6),(2.8,.3,10.8),'SteelTeal' if long else 'BandCoral',bevel=.13)
    m.box((0,h-.42,-3.6),(2.4,.10,9.8),'Steel',bevel=.025)
    m.collider('L2K Springboard Walk', (0,h-.24,-3.6),(2.8,.36,10.8),ground=True)
    for x in (-.9,.9):
        tube(m,[(x,.15,1.2),(x,h-1.1,1.2),(x,h-.5,-1)],.14,'Steel',8)
    m.box((0,.15,1.2),(4,.3,3),'ServiceGrey',bevel=.06)
    if long:
        for x in (-1.5,1.5):
            tube(m,[(x,0,2),(x,h+1,2),(x,h+1,-.7)],.11,'Steel',8)
        for y in (1.5,3,4.5,6,7.5):
            tube(m,[(-1.5,y,2),(1.5,y,2)],.09,'Steel',6)
        m.collider('L2K Springboard Ladder', (0,h/2,2),(3.3,h,1))
    return finish(m, 650)


def terrace(width):
    m = kit.Mesh(f'SpectatorTerrace{width}', Width=width, Tiers=4)
    for i in range(4):
        h = (i+1)*1.5
        z = -4.5+i*3
        m.part(f'L2K Spectator Tier {i+1}', (0,h-.22,z),
               (width,.44,3),'Terrazzo',ground=True)
        if i < 3:
            m.part(f'L2K Spectator Riser {i+1}', (0,h-.75,z+1.47),
                   (width,1.5,.14),'Tile',collide=False)
        else:
            m.box((0,h-.75,z+1.48),(width,1.5,.12),'Bands',bevel=0,
                  uv=band_uv(h-1.5,1.5))
        m.box((0,h-.04,z-1.47),(width,.10,.16),'Terrazzo',bevel=.04)
    for x in (-width/2+1,width/2-1):
        tube(m,[(x,0,-6),(x,3,-6)],.12)
    rail(m,-width/2+1,width/2-1,0,-6)
    m.collider('L2K Spectator Front Guard',(0,1.5,-6),(width-2,3,.3))
    return finish(m, 650)


def arch_panel(m, z, y0, width, rise, mat, front=True):
    # Thin closed semicircular field behind the tile frame.
    r = width/2
    perimeter = [(-r,y0), (r,y0), (r,y0+rise)]
    perimeter += [(r*math.cos(a),y0+rise+r*math.sin(a))
                  for a in [math.pi*i/16 for i in range(1,17)]]
    n=len(perimeter)
    vertices = [(x,y,zz) for zz in (z,z+.1) for x,y in perimeter]
    faces=[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]
    faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    m.raw(vertices,faces,mat)


def grand_stair():
    m=kit.Mesh('GrandStair24',Width=24,Rise=6,LandingDepth=8)
    for i in range(6):
        h=i+1; z=-9+i*2
        tread(m,f'L2K Grand Tread {i+1}',0,h,z,24,2)
        m.box((0,h-.50,z-.96),(24,.95,.08),'Tile',bevel=0)
    m.part('L2K Grand Landing',(0,5.78,4),(24,.44,8),'Terrazzo',ground=True)
    for x in (-12.35,12.35):
        m.box((x,3,-3),( .55,6,13),'Tile',bevel=.04)
        m.box((x,3.7,-3),(.6,1.4,13),'Bands',bevel=0,
              uv=band_uv(3,1.4, 'z'))
        tube(m,[(x,2,-10),(x,8,0),(x,8,7)],.12)
        m.collider(f'L2K Grand Cheek {x}',(x,3,-3),(.55,6,13))
    # Blind, sealed tiled wall and inset mosaic arch: the silhouette is an opening.
    m.part('L2K Grand Blind Back',(0,11,8.65),(26,22,.8),'Tile')
    arch_panel(m,8.19,6.4,15,5,'Mosaic')
    for x in (-8,8):
        m.box((x,12,8.05),(1,12,.28),'Tile',bevel=.05)
    arc=[(8*math.cos(math.pi-i*math.pi/16),17+8*math.sin(math.pi-i*math.pi/16),8.01)
         for i in range(17)]
    tube(m,arc,.55,'Tile',8)
    for x in (-8,8):
        tube(m,[(x,6.2,8),(x,17,8)],.48,'Tile',8)
    return finish(m, 1200)


def gallery(width):
    m=kit.Mesh(f'GalleryBalcony{width}',Width=width,DeckY=14,Depth=6)
    m.part('L2K Gallery Walk',(0,13.7,0),(width,.6,6),'Terrazzo',ground=True)
    m.box((0,13.2,-3.02),(width,.95,.18),'Bands',bevel=0,
          uv=band_uv(12.725,.95))
    for x in range(-width//2+4,width//2,8):
        m.box((x,11.3,1.1),(1.1,4.8,3.3),'Tile',bevel=.12)
    for x in range(-width//2+2,width//2,8):
        tube(m,[(x,14,-2.85),(x,17.1,-2.85)])
    rail(m,-width/2+2,width/2-2,14,-2.85)
    m.collider('L2K Gallery Front Guard',(0,15.5,-2.85),(width-4,3,.34))
    m.marker('StairJoin',(0,14,2.5))
    return finish(m, 800)


def gallery_stair():
    m=kit.Mesh('GalleryStair',Rise=14,Width=6)
    for i in range(14):
        h=i+1; z=-13+i*2
        tread(m,f'L2K Gallery Tread {i+1}',0,h,z,6,2)
        m.box((0,h-.52,z-.97),(6,.95,.07),'Tile',bevel=0)
    for x in (-3.1,3.1):
        tube(m,[(x,2,-14),(x,16,14)],.11)
        for i in (0,3,6,9,12,14):
            y=i+1; z=-14+i*2
            tube(m,[(x,y,z),(x,y+2,z)],.07)
        m.collider(f'L2K Gallery Stair Guard {x}',(x,8,0),(.3,15,28))
    return finish(m, 1350)


def rib(width):
    m=kit.Mesh(f'OverheadRibs{width}',Span=width,Hang=3)
    m.box((0,-1.45,0),(width,2.9,2),'Tile',bevel=.25)
    m.box((0,-2.98,0),(width,.14,2.14),'TileTeal',bevel=.06)
    for x in range(-width//2+4,width//2,8):
        m.box((x,-3.04,0),(.16,.08,2.17),'Steel',bevel=0)
    return finish(m, 400)


def coffer():
    m=kit.Mesh('OverheadCoffer40',Span=40)
    for x in (-19,19):m.box((x,-1,0),(2,2,40),'Tile',bevel=.14)
    for z in (-19,19):m.box((0,-1,z),(36,2,2),'Tile',bevel=.14)
    for x in (-10,0,10):
        for z in (-10,0,10):
            m.box((x,-.2,z),(9.5,.4,9.5),'Tile',bevel=0)
            m.box((x,-.48,z),(8.4,.08,8.4),'TileTeal',bevel=0)
    return finish(m, 500)


def lane_rope(length):
    m=kit.Mesh(f'LaneRope{length}',Length=length,WaterY=.1)
    tube(m,[(0,.1,-length/2),(0,.1,length/2)],.045,'Steel',5)
    count=length//2
    colours=('BandCoral','BandYellow','BandBlue')
    for i in range(count):
        z=-length/2+1+2*i
        m.cylinder((0,.1,z),.38,.38,colours[(i//3)%3],segments=10,axis='Z')
    return finish(m, 1500 if length==64 else 800)


def gate():
    m=kit.Mesh('GateStory',Width=20,Height=22,Sealed=True)
    for x in (-9.1,9.1):
        m.box((x,11,0),(1.8,22,2.2),'Tile',bevel=.12)
    m.box((0,21.1,0),(20,1.8,2.2),'Tile',bevel=.12)
    for x in (-4.4,4.4):
        m.box((x,9.7,-.22),(8.6,18.8,.8),'SteelTeal',bevel=.05)
        for yy in (2,5,8,11,14,17):
            m.box((x,yy,-.67),(7.8,.055,.05),'Steel',bevel=0)
    m.box((0,10,-.76),(.13,18,.10),'Steel',bevel=.025)
    m.box((0,19.9,-1.19),(12,2,.22),'Steel',bevel=.04)
    for x in (-6,-3,0,3,6):
        m.cylinder((x,22,-1.18),.35,.35,'GateRed',segments=8,axis='Z')
    m.marker('Face',(0,0,-1.5))
    return finish(m, 2000)


def ball(m, x, y, z, radius, mat):
    # 32 triangles: two rounded latitude rings plus poles.
    verts=[(x,y+radius,z),(x,y-radius,z)]
    for yy in (.5,-.5):
        verts += [(x+radius*.866*math.cos(i*math.tau/8),
                   y+radius*yy,z+radius*.866*math.sin(i*math.tau/8))
                  for i in range(8)]
    faces=[]
    for i in range(8):
        a=2+i;b=2+(i+1)%8;c=10+i;d=10+(i+1)%8
        faces.extend(((0,a,b),(a,c,d),(a,d,b),(1,d,c)))
    m.raw(verts,faces,mat)


def ball_bed(name,w,d,pitch):
    m=kit.Mesh(name,Size=[w,d])
    colours=('BallCoral','BallYellow','BallBlue','BallLime')
    nx=max(2,int(w/pitch));nz=max(2,int(d/pitch))
    for j in range(nz):
        for i in range(nx):
            x=-w/2+(i+.5)*w/nx
            z=-d/2+(j+.5)*d/nz
            ball(m,x,.93,z,min(w/nx,d/nz)*.49,colours[(i+j*3)%4])
    return finish(m, 4000 if name.endswith('L') else 3000)


def clutter(kind):
    m=kit.Mesh('PropCluster_'+kind)
    if kind=='Kickboards':
        for i in range(4):
            m.box((0,.10+i*.17,0),(2.1,.13,3.4),('BandCoral','BandYellow','BandBlue')[i%3],bevel=.12)
        m.box((3,.11,-1),(2,.13,3.4),'BandBlue',bevel=.12)
    elif kind=='Towels':
        for i in range(3):
            m.box((i*.35,.16+i*.17,0),(2.5,.19,1.6),('Tile','BandCoral','Tile')[i],bevel=.10)
        for x in (-1.4,1.5):
            m.box((x,.07,-2),( .8,.12,1.8),'SteelTeal',bevel=.17)
    elif kind=='Goggles':
        for x in (-.65,.65):
            m.cylinder((x,.12,0),.55,.20,'BandBlue',segments=8,axis='Y')
        tube(m,[(-1.2,.12,0),(-2,.12,.2),(-2.4,.12,0),(2.4,.12,0)],.06,'Steel')
        m.cylinder((3,.12,0),1.1,.18,'BandCoral',segments=12)
    elif kind=='Cones':
        for x in (-1.4,1.4):
            m.box((x,.07,0),(1.5,.14,1.5),'Steel',bevel=.04)
            m.cylinder((x,.9,0),.6,1.65,'BandCoral',segments=8,radius2=.08)
            m.cylinder((x,1.15,0),.34,.22,'Tile',segments=8,radius2=.25)
    elif kind=='Bucket':
        m.cylinder((0,.65,0),.88,1.3,'BandYellow',segments=10,radius2=1.05)
        m.cylinder((0,1.35,0),1.03,.12,'Steel',segments=10)
        tube(m,[(-.8,1.25,0),(-.5,2.2,0),(.5,2.2,0),(.8,1.25,0)],.07)
        tube(m,[(1.8,.05,0),(2.1,2.8,0)],.10,'Steel')
        m.box((2.1,.18,0),(.85,.32,1.1),'SteelTeal',bevel=.04)
    elif kind=='Noodles':
        for i,mat in enumerate(('BandCoral','BandYellow','BandBlue')):
            tube(m,[(-2+i*.45,.25,-2),(-1.7+i*.45,.27,0),(-2+i*.45,.25,2)],
                 .23,mat,8)
    return finish(m, 600)


def build():
    """Register all V1 set pieces; importing this file does not export or render."""
    for name,rgb in (('BallCoral',(247,105,79)),('BallYellow',(250,212,52)),
                     ('BallBlue',(43,156,221)),('BallLime',(119,217,66))):
        kit.PALETTE[name]=('rubber_kids','L2K Rubber',rgb)
    for h in (42,52):tower(h)
    springboard(False);springboard(True)
    for w in (32,64):terrace(w)
    grand_stair()
    for w in (32,64):gallery(w)
    gallery_stair()
    for w in (48,96):rib(w)
    coffer()
    for length in (32,64):lane_rope(length)
    gate()
    for name,w,d,pitch in (('BallBedS',16,12,2.1),('BallBedM',24,18,2.4),
                           ('BallBedL',34,30,2.8)):
        ball_bed(name,w,d,pitch)
    for name in ('Kickboards','Towels','Goggles','Cones','Bucket','Noodles'):
        clutter(name)
    return {name:kit.COMPONENTS[name] for name in BUDGETS}


def review_box(collection, name, center, size, mat):
    m=kit.Mesh(name)
    m.box(center,size,mat,bevel=0)
    mesh=m.finish(register=False)
    obj=bpy.data.objects.new(name,mesh)
    collection.objects.link(obj)
    return obj


def review_coping(collection, center, size):
    m=kit.Mesh('V1 review bullnose coping')
    m.box(center,size,'Terrazzo',bevel=.17)
    mesh=m.finish(register=False)
    obj=bpy.data.objects.new('V1 review bullnose coping',mesh)
    collection.objects.link(obj)


def preview_water(collection,w,d):
    mesh=bpy.data.meshes.new('V1 render water')
    mesh.from_pydata([kit.to_blender(p) for p in ((-w/2,.10,-d/2),(w/2,.10,-d/2),
                      (w/2,.10,d/2),(-w/2,.10,d/2))],[],[(0,3,2,1)])
    mat=bpy.data.materials.new('V1 render water only');mat.use_nodes=True
    nodes=mat.node_tree.nodes;nodes.clear();links=mat.node_tree.links
    output=nodes.new('ShaderNodeOutputMaterial')
    transparent=nodes.new('ShaderNodeBsdfTransparent')
    shine=nodes.new('ShaderNodeBsdfGlossy')
    shine.inputs['Color'].default_value=(.36,.77,.84,1)
    shine.inputs['Roughness'].default_value=.13
    mix=nodes.new('ShaderNodeMixShader');mix.inputs[0].default_value=.31
    links.new(transparent.outputs[0],mix.inputs[1])
    links.new(shine.outputs[0],mix.inputs[2])
    links.new(mix.outputs[0],output.inputs['Surface'])
    mat.surface_render_method='DITHERED'
    mesh.materials.append(mat)
    obj=bpy.data.objects.new('V1 render-only water surface',mesh)
    collection.objects.link(obj)


def point(collection,name,position,target,power,size=15):
    data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape='DISK';data.size=size
    obj=bpy.data.objects.new(name,data);collection.objects.link(obj)
    obj.location=kit.to_blender(position)
    obj.rotation_euler=(kit.to_blender(target)-obj.location).to_track_quat('-Z','Y').to_euler()


def camera(collection,eye,target,lens):
    obj=bpy.data.objects.new('V1 camera',bpy.data.cameras.new('V1 camera'))
    collection.objects.link(obj)
    obj.location=kit.to_blender(eye)
    obj.rotation_euler=(kit.to_blender(target)-obj.location).to_track_quat('-Z','Y').to_euler()
    obj.data.lens=lens
    bpy.context.scene.camera=obj


def hall_scene():
    c=bpy.data.collections.new('V1 assembled 176 x 144 hall')
    bpy.context.scene.collection.children.link(c)
    # 176 X by 144 Z. Recessed pool is 112 X by 102 Z; no seams to the void.
    for x in (-72,72):review_box(c,'V1 side deck',(x,-.42,0),(32,.84,144),'Terrazzo')
    for z in (-61.5,61.5):review_box(c,'V1 end deck',(0,-.42,z),(112,.84,21),'Terrazzo')
    review_box(c,'V1 pool bottom',(0,-1.95,0),(112,.55,102),'Mosaic')
    for x in (-56,56):review_box(c,'V1 pool wall',(x,-.95,0),(.6,1.9,102),'Mosaic')
    for z in (-51,51):review_box(c,'V1 pool wall',(0,-.95,z),(112,1.9,.6),'Mosaic')
    for x in (-56,56):review_coping(c,(x,.08,0),(1.2,.42,103))
    for z in (-51,51):review_coping(c,(0,.08,z),(111,.42,1.2))
    for x in (-34,-17,0,17,34):
        review_box(c,'V1 cobalt lane',(x,-1.65,0),(.65,.035,101),'Cobalt')
    for x in (-87.3,87.3):
        review_box(c,'V1 hall wall',(x,26,0),(1.4,52,144),'Tile')
        review_box(c,'V1 dado',(x-math.copysign(.8,x),2,0),(.12,4,144),'TileTeal')
        for h,mat in ((17,'BandCoral'),(18.1,'BandYellow'),(19.2,'BandBlue')):
            review_box(c,'V1 wall band',(x-math.copysign(.82,x),h,0),(.13,.7,144),mat)
        for z in (-45,0,45):
            review_box(c,'V1 glass panel',(x-math.copysign(.85,x),34,z),(.12,16,12),'GlassBlock')
    for z in (-71.3,71.3):
        review_box(c,'V1 end wall',(0,26,z),(176,52,1.4),'Tile')
        for h,mat in ((17,'BandCoral'),(18.1,'BandYellow'),(19.2,'BandBlue')):
            review_box(c,'V1 end band',(0,h,z-math.copysign(.82,z)),(176,.7,.13),mat)
    # Repeated blind arches below the gallery recall the original side aisles.
    for z in (-46,-21,6,31,56):
        alcove=kit.Mesh('V1 review arcade')
        arch_panel(alcove,-.12,0,11,5,'TileTeal')
        arc=[(5.6*math.cos(math.pi-i*math.pi/12),5+5.6*math.sin(math.pi-i*math.pi/12),-.25)
             for i in range(13)]
        for x in (-5.6,5.6):tube(alcove,[(x,0,-.25),(x,5,-.25)],.35,'Tile',6)
        tube(alcove,arc,.35,'Tile',6)
        mesh=alcove.finish(register=False)
        obj=bpy.data.objects.new('V1 review arcade',mesh);c.objects.link(obj)
        obj.matrix_world=__import__('mathutils').Matrix.Rotation(-math.pi/2,4,'Z')
        obj.location=kit.to_blender((86.35,0,z))
    for x in (-37,37):
        alcove=kit.Mesh('V1 far arcade')
        arch_panel(alcove,-.14,1,13,6,'TileTeal')
        arc=[(6.7*math.cos(math.pi-i*math.pi/12),7+6.7*math.sin(math.pi-i*math.pi/12),-.25)
             for i in range(13)]
        for xx in (-6.7,6.7):tube(alcove,[(xx,1,-.25),(xx,7,-.25)],.42,'Tile',6)
        tube(alcove,arc,.42,'Tile',6)
        mesh=alcove.finish(register=False)
        obj=bpy.data.objects.new('V1 far arcade',mesh);c.objects.link(obj)
        obj.location=kit.to_blender((x,0,70.35))
    for x in (-68,68):
        for z in (-46,46):
            review_box(c,'V1 column',(x,26,z),(4,52,4),'Tile')
            for h,mat in ((13,'BandCoral'),(14,'BandYellow'),(15,'BandBlue')):
                review_box(c,'V1 column band',(x,h,z),(4.1,.6,4.1),mat)
    # A few overhead strips create skylight slots and let daylight reach the pool.
    for x in (-72,-32,32,72):
        review_box(c,'V1 overhead tile',(x,52,0),(32,.5,144),'Tile')
    for z in (-57,-20,20,57):
        review_box(c,'V1 overhead tile',(0,52,z),(48,.5,25),'Tile')
    for z in (-38,0,38):kit.place(c,'OverheadRibs96',(0,51,z))
    kit.place(c,'OverheadRibs48',(-64,51,0),90)
    kit.place(c,'OverheadRibs48',(64,51,0),90)
    kit.place(c,'DivingPlatform_H52',(0,0,52))
    kit.place(c,'Springboard1',(-28,0,50))
    kit.place(c,'Springboard3',(28,0,50))
    kit.place(c,'GrandStair24',(0,0,-61),180)
    for z in (-32,32):kit.place(c,'GalleryBalcony64',(84,0,z),90)
    kit.place(c,'GalleryStair',(76,0,-17),90)
    kit.place(c,'SpectatorTerrace64',(-72,0,0),-90)
    for x in (-25,0,25):kit.place(c,'LaneRope64',(x,0,0))
    for x,z,name in ((-71,-55,'Kickboards'),(70,-53,'Towels'),
                     (-70,49,'Cones'),(71,43,'Bucket'),(-70,-16,'Noodles'),
                     (69,21,'Goggles')):
        kit.place(c,'PropCluster_'+name,(x,0,z))
    preview_water(c,111,101)
    point(c,'V1 day A',(-48,75,-25),(0,0,15),5200,28)
    point(c,'V1 day B',(46,75,26),(0,0,0),4800,28)
    point(c,'V1 warm end',(0,30,-66),(0,2,-20),1000,20)
    for x in (-45,45):
        for z in (-40,40):
            point(c,'V1 skylight daylight',(x,55,z),(x,0,z),500,18)
    sun=bpy.data.lights.new('V1 sun','SUN');sun.energy=2.0;sun.angle=math.radians(8)
    so=bpy.data.objects.new('V1 sun',sun);c.objects.link(so)
    so.rotation_euler=(math.radians(35),math.radians(-22),math.radians(20))
    return c


def render(path,eye,target,lens=22,hide=None):
    scene=bpy.context.scene
    if hide:
        for ob in hide:ob.hide_render=True
    camera(scene.collection.children[0],eye,target,lens)
    scene.render.filepath=str(path)
    bpy.ops.render.render(write_still=True)
    if hide:
        for ob in hide:ob.hide_render=False


def contact_sheet(paths):
    # Blender's own image pixels keep the entire review inside the headless job.
    import numpy as np
    images=[bpy.data.images.load(str(p),check_existing=False) for p in paths]
    w,h=images[0].size
    sheet=bpy.data.images.new('V1 contact sheet',width=w*2,height=h*2,alpha=True)
    pixels=np.zeros((h*2,w*2,4),dtype=np.float32)
    for i,img in enumerate(images):
        data=np.empty(w*h*4,dtype=np.float32)
        img.pixels.foreach_get(data)
        y=(1-i//2)*h;x=(i%2)*w
        pixels[y:y+h,x:x+w,:]=data.reshape(h,w,4)
    sheet.pixels.foreach_set(pixels.ravel())
    sheet.filepath_raw=str(OUT/'_sheet.png')
    sheet.file_format='PNG';sheet.save()


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    build()
    for name,info in kit.COMPONENTS.items():
        mesh=info['mesh']
        assert all(poly.area>1e-10 for poly in mesh.polygons),name
        for rec in info['parts']+info['colliders']+info['markers']:
            assert not any(word in rec['name'] for word in ('Ceiling','Skylight','Roof')),rec
        assert sum(1 for mat in mesh.materials if mat.name=='L2K_Bands')<=1,name
        for poly in mesh.polygons:
            if mesh.materials[poly.material_index].name=='L2K_Bands':
                for loop in poly.loop_indices:
                    v=mesh.uv_layers.active.data[loop].uv.y
                    assert -.0001<=v<=1.0001,(name,v)
        if name.startswith('PropCluster_'):
            assert len(mesh.materials)<=3,(name,len(mesh.materials))
        for rec in info['parts']+info['colliders']:
            if rec.get('ground'):assert rec['size'][0]>=4 or rec['size'][2]>=4,rec
    kit.EXPORT_DIR=EXPORT
    manifest=kit.export()
    for name,(tri,budget) in BUDGETS.items():
        assert tri==sum(c['tris'] for c in manifest['chunks'] if c['component']==name)
        print(f'V1_COMPONENT {name} {tri}/{budget}',flush=True)
    OUT.mkdir(parents=True,exist_ok=True)
    hall_scene()
    sc=bpy.context.scene
    sc.render.engine='BLENDER_EEVEE'
    sc.render.resolution_x=960;sc.render.resolution_y=600
    sc.render.resolution_percentage=100
    sc.render.image_settings.file_format='PNG'
    sc.render.film_transparent=False
    sc.render.threads_mode='FIXED';sc.render.threads=8
    sc.world=bpy.data.worlds.new('V1 daylight ambience')
    sc.world.use_nodes=True
    sc.world.node_tree.nodes['Background'].inputs['Color'].default_value=(.48,.68,.86,1)
    sc.world.node_tree.nodes['Background'].inputs['Strength'].default_value=.22
    sc.view_settings.view_transform='AgX'
    sc.view_settings.look='AgX - Medium High Contrast'
    shots=[('01_assembled.png',(46,17,-58),(0,13,42),25),
           ('02_tower.png',(35,15,3),(0,11,50),26),
           ('03_grand_stair.png',(-22,9,-18),(0,7,-65),27),
           ('04_gallery.png',(2,13,-4),(80,14,9),27)]
    paths=[]
    for name,eye,target,lens in shots:
        path=OUT/name
        render(path,eye,target,lens)
        paths.append(path)
    contact_sheet(paths)
    print('V1_DONE',len(BUDGETS),str(OUT/'_sheet.png'),flush=True)


if __name__=='__main__':
    main()
