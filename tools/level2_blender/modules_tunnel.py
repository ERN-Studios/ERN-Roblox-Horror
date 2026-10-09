"""Job B: offline tunnel/passages. All construction coordinates are Roblox studs.

Run (one independent background process, never the owner's Blender):
  D:/Blender/blender.exe -b --factory-startup --python-exit-code 1 -P G:/Roblox/MongoTV/tools/level2_blender/modules_tunnel.py --

Parts use show=False: kit's show=True preview geometry otherwise also exports
as MeshParts. Reviews draw these records separately, after exporting.
"""
import sys
sys.dont_write_bytecode = True
import argparse
import hashlib
import json
import math
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import bpy
import bmesh
from mathutils import Vector
import kit

EXPORT = Path("G:/Blender/Level2_Pool/jobs/B/export")
REVIEW = Path("G:/Blender/Level2_Pool/review/B")
LENGTHS = (56, 64, 72, 80)
RADIUS, SCALE, CROWN = 14.1, 1.9, 32.0
SPRING = CROWN - RADIUS * SCALE
ANGLE = math.acos(12.1 / RADIUS)
HAUNCH = SPRING + RADIUS * SCALE * math.sin(ANGLE)
BAND_BOTTOM, BAND_TOP = 7.2, 7.2 + 1 / kit.S
COLLAR = 1.75
TRANSITION = 4.0


def part(m, name, center, size, mat, ground=False, collide=True):
    m.part(name, center, size, mat, ground=ground, collide=collide,
           attrs={"Level2_EntityGround": True} if ground else {}, show=False)


def tube(m, a, b, radius, mat="Steel", segments=8):
    """A capped low-poly cylinder along any Roblox-axis vector."""
    av, bv = kit.to_blender(a) / kit.S, kit.to_blender(b) / kit.S
    direction = bv - av
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments,
                         radius1=radius, radius2=radius, depth=direction.length)
    bmesh.ops.transform(bm, matrix=direction.to_track_quat("Z", "Y").to_matrix(), verts=list(bm.verts))
    bmesh.ops.translate(bm, vec=(av + bv) / 2, verts=list(bm.verts))
    m.absorb(bm, mat, smooth=True)


def sweep(m, profile, z0, z1, mat, uv=None, smooth=False):
    """Closed extrusion, including end caps, in the X/Y section."""
    n = len(profile)
    verts = [(x, y, z) for z in (z0, z1) for x, y in profile]
    faces = [(i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n)]
    faces += [tuple(reversed(range(n))), tuple(range(n, 2 * n))]
    m.raw(verts, faces, mat, uv=uv, smooth=smooth)


def bullnose(m, side, z0, z1, top=.45, mat="Terrazzo"):
    # The flat deck stops at x=9.35. This full-thickness rounded edge extends
    # to x=9.10; its top is tangent to the deck, not a coplanar overlay.
    profile = [(side * 9.35, top), (side * 9.35, top - .5)]
    profile += [(side * (9.35 - .25 * math.sin(t)), top - .25 - .25 * math.cos(t))
                for t in [math.pi * i / 8 for i in range(1, 8)]]
    sweep(m, profile, z0, z1, mat)


def lamp(m, side, z, y, wall_x, marker=False, segments=12):
    """Oval bulkhead: steel backplate, convex neon lens, actual cage bars."""
    x = side * (wall_x - .13)
    # Oval closed extrusions along X; the rim and lens have independent depth.
    for mat, depth, ry, rz, shift in (("Steel", .18, 1.05, .68, 0),
                                     ("LampGlow", .25, .87, .51, -.20)):
        xx = x + side * shift
        verts = [(xx + side * d, y + ry * math.cos(t), z + rz * math.sin(t))
                 for d in (-depth / 2, depth / 2)
                 for t in [2 * math.pi * i / segments for i in range(segments)]]
        faces = [(i, (i + 1) % segments, (i + 1) % segments + segments, i + segments)
                 for i in range(segments)]
        faces += [tuple(reversed(range(segments))), tuple(range(segments, 2 * segments))]
        m.raw(verts, faces, mat, smooth=True)
    cage_x = x - side * .43
    cage_segments = 4 if segments <= 8 else 6
    tube(m, (cage_x, y - .97, z), (cage_x, y + .97, z), .055, segments=cage_segments)
    for yy in (y - .46, y + .46):
        tube(m, (cage_x, yy, z - .55), (cage_x, yy, z + .55), .055, segments=cage_segments)
    # Small feet visibly connect the cage to the mounting plate.
    for yy in (y - .95, y + .95):
        tube(m, (cage_x, yy, z), (x, yy, z), .055, segments=cage_segments)
    if marker:
        m.marker("LampLight", (cage_x - side * .2, y, z),
                 instanceName="Level 2 Corridor Vault Light", lightType="PointLight",
                 brightness=.7, range=26, shadows=False)


