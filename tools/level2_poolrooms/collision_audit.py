"""Permanent collision-coverage audit for the Poolrooms kit and dumped worlds (ANALYSIS F12-PERM).

    python -B tools/level2_poolrooms/collision_audit.py                    # kit + the three dumps
    python -B tools/level2_poolrooms/collision_audit.py --no-world         # kit only (about 10 s)
    python -B tools/level2_poolrooms/collision_audit.py --kit DIR... G:/Blender/Level2_Poolrooms/worlds/world_1.json

Pure numpy + scipy, no Blender. Exit code 1 when any check fails. Reports: <out>/collision_kit.json and
<out>/collision_<seed>.json plus a text summary on stdout.

(A) KIT, over one or more kit export dirs (manifest.json + chunks/):
  A1 chain yaw: every oblique collider/collide-part in a numbered chain (same name stem) has one horizontal axis
     tangent to the chain (|dot| >= 0.999 against the neighbours' centre chord; end boxes >= 0.95). A mirrored
     yaw (Blender sign) rotates a box 2*alpha off its chord and fails here.
  A2 coverage: each component's solid chunk surface against its OWN colliders, placed with the importer's
     formula CFrame.new(x,y,z)*CFrame.Angles(0,rad(yaw),0) (12-number cf = full row-major CFrame). Unbacked =
     farther than 0.6 from every own collider. Share <= 0.005 (RoundTunnel/Pipe/Chamber), <= 0.02 otherwise,
     max gap <= 1.0 (<= 0.6 for coves), and as-authored may not be worse than yaw-negated by more than 0.02.
     Cove families (Cove*, CornerCove*, or any component with attr ExposedSide) are sampled only on the faces
     that see the room, and are also backed by the wall/floor planes they are authored against (attrs WallSide/
     WallPlane/Radius, TangentX/TangentZ markers, CornerRadius/FilletRadius).
  A3 allowlist: a component with solid chunks and no colliders fails unless KIT_ALLOW lists it as passable,
     unreachable or backed elsewhere. 'unplaced' entries stop applying as soon as a given dump places them.
(B) BUILDER, per dump: every manifest collider and collide part of every placement survives cloning as a
  CanCollide BasePart (except SocketPlug records), no builder 'Seal' stand-in colliders exist, and every hall
  placement's visual AABB stays inside its hall rectangle + 2 studs (corridor/exit pieces exempt). A lost record
  is accepted only by an explicit rule (BUILDER_RENAMES; a covering 'Level 2 Run ...' collider; a box entirely
  above the ceiling plane; a top-cove fill (CoveTop*, 'Swerve Top Cove Fill') above C - 4), and the accepted counts are reported.
(C) WORLD, per dump: visible non-colliding surfaces sampled at 2/stud^2; backed = a CanCollide part within 0.6;
  reachable = touched by a player flooded from ElevatorSpawn with pressure doors open. PASS per seed:
  C1 every MUST-COLLIDE label: unbacked reachable share <= 0.02;  C2 reachable area with gap > 1.0 <= 1 stud^2
  per label;  C3 sum unbacked / sum reachable <= 0.005;  C4 invisible collision (an invisible collider's face, exposed,
  reachable with a tight body from the feet voxel to one above the head, no visual within 1.0): per collider
  label share <= 0.05 and area <= 50, seed total <= 300 (slide-template hulls and roof/sky caps exempt);  C5 DrainHole plates within 0.3 of the floor collider and
  LightRound tops within 0.3 of the ceiling plane.
"""
from __future__ import annotations

import argparse
import base64
import bisect
from collections import Counter, defaultdict
import fnmatch
import hashlib
import json
import math
from pathlib import Path
import re
import sys
import time
import types

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
try:                                    # inside Blender (world_audit.py) the real modules exist
    import bpy  # noqa: F401
except ImportError:                     # world_check imports bpy/mathutils at module level; only numpy helpers are used
    for _name in ("bpy", "mathutils", "mathutils.bvhtree"):
        sys.modules.setdefault(_name, types.ModuleType(_name))
    sys.modules["mathutils"].Vector = object
    sys.modules["mathutils.bvhtree"].BVHTree = object
import world_check as wc  # noqa: E402
from render_world import fixture_chunk, load_kit_chunks, mesh_triangles_world  # noqa: E402

WORLDS = Path("G:/Blender/Level2_Poolrooms/worlds")
DEFAULT_DUMPS = [WORLDS / f"world_{s}.json" for s in (837834, 1, 101)]
JOBS = Path("G:/Blender/Level2_Poolrooms/jobs")
DEFAULT_OUT = Path("G:/Roblox/_local/l2fix/impl/WP5/audit")

TOL = 0.6            # backed when a collider is this close
GAP = 1.0            # a gap this large is a walk-through
PAD = 3.0            # collider grid padding: distances up to PAD are exact, beyond are inf
DENSITY = 2.0        # samples per square stud

PASSABLE_MATERIALS = {"LightWarm", "Void", "Neon", "Glass", "Water"}
PASSABLE_COMPONENTS = ("LightRound", "DrainHole", "SunSlit", "ExitTubeVisual*")
PASSABLE_PARTS = ("Overhead Tile", "Pump Status Lamp", "Pressure Door Stripe", "Pump Pressure Gauge Needle",
                  "Pump Lever Status Ring", "Pump Lever grip", "Pump Lever Grip",
                  "Pump Lever Colored Plastic Grip")      # the builder's name for the animated lever grip
INVISIBLE_OK = ("Roof Collider", "Sky Cap")          # deliberate roof/sky caps (G6)
SEAL = re.compile(r"\bSeal\b")

# A3: solid components that may ship without colliders. kind: passable | unreachable | backed | unplaced | template
KIT_ALLOW = {
    "LightRound": ("passable", "flush ceiling trim"),
    "DrainHole": ("passable", "flush floor decal"),
    "SunSlit": ("passable", "glow plane inside a wall hole"),
    "WallVoid": ("passable", "dark back plate inside the wall slab"),
    "PumpLever": ("passable", "animated lever (prompt target)"),
    "PumpNeedle": ("passable", "animated gauge needle"),
    "PumpLamp": ("passable", "status lamp"),
    "ExitTubeVisual*": ("backed", "SlideCol bore collision, judged by the exit bore/ride tests"),
    "ExitMouth*": ("backed", "inlay on the exit collar / hall wall"),
    "ArrivalDoor": ("backed", "story-gate door on the arrival wall face"),
    "ExitSkylight": ("unreachable", "ceiling opening (retired by LightWell_R14)"),
    "VaultBay32_*": ("unreachable", "vault above head height"),
    "Porthole_*": ("unplaced", "not placed by the builder"),
    "SlideCol_*": ("template", "collision template, no visual"),
    # Seated chamber fillets (R1.2, R1.5 under LATTICE_SPEC C13): the wall and floor parts back them within 0.35
    # (R1.2, ANALYSIS F12-F) / 0.44 (R1.5) of TOL 0.6. The world audit (C) still judges them where reachable.
    "ChamberSocketCove": ("backed", "seated chamber fillet against the chamber wall and floor"),
    "ChamberSocketStops": ("backed", "seated chamber fillet stops against the chamber wall and floor"),
}
STRICT_FAMILIES = ("RoundTunnel*", "Pipe*", "Chamber_*")
COVE_FAMILIES = ("Cove*", "CornerCove*")
CORNER_PIECE = re.compile(r"^Cove(Base|Top)Corner|^CornerCove|InnerCorner")
CHORD_X = ("Corner Block*", "Wall Block*", "Deck Ground*", "Collar Block*", "Step * Ground*")
BRIDGING = ("RoundTunnel*", "Pipe*", "Exit*", "SlideCol_*")


