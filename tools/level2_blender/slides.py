"""Job F, offline only. All geometry inputs are Roblox studs / axes.

Run: D:/Blender/blender.exe -b --factory-startup --python-exit-code 1
     -P G:/Roblox/MongoTV/tools/level2_blender/slides.py --

No Studio, git, GUI, or shared kit files are modified. The Lua source is a
read-only formula reference, not a deployment baseline. build() also works
when imported by a kit assembly script. See export/checks.json for limitations.
"""
import base64
import hashlib
import json
import math
from pathlib import Path
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).parent))
import bpy
import numpy as np
from mathutils import Vector
from mathutils import Matrix
import kit

OUT = Path('G:/Blender/Level2_Pool/jobs/F/export')
REVIEW = Path('G:/Blender/Level2_Pool/review/F')
SOURCE = kit.ROOT / 'ServerScriptService/Level 2 Systems/Level 2 World Builder.ModuleScript.lua'
PROFILES, SLIDES, PREFABS = {}, {}, {}
PHYSICS = dict(Anchored=True, Transparency=1, CanCollide=True, CanTouch=False,
               CanQuery=True, CastShadow=False, CollisionGroup='Default',
               Material='SmoothPlastic', Color=[255,255,255],
               CollisionFidelity='PreciseConvexDecomposition',
               CustomPhysicalProperties=dict(density=.7, friction=.05,
                   elasticity=.05, frictionWeight=1, elasticityWeight=1))
LIMITATIONS = [
    'A cradle with 17 closed box islands needs 204 triangles, not <=72. '
    'It is split into three unit-length chunks (72/72/60), adding two instances per tub.',
    'Clipped chamfer vertices cannot equal the original uncut box corners. '
    'Checks compare to independently clipped live boxes and verify the removed volume is covered by floor/walls.',
    'Eight open radii plus one ring plus nine three-chunk cradles require 44 meshes, '
    'rather than the report estimate of about 17.',
    'Small prefabs freeze RNG: SlideKit padTop/run 4.5/12 and 8/18; '
    'PlayTower topY 10 and 14; kids longDimension 128, origin zero, forward +Z.',
    'Hall deckY is the slab centre, as in live Lua (walk surface deckY+1), '
    'rather than interpreting deck at 54/74 as its top.',
    'Exit reference lead-in uses hall.MaxX=670 (25 studs). Its first point, tub and mouth '
    'are stretchable runtime records; fixed plunge/transfer/helix remain translation-only.',
    'Recovery overhead is named Recovery Chamber Overhead Tile to obey the forbidden-name rule.',
    'Hall shell uses sealed connector plugs at door sockets and a closed overhead panel; '
    'door/skylight modules are supplied by other kit jobs. No procedural skylight dodge is applied.',
    'Visuals are continuous lofts on the live visual samples rather than overlapping per-chord sleeves. '
    'Collision chords are unchanged; visual lips and support bars are rebuilt.',
    'Recovery story door and its frame use ServiceGrey rather than introducing a new wood material.',
    'Slide hall basins freeze the live 1.8-stud depth as a flat floor; the general kit hall recipe describes a slope. '
    'Water is a Terrain marker, so the Blender review shows the basin mesh without a water simulation.',
    'The hall shell/stair/support bucket is reported separately from the <=1500 slide geometry budget.',
    'Structural tests are offline only. Convex decomposition, ray probes, ride parity, '
    'navigation, multiplayer and mobile performance remain unverified in Studio.',
]


def v(p):
    return np.asarray(p, dtype=float)


def unit(p):
    return p / np.linalg.norm(p)


def vec(p):
    return [float(x) for x in p]


def frame(a, b):
    """CFrame.lookAt(a,b,Y): Roblox local X right, Y up, Z back."""
    look = unit(v(b) - v(a))
    reference = v((0,0,1)) if abs(look[1])>.999 else v((0,1,0))
    right = unit(np.cross(look, reference))
    up = np.cross(right, look)
    return np.column_stack((right, up, -look))


def cf(position, look, axis='Z'):
    f = frame(position, v(position) + v(look))
    if axis == 'X':
        # Lua fromMatrix(position, axis, projectedUp, axis:Cross(up)).
        f = np.column_stack((v(look), f[:, 1], np.cross(v(look), f[:, 1])))
    return dict(position=vec(position), look=vec(look), right=vec(f[:, 0]),
                up=vec(f[:, 1]), back=vec(f[:, 2]), lengthAxis=axis)


def bezier(p0, p1, p2, p3, t):
    return (1-t)**3*v(p0)+3*(1-t)**2*t*v(p1)+3*(1-t)*t*t*v(p2)+t**3*v(p3)


def make_slide_tube(control, segments, collision_segments):
    """WB makeSlideTube, with the installed mesh-template branch frozen true."""
    visual_n = max(segments, int(segments*1.6+.5))
    return ([bezier(*control, i/visual_n) for i in range(visual_n+1)],
            [bezier(*control, i/collision_segments) for i in range(collision_segments+1)])


def make_helix_slide(x, radius, top):
    def at(t):
        a = math.pi/2+t*math.tau*2.1
        return v((x+math.cos(a)*radius, top*(1-t)+3.4*t, math.sin(a)*radius))
    return ([at(i/120) for i in range(121)], [at(i/48) for i in range(49)])


def make_exit_flume(max_x=670):
    """WB makeExitFlume in the plungeStart frame (anchor world 681,83.3,deckZ)."""
    anchor = v((681, 83.3, 0))
    end = v((801, 4, 0))
    c1 = anchor+v((24, -2, 0))
    c2 = end+v((-34, 34*.21/math.sqrt(1-.21**2), 0))
    pts = [v((max_x-14, 83.3, 0)), anchor]
    pts += [bezier(anchor, c1, c2, end, i/72) for i in range(1, 73)]
    pts += [end+v((250*i/18, -250*i/18*.21, 0)) for i in range(1, 19)]
    entry = pts[-1]
    center = entry-v((0, 0, 96))
    delta = math.tau*96*.21
    for i in range(1, 181):
        t = 3*i/180
        a = math.pi/2-t*math.tau
        pts.append(center+v((math.cos(a)*96, -t*delta, math.sin(a)*96)))
    pts = [p-anchor for p in pts]
    recycle = dict(TopY=entry[1]-anchor[1], DeltaY=delta, Turns=3, Radius=96,
        startAngle=math.pi/2, clockwise=True, cw=True, CenterX=center[0]-anchor[0],
        CenterZ=center[2], BottomY=entry[1]-3*delta-anchor[1],
        TriggerY=entry[1]-2*delta-anchor[1], LandingY=entry[1]-delta-anchor[1])
    return pts, recycle, anchor


def rectangle(cx, cy, w, h, angle=0):
    q = np.array(((-w/2,-h/2), (w/2,-h/2), (w/2,h/2), (-w/2,h/2)))
    rot = np.array(((math.cos(angle), -math.sin(angle)),
                    (math.sin(angle), math.cos(angle))))
    return q@rot.T+v((cx,cy))


def clip(poly, axis, limit, keep_greater):
    result = []
    for a, b in zip(poly, np.roll(poly, -1, axis=0)):
        inside_a = a[axis] >= limit-1e-10 if keep_greater else a[axis] <= limit+1e-10
        inside_b = b[axis] >= limit-1e-10 if keep_greater else b[axis] <= limit+1e-10
        if inside_a:
            result.append(a)
        if inside_a != inside_b:
            result.append(a+(b-a)*(limit-a[axis])/(b[axis]-a[axis]))
    return np.array(result)


def live_boxes(r, t, h, closed=False):
    """The six exact live cross-section boxes before allowed chamfer clipping."""
    q = [rectangle(0,-.9*r-t/2,1.55*r,t)]
    for side in (-1,1):
        a = side*math.pi/4
        center = v((math.sin(a)*(.9*r+t/2), -math.cos(a)*(.9*r+t/2)))
        q.append(rectangle(*center,.8*r,t,a))
    q += [rectangle(side*(.9*r+t/2), 0 if closed else -.9*r+h/2,t,h)
          for side in (-1,1)]
    if closed:
        q.append(rectangle(0,.9*r+t/2,1.55*r,t))
    return q


def cross_section(r, t, h=1, closed=False):
    boxes = live_boxes(r,t,h,closed)
    for i in (1,2):
        boxes[i] = clip(clip(clip(boxes[i],1,-.9*r,True),0,-.9*r,True),0,.9*r,False)
    return boxes


def extrude(m, poly, mat, depth=1, center=(0,0,0), transform=None):
    n = len(poly)
    verts = [v((x,y,z)) for z in (-depth/2,depth/2) for x,y in poly]
    if transform is not None:
        verts = [transform@p for p in verts]
    verts = [p+v(center) for p in verts]
    faces = [tuple(reversed(range(n))), tuple(range(n,2*n))]
    faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    m.raw([vec(p) for p in verts],faces,mat)


def gloss_materials():
    # kit.material-compatible entries, plain SmoothPlastic with no tile maps.
    for name, rgb in dict(FibGreen=(96,196,132), FibRed=(224,96,84),
                          FibYellow=(238,202,84), FibBlue=(78,158,214),
                          FibExit=(150,205,200), ColDebug=(235,80,110)).items():
        if name in kit.MATERIALS:
            continue
        material = bpy.data.materials.new('L2K_'+name)
        material.use_nodes = True
        bsdf = material.node_tree.nodes['Principled BSDF']
        bsdf.inputs['Base Color'].default_value = (*map(kit.linear,rgb),1)
        bsdf.inputs['Roughness'].default_value = .23
        bsdf.inputs['Coat Weight'].default_value = .4
        bsdf.inputs['Coat Roughness'].default_value = .18
        kit.MATERIALS[name] = dict(blender=material,robloxMaterial='SmoothPlastic',
            variant=None,color=list(rgb),tile_m=1,reflectance=.06)


