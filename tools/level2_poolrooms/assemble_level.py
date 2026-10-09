"""Assemble a seeded Poolrooms layout for offline owner review.

D:/Blender/blender.exe -b --factory-startup --python-exit-code 1 -P
G:/Roblox/MongoTV/tools/level2_poolrooms/assemble_level.py -- [layout.json] [--draft] [--only name]
"""
import json
import math
import random
import shutil
import subprocess
import sys
from collections import Counter, defaultdict
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import bpy
from mathutils import Vector
import prkit as kit
import modules_arch as arch
import modules_tunnel as tunnels
import objectives

ROOT = Path('G:/Roblox/MongoTV')
DEFAULT = ROOT / 'artifacts/level2-poolrooms-20261003/layouts/layout_837834.json'
OUT = Path('G:/Blender/Level2_Poolrooms/review/LEVEL_FINAL')
BLEND = Path('G:/Blender/Level2_Poolrooms/Level2_Poolrooms_seed837834.blend')
kit.EXPORT_DIR = Path('G:/Blender/Level2_Poolrooms/jobs/L/export')
ARGS = sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
LAYOUT = Path(next((a for a in ARGS if a.endswith('.json')), DEFAULT))
DRAFT = '--draft' in ARGS
ONLY = ARGS[ARGS.index('--only')+1] if '--only' in ARGS else None
COUNTS = Counter()
PLACED = Counter()
OVERHEAD = []
LIGHTS = 0


def collection(name):
    c = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(c)
    return c


def place(col, name, pos=(0, 0, 0), yaw=0):
    assert name in kit.COMPONENTS, name
    obj = kit.place(col, name, pos, yaw)
    PLACED[name] += 1
    return obj


def part(mesh, name, center, size, mat='Tile', ground=False, collide=True):
    assert all(n > 0 for n in size), (name, size)
    assert not any(s in name for s in ('Ceiling', 'Skylight', 'Roof'))
    mesh.part(name, center, size, mat, ground=ground, collide=collide,
              attrs={'Level2_EntityGround': True} if ground else None)


def shell_piece(name, records, col, overhead=False, roof=None):
    m = kit.Mesh(name, Role='ProceduralHallShell')
    for rec in records:
        part(m, *rec)
    if roof:
        m.collider('Level 2 Hall Roof Collider',roof[0],roof[1],
                   attrs={'Level2_NoEntityGround':True})
    m.finish()
    place(col, name)
    if overhead:
        OVERHEAD.extend(o for o in col.objects if o.name.startswith(name))


def openings(hall, corridors):
    out = defaultdict(list)
    for c in corridors:
        if hall['Index'] not in (c['A'], c['B']):
            continue
        coord = c['From'] if hall['Index'] == c['A'] else c['To']
        if c['Axis'] == 'X':
            wall = 'W' if abs(coord-hall['MinX']) < abs(coord-hall['MaxX']) else 'E'
        else:
            wall = 'N' if abs(coord-hall['MinZ']) < abs(coord-hall['MaxZ']) else 'S'
        out[wall].append((c['Cross'], c['Width'], c))
    return out


def runs(lo, hi, gaps):
    cursor = lo
    for cross, width, c in sorted(gaps):
        a, b = max(lo, cross-width/2), min(hi, cross+width/2)
        if a > cursor+.1:
            yield cursor, a, None
        if b > a:
            yield a, b, c
        cursor = max(cursor, b)
    if hi > cursor+.1:
        yield cursor, hi, None


def well_centers(h, rng):
    x = (h['MinX']+h['MaxX'])/2
    z = (h['MinZ']+h['MaxZ'])/2
    typ = h['Type']
    if typ in ('BigPool', 'Arrival'):
        return []
    if typ=='PumpHall' or h.get('PumpIndex'):
        return [(x,z,10)]
    if typ == 'SpiralWell':
        return [(x+(h['MaxX']-h['MinX'])*.22, z+(h['MaxZ']-h['MinZ'])*.22, 10)]
    n = 1 if typ in ('PumpHall', 'PaddlingRoom') else min(3, max(1, int(h['Area']/18000)))
    return [(x+rng.uniform(-.22,.22)*(h['MaxX']-h['MinX']),
             z+rng.uniform(-.22,.22)*(h['MaxZ']-h['MinZ']), 10 if i == 0 else 6)
            for i in range(n)]


def overhead_parts(h, wells, col):
    idx, y = h['Index'], h['FloorY']+h['CeilingClass']
    xs = [h['MinX'], h['MaxX']]
    zs = [h['MinZ'], h['MaxZ']]
    for x,z,r in wells:
        half = r+5
        xs.extend((x-half,x+half)); zs.extend((z-half,z+half))
    xs, zs = sorted(set(xs)), sorted(set(zs))
    records=[]
    for a,b in zip(xs,xs[1:]):
        for c,d in zip(zs,zs[1:]):
            mx,mz=(a+b)/2,(c+d)/2
            if any(abs(mx-x)<1 and abs(mz-z)<1 for x,z,_ in wells):
                continue
            records.append((f'Level 2 Overhead Tile {idx} {len(records)+1}',
                            (mx,y+.4,mz),(b-a,.8,d-c),'Tile',False,False))
    roof=((h['MinX']+h['MaxX'])/2,y+.4,(h['MinZ']+h['MaxZ'])/2)
    shell_piece(f'Hall_{idx:02d}_Overhead',records,col,True,
                (roof,(h['MaxX']-h['MinX'],.8,h['MaxZ']-h['MinZ'])))
    COUNTS['roof_colliders'] += 1
    for x,z,r in wells:
        if r in (6,10):place(col,f'LightWell_R{r}',(x,y,z))


