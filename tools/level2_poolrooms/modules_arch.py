"""PR-A Poolrooms architecture. All modelling inputs are Roblox studs/axes.

Run headless: D:/Blender/blender.exe -b --factory-startup --python-exit-code 1
  -P G:/Roblox/MongoTV/tools/level2_poolrooms/modules_arch.py --

Frames the World Builder poses (owner fix list 2, FIX_SPEC / ANALYSIS F1, F2, F4, F7, F8, F10, F12):
- WALL-FACE frame (straight coves, CoveBaseStop*, Walkway_Straight*): pivot ON the wall's room face, local +Z points
  into the wall (WallSide '+Z'), the room is -Z, local X runs along the wall. y=0 is the base level (deck top or dry
  floor) for base pieces, and 3 below the ceiling for CoveTop*.
- CORNER frame (CornerCove, CoveBaseCorner/CoveTopCorner, Walkway_Corner_*): pivot at the FILLET CENTRE, the walls
  are the planes x=-R and z=-R, the room is +X/+Z (r < R round the corner).
- BOUNDARY frame (SunSlit, WallVoid): pivot on the wall's OUTER boundary plane, local +Z out of the room.
- CEILING frame (LightWell_*): pivot on the ceiling plane (slab underside C); nothing below y=0.
Every floor-standing solid reaches y=-4 (G4); every oblique collider yaw comes from kit.yaw_x_along (G5).

TILE LATTICE (G:/Roblox/_local/l2fix/impl/LATTICE/LATTICE_SPEC.md, step I4). One global lattice of 0.5-stud tiles
(8 x 8 per texture over 4.0 studs) under the whole level: grout lines at world x, y, z = multiples of 0.5. A kit mesh
carries its grid in its UVs, so every piece puts its lines at fixed local phases (LATTICE_SPEC 2.4: WALL-FACE (0, 0,
.25), CORNER (.25, 0, .25), floor/ceiling pockets (0, 0, 0)); a 90/180-degree turn keeps a phase of 0 or T/2.
- Axis-aligned flat faces are planar at the frame phase (Mesh.finish), except declared trims (pool faces, risers),
  which carry the nosing's v.
- Straight runs are laid unstretched from the LENGTHS pieces between integer joints; their u is local x.
- The R3 fillet's v (scaled_v) is whole at the wall tangent and half a tile at the floor/ceiling tangent, 9.5 tiles
  round the arc, in every cove family (straight, stop, torus, inner corner, swerve skin).
- Corner pieces carry 0.25 straight tails (their ends are integer joints); a torus's radial lines continue its
  vertical CornerCove's (a fan along u); a stop fans to its axis; nosings follow their own path in whole tiles.
"""
import math
import json
import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import bpy
import bmesh
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree
import prkit as kit

EXPORT = Path('G:/Blender/Level2_Poolrooms/jobs/A/export')
REVIEW = Path('G:/Blender/Level2_Poolrooms/review/A')
BUDGETS = {}
AXES = {}                 # component -> {record name: Roblox (x, z) unit direction its local X must take}
EXPECT_TOP = {}           # component -> {ground record name: top y}
TAU = math.tau
S = kit.S
FOOT = -4.0               # G4: floor-standing solids start here
DECK_TOP, DECK_BOTTOM = .5, -4.5   # LATTICE_SPEC 2.6: deck top on the lattice (was .445)
DECK_IN, DECK_OUT = .5, 9.5   # deck from 0.5 inside the wall face to 9.5 into the room
N_ARC = 8                 # fillet segments (11.25 deg, well under prkit's 45 deg sharp-edge rule)

# ------------------------------------------------------------------------------------------- tile lattice (I4)
TILE = .5                 # LATTICE_SPEC 2.1: one tile; 8 x 8 tiles per texture over 4.0 studs
TILE_M = 8*TILE*S         # texture repeat in metres: prkit.TILE_M (4.0 * 0.28, MaterialVariant StudsPerTile 4.0)
assert kit.TILE_M == TILE_M and kit.TILE == TILE, ('prkit is not on the 0.5 lattice', kit.TILE_M, TILE_M)
TILED = ('Tile', 'Aqua')
# LATTICE_SPEC 2.5 run pieces (stretch 1): the 14 lengths plus 11's budget fallback {80, 40, 20, 10, 5}, which the
# World Builder lays where the kit carries them (I1.11: fewer pieces per run inside the 12,349 descendants).
LENGTHS = (128, 96, 80, 64, 48, 40, 32, 24, 20, 16, 12, 10, 8, 6, 5, 4, 3, 2, 1)
TAIL = .25                # corner-piece straight tails: every joint along a wall is an integer
FILLET_TILES = 9.5        # LATTICE_SPEC 2.7: tiles round the R3 fillet's 8-segment polyline (4.705 long)
NOSE_W, NOSE_DROP = .25, .3   # pool-edge nosing: 0.25 deep (deck Part edge 9.25 from the face), 0.3 down
DECK_EDGE = DECK_OUT-NOSE_W   # 9.25: the flat deck's pool-side edge, an integer joint (boundary + 11)
STEP_RISE = .65           # LATTICE_SPEC 2.6: first tread stays .05 under the water surface (FloorY - .1)
INNER_LEG = 3.25          # Cove*InnerCorner legs: runs start at boundary + 5
SQUARE_LEG = 10.25        # Walkway_Corner_R0 legs: deck runs start at boundary + 12
WALL_PH, CORNER_PH, ZERO_PH = (0., 0., .25), (.25, 0., .25), (0., 0., 0.)   # lines at local coordinate = phase
STOP_TIP = math.radians(120)  # a stop closes on a half-radius ring 30 deg past the wall plane (inside the wall)
LEAD = math.radians(1.5)   # a curved piece's first facet off a straight joint: its rows leave the joint within 2 deg
AXIS_COS = .999999           # a face this close to an axis is axis-aligned (0.08 deg; LEAD facets turn .75)
FLAT = {}                 # component -> (frame phase, flat-face rule or None): what Mesh.finish laid, for the checks
UNPLACED = ('Porthole_', 'CurveWall_')   # registered for reference; the World Builder never places them


def _axis_of(n):
    """Roblox axis (0 x, 1 y, 2 z) of a Blender-axis normal when it is axis-aligned, else None."""
    r = (n[0], n[2], -n[1])
    a = max(range(3), key=lambda i: abs(r[i]))
    return a if abs(r[a]) > AXIS_COS else None


def planar(phase=ZERO_PH):
    """Box projection of the LOCAL coordinates, grout lines at local coordinate = phase (mod TILE); metres."""
    px, py, pz = phase

    def uv(co, normal):
        x, y, z = co.x/S-px, co.z/S-py, -co.y/S-pz
        a = max(range(3), key=lambda i: abs(normal[i]))      # Blender axes: 0 x, 1 -z, 2 y
        p, q = ((z, y), (x, y), (x, z))[a]
        return p*S, q*S
    return uv


def trims(*planes):
    """Flat-face rule: an axis-aligned face in one of these (axis letter, local value) planes keeps its own mapping
    (a pool face carries the nosing's v), every other one is planar at the frame phase."""
    def rule(centre, axis):
        for letter, value in planes:
            a = 'xyz'.index(letter)
            if axis == a and abs(centre[a]-value) < 1e-4:
                return None
        return 'frame'
    return rule


class Mesh(kit.Mesh):
    """kit.Mesh on the 0.5 lattice: `phase` is the frame's grout phase (LATTICE_SPEC 2.4); `flat(centre, axis)`
    may return None (keep the face's own mapping), 'frame' or another phase for an axis-aligned face."""

    def __init__(self, name, phase=ZERO_PH, flat=None, **attrs):
        super().__init__(name, **attrs)
        self.phase = phase
        FLAT[name] = (phase, flat)

    def finish(self, register=True):
        self.bm.normal_update()
        for i, (f, fn) in enumerate(self.uvf):
            if not f.is_valid or self.mats[f.material_index] not in TILED:
                continue
            axis = _axis_of(f.normal)
            if axis is None:
                continue
            c = f.calc_center_median()/S
            phase = flat_phase(self.name, (c.x, c.z, -c.y), axis)
            if phase is None:
                continue
            self.uvf[i] = (f, planar(phase))
            if f in self.hints:
                self.hints[f] = (self.hints[f][0], None)
        return super().finish(register)


def flat_phase(name, centre, axis):
    """The grout phase an axis-aligned tiled face of `name` must carry at `centre` (None: a declared trim)."""
    phase, rule = FLAT[name]
    got = rule(centre, axis) if rule is not None else 'frame'
    return phase if isinstance(got, str) else got


def done(m, large=False):
    m.finish()
    BUDGETS[m.name] = 4000 if large else 1500
    return m


def uv_round(radius, offset=0):
    """Cylinder unwrap in metres: u = angle in whole tiles round the full turn (no seam at the wrap), v = height
    + offset (studs) so rows sit on the frame's lattice."""
    count = max(1, round(TAU*radius/TILE))

    def unwrap(co, normal):
        if abs(normal.z) > .8:
            return co.x, co.y
        a = math.atan2(-co.y, co.x) % TAU
        radial = normal.x*co.x + normal.y*co.y
        face_a = (math.atan2(-normal.y, normal.x) +
                  (math.pi if radial < 0 else 0)) % TAU
        a += TAU*round((face_a-a)/TAU)
        return a/TAU*count*TILE*S, co.z + offset*S
    return unwrap


def _profile_lengths(profile):
    s = [0.0]
    for a, b in zip(profile, profile[1:]):
        s.append(s[-1] + math.dist(a, b))
    return s


def tile_fit(length, whole=round):
    """Factor that maps `length` studs of u onto a whole number (>= 1) of 0.5-stud tiles."""
    return max(1, whole(length/TILE))*TILE/length


def scaled_v(profile, arc_points, wall_first):
    """v (studs) per profile point, LATTICE_SPEC 2.7: the first `arc_points` points are the R3 fillet, which carries
    FILLET_TILES (9.5) tiles; v is a whole tile at the WALL tangent (a row line on the wall tangent, on the lattice) and
    half a tile at the FLOOR/CEILING tangent (4.75 from an integer boundary: mid-tile of the floor/ceiling lattice).
    wall_first: the profile starts at the wall tangent (top coves) or at the floor tangent (base coves). The rest
    continues at the true pitch. Shared by every cove family (straight, torus, stop, mitre, swerve skin)."""
    s = _profile_lengths(profile)
    arc = s[arc_points-1]
    k = FILLET_TILES*TILE/arc
    v0 = 0.0 if wall_first else TILE/2
    return [v0+(v*k if i < arc_points else arc*k+v-arc) for i, v in enumerate(s)]


NOSE = ((NOSE_W, 0.0), (NOSE_W*.08/.3, -.1), (0.0, -NOSE_DROP))


def nosing(edge, top, bottom, outward):
    """(along, y) points of the rounded pool edge: NOSE_W wide, NOSE_DROP down; `outward` = toward the pool."""
    return [(edge-outward*a, top+b) for a, b in NOSE] + [(edge, bottom)]


def nose_v(prof, i0):
    """The Walkway nosing's v: 0 (a grout line) at profile point i0, the deck's pool-side edge, then the profile's
    arc length (true pitch) both ways. Every deck section (straight, corner, ring, steps, swerve) uses it."""
    v = [0.0]*len(prof)
    for i in range(i0+1, len(prof)):
        v[i] = v[i-1]+math.dist(prof[i-1], prof[i])
    for i in range(i0-1, -1, -1):
        v[i] = v[i+1]-math.dist(prof[i], prof[i+1])
    return v


def prism_x(m, profile, lo, hi, mat='Tile', smooth=True, v=None):
    """Closed prism along local X over a (y, z) profile. UV: u = local x (grout lines at x = k*TILE: a piece whose
    ends sit on integers starts and ends on a line), v = the given per-point v (default profile arc length).
    Axis-aligned faces (caps, backs, skirts) become planar at the frame phase in Mesh.finish. The closing edge
    (last -> first) must be a hidden face."""
    n = len(profile)
    verts = [(x, y, z) for x in (lo, hi) for y, z in profile]
    faces = [(i, (i+1) % n, (i+1) % n+n, i+n) for i in range(n)]
    faces += [tuple(range(n-1, -1, -1)), tuple(n+i for i in range(n))]
    s = v if v is not None else _profile_lengths(profile)

    def uv(co, normal):
        y, z = co.z/S, -co.y/S
        k = min(range(n), key=lambda i: (profile[i][0]-y)**2 + (profile[i][1]-z)**2)
        return co.x, s[k]*S
    m.raw(verts, faces, mat, uv=uv, smooth=smooth)


def revolve(m, profile, angles, mat='Tile', closed=False, smooth=True, ufun=None, v=None, cx=0.0, tip=None):
    """Solid of revolution about the vertical line x = cx, z = 0. profile: closed simple polygon of (r, y), r >= 0
    (r == 0 points sit on the axis and are shared); angles: polar angles, (x, z) = (cx + r cos a, r sin a).
    closed=True wraps a full turn (do not repeat the first angle); otherwise both ends get flat caps. UV: u =
    ufun(angle, r) in studs (default: arc length from the mid angle at the vertex's own radius; an axis vertex takes
    its face's angle, so a fan converges cleanly), v = per-point v (default profile arc length); horizontal faces and
    end caps planar at the frame phase. tip=(angle, scale): one more ring after the last angle with every radius
    scaled (a solid that closes inside a wall instead of capping on its plane)."""
    verts, index = [], []
    rings = [(a, 1.0) for a in angles] + ([tip] if tip else [])
    for r, y in profile:
        if r < 1e-9:
            verts.append((cx, y, 0.0))
            index.append([len(verts)-1]*len(rings))
        else:
            index.append([])
            for a, k in rings:
                verts.append((cx+k*r*math.cos(a), y, k*r*math.sin(a)))
                index[-1].append(len(verts)-1)
    angles = [a for a, _ in rings]
    k, na = len(profile), len(angles)
    faces = []
    for p in range(k):
        q = (p+1) % k
        for j in (range(na) if closed else range(na-1)):
            jj = (j+1) % na
            f = list(dict.fromkeys((index[p][j], index[p][jj], index[q][jj], index[q][j])))
            if len(f) >= 3:
                faces.append(tuple(f))
    if not closed:
        faces.append(tuple(index[p][0] for p in range(k)))
        faces.append(tuple(index[p][-1] for p in reversed(range(k))))
    s = v if v is not None else _profile_lengths(profile)
    amid = math.pi if closed else (angles[0]+angles[-1])/2
    flat = planar(m.phase)

    def uv(co, normal):
        x, y, z = co.x/S-cx, co.z/S, -co.y/S
        nx, ny, nz = normal.x, normal.z, -normal.y
        if abs(ny) > .999:
            return flat(co, normal)
        r = math.hypot(x, z)
        a = math.atan2(z, x)
        af = math.atan2(nz, nx)
        if r < 1e-6:                                      # an axis vertex: the face's side of the axis is the one
            af = min((af, af+math.pi), key=lambda t: abs((t-amid+math.pi) % TAU-math.pi))   # inside the span
        elif math.cos(a-af) < 0:
            af += math.pi                                 # inward-facing side: the face sits at af + pi
        if not closed and abs(-math.sin(af)*nx + math.cos(af)*nz) > .7:
            return flat(co, normal)                       # flat end cap
        af += TAU*round((amid-af)/TAU)
        a = af if r < 1e-6 else af + (a-af+math.pi) % TAU - math.pi   # the vertex angle next to its face
        i = min(range(k), key=lambda t: (profile[t][0]-r)**2 + (profile[t][1]-y)**2)
        return (ufun(a, r) if ufun else (a-amid)*r)*S, s[i]*S
    m.raw(verts, faces, mat, uv=uv, smooth=smooth)


def revolve_var(m, profile_at, angles, mat='Tile', smooth=True, vfun=_profile_lengths, u_radius=None):
    """revolve() with its own profile per angle (same vertex count, no axis points, both ends capped): a ring whose
    inner face follows a straight line in plan, e.g. the curved stairs cut flush at the deck's pool edge. UV as
    revolve(): planar on flat tops and end caps (and on a plan-straight face once it runs oblique), else arc length
    x own radius (or x u_radius: radial cross lines, no shear where the profile changes radius) by v =
    vfun(profile) (default the profile's arc length)."""
    profiles = [profile_at(a) for a in angles]
    k, na = len(profiles[0]), len(angles)
    assert all(len(p) == k for p in profiles) and all(r > 1e-9 for p in profiles for r, _ in p)
    verts = [(p[t][0]*math.cos(a), p[t][1], p[t][0]*math.sin(a)) for t in range(k) for a, p in zip(angles, profiles)]
    index = [[t*na+j for j in range(na)] for t in range(k)]
    faces = [(index[p][j], index[p][j+1], index[(p+1) % k][j+1], index[(p+1) % k][j])
             for p in range(k) for j in range(na-1)]
    faces.append(tuple(index[p][0] for p in range(k)))
    faces.append(tuple(index[p][-1] for p in reversed(range(k))))
    amid = (angles[0]+angles[-1])/2
    flat = planar(m.phase)

    def uv(co, normal):
        x, y, z = co.x/S, co.z/S, -co.y/S
        nx, ny, nz = normal.x, normal.z, -normal.y
        if abs(ny) > .999:
            return flat(co, normal)
        a = math.atan2(z, x)
        if abs(-math.sin(a)*nx + math.cos(a)*nz) > .7:   # an oblique end cap: tiled in its own plane (radius, y)
            return math.hypot(x, z)*S, y*S
        profile = profile_at(a)
        s = vfun(profile)
        r = math.hypot(x, z)
        i = min(range(k), key=lambda t: (profile[t][0]-r)**2 + (profile[t][1]-y)**2)
        return (a-amid)*(u_radius or r)*S, s[i]*S
    m.raw(verts, faces, mat, uv=uv, smooth=smooth)


