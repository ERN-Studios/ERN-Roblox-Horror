"""Poolrooms objective visuals: pump, exit platform / stair / collar / mouth / tube, arrival door. Headless only.

D:/Blender/blender.exe -b --factory-startup --python-exit-code 1 -P G:/Roblox/MongoTV/tools/level2_poolrooms/objectives.py

Exit frames (ANALYSIS F11 + F13, owner fix list 2). E = hall.MaxX, F = hall.FloorY, deckZ = hall.MinZ + 42; never yawed:
  platform frame  CFrame.new(E-36, F, deckZ+10)      ExitPlatform, ExitSpiral
  collar frame    CFrame.new(E,    F, deckZ)         ExitCollar, ExitMouthTrim
  tube frame      CFrame.new(E+23, F+81.2, deckZ)    ExitTubeVisual*, BoreSegment markers (reviewed pathPoints, unchanged)
The tube's first path point (-25,0,0) is the collar face E-2.0; its bore floor (apothem 7.2 below the axis) is F+74.0,
flush with the deck top. Collision: one piece per BoreSegment marker, a clone of SlideTemplates[marker Template] with
Size = marker Size at the marker cf: SlideCol_Bore16 (unit-length 16-gon, square cut) or a mitered SlideCol_Bore16_Mnn
(exact copy of a visual segment next to a sharp bend; the helix is one shape). See bore_extents / exact_templates.

Tile lattice (LATTICE_SPEC I3, tile 0.5 from prkit TILE_M): all three frames sit on the world lattice (E, F, deckZ are
multiples of 4; the tube anchor's 81.2 is undone in its UVs), so every tiled Part edge and every flat face's grid is on
local multiples of TILE. The exit proud plane x = E-2.0 is ONE ExitCollar mesh (planar UV) over z deckZ +-9.5,
y F+72.5 .. F+90.5 minus the bore, plus the tube's start cap (planar UV); with the deck (its east face behind the
collar face) and the Wall Strips beside it, that covers the builder's HallWallGap {deckZ, 18.0, F+73, F+90}. Round the bore: N whole tiles (round(perimeter / TILE)) from
the floor-stave centre on the tube and the mouth trim alike. validate() checks all of it with planted negatives.
"""
import hashlib
import json
import math
import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))

import bpy
import numpy as np
from mathutils import Vector, kdtree
import prkit as kit

OUT = Path("G:/Blender/Level2_Poolrooms/jobs/C/export")
REVIEW = Path("G:/Blender/Level2_Poolrooms/review/C")
SLIDES = Path("G:/Blender/Level2_Pool/jobs/F/export/slides.json")
BUDGETS = {}

# ---- exit geometry (studs) -------------------------------------------------------------------------------------
DECK_TOP = 74.0
AXIS_Y = 81.2                     # tube axis above F: the 7.2 apothem bore floor is flush with the deck top
APO_IN, APO_OUT = 7.2, 7.8        # 16-gon bore: inner apothem, 0.6 wall
SIDES = 16
HALF = math.pi / SIDES            # half a stave angle (11.25 deg)
RHO_IN, RHO_OUT = APO_IN / math.cos(HALF), APO_OUT / math.cos(HALF)   # circumradii 7.341 / 7.953
COLLAR_FACE, COLLAR_BACK = -2.0, 0.25      # collar x relative to E; the hall wall spans E-1.75 .. E
# LATTICE_SPEC 6: the builder cuts HallWallGap {deckZ, width 18.0, F+73 .. F+90}; the collar covers z +-9.5 and
# y 72.5 .. 90.5 on the proud plane (its face below the deck top, 74, sits behind the deck's east face; its bottom
# continues the deck's underside across the 0.25 slot to the wall).
FRAME_Z, FRAME_BOTTOM, FRAME_TOP = 9.5, 72.5, 90.5
FILL_SQUARE = 8.0                 # collision fills: the staircase square round the tube (> RHO_OUT), then bands
DECK_BOTTOM = 72.5                # deck, bridge, strips and nose: 1.5 thick under the 74.0 top (on the lattice)
MOUTH_R, MOUTH_PROUD = 9.0, 0.06
E_X, DECK_Z = 36.0, -10.0         # E and deckZ expressed in the platform frame
ANCHOR_X = 23.0                   # tube anchor x relative to E
BORE_TEMPLATE = "SlideCol_Bore16"
EXACT_DEG = 3.5                   # a segment next to a bend this sharp gets mitered collision (see bore_extents)

# Spiral stair (platform frame). Polar angle th: point = (SC.x + r cos th, y, SC.z + r sin th); th grows uphill.
SC = (-45.6, 7.0)
SR_IN, SR_OUT = 4.8, 15.0
TH1 = math.radians(-90.0)         # arrival heading +X onto the bridge
SPAN = math.radians(1080.0)       # three turns
TH0 = TH1 - SPAN
KR = 78.0 / SPAN                  # 26 studs per turn
STEPS = 156
DSTEP = SPAN / STEPS              # 6.923 deg, 0.5 rise
TREAD_LIFT = 0.16                 # tread top = ramp height at the tread's front edge + this
PAR_IN, PAR_OUT = 14.95, 15.6     # parapet band (the stair's r=15 side is buried 0.05 inside it)
CAP_R = (PAR_OUT - PAR_IN) / 2
# Parapet height above the ramp: 3.5 raised to the next height whose outer-face rows (parapet_uv: a row centred on
# the crown, distance round the profile) land on the lattice (y = k * 0.5). At 3.5 they sat at phase 0.4355 and the
# straight run's outer face stepped 0.0645 against the deck's west face in the corner they fold round (step K).
PAR_H = 3.5 + (0.25 - (3.5 - CAP_R + math.pi / 2 * CAP_R)) % 0.5      # 3.5645
PAR_START = TH0 + math.radians(60.0)     # the open first 60 deg is the entry from the pool
BRIDGE_X = (-45.6, -30.0)         # west end = the stair's TH1 line (SC.x, OFF_LATTICE_EDGES)
BRIDGE_Z = (-8.0, 2.5)
BRIDGE_FRAME = ((0, 1, 0), (1, 0, 0), (0, 0, -1))   # (right, up, back): no face of the bridge anchors at SC.x
WALK_Z = (SC[1] - PAR_IN, 2.0)     # bridge walkway between the parapet and the north guard
# Ramp collision: four radial bands, 6 deg segments plus a 3 deg final segment that lands exactly on the bridge.
# (r0, r1, pitch radius). Measured with the walker in test_level2_exit_stair.py: rises 0.011..0.107 per 0.05 stud,
# ramp-helicoid deviation -0.03..+0.06 (ponytail: planar boxes; a helicoid MeshPart would need its own collision).
RAMP_BANDS = (("A", 4.8, 6.4, 5.8), ("B", 6.3, 8.6, 7.9), ("C", 8.5, 11.6, 10.6), ("D", 11.5, 15.0, 13.9))
RAMP_SEG_DEG, RAMP_LAST_DEG, RAMP_T, RAMP_E = 6.0, 3.0, 1.0, 0.02
PAR_BOXES, PAR_RHO = 76, (15.0, 15.3)    # corner radius incl. the slope lean and overlap stays < 15.55
TILE = .5                         # grout pitch in studs (8 x 8 tiles per texture): LATTICE_SPEC 2.1
# prkit turns UV metres into texture repeats with its TILE_M; the export (and the manifest's Part StudsPerTile) only
# draws this module's 0.5 tiles if TILE_M is 8 tiles of TILE.
assert abs(kit.TILE_M - 8 * TILE * kit.S) < 1e-9, ("prkit.TILE_M is not 8 tiles of", TILE, kit.TILE_M)
# The exit hall's pool floor under the stair foot (generator: ExitHall 224 wide, PoolAxis X, deep end at +X,
# DeepEnd 1.6 .. DeepEndMax 2.0; builder floorShell: top = -(d+.8)/2 at the centre, slope (d-.8)/224). A tread top
# within 0.05 of it z-fights (C16 'ExitSpiral | Hall Water Floor'), so such a tread is buried under it (stair_treads).
POOL_WIDTH, POOL_DEEP = 224.0, (1.6, 2.0)
BURY_MARGIN = .1


def trim_v(offset, width):
    """UV v (studs) across a trim narrower than one tile, from its centre: ONE tile row centred on the trim, so no
    grout line runs along it or hugs its edges (same rule as modules_tunnel.trim_v; VERIFY2 '+' ticks)."""
    assert width < TILE-.1, ("trim wider than a tile row", width)
    return offset+TILE/2


def ramp_y(th):
    return -4.0 + KR * (th - TH0)


def base_blend(th):
    """1 at the foot, 0 from 120 deg on: the first third of a turn grows out of the pool floor (G4) instead of
    hanging a helicoid soffit over it."""
    return min(1.0, max(0.0, (120.0 - math.degrees(th - TH0)) / 90.0))


def soffit_y(th):
    return max(-4.5, ramp_y(th) - 1.3 - 5.2 * base_blend(th))


def parapet_bottom(th):
    return max(-4.5, ramp_y(th) - 2.0 - 5.2 * base_blend(th))


def parapet_top(th):
    return ramp_y(th) + PAR_H


def polar(r, th, y):
    return (SC[0] + r * math.cos(th), y, SC[1] + r * math.sin(th))


def stave_vertex(k, rho):
    """(a, b) of 16-gon vertex k in a (right, up) section: staves centred at -90 + 22.5 j deg (flat floor)."""
    psi = -math.pi / 2 + HALF + 2 * HALF * k
    return rho * math.cos(psi), rho * math.sin(psi)


class Solid:
    """Faces of ONE closed body with welded vertices (keyed at 1e-6), handed to Mesh.raw in one call so
    recalc_face_normals sees a manifold. `tags` keeps a label per face for UV assignment."""

    def __init__(self):
        self.verts, self.index, self.faces, self.tags = [], {}, [], []

    def vid(self, p):
        key = tuple(round(float(c), 6) for c in p)
        if key not in self.index:
            self.index[key] = len(self.verts)
            self.verts.append(tuple(float(c) for c in p))
        return self.index[key]

    def face(self, *pts, tag=None):
        ids = []
        for p in pts:
            i = self.vid(p)
            if not ids or ids[-1] != i:
                ids.append(i)
        if len(ids) > 2 and ids[0] == ids[-1]:
            ids.pop()
        assert len(ids) >= 3 and len(set(ids)) == len(ids), ("degenerate face", pts)
        self.faces.append(tuple(ids))
        self.tags.append(tag)

    def emit(self, mesh, mat, uv_by_tag=None, smooth=False):
        mesh.raw(self.verts, self.faces, mat, smooth=smooth)
        if uv_by_tag:
            n = len(self.faces)
            for j, tag in enumerate(self.tags):
                face, _ = mesh.uvf[-n + j]
                mesh.uvf[-n + j] = (face, uv_by_tag.get(tag))


def loft(solid, rings, closed_ends=True, tag=None):
    """Quads between consecutive rings (equal-length closed profiles) plus the two end polygons."""
    for a, b in zip(rings, rings[1:]):
        n = len(a)
        for k in range(n):
            solid.face(a[k], a[(k + 1) % n], b[(k + 1) % n], b[k], tag=tag)
    if closed_ends:
        solid.face(*rings[0], tag="end")
        solid.face(*reversed(rings[-1]), tag="end")


def done(mesh, limit=1500):
    mesh.finish()
    data = kit.COMPONENTS[mesh.name]["mesh"]
    data.calc_loop_triangles()
    tris = len(data.loop_triangles)
    assert tris <= limit, (mesh.name, tris, limit)
    BUDGETS[mesh.name] = tris
    return mesh


