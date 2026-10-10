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
import sys, json, math, argparse, subprocess
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


def scene(size):
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
    dark = material('stripe', (0.12, 0.12, 0.13), 0.9)
    for i in range(-14, 15):
        m = bpy.data.meshes.new('s'); y = i * 4.0; z = -FLOOR_UP + 0.01
        m.from_pydata([(-60, y - 0.12, z), (60, y - 0.12, z), (60, y + 0.12, z), (-60, y + 0.12, z)], [], [(0, 1, 2, 3)])
        o = bpy.data.objects.new('s', m); o.parent = stripes; sc.collection.objects.link(o); o.data.materials.append(dark)
    sun = bpy.data.objects.new('sun', bpy.data.lights.new('sun', 'SUN')); sun.data.energy = 4.5; sun.data.angle = math.radians(8)
    sun.rotation_euler = (math.radians(52), 0, math.radians(-35)); sc.collection.objects.link(sun)
    fill = bpy.data.objects.new('fill', bpy.data.lights.new('fill', 'SUN')); fill.data.energy = 0.7
    fill.rotation_euler = (math.radians(65), 0, math.radians(140)); sc.collection.objects.link(fill)
    camera = bpy.data.objects.new('cam', bpy.data.cameras.new('cam')); sc.collection.objects.link(camera); sc.camera = camera
    return sc, stripes, camera, material('suit', (0.52, 0.47, 0.16), 0.55)


def aim(camera, view):
    from mathutils import Vector
    target = Vector((0, 0.4, -FLOOR_UP + 4.6))
    cam = camera.data
    if view == 'side':            # from the body's right, flat on
        cam.type = 'ORTHO'; cam.ortho_scale = 15.5
        camera.location = target + Vector((40, 0, 0.6))
    elif view == 'front':
        cam.type = 'ORTHO'; cam.ortho_scale = 15.5
        camera.location = target + Vector((0, 40, 0.6))
    else:                         # three-quarter from the front, at a player's eye height
        cam.type = 'PERSP'; cam.lens = 58
        camera.location = target + Vector((15, 24, 0.9))
    camera.rotation_euler = (target - camera.location).to_track_quat('-Z', 'Y').to_euler()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--clip', default='Run'); parser.add_argument('--clips', default=str(ROOT / 'out' / 'clips.json'))
    parser.add_argument('--tag', default='now'); parser.add_argument('--phases', type=int, default=12)
    parser.add_argument('--views', default='side,threequarter'); parser.add_argument('--video', action='store_true')
    parser.add_argument('--size', type=int, default=480)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
    rig = Rig(ROOT / 'input' / 'rig.json'); bc.RIG = rig
    data = json.loads(Path(args.clips).read_text())[args.clip]
    poses = bc.decode_export(data)
    body = load_body(rig)
    print(f'BODY {len(body["positions"])} vertices; bind pose against the rig: worst matrix difference {body["bind_spread"]:.4f}', flush=True)
    sc, stripes, camera, suit = scene(args.size)
    mesh = bpy.data.meshes.new('entity')
    first = skin(body, rig.fk(poses[0]))
    mesh.from_pydata(first.tolist(), [], body['tris'].tolist())
    for polygon in mesh.polygons: polygon.use_smooth = True
    obj = bpy.data.objects.new('entity', mesh); sc.collection.objects.link(obj); obj.data.materials.append(suit)
    OUT.mkdir(parents=True, exist_ok=True)
    work = OUT / '_frames'; work.mkdir(exist_ok=True)
    frames = data['frames']; seconds = frames / data['fps']; speed = data.get('speed', 0) if data.get('loop') else 0

    def pose_at(index, travelled):
        mesh.vertices.foreach_set('co', skin(body, rig.fk(poses[index % frames])).ravel())
        mesh.update()
        stripes.location = (0, -(travelled % 4.0), 0)   # the floor passes under a body that runs on the spot

    for view in args.views.split(','):
        aim(camera, view)
        files = []
        for k in range(args.phases):
            index = round(k * frames / args.phases) % frames
            pose_at(index, speed * index / data['fps'])
            path = work / f'{args.tag}_{args.clip}_{view}_{k:02d}.png'
            sc.render.filepath = str(path); bpy.ops.render.render(write_still=True); files.append(path)
        columns = min(args.phases, 6); rows = math.ceil(args.phases / columns)
        sheet = OUT / f'{args.tag}_{args.clip}_{view}.jpg'
        sheet.unlink(missing_ok=True)   # a sheet somebody has open cannot be overwritten in place
        subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-framerate', '1', '-i', str(work / f'{args.tag}_{args.clip}_{view}_%02d.png'),
                        '-vf', f'tile={columns}x{rows}', '-frames:v', '1', '-q:v', '3', str(sheet)], check=True)
        print('SHEET', sheet, flush=True)
        if args.video:
            fps = 30; total = int(round(2 * seconds * fps)) if data.get('loop') else int(round(seconds * fps))
            for f in range(total):
                t = f / fps
                pose_at(int(round(t * data['fps'])) if data.get('loop') else min(frames - 1, int(round(t * data['fps']))), speed * t)
                sc.render.filepath = str(work / f'{args.tag}_{args.clip}_{view}_v{f:03d}.png'); bpy.ops.render.render(write_still=True)
            video = OUT / f'{args.tag}_{args.clip}_{view}.mp4'
            video.unlink(missing_ok=True)
            subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-stream_loop', '2', '-framerate', str(fps), '-i',
                            str(work / f'{args.tag}_{args.clip}_{view}_v%03d.png'), '-pix_fmt', 'yuv420p', '-crf', '20', str(video)], check=True)
            print('VIDEO', video, flush=True)
    for leftover in work.glob(f'{args.tag}_{args.clip}_*.png'): leftover.unlink()


if __name__ == '__main__':
    main()
