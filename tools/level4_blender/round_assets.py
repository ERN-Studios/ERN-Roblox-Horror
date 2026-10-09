"""Authored Level 4 round anchors and moving prop parts, added after the v4 dressing.

Run only through v3/blrun.py on a copy. build_round_assets() never saves the place.
The exporter consumes explicit model groups; all marker dimensions use original layout studs.
"""
import bpy, bmesh, json, os, math, collections
from mathutils import Matrix, Vector

HERE = r"G:\Roblox\MongoTV\tools\level4_blender"
PKG, COLL = "L4RoundAssets", "L4 Round Assets"
S, OX = 0.28, 23000.0
REQUIRED = {"L4EntrySpawn": 6, "L4PowerCabinet": 2, "L4Breaker": 6, "L4NoteSpot": 6,
            "L4MainBreaker": 1, "L4FuseSocket": 1, "L4ReelSpot": 10, "L4Projector": 3,
            "L4Screen": 3, "L4ExitScreen": 1, "L4ExitSafeSpawn": 6, "L4HideZone": 41,
            "L4ArcadeCode": 1, "L4PrizeKeypad": 1, "L4PrizeCase": 1}
IDENTITY = [1, 0, 0, 0, 1, 0, 0, 0, 1]
V6_EDITS = {"low_power_panels": True}  # approval item 1; False rebuilds the original cabinets


def _rooms():
    ns = {"__name__": "l4_round_helpers", "__file__": os.path.join(HERE, "props_rooms.py")}
    exec(compile(open(ns["__file__"], encoding="utf-8").read(), ns["__file__"], "exec"), ns)
    # Markers follow the built surface, including an approval build with item 3 switched off.
    counter = bpy.data.objects.get("Concession_Counter")
    if counter is not None:
        ns["V6_EDITS"]["low_counters"] = bool(counter.get("l4_v6_low_counter"))
    return ns


def _rb(p):
    return Vector(((p[0] - OX) * S, -p[2] * S, p[1] * S))


def _stud(p):
    return (p.x / S + OX, p.z / S, -p.y / S)


def _collection():
    c = bpy.data.collections.get(COLL)
    if c is None:
        c = bpy.data.collections.new(COLL)
        bpy.data.collections["L4 Cinema"].children.link(c)
    return c


def _object(me, name):
    o = bpy.data.objects.new(name, me)
    _collection().objects.link(o)
    o["l4_pkg"] = PKG
    return o


def _finish(mb, name, group=None, tag=None, attrs=None, part=None, parent=None):
    me = mb.finish(False)
    lo = Vector(tuple(min(v.co[i] for v in me.vertices) for i in range(3)))
    hi = Vector(tuple(max(v.co[i] for v in me.vertices) for i in range(3)))
    centre = (lo + hi) / 2
    me.transform(Matrix.Translation(-centre))
    if me.get("l4_col"):
        cols = json.loads(me["l4_col"])
        for col in cols:
            col[:3] = list(Vector(col[:3]) - centre)
        me["l4_col"] = json.dumps(cols)
    o = _object(me, name)
    o.matrix_world = Matrix.Translation(centre)
    if group:
        o["l4_prop"] = me.name
        o["l4_model"], o["l4_model_group"] = group, group
        if parent:
            o["l4_model_parent"] = parent
        if tag:
            o["l4_model_tags"] = tag
        o["l4_model_attributes"] = json.dumps(attrs or {})
    if part:
        o["l4_part_name"] = part
    return o


def _pivot(o, point, rotation=None):
    p = o.matrix_world.inverted() @ _rb(point)
    o["l4_pivot"] = json.dumps([round(p.x / S, 6), round(p.z / S, 6), round(-p.y / S, 6)] + (rotation or IDENTITY))
    o["l4_hinge_world"] = json.dumps(point)


def _marker(tag, name, centre, size, attrs=None):
    me = bpy.data.meshes.new("L4Marker_" + name)
    bm = bmesh.new()
    vs = bmesh.ops.create_cube(bm, size=1)["verts"]
    bmesh.ops.scale(bm, verts=vs, vec=Vector((size[0] * S, size[2] * S, size[1] * S)))
    bm.to_mesh(me); bm.free()
    o = _object(me, name)
    o.matrix_world = Matrix.Translation(_rb(centre))
    o.hide_render, o.display_type = True, "WIRE"
    o["l4_marker"], o["l4_tags"] = True, tag
    o["l4_attributes"] = json.dumps(attrs or {})
    o["l4_col"] = "[]"
    return o


