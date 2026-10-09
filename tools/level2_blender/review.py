"""H3: final owner review scenes, built from the real kit, offline in headless Blender.

D:/Blender/blender.exe -b --factory-startup --python-exit-code 1 -P
G:/Roblox/MongoTV/tools/level2_blender/review.py -- --samples 64
All generated files stay under review/H3. --only accepts render-name substrings.
"""
import sys
sys.dont_write_bytecode = True
import argparse, importlib, json, math, hashlib
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import bpy, bmesh, numpy as np
from mathutils import Matrix, Vector
import kit

OUT = Path('G:/Blender/Level2_Pool/review/H3')
MODULES = ('modules_arch', 'modules_tunnel', 'rooms_small', 'props_meshy', 'slides', 'modules_extra', 'props_small')
SCENES, SHOTS, NOTES, BUDGETS = {}, [], [], {}
S = kit.S


def collection(name):
    c = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(c)
    SCENES[name] = c
    return c


def record_preview(records, name):
    """kit.part supports yaw only; preserve full native Part frames in the review."""
    m = kit.Mesh(name)
    for p in records:
        if p.get('properties', {}).get('Transparency') == 1:
            continue
        f = p.get('cframe')
        if f:
            r = np.column_stack((f['right'], f['up'], f['back']))
            rot = Matrix((kit.C.T @ r @ kit.C).tolist()).to_4x4()
        else:
            rot = Matrix.Rotation(-math.radians(p['cf'][3]), 4, 'Z')
        m.box(p['cf'][:3], p['size'], p['material'], bevel=0, rotation=rot)
    return m.finish(register=False)


def place(c, name, pos=(0, 0, 0), yaw=0, open_socket=None, plan=False):
    info = kit.COMPONENTS[name]
    original = info.get('preview')
    if open_socket or plan or (original is None and info['parts']):
        records = [p for p in info['parts']
                   if p['attrs'].get('SocketPlug') != open_socket or not open_socket]
        if plan:
            records = [p for p in records if 'Overhead' not in p['name']
                       and p['cf'][1] - p['size'][1] / 2 < 17]
        info['preview'] = record_preview(records, name + '_review_parts')
    before = set(c.objects)
    ob = kit.place(c, name, pos, yaw)
    info['preview'] = original
    for o in set(c.objects) - before:
        o.name = o.name.replace('Skylight', 'Light')
        if plan and o.data == info['mesh']:
            o.data = o.data.copy()
            bm = bmesh.new(); bm.from_mesh(o.data)
            bmesh.ops.delete(bm, geom=[f for f in bm.faces if all(v.co.z > 17*S for v in f.verts)], context='FACES')
            bm.to_mesh(o.data); bm.free()
    return ob


def finish(m, budget=0):
    m.finish()
    mesh = kit.COMPONENTS[m.name]['mesh']; mesh.calc_loop_triangles()
    n = len(mesh.loop_triangles)
    assert n <= budget, (m.name, n, budget)
    BUDGETS[m.name] = budget
    return m.name


def part(m, name, pos, size, mat, ground=False, collide=True):
    m.part('Level 2 ' + name, pos, size, mat, ground=ground, collide=collide,
           attrs={'Level2_EntityGround': True} if ground else {}, show=False)


def tilted_part(m, name, pos, size, mat, slope, ground=True):
    part(m, name, pos, size, mat, ground=ground)
    a = math.atan(slope)
    m.parts[-1]['cframe'] = {'position': list(pos), 'right': [1,0,0],
                            'up': [0, math.cos(a), -math.sin(a)],
                            'back': [0, math.sin(a), math.cos(a)]}


def light(c, name, pos, target, power, size=6, color=(1,.91,.78), kind='AREA'):
    data = bpy.data.lights.new(name, kind)
    o = bpy.data.objects.new(name, data); c.objects.link(o)
    o.location = kit.to_blender(pos); data.energy = power; data.color = color
    o.rotation_euler = (kit.to_blender(target)-o.location).to_track_quat('-Z','Y').to_euler()
    if kind != 'SUN': data.use_shadow = False
    if kind == 'AREA':
        data.shape = 'DISK'; data.size = size
    if kind == 'POINT': data.shadow_soft_size = .25
    if kind == 'SUN': data.angle = math.radians(12)
    return o


def water_material():
    m = bpy.data.materials.new('H Render Water - Terrain proxy'); m.use_nodes = True
    nt = m.node_tree; nt.nodes.clear()
    out=nt.nodes.new('ShaderNodeOutputMaterial')
    clear=nt.nodes.new('ShaderNodeBsdfTransparent')
    clear.inputs['Color'].default_value=(.84,1,.97,1)
    shine=nt.nodes.new('ShaderNodeBsdfGlossy')
    shine.inputs['Color'].default_value=(.25,.75,.75,1)
    shine.inputs['Roughness'].default_value=.18
    fresnel=nt.nodes.new('ShaderNodeFresnel');fresnel.inputs['IOR'].default_value=1.333
    mix=nt.nodes.new('ShaderNodeMixShader')
    nt.links.new(clear.outputs[0],mix.inputs[1]);nt.links.new(shine.outputs[0],mix.inputs[2])
    nt.links.new(fresnel.outputs[0],mix.inputs[0]);nt.links.new(mix.outputs[0],out.inputs['Surface'])
    m.surface_render_method = 'DITHERED'
    tex = nt.nodes.new('ShaderNodeTexNoise'); tex.inputs['Scale'].default_value = 8
    tex.inputs['Detail'].default_value = 2; tex.inputs['Roughness'].default_value = .5
    bump = nt.nodes.new('ShaderNodeBump'); bump.inputs['Strength'].default_value = .16
    bump.inputs['Distance'].default_value = .006
    nt.links.new(tex.outputs['Fac'],bump.inputs['Height']); nt.links.new(bump.outputs['Normal'],shine.inputs['Normal'])
    return m


