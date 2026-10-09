"""PR-B: round Poolrooms tunnels, narrow pipes, and low escape chambers.

Run headless with D:/Blender/blender.exe -b --factory-startup --python-exit-code 1
-P G:/Roblox/MongoTV/tools/level2_poolrooms/modules_tunnel.py
All authored coordinates are Roblox studs (X right, Y up, Z back).
"""
import json
import math
import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).parent))

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree
import prkit as kit


EXPORT = Path("G:/Blender/Level2_Poolrooms/jobs/B/export")
REVIEW = Path("G:/Blender/Level2_Poolrooms/review/B")
ROOMS = {"A": (48, 48), "B": (48, 64), "C": (64, 64), "D": (40, 56)}
WALL = 1.75
CHAMBER_WALL_BOTTOM = -5.5   # four studs below the submerged floor's -1.5 top, on the 0.5 lattice (LATTICE_SPEC C12)
LOWER_FILL_X = {True: 14.0, False: 4.5}  # inner edge of the one lower spandrel fill (round tunnel, pipe), F12-E
RIB_RELIEF = .24            # rib band depth inside the barrel; keeps it within 0.6 of the facet seams (<= 0.58, F12-E)
COLLAR_GAP = .6             # every collar panel point lies within this of a collider (collision_audit tolerance)
# LATTICE_SPEC C8 (2026-10-05): the round tunnel's collar outline is 18 each side of the axis (a whole number, so the
# builder's hole edges Cross +- 18, its lintels and sills lie on the 0.5 tile lattice); its 17-stud bore no longer
# touches the jambs, so the jamb faces sit behind the panel, not on the bore's widest facet (R2 work order 3, the old
# 0.04 TUNNEL_JAMB). The pipe collar keeps its tangent 6. Tops 32 / 12.
COVE_R = 1.5                 # chamber wall-foot / ceiling cove radius: tangents at y 1.5 / 13.5 and 3.25 from the outer
                             # wall face, on / half the lattice (LATTICE_SPEC C13; R1.2 could not reach both phases)
FILLET = 8-WALL              # chamber vertical corner radius (inner face); centre 8 from both outer faces
LEDGE = 8                    # chamber ledge ring, measured from the OUTER wall face (6.25 visible = FILLET)
SOCKET_HALF = 6              # half the 12-wide socket aperture
CHECKS = {}                  # extra validation counts written to checks.json


def triangle_count(mesh):
    mesh.calc_loop_triangles()
    return len(mesh.loop_triangles)


def floor_height(z, length, rise):
    """The stair bore climbs evenly, so each collision facet can span both collars."""
    if not rise:
        return 0
    return rise*max(0, min(1, (z+length/2)/length))


def arch_angles(radius, cy, segments):
    """Keep the side tangencies in the barrel and collar at identical vertices."""
    low = math.asin(-cy/radius)
    high = math.pi-low
    angles = [low+(high-low)*i/segments for i in range(segments+1)]
    for landmark in (0, math.pi/4, math.pi/2, 3*math.pi/4, math.pi):
        nearest = min(range(1, segments), key=lambda i: abs(angles[i]-landmark))
        angles[nearest] = landmark
    assert all(b>a for a,b in zip(angles,angles[1:]))
    return low, high, angles


def arc_shell(m, radius, cy, length, segments, rise=0, mat="Tile"):
    """Only the visible inside of the barrel; no outer shell or exposed end face.
    Faces point at the bore axis (G2); UVs are per vertex (axial, arc length), so the full-circle pipe seam does not
    wrap (F3+F6 uv). Lattice (LATTICE_SPEC C8): u = z, whole at both mouth planes (integers); v = arc length from the
    floor chord fitted to whole tiles (fit_arc), the same function as the collar reveal, so barrel and reveal meet in
    phase. A stair bore is sheared: its rows climb with the floor and its joints stay plumb (skew = atan(rise/L))."""
    low, high, angles = arch_angles(radius, cy, segments)
    cuts = ([-length/2, length/2] if not rise else
            [-length/2, -2*rise, -rise, 0, rise,
             2*rise, length/2])
    cuts=sorted(set(cuts))
    k = fit_arc(high-low, radius)
    verts = [(radius*math.cos(a), floor_height(z,length,rise)+cy+radius*math.sin(a), z)
             for z in cuts for a in angles]
    uvs = [(z*kit.S, (a-low)*k*kit.S) for z in cuts for a in angles]
    n = segments+1
    faces = [(j*n+i, j*n+i+1, (j+1)*n+i+1, (j+1)*n+i)
             for j in range(len(cuts)-1) for i in range(segments)]
    piece(m, "shear" if rise else "curved", m.raw, verts, faces, mat, smooth=True, vertex_uv=uvs,
          facing=lambda p: (-p[0], cy+floor_height(p[2], length, rise)-p[1], 0))


TILE = .5                   # grout pitch: the texture's grout lines sit at multiples of 0.5 stud of UV (LATTICE_SPEC 2.1;
                            # the UV scale itself is prkit.TILE_M, checked against this in check_lattice)
PIECES = {}                 # component -> [(first polygon, end polygon, kind)] for check_lattice; kind: 'curved' (UV
                            # follows the surface: size band + skew), 'fan' (curved, u fans: v band only),
                            # 'shear' (stair bore: skew up to the bore's own shear). Untagged faces are 'flat'.


def collar_half(radius):
    """Half width of a mouth collar's square outline (LATTICE_SPEC 6: tunnel 18, pipe 6)."""
    return 18 if radius > 10 else 6


def piece(m, kind, fn, *args, phase=(0, 0, 0), **kw):
    """Run one Mesh-building call and tag the polygons it adds (absorb() appends one uvf entry per face, in the order
    finish() writes the polygons). phase: a flat piece's grid lines sit at local x/y/z = phase + k*TILE."""
    start = len(m.uvf)
    out = fn(*args, **kw)
    PIECES.setdefault(m.name, []).append((start, len(m.uvf), kind, tuple(phase)))
    return out


def fit_arc(span, radius):
    """u (studs of UV) per radian so an arc of `span` radians at `radius` carries whole tiles (pitch within 1%)."""
    return round(span*radius/TILE)*TILE/span


def trim_v(offset, width):
    """UV v (studs) across a trim narrower than one tile, measured from its centre: the band sits centred in ONE tile
    row, so no grout line runs along it or hugs its edges. The grid's own phase (a line at an edge, cut by every
    cross joint) drew rows of '+' ticks on the rib and parapet edges (VERIFY2 F03/F03b/F11b, D11)."""
    assert width < TILE-.1, ("trim wider than a tile row", width)
    return offset+TILE/2


def rib(m, radius, cy, z, segments, thickness=.38, floor_y=0):
    """Proud tiled internal band (Tile, F3): ONE row of tiles wrapping the band and both side faces. u = arc length at
    the band's inner radius on all three faces, so every cross joint runs straight over both edges; v runs across the
    row (band: axial, sides: radial) centred in the tile (trim_v). The old planar (x, y) UV on the side annuli cut
    the grid obliquely: '+' / 'L' ticks at 45 degrees and a stepped seam along the ring at grazing angles."""
    inner, outer = radius-RIB_RELIEF, radius+.06
    # Round bores end the rib 0.05 below the floor chord (the outer edge ~0.3 below), buried in the floor, ledge or
    # steps, so the hollow ring has no open slot at its feet. Full-circle pipe ribs pass through the pipe floor.
    low, high, angles = arch_angles(inner, cy+.05, segments) if cy+.05 < inner else arch_angles(radius, cy, segments)
    a, b = z-thickness/2, z+thickness/2
    n = segments+1
    k = fit_arc(high-low, inner)          # whole tiles round the band (LATTICE_SPEC 2.4 curved trims)
    u = [(t-low)*k*kit.S for t in angles]
    band = [(inner*math.cos(t), floor_y+cy+inner*math.sin(t), zz) for zz in (a, b) for t in angles]
    piece(m, "curved", m.raw, band, [(i, n+i, n+i+1, i+1) for i in range(segments)], "Tile", smooth=True,
          vertex_uv=[(ut, trim_v(zz-z, thickness)*kit.S) for zz in (a, b) for ut in u],
          facing=lambda p: (-p[0], floor_y+cy-p[1], 0))
    # Side faces: visible from the band edge (inner) to the barrel (radius); the 0.06 beyond is buried.
    for zz, side in ((a, -1), (b, 1)):
        ring = [(r*math.cos(t), floor_y+cy+r*math.sin(t), zz) for r in (inner, outer) for t in angles]
        piece(m, "curved", m.raw, ring, [(i, i+1, n+i+1, n+i) for i in range(segments)], "Tile",
              vertex_uv=[(ut, trim_v(r-inner-RIB_RELIEF/2, RIB_RELIEF)*kit.S) for r in (inner, outer) for ut in u],
              facing=lambda p, s=side: (0, 0, s))


def collar(m, radius, cy, z, segments, label, floor_y=0):
    """A closed rectangular panel around the floor-chord arch, 1.75 studs deep.

    The circle's mathematical bottom is below the floor for the large bore;
    the tiled threshold closes that buried portion. The panel faces and outside
    edges (planar box UV) and the circular reveal (own shell, arc UV) share one Tile chunk.
    """
    low, high, angles = arch_angles(radius, cy, segments)
    halfwidth = collar_half(radius)
    top = 32 if radius > 10 else 12
    # The pipe circle touches its square at t=0 and pi and its header at pi/2;
    # the panel pinches to those exact tangencies (lifting its outer rail above
    # them folds the panel across the reveal). The tunnel square (18) is one stud
    # wider than its circle, so its panel keeps that width at the sides.
    def outer_point(t):
        if t <= 0:
            return halfwidth, cy*(t-low)/(-low)
        if t <= math.pi/4:
            return halfwidth, cy+(top-cy)*t/(math.pi/4)
        if t <= 3*math.pi/4:
            return halfwidth*(1-4*(t-math.pi/4)/math.pi), top
        if t <= math.pi:
            return -halfwidth, top-(top-cy)*(t-3*math.pi/4)/(math.pi/4)
        return -halfwidth, cy*(high-t)/(high-math.pi)
    # The pivot mouth is at the outer wall face. The reveal projects through
    # the adjacent wall, so its far face is flush with the chamber interior.
    a, b = z, z+(-1.75 if z < 0 else 1.75)
    # Weld coincident inner/outer vertices at the side (and pipe crown)
    # tangencies. Each panel strip then ends in a triangle, not a zero-area
    # quad that can draw a white or dark slit against the barrel.
    verts, rails = [], {}
    for zi, zz in enumerate((a, b)):
        for outer in (False, True):
            rail = []
            for i, t in enumerate(angles):
                x, y = (outer_point(t) if outer else
                        (radius*math.cos(t), cy+radius*math.sin(t)))
                ix, iy = radius*math.cos(t), cy+radius*math.sin(t)
                if outer and math.hypot(x-ix,y-iy)<1e-7:
                    rail.append(rails[(zi, False)][i])
                else:
                    rail.append(len(verts))
                    verts.append((x, y+floor_y, zz))
            rails[(zi, outer)] = rail
    ia, oa, ib, ob = (rails[(0,False)], rails[(0,True)],
                      rails[(1,False)], rails[(1,True)])
    faces = []
    def add_face(*indices):
        clean=[]
        for index in indices:
            if not clean or clean[-1]!=index:
                clean.append(index)
        if clean and clean[0]==clean[-1]:
            clean.pop()
        if len(set(clean))>=3:
            faces.append(tuple(clean))
    # Only the two panels. The collar always sits in a wall cut of exactly its outline (hall walls: the builder's
    # hole, jambs at +-halfwidth, head at the collar top; chambers: the Wall Run ends at +-6, Above Socket from 12;
    # the Threshold Part below both), so its outer edge faces (sides, head) and the two floor-level end caps lay ON
    # the wall's jamb, head and threshold/ledge faces. They were never seen face-on, but the pipe circle is tangent to its jambs at
    # y=cy and the jamb and edge z-fought through that slit (VERIFY2 08: Chamber_B/C/D and a hall wall vs Pipe_Flat/
    # Pipe_Stair4, 5.25 stud^2 per chamber). The wall now owns those planes alone (check_socket_joins).
    for i in range(segments):
        add_face(ia[i],ia[i+1],oa[i+1],oa[i])
        add_face(ib[i],ob[i],ob[i+1],ib[i+1])

    def away(p):
        """Panels (planar, box UV) face away from the collar solid."""
        return (0, 0, a-b) if abs(p[2]-a) < 1e-4 else (0, 0, b-a)
    # Box UV = planar in the corridor frame, phase 0: the outline +-halfwidth, 0 and top are lattice lines, the same
    # lines as the builder's wall slab, lintel and sill round the hole (LATTICE_SPEC C8).
    piece(m, "flat", m.raw, verts, faces, "Tile", facing=away)
    # The circular reveal is its own shell with per-vertex (arc, axial) UVs, so the full-circle pipe reveal does not
    # wrap at its seam (F3+F6 uv); it faces the bore axis. u = the barrel's fitted arc (whole tiles from the floor
    # chord), v = z: whole at the mouth plane, so the reveal continues the barrel exactly (LATTICE_SPEC I2.2).
    ring = [(radius*math.cos(t), floor_y+cy+radius*math.sin(t), zz) for zz in (a, b) for t in angles]
    n = segments+1
    k = fit_arc(high-low, radius)
    piece(m, "curved", m.raw, ring, [(i, n+i, n+i+1, i+1) for i in range(segments)], "Tile", smooth=True,
          vertex_uv=[((t-low)*k*kit.S, zz*kit.S) for zz in (a, b) for t in angles],
          facing=lambda p: (-p[0], floor_y+cy-p[1], 0))
    # A native solid threshold closes the buried section of the large circle.
    # Its top is the Y=0 chord and it fully overlaps the hall floor slab.
    sill=0 if radius > 10 else 1
    m.part(f"Level 2 {'Corridor' if radius > 10 else 'Passage'} {label} Threshold",
           (0, floor_y+(sill-2)/2, z+(-2 if z<0 else 2)),
           (2*halfwidth, 2+sill, 4), "Tile", ground=True,
           attrs={"Level2_EntityGround": True})
    # The visual collar panel is non-colliding. Close its upper rectangular
    # spandrels behind the tiled face. The threshold's top is only the floor
    # chord, so each lower spandrel gets ONE box inscribed below the circle
    # (F12-E): its inner top corner lies on the circle, so it never enters the
    # bore. The rest of the panel is backed by the bore facets (side_collision);
    # check_collar_backing proves every panel point is within COLLAR_GAP.
    corner_x,corner_bottom=(12.7,24) if radius>10 else (4.5,9.5)
    depth_z=z+(-.875 if z<0 else .875)
    for side in (-1,1):
        m.part(f"Level 2 {'Corridor' if radius > 10 else 'Passage'} {label} Corner Fill {side:+}",
               (side*(corner_x+halfwidth)/2,
                floor_y+(corner_bottom+top)/2,
                depth_z),
               (halfwidth-corner_x,top-corner_bottom,1.75),"Tile",show=False)
        m.parts[-1]["properties"]={"Transparency":1}
        x0 = LOWER_FILL_X[radius > 10]
        y1 = cy-math.sqrt(radius*radius-x0*x0)
        m.part(f"Level 2 {'Corridor' if radius > 10 else 'Passage'} {label} Lower Corner Fill {side:+}",
               (side*(x0+halfwidth)/2, floor_y+(sill+y1)/2, depth_z),
               (halfwidth-x0, y1-sill, 1.75), "Tile", show=False)
        m.parts[-1]["properties"]={"Transparency":1}
    m.marker(label, (0, floor_y, z), yaw=180 if z < 0 else 0,
             clearWidth=2*radius if radius > 10 else 12, clearHeight=30 if radius > 10 else 12)


