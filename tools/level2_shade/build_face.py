"""Procedural, sealed shadow face; Blender EEVEE, no external assets.
Full rebuild: Blender --factory-startup -b --python tools/level2_shade/build_face.py
Lighting review: append -- --preview 26 33 (does not assemble partial sheets).
"""
import bpy, math, json, hashlib, subprocess, shutil, struct, sys
import numpy as np
from pathlib import Path
from mathutils import Vector, noise
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'artifacts/level2-shade-face-20261010'
for folder in ('blend', 'frames', 'sheets', 'preview'):
    (OUT / folder).mkdir(parents=True, exist_ok=True)
preview = '--preview' in sys.argv
render_frames = [int(x) for x in sys.argv[sys.argv.index('--preview')+1:]] if preview else list(range(1,37))
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
scene = bpy.context.scene
scene.render.engine = 'BLENDER_EEVEE_NEXT' if 'BLENDER_EEVEE_NEXT' in scene.render.bl_rna.properties['engine'].enum_items.keys() else 'BLENDER_EEVEE'
scene.render.resolution_x = scene.render.resolution_y = 680
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGB'
scene.render.image_settings.color_depth = '8'
scene.render.fps = 12
scene.frame_start, scene.frame_end = 1,36
scene.world.use_nodes = True
scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value = 0
scene.view_settings.view_transform = 'Standard'
scene.render.film_transparent = False
if hasattr(scene, 'eevee'): scene.eevee.taa_render_samples = 48
rig = bpy.data.objects.new('Two-frame held performance', None)
scene.collection.objects.link(rig)

def material(name, color, roughness):
    m = bpy.data.materials.new(name); m.use_nodes = True
    p = m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value = (*color,1)
    p.inputs['Roughness'].default_value = roughness
    p.inputs['Coat Weight'].default_value = .30
    p.inputs['Specular IOR Level'].default_value = .30
    p.inputs['Coat Roughness'].default_value = .14
    return m
skin = material('Wet charcoal skin, crawling pores', (.009,.010,.012), .32)
n, l = skin.node_tree.nodes, skin.node_tree.links
p = n.get('Principled BSDF')
tex = n.new('ShaderNodeTexNoise'); tex.noise_dimensions = '4D'
tex.inputs['Scale'].default_value = 68; tex.inputs['Detail'].default_value = 3
bump = n.new('ShaderNodeBump'); bump.inputs['Strength'].default_value = .26; bump.inputs['Distance'].default_value = .009
l.new(tex.outputs['Fac'], bump.inputs['Height']); l.new(bump.outputs['Normal'], p.inputs['Normal'])
for f in range(1,37):
    tex.inputs['W'].default_value = f*.13; tex.inputs['W'].keyframe_insert('default_value',frame=f)
# There is no emissive outline on the skin: actual lights must expose the sculpt.
veinmat = material('Raised wet strands', (.006,.008,.010), .24)
eyevein = material('Dark capillaries on white orb', (.018,.022,.027), .28)

def mesh_obj(name, verts, faces, mat, parent=rig):
    mesh = bpy.data.meshes.new(name); mesh.from_pydata(verts,[],faces); mesh.update()
    obj = bpy.data.objects.new(name,mesh); scene.collection.objects.link(obj); obj.parent = parent
    obj.data.materials.append(mat)
    for p in mesh.polygons: p.use_smooth = True
    return obj

def sphere(name, loc, scale, mat, parent=rig):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=48,ring_count=32,location=loc)
    obj=bpy.context.object; obj.name=name; obj.parent=parent; obj.scale=scale; obj.data.materials.append(mat)
    for p in obj.data.polygons:p.use_smooth=True
    return obj

def tube(name, points, radius, mat=veinmat, parent=rig, taper=True):
    c=bpy.data.curves.new(name,'CURVE'); c.dimensions='3D'; c.resolution_u=2; c.bevel_depth=radius; c.bevel_resolution=3
    s=c.splines.new('POLY'); s.points.add(len(points)-1)
    for i,(p,co) in enumerate(zip(s.points,points)):
        p.co=(*co,1); p.radius=(.35+.65*math.sin(math.pi*i/(len(points)-1))**.5) if taper else 1
    o=bpy.data.objects.new(name,c);scene.collection.objects.link(o);o.parent=parent;c.materials.append(mat)
    return o