def sweep(m, stations, prof, us, vs, mat='Tile', smooth=True):
    """Closed solid: the closed (d, y) section `prof` set at every station (x, z, ix, iz) - a point on the reference
    line (the wall face) and the unit direction d grows along (into the room) - as vertex (x + d*ix, y, z + d*iz).
    UV: u = us[station] (studs) on every row, so the cross lines run square to the path and fan off the reference
    row; v = vs[profile point]. Axis-aligned faces (the deck top, tails' flat faces, the end sections) become planar
    at the frame phase in Mesh.finish."""
    k, n = len(prof), len(stations)
    verts, uvs = [], []
    for i, (x, z, ix, iz) in enumerate(stations):
        for p, (d, y) in enumerate(prof):
            verts.append((x+d*ix, y, z+d*iz))
            uvs.append((us[i], vs[p]))
    tree = KDTree(len(verts))
    for j, P in enumerate(verts):
        tree.insert(kit.to_blender(P), j)
    tree.balance()
    faces = [(i*k+p, i*k+(p+1) % k, (i+1)*k+(p+1) % k, (i+1)*k+p) for i in range(n-1) for p in range(k)]
    faces += [tuple(range(k-1, -1, -1)), tuple((n-1)*k+p for p in range(k))]

    def uv(co, normal):
        j = tree.find(co)[1]
        return uvs[j][0]*S, uvs[j][1]*S
    m.raw(verts, faces, mat, uv=uv, smooth=smooth)


def lathe(m, rings, mat='Tile', n=32, cap=False, offset=0):
    verts = [(r*math.cos(TAU*i/n), y, r*math.sin(TAU*i/n))
             for y, r in rings for i in range(n)]
    faces = [(j*n+i, j*n+(i+1)%n, (j+1)*n+(i+1)%n, (j+1)*n+i)
             for j in range(len(rings)-1) for i in range(n)]
    if cap:
        faces += [tuple(range(n-1, -1, -1)), tuple((len(rings)-1)*n+i for i in range(n))]
    m.raw(verts, faces, mat, uv=uv_round(rings[0][1], offset), smooth=True)


def arc_solid(m, angles, radii, ys, mat='Tile', uv=None):
    """Closed annular sector between radii (inner, outer) with levels ys (bottom..top; extra levels only split the
    side faces), explicit cylindrical UVs; flat tops planar at the frame phase (Mesh.finish)."""
    n, L = len(angles), len(ys)
    def v(level, ring, j):
        return (level*2+ring)*n+j
    verts = [(r*math.cos(a), y, r*math.sin(a)) for y in ys for r in radii for a in angles]
    faces = []
    for j in range(n-1):
        k = j+1
        faces += [(v(0,0,j),v(0,0,k),v(0,1,k),v(0,1,j)), (v(L-1,0,j),v(L-1,1,j),v(L-1,1,k),v(L-1,0,k))]
        for b in range(L-1):
            faces += [(v(b,0,j),v(b+1,0,j),v(b+1,0,k),v(b,0,k)), (v(b,1,j),v(b,1,k),v(b+1,1,k),v(b+1,1,j))]
    for b in range(L-1):
        faces += [(v(b,0,0),v(b,1,0),v(b+1,1,0),v(b+1,0,0)),
                  (v(b,0,n-1),v(b+1,0,n-1),v(b+1,1,n-1),v(b,1,n-1))]
    def cylindrical(co,normal):
        rr=math.hypot(co.x,co.y)
        angle=math.atan2(-co.y,co.x)
        angle+=TAU*round(((angles[0]+angles[-1])/2-angle)/TAU)
        # End faces unwrap across the radius; the round sides use their own arc length.
        radial=(normal.x*co.x+normal.y*co.y)/max(rr,1e-6)
        return (rr if abs(radial)<.5 else (angle-angles[0])*rr),co.z
    cylindrical=uv or cylindrical
    def surface_uv(co,normal):
        if abs(normal.z)>.8:
            return co.x,co.y
        return cylindrical(co,normal)
    m.raw(verts, faces, mat, uv=surface_uv, smooth=True)


def _expect_axis(m, name, dx, dz):
    length = math.hypot(dx, dz)
    AXES.setdefault(m.name, {})[name] = (dx/length, dz/length)


def arc_boxes(m, points, thickness, label, ground=False, vertical=None):
    """Tangent collision boxes, no more than four studs between stations. Local X runs along each chord (G5)."""
    for i, (a, b) in enumerate(zip(points, points[1:])):
        dx, dz = b[0]-a[0], b[1]-a[1]
        length = math.hypot(dx, dz)
        assert length <= 4.01, (m.name, length)
        y, height = vertical if vertical else (0, 1)
        name = label+str(i+1)
        m.collider(name, ((a[0]+b[0])/2, y, (a[1]+b[1])/2),
                   (max(4,length+.12) if ground else length+.12, height, thickness),
                   ground=ground, yaw=kit.yaw_x_along(dx, dz))
        _expect_axis(m, name, dx, dz)


def tangent_box(m, name, r0, r1, a, half, y0, y1, ground=False, shift=0.0):
    """A box spanning radii r0..r1 along polar angle a, 2*half wide tangentially; local X tangent, Z radial. shift
    moves it along the tangent (toward increasing angle) and grows it by |shift| at that end."""
    c = (r0+r1)/2
    tx, tz = -math.sin(a), math.cos(a)
    m.collider(name, (c*math.cos(a)+tx*shift, (y0+y1)/2, c*math.sin(a)+tz*shift), (2*half+2*abs(shift), y1-y0, r1-r0),
               ground=ground, yaw=kit.yaw_x_along(tx, tz))
    _expect_axis(m, name, tx, tz)
    if ground:
        EXPECT_TOP.setdefault(m.name, {})[name] = y1


def sector_boxes(m, label, ri, ro, a0, a1, n, y0, y1, ground=False, exposed='in', extend=0.0):
    """n boxes tiling the annular sector ri..ro, a0..a1 (radians) from y0 to y1.
    exposed='in': the inner edge is the visible edge (no box reaches inside ri; the outer side must be solid, the
    box corners run past ro into it). exposed='out': the outer edge is visible (box corners stay on ro; the inner
    side must be solid). The uncovered slivers stay under ~0.25 stud for the counts used here. extend: the first and
    last box also cover a straight tail that long past a0 / a1 (corner pieces' tails, no extra instances)."""
    da = (a1-a0)/n
    for i in range(n):
        a = a0+(i+.5)*da
        half = ro*math.sin(da/2)
        lo, hi = (ri, ro) if exposed == 'in' else (min(ri*math.cos(da/2)-.1, ro*math.cos(da/2)-4), ro*math.cos(da/2))
        shift = (-extend/2 if i == 0 else 0)+(extend/2 if i == n-1 else 0)
        tangent_box(m, label+str(i+1), max(lo, 0.0) if exposed == 'in' else lo, hi, a, half, y0, y1, ground, shift)


# ------------------------------------------------------------------------------------------------ coves (F1, F2)

FILLET_CENTRE = {False: (-3.0, 3.0), True: (-3.0, 0.0)}      # (z, y) in the wall-face frame


def fillet_arc(top, n=N_ARC):
    """The ONE concave R3 fillet (F1), wall-face frame (z = -depth into the room, y). Base: floor tangent (-3, 0) to
    wall tangent (0, 3) round centre (-3, 3). Top (pivot 3 below the ceiling): wall tangent (0, 0) to ceiling tangent
    (-3, 3) round centre (-3, 0). The solid lies OUTSIDE the circle, so the room sees a hollow."""
    steps = [math.pi/2*i/n for i in range(n+1)]
    if top:
        return [(-3+3*math.cos(a), 3*math.sin(a)) for a in steps]
    return [(-3+3*math.sin(a), 3-3*math.cos(a)) for a in steps]


def cove_profile(top):
    """Closed (z, y) section: the fillet plus a back 0.3 into the wall and, for the base, a skirt to y=-4 (hidden in
    the deck or floor slab); the top cove's back runs up into the ceiling slab (y 3..5). Closing edge is hidden."""
    arc = fillet_arc(top)
    return arc + ([(-3, 5), (.3, 5), (.3, 0)] if top else [(.3, 3), (.3, FOOT), (-3, FOOT)])


FILL = {False: (-.3, .8), True: (2.2, 3.3)}   # Cove Fill y-range; z-range is -0.8..0.3 (0.8 x 0.8 in the corner)


def cove(length, top):
    """CoveBase{L}/CoveTop{L}, L in LENGTHS (128..1): exact length, butt joints, laid unstretched between integer
    joints (LATTICE_SPEC 2.5); u = local x, so both ends sit on a grout line."""
    name = ('CoveTop' if top else 'CoveBase') + str(length)
    m = Mesh(name, WALL_PH, Length=length, Radius=3, WallSide='+Z', WallPlane=0, Profile='concave',
             Base='3 below the ceiling' if top else 'deck top (.5) or dry floor (0)')
    zy = cove_profile(top)
    prism_x(m, [(y, z) for z, y in zy], -length/2, length/2, v=scaled_v(zy, N_ARC+1, top))
    y0, y1 = FILL[top]
    m.collider('Cove Fill', (0, (y0+y1)/2, -.25), (length, y1-y0, 1.1))
    return done(m)


def stop_u(sign, tail):
    """u (studs) of a stop at revolve angle a: whole at the run joint (u continues the run's local x through the
    tail), then 9 tiles over the quarter at u_radius 3 (pitch .524, a fan toward the axis), whole again at 90 deg."""
    k = 9*TILE/(math.pi/2)

    def u(a, r):
        t = abs(a+math.pi/2)
        return sign*(tail+(0.0 if r < 1e-6 and t <= LEAD else t)*k)   # the joint's apex keeps the joint's u
    return u


def cove_stop(sign, corner=False):
    """CoveBaseStop_PX/_NX: the base cove's room part revolved 90 deg about the vertical line where the run's end
    plane meets the wall face (local x=0, z=0): the fillet turns into the wall and dies out 3 studs further on, at
    the hole edge. PX turns toward local +X (pivot at the +X end of a run), NX toward -X. Rotation cannot mirror
    a MeshPart, hence two pieces. Exactly 3 long, never stretched (LATTICE_SPEC C5): v = the run's (scaled_v), u whole
    at the run joint and 9 tiles round the quarter. It has no end cap on the wall plane (where the old one z-fought
    the hall wall face, C5 'edge' rows): past 90 deg it closes on a tip ring inside the wall (30 deg on, half radius),
    clear of the hole's jamb plane too.
    CoveBaseStopCorner_PX/_NX (square-corner 'stop' mode): a 0.25 straight of the run's section, then the same stop;
    pivot at the run end, 3.25 long, dying into the corner's other wall."""
    tail = TAIL if corner else 0.0
    name = 'CoveBaseStop' + ('Corner' if corner else '') + '_' + ('PX' if sign > 0 else 'NX')
    extra = {'ExposedSide': '-Z'} if corner else {}
    m = Mesh(name, WALL_PH, Length=3+tail, Radius=3, WallSide='+Z', WallPlane=0, Profile='concave',
             Direction='+X' if sign > 0 else '-X', Tail=tail, Pivot='run end', **extra)
    zy = cove_profile(False)
    if corner:
        lo, hi = sorted((0.0, sign*tail))
        prism_x(m, [(y, z) for z, y in zy], lo, hi, v=scaled_v(zy, N_ARC+1, False))
        m.marker('TangentWall', (0, 0, .001))       # the wall plane it dies into (collision audit backing plane)
    # The skirt below the floor tangent tapers to r 2.5 at the foot: buried in the deck/floor either way, it no longer
    # lies along the hole's jamb plane at 90 deg (an 'edge' seam with the Hall Wall's jamb face).
    prof = [(-z, y) for z, y in fillet_arc(False)] + [(0, FOOT), (2.5, FOOT)]
    # A 1.5 deg first ring: the first facet's rows then leave the run's within 1 deg (lattice_audit judges a joint
    # whose rows turn more than 2 deg as a step).
    th = [0.0, LEAD] + [math.pi/2*i/N_ARC for i in range(1, N_ARC+1)]
    revolve(m, prof, [-math.pi/2+sign*t for t in th], ufun=stop_u(sign, tail), v=scaled_v(prof, N_ARC+1, False),
            cx=sign*tail, tip=(-math.pi/2+sign*STOP_TIP, .5))
    m.collider('Cove Fill', (sign*(tail+.7)/2, .2, -.2), (tail+.7, 1.0, 1.0))
    return done(m)


def corner_stations(radius, n):
    """Sweep stations of a corner piece in the CORNER frame: the 0.25 tail on wall x=-R (z .25 -> 0), the quarter
    arc (angle pi -> 3pi/2, n segments), the tail on wall z=-R (x 0 -> .25). Each (x, z, inward x, inward z)."""
    st = [(-radius, TAIL, 1.0, 0.0)]
    for i in range(n+1):
        a = math.pi+math.pi/2*i/n
        st.append((radius*math.cos(a), radius*math.sin(a), -math.cos(a), -math.sin(a)))
    return st+[(TAIL, -radius, 0.0, 1.0)]


def corner_tiles(radius):
    """Whole tiles round a corner's quarter at the wall face r = R (LATTICE_SPEC C4: 25/50/75 for R8/16/24)."""
    return round(math.pi/2*radius/TILE)


def corner_fan(radius):
    """The u (studs) every corner piece of radius R carries at a point (x, z) of the CORNER frame: half a tile at
    each tangent (boundary + 1.75 + R is mid-tile), whole tiles round the quarter at r = R, true pitch along the
    tails; one u per angle, so a torus's radial lines continue its vertical CornerCove's."""
    count = corner_tiles(radius)

    def u(x, z):
        if z > 1e-6 and x < 0:
            return TILE/2-z
        if x > 1e-6 and z < 0:
            return TILE*(count+.5)+x
        a = math.atan2(z, x) % TAU
        a = min(max(a, math.pi-.2), 1.5*math.pi+.2)
        return TILE*(.5+(a-math.pi)/(math.pi/2)*count)
    return u


def corner_us(radius, n, count):
    """Per-station u of corner_stations: whole tiles round the quarter (`count`), half a tile along each tail."""
    return [0.0]+[TILE*(.5+count*i/n) for i in range(n+1)]+[TILE*(count+1)]


def cove_corner(radius, top):
    """CoveBaseCorner_R/CoveTopCorner_R in the CORNER frame: the straight fillet swept round the fillet centre with
    the wall at r=R (F1+F2), so it meets CornerCove's surface, plus a 0.25 straight tail at both ends (LATTICE_SPEC
    2.5: the runs start at boundary + 2 + R, an integer). u: CornerCove's at the same angle (corner_fan: radial
    lines continue from the vertical fillet into the torus, a fan .5027 r/R), the straight cove's along the tails;
    v: the straight's (scaled_v). The foot/ceiling arcs are clean cuts (LATTICE_SPEC 2.8)."""
    name = ('CoveTopCorner' if top else 'CoveBaseCorner') + f'_R{radius}'
    m = Mesh(name, CORNER_PH, CornerRadius=radius, FilletRadius=3, Profile='concave',
             Interior='positive X and positive Z', Tail=TAIL, ArcTiles=corner_tiles(radius))
    # R24 takes 20 segments (4.5 deg): the foot/ceiling arc's first facet then turns 2.25 deg off the tail, so it
    # reads as the curve it is (a clean cut of the deck/ceiling grid, LATTICE_SPEC 2.8), not as a straight seam.
    n = 16 if radius <= 16 else 20
    zy = cove_profile(top)
    sweep(m, corner_stations(radius, n), [(-z, y) for z, y in zy], corner_us(radius, n, corner_tiles(radius)),
          scaled_v(zy, N_ARC+1, top))
    y0, y1 = FILL[top]
    # Instance budget (G8): the fewest boxes that keep check_coves' fillet gap <= .6; the end boxes grow over the tails.
    # They reach .9 into the room (still inside the cove solid at the fill heights): an end box runs along its own
    # chord, which leaves the straight tail by up to .2 at the tail's end.
    count = {8: 4, 16: 5, 24: 6}[radius]
    sector_boxes(m, 'Cove Fill ', radius-.9, radius+.3, math.pi, 1.5*math.pi, count, y0, y1, extend=TAIL)
    return done(m)


def mitre_sweep(m, prof, v, leg, ufun, mat='Tile'):
    """Closed solid: the (d, y) section `prof` (d = into the room from a wall face, closed polygon) swept along BOTH
    walls of a square inside corner and joined on the mitre plane x = z: wall A is z = 0 (section at z = d, swept
    along x from the cap x = leg to the mitre x = d), wall B is x = 0 (x = d, swept along z from the mitre to z = leg).
    Points with d = leg meet both caps on the line (leg, y, leg). Every point's sweep line carries a vertex at every
    station x = d_j of the section that lies in [0, leg], so a u that is a non-linear function of x (ufun) is exact
    at all of them; the strips are triangulated by zipping two neighbouring lines. UV per vertex: (ufun(x), v);
    axis-aligned faces planar at the frame phase (Mesh.finish)."""
    stations = sorted({d for d, _ in prof if 0 <= d <= leg} | {leg})
    verts, uvs, key = [], [], {}

    def vertex(p, side, x):
        d, y = prof[p]
        k = (p, 'M') if abs(x-d) < 1e-9 else (p, side, round(x, 9))
        if k not in key:
            key[k] = len(verts)
            verts.append((x, y, d) if side == 'A' or k[1] == 'M' else (d, y, x))
            uvs.append((ufun(x)*S, v[p]*S))
        return key[k]

    def line(p, side):
        d = prof[p][0]
        return [vertex(p, side, x) for x in [d]+[x for x in stations if x > d+1e-9]]
    faces = []
    n = len(prof)
    for p in range(n):
        q = (p+1) % n
        for side in 'AB':
            a, b = line(p, side), line(q, side)
            xa = [prof[p][0]]+[x for x in stations if x > prof[p][0]+1e-9]
            xb = [prof[q][0]]+[x for x in stations if x > prof[q][0]+1e-9]
            i = j = 0
            while i < len(a)-1 or j < len(b)-1:
                if j == len(b)-1 or (i < len(a)-1 and xa[i+1] <= xb[j+1]+1e-9):
                    tri, i = (a[i], b[j], a[i+1]), i+1
                else:
                    tri, j = (a[i], b[j], b[j+1]), j+1
                if len(set(tri)) == 3:
                    faces.append(tri)
    faces.append(tuple(vertex(p, 'A', leg) for p in range(n)))
    faces.append(tuple(vertex(p, 'B', leg) for p in range(n)))
    m.raw(verts, faces, mat, smooth=True, vertex_uv=uvs)


