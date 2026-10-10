"""Generated Poolrooms shadow anatomy. No external assets; Blender Z up, front -Y."""
import bpy
import math
import json
import hashlib
import sys
from pathlib import Path
from collections import Counter, defaultdict
from mathutils import Vector
OUT = Path(__file__).resolve().parents[2] / 'artifacts' / 'level2-shade-20261010'
TAU = 2 * math.pi
LIMITS = dict(Shade_Stand=7000, Shade_Reach=7000, Shade_Crawl=7000, Shade_Rise=7000,
              Shade_Claw=2500, Shade_Arm=2200, Shade_ArmGrip=2200, Shade_Hands=3000, Shade_Pool=900)
HEIGHTS = dict(Shade_Stand=11, Shade_Reach=11, Shade_Crawl=15.5, Shade_Rise=6.5,
               Shade_Claw=7, Shade_Arm=9.5, Shade_Hands=8)
def volume(vertices, faces):
    return sum(Vector(vertices[a]).dot(Vector(vertices[b]).cross(Vector(vertices[c])))
               for a, b, c in faces) / 6


class Geometry:
    def __init__(self):
        self.vertices, self.faces, self.colours = [], [], []

    def shell(self, vertices, faces, colour):
        assert volume(vertices, faces) != 0
        if volume(vertices, faces) < 0:
            faces = [(a, c, b) for a, b, c in faces]
        offset = len(self.vertices)
        self.vertices.extend(vertices)
        self.faces.extend(tuple(offset + i for i in f) for f in faces)
        self.colours.extend([colour] * len(vertices))


def topology(vertices, faces, label):
    edges = Counter()
    touching = defaultdict(list)
    normals = []
    for fi, (a, b, c) in enumerate(faces):
        assert len({a, b, c}) == 3, (label, 'repeated triangle index')
        cross = (Vector(vertices[b]) - Vector(vertices[a])).cross(Vector(vertices[c]) - Vector(vertices[a]))
        assert cross.length > 1e-8, (label, 'degenerate triangle', fi)
        normals.append(cross.normalized())
        for u, v in ((a, b), (b, c), (c, a)):
            edges[(u, v)] += 1
            touching[tuple(sorted((u, v)))].append(fi)
    assert all(n == 1 and edges[(v, u)] == 1 for (u, v), n in edges.items()), (label, 'edge direction / manifold')
    assert all(len(f) == 2 for f in touching.values())
    adjacent = defaultdict(list)
    for a, b in touching.values():
        adjacent[a].append(b)
        adjacent[b].append(a)
    unseen, component_volumes = set(range(len(faces))), []
    while unseen:
        seed = min(unseen)
        unseen.remove(seed)
        stack, found = [seed], []
        while stack:
            fi = stack.pop()
            found.append(faces[fi])
            for other in adjacent[fi]:
                if other in unseen:
                    unseen.remove(other)
                    stack.append(other)
        signed = volume(vertices, found)
        assert signed > 1e-9, (label, 'inward component', signed)
        component_volumes.append(round(signed, 9))
    # Every vertex link must form one cycle: rejects bow-tie vertices.
    incident = defaultdict(list)
    for a, b, c in faces:
        incident[a].append((b, c)); incident[b].append((c, a)); incident[c].append((a, b))
    for v, pairs in incident.items():
        link = defaultdict(set)
        for a, b in pairs:
            link[a].add(b); link[b].add(a)
        assert all(len(x) == 2 for x in link.values()), (label, 'nonmanifold vertex', v)
        seen, todo = set(), [next(iter(link))]
        while todo:
            a = todo.pop()
            if a not in seen:
                seen.add(a); todo.extend(link[a] - seen)
        assert len(seen) == len(link), (label, 'disconnected vertex link')
    return normals, component_volumes



def catmull(a, b, c, d, t):
    return .5 * ((2*b) + (-a+c)*t + (2*a-5*b+4*c-d)*t*t + (-a+3*b-3*c+d)*t*t*t)


