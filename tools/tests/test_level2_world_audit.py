"""Run all twelve Blender world geometry checks on Poolrooms dumps, plus planted controls.

    python -B tools/tests/test_level2_world_audit.py [world_*.json ...] [--no-mutations]

The Blender script writes one JSON report per dump and raises on any failed
check. Before that, defects the owner reported are injected into a copy of the
first dump (a coplanar quad on a wall, a swerve skin overlapping its neighbour's
deck - the S-In/S-Out joint class -, a convex cove, a straight cove left with a
free end, a floating column, a short water box, a hanging light well, a missing
ceiling tile, a pressure door turned 40 deg so its disc cuts obliquely into its
round tunnel, a square tiled block pushed 1 stud into a tunnel wall, a plate laid
exactly on another plate's top face, a Hall Lintel moved half a tile along its
wall); each MUST be named by its check, or the runner fails: an audit that
cannot see a planted defect proves nothing. Negative controls MUST NOT be named:
the seated pressure doors in their own tunnels (07), a plate tilted so its plane
passes within 0.005 of another's at the world origin while lying 1.5 under it
where they overlap (08, the GB false positive), and a Hall Lintel moved one whole
tile along its wall (12). The two check-12 lintels are real lintels over round
tunnels that continued the lattice before the move; a world that is not on the
lattice yet has none, and then two lintel plates are planted flush in a wall on
that wall's own grid and moved instead (tile = the dump's pitch, so half = 0.25
and whole = 0.5 under LATTICE_SPEC).

The PC is shared with other kit jobs: each Blender run waits (bounded by
--blender-wait seconds) until fewer than four Blender processes are running.
"""
from __future__ import annotations

import argparse
from collections import defaultdict
import json
import math
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "level2_poolrooms"))
import collision_audit as ca  # noqa: E402
import lattice_audit as la  # noqa: E402

DEFAULT_DUMPS = [Path(f"G:/Blender/Level2_Poolrooms/worlds/world_{seed}.json")
                 for seed in (837834, 1, 101)]
MUTATION_SEED = 990001
WALL = re.compile(r"^Level 2 Hall Wall \d+ (North|South|East|West)$")


def frame(cf):
    return np.asarray(cf[:3], float), np.asarray(cf[3:12], float).reshape(3, 3)


def place(part, pos, rot):
    part["cframe"] = [float(v) for v in pos] + [float(v) for v in rot.reshape(-1)]


def hall_of_path(world, path):
    m = re.search(r"Level 2 Hall (\d+)\b", path)
    return next((h for h in world["layout"]["Halls"] if m and h["Index"] == int(m.group(1))), None)