def inner_corner(top):
    """CoveBaseInnerCorner / CoveTopInnerCorner (FA, square R0 corners): the two concave R3 fillets of the
    perpendicular straight runs meeting in a clean mitre on the diagonal, instead of two runs crossing inside each
    other. CORNER frame with R = 0: pivot on the corner of the two wall FACES (the fillet centre of a zero radius), the
    walls are the planes x = 0 and z = 0, the room is +X/+Z; y as the straight pieces (base level, or 3 below the
    ceiling for the top). Each leg is INNER_LEG (3.25) long and ends in the straight runs' own section (butt joints at
    boundary + 5). A picture-frame mitre on the lattice: u along each leg is that wall's lattice (local - .25, the
    CORNER phase), v the straight runs' (scaled_v). On the mitre rows meet rows and cross lines meet cross lines, and
    the leg's cross lines continue the wall's and the floor's along both tangents.
    LATTICE_SPEC C4 asked for u = the perpendicular fillet's v (FA's rule: cross lines meet the other leg's rows).
    That puts a grout line on the face corner (the fillet's v is whole at the wall tangent) where the lattice has a
    mid-tile (the face corner is boundary + 1.75), so every square corner stepped against its walls along the leg's
    wall tangent (lattice_audit on a synthetic hall: 'CoveBaseInnerCorner | Hall Wall' inlay 0.25); no u that depends
    on x alone can satisfy both, this one satisfies the lattice and still meets on the mitre."""
    name = ('CoveTop' if top else 'CoveBase') + 'InnerCorner'
    m = Mesh(name, CORNER_PH, Radius=3, Profile='concave', Mitre='x = z', Leg=INNER_LEG, ExposedSide='Outward',
             Interior='positive X and positive Z',
             Base='3 below the ceiling' if top else 'deck top (.5) or dry floor (0)')
    zy = cove_profile(top)
    prof = [(-z, y) for z, y in zy]
    v = scaled_v(zy, N_ARC+1, top)
    mitre_sweep(m, prof, v, INNER_LEG, lambda x: x-CORNER_PH[0])
    y0, y1 = FILL[top]
    m.collider('Cove Fill A', ((INNER_LEG-.3)/2, (y0+y1)/2, .25), (INNER_LEG+.3, y1-y0, 1.1))
    m.collider('Cove Fill B', (.25, (y0+y1)/2, (INNER_LEG-.3)/2), (1.1, y1-y0, INNER_LEG+.3))
    # The two wall planes it is authored against (x = 0 and z = 0; a marker at the origin would carry no normal, so
    # each sits a hair inside its wall), as CornerCove's tangents: the collision audit's backing planes.
    m.marker('TangentX', (-.001, 0, 0))
    m.marker('TangentZ', (0, 0, -.001), yaw=90)
    return done(m)


def corner_cove(radius, height):
    m = Mesh(f'CornerCove_R{radius}_H{height}', CORNER_PH, Radius=radius, Height=height,
             Interior='positive X and positive Z', ArcTiles=corner_tiles(radius))
    n = 16 if radius <= 16 else 24
    # 0.05 past each tangent (butt joint, FIX_SPEC F1/F2), and into both structural slabs.
    over = math.asin(.05/radius)
    angles = [math.pi-over+i*(math.pi/2+2*over)/n for i in range(n+1)]
    levels = max(1, math.ceil((height+6)/30))      # side triangles under ~30 studs (BVH precision, H96)
    def by_angle(co, normal):
        x, z = co.x/S, -co.y/S
        a = math.atan2(z, x) % TAU                   # the 0.05 overruns are part of the arc (no tails here)
        return TILE*(.5+(a-math.pi)/(math.pi/2)*corner_tiles(radius))*S, co.z
    arc_solid(m, angles, (radius, radius+3), [-4+(height+6)*i/levels for i in range(levels+1)], uv=by_angle)
    # Collision (instance budget, G8): radial sector boxes filling R..R+3 behind the surface; each inner face is
    # tangent to the r=R surface at its mid angle and behind it elsewhere, by R(1-cos(da/2)) <= .12. That gap counts
    # twice in the world: the base torus's upper fillet (w ~.4 off the wall, h ~1.5) is backed by these blocks, and
    # w + gap must stay under the 0.6 backing tolerance (world collision audit C1). R8 5, R16 7, R24 8 boxes (was
    # 4/8/11 four-stud chords whose faces stood R+.25).
    sector_boxes(m, 'Corner Block ', radius, radius+3, angles[0], angles[-1], {8: 5, 16: 7, 24: 8}[radius],
                 FOOT, height+2)
    m.marker('TangentX', (-radius, 0, 0))
    m.marker('TangentZ', (0, 0, -radius), yaw=90)
    return done(m)


# ------------------------------------------------------------------------------------------- floor-standing (G4)

def column(diameter, height):
    r = diameter/2
    m = Mesh(f'Column_D{diameter}_H{height}', Diameter=diameter, Height=height, Bottom=FOOT)
    lathe(m, [(FOOT,r),(height,r)], n=40, cap=True)
    m.collider('Column Block', (0,(height+FOOT)/2,0), (diameter,height-FOOT,diameter),
               shape='Cylinder', attrs={'CylinderAxis':'Y','NativeSizeX':height-FOOT,
                                         'NativeSizeY':diameter,'NativeSizeZ':diameter,
                                         'NativeRotationZ':90})
    return done(m)


def porthole(radius):
    width, height = 2*radius+8, 2*radius+8
    m = Mesh(f'Porthole_R{radius}', HoleRadius=radius, PanelSize=[width,height,3])
    n = 32
    verts=[]
    for z in (-1.5,1.5):
        for ring in (0,1):
            for i in range(n):
                a=TAU*i/n;c,s=math.cos(a),math.sin(a)
                # The panel lip extends inside the adjoining wall by .65 stud.
                rr=radius if ring==0 else min((width/2+.65)/max(abs(c),1e-6),
                                              (height/2+.65)/max(abs(s),1e-6))
                verts.append((rr*c, height/2+rr*s, z))
    faces=[]
    for i in range(n):
        j=(i+1)%n
        faces.extend([(i,j,n+j,n+i), (2*n+i,3*n+i,3*n+j,2*n+j),
                      (i,2*n+i,2*n+j,j), (n+i,n+j,3*n+j,3*n+i)])
    def panel_uv(co,no):
        if abs(no.y)>.8:
            return kit.box_uv(co,no)
        yy=co.z-height/2*S
        a=math.atan2(yy,co.x)%TAU
        radial=no.x*co.x+no.z*yy
        face_a=(math.atan2(no.z,no.x)+(math.pi if radial<0 else 0))%TAU
        a+=TAU*round((face_a-a)/TAU)
        return a*radius*S,-co.y
    m.raw(verts,faces,'Tile',uv=panel_uv,smooth=True)
    # Four simple blockers leave the circular passage conservative and clear.
    side=(width-2*radius)/2
    for sign in (-1,1):
        m.collider('Side Block '+str(sign),(sign*(radius+side/2+.325),height/2,0),
                   (side+.65,height+1.3,3))
        m.collider('Vertical Block '+str(sign),(0,height/2+sign*(radius+side/2),0),
                   (2*radius,side+.65,3))
    m.marker('Opening',(0,height/2,0),Radius=radius)
    return done(m)


def curve_path(kind, extent, count):
    if kind=='Q':
        return [(extent*math.cos(math.pi*i/(2*count)),extent*math.sin(math.pi*i/(2*count)))
                for i in range(count+1)]
    # A shallow S with opposite bends and an inflection at the centre.
    return [(extent*t, .15*extent*math.sin(math.pi*t)) for t in
            [-1+2*i/count for i in range(count+1)]]


def wall_from_path(m, points, height, thickness=3, rounded=True):
    """A closed strip from y=-4, tangent-normal coordinates and arclength UVs."""
    centers=[];lengths=[0.0]
    for a,b in zip(points,points[1:]):
        lengths.append(lengths[-1]+math.dist(a,b))
    for i,p in enumerate(points):
        a=points[max(i-1,0)];b=points[min(i+1,len(points)-1)]
        dx,dz=b[0]-a[0],b[1]-a[1];ll=math.hypot(dx,dz)
        nx,nz=-dz/ll,dx/ll
        centers.append((p,nx,nz))
    cap=[(FOOT,-thickness/2),(FOOT,thickness/2),(height-.75,thickness/2)]
    if rounded:
        cap += [(height-.75+.75*math.sin(a), .75*math.cos(a))
                for a in [math.pi*i/12 for i in range(1,7)]]
        cap += [(height-.75+.75*math.sin(a), .75*math.cos(a))
                for a in [math.pi*i/12 for i in range(7,13)]]
    cap += [(height-.75,-thickness/2)]
    q=len(cap)
    verts=[(p[0]+nx*d,y,p[1]+nz*d) for p,nx,nz in centers for y,d in cap]
    faces=[(j*q+i,j*q+(i+1)%q,(j+1)*q+(i+1)%q,(j+1)*q+i)
           for j in range(len(points)-1) for i in range(q)]
    faces += [tuple(range(q-1,-1,-1)),tuple((len(points)-1)*q+i for i in range(q))]
    def path_uv(co,normal):
        px,pz=co.x/S,-co.y/S
        best=(float('inf'),0)
        for i,(a,b) in enumerate(zip(points,points[1:])):
            dx,dz=b[0]-a[0],b[1]-a[1]
            t=max(0,min(1,((px-a[0])*dx+(pz-a[1])*dz)/(dx*dx+dz*dz)))
            error=(px-a[0]-t*dx)**2+(pz-a[1]-t*dz)**2
            if error<best[0]:best=(error,lengths[i]+t*math.hypot(dx,dz))
        return best[1]*S,co.z
    m.raw(verts,faces,'Tile',uv=path_uv,smooth=False)
    arc_boxes(m,points,1.8,'Wall Block ',vertical=((height+FOOT)/2,height-FOOT))


def curve_wall(kind, extent, height):
    """Kept for reference; the swerve rooms (modules_swerve.py) replaced the free-standing partitions."""
    m=Mesh(f'CurveWall_{kind}{extent}_H{height}', Curve=kind, Radius=extent,
           Height=height, Thickness=3, Bottom=FOOT)
    count= max(12,math.ceil((math.pi*extent if kind=='S' else math.pi*extent/2)/3.7))
    wall_from_path(m,curve_path(kind,extent,count),height)
    return done(m,large=True)


def pier():
    m=Mesh('VaultPier',Size=[5,42-FOOT,5],Top=42,Bottom=FOOT)
    m.part('Pier Tile',(0,(42+FOOT)/2,0),(5,42-FOOT,5),'Tile')
    m.collider('Pier Block',(0,(42+FOOT)/2,0),(5,42-FOOT,5))
    return done(m)


# --------------------------------------------------------------------------------------- decks and steps (F2, F4)

def walkway_straight(length):
    """Walkway_Straight{L}, L in LENGTHS, WALL-FACE frame: the deck runs from the wall face (z=0) to 9.5 into the room
    (z=-9.5), top .5, bottom -4.5 (a solid basin wall on the pool side), pool-side nosing only. The flat top is a Part
    from the face to DECK_EDGE (9.25: an integer joint, boundary + 11); only the 0.25 nosing is mesh, its v whole at
    the deck edge (nose_v), u = local x. The Part ends on the wall face, not inside the wall: at a door hole the wall
    is open and the tunnel collar fills that depth (the builder joins a run's decks into one). Its wall-side edge is
    off the lattice by design, so it is turned 180 deg: object +Z points into the room and the top face's anchored
    (+X, +Z) corner lies on the pool-side edge and a run end (LATTICE_SPEC 4.3, the Run Deck rule)."""
    m = Mesh(f'Walkway_Straight{length}', WALL_PH, trims(('z', -DECK_OUT)), Length=length, Width=10, Top=DECK_TOP,
             Bottom=DECK_BOTTOM, WallSide='+Z', WallPlane=0, PoolEdge=-DECK_OUT, DeckEdge=-DECK_EDGE)
    m.part('Walkway Deck', (0, (DECK_TOP+DECK_BOTTOM)/2, -DECK_EDGE/2),
           (length, DECK_TOP-DECK_BOTTOM, DECK_EDGE), 'Tile', ground=True, yaw=180)
    zy = [(-DECK_EDGE, DECK_BOTTOM)] + nosing(-DECK_OUT, DECK_TOP, DECK_BOTTOM, -1)
    prism_x(m, [(y, z) for z, y in zy], -length/2, length/2, v=nose_v(zy, 1))
    return done(m)


def deck_ring_profile(ri, ro, nose_at_inner):
    """(r, y) section of a curved deck with the nosing on the pool side."""
    if nose_at_inner:
        return [(ro, DECK_BOTTOM), (ro, DECK_TOP)] + nosing(ri, DECK_TOP, DECK_BOTTOM, -1)
    return [(ri, DECK_BOTTOM), (ri, DECK_TOP)] + nosing(ro, DECK_TOP, DECK_BOTTOM, 1)


def walkway_corner(radius):
    """Walkway_Corner_R16/R24, CORNER frame (same pose as CornerCove): the deck section (Walkway_Straight's: 0.5 into
    the wall, nosing 9.25..9.5) swept round the quarter R-9.5..R+0.5 over the (-X,-Z) quadrant plus a 0.25 straight
    tail at both ends, so its ends butt onto the straight decks at integer joints (boundary + 2 + R). The deck top is
    PLANAR on the lattice (CORNER phase .25/.25: square tiles that continue the straight Run Decks, cut by the torus
    foot); the nosing and pool face carry the straight's v and u along the pool edge's own arc in whole tiles."""
    m = Mesh(f'Walkway_Corner_R{radius}', CORNER_PH, trims(('x', -radius+DECK_OUT), ('z', -radius+DECK_OUT)),
             CornerRadius=radius, Width=10, Top=DECK_TOP, Bottom=DECK_BOTTOM, Interior='positive X and positive Z',
             InnerRadius=radius-DECK_OUT, OuterRadius=radius+DECK_IN, Tail=TAIL)
    ri, ro = radius-DECK_OUT, radius+DECK_IN
    n = 16 if radius <= 16 else 24
    prof = [(-DECK_IN, DECK_BOTTOM), (-DECK_IN, DECK_TOP)] + nosing(DECK_OUT, DECK_TOP, DECK_BOTTOM, 1)
    sweep(m, corner_stations(radius, n), prof, corner_us(radius, n, round(math.pi/2*ri/TILE)), nose_v(prof, 2))
    sector_boxes(m, 'Corner Deck Ground ', ri, ro, math.pi, 1.5*math.pi, 3,  # G8 (was 6/8 for R16/R24)
                 DECK_BOTTOM, DECK_TOP, ground=True, exposed='in', extend=TAIL)
    return done(m)


def walkway_corner_square():
    """Walkway_Corner_R0, CORNER frame with R = 0 (pivot on the corner of the two wall faces, room +X/+Z): the deck
    square of a square or R8 corner, the straight decks' own section mitred round the corner, so the pool-edge nosing
    of the two runs turns the pool's corner instead of stopping against a box (FA: deck-nosing crease); legs
    SQUARE_LEG (10.25) long on both walls, so the deck runs start at boundary + 12 (LATTICE_SPEC 2.5). The flat top is
    planar on the lattice (CORNER phase); the nosing and pool faces carry the straight's v, u = local x - .25."""
    m = Mesh('Walkway_Corner_R0', CORNER_PH, trims(('x', DECK_OUT), ('z', DECK_OUT)), CornerRadius=0, Width=10,
             Top=DECK_TOP, Bottom=DECK_BOTTOM, Interior='positive X and positive Z', InnerRadius=0,
             OuterRadius=DECK_OUT, Leg=SQUARE_LEG)
    prof = [(0, DECK_BOTTOM), (0, DECK_TOP)] + nosing(DECK_OUT, DECK_TOP, DECK_BOTTOM, 1)
    nv = nose_v(prof, 2)
    v = [-CORNER_PH[2], -CORNER_PH[2]] + [DECK_EDGE-CORNER_PH[2]+t for t in nv[2:]]
    mitre_sweep(m, prof, v, SQUARE_LEG, lambda x: x-CORNER_PH[0])
    # Two overlapping ground boxes cover the L of the legs (each >= 4 x 4; one 10.25 square would overhang the pool).
    m.collider('Corner Deck Ground', (SQUARE_LEG/2, (DECK_TOP+DECK_BOTTOM)/2, DECK_OUT/2),
               (SQUARE_LEG, DECK_TOP-DECK_BOTTOM, DECK_OUT), ground=True)
    m.collider('Corner Deck Ground B', (DECK_OUT/2, (DECK_TOP+DECK_BOTTOM)/2, SQUARE_LEG/2),
               (DECK_OUT, DECK_TOP-DECK_BOTTOM, SQUARE_LEG), ground=True)
    return done(m)


def walkway_ring():
    """Walkway_Ring_R9: the BigPool island, a full annulus round a Column_D10 (pivot = column pivot). Top planar
    (phase 0); the outer nosing in whole tiles round the full turn."""
    ri, ro = 4.96, 9.0       # tucked 0.03 inside the 40-gon column face (4.992)
    m = Mesh('Walkway_Ring_R9', ZERO_PH, InnerRadius=5, OuterRadius=ro, Top=DECK_TOP, Bottom=DECK_BOTTOM,
             Column='Column_D10')
    count = round(TAU*ro/TILE)
    prof = deck_ring_profile(ri, ro, False)
    revolve(m, prof, [TAU*i/40 for i in range(40)], closed=True, ufun=lambda a, r: a/TAU*count*TILE,
            v=nose_v(prof, 2))
    sector_boxes(m, 'Ring Ground ', ri, ro, 0, TAU, 14, DECK_BOTTOM, DECK_TOP, ground=True, exposed='out')
    return done(m)


def _step_rule(centre, axis):
    """PoolSteps_Straight12 flat faces: the risers (z = front, a multiple of -4) keep the nosing's v; every other flat
    face, the treads and the side cheeks included, planar at (0, 0, .25)."""
    if axis == 2 and abs(centre[2]/4-round(centre[2]/4)) < 1e-6 and centre[2] < -1:
        return None
    return 'frame'