def sky_opening(c,x,y,z,radius):
    """A blue-sky/cloud card above each open well; only a render backdrop."""
    mat=bpy.data.materials.get('H Blue sky and soft clouds')
    if not mat:
        mat=bpy.data.materials.new('H Blue sky and soft clouds');mat.use_nodes=True
        nt=mat.node_tree;nt.nodes.clear()
        out=nt.nodes.new('ShaderNodeOutputMaterial');em=nt.nodes.new('ShaderNodeEmission')
        noise=nt.nodes.new('ShaderNodeTexNoise');noise.inputs['Scale'].default_value=2.2
        noise.inputs['Detail'].default_value=2
        ramp=nt.nodes.new('ShaderNodeValToRGB')
        ramp.color_ramp.elements[0].position=.57;ramp.color_ramp.elements[0].color=(.14,.49,.95,1)
        ramp.color_ramp.elements[1].position=.70;ramp.color_ramp.elements[1].color=(.94,.97,1,1)
        nt.links.new(noise.outputs['Fac'],ramp.inputs['Fac']);nt.links.new(ramp.outputs['Color'],em.inputs['Color'])
        em.inputs['Strength'].default_value=1.4;nt.links.new(em.outputs[0],out.inputs['Surface'])
    mesh=bpy.data.meshes.new('H sky disc')
    mesh.from_pydata([kit.to_blender((x+radius*math.cos(i*math.tau/48),y,z+radius*math.sin(i*math.tau/48)))
                       for i in range(48)],[],[tuple(reversed(range(48)))])
    mesh.materials.append(mat);ob=bpy.data.objects.new('H Render-only blue sky',mesh);c.objects.link(ob)
    ob['review_only']=True
    if hasattr(ob, 'visible_shadow'): ob.visible_shadow=False
    cloud=bpy.data.materials.get('H Cloud white')
    if not cloud:
        cloud=bpy.data.materials.new('H Cloud white');cloud.use_nodes=True
        nodes=cloud.node_tree.nodes;nodes.clear()
        out=nodes.new('ShaderNodeOutputMaterial');glow=nodes.new('ShaderNodeEmission')
        glow.inputs['Color'].default_value=(.94,.97,1,1)
        glow.inputs['Strength'].default_value=1.15
        cloud.node_tree.links.new(glow.outputs[0],out.inputs['Surface'])
    for dx,dz,rx,rz in ((-radius*.35,-radius*.15,radius*.19,radius*.075),
                        (radius*.28,radius*.24,radius*.13,radius*.065)):
        points=[kit.to_blender((x+dx+rx*math.cos(i*math.tau/16),y-.03,
                               z+dz+rz*math.sin(i*math.tau/16))) for i in range(16)]
        cm=bpy.data.meshes.new('H cloud');cm.from_pydata(points,[],[tuple(range(16))])
        cm.materials.append(cloud)
        co=bpy.data.objects.new('H Render-only cloud',cm);c.objects.link(co)
        co['review_only']=True
        if hasattr(co,'visible_shadow'):co.visible_shadow=False


def water(c, w, d, y=.1, x=0, z=0):
    mesh = bpy.data.meshes.new('H Water Surface')
    mesh.from_pydata([kit.to_blender(v) for v in ((x-w/2,y,z-d/2),(x+w/2,y,z-d/2),
                       (x+w/2,y,z+d/2),(x-w/2,y,z+d/2))],[],[(0,3,2,1)])
    mesh.materials.append(WATER)
    o = bpy.data.objects.new('H Render-only Terrain water',mesh); c.objects.link(o)
    o['review_only'] = True


def connection_end(c, z, x=0, floor=0, width=34, height=32):
    """Review-only closure where the procedural world would attach the next room."""
    mesh=bpy.data.meshes.new('H Unbuilt connection backdrop')
    mesh.from_pydata([kit.to_blender(v) for v in ((x-width/2,floor,z),(x+width/2,floor,z),
                          (x+width/2,floor+height,z),(x-width/2,floor+height,z))],[],[(0,1,2,3)])
    kit.material('TileTeal');mesh.materials.append(kit.MATERIALS['TileTeal']['blender'])
    ob=bpy.data.objects.new('H Review-only connection end',mesh);c.objects.link(ob)
    ob['review_only']=True


def edge_modules(c, w, d, floor=0):
    # All four sides are exact 8-stud lengths, with sealed butt joints.
    for zz, yaw in ((-d/2,180),(d/2,0)):
        for xx in np.arange(-w/2+4,w/2,8): place(c,'Coping8',(float(xx),floor,zz),yaw)
        for xx in np.arange(-w/2+8,w/2,16): place(c,'Gutter16',(float(xx),floor,zz+(-1.45 if zz<0 else 1.45)),yaw)
    for xx, yaw in ((-w/2,90),(w/2,-90)):
        for zz in np.arange(-d/2+4,d/2,8): place(c,'Coping8',(xx,floor,float(zz)),yaw)
        for zz in np.arange(-d/2+8,d/2,16): place(c,'Gutter16',(xx+(-1.45 if xx<0 else 1.45),floor,float(zz)),yaw)