def mutate(world):
    """Plant defects in a copy of `world`; returns {check: [{row key: text the naming row must contain}]}."""
    placements, owner = ca.placements_of(world)
    parts_of = {}
    for part in world["parts"]:
        if part["id"] in owner:
            parts_of.setdefault(owner[part["id"]], []).append(part)
    manifest = ca.world_manifests(world)
    spawn = np.asarray(next(p for p in world["parts"] if p["name"] == "ElevatorSpawn")["cframe"][:3], float)
    home = next(h for h in world["layout"]["Halls"] if h["MinX"] <= spawn[0] <= h["MaxX"] and
                h["MinZ"] <= spawn[2] <= h["MaxZ"])
    expect = defaultdict(list)

    # 08 z-fight: a 4x4 tile quad whose face lies exactly on a long wall face of the spawn hall, facing the room,
    # on the wall segment farthest from the spawn (the elevator and arrival door sit near the spawn).
    walls = [p for p in world["parts"] if WALL.match(p["name"]) and hall_of_path(world, p["parentPath"]) is home
             and max(p["size"][0], p["size"][2]) >= 16]
    wall = max(walls, key=lambda p: np.linalg.norm(np.asarray(p["cframe"][:3])[[0, 2]] - spawn[[0, 2]]))
    c, r = frame(wall["cframe"])
    ext = np.abs(r) @ (np.asarray(wall["size"], float) / 2)
    side = WALL.match(wall["name"]).group(1)
    axis, sign = {"North": (2, 1), "South": (2, -1), "West": (0, 1), "East": (0, -1)}[side]
    face = c.copy()
    face[axis] = c[axis] + sign * ext[axis]
    face[1] = home["FloorY"] + 6
    n_in = np.zeros(3)
    n_in[axis] = sign
    quad = dict(wall, id=-1, name="Level 2 Mutation Coplanar Quad", path=wall["parentPath"] + ".Level 2 Mutation Coplanar Quad",
                canCollide=False, fixtureComponent=None, fixtureKind=None, transparency=0)
    quad["size"] = [4.0, 4.0, 0.4] if axis == 2 else [0.4, 4.0, 4.0]
    place(quad, face - n_in * 0.2, np.eye(3))
    world["parts"].append(quad)
    expect["08_zfight"].append({"pair": "Mutation Coplanar Quad"})

    # 08 z-fight, swerve joints: a copy of one S skin slid 1.5 studs back along its travel overlaps the skin it
    # joins on the deck top, the S-In/S-Out overlap class (VERIFY 2026-10-05: ~35 stud^2 per S pair).
    i = next(i for i, p in enumerate(placements) if p["component"].startswith("SwerveS_") and i in parts_of)
    travel = frame(placements[i]["pivot"])[1] @ np.array((1.0, 0, 0))
    for n, part in enumerate(p for p in parts_of[i] if p.get("fixtureKind") == "mesh"):
        name = "Level 2 Mutation Swerve Overlap_" + part["name"].rsplit("_", 1)[-1]
        ghost = dict(part, id=-10 - n, name=name, path=part["parentPath"] + "." + name)
        pos, rot = frame(part["cframe"])
        place(ghost, pos - 1.5 * travel, rot)
        world["parts"].append(ghost)
    expect["08_zfight"].append({"pair": "Mutation Swerve Overlap"})

    # 06 coves: turn one straight base cove into a convex bullnose (180 deg about its run axis through the fillet
    # centre line), the owner's image 1.
    i = next(i for i, p in enumerate(placements) if re.match(r"CoveBase\d", p["component"]) and hall_of_path(world, p["modelPath"]))
    attrs = manifest[placements[i]["component"]]["attrs"]
    R = float(attrs.get("Radius", 3))
    pos, rot = frame(placements[i]["pivot"])
    ws = attrs.get("WallSide", "+Z")
    to_wall = rot @ (np.eye(3)["XYZ".index(ws[-1])] * (-1 if ws[0] == "-" else 1))
    along = rot @ np.eye(3)[0] if ws[-1] == "Z" else rot @ np.eye(3)[2]
    centre = pos - to_wall * (R / 2) + np.array((0, R / 2, 0))
    flip = 2 * np.outer(along, along) - np.eye(3)
    for part in parts_of[i]:
        p, q = frame(part["cframe"])
        place(part, centre + flip @ (p - centre), flip @ q)
    expect["06_coves"].append({"path": placements[i]["modelPath"]})
    convex_hall = hall_of_path(world, placements[i]["modelPath"])

    # 06 coves, free end: delete one straight cove run piece in a plain (non-swerve) hall; the run piece it touched
    # must now end free.
    chunks = ca.load_kit_chunks(world)
    def run_span(i):
        t = np.concatenate([ca.mesh_triangles_world(p, ca.fixture_chunk(p, chunks))
                            for p in parts_of[i] if p.get("fixtureKind") == "mesh"]).reshape(-1, 3)
        return t.min(0), t.max(0)
    runs = [i for i, p in enumerate(placements) if re.match(r"Cove(Base|Top)\d", p["component"]) and i in parts_of
            and hall_of_path(world, p["modelPath"]) not in (None, convex_hall)
            and not hall_of_path(world, p["modelPath"]).get("Swerve")]
    spans = {i: run_span(i) for i in runs}
    def touching(i, j):                         # same wall line and family, end to end
        (lo, hi), (lo2, hi2) = spans[i], spans[j]
        same = placements[i]["component"][:7] == placements[j]["component"][:7] and             hall_of_path(world, placements[i]["modelPath"]) is hall_of_path(world, placements[j]["modelPath"])
        flat = np.abs(hi - lo) < 4                  # the run's two thin axes (depth, height)
        return same and np.allclose(lo[flat], lo2[flat], atol=.05) and np.allclose(hi[flat], hi2[flat], atol=.05)             and any(abs(hi[k] - lo2[k]) < .05 or abs(hi2[k] - lo[k]) < .05 for k in (0, 2) if not flat[k])
    victim, neighbour = next((i, j) for i in runs for j in runs if j != i and touching(i, j))
    gone = {id(p) for p in parts_of[victim]}
    world["parts"] = [p for p in world["parts"] if id(p) not in gone]
    expect["06_coves"].append({"path": placements[neighbour]["modelPath"], "issue": "free end"})

    # 04 floating: lift one hall column 5 studs (its G4 foot starts 4 below the floor, so 1 stud stays buried).
    i = next(i for i, p in enumerate(placements) if p["component"].startswith("Column") and hall_of_path(world, p["modelPath"]))
    for part in parts_of[i]:
        p, q = frame(part["cframe"])
        place(part, p + (0, 5.0, 0), q)
    expect["04_floating"].append({"path": placements[i]["modelPath"]})

    # 05 water: pull one axis-aligned hall water box 8 studs back from its +X wall.
    k = max((k for k, r in enumerate(world["terrainWaterRegions"])
             if str(r.get("label", "")).startswith("Hall ") and np.allclose(r["cframe"][3:], np.eye(3).reshape(-1))),
            key=lambda k: world["terrainWaterRegions"][k]["size"][0] * world["terrainWaterRegions"][k]["size"][2])
    region = world["terrainWaterRegions"][k]
    region["size"][0] -= 8
    region["cframe"][0] -= 4
    expect["05_water"].append({"space": region["label"] + " "})

    # 02 ceiling: drop one light well 2 studs below its ceiling plane (owner's image 6).
    i = next(i for i, p in enumerate(placements) if p["component"].startswith("LightWell_R6"))
    for part in parts_of[i]:
        p, q = frame(part["cframe"])
        place(part, p - (0, 2.0, 0), q)
    expect["02_ceiling"].append({"path": placements[i]["modelPath"]})
    # 01 leaks: lift the spawn hall's largest ceiling tile away (a hole to the sky above the room).
    tiles = [p for p in world["parts"] if "Overhead Tile" in p["name"] and hall_of_path(world, p["parentPath"]) is home]
    tile = max(tiles, key=lambda p: p["size"][0] * p["size"][2])
    world["parts"].remove(tile)
    expect["01_leaks"].append({"where": f"Hall {home['Index']} "})

    # 07 intersect: turn one pressure door 40 deg about the vertical through its centre. The seated door meets its
    # tube only at square junctions (exempt, a door in its frame); the turned disc cuts the bore wall obliquely.
    # Renamed so the row is unambiguous; the "Level 2 Pressure Door " prefix keeps it open for the reach flood.
    door = next(p for p in world["parts"] if re.fullmatch(r"Level 2 Pressure Door \d+", p["name"]))
    stripe = door["name"].replace("Door", "Door Stripe")
    world["parts"] = [p for p in world["parts"] if p["name"] != stripe]
    door["name"] = "Level 2 Pressure Door Tilted"
    door["path"] = door["parentPath"] + "." + door["name"]
    pos, rot = frame(door["cframe"])
    place(door, pos, ca.ry(np.radians(40)) @ rot)
    expect["07_intersect"].append({"pair": ["Pressure Door Tilted", "RoundTunnel_"]})
    # 07 negative: every other pressure door stays seated in the round tunnel of its own corridor (square junctions).
    expect["07_intersect"].append({"pair": DOOR_ROW, "absent": True})

    # 07 intersect: a square tiled block pushed 1 stud into the wall of the spawn hall's own round tunnel, at the
    # bore's axis height halfway along. It is 1.2 tall so that every crease with the bore's facets there is within
    # 10 deg of square (SQUARE_COS): with tubes counted as 'support' (before LATTICE_SPEC 5) it was not seen at all.
    # 40 long, so the tube's 4000 penetration samples land in it (about 10 expected).
    tunnels = [c for c in world["layout"]["Corridors"] if c["Kind"] == "Open" and c["Variant"] in ("Dry", "Wet")
               and c["Length"] >= 56]
    tunnel = next((c for c in tunnels if home["Index"] in (c["A"], c["B"])), tunnels[0])
    along = (tunnel["From"] + tunnel["To"]) / 2
    y = (tunnel["FromY"] + tunnel["ToY"]) / 2 + 13                   # bore axis (lattice_audit.BORE)
    radial = 16.6                                                     # the bore's inner face at axis height
    pos = (along, y, tunnel["Cross"] + radial) if tunnel["Axis"] == "X" else (tunnel["Cross"] + radial, y, along)
    size = [40.0, 1.2, 2.0] if tunnel["Axis"] == "X" else [2.0, 1.2, 40.0]
    block = dict(wall, id=-20, name="Level 2 Mutation Tunnel Block", canCollide=True, fixtureComponent=None,
                 fixtureKind=None, transparency=0, size=size, parentPath=wall["parentPath"],
                 path=wall["parentPath"] + ".Level 2 Mutation Tunnel Block")
    place(block, pos, np.eye(3))
    world["parts"].append(block)
    expect["07_intersect"].append({"pair": ["Mutation Tunnel Block", "RoundTunnel_"]})

    # 08 z-fight both ways (GB's check 08 fix), in the middle of the spawn hall: a flat 24-stud plate whose top lies
    # exactly on an 8-stud block's top (z-fighting: named), and the same plate tilted so that its plane, extrapolated
    # to the world origin, passes 0.003 from the other block's top plane while it lies 1.5 under that top where the
    # two overlap (a tilted basin floor against a threshold: not coplanar, not named).
    F = home["FloorY"]
    cx, cz = (home["MinX"] + home["MaxX"]) / 2, (home["MinZ"] + home["MaxZ"]) / 2
    k = 0 if abs(cx) >= abs(cz) else 2                              # tilt along the axis that is far from the origin
    assert max(abs(cx), abs(cz)) > 100, "the tilted-plate control needs a spawn hall far from the world origin"
    def plate(name, idn, size, centre, rot=np.eye(3)):
        p = dict(wall, id=idn, name=name, canCollide=True, fixtureComponent=None, fixtureKind=None, transparency=0,
                 size=list(map(float, size)), parentPath=wall["parentPath"], path=wall["parentPath"] + "." + name)
        place(p, centre, rot)
        world["parts"].append(p)
    shift = np.zeros(3)
    shift[2 - k] = 14.0                                             # the two pairs side by side across the tilt axis
    c1 = np.array((cx, 0, cz)) - shift
    c2 = np.array((cx, 0, cz)) + shift
    plate("Level 2 Mutation Flat Block", -30, (8, 1, 8), c1 + (0, F + 1.5, 0))
    plate("Level 2 Mutation Flat Plate", -31, (24, .2, 24), c1 + (0, F + 2 - .1, 0))
    expect["08_zfight"].append({"pair": ["Mutation Flat Block", "Mutation Flat Plate"]})
    top, low = F + 2.0, F + .5                                      # block top; tilted plate's top under its centre
    s = 0.0
    for _ in range(50):                                             # (low - s*c2[k]) / sqrt(1 + s^2) = top + 0.003
        s = (low - (top + .003) * math.sqrt(1 + s * s)) / c2[k]
    n = np.zeros(3)
    n[k], n[1] = -s, 1.0
    n /= np.linalg.norm(n)
    ex_ = np.eye(3)[0] - np.eye(3)[0] @ n * n if k == 0 else np.eye(3)[0]
    ex_ /= np.linalg.norm(ex_)
    rot = np.stack((ex_, n, np.cross(ex_, n)), 1)
    assert abs(np.linalg.det(rot) - 1) < 1e-9 and abs(((c2 + (0, low, 0)) @ n) - (top + .003)) < 1e-9
    plate("Level 2 Mutation Tilted Block", -32, (8, 1, 8), c2 + (0, F + 1.5, 0))
    plate("Level 2 Mutation Tilted Plate", -33, (24, .2, 24), c2 + (0, low, 0) - rot @ (0, .1, 0), rot)
    expect["08_zfight"].append({"pair": "Mutation Tilted", "absent": True})

    # 12 lattice: Hall Lintels over round tunnels moved along their wall, half a tile (named) and a whole tile (not
    # named). Each lintel is chosen so that it continued the lattice before the move (lattice_audit on its
    # neighbourhood, the same function check 12 runs), so the controls judge the move and nothing else.
    # A world that is not on the lattice yet (before LATTICE_SPEC I1-I4) has no such lintel: then two lintel plates are
    # planted flush in the spawn hall's far wall face, continuing that wall's own grid, and those are moved instead.
    tile = la.tile_of(world)
    chunks = ca.load_kit_chunks(world)
    clean = clean_lintels(world, chunks, tile, limit=2)
    if len(clean) < 2:
        clean = planted_lintels(world, wall, n_in, home, tile)
        print(f"LATTICE CONTROL: no two tunnel lintels continue the lattice in this world (tile {tile:g}); "
              "moving two lintel plates planted flush in the spawn hall's wall on its grid instead", flush=True)
    for (lintel, axis), (label, step) in zip(clean, (("Half", tile / 2), ("Whole", tile))):
        name = f"Level 2 Hall Lintel Mutation {label}"
        pos, rot = frame(lintel["cframe"])
        lintel.update(name=name, path=lintel["parentPath"] + "." + name)
        place(lintel, pos + axis * step, rot)
        expect["12_lattice"].append({"pair": f"Hall Lintel Mutation {label}", "absent": label == "Whole"})
    world["requestedSeed"] = MUTATION_SEED
    return expect