def steps_straight(count=3):
    """PoolSteps_Straight12: pivot at the deck's pool edge AT deck-top height; three 4-deep, 0.65-rise steps run down
    toward local -Z (tops -0.65/-1.3/-1.95), every step skirted to -4.5 with the deck's 0.25 rounded nosing.
    Each step is one mesh solid from its riser to front + 4.25 (its back 0.25 tucks under the step or deck above),
    planar on the lattice: treads and side cheeks (rows on y = k/2, so the cheeks of two steps meet on one grid, which
    two Step Ground Parts with .65 rise cannot: each anchors its rows at its own top, .15 apart; lattice_audit
    'Step Ground | Step Ground' 0.15). 'Step Ground N' is its ground collider, the same box the Part was, now
    invisible (LATTICE_SPEC C11). PoolSteps_Straight12_1/_2 are its first one/two steps: where the sloped
    basin floor rises to within .1 of a step top (the .8 shallow end and the .8 kids basin) the builder ends the stair
    before it (ANALYSIS F2+F4 check 5: no step top lies on or under the local floor)."""
    m = Mesh('PoolSteps_Straight12' + ('' if count == 3 else f'_{count}'), (0., 0., .25), _step_rule,
             Width=12, StepCount=count, Rise=STEP_RISE, Tread=4, Bottom=DECK_BOTTOM, Pivot='deck pool edge, deck top')
    for i in range(count):
        top, front = -(i+1)*STEP_RISE, -4*(i+1)
        m.collider('Step Ground '+str(i+1), (0, (top+DECK_BOTTOM)/2, front+NOSE_W+2), (12, top-DECK_BOTTOM, 4.0),
                   ground=True)
        zy = [(front+4+NOSE_W, DECK_BOTTOM), (front+4+NOSE_W, top)] + nosing(front, top, DECK_BOTTOM, -1)
        prism_x(m, [(y, z) for z, y in zy], -6, 6, v=nose_v(zy, 2))
    return done(m)


STEP_CLIP = DECK_IN+DECK_OUT   # 10: the deck's pool edge, measured from the curved stairs' pivot (the deck's wall edge)


def steps_curved(count=3):
    """PoolSteps_Curved: three rings (r 10-14, 14-18, 18-22) over local +X, tops -0.65/-1.3/-1.95, skirted to -4.5,
    nosing on each outer edge. Pivot on the deck's wall edge at the door centre (the builder puts it 1.25 from the
    boundary at deck-top height), local +X into the room, so the deck's straight pool edge is the plane x = 10.
    WP7: each ring is cut flush along that plane (x >= 10) instead of running on as a half ring through the deck:
    that part was hidden, and its risers crossed the deck's pool face as visible creases (world audit 07).
    PoolSteps_Curved_1 is its first ring alone, for the .8 kids basin (ring B would be a lip on the floor).
    Tread tops planar at the frame phase (.25, 0, 0)."""
    m = Mesh('PoolSteps_Curved' + ('' if count == 3 else f'_{count}'), (.25, 0., 0.), Width=12, StepCount=count,
             Rise=STEP_RISE, InnerRadius=10, OuterRadius=10+4*count, Bottom=DECK_BOTTOM, ClipX=STEP_CLIP)
    for i in range(count):
        top, ri, ro = -(i+1)*STEP_RISE, 10+i*4, 14+i*4
        # The nosing needs .35 of flat top inside ro: the ring ends where the deck plane reaches ro - .35.
        lim = math.acos(STEP_CLIP/(ro-.35))
        angles = sorted({-lim+j*2*lim/16 for j in range(17)} |
                        ({-math.acos(STEP_CLIP/ri), math.acos(STEP_CLIP/ri)} if ri > STEP_CLIP else set()))

        def profile(a, ri=ri, ro=ro, top=top):
            rin = max(ri, STEP_CLIP/math.cos(a))
            return [(rin, DECK_BOTTOM), (rin, top)] + nosing(ro, top, DECK_BOTTOM, 1)
        # v anchored at the tread's edge (nose_v), u along the pool edge ro: the nosing's cross lines run radial.
        revolve_var(m, profile, angles, vfun=lambda prof: nose_v(prof, 2), u_radius=ro)
        # G8: 5/7/7 boxes per ring (was 10/13/16; 5 keeps ring A's walkable boxes 4 wide on its shorter cut arc);
        # the riser at ro stays within .6 of a box. Rings are lettered A/B/C (not numbered) so collision_audit's
        # numbered-chain check (A1) does not chain one ring into the next. They tile the ring out to where it meets
        # the deck plane; their inner ends sit inside the deck.
        edge = math.acos(STEP_CLIP/ro)
        sector_boxes(m, f'Step {"ABC"[i]} Ground ', ri, ro, -edge, edge, (5, 7, 7)[i],
                     DECK_BOTTOM, top, ground=True, exposed='out')
    return done(m)


def steps_curved_landing():
    """PoolSteps_Curved_Landing: the half disc r<10 inside PoolSteps_Curved, top 0, for a curved stair that starts
    at threshold level with no deck (pivot = the curved steps' pivot, same y as their y=0)."""
    m = Mesh('PoolSteps_Curved_Landing', (.25, 0., 0.), Radius=10, Top=0, Bottom=DECK_BOTTOM)
    angles = [-math.pi/2+j*math.pi/16 for j in range(17)]
    # (0,-4.5) (10,-4.5) (10,-.3) (9.92,-.1) (9.75,0) (0,0): flat top at 0, rounded rim, skirt to -4.5.
    prof = [(0, DECK_BOTTOM), (10, DECK_BOTTOM)] + nosing(10, 0, DECK_BOTTOM, 1)[::-1][1:] + [(0, 0)]
    revolve(m, prof, angles, ufun=lambda a, r: a*10, v=nose_v(prof, len(prof)-2))   # radial lines (u at r 10)
    sector_boxes(m, 'Landing Ground ', 0, 10, -math.pi/2, math.pi/2, 6, DECK_BOTTOM, 0, ground=True,
                 exposed='out')
    return done(m)


# --------------------------------------------------------------------------------------- ceiling openings (F7, F8)

def ceiling_well(m, radius, panel, depth=8):
    """Flush ceiling opening (F7+F14). Pivot on the ceiling plane: the bottom face is a flat square annulus at y=0
    whose OUTER edge is exactly the builder's cut square (panel/2) and whose inner edge is the hole; the round-over
    rises into the hole and the tiled shaft runs to y=depth. Nothing lies below y=0. UV: the flat faces planar at
    phase 0; the round faces in whole tiles round the turn, rows on the ceiling's lattice."""
    n = 48
    rings = [('square', 0, panel/2),
             ('round', 0, radius+.55),
             ('round', .41, radius+.18),
             ('round', .71, radius),
             ('round', depth-.71, radius),                 # top lip mirrors the bottom one: it meets the flat
             ('round', depth-.41, radius+.18),             # annulus at 48 deg, so prkit's 45 deg rule splits it
             ('round', depth, radius+.55),
             ('square', depth, panel/2)]
    verts=[]
    for shape,y,r in rings:
        for i in range(n):
            a=TAU*i/n;c,s=math.cos(a),math.sin(a)
            rr=r/max(abs(c),abs(s)) if shape=='square' else r
            verts.append((rr*c,y,rr*s))
    faces=[(j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i)
           for j in range(len(rings)-1) for i in range(n)]
    # The outer square shaft walls close the solid (they sit on the slab's cut faces below the roof).
    faces += [((len(rings)-1)*n+i,(len(rings)-1)*n+(i+1)%n,(i+1)%n,i)
              for i in range(n)]
    ring=uv_round(radius)
    prof=[(y,r) for shape,y,r in rings if shape=='round']
    sv=_profile_lengths(prof)                      # v along the round-over and shaft, a line on the rim (y 0)

    def well_uv(co,normal):
        u,v=ring(co,normal)
        if abs(normal.z)<=.8:
            y,r=co.z/S,math.hypot(co.x,co.y)/S
            v=sv[min(range(len(prof)),key=lambda k:(prof[k][0]-y)**2+(prof[k][1]-r)**2)]*S
        return u,v
    m.raw(verts,faces,'Tile',uv=well_uv,smooth=True)
    outside=(panel/2)*math.sqrt(2)
    radial=(outside-radius-.3)
    station=radius+.3+radial/2
    count=math.ceil(TAU*station/3.7)
    pts=[(station*math.cos(TAU*i/count),station*math.sin(TAU*i/count))
         for i in range(count+1)]
    arc_boxes(m,pts,radial+.25,'Collar Block ',vertical=(depth/2,depth))


def light_well(radius, panel):
    m=Mesh(f'LightWell_R{radius}',HoleRadius=radius,ShaftDepth=8,PanelSize=panel,
           Pivot='ceiling plane (slab underside)')
    ceiling_well(m,radius,panel,8)
    m.marker('OpenSky',(0,8,0),Radius=radius)
    return done(m)


def spiral(height):
    """SpiralStairWell_H42/H52 (F8). Treads rise to a quarter-turn landing at StairTop = Height-14, so a jumping
    head stays 1.6 under the ceiling. The closed core runs from y=-4 up through the ceiling hole to Height+8; the
    hole itself is a separate LightWell_R12 (PanelSize 32) the builder puts at the ceiling plane."""
    stair_top = height-14
    count = math.ceil(stair_top/.78)        # the last step is the landing
    rise = stair_top/count
    m=Mesh(f'SpiralStairWell_H{height}', Height=height, StairTop=stair_top, PanelSize=32, HoleRadius=12,
           CoreDiameter=10, StairWidth=6.3, Rise=round(rise,4), Steps=count, Opening='LightWell_R12')
    lathe(m,[(FOOT,5),(height+8,5)],n=48,cap=True)
    m.collider('Core Block',(0,(height+8+FOOT)/2,0),(10,height+8-FOOT,10),shape='Cylinder',
               attrs={'CylinderAxis':'Y','NativeSizeX':height+8-FOOT,'NativeSizeY':10,
                      'NativeSizeZ':10,'NativeRotationZ':90})
    delta=.36
    for i in range(count-1):
        a0=-.7+i*delta;a1=a0+delta
        # Broad wedges overlap in angle and height, joining the visible soffit.
        angles=[a0-.13,(a0+a1)/2,a1+.13]
        top=(i+1)*rise
        # G4: the treads under 2.5 studs are skirted to y=-4 (a flooded hall's basin sits up to 2 below FloorY), so
        # the stair stands on the basin instead of hovering over it; their boxes follow them down.
        bottom=FOOT if top<2.5 else top-.8
        arc_solid(m,angles,(5,11.3),(FOOT if top<2.5 else top-.88,top))
        arc_solid(m,[a0-.13,a0+.05,a0+.23],(11,11.3),(top,top+.28))   # lip on the stepped-on part only
        # The stepped-on top of tread i is [a0-.13, a0+.23] (tread i+1 covers the rest): two radial bands, each
        # sized at its mid radius, keep both the gap and the overhang near the core under 0.3 stud.
        # The forward part [a0+.23, a0+.49] lies under tread i+1; 'Stair Fill' backs its soffit and outer face.
        for band,(r0,r1) in (('',(4.9,8.0)),('Outer ',(8.0,11.0))):
            tangent_box(m,f'Stair Ground {band}{i+1}',r0,r1,a0+.05,(r0+r1)/2*math.sin(.18),bottom,top,ground=True)
            tangent_box(m,f'Stair Fill {band}{i+1}',r0,r1,a0+.36,(r0+r1)/2*math.sin(.13),bottom,top)
    a_start=-.7+(count-1)*delta-.13
    land=[a_start+(math.pi/2)*i/12 for i in range(13)]
    arc_solid(m,land,(5,11.3),(stair_top-.88,stair_top))
    arc_solid(m,land,(11,11.3),(stair_top,stair_top+.28))
    # Same two-band rule as the treads, so the landing's exposed back edge (a drop to the last tread) gets no
    # invisible ledge: 4 inner and 5 outer segments, each sized at its band's mid radius.
    for band,(r0,r1),count_ in (('',(4.9,8.0),4),('Outer ',(8.0,11.0),5)):
        da=(math.pi/2)/count_
        for j in range(count_):
            tangent_box(m,f'Stair Ground Landing {band}{j+1}',r0,r1,land[0]+(j+.5)*da,(r0+r1)/2*math.sin(da/2),
                        stair_top-.8,stair_top,ground=True)
    first=-.7+.05
    m.marker('StairStart',(8*math.cos(first),0,8*math.sin(first)))
    mid=a_start+math.pi/4
    m.marker('StairEnd',(8*math.cos(mid),stair_top,8*math.sin(mid)))
    return done(m,large=True)


VAULT_SQUASH = 12/12.65   # Kit World Builder placeVaultBay: the 12.65-stud bay (12 rise + .65 shell) is set to 12 tall


def _vault_rim(c, axis):
    """A VaultBay rim face: vertical, on the bay's boundary |x| = 16 or |z| = 16 (Roblox local studs)."""
    return axis in (0, 2) and abs(c[axis]) > 16-1e-3


def vault(height):
    """VaultBay32: a GROIN vault (two crossing barrels, F4-vault): the edges rise to the flat ceiling at mid-span
    and spring 12 lower only at the four corners, where the builder puts piers."""
    # The builder squashes the bay to 12 studs tall (placeVaultBay: Size.Y 12.65 -> 12, springing at C - 12), so its
    # vertical rim faces carry v pre-scaled by VAULT_SQUASH: their rows land on the pier's 0.5 lattice after the
    # squash (lattice_audit 'corner' VaultBay | Pier Tile, pitch .474 before). Up/down faces stay planar ('frame').
    m=Mesh(f'VaultBay32_H{height}', ZERO_PH, lambda c, axis: None if _vault_rim(c, axis) else 'frame',
           BaySize=32, Spring=height-12, Vault='groin')
    n=16
    verts=[]
    q=(n+1)*(n+1)
    for lift in (0,.65):
        for iz in range(n+1):
            z=-16+32*iz/n
            for ix in range(n+1):
                x=-16+32*ix/n
                y=height-12+12*math.sqrt(max(0,1-(min(abs(x),abs(z))/16)**2))+lift
                verts.append((x,y,z))
    faces=[]
    for iz in range(n):
        for ix in range(n):
            a=iz*(n+1)+ix;b=a+1;c=a+n+2;d=a+n+1
            # The groin crease |x|=|z| must be an edge: a-c lies on it when ix==iz, b-d when ix+iz+1==n.
            tris=[(a,b,d),(b,c,d)] if ix+iz+1==n else [(a,b,c),(a,c,d)]
            faces += tris+[(q+t[2],q+t[1],q+t[0]) for t in tris]
    boundary=(list(range(n+1))+[i*(n+1)+n for i in range(1,n+1)]+
              [n*(n+1)+i for i in range(n-1,-1,-1)]+
              [i*(n+1) for i in range(n-1,0,-1)])
    faces += [(boundary[i],boundary[(i+1)%len(boundary)],
               q+boundary[(i+1)%len(boundary)],q+boundary[i])
              for i in range(len(boundary))]

    # Each barrel is a half ellipse (semi-axes 16 across, 12 up): x = 16 sin t, rise = 12 cos t. Unwrap by its TRUE
    # arc length s(t) (trapezoid table), so tiles keep their pitch from crown to springing.
    ts=np.linspace(0,math.pi/2,2001)
    ds=np.hypot(16*np.cos(ts),12*np.sin(ts))
    arc=np.concatenate(([0],np.cumsum((ds[1:]+ds[:-1])/2*np.diff(ts))))

    def ellipse_s(w):
        return math.copysign(float(np.interp(math.asin(min(1,abs(w)/16)),ts,arc)),w)

    def groin_uv(co,no):
        if abs(no.z)<1e-4:                           # vertical rim faces: v = studs above the springing, squashed
            u,_=kit.box_uv(co,no)
            return u,(co.z/S-(height-12))*VAULT_SQUASH*S
        x,z=co.x/S,-co.y/S
        if abs(no.x)>=abs(no.y):                     # the barrel whose section runs along x (crease-bounded tris)
            return ellipse_s(x)*S,z*S
        return x*S,ellipse_s(z)*S
    m.raw(verts,faces,'Tile',uv=groin_uv,smooth=True)   # 45 deg rule keeps the steep crease sharp, crown smooth
    return done(m,large=True)


def light_round():
    """Flush ceiling trim (F4-lightround): a 0.15 bevel ring and a 0.04 Neon disc; pivot = trim bottom, so the
    builder sets pivot y = C-0.15 and the top meets the ceiling underside. Rows at local y .15 + k/2 (on the
    ceiling's lattice), whole tiles round the ring."""
    m=Mesh('LightRound',(0.,.15,0.),Diameter=3.4,Height=.15)
    n=24
    rings=((0,1.7),(.15,1.5),(.15,1.7))
    verts=[(r*math.cos(TAU*i/n),y,r*math.sin(TAU*i/n))
           for y,r in rings for i in range(n)]
    faces=[(j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i)
           for j in range(2) for i in range(n)]
    faces += [(2*n+i,2*n+(i+1)%n,(i+1)%n,i) for i in range(n)]
    ring=uv_round(1.6,-.15)

    def trim_uv(co,normal):
        u,v=ring(co,normal)
        if .3<abs(normal.z)<.95:                     # the bevel: v along its 0.25 slant (0.15 rise)
            v=(co.z/S-.15)*(.25/.15)*S
        return u,v
    m.raw(verts,faces,'Tile',uv=trim_uv,smooth=True)
    m.cylinder((0,.02,0),1.6,.04,'LightWarm',segments=24)
    m.marker('Light',(0,-.1,0),lightType='PointLight',brightness=1.2,range=25,shadows=False)
    return done(m)


# ------------------------------------------------------------------------------------------- wall decor (F10, F4)

def sun_slit():
    """BOUNDARY frame: a warm Neon plane 2.4 x 14.4 in the outer 0.2 of the wall (y=0 is the plane bottom). The
    builder cuts a 2 x 13.5 hole from y=.5 to y=14 above the pivot (HoleBottom/HoleTop), so the plane overlaps it by
    .5 below, .4 above and .2 each side. No frame: the sill/lintel line the hole."""
    m=Mesh('SunSlit',Opening=[2,13.5],HoleBottom=.5,HoleTop=14.0,Plane=[2.4,14.4],WallSide='+Z',
           Pivot='outer wall boundary, builder puts it at h-17.5')
    m.box((0,7.2,-.1),(2.4,14.4,.2),'LightWarm',bevel=0)
    m.marker('Light',(0,7.2,-.2),lightType='SurfaceLight',face='Front',brightness=2,range=32,shadows=True)
    return done(m)


def wall_void():
    """BOUNDARY frame: a dark back plate in the outer 0.2 of a 10 x 4 hole the builder cuts (y=0 = hole bottom),
    so the void reads as a 1.55-deep recess lined by the wall's own tiles. 0.2 larger than the hole all round."""
    m=Mesh('WallVoid',Opening=[10,4],Depth=1.55,WallSide='+Z',Pivot='outer wall boundary')
    m.part('Void Back',(0,2,-.1),(10.4,4.4,.2),'Void',collide=True)
    return done(m)


