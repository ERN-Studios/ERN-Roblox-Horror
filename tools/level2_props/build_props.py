"""Procedural Level 2 wall fittings. Run with Blender 5.2 --background --python.

Every asset vertex is generated here. No operators/modifiers create prop geometry.
One Blender unit = one stud; 2.86 studs/metre. Wall Y=0, room -Y, up Z.
Export (X,Y,Z)=(Blender X,Blender Z,Blender Y), with reversed triangles.
"""
import argparse
import hashlib
import json
import math
import sys
import os
from collections import Counter, defaultdict
from pathlib import Path

import bpy
from mathutils import Vector

# Numbers, blend and renders go under artifacts/level2-props-20261010 (LEVEL2_PROPS_OUT overrides); install_props.py reads
# props.json from there. Codex wrote this in a scratch folder on 2026-10-10; only these two lines changed when it moved here.
OUT = Path(os.environ.get('LEVEL2_PROPS_OUT') or Path(__file__).resolve().parents[2] / 'artifacts' / 'level2-props-20261010')
ROOT = OUT.parent
STUDS_PER_METRE = 2.86
BLENDER_UNITS_PER_STUD = 1.0
WALL_Y = 0.0
AXIS_MAP = ((1, 0, 0), (0, 0, 1), (0, 1, 0))
assert BLENDER_UNITS_PER_STUD == 1.0 and STUDS_PER_METRE == 2.86 and WALL_Y == 0 and AXIS_MAP[1][2] == 1
assert Vector(AXIS_MAP[0]).dot(Vector(AXIS_MAP[1]).cross(Vector(AXIS_MAP[2]))) == -1
TAU = 2 * math.pi
STEEL = (0.56, 0.61, 0.65)
AQUA = (0.66, 0.93, 1.0)
CAST = (0.28, 0.31, 0.30)
GREEN = (0.12, 1.0, 0.28)
WIRE = (0.075, 0.095, 0.085)
LIMITS = {'PoolLamp_Bezel': 448, 'PoolLamp_Lens': 440,
          'ExitLamp_Base': 620, 'ExitLamp_Lens': 384, 'ExitLamp_Cage': 740}
EXIT_SHIFT = -0.155  # centre the complete projected footprint, including conduit


def volume(vertices, faces):
    return sum(Vector(vertices[a]).dot(Vector(vertices[b]).cross(Vector(vertices[c])))
               for a, b, c in faces) / 6


class Geometry:
    def __init__(self):
        self.vertices, self.faces, self.colours = [], [], []

    def shell(self, vertices, faces, colour):
        assert volume(vertices, faces) != 0
        if volume(vertices, faces) < 0:
            faces = [(a, c, b) for a, b, c in faces]
        offset = len(self.vertices)
        self.vertices.extend(vertices)
        self.faces.extend(tuple(offset + i for i in f) for f in faces)
        self.colours.extend([colour] * len(vertices))


def oval_solid(g, profile, sides, colour, at=(0, 0, 0)):
    """Closed profile from rear centre, along perimeter, to front centre.
    Each station is (X radius, Z radius, wall protrusion), centres use radius 0.
    """
    vertices, rings, faces = [], [], []
    for rx, rz, depth in profile:
        ring = []
        for j in range(sides if rx else 1):
            a = TAU * j / sides
            ring.append(len(vertices))
            vertices.append((at[0] + rx * math.cos(a), at[1] - depth,
                             at[2] + rz * math.sin(a)))
        rings.append(ring)
    for p, q in zip(rings, rings[1:]):
        for j in range(sides):
            k = (j + 1) % sides
            if len(p) == 1:
                faces.append((p[0], q[j], q[k]))
            elif len(q) == 1:
                faces.append((p[j], q[0], p[k]))
            else:
                faces.extend([(p[j], q[j], q[k]), (p[j], q[k], p[k])])
    g.shell(vertices, faces, colour)


def capped_frustum(g, sides, r_back, r_front, d_back, d_front, at, colour):
    """Countersunk screw head: tapered underside, polygonal flat crown."""
    vertices = [(at[0] + r * math.cos(TAU * j / sides + math.pi / 6),
                 at[1] - d, at[2] + r * math.sin(TAU * j / sides + math.pi / 6))
                for r, d in ((r_back, d_back), (r_front, d_front)) for j in range(sides)]
    faces = []
    for j in range(sides):
        k = (j + 1) % sides
        faces += [(j, k, sides + k), (j, sides + k, sides + j)]
    for j in range(1, sides - 1):
        faces += [(0, j + 1, j), (sides, sides + j, sides + j + 1)]
    g.shell(vertices, faces, colour)


