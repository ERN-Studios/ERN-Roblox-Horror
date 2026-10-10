"""Prepare/replay one LE34 private unread field; root alone executes native probe.

Default prepares immutable new artifacts plus meaningful actual-source offline
contracts. --execute runs only the prepared unparented native contract modules.
Never installs production Source, changes mode, invokes live modules or borrows
runtime state. Current originals are guarded during and after both outcomes.
"""
from pathlib import Path
import argparse
import ast
import hashlib
import importlib.util
import json
import re
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / "artifacts/cleanup-20261009/pending-locals-native-v1"
PUZZLE = "ServerScriptService/Level 1 Systems/PuzzleManager.Script.lua"
TEAM = "ServerScriptService/TeamObjectives.ModuleScript.lua"
LUAU = Path("C:/Users/mikke/AppData/Local/Temp/codex-luau-0.737/luau.exe")
COMPILER = LUAU.with_name("luau-compile.exe")
sha = lambda raw: hashlib.sha256(raw).hexdigest()
lf = lambda raw: raw.replace(b"\r\n", b"\n")


def save(path, raw):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("xb") as stream:
        assert stream.write(raw) == len(raw)
    assert path.read_bytes() == raw


def encoded(value):
    return (json.dumps(value, indent=2, ensure_ascii=False) + "\n").encode()


def lua_literal(text):
    level = "="
    while "]" + level + "]" in text:
        level += "="
    # Prevent Lua's initial-newline removal by stripping a known prefix instead.
    return "string.sub([" + level + "[_" + text + "]" + level + "],2)"


LIFECYCLE = r'''
local surfaceLightCache={old=true}
__CLEAR__
local disconnected,destroyed=0,0
freshSession()
local saved=session
session.conns={
 {Disconnect=function() disconnected+=1;error("controlled disconnect failure") end},
 {Disconnect=function() disconnected+=1 end},
}
session.folder={Destroy=function() destroyed+=1 end}
workspaceAttributes.Level1RelaysExtracted=3
workspaceAttributes.Level1ActiveCircuitCount=3
workspaceAttributes.EntityObjectiveTarget="old"
workspaceAttributes.EntityObjectiveStage="fuses"
count,claimed=1,false
model={Parent=true,Destroy=function(self)self.Parent=nil end}
prompt={Enabled=true}
clearPuzzle()
expect(saved.active,false,"clearPuzzle deactivates old private session")
expect(session,nil,"clearPuzzle clears private session")
expect(disconnected,2,"disconnect fault does not skip later connection cleanup")
expect(destroyed,1,"clearPuzzle destroys its controlled folder once")
expect(surfaceLightCache,nil,"clearPuzzle clears rebuilt light cache")
expect(workspaceAttributes.Level1RelaysExtracted,nil,"cleanup clears relays counter")
expect(workspaceAttributes.Level1ActiveCircuitCount,nil,"cleanup clears active circuits")
expect(workspaceAttributes.EntityObjectiveTarget,nil,"cleanup clears objective target")
expect(workspaceAttributes.EntityObjectiveStage,nil,"cleanup clears objective stage")
expect(workspaceAttributes.LightMode,"NORMAL","cleanup restores light mode")
expect(workspaceAttributes.FlickerBoost,0,"cleanup clears flicker boost")
expect(workspaceAttributes.EntitySpeedMul,1,"cleanup restores entity speed")
local beforeLate=#eventTrace
fuseHandler(mikkel)
expect(#eventTrace,beforeLate,"old fuse callback after cleanup cannot emit")
expect(saved.carried[mikkel],nil,"old callback cannot mutate former inventory")
clearPuzzle()
expect(disconnected,2,"empty-session cleanup does not disconnect twice")
expect(destroyed,1,"empty-session cleanup does not destroy twice")
freshSession()
expect(session.active,true,"fresh reentry session is active")
expect(session.boxesDone,0,"fresh reentry starts at zero boxes")
count,claimed=1,false
model={Parent=true,Destroy=function(self)self.Parent=nil end}
prompt={Enabled=true}
fuseHandler(mikkel)
expect(#teamEvents(),2,"reentry retains both in-round recipients")
local afterPickup=#eventTrace
fuseHandler(mikkel)
expect(#eventTrace,afterPickup,"duplicate fuse claim cannot emit twice")
expect(session.carried[mikkel],1,"duplicate fuse claim cannot increase inventory")
local failedSession=session
session.conns={}
session.folder={Destroy=function()error("controlled owned folder failure")end}
local failed=pcall(clearPuzzle)
expect(failed,false,"actual folder failure remains observable")
expect(session,failedSession,"actual folder error retains session for retry")
expect(failedSession.active,false,"folder error still deactivates session")
session.folder={Destroy=function()destroyed+=1 end}
clearPuzzle()
expect(session,nil,"cleanup retry clears failed session")
expect(destroyed,2,"cleanup retry destroys only its current controlled folder")
return {checks=checks,eventTrace=eventTrace,finalWorkspace=workspaceAttributes,
 disconnected=disconnected,destroyed=destroyed,sessionCleared=session==nil}
'''