def tube(g, controls, sides=12, steps=3, reference=(1,0,0)):
    """Centrally capped, elliptic, smooth swept closed shell; zero radius = unique tip."""
    pts, radii = [], []
    for j in range(len(controls)-1):
        a,b,c,d = [Vector(controls[max(0,min(len(controls)-1,k))][:3]) for k in (j-1,j,j+1,j+2)]
        for k in range(steps):
            t=k/steps
            pts.append(catmull(a,b,c,d,t))
            radii.append(tuple(controls[j][q]*(1-t)+controls[j+1][q]*t for q in (3,4)))
    pts.append(Vector(controls[-1][:3])); radii.append(controls[-1][3:5])
    vertices, rings, faces = [], [], []
    for j,(p,rs) in enumerate(zip(pts,radii)):
        tangent=(pts[min(j+1,len(pts)-1)]-pts[max(0,j-1)]).normalized()
        ref=Vector(reference)
        if abs(ref.dot(tangent))>.96: ref=Vector((0,1,0))
        u=(ref-tangent*ref.dot(tangent)).normalized(); v=tangent.cross(u).normalized()
        ring=[]
        for k in range(sides if min(rs)>0 else 1):
            theta=TAU*k/sides
            ring.append(len(vertices))
            vertices.append(tuple(p+(u*rs[0]*math.cos(theta)+v*rs[1]*math.sin(theta)) if min(rs)>0 else p))
        rings.append(ring)
    for a,b in zip(rings,rings[1:]):
        for j in range(sides):
            k=(j+1)%sides
            if len(a)==1: faces.append((a[0],b[k],b[j]))
            elif len(b)==1: faces.append((a[j],a[k],b[0]))
            else: faces.extend(((a[j],a[k],b[k]),(a[j],b[k],b[j])))
    for ring,reverse in ((rings[0],True),(rings[-1],False)):
        if len(ring)>1:
            centre=len(vertices); vertices.append(tuple(pts[0] if reverse else pts[-1]))
            for j in range(sides):
                a,b=ring[j],ring[(j+1)%sides]
                faces.append((centre,b,a) if reverse else (centre,a,b))
    g.shell(vertices,faces,(1,1,1))


def ellipsoid(g, centre, radius, tilt=0):
    # Rounded oval with unique poles, twenty sides and twelve latitude stations.
    v=[(0,0,-radius[2])]; rings=[[0]]
    for j in range(1,12):
        a=math.pi*j/12
        ring=[]
        for k in range(20):
            b=TAU*k/20; ring.append(len(v))
            v.append((radius[0]*math.sin(a)*math.cos(b),radius[1]*math.sin(a)*math.sin(b),-radius[2]*math.cos(a)))
        rings.append(ring)
    rings.append([len(v)]); v.append((0,0,radius[2]))
    faces=[]
    for p,q in zip(rings,rings[1:]):
        for j in range(20):
            k=(j+1)%20
            if len(p)==1: faces.append((p[0],q[j],q[k]))
            elif len(q)==1: faces.append((p[j],q[0],p[k]))
            else: faces.extend(((p[j],q[j],q[k]),(p[j],q[k],p[k])))
    v=[(centre[0]+x*math.cos(tilt)+z*math.sin(tilt),centre[1]+y,
        centre[2]-x*math.sin(tilt)+z*math.cos(tilt)) for x,y,z in v]
    g.shell(v,faces,(1,1,1))


def hand(g,wrist,direction=(0,0,1),width_axis=(1,0,0),scale=.65,grip=False,inner_factor=1):
    """Four digit rays and an opposable thumb: five independent tapered closed shells."""
    w=Vector(wrist); v=Vector(direction).normalized(); u=Vector(width_axis).normalized()
    u=(u-v*u.dot(v)).normalized(); depth=v.cross(u)
    # Keep palm front towards -Y whenever its orientation permits it.
    if depth.y>0: depth=-depth
    def p(x,z,d=0): return tuple(w+scale*(x*u+z*v+d*depth))
    def station(x,z,d,r,t): return (*p(x,z,d),r*scale,t*scale)
    tube(g,[station(0,-.16,0,.17,.12),station(0,.18,0,.30,.14),
            station(0,.48,0,.40,.16),station(0,.66,0,.35,.13),station(0,.74,0,.25,.08),
            station(0,.78,0,0,0)],12,2,tuple(u))
    specifications=[(-.31,-.85,1.63),(-.11,-.30,1.98),(.12,.30,1.86),(.32,.85,1.53)]
    for j,(root,tip,length) in enumerate(specifications):
        if tip>0: tip*=inner_factor
        if grip:
            controls=[station(root,.58,0,.095,.085),station(tip*.65,1.04,.05,.088,.075),
                      station(tip*.78,1.28,.36,.07,.065),station(tip*.80,.98,.76,.05,.045),
                      station(tip*.74,.62,.70,0,0)]
        else:
            controls=[station(root,.58,0,.095,.08),station(root+(tip-root)*.38,.95,0,.085,.073),
                      station(tip*.92,length-.26,.06,.048,.045),station(tip,length,.13,0,0)]
        tube(g,controls,8,3,tuple(u))
    if grip:
        controls=[station(-.24,.20,0,.13,.10),station(-.78,.44,.12,.105,.08),
                  station(-.87,.83,.40,.07,.06),station(-.55,.76,.65,0,0)]
    else:
        controls=[station(-.24,.20,0,.13,.10),station(-.68,.40,0,.10,.085),
                  station(-1.08,.76,.04,.06,.05),station(-1.17,.96,.12,0,0)]
    tube(g,controls,8,3,tuple(u))