def drain():
    """A small dark disc; pivot = disc centre (builder: basin top + 0.03, with the floor's tilt)."""
    m=Mesh('DrainHole',Diameter=3,Height=.06)
    m.cylinder((0,0,0),1.5,.06,'Void',segments=24)
    return done(m)


def build():
    """Register architecture only; no export or UI side effects on import."""
    for r in (8,16,24):
        for h in (34,42,52,96): corner_cove(r,h)
    # LATTICE_SPEC 2.5: CoveBase, CoveTop and Walkway_Straight in the same 19 lengths; every wall segment between
    # integer joints composes exactly at stretch 1 (the builder's fewest-piece table).
    for length in LENGTHS:
        cove(length,True);cove(length,False)
    cove_stop(1);cove_stop(-1);cove_stop(1,True);cove_stop(-1,True)
    for r in (8,16,24):
        cove_corner(r,True);cove_corner(r,False)
    inner_corner(True);inner_corner(False)
    for d in (6,10,16):
        for h in (34,42,52):column(d,h)
    for r in (6,10,15):porthole(r)
    for r in (16,32):
        for h in (34,42,52):curve_wall('Q',r,h)
    for r in (48,64):
        for h in (34,42,52):curve_wall('S',r,h)
    for length in LENGTHS: walkway_straight(length)
    for r in (16,24): walkway_corner(r)
    walkway_corner_square()
    walkway_ring()
    steps_straight();steps_straight(1);steps_straight(2);steps_curved();steps_curved(1);steps_curved_landing()
    for h in (42,52):spiral(h)
    for h in (34,42):vault(h)
    pier();light_round()
    for r,panel in ((6,24),(10,32),(12,32),(14,32)):light_well(r,panel)
    sun_slit();wall_void();drain()
    return {name:kit.COMPONENTS[name] for name in BUDGETS}


# ------------------------------------------------------------------------------------------------------- checks

def _rot(cf):
    if len(cf)==12:
        return np.array(cf[3:],float).reshape(3,3)
    t=math.radians(cf[3]);c,s=math.cos(t),math.sin(t)
    return np.array(((c,0,s),(0,1,0),(-s,0,c)))             # Roblox CFrame.Angles(0,t,0)


def _solids(info):
    return [(r,np.array(r['cf'][:3],float),_rot(r['cf']),np.array(r['size'],float)/2)
            for r in info['colliders']+[p for p in info['parts'] if p['collide']]]


def _dist(pts,boxes):
    """Distance from Roblox points to the union of collider OBBs (vertical cylinders as cylinders)."""
    d=np.full(len(pts),np.inf)
    for rec,pos,R,h in boxes:
        loc=(pts-pos)@R
        if rec.get('shape')=='Cylinder':
            q=np.stack((np.hypot(loc[:,0],loc[:,2])-h[0],np.abs(loc[:,1])-h[1]),1)
        else:
            q=np.abs(loc)-h
        d=np.minimum(d,np.linalg.norm(np.maximum(q,0),axis=1))
    return d


def _top_points(boxes,names=None,k=7):
    """Grid points on the top faces of the (optionally named) boxes."""
    out=[]
    g=np.linspace(-1,1,k)
    for rec,pos,R,h in boxes:
        if names and not any(rec['name'].startswith(n) for n in names):
            continue
        for u in g:
            for v in g:
                out.append(pos+R@np.array((u*h[0],h[1],v*h[2])))
    return np.array(out)


def _verts(info):
    mesh=info['mesh']
    return np.array([v.co[:] for v in mesh.vertices],float)@kit.C.T/S if len(mesh.vertices) else np.zeros((0,3))


def _polys(info):
    mesh=info['mesh'];co=_verts(info)
    for p in mesh.polygons:
        yield co[list(p.vertices)],np.array(p.normal[:])@kit.C.T


def _tris(info):
    """Loop triangles as (Roblox stud corners 3x3, uv 3x2 in metres at the TRUE pitch, Roblox normal, material
    name). Tiled UVs are read at the lattice's 0.5 pitch (TILE_M)."""
    mesh=info['mesh'];mesh.calc_loop_triangles()
    co=_verts(info);uvl=mesh.uv_layers.active.data
    for t in mesh.loop_triangles:
        mat=mesh.materials[t.material_index].name
        tile=(TILE_M if mat.removeprefix('PR_') in TILED else
              next(v['tile_m'] for v in kit.MATERIALS.values() if v['blender'].name==mat))
        yield (co[list(t.vertices)],np.array([uvl[i].uv[:] for i in t.loops],float)*tile,
               np.array(t.normal[:])@kit.C.T,mat)


def _uv_density(P,U):
    """Singular values of d(uv)/d(surface), in tile-metres per metre (1 = the kit's true tile pitch)."""
    e1,e2=(P[1]-P[0])*S,(P[2]-P[0])*S
    t1=e1/np.linalg.norm(e1);w=e2-(e2@t1)*t1;t2=w/np.linalg.norm(w)
    J=np.column_stack((U[1]-U[0],U[2]-U[0]))@np.linalg.inv(np.array(((e1@t1,e2@t1),(0,e2@t2))))
    return np.linalg.svd(J,compute_uv=False)


def _covered(tris,pts):
    """Which (x, z) points fall inside the xz projection of any triangle (each 3x3, Roblox)."""
    hit=np.zeros(len(pts),bool)
    for T in tris:
        a,b,c=T[:,[0,2]]
        v0,v1,v2=c-a,b-a,pts-a
        den=v0[0]*v1[1]-v1[0]*v0[1]
        if abs(den)<1e-12:
            continue
        u=(v2[:,0]*v1[1]-v1[0]*v2[:,1])/den;v=(v0[0]*v2[:,1]-v2[:,0]*v0[1])/den
        hit|=(u>=-1e-9)&(v>=-1e-9)&(u+v<=1+1e-9)
    return hit


def check_tops(name,info,regions,clip=None):
    """Mesh-based deck/step check: every up-facing flat face sits at a declared top, and the up faces at each top
    cover its declared footprint. regions: [(top, r0, r1, a0, a1)] polar ranges in the component frame; clip: the
    mesh stays at x >= clip (a stair cut flush at the deck's pool edge) and only x >= clip + .05 must be covered."""
    ups=[P for P,U,n,m in _tris(info) if n[1]>.99]
    tops={round(t,4) for t,*_ in regions}
    for P in ups:
        assert np.ptp(P[:,1])<1e-4 and round(float(P[0,1]),4) in tops,(name,'up face off the declared tops',
                                                                       P[:,1].round(3))
    if clip is not None:
        assert _verts(info)[:,0].min()>=clip-1e-4,(name,'mesh crosses the deck edge plane')
    for top,r0,r1,a0,a1 in regions:
        pts=np.array([(r*math.cos(t),r*math.sin(t)) for r in np.linspace(r0,r1,15) for t in np.linspace(a0,a1,73)])
        if clip is not None:
            pts=pts[pts[:,0]>=clip+.05]
        hit=_covered([P for P in ups if abs(P[0,1]-top)<1e-4],pts)
        assert hit.all(),(name,'top',top,'not covered at',pts[~hit][:3].round(2))
    return len(ups)


def _fillet_air(w,h):
    """How far a point (w into the room, h above the base) sits inside the room air of a concave R3 fillet."""
    inside=(w>0)&(h>0)
    band=(w<3)&(h<3)
    depth=np.where(band,3-np.hypot(3-w,3-h),np.minimum(w,h))
    return np.where(inside,np.maximum(depth,0),0)


def _stop_axis(name,info):
    """A stop's revolve axis (x offset: its tail) and turn sign."""
    sgn=1 if name.endswith('PX') else -1
    return np.array((sgn*info['attrs'].get('Tail',0.0),0,0)),sgn


def check_coves(name,info):
    """Concave profile, normals toward the fillet centre, Cove Fill gap <= 0.6 and no fill box in the room air.
    Stops are judged about their own axis (past a CoveBaseStopCorner's tail); corner tori include their tails."""
    top='Top' in name
    radius=info['attrs'].get('CornerRadius')
    stop=name.startswith('CoveBaseStop')
    axis,sgn=_stop_axis(name,info) if stop else (np.zeros(3),1)
    arcs=0
    for P,n in _polys(info):
        P=P-axis
        if stop:
            rho=np.hypot(P[:,0],P[:,2]);w,h=rho,P[:,1]
        elif radius:
            w=radius-np.hypot(P[:,0],P[:,2]);h=P[:,1]
        else:
            w,h=-P[:,2],P[:,1]
        hh=h if not top else 3-h
        on=np.abs(np.hypot(3-w,3-hh)-3)<.01
        if not on.all() or abs(n[0])>.5 and not (radius or stop):
            continue
        if (w<-1e-6).any() or (hh<-1e-6).any():
            continue
        arcs+=1
        c=P.mean(0)
        if stop or radius:
            e=np.array((c[0],0,c[2]));e/=max(np.linalg.norm(e),1e-9)
            rc=3.0 if stop else radius-3.0
            centre=e*rc+np.array((0,3.0 if not top else 0.0,0))
        else:
            centre=np.array((c[0],0,-3.0))+np.array((0,3.0 if not top else 0.0,0))
        assert n@(centre-c)>0,(name,'fillet face points away from its centre: convex or flipped',c.round(3))
    assert arcs>=N_ARC,(name,'concave fillet faces found',arcs)
    # Tile pitch on the visible fillet of a straight run: exact now (u 1.0, v 9.5 tiles over 4.705 = 1.0095;
    # LATTICE_SPEC 2.5/2.7), so the band is [.95, 1.05] (was [.75, 1.3] for stretched runs). Corner tori fan along u
    # by design (radial lines continue CornerCove's; LATTICE_SPEC C4) and stops fan to their axis: both are judged by
    # check_lattice's fan rule (u is the declared function of the angle) instead.
    if not (stop or radius):
        dens=[]
        for P,U,n,mat in _tris(info):
            w=-P[:,2]
            hh=P[:,1] if not top else 3-P[:,1]
            if (np.abs(np.hypot(3-w,3-hh)-3)<.01).all() and (w>-1e-6).all() and (hh>-1e-6).all():
                dens.extend(_uv_density(P,U))
        assert dens and .95<=min(dens) and max(dens)<=1.05,(name,'fillet uv density',min(dens),max(dens))
    # Fill coverage: sample the fillet surface, distance to fills + wall + base plane.
    a=np.linspace(0,math.pi/2,61)
    w,hh=3-3*np.sin(a),3-3*np.cos(a)          # every point of the quarter circle round (3,3) in (w, h-from-base)
    boxes=_solids(info)
    if stop:
        th=np.linspace(0,math.pi/2,13)
        pts=np.array([(sgn*ww*math.sin(t),hv,-ww*math.cos(t)) for t in th for ww,hv in zip(w,hh)])+axis
        tail=abs(axis[0])
        if tail:
            pts=np.concatenate((pts,[(x,hv,-ww) for x in np.linspace(0,sgn*tail,4) for ww,hv in zip(w,hh)]))
        back=np.minimum(np.maximum(0,-pts[:,2]),np.maximum(0,pts[:,1]))
    elif radius:
        span=np.linspace(math.pi,1.5*math.pi,25)
        pts=[((radius-ww)*math.cos(t),(3-hv) if top else hv,(radius-ww)*math.sin(t))
             for t in span for ww,hv in zip(w,hh)]
        for s in np.linspace(0,TAIL,4):            # the two straight tails
            pts+=[(-(radius-ww),(3-hv) if top else hv,s) for ww,hv in zip(w,hh)]
            pts+=[(s,(3-hv) if top else hv,-(radius-ww)) for ww,hv in zip(w,hh)]
        pts=np.array(pts)
        back=np.minimum(radius-np.hypot(pts[:,0],pts[:,2]),(3-pts[:,1]) if top else pts[:,1])
    else:
        pts=np.array([(x,(3-hv) if top else hv,-ww) for x in np.linspace(-info['attrs']['Length']/2,
                       info['attrs']['Length']/2,9) for ww,hv in zip(w,hh)])
        back=np.minimum(-pts[:,2],(3-pts[:,1]) if top else pts[:,1])
    gap=np.minimum(_dist(pts,boxes),np.maximum(back,0))
    assert gap.max()<=.6,(name,'cove fill gap',round(float(gap.max()),3),pts[int(gap.argmax())].round(3))
    # Fill boxes may not stand in the room air (corners of their faces).
    corners=[]
    for rec,pos,R,h in boxes:
        for sx in (-1,1):
            for sy in (-1,1):
                for sz in (-1,1):
                    corners.append(pos+R@(h*np.array((sx,sy,sz))))
    corners=np.array(corners)
    if stop:
        loc=corners-axis
        cw,ch=np.where(np.abs(loc[:,0])<=3,np.hypot(loc[:,0],loc[:,2]),9),corners[:,1]
        cw=np.where(corners[:,2]<=0,cw,-1)
    elif radius:
        cw,ch=radius-np.hypot(corners[:,0],corners[:,2]),corners[:,1]
    else:
        cw,ch=-corners[:,2],corners[:,1]
    air=_fillet_air(cw,(3-ch) if top else ch)
    assert air.max()<=.1,(name,'fill box stands in the room air',round(float(air.max()),3))
    return round(float(gap.max()),3)


def check_inner_corner(name,info):
    """FA: the mitred square corner. Every fillet face of either leg is concave and faces its own fillet axis, the
    legs end on the straight runs' section at INNER_LEG, the fills back the whole fillet within 0.6 and stand in no
    room air, and every fillet vertex's u is the perpendicular fillet's v at that distance (grout lines meet on the
    mitre and a leg ends on a grout line)."""
    top='Top' in name
    yc=0.0 if top else 3.0
    co=_verts(info)
    assert abs(co[:,0].max()-INNER_LEG)<1e-6 and abs(co[:,2].max()-INNER_LEG)<1e-6 and co[:,[0,2]].min()>=-.3-1e-6,        (name,'legs are not',INNER_LEG)
    arcs=0
    for P,U,n,mat in _tris(info):
        c=P.mean(0)
        a_side=c[2]<=c[0]
        w=P[:,2] if a_side else P[:,0]
        hh=P[:,1] if not top else 3-P[:,1]
        if not ((np.abs(np.hypot(3-w,3-hh)-3)<.01).all() and (w>-1e-6).all() and (hh>-1e-6).all()):
            continue
        if np.ptp(w)<1e-6 and np.ptp(hh)<1e-6:
            continue
        arcs+=1
        to_axis=np.array((0,yc-c[1],3-c[2])) if a_side else np.array((3-c[0],yc-c[1],0))
        assert n@to_axis>0,(name,'fillet face points away from its axis: convex or flipped',c.round(3))
        # Grout lines (picture-frame mitre on the lattice): every vertex's u is its leg's lattice coordinate (along
        # - .25), so on the mitre (along == w on both legs) the two legs' cross lines meet, rows meet rows (one v per
        # profile point), and a leg's end is a whole tile. Replaces FA's 'u == v on the mitre' (see inner_corner).
        along=P[:,0] if a_side else P[:,2]
        uu=U[:,0]/S
        assert np.allclose(uu,along-CORNER_PH[0],atol=1e-4),(name,'leg u off the lattice',c.round(3))
        end=np.abs(along-INNER_LEG)<1e-6
        assert np.allclose(np.round(uu[end]/TILE)*TILE,uu[end],atol=1e-4),(name,'leg ends off a grout line')
    assert arcs>=2*N_ARC,(name,'mitred fillet faces',arcs)
    a=np.linspace(0,math.pi/2,61)
    w,hh=3-3*np.sin(a),3-3*np.cos(a)
    pts=[]
    for ww,hv in zip(w,hh):
        y=(3-hv) if top else hv
        for x in np.linspace(ww,INNER_LEG,9):
            pts+=[(x,y,ww),(ww,y,x)]
    pts=np.array(pts)
    back=np.maximum(np.minimum(np.minimum(pts[:,0],pts[:,2]),(3-pts[:,1]) if top else pts[:,1]),0)
    boxes=_solids(info)
    gap=np.minimum(_dist(pts,boxes),back)
    assert gap.max()<=.6,(name,'cove fill gap',round(float(gap.max()),3))
    corners=np.array([pos+R@(h*np.array((sx,sy,sz))) for rec,pos,R,h in boxes
                      for sx in (-1,1) for sy in (-1,1) for sz in (-1,1)])
    cw=np.minimum(corners[:,0],corners[:,2])
    air=_fillet_air(cw,(3-corners[:,1]) if top else corners[:,1])
    assert air.max()<=.1,(name,'fill box stands in the room air',round(float(air.max()),3))
    return round(float(gap.max()),3)


def check_ground(name,info,visible,allowed,tops):
    """visible(): Roblox points just under the stepped-on surface, each must be within 0.6 of a ground box.
    allowed(p): True where a ground-box top point may legally sit (visible deck, or inside a solid neighbour)."""
    boxes=[b for b in _solids(info) if b[0]['ground']]
    pts=visible()
    d=_dist(pts,boxes)
    assert d.max()<=.6,(name,'ground gap',round(float(d.max()),3),pts[int(d.argmax())].round(2))
    tp=_top_points(boxes)
    ok=np.array([allowed(p) for p in tp])
    assert ok.all(),(name,'ground box top sticks out',tp[~ok][:3].round(2))
    for rec,pos,R,h in boxes:
        want=tops(rec)
        assert abs(pos[1]+h[1]-want)<1e-6,(name,rec['name'],'top',pos[1]+h[1],want)
    return round(float(d.max()),3)


def _polar(p):
    return math.hypot(p[0],p[2]),math.atan2(p[2],p[0])


