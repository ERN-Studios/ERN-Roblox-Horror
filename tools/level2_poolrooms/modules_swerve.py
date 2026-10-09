"""Whole-room Poolrooms swerve skins. Local +X is travel, local +Z is the room side.

Run with Blender -b --factory-startup --python-exit-code 1 -P modules_swerve.py.
All coordinates passed to prkit are Roblox studs.

TILE LATTICE (G:/Roblox/_local/l2fix/impl/LATTICE/LATTICE_SPEC.md 4.7 and I4): Pythagorean S families, so every
joint lands on an integer: (R 20, sin .8, cos .6) Ls 32 Ds 16, (R 15, .8/.6) Ls 24 Ds 12 - both labelled A53 - and
(R 20, .6/.8) Ls 24 Ds 8 - A37; Deg is only the name label, the geometry comes from sin/cos exactly. Corners carry
0.25 straight tails (their pivot stays on the tangent). The section is the arch kit's (deck top .5, nosing .25, the
shared fillet v). The deck is PLANAR on the piece frame's lattice (S: phases 0 / .25, corner: .25 / .25), so it
continues the straight Run Decks and is cut by the curved fillet foot and nosing; the wall band, both fillets and the
hidden rest share one u per station (arc length along the wall-face path, whole tiles between the joints: radial
cross lines, a fan off the wall row like the corner tori); the nosing and pool face follow their own row in whole
tiles. GA's tiling courses (_deck_courses, COURSE_TOL, _fillet_ref, FILLET_TOL) are retired (LATTICE_SPEC 5).
"""
import json
import math
import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import bpy
import prkit as kit

EXPORT = Path("G:/Blender/Level2_Poolrooms/jobs/D/export")
REVIEW = Path("G:/Blender/Level2_Poolrooms/review/D")
HEIGHTS = (34, 42, 52)
# (R, Deg label, sin, cos): LATTICE_SPEC 4.7, deepest first. Ls = 2 R sin, Ds = 2 R (1 - cos), both integers.
S_FAMILIES = ((20, 53, .8, .6), (15, 53, .8, .6), (20, 37, .6, .8))
CORNER_RADII = (24, 32, 48, 64)

# FA: the skin's section IS the straight pieces' (modules_arch): the same R3 fillet polylines (fillet_arc), the deck
# top with the walkway's own nosing and -4.5 skirt, the 1.75 wall. A straight run, a plateau and a swerve piece
# therefore meet at plain butt joints (no overlap: overlapping copies of one surface z-fight), with the grout lines
# continuous: the fillets use the straight coves' v (scaled_v), the nosing the Walkway's (nose_v), and every u starts
# whole on Start and ends whole on End.
from modules_arch import (AXIS_COS, DECK_BOTTOM, DECK_EDGE, DECK_OUT, DECK_TOP, LEAD, N_ARC, TAIL, TILE,  # noqa: E402
                          Mesh,
                          cove_profile, fillet_arc, flat_phase, nose_v, nosing, scaled_v, trims)

WALL = 1.75
BOTTOM = -8         # skin wall bottom, below every basin (deepest -3.5 - 4)
S_PHASE, CORNER_PHASE = (0., 0., .25), (.25, 0., .25)


def swerve_bands(h):
    """The section as five (n, y) polylines in loop order, n inward from the wall face, y from FloorY: the visible
    WALL (floor tangent -> base fillet -> wall face -> top fillet's wall tangent), TOP (top fillet), DECK (the flat
    deck: base fillet's floor tangent -> the deck edge 9.25), NOSE (deck edge -> nosing -> pool face) and the HIDDEN
    rest (under the deck, the wall's back and bottom, into the ceiling slab). Consecutive bands share their end points,
    so together they close the section. Each band carries the v of the straight piece it continues; DECK is planar."""
    base = [(-z, y+DECK_TOP) for z, y in fillet_arc(False)]          # (3, .5) floor tangent -> (0, 3.5)
    top = [(-z, y+h-3) for z, y in fillet_arc(True)]                 # (0, h-3) wall tangent -> (3, h) ceiling
    wall = base + [top[0]]
    vw = scaled_v(wall, N_ARC+1, False)          # == CoveBase's v on the fillet; the flat wall at the true pitch
    vt = scaled_v(top, N_ARC+1, True)            # == CoveTop's v on the fillet
    nose = nosing(DECK_OUT, DECK_TOP, DECK_BOTTOM, 1)               # (9.25,.5) (9.43,.4) (9.5,.2) (9.5,-4.5)
    deck = [base[0], nose[0]]
    # The hidden rest stays within 0.6 of the skin's own colliders (collision audit A2): under the deck, the wall's
    # back and bottom, and over the top fillet .5 into the ceiling slab (a face ON the ceiling plane z-fought the
    # Overhead Tile where the skin leaves the wall; the wall's back reaches 2 into the slab).
    hidden = [nose[-1], (0, DECK_BOTTOM), (0, BOTTOM), (-WALL, BOTTOM), (-WALL, h+2), (-.3, h+2), (-.3, h+.5),
              (3, h+.5), top[-1]]
    vh = [0.0]
    for a, b in zip(hidden, hidden[1:]):
        vh.append(vh[-1]+math.dist(a, b))
    lift = (BOTTOM-vh[3]) % TILE                  # the wall's back (point 3 -> 4) carries v = y: rows on the lattice,
    vh = [v+lift for v in vh]                     # continuing a plateau wall Part's back face behind the skin
    return {"WALL": (wall, vw), "TOP": (top, vt), "DECK": (deck, [0.0, 0.0]), "NOSE": (nose, nose_v(nose, 0)),
            "HIDDEN": (hidden, vh)}


def swerve_profile(h):
    """The closed section (n, y), for checks: the bands joined end to end."""
    b = swerve_bands(h)
    deck = b["DECK"][0]+b["NOSE"][0][1:]
    return deck[::-1][:-1] + b["WALL"][0][:-1] + b["TOP"][0][:-1] + b["HIDDEN"][0][::-1][:-1]


PROUD = .05    # the wall band starts at least this far proud of a hall wall slab face (z-fight and lattice_audit's
               # COLLINEAR; the slab runs behind the whole swerve wall, Kit World Builder shell)


def _proud_angle(radius):
    """An S's PROUD station: the first whole tile of arc (s = k * TILE from the joint) where the wall row stands PROUD
    off the slab. The band starts there, so its 0.05..0.075 lip falls on a grout line (the band's u ~ s, the slab's
    lines at whole tiles from the integer joint) instead of mid-tile (R15 at .06: s 1.34, a stray line up the wall)."""
    s = TILE
    while radius*(1-math.cos(s/radius)) < PROUD:
        s += TILE
    return s/radius