def _text(mb, r, text, pos, size, mat, face=1):
    co, faces = r["_text_geo"](text, size, 0)
    # Text local -Y faces into the service room: north wall +Z, south wall -Z.
    R = r["_yaw"]((0, -face)).to_4x4()
    mb.add_geo(co, faces, mat, Matrix.Translation(r["_B"](*pos)) @ R)


def _control_red(r):
    mat = bpy.data.materials.get("L4R_ControlRed") or bpy.data.materials.new("L4R_ControlRed")
    mat.use_nodes = True
    node = mat.node_tree.nodes.get("Principled BSDF")
    rgb = (218,32,24)
    node.inputs["Base Color"].default_value = (*[r["_lin"](v) for v in rgb],1)
    node.inputs["Roughness"].default_value = .68
    node.inputs["Metallic"].default_value = 0
    mat.diffuse_color = (*[r["_lin"](v) for v in rgb],1)
    for k,v in {"l4_sem":"plastic","l4_roblox":"SmoothPlastic","l4_color":list(rgb),
                "l4_tile":1.,"l4_alpha":1.,"l4_uv":"box","l4_emit":0.}.items():
        mat[k] = v
    return mat


def _panels(r, m):
    low = V6_EDITS["low_power_panels"]
    label_mat = r["_t"]("PORCELAIN", (238, 230, 210)) if low else m["board"]
    old = bpy.data.objects.get("ServicePanels")
    if old:
        bpy.data.objects.remove(old, do_unlink=True)
    for cab, x0, x1, wz, face, conduits in (
            ("A", 22785., 22796., r["SERV"][2], 1, (22788.2, 22793.2)),
            ("B", 22736., 22747., r["SERV"][3], -1, (22739.2, 22744.2))):
        group = "PowerCabinet_" + cab
        front = wz + face * (.8 if low else 1.3)
        bottom, top = (26., 30.25) if low else (31., 41.)
        mb = r["RMesh"](group + "Body")
        # Hollow shell keeps the three switches visible behind an open door.
        def box(xa, xb, ya, yb, za, zb, mat):
            mb.rbox((xa, ya, min(za, zb)), (xb, yb, max(za, zb)), mat, .025)
        box(x0, x1, bottom, top, wz, wz + face * .20, m["panel_grey"])
        box(x0, x0 + .3, bottom, top, wz, front, m["panel_grey"])
        box(x1 - .3, x1, bottom, top, wz, front, m["panel_grey"])
        box(x0, x1, bottom, bottom + .3, wz, front, m["panel_grey"])
        box(x0, x1, top - .35, top, wz, front, m["panel_grey"])
        box(x0 + .3, x1 - .3, bottom + .3, top - .35, wz + face * .25, wz + face * .35, m["steel_grey"])
        # Body label stays legible when the door is open.
        label_y = 29.45 if low else 40.1
        box(x0 + .7, x1 - .7, label_y - .5, label_y + .5, front + face * .01, front + face * .04, m["black"])
        _text(mb, r, "POWER " + cab, ((x0 + x1)/2, label_y, front + face * (.10 if low else .05)),
              .8 if low else .62, label_mat, face)
        for cx in conduits[:1] if low else conduits:
            cz = wz + face * .5
            pts = ([r["_B"](cx, top, cz), r["_B"](cx, r["SERV_CEIL"], cz)] if low else
                   [r["_B"](cx, 41, cz), r["_B"](cx, 43.2, cz),
                    r["_B"](cx + .9, 44.2, cz), r["_B"](cx + .9, r["SERV_CEIL"], cz)])
            mb.tube(pts, .18, m["emt"], seg=8)
        # The cabinet uses thin shell colliders, not a solid box covering the controls.
        for xa, xb in ((x0, x0 + .3), (x1 - .3, x1)):
            mb.rcol((xa, bottom, min(wz, front)), (xb, top, max(wz, front)))
        # The legacy controller spreads a vertical stack's prompts when it finds a Body.
        # Horizontal controls keep makePrompt's attachment on each separate Handle instead.
        body = _finish(mb, group + "_Body", group, "L4PowerCabinet", {"CabinetId": cab}, "Panel" if low else "Body")
        body["l4_label"] = "POWER " + cab

        if not low:
            door = r["RMesh"](group + "OpenDoor")
            dz = front + face * .08
            hinge = r["_B"](x0 + .3, 36, dz)
            # A wider opening than v4's ajar door, without moving the body/conduit mounts.
            with door.at(Matrix.Translation(hinge) @ Matrix.Rotation(-math.radians(110) * face, 4, "Z") @ Matrix.Translation(-hinge)):
                door.rbox((x0 + .3, 31.4, dz - .07), (x1 - .3, 39.4, dz + .07), m["panel_grey"], .04)
                _text(door, r, "DANGER", ((x0 + x1)/2, 37.3, dz + face * .09), .65, m["red_dk"], face)
                _text(door, r, "HIGH VOLTAGE", ((x0 + x1)/2, 36.3, dz + face * .09), .35, m["black"], face)
            _finish(door, group + "_OpenDoor", group, part="OpenDoor")

        for index, cy in enumerate((27.8,) * 3 if low else (33.0, 35.6, 38.2), 1):
            sw = "Breaker_%s%d" % (cab, index)
            frame = r["RMesh"](sw + "Mount")
            cx = x0 + 1.7 + ((index - 1) if face > 0 else (3 - index)) * 3.8 if low else x0 + 4.5
            z = front + face * .02
            half_width = 1.35 if low else 1.65
            frame.rbox((cx - half_width, cy - .7 if low else cy - .9, z - .13),
                       (cx + half_width, cy + .8 if low else cy + .9, z + .13), m["black"], .04)
            _text(frame, r, "%s%d" % (cab, index),
                  (cx, 26.68, z + face * .19) if low else (x1 - 1.35, cy, z + face * .16),
                  .85 if low else .68, label_mat, face)
            _finish(frame, sw + "_Mount", sw, "L4Breaker", {"CabinetId": cab, "SwitchIndex": index}, "Mount", group)
            lever = r["RMesh"](sw + "Handle")
            hz = z + face * .65
            # One material produces EXACTLY one independently movable Handle MeshPart.
            lever.rbox((cx - 1.08, cy - .7, hz - .14), (cx + 1.08, cy + .55, hz + .14), m["control_red"], .06)
            handle = _finish(lever, sw + "_Handle", sw, part="Handle", parent=group)
            # The south wall reverses local X so the shared -65deg ON rotation swings into the room.
            _pivot(handle, (cx, cy + .55, hz), [-1,0,0,0,1,0,0,0,-1] if face < 0 else None)
            handle["l4_on_angle"] = -65
            handle["l4_col"] = "[]"

    main = "MainBreaker"
    x, wz, face = 22822., r["SERV"][2], 1
    z = wz + 1.1
    mb = r["RMesh"](main + "Box")
    mb.rbox((x - 3.5, 26.0, wz), (x + 3.5, 33.6, z), m["panel_grey"], .08)
    mb.rbox((x - 3.2, 32.1, z + .01), (x + 3.2, 33.4, z + .04), m["black"])
    _text(mb, r, "MAIN BREAKER", (x, 32.75, z + .05), .5, m["board"])
    mb.rbox((x - 2.3, 27.0, z + .01), (x + 1.5, 31.6, z + .08), m["steel_grey"])
    mb.rbox((x + 2, 28.4, z + .02), (x + 2.8, 29.2, z + .15), m["black"])
    mb.rcol((x - 3.5, 26.0, wz), (x + 3.5, 33.6, z))
    _finish(mb, main + "_Body", main, "L4MainBreaker", part="Body")
    mb = r["RMesh"](main + "Lever")
    mb.rbox((x - 1.4, 28.0, z + .55), (x + .6, 30.9, z + .86), m["control_red"], .1)
    lever = _finish(mb, main + "_Lever", main, part="Lever")
    _pivot(lever, (x - .4, 30.9, z + .705))
    lever["l4_on_angle"], lever["l4_col"] = -80, "[]"
    _marker("L4FuseSocket", "FuseSocket", (x + 2.4, 28.8, z + .24), (1, 1, 1))


