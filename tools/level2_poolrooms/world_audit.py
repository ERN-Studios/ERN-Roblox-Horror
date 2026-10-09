"""Visual/geometry audit of dumped Poolrooms worlds (headless Blender for BVH ray casts).

    D:/Blender/blender.exe -b --factory-startup --python-exit-code 1 \
        -P tools/level2_poolrooms/world_audit.py -- [dump.json ...] [--out DIR] [--only 1,4,9] [--crops N]

Default dumps: G:/Blender/Level2_Poolrooms/worlds/world_{837834,1,101}.json. Exit code 2 when any check fails.
Report per dump: <out>/world_audit_<seed>.json (every check: passed, count, examples with world position and the
offending part/component). Everything is found by name pattern / fixtureComponent / manifest attrs, never by a
hard-coded seed position, so it keeps working while the kit and builder change.

 1 leaks      rays from interior samples that reach the sky/void. Only rays leaving upward through a ceiling
              opening's hole are intended: inside HoleRadius at both ends of the straight throat (C+1 and
              C+ShaftDepth-1; the rim flares to r+0.55 at C). Sample points no player can see from (not reachable
              and not open air straight above reachable space, e.g. behind a chamber's rounded corner) are skipped.
 2 ceiling    nothing visible hangs below the ceiling plane C = FloorY + CeilingClass except vault bays carried
              by piers at all four corners and LightRound trim <= 0.6 deep; at every cut in the ceiling slab the
              opening's plate has vertices on C whose outer edge equals the cut within 0.02, no vertex of the
              opening (or any other part) sits inside the cut prism below C, and rays straight up through the
              cut escape only inside the hole circle (no square gap to the sky).
 3 jumpreach  no standable CanCollide top in (C-14, C-3] within cut half + 10 of an opening, and a colliding Sky
              Cap covers the whole cut between C and C+3.
 4 floating   floor-standing visible solids: every bottom vertex rests on (or is buried in) the surface below;
              a gap above the floor/basin/deck under it > 0.05 fails.
 5 water      every visible basin floor (floor top below its space's FloorY) of a hall, chamber or channel lies
              under water: inside a terrain water region whose 4-stud voxel column is solid at the surface,
              also 1 stud to each side unless that probe is inside a wall/step.
 6 coves      straight coves and corner pieces are concave fillets (radius from attrs) tangent to the wall and
              floor/ceiling, their shading normals face the room, and no straight cove ends free (another cove,
              a corner piece, a CoveBaseStop or a swerve skin's own cove must continue it). A straight run is
              judged against its own wall plane (its pivot), so runs on a swerve hall's plateau are measured
              against the plateau face, not the hall rectangle.
 7 intersect  visible solids interpenetrating closed solids (walls, collars, doors, decks, other props) by more
              than 0.1 (cove families into the wall/floor shell up to 0.75; floor slabs are exempt targets), counted
              only where the intersection line is a visible crease from reachable space for > 0.25 stud (both
              surfaces seen 0.08 off the line; tangent junctions, square junctions with a wall/floor/ceiling/deck/
              chamber shell, a pressure door's square junctions with the round tunnel of its OWN corridor, and parts
              of one pump station or pressure door are not creases). Corridor tubes are not support for anything
              else: a part pushed squarely into a tunnel wall is judged.
 8 zfight     coplanar overlapping faces of different objects within 0.005, counted when > 0.25 stud^2 of the
              overlap is seen from reachable space on a side where both faces render; closed solids touching face
              to face (butt joints, a decal on its floor) are contact patches, not z-fighting. Coplanar means the
              two planes are within 0.005 of each other over their overlap polygon (not that their offsets from the
              world origin agree: a slightly tilted basin floor extrapolated to the origin can match a threshold's).
              Sight for 1/7/8: rays from the point must enter a reachable body voxel (flood from ElevatorSpawn,
              2..7 voxels above the feet) whose centre is in clear line of sight (class Sight).
 9 stretch    tiled MeshParts whose size / exported chunk size is outside [0.875, 1.125] on any axis.
10 colour     every tiled surface is PR Tile / PR Tile Aqua, SmoothPlastic, Color (241,237,220), Reflectance .06.
11 decor      wall decor (WallVoid, SunSlit, Porthole, attr WallDecor) protrudes <= 0.05 from the wall face and
              its dark/glow face is not buried inside an opaque part.
12 lattice    tile-grid seams: lattice_audit.audit_parts on this world, same thresholds (a seam whose grout lines
              step by > 0.01 and that is seen for >= 0.25 stud), tile pitch from the dump's kit manifest, Part grids
              per the measured face-anchor rule. Seam kinds: edge, inlay and corner (inside/outside folds and
              T-corners: reveals, sills, plinths, a box on a floor). Rows: one per category (familyA | familyB), worst
              offset, exposed studs, owners, kinds; curved cuts are counted (stats), not judged. See lattice_audit.
"""
from __future__ import annotations

import argparse
from collections import defaultdict
import json
import math
from pathlib import Path
import re
import sys
import time

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree
import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import collision_audit as ca  # noqa: E402  (numpy parts only; scipy is imported lazily there)
import world_check as wc  # noqa: E402
from render_world import fixture_chunk, load_kit_chunks, mesh_triangles_world  # noqa: E402

DEFAULT_OUT = ca.DEFAULT_OUT
TILE_RGB = np.array((241, 237, 220)) / 255
TILE_VARIANTS = {"PR Tile", "PR Tile Aqua"}
TILE_CHUNK_MATERIALS = {"Tile", "Aqua", "TileShade", "Worn"}
TILED_PART_NAME = re.compile(r"^Level 2 (Hall (Wall|Floor|Water Floor|Sill|Lintel)|Overhead Tile|"
                             r"Corridor (Wall|Floor|Facet)|Passage (Wall|Floor|Facet)|Exit Lead Tile|"
                             r"Arrival Wall|Room (Wall|Floor))")
STRETCH = (.875, 1.125)     # inclusive: the builder's fit() lays runs at exactly 1.125 (total*1.125, 1e-9 slack)
STRETCH_EPS = 1e-6          # rounding: a CoveTop4 fitted at exactly 1.125 is 4.500000000000057 studs (seed 35746866)
SHELL = re.compile(r"^Level 2 (Hall (Wall|Sill|Lintel|Floor|Water Floor|Roof Collider)|Overhead Tile|"
                   r"Corridor (Roof|Ceiling)|Passage Roof|Arrival Wall|Recovery Chamber|Sky Cap)")
FLOOR = re.compile(r"Floor")
NOT_FLOOR = re.compile(r"Overhead|Roof|Collision|Recovery|Entry")
DECOR = ("WallVoid*", "SunSlit*", "Porthole*")
COVE_STRAIGHT = re.compile(r"^Cove(Base|Top)\d")
COVE_TORUS = re.compile(r"^Cove(Base|Top)Corner")
COVE_VERTICAL = re.compile(r"^CornerCove")
COVE_ANY = re.compile(r"^(Cove|CornerCove)")
FREE_END_ANGLES = tuple(math.radians(t) for t in (10, 45, 80))    # arc probes from the wall tangent
SWERVE_SKIN = re.compile(r"^Swerve(S_|Corner_)")    # modules_swerve: wall + top cove + base cove + deck in one sweep
GROUND_COMPONENT = re.compile(r"^(Column|VaultPier|CurveWall|Swerve|SpiralStairWell|ExitSpiral|ExitPlatform|"
                              r"Walkway|PoolSteps|PumpStation|DrainHole|Chamber_)")
GLOW = ca.PASSABLE_MATERIALS
SIDES = ("North", "South", "West", "East")


def log(*a):
    print(*a, flush=True)


# ----------------------------------------------------------------------------------------------- scene

class Scene:
    def __init__(self, path):
        self.path = Path(path)
        self.world = ca.load_world(path)
        self.seed = self.world["requestedSeed"]
        self.chunks = load_kit_chunks(self.world)
        self.manifest = ca.world_manifests(self.world)
        self.halls = {h["Index"]: h for h in self.world["layout"]["Halls"]}
        self.placements, owner = ca.placements_of(self.world)
        self.parts = self.world["parts"]
        self._wall_inner()
        objects = {}                           # key -> object
        for part in self.parts:
            if part["id"] in owner:
                key = ("kit", owner[part["id"]])
            else:
                key = ("part", part["id"])
            objects.setdefault(key, []).append(part)
        self.objects = []
        tris, owners, mats, tparts = [], [], [], []
        index_of = {p["id"]: i for i, p in enumerate(self.parts)}
        for key, parts in objects.items():
            ob = {"key": key, "parts": parts, "vis": []}
            if key[0] == "kit":
                pl = self.placements[key[1]]
                ob.update(component=pl["component"], label=pl["component"], path=pl["modelPath"], pivot=pl["pivot"])
            else:
                p = parts[0]
                ob.update(component=None, label=re.sub(r"[\d.]+", "#", p["name"]), path=p["path"],
                          pivot=p["cframe"])
            ob["hall"] = self._hall_of_path(ob["path"])
            for part in parts:
                if part["transparency"] >= .98:
                    continue
                if part.get("fixtureKind") == "mesh":
                    chunk = fixture_chunk(part, self.chunks)
                    t = mesh_triangles_world(part, chunk)
                    mat = part["name"].rsplit("_", 1)[-1]
                    nrm = self._mesh_normals(part, chunk)
                elif part["class"] != "MeshPart":
                    t = np.asarray(wc.part_triangles(part), float)
                    mat = part.get("materialVariant") or str(part["material"]).replace("Material.", "")
                    nrm = None
                else:
                    continue
                ob["vis"].append((part, t, mat, nrm))
            if not ob["vis"]:
                self.objects.append(ob)
                continue
            ob["tris"] = np.concatenate([v[1] for v in ob["vis"]])
            pts = ob["tris"].reshape(-1, 3)
            ob["lo"], ob["hi"] = pts.min(0), pts.max(0)
            if ob["hall"] is None:
                ob["hall"] = self._hall_at(ob["lo"], ob["hi"])
            self.objects.append(ob)
            oid = len(self.objects) - 1
            for part, t, mat, nrm in ob["vis"]:
                tris.append(t)
                owners.append(np.full(len(t), oid))
                mats.append(np.full(len(t), mat, dtype=object))
                tparts.append(np.full(len(t), index_of[part["id"]]))
        self.T = np.concatenate(tris)
        self.owner = np.concatenate(owners)
        self.mat = np.concatenate(mats)
        self.tpart = np.concatenate(tparts)          # triangle -> index into self.parts
        cr = np.cross(self.T[:, 1] - self.T[:, 0], self.T[:, 2] - self.T[:, 0])
        self.area = .5 * np.linalg.norm(cr, axis=1)
        self.N = cr / np.maximum(2 * self.area, 1e-12)[:, None]
        self.is_mesh = self._mesh_flags()        # every MeshPart renders both sides, kit placement or not
        log(f"SCENE seed {self.seed}: {len(self.parts)} parts, {len(self.objects)} objects, {len(self.T)} triangles")
        self.bvh = self._bvh(self.T)
        self.colliders = ca.Colliders([p for p in self.parts if p["canCollide"]])
        self.solids = ca.Colliders([dict(p, canCollide=True) for p in self.parts
                                    if p["transparency"] < .98 and p["class"] != "MeshPart"], pad=1.0)
        self._sight = None
        self._closed = {}

    @property
    def sight(self):
        if self._sight is None:
            self._sight = Sight(self)
        return self._sight

    def outward_sign(self, pi):
        """+1/-1 turning the stored triangle normals of part pi outward, 0 for an open mesh. Part triangles are
        wound inward (-1); a watertight mesh is oriented by the sign of its enclosed volume."""
        if pi not in self._closed:
            part = self.parts[pi]
            if part.get("fixtureKind") != "mesh":
                self._closed[pi] = -1
            else:
                t = self.T[self.tpart == pi]
                vol = float(np.einsum("ij,ij->i", t[:, 0], np.cross(t[:, 1], t[:, 2])).sum()) if closed_mesh(t) else 0.0
                self._closed[pi] = int(np.sign(vol))
        return self._closed[pi]

    def outward(self, ti):
        """Outward unit normal of triangle ti when its part is a closed solid, else None."""
        s = self.outward_sign(int(self.tpart[ti]))
        return self.N[ti] * s if s else None

    def _mesh_flags(self):
        flags = []
        for ob in self.objects:
            for part, t, mat, nrm in ob.get("vis", []):
                flags.append(np.full(len(t), part.get("fixtureKind") == "mesh"))
        return np.concatenate(flags)

    @staticmethod
    def _bvh(tris):
        verts = tris.reshape(-1, 3).tolist()
        faces = np.arange(len(verts), dtype=np.int32).reshape(-1, 3).tolist()
        return BVHTree.FromPolygons(verts, faces, all_triangles=True)

    def _mesh_normals(self, part, chunk):
        """Stored (shading) normals per triangle corner, in world space (inverse-transpose of the scaled frame)."""
        rot = np.asarray(part["cframe"][3:], float).reshape(3, 3)
        scale = np.asarray(part["size"], float) / np.maximum(np.asarray(chunk["record"]["size"], float), 1e-9)
        n = chunk["normals"][chunk["indices"][:, :, 1]] / scale
        n = n @ rot.T
        return n / np.maximum(np.linalg.norm(n, axis=2)[:, :, None], 1e-12)

    def _hall_of_path(self, path):
        m = re.search(r"Level 2 Hall (\d+)\b", path or "")
        return self.halls.get(int(m.group(1))) if m else None

    def _hall_at(self, lo, hi):
        c = (lo + hi) / 2
        for h in self.halls.values():
            if h["MinX"] <= c[0] <= h["MaxX"] and h["MinZ"] <= c[2] <= h["MaxZ"]:
                return h
        return None

    def _wall_inner(self):
        """Inner wall face per hall side, measured from the builder's 'Level 2 Hall Wall ... <Side>' slabs."""
        self.inner = {}
        reach = defaultdict(list)
        for p in self.parts:
            m = re.search(r"Level 2 Hall Wall .*?(North|South|West|East)$", p["name"])
            h = self._hall_of_path(p["parentPath"]) if m else None
            if not h:
                continue
            c, r = wc.frame(p["cframe"])
            ext = np.abs(r) @ (np.asarray(p["size"]) / 2)
            lo, hi = c - ext, c + ext
            side = m.group(1)
            if side == "North":
                reach[(h["Index"], side)].append(hi[2] - h["MinZ"])
            elif side == "South":
                reach[(h["Index"], side)].append(h["MaxZ"] - lo[2])
            elif side == "West":
                reach[(h["Index"], side)].append(hi[0] - h["MinX"])
            else:
                reach[(h["Index"], side)].append(h["MaxX"] - lo[0])
        for h in self.halls.values():
            for side in SIDES:
                v = [x for x in reach.get((h["Index"], side), []) if 0 < x < 6]
                t = float(np.median(v)) if v else 1.75
                self.inner[(h["Index"], side)] = {
                    "North": h["MinZ"] + t, "South": h["MaxZ"] - t, "West": h["MinX"] + t, "East": h["MaxX"] - t}[side]

    def into_room(self, h, side, pts, face=None):
        """Signed distance from the inner wall face (or the given face plane) into the room."""
        f = self.inner[(h["Index"], side)] if face is None else face
        return {"North": pts[..., 2] - f, "South": f - pts[..., 2], "West": pts[..., 0] - f,
                "East": f - pts[..., 0]}[side]

    def nearest_side(self, h, p):
        return min(SIDES, key=lambda s: abs(float(self.into_room(h, s, np.asarray(p, float)))))

    def ceiling(self, h):
        return h["FloorY"] + h["CeilingClass"]

    def where(self, p):
        return ca.hall_of(self.world, p)