def _arc_params(theta, spacing, lead, proud=0.0):
    """Station angles 0..theta at about `spacing`/R steps, with a `lead` station after 0 (rows leave a straight
    joint within lead/2) and, given `proud` (an angle), a station where the wall row stands PROUD off the joint's
    plane - returned for a radius-1 arc; the caller scales."""
    steps = max(1, math.ceil(theta/spacing))
    a = [theta*j/steps for j in range(steps+1)]
    if lead and a[1] > 2*lead:
        a.insert(1, lead)
    if proud:
        assert a[1] < proud < a[2]-lead, (a[:3], proud)
        a.insert(2, proud)
    return a


def _path_s(radius, sin, cos, inward, spacing=2.4, lead=LEAD):
    """S path (x, z, heading, s): two opposite arcs of `radius` through theta = atan2(sin, cos), ending at (2R sin,
    +-2R(1-cos)) heading 0; s = arc length along the wall-face path. lead: a station `lead` rad into each end arc."""
    theta = math.atan2(sin, cos)
    first = _arc_params(theta, spacing/radius, lead, lead and _proud_angle(radius))
    second = [theta-a for a in reversed(first)]
    sign = 1 if inward else -1
    points = []
    for a in first:
        points.append((radius*math.sin(a), sign*radius*(1-math.cos(a)), sign*a, radius*a))
    for a in second[1:]:
        x = radius*(2*math.sin(theta)-math.sin(theta-a))
        z = radius*(1-math.cos(theta)+math.cos(theta-a)-math.cos(theta))
        points.append((x, sign*z, sign*(theta-a), radius*(theta+a)))
    end = points[-1]
    assert abs(end[0]-2*radius*sin) < 1e-9 and abs(abs(end[1])-2*radius*(1-cos)) < 1e-9
    return points


FIRST_ARC = math.radians(4.5)   # a corner's first/last arc facet turns 2.25 deg off its tail (see _path_corner)


def _path_corner(radius, spacing=2.4, tails=True):
    """Corner path (x, z, heading, s): a quarter of `radius` turning toward the room, with a TAIL straight before
    (x -.25..0) and after (z R..R+.25) when `tails`; s from the first point. With tails, the first and last arc facets
    span at least FIRST_ARC: on R48/R64 the 2.4-stud stations turn under 4 deg, so the facet next to a tail ran within
    2 deg of the straight and lattice_audit judged the top fillet's ceiling edge there as a straight seam with the
    ceiling Part (the fan's 5% pitch drifted .11..25); at 4.5 it reads as the curve's clean cut (LATTICE_SPEC 2.8)."""
    steps = math.ceil(radius*math.pi/2/spacing)
    angles = [math.pi*j/(2*steps) for j in range(steps+1)]
    if tails and angles[1] < FIRST_ARC:
        inner = max(1, math.ceil((math.pi/2-2*FIRST_ARC)*radius/spacing))
        angles = [0.0]+[FIRST_ARC+(math.pi/2-2*FIRST_ARC)*j/inner for j in range(inner+1)]+[math.pi/2]
    pts = [(radius*math.sin(a), radius*(1-math.cos(a)), a, TAIL+radius*a) for a in angles]
    if not tails:
        return [(x, z, t, s-TAIL) for x, z, t, s in pts]
    return [(-TAIL, 0.0, 0.0, 0.0)] + pts + [(radius, radius+TAIL, math.pi/2, 2*TAIL+radius*math.pi/2)]


STRIPS = {}               # component -> (path, strips, phase): the loft's own (n, y, u, v) grid, for validate's checks


def _slab_ends(kind, direction):
    """Path ends that sit on a Level 2 Hall Wall slab face (the slab runs behind the whole swerve wall): both corner
    tails, an S-In's start and an S-Out's end. A plateau end meets a Swerve Wall Part that stops at the joint."""
    return (0, -1) if kind == "Corner" else (0,) if direction == "In" else (-1,)


def _slab_offset(path, i, end):
    """Wall row's offset at station i off the slab face plane through path end `end` (room side positive)."""
    x, z, _, _ = path[i]
    ex, ez, eh, _ = path[end]
    return -(x-ex)*math.sin(eh)+(z-ez)*math.cos(eh)


def _slab_facets(path, ends, kind, radius):
    """Facets whose wall row stays on a slab face (a corner's tails) or, on an S, within the PROUD station's offset
    (its LEAD facet and the next one, up to the PROUD station). Their wall-plane quads are left out: the slab
    supplies that wall."""
    limit = radius*(1-math.cos(_proud_angle(radius))) if kind == "S" else 0.0
    return {i for i in range(len(path)-1) for e in ends
            if max(abs(_slab_offset(path, i, e)), abs(_slab_offset(path, i+1, e))) < limit+1e-9}


def _lip_failures(path, wall_u, skip, ends):
    """lip: (S) where the wall band starts off the slab (its first kept facet's slab-side station), the band's u
    and the station's distance along the slab from the joint both lie within .02 of a grout line, so the band's
    lip reads as one of the lines, not as a stray line mid-tile."""
    out = []
    for e in ends:
        kept = [i for i in range(len(path)-1) if i not in skip]
        st = kept[0] if e == 0 else kept[-1]+1
        ex, ez, eh, _ = path[e]
        x, z, _, _ = path[st]
        along = (x-ex)*math.cos(eh)+(z-ez)*math.sin(eh)
        if _off_line(wall_u[st]) > .02 or _off_line(along) > .02:
            out.append((e, st, round(wall_u[st], 4), round(along, 4)))
    return out


def _on_slab(a, b):
    """A band quad between rows a and b that lies in the wall face (n 0) or the wall's back (n -WALL) plane."""
    return a[0] == b[0] and a[0] in (0, -WALL)
VISIBLE = ("WALL", "TOP", "DECK", "NOSE")


def _row(path, n):
    return [(x-math.sin(t)*n, z+math.cos(t)*n) for x, z, t, _ in path]


def _fitted(path, n, kind, radius):
    """u per station along row n (studs): whole tiles from Start to End. A corner's tails keep the true pitch (half
    a tile each) and its arc takes whole tiles; an S fits its whole length."""
    pts = _row(path, n)
    cum = [0.0]
    for a, b in zip(pts, pts[1:]):
        cum.append(cum[-1]+math.dist(a, b))
    if kind == "Corner":
        arc = cum[-2]-cum[1]
        k = max(1, round(arc/TILE))*TILE/arc
        return [0.0]+[TILE/2+(c-cum[1])*k for c in cum[1:-1]]+[TILE/2+(cum[-2]-cum[1])*k+TILE/2]
    k = max(1, round(cum[-1]/TILE))*TILE/cum[-1]
    return [c*k for c in cum]


