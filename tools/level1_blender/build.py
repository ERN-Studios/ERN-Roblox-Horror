"""Build the ImageGen-directed Level 1 kit in an independent headless Blender.

D:/Blender/blender.exe -b --factory-startup --python-exit-code 1 -P tools/level1_blender/build.py
Only this new kit is written. The open Blender session and Studio are untouched.
"""
from pathlib import Path
import base64, hashlib, json, math, sys
import bpy, bmesh
import numpy as np
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/level1/blender"
TEX = OUT / "textures"
S = 0.28
C = np.array(((1, 0, 0), (0, 0, 1), (0, -1, 0)), float)
MATERIALS = {}
COMPONENTS = {}
ROOMS = {}
assert bpy.app.background, "Use independent headless Blender; never run in the user's open scene"


def linear(x):
    x /= 255
    return x / 12.92 if x <= .04045 else ((x + .055) / 1.055) ** 2.4


def material(name, rgb, rough, stem=None, tile=4, metal=0, emission=0):
    m = bpy.data.materials.new("L1_" + name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*[linear(v) for v in rgb], 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emission:
        b.inputs["Emission Color"].default_value = (*[linear(v) for v in rgb], 1)
        b.inputs["Emission Strength"].default_value = emission
    maps = {}
    for kind, socket in (("albedo", "Base Color"), ("rough", "Roughness"), ("normal", "Normal")):
        path = TEX / (stem + "_" + kind + ".png") if stem else None
        if not path or not path.exists():
            continue
        image = bpy.data.images.load(str(path), check_existing=True)
        image.filepath = "//textures/" + path.name
        if kind != "albedo":
            image.colorspace_settings.name = "Non-Color"
        tex = m.node_tree.nodes.new("ShaderNodeTexImage")
        tex.image = image
        tex.extension = "REPEAT"
        if kind == "normal":
            n = m.node_tree.nodes.new("ShaderNodeNormalMap")
            m.node_tree.links.new(tex.outputs["Color"], n.inputs["Color"])
            m.node_tree.links.new(n.outputs["Normal"], b.inputs[socket])
        else:
            m.node_tree.links.new(tex.outputs["Color"], b.inputs[socket])
        maps[kind] = path.name
    m["l1_tile_studs"] = tile
    MATERIALS[name] = {"blender": m, "color": list(rgb), "roughness": rough,
                       "metalness": metal, "emission": emission, "maps": maps,
                       "tileStuds": tile, "robloxMaterial": "Neon" if emission else "SmoothPlastic"}
    return name


class Mesh:
    def __init__(self, name):
        self.name, self.bm, self.mats, self.colliders = name, bmesh.new(), [], []

    def absorb(self, tmp, mat):
        if mat not in self.mats:
            self.mats.append(mat)
        idx, mapping = self.mats.index(mat), {}
        for v in tmp.verts:
            mapping[v] = self.bm.verts.new(v.co)
        for face in tmp.faces:
            f = self.bm.faces.new([mapping[v] for v in face.verts])
            f.material_index = idx
        tmp.free()

    def box(self, center, size, mat, bevel=.025, rotation=None):
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1)
        bmesh.ops.scale(bm, vec=Vector(size), verts=list(bm.verts))
        if bevel:
            bmesh.ops.bevel(bm, geom=list(bm.edges), offset=min(bevel, min(size) * .3),
                            segments=2, affect="EDGES")
        if rotation is not None:
            bmesh.ops.transform(bm, matrix=rotation, verts=list(bm.verts))
        bmesh.ops.translate(bm, vec=Vector(center), verts=list(bm.verts))
        self.absorb(bm, mat)
        return self

    def cylinder(self, center, radius, height, mat, segments=12, axis="Z", radius2=None):
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments,
                             radius1=radius, radius2=radius if radius2 is None else radius2,
                             depth=height)
        if axis != "Z":
            bmesh.ops.rotate(bm, cent=Vector(), matrix=Matrix.Rotation(math.pi / 2, 3, "Y" if axis == "X" else "X"),
                            verts=list(bm.verts))
        bmesh.ops.translate(bm, vec=Vector(center), verts=list(bm.verts))
        self.absorb(bm, mat)
        return self

    def sphere(self, center, radius, mat):
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=8, radius=radius)
        bmesh.ops.translate(bm, vec=Vector(center), verts=list(bm.verts))
        self.absorb(bm, mat)
        return self

    def collider(self, center, size):
        self.colliders.append({"cf": [center[0], center[2], -center[1], 1, 0, 0, 0, 1, 0, 0, 0, 1],
                               "size": [size[0], size[2], size[1]]})
        return self

    def finish(self):
        bmesh.ops.recalc_face_normals(self.bm, faces=list(self.bm.faces))
        self.bm.normal_update()
        uv = self.bm.loops.layers.uv.new("UVMap")
        for face in self.bm.faces:
            axis = max(range(3), key=lambda i: abs(face.normal[i]))
            tile = MATERIALS[self.mats[face.material_index]]["tileStuds"]
            for loop in face.loops:
                x, y, z = loop.vert.co
                a, b = (y, z) if axis == 0 else ((x, z) if axis == 1 else (x, y))
                loop[uv].uv = (a / tile, b / tile)
        bmesh.ops.scale(self.bm, vec=Vector((S, S, S)), verts=list(self.bm.verts))
        mesh = bpy.data.meshes.new("L1Asset_" + self.name)
        self.bm.to_mesh(mesh)
        self.bm.free()
        for key in self.mats:
            mesh.materials.append(MATERIALS[key]["blender"])
        mesh.update()
        COMPONENTS[self.name] = {"mesh": mesh, "colliders": self.colliders, "chunks": []}
        return self


