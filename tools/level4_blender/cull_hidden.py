"""Conservative post-build cull; run ONLY through the project's blrun.py.

  python blrun.py input.blend cull_hidden.py output.blend --report report.json
      --work-dir work --layout matching_layout.json --python python.exe
      --python-path path/to/embreex --views proof_views.json [--keep keep.json]

The input stays untouched. Visibility mode removes only unhit polygons whose
exact probes all fail. --mode enclosure adds the original convex burial gate.
Doors/gameplay/tags and uncertain geometry stay. Render proof is mandatory.
Proof rendering is a separate gate: use the P7 proof_hidden.py/proof_summary.py.
The ordinary Python worker requires numpy, scipy and embreex (no Blender process).
"""
import argparse
import collections
import hashlib
import json
import os
import re
from pathlib import Path
import subprocess
import sys
import time

import numpy as np


def json_write(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + '.tmp')
    tmp.write_text(json.dumps(value, indent=2), encoding='utf-8')
    os.replace(tmp, path)


def file_hash(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def l4_owned(obj):
    """Round contracts must survive geometry and cleanup nominations, including child meshes."""
    fields = ('l4_marker', 'l4_collision_only', 'l4_model_group', 'l4_model_tags', 'l4_model_attributes',
              'l4_attributes', 'l4_part_name', 'l4_pivot', 'l4_zone', 'L4Zone')
    current = obj
    while current is not None:
        data = getattr(current, 'data', None)
        if any(current.get(k) is not None or (data is not None and data.get(k) is not None) for k in fields):
            return True
        current = getattr(current, 'parent', None)
    return False


def material_transparent(mat):
    if mat is None:
        return False
    if (float(mat.get('l4_alpha', 1)) < .999999 or mat.diffuse_color[3] < .999999
            or mat.get('l4_sem') in ('glass', 'decal') or 'DECAL' in mat.name.upper()
            or mat.get('l4_roblox') == 'Glass'):
        return True
    if mat.use_nodes:
        for node in mat.node_tree.nodes:
            if node.type in ('BSDF_TRANSPARENT', 'BSDF_GLASS'):
                return True
            if node.type == 'BSDF_PRINCIPLED':
                if node.inputs['Alpha'].is_linked or node.inputs['Alpha'].default_value < .999999:
                    return True
                transmission = node.inputs.get('Transmission Weight') or node.inputs.get('Transmission')
                if transmission and (transmission.is_linked or transmission.default_value > 0):
                    return True
    return False


def convex_certificate(vertices, triangles, margin=1e-5):
    """Closed convex mesh only; its ORIGINAL surfaces will remain immutable.

    Bounds alone are insufficient (rooms, hollow props, bevels). Require every
    triangle edge twice, consistent outward halfspaces, and a nonzero volume.
    """
    if len(vertices) < 4 or len(vertices) > 64 or len(triangles) > 128:
        return None
    edge = np.sort(np.concatenate((triangles[:, [0, 1]], triangles[:, [1, 2]],
                                   triangles[:, [2, 0]])), axis=1)
    _, count = np.unique(edge, axis=0, return_counts=True)
    if not len(count) or np.any(count != 2):
        return None
    p = vertices[triangles]
    n = np.cross(p[:, 1] - p[:, 0], p[:, 2] - p[:, 0])
    size = np.linalg.norm(n, axis=1)
    if np.any(size < 1e-10):
        return None
    n /= size[:, None]
    centre = vertices.mean(0)
    d = np.einsum('ij,ij->i', n, p[:, 0])
    # Consistently reverse a negatively scaled mesh, but reject mixed winding.
    inward = n @ centre - d
    if np.all(inward > -margin):
        n, d = -n, -d
        inward = -inward
    if np.any(inward >= -margin) or np.any(vertices @ n.T - d > margin):
        return None
    return {'lo': vertices.min(0).tolist(), 'hi': vertices.max(0).tolist(),
            'planes': [{'n': a.tolist(), 'd': float(b)} for a, b in zip(n, d)]}


def load_exporter(here, layout, build_dir=None):
    # A private namespace suppresses export() and protects the running scene.
    path = here / 'export_l4.py'
    source = path.read_text(encoding='utf-8')
    ex = {'L4_EXPORT_NO_RUN': True, '__file__': str(path), 'L4_EXPORT_LAYOUT': str(layout)}
    if build_dir:
        ex['L4_EXPORT_BUILD_DIR'] = str(build_dir)
    exec(compile(source, str(path), 'exec'), ex)
    ex['LAYOUT'] = json.loads(Path(layout).read_text(encoding='utf-8'))
    return ex, hashlib.sha256(source.encode()).hexdigest()


def gather_colliders(objects, ex):
    """Match export_l4's layout filtering, coverage pruning and occluder rules."""
    base, scene_cols, all_scene = {}, [], []
    for obj in objects:
        if not obj.get('l4_door_leaf'):
            cols = ex['object_colliders'](obj)
            all_scene.extend(cols)
            scene_cols.extend(cols)
        if obj.get('l4_src') is not None and obj.get('l4_path'):
            i = int(obj['l4_src'])
            if i < len(ex['LAYOUT']['parts']) and ex['LAYOUT']['parts'][i]['p'] == obj['l4_path']:
                from mathutils import Vector
                bb = np.array([ex['studio_pos'](obj.matrix_world @ Vector(v)) for v in obj.bound_box])
                base[i] = (bb.min(0), bb.max(0))
    layout_cols, occluder_src, mismatches = [], set(), []
    for i, part in enumerate(ex['LAYOUT']['parts']):
        if part.get('removed') or not part['cc'] or ex['DOOR_PARTS'].search(part['p']):
            continue
        shape = part.get('sh') or ('Wedge' if part['c'] == 'WedgePart' else 'Block')
        if 'layout_occluder' not in ex:
            raise RuntimeError('Exporter must expose layout_occluder(p); reread the current exporter')
        occ = bool(ex['layout_occluder'](part))
        if occ:
            occluder_src.add(i)
        layout_cols.append((part['p'], {'cf': part['cf'], 's': part['s'], 'm': part['m'],
            'tags': list(part.get('tags') or []),
            'at': {k: v for k, v in (part.get('at') or {}).items()
                   if k not in ('OccasionalFlicker', 'AutoDoorLeaf')},
            'sh': shape, 'kind': 'Seat' if part['c'] == 'Seat' else 'Part',
            'occ': occ, '_protected': ex['protected'](part)}))
    rx, rep = ex['replaced_patterns']()
    replaced = lambda path: any(r.search(path) for r in rx) or bool(rep and rep.search(ex['key'](path)))
    kept, pruning = ex['prune_replaced'](layout_cols, scene_cols, replaced)
    for obj in objects:
        i = obj.get('l4_src')
        if i is not None and obj.get('l4_path'):
            if int(i) >= len(ex['LAYOUT']['parts']) or ex['LAYOUT']['parts'][int(i)]['p'] != obj['l4_path']:
                mismatches.append(obj.name)
    omitted = json.loads(ex['bpy'].context.scene.get('l4_culled_colliders', '[]'))
    def skipped(c):
        return any((x.get('path') == c.get('_path') and x.get('orig') == c['cf'][:3])
                   if 'path' in x else (x.get('src') == c.get('src') and x.get('cf') == c['cf'] and x.get('s') == c['s'])
                   for x in omitted)
    for path, c in layout_cols:
        c['_path'] = path
    return [c for c in kept + all_scene if not skipped(c)], occluder_src, pruning, mismatches


def scene_counts(root, ex):
    result = {'objects': len(root.all_objects), 'meshes': 0, 'lights': 0,
              'triangles_placed': 0, 'triangles_unique': 0, 'colliders_scene': 0,
              'per_collection': {}}
    seen = set()
    omitted = json.loads(ex['bpy'].context.scene.get('l4_culled_colliders', '[]'))
    dg = ex['bpy'].context.evaluated_depsgraph_get()
    visible = {o.name for o in ex['visible_meshes']()}
    for obj in sorted(root.all_objects, key=lambda o: o.name):
        key = obj.users_collection[0].name if obj.users_collection else 'None'
        col = result['per_collection'].setdefault(key, {'objects': 0, 'triangles': 0, 'lights': 0, 'colliders': 0})
        col['objects'] += 1
        if obj.type == 'LIGHT':
            result['lights'] += 1
            col['lights'] += 1
        if obj.name not in visible:
            continue
        me, ev = ex['mesh_of'](obj, dg)
        me.calc_loop_triangles()
        n = len(me.loop_triangles)
        result['meshes'] += 1
        result['triangles_placed'] += n
        col['triangles'] += n
        unique = (obj.data.as_pointer(), tuple((m.type, m.show_render) for m in obj.modifiers))
        if unique not in seen:
            result['triangles_unique'] += n
            seen.add(unique)
        if ev:
            ev.to_mesh_clear()
        c = sum(not any(x.get('src') == box.get('src') and x.get('cf') == box['cf'] and x.get('s') == box['s']
                        for x in omitted if 'src' in x) for box in ex['object_colliders'](obj)) if not obj.get('l4_door_leaf') else 0
        result['colliders_scene'] += c
        col['colliders'] += c
    return result


def export_worker_scene(work, ex, args):
    import bpy
    dg = bpy.context.evaluated_depsgraph_get()
    objects = sorted(ex['visible_meshes'](), key=lambda o: o.name)
    boxes, occ_src, pruning, mismatch = gather_colliders(objects, ex)
    if mismatch:
        raise RuntimeError('Layout source/path mismatch; supply the matching --layout: ' + ', '.join(mismatch[:10]))
    chunks, polygons, alpha_chunks, records, safe_boxes, features = [], [], [], [], [], []
    offset = 0
    tagged_colliders = {c.get('src') for c in boxes if c.get('tags') or c.get('at') or c.get('kind') == 'Seat'}
    keep = set()
    if args.keep:
        value = json.loads(Path(args.keep).read_text(encoding='utf-8'))
        keep = set(value.get('objects', [])) if isinstance(value, dict) else set(value)
    for light in bpy.data.collections['L4 Cinema'].all_objects:
        if light.type == 'LIGHT':
            host = light.get('l4_host', light.data.get('l4_host'))
            if host:
                keep.add(str(host))
            parent = light.parent
            while parent is not None:
                keep.add(parent.name)
                parent = parent.parent
    for obj in objects:
        me, ev = ex['mesh_of'](obj, dg)
        me.calc_loop_triangles()
        nt = len(me.loop_triangles)
        co = np.empty(len(me.vertices) * 3)
        me.vertices.foreach_get('co', co)
        co = co.reshape(-1, 3)
        mw = np.array(obj.matrix_world)
        world = co @ mw[:3, :3].T + mw[:3, 3]
        tv = np.empty(nt * 3, dtype=np.int32)
        me.loop_triangles.foreach_get('vertices', tv)
        tv = tv.reshape(-1, 3)
        pi = np.empty(nt, dtype=np.int32)
        me.loop_triangles.foreach_get('polygon_index', pi)
        mi = np.empty(nt, dtype=np.int32)
        me.loop_triangles.foreach_get('material_index', mi)
        materials = [slot.material for slot in obj.material_slots]
        transparent = np.array([material_transparent(m) for m in materials] or [False])
        ta = transparent[np.minimum(mi, len(transparent) - 1)]
        if obj.get('l4_door_leaf'):
            ta[:] = True  # A moving/open door must never certify hidden scenery.
        part = None
        src = obj.get('l4_src')
        if src is not None and int(src) < len(ex['LAYOUT']['parts']):
            part = ex['LAYOUT']['parts'][int(src)]
        tags = bool(obj.get('l4_tags') or obj.get('l4_attrs') or obj.get('tags') or obj.data.get('l4_tags')
                    or obj.data.get('l4_attrs') or obj.data.get('tags') or obj.data.get('l4_col_tags')
                    or (part and (part.get('tags') or part.get('at'))))
        label = obj.name + ' ' + str(obj.get('l4_path', '')) + ' ' + str(obj.get('l4_role', ''))
        protected = bool(l4_owned(obj) or tags or obj.get('l4_door_leaf') or obj.get('l4_seat')
            or obj.data.get('l4_seat') or obj.data.get('l4_seat_col') is not None or obj.name in tagged_colliders
            or re.search(r'door|frame|jamb|casing|seat|Level4V4|arcade.*(?:control|button|interactive)', label, re.I) or obj.name in keep
            or any('Door' in c.name for c in obj.users_collection)
            or any(m and m.get('l4_tags') for m in materials))
        if nt and re.search(r'door|opening|stair|step|gap|reveal|landing|threshold', label, re.I):
            features.append({'name': obj.name, 'lo': world.min(0).tolist(), 'hi': world.max(0).tolist()})
        occludes = bool((src is not None and int(src) in occ_src and obj.get('l4_path')
                        and part and obj['l4_path'] == part['p'] and not obj.get('l4_prop'))
                        or obj.get('l4_occluder') or obj.data.get('l4_occluder'))
        blockers = [c for c in boxes if c.get('occ') and c.get('sh') == 'Block'
                    and min(c['s']) >= .5 - 1e-9
                    and (c.get('src') == obj.name or (part and c.get('cf') == part['cf']))]
        # A live hull moved outside its old layout collision is not a safe enclosure.
        studio = np.column_stack((world[:, 0] / .28 + 23000, world[:, 2] / .28, -world[:, 1] / .28))
        covered = any(np.all(np.abs((studio - c['cf'][:3]) @ np.array(c['cf'][3:]).reshape(3, 3))
                             <= np.array(c['s']) / 2 + .11) for c in blockers)
        occludes = occludes and covered
        cert = convex_certificate(world, tv) if occludes and not ta.any() else None
        if cert:
            cert['name'] = obj.name
            safe_boxes.append(cert)
            if args.mode == 'enclosure':
                protected = True  # enclosure certificates require immutable anchors
        records.append({'name': obj.name, 'start': offset, 'end': offset + nt,
                        'protected': protected, 'prop': bool(obj.get('l4_prop')),
                        'certificate': bool(cert), 'polygons': len(me.polygons),
                        'src': int(src) if src is not None else None,
                        'path': part['p'] if part else None, 'orig': part['cf'][:3] if part else None,
                        'has_children': bool(obj.children), 'collections': [c.name for c in obj.users_collection]})
        chunks.append(world[tv].astype(np.float32))
        polygons.append(pi)
        alpha_chunks.append(ta)
        offset += nt
        if ev:
            ev.to_mesh_clear()
    # Evaluated generated instances participate in visibility but are never edited.
    allowed = {o.name for o in bpy.data.collections['L4 Cinema'].all_objects}
    for inst in dg.object_instances:
        if not inst.is_instance or not (inst.parent and inst.parent.original.name in allowed):
            continue
        ev = inst.object
        if ev.type != 'MESH':
            continue
        me = ev.to_mesh()
        me.calc_loop_triangles()
        co = np.array([v.co[:] for v in me.vertices])
        tv = np.array([t.vertices[:] for t in me.loop_triangles], dtype=np.int32)
        mw = np.array(inst.matrix_world)
        p = (co @ mw[:3, :3].T + mw[:3, 3])[tv]
        chunks.append(p.astype(np.float32))
        polygons.append(np.full(len(tv), -1, np.int32))
        alpha_chunks.append(np.array([material_transparent(me.materials[t.material_index])
            if t.material_index < len(me.materials) else False for t in me.loop_triangles]))
        records.append({'name': 'INSTANCE:' + ev.name, 'start': offset, 'end': offset + len(tv),
                        'protected': True, 'prop': True, 'certificate': False})
        offset += len(tv)
        ev.to_mesh_clear()
    np.save(work / 'triangles.npy', np.concatenate(chunks))
    np.save(work / 'triangle_polygons.npy', np.concatenate(polygons))
    np.save(work / 'transparent.npy', np.concatenate(alpha_chunks))
    lights = []
    for obj in bpy.data.collections['L4 Cinema'].all_objects:
        if obj.type != 'LIGHT':
            continue
        distance = obj.get('l4_range', obj.data.get('l4_range'))
        if distance is None:
            distance = obj.data.cutoff_distance / .28 if obj.data.use_custom_distance else 16
        lights.append({'name': obj.name, 'pos': list(obj.matrix_world.translation), 'range': float(distance),
                       'protected': bool(l4_owned(obj) or obj.get('l4_tags') or obj.get('l4_attrs') or obj.name in keep
                                         or re.search(r'Level4V4|door|seat', obj.name, re.I))})
    extra_views, extra_view_files = [], []
    qa_views = Path('G:/Roblox/_local/l4facelift/v3/integ/qa_views.json')
    view_paths = ([Path(args.views)] if args.views else []) + ([Path(args.visibility_views)] if args.visibility_views else [])
    view_paths += [qa_views] if qa_views.is_file() else []
    for view_path in dict.fromkeys(view_paths):
        extra_view_files.append({'path': str(view_path.resolve()), 'sha256': file_hash(view_path)})
        view_data = json.loads(view_path.read_text(encoding='utf-8'))
        for view in view_data.get('views', []) if isinstance(view_data, dict) else view_data:
            point = view.get('eye', view.get('cam'))
            if point is not None:
                extra_views.append(point if isinstance(view_data, dict) and view_data.get('coordinate_system') == 'blender'
                                   else w_rb(point).tolist())
    scene = {'visibility_extra_views': extra_views, 'visibility_view_files': extra_view_files,
             'boxes': boxes, 'safe_boxes': safe_boxes, 'objects': records, 'features': features, 'lights': lights,
             'seeds': [[23075, 26, 110], [23000, 27, 226]], 'layout_pruning': pruning,
             'layout_mismatches': mismatch, 'coordinate_system': 'blender',
             'source_blend': bpy.data.filepath}
    json_write(work / 'scene.json', scene)
    print('P7 exported', offset, 'triangles;', len(boxes), 'collision boxes;',
          len(safe_boxes), 'immutable convex occluders', flush=True)
    return scene


def preserve_bounds_collider(obj):
    """Deleting visual faces must not silently shrink an existing bounds collider."""
    if obj.get('l4_col', obj.data.get('l4_col')) is not None:
        return
    if obj.get('l4_collide') == 'bounds' or obj.get('l4_occluder') or obj.data.get('l4_occluder'):
        bb = np.array(obj.bound_box)
        obj['l4_col'] = json.dumps([((bb.min(0) + bb.max(0)) / 2).tolist()
                                   + (bb.max(0) - bb.min(0)).tolist()])


def delete_faces_preserving_normals(me, faces):
    """Hidden neighbour deletion must not reshape the shading of visible faces."""
    import bmesh
    normal = np.empty(len(me.corner_normals) * 3)
    me.corner_normals.foreach_get('vector', normal)
    normal = normal.reshape(-1, 3)
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    layer = bm.loops.layers.int.new('__p7_original_loop')
    layer_name = layer.name
    for face in bm.faces:
        for loop, old_id in zip(face.loops, me.polygons[face.index].loop_indices):
            loop[layer] = int(old_id)
    bmesh.ops.delete(bm, geom=[bm.faces[int(i)] for i in faces], context='FACES')
    bm.to_mesh(me)
    bm.free()
    me.update()
    attr = me.attributes[layer_name]
    source_ids = np.empty(len(attr.data), np.int32)
    attr.data.foreach_get('value', source_ids)
    me.attributes.remove(attr)
    raw = np.empty(len(me.corner_normals) * 3)
    me.corner_normals.foreach_get('vector', raw)
    raw = raw.reshape(-1, 3)
    expected = normal[source_ids]
    changed = not np.array_equal(raw, expected)
    if changed:
        me.normals_split_custom_set(expected.tolist())
        me.update()
        me.corner_normals.foreach_get('vector', raw.reshape(-1))
    error = float(np.linalg.norm(raw - expected, axis=1).max(initial=0))
    if error >= .001:
        raise RuntimeError('Normal preservation exceeds tolerance; original input is unchanged')
    return {'custom_normals_needed': changed, 'max_normal_vector_error': error}


def apply_removals(work, scene, ex, mode):
    import bpy
    import bmesh
    removable = np.load(work / 'removable.npy')
    polygon_ids = np.load(work / 'triangle_polygons.npy')
    deleted, edits, retained = [], [], []
    cleanup = json.loads((work / 'cleanup.json').read_text(encoding='utf-8')) if mode == 'visibility' else {'colliders': [], 'lights': []}
    omitted = json.loads(bpy.context.scene.get('l4_culled_colliders', '[]')) + cleanup['colliders']
    bpy.context.scene['l4_culled_colliders'] = json.dumps(omitted)
    carriers = json.loads(bpy.context.scene.get('l4_culled_carriers', '[]'))
    def collider_kept(obj):
        return any(not any(x.get('src') == c.get('src') and x.get('cf') == c['cf'] and x.get('s') == c['s']
                           for x in omitted if 'src' in x) for c in ex['object_colliders'](obj))
    def record_carrier(record):
        if record.get('path'):
            carriers.append({'path': record['path'], 'orig': record['orig']})
    variants = {}
    dg = bpy.context.evaluated_depsgraph_get()
    for record in scene['objects']:
        a, b = record['start'], record['end']
        if record['protected'] or not np.any(removable[a:b]):
            continue
        obj = bpy.data.objects.get(record['name'])
        if obj is None:
            continue
        if l4_owned(obj):
            raise RuntimeError('Refusing a stale cull nomination for L4-owned object: ' + obj.name)
        if record['prop']:
            if not np.all(removable[a:b]) or obj.children or collider_kept(obj):
                continue  # uncertain host/collision semantics retain whole instance
            record_carrier(record)
            deleted.append({'name': obj.name, 'kind': 'prop', 'triangles': b - a, 'collections': record['collections']})
            bpy.data.objects.remove(obj, do_unlink=True)
            continue
        # Every triangle of a polygon must pass; preserve its UVs, materials and attributes.
        ids = polygon_ids[a:b]
        total = np.bincount(ids, minlength=record['polygons'])
        passed = np.bincount(ids[removable[a:b]], minlength=record['polygons'])
        faces = np.flatnonzero((total > 0) & (total == passed))
        if not len(faces):
            continue
        variant = (obj.data.as_pointer(), tuple(faces)) if not obj.modifiers else None
        reused = variant is not None and variant in variants
        if reused:
            me, normal_stats = variants[variant]
        elif obj.modifiers:
            mesh_props = {k: obj.data[k] for k in obj.data.keys()}
            ev = obj.evaluated_get(dg)
            me = bpy.data.meshes.new_from_object(ev, preserve_all_data_layers=True, depsgraph=dg)
            for key, value in mesh_props.items():
                me[key] = value
        else:
            me = obj.data.copy()
        if not reused:
            try:
                normal_stats = delete_faces_preserving_normals(me, faces)
            except RuntimeError as exc:
                if not str(exc).startswith('Normal preservation exceeds tolerance'):
                    raise
                retained.append({'name': obj.name, 'reason': str(exc)})
                print('P7 RETAIN', obj.name, str(exc), flush=True)
                bpy.data.meshes.remove(me)
                continue
            if variant is not None:
                variants[variant] = (me, normal_stats)
        preserve_bounds_collider(obj)
        obj.modifiers.clear()
        obj.data = me
        if len(faces) == record['polygons']:
            record_carrier(record)
        edits.append({'name': obj.name, 'faces': faces.tolist(),
                      'triangles_removed': int(passed[faces].sum()), 'collections': record['collections'], **normal_stats})
        if not obj.data.polygons and not collider_kept(obj):
            deleted.append({'name': obj.name, 'kind': 'pooled', 'triangles': b - a, 'collections': record['collections']})
            bpy.data.objects.remove(obj, do_unlink=True)
    for name in cleanup['lights']:
        obj = bpy.data.objects.get(name)
        if obj and obj.type == 'LIGHT':
            if l4_owned(obj):
                raise RuntimeError('Refusing cleanup of L4-owned light: ' + obj.name)
            deleted.append({'name': name, 'kind': 'light', 'collections': [c.name for c in obj.users_collection]})
            bpy.data.objects.remove(obj, do_unlink=True)
    bpy.context.scene['l4_culled_carriers'] = json.dumps(carriers)
    return deleted, edits, retained


def blender_main():
    import bpy
    started = time.perf_counter()
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('output')
    p.add_argument('--report', required=True)
    p.add_argument('--work-dir')
    p.add_argument('--layout', default=str(Path(__file__).with_name('l4_layout.json')))
    p.add_argument('--build-dir', help='Frozen builder scripts used for export metadata; defaults to repository scripts')
    p.add_argument('--python', default='python')
    p.add_argument('--python-path', action='append', default=[])
    p.add_argument('--views', help='Proof viewpoint JSON; copied into the audit report by hash')
    p.add_argument('--visibility-views', help='Extra sightline cameras; independent of later generated proof viewpoints')
    p.add_argument('--keep', help='JSON object-name list or {objects:[...]}; rerun from original input')
    p.add_argument('--seed', type=int, default=7007)
    p.add_argument('--samples', type=int, default=3000)
    p.add_argument('--directions', type=int, default=2048)
    p.add_argument('--burial-margin-studs', type=float, default=.3)
    p.add_argument('--mode', choices=('visibility', 'enclosure'), default='visibility')
    args = p.parse_args(argv)
    output = Path(args.output).resolve()
    source = Path(bpy.data.filepath).resolve()
    master = Path('G:/Blender/Level4_Cinema/Level4_Cinema.blend').resolve()
    if output in (source, master):
        raise ValueError('Output must differ from both input and protected master')
    if args.samples < 3000 or args.directions < 2048:
        raise ValueError('Full cull requires >=3000 sample points and >=2048 directions')
    if args.burial_margin_studs < .3:
        raise ValueError('Burial margin must be >=.3 studs (collider inset plus bound tolerance)')
    if args.views and not Path(args.views).is_file():
        raise FileNotFoundError(args.views)
    if args.visibility_views and not Path(args.visibility_views).is_file():
        raise FileNotFoundError(args.visibility_views)
    work = Path(args.work_dir or str(Path(args.report).with_suffix('')) + '_work').resolve()
    work.mkdir(parents=True, exist_ok=True)
    here = Path(__file__).resolve().parent
    build_dir = Path(args.build_dir or here).resolve()
    ex, export_hash = load_exporter(here, args.layout, build_dir)
    dependency_paths = [here / 'export_l4.py', here / 'make_place.py', here / 'l4_dump.json',
                        Path(args.layout), build_dir / 'build_base.py'] + [build_dir / f for f in ex['BUILD_MODULES']]
    dependency_paths += [Path(f) for f in (args.views, args.visibility_views) if f]
    dependencies = {str(path.resolve()): file_hash(path) for path in dependency_paths}
    root = bpy.data.collections.get('L4 Cinema')
    if root is None:
        raise ValueError('Input has no L4 Cinema collection')
    before = scene_counts(root, ex)
    source_hash = file_hash(source)
    tool_hash = file_hash(__file__)
    keep_hash = file_hash(args.keep) if args.keep else None
    scene = export_worker_scene(work, ex, args)
    command = [args.python, str(Path(__file__).resolve()), '--worker', str(work),
               '--seed', str(args.seed), '--samples', str(args.samples),
               '--directions', str(args.directions), '--burial-margin-studs', str(args.burial_margin_studs), '--mode', args.mode]
    for path in args.python_path:
        command.extend(['--python-path', path])
    print('P7 worker', command, flush=True)
    subprocess.run(command, check=True)
    deleted, edits, retained = apply_removals(work, scene, ex, args.mode)
    after = scene_counts(root, ex)
    # Verify collision records stay identical, not just their count.
    current = sorted(ex['visible_meshes'](), key=lambda o: o.name)
    after_boxes, _, _, _ = gather_colliders(current, ex)
    collision_same = json.dumps(scene['boxes'], sort_keys=True) == json.dumps(after_boxes, sort_keys=True)
    omitted = json.loads(bpy.context.scene.get('l4_culled_colliders', '[]'))
    def nominated(c):
        return any((x.get('path') == c.get('_path') and x.get('orig') == c['cf'][:3]) if 'path' in x
                   else (x.get('src') == c.get('src') and x.get('cf') == c['cf'] and x.get('s') == c['s']) for x in omitted)
    expected = [c for c in scene['boxes'] if not nominated(c)]
    if json.dumps(expected, sort_keys=True) != json.dumps(after_boxes, sort_keys=True):
        raise RuntimeError('Cull changed an unapproved collider; output was not saved')
    if file_hash(__file__) != tool_hash or (args.keep and file_hash(args.keep) != keep_hash):
        raise RuntimeError('Cull tool/keep baseline changed during run; output was not saved')
    if file_hash(source) != source_hash or any(file_hash(path) != sha for path, sha in dependencies.items()):
        raise RuntimeError('Input/export metadata changed during run; output was not saved')
    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(output), check_existing=False)
    report = {'status': 'culled_proof_pending', 'input': str(source), 'output': str(output),
        'input_sha256': source_hash, 'output_sha256': file_hash(output),
        'tool_sha256': tool_hash, 'exporter_sha256': export_hash,
        'build_dir': str(build_dir), 'dependencies_sha256': dependencies,
        'keep': str(Path(args.keep).resolve()) if args.keep else None, 'keep_sha256': keep_hash,
        'layout': str(Path(args.layout).resolve()), 'layout_sha256': file_hash(args.layout),
        'seed': args.seed, 'mode': args.mode, 'before': before, 'after': after,
        'savings': {k: before[k] - after[k] for k in ('objects', 'meshes', 'lights',
                    'triangles_placed', 'triangles_unique', 'colliders_scene')},
        'colliders_layout_and_scene': {'before': len(scene['boxes']), 'after': len(after_boxes), 'identical': collision_same},
        'deleted_instances': deleted, 'edited_objects': edits,
        'retained_uncertain_objects': retained,
        'deleted_colliders': omitted,
        'per_collection_savings': {k: {m: v[m] - after['per_collection'].get(k, {}).get(m, 0) for m in v}
                                   for k, v in before['per_collection'].items()},
        'worker': json.loads((work / 'worker_report.json').read_text(encoding='utf-8')),
        'camera_samples': str(work / 'camera_samples.npy'), 'work_dir': str(work),
        'visibility_view_files': scene['visibility_view_files'],
        'proof_views': str(Path(args.views).resolve()) if args.views else None,
        'proof_views_sha256': file_hash(args.views) if args.views else None,
        'elapsed_seconds': time.perf_counter() - started,
        'policy': ('Unhit faces with every exact probe occluded; protected gameplay stays; paired render proof required.'
                   if args.mode == 'visibility' else 'Certified convex-occluder-contained unseen polygons only.'),
        'limitations': ['Finite proof viewpoints do not establish universal gameplay visibility.',
                         'Glass, decals, unknown alpha and uncertain candidates retained or rays continued.',
                         'Light/collider reachability is offline voxel analysis, not a Roblox gameplay test.']}
    json_write(args.report, report)
    print('P7 SAVINGS', report['savings'], 'seconds', round(report['elapsed_seconds'], 2), flush=True)