def lathe(mesh, rings, mat, n=32, center=(0, 0), axis="Y", closed=False):
    """A connected circular profile with lengthwise tile UVs: whole tiles round (u = angle x round_tiles, about the
    first ring's arc pitch), so the wrap at the back closes on a grout line."""
    round_tiles = round(math.tau * rings[0][1] / TILE) * TILE / math.tau
    verts = []
    for along, radius in rings:
        for i in range(n):
            angle = math.tau * i / n
            c, s = math.cos(angle), math.sin(angle)
            if axis == "Y":
                verts.append((center[0] + radius*c, along, center[1] + radius*s))
            elif axis == "X":
                verts.append((along, center[0] + radius*c, center[1] + radius*s))
    faces = [(j*n+i, j*n+(i+1)%n, (j+1)*n+(i+1)%n, (j+1)*n+i)
             for j in range(len(rings)-1) for i in range(n)]
    if closed:
        faces += [tuple(range(n-1, -1, -1)), tuple((len(rings)-1)*n+i for i in range(n))]
    mesh.raw(verts, faces, mat, smooth=True)

    def make_uv(target, seg):
        # A profile segment narrower than one tile row (the core's 0.3 x 0.3 chamfer) is ONE row centred in the tile
        # (v = trim_v of the distance along the profile): with v = height a grout line ran round the chamfer at
        # y = 77.4 and every cross joint made a '+' on the rim (VERIFY2 F11b).
        (a0, r0), (a1, r1) = rings[seg], rings[seg+1]
        slant = math.hypot(a1-a0, r1-r0)
        def uv(co, no):
            if axis=="Y":
                angle=math.atan2(-co.y-center[1]*kit.S,co.x-center[0]*kit.S)
                along=co.z
            else:
                angle=math.atan2(-co.y-center[1]*kit.S,co.z-center[0]*kit.S)
                along=co.x
            angle+=math.tau*round((target-angle)/math.tau)
            if slant < TILE-.1 and a1 != a0:
                along=trim_v((along/kit.S-(a0+a1)/2)*slant/(a1-a0), slant)*kit.S
            return (angle*round_tiles*kit.S,along)
        return uv
    for j,(face,_) in enumerate(mesh.uvf[-len(faces):]):
        mesh.uvf[-len(faces)+j]=(face,make_uv((j%n+.5)*math.tau/n, j//n) if j<(len(rings)-1)*n else kit.box_uv)


def rod(mesh, a, b, radius, mat="Iron", n=12):
    a, b = Vector(a), Vector(b)
    d = (b-a).normalized()
    ref = Vector((0, 0, 1)) if abs(d.z) < .8 else Vector((1, 0, 0))
    side = d.cross(ref).normalized()
    up = d.cross(side).normalized()
    verts = [tuple(p + radius*(side*math.cos(i*math.tau/n)+up*math.sin(i*math.tau/n)))
             for p in (a, b) for i in range(n)]
    faces = [(i, (i+1)%n, n+(i+1)%n, n+i) for i in range(n)]
    faces += [tuple(range(n-1, -1, -1)), tuple(n+i for i in range(n))]
    mesh.raw(verts, faces, mat, smooth=True)


def pump():
    m = kit.Mesh("PumpStation", Height=6.8, Role="Objective", StaticBody=True)
    # Whole studs about the station centre (a multiple of 0.5 in the world): every plinth edge is on the 0.5 lattice,
    # so its side columns meet the floor's grout lines at the base corners (was 9.2 x 0.96 x 7.2: 0.1 / 0.04 off).
    m.part("Level 2 Pump Plinth", (0, .5, 0), (9.0, 1.0, 7.0), "Tile", ground=True)
    m.collider("Level 2 Pump Body Collider", (0, 3.1, 0), (4.4, 4.4, 3.4))
    # F12-G: every visible iron piece outside the body box has its own collider; all of them stay inside the
    # 9 x 7 plinth and behind the lever plane (z < 1.6), so the lever prompt keeps line of sight.
    for side, label in ((-1, "Left"), (1, "Right")):
        m.collider(f"Level 2 Pump Elbow Collider {label}", (side*2.35, 2.5, -.35), (2.7, .9, .9))
        # The drop pipe is visible from the plinth top (1.0) to the elbow (2.05); its flange is inside the plinth.
        m.collider(f"Level 2 Pump Drop Collider {label}", (side*3.25, 1.55, -.35), (.9, 1.25, .9))
    m.collider("Level 2 Pump Rod Collider H", (2.65, 4.2, -.5), (2.7, 1.0, 1.0))
    m.collider("Level 2 Pump Rod Collider V", (3.5, 2.6, -.5), (1.0, 4.2, 1.0))
    # Inscribed in the r 0.71 gauge disc (no corner outside it), plus the visible stem under it.
    m.collider("Level 2 Pump Gauge Collider", (-1.4, 6.05, .12), (1.0, 1.0, .3))
    m.collider("Level 2 Pump Gauge Stem Collider", (-1.4, 5.775, -.35), (.32, .65, .32))
    # The cast iron drum and broad round front plate have a quieter silhouette
    # than the old cabinet; the tiled plinth remains the only walkable surface.
    lathe(m, [(1.02, 1.75), (1.22, 1.98), (1.4, 1.78), (5.15, 1.78),
              (5.38, 1.98), (5.55, 1.82)], "Iron", 24, center=(-.75, -.35), closed=True)
    lathe(m, [(5.5, 1.5), (5.75, 1.5), (5.75, 1.05), (5.88, 1.05)],
          "Iron", 24, center=(-.75, -.35))
    # Circular machine face, bolts and pipe flanges.
    m.cylinder((-.75, 3.2, 1.51), 1.48, .28, "Iron", 16, axis="Z")
    m.cylinder((-.75, 3.2, 1.7), .47, .22, "Steel", 12, axis="Z")
    for i in range(6):
        a = math.tau*i/6
        m.cylinder((-.75+1.25*math.cos(a), 3.2+1.25*math.sin(a), 1.72), .095, .16,
                   "Steel", 6, axis="Z")
    # Two continuous heavy elbows: one goes into the flooded floor, one into the wall socket.
    for side in (-1, 1):
        x = side*2.35
        route = [(side*1.05, 2.5, -.35), (x, 2.5, -.35),
                 (side*3.25, 2.05, -.35), (side*3.25, .15, -.35)]
        for a,b in zip(route, route[1:]):
            rod(m, a, b, .42, "Iron", 8)
        m.cylinder((side*3.25, .42, -.35), .72, .2, "Iron", 12)
        m.part("Level 2 Pump Intake Pipe", (x, 2.5, -.35), (2.5, .85, .85),
               "Iron", collide=False, show=False,
               attrs={"RuntimeCanQuery": False, "AudioAnchor": True})
    rod(m, (.9, 4.2, -.5), (3.5, 4.2, -.5), .48, n=8)      # starts inside the drum (surface x 1.02 at y 4.2)
    rod(m, (3.5, 4.2, -.5), (3.5, 1, -.5), .48, n=8)
    # Short gauge stem, circular frame, plain dial face (F3: 'Dial', not a tile surface); the needle is separate.
    rod(m, (-1.4, 5.45, -.35), (-1.4, 6.1, -.35), .16, n=12)
    m.cylinder((-1.4, 6.05, .12), .71, .24, "Iron", 24, axis="Z")
    m.cylinder((-1.4, 6.05, .27), .57, .04, "Dial", 24, axis="Z")
    m.part("Level 2 Pump Pressure Gauge Face", (-1.4, 6.05, .27),
           (1.14, 1.14, .04), "Dial", collide=False, show=False)
    m.part("Level 2 Pump Lever Status Ring", (1.0, 3.52, 1.78),
           (.95, .95, .12), "Iron", collide=False,
           attrs={"RuntimeShape":"Cylinder","RuntimeAxis":"Z"})
    m.marker("PumpLeverComponent", (0, 0, 0), Component="PumpLever")
    m.marker("PumpNeedleComponent", (0, 0, 0), Component="PumpNeedle")
    m.marker("PumpLampComponent", (0, 0, 0), Component="PumpLamp")
    done(m, 1500)

    lever = kit.Mesh("PumpLever", Role="AnimatedLever")
    pivot = (1.0, 3.52, 1.88)
    grip = (2.38, 1.53, 2.20)
    lever.cylinder(pivot, .36, .35, "Iron", 16, axis="Z")
    rod(lever, pivot, grip, .23, n=12)
    lever.cylinder(grip, .43, 1.18, "Iron", 16, axis="X")
    lever.part("Level 2 Pump Lever Animated Pivot", pivot, (.3, .3, .3),
               "Iron", collide=False, show=False,
               attrs={"RuntimeTransparency": 1, "RuntimeCanQuery": False})
    lever.part("Level 2 Pump Lever Colored Plastic Grip", grip,
               (1.18, .86, .86), "Iron", collide=False, show=False,
               attrs={"RuntimeCanQuery": True, "PromptParent": True})
    lever.marker("Level 2 Pump Prompt", grip, ClassName="ProximityPrompt",
                 ActionText="START PUMP", HoldDuration=1.6,
                 MaxActivationDistance=10, RequiresLineOfSight=True,
                 ParentPart="Level 2 Pump Lever Colored Plastic Grip")
    lever.marker("LeverRestCFrame", pivot, EulerXYZDegrees=[38, 0, 0],
                 PivotPart="Level 2 Pump Lever Animated Pivot")
    lever.marker("LeverFullCFrame", pivot, EulerXYZDegrees=[-35, 0, 0],
                 PivotPart="Level 2 Pump Lever Animated Pivot")
    lever.marker("LeverAssembly", pivot, ModelName="Level 2 Pump Lever Assembly",
                 Lever="Level 2 Pump Lever Animated Pivot",
                 LeverGrip="Level 2 Pump Lever Colored Plastic Grip")
    done(lever)

    needle = kit.Mesh("PumpNeedle", Role="AnimatedGaugeNeedle")
    np_ = (-1.4, 6.05, .35)
    rod(needle, np_, (-1.12, 6.45, .37), .045, "Iron", 8)
    needle.cylinder(np_, .1, .08, "Iron", 12, axis="Z")
    needle.part("Level 2 Pump Pressure Gauge Needle Pivot", np_, (.12, .12, .08),
                "Iron", collide=False, show=False,
                attrs={"RuntimeTransparency": 1, "RuntimeCanQuery": False})
    needle.part("Level 2 Pump Pressure Gauge Needle",(-1.12,6.45,.37),
                (.09,.58,.09),"Iron",collide=False,show=False,
                attrs={"WeldTo":"Level 2 Pump Pressure Gauge Needle Pivot"})
    needle.marker("GaugeNeedleZeroCFrame", np_, EulerXYZDegrees=[0, 0, 65])
    needle.marker("GaugeNeedleFullCFrame", np_, EulerXYZDegrees=[0, 0, -65])
    needle.marker("GaugePressureValue", np_, ClassName="NumberValue",
                  InstanceName="Level 2 Pump Pressure Value", Value=0)
    needle.marker("GaugePressureText", np_, ClassName="TextLabel",
                  InstanceName="Level 2 Pump Pressure Percent", ParentPart="Level 2 Pump Pressure Gauge Face")
    done(needle)

    lamp = kit.Mesh("PumpLamp", Role="DrivenStatusLamp")
    lamp.cylinder((.9, 5.35, 1.73), .31, .17, "Iron", 16, axis="Z")
    lamp.part("Level 2 Pump Status Lamp", (.9, 5.35, 1.85),
              (.38, .38, .05), "LightWarm", collide=False,
              attrs={"RuntimeShape":"Cylinder","RuntimeAxis":"Z"})
    lamp.marker("Level 2 Pump Status Lamp Glow", (.9, 5.35, 1.9),
                ClassName="PointLight", Brightness=.294, Range=12, Shadows=False,
                ParentPart="Level 2 Pump Status Lamp")
    done(lamp)


# ---- exit platform -----------------------------------------------------------------------------------------------
NOSE_N = 24                 # 24 lip + 24 nose-ground colliders (G8 budget)


def nose_curve():
    """Front edge of the deck: half ellipse over x in [-30, 34] (deck width), 5 deep beyond z = 18."""
    return [(2 + 32 * math.cos(math.pi * i / NOSE_N), 18 + 5 * math.sin(math.pi * i / NOSE_N))
            for i in range(NOSE_N + 1)]


def inward_normals(pts):
    out = []
    for (x0, z0), (x1, z1) in zip(pts, pts[1:]):
        dx, dz = x1 - x0, z1 - z0
        length = math.hypot(dx, dz)
        out.append((-dz / length, dx / length))   # rotate the chord +90 deg: points into the deck
    return out


def platform():
    m = kit.Mesh("ExitPlatform", Role="ExitDeck", Width=64, Depth=46, DeckTopY=DECK_TOP, NoRotation=True,
                 FrameRule="CFrame.new(hall.MaxX-36, hall.FloorY, deckZ+10); deckZ = hall.MinZ+42",
                 DeckEastX=E_X - 2.0)
    m.part("Level 2 Exit Platform Deck", (2, (DECK_BOTTOM + DECK_TOP) / 2, -2.5), (64, DECK_TOP - DECK_BOTTOM, 41),
           "Tile", ground=True)
    # The deck's east face is the collar face (E-2.0); these strips close the 0.25 slot to the wall face (E-1.75)
    # beside the collar (z deckZ +-9.5; the ExitCollar fills it between). Each reaches E-1.5, 0.25 into the wall, so
    # every edge is on the lattice (their tops and bottoms continue the deck's grid).
    sx = E_X + COLLAR_FACE + TILE / 2
    for label, z0, z1 in (("North", -23.0, DECK_Z - FRAME_Z), ("South", DECK_Z + FRAME_Z, 18.0)):
        m.part(f"Level 2 Exit Platform Wall Strip {label}", (sx, (DECK_BOTTOM + DECK_TOP) / 2, (z0 + z1) / 2),
               (TILE, DECK_TOP - DECK_BOTTOM, z1 - z0), "Tile", ground=True)
    lathe(m, [(-4, 5), (73, 5)], "Tile", 32, center=(15, -10), closed=True)
    m.collider("Level 2 Exit Platform Support Collider", (15, 34.5, -10), (10, 77, 10), shape="Cylinder",
               attrs={"CylinderAxis": "Y", "NativeSizeX": 77, "NativeSizeY": 10, "NativeSizeZ": 10,
                      "NativeRotationZ": 90})
    pts = nose_curve()
    normals = inward_normals(pts)
    # Nose: one closed slab between z = 18 (the deck's front face) and the curve.
    nose = Solid()
    top = [(x, DECK_TOP, z) for x, z in pts]
    bottom = [(x, DECK_BOTTOM, z) for x, z in pts]
    nose.face(*top)
    nose.face(*reversed(bottom))
    for i in range(NOSE_N):
        nose.face(bottom[i], bottom[i + 1], top[i + 1], top[i])
    nose.face(bottom[-1], bottom[0], top[0], top[-1])
    nose.emit(m, "Tile")
    # Lip: a closed 0.6 x 0.85 kerb with a half-round top along the curve (offset lines parallel to each chord).
    miters = [normals[0]]
    for a, b in zip(normals, normals[1:]):
        s = 1 + a[0] * b[0] + a[1] * b[1]
        miters.append(((a[0] + b[0]) / s, (a[1] + b[1]) / s))
    miters.append(normals[-1])
    # Offset 0.02 inside the nose edge: the two closed bodies touch face to face, never along a shared edge.
    profile = [(.02, 74.0), (.62, 74.0), (.62, 74.55)]
    profile += [(.32 + .3 * math.cos(math.pi * k / 5), 74.55 + .3 * math.sin(math.pi * k / 5)) for k in range(1, 5)]
    profile.append((.02, 74.55))
    lip = Solid()
    rings = [[(x + o * mx, y, z + o * mz) for o, y in profile] for (x, z), (mx, mz) in zip(pts, miters)]
    loft(lip, rings)
    # UV: u = arc length along the nose, v = distance round the visible profile as 4 tile rows (side, two on the
    # half-round, side: 0.55 / 0.47 / 0.47 / 0.55), so the grout lines lie ON the two creases with the deck, on both
    # shoulders and on the crown, never a line sliding along the kerb near an edge ('+' ticks; box UV cut the curved
    # kerb obliquely). Every row stays inside LATTICE_SPEC 2.4's [0.45, 0.55].
    arc = [0.0]
    for (x0, z0), (x1, z1) in zip(pts, pts[1:]):
        arc.append(arc[-1] + math.hypot(x1 - x0, z1 - z0))
    perim = 2 * .55 + math.pi * .3
    dist = [0.0]
    for (o0, y0), (o1, y1) in zip(profile[1:], profile[2:]):
        dist.append(dist[-1] + math.hypot(o1 - o0, y1 - y0))
    dist.append(perim)                   # the outer side's foot (profile[0], closing the loop)
    s1, s2 = dist[1], dist[-2]           # the inner and outer shoulders (the round's two ends)

    def rows(d):
        if d <= s1:
            return d / s1
        if d >= s2:
            return 3 + (d - s2) / (perim - s2)
        return 1 + 2 * (d - s1) / (s2 - s1)
    info = {}
    for i, ring in enumerate(rings):
        for k, p in enumerate(ring):
            d = dist[k - 1] if k else dist[-1]
            info[tuple(round(c, 6) for c in p)] = (arc[i], rows(d) * TILE, profile[k][0])
    tree = kdtree.KDTree(len(info))
    for j, p in enumerate(info):
        tree.insert(p, j)
    tree.balance()
    keys = list(info)

    def lip_uv(co, no, end=False):
        s, v, o = info[keys[tree.find((co.x / kit.S, co.z / kit.S, -co.y / kit.S))[1]]]
        if end:                          # end caps: planar (offset into the deck, height), 0.3 off both edges
            return ((o + TILE / 2 - .02) * kit.S, (co.z / kit.S - 74.0 + TILE / 2) * kit.S)
        return (s * kit.S, v * kit.S)
    lip.emit(m, "Tile", {None: lip_uv, "end": lambda co, no: lip_uv(co, no, True)}, smooth=True)
    for i, ((x0, z0), (x1, z1)) in enumerate(zip(pts, pts[1:])):
        nx, nz = normals[i]
        dx, dz = x1 - x0, z1 - z0
        chord = math.hypot(dx, dz)
        yaw = kit.yaw_x_along(dx, dz)
        mx, mz = (x0 + x1) / 2, (z0 + z1) / 2
        m.collider(f"Level 2 Exit Platform Lip {i + 1:02d}", (mx + .32 * nx, 74.35, mz + .32 * nz),
                   (chord, .7, .6), yaw=yaw)
        # Walk surface under the curve: an axis-aligned step per chord, from 0.2 inside the deck to the lower end of
        # the chord (inside the silhouette); the kerb boxes back the outer 0.6 along the curve.
        top_z = min(z0, z1)
        if top_z - 17.8 > .05:
            m.collider(f"Level 2 Exit Platform Nose Ground {i + 1:02d}", (mx, 73.35, (top_z + 17.8) / 2),
                       (abs(dx), 1.3, top_z - 17.8), ground=True)
    m.marker("MouthCenter", (E_X + COLLAR_FACE, AXIS_Y, DECK_Z), Axis="X", BoreRadius=8)
    m.marker("CollarPivot", (E_X, 0, DECK_Z), Component="ExitCollar")
    m.marker("TubeAnchor", (E_X + ANCHOR_X, AXIS_Y, DECK_Z), Component="ExitTubeVisual")
    m.marker("SpiralLanding", (BRIDGE_X[1], DECK_TOP, sum(WALK_Z) / 2), Width=WALK_Z[1] - WALK_Z[0])
    m.marker("LightWellCenter", (0, 0, 0), Component="LightWell_R14", Note="old ExitSkylight x/z (retired)")
    done(m, 1500)


# ---- exit spiral stair -------------------------------------------------------------------------------------------

def pool_floor(x, deep):
    """Exit hall pool floor top (relative to F) at platform-frame x for DeepEnd `deep` (see POOL_WIDTH)."""
    return -(deep + .8) / 2 - (x - E_X + POOL_WIDTH / 2) * (deep - .8) / POOL_WIDTH


def floor_band(a, b):
    """(lowest, highest) pool floor top under the stair sector [a, b] over every legal DeepEnd."""
    xs = [SC[0] + r * math.cos(a + (b - a) * k / 8) for k in range(9) for r in (SR_IN, SR_OUT)]
    return min(pool_floor(x, POOL_DEEP[1]) for x in xs), max(pool_floor(x, POOL_DEEP[0]) for x in xs)


def stair_treads():
    """[(top, [angles])]: tread i rises to -4 + 0.5(i+1) and starts where the ramp is TREAD_LIFT below it. A tread
    whose top could lie within 0.05 of the pool floor (floor_band) is buried BURY_MARGIN under its lowest floor."""
    treads = []
    for i in range(-1, STEPS):
        a = max(TH0, TH0 + (i + 1 - TREAD_LIFT / .5) * DSTEP)
        b = min(TH1, TH0 + (i + 2 - TREAD_LIFT / .5) * DSTEP)
        if b - a < 1e-9:
            continue
        n = max(1, round(3 * (b - a) / DSTEP))
        top = -4.0 + .5 * (i + 1)
        lo, hi = floor_band(a, b)
        if lo - .05 < top < hi + .05:
            top = lo - BURY_MARGIN
        treads.append((top, [a + (b - a) * k / n for k in range(n + 1)]))
    assert abs(treads[-1][0] - DECK_TOP) < 1e-9 and abs(treads[-1][1][-1] - TH1) < 1e-12
    assert all(t1 > t0 for (t0, _), (t1, _) in zip(treads, treads[1:])), "a buried tread fell below its neighbour"
    return treads


def tread_top(th):
    """Top of the tread that covers polar angle th (the stair solid's upper surface there)."""
    for top, angs in stair_treads():
        if angs[0] - 1e-12 <= th <= angs[-1] + 1e-12:
            return top
    return DECK_TOP


def helix_uv(co, no):
    """Tile UV (metres) for faces of the stair and parapet: plan projection on flat-ish faces, (arc, height) on the
    cylinder faces (arc from the TH1 end, offset so that its lines meet the bridge's lattice lines x = k TILE where
    the stair ends at x = SC.x), (radius, height) on risers and end faces."""
    x, y, z = co.x / kit.S, co.z / kit.S, -co.y / kit.S
    nx, ny, nz = no.x, no.z, -no.y
    if abs(ny) > .6:
        return (co.x, co.y)
    dx, dz = x - SC[0], z - SC[1]
    rho = max(math.hypot(dx, dz), 1e-9)
    if abs(nx * dx + nz * dz) / rho > .7:
        th = math.atan2(dz, dx)
        guess = TH0 + (y + 1.5 + 4.0) / KR
        th += math.tau * round((guess - th) / math.tau)
        return (((th - TH1) * rho + SC[0]) * kit.S, co.z)
    return (rho * kit.S, co.z)


def stair_uv(co, no):
    """Treads and risers as tiled steps: every tread is gridded square to its own nosing (u along the nosing = the
    riser's u, v from the nosing, so a grout line lies ON each nosing crease), every 0.5 riser is ONE tile row
    from its foot crease (a row cut to 0.5 under the nosing), so the cross joints run from each riser straight over
    its nosing onto the tread. Plan projection cut the rotating nosings obliquely and v = height put a grout line
    along some risers' edges: ticks and stubs at every nosing. Soffit and buried sides keep helix_uv."""
    x, y, z = co.x / kit.S, co.z / kit.S, -co.y / kit.S
    nx, ny, nz = no.x, no.z, -no.y
    steps = (y + 4.0) / .5
    dx, dz = x - SC[0], z - SC[1]
    rho = max(math.hypot(dx, dz), 1e-9)
    th = math.atan2(dz, dx)
    radial = abs(nx * dx + nz * dz) / rho
    if ny > .6 and abs(y - DECK_TOP) < 1e-6:                  # the landing: planar, continues the bridge's lattice
        return (co.x, co.y)
    if ny > .6 and abs(steps - round(steps)) < 1e-6:          # a tread top: the nosing of tread i+1 = steps
        a = max(TH0, TH0 + (round(steps) - TREAD_LIFT / .5) * DSTEP)
        th += math.tau * round((a - th) / math.tau)
        return (rho * math.cos(th - a) * kit.S, rho * math.sin(th - a) * kit.S)
    if abs(ny) < .2 and radial < .3:                           # a riser: rho along, one row up its 0.5
        th += math.tau * round((TH0 + (y + 4.0 - TREAD_LIFT) / KR - th) / math.tau)
        top = -4.0 + .5 * round((th - TH0) / DSTEP + TREAD_LIFT / .5)   # the riser stands at its tread's nosing
        return (rho * kit.S, (y - (top - .5)) * kit.S)
    return helix_uv(co, no)


def parapet_uv(co, no, straight=False):
    """(arc at the band centre, distance around the profile from the crown + half a tile). The rows follow the
    climbing band, a tile row is centred on the crown of the half-round cap (lines at +-0.3 on its shoulders) and the
    cross joints run straight over the cap and down both faces. The old v = height on the faces and a cap phase that
    drifted with the slope let grout lines slide along the cap and its edges: '+' ticks along the parapet (VERIFY2).
    The straight run along the bridge continues the helix's u from the junction (TH1, tangent +X)."""
    x, y, z = co.x / kit.S, co.z / kit.S, -co.y / kit.S
    cr = (PAR_IN + PAR_OUT) / 2
    if straight:
        rho, th = SC[1] - z, TH1
        u = TH1 * cr + (x - SC[0])
    else:
        dx, dz = x - SC[0], z - SC[1]
        rho = math.hypot(dx, dz)
        th = math.atan2(dz, dx)
        guess = TH0 + (y + 1.5 + 4.0) / KR
        th += math.tau * round((guess - th) / math.tau)
        u = th * cr
    side = parapet_top(th) - CAP_R
    quarter = math.pi / 2 * CAP_R
    if no.z < -.6:                      # underside: continues the outer face's distance across the band bottom
        d = -quarter - (side - y) - (PAR_OUT - rho)
    elif y <= side + 1e-6:
        d = -quarter - (side - y) if rho > cr else quarter + (side - y)
    else:
        d = CAP_R * (math.atan2(y - side, rho - cr) - math.pi / 2)
    return (u * kit.S, (d + TILE / 2) * kit.S)


def pitched_frame(th, pitch):
    """X radial at th, Z' along the uphill tangent pitched up by `pitch`, Y' = Z' x X (right-handed)."""
    c, s = math.cos(th), math.sin(th)
    t = np.array((-s, 0.0, c))
    up = np.array((0.0, 1.0, 0.0))
    X = np.array((c, 0.0, s))
    Z = math.cos(pitch) * t + math.sin(pitch) * up
    Y = np.cross(Z, X)
    return X, Y, Z


def spiral():
    m = kit.Mesh("ExitSpiral", Role="ExitAccess", TopY=DECK_TOP, Turns=3, OuterRadius=SR_OUT, CoreRadius=5,
                 Center=list(SC), Theta0Deg=math.degrees(TH0), Theta1Deg=math.degrees(TH1), RampRisePerTurn=26,
                 NoRotation=True, FrameRule="same frame as ExitPlatform")
    # Core: a closed newel from y=-4 (G4) to 3.5 above the deck, chamfered top.
    lathe(m, [(-4, 5), (77.2, 5), (77.5, 4.7)], "Tile", 32, center=SC, closed=True)
    m.collider("Level 2 Exit Spiral Core Collider", (SC[0], 36.75, SC[1]), (10, 81.5, 10), shape="Cylinder",
               attrs={"CylinderAxis": "Y", "NativeSizeX": 81.5, "NativeSizeY": 10, "NativeSizeZ": 10,
                      "NativeRotationZ": 90})
    # The stair: ONE closed solid (treads, risers, both sides, helicoid soffit, start and end faces).
    stair = Solid()
    treads = stair_treads()
    prev = None
    for idx, (top, angs) in enumerate(treads):
        for a, b in zip(angs, angs[1:]):
            stair.face(polar(SR_IN, a, top), polar(SR_IN, b, top), polar(SR_OUT, b, top), polar(SR_OUT, a, top))
            stair.face(polar(SR_IN, a, soffit_y(a)), polar(SR_OUT, a, soffit_y(a)),
                       polar(SR_OUT, b, soffit_y(b)), polar(SR_IN, b, soffit_y(b)))
            for r in (SR_IN, SR_OUT):
                pts = [polar(r, a, soffit_y(a)), polar(r, b, soffit_y(b)), polar(r, b, top), polar(r, a, top)]
                if prev is not None and a == angs[0]:
                    pts.append(polar(r, a, prev))           # riser edge vertex: keeps the side manifold
                stair.face(*pts)
        a = angs[0]
        if prev is None:
            stair.face(polar(SR_IN, a, soffit_y(a)), polar(SR_OUT, a, soffit_y(a)),
                       polar(SR_OUT, a, top), polar(SR_IN, a, top))
        else:
            stair.face(polar(SR_IN, a, prev), polar(SR_OUT, a, prev), polar(SR_OUT, a, top), polar(SR_IN, a, top))
        prev = top
    stair.face(polar(SR_IN, TH1, soffit_y(TH1)), polar(SR_OUT, TH1, soffit_y(TH1)),
               polar(SR_OUT, TH1, DECK_TOP), polar(SR_IN, TH1, DECK_TOP))
    stair.emit(m, "Tile", {None: stair_uv})
    # Parapet: closed band r 14.95..15.6 with a half-round cap, from 60 deg to the top, then straight along the
    # bridge's south edge to the deck (x = -30).
    def ring_helix(th):
        bot, top = parapet_bottom(th), parapet_top(th)
        side = top - CAP_R
        cr = (PAR_IN + PAR_OUT) / 2
        prof = [(PAR_IN, bot), (PAR_OUT, bot), (PAR_OUT, side)]
        prof += [(cr + CAP_R * math.cos(math.pi * k / 5), side + CAP_R * math.sin(math.pi * k / 5)) for k in range(1, 5)]
        prof.append((PAR_IN, side))
        return prof
    n = math.ceil((TH1 - PAR_START) / DSTEP)
    stations = [PAR_START + (TH1 - PAR_START) * k / n for k in range(n + 1)]
    rings = [[polar(r, th, y) for r, y in ring_helix(th)] for th in stations]
    end_prof = ring_helix(TH1)
    straight = [[(x, y, SC[1] - r) for r, y in end_prof] for x in (SC[0], BRIDGE_X[1])]
    parapet = Solid()
    loft(parapet, rings, closed_ends=False, tag="helix")
    loft(parapet, straight, closed_ends=False, tag="straight")
    parapet.face(*rings[0], tag="end")
    parapet.face(*reversed(straight[-1]))       # the straight run's end on the deck edge: planar on the lattice
    parapet.emit(m, "Tile", {"helix": parapet_uv, "end": helix_uv,
                             "straight": lambda co, no: parapet_uv(co, no, straight=True)}, smooth=True)
    # Landing: the bridge onto the deck and its north guard are plain tile Parts (G6: they collide themselves).
    # Both run from the off-lattice west end (SC.x) to the lattice east end. A Part face anchors its grid at one corner
    # (object space, TILE_PHASE.md), so they are turned until no face anchors at the west end: object X up, object Y
    # east, object Z = -Z (sizes height, length, depth). Every face then anchors at the east end and at lattice y / z
    # edges (check_part_faces); axis-aligned, the +Z side faces anchored at the west end and stood 0.1 off.
    bx0, bx1 = BRIDGE_X
    m.part("Level 2 Exit Spiral Bridge", ((bx0 + bx1) / 2, (DECK_BOTTOM + DECK_TOP) / 2, sum(BRIDGE_Z) / 2),
           (DECK_TOP - DECK_BOTTOM, bx1 - bx0, BRIDGE_Z[1] - BRIDGE_Z[0]), "Tile", ground=True, frame=BRIDGE_FRAME)
    m.part("Level 2 Exit Spiral Bridge North Guard", ((bx0 + bx1) / 2, 75.75, (WALK_Z[1] + BRIDGE_Z[1]) / 2),
           (3.5, bx1 - bx0, BRIDGE_Z[1] - WALK_Z[1]), "Tile", frame=BRIDGE_FRAME)
    m.collider("Level 2 Exit Spiral Bridge South Guard Collider",
               ((bx0 + bx1) / 2, (72.05 + 77.5 - CAP_R) / 2, SC[1] - 15.275),
               (bx1 - bx0, 77.5 - CAP_R - 72.05, .55))
    # Ramp collision: the only walk surface on the stair. Planar boxes, X radial, pitched along the helix.
    span = 1080.0 - RAMP_LAST_DEG
    for band, r0, r1, rc in RAMP_BANDS:
        count = math.ceil(span / RAMP_SEG_DEG)
        d = math.radians(span / count)
        segs = [(TH0 + j * d, TH0 + (j + 1) * d, False) for j in range(count)]
        segs.append((TH1 - math.radians(RAMP_LAST_DEG), TH1, True))
        for i, (ta, tb, last) in enumerate(segs):
            tm, h = (ta + tb) / 2, (tb - ta) / 2
            # The final segment pitches at the band's outer radius and meets 74.0 at (r1, TH1): nowhere on the
            # bridge side of TH1 does it stand more than 0.003 above the bridge top.
            pitch = math.atan(KR / (r1 if last else rc))
            top = DECK_TOP - KR * math.tan(h) if last else ramp_y(tm)
            ri = r0 * math.cos(h)
            sw = r1 * math.tan(h) + RAMP_E / 2
            ro = math.sqrt((r1 - .01) ** 2 - sw * sw)     # outer corners inside r1 and the faceted r=15 side
            X, Y, Z = pitched_frame(tm, pitch)
            ctop = np.array(polar((ri + ro) / 2, tm, top))
            m.collider(f"Level 2 Exit Spiral Ramp {band} {i + 1:03d}", tuple(ctop - RAMP_T / 2 * Y),
                       (ro - ri, RAMP_T, 2 * sw / math.cos(pitch)), ground=True, frame=(X, Y, Z),
                       attrs={"Level2_StairRamp": True})
    # Parapet collision: boxes inside the visual band (radial 15.0..15.35, from 0.05 above its bottom to its cap
    # line), consecutive boxes overlap; the two hard ends are shrunk so no corner passes the band's end faces.
    rho_i, rho_o = PAR_RHO
    rp = (rho_i + rho_o) / 2
    pitch = math.atan(KR / rp)
    d = (TH1 - PAR_START) / PAR_BOXES
    h = d / 2
    lo, hi = -1.95, PAR_H - CAP_R
    hl = (hi - lo) * math.cos(pitch)
    slant = hl / 2 * math.sin(pitch)
    for i in range(PAR_BOXES):
        tm = PAR_START + (i + .5) * d
        hard = rho_i * math.tan(h) - .02 - slant        # mid-height reach of a hard end
        # Interior ends overlap their neighbour by 0.3: the lean of two neighbours differs by slant * d radially.
        reach = rho_o * math.tan(h) + .3
        s_lo = -hard if i == 0 else -reach
        s_hi = hard if i == PAR_BOXES - 1 else reach
        sc = (s_lo + s_hi) / 2
        X, Y, Z = pitched_frame(tm, pitch)
        t = np.array((-math.sin(tm), 0.0, math.cos(tm)))
        centre = np.array(polar(rp, tm, ramp_y(tm) + (lo + hi) / 2 + sc * math.tan(pitch))) + sc * t
        m.collider(f"Level 2 Exit Spiral Parapet {i + 1:03d}", tuple(centre),
                   (rho_o - rho_i, hl, (s_hi - s_lo) / math.cos(pitch)), frame=(X, Y, Z))
    # The pitched boxes' end faces lean with the slope, so each hard end leaves a 1.3-stud wedge (bottom at the
    # entry, top at the bridge); an upright box fills each wedge, inside the band.
    for label, ta, tb in (("Start", PAR_START + .002, PAR_START + .09), ("Junction", TH1 - .09, TH1)):
        tm, h = (ta + tb) / 2, (tb - ta) / 2
        bottom = parapet_bottom(min(TH1, tb + DSTEP)) + .05     # the band's bottom is linear between stations
        top = ramp_y(ta) + PAR_H - CAP_R
        sw = rho_i * math.tan(h)
        X, Y, Z = pitched_frame(tm, 0.0)
        m.collider(f"Level 2 Exit Spiral Parapet {label}", polar(rp, tm, (bottom + top) / 2),
                   (rho_o - rho_i, top - bottom, 2 * sw), frame=(X, Y, Z))
    # The foot (first 125 deg) is a thick solid down to the floor: upright boxes back its underside, kept 0.3 under
    # the ramp top (never a bump in the walk) and above the soffit / band bottom (inside the visual).
    for label, r0, r1, start, top_off in (("Base", SR_IN, SR_OUT, TH0, -.3), ("Parapet Base", rho_i, rho_o, PAR_START, -1.5)):
        seg = math.radians(4.0)
        count = math.ceil((TH0 + math.radians(125) - start) / seg)
        for i in range(count):
            ta = start + i * seg + (.002 if i == 0 else 0)
            tb = start + (i + 1) * seg
            tm, h = (ta + tb) / 2, (tb - ta) / 2
            if label == "Base":
                bottom = soffit_y(tb) + .02
            else:   # the band's bottom is linear between its stations
                bottom = parapet_bottom(min(TH1, PAR_START + DSTEP * math.ceil((tb - PAR_START) / DSTEP))) + .05
            top = ramp_y(ta) + top_off
            if label == "Base":         # never above the visible tread (a buried tread sits under the ramp)
                top = min(top, min(tread_top(ta + (tb - ta) * k / 8) for k in range(9)) - .02)
            if top - bottom < .2:
                continue
            ri, ro = r0, r1 * math.cos(h) - .01
            sw = ri * math.tan(h)
            X, Y, Z = pitched_frame(tm, 0.0)
            m.collider(f"Level 2 Exit Spiral {label} {i + 1:02d}", polar((ri + ro) / 2, tm, (bottom + top) / 2),
                       (ro - ri, top - bottom, 2 * sw), frame=(X, Y, Z))
    m.marker("SpiralStart", polar((SR_IN + SR_OUT) / 2, TH0 + math.radians(45), ramp_y(TH0 + math.radians(45))))
    m.marker("SpiralEnd", (BRIDGE_X[1], DECK_TOP, sum(WALK_Z) / 2))
    done(m, 9000)


# ---- exit collar, mouth trim -------------------------------------------------------------------------------------

def bore_tiles(apo):
    """Whole tiles round the 16-gon of apothem apo: round(perimeter / TILE) (92 inside, 99 outside at 0.5)."""
    return round(SIDES * 2 * apo * math.tan(HALF) / TILE)


def bore_stave(a, b):
    """Stave index -7 .. 8 (0 = floor, 8 = crown) of the section direction (a right, b up) away from the axis."""
    c = round((math.atan2(b, a) + math.pi / 2) / (2 * HALF)) % SIDES
    return c - SIDES if c > SIDES // 2 else c


def bore_u(a, b, c, apo):
    """Studs of u round the bore at section point (a, b) on stave c: the arc from the floor stave's centre, scaled to
    bore_tiles(apo) whole tiles, so the floor's lines fall on the deck's (within 0.004 over its 2.86 width) and the
    wrap at the crown's -right edge closes on a grout line. ExitTubeVisual and ExitMouthTrim share it."""
    w = 2 * apo * math.tan(HALF)
    psi = -math.pi / 2 + 2 * HALF * c
    lateral = -a * math.sin(psi) + b * math.cos(psi)
    return (c * w + lateral) * bore_tiles(apo) * TILE / (SIDES * w)


def bore_point(apo, theta):
    """The 16-gon of apothem apo in section direction theta (staves centred at -90 + 22.5 c deg)."""
    psi = -math.pi / 2 + 2 * HALF * round((theta + math.pi / 2) / (2 * HALF))
    r = apo / math.cos(theta - psi)
    return r * math.cos(theta), r * math.sin(theta)


def collar():
    """ONE closed frame on the proud plane x = E-2.0 (LATTICE_SPEC I3.2): z deckZ +-9.5, y F+72.5 .. F+90.5 minus
    the tube's outer 16-gon, from the face back through the wall to E+0.25. Box (planar) UV in its lattice frame: the
    face continues the tube's planar start cap round the bore and every line is on the world lattice. Below F+74 the
    face sits behind the deck's east face and its bottom continues the deck's underside; the Wall Strips own the
    0.25 slot beside it."""
    m = kit.Mesh("ExitCollar", Role="ExitCollar", NoRotation=True, FrameZ=FRAME_Z, FrameBottomY=FRAME_BOTTOM,
                 FrameTopY=FRAME_TOP, FaceX=COLLAR_FACE, BackX=COLLAR_BACK, AxisY=AXIS_Y,
                 FrameRule="CFrame.new(hall.MaxX, hall.FloorY, deckZ)")
    up, down = FRAME_TOP - AXIS_Y, AXIS_Y - FRAME_BOTTOM
    # Inner loop = the tube's outer 16-gon plus the points in the four frame-corner directions; outer loop = the
    # radial projection of each onto the frame rectangle (the corners land exactly on its corners).
    angles = [math.atan2(b, a) for a, b in (stave_vertex(k, RHO_OUT) for k in range(SIDES))]
    angles += [math.atan2(up, FRAME_Z), math.atan2(up, -FRAME_Z), math.atan2(-down, -FRAME_Z), math.atan2(-down, FRAME_Z)]
    inner = [bore_point(APO_OUT, t) for t in sorted(angles)]

    def project(a, b):
        s = min(FRAME_Z / abs(a) if abs(a) > 1e-12 else math.inf,
                up / b if b > 1e-12 else down / -b if b < -1e-12 else math.inf)
        return a * s, b * s
    outer = [project(a, b) for a, b in inner]

    def pt(x, ab):
        return (x, AXIS_Y + ab[1], ab[0])
    s = Solid()
    n = len(inner)
    for k in range(n):
        j = (k + 1) % n
        s.face(pt(COLLAR_FACE, inner[k]), pt(COLLAR_FACE, inner[j]), pt(COLLAR_FACE, outer[j]), pt(COLLAR_FACE, outer[k]))
        s.face(pt(COLLAR_BACK, inner[k]), pt(COLLAR_BACK, outer[k]), pt(COLLAR_BACK, outer[j]), pt(COLLAR_BACK, inner[j]))
        s.face(pt(COLLAR_FACE, inner[k]), pt(COLLAR_BACK, inner[k]), pt(COLLAR_BACK, inner[j]), pt(COLLAR_FACE, inner[j]))
        s.face(pt(COLLAR_FACE, outer[k]), pt(COLLAR_FACE, outer[j]), pt(COLLAR_BACK, outer[j]), pt(COLLAR_BACK, outer[k]))
    s.emit(m, "Tile")
    depth, xc, sq = COLLAR_BACK - COLLAR_FACE, (COLLAR_FACE + COLLAR_BACK) / 2, FILL_SQUARE
    low = AXIS_Y - FRAME_BOTTOM          # below the square the fills reach the frame bottom (no separate band)
    for sz in (-1, 1):
        for sy in (-1, 1):
            outer = low if sy < 0 else sq
            m.collider(f"Level 2 Exit Collar Corner Fill {'L' if sz < 0 else 'R'}{'B' if sy < 0 else 'T'}",
                       (xc, AXIS_Y + sy * (5.6 + outer) / 2, sz * (5.6 + sq) / 2), (depth, outer - 5.6, sq - 5.6))
    # Side fills: per half-octant a 3-step staircase between the tube's outer 16-gon and the +-8 square. Each step's
    # inner face sits where the 16-gon is widest over its band, so no box enters the hole, and every collar face
    # stays within 0.9 of a box (the hole wall drops <= 0.9 per band; audit: share beyond 0.6 <= 0.02, gap <= 1).
    def poly_z(y):
        return min((APO_OUT - y * math.sin(k * 2 * HALF)) / math.cos(k * 2 * HALF) for k in range(3))
    bands = ((0.0, 3.72), (3.72, 5.03), (5.03, 5.6))
    index = 0
    for sz in (-1, 1):
        for sy in (-1, 1):
            for swap in (False, True):
                for y0, y1 in bands:
                    z0 = min(poly_z(y0), sq - .05)
                    outer = low if swap and sy < 0 else sq
                    a, b = (outer + z0) / 2, (y0 + y1) / 2
                    da, db = outer - z0, y1 - y0
                    if swap:
                        a, b, da, db = b, a, db, da
                    index += 1
                    m.collider(f"Level 2 Exit Collar Side Fill {index:02d}", (xc, AXIS_Y + sy * b, sz * a), (depth, db, da))
    # The frame outside the square: both sides from the frame bottom to the square's top, then the top band.
    for sz, label in ((-1, "Left"), (1, "Right")):
        m.collider(f"Level 2 Exit Collar Band {label}", (xc, (FRAME_BOTTOM + AXIS_Y + sq) / 2, sz * (sq + FRAME_Z) / 2),
                   (depth, AXIS_Y + sq - FRAME_BOTTOM, FRAME_Z - sq))
    m.collider("Level 2 Exit Collar Band Top", (xc, (AXIS_Y + sq + FRAME_TOP) / 2, 0),
               (depth, FRAME_TOP - AXIS_Y - sq, 2 * FRAME_Z))
    m.marker("CollarFace", (COLLAR_FACE, AXIS_Y, 0), Axis="X")
    done(m, 1500)


def mouth_trim():
    """The recolour target (builder: Exit.Mouth): an arch inlay from the bore's 16-gon to r 9, above the deck top,
    0.06 proud of the opaque collar, so the controller's pale green at 0.35 transparency still reads as a solid ring.
    Its bore faces continue the tube's inner staves (bore_u round, v along the axis from the collar plane); the rest
    is planar on the lattice like the collar under it."""
    m = kit.Mesh("ExitMouthTrim", Role="RecolorableExitMouth", NoRotation=True, RecolorTarget=True,
                 BoreRadius=8, FrameRule="CFrame.new(hall.MaxX, hall.FloorY, deckZ)")
    inner = []
    for k in range(SIDES - 1):          # vertex 0 (-78.75) .. vertex 15 (258.75): everything but the floor stave
        a0, a1 = stave_vertex(k, RHO_IN), stave_vertex(k + 1, RHO_IN)
        for q in range(3):
            inner.append((a0[0] + (a1[0] - a0[0]) * q / 3, a0[1] + (a1[1] - a0[1]) * q / 3))
    inner.append(stave_vertex(SIDES - 1, RHO_IN))
    lo = math.asin(-APO_IN / MOUTH_R)
    span = math.pi - 2 * lo
    outer = [(MOUTH_R * math.cos(lo + span * i / (len(inner) - 1)), MOUTH_R * math.sin(lo + span * i / (len(inner) - 1)))
             for i in range(len(inner))]
    x0, x1 = COLLAR_FACE - MOUTH_PROUD, COLLAR_FACE
    def pt(x, ab):
        return (x, AXIS_Y + ab[1], ab[0])
    s = Solid()
    for i in range(len(inner) - 1):
        s.face(pt(x0, inner[i]), pt(x0, inner[i + 1]), pt(x0, outer[i + 1]), pt(x0, outer[i]))
        s.face(pt(x1, inner[i]), pt(x1, outer[i]), pt(x1, outer[i + 1]), pt(x1, inner[i + 1]))
        s.face(pt(x0, inner[i]), pt(x1, inner[i]), pt(x1, inner[i + 1]), pt(x0, inner[i + 1]), tag="bore")
        s.face(pt(x0, outer[i]), pt(x0, outer[i + 1]), pt(x1, outer[i + 1]), pt(x1, outer[i]))
    for i in (0, len(inner) - 1):
        s.face(pt(x0, inner[i]), pt(x0, outer[i]), pt(x1, outer[i]), pt(x1, inner[i]))

    def bore_uv(co, no):
        a, b = -co.y / kit.S, co.z / kit.S - AXIS_Y
        c = bore_stave(no.y, -no.z)             # the face's solid-outward normal points at the axis
        return (bore_u(a, b, c, APO_IN) * kit.S, (co.x / kit.S - COLLAR_FACE) * kit.S)
    s.emit(m, "Tile", {"bore": bore_uv})
    m.marker("Mouth", (x0, AXIS_Y, 0), Axis="X", RecolorTarget=True)
    done(m, 1500)


# ---- exit tube: visual + collision template from ONE path and ONE cross-section ---------------------------------

def path_frames(points):
    """Per-segment frames shared by the visual and the BoreSegment markers: look along the segment,
    right = look x Y, up = right x look (so CFrame back = -look)."""
    P = np.array(points, float)
    look = P[1:] - P[:-1]
    lengths = np.linalg.norm(look, axis=1)
    look /= lengths[:, None]
    right = np.cross(look, (0.0, 1.0, 0.0))
    right /= np.linalg.norm(right, axis=1)[:, None]
    up = np.cross(right, look)
    return P, lengths, look, right, up


def bore_extents(look):
    """Square-cut pieces (SlideCol_Bore16 scaled to SizeZ) at a joint of bend phi, t = tan(phi/2): the visual miter
    reaches RHO_IN*t past the joint on the bend's outside and stops RHO_IN*t short of it on the inside, so each piece
    reaches RHO_IN*t (+0.005) past both of its joints to cover its own visual exactly. It then stands about
    (RHO_IN*t + APO_IN*t)*sin(phi) inside its neighbour's bore on the inside of the bend (0.024 at 3.3 deg); the
    no-roll frames' twist (1.23 deg per helix joint) adds 0.03 at a stave corner. Covering less is no way out: a
    neighbour's twisted stave misses the visual by 0.03, over the 0.02 rule. Above EXACT_DEG the sum passes F13's
    0.1 (0.106 per helix joint, 0.13 at the entry crest), so those segments get mitered collision templates
    (exact copies of the visual segment; extensions unused). Returns (back[j], fwd[j]) and the bend angles."""
    n = len(look)
    back, fwd, phis = np.zeros(n), np.zeros(n), np.zeros(n - 1)
    for j in range(n - 1):
        phis[j] = math.atan2(np.linalg.norm(np.cross(look[j], look[j + 1])), look[j] @ look[j + 1])
        back[j + 1] = fwd[j] = RHO_IN * math.tan(phis[j] / 2) + .005
    return back, fwd, phis


def exact_templates(P, rings, right, up, look):
    """Mitered collision for every segment next to a bend >= EXACT_DEG: the 16 stave prisms of the visual segment,
    in the segment frame (origin at its bounding-box centre). Congruent segments share one template
    (the helix is one shape). Returns {segment: (template name, centre offset in the frame, size)}."""
    n = len(look)
    phi = [0.0] + [math.degrees(math.acos(min(1.0, float(look[j] @ look[j + 1])))) for j in range(n - 1)] + [0.0]
    groups, out = {}, {}
    for j in range(n):
        if max(phi[j], phi[j + 1]) < EXACT_DEG:
            continue
        R = np.stack([right[j], up[j], -look[j]], 1)
        mid = (P[j] + P[j + 1]) / 2
        local = [(np.array(rings[j][i][0]) - mid) @ R for i in range(4)]       # inner start/end, outer start/end
        allp = np.concatenate(local)
        centre = (allp.min(0) + allp.max(0)) / 2
        local = [x - centre for x in local]
        key = tuple(np.round(np.concatenate(local), 3).ravel())
        if key not in groups:
            groups[key] = (f"SlideCol_Bore16_M{len(groups) + 1:02d}", local, [])
        groups[key][2].append(j)
        out[j] = (groups[key][0], centre, (allp.max(0) - allp.min(0)).tolist())
    for name, local, segs in groups.values():
        m = kit.Mesh(name, Template=True, Role="SlideCollisionTemplate", Sides=SIDES, InnerApothem=APO_IN,
                     OuterApothem=APO_OUT, Mitered=True, Segments=[j + 1 for j in segs],
                     SizeRule="Size = marker Size (native), CFrame = marker cf, at each BoreSegment marker naming it")
        i_s, i_e, o_s, o_e = local
        for k in range(SIDES):
            q = (k + 1) % SIDES
            st = Solid()
            loft(st, [[i_s[k], i_s[q], o_s[q], o_s[k]], [i_e[k], i_e[q], o_e[q], o_e[k]]])
            st.emit(m, "Tile")
        done(m, 400)
    return out


def bore_template():
    m = kit.Mesh(BORE_TEMPLATE, Template=True, Role="SlideCollisionTemplate", Sides=SIDES, InnerApothem=APO_IN,
                 OuterApothem=APO_OUT, UnitLengthAxis="Z", Size=[2 * APO_OUT, 2 * APO_OUT, 1.0],
                 SizeRule="Size = (15.6, 15.6, marker SizeZ), CFrame = marker cf, at each BoreSegment marker")
    for k in range(SIDES):
        a0, a1 = stave_vertex(k, RHO_IN), stave_vertex(k + 1, RHO_IN)
        b0, b1 = stave_vertex(k, RHO_OUT), stave_vertex(k + 1, RHO_OUT)
        s = Solid()
        ring = [a0, a1, b1, b0]
        loft(s, [[(p[0], p[1], z) for p in ring] for z in (-.5, .5)])
        s.emit(m, "Tile")
    done(m, 400)


def tube_visual():
    raw = SLIDES.read_bytes()
    rec = json.loads(raw)["slides"]["ExitFlume_Tube"]
    assert rec["pathPoints"][0] == [-25.0, 0.0, 0.0] and rec["pathPoints"][1] == [0.0, 0.0, 0.0]
    assert len(rec["pathPoints"]) == len(rec["segments"]) + 1 == 272
    P, L, look, right, up = path_frames(rec["pathPoints"])
    n = len(L)
    planes = [look[0]] + [(look[j - 1] + look[j]) / np.linalg.norm(look[j - 1] + look[j]) for j in range(1, n)] + [look[-1]]
    arc = np.concatenate([[0.0], np.cumsum(L)])
    mids = (P[1:] + P[:-1]) / 2
    back, fwd, _ = bore_extents(look)

    def ring(j, at, rho):
        pts, ts = [], []
        for k in range(SIDES):
            a, b = stave_vertex(k, rho)
            o = a * right[j] + b * up[j]
            t = -(o @ planes[at]) / (look[j] @ planes[at])
            pts.append(P[at] + o + t * look[j])
            ts.append(arc[at] + t)
        return pts, ts

    rings = []
    for j in range(n):   # (inner start, inner end, outer start, outer end), each (points, along)
        rings.append([ring(j, j, RHO_IN), ring(j, j + 1, RHO_IN), ring(j, j, RHO_OUT), ring(j, j + 1, RHO_OUT)])
    # Chunk joints (LATTICE_SPEC I3.3): the first in the straight run after the lead's bends (segments 74..90, bend
    # 0), where both chunks' rings, v and v pitch are identical; the rest at helix joints, whose twisted rings share no
    # edge (two caps back to back). At joint 62 (bend 0.95) the two sides' v pitch differed (C16 'pitch' rows).
    bounds = [0, 80, 128, 176, 224, n]
    assert float(look[bounds[1] - 1] @ look[bounds[1]]) > 1 - 1e-12, "first tube chunk joint must be straight"
    shared = set()
    for j in range(1, n):
        if j in bounds:
            continue
        gap = max(np.abs(np.array(rings[j - 1][1][0]) - np.array(rings[j][0][0])).max(),
                  np.abs(np.array(rings[j - 1][3][0]) - np.array(rings[j][2][0])).max())
        if gap < 1e-3:   # planar joints: the two miter cuts coincide, one ring serves both segments
            rings[j][0], rings[j][2] = rings[j - 1][1], rings[j - 1][3]
            shared.add(j)
    exact = exact_templates(P, rings, right, up, look)
    oneway = [bool(s.get("oneWay")) for s in rec["segments"]]
    chunks = []
    source_sha = hashlib.sha256(raw).hexdigest()
    for c0, c1 in zip(bounds, bounds[1:]):
        name = "ExitTubeVisual" if not chunks else f"ExitTubeVisual_{len(chunks) + 1:02d}"
        m = kit.Mesh(name, Role="ExitFlumeVisual", NoRotation=True,
                     AnchorRule="Pivot = anchor = (hall.MaxX+23, hall.FloorY+81.2, deckZ); never yaw",
                     PathStartIndex=c0, PathEndIndex=c1, Sides=SIDES, InnerApothem=APO_IN, OuterApothem=APO_OUT,
                     CollisionTemplate="per BoreSegment marker (attr Template)", PathSourceSha256=source_sha)
        # Staves: one welded mesh per chunk (shared rings at planar joints), smooth-shaded (22.5 deg < SHARP_DEG),
        # so the 16 staves do not read as lengthwise light/dark stripes (G2). UV per loop: u = bore_u (whole tiles
        # round from the floor stave's centre, unwrapped next to the face: no seam vertex), v = arc length along the
        # path (0 at the collar plane E-2.0, on the lattice).
        verts, faces, info, vid = [], [], [], {}

        def vert(key, p, k, along, inner_side, j):
            if key not in vid:
                vid[key] = len(verts)
                verts.append(tuple(p))
                info.append((k, along, inner_side, j))
            return vid[key]
        for j in range(c0, c1):
            js = j - 1 if j in shared else j            # a shared start ring is the previous segment's end ring
            for side, (start, end) in ((True, (0, 1)), (False, (2, 3))):
                (ps, vs), (pe, ve) = rings[j][start], rings[j][end]
                ks = [vert((js, start if js == j else end, k), ps[k], k, vs[k], side, j) for k in range(SIDES)]
                ke = [vert((j, end, k), pe[k], k, ve[k], side, j) for k in range(SIDES)]
                for k in range(SIDES):
                    q = (k + 1) % SIDES
                    faces.append((ks[k], ks[q], ke[q], ke[k]))
        tree = kdtree.KDTree(len(verts))
        for i, p in enumerate(verts):
            tree.insert(p, i)
        tree.balance()

        def stave_uv(co, no, info=info, tree=tree):
            p = (co.x / kit.S, co.z / kit.S, -co.y / kit.S)
            k, along, inner_side, j = info[tree.find(p)[1]]
            n = np.array((no.x, no.z, -no.y)) * (-1 if inner_side else 1)      # outward radial of the face
            c = bore_stave(n @ right[j], n @ up[j])                               # stave centre index
            kk = k + SIDES * round((c - k - .5) / SIDES)
            apo = APO_IN if inner_side else APO_OUT
            return ((kk + .5) * bore_tiles(apo) * TILE / SIDES * kit.S, along * kit.S)

        def facing(p):
            j = int(np.argmin(np.linalg.norm(mids[c0:c1] - p, axis=1))) + c0
            d = np.array(p) - P[j]
            perp = d - (d @ look[j]) * look[j]
            return tuple(-perp if np.linalg.norm(perp) < (APO_IN + APO_OUT) / 2 else perp)
        m.raw(verts, faces, "Tile", uv=stave_uv, smooth=True, facing=facing)
        for j in range(c0, c1):
            (is_, _), (ie, _), (os_, _), (oe, _) = rings[j]
            caps = []
            if j not in shared:            # chunk starts are never shared
                caps.append((is_, os_, -look[j]))
            if j + 1 == c1 or (j + 1) not in shared:
                caps.append((ie, oe, look[j]))
            for inner_ring, outer_ring, toward in caps:
                cv, cf, cu = [], [], []
                for k in range(SIDES):
                    q = (k + 1) % SIDES
                    base = len(cv)
                    for p in (inner_ring[k], outer_ring[k], outer_ring[q], inner_ring[q]):
                        cv.append(tuple(p))
                        # planar in the anchor frame, y back on F (+81.2): the start cap continues the collar's grid
                        cu.append((float(p @ right[j]) * kit.S, float(p @ up[j] + AXIS_Y) * kit.S))
                    cf.append((base, base + 1, base + 2, base + 3))
                m.raw(cv, cf, "Tile", facing=lambda p, toward=toward: tuple(toward), vertex_uv=cu)
            # Collision piece j: a mitered template (exact copy of this visual segment), or SlideCol_Bore16 scaled
            # to span [P[j] - back[j], P[j+1] + fwd[j]] along look[j] (see bore_extents).
            frame = np.stack([right[j], up[j], -look[j]], 1)
            if j in exact:
                tpl, centre, size = exact[j]
                pos = (P[j] + P[j + 1]) / 2 + frame @ centre
                ext = (0.0, 0.0)
            else:
                start, end = P[j] - back[j] * look[j], P[j + 1] + fwd[j] * look[j]
                tpl, pos, size = BORE_TEMPLATE, (start + end) / 2, [2 * APO_OUT, 2 * APO_OUT, float(np.linalg.norm(end - start))]
                ext = (float(back[j]), float(fwd[j]))
            m.marker("BoreSegment", tuple(pos), frame=(right[j], up[j], -look[j]), Index=j + 1, Length=float(L[j]),
                     Template=tpl, Size=[float(x) for x in size], BackExtension=ext[0], ForwardExtension=ext[1],
                     OneWay=oneway[j])
        done(m, 20000)
        chunks.append(name)
    assert len(chunks) == 5 and sum(BUDGETS[x] for x in chunks) <= 100000
    assert all(kit.COMPONENTS[x]["mesh"].materials[0].name == "PR_Tile" for x in chunks)
    return chunks


# ---- arrival door ------------------------------------------------------------------------------------------------

ARRIVAL_HALF, ARRIVAL_RISE = 7.0, 6.35   # LATTICE_SPEC 6: frame 14.0 wide (builder CoveOnly hole +-7.0), top 21.35


def door_arch(mesh, inner=5, outer=(ARRIVAL_HALF, ARRIVAL_RISE), top=15, n=24):
    """Arch over the jambs: inner circle r 5, outer half-ellipse (half-width, rise)."""
    verts=[]
    for z in (-.8,.12):
        for rx,ry in ((inner,inner),outer):
            for i in range(n+1):
                a=math.pi*i/n
                verts.append((rx*math.cos(a),top+ry*math.sin(a),z))
    row=n+1
    faces=[]
    for i in range(n):
        faces += [(i,i+1,row+i+1,row+i),
                  (2*row+i,3*row+i,3*row+i+1,2*row+i+1),
                  (i,2*row+i,2*row+i+1,i+1),
                  (row+i,row+i+1,3*row+i+1,3*row+i)]
    faces += [(0,row,3*row,2*row),(n,2*row+n,3*row+n,row+n)]   # closed ends where the arch sits on the jambs
    mesh.raw(verts,faces,"Tile",smooth=True)


def arrival():
    m=kit.Mesh("ArrivalDoor",Role="StoryGate",Width=24,Height=26,FrameWidth=2*ARRIVAL_HALF)
    for name,center,size in (
        ("Left",(-8.5,13,0),(7,26,1)),
        ("Right",(8.5,13,0),(7,26,1)),
        ("Upper",(0,23,0),(10,6,1))):
        m.part(f"Level 2 Arrival Wall {name}",center,size,"Tile",collide=False)
    # The iron leaves meet at x=0; their arched top follows the tiled reveal.
    for side in (-1,1):
        verts=[]
        for z in (-.58,-.2):
            for x,y in ((0,0),(5*side,0),(5*side,15),(4.62*side,16.9),
                        (3.54*side,18.54),(1.91*side,19.62),(0,20)):
                verts.append((x,y,z))
        faces=[(0,1,2,3,4,5,6),(13,12,11,10,9,8,7)]
        faces += [(i,(i+1)%7,(i+1)%7+7,i+7) for i in range(7)]
        m.raw(verts,faces,"Iron")
        m.cylinder((2.5*side, 9, -.63), .12, .17, "Steel", 12, axis="Z")
    door_arch(m)
    for side in (-1,1):
        # The pivot sits on the wall face (world phase 0.25 through the wall, LATTICE_SPEC 2.4), so the box UV's
        # through-wall lines are shifted a quarter tile: the jamb sides' vertical grout then meets the hall floor's
        # (world phase 0) in the T-corner they stand in (step K; Blender co[1] = -z).
        m.box((side*(5+ARRIVAL_HALF)/2,7.5,-.35),(ARRIVAL_HALF-5,15,1),"Tile",bevel=.08,
              uv=lambda co,n:kit.box_uv((co[0],co[1]+.25*kit.S,co[2]),n))
        # Room-side fill between the arch's outer edge and the Upper wall (y 20), out to the side walls (x 5).
        x0=ARRIVAL_HALF*math.sqrt(1-(5/ARRIVAL_RISE)**2)
        verts=[]
        for i in range(7):
            x=x0+(5-x0)*i/6
            y=15+ARRIVAL_RISE*math.sqrt(max(0,1-(x/ARRIVAL_HALF)**2))
            verts.extend(((side*x,y,-.31),(side*x,20,-.31)))
        m.raw(verts,[(2*i,2*i+1,2*i+3,2*i+2) for i in range(6)],"Tile",facing=lambda p:(0,0,-1))   # room side
    m.box((0,3,-.78),(.08,6,.1),"Iron",bevel=.01)
    m.cylinder((0,22.7,-.62),.78,.3,"Iron",20,axis="Z")
    m.cylinder((0,22.7,-.84),.42,.04,"LightWarm",20,axis="Z")
    m.marker("ArrivalLampGlow",(0,22.7,-.9),ClassName="PointLight",
             Brightness=.4,Range=12,Shadows=False)
    m.marker("StoryGate",(0,0,-.7),Closed=True)
    done(m,1500)


def build():
    pump()
    platform()
    spiral()
    collar()
    mouth_trim()
    bore_template()
    tube_visual()
    arrival()
    return BUDGETS


# ---- lattice validation (LATTICE_SPEC I3) ------------------------------------------------------------------------
# Run after export on what ships (manifest + chunk files). Each check returns a list of problems; validate() requires
# every list to be empty AND every planted negative to produce one (a check that cannot fail proves nothing).

LATTICE_COMPONENTS = ("ExitPlatform", "ExitSpiral", "ExitCollar", "ExitMouthTrim", "PumpStation")
# (part, axis, 0 = min / 1 = max) -> why that edge may stay off the lattice. BRIDGE_FRAME turns both Parts so that NO
# face anchors its grid there (check_part_faces proves it), so every grout line they draw is on the lattice.
OFF_LATTICE_EDGES = {
    ("Level 2 Exit Spiral Bridge", 0, 0): "west end = the stair's TH1 line, x = SC.x (builder stair centre E-81.6)",
    ("Level 2 Exit Spiral Bridge North Guard", 0, 0): "west end = the stair's TH1 line, x = SC.x",
}
PHASE_TOL = 2e-3            # tile units: 0.001 stud at 0.5
HALL_WALL_GAP = (18.0, 73.0, 90.0)   # LATTICE_SPEC 6 HallWallGap (width, bottom, top) in the collar frame


def lattice_off(v):
    """Studs from the nearest lattice line (multiples of TILE in a frame whose origin is on the lattice)."""
    r = np.asarray(v, float) / TILE
    return np.abs(r - np.round(r)) * TILE


def record_bounds(rec):
    cf, half = rec["cf"], np.asarray(rec["size"], float) / 2
    if len(cf) == 4:
        c, R = np.asarray(cf[:3], float), np.eye(3)
        if round(cf[3] / 90) % 2:
            half = half[[2, 1, 0]]
    else:
        c, R = np.asarray(cf[:3], float), np.asarray(cf[3:], float).reshape(3, 3)
    ext = np.abs(R) @ half
    return c - ext, c + ext


def check_part_lattice(components):
    """Every visible tiled Part record of the exit components: all six bounds on the lattice of its frame (all exit
    frames sit on the world lattice), except OFF_LATTICE_EDGES, which must be exactly where they are declared."""
    bad = []
    for comp in LATTICE_COMPONENTS:
        for rec in components[comp]["parts"]:
            if rec["material"] not in ("Tile", "Aqua"):
                continue
            lo, hi = record_bounds(rec)
            for side, v in enumerate((lo, hi)):
                for axis in range(3):
                    if (rec["name"], axis, side) in OFF_LATTICE_EDGES:
                        if abs(v[axis] - SC[0]) > 1e-9:
                            bad.append(f"{rec['name']}: declared edge moved to {v[axis]:.4f}")
                        continue
                    if lattice_off(v[axis]) > 1e-6:
                        bad.append(f"{comp}/{rec['name']}: {'xyz'[axis]} {'min' if side == 0 else 'max'} "
                                   f"{v[axis]:.4f} off the {TILE} lattice")
    return bad


def record_part(rec):
    """A Part record as lattice_audit's {cframe (12), size}; a 4-number cf is CFrame.new(x,y,z)*CFrame.Angles(0,yaw,0)."""
    cf = rec["cf"]
    if len(cf) == 4:
        t = math.radians(cf[3])
        c, s_ = math.cos(t), math.sin(t)
        cf = [*cf[:3], c, 0, s_, 0, 1, 0, -s_, 0, c]
    return {"cframe": [float(v) for v in cf], "size": rec["size"]}


def check_part_faces(components):
    """The anchor-corner rule (TILE_PHASE.md, lattice_audit.ANCHOR): every face of every tiled exit/pump Part draws its
    grout lines on the frame lattice. A Part whose six bounds are on the lattice passes by construction; this is what
    proves that no face anchors at a declared OFF_LATTICE_EDGES end."""
    import lattice_audit as la
    bad = []
    for comp in LATTICE_COMPONENTS:
        for rec in components[comp]["parts"]:
            if rec["material"] not in ("Tile", "Aqua"):
                continue
            for f in la.part_faces(record_part(rec), TILE):
                for G, c in f["fams"]:
                    if abs(c - round(c)) * TILE > 1e-6:
                        a, sg = f["face"]
                        bad.append(f"{comp}/{rec['name']}: object {'+' if sg > 0 else '-'}{'XYZ'[a]} face grid "
                                   f"{abs(c - round(c)) * TILE:.4f} off the lattice along {np.round(G * TILE, 3)}")
    return bad


def component_mesh(chunks, comp, shift=(0, 0, 0)):
    """Tile triangles (n,3,3) in the component frame (+ shift into the collar frame) and their uv (n,3,2)."""
    chunk = chunks[(comp, "Tile")]
    pos = chunk["positions"].astype(float) + np.asarray(chunk["record"]["center"], float) + np.asarray(shift, float)
    return pos[chunk["indices"][:, :, 0]], chunk["uv"][chunk["indices"][:, :, 2]].astype(float)


def tri_normals(T):
    n = np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0])
    return n / np.maximum(np.linalg.norm(n, axis=1), 1e-12)[:, None]