def _prize(r, m):
    o = bpy.data.objects["ArcadePrize"]
    py = lambda y: r["_v6_counter_y"](y, 28.61)
    # v4 front glass is a single box. Remove only that box, retain showcase and prizes.
    if not o.get("l4_round_prize_split"):
        o.data = o.data.copy()
        bm = bmesh.new(); bm.from_mesh(o.data)
        kill = []
        for f in bm.faces:
            pts = [_stud(o.matrix_world @ v.co) for v in f.verts]
            if all(23175.09 <= p[0] <= 23208.91 and py(24.899) <= p[1] <= py(28.301) and 224.079 <= p[2] <= 224.121 for p in pts):
                kill.append(f)
        assert len(kill) == 6, "prize glass shape drifted; inspect fresh geometry"
        bmesh.ops.delete(bm, geom=kill, context="FACES")
        bm.to_mesh(o.data); bm.free()
        o["l4_round_prize_split"] = True
    o["l4_prop"], o["l4_model"], o["l4_model_group"] = o.data.name, "PrizeCase", "PrizeCase"
    o["l4_model_tags"], o["l4_model_attributes"] = "L4PrizeCase", "{}"
    o["l4_part_name"] = "Case"
    for k, xa, xb in ((0, 23175.1, 23183.65), (1, 23191.85, 23208.9)):
        mb = r["RMesh"]("PrizeFixedGlass%d" % k)
        mb.rbox((xa, py(24.9), 224.08), (xb, py(28.3), 224.12), m["glass"])
        _finish(mb, "PrizeFixedGlass%d" % k, "PrizeCase", part="FixedGlass")
    mb = r["RMesh"]("PrizeGlassDoor")
    mb.rbox((23183.65, py(24.9), 224.065), (23191.85, py(28.3), 224.125), m["glass"])
    door = _finish(mb, "PrizeGlassDoor", "PrizeCase", part="Door")
    _pivot(door, (23191.85, py(26.6), 224.095))
    door["l4_on_angle"], door["l4_col"] = -100, "[]"
    # Visible keypad body plus coincident invisible gameplay marker.
    mb = r["RMesh"]("PrizeKeypadBody")
    mb.rbox((23192.2, py(25.6), 223.5), (23193.6, py(27.4), 223.9), m["black"], .04)
    for row in range(4):
        for col in range(3):
            x, y = 23192.45 + col * .43, 27.12 - row * .41
            mb.rbox((x - .13, py(y - .12), 223.47), (x + .13, py(y + .12), 223.51), m["chrome"], .015)
    _finish(mb, "PrizeKeypadBody", "PrizeCase", part="Keypad")
    _marker("L4PrizeKeypad", "PrizeKeypad", (23192.9, py(26.5), 223.46), (1.4, py(27.4)-py(25.6), .12))