EYE_LIFTS = (2, 7)      # reachable space: the flood's standing (feet) voxels lifted 2..7 voxels, no sideways dilation
SIGHT_RANGE = 120.0
SIGHT_STEP = .7
SIGHT_DIRS = wc.directions(96)


class Sight:
    """Line of sight from reachable space. Viewpoints are the centres of the voxels a player's body column fills when
    flooded from ElevatorSpawn with the pressure doors open (collision_audit.reach_mask standing voxels lifted
    EYE_LIFTS, chest to just above the head). From two voxels up the flood guarantees a 3x3 collider-free footprint,
    so a viewpoint never sits in a one-voxel pit between colliders or inside a thin visual skin. A point is visible
    when a ray leaving it into an admissible cone enters a viewpoint voxel before it hits any visible triangle (BVH
    of every visible triangle, both sides) AND the straight line to that voxel's centre is clear: a ray sample can
    share a voxel with a surface, the centre is the actual viewpoint. Limitation: the third-person camera can rise
    above the head; tops of tall props only such a camera sees are not judged."""

    def __init__(self, sc):
        t = time.time()
        self.low, _, visited = ca.reach_mask(sc.world, log, with_body=False)
        eye = np.zeros_like(visited)
        for dy in range(EYE_LIFTS[0], EYE_LIFTS[1] + 1):
            eye[dy:] |= visited[:-dy]
        del visited
        self.eye = eye
        self.bvh = sc.bvh
        self.steps = np.arange(SIGHT_STEP / 2, SIGHT_RANGE, SIGHT_STEP)
        log(f"SIGHT {int(eye.sum())} reachable voxels ({time.time() - t:.1f} s)")

    def reachable(self, pts):
        return ca.lookup(self.eye, self.low, np.asarray(pts, float).reshape(-1, 3))

    def above_reachable(self, p):
        """p is reachable, or open air straight above reachable space (nothing visible in between)."""
        if self.reachable(p)[0]:
            return True
        i = np.floor(np.asarray(p, float) - self.low).astype(int)
        ny, nz, nx = self.eye.shape
        if not (0 <= i[0] < nx and 0 <= i[2] < nz):
            return False
        col = np.nonzero(self.eye[:min(max(i[1], 0), ny), i[2], i[0]])[0]
        if not len(col):
            return False
        drop = p[1] - (self.low[1] + col[-1] + .5)
        return self.bvh.ray_cast(Vector(p), Vector((0, -1, 0)), drop)[0] is None

    def visible(self, p, wedges, offset=.03, chunk=12):
        """True when p is seen from reachable space through any wedge. A wedge is a tuple of unit normals; its rays are
        the directions d with d.n > 0.1 for every n (one normal: a half-space; two: the region outside both)."""
        p = np.asarray(p, float)
        for wedge in wedges:
            ns = np.asarray(wedge, float).reshape(-1, 3)
            dirs = SIGHT_DIRS[np.all(SIGHT_DIRS @ ns.T > .1, axis=1)]
            if not len(dirs):
                continue
            mid = ns.sum(0)
            mid /= max(np.linalg.norm(mid), 1e-9)
            dirs = dirs[np.argsort(-(dirs @ mid))]
            o = p + mid * offset
            vo = Vector(o)
            for s in range(0, len(dirs), chunk):
                d = dirs[s:s + chunk]
                dist = np.array([(lambda h: SIGHT_RANGE if h[0] is None else h[3])(
                    self.bvh.ray_cast(vo, Vector(x), SIGHT_RANGE)) for x in d])
                pts = o + d[:, None, :] * self.steps[None, :, None]
                ok = self.steps[None, :] < dist[:, None] - .1
                if not ok.any():
                    continue
                hit = np.zeros(ok.shape, bool)
                hit[ok] = self.reachable(pts[ok])
                for r in np.nonzero(hit.any(1))[0]:
                    cells = np.unique(np.floor(pts[r][hit[r]] - self.low).astype(int), axis=0)[:3]
                    for c in cells + self.low + .5:
                        v = c - o
                        L = float(np.linalg.norm(v))
                        if self.bvh.ray_cast(vo, Vector(v / L), L - 1e-3)[0] is None:
                            return True
        return False


def ex(pos, ob=None, **kw):
    out = {"pos": [round(float(v), 2) for v in pos]}
    if ob is not None:
        out.update(component=ob["label"], path=ob["path"])
    out.update(kw)
    return out


def result(passed, count, examples, **kw):
    return dict(passed=bool(passed), count=int(count), examples=examples[:12], **kw)


# ----------------------------------------------------------------------------------------------- openings

def openings(sc):
    """Cuts in each hall's Overhead Tile slab: centre, half extents, ceiling C, hole radius if known."""
    tiles = defaultdict(list)
    for p in sc.parts:
        if "Overhead Tile" in p["name"] and p["transparency"] < .98:
            h = sc._hall_of_path(p["parentPath"])
            if h:
                c, r = wc.frame(p["cframe"])
                ext = np.abs(r) @ (np.asarray(p["size"]) / 2)
                tiles[h["Index"]].append((c - ext, c + ext))
    markers = [p for p in sc.parts if "Level2_OpenSkyRadius" in p["attributes"]]
    out = []
    step = .5

    def snap(v, faces):
        """The raster finds a cut edge to within one cell; the exact edge is the tile-box face nearest to it."""
        if not len(faces):
            return v
        k = int(np.argmin(np.abs(faces - v)))
        return float(faces[k]) if abs(faces[k] - v) <= step else v

    for hi_, boxes in tiles.items():
        h = sc.halls[hi_]
        C = sc.ceiling(h)
        x0, x1 = sc.inner[(hi_, "West")], sc.inner[(hi_, "East")]
        z0, z1 = sc.inner[(hi_, "North")], sc.inner[(hi_, "South")]
        xs = np.arange(x0 + step / 2, x1, step)
        zs = np.arange(z0 + step / 2, z1, step)
        cov = np.zeros((len(xs), len(zs)), bool)
        xf, zf = [], []
        for lo, hi in boxes:
            if hi[1] < C - .5 or lo[1] > C + .5:
                continue
            xf += [lo[0], hi[0]]
            zf += [lo[2], hi[2]]
            ix = (xs >= lo[0] - 1e-6) & (xs <= hi[0] + 1e-6)
            iz = (zs >= lo[2] - 1e-6) & (zs <= hi[2] + 1e-6)
            cov[np.ix_(ix, iz)] = True
        xf, zf = np.array(xf), np.array(zf)
        for comp in label_components(~cov):
            if len(comp) < 8:
                continue
            cx, cz = xs[comp[:, 0]], zs[comp[:, 1]]
            lo_x, hi_x = snap(cx.min() - step / 2, xf), snap(cx.max() + step / 2, xf)
            lo_z, hi_z = snap(cz.min() - step / 2, zf), snap(cz.max() + step / 2, zf)
            centre = np.array(((lo_x + hi_x) / 2, C, (lo_z + hi_z) / 2))
            half = (hi_x - lo_x) / 2, (hi_z - lo_z) / 2
            radius = None
            for m in markers:
                mp = np.asarray(m["cframe"][:3])
                if abs(mp[0] - centre[0]) <= half[0] and abs(mp[2] - centre[2]) <= half[1]:
                    radius = float(m["attributes"]["Level2_OpenSkyRadius"])
            owner, shaft = None, 0.0
            for oid, ob in enumerate(sc.objects):
                if ob["component"] and "tris" in ob:
                    pv = ob["pivot"]
                    if abs(pv[0] - centre[0]) <= half[0] and abs(pv[2] - centre[2]) <= half[1] and \
                            ob["hi"][1] >= C - .5 and ob["component"] not in ("LightRound",):
                        attrs = sc.manifest.get(ob["component"], {}).get("attrs", {})
                        if "HoleRadius" in attrs or "PanelSize" in attrs or "Radius" in attrs:
                            owner = oid
                            radius = radius or float(attrs.get("HoleRadius", attrs.get("Radius", 0)) or 0) or None
                            shaft = float(attrs.get("ShaftDepth", 0) or 0)
            out.append({"hall": h, "C": C, "centre": centre, "half": half, "radius": radius, "owner": owner,
                        "shaft": shaft,
                        "label": sc.objects[owner]["label"] if owner is not None else "unknown opening"})
    return out