def floor_part(m, name, center, size, mat):
    m.part(name, center, size, mat, ground=True, attrs={"Level2_EntityGround": True})


def side_collision(m, radius, cy, length, rise, narrow):
    """One oriented, overlapping box per facet of the entire circular bore."""
    facets = 8 if narrow else 12
    slope = rise/length
    back = Vector((0, slope, 1)).normalized()
    # The round bore's facets are 3.2 thick OUTWARD (inner plane unchanged) so they also back the collar panel's
    # upper spandrels between the circle and the Corner Fill (F12-E) without extra parts. Their outer corners stay
    # within 20.62 of the axis: a third hall's wall slab (1.75 thick) starts >= 20 from the corridor axis, so a corner
    # can only end inside that slab, never in its room.
    # Pipe facets are 1.2 thick (outer corners 7.35 from the axis): on Pipe_Stair4_16 the tilted top facets drop 0.44
    # below the flat collar at its hall face, and 0.7 left the header 0.84 from collision (F12-E).
    # LATTICE_SPEC C8 widened the tunnel collar from 17.04 to 18 each side: 3.0 / 0.8 left the panel's new outer strip
    # 0.65-1.2 from collision at y ~23 on the tilted Stair8 boxes (check_collar_backing); 3.2 / 1.6 close it.
    thickness = 1.2 if narrow else 3.2
    # Seam overlap: 0.2 on the pipe; 1.6 on the round bore, whose thick boxes otherwise part at their OUTER corners
    # (the 30-degree seam behind the collar's upper spandrel, worst on the tilted Stair8 boxes at the high mouth).
    # The widened inner corners (17.54 from the axis) stay behind the neighbouring facet's inner plane (17.11 >= 16.75),
    # never in the bore.
    overlap = .2 if narrow else 1.6
    for i in range(facets):
        angle = math.tau*(i+.5)/facets
        radial = Vector((math.cos(angle), math.sin(angle),
                         -slope*math.sin(angle))).normalized()
        right = radial.cross(back).normalized()
        up = back.cross(right).normalized()
        # The inner plane is 0.25 stud inside the circle at each facet centre.
        centre = Vector((math.cos(angle)*(radius-.25+thickness/2),
                         cy+rise/2+math.sin(angle)*(radius-.25+thickness/2), 0))
        m.collider(f"Level 2 {'Passage' if narrow else 'Corridor'} Facet {i+1:02d}",
                   tuple(centre),
                   (2*radius*math.sin(math.pi/facets)+overlap, thickness,
                    (length+3.5)*math.sqrt(1+slope*slope)))
        m.colliders[-1]["cf"] = [*centre,
            right.x, up.x, back.x, right.y, up.y, back.y,
            right.z, up.z, back.z]
    crown = cy+radius
    roof_depth=2 if not narrow else .84
    m.collider(f"Level 2 {'Passage' if narrow else 'Corridor'} Roof Collider",
               (0, crown+rise+roof_depth/2, 0),
               (2*radius, roof_depth, length+3.5),
               attrs={"Level2_NoEntityGround": True})
    if rise and not narrow:
        m.collider("Level 2 Corridor Entry Crown Cap",
                   (0,crown+1,-length/2-.875),(2*radius,2,1.75))


def steps(m, length, rise, width, label, material="Tile", base=0):
    count = math.ceil(rise/3)
    run = length/count
    assert run >= 4
    slope = rise/length
    pitch = math.sqrt(1+slope*slope)
    for i in range(count):
        z0,z1=-length/2+i*run,-length/2+(i+1)*run
        y0,y1=base+rise*i/count,base+rise*(i+1)/count
        verts=[(x,y,z) for x in (-width/2,width/2)
               for y,z in ((y0,z0),(y1,z1),(y1-.9,z1),(y0-.9,z0))]
        faces=[(0,1,5,4),(3,7,6,2),(0,4,7,3),
               (1,2,6,5),(0,3,2,1),(4,5,6,7)]
        piece(m, "flat", m.raw, verts, faces, material)   # box UV: planar phase 0 (the sloped top: projected)
        mid=(y0+y1)/2
        m.part(f"{label} Ramp {i+1}",
               (0,mid-.45/pitch,(z0+z1)/2+.45*slope/pitch),
               (width,.9,run*pitch+.025),material,ground=True,show=False,
               attrs={"Level2_EntityGround":True})
        m.parts[-1]["cf"]=[*m.parts[-1]["cf"][:3],
            1,0,0, 0,1/pitch,slope/pitch, 0,-slope/pitch,1/pitch]
        m.parts[-1]["properties"]={"Transparency":1}


def tunnel(variant, length):
    radius, cy = 17, 13
    rise = {"Stair4": 4, "Stair8": 8}.get(variant, 0)
    m = kit.Mesh(f"RoundTunnel_{variant}_{length}", Kind="Tunnel", Variant=variant,
                 Length=length, Width=34, FromY=0, ToY=rise,
                 InnerRadius=radius, CircleCentreY=cy, CollarDepth=1.75,
                 MeshCanCollide=False, MeshCanQuery=False, MeshCanTouch=False)
    arc_shell(m, radius, cy, length, 48, rise)
    for z in (-length/2, length/2):
        collar(m, radius, cy, z, 48, "MouthFrom" if z < 0 else "MouthTo",
               rise if z > 0 else 0)
    # Rings are spaced 16-24 studs and never straddle the flat mouth collar.
    ring_count = max(2, round(length/20)-1)
    for i in range(1, ring_count+1):
        z=-length/2+i*length/(ring_count+1)
        rib(m, radius, cy, z, 48, floor_y=floor_height(z,length,rise))
    # LATTICE_SPEC C9: every floor edge on the 0.5 lattice. The floor reaches x +-11.5, 0.55 past the bore's floor
    # chord (10.95), so its outer edge hides under the tiled wall.
    floor_width=23
    body=length
    if variant == "Wet":
        channel_half=7
        floor_part(m, "Level 2 Corridor Water Floor", (0, -2, 0),
                   (2*channel_half, 1, body), "Aqua")
        # Each ledge is one solid from the channel face (x 7) to the wall (11.5), down past the water floor top (-1.5)
        # to -2, so its side IS the channel side and no two tile tops share the y=0 plane (F4-M). The spec's 1.9 height
        # would leave the hidden bottom edge at -1.9, off the lattice: 2.0 keeps every edge on it.
        for side in (-1, 1):
            floor_part(m, f"Level 2 Corridor Ledge {side:+}",
                       (side*(channel_half+floor_width/2)/2, -1, 0),
                       (floor_width/2-channel_half, 2, body), "Tile")
        # F5a: one 4-stud voxel row [F-4, F-0.1] over the channel strip [Cross-8, Cross+8]; its edges sit under the
        # ledges (top F), so the ledges stay dry and the water meets the channel sides.
        m.attrs["waterRegion"] = {"center": [0, -2.05, 0], "size": [16, 3.9, body],
                                   "surfaceY": -.1, "terrainOnly": True}
    elif rise:
        steps(m, length, rise, floor_width, "Level 2 Corridor")
    else:
        floor_part(m, "Level 2 Corridor Dry Floor", (0, -.5, 0),
                   (floor_width, 1, body), "Tile")
    side_collision(m, radius, cy, length, rise, False)
    m.marker("LampLight", (0, cy+radius-1.4+rise/2, 0), Brightness=.35, Range=32,
             Shadows=False, Colour="Warm")
    m.finish()