def _arcade(r, m):
    cabinet = next(o for o in bpy.data.objects if o.get("l4_model") == "ArcadeLeft_01")
    cabinet["l4_model_group"] = cabinet.name
    cabinet["l4_model_tags"] = "L4ArcadeCode"
    cabinet["l4_model_attributes"] = "{}"
    cabinet["l4_part_name"] = "Cabinet"
    kind = str(cabinet.get("l4_prop"))
    (y0, z0), (y1, z1), width = r["SCREENS"][kind]
    # Native CRT face remains under the independent thin screen skin; its UV stays intact.
    normal = Vector((0, -(z1-z0), y1-y0)).normalized()
    points = [Vector((-width, y0, z0)), Vector((width, y0, z0)),
              Vector((width, y1, z1)), Vector((-width, y1, z1))]
    points = [cabinet.matrix_world @ (v + normal * .014) for v in points]
    centre = sum(points, Vector()) / 4
    right = -(points[1]-points[0]).normalized()
    up = (points[3]-points[0]).normalized()
    out = up.cross(right).normalized()
    rotation = Matrix((right,out,up)).transposed()
    frame = Matrix.Translation(centre) @ rotation.to_4x4()
    me = bpy.data.meshes.new("L4Round_ArcadeCodeScreen")
    me.from_pydata([frame.inverted() @ p for p in points], [], [(0, 1, 2, 3)])
    me.materials.append(m["black"])
    o = _object(me, "ArcadeCodeScreen")
    o.matrix_world = frame
    o["l4_prop"], o["l4_model"], o["l4_model_group"] = me.name, cabinet.name, cabinet.name
    o["l4_part_name"], o["l4_col"] = "Screen", "[]"


