"""Run the permanent Poolrooms kit, builder-preservation and collision audits.

    python -B tools/tests/test_level2_kit_collision.py [world_*.json ...]
    python -B tools/tests/test_level2_kit_collision.py --all

The three frozen dumps are the default regression set. Audit failures are test
failures, so known-bad dumps intentionally return a nonzero status. Before the
audit, mutations prove each rule both ways: a mirrored arc-box yaw and a deleted
collider fail; a documented rename, a covering 'Level 2 Run' collider and a
collider above the ceiling plane are accepted, and the same three fail again
once the rename changes size, the run stops covering, or the dropped collider
sits below the ceiling. The top-cove rule (CoveTop* fills and swerve pieces'
'Swerve Top Cove Fill' boxes above C - 4) is proved the same way, once per
family. A dump with no real drop for a height rule gets a planted one. The
LATTICE_SPEC kit names are checked first: a CoveBaseStopCorner_* is judged as a
straight cove (wall plane + floor backing), the corner pieces stay radial.
"""
from __future__ import annotations

import copy
import json
import math
from pathlib import Path
import re
import sys

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "level2_poolrooms"))
import collision_audit  # noqa: E402


def mini_world(world, placement, parts):
    return {"kitExports": world["kitExports"], "layout": world["layout"], "components": [placement], "parts": parts}


def lost_names(world, placement, parts, chunks):
    lost = collision_audit.builder_check(mini_world(world, placement, parts), chunks)["lostColliders"]
    return set(lost.get(placement["component"], {}).get("names", []))


def mutation_checks(dump):
    """Prove the regressions from F12-PERM trip their checks and the documented consolidations are exact."""
    yaw = math.degrees(math.atan2(-1, 3))
    def chain(angle):
        return {"colliders": [{"name": f"Wall Block {i + 1}", "cf": [i * 3, 0, i, angle],
                               "size": [3.2, 2, .5]} for i in range(3)]}
    assert not collision_audit.chain_yaw_failures("CurveWall_Mutation", chain(yaw))
    assert collision_audit.chain_yaw_failures("CurveWall_Mutation", chain(-yaw))
    print("MUTATION PASS: mirrored arc-box yaw fails chain parallelism", flush=True)

    world = collision_audit.load_world(dump)
    chunks = collision_audit.load_kit_chunks(world)
    placements, owner = collision_audit.placements_of(world)
    manifest = collision_audit.world_manifests(world)
    parts_of = {}
    for part in world["parts"]:
        if part["id"] in owner:
            parts_of.setdefault(owner[part["id"]], []).append(part)
    halls = {h["Index"]: h for h in world["layout"]["Halls"]}
    done = set()
    for i, placement in enumerate(placements):
        records = manifest[placement["component"]].get("colliders", [])
        parts = parts_of.get(i, [])
        available = {p["name"] for p in parts if p["canCollide"]}
        if not records or lost_names(world, placement, parts, chunks):
            continue
        for rec in records:
            victim = next((p for p in parts if p["name"] == rec["name"] and p["canCollide"]), None)
            renamed = next((p for p in parts if p["canCollide"] and
                            any(dst.match(p["name"]) for _, dst in collision_audit.BUILDER_RENAMES)), None)
            if "rename" not in done and rec["name"] not in available and renamed is not None:
                bad = [dict(p, size=[s + 1 for s in p["size"]]) if p is renamed else p for p in parts]
                assert rec["name"] in lost_names(world, placement, bad, chunks)
                print(f"MUTATION PASS: documented rename '{renamed['name']}' accepted, fails once its size changes",
                      flush=True)
                done.add("rename")
            if victim is None:
                continue
            rule = collision_audit.accepted_loss(world, placement, rec, [], None, halls)
            rest = [p for p in parts if p is not victim]
            if rule is None and "delete" not in done:
                assert rec["name"] in lost_names(world, placement, rest, chunks)
                print(f"MUTATION PASS: deleting {victim['name']} fails collider preservation", flush=True)
                done.add("delete")
            if rule is None and "run" not in done and "Cylinder" not in str(victim["shape"]):
                run = dict(copy.deepcopy(victim), id=-1, name="Level 2 Run Mutation", fixtureComponent=None,
                           fixtureKind=None, size=[s + .02 for s in victim["size"]])
                assert not lost_names(world, placement, rest + [run], chunks), "covering run collider rejected"
                k = int(np.argmax(run["size"]))
                short = dict(run, size=[s * .5 if j == k else s for j, s in enumerate(run["size"])])
                assert rec["name"] in lost_names(world, placement, rest + [short], chunks)
                print(f"MUTATION PASS: a covering 'Level 2 Run' collider replaces {victim['name']}, "
                      "a shorter one fails", flush=True)
                done.add("run")
        if {"rename", "delete", "run"} <= done:
            break
    for rule, family in (("ceiling", "other"), ("topcove", "CoveTop"), ("topcove", "Swerve")):
        prove_height_rule(world, chunks, placements, parts_of, manifest, halls, rule, family)
        done.add(rule)
    if not {"rename", "delete", "run", "ceiling", "topcove"} <= done:
        raise AssertionError(f"builder mutations incomplete, only proved {sorted(done)}")


