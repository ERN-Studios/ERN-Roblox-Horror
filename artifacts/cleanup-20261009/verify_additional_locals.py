"""Propose LE-34 pure overwritten/constant locals and unread session field.

Actual whole RoomDressing Plan/Apply runs against offline engine boundaries;
actual PuzzleManager session literal runs with existing actual prompt handlers.
Writes only artifacts/temp files. No Studio/production/manifest/commits.
"""
import argparse
import difflib
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SHA = lambda data: hashlib.sha256(data).hexdigest()
DRESS = "ServerScriptService/Level 3 Systems/Level 3 Worn Party Room Dressing.ModuleScript.lua"
PUZZLE = "ServerScriptService/Level 1 Systems/PuzzleManager.Script.lua"
EDITS = [
    ("safeRect private constant parameter", "local function safeRect(rect, room, blocked, reservePerimeter)\n\tlocal inset = if reservePerimeter then 11.5 else WALL_INSET", "local function safeRect(rect, room, blocked)\n\tlocal inset = WALL_INSET"),
    ("Plan literal false caller", "safeRect(withPartition,room,blocked,false)", "safeRect(withPartition,room,blocked)"),
    ("fallback literal false caller", "safeRect(rect,room,blocked,false)", "safeRect(rect,room,blocked)"),
    ("breaker unused immutable position", 'local localPosition=if kind=="breaker" then V(.98,6.70,.42)', 'local localPosition=if kind=="breaker" then V(.98,2.15,.42)'),
    ("breaker immediate override", '\t\tif kind=="breaker" then localPosition=V(.98,2.15,.42) end\n', ""),
]
LATCH_OLD = "boxesDone = 0, boxCount = boxCount, latchMode = true,"
LATCH_NEW = "boxesDone = 0, boxCount = boxCount,"


