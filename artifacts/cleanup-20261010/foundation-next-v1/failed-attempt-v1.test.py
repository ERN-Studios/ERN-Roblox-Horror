"""Actual candidate main() and generated Luau guards on owned fake boundaries."""
from __future__ import annotations
import argparse
from contextlib import redirect_stdout
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools/tests"))
import sync_from_studio as sync
import push_repo_to_studio as push
import studio_source_contract as contract

spec = importlib.util.spec_from_file_location("installer_candidate", OUT / "install_new_scripts.candidate.py")
candidate = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(candidate)

PATH = "ServerScriptService.Fixture"
FILE = "ServerScriptService/Fixture.ModuleScript.lua"
OLD = "-- caf\u00e9\r\nreturn 'old'\r\n"
NEW = "-- \u00e6\u00f8\u00e5 \U0001f600\nreturn 'new'\n"
FOREIGN = "return 'foreign'\n"
CHECKS = 0


def check(condition, why):
    global CHECKS
    CHECKS += 1
    assert condition, why


def sha(raw):
    return hashlib.sha256(raw.encode() if isinstance(raw, str) else raw).hexdigest()


def record(source=OLD, klass="ModuleScript"):
    props = {"Archivable": True, "LinkedSource": ""}
    if klass != "ModuleScript":
        props.update(Enabled=True, Disabled=False, RunContext="Enum.RunContext.Legacy")
    return {"segments": PATH.split("."), "path": PATH, "className": klass,
            "instanceId": "target", "parentId": "parent", "placeId": sync.EXPECTED_PLACE_ID,
            "universeId": sync.EXPECTED_UNIVERSE_ID, "properties": props,
            "attributes": {"Marker": "preserve", "Generation": 17, "Active": False}, "tags": ["a", "z"],
            "sourceEditorMatches": True, "rawSourceSHA256": sha(source), "rawEditorSHA256": sha(source),
            "sourceSHA256": sha(contract.normalize(source)), "canonicalBytes": len(contract.canonical_bytes(source))}


