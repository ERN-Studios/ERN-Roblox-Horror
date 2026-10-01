"""Append the 1990s kitchen and back-service sections to an existing Level 6 kit.

Call ``build_revision_sections(materials, parent=library_scene.collection)`` after
the original ``L6K_*`` prefabs exist. The result contains new prefab collections,
room collections, placement records, and measured triangle counts. This module
does not clear a scene, save a file, export meshes, or touch a live game.

All distances are Roblox studs (one Blender unit per stud), Z is up, and a
prefab's front is -Y. Rooms are 24 X by 24 Y by 12 Z with clear, 14-stud
north/south portals. Collection instances in room modules must be realized or
exported separately by a caller that needs a flat mesh package. Collision-only
proxies and connection anchors must not become visual meshes.
"""

from __future__ import annotations

import importlib.util
import math
from pathlib import Path

import bpy


PREFIX = "L6K_"
ROOM_WIDTH = 24.0
ROOM_DEPTH = 24.0
ROOM_HEIGHT = 12.0
DOOR_WIDTH = 14.0
DOOR_HEIGHT = 10.5
WALL_THICKNESS = 1.5

NEW_PROPS = (
    "KitchenPrepBench", "KitchenShelf", "KitchenHood", "KitchenFridge",
    "KitchenStove", "KitchenWasteBin", "KitchenTrayStack", "StaffBreakCounter",
)
NEW_ROOMS = ("RoomKitchenPrep", "RoomUtilityHall", "RoomStaffNook")
REQUIRED_EXISTING = (
    "FluorescentFrame", "FluorescentDiffuser", "WorkshopBench", "Pegboard",
    "BreakerPanel", "MopBucket", "SupplyShelf", "ChairRed", "ChairBlue",
    "WallClock",
)
REQUIRED_MATERIALS = (
    "kitchen_tile", "diamondplate", "wallpaper", "orange_wall",
    "carpet_city", "carpet_red", "grey_metal", "black_metal", "chrome", "cardboard",
    "paper", "rubber", "laminate", "wood_worn", "ivory_plastic",
    "red_plastic", "ceiling", "ceiling_grid", "black_wall",
)

# Tuple members: asset, XYZ offset, rotation around Z in degrees. A quarter turn
# puts long benches and shelves along a side wall, away from the portal axis.
ROOM_FURNISHINGS = {
    "RoomKitchenPrep": (
        ("KitchenPrepBench", (-6.25, -5.4, 0), 90),
        ("KitchenTrayStack", (-6.10, -6.7, 3.34), 90),
        ("KitchenStove", (-6.25, 3.15, 0), 90),
        ("KitchenHood", (-6.25, 3.15, 0), 90),
        ("KitchenFridge", (6.15, -7.2, 0), 0),
        ("KitchenShelf", (6.35, 3.4, 0), -90),
        ("KitchenWasteBin", (5.9, -1.35, 0), 0),
    ),
    "RoomUtilityHall": (
        ("WorkshopBench", (-6.2, -1.1, 0), 90),
        ("Pegboard", (-7.37, -1.1, 4.4), 90),
        ("SupplyShelf", (6.35, -4.5, 0), -90),
        ("BreakerPanel", (7.36, 5.5, 3.1), -90),
        ("MopBucket", (5.35, 6.6, 0), 0),
        ("KitchenWasteBin", (-5.7, 7.8, 0), 0),
    ),
    "RoomStaffNook": (
        ("StaffBreakCounter", (-6.15, -1.7, 0), 90),
        ("ChairRed", (4.8, -4.5, 0), -90),
        ("ChairBlue", (4.8, 2.9, 0), -90),
        ("KitchenFridge", (6.15, 7.25, 0), 0),
        ("KitchenWasteBin", (-5.9, 7.4, 0), 0),
        ("WallClock", (7.42, 0.4, 8.1), -90),
    ),
}


