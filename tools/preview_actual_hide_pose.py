"""Review a readable tucked pose using the actual character geometry."""
import json
from pathlib import Path
from blender_mcp_client import execute
from prepare_table_hide_pose import poses
ROOT=Path(__file__).resolve().parents[1]
v=json.loads((ROOT/'assets/animations/table-hiding/authored-actual-pose.json').read_text())['parameters']
transforms={n:m.tolist() for n,m in poses(v).items()}
code='transforms='+repr(transforms)+'\n'+r'''
import bpy, math, json
from mathutils import Matrix,Vector
scene=bpy.data.scenes['Zyntra_TableHide_Actual_20260916']; bpy.context.window.scene=scene
arm=scene.objects['Zyntra_Actual_Hazmat_Rig']
arm.animation_data.action=None
B=Matrix(((1,0,0,0),(0,0,-1,0),(0,1,0,0),(0,0,0,1)))
rig=json.loads(open(r'G:\Roblox\MongoTV\artifacts\trello-20260915\codex-hiding-rig.json').read())
for j in rig['joints']: arm.pose.bones[j['part1']].matrix_basis=B@Matrix(transforms[j['name']])@B.inverted()
for obj in scene.objects:
    if obj.name.startswith('Table side support'): obj.hide_render=True
    if obj.get('roblox_part','').endswith('SeamLiner'):
        color=(.0784314,.0862745,.0941176,1) if obj['roblox_part']=='NeckSeamLiner' else (.2980392,.2588235,.1176471,1)
        for mat in obj.data.materials:
            base=mat.node_tree.nodes.get('Principled BSDF').inputs['Base Color']
            for link in list(base.links):mat.node_tree.links.remove(link)
            base.default_value=color
    if obj.get('roblox_part') and not obj['roblox_part'].endswith('SeamLiner'):
        for material in obj.data.materials:
            if material and not material.get('roblox_tint'):
                tree=material.node_tree; bsdf=tree.nodes.get('Principled BSDF'); base=bsdf.inputs['Base Color']
                if base.is_linked:
                    original=base.links[0].from_socket
                    multiply=tree.nodes.new('ShaderNodeMixRGB'); multiply.blend_type='MULTIPLY'; multiply.inputs[0].default_value=1
                    multiply.inputs[2].default_value=(.8431373,.6666667,.1764706,1)
                    tree.links.new(original,multiply.inputs[1]); tree.links.new(multiply.outputs[0],base)
                    material['roblox_tint']=True
scene.camera.location=(7,5,1.5); scene.camera.rotation_euler=(Vector((0,0,-.7))-scene.camera.location).to_track_quat('-Z','Y').to_euler()
scene.camera.data.ortho_scale=7
scene.render.filepath=r'G:\Roblox\MongoTV\assets\animations\table-hiding\actual-pose-candidate.png'
bpy.context.view_layer.update()
dg=bpy.context.evaluated_depsgraph_get()
bounds={}
for obj in scene.objects:
    if obj.get('roblox_part'):
        e=obj.evaluated_get(dg); mesh=e.to_mesh(); pts=[B.inverted()@(e.matrix_world@vert.co) for vert in mesh.vertices]
        bounds[obj['roblox_part']]={'min':[min(p[i] for p in pts) for i in range(3)],'max':[max(p[i] for p in pts) for i in range(3)]}; e.to_mesh_clear()
bpy.ops.render.render(write_still=True)
result={'bounds':bounds,'preview':scene.render.filepath}
'''
if __name__=='__main__':
    result=execute(code)
    (ROOT/'artifacts/trello-20260916/actual-pose-candidate.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result))