def flight_span(length, rise):
    return min(length / 3, math.ceil(rise / .78) * 2.3) if rise else 0


def floor_height(z, length, rise):
    if not rise:
        return 0
    span = flight_span(length, rise)
    return rise * max(0.0, min(1.0, (z + span / 2) / span))


def floors(m, length, rise, width, mat, prefix):
    if not rise:
        part(m, prefix + " Floor", (0, -.6, 0), (width, 1.2, length), mat, ground=True)
        return
    n = math.ceil(rise / .78)
    span = flight_span(length, rise)
    run = span / n
    part(m, prefix + " Entry Landing", (0, -.6, -(length + span) / 4),
         (width, 1.2, (length - span) / 2), mat, ground=True)
    for i in range(n):
        h = min((i + 1) * .78, rise)
        z = -span / 2 + (i + .5) * run
        part(m, prefix + f" Step {i + 1:02}", (0, (h - 1.2) / 2, z),
             (width, h + 1.2, run), mat, ground=True)
        # Round only the exposed arris; flat treads stay native Parts.
        nose_y, nose_z = h - .07, z - run / 2 + .015
        profile = [(-.09, -.09), (.09, -.09), (.09, .00), (.045, .055), (-.045, .055), (-.09, .00)]
        verts = [(x, nose_y + py, nose_z + pz) for x in (-width / 2, width / 2) for pz, py in profile]
        nn = len(profile)
        faces = [(j, (j + 1) % nn, (j + 1) % nn + nn, j + nn) for j in range(nn)]
        faces += [tuple(reversed(range(nn))), tuple(range(nn, 2 * nn))]
        m.raw(verts, faces, "Terrazzo" if prefix.endswith("Corridor") else "Steel")
    part(m, prefix + " Exit Landing", (0, rise - .6, (length + span) / 4),
         (width, 1.2, (length - span) / 2), mat, ground=True)
    m.attrs.update(stepRise=.78, lastStepRise=round(rise - (n - 1) * .78, 6),
                   stepCount=n, stepRun=run, stepSpan=[-span / 2, span / 2])


def section(y_offset=0):
    # The certified rib-foot line is 12.1. Solid haunches fill the nominal
    # 34-stud shell behind it. The upper barrel is the specified 14.1 x 1.9 ellipse.
    return [(-12.1, -3 + y_offset)] + [
        (RADIUS * math.cos(t), SPRING + RADIUS * SCALE * math.sin(t) + y_offset)
        for t in [math.pi - ANGLE - (math.pi - 2 * ANGLE) * i / 28 for i in range(29)]
    ] + [(12.1, -3 + y_offset)]


