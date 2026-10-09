# Level 4 cinema, Blender rebuild - stage 1: architecture from the Studio layout dump.
# Run inside Blender (MCP execute or `blender -P`). Rebuilds the scene from l4_dump.json:
# every visible part of Workspace."Level 4 Cinema Preview" at its exact CFrame and size, 1 stud = 0.28 m,
# Studio (23000, 0, 0) at the Blender origin. Props that props.py models properly are skipped here.
import bpy, bmesh, json, math, os, re, colorsys
from mathutils import Matrix, Vector

HERE = r"G:\Roblox\MongoTV\tools\level4_blender"
TEX = r"G:\Blender\Level4_Cinema\textures"
# build_all executes this stage before slots.py; keep its PBR texture globals separate from the legacy ones.
_slot_ns = {}
exec(compile(open(os.path.join(HERE, "slots.py"), encoding="utf-8").read(), "slots.py", "exec"), _slot_ns)
slot = _slot_ns["slot"]
S = 0.28                      # metres per stud
OX = 23000.0                  # Studio X of the Blender origin
C = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))   # Roblox (Y-up) -> Blender (Z-up), a proper rotation
D = json.load(open(os.path.join(HERE, "l4_layout.json")))   # dump + layout_edits.py

# Parts that props.py replaces with modelled assets (matched on the path with digits collapsed).
REPLACED = re.compile(
    r"^AutomaticDoors/(?!.*_Post$)"                    # door leaves + hardware -> doors.py (posts stay)
    r"|_Chair(Seat|Back)$"                             # auditorium seats
    r"|^Arcade/Arcade(Left|Right)#_"                   # arcade cabinets
    r"|/(Lobby|WallCafe|Standing)Table(Foot|Rim|Stem|Top)$"
    r"|/WallCafeChair(Back|Leg|Seat)$"
    r"|/ConcourseColumn(AmberCollar|Base)?$"
    r"|^Concession/PopcornCase/"
    r"|^Restrooms/(Men|Women)_(Sink|Toilet)/"
    r"|^Service/StockBox/"
    r"|^Service/(North|South)ServiceExtinguisher$"
    r"|^Service/JanitorCart/"
    r"|/ArcadeStool(Seat|Stem)$"
    r"|/Lobby(Bench|Sofa)(Back|Seat|Arm)$"
)


def key(path):
    return re.sub(r"\d+", "#", path)


def cf_matrix(cf):
    x, y, z, a, b, c, d, e, f, g, h, i = cf
    R = Matrix(((a, b, c), (d, e, f), (g, h, i)))
    M = (C @ R @ C.transposed()).to_4x4()
    M.translation = C @ Vector(((x - OX) * S, y * S, z * S))
    return M


def dims(size):
    sx, sy, sz = size
    return Vector((sx * S, sz * S, sy * S))   # Roblox local X,Y,Z -> Blender local X,Z,(-)Y


# ---------------------------------------------------------------- unit meshes (Blender local frame)
def unit_mesh(name, build):
    me = bpy.data.meshes.get(name)
    if me:
        return me
    bm = bmesh.new()
    build(bm)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = False
    me.materials.append(None)          # one slot, linked per object
    return me


def b_box(bm):
    bmesh.ops.create_cube(bm, size=1.0)


def b_cyl(bm):      # Roblox cylinders run along local X
    bmesh.ops.create_cone(bm, cap_ends=True, segments=24, radius1=0.5, radius2=0.5, depth=1.0,
                          matrix=Matrix.Rotation(math.radians(90), 4, 'Y'))


def b_ball(bm):
    bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=12, radius=0.5)


def b_wedge(bm):    # Roblox wedge: full bottom, full back (+Z roblox = -Y blender), slope to the front
    v = [bm.verts.new(p) for p in ((-.5, .5, -.5), (.5, .5, -.5), (.5, -.5, -.5), (-.5, -.5, -.5),
                                   (-.5, -.5, .5), (.5, -.5, .5))]
    for f in ((0, 3, 2, 1), (3, 4, 5, 2), (0, 1, 5, 4), (0, 4, 3), (1, 2, 5)):
        bm.faces.new([v[i] for i in f])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)


UNIT = {"Block": ("L4U_Box", b_box), "Cylinder": ("L4U_Cyl", b_cyl), "Ball": ("L4U_Ball", b_ball),
        "Wedge": ("L4U_Wedge", b_wedge)}


# ---------------------------------------------------------------- materials
def srgb2lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