NATIVE = r'''
local checks=0
local function check(value,why)checks+=1;assert(value,why)end
local knownHashes=__HASHES__
local trueType=typeof
local typeof=function(v) if type(v)=="table" and v.__enum then return "EnumItem" end return trueType(v) end
local Enum={HashAlgorithm={Sha256={__enum=true}}}
local context=setmetatable({__enum=true},{__tostring=function()return "Enum.RunContext.Legacy" end})
local function fresh(className,scenario,missing)
 local rows,services={},{}
 local writes,destroys,callbacks=0,0,0
 local methods={}
 local function node(row)
  local object={};rows[object]=row
  return setmetatable(object,{
   __index=function(_,key) if methods[key] then return methods[key] end return row[key] end,
   __newindex=function(_,key,value)
    if key=="Source" then writes+=1 end
    if key=="Parent" then
     local old=row.Parent
     if old then for i,child in rows[old].children do if child==object then table.remove(rows[old].children,i);break end end end
     if value then table.insert(rows[value].children,object) end
    end
    row[key]=value
    if key=="Enabled" then row.Disabled=not value end
   end,
  })
 end
 function methods.GetChildren(self)return table.clone(rows[self].children or {})end
 function methods.GetDebugId(self,depth)assert(depth==16);return rows[self].id end
 function methods.GetFullName(self)
  local names={} while rows[self].Parent do table.insert(names,1,rows[self].Name);self=rows[self].Parent end
  return table.concat(names,".")
 end
 function methods.GetAttributes(self)return table.clone(rows[self].attributes or {})end
 function methods.Destroy(self)destroys+=1;self.Parent=nil end
 local game=node({Name="game",ClassName="DataModel",id="game",children={},PlaceId=131311258779917,GameId=10559217407})
 local parent=node({Name="ServerScriptService",ClassName="ServerScriptService",id="parent",Parent=game,children={}})
 rows[game].children={parent}
 local target=node({Name="Fixture",ClassName=className,id="target",Parent=parent,children={},Source=__OLD__,editor=__OLD__,
  Archivable=true,LinkedSource="",Enabled=true,Disabled=false,RunContext=context,
  attributes={Marker="preserve",Generation=17,Active=false},tags={"z","a"}})
 rows[parent].children=missing and {} or {target}
 local running=false
 local created=nil
 Instance={new=function(klass)
  created=node({Name=klass,ClassName=klass,id="owned",children={},Source="",editor="",Archivable=true,
   LinkedSource="",Enabled=true,Disabled=false,RunContext=context,attributes={},tags={}})
  return created
 end}
 services.HttpService={JSONEncode=function(_,value)return value end,JSONDecode=function(_,value)return value end}
 services.RunService={IsRunning=function()return running end}
 services.EncodingService={ComputeBufferHash=function(_,value,algorithm)
  assert(algorithm==Enum.HashAlgorithm.Sha256)
  return buffer.fromstring(assert(knownHashes[buffer.tostring(value)],"Unexpected SHA boundary input"))
 end}
 services.CollectionService={GetTags=function(_,object)return table.clone(rows[object].tags or {})end}
 services.ScriptEditorService={GetEditorSource=function(_,object)return rows[object].editor end,
  UpdateSourceAsync=function(_,object,callback)
   callbacks+=1
   local row=rows[object]
   if scenario=="update-error" then error("fixture SES error before callback") end
   if scenario=="callback-source" then row.Source=__FOREIGN__;row.editor=__FOREIGN__ end
   if scenario=="editor-conflict" then row.editor=__FOREIGN__ end
   if scenario=="identity" then row.id="foreign-target" end
   if scenario=="parent" then rows[parent].id="foreign-parent" end
   if scenario=="class" then row.ClassName="Folder" end
   if scenario=="property" then row.Archivable=false end
   if scenario=="attribute" then row.attributes.Generation=18 end
   if scenario=="tag" then row.tags={"foreign"} end
   if scenario=="mode" then running=true end
   if scenario=="place" then rows[game].PlaceId+=1 end
   local old=scenario=="callback-old" and __FOREIGN__ or row.editor
   local result=callback(old)
   object.Source=result;row.editor=result
   if scenario=="commit-then-error" then error("fixture committed then SES error") end
  end}
 function methods.GetService(self,name)assert(self==game);return assert(services[name])end
 if scenario=="initial-editor" then rows[target].editor=__FOREIGN__ end
 if scenario=="initial-class" then rows[target].ClassName="Folder" end
 if scenario=="initial-source" then rows[target].Source=__FOREIGN__;rows[target].editor=__FOREIGN__ end
 if scenario=="initial-identity" then rows[target].id="foreign-target" end
 if scenario=="initial-property" then rows[target].Archivable=false end
 if scenario=="initial-attribute" then rows[target].attributes.Generation=18 end
 if scenario=="initial-tag" then rows[target].tags={"foreign"} end
 if scenario=="create-race" then rows[parent].children={target} end
 return game,function()
  return {writes=writes,destroys=destroys,callbacks=callbacks,source=rows[target].Source,editor=rows[target].editor,
    created=created,createdSource=created and rows[created].Source,createdParent=created and rows[created].Parent,
    originalParent=rows[target].Parent,originalChildren=#rows[parent].children,createdEnabled=created and rows[created].Enabled}
 end
end
local updateRunners={__UPDATES__}
local createRunners={__CREATES__}
local cases=0
for _,klass in {"ModuleScript","Script","LocalScript"} do
 local game,state=fresh(klass,"good",false)
 check(updateRunners[klass](game)=="ok","good CAS")
 local result=state();check(result.writes==1 and result.callbacks==1 and result.source==__NEW__,"one scoped source write")
 cases+=1
 for _,scenario in {"callback-source","callback-old","editor-conflict","identity","parent","class","property","attribute","tag","mode","place","update-error",
  "initial-editor","initial-class","initial-source","initial-identity","initial-property","initial-attribute","initial-tag"} do
  local g,state=fresh(klass,scenario,false)
  local ok,err=pcall(updateRunners[klass],g)
  check(not ok,"negative CAS rejects: "..scenario)
  local result=state();check(result.writes==0,"no Source write on failed guard: "..scenario)
  check(result.destroys==0 and result.created==nil,"no original destruction or probe on failed CAS")
  if scenario=="callback-source" or scenario=="initial-source" then check(result.source==__FOREIGN__,"foreign Source preserved")end
  cases+=1
 end
 for _,scenario in {"good","create-race","update-error","commit-then-error","editor-conflict","property","attribute","tag","identity","class","mode","place"} do
  local g,state=fresh(klass,scenario,true)
  local ok,err=pcall(createRunners[klass],g)
  local result=state()
  if scenario=="good" then
   check(ok and result.writes==1 and result.createdSource==__NEW__ and result.createdParent~=nil,"owned create and landing")
   check(klass=="ModuleScript" or result.createdEnabled==true,"restore own default Enabled only after landing")
  else
   check(not ok,"create negative rejects: "..scenario)
   check(result.source==__OLD__ and result.originalParent~=nil,"never edit/destroy raced original")
   if scenario=="update-error" or scenario=="commit-then-error" or scenario=="mode" or scenario=="place" then
    check(result.createdParent==nil,"clean exact owned instance after controlled failure")
   end
   if scenario~="commit-then-error" then check(result.writes==0,"failed creation guard does not write Source")end
  end
  cases+=1
 end
end
print("NATIVE CASES="..cases.." CHECKS="..checks)
'''