def _surface(o, x, z, ceiling=150):
    start = _rb((x, ceiling, z)); inv = o.matrix_world.inverted()
    direction = (inv.to_3x3() @ Vector((0, 0, -1))).normalized()
    hit, pos, normal, face = o.ray_cast(inv @ start, direction)
    assert hit, "No authored surface beneath %s at %.3f %.3f" % (o.name, x, z)
    world = o.matrix_world @ pos
    assert (o.matrix_world.to_3x3() @ normal).normalized().z > .85, "spot is not on a flat top"
    return _stud(world)[1]


def _spot(tag, name, obj, x, z, size, attrs=None, ceiling=150):
    y = _surface(obj, x, z, ceiling)
    o = _marker(tag, name, (x, y-size[1]/2, z), size, attrs)
    o["l4_support"], o["l4_surface_y"] = obj.name, y
    return o


def _spots(r, m):
    cy = r["_v6_counter_y"]
    # 28 players: 4 columns, 7 rows. Slot 1 at back, the other pads point north.
    for i, (x, z) in enumerate(((22864, 90), (22858, 70), (22864, 70),
                                (22870, 70), (22858, 66), (22870, 66)), 1):
        _marker("L4EntrySpawn", "EntrySpawn_%d" % i, (x, 23.55, z), (4, 1, 4), {"Slot": i})
    # A small wall-mounted tray makes the service-door note immediately reachable.
    tray = r["RMesh"]("ServiceDoorNoteTray")
    tray.rbox((22872, 27.8, 98.1), (22877, 28.0, 100.05), m["steel_grey"], .025)
    tray.rcol((22872, 27.8, 98.1), (22877, 28.0, 100.05))
    tray = _finish(tray, "ServiceDoorNoteTray")
    # The rack's wire deck gets a thin metal writing tray; no marker lies over an empty grid cell.
    shelf = r["RMesh"]("ServiceShelfNoteTray")
    shelf.rbox((22744, 31.77, 117), (22747, 31.82, 120), m["deck"])
    shelf = _finish(shelf, "ServiceShelfNoteTray")
    table = next(o for o in bpy.data.objects if o.get("l4_model") == "LobbyTable"
                 and o.get("l4_src") is not None and abs(_stud(o.location)[0]-22825) < 1)
    for name, obj, x, z, limit in (
        ("Note_Workbench", bpy.data.objects["Workbench"], 22801, 226, 29),
        ("Note_Concession", bpy.data.objects["Concession_Counter"], 22894, 111, cy(29)),
        ("Note_Cafe", table, 22824.3, 55, 28.1),
        ("Note_ServiceShelf", shelf, 22745.5, 118.5, 33),
        ("Note_TicketBooth", bpy.data.objects["Concession_BoxOffice"], 22947, 103.1, 29),
        ("Note_ServiceDoor", tray, 22874.5, 99, 29)):
        _spot("L4NoteSpot", name, obj, x, z, (1, .2, 1.4), ceiling=limit)

    _spot("L4ReelSpot", "Reel_Prize", bpy.data.objects["ArcadePrize"], 23187.5, 225.5,
          (1.4, .6, 1.4), {"SpotName": "Præmemontren", "Locked": True}, cy(26.05, 28.61))
    _spot("L4ReelSpot", "Reel_Popcorn", bpy.data.objects["PopcornStation"], 22909, 110.5,
          (1.4, .6, 1.4), {"SpotName": "Popcornmaskinen"}, cy(32))
    for nm, x in (("Men", 23277), ("Women", 23318)):
        _marker("L4ReelSpot", "Reel_"+nm, (x, 23.7, 154), (1.4,.6,1.4),
                {"SpotName": "Herretoilettet" if nm == "Men" else "Dametoilettet"})
    _spot("L4ReelSpot", "Reel_ServiceShelf", shelf, 22746, 119, (1.4,.6,1.4), {"SpotName":"Servicereolen"}, 33)
    _spot("L4ReelSpot", "Reel_Cafe", table, 22826, 54.5, (1.4,.6,1.4), {"SpotName":"Cafébordet"}, 28.1)
    _spot("L4ReelSpot", "Reel_BackCounter", bpy.data.objects["Concession_Counter"], 23044, 109.2,
          (1.4,.6,1.4), {"SpotName":"Bag disken"}, cy(29))
    seat = next(o for o in bpy.data.objects if o.get("l4_prop", "").startswith("CinemaSeat")
                and o.get("l4_src") is not None and r["D2_P"][o["l4_src"]]["p"] == "A1/A1_ChairSeat"
                and abs(r["D2_P"][o["l4_src"]]["cf"][0]-22704) < 1
                and abs(r["D2_P"][o["l4_src"]]["cf"][2]+200) < 1)
    _spot("L4ReelSpot", "Reel_Cinema1", seat, 22704, -200.7, (1.4,.6,1.4), {"SpotName":"Sædet i Cinema 1"}, 30)
    locker = bpy.data.objects["Gallery_LockerBank1"]
    _spot("L4ReelSpot", "Reel_Gallery", locker, 23375, .7, (1.4,.6,1.4), {"SpotName":"Skabene på galleriet"}, 96)
    _spot("L4ReelSpot", "Reel_TicketBooth", bpy.data.objects["Concession_BoxOffice"], 22994, 103.1,
          (1.4,.6,1.4), {"SpotName":"Billetlugen"}, 29)


