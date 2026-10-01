"""Export a verified-source lobby FBX candidate without changing its native file.

Factory-startup Blender only. Every export object owns independent mesh data,
one material and only AtlasUV, preventing the importer from selecting an older
authoring PaletteUV. Source .blend / manifest / binary chunks are read-only.
The caller round-trips the candidate before promoting it to the final filename.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys

import bpy


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    arguments = sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument('--source-blend', required=True)
    parser.add_argument('--manifest', required=True)
    parser.add_argument('--candidate', required=True)
    parser.add_argument('--receipt', required=True)
    args = parser.parse_args(arguments)
    source, manifest_path = Path(args.source_blend).resolve(), Path(args.manifest).resolve()
    destination, receipt_path = Path(args.candidate).resolve(), Path(args.receipt).resolve()
    if destination.suffix.lower() != '.fbx' or destination == source:
        raise ValueError('Candidate must be a distinct FBX file')
    if destination.exists():
        raise RuntimeError('Candidate already exists; choose a fresh reviewable filename')
    source_hash, manifest_hash = sha(source), sha(manifest_path)
    manifest = json.loads(manifest_path.read_text())
    if source_hash != manifest['sourceBlendSha256']:
        raise RuntimeError('Native source hash differs from the current export manifest')
    bpy.ops.wm.open_mainfile(filepath=str(source), load_ui=False)
    native_scene = bpy.data.scenes.get('Lobby Reimagined | Full Preview')
    if native_scene is None:
        raise RuntimeError('Native assembled preview scene is missing')
    source_meshes = [o for o in native_scene.objects if o.type == 'MESH']
    if len(source_meshes) != len(manifest['placements']):
        raise RuntimeError('Native mesh copies differ from the placement manifest')
    source_atlas = bpy.data.images.get('Lobby Preview | Color Wear Atlas')
    if source_atlas is None:
        raise RuntimeError('Native packed atlas is missing')
    # Packed images load lazily after open_mainfile; size/pixel access realizes
    # the archived data before checking has_data.
    atlas_size, atlas_pixels = list(source_atlas.size), len(source_atlas.pixels)
    if not source_atlas.has_data or atlas_size != [1024, 1024] or atlas_pixels != 4194304:
        raise RuntimeError('Native packed atlas is missing or invalid')
    export_scene = bpy.data.scenes.new('Lobby FBX | Independent AtlasUV Copies')
    export_scene.unit_settings.system = native_scene.unit_settings.system
    export_scene.unit_settings.scale_length = native_scene.unit_settings.scale_length
    bpy.context.window.scene = export_scene
    atlas_material = bpy.data.materials.new('LRP_FBX_Fallback_AtlasUV')
    atlas_material.use_nodes = True
    shader = next(n for n in atlas_material.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    shader.inputs['Roughness'].default_value = .67
    image_node = atlas_material.node_tree.nodes.new('ShaderNodeTexImage')
    image_node.image = source_atlas
    uv_node = atlas_material.node_tree.nodes.new('ShaderNodeUVMap')
    uv_node.uv_map = 'AtlasUV'
    atlas_material.node_tree.links.new(uv_node.outputs['UV'], image_node.inputs['Vector'])
    atlas_material.node_tree.links.new(image_node.outputs['Color'], shader.inputs['Base Color'])
    expected_triangles = manifest['instantiatedTriangles']
    actual_triangles = 0
    for index, source_obj in enumerate(source_meshes):
        mesh = source_obj.data.copy()
        mesh.name = f'LRP_FBX_IndependentMesh_{index:04d}'
        if mesh.uv_layers.get('AtlasUV') is None:
            raise RuntimeError('Source object lacks its authored wear-atlas UVs: ' + source_obj.name)
        for layer in list(mesh.uv_layers):
            if layer.name != 'AtlasUV':
                mesh.uv_layers.remove(layer)
        mesh.uv_layers.active_index = 0
        mesh.uv_layers[0].active_render = True
        mesh.materials.clear()
        mesh.materials.append(atlas_material)
        for face in mesh.polygons:
            face.material_index = 0
        mesh.calc_loop_triangles()
        actual_triangles += len(mesh.loop_triangles)
        obj = bpy.data.objects.new(f'LRP_FBX_{index:04d}_{source_obj.name}', mesh)
        obj.matrix_world = source_obj.matrix_world.copy()
        export_scene.collection.objects.link(obj)
    if actual_triangles != expected_triangles:
        raise RuntimeError('Candidate geometry differs from binary runtime mesh counts')
    if len({o.data.name for o in export_scene.objects}) != len(source_meshes):
        raise RuntimeError('Independent mesh copy invariant failed')
    # Select only this isolated export scene; no source-scene objects are touched.
    for obj in export_scene.objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = next(iter(export_scene.objects))
    destination.parent.mkdir(parents=True, exist_ok=True)
    result = bpy.ops.export_scene.fbx(filepath=str(destination), use_selection=True,
        object_types={'MESH'}, axis_forward='-Z', axis_up='Y', global_scale=1,
        apply_unit_scale=True, bake_anim=False, use_mesh_modifiers=True,
        path_mode='COPY', embed_textures=True, add_leaf_bones=False)
    if result != {'FINISHED'}:
        raise RuntimeError('FBX export did not finish: ' + str(result))
    if sha(source) != source_hash or sha(manifest_path) != manifest_hash:
        raise RuntimeError('Source or manifest changed during fallback export; do not promote the candidate')
    receipt = {
        'schema': 'lobby-reimagined-fbx-candidate/1', 'blender_version': bpy.app.version_string,
        'source_blend': str(source), 'source_blend_sha256': source_hash,
        'manifest': str(manifest_path), 'manifest_sha256': manifest_hash,
        'candidate': str(destination), 'candidate_sha256': sha(destination),
        'candidate_bytes': destination.stat().st_size,
        'mesh_objects': len(source_meshes), 'unique_export_meshes': len(source_meshes),
        'triangles': actual_triangles, 'uv_layers_per_mesh': 1,
        'uv_layer_name': 'AtlasUV', 'material_slots_per_mesh': 1,
        'texture_route': 'AtlasUV -> packed Color Wear Atlas -> Principled Base Color',
        'source_manifest_chunks_unchanged': True,
        'candidate_requires_roundtrip_before_promotion': True,
    }
    receipt_path.parent.mkdir(parents=True, exist_ok=True)
    receipt_path.write_text(json.dumps(receipt, indent=2)+'\n')
    print(json.dumps(receipt, indent=2), flush=True)


if __name__ == '__main__':
    main()