def tri_area(T):
    return .5 * np.linalg.norm(np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0]), axis=1)


def planar_lattice_problems(T, UV, label, axes=(2, 1)):
    """Each triangle's two grout families run along the frame axes `axes` at pitch TILE with lines on the lattice."""
    import lattice_audit as la
    G, C, valid = la.tri_families(T, UV)
    bad = []
    for i in range(len(T)):
        for f in (0, 1):
            g = G[i, f]
            axis = int(np.argmax(np.abs(g)))
            if not valid[i, f] or axis not in axes or abs(abs(g[axis]) * TILE - 1) > 1e-3 \
                    or np.linalg.norm(np.delete(g, axis)) * TILE > 1e-3:
                bad.append(f"{label}: triangle {i} family {f} is not a {TILE} grid along the frame axes ({g})")
                continue
            # phase at the triangle's own corners (8 u in tiles minus the lattice coordinate): a gradient taken from a
            # sliver triangle would amplify the export's 1e-5 uv rounding if extrapolated to the frame origin
            d = 8 * UV[i, :, f] - np.sign(g[axis]) * T[i, :, axis] / TILE
            d = d - np.round(d)
            if np.abs(d).max() > PHASE_TOL:
                bad.append(f"{label}: triangle {i} family {f} lines off the lattice by {np.abs(d).max() * TILE:.4f}")
    return bad


