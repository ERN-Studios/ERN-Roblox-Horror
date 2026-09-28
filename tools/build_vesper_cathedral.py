"""Build original modular Vesper Cathedral. Run inside Blender 5.x.

Geometry is authored in a compact design grid, converted at 3 studs per grid unit.
No existing scene is deleted or modified. The new scene is self-contained.
"""
import bpy, bmesh, math, json, random
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1] / 'assets/maps/vesper-cathedral'
ROOT.mkdir(parents=True, exist_ok=True)
S = 3.0
SEED = 928
random.seed(SEED)
BUILDERS, COLLIDERS, LIGHTS = {}, [], []
SCENE_NAME = 'Vesper Cathedral'
if bpy.data.scenes.get(SCENE_NAME):
    raise RuntimeError('Vesper Cathedral already exists; use a fresh scene for a rebuild.')
scene = bpy.data.scenes.new(SCENE_NAME)
bpy.context.window.scene = scene
scene.unit_settings.system = 'NONE'
scene.unit_settings.scale_length = 1.0
architecture = bpy.data.collections.new('VESPER | Import Geometry')
scene.collection.children.link(architecture)
presentation = bpy.data.collections.new('VESPER | Preview Cameras and Lights')
scene.collection.children.link(presentation)

class Builder:
    def __init__(self, name, glass=False):
        self.name, self.glass = name, glass
        self.v, self.f, self.tiles = [], [], []
    def add(self, verts, faces, tile):
        n=len(self.v)
        self.v.extend(tuple(float(c)*S for c in p) for p in verts)
        self.f.extend(tuple(n+i for i in face) for face in faces)
        self.tiles.extend([tile]*len(faces))

def group(name, glass=False):
    if name not in BUILDERS: BUILDERS[name]=Builder(name,glass)
    return BUILDERS[name]

def collider(name, center, size, rotation=(0,0,0)):
    COLLIDERS.append(dict(name=name,position=[center[0]*S,center[2]*S,-center[1]*S],
                          size=[size[0]*S,size[2]*S,size[1]*S],rotation=list(rotation)))

def box(g, c, d, tile=0, solid=False):
    if min(d)<=0:return
    x,y,z=c; a,b,h=[v/2 for v in d]
    v=[(x-a,y-b,z-h),(x+a,y-b,z-h),(x+a,y+b,z-h),(x-a,y+b,z-h),
       (x-a,y-b,z+h),(x+a,y-b,z+h),(x+a,y+b,z+h),(x-a,y+b,z+h)]
    g.add(v,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],tile)
    if solid: collider(g.name+'_solid',c,d)

def prism(g, polygon, fixed, depth, axis='X', tile=0):
    # Extrude closed 2D polygon in u/z; bmesh resolves outward normals later.
    def p(u,z,d): return (u,d,z) if axis=='X' else (d,u,z)
    n=len(polygon)
    v=[p(u,z,fixed-depth/2) for u,z in polygon]+[p(u,z,fixed+depth/2) for u,z in polygon]
    faces=[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]
    faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    g.add(v,faces,tile)

def cylinder(g,c,r,h,tile=0,n=12,r2=None):
    if r2 is None:r2=r
    x,y,z=c
    v=[(x+math.cos(i*2*math.pi/n)*rr,y+math.sin(i*2*math.pi/n)*rr,zz)
       for rr,zz in [(r,z-h/2),(r2,z+h/2)] for i in range(n)]
    f=[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]
    f += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    g.add(v,f,tile)

