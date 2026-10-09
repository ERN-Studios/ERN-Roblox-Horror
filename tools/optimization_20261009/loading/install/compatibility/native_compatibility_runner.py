"""Root-run isolated streaming contracts; default invocation only prepares local files.

Reuse the original native runner's staging, exact original/editor preservation,
fresh empty ModuleScript CAS, and success/failure cleanup without changing its
four-probe defaults or receipt. No native backup is taken. --run is the explicit
Studio mutation boundary, reserved for the coordinating root agent.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import sys

HERE = Path(__file__).resolve().parent
TASK = HERE.parents[2]
ROOT = TASK.parents[1]
sys.path.insert(0, str(TASK))
from native_probe_runner import (
    StudioMcpClient, find_mcp_batch, literal, load_inputs, make_code, read_source,
    select_studio, sha, utc,
)

PROBES = (
    ("streaming-lifecycle-contract", "native-contract-probe.luau", 841),
    ("streaming-native-instances", "native-instance-probe.luau", 10),
)


def section(source: str, start: str, end: str) -> str:
    assert source.count(start) == source.count(end) == 1
    return source.split(start, 1)[1].split(end, 1)[0]


def reviewed_inputs():
    # This preserves the existing five inputs and their loading/spectate fixture
    # source pins. The two compatibility sources are additional expected rows.
    sources, budget = load_inputs()
    manifest = json.loads((HERE / "source-install-manifest.json").read_text(encoding="utf-8"))
    assert manifest["placeId"] == 131311258779917 and manifest["universeId"] == 10559217407
    assert len(manifest["scripts"]) == 2
    offline = json.loads((HERE / "offline-result.json").read_text(encoding="utf-8"))
    assert offline["productionExtractedChecks"] == 841 and offline["focusedTransitionChecks"] == 41
    compat_sources = []
    for row in manifest["scripts"]:
        path = (ROOT / row["afterFile"]).resolve()
        assert path.is_relative_to(HERE), "Only the scoped compatibility sources"
        source = read_source(path)
        assert sha(source) == row["afterSha256"] == offline["proposals"][path.name], "Compatibility source/hash changed"
        assert len(source.encode("utf-8")) == row["afterBytes"]
        compat_sources.append({"segments":row["segments"], "class":row["class"], "source":source, "sha256":sha(source)})
    assert len({tuple(row["segments"]) for row in sources+compat_sources}) == 7, "Duplicate installed target"
    l2 = next(row["source"] for row in compat_sources if row["segments"][-1] == "Level 2 Sound Controller")
    l6 = next(row["source"] for row in compat_sources if row["segments"][-1] == "Level 6 Playground Client")
    helpers = (
        "local function stopRandomSession()" + section(l2, "local function stopRandomSession()", "local function classifyAmbientAnchor(instance)"),
        "local function classifyAmbientAnchor(instance)" + section(l2, "local function classifyAmbientAnchor(instance)", "local function randomActive()"),
        "local function forgetFinaleInstance(item)" + section(l6, "local function forgetFinaleInstance(item)", "workspace.DescendantRemoving:Connect(forgetFinaleInstance)"),
        "local function rigOf(child)" + section(l6, "local function rigOf(child)", "-- Kill cam (KILL_CHOKE_20261004"),
    )
    fixtures = {}
    for name, filename, checks in PROBES:
        fixture = read_source(HERE / filename)
        assert fixture.startswith("return function()"), "Fixture must return a run function"
        assert all(helper in fixture for helper in helpers), "Native fixture diverged from installed production helpers"
        fixtures[name] = fixture
    return sources + compat_sources, budget, fixtures


def require_installation(receipt_path: Path, sources):
    installation = json.loads(receipt_path.read_text(encoding="utf-8"))
    assert installation["complete"] is True, "Install expected sources before native probes: " + str(receipt_path)
    installed = {row["path"]:row for row in installation["scripts"]}
    for expected in sources:
        path = ".".join(expected["segments"])
        row = installed[path]
        assert row["afterSha256"] == expected["sha256"] and row["editorMatches"] is True
        assert row["class"] == expected["class"]


def assertion_count(name: str, result) -> int:
    contract = result.get("contract") or {}
    if name == "streaming-lifecycle-contract":
        assert contract.get("result") is True, "Mocked fixture must return true"
        totals = [re.fullmatch(r"STREAMING_LIFECYCLE_CHECKS=(\d+)", line) for line in contract.get("output", [])]
        totals = [match for match in totals if match is not None]
        assert len(totals) == 1, "Expected exactly one captured native lifecycle total"
        return int(totals[0].group(1))
    detail = contract.get("result")
    assert isinstance(detail, dict), "Native Instance fixture must return its result fields"
    assert detail.get("realStreamingGameplayPerformancePass") is False
    return detail["nativeFixtureChecks"]


def verify_read_only(sources, destination: Path):
    """Check installed exact bytes with no ModuleScript or other Studio mutation."""
    code = '''local H=game:GetService("HttpService")
local SES=game:GetService("ScriptEditorService")
assert(not game:GetService("RunService"):IsRunning(),"Edit required")
assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"Unexpected place/universe")
local expected=H:JSONDecode(%s)
local pins={}
for _,row in ipairs(expected) do
 local node=game
 for _,segment in ipairs(row.segments) do
  local match=nil
  for _,child in ipairs(node:GetChildren()) do
   if child.Name==segment then assert(match==nil,"Ambiguous target");match=child end
  end
  assert(match,"Missing target");node=match
 end
 assert(node.ClassName==row.class,"Installed class changed: "..node:GetFullName())
 assert(node.Source==row.source and SES:GetEditorSource(node)==row.source,"Installed Source/editor mismatch: "..node:GetFullName())
 table.insert(pins,{path=node:GetFullName(),class=node.ClassName,instanceId=node:GetDebugId(16),bytes=#node.Source,sourceSha256=row.sha256,editorMatches=true})
end
return H:JSONEncode({verifiedUtc=os.date("!%%Y-%%m-%%dT%%H:%%M:%%SZ"),datamodel="Edit",readOnly=true,complete=true,sources=pins})
''' % literal(sources)
    client = StudioMcpClient(find_mcp_batch())
    try:
        client.initialize()
        studio = select_studio(client, "[UPDATE] BACKROOMS: STAY QUIET", 25)
        sid = studio.get("studio_id") or studio.get("id")
        result = json.loads(client.call("execute_luau", {"studio_id":sid, "datamodel_type":"Edit", "code":code}))
        assert result["complete"] and len(result["sources"]) == 7
        result["studioId"] = sid
        destination.write_text(json.dumps(result, indent=2)+"\n", encoding="utf-8")
        print(f"Read-only exact Source/editor verification passed for seven installed sources at {result['verifiedUtc']}.")
    finally:
        client.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    actions = parser.add_mutually_exclusive_group()
    actions.add_argument("--run", action="store_true", help="Root only: stage and execute both isolated native fixtures in Edit")
    actions.add_argument("--verify-only", action="store_true", help="Read-only installed Source/editor pins; no Studio mutation or native fixture execution")
    parser.add_argument("--emit", type=Path, default=ROOT / "_local/optimization-20261009/native-compatibility-probes")
    parser.add_argument("--receipt", type=Path, default=HERE / "native-probe-receipt.json")
    parser.add_argument("--compatibility-install-receipt", type=Path, default=HERE / "source-install-receipt.json")
    args = parser.parse_args()
    assert args.receipt.resolve() != (TASK / "native-probe-receipt.json").resolve(), "Preserve original four-probe receipt"
    sources, budget, fixtures = reviewed_inputs()
    if args.verify_only:
        verify_read_only(sources, HERE / "read-only-source-pins.json")
        return
    args.emit.mkdir(parents=True, exist_ok=True)
    prepared = []
    for name, filename, checks in PROBES:
        fixture = fixtures[name]
        code, stage = make_code(name, fixture, sources, budget)
        (args.emit / (name+".runner.luau")).write_text(code, encoding="utf-8", newline="\n")
        (args.emit / (name+".module.luau")).write_text(stage, encoding="utf-8", newline="\n")
        prepared.append((name, checks, code, {"fixtureFile":str((HERE / filename).relative_to(ROOT)),
            "fixtureSha256":sha(fixture), "stagedSourceSha256":sha(stage)}))
    if not args.run:
        print(f"Prepared two isolated compatibility probes with seven exact installed-source pins in {args.emit}; no Studio connection or native execution.")
        return
    require_installation(TASK / "source-install-receipt.json", sources[:5])
    require_installation(args.compatibility_install_receipt, sources[5:])
    receipt = {"startedUtc":utc(), "placeId":131311258779917, "universeId":10559217407,
        "backupPolicy":"Owner explicitly instructed no native backup (2026-10-09)",
        "kind":"synthetic-native-contract", "gameplay":False, "performance":False, "multiplayer":False,
        "actualAssetFetches":False, "realReplicationFocusCalls":False, "realStreamingPass":False,
        "expectedSources":[{key:row[key] for key in ("segments","class","sha256")} for row in sources],
        "compatibilityInstallReceipt":str(args.compatibility_install_receipt), "complete":False, "probes":[]}
    def save():
        args.receipt.parent.mkdir(parents=True, exist_ok=True)
        args.receipt.write_text(json.dumps(receipt, indent=2)+"\n", encoding="utf-8")
    client = None
    save()
    try:
        client = StudioMcpClient(find_mcp_batch())
        client.initialize()
        studio = select_studio(client, "[UPDATE] BACKROOMS: STAY QUIET", 25)
        sid = studio.get("studio_id") or studio.get("id")
        receipt["studioId"] = sid
        for name, expected_checks, code, provenance in prepared:
            row = {"probe":name, "startedUtc":utc(), **provenance}
            receipt["probes"].append(row)
            save()
            try:
                result = json.loads(client.call("execute_luau", {"studio_id":sid, "datamodel_type":"Edit", "code":code}))
                row.update(result)
                count = assertion_count(name, result)
                row["assertionChecks"] = count
                assert result["passed"] and result["cleanupPassed"] and result["originalsPreserved"], "Native contract/preservation failed"
                assert count == expected_checks, f"Unexpected native assertions {count}, expected {expected_checks}"
                assert len(result["installed"]) == 7 and all(phase["installedChecked"] == 7 for phase in result["phases"])
                print(f"{name}: {count} synthetic native assertions; all seven sources and original preservation verified", flush=True)
            except Exception as error:
                row["passed"] = False
                row["runnerError"] = f"{type(error).__name__}: {error}"
                raise
            finally:
                row["finishedUtc"] = utc()
                save()
        receipt["complete"] = True
    except Exception as error:
        receipt["error"] = f"{type(error).__name__}: {error}"
        raise
    finally:
        receipt["finishedUtc"] = utc()
        save()
        if client is not None: client.close()


if __name__ == "__main__":
    main()