def label_components(mask):
    """4-connected components of a 2-D bool mask (no scipy in Blender) -> list of (n, 2) index arrays."""
    seen = np.zeros_like(mask)
    comps = []
    for start in zip(*np.nonzero(mask)):
        if seen[start]:
            continue
        stack, cells = [start], []
        seen[start] = True
        while stack:
            i, j = stack.pop()
            cells.append((i, j))
            for a, b in ((i + 1, j), (i - 1, j), (i, j + 1), (i, j - 1)):
                if 0 <= a < mask.shape[0] and 0 <= b < mask.shape[1] and mask[a, b] and not seen[a, b]:
                    seen[a, b] = True
                    stack.append((a, b))
        comps.append(np.array(cells))
    return comps


# ----------------------------------------------------------------------------------------------- 1 leaks

THROAT_RIM = 1.0       # light wells flare from r+0.55 at C to the HoleRadius throat at C+0.71..C+ShaftDepth-0.71


def through_hole(origin, ray, o):
    """The ray passes the opening's round hole: inside HoleRadius at both ends of the straight throat (C+1 and
    C+ShaftDepth-1; at C when the opening has no shaft). A ray through a gap beside the plate fails one end."""
    if ray[1] <= 1e-5 or not o["radius"]:
        return False
    heights = (o["C"] + THROAT_RIM, o["C"] + o["shaft"] - THROAT_RIM) if o["shaft"] >= 2 * THROAT_RIM else (o["C"],)
    for y in heights:
        t = (y - origin[1]) / ray[1]
        if t <= 0:
            return False
        if np.hypot(*(origin + t * ray - o["centre"])[[0, 2]]) >= o["radius"] + .02:
            return False
    return True


def check_leaks(sc, ops):
    """Sample origins come from the layout rectangles; an origin a player can never see from (not reachable and not
    open air straight above reachable space, e.g. behind a chamber's rounded corner) is skipped, not a leak source."""
    samples = wc.sample_points(sc.world["layout"])
    rays = wc.directions()
    boxes = wc.volume_boxes(sc.world["layout"])
    clusters = defaultdict(lambda: {"count": 0, "sum": np.zeros(3), "example": None, "sources": set()})
    intended = leaks = skipped = 0
    for origin, label in samples:
        if not sc.sight.above_reachable(origin):
            skipped += 1
            continue
        v = Vector(origin)
        for ray in rays:
            if sc.bvh.ray_cast(v, Vector(ray), 2500)[0] is not None:
                continue
            if any(through_hole(origin, ray, o) for o in ops):
                intended += 1
                continue
            leaks += 1
            point = wc.first_volume_exit(origin, ray, boxes)
            c = clusters[tuple(np.floor(point / 12).astype(int))]
            c["count"] += 1
            c["sum"] += point
            c["sources"].add(label)
            c["example"] = c["example"] or (origin.tolist(), ray.tolist())
    recs = []
    for c in sorted(clusters.values(), key=lambda c: -c["count"]):
        p = c["sum"] / c["count"]
        near = wc.nearest_parts(p, sc.world, 3) if len(recs) < 12 else []
        recs.append(ex(p, rays=c["count"], where=sc.where(p), sample=np.round(c["example"][0], 1).tolist(),
                       direction=np.round(c["example"][1], 3).tolist(), sources=sorted(c["sources"])[:3],
                       nearest=near))
    return result(leaks == 0, len(recs), recs, leakRays=leaks, intendedRays=intended,
                  samplePoints=len(samples), unseenSamplePoints=skipped, raysPerPoint=len(rays))


# ----------------------------------------------------------------------------------------------- 2 ceiling

def check_ceiling(sc, ops):
    bad = []
    for marker in (p for p in sc.parts if "Level2_OpenSkyRadius" in p.get("attributes", {})):
        mp = np.asarray(marker["cframe"][:3], float)
        if not any(abs(mp[0] - o["centre"][0]) <= o["half"][0] and
                   abs(mp[2] - o["centre"][2]) <= o["half"][1] for o in ops):
            bad.append(ex(mp, None, component=marker.get("fixtureComponent") or marker["name"],
                          path=marker["path"], issue="open-sky marker has no measured ceiling cut"))
    # a) per hall: visible objects touching the ceiling but not standing on the floor
    piers = [ob for ob in sc.objects if ob["component"] and re.match(r"VaultPier|Column", ob["component"])
             and "tris" in ob]
    for ob in sc.objects:
        h = ob["hall"]
        if "tris" not in ob or h is None or h.get("Role") == "Small":
            continue
        name = ob["label"]
        if SHELL.search(ob["parts"][0]["name"]) or COVE_ANY.match(ob["component"] or ""):
            continue
        C = sc.ceiling(h)
        lo, hi = ob["lo"], ob["hi"]
        if hi[1] < C - .3 or lo[1] <= h["FloorY"] + 1 or lo[1] >= C - .02:
            continue
        centre = (lo + hi) / 2
        if min(abs(float(sc.into_room(h, s, centre))) for s in SIDES) < 4:
            continue                        # wall-attached (coves, top trims)
        depth = C - lo[1]
        if (ob["component"] or "").startswith("LightRound") and depth <= .6:
            continue
        if (ob["component"] or "").startswith("VaultBay"):
            corners = [(x, z) for x in (lo[0], hi[0]) for z in (lo[2], hi[2])]
            carried = sum(any(p["lo"][0] - 1.5 <= x <= p["hi"][0] + 1.5 and p["lo"][2] - 1.5 <= z <= p["hi"][2] + 1.5
                              and p["lo"][1] <= h["FloorY"] + 1 for p in piers) for x, z in corners)
            if carried == 4:
                continue
            bad.append(ex(centre, ob, issue=f"vault bay carried at {carried}/4 corners", depth=round(depth, 2)))
            continue
        bad.append(ex(centre, ob, issue="hangs below the ceiling", depth=round(float(depth), 2)))
    hanging = len(bad)
    # b) per opening: flush plate, nothing in the cut prism, no square gap to the sky
    for o in ops:
        c, (hx, hz), C = o["centre"], o["half"], o["C"]
        half = max(hx, hz)
        cheb = np.maximum(np.abs(sc.T[:, :, 0] - c[0]), np.abs(sc.T[:, :, 2] - c[2]))     # per corner
        y = sc.T[:, :, 1]
        own = sc.owner == o["owner"] if o["owner"] is not None else np.zeros(len(sc.T), bool)
        not_ceiling = np.array([not SHELL.search(sc.objects[i]["parts"][0]["name"]) for i in sc.owner]) \
            if not hasattr(sc, "_not_shell") else sc._not_shell
        sc._not_shell = not_ceiling
        near = (cheb.min(1) <= half + 1) & not_ceiling
        on_c = near[:, None] & own[:, None] & (np.abs(y - C) <= .02) & (cheb <= half + 1)
        problems = []
        if not on_c.any():
            problems.append("no plate vertex on the ceiling plane")
        else:
            x_edge = float(np.abs(sc.T[:, :, 0] - c[0])[on_c].max())
            z_edge = float(np.abs(sc.T[:, :, 2] - c[2])[on_c].max())
            if abs(x_edge - hx) > .02 or abs(z_edge - hz) > .02:
                problems.append(f"plate outer edge [{x_edge:.2f}, {z_edge:.2f}] != cut half [{hx:.2f}, {hz:.2f}]")
        inside = (cheb < half - .05) & (y < C - .02) & (y >= C - 12)
        own_hang = inside & (y >= C - 3) & own[:, None]
        other = inside & ~own[:, None] & not_ceiling[:, None]
        if own_hang.any():
            problems.append(f"opening hangs {C - float(y[own_hang].min()):.2f} below the ceiling inside its cut")
        if other.any():
            labels = sorted({sc.objects[i]["label"] for i in sc.owner[other.any(1)]})
            problems.append("intrudes into the cut prism: " + ", ".join(labels[:4]))
        # sky through the cut
        gx = np.arange(c[0] - hx + .25, c[0] + hx, .5)
        gz = np.arange(c[2] - hz + .25, c[2] + hz, .5)
        esc = []
        for x in gx:
            for z in gz:
                if sc.bvh.ray_cast(Vector((x, C - 1, z)), Vector((0, 1, 0)), 500)[0] is None:
                    esc.append((x, z))
        esc = np.array(esc).reshape(-1, 2)
        if len(esc):
            r = np.hypot(esc[:, 0] - c[0], esc[:, 1] - c[2])
            if o["radius"]:
                outside = r > o["radius"] + .1
                if outside.any():
                    problems.append(f"sky through the cut outside the r{o['radius']:g} hole: "
                                    f"{outside.sum() * .25:.1f} stud^2")
            elif len(esc) * .25 > 1.15 * math.pi * r.max() ** 2:
                problems.append(f"sky through a non-round gap ({len(esc) * .25:.1f} stud^2, r_max {r.max():.1f})")
        if problems:
            bad.append(ex(c, sc.objects[o["owner"]] if o["owner"] is not None else None,
                          hall=f"Hall {o['hall']['Index']} {o['hall']['Type']}", cutHalf=[hx, hz],
                          radius=o["radius"], issue="; ".join(problems)))
    return result(not bad, len(bad), bad, hangingObjects=hanging, openings=len(ops),
                  failingOpenings=len(bad) - hanging)


# ----------------------------------------------------------------------------------------------- 3 jump reach

def check_jump(sc, ops):
    bad = []
    col = sc.colliders
    caps = [p for p in sc.parts if p["canCollide"] and "Sky Cap" in p["name"]]
    cap_col = ca.Colliders(caps) if caps else None
    aabb_lo = col.c - np.einsum("nij,nj->ni", np.abs(col.R), col.e)
    aabb_hi = col.c + np.einsum("nij,nj->ni", np.abs(col.R), col.e)
    non_cap = np.array([not any(k in p["name"] for k in ("Sky Cap", "Roof Collider", "Overhead Tile", "Ceiling"))
                        for p in col.parts])
    for o in ops:
        c, (hx, hz), C = o["centre"], o["half"], o["C"]
        w = max(hx, hz) + 10
        sel = (aabb_lo[:, 0] < c[0] + w) & (aabb_hi[:, 0] > c[0] - w) & (aabb_lo[:, 2] < c[2] + w) & \
              (aabb_hi[:, 2] > c[2] - w) & (aabb_hi[:, 1] > C - 14) & (aabb_hi[:, 1] <= C + 1) & non_cap & \
              (aabb_hi[:, 0] - aabb_lo[:, 0] >= 1) & (aabb_hi[:, 2] - aabb_lo[:, 2] >= 1)
        where = f"Hall {o['hall']['Index']} {o['hall']['Type']}"
        if sel.any():
            i = int(np.argmax(np.where(sel, aabb_hi[:, 1], -1e9)))
            names = sorted({ca.label_of(col.parts[j])[0] for j in np.nonzero(sel)[0]})
            bad.append(ex(c, None, hall=where, issue=f"standable top {aabb_hi[i, 1] - C:+.2f} rel C within "
                          f"{w:.0f} of the opening", parts=names[:5], opening=o["label"]))
        gx = np.arange(c[0] - hx + .25, c[0] + hx, 1.0)
        gz = np.arange(c[2] - hz + .25, c[2] + hz, 1.0)
        g = np.array([(x, z) for x in gx for z in gz])
        covered = np.zeros(len(g), bool)
        if cap_col is not None:
            for yy in np.arange(C + .25, C + 3, .5):
                covered |= cap_col.inside(np.column_stack((g[:, 0], np.full(len(g), yy), g[:, 1])))
        if not covered.all():
            bad.append(ex(c, None, hall=where, opening=o["label"],
                          issue=f"no colliding Sky Cap: {100 * (~covered).mean():.0f}% of the cut open above C"))
        bad_caps = [p["name"] for p in caps if abs(p["cframe"][0] - c[0]) <= hx and
                    abs(p["cframe"][2] - c[2]) <= hz and
                    (p.get("canQuery", True) or p.get("canTouch", True) or p["transparency"] < .98)]
        if bad_caps:
            bad.append(ex(c, None, hall=where, opening=o["label"],
                          issue="Sky Cap must be invisible, CanQuery=false and CanTouch=false", parts=bad_caps[:3]))
    return result(not bad, len(bad), bad, openings=len(ops))


