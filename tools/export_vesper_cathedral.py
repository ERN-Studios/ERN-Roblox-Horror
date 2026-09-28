"""Export selected map meshes and render named previews; Blender background script."""
import bpy, json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]/'assets/maps/vesper-cathedral'
scene=bpy.data.scenes['Vesper Cathedral']
bpy.context.window.scene=scene
for obj in bpy.context.selected_objects:obj.select_set(False)
coll=bpy.data.collections['VESPER | Import Geometry']
for obj in coll.objects:obj.select_set(True)
bpy.context.view_layer.objects.active=next(iter(coll.objects))
# Raw coordinates are studs; Studio Scale Unit must be Studs.
bpy.ops.export_scene.gltf(filepath=str(ROOT/'VesperCathedral.glb'),use_selection=True,use_active_scene=True,
                         export_yup=True,export_apply=True,export_animations=False,
                         export_cameras=False,export_lights=False,export_materials='EXPORT',
                         export_extras=True)
bpy.ops.export_scene.fbx(filepath=str(ROOT/'VesperCathedral.fbx'),use_selection=True,
                        object_types={'MESH'},global_scale=1,apply_unit_scale=True,
                        apply_scale_options='FBX_SCALE_UNITS',axis_forward='-Z',axis_up='Y',
                        use_mesh_modifiers=True,mesh_smooth_type='OFF',use_triangles=True,
                        add_leaf_bones=False,bake_anim=False,path_mode='COPY',embed_textures=True)
for label in ('Exterior','Interior','Sanctuary'):
    scene.camera=bpy.data.objects['Vesper_Camera_'+label]
    scene.render.filepath=str(ROOT/'previews'/f'{label.lower()}.png')
    bpy.ops.render.render(write_still=True)
print(json.dumps({'exports':['VesperCathedral.glb','VesperCathedral.fbx'],
                  'previews':['exterior.png','interior.png','sanctuary.png']}))