def profile(name, kind, r, t, polygons, depths=None, **extra):
    depths = depths or [1]*len(polygons)
    m = kit.Mesh(name, Collision=True, properties=PHYSICS, Template=True)
    for p,d in zip(polygons,depths):
        extrude(m,p,'ColDebug',d)
    m.finish()
    verts = np.array([vert.co[:] for vert in kit.COMPONENTS[name]['mesh'].vertices])@kit.C.T/kit.S
    lo,hi = verts.min(0),verts.max(0)
    PROFILES[name] = dict(kind=kind,r=r,t=t,islands=[p.tolist() for p in polygons],
        islandDepths=depths,axisOffsetY=float((lo[1]+hi[1])/2),
        axisOffset=vec((lo+hi)/2),size=vec(hi-lo),**extra)
    return name


def create_profiles():
    for r in (7.5,4.6,2.6,4.2,1.8,2.7,3.5,4.1):
        q = cross_section(r,.6)
        profile(f'SlideCol_Floor_r{r:g}','Floor',r,.6,q[:3])
        profile(f'SlideCol_Guard_r{r:g}','Guard',r,.6,q[3:],unitHeight=1)
    profile('SlideCol_Ring_r8','Ring',8,.9,cross_section(8,.9,14.4,True))
    for r in (7.5,4.6,8,2.6,4.2,1.8,2.7,3.5,4.1):
        length = min(10,max(5.5,1.35*r))+.35
        polygons = []
        step = math.radians(226)/16
        tangent_length = 2*1.085*r*math.sin(step/2)+.08
        for i in range(16):
            a = math.radians(157)+(i+.5)*step
            # The live sideDirection equals lookAt's localRight.
            center = (math.cos(a)*1.0425*r,math.sin(a)*1.0425*r)
            polygons.append(rectangle(*center,.085*r,tangent_length,a))
        thickness = min(.55,max(.28,.065*r))
        polygons.append(rectangle(0,-r+.03-thickness/2,2.15*r,thickness))
        depths = [(length-.16)/length]*16+[1]
        root = f'SlideCol_Cradle_r{r:g}'
        children = []
        for i,start in enumerate(range(0,17,6)):
            key = f'{root}_{i+1}'
            children.append(profile(key,'Cradle',r,.6,polygons[start:start+6],
                depths[start:start+6],supportLength=length,islandStart=start))
        # Named assembly component has no mesh triangles; each child remains <=72.
        kit.Mesh(root,Collision=True,Template=True,children=children).finish()
        PROFILES[root] = dict(kind='CradleAssembly',r=r,t=.6,children=children,
            supportLength=length,axisOffsetY=0)


def sweep(m, points, r, mat, closed=False, thickness=.34, radial_steps=24,
          frames=None, cap_start=True, cap_end=True):
    """Continuous hollow shell with rounded exposed lips and sealed axial thickness.

    Same path samples as collision/visual formulas; averaged chord frames remove
    the legacy overlapping feathers. No concave collision is made here.
    """
    if closed:
        angles = [math.tau*i/radial_steps for i in range(radial_steps)]
        section = [(math.cos(a)*rr,math.sin(a)*rr)
                   for rr in (.9*r,.9*r+thickness) for a in angles]
        section_edges = [(i,(i+1)%radial_steps) for i in range(radial_steps)]
        section_edges += [(i+radial_steps,j+radial_steps) for i,j in section_edges[:]]
    else:
        start,end = math.pi-.35,math.tau+.35
        angles = [start+(end-start)*i/radial_steps for i in range(radial_steps+1)]
        inner,outer = .9*r,.9*r+thickness
        section = [(math.cos(a)*inner,math.sin(a)*inner) for a in angles]
        # Semicircular lip wraps (real bullnose, no knife edges).
        mid = (inner+outer)/2
        for j in range(1,5):
            d = math.pi*j/4
            radial = -math.cos(d)*thickness/2
            tangent = math.sin(d)*thickness/2
            section.append((math.cos(end)*(mid+radial)-math.sin(end)*tangent,
                            math.sin(end)*(mid+radial)+math.cos(end)*tangent))
        section += [(math.cos(a)*outer,math.sin(a)*outer) for a in reversed(angles[:-1])]
        for j in range(1,4):
            d = math.pi*j/4
            radial = math.cos(d)*thickness/2
            tangent = -math.sin(d)*thickness/2
            section.append((math.cos(start)*(mid+radial)-math.sin(start)*tangent,
                            math.sin(start)*(mid+radial)+math.cos(start)*tangent))
        section_edges = [(i,(i+1)%len(section)) for i in range(len(section))]
    verts=[]
    for i,p in enumerate(points):
        a,b = points[max(0,i-1)],points[min(len(points)-1,i+1)]
        f = frames[i] if frames is not None else frame(a,b)
        verts += [vec(v(p)+f@v((x,y,0))) for x,y in section]
    n=len(section)
    faces=[]
    for row in range(len(points)-1):
        faces += [(row*n+i,row*n+j,(row+1)*n+j,(row+1)*n+i) for i,j in section_edges]
    side_face_count=len(faces)
    if closed:
        for row in ([0] if cap_start else [])+([len(points)-1] if cap_end else []):
            o=row*n
            faces += [(o+i,o+(i+1)%radial_steps,o+(i+1)%radial_steps+radial_steps,
                       o+i+radial_steps) for i in range(radial_steps)]
    else:
        for row in ([0] if cap_start else [])+([len(points)-1] if cap_end else []):
            o=row*n
            # Explicit strip quads avoid ambiguous triangulation of a very concave U cap.
            def outer(i):
                return radial_steps+4 if i==radial_steps else 2*radial_steps+4-i
            faces += [(o+i,o+i+1,o+outer(i+1),o+outer(i)) for i in range(radial_steps)]
            faces += [tuple(o+i for i in range(radial_steps,radial_steps+5)),
                      tuple([o+2*radial_steps+4]+list(range(o+2*radial_steps+5,o+n))+[o])]
    old_faces=len(m.bm.faces)
    m.raw(verts,faces,mat,smooth=True)
    for face in list(m.bm.faces)[old_faces+side_face_count:]:
        face.smooth=False


def bar(m,a,b,mat='Steel',width=.32,bevel=.06):
    a,b=v(a),v(b)
    f=frame(a,b)
    poly=rectangle(0,0,width,width)
    extrude(m,poly,mat,np.linalg.norm(b-a),(a+b)/2,f)


def record_part(m,name,position,size,mat,look=None,axis='Z',properties=None,**kw):
    m.part(name,position,size,mat,**kw)
    rec=m.parts[-1]
    if look is not None:
        rec['cframe']=cf(position,look,axis)
        if kw.get('show',True):
            # part() has yaw only; draw exact tilted source frame instead.
            # Remove only the just-created preview cube by rebuilding previews later.
            rec['_tiltedPreview']=True
    if properties:
        rec['properties']=properties
    return rec


def finish_prefab(m):
    # Render Part records using full frames; original kit API supports yaw only.
    if m.preview:
        m.preview.bm.free()
    m.preview=kit.Mesh(m.name+'__parts') if m.parts else None
    for p in m.parts:
        p.pop('_tiltedPreview',False)
        if p.get('properties',{}).get('Transparency')==1:
            continue
        size=p['size']
        f=p.get('cframe')
        if f:
            transform=np.column_stack((f['right'],f['up'],f['back']))
            extrude(m.preview,rectangle(0,0,size[0],size[1]),p['material'],size[2],p['cf'][:3],transform)
        else:
            angle=math.radians(p['cf'][3])
            transform=np.array(((math.cos(angle),0,math.sin(angle)),(0,1,0),(-math.sin(angle),0,math.cos(angle))))
            extrude(m.preview,rectangle(0,0,size[0],size[1]),p['material'],size[2],p['cf'][:3],transform)
    m.finish()


