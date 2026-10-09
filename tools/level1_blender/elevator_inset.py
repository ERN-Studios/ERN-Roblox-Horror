"""Author the separate fixed-UV Level 1 elevator in independent headless Blender.

D:/Blender/blender.exe -b --factory-startup -t 4 --python-exit-code 1 -P tools/level1_blender/elevator_inset.py
Does not access Studio, upload assets, or overwrite any existing Blender project.
"""
from pathlib import Path
import hashlib
import importlib.util
import json
import math
import shutil

import bpy
from mathutils import Vector

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("inset_export_contract", HERE / "build.py")
b = importlib.util.module_from_spec(spec)
spec.loader.exec_module(b)
b.OUT = b.ROOT / "assets/level1/elevator-inset-20261004"
b.TEX = b.OUT / "textures"
S = b.S
DEPTHS = (12, 14, 16, 18)
ASSEMBLIES = {}


def box(mesh, p, size, material, bevel=.008):
    """Roblox local studs: front -Z, up +Y, back +Z."""
    mesh.box((p[0], -p[2], p[1]), (size[0], size[2], size[1]), material, bevel)
    return mesh


def disc(mesh, p, radius, thickness, material):
    mesh.cylinder((p[0], -p[2], p[1]), radius, thickness, material, 24, axis="Y")


def materials():
    old = b.ROOT / "assets/level1/blender-v2/textures"
    b.TEX.mkdir(parents=True, exist_ok=True)
    for filename in ("wallpaper_albedo.png", "wallpaper_normal.png", "wallpaper_rough.png"):
        src, dst = old / filename, b.TEX / filename
        if dst.exists():
            assert dst.read_bytes() == src.read_bytes(), "Original wallpaper must remain unchanged"
        else:
            shutil.copyfile(src, dst)
    b.material("Wallpaper", (255, 235, 150), .88, "wallpaper", 6)
    entry = b.MATERIALS["Wallpaper"]
    entry.update(tintTexture=True, originalColorMap=87947439437597)
    mat = entry["blender"]
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    source = bsdf.inputs["Base Color"].links[0].from_socket
    mix = mat.node_tree.nodes.new("ShaderNodeMixRGB")
    mix.blend_type = "MULTIPLY"
    mix.inputs[0].default_value = 1
    mix.inputs[2].default_value = (*[b.linear(x) for x in (255, 235, 150)], 1)
    mat.node_tree.links.new(source, mix.inputs[1])
    mat.node_tree.links.new(mix.outputs[0], bsdf.inputs["Base Color"])
    for filename in ("steel_albedo.png", "steel_normal.png", "steel_rough.png", "steel_metal.png"):
        assert (b.TEX / filename).exists(), "Wait for the Imagegen steel material handoff: " + filename
    b.material("InsetSteel", (255, 255, 255), .38, "steel", 2, metal=.8)
    steel = b.MATERIALS["InsetSteel"]
    steel["robloxMaterial"] = "Metal"
    steel["maps"]["metal"] = "steel_metal.png"
    steel["source"] = "Imagegen-directed cool gray satin brushed stainless steel, 2026-10-04"
    shader = steel["blender"].node_tree.nodes.get("Principled BSDF")
    image = bpy.data.images.load(str(b.TEX / "steel_metal.png"), check_existing=True)
    image.filepath = "//textures/steel_metal.png"
    image.colorspace_settings.name = "Non-Color"
    tex = steel["blender"].node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = image
    steel["blender"].node_tree.links.new(tex.outputs["Color"], shader.inputs["Metallic"])
    b.material("PanelJoint", (34, 39, 45), .52, tile=2, metal=.3)
    b.MATERIALS["PanelJoint"]["robloxMaterial"] = "Metal"
    b.material("ReadoutBlack", (7, 12, 16), .28, tile=2)
    b.material("CallGreen", (115, 235, 155), .4, tile=2, emission=.8)
    b.material("Lamp", (235, 241, 249), .45, tile=2, emission=2)
    b.material("ReviewCarpet", (151, 135, 84), .98, tile=6)