# Worker implementation follows below. Imports bpy only in blender_main().
"""Plain-Python visibility worker; imported/embedded by cull_hidden.py.

Visibility mode nominates unhit whole polygons and rejects every clear or uncertain
exact probe. Enclosure mode additionally requires convex opaque burial >=0.3 studs.
Transparent surfaces and gameplay objects remain; transparent blockers are ignored.
"""


def w_rb(points):
    """Studio studs -> Blender metres (works for any leading dimensions)."""
    import numpy as np
    p = np.asarray(points, dtype=np.float64)
    return np.stack(((p[..., 0] - 23000) * .28, -p[..., 2] * .28, p[..., 1] * .28), -1)


def w_box(box):
    import numpy as np
    cf = np.asarray(box["cf"], dtype=np.float64)
    size = np.asarray(box["s"], dtype=np.float64)
    if cf.shape != (12,) or size.shape != (3,) or not np.isfinite(cf).all() or not np.isfinite(size).all():
        raise ValueError("invalid collider frame/size")
    if np.any(size <= 0):
        raise ValueError("nonpositive collider size")
    transform = np.array(((1, 0, 0), (0, 0, -1), (0, 1, 0)), float)
    rotation = transform @ cf[3:].reshape(3, 3)
    if not np.allclose(rotation.T @ rotation, np.eye(3), atol=.002):
        raise ValueError("nonorthogonal collider rotation")
    return w_rb(cf[:3]) / .28, rotation, size / 2