def tube(g, path, radius, sides, reference, colour, closed=False):
    vertices, faces = [], []
    count = len(path)
    ref = Vector(reference)
    for j, p in enumerate(path):
        prev = Vector(path[(j - 1) % count] if closed or j else path[j])
        nxt = Vector(path[(j + 1) % count] if closed or j < count - 1 else path[j])
        tangent = (nxt - prev).normalized()
        b1 = (ref - tangent * ref.dot(tangent)).normalized()
        b2 = tangent.cross(b1).normalized()
        for k in range(sides):
            a = TAU * k / sides
            vertices.append(tuple(Vector(p) + radius * (math.cos(a) * b1 + math.sin(a) * b2)))
    for j in range(count if closed else count - 1):
        following = (j + 1) % count
        for k in range(sides):
            a, b = j * sides + k, j * sides + (k + 1) % sides
            c, d = following * sides + k, following * sides + (k + 1) % sides
            faces += [(a, c, d), (a, d, b)]
    if not closed:
        last = (count - 1) * sides
        for k in range(1, sides - 1):
            faces += [(0, k, k + 1), (last, last + k + 1, last + k)]
    g.shell(vertices, faces, colour)


def pool_lamp():
    bezel, lens = Geometry(), Geometry()
    # Outer chamfer / broad face / two slopes of rolled inner lip / thin backplate.
    oval_solid(bezel, [(0, 0, 0), (.70, .70, 0), (.662, .662, .045),
                      (.545, .545, .045), (.532, .532, .054), (.52, .52, .05),
                      (.52, .52, .012), (0, 0, .012)], 24, STEEL)
    for i in range(8):
        a = TAU * i / 8 + math.pi / 8
        capped_frustum(bezel, 6, .020, .034, .035, .048,
                       (.603 * math.cos(a), 0, .603 * math.sin(a)), (.34, .38, .40))
    # Five sawtooth annuli follow a shallow convex envelope. Centre is a boss.
    profile = [(0, 0, .047), (.52, .52, .05)]
    for radius in (.46, .38, .30, .22, .14):
        crown = .05 + .09 * (1 - (radius / .52) ** 2)
        profile.append((radius, radius, crown))
        r = radius - .030
        valley = .05 + .09 * (1 - (r / .52) ** 2) - .026
        profile.append((r, r, valley))
    profile.append((0, 0, .14))
    oval_solid(lens, profile, 20, AQUA)
    # First render hid the shallow teeth. Darker aqua at valley stations keeps
    # the relief visible when the lead uses Neon, without textures or more faces.
    for ring in range(3, 12, 2):
        for i in range(1 + (ring - 1) * 20, 1 + ring * 20):
            lens.colours[i] = (.48, .75, .84)
    return {'PoolLamp_Bezel': bezel, 'PoolLamp_Lens': lens}


def exit_lamp():
    base, lens, cage = Geometry(), Geometry(), Geometry()
    centre = (0, 0, EXIT_SHIFT)
    oval_solid(base, [(0, 0, 0), (.44, .29, 0), (.46, .31, .035),
                     (.46, .31, .18), (.435, .285, .225),
                     (.385, .235, .225), (.385, .235, .045), (0, 0, .045)], 32, CAST, centre)
    for side in (-1, 1):
        # Eight-sided fixing ears, each with a small countersunk head.
        capped_frustum(base, 8, .075, .075, 0, .07,
                       (side * .475, 0, EXIT_SHIFT), CAST)
        capped_frustum(base, 8, .017, .030, .058, .073,
                       (side * .493, 0, EXIT_SHIFT), (.42, .44, .42))
    # Upward conduit, radius .12, .35 long. Seat .04 into the curved housing.
    conduit = []
    for r, z in ((.12, .27), (.12, .31), (.12, .325), (.12, .62)):
        for j in range(12):
            a = TAU * j / 12
            conduit.append((r * math.cos(a), -.13 + r * math.sin(a), z + EXIT_SHIFT))
    faces = []
    for ring in range(3):
        for j in range(12):
            k = (j + 1) % 12
            a, b, c, d = ring * 12 + j, ring * 12 + k, (ring + 1) * 12 + j, (ring + 1) * 12 + k
            faces += [(a, b, d), (a, d, c)]
    for j in range(1, 11):
        faces += [(0, j + 1, j), (36, 36 + j, 36 + j + 1)]
    base.shell(conduit, faces, CAST)
    profile = [(0, 0, .220), (.385, .235, .222)]
    for angle in (math.pi / 12, math.pi / 6, math.pi / 4, math.pi / 3, 5 * math.pi / 12):
        profile.append((.385 * math.cos(angle), .235 * math.cos(angle), .222 + .184 * math.sin(angle)))
    profile.append((0, 0, .406))
    oval_solid(lens, profile, 32, GREEN, centre)
    rim = [(.407 * math.cos(TAU * j / 32), -.294,
            EXIT_SHIFT + .257 * math.sin(TAU * j / 32)) for j in range(32)]
    tube(cage, rim, .022, 6, (0, 1, 0), WIRE, True)
    for vertical in (False, True):
        path = []
        for j in range(13):
            angle = math.pi * j / 12
            x = 0 if vertical else .407 * math.cos(angle)
            z = .257 * math.cos(angle) if vertical else 0
            path.append((x, -(.294 + .184 * math.sin(angle)), EXIT_SHIFT + z))
        tube(cage, path, .022, 6, (1, 0, 0) if vertical else (0, 0, 1), WIRE)
    return {'ExitLamp_Base': base, 'ExitLamp_Lens': lens, 'ExitLamp_Cage': cage}


