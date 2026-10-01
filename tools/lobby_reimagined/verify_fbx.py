"""Isolated Blender FBX round-trip audit; no live app or source-place mutation.

Run Blender --background --factory-startup --python this_file -- --fbx FILE
--manifest FILE --report FILE. The FBX is imported into a fresh local scene.
Reports actual meshes, tessellated triangles, UVs, material-index validity and
connected image routes. This verifies a downloadable fallback, not Roblox FPS.
"""

from __future__ import annotations

import argparse
import base64
from collections import Counter
import hashlib
import json
import math
from pathlib import Path
import sys
import struct

import bpy
from mathutils import Matrix, Vector


def main():
    arguments = sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument('--fbx', required=True)
    parser.add_argument('--manifest', required=True)
    parser.add_argument('--report', required=True)
    args = parser.parse_args(arguments)
    fbx, manifest_path = Path(args.fbx).resolve(), Path(args.manifest).resolve()
    source_hash = hashlib.sha256(fbx.read_bytes()).hexdigest()
    manifest_bytes = manifest_path.read_bytes()
    manifest_hash = hashlib.sha256(manifest_bytes).hexdigest()
    manifest = json.loads(manifest_bytes)
    # Fresh standalone scene; never reset the user's running Blender instance.
    scene = bpy.data.scenes.new('Lobby FBX | isolated round-trip verification')
    bpy.context.window.scene = scene
    result = bpy.ops.import_scene.fbx(filepath=str(fbx), use_anim=False)
    if result != {'FINISHED'}:
        raise RuntimeError('FBX importer did not finish: ' + str(result))
    meshes = [o for o in scene.objects if o.type == 'MESH']
    expected_triangles = {r['family']: r['triangles'] for r in manifest['chunks']}
    expected_counts = Counter(expected_triangles[p['family']] for p in manifest['placements'])
    prefab_points = {}
    for chunk in manifest['chunks']:
        wire = base64.b64decode((manifest_path.parent/chunk['file']).read_bytes())
        if hashlib.sha256(wire).hexdigest() != chunk['sha256']:
            raise RuntimeError('Prefab chunk changed or hash mismatch: ' + chunk['family'])
        magic, nv, nn, nu, nf = struct.unpack_from('<5I', wire)
        if magic != 0x364D564C or nv != chunk['vertices'] or nf != chunk['triangles']:
            raise RuntimeError('Unexpected binary prefab header: ' + chunk['family'])
        points = [struct.unpack_from('<3f', wire, 20+i*12) for i in range(nv)]
        center = chunk['center']
        # Binary is Roblox X,Z,-Y. Convert centered points back to Blender XYZ.
        prefab_points[chunk['family']] = [Vector((p[0]+center[0],
                                            -(p[2]+center[2]), p[1]+center[1])) for p in points]
    def bounds(points):
        return tuple(min(p[i] for p in points) for i in range(3)) + \
               tuple(max(p[i] for p in points) for i in range(3))
    expected_placements = []
    for item in manifest['placements']:
        x, z, minusy = item['robloxPosition']
        position = Vector((x, -minusy, z))
        rotation = Matrix.Rotation(item.get('yaw', 0), 3, 'Z')
        transformed = [position + rotation @ p for p in prefab_points[item['family']]]
        expected_placements.append({'family': item['family'], 'triangles': expected_triangles[item['family']],
                                    'bounds': bounds(transformed)})
    actual_counts = Counter()
    actual_placements = []
    records, materials, images = [], {}, {}
    for obj in meshes:
        mesh = obj.data
        mesh.calc_loop_triangles()
        triangles = len(mesh.loop_triangles)
        actual_counts[triangles] += 1
        world_bounds = bounds([obj.matrix_world @ vertex.co for vertex in mesh.vertices])
        actual_placements.append({'object': obj.name, 'triangles': triangles, 'bounds': world_bounds})
        valid_indices = all(0 <= p.material_index < len(mesh.materials)
                            and mesh.materials[p.material_index] is not None
                            for p in mesh.polygons)
        uv = mesh.uv_layers.active
        valid_uv = uv is not None and len(uv.data) == len(mesh.loops)
        if valid_uv:
            valid_uv = all(math.isfinite(c) and -.00001 <= c <= 1.00001
                           for loop in uv.data for c in loop.uv)
        for mat in mesh.materials:
            if mat is None:
                continue
            if mat.name not in materials:
                route = []
                uv_routes = []
                if mat.use_nodes:
                    shaders = [n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED']
                    for shader in shaders:
                        pending = [link.from_node for link in shader.inputs['Base Color'].links]
                        seen = set()
                        while pending:
                            node = pending.pop()
                            if node in seen:
                                continue
                            seen.add(node)
                            if node.type == 'TEX_IMAGE' and node.image:
                                image = node.image
                                route.append(image.name)
                                uv_routes.extend(link.from_node.uv_map for link in node.inputs['Vector'].links
                                                 if link.from_node.type == 'UVMAP')
                                path = Path(bpy.path.abspath(image.filepath)) if image.filepath else None
                                images[image.name] = {
                                    'size': list(image.size), 'channels': image.channels,
                                    'has_data': image.has_data,
                                    'packed': bool(image.packed_file), 'filepath': str(path) if path else None,
                                    'file_exists': bool(path and path.is_file()),
                                    'file_sha256': hashlib.sha256(path.read_bytes()).hexdigest()
                                    if path and path.is_file() else None,
                                }
                            pending.extend(link.from_node for socket in node.inputs for link in socket.links)
                materials[mat.name] = {'base_color_image_routes': sorted(set(route)),
                                      'image_explicit_uv_maps': sorted(set(uv_routes))}
        records.append({'object': obj.name, 'mesh': mesh.name, 'vertices': len(mesh.vertices),
                        'triangles': triangles, 'material_slots': len(mesh.materials),
                        'world_bounds_xyz': list(world_bounds),
                        'material_indices_valid': valid_indices, 'uvs_valid': valid_uv,
                        'uv_layers': [layer.name for layer in mesh.uv_layers],
                        'active_uv': uv.name if uv else None,
                        'render_uv': next((layer.name for layer in mesh.uv_layers if layer.active_render), None),
                        'material_names': [m.name if m else None for m in mesh.materials]})
    assigned_materials = {m.name for o in meshes for m in o.data.materials if m}
    all_routes_valid = all(materials[name]['base_color_image_routes'] for name in assigned_materials)
    image_routes_valid = bool(images) and all(image['has_data'] and image['size'] == [1024, 1024]
                         and (image['packed'] or image['file_exists']) for image in images.values())
    bad_texture_uv_objects = []
    for record in records:
        for name in record['material_names']:
            if name is None:
                continue
            explicit_uvs = materials[name]['image_explicit_uv_maps']
            if explicit_uvs:
                valid = all(uv_name == 'AtlasUV' and uv_name in record['uv_layers'] for uv_name in explicit_uvs)
            else:
                valid = record['render_uv'] == 'AtlasUV'
            if not valid:
                bad_texture_uv_objects.append(record['object'])
                break
    # Pair equal-triangle-count placements by actual float bounds. Rounded-string
    # equality would falsely reject valid bounds straddling a .0005 rounding tie.
    candidates = []
    for ei, expected in enumerate(expected_placements):
        for ai, actual in enumerate(actual_placements):
            if expected['triangles'] != actual['triangles']:
                continue
            error = max(abs(a-b) for a, b in zip(expected['bounds'], actual['bounds']))
            if error <= .001:
                candidates.append((error, ei, ai))
    expected_matched, actual_matched, errors = set(), set(), []
    for error, ei, ai in sorted(candidates):
        if ei not in expected_matched and ai not in actual_matched:
            expected_matched.add(ei)
            actual_matched.add(ai)
            errors.append(error)
    placements_match = (len(expected_matched) == len(expected_placements)
                        and len(actual_matched) == len(actual_placements))
    report = {
        'schema': 'lobby-reimagined-fbx-roundtrip/1', 'blender_version': bpy.app.version_string,
        'fbx': str(fbx), 'fbx_sha256': source_hash, 'fbx_bytes': fbx.stat().st_size,
        'manifest': str(manifest_path), 'manifest_sha256': manifest_hash,
        'source_blend_sha256_recorded': manifest['sourceBlendSha256'],
        'expected_objects': len(manifest['placements']), 'actual_mesh_objects': len(meshes),
        'unique_mesh_datablocks': len({o.data.name for o in meshes}),
        'expected_triangles': manifest['instantiatedTriangles'],
        'actual_triangles': sum(r['triangles'] for r in records),
        'triangle_count_multiset_matches': expected_counts == actual_counts,
        'world_placement_bounds_match_001_stud': placements_match,
        'largest_matched_placement_bound_error_studs': max(errors) if errors else None,
        'missing_or_changed_placement_bounds': [item for i, item in enumerate(expected_placements)
                                               if i not in expected_matched],
        'unexpected_placement_bounds': [item for i, item in enumerate(actual_placements)
                                        if i not in actual_matched],
        'all_geometry_material_indices_valid': all(r['material_indices_valid'] for r in records),
        'all_geometry_uvs_valid': all(r['uvs_valid'] for r in records),
        'all_assigned_materials_route_base_color_to_image': all_routes_valid,
        'connected_images_valid': image_routes_valid,
        'all_texture_routes_use_AtlasUV': not bad_texture_uv_objects,
        'bad_texture_uv_objects': bad_texture_uv_objects,
        'images': images, 'materials': materials, 'objects': records,
        'source_fbx_changed_during_inspection': hashlib.sha256(fbx.read_bytes()).hexdigest() != source_hash,
        'source_manifest_changed_during_inspection': hashlib.sha256(manifest_path.read_bytes()).hexdigest() != manifest_hash,
        'limitations': ['No Studio mesh-import or Roblox performance result is inferred.',
                        'FBX excludes native Studio text, queue controls, real launch logic and collision proxies.'],
    }
    report['passed'] = (len(meshes) == report['expected_objects'] and
                        report['actual_triangles'] == report['expected_triangles'] and
                        report['triangle_count_multiset_matches'] and
                        report['world_placement_bounds_match_001_stud'] and
                        report['all_geometry_material_indices_valid'] and
                        report['all_geometry_uvs_valid'] and all_routes_valid and image_routes_valid and
                        report['all_texture_routes_use_AtlasUV'] and
                        not report['source_fbx_changed_during_inspection'] and
                        not report['source_manifest_changed_during_inspection'])
    target = Path(args.report).resolve()
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps({k: v for k, v in report.items() if k not in {'objects', 'materials', 'images'}}, indent=2), flush=True)
    if not report['passed']:
        raise RuntimeError('FBX round-trip audit failed; inspect ' + str(target))


if __name__ == '__main__':
    main()
