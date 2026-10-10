"""Compile/replay actual readonly capture suffix with explicit fake service boundaries."""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SHA = lambda raw: hashlib.sha256(raw).hexdigest()
LUAU = "C:/Users/mikke/AppData/Local/Temp/codex-luau-0.737/luau-compile.exe"
LUNE = "C:/Users/mikke/AppData/Local/Temp/codex-lune-0.10.5/lune.exe"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--receipt", type=Path, required=True)
    args = parser.parse_args(); target = args.receipt.resolve()
    assert target.parent.is_dir() and target.is_relative_to(ROOT / "artifacts/cleanup-20261010") and not target.exists()
    suffix = (HERE / "native-capture.luau").read_bytes()
    config = (HERE / "capture-config.json").read_bytes()
    header = b"local serde=require('@lune/serde')\nlocal results={} local checks=0\nlocal function check(v,m)checks+=1 assert(v,m)end\nlocal function actual(A,PORT_CONFIG,game,shared,buffer,task)\n"
    fixture = header + suffix + b"\nend\nlocal pinned=serde.decode('json',[====[" + config + b"]====])\n" + r'''
local function fakeCase(mode)
 local config=table.clone(pinned) config.privateToken=if mode=="bad-token" then "wrong" else string.rep("b",64)
 local shared={} local A={} local nodes={} local sources={} local sourceBaseline={} local serializations=0 local uploads=0
 local connectionCount,disconnected,failedDisconnect=0,0,false
 local yields,modeChanged=0,false
 local function same(a,b)
  if a==b then return true end if type(a)~=type(b)then return false end
  if type(a)~="table"then return false end
  for k,v in a do if not same(v,b[k])then return false end end
  for k in b do if a[k]==nil then return false end end return true
 end
 local function node(name,class,parent)
  local n={Name=name,ClassName=class,Parent=parent,Archivable=true,children={}}
  function n:GetChildren()return table.clone(self.children)end
  function n:GetDescendants()local out={} local function walk(p)for _,c in p.children do out[#out+1]=c walk(c)end end walk(self)return out end
  function n:GetAttributes()return {}end function n:GetTags()return {}end
  function n:GetFullName()if self.Parent and self.Parent.Name~="game"then return self.Parent:GetFullName().."."..self.Name end return self.Name end
  function n:IsDescendantOf(p)local q=self.Parent while q do if q==p then return true end q=q.Parent end return false end
  if parent then parent.children[#parent.children+1]=n end nodes[#nodes+1]=n return n
 end
 local game=node("game","DataModel",nil) game.PlaceId=131311258779917 game.GameId=10559217407
 function game:GetService(name)for _,n in self.children do if n.Name==name then return n end end error("missing service")end
 local SS=node("ServerStorage","ServerStorage",game) local starter=node("StarterPlayer","StarterPlayer",game)
 local workspace=node("Workspace","Workspace",game)
 for i=1,1100 do node("CensusFiller"..i,"Folder",workspace)end
 local names={"LobbyReimaginedBlenderSource20261001","LobbyReimaginedBlenderSource20261001R2","LobbyReimaginedBlenderSource20261001R3","LobbyReimaginedBlenderSource20261001R3B","Level1BlenderKit"}
 local oldroots={} for _,name in names do oldroots[#oldroots+1]=node(name,"Folder",SS)end
 for _,pin in config.sources do
  local parent=game
  for i,name in pin.segments do
   local found=nil for _,child in parent.children do if child.Name==name then found=child break end end
   if not found then found=node(name,if i==#pin.segments then pin.className else "Folder",parent)end
   parent=found
  end
  parent.ClassName=pin.className
  local source=setmetatable({hash=pin.rawSHA256},{__len=function()return pin.rawBytes end})
  sources[parent]={source=source,properties=pin.properties,parent=parent.Parent,class=pin.className}
  sourceBaseline[parent]=source
 end
 local welds={} local count=if mode=="missing-weld"then 108 elseif mode=="extra-weld"then 110 else 109
 for i=1,count do welds[#welds+1]=node("WeldConstraint","WeldConstraint",if i<=2 then starter else workspace)end
 if mode=="unarchivable"then welds[3].Archivable=false end
 local originalRows={} for _,n in nodes do originalRows[n]={Name=n.Name,ClassName=n.ClassName,Parent=n.Parent,Archivable=n.Archivable}end
 local function connect(s)
  connectionCount+=1 local index=connectionCount
  local c={} function c:Disconnect()
   if mode=="disconnect-fails" and index==1 then failedDisconnect=true error("explicit owned disconnect fault")end
   disconnected+=1
  end s.connections[#s.connections+1]=c
 end
 function A.check(v,m)check(v,m)end
 function A.mode()check(mode~="mode-before" and not modeChanged,"Edit required")end
 function A.watchInventory(s)connect(s)end
 function A.watchNode(s,n,scope,children)connect(s)end
 function A.begin(cfg)
  local s={config=cfg,roots=oldroots,sources=sources,sourceCount=213,connections={},epoch=0,baselineComplete=false,previous=shared[A.ORIGINAL_KEY]}
  shared[A.KEY]=s A.watchInventory(s)
  if mode=="begin-fails"then error("explicit partial begin failure")end
  s.baselineComplete=true return s
 end
 function A.guard(s)
  A.mode()
  check(shared[A.KEY]==s and shared[A.ORIGINAL_KEY]==s.previous and s.epoch==0,"owned scope/epoch guard")
  for n,source in sourceBaseline do check(s.sources[n].source==source,"Source baseline changed")end
 end
 function A.checkpoint(s,label)
  A.mode() check(shared[A.KEY]==s and shared[A.ORIGINAL_KEY]==s.previous and s.epoch==0,"bounded resume owned scope/epoch guard")
 end
 function A.scriptRow(n)return sources[n]end
 A.same=same A.SS=SS A.shaText=function(v)return v.hash end A.sha=function(v)return v.hash end
 A.tags=function(n)return n:GetTags()end
 A.HS={JSONEncode=function(_,v)return serde.encode("json",v)end}
 A.properties=function(class)
  local names=if class=="WeldConstraint"then {"Part0Internal","Part1Internal"}else {"PlaceAvatarRules"}
  local rows={}for _,name in names do rows[#rows+1]={Name=name,Serialized=true,Type={ScriptType="Instance",InstanceType=if class=="WeldConstraint"then "BasePart"else "Instance"}}end return rows
 end
 A.SER={SerializeInstancesAsync=function(_,roots)
  serializations+=1
  if (mode=="serializer-first"and serializations==1)or(mode=="serializer-joint"and serializations==2)or(mode=="serializer-again"and serializations==3)then error("explicit serializer failure")end
  if serializations==2 then
   if mode=="epoch"then shared[A.KEY].epoch=1 end
   if mode=="foreign-lease"then shared[A.KEY]={foreignMarker=true}end
   if mode=="foreign-ledger"then shared[A.ORIGINAL_KEY]={foreignMarker=true}end
   if mode=="source-change"then sources[next(sources)].source={}end
  end
  return {bytes=if #roots==5 then 8050869 else 8050878,hash=if #roots==5 then config.nativeSHA256 else string.rep("c",64),text="explicit-fake-serializer-buffer"}
 end}
 A.upload=function(cfg,kind,text)
  uploads+=1 if mode=="transfer-fails"then error("explicit transfer failure")end
  return {parts=1,bytes=8050878,sha256=string.rep("c",64)}
 end
 A.diagnostics=function(s)return {stateAvailable=s~=nil}end
 local buffers={len=function(v)return v.bytes end,tostring=function(v)return v.text end}
 local tasks={wait=function()
  yields+=1
  if yields==1 then
   if mode=="mode-after-yield"then modeChanged=true end
   if mode=="epoch-after-yield"then shared[A.KEY].epoch=1 end
   if mode=="source-after-yield"then sources[next(sources)].source={}end
   if mode=="foreign-lease-after-yield"then shared[A.KEY]={foreignMarker=true}end
  end
 end}
 local result=serde.decode("json",actual(A,config,game,shared,buffers,tasks))
 check(result.passed==(mode=="success"),"Only exact success passes")
 check(result.originalWrites==0 and result.instancesCreated==0 and result.modeSwitches==0 and not result.deletionApproved and not result.referenceAbsenceCertified,"No broad certificate or native mutations")
 for n,row in originalRows do check(n.Name==row.Name and n.ClassName==row.ClassName and n.Parent==row.Parent and n.Archivable==row.Archivable,"Every original fake identity/property unchanged")end
 check(disconnected+(if failedDisconnect then 1 else 0)==connectionCount,"Every owned connection attempted")
 if mode=="disconnect-fails"then check(result.connectionsRetained==1 and shared[A.KEY]~=nil and shared[A.ORIGINAL_KEY]~=nil,"Failed owned connection/state remains reachable")
 else check(result.connectionsRetained==0,"No retained owned connection")end
 if mode=="foreign-lease"or mode=="foreign-lease-after-yield"then check(shared[A.KEY].foreignMarker==true,"Foreign capture namespace preserved")end
 if mode=="foreign-ledger"then check(shared[A.ORIGINAL_KEY].foreignMarker==true,"Foreign ledger preserved")end
 if mode~="foreign-lease"and mode~="foreign-lease-after-yield"and mode~="foreign-ledger"and mode~="disconnect-fails"then check(shared[A.KEY]==nil and shared[A.ORIGINAL_KEY]==nil,"Only owned scopes released even partial begin/throw")end
 if string.find(mode,"after-yield",1,true)then check(yields>=1,"Fault crosses actual suffix yield boundary")end
 if mode=="success"then check(yields>=6,"Both witness census and all successful guards use bounded yields")end
 results[#results+1]={mode=mode,passed=true,capturePassed=result.passed,createdFakeConnections=connectionCount,disconnectAttempts=disconnected+(if failedDisconnect then 1 else 0),serializerCalls=serializations,transferCalls=uploads,boundedYields=yields}
end
for _,mode in {"success","bad-token","mode-before","begin-fails","serializer-first","serializer-joint","serializer-again","transfer-fails","epoch","source-change","foreign-lease","foreign-ledger","disconnect-fails","missing-weld","extra-weld","unarchivable","mode-after-yield","epoch-after-yield","source-after-yield","foreign-lease-after-yield"}do fakeCase(mode)end
print(serde.encode("json",{passed=true,cases=#results,checks=checks,results=results}))
'''.encode()
    receipt = {"schema": "retired-authoring-actual-readonly-capture-suffix-offline-v1", "passed": False,
               "nativeCalls": 0, "receiverHTTPStarted": False,
               "inputs": [{"path": (HERE / name).relative_to(ROOT).as_posix(), "bytes": len(raw), "sha256": SHA(raw)} for name, raw in (("native-capture.luau", suffix), ("capture-config.json", config))],
               "fixtureSHA256": SHA(fixture), "limits": "Actual suffix under explicit table/script-row/serializer/common-guard boundaries. Not actual Instance getters, engine events, serialization, Source parity, HTTP or reference absence."}
    try:
        with tempfile.TemporaryDirectory(prefix="mongotv-readonly-suffix-") as directory:
            path = Path(directory) / "suffix.luau"; path.write_bytes(fixture)
            compiled = subprocess.run([LUAU, str(path)], capture_output=True, text=True, timeout=30)
            receipt["compile"] = {"exitCode": compiled.returncode, "stderr": compiled.stderr[:4000]}
            assert compiled.returncode == 0, compiled.stderr
            replay = subprocess.run([LUNE, "run", str(path)], capture_output=True, text=True, timeout=60)
            receipt["exitCode"] = replay.returncode; receipt["stderr"] = replay.stderr[:5000]
            assert replay.returncode == 0, replay.stderr
            receipt["replay"] = json.loads(replay.stdout)
            assert receipt["replay"]["passed"] and receipt["replay"]["cases"] == 20
            receipt["passed"] = True
    except BaseException as error:
        receipt["error"] = str(error); raise
    finally:
        assert (HERE / "native-capture.luau").read_bytes() == suffix and (HERE / "capture-config.json").read_bytes() == config
        with target.open("xb") as stream: stream.write((json.dumps(receipt, indent=2) + "\n").encode())
    print(json.dumps({"passed": True, "cases": receipt["replay"]["cases"], "checks": receipt["replay"]["checks"], "receiptSHA256": SHA(target.read_bytes())}))


if __name__ == "__main__": main()
