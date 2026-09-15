"""Author and bake the measured R15 hiding loop through the live Blender MCP."""
from pathlib import Path
import json
from blender_mcp_client import execute

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/animations/table-hiding'

CODE=r'''
import bpy, json, math
from mathutils import Matrix, Vector
from pathlib import Path
root=Path(r"G:\Roblox\MongoTV")
out=root/'assets/animations/table-hiding'
rig=json.loads((root/'artifacts/trello-20260915/codex-hiding-rig.json').read_text())
authored=json.loads((out/'authored-pose.json').read_text())
def cf(a):
    return Matrix(((a[3],a[4],a[5],a[0]),(a[6],a[7],a[8],a[1]),(a[9],a[10],a[11],a[2]),(0,0,0,1)))
B=Matrix(((1,0,0,0),(0,0,-1,0),(0,1,0,0),(0,0,0,1)))
def convert(m): return B@m@B.inverted()
parts={p['name']:p for p in rig['parts']}
ordered=[];rest={'HumanoidRootPart':Matrix.Identity(4)}
while len(ordered)<len(rig['joints']):
    ready=[j for j in rig['joints'] if j['part0'] in rest and j['part1'] not in rest]
    if not ready: raise RuntimeError('Disconnected rig')
    for j in ready:
        rest[j['part1']]=rest[j['part0']]@cf(j['c0'])@cf(j['c1']).inverted()
        ordered.append(j)

# Preserve every existing scene/object and save a separate authoring project.
scene_name='Zyntra_TableHide_20260915'
scene=bpy.data.scenes.get(scene_name)
if scene and len(scene.objects): raise RuntimeError('Scene already has authored objects; inspect before rebuilding')
scene=scene or bpy.data.scenes.new(scene_name)
bpy.context.window.scene=scene
scene.render.fps=30;scene.frame_start=1;scene.frame_end=121
scene.render.engine='BLENDER_EEVEE'
scene.render.resolution_x=1200;scene.render.resolution_y=900;scene.render.resolution_percentage=100
scene.world=bpy.data.worlds.new('TableHide_World')
scene.world.color=(.035,.045,.05)
scene.view_settings.view_transform='AgX'

def material(name,color,roughness=.65):
    mat=bpy.data.materials.new(name);mat.diffuse_color=(*color,1);mat.use_nodes=True
    bsdf=mat.node_tree.nodes.get('Principled BSDF');bsdf.inputs['Base Color'].default_value=(*color,1);bsdf.inputs['Roughness'].default_value=roughness
    return mat
yellow=material('Hide_Hazmat',(.59,.43,.085));dark=material('Hide_Gloves_Boots',(.025,.033,.038));hood=material('Hide_Hood',(.74,.56,.14));metal=material('Hide_Table',(.11,.14,.15));floor_mat=material('Hide_Floor',(.12,.14,.15))
arm_data=bpy.data.armatures.new('Zyntra_Measured_R15')
arm=bpy.data.objects.new('Zyntra_TableHide_Rig',arm_data);scene.collection.objects.link(arm)
bpy.context.view_layer.objects.active=arm;arm.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')
base=arm_data.edit_bones.new('HumanoidRootPart');base.head=(0,0,0);base.tail=(0,.3,0)
for j in ordered:
    bone=arm_data.edit_bones.new(j['part1']);bone.head=(0,0,0);bone.tail=(0,.4,0)
    bone.matrix=convert(rest[j['part0']]@cf(j['c0']))
    bone.length=.4
    bone.parent=arm_data.edit_bones[j['part0']]
    bone.use_connect=False
bpy.ops.object.mode_set(mode='OBJECT')
arm.show_in_front=True
for j in ordered:
    p=parts[j['part1']];sx,sy,sz=p['size']
    verts=[(x*sx/2,-z*sz/2,y*sy/2) for x,y,z in [(-1,-1,-1),(-1,-1,1),(-1,1,-1),(-1,1,1),(1,-1,-1),(1,-1,1),(1,1,-1),(1,1,1)]]
    faces=[(0,4,6,2),(1,3,7,5),(0,1,5,4),(2,6,7,3),(0,2,3,1),(4,5,7,6)]
    mesh=bpy.data.meshes.new(p['name']+'_Proxy');mesh.from_pydata(verts,[],faces);mesh.update()
    obj=bpy.data.objects.new(p['name']+'_MeasuredProxy',mesh);scene.collection.objects.link(obj)
    obj.matrix_world=convert(rest[p['name']])
    obj.data.materials.append(hood if p['name']=='Head' else dark if 'Hand' in p['name'] or 'Foot' in p['name'] else yellow)
    group=obj.vertex_groups.new(name=p['name']);group.add(list(range(8)),1,'REPLACE')
    mod=obj.modifiers.new('Measured rig','ARMATURE');mod.object=arm
    bevel=obj.modifiers.new('Proxy edge rounding','BEVEL');bevel.width=.07;bevel.segments=3
    obj['authoring_proxy']=True
    obj['note']='Measured MeshPart bounding box, not the final Roblox mesh'

arm.animation_data_create()
action=bpy.data.actions.new('Zyntra_TableHide_Hold_4s_v1')
arm.animation_data.action=action
for bone in arm.pose.bones: bone.rotation_mode='QUATERNION'
for frame in range(1,122):
    phase=(frame-1)/120*math.tau
    for j in ordered:
        T=Matrix(authored['jointTransforms'][j['name']])
        # Gentle defensive breathing; no horizontal root motion or drift.
        if j['name']=='Waist': T=T@Matrix.Rotation(math.radians(math.sin(phase)*.35),4,'X')
        elif j['name']=='Neck': T=T@Matrix.Rotation(math.radians(-math.sin(phase)*.20),4,'X')
        elif j['name'] in ('LeftElbow','RightElbow'): T=T@Matrix.Rotation(math.radians(math.sin(phase)*.25),4,'X')
        bone=arm.pose.bones[j['part1']]
        bone.matrix_basis=convert(T)
        bone.keyframe_insert('location',frame=frame,group=bone.name)
        bone.keyframe_insert('rotation_quaternion',frame=frame,group=bone.name)
    arm.pose.bones['HumanoidRootPart'].matrix_basis=Matrix.Identity(4)

def curves(action):
    if hasattr(action,'fcurves'): return list(action.fcurves)
    return [c for layer in action.layers for strip in layer.strips for bag in strip.channelbags for c in bag.fcurves]
for curve in curves(action):
    for key in curve.keyframe_points: key.interpolation='LINEAR'
action.use_fake_user=True

# Bake evaluated Blender pose matrices back into Roblox's joint-local space.
frames=[];worst_error=0
for frame in range(1,122):
    scene.frame_set(frame);evaluated=arm.evaluated_get(bpy.context.evaluated_depsgraph_get())
    world={'HumanoidRootPart':Matrix.Identity(4)};values=[['HumanoidRootPart',0,0,0,0,0,0,1]]
    for j in ordered:
        bone_world=B.inverted()@evaluated.pose.bones[j['part1']].matrix@B
        world[j['part1']]=bone_world@cf(j['c1']).inverted()
        T=cf(j['c0']).inverted()@world[j['part0']].inverted()@world[j['part1']]@cf(j['c1'])
        q=T.to_quaternion();p=T.translation
        values.append([j['part1'],float(p.x),float(p.y),float(p.z),float(q.x),float(q.y),float(q.z),float(q.w)])
        if frame==1:
            expected=Matrix(authored['jointTransforms'][j['name']])
            worst_error=max(worst_error,max(abs(T[r][c]-expected[r][c]) for r in range(4) for c in range(4)))
    frames.append([(frame-1)/30,values])
if worst_error>.00005: raise RuntimeError('Blender round-trip mismatch: '+str(worst_error))
payload={'name':'Zyntra_TableHide_Hold_4s_v1','looped':True,'priority':'Action','fps':30,'parents':{'HumanoidRootPart':None,**{j['part1']:j['part0'] for j in ordered}},'jointNames':{j['part1']:j['name'] for j in ordered},'frames':frames,'blenderRoundtripMaxError':worst_error}
(out/'hide-hold-keyframes.json').write_text(json.dumps(payload,separators=(',',':'))+'\n')

def cube(name,location,size,mat):
    bpy.ops.mesh.primitive_cube_add(size=1,location=location)
    obj=bpy.context.object;obj.name=name;obj.dimensions=size;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);obj.data.materials.append(mat);return obj
cube('Authoring floor',(0,0,-2.28),(9,9,.16),floor_mat)
# A cutaway illustrates the actual underside height; final clearance is tested in Roblox.
cube('Tabletop cutaway',(0,-1.87,.8),(5.4,.4,.48),metal)
for x in [-2.5,2.5]: cube('Table side support',(x,0,-.9),(.18,4.3,2.6),metal)
for loc,energy,size in [((3,4,6),1500,5),((-4,1,3),1000,4),((0,-4,4),1100,3)]:
    light=bpy.data.lights.new('Hide_KeyLight','AREA');light.energy=energy;light.shape='DISK';light.size=size
    obj=bpy.data.objects.new(light.name,light);scene.collection.objects.link(obj);obj.location=loc;obj.rotation_euler=(Vector((0,0,-.7))-obj.location).to_track_quat('-Z','Y').to_euler()
camdata=bpy.data.cameras.new('Hide_ReviewCamera');cam=bpy.data.objects.new(camdata.name,camdata);scene.collection.objects.link(cam)
cam.location=(6,7,3.2);cam.rotation_euler=(Vector((0,0,-.7))-cam.location).to_track_quat('-Z','Y').to_euler();camdata.type='ORTHO';camdata.ortho_scale=7;scene.camera=cam
scene.frame_set(1)
scene['source']='Measured Roblox R15, authored via Blender MCP; proxy meshes for pose preview only'
scene['root_floor_height']=2.20;scene['table_collider_underside']=2.76
bpy.ops.wm.save_as_mainfile(filepath=str(out/'zyntra-table-hide-v1.blend'),copy=True)
scene.render.filepath=str(out/'hide-hold-preview.png');bpy.ops.render.render(write_still=True)
result={'scene':scene.name,'action':action.name,'frames':121,'duration':4,'roundtripMaxError':worst_error,'blend':str(out/'zyntra-table-hide-v1.blend'),'keyframes':str(out/'hide-hold-keyframes.json'),'preview':str(out/'hide-hold-preview.png')}
'''

if __name__=='__main__':
    result=execute(CODE,timeout=120)
    OUT.mkdir(parents=True,exist_ok=True)
    (OUT/'blender-build-result.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result))
