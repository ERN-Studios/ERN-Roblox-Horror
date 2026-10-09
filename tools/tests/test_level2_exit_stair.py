"""Exit spiral stair, landing and platform checks over the Poolrooms kit export (ANALYSIS F11, numpy only).

    python -B tools/tests/test_level2_exit_stair.py [export_dir]

export_dir defaults to $L2_POOLROOMS_EXPORT or assets/level2/poolrooms-kit/export. All ExitSpiral / ExitPlatform
records share the platform frame, so the checks run in it. Every check prints PASS or raises.
(a) A walker on the union of collider tops (step-up <= 0.3) climbs circles r in {5, 5.5, 7, 9, 11, 13, 14.5} from
    theta0 to theta1 with no hole and every 0.05-stud rise in [-0.02, +0.12], ends at 74.0 and keeps 74.0 across the
    bridge onto the deck.
(b) Ramp top minus the visible tread top under it is in [-0.25, +0.45]. A tread under the exit pool floor's lowest top
    (POOL_FLOOR_LOW: under the floor in every legal exit hall) is not visible and not judged; objectives.py buries the
    one tread whose top could meet the floor (C16 'ExitSpiral | Hall Water Floor', LATTICE_SPEC I3.4).
(c) Every ramp and parapet collider's local X is radial (|dot| >= 0.999) at its top-face centre / centre.
(d) Every parapet collider corner lies inside the closed parapet solid; the parapet colliders leave no gap along the
    band; the visible parapet top is >= ramp + 3.4.
(e) Every Exit* chunk is closed: welded at 1e-4, each undirected edge belongs to exactly two triangles.
(f) Every ExitPlatform lip/nose collider stays inside the visible deck, nose and kerb (lip top corners at most at the
    kerb's crown, y <= 74.86), and every ramp box's bottom corners lie inside a visible stair body, inside the bridge
    Part or below y = -3.5 (under the pool floor): no ghost collision under the stair.
(g) Instance budget (G8): parts + colliders + mesh chunks per exit/pump component stay within EXIT_INSTANCE_BUDGET.
(h) Trim rows: no grout line (UV at a whole tile, any pitch) runs INSIDE a 0.5 stair riser, the core's 0.3
    chamfer or the crown row of the parapet cap; a line there, cut by every cross joint, drew rows of '+' ticks
    along the trim (VERIFY2 F11b, 2026-10-05).
"""
from __future__ import annotations

import hashlib
import math
import os
from pathlib import Path
import sys

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "level2_poolrooms"))
from render_world import load_kit_chunks  # noqa: E402

CANONICAL = ROOT / "assets" / "level2" / "poolrooms-kit" / "export"
SC = np.array((-45.6, 7.0))
TH1 = math.radians(-90.0)
TH0 = TH1 - math.radians(1080.0)
KR = 78.0 / math.radians(1080.0)
RADII = (5.0, 5.5, 7.0, 9.0, 11.0, 13.0, 14.5)
DECK_X = -30.0
# Exit hall pool floor (objectives.py POOL_WIDTH / POOL_DEEP; builder floorShell): top -(d+.8)/2 at the hall centre
# (E-112), falling (d-.8)/224 per stud towards E, DeepEnd d in 1.6 .. 2.0. Its lowest top under the stair (r <= 15):
POOL_FLOOR_LOW = -(2.0 + .8) / 2 - (SC[0] + 15.0 - 36.0 + 112.0) * (2.0 - .8) / 224
# Records per component that become instances at runtime (parts + colliders + mesh chunks), measured 2026-10-04.
# ExitSpiral is dominated by 724 ramp boxes (4 bands x 181): see RAMP_BANDS in objectives.py and the walk limit (a).
EXIT_INSTANCE_BUDGET = {"ExitSpiral": 850, "ExitPlatform": 54, "ExitCollar": 32, "ExitMouthTrim": 1,
                        "PumpStation": 17}


def export_dir(argv):
    args = [a for a in argv if not a.startswith("-")]
    return Path(args[0] if args else os.environ.get("L2_POOLROOMS_EXPORT", CANONICAL))


def load_export(path):
    manifest_path = Path(path) / "manifest.json"
    raw = manifest_path.read_bytes()
    world = {"kitExports": {"export": {"path": str(manifest_path), "sha256": hashlib.sha256(raw).hexdigest()}}}
    import json
    return json.loads(raw), load_kit_chunks(world)


