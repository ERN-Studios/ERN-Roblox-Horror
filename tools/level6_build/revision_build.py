"""Revise the existing full Level 6 Blender source without writing to Studio.

Run in a background Blender loaded from the original FULL_Seed101.blend.
The original library/scenes remain available in the new file. Architecture is
realized only in revision scenes so physical UV repeats survive instance scale.
Planar cuts reset each image tile to UV 0..1, not displaced geometry.
"""
from __future__ import annotations

import bpy
import bmesh
import hashlib
import importlib.util
import json
import math
import os
import struct
import sys
from pathlib import Path
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'artifacts/level6-blender-revision-20260930'
SOURCE = ROOT / 'assets/level6-worn-party/Level6_FULL_Seed101.blend'
MAP_FILE = ROOT / 'artifacts/level6-build-20260930/seed101-layout.json'
MATERIAL_FILE = OUT / 'materials/material-manifest.json'
SCENE_NAME = 'Level 6 | Revised FULL seed 101 | 35 rooms'
OUTPUT = Path(os.environ.get('LEVEL6_REVISION_OUTPUT', ROOT / 'artifacts/level6-studio-revision-20261001/StudioImport_Portal14_Full_Seed101.blend')).resolve()
RECORD_OUT = Path(os.environ.get('LEVEL6_REVISION_RECORD_DIR', ROOT / 'artifacts/level6-studio-revision-20261001/blender-portal14')).resolve()
PLAN = json.loads(MAP_FILE.read_text())['layout']
SURFACES = json.loads(MATERIAL_FILE.read_text())['materials']
ATLAS = json.loads((ROOT / 'assets/level6-worn-party/textures/atlas-layout.json').read_text())
IMAGE_CACHE = {}
UV_RECORDS = []
SOURCE_HASHES = {}
MATERIALS = {}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def image(path, noncolor=False):
    path = str(Path(path).resolve())
    key = (path, noncolor)
    if key not in IMAGE_CACHE:
        im = bpy.data.images.load(path, check_existing=False)
        if noncolor:
            im.colorspace_settings.name = 'Non-Color'
        im.pack()
        IMAGE_CACHE[key] = im
    return IMAGE_CACHE[key]


def surface_material(identifier, material=None, red_variant=False):
    row = SURFACES[identifier]
    material = material or bpy.data.materials.new('L6R_' + identifier)
    material.use_nodes = True
    material['l6_surface_id'] = identifier
    material['l6_physical_repeat_studs'] = row['physicalRepeatStuds']
    material['l6_bump_distance_studs'] = row['bumpDistanceStuds']
    if red_variant:
        material['l6_color_variant'] = 'red plaster from orange wall wear'
    nodes = material.node_tree.nodes
    nodes.clear()
    links = material.node_tree.links
    shader = nodes.new('ShaderNodeBsdfPrincipled')
    shader.location = (550, 80)
    output = nodes.new('ShaderNodeOutputMaterial')
    output.location = (820, 80)
    links.new(shader.outputs['BSDF'], output.inputs['Surface'])
    uv = nodes.new('ShaderNodeUVMap')
    uv.uv_map = 'SurfaceUV'
    uv.location = (-780, 80)
    for index, (map_key, relative) in enumerate(row['maps'].items()):
        texture = nodes.new('ShaderNodeTexImage')
        # Blender uses the unchanged source-resolution artwork. Separate 1024
        # color maps are delivered for Roblox, not silently substituted here.
        relative = row.get('sourceColor', relative) if map_key == 'color' else relative
        texture.image = image(OUT / relative, noncolor=map_key != 'color')
        texture.label = map_key
        texture.location = (-490, 280 - index * 240)
        links.new(uv.outputs['UV'], texture.inputs['Vector'])
        if map_key == 'color':
            if red_variant:
                gray = nodes.new('ShaderNodeRGBToBW')
                multiply = nodes.new('ShaderNodeMixRGB')
                multiply.blend_type = 'MULTIPLY'
                multiply.inputs[0].default_value = 1.0
                # Linearized tint of the approved original red wall palette.
                def linear(v):
                    v /= 255.0
                    return v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4
                multiply.inputs[2].default_value = tuple(linear(v) for v in (145, 58, 48)) + (1,)
                remap = nodes.new('ShaderNodeMapRange')
                remap.inputs['From Min'].default_value = 0
                remap.inputs['From Max'].default_value = .35
                remap.inputs['To Min'].default_value = .55
                remap.inputs['To Max'].default_value = 1.15
                links.new(texture.outputs['Color'], gray.inputs['Color'])
                links.new(gray.outputs[0], remap.inputs['Value'])
                links.new(remap.outputs[0], multiply.inputs[1])
                links.new(multiply.outputs[0], shader.inputs['Base Color'])
            else:
                links.new(texture.outputs['Color'], shader.inputs['Base Color'])
        elif map_key == 'roughness':
            links.new(texture.outputs['Color'], shader.inputs['Roughness'])
        elif map_key == 'metalness':
            links.new(texture.outputs['Color'], shader.inputs['Metallic'])
        elif map_key == 'normalOpenGL':
            normal = nodes.new('ShaderNodeNormalMap')
            normal.uv_map = 'SurfaceUV'
            normal.inputs['Strength'].default_value = 1
            normal.location = (280, -300)
            links.new(texture.outputs['Color'], normal.inputs['Color'])
            links.new(normal.outputs['Normal'], shader.inputs['Normal'])
        elif map_key == 'height':
            # Alternative editable bump route. Do not add the same relief
            # twice: the baked normal, already derived from this height, is
            # the active render/export route.
            bump = nodes.new('ShaderNodeBump')
            bump.label = 'Alternative height route — baked normal is active'
            bump.inputs['Distance'].default_value = row['bumpDistanceStuds']
            bump.location = (30, -570)
            links.new(texture.outputs['Color'], bump.inputs['Height'])
    MATERIALS[identifier] = material
    return material


