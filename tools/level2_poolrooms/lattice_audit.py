"""Tile-lattice seam audit for dumped Poolrooms worlds (pure numpy, no Blender needed; runs inside it too).

    python -B tools/level2_poolrooms/lattice_audit.py world_837834.json [...] [--max-offset 0.01] [--json OUT]
    python -B tools/level2_poolrooms/lattice_audit.py --self-test

Exit code 1 when any finding is reported (self-test: when a planted control is misjudged, at tile 0.6 and 0.5).

THE RULE (measured in a Play client on 2026-10-05, G:/Roblox/_local/l2fix/studio/TILE_PHASE.md). A tiled Part
(MaterialVariant PR Tile / PR Tile Aqua, 8 x 8 tiles per StudsPerTile) anchors its texture at ONE corner of each face,
in object space: a full tile starts exactly at that corner and grout lines repeat every tile from it. The corner is
fixed per face (ANCHOR below; every side face anchors at its top-left corner seen from outside). A kit MeshPart carries
its grid in its own UVs: grout lines where 8*u or 8*v is an integer, so its grid moves with the placement (and any
stretch). Nothing is world-aligned and nothing is face-centred. The tile pitch is read from the dump's kit manifest
(materials.Tile.tile_m / scaleMetresPerStud / 8: 0.6 today, 0.5 under LATTICE_SPEC).

WHAT IS A SEAM. Two tiled surfaces of two different parts - Part/Part, Part/MeshPart, MeshPart/MeshPart - facing the
same way (normals within ~20 deg: a cove's last facet runs a few degrees off its wall) and within COLLINEAR (0.05) of
one plane at the meeting line (a 0.02 step reads as one surface; a flat trim parallel to its host face up to
INLAY_PLANE 0.1 proud, like ExitMouthTrim 0.06 off the exit collar):
  edge   their boundary edges are collinear (within 0.05) and overlap by > 0.02, the faces on opposite sides;
  inlay  a boundary edge of one lies strictly inside a coplanar tiled Part face, or inside an axis-aligned flat triangle
         of another tiled mesh (a cove's tangent edge on a wall, a torus foot on a ring deck, a frame on a panel):
         the host is seen on the far side of that edge.
  corner two tiled faces folding round one shared edge at 60..120 deg, inside or outside: their boundary edges
         collinear (different parts, or one Part's own edge: a plinth), or one face's edge lying inside a perpendicular
         tiled Part face, the face rising off its front (a T-corner: a sill top or lintel soffit against its jamb, a
         box standing on a floor). Only the lines that CROSS the edge must meet there (compare_corner).
Same-facing is required for meshes too: kit meshes are DoubleSided, but finish() winds faces to their visible side, so a
face wound against its neighbour is a hidden back (a column cap on the ceiling plane). Hidden faces may be wound either
way (the swerve tail caps face into their own solid), which is why the exposure test's inside check is a ray parity.

OFFSETS. Each side's grid families (sets of parallel grout lines) are unfolded into that side's own seam frame (seam
direction t, in-surface direction across it), matched to the other side's family of the same direction, and their phase
difference is evaluated exactly at both ends of every shared piece (it is linear along the piece). 'along' = lines
crossing the seam (a jog along it), 'across' = lines parallel to it (a sliver tile or a doubled line), both folded into
[0, half a tile]. No counterpart within 2 degrees counts half a tile ('angle'); a pitch more than 1% off is 'pitch'.
CURVED CUTS are not seams: where a square field (grid along the world axes) is met along a line its grid crosses
obliquely - a curve such as a corner torus's foot, a ring deck's nosing, a stop's arc - by a trim whose own grid follows
that line, no tiling can continue the square grid; the field is cut and the trim's rows run along the cut. Such pieces
are counted (stats cut_pieces / cut_length_x10), not judged. A straight seam along a field's own axes always has a field
family parallel to it, so a trim with a mis-turned grid there is still a finding.

FINDINGS. A seam whose worst offset exceeds --max-offset (0.01) is a finding when at least --min-exposed (0.25) studs of
it are visible from where a player can be, on BOTH of its faces: each face is sampled SIDE_STEP (0.03) into itself from
the seam line (0.5 apart, at most EXPOSURE_CAP per piece; a T-corner's Part face on either side of the edge), and a
sample is visible when, 0.02 off the face, it lies in an air box (a hall from its basin floor up, a corridor from 2 under
its floor, the exit flume's own pieces), is inside no visible solid Part and no closed kit mesh (ray parity: a cap
butted against the next piece's cap is sealed; an open kit mesh whose every free edge lies on visible Part faces,
like a swerve skin whose wall-plane facets the hall wall slab supplies, counts as closed by them), and one of the EXPOSURE_DIRS rays within 75 deg of the face normal
runs EXPOSURE_RANGE (4) studs without hitting any visible triangle and ends in air inside the room (a hall's box less
its WALL_DEPTH wall band, a bore, the flume: a ray that stays in the wall band runs up a hidden void). Offsets are computed for every
seam; exposure only for the ones that step. Not judged: tiled faces that meet nothing (an isolated Part may sit off the
lattice), seams on non-axis-aligned mesh hosts (only edge seams are found there), and the grid inside one mesh.

API (stable; the builder test and world_audit import it):
    audit_world(dump_path, max_offset=MAX_OFFSET, min_exposed=MIN_EXPOSED, stats=None) -> list[dict]   (findings)
    audit_parts(parts, layout, chunks, max_offset=..., min_exposed=..., stats=None, jobs=None, tile=TILE)
        parts: dump_world.py part dicts; layout: the dump's layout (air boxes); chunks: render_world.load_kit_chunks
        (or {(component, material): {"record": {"size"}, "positions", "uv", "indices"}}); jobs: component -> kit job
        letter for the owner field (default: the chunks' "job"); tile: pitch in studs (audit_world reads the manifest).
    seam_pieces(parts, chunks, tile) -> raw per-piece arrays, no exposure (fast; for counts and mutations).
A finding: {kind, category ("familyA | familyB"), a, b ({name, family, component, class, owner, path}), along, across,
offset, flags, exposed, length, at (world xyz of a visible sample), normal, hall}.
"""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import json
import math
from pathlib import Path
import re
import sys

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import collision_audit as ca  # noqa: E402  (stubs bpy, so world_check's numpy helpers import without Blender)
import world_check as wc  # noqa: E402
from render_world import fixture_chunk, load_kit_chunks  # noqa: E402

TILE = .6
MAX_OFFSET = .01
MIN_EXPOSED = .25
TILED_VARIANTS = {"PR Tile", "PR Tile Aqua"}
TILED_CHUNKS = {"Tile", "Aqua"}
# Measured anchor corner per face, object space: (face axis, sign) -> ((axis 1, anchored sign), (axis 2, anchored sign)).
ANCHOR = {
    (1, 1): ((0, 1), (2, 1)),      # +Y top:    +X, +Z
    (1, -1): ((0, 1), (2, -1)),    # -Y bottom: +X, -Z
    (0, 1): ((1, 1), (2, 1)),      # +X:        +Y, +Z
    (0, -1): ((1, 1), (2, -1)),    # -X:        +Y, -Z
    (2, 1): ((1, 1), (0, -1)),     # +Z:        +Y, -X
    (2, -1): ((1, 1), (0, 1)),     # -Z:        +Y, +X
}
SMOOTH = .94            # normals within ~20 deg: one continuing surface (a cove's last facet is ~6 deg off its wall)
# Both sides must face the SAME way. Kit meshes are DoubleSided, but finish() winds every face to its visible side
# (FIX_SPEC G2) and closed solids wind outward, so a mesh face wound against its neighbour is a hidden back (a column's
# top cap on the ceiling plane), not a seam.
COLLINEAR = .05         # edge lines (and planes) this close read as one seam / one surface: the dry floor sits
                        # .02 under the thresholds, a grid jog across that step is still a seam
INLAY_PLANE = .1        # a flat trim laid PARALLEL on a face (normals within ~0.8 deg) reads as an inlay up to this far
                        # proud: ExitMouthTrim stands 0.06 off the exit collar, and its outline is a seam there. Leaning
                        # facets (a cove's last facet) keep COLLINEAR, or every cove end profile would pair its wall.
PARALLEL = 1 - 1e-4
MARGIN = .01            # an inlay edge lies this far inside the host face
MIN_OVERLAP = .02
EXPOSURE_STEP = .5      # visibility sample spacing
EXPOSURE_RANGE = 4.0
EXPOSURE_CAP = 24        # visibility samples per seam piece (spread evenly)
SIDE_STEP = .03         # exposure samples sit this far into each face from the seam line
SEAL_TOL = .1           # an open mesh's free edge this close to a Part surface is sealed by it (Exposure.sealed):
                        # a swerve S stands its wall band 0.05..0.075 proud of the slab at its LEAD facets
WALL_DEPTH = 1.75       # a hall's wall faces stand this far inside its layout rectangle (LATTICE_SPEC 2.2)
EXPOSURE_DIRS = wc.directions(96)
OWNERS = {"A": "modules_arch.py", "B": "modules_tunnel.py", "C": "objectives.py", "D": "modules_swerve.py"}
BUILDER = "Kit World Builder"


# ----------------------------------------------------------------------------------------------- faces and grids

def frame(part):
    cf = np.asarray(part["cframe"], float)
    return cf[:3], cf[3:].reshape(3, 3)


def tiled_part(p):
    return (p["class"] != "MeshPart" and p.get("materialVariant") in TILED_VARIANTS and p["transparency"] < .98
            and "Block" in str(p.get("shape", "Block")))


def tiled_mesh(p):
    return (p.get("fixtureKind") == "mesh" and p["transparency"] < .98
            and p["name"].rsplit("_", 1)[-1] in TILED_CHUNKS)


def part_faces(part, tile=TILE):
    """The six faces of a tiled Block Part: dicts with normal, centre, axes (e1, e2, half sizes) and grid families
    [(G, c)]: grout lines where G.P + c is an integer (G = face axis / 0.6, c from the measured anchor corner)."""
    c, R = frame(part)
    s = np.asarray(part["size"], float) / 2
    out = []
    for (a, sg), ((i, si), (j, sj)) in ANCHOR.items():
        n = R[:, a] * sg
        fc = c + n * s[a]
        ei, ej = R[:, i], R[:, j]
        anchor = fc + ei * si * s[i] + ej * sj * s[j]
        fams = [(ei / tile, -(ei @ anchor) / tile), (ej / tile, -(ej @ anchor) / tile)]
        out.append({"n": n, "c": fc, "e": (ei, ej), "h": (s[i], s[j]), "fams": fams, "face": (a, sg)})
    return out


def tri_families(T, UV):
    """Per triangle (n,3,3 world; n,3,2 uv): G (n,2,3), c (n,2), valid (n,2): lines where G.P + c is an integer."""
    e1, e2 = T[:, 1] - T[:, 0], T[:, 2] - T[:, 0]
    a, b, d = (e1 * e1).sum(1), (e1 * e2).sum(1), (e2 * e2).sum(1)
    det = a * d - b * b
    ok = det > 1e-12
    det = np.where(ok, det, 1)
    G = np.zeros((len(T), 2, 3))
    C = np.zeros((len(T), 2))
    for k in (0, 1):
        du1, du2 = (UV[:, 1, k] - UV[:, 0, k]) * 8, (UV[:, 2, k] - UV[:, 0, k]) * 8
        # G = x e1 + y e2 with G.e1 = du1, G.e2 = du2
        x, y = (d * du1 - b * du2) / det, (a * du2 - b * du1) / det
        G[:, k] = x[:, None] * e1 + y[:, None] * e2
        C[:, k] = UV[:, 0, k] * 8 - (G[:, k] * T[:, 0]).sum(1)
    valid = ok[:, None] & (np.linalg.norm(G, axis=2) > 1e-3)
    return G, C, valid


