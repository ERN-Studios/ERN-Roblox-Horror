# Level 4 cinema, Blender rebuild - stage 3: every door is its own model.
# One collection per door under "L4 Doors": the hinge post plus an Empty "DoorHinge_<Name>" sitting on the
# hinge axis, with the modelled leaf parented to it. The leaf's origin IS the hinge, so rotating the Empty
# (or the leaf) about Z swings the door; nothing else has to move.
import bpy, bmesh, json, math, os, re
from mathutils import Matrix, Vector

exec(open(r"G:\Roblox\MongoTV\tools\level4_blender\props.py").read().split("# ---------------------------------------------------------------- assets")[0])

STYLE = [  # first match wins
    (r"_FrontExit$|^Arcade(Left|Right)$", "leather"),
    (r"_Restroom$", "restroom"),
    (r"^MainEntry", "glass"),
    (r"^SecretPoster$", "poster"),
    (r".", "steel"),
]


def leaf_asset(style, W, H, T, col):
    m = M()
    key = "DoorLeaf_%s_%d_%d" % (style, round(W * 100), round(H * 100))
    if bpy.data.meshes.get("L4A_" + key):
        return bpy.data.meshes["L4A_" + key]
    a = Asset(key)
    x0 = 0.02                       # hinge gap
    w = W - x0
    cx = x0 + w / 2
    if style == "leather":
        leather = pmat("door_leather", (140, 18, 26), 0.6, tex="tex_door_red_leather.png", tile=0.9)
        a.box((cx, 0, H / 2), (w, T, H), m["metal_black"], bevel=0.01)
        for s in (-1, 1):
            a.box((cx, s * (T / 2 + 0.012), H * 0.52), (w * 0.86, 0.025, H * 0.86), leather, bevel=0.03)
            a.cyl((cx + w * 0.18, s * (T / 2 + 0.03), H * 0.68), 0.2, 0.02, m["brass"], axis="Y", seg=24)
            a.cyl((cx + w * 0.18, s * (T / 2 + 0.035), H * 0.68), 0.16, 0.02, m["glass"], axis="Y", seg=24)
            a.box((cx + w * 0.36, s * (T / 2 + 0.04), H * 0.45), (0.1, 0.02, 0.5), m["brass"], bevel=0.005)
            a.box((cx, s * (T / 2 + 0.03), 0.12), (w * 0.94, 0.012, 0.22), m["brass"])
    elif style == "restroom":
        lam = pmat("door_laminate_%02x%02x%02x" % tuple(col), col, 0.45, tex="tex_wood_door_n.png", tile=1.2)
        a.box((cx, 0, H / 2), (w, T, H), lam, bevel=0.01)
        for s in (-1, 1):
            a.box((cx, s * (T / 2 + 0.004), 0.16), (w * 0.94, 0.01, 0.3), m["steel"])
            a.box((cx + w * 0.36, s * (T / 2 + 0.006), H * 0.5), (0.12, 0.012, 0.36), m["steel"])
            a.box((cx, s * (T / 2 + 0.006), H * 0.72), (0.3, 0.012, 0.3), m["plastic_black"], bevel=0.01)
    elif style == "glass":
        a.box((cx, 0, H / 2), (w * 0.9, T * 0.4, H * 0.86), m["glass"])
        for z in (0.07, H - 0.07):
            a.box((cx, 0, z), (w, T, 0.14), m["metal_black"], bevel=0.01)
        for x in (x0 + 0.05, W - 0.05):
            a.box((x, 0, H / 2), (0.1, T, H), m["metal_black"], bevel=0.01)
        for s in (-1, 1):
            a.cyl((cx + w * 0.34, s * 0.07, H * 0.48), 0.02, H * 0.3, m["chrome"], seg=10)
    elif style == "poster":
        wall = pmat("door_poster_back", col, 0.8)
        a.box((cx, 0, H / 2), (w, T, H), wall)
    else:  # steel service door
        steel = pmat("door_steel_%02x%02x%02x" % tuple(col), col, 0.45, 0.6, tex="tex_steel_scuffed_n.png", tile=1.0)
        a.box((cx, 0, H / 2), (w, T, H), steel, bevel=0.008)
        for s in (-1, 1):
            a.box((cx + w * 0.2, s * (T / 2 + 0.004), H * 0.66), (w * 0.2, 0.01, H * 0.2), m["glass"])
            a.box((cx + w * 0.2, s * (T / 2 + 0.006), H * 0.66), (w * 0.24, 0.008, H * 0.24), m["metal_black"])
            a.box((cx, s * (T / 2 + 0.03), H * 0.45), (w * 0.8, 0.04, 0.06), m["steel"], bevel=0.01)
            a.box((cx, s * (T / 2 + 0.004), 0.14), (w * 0.94, 0.008, 0.26), m["steel"])
    return a.finish()