def room_furnishings(name):
    """Keep furnishings at their authored distance from the widened side walls."""
    shift = (ROOM_WIDTH - 18.0) / 2
    return tuple((asset, (xyz[0] + math.copysign(shift, xyz[0]) if xyz[0] else 0,
                           xyz[1], xyz[2]), angle)
                 for asset, xyz, angle in ROOM_FURNISHINGS[name])

ROOM_FINISHES = {
    "RoomKitchenPrep": {"floor": "kitchen_tile", "wall": "kitchen_tile",
                        "upper": "orange_wall", "kick": "grey_metal"},
    "RoomUtilityHall": {"floor": "diamondplate", "wall": "orange_wall",
                         "upper": "orange_wall", "kick": "diamondplate"},
    "RoomStaffNook": {"floor": "carpet_city", "wall": "wallpaper",
                       "upper": "wallpaper", "kick": "wood_worn"},
}


def _prop_module():
    """Load the kit's existing low-poly geometry/proxy helpers by file path."""
    spec = importlib.util.spec_from_file_location(
        "level6_revision_prop_helpers", Path(__file__).with_name("props.py"))
    if spec is None or spec.loader is None:
        raise RuntimeError("Could not load Level 6 prop geometry helpers")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _anchor(collection, asset, label, xyz, **metadata):
    obj = bpy.data.objects.new(asset + "__" + label, None)
    collection.objects.link(obj)
    obj.location = xyz
    obj.empty_display_type = "PLAIN_AXES"
    obj.empty_display_size = .24
    obj.hide_render = True
    obj["l6_asset"] = asset
    obj["l6_role"] = "connection_anchor" if label.startswith("Join") else "interaction_anchor"
    obj["l6_anchor"] = label
    for key, value in metadata.items():
        obj[key] = value
    return obj


def _make_asset(helpers, parent, name, geometry, materials, collision=(), anchors=None):
    col = bpy.data.collections.new(PREFIX + name)
    parent.children.link(col)
    col["l6_asset"] = name
    col["l6_family"] = "back-service-prop"
    col["l6_units"] = "studs"
    col["l6_forward"] = "-Y"
    helpers._create_mesh_objects(name, geometry, col, materials)
    for i, (center, size) in enumerate(collision):
        helpers._proxy(name, i, center, size, col)
    for label, xyz in (anchors or {}).items():
        _anchor(col, name, label, xyz)
    return col


def _prep_bench(G):
    g = G()
    # Pressed stainless top has a real opening rather than a black sticker.
    for x in (-2.70, 2.70):
        for y in (-.94, .94):
            g.box("grey_metal", (x, y, 1.63), (.22, .18, 3.26))
    g.box("grey_metal", (-1.33, 0, 3.30), (3.14, 2.4, .18))
    g.box("grey_metal", (2.45, 0, 3.30), (.90, 2.4, .18))
    for y in (-.88, .88):
        g.box("grey_metal", (1.13, y, 3.30), (1.76, .64, .18))
    g.box("grey_metal", (0, 1.13, 3.75), (5.8, .12, .78))
    for x in (.25, 2.01):
        g.box("grey_metal", (x, 0, 2.92), (.11, 1.11, .63))
    for y in (-.55, .55):
        g.box("grey_metal", (1.13, y, 2.92), (1.87, .08, .63))
    g.box("black_metal", (1.13, 0, 2.62), (1.75, 1.04, .08))
    g.cone("chrome", (1.13, 0, 2.67), .11, .02, sides=8)
    g.box("grey_metal", (0, 0, .72), (5.23, 2.05, .12))
    for x in (-2.4, 2.4):
        for y in (-.9, .9):
            g.box("rubber", (x, y, .07), (.20, .18, .14))
    # Two-knob bent spout, low segment count and no bevel modifier.
    g.rod("chrome", (1.08, .84, 3.36), (1.08, .84, 4.11), .065, 6)
    g.rod("chrome", (1.08, .84, 4.11), (1.08, .17, 4.11), .065, 6)
    g.rod("chrome", (1.08, .17, 4.11), (1.08, .17, 3.85), .055, 6)
    for x in (.46, 1.70):
        g.cone("black_metal", (x, .82, 3.39), .12, .11, sides=8)
    for x in (-2.4, -1.62, -1.1):
        g.box("black_metal", (x, -1.205, 3.305), (.16, .018, .025))
    return g