def _shared_u(path, rows, kind, wall):
    """u per station per row of the bands that share the wall row's u (WALL, TOP, HIDDEN). Every row advances with
    the wall row (radial cross lines, a fan off it), except on an S's two LEAD facets, where each row takes its own
    true length: those facets run within 2 deg of the straight neighbour, so lattice_audit judges the fillet's
    floor/ceiling-tangent edge there as a straight seam with the ceiling Part. The two facets curve opposite ways
    through the same angle, so their offsets cancel and every row ends on the wall row's whole tile."""
    if kind != "S":
        return [[w]*len(rows) for w in wall]
    pts = _row(path, 0)
    k = wall[-1]/sum(math.dist(a, b) for a, b in zip(pts, pts[1:]))
    last = len(path)-2
    out = [[0.0]*len(rows)]
    for i in range(len(path)-1):
        step = [math.dist(*_row(path[i:i+2], n))*k if i in (0, last) else wall[i+1]-wall[i] for n, _, _ in rows]
        out.append([p+d for p, d in zip(out[-1], step)])
    return out


def _strips(path, h, kind, radius, phase):
    """{band, rows [(n, y, v)], u [[u per row] per station], ref (the wall row's u)}. WALL, TOP and HIDDEN share the
    wall row's u (_shared_u); NOSE follows the pool-edge row (n 9.5); DECK is planar (u, v from the positions)."""
    bands = swerve_bands(h)
    wall_u = _fitted(path, 0, kind, radius)
    nose_u = _fitted(path, DECK_OUT, kind, radius)
    out = []
    for band, (section, v) in bands.items():
        rows = [(n, y, vv) for (n, y), vv in zip(section, v)]
        if band == "DECK":
            u = [[(x-math.sin(t)*n)-phase[0] for n, _, _ in rows] for x, z, t, _ in path]
            rows = [(n, y, None) for n, y, _ in rows]
        elif band == "NOSE":
            u = [[w]*len(rows) for w in nose_u]
        else:
            u = _shared_u(path, rows, kind, wall_u)
        out.append({"band": band, "rows": rows, "u": u, "ref": nose_u if band == "NOSE" else wall_u})
    return out


def _vertex_v(strip, i, j, path, phase):
    n, y, v = strip["rows"][j]
    if v is not None:
        return v
    x, z, t, _ = path[i]
    return (z+math.cos(t)*n)-phase[2]          # DECK: planar along local z


def _loft(name, path, collision_path, h, kind, phase, **attrs):
    # A corner's tails carry axis-aligned pool faces (start z = 9.5, end x = R - 9.5): they keep the nosing's v.
    rule = trims(("z", DECK_OUT), ("x", attrs["Radius"]-DECK_OUT)) if kind == "Corner" else None
    m = Mesh(name, phase, rule, Height=h, WallThickness=WALL, DeckWidth=10,
             DeckTop=DECK_TOP, WallBottom=BOTTOM, DeckBottom=DECK_BOTTOM, **attrs)

    def local(point):
        px, y, pz = point
        nearest = min(path, key=lambda p: (px-p[0])**2+(pz-p[1])**2)
        sn, cs = math.sin(nearest[2]), math.cos(nearest[2])
        return -(px-nearest[0])*sn+(pz-nearest[1])*cs, y, sn, cs

    def toward(n0, y0):
        def face(point):
            n, y, sn, cs = local(point)
            return (-sn*(n0-n), y0-y, cs*(n0-n))
        return face

    def wall_face(point):
        n, y, sn, cs = local(point)
        return (-sn, 0, cs) if y > 3+DECK_TOP+.01 else toward(3, 3+DECK_TOP)(point)

    def deck_face(point):
        n, y, sn, cs = local(point)
        return (-sn, 0, cs) if n > DECK_OUT-.01 and y < DECK_TOP-.31 else \
            (-.4*sn, 1, .4*cs) if n > DECK_EDGE-.06 else (0, 1, 0)

    def hidden_face(point):
        n, y, sn, cs = local(point)
        if y < DECK_BOTTOM+.01 and n > .01:
            return (0, -1, 0)
        if y < BOTTOM+.01:
            return (0, -1, 0)
        if y > h-.01 and n > -WALL+.01:
            return (0, 1, 0)
        return (sn, 0, -cs) if n < -WALL+.01 else (-sn, 0, cs)
    facing = {"WALL": wall_face, "TOP": toward(3, h-3), "DECK": deck_face, "NOSE": deck_face, "HIDDEN": hidden_face}
    # Each band is its own strip (its own vertices, so its own u and v); the strips share their edges geometrically.
    strips = _strips(path, h, kind, attrs["Radius"], phase)
    STRIPS[name] = (path, strips, phase)
    slab = _slab_facets(path, _slab_ends(kind, attrs.get("Direction")), kind, attrs["Radius"])
    for strip in strips:
        rows = strip["rows"]
        q = len(rows)
        vertices, uv = [], []
        for i, ((x, z, heading, _), us) in enumerate(zip(path, strip["u"])):
            sn, cs = math.sin(heading), math.cos(heading)
            for j, ((n, y, _), uu) in enumerate(zip(rows, us)):
                vertices.append((x-sn*n, y, z+cs*n))
                uv.append((uu*kit.S, _vertex_v(strip, i, j, path, phase)*kit.S))
        faces = [(i*q+j, (i+1)*q+j, (i+1)*q+j+1, i*q+j+1)
                 for i in range(len(path)-1) for j in range(q-1) if not (i in slab and _on_slab(rows[j], rows[j+1]))]
        m.raw(vertices, faces, "Tile", smooth=True, facing=facing[strip["band"]], vertex_uv=uv)
    # The two open ends: the section's own polygon, hidden in the neighbour's butt joint (closes the solid).
    loop = swerve_profile(h)
    for (x, z, heading, _) in (path[0], path[-1]):
        sn, cs = math.sin(heading), math.cos(heading)
        m.raw([(x-sn*n, y, z+cs*n) for n, y in loop], [tuple(range(len(loop)))], "Tile")
    radius = attrs["Radius"]
    s_bend = kind == "S"
    half = (len(collision_path)-1)//2
    for i, (a, b) in enumerate(zip(collision_path, collision_path[1:]), 1):
        dx, dz = b[0]-a[0], b[1]-a[1]
        length = math.hypot(dx, dz)
        yaw = kit.yaw_x_along(dx, dz)
        heading = math.atan2(dz, dx)
        sn, cs = math.sin(heading), math.cos(heading)
        mx, mz = (a[0]+b[0])/2, (a[1]+b[1])/2
        # Chord boxes overlap their neighbours (and run .5 past a corner's tangents over its 0.25 tails). Their centre
        # is behind the wall face, with only .025 stud nominal front overlap.
        extension = .5
        chain = (f"{'A' if i <= half else 'B'} {i if i <= half else i-half}"
                 if s_bend else str(i))
        m.collider(f"Swerve Wall Block {chain}", (mx+.8*sn, (h-6)/2, mz-.8*cs),
                   (length*(radius+1.75)/radius+2*extension, h+10, 1.75), yaw=yaw)
        m.collider(f"Swerve Deck Ground {chain}", (mx-5.0*sn, (DECK_TOP+DECK_BOTTOM)/2, mz+5.0*cs),
                   (length*(radius+9.5)/radius+2*extension, DECK_TOP-DECK_BOTTOM, 9.4), ground=True, yaw=yaw)
        m.collider(f"Swerve Base Cove Fill {chain}", (mx-.25*sn, .7, mz+.25*cs),
                   (length+2*extension, 1.1, 1.1), yaw=yaw)
        m.collider(f"Swerve Top Cove Fill {chain}", (mx-1.2*sn, h, mz+1.2*cs),
                   (length+2*extension, .6, 3.0), yaw=yaw)
    start, end = path[0], path[-1]
    m.marker("Start", (start[0], 0, start[1]), yaw=0)
    m.marker("End", (end[0], 0, end[1]), yaw=kit.yaw_x_along(math.cos(end[2]), math.sin(end[2])))
    m.finish()
    return m


