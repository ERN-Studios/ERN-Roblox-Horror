"""Independent offline inspection of the completed R4 authoring/export package.

Run in isolated background Blender. No Studio writes; no save_as_mainfile.
"""
from pathlib import Path
import bpy, json, math, base64, struct, hashlib
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).parent
ASSET = ROOT / 'assets/models/lobby-reimagined-r4-20261001'
manifest = json.loads((ASSET / 'manifest.json').read_text())
bpy.ops.wm.open_mainfile(filepath=str(ASSET / 'LobbyReimaginedPreview.blend'))
scene = bpy.data.scenes['Lobby Reimagined | Full Preview']
bpy.context.window.scene = scene
graph = bpy.context.evaluated_depsgraph_get()
report = {'scope':'offline Blender geometry and serialized export only, not Studio or multiplayer',
          'blendSha256':hashlib.sha256((ASSET/'LobbyReimaginedPreview.blend').read_bytes()).hexdigest(),
          'manifestSha256':hashlib.sha256((ASSET/'manifest.json').read_bytes()).hexdigest(),
          'routes':[], 'seamFloorSamples':[], 'signs':[], 'chunks':[], 'collisionRoutes':[],
          'closedGeometryVolumes':{}, 'findings':[]}

verts, faces, labels = [], [], []
for obj in scene.objects:
    if obj.type != 'MESH': continue
    ev = obj.evaluated_get(graph); mesh = ev.to_mesh()
    try:
        mesh.calc_loop_triangles(); start = len(verts)
        verts.extend(obj.matrix_world @ v.co for v in mesh.vertices)
        for t in mesh.loop_triangles:
            faces.append(tuple(start+i for i in t.vertices)); labels.append(obj.name)
    finally: ev.to_mesh_clear()
bvh = BVHTree.FromPolygons(verts, faces, all_triangles=True)
def ray(origin, target):
    delta=Vector(target)-Vector(origin); dist=delta.length
    p,n,idx,d=bvh.ray_cast(Vector(origin),delta.normalized(),dist)
    return None if p is None else {'object':labels[idx], 'position':list(p), 'normal':list(n), 'distance':d}

for sign in manifest['signs']:
    side,row=sign['side'],sign['row']; yy=-row
    start=(side*22, yy, 5.8); target=(side*63,yy,5.8)
    hit=ray(start,target)
    report['routes'].append({'level':sign['level'],'start':start,'target':target,'visualCenterRouteHit':hit})
    if hit: report['findings'].append(f"Level {sign['level']} center entrance ray is obstructed by {hit['object']}")
    samples=[]
    for xx in (26,28.6,30,32,34,35,36,38,40,42,45,50):
        hit=ray((side*xx,yy,6),(side*xx,yy,-3))
        samples.append({'x':side*xx,'hit':hit})
    report['seamFloorSamples'].append({'level':sign['level'],'samples':samples})
    gate=Matrix.Translation(Vector((side*28.6,yy,.8)))@Matrix.Rotation(sign['yaw'],4,'Z')
    header=Vector((0,-1.44,17.2)); world=gate@header
    facing=(gate.to_3x3()@Vector((0,-1,0))).normalized()
    inward=Vector((-side,0,0))
    item={'level':sign['level'],'headerWorldCenter':list(world), 'headerFacingTunnelDot':facing.dot(inward),
          'headerHeight':world.z,'bladeChecks':[]}
    for name,localx,viewdir in (('Left',-15.43,Vector((-1,0,0))),('Right',-14.57,Vector((1,0,0)))):
        center=gate@Vector((localx,-5.1,17.0)); normal=gate.to_3x3()@viewdir
        observer=center+normal*35; observer.z=5.8
        hit=ray(observer,center+normal*.015)
        item['bladeChecks'].append({'face':name,'center':list(center),'normal':list(normal),
                                    'observer':list(observer),'occlusion':hit})
    report['signs'].append(item)

# SAT against the actual serialized OBB collision metadata. This is a static
# clearance check; the Studio Humanoid, stepping and collision groups are not
# simulated. Low horizontal floors and queue podiums are explicitly excluded.
def overlaps_body(center, half, item):
    c=Vector(item['position']); e=Vector(item['size'])*.5
    if 'rotation' in item:
        rx,ry,rz=item['rotation']
        rot=Matrix.Rotation(rx,3,'X')@Matrix.Rotation(ry,3,'Y')@Matrix.Rotation(rz,3,'Z')
    else:rot=Matrix.Rotation(item.get('yaw',0),3,'Y')
    axes=[rot.col[i].normalized() for i in range(3)]
    world=[Vector((1,0,0)),Vector((0,1,0)),Vector((0,0,1))]
    tests=world+axes+[a.cross(b) for a in world for b in axes]
    delta=c-center
    for axis in tests:
        if axis.length<1e-7:continue
        axis.normalize()
        bodyRadius=sum(half[k]*abs(axis[k]) for k in range(3))
        partRadius=sum(e[k]*abs(axis.dot(axes[k])) for k in range(3))
        if abs(delta.dot(axis))>=bodyRadius+partRadius-1e-5:return False
    return True

skip={'Road','Sidewalk','Door Threshold','Connector Floor','Bay Floor','Queue Pad'}
for s in manifest['signs']:
    side,row=s['side'],s['row']; found=[]
    for x in (22+i*.5 for i in range(87)):
        p=Vector((side*x,4.3,row))
        for item in manifest['colliders']:
            if item['name'] in skip:continue
            if overlaps_body(p,Vector((1.5,2.5,1.5)),item):
                found.append({'x':side*x,'collider':item['name'],'colliderPosition':item['position']})
    report['collisionRoutes'].append({'level':s['level'],'staticBodySize':[3,5,3],'hits':found})
    if found:report['findings'].append(f"Level {s['level']} static center clearance intersects {found[0]['collider']}")