def tile_uv(obj, repeat=None):
    """Physical repeats with face UVs inside 0..1; object scale is baked first."""
    material = next((m for m in obj.data.materials if m and m.get('l6_surface_id')), None)
    if not material:
        return
    repeat = float(repeat or material['l6_physical_repeat_studs'])
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    for axis in range(3):
        low = min(v.co[axis] for v in bm.verts)
        high = max(v.co[axis] for v in bm.verts)
        for index in range(math.floor(low / repeat) + 1, math.ceil(high / repeat)):
            point = Vector((0, 0, 0))
            point[axis] = index * repeat
            direction = Vector((0, 0, 0))
            direction[axis] = 1
            bmesh.ops.bisect_plane(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces),
                                   dist=1e-6, plane_co=point, plane_no=direction,
                                   clear_inner=False, clear_outer=False)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    # All realized surface objects have one material; no atlas UV is retained
    # ahead of this UV layer in the exported PBR mesh.
    while obj.data.uv_layers:
        obj.data.uv_layers.remove(obj.data.uv_layers[0])
    uv = obj.data.uv_layers.new(name='SurfaceUV')
    obj.data.uv_layers.active = uv
    uv.active_render = True
    minimum, maximum = 1., 0.
    for polygon in obj.data.polygons:
        axis = max(range(3), key=lambda a: abs(polygon.normal[a]))
        if axis == 2:
            uaxis, vaxis, sign = 0, 1, 1 if polygon.normal.z >= 0 else -1
        elif axis == 0:
            uaxis, vaxis, sign = 1, 2, 1 if polygon.normal.x >= 0 else -1
        else:
            uaxis, vaxis, sign = 0, 2, -1 if polygon.normal.y >= 0 else 1
        values = [(sign * obj.data.vertices[obj.data.loops[i].vertex_index].co[uaxis] / repeat,
                   obj.data.vertices[obj.data.loops[i].vertex_index].co[vaxis] / repeat)
                  for i in polygon.loop_indices]
        cell_u = math.floor(sum(v[0] for v in values) / len(values) + 1e-9)
        cell_v = math.floor(sum(v[1] for v in values) / len(values) + 1e-9)
        for loop, value in zip(polygon.loop_indices, values):
            raw = (value[0] - cell_u, value[1] - cell_v)
            assert min(raw) >= -1e-4 and max(raw) <= 1.0001, (obj.name, raw)
            xy = (max(0., min(1., raw[0])), max(0., min(1., raw[1])))
            uv.data[loop].uv = xy
            minimum = min(minimum, *xy)
            maximum = max(maximum, *xy)
    obj['l6_uv_repeat_studs'] = repeat
    obj['l6_uv_layout'] = 'World-aligned tile faces; UV 0..1; no displacement'
    UV_RECORDS.append({'object': obj.name, 'surface': material['l6_surface_id'],
                       'repeatStuds': repeat, 'uvMin': minimum, 'uvMax': maximum,
                       'polygons': len(obj.data.polygons)})