def tub(m, key, points, r, deck_top, mat, separate_mouth=False):
    mouth,toward=points[0],points[1]
    direction=unit(v((toward[0]-mouth[0],0,toward[2]-mouth[2])))
    length=min(10,max(5.5,1.35*r))
    rear=mouth-direction*length
    center=(rear+mouth)/2
    f=frame(center,mouth)
    floorcenter=(rear+mouth+direction*.75)/2
    floorcenter[1]=mouth[1]-.9*r-.3
    attrs=dict(Level2_SlideCollision=True,Level2_SlideFloor=True,
               Level2_NoEntityGround=True,Level2_SlideDirection=vec(direction))
    record_part(m,SLIDES[key]['model']+' Entry Collision Floor',vec(floorcenter),
        (1.55*r,.6,length+.75),mat,look=direction,properties=PHYSICS,
        attrs=attrs,show=False)
    apron_name=f'{key}_Mouth'
    apron=kit.Mesh(apron_name,Level2_SlideEntry=True,Mouth=separate_mouth)
    sweep(apron,[rear-direction*.07,mouth+direction*.07],r,mat)
    # Grounded cradle visual; invisible exact bands remain separate templates.
    sweep(apron,[rear-direction*.175,mouth+direction*.175],r/ .9,mat,thickness=.10*r)
    bt=min(.55,max(.28,.065*r))
    base_y=max(deck_top+.08,mouth[1]-r+.03)-bt/2
    apron.box(vec((center[0],base_y,center[2])),(2.15*r,bt,length+.35),mat,bevel=.05)
    apron.finish()
    SLIDES[key]['visualChunks'].append(apron_name)
    profile_key=f'SlideCol_Cradle_r{r:g}'
    children=PROFILES[profile_key]['children']
    placements=[]
    for child in children:
        p=PROFILES[child]
        offset=v(p['axisOffset']);offset[2]*=length+.35
        placements.append(dict(profile=child,cframe=cf(center+f@offset,direction),
            size=[p['size'][0],p['size'][1],p['size'][2]*(length+.35)],
            attrs=dict(Level2_SlideCollision=True,Level2_SlideEntrySupport=True,
                       Level2_NoEntityGround=True),properties=PHYSICS))
    handles=kit.Mesh(key+'_Handles')
    side=v((-direction[2],0,direction[0]))
    lift=min(2.8,max(1.7,.38*r))
    for sign in (-1,1):
        back=rear+side*sign*(r+.72);back[1]=deck_top+.35
        front=mouth-direction*1.1+side*sign*(r+.72);front[1]=deck_top+.35
        bar(handles,back,back+v((0,lift,0)))
        bar(handles,front,front+v((0,lift,0)))
        bar(handles,back+v((0,lift,0)),front+v((0,lift,0)))
    handles.finish()
    SLIDES[key]['visualChunks'].append(handles.name)
    SLIDES[key]['tub']=dict(mouth=vec(mouth),toward=vec(toward),deckTop=deck_top,r=r,
        entryLength=length,profile=profile_key,cframe=cf(center,direction),
        collisionPlacements=placements,entryFloor=m.parts[-1],mouthComponent=apron_name)


def make_tube(prefab,key,model,visual,collision,r,mat,full=14,closed=False):
    t=.9 if closed else .6
    segments=[]
    for i,(a,b) in enumerate(zip(collision,collision[1:]),1):
        direction=unit(b-a)
        h=1.8*r if closed else 1.15*r+(max(full,1.15*r)-1.15*r)*min(1,(len(collision)-1-i)/2)
        midpoint=(a+b)/2
        floor_profile=f'SlideCol_Ring_r8' if closed else f'SlideCol_Floor_r{r:g}'
        rec=dict(i=i,len=float(np.linalg.norm(b-a)+1.5),dir=vec(direction),
            oneWay=bool(closed and direction[1]<-.01),guardHeight=h,
            profile=floor_profile,cframe=cf(midpoint,direction))
        placements=[]
        for pkey,kind in [(floor_profile,'Floor')]+([] if closed else [(f'SlideCol_Guard_r{r:g}','Guard')]):
            p=PROFILES[pkey]
            offset=v(p['axisOffset'])
            size=p['size'].copy();size[2]=rec['len']
            if kind=='Guard':
                offset[1]=-.9*r+h/2
                size[1]=h
            attrs=dict(Level2_SlideCollision=True)
            if kind=='Floor':
                attrs.update(Level2_SlideFloor=True,Level2_SlideDirection=vec(direction),Level2_NoEntityGround=True)
                if rec['oneWay']:
                    attrs['Level2_OneWayExit']=True
            placements.append(dict(profile=pkey,name=model+f' Collision {kind} {i:03d}',
                cframe=cf(midpoint+frame(a,b)@offset,direction),size=size,
                attrs=attrs,properties=PHYSICS,rotateDirectionFromLookVector=True))
        rec['pieces']=placements
        segments.append(rec)
    chunks=[]
    visual_placements={}
    if closed:
        lead_name=key+'_LeadVisual'
        lead=kit.Mesh(lead_name,Level2_SlideVisual=True,Stretchable=True)
        sweep(lead,[v((0,0,.5)),v((0,0,-.5))],r,mat,True)
        lead.finish();chunks.append(lead_name)
        a,b=visual[:2]
        visual_placements[lead_name]=dict(cframe=cf((a+b)/2,unit(b-a)),scaleZ=float(np.linalg.norm(b-a)),stretchable=True)
    # <= 20k per chunk, maximum 130 visual chords for closed tubes / 120 open.
    span=130 if closed else 120
    frames=[frame(visual[max(0,i-1)],visual[min(len(visual)-1,i+1)]) for i in range(len(visual))]
    for j,start in enumerate(range(1 if closed else 0,len(visual)-1,span),1):
        name=f'{key}_Visual_{j:02d}'
        m=kit.Mesh(name,Level2_SlideVisual=True,CanCollide=False,CanQuery=False,CanTouch=False)
        stop=min(start+span+1,len(visual))
        sweep(m,visual[start:stop],r,mat,closed,frames=frames[start:stop],
              cap_start=start==(1 if closed else 0),cap_end=stop==len(visual))
        m.finish();chunks.append(name)
    SLIDES[key]=dict(prefab=prefab,model=model,kind='closed' if closed else 'open',r=r,t=t,
        overlap=1.5,oneWay=closed,guard=dict(full=1.8*r if closed else max(full,1.15*r),outlet=1.15*r),
        collisionPoints=[vec(p) for p in collision],visualPoints=[vec(p) for p in visual],
        segments=segments,visualChunks=chunks,visualPlacements=visual_placements,
        attrs=dict(Level2_SmoothSlide=True,Level2_OpenTop=not closed,
                   Level2_OneWayExit=closed,Level2_CollisionWallThickness=t))
    PREFABS[prefab]['tubes'].append(key)
    return key


def rail(m,a,b,height=3.2):
    a,b=v(a),v(b)
    for dy in (height, height*.5):
        bar(m,a+v((0,dy,0)),b+v((0,dy,0)))
    n=max(1,math.ceil(np.linalg.norm(b-a)/7))
    for i in range(n+1):
        p=a+(b-a)*i/n
        bar(m,p,p+v((0,height,0)))
    # Simple thin blockers do not occlude the bore or masquerade as slide floors.
    horizontal=b-a;horizontal[1]=0
    if np.linalg.norm(horizontal)>.01:
        yaw=math.degrees(math.atan2(-horizontal[0],-horizontal[2]))
        m.collider('L2K Rail Blocker',vec((a+b)/2+v((0,height/2,0))),
                   (.32,height,float(np.linalg.norm(horizontal))),yaw=yaw)


def coping(m,a,b):
    # Low-poly bullnose coping, .6 stud radius, one Terrazzo chunk.
    poly=[(-.6,-.3),(.6,-.3),(.6,0)]
    poly += [(math.cos(i*math.pi/8)*.6,math.sin(i*math.pi/8)*.6) for i in range(1,9)]
    extrude(m,np.array(poly),'Terrazzo',np.linalg.norm(v(b)-v(a)),(v(a)+v(b))/2,frame(a,b))


def hall_shell(m,w,d,h,grand):
    bx,bz=w/2-14,d/2-14
    m.part('Level 2 Hall Water Floor {i}',(0,-2.2,0),(2*bx,.8,2*bz),'Mosaic',ground=True)
    for side in (-1,1):
        m.part('L2K Pool Basin End',(0,-.9,side*bz),(2*bx,1.8,1),'Mosaic')
        m.part('L2K Pool Basin Side',(side*bx,-.9,0),(1,1.8,2*bz),'Mosaic')
        m.part('L2K Pool Edge Deck',(0,-.5,side*(d/2-7)),(w,1,14),'Terrazzo',ground=True)
        m.part('L2K Pool Side Deck',(side*(w/2-7),-.5,0),(14,1,d-28),'Terrazzo',ground=True)
        coping(m,(-bx,0,side*bz),(bx,0,side*bz))
        coping(m,(side*bx,0,-bz+.6),(side*bx,0,bz-.6))
    for x in (-54,-18,18,54):
        m.part('L2K Pool Lane',(x,-1.785,0),(.7,.03,2*bz-1),'Cobalt',collide=False)
    # Flat shell Parts. Cut only the exact exit wall gap; socket plugs are removable records.
    gap_z=-79.25
    for axis,sign in [('X',-1),('X',1),('Z',-1),('Z',1)]:
        width=d if axis=='X' else w
        wallpos=sign*(w/2 if axis=='X' else d/2)
        def panel(label,along,y,length,height,mat='Tile',proud=0):
            pos=(wallpos-sign*proud,y,along) if axis=='X' else (along,y,wallpos-sign*proud)
            size=(1.5,height,length) if axis=='X' else (length,height,1.5)
            m.part(f'L2K {axis}{sign} {label}',pos,size,mat)
        if grand and axis=='X' and sign==1:
            # Exact 18.5-square portal centred on y=83.3, z=-79.25.
            lo,hi=gap_z-9.25,gap_z+9.25
            panel('Wall South',(hi+d/2)/2,h/2,d/2-hi,h)
            panel('Wall North',(-d/2+lo)/2,h/2,lo+d/2,h)
            panel('Wall Below Portal',gap_z,(83.3-9.25)/2,18.5,83.3-9.25)
            panel('Wall Above Portal',gap_z,(83.3+9.25+h)/2,18.5,h-83.3-9.25)
        else:
            # Sealed Parts at sockets; downstream assembler opens only joined doors.
            panel('Wall Left',-(width/2+15)/2,h/2,width/2-15,h)
            panel('Wall Right',(width/2+15)/2,h/2,width/2-15,h)
            panel('Wall Header',0,(h+30)/2,30,h-30)
            panel('Connector Plug',0,15,30,30)
            m.parts[-1]['attrs']['RemoveOnConnectedSocket']=True
            p=(wallpos,0,0) if axis=='X' else (0,0,wallpos)
            m.marker(f'DoorSocket_{axis}{sign}',p,90*sign if axis=='X' else (180 if sign==1 else 0),Width=30,Height=30)
        panel('Teal Dado',0,1.5,width,3,'TileTeal',.78)
        for y0 in (h/3,h-5):
            for j,mat in enumerate(('BandCoral','BandYellow','BandBlue')):
                panel('Tile Stripe',0,y0+j*.9,width,.6,mat,.82)
    m.part('Level 2 Overhead Tile Hall',(0,h+.6,0),(w+1.5,1.2,d+1.5),'Tile',collide=False)
    m.collider('Level 2 Hall Roof',(0,h+1.3,0),(w+1.5,.2,d+1.5))
    m.marker('HallCentre',(0,0,0),Width=w,Depth=d,Height=h,PoolDepth=1.8,FloorY=0)
    m.marker('TerrainWater',(0,-.4,0),Width=2*bx,Depth=2*bz,Bottom=-1.8,Surface=-.4)
    # Window panels sit proud of backed walls, leaving no view to the void.
    for x in (-w/2+.82,w/2-.82):
        for z in (-20,24,62):
            m.part('L2K Glass Block Window',(x,h*.65,z),(.22,h*.27,18),'GlassBlock',collide=False)