def load_chunk(chunk):
    raw=base64.b64decode((ASSET/chunk['file']).read_bytes())
    magic,np,nn,nu,nf=struct.unpack_from('<5I',raw); offset=20
    p=[Vector(struct.unpack_from('<3f',raw,offset+i*12))+Vector(chunk['center']) for i in range(np)]; offset+=np*12
    n=[Vector(struct.unpack_from('<3f',raw,offset+i*12)) for i in range(nn)]; offset+=nn*12+nu*8
    f=[struct.unpack_from('<9I',raw,offset+i*36) for i in range(nf)]
    return p,n,f

for chunk in manifest['chunks']:
    if chunk['family'] not in ('PlainShell','PortalShell','ArchRib') and not chunk['family'].startswith('BayShell'): continue
    p,n,fs=load_chunk(chunk); windingBad=0; count=0; radialErrors=[]
    for ids in fs:
        pts=[p[ids[k]] for k in (0,3,6)]
        face=(pts[1]-pts[0]).cross(pts[2]-pts[0])
        if face.length<1e-8: continue
        face.normalize(); count+=1
        normals=[n[ids[k]] for k in (1,4,7)]
        if min(face.dot(v) for v in normals)<.90: windingBad+=1
        center=sum(pts,Vector())/3
        isBay=chunk['family'].startswith('BayShell')
        if isBay:
            # Serialized XYZ = Blender X,Z,-Y: radial direction on Roblox XZ.
            radial=Vector((center.x,0,center.z)); radius=radial.length
            if radius<27.5 or radius>29.0 or abs(face.y)>.1 or center.y<1.0 or center.y>22.5: continue
            if abs(face.dot(radial.normalized()))<.98: continue
            if min((Vector((pt.x,0,pt.z)).length) for pt in pts)<27.5: continue
            sign=1 if face.dot(radial)>0 else -1
            for pt,norm in zip(pts,normals):
                desired=Vector((pt.x,0,pt.z)).normalized()*sign
                radialErrors.append(math.degrees(math.acos(max(-1,min(1,norm.dot(desired))))))
        else:
            radial=Vector((center.x,center.y-1,0)); radius=radial.length
            if radius<33.8 or radius>36.3 or abs(face.z)>.1: continue
            if abs(face.dot(radial.normalized()))<.98: continue
            radii=[Vector((pt.x,pt.y-1,0)).length for pt in pts]
            if max(radii)-min(radii)>.001:continue
            allowed=(33.9,34.65) if chunk['family']=='ArchRib' else (35.0,36.1)
            if min(abs(radii[0]-r) for r in allowed)>.001:continue
            sign=1 if face.dot(radial)>0 else -1
            for pt,norm in zip(pts,normals):
                desired=Vector((pt.x,pt.y-1,0)).normalized()*sign
                radialErrors.append(math.degrees(math.acos(max(-1,min(1,norm.dot(desired))))))
    report['chunks'].append({'name':chunk['name'],'windingNormalsInconsistentTriangles':windingBad,
                            'checkedTriangles':count,'radialSamples':len(radialErrors),
                            'maxRadialNormalErrorDegrees':max(radialErrors,default=None)})

for chunk in manifest['chunks']:
    if chunk['family'] not in ('LevelGate','EntryConnector','DoorThreshold','RoadSection','SidewalkSection','StageDeck','R4WallMonitor','R4MonitorArm','PlainShell','PortalShell') and not chunk['family'].startswith('BayShell'):continue
    p,n,fs=load_chunk(chunk);volume=0
    for ids in fs:volume+=p[ids[0]].dot(p[ids[3]].cross(p[ids[6]]))/6
    report['closedGeometryVolumes'][chunk['family']]=report['closedGeometryVolumes'].get(chunk['family'],0)+volume
for family,volume in report['closedGeometryVolumes'].items():
    if volume<=0:report['findings'].append(f'{family} closed authoring geometry signed volume is nonpositive')

(OUT/'completed-r4-offline-audit.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({'findings':report['findings'],'routeCount':len(report['routes']),
                  'headerFacingDot':[s['headerFacingTunnelDot'] for s in report['signs']],
                  'chunkNormalErrors':[{k:c[k] for k in ('name','maxRadialNormalErrorDegrees','windingNormalsInconsistentTriangles')} for c in report['chunks']]}),flush=True)

if '--renders' in __import__('sys').argv or '--stage' in __import__('sys').argv:
    cam=scene.camera; scene.render.engine='CYCLES'; scene.cycles.samples=16
    scene.render.resolution_x=1100; scene.render.resolution_y=700; scene.render.resolution_percentage=100
    for name,origin,target,lens in (
        ('audit-level3-bay-from-entry.png',(-43,0,5.8),(-66,0,10),24),
        ('audit-level4-bay-from-entry.png',(43,0,5.8),(66,0,10),24),
        ('audit-level6-bay-from-entry.png',(43,-80,5.8),(66,-80,10),24),
        ('audit-dj-stage-close.png',(0,-102,5.8),(0,-124,8),24),
    ):
        if '--stage' in __import__('sys').argv and 'dj-stage' not in name:continue
        cam.location=origin; cam.rotation_euler=(Vector(target)-Vector(origin)).to_track_quat('-Z','Y').to_euler();cam.data.lens=lens
        scene.render.filepath=str(OUT/name); bpy.ops.render.render(write_still=True)
