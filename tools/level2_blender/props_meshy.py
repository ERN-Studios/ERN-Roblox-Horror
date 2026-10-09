"""Job D: Meshy atlases -> Level 2 kit components, entirely in headless Blender.

Run: D:/Blender/blender.exe -b --factory-startup --python-exit-code 1
     -P G:/Roblox/MongoTV/tools/level2_blender/props_meshy.py --
Optional --only bench lockers limits both build and review to those names.
build() registers components without changing another builder's scene or export path.
Canonical/decimation/texture helpers adapted from the proven Level 4 importer;
there is deliberately no runtime dependency on Level 4.
"""
from pathlib import Path
import argparse
import base64
import hashlib
import json
import math
import sys

sys.dont_write_bytecode = True

import bpy
import bmesh
import numpy as np
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import kit

SOURCE = Path('G:/Roblox/_local/l2blender/meshy')
TEXTURES = kit.KIT_DIR / 'textures' / 'props'
REVIEW = kit.KIT_DIR / 'review' / 'D'
EXPORT = kit.KIT_DIR / 'jobs' / 'D' / 'export'
# Meshy's glTF front +Z imports as Blender -Y. Roblox -Z is Blender +Y.
# Per-prop corrections live here, leaving the shared spec untouched.
YAW = {}


def coordinates(mesh):
    a = np.empty(len(mesh.vertices) * 3, dtype=np.float64)
    mesh.vertices.foreach_get('co', a)
    return a.reshape(-1, 3)


def triangle_count(mesh):
    mesh.calc_loop_triangles()
    return len(mesh.loop_triangles)


def min_area_yaw(points):
    xy = points[:, :2]
    best, angle = None, 0.0
    for a in sorted(np.arange(-44.75, 45.125, .25), key=abs):
        c, s = math.cos(math.radians(a)), math.sin(math.radians(a))
        x, y = xy[:, 0] * c - xy[:, 1] * s, xy[:, 0] * s + xy[:, 1] * c
        area = np.ptp(x) * np.ptp(y)
        if best is None or area < best * .999:
            best, angle = area, float(a)
    return angle


def canonical(mesh, spec, yaw=0):
    """Bake yaw, fit specified axes exactly; free axes keep uniform proportion.

    Wall back is Blender y=0 / Roblox z=0; its entire depth is in front of that
    plane. Non-wall footprints are centred. All pivots have bottom z=0.
    """
    mesh.transform(Matrix.Rotation(math.radians(yaw), 4, 'Z'))
    v = coordinates(mesh)
    lo, hi = v.min(0), v.max(0)
    dims = [spec['dims'][i] for i in (0, 2, 1)]
    factors = np.array([d * kit.S / s if d is not None else np.nan
                        for d, s in zip(dims, np.maximum(hi - lo, 1e-9))])
    assert not np.isnan(factors).all(), 'At least one target dimension is required'
    factors = np.where(np.isnan(factors), np.nanmin(factors), factors)
    pivot = np.array([(lo[0] + hi[0]) / 2,
                      lo[1] if spec.get('wall') else (lo[1] + hi[1]) / 2, lo[2]])
    transform = np.diag([*factors, 1.0])
    transform[:3, 3] = -pivot * factors
    mesh.transform(Matrix(transform.tolist()))
    mesh.update()