def check_proud_plane(chunks):
    """The proud plane x = E-2.0 (collar frame), facing the hall: the ExitCollar face and the tube's start cap tile it
    exactly once over z +-9.5, y 72.5 .. 90.5 minus the open bore, each with a planar grid on the world lattice."""
    bad, area = [], 0.0
    for comp, shift in (("ExitCollar", (0, 0, 0)), ("ExitTubeVisual", (ANCHOR_X, AXIS_Y, 0))):
        T, UV = component_mesh(chunks, comp, shift)
        sel = np.all(np.abs(T[:, :, 0] - COLLAR_FACE) < 1e-4, axis=1) & (tri_normals(T)[:, 0] < -.999)
        if not sel.any():
            bad.append(f"{comp}: nothing on the proud plane")
            continue
        bad += planar_lattice_problems(T[sel], UV[sel], comp)
        area += tri_area(T[sel]).sum()
    want = 2 * FRAME_Z * (FRAME_TOP - FRAME_BOTTOM) - SIDES * APO_IN ** 2 * math.tan(HALF)
    if abs(area - want) > 1e-3:
        bad.append(f"proud plane covered {area:.4f} != {want:.4f} (frame minus the open bore): a gap or an overlap")
    return bad


def check_collar_frame(chunks, components):
    """The ExitCollar frame itself (LATTICE_SPEC 6 'exit proud plane'): its attributes and its mesh outline are the
    lattice numbers FaceX / +-FrameZ / FrameBottomY / FrameTopY, they cover the builder's HallWallGap, the back
    (BackX) is behind the wall's outer face, and EVERY flat face of the frame (face, top, bottom, sides, back; not the
    bore wall, which the tube's outer staves fill) draws a planar grid on the lattice along its own two axes."""
    bad = []
    a = components["ExitCollar"]["attrs"]
    face, back, z, lo, hi = a["FaceX"], a["BackX"], a["FrameZ"], a["FrameBottomY"], a["FrameTopY"]
    for k, v in (("FaceX", face), ("FrameZ", z), ("FrameBottomY", lo), ("FrameTopY", hi)):
        if lattice_off(v) > 1e-9:
            bad.append(f"ExitCollar {k} {v} off the {TILE} lattice")
    width, gap_lo, gap_hi = HALL_WALL_GAP
    if not (z >= width / 2 and lo <= gap_lo and hi >= gap_hi and back >= 0):
        bad.append(f"ExitCollar frame z +-{z}, y {lo}..{hi}, back {back} does not cover HallWallGap {HALL_WALL_GAP}")
    T, UV = component_mesh(chunks, "ExitCollar")
    want = np.array(((face, lo, -z), (back, hi, z)))
    got = np.array((T.reshape(-1, 3).min(0), T.reshape(-1, 3).max(0)))
    if np.abs(got - want).max() > 1e-4:
        bad.append(f"ExitCollar mesh spans {np.round(got, 4).tolist()} != its frame {want.tolist()}")
    hole = np.all(np.hypot(T[:, :, 2], T[:, :, 1] - AXIS_Y) < RHO_OUT + 1e-4, axis=1)
    n = tri_normals(T)
    for k in range(3):
        sel = ~hole & (np.abs(n[:, k]) > .9999)
        bad += planar_lattice_problems(T[sel], UV[sel], f"ExitCollar {'xyz'[k]} face", tuple(i for i in range(3) if i != k))
    if (~hole & (np.abs(n).max(1) <= .9999)).any():
        bad.append("ExitCollar: a frame face that is not axis-aligned")
    return bad


