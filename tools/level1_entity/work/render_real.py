"""Render a clip on the Entity's REAL body (input/mesh.json, read from Studio by export_mesh.py), offline.

    Blender -b --python work/render_real.py -- --clip Run [--clips out/clips.json] [--tag v2] [--phases 12]
                                               [--views side,threequarter,front] [--video] [--size 480]

Why: the first motion pass was approved on a capsule figure and its run turned out, on the real body, to be the walk
folded double. The body is a bulky hunched suit with heavy boots; a capsule figure says nothing about how it reads.
This skins the game's own mesh with the clip's poses (linear blend, the four weights the mesh carries), on the measured
rig, and renders contact sheets (phases side by side) and, with --video, two cycles over a floor whose stripes pass at
the clip's own speed, so a sliding foot shows.

Out: artifacts/level1-entity-anim-20261010/real/<tag>_<Clip>_<view>.jpg (sheet) and .mp4 (video).
"""
import sys, json, math, argparse, subprocess, tempfile, shutil
sys.dont_write_bytecode = True
from pathlib import Path
import numpy as np
import bpy

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
import build_clips as bc
from rig_math import Rig

OUT = ROOT.parents[1] / 'artifacts' / 'level1-entity-anim-20261010' / 'real'
FLOOR_UP = 8.0


def to_blender(points):
    """Roblox root space (Y up, forward -Z) -> Blender (Z up, forward +Y)."""
    return np.stack([points[:, 0], -points[:, 2], points[:, 1]], axis=1)


def load_body(rig):
    mesh = json.loads((ROOT / 'input' / 'mesh.json').read_text())
    size = [float(x) for x in mesh['head'].split()[1].split(',')]
    part = [float(x) for x in mesh['head'].split()[3].split(',')]
    scale = part[1] / size[1]
    verts = np.array(mesh['verts'], float).reshape(-1, 11)
    positions = verts[:, :3] / 10000 * scale
    bones = verts[:, 3:7].astype(int)
    weights = verts[:, 7:11] / 1000
    weights[bones < 0] = 0
    bones[bones < 0] = 0
    weights /= np.maximum(weights.sum(axis=1, keepdims=True), 1e-9)
    inverse_bind, names = [], mesh['bones']
    for comps in mesh['bone_cframes']:
        m = np.eye(4)
        m[:3, 3] = np.array(comps[:3]) * scale
        m[:3, :3] = np.array(comps[3:]).reshape(3, 3)
        inverse_bind.append(np.linalg.inv(m))
    inverse_bind = np.array(inverse_bind)
    # the mesh's own bind pose against the measured rig: every bone must give the same mesh-to-root transform
    spread = [rig.rest_world[n] @ inverse_bind[i] for i, n in enumerate(names) if n in rig.rest_world]
    worst = max(float(np.abs(t - spread[0]).max()) for t in spread)
    tris = np.array(mesh['tris'], int).reshape(-1, 3)
    return dict(positions=np.concatenate([positions, np.ones((len(positions), 1))], axis=1), bones=bones, weights=weights,
                inverse_bind=inverse_bind, names=names, tris=tris, bind_spread=worst)


def skin(body, world):
    matrices = np.array([world[n] @ body['inverse_bind'][i] if n in world else np.eye(4) for i, n in enumerate(body['names'])])
    out = np.zeros((len(body['positions']), 3))
    for k in range(4):
        moved = np.einsum('nij,nj->ni', matrices[body['bones'][:, k]], body['positions'])[:, :3]
        out += body['weights'][:, k:k + 1] * moved
    return to_blender(out)