# semantic -> (texture file or None, tile metres, roughness, metallic)
SEM = {
    "carpet": ("tex_carpet_red_circles_n.png", 2.2, 0.95, 0.0),
    "carpet_arcade": ("tex_carpet_arcade_n.png", 2.2, 0.95, 0.0),
    "plaster": ("tex_wall_orange_plaster_n.png", 3.2, 0.85, 0.0),
    "velvet": ("tex_velvet_red_n.png", 0.7, 0.9, 0.0),
    "marble": ("tex_marble_black_gold.png", 2.0, 0.25, 0.0),
    "tile": ("tex_tile_restroom_n.png", 1.6, 0.35, 0.0),
    "ceiling": ("tex_ceiling_tile_n.png", 2.4, 0.9, 0.0),
    "wood": ("tex_wood_door_n.png", 1.4, 0.6, 0.0),
    "metal": ("tex_steel_scuffed_n.png", 1.6, 0.38, 0.85),
    "granite": ("tex_granite_counter.png", 1.6, 0.3, 0.0),
    "concrete": ("tex_concrete_stained_n.png", 3.0, 0.9, 0.0),
    "wall_dark": ("tex_wall_dark_red_n.png", 3.2, 0.85, 0.0),
    "acoustic": ("tex_acoustic_fabric_n.png", 1.4, 0.95, 0.0),
    "plastic": (None, 1, 0.55, 0.0),
    "neon": (None, 1, 0.5, 0.0),
    "glass": (None, 1, 0.05, 0.0),
    "screen": (None, 1, 0.9, 0.0),
}
FLOORY = re.compile(r"Carpet|Tread|Tier|Aisle|Landing|Floor|Runner|Apron|TopWalk|Connector|GroundJoint")
CEILY = re.compile(r"Roof|Ceiling")


def semantic(p):
    name, m = p["p"].rsplit("/", 1)[-1], p["m"]
    if m == "Neon":
        return "neon"
    if m == "Glass":
        return "glass"
    if m in ("Metal", "Foil", "DiamondPlate", "CorrodedMetal"):
        return "metal"
    if m in ("Granite", "Marble") or re.search(r"WornStone|StonePier", name):
        return "marble"
    if m == "CeramicTiles":
        return "tile"
    if m in ("Wood", "WoodPlanks"):
        return "wood"
    if name == "CounterTop":
        return "granite"
    if m == "Concrete" or name == "ServiceConcrete":
        return "concrete"
    if m == "Fabric":
        if "Acoustic" in name:
            return "acoustic"
        if name == "Arcade_Carpet":
            return "carpet_arcade"
        if FLOORY.search(name):
            return "carpet"
        return "velvet"
    if name in ("A1_Screen", "A2_Screen", "A3_Screen") or name.endswith("_Screen"):
        return "screen"
    if CEILY.search(name):
        return "ceiling"
    if max(p["s"]) >= 6 and not re.search(r"Poster|Sign|Menu|Notice|Marquee|Board|Wrapper|Pack", name):
        r, g, b = p["col"]
        return "wall_dark" if 0.299 * r + 0.587 * g + 0.114 * b < 55 else "plaster"
    return "plastic"


def quant(col):
    return tuple(min(255, int(round(c / 8.0)) * 8) for c in col)


def image(fname):
    img = bpy.data.images.get(fname)
    if img:
        return img
    path = os.path.join(TEX, fname)
    if not os.path.exists(path):
        return None
    return bpy.data.images.load(path)