DOOR_ROW = re.compile(r"Pressure Door (Stripe )?#.*RoundTunnel_|RoundTunnel_.*Pressure Door (Stripe )?#")
TUNNEL_LINTEL_MIN = 30.0      # along-wall width of a lintel over a round tunnel's hole (34.08, 36 under LATTICE_SPEC)


def clean_lintels(world, chunks, tile, limit):
    """Up to `limit` (lintel, along-wall world axis) over round-tunnel holes none of whose seams steps (lattice_audit's
    seam_pieces on the lintel's neighbourhood, corners included - check 12 judges reveal corners: every part whose box
    comes within 6 studs of the lintel's)."""
    parts = world["parts"]
    boxes = np.array([np.concatenate(aabb(p)) for p in parts])
    out = []
    for p in parts:
        if not re.match(r"^Level 2 Hall Lintel \d+ (North|South|East|West)$", p["name"]):
            continue
        lo, hi = aabb(p)
        ext = hi - lo
        axis = 0 if ext[0] >= ext[2] else 2
        if ext[axis] < TUNNEL_LINTEL_MIN:
            continue
        near = np.all(boxes[:, :3] <= hi + 6, 1) & np.all(boxes[:, 3:] >= lo - 6, 1)
        local = [parts[i] for i in np.nonzero(near)[0]]
        if not any(str(q.get("fixtureComponent") or "").startswith("RoundTunnel_") for q in local):
            continue                                    # the exit hole's lintel, a pipe's: not over a round tunnel
        me = next(i for i, q in enumerate(local) if q is p)
        steps = 0
        for _, pa, pb, *_, along, across, _, _, cut in la.seam_pieces(local, chunks, tile, corners=True):
            mine = (pa == me) | (pb == me)
            steps += int((mine & (np.maximum(along, across) > la.MAX_OFFSET)).sum())
        if steps == 0:
            out.append((p, np.eye(3)[axis]))
            if len(out) == limit:
                break
    return out