def tunnel_shell(m, length, rise, raise_vault):
    # A collar has a genuinely rectangular clear 30x30 opening for 1.75 studs.
    # Short lofts behind it join the barrel without open spandrels or void seams.
    span = flight_span(length, rise) if rise else length / 3
    cuts = [-length / 2, -length / 2 + COLLAR,
            -length / 2 + COLLAR + TRANSITION, -span / 2, span / 2,
            length / 2 - COLLAR - TRANSITION, length / 2 - COLLAR, length / 2]
    cuts = sorted(set(cuts))
    contours = []
    roof_top = CROWN + (rise if raise_vault else 0) + 2
    for z in cuts:
        base = floor_height(z, length, rise)
        offset = base if raise_vault else 0
        curved = section(offset)
        mouth = abs(z) >= length / 2 - COLLAR - 1e-5
        if mouth:
            # Same topology as the barrel, but all upper points lie on the
            # flat lintel; the first/last two form vertical jambs.
            top = base + 30 if raise_vault else 30
            inner = [(-15, -3)] + [(-15 + 30 * i / 28, top) for i in range(29)] + [(15, -3)]
        else:
            inner = curved
            inner[0] = (-12.1, -3)
            inner[-1] = (12.1, -3)
        # Outer rectangle makes the whole vault watertight and supports a
        # single horizontal roof box even over the rising stair floor.
        contours.append(inner + [(17, -3), (17, roof_top), (-17, roof_top), (-17, -3)])
    def vault_uv(co, normal):
        # Along metres / meridian arc length, avoiding the box-projection
        # collapse at the crown. Linear interpolation follows the authored loft.
        z = -co.y / kit.S
        y = co.z / kit.S - (floor_height(z, length, rise) if raise_vault else 0)
        x = co.x / kit.S
        arc_span = RADIUS * SCALE * (math.pi - 2 * ANGLE)
        if y < HAUNCH:
            arc = y + 3 if x < 0 else 2 * (HAUNCH + 3) + arc_span - (y + 3)
        else:
            t = math.atan2((y - SPRING) / SCALE, x)
            arc = HAUNCH + 3 + RADIUS * SCALE * (math.pi - ANGLE - t)
        return -co.y, arc * kit.S

    def loft(zs, profiles):
        n = len(profiles[0])
        verts = [(x, y, z) for z, profile in zip(zs, profiles) for x, y in profile]
        faces = [(j * n + i, j * n + (i + 1) % n,
                  (j + 1) * n + (i + 1) % n, (j + 1) * n + i)
                 for j in range(len(zs) - 1) for i in range(n)]
        faces += [tuple(reversed(range(n))), tuple((len(zs) - 1) * n + i for i in range(n))]
        m.raw(verts, faces, "Tile", uv=vault_uv)

    # The collar/transition is a shaped closed feature. Long flat body walls
    # remain native Parts, while only the upper curved barrel becomes a mesh.
    loft(cuts[:3], contours[:3])
    loft(cuts[-3:], contours[-3:])
    body_cuts = cuts[2:-2]
    upper = []
    for z in body_cuts:
        offset = floor_height(z, length, rise) if raise_vault else 0
        upper.append(section(offset)[1:-1] + [(17, HAUNCH + offset), (17, roof_top),
                                              (-17, roof_top), (-17, HAUNCH + offset)])
    loft(body_cuts, upper)
    body_end = length / 2 - COLLAR - TRANSITION
    for side in (-1, 1):
        wall_top = HAUNCH + (rise if raise_vault else 0)
        part(m, f"Level 2 Corridor Haunch Wall {side:+}",
             (side * (12.1 + 17) / 2, (wall_top - 3) / 2, 0),
             (17 - 12.1, wall_top + 3, 2 * body_end), "Tile")
        # One Bands chunk, with v exactly 0..1 over one metre of wall height.
        band_profiles = []
        for z in body_cuts:
            offset = floor_height(z, length, rise) if raise_vault else 0
            band_profiles.append([(side * x, y + offset) for x, y in
                                  ((12.02, BAND_BOTTOM), (12.02, BAND_TOP),
                                   (12.10, BAND_TOP), (12.10, BAND_BOTTOM))])
        n = 4
        verts = [(x, y, z) for z, profile in zip(body_cuts, band_profiles) for x, y in profile]
        faces = [(j * n + i, j * n + (i + 1) % n,
                  (j + 1) * n + (i + 1) % n, (j + 1) * n + i)
                 for j in range(len(body_cuts) - 1) for i in range(n)]
        faces += [tuple(reversed(range(n))), tuple((len(body_cuts) - 1) * n + i for i in range(n))]
        def stair_band_uv(co, normal):
            offset = floor_height(-co.y / kit.S, length, rise) if raise_vault else 0
            return -co.y, (co.z / kit.S - offset - BAND_BOTTOM) / (BAND_TOP - BAND_BOTTOM)
        m.raw(verts, faces, "Bands", uv=stair_band_uv)
        # Low tiled skirting with a real bevel where the deck light catches it.
        m.box((side * 12.03, .9, 0), (.12, .7, 2 * body_end), "Tile", bevel=.04)
        # Three stepped backstops per side, wholly contained in the solid haunch.
        # No boxes enter either clear mouth or its rectangular collar.
        for i, (lo, hi, inner) in enumerate(((-3, 10, 12.1), (10, 22, 12.1), (22, 32, 11.05))):
            if raise_vault and i >= 1:
                hi += rise
            if raise_vault and i == 2:
                lo += rise
            m.collider(f"Level 2 Corridor Side {side:+} {i + 1}",
                       (side * (inner + 17) / 2, (lo + hi) / 2, 0),
                       (17 - inner, hi - lo, 2 * body_end))
    roof_bottom = CROWN + (rise if raise_vault else 0)
    # The shaped collar is visual only. Keep a continuous collision face behind
    # it without entering the 30-stud clear mouth (inner faces at x=+/-15.25).
    for side in (-1, 1):
        m.collider(f"Level 2 Corridor Shell Backstop {side:+}",
                   (side * 16.125, (roof_bottom - 3) / 2, 0),
                   (1.75, roof_bottom + 3, length))
    m.collider("Level 2 Corridor Roof Collider", (0, roof_bottom + 1, 0),
               (34, 2, length), attrs={"Level2_NoEntityGround": True})