def record_low(placement, rec):
    """Lowest world Y of a kit record's box under this placement (the height the ceiling/topcove rules judge)."""
    ppos, prot = collision_audit.placement_frame(placement)
    rpos, rrot = collision_audit.record_frame(rec["cf"])
    return float(collision_audit.record_box_samples((ppos + prot @ rpos, prot @ rrot), rec["size"])[:, 1].min())


def prove_height_rule(world, chunks, placements, parts_of, manifest, halls, rule, family):
    """The ceiling/topcove rules both ways: a dropped record whose box sits 0.25 above the rule's plane is accepted,
    the same drop 0.25 below it fails. Uses a record the builder really dropped when the dump has one, otherwise
    plants one: any hall placement of the family with the record's part removed and the placement raised."""
    def family_of(placement, rec):
        if not collision_audit.is_top_cove_fill(placement, rec):
            return "other"
        return "Swerve" if rec["name"].startswith("Swerve Top Cove Fill") else "CoveTop"
    best = None
    for i, placement in enumerate(placements):
        hm = re.search(r"Level 2 Hall (\d+)\b", placement["modelPath"])
        if not hm or int(hm.group(1)) not in halls:
            continue
        h = halls[int(hm.group(1))]
        plane = h["FloorY"] + h["CeilingClass"] - (4 if rule == "topcove" else 0)
        records = manifest[placement["component"]].get("colliders", [])
        names = [r["name"] for r in records]
        have = {p["name"] for p in parts_of.get(i, []) if p["canCollide"]}
        for rec in records:
            if names.count(rec["name"]) != 1 or family_of(placement, rec) != family:
                continue
            dropped = rec["name"] not in have and record_low(placement, rec) >= plane + .25
            if best is None or dropped and not best[3]:
                best = (placement, rec, plane, dropped, i)
            if dropped:
                break
        if best and best[3]:
            break
    assert best, f"no hall placement holds a {family} collider record to prove the {rule} rule with"
    placement, rec, plane, dropped, i = best
    rest = [p for p in parts_of.get(i, []) if p["name"] != rec["name"]]

    def shifted(dy):
        return dict(placement, pivot=[placement["pivot"][0], placement["pivot"][1] + dy] + placement["pivot"][2:])
    low = record_low(placement, rec)
    above = placement if dropped else shifted(plane + .25 - low)
    below = shifted(plane - .25 - low)
    assert collision_audit.accepted_loss(world, above, rec, [], None, halls) == rule
    assert rec["name"] not in lost_names(world, above, rest, chunks), f"{rule} rule rejected {rec['name']}"
    assert collision_audit.accepted_loss(world, below, rec, [], None, halls) is None
    assert rec["name"] in lost_names(world, below, rest, chunks), f"{rule} rule accepted {rec['name']} below its plane"
    how = "the builder's own drop" if dropped else "a planted drop (raised to 0.25 above its plane)"
    print(f"MUTATION PASS: {rule} rule accepts {how} of {placement['component']} '{rec['name']}' "
          "and fails the same drop 0.25 below the plane", flush=True)


