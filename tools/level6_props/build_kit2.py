"""Level 6 kit, part 2: parts modelled here in Blender (no Meshy): the hollow slide-tube segment and the PA horn.

    Blender -b --python tools/level6_props/build_kit2.py

tube_segment: unit length along X, outer radius 1, open ends with a joint flange; the importer scales it per
slide segment and tints it. pa_speaker: ceiling horn, opening downwards.
"""
import bpy, bmesh, math, os

ROOT = os.path.abspath('artifacts/level6-props-20261003')
bpy.ops.wm.read_factory_settings(use_empty=True)


def lathe(name, profile, sides, axis='X', closed_profile=True):
    """profile: [(along, radius)] revolved round `axis`; consecutive points make quads."""
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new('UVMap')
    rings = []
    for a, r in profile:
        ring = []
        for k in range(sides):
            t = 2 * math.pi * k / sides
            c, s = math.cos(t) * r, math.sin(t) * r
            ring.append(bm.verts.new((a, c, s) if axis == 'X' else (c, s, a)))
        rings.append(ring)
    n = len(profile)
    total = sum(math.dist(profile[i], profile[(i + 1) % n]) for i in range(n if closed_profile else n - 1)) or 1
    run = 0.0
    for i in range(n if closed_profile else n - 1):
        j = (i + 1) % n
        step = math.dist(profile[i], profile[j])
        for k in range(sides):
            k2 = (k + 1) % sides
            f = bm.faces.new((rings[i][k], rings[i][k2], rings[j][k2], rings[j][k]))
            f.smooth = True
            for loop, (uu, vv) in zip(f.loops, ((k, run), (k + 1, run), (k + 1, run + step), (k, run + step))):
                loop[uv].uv = (uu / sides * 3, vv / total * 2)
        run += step
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me); bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


# hollow tube: outer skin, flange at each end, inner skin (profile walked as a closed loop)
R, T, F, W = 1.0, 0.07, 1.09, 0.06
tube = lathe('tube_segment', [(-0.5, R - T), (-0.5, F), (-0.5 + W, F), (-0.5 + W, R), (0.5 - W, R), (0.5 - W, F), (0.5, F),
                              (0.5, R - T)], 20)
# PA horn: mounting stem, driver can, flare, rolled lip, and the dark throat inside
horn = lathe('pa_speaker', [(1.9, 0.0), (1.9, 0.12), (1.3, 0.12), (1.3, 0.34), (0.75, 0.34), (0.7, 0.22), (0.25, 0.55),
                            (0.0, 1.0), (-0.06, 1.04), (-0.1, 1.0), (0.05, 0.9), (0.3, 0.45), (0.6, 0.12), (0.6, 0.0)],
             18, axis='Z', closed_profile=False)
horn.location = (4, 0, 0)
for o in (tube, horn):
    print('KIT2 %-14s tris %d' % (o.name, sum(len(p.vertices) - 2 for p in o.data.polygons)))
bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, 'Level6PropKit2.glb'), export_format='GLB', use_selection=True, export_apply=True)
print('KIT2 written')