# ----------------------------------------------------------------------------------------------- 4 floating

def horizontal_bvh(sc):
    """BVH of floor-like faces: Parts' outward-up faces (part_triangles winding is inward) and mesh faces with
    |n.y| > 0.5 (meshes render both sides). Returns (bvh, owner per face)."""
    up = np.where(sc.is_mesh, np.abs(sc.N[:, 1]) > .5, -sc.N[:, 1] > .5)
    idx = np.nonzero(up)[0]
    return sc._bvh(sc.T[idx]), sc.owner[idx]


def first_foreign(bvh, owners, origin, direction, me, limit):
    o = Vector(origin)
    d = Vector(direction)
    travelled = 0.0
    for _ in range(64):
        loc, _, i, dist = bvh.ray_cast(o, d, limit - travelled)
        if loc is None:
            return None
        if owners[i] != me:
            return travelled + dist
        # A flush decal's own face can coincide with the surface it rests on; skipping past the own face would
        # step over that coplanar support, so a foreign face within 0.01 of the own hit counts as the hit.
        if any(owners[n[2]] != me for n in bvh.find_nearest_range(loc, .01)):
            return travelled + dist
        travelled += dist + 1e-3
        o = loc + d * 1e-3
    return None


def check_floating(sc):
    bvh, owners = horizontal_bvh(sc)
    bad = []
    tested = 0
    for oid, ob in enumerate(sc.objects):
        h = ob["hall"]
        if "tris" not in ob or h is None:
            continue
        name = ob["parts"][0]["name"]
        if SHELL.search(name) or (FLOOR.search(name) and not ob["component"]):
            continue
        fy = h["FloorY"]
        lo = ob["lo"]
        upper = fy + (8.0 if GROUND_COMPONENT.match(ob["component"] or "") else 1.0)
        if not (fy - 4.5 <= lo[1] <= upper):
            continue
        pts = ob["tris"].reshape(-1, 3)
        bottom = pts[pts[:, 1] <= lo[1] + .05]
        inner = (bottom[:, 0] > sc.inner[(h["Index"], "West")] + .1) & (bottom[:, 0] < sc.inner[(h["Index"], "East")] - .1) & \
                (bottom[:, 2] > sc.inner[(h["Index"], "North")] + .1) & (bottom[:, 2] < sc.inner[(h["Index"], "South")] - .1)
        bottom = np.unique(np.round(bottom[inner], 3), axis=0)
        if not len(bottom):
            continue
        if len(bottom) > 24:
            bottom = bottom[np.linspace(0, len(bottom) - 1, 24).astype(int)]
        tested += 1
        worst, where = 0.0, None
        for v in bottom:
            if first_foreign(bvh, owners, v - (0, 1e-3, 0), (0, 1, 0), oid, 5.0) is not None:
                continue                            # under a floor/deck surface: buried, fine
            d = first_foreign(bvh, owners, v + (0, .02, 0), (0, -1, 0), oid, 12.0)
            gap = 12.0 if d is None else d - .02
            if gap > worst:
                worst, where = gap, v
        if worst > .05:
            bad.append(ex(where, ob, gap=round(float(worst), 2), hallType=h["Type"]))
    bad.sort(key=lambda e: -e["gap"])
    by = defaultdict(lambda: [0, 0.0])
    for e in bad:
        k = f"{e['component']} ({e['hallType']})"
        by[k][0] += 1
        by[k][1] = max(by[k][1], e["gap"])
    return result(not bad, len(bad), bad, tested=tested,
                  byComponent={k: {"count": v[0], "maxGap": v[1]} for k, v in sorted(by.items(), key=lambda kv: -kv[1][0])})


# ----------------------------------------------------------------------------------------------- 5 water

def part_top(p, X, Z):
    c, r = wc.frame(p["cframe"])
    up = r[:, 1]
    if abs(up[1]) < .5:
        return np.full(X.shape, -1e9)
    t = c + up * p["size"][1] / 2 * np.sign(up[1])
    up = up * np.sign(up[1])
    return t[1] - (up[0] * (X - t[0]) + up[2] * (Z - t[2])) / up[1]


def part_contains_xz(p, X, Z):
    c, r = wc.frame(p["cframe"])
    h = np.asarray(p["size"]) / 2
    lx = (X - c[0]) * r[0, 0] + (Z - c[2]) * r[2, 0]
    lz = (X - c[0]) * r[0, 2] + (Z - c[2]) * r[2, 2]
    return (np.abs(lx) <= h[0] + 1e-6) & (np.abs(lz) <= h[2] + 1e-6)


def region_box(r):
    """World AABB of a water region. Builder regions are yawed by multiples of 90 deg (a Z-axis corridor's
    16 x 3.9 x L box), so the rotated extent is exact; region_oblique() flags anything else."""
    c, rot = wc.frame(r["cframe"])
    e = np.abs(rot) @ (np.asarray(r["size"], float) / 2)
    return c - e, c + e


def region_oblique(r):
    return ca.is_oblique_rotation(wc.frame(r["cframe"])[1])


def water_grid(regions):
    if not regions:
        return None
    lo = np.floor(np.min([region_box(r)[0] for r in regions], 0) / 4).astype(int) - 1
    hi = np.ceil(np.max([region_box(r)[1] for r in regions], 0) / 4).astype(int) + 1
    occ = np.zeros(tuple(hi - lo), np.float32)
    for r in regions:
        a, b = region_box(r)
        f = []
        for k in range(3):
            cells = (np.arange(lo[k], hi[k])) * 4.0
            f.append(np.clip(np.minimum(b[k], cells + 4) - np.maximum(a[k], cells), 0, 4) / 4)
        occ = np.maximum(occ, f[0][:, None, None] * f[1][None, :, None] * f[2][None, None, :])
    return lo, occ


def solid_at(grid, x, z, surf):
    """Voxel column at (x, z) solid at the surface level (full row, or a partial row on a full row)."""
    lo, occ = grid
    i = np.floor(x / 4).astype(int) - lo[0]
    k = np.floor(z / 4).astype(int) - lo[2]
    j = math.floor((surf - .01) / 4) - lo[1]
    ok = (i >= 0) & (i < occ.shape[0]) & (k >= 0) & (k < occ.shape[2]) & (0 < j < occ.shape[1])
    out = np.zeros(x.shape, bool)
    if not (0 < j < occ.shape[1]):
        return out
    o = occ[i[ok], j, k[ok]]
    below = occ[i[ok], j - 1, k[ok]]
    expect = (surf - 4 * (j + lo[1])) / 4
    out[ok] = (o >= .9) | ((below >= .9) & (np.abs(o - expect) < .02))
    return out


def check_water(sc):
    regions = sc.world["terrainWaterRegions"]
    grid = water_grid([r for r in regions if "Water" in str(r.get("material", "Water"))])
    boxes = [region_box(r) for r in regions]
    floors = [p for p in sc.parts if p["canCollide"] and p["transparency"] < .98 and p["class"] != "MeshPart"
              and FLOOR.search(p["name"]) and not NOT_FLOOR.search(p["name"])]
    spaces = []
    for h in sc.halls.values():
        spaces.append((f"Hall {h['Index']} {h['Type']}", (h["MinX"], h["MaxX"], h["MinZ"], h["MaxZ"]), h["FloorY"]))
    for c in sc.world["layout"]["Corridors"]:
        if c["FromY"] != c["ToY"]:
            continue
        half = c["Width"] / 2
        fp = (c["From"], c["To"], c["Cross"] - half, c["Cross"] + half) if c["Axis"] == "X" else \
            (c["Cross"] - half, c["Cross"] + half, c["From"], c["To"])
        spaces.append((f"Corridor {c['Index']} {c['Kind']} {c['Variant']}", fp, c["FromY"]))
    step = .5
    bad, total_dry, total_thin = [], 0.0, 0.0
    flooded = 0
    for r in regions:
        if region_oblique(r):
            bad.append(ex(r["cframe"][:3], None, space=r.get("label"), issue="oblique water region: terrain water is "
                          "voxelised on the world grid, its edge cannot follow an oblique wall", dryNoWater=0.0,
                          notSolidAtSurface=0.0))
    for name, (x0, x1, z0, z1), F in spaces:
        mine = [p for p in floors if np.any(part_contains_xz(p, np.array([(x0 + x1) / 2]), np.array([(z0 + z1) / 2])))
                or overlaps_xz(p, x0, x1, z0, z1)]
        if not mine:
            continue
        xs = np.arange(x0 + step / 2, x1, step)
        zs = np.arange(z0 + step / 2, z1, step)
        X, Z = np.meshgrid(xs, zs, indexing="ij")
        top = np.full(X.shape, -1e9)
        for p in mine:
            m = part_contains_xz(p, X, Z)
            if m.any():
                top = np.where(m, np.maximum(top, part_top(p, X, Z)), top)
        basin = (top > -1e8) & (top < F - .05)
        if not basin.any():
            continue
        flooded += 1
        Xb, Zb, Tb = X[basin], Z[basin], top[basin]
        probe = np.column_stack((Xb, Tb + .15, Zb))
        visible = ~sc.colliders.inside(probe)
        Xb, Zb, Tb = Xb[visible], Zb[visible], Tb[visible]
        if not len(Xb):
            continue
        surf = np.full(len(Xb), -1e9)
        for lo, hi in boxes:
            m = (Xb >= lo[0]) & (Xb <= hi[0]) & (Zb >= lo[2]) & (Zb <= hi[2]) & (hi[1] > Tb)
            surf = np.where(m, np.maximum(surf, hi[1]), surf)
        dry = surf < -1e8
        thin = np.zeros(len(Xb), bool)
        if grid is not None and (~dry).any():
            for s in np.unique(surf[~dry]):
                m = (~dry) & (surf == s)
                ok = solid_at(grid, Xb[m], Zb[m], s)
                for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    px, pz = Xb[m] + dx, Zb[m] + dz
                    walled = sc.colliders.inside(np.column_stack((px, np.minimum(Tb[m] + .15, s - .02), pz)))
                    ok &= solid_at(grid, px, pz, s) | walled
                thin[np.nonzero(m)[0][~ok]] = True
        a_dry, a_thin = dry.sum() * step * step, thin.sum() * step * step
        total_dry += a_dry
        total_thin += a_thin
        if a_dry > 0 or a_thin > 0:
            k = np.nonzero(dry | thin)[0][0]
            floor_part = next((p for p in mine if part_contains_xz(p, np.array([Xb[k]]), np.array([Zb[k]]))[0]), mine[0])
            bad.append(ex((Xb[k], Tb[k], Zb[k]), None, space=name, component=floor_part.get("fixtureComponent") or
                          floor_part["name"], path=floor_part["path"], visibleBasin=round(len(Xb) * step * step, 1),
                          dryNoWater=round(float(a_dry), 1), notSolidAtSurface=round(float(a_thin), 1)))
    bad.sort(key=lambda e: -(e["dryNoWater"] + e["notSolidAtSurface"]))
    return result(not bad, len(bad), bad, floodedSpaces=flooded, dryArea=round(total_dry, 1),
                  notSolidArea=round(total_thin, 1))


def overlaps_xz(p, x0, x1, z0, z1):
    c, r = wc.frame(p["cframe"])
    ext = np.abs(r) @ (np.asarray(p["size"]) / 2)
    return c[0] - ext[0] < x1 and c[0] + ext[0] > x0 and c[2] - ext[2] < z1 and c[2] + ext[2] > z0


# ----------------------------------------------------------------------------------------------- 6 coves