def hall_shell(h, corridors, col, rng):
    idx, fy = h['Index'], h['FloorY']
    x0,x1,z0,z1 = (h[k] for k in ('MinX','MaxX','MinZ','MaxZ'))
    cx,cz=(x0+x1)/2,(z0+z1)/2
    w,d=x1-x0,z1-z0
    typ=h['Type']
    dry=typ in ('Arrival','PumpHall','ExitHall') and typ!='ExitHall'
    depth=0 if dry else (.8 if typ=='PaddlingRoom' else min(2.0,h.get('DeepEnd',1.6)))
    floor_y=fy-depth
    m=kit.Mesh(f'Hall_{idx:02d}_Shell',Role='ProceduralHallShell')
    part(m,f'Level 2 Hall Water Floor {idx}',(cx,floor_y-.5,cz),(w,1,d),
         'Tile' if dry else 'Aqua',ground=True)
    gapmap=openings(h,corridors)
    if typ=='ExitHall':
        gapmap['E'].append((cz-10,18.2,{'Index':1000+idx,'Width':18.2,'ExitPortal':True}))
    height=h['CeilingClass']
    for side,lo,hi,face in (('N',x0,x1,z0),('S',x0,x1,z1),
                            ('W',z0,z1,x0),('E',z0,z1,x1)):
        for a,b,c in runs(lo,hi,gapmap[side]):
            spans=((0,75.3),(92.3,height)) if c and c.get('ExitPortal') else (
                ((12 if c['Width']==12 else 30),height),) if c else ((0,height),)
            for bot,top in spans:
                if top-bot < .1:continue
                center=((a+b)/2,fy+(bot+top)/2,face) if side in 'NS' else (face,fy+(bot+top)/2,(a+b)/2)
                size=(b-a,top-bot,2) if side in 'NS' else (2,top-bot,b-a)
                part(m,f'Level 2 Hall {idx} {side} Wall {int(a)} {bot}',center,size)
            if c is None and b-a >= 16:
                for top_cove in (False,True):
                    yy=fy+(height-3 if top_cove else 0)
                    length=b-a
                    cursor=a
                    while length>=15.9:
                        seg=64 if length>=64 else 32 if length>=32 else 16
                        along=cursor+seg/2
                        pos=(along,yy,face-1 if side=='N' else face+1) if side in 'NS' else (face-1 if side=='E' else face+1,yy,along)
                        yaw={'N':0,'S':180,'E':90,'W':270}[side]
                        place(col,f'Cove{"Top" if top_cove else "Base"}{seg}',pos,yaw)
                        cursor+=seg;length-=seg
        # The broad low threshold at each mouth is clear walkable tile.
        for cross,width,c in gapmap[side]:
            if c.get('ExitPortal'):continue
            pos=(cross,fy-.35,face) if side in 'NS' else (face,fy-.35,cross)
            size=(width,.7,8) if side in 'NS' else (8,.7,width)
            part(m,f'Level 2 Hall {idx} Door Approach {c["Index"]}',pos,size,ground=True)
    m.finish();place(col,m.name)
    radius=24 if typ=='PaddlingRoom' or min(w,d)>200 else 8 if min(w,d)<112 else 16
    ch=height if height in (34,42,52) else 52
    for sx in (-1,1):
        for sz in (-1,1):
            corner_x=x1 if sx==1 else x0
            corner_z=z1 if sz==1 else z0
            wall_x='E' if sx==1 else 'W'
            wall_z='S' if sz==1 else 'N'
            near_door=(any(abs(cross-corner_x)<radius+width/2+2
                           for cross,width,_ in gapmap[wall_z]) or
                       any(abs(cross-corner_z)<radius+width/2+2
                           for cross,width,_ in gapmap[wall_x]))
            cr=8 if near_door else radius
            pos=(corner_x-sx*cr,fy,corner_z-sz*cr)
            yaw={(1,1):180,(-1,1):270,(-1,-1):0,(1,-1):90}[(sx,sz)]
            place(col,f'CornerCove_R{cr}_H{ch}',pos,yaw)
            for top_cove in (False,True):
                place(col,f'Cove{"Top" if top_cove else "Base"}Corner_R{cr}',
                      (pos[0],fy+height-3 if top_cove else fy,pos[2]),yaw)
    if typ not in ('Arrival','ExitHall'):
        # One uninterrupted raised edge route; module Part records are the Roblox ground.
        for z in range(int(z0+16),int(z1-15),32):
            place(col,'Walkway_Straight32',(x0+6,fy,z),90)
            preview=kit.Mesh(f'Walkway preview {idx} {z}')
            preview.box((x0+6,fy+.05,z),(9.4,.8,32),'Tile',bevel=0)
            ob=bpy.data.objects.new(preview.name,preview.finish(register=False));col.objects.link(ob)
    wells=well_centers(h,rng)
    if typ=='ExitHall':wells=[(x1-29,cz,14)]
    overhead_parts(h,wells,col)
    COUNTS['halls']+=1
    if depth:
        water(col,(cx,fy+.1,cz),(w-.6,d-.6),idx)
        COUNTS['water_regions']+=1
    return wells