def scene(size, dark=False):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    for engine in ('BLENDER_EEVEE_NEXT', 'BLENDER_EEVEE'):
        try:
            sc.render.engine = engine
            break
        except TypeError:
            continue
    sc.render.resolution_x = sc.render.resolution_y = size
    sc.render.image_settings.file_format = 'PNG'
    sc.render.film_transparent = False
    world = bpy.data.worlds.new('w'); sc.world = world; world.use_nodes = True
    world.node_tree.nodes['Background'].inputs[0].default_value = (0.62, 0.64, 0.66, 1)
    world.node_tree.nodes['Background'].inputs[1].default_value = 0.45

    def material(name, colour, rough=0.6):
        m = bpy.data.materials.new(name); m.use_nodes = True
        b = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
        b.inputs['Base Color'].default_value = (*colour, 1); b.inputs['Roughness'].default_value = rough
        return m
    floor = bpy.data.meshes.new('floor')
    floor.from_pydata([(-60, -60, -FLOOR_UP), (60, -60, -FLOOR_UP), (60, 60, -FLOOR_UP), (-60, 60, -FLOOR_UP)], [], [(0, 1, 2, 3)])
    fo = bpy.data.objects.new('floor', floor); sc.collection.objects.link(fo); fo.data.materials.append(material('floor', (0.42, 0.43, 0.44), 0.9))
    stripes = bpy.data.objects.new('stripes', None); sc.collection.objects.link(stripes)
    stripe = material('stripe', (0.12, 0.12, 0.13), 0.9)
    for i in range(-14, 15):
        m = bpy.data.meshes.new('s'); y = i * 4.0; z = -FLOOR_UP + 0.01
        m.from_pydata([(-60, y - 0.12, z), (60, y - 0.12, z), (60, y + 0.12, z), (-60, y + 0.12, z)], [], [(0, 1, 2, 3)])
        o = bpy.data.objects.new('s', m); o.parent = stripes; sc.collection.objects.link(o); o.data.materials.append(stripe)
    sun = bpy.data.objects.new('sun', bpy.data.lights.new('sun', 'SUN')); sun.data.energy = 4.5; sun.data.angle = math.radians(8)
    sun.rotation_euler = (math.radians(52), 0, math.radians(-35)); sc.collection.objects.link(sun)
    fill = bpy.data.objects.new('fill', bpy.data.lights.new('fill', 'SUN')); fill.data.energy = 0.7
    fill.rotation_euler = (math.radians(65), 0, math.radians(140)); sc.collection.objects.link(fill)
    camera = bpy.data.objects.new('cam', bpy.data.cameras.new('cam')); sc.collection.objects.link(camera); sc.camera = camera
    suit = material('suit', (0.52, 0.47, 0.16), 0.55)
    if dark:
        # Level 1 as the hunted player has it: a dim yellow room lit from behind the Entity, the Entity a black shape
        world.node_tree.nodes['Background'].inputs[0].default_value = (0.20, 0.15, 0.05, 1)
        world.node_tree.nodes['Background'].inputs[1].default_value = 0.12
        suit = material('suit', (0.004, 0.004, 0.004), 0.9)
        fo.data.materials[0] = material('carpet', (0.20, 0.15, 0.06), 0.95)
        sun.data.energy = 0.0; fill.data.energy = 0.0
        wall = bpy.data.meshes.new('wall')
        wall.from_pydata([(-70, -60, -FLOOR_UP), (70, -60, -FLOOR_UP), (70, -60, -FLOOR_UP + 14), (-70, -60, -FLOOR_UP + 14)], [], [(0, 1, 2, 3)])
        wo = bpy.data.objects.new('wall', wall); sc.collection.objects.link(wo)
        glow = bpy.data.materials.new('glow'); glow.use_nodes = True
        e = next(n for n in glow.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
        e.inputs['Base Color'].default_value = (0.9, 0.7, 0.2, 1)
        e.inputs['Emission Color'].default_value = (0.95, 0.72, 0.22, 1); e.inputs['Emission Strength'].default_value = 2.2
        wo.data.materials.append(glow)
        lamp = bpy.data.objects.new('lamp', bpy.data.lights.new('lamp', 'AREA')); lamp.data.energy = 26000; lamp.data.size = 30
        lamp.data.color = (1.0, 0.8, 0.35); lamp.location = (0, -30, -FLOOR_UP + 13); lamp.rotation_euler = (0, 0, 0)
        sc.collection.objects.link(lamp)
    return sc, stripes, camera, suit


def aim(camera, view, distance=None):
    from mathutils import Vector
    target = Vector((0, 0.4, -FLOOR_UP + 4.6))
    cam = camera.data
    if view == 'side':            # from the body's right, flat on
        cam.type = 'ORTHO'; cam.ortho_scale = 15.5
        camera.location = target + Vector((40, 0, 0.6))
    elif view == 'front':
        cam.type = 'ORTHO'; cam.ortho_scale = 15.5
        camera.location = target + Vector((0, 40, 0.6))
    elif view == 'player':        # what the hunted player sees: eye height, dead ahead, the game's 70-degree lens
        cam.type = 'PERSP'; cam.sensor_fit = 'VERTICAL'; cam.angle_y = math.radians(70 if distance is None else 34)
        eye = Vector((0, 15 if distance is None else distance, -FLOOR_UP + 4.6))
        camera.location = eye
        camera.rotation_euler = (Vector((0, 0, -FLOOR_UP + 4.6)) - eye).to_track_quat('-Z', 'Y').to_euler()
        return
    else:                         # three-quarter from the front, at a player's eye height
        cam.type = 'PERSP'; cam.lens = 58
        camera.location = target + Vector((15, 24, 0.9))
    camera.rotation_euler = (target - camera.location).to_track_quat('-Z', 'Y').to_euler()


def aim_victim(camera,grip,head,eyes):
    from mathutils import Vector
    eye=to_blender(bc.victim_eye(grip,head)[None,:])[0]
    target=to_blender(np.asarray(eyes)[None,:])[0]
    camera.data.type='PERSP';camera.data.sensor_fit='VERTICAL';camera.data.angle_y=math.radians(70)
    camera.location=eye
    camera.rotation_euler=(Vector(target)-Vector(eye)).to_track_quat('-Z','Y').to_euler()


def make_victim(sc):
    def material(name,colour):
        m=bpy.data.materials.new(name);m.use_nodes=True
        node=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
        node.inputs['Base Color'].default_value=(*colour,1);node.inputs['Roughness'].default_value=.85
        return m
    mats=[material('Victim teal',(.08,.45,.53)),material('Throat contact',(.95,.37,.08)),material('Victim head',(.10,.16,.24))]
    result=[]
    for name,centre,size in bc.victim_blocks():
        bpy.ops.mesh.primitive_cube_add(size=1)
        obj=bpy.context.object;obj.name='Victim_'+name;obj.scale=(size[0],size[2],size[1])
        obj.data.materials.append(mats[1 if name=='neck' else 2 if name=='head' else 0])
        result.append((obj,np.array(centre)))
    return result


def make_eyes(sc):
    # mesh.json carries neither UVs nor the game's face texture. Small emissive
    # markers on two measured visor samples stand in for its two yellow eyes.
    mat=bpy.data.materials.new('Yellow eyes - texture placement reference');mat.use_nodes=True
    node=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    node.inputs['Base Color'].default_value=(1,.75,.01,1)
    node.inputs['Emission Color'].default_value=(1,.73,.015,1);node.inputs['Emission Strength'].default_value=5
    eyes=[]
    for i in range(2):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=12,ring_count=8,radius=.11)
        obj=bpy.context.object;obj.name=f'Measured_yellow_eye_{i}';obj.data.materials.append(mat);eyes.append(obj)
    return eyes