def build_components():
    material("Carpet", (140, 120, 70), .98, "carpet", 6)
    material("Wallpaper", (195, 181, 103), .86, "wallpaper", 6)
    material("Ceiling", (173, 164, 116), .91, "ceiling", 4)
    material("Trim", (179, 170, 127), .7, tile=4)
    material("Steel", (75, 76, 65), .44, metal=.65)
    material("Wood", (119, 95, 48), .8, tile=3)
    material("Fabric", (114, 102, 61), .98, "carpet", 2)
    material("Dark", (29, 31, 25), .65)
    material("Paper", (183, 163, 111), .93)
    material("Lamp", (255, 238, 178), .45, emission=3)
    material("Red", (118, 37, 24), .45)

    Mesh("Floor").box((0, 0, -.16), (24, 24, .32), "Carpet", 0).collider((0, 0, -.16), (24, 24, .32)).finish()
    roof = Mesh("Ceiling").box((0, 0, 14.18), (24, 24, .36), "Ceiling", 0)
    for t in range(-12, 13, 4):
        roof.box((t, 0, 13.975), (.055, 24, .045), "Steel", 0)
        roof.box((0, t, 13.97), (24, .055, .05), "Steel", 0)
    roof.collider((0, 0, 14.18), (24, 24, .36)).finish()
    wall = Mesh("WallHalf").box((0, 0, 7), (24, 1, 14), "Wallpaper", 0)
    for y in (-.505, .505):
        wall.box((0, y, .37), (24, .12, .74), "Trim", .015)
        wall.box((0, y, 13.8), (24, .1, .4), "Trim", .012)
    wall.collider((0, 0, 7), (24, 1, 14)).finish()
    # Separate skins may be resized over special pit/elevator structures without changing collision.
    Mesh("WallSkin").box((0, 0, 7), (24, .06, 14), "Wallpaper", 0).finish()
    Mesh("FloorSkin").box((0, 0, 0), (24, 24, .035), "Carpet", 0).finish()
    pillar = Mesh("Pillar").box((0, 0, 7), (1.8, 1.8, 14), "Wallpaper", .03)
    pillar.box((0, 0, .4), (2.06, 2.06, .8), "Trim").box((0, 0, 13.8), (2.02, 2.02, .4), "Trim")
    pillar.collider((0, 0, 7), (2.06, 2.06, 14)).finish()
    fixture = Mesh("Fluorescent").box((0, 0, -.10), (4, 7.6, .3), "Steel")
    fixture.box((0, 0, -.26), (3.7, 7.3, .08), "Trim", .015)
    for x in (-1.05, 1.05):
        fixture.cylinder((x, 0, -.39), .14, 6.7, "Lamp", axis="Y")
    for y in (-3.35, 3.35):
        fixture.box((0, y, -.37), (3.5, .12, .14), "Steel", 0)
    fixture.finish()
    dark = Mesh("FluorescentDark").box((0, 0, -.10), (4, 7.6, .3), "Steel")
    for x in (-1.05, 1.05):
        dark.cylinder((x, 0, -.39), .14, 6.7, "Trim", axis="Y")
    dark.finish()

    cab = Mesh("FilingCabinet").box((0, 0, 3.2), (2.7, 2.5, 6.4), "Steel", .08)
    for z in (1.1, 2.55, 4, 5.45):
        cab.box((0, 1.29, z), (2.5, .12, 1.3), "Steel")
        cab.box((0, 1.4, z + .22), (.9, .12, .1), "Trim")
        cab.box((0, 1.37, z - .10), (.74, .045, .25), "Paper", .006)
    cab.collider((0, 0, 3.2), (2.7, 2.5, 6.4)).finish()
    chair = Mesh("Chair").box((0, 0, 1.75), (2.1, 2, .28), "Fabric", .12)
    chair.box((0, -.85, 2.75), (2.05, .28, 1.72), "Fabric", .1)
    chair.cylinder((0, 0, .9), .12, 1.65, "Steel")
    for k in range(5):
        a = k * math.tau / 5
        R = Matrix.Rotation(a, 3, "Z")
        p = R @ Vector((.65, 0, .18))
        chair.box(p, (1.4, .13, .12), "Steel", .025, R)
        chair.cylinder((math.cos(a) * 1.25, math.sin(a) * 1.25, .17), .17, .18, "Dark", axis="X")
    chair.collider((0, 0, 1.1), (2.3, 2.3, 2.2)).finish()
    table = Mesh("Table").box((0, 0, 2.98), (5, 3, .3), "Wood", .045)
    for x in (-2.15, 2.15):
        for y in (-1.12, 1.12):
            table.box((x, y, 1.45), (.2, .2, 2.9), "Steel")
    table.collider((0, 0, 1.56), (5, 3, 3.13)).finish()
    phone = Mesh("Telephone").box((0, 0, .25), (1.24, .95, .42), "Dark", .09)
    phone.cylinder((.16, -.02, .50), .30, .06, "Steel", segments=20)
    for k in range(10):
        a = k * math.tau / 10
        phone.cylinder((.16 + .22 * math.cos(a), -.02 + .22 * math.sin(a), .54), .035, .03, "Dark", segments=6)
    phone.box((0, .28, .65), (1.35, .28, .18), "Dark", .06)
    for x in (-.55, .55):
        phone.box((x, .28, .58), (.24, .36, .24), "Dark", .08)
    for k in range(12):
        phone.sphere((-.75 + .05 * math.cos(k * 2), .15 - k * .034, .3), .04, "Dark")
    phone.finish()

    def carton(mesh, x, y, z, w, h, d, openbox=False):
        if openbox:
            mesh.box((x, y, z + .06), (w, d, .12), "Paper", 0)
            for sx in (-1, 1):
                mesh.box((x + sx * (w / 2 - .05), y, z + h / 2), (.1, d, h), "Paper", 0)
            for sy in (-1, 1):
                mesh.box((x, y + sy * (d / 2 - .05), z + h / 2), (w, .1, h), "Paper", 0)
                R = Matrix.Rotation(sy * .4, 3, "X")
                mesh.box((x, y + sy * (d / 2 + .22), z + h + .25), (w, .7, .055), "Paper", 0, R)
        else:
            mesh.box((x, y, z + h / 2), (w, d, h), "Paper", .035)
            mesh.box((x, y, z + h + .018), (.24, d, .035), "Wood", 0)
            mesh.box((x, y + d / 2 + .018, z + h / 2), (.24, .035, h), "Wood", 0)
            mesh.box((x + .55, y + d / 2 + .02, z + h / 2), (.5, .038, .32), "Trim", 0)
    one = Mesh("Carton")
    carton(one, 0, 0, 0, 2.3, 2.1, 2.1)
    one.collider((0, 0, 1.05), (2.3, 2.1, 2.1)).finish()
    pile = Mesh("CardboardPile")
    carton(pile, -1.15, 0, 0, 2.1, 2.1, 2.2)
    carton(pile, 1.05, .4, 0, 2.1, 1.9, 2.1, True)
    carton(pile, -1, .05, 2.1, 1.8, 1.65, 1.9, True)
    for k in range(3):
        pile.box((1.05, .2 + k * .27, 2.17 + k * .11), (1.4, .035, .72), "Trim", 0)
    pile.collider((0, 0, 1.4), (4.5, 3.6, 2.8)).finish()
    pallet = Mesh("Pallet")
    for y in (-1.4, -.7, 0, .7, 1.4):
        pallet.box((0, y, .4), (4.5, .58, .18), "Wood", .01)
    for x in (-1.7, 0, 1.7):
        pallet.box((x, 0, .2), (.45, 3.5, .32), "Wood", .01)
    pallet.collider((0, 0, .25), (4.5, 3.5, .5)).finish()
    crate = Mesh("Crate").box((0, 0, 1.45), (3.3, 2.8, 2.9), "Wood", .02)
    for z in (.35, 1.4, 2.55):
        crate.box((0, 1.44, z), (3.3, .12, .17), "Wood", .005)
    for x in (-1.45, 1.45):
        crate.box((x, 1.5, 1.45), (.20, .12, 2.9), "Steel", .005)
    crate.collider((0, 0, 1.45), (3.3, 2.8, 2.9)).finish()
    printer = Mesh("Printer").box((0, 0, 1.8), (3.5, 2.7, 3.6), "Trim", .10)
    for z in (.65, 1.5, 2.3):
        printer.box((0, 1.39, z), (3.15, .16, .65), "Steel")
        printer.box((0, 1.5, z + .18), (.9, .14, .11), "Dark")
    printer.box((0, -.1, 3.8), (3.2, 2.35, .35), "Steel", .09)
    printer.box((.8, 1.05, 4.05), (1.15, .65, .16), "Dark", .05)
    printer.box((-.4, 1.2, 4.2), (1.5, 1.4, .025), "Paper", 0)
    printer.collider((0, 0, 2.1), (3.5, 3, 4.2)).finish()
    clock = Mesh("GrandfatherClock").box((0, 0, 4.0), (2.3, 1.55, 8), "Wood", .05)
    clock.box((0, .8, 3.35), (1.35, .05, 4.0), "Dark", .03)
    clock.box((0, 0, .3), (2.65, 1.85, .6), "Wood", .025)
    clock.box((0, 0, 8.05), (2.65, 1.85, .3), "Wood", .025)
    clock.cylinder((0, .88, 6.9), .82, .08, "Trim", segments=24, axis="Y")
    for k in range(12):
        a = k * math.tau / 12
        clock.box((.68 * math.sin(a), .94, 6.9 + .68 * math.cos(a)), (.035, .035, .1), "Steel", 0)
    clock.box((0, .98, 7.12), (.06, .03, .48), "Steel", 0)
    clock.box((.19, .99, 6.9), (.4, .03, .06), "Steel", 0)
    clock.box((0, .86, 3.5), (.05, .035, 2.5), "Steel", 0)
    clock.cylinder((0, .89, 2.2), .36, .08, "Trim", axis="Y")
    clock.collider((0, 0, 4.1), (2.65, 1.85, 8.2)).finish()
    relay = Mesh("RelayCabinet").box((0, 0, 3.45), (3.1, 1.8, 6.9), "Steel", .08)
    relay.box((0, .94, 3.55), (2.82, .12, 6.35), "Steel", .06)
    relay.box((-.99, 1.07, 3.2), (.12, .14, .7), "Trim")
    relay.box((0, 1.035, 5.8), (.9, .045, .32), "Trim", .01)
    for z in (1, 1.17, 1.34, 1.51, 1.68):
        relay.box((0, 1.02, z), (1.9, .035, .04), "Dark", 0)
    relay.collider((0, 0, 3.45), (3.1, 1.8, 6.9)).finish()
    lever = Mesh("Lever").box((0, 0, .5), (.75, .3, 1), "Steel", .04)
    lever.cylinder((0, .24, .6), .1, .35, "Steel", axis="Y")
    lever.box((0, .30, 1.05), (.08, .08, 1), "Steel", .015)
    lever.sphere((0, .30, 1.6), .19, "Red").finish()
    Mesh("LeverBase").box((0, 0, 0), (.75, .3, 1), "Steel", .04).finish()
    handle = Mesh("LeverHandle").box((0, 0, .5), (.09, .09, 1), "Steel", .015)
    handle.sphere((0, 0, 1.12), .19, "Red").finish()
    door = Mesh("RelayDoor").box((0, 0, 0), (2.82, .12, 6.35), "Steel", .06)
    door.box((-.99, .13, -.35), (.12, .14, .7), "Trim")
    door.box((0, .095, 2.25), (.9, .045, .32), "Trim", .01)
    door.finish()
    fuse = Mesh("Fuse").cylinder((0, 0, .55), .18, .65, "Trim", segments=12)
    fuse.cylinder((0, 0, .14), .20, .26, "Steel", segments=12)
    fuse.cylinder((0, 0, .96), .20, .26, "Steel", segments=12).finish()
    radiator = Mesh("Radiator")
    for x in np.linspace(-1.8, 1.8, 12):
        radiator.box((x, 0, 1.65), (.24, .6, 2.7), "Steel", .09)
    radiator.cylinder((0, 0, .48), .13, 4.15, "Steel", axis="X")
    radiator.cylinder((0, 0, 2.8), .13, 4.15, "Steel", axis="X")
    radiator.collider((0, 0, 1.65), (4.2, .6, 3.3)).finish()
    panel = Mesh("BrokenPanel").box((0, 0, 1.8), (2.6, .15, 3.6), "Wallpaper", 0)
    panel.box((0, -.095, .04), (2.6, .1, .12), "Trim", .01)
    panel.finish()
    frame = Mesh("ElevatorFrame")
    for x in (-4.35, 4.35):
        frame.box((x, 0, 5.7), (.75, .6, 11.4), "Steel", .045)
    frame.box((0, 0, 11.35), (9.45, .6, .8), "Steel", .045)
    frame.box((0, .17, .09), (8.7, .9, .18), "Steel", .02)
    frame.finish()
    Mesh("ElevatorDoorSkin").box((0, 0, 5.45), (4.0, .08, 10.7), "Steel", .012).finish()
    vent = Mesh("WallVent").box((0, 0, 0), (2.6, .13, 1.1), "Steel", .035)
    for z in np.linspace(-.42, .42, 8):
        vent.box((0, .1, z), (2.35, .1, .04), "Dark", .005)
    vent.finish()
    conduit = Mesh("Conduit")
    for x in (-.22, .22):
        conduit.cylinder((x, 0, 3.5), .07, 7, "Steel", segments=8)
        for z in (.5, 3.5, 6.5):
            conduit.box((x, 0, z), (.20, .2, .10), "Steel", .01)
    conduit.finish()