def _screens_projectors(r):
    for num in (1, 2, 3):
        obj = bpy.data.objects["A%d_Projector" % num]
        obj["l4_model_tags"] = "L4Projector"
        obj["l4_model_attributes"] = json.dumps({"Screen":num})
        obj["l4_model_group"] = obj.get("l4_model", obj.name)
        scr = next(p for p in r["D2_P"] if p["p"] == "A%d/A%d_Screen" % (num, num))
        # v4's visible screen plane is the original Back face with 0.12 stud thickness behind it.
        face = scr["cf"][2] + scr["s"][2]/2
        _marker("L4Screen", "Screen_%d" % num, (scr["cf"][0],scr["cf"][1],face + .025),
                (scr["s"][0],scr["s"][1],.05), {"Screen":num})
        if num == 2:
            _marker("L4ExitScreen", "ExitScreen", (scr["cf"][0],scr["cf"][1],face+.25),
                    (scr["s"][0],scr["s"][1],.5))


def _hides(r):
    for aid in ("A1","A2","A3"):
        rows = collections.defaultdict(list)
        for p in r["D2_P"]:
            if p["p"] == aid+"/"+aid+"_ChairSeat" and not p.get("removed"):
                rows[(p["cf"][1],p["cf"][2])].append(p["cf"][0])
        for i, ((height,z), xs) in enumerate(sorted(rows.items())):
            if i not in (1,4,7,10,13,16):
                continue
            centre = sum(xs)/len(xs)
            for side, xx in (("L",[x for x in xs if x < centre]), ("R",[x for x in xs if x > centre])):
                # Legroom in front of each selected seat block; centre aisle remains outside both boxes.
                xa, xb = min(xx)-1.8, max(xx)+1.8
                floor = height-1
                _marker("L4HideZone", "Hide_%s_Row%d_%s" % (aid,i+1,side),
                        ((xa+xb)/2,floor+1.5,z-3.3),(xb-xa,3,1.8), {"HideKind":"Seats"})
    for room in r["ROOMS"]:
        for i in (0,1):
            pl, pr = room["panels"][2*i:2*i+2]
            # Front half of a stall avoids the toilet bowl and the opened door's sweep.
            _marker("L4HideZone", "Hide_%s_Stall%d" % (room["name"],i+1),
                    ((pl+pr)/2,25.8,154.7), (pr-pl-1,3.6,5.2), {"HideKind":"Stall"})
    if r["V6_EDITS"]["low_counters"]:
        floor, top = r["FLOOR"] + .05, r["_v6_counter_y"](r["CTOP"])
        _marker("L4HideZone", "Hide_ConcessionCounter", (22929,(floor+top)/2,105.5),
                (72,top-floor,3.7), {"HideKind":"Counter"})
    else:
        _marker("L4HideZone", "Hide_ConcessionCounter", (22929,25.5,105.5),(72,3,3.7), {"HideKind":"Counter"})