def check_kit():
    """Kit rules named in ANALYSIS F1/F2/F7/F8/F10/F12 (beyond the budget/finite checks)."""
    report={}
    C=kit.COMPONENTS
    # G5: every chained/oblique collider's local X, decoded with Roblox's own formula, matches its chord/tangent.
    for name,recs in AXES.items():
        info=C[name]
        byname={r['name']:r for r in info['colliders']+info['parts']}
        for rec_name,(ex,ez) in recs.items():
            R=_rot(byname[rec_name]['cf'])
            assert abs(R[0,0]*ex+R[2,0]*ez)>=.999,(name,rec_name,'local X off its chord (mirrored yaw?)')
    report['axisChecked']=sum(len(v) for v in AXES.values())
    for name,info in C.items():
        if name not in BUDGETS:
            continue
        co=_verts(info)
        if name.endswith('InnerCorner'):
            report.setdefault('coveFillGap',{})[name]=check_inner_corner(name,info)
        elif name.startswith(('Cove','CoveBaseStop')):
            report.setdefault('coveFillGap',{})[name]=check_coves(name,info)
        if name.startswith(('Column_','CurveWall_','SpiralStairWell_')):
            assert co[:,1].min()<=FOOT+1e-6,(name,'does not reach y=-4')
        if name=='VaultPier':
            p=info['parts'][0];assert p['cf'][1]-p['size'][1]/2<=FOOT+1e-6,name
        if name.startswith(('Walkway_','PoolSteps_')):
            lows=[co[:,1].min()] if len(co) else []
            lows+=[p['cf'][1]-p['size'][1]/2 for p in info['parts']]
            assert min(lows)<=DECK_BOTTOM+1e-6,(name,'deck/step skirt does not reach -4.5')
        if name.startswith('LightWell_'):
            panel,half=info['attrs']['PanelSize'],info['attrs']['PanelSize']/2
            assert panel>2*(info['attrs']['HoleRadius']+1.15),name
            assert co[:,1].min()>=-1e-6,(name,'mesh below the ceiling plane')
            rim=co[np.abs(co[:,1])<1e-4]
            assert abs(np.abs(rim[:,[0,2]]).max()-half)<1e-4,(name,'plate outer edge != cut square')
            for r in info['colliders']:
                assert r['cf'][1]-r['size'][1]/2>=-.01,(name,r['name'],'collider below the ceiling plane')
        if name.startswith('SpiralStairWell_'):
            a=info['attrs'];H=a['Height']
            band=co[(co[:,1]>=H-3)&(co[:,1]<H)&(np.abs(co[:,0])<=16.01)&(np.abs(co[:,2])<=16.01)]
            assert len(band)==0,(name,'geometry within 3 under the ceiling plane',len(band))
            rr=np.hypot(co[:,0],co[:,2])
            assert co[rr>5.5,1].min()<=FOOT+1e-6,(name,'G4: the lowest treads do not reach y=-4')
            # The core's two 48-vertex end rings exist (the skirted treads also put their inner corners on r=5 at
            # y=-4, so the foot ring may hold more than 48 vertices; the top ring holds exactly 48).
            ring=[(5*math.cos(TAU*i/48),5*math.sin(TAU*i/48)) for i in range(48)]
            ends=[sum(bool((np.hypot(co[:,0]-x,co[:,2]-z)+np.abs(co[:,1]-y)<1e-4).any()) for x,z in ring)
                  for y in (FOOT,H+8)]
            top_ring=int(((np.abs(rr-5)<1e-3)&(np.abs(co[:,1]-H-8)<1e-4)).sum())
            assert ends==[48,48] and top_ring==48 and rr.min()>4.99,(name,'core is not one closed column',ends)
            treads=[c for c in info['colliders'] if c['ground']]
            top=max(c['cf'][1]+c['size'][1]/2 for c in treads)
            assert abs(top-a['StairTop'])<1e-6 and a['StairTop']<=H-14,(name,'StairTop rule',top)
            assert a['PanelSize']==32 and len(info['parts'])==0,name
        if name.startswith(('SunSlit','WallVoid')):
            zs=list(co[:,2])+[p['cf'][2]+s*p['size'][2]/2 for p in info['parts'] for s in (-1,1)]
            assert min(zs)>=-.25-1e-6 and max(zs)<=1e-6,(name,'decor leaves the outer 0.25 of the wall')
        if name=='LightRound':
            assert abs(co[:,1].max()-.15)<1e-6 and co[:,1].min()>=-1e-6,name
        if name.startswith('CornerCove_'):
            R=info['attrs']['Radius'];inner=0
            for P,U,n,mat in _tris(info):
                rr=np.hypot(P[:,0],P[:,2])
                if (np.abs(rr-R)<1e-3).all() and abs(n[1])<.5:
                    inner+=1
                    c=P.mean(0);assert n@np.array((-c[0],0,-c[2]))>0,(name,'r=R face does not face the pivot')
            surf=co[np.abs(np.hypot(co[:,0],co[:,2])-R)<1e-3]
            assert inner and max(surf[:,0].max(),surf[:,2].max())<=.05+1e-6,(name,'runs > .05 past a tangent')
        if name.startswith(('CoveBaseCorner_','CoveTopCorner_','Walkway_Corner_R')) and not name.endswith('R0'):
            # LATTICE_SPEC 2.5: the piece ends 0.25 past both tangents (its tails), at the runs' integer joints.
            assert abs(co[:,2].max()-TAIL)<1e-5 and abs(co[:,0].max()-TAIL)<1e-5,(name,'tails are not',TAIL)
        if name=='Walkway_Corner_R0':
            assert abs(co[:,0].max()-SQUARE_LEG)<1e-5 and abs(co[:,2].max()-SQUARE_LEG)<1e-5,(name,'legs',SQUARE_LEG,co[:,0].max(),co[:,2].max())
        if name.startswith('CoveBaseStop'):
            # C5: 3 studs (+ the 0.25 tail of a corner stop) from the run joint, never stretched, and nothing on the
            # wall plane z = 0 except the fillet's own section line (the old end cap z-fought the hall wall).
            tail=info['attrs']['Tail'];sgn=1 if name.endswith('PX') else -1
            far,near=(co[:,0].max(),co[:,0].min()) if sgn>0 else (-co[:,0].min(),-co[:,0].max())
            assert abs(far-(3+tail))<1e-5 and abs(near)<1e-5,(name,'length',far,near)
            for P,n in _polys(info):
                assert not (np.abs(P[:,2])<1e-6).all(),(name,'a face lies in the wall plane',P.mean(0).round(3))
        if name.startswith('VaultBay32'):
            for P,U,n,mat in _tris(info):
                if abs(n[1])>1e-3:
                    d=np.abs(P[:,0])-np.abs(P[:,2])
                    assert not (d.max()>1e-6 and d.min()<-1e-6),(name,'triangle straddles the groin crease')
            H=int(name.split('_H')[1])
            low=co[co[:,1]<H+.01]
            def y_at(x,z):
                return low[np.argmin(np.hypot(low[:,0]-x,low[:,2]-z))][1]
            assert abs(y_at(16,0)-H)<.05 and abs(y_at(0,-16)-H)<.05 and abs(y_at(16,16)-(H-12))<.05,\
                (name,'not a groin vault')
    # Ground coverage and overhang of every curved deck/step/landing (analytic visible surfaces).
    def grid(r0,r1,a0,a1,y,nr=13,na=61):
        return lambda: np.array([(r*math.cos(t),y-.02,r*math.sin(t)) for r in np.linspace(r0,r1,nr)
                                 for t in np.linspace(a0,a1,na)])
    for R in (16,24):
        n=f'Walkway_Corner_R{R}'
        def deck_vis(R=R):                         # the quarter and both 0.25 tails, up to the deck edge
            tails=[(-(R-d),DECK_TOP-.02,s) for d in np.linspace(-DECK_IN,DECK_EDGE,13) for s in np.linspace(0,TAIL,3)]
            tails+=[(s,DECK_TOP-.02,-(R-d)) for d in np.linspace(-DECK_IN,DECK_EDGE,13) for s in np.linspace(0,TAIL,3)]
            return np.concatenate((grid(R-DECK_EDGE,R,math.pi,1.5*math.pi,DECK_TOP)(),tails))
        report.setdefault('groundGap',{})[n]=check_ground(n,C[n],deck_vis,
            lambda p,R=R:_polar(p)[0]>=R-DECK_OUT-.35,lambda r:DECK_TOP)
    report['groundGap']['Walkway_Ring_R9']=check_ground('Walkway_Ring_R9',C['Walkway_Ring_R9'],
        grid(5,8.75,0,TAU,DECK_TOP),lambda p:_polar(p)[0]<=9.35,lambda r:DECK_TOP)
    report['groundGap']['PoolSteps_Curved_Landing']=check_ground('PoolSteps_Curved_Landing',
        C['PoolSteps_Curved_Landing'],grid(0,9.75,-math.pi/2,math.pi/2,0),
        lambda p:_polar(p)[0]<=10.35 or p[0]<0,lambda r:0)
    # The same decks from the MESH: up faces only at the declared tops, covering each top's footprint (chord sag
    # trimmed off the outer edge).
    sag=lambda r,n:r*math.cos(math.pi/(2*n))-.02
    report['upFaces']={
        **{f'Walkway_Corner_R{R}':check_tops(f'Walkway_Corner_R{R}',C[f'Walkway_Corner_R{R}'],
           [(DECK_TOP,R-DECK_EDGE+.01,sag(R+DECK_IN,32 if R<=16 else 48),math.pi,1.5*math.pi)]) for R in (16,24)},
        'Walkway_Ring_R9':check_tops('Walkway_Ring_R9',C['Walkway_Ring_R9'],[(DECK_TOP,5.0,sag(8.74,20),0,TAU)]),
        **{n:check_tops(n,C[n],[(-(i+1)*STEP_RISE,10+4*i+.01,sag(13.74+4*i,16),-math.pi/2,math.pi/2)
                                for i in range(k)],clip=STEP_CLIP)
           for n,k in (('PoolSteps_Curved',3),('PoolSteps_Curved_1',1))},
        'PoolSteps_Curved_Landing':check_tops('PoolSteps_Curved_Landing',C['PoolSteps_Curved_Landing'],
           [(0,0,sag(9.74,16),-math.pi/2,math.pi/2)])}
    for n,k in (('PoolSteps_Curved',3),('PoolSteps_Curved_1',1)):
        def curved_vis(k=k):
            pts=np.concatenate([grid(10+4*i,13.75+4*i,-math.pi/2,math.pi/2,-(i+1)*STEP_RISE)() for i in range(k)])
            return pts[pts[:,0]>=STEP_CLIP+.05]     # the visible tread, outside the deck it is cut flush with
        def curved_ok(p):
            r=_polar(p)[0];ring=int(round(-p[1]/STEP_RISE))-1
            return r<=14+4*ring+.35
        report['groundGap'][n]=check_ground(n,C[n],curved_vis,curved_ok,
            lambda rec:-('ABC'.index(rec['name'].split()[1])+1)*STEP_RISE)
    for H in (42,52):
        n=f'SpiralStairWell_H{H}';info=C[n];a=info['attrs']
        count=a['Steps'];rise=a['StairTop']/count
        def tread_vis(count=count,rise=rise):
            pts=[]
            for i in range(count-1):
                a0=-.7+i*.36
                pts.append(grid(5.2,11.0,a0-.13,a0+.23,(i+1)*rise,9,13)())
            a_s=-.7+(count-1)*.36-.13
            pts.append(grid(5.2,11.0,a_s,a_s+math.pi/2,count*rise,9,41)())
            return np.concatenate(pts)
        def tread_ok(p,count=count,rise=rise):
            r,t=_polar(p);i=int(round(p[1]/rise))-1
            if r>11.3+.35:
                return False
            if r<5:
                return True
            a0=-.7+i*.36
            t+=TAU*round((a0+.18-t)/TAU)
            if i==count-1:
                return t>=a0-.13-.35/r
            return a0-.13-.35/r<=t<=a0+.36+.49
        report['groundGap'][n]=check_ground(n,info,tread_vis,tread_ok,
            lambda rec,info=info:rec['cf'][1]+rec['size'][1]/2)
    return report


# ------------------------------------------------------------------------------------- lattice checks (I4, LS 7)
# The kit side of LATTICE_SPEC: every rule below has a planted negative in check_lattice().
#  parts   every tiled Part record's edges along each local axis on the frame phase (declared exceptions below)
#  planar  every axis-aligned tiled triangle planar at its phase: pitch exactly TILE, families along the face axes,
#          lines on the phase (Mesh.finish lays it; declared trims carry their own v)
#  trim    every other tiled triangle: tile size [.45, .55] along u and v, grid skew <= 11.5 deg (|cos| <= .2); a
#          declared fan (CornerCove, tori, stops) instead carries exactly the u its polar angle dictates
#  joint   straights' u is local x (both ends on a line); the R3 fillet's v whole at the wall tangent and half a tile
#          at the floor/ceiling tangent (LATTICE_SPEC 2.7); the deck nosing's v whole at the deck edge; corner decks'
#          and R0's u whole at their tail/leg ends

def _off(x):
    """Distance from x (studs) to the nearest grout line (a multiple of TILE)."""
    x=np.asarray(x,float)
    return np.abs(x/TILE-np.round(x/TILE))*TILE


def _tiled(info):
    """Tiled triangles: P (n,3,3) Roblox studs, U (n,3,2) studs at the 0.5 pitch (8 tiles per UV unit), N (n,3)."""
    mesh=info['mesh'];mesh.calc_loop_triangles()
    co=_verts(info);uvl=mesh.uv_layers.active.data
    P,U,N=[],[],[]
    for t in mesh.loop_triangles:
        if mesh.materials[t.material_index].name.removeprefix('PR_') not in TILED:
            continue
        P.append(co[list(t.vertices)]);U.append([uvl[i].uv[:] for i in t.loops])
        N.append(np.array(t.normal[:])@kit.C.T)
    if not P:
        return np.zeros((0,3,3)),np.zeros((0,3,2)),np.zeros((0,3))
    return np.array(P),np.array(U,float)*8*TILE,np.array(N)


def _axis_rbx(n):
    a=int(np.argmax(np.abs(n)))
    return a if abs(n[a])>AXIS_COS else None


def _grid(P,U):
    """Per triangle: du, dv = surface step per stud of u / of v (|du| = tile size / TILE), their lengths, |cos| of the
    angle between the two grout families, and whether the uv map is regular."""
    e1,e2=P[:,1]-P[:,0],P[:,2]-P[:,0]
    t1,t2=U[:,1]-U[:,0],U[:,2]-U[:,0]
    det=t1[:,0]*t2[:,1]-t1[:,1]*t2[:,0]
    ok=np.abs(det)>1e-9
    safe=np.where(ok,det,1.0)[:,None]
    du=(e1*t2[:,1:2]-e2*t1[:,1:2])/safe
    dv=(e2*t1[:,0:1]-e1*t2[:,0:1])/safe
    su,sv=np.linalg.norm(du,axis=1),np.linalg.norm(dv,axis=1)
    cos=np.abs((du*dv).sum(1))/np.maximum(su*sv,1e-12)
    return du,dv,su,sv,cos,ok


def _fan(name,info):
    """The declared u fan of a component, P -> u (studs), or None. CornerCove: by polar angle on every surface
    (incl. its 0.05 overruns); tori: corner_fan (angle round the quarter, true pitch along the tails); stops: 9 tiles
    round the quarter about their axis, local x along a corner stop's tail."""
    a=info['attrs']
    if name.startswith('CornerCove_'):
        R=a['Radius'];count=corner_tiles(R)
        return lambda P:TILE*(.5+((math.atan2(P[2],P[0])%TAU)-math.pi)/(math.pi/2)*count)
    if name.startswith(('CoveBaseCorner_','CoveTopCorner_')):
        f=corner_fan(a['CornerRadius'])
        return lambda P:f(P[0],P[2])
    if name.startswith('CoveBaseStop'):
        axis,sgn=_stop_axis(name,info)
        ufun=stop_u(sgn,a['Tail'])

        def u(P):
            x=P[0]-axis[0]
            if sgn*x<-1e-6:
                return P[0]                            # the tail: the run's own u (local x)
            if math.hypot(x,P[2])<1e-6:
                return None                            # an axis vertex takes its face's angle
            return ufun(math.atan2(P[2],x) if sgn>0 else math.atan2(P[2],-x),math.hypot(x,P[2]))
        return u
    return None


def _hidden(name,info):
    """Faces the lattice cannot be judged on because the world hides them, by component: a corner deck's back face
    inside the wall (r > R), the island ring's inner face against its column, a cove's faces under the floor, in the
    ceiling slab or in the wall, a curved step ring's inner face inside the ring or deck before it."""
    a=info['attrs']

    def behind(R):                                   # CORNER frame: beyond the wall face r = R (tails included)
        return lambda c,n=None:math.hypot(c[0],c[2])>R+1e-3 or (c[2]>1e-6 and c[0]<-R) or (c[0]>1e-6 and c[2]<-R)
    if name.startswith('Walkway_Corner_R') and a['CornerRadius']>0:
        return behind(a['CornerRadius'])
    if name.startswith('PoolSteps_Curved') and 'Landing' not in name:
        # a ring's inner face (normal toward the pivot axis) lies inside the ring or deck before it
        return lambda c,n=None:n is not None and n[0]*c[0]+n[2]*c[2]<0
    if name.startswith('Cove'):
        # Cove families: under the floor/deck (base) or in the ceiling slab (top), or inside the wall.
        top='Top' in name
        out=(lambda c:c[1]>3+1e-6) if top else (lambda c:c[1]<-1e-6)
        if name.startswith(('CoveBaseCorner_','CoveTopCorner_')):
            wall=behind(a['CornerRadius'])
        elif name.endswith('InnerCorner'):
            wall=lambda c:min(c[0],c[2])<-1e-6
        else:
            wall=lambda c:c[2]>1e-6
        return lambda c,n=None:out(c) or wall(c)
    if name=='Walkway_Ring_R9':
        return lambda c,n=None:math.hypot(c[0],c[2])<5.0
    return None


def fail_parts(name,parts):
    """Tiled Part records: both edges along each local axis on the frame phase. Declared: a deck Part's wall-side
    edge (z = 0, the wall face; LATTICE_SPEC 4.3: turned 180 so the top face's anchored corner is the pool-side
    edge)."""
    phase=FLAT[name][0];out=[]
    for rec in parts:
        if rec['material'] not in TILED:
            continue
        R=_rot(rec['cf']);c=np.array(rec['cf'][:3],float);h=np.abs(R)@(np.array(rec['size'],float)/2)
        for a in range(3):
            for side,val in (('min',c[a]-h[a]),('max',c[a]+h[a])):
                if _off(val-phase[a])<=1e-6:
                    continue
                if rec['name']=='Walkway Deck' and a==2 and side=='max' and abs(val)<1e-6:
                    continue
                out.append((rec['name'],'xyz'[a],side,round(float(val),4)))
        if rec['name']=='Walkway Deck' and round(rec['cf'][3])%360!=180:
            out.append((rec['name'],'yaw',rec['cf'][3],'top anchor not on the pool-side edge'))
    return out


