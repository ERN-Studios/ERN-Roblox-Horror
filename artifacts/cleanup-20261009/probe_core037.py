"""Bounded CORE-037 counter/suite probe using actual sources offline only.

Host source/OnInvoke are executed against fake engine boundaries, explicitly
not evidence of a real GameManager host or Roblox teleport. No native/state
writes. Proposes only removing RunAll's shared-counter reset; routing API stays.
"""
import argparse
import difflib
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SUITE = "ServerScriptService/Round Completion Test Suite.ModuleScript.lua"
ROUTING = "ServerScriptService/Round Completion Routing.ModuleScript.lua"
MANAGER = "ServerScriptService/GameManager.Script.lua"
SHA = lambda value: hashlib.sha256(value).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--luau", required=True)
    parser.add_argument("--compiler", required=True)
    args = parser.parse_args()
    manifest_path = ROOT / "studio-sync-manifest.json"
    manifest_raw = manifest_path.read_bytes()
    entries = {item["file"]: item for item in json.loads(manifest_raw)["items"]}
    raw = {name: (ROOT / name).read_bytes() for name in (SUITE, ROUTING, MANAGER)}
    source = {name: data.replace(b"\r\n", b"\n").decode() for name, data in raw.items()}
    for name in source:
        assert SHA(source[name].encode()) == entries[name]["sha256"]
        assert entries[name]["sourceEditorMatches"] is True and entries[name]["status"] == "synced"
    reset = "\tRouting.ResetAttemptIds()\n"
    assert source[SUITE].count(reset) == 1
    candidate = source[SUITE].replace(reset, "", 1)
    start = source[MANAGER].index("Routing.LoadedBy = script:GetFullName()")
    stop = source[MANAGER].index("\nlocal zyntraLevelCompleted", start)
    host_setup = source[MANAGER][start:stop]
    host = Path(__file__).with_name("local-helpers-host.luau").read_text(encoding="utf-8")
    # Large literal is observed host source, never executed in full.
    level = "="
    while "]" + level + "]" in source[MANAGER]:
        level += "="
    manager_literal = "[" + level + "[" + source[MANAGER] + "]" + level + "]"
    common = host + '''
local typeof=type
function Methods:SetTeleportData(data) self._props.TeleportData=data end
function Methods:GetTeleportData() return self._props.TeleportData end
local function loadRouting()
''' + source[ROUTING] + '''
end
local function loadSuite(e,Routing)
local game,workspace,Instance=e.game,e.workspace,e.Instance
local script={Parent={WaitForChild=function(_,name) assert(name=="Round Completion Routing"); return Routing end}}
local require=function(module) assert(module==Routing); return module end
__SUITE_BODY__
end
local function scenario()
local e=engine()
local ServerStorage=e.new("Folder","ServerStorage")
local ServerScriptService=e.new("Folder","ServerScriptService")
local manager=e.new("Script","GameManager",ServerScriptService)
manager.Source=__MANAGER_SOURCE__
local Routing=loadRouting()
e.workspace.Attributes={}
function e.workspace:SetAttribute(key,value) self.Attributes[key]=value end
function e.workspace:GetAttribute(key) return self.Attributes[key] end
local oldService=e.game.GetService
e.game.GetService=function(self,name)
    if name=="RunService" then return {IsRunning=function() return true end} end
    if name=="ServerStorage" then return ServerStorage end
    if name=="ServerScriptService" then return ServerScriptService end
    return oldService(self,name)
end
-- Execute only current host's exact routing-probe installation on fake objects.
local script={GetFullName=function() return "ServerScriptService.GameManager" end}
local Instance,workspace=e.Instance,e.workspace
__HOST_SETUP__
local probe=ServerStorage:FindFirstChild(Routing.ProbeName)
probe.ClassName="BindableFunction"
probe.Invoke=function(self) return self.OnInvoke() end
local Suite=loadSuite(e,Routing)
local used={}
for _=1,5000 do used[Routing.NewAttemptId()]=true end
local newAttempt=Routing.NewAttemptId
local repeats,generated=0,0
Routing.NewAttemptId=function()
    local id=newAttempt(); generated+=1
    if used[id] then repeats+=1 end
    used[id]=true; return id
end
local text,failures=Suite.RunAll()
check(failures==5,"baseline known five test/source-shape failures remain visible")
local secondText,secondFailures=Suite.RunAll()
check(secondFailures==5,"second Suite reentry preserves known five failures")
check(text==secondText,"report same on repeated suite runs")
local next=newAttempt()
print("COUNTER generated="..generated.." repeats="..repeats.." next="..next)
print(text)
return repeats,next
end
local repeats,next=scenario()
__EXPECT__
'''
    common = common.replace("__MANAGER_SOURCE__", manager_literal).replace("__HOST_SETUP__", host_setup)
    output = Path(__file__).with_name("core037")
    output.mkdir(exist_ok=True)
    result = {"finding": "CORE-037", "status": "pending native isolated real-TeleportOptions/live-host test; proposal only",
        "scope": "only RunAll automatic ResetAttemptIds call; no runtime Routing/GameManager changes", "productionWrites": 0,
        "studioCalls": 0, "boundary": "offline fake engine host probe; not actual Studio host, TeleportOptions or teleport proof", "tests": []}
    with tempfile.TemporaryDirectory(prefix="core037-") as folder:
        path = Path(folder) / "gate.luau"
        for label, body, expectation in (("before", source[SUITE], 'check(repeats>0 and next<5000,"baseline shared IDs demonstrably rewound")'),
            ("candidate", candidate, 'check(repeats==0 and next>5000,"candidate preserves monotonic IDs on suite reentry")')):
            fixture = common.replace("__SUITE_BODY__", body).replace("__EXPECT__", expectation)
            path.write_text(fixture, encoding="utf-8", newline="\n")
            run = subprocess.run([args.luau, str(path)], capture_output=True, text=True, timeout=30)
            assert run.returncode == 0, run.stdout + run.stderr
            import re
            match = re.search(r"COUNTER generated=(\d+) repeats=(\d+) next=(\d+)", run.stdout)
            total = re.search(r"TOTAL: (\d+) checks, (\d+) failed", run.stdout)
            result["tests"].append({"version": label, "generatedAcrossTwoRuns": int(match[1]), "reusedIDs": int(match[2]), "nextID": int(match[3]), "suiteChecksEachRun": int(total[1]), "suiteFailuresEachRun": int(total[2]), "suiteReportSHA256": SHA(run.stdout[match.end():].encode())})
            (output / f"{label}-offline-suite.txt").write_text(run.stdout, encoding="utf-8", newline="\n")
        assert result["tests"][0]["suiteReportSHA256"] == result["tests"][1]["suiteReportSHA256"], "Suite report changed"
        for body in (source[SUITE], candidate):
            path.write_text(body, encoding="utf-8", newline="\n")
            for optimization in (0, 1):
                compiled = subprocess.run([args.compiler, "--null", f"-O{optimization}", str(path)], capture_output=True, timeout=30)
                assert compiled.returncode == 0, compiled.stderr.decode(errors="replace")
    assert manifest_path.read_bytes() == manifest_raw and all((ROOT / name).read_bytes() == data for name, data in raw.items())
    entry = entries[SUITE]
    result["file"] = SUITE
    for key in ("studioPath", "className", "properties", "attributes"):
        result[key] = entry.get(key)
    result.update({"beforeSHA256Lf": SHA(source[SUITE].encode()), "candidateSHA256Lf": SHA(candidate.encode()),
        "beforeBytesLf": len(source[SUITE].encode()), "candidateBytesLf": len(candidate.encode()), "compileGates": 4,
        "diff": "".join(difflib.unified_diff(source[SUITE].splitlines(keepends=True), candidate.splitlines(keepends=True), fromfile=SUITE, tofile=SUITE, n=2)), "passedOffline": True})
    (output / "Suite.before.luau").write_text(source[SUITE], encoding="utf-8", newline="\n")
    (output / "Suite.candidate.luau").write_text(candidate, encoding="utf-8", newline="\n")
    (output / "offline-counter-suite-probe.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result["tests"], indent=2))
    print("Actual-source offline-only; authoritative runtime/module state unchanged; native gate pending.")


if __name__ == "__main__":
    main()
