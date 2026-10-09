"""Exit tube: visual bore vs SlideCol_Bore16 collision, markers, collar and mouth trim (ANALYSIS F13, numpy only).

    python -B tools/tests/test_level2_exit_bore.py [export_dir]

export_dir defaults to $L2_POOLROOMS_EXPORT or assets/level2/poolrooms-kit/export. Frames: ExitTubeVisual* and their
BoreSegment markers are anchor-relative (anchor = E+23, F+81.2, deckZ); ExitCollar / ExitMouthTrim are relative to
(E, F, deckZ). The builder clones SlideTemplates[marker Template] per marker with Size = marker Size at the marker cf:
SlideCol_Bore16 (unit length, Size (15.6, 15.6, span)) or a mitered SlideCol_Bore16_Mnn (native Size). A piece is
modelled as its template's 16-gon (apothem 7.2..7.8 about the local Z axis) between its two cap planes, both taken
from the template mesh scaled by Size / native size.
(1) 271 BoreSegment markers, Index 1..271, Length = |p[j+1]-p[j]| of the reviewed pathPoints, OneWay from the slide
    segments, frame back = -look and right = look x Y, local Z axis on the segment axis; the start cap passes through
    or behind p[j] and the end cap through or beyond p[j+1]; mitered caps are the visual's miter planes; piece 1
    starts exactly at the mouth plane through (-25, 0, 0), piece 271 ends at the plane through the path end.
(2) Every named template is Template=true, one chunk of 16 hexahedral stave prisms (apothem 7.2..7.8), no records;
    SlideCol_Bore16 is 15.6 x 15.6 x 1 centred (z +-0.5); a mitered template's Segments attr lists its markers.
(3) Deterministic: every vertex, edge midpoint and a 6x barycentric grid of every visual inner stave triangle lies
    within 0.02 of a collision inner face, and no collision piece stands more than 0.1 inside the bore (F13's limit).
(4) Random points on each piece's inner faces between its two miter planes lie within 0.02 of a visual triangle.
(5) ExitTubeVisual*, ExitCollar and ExitMouthTrim are closed; tube mouth at x = -25, collar face at E-2.0 (= -25+23),
    bore floor at the deck top; the trim stays above the deck top and inside r 9.
(6) Tile lattice (LATTICE_SPEC I3, tools/level2_poolrooms/lattice_audit.py): every Exit* mesh and tiled Part placed in
    its builder frame next to stand-in builder walls cut by HallWallGap {deckZ, 18, F+73, F+90}: every seam between two
    of them (edge or inlay, hidden ones included) steps by at most 0.01, at the LATTICE_SPEC pitch. Planted
    negative: the ExitCollar moved 0.25 along the wall must step. Judged at LATTICE_TILE (0.5).
"""
from __future__ import annotations

import json
import math
from pathlib import Path
import sys

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_level2_exit_stair import (ROOT, boxes, closure_failures, component_triangles,  # noqa: E402
                                    corners, export_dir, frame, inside_solid, load_export)

SLIDES = ROOT / "assets" / "level2" / "blender-kit" / "export" / "slides.json"
APO_IN, APO_OUT, SIDES = 7.2, 7.8, 16
HALF = math.pi / SIDES
PROTRUSION_LIMIT = 0.1          # ANALYSIS F13: "never more than 0.1 inside the bore"
RNG = np.random.default_rng(20261004)


def stave_normals():
    ang = -math.pi / 2 + 2 * HALF * np.arange(SIDES)
    return np.stack([np.cos(ang), np.sin(ang)], 1)


NORMALS = stave_normals()