def topology(vertices, faces, label):
    edges = Counter()
    touching = defaultdict(list)
    normals = []
    for fi, (a, b, c) in enumerate(faces):
        assert len({a, b, c}) == 3, (label, 'repeated triangle index')
        cross = (Vector(vertices[b]) - Vector(vertices[a])).cross(Vector(vertices[c]) - Vector(vertices[a]))
        assert cross.length > 1e-8, (label, 'degenerate triangle', fi)
        normals.append(cross.normalized())
        for u, v in ((a, b), (b, c), (c, a)):
            edges[(u, v)] += 1
            touching[tuple(sorted((u, v)))].append(fi)
    assert all(n == 1 and edges[(v, u)] == 1 for (u, v), n in edges.items()), (label, 'edge direction / manifold')
    assert all(len(f) == 2 for f in touching.values())
    adjacent = defaultdict(list)
    for a, b in touching.values():
        adjacent[a].append(b)
        adjacent[b].append(a)
    unseen, component_volumes = set(range(len(faces))), []
    while unseen:
        seed = min(unseen)
        unseen.remove(seed)
        stack, found = [seed], []
        while stack:
            fi = stack.pop()
            found.append(faces[fi])
            for other in adjacent[fi]:
                if other in unseen:
                    unseen.remove(other)
                    stack.append(other)
        signed = volume(vertices, found)
        assert signed > 1e-9, (label, 'inward component', signed)
        component_volumes.append(round(signed, 9))
    # Every vertex link must form one cycle: rejects bow-tie vertices.
    incident = defaultdict(list)
    for a, b, c in faces:
        incident[a].append((b, c)); incident[b].append((c, a)); incident[c].append((a, b))
    for v, pairs in incident.items():
        link = defaultdict(set)
        for a, b in pairs:
            link[a].add(b); link[b].add(a)
        assert all(len(x) == 2 for x in link.values()), (label, 'nonmanifold vertex', v)
        seen, todo = set(), [next(iter(link))]
        while todo:
            a = todo.pop()
            if a not in seen:
                seen.add(a); todo.extend(link[a] - seen)
        assert len(seen) == len(link), (label, 'disconnected vertex link')
    return normals, component_volumes


def uv_for(name, p):
    if name == 'PoolLamp_Lens':
        return [round(.5 + p[0] / 1.04, 6), round(.5 + p[2] / 1.04, 6)]
    if name == 'PoolLamp_Bezel':
        return [round((math.atan2(p[2], p[0]) / TAU) % 1, 6), round(-p[1] / .054, 6)]
    if name == 'ExitLamp_Lens':
        return [round(.5 + p[0] / .77, 6), round(.5 + (p[2] - EXIT_SHIFT) / .47, 6)]
    return [0.0, 0.0]