def chunk_boundary(chunk):
    """(triangle, corner) of every edge where this chunk's surface ends: no other triangle of the chunk continues
    smoothly across it (a free edge or a crease sharper than SMOOTH). Kit-local, cached per chunk."""
    if "_boundary" in chunk:           # cached on the chunk itself (an id() key goes stale once a world is freed)
        return chunk["_boundary"]
    P, I = chunk["positions"], chunk["indices"]
    tri = P[I[:, :, 0]].astype(float)
    nrm = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    nrm /= np.maximum(np.linalg.norm(nrm, axis=1), 1e-12)[:, None]
    _, vid = np.unique(np.round(P / .002).astype(np.int64), axis=0, return_inverse=True)
    vid = vid.reshape(-1)[I[:, :, 0]]
    edges = np.stack([np.sort(np.stack((vid[:, k], vid[:, (k + 1) % 3]), 1), 1) for k in range(3)], 1).reshape(-1, 2)
    owner = np.repeat(np.arange(len(tri)), 3)
    corner = np.tile(np.arange(3), len(tri))
    order = np.lexsort((edges[:, 1], edges[:, 0]))
    e = edges[order]
    start = np.r_[0, np.nonzero(np.any(e[1:] != e[:-1], axis=1))[0] + 1, len(e)]
    boundary = []
    for g0, g1 in zip(start[:-1], start[1:]):
        members = order[g0:g1]
        for m in members:
            t = owner[m]
            if not any(owner[o] != t and nrm[owner[o]] @ nrm[t] > SMOOTH for o in members):
                boundary.append((t, corner[m]))
    chunk["_boundary"] = np.asarray(boundary, dtype=np.int64).reshape(-1, 2)
    return chunk["_boundary"]


def mesh_world(part, chunk, which=None):
    """World triangles (n,3,3) and uv (n,3,2) of a placed mesh fixture; 'which' selects triangles."""
    c, R = frame(part)
    scale = np.asarray(part["size"], float) / np.asarray(chunk["record"]["size"], float)
    I = chunk["indices"] if which is None else chunk["indices"][which]
    T = (chunk["positions"][I[:, :, 0]] * scale) @ R.T + c
    return T, chunk["uv"][I[:, :, 2]].astype(float)


# ----------------------------------------------------------------------------------------------- naming

def family(part):
    name = re.sub(r"^Level 2 ", "", part["name"])
    if part.get("fixtureKind") == "mesh":
        comp = re.sub(r"\d+", "#", part["fixtureComponent"])
        return f"{comp}:{name.rsplit('_', 1)[-1]}"
    name = re.sub(r"[+-]?\d+(\.\d+)?", "#", name)
    name = re.sub(r"\b[NSEW]#?\b", "*", name)
    name = re.sub(r" (North|South|East|West)$", "", name)
    name = re.sub(r"( #)+$", "", name).strip()
    comp = part.get("fixtureComponent")
    return f"{re.sub(chr(92) + 'd+', '#', comp)}/{name}" if comp else name


def owner_of(part, jobs):
    comp = part.get("fixtureComponent")
    if comp:
        return OWNERS.get(jobs.get(comp), f"job {jobs.get(comp)}")
    if ".Level 2 Exit Flume." in part.get("path", ""):
        return "objectives.py (SlidesJSON prefab via builder)"
    return BUILDER


# ----------------------------------------------------------------------------------------------- seam elements

def collect(parts, chunks, tile=TILE):
    """Boundary edge elements as arrays: P0, P1 (m,3), part (m), N surface normal, IN interior direction (in-plane,
    into the face), FG (m,2,3) / FC (m,2) / FV (m,2) grid families, mesh flag; and the tiled Part faces (for inlays)."""
    P0, P1, PI, N, IN, FG, FC, FV, MESH = [], [], [], [], [], [], [], [], []
    faces = defaultdict(list)
    for pi, p in enumerate(parts):
        if tiled_part(p):
            for f in part_faces(p, tile):
                (ei, ej), (hi, hj) = f["e"], f["h"]
                G = np.stack([g for g, _ in f["fams"]])
                C = np.array([c for _, c in f["fams"]])
                for k, v in (("c", f["c"]), ("n", f["n"]), ("e1", ei), ("e2", ej), ("h", (hi, hj)), ("G", G), ("C", C)):
                    faces[k].append(v)
                faces["pi"].append(pi)
                for e, h, o, ho in ((ei, hi, ej, hj), (ej, hj, ei, hi)):
                    for sg in (-1, 1):
                        mid = f["c"] + o * sg * ho
                        P0.append((mid - e * h)[None]), P1.append((mid + e * h)[None]), PI.append([pi])
                        N.append(f["n"][None]), IN.append((-o * sg)[None]), FG.append(G[None]), FC.append(C[None])
                        FV.append(np.ones((1, 2), bool)), MESH.append([False])
        elif tiled_mesh(p):
            chunk = fixture_chunk(p, chunks)
            b = chunk_boundary(chunk)
            if not len(b):
                continue
            T, UV = mesh_world(p, chunk, b[:, 0])
            G, C, valid = tri_families(T, UV)
            nrm = np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0])
            nrm /= np.maximum(np.linalg.norm(nrm, axis=1), 1e-12)[:, None]
            r = np.arange(len(b))
            k = b[:, 1]
            p0, p1, third = T[r, k], T[r, (k + 1) % 3], T[r, (k + 2) % 3]
            t = p1 - p0
            L = np.linalg.norm(t, axis=1)
            keep = (L >= MIN_OVERLAP) & valid.any(1)
            t = t / np.maximum(L, 1e-12)[:, None]
            w = third - p0
            inward = w - t * (w * t).sum(1)[:, None]
            inward /= np.maximum(np.linalg.norm(inward, axis=1), 1e-12)[:, None]
            P0.append(p0[keep]), P1.append(p1[keep]), PI.append(np.full(keep.sum(), pi)), N.append(nrm[keep])
            IN.append(inward[keep]), FG.append(G[keep]), FC.append(C[keep]), FV.append(valid[keep])
            MESH.append(np.ones(keep.sum(), bool))
    if not P0:
        P0, P1, N, IN = [np.zeros((0, 3))] * 4
        PI, FG, FC, FV, MESH = [np.zeros(0, np.int64)], [np.zeros((0, 2, 3))], [np.zeros((0, 2))], [np.zeros((0, 2), bool)], [np.zeros(0, bool)]
    E = {"P0": np.concatenate(P0), "P1": np.concatenate(P1), "part": np.concatenate(PI).astype(np.int64),
         "N": np.concatenate(N), "IN": np.concatenate(IN), "FG": np.concatenate(FG), "FC": np.concatenate(FC),
         "FV": np.concatenate(FV), "mesh": np.concatenate(MESH).astype(bool)}
    F = {k: np.asarray(v) for k, v in faces.items()}
    return E, F


def canonical(v):
    """Rows of v flipped so the first clearly non-zero component is positive (one key for both directions)."""
    v = np.atleast_2d(np.asarray(v, float))
    first = np.argmax(np.abs(v) > 1e-6, axis=1)
    sign = np.sign(v[np.arange(len(v)), first])
    sign[sign == 0] = 1
    return v * sign[:, None]


def nkey(n, either=False):
    """One seam per face pair: two parts can meet on several faces (a slab's room face and its top)."""
    return tuple(np.round(canonical(n)[0] if either else n, 1))


# ----------------------------------------------------------------------------------------------- offsets

def wrap(x):
    return x - np.round(x)


def max_wrap(f0, f1):
    """max |wrap(f)| over a segment where f runs linearly from f0 to f1 (exact: |wrap| peaks at the ends unless the
    range holds a half-integer, where it is 0.5)."""
    lo, hi = np.minimum(f0, f1), np.maximum(f0, f1)
    crosses = (np.floor(hi - .5) >= np.ceil(lo - .5)) | (hi - lo >= 1)
    return np.where(crosses, .5, np.maximum(np.abs(wrap(f0)), np.abs(wrap(f1))))


def across(n, t, away):
    """Unit in-surface direction perpendicular to the seam t on a side with normal n, signed along 'away'."""
    s = np.cross(n, t)
    s /= np.maximum(np.linalg.norm(s, axis=1), 1e-12)[:, None]
    return s * np.where((s * away).sum(1) < 0, -1.0, 1.0)[:, None]


def compare(GA, CA, VA, GB, CB, VB, q0, q1, t, sA, sB, tile=TILE):
    """Vectorised over seam pieces k: worst 'along' / 'across' offset (studs, folded to [0, 0.3]) between side A's grid
    families (GA (k,2,3), CA (k,2), VA (k,2) valid) and side B's along the piece q0 -> q1, matched both ways, plus
    angle / pitch flags. t: seam direction; sA / sB: each side's in-surface direction across the seam, both pointing
    from A to B, so a cove's last facet (a few degrees off its wall) unfolds into the wall's plane. Exact: the phase
    difference of two families is linear along the piece, so its worst wrap is at an end or 0.5."""
    along = np.zeros(len(q0))
    across_ = np.zeros(len(q0))
    angle = np.zeros(len(q0), bool)
    pitch = np.zeros(len(q0), bool)
    r = np.arange(len(q0))
    flat = lambda G, s: np.stack(((G * t[:, None]).sum(2), (G * s[:, None]).sum(2)), 2)     # (k,2,2) in (t, s)
    cut = curved_cut(GA, VA, sA, GB, VB, sB, t)
    for (G1, C1, V1, s1, G2, C2, V2, s2) in ((GA, CA, VA, sA, GB, CB, VB, sB), (GB, CB, VB, sB, GA, CA, VA, sA)):
        F1, F2 = flat(G1, s1), flat(G2, s2)
        n1 = np.linalg.norm(F1, axis=2)
        n2 = np.linalg.norm(F2, axis=2)
        for f in (0, 1):
            g = F1[:, f]
            gn = np.maximum(n1[:, f], 1e-12)
            cos = np.abs(np.einsum("ki,kji->kj", g, F2)) / (gn[:, None] * np.maximum(n2, 1e-12))
            cos = np.where(V2, cos, -1)
            m = np.argmax(cos, axis=1)
            best = cos[r, m]
            sg = np.sign(np.einsum("ki,ki->k", g, F2[r, m]))
            sg[sg == 0] = 1
            g3, h3, c2 = G1[:, f], G2[r, m], C2[r, m]
            f0 = (np.einsum("ki,ki->k", g3, q0) + C1[:, f]) - sg * (np.einsum("ki,ki->k", h3, q0) + c2)
            f1 = (np.einsum("ki,ki->k", g3, q1) + C1[:, f]) - sg * (np.einsum("ki,ki->k", h3, q1) + c2)
            off = np.minimum(max_wrap(f0, f1) / gn, tile / 2)
            bad_angle = best < math.cos(math.radians(2))
            off = np.where(bad_angle, tile / 2, off)
            off = np.where(V1[:, f], off, 0.0)
            angle |= bad_angle & V1[:, f]
            pitch |= V1[:, f] & ~bad_angle & (np.abs(n2[r, m] / gn - 1) > .01)
            cross_seam = np.abs(g[:, 0]) >= np.abs(g[:, 1])
            along = np.where(cross_seam, np.maximum(along, off), along)
            across_ = np.where(cross_seam, across_, np.maximum(across_, off))
    return np.where(cut, 0, along), np.where(cut, 0, across_), angle & ~cut, pitch & ~cut, cut