def cap_normals(tris):
    """Outward normals of the two cap planes of a closed stave-prism template: caps are the triangles whose normal
    is within 60 deg of the local Z axis (+Z = back = the start cap first); each cap must be planar."""
    n = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
    n /= np.linalg.norm(n, axis=1)[:, None]
    out = []
    for sign in (1, -1):
        sel = tris[np.abs(n[:, 2]) > .5]
        sel = sel[np.sign(sel.mean(1)[:, 2] - tris[:, :, 2].mean()) == sign].reshape(-1, 3)
        normal = np.linalg.svd(sel - sel.mean(0))[2][2]
        normal *= sign * np.sign(normal[2])
        assert np.ptp(sel @ normal) < 1e-3, ("template cap not planar", np.ptp(sel @ normal))
        out.append(normal)
    return out


def markers(manifest, chunks):
    templates, out = {}, []
    for name, info in manifest["components"].items():
        if name.startswith("ExitTubeVisual"):
            for m in info["markers"]:
                if m["name"] == "BoreSegment":
                    pos, rot = frame(m["cf"])
                    out.append({"c": pos, "R": rot, **m["attrs"], "chunk": name})
    out.sort(key=lambda m: m["Index"])
    for m in out:
        tpl = m["Template"]
        if tpl not in templates:
            native = np.array(manifest["chunks"][manifest["components"][tpl]["chunks"][0]]["size"], float)
            templates[tpl] = (component_triangles(manifest, chunks, tpl), native)
        tris, native = templates[tpl]
        scaled = tris * (np.array(m["Size"], float) / native)
        m["caps"] = [(nrm, (scaled.reshape(-1, 3) @ nrm).max()) for nrm in cap_normals(scaled)]   # n.x <= d
        m["reach"] = np.abs(scaled.reshape(-1, 3)).max(0)
    return out


def against_pieces(pieces, pts, seg):
    """For each point (on segment seg): the distance to the nearest collision inner face of a piece whose length
    contains it (near) and how far the point lies inside any piece's wall, i.e. how far that piece's inner face
    stands inside the bore there (protrude, -inf when none). Pieces seg-2 .. seg+2 are tested (a piece reaches at
    most 0.45 past a joint and every segment is longer than 1)."""
    C = np.stack([p["c"] for p in pieces])
    R = np.stack([p["R"] for p in pieces])
    caps = np.array([[np.append(n, d) for n, d in p["caps"]] for p in pieces])        # (pieces, 2, 4)
    near = np.full(len(pts), np.inf)
    protrude = np.full(len(pts), -np.inf)
    for off in range(-2, 3):
        k = np.clip(seg + off, 0, len(pieces) - 1)
        for i in range(0, len(pts), 200000):
            sl = slice(i, i + 200000)
            local = np.einsum("pk,pkj->pj", pts[sl] - C[k[sl]], R[k[sl]])
            apo = (local[:, None, :2] * NORMALS[None]).sum(-1).max(-1)                  # convex 16-gon
            cp = caps[k[sl]]
            inlen = np.all(np.einsum("pj,pcj->pc", local, cp[:, :, :3]) <= cp[:, :, 3] + 1e-4, axis=1)   # float32
            near[sl] = np.minimum(near[sl], np.where(inlen, np.abs(apo - APO_IN), np.inf))
            protrude[sl] = np.maximum(protrude[sl], np.where(inlen & (apo < APO_OUT), apo - APO_IN, -np.inf))
    return near, protrude


def path_frames(P):
    look = np.diff(P, axis=0)
    look /= np.linalg.norm(look, axis=1)[:, None]
    right = np.cross(look, (0, 1, 0))
    right /= np.linalg.norm(right, axis=1)[:, None]
    planes = [look[0]] + [(look[j - 1] + look[j]) / np.linalg.norm(look[j - 1] + look[j])
                          for j in range(1, len(look))] + [look[-1]]
    return look, right, np.cross(right, look), np.array(planes)


