"""Prepare a Root-executed readonly baseline request from the actual helpers."""
from pathlib import Path
import hashlib
import json

OUT = Path(__file__).resolve().parent
source_path = OUT / "restoration-probe-v3.luau"
source_raw = source_path.read_bytes()
source = source_raw.decode()
start, end = "local function sha(raw)\n", "local function watch(signal)\n"
assert source.count(start) == source.count(end) == 1
helpers = start + source.split(start, 1)[1].split(end, 1)[0]
header = '''-- Root-only readonly current baseline. No Instances created, no Source/property/Parent/mode writes.
local HS=game:GetService("HttpService")
local ENC=game:GetService("EncodingService")
local SES=game:GetService("ScriptEditorService")
local RS=game:GetService("RunService")
local SS=game:GetService("ServerStorage")
local BASE="http://127.0.0.1:18916"
local ORIGINAL_KEY="__MongoTVStorageCleanup20261009"
local checks=0
local function check(value,message) assert(value,message) checks+=1 end
'''
tail = '''local beforeSources,beforeRoots,connections={},{},{}
local initialCount,epoch=0,0
local expected,baselineRaw,baseline
local state=shared[ORIGINAL_KEY]
local function countKeys(t) local n=0 for _ in t do n+=1 end return n end
local function owned()
 return game.PlaceId==131311258779917 and game.GameId==10559217407 and not RS:IsRunning()
  and shared[ORIGINAL_KEY]==state and state and state.rootRefs and state.scriptRefs
  and not state.probeLease and not state.portLease and state.storagePort==nil
  and countKeys(state.rootRefs)==73 and countKeys(state.scriptRefs)==222
end
local function guard()
 check(owned() and epoch==0,"baseline mode/ledger/epoch changed")
 check(#game:GetDescendants()==initialCount and #SS:GetChildren()==expected.expectedLiveRoots,"baseline live census/roots changed")
 for root,facts in beforeRoots do
  check(root.Parent==SS and canonical({root.Name,root.ClassName,root.Archivable,root:GetAttributes(),tags(root)})==facts,"baseline live root changed")
 end
 local count=0
 for s,row in beforeSources do
  check(s:IsDescendantOf(game) and scriptMatches(s,row),"baseline Source/editor/parent/metadata changed") count+=1
 end
 check(count==213,"baseline source count changed")
end
local function watch(signal) connections[#connections+1]=signal:Connect(function()epoch+=1 end) end
local report={schema="storage-restoration-live-baseline-completion-v1",pass=false,nativeObjectCreations=0,
 sourceWrites=0,propertyWrites=0,originalParentWrites=0,modeSwitches=0,restorationCertified=false}
local ok,why=xpcall(function()
 check(owned() and HS.HttpEnabled,"correct Edit/current original ledger/existing HTTP required")
 expected=HS:JSONDecode(HS:GetAsync(BASE.."/baseline-context",true))
 check(expected.schema=="storage-restoration-live-baseline-context-v1" and expected.expectedLiveSources==213
  and expected.expectedLedgerRootRefs==73 and expected.expectedLedgerScriptRefs==222,"invalid exact baseline context")
 watch(game.DescendantAdded) watch(game.DescendantRemoving) watch(SS.ChildAdded) watch(SS.ChildRemoved)
 for _,root in SS:GetChildren() do
  beforeRoots[root]=canonical({root.Name,root.ClassName,root.Archivable,root:GetAttributes(),tags(root)})
  watch(root.Changed) watch(root.AttributeChanged)
 end
 local census=game:GetDescendants() initialCount=#census
 check(initialCount==expected.expectedLiveDescendants and #SS:GetChildren()==expected.expectedLiveRoots,"fresh census/root baseline mismatch")
 local pins={}
 local unique={}
 for index,s in census do
  if s:IsA("LuaSourceContainer") then
   local row=scriptRow(s)
   check(not unique[row.path],"ambiguous current Source path") unique[row.path]=true
   beforeSources[s]=row watch(s.Changed) watch(s.AttributeChanged)
   pins[#pins+1]={path=row.path,class=row.class,identity=s:GetDebugId(),parentIdentity=row.parent:GetDebugId(),
    sourceSHA256=sha(buffer.fromstring(row.source)),bytes=#row.source,
    metadataSHA256=sha(buffer.fromstring(canonical({properties=row.properties,attributes=row.attributes,tags=row.tags})))}
  end
  if index%1000==0 then task.wait() check(owned() and epoch==0,"baseline changed during census") end
 end
 check(#pins==213,"exact213 current Sources required")
 table.sort(pins,function(a,b)return a.path<b.path end)
 guard()
 baseline={schema="storage-restoration-live-baseline-v1",placeId=game.PlaceId,universeId=game.GameId,mode="Edit",
  expectedLiveSources=213,expectedLiveRoots=#SS:GetChildren(),expectedLiveDescendants=initialCount,
  expectedLedgerRootRefs=73,expectedLedgerScriptRefs=222,sourcePins=pins,capturedAtUtc=DateTime.now():ToIsoDate(),
  sourceWrites=0,propertyWrites=0,originalParentWrites=0,modeSwitches=0}
 baselineRaw=HS:JSONEncode(baseline)
 check(#baselineRaw<=250000,"baseline metadata response bound exceeded")
 check(HS:PostAsync(BASE.."/baseline",baselineRaw,Enum.HttpContentType.ApplicationJson)=="saved","baseline receiver rejected")
 guard()
end,debug.traceback)
for _,connection in connections do
 local released,problem=pcall(function()connection:Disconnect()end)
 if not released then ok=false why=tostring(why).."\\nwatcher release failed: "..tostring(problem) end
end
local final,problem=pcall(function()
 check(expected~=nil and baselineRaw~=nil,"baseline never completed")
 guard()
end)
if not final then ok=false why=tostring(why).."\\nfinal readonly baseline guard: "..tostring(problem) end
report.pass=ok report.error=if ok then nil else tostring(why)
report.originalSourcesUnchanged=final and ok
report.liveSources=if baseline then #baseline.sourcePins else 0
report.liveRoots=#SS:GetChildren() report.liveDescendants=#game:GetDescendants()
report.baselineSHA256=if baselineRaw then sha(buffer.fromstring(baselineRaw)) else nil
report.watchers=#connections report.watchersReleaseAttempted=#connections
report.checks=checks report.capturedAtUtc=DateTime.now():ToIsoDate()
return HS:JSONEncode(report)
'''
request = (header + helpers + tail).encode()
assert source_path.read_bytes() == source_raw
with (OUT / "capture-live-baseline.luau").open("xb") as stream:
    stream.write(request)
receipt = {"schema": "storage-restoration-baseline-preparation-v1", "nativeCalls": 0,
    "sourceCandidateSHA256": hashlib.sha256(source_raw).hexdigest(), "baselineBytes": len(request),
    "baselineSHA256": hashlib.sha256(request).hexdigest(), "candidateExecuted": False,
    "scope": "Actual sha/canonical/scriptRow/scriptMatches helpers extracted unchanged. Future readonly Root request, no Studio call by preparer."}
with (OUT / "baseline-preparation.json").open("xb") as stream:
    stream.write((json.dumps(receipt, indent=2) + "\n").encode())
print(json.dumps(receipt))