def body(g, twist=False):
    tube(g,[(0,-.53,5.05,0,0),(0,-.53,5.42,.57,.38),(0,-.54,5.95,.51,.36),
            (0,-.57,6.75,.39,.29),(0,-.60,7.7,.49,.36),
            (.06 if twist else 0,-.62,8.55,.72,.44),(0,-.59,8.94,.79,.37),
            (0,-.58,9.25,.30,.24),(0,-.57,9.34,0,0)],20,2)
    tube(g,[(0,-.59,8.98,.23,.20),(0,-.62,9.6,.19,.18),(.03,-.71,10.05,.20,.19)],12,3)
    ellipsoid(g,(.035,-.78,10.32),(.40,.42,.68),-.08)
    for s in (-1,1):
        tube(g,[(s*.28,-.53,5.90,.22,.23),(s*.39,-.51,5.22,.30,.29),(s*.43,-.50,4.6,.29,.28),
                (s*.49,-.55,3.08,.23,.24),(s*.54,-.52,1.45,.18,.21),
                (s*.60,-.63,.30,.16,.22),(s*.63,-.82,.13,.22,.32),
                (s*.63,-.84,0,0,0)],14,3)


def hanging(g,s):
    tube(g,[(s*.60,-.62,8.82,.18,.19),(s*1.02,-.61,8.3,.205,.20),
            (s*1.28,-.58,6.7,.16,.17),(s*1.41,-.57,5.25,.13,.14),
            (s*1.58,-.59,4.10,.115,.12)],12,3)
    hand(g,(s*1.58,-.59,4.1),(0,0,-1),(s,0,0),.67)


def standing(pose):
    g=Geometry(); body(g,pose=='reach')
    if pose=='stand':
        hanging(g,-1); hanging(g,1)
    elif pose=='reach':
        hanging(g,-1)
        tube(g,[(.58,-.64,8.82,.18,.19),(1.48,-.68,8.90,.21,.20),
                (2.65,-.76,9.05,.17,.17),(3.62,-.78,9.25,.13,.14),
                (4.16,-.78,9.34,.12,.12)],12,3,reference=(0,0,1))
        hand(g,(4.16,-.78,9.34),(1,0,.08),(0,0,1),.67)
    else:
        for s in (-1,1):
            tube(g,[(s*.60,-.62,8.82,.18,.19),(s*.99,-.62,9.45,.20,.20),
                    (s*1.03,-.61,11.1,.16,.17),(s*.86,-.59,12.8,.13,.14),
                    (s*.80,-.60,14.1,.12,.12)],12,3)
            # Thumbs point outward so they cannot merge in the central slot.
            hand(g,(s*.80,-.60,14.1),(0,0,1),(-s,0,0),.70)
    return g


def rise():
    g=Geometry()
    tube(g,[(0,-.46,0,.46,.35),(0,-.48,.7,.43,.32),(0,-.52,1.8,.39,.29),
            (0,-.58,3,.51,.37),(0,-.61,4.1,.74,.40),(0,-.61,4.55,.29,.24),
            (0,-.60,4.7,0,0)],20,3)
    tube(g,[(0,-.62,4.25,.22,.20),(0,-.64,5.2,.17,.18),(0,-.72,5.6,.19,.18)],12,3)
    ellipsoid(g,(.16,-.76,6.03),(.40,.41,.69),.23)
    waist_indices={i for i,p in enumerate(g.vertices) if abs(p[2])<1e-7}
    angle=math.radians(35)
    g.vertices=[(x,y*math.cos(angle)-z*math.sin(angle),y*math.sin(angle)+z*math.cos(angle)) for x,y,z in g.vertices]
    # Closed waist cut stays on Z=0. Uniform upper-body scaling preserves the 35-degree lean.
    low=min(p[2] for p in g.vertices); high=max(p[2] for p in g.vertices)
    factor=6.5/(high-low)
    g.vertices=[(x*factor,y*factor,0 if i in waist_indices else (z-low)*factor) for i,(x,y,z) in enumerate(g.vertices)]
    assert all(g.vertices[i][2]==0 for i in waist_indices), 'Horizontal closed waist cut'
    for s in (-1,1):
        shoulder=(s*.66,-3.22,4.32)
        tube(g,[(*shoulder,.23,.23),(s*1.12,-3.55,4.3,.20,.20),
                (s*1.55,-4.00,3.92,.16,.17),(s*1.82,-4.05,3.90,.12,.13)],12,3)
        hand(g,(s*1.82,-4.05,3.90),(0,-.75,-.66),(s,0,0),.68)
    return g


