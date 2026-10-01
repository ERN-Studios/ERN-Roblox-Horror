"""Export revised reusable kit with PBR PNG sidecars; no Studio operations."""
from __future__ import annotations

import bpy
import bmesh
import hashlib
import importlib.util
import json
import os
import shutil
from pathlib import Path
from mathutils import Matrix

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'artifacts/level6-blender-revision-20260930'
EXPORT = Path(os.environ.get('LEVEL6_REVISION_EXPORT_DIR', ROOT / 'artifacts/level6-studio-revision-20261001/exports-portal14')).resolve()
PROP_ATLAS = OUT / 'materials/props/color-1024.png'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def load_helpers():
    spec = importlib.util.spec_from_file_location('revision_build_helpers', Path(__file__).with_name('revision_build.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def bake_red_color(source_material, helper):
    """Bake the red wall color variant, so FBX requires no procedural nodes."""
    destination = EXPORT / 'red-wall-color-1024.png'
    scene = bpy.data.scenes.new('Export bake | red wall albedo')
    bpy.context.window.scene = scene
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 1
    material = source_material.copy()
    material.name = 'L6R_red_wall_bake'
    nodes, links = material.node_tree.nodes, material.node_tree.links
    shader = next(n for n in nodes if n.type == 'BSDF_PRINCIPLED')
    original = next(l for l in links if l.to_socket == shader.inputs['Base Color']).from_socket
    emit = nodes.new('ShaderNodeEmission')
    links.new(original, emit.inputs['Color'])
    output = next(n for n in nodes if n.type == 'OUTPUT_MATERIAL')
    links.new(emit.outputs[0], output.inputs['Surface'])
    image = bpy.data.images.new('L6R_RedWall_ExportColor', width=1024, height=1024)
    image.colorspace_settings.name = 'sRGB'
    target = nodes.new('ShaderNodeTexImage')
    target.image = image
    nodes.active = target
    mesh = bpy.data.meshes.new('Red albedo baking plane')
    mesh.from_pydata([(0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0)], [], [(0, 1, 2, 3)])
    uv = mesh.uv_layers.new(name='SurfaceUV')
    for loop, value in enumerate([(0, 0), (1, 0), (1, 1), (0, 1)]):
        uv.data[loop].uv = value
    obj = bpy.data.objects.new('Red albedo baking plane', mesh)
    scene.collection.objects.link(obj)
    mesh.materials.append(material)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.bake(type='EMIT', margin=0, use_clear=True)
    image.filepath_raw = str(destination)
    image.file_format = 'PNG'
    image.save()
    image.pack()
    return destination, image


def export_material(original, helper, red_image):
    copy = original.copy()
    copy.name = original.name + '_Export'
    identifier = original.get('l6_surface_id')
    if identifier:
        nodes, links = copy.node_tree.nodes, copy.node_tree.links
        shader = next(n for n in nodes if n.type == 'BSDF_PRINCIPLED')
        for link in list(links):
            if link.to_socket == shader.inputs['Base Color']:
                links.remove(link)
        color = nodes.new('ShaderNodeTexImage')
        color.image = red_image if original.get('l6_color_variant') else helper.image(
            OUT / helper.SURFACES[identifier]['maps']['color'])
        uv = next(n for n in nodes if n.type == 'UVMAP')
        links.new(uv.outputs['UV'], color.inputs['Vector'])
        links.new(color.outputs['Color'], shader.inputs['Base Color'])
    else:
        runtime_atlas = helper.image(PROP_ATLAS)
        for node in copy.node_tree.nodes:
            if node.type == 'TEX_IMAGE':
                node.image = runtime_atlas
    # Keep only the connected export shader. This avoids packing full-resolution
    # archival colors and authoring-only height maps into the import kit twice.
    nodes = copy.node_tree.nodes
    keep = {node for node in nodes if node.type == 'OUTPUT_MATERIAL'}
    stack = list(keep)
    while stack:
        node = stack.pop()
        for socket in node.inputs:
            for link in socket.links:
                if link.from_node not in keep:
                    keep.add(link.from_node)
                    stack.append(link.from_node)
    for node in list(nodes):
        if node not in keep:
            nodes.remove(node)
    return copy


def main():
    EXPORT.mkdir(parents=True, exist_ok=True)
    PROP_ATLAS.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(ROOT / 'artifacts/level6-textures-20260930/candidate/textures/WornParty_Level3Reference_Atlas1024.png', PROP_ATLAS)
    source = Path(os.environ.get('LEVEL6_REVISION_SOURCE', ROOT / 'artifacts/level6-studio-revision-20261001/StudioImport_Portal14_Full_Seed101.blend')).resolve()
    source_hash = sha(source)
    helper = load_helpers()
    red_path, red_image = bake_red_color(bpy.data.materials['L6_red_wall'], helper)
    scene = bpy.data.scenes.new('Roblox import | revised reusable Level 6 kit')
    bpy.context.window.scene = scene
    scene.unit_settings.scale_length = 1
    materials = {}
    chunks = []
    for index, col in enumerate(sorted((c for c in bpy.data.collections if c.name.startswith('L6K_')), key=lambda c: c.name)):
        parts = helper.realize_collection(col, Matrix.Identity(4), scene.collection, col.name)
        groups = {}
        for obj in parts:
            assert len(obj.data.materials) == 1, (obj.name, len(obj.data.materials))
            original = obj.data.materials[0]
            materials.setdefault(original.name, export_material(original, helper, red_image))
            obj.data.materials[0] = materials[original.name]
            groups.setdefault(original.name, []).append(obj)
        for material_name, objects in groups.items():
            bpy.ops.object.select_all(action='DESELECT')
            for obj in objects:
                obj.select_set(True)
            bpy.context.view_layer.objects.active = objects[0]
            if len(objects) > 1:
                bpy.ops.object.join()
            obj = bpy.context.view_layer.objects.active
            mat = obj.data.materials[0]
            obj.name = col.name + '__' + mat.name.removesuffix('_Export').removeprefix('L6_')
            obj.location = ((index % 8) * 110, (index // 8) * 95, 0)
            obj.data.calc_loop_triangles()
            # FBX cannot emit tangent space for n-gons. Triangulate the export
            # copy explicitly; source/library/normal relief geometry is intact.
            bm = bmesh.new()
            bm.from_mesh(obj.data)
            bmesh.ops.triangulate(bm, faces=list(bm.faces))
            bm.to_mesh(obj.data)
            bm.free()
            obj.data.update()
            obj.data.calc_loop_triangles()
            triangles = len(obj.data.loop_triangles)
            assert triangles <= 20000, (obj.name, triangles)
            uv = obj.data.uv_layers.active
            assert uv
            obj.data.calc_tangents(uvmap=uv.name)
            bounds = [min(v.uv[a] for v in uv.data) for a in range(2)] + [max(v.uv[a] for v in uv.data) for a in range(2)]
            assert min(bounds) >= -1e-5 and max(bounds) <= 1.00001, (obj.name, bounds)
            surface = mat.get('l6_surface_id')
            maps = dict(helper.SURFACES[surface]['maps']) if surface else {'color': str(PROP_ATLAS.relative_to(OUT))}
            if mat.get('l6_color_variant'):
                # The original red bake is byte-identical and its image was
                # already routed/uploaded; keep that stable material source.
                assert sha(red_path) == sha(OUT / 'exports/red-wall-color-1024.png')
                maps['color'] = 'exports/red-wall-color-1024.png'
            chunks.append({'asset': col.name.removeprefix('L6K_'), 'object': obj.name,
                           'material': mat.name, 'surface': surface, 'maps': maps,
                           'vertices': len(obj.data.vertices), 'triangles': triangles,
                           'uvLayer': uv.name, 'uvBounds': bounds, 'triangulated': True,
                           'showroomXYZ': list(obj.location),
                           'localBoundingBoxXYZ': [list(v) for v in obj.bound_box],
                           'repeatStuds': mat.get('l6_physical_repeat_studs'),
                           'normalConvention': 'OpenGL +Y tangent space' if surface else None})
    bpy.ops.object.select_all(action='SELECT')
    fbx = EXPORT / 'Level6_Revised_ReusableKit.fbx'
    bpy.ops.export_scene.fbx(filepath=str(fbx), use_selection=True, object_types={'MESH'},
                             axis_forward='-Z', axis_up='Y', global_scale=1,
                             apply_unit_scale=True, bake_anim=False,
                             use_tspace=True, mesh_smooth_type='FACE',
                             use_mesh_modifiers=True, path_mode='RELATIVE',
                             add_leaf_bones=False)
    # A self-contained kit-only Blender file. The editable full revision remains
    # a separate source, and the export file doesn't duplicate its 35 rooms.
    bpy.data.libraries.write(str(EXPORT / 'Level6_Revised_ImportKit.blend'),
                             {scene}, fake_user=False, compress=True)
    record = {'schemaVersion': 1, 'sourceBlendSha256': source_hash,
              'fbx': os.path.relpath(fbx, OUT), 'fbxSha256': sha(fbx),
              'importKitBlend': os.path.relpath(EXPORT / 'Level6_Revised_ImportKit.blend', OUT),
              'importKitBlendSha256': sha(EXPORT / 'Level6_Revised_ImportKit.blend'),
              'kitCollections': len({r['asset'] for r in chunks}),
              'meshObjects': len(chunks), 'totalUniqueTriangles': sum(r['triangles'] for r in chunks),
              'maximumTrianglesPerMesh': max(r['triangles'] for r in chunks),
              'axisMapping': '(x,y,z) -> (x,z,-y)', 'studsPerUnit': 1,
              'tangentsExportRequested': True, 'redWallColorBaked': os.path.relpath(red_path, OUT),
              'redWallColorSha256': sha(red_path), 'sourceBlendUnchanged': sha(source) == source_hash,
              'studioImportVerified': False, 'meshes': chunks,
              'limitations': ['PBR sidecars present; actual Studio import/assignment is unverified.',
                              'Reusable kit showroom layout is not a runtime generator installation.',
                              'Existing collision/light/CD/AI controller data require a fresh Studio reconciliation.']}
    assert record['sourceBlendUnchanged']
    (EXPORT / 'import-manifest.json').write_text(json.dumps(record, indent=2) + '\n')
    print('LEVEL6_REVISION_EXPORTED', json.dumps({k: v for k, v in record.items() if k != 'meshes'}), flush=True)


if __name__ == '__main__':
    main()