def _spacing(radius):
    return min(math.sqrt(2*(radius-9.5)), radius*math.sqrt(2/(radius+9.5)))


def swerve_s(radius, deg, sin, cos, direction, h):
    assert direction in ("In", "Out")
    return _loft(f"SwerveS_{direction}_R{radius}_A{deg}_H{h}",
                 _path_s(radius, sin, cos, direction == "In"),
                 _path_s(radius, sin, cos, direction == "In", _spacing(radius), 0), h, "S", S_PHASE,
                 Kind="S", Direction=direction, Radius=radius, Angle=deg, Sin=sin, Cos=cos,
                 Length=round(2*radius*sin, 6), Depth=round(2*radius*(1-cos), 6))


def swerve_corner(radius, h):
    return _loft(f"SwerveCorner_R{radius}_H{h}", _path_corner(radius),
                 _path_corner(radius, _spacing(radius), tails=False), h, "Corner", CORNER_PHASE,
                 Kind="Corner", Radius=radius, Angle=90, Tail=TAIL)


def build():
    for h in HEIGHTS:
        for radius, deg, sin, cos in S_FAMILIES:
            for direction in ("In", "Out"):
                swerve_s(radius, deg, sin, cos, direction, h)
        for radius in CORNER_RADII:
            swerve_corner(radius, h)


def _inside(record, point):
    x, y, z, yaw = record["cf"]
    dx, dz = point[0]-x, point[2]-z
    a = math.radians(yaw)
    cs, sn = math.cos(a), math.sin(a)
    lx, lz = cs*dx-sn*dz, sn*dx+cs*dz
    sx, sy, sz = record["size"]
    return abs(lx) <= sx/2+1e-5 and abs(point[1]-y) <= sy/2+1e-5 and abs(lz) <= sz/2+1e-5


def _samples(path):
    for a, b in zip(path, path[1:]):
        length = math.hypot(b[0]-a[0], b[1]-a[1])
        count = math.ceil(length/.5)
        for j in range(count):
            t = j/count
            yield (a[0]+t*(b[0]-a[0]), a[1]+t*(b[1]-a[1]),
                   math.atan2(b[1]-a[1], b[0]-a[0]))
    yield path[-1][:3]


def _face_offset(path, point):
    px, pz = point
    nearest = (float("inf"), 0)
    for a, b in zip(path, path[1:]):
        dx, dz = b[0]-a[0], b[1]-a[1]
        t = max(0, min(1, ((px-a[0])*dx+(pz-a[1])*dz)/(dx*dx+dz*dz)))
        ex, ez = px-a[0]-t*dx, pz-a[1]-t*dz
        distance = ex*ex+ez*ez
        if distance < nearest[0]:
            nearest = (distance, (-dz*ex+dx*ez)/math.hypot(dx, dz))
    return nearest[1]


def _off_line(v):
    """Distance (v studs) from v to the nearest grout line."""
    return abs(v/TILE-round(v/TILE))*TILE


def _straight_v(h):
    """{(n, y): v} of the straight neighbours' meshes on the swerve section: CoveBase's and CoveTop's fillets
    (scaled_v, base level DECK_TOP and h-3) and Walkway_Straight's nosing (nose_v, from the deck edge)."""
    out = {}
    for top, lift in ((False, DECK_TOP), (True, h-3)):
        prof = cove_profile(top)
        for (z, y), v in list(zip(prof, scaled_v(prof, N_ARC+1, top)))[:N_ARC+1]:
            out[(round(-z, 4), round(y+lift, 4))] = v
    nose = nosing(DECK_OUT, DECK_TOP, DECK_BOTTOM, 1)
    for (n, y), v in zip(nose, nose_v(nose, 0)):
        out[(round(n, 4), round(y, 4))] = v
    return out