def build_exterior():
    m = b.Mesh("ElevatorExterior")
    # Full facade, exact six-stud original wallpaper UVs; no resized old wall skin.
    for x in (-8.06, 8.06):
        box(m, (x, 5.06, 1), (7.88, 10.12, 2), "Wallpaper", 0)
    box(m, (0, 12.06, 1), (24, 3.88, 2), "Wallpaper", 0)
    # One .4-stud face jamb and a taller 1.8-stud commercial stainless header.
    for x in (-4.2, 4.2):
        box(m, (x, 5, -.06), (.4, 10, .16), "InsetSteel", .009)
    box(m, (0, 10.9, -.06), (8.8, 1.8, .16), "InsetSteel", .009)
    # Full-depth square-edged steel returns hide every wallpaper opening face.
    for x in (-4.06, 4.06):
        box(m, (x, 5, .96), (.12, 10, 2.08), "InsetSteel", 0)
    box(m, (0, 10.06, .96), (8.24, .12, 2.08), "InsetSteel", 0)
    box(m, (0, .10, .8), (8.24, .20, 2.2), "InsetSteel", .004)
    # One decorative call plate to the right of the jamb; no new gameplay prompt.
    box(m, (-5.25, 4.8, -.08), (.8, 4, .18), "InsetSteel", .012)
    box(m, (-5.25, 6.10, -.179), (.59, .62, .02), "ReadoutBlack", .006)
    for y in (6.0, 6.19):
        box(m, (-5.14, y, -.196), (.042, .15, .017), "CallGreen", .002)
    for y in (4.75, 3.8):
        disc(m, (-5.25, y, -.177), .137, .045, "PanelJoint")
        disc(m, (-5.25, y, -.204), .108, .03, "InsetSteel")
    m.finish()
    leaf = b.Mesh("ElevatorDoorLeaf")
    box(leaf, (0, 5, 0), (4, 10, .45), "InsetSteel", .006)
    # Authored hairline edges remain visible under bright normal-mode lights.
    # Both faces have a seam; the two closed leaves still fill the complete aperture.
    for x in (-1.994, 1.994):
        for z in (-.2255, .2255):
            box(leaf, (x, 5, z), (.012, 9.98, .001), "PanelJoint", 0)
    leaf.finish()


def wall_panel(name, width):
    m = b.Mesh(name)
    box(m, (0, 5, .25), (width - .016, 10, .5), "InsetSteel", .005)
    for x in (-width / 2 + .005, width / 2 - .005):
        box(m, (x, 5, -.002), (.01, 10, .009), "PanelJoint", 0)
    m.finish()