def beam(g,a,b,r,tile=1,n=8):
    a,b=Vector(a),Vector(b); axis=(b-a).normalized()
    up=Vector((0,0,1)) if abs(axis.z)<.95 else Vector((1,0,0))
    u=axis.cross(up).normalized()*r;v=axis.cross(u).normalized()*r
    verts=[tuple(p+u*math.cos(i*2*math.pi/n)+v*math.sin(i*2*math.pi/n)) for p in (a,b) for i in range(n)]
    faces=[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    g.add(verts,faces,tile)

def arch_points(w,spring,steps=12):
    left=[(w/2+w*math.cos(math.pi-i*math.pi/(3*steps)),spring+w*math.sin(math.pi-i*math.pi/(3*steps))) for i in range(steps+1)]
    right=[(-w/2+w*math.cos(math.pi/3-i*math.pi/(3*steps)),spring+w*math.sin(math.pi/3-i*math.pi/(3*steps))) for i in range(1,steps+1)]
    return left+right

def arch(g,u,fixed,w,spring,base=0,t=.25,depth=.5,axis='X',tile=1):
    inner=arch_points(w,spring);outer=arch_points(w+2*t,spring)
    for i in range(len(inner)-1):
        poly=[(u+inner[i][0],inner[i][1]),(u+inner[i+1][0],inner[i+1][1]),
              (u+outer[i+1][0],outer[i+1][1]),(u+outer[i][0],outer[i][1])]
        prism(g,poly,fixed,depth,axis,tile)
    for sign in (-1,1):
        a=u+sign*w/2;b=u+sign*(w/2+t)
        prism(g,[(a,base),(b,base),(b,spring),(a,spring)],fixed,depth,axis,tile)

def wall_window(g,u,fixed,bay,w,base,spring,top,axis='X',tile=0):
    # Complete wall around a real opening, with separate simple wall collision strips.
    depth=.65
    def wallbox(uc,zc,uw,zh,coll=True):
        c=(uc,fixed,zc) if axis=='X' else (fixed,uc,zc)
        d=(uw,depth,zh) if axis=='X' else (depth,uw,zh)
        box(g,c,d,tile,coll)
    wallbox(u,base/2,bay,base)
    for sign in (-1,1):wallbox(u+sign*(bay+w)/4,(top+base)/2,(bay-w)/2,top-base)
    curve=arch_points(w,spring)
    for p,q in zip(curve,curve[1:]):
        prism(g,[(u+p[0],p[1]),(u+q[0],q[1]),(u+q[0],top),(u+p[0],top)],fixed,depth,axis,tile)
    arch(g,u,fixed,w,spring,base,.22,.92,axis,1)

def stained_window(name,u,fixed,w,base,spring,axis='X'):
    g=group(name+'_Glass',True);lead=group(name+'_Tracery')
    outline=[(u-w/2,base)]+[(u+x,z) for x,z in arch_points(w,spring)]+[(u+w/2,base)]
    center=(u,(base+spring)/2+.3)
    colors=[8,9,11,8,10,11,9,8]
    # Radial jewel-like cut glass; closed thin wedges retain color in portable exports.
    for i in range(len(outline)):
        p,q=outline[i],outline[(i+1)%len(outline)]
        prism(g,[center,p,q],fixed,.065,axis,colors[i%len(colors)])
    arch(lead,u,fixed,w,spring,base,.065,.11,axis,12)
    def pt(a,z):return (a,fixed,z) if axis=='X' else (fixed,a,z)
    for off in (-w/6,w/6):beam(lead,pt(u+off,base),pt(u+off,spring+w*.58),.045,12,6)
    for z in (base+(spring-base)*.48,spring):beam(lead,pt(u-w/2,z),pt(u+w/2,z),.04,12,6)
    # Inset miniature lancets form unmistakable Gothic tracery.
    for off in (-w/4,w/4):arch(lead,u+off,fixed,w*.43,spring-.18,base,.045,.1,axis,6)

def rose(name,c,r,fixed):
    x,z=c;stone=group(name+'_Stone');glass=group(name+'_Glass',True);lead=group(name+'_Tracery')
    for rr,th,tile in [(r,.19,1),(r+.27,.10,6),(r*.29,.085,6)]:
        for i in range(48):
            a,b=i*math.tau/48,(i+1)*math.tau/48
            prism(stone,[(x+rr*math.cos(a),z+rr*math.sin(a)),(x+rr*math.cos(b),z+rr*math.sin(b)),
                         (x+(rr+th)*math.cos(b),z+(rr+th)*math.sin(b)),(x+(rr+th)*math.cos(a),z+(rr+th)*math.sin(a))],fixed,.24,'X',tile)
    for i in range(16):
        a,b=i*math.tau/16,(i+1)*math.tau/16
        inner=r*.29;outer=r*.98
        prism(glass,[(x+inner*math.cos(a),z+inner*math.sin(a)),(x+outer*math.cos(a),z+outer*math.sin(a)),
                     (x+outer*math.cos(b),z+outer*math.sin(b)),(x+inner*math.cos(b),z+inner*math.sin(b))],fixed,.08,'X',[8,11,9,10][i%4])
        beam(lead,(x+inner*math.cos(a),fixed,z+inner*math.sin(a)),(x+outer*math.cos(a),fixed,z+outer*math.sin(a)),.045,6,6)
    poly=[(x+r*.26*math.cos(i*math.tau/16),z+r*.26*math.sin(i*math.tau/16)) for i in range(16)]
    prism(glass,poly,fixed,.08,'X',9)

def add_light(name,p,color=(1,.64,.3),energy=140,radius=1,roblox=True):
    data=bpy.data.lights.new(name,'POINT');data.energy=energy*S*S;data.color=color;data.shadow_soft_size=radius*S
    data.use_shadow=name.startswith('Chandelier')
    obj=bpy.data.objects.new(name,data);presentation.objects.link(obj);obj.location=Vector(p)*S
    if roblox:LIGHTS.append(dict(name=name,position=[p[0]*S,p[2]*S,-p[1]*S],color=list(color),range=10*S,brightness=1.1))
    return obj

def build_site():
    g=group('Vesper_01_Foundation')
    box(g,(0,-1,-.52),(36,56,1),15,True)
    box(g,(0,-1,.015),(35.6,55.6,.08),3,True)
    # Long central approach, restrained geometric border, and clipped lawn quadrants.
    for x in (-11.8,11.8):
        for y in (-24.2,23):
            box(g,(x,y,.08),(8.2,6.6,.12),13)
            for dx in (-4.2,4.2):box(g,(x+dx,y,.16),(.15,6.9,.2),1)
            for dy in (-3.45,3.45):box(g,(x,y+dy,.16),(8.55,.15,.2),1)
    for y in (-27,-25,-23):box(g,(0,y,.09),(7, .08,.08),2)
    for x in (-3.6,3.6):box(g,(x,-24,.13),(.15,8,.14),6)
    # Low plinth and gentle broad entrance steps; all risers below one stud.
    box(g,(0,0,.22),(23,41,.42),2,True)
    for i in range(3):box(g,(0,-21.3+i*.45,.11+i*.11),(8-i*.7,2.0-i*.45,.22+i*.22),1,True)

def build_nave():
    floor=group('Vesper_02_InteriorFloor')
    box(floor,(0,0,.47),(21.3,39.9,.14),3,True)
    for x in range(-10,11,2):box(floor,(x,0,.55),(.035,39,.015),2)
    for y in range(-19,20,2):box(floor,(0,y,.55),(21,.035,.015),2)
    box(floor,(0,-2,.58),(4.2,33,.045),7)
    for x in (-2.04,2.04):box(floor,(x,-2,.612),(.075,33,.02),6)
    for y in (-18.1,14.1):box(floor,(0,y,.62),(4.2,.075,.02),6)
    # Five side bays. Windows leave the floor and aisle collision uncomplicated.
    for side in (-1,1):
        for i, y in enumerate((-15.2,-7.6,0,7.6,15.2)):
            g=group(f'Vesper_03_{"West" if side<0 else "East"}_Bay{i+1}')
            wall_window(g,y,side*10.7,7.6,3.9,3.2,7.1,11.4,'Y')
            stained_window(f'Vesper_Window_{side}_{i}',y,side*10.7,3.9,3.2,7.1,'Y')
            for z in (1,2.7,11.15):box(g,(side*10.7,y,z),(1,7.6,.18),1)
        butt=group(f'Vesper_04_Buttresses_{side}')
        for end in (-19.5,19.5):box(butt,(side*10.7,end,5.7),(.65,1,11.4),0,True)
        for y in (-19,-11.4,-3.8,3.8,11.4,19):
            box(butt,(side*11.45,y,3),(1.45,1,5.1),0,True)
            box(butt,(side*11.13,y,7.55),(.92,.8,4.05),0)
            box(butt,(side*11.13,y,9.68),(1.14,1,.24),1)
            cylinder(butt,(side*11.13,y,10.55),.6,1.5,1,4,.08)
        # Nave arcade; columns carry a rhythm of tall transverse arches.
        cols=group(f'Vesper_05_Arcade_{side}')
        for y in (-18,-10.8,-3.6,3.6,10.8,18):
            box(cols,(side*5.65,y,.8),(1.25,1.25,.5),1,True)
            cylinder(cols,(side*5.65,y,4.28),.48,6.5,0,12)
            for dx,dy in ((.42,0),(-.42,0),(0,.42),(0,-.42)):
                cylinder(cols,(side*5.65+dx,y+dy,4.28),.16,6.5,1,8)
            box(cols,(side*5.65,y,7.65),(1.26,1.26,.38),1)
            collider('NaveColumn',(side*5.65,y,4.15),(1.24,1.24,7.2))
        for y in (-14.4,-7.2,0,7.2,14.4):
            arch(cols,y,side*5.65,6.1,7.65,.62,.32,.55,'Y')
            cler=group(f'Vesper_06_Clerestory_{side}_{y}')
            wall_window(cler,y,side*5.65,7.2,2.15,13.4,14.15,16.6,'Y')
            # Remove collision strips below clerestory which would block the arcade.
            for _ in range(3):COLLIDERS.pop()
            # wall_window base extends to ground; replace those lower faces by building in a separate band later.
            # The clipped base mesh is corrected before mesh realization.
            cler.clip_below=12.95*S
            stained_window(f'Vesper_UpperWindow_{side}_{y}',y,side*5.65,2.15,13.4,14.15,'Y')

def build_roofs():
    roof=group('Vesper_07_NaveRoof')
    # Watertight sloping slabs, two sides of a steep ridged roof.
    for side in (-1,1):
        poly=[(0,20.25),(side*6.3,16.45),(side*6.3,16.12),(0,19.92)]
        prism(roof,poly,0,40.4,'X',4)
        beam(roof,(side*6.25,-20.3,16.4),(side*6.25,20.3,16.4),.14,1)
        aisle=group(f'Vesper_08_AisleRoof_{side}')
        poly=[(side*5.6,13.03),(side*11.3,11.65),(side*11.3,11.35),(side*5.6,12.73)]
        prism(aisle,poly,0,39.9,'X',4)
        beam(aisle,(side*11.3,-20.0,11.6),(side*11.3,20.0,11.6),.12,1)
    beam(roof,(0,-20.35,20.27),(0,20.35,20.27),.15,6)
    # Ceiling ribs plus slender ridge bosses show through the playable interior.
    for i,y in enumerate((-18,-10.8,-3.6,3.6,10.8,18)):
        ribs=group(f'Vesper_09_VaultRib{i}')
        arch(ribs,0,y,10.5,10.45,7.5,.19,.26,'X',1)
        for side in (-1,1):
            beam(ribs,(side*5.65,y,7.9),(side*5.65,y,16.3),.13,1)
        cylinder(ribs,(0,y,19.64),.3,.25,6,8)
    # Subtle roof seam geometry, not thousands of individual roof tiles.
    seams=group('Vesper_10_RoofSeams')
    for y in (-18,-12,-6,0,6,12,18):
        for side in (-1,1):beam(seams,(0,y,20.3),(side*6.28,y,16.51),.035,2,5)

def build_ends():
    front=group('Vesper_11_Entrance')
    # Main portal has an open doorway, nested stone archivolts, and open oak doors.
    marker=len(COLLIDERS)
    wall_window(front,0,-20,12.4,5.2,0,4.4,9.35,'X')
    del COLLIDERS[marker:]
    for side in (-1,1):collider('EntranceJamb',(side*4.4,-20,4.7),(3.5,.7,9.4))
    for t in (.45,.75):arch(front,0,-20.2-t*.25,5.2+2*t,4.4,0,.2,.9,'X',1)
    for side in (-1,1):
        door=group(f'Vesper_12_OpenOakDoor_{side}')
        box(door,(side*2.58,-18.45,2.8),(.22,2.85,4.6),5)
        for z in (1.1,2.7,4.6):box(door,(side*2.45,-18.45,z),(.05,2.84,.1),12)
        for yy in (-19.5,-18.8,-18.1,-17.4):box(door,(side*2.43,yy,2.8),(.05,.027,4.6),2)
    # Rose opening in facade: square annulus around a circular cutout.
    cx,cz,r=0,13,2.35
    for i in range(48):
        aa=i*math.tau/48;bb=(i+1)*math.tau/48
        def pts(a):
            co,si=math.cos(a),math.sin(a);k=3.7/max(abs(co),abs(si))
            return (cx+r*co,cz+r*si),(cx+k*co,cz+k*si)
        a,o=pts(aa);b,p=pts(bb)
        prism(front,[a,b,p,o],-20,.65,'X',0)
    for side in (-1,1):box(front,(side*4.95,-20,13),(2.5,.65,7.4),0)
    prism(front,[(-6.2,16.7),(6.2,16.7),(0,20.35)],-20,.7,'X',0)
    rose('Vesper_13_RoseWindow',(0,13),2.35,-20.05)
    for side in (-1,1):beam(front,(side*6.35,-20.4,16.6),(0,-20.4,20.65),.13,1)
    # Altar end wall with three tall windows.
    for i,x in enumerate((-7.5,0,7.5)):
        back=group(f'Vesper_14_SanctuaryWall_{i}')
        w=3.3 if i==1 else 3.0
        spring,top=(10.1,16.65) if i==1 else (7.8,11.4)
        wall_window(back,x,20,7.5,w,4,spring,top,'X')
        stained_window(f'Vesper_SanctuaryGlass_{i}',x,20,w,4,spring,'X')
    g=group('Vesper_15_EastGable')
    for side in (-1,1):box(g,(side*5.025,20,14),(2.55,.7,5.2),0)
    for side in (-1,1):
        prism(g,[(side*6.3,11.35),(side*11.3,11.35),(side*11.3,11.67),(side*6.3,12.88)],20,.7,'X',0)
    prism(g,[(-6.3,15.6),(6.3,15.6),(6.3,16.55),(0,20.3),(-6.3,16.55)],20,.7,'X',0)

def build_towers():
    for side in (-1,1):
        x,y=side*8.8,-18.2;g=group(f'Vesper_16_BellTower_{side}')
        box(g,(x,y,7.25),(4.65,4.9,13.6),0,True)
        for z in (.8,4.4,12.9,14):box(g,(x,y,z),(5.0,5.15,.23),1)
        # Raised long lancet insets on the facade, warm copper belfry aperture.
        for dx in (-1.12,1.12):
            arch(g,x+dx,y-2.54,.75,10.1,7.3,.12,.13,'X',1)
            prism(g,[(x+dx-.375,7.3)]+[(x+dx+a,b) for a,b in arch_points(.75,10.1)]+[(x+dx+.375,7.3)],y-2.47,.07,'X',12)
        for dx in (-1.9,1.9):
            for dy in (-2.05,2.05):
                box(g,(x+dx,y+dy,16),(.55,.55,4.5),1)
        for fixed,axis,u in ((y-2.05,'X',x),(y+2.05,'X',x),(x-1.9,'Y',y),(x+1.9,'Y',y)):
            arch(g,u,fixed,3.15,16.1,14,.21,.43,axis,1)
        box(g,(x,y,18.97),(4.65,4.95,.4),1)
        spire=group(f'Vesper_17_Spire_{side}')
        cylinder(spire,(x,y,22.35),3.05,6.35,4,8,.035)
        for i in range(8):
            a=i*math.tau/8;beam(spire,(x+3.05*math.cos(a),y+3.05*math.sin(a),19.2),(x,y,25.5),.04,6,5)
        for dx in (-2.1,2.1):
            for dy in (-2.1,2.1):
                cylinder(spire,(x+dx,y+dy,19.85),.39,1.75,1,4,.01)
        beam(spire,(x,y,25.35),(x,y,26.5),.055,6)
        beam(spire,(x-.38,y,26.15),(x+.38,y,26.15),.05,6)
        # Bell silhouette within open belfry.
        cylinder(g,(x,y,15.7),.7,1.0,6,16,.36)
        cylinder(g,(x,y,15.16),.78,.15,6,16)

def build_furnishings():
    for side in (-1,1):
        for i,y in enumerate((-13.4,-10.8,-8.2,-5.6,-3,-.4,2.2,4.8,7.4,10)):
            g=group(f'Vesper_18_Pews_{side}_{i//5}')
            x=side*3.55
            box(g,(x,y,1.02),(2.5,.82,.14),5)
            box(g,(x,y-.32,1.55),(2.5,.14,.95),5)
            box(g,(x,y-.33,2.02),(2.65,.18,.12),6)
            for dx in (-1.12,1.12):
                box(g,(x+dx,y,.86),(.18,.7,.61),5)
                box(g,(x+dx,y,1.47),(.18,.85,.17),5)
            collider('Pew',(x,y,1.18),(2.66,.85,1.3))
    altar=group('Vesper_19_Altar')
    for i in range(3):box(altar,(0,16.7,.63+i*.17),(10-i*.55,5.6-i*.45,.2),1,True)
    box(altar,(0,17.3,1.65),(4.7,1.8,1.0),0,True)
    box(altar,(0,17.3,2.2),(5.05,2.05,.22),1)
    box(altar,(0,17.15,2.33),(2.05,2.08,.035),7)
    for x in (-1.8,1.8):
        cylinder(altar,(x,17.3,2.63),.13,.6,6,10)
        cylinder(altar,(x,17.3,3.01),.09,.42,14,10)
    # Minimal gilded sanctuary cross, floating visually against triptych.
    box(altar,(0,19.05,5.2),(.17,.2,4.1),6)
    box(altar,(0,19.05,6.05),(2.0,.2,.17),6)
    for y in (-10.8,3.6,14.4):
        g=group('Vesper_20_Chandeliers')
        z=9.2
        beam(g,(0,y,z),(0,y,19.1),.025,12,6)
        for i in range(12):
            a,b=i*math.tau/12,(i+1)*math.tau/12
            beam(g,(1.3*math.cos(a),y+1.3*math.sin(a),z),(1.3*math.cos(b),y+1.3*math.sin(b),z),.065,6,6)
        for i in range(6):
            a=i*math.tau/6;x,yy=1.3*math.cos(a),y+1.3*math.sin(a)
            beam(g,(0,y,z+.7),(x,yy,z),.045,6,6)
            cylinder(g,(x,yy,z+.19),.085,.35,14,8)
        add_light(f'Chandelier_{y}',(0,y,z-.5),energy=230,radius=1.5)
    # Courtyard votive lanterns and slender cypress silhouettes.
    for side in (-1,1):
        g=group(f'Vesper_21_Courtyard_{side}')
        for y in (-25,23):
            x=side*13.6
            cylinder(g,(x,y,.9),.58,1.2,1,8)
            cylinder(g,(x,y,2.5),.28,2.0,5,8)
            for k in range(3):cylinder(g,(x,y,3.8+k*.75),1.05-k*.22,2.5,13,9,.1)
        x,y=side*5,-24
        cylinder(g,(x,y,1.5),.11,2.75,12,8)
        box(g,(x,y,3),(.58,.58,.73),9)
        cylinder(g,(x,y,3.47),.5,.37,12,4,.06)
        add_light(f'EntryLantern_{side}',(x,y,3.1),energy=95,radius=.4)
    add_light('SanctuaryWarm',(0,16,5.4),energy=340,radius=2)
    for side in (-1,1):
        for y in (-11.4,3.8,15.2):add_light(f'WindowWash_{side}_{y}',(side*8.5,y,7),(0.27,.58,1),energy=150,radius=1.2)

def realize():
    img=bpy.data.images.load(str(ROOT/'textures/VesperCathedral_BaseColor.png'),check_existing=True)
    rough=bpy.data.images.load(str(ROOT/'textures/VesperCathedral_Roughness.png'),check_existing=True)
    rough.colorspace_settings.name='Non-Color'
    mats=[]
    for name,glow in [('Vesper_Atlas',0),('Vesper_StainedGlass',.55)]:
        mat=bpy.data.materials.new(name);mat.use_nodes=True
        nodes=mat.node_tree.nodes;p=next(n for n in nodes if n.type=='BSDF_PRINCIPLED')
        tex=nodes.new('ShaderNodeTexImage');tex.image=img;mat.node_tree.links.new(tex.outputs['Color'],p.inputs['Base Color'])
        rt=nodes.new('ShaderNodeTexImage');rt.image=rough;mat.node_tree.links.new(rt.outputs['Color'],p.inputs['Roughness'])
        if glow:
            mat.node_tree.links.new(tex.outputs['Color'],p.inputs['Emission Color']);p.inputs['Emission Strength'].default_value=glow
        mats.append(mat)
    stats=[]
    for name,g in BUILDERS.items():
        mesh=bpy.data.meshes.new(name);mesh.from_pydata(g.v,[],g.f);mesh.update()
        # Per-face atlas coordinates with generous padding; stone variations follow world geometry.
        uv=mesh.uv_layers.new(name='UVMap')
        for poly,tile in zip(mesh.polygons,g.tiles):
            coords=[Vector(mesh.vertices[v].co) for v in poly.vertices]
            normal=poly.normal; drop=max(range(3),key=lambda i:abs(normal[i])); axes=[i for i in range(3) if i!=drop]
            lo=[min(v[a] for v in coords) for a in axes]; hi=[max(v[a] for v in coords) for a in axes]
            for li,co in zip(poly.loop_indices,coords):
                u=(co[axes[0]]-lo[0])/max(hi[0]-lo[0],.001);v=(co[axes[1]]-lo[1])/max(hi[1]-lo[1],.001)
                uv.data[li].uv=((tile%4+.055+.89*u)/4,(tile//4+.055+.89*v)/4)
        bm=bmesh.new();bm.from_mesh(mesh)
        if hasattr(g,'clip_below'):
            bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),dist=.00001,
                                  plane_co=(0,0,g.clip_below),plane_no=(0,0,1),clear_inner=True,clear_outer=False)
            boundary=[e for e in bm.edges if e.is_boundary]
            if boundary:bmesh.ops.holes_fill(bm,edges=boundary,sides=0)
        bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
        bmesh.ops.triangulate(bm,faces=list(bm.faces))
        bm.to_mesh(mesh);bm.free();mesh.update()
        obj=bpy.data.objects.new(name,mesh);architecture.objects.link(obj)
        obj.data.materials.append(mats[1 if g.glass else 0]);obj['VesperCategory']='Glass' if g.glass else 'Architecture'
        obj['Roblox_CanCollide']=False;obj['Roblox_Anchored']=True
        stats.append(dict(name=name,vertices=len(mesh.vertices),triangles=len(mesh.polygons),material=obj.data.materials[0].name))
    return stats

def camera(name,loc,target,lens=38,ortho=None):
    d=bpy.data.cameras.new(name);o=bpy.data.objects.new(name,d);presentation.objects.link(o)
    o.location=Vector(loc)*S;o.rotation_euler=(Vector(target)*S-o.location).to_track_quat('-Z','Y').to_euler();d.lens=lens;d.clip_end=1500
    if ortho:d.type='ORTHO';d.ortho_scale=ortho*S
    return o

def lighting():
    world=bpy.data.worlds.new('Vesper_Dusk');world.use_nodes=True
    bg=next(n for n in world.node_tree.nodes if n.type=='BACKGROUND');bg.inputs['Color'].default_value=(.14,.2,.28,1);bg.inputs['Strength'].default_value=.45;scene.world=world
    sun=bpy.data.lights.new('GoldenEvening','SUN');sun.energy=2.3;sun.color=(1,.78,.52);sun.angle=.12
    ob=bpy.data.objects.new('GoldenEvening',sun);presentation.objects.link(ob);ob.rotation_euler=(math.radians(30),math.radians(-32),math.radians(-28))
    area=bpy.data.lights.new('SkyFill','AREA');area.energy=1900*S*S;area.shape='DISK';area.size=25*S;area.color=(.45,.65,1)
    ob=bpy.data.objects.new('SkyFill',area);presentation.objects.link(ob);ob.location=Vector((15,-8,25))*S;ob.rotation_euler=(Vector((0,0,8))*S-ob.location).to_track_quat('-Z','Y').to_euler()
    scene.render.engine='BLENDER_EEVEE'
    scene.render.resolution_x=1400;scene.render.resolution_y=1050;scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='PNG'
    scene.render.film_transparent=False
    # Blender defaults supply a valid color-management transform on the installed version.
    scene.view_settings.exposure=.35

def finish(stats):
    camera('Vesper_Camera_Exterior',(40,-54,34),(0,-1,10),ortho=68)
    camera('Vesper_Camera_Interior',(0,-17.3,3.1),(0,14.0,7.7),lens=22)
    camera('Vesper_Camera_Sanctuary',(3,-2,4),(0,16,6.2),lens=25)
    scene.camera=bpy.data.objects['Vesper_Camera_Exterior']
    lighting()
    for o in bpy.context.selected_objects:o.select_set(False)
    for o in architecture.objects:o.select_set(True)
    bpy.context.view_layer.objects.active=next(iter(architecture.objects))
    bounds=[Vector(v.co) for o in architecture.objects for v in o.data.vertices]
    lo=[min(v[i] for v in bounds) for i in range(3)];hi=[max(v[i] for v in bounds) for i in range(3)]
    dims=[hi[0]-lo[0],hi[2]-lo[2],hi[1]-lo[1]]
    center=[(lo[0]+hi[0])/2,(lo[2]+hi[2])/2,-(lo[1]+hi[1])/2]
    data=dict(dimensions=dims,center=center,colliders=COLLIDERS,lights=LIGHTS)
    (ROOT/'setup-data.json').write_text(json.dumps(data,indent=2))
    (ROOT/'geometry-manifest.json').write_text(json.dumps(dict(name='Vesper Cathedral',units='studs',seed=SEED,
        design_grid_to_studs=S,mesh_count=len(stats),triangles=sum(x['triangles'] for x in stats),
        max_mesh_triangles=max(x['triangles'] for x in stats),dimensions_roblox=dims,center_roblox=center,
        objects=stats,collision_parts=len(COLLIDERS),local_lights=len(LIGHTS),studio_import_verified=False),indent=2))
    for img in bpy.data.images:
        if img.filepath and 'vesper-cathedral' in img.filepath:img.pack()
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'VesperCathedral.blend'),check_existing=False)
    print(json.dumps({'scene':scene.name,'meshes':len(stats),'triangles':sum(x['triangles'] for x in stats),'dimensions':dims}))

build_site();build_nave();build_roofs();build_ends();build_towers();build_furnishings()
stats=realize();finish(stats)