def joint_grid(P, lateral=9, near_end=1.5, step=.05, mid_step=.5):
    """Deterministic points on the ideal inner staves of every segment, between its two miter planes: 16 staves x
    `lateral` positions (both stave corners included), every `step` within `near_end` of either miter (where the
    pieces overlap) and every `mid_step` between. Returns (points, segment index)."""
    look, right, up, planes = path_frames(P)
    w = APO_IN * math.tan(HALF)
    tang = np.stack([-NORMALS[:, 1], NORMALS[:, 0]], 1)
    ab = (NORMALS[:, None] * APO_IN + tang[:, None] * np.linspace(-w, w, lateral)[None, :, None]).reshape(-1, 2)
    pts, seg = [], []
    for j in range(len(look)):
        o = ab[:, :1] * right[j] + ab[:, 1:] * up[j]                     # offsets from the axis
        s0 = -(o @ planes[j]) / (look[j] @ planes[j])                    # along from p[j] to each miter plane
        length = np.linalg.norm(P[j + 1] - P[j])
        s1 = length - (o @ planes[j + 1]) / (look[j] @ planes[j + 1])
        span = (s1 - s0).min()
        f = np.unique(np.concatenate([np.arange(0, min(near_end, span / 2), step),
                                      np.arange(near_end, span - near_end, mid_step),
                                      span - np.arange(0, min(near_end, span / 2), step)]))
        for k in range(len(o)):
            along = s0[k] + f * (s1[k] - s0[k]) / span
            pts.append(P[j] + o[k] + along[:, None] * look[j])
            seg.append(np.full(len(along), j))
    return np.concatenate(pts), np.concatenate(seg)


def nearest_segment(P, pts):
    """Index of the path segment closest to each point (point-to-segment distance)."""
    a, d = P[:-1], np.diff(P, axis=0)
    best = np.full(len(pts), np.inf)
    out = np.zeros(len(pts), int)
    for j in range(len(d)):
        t = np.clip(((pts - a[j]) @ d[j]) / (d[j] @ d[j]), 0, 1)
        dist = np.linalg.norm(pts - a[j] - t[:, None] * d[j], axis=1)
        better = dist < best
        best[better], out[better] = dist[better], j
    return out


def point_triangle_distance(p, tris):
    """Distance from each point p (P,3) to each triangle (P,K,3,3) -> (P,K); Ericson's closest-point test."""
    a, b, c = tris[..., 0, :], tris[..., 1, :], tris[..., 2, :]
    p = p[:, None, :]
    ab, ac, ap = b - a, c - a, p - a
    d1, d2 = (ab * ap).sum(-1), (ac * ap).sum(-1)
    bp = p - b
    d3, d4 = (ab * bp).sum(-1), (ac * bp).sum(-1)
    cp = p - c
    d5, d6 = (ab * cp).sum(-1), (ac * cp).sum(-1)
    va, vb, vc = d3 * d6 - d5 * d4, d5 * d2 - d1 * d6, d1 * d4 - d3 * d2
    den = np.where(np.abs(va + vb + vc) > 1e-18, va + vb + vc, 1)
    v, w = vb / den, vc / den
    closest = a + v[..., None] * ab + w[..., None] * ac
    # Edge / vertex regions: fall back to the nearest of the three edges (exact for points off the face).
    def seg(x, y):
        t = np.clip(((p - x) * (y - x)).sum(-1) / np.maximum(((y - x) ** 2).sum(-1), 1e-18), 0, 1)
        return x + t[..., None] * (y - x)
    inside = (va >= 0) & (vb >= 0) & (vc >= 0)
    best = np.where(inside[..., None], closest, seg(a, b))
    for cand in (seg(b, c), seg(c, a)):
        best = np.where((~inside[..., None]) & (((cand - p) ** 2).sum(-1) < ((best - p) ** 2).sum(-1))[..., None],
                        cand, best)
    return np.linalg.norm(best - p, axis=-1)


