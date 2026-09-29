"""Blender-authored modular Level6 kit, six furnished studies, and export source."""
import bpy,bmesh,json,math,sys,random
from pathlib import Path
from mathutils import Vector,Matrix

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'assets/level6-worn-party'
VERSION='v2'
EXPORT=OUT/('exports-'+VERSION)
sys.path.insert(0,str(Path(__file__).parent))
ATLAS=json.loads((OUT/'textures/atlas-layout.json').read_text())
MATS={};KITS={};COLLIDERS={};ANCHORS={}
SCENE=bpy.data.scenes.new('Level 6 | Modular Asset Library')
bpy.context.window.scene=SCENE
SCENE.unit_settings.scale_length=1.0

def material(key):
    if key in MATS:return MATS[key]
    mat=bpy.data.materials.new('L6_'+key);mat.use_nodes=True;mat['l6_material_key']=key
    p=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    tex=mat.node_tree.nodes.new('ShaderNodeTexImage');tex.image=bpy.data.images.load(str(OUT/'textures/WornParty_Atlas.png'),check_existing=True)
    mat.node_tree.links.new(tex.outputs['Color'],p.inputs['Base Color'])
    if key=='glass':
        p.inputs['Alpha'].default_value=.16
        if hasattr(mat,'surface_render_method'):
            valid={i.identifier for i in mat.bl_rna.properties['surface_render_method'].enum_items}
            if 'DITHERED' in valid:mat.surface_render_method='DITHERED'
    p.inputs['Roughness'].default_value=.84 if 'carpet' in key else .66
    if key in ('chrome','cd_silver'):p.inputs['Metallic'].default_value=.72;p.inputs['Roughness'].default_value=.30
    if key.startswith('screen_') and key!='screen_dark':
        mat.node_tree.links.new(tex.outputs['Color'],p.inputs['Emission Color']);p.inputs['Emission Strength'].default_value=.7
    if key=='glow':
        mat.node_tree.links.new(tex.outputs['Color'],p.inputs['Emission Color']);p.inputs['Emission Strength'].default_value=2.5
    mat.diffuse_color=(.6,.5,.3,1);MATS[key]=mat
    return mat

for k in ATLAS['mapping']:material(k)
# Shared aliases used by the prop author.
MATS['cardboard']=material('cardboard');MATS['grey_metal']=material('grey_metal')

def collection(name):
    c=bpy.data.collections.new('L6K_'+name);SCENE.collection.children.link(c);KITS[name]=c;return c

def mesh_object(col,name,vs,fs,key):
    me=bpy.data.meshes.new(name);me.from_pydata(vs,[],fs);me.update()
    ob=bpy.data.objects.new(name,me);col.objects.link(ob);ob.data.materials.append(material(key));ob['l6_material_key']=key
    return ob

def box(col,name,c,d,key,bevel=0):
    bm=bmesh.new();bmesh.ops.create_cube(bm,size=1)
    for v in bm.verts:v.co=Vector((v.co.x*d[0],v.co.y*d[1],v.co.z*d[2]))
    if bevel:
        bmesh.ops.bevel(bm,geom=list(bm.edges),offset=min(bevel,min(d)*.45),segments=2,affect='EDGES',clamp_overlap=True)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));me=bpy.data.meshes.new(name);bm.to_mesh(me);bm.free()
    ob=bpy.data.objects.new(name,me);col.objects.link(ob);ob.location=c;ob.data.materials.append(material(key));ob['l6_material_key']=key;return ob

def anchor(col,name,position):
    ob=bpy.data.objects.new(name,None);col.objects.link(ob);ob.location=position;ob['l6_anchor']=True
    return ob

def tiled_plane(col,name,w,d,z,key,tile=16,down=False):
    nx=math.ceil(w/tile);ny=math.ceil(d/tile);vs=[];fs=[]
    for iy in range(ny):
        for ix in range(nx):
            x0=-w/2+ix*w/nx;x1=-w/2+(ix+1)*w/nx;y0=-d/2+iy*d/ny;y1=-d/2+(iy+1)*d/ny
            j=len(vs);vs.extend([(x0,y0,z),(x1,y0,z),(x1,y1,z),(x0,y1,z)]);fs.append(tuple(j+i for i in ([3,2,1,0] if down else [0,1,2,3])))
    ob=mesh_object(col,name,vs,fs,key);ob['l6_face_uv']=True;return ob