def component_triangles(manifest, chunks, component):
    """Triangles (n, 3, 3) of every chunk of `component`, in the component pivot frame (studs)."""
    out = []
    for (name, _material), chunk in chunks.items():
        if name == component:
            pos = chunk["positions"] + np.asarray(chunk["record"]["center"], float)
            out.append(pos[chunk["indices"][:, :, 0]])
    assert out, f"{component}: no mesh chunk in the export"
    return np.concatenate(out)


def frame(cf):
    """Importer rule: 12 numbers = CFrame.new(x,y,z,R00..R22); 4 numbers = CFrame.Angles(0, rad(yaw), 0)."""
    if len(cf) == 12:
        return np.asarray(cf[:3], float), np.asarray(cf[3:], float).reshape(3, 3)
    t = math.radians(cf[3])
    c, s = math.cos(t), math.sin(t)
    return np.asarray(cf[:3], float), np.array(((c, 0, s), (0, 1, 0), (-s, 0, c)))


def boxes(records, keep=lambda r: True):
    out = []
    for r in records:
        if keep(r) and r.get("shape", "Block") == "Block":
            pos, rot = frame(r["cf"])
            out.append({"name": r["name"], "c": pos, "R": rot, "h": np.asarray(r["size"], float) / 2, "rec": r})
    return out


def corners(b):
    signs = np.array([(i, j, k) for i in (-1, 1) for j in (-1, 1) for k in (-1, 1)], float)
    return b["c"] + (signs * b["h"]) @ b["R"].T


def top_along_vertical(b, x, z):
    """Highest y of box b on the vertical lines through (x, z); nan where the line misses the box."""
    lo = np.full(x.shape, -np.inf)
    hi = np.full(x.shape, np.inf)
    ok = np.ones(x.shape, bool)
    for i in range(3):
        a = b["R"][0, i] * (x - b["c"][0]) + b["R"][2, i] * (z - b["c"][2])
        k = b["R"][1, i]
        if abs(k) < 1e-9:
            ok &= np.abs(a) <= b["h"][i] + 1e-9
            continue
        y0 = (-b["h"][i] - a) / k + b["c"][1]
        y1 = (b["h"][i] - a) / k + b["c"][1]
        lo = np.maximum(lo, np.minimum(y0, y1))
        hi = np.minimum(hi, np.maximum(y0, y1))
    ok &= lo <= hi + 1e-9
    return np.where(ok, hi, np.nan)


def inside_boxes(bs, pts, tol=1e-6):
    hit = np.zeros(len(pts), bool)
    for b in bs:
        local = (pts - b["c"]) @ b["R"]
        hit |= np.all(np.abs(local) <= b["h"] + tol, axis=1)
    return hit


def walk(walkable, xs, zs, start):
    tops = np.array([top_along_vertical(b, xs, zs) for b in walkable])
    heights = np.empty(len(xs))
    prev = start
    for i in range(len(xs)):
        c = tops[:, i]
        c = c[~np.isnan(c) & (c <= prev + 0.3)]
        heights[i] = c.max() if len(c) else np.nan
        if len(c):
            prev = heights[i]
    return heights


def weld(tris, tol=1e-4):
    key = np.round(tris.reshape(-1, 3) / tol).astype(np.int64)
    _, ids = np.unique(key, axis=0, return_inverse=True)
    return ids.reshape(-1, 3)


def closure_failures(tris):
    ids = weld(tris)
    ids = ids[(ids[:, 0] != ids[:, 1]) & (ids[:, 1] != ids[:, 2]) & (ids[:, 0] != ids[:, 2])]
    edges = np.sort(np.concatenate([ids[:, [0, 1]], ids[:, [1, 2]], ids[:, [2, 0]]]), axis=1)
    _, counts = np.unique(edges, axis=0, return_counts=True)
    return int((counts != 2).sum()), len(ids)


def connected_parts(tris):
    """Split triangles into welded connected components (each closed body of a chunk)."""
    ids = weld(tris)
    parent = np.arange(ids.max() + 1)

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a
    for t in ids:
        ra, rb, rc = find(t[0]), find(t[1]), find(t[2])
        parent[rb] = ra
        parent[find(rc)] = ra
    roots = np.array([find(t[0]) for t in ids])
    return [tris[roots == r] for r in np.unique(roots)]


