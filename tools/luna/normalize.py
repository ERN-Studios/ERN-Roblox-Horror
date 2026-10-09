# blender -b -P normalize.py -- <in.glb> <out.blend> <target_height_studs>
# Aligns the Meshy dog: spine along +Y with the nose at +Y (Blender +Y -> glTF -Z -> Roblox LookVector),
# feet on Z=0, body centred on the origin, 1 Blender unit = 1 stud.
import bpy, sys, json
import numpy as np
from mathutils import Matrix

argv = sys.argv[sys.argv.index("--") + 1:]
src, out, target_h = argv[0], argv[1], float(argv[2])
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
assert len(meshes) == 1, meshes
ob = meshes[0]
# drop the importer's empty parents but keep the world transform
mw = ob.matrix_world.copy()
ob.parent = None
ob.matrix_world = mw
bpy.context.view_layer.objects.active = ob
ob.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for o in list(bpy.context.scene.objects):
    if o is not ob:
        bpy.data.objects.remove(o)

v = np.array([vv.co[:] for vv in ob.data.vertices])
xy = v[:, :2] - v[:, :2].mean(0)
w, vecs = np.linalg.eigh(np.cov(xy.T))
axis = vecs[:, np.argmax(w)]                    # spine direction in XY
proj = xy @ axis
# head end = the end that holds the highest vertices (ears)
top = v[:, 2] > np.percentile(v[:, 2], 97)
if proj[top].mean() < 0:
    axis = -axis
yaw = np.arctan2(axis[0], axis[1])              # rotate axis onto +Y
R = Matrix.Rotation(yaw, 4, "Z")
ob.data.transform(R)
v = np.array([vv.co[:] for vv in ob.data.vertices])
lo, hi = v.min(0), v.max(0)
s = target_h / (hi[2] - lo[2])
c = (lo + hi) / 2
ob.data.transform(Matrix.Scale(s, 4) @ Matrix.Translation((-c[0], -c[1], -lo[2])))
v = np.array([vv.co[:] for vv in ob.data.vertices])
ob.name = ob.data.name = "LunaMesh"
# weld seams so bone-heat sees one surface
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.mesh.remove_doubles(threshold=0.0005)
bpy.ops.object.mode_set(mode="OBJECT")
islands = None
print("NORM", json.dumps({"yaw_deg": float(np.degrees(yaw)), "scale": s, "lo": v.min(0).tolist(), "hi": v.max(0).tolist(),
                          "verts": len(ob.data.vertices), "tris": sum(len(p.vertices) - 2 for p in ob.data.polygons)}))
bpy.ops.wm.save_as_mainfile(filepath=out)