def w_raster(grid, origin, box, mode="inner"):
    """Mark certain solid cells, or possible support cells, of an oriented box.

    Inner occupancy requires the whole voxel to fit: uncertainty enlarges free
    space. Outer support only requires potential intersection: uncertainty adds
    possible floors. Both choices keep rather than erase uncertain geometry.
    Camera occupancy uses cell centres; its dilation is deliberately permissive.
    """
    import numpy as np
    centre, rotation, half = w_box(box)
    extent = np.abs(rotation) @ half
    cell_margin = .5 * np.abs(rotation).sum(axis=0)
    test_half = half + cell_margin if mode == "outer" else half - cell_margin if mode == "inner" else half
    if np.any(test_half <= 0):
        return
    lo = np.maximum(0, np.floor(centre - extent - 1 - origin).astype(int))
    hi = np.minimum(grid.shape, np.ceil(centre + extent + 1 - origin).astype(int))
    if np.any(lo >= hi):
        return
    axes = [np.arange(lo[k], hi[k], dtype=np.float32) + float(origin[k]) + .5 - centre[k] for k in range(3)]
    # Slab along X bounds temporary memory even for building-wide floor boxes.
    yz = axes[1][:, None], axes[2][None, :]
    for start in range(0, len(axes[0]), 16):
        xx = axes[0][start:start + 16, None, None]
        inside = np.ones((len(xx), len(axes[1]), len(axes[2])), dtype=bool)
        for k in range(3):
            local = xx * rotation[0, k] + yz[0][None] * rotation[1, k] + yz[1][None] * rotation[2, k]
            inside &= np.abs(local) <= test_half[k] + 1e-6
        region = grid[lo[0] + start:lo[0] + start + len(xx), lo[1]:hi[1], lo[2]:hi[2]]
        region |= inside


