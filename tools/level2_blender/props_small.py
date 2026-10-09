"""Level 2 small saturated props. Run only in independent headless Blender."""
import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).parent))
import kit


def plain(name, rgb, roblox_material="SmoothPlastic"):
    """Register a map-free kit material in the same manifest shape as kit.material()."""
    if name in kit.MATERIALS:
        return name
    mat = bpy.data.materials.new("L2K_" + name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*map(kit.linear, rgb), 1)
    bsdf.inputs["Roughness"].default_value = .29 if roblox_material == "Glass" else .45
    if roblox_material == "Glass":
        bsdf.inputs["Transmission Weight"].default_value = .78
        bsdf.inputs["Roughness"].default_value = .08
        bsdf.inputs["Alpha"].default_value = .16
        mat.surface_render_method = "BLENDED"
    kit.MATERIALS[name] = {"blender": mat, "robloxMaterial": roblox_material,
                           "variant": None, "color": list(rgb), "tile_m": 1}
    return name


def bar(mesh, a, b, radius, mat, sides=5):
    """A low-sided solid rod between two Roblox-axis points."""
    a, b = Vector(a), Vector(b)
    axis = (b - a).normalized()
    ref = Vector((0, 0, 1)) if abs(axis.z) < .9 else Vector((1, 0, 0))
    u = axis.cross(ref).normalized() * radius
    v = axis.cross(u).normalized() * radius
    verts = []
    for p in (a, b):
        verts.extend([tuple(p + math.cos(2 * math.pi * i / sides) * u +
                            math.sin(2 * math.pi * i / sides) * v) for i in range(sides)])
    faces = [tuple(reversed(range(sides))), tuple(range(sides, sides * 2))]
    faces += [(i, (i + 1) % sides, (i + 1) % sides + sides, i + sides) for i in range(sides)]
    mesh.raw(verts, faces, mat)


def ring(mesh, center, radius, tube, mat, plane="XZ", major=16, minor=4,
         scale_x=1, scale_z=1):
    verts, faces = [], []
    cx, cy, cz = center
    for i in range(major):
        t = 2 * math.pi * i / major
        for j in range(minor):
            q = 2 * math.pi * j / minor
            r = radius + tube * math.cos(q)
            if plane == "XZ":
                verts.append((cx + r * math.cos(t) * scale_x, cy + tube * math.sin(q),
                              cz + r * math.sin(t) * scale_z))
            else:
                verts.append((cx + r * math.cos(t), cy + r * math.sin(t), cz + tube * math.sin(q)))
    for i in range(major):
        for j in range(minor):
            a = i * minor + j
            b = ((i + 1) % major) * minor + j
            faces.append((a, b, ((i + 1) % major) * minor + (j + 1) % minor,
                          i * minor + (j + 1) % minor))
    mesh.raw(verts, faces, mat, smooth=True)


def ball(mesh, center, radius, mat, lon=8, lat=4):
    cx, cy, cz = center
    verts = [(cx, cy + radius, cz)]
    for j in range(1, lat):
        p = math.pi * j / lat
        for i in range(lon):
            t = 2 * math.pi * i / lon
            verts.append((cx + radius * math.sin(p) * math.cos(t),
                          cy + radius * math.cos(p), cz + radius * math.sin(p) * math.sin(t)))
    verts.append((cx, cy - radius, cz))
    faces = []
    for i in range(lon):
        faces.append((0, 1 + i, 1 + (i + 1) % lon))
    for j in range(lat - 2):
        for i in range(lon):
            a = 1 + j * lon + i
            b = 1 + j * lon + (i + 1) % lon
            faces.append((a, a + lon, b + lon, b))
    bottom = len(verts) - 1
    for i in range(lon):
        faces.append((bottom, bottom - lon + (i + 1) % lon, bottom - lon + i))
    mesh.raw(verts, faces, mat, smooth=True)


def face_stroke(mesh, a, b, width, z, mat):
    """Two-triangle raised mark on a wall-facing dial."""
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    length = math.hypot(dx, dy)
    nx, ny = -dy * width / (2 * length), dx * width / (2 * length)
    mesh.raw([(ax + nx, ay + ny, z), (bx + nx, by + ny, z),
              (bx - nx, by - ny, z), (ax - nx, ay - ny, z)],
             [(0, 3, 2, 1)], mat)


def ellipse_disk(mesh, center, rx, rz, mat, sides=16):
    cx, cy, cz = center
    verts = [(cx + rx * math.cos(2 * math.pi * i / sides), cy,
              cz + rz * math.sin(2 * math.pi * i / sides)) for i in range(sides)]
    mesh.raw(verts, [tuple(range(sides))], mat)