def fail_planar(name,P,U,N):
    """Axis-aligned tiled triangles (declared trims excepted): pitch exactly TILE along two face axes, lines on the
    phase flat_phase gives for that face."""
    du,dv,su,sv,cos,ok=_grid(P,U);out=[]
    for j in range(len(P)):
        axis=_axis_rbx(N[j])
        if axis is None:
            continue
        ph=flat_phase(name,tuple(P[j].mean(0)),axis)
        if ph is None:
            continue
        if not ok[j]:
            out.append((j,'collapsed uv',P[j].mean(0).round(3).tolist()));continue
        for g,col in ((du[j],0),(dv[j],1)):
            a=int(np.argmax(np.abs(g)))
            sgn=math.copysign(1,g[a])
            if a==axis or abs(np.linalg.norm(g)-1)>1e-3 or abs(abs(g[a])-1)>1e-3 or \
                    max(float(_off(U[j,i,col]-sgn*(P[j,i,a]-ph[a]))) for i in range(3))>1e-3:
                out.append((j,'not planar on the phase',P[j].mean(0).round(3).tolist(),ph));break
    return out


def fail_trims(name,info,P,U,N):
    du,dv,su,sv,cos,ok=_grid(P,U);out=[]
    fan=_fan(name,info);hidden=_hidden(name,info)
    for j in range(len(P)):
        if _axis_rbx(N[j]) is not None:
            continue
        c=P[j].mean(0)
        if hidden and hidden(c,N[j]):
            continue
        if fan is not None:
            for i in range(3):
                want=fan(P[j,i])
                if want is not None and abs(U[j,i,0]-want)>1e-3:
                    out.append((j,'fan u',P[j,i].round(3).tolist(),round(float(U[j,i,0]),4),round(want,4)));break
            if ok[j] and (not .9<=sv[j]<=1.1 or cos[j]>.2):
                out.append((j,'fan v/skew',c.round(3).tolist(),round(float(sv[j]),3),round(float(cos[j]),3)))
            continue
        if not ok[j]:
            out.append((j,'collapsed uv',c.round(3).tolist()));continue
        if not (.9<=su[j]<=1.1 and .9<=sv[j]<=1.1 and cos[j]<=.2):
            out.append((j,'size/skew',c.round(3).tolist(),round(float(su[j]),3),round(float(sv[j]),3),
                        round(float(cos[j]),3)))
    return out


def _fillet_wh(name,info,P):
    """(w, h) of points in the fillet's own section (w into the room from the wall face, h from the floor/ceiling
    tangent's level toward the wall tangent), or None for families without an R3 fillet."""
    a=info['attrs'];top='Top' in name
    x,y,z=P[...,0],P[...,1],P[...,2]
    if name.startswith('CoveBaseStop'):
        axis,sgn=_stop_axis(name,info);x=x-axis[0]
        w=np.where(sgn*x<0,-z,np.hypot(x,z))
    elif name.startswith(('CoveBaseCorner_','CoveTopCorner_')):
        w=a['CornerRadius']-np.hypot(x,z)
    elif name.endswith('InnerCorner'):
        w=np.minimum(x,z)
    elif name.startswith(('CoveBase','CoveTop')):
        w=-z
    else:
        return None
    return w,(3-y if top else y)


def fail_joints(name,info,P,U,N):
    out=[];a=info['attrs']
    flat=np.array([_axis_rbx(n) is not None for n in N],bool) if len(N) else np.zeros(0,bool)
    hidden=_hidden(name,info)
    if hidden:
        flat|=np.array([hidden(p.mean(0),n) for p,n in zip(P,N)],bool)
    curved=~flat
    straight=name.startswith(('CoveBase','CoveTop','Walkway_Straight')) and name.rstrip('0123456789')!=name \
        and 'Corner' not in name and 'Stop' not in name
    if straight:
        bad=_off(U[curved][:,:,0]-P[curved][:,:,0])>1e-3
        if bad.any():
            out.append(('u is not local x',P[curved][bad.any(1)][0].mean(0).round(3).tolist()))
    wh=_fillet_wh(name,info,P)
    if wh is not None:
        w,h=wh
        on=curved[:,None]&(np.abs(np.hypot(3-w,3-h)-3)<.02)
        wall=on&(np.abs(w)<.02)&(np.abs(h-3)<.02)
        foot=on&(np.abs(w-3)<.02)&(np.abs(h)<.02)
        if not (wall.any() and foot.any()):
            out.append(('fillet tangents not found',int(wall.sum()),int(foot.sum())))
        if (_off(U[:,:,1][wall])>1e-3).any():
            out.append(('fillet v off a line at the wall tangent',float(U[:,:,1][wall][0])))
        if (np.abs(_off(U[:,:,1][foot])-TILE/2)>1e-3).any():
            out.append(('fillet v not mid-tile at the floor/ceiling tangent',float(U[:,:,1][foot][0])))
    if name.endswith('InnerCorner'):
        # picture-frame mitre (LATTICE_SPEC C4, I4 deviation): u is the leg's lattice coordinate (along - .25)
        for j in np.flatnonzero(curved):
            c=P[j].mean(0);along=P[j,:,0] if c[2]<=c[0] else P[j,:,2]
            if (np.abs(U[j,:,0]-(along-CORNER_PH[0]))>1e-3).any():
                out.append(('mitre u is not the leg lattice coordinate',c.round(3).tolist()));break
    if name.startswith('VaultBay'):
        # rim faces (vertical): v = height above the springing x VAULT_SQUASH (0.5 rows after the builder's squash),
        # u planar along the face (box projection, lines on the bay's integer frame)
        for j in range(len(N)):
            ax=_axis_rbx(N[j])
            if not _vault_rim(P[j].mean(0),ax):
                continue
            if (np.abs(U[j,:,1]-(P[j,:,1]-a['Spring'])*VAULT_SQUASH)>1e-3).any() or                     (_off(U[j,:,0]-(-P[j,:,2] if ax==0 else P[j,:,0]))>1e-3).any():
                out.append(('vault rim off its squashed lattice',P[j].mean(0).round(3).tolist()));break
    if name.startswith('Walkway_'):
        edge=curved[:,None]&(np.abs(P[:,:,1]-DECK_TOP)<1e-4)
        if not edge.any() or (_off(U[:,:,1][edge])>1e-3).any():
            out.append(('nosing v not whole at the deck edge',int(edge.sum())))
    if name.startswith('Walkway_Corner_R'):
        L=SQUARE_LEG if a['CornerRadius']==0 else TAIL
        end=curved[:,None]&((np.abs(P[:,:,0]-L)<1e-4)|(np.abs(P[:,:,2]-L)<1e-4))
        if not end.any() or (_off(U[:,:,0][end])>1e-3).any():
            out.append(('nosing u not whole at the tail/leg ends',int(end.sum())))
    return out


def lattice_failures(name,info,data=None,parts=None):
    P,U,N=data if data is not None else _tiled(info)
    return {'parts':fail_parts(name,info['parts'] if parts is None else parts),'planar':fail_planar(name,P,U,N),
            'trim':fail_trims(name,info,P,U,N),'joint':fail_joints(name,info,P,U,N)}


def check_lattice():
    """Every placed component passes the four lattice rules; each rule then fails on a planted defect."""
    report={'components':0,'flatTris':0,'trimTris':0}
    for name in BUDGETS:
        if name.startswith(UNPLACED):
            continue
        info=kit.COMPONENTS[name]
        P,U,N=_tiled(info)
        fails=lattice_failures(name,info,(P,U,N))
        assert not any(fails.values()),(name,'lattice',{k:v[:3] for k,v in fails.items() if v})
        report['components']+=1
        flat=sum(_axis_rbx(n) is not None for n in N)
        report['flatTris']+=flat;report['trimTris']+=len(N)-flat
    C=kit.COMPONENTS

    def planted(name,rule,mutate):
        P,U,N=(x.copy() for x in _tiled(C[name]))
        parts=[dict(r,cf=list(r['cf'])) for r in C[name]['parts']]
        mutate(P,U,N,parts)
        got=lattice_failures(name,C[name],(P,U,N),parts)[rule]
        assert got,(name,rule,'planted defect not caught')
        return len(got)

    def first(N,flat):
        return next(j for j in range(len(N)) if (_axis_rbx(N[j]) is not None)==flat)

    def shift_part(P,U,N,parts):
        parts[0]['cf'][0]+=TILE/2                     # a deck Part moved off the lattice by half a tile

    def shift_flat(P,U,N,parts):
        j=next(j for j in range(len(N)) if N[j][1]>AXIS_COS)
        U[j,:,0]+=TILE/2                              # a planar deck triangle's grid moved half a tile

    def stretch_trim(P,U,N,parts):
        j=first(N,False)
        U[j,:,0]*=1.25                                 # a fillet triangle's u stretched 25%

    def wrong_fan(P,U,N,parts):
        for j in range(len(N)):                       # the torus's u at its own radius (the old sqrt(R(R-3)) unwrap)
            r=np.hypot(P[j,:,0],P[j,:,2]);U[j,:,0]*=r/8

    def shift_u(P,U,N,parts):
        U[:,:,0]+=TILE/2                               # a straight run's u starting mid-tile

    def old_v(P,U,N,parts):
        U[:,:,1]-=TILE/2                               # the fillet's v from 0 at the floor tangent (pre-lattice)

    def nose_off(P,U,N,parts):
        U[:,:,1]+=.1                                   # the nosing's v off the deck-edge line

    def tail_off(P,U,N,parts):
        U[:,:,0]+=.1

    def unsquash(P,U,N,parts):
        U[:,:,1]/=VAULT_SQUASH                         # the rim's v at the mesh's own pitch (.474 after the squash)

    def skew_trim(P,U,N,parts):
        j=first(N,False)
        U[j,:,0]+=.5*U[j,:,1]                          # a fillet triangle's grid sheared (|cos| .45 > .2)

    def pitch_flat(P,U,N,parts):
        j=next(j for j in range(len(N)) if N[j][1]>AXIS_COS)
        U[j,:,0]=U[j,0,0]+(U[j,:,0]-U[j,0,0])*1.01     # a planar deck triangle at a 1% pitch (0.505)
    report['planted']={
        'trim CoveBase8 skewed':planted('CoveBase8','trim',skew_trim),
        'planar Walkway_Corner_R24 deck pitch 1%':planted('Walkway_Corner_R24','planar',pitch_flat),
        'joint CoveBaseInnerCorner mitre u':planted('CoveBaseInnerCorner','joint',tail_off),
        'joint VaultBay32_H42 rim v unsquashed':planted('VaultBay32_H42','joint',unsquash),
        'parts Walkway_Straight8 shifted':planted('Walkway_Straight8','parts',shift_part),
        'parts VaultPier shifted':planted('VaultPier','parts',shift_part),
        'planar Walkway_Corner_R16 deck':planted('Walkway_Corner_R16','planar',shift_flat),
        'planar Walkway_Corner_R0 deck':planted('Walkway_Corner_R0','planar',shift_flat),
        'trim CoveBase8 stretched':planted('CoveBase8','trim',stretch_trim),
        'trim CoveBaseCorner_R8 own-radius fan':planted('CoveBaseCorner_R8','trim',wrong_fan),
        'trim CoveBaseStop_PX shifted':planted('CoveBaseStop_PX','trim',shift_u),
        'joint CoveTop32 u':planted('CoveTop32','joint',shift_u),
        'joint CoveBase4 fillet v':planted('CoveBase4','joint',old_v),
        'joint CoveTopCorner_R16 fillet v':planted('CoveTopCorner_R16','joint',old_v),
        'joint Walkway_Straight16 nosing v':planted('Walkway_Straight16','joint',nose_off),
        'joint Walkway_Corner_R24 tail u':planted('Walkway_Corner_R24','joint',tail_off)}
    return report


def validate():
    rows=[]
    for name,budget in BUDGETS.items():
        info=kit.COMPONENTS[name];mesh=info['mesh'];mesh.calc_loop_triangles()
        tris=len(mesh.loop_triangles)
        assert tris<=budget,(name,tris,budget)
        assert all(math.isfinite(v) for p in mesh.vertices for v in p.co),name
        assert all(math.isfinite(v) for uv in mesh.uv_layers.active.data for v in uv.uv),name
        assert all(not any(word in rec['name'] for word in ('Ceiling','Skylight','Roof'))
                   for rec in info['parts']+info['colliders']+info['markers']),name
        # Ground blocks stay >= 4 x 4 (walkable footprint); the spiral's two radial bands are the one exception.
        assert all(rec['shape']!='Block' or not rec['ground'] or rec['name'].startswith('Stair Ground ') or
                   (rec['size'][0]>=4-1e-6 and rec['size'][2]>=4-1e-6)
                   for rec in info['colliders']),(name,[(r['name'],r['size']) for r in info['colliders']
                                                         if r['ground'] and min(r['size'][0],r['size'][2])<4])
        assert not set(info['mesh'].materials.keys())&{'PR_TileShade','PR_Worn'},name
        # Every chunk (one per material) is a closed solid with outward normals: positive signed volume.
        vol={}
        for P,U,n,mat in _tris(info):
            vol[mat]=vol.get(mat,0)+float(P[0]@np.cross(P[1],P[2]))/6
        assert all(v>0 for v in vol.values()),(name,'inside-out chunk (signed volume)',vol)
        rows.append(dict(name=name,tris=tris,budget=budget,chunks=len(mesh.materials),
                         parts=len(info['parts']),colliders=len(info['colliders'])))
    report=check_kit()
    report['lattice']=check_lattice()
    print('PR_A_COMPONENTS='+json.dumps(rows),flush=True)
    print('PR_A_KIT_CHECKS='+json.dumps(report),flush=True)
    return rows



def _part_in_bvh(bm, record):
    """Add a visible Part record as six closed quads, in Blender metres."""
    sx,sy,sz=record['size']
    center=kit.to_blender(record['cf'][:3])
    rot=Matrix.Rotation(math.radians(record['cf'][3]),3,'Z')
    corners=[bm.verts.new(center+rot @ Vector((x*sx*S/2,z*sz*S/2,y*sy*S/2)))
             for y in (-1,1) for z in (-1,1) for x in (-1,1)]
    for ids in ((0,1,3,2),(4,6,7,5),(0,4,5,1),
                (2,3,7,6),(0,2,6,4),(1,5,7,3)):
        bm.faces.new([corners[i] for i in ids])
    return center


def _ray_directions(count=160):
    """Even sphere coverage plus the six axial directions."""
    ds=[Vector(v) for v in ((1,0,0),(-1,0,0),(0,1,0),
                            (0,-1,0),(0,0,1),(0,0,-1))]
    golden=math.pi*(3-math.sqrt(5))
    for i in range(count):
        z=1-2*(i+.5)/count
        r=math.sqrt(max(0,1-z*z))
        a=i*golden
        ds.append(Vector((r*math.cos(a),r*math.sin(a),z)))
    return ds


def _inside_round_opening(x,z,radius,segments):
    """Point inside the exact polygonal aperture, with a 0.01-stud guard."""
    a=math.atan2(z,x)%TAU
    step=TAU/segments
    edge=(radius-.01)*S*math.cos(step/2)/math.cos(a%step-step/2)
    return math.hypot(x,z)<edge


def _misses_solid(tree,origin,direction,max_distance):
    """Reject isolated edge-grazing misses at Blender's BVH precision."""
    if tree.ray_cast(origin,direction,max_distance)[0] is not None:
        return False,False
    tangent=direction.cross(Vector((0,0,1)))
    if tangent.length<.1:tangent=direction.cross(Vector((0,1,0)))
    tangent.normalize()
    bitangent=direction.cross(tangent).normalized()
    # At the far 400-stud limit this nudges a ray by just 0.04 stud.
    neighbors=[(direction+side*.0001*offset).normalized()
               for offset in (tangent,bitangent) for side in (-1,1)]
    graze=any(tree.ray_cast(origin,d,max_distance)[0] is not None for d in neighbors)
    return not graze,graze


def watertight_checks():
    """BVH sweeps through each module's tiled solids and declared apertures.

    Open architectural modules do not enclose a whole hall. The sampled origins
    are inside their own tiled bodies; portholes and wells get an additional
    sphere sweep from within the aperture, exempting only the useful passage.
    """
    directions=_ray_directions()
    rows=[]
    for name in BUDGETS:
        info=kit.COMPONENTS[name]
        mesh=info['mesh'];mesh.calc_loop_triangles()
        bm=bmesh.new();bm.from_mesh(mesh)
        part_origins=[_part_in_bvh(bm,p) for p in info['parts']]
        bm.normal_update()
        open_edges=sum(not e.is_manifold for e in bm.edges)
        assert open_edges==0,(name,'open material edges',open_edges)
        tree=BVHTree.FromBMesh(bm,epsilon=.00001)
        tiled=[t for t in mesh.loop_triangles
               if mesh.materials[t.material_index].name in ('PR_Tile','PR_Aqua')]
        indices={round(i*(len(tiled)-1)/min(27,len(tiled)-1))
                 for i in range(min(28,len(tiled)))} if len(tiled)>1 else ({0} if tiled else set())
        origins=[]
        for i in sorted(indices):
            tri=tiled[i]
            midpoint=sum((mesh.vertices[v].co for v in tri.vertices),Vector())/3
            normal=tri.normal.normalized()
            inset=.018
            if name.startswith('Column_') and abs(normal.z)>.9:
                midpoint.x=0;midpoint.y=0
                inset=.2
            candidates=(midpoint-normal*inset*S,midpoint+normal*inset*S)
            # A face normal can point either way after Blender joins lofted
            # pieces. Select the side enclosed by the module, using the full
            # angular sweep rather than six axes that can miss a diagonal gap.
            origin=min(candidates,key=lambda p:sum(
                tree.ray_cast(p,d,400*S)[0] is None for d in directions))
            origins.append(origin)
        origins.extend(part_origins)
        escape=0;rays=0;grazes=0;bad=[]
        for origin in origins:
            for direction in directions:
                rays+=1
                miss,graze=_misses_solid(tree,origin,direction,400*S)
                grazes+=graze
                if miss:
                    escape+=1
                    if len(bad)<4:bad.append((tuple(round(c/S,3) for c in origin),
                                              tuple(round(c,3) for c in direction)))

        # A void in an arch panel is an intended through passage. All the
        # remaining angular directions must meet the panel itself.
        if name.startswith('Porthole_'):
            radius=info['attrs']['HoleRadius']
            center=kit.to_blender((0,radius+4,0))
            for direction in directions:
                rays+=1
                if abs(direction.y)>1e-8:
                    t=1.5*S/abs(direction.y)
                    dx=center.x+t*direction.x
                    dy=center.z+t*direction.z-(radius+4)*S
                    if _inside_round_opening(dx,dy,radius,32):
                        continue
                miss,graze=_misses_solid(tree,center,direction,100*S)
                grazes+=graze
                if miss:
                    escape+=1
                    if len(bad)<4:bad.append(('passage',tuple(round(c,3) for c in direction)))
        if name.startswith('LightWell_'):
            r=info['attrs']['HoleRadius']
            center=kit.to_blender((0,4,0))
            for direction in directions:
                rays+=1
                if tree.ray_cast(center,direction,100*S)[0] is not None:
                    continue
                if abs(direction.z)>1e-8:
                    plane=(8 if direction.z>0 else 0)*S
                    t=(plane-center.z)/direction.z
                    if t>0 and _inside_round_opening(center.x+t*direction.x,
                                                      center.y+t*direction.y,r+.55,48):
                        continue  # declared sky hole / connection to the hall
                miss,graze=_misses_solid(tree,center,direction,100*S)
                grazes+=graze
                if miss:
                    escape+=1
                    if len(bad)<4:bad.append(('shaft',tuple(round(c,3) for c in direction)))
        bm.free()
        row={'name':name,'rays':rays,'escapes':escape,'grazes':grazes,
             'origins':len(origins),'openEdges':open_edges}
        rows.append(row)
        print('PR_A_ESCAPES '+json.dumps(row),flush=True)
        assert escape==0,(name,escape,bad)
    return rows