def _tiling_failures(path, strips, h, phase):
    """Lattice tiling checks on the loft's own grid (u, v in studs; one tile = TILE). Returns {check: [failures]}.
    size:   every visible path-mapped triangle: tile size along v in [.9, 1.1] tile, grid skew <= 11.5 deg (|cos|
            <= .2); along u in [.9, 1.1] on the wall row (n 0) and on every NOSE row (the fillets and the rest fan
            off the wall row: radial cross lines, one u per station, like the corner tori).
    joint:  at both ends every WALL/TOP/NOSE row sits on a grout line (u 0 at Start, whole at End); the first and
            last chord turn at most 2 deg off the joint (the rows leave a straight neighbour's within 2 deg); every row
            the straight neighbours share carries their v; every station of a band shares one u (radial lines).
    planar: the DECK carries u = local x - px, v = local z - pz at every vertex (the lattice, LATTICE_SPEC 2.8).
    double: where two path-mapped strips meet (WALL/TOP), the first grout line on each side is the same line or the
            two lie at least half a tile apart."""
    fails = {"size": [], "joint": [], "planar": [], "double": []}
    neighbour = _straight_v(h)

    def point(i, n, y):
        x, z, t, _ = path[i]
        return (x-math.sin(t)*n, y, z+math.cos(t)*n)
    for end in (0, -2):
        a, b = path[end], path[end+1]
        turn = abs(math.degrees(math.atan2(b[1]-a[1], b[0]-a[0])-(a[2] if end == 0 else b[2])))
        if turn > 2+1e-9:
            fails["joint"].append(("chord turns off the joint", end, round(turn, 3)))
    fails["joint"] += _arc_entry_failures(path)
    ends = []
    for k, s in enumerate(strips):
        if s["band"] not in VISIBLE:
            continue
        rows, u = s["rows"], s["u"]
        if s["band"] == "DECK":
            for i in range(len(path)):
                for j, (n, y, _) in enumerate(rows):
                    x, yy, z = point(i, n, y)
                    if abs(u[i][j]-(x-phase[0])) > 1e-6 or abs(_vertex_v(s, i, j, path, phase)-(z-phase[2])) > 1e-6:
                        fails["planar"].append((k, i, j, round(u[i][j], 4), round(x, 4)))
            continue
        lead = 2*math.sin(LEAD/2)*1.02
        for i in range(len(path)):
            if any(abs(w-s["ref"][i]) > abs(n)*lead+1e-9 for w, (n, _, _) in zip(u[i], rows)) or                     (i in (0, len(path)-1) and max(u[i])-min(u[i]) > 1e-9):
                fails["joint"].append((k, s["band"], "cross line not radial (beyond the LEAD facets' offset)", i))
        for i in range(len(path)-1):
            for j in range(len(rows)-1):
                for tri in (((i, j), (i+1, j), (i+1, j+1)), ((i, j), (i+1, j+1), (i, j+1))):
                    P = [point(a, *rows[b][:2]) for a, b in tri]
                    e1, e2 = [[P[c][d]-P[0][d] for d in range(3)] for c in (1, 2)]
                    t1, t2 = [(u[tri[c][0]][tri[c][1]]-u[i][j], rows[tri[c][1]][2]-rows[j][2]) for c in (1, 2)]
                    cross = (e1[1]*e2[2]-e1[2]*e2[1], e1[2]*e2[0]-e1[0]*e2[2], e1[0]*e2[1]-e1[1]*e2[0])
                    det = t1[0]*t2[1]-t1[1]*t2[0]
                    if math.hypot(*cross) < 1e-6:
                        continue
                    if abs(det) < 1e-9:
                        fails["size"].append((k, s["band"], i, j, "collapsed uv"))
                        continue
                    du = [(e1[d]*t2[1]-e2[d]*t1[1])/det for d in range(3)]
                    dv = [(e2[d]*t1[0]-e1[d]*t2[0])/det for d in range(3)]
                    su, sv = math.hypot(*du), math.hypot(*dv)
                    cos = sum(a*b for a, b in zip(du, dv))/(su*sv)
                    banded_u = s["band"] == "NOSE" or (j == 0 and rows[0][0] == 0 and rows[1][0] == 0)
                    if i in (0, len(path)-2) and s["band"] != "NOSE" and not .97 <= su <= 1.03:
                        # the first/last facet: true pitch on every WALL/TOP row (the top fillet's ceiling edge
                        # meets the ceiling Part there as a straight seam)
                        fails["size"].append((k, s["band"], i, j, "end facet u", round(su, 3)))
                    if not (.9 <= sv <= 1.1 and abs(cos) <= .2 and (not banded_u or .9 <= su <= 1.1)):
                        fails["size"].append((k, s["band"], i, j, round(su, 3), round(sv, 3), round(cos, 3)))
        wall_row = [rows.index(r) for r in rows if r[0] == 0]
        if s["band"] == "WALL" and wall_row:
            for i in range(len(path)-1):
                j = wall_row[0]
                d = math.dist(point(i, *rows[j][:2]), point(i+1, *rows[j][:2]))
                if not .9 <= d/max(abs(u[i+1][j]-u[i][j]), 1e-12) <= 1.1:
                    fails["size"].append((k, "WALL row u", i, round(d, 4), round(u[i+1][j]-u[i][j], 4)))
        for i in (0, -1):
            for j, uu in enumerate(u[i]):
                if (abs(uu) > 1e-6 if i == 0 else _off_line(uu) > 1e-4):
                    fails["joint"].append((k, s["band"], "end row off a grout line", i, j, round(uu, 4)))
        for n, y, v in rows:
            key = (round(n, 4), round(y, 4))
            if key in neighbour and _off_line(v-neighbour[key]) > 1e-4:
                fails["joint"].append((k, s["band"], "v phase differs from the straight neighbour", key, v))
        if s["band"] in ("WALL", "TOP"):
            for b in (0, len(rows)-1):
                vb = rows[b][2]
                inward = 1 if any(r[2] > vb for r in rows) else -1
                first = (-inward*vb) % TILE
                first = 0 if min(first, TILE-first) < 1e-4 else first
                if first <= max(abs(r[2]-vb) for r in rows)+1e-9:
                    ends.append((k, (round(rows[b][0], 4), round(rows[b][1], 4)), first))
    for a in range(len(ends)):
        for b in range(a+1, len(ends)):
            (ka, pa, fa), (kb, pb, fb) = ends[a], ends[b]
            if ka != kb and pa == pb and not (fa == 0 and fb == 0) and fa+fb < TILE/2:
                fails["double"].append((strips[ka]["band"], strips[kb]["band"], pa, round(fa, 4), round(fb, 4)))
    return fails


def _arc_entry_failures(path):
    """A corner's first and last ARC facets (next to its straight tails) turn more than 2 deg off the tail, so the
    fillet's curved edges read as cuts, not as straight seams with a fan pitch (FIRST_ARC)."""
    out = []
    if path[0][2] == path[1][2] == 0 and abs(path[1][0]-path[0][0]-TAIL) < 1e-9:
        for a, b, t in ((path[1], path[2], path[1][2]), (path[-3], path[-2], path[-2][2])):
            turn = abs(math.degrees(math.atan2(b[1]-a[1], b[0]-a[0])-t))
            if turn < 2+1e-9:
                out.append(("arc facet next to a tail runs within 2 deg of it", round(turn, 3)))
    return out


def _band_polys(path, strips, skip):
    """The band quads as the loft emits them (local studs), with the on-slab quads of the facets in `skip` left out."""
    out = []
    for s in strips:
        rows = s["rows"]
        for i in range(len(path)-1):
            for j in range(len(rows)-1):
                if i in skip and _on_slab(rows[j], rows[j+1]):
                    continue
                out.append([(x-math.sin(t)*n, y, z+math.cos(t)*n)
                            for (x, z, t, _), (n, y, _) in ((path[i], rows[j]), (path[i+1], rows[j]),
                                                            (path[i+1], rows[j+1]), (path[i], rows[j+1]))])
    return out