def build_cabin_components():
    wall_panel("CabinWallModule4", 4)
    wall_panel("CabinWallModule2", 2)
    back = b.Mesh("CabinBack12")
    for x in (-4, 0, 4):
        box(back, (x, 5, .25), (3.984, 10, .5), "InsetSteel", .005)
    for x in (-2, 2):
        box(back, (x, 5, -.002), (.018, 10, .009), "PanelJoint", 0)
    back.finish()
    front = b.Mesh("CabinFrontReturn12")
    for x in (-5.06, 5.06):
        box(front, (x, 5, -.07), (1.88, 10, .20), "InsetSteel", .003)
    # Inward-facing return trim, entirely outside the eight-stud opening.
    for x in (-4.2, 4.2):
        box(front, (x, 5, .052), (.4, 10, .09), "InsetSteel", .006)
    box(front, (0, 10.1, .045), (12, .2, .09), "InsetSteel", .006)
    front.finish()
    panel = b.Mesh("CabinControlPanel")
    box(panel, (0, 0, 0), (.14, 3.3, .8), "InsetSteel", .009)
    box(panel, (-.078, 1.00, 0), (.02, .58, .59), "ReadoutBlack", .006)
    box(panel, (-.091, 1.00, .09), (.017, .30, .045), "CallGreen", .002)
    for y in (-.10, -.86):
        panel.cylinder((-.078, 0, y), .136, .045, "PanelJoint", 24, axis="X")
        panel.cylinder((-.105, 0, y), .108, .025, "InsetSteel", 24, axis="X")
    panel.finish()
    for depth in DEPTHS:
        floor = b.Mesh("CabinFloorDepth" + str(depth))
        box(floor, (0, .1, depth / 2), (12.4, .2, depth + .2), "InsetSteel", .003)
        floor.finish()
        ceiling = b.Mesh("CabinCeilingDepth" + str(depth))
        # A real opening for the flush white line, not a glowing bar stuck below a solid ceiling.
        x0, x1, z0, z1 = -5.6, 5.6, .37, .59
        for a, c, d, e in ((-6.2, x0, -.1, depth + .1), (x1, 6.2, -.1, depth + .1),
                           (x0, x1, -.1, z0), (x0, x1, z1, depth + .1)):
            box(ceiling, ((a+c)/2, 10.10, (d+e)/2), (c-a, .2, e-d), "InsetSteel", 0)
        ceiling.finish()
    line = b.Mesh("CabinLinearLight12")
    # One cross-width polymer diffuser and narrow metal recess. No PointLights exported.
    box(line, (0, 9.993, .48), (11.2, .018, .22), "Lamp", .003)
    for z in (.358, .602):
        box(line, (0, 10.025, z), (11.26, .07, .025), "InsetSteel", .003)
    for x in (-5.63, 5.63):
        box(line, (x, 10.025, .48), (.026, .07, .22), "InsetSteel", .003)
    line.finish()


def placement(component, position=(0, 0, 0), yaw=0, role="Cabin"):
    # A temporary collection gives the existing tested axis/transform conversion.
    local = b.Matrix.Rotation(-math.radians(yaw), 4, "Z")
    local.translation = Vector((position[0]*S, -position[2]*S, position[1]*S))
    return {"component": component, "cf": b.cf_of(local), "role": role}


def build_assemblies():
    for depth in DEPTHS:
        ps = [placement("CabinBack12", (0, 0, depth)),
              placement("CabinFrontReturn12"),
              placement("CabinFloorDepth"+str(depth), role="Floor"),
              placement("CabinCeilingDepth"+str(depth), role="Ceiling"),
              placement("CabinLinearLight12", role="Lamp"),
              placement("CabinControlPanel", (5.91, 4.65, 3.0), role="ControlPlate")]
        remaining, cursor = depth, 0
        while remaining:
            span = 4 if remaining >= 4 else 2
            for x, yaw in ((-6, 90), (6, -90)):  # steel outside the 12-stud interior, seams facing in
                ps.append(placement("CabinWallModule"+str(span), (x, 0, cursor+span/2), yaw))
            remaining -= span
            cursor += span
        ASSEMBLIES["CabinDepth"+str(depth)] = {
            "placements": ps, "width": 12, "depth": depth, "ceilingY": 10,
            "pivot": [0, 0, 0], "front": "-Z", "fixedSize": True,
            "anchors": {"GuidePoster": [0, 5.1, depth-.08], "Selector": [5.93, 4.6, 1.2],
                        "PointLight": [0, 9.7, .48]},
        }


def place_record(col, record):
    ob = bpy.data.objects.new(record["component"], b.COMPONENTS[record["component"]]["mesh"])
    col.objects.link(ob)
    # Inverse of the tested Roblox-to-Blender coordinate contract.
    cf = record["cf"]
    rb = b.Matrix(((cf[3], cf[4], cf[5], cf[0]), (cf[6], cf[7], cf[8], cf[1]),
                   (cf[9], cf[10], cf[11], cf[2]), (0, 0, 0, 1)))
    C = b.Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
    native = C @ rb @ C.transposed()
    native.translation *= S
    ob.matrix_world = native
    ob["l1_component"], ob["l1_role"] = record["component"], record["role"]
    return ob