def tunnel(variant, length, raise_vault=True):
    rise = 4 if variant == "Stair4" else 8 if variant == "Stair8" else 0
    wet = variant in ("Wet", "Drain", "Kids")
    depth = 1.8 if variant == "Drain" else 1.5
    m = kit.Mesh(f"Tunnel_{variant}_{length}", kind="Tunnel", variant=variant, length=length,
                 width=34, ribClearWidth=24.2, mouthClearWidth=30,
                 mouthClearHeight=30 if raise_vault else 30 - rise,
                 fromY=0, toY=rise, vaultRadius=RADIUS, vaultVerticalScale=SCALE,
                 collarDepth=COLLAR, transitionLength=TRANSITION,
                 meshCanCollide=False, meshCanQuery=False, meshCanTouch=False,
                 stairVaultRaised=bool(rise and raise_vault))
    tunnel_shell(m, length, rise, raise_vault)
    if wet:
        part(m, "Level 2 Corridor Water Floor", (0, -depth - .6, 0),
             (34, 1.2, length), "Rubber" if variant == "Kids" else "Mosaic", ground=True)
        for side in (-1, 1):
            bottom = -depth - .3
            part(m, f"Level 2 Corridor Side Ledge {side:+}",
                 (side * (9.35 + 15.4) / 2, (.45 + bottom) / 2, 0),
                 (15.4 - 9.35, .45 - bottom, length),
                 "Terrazzo", ground=True)
            bullnose(m, side, -length / 2, length / 2)
            m.collider(f"Level 2 Corridor Bullnose Support {side:+}",
                       (side * 9.225, (.20 + bottom) / 2, 0),
                       (.25, .20 - bottom, length), ground=True,
                       attrs={"Level2_EntityGround": True})
            # Native submerged curb, 1.2 wide, as in the existing envelope.
            part(m, f"Level 2 Corridor Submerged Curb {side:+}",
                 (side * 8.5, (-.8 + bottom) / 2, 0),
                 (1.2, -.8 - bottom, length), "Mosaic", ground=True)
            # Rounded curb arris is shaped mosaic geometry.
            m.cylinder((side * 7.9, -.86, 0), .06, length, "Mosaic", segments=8, axis="Z")
        for x in (-3.15, 3.15):
            m.box((x, -depth + .016, 0), (.42, .024, length), "Cobalt", bevel=0)
        m.attrs["waterRegion"] = {"center": [0, (.1 - depth) / 2, 0],
                                  "size": [18.2, depth + .1, length], "surfaceY": .1,
                                  "terrainOnly": True, "drainable": variant == "Drain"}
    else:
        floors(m, length, rise, 34, "Terrazzo", "Level 2 Corridor")
    for side, z in ((-1, -length / 4), (1, length / 4)):
        lamp(m, side, z, 13 + (floor_height(z, length, rise) if raise_vault else 0), 12.1,
             marker=side == -1)
    # Explicit mouth sockets, no review camera markers.
    m.marker("MouthFrom", (0, 0, -length / 2), yaw=180, clearWidth=30, clearHeight=30)
    m.marker("MouthTo", (0, rise, length / 2), clearWidth=30,
             clearHeight=30 if raise_vault else 30 - rise)
    m.finish()


