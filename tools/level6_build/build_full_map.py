"""Assemble one complete 32-room Level 6 Blender map from the reusable kit.

The serialized seed is a verified candidate from the same layout generator
that the Level 6 preview runs. New seeds use the same Blender asset library.
"""
import bpy,json,math,random
from pathlib import Path
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'assets/level6-worn-party'
PLAN=json.loads((ROOT/'artifacts/level6-build-20260930/seed101-layout.json').read_text())['layout']
ROOMS={r['Id']:r for r in PLAN['Rooms']}
KITS={c.name[4:]:c for c in bpy.data.collections if c.name.startswith('L6K_')}
assert len(KITS)==49 and len(ROOMS)==32 and len(PLAN['Links'])==37

scene=bpy.data.scenes.new('Level 6 | FULL seed 101 | 32 rooms')
scene.unit_settings.scale_length=1
instances=[]

def instance(asset,point,angle=0,scale=(1,1,1),label=None):
    assert asset in KITS,asset
    o=bpy.data.objects.new(label or asset,None)
    o.instance_type='COLLECTION';o.instance_collection=KITS[asset]
    scene.collection.objects.link(o)
    o.location=point;o.rotation_euler.z=angle;o.scale=scale
    o['Level6_KitAsset']=asset
    instances.append(o)
    return o

def bpos(room):return Vector((room['X'],-room['Z'],0))
def theme(room):
    t=room.get('ThemeId')
    if t=='OrangeBlackParty':return 'Orange'
    if t=='RedParty':return 'Red'
    if room.get('Role')=='Exit':return 'Service'
    return 'Beige'

def wall_line(theme_name,p0,p1,height=12):
    v=Vector(p1)-Vector(p0);length=v.length
    if length<=.01:return
    along=math.atan2(v.y,v.x)
    count=max(1,math.ceil(length/8))
    for i in range(count):
        frac=(i+.5)/count;pos=Vector(p0)+v*frac
        instance('Wall'+theme_name,pos,along,(length/count/8,1,height/12),'Wall segment')

def room_shell(room,openings):
    p=bpos(room);w=room['W'];d=room['D'];h=room['H'];t=theme(room)
    instance('Floor'+t,p,0,(w/80,d/64,1),room['Id']+' | floor')
    instance('Ceiling',p+Vector((0,0,h-.5)),0,(w/80,d/64,1),room['Id']+' | ceiling')
    for direction in ('North','South','East','West'):
        axis=direction in ('North','South')
        span=w if axis else d
        at=(d/2 if direction=='North' else -d/2) if axis else (w/2 if direction=='East' else -w/2)
        def line(lo,hi):
            if axis:wall_line(t,p+Vector((lo,at,0)),p+Vector((hi,at,0)),h)
            else:wall_line(t,p+Vector((at,lo,0)),p+Vector((at,hi,0)),h)
        if direction in openings:
            line(-span/2,-7);line(7,span/2)
            center=p+(Vector((0,at,10.5)) if axis else Vector((at,0,10.5)))
            instance('Lintel'+t,center,0 if axis else math.pi/2,(1,1,(h-10.5)/1.5),room['Id']+' | 14-stud portal lintel')
        else:line(-span/2,span/2)

def corridor(a,b,link):
    pa=bpos(a);pb=bpos(b)
    along_x=abs(pb.x-pa.x)>abs(pb.y-pa.y)
    if along_x:
        direction=1 if pb.x>pa.x else -1
        start=pa+Vector((direction*a['W']/2,0,0))
        end=pb-Vector((direction*b['W']/2,0,0))
    else:
        direction=1 if pb.y>pa.y else -1
        start=pa+Vector((0,direction*a['D']/2,0))
        end=pb-Vector((0,direction*b['D']/2,0))
    center=(start+end)/2;length=(end-start).length
    t=theme(a)
    sections=math.ceil(length/64)
    for j in range(sections):
        pos=start+(end-start)*((j+.5)/sections)
        if along_x:scale=(length/sections/80,14/64,1)
        else:scale=(14/80,length/sections/64,1)
        instance('Floor'+t,pos,0,scale,link['Id']+' | corridor floor')
        instance('Ceiling',pos+Vector((0,0,10.45)),0,scale,link['Id']+' | corridor ceiling')
    for side in (-1,1):
        off=7.75*side
        if along_x:wall_line(t,start+Vector((0,off,0)),end+Vector((0,off,0)),10.5)
        else:wall_line(t,start+Vector((off,0,0)),end+Vector((off,0,0)),10.5)
    for j in range(1,max(2,math.ceil(length/26))):
        pos=start+(end-start)*(j/max(2,math.ceil(length/26)))
        instance('FluorescentFrame',pos+Vector((0,0,10.1)),0)
        instance('FluorescentDiffuser',pos+Vector((0,0,9.95)),0)

openings={name:set() for name in ROOMS}
for link in PLAN['Links']:
    a=ROOMS[link['A']];b=ROOMS[link['B']]
    if abs(a['X']-b['X'])>abs(a['Z']-b['Z']):
        openings[a['Id']].add('East' if b['X']>a['X'] else 'West')
        openings[b['Id']].add('West' if b['X']>a['X'] else 'East')
    else:
        openings[a['Id']].add('South' if b['Z']>a['Z'] else 'North')
        openings[b['Id']].add('North' if b['Z']>a['Z'] else 'South')