def _shelf(G):
    g = G()
    for x in (-2.25, 2.25):
        for y in (-.62, .62):
            g.box("grey_metal", (x, y, 3.29), (.12, .12, 6.58))
    for z in (.38, 2.30, 4.24, 6.14):
        g.box("grey_metal", (0, 0, z), (4.70, 1.36, .10))
        g.box("black_metal", (0, -.70, z-.03), (4.68, .05, .06))
    for x, y, z, w, d, h in (
        (-1.25, 0, .44, 1.40, .98, 1.16), (.66, 0, .44, 1.62, 1.02, .95),
        (-1.10, .08, 2.36, 1.48, .98, 1.31), (1.10, 0, 4.30, 1.65, .95, 1.10),
    ):
        g.box("cardboard", (x, y, z+h/2), (w, d, h))
        g.box("paper", (x, -.51, z+h*.57), (w*.44, .015, h*.27))
    for x in (-1.43, -.67, .13):
        g.cone("ivory_plastic", (x, 0, 4.69), .23, .75, sides=8)
        g.cone("black_metal", (x, 0, 5.08), .22, .025, sides=8)
    for x in (.12, 1.10, 1.73):
        g.box("grey_metal", (x, 0, 6.42), (.51, .92, .42))
    return g


def _hood(G):
    g = G()
    # Floor-origin wall fixture: the canopy bottom sits above the stove.
    g.box("grey_metal", (0, .15, 7.49), (4.55, 2.28, .18))
    g.box("black_metal", (0, -.51, 7.39), (3.62, .75, .025))
    for x in (-1.35, -.81, -.27, .27, .81, 1.35):
        g.box("grey_metal", (x, -.51, 7.37), (.055, .72, .035))
    g.profile("grey_metal", [(-.99, 7.58), (1.13, 7.58),
                              (.50, 8.76), (-.47, 8.76)], 4.28)
    g.box("grey_metal", (0, .02, 10.31), (1.68, 1.38, 3.18))
    g.box("black_metal", (0, -1.01, 7.48), (4.05, .055, .09))
    return g


def _fridge(G):
    g = G()
    g.box("ivory_plastic", (0, 0, 3.43), (2.47, 2.55, 6.66), .04)
    g.box("grey_metal", (0, 0, .11), (2.51, 2.58, .22))
    g.box("ivory_plastic", (0, -1.30, 2.00), (2.31, .075, 3.86))
    g.box("ivory_plastic", (0, -1.30, 5.45), (2.31, .075, 2.62))
    g.box("black_metal", (0, -1.35, 3.94), (2.30, .025, .06))
    for x, z, h in ((.79, 2.78, 1.02), (.79, 5.70, .68)):
        g.box("chrome", (x, -1.40, z), (.12, .13, h))
        for sign in (-1, 1):
            g.box("grey_metal", (x, -1.34, z+sign*(h/2-.08)), (.20, .15, .07))
    for x in (-.68, -.34, 0, .34, .68):
        g.box("black_metal", (x, -1.40, .36), (.10, .025, .16))
    g.box("paper", (-.50, -1.35, 5.28), (.61, .015, .40))
    g.box("red_plastic", (-.50, -1.36, 5.45), (.60, .012, .065))
    return g