def native_fixture():
    hashes = {s: hashlib.sha256(s.encode()).digest() for s in {OLD, NEW, FOREIGN, contract.normalize(OLD), ""}}
    updates = {k: candidate.lua_update(PATH, NEW, record(OLD, k)) for k in ("ModuleScript", "Script", "LocalScript")}
    creates = {k: candidate.lua_create(PATH, NEW, k, "parent") for k in updates}
    program = NATIVE.replace("__HASHES__", candidate.lua_value({k: v.decode("latin1") for k, v in hashes.items()}))
    # Hash service result buffers need arbitrary SHA bytes, not UTF8 encoding.
    program = program.replace(candidate.lua_value({k: v.decode("latin1") for k, v in hashes.items()}),
        "{" + ",".join("[" + push.luau_string(s) + "]=" + '"' + ''.join("\\" + f"{v:03}" for v in h) + '"' for s, h in hashes.items()) + "}")
    program = program.replace("__OLD__", push.luau_string(OLD)).replace("__NEW__", push.luau_string(NEW)).replace("__FOREIGN__", push.luau_string(FOREIGN))
    program = program.replace("__UPDATES__", ",".join("[" + push.luau_string(k) + "]=function(game)\n" + v + "\nend" for k,v in updates.items()))
    program = program.replace("__CREATES__", ",".join("[" + push.luau_string(k) + "]=function(game)\n" + v + "\nend" for k,v in creates.items()))
    return program, updates, creates