def match(name, patterns):
    return any(fnmatch.fnmatchcase(name, p) for p in patterns)


def allow_entry(name):
    return next((v for k, v in KIT_ALLOW.items() if fnmatch.fnmatchcase(name, k)), None)


# ----------------------------------------------------------------------------------------------- geometry basics

def ry(theta):
    """Roblox CFrame.Angles(0, theta, 0): local X -> (cos, 0, -sin)."""
    c, s = math.cos(theta), math.sin(theta)
    return np.array(((c, 0, s), (0, 1, 0), (-s, 0, c)))


def record_frame(cf, negate_yaw=False):
    """Importer formula for a kit record cf (3, 4 or 12 numbers) -> (position, rotation)."""
    if len(cf) == 12:
        return np.array(cf[:3], float), np.array(cf[3:], float).reshape(3, 3)
    yaw = cf[3] if len(cf) > 3 else 0.0
    if negate_yaw and oblique(yaw):
        yaw = -yaw
    return np.array(cf[:3], float), ry(math.radians(yaw))


def oblique(yaw):
    return abs(yaw / 90 - round(yaw / 90)) > 1e-6


def is_oblique_rotation(rot):
    return bool(np.any((np.abs(rot) > 1e-4) & (np.abs(rot) < 1 - 1e-4)))


def normalize_cylinder(part):
    """world_check, Colliders and the voxel grid use the fake engine's logical cylinder (axis = local Y, size
    (d, h, d)). Roblox's native cylinder (the importer's nativeCylinder: axis = local X, size (h, d, d), rotated
    90 deg about Z) is converted back, so the audit works on either kind of dump (G9)."""
    if "Cylinder" not in str(part["shape"]):
        return part
    s = np.asarray(part["size"], float)
    rot = np.asarray(part["cframe"][3:], float).reshape(3, 3)
    native = abs(s[1] - s[2]) < 1e-6 and abs(s[0] - s[2]) > 1e-6
    if abs(s[0] - s[1]) < 1e-6 and abs(s[1] - s[2]) < 1e-6:      # all equal: take the vertical axis
        native = abs(rot[1, 0]) > abs(rot[1, 1])
    if not native:
        return part
    rz = np.array(((0, -1, 0), (1, 0, 0), (0, 0, 1)), float)       # Angles(0,0,90deg): local X -> Y
    q = dict(part)
    q["size"] = [s[1], s[0], s[2]]
    q["cframe"] = list(part["cframe"][:3]) + list((rot @ rz.T).reshape(-1))
    return q


def normalize_world(world):
    world["parts"] = [normalize_cylinder(p) for p in world["parts"]]
    return world


def load_world(path):
    return normalize_world(json.loads(Path(path).read_text(encoding="utf-8")))


def sample(tri, rng, density=DENSITY):
    """Area-weighted random points on triangles (n, 3, 3) -> points, weights, unit normals, triangle index."""
    tri = np.asarray(tri, dtype=np.float64)
    if len(tri) == 0:
        return np.zeros((0, 3)), np.zeros(0), np.zeros((0, 3)), np.zeros(0, int)
    a, b, c = tri[:, 0], tri[:, 1], tri[:, 2]
    cross = np.cross(b - a, c - a)
    area = .5 * np.linalg.norm(cross, axis=1)
    normal = cross / np.maximum(2 * area, 1e-12)[:, None]
    n = np.maximum(1, np.ceil(area * density)).astype(int)
    idx = np.repeat(np.arange(len(tri)), n)
    u, v = rng.random(len(idx)), rng.random(len(idx))
    flip = u + v > 1
    u[flip], v[flip] = 1 - u[flip], 1 - v[flip]
    pts = a[idx] + u[:, None] * (b - a)[idx] + v[:, None] * (c - a)[idx]
    return pts, (area / n)[idx], normal[idx], idx


class Colliders:
    """Exact distance from points to the union of box / logical-Y cylinder parts (slide-template hulls use
    world_check's nominal radius-8 annulus). Uniform 4-stud hash grid; distances beyond `pad` are inf."""
    CELL = 4.0

    def __init__(self, parts, pad=PAD):
        cs = list(parts)
        self.parts = cs
        n = len(cs)
        self.c = np.array([p["cframe"][:3] for p in cs], dtype=np.float64).reshape(n, 3)
        self.R = np.array([np.asarray(p["cframe"][3:], float).reshape(3, 3) for p in cs]).reshape(n, 3, 3)
        self.size = np.array([p["size"] for p in cs], dtype=np.float64).reshape(n, 3)
        self.e = self.size / 2
        self.kind = np.array([2 if p.get("fixtureKind") == "slide-template" else
                              1 if "Cylinder" in str(p.get("shape")) else 0 for p in cs], dtype=int)
        ext = np.einsum("nij,nj->ni", np.abs(self.R), self.e) + pad
        lo = np.floor((self.c - ext) / self.CELL).astype(np.int64)
        hi = np.floor((self.c + ext) / self.CELL).astype(np.int64)
        keys, ids = [np.zeros(0, np.int64)], [np.zeros(0, np.int64)]
        for i in range(n):
            g = np.stack(np.meshgrid(*[np.arange(lo[i, k], hi[i, k] + 1) for k in range(3)],
                                     indexing="ij"), -1).reshape(-1, 3)
            keys.append(self.key(g))
            ids.append(np.full(len(g), i))
        keys, ids = np.concatenate(keys), np.concatenate(ids)
        order = np.argsort(keys, kind="stable")
        self.keys, self.ids = keys[order], ids[order]

    @staticmethod
    def key(g):
        g = g + 4096
        return (g[:, 0] << 26) | (g[:, 1] << 13) | g[:, 2]

    def distance(self, pts, want_id=False):
        pts = np.asarray(pts, dtype=np.float64).reshape(-1, 3)
        out = np.full(len(pts), np.inf)
        nearest = np.full(len(pts), -1)
        for s in range(0, len(pts), 200000):
            p = pts[s:s + 200000]
            k = self.key(np.floor(p / self.CELL).astype(np.int64))
            a = np.searchsorted(self.keys, k, "left")
            b = np.searchsorted(self.keys, k, "right")
            cnt = b - a
            if cnt.sum() == 0:
                continue
            pi = np.repeat(np.arange(len(p)), cnt)
            start = np.repeat(a, cnt)
            offs = np.arange(len(pi)) - np.repeat(np.cumsum(cnt) - cnt, cnt)
            ci = self.ids[start + offs]
            q = np.einsum("nj,nji->ni", p[pi] - self.c[ci], self.R[ci])
            e, kind, size = self.e[ci], self.kind[ci], self.size[ci]
            d = np.linalg.norm(np.maximum(np.abs(q) - e, 0), axis=1)
            cyl = kind == 1
            if cyl.any():
                qc, ec = q[cyl], e[cyl]
                r = np.sqrt((qc[:, 0] / ec[:, 0]) ** 2 + (qc[:, 2] / ec[:, 2]) ** 2)
                dr = np.maximum(r - 1, 0) * np.minimum(ec[:, 0], ec[:, 2])
                dy = np.maximum(np.abs(qc[:, 1]) - ec[:, 1], 0)
                d[cyl] = np.hypot(dr, dy)
            sl = kind == 2
            if sl.any():
                qs, ss = q[sl], size[sl]
                rn = np.hypot(qs[:, 0] / np.maximum(ss[:, 0], .1) * 16, qs[:, 1] / np.maximum(ss[:, 1], .1) * 16)
                k_ = np.maximum(ss[:, 0], ss[:, 1]) / 16
                dr = np.maximum(np.maximum(6.8 - rn, rn - 8.25), 0) * k_
                dz = np.maximum(np.abs(qs[:, 2]) - ss[:, 2] / 2, 0)
                d[sl] = np.hypot(dr, dz)
            order = np.lexsort((d, pi))
            rows, first = np.unique(pi[order], return_index=True)
            idx = order[first]
            out[s + rows] = d[idx]
            nearest[s + rows] = ci[idx]
        return (out, nearest) if want_id else out

    def inside(self, pts):
        return self.distance(pts) <= 1e-9