def _stove(G):
    g = G()
    g.box("grey_metal", (0, 0, 1.73), (3.14, 2.58, 3.40), .025)
    g.box("black_metal", (0, -1.33, 1.72), (2.78, .06, 2.32))
    g.box("grey_metal", (0, -1.37, 1.70), (2.46, .035, 2.01))
    g.box("black_metal", (0, -1.40, 1.78), (2.14, .025, 1.65))
    g.box("chrome", (0, -1.52, 2.52), (1.87, .12, .09))
    for x in (-1.04, -.35, .35, 1.04):
        g.cone("black_metal", (x, -1.40, 3.00), .13, .12, sides=8)
        g.box("chrome", (x, -1.54, 3.00), (.035, .025, .18))
    g.box("grey_metal", (0, 0, 3.44), (3.16, 2.62, .13))
    for x in (-.73, .73):
        for y in (-.59, .59):
            g.cone("black_metal", (x, y, 3.53), .36, .05, sides=8)
            g.cone("grey_metal", (x, y, 3.565), .17, .03, sides=8)
    g.box("grey_metal", (0, 1.25, 3.80), (3.16, .12, .63))
    return g


def _waste_bin(G):
    g = G()
    g.cone("grey_metal", (0, 0, 1.01), .68, 1.96, .83, sides=10)
    g.cone("black_metal", (0, 0, 1.995), .79, .025, sides=10)
    g.ring("grey_metal", (0, 0, 2.02), .85, .71, .10, sides=10)
    g.box("paper", (0, -.78, 1.08), (.50, .015, .43))
    return g


def _trays(G):
    g = G()
    for i in range(4):
        z = .07+i*.13
        g.box("grey_metal", (0, 0, z), (1.78, 1.02, .035))
        for y in (-.50, .50):
            g.box("grey_metal", (0, y, z+.06), (1.78, .05, .11))
        for x in (-.86, .86):
            g.box("grey_metal", (x, 0, z+.06), (.05, 1.02, .11))
    return g


def _break_counter(G):
    g = G()
    g.box("wood_worn", (0, .20, 1.59), (5.31, 1.87, 3.14))
    g.box("laminate", (0, 0, 3.25), (5.48, 2.27, .16))
    g.box("grey_metal", (0, -1.00, .15), (5.27, .08, .30))
    for x in (-1.31, 1.31):
        g.box("black_metal", (x, -1.01, 1.75), (.035, .020, 2.72))
        g.box("chrome", (x, -1.07, 1.61), (.52, .12, .08))
    # An early-90s box microwave and a mismatched coffee urn.
    g.box("ivory_plastic", (-1.19, .12, 3.87), (2.20, 1.37, 1.12))
    g.box("black_metal", (-1.43, -.585, 3.88), (1.38, .03, .75))
    g.box("chrome", (-.29, -.62, 3.87), (.09, .07, .47))
    for z in (3.65, 3.91, 4.17):
        g.box("black_metal", (-.04, -.61, z), (.14, .04, .045))
    g.cone("chrome", (1.31, .25, 3.88), .43, .91, .39, sides=10)
    g.cone("black_metal", (1.31, .25, 4.37), .44, .08, sides=10)
    g.box("black_metal", (1.80, .15, 3.89), (.17, .36, .34))
    g.box("paper", (1.84, -.55, 3.38), (.45, .45, .13))
    return g


PROP_BUILDERS = {
    "KitchenPrepBench": _prep_bench,
    "KitchenShelf": _shelf,
    "KitchenHood": _hood,
    "KitchenFridge": _fridge,
    "KitchenStove": _stove,
    "KitchenWasteBin": _waste_bin,
    "KitchenTrayStack": _trays,
    "StaffBreakCounter": _break_counter,
}

PROP_COLLISION = {
    "KitchenPrepBench": (((0, 0, 1.70), (5.80, 2.40, 3.40)),),
    "KitchenShelf": (((0, 0, 3.30), (4.70, 1.40, 6.60)),),
    "KitchenHood": (),
    "KitchenFridge": (((0, 0, 3.43), (2.51, 2.59, 6.86)),),
    "KitchenStove": (((0, 0, 1.76), (3.18, 2.64, 3.52)),),
    "KitchenWasteBin": (((0, 0, 1.02), (1.70, 1.70, 2.04)),),
    "KitchenTrayStack": (),
    "StaffBreakCounter": (((0, .10, 1.65), (5.50, 2.30, 3.30)),),
}