def point_in_tri(p, t, tol=1e-4):
    """p (3,) within tol of triangle t (3,3), in its plane."""
    e1, e2 = t[1] - t[0], t[2] - t[0]
    n = np.cross(e1, e2)
    n /= np.linalg.norm(n)
    d = p - t[0]
    if abs(d @ n) > tol:
        return False
    M = np.array(((e1 @ e1, e1 @ e2), (e1 @ e2, e2 @ e2)))
    u, v = np.linalg.solve(M, (d @ e1, d @ e2))
    scale = max(np.linalg.norm(e1), np.linalg.norm(e2))
    return u >= -tol / scale and v >= -tol / scale and u + v <= 1 + tol / scale


def seam_problems(A, B, on_seam, label):
    """A, B = (T, UV) in one frame. Every A triangle with an edge on the seam (both ends pass on_seam) is matched to the
    coplanar, same-facing B triangles holding those ends: both grout families must share direction, pitch (1%) and
    phase at the ends (PHASE_TOL), the way lattice_audit judges an edge seam. Returns (problems, matched edges)."""
    import lattice_audit as la
    (TA, UA), (TB, UB) = A, B
    GA, CA, VA = la.tri_families(TA, UA)
    GB, CB, VB = la.tri_families(TB, UB)
    nA, nB = tri_normals(TA), tri_normals(TB)
    keepB = np.nonzero(np.array([on_seam(t).any() for t in TB]))[0]
    bad, matched = [], 0
    for i in range(len(TA)):
        ends = TA[i][on_seam(TA[i])]
        if len(ends) < 2:
            continue
        hosts = [j for j in keepB if nA[i] @ nB[j] > .9999 and all(point_in_tri(p, TB[j]) for p in ends)]
        for j in hosts:
            matched += 1
            for f in (0, 1):
                if not VA[i, f]:
                    continue
                cos = [abs(GA[i, f] @ GB[j, g]) / (np.linalg.norm(GA[i, f]) * np.linalg.norm(GB[j, g]))
                       if VB[j, g] else 0 for g in (0, 1)]
                g = int(np.argmax(cos))
                if cos[g] < .9999:
                    bad.append(f"{label}: A{i}/B{j} family {f} turned against its neighbour")
                    continue
                ratio = np.linalg.norm(GA[i, f]) / np.linalg.norm(GB[j, g])
                if abs(ratio - 1) > .01:
                    bad.append(f"{label}: A{i}/B{j} family {f} pitch differs by {abs(ratio - 1):.2%}")
                s = np.sign(GA[i, f] @ GB[j, g])
                for p in ends:
                    d = (GA[i, f] @ p + CA[i, f]) - s * (GB[j, g] @ p + CB[j, g])
                    if abs(d - round(d)) > PHASE_TOL:
                        bad.append(f"{label}: A{i}/B{j} family {f} steps {abs(d - round(d)) * TILE:.4f} at {np.round(p, 3)}")
    return bad, matched


