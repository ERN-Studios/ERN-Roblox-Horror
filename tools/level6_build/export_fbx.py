"""Export each authored prefab as one named mesh for Studio's standard importer."""
import bpy,bmesh,json,math
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'assets/level6-worn-party'
scene=bpy.data.scenes.new('Studio Import | 49 reusable prefabs')
bpy.context.window.scene=scene
scene.unit_settings.scale_length=1
flat=bpy.data.materials.new('L6_TextureAssignedInStudio');flat.diffuse_color=(1,1,1,1)
objects=[]
for index,col in enumerate(sorted([c for c in bpy.data.collections if c.name.startswith('L6K_')],key=lambda c:c.name)):
    parts=[]
    for ob in col.all_objects:
        if ob.type!='MESH' or ob.get('export_collision_only'):continue
        copy=ob.copy();copy.data=ob.data.copy();scene.collection.objects.link(copy);parts.append(copy)
    bpy.ops.object.select_all(action='DESELECT')
    for ob in parts:ob.select_set(True)
    bpy.context.view_layer.objects.active=parts[0]
    bpy.ops.object.join()
    ob=bpy.context.view_layer.objects.active;ob.name=col.name
    # Bake each source object's transform, then use a neat grid for easy import review.
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    ob.data.materials.clear();ob.data.materials.append(flat)
    for poly in ob.data.polygons:poly.material_index=0
    ob.location=((index%7)*110,(index//7)*95,0)
    objects.append(ob)
for ob in objects:ob.select_set(True)
bpy.ops.export_scene.fbx(filepath=str(OUT/'Level6_ReusableKit.fbx'),use_selection=True,object_types={'MESH'},axis_forward='-Z',axis_up='Y',global_scale=1.0,apply_unit_scale=True,apply_scale_options='FBX_SCALE_NONE',bake_anim=False,mesh_smooth_type='FACE',use_mesh_modifiers=True,path_mode='AUTO',add_leaf_bones=False)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'Level6_ImportKit.blend'))
print('FBX_KIT_EXPORTED',len(objects),flush=True)