PROP_ANCHORS = {
    "KitchenPrepBench": {"Sink": (1.13, -.38, 3.35)},
    "KitchenFridge": {"Handle": (.79, -1.49, 2.78)},
    "KitchenStove": {"OvenControls": (0, -1.50, 3.03)},
    "StaffBreakCounter": {"Microwave": (-1.19, -.70, 3.88)},
}


def _room_geometry(G, room_name):
    f = ROOM_FINISHES[room_name]
    g = G()
    g.box("black_wall", (0, 0, -.52), (ROOM_WIDTH, ROOM_DEPTH, 1.00))
    g.box(f["floor"], (0, 0, -.01), (ROOM_WIDTH, ROOM_DEPTH, .04))
    # Divide walls at a seven-stud washable wainscot line in the kitchen.
    wall_segments = ((3.50, 7.00, f["wall"]), (9.50, 5.00, f["upper"]))
    for z, height, key in wall_segments:
        for x in (-ROOM_WIDTH/2+WALL_THICKNESS/2,
                  ROOM_WIDTH/2-WALL_THICKNESS/2):
            g.box(key, (x, 0, z), (WALL_THICKNESS, ROOM_DEPTH, height))
        side_width = (ROOM_WIDTH-DOOR_WIDTH)/2
        for y in (-ROOM_DEPTH/2+WALL_THICKNESS/2,
                  ROOM_DEPTH/2-WALL_THICKNESS/2):
            for x in (-(DOOR_WIDTH+side_width)/2,
                      (DOOR_WIDTH+side_width)/2):
                g.box(key, (x, y, z),
                      (side_width, WALL_THICKNESS, height))
    # The opening is full width below 10.5 studs; no hidden door leaf.
    for y in (-11.25, 11.25):
        g.box(f["upper"], (0, y, 11.25),
              (DOOR_WIDTH, WALL_THICKNESS, ROOM_HEIGHT-DOOR_HEIGHT))
        for x in (-(DOOR_WIDTH/2+.03), DOOR_WIDTH/2+.03):
            g.box("grey_metal", (x, y-.015, 5.24), (.055, 1.56, 10.48))
        g.box("grey_metal", (0, y-.015, 10.51), (DOOR_WIDTH+.07, 1.56, .055))
    # Raised kick strip protects all four sides, kept outside the clear portal.
    side_kick_x = ROOM_WIDTH/2 - WALL_THICKNESS - .03
    for x in (-side_kick_x, side_kick_x):
        g.box(f["kick"], (x, 0, .56), (.08, ROOM_DEPTH, 1.12))
    for y in (-11.46, 11.46):
        side_width = (ROOM_WIDTH-DOOR_WIDTH)/2
        for x in (-(DOOR_WIDTH+side_width)/2, (DOOR_WIDTH+side_width)/2):
            g.box(f["kick"], (x, y, .56), (side_width, .08, 1.12))
    g.box("ceiling", (0, 0, 11.94), (ROOM_WIDTH, ROOM_DEPTH, .12))
    for x in (-6, 6):
        g.box("ceiling_grid", (x, 0, 11.867), (.055, ROOM_DEPTH, .045))
    # Trim the inner T-bars around the two 7.5-by-2.4 fluorescent housings.
    for x in (-2, 2):
        for y, length in ((-8.625, 6.75), (0, 5.5), (8.625, 6.75)):
            g.box("ceiling_grid", (x, y, 11.867), (.055, length, .045))
    for y in (-10, -6, -2, 2, 6, 10):
        g.box("ceiling_grid", (0, y, 11.867), (ROOM_WIDTH, .055, .045))
    if room_name == "RoomKitchenPrep":
        # Drain and scuffed threshold pick up the institutional tile texture.
        g.box("black_metal", (0, 1.2, .014), (.38, .38, .012))
        for x in (-.09, 0, .09):
            g.box("grey_metal", (x, 1.2, .023), (.025, .30, .008))
    elif room_name == "RoomStaffNook":
        # Small red runner hints at the old party venue, away from the aisle.
        g.box("carpet_red", (-6.0, -7.0, .013), (2.0, 3.2, .012))
    return g