def architecture():
    for suffix,key in [('Beige','beige_wall'),('Orange','orange_wall'),('Red','red_wall'),('Service','beige_wall')]:
        col=collection('Wall'+suffix)
        box(col,'Painted plaster',(0,0,6),(8,1.5,12),key,.025)
        h=3 if suffix in ('Orange','Red') else .48
        for y in (-.761,.761):box(col,'Vinyl kick panel',(0,y,h/2),(8,.022,h),'black_wall')
        if suffix=='Service':
            for y in (-.776,.776):box(col,'Retrofitted conduit',(0,y,10.5),(8,.075,.075),'grey_metal',.02)
        COLLIDERS['Wall'+suffix]=[{'center':[0,0,6],'size':[8,1.5,12]}]
        col=collection('Lintel'+suffix);box(col,'Plaster lintel',(0,0,.75),(14,1.5,1.5),key,.025)
    for suffix,key in [('Beige','carpet_beige'),('Orange','carpet_confetti'),('Red','carpet_red'),('Service','linoleum')]:
        col=collection('Floor'+suffix)
        tiled_plane(col,'Carpet / floor finish',80,64,.005,key,16)
        box(col,'Floor slab',(0,0,-.51),(80,64,1),'black_wall')
        COLLIDERS['Floor'+suffix]=[{'center':[0,0,-.5],'size':[80,64,1]}]
    col=collection('Ceiling')
    tiled_plane(col,'Acoustic ceiling tiles',80,64,0,'ceiling',4,True)
    for x in range(-40,41,4):box(col,'T-grid crossbar',(x,0,-.035),(.07,64,.075),'ceiling_grid')
    for y in range(-32,33,4):box(col,'T-grid rail',(0,y,-.035),(80,.07,.075),'ceiling_grid')
    # Fixture shell; emissive diffuser is kept as a distinct Blender mesh prefab
    # so the Roblox blackout controller can own it without repainting an atlas room.
    col=collection('FluorescentFrame')
    box(col,'Pressed metal frame',(0,0,.11),(7.5,2.4,.32),'grey_metal',.035)
    for x in (-3.61,3.61):box(col,'Clip',(x,0,-.065),(.09,2.26,.065),'chrome')
    col=collection('FluorescentDiffuser')
    box(col,'Ribbed yellowed diffuser',(0,0,0),(7.05,2.05,.14),'glow',.035)
    for x in range(-17,18):box(col,'Diffuser fluting',(x*.195,0,-.075),(.016,1.96,.02),'ivory_plastic')
    col=collection('PASpeaker')
    box(col,'Speaker enclosure',(0,0,0),(1.75,1.1,2.3),'black_metal',.08)
    for z in (-.55,.5):
        bm=bmesh.new();bmesh.ops.create_uvsphere(bm,u_segments=16,v_segments=8,radius=.58)
        for v in bm.verts:v.co.y*=.12;v.co.y-=.59;v.co.z+=z
        me=bpy.data.meshes.new('Speaker cone');bm.to_mesh(me);bm.free();o=bpy.data.objects.new('Speaker cone',me);col.objects.link(o);o.data.materials.append(material('rubber'))
    col=collection('RoomDivider')
    for i in (-1,0,1):
        x=i*2.75
        box(col,'Folding frame',(x,0,4),(2.76,.24,8),'black_metal',.045)
        box(col,'Fabric panel',(x,-.15,4),(2.48,.09,7.68),'paper_worn',.015)
        for sx in (-1,1):box(col,'Rubber foot',(x+sx*1.14,0,.16),(.18,.7,.25),'rubber',.04)
    col=collection('ServiceDoor')
    box(col,'Door slab',(0,0,5),(6,.28,10),'service_door',.04)
    box(col,'Steel kick plate',(0,-.153,1.0),(5.65,.035,1.5),'grey_metal')
    box(col,'Handle escutcheon',(2.22,-.18,4.2),(.25,.045,.8),'chrome',.04)
    box(col,'Lever handle',(2.0,-.28,4.3),(.8,.12,.10),'chrome',.04)
    for sx in (-1,1):box(col,'Door frame',(sx*3.17,0,5.12),(.22,.55,10.25),'grey_metal')
    box(col,'Header',(0,0,10.22),(6.56,.55,.22),'grey_metal')
    col=collection('VentGrille');box(col,'Grille surround',(0,0,0),(3.5,.14,1.8),'grey_metal',.035)
    for z in range(-6,7):box(col,'Vent slat',(0,-.095,z*.105),(3.15,.045,.055),'black_metal')
    col=collection('Clock');
    # Flat chamfered round clock using a small authored cylinder.
    for name,r,depth,y,key in [('Rim',.8,.12,0,'black_metal'),('Face',.72,.02,-.075,'paper')]:
        vs=[(math.cos(i*math.tau/32)*r,y+dy,math.sin(i*math.tau/32)*r) for dy in (-depth/2,depth/2) for i in range(32)]
        fs=[tuple(range(31,-1,-1)),tuple(range(32,64))]+[(i,(i+1)%32,(i+1)%32+32,i+32) for i in range(32)]
        mesh_object(col,name,vs,fs,key)
    for i in range(12):
        angle=i*math.tau/12;ob=box(col,'Clock tick',(math.sin(angle)*.59,-.1,math.cos(angle)*.59),(.045,.014,.105),'black_metal');ob.rotation_euler.y=angle
    box(col,'Minute hand',(0,-.12,.24),(.03,.02,.48),'black_metal');o=box(col,'Hour hand',(.15,-.13,0),(.32,.02,.04),'black_metal');o.rotation_euler.y=-.6