def planted_lintels(world, wall, n_in, home, tile):
    """Two 8 x 6 tile plates set flush into `wall`'s room face (0.4 thick, half of it in the wall) at FloorY + 11 (above
    the 08 quad) and up to 10 studs either side of the face centre, each snapped so its anchored corner lies a whole number of tiles from the
    wall face's own (lattice_audit.ANCHOR): they continue the wall's grid. Returns [(plate, along-wall unit)]."""
    face = next(f for f in la.part_faces(wall, tile) if f["n"] @ n_in > .99)
    (ei, ej), (hi, hj) = face["e"], face["h"]                   # ei: up (every side face's first anchor axis)
    (_, si), (_, sj) = la.ANCHOR[face["face"]]
    anchor = face["c"] + ei * si * hi + ej * sj * hj
    pi, pj = 3 * tile, 4 * tile                                 # plate half sizes along ei, ej
    _, rot = frame(wall["cframe"])
    size = np.abs(rot.T @ (ei * 2 * pi + ej * 2 * pj + n_in * .4))
    out = []
    off = min(10.0, hj - pj - 1)
    assert off > pj + 2, "the spawn hall's far wall is too narrow for the planted lintel plates"
    for k, side in enumerate((-off, off)):
        centre = face["c"] + ej * side + ei * (ei @ (np.array((0, home["FloorY"] + 11, 0)) - face["c"]))
        delta = anchor - (centre + ei * si * pi + ej * sj * pj)
        snapped = anchor - ei * (round(delta @ ei / tile) * tile) - ej * (round(delta @ ej / tile) * tile)
        face_centre = snapped - ei * si * pi - ej * sj * pj
        name = f"Level 2 Hall Lintel Planted {k + 1}"
        plate = dict(wall, id=-40 - k, name=name, path=wall["parentPath"] + "." + name, canCollide=False,
                     fixtureComponent=None, fixtureKind=None, transparency=0, size=[float(v) for v in size])
        place(plate, face_centre - n_in * .2, rot)
        world["parts"].append(plate)
        out.append((plate, ej))
    for plate, _ in out:                                        # inlay seams in the wall face, none stepping
        pieces = [p for p in la.seam_pieces([wall, plate], {}, tile) if len(p[1])]
        worst = max((float(np.maximum(p[8], p[9]).max()) for p in pieces), default=None)
        assert worst is not None and worst <= la.MAX_OFFSET, f"{plate['name']} does not continue its wall ({worst})"
    return out