def gauss(x,z,cx,cz,sx,sz):return math.exp(-((x-cx)/sx)**2-((z-cz)/sz)**2)
# Horizontal anatomical rings, not an ellipsoid. Broad bony cheeks, sunken
# temples, angular jaw and long pinched chin interrupt the skull silhouette.
profile=[(-1.72,.04,.13),(-1.58,.19,.29),(-1.36,.28,.36),(-1.12,.40,.40),(-.85,.48,.41),(-.58,.43,.40),(-.32,.49,.42),(-.08,.66,.46),(.12,.58,.48),(.40,.57,.49),(.70,.54,.50),(1.02,.64,.52),(1.30,.59,.48),(1.51,.42,.35),(1.66,.05,.10)]
def dims(z):
    for i,((z0,w0,d0),(z1,w1,d1)) in enumerate(zip(profile,profile[1:])):
        if z0<=z<=z1:
            t=(z-z0)/(z1-z0);dt=z1-z0
            prev=profile[max(0,i-1)];nxt=profile[min(len(profile)-1,i+2)]
            result=[]
            for k in (1,2):
                m0=(profile[i+1][k]-prev[k])/(profile[i+1][0]-prev[0])
                m1=(nxt[k]-profile[i][k])/(nxt[0]-profile[i][0])
                result.append((2*t**3-3*t*t+1)*profile[i][k]+(t**3-2*t*t+t)*dt*m0+(-2*t**3+3*t*t)*profile[i+1][k]+(t**3-t*t)*dt*m1)
            return result
    return profile[-1][1:]
def anatomy(x,z):
    y=0
    for cx,cz,r in [(-.33,.39,.205),(.34,.26,.256)]:
        y += .27*gauss(x,z,cx,cz,r*.93,r*.86) # actual hollow socket
        rr=math.sqrt(((x-cx)/(r*1.19))**2+((z-cz)/(r*1.10))**2)
        y -= .075*math.exp(-((rr-1)/.17)**2) # orbital bone, no eyelid
        y -= .14*gauss(x,z,cx,cz+r*.92,.28,.085) # overhanging brow
    y -= .07*gauss(x,z,0,.40,.085,.36) # narrow bridge, no nose
    for side in (-1,1):
        y -= .15*gauss(x,z,side*.49,-.10-(.07 if side>0 else 0),.13,.12)
        y += .13*gauss(x,z,side*.34,-.49,.15,.25) # hollow cheek
        y += .095*gauss(x,z,side*.50,.75,.10,.20) # temple hollow
        y -= .085*gauss(x,z,side*.36,-1.03,.10,.22) # jaw corner
    y -= .13*gauss(x,z,.025,-1.44,.19,.22)
    # Grown-over mouth: exclusively vertical tension, no horizontal lip/seam.
    envelope=math.exp(-(x/.34)**6-((z+.83)/.39)**4)
    y -= envelope*(.035+.043*(.5+.5*math.cos(x*64+z*2.7)))
    return y
nu,nv=192,160
verts=[];coords=[];faces=[]
for j in range(nv+1):
    z0=-1.72+3.38*j/nv
    w,d=dims(z0)
    for i in range(nu):
        phi=2*math.pi*i/nu;x=w*math.cos(phi)*(1+.022*math.sin(z0*5+phi*3))
        z=z0-.065*(x/max(w,.01))*(math.sin(math.pi*j/nv)**2)
        front=max(0,-math.sin(phi))**3
        y=d*math.sin(phi)+front*anatomy(x,z)
        # Fine real mesh displacement, in addition to the pore shader.
        y += front*.006*noise.noise_vector(Vector((x*34,y*34,z*34))).x
        verts.append((x,y,z));coords.append((x,y,z,front))
for j in range(nv):
    for i in range(nu):
        a=j*nu+i;b=j*nu+(i+1)%nu;faces.append((a,b,b+nu,a+nu))
# Closed pole caps preserve a fully sealed mesh.
for ring,zcap in ((0,-1.73),(nv,1.67)):
    center=len(verts);verts.append((0,0,zcap));coords.append((0,0,zcap,0))
    for i in range(nu):faces.append((center,ring*nu+i,ring*nu+(i+1)%nu) if ring else (center,(i+1)%nu,i))
