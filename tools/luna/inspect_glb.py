# blender -b -P inspect_glb.py -- <in.glb> <out_prefix>
import bpy, sys, math, json
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
src, out = argv[0], argv[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
info = {"objects": [(o.name, o.type) for o in bpy.context.scene.objects]}
lo = Vector((1e9,) * 3); hi = Vector((-1e9,) * 3)
tris = 0
for o in meshes:
    me = o.data
    me.calc_loop_triangles()
    tris += len(me.loop_triangles)
    for v in me.vertices:
        w = o.matrix_world @ v.co
        lo = Vector(map(min, lo, w)); hi = Vector(map(max, hi, w))
info.update(tris=tris, verts=sum(len(o.data.vertices) for o in meshes), lo=list(lo), hi=list(hi),
            size=list(hi - lo), materials=[m.name for o in meshes for m in o.data.materials])
print("INFO", json.dumps(info))

scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"
scene.display.shading.color_type = "TEXTURE"
scene.render.resolution_x = scene.render.resolution_y = 768
scene.render.film_transparent = False
world = bpy.data.worlds.new("w"); scene.world = world
world.color = (0.35, 0.35, 0.38)
center = (lo + hi) / 2
radius = (hi - lo).length * 0.9
cam_data = bpy.data.cameras.new("cam"); cam = bpy.data.objects.new("cam", cam_data)
scene.collection.objects.link(cam); scene.camera = cam
cam_data.type = "ORTHO"; cam_data.ortho_scale = max(hi - lo) * 1.15
views = {"front": (0, -1, 0), "side": (1, 0, 0), "back": (0, 1, 0), "three": (0.7, -0.7, 0.35), "top": (0, -0.01, 1)}
for name, d in views.items():
    d = Vector(d).normalized()
    cam.location = center + d * radius * 2
    cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = f"{out}_{name}.png"
    bpy.ops.render.render(write_still=True)