def aabb(p):
    c, r = frame(p["cframe"])
    e = np.abs(r) @ (np.asarray(p["size"], float) / 2)
    return c - e, c + e


def named(check, marker):
    """A row of the check names the marker: every key's text(s) occur in that row field (a compiled regex searches)."""
    def has(value, text):
        return text.search(value) is not None if isinstance(text, re.Pattern) else text in value
    rows = check.get("table") or check.get("examples", [])
    return any(all(all(has(str(row.get(key, "")), t) for t in (text if isinstance(text, list) else [text]))
                   for key, text in marker.items() if key != "absent")
               for row in rows + check.get("examples", []))


def wait_for_blender_slot(limit):
    """Block until fewer than four Blender processes run (never start a fifth), at most `limit` seconds."""
    deadline = time.monotonic() + limit
    while True:
        count = subprocess.run(["tasklist"], capture_output=True, text=True, check=True).stdout.lower().count("blender.exe")
        if count < 4:
            return
        if time.monotonic() >= deadline:
            raise SystemExit(f"{count} Blender processes still running after {limit} s; try again later")
        print(f"WAIT {count} Blender processes running; retrying in 20 s", flush=True)
        time.sleep(20)


def run_blender(args, dumps, out, only=""):
    wait_for_blender_slot(args.blender_wait)
    command = [str(args.blender), "-b", "--factory-startup", "--python-exit-code", "1",
               "-P", str(ROOT / "level2_poolrooms/world_audit.py"), "--", *map(str, dumps), "--out", str(out)]
    if only:
        command += ["--only", only]
    if args.crops:
        command += ["--crops", str(args.crops)]
    return subprocess.run(command, check=False).returncode


