"""Render saved mall at 960x540, Eevee/16 samples, one process / two threads.
Blender -b --factory-startup --threads 2 --python tools/lobby_mall/render_mall.py
Optional '-- --views R03 R13' restricts named frames without changing design.
Only R14 gets temporary work lights, R00 hides ceiling for plan review.
"""
import bpy,json,math,sys,tempfile,atexit
sys.dont_write_bytecode=True
import numpy as np
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parent))
from build_mall import rotation,local_mesh,S
from mathutils import Vector
scratch=tempfile.TemporaryDirectory(prefix='stayquiet_mall_render_',dir='/tmp');atexit.register(scratch.cleanup)
bpy.context.preferences.filepaths.temporary_directory=scratch.name
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'artifacts/lobby-mall-20261011/build'
bpy.ops.wm.open_mainfile(filepath=str(OUT/'mall.blend'));scene=bpy.context.scene
scene.render.engine='BLENDER_EEVEE';scene.render.threads_mode='FIXED';scene.render.threads=2
scene.render.resolution_x=960;scene.render.resolution_y=540;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGB'
if hasattr(scene,'eevee'):scene.eevee.taa_render_samples=16

def v(p):return Vector((p[0],p[2],p[1]))
# Eye-level shop views perpendicular to fronts, all from the fixed floor plan.
views=[
 ('R00_plan',(220,365,-660),(220,30,-660),50,'ORTHO'),
 ('R01_arrival',(220,34.5,-899.2),(220,37.5,-795),116,'PERSP'),
 ('R02_shop_and_supplies',(202,34.5,-811),(220,36.7,-770),98,'PERSP'),
 ('R03_shop_level1',(206,34.5,-840),(151,36.8,-840),90,'PERSP'),
 ('R04_shop_level2',(234,34.5,-840),(289,36.8,-840),90,'PERSP'),
 ('R05_shop_level3',(206,34.5,-760),(151,36.8,-760),90,'PERSP'),
 ('R06_shop_level4',(234,34.5,-760),(289,36.8,-760),90,'PERSP'),
 ('R07_shop_level5',(206,34.5,-680),(151,36.8,-680),90,'PERSP'),
 ('R08_shop_level6',(234,34.5,-680),(289,36.8,-680),90,'PERSP'),
 ('R09_queue_bay',(186,34.5,-863),(155,35.7,-837),104,'PERSP'),
 ('R10_the_tape',(245,34.5,-650),(233.3,33.2,-621),96,'PERSP'),
 ('R11_in_the_dark',(220,34.5,-598),(220,35,-511),90,'PERSP'),
 ('R12_event_stage',(220,34.5,-696.5),(220,36.6,-641),67,'PERSP'),
 ('R13_stand_from_above',(193,65,-804),(220,33.4,-770),65,'PERSP'),
 ('R14_dark_wing_lit_for_review',(220,40,-617),(220,36,-500),78,'PERSP'),
 ('R15_shop_skins',(220,34.5,-798),(220,34.0,-784),91,'PERSP'),
 ('R16_shop_advanced_equipment',(220,34.5,-791),(220,33.1,-781.2),78,'PERSP')]
D=json.loads(bpy.data.texts['mall.json'].as_string())
if D!=json.loads((OUT/'mall.json').read_text()):raise RuntimeError('STALE BLEND: rebuild before rendering')
(OUT/'renders').mkdir(exist_ok=True)
errors=[];max_error=0
bpy.context.view_layer.update()
for p in D['parts']:
    ob=bpy.data.objects[p['name']];vertices=np.array([tuple(v.co) for v in ob.data.vertices]);M=np.array(ob.matrix_world)
    world=vertices@M[:3,:3].T+M[:3,3]
    local,_=local_mesh(p['shape'],p['size'])
    expected=(local@rotation(p['rot']).T+np.array(p['pos']))@S.T
    err=float(np.max(abs(world-expected)));max_error=max(err,max_error)
    if err>1e-4:errors.append(p['name'])
if errors:raise RuntimeError('Blender geometry diverged: '+str(errors))
shader_checks={}
for name,expected in [('PriceAdvancedEquipment_Face','ShaderNodeEmission'),('Shop1_Station1_Face','ShaderNodeEmission'),('StandCRTScreen','ShaderNodeEmission'),('PartyTable','ShaderNodeBsdfPrincipled'),('Counter0_Body','ShaderNodeBsdfPrincipled')]:
    mat=bpy.data.objects[name].active_material
    node=next(n for n in mat.node_tree.nodes if n.type=='OUTPUT_MATERIAL')
    actual=node.inputs['Surface'].links[0].from_node.bl_idname
    if actual!=expected:raise RuntimeError('Wrong face/body shader: '+name+' '+actual)
    shader_checks[name]=actual