SIN2 = math.sin(math.radians(2))
COS2 = math.cos(math.radians(2))


def compare_corner(GA, CA, VA, GB, CB, VB, q0, q1, t, tile=TILE):
    """Corner seams: only the lines that CROSS the shared edge have to meet there (the families parallel to it are
    each face's own business: a fold may start a part tile). Per side the crossing family is the one most nearly
    perpendicular to the edge; its phase along the edge is G.q + c. Both perpendicular (within 2 deg): the worst jog
    of the two phases along the piece ('along', exact at the ends, like compare); one only: 'angle', half a tile;
    neither (a curved trim meeting a fold): a cut, counted, not judged. Also a cut: a square field (grid along the
    world axes) met along a line its grid crosses obliquely by a side whose lines do cross that line square - a column
    or a light ring standing on a ceiling, a stop's arc against its wall (the curved-cut rule of curved_cut, 2.8)."""
    r = np.arange(len(q0))

    def crossing(G, V):
        n = np.maximum(np.linalg.norm(G, axis=2), 1e-12)
        cos = np.where(V, np.abs(np.einsum("kfi,ki->kf", G, t)) / n, -1)
        f = np.argmax(cos, axis=1)
        return f, cos[r, f] > COS2, n[r, f]
    fA, perpA, nA = crossing(GA, VA)
    fB, perpB, nB = crossing(GB, VB)

    def field(G, V):
        n = np.maximum(np.linalg.norm(G, axis=2), 1e-12)
        return (~V | (np.abs(G).max(2) / n > 1 - SIN2 * SIN2 / 2)).all(1) & V.any(1)
    fieldA, fieldB = field(GA, VA), field(GB, VB)
    gA, gB = np.einsum("ki,ki->k", GA[r, fA], t), np.einsum("ki,ki->k", GB[r, fB], t)
    sg = np.where(gA * gB < 0, -1.0, 1.0)
    phase = lambda q: (np.einsum("ki,ki->k", GA[r, fA], q) + CA[r, fA]) - sg * (np.einsum("ki,ki->k", GB[r, fB], q) + CB[r, fB])
    off = np.minimum(max_wrap(phase(q0), phase(q1)) / np.maximum(np.abs(gA), 1e-12), tile / 2)
    cut = (~perpA & ~perpB) | (fieldA & ~perpA & perpB) | (fieldB & ~perpB & perpA)
    angle = (perpA ^ perpB) & ~cut
    along = np.where(angle, tile / 2, np.where(cut, 0, off))
    pitch = perpA & perpB & (np.abs(nA / np.maximum(nB, 1e-12) - 1) > .01)
    return along, np.zeros(len(q0)), angle, pitch, cut


def curved_cut(GA, VA, sA, GB, VB, sB, t):
    """A clean cut, not a seam: a square field (a side whose grid runs along the world axes) is met along a line its
    grid crosses obliquely - a curved boundary, like a corner torus's foot on the floor or a ring deck's nosing - by a
    trim whose own grid follows that line (a family of lines parallel to it). No tiling can continue a square grid
    across a curve; the field is cut there and the trim's rows run along the cut, as a tiler lays them. Each side of a
    STRAIGHT aligned seam keeps the full check: a field always has a family parallel to a seam along its own axes, so a
    mis-rotated mesh against it is never a cut."""
    def props(G, V, s):
        par = np.zeros(len(G), bool)
        field = np.ones(len(G), bool)
        for f in (0, 1):
            g = G[:, f]
            n = np.maximum(np.linalg.norm(g, axis=1), 1e-12)
            par |= V[:, f] & (np.abs((g * t).sum(1)) / n < SIN2)
            field &= ~V[:, f] | (np.abs(g).max(1) / n > 1 - SIN2 * SIN2 / 2)
        return par, field & V.any(1)
    parA, fieldA = props(GA, VA, sA)
    parB, fieldB = props(GB, VB, sB)
    return (fieldA & ~parA & parB) | (fieldB & ~parB & parA)


# ----------------------------------------------------------------------------------------------- pairing

def close_pairs(X, r):
    """All (i, j), i < j, with |X[i] - X[j]| <= r: cKDTree.query_pairs without scipy (Blender's Python has none, and
    world_audit check 12 runs this module there). Sorted along one oblique projection, every pair within r lies
    within r * |w| on it; the window candidates are then filtered by the exact distance."""
    if len(X) < 2:
        return np.zeros((0, 2), np.int64)
    w = np.linspace(1.0, 1.7, X.shape[1])          # oblique: no axis-aligned family collapses onto one value
    proj = X @ w
    order = np.argsort(proj, kind="stable")
    ps = proj[order]
    hi = np.searchsorted(ps, ps + r * np.linalg.norm(w), side="right")
    out = []
    start = 0
    while start < len(order):                       # bounded chunks: a dense cluster cannot exhaust memory
        stop = start + 1
        total = 0
        while stop < len(order) and total < 4_000_000:
            total += hi[stop - 1] - stop
            stop += 1
        n = hi[start:stop] - np.arange(start + 1, stop + 1)
        a = np.repeat(np.arange(start, stop), n)
        b = (np.arange(len(a)) - np.repeat(np.cumsum(n) - n, n)) + a + 1
        ia, ib = order[a], order[b]
        ok = ((X[ia] - X[ib]) ** 2).sum(1) <= r * r
        out.append(np.sort(np.stack((ia[ok], ib[ok]), 1), 1))
        start = stop
    return np.concatenate(out).astype(np.int64)


def line_pairs(E):
    """(i, j) element pairs whose boundary edges are collinear (within COLLINEAR) and overlap by MIN_OVERLAP; the
    overlap q0 -> q1 and its direction. No part or normal filter (edge_pairs / corner_pairs add those)."""
    t = E["P1"] - E["P0"]
    L = np.linalg.norm(t, axis=1)
    th = canonical(t / np.maximum(L, 1e-12)[:, None])
    foot = E["P0"] - th * (E["P0"] * th).sum(1)[:, None]
    pairs = close_pairs(np.hstack((th * 20, foot)), COLLINEAR * 1.5)
    i, j = pairs[:, 0], pairs[:, 1]
    ta = t[i] / np.maximum(L[i], 1e-12)[:, None]
    d0 = np.linalg.norm(np.cross(E["P0"][j] - E["P0"][i], ta), axis=1)
    d1 = np.linalg.norm(np.cross(E["P1"][j] - E["P0"][i], ta), axis=1)
    u0 = ((E["P0"][j] - E["P0"][i]) * ta).sum(1)
    u1 = ((E["P1"][j] - E["P0"][i]) * ta).sum(1)
    lo = np.maximum(0, np.minimum(u0, u1))
    hi = np.minimum(L[i], np.maximum(u0, u1))
    ok = (d0 < COLLINEAR) & (d1 < COLLINEAR) & (hi - lo >= MIN_OVERLAP)
    i, j, lo, hi, ta = i[ok], j[ok], lo[ok], hi[ok], ta[ok]
    return i, j, E["P0"][i] + ta * lo[:, None], E["P0"][i] + ta * hi[:, None], ta


def edge_pairs(E, lines=None):
    """(i, j) element pairs whose boundary edges are collinear and overlap, with the faces on opposite sides; the
    overlap q0 -> q1 and its direction."""
    i, j, q0, q1, ta = line_pairs(E) if lines is None else lines
    ok = (E["part"][i] != E["part"][j]) & ((E["N"][i] * E["N"][j]).sum(1) > SMOOTH)
    ok &= (E["IN"][i] * E["IN"][j]).sum(1) < -.5
    return i[ok], j[ok], q0[ok], q1[ok], ta[ok]


CORNER_DOT = .5         # corner seams: the two faces meet at 60..120 deg


def corner_pairs(E, lines=None):
    """(i, j) element pairs that fold round one shared edge at 60..120 deg: two faces of different parts, or two faces
    of one Part (its own edges; a mesh's own creases are its UVs' business). Only a real corner counts: both faces open
    to the same space, an inside corner (each face rises from the other's side: N_i.IN_j > 0 and N_j.IN_i > 0) or an
    outside one (both < 0). A face whose back meets the other (mixed signs) is never seen together with it."""
    i, j, q0, q1, ta = line_pairs(E) if lines is None else lines
    dn = (E["N"][i] * E["N"][j]).sum(1)
    a = (E["N"][i] * E["IN"][j]).sum(1)
    b = (E["N"][j] * E["IN"][i]).sum(1)
    same = E["part"][i] == E["part"][j]
    ok = (np.abs(dn) < CORNER_DOT) & (np.abs(a) > .5) & (np.abs(b) > .5) & (np.sign(a) == np.sign(b))
    ok &= ~same | ~E["mesh"][i]
    return i[ok], j[ok], q0[ok], q1[ok], ta[ok]


T_CELL = 16.0


def corner_inlay_pairs(E, F):
    """T-corners: a boundary edge of one face lying INSIDE a perpendicular tiled Part face of another part, the face
    rising off the Part face's visible side (a sill top against its jamb, a lintel soffit against the wall end face
    above a door, a plinth standing on a floor). The edge is clipped to the Part face shrunk by MARGIN, so an edge
    along the Part face's own boundary stays a corner_pairs seam. Returns element, face, clipped q0, q1, direction."""
    z = np.zeros(0, np.int64)
    if not len(F.get("pi", ())) or not len(E["P0"]):
        return z, z, np.zeros((0, 3)), np.zeros((0, 3)), np.zeros((0, 3))
    es, fs = [z], [z]
    for a in range(3):
        u, w = [k for k in range(3) if k != a]
        on = np.nonzero(np.abs(F["n"][:, a]) > 1 - 1e-6)[0]
        cand = np.nonzero((np.abs(E["N"][:, a]) < CORNER_DOT) & (np.abs(E["IN"][:, a]) > .5)
                          & (np.abs(E["P0"][:, a] - E["P1"][:, a]) < COLLINEAR))[0]
        if not len(on) or not len(cand):
            continue
        cells = defaultdict(list)
        lo = np.floor(np.minimum(E["P0"][cand][:, [u, w]], E["P1"][cand][:, [u, w]]) / T_CELL).astype(np.int64)
        hi = np.floor(np.maximum(E["P0"][cand][:, [u, w]], E["P1"][cand][:, [u, w]]) / T_CELL).astype(np.int64)
        key = np.round((E["P0"][cand, a] + E["P1"][cand, a]) / 2 / COLLINEAR).astype(np.int64)
        for e, k, l, h in zip(cand, key, lo, hi):
            for cu in range(l[0], h[0] + 1):
                for cw in range(l[1], h[1] + 1):
                    cells[(k, cu, cw)].append(e)
        ext = np.abs(F["e1"][on][:, [u, w]]) * F["h"][on, :1] + np.abs(F["e2"][on][:, [u, w]]) * F["h"][on, 1:]
        flo = np.floor((F["c"][on][:, [u, w]] - ext) / T_CELL).astype(np.int64)
        fhi = np.floor((F["c"][on][:, [u, w]] + ext) / T_CELL).astype(np.int64)
        fk = np.round(F["c"][on, a] / COLLINEAR).astype(np.int64)
        for f, k, l, h in zip(on, fk, flo, fhi):
            hit = [e for kk in (k - 1, k, k + 1) for cu in range(l[0], h[0] + 1) for cw in range(l[1], h[1] + 1)
                   for e in cells.get((kk, cu, cw), ())]
            if hit:
                hit = np.unique(hit)
                es.append(hit), fs.append(np.full(len(hit), f))
    e, f = np.concatenate(es).astype(np.int64), np.concatenate(fs).astype(np.int64)
    rise = (E["IN"][e] * F["n"][f]).sum(1)
    ok = (E["part"][e] != F["pi"][f]) & (rise > .5)          # IN is geometric (no winding): off the face's front
    P0, d = E["P0"][e], E["P1"][e] - E["P0"][e]
    ok &= np.abs(((P0 - F["c"][f]) * F["n"][f]).sum(1)) < COLLINEAR
    t0, t1 = np.zeros(len(e)), np.ones(len(e))
    for ax, h in (("e1", F["h"][f, 0]), ("e2", F["h"][f, 1])):      # clip to the shrunk rectangle (Liang-Barsky)
        p0 = ((P0 - F["c"][f]) * F[ax][f]).sum(1)
        dp = (d * F[ax][f]).sum(1)
        lim = h - MARGIN
        flat = np.abs(dp) < 1e-12
        ok &= ~flat | (np.abs(p0) < lim)
        dps = np.where(flat, 1, dp)
        ta, tb = (-lim - p0) / dps, (lim - p0) / dps
        t0 = np.where(flat, t0, np.maximum(t0, np.minimum(ta, tb)))
        t1 = np.where(flat, t1, np.minimum(t1, np.maximum(ta, tb)))
    L = np.linalg.norm(d, axis=1)
    ok &= (t1 - t0) * L >= MIN_OVERLAP
    e, f, t0, t1, d, P0, L = e[ok], f[ok], t0[ok], t1[ok], d[ok], P0[ok], L[ok]
    return e, f, P0 + d * t0[:, None], P0 + d * t1[:, None], d / np.maximum(L, 1e-12)[:, None]