def check_coves(sc):
    bad = []
    stats = defaultdict(lambda: [0, 0])
    cove_ids = [oid for oid, ob in enumerate(sc.objects) if "tris" in ob and COVE_ANY.match(ob["component"] or "")]
    # A straight cove may also run on into a swerve skin, whose profile carries the same R3 top and base coves.
    skin_ids = [oid for oid, ob in enumerate(sc.objects) if "tris" in ob and SWERVE_SKIN.match(ob["component"] or "")]
    sel = np.isin(sc.owner, cove_ids + skin_ids)
    cidx = np.nonzero(sel)[0]
    cbvh = sc._bvh(sc.T[cidx]) if len(cidx) else None
    cown = sc.owner[cidx]
    for oid in cove_ids:
        ob = sc.objects[oid]
        h = ob["hall"]
        comp = ob["component"]
        attrs = sc.manifest.get(comp, {}).get("attrs", {})
        if h is None:
            continue
        m = sc.owner == oid
        T, Ns = sc.T[m], None
        normals = [v[3] for v in ob["vis"] if v[3] is not None]
        Ns = np.concatenate(normals).mean(1) if normals else None
        cent = T.mean(1)
        tn = sc.N[m]
        C = sc.ceiling(h)
        top = "Top" in comp
        issues = []
        pivot = np.asarray(ob["pivot"][:3], float)
        if COVE_STRAIGHT.match(comp) or ("WallSide" in attrs and "Corner" not in comp and "Stop" not in comp):
            R = float(attrs.get("Radius", 3))
            side = sc.nearest_side(h, pivot)
            # The run's own wall face is its pivot plane (wallPose): the hall's inner face, or a swerve hall's
            # plateau face set Offset further in. Measuring from the hall face put plateau coves off their wall.
            axis = 2 if side in ("North", "South") else 0
            face = float(pivot[axis])
            dw = sc.into_room(h, side, cent, face)
            along = np.array((1.0, 0, 0)) if side in ("North", "South") else np.array((0, 0, 1.0))
            dh = (C - cent[:, 1]) if top else (cent[:, 1] - pivot[1])
            arc = (dw > .05) & (dw < R - .05) & (dh > .05) & (dh < R - .05) & (np.abs(tn @ along) < .3)
            centre_dir = None
            if not arc.any():
                issues.append("no fillet faces in the wall/floor corner band")
            else:
                conc = np.abs(np.hypot(R - dw[arc], R - dh[arc]) - R) < .15
                if conc.mean() < .9:
                    bull = np.abs(np.hypot(R - dw[arc], dh[arc]) - R) < .15
                    issues.append("convex bullnose (round side away from the wall corner)" if bull.mean() > .5
                                  else f"not a concave R{R:g} fillet ({conc.mean():.0%} on the arc)")
                elif Ns is not None:
                    # shading normals must point toward the fillet centre (into the room)
                    wall_n = {"North": (0, 0, 1), "South": (0, 0, -1), "West": (1, 0, 0), "East": (-1, 0, 0)}[side]
                    to_c = np.array(wall_n)[None] * (R - dw[arc])[:, None] + \
                        np.array((0, -1 if top else 1, 0))[None] * (R - dh[arc])[:, None]
                    facing = ((Ns[arc] * to_c).sum(1) > 0).mean()
                    if facing < .9:
                        issues.append(f"shading normals face away from the room on {1 - facing:.0%} of the arc")
            # free ends: 0.2 past each end, the next piece's surface must pass within 0.35 of this run's arc at
            # 10, 45 and 80 deg (a flush continuation of the same profile, not just something nearby)
            if cbvh is not None:
                a = (T.reshape(-1, 3) @ along)
                wall_n = {"North": (0, 0, 1), "South": (0, 0, -1), "West": (1, 0, 0), "East": (-1, 0, 0)}[side]
                for end, sgn in ((a.min(), -1), (a.max(), 1)):
                    for theta in FREE_END_ANGLES:
                        dw_t, dh_t = R * (1 - math.cos(theta)), R * (1 - math.sin(theta))
                        p = pivot.copy()
                        p[axis] = face + wall_n[axis] * dw_t
                        p[1] = (C - dh_t) if top else (pivot[1] + dh_t)
                        p[0 if along[0] else 2] = end + sgn * .2
                        near = cbvh.find_nearest_range(Vector(p), .35)
                        if not any(cown[n[2]] != oid for n in near):
                            issues.append(f"free end at {np.round(p, 1).tolist()}")
                            break
            kind = "straight"
        elif COVE_TORUS.match(comp) or COVE_VERTICAL.match(comp):
            R = float(attrs.get("CornerRadius", attrs.get("Radius", 0)))
            f = float(attrs.get("FilletRadius", 3))
            cx = h["MinX"] if pivot[0] < (h["MinX"] + h["MaxX"]) / 2 else h["MaxX"]
            cz = h["MinZ"] if pivot[2] < (h["MinZ"] + h["MaxZ"]) / 2 else h["MaxZ"]
            sx, sz = (1 if cx == h["MinX"] else -1), (1 if cz == h["MinZ"] else -1)
            fx = sc.inner[(h["Index"], "West" if sx > 0 else "East")] + sx * R
            fz = sc.inner[(h["Index"], "North" if sz > 0 else "South")] + sz * R
            r = np.hypot(cent[:, 0] - fx, cent[:, 2] - fz)
            if COVE_VERTICAL.match(comp):
                kind = "vertical"
                vert = np.abs(tn[:, 1]) < .2
                quad = ((cent[:, 0] - fx) * -sx >= -1e-3) & ((cent[:, 2] - fz) * -sz >= -1e-3)
                on = vert & quad & (np.abs(r - R) < .1)
                ang = np.degrees(np.arctan2(np.abs(cent[on, 2] - fz), np.abs(cent[on, 0] - fx)))
                bins = len(np.unique(np.clip(np.floor(ang / 5), 0, 17)))
                if bins < 17:
                    issues.append(f"not a concave R{R:g} fillet tangent to both walls ({bins * 5} of 90 deg)")
            else:
                kind = "torus"
                dw = R - r
                dh = (C - cent[:, 1]) if top else (cent[:, 1] - pivot[1])
                arc = (dw > .05) & (dw < f - .05) & (dh > .05) & (dh < f - .05)
                if not arc.any():
                    issues.append("no fillet faces at the corner")
                else:
                    conc = np.abs(np.hypot(f - dw[arc], f - dh[arc]) - f) < .15
                    if conc.mean() < .9:
                        issues.append(f"not a concave fillet around the corner ({conc.mean():.0%})")
        else:
            continue
        stats[kind][0] += 1
        if issues:
            stats[kind][1] += 1
            bad.append(ex(cent.mean(0), ob, kind=kind, issue="; ".join(issues[:3])))
    return result(not bad, len(bad), bad, byKind={k: {"pieces": v[0], "failing": v[1]} for k, v in stats.items()})


# ----------------------------------------------------------------------------------------------- 7 intersections

def closed_mesh(tris):
    """Every undirected edge shared by exactly two triangles (vertex positions rounded to 1e-4)."""
    v = np.round(tris.reshape(-1, 3), 4)
    _, inv = np.unique(v, axis=0, return_inverse=True)
    f = inv.reshape(-1, 3)
    e = np.sort(np.concatenate((f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]])), axis=1)
    _, counts = np.unique(e, axis=0, return_counts=True)
    return bool(len(counts)) and bool(np.all(counts == 2))


TANGENT_COS = .97       # surfaces meeting within ~14 deg of parallel: a tangent/flush junction (a cove into its wall)
SQUARE_COS = .17        # within ~10 deg of square
SUPPORT = re.compile(r"^Level 2 (Hall (Wall|Floor|Water Floor|Sill|Lintel)|Overhead Tile|Arrival Wall|"
                     r"Corridor (Wall|Floor)|Passage (Wall|Floor)|Room (Wall|Floor))|Deck")
# Decks and the chamber room shells. The corridor tubes (RoundTunnel_/Pipe_) are NOT support: a part pushed squarely
# into a tunnel wall is a crease (test_level2_world_audit plants one). The one square junction with a tube that is
# authored is door_in_own_tube: a pressure door is its corridor's own bore disc seated 0.3 into the mouth collar with its lower
# segment under the walkway (Kit World Builder, FA), so a 'Level 2 Pressure Door N' (or its Stripe) meets the
# RoundTunnel_ of corridor N only squarely, a door in its frame. An oblique cut still counts (a planted control).
SUPPORT_COMPONENT = re.compile(r"^(Walkway|Chamber_)")
DOOR = re.compile(r"^Level 2 Pressure Door (?:Stripe )?(\d+)$")
OWN_TUBE = re.compile(r"\.Level 2 Corridor (\d+)\.RoundTunnel_")     # a tube part's path after makeCorridor reparents


def door_in_own_tube(sc, oa, ob):
    """True when one object is pressure door N (or its stripe) and the other the RoundTunnel_ of corridor N."""
    for d, t in ((sc.objects[oa], sc.objects[ob]), (sc.objects[ob], sc.objects[oa])):
        m = DOOR.match(d["parts"][0]["name"]) if d["key"][0] == "part" else None
        if not m or t["key"][0] != "kit" or not (t["component"] or "").startswith("RoundTunnel_"):
            continue
        tubes = {int(n.group(1)) for n in (OWN_TUBE.search(p.get("path") or "") for p in t["parts"]) if n}
        if tubes == {int(m.group(1))}:
            return True
    return False
# Authored assemblies: parts of one objective model are mounted into each other on purpose (a lever hub in the pump
# housing, a stripe on its door), so their mutual penetrations are not judged.
ASSEMBLY = re.compile(r"\.Level 2 (Pump Station \d+)\.|\.Level 2 (Pressure Door)(?: Stripe)? (\d+)$")
MIN_VISIBLE = .25       # stud (intersection line) / stud^2 (coplanar overlap) seen from reachable space
SIGHT_POINTS = 16       # sight tests per object pair (a random spread over its candidate points)


def tri_tri_segments(A, B):
    """Intersection segments of triangle pairs A[i] x B[i] (n, 3, 3) -> ((n, 2, 3) endpoints, valid mask).
    Coplanar pairs are invalid: the z-fight check owns coplanar overlap."""
    def unit_normal(T):
        n = np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0])
        return n / np.maximum(np.linalg.norm(n, axis=1)[:, None], 1e-12)

    nA, nB = unit_normal(A), unit_normal(B)
    line = np.cross(nA, nB)
    ln = np.linalg.norm(line, axis=1)
    valid = ln > 1e-6
    line /= np.maximum(ln, 1e-12)[:, None]

    def interval(T, n0, p0):
        d = np.einsum("nij,nj->ni", T - p0[:, None, :], n0)
        lo, hi = np.full(len(T), np.inf), np.full(len(T), -np.inf)
        plo, phi = np.zeros((len(T), 3)), np.zeros((len(T), 3))
        for i, j in ((0, 1), (1, 2), (2, 0)):
            di, dj = d[:, i], d[:, j]
            hit = (di * dj <= 0) & (np.abs(di - dj) > 1e-12)
            t = np.where(hit, di / np.where(hit, di - dj, 1), 0)
            p = T[:, i] + t[:, None] * (T[:, j] - T[:, i])
            s = np.where(hit, (p * line).sum(1), np.nan)
            m = hit & (s < lo)
            lo, plo = np.where(m, s, lo), np.where(m[:, None], p, plo)
            m = hit & (s > hi)
            hi, phi = np.where(m, s, hi), np.where(m[:, None], p, phi)
        return lo, hi, plo, phi

    la, ha, pla, pha = interval(A, nB, B[:, 0])
    lb, hb, plb, phb = interval(B, nA, A[:, 0])
    lo, hi = np.maximum(la, lb), np.minimum(ha, hb)
    valid &= np.isfinite(lo) & np.isfinite(hi) & (hi > lo + 1e-6)
    p0 = np.where((la >= lb)[:, None], pla, plb)
    p1 = np.where((ha <= hb)[:, None], pha, phb)
    return np.stack((p0, p1), 1), valid