def inside_solid(tris, pts):
    """Parity of +x rays against a closed triangle mesh (jittered direction avoids edge hits)."""
    d = np.array((1.0, 1e-3, 2e-3))
    d /= np.linalg.norm(d)
    v0, v1, v2 = tris[:, 0], tris[:, 1], tris[:, 2]
    e1, e2 = v1 - v0, v2 - v0
    p = np.cross(d, e2)
    det = (e1 * p).sum(1)
    good = np.abs(det) > 1e-12
    inv = np.where(good, 1 / np.where(good, det, 1), 0)
    out = []
    for q in pts:
        s = q - v0
        u = (s * p).sum(1) * inv
        qv = np.cross(s, e1)
        v = (qv @ d) * inv
        t = (qv * e2).sum(1) * inv
        out.append(int((good & (u >= 0) & (v >= 0) & (u + v <= 1) & (t > 0)).sum()) % 2 == 1)
    return np.array(out)


def horizontal_hits(tris, xs, zs, near):
    """y of the upward horizontal triangle above/below each (x, z) closest to `near` (nan if none)."""
    n = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
    n /= np.linalg.norm(n, axis=1)[:, None]
    flat = tris[np.abs(n[:, 1]) > .999]
    lo, hi = flat[:, :, [0, 2]].min(1), flat[:, :, [0, 2]].max(1)
    cell = 1.0
    grid = {}
    for i, (a, b) in enumerate(zip(np.floor(lo / cell).astype(int), np.floor(hi / cell).astype(int))):
        for gx in range(a[0], b[0] + 1):
            for gz in range(a[1], b[1] + 1):
                grid.setdefault((gx, gz), []).append(i)
    out = np.full(len(xs), np.nan)
    keys = np.floor(np.stack([xs, zs], 1) / cell).astype(int)
    for key in {tuple(k) for k in keys}:
        sel = np.where((keys[:, 0] == key[0]) & (keys[:, 1] == key[1]))[0]
        cand = grid.get(key)
        if not cand:
            continue
        t = flat[cand]
        a, b, c = t[:, 0][:, [0, 2]], t[:, 1][:, [0, 2]], t[:, 2][:, [0, 2]]
        P = np.stack([xs[sel], zs[sel]], 1)[:, None, :]
        v0, v1, v2 = b - a, c - a, P - a
        d00, d01, d11 = (v0 * v0).sum(-1), (v0 * v1).sum(-1), (v1 * v1).sum(-1)
        d20, d21 = (v2 * v0).sum(-1), (v2 * v1).sum(-1)
        den = d00 * d11 - d01 * d01
        v = (d11 * d20 - d01 * d21) / den
        w = (d00 * d21 - d01 * d20) / den
        inside = (v >= -1e-9) & (w >= -1e-9) & (v + w <= 1 + 1e-9)
        y = np.where(inside, t[:, 0, 1][None, :], np.nan)
        dist = np.abs(y - near[sel][:, None])
        dist = np.where(np.isnan(dist) | (dist > 1.0), np.inf, dist)   # only the turn the walker is on
        best = dist.argmin(1)
        found = np.isfinite(dist[np.arange(len(sel)), best])
        out[sel[found]] = y[np.arange(len(sel)), best][found]
    return out


def ramp_y(th):
    return -4.0 + KR * (th - TH0)