def material(sem, col, alpha=1.0):
    col = quant(col)
    name = "L4_%s_%02x%02x%02x" % ((sem,) + col) + ("" if alpha >= 0.99 else "_t%02d" % int(alpha * 100))
    mat = bpy.data.materials.get(name)
    if mat:
        return mat
    tex, tile, rough, metal = SEM[sem]
    lin = [srgb2lin(c / 255.0) for c in col]
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    mat["l4_sem"] = sem
    mat["l4_color"] = list(col)
    mat["l4_tile"] = tile
    mat["l4_tex"] = tex or ""
    mat["l4_alpha"] = alpha
    img = image(tex) if tex else None
    if img:
        geo = nt.nodes.new("ShaderNodeNewGeometry")
        sc = nt.nodes.new("ShaderNodeVectorMath"); sc.operation = "SCALE"
        sc.inputs["Scale"].default_value = 1.0 / tile
        it = nt.nodes.new("ShaderNodeTexImage"); it.image = img
        it.projection = "BOX"; it.projection_blend = 0.15
        nt.links.new(geo.outputs["Position"], sc.inputs[0])
        nt.links.new(sc.outputs["Vector"], it.inputs["Vector"])
        if tex.endswith("_n.png"):      # neutral detail map, tinted by the Studio colour
            mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = "RGBA"; mix.blend_type = "MULTIPLY"
            mix.inputs["Factor"].default_value = 1.0
            mix.inputs["A"].default_value = (*[min(1.0, c / 0.75) for c in lin], 1)
            nt.links.new(it.outputs["Color"], mix.inputs["B"])
            nt.links.new(mix.outputs["Result"], bsdf.inputs["Base Color"])
        else:
            nt.links.new(it.outputs["Color"], bsdf.inputs["Base Color"])
    else:
        bsdf.inputs["Base Color"].default_value = (*lin, 1)
    if sem == "neon":
        bsdf.inputs["Emission Color"].default_value = (*lin, 1)
        bsdf.inputs["Emission Strength"].default_value = 6.0
    if sem == "screen":
        bsdf.inputs["Emission Color"].default_value = (*lin, 1)
        bsdf.inputs["Emission Strength"].default_value = 0.4
    if alpha < 0.99 or sem == "glass":
        a = min(alpha, 0.35) if sem == "glass" else alpha
        bsdf.inputs["Alpha"].default_value = a
        mat["l4_alpha"] = a
        try:
            mat.surface_render_method = "BLENDED"
        except Exception:
            pass
    mat.diffuse_color = (*lin, 1)
    return mat


# ---------------------------------------------------------------- scene
def coll(name, parent=None):
    c = bpy.data.collections.get(name)
    if not c:
        c = bpy.data.collections.new(name)
        (parent or bpy.context.scene.collection).children.link(c)
    return c


def reset():
    for c in list(bpy.data.collections):
        if c.name.startswith("L4"):
            for o in list(c.all_objects):
                bpy.data.objects.remove(o, do_unlink=True)
            bpy.data.collections.remove(c)
    for o in list(bpy.context.scene.collection.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for me in list(bpy.data.meshes):
        if me.users == 0:
            bpy.data.meshes.remove(me)
    for m in list(bpy.data.materials):
        if m.name.startswith("L4_") and m.users == 0:
            bpy.data.materials.remove(m)


def build():
    reset()
    root = coll("L4 Cinema")
    arch = coll("L4 Architecture", root)
    made = skipped = 0
    for idx, p in enumerate(D["parts"]):
        k = key(p["p"])
        if REPLACED.search(k):
            skipped += 1
            continue
        if p["t"] >= 0.95:
            continue
        shape = p.get("sh") or "Block"
        if shape not in UNIT:
            shape = "Block"
        mname, fn = UNIT[shape]
        top = p["p"].split("/")[0]
        c = coll("L4 " + top, arch)
        o = bpy.data.objects.new(p["p"].rsplit("/", 1)[-1], unit_mesh(mname, fn))
        o.matrix_world = cf_matrix(p["cf"])
        o.scale = dims(p["s"])
        sem = semantic(p)
        # Owner v3: unify plain wall finishes, preserving horizontal slabs/floors that the old semantic
        # heuristic also calls plaster. Acoustic / velvet panels, ceramic tiles, metal and glass stay intact.
        is_wall = sem in ("plaster", "wall_dark") and not FLOORY.search(p["p"].rsplit("/", 1)[-1]) and p["s"][1] > min(p["s"][0], p["s"][2])
        if p["p"] == "Concession/BackWainscot":
            mat = slot("WAINSCOT_LACQUER")
        elif is_wall:
            mat = slot("WALLPAPER_MAIN")
        elif top == "HiddenService" and sem == "carpet":
            # The gallery, stair treads, landings and ground runner form one continuous staff route.
            mat = slot("CARPET_LOBBY")
        else:
            mat = material(sem, p["col"], 1.0 - p["t"])
        o["l4_src"] = idx                  # index into l4_dump.json parts
        o["l4_path"] = p["p"]
        if p["p"].startswith("Shell/C1BlockWall"):
            o["l4_occluder"] = True         # v3 new solid closure also blocks the player camera
        if "dec" in p:
            o["l4_decals"] = 1             # posters/signs: Studio re-applies the original Decals/SurfaceGuis
        c.objects.link(o)
        o.material_slots[0].link = "OBJECT"
        o.material_slots[0].material = mat
        made += 1
    return made, skipped


made, skipped = build()
print("architecture objects", made, "skipped for props", skipped, "materials",
      len([m for m in bpy.data.materials if m.name.startswith("L4_")]))