def principled(material):
    return next((n for n in material.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None) \
        if material and material.use_nodes else None


def source(socket):
    """Trace normal-map and glTF Separate Color nodes; retain MR channel."""
    channel, visited = None, set()
    while socket.is_linked:
        link = socket.links[0]
        node = link.from_node
        channel = {'Red': 0, 'Green': 1, 'Blue': 2}.get(link.from_socket.name, channel)
        if node.type == 'TEX_IMAGE':
            return node.image, channel
        if node.as_pointer() in visited:
            break
        visited.add(node.as_pointer())
        linked = [i for i in node.inputs if i.is_linked]
        if not linked:
            break
        socket = linked[0]
    return None, None


def pixels(image, size):
    image = image.copy()
    image.scale(size, size)
    a = np.empty(size * size * 4, dtype=np.float32)
    image.pixels.foreach_get(a)
    bpy.data.images.remove(image)
    return a.reshape(size, size, 4)


def save_pixels(a, path, data=False):
    h, w = a.shape[:2]
    image = bpy.data.images.new(path.name, w, h, alpha=False)
    image.colorspace_settings.name = 'Non-Color' if data else 'sRGB'
    rgba = np.ones((h, w, 4), dtype=np.float32)
    rgba[..., :3] = a[..., :3] if a.ndim == 3 else a[..., None]
    image.pixels.foreach_set(rgba.ravel())
    image.filepath_raw, image.file_format = str(path), 'PNG'
    image.save()
    bpy.data.images.remove(image)
    return str(path)


def atlas(name, mesh, spec):
    mats = [m for m in mesh.materials if principled(m) and source(principled(m).inputs['Base Color'])[0]]
    assert len(mats) == 1, f'{name}: expected one textured atlas, got {len(mats)}'
    b, size = principled(mats[0]), spec['tex']
    maps, statistics = {}, {}
    TEXTURES.mkdir(parents=True, exist_ok=True)
    for kind, socket in [('albedo', 'Base Color'), ('normal', 'Normal'),
                         ('rough', 'Roughness'), ('metal', 'Metallic')]:
        image, channel = source(b.inputs[socket])
        if image:
            a = pixels(image, size)
            if kind in ('rough', 'metal'):
                a = a[..., channel if channel is not None else 0]
        elif kind == 'normal':
            a = np.broadcast_to((.5, .5, 1.), (size, size, 3))
        else:
            default = b.inputs[socket].default_value
            a = np.full((size, size), default, dtype=np.float32)
        statistics[kind] = [round(float(np.min(a)), 5), round(float(np.max(a)), 5)]
        if kind == 'metal' and float(np.max(a)) <= .04:
            # Remove only this prop's obsolete job output from an earlier run.
            (TEXTURES / f'{name}_metal.png').unlink(missing_ok=True)
            continue
        maps[kind] = save_pixels(a, TEXTURES / f'{name}_{kind}.png', kind != 'albedo')
    key = kit.atlas_material('Atlas_' + name, maps)
    mesh.materials.clear()
    mesh.materials.append(kit.MATERIALS[key]['blender'])
    mesh.polygons.foreach_set('material_index', np.zeros(len(mesh.polygons), dtype=np.int32))
    mesh.uv_layers.active_index = 0
    return maps, statistics


def import_prop(name, spec):
    path = SOURCE / name / (name + '.glb')
    if not path.is_file():
        print(f'SKIP Prop_{name}: missing GLB {path}', flush=True)
        return None
    before = {k: {x.as_pointer() for x in getattr(bpy.data, k)}
              for k in ('objects', 'meshes', 'materials', 'images')}
    bpy.ops.import_scene.gltf(filepath=str(path), merge_vertices=True)
    objects = [o for o in bpy.data.objects if o.as_pointer() not in before['objects']]
    meshes = [o for o in objects if o.type == 'MESH']
    assert meshes, f'{name}: GLB has no meshes'
    for o in meshes:
        if o.data.users > 1:
            o.data = o.data.copy()
        world = o.matrix_world.copy()
        o.parent = None
        o.data.transform(world)
        o.matrix_world = Matrix.Identity(4)
    for o in objects:
        if o.type != 'MESH':
            bpy.data.objects.remove(o, do_unlink=True)
    o = meshes[0]
    if len(meshes) > 1:
        with bpy.context.temp_override(object=o, active_object=o, selected_objects=meshes,
                                       selected_editable_objects=meshes):
            bpy.ops.object.join()
    initial = triangle_count(o.data)
    # glTF merge_vertices only merges vertices with identical split attributes.
    # Meshy often splits even flat triangles at normals/UV seams. Weld POSITION
    # here so decimation collapses a connected surface, instead of deleting
    # isolated triangles. BMesh loop UVs retain every atlas seam.
    vertices_before = len(o.data.vertices)
    weld = bmesh.new()
    weld.from_mesh(o.data)
    tolerance = max(float(np.ptp(coordinates(o.data), axis=0).max()) * 1e-6, 1e-9)
    bmesh.ops.remove_doubles(weld, verts=list(weld.verts), dist=tolerance)
    # Intersecting Meshy shells can share more than two faces on one edge after
    # welding. Separate those junctions; collapse cannot simplify nonmanifold fans.
    junctions = [e for e in weld.edges if len(e.link_faces) > 2]
    junction_count = len(junctions)
    if junctions:
        bmesh.ops.split_edges(weld, edges=junctions)
    bmesh.ops.recalc_face_normals(weld, faces=list(weld.faces))
    weld.to_mesh(o.data)
    weld.free()
    welded = vertices_before - len(o.data.vertices)
    yaw = min_area_yaw(coordinates(o.data)) + spec.get('yaw_deg', YAW.get(name, 180))
    canonical(o.data, spec, yaw)
    for attempt in range(5):
        n = triangle_count(o.data)
        if n <= spec['tris']:
            break
        modifier = o.modifiers.new('Prop simplify', 'DECIMATE')
        modifier.ratio = spec['tris'] / n * (.98 if attempt == 0 else .90)
        modifier.use_collapse_triangulate = True
        dg = bpy.context.evaluated_depsgraph_get()
        low = bpy.data.meshes.new_from_object(o.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
        o.modifiers.remove(modifier)
        old, o.data = o.data, low
        bpy.data.meshes.remove(old)
        o.data.update()
        print(f'DECIMATE {name}: {n} -> {triangle_count(low)}', flush=True)
    mesh = o.data
    assert triangle_count(mesh) <= spec['tris'], f'{name}: decimation missed budget'
    # Collapse may move the extrema slightly; restore exact final dimensions/pivot.
    canonical(mesh, spec)
    cn = mesh.attributes.get('custom_normal')
    if cn:
        mesh.attributes.remove(cn)
    if mesh.has_custom_normals:
        with bpy.context.temp_override(object=o, active_object=o, selected_editable_objects=[o]):
            bpy.ops.mesh.customdata_custom_splitnormals_clear()
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(mesh)
    bm.free()
    mesh.shade_smooth()
    mesh.set_sharp_from_angle(angle=math.radians(spec.get('sharp_angle', 40)))
    assert mesh.uv_layers, f'{name}: missing Meshy UVs'
    uv = np.array([loop.uv[:] for loop in mesh.uv_layers.active.data])
    assert np.isfinite(uv).all(), f'{name}: invalid UVs'
    maps, map_stats = atlas(name, mesh, spec)
    assert len(mesh.materials) == 1
    v = coordinates(mesh) @ kit.C.T / kit.S
    lo, hi = v.min(0), v.max(0)
    assert np.isfinite(v).all() and np.all(hi > lo)
    assert abs(lo[1]) < 1e-5 and abs(lo[0] + hi[0]) < 1e-5
    for i, d in enumerate(spec['dims']):
        if d is not None:
            assert abs((hi - lo)[i] - d) < 1e-4, (name, i, hi - lo)
    if spec.get('wall'):
        assert abs(hi[2]) < 1e-5 and lo[2] < 0, (name, lo, hi)
    else:
        assert abs(lo[2] + hi[2]) < 1e-5
    records = []
    if spec['collide']:
        # Ground stays false: these small/tall boxes do not meet the entity-ground
        # minimum 4-stud footprint and maximum 3-stud rise contract.
        records = [{'name': 'L2K ' + name + ' Collider', 'cf': [*((lo + hi) / 2).tolist(), 0],
                    'size': (hi - lo).tolist(), 'ground': False, 'shape': 'Block', 'attrs': {}}]
    component = 'Prop_' + name
    mesh.name, mesh.use_fake_user = 'L2K_' + component, True
    kit.register_mesh(component, mesh, colliders=records, Prop=name)
    bpy.data.objects.remove(o, do_unlink=True)
    for k in ('meshes', 'materials', 'images'):
        for x in list(getattr(bpy.data, k)):
            if x.as_pointer() not in before[k] and x.users == 0 and not x.use_fake_user:
                getattr(bpy.data, k).remove(x)
    result = {'name': component, 'source': str(path), 'sourceTris': initial,
              'sourceSha256': hashlib.sha256(path.read_bytes()).hexdigest(),
              'weldedDuplicateVertices': welded,
              'splitNonmanifoldJunctions': junction_count,
              'tris': triangle_count(mesh), 'budget': spec['tris'], 'tex': spec['tex'],
              'dimsStuds': (hi - lo).round(5).tolist(), 'yawBlenderDegrees': yaw,
              'wallBackRobloxZ': 0 if spec.get('wall') else None,
              'maps': maps, 'mapRange': map_stats, 'collider': records}
    if name in ('filter', 'lanereel'):
        result['reviewNote'] = 'Faceting also visible in the original Meshy GLB; source comparison rendered.'
    print('PROP ' + json.dumps(result), flush=True)
    return result


def build(names=None):
    """Register every available spec prop; skip downloads that are still missing."""
    assert bpy.app.background, 'Headless Blender only'
    specs = json.loads(Path(__file__).with_name('props_spec.json').read_text())
    if names:
        assert set(names) <= set(specs), 'Unknown prop name'
    return [r for name, spec in specs.items() if not name.startswith('_') and
            (not names or name in names) and (r := import_prop(name, spec)) is not None]


def review(results):
    """512px EEVEE reviews, each with a true 5-stud capsule; labelled 4-wide sheet."""
    REVIEW.mkdir(parents=True, exist_ok=True)
    previous_scene = bpy.context.window.scene
    scene = bpy.data.scenes.new('D Prop Review')
    bpy.context.window.scene = scene
    collection = scene.collection
    scene.render.engine = 'BLENDER_EEVEE'
    scene.eevee.taa_render_samples = 64
    scene.render.resolution_x = scene.render.resolution_y = 512
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.view_settings.view_transform = 'AgX'
    world = bpy.data.worlds.new('D Neutral World')
    world.use_nodes = True
    world.node_tree.nodes['Background'].inputs[0].default_value = (.32, .32, .32, 1)
    world.node_tree.nodes['Background'].inputs[1].default_value = .8
    scene.world = world
    grey = bpy.data.materials.new('D Review Grey')
    grey.diffuse_color = (.22, .22, .22, 1)
    bpy.ops.mesh.primitive_plane_add(size=200)
    floor = bpy.context.object
    floor.name = 'D Neutral Floor'
    floor.data.materials.append(grey)
    cam = bpy.data.objects.new('D Review Camera', bpy.data.cameras.new('D Review Camera'))
    collection.objects.link(cam)
    cam.data.type = 'ORTHO'
    scene.camera = cam
    for name, pos, power, size in [('Key', (3, 4, 7), 700, 5),
                                    ('Fill', (-4, 2, 4), 300, 4), ('Rim', (1, -4, 5), 500, 4)]:
        light = bpy.data.objects.new('D ' + name, bpy.data.lights.new('D ' + name, 'AREA'))
        collection.objects.link(light)
        light.location, light.data.energy, light.data.shape, light.data.size = pos, power, 'DISK', size
        light.rotation_euler = (-light.location).to_track_quat('-Z', 'Y').to_euler()
    caption_mat = bpy.data.materials.new('D Caption')
    caption_mat.use_nodes = True
    nt = caption_mat.node_tree
    nt.nodes.clear()
    emission, output = nt.nodes.new('ShaderNodeEmission'), nt.nodes.new('ShaderNodeOutputMaterial')
    emission.inputs['Color'].default_value = (.018, .018, .018, 1)
    nt.links.new(emission.outputs[0], output.inputs['Surface'])
    sheet_rows = math.ceil(len(results) / 4)
    sheet = np.ones((max(1, sheet_rows) * 512, 2048, 4), np.float32)
    for index, result in enumerate(results):
        o = kit.place(collection, result['name'])
        bounds = coordinates(o.data)
        lo, hi = bounds.min(0), bounds.max(0)
        # Capsule: radius .5 stud, four-stud body, total height exactly 5 studs.
        cx, cy, radius = hi[0] + 1.2 * kit.S, (lo[1] + hi[1]) / 2, .5 * kit.S
        capsule = []
        bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=radius, depth=4 * kit.S,
                                          location=(cx, cy, 2.5 * kit.S))
        capsule.append(bpy.context.object)
        for z in (.5 * kit.S, 4.5 * kit.S):
            bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, radius=radius, location=(cx, cy, z))
            capsule.append(bpy.context.object)
        for ob in capsule:
            ob.data.materials.append(grey)
            ob.data.shade_smooth()
        points = np.vstack([bounds, [(x, y, z) for x in (cx - radius, cx + radius)
                                     for y in (cy - radius, cy + radius) for z in (0, 5 * kit.S)]])
        target = Vector(((lo[0] + cx + radius) / 2, cy, max(hi[2], 5 * kit.S) / 2))
        cam.location = target + Vector((4, 6, 3))
        cam.rotation_euler = (target - cam.location).to_track_quat('-Z', 'Y').to_euler()
        projected = np.array([cam.rotation_euler.to_matrix().transposed() @ (Vector(p) - target) for p in points])
        cam.data.ortho_scale = max(np.ptp(projected[:, 0]), np.ptp(projected[:, 1])) * 1.45
        text = bpy.data.objects.new('D Label', bpy.data.curves.new('D Label', 'FONT'))
        collection.objects.link(text)
        text.data.body = result['name'] + f"  |  {result['tris']} tris\nGrey capsule: 5 studs"
        text.data.size = cam.data.ortho_scale * .027
        text.data.materials.append(caption_mat)
        text.parent = cam
        text.location = (-cam.data.ortho_scale * .46, -cam.data.ortho_scale * .44, -1)
        scene.render.filepath = str(REVIEW / (result['name'].removeprefix('Prop_') + '.png'))
        bpy.ops.render.render(write_still=True)
        im = bpy.data.images.load(scene.render.filepath, check_existing=False)
        a = np.empty(512 * 512 * 4, np.float32)
        im.pixels.foreach_get(a)
        bpy.data.images.remove(im)
        # Image pixels are bottom-up; arrange the spec's first row at the top.
        row = sheet_rows - 1 - index // 4
        sheet[row * 512:(row + 1) * 512, index % 4 * 512:(index % 4 + 1) * 512] = a.reshape(512, 512, 4)
        for ob in [o, text, *capsule]:
            bpy.data.objects.remove(ob, do_unlink=True)
    save_pixels(sheet, REVIEW / '_sheet.png')
    for ob in list(scene.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    bpy.context.window.scene = previous_scene
    bpy.data.scenes.remove(scene)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--only', nargs='+')
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
    bpy.ops.wm.read_factory_settings(use_empty=True)
    results = build(args.only)
    for r in results:
        print(f"{r['name']} / {r['tris']} tris / {r['tex']}px / {len(r['collider'])} collider", flush=True)
    kit.EXPORT_DIR = EXPORT
    manifest = kit.export()
    assert len(manifest['chunks']) == len(results), 'Exactly one chunk per prop'
    assert all(c['tris'] <= next(r['budget'] for r in results if r['name'] == c['component'])
               for c in manifest['chunks'])
    # Read the wire files back: verify hashes, serialized triangle counts, finite
    # coordinates/normals/UVs and every index, not just the in-memory Blender mesh.
    for chunk in manifest['chunks']:
        wire = (EXPORT / 'chunks' / ('c%05d.b64' % chunk['id'])).read_bytes()
        blob = base64.b64decode(wire, validate=True)
        assert hashlib.sha256(wire).hexdigest() == chunk['wireSha256']
        assert hashlib.sha256(blob).hexdigest() == chunk['sha256']
        nv, nn, nu, nt = map(int, np.frombuffer(blob, dtype='<u4', count=4))
        assert nt == chunk['tris'] and nv == chunk['verts']
        floats = 3 * nv + 3 * nn + 2 * nu
        arrays = np.frombuffer(blob, dtype='<f4', count=floats, offset=16)
        assert np.isfinite(arrays).all()
        faces = np.frombuffer(blob, dtype='<u4', offset=16 + 4 * floats).reshape(nt, 3, 3)
        for axis, limit in enumerate((nv, nn, nu)):
            assert faces[:, :, axis].max() < limit
        normals = arrays[3 * nv:3 * (nv + nn)].reshape(nn, 3)
        assert np.allclose(np.linalg.norm(normals, axis=1), 1, atol=.001)
    for r in results:
        for kind, path in r['maps'].items():
            im = bpy.data.images.load(path, check_existing=True)
            assert tuple(im.size) == (r['tex'], r['tex'])
    print('D_WIRE_CHECK_OK', flush=True)
    EXPORT.mkdir(parents=True, exist_ok=True)
    (EXPORT / 'props_report.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
    review(results)
    print('D_OK ' + str(EXPORT / 'manifest.json'), flush=True)