def passage(variant, length):
    rise = 4 if variant == "Stair4" else 0
    m = kit.Mesh(f"Passage_{variant}_{length}", kind="Narrow", width=12, clearWidth=11,
                 clearHeight=16, length=length, fromY=0, toY=rise,
                 meshCanCollide=False, meshCanQuery=False, meshCanTouch=False)
    floors(m, length, rise, 11, "Service", "Level 2 Passage")
    # One native slab per side, and one overhead slab; a raised passage keeps
    # at least 16 studs above its high landing rather than blocking the far door.
    height = 16 + rise
    for side in (-1, 1):
        part(m, f"Level 2 Passage Wall {side:+}", (side * 5.75, (height - 1.2) / 2, 0),
             (.5, height + 1.2, length), "Service")
    part(m, "Level 2 Overhead Service Slab", (0, height + .25, 0),
         (12, .5, length), "Service", collide=False)
    m.collider("Level 2 Passage Roof Collider", (0, height + .25, 0),
               (12, .5, length), attrs={"Level2_NoEntityGround": True})
    # Floor strip: a thin steel frame, with recessed dark slots, no floating grille.
    span = flight_span(length, rise)
    for z0, z1, y in [(-length / 2, -span / 2 if rise else length / 2, 0)] + (
            [(span / 2, length / 2, rise)] if rise else []):
        part(m, f"Level 2 Passage Drain Recess {z0:g}", (0, y + .006, (z0 + z1) / 2),
             (.65, .012, z1 - z0), "ServiceGrey", collide=False)
        for x in (-.34, .34):
            m.box((x, y + .025, (z0 + z1) / 2), (.06, .04, z1 - z0), "Steel", bevel=0)
        for j in range(max(1, math.ceil((z1 - z0) / 2.4))):
            z = z0 + (j + .5) * (z1 - z0) / math.ceil((z1 - z0) / 2.4)
            m.box((0, y + .028, z), (.64, .045, .12), "Steel", bevel=0)
    # Two pipe runs, connectors and wall brackets share one Steel chunk.
    for x, y, radius in ((-4.75, height - 1.55, .22), (-3.90, height - 1.30, .15)):
        tube(m, (x, y, -length / 2), (x, y, length / 2), radius, segments=6)
        for z in (-length / 3, 0, length / 3):
            m.cylinder((x, y, z), radius + .075, .16, "Steel", segments=6, axis="Z")
            m.box((-4.68, y - .40, z), (1.65, .08, .20), "Steel", bevel=0)
    # Open ladder tray, with actual rungs and suspended fixing rods.
    for x in (1.25, 2.75):
        m.box((x, height - 1.0, 0), (.10, .26, length), "Steel", bevel=0)
    for j in range(math.ceil(length / 6)):
        z = -length / 2 + (j + .5) * length / math.ceil(length / 6)
        m.box((2, height - 1.07, z), (1.50, .09, .10), "Steel", bevel=0)
    for z in (-length / 3, length / 3):
        for x in (1.25, 2.75):
            tube(m, (x, height - .85, z), (x, height, z), .045, segments=6)
    lamps = max(1, math.ceil(length / 24))
    for i in range(lamps):
        z = -length / 2 + (i + .5) * length / lamps
        lamp(m, 1, z, 10.0 + floor_height(z, length, rise), 5.5, marker=i == 0, segments=8)
    m.attrs["lampCount"] = lamps
    m.marker("MouthFrom", (0, 0, -length / 2), yaw=180, clearWidth=11, clearHeight=16)
    m.marker("MouthTo", (0, rise, length / 2), clearWidth=11, clearHeight=16)
    m.finish()


def build(raise_stair_vault=True):
    """Register the 24 tunnel and nine passage components with kit.COMPONENTS."""
    for variant in ("Wet", "Drain", "Dry", "Stair4", "Stair8", "Kids"):
        for length in LENGTHS:
            tunnel(variant, length, raise_stair_vault)
    for length in (16, 24, 32, 48, 64, 80):
        passage("Flat", length)
    for length in (32, 48, 64):
        passage("Stair4", length)