def check_stair(manifest, chunks):
    comps = manifest["components"]
    spiral, plat = comps["ExitSpiral"], comps["ExitPlatform"]
    ramp = boxes(spiral["colliders"], lambda r: r["attrs"].get("Level2_StairRamp"))
    parapet = boxes(spiral["colliders"], lambda r: "Parapet" in r["name"])
    assert len(ramp) >= 480 and len(parapet) >= 57, (len(ramp), len(parapet))
    walkable = ramp + boxes(spiral["parts"] + plat["parts"] + plat["colliders"], lambda r: r.get("ground"))
    walkable += boxes([r for r in spiral["parts"] if r.get("collide", True)], lambda r: "Guard" in r["name"])
    names = {r["name"] for r in spiral["parts"]}
    assert {"Level 2 Exit Spiral Bridge", "Level 2 Exit Spiral Bridge North Guard"} <= names, names
    stair_tris = component_triangles(manifest, chunks, "ExitSpiral")
    worst = [np.inf, -np.inf, np.inf, -np.inf]
    for r in RADII:
        n = int((TH1 - TH0) * r / .05) + 1
        th = np.linspace(TH0, TH1, n)
        xs, zs = SC[0] + r * np.cos(th), SC[1] + r * np.sin(th)
        bridge_x = np.arange(SC[0] + .05, DECK_X + 3.0, .05)
        allx = np.concatenate([xs, bridge_x])
        allz = np.concatenate([zs, np.full(len(bridge_x), SC[1] - r)])
        h = walk(walkable, allx, allz, ramp_y(TH0) + .05)
        assert not np.isnan(h).any(), (r, "no collider under", np.where(np.isnan(h))[0][:5])
        dy = np.diff(h)
        assert dy.min() >= -.02 and dy.max() <= .12, (r, "rise outside [-0.02, 0.12]", dy.min(), dy.max(),
                                                     int(dy.argmin()), int(dy.argmax()))
        assert abs(h[n - 1] - 74.0) <= .02, (r, "top", h[n - 1])
        assert np.abs(h[n:] - 74.0).max() <= .02, (r, "bridge/deck height", h[n:].min(), h[n:].max())
        tread = horizontal_hits(stair_tris, xs, zs, h[:n])
        valid = ~np.isnan(tread)
        assert valid.mean() > .97, (r, "visual tread missing under the walker", valid.mean())
        seen = valid & (tread > POOL_FLOOR_LOW)
        diff = h[:n][seen] - tread[seen]
        assert diff.min() >= -.25 and diff.max() <= .45, (r, "ramp - tread", diff.min(), diff.max())
        worst = [min(worst[0], dy.min()), max(worst[1], dy.max()), min(worst[2], diff.min()), max(worst[3], diff.max())]
    print(f"PASS (a) walker climbs {len(RADII)} circles to 74.0 and over the bridge: rise {worst[0]:.3f}..{worst[1]:.3f}"
          f" per 0.05 stud ({len(ramp)} ramp boxes)", flush=True)
    print(f"PASS (b) ramp - visible tread {worst[2]:.3f}..{worst[3]:.3f} (allowed -0.25..+0.45)", flush=True)
    worst_dot = 1.0
    for b, is_ramp in [(b, True) for b in ramp] + [(b, False) for b in parapet]:
        # Reference point: a ramp box's top-face centre (its walking surface; the pitch shifts the box centre
        # sideways by thickness/2 * sin(pitch)), a parapet box's centre.
        ref = b["c"] + (b["h"][1] * b["R"][:, 1] if is_ramp else 0)
        radial = ref[[0, 2]] - SC
        radial /= np.linalg.norm(radial)
        x = b["R"][[0, 2], 0]
        assert abs(b["R"][1, 0]) < 1e-6, (b["name"], "X not horizontal")
        worst_dot = min(worst_dot, abs(x @ radial) / np.linalg.norm(x))
    assert worst_dot >= .999, worst_dot
    print(f"PASS (c) ramp and parapet colliders have radial X (min |dot| {worst_dot:.5f})", flush=True)
    parts = connected_parts(stair_tris)
    band = max(parts, key=lambda t: np.linalg.norm(t[:, :, [0, 2]] - SC, axis=2).max())
    for b in parapet:
        assert inside_solid(band, corners(b)).all(), (b["name"], "corner outside the parapet solid")
    # Every other non-ramp, non-core box (stair base, bridge south guard) sits inside a visible closed body.
    others = boxes(spiral["colliders"], lambda r: not r["attrs"].get("Level2_StairRamp") and "Parapet" not in r["name"])
    for b in others:
        pts = b["c"] + (corners(b) - b["c"]) * .99
        ok = np.zeros(len(pts), bool)
        for solid in parts:
            ok |= inside_solid(solid, pts)
        assert ok.all(), (b["name"], "collider corner outside every visible body (ghost collision)")
    th = np.arange(math.radians(-1170 + 60) + .01, TH1 - .005, .02 / 15.2)
    pts = []
    for rho in (15.15, 15.3):     # inside every chord box: 15.0 / cos(half angle) = 15.10
        for dy in (-1.8, .5, 2.6):
            pts.append(np.stack([SC[0] + rho * np.cos(th), ramp_y(th) + dy, SC[1] + rho * np.sin(th)], 1))
    pts = np.concatenate(pts)
    covered = inside_boxes(parapet, pts)
    assert covered.all(), ("parapet collision gap", pts[~covered][:4])
    ts = th[::50]
    ramp_top = union_top(ramp, SC[0] + 14.9 * np.cos(ts), SC[1] + 14.9 * np.sin(ts), ramp_y(ts))
    cap = band_top(band, ts)
    assert np.all(cap - ramp_top >= 3.4), (cap - ramp_top).min()
    print(f"PASS (d) {len(parapet)} parapet colliders inside the band solid, {len(others)} base/guard colliders inside"
          f" the stair/parapet, no gap along {len(pts)} samples,"
          f" band top >= ramp + {np.min(cap - ramp_top):.2f}", flush=True)
    bridge = boxes([r for r in spiral["parts"] if r["name"] == "Level 2 Exit Spiral Bridge"])
    bottom_signs = np.array([(i, -1, k) for i in (-1, 1) for k in (-1, 1)], float)
    protruding = []
    for b in ramp:
        bpts = b["c"] + (bottom_signs * b["h"] * .99) @ b["R"].T
        ok = (bpts[:, 1] < -3.5) | inside_boxes(bridge, bpts, 1e-4)
        for solid in parts:
            ok |= inside_solid(solid, bpts)
        if not ok.all():
            protruding.append(b["name"])
    assert not protruding, ("ramp bottom outside the stair, bridge and pool floor", protruding[:5])
    print(f"PASS (f-ramp) {len(ramp)} ramp boxes: bottom corners inside the stair body, the bridge or under the pool floor",
          flush=True)