def session_literal(body):
    marker = "\tsession = {\n\t\tactive = true, stage = \"fuses\""
    start = body.index(marker)
    end = body.index("\n\t}", start) + len("\n\t}")
    return body[start:end]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--luau", required=True)
    parser.add_argument("--compiler", required=True)
    parser.add_argument("--verify-installed", action="store_true", help="Rerun immutable proposal contracts against exact installed candidate; save separate receipt")
    args = parser.parse_args()
    manifest_path = ROOT / "studio-sync-manifest.json"
    manifest_raw = manifest_path.read_bytes()
    entries = {item["file"]: item for item in json.loads(manifest_raw)["items"]}
    captured = {name: (ROOT / name).read_bytes() for name in (DRESS, PUZZLE)}
    current = {name: raw.replace(b"\r\n", b"\n").decode() for name, raw in captured.items()}
    before = dict(current)
    output = Path(__file__).with_name("additional-locals")
    output.mkdir(exist_ok=True)
    preserved, saved_candidate = {}, {}
    if args.verify_installed:
        proposal_path = output / "candidate-manifest.json"
        preserved[proposal_path] = proposal_path.read_bytes()
        proposal = json.loads(preserved[proposal_path])
        assert proposal["passed"] is True
        saved = {item["file"]: item for item in proposal["files"]}
        assert set(saved) == {DRESS, PUZZLE}
        for name, item in saved.items():
            before_path, candidate_path = ROOT / item["beforeFile"], ROOT / item["candidateFile"]
            preserved[before_path], preserved[candidate_path] = before_path.read_bytes(), candidate_path.read_bytes()
            before[name], saved_candidate[name] = preserved[before_path].decode(), preserved[candidate_path].decode()
            assert SHA(before[name].encode()) == item["beforeSHA256Lf"]
            assert SHA(saved_candidate[name].encode()) == item["candidateSHA256Lf"]
            assert current[name] == saved_candidate[name], "Installed source is not exact saved candidate"
            for key in ("studioPath", "className", "properties", "attributes"):
                assert entries[name].get(key) == item.get(key), f"Installed metadata drift: {key}"
    for name, body in current.items():
        assert entries[name]["status"] == "synced" and entries[name]["sourceEditorMatches"] is True
        assert SHA(body.encode()) == entries[name]["sha256"], "Fresh mirror/manifest mismatch"
    assert len(re.findall(r"\bsafeRect\b", before[DRESS])) == 3
    assert len(re.findall(r"\breservePerimeter\b", before[DRESS])) == 2
    assert before[DRESS].count('local V = Vector3.new') == 1
    assert len(re.findall(r"\blatchMode\b", before[PUZZLE])) == 1
    assert not re.search(r"session\[|pairs\(session\)|table\.(clone|freeze)\(session", before[PUZZLE]), "Session acquired reflection/indirect access"
    after = dict(before)
    for label, old, new in EDITS:
        assert after[DRESS].count(old) == 1, label
        after[DRESS] = after[DRESS].replace(old, new, 1)
    assert before[PUZZLE].count(LATCH_OLD) == 1
    after[PUZZLE] = before[PUZZLE].replace(LATCH_OLD, LATCH_NEW, 1)
    if args.verify_installed:
        assert after == saved_candidate, "Proposal no longer matches exact scoped substitutions"
    helper_spec = importlib.util.spec_from_file_location("helper_proposals", Path(__file__).with_name("verify_local_helpers.py"))
    helper = importlib.util.module_from_spec(helper_spec)
    helper_spec.loader.exec_module(helper)
    team_spec = importlib.util.spec_from_file_location("existing_team_port", ROOT / "tools/tests/test_level1_team_prompts.py")
    team = importlib.util.module_from_spec(team_spec)
    team_spec.loader.exec_module(team)
    assert team.PUZZLE == current[PUZZLE], "Existing fixture read changed source"
    host = Path(__file__).with_name("local-helpers-host.luau").read_text(encoding="utf-8")
    host += Path(__file__).with_name("additional-locals-host.luau").read_text(encoding="utf-8")
    def loader(name, source):
        return f'''local function {name}(e)
local game,workspace,task,Instance,os=e.game,e.workspace,e.task,e.Instance,e.os
{source}
end
'''
    def team_port(puzzle):
        server = (team.SERVER.replace("__ANNOUNCE__", team.ANNOUNCE)
            .replace("__TEAM_DELIVERY__", team.section(team.TEAM, "function TeamObjectives.Announce(", "\nreturn TeamObjectives"))
            .replace("__FUSE__", team.FUSE_HANDLER).replace("__BOX__", team.BOX_HANDLER).replace("__LEVER__", team.LEVER_HANDLER))
        # Execute the actual production session literal; preserve fixture roster.
        start = server.index("    session = {", server.index("local function freshSession()"))
        end = server.index("\n    }", start) + len("\n    }")
        actual = "local folder={}\nlocal boxCount=3\nlocal roundPlayerSet={[mikkel]=true,[mate]=true}\n" + session_literal(puzzle)
        return server[:start] + actual + server[end:]
    receipt = {"finding": "LE-34", "status": "installed exact candidates verified; native receipts owned by root" if args.verify_installed else "proposal only; root native baseline/CAS review required",
        "productionWrites": 0, "studioCalls": 0, "testBoundary": "offline actual-source authoring/prompt contracts; no native assets/pathfinding/clients/teleport claim", "files": [], "tests": []}
    with tempfile.TemporaryDirectory(prefix="additional-locals-") as directory:
        probe = Path(directory) / "gate.luau"
        for name, key in ((DRESS, "RoomDressing"), (PUZZLE, "PuzzleManager")):
            compile_gates = []
            for label, body in (("before", before[name]), ("candidate", after[name])):
                for optimization in (0, 1):
                    probe.write_text(body, encoding="utf-8", newline="\n")
                    compiled = subprocess.run([args.compiler, "--binary", "-g0", f"-O{optimization}", str(probe)], capture_output=True, timeout=30)
                    assert compiled.returncode == 0, compiled.stderr.decode(errors="replace")
                    compile_gates.append({"version": label, "optimization": optimization, "success": True, "bytecodeSHA256": SHA(compiled.stdout), "bytecodeBytes": len(compiled.stdout)})
            old_path, new_path = output / f"{key}.before.luau", output / f"{key}.candidate.luau"
            if not args.verify_installed:
                old_path.write_text(before[name], encoding="utf-8", newline="\n")
                new_path.write_text(after[name], encoding="utf-8", newline="\n")
            entry = entries[name]
            receipt["files"].append({"file": name, "studioPath": entry["studioPath"], "className": entry["className"],
                "properties": entry.get("properties"), "attributes": entry.get("attributes"),
                "beforeSHA256Lf": SHA(before[name].encode()), "candidateSHA256Lf": SHA(after[name].encode()),
                "beforeBytesLf": len(before[name].encode()), "candidateBytesLf": len(after[name].encode()),
                "beforeFile": old_path.relative_to(ROOT).as_posix(), "candidateFile": new_path.relative_to(ROOT).as_posix(), "compile": compile_gates,
                "diff": "".join(difflib.unified_diff(before[name].splitlines(keepends=True), after[name].splitlines(keepends=True), fromfile=name, tofile=name, n=2))})
        gate_source = host + loader("before", before[DRESS]) + loader("candidate", after[DRESS]) + '''
check(stable(planFixture(before))==stable(planFixture(candidate)),"same seeded wall/portal/envelope authoring decisions")
for _,scenario in ipairs({{false,false,false},{true,false,false},{false,true,false},{false,false,true}}) do
    check(stable(dressingFixture(before,table.unpack(scenario)))==stable(dressingFixture(candidate,table.unpack(scenario))),"same complete RoomDressing graph/reports/interactions/errors/cleanup")
end
print("AUTHORING PASS assertions="..checks)
'''
        gate = helper.run_luau(args.luau, gate_source, probe)
        assert gate.returncode == 0, gate.stdout + gate.stderr
        receipt["tests"].append({"name": "same actual complete RoomDressing Plan/Apply", "passed": True, "assertions": int(re.search(r"assertions=(\d+)", gate.stdout).group(1)), "output": gate.stdout.strip()})
        team_results = []
        for label, body in (("before", before[PUZZLE]), ("candidate", after[PUZZLE])):
            result = helper.run_luau(args.luau, team_port(body), probe)
            assert result.returncode == 0, result.stdout + result.stderr
            team_results.append(result.stdout)
        assert team_results[0] == team_results[1], "Session literal altered prompt contract output"
        receipt["tests"].append({"name": "actual production session initializer + existing actual three prompt handlers", "passed": True, "identicalBeforeAfter": True, "output": team_results[0].strip()})
        controls = (("wall inset changes active placement", host + loader("mutant", after[DRESS].replace("local inset = WALL_INSET", "local inset = 12", 1)) + "\nplanFixture(mutant)", "authoring seed0 chooses positive corner"),
            ("breaker latch positioned at discarded height", host + loader("mutant", after[DRESS].replace('local localPosition=if kind=="breaker" then V(.98,2.15,.42)', 'local localPosition=if kind=="breaker" then V(.98,6.70,.42)', 1)) + "\ndressingFixture(mutant,false,false,false)", "breaker latch prompt uses mounted +2.15 position"),
            ("session active initializer removed", team_port(after[PUZZLE]).replace('active = true, stage = "fuses"', 'active = false, stage = "fuses"', 1), "one team event per in-round player"))
        for label, body, reason in controls:
            result = helper.run_luau(args.luau, body, probe)
            assert result.returncode != 0 and reason in result.stderr, result.stdout + result.stderr
            receipt["tests"].append({"name": label, "negativeControlRejected": True, "expectedFailure": reason})
    assert all((ROOT / name).read_bytes() == raw for name, raw in captured.items()), "Canonical source changed; reconcile"
    assert manifest_path.read_bytes() == manifest_raw, "Manifest changed; reconcile"
    assert all(path.read_bytes() == value for path, value in preserved.items()), "Immutable proposal evidence changed"
    receipt["passed"] = True
    receipt["currentManifestSHA256"] = SHA(manifest_raw)
    if args.verify_installed:
        receipt["immutableProposalEvidenceUnchanged"] = True
        receipt["immutableProposalEvidenceSHA256"] = {path.relative_to(ROOT).as_posix(): SHA(value) for path, value in preserved.items()}
    path = output / ("installed-contract-check.json" if args.verify_installed else "candidate-manifest.json")
    path.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("PASS", json.dumps(receipt["tests"][:2], ensure_ascii=False))
    print("8 full-source O0/O1 compile gates;3 independent negative controls rejected; canonical files/manifest/Studio unchanged.")
    print(path.relative_to(ROOT).as_posix())


if __name__ == "__main__":
    main()
