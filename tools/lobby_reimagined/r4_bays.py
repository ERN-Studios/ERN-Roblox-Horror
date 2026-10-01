"""Blender bay kit for the isolated R4 lobby; no Studio or file writes.

`build_bays(globals())` uses the parent's Geometry/material/place/collider/light
helpers. Coordinates here are Blender X,Y,Z (one unit = one Roblox stud).
Each room opens towards local -Y; pads reproduce measured original WORLD
X +/-9, Roblox Z +/-13.2 offsets rather than rotating the pad arrangement.
The caller owns gateways/connectors, asset maps, export and runtime UI/actions.
"""
from __future__ import annotations

import math

RADIUS, THICKNESS, FLOOR_TOP, HEIGHT = 28.0, .65, .8, 22.0
CEILING_BOTTOM = FLOOR_TOP + HEIGHT
ENTRY_START, ENTRY_END = math.radians(246), math.radians(294)
PAD_RADIUS = 7.41


def _linear(rgb):
    return tuple(c/255/12.92 if c/255 <= .04045
                 else ((c/255+.055)/1.055)**2.4 for c in rgb)


def _rotate(v, yaw):
    c, s = math.cos(yaw), math.sin(yaw)
    return (c*v[0]-s*v[1], s*v[0]+c*v[1], v[2])


def _box(g, center, size, material, rotation=(0, 0, 0)):
    """A box with full XYZ rotation, unlike the parent's Z-only convenience."""
    rx, ry, rz = rotation
    sx, sy, sz, cx, cy, cz = (math.sin(rx), math.sin(ry), math.sin(rz),
                             math.cos(rx), math.cos(ry), math.cos(rz))
    points = []
    for a, b, c in ((-1,-1,-1),(-1,-1,1),(-1,1,-1),(-1,1,1),
                    (1,-1,-1),(1,-1,1),(1,1,-1),(1,1,1)):
        x, y, z = a*size[0]/2, b*size[1]/2, c*size[2]/2
        y, z = y*cx-z*sx, y*sx+z*cx
        x, z = x*cy+z*sy, -x*sy+z*cy
        x, y = x*cz-y*sz, x*sz+y*cz
        points.append((x+center[0], y+center[1], z+center[2]))
    for indices in ((0,4,6,2),(1,3,7,5),(0,1,5,4),
                    (2,6,7,3),(0,2,3,1),(4,5,7,6)):
        g.face([points[i] for i in reversed(indices)], material)


def _rod(g, start, end, radius, material, segments=10):
    d = tuple(end[i]-start[i] for i in range(3))
    length = math.sqrt(sum(x*x for x in d))
    if length <= 1e-8:
        raise ValueError('A bay rod must have nonzero length')
    axis = tuple(x/length for x in d)
    reference = (0, 0, 1) if abs(axis[2]) < .9 else (0, 1, 0)
    u = (axis[1]*reference[2]-axis[2]*reference[1],
         axis[2]*reference[0]-axis[0]*reference[2],
         axis[0]*reference[1]-axis[1]*reference[0])
    length_u = math.sqrt(sum(x*x for x in u))
    u = tuple(x/length_u for x in u)
    v = (axis[1]*u[2]-axis[2]*u[1],
         axis[2]*u[0]-axis[0]*u[2], axis[0]*u[1]-axis[1]*u[0])
    rings = []
    for center in (start, end):
        rings.append([tuple(center[j]+radius*(math.cos(i*math.tau/segments)*u[j]
                      + math.sin(i*math.tau/segments)*v[j]) for j in range(3))
                      for i in range(segments)])
    g.face(list(reversed(rings[0])), material)
    g.face(rings[1], material)
    for i in range(segments):
        j = (i+1) % segments
        g.face([rings[0][i], rings[0][j], rings[1][j], rings[1][i]], material)


def _sphere(g, center, scale, material, longitude=16, latitude=10):
    rows = []
    for lat in range(1, latitude):
        phi = math.pi*lat/latitude
        rows.append([tuple(center[j]+scale[j]*value for j, value in enumerate(
                    (math.sin(phi)*math.cos(lon*math.tau/longitude),
                     math.sin(phi)*math.sin(lon*math.tau/longitude),
                     math.cos(phi)))) for lon in range(longitude)])
    top = (center[0], center[1], center[2]+scale[2])
    bottom = (center[0], center[1], center[2]-scale[2])
    for i in range(longitude):
        j = (i+1) % longitude
        g.face([top, rows[0][i], rows[0][j]], material)
        for a, b in zip(rows, rows[1:]):
            g.face([a[i], b[i], b[j], a[j]], material)
        g.face([rows[-1][i], bottom, rows[-1][j]], material)