def preview_scene(name, open_doors=False, inside=False, depth=12):
    scene = bpy.data.scenes.new(name)
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 24
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = 1440, 1080
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "AgX"
    scene.world = bpy.data.worlds.new(name+"World")
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs[0].default_value = (.48, .50, .53, 1)
    scene.world.node_tree.nodes["Background"].inputs[1].default_value = .80
    col = b.collection(name+" Geometry", scene.collection)
    place_record(col, placement("ElevatorExterior"))
    for p in ASSEMBLIES["CabinDepth"+str(depth)]["placements"]:
        cp = dict(p)
        cp["cf"] = list(p["cf"])
        cp["cf"][2] += 2
        place_record(col, cp)
    for direction in (-1, 1):
        place_record(col, placement("ElevatorDoorLeaf", (direction*(5.6 if open_doors else 2), 0, 1), role="MovingDoor"))
    if inside:
        pos, target = (0, -(depth+.3), 6.2), (0, -2.9, 5.3)
    else:
        pos, target = ((9.5, 23, 8) if open_doors else (0, 22.5, 7.5)), (0, -.2, 6.2)
    cam = b.render_camera(scene, name+"Camera", pos, target)
    scene.camera.data.lens = 24 if inside else 38
    for i, (p, power, size) in enumerate([((0, 8, 12), 230, 11), ((0, -5, 9.4), 160, 9),
                                       ((-7, 2, 9), 85, 7), ((7, -9, 7), 50, 6)]):
        data = bpy.data.lights.new(name+"Fill"+str(i), "AREA")
        data.energy, data.shape, data.size = power, "DISK", size*S
        ob = bpy.data.objects.new(data.name, data)
        scene.collection.objects.link(ob)
        ob.location = Vector(p)*S
        ob.rotation_euler = (Vector((0, -4, 5))*S-ob.location).to_track_quat("-Z","Y").to_euler()
    # Review-only carpet plane; it is not included in the runtime export.
    mesh = bpy.data.meshes.new(name+"ReviewFloor")
    mesh.from_pydata([(-15*S, 10*S, -.018*S), (15*S, 10*S, -.018*S),
                     (15*S, -22*S, -.018*S), (-15*S, -22*S, -.018*S)], [], [(0,1,2,3)])
    mesh.materials.append(b.MATERIALS["ReviewCarpet"]["blender"])
    ob = bpy.data.objects.new(mesh.name, mesh)
    scene.collection.objects.link(ob)
    scene["ReferenceStatus"] = "Owner photographs described and visually reviewed by root; local photographs unavailable"
    scene["GuidePolicy"] = "Runtime CableGuidePoster/selector SurfaceGuis preserved by integration; guide anchor included"
    return scene


def export():
    b.export_chunks()
    path = b.OUT / "export/manifest.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    data.update(version=3, build="level1-elevator-inset-20261004", aliases={}, rooms={},
                assemblies=ASSEMBLIES, wallpaperSourceAsset=87947439437597,
                kitName="Level1ElevatorInsetKit", referenceStatus="Root owns visual comparison to attached owner references",
                contract={"front": "-Z", "exteriorPivot": "front wall floor at x1", "cabinPivot": "cabin front floor at xFront",
                          "worldYawDegrees": -90, "wallWidth": 24, "wallHeight": 14,
                          "openingWidth": 8, "openingHeight": 10, "cabinWidth": 12,
                          "depths": list(DEPTHS), "exteriorJambWidth": .4, "exteriorHeaderHeight": 1.8,
                          "doorSizeAuthored": [4,10,.45], "doorProxyWorldSize": [.45,10,4],
                          "doorSlideStuds": 3.6, "openDoorClearWidth": 7.2,
                          "collisionAuthority": "Original Level1 gameplay Parts; new visual meshes never collide/query/touch",
                          "placementPolicy": "Clone fixed UV components and PivotTo; never resize the complete facade/cabin"})
    data["components"]["ElevatorExterior"]["anchors"] = {"FrontFloor": [0,0,0], "Opening": [0,5,1]}
    data["components"]["ElevatorDoorLeaf"]["movingVisual"] = True
    data["materialFiles"] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in b.TEX.glob("*.png")}
    path.write_text(json.dumps(data, indent=2)+"\n", encoding="utf-8", newline="\n")
    print("INSET_EXPORT="+json.dumps({"components":len(data["components"]), "assemblies":len(ASSEMBLIES),
                                      "chunks":len(data["chunks"]), "triangles":sum(x["tris"] for x in data["chunks"])}), flush=True)