def render_sides(sc, ti):
    """Unit normals of the sides a triangle renders to: a Part only outward (part_triangles winding is inward),
    a MeshPart both (kit meshes are DoubleSided in Roblox)."""
    n = sc.N[ti]
    return (n, -n) if sc.is_mesh[ti] else (-n,)


CREASE_OFFSET = .08     # a crease is seen when both surfaces are seen this far off the intersection line


def visible_intersection(sc, cache, oa, ob, support, rng):
    """(stud of the oa/ob intersection line that is a visible crease, a seen point). Tangent junctions and square
    junctions with a support surface are dropped first. A line sample then counts when, on BOTH surfaces, a point
    CREASE_OFFSET off the line (on that object's own surface) is seen from reachable space: a face that ends at the
    line or continues only into the other solid makes no visible crease. The sum is a lower bound (sampled points
    are spread over the line, each carrying the line length it stands for)."""
    (ta, bvh_a), (tb, bvh_b) = cache(oa), cache(ob)
    if bvh_a is None or bvh_b is None:
        return 0.0, None
    pairs = np.array(bvh_a.overlap(bvh_b), dtype=int).reshape(-1, 2)
    if not len(pairs):
        return 0.0, None
    ia, ib = ta[pairs[:, 0]], tb[pairs[:, 1]]
    seg, ok = tri_tri_segments(sc.T[ia], sc.T[ib])
    cos = np.abs((sc.N[ia] * sc.N[ib]).sum(1))
    ok &= cos < TANGENT_COS
    if support:
        ok &= cos > SQUARE_COS
    if not ok.any():
        return 0.0, None
    seg, ia, ib = seg[ok], ia[ok], ib[ok]
    length = np.linalg.norm(seg[:, 1] - seg[:, 0], axis=1)
    n = np.maximum(1, np.ceil(length / .25)).astype(int)
    k = np.repeat(np.arange(len(seg)), n)
    f = (np.arange(len(k)) - np.repeat(np.cumsum(n) - n, n) + .5) / n[k]
    pts = seg[k, 0] + f[:, None] * (seg[k, 1] - seg[k, 0])
    w = (length / n)[k]
    cell = np.round(pts / .5).astype(np.int64)
    _, first, inverse = np.unique(cell, axis=0, return_index=True, return_inverse=True)
    weight = np.bincount(inverse.reshape(-1), weights=w)
    order = rng.permutation(len(first))[:2 * SIGHT_POINTS]
    seen, where = 0.0, None

    def surface_seen(m, line, tri, bvh):
        u = np.cross(sc.N[tri], line)
        u /= max(np.linalg.norm(u), 1e-12)
        for q in (m + CREASE_OFFSET * u, m - CREASE_OFFSET * u):
            near = bvh.find_nearest(Vector(q))
            if near[0] is not None and near[3] < 2e-3 and                     sc.sight.visible(q, [(s,) for s in render_sides(sc, tri)]):
                return True
        return False

    for g in order:
        j = first[g]
        t = k[j]
        line = seg[t, 1] - seg[t, 0]
        line /= max(np.linalg.norm(line), 1e-12)
        if surface_seen(pts[j], line, ia[t], bvh_a) and surface_seen(pts[j], line, ib[t], bvh_b):
            seen += float(weight[g])
            where = pts[j] if where is None else where
            if seen > MIN_VISIBLE:
                break
    return seen, where


def check_intersections(sc):
    """Visible solids penetrating each other by more than 0.1 (cove families into the wall/ceiling shell up to 0.75;
    floor slabs are exempt targets, G4). A penetrating pair counts only when its intersection line is seen from
    reachable space for more than MIN_VISIBLE stud, after dropping tangent junctions (a fillet meeting its wall or
    ceiling) and square junctions with a support surface (a deck end butting into a wall, a column through a deck).
    Faces hidden inside walls, floors and ceilings never reach the count: no reachable ray sees them."""
    obs = [oid for oid, ob in enumerate(sc.objects) if "tris" in ob]
    lo = np.array([sc.objects[o]["lo"] for o in obs])
    hi = np.array([sc.objects[o]["hi"] for o in obs])
    first = [sc.objects[o]["parts"][0]["name"] for o in obs]
    shell = np.array([bool(SHELL.search(n)) for n in first])
    floor = np.array([bool(FLOOR.search(n)) and not sc.objects[o]["component"] for n, o in zip(first, obs)])
    cove = np.array([bool(COVE_ANY.match(sc.objects[o]["component"] or "")) for o in obs])
    support = {o: bool(SUPPORT.search(n)) or bool(SUPPORT_COMPONENT.match(sc.objects[o]["component"] or ""))
               for n, o in zip(first, obs)}
    rng = np.random.default_rng(sc.seed)
    samples = {}

    def pts_of(o):
        if o not in samples:
            t = sc.T[sc.owner == o]
            p, _, _, _ = ca.sample(t, rng, 1.0)
            p = np.concatenate((p, t.reshape(-1, 3)))
            samples[o] = p[rng.permutation(len(p))[:4000]]
        return samples[o]

    solid_bvh = {}

    def depth_in(target, pts):
        """Penetration depth of points inside the target's closed solid(s) (0 where outside)."""
        ob = sc.objects[target]
        best = np.zeros(len(pts))
        for part, t, mat, _ in ob["vis"]:
            if part.get("fixtureKind") == "mesh":
                if target not in solid_bvh:
                    tt = sc.T[sc.owner == target]
                    solid_bvh[target] = sc._bvh(tt) if closed_mesh(tt) else None
                bvh = solid_bvh[target]
                if bvh is None:
                    continue
                for i, p in enumerate(pts):
                    v = Vector(p)
                    hits, o = 0, v
                    for _ in range(32):
                        loc, _, _, dist = bvh.ray_cast(o, Vector((1, 0, 0)), 1000)
                        if loc is None:
                            break
                        hits += 1
                        o = loc + Vector((1e-4, 0, 0))
                    if hits % 2:
                        best[i] = max(best[i], bvh.find_nearest(v)[3])
                continue
            c, r = wc.frame(part["cframe"])
            e = np.asarray(part["size"]) / 2
            q = (pts - c) @ r
            if "Cylinder" in str(part["shape"]):
                rad = min(e[0], e[2])
                d = np.minimum(rad - np.hypot(q[:, 0], q[:, 2]), e[1] - np.abs(q[:, 1]))
            else:
                d = (e - np.abs(q)).min(1)
            best = np.maximum(best, np.maximum(d, 0))
        return best

    surfaces = {}

    def surface(oid, mesh_only=False):
        if (oid, mesh_only) not in surfaces:
            sel = np.nonzero((sc.owner == oid) & (sc.is_mesh if mesh_only else True))[0]
            surfaces[(oid, mesh_only)] = (sel, sc._bvh(sc.T[sel]) if len(sel) else None)
        return surfaces[(oid, mesh_only)]

    def assembly(o):
        m = ASSEMBLY.search(sc.objects[o]["path"] or "")
        return m.groups() if m else None

    penetrating = {}

    def note(x, y, depth, pos):
        if assembly(x) is not None and assembly(x) == assembly(y):
            return
        rec = penetrating.setdefault((min(x, y), max(x, y)), {"depth": 0.0, "into": (x, y)})
        if depth > rec["depth"]:
            rec.update(depth=float(depth), into=(x, y))

    order = np.argsort(lo[:, 0])
    for a_i in range(len(obs)):
        ia = order[a_i]
        for b_i in range(a_i + 1, len(obs)):
            ib = order[b_i]
            if lo[ib, 0] > hi[ia, 0] - .1:
                break
            if np.any(lo[ib] > hi[ia] - .1) or np.any(lo[ia] > hi[ib] - .1):
                continue
            if shell[ia] and shell[ib]:
                continue
            # Two open MeshPart skins have no inside volume, yet can still cut
            # through each other. BVH triangle crossings cover that case.
            sa, ba = surface(obs[ia], True)
            sb, bb = surface(obs[ib], True)
            if ba is not None and bb is not None:
                for ai, bi in ba.overlap(bb):
                    a, b = sc.T[sa[ai]], sc.T[sb[bi]]
                    da, db = (b - a[0]) @ sc.N[sa[ai]], (a - b[0]) @ sc.N[sb[bi]]
                    depth = min(da.max(), -da.min(), db.max(), -db.min())
                    if depth > .1:
                        note(obs[ia], obs[ib], depth, (a.mean(0) + b.mean(0)) / 2)
                        break
            for x, y in ((ia, ib), (ib, ia)):
                if floor[y] or (shell[x] and not cove[y]):
                    continue                        # floor slabs are exempt targets (G4); shell into props is judged the other way
                limit = .75 if cove[x] and shell[y] else .1
                p = pts_of(obs[x])
                inb = np.all((p >= lo[y] + limit) & (p <= hi[y] - limit), axis=1)
                if not inb.any():
                    continue
                d = depth_in(obs[y], p[inb])
                k = int(np.argmax(d))
                if d[k] > limit:
                    note(obs[x], obs[y], d[k], p[inb][k])
    groups = defaultdict(lambda: {"count": 0, "maxDepth": 0.0, "visibleLine": 0.0, "example": None})
    unseen = 0
    for (oa, ob_), rec in penetrating.items():
        seen, where = visible_intersection(sc, surface, oa, ob_,
                                           support[oa] or support[ob_] or door_in_own_tube(sc, oa, ob_), rng)
        if seen <= MIN_VISIBLE:
            unseen += 1
            continue
        x, y = rec["into"]
        A, B = sc.objects[x], sc.objects[y]
        g = groups[(A["label"], B["label"])]
        g["count"] += 1
        if seen > g["visibleLine"]:
            g["visibleLine"], g["maxDepth"] = round(seen, 2), round(rec["depth"], 2)
            g["example"] = ex(where, A, into=B["label"], intoPath=B["path"], depth=g["maxDepth"],
                              visibleLine=g["visibleLine"])
    # An exit inlay can be hidden behind a convex corner without the two open
    # skins physically crossing. Probe it from the hall side and name the cove
    # that blocks it; the corrected collar and inlay must remain clear.
    obscured = []
    exit_occluders = []
    rng = np.random.default_rng(sc.seed + 1)
    for ob in sc.objects:
        if not (ob["component"] or "").startswith(("ExitMouth", "ExitCollar")) or "tris" not in ob or not ob["hall"]:
            continue
        h = ob["hall"]
        centre = ob["tris"].reshape(-1, 3).mean(0)
        side = sc.nearest_side(h, centre)
        inward = np.array({"North": (0, 0, 1), "South": (0, 0, -1),
                           "West": (1, 0, 0), "East": (-1, 0, 0)}[side], float)
        origin = centre + inward * 15
        pts, _, _, _ = ca.sample(ob["tris"], rng, .25)
        pts = pts[:500]
        hidden = defaultdict(list)
        blockers = defaultdict(int)
        for p in pts:
            ray = Vector(p - origin)
            distance = ray.length
            if distance < .1:
                continue
            _, _, ti, hit_distance = sc.bvh.ray_cast(Vector(origin), ray.normalized(), distance - .1)
            if ti is None:
                continue
            blocker = sc.objects[sc.owner[ti]]
            if blocker["key"] != ob["key"]:
                blockers[blocker["label"]] += 1
            if COVE_ANY.match(blocker["component"] or ""):
                hidden[blocker["label"]].append(p)
        if blockers:
            exit_occluders.append({"component": ob["component"], "path": ob["path"],
                                   "testedSamples": len(pts), "blockers": dict(sorted(blockers.items(),
                                                                               key=lambda kv: -kv[1])[:8])})
        if hidden and sum(map(len, hidden.values())) > .02 * max(1, len(pts)):
            name, positions = max(hidden.items(), key=lambda kv: len(kv[1]))
            obscured.append(ex(positions[0], ob, into=name, issue="exit trim hidden behind cove",
                               hiddenSamples=sum(map(len, hidden.values())), testedSamples=len(pts)))
    rows = sorted(({"pair": f"{a} in {b}", **v} for (a, b), v in groups.items()), key=lambda r: -r["count"])
    examples = [r["example"] | {"pair": r["pair"], "objectPairs": r["count"]} for r in rows]
    notable = [e for e in examples[12:] if any(k in e["pair"] for k in ("Exit", "Tube", "Mouth"))][:24]
    return result(not (rows or obscured), sum(r["count"] for r in rows) + len(obscured),
                  obscured + examples, groups=len(rows), notable=notable, obscuredExitTrim=obscured,
                  exitTrimOccluders=exit_occluders, penetratingObjectPairs=len(penetrating), unseenObjectPairs=unseen,
                  table=[{"pair": r["pair"], "objectPairs": r["count"], "visibleLine": r["visibleLine"],
                          "depth": r["maxDepth"], "pos": r["example"]["pos"]} for r in rows])


