"""Bind the native Studio OBJ export to the measured animation rig in Blender."""
from pathlib import Path
import json
from blender_mcp_client import execute

ROOT = Path(__file__).resolve().parents[1]
CODE = r'''
import bpy, json, math
from pathlib import Path
from mathutils import Matrix, Vector
root=Path(r'G:\Roblox\MongoTV')
out=root/'assets/animations/table-hiding'
export=root/'_local/trello-20260916/character-export/actual-character.obj'
exported=json.loads((root/'artifacts/trello-20260916/character-export-rig.json').read_text())
rig=json.loads((root/'artifacts/trello-20260915/codex-hiding-rig.json').read_text())
def cf(a): return Matrix(((a[3],a[4],a[5],a[0]),(a[6],a[7],a[8],a[1]),(a[9],a[10],a[11],a[2]),(0,0,0,1)))
B=Matrix(((1,0,0,0),(0,0,-1,0),(0,1,0,0),(0,0,0,1)))
def convert(m): return B@m@B.inverted()
rest={'HumanoidRootPart':Matrix.Identity(4)}
ordered=[]
while len(ordered)<len(rig['joints']):
    ready=[j for j in rig['joints'] if j['part0'] in rest and j['part1'] not in rest]
    if not ready: raise RuntimeError('Disconnected rig')
    for j in ready:
        rest[j['part1']]=rest[j['part0']]@cf(j['c0'])@cf(j['c1']).inverted(); ordered.append(j)
name='Zyntra_TableHide_Actual_20260916'
if bpy.data.scenes.get(name): raise RuntimeError('Inspect existing scene before rebuilding')
source=bpy.data.scenes['Zyntra_TableHide_20260915']
scene=source.copy(); scene.name=name
bpy.context.window.scene=scene
copies={}
for obj in list(scene.objects):
    scene.collection.objects.unlink(obj)
    if obj.get('authoring_proxy'): continue
    new=obj.copy()
    if obj.data: new.data=obj.data.copy()
    scene.collection.objects.link(new); copies[obj.name]=new
arm=copies['Zyntra_TableHide_Rig']; arm.name='Zyntra_Actual_Hazmat_Rig'
arm.animation_data.action=arm.animation_data.action.copy()
arm.animation_data.action.name='Zyntra_TableHide_Hold_Actual_v2'
scene.camera=copies[source.camera.name]
scene.frame_set(1)
bpy.ops.object.select_all(action='DESELECT')
bpy.ops.wm.obj_import(filepath=str(export),forward_axis='NEGATIVE_Z',up_axis='Y',use_split_objects=True,use_split_groups=True)
imported=list(bpy.context.selected_objects)
parts={p['name']:p for p in exported['parts'] if p['name']!='HumanoidRootPart'}
mapped=[]
for obj in imported:
    pts=[obj.matrix_world@v.co for v in obj.data.vertices]
    lo=Vector(tuple(min(v[i] for v in pts) for i in range(3)))
    hi=Vector(tuple(max(v[i] for v in pts) for i in range(3)))
    center=(lo+hi)/2; size=hi-lo
    def err(p):
        expected=B@Vector(p['cf'][:3]); s=p['size']; dims=Vector((s[0],s[2],s[1]))
        return (center-expected).length+(size-dims).length
    match=min(parts.values(),key=err); error=err(match)
    if error>.015: raise RuntimeError('Mesh mapping mismatch '+obj.name+' '+match['name']+' '+str(error))
    pname=match['name']; parts.pop(pname)
    target=pname if pname in rest else 'UpperTorso'
    export_cf=convert(cf(match['cf']))
    target_cf=convert(rest[target])
    if target!=pname:
        upper=next(p for p in exported['parts'] if p['name']=='UpperTorso')
        target_cf=target_cf@convert(cf(upper['cf'])).inverted()@export_cf
    obj.data.transform(export_cf.inverted()@obj.matrix_world)
    obj.matrix_world=target_cf; obj.name=pname+'_Actual'
    group=obj.vertex_groups.new(name=target); group.add(list(range(len(obj.data.vertices))),1,'REPLACE')
    mod=obj.modifiers.new('Actual measured rig','ARMATURE'); mod.object=arm
    obj['roblox_part']=pname; obj['mesh_mapping_error']=error
    mapped.append({'part':pname,'vertices':len(obj.data.vertices),'mappingError':error})
if parts: raise RuntimeError('Missing exported parts '+str(list(parts)))
scene['source']='Actual StarterPlayer.StarterCharacter meshes/textures exported by native Studio UI; measured AnimationConstraint attachments'
scene.render.resolution_x=1400; scene.render.resolution_y=1050
scene.render.filepath=str(out/'actual-character-hide-preview.png')
bpy.ops.wm.save_as_mainfile(filepath=str(out/'zyntra-table-hide-v2.blend'),copy=True)
bpy.ops.render.render(write_still=True)
result={'scene':scene.name,'mapped':mapped,'preview':scene.render.filepath}
'''

if __name__ == '__main__':
    result=execute(CODE,timeout=120)
    (ROOT/'artifacts/trello-20260916/actual-character-blender.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result))