def _slab_failures(path, polys, ends, kind):
    """slab:  no wall-face (n 0) or wall-back (n -WALL) polygon lies within .05 of a Hall Wall slab plane over its
            whole extent (coplanar overlap: world_audit 08 z-fight; the corner tails' band was exactly on it).
    proud: (S) every such polygon stands at least .05 off the slab plane at its slab end (the band starts proud,
            not as a sliver .007 off the slab: a z-fight risk at distance)."""
    fails = {"slab": [], "proud": []}
    for poly in polys:
        offs = [_face_offset(path, (x, z)) for x, _, z in poly]
        plane = 0 if all(abs(o) < 1e-4 for o in offs) else -WALL if all(abs(o+WALL) < 1e-4 for o in offs) else None
        if plane is None:
            continue
        for e in ends:
            ex, ez, eh, _ = path[e]
            d = [-(x-ex)*math.sin(eh)+(z-ez)*math.cos(eh)-plane for x, _, z in poly]
            if max(map(abs, d)) < .05:
                fails["slab"].append((e, plane, [round(c, 3) for c in poly[0]]))
            elif kind == "S" and min(map(abs, d)) < .05-1e-9:
                fails["proud"].append((e, plane, round(min(map(abs, d)), 4)))
    return fails


def _planted(path, strips, mode):
    """Planted defects (each must fail its check): 'u' = the wall row's u on the nosing too (one u for every row, the
    old loft) -> size; 'row' = each row's own arc length with no whole-tile fit -> joint; 'v' = the pre-lattice fillet
    v (0 at the floor tangent: half a tile off the straights) -> joint; 'planar' = the deck's grid moved a quarter
    tile -> planar; 'lead' = every row on the wall row's u in the end facets too (pure fan) -> size; 'skew' = the
    wall band's u sheared by half its v (|cos| .45) -> size; 'double' = the top fillet's v moved .1 so its first line
    runs .1 off the wall band's last -> double."""
    out = []
    wall = next(s for s in strips if s["band"] == "WALL")["u"]
    wall_rows = next(s for s in strips if s["band"] == "WALL")["rows"]
    for s in strips:
        rows, u = list(s["rows"]), [list(r) for r in s["u"]]
        if mode == "u" and s["band"] == "NOSE":
            u = [[wall[i][0]]*len(rows) for i in range(len(path))]
        elif mode == "row" and s["band"] in ("WALL", "TOP", "NOSE"):
            for j, (n, _, _) in enumerate(rows):
                pts = _row(path, n)
                d = [0.0]
                for a, b in zip(pts, pts[1:]):
                    d.append(d[-1]+math.dist(a, b))
                for i in range(len(path)):
                    u[i][j] = d[i]
        elif mode == "v" and s["band"] == "WALL":
            rows = [(n, y, v-TILE/2) for n, y, v in rows]
        elif mode == "lead" and s["band"] in ("WALL", "TOP"):
            u = [[s["ref"][i]]*len(rows) for i in range(len(path))]
        elif mode == "planar" and s["band"] == "DECK":
            u = [[w+TILE/4 for w in r] for r in u]
        elif mode == "skew" and s["band"] == "WALL":
            u = [[w+.5*v for w, (_, _, v) in zip(r, rows)] for r in u]
        elif mode == "double" and s["band"] == "TOP":
            keys = {(r[0], r[1]) for r in (wall_rows[0], wall_rows[-1])}
            b = next(b for b in (0, len(rows)-1) if (rows[b][0], rows[b][1]) in keys)
            inward = 1 if any(r[2] > rows[b][2] for r in rows) else -1
            rows = [(n, y, v-inward*.1) for n, y, v in rows]
        out.append({"band": s["band"], "rows": rows, "u": u, "ref": s["ref"]})
    return out