def check_bore_seam(chunks):
    """The bore circle on the collar plane: the mouth trim's bore faces continue the tube's inner staves (same whole
    tiles round from the floor centre, v continuous)."""
    trim = component_mesh(chunks, "ExitMouthTrim")
    tube = component_mesh(chunks, "ExitTubeVisual", (ANCHOR_X, AXIS_Y, 0))

    def on_ring(t):
        return (np.abs(t[:, 0] - COLLAR_FACE) < 1e-4) & (np.hypot(t[:, 2], t[:, 1] - AXIS_Y) < RHO_IN + 1e-4)
    bad, matched = seam_problems(trim, tube, on_ring, "mouth trim | tube")
    if matched < 3 * (SIDES - 1):
        bad.append(f"mouth trim | tube: only {matched} bore edges matched (want {3 * (SIDES - 1)})")
    return bad


def check_tube_joints(chunks, manifest):
    """Every tube chunk joint whose two rings coincide continues the grid; joints whose rings do not coincide (helix
    twist) share no edge. The first joint must be a coincident one (LATTICE_SPEC I3.3)."""
    bad, names, coincident = [], sorted(c for c in manifest["components"] if c.startswith("ExitTubeVisual")), []
    rec = json.loads(SLIDES.read_text(encoding="utf-8"))["slides"]["ExitFlume_Tube"]
    P = np.array(rec["pathPoints"], float)
    for a, b in zip(names, names[1:]):
        joint = manifest["components"][b]["attrs"]["PathStartIndex"]
        look = (P[joint] - P[joint - 1]) / np.linalg.norm(P[joint] - P[joint - 1])
        nxt = (P[joint + 1] - P[joint]) / np.linalg.norm(P[joint + 1] - P[joint])
        plane = (look + nxt) / np.linalg.norm(look + nxt)

        def on_joint(t):
            return np.abs((t - P[joint]) @ plane) < 1e-3
        problems, matched = seam_problems(component_mesh(chunks, a), component_mesh(chunks, b), on_joint, f"{a} | {b}")
        bad += problems
        if matched:
            coincident.append(joint)
    first = manifest["components"][names[1]]["attrs"]["PathStartIndex"]
    if first not in coincident:
        bad.append(f"tube joint {first}: the first chunk joint shares no edge (its rings do not coincide)")
    return bad, coincident