def spiral(m,center,top):
    base=-.8
    turns=max(2,math.floor((top-base)/34+.5))
    n=max(max(10,math.floor((top-base)/1.05)),math.ceil(turns*math.tau*12/3.2))
    m.cylinder((center[0],(top+base+5)/2,center[2]),4,top-base+5,'Tile',segments=20)
    m.collider('L2K Spiral Core',(center[0],(top+base)/2,center[2]),(8,top-base,8),shape='Cylinder',
               attrs={'CylinderAxis':'Y','NativeSizeX':top-base,'NativeSizeY':8,
                      'NativeSizeZ':8,'NativeRotationZ':90})
    last=None
    every=max(2,math.floor(n*5.5/(turns*math.tau*12)+.5))
    for i in range(n+1):
        t=i/n;a=-t*math.tau*turns
        y=base+t*(top-base)
        p=v(center)+v((math.cos(a)*12,y,math.sin(a)*12))
        m.part(f'L2K Spiral Tread {i}',vec(p),(17.4,.7,6.4),'Terrazzo',ground=True,yaw=-math.degrees(a))
        if i%every==0 and t<.86:
            p=v(center)+v((math.cos(a)*19.44,y,math.sin(a)*19.44))
            bar(m,p,p+v((0,3.2,0)))
            m.collider('L2K Spiral Post',vec(p+v((0,1.6,0))),(.35,3.2,.35))
            if last is not None:
                bar(m,last,p+v((0,3.2,0)))
            last=p+v((0,3.2,0))


def hall(name,w,d,h):
    grand=name=='GrandSlideHall'
    PREFABS[name]=dict(component=name,tubes=[],instances={})
    m=kit.Mesh(name,Role='SlideHall',Width=w,Depth=d,Height=h)
    hall_shell(m,w,d,h,grand)
    deck=h-22;deck_z=-d/2+.75+23;front=deck_z+23
    west,east=-w/2+8,w/2-.75
    m.part('Level 2 Slide Hall Deck',((west+east)/2,deck,deck_z),(east-west,2,46),'Terrazzo',ground=True)
    mats=['FibGreen','FibRed','FibYellow']
    for i,x in enumerate((-34,0,34),1):
        control=[(x,deck+8.65,front+1),(x,deck+8.65,front+14),
                 (x,15,d*.06),(x,6.1,d*.26)]
        visual,collision=make_slide_tube(control,66,40)
        key=make_tube(name,f'{name}_Flume{i}',f'Level 2 Slide Hall {{i}} Flume {i}',visual,collision,7.5,mats[i-1])
        tub(m,key,visual,7.5,deck+1,mats[i-1])
        # Sparse supports outside the half-pipe; not inside its rider bore.
        for idx in (30,55,80):
            p=visual[idx]
            bottom=-1.8;ytop=p[1]-7.3
            if ytop>bottom+.5:
                for sign in (-1,1):
                    pos=(p[0]+sign*7.1,(ytop+bottom)/2,p[2])
                    m.cylinder(pos,.38,ytop-bottom,'Steel',segments=8)
                    m.collider('L2K Flume Support',pos,(.76,ytop-bottom,.76))
                bar(m,(p[0]-7.1,ytop,p[2]),(p[0]+7.1,ytop,p[2]),width=.5)
    x=w*.3;radius=15.4 if not grand else 16
    visual,collision=make_helix_slide(x,radius,deck+5.75)
    key=make_tube(name,name+'_Helix','Level 2 Slide Hall {i} Helix',visual,collision,4.6,'FibBlue')
    tub(m,key,visual,4.6,deck+1,'FibBlue')
    # Dedicated tiled helix column, one explicit Bands chunk.
    m.cylinder((x,h/2,0),4.5,h,'Tile',segments=24)
    band_height=1/kit.S
    for y0 in (3,h/3,h-7):
        def uv(co,normal,y0=y0):
            return (math.atan2(co[1],co[0]-x*kit.S)*4.52*kit.S,(co[2]-y0*kit.S)/(band_height*kit.S))
        m.cylinder((x,y0+band_height/2,0),4.52,band_height,'Bands',segments=24,uv=uv,caps=False)
    m.collider('L2K Helix Core',(x,h/2,0),(9,h,9),shape='Cylinder',
               attrs={'CylinderAxis':'Y','NativeSizeX':h,'NativeSizeY':9,
                      'NativeSizeZ':9,'NativeRotationZ':90})
    rear=v(SLIDES[key]['tub']['mouth'])-unit(v(SLIDES[key]['tub']['toward'])-v(SLIDES[key]['tub']['mouth']))*6.21
    dock_z=rear[2]
    inner=w/2-16;outer=w/2-.75
    m.part('L2K Helix Bridge',((inner+x)/2,deck,dock_z),(inner-x,2,14),'Terrazzo',ground=True)
    end_z=d/2-22.6
    m.part('L2K East Catwalk',((inner+outer)/2,deck,(end_z+front)/2),(outer-inner,2,end_z-front),'Terrazzo',ground=True)
    m.part('L2K Deck Join Backing',((inner+outer)/2,deck+.78,front),(outer-inner+.4,.4,1.2),'Terrazzo',collide=False)
    m.part('L2K Bridge Join Backing',(inner,deck+.78,dock_z),(1.2,.4,14.4),'Terrazzo',collide=False)
    for z in (dock_z-6.6,dock_z+6.6):
        rail(m,(inner,deck+1,z),(rear[0]+.3,deck+1,z))
    rail(m,(inner,deck+1,front),(inner,deck+1,dock_z-7.5))
    rail(m,(inner,deck+1,dock_z+7.5),(inner,deck+1,d/2-31))
    cursor=-w/2+10
    for mouth in (-34,0,34):
        rail(m,(cursor,deck+1,front),(mouth-10.5,deck+1,front))
        cursor=mouth+10.5
    rail(m,(cursor,deck+1,front),(inner,deck+1,front))
    rail(m,(west,deck+1,deck_z-23),(west,deck+1,front))
    spiral(m,(w/2-.75-20.7-.75,0,d/2-26),deck+.65)
    m.marker('Deck',(0,deck+1,deck_z),DeckY=deck,DeckZ=deck_z)
    m.marker('SlideHallIndex',(0,0,0),Placeholder='{i}',ColorCycle=['FibGreen','FibRed','FibYellow','FibBlue'])
    if grand:
        m.marker('ExitMouth',(98,83.3,-79.25),90,Gap=[18.5,18.5],NoRotation=True)
        # Square portal to round flume reveal; closes all visible corner voids.
        verts=[]
        for xplane in (w/2-.9,w/2+.9):
            for radius in (8.1,15.25):
                for i in range(32):
                    a=i*math.tau/32
                    verts.append((xplane,83.3+math.cos(a)*radius,-79.25+math.sin(a)*radius))
        faces=[]
        for i in range(32):
            j=(i+1)%32
            faces += [(i,j,32+j,32+i),(64+i,96+i,96+j,64+j),
                      (i,64+i,64+j,j),(32+i,32+j,96+j,96+i)]
        m.raw(verts,faces,'Tile',smooth=True)
        PREFABS[name]['exitBinding']=dict(component='ExitFlume',mouthComponent='ExitFlume_Tube_Mouth',
            referenceAnchorHallLocal=[123,83.3,-79.25],NoRotation=True)
    finish_prefab(m)


def straight_stairs(m,base,forward,width,count,run,rise,name):
    base,forward=v(base),v(forward)
    direction=unit(forward)
    for i in range(1,count+1):
        center=base+direction*((i-.5)*run)+v((0,i*rise-.35,0))
        # Exposed stair is shaped geometry; walkable simple box colliders.
        extrude(m,rectangle(0,0,width,.7),'Terrazzo',run+.05,center,frame(center,center+direction))
        yaw=math.degrees(math.atan2(-direction[0],-direction[2]))
        m.collider(f'L2K {name} Tread {i}',vec(center),(width,.7,run+.05),ground=True,yaw=yaw)
    side=unit(np.cross(direction,v((0,1,0))))
    for sign in (-1,1):
        rail(m,base+side*sign*(width/2+.15),base+forward*count*run+side*sign*(width/2+.15)+v((0,count*rise,0)))