def arm(grip=False):
    g=Geometry(); angle=math.radians(55 if grip else 20)
    wrist=(0,-.40-3.4*math.sin(angle),4.2+3.4*math.cos(angle))
    tube(g,[(0,-.40,0,.28,.28),(0,-.40,1.1,.25,.25),(0,-.40,3.5,.20,.21),
            (0,-.40,4.2,.19,.20),(0,-.40-1.7*math.sin(angle),4.2+1.7*math.cos(angle),.15,.16),
            (*wrist,.12,.13)],12,3)
    hand(g,wrist,(0,0,1),(1,0,0),.97,grip)
    return g


def claw():
    g=Geometry()
    tube(g,[(0,-.46,0,0,0),(0,-.46,.45,.32,.25),(0,-.47,1.5,.40,.29),
            (0,-.49,2.4,.40,.30)],12,3)
    hand(g,(0,-.49,2.4),(0,0,1),(1,0,0),2.32)
    return g


def hands():
    g=Geometry()
    for s in (-1,1):
        z=6 if s<0 else 5.85
        tube(g,[(s*.80,-.40,0,0,0),(s*.80,-.40,.55,.26,.24),
                (s*.83,-.46,2.8,.21,.21),(s*.91,-.60,4.0,.18,.18),
                (s*.80,-.66,z,.13,.13)],12,3)
        hand(g,(s*.8,-.66,z),(s*.055,0,1),(-s,0,0),1.01 if s<0 else 1.06,inner_factor=.61)
    return g


def pool():
    g=Geometry(); sides=110; v=[]
    # Radial field of eleven unequal tapered tendrils; no rotational symmetry.
    angles=[.08,.59,1.01,1.70,2.04,2.71,3.16,3.78,4.36,5.05,5.75]
    lengths=[.70,.31,.54,.25,.62,.43,.68,.36,.57,.28,.49]
    widths=[.10,.15,.11,.09,.13,.10,.14,.095,.12,.08,.11]
    outline=[]
    for j in range(sides):
        a=TAU*j/sides
        radius=1+.048*math.sin(7*a+.4)+.035*math.sin(17*a)
        for b,l,w in zip(angles,lengths,widths):
            d=abs((a-b+math.pi)%TAU-math.pi)
            radius+=l*max(0,1-d/w)**1.4
        outline.append((radius*math.cos(a),radius*math.sin(a)))
    # Coplanar inset rings keep angle-weighted side normals in a narrow rim,
    # avoiding a visible triangular fan across the otherwise flat top.
    for z,shrink in ((0,1),(0,.96),(.04,.96),(.04,1)):
        v.extend((x*shrink,y*shrink,z) for x,y in outline)
    v.extend(((0,0,0),(0,0,.04))); f=[]
    for j in range(sides):
        k=(j+1)%sides
        f.extend(((4*sides,sides+k,sides+j),
                  (4*sides+1,2*sides+j,2*sides+k)))
        for a,b in ((1,0),(0,3),(3,2)):
            f.extend(((a*sides+j,a*sides+k,b*sides+k),
                      (a*sides+j,b*sides+k,b*sides+j)))
    g.shell(v,f,(1,1,1)); return g