head=mesh_obj('Asymmetric gaunt skull, continuous closed mouth skin',verts,faces,skin)
head.shape_key_add(name='Basis')
for f in range(1,37):
    key=head.shape_key_add(name=f'Pressure and crawl {f:02d}')
    pressure=.08*max(0,min(1,(f-9)/9)) if f<19 else .85+.15*math.sin(f*1.6)
    cx=.28*math.sin((f-19)*.85);cz=-.88+.12*math.cos(f*.7)
    for idx,(x,y,z,front) in enumerate(coords):
        env=math.exp(-(x/.36)**6-((z+.83)/.43)**4)
        bulge=.18*gauss(x,z,cx,cz,.14,.24)-.09*gauss(x,z,-cx,-.83,.18,.24)
        folds=.060*math.cos(x*(58+8*math.sin(f*.7))+z*(3+math.sin(f)))*env
        jaw=.11*gauss(x,z,.39*math.sin(f*.78),-1.19,.11,.13)
        crawl=.004*noise.noise_vector(Vector((x*38+f*.05,z*38,f*.21))).x
        key.data[idx].co.y=y-front*(pressure*(bulge+folds+jaw)+crawl)
    key.value=0;key.keyframe_insert('value',frame=max(0,f-1))
    key.value=1;key.keyframe_insert('value',frame=f)
    key.value=0;key.keyframe_insert('value',frame=f+1)
# Narrow neck and a low shoulder saddle, no circular torso/alien body.
sphere('Sinewy neck',(0,.17,-1.92),(.19,.25,.69),skin)
sphere('Bony upper shoulders',(0,.25,-2.86),(1.12,.32,.40),skin)
for side in (-1,1):
    pts=[(side*(.15+.055*t),-.015-.12*math.sin(t*math.pi),-1.46-1.15*t) for t in np.linspace(0,1,32)]
    tube('Exposed neck tendon',pts,.028,skin)
    pts=[(side*(.12+.91*t),-.025+.15*t,-2.62-.19*t+.065*math.sin(t*math.pi)) for t in np.linspace(0,1,36)]
    tube('Raised collarbone',pts,.035,skin)
    for k in range(3):
        pts=[]
        for t in np.linspace(0,1,34):
            z=.69+.48*t-.10*k;x=side*(.46+.07*math.sin(t*4+k))
            w,d=dims(z);phi=-math.acos(min(.99,abs(x)/w)) if side>0 else math.pi+math.acos(min(.99,abs(x)/w))
            y=-d*math.sqrt(max(.01,1-(x/w)**2))+max(.01,1-(x/w)**2)**1.5*anatomy(x,z)-.006
            pts.append((x,y,z))
        tube('Temple raised branching vein',pts,.007+k*.002)
    for k in range(2):
        pts=[(side*(.10+.038*math.sin(t*8+k)), -.065-.045*math.sin(t*math.pi), -1.75-.71*t) for t in np.linspace(0,1,36)]
        tube('Neck vein',pts,.007)
# Long tapered skin/wet filaments anchored under chin and jaw; never teeth.
for k,(x,z,length) in enumerate([(-.29,-1.35,.62),(-.13,-1.57,.46),(.10,-1.59,.64),(.34,-1.25,.52)]):
    pts=[(x+.018*math.sin(t*6+k),-.24-.025*t,z-length*t) for t in np.linspace(0,1,38)]
    o=tube('Hanging wet chin filament',pts,.008)
    for f in range(1,37):
        for i,p in enumerate(o.data.splines[0].points):
            t=i/(len(pts)-1);p.co.x=pts[i][0]+.018*t*math.sin(f*1.1+k+t*5)
            p.keyframe_insert('co',frame=f)
# Round orbs: grazing emission falls off to grey at the spherical rim.
eye=material('White orb with dark spherical rim',(.30,.32,.34),.16)
n,l=eye.node_tree.nodes,eye.node_tree.links;p=n.get('Principled BSDF')
lw=n.new('ShaderNodeLayerWeight');lw.inputs['Blend'].default_value=.4
ramp=n.new('ShaderNodeValToRGB');ramp.color_ramp.elements[0].position=.12;ramp.color_ramp.elements[0].color=(.93,.96,1,1)
ramp.color_ramp.elements[1].position=.84;ramp.color_ramp.elements[1].color=(.028,.033,.04,1)
l.new(lw.outputs['Facing'],ramp.inputs[0])
blowout=n.new('ShaderNodeMixRGB');blowout.blend_type='MIX';blowout.inputs[2].default_value=(1,1,1,1)
l.new(ramp.outputs[0],blowout.inputs[1]);l.new(blowout.outputs[0],p.inputs['Emission Color'])
for f in range(1,37):
    blowout.inputs[0].default_value=0 if f<34 else (f-33)/3
    blowout.inputs[0].keyframe_insert('default_value',frame=f)