def export_mesh(name, g):
    assert all(p[1] <= .0005 for p in g.vertices), (name, 'behind wall')
    assert len(g.faces) <= LIMITS[name], (name, 'triangle budget')
    topology(g.vertices, g.faces, name + ' Blender')
    # Reflection has determinant -1; swap corners B and C to restore outward faces.
    verts = [(round(x * 1000), round(z * 1000), round(y * 1000)) for x, y, z in g.vertices]
    faces = [(a, c, b) for a, b, c in g.faces]
    points = [tuple(c / 1000 for c in p) for p in verts]
    face_normals, component_volumes = topology(points, faces, name + ' exported')
    sums = [Vector((0, 0, 0)) for _ in points]
    # Angle-weighted shared normals: compact indexed topology remains watertight.
    for face, normal in zip(faces, face_normals):
        for j, vi in enumerate(face):
            p = Vector(points[vi])
            e1 = (Vector(points[face[(j + 1) % 3]]) - p).normalized()
            e2 = (Vector(points[face[(j + 2) % 3]]) - p).normalized()
            angle = math.acos(max(-1, min(1, e1.dot(e2))))
            sums[vi] += normal * angle
    normals = [tuple(round(c * 1000) for c in v.normalized()) for v in sums]
    assert all(.997 < Vector(n).length / 1000 < 1.003 for n in normals)
    assert all(Vector(normals[vi]).dot(n) > 0 for f, n in zip(faces, face_normals) for vi in f), (name, 'normal facing')
    colours = [round(max(0, min(1, c)) * 255) for rgb in g.colours for c in rgb]
    numbers = {'verts': [c for p in verts for c in p],
               'normals': [c for p in normals for c in p],
               'colours': colours, 'tris': [i for f in faces for i in f]}
    low = [min(p[i] for p in verts) / 1000 for i in range(3)]
    high = [max(p[i] for p in verts) / 1000 for i in range(3)]
    assert high[2] <= .0005
    digest = hashlib.sha1(json.dumps(numbers, separators=(',', ':')).encode()).hexdigest()[:12]
    # Explicit UV indices preserve angular seam without splitting topology vertices.
    uv_values, uv_tris = [], []
    for f in faces:
        uv = [uv_for(name, g.vertices[i]) for i in f]
        if name == 'PoolLamp_Bezel' and max(x[0] for x in uv) - min(x[0] for x in uv) > .5:
            uv = [[u + (1 if u < .5 else 0), v] for u, v in uv]
        for value in uv:
            uv_tris.append(len(uv_values) // 2)
            uv_values.extend(value)
    return {**numbers, 'middle': [round((a + b) / 2, 6) for a, b in zip(low, high)],
            'size': [round(b - a, 6) for a, b in zip(low, high)],
            'bbox': {'min': low, 'max': high}, 'triangles': len(faces), 'vertices': len(verts),
            'closed': True, 'components': len(component_volumes),
            'signed_volumes': component_volumes, 'sha1': digest,
            'uvs': uv_values, 'uv_tris': uv_tris,
            'uv_mapping': 'cylindrical angle/depth' if name == 'PoolLamp_Bezel' else
                          'planar 0..1' if name.endswith('Lens') else 'unused'}


def material(name, colour, metal=0, glow=0, roughness=.35):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*colour, 1)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get('Principled BSDF')
    attr = mat.node_tree.nodes.new('ShaderNodeVertexColor')
    attr.layer_name = 'Col'
    mat.node_tree.links.new(attr.outputs['Color'], shader.inputs['Base Color'])
    shader.inputs['Metallic'].default_value = metal
    shader.inputs['Roughness'].default_value = roughness
    if glow:
        mat.node_tree.links.new(attr.outputs['Color'], shader.inputs['Emission Color'])
        shader.inputs['Emission Strength'].default_value = glow
    return mat