def atlas_uv(obj):
    """Assign original atlas islands to newly authored non-PBR props only."""
    layer = obj.data.uv_layers.active or obj.data.uv_layers.new(name='AtlasUV')
    for p in obj.data.polygons:
        mat = obj.data.materials[p.material_index]
        key = mat.get('l6_material_key', 'grey_metal')
        row = ATLAS['mapping'].get(key, ATLAS['mapping']['grey_metal'])
        cell, rect = row['cell'], row['rect']
        x, y = (cell % 4) * 512, (cell // 4) * 512
        u0, v0, u1, v1 = (x + rect[0]) / 2048, 1 - (y + rect[3]) / 2048, (x + rect[2]) / 2048, 1 - (y + rect[1]) / 2048
        axis = max(range(3), key=lambda a: abs(p.normal[a]))
        axes = [a for a in range(3) if a != axis]
        points = [(obj.data.vertices[obj.data.loops[i].vertex_index].co[axes[0]],
                   obj.data.vertices[obj.data.loops[i].vertex_index].co[axes[1]]) for i in p.loop_indices]
        lo = [min(v[a] for v in points) for a in range(2)]
        hi = [max(v[a] for v in points) for a in range(2)]
        for loop, point in zip(p.loop_indices, points):
            u = (point[0] - lo[0]) / max(hi[0] - lo[0], .001)
            v = (point[1] - lo[1]) / max(hi[1] - lo[1], .001)
            layer.data[loop].uv = (u0 + (u1 - u0) * u, v0 + (v1 - v0) * v)


def library_surface_uv(obj):
    """Keep editable template geometry intact; placed/exported copies are tiled."""
    mat = next((m for m in obj.data.materials if m and m.get('l6_surface_id')), None)
    if not mat:
        return
    repeat = float(mat['l6_physical_repeat_studs'])
    layer = obj.data.uv_layers.get('SurfaceUV') or obj.data.uv_layers.new(name='SurfaceUV')
    for polygon in obj.data.polygons:
        axis = max(range(3), key=lambda a: abs(polygon.normal[a]))
        axes = (0, 1) if axis == 2 else ((1, 2) if axis == 0 else (0, 2))
        sign = 1 if (axis == 0 and polygon.normal.x >= 0) or (axis == 1 and polygon.normal.y < 0) or (axis == 2 and polygon.normal.z >= 0) else -1
        for loop in polygon.loop_indices:
            point = obj.data.vertices[obj.data.loops[loop].vertex_index].co
            layer.data[loop].uv = (sign * point[axes[0]] / repeat, point[axes[1]] / repeat)


def realize_collection(collection, matrix, destination, label, pbr_override=None):
    objects = []
    for original in collection.objects:
        # Newly authored fixture instance matrices can be stale until the
        # dependency graph runs; these prefabs have no parenting/constraints.
        local = Matrix.LocRotScale(original.location,
                                  original.rotation_euler.to_quaternion(), original.scale)
        transform = matrix @ local
        if original.type == 'EMPTY' and original.instance_collection:
            objects += realize_collection(original.instance_collection, transform, destination,
                                          label + ' / ' + original.name)
        elif original.type == 'MESH' and not original.get('export_collision_only') and not original.get('L6Collider'):
            copy = original.copy()
            copy.data = original.data.copy()
            destination.objects.link(copy)
            copy.name = label + ' / ' + original.name
            for vertex in copy.data.vertices:
                vertex.co = transform @ vertex.co
            copy.matrix_world = Matrix.Identity(4)
            if pbr_override:
                for index, mat in enumerate(copy.data.materials):
                    if mat and mat.get('l6_surface_id'):
                        copy.data.materials[index] = pbr_override
            copy.data.update()
            if any(m and m.get('l6_surface_id') for m in copy.data.materials):
                tile_uv(copy)
            objects.append(copy)
    return objects


def instance(collection, destination, label, point, angle=0):
    obj = bpy.data.objects.new(label, None)
    obj.instance_type = 'COLLECTION'
    obj.instance_collection = collection
    destination.objects.link(obj)
    obj.location = point
    obj.rotation_euler.z = angle
    return obj


def night(scene):
    scene.world = bpy.data.worlds.new(scene.name + ' | sealed night')
    scene.world.use_nodes = True
    bg = next(n for n in scene.world.node_tree.nodes if n.type == 'BACKGROUND')
    bg.inputs['Color'].default_value = (.03, .035, .045, 1)
    bg.inputs['Strength'].default_value = .025
    try:
        scene.render.engine = 'CYCLES'
    except TypeError:
        pass
    scene.cycles.samples = 24
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = 960, 640
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'


def area_light(scene, point, watts=1050):
    data = bpy.data.lights.new('L6R ceiling lamp', 'AREA')
    data.energy = watts
    data.color = (1, .9, .73)
    data.shape = 'RECTANGLE'
    data.size, data.size_y = 7, 2
    obj = bpy.data.objects.new('L6R ceiling lamp', data)
    scene.collection.objects.link(obj)
    obj.location = point
    return obj


def camera(scene, point, target, lens=24):
    data = bpy.data.cameras.new(scene.name + ' | camera')
    data.lens = lens
    obj = bpy.data.objects.new('L6R player-eye camera', data)
    scene.collection.objects.link(obj)
    obj.location = point
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat('-Z', 'Y').to_euler()
    scene.camera = obj
    return obj


def box(collection, name, center, size, mat):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1)
    for v in bm.verts:
        v.co = Vector(center) + Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    mesh.materials.append(mat)
    if mat.get('l6_surface_id'):
        tile_uv(obj)
    else:
        atlas_uv(obj)
    return obj