def _rounded_screen_box(g, center, width, height, depth, radius, material):
    """Rounded rectangle in XZ, with real silhouette and flat readable face."""
    perimeter = []
    for cx, cz, start in ((width/2-radius, height/2-radius, 0),
                          (-width/2+radius, height/2-radius, math.pi/2),
                          (-width/2+radius, -height/2+radius, math.pi),
                          (width/2-radius, -height/2+radius, math.pi*1.5)):
        for step in range(6):
            angle = start+step*math.pi/10
            perimeter.append((center[0]+cx+radius*math.cos(angle),
                              center[2]+cz+radius*math.sin(angle)))
    front = [(x, center[1]-depth/2, z) for x,z in perimeter]
    back = [(x, center[1]+depth/2, z) for x,z in perimeter]
    g.face(front, material)
    g.face(list(reversed(back)), material)
    for i in range(len(front)):
        j = (i+1) % len(front)
        g.face([front[i], back[i], back[j], front[j]], material)


def _wall_arc(g, start, end, z0, z1, material, segments):
    """Continuous annular shell; no internal radial segment cap faces."""
    rings = [[(r*math.cos(start+(end-start)*i/segments),
               r*math.sin(start+(end-start)*i/segments), z)
              for i in range(segments+1)]
             for r,z in ((RADIUS,z0),(RADIUS,z1),
                         (RADIUS+THICKNESS,z0),(RADIUS+THICKNESS,z1))]
    for i in range(segments):
        j = i+1
        g.face([rings[0][i],rings[1][i],rings[1][j],rings[0][j]],material)
        g.face([rings[2][i],rings[2][j],rings[3][j],rings[3][i]],material)
        g.face([rings[1][i],rings[3][i],rings[3][j],rings[1][j]],material)
        g.face([rings[0][i],rings[0][j],rings[2][j],rings[2][i]],material)
    g.face([rings[0][0],rings[2][0],rings[3][0],rings[1][0]],material)
    g.face([rings[0][-1],rings[1][-1],rings[3][-1],rings[2][-1]],material)


def _finish(g, level=None, smooth_wall=False, role=None):
    obj = g.object()
    # Only helper-owned mesh is welded. Correct primitive winding on every
    # closed piece; curved walls additionally get radial smooth shading.
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1e-6)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    if smooth_wall:
        for polygon in obj.data.polygons:
            c, n = polygon.center, polygon.normal
            radius = math.hypot(c.x,c.y)
            polygon.use_smooth = (radius > 1 and abs(n.z) < .15
                 and abs((n.x*c.x+n.y*c.y)/radius) > .9)
    if level is not None:
        obj['r4_bay_level'] = level
    if role:
        obj['r4_role'] = role
    return obj


