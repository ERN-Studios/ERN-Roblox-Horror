"""Classic Level 1 quality pass; independent headless project, V1 untouched.

python tools/level1_blender/prepare_v2_textures.py
D:/Blender/blender.exe -b --factory-startup --python-exit-code 1 -P tools/level1_blender/build_v2.py
"""
from pathlib import Path
import hashlib, importlib.util, json, math
import bpy, numpy as np
from mathutils import Matrix, Vector

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("l1_existing_builder", HERE / "build.py")
b = importlib.util.module_from_spec(spec)
spec.loader.exec_module(b)
b.OUT = b.ROOT / "assets/level1/blender-v2"
b.TEX = b.OUT / "textures"
Mesh = b.Mesh
S = b.S


def image_node(mat, filename, noncolor=False):
    path = b.TEX / filename
    assert path.exists(), path
    image = bpy.data.images.load(str(path), check_existing=True)
    image.filepath = "//textures/" + filename
    if noncolor:
        image.colorspace_settings.name = "Non-Color"
    node = mat.node_tree.nodes.new("ShaderNodeTexImage")
    node.image, node.extension = image, "REPEAT"
    return node


def finish_material(name, stem, tile=3, metal=False):
    if name not in b.MATERIALS:
        b.material(name, (255, 255, 255), .62, tile=tile, metal=1 if metal else 0)
    entry = b.MATERIALS[name]
    mat = entry["blender"]
    mat.node_tree.nodes.clear()
    bsdf = mat.node_tree.nodes.new("ShaderNodeBsdfPrincipled")
    mat.node_tree.links.new(bsdf.outputs["BSDF"], mat.node_tree.nodes.new("ShaderNodeOutputMaterial").inputs["Surface"])
    maps = {"albedo": "prop_" + stem + "_albedo.png", "normal": "prop_normal.png", "rough": "prop_rough.png",
            "metal": "prop_metal.png" if metal else "prop_paintmetal.png"}
    for key, socket in (("albedo", "Base Color"), ("rough", "Roughness"), ("metal", "Metallic")):
        tex = image_node(mat, maps[key], key != "albedo")
        mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs[socket])
    normal = mat.node_tree.nodes.new("ShaderNodeNormalMap")
    tex = image_node(mat, maps["normal"], True)
    mat.node_tree.links.new(tex.outputs["Color"], normal.inputs["Color"])
    mat.node_tree.links.new(normal.outputs["Normal"], bsdf.inputs["Normal"])
    mat["l1_tile_studs"] = tile
    entry.update(color=[255, 255, 255], roughness=.62, metalness=1 if metal else 0,
                 tileStuds=tile, maps=maps, robloxMaterial="Metal" if metal else "SmoothPlastic")


def replace(name):
    old = b.COMPONENTS.pop(name, None)
    if old:
        bpy.data.meshes.remove(old["mesh"])
    return Mesh(name)


def frame(mesh, x, y, z, width, height, depth, thickness, mat):
    for side in (-1, 1):
        mesh.box((x + side * (width - thickness) / 2, y, z), (thickness, depth, height), mat, .025)
        mesh.box((x, y, z + side * (height - thickness) / 2), (width, depth, thickness), mat, .025)
    return mesh


def bolt(mesh, x, y, z, radius=.07):
    mesh.cylinder((x, y, z), radius, .065, "Steel", segments=8, axis="Y")
    mesh.box((x, y + .04, z), (radius * 1.25, .012, .014), "Dark", 0)