# ----------------------------------------------------------------------------------------------- 8 z-fight

def tri_overlap_poly(a, b):
    """Intersection polygon of two 2-D triangles (Sutherland-Hodgman); [] when they do not overlap."""
    def clip(poly, p, q):
        out = []
        n = len(poly)
        for i in range(n):
            cur, prv = poly[i], poly[i - 1]
            ci = (q[0] - p[0]) * (cur[1] - p[1]) - (q[1] - p[1]) * (cur[0] - p[0])
            pi = (q[0] - p[0]) * (prv[1] - p[1]) - (q[1] - p[1]) * (prv[0] - p[0])
            if ci >= 0:
                if pi < 0:
                    out.append(inter(prv, cur, p, q))
                out.append(cur)
            elif pi >= 0:
                out.append(inter(prv, cur, p, q))
        return out

    def inter(s, e, p, q):
        dc = (s[0] - e[0], s[1] - e[1])
        dp = (p[0] - q[0], p[1] - q[1])
        n1 = s[0] * e[1] - s[1] * e[0]
        n2 = p[0] * q[1] - p[1] * q[0]
        den = dc[0] * dp[1] - dc[1] * dp[0]
        if abs(den) < 1e-12:
            return e
        return ((n1 * dp[0] - n2 * dc[0]) / den, (n1 * dp[1] - n2 * dc[1]) / den)

    def ccw(t):
        t = [tuple(x) for x in t]
        s = (t[1][0] - t[0][0]) * (t[2][1] - t[0][1]) - (t[1][1] - t[0][1]) * (t[2][0] - t[0][0])
        return t if s > 0 else t[::-1]

    poly = ccw(a)
    b = ccw(b)
    for i in range(3):
        poly = clip(poly, b[i - 1], b[i])
        if not poly:
            return []
    return poly


def check_zfight(sc, tol=.005, min_area=MIN_VISIBLE):
    """Coplanar (within tol) overlapping visible faces of two different objects. A pair counts when more than
    min_area stud^2 of the overlap is seen from reachable space on a side where BOTH faces render (a Part renders
    outward only, a MeshPart both ways). Two Parts facing opposite ways at the same plane are an authored butt joint
    (their contact patch renders on no side); faces hidden inside walls, floors and ceilings are never seen."""
    big = sc.area > 1e-3
    idx = np.nonzero(big)[0]
    n = sc.N[idx].copy()
    sign = np.sign(n[np.arange(len(n)), np.argmax(np.abs(n), 1)])
    n *= sign[:, None]
    d = (sc.T[idx, 0] * n).sum(1)
    key_n = np.round(n * 50).astype(int)
    key_d = np.floor(d / .05).astype(int)
    buckets = defaultdict(list)
    for j, (kn, kd) in enumerate(zip(map(tuple, key_n), key_d)):
        buckets[(kn, kd)].append(j)
    pairs = defaultdict(lambda: {"area": 0.0, "polys": []})
    near_band = butt = 0
    seen = set()
    for (kn, kd), members in buckets.items():
        cand = list(members)
        cand2 = buckets.get((kn, kd + 1), [])
        if len(set(sc.owner[idx[cand + cand2]])) < 2:
            continue
        pool = cand + cand2
        P = np.array(pool)
        tri = sc.T[idx[P]]
        nn = n[P[0]]
        u = np.cross(nn, (1, 0, 0) if abs(nn[0]) < .9 else (0, 1, 0))
        u /= np.linalg.norm(u)
        v = np.cross(nn, u)
        uv = np.stack(((tri @ u), (tri @ v)), -1)
        blo, bhi = uv.min(1), uv.max(1)
        own = sc.owner[idx[P]]
        for i in range(len(members)):
            ok = (own != own[i]) & np.all(blo < bhi[i] - 1e-3, 1) & np.all(bhi > blo[i] + 1e-3, 1) & \
                 (np.abs(d[P] - d[P[i]]) <= .05)
            for j in np.nonzero(ok)[0]:
                a_, b_ = idx[P[i]], idx[P[j]]
                if (b_, a_) in seen:
                    continue
                seen.add((a_, b_))
                # Coplanar = the two planes within tol over the overlap polygon (GB, 2026-10-05). Comparing the
                # offsets d from the world origin reported a basin floor tilted 0.21 deg whose plane, extrapolated
                # 336 studs to x = 0, passed 0.004 from the thresholds' y = 0, while the faces were 0.8..1.6 apart.
                poly = tri_overlap_poly(uv[i], uv[j])
                if len(poly) < 3:
                    continue
                q = np.asarray(poly)
                X = q[:, :1] * u + q[:, 1:] * v                    # overlap vertices in the bucket plane (offset 0)
                ni, nj = n[P[i]], n[P[j]]
                si = (tri[i, 0] @ ni - X @ ni) / (ni @ nn)         # each face's offset along nn at those vertices
                sj = (tri[j, 0] @ nj - X @ nj) / (nj @ nn)
                gap = float(np.abs(si - sj).max())
                if gap > tol:
                    near_band += 1
                    continue
                oa_, ob2 = sc.outward(a_), sc.outward(b_)
                if oa_ is not None and ob2 is not None and oa_ @ ob2 < -.5:
                    butt += 1                       # two closed solids touching face to face: a contact patch
                    continue
                # sides (+1/-1 along nn) on which both faces render
                sides = [s for s in (1, -1) if all(any(r @ (s * nn) > .5 for r in render_sides(sc, t)) for t in (a_, b_))]
                if not sides:                       # a Part's outward face against the other's back: nothing renders
                    butt += 1
                    continue
                area = .5 * abs(np.dot(q[:, 0], np.roll(q[:, 1], 1)) - np.dot(q[:, 1], np.roll(q[:, 0], 1)))
                if area < 1e-3:
                    continue
                cen = q.mean(0)                     # interior point of the convex overlap polygon
                plane = float((si.mean() + sj.mean()) / 2)      # both faces' offset at cen (linear: vertex mean)
                g = pairs[(min(sc.owner[a_], sc.owner[b_]), max(sc.owner[a_], sc.owner[b_]))]
                g["area"] += area
                g["polys"].append((area, cen[0] * u + cen[1] * v + plane * nn, [s * nn for s in sides]))
    groups = defaultdict(lambda: {"count": 0, "area": 0.0, "visibleArea": 0.0, "example": None})
    unseen = 0
    for (oa, ob_), g in pairs.items():
        if g["area"] <= min_area:
            continue
        vis, where = 0.0, None                      # lower bound: areas of overlap polygons whose centre is seen
        for area, p, sides in sorted(g["polys"], key=lambda e: -e[0])[:3 * SIGHT_POINTS]:
            if all(sc.solids.inside((p + s * .03)[None])[0] for s in sides):
                continue                            # buried in an opaque Part on every rendering side
            if sc.sight.visible(p, [(s,) for s in sides], offset=.01):
                vis += area
                where = p if where is None else where
                if vis > min_area:
                    break
        if vis <= min_area:
            unseen += 1
            continue
        A, B = sc.objects[oa], sc.objects[ob_]
        k = tuple(sorted((A["label"], B["label"])))
        r = groups[k]
        r["count"] += 1
        r["area"] += g["area"]
        if vis > r["visibleArea"]:
            r["visibleArea"] = round(vis, 2)
            r["example"] = ex(where, A, other=B["label"], otherPath=B["path"], overlapArea=round(g["area"], 2),
                              visibleArea=r["visibleArea"])
    rows = sorted(({"pair": " / ".join(k), **v} for k, v in groups.items()), key=lambda r: -r["area"])
    examples = [r["example"] | {"pair": r["pair"], "objectPairs": r["count"], "area": round(r["area"], 1)}
                for r in rows]
    notable = [e for e in examples[12:] if any(k in e["pair"] for k in ("Exit", "Tube", "Mouth"))][:24]
    return result(not rows, sum(r["count"] for r in rows), examples, groups=len(rows), notable=notable,
                  coplanarObjectPairs=len(pairs), unseenObjectPairs=unseen, buttJointTrianglePairs=butt,
                  nearCoplanarPairs_0p005_0p05=near_band,
                  table=[{"pair": r["pair"], "objectPairs": r["count"], "area": round(r["area"], 1),
                          "visibleArea": r["visibleArea"], "pos": r["example"]["pos"]} for r in rows])


# ----------------------------------------------------------------------------------------------- 9, 10, 11

def check_stretch(sc):
    by = defaultdict(lambda: {"count": 0, "min": 9.0, "max": 0.0, "example": None})
    for p in sc.parts:
        if p.get("fixtureKind") != "mesh" or p["transparency"] >= .98:
            continue
        chunk = fixture_chunk(p, sc.chunks)
        mat = chunk["record"]["material"]
        if mat not in TILE_CHUNK_MATERIALS and not str(p.get("materialVariant", "")).startswith("PR Tile"):
            continue
        src = np.asarray(chunk["record"]["size"], float)
        f = np.asarray(p["size"], float) / np.where(src > .05, src, 1)
        f = np.where(src > .05, f, 1)
        if np.any((f < STRETCH[0] - STRETCH_EPS) | (f > STRETCH[1] + STRETCH_EPS)):
            b = by[p["fixtureComponent"]]
            b["count"] += 1
            b["min"], b["max"] = round(min(b["min"], f.min()), 3), round(max(b["max"], f.max()), 3)
            b["example"] = b["example"] or ex(p["cframe"][:3], None, component=p["fixtureComponent"], path=p["path"],
                                              scale=np.round(f, 3).tolist())
    rows = sorted(by.items(), key=lambda kv: -kv[1]["count"])
    return result(not rows, sum(v["count"] for _, v in rows),
                  [v["example"] | {"meshParts": v["count"], "range": [v["min"], v["max"]]} for _, v in rows])


def check_colour(sc):
    by = defaultdict(lambda: {"count": 0, "example": None})
    for p in sc.parts:
        if p["transparency"] >= .98:
            continue
        variant = str(p.get("materialVariant", ""))
        chunk_mat = p["name"].rsplit("_", 1)[-1] if p.get("fixtureKind") == "mesh" else None
        if not variant.startswith("PR Tile") and chunk_mat not in TILE_CHUNK_MATERIALS and \
                not TILED_PART_NAME.match(p["name"]):
            continue
        issues = []
        if variant not in TILE_VARIANTS:
            issues.append(f"variant {variant or '-'}")
        rgb = np.asarray(p["color"], float)
        if np.abs(rgb - TILE_RGB).max() > .6 / 255:
            issues.append("colour " + str(tuple(int(round(x * 255)) for x in rgb)))
        if "SmoothPlastic" not in str(p["material"]):
            issues.append(str(p["material"]))
        if abs(float(p.get("reflectance", 0)) - .06) > 1e-3:
            issues.append(f"reflectance {p.get('reflectance')}")
        if issues:
            lab = p.get("fixtureComponent") or re.sub(r"[\d.]+", "#", p["name"])
            k = (lab, "; ".join(issues))
            by[k]["count"] += 1
            by[k]["example"] = by[k]["example"] or ex(p["cframe"][:3], None, component=lab, path=p["path"])
    rows = sorted(by.items(), key=lambda kv: -kv[1]["count"])
    return result(not rows, sum(v["count"] for _, v in rows),
                  [v["example"] | {"issue": k[1], "parts": v["count"]} for k, v in rows])