def build_bays(ctx):
    """Add six complete authored bay compositions and return a JSON-safe receipt."""
    G, make_material = ctx['Geometry'], ctx['material']
    place, collider, light = ctx['place'], ctx['collider'], ctx['light']
    steel, edge, cyan, screen = (ctx[k] for k in ('STEEL','EDGE','CYAN','SCREEN'))
    amber = ctx['AMBER']
    pads, bays = ctx['PADS'], ctx['BAYS']
    if pads or bays:
        raise ValueError('R4 build_bays expects parent to remove the old bay loop')
    created = []
    palettes = {
        1: ((197,180,116),(158,144,96),(222,214,170),'YellowOfficeBackrooms'),
        2: ((206,221,212),(236,227,196),(228,224,205),'Poolrooms'),
        3: ((183,78,35),(13,17,24),(218,211,184),'MallBackroomsParty'),
        4: ((181,169,142),(47,17,24),(205,195,168),'WornNinetiesCinema'),
        5: ((214,205,174),(162,150,125),(232,225,205),'IndoorSuburbs'),
        6: ((176,99,74),(18,18,22),(218,211,184),'Level6NinetiesMallParty'),
    }
    source_maps = {
        1: ('87947439437597','100093931957721','91804597609254',6,6,8),
        2: ('113211706146395','113211706146395','113211706146395',7,7,7),
        3: ('128270554927663','110230144446272',None,22,22,8),
        4: (None,None,None,8,8,8),
        5: ('108985650994325','113909496202267','108985650994325',12,6,12),
        6: ('128270554927663','110230144446272',None,22,22,8),
    }
    bay_materials = {}
    def mat(name, rgb, rough=.78, metal=0, role=None, asset=None, tile=8):
        result = make_material(name,_linear(rgb),rough,metal)
        result['r4_surface_role'] = role or 'bay-prop'
        result['r4_studs_per_tile'] = tile
        if asset:
            result['r4_texture_source'] = 'rbxassetid://'+asset
        return result
    for level,(wall_rgb,floor_rgb,ceiling_rgb,theme) in palettes.items():
        spec = source_maps[level]
        bay_materials[level] = {
            'wall': mat(f'R4_L{level}_Wall',wall_rgb,.85,role=f'level{level}-wall',asset=spec[0],tile=spec[3]),
            'floor': mat(f'R4_L{level}_Floor',floor_rgb,.96 if level in (1,3,5,6) else .78,role=f'level{level}-floor',asset=spec[1],tile=spec[4]),
            'ceiling': mat(f'R4_L{level}_Ceiling',ceiling_rgb,.9,role=f'level{level}-ceiling',asset=spec[2],tile=spec[5]),
        }
    ivory = mat('R4_DomesticIvory',(241,238,220),.75)
    brass = mat('R4_BrassHardware',(137,119,65),.45,.65)
    sage = mat('R4_SageSiding',(174,187,173),.87,role='level5-siding',asset='115748401620318',tile=12)
    domestic_pale = mat('R4_PaleSiding',(232,225,205),.87,role='level5-siding',asset='115748401620318',tile=12)
    domestic_stone = mat('R4_StoneSiding',(194,181,160),.87,role='level5-siding',asset='115748401620318',tile=12)
    domestic_wood = mat('R4_DomesticVeneer',(232,225,205),.74,role='level5-wood',asset='118880038763227',tile=4)
    pool_blue = mat('R4_PoolBlue',(108,164,181),.55)
    pool_water = mat('R4_PoolWater',(48,150,159),.19)
    red = mat('R4_PartyRed',(187,42,52),.42)
    blue = mat('R4_PartyBlue',(40,104,169),.42)
    yellow = mat('R4_PartyYellow',(210,159,37),.43)
    cloth = mat('R4_ConfettiTablecloth',(38,153,165),.91,asset='103412925025303',tile=10)
    fixture_live = mat('R4_WarmFluorescentLens',(255,244,210),.35)
    fixture_live['r4_emission'] = .65
    try:
        sh = next(n for n in fixture_live.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
        if 'Emission Color' in sh.inputs:
            sh.inputs['Emission Color'].default_value = (*_linear((255,244,210)),1)
            sh.inputs['Emission Strength'].default_value = .65
    except AttributeError:
        pass
    fixture_dead = mat('R4_DeadFluorescentLens',(92,88,72),.8)

    # Broad rounded monitors replace tiny kiosks, preserving runtime host fields.
    monitor = G('R4WallMonitor')
    _rounded_screen_box(monitor,(0,0,0),12.18,4.34,.52,.58,steel)
    _rounded_screen_box(monitor,(0,-.294,0),11.91,4.10,.09,.46,edge)
    _rounded_screen_box(monitor,(0,-.354,0),11.62,3.82,.04,.35,screen)
    monitor.box((0,-.39,-2.02),(10.95,.045,.065),cyan)
    for x in (-5.68,5.68):
        for z in (-1.74,1.74):
            _rod(monitor,(x,-.275,z),(x,-.324,z),.055,edge,8)
    _finish(monitor,role='queue-wall-monitor'); created.append('R4WallMonitor')
    arm = G('R4MonitorArm')
    arm.box((0,6.15,.7),(2.25,.34,2.7),steel)
    points = ((0,5.96,.7),(-.85,4.3,.95),(.7,2.35,.35),(0,.4,0))
    for a,b in zip(points,points[1:]): _rod(arm,a,b,.16,edge,12)
    for p in points: _sphere(arm,p,(.28,.28,.28),steel,12,6)
    _finish(arm,role='queue-monitor-wall-arm'); created.append('R4MonitorArm')

    for name,dead in (('R4BayFluorescent',False),('R4BayFluorescentDead',True)):
        g = G(name)
        g.box((0,0,0),(7.5,2.4,.32),steel)
        g.box((0,0,-.205),(7.05,2.05,.14),fixture_dead if dead else fixture_live)
        for x in (-3.42,3.42): g.box((x,0,-.13),(.09,2.18,.13),edge)
        _finish(g,role='bay-fluorescent'); created.append(name)
    poolfixture = G('R4PoolCeilingPanel')
    poolfixture.box((0,0,0),(20,6.5,.5),steel)
    poolfixture.box((0,0,-.34),(17,4.8,.18),fixture_live)
    _finish(poolfixture,role='pool-broad-fixture');created.append('R4PoolCeilingPanel')
    partychair = G('R4PartyChair')
    partychair.box((0,0,2.0),(2.25,2.1,.24),red)
    partychair.box((0,.95,3.15),(2.18,.18,2.0),yellow)
    for x in (-.82,.82):
        for y in (-.73,.73): _rod(partychair,(x,y,.04),(x,y,1.94),.095,edge)
    _finish(partychair,role='party-chair');created.append('R4PartyChair')
    balloons = G('R4BalloonBouquet')
    for i,(x,y,z) in enumerate(((-1.2,0,7.1),(.2,.5,8.2),(1.35,-.25,7.35))):
        _sphere(balloons,(x,y,z),(.86,.86,1.18),(red,blue,yellow)[i])
        _rod(balloons,(x,y,z-1.2),(0,0,.15),.022,edge,6)
        _box(balloons,(x,y,z-1.18),(.11,.11,.18),(red,blue,yellow)[i])
    balloons.box((0,0,.12),(.5,.5,.24),steel)
    _finish(balloons,role='party-balloon-bouquet');created.append('R4BalloonBouquet')

    receipt = {'schema':'lobby-r4-bay-authoring-v1','padRadius':PAD_RADIUS,
               'padOffsetsWorldXZ':[[-9,-13.2],[9,-13.2],[-9,13.2],[9,13.2]],
               'monitorSize':[12.18,4.34,.52],'rooms':[],
               'level4ReferenceVerified':True,'createdFamilies':created,
               'level4Reference':'authoritative native-after Level4V4PreviewAccess -> Level 4 Cinema Blender, LayoutVersion4'}
    for side,row,level in ((-1,-80,1),(1,-80,2),(-1,0,3),
                           (1,0,4),(-1,80,5),(1,80,6)):
        center_x, center_y = side*63, -row
        yaw = math.pi/2 if side<0 else -math.pi/2
        surfaces = bay_materials[level]
        def world(local):
            x,y,z = _rotate(local,yaw)
            return (center_x+x,center_y+y,z)
        def local_place(family,x,y,z=FLOOR_TOP,turn=0):
            x,y,z = world((x,y,z)); place(family,x,y,z,yaw=yaw+turn)
        def local_collision(name,c,s,turn=0):
            collider(name,world(c),s,yaw=yaw+turn)
        shell_name = f'BayShellLevel{level}'
        shell = G(shell_name)
        shell.cylinder((0,0,.4),28.65,.8,surfaces['floor'],128)
        shell.cylinder((0,0,CEILING_BOTTOM+.4),28.65,.8,surfaces['ceiling'],128)
        _wall_arc(shell,ENTRY_END,ENTRY_START+math.tau,FLOOR_TOP,CEILING_BOTTOM,
                  surfaces['wall'],112)
        _wall_arc(shell,ENTRY_START,ENTRY_END,20.35,CEILING_BOTTOM,
                  surfaces['wall'],18)
        # Narrow return cheeks close the 0.09-stud chord mismatch between the
        # radius28 shell cut and parent's 22.6-wide straight connector. They
        # remain outside its existing clear opening (inner cheek X10.4).
        for sign in (-1,1):
            _box(shell,(sign*11.32,-25.65,(FLOOR_TOP+20.35)/2),
                 (.4,1.1,20.35-FLOOR_TOP),surfaces['wall'])
        _finish(shell,level,smooth_wall=True,role='bay-shell')
        created.append(shell_name);local_place(shell_name,0,0,0)
        collider('Bay Floor',(center_x,center_y,.4),(57.3,57.3,.8))
        ctx['COLLIDERS'][-1]['shape']='Cylinder'
        collider('Bay Roof',(center_x,center_y,CEILING_BOTTOM+.4),(57.3,57.3,.8))
        ctx['COLLIDERS'][-1]['shape']='Cylinder'
        for i in range(52):
            a = ENTRY_END+(ENTRY_START+math.tau-ENTRY_END)*(i+.5)/52
            p = (28.35*math.cos(a),28.35*math.sin(a),(FLOOR_TOP+CEILING_BOTTOM)/2)
            local_collision('Bay Wall',p,(3.16,.65,HEIGHT),a-math.pi/2)
        for i in range(9):
            a = ENTRY_START+(ENTRY_END-ENTRY_START)*(i+.5)/9
            p = (28.35*math.cos(a),28.35*math.sin(a),(20.35+CEILING_BOTTOM)/2)
            local_collision('Bay Entry Upper Frieze',p,(2.7,.65,CEILING_BOTTOM-20.35),a-math.pi/2)
        for sign in (-1,1):
            local_collision('Bay Wall',(sign*11.32,-25.65,(FLOOR_TOP+20.35)/2),
                            (.4,1.1,20.35-FLOOR_TOP))
        bays.append({'level':level,'position':[center_x,.4,row],
                     'diameter':56.0,'floorPosition':[center_x,.4,row],
                     'floorSize':[57.3,.8,57.3],'floorTopY':FLOOR_TOP,'yaw':yaw,
                     'theme':palettes[level][3],'clearHeight':HEIGHT,
                     'referenceVerified':True})
        # Pad centers match the original world-aligned four-station layout.
        for index,(dx,dy) in enumerate(((-9,13.2),(9,13.2),(-9,-13.2),(9,-13.2)),1):
            px,py = center_x+dx,center_y+dy
            place('QueuePad',px,py,FLOOR_TOP)
            collider('Queue Pad',(px,py,1.21),(14.82,14.82,.82))
            ctx['COLLIDERS'][-1]['shape']='Cylinder'
            monitor_y = center_y+math.copysign(20.25,dy)
            monitor_yaw = 0 if dy>0 else math.pi
            monitor_z = FLOOR_TOP+7.18
            place('R4WallMonitor',px,monitor_y,monitor_z,yaw=monitor_yaw)
            place('R4MonitorArm',px,monitor_y,monitor_z,yaw=monitor_yaw)
            pads.append({'id':f'R4_Level{level}_Pad{index}','level':level,
                         'position':[px,1.62,-py],'radius':PAD_RADIUS,
                         'bayPosition':[center_x,.4,row],
                         'kioskPosition':[px,monitor_z,-monitor_y],'kioskYaw':monitor_yaw,
                         'controlLocalPosition':[0,-1.55,.43],
                         'statusLocalPosition':[0,0,.405],
                         'statusLocalSize':[11.5,3.74,.04],'statusFace':'Back',
                         'monitorFamily':'R4WallMonitor','monitorWallMounted':True,
                         'maxPartySize':6,'minimumPartySize':1})
        decor = G(f'BayDecorLevel{level}')
        if level in (1,3,5,6):
            for offset in (-16,-8,0,8,16):
                decor.box((offset,0,CEILING_BOTTOM-.06),(.065,44,.04),edge)
                decor.box((0,offset,CEILING_BOTTOM-.06),(44,.065,.04),edge)
        fixture_positions = ((-9,-8),(9,-8),(-9,8),(9,8))
        if level==2:
            fixture_positions = ((0,-8),(0,8))
        for index,(x,y) in enumerate(fixture_positions,1):
            dead = level==3 and index==4
            local_place('R4PoolCeilingPanel' if level==2 else
                        'R4BayFluorescentDead' if dead else 'R4BayFluorescent',
                        x,y,CEILING_BOTTOM-.5)
            if not dead:
                color = [1,.95,.79] if level in (1,2) else [1,.87,.71]
                light(f'Level{level} Bay Fluorescent',world((x,y,CEILING_BOTTOM-.95)),
                      color,1.3 if level in (3,6) else 1.0,32)
        if level==1:
            for index,x in enumerate((-4.5,4.5)):
                local_place('BrownOfficeChair',x,23,.8,math.pi+(-.16 if index==0 else .21))
                local_collision('Bay Furniture',(x,23,2.25),(2.5,2.6,2.9))
            local_place('FilingCabinet',-11,22.8,.8,math.pi)
            # A little geometric corruption is deliberate, with no collision.
            local_place('StackChair',12.5,25.0,3.0,2.7)
        elif level==2:
            tile = surfaces['floor']
            decor.cylinder((0,22.0,.845),5.35,.085,tile,64)
            decor.cylinder((0,22.0,.90),4.95,.035,pool_water,64)
            _box(decor,(0,24.2,5.4),(3.6,3.6,9.2),surfaces['wall'])
            for z in (1.05,9.75): _box(decor,(0,24.2,z),(5.0,5.0,.5),tile)
            local_collision('Bay Furniture',(0,24.2,5.4),(3.6,3.6,9.2))
            for x in (-1.35,1.35):
                _rod(decor,(x,18.3,.9),(x,18.3,5.9),.14,edge,12)
            for z in (1.5,2.5,3.5,4.5): _rod(decor,(-1.35,18.3,z),(1.35,18.3,z),.11,edge,12)
            _box(decor,(10,20.9,1.35),(2.6,6.4,.5),pool_blue)
            _box(decor,(10,23.7,2.7),(2.6,3.4,.4),pool_blue,(math.radians(35),0,0))
            for x in (9,11):
                for y in (18.5,22.6): _rod(decor,(x,y,.83),(x,y,1.2),.08,edge)
            _sphere(decor,(-5.4,22.5,2.25),(1.15,1.15,1.15),yellow)
            _rod(decor,(13.5,24.4,4.0),(17.2,20.7,6.3),.30,cyan,16)
        elif level in (3,6):
            _box(decor,(0,22.4,4.10),(11.2,4.35,.40),ivory)
            _box(decor,(0,22.4,4.34),(11.45,4.62,.10),cloth)
            for x in (-4.4,4.4):
                for y in (20.9,23.9): _rod(decor,(x,y,.85),(x,y,3.9),.10,edge)
            local_collision('Bay Furniture',(0,22.4,2.6),(11.45,4.62,3.6))
            for x,y,turn in ((-7.2,21.0,-math.pi/2),(7.2,21.0,math.pi/2)):
                local_place('R4PartyChair',x,y,.8,turn)
                local_collision('Bay Furniture',(x,y,2.25),(2.3,2.2,2.9))
            local_place('R4BalloonBouquet',-11,21.5,.8)
            if level==6:
                local_place('R4BalloonBouquet',10.8,22.5,.8,.5)
                # A small grounded arcade silhouette previews the revised mall.
                for x in (-6,6):
                    _box(decor,(x,25.2,3.0),(2.5,2.1,4.4),steel)
                    _box(decor,(x,24.08,4.25),(2.08,.08,1.50),screen)
                    _box(decor,(x,23.95,3.30),(2.15,.6,.18),edge,(math.radians(12),0,0))
                    _sphere(decor,(x-.55,23.80,3.70),(.12,.12,.12),red,10,6)
                    for bx in (.25,.60): _sphere(decor,(x+bx,23.85,3.49),(.095,.095,.05),cyan,10,4)
                light('Level6 Arcade Accent',world((0,23,4.5)),[.30,.70,.60],.25,10)
        elif level==5:
            # Original shared-ceiling domestic fronts, kept behind all pads.
            for index,(x,y,height,finish) in enumerate(((-10,22.5,11.4,sage),
                          (0,23.6,18.2,domestic_pale),(10,22.5,14.4,domestic_stone)),1):
                _box(decor,(x,y,.8+height/2),(8.6,.55,height),finish)
                _box(decor,(x,y-.36,1.02),(8.7,.24,.36),ivory)
                _box(decor,(x,y-.34,.8+height-.1),(8.8,.32,.4),ivory)
                door_x = x-2.15
                _box(decor,(door_x,y-.35,4.9),(3.1,.22,7.6),domestic_wood)
                for xx in (door_x-1.67,door_x+1.67): _box(decor,(xx,y-.5,4.95),(.18,.24,8.0),ivory)
                _box(decor,(door_x,y-.5,8.92),(3.52,.24,.23),ivory)
                _box(decor,(door_x+1.07,y-.54,4.9),(.15,.19,.28),brass)
                for slope in (-1,1):
                    _box(decor,(door_x+slope*1.05,y-1.04,9.53),(2.5,1.6,.28),steel,
                         (0,-slope*math.radians(16),0))
                _box(decor,(door_x,y-1.35,.88),(4.2,1.5,.16),ivory)
                _box(decor,(door_x,y-1.36,.97),(2.35,.78,.04),screen)
                _box(decor,(x,y-.72,7.85),(.38,.24,.62),fixture_live)
                light(f'Level5 Porch Sconce {index}',world((x,y-1,7.85)),[1,.83,.61],.38,9)
                wx = x+1.6
                _box(decor,(wx,y-.40,5.1),(3.05,.10,4.20),screen)
                for xx in (wx-1.58,wx+1.58): _box(decor,(xx,y-.55,5.1),(.14,.24,4.42),ivory)
                for zz in (2.86,7.34): _box(decor,(wx,y-.55,zz),(3.35,.24,.14),ivory)
                _box(decor,(wx,y-.57,5.1),(.08,.08,4.15),ivory)
                _box(decor,(wx,y-.57,5.1),(3.0,.08,.09),ivory)
            _box(decor,(0,21.95,11.15),(8.1,2.6,.35),ivory)
            for x in (-3.8,-2.85,-1.9,-.95,0,.95,1.9,2.85,3.8):
                _box(decor,(x,20.65,12.6),(.12,.14,2.6),ivory)
            _box(decor,(0,20.65,13.93),(8.3,.20,.16),ivory)
            _box(decor,(0,20.65,11.35),(8.3,.16,.12),ivory)
            _box(decor,(1.5,23.20,15.8),(3.15,.12,3.7),screen)
            for x in (-.15,3.15): _box(decor,(x,23.08,15.8),(.14,.16,3.95),ivory)
            for z in (13.84,17.76): _box(decor,(1.5,23.08,z),(3.45,.16,.14),ivory)
        elif level==4:
            # Active Level4V4 is the authored cinema. Worn poster frames,
            # burgundy seats and a rear ticket counter retain a clear aisle.
            for x in (-8,8):
                _rounded_screen_box(decor,(x,25.4,8.1),5.2,7.0,.26,.12,brass)
                _rounded_screen_box(decor,(x,25.23,8.1),4.85,6.65,.08,.09,screen)
                _box(decor,(x,25.15,6.02),(4.55,.05,.32),yellow)
                for band in range(4):
                    _box(decor,(x-1.55+band*1.0,25.16,8.1+(-1 if band%2 else 1)),
                         (.55,.04,2.65),red if band%2 else blue)
                _box(decor,(x,25.12,4.90),(3.5,.04,.16),ivory)
            _box(decor,(0,24.6,2.4),(7.6,2.0,3.2),steel)
            _box(decor,(0,24.6,4.08),(7.8,2.25,.18),brass)
            for x in (-2.8,0,2.8):
                _box(decor,(x,23.56,2.6),(1.8,.05,2.3),red)
                _box(decor,(x,23.50,2.6),(.09,.05,2.3),brass)
            for x in (-12,-8,8,12):
                _box(decor,(x,22.3,1.8),(2.0,2.1,.58),red)
                _box(decor,(x,23.14,3.0),(2.05,.45,2.0),red,
                     (math.radians(-7),0,0))
                for xx in (-1.05,1.05):
                    _box(decor,(x+xx,22.3,2.24),(.17,1.8,.20),brass)
                    _rod(decor,(x+xx,22.7,.9),(x+xx,22.7,2.15),.095,steel)
                local_collision('Bay Furniture',(x,22.4,1.9),(2.3,2.5,2.2))
            light('Level4 Cinema Poster Spill',world((0,23,8.5)),[1,.61,.31],.25,14)
        _finish(decor,level,role='bay-distinct-decor');created.append(f'BayDecorLevel{level}')
        local_place(f'BayDecorLevel{level}',0,0,0)
        receipt['rooms'].append({'level':level,'theme':palettes[level][3],
                 'innerRadius':RADIUS,'clearHeight':HEIGHT,'padCount':4,
                 'openingDegrees':[246,294],'referenceVerified':True,
                 'surfaceMaterialNames':{k:v.name for k,v in surfaces.items()}})
    assert len(pads)==24 and len(bays)==6
    # All circular detector footprints must remain distinct and inside the bay.
    for bay in bays:
        local_pads = [p for p in pads if p['level']==bay['level']]
        for i,a in enumerate(local_pads):
            dx = a['position'][0]-bay['floorPosition'][0]
            dz = a['position'][2]-bay['floorPosition'][2]
            assert math.hypot(dx,dz)+PAD_RADIUS < RADIUS
            for b in local_pads[i+1:]:
                assert math.hypot(a['position'][0]-b['position'][0],
                                  a['position'][2]-b['position'][2]) > PAD_RADIUS*2
    return receipt