def _room_shell_collision():
    boxes = [((0, 0, -.50), (ROOM_WIDTH, ROOM_DEPTH, 1.0))]
    side_wall_x = ROOM_WIDTH/2 - WALL_THICKNESS/2
    for x in (-side_wall_x, side_wall_x):
        boxes.append(((x, 0, 6.0), (WALL_THICKNESS, ROOM_DEPTH, ROOM_HEIGHT)))
    for y in (-11.25, 11.25):
        side_width = (ROOM_WIDTH-DOOR_WIDTH)/2
        for x in (-(DOOR_WIDTH+side_width)/2, (DOOR_WIDTH+side_width)/2):
            boxes.append(((x, y, 6.0), (side_width, WALL_THICKNESS, ROOM_HEIGHT)))
        boxes.append(((0, y, 11.25), (DOOR_WIDTH, WALL_THICKNESS, 1.5)))
    return boxes


def _instance(collection, asset, xyz, angle_degrees, source):
    obj = bpy.data.objects.new(asset + "__" + source.name[4:], None)
    collection.objects.link(obj)
    obj.instance_type = "COLLECTION"
    obj.instance_collection = source
    obj.location = xyz
    obj.rotation_euler.z = math.radians(angle_degrees)
    obj["l6_asset"] = asset
    obj["l6_role"] = "fixture_instance"
    obj["l6_child_asset"] = source.name[len(PREFIX):]
    return obj


def _transformed_box(center, size, xyz, angle_degrees):
    angle = math.radians(angle_degrees)
    c, s = math.cos(angle), math.sin(angle)
    x, y, z = center
    cx = xyz[0] + x*c-y*s
    cy = xyz[1] + x*s+y*c
    cz = xyz[2] + z
    # AABB is exact for the 0/90/180/270 degree fixtures used here.
    sx = abs(c)*size[0]+abs(s)*size[1]
    sy = abs(s)*size[0]+abs(c)*size[1]
    return ((cx, cy, cz), (sx, sy, size[2]))


def _room(helpers, parent, name, collections, materials):
    col = bpy.data.collections.new(PREFIX + name)
    parent.children.link(col)
    col["l6_asset"] = name
    col["l6_family"] = "back-service-room"
    col["l6_units"] = "studs"
    col["l6_forward"] = "-Y"
    col["l6_room_size_xyz"] = [ROOM_WIDTH, ROOM_DEPTH, ROOM_HEIGHT]
    col["l6_port_width"] = DOOR_WIDTH
    col["l6_port_height"] = DOOR_HEIGHT
    col["l6_floor_visual_separate"] = True
    helpers._create_mesh_objects(name, _room_geometry(helpers.Geometry, name),
                                 col, materials)
    collision = _room_shell_collision()
    for asset, xyz, angle in room_furnishings(name):
        _instance(col, name, xyz, angle, collections[asset])
        raw = PROP_COLLISION.get(asset, helpers.COLLIDERS.get(asset, ()))
        collision.extend(_transformed_box(center, size, xyz, angle)
                         for center, size in raw)
    for i, (center, size) in enumerate(collision):
        helpers._proxy(name, i, center, size, col)
    for x, y, label, normal in (
        (0, -ROOM_DEPTH/2, "JoinSouth", (0, -1, 0)),
        (0, ROOM_DEPTH/2, "JoinNorth", (0, 1, 0)),
    ):
        _anchor(col, name, label, (x, y, 0),
                l6_connection_normal_xyz=normal,
                l6_port_width=DOOR_WIDTH,
                l6_port_height=DOOR_HEIGHT)
    _anchor(col, name, "PlacementReference", (0, 0, 0))
    for y in (-4.0, 4.0):
        _instance(col, name, (0, y, 11.65), 0,
                  collections["FluorescentFrame"])
        _instance(col, name, (0, y, 11.48), 0,
                  collections["FluorescentDiffuser"])
    return col, collision