def transform(point, angle=0):
    return Matrix.Translation(Vector(point)) @ Matrix.Rotation(angle, 4, 'Z')


def create_revision_scene(source, name, kits, cuts=()):
    scene = bpy.data.scenes.new(name)
    scene.unit_settings.scale_length = 1
    architecture = bpy.data.collections.new(name + ' | architecture')
    scene.collection.children.link(architecture)
    for original in source.objects:
        if original.type == 'EMPTY' and original.instance_collection:
            col = original.instance_collection
            asset = col.name.removeprefix('L6K_')
            matrix = Matrix.LocRotScale(original.location,
                                       original.rotation_euler.to_quaternion(), original.scale)
            if original.name.startswith('Arrival | floor'):
                col, asset = kits['FloorDefault'], 'FloorDefault'
            if original.name.startswith('Exit | floor'):
                col, asset = kits['FloorService'], 'FloorService'
            # The historical full assembly routes Exit by its red district;
            # this revision deliberately uses the original Exit metal finish.
            if 'corridor floor' in original.name:
                link = next((l for l in PLAN['Links'] if original.name.startswith(l['Id'] + ' |')), None)
                if link and 'Exit' in (link['A'], link['B']):
                    col, asset = kits['FloorService'], 'FloorService'
                elif link and 'Arrival' in (link['A'], link['B']):
                    col, asset = kits['FloorDefault'], 'FloorDefault'
            if asset.startswith(('Floor', 'Wall', 'Lintel')):
                handled = False
                for cut in cuts:
                    # Both selected hosts use an exterior horizontal wall;
                    # remove only the eight-stud door span, retaining stubs.
                    if asset.startswith('Wall') and abs(original.location.y - cut['y']) < .02:
                        half = 4 * abs(original.scale.x)
                        low, high = original.location.x - half, original.location.x + half
                        door_low, door_high = cut['x'] - 4, cut['x'] + 4
                        if low < door_high - .001 and high > door_low + .001:
                            for a, b in ((low, min(high, door_low)), (max(low, door_high), high)):
                                if b - a > .001:
                                    # An unlinked copied object's matrix_world
                                    # remains stale until depsgraph evaluation.
                                    # Compose the transformed stub explicitly.
                                    trimmed_matrix = matrix.copy()
                                    ratio = ((b - a) / 8) / original.scale.x
                                    for row in range(3):
                                        trimmed_matrix[row][0] *= ratio
                                    trimmed_matrix.translation.x = (a + b) / 2
                                    realize_collection(col, trimmed_matrix, architecture,
                                                       original.name + ' | door stub')
                            handled = True
                            break
                if not handled:
                    realize_collection(col, matrix, architecture, original.name)
            else:
                copy = original.copy()
                scene.collection.objects.link(copy)
                if asset == 'FluorescentDiffuser':
                    area_light(scene, original.location + Vector((0, 0, -.13)), 900)
        else:
            copy = original.copy()
            if original.type in ('CAMERA', 'LIGHT'):
                copy.data = original.data.copy()
            scene.collection.objects.link(copy)
            if original == source.camera:
                scene.camera = copy
    for cut in cuts:
        box(architecture, 'New eight-stud portal lintel', (cut['x'], cut['y'], 11.25),
            (8, 1.5, 1.5), cut['material'])
    night(scene)
    return scene, architecture