p.inputs['Emission Strength'].default_value=1.15
orbs=[]
capillaries=[]
for index,(cx,cz,r) in enumerate([(-.33,.39,.17),(.34,.26,.213)]):
    orb=sphere('Deep lidless wet orb '+str(index),(cx,-.35,cz),(r,r,r),eye);orbs.append(orb)
    # Capillaries lie on the spherical surface, branching in from the edge.
    for k in range(7):
        angle=2*math.pi*k/7+.31*index
        def veinpath(start,end,offset=0):
            pts=[]
            for t in np.linspace(0,1,22):
                rr=start+(end-start)*t;ang=angle+offset+.055*math.sin(t*9+k)
                u,v=rr*math.cos(ang),rr*math.sin(ang)
                pts.append((u,-math.sqrt(max(.01,1-u*u-v*v))-.018,v))
            return pts
        capillaries.append(tube('Fine dark orb vein',veinpath(.96,.59),.010,eyevein,orb))
        if k%2==0:capillaries.append(tube('Orb capillary fork',veinpath(.80,.68,.12),.007,eyevein,orb))

def light(name,kind,loc,energy,size,target=None,parent=None):
    d=bpy.data.lights.new(name,kind);d.energy=energy;d.color=(.85,.91,1)
    o=bpy.data.objects.new(name,d);scene.collection.objects.link(o);o.location=loc;o.parent=parent
    if kind=='AREA':
        d.shape='DISK';d.size=size
        o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()
    else:d.shadow_soft_size=size
    return o
rims=[light('Left cold rim','AREA',(-2.1,.9,.9),45,1.1,(0,0,0),rig),light('Right cold rim','AREA',(1.9,.8,.0),35,.9,(0,0,-.4),rig)]
top=light('Very weak overhead','AREA',(0,-1.6,3.1),12,1.2,(0,0,-.4),rig)
# Small real lights at each eye, forward of the orb to illuminate its surrounding skin.
spills=[light('Cold eye spill','POINT',(o.location.x,-.69,o.location.z),3.0,.14,parent=rig) for o in orbs]
# Reflection of eye glow reaching the sealed lower face, placed at the eye line.
down=light('Eye glow downward reflection','AREA',(0,-1.15,.31),12,.65,(0,-.45,-.86),rig)
crown=light('Crown and chin rim','AREA',(0,.85,3),22,.85,(0,0,0),rig)
glint=light('Tiny wet eye glint','AREA',(-.8,-2,1.3),8,.12,(0,-.4,.3),rig)
jawrim=light('Jaw and filament rim','AREA',(-.75,.6,-1.4),6,.8,(0,0,-1.6),rig)
camd=bpy.data.cameras.new('Fixed square orthographic camera');cam=bpy.data.objects.new('Fixed camera',camd)
scene.collection.objects.link(cam);cam.location=(0,-10,-.22)
cam.rotation_euler=(Vector((0,0,-.22))-cam.location).to_track_quat('-Z','Y').to_euler()
camd.type='ORTHO';camd.ortho_scale=5.1;scene.camera=cam
# Rig held in two-frame poses; microscopic skin continues moving during holds.
poses={1:(.45,0,0),3:(.45,0,0),5:(.45,0,0),7:(.58,-4,.012),9:(.72,-9,-.016),11:(.89,-16,.016),13:(1.04,-23,-.013),15:(1.20,-29,.018),17:(1.33,-35,-.015),19:(1.42,0,.05),20:(1.48,-37,-.06),21:(1.49,12,.03),22:(1.50,-13,-.025),23:(1.40,-6,-.012),25:(1.41,-9,.009),27:(1.42,-5,-.015),29:(1.43,-8,.007),31:(1.51,-4,0),32:(1.57,3,-.018),33:(1.63,-5,.015),34:(2.35,0,0),35:(4.5,0,0),36:(8,0,0)}
for f in range(1,37):
    pf=max(k for k in poses if k<=f);s,tilt,sway=poses[pf]
    rig.scale=(s,s,s);rig.rotation_euler=(0,math.radians(tilt),0)
    rig.location=(sway,0,-.12 if f<34 else -.3*s)
    for prop in ('scale','rotation_euler','location'):rig.keyframe_insert(prop,frame=f)
    for o,r in zip(orbs,(.17,.213)):
        growth=1+max(0,f-23)*.012 if f<31 else [1.30,1.45,1.60,2.5,3.8,5.3][f-31]
        opening=min(1,f/5)
        o.scale=(r*growth,r*growth,r*growth*opening);o.keyframe_insert('scale',frame=f)
        o.location.x=(-.33 if o==orbs[0] else .34)*(.75**(f-33) if f>=34 else 1)
        o.keyframe_insert('location',frame=f)
    p.inputs['Emission Strength'].default_value=(1.5 if f<=6 else .60) if f<31 else [.85,1.0,1.15,5,9,18][f-31]
    if f in (19,20,21,22):p.inputs['Emission Strength'].default_value=1.9
    p.inputs['Emission Strength'].keyframe_insert('default_value',frame=f)
    gain=.015 if f<=6 else min(1,.32+(f-7)*.10)
    for o,base in zip(rims,(45,35)):
        o.data.energy=base*gain;o.data.keyframe_insert('energy',frame=f)
    for o,base in zip((top,down,crown,glint,jawrim),(12,12,22,8,6)):
        o.data.energy=base*gain if f>6 else 0;o.data.keyframe_insert('energy',frame=f)
    for o in spills:
        o.data.energy=0 if f<=6 else 3*min(1,(f-6)/6);o.data.keyframe_insert('energy',frame=f)