def hall(c, name, w=144, d=176, h=42, floor=0, centre=(0,0), wet=True,
         kids=False, doors=(('N',0,'Arch'),('S',0,'Arch'),('E',40,'Service')), plan=False):
    """Runtime-style flat Parts, one sloped pool floor and real kit detail."""
    cx,cz = centre; m = kit.Mesh(name,Width=w,Depth=d,Height=h,FloorY=floor,ReviewShell=True)
    pw,pd=w-24,d-24; shallow,deep=(.8,.8) if kids else (.8,2.0)
    if wet:
        for x in (-1,1): part(m,'Hall Deck Side',(x*(pw/2+6),floor-.5,0),(12,1,d),'Rubber' if kids else 'Terrazzo',True)
        for z in (-1,1): part(m,'Hall Deck End',(0,floor-.5,z*(pd/2+6)),(pw,1,12),'Rubber' if kids else 'Terrazzo',True)
        slope=-(deep-shallow)/pd
        # Exactly one tilted floor Part. Thickness is measured along its normal.
        tilted_part(m,'Hall Water Floor',(0,floor-(deep+shallow)/2-.6,0),
                    (pw,1.2,math.hypot(pd,deep-shallow)),'Mosaic',slope)
        for xx in (-pw/2,pw/2): part(m,'Basin Wall',(xx,floor-deep/2,0),(.6,deep,pd),'Mosaic')
        for zz in (-pd/2,pd/2): part(m,'Basin Wall',(0,floor-deep/2,zz),(pw,deep,.6),'Mosaic')
        for xx in np.linspace(-pw/2+12,pw/2-12,5):
            tilted_part(m,'Cobalt Lane',(float(xx),floor-(deep+shallow)/2+.025,0),
                        (.5,.025,math.hypot(pd,deep-shallow)),'Cobalt',slope,False)
        m.attrs['WaterRegion']={'surfaceY':floor+.1,'bottom':floor-deep,'size':[pw,deep+.1,pd]}
    else: part(m,'Hall Dry Deck',(0,floor-.5,0),(w,1,d),'Terrazzo',True)
    # Runs between apertures, tiled dado, three tinted strips; no wall behind a door.
    for wall in 'NSEW':
        long=w if wall in 'NS' else d; holes=sorted((off,30 if typ=='Arch' else 12,34.5 if typ=='Arch' else 17.1)
              for side,off,typ in doors if side==wall)
        runs=[]; start=-long/2
        for off,hw,hh in holes:
            runs.append((start,off-hw/2,0,h)); runs.append((off-hw/2,off+hw/2,hh,h)); start=off+hw/2
        runs.append((start,long/2,0,h))
        for a,b,lo,hi in runs:
            if b<=a or hi<=lo: continue
            def wallpart(label,y,hei,mat,proud=0):
                sign=-1 if wall in 'NW' else 1
                pos=((a+b)/2,floor+y,sign*(d/2-proud)) if wall in 'NS' else (sign*(w/2-proud),floor+y,(a+b)/2)
                size=(b-a,hei,1.75 if not proud else .12) if wall in 'NS' else (1.75 if not proud else .12,hei,b-a)
                part(m,label,pos,size,mat)
            wallpart('Hall Tile Wall',(lo+hi)/2,hi-lo,'Tile')
            if lo==0: wallpart('Hall Teal Dado',1.5,3,'TileTeal',.94)
            for band_base in (h/3,h-5):
                for i,mat in enumerate(('BandCoral','BandYellow','BandBlue')):
                    y=band_base+i*.78
                    if y-.3>=lo and y+.3<=hi: wallpart('Hall '+mat,y,.6,mat,1)
    # Four slots with exact square boundaries; no slab spans an opening.
    wells=[(-w*.25,-d*.26),(w*.25,-d*.26),(-w*.25,d*.26),(w*.25,d*.26)]
    size=36 if w<144 else 52; letter='S' if size==36 else 'L'
    xs=sorted(set([-w/2,w/2]+[v for x,z in wells for v in (x-size/2,x+size/2)]))
    zs=sorted(set([-d/2,d/2]+[v for x,z in wells for v in (z-size/2,z+size/2)]))
    for a,b in zip(xs,xs[1:]):
        for p,q in zip(zs,zs[1:]):
            x,z=(a+b)/2,(p+q)/2
            if any(abs(x-wx)<size/2-.01 and abs(z-wz)<size/2-.01 for wx,wz in wells):continue
            part(m,'Overhead Tile',(x,floor+h+.3,z),(b-a,.6,q-p),'Tile',collide=False)
    m.collider('Level 2 Hall Roof Collider',(0,floor+h+6.5,0),(w,.5,d),attrs={'Level2_NoEntityGround':True})
    finish(m)
    place(c,name,(cx,0,cz),plan=plan)
    for side,off,typ in doors:
        pos=(cx+off,floor,cz+(-d/2 if side=='N' else d/2)) if side in 'NS' else (cx+(-w/2 if side=='W' else w/2),floor,cz+off)
        place(c,'DoorArch30' if typ=='Arch' else 'DoorService12',pos,90 if side in 'EW' else 0,plan=plan)
    if not plan:
        for x,z in wells:
            place(c,'SkylightWell'+letter,(cx+x,floor+h,cz+z))
            sky_opening(c,cx+x,floor+h+6.25,cz+z,11 if letter=='S' else 19)
            light(c,'H Daylight well',(cx+x,floor+h+5.7,cz+z),(cx+x-9,floor,cz+z+12),5000,9,(1,.94,.84))
        sun=light(c,'H Sun',(cx-80,floor+h+100,cz-100),(cx+40,floor,cz+35),3.8,kind='SUN',color=(1,.86,.67))
        sun.data.angle=math.radians(2)
        light(c,'H Soft reflected daylight',(cx,floor+22,cz-20),(cx,floor+12,cz+50),1250,14,(1,.9,.76))
        for zz in (-d/2+5,d/2-5):
            for xx in (-w/2+15,w/2-15):
                place(c,'LampPanel',(cx+xx,floor+h-1,cz+zz))
                light(c,'H Warm panel',(cx+xx,floor+h-1.2,cz+zz),(cx+xx,floor,cz+zz),300,2.5)
        for zz in (-d/2+10,0,d/2-10):
            place(c,'OverheadRibs96',(cx,floor+h,cz+zz))
        place(c,'OverheadCoffer40',(cx,floor+h,cz))
        for xx in (-w/2+1,w/2-1):
            for zz in (-d/2+36,d/2-36):
                g=kit.Mesh(name+'_Glass_'+str(xx)+'_'+str(zz))
                part(g,'Glass Block Panel',(xx,floor+h*.5,zz),(.22,18,12),'GlassBlock',False,False)
                finish(g);place(c,g.name,(cx,0,cz))
        # Cove sockets are aligned with wall tops and only use fixed kit lengths.
        for zz,yaw in ((-d/2+1,180),(d/2-1,0)):
            for xx in np.arange(-w/2+8,w/2-7,16):place(c,'Cove16',(cx+float(xx),floor+h,cz+zz),yaw)
    diameter=4.5 if kids else 5.5 if h==42 else 9
    for x in (-w/2+7,w/2-7):
        for z in (-d/2+27,-d/2+57,d/2-57,d/2-27):
            if abs(z)<20:continue
            place(c,f'Column{str(diameter).replace(".","_")}_H{h}',(cx+x,floor,cz+z),plan=plan)
    if wet:
        # Place local edge detail then translate objects, keeping exact module pivots.
        before=set(c.objects);edge_modules(c,pw,pd,floor)
        place(c,'PoolSteps',(0,floor,-pd/2),180)
        for x in (-pw/2+20,pw/2-20):place(c,'Ladder',(x,floor,pd/2))
        for o in set(c.objects)-before:o.location+=kit.to_blender((cx,0,cz))
        water(c,pw-.6,pd-.6,floor+.1,cx,cz)
    return (pw,pd)