def nearest_triangle(points, tris, cell=3.0):
    lo = tris.min(1)
    hi = tris.max(1)
    grid = {}
    for i, (l, h) in enumerate(zip(np.floor(lo / cell).astype(int), np.floor(hi / cell).astype(int))):
        for gx in range(l[0], h[0] + 1):
            for gy in range(l[1], h[1] + 1):
                for gz in range(l[2], h[2] + 1):
                    grid.setdefault((gx, gy, gz), []).append(i)
    out = np.full(len(points), np.inf)
    for i, p in enumerate(points):
        key = tuple(np.floor(p / cell).astype(int))
        cand = grid.get(key, [])
        if cand:
            out[i] = point_triangle_distance(p[None], tris[cand][None])[0].min()
    return out


# Builder frames in a hall with E = F = deckZ = 0 (all three are multiples of 4 in a real build: on the lattice).
EXIT_FRAMES = {"ExitPlatform": (-36.0, 0.0, 10.0), "ExitSpiral": (-36.0, 0.0, 10.0), "ExitCollar": (0.0, 0.0, 0.0),
               "ExitMouthTrim": (0.0, 0.0, 0.0)}
TUBE_ANCHOR = (23.0, 81.2, 0.0)
LATTICE_TILE = .5                # LATTICE_SPEC 2.1
# Stand-in builder east wall E-1.75 .. E around HallWallGap (LATTICE_SPEC 6): (name, z0, z1, y0, y1).
WALL = (("Wall N", -40, -9, -4, 98), ("Wall S", 9, 40, -4, 98), ("Sill", -9, 9, -4, 73), ("Lintel", -9, 9, 90, 98))


def exit_assembly(manifest, chunks, collar_shift=0.0):
    """dump_world-style part dicts: every Exit* Tile chunk and tiled Part record at its builder pivot, plus WALL."""
    parts = []

    def block(name, size, centre, rot=np.eye(3), comp=None):
        return {"name": name, "class": "Part", "shape": "PartType.Block", "size": [float(v) for v in size],
                "cframe": [float(v) for v in centre] + list(np.asarray(rot, float).reshape(-1)), "transparency": 0,
                "materialVariant": "PR Tile", "fixtureComponent": comp, "fixtureKind": None, "path": name}
    for name, z0, z1, y0, y1 in WALL:
        parts.append(block(f"Level 2 Hall {name} 1 East", (1.75, y1 - y0, z1 - z0), (-.875, (y0 + y1) / 2, (z0 + z1) / 2)))
    for comp, info in manifest["components"].items():
        if not comp.startswith("Exit"):
            continue
        pivot = np.asarray(TUBE_ANCHOR if comp.startswith("ExitTubeVisual") else EXIT_FRAMES[comp], float)
        if comp == "ExitCollar":
            pivot = pivot + (0, 0, collar_shift)
        if (comp, "Tile") in chunks:
            rec = chunks[(comp, "Tile")]["record"]
            parts.append({"name": f"{comp}_Tile", "class": "MeshPart", "shape": "Mesh", "size": rec["size"],
                          "cframe": list(pivot + np.asarray(rec["center"], float)) + list(np.eye(3).reshape(-1)),
                          "transparency": 0, "materialVariant": "PR Tile", "fixtureComponent": comp,
                          "fixtureKind": "mesh", "path": comp})
        for r in info["parts"]:
            if r["material"] not in ("Tile", "Aqua"):
                continue
            pos, rot = frame(r["cf"])
            parts.append(block(r["name"], r["size"], pivot + pos, rot, comp))
    return parts