def organic_union(name,g):
    """Sparse voxel union rounds intersections, then bounded quadric simplification.
    This is sequential; the temporary object is freed before the next mesh.
    Pool retains its analytical thin closed shell.
    """
    if name=='Shade_Pool': return g
    mesh=bpy.data.meshes.new('temporary union'); mesh.from_pydata(g.vertices,[],g.faces); mesh.update()
    obj=bpy.data.objects.new('temporary union',mesh); bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.objects.active=obj; obj.select_set(True)
    mesh.remesh_voxel_size=.022 if name in ('Shade_Stand','Shade_Reach','Shade_Crawl','Shade_Rise') else .025
    mesh.use_remesh_preserve_volume=True
    bpy.ops.object.voxel_remesh()
    smooth=obj.modifiers.new('Organic transition','SMOOTH'); smooth.factor=.55; smooth.iterations=3
    bpy.ops.object.modifier_apply(modifier=smooth.name)
    tri=obj.modifiers.new('Explicit triangles','TRIANGULATE'); bpy.ops.object.modifier_apply(modifier=tri.name)
    target={'Shade_Stand':6200,'Shade_Reach':6200,'Shade_Crawl':6200,'Shade_Rise':6200,
            'Shade_Claw':2300,'Shade_Arm':2050,'Shade_ArmGrip':2050,'Shade_Hands':2800}[name]
    dec=obj.modifiers.new('Budgeted organic surface','DECIMATE'); dec.ratio=min(1,target/len(obj.data.polygons))
    bpy.ops.object.modifier_apply(modifier=dec.name)
    result=Geometry(); vertices=[tuple(v.co) for v in obj.data.vertices]
    faces=[tuple(p.vertices) for p in obj.data.polygons]
    # Voxel union can leave microscopic enclosed bubbles at overlapping caps.
    # Retain macroscopic exterior shells only, each independently oriented.
    incident=defaultdict(list)
    for fi,f in enumerate(faces):
        for vi in f: incident[vi].append(fi)
    unseen=set(range(len(faces)))
    while unseen:
        seed=unseen.pop(); todo=[seed]; found=[]
        while todo:
            fi=todo.pop(); found.append(faces[fi])
            for vi in faces[fi]:
                for other in incident[vi]:
                    if other in unseen: unseen.remove(other); todo.append(other)
        if volume(vertices,found)<=.00001: continue
        indices=sorted({i for f in found for i in f}); lookup={old:new for new,old in enumerate(indices)}
        result.shell([vertices[i] for i in indices],[tuple(lookup[i] for i in f) for f in found],(1,1,1))
    used=obj.data; bpy.data.objects.remove(obj,do_unlink=True); bpy.data.meshes.remove(used)
    print('Organic union',name,len(faces),flush=True)
    return result


def finish_shape(name,g):
    if name in HEIGHTS:
        low=min(p[2] for p in g.vertices); h=max(p[2] for p in g.vertices)-low
        factor=HEIGHTS[name]/h
        # Exact vertical specifications; Rise already preserves its leaning torso angle.
        g.vertices=[(x,y,(z-low)*factor) for x,y,z in g.vertices]
    if name=='Shade_Claw':
        width=max(p[0] for p in g.vertices)-min(p[0] for p in g.vertices)
        g.vertices=[(x*5.5/width,y,z) for x,y,z in g.vertices]
    if name in ('Shade_Stand','Shade_Reach','Shade_Crawl'):
        depth=max(p[1] for p in g.vertices)-min(p[1] for p in g.vertices)
        g.vertices=[(x,y*1.2/depth,z) for x,y,z in g.vertices]
    if name!='Shade_Pool':
        high=max(p[1] for p in g.vertices)
        g.vertices=[(x,y-high,z) for x,y,z in g.vertices]
    return g


def export(name,g):
    assert len(g.faces)<=LIMITS[name],(name,len(g.faces))
    assert len(g.colours)==len(g.vertices) and all(c==(1,1,1) for c in g.colours)
    assert set(i for f in g.faces for i in f)==set(range(len(g.vertices))),(name,'loose vertices')
    topology(g.vertices,g.faces,name)
    if name!='Shade_Pool': assert max(v[1] for v in g.vertices)<=.0005
    if name=='Shade_Pool': assert abs(max(v[2] for v in g.vertices)-min(v[2] for v in g.vertices)-.04)<.00001
    if name in HEIGHTS: assert abs((max(v[2] for v in g.vertices)-min(v[2] for v in g.vertices))/HEIGHTS[name]-1)<.03
    verts=[(round(x*1000),round(z*1000),round(y*1000)) for x,y,z in g.vertices]
    points=[tuple(c/1000 for c in p) for p in verts]; faces=[(a,c,b) for a,b,c in g.faces]
    normals,volumes=topology(points,faces,name+' quantized Roblox')
    sums=[Vector((0,0,0)) for p in points]
    for face,n in zip(faces,normals):
        for j,i in enumerate(face):
            p=Vector(points[i]); a=(Vector(points[face[(j+1)%3]])-p).normalized(); b=(Vector(points[face[(j+2)%3]])-p).normalized()
            sums[i]+=n*math.acos(max(-1,min(1,a.dot(b))))
    ns=[tuple(round(c*1000) for c in n.normalized()) for n in sums]
    assert all(.997<Vector(n).length/1000<1.003 for n in ns)
    numbers=dict(verts=[c for p in verts for c in p],normals=[c for p in ns for c in p],
                 colours=[255]*len(verts)*3,tris=[i for f in faces for i in f])
    low=[min(p[i] for p in points) for i in range(3)]; high=[max(p[i] for p in points) for i in range(3)]
    return {**numbers,'middle':[round((a+b)/2,6) for a,b in zip(low,high)],
            'size':[round(b-a,6) for a,b in zip(low,high)],'bbox':dict(min=low,max=high),
            'triangles':len(faces),'vertices':len(verts),'closed':True,'components':len(volumes),
            'sha1':hashlib.sha1(json.dumps(numbers,separators=(',',':')).encode()).hexdigest()[:12]}


