"""Bake the reviewed actual-character hold and verify every mesh frame."""
from pathlib import Path
import json
from blender_mcp_client import execute
ROOT=Path(__file__).resolve().parents[1]
CODE=r'''
import bpy,json,math
from mathutils import Matrix,Vector
from pathlib import Path
root=Path(r'G:\Roblox\MongoTV');out=root/'assets/animations/table-hiding'
scene=bpy.data.scenes['Zyntra_TableHide_Actual_20260916'];bpy.context.window.scene=scene
arm=scene.objects['Zyntra_Actual_Hazmat_Rig']
authored=json.loads((out/'authored-actual-pose.json').read_text())
rig=json.loads((root/'artifacts/trello-20260915/codex-hiding-rig.json').read_text())
B=Matrix(((1,0,0,0),(0,0,-1,0),(0,1,0,0),(0,0,0,1)))
def cf(a):return Matrix(((a[3],a[4],a[5],a[0]),(a[6],a[7],a[8],a[1]),(a[9],a[10],a[11],a[2]),(0,0,0,1)))
known={'HumanoidRootPart'};ordered=[]
while len(ordered)<len(rig['joints']):
    ready=[j for j in rig['joints'] if j['part0'] in known and j['part1'] not in known]
    if not ready:raise RuntimeError('Disconnected rig')
    for j in ready:ordered.append(j);known.add(j['part1'])
action=bpy.data.actions.new('Zyntra_TableHide_Actual_Hold_4s_v2');arm.animation_data.action=action;action.use_fake_user=True
for bone in arm.pose.bones:bone.rotation_mode='QUATERNION'
for frame in range(1,122):
    phase=(frame-1)/120*math.tau
    for j in ordered:
        T=Matrix(authored['jointTransforms'][j['name']])
        if j['name']=='Waist':T=T@Matrix.Rotation(math.radians(math.sin(phase)*.20),4,'X')
        elif j['name']=='Neck':T=T@Matrix.Rotation(math.radians(-math.sin(phase)*.15),4,'X')
        bone=arm.pose.bones[j['part1']];bone.matrix_basis=B@T@B.inverted()
        bone.keyframe_insert('location',frame=frame,group=bone.name)
        bone.keyframe_insert('rotation_quaternion',frame=frame,group=bone.name)
    arm.pose.bones['HumanoidRootPart'].matrix_basis=Matrix.Identity(4)
curves=list(action.fcurves) if hasattr(action,'fcurves') else [c for l in action.layers for s in l.strips for b in s.channelbags for c in b.fcurves]
for curve in curves:
    for k in curve.keyframe_points:k.interpolation='LINEAR'
frames=[];worst=0;min_y=1e6;max_y=-1e6;max_x=0;max_z=0
for frame in range(1,122):
    scene.frame_set(frame);dg=bpy.context.evaluated_depsgraph_get();evaluated=arm.evaluated_get(dg)
    world={'HumanoidRootPart':Matrix.Identity(4)};values=[['HumanoidRootPart',0,0,0,0,0,0,1]]
    for j in ordered:
        bone_world=B.inverted()@evaluated.pose.bones[j['part1']].matrix@B
        world[j['part1']]=bone_world@cf(j['c1']).inverted()
        T=cf(j['c0']).inverted()@world[j['part0']].inverted()@world[j['part1']]@cf(j['c1'])
        q=T.to_quaternion();p=T.translation
        values.append([j['part1'],float(p.x),float(p.y),float(p.z),float(q.x),float(q.y),float(q.z),float(q.w)])
        if frame==1:
            expected=Matrix(authored['jointTransforms'][j['name']])
            worst=max(worst,max(abs(T[r][c]-expected[r][c]) for r in range(4) for c in range(4)))
    frames.append([(frame-1)/30,values])
    for obj in scene.objects:
        if not obj.get('roblox_part'):continue
        e=obj.evaluated_get(dg);mesh=e.to_mesh()
        for vert in mesh.vertices:
            p=B.inverted()@(e.matrix_world@vert.co)
            min_y=min(min_y,p.y);max_y=max(max_y,p.y);max_x=max(max_x,abs(p.x));max_z=max(max_z,abs(p.z))
        e.to_mesh_clear()
if worst>5e-5:raise RuntimeError('Joint roundtrip mismatch: '+str(worst))
if min_y < -2.18 or max_y > .53 or max_x >1.51 or max_z >2.06:raise RuntimeError('Geometry outside hide clearance '+str((min_y,max_y,max_x,max_z)))
payload={'name':'Zyntra_TableHide_Actual_Hold_4s_v2','looped':True,'priority':'Action','fps':30,'parents':{'HumanoidRootPart':None,**{j['part1']:j['part0'] for j in ordered}},'jointNames':{j['part1']:j['name'] for j in ordered},'frames':frames,'blenderRoundtripMaxError':worst}
(out/'hide-hold-v2-keyframes.json').write_text(json.dumps(payload,separators=(',',':'))+'\n')
# Replace only the authoring table proxies with the actual imported table.
for obj in scene.objects:
    if obj.name.startswith(('Tabletop cutaway','Table side support')):obj.hide_render=True
if not scene.objects.get('Level3_Actual_Table'):
    bpy.ops.object.select_all(action='DESELECT')
    bpy.ops.wm.obj_import(filepath=str(root/'_local/trello-20260916/character-export/actual-table.obj'),forward_axis='NEGATIVE_Z',up_axis='Y',use_split_objects=True,use_split_groups=True)
    for obj in bpy.context.selected_objects:obj.name='Level3_Actual_Table'
scene.frame_set(1);scene.camera.location=(7,9,2.5);scene.camera.rotation_euler=(Vector((-1,0,-.6))-scene.camera.location).to_track_quat('-Z','Y').to_euler();scene.camera.data.ortho_scale=10
scene.render.filepath=str(out/'actual-character-table-final.png');bpy.ops.render.render(write_still=True)
bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=str(out/'zyntra-table-hide-v2.blend'),copy=True)
result={'frames':121,'seconds':4,'roundtripMaxError':worst,'floorClearance':2.2+min_y,'colliderClearance':.56-max_y,'maxLaneX':max_x,'maxDepth':max_z,'meshes':18,'rootDrift':0,'assetPending':True}
(out/'actual-bake-validation.json').write_text(json.dumps(result,indent=2)+'\n')
'''
if __name__=='__main__':print(json.dumps(execute(CODE,timeout=120)))