def dome(mesh, base_y, rings, mat, sides=16):
    verts = []
    for y, r in rings:
        verts.extend((r * math.cos(2 * math.pi * i / sides), base_y + y,
                      r * math.sin(2 * math.pi * i / sides)) for i in range(sides))
    faces = []
    for j in range(len(rings) - 1):
        for i in range(sides):
            faces.append((j * sides + i, j * sides + (i + 1) % sides,
                          (j + 1) * sides + (i + 1) % sides, (j + 1) * sides + i))
    faces.append(tuple((len(rings) - 1) * sides + i for i in range(sides)))
    mesh.raw(verts, faces, mat, smooth=True)


def cone_section(mesh, y0, y1, r0, r1, mat, x=0, z=0, sides=12):
    verts = []
    for y, r in ((y0, r0), (y1, r1)):
        verts.extend((x + r * math.cos(2 * math.pi * i / sides), y,
                      z + r * math.sin(2 * math.pi * i / sides)) for i in range(sides))
    faces = [tuple(reversed(range(sides))), tuple(range(sides, 2 * sides))]
    faces += [(i, (i + 1) % sides, (i + 1) % sides + sides, i + sides) for i in range(sides)]
    mesh.raw(verts, faces, mat, smooth=True)


def panel(mesh, lower_z, upper_z, mat):
    """Sloped, solid A-frame face, separated from the ground by two feet."""
    x, y0, y1, t = .67, .25, 2.18, .075
    verts = [(-x, y0, lower_z), (x, y0, lower_z), (x * .79, y1, upper_z),
             (-x * .79, y1, upper_z), (-x, y0, lower_z + t), (x, y0, lower_z + t),
             (x * .79, y1, upper_z + t), (-x * .79, y1, upper_z + t)]
    faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5),
             (2, 3, 7, 6), (3, 0, 4, 7)]
    mesh.raw(verts, faces, mat)