def mutation_controls(args, dump):
    world = json.loads(Path(dump).read_text(encoding="utf-8"))
    expect = mutate(world)
    with tempfile.TemporaryDirectory() as tmp:
        target = Path(tmp) / f"world_{MUTATION_SEED}.json"
        target.write_text(json.dumps(world), encoding="utf-8")
        only = ",".join(str(int(k[:2])) for k in sorted(expect))
        run_blender(args, [target], Path(tmp), only)
        report = json.loads((Path(tmp) / f"world_audit_{MUTATION_SEED}.json").read_text(encoding="utf-8"))
    missed = []
    for check, markers in sorted(expect.items()):
        result = report["checks"][check]
        for marker in markers:
            if marker.get("absent"):
                ok = not named(result, marker)
                print(f"CONTROL {'PASS' if ok else 'FAILED'}: {check} does not name the planted non-defect ({marker})",
                      flush=True)
            else:
                ok = not result["passed"] and named(result, marker)
                print(f"MUTATION {'PASS' if ok else 'MISSED'}: {check} names the planted defect ({marker})", flush=True)
            if not ok:
                missed.append(f"{check} {marker}")
    assert not missed, f"world audit misjudged planted controls: {missed}"


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("dumps", nargs="*", type=Path)
    ap.add_argument("--quick", action="store_true", help="audit the three frozen regression dumps (default)")
    ap.add_argument("--all", action="store_true", help="audit every world_*.json in the dump directory")
    ap.add_argument("--out", type=Path, default=Path("G:/Roblox/_local/l2fix/impl/WP5/audit"))
    ap.add_argument("--blender", type=Path, default=Path("D:/Blender/blender.exe"))
    ap.add_argument("--only", default="", help="comma-separated check numbers (default: all twelve)")
    ap.add_argument("--crops", type=int, default=0)
    ap.add_argument("--no-mutations", action="store_true", help="skip the planted-defect positive controls")
    ap.add_argument("--blender-wait", type=float, default=1800,
                    help="seconds to wait for a free Blender slot before giving up (default 1800)")
    args = ap.parse_args(argv)
    if args.all and (args.dumps or args.quick):
        ap.error("--all cannot be combined with explicit dump paths or --quick")
    dumps = (sorted(DEFAULT_DUMPS[0].parent.glob("world_*.json")) if args.all else args.dumps or DEFAULT_DUMPS)
    if not dumps or any(not p.is_file() for p in dumps):
        ap.error("one or more world dumps are missing")
    if not args.no_mutations:
        mutation_controls(args, dumps[0])
    args.out.mkdir(parents=True, exist_ok=True)
    return run_blender(args, dumps, args.out, args.only)


if __name__ == "__main__":
    raise SystemExit(main())