def ray_hits(origins, dirs, tris, t_min=1e-3, t_max=60.0):
    """Vectorised Moller-Trumbore: True where the ray hits any triangle (both sides)."""
    hit = np.zeros(len(origins), bool)
    if len(tris) == 0:
        return hit
    v0, e1, e2 = tris[:, 0], tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0]
    step = max(1, 2_000_000 // max(1, len(tris)))
    for s in range(0, len(origins), step):
        o, d = origins[s:s + step, None, :], dirs[s:s + step, None, :]
        p = np.cross(d, e2[None])
        det = (e1[None] * p).sum(-1)
        ok = np.abs(det) > 1e-12
        inv = np.where(ok, 1 / np.where(ok, det, 1), 0)
        tv = o - v0[None]
        u = (tv * p).sum(-1) * inv
        q = np.cross(tv, e1[None])
        v = (d * q).sum(-1) * inv
        t = (e2[None] * q).sum(-1) * inv
        h = ok & (u >= 0) & (v >= 0) & (u + v <= 1) & (t > t_min) & (t < t_max)
        hit[s:s + step] = h.any(1)
    return hit


# ----------------------------------------------------------------------------------------------- kit loading

def load_kit(dirs):
    """{name: component} and {(name, material): {record, tris (kit-local studs)}} for export dirs."""
    comps, chunks = {}, {}
    for d in map(Path, dirs):
        manifest = json.loads((d / "manifest.json").read_text(encoding="utf-8"))
        for name, comp in manifest["components"].items():
            assert name not in comps, f"component {name} exported twice ({d})"
            comps[name] = comp
        for rec in manifest["chunks"]:
            wire = (d / "chunks" / f"c{rec['id']:05d}.b64").read_text(encoding="ascii").strip()
            assert hashlib.sha256(wire.encode("ascii")).hexdigest() == rec["wireSha256"], (d, rec["id"])
            blob = base64.b64decode(wire)
            npos, nnorm, nuv, ntri = (int(x) for x in np.frombuffer(blob, dtype="<u4", count=4))
            pos = np.frombuffer(blob, dtype="<f4", count=npos * 3, offset=16).reshape(-1, 3).astype(np.float64)
            off = 16 + npos * 12 + nnorm * 12 + nuv * 8
            idx = np.frombuffer(blob, dtype="<u4", count=ntri * 9, offset=off).reshape(-1, 3, 3)
            chunks[(rec["component"], rec["material"])] = {
                "record": rec, "tris": (pos + np.array(rec["center"]))[idx[:, :, 0]]}
    return comps, chunks


def default_kit_dirs():
    return [JOBS / j / "export" for j in "ABCDEFG" if (JOBS / j / "export/manifest.json").exists()]


def solid_records(comp, negate_yaw=False):
    """Colliders + collide parts as fake world parts placed with the importer formula."""
    out = []
    for rec in comp.get("colliders", []) + [r for r in comp.get("parts", []) if r.get("collide")]:
        pos, rot = record_frame(rec["cf"], negate_yaw)
        out.append({"name": rec["name"], "canCollide": True, "fixtureKind": "collider",
                    "shape": "PartType.Cylinder" if rec.get("shape") == "Cylinder" else "PartType.Block",
                    "size": list(map(float, rec["size"])), "cframe": list(pos) + list(rot.reshape(-1))})
    return out


# ----------------------------------------------------------------------------------------------- (A) kit check

def chain_yaw_failures(name, comp):
    """A1: boxes in a numbered chain must keep one horizontal axis tangent to the chain."""
    groups = defaultdict(list)
    for rec in comp.get("colliders", []) + [r for r in comp.get("parts", []) if r.get("collide")]:
        nums = tuple(int(x) for x in re.findall(r"\d+", rec["name"]))
        if not nums:
            continue
        pos, rot = record_frame(rec["cf"])
        groups[re.sub(r"\d+", "#", rec["name"])].append((nums, pos, rot, rec))
    bad = []
    for stem, items in groups.items():
        items.sort(key=lambda it: it[0])
        n = len(items)
        if n < 2:
            continue
        for i, (_, pos, rot, rec) in enumerate(items):
            if not is_oblique_rotation(rot) or rot[1, 1] < 1 - 1e-6:
                continue                    # only horizontal (pure yaw) chains: the Blender-sign yaw bug lives there
            prev = items[i - 1][1] if i > 0 else pos
            nxt = items[i + 1][1] if i + 1 < n else pos
            chord = (nxt - prev)[[0, 2]]
            reach = 2.5 * max(rec["size"][0], rec["size"][2], 1.0) * (2 if 0 < i < n - 1 else 1)
            if np.linalg.norm(chord) < 1e-3 or np.linalg.norm(chord) > reach:
                continue                    # not a chain neighbour (ring jump, stacked boxes)
            chord = chord / np.linalg.norm(chord)
            ax = np.array((rot[0, 0], rot[2, 0])); az = np.array((rot[0, 2], rot[2, 2]))
            ax, az = ax / max(np.linalg.norm(ax), 1e-9), az / max(np.linalg.norm(az), 1e-9)
            # arc_boxes writes its chord direction along local X, even when the
            # box is wider radially along Z (decks and collar rings).
            best = abs(ax @ chord) if match(rec["name"], CHORD_X) else max(abs(ax @ chord), abs(az @ chord))
            need = .999 if 0 < i < n - 1 else .95
            if best < need:
                bad.append({"record": rec["name"], "dot": round(float(best), 4),
                            "offDegrees": round(math.degrees(math.acos(min(1, best))), 1)})
    return bad


def exposed_setup(name, comp):
    """(direction function, virtual backing distance function, cap-axis) for cove families, or None."""
    attrs = comp.get("attrs", {})
    side = attrs.get("ExposedSide")
    if side is None and not match(name, COVE_FAMILIES):
        return None
    # Straight = a profile along one wall: runs, stops and CoveBaseStopCorner_* (a stop with a 0.25 straight tail at
    # a square corner, LATTICE_SPEC 2.5). Corner pieces (tori, vertical fillets, inner mitres) are not.
    straight = "WallSide" in attrs and not CORNER_PIECE.search(name)
    radius = float(attrs.get("Radius", attrs.get("FilletRadius", 3)))
    top = "Top" in name
    planes = []                                     # (point, outward unit normal of the backing half-space)
    if straight:
        ws = attrs.get("WallSide", "+Z")
        axis = {"X": 0, "Y": 1, "Z": 2}[ws[-1]]
        sign = -1.0 if ws.startswith("-") else 1.0
        n = np.zeros(3); n[axis] = sign
        planes.append((n * float(attrs.get("WallPlane", 0.0)), n))
        side = side or ("-" if sign > 0 else "+") + ws[-1]
    for mk in comp.get("markers", []):
        if mk["name"].startswith("Tangent"):
            m = np.array(mk["cf"][:3], float); m[1] = 0
            if np.linalg.norm(m) > 1e-6:
                planes.append((m, m / np.linalg.norm(m)))
    if not straight and "CornerRadius" in attrs:
        cyl_r = float(attrs["CornerRadius"])
    else:
        cyl_r = None
    floor = None
    if re.search(r"Cove(Base|Top)", name):
        floor = (radius, 1.0) if top else (0.0, -1.0)      # (plane y, outward sign of the backing half-space)

    def direction(cent):
        if side and side[-1] in "XYZ" and side[0] in "+-":
            v = np.zeros((len(cent), 3)); v[:, "XYZ".index(side[-1])] = 1.0 if side[0] == "+" else -1.0
            return v
        h = -cent.copy(); h[:, 1] = 0                   # 'Inward' (default for corner pieces): toward the pivot axis
        if side == "Outward":
            h = -h
        return h / np.maximum(np.linalg.norm(h, axis=1)[:, None], 1e-9)

    def virtual(pts):
        d = np.full(len(pts), np.inf)
        for p0, n in planes:
            d = np.minimum(d, np.maximum(0, -((pts - p0) @ n)))
        if cyl_r is not None:
            d = np.minimum(d, np.maximum(0, cyl_r - np.hypot(pts[:, 0], pts[:, 2])))
        if floor is not None:
            d = np.minimum(d, np.maximum(0, -(pts[:, 1] - floor[0]) * floor[1]))
        return d

    return direction, virtual, (0 if straight else None)


def kit_check(dirs, placed=frozenset(), rng_seed=0):
    comps, chunks = load_kit(dirs)
    rng = np.random.default_rng(rng_seed)
    rows, failures = [], []
    for name, comp in sorted(comps.items()):
        tris = [c["tris"] for (cn, mat), c in sorted(chunks.items()) if cn == name and mat not in PASSABLE_MATERIALS]
        solids = solid_records(comp)
        row = {"component": name, "colliders": len(solids), "status": "ok", "problems": []}
        yaw_bad = chain_yaw_failures(name, comp)
        if yaw_bad:
            row["problems"].append(f"A1 chain yaw: {len(yaw_bad)} boxes off their chord, worst "
                                   f"{max(b['offDegrees'] for b in yaw_bad)} deg ({yaw_bad[0]['record']})")
            row["chainYaw"] = yaw_bad[:6]
        if not tris:
            row["status"] = "no solid surface"
            rows.append(row)
            if row["problems"]:
                failures.append(row)
            continue
        tri = np.concatenate(tris)
        entry = allow_entry(name)
        if entry and not (entry[0] == "unplaced" and name in placed):
            row.update(status="allowlisted", allow=f"{entry[0]}: {entry[1]}")
        elif not solids:
            row["status"] = "FAIL"
            row["problems"].append("A3 solid component ships no collider and is not in KIT_ALLOW")
        exposed = exposed_setup(name, comp)
        pts, w, nrm, ti = sample(tri, rng)
        virtual = None
        if exposed:
            direction, virtual, cap_axis = exposed
            cent = tri.mean(1)
            seen = ~ray_hits(cent + 1e-3 * direction(cent), direction(cent), tri)
            tn = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
            tn /= np.maximum(np.linalg.norm(tn, axis=1)[:, None], 1e-12)
            if cap_axis is not None:
                seen &= np.abs(tn[:, cap_axis]) < .9
            else:                                   # radial piece: drop the tangential end caps
                t = np.stack((-cent[:, 2], np.zeros(len(cent)), cent[:, 0]), 1)
                t /= np.maximum(np.linalg.norm(t, axis=1)[:, None], 1e-9)
                seen &= np.abs((tn * t).sum(1)) < .9
            keep = seen[ti]
            pts, w = pts[keep], w[keep]
            row["exposedShare"] = round(float(keep.mean()), 3) if len(keep) else 0
        if solids and len(pts):
            res = []
            for neg in (False, True):
                d = Colliders(solid_records(comp, neg)).distance(pts)
                if virtual is not None:
                    d = np.minimum(d, virtual(pts))
                res.append((float(w[d > TOL].sum() / w.sum()), float(min(d.max(), 9.99))))
            share, gap = res[0]
            limit = .005 if match(name, STRICT_FAMILIES) else .02
            row.update(unbacked=round(share, 4), unbackedYawNegated=round(res[1][0], 4), maxGap=round(gap, 2),
                       limit=limit)
            if row["status"] != "allowlisted":
                if share > limit:
                    row["problems"].append(f"A2 unbacked share {share:.3f} > {limit}")
                gap_limit = TOL if match(name, COVE_FAMILIES) else GAP
                if gap > gap_limit:
                    row["problems"].append(f"A2 max gap {gap:.2f} > {gap_limit}")
                if share > res[1][0] + .02:
                    row["problems"].append(f"A2 mirrored yaw: share {share:.3f} drops to {res[1][0]:.3f} "
                                           "with oblique yaws negated")
        if row["problems"] and row["status"] != "allowlisted":
            row["status"] = "FAIL"
        elif row["problems"]:                       # allowlisted but a chain yaw is still wrong
            row["status"] = "FAIL"
        if row["status"] == "FAIL":
            failures.append(row)
        rows.append(row)
    return {"dirs": [str(d) for d in dirs], "components": len(comps), "rows": rows,
            "failures": [r["component"] for r in failures], "passed": not failures}


# ----------------------------------------------------------------------------------------------- world helpers

def label_of(part):
    if part.get("fixtureKind") == "mesh":
        return part["fixtureComponent"], part["name"].rsplit("_", 1)[-1]
    name = re.sub(r"[\d.]+", "#", part["name"])
    name = re.sub(r" (North|South|East|West)$", "", name)
    owner = part.get("fixtureComponent") or "builder"
    mat = part.get("materialVariant") or str(part.get("material", "")).replace("Material.", "")
    return f"part:{owner}:{name}", mat


def is_passable(lab):
    comp, mat = lab
    owner = comp.split(":")[1] if comp.startswith("part:") else comp
    if mat in PASSABLE_MATERIALS or match(comp, PASSABLE_COMPONENTS) or (allow_entry(owner) or ("",))[0] == "passable":
        return True
    return comp.startswith("part:") and any(k in comp for k in PASSABLE_PARTS)


def visual_triangles(world, chunks):
    """[(tris, label, canCollide, part)] for every visible part (mesh fixtures + non-mesh Parts)."""
    out = []
    for part in world["parts"]:
        if part["transparency"] >= .98:
            continue
        if part.get("fixtureKind") == "mesh":
            t = mesh_triangles_world(part, fixture_chunk(part, chunks))
        elif part["class"] != "MeshPart":
            t = wc.part_triangles(part)
        else:
            continue
        out.append((np.asarray(t, dtype=np.float64), label_of(part), part["canCollide"], part))
    return out


def placements_of(world):
    """part id -> placement dict (bisect on the clone's model id, as render_world.map_mesh_fixtures)."""
    placements = sorted(world["components"], key=lambda c: c["modelId"])
    ids = [p["modelId"] for p in placements]
    owner = {}
    for part in world["parts"]:
        comp = part.get("fixtureComponent")
        if not comp:
            continue
        i = bisect.bisect_left(ids, part["id"]) - 1
        if i >= 0 and placements[i]["component"] == comp:
            owner[part["id"]] = i
    return placements, owner


def hall_of(world, p):
    for h in world["layout"]["Halls"]:
        if h["MinX"] - 2 <= p[0] <= h["MaxX"] + 2 and h["MinZ"] - 2 <= p[2] <= h["MaxZ"] + 2:
            return f"Hall {h['Index']} {h['Type']}"
    for c in world["layout"]["Corridors"]:
        along, cross = (p[0], p[2]) if c["Axis"] == "X" else (p[2], p[0])
        if c["From"] - 2 <= along <= c["To"] + 2 and abs(cross - c["Cross"]) <= c["Width"] / 2 + 2:
            return f"Corridor {c['Index']} {c['Kind']} {c['Variant']}"
    return "outside"


def where_types(world, pts):
    out = np.array(["outside"] * len(pts), dtype=object)
    for c in world["layout"]["Corridors"]:
        along, cross = (pts[:, 0], pts[:, 2]) if c["Axis"] == "X" else (pts[:, 2], pts[:, 0])
        m = (along >= c["From"] - 2) & (along <= c["To"] + 2) & (np.abs(cross - c["Cross"]) <= c["Width"] / 2 + 2)
        out[m] = f"Corridor {c['Kind']} {c['Variant']}"
    for h in world["layout"]["Halls"]:
        m = (pts[:, 0] >= h["MinX"] - 2) & (pts[:, 0] <= h["MaxX"] + 2) & \
            (pts[:, 2] >= h["MinZ"] - 2) & (pts[:, 2] <= h["MaxZ"] + 2)
        out[m] = h["Type"]
    return out


def standing_space(occupied):
    """Centre column clear for 5 voxels, the 3x3 footprint only from 2 voxels above the feet (step-up)."""
    centre = occupied.copy()
    for dy in range(1, 5):
        centre[:-dy] |= occupied[dy:]
    upper = np.zeros_like(occupied)
    for dy in range(2, 5):
        upper[:-dy] |= occupied[dy:]
    side = upper.copy()
    for dz in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if dx == dz == 0:
                continue
            zd = slice(max(0, -dz), min(side.shape[1], side.shape[1] - dz))
            zs = slice(max(0, dz), min(side.shape[1], side.shape[1] + dz))
            xd = slice(max(0, -dx), min(side.shape[2], side.shape[2] - dx))
            xs = slice(max(0, dx), min(side.shape[2], side.shape[2] + dx))
            side[:, zd, xd] |= upper[:, zs, xs]
    blocked = centre | side
    del upper, side, centre
    free = ~blocked
    free[1:] &= occupied[:-1]
    free[0] = False
    return free, blocked


def reach_mask(world, log=print, with_body=True):
    """Flood from ElevatorSpawn with pressure doors open; returns (low, body voxels, standing voxels).
    with_body=False skips the dilated body mask (returns None for it)."""
    low, occupied, _ = wc.voxel_grid(world, True)
    standable, blocked = standing_space(occupied)
    allowed, near = wc.volume_masks(world, low, occupied.shape)
    ny, nz, nx = occupied.shape
    del occupied
    visited = np.zeros_like(standable)
    spawn = next(p for p in world["parts"] if p["name"] == "ElevatorSpawn")
    s = np.floor(np.asarray(spawn["cframe"][:3]) - low).astype(int)
    while s[1] < ny - 6 and not standable[s[1], s[2], s[0]]:
        s[1] += 1
    assert s[1] < ny - 6, "ElevatorSpawn has no standing voxel"
    queue = [(s[1], s[2], s[0])]
    standable[s[1], s[2], s[0]] = False
    visited[s[1], s[2], s[0]] = True
    head = 0
    low_floor = min(h["FloorY"] for h in world["layout"]["Halls"])
    while head < len(queue):
        iy, iz, ix = queue[head]
        head += 1
        if not allowed[iy, iz, ix] and not near[iz, ix]:
            continue
        if low[1] + iy + .5 < low_floor - 4:
            continue
        for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            xx, zz = ix + dx, iz + dz
            if not (1 <= xx < nx - 1 and 1 <= zz < nz - 1):
                continue
            nxt = None
            for delta in (0, 1, -1, 2, -2, 3, -3):
                yy = iy + delta
                if 1 <= yy < ny - 5 and standable[yy, zz, xx]:
                    nxt = yy
                    break
            if nxt is None and not blocked[iy, zz, xx]:
                for yy in range(iy - 1, 0, -1):
                    if blocked[yy, zz, xx]:
                        break
                    if standable[yy, zz, xx]:
                        nxt = yy
                        break
            if nxt is not None:
                standable[nxt, zz, xx] = False
                visited[nxt, zz, xx] = True
                queue.append((nxt, zz, xx))
    del standable, blocked, allowed, near
    log(f"  flood reached {len(queue)} standing voxels")
    if not with_body:
        return low, None, visited
    body = visited.copy()
    for dy in range(1, 6):                       # 5 tall body + 1 above head
        body[dy:] |= visited[:-dy]
    body[:-1] |= body[1:].copy()                 # 1 below the feet (the floor itself)
    for _ in range(2):                           # 3x3 footprint, +1 contact
        body = dilate_xz(body)
    return low, body, visited


def dilate_xz(m):
    b = m.copy()
    b[:, 1:, :] |= m[:, :-1, :]
    b[:, :-1, :] |= m[:, 1:, :]
    b[:, :, 1:] |= m[:, :, :-1]
    b[:, :, :-1] |= m[:, :, 1:]
    return b


def lookup(mask, low, pts):
    idx = np.floor(pts - low).astype(int)
    ny, nz, nx = mask.shape
    ok = (idx[:, 0] >= 0) & (idx[:, 0] < nx) & (idx[:, 1] >= 0) & (idx[:, 1] < ny) & \
         (idx[:, 2] >= 0) & (idx[:, 2] < nz)
    out = np.zeros(len(pts), dtype=bool)
    out[ok] = mask[idx[ok, 1], idx[ok, 2], idx[ok, 0]]
    return out


def world_manifests(world):
    comps = {}
    for receipt in world["kitExports"].values():
        comps.update(json.loads(Path(receipt["path"]).read_text(encoding="utf-8"))["components"])
    return comps


# ----------------------------------------------------------------------------------------------- (B) builder checks

# Documented builder renames: (kit record name, regex the builder's clone may carry instead). The clone must also
# keep the record's exact size. makeCorridor renames every BasePart whose name contains 'Roof' to
# 'Level 2 Passage|Corridor Roof Collider <corridor index>' (Kit World Builder, corridor roof loop).
BUILDER_RENAMES = ((re.compile(r"Roof"), re.compile(r"^Level 2 (Passage|Corridor) Roof Collider \d+$")),)
# Documented consolidation (B): a lost kit collider is accepted when
#   RUN     the union of the placement's hall/corridor 'Level 2 Run ...' CanCollide parts covers every sample of the
#           record's box (surface + centre, <= 0.5 apart) within RUN_TOL;
#   CEILING the record box lies entirely above its hall's ceiling plane C = FloorY + CeilingClass (inside the slab,
#           the roof band or a light-well shaft; check 03 proves every opening is capped and out of jump reach);
#   TOPCOVE a top-cove fill (any CoveTop* record, or a swerve piece's 'Swerve Top Cove Fill ...') whose box lies
#           entirely above C - 4 (CeilingClass - 4 above the floor).
RUN_PREFIX = "Level 2 Run"
RUN_TOL = .05


def record_box_samples(box_cf, size, step=.5):
    """Points on the surface of an oriented box (and its centre), <= step apart."""
    pos, rot = box_cf
    e = np.asarray(size, float) / 2
    axes = [np.linspace(-e[k], e[k], max(2, int(math.ceil(2 * e[k] / step)) + 1)) for k in range(3)]
    g = np.stack(np.meshgrid(*axes, indexing="ij"), -1).reshape(-1, 3)
    surface = np.any(np.isclose(np.abs(g), e, atol=1e-9), axis=1)
    local = np.vstack((g[surface], np.zeros((1, 3))))
    return local @ rot.T + pos


def placement_frame(pl):
    return np.asarray(pl["pivot"][:3], float), np.asarray(pl["pivot"][3:], float).reshape(3, 3)


def is_top_cove_fill(pl, rec):
    """A top-cove fill: any CoveTop* record, or a swerve piece's 'Swerve Top Cove Fill ...' (buildSwerve drops both)."""
    return fnmatch.fnmatchcase(pl["component"], "CoveTop*") or rec["name"].startswith("Swerve Top Cove Fill")


def accepted_loss(world, pl, rec, have_parts, runs, halls):
    """Name of the documented rule that accepts a lost kit collider record, or None."""
    for src, dst in BUILDER_RENAMES:
        if src.search(rec["name"]) and any(dst.match(p["name"]) and np.allclose(p["size"], rec["size"], atol=1e-3)
                                           for p in have_parts):
            return "rename"
    ppos, prot = placement_frame(pl)
    rpos, rrot = record_frame(rec["cf"])
    box = (ppos + prot @ rpos, prot @ rrot)
    pts = record_box_samples(box, rec["size"])
    if runs is not None and len(pts) and np.all(runs.distance(pts) <= RUN_TOL):
        return "run"
    hm = re.search(r"Level 2 Hall (\d+)\b", pl["modelPath"])
    h = halls.get(int(hm.group(1))) if hm else None
    if h is not None:
        C = h["FloorY"] + h["CeilingClass"]
        low = float(pts[:, 1].min())
        if low >= C - 1e-3:
            return "ceiling"
        if is_top_cove_fill(pl, rec) and low >= C - 4 - 1e-3:
            return "topcove"
    return None


def builder_check(world, chunks):
    comps = world_manifests(world)
    placements, owner = placements_of(world)
    by_placement = defaultdict(list)
    for part in world["parts"]:
        if part["id"] in owner:
            by_placement[owner[part["id"]]].append(part)
    halls = {h["Index"]: h for h in world["layout"]["Halls"]}
    run_parts = [p for p in world["parts"] if p["canCollide"] and p["name"].startswith(RUN_PREFIX)]
    runs = Colliders(run_parts, pad=RUN_TOL + .01) if run_parts else None
    missing = defaultdict(lambda: {"placements": 0, "records": 0, "names": set(), "example": None})
    accepted = Counter()
    out_of_bounds = defaultdict(lambda: {"placements": 0, "worst": 0.0, "example": None})
    for i, pl in enumerate(placements):
        comp = comps.get(pl["component"], {})
        records = [r for r in comp.get("colliders", []) + [r for r in comp.get("parts", []) if r.get("collide")]
                   if not r.get("attrs", {}).get("SocketPlug")]
        want = Counter(r["name"] for r in records)
        have_parts = [p for p in by_placement[i] if p["canCollide"]]
        have = Counter(p["name"] for p in have_parts)
        lost = want - have
        if lost:
            extra = [p for p in have_parts if p["name"] not in want]
            for name, n in list(lost.items()):
                for rec in [r for r in records if r["name"] == name][-n:]:
                    rule = accepted_loss(world, pl, rec, extra, runs, halls)
                    if rule:
                        accepted[rule] += 1
                        lost[name] -= 1
            lost = +lost
        if lost:
            m = missing[pl["component"]]
            m["placements"] += 1
            m["records"] += sum(lost.values())
            m["names"].update(lost)
            m["example"] = m["example"] or pl["modelPath"]
        hm = re.search(r"Level 2 Hall (\d+)\b", pl["modelPath"])
        if not hm or match(pl["component"], BRIDGING) or int(hm.group(1)) not in halls:
            continue
        h = halls[int(hm.group(1))]
        tris = [mesh_triangles_world(p, fixture_chunk(p, chunks)) for p in by_placement[i]
                if p.get("fixtureKind") == "mesh"]
        if not tris:
            continue
        t = np.concatenate(tris).reshape(-1, 3)
        over = max(h["MinX"] - 2 - t[:, 0].min(), t[:, 0].max() - h["MaxX"] - 2,
                   h["MinZ"] - 2 - t[:, 2].min(), t[:, 2].max() - h["MaxZ"] - 2)
        if over > .01:
            o = out_of_bounds[pl["component"]]
            o["placements"] += 1
            if over > o["worst"]:
                o["worst"], o["example"] = round(float(over), 2), pl["modelPath"]
    seals = defaultdict(int)
    for part in world["parts"]:
        if part["canCollide"] and not part.get("fixtureComponent") and SEAL.search(part["name"]):
            seals[re.sub(r"[\d.]+", "#", part["name"])] += 1
    result = {
        "lostColliders": {k: {"placements": v["placements"], "records": v["records"],
                              "names": sorted(v["names"])[:8],
                              "nameCount": len(v["names"]), "example": v["example"]}
                          for k, v in sorted(missing.items())},
        "seals": dict(seals),
        "outOfHall": {k: dict(v) for k, v in sorted(out_of_bounds.items())},
        "acceptedLosses": dict(accepted),
    }
    result["passed"] = not (result["lostColliders"] or result["seals"] or result["outOfHall"])
    return result


# ----------------------------------------------------------------------------------------------- (C) world audit

def world_audit(world, chunks, log=print):
    from scipy.spatial import cKDTree      # lazy: Blender's Python (world_audit.py) has no scipy
    seed = world["requestedSeed"]
    vis = visual_triangles(world, chunks)
    colliding = [p for p in world["parts"] if p["canCollide"]]
    col = Colliders(colliding)
    low, body, visited = reach_mask(world, log)
    # Body for the invisible pass: feet voxel up to one above the head, one voxel sideways. The feet voxel already
    # holds the 0.35 probe off any floor it stands on; extending it one voxel BELOW the feet reached 0.6 under a pipe
    # floor's top, behind the pipe's visual skin (5-9% false ghost collision on every narrow-pipe facet).
    tight = visited.copy()
    for dy in range(1, 6):
        tight[dy:] |= visited[:-dy]
    around = tight.copy()
    around[:, 1:, :] |= tight[:, :-1, :]
    around[:, :-1, :] |= tight[:, 1:, :]
    tight = around.copy()
    tight[:, :, 1:] |= around[:, :, :-1]
    tight[:, :, :-1] |= around[:, :, 1:]
    del visited
    rng = np.random.default_rng(seed)
    per = defaultdict(lambda: {"reach": 0.0, "unbacked": 0.0, "deep": 0.0, "count": 0, "pts": [],
                               "types": defaultdict(float)})
    vis_pts = []
    for t, lab, collides, _part in vis:
        pts, w, _, _ = sample(t, rng)
        # The 'visual within 1.0' tree needs no random holes wider than 1.0: sample it four times as densely.
        vis_pts.append(np.concatenate((pts, sample(t, rng, 3 * DENSITY)[0])))
        if collides:
            continue
        d = col.distance(pts)
        reach = lookup(body, low, pts)
        r = per[lab]
        r["count"] += 1
        r["reach"] += w[reach].sum()
        bad = reach & (d > TOL)
        r["unbacked"] += w[bad].sum()
        r["deep"] += w[reach & (d > GAP)].sum()
        if bad.any():
            wt = where_types(world, pts[bad])
            for k in set(wt):
                r["types"][k] += float(w[bad][wt == k].sum())
            for i in np.argsort(-d[bad])[:2]:
                r["pts"].append((pts[bad][i].round(1).tolist(), round(float(min(d[bad][i], 9.99)), 2)))
    del body
    tree = cKDTree(np.concatenate(vis_pts))
    del vis_pts
    phantom = defaultdict(lambda: {"reach": 0.0, "far": 0.0, "pts": []})
    for p in colliding:
        if p.get("fixtureKind") == "slide-template" or p["transparency"] < .98:
            continue                             # a visible collider is its own visual: never ghost collision
        pts, w, nrm, _ = sample(np.asarray(wc.part_triangles(p)), rng, 1.0)
        a, b = pts + nrm * .35, pts - nrm * .35
        da, db = col.distance(a), col.distance(b)
        off = np.where((da >= db)[:, None], a, b)
        exposed = np.maximum(da, db) > .05
        reach = exposed & lookup(tight, low, off)
        if not reach.any():
            continue
        dd, _ = tree.query(pts[reach], distance_upper_bound=1.5)
        lab = label_of(p)[0]
        far = dd > 1.0
        phantom[lab]["reach"] += w[reach].sum()
        phantom[lab]["far"] += w[reach][far].sum()
        if far.any() and len(phantom[lab]["pts"]) < 3:
            phantom[lab]["pts"].append(pts[reach][far][0].round(1).tolist())
    del tight
    rows = []
    for lab, r in per.items():
        if r["reach"] <= 0:
            continue
        share = r["unbacked"] / r["reach"]
        row = {"label": lab[0], "material": lab[1], "passable": is_passable(lab), "instances": r["count"],
               "reachableArea": round(r["reach"], 1), "unbacked": round(r["unbacked"], 1),
               "walkThrough": round(r["deep"], 1), "share": round(share, 4),
               "byWhere": {k: round(v, 1) for k, v in sorted(r["types"].items(), key=lambda kv: -kv[1])},
               "examples": [{"pos": p, "gap": g, "where": hall_of(world, p)}
                            for p, g in sorted(r["pts"], key=lambda v: -v[1])[:3]]}
        row["fails"] = [] if row["passable"] else \
            (["C1 share"] if share > .02 else []) + (["C2 walk-through"] if r["deep"] > 1.0 else [])
        rows.append(row)
    rows.sort(key=lambda x: -x["unbacked"])
    ph = []
    for k, v in phantom.items():
        if v["far"] <= 0:
            continue
        exempt = any(s in k for s in INVISIBLE_OK)
        share = v["far"] / max(v["reach"], 1e-9)
        fails = [] if exempt else (["C4 share"] if share > .05 else []) + (["C4 area"] if v["far"] > 50 else [])
        ph.append({"collider": k, "reachableArea": round(v["reach"], 1), "invisible": round(v["far"], 1),
                   "share": round(share, 3), "exempt": exempt, "fails": fails,
                   "examples": [{"pos": p, "where": hall_of(world, p)} for p in v["pts"]]})
    ph.sort(key=lambda x: -x["invisible"])
    solid = [r for r in rows if not r["passable"]]
    reach_total = sum(r["reachableArea"] for r in solid)
    unbacked_total = sum(r["unbacked"] for r in solid)
    invisible_total = sum(p["invisible"] for p in ph if not p["exempt"])
    decals = flush_decals(world, chunks, col)
    criteria = {
        "C1 per-label unbacked share <= 0.02": [r["label"] + f" [{r['material']}]" for r in solid if "C1 share" in r["fails"]],
        "C2 per-label walk-through area <= 1": [r["label"] + f" [{r['material']}]" for r in solid if "C2 walk-through" in r["fails"]],
        "C3 total unbacked share <= 0.005": [] if unbacked_total <= .005 * max(reach_total, 1e-9) else
        [f"{unbacked_total:.1f} / {reach_total:.1f} = {unbacked_total / max(reach_total, 1e-9):.4f}"],
        "C4 invisible collision per label / total <= 300": [p["collider"] for p in ph if p["fails"]] +
        ([f"seed total {invisible_total:.1f}"] if invisible_total > 300 else []),
        "C5 flush decals": [f"{d['component']} x{d['bad']}" for d in decals if d["bad"]],
    }
    return {"seed": seed,
            "totals": {"solidReachable": round(reach_total, 1), "solidUnbacked": round(unbacked_total, 1),
                       "solidWalkThrough": round(sum(r["walkThrough"] for r in solid), 1),
                       "invisibleCollision": round(invisible_total, 1)},
            "criteria": {k: v for k, v in criteria.items()},
            "passed": not any(criteria.values()), "visual": rows, "invisible": ph, "decals": decals}


def flush_decals(world, chunks, col):
    """C5: DrainHole plates sit on the floor collider; LightRound tops touch the ceiling plane."""
    placements, owner = placements_of(world)
    groups = defaultdict(list)
    for part in world["parts"]:
        if part.get("fixtureKind") == "mesh" and part["id"] in owner and \
                part["fixtureComponent"] in ("DrainHole", "LightRound"):
            groups[owner[part["id"]]].append(part)
    halls = world["layout"]["Halls"]
    out = {"DrainHole": {"component": "DrainHole", "placed": 0, "bad": 0, "worst": 0.0, "examples": []},
           "LightRound": {"component": "LightRound", "placed": 0, "bad": 0, "worst": 0.0, "examples": []}}
    for i, parts in groups.items():
        comp = placements[i]["component"]
        t = np.concatenate([mesh_triangles_world(p, fixture_chunk(p, chunks)) for p in parts]).reshape(-1, 3)
        c = t.mean(0)
        if comp == "DrainHole":
            err = float(col.distance(t).max())
        else:
            h = next((h for h in halls if h["MinX"] <= c[0] <= h["MaxX"] and h["MinZ"] <= c[2] <= h["MaxZ"]), None)
            if h is None:
                continue
            err = abs(float(t[:, 1].max()) - (h["FloorY"] + h["CeilingClass"]))
        o = out[comp]
        o["placed"] += 1
        if err > .3:
            o["bad"] += 1
            o["worst"] = round(max(o["worst"], min(err, 9.99)), 2)
            if len(o["examples"]) < 3:
                o["examples"].append({"pos": c.round(1).tolist(), "error": round(min(err, 9.99), 2),
                                      "where": hall_of(world, c)})
    return list(out.values())


# ----------------------------------------------------------------------------------------------- driver

def placed_components(dumps):
    placed = set()
    for d in dumps:
        placed |= {c["component"] for c in json.loads(Path(d).read_text(encoding="utf-8"))["components"]}
    return frozenset(placed)


def print_kit(report):
    print(f"KIT {len(report['dirs'])} dirs, {report['components']} components, "
          f"{len(report['failures'])} failing: {'PASS' if report['passed'] else 'FAIL'}")
    for r in report["rows"]:
        if r["status"] == "FAIL":
            extra = f" unbacked={r.get('unbacked')} yawNeg={r.get('unbackedYawNegated')} gap={r.get('maxGap')}"
            print(f"  FAIL {r['component']:28s}{extra}  " + "; ".join(r["problems"]))


def print_world(rep):
    b, w = rep["builder"], rep["world"]
    print(f"WORLD seed {rep['seed']}: builder {'PASS' if b['passed'] else 'FAIL'}, "
          f"audit {'skipped' if w is None else 'PASS' if w['passed'] else 'FAIL'}  ({rep['seconds']} s)")
    for k, v in b["lostColliders"].items():
        print(f"  B lost colliders {k}: {v['placements']} placements, {v['nameCount']} names e.g. {v['names'][:3]}")
    for k, v in b["seals"].items():
        print(f"  B seal stand-in {k} x{v}")
    for k, v in b["outOfHall"].items():
        print(f"  B outside its hall {k}: {v['placements']} placements, worst {v['worst']} ({v['example']})")
    if b.get("acceptedLosses"):
        print(f"  B documented collider renames/consolidations accepted: {b['acceptedLosses']}")
    if not w:
        return
    print(f"  totals {w['totals']}")
    for k, v in w["criteria"].items():
        print(f"  {'FAIL' if v else 'pass'} {k}" + (f": {len(v)} -> {v[:6]}" if v else ""))
    for r in [r for r in w["visual"] if r["fails"]][:25]:
        print(f"    {r['unbacked']:9.1f}/{r['reachableArea']:9.1f} ({r['share']:.3f}) walk {r['walkThrough']:8.1f} "
              f"{r['label']} [{r['material']}] x{r['instances']} {r['examples'][:1]}")
    for p in [p for p in w["invisible"] if p["fails"]][:12]:
        print(f"    INVISIBLE {p['invisible']:8.1f}/{p['reachableArea']:8.1f} ({p['share']:.2f}) {p['collider']} "
              f"{p['examples'][:1]}")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("dumps", nargs="*", type=Path, help="world dump JSON files (default: the three regression dumps)")
    ap.add_argument("--kit", nargs="*", type=Path, help="kit export dirs (default: jobs/*/export)")
    ap.add_argument("--no-kit", action="store_true")
    ap.add_argument("--no-world", action="store_true")
    ap.add_argument("--quick", action="store_true", help="audit the three frozen regression dumps (default)")
    ap.add_argument("--all", action="store_true", help="audit every world_*.json in the dump directory")
    ap.add_argument("--builder-only", action="store_true", help="skip the voxel world audit (C)")
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT)
    args = ap.parse_args(argv)
    if args.all and (args.dumps or args.quick):
        ap.error("--all cannot be combined with explicit dumps or --quick")
    dumps = [] if args.no_world else (sorted(WORLDS.glob("world_*.json")) if args.all else
                                      args.dumps or DEFAULT_DUMPS)
    if args.all and not args.no_world and not dumps:
        ap.error("--all found no world dumps")
    args.out.mkdir(parents=True, exist_ok=True)
    passed = True
    if not args.no_kit:
        t0 = time.time()
        dirs = args.kit or default_kit_dirs()
        report = kit_check(dirs, placed_components(dumps))
        report["seconds"] = round(time.time() - t0, 1)
        (args.out / "collision_kit.json").write_text(json.dumps(report, indent=1), encoding="utf-8")
        print_kit(report)
        passed &= report["passed"]
    for path in dumps:
        t0 = time.time()
        world = load_world(path)
        chunks = load_kit_chunks(world)
        rep = {"seed": world["requestedSeed"], "dump": str(path), "builder": builder_check(world, chunks)}
        rep["world"] = None if args.builder_only else world_audit(world, chunks)
        rep["seconds"] = round(time.time() - t0, 1)
        rep["passed"] = rep["builder"]["passed"] and (args.builder_only or rep["world"]["passed"])
        (args.out / f"collision_{rep['seed']}.json").write_text(json.dumps(rep, indent=1, default=str),
                                                               encoding="utf-8")
        print_world(rep)
        passed &= rep["passed"]
        del world, chunks
    print("COLLISION AUDIT", "PASS" if passed else "FAIL", f"(reports in {args.out})")
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