for o in capillaries:
    for f,hide in ((1,False),(33,False),(34,True),(36,True)):
        o.hide_render=o.hide_viewport=hide
        o.keyframe_insert('hide_render',frame=f);o.keyframe_insert('hide_viewport',frame=f)
# Only the white orbs remain in the final two blown-out frames; remove
# geometry engulfed by their expansion rather than allowing shadow artifacts.
for o in list(scene.objects):
    if o.type not in ('MESH','CURVE','LIGHT') or o in orbs or o in capillaries:continue
    for f,hide in ((1,False),(34,False),(35,True),(36,True)):
        o.hide_render=o.hide_viewport=hide
        o.keyframe_insert('hide_render',frame=f);o.keyframe_insert('hide_viewport',frame=f)
# Constant rig curves make the two-frame holds unambiguous in the saved animation.
def constant_keys(obj):
    if not obj.animation_data or not obj.animation_data.action:return
    a=obj.animation_data.action
    if hasattr(a,'fcurves'):curves=a.fcurves
    else:curves=[fc for layer in a.layers for strip in layer.strips for bag in strip.channelbags for fc in bag.fcurves]
    for fc in curves:
        for k in fc.keyframe_points:k.interpolation='CONSTANT'
constant_keys(rig)
scene.use_nodes=True
if hasattr(scene,'compositing_node_group'):
    tree=bpy.data.node_groups.new('Cold white bloom','CompositorNodeTree');scene.compositing_node_group=tree
    tree.interface.new_socket(name='Image',in_out='OUTPUT',socket_type='NodeSocketColor')
else:tree=scene.node_tree
n,l=tree.nodes,tree.links;n.clear();rl=n.new('CompositorNodeRLayers');gl=n.new('CompositorNodeGlare')
if hasattr(gl,'glare_type'):
    gl.glare_type='FOG_GLOW';gl.quality='HIGH';gl.threshold=.8;gl.size=8
else:
    gl.inputs['Type'].default_value='Fog Glow';gl.inputs['Quality'].default_value='High';gl.inputs['Threshold'].default_value=.8;gl.inputs['Size'].default_value=.22