def w_hulls(raw):
    import numpy as np
    out = []
    for box in raw:
        lo, hi = np.asarray(box["lo"], float), np.asarray(box["hi"], float)
        if not np.isfinite(lo).all() or not np.isfinite(hi).all() or np.any(lo >= hi):
            continue
        if box.get("planes"):
            normal = np.array([p["n"] for p in box["planes"]], float)
            offset = np.array([p["d"] for p in box["planes"]], float)
            length = np.linalg.norm(normal, axis=1)
            if np.any(length < 1e-8) or not np.isfinite(normal).all() or not np.isfinite(offset).all():
                continue
            normal, offset = normal / length[:, None], offset / length
        else:
            normal = np.vstack((np.eye(3), -np.eye(3)))
            offset = np.concatenate((hi, -lo))
        out.append(dict(box, lo=lo, hi=hi, normal=normal, offset=offset))
    return out


def w_inside(points, hull, margin=0):
    import numpy as np
    return np.all(np.asarray(points) @ hull["normal"].T <= hull["offset"] - margin + 1e-7, axis=-1)


def w_exclude_hulls(grid, origin, hulls):
    """No camera can occupy the inside of an intact opaque camera occluder.

    Grid centres deeper than one voxel's half diagonal are certainly inside;
    exclude only those cells. Boundary cells stay for conservative sampling.
    """
    import numpy as np
    for hull in hulls:
        lo = np.maximum(0, np.floor(hull["lo"] / .28 - origin).astype(int))
        hi = np.minimum(grid.shape, np.ceil(hull["hi"] / .28 - origin).astype(int))
        if np.any(lo >= hi):
            continue
        axes = [(np.arange(lo[k], hi[k], dtype=np.float32) + origin[k] + .5) * .28 for k in range(3)]
        for start in range(0, len(axes[0]), 8):
            coords = np.stack(np.broadcast_arrays(axes[0][start:start+8, None, None],
                                                 axes[1][None, :, None], axes[2][None, None, :]), -1)
            inner = w_inside(coords.reshape(-1, 3), hull, margin=.28 * (.5 * 3**.5 + 1e-3))
            view = grid[lo[0]+start:lo[0]+start+len(coords), lo[1]:hi[1], lo[2]:hi[2]]
            view &= ~inner.reshape(view.shape)


def w_standable(solids, support):
    """2 x 2 footprint, five cells headroom, possible floor <=1.5 studs below.

    Half-cell support uncertainty is rounded outwards to two cells. Clearance is
    tested over the four possible footprint anchors; any clear anchor keeps a
    standable cell. This overapproximates quantised player motion.
    """
    import numpy as np
    clear = ~solids.copy()
    for dz in range(1, 5):
        clear[:, :, :-dz] &= ~solids[:, :, dz:]
        clear[:, :, -dz:] = False
    foot = np.zeros_like(clear)
    for sx, sy in ((0, 0), (0, 1), (1, 0), (1, 1)):
        base = clear[:-1, :-1] & clear[1:, :-1] & clear[:-1, 1:] & clear[1:, 1:]
        foot[sx:sx+base.shape[0], sy:sy+base.shape[1]] |= base
    floor = np.zeros_like(support)
    floor[:, :, 1:] |= support[:, :, :-1]
    floor[:, :, 2:] |= support[:, :, :-2]
    foot &= floor
    return foot


def w_components(stand, origin, seeds):
    """Flood standable graph with cardinal moves and <=2-stud step-up/down.

    Keep disconnected components too: narrow stairs/doors can be missed by a
    one-stud lattice. This fallback enlarges visibility, never deletion.
    """
    import numpy as np
    from scipy import sparse
    from scipy.sparse.csgraph import connected_components
    ids = np.flatnonzero(stand)
    if not len(ids):
        return stand, dict(standable_cells=0, flooded_cells=0, disconnected_fallback=True,
                           fallback_reason="no standable lattice cells")
    shape = np.array(stand.shape)
    xyz = np.stack(np.unravel_index(ids, stand.shape), -1)
    edges_a, edges_b = [], []
    for dx, dy in ((1, 0), (0, 1)):
        for dz in range(-2, 3):
            shifted = xyz + [dx, dy, dz]
            valid = ((shifted >= 0) & (shifted < shape)).all(1)
            left = np.flatnonzero(valid)
            values = np.ravel_multi_index(shifted[valid].T, stand.shape)
            right = np.searchsorted(ids, values)
            ok = right < len(ids)
            ok[ok] &= ids[right[ok]] == values[ok]
            edges_a.append(left[ok].astype(np.int32))
            edges_b.append(right[ok].astype(np.int32))
    a, b = np.concatenate(edges_a), np.concatenate(edges_b)
    graph = sparse.coo_matrix((np.ones(len(a), np.uint8), (a, b)), shape=(len(ids), len(ids))).tocsr()
    number, labels = connected_components(graph, directed=False)
    # Nearest standable cell is a conservative seed when arrival intersects a
    # collider/support boundary. Include a 12-stud arrival-neighbourhood also.
    from scipy.spatial import cKDTree
    tree = cKDTree(xyz + origin + .5)
    seed_studs = w_rb(seeds) / .28
    chosen = set()
    for seed in seed_studs:
        nearby = tree.query_ball_point(seed, 12)
        if nearby:
            chosen.update(int(labels[n]) for n in nearby)
        else:
            chosen.add(int(labels[tree.query(seed)[1]]))
    flooded = np.isin(labels, list(chosen))
    return stand, dict(standable_cells=int(len(ids)), standable_components=int(number),
                       seed_components=len(chosen), flooded_cells=int(flooded.sum()),
                       disconnected_fallback=bool(not flooded.all()),
                       fallback_reason="all standable components retained for stair/door quantisation" if not flooded.all() else None)