# ------------------------------------------------------------------------------------------------------ reviews


# ------------------------------------------------------------------------------------------------------ reviews

def collection(name):
    c=bpy.data.collections.new(name);bpy.context.scene.collection.children.link(c)
    return c


def review_box(col,name,center,size,mat='Tile'):
    m=kit.Mesh(name);m.box(center,size,mat,bevel=0)
    ob=bpy.data.objects.new(name,m.finish(register=False));col.objects.link(ob)
    return ob


# The measured Roblox Part rule (G:/Roblox/_local/l2fix/studio/TILE_PHASE.md): each face's tiles start at one corner,
# in object space. (face axis, sign) -> ((axis 1, anchored end), (axis 2, anchored end)).
ANCHOR={(1,1):((0,1),(2,1)),(1,-1):((0,1),(2,-1)),(0,1):((1,1),(2,1)),(0,-1):((1,1),(2,-1)),
        (2,1):((1,1),(0,-1)),(2,-1):((1,1),(0,1))}


def part_box(col,name,center,size,mat='Tile',yaw=0):
    """A review Part tiled by the measured rule (yaw a multiple of 90, Roblox convention), unlike review_box's
    world-aligned grid: the renders show Part seams as Studio draws them."""
    t=math.radians(yaw);R=np.array(((math.cos(t),0,math.sin(t)),(0,1,0),(-math.sin(t),0,math.cos(t))))
    h=np.array(size,float)/2;c=np.array(center,float)
    bm=bmesh.new();uvl=bm.loops.layers.uv.new('UVMap')
    for (a,sg),((i,si),(j,sj)) in ANCHOR.items():
        quad=[]
        for p,q in ((-1,-1),(1,-1),(1,1),(-1,1)):
            o=np.zeros(3);o[a]=sg*h[a];o[i]=p*h[i];o[j]=q*h[j]
            quad.append(o)
        if np.cross(quad[1]-quad[0],quad[2]-quad[0])@np.eye(3)[a]*sg<0:
            quad=quad[::-1]
        vs=[bm.verts.new(kit.to_blender(c+R@o)) for o in quad]
        f=bm.faces.new(vs)
        for loop,o in zip(f.loops,quad):
            loop[uvl].uv=((o[i]-si*h[i])/(8*TILE),(o[j]-sj*h[j])/(8*TILE))
    kit.material(mat)
    mesh=bpy.data.meshes.new(name);bm.to_mesh(mesh);bm.free()
    mesh.materials.append(kit.MATERIALS[mat]['blender'])
    ob=bpy.data.objects.new(name,mesh);col.objects.link(ob)
    return ob


def place(col,name,pos=(0,0,0),yaw=0):
    """Instance a component (mesh only: its Part records are drawn by part_box where a review needs them) at Roblox
    studs / yaw. Runs are never stretched (LATTICE_SPEC 2.5)."""
    info=kit.COMPONENTS[name]
    M=Matrix.Translation(kit.to_blender(pos))@Matrix.Rotation(math.radians(yaw),4,'Z')
    if len(info['mesh'].vertices):
        o=bpy.data.objects.new(name,info['mesh']);col.objects.link(o);o.matrix_world=M


def compose(length):
    """The builder's exact rule: the fewest LENGTHS pieces summing to an integer length (stretch 1)."""
    L=round(length);assert abs(L-length)<1e-9 and L>=0,length
    best=[[]]+[None]*L
    for t in range(1,L+1):
        best[t]=min(([p]+best[t-p] for p in LENGTHS if p<=t),key=len)
    return sorted(best[L],reverse=True)


class Hall:
    """A review hall posed as the World Builder poses it: integer boundary, wall faces 1.75 in, FloorY 0."""
    def __init__(self,x0,x1,z0,z1,C):
        self.x0,self.x1,self.z0,self.z1,self.C=x0,x1,z0,z1,C

    def pose(self,side,along,inset=.75):
        """wallPose: (x, z, yaw) of a wall-face point (inset .75 = the face, boundary + 1.75)."""
        d=inset+1
        return {'S':(along,self.z1-d,0),'N':(along,self.z0+d,180),'W':(self.x0+d,along,-90),
                'E':(self.x1-d,along,90)}[side]

    def run(self,col,prefix,side,a,b,y,deck=False):
        """Lay an exact run of prefix{L} between integer joints a..b (world along-coordinates)."""
        s=min(a,b)
        for p in compose(abs(b-a)):
            x,z,yaw=self.pose(side,s+p/2)
            place(col,prefix+str(p),(x,y,z),yaw)
            s+=p
        if deck:                                    # the builder's Run Deck Part (LATTICE_SPEC 4.3)
            x,z,yaw=self.pose(side,(a+b)/2)
            t=math.radians(yaw);into=(-math.sin(t)*DECK_EDGE/2,-math.cos(t)*DECK_EDGE/2)
            part_box(col,'Run Deck',(x+into[0],(DECK_TOP+DECK_BOTTOM)/2,z+into[1]),
                     (abs(b-a),DECK_TOP-DECK_BOTTOM,DECK_EDGE),yaw=yaw+180)

    def corner(self,index):
        """cornerFrame: (x, z, yaw) of corner index 1..4 (MinX/MinZ, MaxX/MinZ, MinX/MaxZ, MaxX/MaxZ) for radius R."""
        return lambda R:{1:(self.x0+1.75+R,self.z0+1.75+R,0),2:(self.x1-1.75-R,self.z0+1.75+R,-90),
                         3:(self.x0+1.75+R,self.z1-1.75-R,90),4:(self.x1-1.75-R,self.z1-1.75-R,180)}[index]


def light(col,name,position,target,energy,size=0,color=(1,.88,.71),kind='AREA'):
    data=bpy.data.lights.new(name,kind);data.color=color;data.energy=energy
    if kind=='AREA':data.shape='DISK';data.size=size*S
    ob=bpy.data.objects.new(name,data);col.objects.link(ob)
    ob.location=kit.to_blender(position)
    ob.rotation_euler=(kit.to_blender(target)-ob.location).to_track_quat('-Z','Y').to_euler()
    return ob


def camera_render(col,name,eye,target,lens=24,folder=None):
    sc=bpy.context.scene
    for c in sc.collection.children:c.hide_render=c!=col
    for mat in bpy.data.materials:
        mat.use_backface_culling=True               # wrong-facing faces must show in reviews
    camera=bpy.data.objects.new('Review Camera',bpy.data.cameras.new('Review Camera'))
    col.objects.link(camera);camera.location=kit.to_blender(eye)
    camera.rotation_euler=(kit.to_blender(target)-camera.location).to_track_quat('-Z','Y').to_euler()
    camera.data.clip_end=700;camera.data.lens=lens
    sc.camera=camera
    sc.render.filepath=str((folder or REVIEW)/name)
    bpy.ops.render.render(write_still=True)
    col.objects.unlink(camera);bpy.data.objects.remove(camera)


def hall_review():
    """A decked pool hall on the lattice, posed exactly as the builder should (LATTICE_SPEC 2.5/4.3): boundary
    x -48..48, z -44..44 (integers), C 34. Corners: R16 (MinX/MinZ) and R24 (MinX/MaxZ) arcs with CornerCove, both
    tori and the ring deck; square corners (MaxX) with inner mitres and Walkway_Corner_R0. The South wall has a
    12-wide door (x -6..6, y 0..12) with CoveBaseStops; North has PoolSteps_Straight12. Parts (walls, Run Decks,
    floor, ceiling) are tiled by the measured face-corner rule."""
    col=collection('PR-A lattice hall');h=Hall(-48,48,-44,44,34);C=h.C;base=DECK_TOP
    radii={1:16,2:0,3:24,4:0}
    door=(-6,6,0,12)
    # Wall slabs: face to boundary, foot -8 to C+2 (on the lattice), split round the door.
    for side,(lo,hi) in (('S',(h.x0,h.x1)),('N',(h.x0,h.x1)),('W',(h.z0,h.z1)),('E',(h.z0,h.z1))):
        cuts=[(lo,door[0]),(door[0],door[1]),(door[1],hi)] if side=='S' else [(lo,hi)]
        for a,b in cuts:
            spans=[(door[3],C+2)] if side=='S' and a==door[0] else [(-8,C+2)]
            for y0,y1 in spans:
                x,z,yaw=h.pose(side,(a+b)/2,-.125)     # centre .875 in: face to boundary
                part_box(col,'Hall Wall',(x,(y0+y1)/2,z),(b-a,y1-y0,1.75),yaw=yaw)
    part_box(col,'Ceiling',(0,C+1,0),(96,2,88))
    part_box(col,'Basin',(0,-2,0),(92,1,84),'Aqua')
    # Corners.
    starts={}
    for index,R in radii.items():
        x,z,yaw=h.corner(index)(R)
        if R:
            place(col,f'CornerCove_R{R}_H{C}',(x,0,z),yaw)
            place(col,f'CoveBaseCorner_R{R}',(x,base,z),yaw)
            place(col,f'CoveTopCorner_R{R}',(x,C-3,z),yaw)
            place(col,f'Walkway_Corner_R{R}',(x,0,z),yaw)
            starts[index]=(2+R,2+R,2+R)                # cove, top, deck run starts from the boundary
        else:
            place(col,'CoveTopInnerCorner',(x,C-3,z),yaw)
            place(col,'CoveBaseInnerCorner',(x,base,z),yaw)
            place(col,'Walkway_Corner_R0',(x,0,z),yaw)
            starts[index]=(5,5,12)
    walls={'N':(1,2,h.x0,h.x1),'S':(3,4,h.x0,h.x1),'W':(1,3,h.z0,h.z1),'E':(2,4,h.z0,h.z1)}
    for side,(c0,c1,lo,hi) in walls.items():
        a,b=lo+starts[c0][1],hi-starts[c1][1]
        h.run(col,'CoveTop',side,a,b,C-3)
        a,b=lo+starts[c0][2],hi-starts[c1][2]
        if side=='N':                                 # steps at x 14..26: the deck runs on both sides of them
            h.run(col,'Walkway_Straight',side,a,b,0,deck=True)
            x,z,yaw=h.pose('N',20,.75+DECK_OUT)
            place(col,'PoolSteps_Straight12',(x,base,z),yaw)
        else:
            h.run(col,'Walkway_Straight',side,a,b,0,deck=True)
        a,b=lo+starts[c0][0],hi-starts[c1][0]
        if side=='S':                                  # base cove split at the door, 3-stud stops at the hole edges
            h.run(col,'CoveBase',side,a,door[0]-3,base)
            h.run(col,'CoveBase',side,door[1]+3,b,base)
            x,z,yaw=h.pose('S',door[0]-3);place(col,'CoveBaseStop_PX',(x,base,z),yaw)
            x,z,yaw=h.pose('S',door[1]+3);place(col,'CoveBaseStop_NX',(x,base,z),yaw)
        else:
            h.run(col,'CoveBase',side,a,b,base)
    for p in ((0,30,0),(-24,30,-20),(24,30,20),(-24,30,20),(24,30,-20)):
        light(col,'Hall lamp',p,(p[0],0,p[2]),2600,8)
    fz=h.z1-1.75
    shots=[('A01_cove_stops_at_door.png',(-1,4.5,fz-9),(-7,1.5,fz)),
           ('A02_ring_deck_R16_corner.png',(-24,8,-20),(-44,.5,-40)),
           ('A03_ring_deck_R16_low.png',(-30,2.5,-34),(-43,.3,-36)),
           ('A04_ring_deck_R24_corner.png',(-22,8,18),(-44,.5,40)),
           ('A05_square_corner_R0.png',(32,6,-28),(46,1,-42)),
           ('A06_corner_top_coves.png',(-24,24,-22),(-46,33,-42)),
           ('A07_pool_steps.png',(20,6,-24),(20,-1,-36)),
           ('A08_stop_close.png',(-5,2.2,fz-4),(-8,1,fz))]
    for name,eye,target in shots:
        camera_render(col,name,eye,target)


def spiral_review():
    col=collection('PR-A spiral');C=42;f=36
    part_box(col,'Basin',(0,-1.5,0),(2*f,1,2*f),'Aqua')
    for x in (-f-1,f+1):
        part_box(col,'Wall',(x,C/2,0),(2,C+8,2*f+4))
    for z in (-f-1,f+1):
        part_box(col,'Wall',(0,C/2,z),(2*f,C+8,2))
    for x0,x1,z0,z1 in ((-f,-16,-f,f),(16,f,-f,f),(-16,16,-f,-16),(-16,16,16,f)):
        part_box(col,'Ceiling',((x0+x1)/2,C+1,(z0+z1)/2),(x1-x0,2,z1-z0))
    place(col,'LightWell_R12',(0,C,0))
    place(col,'SpiralStairWell_H42')
    light(col,'Lamp',(20,36,-20),(0,10,0),5000,10)
    light(col,'Lamp',(-20,36,20),(0,10,0),3000,10)
    light(col,'Well daylight',(0,C+25,0),(0,0,0),12000,6)
    camera_render(col,'A11_spiral_from_below.png',(24,4,-26),(0,18,0))
    camera_render(col,'A12_spiral_landing_and_hole.png',(14,20,-20),(0,34,0))


def detail_review():
    """The pieces the hall shots miss: a 2x2 groin-vault group and curved steps with their landing."""
    col=collection('PR-A vault')
    part_box(col,'Floor',(0,-.5,0),(72,1,72))
    for x in (-16,16):
        for z in (-16,16):place(col,'VaultBay32_H34',(x,0,z))
    for x in (-32,0,32):
        for z in (-32,0,32):part_box(col,'Pier Tile',(x,(42+FOOT)/2,z),(5,42-FOOT,5))
    light(col,'Lamp',(0,6,-30),(0,30,0),20000,20);light(col,'Lamp',(20,6,20),(0,30,0),8000,10)
    camera_render(col,'A14_vault_group_from_below.png',(-6,4,-6),(10,30,10),lens=18)
    col=collection('PR-A curved steps')
    part_box(col,'Basin',(0,-2.5,0),(60,1,60),'Aqua')            # deepest basin (FloorY-2): all three steps show
    part_box(col,'Wall',(-2+.875,10,0),(1.75,24,60))          # boundary x = -2, wall face -.25
    x=-2+1.25                                                 # pivot 1.25 from the boundary, deck top 0
    place(col,'PoolSteps_Curved',(x,0,0));place(col,'PoolSteps_Curved_Landing',(x,0,0))
    light(col,'Lamp',(10,25,0),(10,0,0),6000,10)
    camera_render(col,'A16_curved_steps_landing.png',(30,9,-14),(8,-1,0))


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    build();rows=validate()
    leak_rows=watertight_checks()
    kit.EXPORT_DIR=EXPORT
    manifest=kit.export()
    for stale in (EXPORT/'chunks').glob('c*.b64'):
        if stale.name not in {f'c{i:05d}.b64' for i in range(len(manifest['chunks']))}:
            stale.unlink()
    for row in rows:
        chunks=[c for c in manifest['chunks'] if c['component']==row['name']]
        assert sum(c['tris'] for c in chunks)==row['tris']
        assert all(c['tris']<=row['budget'] for c in chunks)
    (EXPORT/'architecture_checks.json').write_text(json.dumps({
        'components':rows,'watertightRays':leak_rows,'totalComponents':len(rows),
        'totalTriangles':sum(r['tris'] for r in rows),
        'runtimeChecks':'Studio gameplay, navigation, multiplayer and performance unverified.'
    },indent=2),encoding='utf-8')
    if '--no-render' in sys.argv:
        print('PR_A_OK '+json.dumps({'components':len(rows)}),flush=True)
        return
    REVIEW.mkdir(parents=True,exist_ok=True)
    sc=bpy.context.scene
    sc.render.engine='BLENDER_EEVEE'
    if hasattr(sc.eevee,'use_raytracing'):sc.eevee.use_raytracing=True
    sc.render.resolution_x=1200;sc.render.resolution_y=800
    sc.render.resolution_percentage=100
    sc.render.image_settings.file_format='PNG'
    sc.world=bpy.data.worlds.new('PR-A green ambient');sc.world.use_nodes=True
    bg=sc.world.node_tree.nodes['Background']
    bg.inputs['Color'].default_value=(.32,.42,.35,1)
    bg.inputs['Strength'].default_value=.35
    sc.view_settings.view_transform='AgX'
    hall_review();spiral_review();detail_review()
    print('PR_A_OK '+json.dumps({'components':len(rows),'tris':sum(r['tris'] for r in rows),
        'renders':[str(p) for p in sorted(REVIEW.glob('A*.png'))]}),flush=True)


if __name__=='__main__':main()