def union_top(bs, xs, zs, near, window=1.0):
    """Highest box top on each vertical line within `window` of `near` (the current turn only)."""
    tops = np.array([top_along_vertical(b, xs, zs) for b in bs])
    tops = np.where(np.abs(tops - near) < window, tops, -np.inf)
    return tops.max(0)


def band_top(band, th):
    """Highest point of the parapet solid on short vertical lines across the band at angle th."""
    out = []
    for t in th:
        best = -np.inf
        for rho in np.linspace(14.97, 15.58, 9):
            x, z = SC[0] + rho * math.cos(t), SC[1] + rho * math.sin(t)
            y = horizontal_or_any_top(band, x, z, ramp_y(t) + 3.5)
            best = max(best, y)
        out.append(best)
    return np.array(out)


def horizontal_or_any_top(tris, x, z, near):
    """Highest triangle crossing the vertical line (x, z) within 2 studs of `near`."""
    a, b, c = tris[:, 0], tris[:, 1], tris[:, 2]
    P = np.array((x, z))
    A, B, Cc = a[:, [0, 2]], b[:, [0, 2]], c[:, [0, 2]]
    v0, v1, v2 = B - A, Cc - A, P - A
    d00, d01, d11 = (v0 * v0).sum(1), (v0 * v1).sum(1), (v1 * v1).sum(1)
    d20, d21 = (v2 * v0).sum(1), (v2 * v1).sum(1)
    den = d00 * d11 - d01 * d01
    ok = np.abs(den) > 1e-12
    den = np.where(ok, den, 1)
    v = (d11 * d20 - d01 * d21) / den
    w = (d00 * d21 - d01 * d20) / den
    hit = ok & (v >= 0) & (w >= 0) & (v + w <= 1)
    y = (1 - v - w) * a[:, 1] + v * b[:, 1] + w * c[:, 1]
    y = y[hit & (np.abs(y - near) < 2)]
    return y.max() if len(y) else -np.inf


def check_platform(manifest, chunks):
    plat = manifest["components"]["ExitPlatform"]
    tris = component_triangles(manifest, chunks, "ExitPlatform")
    deck = next(r for r in plat["parts"] if r["name"] == "Level 2 Exit Platform Deck")
    dpos, _ = frame(deck["cf"])
    east = dpos[0] + deck["size"][0] / 2
    assert abs(east - 34.0) < 1e-6 and abs(dpos[1] + deck["size"][1] / 2 - 74.0) < 1e-6, (east, dpos)
    assert not any("Portal" in r["name"] for r in plat["parts"]), "exit portal walls must be gone"
    solids = connected_parts(tris)
    lip_nose = [b for b in boxes(plat["colliders"]) if "Lip" in b["name"] or "Nose Ground" in b["name"]]
    deck_box = boxes([deck])[0]
    for b in lip_nose:
        pts = corners(b)
        shrunk = b["c"] + (pts - b["c"]) * .97     # corners pulled 3% inward: no face-on-face parity ties
        ok = inside_boxes([deck_box], shrunk, 1e-4)
        for solid in solids:
            ok |= inside_solid(solid, shrunk)
        if "Lip" in b["name"]:
            # The kerb's half-round cap: the box's top corners stand over the round's shoulders, never above its
            # crown (74.85).
            ok |= (shrunk[:, 1] > 74.5) & (shrunk[:, 1] <= 74.86)
        assert ok.all(), (b["name"], "corner outside the deck / nose / lip silhouette", shrunk[~ok][:2])
    print(f"PASS (f) deck east face at local x 34 (E-2.0), deck top 74, {len(lip_nose)} lip/nose colliders inside"
          " the visible deck, nose and kerb; no portal walls", flush=True)