def main():
    global OUT
    parser = argparse.ArgumentParser()
    parser.add_argument('--clip', default='Run'); parser.add_argument('--clips', default=str(ROOT / 'out' / 'clips.json'))
    parser.add_argument('--tag', default='now'); parser.add_argument('--phases', type=int, default=12)
    parser.add_argument('--views', default='side,threequarter'); parser.add_argument('--video', action='store_true')
    parser.add_argument('--size', type=int, default=480)
    parser.add_argument('--out', default=str(OUT))
    parser.add_argument('--dark', action='store_true', help='the Entity black against a lit yellow room, as in Level 1')
    parser.add_argument('--approach', action='store_true', help='video: it runs at the camera from 95 studs to 12 instead of on the spot')
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
    OUT = Path(args.out)
    rig = Rig(ROOT / 'input' / 'rig.json'); bc.RIG = rig
    data = json.loads(Path(args.clips).read_text())[args.clip]
    poses = bc.decode_export(data)
    body = load_body(rig)
    print(f'BODY {len(body["positions"])} vertices; bind pose against the rig: worst matrix difference {body["bind_spread"]:.4f}', flush=True)
    sc, stripes, camera, suit = scene(args.size, args.dark)
    mesh = bpy.data.meshes.new('entity')
    first = skin(body, rig.fk(poses[0]))
    mesh.from_pydata(first.tolist(), [], body['tris'].tolist())
    for polygon in mesh.polygons: polygon.use_smooth = True
    obj = bpy.data.objects.new('entity', mesh); sc.collection.objects.link(obj); obj.data.materials.append(suit)
    OUT.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='stayquiet-kill-render-',dir='/tmp'))
    frames = data['frames']; seconds = frames / data['fps']; speed = data.get('speed', 0) if data.get('loop') else 0
    tracks={k:np.array(v).reshape(-1,3)/1000 for k,v in data.get('tracks',{}).items()}
    victim=make_victim(sc) if args.clip=='Kill_Choke' else []
    eyes=make_eyes(sc) if args.clip=='Kill_Choke' else []
    current_view='side'
    # Sheet labels are outside each 480px render, preserving the contact pixels.
    def labelled(path,text):
        result=bpy.data.images.load(str(path),check_existing=False)
        pixels=np.empty(args.size*args.size*4,dtype=np.float32);result.pixels.foreach_get(pixels)
        pixels=pixels.reshape(args.size,args.size,4)
        tile=np.empty((args.size+44,args.size,4),np.float32);tile[44:]=pixels
        from preview import _bitmap_labels
        _bitmap_labels(tile,args.clip+' '+current_view,text)
        dst=bpy.data.images.new('labelled',args.size,args.size+44,alpha=True);dst.pixels.foreach_set(tile.ravel())
        dst.filepath_raw=str(path);dst.file_format='PNG';dst.save()
        bpy.data.images.remove(dst);bpy.data.images.remove(result)

    def pose_at(index, travelled, advance=None):
        index=index%frames;world=rig.fk(poses[index]);points = skin(body,world)
        if advance is not None:
            points[:, 1] += advance          # it really comes closer; the floor stays where it is
            stripes.location = (0, 0, 0)
        else:
            stripes.location = (0, -(travelled % 4.0), 0)   # the floor passes under a body that runs on the spot
        mesh.vertices.foreach_set('co', points.ravel())
        mesh.update()
        if tracks:
            grip,head,eye=[tracks[k][index] for k in ['grip','head','eyes']]
            t=index/(frames-1)*seconds
            if current_view=='victim':aim_victim(camera,grip,head,eye)
            if current_view=='grip':
                from mathutils import Vector
                target=Vector(to_blender(grip[None,:])[0]);camera.data.type='ORTHO';camera.data.ortho_scale=4.5
                camera.location=target+Vector((40,6,1))
                camera.rotation_euler=(target-Vector(camera.location)).to_track_quat('-Z','Y').to_euler()
            hung=grip.copy() if t>=data['marks']['grab'] else np.array([0,-3.9,-3.7])
            if t>=data['marks']['release']:
                j=round(data['marks']['release']/seconds*(frames-1));hung=tracks['grip'][j].copy()
                hung[1]=max(-3.9,hung[1]-16*(t-data['marks']['release'])**2)
            basis=bc.victim_basis(hung,head)
            from mathutils import Matrix
            conversion=np.array([[1,0,0],[0,0,-1],[0,1,0]])
            for obj,offset in victim:
                obj.hide_render=current_view not in ['side','threequarter','grip']
                obj.location=to_blender((hung+basis@offset)[None,:])[0]
                obj.rotation_euler=Matrix((conversion@basis@conversion.T).tolist()).to_euler()
            for obj,offset in zip(eyes,bc.CHOKE_EYE_SAMPLES):
                p=world['Head'][:3,3]+world['Head'][:3,:3]@(offset+np.array([0,.055,0]))
                obj.location=to_blender(p[None,:])[0]

    def render_at(index,path):
        t=index/(frames-1)*seconds if not data.get('loop') else index/data['fps']
        sc.render.filepath=str(path)
        if current_view=='victim' and t>=data['marks']['dark']-seconds/(frames-1)*.5:
            im=bpy.data.images.new('black',args.size,args.size,alpha=True)
            px=np.zeros((args.size*args.size,4),np.float32);px[:,3]=1;im.pixels.foreach_set(px.ravel())
            im.filepath_raw=str(path);im.file_format='PNG';im.save();bpy.data.images.remove(im)
        else:bpy.ops.render.render(write_still=True)

    for view in args.views.split(','):
        current_view=view
        aim(camera, view)
        files = []
        samples=[(round(k*(frames-1)/(args.phases-1)),None) for k in range(args.phases)] if not data.get('loop') else [(round(k*frames/args.phases)%frames,None) for k in range(args.phases)]
        samples += [(round(t/seconds*(frames-1)),mark) for mark,t in data.get('marks',{}).items()]
        for k,(index,mark) in enumerate(samples):
            pose_at(index, speed * index / data['fps'])
            path = work / f'{args.tag}_{args.clip}_{view}_{k:02d}.png'
            render_at(index,path)
            labelled(path,f'F{index} T={index/(frames-1)*seconds:.3f} '+(mark or ''))
            files.append(path)
        columns = min(len(samples), 4); rows = math.ceil(len(samples) / columns)
        sheet = OUT / f'{args.tag}_{args.clip}_{view}.jpg'
        sheet.unlink(missing_ok=True)   # a sheet somebody has open cannot be overwritten in place
        subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-framerate', '1', '-i', str(work / f'{args.tag}_{args.clip}_{view}_%02d.png'),
                        '-vf', f'tile={columns}x{rows}', '-frames:v', '1', '-q:v', '3', str(sheet)], check=True)
        print('SHEET', sheet, flush=True)
        if args.video and view!='grip':
            fps = 30; total = int(round(2 * seconds * fps)) if data.get('loop') else int(round(seconds * fps))
            approach = args.approach and view == 'player' and speed > 0
            if approach:
                aim(camera, view, 95.0); total = int((95.0 - 12.0) / speed * fps)
            for f in range(total):
                t = f / fps
                index=int(round(t*data['fps'])) if data.get('loop') else min(frames-1,round(t/seconds*(frames-1)))
                pose_at(index, speed * t,
                        speed * t if approach else None)
                render_at(index,work / f'{args.tag}_{args.clip}_{view}_v{f:03d}.png')
            video = OUT / f'{args.tag}_{args.clip}_{view}.mp4'
            video.unlink(missing_ok=True)
            subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-framerate', str(fps), '-i',
                            str(work / f'{args.tag}_{args.clip}_{view}_v%03d.png'), '-pix_fmt', 'yuv420p', '-crf', '20', str(video)], check=True)
            print('VIDEO', video, flush=True)
    shutil.rmtree(work)


if __name__ == '__main__':
    main()