def material(name,colour,emission=False):
    m=bpy.data.materials.new(name); m.use_nodes=True; nodes=m.node_tree.nodes; nodes.clear()
    out=nodes.new('ShaderNodeOutputMaterial')
    shader=nodes.new('ShaderNodeEmission' if emission else 'ShaderNodeBsdfPrincipled')
    if emission: shader.inputs['Color'].default_value=(*colour,1)
    else:
        shader.inputs['Base Color'].default_value=(*colour,1)
        shader.inputs['Roughness'].default_value=.29
        shader.inputs['Metallic'].default_value=.15
    m.node_tree.links.new(shader.outputs[0],out.inputs['Surface']); m.diffuse_color=(*colour,1)
    return m


def make_obj(name,g,col,mat,data=None):
    mesh=bpy.data.meshes.new(name); mesh.from_pydata(g.vertices,[],g.faces); mesh.update()
    obj=bpy.data.objects.new(name,mesh); col.objects.link(obj); mesh.materials.append(mat)
    for p in mesh.polygons: p.use_smooth=True
    colour=mesh.color_attributes.new(name='Col',type='BYTE_COLOR',domain='POINT')
    for c in colour.data: c.color=(1,1,1,1)
    if data:
        n=data['normals']; mesh.normals_split_custom_set_from_vertices([(n[i]/1000,n[i+2]/1000,n[i+1]/1000) for i in range(0,len(n),3)])
    return obj


def camera(scene,cam,position,target,scale):
    cam.location=position; cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler()
    cam.data.ortho_scale=scale; scene.camera=cam


def fit_camera(scene,cam,points,direction):
    """Frame actual projected vertices, including long forward-reaching fingers."""
    direction=Vector(direction).normalized()
    rotation=(-direction).to_track_quat('-Z','Y')
    right=rotation@Vector((1,0,0)); up=rotation@Vector((0,1,0))
    centre=Vector(tuple((min(p[i] for p in points)+max(p[i] for p in points))/2 for i in range(3)))
    horizontal=[(Vector(p)-centre).dot(right) for p in points]
    vertical=[(Vector(p)-centre).dot(up) for p in points]
    centre+=right*(min(horizontal)+max(horizontal))/2+up*(min(vertical)+max(vertical))/2
    aspect=scene.render.resolution_x/scene.render.resolution_y
    width=max(horizontal)-min(horizontal); height=max(vertical)-min(vertical)
    scale=max(height,width/aspect)*1.15 if aspect<1 else max(width,height*aspect)*1.15
    camera(scene,cam,centre+direction*35,centre,scale)