def model_fixture(name, lit=True):
    m = replace(name)
    # Original image: five fluorescent banks, five rows of deeply recessed louvers.
    m.box((0, 0, .06), (4, 4, .12), "Cream", .02)
    for side in (-1, 1):
        m.box((side * 1.94, 0, -.22), (.12, 4, .56), "Cream", .018)
        m.box((0, side * 1.94, -.22), (4, .12, .56), "Cream", .018)
    for x in np.linspace(-1.42, 1.42, 5):
        # Each reflector is a shallow V behind one long lamp, modelled rather than a flat picture.
        for side in (-1, 1):
            R = Matrix.Rotation(side * .28, 3, "Y")
            m.box((x + side * .19, 0, -.06), (.4, 3.65, .035), "Steel", .006, R)
        m.cylinder((x, 0, -.20), .065, 3.44, "Lamp" if lit else "Porcelain", segments=12, axis="Y")
        for y in (-1.69, 1.69):
            m.cylinder((x, y, -.20), .085, .13, "Porcelain", segments=10, axis="Y")
    for axis in (0, 1):
        for value in np.linspace(-1.77, 1.77, 6):
            pos = (value, 0, -.29) if axis == 0 else (0, value, -.29)
            size = (.033, 3.56, .40) if axis == 0 else (3.56, .033, .40)
            m.box(pos, size, "Steel", .008)
    for x in (-1.92, 1.92):
        for y in (-1.92, 1.92):
            m.cylinder((x, y, -.51), .04, .016, "Steel", segments=8)
    m.finish()