def main():
    assert bpy.app.background, "Independent headless Blender only"
    assert b.OUT.name == "elevator-inset-20261004"
    b.OUT.mkdir(parents=True, exist_ok=True)
    bpy.context.preferences.filepaths.save_version = 0
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    materials()
    build_exterior()
    build_cabin_components()
    build_assemblies()
    library = b.collection("Elevator Components", bpy.context.scene.collection)
    for i, (name, info) in enumerate(b.COMPONENTS.items()):
        ob = bpy.data.objects.new(name, info["mesh"])
        library.objects.link(ob)
        ob.location = (i%5*18*S, -50*S-i//5*22*S, 0)
        ob["l1_component"] = name
    catalogue = b.collection("Elevator Cabin Assemblies", bpy.context.scene.collection)
    for i, (name, data) in enumerate(ASSEMBLIES.items()):
        col = b.collection(name, catalogue)
        for p in data["placements"]:
            ob = place_record(col,p)
            ob.location.x += (i+1)*30*S
        marker = bpy.data.objects.new(name+"GuideAnchor", None)
        col.objects.link(marker)
        marker.location = Vector(((i+1)*30*S, -(data["depth"]-.08)*S, 5.1*S))
        marker["RuntimeSource"] = "Existing CableGuidePoster, unchanged SurfaceGui"
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.context.scene["AssetBuild"] = "Level1ElevatorInsetKit"
    bpy.context.scene["CoordinateContract"] = "Native front+Y maps Roblox-Z; runtime rotatesYaw-90 toworld+X"
    export()
    previews = [preview_scene("ExteriorClosed"), preview_scene("ExteriorOpen", True),
                preview_scene("CabinInterior12", False, True), preview_scene("CabinInterior18", False, True, 18)]
    for image in bpy.data.images:
        if image.source=="FILE" and image.filepath:
            filename = image.filepath.replace("\\", "/").rstrip("/").rsplit("/", 1)[-1]
            if not (b.TEX/filename).is_file():
                continue
            image.filepath = str(b.TEX/filename)
            image.pack()
            image.filepath = "//textures/"+filename
    blend = b.OUT/"Level1_ElevatorInset.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(blend))
    # Export after setting the project's location so relative texture paths resolve correctly.
    bpy.ops.object.select_all(action="DESELECT")
    for ob in library.objects:
        ob.select_set(True)
    bpy.ops.export_scene.fbx(filepath=str(b.OUT/"Level1_ElevatorInset.fbx"), use_selection=True,
                             object_types={"MESH"}, apply_unit_scale=True, axis_forward="-Z", axis_up="Y",
                             bake_anim=False, path_mode="RELATIVE", mesh_smooth_type="FACE", use_mesh_modifiers=False)
    (b.OUT/"renders").mkdir(exist_ok=True)
    for scene in previews:
        scene.render.filepath = str(b.OUT/"renders"/(scene.name+".png"))
        bpy.ops.render.render(write_still=True, scene=scene.name)
    bpy.ops.wm.save_as_mainfile(filepath=str(blend))
    hashes={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in (blend,b.OUT/"Level1_ElevatorInset.fbx")}
    (b.OUT/"native-files.json").write_text(json.dumps(hashes,indent=2)+"\n",encoding="utf-8")
    print("INSET_DONE="+json.dumps(hashes),flush=True)


if __name__ == "__main__":
    main()