def build_contract(team_module, puzzle):
    # Keep the existing production handler extraction and its 21 actual checks.
    server = (team_module.SERVER.replace("__ANNOUNCE__", team_module.ANNOUNCE)
              .replace("__TEAM_DELIVERY__", team_module.section(team_module.TEAM, "function TeamObjectives.Announce(", "\nreturn TeamObjectives"))
              .replace("__FUSE__", team_module.FUSE_HANDLER)
              .replace("__BOX__", team_module.BOX_HANDLER)
              .replace("__LEVER__", team_module.LEVER_HANDLER))
    start = server.index("    session = {", server.index("local function freshSession()"))
    end = server.index("\n    }", start) + len("\n    }")
    marker = '\tsession = {\n\t\tactive = true, stage = "fuses"'
    begin = puzzle.index(marker)
    finish = puzzle.index("\n\t}", begin) + len("\n\t}")
    initializer = 'local folder={}\nlocal boxCount=3\nlocal roundPlayerSet={[mikkel]=true,[mate]=true}\n' + puzzle[begin:finish]
    server = server[:start] + initializer + server[end:]
    server = server.replace("local sent = {}", "local sent = {}\nlocal eventTrace = {}", 1)
    old = "function status:FireClient(target, ...) table.insert(sent, {target = target, args = {...}}) end"
    new = "function status:FireClient(target, ...) table.insert(sent, {target = target, args = {...}});eventTrace[#eventTrace+1]={target=target.Name,args={...}} end"
    assert server.count(old) == 1
    server = server.replace(old, new, 1)
    old = "function status:FireAllClients(...) table.insert(sent, {target = 'all', args = {...}}) end"
    new = "function status:FireAllClients(...) table.insert(sent, {target = 'all', args = {...}});eventTrace[#eventTrace+1]={target='all',args={...}} end"
    assert server.count(old) == 1
    server = server.replace(old, new, 1)
    assert server.count("print(('server ok (%d checks)'):format(checks))") == 1
    server = server.replace("print(('server ok (%d checks)'):format(checks))", "", 1)
    cleanup = team_module.section(puzzle, "local function clearPuzzle()", "\nlocal function startPuzzle()")
    return 'return function()\nlocal os={clock=function()return 100 end}\n' + server + LIFECYCLE.replace("__CLEAR__", cleanup) + "\nend\n"