def verify():
    rows = []
    for name, info in kit.COMPONENTS.items():
        mesh = info["mesh"]
        mesh.calc_loop_triangles()
        tris = len(mesh.loop_triangles)
        budget = 3000 if name.startswith("Tunnel_") else 1500
        visual_tris = tris + 12 * len(info["parts"])
        assert 0 < visual_tris <= budget, (name, visual_tris, budget)
        mats = {t.material_index for t in mesh.loop_triangles}
        assert len(mats) <= (7 if name.startswith("Tunnel_") else 3), (name, len(mats))
        assert all(t.area > 1e-10 for t in mesh.loop_triangles), (name, "degenerate face")
        assert all(math.isfinite(v) for p in mesh.vertices for v in p.co), name
        roofs = [r for r in info["parts"] + info["colliders"]
                 if any(s in r["name"] for s in ("Roof", "Ceiling", "Skylight"))]
        assert len(roofs) == 1 and roofs[0] in info["colliders"], name
        assert not roofs[0]["ground"]
        assert len([r for r in info["markers"] if r["name"] == "LampLight"]) == 1
        assert all(r["attrs"].get("Level2_EntityGround") for r in info["parts"] + info["colliders"] if r["ground"])
        if name.startswith("Tunnel_"):
            sides = [r for r in info["colliders"] if r["name"].startswith("Level 2 Corridor Side")]
            assert len(sides) == 6
            for side in (-1, 1):
                low = next(r for r in sides if r["name"] == f"Level 2 Corridor Side {side:+} 1")
                assert abs(abs(low["cf"][0]) - low["size"][0] / 2 - 12.1) < 1e-6
            assert sum(mesh.materials[i].name == "L2K_Bands" for i in mats) == 1
            idx = next(i for i, mat in enumerate(mesh.materials) if mat.name == "L2K_Bands")
            vs = [mesh.uv_layers.active.data[l].uv.y for t in mesh.loop_triangles
                  if t.material_index == idx for l in t.loops]
            assert min(vs) >= -1e-6 and max(vs) <= 1 + 1e-6, name
        # Verify winding/closed shaped solids without changing the foundation.
        bm = bmesh.new(); bm.from_mesh(mesh)
        assert all(e.is_manifold for e in bm.edges), (name, "open mesh edge")
        pending = set(bm.faces)
        while pending:
            first = pending.pop()
            island, stack = [first], [first]
            while stack:
                face = stack.pop()
                for edge in face.edges:
                    for adjacent in edge.link_faces:
                        if adjacent in pending:
                            pending.remove(adjacent); stack.append(adjacent); island.append(adjacent)
            # Signed tetrahedra work for the concave end caps, too. Validate
            # every disconnected solid, so a positive aggregate cannot hide a flip.
            volume6 = 0
            for face in island:
                vs = [v.co for v in face.verts]
                volume6 += sum(vs[0].dot(vs[i].cross(vs[i + 1])) for i in range(1, len(vs) - 1))
            assert volume6 > 1e-10, (name, "inward shaped solid", volume6)
        bm.free()
        row = {"name": name, "chunks": len(mats), "tris": tris, "budget": budget,
               "visualTrisIncludingNativeParts": visual_tris,
               "parts": len(info["parts"]), "colliders": len(info["colliders"])}
        rows.append(row)
        print(f"{name} / {len(mats)} chunks / {tris} tris", flush=True)
    assert len(rows) == 33
    return rows


def review_record(col, record, label="ReviewPart"):
    # Use the foundation's UV/material handling, but do not register/export reviews.
    tmp = kit.Mesh(label)
    tmp.box(record["cf"][:3], record["size"], record["material"], bevel=0)
    tmp.finish()
    ob = kit.place(col, label)
    kit.COMPONENTS.pop(label)
    ob.name = record["name"]
    ob["review_only"] = True
    return ob


def review_box(col, name, center, size, mat):
    return review_record(col, {"name": name, "cf": list(center), "size": size, "material": mat}, name)


def light(col, name, position, target, power=1000, size=5, color=(1, .92, .80), kind="AREA"):
    data = bpy.data.lights.new(name, kind)
    ob = bpy.data.objects.new(name, data); col.objects.link(ob)
    ob.location = kit.to_blender(position)
    data.energy, data.color = power, color
    if kind == "AREA":
        data.shape, data.size = "DISK", size
        ob.rotation_euler = (kit.to_blender(target) - ob.location).to_track_quat("-Z", "Y").to_euler()
    else:
        data.shadow_soft_size = .45
    return ob