for room in PLAN['Rooms']:room_shell(room,openings[room['Id']])
for link in PLAN['Links']:corridor(ROOMS[link['A']],ROOMS[link['B']],link)

def decorate_room(room):
    p=bpos(room);w=room['W'];d=room['D'];h=room['H'];rnd=random.Random(room['LocalSeed'])
    special=room.get('ServiceVariant')
    center=room.get('Role') in ('Arrival','Exit')
    # All decorative furniture is kept outside a 14-stud cross joining the
    # cardinal portals; runtime has additional AI and CD spacing checks.
    tables=1 if center else (2+rnd.randrange(2))
    for j in range(tables):
        x=(-1 if j%2 else 1)*(16+4*(j//2));y=(-1 if j%2 else 1)*(12+3*(j//2))
        q=p+Vector((x,y,0))
        instance('FoldingTable',q,label=room['Id']+' | table')
        for i,(cx,cy,ang) in enumerate(((-3,-3.8,math.pi),(3,-3.8,math.pi),(-3,3.8,0),(3,3.8,0))):
            instance(('ChairRed','ChairYellow','ChairGreen','ChairBlue')[(i+j)%4],q+Vector((cx,cy,0)),ang)
    if not center:
        instance('BalloonCluster',p+Vector((-w/2+6,d/2-7,0)))
        instance('BirthdayGarland',p+Vector((0,d/2-.8,h-2.5)))
        instance('CakeTable',p+Vector((-w/2+5,3,0)),math.pi/2)
        instance('PASpeaker',p+Vector((w/2-.5,-d/2+7,h-2.4)),-math.pi/2)
        if room['SectionIndex']==3 and rnd.random()<.35:
            instance('RoomDivider',p+Vector((w/2-9,d/2-9,0)))
        if rnd.random()<.5:instance('ChairStack',p+Vector((w/2-5,d/2-5,0)))
    for x in (-w*.25,w*.25):
        for y in (-d*.20,d*.20):
            instance('FluorescentFrame',p+Vector((x,y,h-.4)))
            instance('FluorescentDiffuser',p+Vector((x,y,h-.57)))
    # Service pockets add genuinely different traversable spaces with visual
    # ties back to the same budget birthday venue.
    if special:
        c=p+Vector((w/2-13,d/2-16,0))
        if special=='BudgetArcade':
            for i,name in enumerate(('ArcadeInvaders','ArcadeMaze','ArcadePlatform')):
                instance(name,c+Vector((-7+i*5,6,0)),math.pi)
            instance('PrizeCounter',c+Vector((7,-4,0)),math.pi/2)
            instance('ClawMachine',c+Vector((-7,-7,0)),math.pi/2)
        elif special=='PartySupplyStore':
            instance('SupplyShelf',c+Vector((7,0,0)),-math.pi/2)
            instance('FoldedTables',c+Vector((-6,0,0)),math.pi/2)
            instance('HeliumTank',c+Vector((5,8,0)))
            instance('FlatClownCutout',c+Vector((-6,7,0)))
        elif special=='MaintenanceWorkshop':
            instance('WorkshopBench',c+Vector((7,0,0)),-math.pi/2)
            instance('Pegboard',c+Vector((8,0,5)),-math.pi/2)
            instance('BreakerPanel',c+Vector((-7,6,5.5)),math.pi/2)
            instance('MopBucket',c+Vector((2,-7,0)))
    # The actual five discs' positions are keyed to objective data at runtime.
    if room.get('Module'):
        instance('CDCase',p+Vector((17,14,3.45)))
        instance('CD',p+Vector((17,14,3.77)))
    if room['Id']=='SignalHall':
        instance('FoldingTable',p+Vector((0,16,0)))
        instance('CDPlayer',p+Vector((0,16,3.45)))

for room in PLAN['Rooms']:decorate_room(room)

scene.world=bpy.data.worlds.new('Level 6 | subdued ambient');scene.world.use_nodes=True
bg=next(n for n in scene.world.node_tree.nodes if n.type=='BACKGROUND');bg.inputs['Color'].default_value=(.21,.19,.16,1);bg.inputs['Strength'].default_value=.35
camdata=bpy.data.cameras.new('Whole 32-room map view');cam=bpy.data.objects.new('Whole map camera',camdata);scene.collection.objects.link(cam)
xs=[r['X'] for r in PLAN['Rooms']];ys=[-r['Z'] for r in PLAN['Rooms']]
cx=(min(xs)+max(xs))/2;cy=(min(ys)+max(ys))/2
cam.location=(cx,cy-900,1500);cam.rotation_euler=(Vector((cx,cy,0))-cam.location).to_track_quat('-Z','Y').to_euler();camdata.lens=24;scene.camera=cam

bpy.context.window.scene=scene
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'Level6_FULL_Seed101.blend'))
record={'seed':101,'sourceLayoutHash':PLAN['LayoutHash'],'rooms':32,'links':37,'sourceRoomAreaStud2':PLAN['RoomFloorArea'],'blenderInstances':len(instances),'mapXYBlenderBounds':[min(xs),max(xs),min(ys),max(ys)],'source':str(OUT/'Level6_FULL_Seed101.blend'),'scope':'Whole authored map source with Blender instances. Gameplay controllers and invisible collision are supplied by Level6 Studio runtime; visual placements may be refined by live export.'}
(OUT/'full-map-record.json').write_text(json.dumps(record,indent=2)+'\n')
print('FULL_MAP_ASSEMBLED',json.dumps(record),flush=True)