def prop(c, name, pos, yaw=0, scale=1):
    key='Prop_'+name
    if key not in kit.COMPONENTS:
        NOTES.append('Missing '+key);return None
    o=place(c,key,pos,yaw);o.scale=(scale,)*3;return o


def small(c, name, pos, yaw=0):
    return place(c,'Small_'+name,pos,yaw)


def cluster(c, name, pos, yaw=0):
    return place(c,'PropCluster_'+name,pos,yaw)


def tunnel(c, name, pos=(0,0,0), yaw=0, plan=False):
    o=place(c,name,pos,yaw,plan=plan);info=kit.COMPONENTS[name]
    for rec in info['markers']:
        if rec['name'] not in ('LampLight','Light'):continue
        v=Matrix.Rotation(math.radians(yaw),4,'Z')@kit.to_blender(rec['cf'][:3])+kit.to_blender(pos)
        rp=kit.C@np.array(v)/S
        light(c,'H Bulkhead bounce',tuple(rp),tuple(rp+[0,-4,0]),100,kind='POINT')
    wr=info['attrs'].get('waterRegion')
    if wr:
        # Current review connections use a Z-axis wet tunnel.
        water(c,18.1,info['attrs']['length'],pos[1]+.1,pos[0],pos[2])
    return o


def room(c,name,pos=(0,0,0),open_socket=None,plan=False):
    o=place(c,name,pos,open_socket=open_socket,plan=plan)
    for mk in kit.COMPONENTS[name]['markers']:
        if mk['name']=='Light':
            p=tuple(a+b for a,b in zip(pos,mk['cf'][:3]))
            light(c,'H Room fixture',p,(p[0],pos[1],p[2]),240 if name.startswith('Changing') else 110,2)
    return o


def shot(c,name,eye,target,lens=24,ortho=None,description=''):
    SHOTS.append(dict(scene=c.name,name=name,eye=eye,target=target,lens=lens,ortho=ortho,description=description))