def check_pool_floor(chunks, extra=None):
    """No up-facing ExitSpiral / ExitPlatform face lies within 0.05 of the exit pool floor for any legal DeepEnd
    (POOL_WIDTH / POOL_DEEP): that inlay z-fights (C16 'ExitSpiral | Hall Water Floor')."""
    bad = []
    for comp in ("ExitSpiral", "ExitPlatform"):
        T, _ = component_mesh(chunks, comp)
        if extra is not None and comp == "ExitSpiral":
            T = np.concatenate([T, extra])
        up = tri_normals(T)[:, 1] > .94
        T = T[up]
        for d in np.linspace(*POOL_DEEP, 81):
            near = np.all(np.abs(T[:, :, 1] - pool_floor(T[:, :, 0], d)) < .05, axis=1)
            if near.any():
                bad.append(f"{comp}: {int(near.sum())} up-facing triangles within 0.05 of the pool floor "
                           f"(DeepEnd {d:.3f}) at {np.round(T[near][0].mean(0), 2)}")
                break
    return bad


def validate(out=OUT):
    """LATTICE_SPEC I3 checks on the export in `out`, each with a planted negative that must fail."""
    import copy
    from render_world import load_kit_chunks
    path = Path(out) / "manifest.json"
    raw = path.read_bytes()
    manifest = json.loads(raw)
    chunks = load_kit_chunks({"kitExports": {"C": {"path": str(path), "sha256": hashlib.sha256(raw).hexdigest()}}})
    comps = manifest["components"]
    assert (bore_tiles(APO_IN), bore_tiles(APO_OUT)) == (92, 99), (bore_tiles(APO_IN), bore_tiles(APO_OUT))
    results = {}
    results["parts"] = check_part_lattice(comps)
    results["part faces"] = check_part_faces(comps)
    results["collar frame"] = check_collar_frame(chunks, comps)
    results["proud plane"] = check_proud_plane(chunks)
    results["bore seam"] = check_bore_seam(chunks)
    results["tube joints"], coincident = check_tube_joints(chunks, manifest)
    results["pool floor"] = check_pool_floor(chunks)
    failed = {k: v for k, v in results.items() if v}
    assert not failed, "PR_C_LATTICE FAIL " + json.dumps({k: v[:6] for k, v in failed.items()}, indent=1)
    # Planted negatives.
    negatives = {}
    shifted = copy.deepcopy(comps)
    rec = next(r for r in shifted["ExitSpiral"]["parts"] if r["name"] == "Level 2 Exit Spiral Bridge")
    rec["cf"][2] += TILE / 2
    negatives["bridge moved half a tile"] = check_part_lattice(shifted)
    upright = copy.deepcopy(comps)        # the bridge as it was: axis-aligned, its +Z side anchored at SC.x
    rec = next(r for r in upright["ExitSpiral"]["parts"] if r["name"] == "Level 2 Exit Spiral Bridge")
    rec["cf"], rec["size"] = [*rec["cf"][:3], 0], [rec["size"][1], rec["size"][0], rec["size"][2]]
    negatives["bridge face anchored at SC.x"] = check_part_faces(upright)
    plinth = copy.deepcopy(comps)
    next(r for r in plinth["PumpStation"]["parts"] if r["name"] == "Level 2 Pump Plinth")["size"] = [9.2, .96, 7.2]
    negatives["pump plinth 9.2 x 0.96 x 7.2"] = check_part_lattice(plinth)
    moved = dict(chunks)
    for comp, du in (("ExitCollar", 1 / 16), ("ExitMouthTrim", 1 / 16), ("ExitTubeVisual_02", 0)):
        moved[(comp, "Tile")] = dict(chunks[(comp, "Tile")], uv=chunks[(comp, "Tile")]["uv"] + (du, 1 / 16 - du))
    negatives["collar UV half a tile off"] = check_proud_plane(moved)
    negatives["trim UV half a tile off"] = check_bore_seam(moved)
    negatives["tube chunk 2 v half a tile off"] = check_tube_joints(moved, manifest)[0]
    negatives["collar side faces half a tile off"] = [p for p in check_collar_frame(moved, comps) if " x face" not in p]
    wide = dict(chunks)
    c = chunks[("ExitCollar", "Tile")]
    pos = c["positions"].astype(float)
    pos[:, 2] += np.where(pos[:, 2] + c["record"]["center"][2] > FRAME_Z - 1e-4, TILE / 2, 0)
    wide[("ExitCollar", "Tile")] = dict(c, positions=pos)
    negatives["collar frame 0.25 wider"] = check_collar_frame(wide, comps)
    low = copy.deepcopy(comps)
    low["ExitCollar"]["attrs"]["FrameBottomY"] = 73.5
    negatives["collar frame above the wall gap"] = check_collar_frame(chunks, low)
    a, b = TH0 + 4.8 * DSTEP, TH0 + 5.6 * DSTEP
    raised = np.array([[polar(r, t, -1.5) for r, t in ((6, a), (14, a), (14, b))],
                       [polar(r, t, -1.5) for r, t in ((6, a), (14, b), (6, b))]], float)
    raised = np.concatenate([raised, raised[:, ::-1]])         # both windings: one of them faces up
    negatives["unburied tread at -1.5"] = check_pool_floor(chunks, extra=raised)
    survived = [k for k, v in negatives.items() if not v]
    assert not survived, f"PR_C_LATTICE planted negatives not caught: {survived}"
    for k, v in negatives.items():
        print(f"PR_C_LATTICE negative '{k}' caught: {v[0]}", flush=True)
    print(f"PR_C_LATTICE PASS: tile {TILE}; tiled exit/pump Parts on the lattice ({len(OFF_LATTICE_EDGES)} declared edges, never anchored);"
          f" collar frame z +-{FRAME_Z} y {FRAME_BOTTOM}..{FRAME_TOP} on the lattice over HallWallGap, every frame face planar;"
          f" proud plane tiled once, planar on the lattice; bore {bore_tiles(APO_IN)}/{bore_tiles(APO_OUT)} tiles round,"
          f" trim = tube; tube joints continuous at {coincident}; no face within 0.05 of the pool floor; "
          f"{len(negatives)} planted negatives caught", flush=True)