def w_stratum_cells(indices, stride, seed):
    import numpy as np
    if not len(indices):
        return np.empty((0, 3), dtype=np.int64)
    order = np.random.default_rng(seed).permutation(len(indices))
    _, first = np.unique(indices[order] // stride, axis=0, return_index=True)
    return indices[order[first]]


def w_filter_hulls(samples, hulls):
    import numpy as np
    valid = np.ones(len(samples), bool)
    for hull in hulls:
        ids = np.flatnonzero(((samples >= hull['lo']) & (samples <= hull['hi'])).all(1))
        if len(ids):
            valid[ids] &= ~w_inside(samples[ids], hull)
    return samples[valid]


def w_peek_samples(scene, camera, camera13, origin, hulls, seed):
    """Augment shell14 and every exported doorway/stair/gap near boundary3.

    Feature crops are padded by three cells before erosion, so crop edges do not
    manufacture a boundary. Named features get a representative in EVERY two
    stud stratum containing boundary air; no per-feature random cap.
    """
    import numpy as np
    from scipy import ndimage as ndi
    shell_ids = np.stack(np.unravel_index(np.flatnonzero(camera & ~camera13), camera.shape), -1)
    shell_cells = w_stratum_cells(shell_ids, 8, seed + 101)
    shell_samples = w_filter_hulls((shell_cells + origin + .5) * .28, hulls)
    all_cells = []
    feature_report = []
    for number, feature in enumerate(scene.get('features', [])):
        flo, fhi = np.asarray(feature['lo'], float) / .28, np.asarray(feature['hi'], float) / .28
        if (flo.shape != (3,) or fhi.shape != (3,) or not np.isfinite(flo).all()
                or not np.isfinite(fhi).all() or np.any(flo > fhi)):
            feature_report.append({'name': feature.get('name'), 'invalid': True})
            continue
        lo = np.maximum(0, np.floor(flo - origin - 6).astype(int))
        hi = np.minimum(camera.shape, np.ceil(fhi - origin + 6).astype(int))
        if np.any(lo >= hi):
            feature_report.append({'name': feature.get('name'), 'samples': 0})
            continue
        patch = camera[tuple(slice(int(a), int(b)) for a, b in zip(lo, hi))]
        boundary = patch & ~ndi.binary_erosion(patch, structure=np.ones((3, 3, 3), bool),
                                              iterations=3, border_value=1)
        indices = np.stack(np.nonzero(boundary), -1) + lo
        centres = indices + origin + .5
        # Cells within three studs of the feature, and within three of boundary.
        near = ((centres >= flo - 3.5) & (centres <= fhi + 3.5)).all(1)
        cells = w_stratum_cells(indices[near], 2, seed + 200 + number)
        feature_report.append({'name': feature.get('name'), 'kind': feature.get('kind'),
                               'boundary_air_cells': int(near.sum()), 'samples': int(len(cells))})
        all_cells.append(cells)
    cells = np.unique(np.concatenate(all_cells), axis=0) if all_cells else np.empty((0, 3), np.int64)
    feature_samples = w_filter_hulls((cells + origin + .5) * .28, hulls)
    samples = np.unique(np.concatenate((shell_samples, feature_samples)), axis=0)
    return samples.astype(np.float32), shell_samples.astype(np.float32), {
        'outer_shell14_air_cells': int(len(shell_ids)), 'outer_shell14_samples': int(len(shell_samples)),
        'feature_boundary_band_studs': 3, 'feature_sample_stride_studs': 2,
        'extra_feature_samples': int(len(feature_samples)), 'peek_feature_coverage': feature_report}


def w_gap_samples(camera, occluders, origin, hulls, seed):
    """Unnamed <=6-stud gaps: opposing occluders at <=3 studs, stride4.

    Inspect 32-cell X slabs so this does not allocate several full-grid masks.
    Every bottleneck stratum receives a sample; there is no global cap.
    """
    import numpy as np
    chosen, cells = [], 0
    shape = np.asarray(camera.shape)
    for start in range(0, camera.shape[0], 32):
        end = min(start + 32, camera.shape[0])
        gap = np.zeros_like(camera[start:end])
        for axis in range(3):
            side = [np.zeros_like(gap), np.zeros_like(gap)]
            for direction, sign in enumerate((-1, 1)):
                for distance in (1, 2, 3):
                    offset = sign * distance
                    base_lo, base_hi = np.array([start, 0, 0]), np.array([end, shape[1], shape[2]])
                    src_lo, src_hi = base_lo.copy(), base_hi.copy()
                    src_lo[axis] += offset
                    src_hi[axis] += offset
                    clipped_lo, clipped_hi = np.maximum(src_lo, 0), np.minimum(src_hi, shape)
                    if np.any(clipped_lo >= clipped_hi):
                        continue
                    dst_lo = clipped_lo - src_lo
                    dst_hi = dst_lo + clipped_hi - clipped_lo
                    side[direction][tuple(slice(a, b) for a, b in zip(dst_lo, dst_hi))] |= \
                        occluders[tuple(slice(a, b) for a, b in zip(clipped_lo, clipped_hi))]
            gap |= side[0] & side[1]
        gap &= camera[start:end]
        cells += int(gap.sum())
        indices = np.stack(np.nonzero(gap), -1) + [start, 0, 0]
        chosen.append(w_stratum_cells(indices, 4, seed + 300 + start))
    indices = np.concatenate(chosen) if chosen else np.empty((0, 3), np.int64)
    samples = w_filter_hulls((indices + origin + .5) * .28, hulls)
    return samples.astype(np.float32), {'unnamed_gap_air_cells': cells,
        'unnamed_gap_samples': len(samples), 'unnamed_gap_stride_studs': 4,
        'unnamed_gap_opposing_occluder_distance_studs': 3}


def w_region_box_touch(region, origin, box, margin=2):
    """Conservative OBB/voxel-volume touch test; local L-infinity margin.

    Extra corner cells retain uncertain boxes. True is a KEEP decision.
    """
    import numpy as np
    centre, rotation, half = w_box(box)
    expanded = half + float(margin)
    extent = np.abs(rotation) @ expanded
    lo = np.maximum(0, np.floor(centre - extent - origin).astype(int))
    hi = np.minimum(region.shape, np.ceil(centre + extent - origin).astype(int))
    if np.any(lo >= hi):
        return False
    cell_margin = .5 * np.abs(rotation).sum(axis=0)
    for start in range(int(lo[0]), int(hi[0]), 16):
        patch = region[start:min(start + 16, int(hi[0])), lo[1]:hi[1], lo[2]:hi[2]]
        if not patch.any():
            continue
        coords = np.stack(np.nonzero(patch), -1) + [start, lo[1], lo[2]] + origin + .5
        local = (coords - centre) @ rotation
        if np.any((np.abs(local) <= expanded + cell_margin + 1e-6).all(1)):
            return True
    return False


def w_region_sphere_touch(region, origin, position, radius_studs):
    """Exact sphere versus conservative union of camera voxel volumes.

    Face/edge/corner tangency retains the light. Invalid range retains it.
    """
    import numpy as np
    centre = np.asarray(position, float) / .28
    radius = float(radius_studs)
    if centre.shape != (3,) or not np.isfinite(centre).all() or not np.isfinite(radius) or radius < 0:
        return True
    lo = np.maximum(0, np.floor(centre - radius - origin).astype(int))
    hi = np.minimum(region.shape, np.ceil(centre + radius - origin).astype(int))
    # Tangent zero-radius spheres on a voxel boundary need both neighbours.
    lo = np.maximum(0, lo - 1)
    hi = np.minimum(region.shape, hi + 1)
    if np.any(lo >= hi):
        return False
    for start in range(int(lo[0]), int(hi[0]), 16):
        patch = region[start:min(start + 16, int(hi[0])), lo[1]:hi[1], lo[2]:hi[2]]
        if not patch.any():
            continue
        cells = np.stack(np.nonzero(patch), -1) + [start, lo[1], lo[2]] + origin
        distance = np.maximum(np.maximum(cells - centre, centre - cells - 1), 0)
        if np.any(np.einsum('ij,ij->i', distance, distance) <= radius * radius + 1e-6):
            return True
    return False


def w_cleanup_nominations(scene, stand, camera, origin):
    """Return exact scene['boxes'] indices and light names safe to nominate.

    The caller applies nominations only after the visibility proof gate. Exported
    layout boxes need their originating layout part suppressed, not mesh deletion.
    """
    import re
    protected_name = re.compile(r'door|frame|jamb|lintel|seat|pushdoor|level4v4', re.I)
    records = {o['name']: o for o in scene.get('objects', [])}
    colliders, lights, kept_boundary, invalid = [], [], [], []
    for index, box in enumerate(scene.get('boxes', [])):
        name = str(box.get('src', box.get('path', box.get('_path', ''))))
        record = records.get(name, {})
        gameplay = record.get('gameplay_protected', bool(record.get('protected') and not record.get('certificate')))
        if (box.get('_protected') or gameplay or protected_name.search(name) or box.get('tags')
                or box.get('at') or box.get('door') or box.get('kind') in ('Seat', 'Marker')):
            continue
        try:
            camera_touch = w_region_box_touch(camera, origin, box, 2)
            stand_touch = w_region_box_touch(stand, origin, box, 2)
        except (KeyError, ValueError, TypeError) as exc:
            invalid.append({'index': index, 'src': name, 'reason': str(exc)})
            continue
        if box.get('occ') and camera_touch:
            kept_boundary.append(index)
        if not camera_touch and not stand_touch:
            colliders.append({'index': index, 'src': name, 'occ': bool(box.get('occ')),
                              'reason': 'no standable/camera voxel within 2 studs'})
    for light in scene.get('lights', []):
        name = str(light.get('name', ''))
        if light.get('protected') or light.get('tags') or light.get('l4_tags') or protected_name.search(name):
            continue
        position = light.get('position', light.get('position_blender', light.get('pos')))
        try:
            touches = w_region_sphere_touch(camera, origin, position, light['range'])
        except (KeyError, TypeError, ValueError):
            touches = True
        if not touches:
            lights.append({'name': name, 'range': light['range'],
                           'reason': 'range sphere does not touch reachable camera air'})
    return {'collider_cleanup_nominations': colliders, 'light_cleanup_nominations': lights,
            'camera_boundary_occluder_indices_retained': kept_boundary,
            'cleanup_invalid_boxes_retained': invalid}



def w_camera(scene, triangles, count, seed, work=None):
    import numpy as np
    from scipy import ndimage as ndi
    boxes = []
    invalid = []
    for box in scene["boxes"]:
        if box.get("kind") == "Marker" or box.get("door"):
            continue
        try:
            w_box(box)
            boxes.append(box)
        except (ValueError, KeyError) as exc:
            invalid.append({"src": box.get("src"), "reason": str(exc)})
    hulls = w_hulls(scene.get("safe_boxes", []))
    points = triangles.reshape(-1, 3)
    low, high = points.min(0) / .28, points.max(0) / .28
    for box in boxes:
        centre, rotation, half = w_box(box)
        extent = np.abs(rotation) @ half
        low = np.minimum(low, centre - extent)
        high = np.maximum(high, centre + extent)
    origin = np.floor(low - 18).astype(int)
    shape = np.ceil(high + 18 - origin).astype(int)
    volume = int(np.prod(shape, dtype=np.int64))
    if volume > 180_000_000:
        raise RuntimeError("voxel domain exceeds safe memory bound; keep geometry and tighten input bounds")
    solids = np.zeros(shape, bool)
    support = np.zeros(shape, bool)
    occluders = np.zeros(shape, bool)
    for i, box in enumerate(boxes):
        # A wedge's bounding box can exclude a valid stair approach: use it only
        # for possible floor support, not certain player/camera obstruction.
        if box.get("sh", "Block") == "Block":
            w_raster(solids, origin, box, "inner")
            if box.get("occ") and min(box['s']) >= .5 - 1e-9:
                camera_box = dict(box, s=[s - .2 for s in box['s']])
                w_raster(occluders, origin, camera_box, "inner")
        w_raster(support, origin, box, "outer")
        if i and i % 1000 == 0:
            print("worker raster", i, "/", len(boxes), flush=True)
    stand = w_standable(solids, support)
    del solids, support
    stand, report = w_components(stand, origin, scene.get("seeds", [[23075, 26, 110], [23000, 27, 226]]))
    camera = stand & ~occluders
    # Chebyshev dilation includes every <=14-stud Euclidean route and some
    # longer diagonal routes. Extra possible views are deliberately retained.
    camera13 = ndi.binary_dilation(camera, structure=np.ones((3, 3, 3), bool), iterations=13,
                                   mask=~occluders, border_value=0)
    camera = ndi.binary_dilation(camera13, structure=np.ones((3, 3, 3), bool), iterations=1,
                                 mask=~occluders, border_value=0)
    w_exclude_hulls(camera, origin, hulls)
    extra_samples, shell_samples, extra_report = w_peek_samples(scene, camera, camera13, origin, hulls, seed)
    gap_samples, gap_report = w_gap_samples(camera, occluders, origin, hulls, seed)
    extra_samples = np.concatenate((extra_samples, gap_samples))
    extra_report.update(gap_report)
    cleanup_report = w_cleanup_nominations(scene, stand, camera, origin)
    omitted = []
    for entry in cleanup_report['collider_cleanup_nominations']:
        box = scene['boxes'][entry['index']]
        item = {'path': box['_path'], 'orig': box['cf'][:3]} if box.get('_path') else {k: box[k] for k in ('src', 'cf', 's')}
        item['approved_by'] = 'visibility_air_margin2'
        omitted.append(item)
    if work:
        np.save(os.path.join(work, 'camera_shell_samples.npy'), shell_samples)
        json_write(Path(work) / 'cleanup.json', {'colliders': omitted,
            'lights': [x['name'] for x in cleanup_report['light_cleanup_nominations']]})
    del stand, camera13
    flat = np.flatnonzero(camera)
    if len(flat) < count:
        raise RuntimeError("insufficient camera air cells; keep geometry and inspect seed/collider export")
    rng = np.random.default_rng(seed)
    pool_ids = rng.choice(flat, size=min(len(flat), max(80_000, count * 32)), replace=False)
    pool = np.stack(np.unravel_index(pool_ids, camera.shape), -1)
    # One representative per 16-stud 3D stratum, then uniform coverage fills the
    # requested count. Sample points are inside one-stud cells, never on edges.
    bins = pool // 16
    order = rng.permutation(len(pool))
    _, first = np.unique(bins[order], axis=0, return_index=True)
    chosen = order[first]
    if len(chosen) >= count:
        chosen = rng.choice(chosen, count, replace=False)
    else:
        rest = np.setdiff1d(np.arange(len(pool)), chosen, assume_unique=False)
        chosen = np.concatenate((chosen, rng.choice(rest, count-len(chosen), replace=False)))
    # Extra samples near walls/ceilings/openings: six neighbour probes identify
    # cramped cells without a full-volume float distance transform.
    close = np.zeros(len(pool), np.int8)
    for distance in (1, 2, 4):
        for axis in range(3):
            for sign in (-1, 1):
                adj = pool.copy()
                adj[:, axis] = np.clip(adj[:, axis] + sign * distance, 0, camera.shape[axis]-1)
                close += occluders[tuple(adj.T)]
    extra = np.argsort(-close, kind="stable")[:min(512, len(pool))]
    chosen = np.unique(np.concatenate((chosen, extra)))
    indices = pool[chosen]
    # Jitter only inside actual air, including exact retained opaque hull tests.
    samples = (indices + origin + rng.uniform(.1, .9, (len(indices), 3))) * .28
    rejected = 0
    for hull in hulls:
        ids = np.flatnonzero(((samples >= hull["lo"]) & (samples <= hull["hi"])).all(1))
        if len(ids):
            inside = w_inside(samples[ids], hull)
            rejected += int(inside.sum())
            samples[ids[inside]] = np.nan
    samples = samples[np.isfinite(samples).all(1)]
    # Rare boundary jitters inside a hull are replaced by additional valid air
    # cell centres. Reject rather than project a point through a solid surface.
    while len(samples) < count:
        refill = rng.choice(flat, size=min(len(flat), max(1024, count-len(samples))), replace=False)
        new = (np.stack(np.unravel_index(refill, camera.shape), -1) + origin + .5) * .28
        valid = np.ones(len(new), bool)
        for hull in hulls:
            ids = np.flatnonzero(((new >= hull["lo"]) & (new <= hull["hi"])).all(1))
            if len(ids):
                valid[ids] &= ~w_inside(new[ids], hull)
        new = new[valid]
        if not len(new):
            raise RuntimeError("all refill camera samples lie inside retained hulls")
        samples = np.concatenate((samples, new[:count-len(samples)]))
    samples = np.unique(np.concatenate((samples, extra_samples)), axis=0)
    report.update(extra_report)
    report.update(cleanup_report)
    report.update(voxel_size_studs=1, voxel_origin_blender_studs=origin.tolist(), voxel_shape=shape.tolist(),
                  voxel_cells=volume, colliders=len(boxes), camera_occluder_boxes=sum(
                      bool(b.get('occ')) and min(b['s']) >= .5 - 1e-9 for b in boxes),
                  camera_occluder_inset_studs=.1,
                  invalid_boxes=invalid, camera_region_cells=int(len(flat)), camera_geodesic_limit_studs=14,
                  camera_metric="Chebyshev overapproximation", camera_samples=int(len(samples)),
                  requested_samples=count, extra_cramped_samples=int(len(chosen)-count),
                  rejected_hull_interior_samples=rejected, safe_hulls=len(hulls))
    return samples.astype(np.float32), report, hulls


def w_directions(count, seed):
    import numpy as np
    rng = np.random.default_rng(seed)
    z = 1 - 2 * (np.arange(count) + rng.uniform(.05, .95, count)) / count
    phi = np.arange(count) * (np.pi * (3 - 5**.5)) + rng.uniform(-np.pi / count, np.pi / count, count)
    radius = np.sqrt(1-z*z)
    return np.column_stack((radius*np.cos(phi), radius*np.sin(phi), z)).astype(np.float32)


def w_first_opaque(accel, origins, directions, transparent, seen=None, max_steps=64):
    """First opaque hit after transparent surfaces; ceiling/floating ambiguity is
    returned separately so callers keep candidates. Distances are from original
    origins. No backface culling is used (Roblox's opaque enclosure is two-sided).
    """
    import numpy as np
    n = len(origins)
    active = np.arange(n)
    here = np.asarray(origins, np.float32).copy()
    dirs = np.asarray(directions, np.float32)
    travelled = np.zeros(n, np.float32)
    hit = np.full(n, -1, np.int32)
    distance = np.full(n, np.inf, np.float32)
    uncertain = np.zeros(n, bool)
    rays = 0
    for _ in range(max_steps):
        if not len(active):
            break
        result = accel.run(here[active], dirs[active], output=1)
        ids, tfar = result["primID"], result["tfar"]
        rays += len(active)
        found = (ids >= 0) & (ids < len(transparent))
        invalid = ((ids >= len(transparent)) | (found & (~np.isfinite(tfar) | (tfar < -1e-5))))
        uncertain[active[invalid]] = True
        found &= ~invalid
        if seen is not None:
            seen[ids[found]] = True
        opaque = found.copy()
        opaque[found] &= ~transparent[ids[found]]
        dst = active[opaque]
        hit[dst] = ids[opaque]
        distance[dst] = travelled[dst] + tfar[opaque]
        onward = found & ~opaque
        active = active[onward]
        if len(active):
            step = tfar[onward] + 1e-5
            here[active] += dirs[active] * step[:, None]
            travelled[active] += step
    else:
        uncertain[active] = True
    return hit, distance, uncertain, rays


class w_OpaqueAdapter:
    """Independent opaque BVH; reports original triangle IDs, ignoring glass.

    This resolves coincident transparent surfaces without depending on advanced
    ray origins or a transparent-layer traversal ceiling.
    """
    def __init__(self, triangles, transparent):
        import numpy as np
        from embreex.rtcore_scene import EmbreeScene
        from embreex.mesh_construction import TriangleMesh
        self.ids = np.flatnonzero(~transparent).astype(np.int32)
        self.scene = EmbreeScene()
        self.mesh = TriangleMesh(self.scene, np.asarray(triangles[self.ids], np.float32))

    def run(self, origins, directions, output=1):
        import numpy as np
        result = self.scene.run(origins, directions, output=output)
        found = result["primID"] >= 0
        mapped = result["primID"].copy()
        mapped[found] = self.ids[mapped[found]]
        result["primID"] = mapped
        return result


def w_visibility(accel, opaque, samples, transparent, count, seed):
    import numpy as np
    from scipy.spatial.transform import Rotation
    directions = w_directions(count, seed)
    rng = np.random.default_rng(seed + 1)
    seen = np.zeros(len(transparent), bool)
    rays, uncertain, opaque_queries, opaque_uncertain = 0, 0, 0, 0
    # 64 viewpoints per Embree batch: ~131k rays at the default setting.
    for i in range(0, len(samples), 64):
        origins = samples[i:i+64]
        rotations = Rotation.random(len(origins), random_state=rng).as_matrix().astype(np.float32)
        dirs = np.einsum("nij,kj->nki", rotations, directions).reshape(-1, 3)
        o = np.repeat(origins, count, axis=0)
        _, _, bad, queries = w_first_opaque(accel, o, dirs, transparent, seen)
        rays += queries
        uncertain += int(bad.sum())
        # Always query the original ray in an independent opaque BVH. Every
        # transparent face stays, and this pass records the first real blocker
        # even when coincident glass exhausted the transparent traversal cap.
        _, _, bad_opaque, queries = w_first_opaque(opaque, o, dirs, transparent, seen)
        opaque_queries += queries
        opaque_uncertain += int(bad_opaque.sum())
        if i % 512 == 0:
            print("worker visibility viewpoints", i, "/", len(samples), "hits", int(seen.sum()), flush=True)
    return seen, dict(random_visibility_rays=int(len(samples)*count), embree_visibility_queries=rays,
                      visibility_hit_triangles=int(seen.sum()), uncertain_visibility_rays=uncertain,
                      independent_opaque_visibility_queries=opaque_queries,
                      transparent_ceiling_rays_resolved_by_opaque_bvh=uncertain,
                      uncertain_opaque_visibility_rays=opaque_uncertain,
                      jittered_directions_per_sample=count)


def w_eligible(scene, seen, transparent, mode):
    eligible = ~seen & ~transparent
    for obj in scene['objects']:
        a, b = obj['start'], obj['end']
        # Instanced props are indivisible. A visible face or child keeps the whole
        # instance, so probing its other faces cannot change the removal result.
        if (obj.get('protected') or (mode == 'enclosure' and obj.get('certificate'))
                or (obj.get('prop') and (obj.get('has_children') or not eligible[a:b].all()))):
            eligible[a:b] = False
    return eligible


def w_certify(triangles, eligible, hulls, samples, burial_margin_studs=.3):
    import numpy as np
    from scipy.spatial import cKDTree
    centres = triangles.mean(1)
    tree = cKDTree(centres)
    low, high = triangles.min(1), triangles.max(1)
    certified = np.zeros(len(triangles), bool)
    certificate = np.full(len(triangles), -1, np.int32)
    skipped = []
    # Parent validates the real opaque collider covers this intact hull within
    # .11 stud. At least .3 stud exceeds that tolerance plus its .1-stud inset.
    # The solid retained hull is the proof; finite voxel sampling is not.
    margin = .28 * max(.3, burial_margin_studs)
    for i, hull in enumerate(hulls):
        # A camera sample inside an enclosure invalidates its universal claim.
        near = ((samples >= hull["lo"]) & (samples <= hull["hi"])).all(1)
        if near.any() and w_inside(samples[near], hull).any():
            skipped.append(hull.get("name", str(i)))
            continue
        c = (hull["lo"] + hull["hi"]) / 2
        radius = np.linalg.norm(hull["hi"] - hull["lo"]) / 2
        ids = np.asarray(tree.query_ball_point(c, radius), dtype=np.int64)
        if not len(ids):
            continue
        ids = ids[eligible[ids] & ~certified[ids]]
        ids = ids[((low[ids] >= hull["lo"] + margin) & (high[ids] <= hull["hi"] - margin)).all(1)]
        for start in range(0, len(ids), 4096):
            batch = ids[start:start+4096]
            good = w_inside(triangles[batch].reshape(-1, 3), hull, margin).reshape(-1, 3).all(1)
            accepted = batch[good]
            certified[accepted] = True
            certificate[accepted] = i
    return certified, certificate, dict(certified_triangles=int(certified.sum()), certificate_margin_studs=margin/.28,
                                         certificate_hulls_rejected_for_camera_interior=skipped)


def w_face_ids(objects, polygon_ids):
    import numpy as np
    face_ids = np.full(len(polygon_ids), -1, np.int64)
    offset = 0
    for obj in objects:
        start, end = obj["start"], obj["end"]
        if not 0 <= start <= end <= len(polygon_ids) or np.any(face_ids[start:end] != -1):
            raise ValueError("invalid/overlapping exported object triangle ranges")
        ids = polygon_ids[start:end]
        if len(ids) and np.any(ids < 0):
            if not obj.get('protected') or not obj['name'].startswith('INSTANCE:'):
                raise ValueError("negative exported polygon ID")
            ids = np.arange(len(ids), dtype=np.int64)  # immutable generated instances only
        face_ids[start:end] = ids + offset
        offset += max(int(ids.max())+1 if len(ids) else 0, int(obj.get("polygons", 0)))
    if np.any(face_ids < 0):
        raise ValueError("exported object ranges do not cover every triangle")
    return face_ids


def w_verify(accel, triangles, candidates, samples, transparent, face_ids=None):
    """For each all-triangle-candidate polygon, probe centre + 2%-inset vertices from every
    sample within 40 studs AND the 64 nearest samples. Any clear/uncertain ray
    preserves the polygon. Every nominated polygon receives the exact checks.
    """
    import numpy as np
    from scipy.spatial import cKDTree
    tree = cKDTree(samples)
    if face_ids is None:
        face_ids = np.arange(len(triangles), dtype=np.int64)
    totals = np.bincount(face_ids)
    candidate_totals = np.bincount(face_ids[candidates], minlength=len(totals))
    whole_faces = (candidate_totals > 0) & (candidate_totals == totals)
    removable = candidates & whole_faces[face_ids]
    ids = np.flatnonzero(removable)
    order = np.argsort(face_ids[ids], kind="stable")
    ids = ids[order]
    face_numbers, starts, counts = np.unique(face_ids[ids], return_index=True, return_counts=True)
    rays = queries = kept = bad_count = 0
    kept_triangles = 0
    for position, (face_number, start, count) in enumerate(zip(face_numbers, starts, counts)):
        triangle_ids = ids[start:start+count]
        vertices = np.unique(triangles[triangle_ids].reshape(-1, 3), axis=0)
        centre = vertices.mean(0)
        _, nearest = tree.query(centre, k=min(64, len(samples)))
        near = tree.query_ball_point(centre, 40*.28)
        sample_ids = np.union1d(np.atleast_1d(nearest), near).astype(np.int64)
        targets = np.vstack((centre, vertices*.98 + centre*.02))
        n_targets = len(targets)
        visible = False
        for start in range(0, len(sample_ids), 2048):
            origins = np.repeat(samples[sample_ids[start:start+2048]], n_targets, axis=0)
            target = np.tile(targets, (len(origins)//n_targets, 1))
            directions = target - origins
            length = np.linalg.norm(directions, axis=1)
            rays += len(origins)
            if np.any(length < 1e-5) or not np.isfinite(length).all():
                visible = True
                bad_count += 1
                break
            directions /= length[:, None]
            hit, distance, bad, nq = w_first_opaque(accel, origins, directions, transparent)
            queries += nq
            # A miss, target hit, endpoint neighbour or continuation uncertainty
            # is a clear/uncertain sight line. Tolerance errs toward preservation.
            target_hit = (hit >= 0)
            target_hit[target_hit] &= face_ids[hit[target_hit]] == face_number
            if np.any(bad | (hit < 0) | target_hit | (distance >= length - .001)):
                visible = True
                bad_count += int(bad.sum())
                break
        if visible:
            removable[triangle_ids] = False
            kept += 1
            kept_triangles += len(triangle_ids)
        if position % 2000 == 0:
            print("worker verify polygons", position, "/", len(face_numbers), "kept", kept, "rays", rays, flush=True)
    return removable, dict(exact_candidate_triangles=int(len(ids)), exact_sightline_tests=rays,
                            exact_candidate_polygons=int(len(face_numbers)),
                            embree_exact_queries=queries, exact_visible_candidates_kept=kept,
                            exact_visible_candidate_triangles_kept=kept_triangles,
                            exact_uncertain_rays_kept=bad_count, exact_nearest_samples=64,
                            exact_radius_studs=40, exact_targets="polygon centre and all unique polygon vertices pulled 2% inward")


def w_self_check():
    import numpy as np
    from embreex.rtcore_scene import EmbreeScene
    from embreex.mesh_construction import TriangleMesh
    assert np.allclose(w_rb([23001, 2, 3]), [.28, -.84, .56])
    box = {"cf": [23000, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1], "s": [4, 4, 4]}
    inside = np.zeros((8, 8, 8), bool)
    w_raster(inside, np.array([-4, -4, -4]), box, "inner")
    assert inside.sum() == 64
    hull = w_hulls([{"lo": [-1, -1, -1], "hi": [1, 1, 1], "name": "box"}])[0]
    assert w_inside([[0, 0, 0]], hull, .28)[0]
    assert not w_inside([[.9, 0, 0]], hull, .28)[0]
    tri = np.array([[[-.5, -.5, 0], [.5, -.5, 0], [0, .5, 0]]], np.float32)
    accel = EmbreeScene()
    mesh = TriangleMesh(accel, tri)
    hits, dist, bad, _ = w_first_opaque(accel, np.array([[0, 0, 1]], np.float32),
                                      np.array([[0, 0, -1]], np.float32), np.array([False]))
    assert hits[0] == 0 and abs(dist[0]-1) < 1e-5 and not bad[0]
    hits, dist, bad, _ = w_first_opaque(accel, np.array([[0, 0, 1]], np.float32),
                                      np.array([[0, 0, -1]], np.float32), np.array([True]))
    assert hits[0] == -1 and not bad[0]
    samples = np.array([[0, 0, 1]], np.float32)
    remove, report = w_verify(accel, tri, np.array([True]), samples, np.array([False]))
    assert not remove[0] and report["exact_visible_candidates_kept"] == 1
    # A partially nominated two-triangle face cannot be removed as a polygon.
    remove, report = w_verify(accel, np.concatenate((tri, tri)), np.array([True, False]),
                              samples, np.array([False, False]), np.array([0, 0]))
    assert not remove.any() and report["exact_candidate_polygons"] == 0
    opaque = w_OpaqueAdapter(np.concatenate((tri, tri + [0, 0, -.5])), np.array([True, False]))
    hit, dist, bad, _ = w_first_opaque(opaque, samples, np.array([[0, 0, -1]], np.float32), np.array([True, False]))
    assert hit[0] == 1 and abs(dist[0]-1.5) < 1e-5 and not bad[0]
    # A real retained opaque shell hides a certified triangle; its universal
    # burial certificate and finite polygon probes must agree on this case.
    vertices = np.array([[-1,-1,-1], [1,-1,-1], [1,1,-1], [-1,1,-1],
                         [-1,-1,1], [1,-1,1], [1,1,1], [-1,1,1]], np.float32)
    faces = np.array([[0,1,2], [0,2,3], [4,6,5], [4,7,6], [0,4,5], [0,5,1],
                      [1,5,6], [1,6,2], [2,6,7], [2,7,3], [3,7,4], [3,4,0]])
    enclosed = np.concatenate((vertices[faces], tri))
    cand = np.zeros(len(enclosed), bool)
    cand[-1] = True
    samples_outside = np.array([[0,0,3], [3,0,0], [-3,0,0]], np.float32)
    cert, _, _ = w_certify(enclosed, cand, [hull], samples_outside)
    assert cert[-1] and cert.sum() == 1
    cube_opaque = w_OpaqueAdapter(enclosed, np.zeros(len(enclosed), bool))
    remove, _ = w_verify(cube_opaque, enclosed, cert, samples_outside, np.zeros(len(enclosed), bool))
    assert remove[-1] and remove.sum() == 1
    cert, _, _ = w_certify(enclosed, cand, [hull], np.array([[0,0,0]], np.float32))
    assert not cert.any()  # Camera inside the shell invalidates its claim.
    assert np.array_equal(w_face_ids([{"start": 0, "end": 2, "polygons": 1},
                                      {"start": 2, "end": 3, "polygons": 1}], np.array([0,0,0])), [0,0,1])
    assert np.array_equal(w_face_ids([{'name': 'INSTANCE:test', 'start': 0, 'end': 2, 'protected': True}],
                                    np.array([-1, -1])), [0, 1])
    behind = np.concatenate((tri, tri + [0, 0, -.5]))
    mask = w_eligible({'objects': [{'start': 0, 'end': 2}]}, np.array([True, False]), np.zeros(2, bool), 'visibility')
    opaque_wall = w_OpaqueAdapter(behind, np.zeros(2, bool))
    removal, _ = w_verify(opaque_wall, behind, mask, samples, np.zeros(2, bool))
    assert removal[1]  # Visibility needs no convex enclosure certificate.
    glass_wall = w_OpaqueAdapter(behind, np.array([True, False]))
    removal, _ = w_verify(glass_wall, behind, mask, samples, np.array([True, False]))
    assert not removal.any()  # Glass cannot hide a removal candidate.
    solid = np.zeros((8, 8, 10), bool)
    solid[:, :, 0] = True
    stand = w_standable(solid, solid)
    assert stand[3, 3, 1] and not stand[3, 3, 0]
    solid[3:5, 3:5, 4] = True
    stand = w_standable(solid, solid)
    assert not stand[3, 3, 1]
    props = {'objects': [{'start': 0, 'end': 2, 'prop': True}, {'start': 2, 'end': 3, 'prop': False}]}
    assert np.array_equal(w_eligible(props, np.array([True, False, False]), np.zeros(3, bool), 'visibility'), [False, False, True])
    assert w_eligible(props, np.zeros(3, bool), np.zeros(3, bool), 'visibility').all()
    print("worker self-check: coordinate/voxel/hull/transparent-ray/whole-polygon/opaque-certificate/headroom PASS", flush=True)


def worker_main(argv=None):
    import argparse, json, os, sys, time
    parser = argparse.ArgumentParser(description="Conservative Level 4 visibility worker")
    parser.add_argument("--worker")
    parser.add_argument("--seed", type=int, default=7007)
    parser.add_argument("--samples", type=int, default=3000)
    parser.add_argument("--directions", type=int, default=2048)
    parser.add_argument("--burial-margin-studs", type=float, default=.3)
    parser.add_argument("--mode", choices=("visibility", "enclosure"), default="visibility")
    parser.add_argument("--python-path", action="append", default=[])
    parser.add_argument("--self-check", action="store_true")
    args = parser.parse_args(argv)
    for path in reversed(args.python_path):
        sys.path.insert(0, path)
    if args.self_check:
        w_self_check()
        return
    if not args.worker:
        parser.error("--worker DIR is required")
    if args.samples < 3000 or args.directions < 2048:
        parser.error("full runs require >=3000 samples and >=2048 directions")
    if args.burial_margin_studs < .3:
        parser.error("burial margin must be at least .3 stud")
    import numpy as np
    from embreex.rtcore_scene import EmbreeScene
    from embreex.mesh_construction import TriangleMesh
    root = args.worker
    start = time.perf_counter()
    scene = json.load(open(os.path.join(root, "scene.json"), encoding="utf-8"))
    triangles = np.load(os.path.join(root, "triangles.npy"), mmap_mode="r")
    polygons = np.load(os.path.join(root, "triangle_polygons.npy"), mmap_mode="r")
    transparent = np.load(os.path.join(root, "transparent.npy")).astype(bool)
    if triangles.shape != (len(transparent), 3, 3) or len(polygons) != len(triangles):
        raise ValueError("inconsistent exported triangle/face/material arrays")
    if not np.isfinite(triangles).all():
        raise ValueError("nonfinite triangles: cull must keep all geometry")
    report = dict(seed=args.seed, status="running", triangle_count=len(triangles),
                  mode=args.mode, policy="unhit polygons with all exact probes occluded" if args.mode == 'visibility' else "certified opaque buried faces",
                  finite_sampling_is_not_universal_proof=True)
    timings = {}
    def checkpoint(stage):
        now = time.perf_counter()
        timings[stage] = round(now-start-sum(timings.values()), 3)
        report["timings_seconds"] = timings
        report["elapsed_seconds"] = round(now-start, 3)
        with open(os.path.join(root, "worker_report.json"), "w", encoding="utf-8") as stream:
            json.dump(report, stream, indent=2)
        print("worker", stage, timings[stage], "seconds", flush=True)
    samples, camera_report, hulls = w_camera(scene, triangles, args.samples, args.seed, root)
    np.save(os.path.join(root, "camera_samples.npy"), samples)
    report.update(camera_report)
    checkpoint("reachable_camera")
    extra_views = np.asarray(scene.get('visibility_extra_views', []), np.float32).reshape(-1, 3)
    if len(extra_views):
        if not np.isfinite(extra_views).all():
            raise ValueError('Nonfinite required visibility viewpoint')
        samples = np.unique(np.concatenate((samples, extra_views)), axis=0)
    report['additional_required_viewpoints'] = int(len(extra_views))
    report['visibility_viewpoints'] = int(len(samples))
    np.save(os.path.join(root, 'visibility_samples.npy'), samples)
    accel = EmbreeScene()
    mesh = TriangleMesh(accel, np.asarray(triangles, np.float32))
    opaque = w_OpaqueAdapter(triangles, transparent)
    checkpoint("bvh")
    seen, visibility_report = w_visibility(accel, opaque, samples, transparent, args.directions, args.seed)
    np.save(os.path.join(root, "visibility_seen.npy"), seen)
    report.update(visibility_report)
    checkpoint("visibility")
    eligible = w_eligible(scene, seen, transparent, args.mode)
    certified, certificate, cert_report = w_certify(triangles, eligible, hulls, samples, args.burial_margin_studs)
    np.save(os.path.join(root, "certified.npy"), certified)
    report.update(cert_report)
    report["unhit_uncertified_triangles_retained"] = int((eligible & ~certified).sum()) if args.mode == 'enclosure' else 0
    checkpoint("certification")
    if report["uncertain_opaque_visibility_rays"] or report["invalid_boxes"]:
        # An exhausted transparent traversal or invalid scene collider cannot be
        # used to justify visibility. Conservatively produce an unchanged mesh.
        remove = np.zeros(len(triangles), bool)
        report["global_uncertainty_keeps_all"] = True
        json_write(Path(root) / "cleanup.json", {"colliders": [], "lights": []})
    else:
        face_ids = w_face_ids(scene["objects"], polygons)
        remove, verify_report = w_verify(opaque, triangles, eligible if args.mode == 'visibility' else certified, samples, transparent, face_ids)
        report.update(verify_report)
        report["global_uncertainty_keeps_all"] = False
    np.save(os.path.join(root, "removable.npy"), remove)
    np.save(os.path.join(root, "certificates.npy"), certificate)
    report["removable_triangles"] = int(remove.sum())
    report["status"] = "complete"
    checkpoint("exact_verification")


if __name__ == '__main__':
    if '--worker' in sys.argv or '--self-check' in sys.argv:
        worker_main()
    else:
        blender_main()