def prepare():
    destination = ART / "latch-only"
    assert not destination.exists(), "Immutable proposal already exists"
    manifest_raw = (ROOT / "studio-sync-manifest.json").read_bytes()
    mirror_raw = (ROOT / PUZZLE).read_bytes()
    team_raw = (ROOT / TEAM).read_bytes()
    proposal_raw = (ROOT / "artifacts/cleanup-20261009/additional-locals/candidate-manifest.json").read_bytes()
    proposal = json.loads(proposal_raw)
    item = next(row for row in proposal["files"] if row["file"] == PUZZLE)
    before_raw = (ROOT / item["beforeFile"]).read_bytes()
    candidate_raw = (ROOT / item["candidateFile"]).read_bytes()
    assert sha(before_raw) == item["beforeSHA256Lf"] and sha(candidate_raw) == item["candidateSHA256Lf"]
    assert lf(mirror_raw) == before_raw
    old = b"boxesDone = 0, boxCount = boxCount, latchMode = true,"
    new = b"boxesDone = 0, boxCount = boxCount,"
    assert before_raw.count(old) == 1 and before_raw.replace(old, new, 1) == candidate_raw
    assert len(re.findall(rb"\blatchMode\b", before_raw)) == 1
    assert not re.search(rb"(?:session|owningSession)\[|(?:pairs|next|rawget|setmetatable)\((?:session|owningSession)[,)]", before_raw)
    native = json.loads((ART / "observation.json").read_bytes())
    puzzle_native = next(row for row in native["rows"] if row["studioPath"] == item["studioPath"])
    team_native = json.loads((ART / "team-observation.json").read_bytes())
    assert sha(before_raw) == puzzle_native["sourceSHA256"] and puzzle_native["sourceEditorMatches"]
    assert lf(team_raw).decode() == team_native["source"] and sha(lf(team_raw)) == team_native["sourceSHA256"]
    spec = importlib.util.spec_from_file_location("team_fixture", ROOT / "tools/tests/test_level1_team_prompts.py")
    team_module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(team_module)
    assert team_module.PUZZLE.encode() == before_raw and team_module.TEAM.encode() == lf(team_raw)
    payloads = {"before": build_contract(team_module, before_raw.decode()), "candidate": build_contract(team_module, candidate_raw.decode())}
    needle = 'active = true, stage = "fuses"'
    assert payloads["candidate"].count(needle) == 1
    payloads["inactiveNegative"] = payloads["candidate"].replace(needle, 'active = false, stage = "fuses"', 1)
    compile_checks = []
    with tempfile.TemporaryDirectory(prefix="mongotv-latch-local-contract-") as directory:
        temp = Path(directory)
        for name, body in {"fullBefore": before_raw.decode(), "fullCandidate": candidate_raw.decode(), **payloads}.items():
            probe = temp / (name + ".luau")
            probe.write_bytes(body.encode())
            for optimization in ("-O0", "-O1"):
                run = subprocess.run([str(COMPILER), "--binary", optimization, str(probe)], capture_output=True, timeout=15)
                assert run.returncode == 0, run.stderr.decode(errors="replace")
                compile_checks.append({"input": name, "optimization": optimization, "sourceSHA256": sha(body.encode()), "pass": True})
        stable = '''local function stable(v) if type(v)~="table" then return tostring(v) end local keys={} for k in v do keys[#keys+1]=k end table.sort(keys,function(a,b)return tostring(a)<tostring(b)end) local out={} for _,k in keys do out[#out+1]=tostring(k)..":"..stable(v[k]) end return "{"..table.concat(out,",").."}" end\n'''
        loaders = "\n".join(f"local {name}=(function()\n{body}\nend)()" for name, body in payloads.items())
        gate = stable + loaders + '\nlocal a,b=before(),candidate()\nassert(stable(a)==stable(b),"actual output drift")\nassert(stable(before())==stable(a) and stable(candidate())==stable(b),"reentry drift")\nlocal ok,err=pcall(inactiveNegative)\nassert(not ok and tostring(err):find("one team event per in-round player",1,true),"inactive semantic mutant accepted")\nprint("CONTRACT_CHECKS="..a.checks)\n'
        path = temp / "paired.luau"
        path.write_bytes(gate.encode())
        result = subprocess.run([str(LUAU), str(path)], capture_output=True, text=True, timeout=15)
        assert result.returncode == 0, result.stdout + result.stderr
        checks = int(re.search(r"CONTRACT_CHECKS=(\d+)", result.stdout)[1])
    manifest = json.loads(manifest_raw)
    originals = []
    for row in (puzzle_native, team_native):
        originals.append({key: row[key] for key in ("studioPath", "instanceId", "parentId", "className", "properties", "attributes", "tags", "sourceSHA256")})
    originals[0]["segments"] = puzzle_native["segments"]
    originals[1]["segments"] = ["ServerScriptService", "TeamObjectives"]
    expected = {"nativeScriptCount": manifest["counts"]["scripts"], "contractChecks": checks, "originals": originals}
    template = Path(__file__).with_name("latch_mode_probe.luau").read_text(encoding="utf8")
    codes = {}
    for mode in ("before", "installed"):
        values = json.loads(json.dumps(expected))
        if mode == "installed": values["originals"][0]["sourceSHA256"] = item["candidateSHA256Lf"]
        code = template.replace("__EXPECTED__", lua_literal(json.dumps(values, ensure_ascii=False)))
        code = code.replace("__PAYLOADS__", lua_literal(json.dumps(payloads, ensure_ascii=False))).replace("__INSTALLED__", str(mode == "installed").lower())
        assert not re.search(r"__EXPECTED__|__PAYLOADS__|__INSTALLED__", code)
        with tempfile.TemporaryDirectory(prefix="mongotv-latch-native-compile-") as directory:
            path = Path(directory) / "native.luau";path.write_bytes(code.encode())
            for optimization in ("-O0", "-O1"):
                run = subprocess.run([str(COMPILER), "--binary", optimization, str(path)], capture_output=True, timeout=15)
                assert run.returncode == 0, run.stderr.decode(errors="replace")
                compile_checks.append({"input": "native-" + mode, "optimization": optimization, "sourceSHA256": sha(code.encode()), "pass": True})
        codes[mode] = code
    assert (ROOT / PUZZLE).read_bytes() == mirror_raw and (ROOT / TEAM).read_bytes() == team_raw
    assert (ROOT / "studio-sync-manifest.json").read_bytes() == manifest_raw
    assert (ROOT / "artifacts/cleanup-20261009/additional-locals/candidate-manifest.json").read_bytes() == proposal_raw
    for name, body in payloads.items(): save(destination / (name + ".module.luau"), body.encode())
    for name, code in codes.items(): save(destination / ("native-" + name + ".luau"), code.encode())
    proof = {"schema": "mongotv-latch-only-proposal-v1", "pass": True, "scope": "LE34 ONLY private latchMode initializer field; no RoomDressing/Usher edits", "file": PUZZLE,
             "beforeFile": item["beforeFile"], "candidateFile": item["candidateFile"], "beforeSHA256": item["beforeSHA256Lf"], "candidateSHA256": item["candidateSHA256Lf"],
             "bytesRemoved": len(before_raw)-len(candidate_raw), "checksPerVersion": checks, "pairedChecks": 2*checks, "reentryChecks": 2*checks, "semanticNegativeRejected": True,
             "compileChecks": compile_checks, "originals": expected["originals"], "nativeScriptCount": expected["nativeScriptCount"], "manifestAtPrepareSHA256": sha(manifest_raw),
             "payloadHashes": {name: sha(body.encode()) for name, body in payloads.items()}, "nativeCodeHashes": {name: sha(code.encode()) for name, code in codes.items()},
             "nativeCalls": 0, "productionWrites": 0, "manifestWrites": 0, "immutableOldProposalPreserved": True,
             "status": "offline ready; root reviews then executes native-before. No installation or native port pass yet.",
             "limits": "Actual initializer/three handlers/announce/clearPuzzle; engine/players/remotes/analytics/world/clock are local boundaries. Native full-round/multiplayer/streaming/respawn/teleport/performance remain untested."}
    save(destination / "proposal.json", encoded(proof))
    print(json.dumps({key: proof[key] for key in ("pass", "bytesRemoved", "checksPerVersion", "pairedChecks", "reentryChecks", "nativeCalls", "status")}))


