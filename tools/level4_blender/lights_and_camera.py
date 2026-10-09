# Level 4 cinema, Blender rebuild - lights from the Studio dump, world, and a preview-render helper.
import ast, bpy, json, math, os, re
from mathutils import Matrix, Vector

HERE = r"G:\Roblox\MongoTV\tools\level4_blender"
S, OX = 0.28, 23000.0
D = json.load(open(os.path.join(HERE, "l4_layout.json")))   # dump + layout_edits.py


def rb2b(x, y, z):
    return Vector(((x - OX) * S, -z * S, y * S))


def srgb2lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def build_lights():
    c = bpy.data.collections.get("L4 Lights")
    if c:
        for o in list(c.objects):
            bpy.data.objects.remove(o, do_unlink=True)
    else:
        c = bpy.data.collections.new("L4 Lights")
        bpy.data.collections["L4 Cinema"].children.link(c)
    # The final ceiling package owns these fixtures. Read its literal export list without running its builder.
    tree = ast.parse(open(os.path.join(HERE, "ceilings.py"), encoding="utf-8").read())
    superseded = [re.compile(p) for n in tree.body if isinstance(n, ast.Assign)
                  and any(isinstance(t, ast.Name) and t.id == "LIGHTS_SUPERSEDED" for t in n.targets)
                  for p in ast.literal_eval(n.value)]
    removed, count = [], 0
    for i, l in enumerate(D["lights"]):
        if any(p.search(l["p"]) for p in superseded):
            removed.append(l["p"])
            continue
        col = tuple(srgb2lin(v / 255.0) for v in l["col"])
        rng = (l.get("rng") or 16) * S
        if l["c"] == "SpotLight":
            ld = bpy.data.lights.new("L4L_%d" % i, "SPOT")
            ld.spot_size = math.radians(max(20, min(170, l.get("ang") or 90)))
            ld.spot_blend = 0.6
        else:
            ld = bpy.data.lights.new("L4L_%d" % i, "POINT")
        ld.color = col
        ld.energy = 2500.0 * max(0.2, l["b"]) * (rng / 4.0) ** 2
        ld.shadow_soft_size = 0.4
        ld.use_custom_distance = True
        ld.cutoff_distance = rng * 1.3
        o = bpy.data.objects.new("L4L_" + l["p"].rsplit("/", 1)[-1], ld)
        o.location = rb2b(*l["pos"])
        if l["c"] == "SpotLight":
            face = l.get("face") or "Bottom"
            # most Studio spots in this build hang from ceilings pointing down
            o.rotation_euler = (0, 0, 0) if face in ("Bottom",) else (math.radians(90), 0, 0)
        o["l4_light"] = 1
        o["l4_src_light"] = i
        c.objects.link(o)
        count += 1
    print("L4 legacy ceiling lights omitted:", removed)
    return count


def world():
    sc = bpy.context.scene
    w = sc.world or bpy.data.worlds.new("L4World")
    sc.world = w
    w.use_nodes = True
    bg = w.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.025, 0.028, 0.04, 1)
    bg.inputs["Strength"].default_value = 0.12
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x, sc.render.resolution_y = 1280, 720
    sc.view_settings.view_transform = "AgX"
    sc.view_settings.look = "AgX - Medium High Contrast"
    sc.view_settings.exposure = 0.0
    try:
        sc.eevee.use_raytracing = True
    except Exception:
        pass
    sc.eevee.taa_render_samples = 32


def shot(path, cam_rb, look_rb, lens=18):
    cam = bpy.data.objects.get("L4Cam")
    if not cam:
        cam = bpy.data.objects.new("L4Cam", bpy.data.cameras.new("L4Cam"))
        bpy.context.scene.collection.objects.link(cam)
    cam.data.lens = lens
    cam.data.clip_start = 0.05
    cam.data.clip_end = 500
    p, t = rb2b(*cam_rb), rb2b(*look_rb)
    cam.location = p
    cam.rotation_euler = (t - p).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = cam
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return path