def main():
    assert Path(bpy.data.filepath).resolve() == SOURCE.resolve(), bpy.data.filepath
    assert len(PLAN['Rooms']) == 32 and len(PLAN['Links']) == 37
    OUT.mkdir(parents=True, exist_ok=True)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    RECORD_OUT.mkdir(parents=True, exist_ok=True)
    for p in [SOURCE, ROOT / 'assets/level6-worn-party/Level6_WornParty_v2.blend', MAP_FILE]:
        SOURCE_HASHES[str(p.relative_to(ROOT))] = sha(p)
    kit_inventory = sorted(c.name for c in bpy.data.collections if c.name.startswith('L6K_'))
    source_object_count = len(bpy.data.objects)
    source_mesh_geometry = {o.name: hashlib.sha256(b''.join(struct.pack('<3f', *v.co) for v in o.data.vertices)).hexdigest()
                            for o in bpy.data.objects if o.type == 'MESH'}
    old_atlas = next(im for im in bpy.data.images if im.name.startswith('WornParty_Atlas'))
    revised_atlas = image(ROOT / 'artifacts/level6-textures-20260930/candidate/textures/WornParty_Level3Reference_Atlas.png')
    for mat in bpy.data.materials:
        MATERIALS[mat.get('l6_material_key', mat.name)] = mat
        if mat.use_nodes:
            for node in mat.node_tree.nodes:
                if node.type == 'TEX_IMAGE' and node.image == old_atlas:
                    node.image = revised_atlas
    route = {'carpet_beige': 'carpet_city', 'carpet_confetti': 'carpet_neon',
             'carpet_red': 'carpet_red', 'linoleum': 'diamondplate',
             'beige_wall': 'wallpaper', 'orange_wall': 'orange_wall', 'red_wall': 'orange_wall'}
    for old, identifier in route.items():
        surface_material(identifier, MATERIALS[old], red_variant=old == 'red_wall')
    # Red reuses the orange wear but must not replace the orange dictionary entry.
    MATERIALS['orange_wall'] = bpy.data.materials['L6_orange_wall']
    MATERIALS['wallpaper'] = bpy.data.materials['L6_beige_wall']
    surface_material('carpet_default')
    surface_material('kitchen_tile')
    kits = {c.name[4:]: c for c in bpy.data.collections if c.name.startswith('L6K_')}
    default = bpy.data.collections.new('L6K_FloorDefault')
    bpy.data.scenes['Level 6 | Modular Asset Library'].collection.children.link(default)
    for obj in kits['FloorOrange'].objects:
        copy = obj.copy()
        if obj.type == 'MESH':
            copy.data = obj.data.copy()
            for i, mat in enumerate(copy.data.materials):
                if mat and mat.get('l6_surface_id'):
                    copy.data.materials[i] = MATERIALS['carpet_default']
        default.objects.link(copy)
    kits['FloorDefault'] = default
    spec = importlib.util.spec_from_file_location('revision_sections', Path(__file__).with_name('revision_sections.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    new = module.build_revision_sections(MATERIALS, parent=bpy.data.scenes['Level 6 | Modular Asset Library'], existing=kits)
    kits.update(new['new_collections'])
    for col in new['new_collections'].values():
        for obj in col.objects:
            if obj.type == 'MESH' and not obj.get('export_collision_only') and not obj.get('L6Collider'):
                # Local source UVs are for kit editing. Final placed geometry is
                # tiled again after the instance transform has been baked.
                if any(m and m.get('l6_surface_id') for m in obj.data.materials):
                    tile_uv(obj)
                else:
                    atlas_uv(obj)
    # Source source-mesh vertex positions remain unchanged. New UVs are authored
    # only in copies/new collections; original source file hashes also persist.
    for name, expected in source_mesh_geometry.items():
        obj = bpy.data.objects[name]
        assert hashlib.sha256(b''.join(struct.pack('<3f', *v.co) for v in obj.data.vertices)).hexdigest() == expected
        library_surface_uv(obj)
    full_source = next(s for s in bpy.data.scenes if s.name.startswith('Level 6 | FULL seed 101'))
    cuts = [dict(x=238., y=128., material=MATERIALS['wallpaper']),
            dict(x=238., y=-716., material=MATERIALS['red_wall'])]
    full, architecture = create_revision_scene(full_source, SCENE_NAME, kits, cuts)
    placements = [('RoomKitchenPrep', (238, 140, 0), 0),
                  ('RoomStaffNook', (238, 164, 0), 0),
                  ('RoomUtilityHall', (238, -728, 0), math.pi)]
    for asset, point, angle in placements:
        realize_collection(kits[asset], transform(point, angle), architecture, asset)
        for y in (-4., 4.):
            area_light(full, transform(point, angle) @ Vector((0, y, 11.35)), 700)
    # Close the free ends: source modules keep both connection ports reusable.
    box(architecture, 'Staff nook outer end cap', (238, 176, 5.25), (8, 1.5, 10.5), MATERIALS['wallpaper'])
    box(architecture, 'Utility outer end cap', (238, -740, 5.25), (8, 1.5, 10.5), MATERIALS['orange_wall'])
    preview_scenes = []
    for index in range(1, 7):
        source = next(s for s in bpy.data.scenes if s.name.startswith(f'Study {index:02d} |'))
        # These authored study routes are scoped copies, not historical Studio state.
        if index == 4:
            original_floor = next(o for o in source.objects if o.name.startswith('Floor.') and o.instance_collection)
            clone = original_floor.copy()
            clone.instance_collection = kits['FloorBeige']
            source = source.copy()
            source.name = 'Revision study routing | Arcade'
            source.collection.objects.unlink(original_floor)
            source.collection.objects.link(clone)
        elif index == 5:
            original_floor = next(o for o in source.objects if o.name.startswith('Floor.') and o.instance_collection)
            clone = original_floor.copy()
            clone.instance_collection = kits['FloorOrange']
            source = source.copy()
            source.name = 'Revision study routing | Supply'
            source.collection.objects.unlink(original_floor)
            source.collection.objects.link(clone)
        scene, _ = create_revision_scene(source, f'Revision study {index:02d} | ' + source.name.split('|')[-1].strip(), kits)
        preview_scenes.append(scene.name)
    for index, asset in enumerate(module.NEW_ROOMS, 7):
        scene = bpy.data.scenes.new(f'Revision study {index:02d} | {asset}')
        night(scene)
        realize_collection(kits[asset], Matrix.Identity(4), scene.collection, asset)
        # Room studies show a closed far end, same kit section as the map.
        box(scene.collection, 'Study far-end cap', (0, 12, 5.25), (8, 1.5, 10.5),
            MATERIALS['wallpaper'] if asset == 'RoomStaffNook' else MATERIALS['orange_wall'])
        for y in (-4, 4):
            area_light(scene, (0, y, 11.35), 700)
        camera(scene, (1.9, -10.4, 5.6), (-1.5, 3, 4.8), 21)
        preview_scenes.append(scene.name)
    # Keep five CD assets/player and old routes in the full assembly; no game
    # controllers/objective positions are changed by this visual Blender file.
    full['revision_scope'] = 'OFFLINE Blender revision; not installed in Studio'
    full['source_layout_hash'] = PLAN['LayoutHash']
    full['original_rooms'] = 32
    full['added_rooms'] = 3
    full['original_links'] = 37
    full['added_links'] = 3
    full['original_room_floor_area_stud2'] = PLAN['RoomFloorArea']
    full['revised_room_floor_area_stud2'] = PLAN['RoomFloorArea'] + 3 * 18 * 24
    full['random_layout_note'] = 'Seed 101 preserved; reusable room modules have two 8-stud ports for later seed integration'
    camera(full, (228, 110, 5.6), (225, 140, 5.3), 24)
    bpy.context.window.scene = full
    for im in bpy.data.images:
        if im.source == 'FILE' and not im.packed_file:
            im.pack()
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT))
    for p, expected in SOURCE_HASHES.items():
        assert sha(ROOT / p) == expected
    record = {'schemaVersion': 1, 'installedInStudio': False, 'sourceFilesSha256': SOURCE_HASHES,
              'outputBlend': str(OUTPUT.relative_to(ROOT)), 'outputSha256': sha(OUTPUT),
              'sourceLayoutHash': PLAN['LayoutHash'], 'originalRooms': 32, 'originalLinks': 37,
              'originalFloorAreaStud2': PLAN['RoomFloorArea'], 'addedRoomModules': 3,
              'addedLinks': 3, 'addedFloorAreaStud2': 3 * module.ROOM_WIDTH * module.ROOM_DEPTH,
              'revisedFloorAreaStud2': PLAN['RoomFloorArea'] + 3 * module.ROOM_WIDTH * module.ROOM_DEPTH,
              'originalKitCollectionsPreserved': all(bpy.data.collections.get(n) for n in kit_inventory),
              'originalKitCollections': kit_inventory, 'newCollections': sorted(c.name for c in new['new_collections'].values()) + ['L6K_FloorDefault'],
              'originalMeshVertexPositionsPreserved': True, 'sourceObjectCount': source_object_count,
              'outputObjectCount': len(bpy.data.objects), 'packedMapCount': len(IMAGE_CACHE),
              'physicalUVObjects': len(UV_RECORDS), 'uvBounds': [min(r['uvMin'] for r in UV_RECORDS), max(r['uvMax'] for r in UV_RECORDS)],
              'fullSceneObjects': len(full.objects), 'fullSceneLights': sum(o.type == 'LIGHT' for o in full.objects),
              'newSectionsStats': new['stats'], 'newRoomPlacements': [{'asset': a, 'xyz': list(p), 'angle': r} for a, p, r in placements],
              'previewScenes': preview_scenes, 'normalConvention': 'OpenGL +Y tangent space',
              'bumpImplementation': 'Baked microfiber/tread normal; height intermediate retained; zero geometric displacement',
              'limitations': ['Studio place not open; fresh live source/editor inspection blocked.',
                              'Blender seed 101 preserved; random runtime generator not changed.',
                              'Roblox material import, gameplay and performance are unverified.']}
    (RECORD_OUT / 'build-manifest.json').write_text(json.dumps(record, indent=2) + '\n')
    (RECORD_OUT / 'physical-uv-records.json').write_text(json.dumps(UV_RECORDS, indent=2) + '\n')
    print('LEVEL6_REVISION_BUILT', json.dumps(record), flush=True)


if __name__ == '__main__':
    main()