def build():
    for name, color in {
        "Lagoon": (20, 166, 210), "Orange": (255, 110, 20),
        "SignalYellow": (255, 205, 0), "AidGreen": (0, 160, 70),
        "WhitePlastic": (245, 245, 240), "GlassPale": (180, 220, 230),
        "CoralPlastic": (255, 99, 80), "Lime": (157, 222, 35),
        "Charcoal": (32, 39, 42), "SafetyRed": (217, 31, 31),
    }.items():
        plain(name, color, "Glass" if name == "GlassPale" else "SmoothPlastic")

    m = kit.Mesh("Small_Bin")
    m.cylinder((0, .93, 0), .65, 1.78, "Lagoon", segments=16)
    m.cylinder((0, 1.84, 0), .72, .20, "Lagoon", segments=16)
    # A continuous dome keeps the light-catching rim and swing seam.
    dome(m, 1.90, ((0, .67), (.13, .61), (.29, .49), (.40, .30), (.50, .05)), "Lagoon")
    m.box((0, 2.095, -.611), (.83, .27, .025), "Charcoal", bevel=.025)
    m.box((0, 2.105, -.636), (.77, .20, .025), "Lagoon", bevel=.035)
    m.collider("L2K Bin Collision", (0, 1.2, 0), (1.4, 2.4, 1.4), ground=False)
    m.finish()

    m = kit.Mesh("Small_Cones")
    for offset, scale in ((0, .68), (.48, 1.0)):
        y = offset
        m.box((0, y + .07, 0), (1.50 * scale, .14, 1.50 * scale), "Orange", bevel=.035)
        cone_section(m, y + .13, y + .50 * scale, .58 * scale, .42 * scale, "Orange")
        cone_section(m, y + .50 * scale, y + .96 * scale, .42 * scale, .29 * scale, "WhitePlastic")
        cone_section(m, y + .96 * scale, y + 1.72 * scale, .29 * scale, .105 * scale, "Orange")
    m.collider("L2K Cones Collision", (0, 1.1, 0), (1.5, 2.2, 1.5), ground=False)
    m.finish()

    m = kit.Mesh("Small_Extinguisher", RecommendedMountY=2.0)
    # Back at z=0; door and glass face outward along -z.
    m.box((0, 1.30, -.08), (1.4, 2.6, .16), "Steel", bevel=.025)
    for x in (-.65, .65):
        m.box((x, 1.30, -.51), (.10, 2.6, .10), "Steel", bevel=.02)
    for y in (.06, 2.54):
        m.box((0, y, -.51), (1.4, .12, .10), "Steel", bevel=.02)
    m.cylinder((0, 1.19, -.31), .24, 1.60, "SafetyRed", segments=12)
    m.cylinder((0, 2.06, -.31), .10, .18, "Steel", segments=10)
    bar(m, (-.19, 2.15, -.32), (.26, 2.15, -.32), .035, "Steel")
    bar(m, (-.19, 2.10, -.32), (-.35, .72, -.32), .035, "Charcoal")
    m.box((0, 1.3, -.562), (1.14, 2.32, .018), "GlassPale", bevel=0)
    m.box((-.62, 1.2, -.58), (.09, .18, .08), "Steel", bevel=.01)
    m.finish()

    m = kit.Mesh("Small_FirstAid", RecommendedMountY=3.0)
    m.box((0, .90, -.20), (1.8, 1.8, .40), "WhitePlastic", bevel=.045)
    m.box((0, .90, -.43), (1.65, 1.65, .08), "WhitePlastic", bevel=.035)
    m.box((0, .90, -.482), (.26, .91, .025), "AidGreen", bevel=0)
    m.box((0, .90, -.484), (.91, .26, .025), "AidGreen", bevel=0)
    m.box((-.75, .90, -.49), (.10, .17, .07), "Steel", bevel=.01)
    m.finish()

    m = kit.Mesh("Small_Fountain", RecommendedMountY=2.8)
    m.box((0, .64, -.075), (1.5, 1.28, .15), "CoralPlastic", bevel=.08)
    m.box((0, .45, -.31), (.45, .78, .36), "Steel", bevel=.035)
    # Solid basin with an inset dark water well and a raised bullnose rim.
    m.box((0, .79, -.64), (1.60, .49, 1.05), "CoralPlastic", bevel=.14)
    ellipse_disk(m, (0, 1.045, -.65), .62, .36, "Charcoal")
    ring(m, (0, 1.07, -.65), 1, .065, "CoralPlastic", major=16, minor=3,
         scale_x=.70, scale_z=.44)
    m.cylinder((.50, 1.17, -.37), .085, .22, "Steel", segments=10)
    m.cylinder((0, .83, -1.195), .13, .08, "Steel", segments=10, axis="Z")
    m.finish()

    m = kit.Mesh("Small_Noodles")
    # Nine foam rods and a lagoon-coated wire basket share four color chunks.
    coords = [(-.45, -.43), (0, -.52), (.44, -.40), (-.55, .02),
              (-.02, 0), (.53, .05), (-.40, .47), (.06, .48), (.48, .43)]
    mats = ("CoralPlastic", "SignalYellow", "Lagoon", "Lime")
    for i, (x, z) in enumerate(coords):
        h = 3.12 + .16 * (i % 3)
        m.cylinder((x, .12 + h / 2, z), .18, h, mats[i % 4], segments=8)
    for y in (.10, 1.72, 2.55):
        ring(m, (0, y, 0), .81, .026, "Lagoon", major=12, minor=3)
    for i in range(8):
        t = i * math.pi / 4
        x, z = .81 * math.cos(t), .81 * math.sin(t)
        bar(m, (x, .10, z), (x, 2.55, z), .018, "Lagoon", sides=4)
    m.collider("L2K Noodle Basket Collision", (0, 1.8, 0), (1.65, 3.6, 1.65), ground=False)
    m.finish()

    m = kit.Mesh("Small_Towels")
    for i in range(4):
        y = .12 + i * .19
        base = "CoralPlastic" if i % 2 else "Lagoon"
        m.box((0, y, 0), (1.6, .18, .96), base, bevel=.035)
        for x in (-.39, .0, .39):
            m.box((x, y + .095, 0), (.16, .018, .93), "WhitePlastic", bevel=0)
        m.box((0, y, -.489), (1.52, .09, .018), "WhitePlastic", bevel=0)
    for x in (-.38, .38):
        # Yellow soles and the two V straps on top of the towel pile.
        m.box((x, .94, -.04), (.47, .09, .82), "SignalYellow", bevel=.09)
        bar(m, (x, 1.06, -.31), (x - .16, 1.09, .15), .028, "SignalYellow", sides=4)
        bar(m, (x, 1.06, -.31), (x + .16, 1.09, .15), .028, "SignalYellow", sides=4)
    m.finish()

    m = kit.Mesh("Small_WetFloor")
    panel(m, -.54, -.10, "SignalYellow")
    panel(m, .47, .03, "SignalYellow")
    for z in (-.53, .47):
        for x in (-.52, .52):
            m.box((x, .15, z), (.26, .30, .13), "SignalYellow", bevel=.025)
    bar(m, (-.55, 2.26, -.035), (.55, 2.26, -.035), .085, "SignalYellow", sides=8)
    # Raised slip warning: triangle, head and angled limbs on the front slope.
    def face_z(y):
        return -.54 + (.44 * (y - .25) / 1.93) - .025
    for a, b in (((0, 1.72), (-.44, .82)), ((-.44, .82), (.44, .82)),
                 ((.44, .82), (0, 1.72))):
        bar(m, (a[0], a[1], face_z(a[1])), (b[0], b[1], face_z(b[1])),
            .025, "Charcoal", sides=4)
    m.cylinder((-.10, 1.34, face_z(1.34) - .018), .07, .028, "Charcoal", segments=8, axis="Z")
    for a, b in (((-.08, 1.22), (.10, 1.07)), ((.10, 1.07), (.28, 1.16)),
                 ((.08, 1.11), (-.03, .94)), ((-.03, .94), (.16, .87)),
                 ((-.08, 1.21), (-.23, 1.04)), ((.04, 1.15), (.20, 1.37))):
        bar(m, (a[0], a[1], face_z(a[1]) - .018),
            (b[0], b[1], face_z(b[1]) - .018), .027, "Charcoal", sides=4)
    m.collider("L2K Wet Floor Collision", (0, 1.2, 0), (1.4, 2.4, 1.2), ground=False)
    m.finish()

    m = kit.Mesh("Small_Clock", RecommendedMountY=6.0)
    m.cylinder((0, 1.1, -.13), 1.09, .26, "CoralPlastic", segments=20, axis="Z")
    m.cylinder((0, 1.1, -.274), .96, .035, "WhitePlastic", segments=20, axis="Z")
    ring(m, (0, 1.1, -.28), 1.015, .072, "CoralPlastic", plane="XY", major=20, minor=3)
    for i in range(24):
        t = 2 * math.pi * i / 24
        r0 = .79 if i % 2 == 0 else .85
        r1 = .91
        face_stroke(m, (r0 * math.sin(t), 1.1 + r0 * math.cos(t)),
                    (r1 * math.sin(t), 1.1 + r1 * math.cos(t)),
                    .018 if i % 2 else .028, -.302, "Charcoal")
    for degrees, length, thick in ((60, .72, .032), (65, .49, .052)):
        t = math.radians(degrees)
        face_stroke(m, (0, 1.1), (-length * math.sin(t), 1.1 + length * math.cos(t)),
                    thick * 2, -.325, "Charcoal")
    m.cylinder((0, 1.1, -.342), .055, .035, "Charcoal", segments=8, axis="Z")
    m.finish()

    m = kit.Mesh("Small_RopeCoil")
    rope = "WhitePlastic"
    for layer, radius, phase in ((0, 1.17, 0), (1, .88, .32)):
        pts = []
        for i in range(9):
            t = 2 * math.pi * i / 8 + phase
            pts.append((radius * math.cos(t), .18 + layer * .25 + .04 * math.sin(3 * t),
                        radius * math.sin(t)))
        for a, b in zip(pts, pts[1:]):
            bar(m, a, b, .043, rope, sides=4)
        for i in range(6):
            t = 2 * math.pi * i / 6 + phase
            p = (radius * math.cos(t), .20 + layer * .25 + .04 * math.sin(3 * t),
                 radius * math.sin(t))
            ball(m, p, .22, ("CoralPlastic", "SignalYellow", "Lagoon")[(i + layer) % 3],
                 lon=8, lat=3)
    m.finish()

    return list(kit.COMPONENTS)