def small_prefabs():
    for variant,(top,run) in enumerate(((4.5,12),(8,18)),1):
        name=f'SlideKit_{variant}';PREFABS[name]=dict(component=name,tubes=[],instances={})
        m=kit.Mesh(name,FixedVariant=variant,PadTop=top,ChuteRun=run)
        m.part('Level 2 Slide Kit Pad {i}',(0,top-.4,0),(8,.8,8),'Terrazzo',ground=True)
        for x,z in ((-3.2,-3.2),(3.2,-3.2),(-3.2,3.2),(3.2,3.2)):
            ht=top-.8+1.8
            m.cylinder((x,-1.8+ht/2,z),.55,ht,'Steel',segments=8)
            m.collider('L2K Pad Leg',(x,-1.8+ht/2,z),(1.1,ht,1.1))
        n=math.ceil((top+1.8)/.75)
        straight_stairs(m,(-4-n*1.5,-1.8,0),(1,0,0),6,n,1.5,(top+1.8)/n,'Kit')
        for sign in (-1,1):
            rail(m,(-3.8,top+.1,sign*3.8),(3.8,top+.1,sign*3.8))
        p0=v((3.6,top+2.75,0));p3=v((4+run,1.2,0))
        control=[p0,p0+v((run*.3,0,0)),p3-v((run*.28,0,0))+v((0,max(1.5,(p0[1]-p3[1])*.18),0)),p3]
        vis,col=make_slide_tube(control,24,10)
        key=make_tube(name,name+'_Chute','Level 2 Slide Kit Chute {i}',vis,col,2.6,'FibYellow',4.94)
        tub(m,key,vis,2.6,top,'FibYellow')
        m.marker('Pad',(0,top,0));finish_prefab(m)
    for variant,top in enumerate((10,14),1):
        name=f'PlayTower_{variant}';PREFABS[name]=dict(component=name,tubes=[],instances={})
        m=kit.Mesh(name,FixedVariant=variant,TopY=top)
        m.part('Level 2 Play Tower {i} Deck',(0,top-.5,0),(13,1,13),'Terrazzo',ground=True)
        n=math.ceil((top+1.8)/.85)
        straight_stairs(m,(-6.5-n*1.5,-1.8,0),(1,0,0),6,n,1.5,(top+1.8)/n,'Tower')
        rail(m,(-6,top+.1,-6.2),(6,top+.1,-6.2))
        for x,z in ((-5,-5),(5,-5),(-5,5),(5,5)):
            m.cylinder((x,(top-1.8)/2,z),.7,top+1.8,'Tile',segments=8)
            m.collider('L2K Tower Leg',(x,(top-1.8)/2,z),(1.4,top+1.8,1.4))
        control=[(0,top+4.4,6),(0,top+4.4,13.5),(-2,7.8,17),(-6,2.8,26)]
        vis,col=make_slide_tube(control,32,12)
        key=make_tube(name,name+'_Slide','Level 2 Play Tower {i} Slide',vis,col,4.2,'FibRed',8)
        tub(m,key,vis,4.2,top,'FibRed');m.marker('Deck',(0,top,0));finish_prefab(m)
    for mode,r,top,n,run,length,dw,dd,side_offset,stair_side,sw,lift,visual_n in (
        ('Nano',1.8,3.8,5,.8,10.5,8,5,2.5,4.3,4,.8,16),
        ('Micro',2.7,5.4,7,1.1,20,12,6,3.3,6,5,1.4,20),
        ('Compact',3.5,7.2,10,1.45,29,17,8,4.7,8.5,6.5,2.2,24),
        ('Full',4.1,8.5,12,1.7,39,20,9,5.4,10,7.5,2.2,28)):
        name=f'KidsSlide_{mode}';PREFABS[name]=dict(component=name,tubes=[],instances={})
        m=kit.Mesh(name,Level2_KidsSlideMode=mode,LongDimension=128)
        # Freeze the live centered entry formula, side=(-1,0,0), forward=+Z.
        landing=dict(Nano=4.5,Micro=7,Compact=9,Full=11)[mode]
        lateral=dict(Nano=2,Micro=3,Compact=4.2,Full=5)[mode]
        entry=v((lateral,0,(n*run-length-landing)/2))
        exit=entry+v((0,0,length))
        deck_center=entry+v((-side_offset,top-.4,0))
        m.part('Level 2 Kids Slide Landing Deck {i}',vec(deck_center),(dw,.8,dd),'Rubber',ground=True,
               attrs={'Level2_KidsSlideMode':mode})
        for side in (side_offset-dw/2+1,side_offset+dw/2-1):
            for z in (-dd/2+1,dd/2-1):
                pos=entry+v((-side,top/2,z))
                m.box(vec(pos),(1.4,top,1.4),'Rubber',bevel=.1)
                m.collider('L2K Kids Support',vec(pos),(1.4,top,1.4))
        base=entry+v((-stair_side,0,-n*run))
        straight_stairs(m,base,(0,0,1),sw,n,run,top/n,'Kids')
        p0=entry+v((0,top+r+.5,0));p3=exit+v((0,.58+.9*r,0))
        control=[p0,p0+v((0,0,length*.28)),p3+v((0,lift,-length*.30)),p3]
        vis,col=make_slide_tube(control,visual_n,10)
        key=make_tube(name,name+'_Slide','Level 2 Kids Slide {i}',vis,col,r,'FibBlue',1.9*r)
        SLIDES[key]['attrs']['Level2_KidsSlideMode']=mode
        sizes=dict(Nano=(6,.76,5),Micro=(10,.76,8),Compact=(12,.76,10),Full=(14,.76,12))
        ahead=dict(Nano=2,Micro=3,Compact=4,Full=5)[mode]
        m.part('Level 2 Kids Slide Landing Mat {i}',vec(exit+v((0,.38,ahead))),sizes[mode],'Rubber',ground=True)
        # Rear/side guards preserve the stair opening.
        guard_h=2.4 if mode=='Nano' else 3.2 if mode=='Micro' else 4.2
        inner=stair_side-sw/2-.5;left=side_offset-dw/2
        rw=max(2.5,inner-left)
        m.part('L2K Kids Rear Guard',vec(entry+v((-(left+rw/2),top-.1+guard_h/2,-dd/2+.5))),
               (rw,guard_h,.8),'Rubber')
        side_h=2.1 if mode=='Nano' else 2.8 if mode=='Micro' else 3.4
        m.part('L2K Kids Side Guard',vec(entry+v((-(side_offset+dw/2-.4),top+side_h/2-.1,0))),
               (.8,side_h,dd-1),'Rubber')
        m.marker('KidsEntry',vec(entry),Mode=mode);finish_prefab(m)


def path_at_x(points,x):
    for a,b in zip(points,points[1:]):
        if min(a[0],b[0])<=x<=max(a[0],b[0]):
            alpha=min(1,max(0,(x-a[0])/(b[0]-a[0]))) if abs(b[0]-a[0])>1e-4 else 0
            return a+(b-a)*alpha,unit(b-a)
    return points[-1],unit(points[-1]-points[-2])


def exit_prefab():
    name='ExitFlume';PREFABS[name]=dict(component=name,tubes=[],instances={},NoRotation=True)
    m=kit.Mesh(name,NoRotation=True)
    points,recycle,anchor=make_exit_flume()
    key=make_tube(name,'ExitFlume_Tube','Level 2 Exit Flume',points,points,8,'FibExit',closed=True)
    tub(m,key,points,8,75-anchor[1],'FibExit',True)
    tube=SLIDES[key]
    tube.update(anchor=vec(anchor),anchorRule='world (681,83.3,deckZ); translation only; do not add hall x to fixed world plunge',
        pathPoints=[vec(p) for p in points],plungeEndIndex=74,recycle=recycle,
        TransitionStart=vec(points[74]),TransitionEnd=vec(points[-1]),
        TransitionLength=sum(float(np.linalg.norm(b-a)) for a,b in zip(points[73:],points[74:])),
        leadIn=dict(stretchable=True,fromHallLocal=[98,83.3,-79.25],
            fromRule='(hall.MaxX-14,83.3,deckZ) minus anchor',to=[0,0,0],
            referenceMaxX=670,referenceLength=25,profile='SlideCol_Ring_r8',
            visualComponent=tube['visualChunks'][0],visualPlacement=tube['visualPlacements'][tube['visualChunks'][0]],
            scaleVisualSizeZ=True,updateCollisionSegment=1,moveTubWithMouth=True),sensorOffsets=[-26,-6])
    axis=unit(points[-1]-points[-2]);stop_pos=points[-1]+axis*.5
    stop=record_part(m,'Level 2 Exit Transition End Stop',vec(stop_pos),(2,18,18),
        'FibExit',look=axis,axis='X',properties=dict(CanQuery=False,CanTouch=False,CastShadow=False),
        attrs={'Level2_ExitTransitionEndStop':True})
    tube['endStopFrame']=stop['cframe'];tube['endStop']=stop
    sensors=[]
    for offset,label in ((-26,'Beam'),(-6,'Backstop')):
        point,direction=path_at_x(points,120+offset)
        rec=record_part(m,'Level 2 Exit Completion '+label,vec(point),(9,18,18),'FibExit',
            look=direction,axis='X',properties=dict(Transparency=1,CanQuery=False,CanTouch=False,CastShadow=False),
            collide=False,show=False,attrs=dict(Level2_ExitCompletionBeam=True,Level2_ExitCompletionSensorThickness=9))
        sensors.append(dict(offset=offset,part=rec))
    tube['sensors']=sensors
    top=-3.2-anchor[1];cx=801-7+39-anchor[0];cz=300
    m.part('Level 2 Recovery Chamber Floor',(cx,top-.75,cz),(78,1.5,78),'Terrazzo',ground=True)
    m.part('Level 2 Recovery Chamber Overhead Tile',(cx,top+30+.75,cz),(79.7,1.5,79.7),'Tile')
    for label,position,size in (
        ('North',(cx,top+15+.175,cz-39),(78,30.35,1.5)),
        ('South',(cx,top+15+.175,cz+39),(78,30.35,1.5)),
        ('East',(cx+39,top+15+.175,cz),(1.5,30.35,78)),
        ('West',(cx-39,top+15+.175,cz),(1.5,30.35,78))):
        m.part('Level 2 Recovery Chamber '+label+' Wall',position,size,'Tile')
    # Live story door, frame and safe spawn positions; compatible Service tints.
    door=v((cx+39-1.65,top+7,cz))
    m.part('Level 2 Exit Room Wooden Door',vec(door),(1.2,14,12),'ServiceGrey',attrs={'Level2_StoryDoor':True})
    for off,size in [((0,0,-6.6),(1.55,16,1.2)),((0,0,6.6),(1.55,16,1.2)),((0,7.6,0),(1.55,1.2,14.4))]:
        m.part('Level 2 Exit Room Door Frame',vec(door+v(off)),size,'ServiceGrey')
    safe=door+v((-4,-7+.12,0))
    record_part(m,'Level 2 Exit Safe Spawn',vec(safe),(8,.24,8),'Tile',collide=False,show=False,
                properties={'Transparency':1,'CanTouch':False},attrs={'Level2_ExitRecoverySpawn':True})
    tube['SafeSpawn']=vec(safe)
    bounds=np.array(points);padding=32
    tube['FlumeBoundsCenter']=vec((bounds.min(0)+bounds.max(0))/2)
    tube['FlumeBoundsSize']=vec(bounds.max(0)-bounds.min(0)+padding*2)
    for k,value in recycle.items():
        mapkey=dict(TriggerY='RecycleTriggerY',DeltaY='RecycleDeltaY',CenterX='HelixCenterX',
            CenterZ='HelixCenterZ',Radius='HelixRadius',TopY='HelixTopY',BottomY='HelixBottomY').get(k)
        if mapkey:
            tube['attrs']['Level2_'+mapkey]=value
    tube['attrs'].update(Level2_RecycleActive=True,Level2_FlumeBoreRadius=8)
    m.marker('PlungeStart',(0,0,0),AnchorWorld=vec(anchor),NoRotation=True)
    m.marker('ExitSafeSpawn',vec(safe));finish_prefab(m)