DECOR_EDGE = .5         # documented overlap: a glow/dark plane may run up to 0.5 into the wall around its hole
DECOR_BURIED_MAX = .02  # (SunSlit's plane is 0.2 wider and 0.4 taller than its cut so no sliver of sky shows)


def buried_share(sc, t, wall_n):
    """Area share of a decor face (its faces looking along the wall normal, inset DECOR_EDGE from their outline)
    whose room side is inside an opaque Part."""
    n = np.cross(t[:, 1] - t[:, 0], t[:, 2] - t[:, 0])
    n /= np.maximum(np.linalg.norm(n, axis=1)[:, None], 1e-12)
    face = t[np.abs(n @ wall_n) > .9]
    if not len(face):
        return 0.0
    pts, w, _, _ = ca.sample(face, np.random.default_rng(0), 64.0)
    u = np.cross(wall_n, (0, 1, 0))
    a, b = pts @ u, pts[:, 1]
    keep = (a > a.min() + DECOR_EDGE) & (a < a.max() - DECOR_EDGE) & (b > b.min() + DECOR_EDGE) & (b < b.max() - DECOR_EDGE)
    if not keep.any():
        return 0.0
    front = pts[keep] + wall_n * .1
    return float(w[keep][sc.solids.inside(front)].sum() / w[keep].sum())


def check_decor(sc):
    bad = []
    tested = 0
    for ob in sc.objects:
        comp = ob["component"] or ""
        attrs = sc.manifest.get(comp, {}).get("attrs", {})
        if "tris" not in ob or ob["hall"] is None or not (ca.match(comp, DECOR) or attrs.get("WallDecor")):
            continue
        tested += 1
        h = ob["hall"]
        side = sc.nearest_side(h, ob["pivot"][:3])
        pts = ob["tris"].reshape(-1, 3)
        dw = sc.into_room(h, side, pts)
        issues = []
        k = int(np.argmax(dw))
        if dw[k] > .05:
            issues.append(f"protrudes {dw[k]:.2f} from the {side} wall face")
        wall_n = np.array({"North": (0, 0, 1), "South": (0, 0, -1), "West": (1, 0, 0), "East": (-1, 0, 0)}[side], float)
        for part, t, mat, _ in ob["vis"]:
            base = mat.replace("Material.", "")
            if base in GLOW or "Neon" in str(part["material"]):
                buried = buried_share(sc, t, wall_n)
                if buried > DECOR_BURIED_MAX:
                    issues.append(f"{base} face {buried:.0%} buried inside an opaque part")
                    break
        if issues:
            bad.append(ex(pts[k], ob, side=side, issue="; ".join(issues)))
    return result(not bad, len(bad), bad, tested=tested)


# ----------------------------------------------------------------------------------------------- 12 lattice

def check_lattice(sc):
    """Tile-grid seams: lattice_audit.audit_parts on this scene's world with its own thresholds and the dump's tile
    pitch. One row per category, its worst finding as the example (path = the owning object, for the crop)."""
    import lattice_audit as la                     # numpy only (no scipy in Blender's Python)
    stats = defaultdict(int)
    tile = la.tile_of(sc.world)
    findings = la.audit_parts(sc.parts, sc.world["layout"], sc.chunks, stats=stats, jobs=la.kit_jobs(sc.world),
                              tile=tile)
    object_path = {p["path"]: ob["path"] for ob in sc.objects for p in ob["parts"]}
    rows = []
    for cat, c in sorted(la.summarize(findings).items(), key=lambda kv: (-kv[1]["exposed"], kv[0])):
        worst = max((f for f in findings if f["category"] == cat), key=lambda f: (f["offset"], f["exposed"]))
        rows.append({"pair": cat, "findings": c["count"], "maxOffset": round(c["max"], 4),
                     "exposed": round(c["exposed"], 1), "owners": sorted(c["owners"]), "kinds": dict(c["kinds"]),
                     "flags": dict(c["flags"]), "pos": worst["at"],
                     "example": ex(worst["at"], None, path=object_path.get(worst["a"]["path"], worst["a"]["path"]),
                                   pair=cat, kind=worst["kind"], offset=worst["offset"], along=worst["along"],
                                   across=worst["across"], exposed=worst["exposed"], normal=worst["normal"],
                                   a=worst["a"]["name"], b=worst["b"]["name"], hall=worst["hall"])})
    return result(not findings, len(findings), [r.pop("example") for r in rows], tile=tile, stats=dict(stats),
                  groups=len(rows), table=rows)


# ----------------------------------------------------------------------------------------------- crops

def render_crops(sc, report, per_check, out_dir):
    """Workbench crops of the first examples of failing checks, backface culling on (wrong-facing faces show)."""
    scene = bpy.context.scene
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.show_backface_culling = True
    scene.render.resolution_x, scene.render.resolution_y = 800, 450
    scene.render.image_settings.file_format = "PNG"
    world = bpy.data.worlds.new("sky")
    world.color = (.55, .7, .95)
    scene.world = world
    B = np.array(((1, 0, 0), (0, 0, -1), (0, 1, 0)), float) * .28
    mats = {}

    def mat(name, rgb):
        if name not in mats:
            m = bpy.data.materials.new(name)
            m.diffuse_color = (*rgb, 1)
            m.use_backface_culling = True
            mats[name] = m
        return mats[name]

    cam_data = bpy.data.cameras.new("cam")
    cam_data.lens = 18
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    files = []
    centres = sc.T.mean(1)
    for name, chk in report["checks"].items():
        if chk.get("passed", True):
            continue
        for i, e in enumerate(chk["examples"][:per_check]):
            p = np.asarray(e["pos"], float)
            sel = np.nonzero(np.linalg.norm(centres - p, axis=1) < (40 if name.endswith("ceiling") else 28))[0]
            if not len(sel):
                continue
            targets = [j for j, ob in enumerate(sc.objects) if ob["path"] == e.get("path")]
            objs = []
            for flag, rgb in (("target", (1.0, .34, .12)), ("mesh", (.85, .82, .7)),
                              ("part", (.65, .67, .67))):
                target = np.isin(sc.owner[sel], targets)
                use = target if flag == "target" else (sc.is_mesh[sel] & ~target if flag == "mesh"
                                                      else ~sc.is_mesh[sel] & ~target)
                s = sel[use]
                if not len(s):
                    continue
                t = sc.T[s]
                if flag == "part":                 # part_triangles winding is inward: flip for culling
                    t = t[:, ::-1]
                verts = (t.reshape(-1, 3) @ B.T).tolist()
                me = bpy.data.meshes.new(f"crop{flag}")
                me.from_pydata(verts, [], np.arange(len(verts)).reshape(-1, 3).tolist())
                me.materials.append(mat(f"m{flag}", rgb))
                ob = bpy.data.objects.new(me.name, me)
                scene.collection.objects.link(ob)
                objs.append(ob)
            h = sc._hall_at(p, p)
            if name.endswith("lattice") and e.get("normal"):
                n = np.asarray(e["normal"], float)                  # face the seam: 7 studs off its surface
                side = np.cross(n, (0, 1, 0) if abs(n[1]) < .9 else (1, 0, 0))
                eye = p + n * 7 + side / max(np.linalg.norm(side), 1e-9) * 2
                cam_data.lens = 30
            elif h:
                side = sc.nearest_side(h, p)
                inward = {"North": (0, 0, 1), "South": (0, 0, -1),
                          "West": (1, 0, 0), "East": (-1, 0, 0)}[side]
                if name.endswith("ceiling"):
                    eye = p + np.array((14, -min(30, p[1] - h["FloorY"] - 5), 10))
                    cam_data.lens = 22
                elif name.endswith("coves"):
                    along = (0, 0, 12) if side in ("West", "East") else (12, 0, 0)
                    eye = p + np.asarray(inward) * 20 + np.asarray(along) + np.array((0, -18, 0))
                    cam_data.lens = 24
                else:
                    eye = p + np.asarray(inward) * 22
                    cam_data.lens = 35
            else:
                eye = p + np.array((18, 4, 14))
                cam_data.lens = 30
            cam.location = Vector(eye @ B.T)
            cam.rotation_euler = (Vector(p @ B.T) - cam.location).to_track_quat("-Z", "Y").to_euler()
            target = out_dir / f"world_audit_{sc.seed}_{name}_{i + 1}.png"
            scene.render.filepath = str(target)
            bpy.ops.render.render(write_still=True)
            files.append(str(target))
            e["crop"] = str(target)
            for ob in objs:
                me = ob.data
                bpy.data.objects.remove(ob, do_unlink=True)
                bpy.data.meshes.remove(me)
    return files


# ----------------------------------------------------------------------------------------------- driver

CHECKS = {
    1: ("leaks", lambda sc, ops: check_leaks(sc, ops)),
    2: ("ceiling", lambda sc, ops: check_ceiling(sc, ops)),
    3: ("jumpreach", lambda sc, ops: check_jump(sc, ops)),
    4: ("floating", lambda sc, ops: check_floating(sc)),
    5: ("water", lambda sc, ops: check_water(sc)),
    6: ("coves", lambda sc, ops: check_coves(sc)),
    7: ("intersect", lambda sc, ops: check_intersections(sc)),
    8: ("zfight", lambda sc, ops: check_zfight(sc)),
    9: ("stretch", lambda sc, ops: check_stretch(sc)),
    10: ("colour", lambda sc, ops: check_colour(sc)),
    11: ("decor", lambda sc, ops: check_decor(sc)),
    12: ("lattice", lambda sc, ops: check_lattice(sc)),
}


def audit(path, only, out, crops):
    t0 = time.time()
    sc = Scene(path)
    ops = openings(sc)
    log(f"OPENINGS {len(ops)}: " + ", ".join(sorted({o['label'] for o in ops})))
    report = {"seed": sc.seed, "dump": str(path), "builderSha256": sc.world.get("builderSha256"), "checks": {}}
    for n in only:
        name, fn = CHECKS[n]
        t = time.time()
        r = fn(sc, ops)
        r["seconds"] = round(time.time() - t, 1)
        report["checks"][f"{n:02d}_{name}"] = r
        log(f"  {'pass' if r['passed'] else 'FAIL'} {n:2d} {name:10s} count={r['count']:6d}  ({r['seconds']} s)  " +
            ("" if r["passed"] else json.dumps(r["examples"][0], default=str)[:260]))
    report["passed"] = all(r["passed"] for r in report["checks"].values())
    if crops:
        report["crops"] = render_crops(sc, report, crops, out)
    report["seconds"] = round(time.time() - t0, 1)
    target = out / f"world_audit_{sc.seed}.json"
    target.write_text(json.dumps(report, indent=1, default=str), encoding="utf-8")
    log(f"WORLD_AUDIT {sc.seed} {'PASS' if report['passed'] else 'FAIL'} "
        f"failing={[k for k, v in report['checks'].items() if not v['passed']]} time={report['seconds']}s -> {target}")
    return report["passed"]


def main():
    assert bpy.app.background, "run in headless Blender (-b)"
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("dumps", nargs="*", type=Path)
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT)
    ap.add_argument("--only", default="", help="comma-separated check numbers (default all)")
    ap.add_argument("--crops", type=int, default=0, help="render N example crops per failing check")
    args = ap.parse_args(argv)
    only = [int(x) for x in args.only.split(",") if x] or sorted(CHECKS)
    args.out.mkdir(parents=True, exist_ok=True)
    ok = True
    for path in args.dumps or ca.DEFAULT_DUMPS:
        ok = audit(path, only, args.out, args.crops) and ok
    if not ok:
        raise RuntimeError("Poolrooms world audit failed; inspect the JSON reports above")


if __name__ == "__main__":
    main()
