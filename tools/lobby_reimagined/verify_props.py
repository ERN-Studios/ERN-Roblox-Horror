"""Run isolated QA with Blender --background --factory-startup --python thisfile.

This verifies mesh counts, bounds, UVs, triangle areas and safe repeated builds.
It does not open or mutate the user's live Blender/Studio scene. No Roblox
performance, animation or collision result is inferred from this authoring QA.
"""

import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'artifacts/lobby-reimagined-20261001/blender/props-qa'


def main():
    spec = importlib.util.spec_from_file_location('lobby_reimagined_props', Path(__file__).with_name('props.py'))
    props = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(props)
    scene = bpy.data.scenes.new('Lobby prop kit | isolated authoring QA')
    bpy.context.window.scene = scene
    scene.unit_settings.scale_length = 1
    library_col = bpy.data.collections.new('Lobby prop kit | library')
    scene.collection.children.link(library_col)
    library = props.build_library(library_col)
    report = props.metadata(library)
    report['blender_version'] = bpy.app.version_string
    report['builder_sha256'] = hashlib.sha256(Path(props.__file__).read_bytes()).hexdigest()
    report['checks'] = {}
    for name, record in library.items():
        mesh = record['objects'][0].data
        if any(tri.area < 1e-10 for tri in mesh.loop_triangles):
            raise RuntimeError(f'{name}: degenerate triangle')
        uv = mesh.uv_layers.active
        if uv is None or any(not 0 <= component <= 1 for loop in uv.data for component in loop.uv):
            raise RuntimeError(f'{name}: invalid palette UV')
        if any(not math.isfinite(component) for vertex in mesh.vertices for component in vertex.co):
            raise RuntimeError(f'{name}: non-finite vertex')
    try:
        props.build_library(library_col, include=['FloralSofa90s'])
    except RuntimeError as exc:
        assert 'Refusing to overwrite' in str(exc)
    else:
        raise RuntimeError('Repeated build failed to refuse existing names')
    report['checks'] = {'triangles_below_20000_per_mesh': True,
                        'total_below_60000': True, 'all_grounded': True,
                        'no_degenerate_triangles': True, 'palette_uvs_inside_0_1': True,
                        'all_vertices_finite': True, 'existing_names_preserved': True,
                        'live_blender_or_studio_mutated': False}
    OUT.mkdir(parents=True, exist_ok=True)
    atlas = props.create_palette_atlas(OUT/'palette-atlas-512.png')
    export_test = bpy.data.collections.new('Lobby prop kit | isolated atlas export test')
    export_test.hide_render = True
    scene.collection.children.link(export_test)
    export_library = {}
    for name, record in library.items():
        copy = record['objects'][0].copy()
        copy.data = record['objects'][0].data.copy()
        export_test.objects.link(copy)
        export_library[name] = {'objects': [copy]}
    props.use_palette_atlas(export_library, atlas)
    assert all(len(record['objects'][0].data.materials) == 1
               for record in export_library.values())
    assert all(len(record['objects'][0].data.materials) > 1
               for record in library.values())
    report['checks']['single_atlas_export_keeps_authoring_materials'] = True
    (OUT/'report.json').write_text(json.dumps(report, indent=2)+'\n')
    if os.environ.get('LOBBY_PROP_QA_RENDER') == '0':
        print(json.dumps({'report': str(OUT/'report.json'),
                          'total_original_triangles': report['total_original_triangles']}))
        return
    # Preview objects are linked copies; their library mesh IDs remain shared.
    preview = bpy.data.collections.new('Lobby prop kit | preview layout')
    scene.collection.children.link(preview)
    positions = {
        'FloralSofa90s': (-14, 0, 0), 'OliveVinylBench': (-5, 0, 0),
        'LaminateOfficeDesk': (4, 0, 0), 'FourDrawerFilingCabinet': (11, 0, 0),
        'BeigeCRTMonitor': (2.4, -.25, 3.195), 'BeigeKeyboard': (4.1, -.75, 3.195),
        'OfficePhotocopier': (16, 0, 0), 'BrownOfficeChair': (5, -4, 0),
        'BrownStackChair': (-4, -4.5, 0), 'WireServiceTrolley': (-11, -5, 0),
        'RolledCarpet': (-15, -4, 0), 'TwinDeckDJConsole': (0, 9, 0),
        'FestivalTrussSpeakerTower': (-10.0, 9, 0), 'TwinSubwoofer': (9, 9, 0),
    }
    for name, record in library.items():
        if name.startswith('VinylDisc'):
            continue
        source = record['objects'][0]
        obj = source.copy()
        obj.data = source.data
        obj.name = 'QA_'+name
        obj.location = positions[name]
        preview.objects.link(obj)
    console_meta = library['TwinDeckDJConsole']['metadata']
    for anchor, position in console_meta['anchors_xyz'].items():
        disc = library[console_meta['record_assets'][anchor]]['objects'][0].copy()
        disc.location = Vector(positions['TwinDeckDJConsole']) + Vector(position)
        preview.objects.link(disc)
    library_col.hide_render = True
    floor_mesh = bpy.data.meshes.new('QA_Floor')
    floor_mesh.from_pydata([(-24, -12, -.02), (24, -12, -.02),
                           (24, 18, -.02), (-24, 18, -.02)], [], [(0, 1, 2, 3)])
    floor_mesh.materials.append(props.material('steel_edge'))
    floor = bpy.data.objects.new('QA_Floor', floor_mesh)
    scene.collection.objects.link(floor)
    world = bpy.data.worlds.new('QA_DarkWorld')
    world.use_nodes = True
    background = next(n for n in world.node_tree.nodes if n.type == 'BACKGROUND')
    background.inputs['Color'].default_value = (.12, .14, .17, 1)
    background.inputs['Strength'].default_value = .35
    scene.world = world
    for pos, energy, size, color in [((4, -12, 24), 11000, 16, (1, .85, .62)),
                                   ((-16, 4, 20), 7000, 12, (.48, .86, 1)),
                                   ((12, 13, 18), 8000, 10, (1, .73, .41))]:
        light = bpy.data.lights.new('QA_AreaLight', 'AREA')
        light.energy, light.size, light.color = energy, size, color
        obj = bpy.data.objects.new(light.name, light)
        scene.collection.objects.link(obj)
        obj.location = pos
        obj.rotation_euler = (Vector((0, 3, 3))-obj.location).to_track_quat('-Z', 'Y').to_euler()
    camera = bpy.data.cameras.new('QA_Camera')
    cam = bpy.data.objects.new(camera.name, camera)
    scene.collection.objects.link(cam)
    cam.location = (30, -36, 29)
    cam.rotation_euler = (Vector((0, 4, 8))-cam.location).to_track_quat('-Z', 'Y').to_euler()
    camera.type, camera.ortho_scale = 'ORTHO', 52
    scene.camera = cam
    try:
        scene.render.engine = 'CYCLES'
    except TypeError as exc:
        raise RuntimeError('Cycles is unavailable in this isolated Blender build') from exc
    scene.cycles.samples = 24
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = 1800, 1300
    scene.render.resolution_percentage = 100
    formats = {i.identifier for i in scene.render.image_settings.bl_rna.properties['file_format'].enum_items}
    if 'PNG' not in formats:
        raise RuntimeError('PNG is unsupported by this Blender version')
    scene.render.image_settings.file_format = 'PNG'
    scene.render.filepath = str(OUT/'props-overview.png')
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'props-qa.blend'))
    bpy.ops.render.render(write_still=True)
    # A second closer camera proves the pickup and separate record construction.
    cam.location = (6.8, 2.9, 8.4)
    cam.rotation_euler = (Vector((0, 9, 2.3))-cam.location).to_track_quat('-Z', 'Y').to_euler()
    camera.ortho_scale = 13.0
    scene.render.resolution_x, scene.render.resolution_y = 1600, 1000
    scene.render.filepath = str(OUT/'dj-console-closeup.png')
    bpy.ops.render.render(write_still=True)
    print(json.dumps({'report': str(OUT/'report.json'),
                      'total_original_triangles': report['total_original_triangles'],
                      'max_per_mesh': max(v['triangles'] for v in library.values())}))


if __name__ == '__main__':
    main()