def inlay_pairs(E, F):
    """(element, face) pairs: a boundary edge strictly inside a coplanar tiled Part face of another part. The element's
    own facet may lean up to ~20 deg off the face (a cove's last facet ends tangent to its wall), so candidates are
    found by the face's plane, not the element's. A facet parallel to the face may stand up to INLAY_PLANE proud."""
    z = np.zeros(0, np.int64)
    if not len(F.get("pi", ())) or not len(E["P0"]):
        return z, z
    mid = (E["P0"] + E["P1"]) / 2
    es, fs = [z], [z]
    aligned = np.zeros(len(F["pi"]), bool)
    for a in range(3):
        on = np.nonzero(np.abs(F["n"][:, a]) > 1 - 1e-6)[0]
        aligned[on] = True
        cand = np.nonzero(np.abs(E["N"][:, a]) > SMOOTH)[0]
        order = cand[np.argsort(mid[cand, a])]
        key = mid[order, a]
        d = F["c"][on, a]
        lo, hi = np.searchsorted(key, d - INLAY_PLANE), np.searchsorted(key, d + INLAY_PLANE)
        n = hi - lo
        if n.sum():
            fs.append(np.repeat(on, n))
            es.append(order[np.concatenate([np.arange(x, y) for x, y in zip(lo, hi)])])
    for k in np.nonzero(~aligned)[0]:         # tilted floors, oblique parts: brute force
        hit = np.nonzero(np.abs((mid - F["c"][k]) @ F["n"][k]) < INLAY_PLANE)[0]
        es.append(hit), fs.append(np.full(len(hit), k))
    e, f = np.concatenate(es).astype(np.int64), np.concatenate(fs).astype(np.int64)
    dot = (E["N"][e] * F["n"][f]).sum(1)
    ok = (E["part"][e] != F["pi"][f]) & (dot > SMOOTH)
    plane = np.where(dot > PARALLEL, INLAY_PLANE, COLLINEAR)
    for P in (E["P0"], E["P1"]):
        d = P[e] - F["c"][f]
        ok &= np.abs((d * F["n"][f]).sum(1)) < plane
        ok &= np.abs((d * F["e1"][f]).sum(1)) < F["h"][f, 0] - MARGIN
        ok &= np.abs((d * F["e2"][f]).sum(1)) < F["h"][f, 1] - MARGIN
    return e[ok], f[ok]


def flat_mesh_triangles(parts, chunks):
    """Every tiled mesh triangle whose plane is axis-aligned (decks, floors, wall bands and ceilings inside kit
    meshes): world corners, normal, part, families. Inlays on those are found like inlays on Part faces."""
    T, N, PI, G, C, V = [], [], [], [], [], []
    for pi, p in enumerate(parts):
        if not tiled_mesh(p):
            continue
        t, uv = mesh_world(p, fixture_chunk(p, chunks))
        n = np.cross(t[:, 1] - t[:, 0], t[:, 2] - t[:, 0])
        n /= np.maximum(np.linalg.norm(n, axis=1), 1e-12)[:, None]
        flat = np.abs(n).max(1) > 1 - 1e-6
        if not flat.any():
            continue
        g, c, v = tri_families(t[flat], uv[flat])
        T.append(t[flat]), N.append(n[flat]), PI.append(np.full(flat.sum(), pi)), G.append(g), C.append(c), V.append(v)
    if not T:
        return None
    return {"T": np.concatenate(T), "N": np.concatenate(N), "part": np.concatenate(PI), "G": np.concatenate(G),
            "C": np.concatenate(C), "V": np.concatenate(V)}


MESH_CELL = 4.0


def mesh_inlay_pairs(E, M):
    """(element, triangle) pairs: a boundary edge whose far side (0.02 off the edge, away from its own face) lies
    strictly inside a coplanar, same-facing flat triangle of ANOTHER tiled mesh (a torus foot on a ring deck)."""
    z = np.zeros(0, np.int64)
    if M is None or not len(E["P0"]):
        return z, z
    T, N = M["T"], M["N"]
    axis = np.argmax(np.abs(N), 1)
    es, ts = [z], [z]
    probe = (E["P0"] + E["P1"]) / 2 - E["IN"] * .02
    for a in range(3):
        sel = np.nonzero(axis == a)[0]
        if not len(sel):
            continue
        u, w = [k for k in range(3) if k != a]
        lo = np.floor(T[sel][:, :, [u, w]].min(1) / MESH_CELL).astype(np.int64)
        hi = np.floor(T[sel][:, :, [u, w]].max(1) / MESH_CELL).astype(np.int64)
        cells = {}
        for k, (l, h) in enumerate(zip(lo, hi)):
            for cu in range(l[0], h[0] + 1):
                for cw in range(l[1], h[1] + 1):
                    cells.setdefault((cu, cw), []).append(sel[k])
        cand = np.nonzero(np.abs(E["N"][:, a]) > SMOOTH)[0]
        cu = np.floor(probe[cand, u] / MESH_CELL).astype(np.int64)
        cw = np.floor(probe[cand, w] / MESH_CELL).astype(np.int64)
        for e, x, y in zip(cand, cu, cw):
            hit = cells.get((x, y))
            if hit:
                es.append(np.full(len(hit), e)), ts.append(np.asarray(hit))
    e, t = np.concatenate(es).astype(np.int64), np.concatenate(ts).astype(np.int64)
    keep = [np.zeros(0, np.int64)]
    for s in range(0, len(e), 2_000_000):            # plane filter first, in chunks: a cell can pair ~20M candidates
        es_, ts_ = e[s:s + 2_000_000], t[s:s + 2_000_000]
        dot = (E["N"][es_] * N[ts_]).sum(1)
        ok = (E["part"][es_] != M["part"][ts_]) & (dot > SMOOTH)
        ok &= np.abs(((probe[es_] - T[ts_, 0]) * N[ts_]).sum(1)) < np.where(dot > PARALLEL, INLAY_PLANE, COLLINEAR)
        keep.append(s + np.nonzero(ok)[0])
    e, t = e[np.concatenate(keep)], t[np.concatenate(keep)]
    p = probe[e]
    ok = np.ones(len(e), bool)
    # strictly inside the triangle (barycentric, in its own plane)
    v0, v1, v2 = T[t, 0], T[t, 1], T[t, 2]
    d00 = ((v1 - v0) ** 2).sum(1); d01 = ((v1 - v0) * (v2 - v0)).sum(1); d11 = ((v2 - v0) ** 2).sum(1)
    d20 = ((p - v0) * (v1 - v0)).sum(1); d21 = ((p - v0) * (v2 - v0)).sum(1)
    den = np.where(np.abs(d00 * d11 - d01 * d01) > 1e-12, d00 * d11 - d01 * d01, 1)
    b1 = (d11 * d20 - d01 * d21) / den
    b2 = (d00 * d21 - d01 * d20) / den
    ok &= (b1 > 1e-6) & (b2 > 1e-6) & (b1 + b2 < 1 - 1e-6)
    e, t = e[ok], t[ok]
    keep = np.unique(e, return_index=True)[1]          # one host triangle per element
    return e[keep], t[keep]


# ----------------------------------------------------------------------------------------------- exposure

def basin_depth(h):
    """Kit World Builder basinDepth: the pool floor's deepest point under FloorY (0 for dry floors)."""
    if h.get("Role") == "Small":
        return 4.0                                     # chamber water and aqua floor
    if h["Type"] in ("Arrival", "PumpHall") or (h.get("PoolType") == "Dry" and h["Type"] != "PaddlingRoom"):
        return 0.0
    return .8 if h["Type"] == "PaddlingRoom" else min(max(h.get("DeepEnd") or 1.6, 1.6), 3.5)


def air_boxes(layout):
    """Where a player's eye can be inside a hall: its rectangle (walls included) from the basin floor up to the roof
    band, as world_check.volume_boxes otherwise."""
    boxes = []
    for b, h in zip(wc.volume_boxes({"Halls": layout["Halls"], "Corridors": []}), layout["Halls"]):
        boxes.append((b[0], h["FloorY"] - basin_depth(h) - .1, b[2], b[3], b[4], b[5]))
    return boxes


BORE = {True: (13.0, 17.0), False: (6.0, 6.0)}     # (axis height over the floor, radius): round tunnel, pipe


def air_bores(layout):
    """A corridor's air is its bore, not its box: (a, b, radius, axis height) segments along the axis, the axis at
    floor + 13 (tunnel, r 17) or floor + 6 (pipe, r 6), rising with a stair corridor's floor; in_air also cuts it 2.1
    under the floor (a wet tunnel's channel)."""
    out = []
    for c in layout["Corridors"]:
        cy, r = BORE[c["Width"] > 12]
        p0 = [c["From"], c["FromY"] + cy, c["Cross"]] if c["Axis"] == "X" else [c["Cross"], c["FromY"] + cy, c["From"]]
        p1 = [c["To"], c["ToY"] + cy, c["Cross"]] if c["Axis"] == "X" else [c["Cross"], c["ToY"] + cy, c["To"]]
        out.append((p0, p1, r + .1, cy))
    return out


def closed(chunk):
    """A chunk is a closed solid when every welded edge has a partner (no free edge). Cached on the chunk."""
    if "_closed" not in chunk:
        P, I = chunk["positions"], chunk["indices"]
        _, vid = np.unique(np.round(P / .002).astype(np.int64), axis=0, return_inverse=True)
        vid = vid.reshape(-1)[I[:, :, 0]]
        e = np.sort(np.concatenate([np.stack((vid[:, k], vid[:, (k + 1) % 3]), 1) for k in range(3)]), 1)
        _, count = np.unique(e, axis=0, return_counts=True)
        chunk["_closed"] = bool(len(e)) and not (count == 1).any()
    return chunk["_closed"]


