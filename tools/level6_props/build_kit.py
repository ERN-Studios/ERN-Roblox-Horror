"""Level 6 hero props: join Meshy's GLBs into one kit file for Studio's File > Import.

    Blender -b --python tools/level6_props/build_kit.py

Each prop becomes one object named after its file, origin at the bottom centre, textures cut to 1024 px.
Sizes are set in Studio after the import (import_kit in tools/level6_playground/import_to_studio.py).
"""
import bpy, os
from mathutils import Vector

ROOT = os.path.abspath('artifacts/level6-props-20261003')
bpy.ops.wm.read_factory_settings(use_empty=True)
x = 0.0
names = sorted(f[:-4] for f in os.listdir(os.path.join(ROOT, 'glb')) if f.endswith('.glb'))
for name in names:
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT, 'glb', name + '.glb'))
    new = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in new if o.type == 'MESH']
    bpy.ops.object.select_all(action='DESELECT')
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.parent_clear(type='CLEAR_KEEP_TRANSFORM')
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for o in new:
        if o.type != 'MESH' and o.name in bpy.data.objects:
            bpy.data.objects.remove(o, do_unlink=True)
    co = [v.co for v in obj.data.vertices]
    lo = Vector((min(c.x for c in co), min(c.y for c in co), min(c.z for c in co)))
    hi = Vector((max(c.x for c in co), max(c.y for c in co), max(c.z for c in co)))
    shift = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
    for v in obj.data.vertices:
        v.co -= shift
    obj.location = (x, 0, 0)
    x += (hi.x - lo.x) + 0.5
    obj.name = obj.data.name = name
    for m in obj.data.materials:
        m.name = name + '_mat'
    print('PROP %-20s tris %5d size %.2f %.2f %.2f' % (name, sum(len(p.vertices) - 2 for p in obj.data.polygons), *(hi - lo)))
for img in bpy.data.images:
    if img.size[0] > 1024:
        img.scale(1024, 1024)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, 'Level6PropKit.glb'), export_format='GLB', use_selection=True,
                          export_image_format='JPEG', export_jpeg_quality=85, export_apply=True)
print('KIT', len(names), os.path.getsize(os.path.join(ROOT, 'Level6PropKit.glb')) // 1024, 'KB')