def world_mutations(dump):
    """Plant a ghost collider (invisible, colliding) and a solid-looking prop with no collider beside ElevatorSpawn;
    the world audit must name both (C4 and C1/C2)."""
    world = collision_audit.load_world(dump)
    chunks = collision_audit.load_kit_chunks(world)
    spawn = next(p for p in world["parts"] if p["name"] == "ElevatorSpawn")
    base = next(p for p in world["parts"] if p["canCollide"] and p["transparency"] < .98 and
                p["class"] == "Part" and "Floor" in p["name"] and
                abs(p["cframe"][0] - spawn["cframe"][0]) < p["size"][0] / 2 and
                abs(p["cframe"][2] - spawn["cframe"][2]) < p["size"][2] / 2)
    top = base["cframe"][1] + base["size"][1] / 2
    x, z = spawn["cframe"][0], spawn["cframe"][2]
    inward = 1.0 if base["cframe"][0] > x else -1.0         # toward the middle of the spawn hall's floor
    def box(name, dz, collide, transparency):
        return dict(base, id=-1, name=name, path=base["parentPath"] + "." + name, fixtureComponent=None,
                    fixtureKind=None, canCollide=collide, transparency=transparency, size=[4.0, 4.0, 4.0],
                    cframe=[x + 12 * inward, top + 2.0, z + dz] + [1, 0, 0, 0, 1, 0, 0, 0, 1])
    world["parts"] += [box("Level 2 Mutation Ghost Collider", 8, True, 1),
                       box("Level 2 Mutation Prop Without Collider", -8, False, 0)]
    report = collision_audit.world_audit(world, chunks, log=lambda *a: None)
    ghost = [row for row in report["invisible"] if "Mutation Ghost Collider" in row["collider"] and row["fails"]]
    prop = [row for row in report["visual"] if "Mutation Prop Without Collider" in row["label"] and row["fails"]]
    assert ghost, "C4 missed an invisible colliding box in reachable space"
    print("MUTATION PASS: C4 names an invisible colliding box beside the spawn", flush=True)
    assert prop, "C1/C2 missed a visible box without collision in reachable space"
    print("MUTATION PASS: C1/C2 name a visible box without collision beside the spawn", flush=True)


def kit_expectations():
    """LATTICE_SPEC kit names reach the right A2 rules: a CoveBaseStopCorner_* (a 3-stud stop with a 0.25 straight
    tail at a square corner) is a STRAIGHT cove backed by its wall plane and floor, not a corner piece; the corner
    pieces (tori, vertical fillets, inner mitres) stay radial. Checked on planted components and on every such
    component the current kit exports."""
    straight = {"attrs": {"WallSide": "+Z", "WallPlane": 0, "Radius": 3}, "markers": []}
    for name in ("CoveBaseStopCorner_PX", "CoveBaseStop_NX", "CoveBase128", "CoveTop1"):
        direction, virtual, cap = collision_audit.exposed_setup(name, straight)
        behind, room = virtual(np.array(((0, 1.0, .3), (0, 1.0, -2.0))))     # in the wall / out in the room
        assert cap == 0 and behind == 0 and room > .5, (name, cap, behind, room)
    for name in ("CoveBaseCorner_R8", "CoveTopCorner_R24", "CornerCove_R16_H42", "CoveBaseInnerCorner"):
        assert collision_audit.exposed_setup(name, straight)[2] is None, name
    comps = {}
    for d in collision_audit.default_kit_dirs():
        comps.update(json.loads((d / "manifest.json").read_text(encoding="utf-8"))["components"])
    stops = [n for n in comps if n.startswith("CoveBaseStopCorner_")]
    for name in stops:
        assert collision_audit.exposed_setup(name, comps[name])[2] == 0, f"{name} is not judged as a straight cove"
    print(f"KIT PASS: stop-corner coves are straight, corner pieces radial ({len(stops)} CoveBaseStopCorner_* in "
          "the current kit)", flush=True)


def main(argv=None):
    args = list(sys.argv[1:] if argv is None else argv)
    kit_expectations()
    if "--no-world" not in args:
        dump = next((Path(a) for a in args if a.endswith(".json")), collision_audit.DEFAULT_DUMPS[0])
        mutation_checks(dump)
        world_mutations(dump)
    return collision_audit.main(args)


if __name__ == "__main__":
    raise SystemExit(main())