def notes(data):
    rows='\n'.join(f"| {n} | {m['triangles']} | {m['vertices']} | {m['size']} | {m['bbox']['min']} | {m['bbox']['max']} | {m['components']} | `{m['sha1']}` |" for n,m in data.items())
    Path(__file__).with_name('SHADE.md').write_text('''# Level 2 Shade

All anatomy and preview geometry are generated by `build_shade.py`; no downloaded assets.
One Blender unit = one Roblox stud. Blender Z up, front -Y, wall Y=0.
Every source mesh origin is (0,0,0). All vertices have Y<=0 except Shade_Pool,
which is centred in XY with Z=0..0.04. Feet/closed bases start at Z=0.
Export: Roblox (X,Y,Z) = Blender (X,Z,Y), triangle B/C swapped.
Positions stay relative to the origin; `middle` is only bounding-box metadata.
The installer positions the MeshPart box at `middle` relative to the origin.

`shade.json`: flat integer millistud `verts`, integer x1000 angle-weighted shared
`normals`, all-white RGB-byte `colours`, zero-based `tris`. SHA1 covers compact JSON
of those four arrays in that order. Budgets, heights, white colours, wall clearance,
no loose vertices, triangle area, paired directed edges, cyclic vertex links and positive
closed-shell volumes are asserted, including topology after export quantization.
Anatomy uses sparse voxel union, gentle smoothing and budgeted decimation. The final
quantized surfaces are checked as closed shells; Hands retains two disjoint arms.
Shade_ArmGrip uses the same 4.2+3.4-stud arm segments as Shade_Arm; its 55-degree
elbow and curled hand naturally give a lower overall height than the open arm.
Preview materials do not affect white exported vertex colours. Use black MeshParts.

The blend contains nine zero-origin source objects in Assets and a separate Preview scene.
Fronts are orthographic pure-black emissions on a pale tile-colour field; Pool front is
orthographic from above, since its XY footprint is its useful silhouette. Three-quarter
renders use dark glossy grey under broad lights. Sheet shows front projections at one
scale with a 5.5-stud grey player box; Pool is rotated only in the preview copy.

Bounding boxes and sizes below are Roblox axes in studs.

| Mesh | Tris | Vertices | Bbox size | Bbox min | Bbox max | Shells | SHA1 |
|---|---:|---:|---|---|---|---:|---|
'''+rows+'''

Rebuild from project root, one Blender process at a time:
```sh
/Applications/Blender.app/Contents/MacOS/Blender --factory-startup -b --python tools/level2_shade/build_shade.py
```
Optional `-- --skip-renders` rebuilds JSON and blend only. Renders are sequential,
EEVEE with two CPU threads. No Studio, upload, gameplay validation or publishing.

Visual review: all nine fronts and the common-scale sheet were opened. Stand/Reach/Crawl
have an uninterrupted leg gap, arms clear of the torso, a smooth small bare oval head,
and five separately readable tapered fingers on each hand. Rise also shows ten digits
clear of its torso. Claw and Arm show five splayed digits; ArmGrip curls into a forward
hook in 3D. Hands has ten separate digits and unequal arms; the initial two touching
inner tips were separated. Pool is an asymmetric ragged eleven-tendril footprint.
The initial capped shoulder/hip steps were removed by blending the generated shells.
All three-quarter images are reviewed for smooth form and full-frame coverage.
Pool's front render is deliberately top-down, the only useful silhouette for this flat
XY asset. ArmGrip is 7.452 studs tall, rather than 9.5: the more bent forearm and curled
fingers reduce its height. No Roblox runtime checks were performed.
''')