def wires(col, rec, mat):
    center, half = Vector(rec["cf"][:3]), Vector(rec["size"]) / 2
    points = [center + Vector((sx * half.x, sy * half.y, sz * half.z))
              for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
    curve = bpy.data.curves.new("Collider edges", "CURVE"); curve.dimensions = "3D"
    curve.bevel_depth, curve.bevel_resolution = .012, 0
    for i in range(8):
        for bit in (1, 2, 4):
            j = i ^ bit
            if j <= i:
                continue
            sp = curve.splines.new("POLY"); sp.points.add(1)
            for p, v in zip(sp.points, (points[i], points[j])):
                p.co = (*kit.to_blender(v), 1)
    curve.materials.append(mat)
    ob = bpy.data.objects.new("WIRE " + rec["name"], curve); col.objects.link(ob)


def render_review(name, cutaway=False):
    sc = bpy.context.scene
    for ob in list(sc.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    col = bpy.data.collections.new("Review " + name); sc.collection.children.link(col)
    info = kit.COMPONENTS[name]; attrs = info["attrs"]
    length, rise = attrs["length"], attrs["toY"]
    main = kit.place(col, name)
    if cutaway:
        main.data = main.data.copy()
        bm = bmesh.new(); bm.from_mesh(main.data)
        bmesh.ops.bisect_plane(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces),
                              dist=.00001, plane_co=(0, 0, 0), plane_no=(1, 0, 0),
                              clear_outer=True, clear_inner=False)
        bm.to_mesh(main.data); bm.free()
    for rec in info["parts"]:
        if cutaway and (rec["cf"][0] > 0 or rec["name"].startswith("Level 2 Overhead")):
            continue
        review_record(col, rec)
    if cutaway:
        mat = bpy.data.materials.new("Review Collider Orange"); mat.diffuse_color = (1, .14, .02, 1)
        mat.use_nodes = True
        b = mat.node_tree.nodes.get("Principled BSDF")
        b.inputs["Base Color"].default_value = (1, .14, .02, 1)
        b.inputs["Emission Color"].default_value = (1, .09, .01, 1)
        b.inputs["Emission Strength"].default_value = .6
        for rec in info["colliders"] + [r for r in info["parts"] if r["collide"]]:
            wires(col, rec, mat)
        review_box(col, "Review Ground", (0, -4.1, 0), (110, .2, 130), "Service")
        camera_pos, target = (67, 42, -72), (0, 13, 0)
        light(col, "Review Key", (15, 48, -35), (0, 10, 0), 3800, 12)
        light(col, "Review Fill", (-32, 22, 5), (0, 12, 0), 1800, 10, (.72, .86, 1))
    else:
        narrow = name.startswith("Passage_")
        camera_pos = (0 if narrow else -4.1, 5.6, -length / 2 + 2.7)
        target = (0, rise + 5.6, length / 2 + 10)
        # Bright fake hall: native-style deck, basin, glass block and columns.
        if attrs.get("waterRegion"):
            depth = .1 - attrs["waterRegion"]["size"][1]
            review_box(col, "Review Hall Basin", (0, depth - .6, length / 2 + 25), (18.2, 1.2, 50), "Mosaic")
            for x in (-23.05, 23.05):
                review_box(col, "Review Hall Deck", (x, rise - .6, length / 2 + 25), (27.9, 1.2, 50), "Terrazzo")
        else:
            review_box(col, "Review Hall Deck", (0, rise - .6, length / 2 + 25), (74, 1.2, 50), "Terrazzo")
        review_box(col, "Review Hall Rear", (0, rise + 21, length / 2 + 49), (74, 44, 1), "Tile")
        review_box(col, "Review Hall Glass Blocks", (0, rise + 19, length / 2 + 48.3), (18, 23, .3), "GlassBlock")
        review_box(col, "Review Hall Dado", (0, rise + 1.5, length / 2 + 48.3), (74, 3, .3), "TileTeal")
        for x in (-14, 14):
            tmp = kit.Mesh("ReviewColumn")
            column_z = length / 2 + 14
            tmp.cylinder((x, rise + 18, column_z), 3, 36, "Tile", segments=20)
            def column_band_uv(co, normal):
                u = math.atan2(-co.y / kit.S - column_z, co.x / kit.S - x) * 3 * kit.S
                return u, (co.z / kit.S - rise - BAND_BOTTOM) / (BAND_TOP - BAND_BOTTOM)
            tmp.cylinder((x, rise + (BAND_BOTTOM + BAND_TOP) / 2, column_z), 3.03,
                         BAND_TOP - BAND_BOTTOM, "Bands", segments=20, uv=column_band_uv)
            tmp.finish(); kit.place(col, "ReviewColumn"); kit.COMPONENTS.pop("ReviewColumn")
        if attrs.get("waterRegion"):
            # Review-only water proxy; runtime export contains only a Terrain region.
            water = bpy.data.materials.new("Review water proxy"); water.use_nodes = True
            b = water.node_tree.nodes.get("Principled BSDF")
            b.inputs["Base Color"].default_value = (.05, .28, .32, .48)
            b.inputs["Roughness"].default_value = .13
            b.inputs["Alpha"].default_value = .48
            b.inputs["IOR"].default_value = 1.333
            b.inputs["Transmission Weight"].default_value = .35
            noise = water.node_tree.nodes.new("ShaderNodeTexNoise")
            noise.inputs["Scale"].default_value = 13
            bump = water.node_tree.nodes.new("ShaderNodeBump")
            bump.inputs["Strength"].default_value = .22; bump.inputs["Distance"].default_value = .035
            water.node_tree.links.new(noise.outputs["Fac"], bump.inputs["Height"])
            water.node_tree.links.new(bump.outputs["Normal"], b.inputs["Normal"])
            water.surface_render_method = "DITHERED"
            mesh = bpy.data.meshes.new("Review Water Surface")
            mesh.from_pydata([kit.to_blender(p) for p in [(-9.1, .1, -length / 2), (9.1, .1, -length / 2),
                                                        (9.1, .1, length / 2 + 50), (-9.1, .1, length / 2 + 50)]], [], [(0, 3, 2, 1)])
            mesh.materials.append(water)
            ob = bpy.data.objects.new("Review-only Terrain water proxy", mesh); col.objects.link(ob)
        for z in (-length / 3, 0, length / 3):
            y = floor_height(z, length, rise)
            light(col, "Review bounce", (0, y + (12 if narrow else 20), z),
                  (0, y, z + 4), 180 if narrow else 500, 3 if narrow else 6)
        if not narrow:
            light(col, "Review vault grazing light", (-5, rise + 25, length / 2 - 9),
                  (0, rise + 29, length / 2 + 2), 420, 4, (.85, .93, 1))
        light(col, "Review hall daylight", (0, rise + 30, length / 2 + 15),
              (0, 4, 0), 2600, 8, (.83, .93, 1))
        light(col, "Review hall top", (0, rise + 38, length / 2 + 34),
              (0, rise, length / 2 + 20), 3000, 10)
        for marker in info["markers"]:
            if marker["name"] == "LampLight":
                light(col, "Review bulkhead point", marker["cf"][:3], (0, 0, 0), 75, kind="POINT")
    cam = bpy.data.objects.new("Review Camera", bpy.data.cameras.new("Review Camera")); col.objects.link(cam)
    cam.location = kit.to_blender(camera_pos)
    cam.rotation_euler = (kit.to_blender(target) - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = 30 if cutaway else 23 if name.startswith("Passage_") else 22
    cam.data.clip_start, cam.data.clip_end = .04, 400
    sc.camera = cam
    sc.render.engine = "BLENDER_EEVEE"
    sc.eevee.taa_render_samples = 64
    sc.eevee.use_raytracing = True
    sc.render.resolution_x, sc.render.resolution_y, sc.render.resolution_percentage = 1280, 800, 100
    sc.render.image_settings.file_format = "PNG"
    sc.render.film_transparent = False
    sc.world = bpy.data.worlds.new("Review World"); sc.world.use_nodes = True
    sc.world.node_tree.nodes["Background"].inputs[0].default_value = (.32, .40, .50, 1)
    sc.world.node_tree.nodes["Background"].inputs[1].default_value = .35
    sc.view_settings.view_transform = "AgX"
    sc.view_settings.look = "AgX - Medium High Contrast"
    suffix = "_cutaway" if cutaway else "_inside"
    path = REVIEW / (name + suffix + ".png")
    sc.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    print("REVIEW=" + str(path), flush=True)
    return str(path)


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixed-stair-vault", action="store_true",
                        help="Keep stair roof at y32..34, accepting reduced far-mouth clearance.")
    parser.add_argument("--export-only", action="store_true")
    opts = parser.parse_args(args)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    build(raise_stair_vault=not opts.fixed_stair_vault)
    rows = verify()
    kit.EXPORT_DIR = EXPORT
    manifest = kit.export()
    assert sum(c["tris"] for c in manifest["chunks"]) == sum(r["tris"] for r in rows)
    REVIEW.mkdir(parents=True, exist_ok=True)
    paths = []
    if not opts.export_only:
        for name in ("Tunnel_Wet_72", "Tunnel_Stair8_64", "Tunnel_Kids_64", "Passage_Flat_48", "Passage_Stair4_48"):
            paths.append(render_review(name))
        paths.append(render_review("Tunnel_Wet_72", cutaway=True))
    (EXPORT / "verification.json").write_text(json.dumps({
        "components": rows, "renders": paths, "engine": "BLENDER_EEVEE",
        "sourceSha256": {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in (
            Path(__file__), Path(kit.__file__),
            kit.ROOT / "artifacts/level2-blender-20261002/KIT_SPEC.md")},
        "scope": "offline only; no Studio, gameplay or phone verification",
        "decisions": [
            "34 is the nominal envelope; the certified floor collider line gives 24.2 clear between haunches.",
            "30x30 rectangular mouths have 1.75-stud collars and 4-stud transitions into the vault.",
            "Stair vault rises to preserve mouth clearance; single roof box covers the highest crown." if not opts.fixed_stair_vault else
            "Stair vault fixed at 32; far-mouth height reduced by the floor rise.",
            "Steps stay within the middle third with 2.3 runs where possible; short flights compress treads. Final riser shortened for exact 4/8 rise.",
            "Curb is the existing 1.2 wide; ground minimum interpreted across the long support axis.",
            "Bands use one one-metre block on both walls; Kids retains that palette with Rubber channel floor.",
            "kit.part show=True would duplicate native Parts into chunks; reviews use separate proxies.",
            "Passages use Steel and LampGlow mesh chunks; concrete remains Service/ServiceGrey Part records."
        ]}, indent=2), encoding="utf-8")
    print("JOB_B_OK", flush=True)