def build_scenes(slides):
    c=collection('PoolHall');pw,pd=hall(c,'H_PoolHall',doors=(('S',0,'Arch'),('E',40,'Service')))
    place(c,'GrandStair24',(0,0,78))
    place(c,'SpectatorTerrace32',(-66,0,0),90)
    for x in (-41,-21,21,41):
        for z in (-44,20):place(c,'LaneRope64',(x,0,z))
    # Centre cross and all door spokes are deliberately free of dressing.
    for x,yaw in ((-67,-90),(67,90)):
        for z in (-66,-40,28,66):prop(c,'lounger',(x,0,z),yaw)
    prop(c,'lifeguard',(-65,0,57),-90);prop(c,'lifeguard',(65,0,-55),90)
    prop(c,'lanereel',(62,0,-65))
    prop(c,'kickboards',(-63,0,-64));prop(c,'vacuum',(64,0,-30))
    for x in (-42,-21,21,42):prop(c,'startblock',(x,0,-82))
    for x in (-66,66):
        for z in (-71,74):
            cluster(c,'Towels',(x,0,z));small(c,'Bin',(x,0,z+3))
    small(c,'Noodles',(-64,0,12));small(c,'Fountain',(70,3,-55),90)
    small(c,'WetFloor',(65,0,53));small(c,'Clock',(-70,8,0),90)
    small(c,'RopeCoil',(-64,0,-29));cluster(c,'Goggles',(64,0,-48))
    cluster(c,'Towels',(-65,0,-48));cluster(c,'Goggles',(-63,0,-35))
    small(c,'Bin',(-69,0,-35));small(c,'Noodles',(-69,0,-54))
    for z in (-52,52):
        prop(c,'lifebuoy',(-70.9,5,z),90);prop(c,'lifebuoy',(70.9,5,z),-90)
    for x,yaw in ((-70.9,90),(70.9,-90)):
        for z in (-63,-20,20,63):
            prop(c,'bulkhead',(x,12,z),yaw)
            light(c,'H Pool wall sconce',(x*.97,12,z),(x*.65,5,z),90,1.2)
    tunnel(c,'Tunnel_Dry_64',(0,0,-120))
    connection_end(c,-151.9)
    tunnel(c,'Passage_Flat_48',(96,0,40),90)
    shot(c,'01_PoolHall_deck',(0,4.5,-84),(0,8,70),24,description='Pool hall from the deck toward the grand stair and blind arch.')
    shot(c,'02_PoolHall_corner',(49,4.5,-81),(-8,5,50),23,description='The same pool hall from its shallow-end corner.')

    c=collection('TallHall');hall(c,'H_TallHall',144,176,52)
    place(c,'DivingPlatform_H52',(0,0,64))
    place(c,'SpectatorTerrace32',(66,0,0),-90)
    for x in (-38,38):place(c,'Springboard3' if x<0 else 'Springboard1',(x,0,72))
    for x,yaw in ((-67,90),(67,-90)):
        for z in (-48,24):place(c,'GalleryBalcony32',(x,14,z),yaw)
    place(c,'GalleryStair',(-62,0,57),180)
    for x in (-41,-21,21,41):
        for z in (-44,20):place(c,'LaneRope64',(x,0,z))
    for x in (-66,66):
        for z in (-60,54):cluster(c,'Kickboards',(x,0,z))
    tunnel(c,'Tunnel_Wet_64',(0,0,-120))
    tunnel(c,'Tunnel_Wet_64',(0,0,120))
    connection_end(c,151.9)
    light(c,'H Tunnel warm bounce',(-5,16,-114),(0,5,-80),250,3)
    shot(c,'03_TallHall_tunnel',(0,4.5,-105),(0,16,60),22,description='Tall diving hall seen through the wet tunnel arch.')

    c=collection('LevelChange')
    hall(c,'H_LowerHall',144,144,42,centre=(0,-108),wet=False,doors=(('S',0,'Arch'),))
    hall(c,'H_UpperHall',144,144,42,8,centre=(0,108),doors=(('N',0,'Arch'),))
    tunnel(c,'Tunnel_Stair8_72')
    for z in (-22,18):light(c,'H Stair bulkhead bounce',(0,18,z),(0,5,z+8),240,4)
    shot(c,'04_LevelChange_stair',(0,4.5,-31),(0,13,60),22,description='Bottom of the 72-stud stair tunnel, rising eight studs into the upper hall.')

    c=collection('EscapeRoute')
    hall(c,'H_EscapeHall',144,144,42,centre=(0,-120),doors=(('S',0,'Service'),))
    tunnel(c,'Passage_Flat_48',(0,0,-24))
    room(c,'ChangingRoom_B',(0,0,40),open_socket='N0')
    small(c,'WetFloor',(-18,0,25));small(c,'Bin',(24,0,62))
    cluster(c,'Towels',(-20,0,57));small(c,'Fountain',(27,3,37),-90)
    place(c,'DoorService12',(0,0,0))
    light(c,'H Passage key',(0,12,-15),(0,6,12),120,3)
    shot(c,'05_EscapeRoute_passage',(0,4.5,-27),(0,6,51),23,description='12-stud escape passage through the opened N0 socket into ChangingRoom_B.')
    shot(c,'06_ChangingRoom_inside',(-20,4.5,17),(11,5,66),22,description='ChangingRoom_B with its authored lockers, benches, cubicles and fixtures.')

    c=collection('PlantRoom');room(c,'PlantRoom_B')
    light(c,'H Industrial side fill',(-32,17,-19),(0,5,0),1100,9,(.72,.86,1))
    light(c,'H Industrial overhead',(12,21,0),(5,0,-6),1700,12,(.88,.95,1))
    light(c,'H Industrial rear',(32,14,-27),(0,5,-13),900,8,(1,.89,.70))
    small(c,'Extinguisher',(33,3,-17),-90);small(c,'Cones',(24,0,18))
    shot(c,'07_PlantRoom_inside',(-29,4.5,24),(10,5,-18),21,description='PlantRoom_B as built, with filters, pumps and pipe manifold under industrial light.')

    c=collection('KidsRoom');hall(c,'H_KidsRoom',128,112,34,kids=True,doors=(('N',0,'Arch'),))
    pit=kit.Mesh('H_KidsBallIsland')
    part(pit,'Kids Ball Island',(-39,.05,0),(25,.5,20),'Rubber',True)
    for x in (-51.65,-26.35):part(pit,'Kids Ball Lip',(x,.55,0),(.3,.8,20),'BandCoral')
    for z in (-10.15,10.15):part(pit,'Kids Ball Lip',(-39,.55,z),(25,.8,.3),'BandYellow')
    finish(pit);place(c,pit.name)
    place(c,'BallBedM',(-39,.3,0))
    small(c,'Noodles',(54,0,20));small(c,'Bin',(-56,0,18))
    cluster(c,'Kickboards',(53,0,-29));cluster(c,'Bucket',(-55,0,-22))
    for p in ((-38,.12,-25),(35,.12,24),(38,.12,-24)):prop(c,'floatring',p)
    prop(c,'kickboards',(-55,0,35));prop(c,'kickboards',(54,0,-36))
    # Subtle render-only flush decal: clear 8 x 8 pocket, outside the central 24-wide hub.
    mk=kit.Mesh('H_FoamPocketMark')
    for x,z,sx,sz in ((-56,-36,8,.12),(-56,-28,8,.12),(-60,-32,.12,8),(-52,-32,.12,8)):
        mk.box((x,.012,z),(sx,.012,sz),'BandBlue',bevel=0)
    finish(mk,48);place(c,mk.name)
    shot(c,'08_KidsRoom_splash',(0,4.5,-51),(-38,2,0),22,description='Deck-eye kids hall, shallow splash pool, ball pit and clear central hub.')

    c=collection('PumpHall');hall(c,'H_PumpHall',160,128,42,wet=False,doors=(('N',0,'Arch'),('S',0,'Arch')))
    tunnel(c,'Tunnel_Dry_64',(0,0,96));connection_end(c,127.9)
    info=kit.COMPONENTS.get('Prop_pumpshell')
    if info:
        ys=[v.co.z/S for v in info['mesh'].vertices];scale=6.8/(max(ys)-min(ys))
        prop(c,'pumpshell',(0,0,0),0,scale)
    m=kit.Mesh('H_PumpControls')
    m.cylinder((2.2,4,-3.1),.16,2.2,'Steel',segments=8)
    m.cylinder((2.2,5.1,-3.1),.26,1.2,'SteelRed',segments=12,axis='X')
    m.cylinder((-1.4,4.8,-2.72),.65,.16,'Steel',segments=20,axis='Z')
    m.cylinder((-1.4,4.8,-2.83),.52,.08,'Tile',segments=20,axis='Z')
    m.box((-1.22,4.98,-2.89),(.05,.62,.05),'SteelRed',bevel=0,rotation=Matrix.Rotation(-.7,4,'Y'))
    finish(m,500);place(c,m.name)
    # Crates at corners; pump is the gameplay-required exception at hall centre.
    crates=kit.Mesh('H_PumpCrates')
    for x,z in ((-57,-37),(57,37)):
        crates.box((x,1.5,z),(4,3,4),'ServiceGrey',bevel=.07)
        for dx in (-1.4,1.4):crates.box((x+dx,1.5,z-2.04),(.2,3,.08),'Steel',bevel=0)
    finish(crates,200);place(c,crates.name)
    prop(c,'drums',(-57,0,34));prop(c,'drums',(59,0,-36))
    prop(c,'hosereel',(-78,7,-38),90);prop(c,'mopbucket',(58,0,32))
    prop(c,'vacuum',(-56,0,-34))
    small(c,'Extinguisher',(-77,3,35),90)
    cluster(c,'Cones',(53,0,-46));cluster(c,'Bucket',(-61,0,47))
    walk=kit.Mesh('H_PumpWalkways')
    for x in (-9,9):part(walk,'Pump Walkway Border',(x,.009,0),(.18,.016,110),'Cobalt',False,False)
    for z in (-9,9):part(walk,'Pump Walkway Border',(0,.01,z),(142,.016,.18),'Cobalt',False,False)
    finish(walk);place(c,walk.name)
    shot(c,'09_PumpHall_station',(-17,4.5,-23),(0,3.5,0),29,description='Dry 160 x 128 pump hall with 6.8-stud pump shell, red lever, gauge and clear routes.')

    if slides and 'SlideHall' in kit.COMPONENTS:
        c=collection('SlideHall');slides.place_prefab(c,'SlideHall')
        wr=next(m for m in kit.COMPONENTS['SlideHall']['markers'] if m['name']=='TerrainWater')
        water(c,wr['attrs']['Width'],wr['attrs']['Depth'],.1)
        for pos,power in (((-45,70,-30),11000),((65,69,-70),12000),((0,35,60),6500)):
            light(c,'H Slide panel bounce',pos,(0,20,0),power,16,(1,.88,.72))
        for x in (-82,82):
            for z in (-67,49):place(c,'OverheadRibs48',(x,76,z))
        for x,z in ((-90,70),(90,70)):
            small(c,'Bin',(x,0,z));cluster(c,'Towels',(x,0,z-4))
        shot(c,'10_SlideHall_deck',(86,60.5,38),(-9,35,-14),22,description='Flumes and helix from the elevated deck stair top.')
        shot(c,'11_SlideHall_pool',(-68,4.5,69),(23,39,-20),23,description='Flumes and helix from the pool edge.')
    else:NOTES.append('slides.py missing or build unavailable; slide reviews skipped.')

    c=collection('Arrival');hall(c,'H_Arrival',144,144,42,wet=False,
                                 doors=(('N',0,'Arch'),('S',0,'Arch')))
    place(c,'GateStory',(0,0,45))
    for x in (-65,65):
        for z in (-45,45):small(c,'Bin',(x,0,z))
    small(c,'Clock',(-70,8,18),90)
    shot(c,'12_Arrival_gate',(0,4.5,-29),(0,10,45),30,description='Dry arrival hall, clear spawn apron and sealed story gate.')

    shot(SCENES['PoolHall'],'13_DressedDeck_close',(-57,4.5,-62),(-67,2,-42),31,
         description='Player-eye deck detail: loungers, lifeguard chair, bins, towels and pool fittings.')
    shot(SCENES['TallHall'],'14_WetTunnel_lamps',(0,3.5,-132),(0,5,-75),23,
         description='Wet vaulted tunnel with water channel, bands, bulkhead lamps and daylight beyond.')