def build():
    """Register job F components; no export/render side effects when imported."""
    assert not PROFILES, 'build() is intended to run once per Blender process'
    gloss_materials();create_profiles()
    hall('SlideHall',208,176,76)
    hall('GrandSlideHall',224,208,96)
    exit_prefab();small_prefabs()
    return dict(slideProfiles=PROFILES,slides=SLIDES,prefabs=PREFABS,
                physicalProperties=PHYSICS,limitations=LIMITATIONS)


def independent_clip_reference(poly,r):
    """Intersection via half-plane line crossings, independent of clip()."""
    # Intersect all six lines, retain points inside the original box + clip domain.
    lines=[]
    for a,b in zip(poly,np.roll(poly,-1,axis=0)):
        edge=b-a;n=v((-edge[1],edge[0]));lines.append((n,float(n@a)))
    lines += [(v((0,1)),-.9*r),(v((1,0)),-.9*r),(v((-1,0)),-.9*r)]
    pts=[]
    for i,(na,da) in enumerate(lines):
        for nb,db in lines[i+1:]:
            mat=np.vstack((na,nb))
            if abs(np.linalg.det(mat))<1e-9:
                continue
            p=np.linalg.solve(mat,v((da,db)))
            if all(n@p>=d-1e-7 for n,d in lines) and not any(np.linalg.norm(p-q)<1e-7 for q in pts):
                pts.append(p)
    center=np.mean(pts,axis=0)
    return np.array(sorted(pts,key=lambda p:math.atan2(p[1]-center[1],p[0]-center[0])))


def close_vertices(a,b,tol=1e-3):
    assert len(a)==len(b),(len(a),len(b))
    errors=[min(np.linalg.norm(p-q) for q in b) for p in a]
    assert max(errors)<tol, (max(errors),vec(a[int(np.argmax(errors))]),vec(b[0]))


def decode_chunk(chunk):
    wire=(OUT/'chunks'/f"c{chunk['id']:05d}.b64").read_text()
    data=base64.b64decode(wire)
    assert hashlib.sha256(data).hexdigest()==chunk['sha256']
    counts=np.frombuffer(data,dtype='<u4',count=4)
    verts=np.frombuffer(data,dtype='<f4',count=int(counts[0])*3,offset=16).reshape(-1,3)
    return verts+v(chunk['center'])