def _review():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = scene.render.resolution_y = 700
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "Standard"
    scene.world = bpy.data.worlds.new("Review ambient")
    scene.world.color = (.55, .60, .66)
    col = bpy.data.collections.new("V2 Review")
    scene.collection.children.link(col)
    camera_data = bpy.data.cameras.new("Review Camera")
    camera = bpy.data.objects.new("Review Camera", camera_data)
    col.objects.link(camera)
    scene.camera = camera
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = 7.5 * kit.S
    light_data = bpy.data.lights.new("Large softbox", "AREA")
    light_data.energy = 360
    light_data.shape = "DISK"
    light_data.size = 7
    light = bpy.data.objects.new("Large softbox", light_data)
    col.objects.link(light)
    light.location = kit.to_blender((-3, 9, -5))
    light.rotation_euler = (kit.to_blender((0, 2, 0)) - light.location).to_track_quat("-Z", "Y").to_euler()
    sun_data = bpy.data.lights.new("Fill sun", "SUN")
    sun_data.energy = .65
    sun = bpy.data.objects.new("Fill sun", sun_data)
    col.objects.link(sun)
    sun.rotation_euler = (math.radians(30), math.radians(-20), math.radians(20))
    review_dir = kit.KIT_DIR / "review" / "V2"
    review_dir.mkdir(parents=True, exist_ok=True)
    def review_mat(name, rgb):
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes["Principled BSDF"]
        bsdf.inputs["Base Color"].default_value = (*rgb, 1)
        bsdf.inputs["Roughness"].default_value = .8
        return mat
    grey = review_mat("Review capsule grey", (.18, .20, .22))
    stage = review_mat("Review stage", (.43, .46, .46))
    wall_mat = review_mat("Review wall", (.56, .59, .57))
    names = list(kit.COMPONENTS)
    images = []
    mount = {"Small_Extinguisher": 2.0, "Small_FirstAid": 3.0,
             "Small_Fountain": 2.8, "Small_Clock": 5.9}
    for name in names:
        objects = []
        y = mount.get(name, 0)
        placed = kit.place(col, name, (0, y, 0))
        objects.extend([o for o in col.objects if o.get("l2k_component") == name])
        # Scale reference: a simple 5-stud grey person capsule.
        for zc, r, depth in ((2.5, .43, 4.14), (.43, .43, .86), (4.57, .43, .86)):
            if depth == 4.14:
                bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=r * kit.S, depth=depth * kit.S,
                                                    location=kit.to_blender((-2.05, zc, .35)))
            else:
                bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=6, radius=r * kit.S,
                                                    location=kit.to_blender((-2.05, zc, .35)))
            o = bpy.context.object
            o.data.materials.append(grey)
            objects.append(o)
        bpy.ops.mesh.primitive_cube_add(size=1, location=kit.to_blender((0, -.08, 0)))
        floor = bpy.context.object
        floor.dimensions = (7 * kit.S, 7 * kit.S, .16 * kit.S)
        floor.data.materials.append(stage)
        objects.append(floor)
        if name in mount:
            bpy.ops.mesh.primitive_cube_add(size=1, location=kit.to_blender((0, 4.5, .19)))
            wall = bpy.context.object
            wall.dimensions = (4.2 * kit.S, .2 * kit.S, 9.3 * kit.S)
            wall.data.materials.append(wall_mat)
            objects.append(wall)
        target_y = 4.1 if name == "Small_Clock" else 2.45
        camera_data.ortho_scale = (9.8 if name == "Small_Clock" else 7.5) * kit.S
        camera.location = kit.to_blender((4.8, target_y + 2.5, -10.5))
        target = kit.to_blender((0, target_y, 0))
        camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = str(review_dir / (name + ".png"))
        bpy.ops.render.render(write_still=True)
        images.append(Path(scene.render.filepath))
        for o in objects:
            bpy.data.objects.remove(o, do_unlink=True)
    # Pixel-copy the reviewed renders into a contact sheet, with no extra image dependency.
    tile = 700
    canvas = np.ones((2 * tile, 5 * tile, 4), dtype=np.float32)
    for i, path in enumerate(images):
        img = bpy.data.images.load(str(path), check_existing=False)
        pixels = np.empty(tile * tile * 4, dtype=np.float32)
        img.pixels.foreach_get(pixels)
        row, column = divmod(i, 5)
        row = 1 - row  # Blender image pixels start at the bottom.
        canvas[row * tile:(row + 1) * tile, column * tile:(column + 1) * tile] = pixels.reshape(tile, tile, 4)
        bpy.data.images.remove(img)
    sheet = bpy.data.images.new("V2 contact sheet", width=5 * tile, height=2 * tile, alpha=True)
    sheet.pixels.foreach_set(canvas.ravel())
    sheet.filepath_raw = str(review_dir / "_sheet.png")
    sheet.file_format = "PNG"
    sheet.save()
    bpy.data.images.remove(sheet)
    return images


if __name__ == "__main__":
    bpy.ops.wm.read_factory_settings(use_empty=True)
    names = build()
    assert len(names) == 10, names
    for name in names:
        mesh = kit.COMPONENTS[name]["mesh"]
        mesh.calc_loop_triangles()
        triangles = len(mesh.loop_triangles)
        chunks = len({t.material_index for t in mesh.loop_triangles})
        assert triangles <= 600, (name, triangles)
        assert chunks <= 4, (name, chunks)
        print(f"PROP_BUDGET {name}: {triangles} tris, {chunks} chunks", flush=True)
    kit.EXPORT_DIR = kit.KIT_DIR / "jobs" / "V2" / "export"
    manifest = kit.export()
    assert len(manifest["components"]) == 10
    _review()
    print("V2_OK", flush=True)