def main():
    for p in (OUT/'blend',OUT/'renders'): p.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene=bpy.context.scene; scene.name='Assets'
    col=bpy.data.collections.new('Shade source meshes — all origins zero'); scene.collection.children.link(col)
    geometries=dict(Shade_Stand=standing('stand'),Shade_Reach=standing('reach'),Shade_Crawl=standing('crawl'),
                    Shade_Rise=rise(),Shade_Claw=claw(),Shade_Arm=arm(),Shade_ArmGrip=arm(True),Shade_Hands=hands(),Shade_Pool=pool())
    geometries={n:finish_shape(n,organic_union(n,g)) for n,g in geometries.items()}
    data={n:export(n,g) for n,g in geometries.items()}
    (OUT/'shade.json').write_text(json.dumps(dict(about='Procedural Poolrooms Shade; studs; Roblox X,Z,Y from Blender; origin unchanged; reversed winding; white vertex colours',meshes=data),separators=(',',':'))+'\n')
    for n,m in data.items(): print(n,m['triangles'],m['vertices'],m['size'],flush=True)
    dark=material('Dark glossy anatomy',(.025,.029,.032)); black=material('Pure black silhouette',(0,0,0),True)
    pale=material('Pale pool tile field',(.79,.83,.76),True); grey=material('5.5-stud player',(.32,.35,.34),True)
    assets={n:make_obj(n,g,col,dark,data[n]) for n,g in geometries.items()}
    preview=bpy.data.scenes.new('Preview'); pc=bpy.data.collections.new('Render-only copies and lighting'); preview.collection.children.link(pc)
    copies={}
    for n,o in assets.items():
        obj=bpy.data.objects.new(n+' preview',o.data.copy()); pc.objects.link(obj); copies[n]=obj
    preview.world=bpy.data.worlds.new('Pale tile background'); preview.world.use_nodes=True
    preview.world.node_tree.nodes['Background'].inputs[0].default_value=(.79,.83,.76,1)
    preview.world.node_tree.nodes['Background'].inputs[1].default_value=.8
    preview.render.engine='BLENDER_EEVEE'
    preview.render.threads_mode='FIXED'; preview.render.threads=2
    preview.eevee.taa_render_samples=24
    preview.render.resolution_x=768; preview.render.resolution_y=1024; preview.render.resolution_percentage=100
    preview.view_settings.view_transform='Standard'
    cdata=bpy.data.cameras.new('Orthographic camera'); cdata.type='ORTHO'; cam=bpy.data.objects.new('Orthographic camera',cdata); pc.objects.link(cam)
    lights=[]
    for name,loc,power,size in [('Broad key',(-6,-10,13),1800,8),('Edge fill',(7,-2,10),1600,7),('Top',(0,0,16),1100,6)]:
        ld=bpy.data.lights.new(name,'AREA'); ld.energy=power; ld.shape='DISK'; ld.size=size
        o=bpy.data.objects.new(name,ld); pc.objects.link(o); o.location=loc; o.rotation_euler=(Vector((0,-1,6))-o.location).to_track_quat('-Z','Y').to_euler(); lights.append(o)
    skip='--skip-renders' in sys.argv
    if not skip:
        for n,obj in copies.items():
            for o in copies.values(): o.hide_render=True
            obj.hide_render=False
            lo=Vector(tuple(min(v[i] for v in geometries[n].vertices) for i in range(3)))
            hi=Vector(tuple(max(v[i] for v in geometries[n].vertices) for i in range(3)))
            centre=(lo+hi)/2; size=hi-lo
            obj.data.materials[0]=black
            if n=='Shade_Pool':
                camera(preview,cam,centre+Vector((0,0,25)),centre,max(size.x/ .75,size.y)*1.18)
            else: camera(preview,cam,(centre.x,-30,centre.z),centre,max(size.z,size.x/.75)*1.15)
            preview.render.filepath=str(OUT/'renders'/f'{n}_front.png'); bpy.ops.render.render(write_still=True,scene=preview.name)
            obj.data.materials[0]=dark
            fit_camera(preview,cam,geometries[n].vertices,(18,-25,9))
            preview.render.filepath=str(OUT/'renders'/f'{n}_34.png'); bpy.ops.render.render(write_still=True,scene=preview.name)
        # Shared scale sheet, baseline zero. Black captions use Blender's built-in font.
        x=0; labels=[]
        for n,obj in copies.items():
            obj.hide_render=False; obj.data.materials[0]=black
            if n=='Shade_Pool': obj.rotation_euler.x=math.pi/2
            width=data[n]['size'][0]
            obj.location.x=x-data[n]['bbox']['min'][0]
            if n=='Shade_Pool': obj.location.z=-data[n]['bbox']['min'][2]
            label=bpy.data.curves.new(n+' caption','FONT'); label.body=n.replace('Shade_',''); label.size=.40; label.align_x='CENTER'
            text=bpy.data.objects.new(n+' caption',label); pc.objects.link(text); text.location=(x+width/2,-8,-.9); text.rotation_euler=(math.pi/2,0,0); label.materials.append(black); labels.append(text)
            x+=width+1.3
        g=Geometry(); g.vertices=[(x+dx,-.5+dy,z) for dx,dy,z in [(0,0,0),(1.7,0,0),(1.7,.5,0),(0,.5,0),(0,0,5.5),(1.7,0,5.5),(1.7,.5,5.5),(0,.5,5.5)]]
        g.faces=[(0,2,1),(0,3,2),(4,5,6),(4,6,7),(0,1,5),(0,5,4),(1,2,6),(1,6,5),(2,3,7),(2,7,6),(3,0,4),(3,4,7)]
        player=make_obj('5.5-stud grey player scale',g,pc,grey)
        label=bpy.data.curves.new('Player caption','FONT'); label.body='Player 5.5'; label.size=.4; label.align_x='CENTER'; label.materials.append(black)
        text=bpy.data.objects.new('Player caption',label); pc.objects.link(text); text.location=(x+.85,-8,-.9); text.rotation_euler=(math.pi/2,0,0)
        x+=2.3
        preview.render.resolution_x=2800; preview.render.resolution_y=1100
        camera(preview,cam,(x/2,-45,7),(x/2,0,7),x*1.06)
        preview.render.filepath=str(OUT/'renders'/'sheet.png'); bpy.ops.render.render(write_still=True,scene=preview.name)
    # Save sources at exact origins; render-only arrangement remains isolated.
    bpy.context.window.scene=scene
    for o in assets.values(): assert tuple(o.location)==(0,0,0)
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'blend'/'Level2_Shade.blend'))
    notes(data)
    print('DONE — closed shells / exported topology / budgets / axes / heights / white colours asserted.',flush=True)

if __name__=='__main__': main()