def offline_check(manifest,data):
    """Read exported wire and JSON, rather than merely rechecking in-memory state."""
    checks=dict(templateVertexComparisons=0,segmentPieceComparisons=0,templates={},components={})
    chunks={}
    for c in manifest['chunks']:
        chunks.setdefault(c['component'],[]).append(c)
        assert c['tris']<=20000 and max(c['size'])<=1800
    for name,info in kit.COMPONENTS.items():
        mesh=info['mesh'];mesh.calc_loop_triangles()
        triangles=len(mesh.loop_triangles)
        checks['components'][name]=triangles
        if info['attrs'].get('Template') and triangles:
            assert triangles<=72,(name,triangles)
        # Every authored mesh shell is closed except deliberately uncapped column stripe sleeves.
        if name in PROFILES and triangles:
            edges={}
            for face in mesh.polygons:
                for edge in face.edge_keys:
                    edges[edge]=edges.get(edge,0)+1
            assert all(n==2 for n in edges.values()),name
    for name,p in data['slideProfiles'].items():
        if p['kind']=='CradleAssembly':
            assert sum(checks['components'][key] for key in p['children'])==204
            continue
        expected=[]
        for poly,d in zip(p['islands'],p['islandDepths']):
            expected += [[x,y,z] for z in (-d/2,d/2) for x,y in poly]
        expected=np.unique(np.round(expected,5),axis=0)
        actual=decode_chunk(chunks[name][0])
        close_vertices(actual,expected)
        checks['templateVertexComparisons']+=len(actual)
        checks['templates'][name]=dict(triangles=checks['components'][name],islands=len(p['islands']))
    for tube in data['slides'].values():
        pts=np.array(tube['collisionPoints'])
        for s in tube['segments']:
            a,b=pts[s['i']-1:s['i']+1]
            direction=unit(b-a);length=float(np.linalg.norm(b-a)+1.5)
            assert abs(length-s['len'])<1e-8
            assert np.linalg.norm(direction-v(s['dir']))<1e-8
            expected_boxes=live_boxes(tube['r'],tube['t'],s['guardHeight'],tube['kind']=='closed')
            for i in (1,2):
                original=expected_boxes[i].copy()
                expected_boxes[i]=independent_clip_reference(original,tube['r'])
                # Removed corners are contained in the existing floor/wall solids.
                r,t=tube['r'],tube['t']
                for x,y in original:
                    if y<-.9*r-1e-7 or abs(x)>.9*r+1e-7:
                        floor=abs(x)<=.775*r+1e-7 and -.9*r-t-1e-7<=y<=-.9*r+1e-7
                        wall=.9*r-1e-7<=abs(x)<=.9*r+t+1e-7 and y>=-.9*r-1e-7
                        assert floor or wall,(r,t,x,y)
            offset=0
            for piece in s['pieces']:
                p=data['slideProfiles'][piece['profile']]
                actual=decode_chunk(chunks[piece['profile']][0])
                center=v(p['axisOffset'])
                local=actual-center
                local[:,2]*=length
                if p['kind']=='Guard':
                    local[:,1]*=s['guardHeight']
                transform=np.column_stack((piece['cframe']['right'],piece['cframe']['up'],piece['cframe']['back']))
                actual_world=local@transform.T+v(piece['cframe']['position'])
                island_count=len(p['islands'])
                expected_local=np.array([[x,y,z] for polygon in expected_boxes[offset:offset+island_count]
                    for z in (-length/2,length/2) for x,y in polygon])
                expected_world=expected_local@frame(a,b).T+(a+b)/2
                expected_world=np.unique(np.round(expected_world,7),axis=0)
                close_vertices(actual_world,expected_world)
                checks['segmentPieceComparisons']+=1
                offset+=island_count
        if tube.get('tub'):
            tubdata=tube['tub'];r=tube['r'];length=tubdata['entryLength']+.35
            direction=unit(v(tubdata['toward'])-v(tubdata['mouth']));direction[1]=0;direction=unit(direction)
            side=v((-direction[2],0,direction[0]));support=v(tubdata['mouth'])-direction*tubdata['entryLength']/2
            expected=[];step=math.radians(226)/16;thick=.085*r
            tang=2*1.085*r*math.sin(step/2)+.08
            for i in range(16):
                angle=math.radians(157)+(i+.5)*step
                radial=side*math.cos(angle)+v((0,1,0))*math.sin(angle)
                tangent=np.cross(direction,radial)
                center=support+radial*1.0425*r
                expected.append(np.array([center+direction*x+radial*y+tangent*z
                    for x in (-(length-.16)/2,(length-.16)/2)
                    for y in (-thick/2,thick/2) for z in (-tang/2,tang/2)]))
            bt=min(.55,max(.28,.065*r));base=support.copy()
            base[1]=max(tubdata['deckTop']+.08,support[1]-r+.03)-bt/2
            f=frame(support,support+direction)
            expected.append(np.array([base+f@v((x,y,z)) for x in (-1.075*r,1.075*r)
                for y in (-bt/2,bt/2) for z in (-length/2,length/2)]))
            index=0
            for piece in tubdata['collisionPlacements']:
                p=data['slideProfiles'][piece['profile']]
                actual=decode_chunk(chunks[piece['profile']][0])-v(p['axisOffset'])
                actual[:,2]*=length
                transform=np.column_stack((piece['cframe']['right'],piece['cframe']['up'],piece['cframe']['back']))
                actual=actual@transform.T+v(piece['cframe']['position'])
                n=len(p['islands']);wanted=np.vstack(expected[index:index+n])
                try:
                    close_vertices(actual,np.unique(np.round(wanted,7),axis=0))
                except AssertionError as error:
                    raise AssertionError((tube['prefab'],piece['profile'],str(error))) from error
                index+=n
                checks['segmentPieceComparisons']+=1
            assert index==17
    exit_tube=data['slides']['ExitFlume_Tube'];pts=np.array(exit_tube['pathPoints'])
    anchor_y=exit_tube['anchor'][1]
    assert len(pts)==272 and len(exit_tube['segments'])==271
    segments=exit_tube['segments']
    centers=np.array([s['pieces'][0]['cframe']['position'] for s in segments])
    sensor=v(exit_tube['sensors'][0]['part']['cframe']['position'])
    start=int(np.argmin(np.linalg.norm(centers-sensor,axis=1)))
    grades=[-s['dir'][1] for s in segments[start:]]
    assert min(grades)>.12 and all(s['oneWay'] for s in segments[start:])
    lengths=np.array([s['len'] for s in segments])
    overlaps=np.linalg.norm(np.diff(centers[start:],axis=0),axis=1)-(lengths[start:-1]+lengths[start+1:])/2
    assert max(overlaps)<=0
    measured=float(np.linalg.norm(np.diff(centers[start:],axis=0),axis=1).sum())
    assert measured/105>15
    assert exit_tube['TransitionLength']>=2000
    assert abs(exit_tube['TransitionLength']-measured)<measured*.35
    lowest=float(centers[:,1].min()+anchor_y);assert lowest>-460
    stops=[p for p in data['prefabParts']['ExitFlume'] if p['attrs'].get('Level2_ExitTransitionEndStop')]
    assert len(stops)==1 and stops[0]['collide']
    stop=stops[0];f=stop['cframe'];transform=np.column_stack((f['right'],f['up'],f['back']))
    local=transform.T@(pts[-1]-v(f['position']))
    assert np.all(np.abs(local)<=v(stop['size'])/2+.01)
    recycle=exit_tube['recycle'];assert recycle['Turns']>=3
    assert abs(recycle['TriggerY']+recycle['DeltaY']-recycle['LandingY'])<1e-6
    assert recycle['LandingY']<=recycle['TopY']+1e-6
    seam=0;checked=0
    for p in pts:
        if recycle['BottomY']-.001<=p[1]<=recycle['TriggerY']+.001:
            error=float(np.linalg.norm(pts-(p+v((0,recycle['DeltaY'],0))),axis=1).min())
            seam=max(seam,error);checked+=1
    assert checked and seam<.5
    assert recycle['BottomY']+anchor_y>-460
    margin=recycle['TriggerY']-recycle['DeltaY']*.5-recycle['BottomY'];assert margin>40
    chamber=[p for p in data['prefabParts']['ExitFlume'] if 'Recovery Chamber' in p['name']]
    assert len(chamber)>=6
    distance=float(np.linalg.norm(centers-v(exit_tube['SafeSpawn']),axis=1).min());assert distance>40
    for s in exit_tube['sensors']:
        p=s['part'];assert p['size']==[9,18,18] and not p['collide']
        assert p['attrs']['Level2_ExitCompletionSensorThickness']==9 and p['attrs']['Level2_ExitCompletionBeam']
        assert p['properties']['Transparency']==1 and not p['properties']['CanTouch'] and not p['properties']['CanQuery']
    checks['exit']=dict(pathPoints=272,sensorFloorIndex=start+1,minimumGrade=min(grades),
        worstOverlap=float(max(overlaps)),measuredTransitionLength=measured,
        declaredTransitionLength=exit_tube['TransitionLength'],secondsAtCap=measured/105,
        lowestFloorWorldY=lowest,recycleSeam=seam,recyclePointsChecked=checked,
        BottomWorldY=recycle['BottomY']+anchor_y,backstopMargin=margin,recoveryDistance=distance,
        recoveryShellParts=len(chamber),endStopLocalEnd=vec(local))
    for name,prefab in data['prefabs'].items():
        visual=sum(len(chunks.get(component,[])) for key in prefab['tubes'] for component in data['slides'][key]['visualChunks'])
        visual+=len(chunks.get(name,[]))
        collision=sum(sum(len(s['pieces']) for s in data['slides'][key]['segments'])+
            len(data['slides'][key].get('tub',{}).get('collisionPlacements',[])) for key in prefab['tubes'])
        parts=len(data['prefabParts'][name])+len(data['prefabColliders'][name])
        prefab['instances']=dict(visualMeshParts=visual,collisionMeshParts=collision,
                                parts=parts,total=visual+collision+parts)
        print('F_INSTANCES '+name+' '+json.dumps(prefab['instances']),flush=True)
    # Same inventory as the reader's 4,873 baseline; tubes/tubs only, apples to apples.
    inventory=[('SlideHall',2),('GrandSlideHall',1),('ExitFlume',1),('SlideKit_1',8),('PlayTower_1',2),('KidsSlide_Full',1)]
    collision_total=1;today=1;total=0  # The terminal end stop is the baseline's 4,873rd part.
    for name,count in inventory:
        prefab=data['prefabs'][name]
        collision_total+=count*prefab['instances']['collisionMeshParts']
        total+=count*prefab['instances']['total']
        for key in prefab['tubes']:
            tube=data['slides'][key]
            collision_total+=count*(1 if tube.get('tub') else 0)
            today+=count*(len(tube['segments'])*(6 if tube['kind']=='closed' else 5)+(18 if tube.get('tub') else 0))
    # The grand hall in live inventory has three flumes but no hall helix in that count.
    grand_helix=data['slides']['GrandSlideHall_Helix']
    collision_total-=48*2+4;today-=48*5+18
    checks['inventory']=dict(todayCollisionParts=today,quotedBaseline=4873,
        rebuiltCollisionInstances=collision_total,saved=today-collision_total,
        reductionPercent=100*(today-collision_total)/today,
        baselineNote='9 flumes, 2 hall helices, exit, 22 tubs, 8 kits, 2 towers, 1 kids slide; excludes 271 old modifiers.',
        allPrefabInstancesForInventory=total,
        prefabNote='Includes shell/stairs/supports; subtract grand helix for the collision baseline only.')
    # Hall-only target includes parts; this check exposes whether the source stairs dominate it.
    checks['hallBucketAllInstances']=sum(data['prefabs'][name]['instances']['total']*n for name,n in [('SlideHall',2),('GrandSlideHall',1),('ExitFlume',1)])
    slide_bucket=0
    for name,count in [('SlideHall',2),('GrandSlideHall',1),('ExitFlume',1)]:
        for key in data['prefabs'][name]['tubes']:
            tube=data['slides'][key]
            slide_bucket+=count*(sum(len(s['pieces']) for s in tube['segments'])+
                sum(len(chunks[c]) for c in tube['visualChunks'])+
                (4 if tube.get('tub') else 0))
    slide_bucket+=1 # terminal end stop
    assert slide_bucket<=1500,slide_bucket
    checks['hallSlideGeometryBucket']=slide_bucket
    checks['hallShellStairsSupportsBucket']=checks['hallBucketAllInstances']-slide_bucket
    checks['limitations']=LIMITATIONS
    checks['status']='offline structural checks passed; runtime verification pending'
    print('F_CHECKS '+json.dumps({k:val for k,val in checks.items() if k not in ('components','templates')}),flush=True)
    return checks


def review_collection(name):
    col=bpy.data.collections.new(name);bpy.context.scene.collection.children.link(col)
    return col


def place_prefab(col,name,position=(0,0,0)):
    kit.place(col,name,position)
    for key in PREFABS[name]['tubes']:
        for component in SLIDES[key]['visualChunks']:
            ob=kit.place(col,component,position)
            placement=SLIDES[key].get('visualPlacements',{}).get(component)
            if placement:
                f=placement['cframe']
                rotation=np.column_stack((f['right'],f['up'],f['back']))
                matrix=Matrix((kit.C.T@rotation@kit.C).tolist()).to_4x4()
                matrix=matrix@Matrix.Diagonal((1,placement['scaleZ'],1,1))
                matrix.translation=kit.to_blender(v(position)+v(f['position']))
                ob.matrix_world=matrix


def light(col,position,target,power,size=30,color=(1,.88,.72)):
    data=bpy.data.lights.new('F_Area','AREA');data.energy=power;data.shape='DISK';data.size=size
    data.color=color
    obj=bpy.data.objects.new('F_Area',data);col.objects.link(obj)
    obj.location=kit.to_blender(position)
    obj.rotation_euler=(kit.to_blender(target)-obj.location).to_track_quat('-Z','Y').to_euler()


def render(col,name,eye,target,ortho=None):
    sc=bpy.context.scene
    for collection in sc.collection.children:
        collection.hide_render=collection!=col
    camdata=bpy.data.cameras.new('F_Camera');cam=bpy.data.objects.new('F_Camera',camdata);col.objects.link(cam)
    sc.camera=cam;cam.location=kit.to_blender(eye)
    cam.rotation_euler=(kit.to_blender(target)-cam.location).to_track_quat('-Z','Y').to_euler()
    camdata.lens=23 if ortho is None else 50
    camdata.clip_end=2000
    if ortho:
        camdata.type='ORTHO';camdata.ortho_scale=ortho*kit.S
    sc.render.filepath=str(REVIEW/(name+'.png'))
    bpy.ops.render.render(write_still=True)
    col.objects.unlink(cam);bpy.data.objects.remove(cam)