def validate():
    expected = {f"SwerveS_{d}_R{r}_A{a}_H{h}" for h in HEIGHTS
                for r, a, _, _ in S_FAMILIES for d in ("In", "Out")}
    expected |= {f"SwerveCorner_R{r}_H{h}" for h in HEIGHTS for r in CORNER_RADII}
    assert expected <= kit.COMPONENTS.keys() and len(expected) == 30
    for name in sorted(expected):
        c = kit.COMPONENTS[name]
        a = c["attrs"]
        radius = a["Radius"]
        corner = name.startswith("SwerveCorner")
        path, strips, phase = STRIPS[name]
        collision_path = (_path_corner(radius, _spacing(radius), tails=False) if corner else
                          _path_s(radius, a["Sin"], a["Cos"], a["Direction"] == "In", _spacing(radius), 0))
        for p, q in zip(collision_path, collision_path[1:]):
            assert math.dist(p[:2], q[:2]) <= 2*math.sqrt(.5*radius)+1e-5, name
            assert (radius+9.5)*(1-math.cos(abs(q[2]-p[2])/2)) <= .25+1e-5, name
        if not corner:
            # LATTICE_SPEC 4.7: Pythagorean families, integer length and depth.
            assert abs(a["Length"]-round(a["Length"])) < 1e-9 and abs(a["Depth"]-round(a["Depth"])) < 1e-9, name
            assert abs(path[-1][0]-a["Length"]) < 1e-9 and abs(abs(path[-1][1])-a["Depth"]) < 1e-9, name
        else:
            assert path[0][:2] == (-TAIL, 0.0) and abs(path[-1][1]-radius-TAIL) < 1e-12, (name, "tails")
        c["mesh"].calc_loop_triangles()
        assert len(c["mesh"].loop_triangles) <= 4000, name
        assert len(c["markers"]) == 2 and c["markers"][0]["name"] == "Start"
        start, end = c["markers"][0]["cf"], c["markers"][1]["cf"]
        assert math.dist((start[0], start[2]), path[0][:2]) < .01, name
        assert math.dist((end[0], end[2]), path[-1][:2]) < .01, name
        assert abs(end[3]-math.degrees(-path[-1][2])) < .05, name
        walls = [b for b in c["colliders"] if b["name"].startswith("Swerve Wall")]
        deck = [b for b in c["colliders"] if b["name"].startswith("Swerve Deck")]
        assert len(walls) == len(deck) and all(b["ground"] for b in deck), name
        for b in walls:
            x, _, z, yaw = b["cf"]
            sx, _, sz = b["size"]
            ang = math.radians(yaw)
            cs, sn = math.cos(ang), math.sin(ang)
            for lx in (-sx/2, sx/2):
                for lz in (-sz/2, sz/2):
                    pt = (x+cs*lx+sn*lz, z-sn*lx+cs*lz)
                    assert _face_offset(path, pt) <= .3+1e-5, (name, "wall protrusion", pt)
        h = a["Height"]
        for x, z, angle in _samples(path):
            sn, cs = math.sin(angle), math.cos(angle)
            face = (x+.1*sn, .5, z-.1*cs)  # n=-.1, behind room face
            assert any(_inside(b, face) for b in walls), (name, "wall gap", face)
            assert any(_inside(b, (face[0], h-.5, face[2])) for b in walls), (name, "upper wall gap", face)
            for n in (3, 5, 7, 9):
                p = (x-n*sn, DECK_TOP-.02, z+n*cs)
                assert any(_inside(b, p) for b in deck), (name, "deck gap", p)
        # The visible profile uses the F1 concave quarter circles verbatim, reflected from F1's local z=-n and lifted
        # to the deck top.
        for n, y in swerve_profile(h):
            if 0 <= n <= 3 and DECK_TOP <= y <= 3+DECK_TOP:
                assert abs(math.hypot(n-3, y-3-DECK_TOP)-3) < .01, (name, "base profile", n, y)
            if 0 <= n <= 3 and h-3 <= y <= h:
                assert abs(math.hypot(n-3, y-(h-3))-3) < .01, (name, "top profile", n, y)
        # FA: butt joints. No vertex reaches past the Start or End section, every u on Start is a grout line at 0
        # and every u on End a whole tile (read back from the mesh: 8 tiles per UV unit, whatever prkit's tile_m).
        mesh = c["mesh"]
        uvl = mesh.uv_layers.active.data
        sx_, sz_, sh = path[0][:3]
        ex_, ez_, eh = path[-1][:3]
        for poly in mesh.polygons:
            if abs(poly.normal[2]) > .999:
                continue                    # the planar deck: its lines across a joint are judged by 'planar'
            for li in (poly.loop_indices if len(poly.vertices) == 4 else ()):   # the band quads (caps are hidden)
                co = mesh.vertices[mesh.loops[li].vertex_index].co
                x, z = co.x/kit.S, -co.y/kit.S
                behind = (x-sx_)*math.cos(sh)+(z-sz_)*math.sin(sh)
                ahead = (x-ex_)*math.cos(eh)+(z-ez_)*math.sin(eh)
                assert behind > -1e-4 and ahead < 1e-4, (name, "mesh passes its Start/End section", behind, ahead)
                u = uvl[li].uv[0]*8*TILE
                if abs(behind) < 1e-4:
                    assert _off_line(u) < 1e-3, (name, "u off a grout line on Start", u)
                if abs(ahead) < 1e-4:
                    assert _off_line(u) < 1e-3, (name, "u ends off a grout line", u)
        fails = _tiling_failures(path, strips, h, phase)
        assert not any(fails.values()), (name, "tiling", {k: v[:3] for k, v in fails.items() if v})
        # The Hall Wall slab runs behind the whole swerve wall: no band face may lie on it (read back from the mesh),
        # with planted negatives: every on-slab quad kept (slab), an S keeping its PROUD-station facet (proud).
        ends = _slab_ends("Corner" if corner else "S", a.get("Direction"))
        kind = "Corner" if corner else "S"
        polys = [[(mesh.vertices[v].co.x/kit.S, mesh.vertices[v].co.z/kit.S, -mesh.vertices[v].co.y/kit.S)
                  for v in poly.vertices] for poly in mesh.polygons]
        slab = _slab_failures(path, polys, ends, kind)
        assert not any(slab.values()), (name, "on the hall wall slab", {k: v[:3] for k, v in slab.items() if v})
        skip = _slab_facets(path, ends, kind, radius)
        assert skip and not any(_slab_failures(path, _band_polys(path, strips, skip), ends, kind).values()), name
        assert _slab_failures(path, _band_polys(path, strips, set()), ends, kind)["slab"], (name, "planted slab")
        if not corner:
            lead_only = {i for i in skip if max(abs(_slab_offset(path, j, e)) for j in (i, i+1) for e in ends) < .02}
            assert len(lead_only) == 1 and _slab_failures(path, _band_polys(path, strips, lead_only), ends,
                                                          kind)["proud"], (name, "planted proud")
            # the band's lip on a grout line, with a planted negative: the band from the LEAD station (u ~.39)
            wall_u = next(st for st in strips if st["band"] == "WALL")["ref"]
            assert not _lip_failures(path, wall_u, skip, ends), (name, "lip", _lip_failures(path, wall_u, skip, ends))
            assert _lip_failures(path, wall_u, lead_only, ends), (name, "planted lip")
        if corner:      # the uniform 2.4-stud stations (the old corner path) put a near-straight facet by each tail
            steps = math.ceil(radius*math.pi/2/2.4)
            old = [path[0]]+[(radius*math.sin(t), radius*(1-math.cos(t)), t, 0.0)
                             for t in (math.pi*j/(2*steps) for j in range(steps+1))]+[path[-1]]
            assert _arc_entry_failures(old) or 90/steps > 4, (name, "planted near-straight arc facet not caught")
        for mode, check in (("u", "size"), ("row", "joint"), ("v", "joint"), ("planar", "planar"), ("skew", "size"),
                            ("double", "double"))+                (() if corner else (("lead", "size"),)):     # a corner's end facets are its straight tails
            assert _tiling_failures(path, _planted(path, strips, mode), h, phase)[check], (name, mode, check)
        # Flat faces: every axis-aligned tiled face of the piece is planar on its phase (Mesh.finish) or a declared
        # trim (a corner tail's pool face carries the nosing's v).
        checked = 0
        for t in mesh.loop_triangles:
            nr = (t.normal[0], t.normal[2], -t.normal[1])
            ax = max(range(3), key=lambda i: abs(nr[i]))
            if abs(nr[ax]) < AXIS_COS:
                continue
            P = [mesh.vertices[v].co for v in t.vertices]
            cen = [sum(p.x for p in P)/3/kit.S, sum(p.z for p in P)/3/kit.S, -sum(p.y for p in P)/3/kit.S]
            ph = flat_phase(name, cen, ax)
            if ph is None:
                continue
            axes = [i for i in range(3) if i != ax]
            for li, v in zip(t.loops, t.vertices):
                co = mesh.vertices[v].co
                loc = (co.x/kit.S, co.z/kit.S, -co.y/kit.S)
                uv = [w*8*TILE for w in uvl[li].uv]
                got = sorted(_off_line(w) for w in uv)
                want = sorted(_off_line(loc[i]-ph[i]) for i in axes)
                assert all(abs(g-w) < 1e-3 for g, w in zip(got, want)), (name, "flat face off its phase", cen)
            checked += 1
        print("PASS", name, "tris", len(c["mesh"].loop_triangles), "colliders", len(c["colliders"]),
              "flat tris", checked, flush=True)
    print("SWERVE_VALIDATE PASS 30; face/deck coverage, wall protrusion, sagitta, markers, profile, tris; lattice "
          "size/skew/joint/planar/double and hall-wall slab/proud/lip, each with a planted negative; flat faces on their phase", flush=True)
    return expected