def check_budget(manifest):
    comps = manifest["components"]
    counts = {n: len(comps[n]["parts"]) + len(comps[n]["colliders"]) + len(comps[n]["chunks"])
              for n in EXIT_INSTANCE_BUDGET}
    over = {n: (c, EXIT_INSTANCE_BUDGET[n]) for n, c in counts.items() if c > EXIT_INSTANCE_BUDGET[n]}
    assert not over, ("instance budget exceeded (count, budget)", over)
    print(f"PASS (g) instances per component {counts} (budget {EXIT_INSTANCE_BUDGET}); exit total "
          f"{sum(v for k, v in counts.items() if k.startswith('Exit'))} + 3 pumps x {counts['PumpStation']}", flush=True)


def check_closure(manifest, chunks):
    names = sorted({c for c, _ in chunks if c.startswith("Exit")})
    assert {"ExitSpiral", "ExitPlatform", "ExitCollar", "ExitMouthTrim", "ExitTubeVisual"} <= set(names), names
    assert "ExitSkylight" not in names and "ExitMouth" not in names, "retired exit components still exported"
    for name in names:
        bad, count = closure_failures(component_triangles(manifest, chunks, name))
        assert bad == 0, (name, bad, "edges not shared by exactly two triangles")
    print(f"PASS (e) closed solids: {', '.join(names)}", flush=True)


def check_trim_rows(manifest, chunks):
    tris, uvs = [], []
    for (name, material), chunk in chunks.items():
        if name == "ExitSpiral" and material == "Tile":
            pos = chunk["positions"] + np.asarray(chunk["record"]["center"], float)
            tris.append(pos[chunk["indices"][:, :, 0]])
            uvs.append(chunk["uv"][chunk["indices"][:, :, 2]])
    tris, uvs = np.concatenate(tris), np.concatenate(uvs)
    n = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
    n /= np.maximum(np.linalg.norm(n, axis=1), 1e-12)[:, None]
    c = tris.mean(1)
    d = c[:, [0, 2]] - SC
    rho = np.linalg.norm(d, axis=1)
    radial = np.abs((n[:, [0, 2]] * d).sum(1)) / np.maximum(rho, 1e-9)
    ys = tris[:, :, 1]
    rows = (1 - uvs[:, :, 1]) * 8                       # tile rows (8 per texture repeat), export stores 1 - v
    lo, hi = rows.min(1), rows.max(1)
    inside = np.floor(lo + 1e-4) != np.floor(hi - 1e-4)   # a whole-tile line strictly inside the triangle's v range
    groups = {
        "riser": (np.abs(n[:, 1]) < .2) & (radial < .3) & (rho < 14.9) & (np.ptp(ys, 1) <= .5 + 1e-6),
        "chamfer": (ys.min(1) >= 77.2 - 1e-6) & (ys.max(1) <= 77.5 + 1e-6) & (n[:, 1] > .2) & (n[:, 1] < .9) &
                   (rho < 5.1),
        "parapet crown": (n[:, 1] > .9) & (rho > 14.95) & (rho < 15.6),
    }
    counts = {}
    for label, mask in groups.items():
        counts[label] = int(mask.sum())
        assert counts[label] > 0, (label, "no triangles found: the selection no longer matches the stair")
        bad = np.nonzero(mask & inside)[0]
        assert not len(bad), (label, "grout line inside a one-row trim", c[bad[:4]].round(2).tolist())
    print(f"PASS (h) one tile row, no grout line inside: {counts} triangles", flush=True)


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    path = export_dir(argv)
    manifest, chunks = load_export(path)
    print(f"export {path}", flush=True)
    check_stair(manifest, chunks)
    check_closure(manifest, chunks)
    check_platform(manifest, chunks)
    check_budget(manifest)
    check_trim_rows(manifest, chunks)
    print("EXIT STAIR OK", flush=True)


if __name__ == "__main__":
    main()