def renders():
    REVIEW.mkdir(parents=True,exist_ok=True)
    sc=bpy.context.scene
    sc.render.engine='BLENDER_EEVEE'
    sc.render.resolution_x=1400;sc.render.resolution_y=900;sc.render.resolution_percentage=100
    sc.render.image_settings.file_format='PNG'
    sc.render.film_transparent=False
    sc.world=bpy.data.worlds.new('F_World');sc.world.use_nodes=True
    sc.world.node_tree.nodes['Background'].inputs['Color'].default_value=(.32,.40,.48,1)
    sc.world.node_tree.nodes['Background'].inputs['Strength'].default_value=.6
    sc.view_settings.view_transform='AgX'
    for name,eye,target in (
        ('SlideHall_Deck',(-78,66,-53),(16,32,20)),
        ('SlideHall_Pool',(-67,9,64),(20,43,-15)),
        ('GrandSlideHall_Exit',(70,81,-49),(107,83.3,-79.25))):
        prefab='GrandSlideHall' if name.startswith('Grand') else 'SlideHall'
        col=review_collection(name);place_prefab(col,prefab)
        if prefab=='GrandSlideHall':
            for component in ('ExitFlume_Tube_Mouth','ExitFlume_Tube_Handles'):
                kit.place(col,component,(123,83.3,-79.25))
            lead=kit.Mesh('F_Review_ExitLead')
            sweep(lead,[v((98,83.3,-79.25)),v((125,83.3,-79.25))],8,'FibExit',True)
            # Review-only mesh, never registered/exported.
            ob=bpy.data.objects.new('Review exit lead',lead.finish(register=False));col.objects.link(ob)
        h=96 if prefab=='GrandSlideHall' else 76
        light(col,(-45,h-5,-30),(0,20,0),18000,26)
        light(col,(65,h-7,-70),(25,45,10),24000,24,(.72,.88,1))
        light(col,(0,35,60),(0,15,-20),14000,20)
        light(col,(-70,15,25),(35,35,-20),8000,18)
        render(col,name,eye,target)
    col=review_collection('ExitFlume_Whole');place_prefab(col,'ExitFlume',(0,83.3,0))
    light(col,(100,250,150),(280,-120,-70),50000,80)
    light(col,(600,50,-160),(260,-150,-80),50000,100,(.7,.85,1))
    sun=bpy.data.objects.new('F_Sun',bpy.data.lights.new('F_Sun','SUN'));col.objects.link(sun)
    sun.data.energy=2;sun.rotation_euler=(.4,-.6,.3)
    render(col,'ExitFlume_Whole',(670,150,750),(210,-165,30),ortho=1050)
    # One short cut specimen; source unit templates shown as actual islands in wireframe.
    col=review_collection('Flume_Collision_Cut')
    specimen=kit.Mesh('F_Cut_Specimen')
    sweep(specimen,[v((0,0,-5)),v((0,0,5))],7.5,'FibGreen')
    obj=bpy.data.objects.new('Cut visual',specimen.finish(register=False));col.objects.link(obj)
    for kind in ('Floor','Guard'):
        component=f'SlideCol_{kind}_r7.5'
        ob=kit.place(col,component)
        # Unit guard stretches about its bottom, not about the tube axis.
        ob.data=ob.data.copy()
        for vertex in ob.data.vertices:
            rp=kit.C@np.array(vertex.co)/kit.S
            rp[2]*=10
            if kind=='Guard':
                rp[1]=-.9*7.5+(rp[1]+.9*7.5)*14
            vertex.co=kit.to_blender(rp)
        mod=ob.modifiers.new('Convex island edges','WIREFRAME');mod.thickness=.012
        mod.use_replace=True
    light(col,(-18,25,12),(0,0,0),1500,10)
    light(col,(15,10,-20),(0,0,0),1400,8,(.7,.85,1))
    render(col,'Flume_Collision_Cut',(18,15,30),(0,0,0),ortho=36)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    data=build();kit.EXPORT_DIR=OUT
    manifest=kit.export()
    for name,p in PROFILES.items():
        p['chunks']=kit.COMPONENTS[name]['chunks']
    data['prefabParts']={name:kit.COMPONENTS[name]['parts'] for name in PREFABS}
    data['prefabColliders']={name:kit.COMPONENTS[name]['colliders'] for name in PREFABS}
    data['prefabMarkers']={name:kit.COMPONENTS[name]['markers'] for name in PREFABS}
    data['sourceReference']=dict(path=str(SOURCE),sha256=hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
                                authority='offline repository snapshot only')
    data['runtimeInstructions']=[
        'Create collision templates with PreciseConvexDecomposition before cloning; no Box fidelity.',
        'Wire chunks are centered; use exported per-piece cframe/size. Floor/Ring only scale Z. Guard scales Y and Z.',
        'Apply properties and attributes; rotate SlideDirection from final CFrame.LookVector after prefab placement.',
        'Instantiate cradle children with recorded size/CFrame; entry floor stays a Part.',
        'Exit uses plungeStart world anchor (681,83.3,deckZ), never yaw. Add anchor Y to recycle values and X/Z to centers.',
        'Stretch the unit LeadVisual along its local Z; update its pose, collision segment 1 and tub/apron translation from actual hall.MaxX; retain indices 1..272.',
        'Exit Mouth is tub mouthComponent; recoloring that one component must not recolor the tube shell.',
        'Use full Part cframe fields where present; kit part cf contains only yaw and cannot express sensor/end-stop tilt.',
        'Remove connector plugs only after a connected module closes the socket. Create Terrain water from marker, never mesh water.',
    ]
    path=OUT/'slides.json';path.write_text(json.dumps(data,indent=1),encoding='utf-8')
    # Parse the written schema and wire; no stale in-memory shortcuts in the checker.
    checked_data=json.loads(path.read_text(encoding='utf-8'))
    checks=offline_check(json.loads((OUT/'manifest.json').read_text()),checked_data)
    data['prefabs']=checked_data['prefabs']
    path.write_text(json.dumps(data,indent=1),encoding='utf-8')
    manifest['slideProfiles']=PROFILES;manifest['slides']=SLIDES;manifest['prefabs']=data['prefabs']
    (OUT/'manifest.json').write_text(json.dumps(manifest,indent=1),encoding='utf-8')
    (OUT/'checks.json').write_text(json.dumps(checks,indent=1),encoding='utf-8')
    report=['# Job F: offline slide kit',
        '', 'Run the command in slides.py. No git, Studio, MCP, GUI Blender, publication or import was used.',
        '', f"Export: {len(manifest['components'])} components, {len(manifest['chunks'])} one-material chunks, "
        f"{sum(c['tris'] for c in manifest['chunks']):,} authored triangles (templates counted once).",
        '', '## Validation', '',
        f"{checks['templateVertexComparisons']} exported template vertices checked; "
        f"{checks['segmentPieceComparisons']} scaled segment/cradle pieces checked against the live box formulas.",
        '', 'Exit structural results: '+json.dumps(checks['exit']),
        '', 'Collision comparison: '+json.dumps(checks['inventory']),
        '', f"Two SlideHalls + GrandSlideHall + ExitFlume: {checks['hallBucketAllInstances']} instances total; "
        f"{checks['hallSlideGeometryBucket']} are slide geometry, {checks['hallShellStairsSupportsBucket']} shell/stairs/supports. "
        'The full total exceeds 1,500 if that budget is interpreted to include the architectural shell.',
        '', '## Prefab instance counts', '',
        '| Prefab | Visual MeshParts | Collision MeshParts | Parts/colliders | Total |',
        '|---|---:|---:|---:|---:|']
    for name,prefab in data['prefabs'].items():
        p=prefab['instances']
        report.append(f"| {name} | {p['visualMeshParts']} | {p['collisionMeshParts']} | {p['parts']} | {p['total']} |")
    report += ['', 'Marker records and Model/Folder containers are not included in these BasePart totals.',
               '', '## Component triangles', '', '| Component | Triangles |', '|---|---:|']
    report += [f'| {name} | {count} |' for name,count in checks['components'].items()]
    report += ['', '## Deviations, ambiguities and unverified checks', '']
    report += ['- '+item for item in LIMITATIONS]
    report += ['', 'The 1-stud exit upper-corner collision slots are preserved. Floor/chamfer groups '
               'and guard groups stay separate on every open slide. No kit.py bug was found; full '
               'sensor/end-stop frames are an additional record field because the foundation supports yaw only.',
               '', '## Files', '', '- slides.py in the repository tools directory',
               '- manifest.json, slides.json, checks.json, review.json, REPORT.md in this export directory',
               '- chunks/c00000.b64 through chunks/c00119.b64 (manifest hashes are authoritative)',
               '- Five PNG review images under G:/Blender/Level2_Pool/review/F/']
    (OUT/'REPORT.md').write_text('\n'.join(report)+'\n',encoding='utf-8')
    renders()
    (OUT/'review.json').write_text(json.dumps(dict(images=[str(REVIEW/(n+'.png')) for n in
        ('SlideHall_Deck','SlideHall_Pool','GrandSlideHall_Exit','ExitFlume_Whole','Flume_Collision_Cut')],
        renderEngine='BLENDER_EEVEE',runtimeChecks='pending'),indent=1),encoding='utf-8')
    print('JOB_F_OK',flush=True)


if __name__=='__main__':
    main()