def uv_rect(key):
    info=ATLAS['mapping'].get(key,ATLAS['mapping']['grey_metal']);cell=info['cell'];r=info['rect'];x=(cell%4)*512;y=(cell//4)*512
    return ((x+r[0])/2048,1-(y+r[3])/2048,(x+r[2])/2048,1-(y+r[1])/2048)

def assign_uv(ob):
    me=ob.data;layer=me.uv_layers.active or me.uv_layers.new(name='AtlasUV')
    for p in me.polygons:
        mat=me.materials[p.material_index] if p.material_index<len(me.materials) else None
        key=mat.get('l6_material_key') if mat else ob.get('l6_material_key','grey_metal')
        if not key:key=ob.get('l6_material_key','grey_metal')
        u0,v0,u1,v1=uv_rect(key)
        ids=list(p.loop_indices);coords=[me.vertices[me.loops[i].vertex_index].co for i in ids]
        ax=max(range(3),key=lambda a:abs(p.normal[a]));axes=[a for a in range(3) if a!=ax]
        vals=[(v[axes[0]],v[axes[1]]) for v in coords];lo=[min(v[a] for v in vals) for a in range(2)];hi=[max(v[a] for v in vals) for a in range(2)]
        for i,(x,y) in zip(ids,vals):
            u=(x-lo[0])/max(hi[0]-lo[0],.001);v=(y-lo[1])/max(hi[1]-lo[1],.001)
            layer.data[i].uv=(u0+(u1-u0)*u,v0+(v1-v0)*v)

def instance(scene,name,asset,pos=(0,0,0),angle=0,scale=(1,1,1)):
    ob=bpy.data.objects.new(name,None);ob.instance_type='COLLECTION';ob.instance_collection=KITS[asset];scene.collection.objects.link(ob);ob.location=pos;ob.rotation_euler.z=angle;ob.scale=scale;return ob

def setup_render(scene):
    scene.render.engine='CYCLES';scene.cycles.samples=24
    scene.render.resolution_x=1536;scene.render.resolution_y=1024;scene.render.resolution_percentage=75
    scene.view_settings.exposure=.4
    scene.render.image_settings.file_format='PNG'
    try:scene.view_settings.view_transform='AgX'
    except TypeError:pass
    scene.world=bpy.data.worlds.new(scene.name+' | World');scene.world.use_nodes=True
    bg=next(n for n in scene.world.node_tree.nodes if n.type=='BACKGROUND');bg.inputs['Color'].default_value=(.25,.28,.33,1);bg.inputs['Strength'].default_value=.18

def lamp(scene,name,pos,energy=450,size=6):
    data=bpy.data.lights.new(name,'AREA');data.energy=energy;data.color=(1,.84,.61);data.shape='RECTANGLE';data.size=size;data.size_y=2
    ob=bpy.data.objects.new(name,data);scene.collection.objects.link(ob);ob.location=pos;return ob

def camera(scene,pos,target,lens=25):
    data=bpy.data.cameras.new(scene.name+' Camera');data.lens=lens;ob=bpy.data.objects.new('Player eye camera',data);scene.collection.objects.link(ob);ob.location=pos;ob.rotation_euler=(Vector(target)-ob.location).to_track_quat('-Z','Y').to_euler();scene.camera=ob

def make_study(kind,index):
    scene=bpy.data.scenes.new('Study %02d | %s'%(index,kind));setup_render(scene)
    suffix='Beige' if kind=='Beige Party Hall' else ('Red' if kind=='Red Party Maze' else ('Service' if kind in ('Party Supply Store','Maintenance Workshop') else 'Orange'))
    w,d=(32,28) if suffix=='Service' else (48,40)
    instance(scene,'Floor','Floor'+suffix,scale=(w/80,d/64,1));instance(scene,'Ceiling','Ceiling',pos=(0,0,12),scale=(w/80,d/64,1))
    for x in (-w/2,w/2):instance(scene,'Side wall','Wall'+suffix,(x,0,0),math.pi/2,(d/8,1,1))
    # A large open rear portal creates depth to the next party room.
    portal=14;side=(w-portal)/2
    for sign in (-1,1):instance(scene,'Rear wall','Wall'+suffix,(sign*(portal/2+side/2),d/2,0),0,(side/8,1,1))
    instance(scene,'Rear portal lintel','Lintel'+suffix,(0,d/2,10.5))
    instance(scene,'Next room floor','FloorOrange',(0,d/2+16,0),scale=(.5,.5,1));instance(scene,'Next room ceiling','Ceiling',(0,d/2+16,12),scale=(.5,.5,1))
    instance(scene,'Far party wall','WallOrange',(0,d/2+30,0),0,(5,1,1))
    for x,y in [(-w*.22,-d*.20),(w*.22,d*.19),(0,d*.63)]:
        instance(scene,'Fluorescent frame','FluorescentFrame',(x,y,11.65));instance(scene,'Fluorescent diffuser','FluorescentDiffuser',(x,y,11.48));lamp(scene,'Fluorescent spill',(x,y,11.35),1050,7)
    def p(asset,pos,angle=0,scale=(1,1,1)):
        if asset in KITS:return instance(scene,asset,asset,pos,angle,scale)
    def table(x,y):
        p('FoldingTable',(x,y,0))
        p('Tableware',(x,y,3.44))
        for i,(dx,dy,a) in enumerate([(-3,-3.7,math.pi),(3,-3.7,math.pi),(-3,3.7,0),(3,3.7,0)]):p(['ChairRed','ChairYellow','ChairGreen','ChairBlue'][i],(x+dx,y+dy,0),a)
    table(0,d/2+17)
    if kind in ('Beige Party Hall','Orange Birthday Rooms','Red Party Maze'):
        table(-12,-7);table(11,5);p('CakeTable',(-w/2+4,10,0),math.pi/2)
        p('BalloonCluster',(-10,15,0));p('BirthdayGarland',(0,d/2-.8,9))
        p('ChairStack',(w/2-4,d/2-4,0));p('PASpeaker',(w/2-.7,4,9),-math.pi/2)
        if kind=='Red Party Maze':p('RoomDivider',(2,11,0),.25)
        if kind=='Beige Party Hall':p('PrizeCounter',(-w/2+4,3,0),math.pi/2)
    elif kind=='Budget Arcade':
        for i,a in enumerate(['ArcadeInvaders','ArcadeMaze','ArcadePlatform']):p(a,(-w/2+3,-7+i*6,0),math.pi/2)
        p('PrizeCounter',(10,13,0));p('ClawMachine',(w/2-4,3,0),-math.pi/2);p('ServiceDoor',(12,d/2-.85,0))
        table(11,-9);p('BirthdayGarland',(10,d/2-.8,9))
    elif kind=='Party Supply Store':
        for y in (-6,5):p('SupplyShelf',(-w/2+2,y,0),math.pi/2)
        p('ChairStack',(w/2-3,6,0));p('FoldedTables',(w/2-3,-3,0),math.pi/2);p('HeliumTank',(-w/2+5,10,0));p('FlatClownCutout',(w/2-5,-7,0));p('ServiceDoor',(9,d/2-.9,0))
    elif kind=='Maintenance Workshop':
        p('WorkshopBench',(-w/2+3,0,0),math.pi/2);p('Pegboard',(-w/2+1,0,5.2),math.pi/2)
        p('SupplyShelf',(w/2-3,4,0),-math.pi/2);p('BreakerPanel',(w/2-1,-5,6),-math.pi/2);p('MopBucket',(w/2-4,-8,0))
        p('ChairRed',(-w/2+5,7,0),-.4);p('Clock',(-w/2+1,5,8.8),math.pi/2)
    camera(scene,(w*.27,-d/2+2,5.6),(-2,6,5.3),24)
    return scene

def build():
    architecture()
    import props
    props_result=props.build_props({'materials':MATS,'collection_prefix':'L6K_','quality':'game','spec_path':str(OUT/('prop-specification-'+VERSION+'.json'))})
    if 'collections' in props_result:props_result=props_result['collections']
    for name,col in props_result.items():
        if isinstance(col,bpy.types.Collection):KITS[name]=col
    for name,col in KITS.items():
        if col.name not in SCENE.collection.children:SCENE.collection.children.link(col)
        for ob in col.all_objects:
            if ob.type=='MESH' and not ob.get('export_collision_only'):assign_uv(ob)
    # Lossless prefab export directly from the authored Blender geometry.
    import importlib.util
    spec=importlib.util.spec_from_file_location('prefab_exporter',str(Path(__file__).parent/'import/export_prefabs.py'))
    exporter=importlib.util.module_from_spec(spec);spec.loader.exec_module(exporter)
    bpy.context.view_layer.update()
    chunks=[]
    for name,col in KITS.items():
        visuals=[o for o in col.all_objects if o.type=='MESH' and not o.get('export_collision_only')]
        cols=COLLIDERS.get(name,[])+[{'center':list(o['center_xyz']),'size':list(o['dimensions_xyz'])} for o in col.all_objects if o.get('export_collision_only')]
        meta={'colliders_xyz':cols,'anchors_xyz':{o.get('l6_anchor',o.name):list(o.location) for o in col.all_objects if o.type=='EMPTY'},'transparent':any(o.get('l6_material_key')=='glass' for o in visuals)}
        chunks.append(exporter.export_prefab(name,visuals,EXPORT,len(chunks),metadata=meta))
    (EXPORT/'manifest.json').write_text(json.dumps({'schema':'level6-blender-prefabs-v1','axisMapping':'X,Z,-Y','studsPerUnit':1,'groupId':1039373905,'atlas':'../textures/WornParty_Atlas1024.png','chunks':chunks},indent=2)+'\n')
    studies=[make_study(name,i+1) for i,name in enumerate(['Beige Party Hall','Orange Birthday Rooms','Red Party Maze','Budget Arcade','Party Supply Store','Maintenance Workshop'])]
    # Organize library view by placing instances in a showroom; source collections remain in their separate scene.
    showroom=bpy.data.scenes.new('Level 6 | Reusable Kit Overview');setup_render(showroom)
    for i,name in enumerate(KITS):instance(showroom,name,name,((i%8)*20,(i//8)*20,0))
    camera(showroom,(70,-65,105),(70,60,0),36)
    lamp(showroom,'Kit overhead',(70,55,110),8000,100)
    bpy.context.window.scene=studies[0]
    for im in bpy.data.images:
        if im.source=='FILE':im.pack()
    manifest={'units':'1 Blender unit = 1 Roblox stud','axisMap':'(x,y,z)->(x,z,-y)','atlas':'textures/WornParty_Atlas.png','assets':{},'studies':[s.name for s in studies]}
    for name,col in KITS.items():
        visuals=[o for o in col.all_objects if o.type=='MESH' and not o.get('export_collision_only')]
        tris=0
        for o in visuals:o.data.calc_loop_triangles();tris+=len(o.data.loop_triangles)
        manifest['assets'][name]={'collection':col.name,'visualObjects':len(visuals),'triangles':tris,'colliders':COLLIDERS.get(name,[]),'anchors':{o.name:list(o.location) for o in col.all_objects if o.type=='EMPTY'}}
    (OUT/('kit-manifest-'+VERSION+'.json')).write_text(json.dumps(manifest,indent=2)+'\n')
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/('Level6_WornParty_'+VERSION+'.blend')))
    print('L6_BUILD_COMPLETE',len(KITS),'prefabs',sum(x['triangles'] for x in manifest['assets'].values()),'unique triangles',flush=True)
    if '--render' in sys.argv:
        for i,scene in enumerate(studies):
            bpy.context.window.scene=scene;scene.render.filepath=str(OUT/('previews-'+VERSION)/('%02d-%s.png'%(i+1,scene.name.split('|')[-1].strip().replace(' ','-'))));bpy.ops.render.render(write_still=True)

if __name__=='__main__':build()