def build_revision_sections(materials, *, parent=None, existing=None):
    """Append new L6K props and furnished room modules; never replace a kit.

    ``materials`` maps material keys to bpy Material instances. ``parent`` is a
    collection or scene receiving a new ``L6_RevisionSections`` child. ``existing``
    may map unprefixed kit names to existing collections; otherwise they are
    found in bpy.data. The return dictionary has ``collections`` (new plus
    existing references), ``new_collections``, ``room_collisions``,
    ``room_furnishings``, and ``stats``. A caller owns UV remapping, export,
    scene placement, save, and any later Studio import.
    """
    if not isinstance(materials, dict):
        raise TypeError("materials must map Level 6 material keys to Blender materials")
    missing_materials = [key for key in REQUIRED_MATERIALS
                         if not isinstance(materials.get(key), bpy.types.Material)]
    if missing_materials:
        raise ValueError("Missing Level 6 materials: " + ", ".join(missing_materials))
    existing = dict(existing or {})
    for name in REQUIRED_EXISTING:
        existing.setdefault(name, bpy.data.collections.get(PREFIX + name))
    missing_assets = [name for name in REQUIRED_EXISTING
                      if not isinstance(existing.get(name), bpy.types.Collection)]
    if missing_assets:
        raise ValueError("Build the existing Level 6 kit first: " +
                         ", ".join(missing_assets))
    target_names = [PREFIX + name for name in NEW_PROPS + NEW_ROOMS]
    collisions = [name for name in target_names if bpy.data.collections.get(name)]
    if bpy.data.collections.get("L6_RevisionSections"):
        collisions.append("L6_RevisionSections")
    if collisions:
        raise ValueError("Refusing to overwrite existing collections: " +
                         ", ".join(collisions))
    if parent is None:
        parent = bpy.context.scene.collection
    elif isinstance(parent, bpy.types.Scene):
        parent = parent.collection
    if not isinstance(parent, bpy.types.Collection):
        raise TypeError("parent must be a Blender scene or collection")

    helpers = _prop_module()
    library = bpy.data.collections.new("L6_RevisionSections")
    parent.children.link(library)
    collections = dict(existing)
    new = {}
    for name in NEW_PROPS:
        new[name] = _make_asset(helpers, library, name,
                                PROP_BUILDERS[name](helpers.Geometry), materials,
                                PROP_COLLISION[name], PROP_ANCHORS.get(name))
        collections[name] = new[name]
    room_collisions = {}
    for name in NEW_ROOMS:
        new[name], room_collisions[name] = _room(
            helpers, library, name, collections, materials)
        collections[name] = new[name]

    triangles = {}
    visual_objects = {}
    for name, col in new.items():
        visuals = [obj for obj in col.objects
                   if obj.type == "MESH" and obj.get("l6_role") == "visual"]
        visual_objects[name] = len(visuals)
        triangles[name] = sum(sum(len(poly.vertices)-2 for poly in obj.data.polygons)
                              for obj in visuals)
    return {
        "library": library,
        "collections": collections,
        "new_collections": new,
        "room_collisions": room_collisions,
        "room_furnishings": {name: room_furnishings(name) for name in NEW_ROOMS},
        "stats": {
            "new_prefabs": len(NEW_PROPS),
            "new_rooms": len(NEW_ROOMS),
            "triangles_by_collection": triangles,
            "unique_visual_triangles": sum(triangles.values()),
            "visual_objects_by_collection": visual_objects,
            "room_collision_boxes": {name: len(boxes)
                                     for name, boxes in room_collisions.items()},
        },
    }


run = build_revision_sections