def label(c,text,pos,size):
    curve=bpy.data.curves.new('H Label','FONT');curve.body=text;curve.align_x='CENTER';curve.size=size*S
    o=bpy.data.objects.new('H '+text,curve);c.objects.link(o);o.location=kit.to_blender(pos)
    # Native text is in XY, already horizontal in Blender.
    mat=bpy.data.materials.get('H Ink')
    if not mat:
        mat=bpy.data.materials.new('H Ink');mat.diffuse_color=(.018,.055,.065,1)
    curve.materials.append(mat)


def validate(modules):
    rows=[];prop_spec=json.loads(Path(__file__).with_name('props_spec.json').read_text())
    arch=modules.get('modules_arch')
    extra=modules.get('modules_extra')
    for name,info in kit.COMPONENTS.items():
        mesh=info['mesh'];mesh.calc_loop_triangles();n=len(mesh.loop_triangles)
        budget=BUDGETS.get(name)
        if arch and name in arch.BUDGETS:budget=arch.BUDGETS[name]
        if extra and name in extra.BUDGETS:budget=extra.BUDGETS[name][1]
        if name.startswith('Tunnel_'):budget=3000
        if name.startswith('Passage_'):budget=1500
        if name.startswith('Prop_'):budget=prop_spec[name[5:]]['tris']
        if name.startswith('Small_'):budget=2500
        if budget is not None:assert n<=budget,(name,n,budget)
        assert all(math.isfinite(v) for p in mesh.vertices for v in p.co),name
        assert all(Path(im.filepath).exists() or im.packed_file for im in bpy.data.images
                   if im.source=='FILE' and im.filepath), 'Missing image texture'
        rows.append(dict(name=name,tris=n,budget=budget,parts=len(info['parts']),colliders=len(info['colliders'])))
    # Small-room details have per-feature budgets, not a whole-room cap.
    small=modules.get('rooms_small')
    if small:
        for name,details in small.DETAIL_TRIS.items():
            for feature,n in details:
                if feature=='Cubicle':assert n<=800,(name,feature,n)
    return rows