def build_components():
    b.build_components()
    # Exact original pattern. Stronger yellow comes from a material tint, not edited pixels.
    wall = b.MATERIALS["Wallpaper"]
    wall["color"], wall["tintTexture"] = [255, 235, 150], True
    mat = wall["blender"]
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    link = next(link for link in mat.node_tree.links if link.to_socket == bsdf.inputs["Base Color"])
    texture = link.from_socket
    mat.node_tree.links.remove(link)
    mix = mat.node_tree.nodes.new("ShaderNodeMixRGB")
    mix.blend_type, mix.inputs[0].default_value = "MULTIPLY", 1
    mix.inputs[2].default_value = (*[b.linear(v) for v in wall["color"]], 1)
    mat.node_tree.links.new(texture, mix.inputs[1])
    mat.node_tree.links.new(mix.outputs[0], bsdf.inputs["Base Color"])
    for name, stem, metal in (("Steel", "steel", True), ("Trim", "cream", False), ("Cream", "cream", False),
                              ("Ochre", "ochre", False), ("Olive", "olive", False), ("Red", "red", False),
                              ("Copper", "copper", True), ("Porcelain", "porcelain", False)):
        finish_material(name, stem, tile=2 if name != "Copper" else .8, metal=metal)
    b.material("GreenGlass", (143, 166, 113), .22, tile=1)
    glass = b.MATERIALS["GreenGlass"]
    glass.update(robloxMaterial="Glass", transparency=.38)
    shader = glass["blender"].node_tree.nodes.get("Principled BSDF")
    shader.inputs["Transmission Weight"].default_value = .45
    shader.inputs["Alpha"].default_value = .62
    shader.inputs["IOR"].default_value = 1.46
    model_fixture("Fluorescent", True)
    model_fixture("FluorescentDark", False)
    p = replace("Pillar").box((0, 0, 7), (2.1, 2.1, 14), "Wallpaper", .16)
    p.box((0, 0, .38), (2.5, 2.5, .76), "Trim", .075)
    p.box((0, 0, .81), (2.3, 2.3, .10), "Trim", .025)
    p.box((0, 0, 13.72), (2.4, 2.4, .56), "Trim", .07)
    p.collider((0, 0, 7), (2.5, 2.5, 14)).finish()
    low = Mesh("WallShort").box((0, 0, 4.16), (6, 1, 8.32), "Wallpaper", .025)
    for y in (-.505, .505):
        low.box((0, y, .37), (6, .12, .74), "Trim", .018)
    low.box((0, 0, 8.41), (6, 1.14, .18), "Trim", .025)
    low.collider((0, 0, 4.25), (6, 1.14, 8.5)).finish()

    # Relay shell is open. Door, fuse, label, indicator and release handle remain separate live controls.
    relay = Mesh("RelayShell").box((0, .08, 3.525), (5.85, .16, 7.05), "Cream", .045)
    for x in (-2.8, 2.8):
        relay.box((x, .62, 3.525), (.25, 1.08, 7.05), "Cream", .04)
    for z in (.14, 6.91):
        relay.box((0, .62, z), (5.6, 1.08, .28), "Cream", .04)
    frame(relay, 0, 1.12, 3.525, 5.65, 6.85, .13, .12, "Steel")
    relay.box((0, .2, 3.4), (4.8, .16, 5.8), "Cream", .02)
    for z in (1.8, 5.0):
        relay.box((0, .33, z), (1.7, .18, .45), "Steel")
        for x in (-.7, .7):
            bolt(relay, x, .48, z)
    for z in (.85, 6.2):
        relay.cylinder((-2.8, 1.13, z), .105, .58, "Steel", segments=12)
    for x in (-2.57, 2.57):
        for z in (.48, 6.57):
            bolt(relay, x, 1.23, z)
    relay.finish()
    door = replace("RelayDoor").box((0, 0, 0), (5.15, .18, 6.25), "Cream", .06)
    frame(door, 0, .11, 0, 4.9, 6, .1, .09, "Cream")
    for z in (-2.65, 2.65):
        door.cylinder((-2.52, .10, z), .10, .55, "Steel", segments=12)
    for x in (-2.22, 2.22):
        for z in (-2.79, 2.79):
            bolt(door, x, .19, z)
    door.finish()

    box = Mesh("FuseBoxShell").box((0, .58, 2.225), (4.2, 1.16, 4.2), "Ochre", .08)
    # Recessed receiver bay; porcelain holders are instanced per actual configured fuse slot.
    box.box((0, 1.205, 2.0), (3.0, .09, 2.5), "Dark", .045)
    frame(box, 0, 1.29, 2.225, 4.45, 4.45, .18, .14, "Steel")
    frame(box, 0, 1.34, 2.0, 3.15, 2.7, .16, .13, "Steel")
    for x in (-1.92, 1.92):
        for z in (.3, 4.15):
            bolt(box, x, 1.45, z, .095)
    for z in (.8, 3.55):
        box.cylinder((-2.07, 1.3, z), .10, .48, "Steel")
    box.box((0, 1.4, .53), (2.65, .07, .29), "Cream", .015)
    box.finish()
    socket = Mesh("FuseSocket").box((0, 0, 0), (.72, .15, 1.75), "Steel", .035)
    socket.box((0, .10, 0), (.44, .10, 1.25), "Dark", .025)
    for z in (-.67, .67):
        socket.box((0, .13, z), (.63, .11, .28), "Porcelain", .07)
        socket.cylinder((0, .21, z), .19, .075, "Copper", segments=12, axis="Y")
    socket.finish()
    lever = Mesh("LeverShell").box((0, .27, 2.325), (3.2, .54, 4.4), "Cream", .09)
    frame(lever, 0, .64, 2.325, 3.45, 4.65, .16, .12, "Steel")
    # Cast bearing and side feed-through, as in the ImageGen mechanical reference.
    lever.box((0, .75, 1.84), (1.65, .3, 2.1), "Steel", .10)
    lever.cylinder((0, .95, 1.94), .57, .3, "Steel", segments=20, axis="Y")
    lever.cylinder((0, 1.13, 1.94), .31, .13, "Copper", segments=16, axis="Y")
    for x in (-1.35, 1.35):
        for z in (.35, 4.3):
            bolt(lever, x, .74, z, .095)
    lever.finish()
    shaft = Mesh("LeverShaft").cylinder((0, 0, 1.225), .17, 2.45, "Steel", segments=16)
    shaft.cylinder((0, 0, 1.83), .245, 1.1, "Red", segments=16)
    for z in (1.36, 2.31):
        shaft.cylinder((0, 0, z), .255, .055, "Steel", segments=16)
    shaft.finish()
    Mesh("LeverKnob").sphere((0, 0, 0), .41, "Red").finish()
    core = Mesh("FuseCore").cylinder((0, 0, 1.325), .35, 2.65, "Porcelain", segments=24)
    for z in (.25, .38, .51, 2.13, 2.26, 2.39):
        core.cylinder((0, 0, z), .38, .085, "Porcelain", segments=24)
    core.finish()
    cap = Mesh("FuseCap").cylinder((0, 0, 0), .54, .22, "Copper", segments=24)
    cap.cylinder((0, 0, .11), .50, .035, "Copper", segments=24).finish()
    whole = replace("Fuse").cylinder((0, 0, 1.55), .38, 2.65, "Porcelain", segments=24)
    for z in (.47, .60, .73, 2.39, 2.52, 2.65):
        whole.cylinder((0, 0, z), .41, .085, "Porcelain", segments=24)
    for z in (.17, 2.93):
        whole.cylinder((0, 0, z), .54, .34, "Copper", segments=24)
    whole.finish()

    portal = Mesh("ExitPortal")
    for x in (-3.75, 3.75):
        portal.box((x, .625, 6.25), (1.05, 1.25, 12.5), "Cream", .09)
        portal.box((x + (.34 if x < 0 else -.34), 1.25, 6.0), (.15, .15, 11.7), "Steel", .025)
    portal.box((0, .625, 12.4), (8.55, 1.25, 1.15), "Cream", .09)
    for x in (-3.95, 3.95):
        for z in (.35, 12.64):
            bolt(portal, x, 1.3, z, .12)
    portal.finish()
    leaf = Mesh("ExitDoor")
    # True window aperture in a four-panel leaf; no opaque slab under the wire glass.
    leaf.box((0, 0, 3.16), (7, .35, 6.32), "Olive", .06)
    leaf.box((0, 0, 10.48), (7, .35, 1.04), "Olive", .06)
    for x in (-2.4, 2.4):
        leaf.box((x, 0, 8.2), (2.2, .35, 4.0), "Olive", .045)
    frame(leaf, 0, .22, 8.2, 2.8, 4.3, .15, .17, "Steel")
    leaf.box((0, .2, 8.2), (2.45, .04, 3.95), "GreenGlass", .006)
    for x in np.linspace(-1.15, 1.15, 11):
        leaf.box((x, .23, 8.2), (.012, .014, 3.95), "Steel", 0)
    for z in np.linspace(6.32, 10.08, 17):
        leaf.box((0, .24, z), (2.45, .014, .012), "Steel", 0)
    leaf.box((0, .22, .98), (6.7, .13, 1.8), "Steel", .025)
    leaf.box((-.3, .61, 4.55), (5.75, .27, .31), "Steel", .07)
    for x in (-2.95, 2.65):
        leaf.box((x, .36, 4.55), (.44, .44, 1.25), "Steel", .07)
    for z in (1.2, 5.5, 10.0):
        leaf.cylinder((3.45, .05, z), .105, .60, "Steel", segments=12)
    for x in (-1.28, 1.28):
        for z in (6.13, 10.27):
            bolt(leaf, x, .35, z, .05)
    leaf.finish()