def _safe(r, m):
    # Collision-only opaque walls are exported as inset black Parts. They do not expand cull's render voxel domain.
    for name, centre, size in (
        ("Floor",(23000,-401,350),(40,2,32)), ("Roof",(23000,-386,350),(40,2,32)),
        ("West",(22979,-393.5,350),(2,17,36)), ("East",(23021,-393.5,350),(2,17,36)),
        ("North",(23000,-393.5,333),(40,17,2)), ("South",(23000,-393.5,367),(40,17,2))):
        mb = r["RMesh"]("AfterCredits"+name)
        lo = [centre[i]-size[i]/2 for i in range(3)]
        hi = [centre[i]+size[i]/2 for i in range(3)]
        mb.rbox(lo,hi,m["black"]); mb.rcol(lo,hi)
        o = _finish(mb,"AfterCredits"+name)
        o.hide_render = True
        o["l4_collision_only"],o["l4_occluder"] = True,True
        o["l4_tags"],o["l4_attributes"] = "L4AfterCreditsRoom",json.dumps({"L4Owned":True})
    for i in range(6):
        _marker("L4ExitSafeSpawn","ExitSafeSpawn_%d" % (i+1),
                (22990+(i%3)*10,-399.95,343+(i//3)*12),(4,.1,4),{"Slot":i+1})


def _exit_access(r):
    """The full Cinema 2 screen starts at Y38; a walk-up stage makes its exit volume reachable."""
    carpet = r["slot"]("CARPET_AUD")
    for i in range(7):
        top = 26+2*i if i < 6 else 36
        za,zb = (-222-2*i,-220-2*i) if i < 6 else (-237.7,-232)
        name = "L4ExitAccess_Tread%02d" % (i+1) if i < 6 else "L4ExitAccess_Platform"
        mb = r["RMesh"](name)
        lo,hi = (22995,24,za),(23005,top,zb)
        mb.rbox(lo,hi,carpet);mb.rcol(lo,hi)
        o = _finish(mb,name)
        o["l4_tags"] = "Level4V4Floor,L4ExitAccess"
        o["l4_attributes"] = json.dumps({"L4NavFloor":True})
        o["l4_occluder"] = True


def check_exit_access():
    objs = [bpy.data.objects["L4ExitAccess_Tread%02d" % i] for i in range(1,7)]
    platform = bpy.data.objects["L4ExitAccess_Platform"]
    tops,headroom = [],[]
    bpy.context.view_layer.update()
    graph = bpy.context.evaluated_depsgraph_get()
    for i,o in enumerate(objs+[platform]):
        x,y,z = _stud(o.location)
        top = _surface(o,x,z,40)
        tops.append(top)
        assert abs(top-(26+2*i if i < 6 else 36)) < .002
        assert "Level4V4Floor" in o["l4_tags"] and json.loads(o["l4_attributes"])["L4NavFloor"]
        assert o["l4_occluder"] and len(json.loads(o.data["l4_col"]))==1
        origin = _rb((x,top+.05,z))
        for _ in range(8):
            hit,point,normal,index,obstacle,matrix = bpy.context.scene.ray_cast(graph,origin,Vector((0,0,1)),distance=80*S)
            if not hit or not obstacle.get("l4_marker"):
                break
            origin = point+Vector((0,0,.005))
        clearance = (_stud(point)[1]-top) if hit else 80
        assert clearance >= 7.6,(o.name,obstacle.name,clearance)
        headroom.append(round(clearance,4))
    assert max(b-a for a,b in zip([24]+tops,tops)) <= 2.5
    for z in (-233,-235,-236.5):
        assert abs(_surface(platform,23000,z,40)-36) < .002
    # Standing root on the platform is within the gameplay exit OBB (+3stud tolerance).
    exit = bpy.data.objects["ExitScreen"]
    point = _rb((23000,39,-235.6))
    local = exit.matrix_world.inverted() @ point
    assert all(abs(local[k])/S <= exit.dimensions[k]/S/2+3 for k in range(3))
    overlaps = []
    for seat in bpy.data.collections["L4 Cinema"].all_objects:
        if seat.type != "MESH" or not seat.get("l4_prop","").startswith("CinemaSeat"):
            continue
        co = [_stud(seat.matrix_world @ Vector(v)) for v in seat.bound_box]
        lo = [min(v[k] for v in co) for k in range(3)]
        hi = [max(v[k] for v in co) for k in range(3)]
        if all(min(hi[k],(23005,36,-220)[k])-max(lo[k],(22995,24,-237.7)[k]) > .001 for k in range(3)):
            overlaps.append(seat.name)
    assert not overlaps,overlaps
    return {"floor_tops":tops,"step_max":2,"platform_root":[23000,39,-235.6],
            "exit_obb_reachable":True,"seat_overlaps":0,"headroom":headroom}


def _spawn_check(r):
    """Conservative OBB-to-AABB clearance check for the exact 28-player entry grid."""
    boxes = []
    for p in r["D2_P"]:
        if p.get("cc") and not p.get("removed") and p["t"] < 1:
            R = Matrix([p["cf"][3:6],p["cf"][6:9],p["cf"][9:12]])
            extent = Vector(tuple(sum(abs(R[i][j])*p["s"][j]/2 for j in range(3)) for i in range(3)))
            c = Vector(p["cf"][:3]); boxes.append((p["p"],c-extent,c+extent))
    for o in bpy.data.collections["L4 Cinema"].all_objects:
        if o.type != "MESH" or o.get("l4_marker"):
            continue
        cols = json.loads(o.get("l4_col",o.data.get("l4_col","[]")))
        for b in cols:
            corners = [o.matrix_world @ Vector((b[0]+sx*b[3]/2,b[1]+sy*b[4]/2,b[2]+sz*b[5]/2))
                       for sx in (-1,1) for sy in (-1,1) for sz in (-1,1)]
            rb = [_stud(c) for c in corners]
            lo = Vector(tuple(min(c[i] for c in rb) for i in range(3)))
            hi = Vector(tuple(max(c[i] for c in rb) for i in range(3)))
            boxes.append((o.name,lo,hi))
    conflicts = []
    for row in range(7):
        for col in range(4):
            c = Vector((22864+(col-1.5)*4,27.05,90-row*4))
            lo,hi = c-Vector((1.3,2.9,1.3)),c+Vector((1.3,3.0,1.3))
            for name,blo,bhi in boxes:
                if all(min(hi[i],bhi[i])-max(lo[i],blo[i]) > .015 for i in range(3)):
                    conflicts.append((row,col,name))
    assert not conflicts, ("entry grid collision",conflicts)
    return {"players":28,"tested_collision_boxes":len(boxes),"overlaps":0}


def check_round_assets():
    counts = collections.Counter()
    groups = collections.defaultdict(list)
    for o in bpy.data.objects:
        for key in ("l4_tags","l4_model_tags"):
            for tag in o.get(key,"").split(","):
                if tag in REQUIRED:
                    counts[tag] += 1
        if o.get("l4_model_group"):
            groups[o["l4_model_group"]].append(o)
        if o.get("l4_marker") and o.get("l4_pkg") == PKG:
            assert o.hide_render and json.loads(o["l4_col"]) == []
            if o.get("l4_support"):
                support = bpy.data.objects[o["l4_support"]]
                x,y,z = _stud(o.location)
                hit_y = _surface(support,x,z,o["l4_surface_y"]+.1)
                assert abs(hit_y-o["l4_surface_y"]) < .005
                assert abs(y+o.dimensions.z/S/2-hit_y) < .005
        if o.get("l4_pivot"):
            p = json.loads(o["l4_pivot"])
            assert p[3:] in (IDENTITY,[-1,0,0,0,1,0,0,0,-1]) and len(o.data.materials)==1
            world = o.matrix_world @ Vector((p[0]*S,-p[2]*S,p[1]*S))
            assert (_rb(json.loads(o["l4_hinge_world"]))-world).length < 1e-4, o.name
    assert dict(counts) == REQUIRED,(counts,REQUIRED)
    for name, parts in groups.items():
        tags = set(t for o in parts for t in o.get("l4_model_tags","").split(","))
        for tag, part in (("L4Breaker","Handle"),("L4MainBreaker","Lever"),("L4PrizeCase","Door"),("L4ArcadeCode","Screen")):
            if tag in tags:
                moving = [o for o in parts if o.get("l4_part_name")==part]
                assert len(moving)==1,(name,part)
                if part != "Screen":
                    assert moving[0].get("l4_pivot")
    return {"counts":dict(counts),"moving_parts":8,"screen_parts":1,
            "entry_grid":{"centre":[22864,24,90],"direction":[0,0,-1],"columns":4,"rows":7,"spacing":4},
            "safe_room_solids":6,"all_contracts":True}


def build_round_assets():
    for o in list(bpy.data.objects):
        if o.get("l4_pkg")==PKG:
            bpy.data.objects.remove(o,do_unlink=True)
    r = _rooms(); m = r["_mats"](); m["control_red"] = _control_red(r)
    _panels(r,m); _prize(r,m); _arcade(r,m); _spots(r,m); _screens_projectors(r); _hides(r); _safe(r,m); _exit_access(r)
    result = check_round_assets()
    result["spawn_clearance"] = _spawn_check(r)
    result["exit_access"] = check_exit_access()
    print("round_assets:",json.dumps(result),flush=True)
    return result