for i in range(1,7):
    actual=bpy.data.objects[f'Product{i}_Glass'].active_material.surface_render_method
    if actual!='BLENDED':raise RuntimeError('Dithered case glass: '+str(i))
    shader_checks[f'Product{i}_Glass']=actual
cap_error=0
for sign in D['signs']:
    ob=bpy.data.objects[sign['name']+'_Text']
    if ob.data.body!=sign['text']:raise RuntimeError('Wrong Blender sign text: '+sign['name'])
    if sign['style']=='box':
        bb=np.array(ob.bound_box);cap=(bb[:,1].max()-bb[:,1].min())*ob.scale.y
        cap_error=max(cap_error,abs(cap-sign['size'][1]*.55))
if cap_error>1e-5:raise RuntimeError('Wrong DIN cap height')
(OUT/'blend_parity.json').write_text(json.dumps({'passed':True,'parts':len(D['parts']),'max_vertex_error_studs':max_error,'json_equal':True,'font':'DIN Condensed Bold','eevee_samples':16,'render_engine':'BLENDER_EEVEE','threads':2,'world_strength':0,'part_color_mode':'white tint for absolute colour maps','standing_eye_y':34.5,'shader_checks':shader_checks,'box_cap_height_max_error':cap_error},indent=2)+'\n')
camdata=bpy.data.cameras.new('QA_camera');camera=bpy.data.objects.new('QA_camera',camdata);scene.collection.objects.link(camera);scene.camera=camera;camdata.clip_start=.15;camdata.clip_end=1500
wanted=None
if '--views' in sys.argv:wanted=sys.argv[sys.argv.index('--views')+1:]
metadata=[]
for name,pos,target,fov,typ in views:
    if wanted and name[:3] not in wanted:continue
    hidden=[];work=[]
    # Plan has no ceiling; increased exposure still uses solely the data lights.
    if name=='R13_stand_from_above':
        for ob in bpy.data.objects:
            if ob.get('group')=='Ceiling':
                hidden.append((ob,ob.hide_render));ob.hide_render=True
    if name=='R00_plan':
        for ob in bpy.data.objects:
            if ob.get('group')=='Ceiling' or (ob.get('part_name') and ('_Ceiling' in ob.name)):
                hidden.append((ob,ob.hide_render));ob.hide_render=True
        # Landscape can display full plan with north pointing right; fits 483x190 studs.
        camera.location=v(pos);camera.rotation_euler=(0,0,math.pi/2);camdata.ortho_scale=505
        scene.view_settings.exposure=1
    else:
        scene.view_settings.exposure=0;camera.location=v(pos);camera.rotation_euler=(v(target)-camera.location).to_track_quat('-Z','Y').to_euler()
    if name=='R14_dark_wing_lit_for_review':
        for k,z in enumerate((-605,-555,-505,-455)):
            data=bpy.data.lights.new(f'REVIEW_ONLY_Worklight{k}','POINT');data.energy=6500;data.shadow_soft_size=4;data.use_shadow=False;data.color=(1,.94,.82)
            ob=bpy.data.objects.new(data.name,data);scene.collection.objects.link(ob);ob.location=v((220,38,z));work.append(ob)
    camdata.type=typ
    if typ=='PERSP':camdata.lens=36/(2*math.tan(math.radians(fov)/2));camdata.sensor_width=36
    scene.render.filepath=str(OUT/'renders'/f'{name}.png');bpy.ops.render.render(write_still=True)
    metadata.append({'view':name,'roblox_camera':pos,'target':target,'horizontal_fov':fov,'type':typ,'ceiling_hidden':bool(hidden),'work_lights':len(work),'exposure':scene.view_settings.exposure})
    for ob,hide in hidden:ob.hide_render=hide
    for ob in work:bpy.data.objects.remove(ob,do_unlink=True)
    print('RENDER_DONE',name,flush=True)
old=[]
if (OUT/'render_views.json').exists():old=json.loads((OUT/'render_views.json').read_text())
by={r['view']:r for r in old};by.update({r['view']:r for r in metadata});(OUT/'render_views.json').write_text(json.dumps(list(by.values()),indent=2)+'\n')
scratch.cleanup()
print('RENDERS COMPLETE',flush=True)