def pipe(variant, length):
    radius, cy = 6, 6
    rise = 4 if variant == "Stair4" else 0
    m = kit.Mesh(f"Pipe_{variant}_{length}", Kind="Narrow", Variant=variant,
                 Length=length, Width=12, FromY=0, ToY=rise,
                 InnerRadius=radius, CircleCentreY=cy, CollarDepth=1.75,
                 MeshCanCollide=False, MeshCanQuery=False, MeshCanTouch=False)
    arc_shell(m, radius, cy, length, 32, rise, "Tile")
    for z in (-length/2, length/2):
        collar(m, radius, cy, z, 32, "MouthFrom" if z < 0 else "MouthTo",
               rise if z > 0 else 0)
    for z in range(-length//2+20, length//2-8, 20):
        rib(m, radius, cy, z, 32, .24, floor_height(z,length,rise))
    # The floor is a dry walkable chord across the very bottom of the bore (F5c: pipes are DRY, no waterRegion;
    # G1: above water, so Tile). Its outer edge hides under the tiled wall rather than ending in a void.
    # LATTICE_SPEC C9: x +-3.5 (0.18 past the bore at the sill, 3.32), y 0..1.
    floor_width=7
    if rise:
        steps(m, length, rise, floor_width, "Level 2 Passage", "Tile", base=1)
    else:
        floor_part(m, "Level 2 Passage Floor", (0, .5, 0),
                   (floor_width, 1, length), "Tile")
    side_collision(m, radius, cy, length, rise, True)
    m.marker("LampLight", (0, 10.8+rise/2, 0), Brightness=.22, Range=18,
             Shadows=False, Colour="Warm")
    m.finish()


COVE_TILES = 4.5            # tiles round a chamber cove's quarter: whole at the wall tangent, half at the floor/ceiling
                            # tangent (3.25 from the outer face, mid-tile of the ledge/slab lattice; LATTICE_SPEC C13)
COVE_SEGS = 6               # facets per cove quarter (cove_strip, corner_cove)


def cove_v(a):
    """Tile v (studs) of a chamber cove profile at angle a (0 = wall tangent, pi/2 = floor/ceiling tangent): exactly
    pitch 0.5 on the two end facets (they lie within 7.5 deg of the wall and the ledge/slab, and where the lower cove
    is cut at a socket its end edge stands against the pipe's collar panel in the wall plane: rows there must be the
    wall's rows), the four middle facets carry the rest (pitch 0.534; the quarter keeps COVE_TILES)."""
    k = a/(math.pi/2)*COVE_SEGS
    chord = 2*COVE_R*math.sin(math.pi/4/COVE_SEGS)
    total = COVE_TILES*TILE
    if k <= 1:
        return k*chord
    if k >= COVE_SEGS-1:
        return total-(COVE_SEGS-k)*chord
    return chord+(k-1)*(total-2*chord)/(COVE_SEGS-2)


def fillet_u(t):
    """Tile u (studs) round a chamber corner at angle t: whole tiles per quarter at FILLET (20, pitch 0.491), zero at
    t = 0, so both tangents (integers along their walls) are lattice lines. The corner tori share it: their radial
    lines continue the vertical fillet's (a fan along u, LATTICE_SPEC 2.4)."""
    return t*fit_arc(math.pi/2, FILLET)


def chamber_corner(m, cx, cz, sx, sz, h=15):
    """Quarter-round vertical corner: only the inner surface the room sees (G2); the outer shell and caps were
    hidden in the wall, ledge and slab. Colliders back it (Room Curved Side). u = fillet_u, v = y (rows from FloorY)."""
    n = 12
    # NE in the X/Z plan is represented by sx=+1, sz=-1; the same
    # first-quadrant quarter maps cleanly to all four corners.
    angles = [i*math.pi/(2*n) for i in range(n+1)]
    ys = (-1.4, h+.8)                      # ledge bottom .. slab top: the hidden ends stay inside solids
    verts = [(cx+sx*FILLET*math.cos(t), y, cz+sz*FILLET*math.sin(t)) for y in ys for t in angles]
    q = n+1
    piece(m, "curved", m.raw, verts, [(i, i+1, q+i+1, q+i) for i in range(n)], "Tile", smooth=True,
          vertex_uv=[(fillet_u(t)*kit.S, y*kit.S) for y in ys for t in angles],
          facing=lambda p: (cx-p[0], 0, cz-p[2]))
    for i in range(4):
        t = (i+.5)*math.pi/8
        x = cx+sx*(FILLET+.75)*math.cos(t)
        z = cz+sz*(FILLET+.75)*math.sin(t)
        m.collider(f"Level 2 Room Curved Side {sx:+} {sz:+} {i+1}",
                   (x, (CHAMBER_WALL_BOTTOM+h+2)/2, z),
                   (1.45, h+2-CHAMBER_WALL_BOTTOM, 3.0), yaw=kit.yaw_x_along(sx*math.cos(t), sz*math.sin(t)))


def corner_cove(m, cx, cz, sx, sz, h, upper, n=12, segs=COVE_SEGS):
    """Cove torus around a chamber fillet centre: continues the straight coves round the corner (F2). Profile
    (r, y) = (FILLET-R(1-cos a), R(1-sin a)) below, (FILLET-R(1-cos a), h-R(1-sin a)) above; concave side to the room.
    u = fillet_u(t) (whole tiles at both tangents, where the straight coves' u = along is an integer), v = cove_v."""
    verts, uvs = [], []
    for i in range(n+1):
        t = (math.pi/2)*i/n
        for k in range(segs+1):
            a = (math.pi/2)*k/segs
            r = FILLET-COVE_R*(1-math.cos(a))
            y = h-COVE_R+COVE_R*math.sin(a) if upper else COVE_R-COVE_R*math.sin(a)
            verts.append((cx+sx*r*math.cos(t), y, cz+sz*r*math.sin(t)))
            uvs.append((fillet_u(t)*kit.S, cove_v(a)*kit.S))
    q = segs+1
    yc = h-COVE_R if upper else COVE_R

    def facing(p):           # toward the cove circle's centre (r = FILLET-R, y = yc)
        dx, dz = p[0]-cx, p[2]-cz
        rp = max(math.hypot(dx, dz), 1e-6)
        k = (FILLET-COVE_R-rp)/rp
        return (dx*k, yc-p[1], dz*k)
    piece(m, "fan", m.raw, verts, [(i*q+k, i*q+k+1, (i+1)*q+k+1, (i+1)*q+k) for i in range(n) for k in range(segs)],
          "Tile", smooth=True, vertex_uv=uvs, facing=facing)


def cove_strip(m, point, a, b, upper, h, facing, segs=COVE_SEGS):
    """A straight quarter-round cove from along=a to along=b. point(along, inset, y) -> Roblox studs, inset measured
    from the wall face into the room; facing = the constant room-side direction (G2). u = along (the frame's own
    coordinate: phase 0, LATTICE_SPEC C13), v = cove_v."""
    assert b > a, (m.name, a, b)
    verts, uvs = [], []
    for along in (a, b):
        for k in range(segs+1):
            t = (math.pi/2)*k/segs
            y = h-COVE_R+COVE_R*math.sin(t) if upper else COVE_R-COVE_R*math.sin(t)
            verts.append(point(along, COVE_R*(1-math.cos(t)), y))
            uvs.append((along*kit.S, cove_v(t)*kit.S))
    q = segs+1
    piece(m, "curved", m.raw, verts, [(k, k+1, q+k+1, q+k) for k in range(segs)], "Tile", smooth=True,
          vertex_uv=uvs, facing=lambda p: facing)


def wall_coves(m, wall, w, d, h, socket_offsets):
    """Upper and lower coves along one chamber wall, tangent to tangent (the corner tori start exactly there; the old
    0.05 butt overlap laid two cove surfaces over each other). The lower cove is cut out of every socket span
    [offset-6, offset+6]: ChamberSocketCove / ChamberSocketStops (placed by the builder at the Socket marker) fill or
    close the cut."""
    horizontal = wall in "NS"
    sign = -1 if wall in "NW" else 1
    plane = sign*((d if horizontal else w)/2-WALL)
    if horizontal:
        point = lambda al, inset, y: (al, y, plane-sign*inset)
    else:
        point = lambda al, inset, y: (plane-sign*inset, y, al)
    end = (w if horizontal else d)/2-8
    for upper in (True, False):
        up = -1 if upper else 1
        face = (0, up, -sign) if horizontal else (-sign, up, 0)
        a = -end
        for off in ([] if upper else sorted(socket_offsets[wall])):
            cove_strip(m, point, a, off-SOCKET_HALF, upper, h, face)
            a = off+SOCKET_HALF
        cove_strip(m, point, a, end, upper, h, face)


def chamber(who, w, d):
    h = 15
    name = f"Chamber_{who}"
    m = kit.Mesh(name, Role="Small", Archetype="Poolrooms Escape Chamber",
                 PoolType="Shallow", Width=w, Depth=d, Height=h,
                 Pivot="FloorCentre", SocketIndexConvention="0=centre, 1=-16, 2=+16",
                 MeshCanCollide=False, MeshCanQuery=False, MeshCanTouch=False,
                 RouteRule="6-wide central cross and straight socket spokes")
    # Native Parts carry the broad shell and every walkable surface.
    # LATTICE_SPEC C12: every chamber Part edge on the 0.5 lattice. The pool floor top moves -1.2 -> -1.5 (y -2.5..-1.5;
    # the spec's 'already on integers' missed it and the ledge's -1.4 bottom), 1.4 under the water surface (-0.1).
    floor_part(m, "Level 2 Room Aqua Floor", (0, -2, 0), (w, 1, d), "Aqua")
    # Uniform ledge ring (F1+F2+F4 chambers): top 0, LEDGE from the outer wall face, so its pool edges pass through
    # the fillet centres and the wall-foot cove rests on y=0 along every wall and round every corner. N/S run the
    # full width and carry the corner squares; bottom -2 overlaps the Aqua floor top by 0.5.
    for sz, wall in ((-1, "N"), (1, "S")):
        floor_part(m, f"Level 2 Room Ledge {wall}", (0, -1, sz*(d/2-LEDGE/2)), (w, 2, LEDGE), "Tile")
    for sx, wall in ((1, "E"), (-1, "W")):
        floor_part(m, f"Level 2 Room Ledge {wall}", (sx*(w/2-LEDGE/2), -1, 0), (LEDGE, 2, d-2*LEDGE), "Tile")
    m.part("Level 2 Overhead Tile Slab", (0, h+.5, 0), (w, 1, d), "Tile", collide=False)
    m.collider("Level 2 Room Roof Collider", (0, h+.5, 0), (w, 1, d),
               attrs={"Level2_NoEntityGround": True})
    socket_offsets = {}
    for wall in "NESW":
        horizontal = wall in "NS"
        length = w if horizontal else d
        offsets = [0, -16, 16] if length >= 64 else [0]
        socket_offsets[wall] = offsets
        end = length/2-8
        cursor = -end                        # exactly at the fillet tangent, an integer (LATTICE_SPEC C12)
        runs = []
        for offset, index in sorted((v, i) for i, v in enumerate(offsets)):
            runs.append((cursor, offset-6, None))
            runs.append((offset-6, offset+6, f"{wall}{index}"))
            cursor = offset+6
        runs.append((cursor, end, None))
        for j, (a, b, plug) in enumerate(runs):
            if b <= a:
                continue
            along = (a+b)/2
            cross = ((-1 if wall=="N" else 1)*(d/2-WALL/2) if horizontal else
                     (1 if wall=="E" else -1)*(w/2-WALL/2))
            # Oriented like the builder's hall slabs (object X up, Y outward, Z along): Roblox anchors every face's
            # tiles at an object +Y edge where Y is a face axis, so each face's through-wall grid starts at the OUTER
            # face (on the lattice), never at the 1.75 room face. Unrotated, a run's end face anchored at the room
            # face and stepped 0.25 against the ledge top in the T-corner it stands on (step K).
            out = {"N": (0, 0, -1), "S": (0, 0, 1), "E": (1, 0, 0), "W": (-1, 0, 0)}[wall]
            wall_frame = ((0, 1, 0), out, (out[2], 0, -out[0]))      # Z = X x Y
            def wall_part(label, center_y, height, attrs=None):
                pos = ((along,center_y,cross) if horizontal else (cross,center_y,along))
                m.part(f"Level 2 Room {wall} {label}", pos, (height, WALL, b-a), "Tile", attrs=attrs,
                       frame=wall_frame)
            if plug:
                wall_part("Below Socket "+plug, (CHAMBER_WALL_BOTTOM-2)/2,
                          -2-CHAMBER_WALL_BOTTOM)
                wall_part("Above Socket "+plug, (h+14)/2, h-10)
                wall_part("Plug "+plug, 5, 14, {"SocketPlug": plug})
            else:
                wall_part("Wall Run "+str(j), (CHAMBER_WALL_BOTTOM+h+2)/2,
                          h+2-CHAMBER_WALL_BOTTOM)
            if plug:
                mark = ((along, 0, -d/2) if wall=="N" else
                        (along, 0, d/2) if wall=="S" else
                        (w/2, 0, along) if wall=="E" else (-w/2, 0, along))
                index = int(plug[1:])
                m.marker("Socket", mark, {"N":0,"E":-90,"S":180,"W":90}[wall],
                         Wall=wall, Index=index, Width=12, Height=14)
    for sx in (-1, 1):
        for sz in (-1, 1):
            chamber_corner(m, sx*(w/2-8), sz*(d/2-8), sx, sz)
            for upper in (True, False):
                corner_cove(m, sx*(w/2-8), sz*(d/2-8), sx, sz, h, upper)
    for wall in "NESW":
        wall_coves(m, wall, w, d, h, socket_offsets)
    # The old Chamber_D nook (a free-standing curved sheet with mirrored colliders, F12-A) is dropped: it stood in the
    # pool and cut the new ledge ring. Chamber_D keeps its own size and porthole side.
    # A single daylight aperture, away from the centre socket and its clear lane.
    if w < 64:
        z = -d/2+WALL+.1
        porthole_x=-9 if who=="D" else 11   # ring (r 2.8) clear of the fillet that starts at w/2-8
        # A tiled rim standing on the wall face (no back face against the wall: that would be coplanar with it).
        wall_z, front = -d/2+WALL, z+.16
        # ONE row of tiles round the rim (same rule as the ribs): u = arc at the mid radius, scaled to a whole number
        # of tiles so the closing joint is a joint, on the face and both sides; v across each face centred in the row
        # (trim_v). One segment per tile: every joint lies on a segment edge, so the 0.45-wide annulus (inner arc
        # 16% shorter than the outer) cannot kink a joint across a quad's diagonal. The face annulus used planar box
        # UV: grid corners ('+', 'L') wherever the ring ran oblique.
        # Rim 2.35..2.7: at the 0.5 pitch a trim row must stay under 0.4 wide (trim_v), the old 2.8 outer edge (0.45)
        # would put grout lines 0.025 off both edges.
        rim = 2.7
        rm = (2.35+rim)/2
        n = round(math.tau*rm/TILE)
        k = n*TILE/(math.tau*rm)
        angles = [math.tau*i/n for i in range(n+1)]
        u = [t*rm*k*kit.S for t in angles]
        for r, out in ((rim, 1), (2.35, -1)):
            side = [(porthole_x+r*math.cos(t), 8.2+r*math.sin(t), zz) for zz in (wall_z, front) for t in angles]
            piece(m, "curved", m.raw, side, [(i, i+1, n+2+i, n+1+i) for i in range(n)], "Tile", smooth=True,
                  vertex_uv=[(ut, trim_v(zz-(wall_z+front)/2, front-wall_z)*kit.S) for zz in (wall_z, front) for ut in u],
                  facing=lambda p, o=out: (o*(p[0]-porthole_x), o*(p[1]-8.2), 0))
        face = [(porthole_x+r*math.cos(t), 8.2+r*math.sin(t), front) for r in (2.35, rim) for t in angles]
        piece(m, "curved", m.raw, face, [(i, i+1, n+2+i, n+1+i) for i in range(n)], "Tile", facing=lambda p: (0, 0, 1),
              vertex_uv=[(ut, trim_v(r-rm, rim-2.35)*kit.S) for r in (2.35, rim) for ut in u])
        # Solid luminous disk lies behind the aperture, against the wall Part.
        m.cylinder((porthole_x, 8.2, z+.035), 2.36, .06, "LightWarm", segments=24, axis="Z")
        m.marker("DaylightPorthole", (porthole_x, 8.2, z), Colour="Warm", Range=20)
    else:
        # Below the upper cove's wall tangent (h-1.2), so the glow plane does not cut the cove.
        m.box((10, 13.15, -d/2+WALL+.02), (5.5, 1.2, .08), "LightWarm", bevel=0)
        m.marker("DaylightSlit", (10, 13.15, -d/2+WALL), Colour="Warm", Range=20)
    # F5b: the full footprint, one 4-stud voxel row [F-4, F-0.1]; its edge lies at the walls' outer faces, the ledge
    # tops (0) stay dry and the water meets the ledge faces 0.1 below their top.
    m.attrs["waterRegion"] = {"center": [0, -2.05, 0], "size": [w, 3.9, d],
                               "surfaceY": -.1, "terrainOnly": True}
    m.finish()


def socket_pieces(h=15):
    """Builder-placed pieces for the chamber's lower-cove cut at each socket, authored in the Socket marker's frame
    (origin: outer wall face, aperture centre, floor y=0; +X along the wall; +Z into the room, inner face z=WALL).
    ChamberSocketCove fills the 12-long cut where the Plug stays; ChamberSocketStops closes the two cut ends where
    the Plug is removed and a pipe threshold fills the gap. Both rest on the ledge; the chamber wall and ledge back
    them (a seated R1.5 fillet leaves at most 0.44, collision tolerance 0.6), so they carry no colliders."""
    common = dict(Role="ChamberSocketPiece", Pivot="SocketMarker", Width=2*SOCKET_HALF, CoveRadius=COVE_R,
                  MeshCanCollide=False, MeshCanQuery=False, MeshCanTouch=False)
    point = lambda al, inset, y: (al, y, WALL+inset)
    m = kit.Mesh("ChamberSocketCove", SocketPiece="Cove", **common)
    # Exactly the cut (the chamber's lower cove stops at +-SOCKET_HALF; the old 0.05 butt laid two coves over each
    # other). u = x: the marker's +X runs along the wall and the socket edges are integers, so the chamber cove's
    # u = along meets it in phase; v = cove_v, the chamber cove's own profile (LATTICE_SPEC C13).
    cove_strip(m, point, -SOCKET_HALF, SOCKET_HALF, False, h, (0, 1, 1))
    m.finish()
    m = kit.Mesh("ChamberSocketStops", SocketPiece="Stops", **common)
    for side in (-1, 1):
        x = side*SOCKET_HALF
        verts = [(x, 0, WALL)]
        for k in range(7):
            t = (math.pi/2)*k/6
            verts.append((x, COVE_R-COVE_R*math.sin(t), WALL+COVE_R*(1-math.cos(t))))
        # a fan from the wall/floor corner: the concave arc is star-shaped from there
        # Planar in the socket frame (LATTICE_SPEC C13): v = y, u = z continuing the jamb it abuts at z = WALL. That
        # jamb is the end face of a 1.75-thick Wall Run, oriented so every face anchors its through-wall grid at the
        # OUTER face (z = 0 here, chamber() wall_frame), so u = z on both sides.
        shift = 0
        piece(m, "flat", m.raw, verts, [(0, k, k+1) for k in range(1, 7)], "Tile", facing=lambda p, s=side: (-s, 0, 0),
              vertex_uv=[((v[2]-shift)*kit.S, v[1]*kit.S) for v in verts], phase=(0, 0, shift))
    m.finish()


def check_chamber(name, item):
    """The wall-foot cove rests on ground at y=0 along every straight run and round every corner, the water region
    is the full footprint, and the corner coves meet the straight runs (F1+F2+F4 chambers, F5b)."""
    a = item["attrs"]
    w, d = a["Width"], a["Depth"]
    tops = [(r, r["cf"][1]+r["size"][1]/2) for r in item["parts"] if r["ground"]]

    def ground_top(x, z):
        hits = [top for r, top in tops if inside_box(r, (x, top-.01, z), .001)]
        return max(hits) if hits else None
    probes = []
    for wall in "NESW":
        horizontal = wall in "NS"
        half = (w if horizontal else d)/2-8
        sign = -1 if wall in "NW" else 1
        cross = sign*((d if horizontal else w)/2-WALL-COVE_R)
        for i in range(int(4*half)+1):
            al = -half+i*.5
            probes.append((al, cross) if horizontal else (cross, al))
    for sx in (-1, 1):
        for sz in (-1, 1):
            for i in range(25):
                t = (math.pi/2)*i/24
                r = FILLET-COVE_R
                probes.append((sx*(w/2-8)+sx*r*math.cos(t), sz*(d/2-8)+sz*r*math.sin(t)))
    bad = [(round(x, 2), round(z, 2), ground_top(x, z)) for x, z in probes
           if ground_top(x, z) is None or abs(ground_top(x, z)) > .05]
    assert not bad, (name, "cove foot not on y=0 ground", bad[:6])
    region = a["waterRegion"]
    assert region["center"] == [0, -2.05, 0] and region["size"] == [w, 3.9, d] and region["surfaceY"] == -.1, name
    assert not any("Nook" in r["name"] or "Side Step" in r["name"] for r in item["parts"]+item["colliders"]), name
    return len(probes)


def box_axes(cf):
    """Right, up, back unit vectors of a 4-value yaw or 12-value oriented CFrame record (Roblox axes)."""
    if len(cf) == 12:
        return (Vector((cf[3], cf[6], cf[9])), Vector((cf[4], cf[7], cf[10])), Vector((cf[5], cf[8], cf[11])))
    c, s = math.cos(math.radians(cf[3])), math.sin(math.radians(cf[3]))
    return Vector((c, 0, -s)), Vector((0, 1, 0)), Vector((s, 0, c))


def visible_parts(item, skip=()):
    return [r for r in item["parts"] if r.get("properties", {}).get("Transparency", 0) < 1 and r["name"] not in skip]


def part_triangles(rec):
    """12 triangles of a Part box, each with its outward normal."""
    import numpy as np
    c, axes, half = Vector(rec["cf"][:3]), box_axes(rec["cf"]), [v/2 for v in rec["size"]]
    out = []
    for k in range(3):
        a, b = [j for j in range(3) if j != k]
        for s in (-1, 1):
            n = axes[k]*s
            o = c+n*half[k]
            q = [o+axes[a]*sa*half[a]+axes[b]*sb*half[b] for sa, sb in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
            out += [(np.array([q[0], q[1], q[2]]), np.array(n)), (np.array([q[0], q[2], q[3]]), np.array(n))]
    return out


def mesh_triangles(item):
    """Exported mesh triangles in Roblox studs (component frame)."""
    import numpy as np
    mesh = item["mesh"]
    mesh.calc_loop_triangles()
    co = np.array([v.co[:] for v in mesh.vertices], float)/kit.S
    co = np.stack([co[:, 0], co[:, 2], -co[:, 1]], 1)
    return [co[list(t.vertices)] for t in mesh.loop_triangles]


def overlap_area(P, Q, n):
    """Area of the overlap of two coplanar triangles (3x3 arrays) with plane normal n (Sutherland-Hodgman)."""
    import numpy as np
    u = np.cross(n, (1, 0, 0) if abs(n[0]) < .9 else (0, 1, 0))
    u /= np.linalg.norm(u)
    v = np.cross(n, u)

    def ccw(T):
        T = [(float(p @ u), float(p @ v)) for p in T]
        s = (T[1][0]-T[0][0])*(T[2][1]-T[0][1])-(T[1][1]-T[0][1])*(T[2][0]-T[0][0])
        return T if s > 0 else T[::-1]
    poly, clipper = ccw(P), ccw(Q)
    for i in range(3):
        p, q = clipper[i-1], clipper[i]
        side = lambda w: (q[0]-p[0])*(w[1]-p[1])-(q[1]-p[1])*(w[0]-p[0])
        out = []
        for j in range(len(poly)):
            cur, prv = poly[j], poly[j-1]
            if side(cur) >= 0:
                if side(prv) < 0:
                    t = side(prv)/(side(prv)-side(cur))
                    out.append((prv[0]+t*(cur[0]-prv[0]), prv[1]+t*(cur[1]-prv[1])))
                out.append(cur)
            elif side(prv) >= 0:
                t = side(prv)/(side(prv)-side(cur))
                out.append((prv[0]+t*(cur[0]-prv[0]), prv[1]+t*(cur[1]-prv[1])))
        poly = out
        if len(poly) < 3:
            return 0.0, None
    q = np.array(poly)
    area = .5*abs(np.dot(q[:, 0], np.roll(q[:, 1], 1))-np.dot(q[:, 1], np.roll(q[:, 0], 1)))
    c = q.mean(0)
    plane = float(P[0] @ n)
    return area, c[0]*u+c[1]*v+plane*n


# ----------------------------------------------------------------------------------------------- tile lattice (I2)
# LATTICE_SPEC 2.3/2.4/I2.6: every chamber and corridor frame sits at world phase 0 on the 0.5 lattice, so the kit's own
# numbers decide whether its grout lines continue its neighbours'. check_lattice proves, per component:
#   (a) every visible tiled Part edge lies on local 0.5 (the measured anchor corner then lands on a lattice line,
#       whichever corner Roblox picks); declared exception: a chamber wall's through-wall axis (1.75 thick, inner face
#       at phase 0.25 = the WALL-FACE frame of LATTICE_SPEC 2.4, like the hall walls), outer face on the lattice;
#   (b) every flat tiled mesh triangle with an axis-aligned normal: both UV families run along local axes, pitch 0.5
#       (+-1e-4), lines on local multiples of 0.5;
#   (c) every other tiled triangle (curved trims, the sloped stair floors): tile size within [0.45, 0.55] and grid skew
#       <= 11.5 deg; a 'fan' piece (corner tori, whose radial lines continue the vertical fillet) is exempt along u, a
#       'shear' piece (a stair bore) may skew by its own shear atan(rise/L);
#   joints: wherever a mesh piece's free edge continues onto another piece or a Part face of the same assembly (the
#       component, plus the socket pieces at their markers), every grid family meets its counterpart in phase
#       (<= 0.01 stud), except at curved cuts (a square field met along a line its grid crosses obliquely by a trim whose
#       rows follow that line, LATTICE_SPEC 2.8).
LATTICE_SMOOTH = .94          # same surface across a joint (lattice_audit SMOOTH)
WALL_PART = ("Level 2 Room N ", "Level 2 Room E ", "Level 2 Room S ", "Level 2 Room W ")
TILED = ("Tile", "Aqua")


def lattice_tile():
    tile = kit.MATERIALS["Tile"]["tile_m"]/kit.S/8
    assert abs(tile-TILE) < 1e-9 and abs(kit.MATERIALS["Aqua"]["tile_m"]/kit.S/8-TILE) < 1e-9, \
        ("prkit TILE_M is not the 0.5-stud lattice of LATTICE_SPEC 2.1 (I4 first edit)", tile, TILE)


def wrap_tiles(x):
    """Signed distance (studs) from x to the nearest multiple of TILE."""
    import numpy as np
    x = np.asarray(x, float)/TILE
    return (x-np.round(x))*TILE


def lattice_tris(item, at=None):
    """Tiled triangles of a component as arrays: T (n,3,3) studs, UV (n,3,2) studs of UV, N (n,3), kind (n,),
    piece (n,), optionally placed at a marker cf `at`."""
    import numpy as np
    mesh = item["mesh"]
    name = next(k for k, v in kit.COMPONENTS.items() if v is item)
    mesh.calc_loop_triangles()
    polys = len(mesh.polygons)
    spans = PIECES.get(name, [])
    assert not spans or spans[-1][1] <= polys, (name, "PIECES out of step with the mesh polygons", spans[-1], polys)
    kind_of = np.array(["flat"]*polys, dtype=object)
    piece_of = np.full(polys, -1)
    phase_of = np.zeros((polys, 3))
    for i, (a, b, kind, phase) in enumerate(spans):
        kind_of[a:b], piece_of[a:b], phase_of[a:b] = kind, i, phase
    co = np.array([v.co[:] for v in mesh.vertices], float)/kit.S
    co = np.stack([co[:, 0], co[:, 2], -co[:, 1]], 1)
    uvl = mesh.uv_layers.active.data
    T, UV, K, P, PH = [], [], [], [], []
    for t in mesh.loop_triangles:
        mat = mesh.materials[t.material_index].name.removeprefix("PR_")
        if mat not in TILED:
            continue
        scale = kit.MATERIALS[mat]["tile_m"]/kit.S
        T.append(co[list(t.vertices)])
        UV.append([[uvl[l].uv[0]*scale, uvl[l].uv[1]*scale] for l in t.loops])
        K.append(kind_of[t.polygon_index])
        PH.append(phase_of[t.polygon_index])
        P.append(piece_of[t.polygon_index] if piece_of[t.polygon_index] >= 0 else 10000+t.polygon_index)
    T, UV = np.array(T, float).reshape(-1, 3, 3), np.array(UV, float).reshape(-1, 3, 2)
    if at is not None:
        right, up, back = (np.array(v) for v in box_axes(at))
        T = T @ np.stack([right, up, back]) + np.array(at[:3], float)
    N = np.cross(T[:, 1]-T[:, 0], T[:, 2]-T[:, 0])
    area = np.linalg.norm(N, axis=1)
    N = N/np.maximum(area, 1e-12)[:, None]
    return {"T": T, "UV": UV, "N": N, "kind": np.array(K, dtype=object), "piece": np.array(P, dtype=np.int64),
            "area": area/2, "phase": np.array(PH, float).reshape(-1, 3)}


def uv_gradients(T, UV):
    """Per triangle: G (n,2,3) with UV_k(p) = G_k . p + C_k (studs of UV per stud), C (n,2)."""
    import numpy as np
    e1, e2 = T[:, 1]-T[:, 0], T[:, 2]-T[:, 0]
    a, b, d = (e1*e1).sum(1), (e1*e2).sum(1), (e2*e2).sum(1)
    det = a*d-b*b
    det = np.where(det > 1e-14, det, 1)
    G, C = np.zeros((len(T), 2, 3)), np.zeros((len(T), 2))
    for k in (0, 1):
        du1, du2 = UV[:, 1, k]-UV[:, 0, k], UV[:, 2, k]-UV[:, 0, k]
        x, y = (d*du1-b*du2)/det, (a*du2-b*du1)/det
        G[:, k] = x[:, None]*e1+y[:, None]*e2
        C[:, k] = UV[:, 0, k]-(G[:, k]*T[:, 0]).sum(1)
    return G, C


def visible_tiled(r):
    return r["material"] in TILED and r.get("properties", {}).get("Transparency", 0) < 1


def part_lattice_problems(name, parts):
    """(a): visible tiled Part records, every edge on local 0.5 (chamber wall through-wall axis: see above)."""
    out = []
    for r in parts:
        if not visible_tiled(r):
            continue
        axes, c = box_axes(r["cf"]), r["cf"][:3]
        for i, ax in enumerate(axes):
            j = max(range(3), key=lambda k: abs(ax[k]))
            if abs(abs(ax[j])-1) > 1e-9:
                out.append((name, r["name"], "not axis-aligned", [round(v, 4) for v in ax]))
                continue
            lo, hi = c[j]-r["size"][i]/2, c[j]+r["size"][i]/2
            off = [abs(float(wrap_tiles(v))) for v in (lo, hi)]
            if r["name"].startswith(WALL_PART) and abs(r["size"][i]-WALL) < 1e-9:
                # The room face is off the lattice by design; every face that has this axis must then anchor its
                # tiles (PART_ANCHOR) at the on-lattice outer face, or its grid steps 0.25 against its neighbours.
                for (k, s), anchored in PART_ANCHOR.items():
                    for a_, sa in anchored:
                        edge = c[j]+ax[j]*sa*r["size"][i]/2
                        if a_ == i and abs(float(wrap_tiles(edge))) > 1e-6:
                            out.append((name, r["name"], "face anchors its tiles at the off-lattice room face",
                                        "+-"[s < 0]+"XYZ"[k], "xyz"[j], round(edge, 4)))
            elif max(off) > 1e-6:
                out.append((name, r["name"], "edge off the 0.5 lattice", "xyz"[j], round(lo, 4), round(hi, 4)))
    return out


def triangle_lattice_problems(name, D, shear_deg=0.0):
    """(b) flat axis-aligned triangles and (c) curved / oblique ones."""
    import numpy as np
    out = []
    G, C = uv_gradients(D["T"], D["UV"])
    norm = np.linalg.norm(G, axis=2)
    ok = D["area"] > 1e-6
    axial = np.abs(D["N"]).max(1) > 1-1e-6
    flat = ok & axial & (D["kind"] == "flat")
    for i in np.nonzero(flat)[0]:
        for k in (0, 1):
            g = G[i, k]
            j = int(np.argmax(np.abs(g)))
            sg = 1.0 if g[j] > 0 else -1.0
            if abs(norm[i, k]-1) > 2e-4 or abs(abs(g[j])-norm[i, k]) > 1e-5*max(norm[i, k], 1):
                out.append((name, "flat", int(i), "uv", k, "pitch/axis", [round(float(v), 5) for v in g]))
                continue
            phase = D["UV"][i, 0, k]-sg*(D["T"][i, 0, j]-D["phase"][i, j])
            if abs(float(wrap_tiles(phase))) > 1e-3:
                out.append((name, "flat", int(i), "uv", k, "phase", round(float(wrap_tiles(phase)), 4),
                            D["T"][i].mean(0).round(2).tolist()))
    curved = ok & ~flat
    lo, hi = 1/1.1, 1/.9                                   # tile size 0.5/|G| within [0.45, 0.55]
    for i in np.nonzero(curved)[0]:
        kind = D["kind"][i]
        for k in (0, 1):
            if kind == "fan" and k == 0:
                continue
            if not lo-1e-9 <= norm[i, k] <= hi+1e-9:
                out.append((name, kind, int(i), "uv", k, "tile size", round(float(TILE/max(norm[i, k], 1e-9)), 4),
                            D["T"][i].mean(0).round(2).tolist()))
        cos = abs(float(G[i, 0] @ G[i, 1]))/max(float(norm[i, 0]*norm[i, 1]), 1e-12)
        skew = 90-math.degrees(math.acos(min(1, cos)))
        limit = max(11.5, shear_deg+.5) if kind == "shear" else 11.5
        if skew > limit:
            out.append((name, kind, int(i), "skew", round(skew, 2), D["T"][i].mean(0).round(2).tolist()))
    return out


# Measured anchor corner per Part face, object space (TILE_PHASE.md, lattice_audit.ANCHOR): (face axis, sign) ->
# ((axis 1, anchored sign), (axis 2, anchored sign)); every side face anchors at its top-left seen from outside.
PART_ANCHOR = {(1, 1): ((0, 1), (2, 1)), (1, -1): ((0, 1), (2, -1)), (0, 1): ((1, 1), (2, 1)),
               (0, -1): ((1, 1), (2, -1)), (2, 1): ((1, 1), (0, -1)), (2, -1): ((1, 1), (0, 1))}


def part_face_tris(parts):
    """The tiled Part faces of an assembly as triangles whose UV is the distance from the face's anchored corner along
    its two axes: the grid Roblox draws (a full tile starts at the anchor)."""
    import numpy as np
    T, UV = [], []
    for r in parts:
        if not visible_tiled(r):
            continue
        c, axes, half = np.array(r["cf"][:3], float), [np.array(a) for a in box_axes(r["cf"])], np.array(r["size"])/2
        for (k, s), ((a, sa_), (b, sb_)) in PART_ANCHOR.items():
            n = axes[k]*s
            o = c+n*half[k]
            anchor = o+axes[a]*sa_*half[a]+axes[b]*sb_*half[b]
            q = [o+axes[a]*sa*half[a]+axes[b]*sb*half[b] for sa, sb in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
            if np.cross(q[1]-q[0], q[2]-q[0]) @ n < 0:
                q = q[::-1]
            for tri in ((q[0], q[1], q[2]), (q[0], q[2], q[3])):
                T.append(tri)
                UV.append([((p-anchor) @ axes[a], (p-anchor) @ axes[b]) for p in tri])
    T, UV = np.array(T, float).reshape(-1, 3, 3), np.array(UV, float).reshape(-1, 3, 2)
    N = np.cross(T[:, 1]-T[:, 0], T[:, 2]-T[:, 0])
    area = np.linalg.norm(N, axis=1)
    return {"T": T, "UV": UV, "N": N/np.maximum(area, 1e-12)[:, None], "kind": np.array(["part"]*len(T), dtype=object),
            "piece": (np.arange(len(T))//2+20000).astype(np.int64), "area": area/2, "phase": np.zeros((len(T), 3))}


def merge(*Ds):
    import numpy as np
    return {k: np.concatenate([D[k] for D in Ds]) for k in Ds[0]}


def joint_problems(label, M, pieces_of_interest=None):
    """Grid continuity across every free edge of a mesh piece onto a same-facing surface of another piece of M."""
    import numpy as np
    G, C = uv_gradients(M["T"], M["UV"])
    norm = np.linalg.norm(G, axis=2)
    mesh = (M["kind"] != "part") & (M["area"] > 1e-6)
    out, checked = [], 0
    # free edges per piece: an edge not shared with a same-facing triangle of the same piece
    key = np.round(M["T"]/1e-3).astype(np.int64)
    edges = {}
    for i in np.nonzero(mesh)[0]:
        for k in range(3):
            a, b = tuple(key[i, k]), tuple(key[i, (k+1) % 3])
            edges.setdefault((int(M["piece"][i]),)+tuple(sorted((a, b))), []).append((i, k))
    samples = []
    for members in edges.values():
        for i, k in members:
            if any(j != i and M["N"][j] @ M["N"][i] > LATTICE_SMOOTH for j, _ in members):
                continue
            if pieces_of_interest is not None and int(M["piece"][i]) not in pieces_of_interest:
                continue
            p0, p1, p2 = M["T"][i, k], M["T"][i, (k+1) % 3], M["T"][i, (k+2) % 3]
            t = p1-p0
            L = np.linalg.norm(t)
            if L < .02:
                continue
            t = t/L
            w = p2-p0
            out_dir = -(w-t*(w @ t))
            out_dir /= max(np.linalg.norm(out_dir), 1e-12)
            for lam in (.1, .5, .9):
                samples.append((i, p0+(p1-p0)*lam, t, out_dir))
    if not samples:
        return out, 0
    I = np.array([s[0] for s in samples])
    Q = np.array([s[1] for s in samples])
    TT = np.array([s[2] for s in samples])
    OUT = np.array([s[3] for s in samples])
    probe = Q+OUT*.02
    T0, E1, E2 = M["T"][:, 0], M["T"][:, 1]-M["T"][:, 0], M["T"][:, 2]-M["T"][:, 0]
    d00, d01, d11 = (E1*E1).sum(1), (E1*E2).sum(1), (E2*E2).sum(1)
    den = np.where(np.abs(d00*d11-d01*d01) > 1e-14, d00*d11-d01*d01, 1)
    lo_box, hi_box = M["T"].min(1)-.05, M["T"].max(1)+.05
    sin2 = math.sin(math.radians(2))

    def props(F, valid, G3):
        par = any(valid[f] and abs(F[f, 0])/np.linalg.norm(F[f]) < sin2 for f in (0, 1))
        field = all((not valid[f]) or np.abs(G3[f]).max()/np.linalg.norm(G3[f]) > 1-1e-6 for f in (0, 1))
        return par, field and bool(valid.any())
    hosts = {}
    for s in range(0, len(Q), 256):
        P = probe[s:s+256]
        near = np.all((P[:, None] >= lo_box[None]) & (P[:, None] <= hi_box[None]), axis=2)
        for r, h in zip(*np.nonzero(near)):
            q = s+r
            i = I[q]
            if M["piece"][h] == M["piece"][i] or M["area"][h] <= 1e-6 or M["N"][h] @ M["N"][i] <= LATTICE_SMOOTH:
                continue
            v = P[r]-T0[h]
            dist = abs(float(v @ M["N"][h]))
            if dist > .02:
                continue
            d20, d21 = v @ E1[h], v @ E2[h]
            bv, bw = (d11[h]*d20-d01[h]*d21)/den[h], (d00[h]*d21-d01[h]*d20)/den[h]
            if min(bv, bw, 1-bv-bw) < -1e-6:
                continue
            # the surface the edge really meets: the nearest one (a mesh before a Part face it covers, e.g. a cove
            # over its wall)
            rank = dist+(.001 if M["kind"][h] == "part" else 0)
            if q not in hosts or rank < hosts[q][0]:
                hosts[q] = (rank, h)
    for q, (_, h) in sorted(hosts.items()):
        if True:
            i = I[q]
            checked += 1
            t, sA = TT[q], OUT[q]
            sH = np.cross(M["N"][h], t)
            sH = sH/max(np.linalg.norm(sH), 1e-12)
            sH = sH if sH @ sA >= 0 else -sH
            FA = np.stack([G[i] @ t, G[i] @ sA], 1)
            FH = np.stack([G[h] @ t, G[h] @ sH], 1)
            validA, validH = norm[i] > 1e-6, norm[h] > 1e-6
            parA, fieldA = props(FA, validA, G[i])
            parH, fieldH = props(FH, validH, G[h])
            if (fieldA and not parA and parH) or (fieldH and not parH and parA):
                continue                                           # curved cut (LATTICE_SPEC 2.8)
            qa = Q[q]
            # A family whose lines CROSS the joint continues when its crossings along the joint coincide: the same
            # rate along t (1%) and the same phase; the lines may kink there (a stair bore's sheared barrel meets its
            # plumb reveal at 3.6/7.1 deg). A family PARALLEL to the joint pairs with the other side's parallel
            # family, phase only (a cove's rows may run at its own pitch, LATTICE_SPEC 2.7).
            for f in (0, 1):
                if not validA[f]:
                    continue
                crossing = abs(FA[f, 0])/np.linalg.norm(FA[f]) > sin2
                cands = [g for g in (0, 1) if validH[g] and (abs(FH[g, 0])/np.linalg.norm(FH[g]) > sin2) == crossing]
                if not cands:
                    out.append((label, int(i), int(h), "angle", f, qa.round(2).tolist(), str(M["kind"][i]),
                                str(M["kind"][h])))
                    continue
                if crossing:
                    g = min(cands, key=lambda g: abs(abs(FH[g, 0])-abs(FA[f, 0])))
                    if abs(abs(FH[g, 0])-abs(FA[f, 0])) > .01*abs(FA[f, 0]):
                        out.append((label, int(i), int(h), "pitch along the joint", f, round(float(FA[f, 0]), 4),
                                    round(float(FH[g, 0]), 4), qa.round(2).tolist()))
                        continue
                    sg = 1.0 if FA[f, 0]*FH[g, 0] >= 0 else -1.0
                else:
                    g = cands[0]
                    sg = 1.0 if FA[f, 1]*FH[g, 1] >= 0 else -1.0
                diff = (G[i, f] @ qa+C[i, f])-sg*(G[h, g] @ qa+C[h, g])
                off = abs(float(wrap_tiles(diff)))
                if off > .01:
                    out.append((label, int(i), int(h), "phase", f, round(off, 4), qa.round(2).tolist(),
                                str(M["kind"][i]), str(M["kind"][h])))
    return out, checked


def lattice_assemblies():
    """(label, merged triangles, judged pieces or None) for every tunnel and pipe, and each chamber with ChamberSocketCove at every Socket
    marker (the plug kept). A chamber alone leaves its lower cove cut open at every socket, and with the stops the cut
    ends meet the pipe threshold, which is not in the kit: both would judge an edge against a hidden face. The stops
    fan is held to the flat rule (b); its neighbours there (jamb, threshold side) face the other way."""
    import numpy as np
    out = []
    for name, item in kit.COMPONENTS.items():
        if name.startswith("ChamberSocket"):
            continue
        D = merge(lattice_tris(item), part_face_tris(item["parts"]))
        if name.startswith("Chamber_"):
            placed = []
            for n, mk in enumerate(mk for mk in item["markers"] if mk["name"] == "Socket"):
                P = lattice_tris(kit.COMPONENTS["ChamberSocketCove"], at=mk["cf"])
                P["piece"] = P["piece"]+30000+1000*n
                placed.append(P)
            name, D = f"{name}+ChamberSocketCove", merge(D, *placed)
            # Every socket open: the stops fans against the jambs of the Wall Runs (only the fans' own edges are
            # judged; the cut cove ends meet the pipe threshold, which is not in the kit).
            stops, parts = [], [r for r in item["parts"] if not r["attrs"].get("SocketPlug")]
            for n, mk in enumerate(mk for mk in item["markers"] if mk["name"] == "Socket"):
                P = lattice_tris(kit.COMPONENTS["ChamberSocketStops"], at=mk["cf"])
                P["piece"] = P["piece"]+50000+1000*n
                stops.append(P)
            focus = {int(x) for P in stops for x in np.unique(P["piece"])}
            out.append((f"{name[:-len('+ChamberSocketCove')]}+ChamberSocketStops",
                        merge(lattice_tris(item), part_face_tris(parts), *stops), focus))
        out.append((name, D, None))
    return out


def check_lattice(negatives=True):
    """LATTICE_SPEC I2.6, (a)/(b)/(c)/joints over every component and chamber assembly, plus planted negatives that
    must each fail: a Part shifted 0.25, a flat triangle's UV shifted half a tile, a flat triangle's UV pitch 1% off,
    a curved triangle's tile size 20% off, a curved triangle sheared 15 deg, the reveal's u shifted 0.25 at the
    barrel joint, and the stops fans' u shifted 0.25 against their jambs."""
    import numpy as np
    lattice_tile()
    problems, counts = [], {"parts": 0, "flat": 0, "curved": 0, "joints": 0}
    for name, item in kit.COMPONENTS.items():
        counts["parts"] += sum(visible_tiled(r) for r in item["parts"])
        problems += part_lattice_problems(name, item["parts"])
        D = lattice_tris(item)
        a = item["attrs"]
        shear = math.degrees(math.atan2(a.get("ToY", 0) or 0, a["Length"])) if "Length" in a else 0
        problems += triangle_lattice_problems(name, D, shear)
        flat = (np.abs(D["N"]).max(1) > 1-1e-6) & (D["kind"] == "flat")
        counts["flat"] += int(flat.sum())
        counts["curved"] += int((~flat).sum())
    for label, M, focus in lattice_assemblies():
        found, checked = joint_problems(label, M, focus)
        problems += found
        counts["joints"] += checked
    assert not problems, ("tile lattice (LATTICE_SPEC I2.6)", len(problems), problems[:8])
    CHECKS["lattice"] = counts
    if not negatives:
        return counts
    # Planted negatives: each must be caught.
    caught = {}
    bad = [dict(r, cf=list(r["cf"])) for r in kit.COMPONENTS["Chamber_B"]["parts"]]
    rec = next(r for r in bad if r["name"].startswith("Level 2 Room Ledge"))
    rec["cf"][0] += .25
    caught["part +0.25"] = len(part_lattice_problems("neg", bad))
    D = lattice_tris(kit.COMPONENTS["Pipe_Flat_48"])
    flat_i = int(np.nonzero((np.abs(D["N"]).max(1) > 1-1e-6) & (D["kind"] == "flat") & (D["area"] > 1e-6))[0][0])
    for label, change in (("flat uv +half tile", lambda uv: uv+np.array((TILE/2, 0))),
                          ("flat uv pitch 1%", lambda uv: uv*1.01)):
        E = {k: v.copy() for k, v in D.items()}
        E["UV"][flat_i] = change(E["UV"][flat_i])
        caught[label] = len(triangle_lattice_problems("neg", E))
    cur_i = int(np.nonzero((D["kind"] == "curved") & (D["area"] > 1e-6))[0][0])
    E = {k: v.copy() for k, v in D.items()}
    E["UV"][cur_i] = E["UV"][cur_i]*1.2
    caught["curved size 20%"] = len(triangle_lattice_problems("neg", E))
    E = {k: v.copy() for k, v in D.items()}
    G, _ = uv_gradients(E["T"][cur_i:cur_i+1], E["UV"][cur_i:cur_i+1])
    g1 = G[0, 1]/np.linalg.norm(G[0, 1])
    E["UV"][cur_i, :, 0] += math.tan(math.radians(15))*np.linalg.norm(G[0, 0])*(E["T"][cur_i] @ g1)
    caught["curved skew 15 deg"] = len(triangle_lattice_problems("neg", E))
    tunnel = kit.COMPONENTS["RoundTunnel_Dry_64"]
    E = merge(lattice_tris(tunnel), part_face_tris(tunnel["parts"]))
    reveal = [i for i, (_, _, kind, _) in enumerate(PIECES["RoundTunnel_Dry_64"]) if kind == "curved"][1]
    E["UV"][E["piece"] == reveal, :, 0] += .25
    caught["reveal u +0.25 at the barrel joint"] = len(joint_problems("neg", E, {reveal})[0])
    label, E, focus = next(a for a in lattice_assemblies() if a[0] == "Chamber_A+ChamberSocketStops")
    E["UV"][np.isin(E["piece"], list(focus)), :, 0] += .25
    caught["stops fan u +0.25 against its jamb"] = len(joint_problems("neg", E, focus)[0])
    # Step K: a Wall Run laid unrotated (its pre-K pose: end faces anchor at the 1.75 room face) must be caught.
    bad = [dict(r) for r in kit.COMPONENTS["Chamber_A"]["parts"]]
    k = next(i for i, r in enumerate(bad) if " Wall Run " in r["name"] and len(r["cf"]) == 12)
    R = np.asarray(bad[k]["cf"][3:], float).reshape(3, 3)
    bad[k] = dict(bad[k], cf=[*bad[k]["cf"][:3], 0], size=list(np.abs(R) @ np.asarray(bad[k]["size"], float)))
    caught["wall run unrotated (room-face anchor)"] = len(part_lattice_problems("neg", bad))
    missed = [k for k, v in caught.items() if not v]
    assert not missed, ("check_lattice planted negatives NOT caught", missed, caught)
    CHECKS["latticeNegatives"] = caught
    print("PR_LATTICE " + json.dumps({**counts, "negatives": caught}), flush=True)
    return counts


def check_socket_joins():
    """Every chamber socket x every pipe end (Pipe_Flat / Pipe_Stair4, all lengths, MouthTo and MouthFrom) as the
    builder joins them: plug removed, ChamberSocketStops at the Socket marker, pipe mouth on the chamber's outer wall
    face, pipe axis along the marker's +Z (into the room). No face of the pipe end may lie coplanar (0.005) on a face
    of the chamber or its stops over more than 0.001 stud^2 where either side of the overlap is open air (the room
    above the ledge or the bore above the pipe floor, outside every visible Part). Two Parts touching face to face
    (opposite outward normals) are a butt joint. VERIFY2 08 found the collar's outer edge faces on the socket jambs
    (5.25 stud^2 per chamber, seen through the slit where the pipe circle is tangent to its jambs)."""
    import numpy as np

    def frame(cf):
        R = np.array([list(v) for v in box_axes(cf)]).T       # columns right, up, back
        return np.array(cf[:3], float), R

    def to_local(tris, pos, R):
        return [((T-pos) @ R, None if n is None else n @ R) for T, n in tris]

    def faces(item, skip=()):
        return [(T, None) for T in mesh_triangles(item)]+part_triangles_list(item, skip)

    def part_triangles_list(item, skip):
        return [(T, n) for r in visible_parts(item, skip) for T, n in part_triangles(r)]

    stops = [(T, None) for T in mesh_triangles(kit.COMPONENTS["ChamberSocketStops"])]
    radius, cy, floor_top, window = 6, 6, 1, 8
    pipes = {}
    for name, item in kit.COMPONENTS.items():
        if not name.startswith("Pipe_"):
            continue
        L, rise = item["attrs"]["Length"], item["attrs"]["ToY"]
        base = faces(item)
        # MouthTo: pipe +z is the marker's +Z; MouthFrom: turned 180 degrees about Y.
        for end, M, shift in (("To", np.eye(3), np.array((0, -rise, -L/2))),
                              ("From", np.diag((-1., 1., -1.)), np.array((0, 0, -L/2)))):
            tris = [(T @ M.T+shift, None if n is None else n @ M.T) for T, n in base]
            pipes[(name, end)] = [(T, n) for T, n in tris if T[:, 2].max() > -window]
    visible = {}

    def solid(p, boxes):
        return any(all(abs(float((p-c) @ ax)) < h-1e-4 for ax, h in zip(axes, half)) for c, axes, half in boxes)

    checked = 0
    for cname, item in kit.COMPONENTS.items():
        if not cname.startswith("Chamber_"):
            continue
        for mark in (m for m in item["markers"] if m["name"] == "Socket"):
            plug = f"{mark['attrs']['Wall']}{mark['attrs']['Index']}"
            skip = {r["name"] for r in item["parts"] if r["attrs"].get("SocketPlug") == plug}
            pos, R = frame(mark["cf"])
            near = [(T, n) for T, n in to_local(faces(item, skip), pos, R)
                    if np.abs(T[:, 0]).max() < 8+window and T[:, 2].min() < window and T[:, 2].max() > -window]
            near += stops
            boxes = []
            for r in visible_parts(item, skip):
                rp, rR = frame(r["cf"])
                boxes.append((((np.array(r["cf"][:3])-pos) @ R), [a @ R for a in rR.T], [s/2 for s in r["size"]]))
            for (pname, end), ptris in pipes.items():
                pitem = kit.COMPONENTS[pname]
                pboxes = []
                M = np.eye(3) if end == "To" else np.diag((-1., 1., -1.))
                shift = np.array((0, -pitem["attrs"]["ToY"], -pitem["attrs"]["Length"]/2)) if end == "To" else \
                    np.array((0, 0, -pitem["attrs"]["Length"]/2))
                for r in visible_parts(pitem):
                    rp, rR = frame(r["cf"])
                    pboxes.append((rp @ M.T+shift, [M @ a for a in rR.T], [s/2 for s in r["size"]]))
                allboxes = boxes+pboxes

                def air(p):
                    if solid(p, allboxes):
                        return False
                    inset = p[2]-WALL
                    if abs(p[0]) > SOCKET_HALF-1e-6 and 0 <= inset < COVE_R and 0 <= p[1] < COVE_R and \
                            (COVE_R-inset)**2+(COVE_R-p[1])**2 > COVE_R**2:
                        return False                  # enclosed behind the wall-foot cove beyond the socket edges
                    room = p[2] > WALL+1e-3 and 0 < p[1] < 15
                    bore = p[2] <= WALL+1e-3 and p[0]**2+(p[1]-cy)**2 < radius**2 and p[1] > floor_top
                    return room or bore
                checked += 1
                PT = np.array([T for T, _ in ptris]); CT = np.array([C for C, _ in near])
                pn = np.cross(PT[:, 1]-PT[:, 0], PT[:, 2]-PT[:, 0]); cn = np.cross(CT[:, 1]-CT[:, 0], CT[:, 2]-CT[:, 0])
                pl, cl = np.linalg.norm(pn, axis=1), np.linalg.norm(cn, axis=1)
                pn, cn = pn/np.maximum(pl, 1e-12)[:, None], cn/np.maximum(cl, 1e-12)[:, None]
                parallel = (np.abs(pn @ cn.T) > 1-1e-6) & (pl[:, None] > 1e-9) & (cl[None, :] > 1e-9)
                gap = np.abs(np.einsum("ij,kj->ik", pn, CT[:, 0])-(pn*PT[:, 0]).sum(1)[:, None])
                for i, j in zip(*np.nonzero(parallel & (gap <= .005))):
                    (T, n), (C, m), nt = ptris[i], near[j], pn[i]
                    if n is not None and m is not None and float(n @ m) < -.5:
                        continue                                      # Part against Part, face to face
                    area, at = overlap_area(T, C, nt)
                    if area <= 1e-3:
                        continue
                    # a side where BOTH faces render (a Part outward only, a MeshPart both ways) and there is air
                    sides = [s for s in (1, -1) if (n is None or float(n @ nt)*s > 0) and (m is None or float(m @ nt)*s > 0)]
                    if any(air(at+s*.05*nt) for s in sides):
                        visible.setdefault((cname, plug, pname, end), []).append(
                            (round(area, 3), [round(float(x), 2) for x in at]))
    assert not visible, ("pipe end coplanar with a chamber socket face in open air", list(visible.items())[:4])
    print(f"PR_SOCKET_JOINS chambers x sockets x pipe ends={checked} coplanar-in-air=0", flush=True)
    return checked


def inside_box(rec, point, margin=0):
    """Point query for the 4-value yaw and 12-value oriented CFrame records."""
    cf=rec["cf"]
    delta=Vector(point)-Vector(cf[:3])
    if len(cf)==12:
        axes=(Vector((cf[3],cf[6],cf[9])),
              Vector((cf[4],cf[7],cf[10])),
              Vector((cf[5],cf[8],cf[11])))
    else:
        c,s=math.cos(math.radians(cf[3])),math.sin(math.radians(cf[3]))
        axes=(Vector((c,0,-s)),Vector((0,1,0)),Vector((s,0,c)))
    return all(abs(delta.dot(axis))<=size/2+margin
               for axis,size in zip(axes,rec["size"]))


def check_capsule_walk(name,item):
    """A 2 x 5 player clears the centre route; every circular seam blocks escape."""
    a=item["attrs"]
    length,rise,radius,cy=(a[k] for k in ("Length","ToY","InnerRadius","CircleCentreY"))
    shell=[r for r in item["colliders"] if "Facet" in r["name"]]
    assert len(shell)==(8 if name.startswith("Pipe") else 12)
    fills=[r for r in item["parts"] if r["name"].split(" Corner Fill ")[0].endswith(("MouthFrom","MouthTo"))]
    assert len(fills)==4 and all(r["collide"] for r in fills),name
    narrow=name.startswith("Pipe")
    # F12-E: one lower spandrel box per side per mouth; its top corner nearest the axis lies on the circle and the rest
    # of the box is outside it, from the sill (0 tunnel, 1 pipe) to the collar's outer edge. Coverage of the whole
    # panel is proved separately (check_collar_backing).
    lower=[r for r in item["parts"] if " Lower Corner Fill " in r["name"]]
    assert len(lower)==4 and all(r["collide"] for r in lower),(name,len(lower))
    for r in lower:
        x,y,z=r["cf"][:3]; sx,sy,_=r["size"]
        base=rise if z>0 else 0
        assert abs((abs(x)-sx/2)**2+(y+sy/2-base-cy)**2-radius*radius)<1e-6,(name,r["name"],"step corner off the circle")
        assert abs(y-sy/2-base-(1 if narrow else 0))<1e-6 and abs(abs(x)+sx/2-collar_half(radius))<1e-6,            (name,r["name"],"lower fill off the spandrel")
    ground=[r for r in item["parts"] if r["ground"]]
    variant=a["Variant"]
    for i in range(1,int(length*2)):
        z=-length/2+i*.5
        foot=(1 if narrow else 0)+floor_height(z,length,rise)
        if variant=="Wet": foot=-1.5
        assert any(inside_box(r,(0,foot-.2,z),.03) for r in ground),\
            (name,"no floor",z)
        for y in (foot+.2,foot+1,foot+2,foot+3,foot+4,foot+5):
            for x in (-1,0,1):
                assert not any(inside_box(r,(x,y,z),-.001) for r in shell),\
                    (name,"capsule hits shell",x,y,z)
                assert x*x+(y-cy-floor_height(z,length,rise))**2 < radius*radius,\
                    (name,"capsule outside bore",x,y,z)
    for z in (-length/2, -length/4, 0, length/4, length/2):
        centre=cy+floor_height(z,length,rise)
        for i in range(96):
            angle=math.tau*i/96
            distances=[d/100 for d in range(int((radius-.4)*100),int((radius+.5)*100)+1,5)
                       if any(inside_box(rec,(d/100*math.cos(angle),
                                              centre+d/100*math.sin(angle),z),.001)
                              for rec in shell)]
            assert distances,(name,"circle collision seam",z,angle)
            assert radius-.301<=min(distances)<=radius+.35,\
                (name,"facet strays from tile",z,angle,min(distances))


def check_collar_backing(name, item, step=.2):
    """F12-E: every point of both collar panels (the rectangle |x| <= half width, sill .. top, outside the bore circle;
    hall face, mid depth and inner face) lies within COLLAR_GAP of a collider or colliding Part (facets, roof, crown
    cap, corner fills, lower fills, threshold). Box-expanded test, as collision_audit's tolerance."""
    import numpy as np
    a=item["attrs"]
    length,rise,radius,cy=(a[k] for k in ("Length","ToY","InnerRadius","CircleCentreY"))
    narrow=name.startswith("Pipe")
    half,top,sill=(6,12,1) if narrow else (collar_half(radius),32,0)
    boxes=[]
    for rec in item["colliders"]+[r for r in item["parts"] if r["collide"]]:
        cf=rec["cf"]
        if len(cf)==12:
            R=np.array(cf[3:]).reshape(3,3)
        else:
            c,s=math.cos(math.radians(cf[3])),math.sin(math.radians(cf[3]))
            R=np.array(((c,0,s),(0,1,0),(-s,0,c)))
        boxes.append((np.array(cf[:3]),R,np.array(rec["size"])/2+COLLAR_GAP))
    xs,ys=np.meshgrid(np.arange(-half,half+1e-9,step),np.arange(sill,top+1e-9,step))
    xs,ys=xs.ravel(),ys.ravel()
    keep=xs*xs+(ys-cy)**2>radius*radius
    xs,ys=xs[keep],ys[keep]
    worst=0
    for end in (-1,1):
        base=rise if end>0 else 0
        for z in (end*length/2, end*(length/2+.875), end*(length/2+1.75)):
            P=np.stack([xs,ys+base,np.full(xs.size,z)],1)
            covered=np.zeros(len(P),bool)
            for c,R,h in boxes:
                covered|=np.all(np.abs((P-c)@R)<=h,axis=1)
            assert covered.all(),(name,"collar panel point farther than COLLAR_GAP from collision",
                                  P[~covered][:4].round(2).tolist())
            worst=max(worst,len(P))
    return worst


def component_bvh(item, open_sockets=False):
    """Triangle BVH of the exported mesh and visible native Part records."""
    mesh=item["mesh"]
    mesh.calc_loop_triangles()
    verts=[v.co.copy() for v in mesh.vertices]
    faces=[tuple(t.vertices) for t in mesh.loop_triangles]
    quads=((0,1,2,3),(4,7,6,5),(0,4,5,1),
           (1,5,6,2),(2,6,7,3),(3,7,4,0))
    for part in item["parts"]:
        if open_sockets and part["attrs"].get("SocketPlug"):
            continue
        cf=part["cf"]
        x,y,z=cf[:3]
        sx,sy,sz=part["size"]
        if len(cf)==12:
            right=Vector((cf[3],cf[6],cf[9]))
            up=Vector((cf[4],cf[7],cf[10]))
            back=Vector((cf[5],cf[8],cf[11]))
        else:
            c,s=math.cos(math.radians(cf[3])),math.sin(math.radians(cf[3]))
            right,up,back=Vector((c,0,-s)),Vector((0,1,0)),Vector((s,0,c))
        corners=[(-sx/2,-sy/2,-sz/2),(sx/2,-sy/2,-sz/2),
                 (sx/2,sy/2,-sz/2),(-sx/2,sy/2,-sz/2),
                 (-sx/2,-sy/2,sz/2),(sx/2,-sy/2,sz/2),
                 (sx/2,sy/2,sz/2),(-sx/2,sy/2,sz/2)]
        base=len(verts)
        verts.extend(kit.to_blender(Vector((x,y,z))+right*px+up*py+back*pz)
                     for px,py,pz in corners)
        for a,b,c,d in quads:
            faces.extend(((base+a,base+b,base+c),(base+a,base+c,base+d)))
    return BVHTree.FromPolygons(verts,faces,all_triangles=True,epsilon=0)


def ray_directions():
    directions=[]
    n=320
    phi=math.pi*(3-math.sqrt(5))
    for i in range(n):
        y=1-2*(i+.5)/n
        r=math.sqrt(1-y*y)
        a=i*phi
        directions.append((r*math.cos(a),y,r*math.sin(a)))
    directions.extend(((1,0,0),(-1,0,0),(0,1,0),(0,-1,0),
                       (0,0,1),(0,0,-1)))
    return directions


def allowed_mouth(name,item,origin,direction):
    attrs=item["attrs"]
    length,rise=attrs["Length"],attrs["ToY"]
    radius,cy=attrs["InnerRadius"],attrs["CircleCentreY"]
    sill=1 if name.startswith("Pipe") else 0
    for end in (-1,1):
        plane=end*(length/2+1.75)
        if end*direction[2]<=1e-9:
            continue
        t=(plane-origin[2])/direction[2]
        if t<=0:
            continue
        x=origin[0]+direction[0]*t
        y=origin[1]+direction[1]*t
        base=rise if end>0 else 0
        if y>=base+sill-.03 and x*x+(y-base-cy)**2 <= (radius+.03)**2:
            return True
    return False


def allowed_socket(item,origin,direction):
    attrs=item["attrs"]
    w,d=attrs["Width"],attrs["Depth"]
    for mark in item["markers"]:
        if mark["name"]!="Socket":
            continue
        wall=mark["attrs"]["Wall"]
        axis=2 if wall in "NS" else 0
        plane=(-d/2 if wall=="N" else d/2 if wall=="S" else
               w/2 if wall=="E" else -w/2)
        rate=direction[axis]
        if abs(rate)<1e-9:
            continue
        t=(plane-origin[axis])/rate
        if t<=0:
            continue
        along=origin[0]+direction[0]*t if wall in "NS" else origin[2]+direction[2]*t
        height=origin[1]+direction[1]*t
        off=mark["cf"][0 if wall in "NS" else 2]
        if abs(along-off)<=6.03 and -2.03<=height<=12.03:
            return True
    return False


def escape_check(name,item,open_sockets=False):
    bvh=component_bvh(item,open_sockets)
    attrs=item["attrs"]
    if name.startswith("Chamber"):
        starts=[(x,y,z) for x,z in ((0,0),(-10,0),(10,0),(0,-10),(0,10))
                for y in (1.5,7,13)]
    else:
        length,rise=attrs["Length"],attrs["ToY"]
        starts=[]
        for z in (-length/2+.9,-length/4,0,length/4,length/2-.9):
            base=floor_height(z,length,rise)
            low=1 if name.startswith("Pipe") else 0
            for x,y in ((0,low+1.5),(0,attrs["CircleCentreY"]),
                        (0,attrs["CircleCentreY"]+attrs["InnerRadius"]-2),
                        (-2.5 if low else -8,low+7),
                        (2.5 if low else 8,low+7)):
                starts.append((x,base+y,z))
    directions=ray_directions()
    escapes=[]
    for start in starts:
        origin=kit.to_blender(start)
        for direction in directions:
            dv=Vector((direction[0],-direction[2],direction[1]))
            hit=bvh.ray_cast(origin,dv,1000*kit.S)[0]
            if hit is not None:
                continue
            allowed=(allowed_socket(item,start,direction) if name.startswith("Chamber") and open_sockets else
                     allowed_mouth(name,item,start,direction) if not name.startswith("Chamber") else False)
            if not allowed:
                escapes.append((tuple(round(v,2) for v in start),
                                tuple(round(v,3) for v in direction)))
    print(f"PR_ESCAPE {name} {'open' if open_sockets else 'sealed'} {len(escapes)}",flush=True)
    assert not escapes,(name,escapes[:8])
    return 0


def build():
    for variant in ("Wet", "Dry", "Stair4", "Stair8"):
        for length in (64, 72, 80):
            tunnel(variant, length)
    for length in (16, 24, 32, 48, 64, 80):
        pipe("Flat", length)
    for length in (16, 24, 32, 48, 64, 80):
        pipe("Stair4", length)
    for letter, (w, d) in ROOMS.items():
        chamber(letter, w, d)
    socket_pieces()
    report = {}
    escape_counts={}
    for name, item in kit.COMPONENTS.items():
        count = triangle_count(item["mesh"])
        limit = 4000 if name.startswith("RoundTunnel") or name.startswith("Chamber_") else 1500
        assert count <= limit, (name, count, limit)
        report[name] = count
        if name.startswith("ChamberSocket"):
            assert not (item["parts"] or item["colliders"] or item["markers"]), name
            continue
        assert sum("Roof" in c["name"] for c in item["colliders"]) == 1, name
        assert all("Ceiling" not in rec["name"] and "Skylight" not in rec["name"]
                   for rec in item["parts"]+item["colliders"]), name
        assert all(rec["attrs"].get("Level2_EntityGround")
                   for rec in item["parts"] if rec["ground"]), name
        if name.startswith(("RoundTunnel", "Pipe")):
            assert len(item["colliders"]) <= (12 if name.startswith("Pipe") else 18), name
            check_capsule_walk(name,item)
            check_collar_backing(name,item)
            region=item["attrs"].get("waterRegion")
            if name.startswith("RoundTunnel_Wet"):
                assert region=={"center":[0,-2.05,0],"size":[16,3.9,item["attrs"]["Length"]],
                                "surfaceY":-.1,"terrainOnly":True},name
            else:
                assert region is None,(name,"dry passage carries water")
        if name.startswith("Chamber_"):
            check_chamber(name,item)
        escape_counts[name]=escape_check(name,item)
        if name.startswith("Chamber"):
            escape_counts[name+"_open"]=escape_check(name,item,open_sockets=True)
        for rec in item["parts"]:
            if rec["ground"]:
                assert rec["size"][0]>=4 and rec["size"][2]>=4,(name,rec["name"])
    assert len(report) == 30, len(report)
    CHECKS["socketJoins"] = check_socket_joins()
    check_lattice()
    return report,escape_counts


def collection(name):
    c = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(c)
    return c


def light(col, name, position, target, power, size, color=(1,.88,.72), kind="AREA"):
    lamp = bpy.data.lights.new(name, kind)
    lamp.energy = power
    if kind == "AREA":
        lamp.shape = "DISK"
        lamp.size = size
    lamp.color = color
    obj = bpy.data.objects.new(name, lamp)
    col.objects.link(obj)
    obj.location = kit.to_blender(position)
    obj.rotation_euler = (kit.to_blender(target)-obj.location).to_track_quat("-Z", "Y").to_euler()


def review_water(col, name, width, length, y=-.1, center_z=0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (.18, .48, .39, 1)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (.05, .37, .29, 1)
    bsdf.inputs["Roughness"].default_value = .30
    bsdf.inputs["Metallic"].default_value = 0
    bsdf.inputs["Alpha"].default_value = .52
    mat.surface_render_method = "DITHERED"
    mesh = kit.Mesh(name)
    mesh.box((0,y-.015,center_z), (width,.03,length), "Aqua", bevel=0)
    obj = bpy.data.objects.new(name, mesh.finish(register=False))
    col.objects.link(obj)
    obj.data.materials.clear()
    obj.data.materials.append(mat)


def render(name, component, eye, target, water=None, hall=False, open_plugs=(), lens=None):
    col = collection(name)
    kit.place(col, component)
    info = kit.COMPONENTS[component]
    if component.startswith("Chamber_"):
        # Review the chamber as the builder assembles it: the socket pieces at every Socket marker (stops where the
        # plug is removed and a pipe joins, the cove segment where it stays).
        if open_plugs:
            for obj in list(col.objects):
                if obj.data == info.get("preview"):
                    bpy.data.objects.remove(obj,do_unlink=True)
            for rec in info["parts"]:
                if rec["attrs"].get("SocketPlug") in open_plugs or not rec.get("properties", {}).get("Transparency", 0) < 1:
                    continue
                piece=kit.Mesh("Connected review part")
                piece.box(rec["cf"][:3],rec["size"],rec["material"],bevel=0)
                col.objects.link(bpy.data.objects.new(rec["name"],piece.finish(register=False)))
        for mark in info["markers"]:
            if mark["name"] != "Socket":
                continue
            plug = mark["attrs"]["Wall"]+str(mark["attrs"]["Index"])
            kit.place(col, "ChamberSocketStops" if plug in open_plugs else "ChamberSocketCove", mark["cf"][:3], mark["cf"][3])
        if "N0" in open_plugs:
            # N0 socket: the pipe's +Z mouth is at the chamber's outer N face.
            # Its far collar face reaches the inner face of the 1.75-stud wall.
            pipe_center=-info["attrs"]["Depth"]/2-24
            assert abs(pipe_center+24+1.75-(-info["attrs"]["Depth"]/2+WALL))<1e-6
            kit.place(col,"Pipe_Flat_48",(0,0,pipe_center))
    if water:
        review_water(col, "Review Water " + name, *water)
    if hall:
        # Context beyond the mouth is review-only geometry and never exported.
        radius=kit.COMPONENTS[component]["attrs"]["InnerRadius"]
        edge=collar_half(radius)
        top=32 if radius>10 else 12
        mouth=-kit.COMPONENTS[component]["attrs"]["Length"]/2
        # The collar projects outward from this pivot mouth by 1.75 studs.
        # Align the review wall with that full depth; a wall centered on the
        # pivot protrudes into the bore and draws false triangular side seams.
        wall_z=mouth-1.75/2
        hall_half=39 if radius>10 else 20
        for side in (-1,1):
            p=kit.Mesh("review")
            p.box((side*(hall_half+edge)/2,(top-2)/2,wall_z),
                  (hall_half-edge,top+4,1.75),"Tile",bevel=0)
            col.objects.link(bpy.data.objects.new("Mouth wall flush to collar",p.finish(register=False)))
        for y, height in ((-3,2),(top+1,2)):
            p=kit.Mesh("review")
            p.box((0,y,wall_z),(2*edge,height,1.75),"Tile",bevel=0)
            col.objects.link(bpy.data.objects.new("Mouth wall sill/header",p.finish(register=False)))
        for x in (-38,38):
            p = kit.Mesh("review")
            p.box((x,15,-59), (2,30,25), "Tile", bevel=0)
            col.objects.link(bpy.data.objects.new("Hall wall", p.finish(register=False)))
        p = kit.Mesh("review")
        p.box((0,-.6,-54), (78,1.2,42), "Aqua", bevel=0)
        col.objects.link(bpy.data.objects.new("Hall floor", p.finish(register=False)))
        p = kit.Mesh("review")
        p.box((0,17,-73), (78,34,1.5), "Tile", bevel=0)
        col.objects.link(bpy.data.objects.new("Hall end wall", p.finish(register=False)))
        p = kit.Mesh("review")
        p.box((0,34,-54), (78,1,42), "Tile", bevel=0)
        col.objects.link(bpy.data.objects.new("Hall overhead", p.finish(register=False)))
        for x in (-24,24):
            p = kit.Mesh("review")
            p.cylinder((x,16,-60), 3.5, 32, "Tile", segments=32)
            col.objects.link(bpy.data.objects.new("Hall column", p.finish(register=False)))
        review_water(col, "Hall Water", 78, 42, center_z=-54)
        light(col, "Hall daylight", (8,27,-61), (0,10,-71), 2800, 5)
    if component.startswith("Chamber"):
        light(col, "Window daylight", (-10 if component=="Chamber_D" else 9,11,-25),
              (0,5,0), 210, 3)
        light(col, "Soft green bounce", (-8,11,7), (0,3,0), 180, 12, (.62,.82,.72))
    else:
        light(col, "Hard warm mouth", (1,28,-48), (0,8,-15), 1800, 5)
        light(col, "Dim inner bounce", (-4,16,13), (0,8,0), 280, 12, (.62,.82,.72))
    sun = bpy.data.objects.new("Warm sun", bpy.data.lights.new("Warm sun", "SUN"))
    col.objects.link(sun)
    sun.data.energy = 1.1
    sun.data.color = (1,.87,.69)
    sun.rotation_euler = (.35,-.55,.32)
    scene = bpy.context.scene
    for item in scene.collection.children:
        item.hide_render = item != col
    camera_data = bpy.data.cameras.new("Review camera")
    camera = bpy.data.objects.new("Review camera", camera_data)
    col.objects.link(camera)
    camera.location = kit.to_blender(eye)
    camera.rotation_euler = (kit.to_blender(target)-camera.location).to_track_quat("-Z", "Y").to_euler()
    camera_data.lens = lens or (22 if component.startswith("Round") else 18)
    camera_data.clip_end = 500
    scene.camera = camera
    for mat in bpy.data.materials:      # wrong-facing faces must show in review (G2)
        mat.use_backface_culling = True
    scene.render.filepath = str(REVIEW / (name+".png"))
    bpy.ops.render.render(write_still=True)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    counts,escapes = build()
    kit.EXPORT_DIR = EXPORT
    manifest = kit.export()
    EXPORT.mkdir(parents=True, exist_ok=True)
    (EXPORT/"checks.json").write_text(json.dumps({"triangles": counts,
        "escapeCounts": escapes, **CHECKS,
        "colliderCounts": {name:len(item["colliders"])
                           for name,item in kit.COMPONENTS.items()},
        "components": len(counts), "chunks": len(manifest["chunks"]),
        "status": "offline geometry and export only; Roblox runtime checks pending"}, indent=2))
    REVIEW.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 800
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.world = bpy.data.worlds.new("Green Poolrooms ambient")
    scene.world.use_nodes = True
    bg = scene.world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (.20,.27,.21,1)
    bg.inputs["Strength"].default_value = .40
    scene.view_settings.view_transform = "AgX"
    render("RoundTunnel_Wet_72", "RoundTunnel_Wet_72",
           (1,5,18), (0,11,-43), water=(16,72), hall=True)
    render("RoundTunnel_Wet_Mouth_Corners_72", "RoundTunnel_Wet_72",
           (8,7,-55), (0,13,-28), water=(16,72), hall=True)
    render("RoundTunnel_Wet_Mouth_LowerCorner_72", "RoundTunnel_Wet_72",
           (-4,3.5,-50), (-14,4,-37), water=(16,72), hall=True)
    render("RoundTunnel_Stair8_64", "RoundTunnel_Stair8_64",
           (0,5,-25), (0,10,20))
    # Rib foot (z=18 ring on the Stair8 ramp): buried in the steps, no open slot into the hollow ring.
    render("RoundTunnel_Stair8_RibFoot_72", "RoundTunnel_Stair8_72", (-5,8,11), (-10.8,6,18), lens=30)
    render("Pipe_Flat_48", "Pipe_Flat_48", (0,3,15), (0,6,-22))
    render("Pipe_Flat_Mouth_Corners_48", "Pipe_Flat_48",
           (4,5,-39), (0,6,-15), hall=True)
    render("Pipe_Stair4_48", "Pipe_Stair4_48",
           (0,3,-15), (0,8,18))
    for letter, (w, d) in ROOMS.items():
        render(f"Chamber_{letter}", f"Chamber_{letter}", (1,5,d/2-8), (0,7,-d/2+6), water=(w,d))
    # One fillet per prefab, each a different corner: ledge, corner torus, vertical corner, upper torus.
    for letter, sx, sz in (("A",1,-1),("B",-1,1),("C",1,1),("D",-1,-1)):
        w, d = ROOMS[letter]
        cx, cz = sx*(w/2-8), sz*(d/2-8)
        render(f"Chamber_{letter}_Corner", f"Chamber_{letter}", (cx-sx*10,4.5,cz-sz*10),
               (cx+sx*5,2.5,cz+sz*5), water=(w,d))
    render("Chamber_B_Socket_Kept_E0", "Chamber_B", (10,4,7), (24,2,0), water=(48,64))
    render("Chamber_B_Pipe_Joined", "Chamber_B", (1,5,12), (0,6,-38),
           water=(48,64), open_plugs=("N0",))
    render("Chamber_B_Socket_Open_N0", "Chamber_B", (6,3.5,-21), (0,2,-31),
           water=(48,64), open_plugs=("N0",))
    print("PR_B_OK " + json.dumps({name:{"tris":tris,
        "colliders":len(kit.COMPONENTS[name]["colliders"])}
        for name,tris in counts.items()}), flush=True)


if __name__ == "__main__":
    main()