l.new(rl.outputs['Image'],gl.inputs['Image']);comp=n.new('NodeGroupOutput' if hasattr(scene,'compositing_node_group') else 'CompositorNodeComposite');l.new(gl.outputs['Image'],comp.inputs['Image'])
scene.frame_set(26)
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'blend/Level2_ShadeFace.blend'))
arrays=[]
for f in render_frames:
    scene.frame_set(f);path=OUT/'frames'/f'face_{f:02d}.png';scene.render.filepath=str(path)
    bpy.ops.render.render(write_still=True)
    im=bpy.data.images.load(str(path),check_existing=False);im.scale(340,340)
    arr=np.array(im.pixels[:],dtype=np.float32).reshape(340,340,4)
    if f<=30 or f==36:
        yy,xx=np.mgrid[-1:1:340j,-1:1:340j];radius=np.sqrt(xx*xx+yy*yy)
        edge=np.clip(((1.40 if f==36 else 1.30)-radius)/(.26 if f==36 else .32),0,1);edge=edge*edge*(3-2*edge)
        arr[:,:,:3]*=edge[:,:,None]
    im.pixels.foreach_set(arr.ravel());im.file_format='PNG';im.filepath_raw=str(path);im.save()
    assert tuple(im.size)==(340,340)
    if f<=30:assert max(arr[0,0,:3].max(),arr[0,-1,:3].max(),arr[-1,0,:3].max(),arr[-1,-1,:3].max())<.00182,(f,'corners not black')
    arrays.append(arr);bpy.data.images.remove(im)
    print(f'FACE FRAME {f}/36 COMPLETE',flush=True)
if preview:print('PREVIEW COMPLETE',flush=True);sys.exit(0)
def save_grid(name,items,grid,fmt):
    canvas=np.zeros((340*grid,340*grid,4),np.float32);canvas[:,:,3]=1
    for i,a in enumerate(items):
        row,col=divmod(i,grid);canvas[(grid-1-row)*340:(grid-row)*340,col*340:(col+1)*340]=a
    im=bpy.data.images.new(name,width=340*grid,height=340*grid,alpha=False)
    im.pixels.foreach_set(canvas.ravel());im.file_format=fmt;im.filepath_raw=str(OUT/name);im.save()
    assert tuple(im.size)==(340*grid,340*grid);bpy.data.images.remove(im)
sheets=[]
for i in range(4):
    name=f'face_sheet_{i+1}.png';save_grid('sheets/'+name,arrays[i*9:i*9+9],3,'PNG');sheets.append(name)
save_grid('preview/contact.jpg',arrays,6,'JPEG')
# Side-by-side frame 26: original supplied contact cell, then the rebuilt face.
reference=ROOT.parent/'stayquiet-l2-shade/briefs/contact_pass1.jpg'
if reference.exists():
    im=bpy.data.images.load(str(reference),check_existing=False);im.scale(2040,2040)
    old=np.array(im.pixels[:],dtype=np.float32).reshape(2040,2040,4)[340:680,340:680].copy()
    bpy.data.images.remove(im)
    im=bpy.data.images.new('Frame26 comparison',width=680,height=340,alpha=False)
    im.pixels.foreach_set(np.concatenate([old,arrays[25]],axis=1).ravel());im.file_format='JPEG';im.filepath_raw=str(OUT/'preview/frame26_comparison.jpg');im.save();bpy.data.images.remove(im)
ffmpeg=shutil.which('ffmpeg') or '/opt/homebrew/bin/ffmpeg'
gif=subprocess.run([ffmpeg,'-y','-framerate','12','-i',str(OUT/'frames/face_%02d.png'),'-filter_complex','[0:v]split[a][b];[a]palettegen=stats_mode=full[p];[b][p]paletteuse=dither=sierra2_4a','-loop','0','-f','gif','pipe:1'],check=True,stdout=subprocess.PIPE)
(OUT/'preview/face.gif').write_bytes(gif.stdout)
manifest={'frames':36,'fps':12,'grid':3,'frame':340,'sheets':sheets,'sha1':{s:hashlib.sha1((OUT/'sheets'/s).read_bytes()).hexdigest() for s in sheets}}
(OUT/'face.json').write_text(json.dumps(manifest,indent=2)+'\n')
for folder,names,size in [('frames',[f'face_{f:02d}.png' for f in range(1,37)],340),('sheets',sheets,1020)]:
    for name in names:
        data=(OUT/folder/name).read_bytes();width,height,depth,color,*_=struct.unpack('>IIBBBBB',data[16:29])
        assert (width,height,depth,color)==(size,size,8,2),(name,'PNG must be 8-bit RGB')
assert len(list((OUT/'frames').glob('face_*.png')))==36
assert len(list((OUT/'sheets').glob('face_sheet_*.png')))==4
print('FACE BUILD VERIFIED',flush=True)