def boundary_loops(chunk):
    """The free edges of a chunk (welded as in closed()) chained into loops of chunk-local points, or None when they
    do not chain into simple loops. Cached on the chunk."""
    if "_loops" not in chunk:
        P, I = chunk["positions"], chunk["indices"]
        _, first, vid = np.unique(np.round(P / .002).astype(np.int64), axis=0, return_index=True, return_inverse=True)
        vid = vid.reshape(-1)[I[:, :, 0]]
        e = np.sort(np.concatenate([np.stack((vid[:, k], vid[:, (k + 1) % 3]), 1) for k in range(3)]), 1)
        u, count = np.unique(e, axis=0, return_counts=True)
        nbr = defaultdict(list)
        for a, b in u[count == 1]:
            nbr[int(a)].append(int(b))
            nbr[int(b)].append(int(a))
        loops = []
        if all(len(v) == 2 for v in nbr.values()):
            seen = set()
            for start in nbr:
                if start in seen:
                    continue
                loop, prev, cur = [start], None, start
                seen.add(start)
                while True:
                    a, b = nbr[cur]
                    nxt = b if a == prev else a
                    if nxt == start or nxt in seen:
                        break
                    loop.append(nxt)
                    seen.add(nxt)
                    prev, cur = cur, nxt
                loops.append(np.asarray(P[first[loop]], float))
        chunk["_loops"] = loops if all(len(v) == 2 for v in nbr.values()) else None
    return chunk["_loops"]


PARITY_DIRS = np.array(((.5773, .6123, .5401), (-.7071, .3162, .6325), (.2673, -.8018, .5345)))
PARITY_DIRS /= np.linalg.norm(PARITY_DIRS, axis=1)[:, None]