class Client:
    def __init__(self, scenario):
        self.scenario=scenario;self.source=OLD;self.closed=False;self.initialized=False
        self.calls=[];self.metadataReads=0;self.updateCalls=0;self.manifest=None
        if scenario in {"same-source", "empty-attributes"}:self.source=NEW
    def initialize(self):self.initialized=True
    def close(self):self.closed=True
    def call(self,tool,arguments=None):
        self.calls.append(tool);arguments=arguments or {}
        if tool=="list_roblox_studios":return json.dumps({"studios":[{"id":"owned-fake","name":f"{candidate.PLACE} (placeId: 131311258779917)"}]})
        if tool=="get_studio_state":return "- Current Studio Mode: Edit\n- Available DataModels: Edit"
        assert tool=="execute_luau"
        code=arguments["code"]
        if code==candidate.lua_lookup(PATH):return json.dumps({"missing":False,"parentId":"parent"})
        if code==sync.native_metadata_code(PATH.split("."),"ModuleScript",sync.EXPECTED_PLACE_ID,sync.EXPECTED_UNIVERSE_ID):
            self.metadataReads+=1;r=record(self.source)
            if self.scenario=="wrong-class":r["className"]="Script"
            if self.scenario=="editor-conflict":r["sourceEditorMatches"]=False
            if self.scenario=="property-read-error":r["properties"].pop("Archivable")
            if self.scenario=="empty-attributes":r["attributes"]=[];r["tags"]=[]
            if self.scenario=="post-property-drift" and self.updateCalls:r["properties"]["Archivable"]=False
            return json.dumps(r)
        names=", ".join(push.luau_string(s) for s in PATH.split("."))
        normal=contract.normalize(self.source)
        if code==push.READ_META_LUAU % names:
            data=normal.encode();return f"{len(data)}\t{push.djb2(data)}\t{normal.count(chr(10))+1}\tModuleScript"
        chunk=re.search(r"local first, count = (\d+), (\d+)",code)
        if chunk:
            first,count=(int(s) for s in chunk.groups())
            assert code==push.READ_CHUNK_LUAU % (names,first,count)
            return "\n".join(normal.split("\n")[first-1:first-1+count])
        assert code==candidate.lua_update(PATH,NEW,record(OLD)),"Unexpected mutation request"
        self.updateCalls+=1
        if self.scenario=="update-error":raise sync.StudioMcpError("fake update error before write")
        if self.scenario=="callback-concurrent":
            self.source=FOREIGN;raise sync.StudioMcpError("actual generated callback test rejects concurrent Source")
        self.source=NEW
        if self.scenario=="manifest-concurrent":
            data=json.loads(self.manifest.read_bytes());data["otherActorMarker"]="preserve";self.manifest.write_text(json.dumps(data),encoding="utf8")
        return "ok"


def main_case(scenario):
    with tempfile.TemporaryDirectory(prefix="mongotv-installer-candidate-main-") as tmp:
        root=Path(tmp);mirror=root/FILE;mirror.parent.mkdir(parents=True);mirror.write_bytes(NEW.encode())
        previous={"studioPath":PATH,"className":"ModuleScript","file":FILE,"sha256":sha(OLD),"bytes":len(OLD.encode()),"status":"synced",
                  "segments":PATH.split("."),"properties":{"Archivable":False,"LinkedSource":"stale"},"attributes":{"Stale":True},"tags":["stale"]}
        if scenario in {"pending","conflict"}:previous.update(status="pending-studio-push" if scenario=="pending" else "studio-push-conflict",studioSha256Before=sha(OLD))
        untouched={"studioPath":"ReplicatedStorage.Other","className":"ModuleScript","file":"ReplicatedStorage/Other.ModuleScript.lua","status":"pending-studio-push","studioSha256Before":"untouched","properties":{"Archivable":False},"attributes":{"ReceiptId":"keep"},"tags":["keep"]}
        manifest=root/"studio-sync-manifest.json";manifest.write_bytes((json.dumps({"items":[previous,untouched],"counts":{"scripts":2,"total":2,"remoteEvents":0}},indent=2)+"\n").encode());before=manifest.read_bytes()
        client=Client(scenario);client.manifest=manifest
        argv=["candidate",FILE]+([] if scenario in {"no-overwrite","same-source","empty-attributes","pending","conflict","dry-run"} else ["--overwrite"])
        if scenario=="dry-run":argv.append("--dry-run")
        error=None
        with patch.object(candidate,"ROOT",root),patch.object(candidate,"StudioMcpClient",lambda _:client),patch.object(candidate,"find_mcp_batch",lambda:root/"NO-MCP"),patch.object(candidate.time,"sleep",lambda _:None),patch.object(sys,"argv",argv),redirect_stdout(io.StringIO()):
            try:exitcode=candidate.main()
            except sync.StudioMcpError as caught:exitcode=1;error=str(caught)
        after=json.loads(manifest.read_bytes());row=next(r for r in after["items"] if r["file"]==FILE)
        check(next(r for r in after["items"] if r["file"]==untouched["file"])==untouched,"other queued row preserved")
        check(mirror.read_bytes()==NEW.encode(),"owned mirror untouched")
        if scenario in {"same-source","overwrite","empty-attributes"}:
            check(exitcode==0 and client.source==NEW,"valid flow succeeds")
            check(row["properties"]==record(NEW)["properties"],"fresh props replace stale row")
            check(row["attributes"]==([] if scenario=="empty-attributes" else record(NEW)["attributes"]),"fresh attrs/empty repr")
            check(row["tags"]==([] if scenario=="empty-attributes" else ["a","z"]),"fresh tags")
            check(row["sourceEditorMatches"] is True and row["segments"]==PATH.split("."),"fresh editor/path facts")
        elif scenario=="manifest-concurrent":
            check(exitcode==1 and after["otherActorMarker"]=="preserve","concurrent manifest retained")
            check(row==previous,"no target registration over concurrent manifest")
        elif scenario=="dry-run":
            check(exitcode==0 and not client.initialized and not client.calls,"dry run no client/network")
            check(manifest.read_bytes()==before,"dry run no manifest write")
        else:
            check(exitcode==1,"negative main flow refused")
            check(manifest.read_bytes()==before,"failed target leaves all manifest bytes unchanged")
            if scenario=="callback-concurrent":check(client.source==FOREIGN,"concurrent Source preserved")
            elif scenario!="post-property-drift":check(client.source==OLD,"no original Source write on refused pre-write flow")
        if scenario in {"pending","conflict"}:check(not client.initialized and not client.calls,"queue refusal before client")
        elif scenario!="dry-run":check(client.initialized and client.closed,"main lifecycle closes on all outcomes")
        return {"case":scenario,"pass":True,"exitCode":exitcode,"updateCalls":client.updateCalls,"metadataReads":client.metadataReads,"error":error}