def render_shot(s,opts):
    sc=bpy.context.scene;c=SCENES[s['scene']]
    background=sc.world.node_tree.nodes['Background'].inputs['Color']
    prior_color=tuple(background.default_value)
    if s['scene'] in ('ExitFlume','Overview'):
        background.default_value=(.24,.27,.28,1)
    for col in sc.collection.children:col.hide_render=col!=c
    data=bpy.data.cameras.new('H Review camera');o=bpy.data.objects.new('H Review camera',data);c.objects.link(o)
    o.location=kit.to_blender(s['eye']);o.rotation_euler=(kit.to_blender(s['target'])-o.location).to_track_quat('-Z','Y').to_euler()
    data.lens=s['lens'];data.clip_start=.03;data.clip_end=1800
    if s['ortho']:
        data.type='ORTHO';data.ortho_scale=s['ortho']*S
        # Fit all visible scene geometry, including the long exit lead-in.
        points=[o.rotation_euler.to_matrix().transposed() @ (ob.matrix_world @ Vector(v.co)-o.location)
                for ob in c.objects if ob.type=='MESH' for v in ob.data.vertices]
        if points:
            lo=np.min(points,axis=0);hi=np.max(points,axis=0)
            delta=o.rotation_euler.to_matrix()@Vector(((lo[0]+hi[0])/2,(lo[1]+hi[1])/2,0))
            o.location+=delta
            data.ortho_scale=max(hi[0]-lo[0],(hi[1]-lo[1])*1920/1080)*1.08
    sc.camera=o
    folder=OUT/'draft' if opts.draft else OUT
    folder.mkdir(parents=True,exist_ok=True);path=folder/(s['name']+'.png')
    sc.render.filepath=str(path);bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(o,do_unlink=True)
    background.default_value=prior_color
    print('H_RENDER='+str(path),flush=True)
    return str(path)