def inside_solid(pts, T):
    """Strictly inside the closed triangle soup T (n,3,3)? Ray parity: an odd number of crossings along a generic
    direction, majority of three. Independent of how the faces are wound: the swerve kit's tail caps face INTO their own
    solid, and a winding number (solid angles) reads a point beside such a cap as outside."""
    if not len(T) or not len(pts):
        return np.zeros(len(pts), bool)
    v0, e1, e2 = T[:, 0], T[:, 1] - T[:, 0], T[:, 2] - T[:, 0]
    votes = np.zeros(len(pts), np.int64)
    step = max(1, 2_000_000 // len(T))
    for d in PARITY_DIRS:
        p = np.cross(d, e2)
        det = (e1 * p).sum(1)
        ok = np.abs(det) > 1e-12
        inv = np.where(ok, 1 / np.where(ok, det, 1), 0)
        for s in range(0, len(pts), step):
            tv = pts[s:s + step, None, :] - v0[None]
            u = (tv * p[None]).sum(-1) * inv
            q = np.cross(tv, e1[None])
            v = (q @ d) * inv
            t = (q * e2[None]).sum(-1) * inv
            votes[s:s + step] += ((ok & (u >= 0) & (v >= 0) & (u + v <= 1) & (t > 1e-9)).sum(1) % 2)
    return votes >= 2


class Exposure:
    """Is a point on a seam seen from the playable space? (see the module docstring)"""

    def __init__(self, parts, layout, chunks):
        self.parts, self.chunks = parts, chunks
        boxes = air_boxes(layout) if layout else []
        # where a ray may END: a hall's room inside its wall faces (WALL_DEPTH in from its rectangle). A sample may sit
        # in the wall band (a door reveal), but a ray that never leaves the band runs up a void between a hole's jamb
        # and the tunnel bore behind its collar, which nobody sees.
        inner = [(b[0] + WALL_DEPTH, b[1], b[2] + WALL_DEPTH, b[3] - WALL_DEPTH, b[4], b[5] - WALL_DEPTH) for b in boxes]
        flume = [p for p in parts if ".Level 2 Exit Flume." in p.get("path", "") and p["transparency"] < .98]
        if flume:           # the exit flume and its recovery room lie outside every hall: each visible piece's box
            lo, hi = self._aabbs(flume)
            boxes += [tuple(a - .5) + tuple(b + .5) for a, b in zip(lo, hi)]
            inner += boxes[len(inner):]
        self.air = np.asarray(boxes, float).reshape(-1, 6)
        self.inner = np.asarray(inner, float).reshape(-1, 6)
        bores = air_bores(layout) if layout else []
        self.bore_a = np.asarray([b[0] for b in bores], float).reshape(-1, 3)
        self.bore_b = np.asarray([b[1] for b in bores], float).reshape(-1, 3)
        self.bore_r = np.asarray([b[2] for b in bores], float)
        self.bore_cy = np.asarray([b[3] for b in bores], float)
        self.vis = [i for i, p in enumerate(parts) if p["transparency"] < .98]
        self.lo, self.hi = self._aabbs([parts[i] for i in self.vis])
        self._tris = {}
        self._sealed = {}

    def sealed(self, i):
        """Triangles that close an OPEN kit mesh whose every free edge lies on visible solid Parts, or None. A swerve
        skin leaves the facets that lie on the hall wall slab to the slab (a mesh face there would z-fight it), so the
        skin and the slab together enclose its solid: its triangles plus a fan over each boundary loop then serve the
        inside test like a closed chunk's. Sealed only when every boundary point (0.25 apart) AND every fan
        triangle's centroid lies on the surface of a visible solid Part (within SEAL_TOL): a tube's rim or a light
        well's opening has its fan's centroids in the air and stays open."""
        if i not in self._sealed:
            p = self.parts[i]
            loops = boundary_loops(fixture_chunk(p, self.chunks))
            out = None
            if loops:
                c, R = frame(p)
                scale = np.asarray(p["size"], float) / np.asarray(fixture_chunk(p, self.chunks)["record"]["size"], float)
                caps, pts = [], []
                for L in loops:
                    W = (L * scale) @ R.T + c
                    mid = W.mean(0)
                    for a, b in zip(W, np.roll(W, -1, 0)):
                        caps.append((mid, a, b))
                        n = max(1, math.ceil(float(np.linalg.norm(b - a)) / .25))
                        pts += [a + (b - a) * k / n for k in range(n)]
                        pts.append((mid + a + b) / 3)
                if self.on_part_surfaces(np.asarray(pts)):
                    out = np.concatenate([self.tris(i)[0], np.asarray(caps, float)])
            self._sealed[i] = out
        return self._sealed[i]

    def on_part_surfaces(self, pts, tol=None):
        """Does every point lie on the surface of some visible solid block Part (inside its box grown by tol, within
        tol of a face)?"""
        tol = SEAL_TOL if tol is None else tol
        lo, hi = pts.min(0) - tol, pts.max(0) + tol
        on = np.zeros(len(pts), bool)
        for k in np.nonzero(np.all(self.lo <= hi, 1) & np.all(self.hi >= lo, 1))[0]:
            p = self.parts[self.vis[k]]
            if p["class"] == "MeshPart" or "Block" not in str(p.get("shape", "Block")):
                continue
            c, Rm = frame(p)
            d = np.abs((pts - c) @ Rm) - np.asarray(p["size"], float) / 2
            on |= np.all(d <= tol, 1) & (d.max(1) >= -tol)
        return bool(on.all())

    @staticmethod
    def _aabbs(parts):
        lo, hi = [], []
        for p in parts:
            c, R = frame(p)
            ext = np.abs(R) @ (np.asarray(p["size"], float) / 2)
            lo.append(c - ext)
            hi.append(c + ext)
        return np.asarray(lo).reshape(-1, 3), np.asarray(hi).reshape(-1, 3)

    def tris(self, i):
        if i not in self._tris:
            p = self.parts[i]
            if p.get("fixtureKind") == "mesh":
                t = mesh_world(p, fixture_chunk(p, self.chunks))[0]
            elif p["class"] == "MeshPart":
                t = np.zeros((0, 3, 3))
            else:
                t = np.asarray(wc.part_triangles(p), float)
            self._tris[i] = (t, t.min(1) if len(t) else np.zeros((0, 3)), t.max(1) if len(t) else np.zeros((0, 3)))
        return self._tris[i]

    def in_air(self, pts, inner=False):
        a = self.inner if inner else self.air
        if not len(a) and not len(self.bore_r):
            return np.ones(len(pts), bool)
        inside = ((pts[:, None, 0] >= a[None, :, 0]) & (pts[:, None, 1] >= a[None, :, 1]) & (pts[:, None, 2] >= a[None, :, 2])
                  & (pts[:, None, 0] <= a[None, :, 3]) & (pts[:, None, 1] <= a[None, :, 4])
                  & (pts[:, None, 2] <= a[None, :, 5])).any(1)
        if len(self.bore_r):
            ab = self.bore_b - self.bore_a
            t = np.clip(np.einsum("pkj,kj->pk", pts[:, None, :] - self.bore_a[None], ab) / (ab * ab).sum(1)[None], 0, 1)
            axis = self.bore_a[None] + t[..., None] * ab[None]
            d = np.linalg.norm(pts[:, None, :] - axis, axis=2)
            # below the corridor floor the bore is solid (threshold, ledges, water floor): air from 2.1 under it
            floor = axis[..., 1] - self.bore_cy[None]
            inside |= ((d <= self.bore_r[None]) & (pts[:, None, 1] >= floor - 2.1)).any(1)
        return inside

    def seen(self, pts, n):
        """Visible flags for points pts (k,3) on a face with outward normal n."""
        if not len(pts):
            return np.zeros(0, bool)
        R = EXPOSURE_RANGE
        lo, hi = pts.min(0) - R - .1, pts.max(0) + R + .1
        near = np.nonzero(np.all(self.lo <= hi, 1) & np.all(self.hi >= lo, 1))[0]
        o = pts + n * .02
        ok = self.in_air(o)
        T, Tlo, Thi = [np.zeros((0, 3, 3))], [np.zeros((0, 3))], [np.zeros((0, 3))]
        for k in near:
            i = self.vis[k]
            p = self.parts[i]
            if p["class"] != "MeshPart" and "Block" in str(p.get("shape", "Block")):
                c, Rm = frame(p)
                local = (o - c) @ Rm
                ok &= ~np.all(np.abs(local) < np.asarray(p["size"], float) / 2 - 1e-3, 1)
            elif p.get("fixtureKind") == "mesh":
                # a closed kit solid (a cove run, a stop) is solid, not air: a face backed by the next piece's coplanar
                # cap is sealed, and rays from inside it slip out along that cap. So is an open skin sealed by the
                # Parts its free edges lie on (a swerve skin on the hall wall slab, sealed()).
                box = np.all((o >= self.lo[k] - 1e-3) & (o <= self.hi[k] + 1e-3), 1) & ok
                if box.any():
                    solid = self.tris(i)[0] if closed(fixture_chunk(p, self.chunks)) else self.sealed(i)
                    if solid is not None:
                        ok[box] = ~inside_solid(o[box], solid)
            t, a, b = self.tris(i)
            T.append(t), Tlo.append(a), Thi.append(b)
        seen = np.zeros(len(pts), bool)
        T, Tlo, Thi = np.concatenate(T), np.concatenate(Tlo), np.concatenate(Thi)
        dirs = EXPOSURE_DIRS[EXPOSURE_DIRS @ n >= .25]
        dirs = dirs[np.argsort(-(dirs @ n))]
        for i in np.nonzero(ok)[0]:
            m = np.all(Tlo <= o[i] + R, 1) & np.all(Thi >= o[i] - R, 1)
            Ti = T[m]
            for s in range(0, len(dirs), 8):
                d = dirs[s:s + 8]
                org = np.repeat(o[i][None], len(d), 0)
                free = ~ca.ray_hits(org, d, Ti, t_min=1e-4, t_max=R) & self.in_air(org + d * R, inner=True)
                if free.any():
                    seen[i] = True
                    break
        return seen


# ----------------------------------------------------------------------------------------------- audit

def seam_pieces(parts, chunks, tile=TILE, corners=False):
    """Every seam piece of the world, as parallel arrays (no exposure yet): tuples (kind, pa, pb, q0, q1, n, side, both,
    along, across, angle, pitch, cut). corners=True adds the 'corner' kind (audit_parts judges it; off by default so
    a caller that judges every piece without exposure, like test_level2_exit_bore, keeps its contract)."""
    return [p[:13] for p in _pieces(parts, chunks, tile, corners)]


def _pieces(parts, chunks, tile, corners):
    """seam_pieces plus, per piece, where its two faces are sampled for exposure: (sA, nA, sB, nB, sB2) = the
    in-surface step from the seam line into each face, that face's normal, and a second step into face B (T-corners: the
    Part face on the other side of the edge; zero otherwise). A seam is only seen where BOTH faces are."""
    E, F = collect(parts, chunks, tile)
    out = []
    lines = line_pairs(E)
    i, j, q0, q1, t = edge_pairs(E, lines)
    along, across_, angle, pitch, cut = compare(E["FG"][i], E["FC"][i], E["FV"][i], E["FG"][j], E["FC"][j], E["FV"][j],
                                           q0, q1, t, across(E["N"][i], t, -E["IN"][i]), across(E["N"][j], t, E["IN"][j]), tile)
    both = E["mesh"][i] & E["mesh"][j]
    n = np.where((E["mesh"][i] & ~E["mesh"][j])[:, None], E["N"][j], E["N"][i])
    out.append(("edge", E["part"][i], E["part"][j], q0, q1, n, np.zeros_like(n), both, along, across_, angle, pitch, cut,
                E["IN"][i], E["N"][i], E["IN"][j], E["N"][j], np.zeros_like(n)))
    e, f = inlay_pairs(E, F)
    q0, q1 = E["P0"][e], E["P1"][e]
    t = (q1 - q0) / np.maximum(np.linalg.norm(q1 - q0, axis=1), 1e-12)[:, None]
    fn = F["n"][f] if len(f) else np.zeros((0, 3))
    along, across_, angle, pitch, cut = compare(E["FG"][e], E["FC"][e], E["FV"][e], F["G"][f] if len(f) else np.zeros((0, 2, 3)),
                                           F["C"][f] if len(f) else np.zeros((0, 2)), np.ones((len(f), 2), bool),
                                           q0, q1, t, across(E["N"][e], t, -E["IN"][e]), across(fn, t, -E["IN"][e]), tile)
    out.append(("inlay", E["part"][e], F["pi"][f] if len(f) else f, q0, q1, fn,
                -E["IN"][e], np.zeros(len(e), bool), along, across_, angle, pitch, cut,
                E["IN"][e], E["N"][e], -E["IN"][e], fn, np.zeros_like(fn)))
    M = flat_mesh_triangles(parts, chunks)
    e, k = mesh_inlay_pairs(E, M)
    if len(e):
        q0, q1 = E["P0"][e], E["P1"][e]
        t = (q1 - q0) / np.maximum(np.linalg.norm(q1 - q0, axis=1), 1e-12)[:, None]
        tn = M["N"][k]
        along, across_, angle, pitch, cut = compare(E["FG"][e], E["FC"][e], E["FV"][e], M["G"][k], M["C"][k], M["V"][k],
                                               q0, q1, t, across(E["N"][e], t, -E["IN"][e]), across(tn, t, -E["IN"][e]), tile)
        out.append(("inlay", E["part"][e], M["part"][k], q0, q1, tn, -E["IN"][e], np.zeros(len(e), bool),
                    along, across_, angle, pitch, cut, E["IN"][e], E["N"][e], -E["IN"][e], tn, np.zeros_like(tn)))
    if corners:
        i, j, q0, q1, t = corner_pairs(E, lines)
        along, across_, angle, pitch, cut = compare_corner(E["FG"][i], E["FC"][i], E["FV"][i], E["FG"][j], E["FC"][j],
                                                           E["FV"][j], q0, q1, t, tile)
        bis = E["N"][i] + E["N"][j]          # the corner's bisector: where a camera sees both faces
        bis /= np.maximum(np.linalg.norm(bis, axis=1), 1e-12)[:, None]
        out.append(("corner", E["part"][i], E["part"][j], q0, q1, bis, np.zeros_like(bis), E["mesh"][i] & E["mesh"][j],
                    along, across_, angle, pitch, cut, E["IN"][i], E["N"][i], E["IN"][j], E["N"][j], np.zeros_like(bis)))
        # T-corners: the Part face is sampled on both sides of the edge (the side under A's solid is hidden anyway)
        e, f, q0, q1, t = corner_inlay_pairs(E, F)
        if len(e):
            fn = F["n"][f]
            along, across_, angle, pitch, cut = compare_corner(E["FG"][e], E["FC"][e], E["FV"][e], F["G"][f], F["C"][f],
                                                               np.ones((len(f), 2), bool), q0, q1, t, tile)
            sB = E["N"][e] - fn * (E["N"][e] * fn).sum(1)[:, None]
            sB /= np.maximum(np.linalg.norm(sB, axis=1), 1e-12)[:, None]
            bis = E["N"][e] + fn
            bis /= np.maximum(np.linalg.norm(bis, axis=1), 1e-12)[:, None]
            out.append(("corner", E["part"][e], F["pi"][f], q0, q1, bis, np.zeros_like(bis), np.zeros(len(e), bool),
                        along, across_, angle, pitch, cut, E["IN"][e], E["N"][e], sB, fn, -sB))
    return out


def audit_parts(parts, layout, chunks, max_offset=MAX_OFFSET, min_exposed=MIN_EXPOSED, stats=None, jobs=None,
                tile=TILE):
    seams = defaultdict(list)
    st = Counter()
    for kind, pa, pb, q0, q1, n, _, both, along, across, angle, pitch, cut, sA, nA, sB, nB, sB2 in _pieces(
            parts, chunks, tile, True):
        st["cut_pieces"] += int(cut.sum())
        st["cut_length_x10"] += int(round(10 * np.linalg.norm(q1 - q0, axis=1)[cut].sum()))
        st[f"pieces_{kind}"] += len(pa)
        for k in range(len(pa)):
            key = (int(pa[k]), int(pb[k]), kind, nkey(n[k], bool(both[k])))
            seams[key].append((along[k], across[k], angle[k], pitch[k], q0[k], q1[k], n[k],
                               (sA[k], nA[k], sB[k], nB[k], sB2[k]), both[k]))
    expo = None
    findings = []

    jobs = jobs if jobs is not None else {comp: ch["job"] for (comp, _), ch in chunks.items() if "job" in ch}
    for (pa, pb, kind, _), items in seams.items():
        st["seams"] += 1
        st[f"seams_{kind}"] += 1
        along = max(x[0] for x in items)
        across = max(x[1] for x in items)
        if max(along, across) <= max_offset:
            continue
        st["stepping"] += 1
        if expo is None:
            expo = Exposure(parts, layout, chunks)
        flags = sorted(({"angle"} if any(x[2] for x in items) else set()) | ({"pitch"} if any(x[3] for x in items) else set()))
        exposed = length = 0.0
        best = None
        for a_, c_, _, _, q0, q1, n, (sA, nA, sB, nB, sB2), both in items:
            if max(a_, c_) <= max_offset:
                continue
            L = float(np.linalg.norm(q1 - q0))
            k = int(min(EXPOSURE_CAP, max(2, math.ceil(L / EXPOSURE_STEP))))
            line = q0 + (q1 - q0) * ((np.arange(k) + .5) / k)[:, None]
            # each face sampled SIDE_STEP into itself, never on the seam line: a line sample sits on the shared
            # boundary of whatever backs the two faces (two abutting ceiling slabs, a wall and the next cove) and is
            # strictly inside neither, so its rays ran inside them. A step is seen only where both faces are.
            vis = expo.seen(line + sA * SIDE_STEP, nA)
            if vis.any():
                visB = expo.seen(line[vis] + sB * SIDE_STEP, nB)
                if sB2.any() and not visB.all():
                    visB[~visB] = expo.seen(line[vis][~visB] + sB2 * SIDE_STEP, nB)
                vis[vis] = visB
            pts = line + sA * SIDE_STEP
            ex = L * vis.mean()
            exposed += ex
            length += L
            if vis.any() and (best is None or ex > best[0]):
                w = np.nonzero(vis)[0]
                best = (ex, pts[w[len(w) // 2]], n)
        if exposed < min_exposed:
            continue
        st["findings"] += 1
        A, B = parts[pa], parts[pb]
        fa, fb = family(A), family(B)
        if (fb, B["name"]) < (fa, A["name"]):
            A, B, fa, fb = B, A, fb, fa
        findings.append({
            "kind": kind, "category": f"{fa} | {fb}",
            "a": {"name": A["name"], "family": fa, "component": A.get("fixtureComponent"), "class": A["class"],
                  "owner": owner_of(A, jobs), "path": A.get("path")},
            "b": {"name": B["name"], "family": fb, "component": B.get("fixtureComponent"), "class": B["class"],
                  "owner": owner_of(B, jobs), "path": B.get("path")},
            "along": round(float(along), 4), "across": round(float(across), 4),
            "offset": round(float(max(along, across)), 4), "flags": flags,
            "exposed": round(exposed, 3), "length": round(length, 3),
            "at": [round(float(v), 2) for v in best[1]],
            "normal": [float(round(v)) if abs(v - round(v)) < 1e-6 else round(float(v), 3) for v in best[2]],
            "hall": ca.hall_of({"layout": layout}, best[1]) if layout else None,
        })
    if stats is not None:
        stats.update(st)
    findings.sort(key=lambda f: (f["category"], -f["exposed"]))
    return findings


def tile_of(world):
    """Tile pitch in studs from the kit manifest the dump was built with: PR Tile's texture spans tile_m metres and
    holds 8 x 8 tiles (prkit TILE_M); the installer gives the Part variants the same StudsPerTile. Every job's Tile
    and Aqua must agree (a kit re-exported job by job can be mixed, and an audit at the first job's pitch reports every
    seam of the others as a grid step), and each manifest must still be the one the dump was built with (sha256)."""
    import hashlib
    pitches = {}
    for job, receipt in sorted(world["kitExports"].items()):
        raw = Path(receipt["path"]).read_bytes()
        if receipt.get("sha256") and hashlib.sha256(raw).hexdigest() != receipt["sha256"]:
            raise ValueError(f"kit manifest of job {job} changed since the dump was built: {receipt['path']}")
        manifest = json.loads(raw)
        for mat in ("Tile", "Aqua"):
            rec = manifest.get("materials", {}).get(mat)
            if rec and rec.get("tile_m"):
                pitches[f"{job}.{mat}"] = round(rec["tile_m"] / manifest.get("scaleMetresPerStud", .28) / 8, 9)
    if len(set(pitches.values())) > 1:
        raise ValueError(f"kit manifests disagree on the tile pitch (studs): {pitches}")
    return next(iter(pitches.values()), TILE)


def kit_jobs(world):
    """component -> kit job letter from every job manifest the dump was built with (a Part-only component such as
    VaultPier has no mesh chunk to carry its job)."""
    jobs = {}
    for job, receipt in world["kitExports"].items():
        for comp in json.loads(Path(receipt["path"]).read_text(encoding="utf-8")).get("components", {}):
            jobs[comp] = job
    return jobs


def audit_world(dump_path, max_offset=MAX_OFFSET, min_exposed=MIN_EXPOSED, stats=None):
    world = ca.load_world(dump_path)
    chunks = load_kit_chunks(world)
    tile = tile_of(world)
    if stats is not None:
        stats["tile_x1000"] = round(tile * 1000)
    return audit_parts(world["parts"], world["layout"], chunks, max_offset, min_exposed, stats, jobs=kit_jobs(world),
                       tile=tile)


def summarize(findings):
    cats = defaultdict(lambda: {"count": 0, "max": 0.0, "exposed": 0.0, "owners": set(), "kinds": Counter(),
                                "flags": Counter(), "example": None})
    for f in findings:
        c = cats[f["category"]]
        c["count"] += 1
        c["exposed"] += f["exposed"]
        c["owners"].update((f["a"]["owner"], f["b"]["owner"]))
        c["kinds"][f["kind"]] += 1
        c["flags"].update(f["flags"])
        if f["offset"] >= c["max"]:
            c["max"], c["example"] = f["offset"], f["at"]
    return cats


def print_summary(path, findings, stats):
    print(f"== {Path(path).name}: tile {stats.get('tile_x1000', 0) / 1000:g}, {stats.get('seams', 0)} seams "
          f"({stats.get('seams_edge', 0)} edge, {stats.get('seams_inlay', 0)} inlay, {stats.get('seams_corner', 0)} corner), "
          f"{stats.get('stepping', 0)} step, "
          f"{len(findings)} findings; {stats.get('cut_pieces', 0)} curved-cut pieces "
          f"({stats.get('cut_length_x10', 0) / 10:.0f} studs, not judged)")
    for cat, c in sorted(summarize(findings).items(), key=lambda kv: -kv[1]["exposed"]):
        print(f"  {c['count']:4d}  max {c['max']:.3f}  exposed {c['exposed']:8.1f}  {cat}  "
              f"[{', '.join(sorted(c['owners']))}] {dict(c['kinds'])} {dict(c['flags']) or ''} eg {c['example']}")


# ----------------------------------------------------------------------------------------------- self-test

def _block(name, size, pos, rot=None):
    R = np.eye(3) if rot is None else np.asarray(rot, float)
    return {"name": name, "class": "Part", "shape": "PartType.Block", "size": list(map(float, size)),
            "cframe": list(map(float, pos)) + list(R.reshape(-1)), "transparency": 0, "materialVariant": "PR Tile",
            "fixtureComponent": None, "fixtureKind": None, "path": name}


def _box_mesh(name, comp, lo, hi, tile, shift=(0, 0, 0), flip=None, omit=None):
    """A closed tiled box mesh over the world box lo..hi, faces wound outward (the face 'flip' = (axis, sign) inward,
    the face 'omit' left out: an open box), box-projected UVs: grout lines where a world coordinate + shift is a whole
    tile. Returns (part, chunks)."""
    lo, hi = np.asarray(lo, float), np.asarray(hi, float)
    c = (lo + hi) / 2
    P, UV, I = [], [], []
    for a in range(3):
        u, w = [k for k in range(3) if k != a]
        for sg in (-1, 1):
            if (a, sg) == omit:
                continue
            quad = np.array([[(hi if (k == a and sg > 0) or (k == u and du) or (k == w and dw) else lo)[k]
                              for k in range(3)] for du, dw in ((0, 0), (1, 0), (1, 1), (0, 1))])
            out = (np.cross(quad[1] - quad[0], quad[2] - quad[0])[a] * sg > 0) != ((a, sg) == flip)
            b = len(P)
            P += list(quad - c)
            UV += [((v[u] + shift[u]) / (8 * tile), (v[w] + shift[w]) / (8 * tile)) for v in quad]
            tris = ((0, 1, 2), (0, 2, 3)) if out else ((0, 2, 1), (0, 3, 2))
            I += [[(b + k, 0, b + k) for k in tri] for tri in tris]
    size = list(map(float, hi - lo))
    part = {"name": name, "class": "MeshPart", "shape": "Mesh", "size": size,
            "cframe": list(map(float, c)) + list(np.eye(3).reshape(-1)), "transparency": 0, "fixtureKind": "mesh",
            "fixtureComponent": comp, "materialVariant": "PR Tile", "path": name}
    return part, {(comp, "Tile"): {"record": {"size": size}, "positions": np.asarray(P, np.float32),
                                   "uv": np.asarray(UV, np.float32), "indices": np.asarray(I, np.uint32)}}


def _rot(axis, deg):
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    return {"x": ((1, 0, 0), (0, c, -s), (0, s, c)), "y": ((c, 0, s), (0, 1, 0), (-s, 0, c)),
            "z": ((c, -s, 0), (s, c, 0), (0, 0, 1))}[axis]


def self_test(tile=TILE):
    """Planted controls in tile units T, each judged alone (one big air box, nothing else in the world). Every 'step'
    pair is continuous under at least one wrong rule (world grid, face centre, the opposite corner) and every 'ok' pair
    steps under one, so the set pins the measured corner on both axes of all six faces, plus a yawed and a rolled part,
    a Part/mesh seam, a flush inlay and the exposure test."""
    T = tile
    layout = {"Halls": [{"MinX": -500, "MaxX": 500, "MinZ": -500, "MaxZ": 500, "FloorY": -100, "CeilingClass": 300,
                         "Type": "Hall", "Index": 1}], "Corridors": []}
    cases = []
    UP = (0, 1, 0)
    # Each face: two thin plates side by side in the face plane, the seam across face axis 1, then axis 2. Plate A spans
    # [0, 7.5T] (its anchored + end at 7.5T), B continues to 12.5T (5 tiles on: ok) or 13T (5.5: a half-tile step).
    # Read from the - end instead, the ok pair would step (0 against 7.5T) and the 13T pair would not show its step.
    for (a, sg), ((i, si), (j, sj)) in ANCHOR.items():
        for seam_axis, sign in ((i, si), (j, sj)):
            other = j if seam_axis == i else i
            for end, expect in ((12.5, False), (13.0, True)):
                plates = []
                for lo, hi in ((0.0, 7.5), (7.5, end)):
                    lo, hi = (-hi, -lo) if sign < 0 else (lo, hi)     # anchored at - : mirror
                    size, pos = [0, 0, 0], [0, 0, 0]
                    size[a], pos[a] = 1.0, -sg * .5                     # face (a, sg) lies on the plane coordinate 0
                    size[seam_axis], pos[seam_axis] = (hi - lo) * T, (lo + hi) / 2 * T
                    size[other], pos[other] = 5 * T, 2.5 * T
                    plates.append((size, pos))
                normal = [0, 0, 0]
                normal[a] = sg
                cases.append((f"face {'XYZ'[a]}{'+' if sg > 0 else '-'} seam across {'XYZ'[seam_axis]} end {end}T",
                              [_block("A", *plates[0]), _block("B", *plates[1])], expect, normal))
    # Yawed: B turned 90 deg about Y (object +X -> world -Z, object +Z -> world +X), so its top anchors at world
    # (max x, min z). A: x [0, 8T], z [0, 5T] anchors (8T, 5T). B: x [8T, 13T], z [0, 5.5T] anchors (13T, 0): ok on both
    # axes (a world-corner reading of 'max z' would see 5.5T against 5T). Moved to z [0.5T, 5.5T]: anchor z 0.5T, a step.
    R = np.asarray(_rot("y", 90))
    assert np.allclose(R @ (1, 0, 0), (0, 0, -1))
    A = _block("A", (8 * T, 1, 5 * T), (4 * T, -.5, 2.5 * T))
    cases.append(("yawed 90 top, continuous", [A, _block("B", (5.5 * T, 1, 5 * T), (10.5 * T, -.5, 2.75 * T), R)], False, UP))
    cases.append(("yawed 90 top, z steps", [A, _block("B", (5 * T, 1, 5 * T), (10.5 * T, -.5, 3 * T), R)], True, UP))
    # Rolled: B turned 90 deg about X (object +Y -> world +Z, object -Z -> world +Y): its top is the object -Z face,
    # anchored at object (+Y, +X) = world (max z, max x). A: x [0, 8T], z [0, 5.5T] anchors (8T, 5.5T).
    R = np.asarray(_rot("x", 90))
    assert np.allclose(R @ (0, 0, -1), (0, 1, 0))
    A = _block("A", (8 * T, 1, 5.5 * T), (4 * T, -.5, 2.75 * T))
    cases.append(("rolled 90 top, continuous", [A, _block("B", (5 * T, 5.5 * T, 1), (10.5 * T, -.5, 2.75 * T), R)], False, UP))
    cases.append(("rolled 90 top, x steps", [A, _block("B", (5.5 * T, 5.5 * T, 1), (10.75 * T, -.5, 2.75 * T), R)], True, UP))
    # Part/mesh: a 4T mesh quad continuing a top plate x [0, 8T] (anchored at 8T); its grid on the plate's (ok), then
    # half a tile off (step). One UV unit is 8 tiles.
    for shift, expect in ((0.0, False), (.5, True)):
        quad = np.array(((0, 0, 0), (4, 0, 0), (4, 0, 4), (0, 0, 4)), float) * T - (2 * T, 0, 2 * T)
        uv = (quad[:, [0, 2]] + (2 * T + shift * T, 2 * T)) / (8 * T)
        chunk = {"record": {"size": [4 * T, .01, 4 * T]}, "positions": quad.astype(np.float32),
                 "uv": uv.astype(np.float32), "indices": np.array((((0, 0, 0), (2, 0, 2), (1, 0, 1)),
                                                                   ((0, 0, 0), (3, 0, 3), (2, 0, 2))), np.uint32)}
        mesh = {"name": "M_Tile", "class": "MeshPart", "shape": "Mesh", "size": [4 * T, .01, 4 * T],
                "cframe": [10 * T, 0, 2 * T] + list(np.eye(3).reshape(-1)), "transparency": 0, "fixtureKind": "mesh",
                "fixtureComponent": "Quad", "materialVariant": "PR Tile", "path": "M"}
        cases.append((f"part/mesh shift {shift}T", ([_block("A", (8 * T, 1, 4 * T), (4 * T, -.5, 2 * T)), mesh],
                                                     {("Quad", "Tile"): chunk}), expect, UP))
    # Inlay: a 4T plate set flush into a 16T floor (top faces coplanar). The floor anchors at (8T, 8T); the plate at
    # x [0, 4T] anchors at 4T (ok), at x [0.5T, 4.5T] at 4.5T (a half-tile step round its outline).
    for cx, expect in ((2.0, False), (2.5, True)):
        cases.append((f"inlay plate at x {cx}T", [_block("Floor", (16 * T, 1, 16 * T), (0, -.5, 0)),
                                                  _block("Plate", (4 * T, .5, 4 * T), (cx * T, -.25, 2 * T))], expect, UP))
    # A flat trim laid parallel 0.06 proud of the floor (ExitMouthTrim on the exit collar) is still an inlay: judged
    # both ways; 0.15 proud it is a raised element of its own (not judged, even when its grid steps).
    for lift, cx, expect in ((.06, 2.0, False), (.06, 2.5, True), (.15, 2.5, False)):
        cases.append((f"plate {lift} proud at x {cx}T", [_block("Floor", (16 * T, 1, 16 * T), (0, -.5, 0)),
                      _block("Plate", (4 * T, .5, 4 * T), (cx * T, -.25 + lift, 2 * T))], expect, UP))
    # Cut: a trim strip lying flush on a 16T floor (an inlay). Laid along a 45 deg line with its grid following the line,
    # it is a clean cut (no finding); laid along x (a straight, aligned seam) with its grid turned 10 deg, it is a seam.
    def strip(yaw, uv_turn):
        a, c = math.radians(yaw), math.radians(uv_turn)
        d, e = np.array((math.cos(a), 0, math.sin(a))), np.array((-math.sin(a), 0, math.cos(a)))
        quad = np.array([d * x + e * z for x, z in ((-4, -.5), (4, -.5), (4, .5), (-4, .5))]) * T
        rot = np.array(((math.cos(c), -math.sin(c)), (math.sin(c), math.cos(c))))
        local = np.array(((-4, -.5), (4, -.5), (4, .5), (-4, .5))) * T
        uv = (local @ rot.T) / (8 * T)
        chunk = {"record": {"size": [8 * T, .01, 8 * T]}, "positions": quad.astype(np.float32), "uv": uv.astype(np.float32),
                 "indices": np.array((((0, 0, 0), (2, 0, 2), (1, 0, 1)), ((0, 0, 0), (3, 0, 3), (2, 0, 2))), np.uint32)}
        mesh = {"name": "S_Tile", "class": "MeshPart", "shape": "Mesh", "size": [8 * T, .01, 8 * T],
                "cframe": [0, 0, 0] + list(np.eye(3).reshape(-1)), "transparency": 0, "fixtureKind": "mesh",
                "fixtureComponent": "Strip", "materialVariant": "PR Tile", "path": "S"}
        return ([_block("Floor", (16 * T, 1, 16 * T), (0, -.5, 0)), mesh], {("Strip", "Tile"): chunk})
    cases.append(("45 deg trim following its line on a floor (cut)", strip(45, 0), False, UP))
    cases.append(("straight trim with its grid turned 10 deg", strip(0, 10), True, UP))
    # Exposure: a stepping top pair under a non-tiled lid 0.2 above it is hidden (no finding); without the lid it steps.
    pair = [_block("A", (7.5 * T, 1, 5 * T), (3.75 * T, -.5, 2.5 * T)),
            _block("B", (5.5 * T, 1, 5 * T), (10.25 * T, -.5, 2.5 * T))]
    lid = dict(_block("Lid", (40 * T, .2, 40 * T), (6 * T, .3, 2.5 * T)), materialVariant="")
    cases.append(("stepping top pair under a lid", pair + [lid], False, UP))
    cases.append(("same pair, lid removed", pair, True, UP))
    # Hidden by a butted closed neighbour (the review's CoveTop96 / Hall Lintel class): a closed tiled mesh's -X end cap
    # at x = 0 steps half a tile against a coplanar tiled Part face beside it. The next closed mesh, butted on the same
    # plane with its own cap wound INTO its solid (as the swerve kit's tail caps are), seals the cap: no finding. With the
    # neighbour removed, the cap is seen and the step is a finding. The neighbour is longer than EXPOSURE_RANGE, so a ray
    # from inside it runs its full length without a hit: only the inside test (ray parity) hides the cap.
    cove = _box_mesh("CoveA_Tile", "CoveA", (0, 0, 0), (4 * T, 4 * T, 4 * T), T, shift=(0, 0, T / 2))
    beside = _block("Lintel", (4 * T, 4 * T, 4 * T), (2 * T, 2 * T, 6 * T))
    nxt = _box_mesh("CoveB_Tile", "CoveB", (-20 * T, 0, 0), (0, 4 * T, 4 * T), T, flip=(0, 1))   # > EXPOSURE_RANGE
    cases.append(("cap sealed by a butted neighbour (inward-wound cap)", ([beside, cove[0], nxt[0]], {**cove[1], **nxt[1]}),
                  False, (-1, 0, 0)))
    cases.append(("same cap, neighbour removed", ([beside, cove[0]], cove[1]), True, (-1, 0, 0)))
    # Sealed by a Part (a swerve skin's wall-plane facets left to the hall wall slab): the same neighbour OPEN on its
    # +Z side is solid only while an (untiled) Part face covers that hole, here within SEAL_TOL; with the Part 0.3 off
    # the hole, or removed, rays from inside the neighbour leave through the hole and the cap is seen.
    opened = _box_mesh("CoveB_Tile", "CoveB", (-20 * T, 0, 0), (0, 4 * T, 4 * T), T, flip=(0, 1), omit=(2, 1))
    for gap, expect, label in ((.05, False, "sealed by a Part 0.05 off its hole"), (.3, True, "Part 0.3 off its hole"),
                               (None, True, "sealing Part removed")):
        seal = [] if gap is None else [dict(_block("Seal", (20 * T, 4 * T, 1), (-10 * T, 2 * T, 4 * T + gap + .5)),
                                            materialVariant="")]
        cases.append((f"cap against an open neighbour, {label}",
                      ([beside, cove[0], opened[0]] + seal, {**cove[1], **opened[1]}), expect, (-1, 0, 0)))
    # Corners: the grout lines that cross a shared edge must meet there. A sill top against its jamb (a T-corner: the
    # sill's edge lies inside the jamb face), in both orientations: the jamb's +X face anchors at its +Z edge (5T), its
    # -X face at its -Z edge (0), the sill top at its +Z edge. A 6T-deep sill from z 0 continues both; moved half a tile
    # along z it steps against both (its own end corners stay whole: 6T deep).
    for sg in (1, -1):
        for z0, expect in ((0.0, False), (0.5, True)):
            jamb = _block("Jamb", (6 * T, 10 * T, 5 * T), (-sg * 3 * T, 5 * T, 2.5 * T))
            sill = _block("Sill", (6 * T, 3 * T, 6 * T), (sg * 3 * T, 1.5 * T, (z0 + 3) * T))
            cases.append((f"sill top against a {'+' if sg > 0 else '-'}X jamb, sill from z {z0}T", [jamb, sill], expect,
                          (sg * .707, .707, 0)))
    # One Part's own corner (a plinth): its top anchors at +X, its +Z face at -X, so the rows crossing that edge meet
    # only when the width is whole tiles.
    for width, expect in ((5.0, False), (5.5, True)):
        cases.append((f"plinth {width}T wide, top/front corner", [_block("Plinth", (width * T, 4 * T, 4 * T),
                                                                           (width / 2 * T, 2 * T, 2 * T))],
                      expect, (0, .707, .707)))
    # A box standing on a floor half a tile off the floor's grid steps at its foot (a T-corner along the floor's axes);
    # the same box turned 45 deg meets the floor along lines the floor's grid crosses obliquely: a cut, not judged.
    floor = _block("Floor", (16 * T, 1, 16 * T), (0, -.5, 0))
    cases.append(("box on a floor half a tile off", [floor, _block("Box", (2 * T, 4 * T, 2 * T), (T, 2 * T, 1.5 * T))],
                  True, "corner"))
    cases.append(("box turned 45 deg on a floor (cut)", [floor, _block("Box", (2 * T, 4 * T, 2 * T), (T, 2 * T, 1.5 * T),
                                                                       _rot("y", 45))], False, "corner"))
    # A stepping pair in a hall's wall band, sealed from the room by an untiled collar 0.1 thick at the wall face: the
    # rays that miss the collar run up and along the band, which is hall air but not the room: no finding. Without the
    # collar the room sees it.
    band = {"Halls": [{"MinX": -20, "MaxX": 20, "MinZ": -20, "MaxZ": 20, "FloorY": -100, "CeilingClass": 300,
                       "Type": "Hall", "Index": 1}], "Corridors": []}
    pair2 = [_block("A", (7.5 * T, 1, 2 * T), (3.75 * T, -.5, -19.8 + T)),
             _block("B", (5.5 * T, 1, 2 * T), (10.25 * T, -.5, -19.8 + T))]
    collar = dict(_block("Collar", (40 * T, 20, .1), (6 * T, 5, -20 + WALL_DEPTH)), materialVariant="")
    cases.append(("stepping pair in the wall band behind a collar", (pair2 + [collar], {}, band), False, UP))
    cases.append(("same pair, collar removed", (pair2, {}, band), True, UP))
    bad = 0
    for name, parts, expect, normal in cases:
        chunks, lay = {}, layout
        if isinstance(parts, tuple):
            parts, chunks, *rest = parts
            lay = rest[0] if rest else layout
        # judge only the planted face: the plates' other faces form seams of their own (other anchor corners)
        found = [f for f in audit_parts(parts, lay, chunks, tile=T)
                 if (f["kind"] == normal if isinstance(normal, str) else f["normal"] == list(map(float, normal)))]
        ok = bool(found) == expect
        bad += not ok
        print(f"  {'ok  ' if ok else 'FAIL'} {name}: expected {'step' if expect else 'continuous'}, "
              f"found {[(f['along'], f['across']) for f in found]}")
    print(f"SELF-TEST tile {T} {'PASS' if not bad else 'FAIL'}: {len(cases) - bad}/{len(cases)}")
    return bad == 0


def tile_of_controls():
    """tile_of's planted controls: agreeing manifests give their pitch; a kit re-exported job by job at two pitches,
    or a manifest changed since the dump, raises instead of auditing at the first job's pitch."""
    import hashlib
    import tempfile
    ok = True
    with tempfile.TemporaryDirectory() as tmp:
        def receipt(job, tile_m, sha=True):
            path = Path(tmp) / f"{job}.json"
            path.write_text(json.dumps({"scaleMetresPerStud": .28, "materials": {"Tile": {"tile_m": tile_m}}}))
            return {"path": str(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest() if sha else ""}
        for name, exports, expect in (
                ("agreeing 0.5", {"A": receipt("A", 1.12), "B": receipt("B", 1.12)}, .5),
                ("mixed 0.6 / 0.5", {"A": receipt("A2", 1.344), "B": receipt("B2", 1.12)}, ValueError),
                ("manifest changed", {"A": dict(receipt("A3", 1.12), sha256="0" * 64)}, ValueError)):
            try:
                got = tile_of({"kitExports": exports})
            except ValueError as error:
                got = ValueError
                print(f"  tile_of {name}: {error}")
            good = got == expect if expect is ValueError else abs(got - expect) < 1e-9
            ok &= good
            print(f"  {'ok  ' if good else 'FAIL'} tile_of {name}: expected {expect}, got {got}")
    print(f"TILE_OF CONTROLS {'PASS' if ok else 'FAIL'}")
    return ok


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("dumps", nargs="*")
    ap.add_argument("--max-offset", type=float, default=MAX_OFFSET)
    ap.add_argument("--min-exposed", type=float, default=MIN_EXPOSED)
    ap.add_argument("--json", type=Path, help="write all findings per dump to this directory")
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args(argv)
    if args.self_test:      # at today's pitch and at LATTICE_SPEC's 0.5
        return 0 if all([self_test(.6), self_test(.5), tile_of_controls()]) else 1
    total = 0
    for path in args.dumps:
        stats = Counter()
        findings = audit_world(path, args.max_offset, args.min_exposed, stats)
        print_summary(path, findings, stats)
        total += len(findings)
        if args.json:
            args.json.mkdir(parents=True, exist_ok=True)
            (args.json / f"lattice_{Path(path).stem}.json").write_text(
                json.dumps({"stats": dict(stats), "findings": findings}, indent=1), encoding="utf-8", newline="\n")
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