# ---- review renders (backface culling ON so wrong-facing faces show) ---------------------------------------------

def review_box(col,name,center,size,mat):
    m=kit.Mesh(name)
    m.box(center,size,mat,bevel=0)
    obj=bpy.data.objects.new(name,m.finish(register=False))
    col.objects.link(obj)
    return obj


def light(col,position,target,power=9000,size=10,color=(1,.86,.65),kind="AREA"):
    dat=bpy.data.lights.new("Warm light",kind)
    dat.energy=power
    if kind=="AREA":
        dat.shape="DISK"
        dat.size=size
    dat.color=color
    obj=bpy.data.objects.new("Warm light",dat)
    col.objects.link(obj)
    obj.location=kit.to_blender(position)
    obj.rotation_euler=(kit.to_blender(target)-obj.location).to_track_quat("-Z","Y").to_euler()


def water(col,size=(100,100),center=(0,.1,0)):
    obj=review_box(col,"Review water",center,(size[0],.025,size[1]),"Aqua")
    mat=bpy.data.materials.new("Review green turquoise water")
    mat.use_nodes=True
    p=mat.node_tree.nodes.get("Principled BSDF")
    p.inputs["Base Color"].default_value=(.055,.24,.17,1)
    p.inputs["Roughness"].default_value=.1
    p.inputs["Alpha"].default_value=.42
    if hasattr(mat,"surface_render_method"):
        mat.surface_render_method="BLENDED"
    obj.data.materials.clear()
    obj.data.materials.append(mat)


def collection(name):
    col=bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(col)
    return col


def render(col,name,eye,target,ortho=None,lens=23):
    scene=bpy.context.scene
    for other in scene.collection.children:
        other.hide_render=other!=col
    data=bpy.data.cameras.new("Review camera")
    cam=bpy.data.objects.new("Review camera",data)
    col.objects.link(cam)
    cam.location=kit.to_blender(eye)
    cam.rotation_euler=(kit.to_blender(target)-cam.location).to_track_quat("-Z","Y").to_euler()
    data.lens=lens
    data.clip_start=.02
    data.clip_end=2500
    if ortho:
        data.type="ORTHO"
        data.ortho_scale=ortho*kit.S
    scene.camera=cam
    scene.render.filepath=str(REVIEW/(name+".png"))
    for mat in bpy.data.materials:
        mat.use_backface_culling=True     # every image, every material made so far: wrong-facing faces must show
    bpy.ops.render.render(write_still=True)
    col.objects.unlink(cam)
    bpy.data.objects.remove(cam)
    return name


def exit_hall_scene(col):
    """Platform frame = world origin: E = 36, F = 0, deckZ = -10, MinZ = -52."""
    for name in ("ExitPlatform","ExitSpiral"):
        kit.place(col,name)
    for name in ("ExitCollar","ExitMouthTrim"):
        kit.place(col,name,(E_X,0,DECK_Z))
    for name in BUDGETS:
        if name.startswith("ExitTubeVisual"):
            kit.place(col,name,(E_X+ANCHOR_X,AXIS_Y,DECK_Z))
    review_box(col,"Hall pool floor",(-60,-1.81,40),(200,1,184),"Aqua")
    # East wall E-1.75..E with the builder's HallWallGap (deckZ +-9, F+73 .. F+90); north wall at MinZ.
    gz0,gz1=DECK_Z-9,DECK_Z+9
    gy0,gy1=73,90
    wx=E_X-.875
    review_box(col,"East wall S",(wx,47,(gz1+132)/2),(1.75,98,132-gz1),"Tile")
    review_box(col,"East wall N",(wx,47,(gz0-52)/2),(1.75,98,gz0+52),"Tile")
    review_box(col,"East wall low",(wx,(gy0-2)/2,DECK_Z),(1.75,gy0+2,gz1-gz0),"Tile")
    review_box(col,"East wall high",(wx,(gy1+96)/2,DECK_Z),(1.75,96-gy1,gz1-gz0),"Tile")
    review_box(col,"North wall",(-60,47,-52.875),(200,98,1.75),"Tile")
    review_box(col,"Ceiling",(-60,96.5,40),(200,1,184),"Tile")
    water(col,(200,184),(-60,-.1,40))


def reviews():
    REVIEW.mkdir(parents=True,exist_ok=True)
    scene=bpy.context.scene
    scene.render.engine="BLENDER_EEVEE"
    scene.render.resolution_x=1100
    scene.render.resolution_y=740
    scene.render.resolution_percentage=100
    scene.render.image_settings.file_format="PNG"
    scene.world=bpy.data.worlds.new("Green ambient")
    scene.world.use_nodes=True
    bg=scene.world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value=(.20,.28,.21,1)
    bg.inputs["Strength"].default_value=.8
    scene.view_settings.view_transform="AgX"
    images=[]

    col=collection("Pump review")
    for name in ("PumpStation","PumpLever","PumpNeedle","PumpLamp"):
        kit.place(col,name)
    review_box(col,"Pool floor",(0,-.55,0),(36,1,36),"Aqua")
    review_box(col,"Left wall",(-18,12,0),(1,25,36),"Tile")
    review_box(col,"Back wall",(0,12,-18),(36,25,1),"Tile")
    water(col,(36,36))
    light(col,(3,22,8),(0,3,0),14000,6)
    images.append(render(col,"pump_station",(8,7,14),(0,3,0)))

    col=collection("Exit hall review")
    exit_hall_scene(col)
    light(col,(0,92,0),(0,40,0),60000,40)
    light(col,(-46,92,7),(-46,0,7),30000,24)
    light(col,(-10,88,30),(30,80,-10),20000,10)
    light(col,(-46,30,40),(-46,30,7),15000,20)
    images.append(render(col,"exit_hall",(-110,60,90),(-10,45,-5)))
    images.append(render(col,"exit_stair_from_below",(-24,1.5,30),(-45.6,40,7)))
    images.append(render(col,"exit_stair_top_down_core",(-43.6,92,5),(-45.6,0,7),lens=14))
    images.append(render(col,"exit_stair_entry",(-30.6,4,-19),polar(9,TH0+math.radians(40),0.5)))
    th=TH0+math.radians(700)
    eye=polar(9.5,th,ramp_y(th)+5.5); tgt=polar(15.2,th+math.radians(40),ramp_y(th+math.radians(40))+2)
    images.append(render(col,"exit_railing_close",eye,tgt))
    th=TH0+math.radians(1050)
    images.append(render(col,"exit_stair_top_landing",polar(10,th-math.radians(30),ramp_y(th)+4.5),(-30,74.5,-3)))
    images.append(render(col,"exit_deck_edge",(-6,77,34),(10,74,18)))
    images.append(render(col,"exit_deck_from_hall",(-20,62,60),(5,74,10)))
    images.append(render(col,"exit_collar_mouth",(-8,80,12),(E_X,AXIS_Y,DECK_Z)))
    images.append(render(col,"exit_collar_under_deck",(27,70.5,-3),(E_X-2,72.97,DECK_Z),lens=20))
    images.append(render(col,"exit_collar_trim_corner",(27,87,-1),(E_X-2,89.6,DECK_Z-FRAME_Z),lens=24))
    trim=[o for o in col.objects if o.get("l2k_component")=="ExitMouthTrim"]
    green=bpy.data.materials.new("Review open mouth green")
    green.use_nodes=True
    p=green.node_tree.nodes.get("Principled BSDF")
    p.inputs["Base Color"].default_value=(.46,.70,.55,1)
    p.inputs["Alpha"].default_value=.65
    if hasattr(green,"surface_render_method"):
        green.surface_render_method="BLENDED"
    saved=[o.data.materials[0] for o in trim]
    for o in trim:
        o.data=o.data.copy(); o.data.materials[0]=green
    images.append(render(col,"exit_collar_mouth_open",(-8,80,12),(E_X,AXIS_Y,DECK_Z)))
    for o,mat in zip(trim,saved):
        o.data.materials[0]=mat
    rec=json.loads(SLIDES.read_text(encoding="utf-8"))["slides"]["ExitFlume_Tube"]
    base=np.array((E_X+ANCHOR_X,AXIS_Y,DECK_Z))
    pts=[base+np.array(p) for p in rec["pathPoints"]]
    light(col,tuple(pts[0]+(4,2,0)),tuple(pts[1]),400,kind="POINT")
    light(col,tuple(pts[121]+(0,2,0)),tuple(pts[124]),1500,kind="POINT")
    images.append(render(col,"exit_tube_inside_lead",tuple(pts[0]+(-6,1.5,0)),tuple(pts[1]),lens=18))
    images.append(render(col,"exit_tube_inside_helix",tuple(pts[120]+(0,1.0,0)),tuple(pts[126]),lens=16))
    col2=collection("Exit tube review")
    for name in BUDGETS:
        if name.startswith("ExitTubeVisual"):
            kit.place(col2,name)
    light(col2,(300,130,200),(270,-100,0),18000,50)
    images.append(render(col2,"exit_tube_outside",(600,260,850),(260,-155,0),ortho=1450))

    col=collection("Arrival review")
    kit.place(col,"ArrivalDoor")
    review_box(col,"Arrival floor",(0,-.65,-12),(32,1.3,32),"Tile")
    light(col,(-8,21,-15),(0,13,0),2800,7)
    images.append(render(col,"arrival_door",(9,12,-32),(0,13,0)))
    return images


if __name__=="__main__":
    bpy.ops.wm.read_factory_settings(use_empty=True)
    build()
    kit.EXPORT_DIR=OUT
    manifest=kit.export()
    for old in (OUT/"chunks").glob("c*.b64"):
        if int(old.stem[1:])>=len(manifest["chunks"]):
            old.unlink()
    assert set(BUDGETS)==set(manifest["components"])
    validate()
    images=[] if "--no-review" in sys.argv else reviews()
    (OUT/"review.json").write_text(json.dumps({
        "componentTriangles":BUDGETS,
        "images":[str(REVIEW/(x+".png")) for x in images],
        "exitCollision":"SlideCol_Bore16 template x 271 BoreSegment markers, generated from the reviewed pathPoints",
        "runtimeGameplayCheck":"unverified offline visual kit"},indent=2),encoding="utf-8")
    print("PR_C_OK "+json.dumps(BUDGETS),flush=True)