def execute(mode, receipt):
    # Parent review/authorization is required before this branch is called.
    assert receipt is not None and not receipt.exists(), "Require a fresh immutable receipt"
    proposal = json.loads((ART / "latch-only/proposal.json").read_bytes())
    path = ART / "latch-only" / ("native-" + mode + ".luau")
    code = path.read_bytes()
    assert sha(code) == proposal["nativeCodeHashes"][mode]
    current = lf((ROOT / PUZZLE).read_bytes())
    expected = proposal["beforeSHA256"] if mode == "before" else proposal["candidateSHA256"]
    assert sha(current) == expected, "Current mirror differs from the selected immutable Source scope"
    sys.path.insert(0, str(ROOT / "tools"))
    from sync_from_studio import StudioMcpClient, find_mcp_batch, select_studio, RELEASE_STUDIO_NAME
    client = StudioMcpClient(find_mcp_batch())
    result = None
    error = None
    try:
        client.initialize()
        studio = select_studio(client, RELEASE_STUDIO_NAME, 15)
        assert studio["id"] == "1b603e69-7ae1-4572-b210-d5bf05c684ff"
        state = client.call("get_studio_state", {"studio_id": studio["id"]})
        assert "Current Studio Mode: Edit" in state, "Preserve the owner's current mode"
        result = json.loads(client.call("execute_luau", {"studio_id": studio["id"], "datamodel_type": "Edit", "code": code.decode()}))
    except BaseException as primary:
        error = primary
    finally:
        try: client.close()
        except BaseException as cleanup:
            if error is None: error = cleanup
            else: error.add_note("MCP cleanup: " + str(cleanup))
        if result is None: result = {"pass": False}
        if error is not None: result.update({"pass": False, "transportError": str(error)})
        result["nativeInputSHA256"] = sha(code)
        save(receipt, encoded(result))
    print(json.dumps({key: result.get(key) for key in ("pass", "contractPassed", "originalsUnchanged", "probesCreated", "probesDestroyed", "remainingProbes", "error", "transportError")}))
    assert error is None and result.get("pass") is True, "Native contract gate failed; keep candidate pending"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--execute", choices=["before", "installed"])
    parser.add_argument("--receipt", type=Path)
    args = parser.parse_args()
    if args.execute: execute(args.execute, args.receipt)
    else: prepare()


if __name__ == "__main__": main()