def collection(name, parent):
    col = bpy.data.collections.new(name)
    parent.children.link(col)
    return col


def cf_of(M):
    a = np.array(M, float)
    pos = C @ a[:3, 3] / S
    rot = C @ a[:3, :3] @ C.T
    return [round(float(v), 6) for v in np.r_[pos, rot.reshape(-1)]]


def place(col, component, position=(0, 0, 0), yaw=0, offset=(0, 0, 0), role="Detail"):
    ob = bpy.data.objects.new(component, COMPONENTS[component]["mesh"])
    col.objects.link(ob)
    # Input positions are Roblox local studs; Blender front +Y converts to Roblox -Z.
    local = Matrix.Rotation(-math.radians(yaw), 4, "Z")
    local.translation = Vector((position[0] * S, -position[2] * S, position[1] * S))
    ob.matrix_world = local.copy()
    ob.location += Vector((offset[0] * S, -offset[2] * S, offset[1] * S))
    ob["l1_component"], ob["l1_role"] = component, role
    return {"component": component, "cf": cf_of(local), "role": role}


def build_rooms(parent):
    masks = {1: "DeadEndN", 2: "DeadEndE", 3: "CornerNE", 4: "DeadEndS", 5: "StraightNS", 6: "CornerES",
             7: "JunctionNES", 8: "DeadEndW", 9: "CornerNW", 10: "StraightEW", 11: "JunctionNEW",
             12: "CornerSW", 13: "JunctionNSW", 14: "JunctionESW", 15: "Cross"}
    for mask in range(1, 16):
        for variation in range(2):
            name = masks[mask] + ("_Quiet" if variation == 0 else "_ColumnBay")
            index = len(ROOMS)
            offset = ((index % 6) * 30, 0, (index // 6) * 30)
            col = collection(name, parent)
            col["OpenMask"], col["CellSize"], col["WallHeight"] = mask, 24, 14
            placements = [place(col, "Floor", offset=offset, role="SurfaceFloor"),
                          place(col, "Ceiling", offset=offset, role="SurfaceCeiling"),
                          place(col, "Fluorescent", (0, 13.96, 0), offset=offset, role="Fixture")]
            for bit, pos, yaw in ((1, (0, 0, 11.5), 0), (2, (11.5, 0, 0), 90),
                                  (4, (0, 0, -11.5), 0), (8, (-11.5, 0, 0), 90)):
                if not mask & bit:
                    placements.append(place(col, "WallHalf", pos, yaw, offset, "ShellWalls"))
            if variation:
                # Corner islands preserve the entire centre and all cardinal 6-stud lanes.
                for x, z in ((-9.6, -9.6), (9.6, 9.6)):
                    placements.append(place(col, "Pillar", (x, 0, z), offset=offset))
            ROOMS[name] = {"mask": mask, "variant": variation, "placements": placements,
                           "markers": {"ObjectiveAnchor": [0, 0, 0]}, "cellSize": 24, "clearLane": 6}
    # Four recognisable pockets; their open-mask contract remains identical to ordinary rooms.
    special = (("MaintenanceAlcove", 1, [("RelayCabinet", (-8.5, 0, -8.6), 0), ("FilingCabinet", (8.7, 0, -8.5), 0),
                                             ("Radiator", (-8.6, 0, 0), 90), ("Conduit", (-5.9, 0, -10.9), 0)]),
               ("OfficeRemnant", 5, [("FilingCabinet", (-8.8, 0, -8), 90), ("Chair", (-8.5, 0, 8.5), 70),
                                         ("BrokenPanel", (9.1, 0, -8.8), 15)]),
               ("RecordsBay", 3, [("CardboardPile", (-8.2, 0, -8), 10), ("FilingCabinet", (-8.7, 0, 8.3), 90)]),
               ("ElevatorArrival", 1, [("ElevatorFrame", (0, 0, -10.96), 0),
                                           ("ElevatorDoorSkin", (-2.03, 0, -10.8), 0),
                                           ("ElevatorDoorSkin", (2.03, 0, -10.8), 0)]))
    for name, mask, props in special:
        base = next(r for r in ROOMS.values() if r["mask"] == mask and r["variant"] == 0)
        index = len(ROOMS)
        offset = ((index % 6) * 30, 0, (index // 6) * 30)
        col = collection(name, parent)
        col["OpenMask"], col["CellSize"], col["WallHeight"] = mask, 24, 14
        placements = []
        for p in base["placements"]:
            ob = bpy.data.objects.new(p["component"], COMPONENTS[p["component"]]["mesh"])
            col.objects.link(ob)
            cf = p["cf"]
            a = np.array(cf[3:], float).reshape(3, 3)
            M = Matrix((C.T @ a @ C).tolist()).to_4x4()
            M.translation = Vector(C.T @ np.array(cf[:3]) * S)
            ob.matrix_world = M
            ob.location += Vector((offset[0] * S, -offset[2] * S, 0))
            ob["l1_component"], ob["l1_role"] = p["component"], p["role"]
            placements.append(dict(p))
        for comp, pos, yaw in props:
            placements.append(place(col, comp, pos, yaw, offset))
        ROOMS[name] = {"mask": mask, "variant": 2, "placements": placements,
                      "markers": {"ObjectiveAnchor": [0, 0, 0]}, "cellSize": 24, "clearLane": 6}


def export_chunks():
    target = OUT / "export"
    (target / "chunks").mkdir(parents=True, exist_ok=True)
    chunks = []
    for name, info in COMPONENTS.items():
        mesh = info["mesh"]
        mesh.calc_loop_triangles()
        for idx, mat in enumerate(mesh.materials):
            ts = [t for t in mesh.loop_triangles if t.material_index == idx]
            if not ts:
                continue
            # Shared corner normals/UVs retain bevels and the same physical repeat as the .blend.
            p = np.array([[mesh.vertices[v].co[:] for v in t.vertices] for t in ts], float) @ C.T / S
            n = np.array([[mesh.corner_normals[l].vector[:] for l in t.loops] for t in ts], float) @ C.T
            u = np.array([[mesh.uv_layers.active.data[l].uv[:] for l in t.loops] for t in ts], float)
            u[:, :, 1] = 1 - u[:, :, 1]
            lo, hi = p.reshape(-1, 3).min(0), p.reshape(-1, 3).max(0)
            center = (lo + hi) / 2
            pv, pi = np.unique(np.round(p.reshape(-1, 3) - center, 5), axis=0, return_inverse=True)
            nv, ni = np.unique(np.round(n.reshape(-1, 3), 4), axis=0, return_inverse=True)
            uv, ui = np.unique(np.round(u.reshape(-1, 2), 5), axis=0, return_inverse=True)
            assert len(ts) <= 20000 and len(pv) <= 60000, name
            f = np.stack([pi.reshape(-1, 3), ni.reshape(-1, 3), ui.reshape(-1, 3)], axis=2).reshape(-1, 9)
            blob = np.array([len(pv), len(nv), len(uv), len(ts)], dtype="<u4").tobytes()
            blob += pv.astype("<f4").tobytes() + nv.astype("<f4").tobytes() + uv.astype("<f4").tobytes() + f.astype("<u4").tobytes()
            cid = len(chunks)
            wire = base64.b64encode(blob).decode()
            path = target / "chunks" / ("c%05d.b64" % cid)
            path.write_text(wire, encoding="ascii")
            record = {"id": cid, "component": name, "material": mat.name.removeprefix("L1_"), "tris": len(ts),
                      "verts": len(pv), "center": np.round(center, 5).tolist(), "size": np.maximum(hi - lo, .01).round(5).tolist(),
                      "sha256": hashlib.sha256(blob).hexdigest(), "wireSha256": hashlib.sha256(wire.encode()).hexdigest()}
            chunks.append(record)
            info["chunks"].append(cid)
    manifest = {"version": 1, "build": "level1-blender-20261002", "scaleMetresPerStud": S,
                "cellSize": 24, "wallHeight": 14, "wallThickness": 2, "floorTop": 0,
                "axis": "Blender(x,y,z) to Roblox(x,z,-y)", "socketBits": {"N_zPlus": 1, "E_xPlus": 2, "S_zMinus": 4, "W_xMinus": 8},
                "components": {k: {"chunks": v["chunks"], "colliders": v["colliders"], "pivot": [0, 0, 0]} for k, v in COMPONENTS.items()},
                "materials": {k: {x: y for x, y in v.items() if x != "blender"} for k, v in MATERIALS.items()},
                "aliases": {"FloorPanel": "Floor", "CeilingPanel": "Ceiling", "LightFixture": "Fluorescent",
                            "FuseRelay": "RelayCabinet", "FuseBox": "RelayCabinet", "ExitFrame": "ElevatorFrame",
                            "ElevatorMetal": "ElevatorDoorSkin", "ElevatorDoor": "ElevatorDoorSkin", "MetalPanel": "ElevatorDoorSkin"},
                "rooms": ROOMS, "chunks": chunks, "reference": "concepts/room-direction.png"}
    (target / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print("L1_EXPORT=" + json.dumps({"components": len(COMPONENTS), "rooms": len(ROOMS), "chunks": len(chunks),
                                    "triangles": sum(c["tris"] for c in chunks)}), flush=True)


def render_camera(scene, name, position, target, ortho=None):
    data = bpy.data.cameras.new(name)
    ob = bpy.data.objects.new(name, data)
    scene.collection.objects.link(ob)
    ob.location = Vector(position) * S
    ob.rotation_euler = (Vector(target) * S - ob.location).to_track_quat("-Z", "Y").to_euler()
    data.lens = 23
    if ortho:
        data.type, data.ortho_scale = "ORTHO", ortho * S
    scene.camera = ob


def area_light(scene, position, power=160, size=4):
    data = bpy.data.lights.new("WarmTroffer", "AREA")
    data.energy, data.shape, data.size, data.color = power, "DISK", size * S, (1, .91, .64)
    ob = bpy.data.objects.new("WarmTroffer", data)
    scene.collection.objects.link(ob)
    ob.location = Vector(position) * S


def render_previews():
    out = OUT / "renders"
    out.mkdir(exist_ok=True)
    scene = bpy.data.scenes.new("L1_CinematicPreview")
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 32
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y, scene.render.resolution_percentage = 1440, 900, 100
    scene.world = bpy.data.worlds.new("L1 WarmDark")
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (.08, .07, .04, 1)
    scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = .10
    scene.view_settings.view_transform = "AgX"
    col = collection("Cinematic Maze", scene.collection)
    for z in range(4):
        for x in range(3):
            pos = (x * 24, 0, z * 24)
            place(col, "Floor", offset=pos)
            place(col, "Ceiling", offset=pos)
            place(col, "Fluorescent", (0, 13.96, 0), offset=pos)
            area_light(scene, (pos[0], -pos[2], 13.4), 95 if z != 2 else 35, 5)
            if x == 0:
                place(col, "WallHalf", (-11.5, 0, 0), 90, pos)
            if x == 2:
                place(col, "WallHalf", (11.5, 0, 0), 90, pos)
            if z == 3:
                place(col, "WallHalf", (0, 0, 11.5), 0, pos)
            # Long overlapping wall planes and corner pillars follow the contact sheet silhouette.
            if x < 2 and z in (1, 3):
                place(col, "WallHalf", (11.5, 0, 0), 90, pos)
            if x == 1 and z in (0, 2):
                place(col, "Pillar", (-8.7, 0, 8.7), offset=pos)
                place(col, "Pillar", (8.7, 0, -8.7), offset=pos)
    for comp, pos, yaw in (("RelayCabinet", (-8, 0, 29), 90), ("FilingCabinet", (-8, 0, 34), 90),
                            ("Chair", (-6.5, 0, 27), 110), ("CardboardPile", (-8, 0, 39), 90),
                            ("Lever", (-10.8, 5, 25), 90), ("Radiator", (57, 0, 62), 270)):
        place(col, comp, pos, yaw)
    render_camera(scene, "Corridor", (2, -4, 6.6), (22, -58, 6.2))
    scene.render.filepath = str(out / "corridor.png")
    bpy.ops.render.render(write_still=True, scene=scene.name)
    render_camera(scene, "Maintenance", (8, -15, 6), (-8, -31, 4))
    scene.render.filepath = str(out / "maintenance.png")
    bpy.ops.render.render(write_still=True, scene=scene.name)
    # Catalogue overview removes ceilings in the render scene only.
    overview = bpy.data.scenes.new("L1_RoomCataloguePreview")
    overview.render.engine = "CYCLES"
    overview.cycles.samples, overview.cycles.use_denoising = 16, True
    overview.render.resolution_x, overview.render.resolution_y, overview.render.resolution_percentage = 1600, 1200, 100
    overview.world = scene.world
    overview.view_settings.view_transform = "AgX"
    cat = collection("Catalogue Visible", overview.collection)
    rooms_collection = bpy.data.collections["L1 Room Catalogue"]
    for room in rooms_collection.children:
        for ob in room.objects:
            if ob.get("l1_component") in ("Ceiling", "Fluorescent"):
                continue
            duplicate = ob.copy()
            cat.objects.link(duplicate)
    area_light(overview, (80, -60, 120), 20000, 150)
    render_camera(overview, "Catalogue", (210, 190, 220), (75, -75, 0), ortho=255)
    overview.render.filepath = str(out / "catalogue.png")
    bpy.ops.render.render(write_still=True, scene=overview.name)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    # This is the throwaway factory-startup process, not the open authoring session.
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    build_components()
    scene = bpy.context.scene
    catalogue = collection("L1 Room Catalogue", scene.collection)
    build_rooms(catalogue)
    library = collection("L1 Prop Library", scene.collection)
    for i, name in enumerate(COMPONENTS):
        ob = bpy.data.objects.new(name, COMPONENTS[name]["mesh"])
        library.objects.link(ob)
        ob.location = ((i % 7) * 10 * S, -220 * S - (i // 7) * 12 * S, 0)
        ob["l1_component"] = name
    scene.unit_settings.system, scene.unit_settings.scale_length = "METRIC", 1
    scene["L1Reference"] = "concepts/room-direction.png"
    scene["L1GridContract"] = "Cell24 WallHeight14 FullWallThickness2 OpenMask N+Z1 E+X2 S-Z4 W-X8"
    export_chunks()
    blend = OUT / "Level1_ModularKit.blend"
    # Zero save versions: the owner explicitly declined backup files.
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(blend))
    bpy.context.view_layer.update()
    # Export each shared component once; .blend collections + manifest preserve room assembly.
    # Blender 5.2's FBX exporter warns on linked duplicate material slots despite a valid reimport.
    bpy.ops.object.select_all(action="DESELECT")
    for ob in library.objects:
        ob.select_set(True)
    bpy.ops.export_scene.fbx(filepath=str(OUT / "Level1_ModularKit.fbx"), use_selection=True,
                             object_types={"MESH"}, apply_unit_scale=True, axis_forward="-Z", axis_up="Y",
                             bake_anim=False, path_mode="RELATIVE", mesh_smooth_type="FACE", use_mesh_modifiers=False)
    render_previews()
    # Save the two review scenes with the native project, without changing its active catalogue scene.
    bpy.ops.wm.save_as_mainfile(filepath=str(blend))
    files = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in (blend, OUT / "Level1_ModularKit.fbx")}
    (OUT / "native-files.json").write_text(json.dumps(files, indent=2), encoding="utf-8")
    print("L1_DONE=" + json.dumps(files), flush=True)


if __name__ == "__main__":
    main()
