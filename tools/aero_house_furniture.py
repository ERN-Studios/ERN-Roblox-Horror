"""Compact, hand-authored furnishings for the Frutiger Aero house.

Called by the house builder with its mesh/collider helper API.  Coordinates are
Roblox-sized Blender units with Z up.  No scene clearing, export, or global scene
settings happen here.  The intentionally broad, clean forms provide detail at
avatar distance without dense upholstery, subdivision, or texture dependencies.
"""

from math import cos, sin, tau


def build_furniture(api):
    """Add room-local furniture, approximate colliders, and three small plants."""

    def box(name, c, d, mat, bevel=0.15, segments=2):
        return api.box(name, c, d, mat, bevel=bevel, segments=segments)

    def cyl(name, c, r, h, mat, n=20, r2=None):
        return api.cylinder(name, c, r, h, mat, n=n, r2=r2)

    def collision(name, c, d):
        api.collider(name, c, d)

    def sofa(room, x, y, floor, width=17, fabric="FabricCyan"):
        """A three-seat sofa facing negative Y; a slim contrasting shell."""
        stem = room + "__Sofa"
        box(stem + "Plinth", (x, y, floor + .30),
            (width - 1.1, 4.55, .6), "Navy", .18, 1)
        box(stem + "Shell", (x, y, floor + 1.25),
            (width, 5.2, 1.55), "Pearl", .58, 3)
        box(stem + "Back", (x, y + 2.00, floor + 3.05),
            (width - .20, 1.05, 3.25), fabric, .48, 3)
        for i, sx in enumerate((-1, 1)):
            box(stem + "Arm" + str(i), (x + sx * (width / 2 - .58), y, floor + 2.45),
                (1.16, 4.9, 2.25), fabric, .5, 3)
        cushion_w = (width - 2.65) / 3
        for i in range(3):
            box(stem + "Seat" + str(i),
                (x + (i - 1) * (cushion_w + .10), y - .35, floor + 2.18),
                (cushion_w, 3.55, .85), fabric, .32, 2)
        for i, sx in enumerate((-1, 1)):
            box(stem + "Pillow" + str(i),
                (x + sx * width * .29, y + .70, floor + 3.23),
                (2.20, .78, 1.72), "FabricWhite", .32, 3)
        collision(stem, (x, y, floor + 2.1), (width, 5.2, 4.2))

    def chair(room, label, x, y, floor, fabric="FabricLime", facing=1, width=3.6):
        """Pedestal chair.  Facing is +1/-1 Y, or +2/-2 X."""
        stem = room + "__" + label
        axis_x = abs(facing) == 2
        direction = 1 if facing > 0 else -1
        cyl(stem + "Foot", (x, y, floor + .18), width * .33, .32, "White", 16)
        cyl(stem + "Stem", (x, y, floor + 1.25), .22, 2.0, "Chrome", 12)
        seat_dim = (3.1, width, .72) if axis_x else (width, 3.1, .72)
        box(stem + "Seat", (x, y, floor + 2.2), seat_dim, fabric, .32, 2)
        back_pos = (x - direction * 1.24, y, floor + 3.38) if axis_x else (
            x, y - direction * 1.24, floor + 3.38)
        back_dim = (.63, width, 2.35) if axis_x else (width, .63, 2.35)
        box(stem + "Back", back_pos, back_dim, fabric, .30, 2)
        collision(stem, (x, y, floor + 2.4),
                  (3.3, width, 4.8) if axis_x else (width, 3.3, 4.8))

    def side_table(room, label, x, y, floor, color="Lime"):
        stem = room + "__" + label
        cyl(stem + "Foot", (x, y, floor + .18), .78, .25, color, 16)
        cyl(stem + "Column", (x, y, floor + 1.45), .16, 2.5, color, 12)
        cyl(stem + "Top", (x, y, floor + 2.85), 1.10, .24, color, 24)
        collision(stem, (x, y, floor + 1.5), (2.2, 2.2, 3))

    def bed(room, x, y, floor, color, width=10.2, length=8.0):
        stem = room + "__Bed"
        box(stem + "ShadowBase", (x, y, floor + .32),
            (width - .9, length - .7, .55), "Navy", .2, 1)
        box(stem + "Platform", (x, y, floor + 1),
            (width + .45, length + .35, 1.05), color, .5, 3)
        box(stem + "Mattress", (x, y, floor + 1.91),
            (width, length, 1), "FabricWhite", .4, 3)
        box(stem + "Duvet", (x, y - .85, floor + 2.47),
            (width + .03, length - 2.2, .36), "FabricWhite", .15, 2)
        box(stem + "Runner", (x, y - length * .29, floor + 2.69),
            (width + .08, 1.6, .12), color, .04, 1)
        box(stem + "Headboard", (x, y + length / 2 - .15, floor + 2.82),
            (width + .35, .65, 4.25), color, .3, 3)
        for i, sx in enumerate((-1, 1)):
            box(stem + "Pillow" + str(i), (x + sx * width * .245, y + length * .30, floor + 2.63),
                (width * .42, 1.72, .50), "FabricWhite", .23, 3)
            nx = x + sx * (width / 2 + 1.6)
            box(stem + "Bedside" + str(i), (nx, y + 2.2, floor + 1.4),
                (2.2, 2.15, 2.65), "White", .38, 2)
            box(stem + "BedsideInset" + str(i), (nx, y + 1.108, floor + 1.45),
                (1.42, .07, .09), color, .025, 1)
            collision(stem + "Bedside" + str(i),
                      (nx, y + 2.2, floor + 1.4), (2.2, 2.15, 2.8))
        collision(stem, (x, y, floor + 1.5), (width + .45, length + .35, 3.0))
        collision(stem + "Headboard", (x, y + length / 2 - .15, floor + 2.82),
                  (width + .35, .65, 4.25))

    def plant(room, label, x, y, floor, height=6):
        """Seven low-resolution sculpted leaves; about 590 triangles per pot."""
        stem = room + "__" + label
        cyl(stem + "Pot", (x, y, floor + .88), .82, 1.76, "Pearl", 16, r2=1.08)
        cyl(stem + "Soil", (x, y, floor + 1.76), .98, .10, "Navy", 16)
        api.tube(stem + "Stalk", [(x, y, floor + 1.7), (x + .10, y, floor + height - .9)],
                 .08, "Leaf", sides=5)
        for i in range(7):
            a = i * tau / 7 + .3
            level = floor + 2.8 + (i % 3) * .78
            radius = .76 if i % 2 else .98
            lx, ly = x + cos(a) * radius, y + sin(a) * radius
            api.tube(stem + "Branch" + str(i),
                     [(x, y, level - .52), (lx, ly, level + .12)], .045, "Leaf", sides=4)
            api.sphere(stem + "Leaf" + str(i), (lx, ly, level + .50),
                       (.32, .46, .96), "Leaf" if i % 2 else "Lime", segments=8, rings=4)
        collision(stem + "Pot", (x, y, floor + .90), (2.16, 2.16, 1.8))

    # Main double-height lounge.  The seating turns toward the entrance glazing.
    sofa("Lounge", -29.5, -4.0, 1.0, width=20.0)
    chair("Lounge", "EasyChairA", -36.8, -23.5, 1, "FabricWhite", facing=1, width=4.7)
    chair("Lounge", "EasyChairB", -22.3, -23.5, 1, "FabricCyan", facing=1, width=4.7)
    cyl("Lounge__CoffeePedestal", (-29.5, -14.3, 2.1), 1.45, 1.8, "Aqua", 24, r2=.9)
    box("Lounge__CoffeeTop", (-29.5, -14.3, 3.17), (10.2, 5.3, .48), "White", .23, 3)
    box("Lounge__CoffeeInset", (-29.5, -14.3, 3.425), (6.7, 2.55, .035), "Cyan", .015, 1)
    collision("Lounge__CoffeeTable", (-29.5, -14.3, 2.3), (10.2, 5.3, 2.6))
    side_table("Lounge", "EndTable", -38.6, -14.5, 1, "Lime")
    plant("Lounge", "Palm", -18.3, -24, 1, 6.2)

    # Kitchen cabinet bodies are joined visually by a thick, soft-edged worktop.
    box("Kitchen__Plinth", (26.2, -11.4, 1.28), (13.4, 3.7, .55), "Navy", .15, 1)
    box("Kitchen__CabinetBank", (26.2, -11.4, 3.0), (13.4, 4.0, 3.2), "White", .25, 2)
    for i in range(5):
        x = 20.95 + i * 2.63
        box("Kitchen__Door" + str(i), (x, -13.445, 3.0), (2.51, .16, 2.88),
            "Lime" if i < 2 else "White", .075, 1)
        box("Kitchen__Pull" + str(i), (x, -13.555, 4.04), (1.00, .10, .10), "Chrome", .025, 1)
    box("Kitchen__Worktop", (26.2, -11.4, 4.77), (13.7, 4.3, .48), "Pearl", .22, 3)
    box("Kitchen__DrySinkInset", (22.45, -11.25, 5.027), (3.35, 2.1, .055), "Chrome", .027, 1)
    box("Kitchen__DrySinkWell", (22.45, -11.25, 5.066), (2.82, 1.65, .040), "Aqua", .019, 1)
    api.tube("Kitchen__Faucet", [(22.45, -10.06, 5.0), (22.45, -10.06, 6.12),
                               (22.45, -10.75, 6.30), (22.45, -11.15, 6.03)],
             .12, "Chrome", sides=8)
    box("Kitchen__Hob", (29.10, -11.4, 5.04), (3.4, 2.72, .065), "Navy", .032, 1)
    for i, (dx, dy) in enumerate(((-.8, -.66), (.8, -.66), (-.8, .66), (.8, .66))):
        cyl("Kitchen__Burner" + str(i), (29.1 + dx, -11.4 + dy, 5.09), .50, .028, "Chrome", 16)
    collision("Kitchen__Cabinets", (26.2, -11.4, 3.0), (13.7, 4.3, 4.0))
    box("Kitchen__FridgeBody", (37.05, -11.6, 5.4), (4.9, 4.3, 8.7), "Pearl", .45, 3)
    for label, z, h in (("Upper", 7.5, 4.2), ("Lower", 3.2, 4.0)):
        box("Kitchen__Fridge" + label, (37.05, -13.83, z), (4.48, .20, h), "Cyan", .09, 2)
        box("Kitchen__FridgePull" + label, (35.65, -14.04, z), (.12, .25, 1.40), "Chrome", .055, 2)
    collision("Kitchen__Fridge", (37.05, -11.6, 5.4), (4.9, 4.6, 8.8))

    # Four generous chairs around a compact rounded dining table.
    cyl("Dining__TableBase", (28.3, -21.0, 1.2), 2.2, .3, "White", 24)
    cyl("Dining__TablePedestal", (28.3, -21.0, 2.8), .65, 3.1, "Cyan", 20, r2=1.0)
    box("Dining__TableTop", (28.3, -21.0, 4.5), (8.5, 4.45, .55), "White", .27, 3)
    collision("Dining__Table", (28.3, -21, 2.9), (8.5, 4.45, 3.8))
    chair("Dining", "ChairWest", 21.7, -21.0, 1, facing=2, width=3.3)
    chair("Dining", "ChairEast", 34.9, -21.0, 1, facing=-2, width=3.3)
    chair("Dining", "ChairFront", 28.3, -25.0, 1, facing=1, width=3.3)
    chair("Dining", "ChairRear", 28.3, -16.2, 1, facing=-1, width=3.3)

    # Three bedrooms use the same economical furniture family in different colors.
    bed("GuestBedroom", -31, 26.8, 1, "Cyan")
    bed("UpperCyanBedroom", -31, 31, 18, "Aqua")
    bed("UpperLimeBedroom", 31, 31, 18, "Lime", width=9.5)
    plant("UpperCyanBedroom", "Plant", -21.4, 24.1, 18, 5.8)

    # Dry, minimal bathroom fixtures; no water mesh, liquid, or animated effects.
    box("Bathroom__Vanity", (-3.5, 29.3, 2.65), (4.5, 3.1, 3.3), "White", .35, 3)
    box("Bathroom__VanityDrawer", (-3.5, 27.70, 2.6), (3.93, .14, 2.48), "Aqua", .065, 1)
    box("Bathroom__DrawerPull", (-3.5, 27.585, 3.43), (1.1, .12, .10), "Chrome", .045, 1)
    box("Bathroom__VanityTop", (-3.5, 29.3, 4.44), (4.75, 3.3, .36), "Pearl", .17, 2)
    box("Bathroom__DryBasin", (-3.5, 29.0, 4.655), (2.8, 1.88, .06), "Aqua", .025, 1)
    api.tube("Bathroom__Faucet", [(-3.5, 30.27, 4.6), (-3.5, 30.27, 5.35),
                                (-3.5, 29.58, 5.35)], .09, "Chrome", sides=8)
    box("Bathroom__MirrorFrame", (-3.5, 30.95, 7.0), (4.6, .35, 4.0), "White", .17, 3)
    box("Bathroom__Mirror", (-3.5, 30.754, 7.0), (4.0, .06, 3.40), "Chrome", .029, 1)
    collision("Bathroom__Vanity", (-3.5, 29.3, 2.85), (4.75, 3.3, 3.7))
    cyl("Bathroom__ToiletPedestal", (2.4, 28.8, 1.75), .68, 1.5, "Pearl", 16, r2=.83)
    api.sphere("Bathroom__ToiletBowl", (2.4, 28.7, 2.72), (1.05, 1.35, .68), "White", segments=16, rings=8)
    box("Bathroom__ToiletClosedLid", (2.4, 28.48, 3.28), (1.87, 2.25, .18), "Pearl", .085, 2)
    box("Bathroom__ToiletTank", (2.4, 30.09, 3.43), (2.0, .84, 2.3), "White", .35, 3)
    cyl("Bathroom__FlushButton", (2.4, 30.09, 4.63), .16, .035, "Chrome", 12)
    collision("Bathroom__Toilet", (2.4, 29.0, 2.85), (2.1, 3.1, 3.7))

    # A cheerful translucent-color desktop evokes early home computers by shape.
    box("Study__Desktop", (32, 28.7, 5.0), (11.8, 3.9, .60), "Pearl", .29, 3)
    for i, x in enumerate((27.6, 36.4)):
        box("Study__DeskPedestal" + str(i), (x, 28.7, 2.9), (1.35, 3.2, 3.7), "Cyan", .45, 3)
    box("Study__MonitorFoot", (32.9, 28.6, 5.46), (2.2, 1.6, .23), "White", .11, 2)
    box("Study__MonitorStand", (32.9, 28.9, 6.15), (.60, .65, 1.25), "Chrome", .18, 2)
    box("Study__ComputerShell", (32.9, 29.0, 7.72), (4.45, 1.55, 3.36), "Aqua", .55, 3)
    box("Study__ComputerScreen", (32.9, 28.185, 7.78), (3.65, .085, 2.56), "Navy", .04, 1)
    box("Study__ScreenGlow", (32.9, 28.130, 7.91), (3.35, .03, 2.22), "Cyan", .014, 1)
    box("Study__Keyboard", (32.55, 27.43, 5.43), (3.40, .95, .18), "White", .085, 2)
    for i in range(3):
        box("Study__KeyRow" + str(i), (32.55, 27.16 + i * .22, 5.535),
            (2.90, .12, .035), "Aqua", .016, 1)
    api.sphere("Study__Mouse", (35.1, 27.45, 5.47), (.32, .49, .15), "Lime", segments=12, rings=6)
    chair("Study", "DeskChair", 32, 24.0, 1, "FabricCyan", facing=1, width=3.8)
    collision("Study__Desk", (32, 28.7, 3.0), (11.8, 3.9, 4.7))
    plant("Study", "Plant", 26.1, 23.8, 1, 5.8)

    sofa("UpperReading", 31, -14.6, 18, width=14.6, fabric="FabricLime")
    cyl("UpperReading__TableColumn", (31, -22.0, 19.15), .58, 2, "Cyan", 16)
    box("UpperReading__TableTop", (31, -22, 20.35), (6.4, 3.4, .44), "White", .21, 3)
    collision("UpperReading__Table", (31, -22, 19.4), (6.4, 3.4, 2.8))
    side_table("UpperReading", "SideTable", 38.5, -21.3, 18, "Cyan")

    # Slim wardrobes stay at bedroom edges, leaving the door-to-bed routes open.
    # Broad sliding panels provide the Aero color without modeled drawer hardware.
    for room, x, y, floor, accent in (
            ("GuestBedroom", -47.4, 26.8, 1, "Cyan"),
            ("UpperCyanBedroom", -47.4, 28.0, 18, "Aqua"),
            ("UpperLimeBedroom", 47.4, 28.0, 18, "Lime")):
        stem = room + "__Wardrobe"
        front = 1 if x < 0 else -1
        box(stem + "Body", (x, y, floor + 4.7), (3.5, 8.0, 9.4), "White", .28, 1)
        box(stem + "ShadowFoot", (x, y, floor + .22), (3.2, 7.7, .44), "Navy", .12, 1)
        for i, offset in enumerate((-1.93, 1.93)):
            px = x + front * (1.78 + i * .045)
            box(stem + "SlidingPanel" + str(i), (px, y + offset, floor + 4.82),
                (.12, 3.72, 8.63), accent if i == 0 else "Pearl", .05, 1)
            box(stem + "RecessedPull" + str(i),
                (px + front * .078, y + offset + .92, floor + 4.55),
                (.06, .10, 1.12), "Chrome", .02, 1)
        collision(stem, (x, y, floor + 4.7), (3.8, 8.0, 9.4))

    # A low console faces the existing lounge sofa; the entrance remains clear.
    box("Lounge__MediaShadowFoot", (-29.5, -35.8, 1.23), (13.4, 2.55, .44), "Navy", .10, 1)
    box("Lounge__MediaConsole", (-29.5, -35.8, 2.44), (14, 2.95, 2.45), "White", .30, 2)
    for i, dx in enumerate((-4.55, 0, 4.55)):
        box("Lounge__MediaPanel" + str(i), (-29.5 + dx, -34.28, 2.45),
            (4.35, .12, 1.83), "Aqua" if i == 1 else "Pearl", .055, 1)
    box("Lounge__TVFoot", (-29.5, -35.7, 3.79), (3.6, 1.5, .25), "Cyan", .12, 1)
    box("Lounge__TVStem", (-29.5, -35.75, 4.28), (.7, .58, 1.0), "White", .15, 1)
    box("Lounge__TVShell", (-29.5, -35.7, 6.55), (8.4, .86, 4.7), "White", .36, 2)
    box("Lounge__TVScreen", (-29.5, -35.243, 6.58), (7.55, .075, 3.86), "Navy", .033, 1)
    box("Lounge__TVScreenReflection", (-29.5, -35.197, 7.87), (6.8, .025, .15), "Aqua", .01, 1)
    collision("Lounge__MediaConsole", (-29.5, -35.8, 2.44), (14, 2.95, 2.9))
    collision("Lounge__TV", (-29.5, -35.7, 6.55), (8.4, .86, 4.7))

    # Small open shelf beside the study desk, with a few simple book spines.
    box("Study__ShelfBack", (44.5, 26.0, 5.0), (.30, 6.5, 8.0), "Aqua", .12, 1)
    for i, y in enumerate((22.75, 29.25)):
        box("Study__ShelfSide" + str(i), (43.6, y, 5.0), (2.1, .30, 8.0), "White", .12, 1)
    for i, z in enumerate((1.20, 3.72, 6.23, 8.80)):
        box("Study__ShelfBoard" + str(i), (43.6, 26.0, z), (2.1, 6.5, .30), "White", .12, 1)
    for i, (y, h, color) in enumerate(((23.45, 1.64, "Lime"), (24.0, 1.85, "Cyan"),
                                      (24.54, 1.47, "Pearl"), (27.76, 1.67, "Cyan"))):
        box("Study__Book" + str(i), (43.50, y, 3.87 + h / 2),
            (1.30, .38, h), color, .035, 1)
    collision("Study__Shelf", (43.6, 26.0, 5.0), (2.3, 6.8, 8.0))

    # A quiet two-chair terrace group sits to the east of the balcony doorway.
    chair("TerraceFurniture", "ChairWest", 37.4, -49.4, 18,
          "FabricCyan", facing=2, width=3.6)
    chair("TerraceFurniture", "ChairEast", 45.0, -49.4, 18,
          "FabricLime", facing=-2, width=3.6)
    side_table("TerraceFurniture", "RoundTable", 41.2, -49.4, 18, "White")

    # Three thin accent pendants.  Root builder may extend these suspension rods.
    for room, x, y, z, radius, finish in (
            ("Lounge", -29.5, -14.3, 14.5, 5.2, "Cyan"),
            ("Dining", 28.3, -21.0, 11.5, 3.8, "Lime"),
            ("UpperReading", 31, -20, 28.5, 3.8, "Aqua")):
        api.ring(room + "__PendantFrame", (x, y, z), radius, .10, finish, n=40, sides=6)
        api.ring(room + "__PendantDiffuser", (x, y, z - .085), radius - .035, .047,
                 "Glow", n=40, sides=4)
        for i, direction in enumerate((-1, 1)):
            api.tube(room + "__PendantCord" + str(i),
                     [(x + direction * radius * .65, y, z + .08),
                      (x + direction * radius * .65, y, 34.5 if room == "Lounge" else (16.5 if room == "Dining" else 34.2))],
                     .025, "Chrome", sides=4)
