"""Actual parser-port ownership/cleanup code with controlled engine boundaries.

No MCP imports/calls. Parser behavior is injected here; actual native parser
execution remains Root-owned. Full original guards and staging cleanup are real
code from the reviewed template, rather than a repeated implementation.
"""
from pathlib import Path
import argparse
import importlib.util
import json
import re
import subprocess
import sys
import tempfile

sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location("actual_exit_parser_installer",HERE/"apply_exit_literal_cleanup.py")
app=importlib.util.module_from_spec(spec);spec.loader.exec_module(app)


def main(receipt=None):
    before,after,_,_,request,template=app.scope()
    sections={
        "__MODE__":template[template.index("local function mode()"):template.index("local function sha(source)")],
        "__STABLE__":template[template.index("local function stable(value)"):template.index("local function segments(n)")],
        "__IDENTITY__":template[template.index("local function targetIdentity()"):template.index("mode();targetIdentity()")],
        "__GUARD__":template[template.index("local function guard(fullCensus,changed)"):template.index("guard(true,false)\n")],
        "__ANCHORS__":template[template.index("local replacements={"):template.index("local function transform(current)")],
        "__PARSER__":template[template.index("-- Native parser port only:"):template.index("SES:UpdateSourceAsync(target,function(current)")],
    }
    program=r'''
local BEFORE=__BEFORE__
local AFTER=__AFTER__
local beforeSHA=__BEFORESHA__
local afterSHA=__AFTERSHA__
local checks=0
local function check(v,why)checks+=1;assert(v,why)end
local function clone(v)
 if type(v)~="table" then return v end local t={} for k,value in v do t[k]=clone(value) end return t
end
local function encode(v)
 if type(v)~="table" then return type(v)..":"..tostring(v) end
 local keys={} for k in v do keys[#keys+1]=k end table.sort(keys,function(a,b)return tostring(a)<tostring(b)end)
 local t={} for _,k in keys do t[#t+1]=encode(k).."="..encode(v[k]) end return "{"..table.concat(t,",").."}"
end
local cases={"success","constructorFailure","emptySource","emptyEditor","callbackCurrent","callbackSource","callbackEditor",
 "callbackParent","callbackName","callbackClass","callbackChildren","requireFailure","requireNonfunction",
 "originalSource","originalEditor","originalProperties","originalClass","originalIdentity","originalParent","originalAttributes","originalTags",
 "foreignLeaseBeforeClaim","foreignLeaseDuringStage","foreignProbeSourceAfterRequire","foreignProbeEditorAfterRequire","foreignProbeParentAfterRequire",
 "foreignProbeNameAfterRequire","foreignProbeClassAfterRequire","foreignProbeChildrenAfterRequire","destroyFailure","originalChangeDuringDestroy"}
local function run(kind)
 local running=false
 local H={JSONEncode=function(_,v)return if type(v)=="table" then v else encode(v) end}
 local RS={IsRunning=function()return running end}
 local game={PlaceId=131311258779917,GameId=10559217407}
 local DateTime={now=function()return {ToIsoDate=function()return "controlled timestamp" end}end}
 local shared={} local KEY="MongoTVExitLiteralCompileLeaseV1" local foreignLease={foreign=true}
 if kind=="foreignLeaseBeforeClaim" then shared[KEY]=foreignLease end
 local request={operation="compile",beforeSHA256=beforeSHA,afterSHA256=afterSHA,expectedTargetSHA256=beforeSHA,nativeScriptCount=213,
  targetProperties={Enabled=true,Disabled=false,RunContext="Enum.RunContext.Legacy",Archivable=true,LinkedSource=""},targetAttributes={},targetTags={},
  compileSources={before=BEFORE,candidate=AFTER}}
 local function sha(body)
  if body==BEFORE then return beforeSHA elseif body==AFTER then return afterSHA end
  if body=="return function()\n"..BEFORE.."\nend\n" then return "factory-before" end
  if body=="return function()\n"..AFTER.."\nend\n" then return "factory-candidate" end
  local i=body:match("^fixtureSource(%d+)$") return if i then "fixtureHash"..i else "unknown bytes"
 end
 local nodes,originals={},{}
 for i=1,213 do
  local targetCase=i==1 local n={Source=targetCase and BEFORE or "fixtureSource"..i};n.editor=n.Source
  n.meta={studioPath=targetCase and "StarterPlayer.StarterPlayerScripts.Round Exit Client" or "ServerScriptService.fixture"..i,
   segments=targetCase and {"StarterPlayer","StarterPlayerScripts","Round Exit Client"} or {"ServerScriptService","fixture"..i},
   instanceId=targetCase and "1_31096" or "fixture"..i,parentId=targetCase and "1_410029" or "fixtureParent",
   className=targetCase and "LocalScript" or "ModuleScript",properties=targetCase and clone(request.targetProperties) or {Archivable=true,LinkedSource=""},attributes={},tags={}}
  function n:IsA(class)return class=="LuaSourceContainer" end
  originals[n]={sha256=sha(n.Source)} for key,value in n.meta do originals[n][key]=clone(value) end
  nodes[#nodes+1]=n
 end
 local target=nodes[1] local fromHash=beforeSHA local toHash=beforeSHA
 function game:GetDescendants()return nodes end
 local function metadata(n)return clone(n.meta)end
 local owned,staged,required,destroyed,bodiesRun={},0,0,0,0
 local Instance={}
 function Instance.new(class)
  check(class=="ModuleScript","actual port creates only ModuleScript")
  if kind=="constructorFailure" then error("controlled constructor failure",0) end
  local p={ClassName=class,Name=class,Source="",editor="",Parent=nil,children={},alive=true}
  if #owned==0 then
   if kind=="emptySource" then p.Source="foreign empty-source edit";p.editor=p.Source
   elseif kind=="emptyEditor" then p.editor="foreign empty-editor edit" end
  end
  function p:GetChildren()return self.children end
  function p:IsDescendantOf()return self.Parent~=nil end
  function p:Destroy()
   if kind=="destroyFailure" then error("controlled destroy failure",0) end
   self.alive=false;destroyed+=1
   if kind=="originalChangeDuringDestroy" then nodes[2].Source="foreign destroy-time source";nodes[2].editor=nodes[2].Source end
  end
  owned[#owned+1]=p
  return p
 end
 local SES={GetEditorSource=function(_,n)return n.editor end}
 function SES:UpdateSourceAsync(p,callback)
  if #owned==1 then
   if kind=="callbackSource" then p.Source="foreign callback-source edit";p.editor=p.Source
   elseif kind=="callbackEditor" then p.editor="foreign callback-editor edit"
   elseif kind=="callbackParent" then p.Parent={foreign=true}
   elseif kind=="callbackName" then p.Name="foreign name"
   elseif kind=="callbackClass" then p.ClassName="Script"
   elseif kind=="callbackChildren" then p.children={{foreign=true}}
   elseif kind=="originalSource" then nodes[2].Source="foreign original source";nodes[2].editor=nodes[2].Source
   elseif kind=="originalEditor" then nodes[2].editor="foreign original editor"
   elseif kind=="originalProperties" then nodes[2].meta.properties.Archivable=false
   elseif kind=="originalClass" then nodes[2].meta.className="Script"
   elseif kind=="originalIdentity" then nodes[2].meta.instanceId="foreign original id"
   elseif kind=="originalParent" then nodes[2].meta.parentId="foreign original parent"
   elseif kind=="originalAttributes" then nodes[2].meta.attributes.foreign=true
   elseif kind=="originalTags" then nodes[2].meta.tags={"foreign tag"}
   elseif kind=="foreignLeaseDuringStage" then shared[KEY]=foreignLease end
  end
  local current=if kind=="callbackCurrent" then "foreign callback current" else p.Source
  local value=callback(current);p.Source=value;p.editor=value;staged+=1
 end
 local function require(p)
  required+=1
  if kind=="requireFailure" then error("controlled native parser failure",0) end
  if kind=="requireNonfunction" then return true end
  if #owned==1 then
   if kind=="foreignProbeSourceAfterRequire" then p.Source="foreign after-require source";p.editor=p.Source
   elseif kind=="foreignProbeEditorAfterRequire" then p.editor="foreign after-require editor"
   elseif kind=="foreignProbeParentAfterRequire" then p.Parent={foreign=true}
   elseif kind=="foreignProbeNameAfterRequire" then p.Name="foreign after-require name"
   elseif kind=="foreignProbeClassAfterRequire" then p.ClassName="Script"
   elseif kind=="foreignProbeChildrenAfterRequire" then p.children={{foreign=true}} end
  end
  return function()bodiesRun+=1;error("client body must never execute",0)end
 end
 __MODE__
 __STABLE__
 __IDENTITY__
 __GUARD__
 __ANCHORS__
 guard(true,false)
 local ok,result=pcall(function()
  __PARSER__
 end)
 check(bodiesRun==0,"actual parser never executes client bodies "..kind)
 check(#nodes==213,"actual original census count preserved "..kind)
 if kind=="foreignLeaseBeforeClaim" then
  check(not ok,"late lease compare must reject foreign lease")
  check(#owned==0 and destroyed==0,"no parser objects created before failed claim")
  check(shared[KEY]==foreignLease,"failed claim preserves foreign lease")
  return
 end
 check(ok,"all owned/parser faults return completion/cleanup receipt "..kind..": "..tostring(result))
 check(result.pass==(kind=="success"),"actual port pass/fail truthful "..kind)
 check(result.probesCreated==#owned and result.probesDestroyed==destroyed and result.remainingProbes==#owned-destroyed,"actual owned object accounting "..kind)
 check(result.originalSourceCoverage==213 and result.originalSourceWrites==0 and result.clientBodiesExecuted==0 and result.modeSwitches==0,"truthful untouched original/parser scope "..kind)
 local originalFailure=kind:sub(1,8)=="original" or kind=="foreignLeaseDuringStage"
 check(result.originalsUnchanged==not originalFailure,"actual originals guard rejects every foreign original change "..kind)
 if kind=="foreignLeaseDuringStage" then
  check(not result.ownedLeaseReleased and shared[KEY]==foreignLease,"foreign replaced lease never cleared")
  check(destroyed==#owned,"own empty module cleaned after foreign lease replacement")
 else
  check(result.ownedLeaseReleased and shared[KEY]==nil,"exact owned lease released on success/failure "..kind)
 end
 local preserve=kind=="emptySource" or kind=="emptyEditor" or kind:sub(1,8)=="callback" and kind~="callbackCurrent" or kind:sub(1,12)=="foreignProbe" or kind=="destroyFailure"
 if preserve then
  check(result.remainingProbes>=1 and #result.cleanupErrors>=1,"foreign or unsuccessfully destroyed probe preserved with evidence "..kind)
 else
  check(result.remainingProbes==0 and #result.cleanupErrors==0,"all exclusively owned probes cleaned "..kind)
 end
 if kind=="success" then
  check(staged==2 and required==2 and destroyed==2 and #result.compiles==2,"two exact whole-source factories parse and clean")
  check(result.compiles[1].sourceSHA256==beforeSHA and result.compiles[2].sourceSHA256==afterSHA,"exact paired Sources in parser result")
 end
end
for _,kind in cases do run(kind)end
print("PARSER_FAULT_CASES="..#cases.." CHECKS="..checks)
'''
    for key,value in {"__BEFORE__":app.lua_literal(before.decode()),"__AFTER__":app.lua_literal(after.decode()),
                      "__BEFORESHA__":app.lua_literal(app.sha(before)),"__AFTERSHA__":app.lua_literal(app.sha(after)),**sections}.items():
        assert program.count(key)==1,key
        program=program.replace(key,value)
    compiles=[]
    with tempfile.TemporaryDirectory(prefix="mongotv-exit-parser-faults-") as folder:
        path=Path(folder)/"actual-parser-faults.luau";path.write_bytes(program.encode())
        for opt in (0,1):
            run=subprocess.run([str(app.helpers.COMPILER),"--binary","-g0",f"-O{opt}",str(path)],capture_output=True,timeout=30)
            assert run.returncode==0,run.stderr.decode(errors="replace")
            compiles.append({"optimization":opt,"pass":True})
        run=subprocess.run([str(app.helpers.LUAU),str(path)],capture_output=True,text=True,timeout=30)
        assert run.returncode==0,run.stdout+run.stderr
    match=re.search(r"PARSER_FAULT_CASES=(\d+) CHECKS=(\d+)",run.stdout)
    proof={"pass":True,"cases":int(match[1]),"checks":int(match[2]),"compileChecks":compiles,"stdout":run.stdout,
           "templateSHA256":app.sha(template.encode()),"fixtureSHA256":app.sha(program.encode()),"toolSHA256":app.sha(Path(__file__).read_bytes()),
           "actualSectionHashes":{name:app.sha(body.encode()) for name,body in sections.items()},"nativeCalls":0,"productionWrites":0,"manifestWrites":0,
           "limits":"Actual original guards, lease compare/claim/release, empty ModuleScript staging callback, parser factory-type check, failure completion and owned cleanup code. Instance/SES/metadata/hash/require outcomes are controlled local boundaries. Not an actual native parser, editor identity, asset/gameplay/multiplayer/streaming certificate."}
    app.save(receipt or HERE/"parser-fault-tests-v1.json",app.encoded(proof))
    print(json.dumps({"pass":True,"cases":proof["cases"],"checks":proof["checks"],"nativeCalls":0}))


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument("--receipt",type=Path)
    main(parser.parse_args().receipt)