def make_object(name, g, mat, collection, exported):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(g.vertices, [], g.faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    obj.location = (0, 0, 0)
    assert tuple(obj.location) == (0, 0, 0)
    layer = mesh.color_attributes.new('Col', 'BYTE_COLOR', 'CORNER')
    for loop in mesh.loops:
        layer.data[loop.index].color = (*g.colours[loop.vertex_index], 1)
    uv_layer = mesh.uv_layers.new(name='UVMap')
    for poly in mesh.polygons:
        values = [uv_for(name, g.vertices[mesh.loops[i].vertex_index]) for i in poly.loop_indices]
        if name == 'PoolLamp_Bezel' and max(u for u, v in values) - min(u for u, v in values) > .5:
            values = [[u + (1 if u < .5 else 0), v] for u, v in values]
        for li, value in zip(poly.loop_indices, values):
            uv_layer.data[li].uv = value
        poly.use_smooth = True
    # Match upload normals, undoing the export axis permutation.
    normals = exported['normals']
    local_normals = [(normals[i] / 1000, normals[i + 2] / 1000, normals[i + 1] / 1000)
                     for i in range(0, len(normals), 3)]
    mesh.normals_split_custom_set_from_vertices(local_normals)
    mesh.materials.append(mat)
    obj['units'] = 'studs; 2.86 studs per metre'
    obj['wall'] = 'Y=0; front=-Y; export X,Z,Y with reversed winding'
    obj['closed_components'] = exported['components']
    obj['triangles'] = exported['triangles']
    return obj


def dimension_assertions(data):
    b = data['PoolLamp_Bezel']['bbox']
    l = data['PoolLamp_Lens']['bbox']
    assert b['min'][:2] == [-.7, -.7] and b['max'][:2] == [.7, .7]
    assert b['max'][2] == 0 and b['min'][2] == -.054
    assert l['min'] == [-.52, -.52, -.14] and l['max'] == [.52, .52, -.047]
    assert abs(.14 - .05 - .09) < 1e-12
    e = data['ExitLamp_Base']['bbox']
    assert 1.08 <= data['ExitLamp_Base']['size'][0] <= 1.10
    assert e['min'][1] == -.465 and e['max'][1] == .465
    assert e['max'][2] == 0 and e['min'][2] >= -.25
    assert data['ExitLamp_Lens']['bbox'] == {'min': [-.385, -.390, -.406], 'max': [.385, .080, -.220]}
    assert data['ExitLamp_Cage']['bbox'] == {'min': [-.426, -.431, -.497], 'max': [.426, .121, -.272]}
    assert e == {'min': [-.547, -.465, -.250], 'max': [.547, .465, 0.0]}
    assert abs(.31 - (-.31) - .62) < 1e-12
    assert abs(.62 - .27 - .35) < 1e-12
    assert abs(.62 - (-.31) - .93) < 1e-12
    assert sum(data[n]['triangles'] for n in data if n.startswith('Pool')) <= 900
    assert sum(data[n]['triangles'] for n in data if n.startswith('Exit')) <= 1800
    # Analytic crown separation: closest wire surface is .05 beyond lens.
    assert abs(.478 - .022 - .406 - .05) < 1e-12


def box_geometry(size, at):
    vertices = [(at[0] + a * size[0] / 2, at[1] + b * size[1] / 2, at[2] + c * size[2] / 2)
                for a, b, c in ((-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),
                                (-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1))]
    return vertices, [(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]


def simple_obj(name, vertices, faces, mat, collection):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    mesh.materials.append(mat)
    return obj


def plain_material(name, colour, roughness):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value = (*colour, 1)
    shader.inputs['Roughness'].default_value = roughness
    return mat


def camera_at(scene, camera, position, target, scale):
    camera.location = position
    camera.rotation_euler = (Vector(target) - camera.location).to_track_quat('-Z', 'Y').to_euler()
    camera.data.ortho_scale = scale
    scene.camera = camera


def preview_setup(scene):
    collection = bpy.data.collections.new('Preview_Set (not exported)')
    scene.collection.children.link(collection)
    tile = plain_material('Pale glazed bath-house tile', (.78, .80, .72), .32)
    grout = plain_material('Ivory grout', (.59, .61, .56), .7)
    # Single low-cost wall mesh of flush tiles, grout plane exactly at Y=0.
    vertices, faces = box_geometry((13, .05, 13), (0, .027, 0))
    simple_obj('Preview grout wall', vertices, faces, grout, collection)
    vertices, faces = [], []
    pitch = .48
    for ix in range(-14, 15):
        for iz in range(-14, 15):
            # Render-only tiles sit 0.001 stud behind the mounting plane.
            x, z, s = (ix + .5) * pitch, (iz + .5) * pitch, (pitch - .010) / 2
            base = len(vertices)
            vertices.extend([(x-s,.001,z-s),(x+s,.001,z-s),(x+s,.001,z+s),(x-s,.001,z+s)])
            faces.append((base,base+1,base+2,base+3))
    simple_obj('Preview pale tile faces', vertices, faces, tile, collection)
    for name, position, power, size, colour in (
            ('Window sun fill', (-3,-4,5), 420, 4.0, (1.0,.93,.80)),
            ('Room bounce', (4,-3,1), 190, 3.0, (.82,.91,1.0))):
        light_data = bpy.data.lights.new(name, 'AREA')
        light_data.energy, light_data.shape, light_data.size, light_data.color = power, 'DISK', size, colour
        light = bpy.data.objects.new(name, light_data)
        collection.objects.link(light)
        light.location = position
        light.rotation_euler = (Vector((0,0,0)) - light.location).to_track_quat('-Z', 'Y').to_euler()
    camera_data = bpy.data.cameras.new('Preview camera')
    camera_data.type = 'ORTHO'
    camera = bpy.data.objects.new('Preview camera', camera_data)
    collection.objects.link(camera)
    scene.render.engine = 'BLENDER_EEVEE'
    if hasattr(scene, 'eevee') and hasattr(scene.eevee, 'taa_render_samples'):
        scene.eevee.taa_render_samples = 24
    scene.render.threads_mode = 'FIXED'
    scene.render.threads = 2
    scene.render.resolution_x, scene.render.resolution_y = 800, 600
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGB'
    scene.world = bpy.data.worlds.new('Sunny Poolrooms ambient')
    scene.world.use_nodes = True
    scene.world.node_tree.nodes['Background'].inputs['Color'].default_value = (.73,.79,.82,1)
    scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value = .35
    scene.view_settings.view_transform = 'AgX'
    return collection, camera


def render_all(scene, assets, preview, camera):
    for group, scale in (('pool', 2.15), ('exit', 1.85)):
        for name, obj in assets.items():
            obj.hide_render = not name.lower().startswith(group)
        target = (0, -.08, 0)
        for view, position, framing in (
                ('three_quarter', (3,-5,2.5), scale),
                ('front', (0,-5,0), scale),
                ('side', (5,-.25,0), scale)):
            camera_at(scene, camera, position, (0,-.25,0) if view == 'side' else target, framing)
            scene.render.filepath = str(OUT / 'renders' / f'{group}_{view}.png')
            bpy.ops.render.render(write_still=True, scene=scene.name)
    grid = []
    for obj in assets.values():
        obj.hide_render = True
    # Three columns, four rows. All instances share the original mesh datablocks.
    for col in range(3):
        for row in range(4):
            for name in ('PoolLamp_Bezel', 'PoolLamp_Lens'):
                obj = assets[name].copy()
                preview.objects.link(obj)
                obj.name = f'Preview grid {name} {col}-{row}'
                obj.location = ((col-1)*2.1, 0, (row-1.5)*2.1)
                obj.hide_render = False
                grid.append(obj)
    camera_at(scene, camera, (2.2,-3.9,10.5), (0,0,0), 7.6)
    scene.render.filepath = str(OUT / 'renders' / 'pool_grid_steep_above.png')
    bpy.ops.render.render(write_still=True, scene=scene.name)
    for obj in grid:
        bpy.data.objects.remove(obj, do_unlink=True)
    for obj in assets.values():
        obj.hide_render = False


def write_readme(data):
    rows = '\n'.join(f"| `{name}` | {m['triangles']} | {m['vertices']} | {m['bbox']['min']} | {m['bbox']['max']} | {m['components']} | `{m['sha1']}` |"
                     for name, m in data.items())
    text = f'''# Level 2 wall lamps — BACKROOMS: STAY QUIET

Rebuild from the project folder (one Blender process at a time):

```sh
/Applications/Blender.app/Contents/MacOS/Blender --factory-startup -b --python work/build_props.py
```

Use `-- --skip-renders` for the deterministic JSON / blend rebuild only. All asset vertices are generated in the script; no downloaded assets, textures or fonts. The saved blend has an `Assets` scene displaying both assemblies apart through collection instances, and a separate `Preview` scene with the five named source mesh objects, tiled wall, camera and lights. The opening scene is `Assets`; the five source objects remain at zero with shared wall origins. Preview geometry is excluded from JSON.

## Units, placement and dimensions

One Blender unit = one Roblox stud. The level scale is **2.86 studs/metre**. Blender wall plane is **X–Z at Y=0**, X right, Z up, room/front **−Y**. All object origins are **(0,0,0)** on this wall plane. No asset vertex lies behind it; there are **no deliberate wall recesses**.

Export axes: **Roblox X=Blender X, Roblox Y=Blender Z, Roblox Z=Blender Y**. Thus wall Z=0, front −Z. This permutation reflects orientation, so every triangle has B/C swapped. Do not apply the old sign script's minus on Blender Y. When using the reference template, position each MeshPart at its `middle` relative to the assembly's wall origin, preserving the exported `size`.

Pool outside diameter **1.40**, lens rim radius **0.52**, total projection **0.14**. Inner lip depth **0.05**, lens crown **0.14**: rise **0.09**. The bezel is 24-sided, the lens 20-sided, and the eight six-sided countersunk heads are on the face at radius 0.603. A 0.012-stud backplate closes the recess; the lip has two angular rolled slopes. Five prismatic teeth surround a smooth central boss.

Exit housing is **about 1.10 wide × 0.62 high**, with the **0.35** upward conduit seated **0.04** into the housing, making complete height **0.93**. Complete depth is **about 0.50**. Origin is the centre of the complete projected footprint, including conduit; housing/lens centre is Blender Z=−0.155 (Roblox Y=−0.155). Conduit radius **0.12** throughout; its complete length is 0.35. Two perpendicular six-sided wire hoops and an oval wire rim have radius **0.022**. The nearest crown wire surface is at least **0.05** beyond the lens, while shoulder spacing is larger. Fixing ears, screws, conduit and crossing wires are overlapping **individually closed shells**, not boolean unions.

## Export numbers

`props.json` has `meshes[name]` with the exact four arrays the supplied `install_sign.py` **UPLOAD** block consumes:

- `verts`: flat **integer XYZ triples in millistuds**, divide by 1000.
- `normals`: flat **integer XYZ triples scaled by 1000**, divide by 1000; one angle-weighted normal per shared vertex.
- `colours`: flat **RGB byte triples**, 0–255, one per shared vertex.
- `tris`: flat **zero-based vertex-index triples**, add 1 only to index Lua tables.

Unlike the reference's private corners, these are shared indexed vertices, accepted unchanged by that UPLOAD code and retaining manifold topology. `middle`/`size` are retained for the template. `bbox` min/max, vertex/triangle counts, closed-shell count, positive component volumes and 12-character SHA1 are added. SHA1 covers compact JSON of the four arrays in order `verts,normals,colours,tris`.

`uvs` are flat floating-point UV pairs with separate zero-based `uv_tris` matching triangle corners; the angular seam is unwrapped per triangle. Pool lens UV is planar 0..1 across its diameter; bezel UV is cylindrical angle/depth. **The reference UPLOAD block ignores UVs**; an installer must add `AddUV`/`SetFaceUVs` handling to retain them. No texture is required. UVMap is already present in the blend.

## Mesh table

Bounding boxes below are **Roblox axes, studs**, measured after 0.001-stud quantization. Every mesh is closed.

| Mesh | Triangles | Shared vertices | Bbox min | Bbox max | Closed shells | Numbers SHA1 |
|---|---:|---:|---|---|---:|---|
{rows}

Pool total: **{sum(m['triangles'] for n,m in data.items() if n.startswith('Pool'))}/900 triangles**. Exit total: **{sum(m['triangles'] for n,m in data.items() if n.startswith('Exit'))}/1800 triangles**.

## Roblox appearance

| Mesh | Material | RGB colour | Purpose |
|---|---|---|---|
| PoolLamp_Bezel | Metal | 143,156,166; head vertices 87,97,102 | Stainless trim, rolled lip, eight heads, hidden backplate |
| PoolLamp_Lens | **Neon** | 168,237,255; valleys 122,191,214 | Glowing aqua-white prismatic lens with subtle vertex-colour relief |
| ExitLamp_Base | Metal | 71,79,77; heads 107,112,107 | Cast grey box, fixing ears, conduit |
| ExitLamp_Lens | **Neon** | 31,255,71 | Green exit indicator lens |
| ExitLamp_Cage | Metal | 19,24,22 | Dark wire guard |

Viewport materials are set in the blend; render emission is modest to preserve the ridge relief. The lead supplies Roblox lighting, depth fading, placement and gameplay. No light instances are exported.

## Validation and render review

The builder asserts both group budgets and each individual allocation, bounds, wall clearance, no degenerate triangles, valid directed edge pairs (exactly one each direction), cyclic vertex links, and **positive signed volume for every connected shell**. It repeats topology, winding and normals checks on the **final quantized Roblox coordinates**. The final table prints on rebuild. Determinism is checked with two builds and byte comparison of JSON. Preview PNGs are 800×600, EEVEE, two CPU threads, sequential renders.

RENDER_REVIEW_PLACEHOLDER

## Not verified

Nothing ran inside Roblox or Roblox Studio. EditableMesh creation/upload, MeshPart recentering, imported UVs, actual Neon appearance, culling in-engine, lighting, depth fade, collision, draw-call cost, 360-copy performance, and readability at the stated in-game distances are not runtime-tested. Renders inspect shape and placement only. Disconnected overlapping shells are intentional; this is not a watertight boolean-union manufacturing model.
'''
    old = OUT / 'README.md'
    review = ('Inspected all seven PNGs. The first pool front/three-quarter views flattened the Fresnel relief, '
              'so valley setback increased from 0.014 to 0.026 studs and subtle darker aqua vertex colours '
              'were added at the five valleys. Re-rendering shows five concentric rings and the central boss; '
              'the exact side view exposes the shallow dome and teeth. The chamfer, rolled lip and eight darker '
              'heads distinguish the fitting from a plain ring. Exit front and three-quarter views leave most '
              'green lens area visible; its exact side view shows the wire gap. The conduit initially touched '
              'the curved housing at a tangent, so it was seated 0.04 studs into the box while retaining its '
              '0.35-stud total length. The 3×4 view remains legible at a steep angle from above. Side cameras '
              'were changed to true orthographic profiles. These are shape reviews, not tests at Roblox viewing distances.')
    text = text.replace('RENDER_REVIEW_PLACEHOLDER', 'Render review: ' + review)
    old.write_text(text)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--skip-renders', action='store_true')
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    args = parser.parse_args(argv)
    for directory in (OUT / 'blend', OUT / 'renders'):
        directory.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.name = 'Assets'
    pool_collection = bpy.data.collections.new('PoolLamp sources - wall origin')
    exit_collection = bpy.data.collections.new('ExitLamp sources - wall origin')
    # Source collections are datablocks; only separated collection instances show in Assets.
    preview_scene = bpy.data.scenes.new('Preview')
    preview_scene.collection.children.link(pool_collection)
    preview_scene.collection.children.link(exit_collection)
    geometries = {**pool_lamp(), **exit_lamp()}
    data = {name: export_mesh(name, g) for name, g in geometries.items()}
    dimension_assertions(data)
    export = {'version': 1, 'units': 'studs', 'studs_per_metre': STUDS_PER_METRE,
              'origin': 'centre of projected footprint on wall; exit includes upward conduit',
              'axes': 'Roblox (X,Y,Z) = Blender (X,Z,Y); front -Z; wall Z=0; reverse winding',
              'number_format': 'flat integer millistud positions, normals x1000, RGB bytes, zero-based triangle indices',
              'meshes': data}
    (OUT / 'props.json').write_text(json.dumps(export, separators=(',', ':')) + '\n')
    print('MESH                    TRIS   VERTS   ROBLOX BBOX MIN             MAX              SHA1', flush=True)
    for name, m in data.items():
        print(f"{name:23s} {m['triangles']:5d} {m['vertices']:7d} {str(m['bbox']['min']):27s} {m['bbox']['max']} {m['sha1']}", flush=True)
    mats = {'PoolLamp_Bezel': material('Stainless trim', STEEL, .8, 0, .28),
            'PoolLamp_Lens': material('Aqua-white Neon preview', AQUA, 0, .45, .22),
            'ExitLamp_Base': material('Cast grey metal', CAST, .55, 0, .48),
            'ExitLamp_Lens': material('Green Neon preview', GREEN, 0, .5, .25),
            'ExitLamp_Cage': material('Dark wire', WIRE, .65, 0, .32)}
    assets = {name: make_object(name, g, mats[name], pool_collection if name.startswith('Pool') else exit_collection, data[name])
              for name, g in geometries.items()}
    for name, collection, x in (('Pool assembly display', pool_collection, -1.0),
                                ('Exit assembly display', exit_collection, 1.0)):
        inst = bpy.data.objects.new(name, None)
        inst.instance_type, inst.instance_collection = 'COLLECTION', collection
        inst.location = (x, 0, 0)
        scene.collection.objects.link(inst)
    preview, camera = preview_setup(preview_scene)
    if not args.skip_renders:
        render_all(preview_scene, assets, preview, camera)
    camera_at(preview_scene, camera, (3,-5,2.5), (0,-.08,0), 2.15)
    bpy.context.window.scene = scene
    # Saved viewport fronts the separated asset instances; no prop transforms applied.
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type == 'VIEW_3D':
                area.spaces.active.shading.type = 'MATERIAL'
                area.spaces.active.region_3d.view_distance = 4.7
                area.spaces.active.region_3d.view_location = (0,0,0)
                area.spaces.active.region_3d.view_rotation = Vector((0,1,0)).to_track_quat('-Z','Y')
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT / 'blend' / 'level2_props.blend'))
    write_readme(data)
    print('DONE: budgets, closed topology, quantized winding/normals, bounds, axes and wall clearance asserted.', flush=True)


if __name__ == '__main__':
    main()
