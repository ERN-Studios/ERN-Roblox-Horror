"""Fresh Studio-derived four-source patch; dry-run unless --apply is explicit.
Only use --apply after the shared Studio handback. Never uses repository runtime
scripts as a deployment baseline. No native place backup, GitHub push, or publish.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
OUT=Path(__file__).resolve().parent
STUDIO="86f22f6f-aafa-4af2-b2dc-cf471bf0e3a4"
spec=importlib.util.spec_from_file_location("snapshot",ROOT/"artifacts/level1-light-polish-20261002/concurrent-studio/export_readonly.py")
snapshot=importlib.util.module_from_spec(spec);spec.loader.exec_module(snapshot)
patch=json.loads((OUT/"progression-patch.json").read_text(encoding="utf-8"))
snapshot.PATHS=[e["repoFile"].split("/")[:-1]+[e["repoFile"].split("/")[-1].rsplit(".",2)[0]] for e in patch]
snapshot.OUT=OUT/"install-baseline";snapshot.OUT.mkdir(exist_ok=True)
parser=argparse.ArgumentParser();parser.add_argument("--apply",action="store_true");args=parser.parse_args()
snapshot.main() # Read-only fresh, stable Source/editor baseline, including foreign changes.
records=json.loads((snapshot.OUT/"export-manifest.json").read_text(encoding="utf-8"))["sources"]
candidates=OUT/"install-candidates"
for entry,change in zip(records,patch):
    source=(ROOT/entry["artifactFile"]).read_text(encoding="utf-8")
    for edit in change["changes"]:
        assert source.count(edit["old"])==1, "Scoped hunk changed; reconcile Studio: "+entry["studioPath"]
        source=source.replace(edit["old"],edit["new"])
    target=candidates/entry["repoFile"];target.parent.mkdir(parents=True,exist_ok=True);target.write_text(source,encoding="utf-8",newline="\n")
    subprocess.run([str(ROOT/"artifacts/hazmat-20260924/luau-0.737/luau-compile.exe"),"--null",str(target)],check=True)
subprocess.run([sys.executable,str(ROOT/"tools/tests/test_level1_readability.py"),str(candidates/patch[-1]["repoFile"])],check=True)
subprocess.run([sys.executable,str(OUT/"candidates-puzzle/test_progression_counter.py"),str(candidates/patch[2]["repoFile"])],check=True)
subprocess.run([sys.executable,str(OUT/"candidates-renderer/check_steel.py"),str(candidates/patch[1]["repoFile"])],check=True)
if not args.apply:
    print("Dry run only: four fresh Studio-derived candidates compile; no Studio write")
    raise SystemExit(0)
client=snapshot.StudioMcpClient(snapshot.find_mcp_batch());client.initialize();receipt=[]
try:
 for entry,change in zip(records,patch):
    parameters=json.dumps({"segments":entry["segments"],"class":entry["className"],"rawBytes":entry["rawSourceBytes"],"rawHash":entry["rawSourceDjb2"],"changes":change["changes"]},ensure_ascii=False)
    # Decode structured payload through Roblox's JSON reader; no shell interpolation.
    code=r'''
assert(game.PlaceId==131311258779917 and game.GameId==10559217407 and game:GetService("RunService"):IsEdit(),"Wrong place/mode")
local HS=game:GetService("HttpService")
local p=HS:JSONDecode(PAYLOAD)
local target=game
for _,name in p.segments do
 local found
 for _,child in target:GetChildren() do if child.Name==name then assert(not found,"Ambiguous source");found=child end end
 target=assert(found,"Missing source")
end
assert(target.ClassName==p.class,"Changed class")
local function hash(s)local h=5381;for i=1,#s do h=(h*33+string.byte(s,i))%4294967296 end;return h end
local SES=game:GetService("ScriptEditorService")
local baseline=target.Source
assert(#baseline==p.rawBytes and hash(baseline)==p.rawHash and SES:GetEditorSource(target)==baseline,"Source/editor changed; reread")
SES:UpdateSourceAsync(target,function(current)
 assert(current==baseline and target.Source==baseline,"CAS source changed; reread")
 local source=current:gsub("\r\n","\n")
 for _,edit in p.changes do
  local first,last=source:find(edit.old,1,true)
  assert(first and not source:find(edit.old,last+1,true),"Changed or ambiguous scoped hunk")
  source=source:sub(1,first-1)..edit.new..source:sub(last+1)
 end
 return source
end)
return "Scoped Source/editor CAS applied: "..target:GetFullName()
'''.replace("PAYLOAD",json.dumps(parameters,ensure_ascii=False))
    receipt.append(snapshot.execute_luau(client,STUDIO,code))
finally:client.close()
(OUT/"install-receipt.json").write_text(json.dumps(receipt,indent=2),encoding="utf-8")
snapshot.OUT=OUT/"installed-studio";snapshot.OUT.mkdir(exist_ok=True);snapshot.main()
for change in patch:
 actual=(snapshot.OUT/change["repoFile"]).read_bytes()
 expected=(candidates/change["repoFile"]).read_bytes()
 assert actual==expected,"Post-write Source/editor mismatch: "+change["repoFile"]
print("Four scoped Studio edits freshly verified; canonical mirrors have not been modified")
