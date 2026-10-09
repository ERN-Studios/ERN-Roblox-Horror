# blender -b -P bed_prep.py -- <bed_meshy.glb> <out.glb> <length_studs> <height_studs>
# Scales the Meshy dog bed to studs, floor at Z=0, centred; reports where the rim's entry dip is and the cushion height.
import bpy, sys, json, math
import numpy as np
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
src, out, length, height = argv[0], argv[1], float(argv[2]), float(argv[3])
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
ob = next(o for o in bpy.context.scene.objects if o.type == "MESH")
mw = ob.matrix_world.copy(); ob.parent = None; ob.matrix_world = mw
for o in list(bpy.context.scene.objects):
    if o is not ob:
        bpy.data.objects.remove(o)
bpy.context.view_layer.objects.active = ob; ob.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
v = np.array([p.co[:] for p in ob.data.vertices])
lo, hi = v.min(0), v.max(0)
size = hi - lo
long_axis = 0 if size[0] >= size[1] else 1
s_xy = length / size[long_axis]
s_z = height / size[2]
c = (lo + hi) / 2
ob.data.transform(Matrix.Diagonal((s_xy, s_xy, s_z, 1)) @ Matrix.Translation((-c[0], -c[1], -lo[2])))
ob.name = ob.data.name = "LunaBed"
v = np.array([p.co[:] for p in ob.data.vertices])
# rim height around the perimeter: max z of vertices in 24 angular sectors of the outer ring
ang = np.arctan2(v[:, 1], v[:, 0])
r = np.hypot(v[:, 0] / (v[:, 0].max()), v[:, 1] / (v[:, 1].max()))
rim = []
for k in range(24):
    a0 = -math.pi + k * 2 * math.pi / 24
    m = (ang >= a0) & (ang < a0 + 2 * math.pi / 24) & (r > 0.6)
    rim.append((round(math.degrees(a0 + math.pi / 24)), round(float(v[m, 2].max()), 3) if m.any() else None))
# cushion top: highest surface hit straight down near the centre
bpy.context.view_layer.update()
dg = bpy.context.evaluated_depsgraph_get()
hits = []
for x in (-0.6, 0, 0.6):
    for y in (-0.6, 0, 0.6):
        ok, loc, *_ = bpy.context.scene.ray_cast(dg, Vector((x, y, 10)), Vector((0, 0, -1)))
        if ok:
            hits.append(round(loc.z, 3))
print("BED", json.dumps({"size": (v.max(0) - v.min(0)).round(3).tolist(), "tris": sum(len(p.vertices) - 2 for p in ob.data.polygons),
                         "rim_deg_z": rim, "cushion_hits": hits, "long_axis": "XY"[long_axis]}))
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_yup=True, export_materials="EXPORT")
bpy.ops.wm.save_as_mainfile(filepath=out.replace(".glb", ".blend"))