def _render(name, pieces, eye, target, ortho=True, extra=()):
    col = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(col)
    for component, x, z, yaw in pieces:
        kit.place(col, component, (x, 0, z), yaw=yaw)
    for make in extra:
        make(col)
    for child in bpy.context.scene.collection.children:
        child.hide_render = child != col
    cam = bpy.data.objects.new("Review Camera", bpy.data.cameras.new("Review Camera"))
    col.objects.link(cam)
    cam.location = kit.to_blender(eye)
    cam.rotation_euler = (kit.to_blender(target)-cam.location).to_track_quat("-Z", "Y").to_euler()
    if ortho:
        cam.data.type = "ORTHO"
        cam.data.ortho_scale = 110*kit.S
    else:
        cam.data.lens = 22
    bpy.context.scene.camera = cam
    bpy.context.scene.render.filepath = str(REVIEW / (name+".png"))
    bpy.ops.render.render(write_still=True)
    col.objects.unlink(cam)
    bpy.data.objects.remove(cam)


def swerve_wall_review(h=42):
    """A swerve wall laid as the builder lays it on the lattice (South wall frame turned half round: local +X the
    travel, +Z the room): a straight run (CoveBase/CoveTop/Walkway_Straight + Run Deck Part + wall Part), S-in R15,
    a plateau run at Ds 12, S-out, a straight, SwerveCorner_R24 with its tails, then the next wall. Parts are tiled
    by the measured rule (modules_arch.part_box)."""
    import modules_arch as A
    if "CoveBase24" not in kit.COMPONENTS:
        A.build()                       # the straight neighbours (after the export: job D stays swerve-only)
    col = A.collection("PR-D swerve wall")
    inn, out = f"SwerveS_In_R15_A53_H{h}", f"SwerveS_Out_R15_A53_H{h}"
    Ls, Ds = 24, 12
    # The wall face line is z = 0 (boundary at z = -1.75), the room +z; pieces in this frame are placed unrotated
    # (yaw 0 = the builder's wallPose * half turn on a North wall).

    def straight(x0, x1, d):
        for prefix, y in (("CoveBase", DECK_TOP), ("CoveTop", h-3), ("Walkway_Straight", 0)):
            s = x0
            for p in A.compose(x1-x0):
                A.place(col, prefix+str(p), (s+p/2, y, d), 180)
                s += p
        A.part_box(col, "Run Deck", ((x0+x1)/2, (DECK_TOP+DECK_BOTTOM)/2, d+DECK_EDGE/2),
                   (x1-x0, DECK_TOP-DECK_BOTTOM, DECK_EDGE), yaw=0)
        if d:                           # a plateau run's own wall; the hall wall slab backs everything at d = 0
            A.part_box(col, "Wall", ((x0+x1)/2, (h+2-8)/2, d-.875), (x1-x0, h+10, 1.75), yaw=0)
    straight(-30, 0, 0)
    A.place(col, inn, (0, 0, 0), 0)
    straight(Ls, Ls+8, Ds)
    A.place(col, out, (Ls+8, 0, Ds), 0)
    straight(2*Ls+8, 2*Ls+30, 0)
    tangent = 2*Ls+30+TAIL
    A.place(col, f"SwerveCorner_R24_H{h}", (tangent, 0, 0), 0)
    # The Hall Wall slab runs behind the whole swerve wall (Kit World Builder): the S pieces' LEAD facets and the
    # corner's tails carry no wall band of their own (_slab_facets), this face is that wall.
    A.part_box(col, "Hall Wall", ((tangent-30)/2, (h+2-8)/2, -.875), (tangent+30, h+10, 1.75), yaw=0)
    A.part_box(col, "Basin", (40, -2.5, 30), (200, 1, 100), "Aqua")
    for p in ((10, 30, 25), (60, 30, 30), (110, 30, 40)):
        A.light(col, "Lamp", p, (p[0], 0, p[2]-10), 6000, 12)
    shots = [("D1_top_cove_band", (6, h-8, 22), (10, h-1, 4)),
             ("D3_base_fillet_joint", (-4, 3, 10), (2, 1.5, 1)),
             ("D9_fillet_close", (14, 6, 18), (12, 3, 6)),
             ("S1_deck_low", (-8, 2.5, 20), (16, 0, 8)),
             ("S2_plateau_and_out", (30, 4, 34), (40, 1, 10)),
             ("C1_corner_tail_joint", (tangent-14, 4, 16), (tangent+4, 1, 4)),
             ("C2_corner_overview", (tangent-10, 30, 30), (tangent+14, 0, 14))]
    for name, eye, target in shots:
        A.camera_render(col, name+".png", eye, target, folder=REVIEW)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for mat in bpy.data.materials:
        mat.use_backface_culling = True
    build()
    validate()
    previous = kit.EXPORT_DIR
    kit.EXPORT_DIR = EXPORT
    manifest = kit.export()
    kit.EXPORT_DIR = previous
    for stale in (EXPORT/"chunks").glob("c*.b64"):
        if stale.name not in {f"c{i:05d}.b64" for i in range(len(manifest["chunks"]))}:
            stale.unlink()
    if "--no-render" in sys.argv:
        print("SWERVE_OK", json.dumps({"components": len(manifest["components"])}), flush=True)
        return
    for mat in bpy.data.materials:
        mat.use_backface_culling = True
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x, scene.render.resolution_y = 1100, 760
    scene.render.resolution_percentage = 100
    scene.world = bpy.data.worlds.new("Review World")
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (.7, .78, .88, 1)
    scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.2
    sun = bpy.data.objects.new("Review Sun", bpy.data.lights.new("Review Sun", "SUN"))
    bpy.context.scene.collection.objects.link(sun)
    sun.rotation_euler = (.35, -.5, -.6)
    sun.data.energy = 2.5
    REVIEW.mkdir(parents=True, exist_ok=True)
    h = 42
    inn = f"SwerveS_In_R20_A53_H{h}"
    out = f"SwerveS_Out_R20_A53_H{h}"
    end = _path_s(20, .8, .6, True)[-1]
    _render("01_s_bend", [(inn, 0, 0, 0), (out, end[0], end[1], 0)], (30, 80, 75), (30, 17, 10))
    _render("04_single_in", [(inn, 0, 0, 0)], (16, 65, 60), (16, 17, 8))
    _render("05_single_out", [(out, 0, 0, 0)], (16, 65, 60), (16, 17, -8))
    _render("02_corner", [(f"SwerveCorner_R48_H{h}", 0, 0, 0)], (35, 80, 95), (27, 17, 28))
    scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = .5
    swerve_wall_review(h)
    print("SWERVE_OK", json.dumps({"components": len(manifest["components"]),
          "renders": [str(p) for p in sorted(REVIEW.glob("*.png"))]}), flush=True)


if __name__ == "__main__":
    main()