def build_doors():
    root = bpy.data.collections.get("L4 Doors")
    if root:
        for c in list(root.children):
            for o in list(c.objects):
                if o.get("l4_door_leaf") or o.type == "EMPTY":
                    bpy.data.objects.remove(o, do_unlink=True)
                else:
                    c.objects.unlink(o)
            bpy.data.collections.remove(c)
    else:
        root = bpy.data.collections.new("L4 Doors")
        bpy.data.collections["L4 Cinema"].children.link(root)
    hinges = {o["p"].split("/")[1].rsplit("_Post", 1)[0]: o.get("at", {}) for o in OTHER
              if o["c"] == "HingeConstraint" and o["p"].startswith("AutomaticDoors/")}
    arch = {o.get("l4_path"): o for o in bpy.data.objects if o.get("l4_path")}
    made = []
    for li, leaf in parts(r"^AutomaticDoors/[^/]+_Leaf$"):
        name = leaf["p"].split("/")[1][:-len("_Leaf")]
        post = next(p for _, p in parts("^AutomaticDoors/" + re.escape(name) + "_Post$"))
        style = next(s for rx, s in STYLE if re.search(rx, name))
        W = leaf["s"][0] * S
        H = leaf["s"][1] * S
        T = leaf["s"][2] * S
        me = leaf_asset(style, W, H, T, leaf["col"])
        d = pos(leaf) - pos(post)
        d.z = 0
        d.normalize()
        # hinge axis sits on the leaf's edge nearest the post
        hinge = pos(leaf) - d * (W / 2)
        hinge.z = (leaf["cf"][1] - leaf["s"][1] / 2) * S
        R = Matrix.Rotation(math.atan2(d.y, d.x), 4, "Z")
        dc = bpy.data.collections.new("Door " + name)
        root.children.link(dc)
        emp = bpy.data.objects.new("DoorHinge_" + name, None)
        emp.empty_display_type = "SINGLE_ARROW"
        emp.empty_display_size = 0.6
        emp.matrix_world = Matrix.Translation(hinge) @ R
        dc.objects.link(emp)
        lo = bpy.data.objects.new("DoorLeaf_" + name, me)
        lo.parent = emp
        lo.matrix_parent_inverse = Matrix.Identity(4)
        lo.matrix_basis = Matrix.Identity(4)
        dc.objects.link(lo)
        at = hinges.get(name, {})
        for o in (emp, lo):
            o["l4_door"] = name
            o["l4_door_style"] = style
            o["l4_open_angle"] = float(at.get("OpenAngle", 95))
            if at.get("FixedOpenAngle"):
                o["l4_fixed_open_angle"] = float(at["FixedOpenAngle"])
            if at.get("NonBlockingWhenOpen"):
                o["l4_nonblocking_open"] = True
        lo["l4_door_leaf"] = True
        lo["l4_src"] = li
        lo["l4_model"] = "Door_" + name
        if name == "SecretPoster":
            lo["l4_decals"] = 1
            lo["l4_attrs"] = json.dumps({"ConcealedEntrance": True})
        po = arch.get("AutomaticDoors/%s_Post" % name)
        if po:
            for c in po.users_collection:
                c.objects.unlink(po)
            dc.objects.link(po)
        made.append((name, style))
    return made


made = build_doors()
print("doors", len(made), made)