def safe_spot(h,x,z,margin=18):
    return (h['MinX']+margin < x < h['MaxX']-margin and
            h['MinZ']+margin < z < h['MaxZ']-margin and
            abs(x-(h['MinX']+h['MaxX'])/2)>17 and
            abs(z-(h['MinZ']+h['MaxZ'])/2)>17)


def hall_dressing(h,col,wells):
    rng=random.Random(h['LocalSeed'])
    x0,x1,z0,z1=(h[k] for k in ('MinX','MaxX','MinZ','MaxZ'))
    cx,cz=(x0+x1)/2,(z0+z1)/2
    fy,typ,height=h['FloorY'],h['Type'],h['CeilingClass']
    def add(name,x,z,y=0,yaw=0): place(col,name,(x,fy+y,z),yaw)
    if typ in ('ColumnHall','BigPool','SpiralWell','VaultArcade','PaddlingRoom'):
        spacing=32 if typ=='BigPool' else 34
        points=[]
        for x in range(math.ceil((x0+20)/spacing)*spacing,math.floor((x1-20)/spacing)*spacing+1,spacing):
            for z in range(math.ceil((z0+20)/spacing)*spacing,math.floor((z1-20)/spacing)*spacing+1,spacing):
                if safe_spot(h,x,z,20):points.append((x,z))
        rng.shuffle(points)
        limit=2 if typ=='PaddlingRoom' else max(3,int(h['Area']/1200))
        for i,(x,z) in enumerate(points[:limit]):
            dia=6 if typ=='PaddlingRoom' else 16 if typ=='ColumnHall' and i==0 else 10
            add(f'Column_D{dia}_H{height if height in (34,42,52) else 52}',x,z)
        if typ=='BigPool' and points:
            x,z=points[0]
            add('Walkway_End',x+8,z)
            for lx in range(int(x0+16),int(x1-16),16):
                for lz in range(int(z0+16),int(z1-16),16):
                    add('LightRound' if (lx//16+lz//16)%3==0 else 'LightRound_Unlit',
                        lx,lz,height)
    if typ=='VaultArcade':
        for x in range(int(x0+32),int(x1-16),32):
            for z in range(int(z0+32),int(z1-16),32):
                if safe_spot(h,x,z,22):
                    add(f'VaultBay32_H{34 if height==34 else 42}',x,z,height-34 if height==34 else height-42)
                    add('VaultPier',x-16,z-16)
        add('Walkway_Bend16',cx+min(35,(x1-x0)*.25),cz+min(35,(z1-z0)*.25))
    if typ=='CurvedChannel':
        for side in (-1,1):
            x=cx+side*min(34,(x1-x0)*.3)
            z=cz+side*min(36,(z1-z0)*.22)
            if safe_spot(h,x,z,12):add(f'CurveWall_Q16_H{height}',x,z,0,90 if side>0 else 270)
        for z in range(int(z0+28),int(z1-20),32):
            add('Walkway_Straight32',x0+11,z,0,90)
    if typ=='SpiralWell':
        if wells:
            x,z,_=wells[0]
            add(f'SpiralStairWell_H{height}',x,z)
    if typ=='PaddlingRoom':
        for z in (z0+22,z1-22):add('PoolSteps_Curved',cx,z)
        COUNTS['foam_spawns']+=1
    if typ=='PumpHall' or h.get('PumpIndex'):
        for name in ('PumpStation','PumpLever','PumpNeedle','PumpLamp'):add(name,cx,cz)
        COUNTS['pumps']+=1
    if typ=='Arrival':
        add('ArrivalDoor',cx,z0+2)
        add('SunSlit',cx+25,z1-2,15)
    if typ=='ExitHall':
        anchor=(x1-29,fy,cz)
        for name in ('ExitSpiral','ExitPlatform','ExitMouth','ExitSkylight'):
            place(col,name,anchor)
        # A narrow bounce from the open collar picks out the stair below the deck.
        global LIGHTS
        source=kit.to_blender((anchor[0]-44,fy+height-16,cz+12))
        target=kit.to_blender((anchor[0]-29,fy+28,cz+7))
        data=bpy.data.lights.new('Exit stair daylight','SPOT')
        data.energy=4800;data.color=(1,.87,.68)
        data.spot_size=math.radians(45);data.spot_blend=.02
        ob=bpy.data.objects.new(data.name,data);col.objects.link(ob)
        ob.location=source;ob.rotation_euler=(target-source).to_track_quat('-Z','Y').to_euler()
        LIGHTS+=1
        # The tube shares the fixed no-rotation exit frame and continues east.
        for name in kit.COMPONENTS:
            if name.startswith('ExitTubeVisual'):place(col,name,(681,fy+83.3,cz-10))
        COUNTS['exit_halls']+=1
    if typ!='BigPool' and typ!='Arrival' and typ!='ExitHall':
        n=min(4,max(1,int(h['Area']/1500)))
        for i in range(n):
            x=rng.uniform(x0+12,x1-12);z=rng.uniform(z0+12,z1-12)
            if not safe_spot(h,x,z,10):continue
            add('DrainHole',x,z)
    if typ=='BigPool':
        for i in range(min(6,max(3,int((x1-x0)/40)))):
            add('WallVoid',x0+24+i*36,z1-2,0)
    elif typ not in ('Arrival','ExitHall','Chamber'):
        add('WallVoid',x0+min(24,(x1-x0)*.3),z1-2,max(8,height*.55))
    if wells:
        for x,z,r in wells:
            daylight(col,(x,fy+height+3,z),r)
            lamp(col,(x,fy+height-6,z),2100,22)
    else:
        lamp(col,(cx,fy+min(height-5,30),cz),1800,24)
    if typ=='BigPool':
        for x in range(int(x0+16),int(x1-16),48):
            for z in range(int(z0+16),int(z1-16),48):
                lamp(col,(x,fy+height-2,z),700,10)


def chamber(h, corridors, col):
    name=h.get('Prefab') or 'Chamber_D'
    assert name in kit.COMPONENTS,name
    cx=(h['MinX']+h['MaxX'])/2;cz=(h['MinZ']+h['MaxZ'])/2
    fy=h['FloorY']
    placed=place(col,name,(cx,fy,cz),h.get('Rotation',0))
    # Keep shared authored mesh; replace the preview Parts so connected socket plugs are open.
    for ob in list(col.objects):
        if ob.name.startswith(name) and ob.data == kit.COMPONENTS[name].get('preview'):
            bpy.data.objects.remove(ob,do_unlink=True)
    gaps=openings(h,corridors)
    records=[]
    for rec in kit.COMPONENTS[name]['parts']:
        plug=rec['attrs'].get('SocketPlug')
        if plug:
            side=plug[0]
            offset=(0,-16,16)[int(plug[1])]
            axis_center=cx if side in 'NS' else cz
            if any(abs(c['Cross']-(axis_center+offset))<6.1 for _,_,c in gaps[side]):
                continue
        records.append(rec)
    for rec in records:
        m=kit.Mesh('Preview_'+rec['name'])
        m.box(rec['cf'][:3],rec['size'],rec['material'],bevel=0)
        ob=bpy.data.objects.new(rec['name'],m.finish(register=False));col.objects.link(ob)
        ob.location=kit.to_blender((cx,fy,cz))
        if 'Overhead' in rec['name']:OVERHEAD.append(ob)
    water(col,(cx,fy+.1,cz),(h['MaxX']-h['MinX']-1,h['MaxZ']-h['MinZ']-1),h['Index'])
    COUNTS['chamber_plugs_removed']+=len(kit.COMPONENTS[name]['parts'])-len(records)
    COUNTS['water_regions']+=1;COUNTS['chambers']+=1
    lamp(col,(cx+9,fy+11,cz-10),500,10)


def unlit_tunnel(name):
    variant=name+'_Unlit'
    if variant not in kit.COMPONENTS:
        source=kit.COMPONENTS[name]
        kit.COMPONENTS[variant]={**source,
                                 'markers':[m for m in source['markers'] if m['name']!='LampLight'],
                                 'chunks':[]}
    return variant


def corridor(c,col):
    narrow=c['Width']==12 or c['Kind']=='Narrow'
    variant=c['Variant']
    name=f'{"Pipe" if narrow else "RoundTunnel"}_{variant}_{c["Length"]}'
    if name not in kit.COMPONENTS:
        assert name=='Pipe_Stair4_24',name
        tunnels.pipe('Stair4',24)
    if c['Index']%8:name=unlit_tunnel(name)
    axis=c['Axis']
    mid=(c['From']+c['To'])/2
    base_y=min(c['FromY'],c['ToY']) if variant.startswith('Stair') else c['FromY']
    pos=(mid,base_y,c['Cross']) if axis=='X' else (c['Cross'],base_y,mid)
    yaw=(90 if axis=='X' else 0)+(180 if variant.startswith('Stair') and c['ToY']<c['FromY'] else 0)
    place(col,name,pos,yaw)
    if variant=='Wet' or narrow and variant=='Flat':
        if axis=='X':water(col,(mid,c['FromY']+.1,c['Cross']),(c['Length']-.5,11 if narrow else 18),c['Index'])
        else:water(col,(c['Cross'],c['FromY']+.1,mid),(11 if narrow else 18,c['Length']-.5),c['Index'])
        COUNTS['water_regions']+=1
    if c['Index']==43:  # A poolroom aperture lights the far end of the pipe review view.
        global LIGHTS
        source=(c['To']+8,c['ToY']+12,c['Cross']) if axis=='X' else (c['Cross'],c['ToY']+12,c['To']+8)
        target=(c['To']-15,c['ToY']+2,c['Cross']) if axis=='X' else (c['Cross'],c['ToY']+2,c['To']-15)
        data=bpy.data.lights.new('Daylight beyond narrow pipe','SPOT')
        data.energy=4200;data.color=(1,.89,.72)
        data.spot_size=math.radians(68);data.spot_blend=.02
        ob=bpy.data.objects.new(data.name,data);col.objects.link(ob)
        ob.location=kit.to_blender(source)
        ob.rotation_euler=(kit.to_blender(target)-ob.location).to_track_quat('-Z','Y').to_euler()
        LIGHTS+=1
    if c['Kind']=='PressureDoor':COUNTS['pressure_doors']+=1
    COUNTS['corridors']+=1


def water(col,center,size,index):
    mesh=bpy.data.meshes.new(f'Water {index}')
    half_x,half_z=size[0]*kit.S/2,size[1]*kit.S/2
    mesh.from_pydata([(-half_x,-half_z,0),(half_x,-half_z,0),
                      (half_x,half_z,0),(-half_x,half_z,0)],[],[(0,1,2,3)])
    mesh.materials.append(WATER)
    ob=bpy.data.objects.new(f'Water {index}',mesh);col.objects.link(ob)
    ob.location=kit.to_blender(center)
    ob['l2k_water']=True
    # Local mesh XY maps to world horizontal XY in Blender; Blender Y is -Roblox Z.


def lamp(col,position,energy,radius):
    global LIGHTS
    data=bpy.data.lights.new('Warm aperture bounce','POINT')
    data.energy=energy*.3;data.shadow_soft_size=kit.S*.2
    data.color=(1,.86,.68)
    ob=bpy.data.objects.new(data.name,data);col.objects.link(ob)
    ob.location=kit.to_blender(position)
    LIGHTS+=1


def daylight(col,position,radius):
    global LIGHTS
    data=bpy.data.lights.new('Hard daylight through well','SPOT')
    data.energy=5000 if radius>=10 else 2800
    data.color=(1,.88,.71)
    data.spot_size=math.radians(68 if radius>=10 else 53)
    data.spot_blend=.015
    data.shadow_soft_size=kit.S*.08
    ob=bpy.data.objects.new(data.name,data);col.objects.link(ob)
    ob.location=kit.to_blender(position)
    ob.rotation_euler=(0,0,0)
    LIGHTS+=1


def lighting():
    global WATER
    watermat=bpy.data.materials.new('PR shallow green water')
    watermat.use_nodes=True
    nodes=watermat.node_tree.nodes;links=watermat.node_tree.links
    nodes.clear()
    output=nodes.new('ShaderNodeOutputMaterial')
    clear=nodes.new('ShaderNodeBsdfTransparent')
    clear.inputs['Color'].default_value=(.94,.99,.93,1)
    shine=nodes.new('ShaderNodeBsdfGlossy')
    shine.inputs['Color'].default_value=(.62,.78,.66,1)
    shine.inputs['Roughness'].default_value=.07
    mix=nodes.new('ShaderNodeMixShader')
    fresnel=nodes.new('ShaderNodeFresnel');fresnel.inputs['IOR'].default_value=1.333
    ramp=nodes.new('ShaderNodeValToRGB')
    ramp.color_ramp.elements[0].position=.02
    ramp.color_ramp.elements[0].color=(.13,.13,.13,1)
    ramp.color_ramp.elements[1].position=.55
    ramp.color_ramp.elements[1].color=(.78,.78,.78,1)
    links.new(fresnel.outputs['Fac'],ramp.inputs['Fac'])
    links.new(ramp.outputs['Color'],mix.inputs[0])
    links.new(clear.outputs[0],mix.inputs[1]);links.new(shine.outputs[0],mix.inputs[2])
    links.new(mix.outputs[0],output.inputs['Surface'])
    bump=nodes.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.22
    bump.inputs['Distance'].default_value=.035
    tex=nodes.new('ShaderNodeTexNoise');tex.inputs['Scale'].default_value=2.5
    tex.inputs['Detail'].default_value=2
    geom=nodes.new('ShaderNodeNewGeometry');links.new(geom.outputs['Position'],tex.inputs['Vector'])
    links.new(tex.outputs['Fac'],bump.inputs['Height']);links.new(bump.outputs['Normal'],shine.inputs['Normal'])
    WATER=watermat
    world=bpy.data.worlds.new('Poolrooms green sky');world.use_nodes=True
    bg=world.node_tree.nodes.get('Background')
    sky=world.node_tree.nodes.new('ShaderNodeTexSky')
    sky.sky_type='MULTIPLE_SCATTERING';sky.sun_elevation=math.radians(28)
    skybg=world.node_tree.nodes.new('ShaderNodeBackground')
    world.node_tree.links.new(sky.outputs['Color'],skybg.inputs['Color'])
    skybg.inputs['Strength'].default_value=.8
    bg.inputs['Color'].default_value=(.09,.17,.105,1)
    bg.inputs['Strength'].default_value=.32
    path=world.node_tree.nodes.new('ShaderNodeLightPath')
    sky_mix=world.node_tree.nodes.new('ShaderNodeMixShader')
    world.node_tree.links.new(path.outputs['Is Camera Ray'],sky_mix.inputs[0])
    world.node_tree.links.new(bg.outputs[0],sky_mix.inputs[1])
    world.node_tree.links.new(skybg.outputs[0],sky_mix.inputs[2])
    world.node_tree.links.new(sky_mix.outputs[0],world.node_tree.nodes['World Output'].inputs['Surface'])
    bpy.context.scene.world=world
    sun_data=bpy.data.lights.new('Hard warm daylight 5300 K','SUN')
    sun_data.energy=5.0;sun_data.angle=math.radians(.4);sun_data.color=(1,.87,.69)
    ob=bpy.data.objects.new(sun_data.name,sun_data);bpy.context.scene.collection.objects.link(ob)
    direction=Vector((-.2,.12,-1)).normalized()
    ob.rotation_euler=direction.to_track_quat('-Z','Y').to_euler()


def tile_ambient():
    # Just enough tile bounce to resolve the darkest passages.
    for name,strength in (('Tile',.025),('TileShade',.018),('Aqua',.09),('Worn',.02)):
        mat=kit.MATERIALS[name]['blender'];nt=mat.node_tree
        bs=nt.nodes.get('Principled BSDF')
        source=next((link.from_socket for link in nt.links if link.to_socket==bs.inputs['Base Color']),None)
        if source:nt.links.new(source,bs.inputs['Emission Color'])
        bs.inputs['Emission Strength'].default_value=strength


def split_exit_tube():
    """Keep the authored path/UVs, but enforce the 4000-triangle chunk budget."""
    for name in list(kit.COMPONENTS):
        if not name.startswith('ExitTubeVisual'):continue
        info=kit.COMPONENTS.pop(name);src=info['mesh'];src.calc_loop_triangles()
        groups=[];group=[];tris=0
        for poly in src.polygons:
            count=len(poly.vertices)-2
            if tris+count>3900 and group:
                groups.append(group);group=[];tris=0
            group.append(poly);tris+=count
        if group:groups.append(group)
        for k,polys in enumerate(groups,1):
            dst=bpy.data.meshes.new(f'{name}_part{k:02d}')
            dst.from_pydata([tuple(v.co) for v in src.vertices],[],[list(p.vertices) for p in polys])
            for mat in src.materials:dst.materials.append(mat)
            uv=dst.uv_layers.new(name='UVMap')
            srcuv=src.uv_layers.active.data
            for old,new in zip(polys,dst.polygons):
                new.material_index=old.material_index;new.use_smooth=old.use_smooth
                for ol,nl in zip(old.loop_indices,new.loop_indices):uv.data[nl].uv=srcuv[ol].uv
            kit.register_mesh(f'{name}_part{k:02d}',dst,
                              markers=info['markers'] if k==1 else (),**info['attrs'])


def camera(col,eye,target,ortho=None,lens=24):
    data=bpy.data.cameras.new('Review camera');ob=bpy.data.objects.new(data.name,data);col.objects.link(ob)
    ob.location=kit.to_blender(eye)
    toward=kit.to_blender(target)-ob.location
    ob.rotation_euler=toward.to_track_quat('-Z','Y').to_euler()
    data.type='ORTHO' if ortho else 'PERSP'
    if ortho:data.ortho_scale=ortho*kit.S
    else:data.lens=lens
    bpy.context.scene.camera=ob
    return ob


def shots(data):
    halls=data['Halls'];corr=data['Corridors']
    def htype(t,n=0):return [h for h in halls if h['Type']==t][n]
    def eye(h,fx=.24,fz=.18):
        return (h['MinX']+(h['MaxX']-h['MinX'])*fx,h['FloorY']+4.5,
                h['MinZ']+(h['MaxZ']-h['MinZ'])*fz)
    def center(h,dy=8):return ((h['MinX']+h['MaxX'])/2,h['FloorY']+dy,(h['MinZ']+h['MaxZ'])/2)
    spec=[]
    for title,h,fx,fz,dy in (
        ('01_column_hall',htype('ColumnHall'),.22,.1,9),
        ('02_big_pool',htype('BigPool'),.18,.15,9),
        ('03_vault_arcade',htype('VaultArcade'),.17,.16,13),
        ('04_curved_channel',htype('CurvedChannel'),.5,.1,8),
        ('05_spiral_well',htype('SpiralWell'),.12,.16,20),
        ('06_paddling_room',htype('PaddlingRoom'),.2,.16,7),
        ('07_pump_hall',htype('PumpHall'),.28,.2,5),
        ('09_arrival',htype('Arrival'),.5,.18,8),
        ('13_chamber',next(h for h in halls if h['Index']==41),.18,.18,7)):
        if title=='07_pump_hall':
            cx,_,cz=center(h)
            spec.append((title,(cx-18,h['FloorY']+4.5,cz+11),(cx,h['FloorY']+4,cz)))
        elif title=='09_arrival':
            cx,_,cz=center(h)
            spec.append((title,(cx,h['FloorY']+4.5,cz+20),
                         (cx,h['FloorY']+10,h['MinZ']+2)))
        elif title=='05_spiral_well':
            cx,_,cz=center(h)
            wx=cx+(h['MaxX']-h['MinX'])*.22
            wz=cz+(h['MaxZ']-h['MinZ'])*.22
            spec.append((title,(wx+45,h['FloorY']+4.4,wz+15),
                         (wx,h['FloorY']+21,wz)))
        elif title=='02_big_pool':
            spec.append((title,(h['MinX']+44,h['FloorY']+4.2,h['MinZ']+8),
                         (h['MinX']+48,h['FloorY']+8,h['MaxZ']-9)))
        elif title=='13_chamber':
            cx,_,cz=center(h)
            spec.append((title,(cx-10,h['FloorY']+3.5,cz+12),
                         (cx+11,h['FloorY']+8.2,h['MinZ']+2)))
        elif title=='04_curved_channel':
            cx,_,cz=center(h)
            spec.append((title,(cx-50,h['FloorY']+4.5,cz-55),
                         (cx+32,h['FloorY']+10,cz+36)))
        else:spec.append((title,eye(h,fx,fz),center(h,dy)))
    wet=next(c for c in corr if c['Variant']=='Wet' and c['Kind']=='Open')
    stair=next(c for c in corr if c['Variant']=='Stair8' and c['Kind']=='Open')
    pipe=next(c for c in corr if c['Kind']=='Narrow' and c['Length']>=48)
    for title,c in (('10_round_tunnel_wet',wet),('11_stair_tunnel',stair),('12_narrow_pipe',pipe)):
        along=c['From']+6;far=c['To']+14
        ey=(along,c['FromY']+4.5,c['Cross']) if c['Axis']=='X' else (c['Cross'],c['FromY']+4.5,along)
        ta=(far,c['ToY']+4,c['Cross']) if c['Axis']=='X' else (c['Cross'],c['ToY']+4,far)
        spec.append((title,ey,ta))
    # A continuous graph view through the actual arrival connector into the next hall.
    a=data['Arrival'];c=next(c for c in corr if a['Index'] in (c['A'],c['B']))
    other=halls[(c['B'] if c['A']==a['Index'] else c['A'])-1]
    spec.append(('14_connected_spaces',center(a,4.5),center(other,8)))
    # A second view of the exit gives the high circular aperture and tube context.
    ex=htype('ExitHall');exz=(ex['MinZ']+ex['MaxZ'])/2
    exx=ex['MaxX']-29
    spec.insert(7,('08_exit_hall',(exx-125,ex['FloorY']+53,exz+70),
                   (exx+8,ex['FloorY']+78,exz-9)))
    spec.append(('15_exit_platform',(exx-66,ex['FloorY']+77,exz+50),
                 (exx+12,ex['FloorY']+84,exz-10)))
    return spec


def configure_render():
    sc=bpy.context.scene
    sc.render.engine='CYCLES'
    prefs=bpy.context.preferences.addons['cycles'].preferences
    try:
        prefs.compute_device_type='OPTIX'
        prefs.get_devices()
        for device in prefs.devices:
            device.use=device.type=='OPTIX'
        if any(d.use for d in prefs.devices):
            sc.cycles.device='GPU'
            print('LEVEL_RENDER_DEVICE=OPTIX',flush=True)
    except (TypeError,RuntimeError):
        print('LEVEL_RENDER_DEVICE=CPU',flush=True)
    sc.cycles.samples=24 if DRAFT else 160
    sc.cycles.use_denoising=True
    sc.render.resolution_x=960 if DRAFT else 1920
    sc.render.resolution_y=540 if DRAFT else 1080
    sc.render.resolution_percentage=100
    sc.render.image_settings.file_format='PNG'
    sc.view_settings.view_transform='AgX'
    sc.view_settings.look='AgX - Medium High Contrast'
    sc.view_settings.exposure=.35
    sc.render.film_transparent=False
    sc.camera=None
    sc.render.image_settings.color_mode='RGB'


def estimate():
    total=0
    for name,n in PLACED.items():
        i=kit.COMPONENTS[name]
        mesh=i['mesh'];mesh.calc_loop_triangles()
        chunks=sum(any(p.material_index==j for p in mesh.polygons) for j in range(len(mesh.materials)))
        total+=n*(chunks+len(i['parts'])+len(i['colliders'])+len(i['markers'])+
                  (1 if name.startswith(('RoundTunnel','Pipe','Chamber','ExitTube')) else 0))
    return total-COUNTS['chamber_plugs_removed']+COUNTS['halls']+COUNTS['chambers']+5


def contact_sheet():
    python=shutil.which('python')
    if not python:return
    code='''from PIL import Image,ImageDraw
from pathlib import Path
import sys
p=Path(sys.argv[1]); files=[f for f in sorted(p.glob('*.png')) if (f.stem[:2].isdigit() and not f.stem.endswith('_draft'))]
assert len(files)==17,len(files)
sheet=Image.new('RGB',(1600,5*250),'#17231f');draw=ImageDraw.Draw(sheet)
for i,f in enumerate(files):
    im=Image.open(f).convert('RGB'); im.thumbnail((394,220))
    x=(i%4)*400;y=(i//4)*250
    sheet.paste(im,(x,y+25));draw.text((x+6,y+5),f.stem.replace('_',' ').title(),fill='white')
sheet.save(p/'_sheet.jpg',quality=91)
'''
    subprocess.run([python,'-c',code,str(OUT)],check=True)


def main():
    if '--sheet-only' in ARGS:
        contact_sheet()
        return
    bpy.ops.wm.read_factory_settings(use_empty=True)
    OUT.mkdir(parents=True,exist_ok=True)
    data=json.loads(LAYOUT.read_text(encoding='utf-8'))
    lighting()
    tunnels.build();arch.build();objectives.build();split_exit_tube();tile_ambient()
    lamp_info=kit.COMPONENTS['LightRound']
    kit.register_mesh('LightRound_Unlit',lamp_info['mesh'],**lamp_info['attrs'])
    # These functions assert each authored component's triangle budget.
    for name,info in kit.COMPONENTS.items():
        info['mesh'].calc_loop_triangles()
        n=len(info['mesh'].loop_triangles)
        cap=4000 if name.startswith(('RoundTunnel','Chamber','ExitSpiral','VaultBay','CurveWall','SpiralStairWell','ExitTubeVisual')) else 1500
        assert n<=cap,(name,n,cap)
    col=collection('Generated Level 2')
    halls=data['Halls'];corr=data['Corridors']
    for h in halls:
        if h['Type']=='Chamber':chamber(h,corr,col)
        else:
            wells=hall_shell(h,corr,col,random.Random(h['LocalSeed']))
            hall_dressing(h,col,wells)
    for c in corr:corridor(c,col)
    if not DRAFT and not ONLY:
        manifest=kit.export()
        assert all(c['tris']<=(4000 if c['component'].startswith(('RoundTunnel','Chamber','ExitSpiral','VaultBay','CurveWall','SpiralStairWell','ExitTubeVisual')) else 1500)
                   for c in manifest['chunks'])
    stats={'seed':data['Seed'],'layout':str(LAYOUT),'halls':len(halls),
           'corridors':len(corr),'hallTypes':dict(Counter(h['Type'] for h in halls)),
           'corridorKinds':dict(Counter(c['Kind'] for c in corr)),
           'componentPlacements':sum(PLACED.values()),'placementsByComponent':dict(PLACED),
           'partRecords':sum(PLACED[n]*len(kit.COMPONENTS[n]['parts']) for n in PLACED)-COUNTS['chamber_plugs_removed'],
           'colliderRecords':sum(PLACED[n]*len(kit.COMPONENTS[n]['colliders']) for n in PLACED),
           'componentTriangles':{n:len(kit.COMPONENTS[n]['mesh'].loop_triangles) for n in PLACED},
           'waterRegions':COUNTS['water_regions'],'reviewLightObjects':LIGHTS+1,
           'runtimeLightMarkers':sum(PLACED[n]*sum(bool(m['name'] in ('Light','LampLight') or
                                      m['attrs'].get('lightType')) for m in kit.COMPONENTS[n]['markers']) for n in PLACED),
           'estimatedRobloxInstances':estimate(),'notes':'Counts placed MeshPart chunks, Parts, colliders, markers, hall and corridor models, and five folders. Connected chamber plugs are removed. Excludes terrain water, render-only lights, active entities, and exit ride collision.'}
    (OUT/'stats.json').write_text(json.dumps(stats,indent=2),encoding='utf-8')
    print('LEVEL_STATS='+json.dumps({k:stats[k] for k in ('halls','corridors','componentPlacements','partRecords','estimatedRobloxInstances')}),flush=True)
    configure_render()
    if not DRAFT and not ONLY:bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
    camcol=collection('Review cameras')
    views=[('00_overview',(1650,1750,-1260),(0,0,240),2600),
           ('00b_top_down',(0,1900,240),(0,0,240),2800)]
    views += [(name,eye,target,None) for name,eye,target in shots(data)]
    for name,eye,target,ortho in views:
        if ONLY and name!=ONLY:continue
        for ob in OVERHEAD:ob.hide_render=bool(ortho)
        for ob in col.objects:
            if ob.get('l2k_water'):ob.hide_render=(name=='00b_top_down')
            if ob.get('l2k_component')=='ExitSkylight':ob.hide_render=bool(ortho)
        cam=camera(camcol,eye,target,ortho,16 if name in ('08_exit_hall','15_exit_platform') else 18 if name=='05_spiral_well' else 24)
        bpy.context.scene.render.filepath=str(OUT/(name+('_draft' if DRAFT else '')+'.png'))
        bpy.ops.render.render(write_still=True)
        print('LEVEL_RENDER='+bpy.context.scene.render.filepath,flush=True)
        bpy.data.objects.remove(cam,do_unlink=True)
    if not DRAFT and not ONLY:contact_sheet()
    print('LEVEL_DONE',flush=True)


if __name__=='__main__':main()