def check_lattice(manifest, chunks):
    sys.path.insert(0, str(ROOT / "tools" / "level2_poolrooms"))
    import lattice_audit as la
    tile = LATTICE_TILE
    declared = manifest["materials"]["Tile"]["tile_m"] / manifest.get("scaleMetresPerStud", .28) / 8
    # The manifest's tile_m becomes the Parts' StudsPerTile: Parts and mesh UVs must draw the same pitch.
    assert abs(declared - tile) < 1e-9, (f"manifest tile_m draws {declared:g}-stud tiles on Parts, not {tile}")

    def worst(parts):
        out = []
        for kind, pa, pb, q0, q1, n, side, both, along, across, angle, pitch, cut in la.seam_pieces(parts, chunks, tile):
            for k in np.nonzero(np.maximum(along, across) > la.MAX_OFFSET)[0]:
                out.append((round(float(max(along[k], across[k])), 4), kind, parts[pa[k]]["name"], parts[pb[k]]["name"],
                            np.round((q0[k] + q1[k]) / 2, 2).tolist()))
        return sorted(out, reverse=True)
    parts = exit_assembly(manifest, chunks)
    steps = worst(parts)
    assert not steps, (f"exit lattice at tile {tile}: {len(steps)} seam pieces step", steps[:6])
    seams = sum(len(x[1]) for x in la.seam_pieces(parts, chunks, tile))
    planted = worst(exit_assembly(manifest, chunks, collar_shift=.25))
    assert any("ExitCollar" in a + b for _, _, a, b, _ in planted), ("planted collar shift not caught", planted[:3])
    print(f"PASS (6) tile {tile}: {seams} seam pieces among {len(parts)} exit parts + stand-in walls, none steps more than"
          f" {la.MAX_OFFSET}; planted ExitCollar +0.25 along the wall caught ({planted[0]})", flush=True)


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    path = export_dir(argv)
    manifest, chunks = load_export(path)
    comps = manifest["components"]
    slide = json.loads(SLIDES.read_text(encoding="utf-8"))["slides"]["ExitFlume_Tube"]
    P = np.array(slide["pathPoints"], float)
    print(f"export {path}", flush=True)

    pieces = markers(manifest, chunks)
    _, _, _, miters = path_frames(P)
    assert [p["Index"] for p in pieces] == list(range(1, 272)), "BoreSegment markers must be Index 1..271"
    for j, m in enumerate(pieces):
        look = P[j + 1] - P[j]
        length = np.linalg.norm(look)
        look /= length
        right = np.cross(look, (0, 1, 0))
        right /= np.linalg.norm(right)
        assert abs(m["Length"] - length) < 1e-6, (j, m["Length"], length)
        assert m["OneWay"] == bool(slide["segments"][j].get("oneWay")), j
        assert np.allclose(m["R"][:, 2], -look, atol=1e-6) and np.allclose(m["R"][:, 0], right, atol=1e-6), j
        d = m["c"] - P[j]
        assert np.linalg.norm(d - (d @ look) * look) < 1e-6, (j, "piece axis off the segment axis")
        # Caps in world space: inside <=> n.x <= d; signed distance of p[j] / p[j+1] to the start / end cap.
        (ns, ds), (ne, de) = [(m["R"] @ nrm, off + (m["R"] @ nrm) @ m["c"]) for nrm, off in m["caps"]]
        start, end = ds - ns @ P[j], de - ne @ P[j + 1]       # >= 0: the cap is behind p[j] / beyond p[j+1]
        assert start >= -1e-4 and end >= -1e-4, (j, "piece does not span its segment", start, end)
        if m["Template"] != "SlideCol_Bore16":                 # mitered: caps are the visual's miter planes
            for nrm, off, k in ((ns, ds, j), (ne, de, j + 1)):
                assert abs(abs(nrm @ miters[k]) - 1) < 1e-5 and abs(off - nrm @ P[k]) < 1e-4, (j, "cap off the miter")
        else:
            assert abs(ns @ look - -1) < 1e-6, j              # square caps
        m["start"], m["end"] = start, end
    assert pieces[0]["start"] < 1e-4, ("piece 1 must start at the mouth plane", pieces[0]["start"])
    assert pieces[-1]["end"] < 1e-4, ("piece 271 must end at the path end", pieces[-1]["end"])
    reach = max(max(p["start"], p["end"]) for p in pieces if p["Template"] == "SlideCol_Bore16")
    mitered = sum(p["Template"] != "SlideCol_Bore16" for p in pieces)
    print(f"PASS (1) 271 BoreSegment markers: lengths, OneWay, frames (back = -look), pieces on the axis spanning "
          f"their segments; {mitered} mitered pieces capped on the miter planes, {271 - mitered} square pieces reaching"
          f" <= {reach:.3f} past a joint; piece 1 starts at the mouth plane, piece 271 ends at the path end",
          flush=True)

    names = sorted({p["Template"] for p in pieces})
    assert "SlideCol_Bore16" in names, names
    for name in names:
        tpl = comps[name]
        assert tpl["attrs"].get("Template") is True and len(tpl["chunks"]) == 1, (name, tpl["attrs"])
        assert not (tpl["parts"] or tpl["colliders"] or tpl["markers"]), (name, "template carries records")
        rec = manifest["chunks"][tpl["chunks"][0]]
        assert np.allclose(rec["center"], 0, atol=1e-4), (name, rec["center"])
        ttris = component_triangles(manifest, chunks, name)
        assert len(ttris) == 16 * 12, (name, "not 16 hexahedral staves", len(ttris))   # neighbours share edges
        v = ttris.reshape(-1, 3)
        apo = (v[:, None, :2] * NORMALS[None]).sum(-1).max(-1)
        assert np.all((np.abs(apo - APO_IN) < 1e-4) | (np.abs(apo - APO_OUT) < 1e-4)), name
        users = [p["Index"] for p in pieces if p["Template"] == name]
        if name == "SlideCol_Bore16":
            assert np.allclose(rec["size"], (15.6, 15.6, 1.0), atol=1e-4) and np.allclose(np.abs(v[:, 2]), .5)
            assert all(np.allclose(p["Size"][:2], 15.6) for p in pieces if p["Template"] == name)
        else:
            assert tpl["attrs"]["Segments"] == users, (name, "Segments attr")
            assert all(np.allclose(p["Size"], rec["size"], atol=1e-4) for p in pieces if p["Template"] == name), name
    print(f"PASS (2) {len(names)} templates ({', '.join(names)}): one chunk of 16 hexahedral staves 7.2..7.8 each; "
          "SlideCol_Bore16 15.6x15.6x1; mitered templates at native Size, Segments = their markers", flush=True)

    vis = np.concatenate([component_triangles(manifest, chunks, n) for n in sorted(comps)
                          if n.startswith("ExitTubeVisual")])
    # (3a) the real mesh: every inner-stave triangle's vertices and edge midpoints.
    cen = vis.mean(1)
    near_c, _ = against_pieces(pieces, cen, nearest_segment(P, cen))
    inner = vis[near_c < 1e-3]
    assert len(inner) >= 271 * 16 * 2, len(inner)
    mesh_pts = np.concatenate([inner.reshape(-1, 3), (inner + np.roll(inner, 1, axis=1)).reshape(-1, 3) / 2])
    near_m, prot_m = against_pieces(pieces, mesh_pts, nearest_segment(P, mesh_pts))
    # (3b) a dense deterministic grid on the same staves (0.05 along near every joint), confirmed to lie on the mesh.
    grid, seg = joint_grid(P)
    on_mesh = nearest_triangle(grid[::997], vis)
    assert on_mesh.max() <= 1e-3, ("grid point off the visual mesh", on_mesh.max())
    near_g, prot_g = against_pieces(pieces, grid, seg)
    near, protrude = np.concatenate([near_m, near_g]), np.concatenate([prot_m, prot_g])
    pts = np.concatenate([mesh_pts, grid])
    worst = int(np.argmax(near))
    assert near.max() <= .02, ("visual inner point away from collision", near.max(), pts[worst])
    worst = int(np.argmax(protrude))
    assert protrude.max() <= PROTRUSION_LIMIT, ("collision stands inside the bore", protrude.max(), pts[worst])
    print(f"PASS (3) {len(mesh_pts)} mesh vertices/edge midpoints + {len(grid)} grid points on the visual inner "
          f"staves: collision face within {near.max():.4f}; collision inside the bore <= {max(protrude.max(), 0):.4f}"
          f" at {np.round(pts[worst], 2)} (limit {PROTRUSION_LIMIT})", flush=True)

    samples = []
    planes = [P[1] - P[0]]
    for j in range(1, 271):
        a, b = P[j] - P[j - 1], P[j + 1] - P[j]
        planes.append(a / np.linalg.norm(a) + b / np.linalg.norm(b))
    planes.append(P[271] - P[270])
    planes = [p / np.linalg.norm(p) for p in planes]
    for j, m in enumerate(pieces):
        k = RNG.integers(0, SIDES, 24)
        lateral = (RNG.random(24) - .5) * 2 * APO_IN * math.tan(HALF)
        w = (RNG.random(24) - .5) * m["Length"]
        nrm = NORMALS[k]
        tang = np.stack([-nrm[:, 1], nrm[:, 0]], 1)
        ab = nrm * APO_IN + tang * lateral[:, None]
        mid = (P[j] + P[j + 1]) / 2
        p = mid + ab[:, :1] * m["R"][:, 0] + ab[:, 1:] * m["R"][:, 1] - w[:, None] * m["R"][:, 2]
        keep = ((p - P[j]) @ planes[j] >= 1e-6) & ((p - P[j + 1]) @ planes[j + 1] <= -1e-6)
        samples.append(p[keep])
    samples = np.concatenate(samples)
    dist = nearest_triangle(samples, vis)
    assert dist.max() <= .02, ("collision inner face away from the visual", dist.max())
    print(f"PASS (4) {len(samples)} collision inner points between miter planes: visual within {dist.max():.4f}",
          flush=True)

    for name in [n for n in sorted(comps) if n.startswith("ExitTubeVisual")] + ["ExitCollar", "ExitMouthTrim"]:
        bad, count = closure_failures(component_triangles(manifest, chunks, name))
        assert bad == 0, (name, bad)
        assert all(manifest["chunks"][c]["material"] == "Tile" for c in comps[name]["chunks"]), name
    first = component_triangles(manifest, chunks, "ExitTubeVisual").reshape(-1, 3)
    assert abs(first[:, 0].min() + 25.0) < 1e-4, first[:, 0].min()
    mouth = first[np.abs(first[:, 0] + 25.0) < 1e-4]
    assert abs(mouth[:, 1].min() + APO_OUT) < 1e-4 and abs(np.sort(np.unique(np.round(mouth[:, 1], 4)))[1] + APO_IN) < 1e-3
    collar = component_triangles(manifest, chunks, "ExitCollar").reshape(-1, 3)
    assert abs(collar[:, 0].min() - (-25.0 + 23.0)) < 1e-4, collar[:, 0].min()
    collar_tris = component_triangles(manifest, chunks, "ExitCollar")
    fills = boxes(comps["ExitCollar"]["colliders"])
    assert len(fills) >= 4, len(fills)
    for b in fills:
        assert inside_solid(collar_tris, b["c"] + (corners(b) - b["c"]) * .99).all(), (b["name"], "outside the collar")
    trim = component_triangles(manifest, chunks, "ExitMouthTrim").reshape(-1, 3)
    assert abs(trim[:, 0].max() + 2.0) < 1e-4 and abs(trim[:, 0].min() + 2.06) < 1e-4
    assert trim[:, 1].min() >= 74.0 - 1e-4 and np.hypot(trim[:, 2], trim[:, 1] - 81.2).max() <= 9.0 + 1e-3
    assert comps["ExitMouthTrim"]["attrs"].get("RecolorTarget") is True
    print(f"PASS (5) closed tube/collar/trim chunks; {len(fills)} collar fills inside the collar; mouth at x -25 = collar face E-2.0; bore floor 7.2 below the axis"
          " (deck top); trim on the collar face, above the deck top, r <= 9", flush=True)
    check_lattice(manifest, chunks)
    print("EXIT BORE OK", flush=True)


if __name__ == "__main__":
    main()