def contact_sheet(paths,folder):
    # Use Blender's own image IO; no external process or dependency is required.
    if not paths:return
    cols=4;tw,th,bar=480,270,32;rows=math.ceil(len(paths)/cols)
    canvas=np.zeros((rows*(th+bar),cols*tw,4),np.float32);canvas[...,3]=1
    canvas[...,:3]=(.027,.039,.046)
    # Compact 5x7 raster font for filename labels.
    chars='ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_ -'
    glyphs=['01110100011000111111100011000110001','11110100011000111110100011000111110','01111100001000010000100001000001111','11110100011000110001100011000111110','11111100001000011110100001000011111','11111100001000011110100001000010000','01111100001000010111100011000101111','10001100011000111111100011000110001','11111001000010000100001000010011111','00111000100001000010100101001001100','10001100101010011000101001001010001','10000100001000010000100001000011111','10001110111010110101100011000110001','10001110011010110011100011000110001','01110100011000110001100011000101110','11110100011000111110100001000010000','01110100011000110001101011001001101','11110100011000111110101001001010001','01111100001000001110000010000111110','11111001000010000100001000010000100','10001100011000110001100011000101110','10001100011000110001100010101000100','10001100011000110101101011101110001','10001100010101000100010101000110001','10001100010101000100001000010000100','11111000010001000100010001000011111','01110100011001110101110011000101110','00100011000010000100001000010001110','01110100010000100010001000100011111','11110000010000101110000010000111110','00010001100101010010111110001000010','11111100001000011110000010000111110','01110100001000011110100011000101110','11111000010001000100010000100001000','01110100011000101110100011000101110','01110100011000101111000010000101110','00000000000000000000000000000011111','00000000000000000000000000000000000','00000000000000011111000000000000000']
    font=dict(zip(chars,glyphs))
    for i,p in enumerate(paths):
        im=bpy.data.images.load(p,check_existing=False);w,h=im.size
        ar=np.empty(w*h*4,np.float32);im.pixels.foreach_get(ar);ar=ar.reshape(h,w,4)
        thumb=ar[np.linspace(0,h-1,th).astype(int)[:,None],np.linspace(0,w-1,tw).astype(int)]
        x=(i%cols)*tw;y=(rows-1-i//cols)*(th+bar)
        canvas[y+bar:y+bar+th,x:x+tw]=thumb
        title=Path(p).stem.upper()[:38]
        for j,ch in enumerate(title):
            bits=font.get(ch,font[' '])
            for row in range(7):
                for k in range(5):
                    if bits[row*5+k]=='1':canvas[y+9+(6-row)*2:y+11+(6-row)*2,x+10+j*12+k*2:x+12+j*12+k*2,:3]=.8
        bpy.data.images.remove(im)
    im=bpy.data.images.new('H Contact sheet',cols*tw,rows*(th+bar),alpha=False)
    im.pixels.foreach_set(canvas.ravel());im.file_format='JPEG';im.filepath_raw=str(folder/'_sheet.jpg');im.save()
    bpy.data.images.remove(im)


def main():
    global WATER
    parser=argparse.ArgumentParser();parser.add_argument('--draft',action='store_true');parser.add_argument('--samples',type=int,default=64)
    parser.add_argument('--only',nargs='*');parser.add_argument('--export-only',action='store_true')
    opts=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    OUT.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    modules={};built=[]
    for name in MODULES:
        if not Path(__file__).with_name(name+'.py').exists():NOTES.append('Missing module '+name);continue
        module=importlib.import_module(name)
        if name=='props_meshy':module.TEXTURES=OUT/'textures'/'props'
        before=set(kit.COMPONENTS);module.build();modules[name]=module
        built.append(dict(module=name,components=len(set(kit.COMPONENTS)-before)))
        print('H_MODULE',name,built[-1]['components'],flush=True)
    WATER=water_material();build_scenes(modules.get('slides'))
    rows=validate(modules)
    kit.EXPORT_DIR=OUT/'export';manifest=kit.export()
    assert sum(c['tris'] for c in manifest['chunks'])==sum(r['tris'] for r in rows)
    sc=bpy.context.scene;sc.render.engine='BLENDER_EEVEE';sc.eevee.taa_render_samples=opts.samples
    sc.eevee.use_raytracing=True
    sc.render.resolution_x=1920;sc.render.resolution_y=1080;sc.render.resolution_percentage=50 if opts.draft else 100
    sc.render.image_settings.file_format='PNG';sc.render.film_transparent=False
    sc.world=bpy.data.worlds.new('H Daylight sky');sc.world.use_nodes=True
    nt=sc.world.node_tree
    nt.nodes['Background'].inputs['Color'].default_value=(.035,.23,.75,1)
    nt.nodes['Background'].inputs['Strength'].default_value=.16
    sc.view_settings.view_transform='AgX';sc.view_settings.look='AgX - Medium High Contrast';sc.view_settings.exposure=0
    paths=[]
    if not opts.export_only:
        for s in SHOTS:
            if opts.only and not any(k.lower() in s['name'].lower() for k in opts.only):continue
            paths.append(render_shot(s,opts))
        folder=OUT/'draft' if opts.draft else OUT
        # A final sheet includes all final renders, even after a scoped rerender.
        contact_sheet(sorted(str(p) for p in folder.glob('*.png')),folder)
    NOTES.extend(['No Studio, gameplay, multiplayer, mobile or publish checks were performed (offline approval task).',
                  'kit.part has no pitch parameter: review.py records full cframe for the single sloped Part and draws that exact frame.',
                  'Tall-hall low bands stop at door apertures; only upper bands run above door crowns (spec 4.1 low-band/unbroken wording conflicts).',
                  'Slide halls retain authored closed overhead and flat basin from slides.py; their builder was not modified.',
                  'Glass-block panels are inset overlays on sealed walls, preserving sight/collision; transmitted daylight is represented by review lighting.'])
    sources=[Path(__file__),Path(kit.__file__),kit.ROOT/'artifacts/level2-blender-20261002/KIT_SPEC.md']+[Path(m.__file__) for m in modules.values()]
    report=dict(modules=built,components=rows,renders=SHOTS,generatedRenders=paths,notes=sorted(set(NOTES)),
                sources={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources},
                engine='BLENDER_EEVEE',samples=opts.samples,resolution=[1920,1080],scope='H3 offline owner approval')
    (OUT/'verification.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    (OUT/'components.tsv').write_text('component\ttriangles\tbudget\tparts\tcolliders\n'+''.join(
        f"{r['name']}\t{r['tris']}\t{r['budget']}\t{r['parts']}\t{r['colliders']}\n" for r in rows),encoding='utf-8')
    print('H_OK',len(rows),'components',len(paths),'renders',flush=True)


if __name__=='__main__':main()