def build_rooms(parent):
    b.build_rooms(parent)
    for name, room in b.ROOMS.items():
        room["selectionWeight"] = 16 if room["variant"] == 0 else (1 if room["variant"] == 1 else 4)
        col = bpy.data.collections[name]
        col["SelectionWeight"] = room["selectionWeight"]
        if room["variant"] == 1:
            # One nicer column in a rare bay, rather than repeated paired columns in half the maze.
            first = next(p for p in room["placements"] if p["component"] == "Pillar")
            room["placements"].remove(first)
            pillars = [ob for ob in col.objects if ob.get("l1_component") == "Pillar"]
            bpy.data.objects.remove(pillars[0], do_unlink=True)
    # Internal dividers change silhouettes without hiding the full-height maze boundary collision.
    for mask in (1, 3, 5, 7, 10, 11, 13, 14):
        original = next(r for r in b.ROOMS.values() if r["mask"] == mask and r["variant"] == 0)
        name = "LowWall_%02d" % mask
        index = len(b.ROOMS)
        offset = ((index % 6) * 30, 0, (index // 6) * 30)
        col = b.collection(name, parent)
        col["OpenMask"], col["CellSize"], col["WallHeight"] = mask, 24, 14
        col["SelectionWeight"], col["ShortWall"] = 3, True
        col["ShortWallHeight"] = 8.5
        placements = []
        for p in original["placements"]:
            comp = p["component"]
            cf = p["cf"]
            rotation = np.array(cf[3:], float).reshape(3, 3)
            M = Matrix((b.C.T @ rotation @ b.C).tolist()).to_4x4()
            M.translation = Vector(b.C.T @ np.array(cf[:3]) * S)
            ob = bpy.data.objects.new(comp, b.COMPONENTS[comp]["mesh"])
            col.objects.link(ob)
            ob.matrix_world = M
            ob.location += Vector((offset[0] * S, -offset[2] * S, 0))
            ob["l1_component"], ob["l1_role"] = comp, p["role"]
            placements.append({"component": comp, "cf": cf, "role": p["role"]})
        # This six-stud divider sits entirely beyond the central +/-8 square and
        # the +/-3 cardinal routing bands. Its authored collider ends at 8.5 too.
        pos, yaw = ((7.8, 0, 9.7), 0) if mask % 2 else ((9.7, 0, 7.8), 90)
        placements.append(b.place(col, "WallShort", pos, yaw, offset, "Detail"))
        b.ROOMS[name] = {**original, "variant": 3, "selectionWeight": 3, "shortWall": True,
                         "shortWallHeight": 8.5, "placements": placements}


def export():
    b.export_chunks()
    path = b.OUT / "export/manifest.json"
    data = json.loads(path.read_text())
    data["version"], data["build"] = 2, "level1-quality-20261002-v2"
    data["reference"] = "concept/puzzle-exit-fixture-reference.png"
    data["references"] = ["concept/puzzle-exit-fixture-reference.png", "concept/exit-door-reference.png",
                           "concept/original-grille-fixture-reference.png", "concepts/original-fixtures/live.png"]
    data["wallpaperSourceAsset"] = 87947439437597
    data["aliases"].update(GridFixture="Fluorescent", LightFixture="Fluorescent", FuseRelay="RelayShell",
                           FuseBox="FuseBoxShell", ExitFrame="ExitPortal")
    data["fixture"] = {"width": 4, "depth": 4, "banks": 5, "grid": [5, 5], "sourceAsset": 135786374638992,
                       "physicalDepth": .62, "liveMaterial": "Lamp"}
    for name in ("RelayShell", "FuseBoxShell", "LeverShell", "ExitPortal", "RelayDoor", "ExitDoor",
                 "LeverShaft", "LeverKnob", "FuseCore", "FuseCap", "FuseSocket"):
        data["components"][name]["puzzleVisual"] = True
    path.write_text(json.dumps(data, indent=2), encoding="utf-8")
    assert len(data["chunks"]) <= 150
    return data


def render_review():
    # Existing room render framing remains useful; replace its component inputs with V2 art.
    b.render_previews()
    scene = bpy.data.scenes.new("L1 V2 Puzzle Detail Review")
    scene.render.engine = "CYCLES"
    scene.cycles.samples, scene.cycles.use_denoising = 40, True
    scene.render.resolution_x, scene.render.resolution_y, scene.render.resolution_percentage = 1600, 1100, 100
    scene.world = bpy.data.scenes["L1_CinematicPreview"].world
    scene.view_settings.view_transform = "AgX"
    col = b.collection("V2 Interactive Prop Detail", scene.collection)
    b.place(col, "Floor")
    b.place(col, "WallHalf", (0, 0, -11.5))
    b.place(col, "Ceiling")
    b.place(col, "Fluorescent", (0, 13.96, 0))
    for comp, pos in (("RelayShell", (-7, 2.5, -10.7)), ("RelayDoor", (-9.8, 6.0, -9.5)),
                       ("Fuse", (-7, 4.3, -10.05)), ("FuseBoxShell", (-.8, 4.0, -10.7)),
                       ("FuseSocket", (-.8, 6.0, -9.27)), ("LeverShell", (5.8, 4, -10.7)),
                       ("LeverShaft", (5.8, 5.9, -9.45)), ("LeverKnob", (5.8, 8.5, -9.45))):
        b.place(col, comp, pos, 180)
    b.area_light(scene, (0, 1, 13.4), 180, 5)
    b.area_light(scene, (-6, 5, 8), 70, 5)
    b.render_camera(scene, "Mechanical Prop Review", (9, 5, 7), (-1.2, 10, 6.1))
    scene.render.filepath = str(b.OUT / "renders/puzzle-detail.png")
    bpy.ops.render.render(write_still=True, scene=scene.name)
    door_scene = bpy.data.scenes.new("L1 V2 Exit Review")
    door_scene.render.engine = "CYCLES"
    door_scene.cycles.samples, door_scene.cycles.use_denoising = 32, True
    door_scene.render.resolution_x, door_scene.render.resolution_y, door_scene.render.resolution_percentage = 1300, 1200, 100
    door_scene.world = scene.world
    door_scene.view_settings.view_transform = "AgX"
    col = b.collection("V2 Exit Detail", door_scene.collection)
    b.place(col, "Floor")
    b.place(col, "ExitPortal", (0, 0, -3))
    b.place(col, "ExitDoor", (0, .15, -4.35))
    b.area_light(door_scene, (-4, 14, 12), 220, 6)
    b.area_light(door_scene, (6, 8, 6), 100, 4)
    b.render_camera(door_scene, "Exit Review", (8, 16, 8.5), (0, 4, 6.6))
    door_scene.render.filepath = str(b.OUT / "renders/exit-detail.png")
    bpy.ops.render.render(write_still=True, scene=door_scene.name)


def main():
    assert bpy.app.background
    assert b.OUT.name == "blender-v2"
    b.OUT.mkdir(parents=True, exist_ok=True)
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    build_components()
    scene = bpy.context.scene
    catalogue = b.collection("L1 Room Catalogue", scene.collection)
    build_rooms(catalogue)
    library = b.collection("L1 Prop Library", scene.collection)
    for i, name in enumerate(b.COMPONENTS):
        ob = bpy.data.objects.new(name, b.COMPONENTS[name]["mesh"])
        library.objects.link(ob)
        ob.location = ((i % 7) * 10 * S, -260 * S - (i // 7) * 12 * S, 0)
        ob["l1_component"] = name
    data = export()
    scene["L1Reference"] = "concept/puzzle-exit-fixture-reference.png"
    scene["L1OriginalWallpaperAsset"] = "87947439437597"
    scene.unit_settings.system, scene.unit_settings.scale_length = "METRIC", 1
    bpy.context.preferences.filepaths.save_version = 0
    blend = b.OUT / "Level1_ModularKit.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(blend))
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action="DESELECT")
    for ob in library.objects:
        ob.select_set(True)
    bpy.ops.export_scene.fbx(filepath=str(b.OUT / "Level1_ModularKit.fbx"), use_selection=True,
                             object_types={"MESH"}, apply_unit_scale=True, axis_forward="-Z", axis_up="Y",
                             bake_anim=False, path_mode="RELATIVE", mesh_smooth_type="FACE", use_mesh_modifiers=False)
    render_review()
    bpy.ops.wm.save_as_mainfile(filepath=str(blend))
    files = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in (blend, b.OUT / "Level1_ModularKit.fbx")}
    (b.OUT / "native-files.json").write_text(json.dumps(files, indent=2), encoding="utf-8")
    print("V2_DONE=" + json.dumps({"rooms": len(data["rooms"]), "components": len(data["components"]),
                                  "chunks": len(data["chunks"]), "nativeFiles": files}), flush=True)


if __name__ == "__main__":
    main()