def run():
    program,updates,creates=native_fixture()
    binaries=Path(tempfile.gettempdir())/"codex-luau-0.737"
    results=[]
    with tempfile.TemporaryDirectory(prefix="mongotv-installer-candidate-native-") as tmp:
        script=Path(tmp)/"guards.luau";script.write_bytes(program.encode())
        for opt in ("-O0","-O1"):
            proc=subprocess.run([str(binaries/"luau-compile.exe"),opt,str(script)],capture_output=True,text=True,encoding="utf8")
            check(proc.returncode==0,"actual generated candidate fixture compiles "+opt+": "+proc.stderr)
            results.append({"opt":opt,"exitCode":proc.returncode})
        proc=subprocess.run([str(binaries/"luau.exe"),str(script)],capture_output=True,text=True,encoding="utf8")
        check(proc.returncode==0,"actual generated candidate guards run: "+proc.stderr)
        native_summary=proc.stdout.strip()
        with (OUT/"candidate-generated-guards.luau").open("x",encoding="utf8",newline="\n") as stream:stream.write(program)
    cases=[main_case(s) for s in ("same-source","overwrite","no-overwrite","empty-attributes","pending","conflict","dry-run","wrong-class","editor-conflict","property-read-error","update-error","callback-concurrent","post-property-drift","manifest-concurrent")]
    return {"schema":"foundation-next-installer-candidate-tests-v1","pass":True,"pythonChecks":CHECKS,"mainCaseCount":len(cases),"cases":cases,"nativeSummary":native_summary,"compiles":results,
            "candidateSHA256":sha((OUT/"install_new_scripts.candidate.py").read_bytes()),"testSHA256":sha(Path(__file__).read_bytes()),"fixtureSHA256":sha(program),
            "generatedUpdateSHA256":{k:sha(v) for k,v in updates.items()},"generatedCreateSHA256":{k:sha(v) for k,v in creates.items()},
            "realMcpCalls":0,"nativeStudioWrites":0,"productionWrites":0,
            "scope":"Actual main against owned temporary mirrors/fake MCP reader protocol; actual generated Lua guards on fake engine services with lookup SHA boundary. Not native authoring, new gameplay, multiprocessing full transaction or Studio engine certification."}


if __name__=="__main__":
    parser=argparse.ArgumentParser();parser.add_argument("--receipt",type=Path,required=True);args=parser.parse_args();result=run()
    with args.receipt.open("x",encoding="utf8",newline="\n") as stream:stream.write(json.dumps(result,indent=2)+"\n")
    print(json.dumps({k:result[k] for k in ("pass","pythonChecks","mainCaseCount","nativeSummary","realMcpCalls","nativeStudioWrites","productionWrites")}))
